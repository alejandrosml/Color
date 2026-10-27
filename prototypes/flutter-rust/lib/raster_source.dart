// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'native_diagnostics.dart';

const maxRasterBytes = 68 * 1024 * 1024;
const maxRasterDimension = 8192;
const maxRasterPixels = 16 * 1024 * 1024;
const maxRasterDecodedBytes = 64 * 1024 * 1024;
const maxIccBytes = 1024 * 1024;
const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
bool _operationInProgress = false;

/// Owns its image handle. Dispose once no renderer or exporter needs this handle;
/// asynchronous consumers must obtain image.clone() before ownership changes.
final class ImportedBackground {
  ImportedBackground._(
    Uint8List bytes,
    this.width,
    this.height,
    this._image,
    Map<String, int> timings,
  ) : pngBytes = bytes.asUnmodifiableView(),
      timingsMicroseconds = Map.unmodifiable(timings);

  final Uint8List pngBytes;
  final int width;
  final int height;
  final ui.Image _image;

  /// Local stage elapsed times, not a benchmark or a process memory bound.
  final Map<String, int> timingsMicroseconds;
  bool _disposed = false;

  ui.Image get image {
    if (_disposed) throw StateError('Cette image a été libérée.');
    return _image;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _image.dispose();
  }
}

/// Imports one static PNG/JPEG into a self-contained, sRGB PNG background.
/// Calls are serialized: a second concurrent operation is rejected, not queued.
Future<ImportedBackground> normaliseRaster(Uint8List input) async {
  _beginOperation();
  final total = Stopwatch()..start();
  final stage = Stopwatch()..start();
  final timings = <String, int>{};
  ui.Image? source;
  ui.Image? converted;
  ui.Image? rgba8;
  ui.Image? finalImage;
  ui.Picture? picture;
  ui.PictureRecorder? recorder;
  try {
    final prepared = await _prepareOffThread(input, _Preparation.source);
    timings['prevalidate'] = stage.elapsedMicroseconds;
    stage.reset();
    source = await _decode(prepared);
    timings['source_decode'] = stage.elapsedMicroseconds;
    stage.reset();
    final width = source.width;
    final height = source.height;
    recordNativeDiagnostics(
      'raster-source:${width}x$height:${source.colorSpace.name}',
    );
    recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(source, ui.Offset.zero, ui.Paint());
    picture = recorder.endRecording();
    // Keep real profile conversion before reading raw pixels: Skia snapshots
    // target sRGB; Impeller works in sRGB/extended sRGB. The snapshot's channel
    // depth is backend-dependent (e.g. F16 on macOS), not necessarily 8 bits.
    converted = await picture.toImage(width, height);
    if (converted.width != width || converted.height != height) {
      throw const FormatException(
        'Le moteur a réduit cette image. Son import est annulé.',
      );
    }
    recordNativeDiagnostics(
      'raster-rendered:${width}x$height:${converted.colorSpace.name}',
    );
    // Snapshot completion ends our need for the source and its display list.
    picture.dispose();
    picture = null;
    source.dispose();
    source = null;
    timings['render_srgb'] = stage.elapsedMicroseconds;
    stage.reset();
    rgba8 = await _quantizeRenderedSrgb8(converted);
    converted.dispose();
    converted = null;
    recordNativeDiagnostics(
      'raster-rgba8:${width}x$height:${rgba8.colorSpace.name}',
    );
    timings['quantize_srgb8'] = stage.elapsedMicroseconds;
    stage.reset();
    final encoded = await rgba8.toByteData(format: ui.ImageByteFormat.png);
    if (encoded == null || encoded.lengthInBytes > maxRasterBytes) {
      throw const FormatException(
        'Le PNG préparé dépasse la taille autorisée.',
      );
    }
    final encodedView = encoded.buffer.asUint8List(
      encoded.offsetInBytes,
      encoded.lengthInBytes,
    );
    recordNativeDiagnostics(
      'raster-png:${width}x$height:'
      'depth=${encodedView.length > 24 ? encodedView[24] : -1}:'
      'type=${encodedView.length > 25 ? encodedView[25] : -1}:'
      'bytes=${encodedView.length}',
    );
    rgba8.dispose();
    rgba8 = null;
    timings['encode_png'] = stage.elapsedMicroseconds;
    stage.reset();
    // ICC removal is legal only after profile conversion and explicit sRGB8
    // quantization. Never remove/relabel the profile of an undecoded source.
    final canonicalPrepared = await _prepareOffThread(
      encodedView,
      _Preparation.converted,
      width: width,
      height: height,
    );
    timings['canonical_prevalidate'] = stage.elapsedMicroseconds;
    stage.reset();
    finalImage = await _decode(canonicalPrepared);
    timings['canonical_decode'] = stage.elapsedMicroseconds;
    timings['total'] = total.elapsedMicroseconds;
    final result = ImportedBackground._(
      canonicalPrepared.bytes,
      width,
      height,
      finalImage,
      timings,
    );
    finalImage = null;
    return result;
  } finally {
    finalImage?.dispose();
    rgba8?.dispose();
    converted?.dispose();
    source?.dispose();
    picture?.dispose();
    if (recorder?.isRecording ?? false) recorder!.endRecording().dispose();
    _operationInProgress = false;
  }
}

