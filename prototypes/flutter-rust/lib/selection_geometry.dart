// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'dart:ui';

import 'rust_document.dart';
import 'stamp_catalog.dart';

/// Geometry bounds use control points. Stroke paint can extend outside the page
/// already, so translation preserves the core's point-in-page contract.
Rect objectBounds(StrokeData object, {bool includeStroke = false}) {
  var left = object.points.first.x;
  var right = left;
  var top = object.points.first.y;
  var bottom = top;
  for (final point in object.points.skip(1)) {
    left = math.min(left, point.x);
    right = math.max(right, point.x);
    top = math.min(top, point.y);
    bottom = math.max(bottom, point.y);
  }
  final bounds = Rect.fromLTRB(left, top, right, bottom);
  return includeStroke ? bounds.inflate(object.outlineRadius) : bounds;
}

Offset clampObjectMovement(
  StrokeData object,
  Offset requested, {
  required double pageWidth,
  required double pageHeight,
}) {
  return clampBoundsMovement(
    objectBounds(object),
    requested,
    pageWidth: pageWidth,
    pageHeight: pageHeight,
  );
}

/// A drag caches these bounds once, avoiding a scan of a long freehand path for
/// each pointer sample.
Offset clampBoundsMovement(
  Rect bounds,
  Offset requested, {
  required double pageWidth,
  required double pageHeight,
}) {
  return Offset(
    requested.dx.clamp(-bounds.left, pageWidth - bounds.right).toDouble(),
    requested.dy.clamp(-bounds.top, pageHeight - bounds.bottom).toDouble(),
  );
}

/// How near the pointer an element must be to count as « under » it, in
/// logical screen pixels: about the tip of a pointer. What is this close is
/// preferred to anything that is only within the wider tolerance.
const precisePixels = 2.5;

// Whether the ink of [object] lies within [reach] of [position]. With
// [boxes] a text or a stamp answers in its whole box, like a filled shape;
// without, a stamp answers only where its artwork is, so that what shows
// through its empty corners can be reached. Without [insides] a filled shape
// answers by its outline alone.
bool _covers(
  StrokeData object,
  Rect bounds,
  Offset position,
  double reach, {
  required bool boxes,
  bool insides = true,
}) {
  final radius = object.outlineRadius + reach;
  if (!bounds.inflate(radius + .000001).contains(position)) return false;
  final points = object.points;
  switch (object.kind) {
    case VectorKind.text:
      // Letters have gaps that would make a small target hard to reach, and
      // a box drawn tight around its lines: the box answers.
      return true;
    case VectorKind.stamp:
      if (boxes) return true;
      final art = stampArtOf(object);
      // Without its catalogue a stamp is known by its box alone.
      return art == null ||
          art.inkAt(position, bounds, object.rgb, reach) != null;
    case VectorKind.stroke:
    case VectorKind.line:
      if (points.length == 1) {
        return (position - Offset(points.first.x, points.first.y)).distance <=
            radius;
      }
      for (var i = 1; i < points.length; i++) {
        if (_segmentDistance(
              position,
              Offset(points[i - 1].x, points[i - 1].y),
              Offset(points[i].x, points[i].y),
            ) <=
            radius) {
          return true;
        }
      }
      return false;
    case VectorKind.rectangle:
      if (insides && object.fillRgb != null && bounds.contains(position)) {
        return true;
      }
      final corners = [
        bounds.topLeft,
        bounds.topRight,
        bounds.bottomRight,
        bounds.bottomLeft,
      ];
      for (var i = 0; i < 4; i++) {
        if (_segmentDistance(position, corners[i], corners[(i + 1) % 4]) <=
            radius) {
          return true;
        }
      }
      return false;
    case VectorKind.ellipse:
      final relative = position - bounds.center;
      final rx = bounds.width / 2;
      final ry = bounds.height / 2;
      if (insides &&
          object.fillRgb != null &&
          _insideEllipse(relative, rx, ry)) {
        return true;
      }
      return _ellipseDistance(relative, rx, ry) <= radius;
    case VectorKind.contour:
      if (insides &&
          object.fillRgb != null &&
          _insideContour(position, points)) {
        return true;
      }
      // Its sides, the last one going back to the first point.
      for (var i = 0; i < points.length; i++) {
        final from = points[i];
        final to = points[i + 1 < points.length ? i + 1 : 0];
        if (_segmentDistance(
              position,
              Offset(from.x, from.y),
              Offset(to.x, to.y),
            ) <=
            radius) {
          return true;
        }
      }
      return false;
  }
}

bool _insideEllipse(Offset relative, double rx, double ry) =>
    relative.dx * relative.dx / (rx * rx) +
        relative.dy * relative.dy / (ry * ry) <=
    1;

