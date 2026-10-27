// SPDX-License-Identifier: MIT
// A stamp painted in its own colours only — the rainbow — shows nothing of
// the chosen colour: no gesture may pretend to give it one. Real Rust
// documents; only dialogs' destinations and storage are in memory.
import 'dart:io';

import 'package:edupaint_flutter_study/color_palette.dart';
import 'package:edupaint_flutter_study/stamp_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  // A large rainbow in the middle of the sheet, in the current colour.
  Future<void> poseRainbow(StudioDriver studio) async {
    await studio.tap('tool-stamp');
    await studio.tap('chooseStamp');
    await studio.tap('stamp-arcenciel');
    await studio.tap('size-large');
    await studio.click();
    studio.expectCount(1);
  }

  // The top of the outer bow of that rainbow: its box is 225 units wide
  // around (600, 400), and the bow is 30.5 % of the box under its top.
  Offset outerBow(StudioDriver studio) => studio.at(600, 356);

  bool swatchSelected(WidgetTester tester, String key) => tester
      .getSemantics(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(IconButton),
        ),
      )
      .flagsCollection
      .isSelected
      .toBoolOrNull()!;

  test('the rainbow alone keeps its own colours', () {
    final catalog = StampCatalog.instance;
    for (final stamp in catalog.stamps) {
      expect(stamp.takesColour, stamp.key != 'arcenciel', reason: stamp.key);
    }
  }, skip: !available);

  testWidgets(
    'the paint pot changes nothing on a rainbow, adds no step, and says why',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await poseRainbow(studio);
      final document = await studio.saved();
      try {
        expect(document.strokes.single.stamp, 23);
        expect(document.strokes.single.rgb, 0x477fb2);
      } finally {
        document.dispose();
      }
      expect(studio.isDirty, isFalse);
      final before = await studio.svg();

      await studio.tap('tool-fill');
      await studio.tap('color-d75e56');
      await studio.click(outerBow(studio));
      expect(find.text('Ce tampon garde ses couleurs.'), findsOneWidget);
      // Nothing to save, nothing new to see.
      expect(studio.isDirty, isFalse);
      expect(await studio.svg(), before);
      // The one step there is takes the rainbow away: none was added.
      await studio.tap('undo');
      studio.expectCount(0);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the paint pot still gives its colour to a stamp that takes one',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await studio.tap('tool-stamp');
      await studio.tap('size-large');
      await studio.click();
      await studio.tap('tool-fill');
      await studio.tap('color-d75e56');
      await studio.click();
      expect(find.text('Ce tampon garde ses couleurs.'), findsNothing);
      final document = await studio.saved();
      try {
        expect(document.strokes.single.stamp, 0);
        expect(document.strokes.single.rgb, 0xd75e56);
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a chosen rainbow keeps the current colour, and a clicked colour leaves it as it is',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await poseRainbow(studio);
      // Another colour becomes the current one.
      await studio.tap('color-eebf4e');
      await studio.tap('tool-select');
      await studio.click(outerBow(studio));
      final semantics = tester.ensureSemantics();
      try {
        expect(
          find.text('Glisse pour déplacer. Ce tampon garde ses couleurs.'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Glisse pour déplacer. Clique une couleur pour le colorier.',
          ),
          findsNothing,
        );
        // The colour hidden in the stamp did not replace the current one.
        expect(paintColorName(0xeebf4e), 'Soleil');
        expect(swatchSelected(tester, 'color-eebf4e'), isTrue);
        expect(swatchSelected(tester, 'color-477fb2'), isFalse);

        // Choosing a colour now is a choice for what comes next, not a
        // change of this stamp.
        await studio.tap('color-d75e56');
        expect(swatchSelected(tester, 'color-d75e56'), isTrue);
        expect(
          find.text('Glisse pour déplacer. Ce tampon garde ses couleurs.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('applySelectionStyle')), findsNothing);
      } finally {
        semantics.dispose();
      }
      // The stamp is still one element that moves and is copied as before.
      expect(studio.isDirty, isTrue);
      final document = await studio.saved();
      try {
        expect(document.strokes.single.rgb, 0x477fb2);
      } finally {
        document.dispose();
      }
      // The click on a colour was no edit: one step back, and the stamp
      // itself is gone.
      await studio.tap('undo');
      studio.expectCount(0);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a chosen stamp that takes a colour is coloured at once by a click on a colour',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await studio.tap('tool-stamp');
      await studio.tap('size-large');
      await studio.click();
      await studio.tap('color-eebf4e');
      await studio.tap('tool-select');
      await studio.click();
      final semantics = tester.ensureSemantics();
      try {
        expect(
          find.text(
            'Glisse pour déplacer. Clique une couleur pour le colorier.',
          ),
          findsOneWidget,
        );
        expect(swatchSelected(tester, 'color-477fb2'), isTrue);
        await studio.tap('color-d75e56');
        expect(swatchSelected(tester, 'color-d75e56'), isTrue);
        expect(find.byKey(const Key('applySelectionStyle')), findsNothing);
      } finally {
        semantics.dispose();
      }
      var document = await studio.saved();
      try {
        expect(document.strokes.single.rgb, 0xd75e56);
      } finally {
        document.dispose();
      }
      // One step for Annuler: the stamp is blue again.
      await studio.tap('undo');
      document = await studio.saved();
      try {
        expect(document.strokes.single.rgb, 0x477fb2);
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );
}
