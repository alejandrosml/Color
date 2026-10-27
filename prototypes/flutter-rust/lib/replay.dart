// SPDX-License-Identifier: MIT
// The film of a drawing, in numbers: when each element is redrawn, and which
// elements lie under which while it plays. Nothing here paints or changes a
// drawing; replay_dialog.dart shows the film.
import 'dart:math' as math;
import 'dart:typed_data';

import 'document_renderer.dart';
import 'rust_document.dart';

/// When each element of a drawing is redrawn in its film.
///
/// The elements come one after the other, in the order of the list, each for
/// a time that suits what it is, with a short pause between two of them. A
/// drawing whose film would last longer than [ReplayPlan.new]'s `longest` is
/// played faster, every element and every pause alike, so that it lasts
/// exactly that long.
///
/// The first `fixed` elements are not redrawn: they are on the sheet from
/// the first moment, complete at zero, and the film begins with the element
/// after them. They are the page of a colouring page, which the child did
/// not draw. The `recoloured` elements after them are zones of that page
/// which the paint pot coloured: each takes its colour in a short step,
/// [zone], before the elements that the child drew are redrawn.
///
/// Times are whole microseconds: the last element is complete at [total],
/// not a rounding later.
final class ReplayPlan {
  /// [sheetDiagonal] is the diagonal of the sheet in the units of the
  /// drawing: the measure of what a long trait is.
  factory ReplayPlan(
    List<RenderedElement> elements, {
    required double sheetDiagonal,
    Duration longest = const Duration(seconds: 24),
    int fixed = 0,
    int recoloured = 0,
  }) {
    if (longest <= Duration.zero) {
      throw ArgumentError.value(longest, 'longest', 'Durée hors limites.');
    }
    final count = elements.length;
    if (fixed < 0 || fixed > count) {
      throw RangeError.range(fixed, 0, count, 'fixed');
    }
    if (recoloured < 0 || recoloured > count - fixed) {
      throw RangeError.range(recoloured, 0, count - fixed, 'recoloured');
    }
    final starts = Int64List(count);
    final ends = Int64List(count);
    var clock = 0;
    // Those already there take no time, and no pause follows them.
    for (var index = fixed; index < count; index++) {
      if (index > fixed) clock += pause.inMicroseconds;
      starts[index] = clock;
      clock += index < fixed + recoloured
          ? zone.inMicroseconds
          : naturalDuration(
              elements[index].data,
              sheetDiagonal: sheetDiagonal,
            ).inMicroseconds;
      ends[index] = clock;
    }
    final limit = longest.inMicroseconds;
    if (clock > limit) {
      // One factor for every moment keeps their order: an element still
      // starts after the one before it has ended.
      final factor = limit / clock;
      for (var index = 0; index < count; index++) {
        starts[index] = (starts[index] * factor).round();
        ends[index] = (ends[index] * factor).round();
      }
      ends[count - 1] = limit;
      clock = limit;
    }
    return ReplayPlan._(starts, ends, Duration(microseconds: clock));
  }

  ReplayPlan._(this._starts, this._ends, this.total);

  /// What a trait as long as the diagonal of the sheet takes.
  static const diagonalTrait = Duration(milliseconds: 1200);

  /// The shortest element: a dot, a very small trait.
  static const shortest = Duration(milliseconds: 250);

  /// The longest element, however long a trait or a text is.
  static const slowest = Duration(milliseconds: 2500);
  static const line = Duration(milliseconds: 400);

  /// A rectangle, an oval or a contour: its outline, then its inside.
  static const shape = Duration(milliseconds: 700);
  static const stamp = Duration(milliseconds: 450);

  /// A zone of a colouring page that takes the colour of the paint pot: a
  /// short step, as long as a stamp.
  static const zone = stamp;

  /// A text before its first character, and what each character adds.
  static const textStart = Duration(milliseconds: 300);
  static const textCharacter = Duration(milliseconds: 40);

  /// The rest between two elements.
  static const pause = Duration(milliseconds: 80);

  /// How long the film takes over one element when nothing hurries it: a
  /// trait by its length, a text by its characters, the others by their
  /// kind.
  static Duration naturalDuration(
    StrokeData data, {
    required double sheetDiagonal,
  }) {
    if (!sheetDiagonal.isFinite || sheetDiagonal <= 0) {
      throw ArgumentError.value(
        sheetDiagonal,
        'sheetDiagonal',
        'Dimension hors limites.',
      );
    }
    switch (data.kind) {
      case VectorKind.stroke:
        final points = data.points;
        var length = 0.0;
        for (var index = 1; index < points.length; index++) {
          final dx = points[index].x - points[index - 1].x;
          final dy = points[index].y - points[index - 1].y;
          length += math.sqrt(dx * dx + dy * dy);
        }
        final micros = length / sheetDiagonal * diagonalTrait.inMicroseconds;
        // Written so that a length beyond every number is simply long.
        if (!(micros > shortest.inMicroseconds)) return shortest;
        if (micros >= slowest.inMicroseconds) return slowest;
        return Duration(microseconds: micros.round());
      case VectorKind.line:
        return line;
      case VectorKind.rectangle:
      case VectorKind.ellipse:
      case VectorKind.contour:
        return shape;
      case VectorKind.stamp:
        return stamp;
      case VectorKind.text:
        // A line break counts as a character: the hand goes back to the left.
        final characters = data.text?.runes.length ?? 0;
        final written = textStart + textCharacter * characters;
        return written > slowest ? slowest : written;
    }
  }

