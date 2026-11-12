// SPDX-License-Identifier: MIT
// Where a decor stands in the frame of the sheet (Color 1.2): each side
// against its edge, everything on the bottom, as large as the height
// allows; smaller when the sheet leaves less room than it was drawn for —
// a child must see everything; only its ground where it would be too small.
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

  DecorLayout layout(Size frame, {double ratio = 1.5}) => DecorLayout(
    frame: frame,
    sheetAtRest: sheetIn(frame, ratio: ratio),
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

  test('where even half its size would not fit, only the ground is shown', () {
    // A tall frame that the sheet fills from side to side.
    const frame = Size(790, 520);
    final none = layout(frame);
    expect(none.pieces, isFalse);
    // The ground then fills the height.
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

  test('two layouts of the same frame are the same', () {
    expect(layout(const Size(1061, 407)), layout(const Size(1061, 407)));
    expect(layout(const Size(1061, 407)), isNot(layout(const Size(1062, 407))));
    expect(
      layout(const Size(900, 300)).hashCode,
      layout(const Size(900, 300)).hashCode,
    );
  });
}
