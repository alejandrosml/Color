// SPDX-License-Identifier: MIT
// Where a decor stands in the frame of the sheet (Color 1.2): each side
// against its edge, everything on the bottom, as large as the height
// allows; smaller when the sheet leaves less room than it was drawn for —
// a child must see everything; no piece at all where it would be too small
// (the studio then shows no decor). And where it stands when it is looked
// at without a sheet, on the whole screen: its two sides together, side by
// side or one above the other.
import 'package:edupaint_flutter_study/decor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const decor = Size(1061, 407);
  const decorSheet = Rect.fromLTWH(266, 26, 526, 351);

  // The sheet of 1200 × 800 at rest in a frame, with the margin of the
  // captions, as the studio lays it.
  Rect sheetIn(Size frame, {double ratio = 1.5, double padding = 28}) {
    final width = frame.width - 2 * padding;
    final height = frame.height - 2 * padding;
    final scale = width / ratio < height ? width / ratio : height;
    final size = Size(scale * ratio, scale);
    return Rect.fromLTWH(
      (frame.width - size.width) / 2,
      (frame.height - size.height) / 2,
      size.width,
      size.height,
    );
  }

  DecorLayout layout(Size frame, {double ratio = 1.5, double padding = 28}) =>
      DecorLayout(
        frame: frame,
        sheetAtRest: sheetIn(frame, ratio: ratio, padding: padding),
        decor: decor,
        decorSheet: decorSheet,
      );

  test('in the frame it was drawn for, the decor is where it was drawn', () {
    final drawn = layout(decor);
    expect(drawn.pieces, isTrue);
    expect(drawn.scale, closeTo(1, .01));
    const cat = Rect.fromLTWH(924, 284, 130, 66);
    final placed = drawn.place(cat, DecorAnchor.right);
    expect(placed.left, closeTo(924, 6));
    expect(placed.bottom, closeTo(350, 6));
    // Nothing of the sides lies under the sheet.
    final sheet = sheetIn(decor);
    expect(
      drawn.place(const Rect.fromLTWH(0, 0, 266, 407), DecorAnchor.left).right,
      lessThanOrEqualTo(sheet.left + 1),
    );
    expect(
      drawn
          .place(const Rect.fromLTWH(792, 0, 269, 407), DecorAnchor.right)
          .left,
      greaterThanOrEqualTo(sheet.right - 1),
    );
  });

  test('in a wider frame each side keeps to its edge, at the full height', () {
    const frame = Size(1700, 500);
    final wide = layout(frame);
    expect(wide.pieces, isTrue);
    expect(wide.scale, closeTo(500 / 407, 1e-9));
    final scale = wide.scale;
    // The window of the desk, against the left edge.
    final window = wide.place(
      const Rect.fromLTWH(37, 41, 166, 188),
      DecorAnchor.left,
    );
    expect(window.left, closeTo(37 * scale, 1e-9));
    expect(window.top, closeTo(41 * scale, 1e-9));
    // The cat, against the right edge and on the bottom.
    final cat = wide.place(
      const Rect.fromLTWH(924, 284, 130, 66),
      DecorAnchor.right,
    );
    expect(frame.width - cat.right, closeTo((1061 - 1054) * scale, 1e-9));
    expect(frame.height - cat.bottom, closeTo((407 - 350) * scale, 1e-9));
    // What lies under the sheet stays under its middle.
    final pencils = wide.place(
      const Rect.fromLTWH(286, 382, 250, 22),
      DecorAnchor.middle,
    );
    expect(
      pencils.center.dx - frame.width / 2,
      closeTo((411 - 529) * scale, 1e-9),
    );
    expect(
      wide.point(const Offset(0, 407), DecorAnchor.left),
      Offset(0, frame.height),
    );
  });

  test(
    'where the sheet leaves less room, the decor is smaller, never hidden',
    () {
      // A frame less wide for its height than the decor: at the full height
      // the sides would go under the sheet.
      const frame = Size(870, 430);
      final narrow = layout(frame);
      final sheet = sheetIn(frame);
      expect(narrow.pieces, isTrue);
      expect(narrow.scale, lessThan(430 / 407));
      expect(narrow.scale, closeTo(sheet.left / 269, 1e-9));
      // Everything of each side beside the sheet, and on the bottom edge.
      final left = narrow.place(
        const Rect.fromLTWH(0, 0, 266, 407),
        DecorAnchor.left,
      );
      final right = narrow.place(
        const Rect.fromLTWH(792, 0, 269, 407),
        DecorAnchor.right,
      );
      expect(left.right, lessThanOrEqualTo(sheet.left + 1e-6));
      expect(right.left, greaterThanOrEqualTo(sheet.right - 1e-6));
      expect(left.bottom, closeTo(frame.height, 1e-9));
      expect(left.top, greaterThan(0));
      // A portrait sheet leaves more room: the decor is as large as it can be.
      expect(layout(frame, ratio: 2 / 3).scale, closeTo(430 / 407, 1e-9));
    },
  );

  test('where even half its size would not fit, its pieces are not shown', () {
    // A tall frame that the sheet fills from side to side.
    const frame = Size(790, 520);
    final none = layout(frame);
    expect(none.pieces, isFalse);
    // The studio then shows no decor at all: a ground alone has no
    // interest (the owner, 12 November 2026).
    expect(none.scale, closeTo(520 / 407, 1e-9));
    // A telephone: the sheet takes all the room.
    expect(
      DecorLayout(
        frame: const Size(560, 380),
        sheetAtRest: sheetIn(const Size(560, 380), padding: 8),
        decor: decor,
        decorSheet: decorSheet,
      ).pieces,
      isFalse,
    );
    // The limit is a share of the full size.
    expect(DecorLayout.minimumShare, .45);
    expect(layout(Size.zero).pieces, isFalse);
  });

  test('what lies under the sheet is left out where the sheet hides it', () {
    // With the captions the sheet leaves a band under it: the pencils that
    // were drawn there are shown, in the frame of the drawing and in a
    // larger one.
    for (final frame in [decor, const Size(1542, 587)]) {
      final shown = layout(frame);
      expect(shown.under, isTrue);
      expect(shown.shows(DecorAnchor.middle), isTrue);
      expect(shown.shows(DecorAnchor.left), isTrue);
      expect(shown.shows(DecorAnchor.right), isTrue);
    }
    // In the simplest interface the sheet comes down to eight points of
    // the bottom: the pencils would be under it, but for a sliver. They
    // are left out; what stands beside the sheet stays.
    final simple = layout(const Size(1100, 420), padding: 8);
    expect(simple.pieces, isTrue);
    expect(simple.under, isFalse);
    expect(simple.shows(DecorAnchor.middle), isFalse);
    expect(simple.shows(DecorAnchor.left), isTrue);
    expect(simple.shows(DecorAnchor.right), isTrue);
    // Half of the band is the limit.
    const frame = Size(1061, 407);
    DecorLayout lowered(double bottom) => DecorLayout(
      frame: frame,
      sheetAtRest: Rect.fromLTRB(266, 26, 792, bottom),
      decor: decor,
      decorSheet: decorSheet,
    );
    expect(lowered(377).under, isTrue);
    expect(lowered(392).under, isTrue);
    expect(lowered(393).under, isFalse);
    // Where the pieces are too small, nothing is shown, on any side.
    final ground = layout(const Size(844, 390), ratio: 2.4, padding: 8);
    expect(ground.pieces, isFalse);
    for (final anchor in DecorAnchor.values) {
      expect(ground.shows(anchor), isFalse);
    }
    // A layout that shows what lies under the sheet is not one that
    // leaves it out.
    expect(lowered(392) == lowered(393), isFalse);
  });

  group('a decor that is looked at without a sheet', () {
    // What lies under the sheet of the desk: an eraser, a brush.
    const middle = Rect.fromLTRB(435.5, 382, 627.5, 400.5);
    const leftSide = Rect.fromLTWH(0, 0, 266, 407);
    const rightSide = Rect.fromLTWH(792, 0, 269, 407);
    DecorLayout gaze(
      Size frame, {
      EdgeInsets safe = EdgeInsets.zero,
      Rect? under = middle,
      DecorGazeArrangement? arrangement,
    }) => DecorLayout.gaze(
      frame: frame,
      safe: safe,
      decor: decor,
      decorSheet: decorSheet,
      middle: under,
      arrangement: arrangement,
    );

    test('a tablet on its side: the two sides meet and fill the screen', () {
      const frame = Size(1366, 1024);
      final layout = gaze(frame);
      expect(layout.pieces, isTrue);
      expect(layout.arrangement, DecorGazeArrangement.beside);
      expect(layout.scale, closeTo(1024 / 407, 1e-9));
      final left = layout.place(leftSide, DecorAnchor.left);
      final right = layout.place(rightSide, DecorAnchor.right);
      // Each against its edge, on the bottom, at the full height; they
      // never cover one another.
      expect(left.left, 0);
      expect(right.right, closeTo(frame.width, 1e-9));
      expect(left.top, closeTo(0, 1e-9));
      expect(left.bottom, closeTo(frame.height, 1e-9));
      expect(right.bottom, closeTo(frame.height, 1e-9));
      expect(left.right, lessThanOrEqualTo(right.left + 1e-9));
      expect(right.left - left.right, lessThan(30));
      // No room between them for what lay under the sheet: it is left
      // out rather than laid over the sides.
      expect(layout.under, isFalse);
      expect(layout.shows(DecorAnchor.middle), isFalse);
      expect(layout.shows(DecorAnchor.left), isTrue);
      // One ground, on the whole frame, its middle in the middle.
      expect(layout.bands, hasLength(1));
      expect(layout.bands.single.rect, Offset.zero & frame);
      expect(
        layout.bands.single.groundLeft + 1061 * layout.scale / 2,
        closeTo(frame.width / 2, 1e-9),
      );
    });

    test('a telephone on its side: away from what the screen hides', () {
      const frame = Size(844, 390);
      const safe = EdgeInsets.only(left: 47, right: 47);
      final layout = gaze(frame, safe: safe);
      expect(layout.arrangement, DecorGazeArrangement.beside);
      expect(layout.scale, closeTo(390 / 407, 1e-9));
      final left = layout.place(leftSide, DecorAnchor.left);
      final right = layout.place(rightSide, DecorAnchor.right);
      expect(left.left, 47);
      expect(right.right, closeTo(844 - 47, 1e-9));
      // The pieces stand on the bottom edge with their ground: nothing is
      // kept away from the bottom.
      expect(left.bottom, closeTo(frame.height, 1e-9));
      // A wide wall between the sides: what lay under the sheet stands
      // there, in the middle of the screen.
      expect(layout.under, isTrue);
      final between = layout.place(middle, DecorAnchor.middle);
      expect(between.center.dx, closeTo(frame.width / 2, 1e-9));
      expect(between.left, greaterThan(left.right));
      expect(between.right, lessThan(right.left));
      expect(between.bottom, lessThanOrEqualTo(frame.height));
      // A decor with nothing under its sheet shows nothing there.
      expect(gaze(frame, safe: safe, under: null).under, isFalse);
    });

    test('a computer: the wall between the sides, wide or not enough', () {
      // 1440 × 900: the sides leave 116 units, the eraser and the brush
      // need 192 and a margin.
      final mac = gaze(const Size(1440, 900));
      expect(mac.scale, closeTo(900 / 407, 1e-9));
      expect(mac.under, isFalse);
      // A very wide window: they fit.
      final wide = gaze(const Size(2400, 900));
      expect(wide.under, isTrue);
      // The limit: the box and its margin on each side.
      const height = 407.0;
      double widthFor(double units) => 266 + 269 + units;
      expect(
        gaze(Size(widthFor(192 + 2 * DecorLayout.gazeMargin), height)).under,
        isTrue,
      );
      expect(
        gaze(Size(widthFor(192 + 2 * DecorLayout.gazeMargin - 1), height))
            .under,
        isFalse,
      );
    });

    test('a telephone held upright: one side above the other', () {
      const frame = Size(390, 844);
      const safe = EdgeInsets.only(top: 47);
      final layout = gaze(frame, safe: safe);
      expect(layout.arrangement, DecorGazeArrangement.stacked);
      expect(layout.scale, closeTo((844 - 47) / 2 / 407, 1e-9));
      final left = layout.place(leftSide, DecorAnchor.left);
      final right = layout.place(rightSide, DecorAnchor.right);
      // The left side above, against the left edge; the right side below,
      // against the right edge and on the bottom. Neither is cut.
      expect(left.left, 0);
      expect(right.right, closeTo(frame.width, 1e-9));
      expect(right.bottom, closeTo(frame.height, 1e-9));
      expect(left.bottom, closeTo(right.top, 1e-9));
      expect(left.top, greaterThanOrEqualTo(47 - 1e-9));
      expect(left.right, lessThanOrEqualTo(frame.width));
      expect(right.left, greaterThanOrEqualTo(0));
      // Each floor has its own ground; nothing is shown between them.
      expect(layout.bands, hasLength(2));
      expect(layout.bands.first.rect.bottom, closeTo(left.bottom, 1e-9));
      expect(layout.bands.last.rect.top, closeTo(right.top, 1e-9));
      expect(layout.bands.last.rect.bottom, frame.height);
      expect(layout.under, isFalse);
      // Much larger so than side by side, which is why.
      final beside = gaze(
        frame,
        safe: safe,
        arrangement: DecorGazeArrangement.beside,
      );
      expect(beside.arrangement, DecorGazeArrangement.beside);
      expect(layout.scale, greaterThan(beside.scale * 1.3));
      expect(beside.place(leftSide, DecorAnchor.left).bottom, frame.height);
    });

    test('a tablet held upright keeps the sides side by side', () {
      // One above the other they would not be fifteen hundredths larger:
      // side by side is how the decor was drawn.
      for (final frame in const [Size(1024, 1366), Size(744, 1133)]) {
        final layout = gaze(frame);
        expect(
          layout.arrangement,
          DecorGazeArrangement.beside,
          reason: '$frame',
        );
        expect(layout.scale, closeTo(frame.width / (266 + 269), 1e-9));
        final left = layout.place(leftSide, DecorAnchor.left);
        final right = layout.place(rightSide, DecorAnchor.right);
        expect(left.right, closeTo(right.left, 1e-6));
        expect(left.bottom, closeTo(frame.height, 1e-9));
        expect(left.top, greaterThan(0));
      }
      expect(DecorLayout.stackedGain, 1.15);
    });

    test('nothing goes beyond the screen, in any frame', () {
      for (final frame in const [
        Size(320, 568),
        Size(390, 844),
        Size(844, 390),
        Size(744, 1133),
        Size(1024, 1366),
        Size(1366, 1024),
        Size(1180, 820),
        Size(1440, 900),
        Size(1920, 1080),
        Size(3440, 1440),
        Size(500, 900),
        Size(900, 500),
      ]) {
        for (final safe in const [
          EdgeInsets.zero,
          EdgeInsets.only(left: 47, right: 47),
          EdgeInsets.only(top: 59),
        ]) {
          final layout = gaze(frame, safe: safe);
          expect(layout.pieces, isTrue, reason: '$frame');
          final room = Rect.fromLTRB(
            safe.left,
            safe.top,
            frame.width - safe.right,
            frame.height,
          ).inflate(1e-6);
          final left = layout.place(leftSide, DecorAnchor.left);
          final right = layout.place(rightSide, DecorAnchor.right);
          for (final box in [left, right]) {
            expect(
              room.contains(box.topLeft) && room.contains(box.bottomRight),
              isTrue,
              reason: '$frame, $safe : $box',
            );
          }
          // The two sides never cover one another.
          expect(left.overlaps(right.deflate(1e-6)), isFalse, reason: '$frame');
          if (layout.under) {
            final between = layout.place(middle, DecorAnchor.middle);
            expect(between.left, greaterThanOrEqualTo(left.right));
            expect(between.right, lessThanOrEqualTo(right.left));
          }
        }
      }
      expect(gaze(Size.zero).pieces, isFalse);
    });

    test(
      'two layouts of the same screen are the same, not that of a sheet',
      () {
        expect(gaze(const Size(1366, 1024)), gaze(const Size(1366, 1024)));
        expect(
          gaze(const Size(1366, 1024)).hashCode,
          gaze(const Size(1366, 1024)).hashCode,
        );
        expect(gaze(const Size(390, 844)), isNot(gaze(const Size(844, 390))));
        expect(
          gaze(const Size(390, 844)),
          isNot(
            gaze(
              const Size(390, 844),
              arrangement: DecorGazeArrangement.beside,
            ),
          ),
        );
        expect(gaze(decor), isNot(layout(decor)));
      },
    );
  });

  test('two layouts of the same frame are the same', () {
    expect(layout(const Size(1061, 407)), layout(const Size(1061, 407)));
    expect(layout(const Size(1061, 407)), isNot(layout(const Size(1062, 407))));
    expect(
      layout(const Size(900, 300)).hashCode,
      layout(const Size(900, 300)).hashCode,
    );
  });
}
