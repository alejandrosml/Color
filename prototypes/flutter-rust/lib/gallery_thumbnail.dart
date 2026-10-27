// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'document_renderer.dart';
import 'rust_document.dart';

/// Pixel size of the thumbnail of a sheet: its longer side measures at most
/// [maxSide], and a small sheet is never enlarged.
({int width, int height}) thumbnailSize(
  int width,
  int height, {
  int maxSide = 320,
}) {
  final scale = math.min(1.0, maxSide / math.max(width, height));
  return (
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

/// A small PNG picture of a drawing as it is saved: its paper, its image
/// background and the objects of its visible layers, in painting order.
///
/// Everything is captured before the first await: the caller may edit the
/// drawing or replace it while the picture is encoded. [background] is
/// borrowed: this function clones its handle and never disposes the caller's.
Future<Uint8List> renderThumbnail(
  List<StrokeData> elements, {
  required int width,
  required int height,
  int paperRgb = whitePaper,
  Image? background,
  int maxSide = 320,
}) async {
  // Refused before a single element is prepared.
  if (elements.length > 10000) {
    throw ArgumentError('Miniature impossible pour ce dessin.');
  }
  return renderThumbnailOf(
    List<RenderedElement>.unmodifiable(elements.map(RenderedElement.new)),
    width: width,
    height: height,
    paperRgb: paperRgb,
    background: background,
    maxSide: maxSide,
  );
}

/// The same picture from elements that are already prepared for painting,
/// in painting order: the studio hands over those it paints the sheet with,
/// and prepares nothing twice.
Future<Uint8List> renderThumbnailOf(
  List<RenderedElement> snapshot, {
  required int width,
  required int height,
  int paperRgb = whitePaper,
  Image? background,
  int maxSide = 320,
}) async {
  if (width < 1 ||
      width > 16384 ||
      height < 1 ||
      height > 16384 ||
      maxSide < 16 ||
      maxSide > 1024 ||
      paperRgb < 0 ||
      paperRgb > 0xffffff ||
      snapshot.length > 10000) {
    throw ArgumentError('Miniature impossible pour ce dessin.');
  }
  final size = thumbnailSize(width, height, maxSide: maxSide);
  final recorder = PictureRecorder();
  Picture? picture;
  Image? image;
  Image? backgroundSnapshot;
  try {
    backgroundSnapshot = background?.clone();
    final canvas = Canvas(recorder);
    canvas.scale(size.width / width, size.height / height);
    final paper = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    canvas.clipRect(paper, doAntiAlias: false);
    canvas.drawRect(paper, Paint()..color = Color(0xff000000 | paperRgb));
    if (backgroundSnapshot != null) {
      canvas.drawImageRect(
        backgroundSnapshot,
        Rect.fromLTWH(
          0,
          0,
          backgroundSnapshot.width.toDouble(),
          backgroundSnapshot.height.toDouble(),
        ),
        paper,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    for (final element in snapshot) {
      element.paint(canvas);
    }
    picture = recorder.endRecording();
    image = await picture.toImage(size.width, size.height);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Le moteur n’a pas pu encoder la miniature.');
    }
    return Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } finally {
    image?.dispose();
    backgroundSnapshot?.dispose();
    picture?.dispose();
    if (recorder.isRecording) recorder.endRecording().dispose();
  }
}
