// SPDX-License-Identifier: MIT
// Real Rust documents; only dialogs' destinations and storage are in memory.
import 'dart:io';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/text_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(Key(key))).onPressed != null;

  Future<StrokeData> single(StudioDriver studio) async {
    final document = await studio.saved();
    try {
      return document.strokes.single;
    } finally {
      document.dispose();
    }
  }

  testWidgets(
    'Plus grand and Plus petit resize a shape around its centre, one undo step each',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-rectangle');
      await studio.drag(studio.at(300, 300), studio.at(500, 400));
      await studio.tap('tool-select');
      // Nothing chosen: nothing to resize.
      expect(enabled(tester, 'growSelection'), isFalse);
      expect(enabled(tester, 'shrinkSelection'), isFalse);
      await studio.click(studio.at(300, 350));
      expect(enabled(tester, 'growSelection'), isTrue);
      expect(enabled(tester, 'shrinkSelection'), isTrue);
      expect(
        find.bySemanticsLabel('Rendre l’élément plus grand'),
        findsOneWidget,
      );

      await studio.tap('growSelection');
      var shape = await single(studio);
      // 200 × 100 around (400, 350) becomes 250 × 125 around the same centre.
      expect(left(shape), closeTo(275, .01));
      expect(top(shape), closeTo(287.5, .01));
      expect(right(shape), closeTo(525, .01));
      expect(bottom(shape), closeTo(412.5, .01));
      // The outline follows: 12 becomes 15, and the slider shows it.
      expect(shape.width, closeTo(15, .001));
      expect(find.text('15'), findsOneWidget);
      // The element stays chosen: the next notch applies to it at once.
      await studio.tap('shrinkSelection');
      await studio.tap('shrinkSelection');
      shape = await single(studio);
      expect(right(shape) - left(shape), closeTo(160, .01));
      expect(bottom(shape) - top(shape), closeTo(80, .01));
      expect(left(shape) + right(shape), closeTo(800, .01));
      expect(shape.width, closeTo(9.6, .001));

      await studio.tap('undo');
      await studio.tap('undo');
      shape = await single(studio);
      expect(right(shape) - left(shape), closeTo(250, .01));
      await studio.tap('undo');
      shape = await single(studio);
      expect(left(shape), closeTo(300, .01));
      expect(right(shape), closeTo(500, .01));
      expect(shape.width, 12);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a stamp keeps its drawing and a text is measured again at its new size',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stamp');
      await studio.click(studio.at(300, 400));
      await studio.addText('Bonjour', x: 600, y: 300);
      studio.expectCount(2);

      await studio.tap('tool-select');
      await studio.click(studio.at(300, 400));
      await studio.tap('growSelection');
      await studio.tap('tool-select');
      await studio.click(studio.at(620, 320));
      await studio.tap('growSelection');
      final document = await studio.saved();
      try {
        final stamp = document.strokes[0];
        final text = document.strokes[1];
        expect(stamp.kind, VectorKind.stamp);
        expect(stamp.stamp, 0);
        expect(stamp.width, 1);
        // 150 units become 187.5, around the point that was clicked.
        expect(right(stamp) - left(stamp), closeTo(187.5, .01));
        expect(left(stamp) + right(stamp), closeTo(600, .01));
        expect(top(stamp) + bottom(stamp), closeTo(800, .01));

        expect(text.text, 'Bonjour');
        expect(text.width, closeTo(70, .001));
        final layout = TextLayout('Bonjour', size: 70, rgb: text.rgb);
        expect(right(text) - left(text), closeTo(layout.width, .01));
        expect(bottom(text) - top(text), closeTo(layout.height, .01));
        // Its centre has not moved: the box grew on every side.
        final before = TextLayout('Bonjour', size: 56, rgb: text.rgb);
        expect(left(text) + right(text), closeTo(2 * 600 + before.width, .5));
        expect(top(text) + bottom(text), closeTo(2 * 300 + before.height, .5));
      } finally {
        document.dispose();
      }
      final exported = await studio.svg();
      expect(exported, contains('font-size="70"'));
      expect(exported, contains('scale(1.875 1.875)'));
      // One step per notch, text included.
      await studio.tap('undo');
      expect(await studio.svg(), contains('font-size="56"'));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the buttons stop where the element would leave the sheet or become too small',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stamp');
      await studio.tap('size-large');
      // In the corner: the stamp occupies 0..240.
      await studio.click(studio.at(5, 5));
      await studio.tap('tool-select');
      await studio.click(studio.at(100, 100));

      // 240 → 300 → 375 → 468.75 → 585.94 → 732.42: the sheet is 800 high.
      for (var notch = 0; notch < 5; notch++) {
        expect(enabled(tester, 'growSelection'), isTrue, reason: '$notch');
        await studio.tap('growSelection');
      }
      expect(enabled(tester, 'growSelection'), isFalse);
      var stamp = await single(studio);
      // Pushed back from the corner at every notch: still whole on the sheet.
      expect(left(stamp), 0);
      expect(top(stamp), 0);
      expect(right(stamp), closeTo(732.42, .01));
      expect(bottom(stamp), closeTo(732.42, .01));

      var notches = 0;
      while (enabled(tester, 'shrinkSelection')) {
        await studio.tap('shrinkSelection');
        notches++;
        expect(notches, lessThan(40));
      }
      stamp = await single(studio);
      final side = right(stamp) - left(stamp);
      // Small, but still easy to catch again; one more notch would go below.
      expect(side, greaterThanOrEqualTo(12));
      expect(side * .8, lessThan(12));
      expect(enabled(tester, 'growSelection'), isTrue);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a hand-drawn trait scales with all its points, and a dot by its width',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stroke');
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(400, 300),
      );
      await gesture.moveTo(studio.sheetCenter + studio.at(450, 380));
      await gesture.moveTo(studio.sheetCenter + studio.at(520, 320));
      await gesture.moveTo(studio.sheetCenter + studio.at(600, 400));
      await gesture.up();
      await tester.pumpAndSettle();
      var trait = await single(studio);
      final pointCount = trait.points.length;
      expect(pointCount, greaterThanOrEqualTo(4));

      await studio.tap('tool-select');
      await studio.click(studio.at(450, 380));
      await studio.tap('growSelection');
      trait = await single(studio);
      expect(trait.points, hasLength(pointCount));
      // 200 × 100 around (500, 350).
      expect(left(trait), closeTo(375, .5));
      expect(right(trait), closeTo(625, .5));
      expect(top(trait), closeTo(287.5, .5));
      expect(bottom(trait), closeTo(412.5, .5));

      // A dot: a single click of the brush, as wide as the brush is now.
      await studio.tap('deleteSelection');
      await studio.tap('tool-stroke');
      await studio.click(studio.at(700, 500));
      var dot = await single(studio);
      final drawn = dot.width;
      await studio.tap('tool-select');
      await studio.click(studio.at(700, 500));
      await studio.tap('growSelection');
      dot = await single(studio);
      expect(dot.points, hasLength(1));
      expect(dot.points.single.x, closeTo(700, .5));
      // It has no size of its own: its width is what grows.
      expect(dot.width, closeTo(drawn * 1.25, .001));
      // Up to the widest brush, then no further.
      var notches = 0;
      while (enabled(tester, 'growSelection')) {
        await studio.tap('growSelection');
        notches++;
        expect(notches, lessThan(20));
      }
      dot = await single(studio);
      expect(dot.width, 48);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a colour and a size given to the chosen element are separate steps; the menu offers the same notches',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-rectangle');
      await studio.drag(studio.at(300, 300), studio.at(500, 400));
      expect(studio.menu.onGrow, isNull);
      expect(studio.menu.onShrink, isNull);
      await studio.tap('tool-select');
      await studio.click(studio.at(300, 350));
      studio.menu.onGrow!();
      await tester.pumpAndSettle();
      var shape = await single(studio);
      expect(shape.rgb, 0x477fb2);
      expect(right(shape) - left(shape), closeTo(250, .01));
      // The colour is on the element at once, which keeps its new size.
      await studio.tap('color-d75e56');
      shape = await single(studio);
      expect(shape.rgb, 0xd75e56);
      expect(right(shape) - left(shape), closeTo(250, .01));
      studio.menu.onShrink!();
      await tester.pumpAndSettle();
      shape = await single(studio);
      expect(shape.rgb, 0xd75e56);
      expect(right(shape) - left(shape), closeTo(200, .01));
      // Three steps: larger, colour, smaller.
      for (var step = 0; step < 3; step++) {
        await studio.tap('undo');
      }
      shape = await single(studio);
      expect(shape.rgb, 0x477fb2);
      expect(shape.width, 12);
      expect(left(shape), closeTo(300, .01));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the resize buttons are full-size targets in a small window with enlarged text',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(680, 520), textScale: 1.5);
      await studio.tap('tool-stamp');
      await studio.click();
      await studio.tap('tool-select');
      await studio.click();
      for (final key in ['shrinkSelection', 'growSelection']) {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.width, greaterThanOrEqualTo(48), reason: key);
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }
      final shrink = tester.getRect(find.byKey(const Key('shrinkSelection')));
      final grow = tester.getRect(find.byKey(const Key('growSelection')));
      expect(grow.left - shrink.right, greaterThanOrEqualTo(4));
      await studio.tap('growSelection');
      final stamp = await single(studio);
      expect(right(stamp) - left(stamp), closeTo(187.5, .01));
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );
}
