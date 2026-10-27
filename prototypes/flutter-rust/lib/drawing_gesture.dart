// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'rust_document.dart';

/// Constrains geometry in document space, independently of zoom and screen DPI.
DocumentPoint shapeEnd(
  DocumentPoint start,
  DocumentPoint raw, {
  required VectorKind kind,
  required bool constrain,
  required double documentWidth,
  required double documentHeight,
}) {
  if (!constrain || kind == VectorKind.stroke) return raw;
  final dx = raw.x - start.x;
  final dy = raw.y - start.y;
  if (dx == 0 && dy == 0) return raw;
  if (kind == VectorKind.line) {
    final angle = (math.atan2(dy, dx) / (math.pi / 4)).round() * math.pi / 4;
    final ux = math.cos(angle);
    final uy = math.sin(angle);
    var length = math.sqrt(dx * dx + dy * dy);
    if (ux.abs() > 1e-10) {
      length = math.min(
        length,
        (ux > 0 ? documentWidth - start.x : start.x) / ux.abs(),
      );
    }
    if (uy.abs() > 1e-10) {
      length = math.min(
        length,
        (uy > 0 ? documentHeight - start.y : start.y) / uy.abs(),
      );
    }
    return DocumentPoint(
      (start.x + ux * length).clamp(0, documentWidth).toDouble(),
      (start.y + uy * length).clamp(0, documentHeight).toDouble(),
    );
  }
  final sx = dx < 0 ? -1.0 : 1.0;
  final sy = dy < 0 ? -1.0 : 1.0;
  final side = math.min(
    math.max(dx.abs(), dy.abs()),
    math.min(
      sx > 0 ? documentWidth - start.x : start.x,
      sy > 0 ? documentHeight - start.y : start.y,
    ),
  );
  return DocumentPoint(start.x + sx * side, start.y + sy * side);
}

/// The start of a line, a rectangle or an oval, posed by a click that did
/// not move: the next click, or the end of the next drag, says where the
/// shape ends. [end] is where the pointer hovers meanwhile, for the preview;
/// null when it is nowhere on the sheet.
class ShapeAnchor {
  ShapeAnchor(this.start, this.kind);
  final DocumentPoint start;
  final VectorKind kind;
  DocumentPoint? end;

  /// Where the pointer really is, before Maj straightens the shape.
  DocumentPoint? rawEnd;
}

/// The shapes that two clicks can make: a start and an end are all they are.
bool madeOfTwoClicks(VectorKind kind) =>
    kind == VectorKind.line ||
    kind == VectorKind.rectangle ||
    kind == VectorKind.ellipse;

/// How far a pressed pointer may travel on the screen, in logical pixels,
/// and still be a click: a hand trembles more on glass than on a mouse.
double clickTravel({required bool touch}) => touch ? 12 : 6;

/// The radius of the little circle that marks a click of a shape made of
/// two, on the screen, in logical pixels.
const double shapeMarkRadius = 6;

/// How near the little circle a second click must be, on the screen, to be
/// a click on the circle itself: it then takes the circle away and draws
/// nothing. A double click that trembles leaves no speck on the sheet.
double shapeMarkReach({required bool touch}) =>
    shapeMarkRadius + (touch ? 8 : 2);

/// A click still makes a brush dot; a shape needs two different points, from
/// a drag or from two clicks.
bool isUsableShape(VectorKind kind, DocumentPoint start, DocumentPoint end) {
  final dx = (end.x - start.x).abs();
  final dy = (end.y - start.y).abs();
  return kind == VectorKind.line
      ? math.max(dx, dy) >= .5
      : dx >= .5 && dy >= .5;
}
