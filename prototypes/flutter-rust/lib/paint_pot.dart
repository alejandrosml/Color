// SPDX-License-Identifier: MIT
// The paint pot of Color 1.1 on the paper: the zone that the lines around
// the touched point close, small gaps plugged where that is allowed, poured
// as a contour of its own under the lines.
//
// The interface paints the drawing's ink into a mask, the core finds the
// zone in it (ep_fill_zone: a distance propagated from the ink, never a
// search for the ends of lines nor for gaps), and the zone comes back as
// rings that this file turns into points of the sheet.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'document_renderer.dart';
import 'rust_document.dart';

/// The gaps the pot closes, in pixels of the screen: a gap narrower than
/// twice this, about three millimetres, holds the paint in.
const potGapPixels = 8.0;

/// The most pixels of a mask, about those of a large screen: a bigger sheet
/// is painted smaller into it.
const maxMaskPixels = 2048 * 1536;

/// The ink of a drawing as the pot sees it, one byte a pixel: 255 where it
/// is drawn, 0 where the paper shows; [scaleX] and [scaleY] pixels per
/// unit of the sheet.
class InkMask {
  const InkMask(
    this.bytes,
    this.width,
    this.height,
    this.scaleX,
    this.scaleY, {
    this.image,
  });
  final Uint8List bytes;
  final int width;
  final int height;
  final double scaleX;
  final double scaleY;

  /// The picture the mask was read from, when it was asked to be kept: the
  /// drawing with nothing under it. What shows the paper before the pot
  /// pours on it paints through it (Color 1.2). Whoever keeps the mask
  /// disposes of it.
  final ui.Image? image;

  /// The pixel under a point of the sheet, inside the mask.
  (int, int) pixelAt(DocumentPoint point) => (
    (point.x * scaleX).floor().clamp(0, width - 1),
    (point.y * scaleY).floor().clamp(0, height - 1),
  );
}

/// The size of the mask of a sheet: its own size in units, smaller when
/// that would exceed [maxMaskPixels].
(int, int) maskSizeFor(int sheetWidth, int sheetHeight) {
  final scale = math.min(
    1.0,
    math.sqrt(maxMaskPixels / (sheetWidth * sheetHeight)),
  );
  return (
    math.max(1, (sheetWidth * scale).round()).clamp(1, 4096),
    math.max(1, (sheetHeight * scale).round()).clamp(1, 4096),
  );
}

/// Paints [elements] into the mask of a sheet of the given size. Where an
/// element covers a pixel by a quarter or more, the pixel is ink: a
/// see-through marker holds the paint as well as a pencil does. With
/// [keepImage] the mask comes with the picture it was read from.
Future<InkMask> renderInkMask(
  Iterable<RenderedElement> elements, {
  required int sheetWidth,
  required int sheetHeight,
  bool keepImage = false,
}) async {
  final (width, height) = maskSizeFor(sheetWidth, sheetHeight);
  final scaleX = width / sheetWidth;
  final scaleY = height / sheetHeight;
  final recorder = ui.PictureRecorder();
  ui.Picture? picture;
  ui.Image? image;
  try {
    final canvas = ui.Canvas(recorder);
    canvas.scale(scaleX, scaleY);
    canvas.clipRect(
      ui.Rect.fromLTWH(0, 0, sheetWidth.toDouble(), sheetHeight.toDouble()),
    );
    for (final element in elements) {
      element.paint(canvas);
    }
    picture = recorder.endRecording();
    image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null || data.lengthInBytes != width * height * 4) {
      throw StateError('Le moteur n’a pas pu lire le dessin.');
    }
    final rgba = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final mask = Uint8List(width * height);
    for (var i = 0, a = 3; i < mask.length; i++, a += 4) {
      final alpha = rgba[a];
      mask[i] = alpha >= 128 ? 255 : alpha * 2;
    }
    final kept = keepImage ? image : null;
    if (keepImage) image = null;
    return InkMask(mask, width, height, scaleX, scaleY, image: kept);
  } finally {
    image?.dispose();
    picture?.dispose();
    if (recorder.isRecording) recorder.endRecording().dispose();
  }
}

/// The radius the core is given, in pixels of the mask: [potGapPixels] of
/// the screen at the view's scale, or 0 where gaps must not be closed.
int potRadius({
  required double viewScale,
  required InkMask mask,
  required bool closesGaps,
}) {
  if (!closesGaps || !(viewScale > 0)) return 0;
  final pixels = potGapPixels / viewScale * math.max(mask.scaleX, mask.scaleY);
  return pixels.round().clamp(1, 64);
}

/// The rings of [zone], in pixels of [mask], as points of the sheet, kept
/// on it: the outer ring of a zone that reaches an edge lies half a pixel
/// beyond it.
List<DocumentPoint> zonePointsOnSheet(
  FillZone zone,
  InkMask mask, {
  required int sheetWidth,
  required int sheetHeight,
}) {
  final points = zone.points!;
  return [
    for (final point in points)
      DocumentPoint(
        (point.x / mask.scaleX).clamp(0, sheetWidth).toDouble(),
        (point.y / mask.scaleY).clamp(0, sheetHeight).toDouble(),
      ),
  ];
}

/// The area of rings filled even-odd: the outer one, less its holes.
double evenOddArea(List<DocumentPoint> points, List<int> rings) {
  var total = 0.0;
  var start = 0;
  for (final (index, count) in rings.indexed) {
    var twice = 0.0;
    for (var i = 0; i < count; i++) {
      final a = points[start + i];
      final b = points[start + (i + 1) % count];
      twice += a.x * b.y - b.x * a.y;
    }
    total += index == 0 ? twice.abs() / 2 : -twice.abs() / 2;
    start += count;
  }
  return total;
}

/// Whether [zone], poured before, is the zone found again: the same box
/// and nearly the same area, so that pouring there once more changes its
/// colour rather than lay a second zone on it.
bool isSameZone(
  StrokeData zone,
  List<DocumentPoint> points,
  List<int> rings, {
  required double tolerance,
}) {
  if (zone.look.transforms) return false;
  ui.Rect bounds(List<DocumentPoint> of) {
    var (left, top, right, bottom) = (
      double.infinity,
      double.infinity,
      double.negativeInfinity,
      double.negativeInfinity,
    );
    for (final p in of) {
      left = math.min(left, p.x);
      top = math.min(top, p.y);
      right = math.max(right, p.x);
      bottom = math.max(bottom, p.y);
    }
    return ui.Rect.fromLTRB(left, top, right, bottom);
  }

  final before = bounds(zone.points);
  final after = bounds(points);
  if ((before.left - after.left).abs() > tolerance ||
      (before.top - after.top).abs() > tolerance ||
      (before.right - after.right).abs() > tolerance ||
      (before.bottom - after.bottom).abs() > tolerance) {
    return false;
  }
  final a = evenOddArea(zone.points, zone.rings ?? [zone.points.length]);
  final b = evenOddArea(points, rings);
  return (a - b).abs() <= .03 * math.max(a, b);
}
