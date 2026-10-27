// SPDX-License-Identifier: MIT
// The row of colours in the real studio, with a real Rust document; only
// dialogs' destinations and storage are in memory.
import 'dart:io';
import 'dart:math' as math;

import 'package:edupaint_flutter_study/color_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  const allColors = [...paintColors, ...morePaintColors];

  // The swatches of the row that are on screen, from left to right.
  List<(NamedPaintColor, Rect)> row(WidgetTester tester) {
    final found = <(NamedPaintColor, Rect)>[
      for (final color in allColors)
        if (find
            .byKey(Key('color-${color.rgb.toRadixString(16)}'))
            .evaluate()
            .isNotEmpty)
          (
            color,
            tester.getRect(
              find.byKey(Key('color-${color.rgb.toRadixString(16)}')),
            ),
          ),
    ];
    found.sort((a, b) => a.$2.left.compareTo(b.$2.left));
    return found;
  }

  testWidgets(
    'in the studio the row of colours fills its panel at every window width',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      var widest = 0;
      for (final size in const [
        Size(680, 520),
        Size(760, 580),
        Size(1000, 700),
        Size(1280, 720),
        Size(1280, 820),
        Size(1512, 900),
        Size(1728, 1000),
        Size(2400, 1200),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');
        final swatches = row(tester);
        // The first ten never leave, in their order; the others follow in
        // theirs.
        expect(swatches.length, greaterThanOrEqualTo(10), reason: '$size');
        expect(
          swatches.map((entry) => entry.$1.rgb),
          allColors.take(swatches.length).map((color) => color.rgb),
          reason: '$size',
        );
        expect(swatches.map((entry) => entry.$2.top).toSet(), hasLength(1));
        // From one edge of the panel to the other: the row is as wide as
        // the line of controls above it, whose last button ends the panel.
        final line = tester.getRect(find.byKey(const Key('paintColorRow')));
        final more = tester.getRect(find.byKey(const Key('morePaintColors')));
        expect(
          swatches.first.$2.left,
          moreOrLessEquals(line.left, epsilon: .01),
        );
        expect(
          swatches.last.$2.right,
          moreOrLessEquals(line.right, epsilon: .01),
        );
        expect(line.right, moreOrLessEquals(more.right, epsilon: .01));
        // As many as the width takes, no fewer: the row counts them itself
        // with the gap of its form, 8 under a low window and 9 otherwise.
        final gap = swatches[1].$2.left - swatches[0].$2.right;
        expect(gap, greaterThanOrEqualTo(8 - .01), reason: '$size');
        expect(
          swatches.length,
          anyOf(
            paletteRowCount(line.width, 8).clamp(0, allColors.length),
            paletteRowCount(line.width, 9).clamp(0, allColors.length),
          ),
          reason: '$size',
        );
        widest = math.max(widest, swatches.length);
      }
      // The widest of these windows shows every colour.
      expect(widest, allColors.length);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a colour that joined the row draws, fills and is reopened like the first ten',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      // At the first size of the window on a Mac, the row has room for
      // more than the first ten.
      expect(find.byKey(const Key('color-ef9439')), findsOneWidget);
      expect(find.byTooltip('Orange'), findsOneWidget);
      await studio.tap('color-ef9439');
      await studio.drag(const Offset(-80, -30), const Offset(60, 40));
      studio.expectCount(1);
      await studio.tap('tool-rectangle');
      await studio.tap('paint-target-fill');
      await studio.tap('color-79513e');
      await studio.drag(const Offset(-150, -90), const Offset(-60, -40));
      studio.expectCount(2);
      final exported = await studio.svg();
      expect(exported, contains('stroke="#ef9439"'));
      expect(exported, contains('fill="#79513e"'));
      final document = await studio.saved();
      try {
        expect(document.strokes.first.rgb, 0xef9439);
        expect(document.strokes.last.fillRgb, 0x79513e);
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  // A window that becomes much wider or narrower at once gives the column of
  // the sheet neighbours on both sides. The colour dialog opened from the
  // palette must still deliver its answer afterwards.
  for (final (from, to) in const [
    (Size(700, 620), Size(1300, 820)),
    (Size(1300, 820), Size(700, 620)),
    (Size(680, 520), Size(2400, 1200)),
    (Size(1000, 700), Size(1280, 820)),
  ]) {
    testWidgets(
      'a colour confirmed after the window went from $from to $to is the current colour',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start(size: from);
        await studio.tap('morePaintColors');
        expect(find.byKey(const Key('paintColorDialog')), findsOneWidget);
        tester.view.physicalSize = to;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('paintColorDialog')), findsOneWidget);
        await studio.tap('shade-e83d48');
        await studio.tap('confirmPaintColor');
        await studio.tap('tool-stroke');
        await studio.drag(const Offset(-40, -20), const Offset(30, 20));
        final document = await studio.saved();
        try {
          expect(document.strokes.single.rgb, 0xe83d48);
        } finally {
          document.dispose();
        }
        await studio.finish();
      },
      skip: !available,
    );
  }
}