/// Whether [position] is inside the closed polygon [points] by the nonzero
/// rule, the one with which the inside of a contour is painted: of the sides
/// that cross the horizontal line of the position on its right, those that
/// go up are not as many as those that go down.
bool _insideContour(Offset position, List<DocumentPoint> points) {
  final x = position.dx;
  final y = position.dy;
  var winding = 0;
  for (var i = 0; i < points.length; i++) {
    final from = points[i];
    final to = points[i + 1 < points.length ? i + 1 : 0];
    // Positive when the position lies on the left of the side.
    final side =
        (to.x - from.x) * (y - from.y) - (x - from.x) * (to.y - from.y);
    if (from.y <= y) {
      if (to.y > y && side > 0) winding++;
    } else if (to.y <= y && side < 0) {
      winding--;
    }
  }
  return winding != 0;
}

/// Whether [object], a hollow rectangle, oval or contour, encloses
/// [position]: where poured paint would go. Any other element encloses
/// nothing.
bool _encloses(StrokeData object, Rect bounds, Offset position) =>
    switch (object.kind) {
      VectorKind.rectangle => bounds.contains(position),
      VectorKind.ellipse => _insideEllipse(
        position - bounds.center,
        bounds.width / 2,
        bounds.height / 2,
      ),
      VectorKind.contour =>
        bounds.contains(position) && _insideContour(position, object.points),
      VectorKind.stroke ||
      VectorKind.line ||
      VectorKind.text ||
      VectorKind.stamp => false,
    };

/// The artwork of a stamp object, or null when the catalogue cannot be read
/// or does not know it.
StampArt? stampArtOf(StrokeData object) {
  final id = object.stamp;
  if (id == null) return null;
  try {
    return StampCatalog.instance[id];
  } catch (_) {
    return null;
  }
}

/// Returns the object that a pointer at [point] designates, or null.
///
/// First what is painted under the pointer, frontmost first, within
/// [precisePixels]: an element that is merely near never takes the place of
/// the one that is there. Only when nothing is under the pointer does the
/// nearest element within [tolerancePixels] answer, frontmost first, so that
/// a thin trait stays easy to catch; a text or a stamp then answers in its
/// whole box. Hollow shapes do not intercept clicks inside them. Tolerances
/// stay in logical screen pixels when the page is resized.
///
/// A caller that owns immutable snapshots may supply their prepared bounds.
/// Each non-null result must match this exact object at this index, without
/// stroke inflation. The default/null fallback recomputes bounds, including for
/// mutable subclasses; this function keeps no identity or historical cache.
///
/// [paintOrder] lists the indices that are actually painted, bottom first: with
/// layers the topmost object is not always the last one, and the objects of a
/// hidden layer cannot be touched. Without it every object is tested, last
/// index on top. The result is always an index into [objects]. A caller may
/// leave out more than the hidden layers: what is left out is not there for
/// the pointer, which reaches what lies under it. The studio leaves out the
/// locked layers of a colouring page for the eraser and « Choisir », and
/// the lines of the page for the paint pot.
///
/// With [insideShapes], for the paint pot, which fills what an outline
/// encloses as a pot of paint would: a trait, a stamp, a text or an outline
/// under the pointer answers first. Otherwise the smallest hollow rectangle,
/// oval or contour that encloses the pointer answers as if it were filled,
/// also when the inside of a larger filled shape is seen through it: a sun
/// drawn on a sky is filled, not the sky. A frame drawn around a drawing
/// never takes the clicks meant for that drawing. The area of a shape is
/// that of its box.
///
/// With [inkOnly], for the pipette: only ink answers, at any distance. A
/// stamp is not its box: what shows through its empty corners is what is
/// seen there.
int? hitTestObjects(
  List<StrokeData> objects,
  DocumentPoint point, {
  required double scale,
  double tolerancePixels = 7,
  Rect? Function(int index, StrokeData object)? preparedBounds,
  List<int>? paintOrder,
  bool insideShapes = false,
  bool inkOnly = false,
}) {
  if (!scale.isFinite || scale <= 0 || tolerancePixels < 0) {
    throw ArgumentError('Échelle de sélection invalide.');
  }
  final position = Offset(point.x, point.y);
  final count = paintOrder?.length ?? objects.length;
  int indexAt(int rank) => paintOrder == null ? rank : paintOrder[rank];
  Rect boundsOf(int index) =>
      preparedBounds?.call(index, objects[index]) ??
      objectBounds(objects[index]);
  // The rank, in paint order, of the frontmost element within reach.
  int? frontmost(double reach, {required bool boxes}) {
    for (var rank = count - 1; rank >= 0; rank--) {
      final index = indexAt(rank);
      if (_covers(
        objects[index],
        boundsOf(index),
        position,
        reach,
        boxes: boxes,
      )) {
        return rank;
      }
    }
    return null;
  }

  final precise = math.min(tolerancePixels, precisePixels) / scale;
  final exact = frontmost(precise, boxes: false);
  if (exact != null && !insideShapes) return indexAt(exact);
  if (insideShapes) {
    // Hollow shapes painted in front of what is seen, and smaller than it.
    var from = 0;
    var smallestArea = double.infinity;
    if (exact != null) {
      final index = indexAt(exact);
      final object = objects[index];
      final bounds = boundsOf(index);
      final isShape = object.kind.canFill;
      // Only the inside of a filled shape lets a frame in front of it answer.
      if (!isShape ||
          object.fillRgb == null ||
          _covers(
            object,
            bounds,
            position,
            precise,
            boxes: false,
            insides: false,
          )) {
        return index;
      }
      from = exact + 1;
      smallestArea = bounds.width * bounds.height;
    }
    int? smallest;
    for (var rank = count - 1; rank >= from; rank--) {
      final index = indexAt(rank);
      final object = objects[index];
      if (object.fillRgb != null) continue;
      final bounds = boundsOf(index);
      final encloses = _encloses(object, bounds, position);
      final area = bounds.width * bounds.height;
      // Strictly smaller: of two equal frames the one in front answers.
      if (encloses && area < smallestArea) {
        smallest = index;
        smallestArea = area;
      }
    }
    if (smallest != null) return smallest;
    if (exact != null) return indexAt(exact);
  }
  if (tolerancePixels <= precisePixels) return null;
  final near = frontmost(tolerancePixels / scale, boxes: !inkOnly);
  return near == null ? null : indexAt(near);
}

