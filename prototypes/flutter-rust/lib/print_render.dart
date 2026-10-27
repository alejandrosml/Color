// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'document_renderer.dart';
import 'rust_document.dart';

/// The image of a drawing as it goes to the printer: opaque pixels, four
/// bytes each (red, green, blue, 255), rows from the top.
class PrintImage {
  PrintImage(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width;
  final int height;
}

// A sheet is printed at twice its size in pixels, which is sharp on a page,
// as long as the image stays within these bounds: 8 million pixels are
// 32 MiB to hand to the system.
const int maxPrintPixels = 8 * 1024 * 1024;
const int maxPrintDimension = 4096;

/// The size in pixels of the image printed for a sheet of [width] by
/// [height] units: twice the sheet, or as large as the bounds allow.
({int width, int height, double scale}) printImageSize(int width, int height) {
  if (width < 1 || height < 1) {
    throw ArgumentError('Cette feuille n’a pas de taille.');
  }
  final scale = [
    2.0,
    math.sqrt(maxPrintPixels / (width * height)),
    maxPrintDimension / math.max(width, height),
  ].reduce(math.min);
  return (
    width: math.max(1, (width * scale).floor()),
    height: math.max(1, (height * scale).floor()),
    scale: scale,
  );
}

/// Renders the committed drawing on its opaque paper, as an export does, at
/// the size that [printImageSize] gives. Every path is copied into a local
/// snapshot before the first await: neither the live list nor a Rust handle
/// is read while the engine works.
Future<PrintImage> renderDocumentForPrint(
  List<StrokeData> elements, {
  required int width,
  required int height,
  Image? background,
  int paperRgb = whitePaper,
}) async {
  if (elements.length > 10000) {
    throw ArgumentError('Le dessin contient trop d’éléments.');
  }
  if (paperRgb < 0 || paperRgb > 0xffffff) {
    throw ArgumentError('La couleur de la feuille est invalide.');
  }
  if (background != null &&
      (background.width != width || background.height != height)) {
    throw ArgumentError('Le fond ne correspond pas aux dimensions du dessin.');
  }
  final size = printImageSize(width, height);
  final snapshot = List<RenderedElement>.unmodifiable(
    elements.map(RenderedElement.new),
  );
  final recorder = PictureRecorder();
  Picture? picture;
  Image? image;
  Image? backgroundSnapshot;
  try {
    // A cheap handle clone keeps the image alive if the studio adopts
    // another document while the engine is working.
    backgroundSnapshot = background?.clone();
    final canvas = Canvas(recorder);
    // The whole image is paper first: a last row or column of pixels that
    // the scaled sheet only partly covers is never left transparent.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width.toDouble(), size.height.toDouble()),
      Paint()..color = Color(0xff000000 | paperRgb),
    );
    canvas.scale(size.width / width, size.height / height);
    final paper = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    canvas.clipRect(paper, doAntiAlias: false);
    if (backgroundSnapshot != null) {
      canvas.drawImageRect(
        backgroundSnapshot,
        paper,
        paper,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    for (final element in snapshot) {
      element.paint(canvas);
    }
    picture = recorder.endRecording();
    image = await picture.toImage(size.width, size.height);
    if (image.width != size.width || image.height != size.height) {
      throw StateError('Le moteur a réduit l’image. L’impression est annulée.');
    }
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (bytes == null || bytes.lengthInBytes != size.width * size.height * 4) {
      throw StateError('Le moteur n’a pas pu préparer l’image à imprimer.');
    }
    // The bytes that the engine hands over are this function's own: they are
    // not copied again, the largest image being 32 MiB.
    final rgba = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    // The paper is opaque everywhere: say so in every pixel, whatever the
    // engine rounded at an edge.
    for (var index = 3; index < rgba.length; index += 4) {
      rgba[index] = 255;
    }
    return PrintImage(rgba, size.width, size.height);
  } finally {
    image?.dispose();
    backgroundSnapshot?.dispose();
    picture?.dispose();
    if (recorder.isRecording) recorder.endRecording().dispose();
  }
}
