// SPDX-License-Identifier: MIT
// Defects found by the independent review of Color 0.7.0. Each test failed
// before its correction. Real Rust documents; the studio is driven as a child
// drives it: presses that last more than one frame, the letters of the
// interface instead of the squares of the test font where the layout
// matters, and the desktop platforms the program ships on.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/interface_font.dart';
import 'support/studio_driver.dart';

// A filled rectangle between two points of the sheet, outline and inside in
// one colour of the palette.
Future<void> filled(
  StudioDriver studio,
  String color,
  Offset from,
  Offset to,
) async {
  await studio.tap('tool-rectangle');
  await studio.tap('paint-target-stroke');
  await studio.tap('color-$color');
  await studio.tap('paint-target-fill');
  await studio.tap('color-$color');
  await studio.drag(studio.at(from.dx, from.dy), studio.at(to.dx, to.dy));
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  final desktop = TargetPlatformVariant.desktop();

  group('the sheet holds still under a pointer', () {
    testWidgets(
      'a click that chooses an element does not move it',
      (tester) async {
        await loadInterfaceFont(tester);
        final studio = StudioDriver(tester);
        // In this window, choosing an element changes the controls under the
        // sheet, and with them the room left to it.
        await studio.start(size: const Size(780, 800));
        await studio.tap('tool-rectangle');
        await studio.drag(studio.at(200, 200), studio.at(400, 400));
        await studio.tap('saveProject');
        await studio.tap('tool-select');
        // Press, two frames, release at the very same place.
        final press = await tester.startGesture(
          studio.sheetCenter + studio.at(200, 300),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 80));
        await press.up();
        await tester.pumpAndSettle();
        expect(studio.isDirty, isFalse, reason: 'choosing is not an edit');
        expect(find.byKey(const Key('deleteSelection')), findsOneWidget);
        final document = await studio.saved();
        try {
          expect(left(document.strokes.single), closeTo(200, .01));
          expect(top(document.strokes.single), closeTo(200, .01));
        } finally {
          document.dispose();
        }
        await studio.finish();
      },
      skip: !available,
      variant: desktop,
    );

    testWidgets(
      'a trait drawn at one height stays straight when the sentence under the sheet changes',
      (tester) async {
        await loadInterfaceFont(tester);
        final studio = StudioDriver(tester);
        await studio.start(size: const Size(780, 800), textScale: 2);
        await studio.tap('tool-stroke');
        final first = await tester.startGesture(
          studio.sheetCenter + studio.at(300, 300),
        );
        await first.moveTo(studio.sheetCenter + studio.at(500, 300));
        await first.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // The next trait starts at once and lasts 600 ms: the recovery copy
        // of the first one is written meanwhile, and the sentence changes.
        final start = studio.sheetCenter + studio.at(300, 500);
        final step = studio.at(350, 500) - studio.at(300, 500);
        final second = await tester.startGesture(start);
        for (var steps = 1; steps <= 12; steps++) {
          await tester.pump(const Duration(milliseconds: 50));
          await second.moveTo(start + step * steps.toDouble());
        }
        await second.up();
        await tester.pumpAndSettle();
        final document = await studio.saved();
        try {
          expect(document.strokes, hasLength(2));
          final stroke = document.strokes.last;
          expect(bottom(stroke) - top(stroke), lessThan(1));
          expect(right(stroke) - left(stroke), closeTo(600, 1));
        } finally {
          document.dispose();
        }
        await studio.finish();
      },
      skip: !available,
      variant: desktop,
    );

    testWidgets(
      'a window resized during a gesture moves nothing; the view follows once the pointer is up',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start(size: const Size(1100, 760));
        await studio.tap('tool-rectangle');
        await studio.drag(studio.at(200, 200), studio.at(400, 400));
        await studio.tap('saveProject');
        await studio.tap('tool-select');
        final where = studio.sheetCenter + studio.at(200, 300);
        final press = await tester.startGesture(where);
        await tester.pump();
        tester.view.physicalSize = const Size(1000, 700);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await press.up();
        await tester.pumpAndSettle();
        expect(studio.isDirty, isFalse);

        // A trait drawn across the same change of size has no kink either.
        await studio.tap('tool-stroke');
        final start = studio.sheetCenter + const Offset(-150, 40);
        final trait = await tester.startGesture(start);
        await trait.moveBy(const Offset(40, 0));
        await tester.pump();
        tester.view.physicalSize = const Size(1100, 760);
        await tester.pump();
        await trait.moveBy(const Offset(40, 0));
        await trait.moveBy(const Offset(40, 0));
        await trait.up();
        await tester.pumpAndSettle();

        // The pointer is up: the sheet is fitted to the window again, and a
        // rectangle drawn now lands where the fitted view says.
        await studio.tap('tool-rectangle');
        await studio.drag(studio.at(700, 500), studio.at(900, 700));
        final document = await studio.saved();
        try {
          expect(document.strokes, hasLength(3));
          expect(left(document.strokes[0]), closeTo(200, .01));
          expect(top(document.strokes[0]), closeTo(200, .01));
          final stroke = document.strokes[1];
          expect(bottom(stroke) - top(stroke), lessThan(.01));
          expect(right(stroke) - left(stroke), greaterThan(50));
          expect(left(document.strokes[2]), closeTo(700, .5));
          expect(top(document.strokes[2]), closeTo(500, .5));
          expect(right(document.strokes[2]), closeTo(900, .5));
          expect(bottom(document.strokes[2]), closeTo(700, .5));
        } finally {
          document.dispose();
        }
        await studio.finish();
      },
      skip: !available,
    );

    testWidgets(
      'the view follows a window resized while the hand tool held the sheet',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start(size: const Size(1100, 760));
        await studio.tap('panPage');
        final hold = await tester.startGesture(studio.sheetCenter);
        await tester.pump();
        tester.view.physicalSize = const Size(900, 700);
        await tester.pump();
        await hold.up();
        await tester.pumpAndSettle();
        // Nothing was slid: the sheet is still shown whole, fitted to the
        // window as it is now.
        expect(find.text('Toute la feuille'), findsOneWidget);
        await studio.tap('panPage');
        await studio.tap('tool-rectangle');
        await studio.drag(studio.at(100, 100), studio.at(300, 300));
        final document = await studio.saved();
        try {
          expect(left(document.strokes.single), closeTo(100, .5));
          expect(bottom(document.strokes.single), closeTo(300, .5));
        } finally {
          document.dispose();
        }
        await studio.finish();
      },
      skip: !available,
    );
  });

  group('what is under the pointer answers, not its neighbour', () {
    testWidgets('the eraser and Choisir take the element under the pointer', (
      tester,
    ) async {
      final studio = StudioDriver(tester);
      await studio.start();
      // Red, drawn first; blue in front, beside it: white paper in between.
      await filled(
        studio,
        'd75e56',
        const Offset(200, 300),
        const Offset(400, 500),
      );
      await filled(
        studio,
        '477fb2',
        const Offset(430, 300),
        const Offset(630, 500),
      );
      final png = await studio.png();
      expect(await studio.pixel(png, 398, 400), [0xd7, 0x5e, 0x56, 255]);
      expect(await studio.pixel(png, 415, 400), [255, 255, 255, 255]);
      // (398, 400) is in the red rectangle, a few screen pixels from the
      // outline of the blue one.
      await studio.tap('tool-select');
      await studio.click(studio.at(398, 400));
      await studio.tap('deleteSelection');
      var document = await studio.saved();
      try {
        expect(document.strokes.single.rgb, 0x477fb2);
      } finally {
        document.dispose();
      }
      await studio.tap('undo');
      await studio.tap('tool-eraser');
      await studio.click(studio.at(398, 400));
      document = await studio.saved();
      try {
        expect(document.strokes.single.rgb, 0x477fb2);
      } finally {
        document.dispose();
      }
      // Between the two, on bare paper, the nearest one still answers: a
      // thin outline stays easy to catch.
      await studio.click(studio.at(415, 400));
      studio.expectCount(0);
      await studio.finish();
    }, skip: !available);

    testWidgets(
      'the pot colours what is seen under the pointer, and paper beside a shape',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start();
        await studio.tap('tool-stamp');
        await studio.click(studio.at(600, 400));
        // A frame drawn around the star afterwards.
        await studio.tap('tool-rectangle');
        await studio.drag(studio.at(300, 200), studio.at(900, 600));
        await studio.tap('tool-fill');
        await studio.tap('color-d75e56');
        await studio.click(studio.at(600, 400));
        var document = await studio.saved();
        try {
          expect(document.strokes[1].fillRgb, isNull);
          expect(document.strokes[0].rgb, 0xd75e56);
          expect(document.paperRgb, 0xffffff);
        } finally {
          document.dispose();
        }
        // Bare paper just outside the frame: the sheet takes the colour, the
        // frame stays hollow.
        await studio.tap('color-eebf4e');
        await studio.click(studio.at(275, 400));
        document = await studio.saved();
        try {
          expect(document.paperRgb, 0xeebf4e);
          expect(document.strokes[1].fillRgb, isNull);
        } finally {
          document.dispose();
        }
        await studio.finish();
      },
      skip: !available,
    );

    testWidgets(
      'a frame filled by the pot goes behind what it was drawn around',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start();
        await studio.tap('color-33484d');
        await studio.addText('MMM', x: 500, y: 350);
        await studio.tap('tool-rectangle');
        await studio.tap('color-477fb2');
        await studio.drag(studio.at(300, 200), studio.at(900, 600));
        await studio.tap('tool-fill');
        await studio.tap('color-eebf4e');
        // In the empty part of the frame, away from the text.
        await studio.click(studio.at(350, 550));
        final png = await studio.png();
        // The inside is there, and the letters are still seen on it.
        expect(await studio.pixel(png, 350, 550), [0xee, 0xbf, 0x4e, 255]);
        expect(await studio.pixel(png, 520, 380), [0x33, 0x48, 0x4d, 255]);
        final document = await studio.saved();
        try {
          expect(document.strokes[0].fillRgb, 0xeebf4e);
          expect(document.strokes[0].rgb, 0x477fb2);
          expect(document.strokes[1].text, 'MMM');
        } finally {
          document.dispose();
        }
        // Annuler takes the colour away, then puts the frame back in front.
        await studio.tap('undo');
        expect(studio.isDirty, isTrue);
        await studio.tap('undo');
        final back = await studio.saved();
        try {
          expect(back.strokes[1].kind.name, 'rectangle');
          expect(back.strokes[1].fillRgb, isNull);
        } finally {
          back.dispose();
        }
        await studio.finish();
      },
      skip: !available,
    );

    testWidgets(
      'a sun drawn on a sky is filled, not the sky; a square inside a large frame keeps the click',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start();
        // The sky: a filled rectangle. The sun: a hollow oval on it.
        await filled(
          studio,
          '477fb2',
          const Offset(100, 100),
          const Offset(1100, 500),
        );
        await studio.tap('tool-ellipse');
        await studio.tap('fillShapeCheckbox');
        await studio.tap('color-33484d');
        await studio.drag(studio.at(700, 150), studio.at(900, 350));
        await studio.tap('tool-fill');
        await studio.tap('color-eebf4e');
        await studio.click(studio.at(800, 250));
        var document = await studio.saved();
        try {
          expect(document.strokes[0].fillRgb, 0x477fb2);
          // The oval stays in front of the sky, with its new inside.
          expect(document.strokes[1].kind.name, 'ellipse');
          expect(document.strokes[1].fillRgb, 0xeebf4e);
        } finally {
          document.dispose();
        }
        // Nothing had to move: one step for Annuler.
        await studio.tap('undo');
        document = await studio.saved();
        try {
          expect(document.strokes, hasLength(2));
          expect(document.strokes[1].fillRgb, isNull);
        } finally {
          document.dispose();
        }
        await studio.tap('redo');
        final png = await studio.png();
        expect(await studio.pixel(png, 800, 250), [0xee, 0xbf, 0x4e, 255]);
        expect(await studio.pixel(png, 300, 300), [0x47, 0x7f, 0xb2, 255]);

        // A large hollow frame drawn last around the whole picture: a click
        // on the sun colours the sun, the smaller of the two.
        await studio.tap('tool-rectangle');
        await studio.drag(studio.at(50, 50), studio.at(1150, 750));
        await studio.tap('tool-fill');
        await studio.tap('color-d75e56');
        await studio.click(studio.at(800, 250));
        document = await studio.saved();
        try {
          expect(document.strokes[1].fillRgb, 0xd75e56);
          expect(document.strokes[2].fillRgb, isNull);
        } finally {
          document.dispose();
        }
        await studio.finish();
      },
      skip: !available,
    );

    testWidgets('one eraser gesture leaves what it has just uncovered', (
      tester,
    ) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stamp');
      await studio.tap('size-small');
      await studio.click(studio.at(500, 400));
      await studio.click(studio.at(700, 400));
      // A filled rectangle drawn afterwards hides both stamps.
      await filled(
        studio,
        'eebf4e',
        const Offset(200, 200),
        const Offset(1000, 600),
      );
      studio.expectCount(3);
      await studio.tap('tool-eraser');
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(300, 400),
      );
      await tester.pump();
      // The rectangle went at the press; the glide then crosses both stamps.
      studio.expectCount(2);
      await gesture.moveTo(studio.sheetCenter + studio.at(900, 400));
      await gesture.up();
      await tester.pumpAndSettle();
      studio.expectCount(2);
      // The next gesture points at one of them: it goes.
      await studio.click(studio.at(500, 400));
      studio.expectCount(1);
      await studio.finish();
    }, skip: !available);

    testWidgets(
      'an eraser glide that starts beside the sheet erases what it crosses',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start();
        await studio.tap('tool-stamp');
        await studio.click(studio.at(150, 400));
        await studio.tap('tool-eraser');
        final gesture = await tester.startGesture(
          studio.sheetCenter + studio.at(-40, 400),
        );
        await gesture.moveTo(studio.sheetCenter + studio.at(150, 400));
        await gesture.moveTo(studio.sheetCenter + studio.at(400, 400));
        await gesture.up();
        await tester.pumpAndSettle();
        studio.expectCount(0);
        await studio.finish();
      },
      skip: !available,
    );

    testWidgets('the pipette takes the colour seen under the pointer', (
      tester,
    ) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await filled(
        studio,
        'd75e56',
        const Offset(300, 200),
        const Offset(900, 600),
      );
      await studio.tap('tool-stamp');
      await studio.tap('color-477fb2');
      // A blue star on the red rectangle: its box is 525..675 × 325..475.
      await studio.click(studio.at(600, 400));
      final png = await studio.png();
      // In the corner of its box the star paints nothing: red is seen there.
      expect(await studio.pixel(png, 530, 330), [0xd7, 0x5e, 0x56, 255]);
      await studio.tap('tool-stroke');
      await studio.tap('color-33484d');
      await studio.tap('pickPaintColor');
      await studio.click(studio.at(530, 330));
      await studio.drag(studio.at(100, 700), studio.at(160, 720));
      // On the star itself, its own blue.
      expect(await studio.pixel(png, 600, 420), [0x47, 0x7f, 0xb2, 255]);
      await studio.tap('pickPaintColor');
      await studio.click(studio.at(600, 420));
      await studio.drag(studio.at(100, 750), studio.at(160, 770));
      final document = await studio.saved();
      try {
        expect(document.strokes[2].rgb, 0xd75e56);
        expect(document.strokes[3].rgb, 0x477fb2);
      } finally {
        document.dispose();
      }
      await studio.finish();
    }, skip: !available);

    testWidgets(
      'a palette colour chosen while the pipette waits is the colour drawn with',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start();
        await studio.tap('tool-rectangle');
        await studio.tap('color-d75e56');
        await studio.drag(studio.at(200, 200), studio.at(500, 450));
        await studio.tap('tool-stroke');
        await studio.tap('pickPaintColor');
        // The child prefers a colour of the palette after all, and draws.
        await studio.tap('color-78a66f');
        await studio.drag(studio.at(200, 300), studio.at(600, 300));
        final document = await studio.saved();
        try {
          expect(document.strokes, hasLength(2));
          expect(document.strokes.last.rgb, 0x78a66f);
        } finally {
          document.dispose();
        }
        await studio.finish();
      },
      skip: !available,
    );

    testWidgets(
      'a click beside the sheet while the pipette waits keeps the chosen element',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start();
        await filled(
          studio,
          'd75e56',
          const Offset(300, 200),
          const Offset(600, 500),
        );
        await studio.tap('tool-select');
        await studio.click(studio.at(450, 350));
        bool chosen() =>
            tester
                .widget<OutlinedButton>(
                  find.byKey(const Key('deleteSelection')),
                )
                .onPressed !=
            null;
        expect(chosen(), isTrue);
        await studio.tap('pickPaintColor');
        // In the margin of the sheet's area, beside the paper.
        final surface = tester.getRect(find.byKey(const Key('drawingSurface')));
        await tester.tapAt(surface.centerLeft + const Offset(6, 0));
        await tester.pumpAndSettle();
        expect(chosen(), isTrue);
        // The pipette still waits; Échap sends it away and keeps the rest.
        bool waiting() => tester
            .widget<IconButton>(find.byKey(const Key('pickPaintColor')))
            .isSelected!;
        expect(waiting(), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(waiting(), isFalse);
        expect(chosen(), isTrue);
        // Nothing was edited meanwhile: the element is as it was drawn.
        final document = await studio.saved();
        try {
          expect(document.strokes.single.rgb, 0xd75e56);
        } finally {
          document.dispose();
        }
        await studio.finish();
      },
      skip: !available,
    );
  });

  group('one dialog at a time, and nothing typed is thrown away', () {
    testWidgets(
      'F1 or Enregistrer while the text tool is pressed open no text dialog',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start();
        await studio.tap('tool-text');
        var gesture = await tester.startGesture(
          studio.sheetCenter + studio.at(300, 300),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await tester.pumpAndSettle();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byKey(const Key('helpDialog')), findsOneWidget);
        await studio.tap('closeHelp');
        expect(find.byType(AlertDialog), findsNothing);
        // The studio answers again: one click, one dialog.
        await studio.click(studio.at(300, 300));
        expect(find.byKey(const Key('textDialog')), findsOneWidget);
        await studio.tap('cancelText');

        gesture = await tester.startGesture(
          studio.sheetCenter + studio.at(300, 300),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('textDialog')), findsNothing);
        expect(studio.files.projects, hasLength(1));
        expect(tester.takeException(), isNull);
        await studio.finish();
      },
      skip: !available,
    );

    testWidgets('a sentence wider than the sheet is posed on several lines', (
      tester,
    ) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-text');
      await studio.click(studio.at(100, 100));
      const sentence = 'Il était une fois un petit chat qui dormait au soleil';
      await studio.write(sentence);
      await studio.tap('confirmText');
      expect(find.byKey(const Key('textDialog')), findsNothing);
      studio.expectCount(1);
      final document = await studio.saved();
      try {
        final text = document.strokes.single;
        // Broken between words only: every word is there, in order.
        expect(text.text, contains('\n'));
        expect(text.text!.replaceAll('\n', ' '), sentence);
        // As close to the click as its width allows, whole on the sheet.
        expect(right(text), lessThanOrEqualTo(1200));
        expect(left(text), inInclusiveRange(0, 100));
        expect(top(text), closeTo(100, .01));
      } finally {
        document.dispose();
      }
      await studio.finish();
    }, skip: !available);

    testWidgets(
      'a colour given to a chosen text stays through Modifier and a move to another layer',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start();
        await studio.addText('Bonjour', x: 300, y: 300);
        await studio.layers(() => studio.tap('addLayer'));
        await studio.tap('tool-select');
        await studio.click(studio.at(320, 320));
        // The text is red at once; no button waits to be pressed.
        await studio.tap('color-d75e56');
        expect(find.byKey(const Key('applySelectionStyle')), findsNothing);
        await studio.tap('editSelectionText');
        await studio.write('Salut');
        await studio.tap('confirmText');
        await tester.tap(find.byKey(const Key('selectionOrder')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('moveSelectionLayerUp')));
        await tester.pumpAndSettle();
        final document = await studio.saved();
        try {
          final text = document.strokes.single;
          expect(text.text, 'Salut');
          expect(text.rgb, 0xd75e56);
          expect(text.layer, document.layers.last.id);
        } finally {
          document.dispose();
        }
        await studio.finish();
      },
      skip: !available,
    );
  });

  testWidgets(
    'Tout devant and Tout derrière are offered only among the elements of one layer',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await filled(
        studio,
        'd75e56',
        const Offset(200, 200),
        const Offset(500, 500),
      );
      await studio.layers(() => studio.tap('addLayer'));
      await filled(
        studio,
        '477fb2',
        const Offset(400, 400),
        const Offset(700, 700),
      );
      await studio.tap('saveProject');
      await studio.tap('tool-select');
      // The red one, alone on its layer: no order to change there.
      await studio.click(studio.at(250, 250));
      expect(studio.menu.onBringToFront, isNull);
      expect(studio.menu.onSendToBack, isNull);
      await tester.tap(find.byKey(const Key('selectionOrder')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PopupMenuItem<Object?>>(
              find.byKey(const Key('bringSelectionToFront')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<PopupMenuItem<Object?>>(
              find.byKey(const Key('sendSelectionToBack')),
            )
            .enabled,
        isFalse,
      );
      // Its layer can still change.
      await tester.tap(find.byKey(const Key('moveSelectionLayerUp')));
      await tester.pumpAndSettle();
      // Now the two share a layer: the red one, moved last, is in front and
      // can go behind.
      expect(studio.menu.onBringToFront, isNull);
      expect(studio.menu.onSendToBack, isNotNull);
      final png = await studio.png();
      expect(await studio.pixel(png, 450, 450), [0xd7, 0x5e, 0x56, 255]);
      await studio.finish();
    },
    skip: !available,
  );

  group('controls a child can hit, on the desktop too', () {
    for (final size in [const Size(1280, 720), const Size(700, 620)]) {
      testWidgets(
        'every control is at least 48 pixels in a ${size.width.round()} × ${size.height.round()} window',
        (tester) async {
          await loadInterfaceFont(tester);
          final studio = StudioDriver(tester);
          await studio.start(size: size);
          final small = <String, String>{};
          void measure(Iterable<String> keys) {
            for (final key in keys) {
              final control = find.byKey(Key(key));
              expect(control, findsOneWidget, reason: key);
              final measured = tester.getSize(control);
              if (measured.width < 48 || measured.height < 48) {
                small[key] =
                    '${measured.width.round()} × ${measured.height.round()}';
              }
            }
          }

          measure([
            'newProject',
            'openProject',
            'saveProject',
            'exportImage',
            'printDrawing',
            // A narrow window folds the help and the album into a menu.
            size.width < 750 ? 'moreFileActions' : 'showHelp',
            'undo',
            'redo',
            'layersButton',
            'zoomIn',
            'zoomOut',
            'fitPage',
            'panPage',
            'bigSheet',
            'pickPaintColor',
            'morePaintColors',
            'color-d75e56',
            for (final tool in [
              'stroke',
              'line',
              'rectangle',
              'ellipse',
              'text',
              'stamp',
              'fill',
              'eraser',
              'select',
            ])
              'tool-$tool',
          ]);
          await studio.tap('tool-rectangle');
          measure([
            'fillShapeCheckbox',
            'paint-target-stroke',
            'paint-target-fill',
          ]);
          await studio.drag(studio.at(200, 200), studio.at(500, 500));
          await studio.addText('mot', x: 700, y: 300);
          await studio.tap('tool-select');
          await studio.click(studio.at(720, 320));
          measure([
            'editSelectionText',
            'duplicateSelection',
            'deleteSelection',
            'selectionOrder',
            'growSelection',
            'shrinkSelection',
          ]);
          await studio.tap('tool-text');
          measure(['size-small', 'size-medium', 'size-large']);
          await studio.click();
          measure([
            'cancelText',
            'confirmText',
            'textDialogSize-small',
            'textDialogSize-medium',
            'textDialogSize-large',
          ]);
          await studio.tap('cancelText');
          await studio.tap('layersButton');
          measure([
            'addLayer',
            'closeLayers',
            'layer-visible-0',
            'layer-select-0',
          ]);
          await studio.tap('closeLayers');
          await studio.tap('tool-stamp');
          measure(['chooseStamp']);
          await studio.tap('chooseStamp');
          measure(['cancelStamp']);
          await studio.tap('cancelStamp');
          await tester.sendKeyEvent(LogicalKeyboardKey.f1);
          await tester.pumpAndSettle();
          measure(['closeHelp']);
          await studio.tap('closeHelp');
          await studio.tap('newProject');
          measure([
            'newSheet-landscape',
            'newSheet-portrait',
            'newSheet-square',
            'cancelNewSheet',
            'createNewSheet',
          ]);
          await studio.tap('cancelNewSheet');
          await studio.tap('exportImage');
          measure(['exportSvg', 'exportPng', 'pngScale2']);
          expect(small, isEmpty);
          expect(tester.takeException(), isNull);
          await studio.finish();
        },
        skip: !available,
        variant: desktop,
      );
    }

    testWidgets(
      'a click that trembles by a few pixels still poses the chosen stamp',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start(size: const Size(1280, 720));
        await studio.tap('tool-stamp');
        final gesture = await tester.startGesture(
          studio.sheetCenter + studio.at(600, 400),
        );
        await gesture.moveBy(const Offset(8, 5));
        await gesture.up();
        await tester.pumpAndSettle();
        // A longer drag still sizes the stamp.
        final drag = await tester.startGesture(
          studio.sheetCenter + studio.at(200, 200),
        );
        await drag.moveBy(const Offset(40, 30));
        await drag.up();
        await tester.pumpAndSettle();
        final document = await studio.saved();
        try {
          final stamp = document.strokes.first;
          expect(right(stamp) - left(stamp), closeTo(150, .01));
          final sized = document.strokes.last;
          expect(left(sized), closeTo(200, .5));
          expect(
            right(sized) - left(sized),
            closeTo(40 / studio.view().scale, .5),
          );
        } finally {
          document.dispose();
        }
        await studio.finish();
      },
      skip: !available,
      variant: desktop,
    );
  });

  group('the keys of the sheet answer without a click on it', () {
    testWidgets('a number chooses a tool after the width slider was used', (
      tester,
    ) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stroke');
      await tester.tap(find.byKey(const Key('brushWidthSemantics')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fillShapeCheckbox')), findsNothing);
      // The third tool: the rectangle, which shows the « Remplir » box.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fillShapeCheckbox')), findsOneWidget);
      await studio.finish();
    }, skip: !available);

    testWidgets(
      'after Enregistrer or Exporter the arrows move the chosen element at once',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start();
        await studio.tap('tool-rectangle');
        await studio.drag(studio.at(200, 200), studio.at(400, 400));
        await studio.tap('tool-select');
        await studio.click(studio.at(200, 300));
        // The slider takes the focus, and the buttons do not take it back
        // by themselves.
        await tester.tap(find.byKey(const Key('brushWidthSemantics')));
        await tester.pumpAndSettle();
        await studio.tap('saveProject');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(studio.isDirty, isTrue);
        await studio.svg();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final document = await studio.saved();
        try {
          expect(left(document.strokes.single), closeTo(201, .01));
          expect(top(document.strokes.single), closeTo(201, .01));
        } finally {
          document.dispose();
        }
        await studio.finish();
      },
      skip: !available,
    );
  });
}