  // Start and end of every element, in microseconds from the beginning of
  // the film. Both never decrease, and an element starts no earlier than the
  // one before it ends.
  final Int64List _starts;
  final Int64List _ends;

  /// How long the whole film lasts.
  final Duration total;

  /// Number of elements.
  int get length => _starts.length;

  /// When element [index] starts.
  Duration startOf(int index) => Duration(microseconds: _starts[index]);

  /// When element [index] is complete.
  Duration endOf(int index) => Duration(microseconds: _ends[index]);

  /// Progress 0…1 of element [index] when [elapsed] of the film has passed.
  double progressAt(int index, Duration elapsed) {
    final now = elapsed.inMicroseconds;
    final end = _ends[index];
    if (now >= end) return 1;
    final start = _starts[index];
    if (now <= start) return 0;
    return (now - start) / (end - start);
  }

  /// Index of the element being drawn at [elapsed] (the last started one),
  /// or -1 before the first.
  int currentAt(Duration elapsed) =>
      _countUpTo(_starts, elapsed.inMicroseconds) - 1;

  /// Number of elements that are complete at [elapsed]: the first ones, since
  /// they come one after the other.
  int finishedAt(Duration elapsed) => _countUpTo(_ends, elapsed.inMicroseconds);

  // How many of the [moments], which never decrease, are not after [now].
  static int _countUpTo(Int64List moments, int now) {
    var low = 0;
    var high = moments.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (moments[middle] <= now) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

/// Which elements of a film lie under which.
///
/// The film reveals the elements in one order and the sheet piles them in
/// another: an element made late on a layer below belongs under what was
/// made before it on the layers above. This keeps the pile, and tells which
/// part of it nothing will ever slip under again, so that this part can be
/// painted once and kept instead of being painted again for every frame.
final class ReplayOrder {
  /// [paintRank] gives, for each element in the order it is revealed, its
  /// place in the pile: 0 at the bottom, every place taken exactly once.
  factory ReplayOrder(List<int> paintRank) {
    final count = paintRank.length;
    final byRank = Int32List(count)..fillRange(0, count, -1);
    for (var index = 0; index < count; index++) {
      final rank = paintRank[index];
      if (rank < 0 || rank >= count || byRank[rank] != -1) {
        throw ArgumentError('L’ordre des éléments du dessin est invalide.');
      }
      byRank[rank] = index;
    }
    // Lowest place among the elements not yet revealed, for every number of
    // revealed ones: everything under that place is on the sheet for good.
    final floors = Int32List(count + 1);
    floors[count] = count;
    for (var index = count - 1; index >= 0; index--) {
      floors[index] = math.min(floors[index + 1], paintRank[index]);
    }
    // One more than the highest place among the revealed ones.
    final reaches = Int32List(count + 1);
    for (var index = 0; index < count; index++) {
      reaches[index + 1] = math.max(reaches[index], paintRank[index] + 1);
    }
    return ReplayOrder._(byRank, floors, reaches);
  }

  ReplayOrder._(this._byRank, this._floors, this._reaches);

  final Int32List _byRank;
  final Int32List _floors;
  final Int32List _reaches;

  /// Number of elements.
  int get length => _byRank.length;

  /// The element, by its place in the order of the film, that is painted at
  /// place [rank] of the pile.
  int elementAt(int rank) => _byRank[rank];

  /// How many places at the bottom of the pile are settled once the first
  /// [revealed] elements are on the sheet: all of them are taken by revealed
  /// elements, and every element still to come goes above them.
  int settledAt(int revealed) => _floors[revealed];

  /// One more than the highest place taken by the first [revealed] elements:
  /// above it the pile is still empty.
  int reachAt(int revealed) => _reaches[revealed];

  /// How many places at the bottom of the pile the picture kept between two
  /// frames holds once [finished] elements are complete. It follows
  /// [settledAt] by steps: at every element while the drawing is small,
  /// then every eighth more of what is already there, and to the end with
  /// the last element. A big drawing whose film completes several elements
  /// in every frame would otherwise have its kept picture, thousands of
  /// elements, painted again for every frame: no better than no picture.
  int restingAt(int finished) {
    if (finished >= length) return settledAt(length);
    var step = 0;
    while (true) {
      final next = step + math.max<int>(1, step >> 3);
      if (next > finished) break;
      step = next;
    }
    return settledAt(step);
  }
}
