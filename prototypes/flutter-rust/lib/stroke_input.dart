// SPDX-License-Identifier: MIT
// What a trait keeps of the pointer: a finger's tremble smoothed away by the
// 1€ filter, samples that do not move dropped, and, at the end, the points
// that the eye cannot tell from a straight line taken out (the techniques of
// the retrospective of October 2026, and its D-08). Plain Dart: no Flutter.
import 'dart:math' as math;

/// The 1€ filter of Casiez, Roussel and Vogel (« 1€ Filter: A Simple
/// Speed-based Low-pass Filter for Noisy Input in Interactive Systems »,
/// CHI 2012), for a point of the screen. A low-pass filter whose cut-off
/// rises with the speed of the pointer: a slow finger trembles less, a quick
/// one is followed without lag. Its estimate of the speed starts from the
/// first move rather than from rest, so that a quick little trait — a
/// check mark — keeps its corner.
final class OneEuroFilter {
  OneEuroFilter({
    this.minCutoff = 4,
    this.beta = .035,
    this.derivativeCutoff = 2,
  });

  /// The cut-off at rest, in hertz: the lower, the smoother and the later.
  final double minCutoff;

  /// How much the cut-off rises per pixel a second of speed.
  final double beta;

  /// The cut-off of the speed itself, in hertz.
  final double derivativeCutoff;

  double? _x;
  double? _y;
  double _dx = 0;
  double _dy = 0;
  bool _moved = false;
  Duration? _at;

  static double _alpha(double cutoff, double seconds) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / seconds);
  }

  /// The point ([x], [y]) seen at [at], smoothed. The first point is kept
  /// as it is; a sample that comes at the same time as the one before, or
  /// earlier, moves the point without smoothing it.
  (double, double) filter(double x, double y, Duration at) {
    final lastX = _x;
    final lastY = _y;
    final last = _at;
    _at = at;
    if (lastX == null || lastY == null || last == null) {
      _x = x;
      _y = y;
      return (x, y);
    }
    final seconds = (at - last).inMicroseconds / Duration.microsecondsPerSecond;
    if (!(seconds > 0)) {
      _x = x;
      _y = y;
      return (x, y);
    }
    final rawDx = (x - lastX) / seconds;
    final rawDy = (y - lastY) / seconds;
    if (_moved) {
      final derivativeAlpha = _alpha(derivativeCutoff, seconds);
      _dx += derivativeAlpha * (rawDx - _dx);
      _dy += derivativeAlpha * (rawDy - _dy);
    } else {
      _moved = true;
      _dx = rawDx;
      _dy = rawDy;
    }
    final speed = math.sqrt(_dx * _dx + _dy * _dy);
    final alpha = _alpha(minCutoff + beta * speed, seconds);
    final filteredX = lastX + alpha * (x - lastX);
    final filteredY = lastY + alpha * (y - lastY);
    _x = filteredX;
    _y = filteredY;
    return (filteredX, filteredY);
  }
}

/// The distance on the screen, in logical pixels, under which a sample of
/// the pointer is not kept: a move the eye cannot see (D-08).
const double unseenMovePixels = .4;

/// The distance on the screen, in logical pixels, from which a point of a
/// trait is taken out at its end: no line of the trait moves farther.
const double simplifyPixels = .25;

/// The indices of the points of the polyline ([xs], [ys]) that the
/// Ramer–Douglas–Peucker algorithm (1972, 1973) keeps for [tolerance]: the
/// first and the last always, and between them every point that lies
/// farther than [tolerance] from the line kept around it. Iterative, with
/// its own stack: a trait of a hundred thousand points does not go a
/// hundred thousand calls deep. And window by window of [window] points,
/// which share their ends: the work grows with the number of points, never
/// with its square, however regular the trait (a zigzag of colouring).
List<int> simplifiedIndices(
  List<double> xs,
  List<double> ys,
  double tolerance, {
  int window = 256,
}) {
  final count = xs.length;
  if (count != ys.length) {
    throw ArgumentError('Autant d’abscisses que d’ordonnées.');
  }
  if (count <= 2 || !(tolerance > 0)) {
    return [for (var index = 0; index < count; index++) index];
  }
  if (window < 3) {
    throw ArgumentError.value(window, 'window', 'au moins 3 points');
  }
  final keep = List<bool>.filled(count, false);
  final squared = tolerance * tolerance;
  final stack = <int>[];
  for (var start = 0; start < count - 1; start += window - 1) {
    final end = math.min(start + window - 1, count - 1);
    keep[start] = true;
    keep[end] = true;
    stack
      ..add(start)
      ..add(end);
    _simplify(xs, ys, squared, keep, stack);
  }
  return [
    for (var index = 0; index < count; index++)
      if (keep[index]) index,
  ];
}

// Ramer–Douglas–Peucker over the ranges of [stack], marking in [keep].
void _simplify(
  List<double> xs,
  List<double> ys,
  double squared,
  List<bool> keep,
  List<int> stack,
) {
  while (stack.isNotEmpty) {
    final last = stack.removeLast();
    final first = stack.removeLast();
    final ax = xs[first], ay = ys[first];
    final bx = xs[last], by = ys[last];
    final dx = bx - ax, dy = by - ay;
    final length = dx * dx + dy * dy;
    var farthest = -1;
    var distance = squared;
    for (var index = first + 1; index < last; index++) {
      final px = xs[index] - ax, py = ys[index] - ay;
      double away;
      if (length == 0) {
        away = px * px + py * py;
      } else {
        // The distance to the segment, not to the line through it: a
        // trait that comes back on itself keeps where it turned.
        final along = ((px * dx + py * dy) / length).clamp(0.0, 1.0);
        final ex = px - along * dx, ey = py - along * dy;
        away = ex * ex + ey * ey;
      }
      if (away > distance) {
        distance = away;
        farthest = index;
      }
    }
    if (farthest >= 0) {
      keep[farthest] = true;
      stack
        ..add(first)
        ..add(farthest)
        ..add(farthest)
        ..add(last);
    }
  }
}
