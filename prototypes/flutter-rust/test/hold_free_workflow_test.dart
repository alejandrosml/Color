// SPDX-License-Identifier: MIT
// « Dessiner sans tenir le bouton » : a mouse that clicks and moves, never
// holding its button. Real Rust documents; only native panels, disk writes
// and recovery are in memory.
import 'dart:io';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_sounds.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_sounds.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  Finder key(String name) => find.byKey(Key(name));

  // A studio with the option on, and a mouse resting on the sheet.
  Future<(StudioDriver, TestGesture, StudioOptionsStore)> open(
    WidgetTester tester, {
    bool holdFree = true,
    RecordingSounds? sounds,
  }) async {
    final store = StudioOptionsStore.memory(StudioOptions(holdFree: holdFree));
    addTearDown(store.dispose);
    final studio = StudioDriver(tester, options: store, sounds: sounds);
    await studio.start(size: const Size(1280, 800));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: studio.sheetCenter);
    addTearDown(mouse.removePointer);
    await tester.pump();
    return (studio, mouse, store);
  }

  // A click of the mouse at a point of the sheet: pressed and released
  // without moving, a moment after whatever came before — a click meant as
  // one, not the second press of a hand that pressed twice.
  Future<void> clickAt(
    WidgetTester tester,
    StudioDriver studio,
    TestGesture mouse,
    double x,
    double y,
  ) async {
    await tester.pump(const Duration(milliseconds: 400));
    final position = studio.sheetCenter + studio.at(x, y);
    await mouse.moveTo(position);
    await mouse.down(position);
    await mouse.up();
    await tester.pumpAndSettle();
  }

  // The same click by a hand that presses twice: the second press comes a
  // tenth of a second after the first, at the same place.
  Future<void> clickTwiceAt(
    WidgetTester tester,
    StudioDriver studio,
    TestGesture mouse,
    double x,
    double y,
  ) async {
    await tester.pump(const Duration(milliseconds: 400));
    final position = studio.sheetCenter + studio.at(x, y);
    await mouse.moveTo(position);
    await mouse.down(position);
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.down(position);
    await mouse.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> keys(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = false,
    bool shift = false,
  }) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  // The mouse moves to a point of the sheet with no button pressed.
  Future<void> hoverTo(
    WidgetTester tester,
    StudioDriver studio,
    TestGesture mouse,
    double x,
    double y,
  ) async {
    await mouse.moveTo(studio.sheetCenter + studio.at(x, y));
    await tester.pump();
  }

  testWidgets('a click begins a trait, the pointer draws it, a click ends it', (
    tester,
  ) async {
    final sounds = RecordingSounds();
    final (studio, mouse, _) = await open(tester, sounds: sounds);
    expect(
      find.textContaining('Clique pour commencer ton trait'),
      findsWidgets,
    );
    await clickAt(tester, studio, mouse, 200, 200);
    // Nothing is drawn yet, and the studio says what comes next.
    studio.expectCount(0);
    expect(find.textContaining('Clique pour arrêter ton trait'), findsWidgets);
    expect(sounds.take(), [StudioSound.stroke]); // the brush touches the sheet
    await hoverTo(tester, studio, mouse, 400, 300);
    await hoverTo(tester, studio, mouse, 600, 200);
    await hoverTo(tester, studio, mouse, 800, 400);
    studio.expectCount(0);
    await clickAt(tester, studio, mouse, 800, 400);
    studio.expectCount(1);
    expect(sounds.take(), isEmpty); // it lifts in silence
    // Moving on draws nothing more.
    await hoverTo(tester, studio, mouse, 1000, 600);
    await hoverTo(tester, studio, mouse, 300, 600);
    studio.expectCount(1);
    final document = await studio.saved();
    addTearDown(document.dispose);
    final trait = document.strokes.single;
    expect(trait.kind, VectorKind.stroke);
    expect(trait.points.length, greaterThanOrEqualTo(4));
    expect(trait.points.first.x, closeTo(200, 2));
    expect(trait.points.first.y, closeTo(200, 2));
    expect(trait.points.last.x, closeTo(800, 2));
    expect(trait.points.last.y, closeTo(400, 2));
    // It went through the points the pointer went through.
    expect(
      trait.points.any(
        (point) => (point.x - 600).abs() < 3 && (point.y - 200).abs() < 3,
      ),
      isTrue,
    );
    await studio.finish();
  }, skip: !available);

  testWidgets('two clicks at one place make a dot, and a drag still draws', (
    tester,
  ) async {
    final (studio, mouse, _) = await open(tester);
    await clickAt(tester, studio, mouse, 300, 300);
    await clickAt(tester, studio, mouse, 300, 300);
    studio.expectCount(1);
    // The button held, as always.
    final from = studio.sheetCenter + studio.at(500, 300);
    await mouse.moveTo(from);
    await mouse.down(from);
    await mouse.moveTo(studio.sheetCenter + studio.at(600, 400));
    await mouse.moveTo(studio.sheetCenter + studio.at(700, 300));
    await mouse.up();
    await tester.pumpAndSettle();
    studio.expectCount(2);
    // The drag left nothing waiting: the pointer moves freely again.
    await hoverTo(tester, studio, mouse, 900, 600);
    studio.expectCount(2);
    final document = await studio.saved();
    addTearDown(document.dispose);
    expect(document.strokes[0].points, hasLength(1));
    expect(document.strokes[1].points.length, greaterThanOrEqualTo(3));
    await studio.finish();
  }, skip: !available);

  testWidgets('Échap gives the trait up; leaving the sheet keeps it', (
    tester,
  ) async {
    final (studio, mouse, _) = await open(tester);
    await clickAt(tester, studio, mouse, 200, 200);
    await hoverTo(tester, studio, mouse, 500, 400);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    studio.expectCount(0);
    await hoverTo(tester, studio, mouse, 700, 500);
    studio.expectCount(0);

    // Towards a colour: the trait ends where the pointer leaves the frame
    // of the sheet, and the click on the colour is only that.
    await clickAt(tester, studio, mouse, 200, 600);
    await hoverTo(tester, studio, mouse, 500, 650);
    final swatch = tester.getCenter(key('color-d75e56'));
    await mouse.moveTo(swatch);
    await tester.pumpAndSettle();
    studio.expectCount(1);
    await mouse.down(swatch);
    await mouse.up();
    await tester.pumpAndSettle();
    studio.expectCount(1);
    // The next trait takes the new colour; the first one kept its own.
    await clickAt(tester, studio, mouse, 800, 200);
    await hoverTo(tester, studio, mouse, 900, 300);
    await clickAt(tester, studio, mouse, 900, 300);
    final document = await studio.saved();
    addTearDown(document.dispose);
    expect(document.strokes, hasLength(2));
    expect(document.strokes[0].rgb, 0x477fb2);
    expect(document.strokes[1].rgb, 0xd75e56);
    await studio.finish();
  }, skip: !available);

  testWidgets('a command asked by the keyboard keeps the trait in progress', (
    tester,
  ) async {
    final (studio, mouse, _) = await open(tester);
    await clickAt(tester, studio, mouse, 200, 200);
    await hoverTo(tester, studio, mouse, 500, 400);
    // Enregistrer: the trait is finished first, and saved with the rest.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(studio.files.projects, hasLength(1));
    final document = RustDocument.fromProject(
      studio.files.projects.values.single,
    );
    addTearDown(document.dispose);
    expect(document.strokes, hasLength(1));
    // Nothing follows the pointer any more.
    await hoverTo(tester, studio, mouse, 900, 600);
    studio.expectCount(1);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'a click chooses an element, a click on it takes it, a click poses it',
    (tester) async {
      final (studio, mouse, _) = await open(tester);
      await studio.tap('tool-rectangle');
      await studio.drag(studio.at(200, 200), studio.at(400, 400));
      await studio.tap('tool-select');
      expect(find.text('Clique un élément pour le choisir.'), findsOneWidget);
      // First click: chosen, not taken.
      await clickAt(tester, studio, mouse, 200, 300);
      expect(find.textContaining('Clique-le pour le prendre.'), findsOneWidget);
      expect(find.text('Clique un élément pour le choisir.'), findsNothing);
      await hoverTo(tester, studio, mouse, 600, 300);
      await hoverTo(tester, studio, mouse, 200, 300);
      // Second click on it: it follows the pointer.
      await clickAt(tester, studio, mouse, 200, 300);
      expect(
        find.text('Bouge pour le déplacer. Clique pour le poser.'),
        findsOneWidget,
      );
      await hoverTo(tester, studio, mouse, 500, 450);
      await hoverTo(tester, studio, mouse, 700, 500);
      await clickAt(tester, studio, mouse, 700, 500);
      // Posed: it stays there, and stays chosen.
      await hoverTo(tester, studio, mouse, 100, 100);
      expect(find.textContaining('Clique-le pour le prendre.'), findsOneWidget);
      final document = await studio.saved();
      addTearDown(document.dispose);
      final moved = document.strokes.single;
      // The corner that was under the pointer went with it: 500 right, 200 down.
      expect(moved.points.first.x, closeTo(700, 3));
      expect(moved.points.first.y, closeTo(400, 3));
      expect(moved.points.last.x, closeTo(900, 3));
      expect(moved.points.last.y, closeTo(600, 3));
      // One step for Annuler brings it back.
      await studio.tap('undo');
      final back = await studio.saved();
      addTearDown(back.dispose);
      expect(back.strokes.single.points.first.x, closeTo(200, 1));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the hand takes the sheet with a click and lets it go with one', (
    tester,
  ) async {
    final (studio, mouse, _) = await open(tester);
    await studio.tap('zoomIn');
    await studio.tap('zoomIn');
    await studio.tap('panPage');
    expect(find.textContaining('Clique pour prendre la feuille'), findsWidgets);
    final painter = find.descendant(
      of: key('drawingSurface'),
      matching: find.byType(CustomPaint),
    );
    Offset sheetOrigin() {
      final custom = tester.widget<CustomPaint>(painter.first);
      final viewport = (custom.painter! as dynamic).viewport;
      return Offset(viewport.left as double, viewport.top as double);
    }

    final before = sheetOrigin();
    final start = studio.sheetCenter;
    await mouse.moveTo(start);
    await mouse.down(start);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.textContaining('Clique pour la lâcher'), findsWidgets);
    await mouse.moveTo(start + const Offset(-60, -40));
    await tester.pumpAndSettle();
    expect(sheetOrigin(), before + const Offset(-60, -40));
    await mouse.down(start + const Offset(-60, -40));
    await mouse.up();
    await tester.pumpAndSettle();
    // Let go: the sheet no longer follows.
    await mouse.moveTo(start + const Offset(40, 40));
    await tester.pumpAndSettle();
    expect(sheetOrigin(), before + const Offset(-60, -40));
    studio.expectCount(0);
    await studio.finish();
  }, skip: !available);

  testWidgets('without the option a click is a dot, as it always was', (
    tester,
  ) async {
    final (studio, mouse, store) = await open(tester, holdFree: false);
    await clickAt(tester, studio, mouse, 300, 300);
    studio.expectCount(1);
    await hoverTo(tester, studio, mouse, 600, 500);
    studio.expectCount(1);
    // Switched on, then off again, while the studio runs.
    await store.change(store.value.copyWith(holdFree: true));
    await tester.pumpAndSettle();
    await clickAt(tester, studio, mouse, 500, 300);
    studio.expectCount(1);
    await hoverTo(tester, studio, mouse, 700, 500);
    await clickAt(tester, studio, mouse, 700, 500);
    studio.expectCount(2);
    await store.change(store.value.copyWith(holdFree: false));
    await tester.pumpAndSettle();
    await clickAt(tester, studio, mouse, 900, 300);
    studio.expectCount(3);
    await studio.finish();
  }, skip: !available);

  testWidgets('a click pressed twice is one click', (tester) async {
    final (studio, mouse, _) = await open(tester);
    // The click that begins a trait, pressed twice: the trait is begun, not
    // begun and ended.
    await clickTwiceAt(tester, studio, mouse, 200, 200);
    studio.expectCount(0);
    expect(find.textContaining('Clique pour arrêter ton trait'), findsWidgets);
    await hoverTo(tester, studio, mouse, 500, 300);
    // The click that ends it, pressed twice: one trait, no dot, and nothing
    // follows the pointer afterwards.
    await clickTwiceAt(tester, studio, mouse, 500, 300);
    studio.expectCount(1);
    expect(find.textContaining('Clique pour arrêter ton trait'), findsNothing);
    await hoverTo(tester, studio, mouse, 900, 600);
    await tester.pump(const Duration(milliseconds: 400));
    await mouse.moveTo(studio.sheetCenter); // towards nothing in particular
    await tester.pumpAndSettle();
    studio.expectCount(1);
    final document = await studio.saved();
    addTearDown(document.dispose);
    expect(document.strokes.single.points.first.x, closeTo(200, 2));
    expect(document.strokes.single.points.last.x, closeTo(500, 2));
    // A while later, the same place clicked again is a new click.
    await clickAt(tester, studio, mouse, 500, 300);
    expect(find.textContaining('Clique pour arrêter ton trait'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await studio.finish();
  }, skip: !available);

  testWidgets('an element clicked twice at once is chosen, not taken away', (
    tester,
  ) async {
    final (studio, mouse, _) = await open(tester);
    await studio.tap('tool-rectangle');
    await studio.drag(studio.at(200, 200), studio.at(400, 400));
    await studio.tap('tool-select');
    await clickTwiceAt(tester, studio, mouse, 200, 300);
    expect(find.textContaining('Clique-le pour le prendre.'), findsOneWidget);
    // Towards a button: nothing goes with the pointer.
    await hoverTo(tester, studio, mouse, 700, 600);
    await mouse.moveTo(tester.getCenter(key('duplicateSelection')));
    await tester.pumpAndSettle();
    final document = await studio.saved();
    addTearDown(document.dispose);
    expect(document.strokes.single.points.first.x, closeTo(200, 0.01));
    expect(document.strokes.single.points.first.y, closeTo(200, 0.01));
    // Nothing was done to it: one Annuler takes the rectangle itself away.
    await studio.tap('undo');
    studio.expectCount(0);
    await studio.finish();
  }, skip: !available);

  testWidgets('a click that trembles chooses an element without moving it', (
    tester,
  ) async {
    final (studio, mouse, _) = await open(tester);
    await studio.tap('tool-rectangle');
    await studio.drag(studio.at(200, 200), studio.at(400, 400));
    await studio.tap('tool-select');
    await tester.pump(const Duration(milliseconds: 400));
    final position = studio.sheetCenter + studio.at(200, 300);
    await mouse.moveTo(position);
    await mouse.down(position);
    await mouse.moveTo(position + const Offset(2, 2));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.textContaining('Clique-le pour le prendre.'), findsOneWidget);
    final document = await studio.saved();
    addTearDown(document.dispose);
    expect(document.strokes.single.points.first.x, 200);
    expect(document.strokes.single.points.first.y, 200);
    // No move was made: one Annuler takes the rectangle itself away.
    await studio.tap('undo');
    studio.expectCount(0);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'Annuler during a trait takes that trait back, not the one before',
    (tester) async {
      final (studio, mouse, _) = await open(tester);
      await clickAt(tester, studio, mouse, 200, 200);
      await hoverTo(tester, studio, mouse, 400, 300);
      await clickAt(tester, studio, mouse, 400, 300);
      studio.expectCount(1);
      await clickAt(tester, studio, mouse, 600, 200);
      await hoverTo(tester, studio, mouse, 800, 400);
      await keys(tester, LogicalKeyboardKey.keyZ, control: true);
      // The first trait is still there; the second was kept, then taken back.
      studio.expectCount(1);
      await hoverTo(tester, studio, mouse, 900, 600);
      studio.expectCount(1);
      var document = await studio.saved();
      addTearDown(document.dispose);
      expect(document.strokes.single.points.first.x, closeTo(200, 2));
      await keys(tester, LogicalKeyboardKey.keyZ, control: true, shift: true);
      studio.expectCount(2);
      document = await studio.saved();
      addTearDown(document.dispose);
      expect(document.strokes[1].points.first.x, closeTo(600, 2));
      expect(document.strokes[1].points.last.x, closeTo(800, 2));
      // Rétablir asked during a trait keeps the trait too.
      await clickAt(tester, studio, mouse, 300, 600);
      await hoverTo(tester, studio, mouse, 500, 650);
      await keys(tester, LogicalKeyboardKey.keyZ, control: true, shift: true);
      studio.expectCount(3);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('a key or a tool chosen during a gesture keeps what it made', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (studio, mouse, _) = await open(tester);
    // The key of a tool: the trait is kept, then the tool changes.
    await clickAt(tester, studio, mouse, 200, 200);
    await hoverTo(tester, studio, mouse, 400, 300);
    await keys(tester, LogicalKeyboardKey.digit3);
    studio.expectCount(1);
    expect(
      tester
          .getSemantics(key('tool-rectangle'))
          .getSemanticsData()
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    // Maj is held with other keys and asks for nothing: the trait goes on.
    await studio.tap('tool-stroke');
    await clickAt(tester, studio, mouse, 600, 200);
    await hoverTo(tester, studio, mouse, 700, 300);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    studio.expectCount(1);
    expect(find.textContaining('Clique pour arrêter ton trait'), findsWidgets);
    await clickAt(tester, studio, mouse, 700, 300);
    studio.expectCount(2);
    // An element carried: Annuler poses it, then takes the move back; the
    // element itself stays.
    await studio.tap('tool-select');
    await clickAt(tester, studio, mouse, 200, 200);
    await clickAt(tester, studio, mouse, 200, 200);
    expect(
      find.text('Bouge pour le déplacer. Clique pour le poser.'),
      findsOneWidget,
    );
    await hoverTo(tester, studio, mouse, 300, 500);
    await keys(tester, LogicalKeyboardKey.keyZ, control: true);
    studio.expectCount(2);
    final document = await studio.saved();
    addTearDown(document.dispose);
    expect(document.strokes[0].points.first.x, closeTo(200, 2));
    expect(document.strokes[0].points.first.y, closeTo(200, 2));
    semantics.dispose();
    await studio.finish();
  }, skip: !available);

  testWidgets('the hint of « Choisir » says clicks in a narrow window too', (
    tester,
  ) async {
    final store = StudioOptionsStore.memory(
      const StudioOptions(holdFree: true),
    );
    addTearDown(store.dispose);
    final studio = StudioDriver(tester, options: store);
    await studio.start(size: const Size(1000, 700));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: studio.sheetCenter);
    addTearDown(mouse.removePointer);
    await studio.tap('tool-rectangle');
    await studio.drag(studio.at(300, 200), studio.at(700, 600));
    await studio.tap('tool-select');
    await clickAt(tester, studio, mouse, 300, 400);
    expect(find.textContaining('Glisse pour déplacer'), findsNothing);
    expect(find.textContaining('Clique-le pour le prendre.'), findsOneWidget);
    await clickAt(tester, studio, mouse, 300, 400);
    expect(
      find.text('Bouge pour le déplacer. Clique pour le poser.'),
      findsOneWidget,
    );
    await clickAt(tester, studio, mouse, 400, 400);
    expect(find.textContaining('Clique-le pour le prendre.'), findsOneWidget);
    await studio.finish();
  }, skip: !available);

  testWidgets('Échap lets the held sheet go and leaves the rest as it is', (
    tester,
  ) async {
    final (studio, mouse, _) = await open(tester);
    await studio.tap('tool-rectangle');
    await studio.drag(studio.at(200, 200), studio.at(400, 400));
    await studio.tap('tool-select');
    await clickAt(tester, studio, mouse, 200, 300);
    expect(find.textContaining('Clique-le pour le prendre.'), findsOneWidget);
    await studio.tap('zoomIn');
    await studio.tap('panPage');
    await tester.pump(const Duration(milliseconds: 400));
    await mouse.moveTo(studio.sheetCenter);
    await mouse.down(studio.sheetCenter);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.textContaining('Clique pour la lâcher'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining('Clique pour la lâcher'), findsNothing);
    // The element chosen before is still the chosen one.
    await studio.tap('panPage');
    expect(find.textContaining('Clique-le pour le prendre.'), findsOneWidget);
    await studio.finish();
  }, skip: !available);

  testWidgets('a pen is not a mouse: its tap is a dot', (tester) async {
    final (studio, _, _) = await open(tester);
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    final position = studio.sheetCenter + studio.at(300, 300);
    await pen.down(position);
    await pen.up();
    await tester.pumpAndSettle();
    studio.expectCount(1);
    expect(find.textContaining('Clique pour arrêter ton trait'), findsNothing);
    await studio.finish();
  }, skip: !available);

  testWidgets('a finger keeps its own gestures: a tap is a dot', (
    tester,
  ) async {
    final (studio, _, _) = await open(tester);
    await studio.click(studio.at(300, 300));
    studio.expectCount(1);
    await studio.drag(studio.at(500, 300), studio.at(700, 400));
    studio.expectCount(2);
    await studio.finish();
  }, skip: !available);
}