// Quantize only a RENDERED sRGB/extended-sRGB image, never undecoded P3 pixels.
// rawRgba clamps extended values to 8-bit sRGB and uses premultiplied alpha.
// ImageDescriptor.raw(rgba8888) also expects premultiplied alpha and explicitly
// creates sRGB pixels; feeding rawStraightRgba here would corrupt transparency.
// The 64 MiB bound is per RGBA8 buffer, not total engine/process/GPU memory.
Future<ui.Image> _quantizeRenderedSrgb8(ui.Image rendered) async {
  final width = rendered.width;
  final height = rendered.height;
  _dimensions(width, height);
  final byteCount = width * height * 4;
  if (byteCount > maxRasterDecodedBytes ||
      (rendered.colorSpace != ui.ColorSpace.sRGB &&
          rendered.colorSpace != ui.ColorSpace.extendedSRGB)) {
    throw const FormatException(
      'Le moteur ne peut pas préparer les couleurs de cette image.',
    );
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    final rgba = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null || rgba.lengthInBytes != byteCount) {
      throw const FormatException(
        'Le moteur n’a pas préparé tous les pixels de cette image.',
      );
    }
    buffer = await ui.ImmutableBuffer.fromUint8List(
      rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
    );
    descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      rowBytes: width * 4,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    codec = await descriptor.instantiateCodec();
    if (codec.frameCount != 1) {
      throw const FormatException('Le moteur n’a pas préparé une image fixe.');
    }
    image = (await codec.getNextFrame()).image;
    if (image.width != width ||
        image.height != height ||
        image.colorSpace != ui.ColorSpace.sRGB) {
      throw const FormatException(
        'Le moteur n’a pas conservé les dimensions et couleurs de cette image.',
      );
    }
    final result = image;
    image = null;
    return result;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Reopens an already-normalized v3 background. No color conversion or encoding.
Future<ImportedBackground> decodeCanonicalBackground(Uint8List input) =>
    _decodePreparedCanonical(
      () => _prepareOffThread(input, _Preparation.canonical),
    );

/// Consumes PNG bytes already captured by the project-loading worker. Validation
/// and pixel decoding are identical; no TransferableTypedData copy starts here.
Future<ImportedBackground> decodeTransferredCanonicalBackground(
  TransferableTypedData input,
) => _decodePreparedCanonical(
  () => _prepareTransferred(input, _Preparation.canonical),
);

Future<ImportedBackground> _decodePreparedCanonical(
  Future<_Prepared> Function() prepare,
) async {
  _beginOperation();
  final timer = Stopwatch()..start();
  ui.Image? image;
  try {
    final prepared = await prepare();
    final prevalidate = timer.elapsedMicroseconds;
    image = await _decode(prepared);
    final result = ImportedBackground._(
      prepared.bytes,
      image.width,
      image.height,
      image,
      {
        'prevalidate': prevalidate,
        'canonical_decode': timer.elapsedMicroseconds - prevalidate,
        'total': timer.elapsedMicroseconds,
      },
    );
    image = null;
    return result;
  } finally {
    image?.dispose();
    _operationInProgress = false;
  }
}

void _beginOperation() {
  if (_operationInProgress) {
    throw StateError('Une image est déjà en préparation.');
  }
  _operationInProgress = true;
}

enum _Preparation { source, canonical, converted }

Future<_Prepared> _prepareOffThread(
  Uint8List input,
  _Preparation operation, {
  int width = 0,
  int height = 0,
}) async {
  if (input.isEmpty || input.length > maxRasterBytes) {
    throw const FormatException(
      'La taille de ce fichier image n’est pas autorisée.',
    );
  }
  // This bounded copy is synchronous and captures the caller's input before the
  // first await. Transfer and worker parsing never retain a mutable caller view.
  return _prepareTransferred(
    TransferableTypedData.fromList([input]),
    operation,
    width: width,
    height: height,
  );
}

Future<_Prepared> _prepareTransferred(
  TransferableTypedData input,
  _Preparation operation, {
  int width = 0,
  int height = 0,
}) async {
  final task = _PreparationTask(input, operation, width, height);
  // A bound top-level-class method captures only transferable bytes and scalar
  // values, never ui.Image, an FFI handle, or the parent async stack's locals.
  final result = await Isolate.run(
    task.run,
    debugName: 'Color image validation',
  );
  return _Prepared(
    result.bytes.materialize().asUint8List(),
    result.width,
    result.height,
    allowOrientation: result.allowOrientation,
  );
}

final class _PreparationTask {
  const _PreparationTask(this.bytes, this.operation, this.width, this.height);
  final TransferableTypedData bytes;
  final _Preparation operation;
  final int width;
  final int height;

  _TransferredPrepared run() {
    final owned = bytes.materialize().asUint8List();
    if (owned.isEmpty || owned.length > maxRasterBytes) {
      throw const FormatException(
        'La taille de ce fichier image n’est pas autorisée.',
      );
    }
    final prepared = switch (operation) {
      _Preparation.source => _prepareSource(owned),
      _Preparation.canonical => _preparePng(owned, canonical: true),
      _Preparation.converted => _preparePng(
        _canonicaliseConvertedPng(owned, width, height),
        canonical: true,
      ),
    };
    return _TransferredPrepared(
      TransferableTypedData.fromList([prepared.bytes]),
      prepared.width,
      prepared.height,
      prepared.allowOrientation,
    );
  }
}

final class _TransferredPrepared {
  const _TransferredPrepared(
    this.bytes,
    this.width,
    this.height,
    this.allowOrientation,
  );
  final TransferableTypedData bytes;
  final int width;
  final int height;
  final bool allowOrientation;
}

final class _Prepared {
  const _Prepared(
    this.bytes,
    this.width,
    this.height, {
    this.allowOrientation = false,
  });
  final Uint8List bytes;
  final int width;
  final int height;
  final bool allowOrientation;
}

void _dimensions(int width, int height) {
  if (width < 1 ||
      height < 1 ||
      width > maxRasterDimension ||
      height > maxRasterDimension ||
      width * height > maxRasterPixels) {
    throw const FormatException(
      'Cette image dépasse les dimensions autorisées.',
    );
  }
}

Future<ui.Image> _decode(_Prepared source) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(source.bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    _dimensions(descriptor.width, descriptor.height);
    if (descriptor.bytesPerPixel < 1 ||
        descriptor.width * descriptor.height * descriptor.bytesPerPixel >
            maxRasterDecodedBytes) {
      throw const FormatException(
        'Cette image demande trop de mémoire pour être décodée.',
      );
    }
    final exact =
        descriptor.width == source.width && descriptor.height == source.height;
    final turned =
        source.allowOrientation &&
        descriptor.width == source.height &&
        descriptor.height == source.width;
    if (!exact && !turned) {
      throw const FormatException(
        'Les dimensions de l’image sont incohérentes.',
      );
    }
    codec = await descriptor.instantiateCodec();
    if (codec.frameCount != 1) {
      throw const FormatException('Choisis une image fixe, sans animation.');
    }
    image = (await codec.getNextFrame()).image;
    if (image.width != descriptor.width || image.height != descriptor.height) {
      throw const FormatException(
        'Les dimensions du décodage sont incohérentes.',
      );
    }
    final result = image;
    image = null;
    return result;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

_Prepared _prepareSource(Uint8List bytes) {
  if (_hasPngSignature(bytes)) return _preparePng(bytes);
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    return _prepareJpeg(bytes);
  }
  throw const FormatException('Choisis une image PNG ou JPEG.');
}

bool _hasPngSignature(Uint8List bytes) {
  if (bytes.length < 8) return false;
  for (var index = 0; index < 8; index++) {
    if (bytes[index] != _pngSignature[index]) return false;
  }
  return true;
}

final class _Chunk {
  const _Chunk(this.type, this.data, this.whole);
  final String type;
  final Uint8List data;
  final Uint8List whole;
}

List<_Chunk> _pngChunks(Uint8List bytes) {
  if (!_hasPngSignature(bytes)) {
    throw const FormatException('Signature PNG invalide.');
  }
  if (bytes.length < 33 ||
      _u32(bytes, 8) != 13 ||
      _ascii(bytes, 12, 4) != 'IHDR') {
    throw const FormatException('L’en-tête PNG est incomplet.');
  }
  // Reject a giant declared image before traversing even its compressed payload.
  _dimensions(_u32(bytes, 16), _u32(bytes, 20));
  final result = <_Chunk>[];
  var cursor = 8;
  var ended = false;
  while (cursor < bytes.length) {
    if (bytes.length - cursor < 12) {
      throw const FormatException('Le PNG est incomplet.');
    }
    final length = _u32(bytes, cursor);
    if (length > bytes.length - cursor - 12) {
      throw const FormatException('La longueur d’un bloc PNG est invalide.');
    }
    final type = String.fromCharCodes(bytes.sublist(cursor + 4, cursor + 8));
    if (!RegExp(r'^[A-Za-z]{2}[A-Z][A-Za-z]$').hasMatch(type)) {
      throw const FormatException('Le type d’un bloc PNG est invalide.');
    }
    final end = cursor + 12 + length;
    if (_crc(bytes, cursor + 4, end - 4) != _u32(bytes, end - 4)) {
      throw const FormatException('Le contrôle d’intégrité du PNG a échoué.');
    }
    result.add(
      _Chunk(
        type,
        Uint8List.sublistView(bytes, cursor + 8, end - 4),
        Uint8List.sublistView(bytes, cursor, end),
      ),
    );
    // Prevent a compact file made of millions of tiny ancillary chunks from
    // creating an unbounded metadata object graph before it is sanitized.
    if (result.length > 65536) {
      throw const FormatException('Le PNG contient trop de blocs.');
    }
    cursor = end;
    if (type == 'IEND') {
      if (length != 0 || cursor != bytes.length) {
        throw const FormatException('La fin du PNG est invalide.');
      }
      ended = true;
      break;
    }
  }
  if (!ended ||
      result.isEmpty ||
      result.first.type != 'IHDR' ||
      result.first.data.length != 13) {
    throw const FormatException('La structure du PNG est incomplète.');
  }
  return result;
}

const _canonicalChunks = {
  'IHDR',
  'IDAT',
  'IEND',
  'sRGB',
  'gAMA',
  'cHRM',
  'pHYs',
};
const _visualChunks = {
  'IHDR',
  'PLTE',
  'IDAT',
  'IEND',
  'tRNS',
  'sRGB',
  'gAMA',
  'cHRM',
  'pHYs',
  'sBIT',
  'iCCP',
  'eXIf',
};

_Prepared _preparePng(Uint8List bytes, {bool canonical = false}) {
  final chunks = _pngChunks(bytes);
  final header = chunks.first.data;
  final width = _u32(header, 0);
  final height = _u32(header, 4);
  _dimensions(width, height);
  final depth = header[8];
  final colorType = header[9];
  const depths = {
    0: {1, 2, 4, 8, 16},
    2: {8, 16},
    3: {1, 2, 4, 8},
    4: {8, 16},
    6: {8, 16},
  };
  if (!(depths[colorType]?.contains(depth) ?? false) ||
      header[10] != 0 ||
      header[11] != 0 ||
      header[12] > 1) {
    throw const FormatException(
      'Le codage de ce PNG n’est pas pris en charge.',
    );
  }
  if (canonical &&
      (depth != 8 || (colorType != 2 && colorType != 6) || header[12] != 0)) {
    throw const FormatException(
      'Le fond du projet n’est pas un PNG normalisé.',
    );
  }
  final seen = <String>{};
  var idat = false;
  var idatEnded = false;
  var paletteEntries = 0;
  var visualMetadata = 0;
  var sanitized = false;
  final kept = <Uint8List>[Uint8List.fromList(_pngSignature)];
  for (final chunk in chunks) {
    final type = chunk.type;
    final data = chunk.data;
    if (type == 'acTL' || type == 'fcTL' || type == 'fdAT') {
      throw const FormatException('Choisis une image fixe, sans animation.');
    }
    if (canonical && !_canonicalChunks.contains(type)) {
      throw const FormatException(
        'Le fond du projet contient des données non normalisées.',
      );
    }
    if (type != 'IDAT' && !seen.add(type) && _visualChunks.contains(type)) {
      throw const FormatException('Le PNG contient un bloc visuel en double.');
    }
    if (type == 'IDAT') {
      if (idatEnded || (colorType == 3 && paletteEntries == 0)) {
        throw const FormatException('L’ordre des blocs PNG est invalide.');
      }
      idat = true;
    } else if (idat) {
      idatEnded = true;
      if (type != 'IEND' && _visualChunks.contains(type)) {
        throw const FormatException(
          'Les métadonnées visuelles doivent précéder les pixels.',
        );
      }
    }
    if (type == 'PLTE') {
      if (colorType == 0 ||
          colorType == 4 ||
          data.isEmpty ||
          data.length % 3 != 0 ||
          data.length > 768) {
        throw const FormatException('La palette du PNG est invalide.');
      }
      paletteEntries = data.length ~/ 3;
      if (colorType == 3 && paletteEntries > 1 << depth) {
        throw const FormatException('La palette du PNG est trop grande.');
      }
    } else if (type == 'tRNS') {
      if ((colorType == 0 && data.length != 2) ||
          (colorType == 2 && data.length != 6) ||
          (colorType == 3 &&
              (paletteEntries == 0 ||
                  data.isEmpty ||
                  data.length > paletteEntries)) ||
          colorType == 4 ||
          colorType == 6) {
        throw const FormatException('La transparence du PNG est invalide.');
      }
    } else if (type == 'sRGB') {
      if (data.length != 1 || data[0] > 3) {
        throw const FormatException('Le repère sRGB est invalide.');
      }
    } else if (type == 'gAMA') {
      if (data.length != 4 || _u32(data, 0) == 0) {
        throw const FormatException('Le gamma du PNG est invalide.');
      }
    } else if (type == 'cHRM') {
      if (data.length != 32) {
        throw const FormatException('La chromaticité du PNG est invalide.');
      }
    } else if (type == 'pHYs') {
      if (data.length != 9 || data[8] > 1) {
        throw const FormatException('La résolution du PNG est invalide.');
      }
    } else if (type == 'iCCP') {
      _validatePngIcc(data, gray: colorType == 0 || colorType == 4);
    } else if (type == 'cICP' || type == 'mDCV' || type == 'cLLI') {
      throw const FormatException(
        'Les images HDR ne sont pas encore prises en charge.',
      );
    }
    if (_visualChunks.contains(type)) {
      if (type != 'IHDR' && type != 'IDAT' && type != 'IEND') {
        visualMetadata += data.length;
        if (visualMetadata > 2 * maxIccBytes) {
          throw const FormatException(
            'Les métadonnées de l’image sont trop volumineuses.',
          );
        }
      }
      kept.add(chunk.whole);
    } else {
      if (type.codeUnitAt(0) & 32 == 0) {
        throw const FormatException(
          'Ce PNG contient un bloc essentiel inconnu.',
        );
      }
      sanitized = true; // Includes all unused Tux Paint and text chunks.
    }
  }
  if (!idat || (seen.contains('sRGB') && seen.contains('iCCP'))) {
    throw const FormatException('Le contenu visuel du PNG est incohérent.');
  }
  return _Prepared(
    sanitized ? _join(kept) : bytes,
    width,
    height,
    allowOrientation: !canonical && seen.contains('eXIf'),
  );
}

void _validatePngIcc(Uint8List data, {required bool gray}) {
  final nul = data.indexOf(0);
  if (nul < 1 || nul > 79 || nul + 2 >= data.length || data[nul + 1] != 0) {
    throw const FormatException('Le profil couleur PNG est invalide.');
  }
  final compressed = Uint8List.sublistView(data, nul + 2);
  if (compressed.length > maxIccBytes) {
    throw const FormatException('Le profil couleur est trop volumineux.');
  }
  if (compressed.length < 6 ||
      (compressed[0] & 15) != 8 ||
      compressed[0] >> 4 > 7 ||
      ((compressed[0] << 8) | compressed[1]) % 31 != 0 ||
      (compressed[1] & 32) != 0) {
    throw const FormatException(
      'L’en-tête compressé du profil couleur est invalide.',
    );
  }
  final sink = _BoundedProfileSink();
  final decoder = ZLibDecoder().startChunkedConversion(sink);
  for (var start = 0; start < compressed.length; start += 4096) {
    final end = (start + 4096).clamp(0, compressed.length);
    decoder.addSlice(compressed, start, end, false);
  }
  decoder.close();
  // Dart's streaming decoder can return complete profile bytes even when the
  // zlib trailer is truncated. Explicitly require its Adler-32 checksum.
  if (_u32(compressed, compressed.length - 4) != sink.adler32) {
    throw const FormatException(
      'Le contrôle du profil couleur compressé a échoué.',
    );
  }
  _validateIcc(sink.bytes, gray: gray);
}

final class _BoundedProfileSink extends ByteConversionSinkBase {
  final _builder = BytesBuilder(copy: false);
  int _length = 0;
  int _sum1 = 1;
  int _sum2 = 0;
  Uint8List get bytes => _builder.takeBytes();
  int get adler32 => (_sum2 << 16) | _sum1;

  @override
  void add(List<int> chunk) {
    if (chunk.length > maxIccBytes - _length) {
      throw const FormatException(
        'Le profil couleur décompressé dépasse la limite autorisée.',
      );
    }
    _length += chunk.length;
    for (var start = 0; start < chunk.length; start += 5552) {
      final end = (start + 5552).clamp(0, chunk.length);
      for (var index = start; index < end; index++) {
        _sum1 += chunk[index];
        _sum2 += _sum1;
      }
      _sum1 %= 65521;
      _sum2 %= 65521;
    }
    _builder.add(chunk);
  }

  @override
  void close() {}
}

void _validateIcc(Uint8List data, {required bool gray}) {
  if (data.length < 132 ||
      data.length > maxIccBytes ||
      _u32(data, 0) != data.length ||
      _ascii(data, 36, 4) != 'acsp' ||
      (data[8] != 2 && data[8] != 4) ||
      _ascii(data, 16, 4) != (gray ? 'GRAY' : 'RGB ') ||
      !{'XYZ ', 'Lab '}.contains(_ascii(data, 20, 4))) {
    throw const FormatException(
      'Le profil couleur n’est pas compatible avec cette image.',
    );
  }
  final count = _u32(data, 128);
  if (count > 4096 || count > (data.length - 132) ~/ 12) {
    throw const FormatException('La table du profil couleur est invalide.');
  }
  final tags = <String>{};
  for (var index = 0; index < count; index++) {
    final cursor = 132 + 12 * index;
    final tag = _ascii(data, cursor, 4);
    final offset = _u32(data, cursor + 4);
    final size = _u32(data, cursor + 8);
    if (!tags.add(tag) ||
        offset < 132 + 12 * count ||
        offset % 4 != 0 ||
        size < 8 ||
        offset > data.length ||
        size > data.length - offset) {
      throw const FormatException('Une entrée du profil couleur est invalide.');
    }
  }
}

_Prepared _prepareJpeg(Uint8List bytes) {
  var cursor = 2;
  var width = 0;
  var height = 0;
  var components = 0;
  var scans = 0;
  var markers = 0;
  var ended = false;
  var metadata = 0;
  var iccParts = 0;
  var iccBytes = 0;
  final icc = <int, Uint8List>{};
  final kept = <Uint8List>[Uint8List.sublistView(bytes, 0, 2)];
  while (cursor < bytes.length) {
    if (++markers > 65536) {
      throw const FormatException('Le JPEG contient trop de marqueurs.');
    }
    final markerStart = cursor;
    if (bytes[cursor++] != 0xff) {
      throw const FormatException('La structure JPEG est invalide.');
    }
    while (cursor < bytes.length && bytes[cursor] == 0xff) {
      cursor++;
    }
    if (cursor >= bytes.length) {
      throw const FormatException('Le JPEG est incomplet.');
    }
    final marker = bytes[cursor++];
    if (marker == 0xd9) {
      if (cursor != bytes.length || scans == 0) {
        throw const FormatException('La fin du JPEG est invalide.');
      }
      kept.add(Uint8List.sublistView(bytes, markerStart, cursor));
      ended = true;
      break;
    }
    if (marker == 0 ||
        marker == 0xd8 ||
        marker == 1 ||
        (marker >= 0xd0 && marker <= 0xd7) ||
        bytes.length - cursor < 2) {
      throw const FormatException('Un marqueur JPEG est invalide.');
    }
    final length = _u16(bytes, cursor);
    if (length < 2 || length > bytes.length - cursor) {
      throw const FormatException('Le JPEG est incomplet.');
    }
    final data = Uint8List.sublistView(bytes, cursor + 2, cursor + length);
    cursor += length;
    var retain = true;
    final isSof =
        marker >= 0xc0 &&
        marker <= 0xcf &&
        !{0xc4, 0xc8, 0xcc}.contains(marker);
    if (isSof) {
      if (!{0xc0, 0xc1, 0xc2}.contains(marker) ||
          width != 0 ||
          data.length < 6 ||
          data[0] != 8) {
        throw const FormatException(
          'Ce type de JPEG n’est pas pris en charge.',
        );
      }
      height = _u16(data, 1);
      width = _u16(data, 3);
      components = data[5];
      if ((components != 1 && components != 3) ||
          data.length != 6 + 3 * components) {
        throw const FormatException(
          'Choisis un JPEG en couleur RGB ou en niveaux de gris.',
        );
      }
      _dimensions(width, height);
    } else if (marker >= 0xe0 && marker <= 0xef || marker == 0xfe) {
      metadata += data.length;
      if (metadata > 2 * maxIccBytes) {
        throw const FormatException(
          'Les métadonnées JPEG sont trop volumineuses.',
        );
      }
      final isIcc =
          marker == 0xe2 &&
          data.length >= 12 &&
          _ascii(data, 0, 12) == 'ICC_PROFILE\x00';
      if (isIcc) {
        if (scans != 0 || data.length < 15) {
          throw const FormatException('Le profil JPEG est incomplet.');
        }
        final index = data[12];
        final count = data[13];
        if (index < 1 ||
            count < 1 ||
            index > count ||
            (iccParts != 0 && count != iccParts) ||
            icc.containsKey(index)) {
          throw const FormatException(
            'Les fragments du profil JPEG sont incohérents.',
          );
        }
        iccParts = count;
        final part = Uint8List.sublistView(data, 14);
        iccBytes += part.length;
        if (iccBytes > maxIccBytes) {
          throw const FormatException('Le profil couleur est trop volumineux.');
        }
        icc[index] = part;
      }
      // Keep EXIF, ICC, JFIF and Adobe interpretation. Other metadata is not
      // needed to decode the flattened appearance and is never retained.
      retain =
          marker == 0xe0 ||
          marker == 0xee ||
          isIcc ||
          (marker == 0xe1 &&
              data.length >= 6 &&
              _ascii(data, 0, 6) == 'Exif\x00\x00');
    }
    if (retain) kept.add(Uint8List.sublistView(bytes, markerStart, cursor));
    if (marker == 0xda) {
      if (width == 0 ||
          data.isEmpty ||
          data[0] < 1 ||
          data[0] > components ||
          data.length != 4 + 2 * data[0]) {
        throw const FormatException('Le balayage JPEG est invalide.');
      }
      if (++scans > 1024) {
        throw const FormatException('Le JPEG contient trop de balayages.');
      }
      final entropyStart = cursor;
      var foundMarker = false;
      while (cursor < bytes.length) {
        if (bytes[cursor] != 0xff) {
          cursor++;
          continue;
        }
        final start = cursor++;
        while (cursor < bytes.length && bytes[cursor] == 0xff) {
          cursor++;
        }
        if (cursor >= bytes.length) {
          throw const FormatException('Le JPEG est incomplet.');
        }
        final next = bytes[cursor];
        if (next == 0 || (next >= 0xd0 && next <= 0xd7)) {
          cursor++;
          continue;
        }
        cursor = start;
        foundMarker = true;
        break;
      }
      if (!foundMarker) throw const FormatException('Le JPEG est incomplet.');
      kept.add(Uint8List.sublistView(bytes, entropyStart, cursor));
    }
  }
  if (!ended || width == 0 || icc.length != iccParts) {
    throw const FormatException('Le JPEG est incomplet.');
  }
  if (iccParts > 0) {
    final profile = _join([
      for (var index = 1; index <= iccParts; index++) icc[index]!,
    ]);
    _validateIcc(profile, gray: components == 1);
  }
  return _Prepared(_join(kept), width, height, allowOrientation: true);
}

Uint8List _canonicaliseConvertedPng(Uint8List bytes, int width, int height) {
  final chunks = _pngChunks(bytes);
  final header = chunks.first.data;
  if (_u32(header, 0) != width ||
      _u32(header, 4) != height ||
      header[8] != 8 ||
      (header[9] != 2 && header[9] != 6) ||
      header[10] != 0 ||
      header[11] != 0 ||
      header[12] != 0) {
    throw const FormatException(
      'Le moteur n’a pas produit un fond PNG normalisé.',
    );
  }
  return _join([
    Uint8List.fromList(_pngSignature),
    chunks.first.whole,
    _makeChunk('sRGB', Uint8List.fromList([0])),
    for (final chunk in chunks)
      if (chunk.type == 'IDAT' || chunk.type == 'IEND') chunk.whole,
  ]);
}

Uint8List _makeChunk(String type, Uint8List data) {
  final bytes = Uint8List(12 + data.length);
  ByteData.sublistView(bytes).setUint32(0, data.length);
  bytes.setRange(4, 8, type.codeUnits);
  bytes.setRange(8, 8 + data.length, data);
  ByteData.sublistView(bytes)
      .setUint32(bytes.length - 4, _crc(bytes, 4, bytes.length - 4));
  return bytes;
}

Uint8List _join(List<Uint8List> chunks) {
  final builder = BytesBuilder(copy: false);
  for (final chunk in chunks) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

int _u32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset);
int _u16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint16(offset);
String _ascii(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(Uint8List.sublistView(bytes, offset, offset + length));
final _crcTable = Uint32List.fromList(
  List.generate(256, (value) {
    var crc = value;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
    return crc;
  }),
);
int _crc(Uint8List bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var index = start; index < end; index++) {
    crc = _crcTable[(crc ^ bytes[index]) & 255] ^ (crc >>> 8);
  }
  return crc ^ 0xffffffff;
}
