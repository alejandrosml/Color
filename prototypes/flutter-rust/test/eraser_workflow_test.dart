// SPDX-License-Identifier: MIT
// Real Rust documents; only dialogs' destinations and storage are in memory.
import 'dart:io';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  // Three medium stamps in a row: boxes of 150 units centred on y = 400.
  Future<void> threeStamps(StudioDriver studio) async {
    await studio.tap('tool-stamp');
    for (final x in [300.0, 600.0, 900.0]) {
      await studio.click(studio.at(x, 400));
    }
    studio.expectCount(3);
  }

  testWidgets(
    'the eraser removes the element it touches, one undoable step each',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await threeStamps(studio);
      await studio.tap('saveProject');
      expect(studio.isDirty, isFalse);

      await studio.tap('tool-eraser');
      // The eraser has nothing to size: no slider, no stamp chooser.
      expect(find.text('Épaisseur'), findsNothing);
      expect(find.byKey(const Key('chooseStamp')), findsNothing);
      expect(
        find.textContaining('Touche un élément pour l’effacer'),
        findsOneWidget,
      );
      // The bare sheet has nothing to erase.
      await studio.click(studio.at(100, 100));
      studio.expectCount(3);
      expect(studio.isDirty, isFalse);

      await studio.click(studio.at(600, 400));
      studio.expectCount(2);
      expect(studio.isDirty, isTrue);
      await studio.click(studio.at(300, 400));
      studio.expectCount(1);
      // Annuler brings them back one by one, the last erased first.
      await studio.tap('undo');
      studio.expectCount(2);
      expect(studio.isDirty, isTrue);
      await studio.tap('undo');
      studio.expectCount(3);
      // Back on the saved drawing: nothing left to save.
      expect(studio.isDirty, isFalse);
      await studio.tap('redo');
      await studio.tap('redo');
      studio.expectCount(1);
      final document = await studio.saved();
      try {
        expect(left(document.strokes.single), closeTo(825, .5));
      } finally {
        document.dispose();
      }
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'gliding the eraser removes what it crosses, never what lies at the edge it left by',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await threeStamps(studio);
      // A fourth stamp in the corner, pushed back whole onto the sheet.
      await studio.click(studio.at(10, 400));
      studio.expectCount(4);
      await studio.tap('tool-eraser');

      // Out through the left edge at the height of the corner stamp, between
      // the first two stamps on the way: positions outside the sheet are not
      // pulled back onto its edge.
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(600, 250),
      );
      await gesture.moveTo(studio.sheetCenter + studio.at(600, 400));
      await tester.pump();
      studio.expectCount(3);
      await gesture.moveTo(studio.sheetCenter + studio.at(900, 400));
      await tester.pump();
      studio.expectCount(2);
      await gesture.moveTo(studio.sheetCenter + studio.at(900, 100));
      await gesture.moveTo(studio.sheetCenter + studio.at(-60, 100));
      await gesture.moveTo(studio.sheetCenter + studio.at(-60, 400));
      await gesture.up();
      await tester.pumpAndSettle();
      studio.expectCount(2);

      final document = await studio.saved();
      try {
        expect(document.strokes.map((object) => left(object).round()), [
          225,
          0,
        ]);
      } finally {
        document.dispose();
      }
      // Two elements crossed: two steps to bring back.
      await studio.tap('undo');
      await studio.tap('undo');
      studio.expectCount(4);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('a quick glide does not jump over a thin line', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-line');
    await studio.drag(studio.at(450, 300), studio.at(450, 500));
    await studio.drag(studio.at(750, 300), studio.at(750, 500));
    studio.expectCount(2);
    await studio.tap('tool-eraser');
    // Two samples only, far on either side of the first line.
    final gesture = await tester.startGesture(
      studio.sheetCenter + studio.at(300, 400),
    );
    await gesture.moveTo(studio.sheetCenter + studio.at(600, 400));
    await gesture.up();
    await tester.pumpAndSettle();
    studio.expectCount(1);
    final document = await studio.saved();
    try {
      expect(left(document.strokes.single), closeTo(750, .5));
    } finally {
      document.dispose();
    }
    await studio.finish();
  }, skip: !available);

  testWidgets('Échap ends an eraser gesture and nothing more is erased', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await threeStamps(studio);
    await studio.tap('tool-eraser');
    final gesture = await tester.startGesture(
      studio.sheetCenter + studio.at(450, 250),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await gesture.moveTo(studio.sheetCenter + studio.at(600, 400));
    await gesture.moveTo(studio.sheetCenter + studio.at(900, 400));
    await gesture.up();
    await tester.pumpAndSettle();
    studio.expectCount(3);
    // The tool is still the eraser: a new press erases again.
    await studio.click(studio.at(900, 400));
    studio.expectCount(2);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'the eraser takes the element in front and leaves hidden layers alone',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stamp');
      await studio.tap('size-large');
      await studio.click(studio.at(600, 400));
      await studio.layers(() => studio.tap('addLayer'));
      await studio.tap('size-small');
      await studio.click(studio.at(600, 400));
      studio.expectCount(2);

      await studio.tap('tool-eraser');
      await studio.click(studio.at(600, 400));
      studio.expectCount(1);
      var document = await studio.saved();
      try {
        // The small stamp of the upper layer went; the large one stays.
        expect(document.strokes.single.layer, 0);
        expect(
          right(document.strokes.single) - left(document.strokes.single),
          closeTo(240, .01),
        );
      } finally {
        document.dispose();
      }
      await studio.tap('undo');
      await studio.layers(() => studio.tap('layer-visible-1'));
      // The upper layer is hidden: the eraser now reaches the large stamp.
      await studio.tap('tool-eraser');
      await studio.click(studio.at(600, 400));
      studio.expectCount(1);
      document = await studio.saved();
      try {
        expect(document.strokes.single.layer, 1);
        expect(document.layers.map((layer) => layer.visible), [true, false]);
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'what the eraser uncovers stays until the next gesture points at it',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      // A large stamp, « the sky », with two small ones on it.
      await studio.tap('tool-stamp');
      await studio.tap('size-large');
      await studio.click(studio.at(600, 400));
      await studio.tap('size-small');
      await studio.click(studio.at(540, 400));
      await studio.click(studio.at(660, 400));
      studio.expectCount(3);
      await studio.tap('tool-eraser');

      // A slightly shaky click erases the small stamp only.
      await studio.drag(studio.at(540, 400), studio.at(543, 402));
      studio.expectCount(2);
      // Starting on the small stamp, the glide may wander over the large one
      // just uncovered, leave it and come back: it stays for this gesture.
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(660, 400),
      );
      await tester.pump();
      studio.expectCount(1);
      await gesture.moveTo(studio.sheetCenter + studio.at(600, 450));
      await gesture.moveTo(studio.sheetCenter + studio.at(540, 350));
      await tester.pump();
      studio.expectCount(1);
      await gesture.moveTo(studio.sheetCenter + studio.at(300, 350));
      await gesture.moveTo(studio.sheetCenter + studio.at(600, 400));
      await gesture.up();
      await tester.pumpAndSettle();
      studio.expectCount(1);
      // The next gesture points at it: it goes.
      await studio.click(studio.at(600, 400));
      studio.expectCount(0);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('erased traits, shapes and texts all come back with Annuler', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-stroke');
    await studio.drag(studio.at(100, 100), studio.at(300, 150));
    await studio.tap('tool-line');
    await studio.drag(studio.at(100, 300), studio.at(300, 300));
    await studio.tap('tool-ellipse');
    await studio.drag(studio.at(500, 100), studio.at(700, 250));
    await studio.addText('mot', x: 800, y: 500);
    studio.expectCount(4);
    final before = await studio.svg();

    await studio.tap('tool-eraser');
    // A hollow oval answers on its outline, not in its empty middle.
    await studio.click(studio.at(600, 175));
    studio.expectCount(4);
    await studio.click(studio.at(600, 100));
    studio.expectCount(3);
    await studio.click(studio.at(200, 300));
    await studio.click(studio.at(200, 125));
    await studio.click(studio.at(820, 520));
    studio.expectCount(0);
    for (var step = 0; step < 4; step++) {
      await studio.tap('undo');
    }
    studio.expectCount(4);
    expect(await studio.svg(), before);
    final document = await studio.saved();
    try {
      expect(document.strokes.map((object) => object.kind), [
        VectorKind.stroke,
        VectorKind.line,
        VectorKind.ellipse,
        VectorKind.text,
      ]);
    } finally {
      document.dispose();
    }
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);
}
