// SPDX-License-Identifier: MIT
import 'dart:typed_data';
import 'dart:ui';

import 'document_renderer.dart';
import 'rust_document.dart';

/// Observations are synchronous and never awaited. Callback failures are ignored
/// so optional diagnostics cannot interrupt rendering or resource disposal.
enum PngExportPhase {
  snapshotStarted,
  snapshotCompleted,
  paintStarted,
  paintCompleted,
  toImageStarted,
  toImageReturned,
  toByteDataStarted,
  toByteDataReturned,
  bytesCopied,
  cleanupStarted,
  cleanupCompleted,
}

void _observePhase(
  void Function(PngExportPhase)? observer,
  PngExportPhase phase,
) {
  if (observer == null) return;
  try {
    observer(phase);
  } catch (_) {
    // Observations must never change the export result.
  }
}

const int maxPngDimension = 8192;
// At most 64 MiB of RGBA pixels. Renderer and PNG encoder add their own overhead;
// this is an allocation bound, not a promise about the process peak memory.
const int maxPngPixels = 16 * 1024 * 1024;

bool canExportDocumentPng({
  required int width,
  required int height,
  int scale = 1,
}) {
  if (scale != 1 && scale != 2) return false;
  if (width < 1 ||
      height < 1 ||
      width > maxPngDimension ~/ scale ||
      height > maxPngDimension ~/ scale) {
    return false;
  }
  return width * scale * height * scale <= maxPngPixels;
}

/// Renders the committed document, on its opaque paper, without capturing UI.
/// All paths are copied into a local render snapshot before the first await.
/// Neither the live list nor a Rust handle is accessed during PNG encoding.
Future<Uint8List> exportDocumentPng(
  List<StrokeData> elements, {
  required int width,
  required int height,
  int scale = 1,
  Image? background,
  int paperRgb = whitePaper,
  void Function(PngExportPhase)? onPhase,
}) async {
  if (!canExportDocumentPng(width: width, height: height, scale: scale)) {
    throw ArgumentError('Cet export PNG dépasse les dimensions autorisées.');
  }
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
  var pointCount = 0;
  for (final element in elements) {
    pointCount += element.points.length;
    if (pointCount > 1000000 ||
        element.points.any(
          (point) =>
              point.x < 0 || point.x > width || point.y < 0 || point.y > height,
        )) {
      throw ArgumentError('Les éléments dépassent les limites du document.');
    }
  }
  _observePhase(onPhase, PngExportPhase.snapshotStarted);
  final snapshot = List<RenderedElement>.unmodifiable(
    elements.map(RenderedElement.new),
  );
  _observePhase(onPhase, PngExportPhase.snapshotCompleted);
  final recorder = PictureRecorder();
  Picture? picture;
  Image? image;
  Image? backgroundSnapshot;
  try {
    // A cheap handle clone keeps the image alive if the studio is disposed or
    // adopts another document while the asynchronous encoder is working.
    _observePhase(onPhase, PngExportPhase.paintStarted);
    backgroundSnapshot = background?.clone();
    final canvas = Canvas(recorder);
    canvas.scale(scale.toDouble());
    final paper = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    canvas.clipRect(paper, doAntiAlias: false);
    canvas.drawRect(paper, Paint()..color = Color(0xff000000 | paperRgb));
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
    _observePhase(onPhase, PngExportPhase.paintCompleted);
    _observePhase(onPhase, PngExportPhase.toImageStarted);
    image = await picture.toImage(width * scale, height * scale);
    _observePhase(onPhase, PngExportPhase.toImageReturned);
    if (image.width != width * scale || image.height != height * scale) {
      throw StateError('Le moteur a réduit l’image. Cet export est annulé.');
    }
    _observePhase(onPhase, PngExportPhase.toByteDataStarted);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    _observePhase(onPhase, PngExportPhase.toByteDataReturned);
    if (bytes == null) {
      throw StateError('Le moteur n’a pas pu encoder cette image PNG.');
    }
    final result = Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    _observePhase(onPhase, PngExportPhase.bytesCopied);
    return result;
  } finally {
    _observePhase(onPhase, PngExportPhase.cleanupStarted);
    image?.dispose();
    backgroundSnapshot?.dispose();
    picture?.dispose();
    if (recorder.isRecording) recorder.endRecording().dispose();
    _observePhase(onPhase, PngExportPhase.cleanupCompleted);
  }
}