/// The colour seen on [object] at [point], which lies on it: the outline of a
/// filled shape when the pointer is on its border, its inside colour
/// elsewhere, the colour of the part of a stamp that is under the pointer,
/// and the single colour of every other object.
int colourOfObjectAt(
  StrokeData object,
  DocumentPoint point, {
  required double scale,
}) {
  if (object.kind == VectorKind.stamp) {
    final art = stampArtOf(object);
    return art?.inkAt(
          Offset(point.x, point.y),
          objectBounds(object),
          object.rgb,
          precisePixels / scale,
        ) ??
        object.rgb;
  }
  final fill = object.fillRgb;
  if (fill == null) return object.rgb;
  final hollow = StrokeData(
    object.points,
    object.rgb,
    object.width,
    kind: object.kind,
  );
  // A narrow tolerance: on the screen the border is exactly as wide as drawn.
  return hitTestObjects([hollow], point, scale: scale, tolerancePixels: 1) ==
          null
      ? fill
      : object.rgb;
}

double _segmentDistance(Offset point, Offset start, Offset end) {
  final delta = end - start;
  if (delta.distanceSquared == 0) return (point - start).distance;
  final fraction =
      (((point.dx - start.dx) * delta.dx + (point.dy - start.dy) * delta.dy) /
              delta.distanceSquared)
          .clamp(0.0, 1.0);
  return (point - start - delta * fraction).distance;
}

// Nearest point on an ellipse via the monotonic Lagrange multiplier equation.
// Unlike normalized-radius tests, this gives a constant distance even for very
// flat ellipses. Symmetry reduces the search to the first quadrant.
double _ellipseDistance(Offset position, double rx, double ry) {
  final a = math.max(rx, ry);
  final b = math.min(rx, ry);
  final x = (rx >= ry ? position.dx : position.dy).abs();
  final y = (rx >= ry ? position.dy : position.dx).abs();
  final aa = a * a;
  final bb = b * b;
  if (y == 0) {
    final difference = aa - bb;
    if (difference > 0 && a * x < difference) {
      final nearestX = aa * x / difference;
      final nearestY = b * math.sqrt(math.max(0, 1 - nearestX * nearestX / aa));
      return Offset(x - nearestX, nearestY).distance;
    }
    return (x - a).abs();
  }
  var low = -bb;
  var high = math.sqrt(aa * x * x + bb * y * y);
  for (var iteration = 0; iteration < 80; iteration++) {
    final t = (low + high) / 2;
    final nx = a * x / (t + aa);
    final ny = b * y / (t + bb);
    if (nx * nx + ny * ny > 1) {
      low = t;
    } else {
      high = t;
    }
  }
  final t = (low + high) / 2;
  return Offset(x - aa * x / (t + aa), y - bb * y / (t + bb)).distance;
}
