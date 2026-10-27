// SPDX-License-Identifier: MIT
// A line, a rectangle or an oval made of two clicks: the first poses a little
// circle where the shape starts, the second says where it ends. Real Rust
// documents; only native panels, disk writes and recovery are in memory.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/brush_width_control.dart';
import 'package:edupaint_flutter_study/drawing_gesture.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_painters.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/interface_font.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  final surface = find.byKey(const Key('drawingSurface'));

  DocumentPainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.descendant(of: surface, matching: find.byType(CustomPaint)),
      )
      .map((paint) => paint.painter)
      .whereType<DocumentPainter>()
      .single;

  ShapeAnchor? anchor(WidgetTester tester) => painter(tester).anchor;

  Future<StrokeData> single(StudioDriver studio) async {
    final document = await studio.saved();
    try {
      return document.strokes.single;
    } finally {
      document.dispose();
    }
  }

  // A mouse that hovers, presses and releases, as a real one does.
  Future<TestGesture> mouse(WidgetTester tester, Offset where) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: where);
    addTearDown(gesture.removePointer);
    await tester.pump();
    return gesture;
  }

  Future<void> clickWith(
    WidgetTester tester,
    TestGesture gesture,
    Offset where,
  ) async {
    await gesture.moveTo(where);
    await gesture.down(where);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  // The colour of one pixel of the sheet as it is painted on the screen,
  // given by a point of the document.
  Future<List<int>> painted(StudioDriver studio, double x, double y) async {
    final tester = studio.tester;
    final canvas = find.descendant(
      of: surface,
      matching: find.byType(RepaintBoundary),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(canvas.first);
    final origin = tester.getTopLeft(canvas.first);
    final where = studio.sheetCenter + studio.at(x, y) - origin;
    return (await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (where.dy.round() * image.width + where.dx.round()) * 4;
        return List<int>.generate(3, (i) => bytes.getUint8(offset + i));
      } finally {
        image.dispose();
      }
    }))!;
  }

  const waitingHelp = {
    'line': 'Clique maintenant là où ta ligne doit s’arrêter. Échap enlève le petit cercle.',
    'rectangle': 'Clique maintenant le coin d’en face de ton rectangle. Échap enlève le petit cercle.',
    'ellipse': 'Clique maintenant plus loin, en biais : ton ovale se placera entre tes deux clics. Échap enlève le petit cercle.',
  };

  // The little circles take the colours of the picture of each tool: yellow
  // then coral for the line and the rectangle, mint then yellow for the oval.
  const startMark = {
    'line': [0xff, 0xcd, 0x62],
    'rectangle': [0xff, 0xcd, 0x62],
    'ellipse': [0xb7, 0xe6, 0xd2],
  };

  for (final (tool, kind) in [
    ('line', VectorKind.line),
    ('rectangle', VectorKind.rectangle),
    ('ellipse', VectorKind.ellipse),
  ]) {
    testWidgets(
      'two clicks make a $tool: a little circle at the first, the shape at the second',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start(size: const Size(1280, 820));
        await studio.tap('tool-$tool');
        expect(anchor(tester), isNull);

        // The first click draws nothing: it poses where the shape starts.
        await studio.click(studio.at(300, 250));
        studio.expectCount(0);
        expect(studio.isDirty, isFalse);
        final posed = anchor(tester);
        expect(posed, isNotNull);
        expect(posed!.kind, kind);
        expect(posed.start.x, closeTo(300, .01));
        expect(posed.start.y, closeTo(250, .01));
        expect(find.text(waitingHelp[tool]!), findsWidgets);
        // The little circle is painted there, in the colour of the picture
        // of the tool; the paper beside it is still white.
        expect(await painted(studio, 300, 250), startMark[tool]);
        expect(await painted(studio, 340, 250), [0xff, 0xff, 0xff]);

        // The second click ends the shape: one element, one step to undo.
        await studio.click(studio.at(700, 500));
        studio.expectCount(1);
        expect(anchor(tester), isNull);
        expect(find.text(waitingHelp[tool]!), findsNothing);
        final shape = await single(studio);
        expect(shape.kind, kind);
        expect(shape.points.first.x, closeTo(300, .01));
        expect(shape.points.first.y, closeTo(250, .01));
        expect(shape.points.last.x, closeTo(700, .01));
        expect(shape.points.last.y, closeTo(500, .01));
        expect(shape.rgb, 0x477fb2);
        // The circle is gone with the click that used it.
        expect(await painted(studio, 300, 250), isNot(startMark[tool]));

        await studio.tap('undo');
        studio.expectCount(0);
        expect(anchor(tester), isNull);
        expect(tester.takeException(), isNull);
        await studio.finish();
      },
      skip: !available,
    );
  }

  testWidgets(
    'holding the button and gliding still makes the shape in one gesture',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await studio.tap('tool-ellipse');
      await studio.drag(studio.at(300, 250), studio.at(700, 500));
      studio.expectCount(1);
      expect(anchor(tester), isNull);
      final shape = await single(studio);
      expect(shape.kind, VectorKind.ellipse);
      expect(shape.points.last.x, closeTo(700, .01));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the second press may glide: the shape ends where it is released',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await studio.tap('tool-rectangle');
      await studio.click(studio.at(200, 200));
      expect(anchor(tester), isNotNull);
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(500, 400),
      );
      await gesture.moveTo(studio.sheetCenter + studio.at(800, 600));
      await tester.pump();
      // While it glides, the draft starts at the first click.
      final draft = painter(tester).draftPoints;
      expect(draft.first.x, closeTo(200, .01));
      expect(draft.last.x, closeTo(800, .01));
      studio.expectCount(0);
      await gesture.up();
      await tester.pumpAndSettle();
      studio.expectCount(1);
      expect(anchor(tester), isNull);
      final shape = await single(studio);
      expect(shape.points.first.x, closeTo(200, .01));
      expect(shape.points.first.y, closeTo(200, .01));
      expect(shape.points.last.x, closeTo(800, .01));
      expect(shape.points.last.y, closeTo(600, .01));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'Échap, a click on the little circle, another tool or Annuler take it away and draw nothing',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      // One element first, to see that Annuler does not remove it.
      await studio.tap('tool-rectangle');
      await studio.drag(studio.at(900, 100), studio.at(1100, 300));
      studio.expectCount(1);

      await studio.tap('tool-line');
      await studio.click(studio.at(300, 300));
      expect(anchor(tester), isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(anchor(tester), isNull);
      studio.expectCount(1);

      await studio.click(studio.at(300, 300));
      expect(anchor(tester), isNotNull);
      await studio.click(studio.at(300, 300));
      expect(anchor(tester), isNull);
      studio.expectCount(1);

      // The circle is a target on the screen, not one exact pixel: a second
      // click of a mouse a few pixels beside its centre is on it.
      final where = studio.sheetCenter + studio.at(300, 300);
      final pointer = await mouse(tester, where);
      for (final beside in const [Offset(1, 0), Offset(3, 2), Offset(-5, 5)]) {
        await clickWith(tester, pointer, where);
        expect(anchor(tester), isNotNull, reason: '$beside');
        await clickWith(tester, pointer, where + beside);
        expect(anchor(tester), isNull, reason: '$beside');
        studio.expectCount(1);
      }
      // A finger is less precise: its reach is wider.
      await studio.click(studio.at(300, 300));
      await tester.tapAt(where + const Offset(9, -8));
      await tester.pumpAndSettle();
      expect(anchor(tester), isNull);
      studio.expectCount(1);
      // Farther than the circle, a mouse makes a short line on purpose.
      await clickWith(tester, pointer, where);
      await clickWith(tester, pointer, where + const Offset(12, 0));
      expect(anchor(tester), isNull);
      studio.expectCount(2);
      await studio.tap('undo');
      studio.expectCount(1);
      expect(
        shapeMarkReach(touch: true),
        greaterThan(shapeMarkReach(touch: false)),
      );
      expect(shapeMarkReach(touch: false), greaterThan(shapeMarkRadius));

      await studio.click(studio.at(300, 300));
      expect(anchor(tester), isNotNull);
      await studio.tap('tool-stroke');
      expect(anchor(tester), isNull);
      // The brush then draws its dot as before, where the circle was.
      await studio.click(studio.at(300, 300));
      studio.expectCount(2);
      await studio.tap('undo');
      studio.expectCount(1);

      // Annuler takes the waiting circle away first, and only it.
      await studio.tap('tool-line');
      await studio.click(studio.at(300, 300));
      expect(anchor(tester), isNotNull);
      await studio.tap('undo');
      expect(anchor(tester), isNull);
      studio.expectCount(1);
      await studio.tap('undo');
      studio.expectCount(0);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'Annuler is offered for a first click on an empty sheet, and only takes the circle away',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      bool canUndo() =>
          tester.widget<IconButton>(find.byKey(const Key('undo'))).onPressed !=
          null;
      expect(canUndo(), isFalse);
      expect(studio.menu.onUndo, isNull);
      await studio.tap('tool-ellipse');
      await studio.click(studio.at(300, 300));
      expect(anchor(tester), isNotNull);
      expect(canUndo(), isTrue);
      expect(studio.menu.onUndo, isNotNull);
      studio.menu.onUndo!();
      await tester.pumpAndSettle();
      expect(anchor(tester), isNull);
      expect(canUndo(), isFalse);
      expect(studio.isDirty, isFalse);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'between the two clicks the shape follows the mouse, Maj squares it, and leaving the sheet hides it',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await studio.tap('tool-rectangle');
      final pointer = await mouse(
        tester,
        studio.sheetCenter + studio.at(300, 200),
      );
      await clickWith(
        tester,
        pointer,
        studio.sheetCenter + studio.at(300, 200),
      );
      final posed = anchor(tester)!;
      expect(posed.end, isNull);

      await pointer.moveTo(studio.sheetCenter + studio.at(700, 400));
      await tester.pump();
      expect(posed.end!.x, closeTo(700, .01));
      expect(posed.end!.y, closeTo(400, .01));
      // The outline of the shape to come is painted, in the current colour.
      expect(await painted(studio, 500, 200), [0x47, 0x7f, 0xb2]);
      // And a second little circle follows the pointer, in the other colour
      // of the pictures of the tools.
      expect(await painted(studio, 700, 400), [0xed, 0x8c, 0x88]);
      studio.expectCount(0);

      // Maj makes it a square at once, without waiting for a move.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(posed.end!.x, closeTo(700, .01));
      expect(posed.end!.y, closeTo(600, .01));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(posed.end!.y, closeTo(400, .01));

      // Beside the sheet a click would draw nothing: nothing is promised.
      final area = tester.getRect(surface);
      await pointer.moveTo(area.centerLeft + const Offset(4, 0));
      await tester.pump();
      expect(posed.end, isNull);
      expect(anchor(tester), same(posed));

      // Back on the sheet, with Maj held, the second click makes a square.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await clickWith(
        tester,
        pointer,
        studio.sheetCenter + studio.at(600, 320),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      studio.expectCount(1);
      final shape = await single(studio);
      expect(shape.kind, VectorKind.rectangle);
      expect(shape.points.first.x, closeTo(300, .01));
      expect(shape.points.first.y, closeTo(200, .01));
      expect(shape.points.last.x, closeTo(600, .01));
      expect(shape.points.last.y, closeTo(500, .01));
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('a click that trembles is still a click; a real glide is not', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start(size: const Size(1280, 820));
    await studio.tap('tool-line');
    final start = studio.sheetCenter + studio.at(300, 300);
    final pointer = await mouse(tester, start);

    // A mouse that moves by a few pixels while it is pressed.
    await pointer.down(start);
    await pointer.moveTo(start + const Offset(3, 2));
    await pointer.up();
    await tester.pumpAndSettle();
    studio.expectCount(0);
    expect(anchor(tester), isNotNull);
    // The circle is where the press began.
    expect(anchor(tester)!.start.x, closeTo(300, .01));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // A short glide on purpose makes a short line, as before.
    await pointer.down(start);
    await pointer.moveTo(start + const Offset(14, 0));
    await pointer.up();
    await tester.pumpAndSettle();
    studio.expectCount(1);
    expect(anchor(tester), isNull);

    // A finger trembles more: twice the travel of a mouse is still a tap.
    final finger = await tester.startGesture(start + const Offset(0, 80));
    await finger.moveTo(start + const Offset(9, 80));
    await finger.up();
    await tester.pumpAndSettle();
    studio.expectCount(1);
    expect(anchor(tester), isNotNull);
    expect(clickTravel(touch: true), greaterThan(clickTravel(touch: false)));
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'the colour, the width and the inside chosen between the two clicks are those of the shape',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await studio.tap('tool-rectangle');
      await studio.click(studio.at(300, 200));
      expect(anchor(tester), isNotNull);
      await studio.tap('color-d75e56');
      await studio.tap('paint-target-fill');
      await studio.tap('color-78a66f');
      // A click in the middle of the slider gives another width.
      final slider = find.byType(BrushWidthControl);
      await tester.tapAt(tester.getCenter(slider));
      await tester.pumpAndSettle();
      final width = tester.widget<BrushWidthControl>(slider).value;
      expect(width, isNot(12));
      // The first click still waits after these choices.
      expect(anchor(tester), isNotNull);
      expect(painter(tester).anchorRgb, 0xd75e56);
      expect(painter(tester).anchorFillRgb, 0x78a66f);
      expect(painter(tester).anchorWidth, width);
      await studio.click(studio.at(600, 500));
      final shape = await single(studio);
      expect(shape.rgb, 0xd75e56);
      expect(shape.fillRgb, 0x78a66f);
      expect(shape.width, width);
      expect(shape.points.first.x, closeTo(300, .01));
      expect(shape.points.last.x, closeTo(600, .01));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the brush, the stamp and the text keep their single click; a new sheet forgets a first click',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await studio.tap('tool-stroke');
      await studio.click(studio.at(300, 300));
      studio.expectCount(1);
      expect(anchor(tester), isNull);
      await studio.tap('tool-stamp');
      await studio.click(studio.at(600, 300));
      studio.expectCount(2);
      expect(anchor(tester), isNull);
      await studio.tap('tool-text');
      await studio.click(studio.at(900, 300));
      expect(find.byKey(const Key('textDialog')), findsOneWidget);
      await studio.tap('cancelText');
      expect(anchor(tester), isNull);

      await studio.tap('tool-line');
      await studio.click(studio.at(300, 600));
      expect(anchor(tester), isNotNull);
      await studio.newSheet('landscape');
      studio.expectCount(0);
      expect(anchor(tester), isNull);
      // The next click starts afresh.
      await studio.click(studio.at(100, 100));
      expect(anchor(tester)!.start.x, closeTo(100, .01));
      await studio.click(studio.at(400, 100));
      studio.expectCount(1);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a first click waits through a save, and nothing is saved of it',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await studio.tap('tool-line');
      await studio.click(studio.at(300, 300));
      final document = await studio.saved();
      try {
        expect(document.strokes, isEmpty);
      } finally {
        document.dispose();
      }
      expect(anchor(tester), isNotNull);
      await studio.click(studio.at(600, 300));
      studio.expectCount(1);
      await studio.finish();
    },
    skip: !available,
  );

  for (final tool in ['rectangle', 'ellipse']) {
    testWidgets(
      'a second click level with the first makes no $tool, and the circle keeps waiting',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start(size: const Size(1280, 820));
        await studio.tap('tool-$tool');
        await studio.click(studio.at(300, 400));
        final posed = anchor(tester);
        expect(posed, isNotNull);
        // Level with the first click, then right below it: nothing can hold
        // between two such points. Nothing is drawn, nothing is lost.
        await studio.click(studio.at(700, 400));
        studio.expectCount(0);
        expect(anchor(tester), same(posed));
        await studio.click(studio.at(300, 700));
        studio.expectCount(0);
        expect(anchor(tester), same(posed));
        expect(find.text(waitingHelp[tool]!), findsWidgets);
        expect(studio.isDirty, isFalse);
        // In a slant, the shape is made from the first click.
        await studio.click(studio.at(700, 600));
        studio.expectCount(1);
        expect(anchor(tester), isNull);
        final shape = await single(studio);
        expect(shape.points.first.x, closeTo(300, .01));
        expect(shape.points.first.y, closeTo(400, .01));
        expect(shape.points.last.x, closeTo(700, .01));
        expect(shape.points.last.y, closeTo(600, .01));
        await studio.finish();
      },
      skip: !available,
    );
  }

  testWidgets(
    'Annuler by the keys while the second press is held takes the two clicks back, not the drawing',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await studio.tap('tool-line');
      await studio.drag(studio.at(900, 100), studio.at(1100, 300));
      studio.expectCount(1);
      await studio.click(studio.at(300, 300));
      expect(anchor(tester), isNotNull);
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(500, 400),
      );
      await gesture.moveTo(studio.sheetCenter + studio.at(600, 500));
      await tester.pump();
      expect(painter(tester).draftPoints, hasLength(2));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(anchor(tester), isNull);
      expect(painter(tester).draftPoints, isEmpty);
      // The line drawn before is still there.
      studio.expectCount(1);
      await gesture.up();
      await tester.pumpAndSettle();
      studio.expectCount(1);
      expect(anchor(tester), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'Rétablir brings a step back and leaves the first click waiting',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await studio.tap('tool-line');
      await studio.drag(studio.at(900, 100), studio.at(1100, 300));
      await studio.tap('undo');
      studio.expectCount(0);
      await studio.click(studio.at(300, 300));
      final posed = anchor(tester);
      expect(posed, isNotNull);
      await studio.tap('redo');
      studio.expectCount(1);
      expect(anchor(tester), same(posed));
      await studio.click(studio.at(600, 500));
      studio.expectCount(2);
      expect(anchor(tester), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the pipette, between the two clicks, gives its colour to the shape to come',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      // A red line to take a colour from.
      await studio.tap('tool-line');
      await studio.tap('color-d75e56');
      await studio.drag(studio.at(900, 200), studio.at(1100, 200));
      await studio.tap('color-477fb2');
      await studio.click(studio.at(300, 300));
      final posed = anchor(tester);
      expect(posed, isNotNull);
      // The pipette leaves the first click waiting, as a colour does.
      await studio.tap('pickPaintColor');
      expect(anchor(tester), same(posed));
      await studio.click(studio.at(1000, 200));
      expect(anchor(tester), same(posed));
      studio.expectCount(1);
      expect(painter(tester).anchorRgb, 0xd75e56);
      await studio.click(studio.at(600, 500));
      studio.expectCount(2);
      final document = await studio.saved();
      try {
        expect(document.strokes.last.rgb, 0xd75e56);
        expect(document.strokes.last.points.first.x, closeTo(300, .01));
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'while the hand moves the sheet, or after a zoom, nothing is promised; the circle waits and the shape lands where the clicks were',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await studio.tap('tool-rectangle');
      final first = studio.sheetCenter + studio.at(300, 200);
      final pointer = await mouse(tester, first);
      await clickWith(tester, pointer, first);
      final posed = anchor(tester)!;
      await pointer.moveTo(studio.sheetCenter + studio.at(700, 400));
      await tester.pump();
      expect(posed.end, isNotNull);

      // A zoom moves the sheet under the pointer: the shape drawn for the
      // view of before goes, until the pointer moves again.
      await studio.tap('zoomIn');
      expect(anchor(tester), same(posed));
      expect(posed.end, isNull);
      await studio.tap('fitPage');
      expect(posed.end, isNull);
      await pointer.moveTo(studio.sheetCenter + studio.at(710, 410));
      await tester.pump();
      expect(posed.end!.x, closeTo(710, .5));

      // The hand tool: a press would move the sheet, not end the shape.
      await studio.tap('panPage');
      await pointer.moveTo(studio.sheetCenter + studio.at(600, 300));
      await tester.pump();
      expect(posed.end, isNull);
      await pointer.down(studio.sheetCenter + studio.at(600, 300));
      await pointer.moveTo(studio.sheetCenter + studio.at(640, 330));
      await pointer.up();
      await tester.pumpAndSettle();
      studio.expectCount(0);
      expect(anchor(tester), same(posed));
      await studio.tap('panPage');
      await studio.tap('fitPage');

      // Back on the fitted sheet, the second click makes the rectangle from
      // where the first click was.
      await clickWith(
        tester,
        pointer,
        studio.sheetCenter + studio.at(700, 500),
      );
      studio.expectCount(1);
      final shape = await single(studio);
      expect(shape.points.first.x, closeTo(300, .01));
      expect(shape.points.first.y, closeTo(200, .01));
      expect(shape.points.last.x, closeTo(700, .01));
      expect(shape.points.last.y, closeTo(500, .01));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a second press released beside the sheet ends the shape at its edge',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 820));
      await studio.tap('tool-line');
      await studio.click(studio.at(600, 400));
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(900, 400),
      );
      await gesture.moveTo(studio.sheetCenter + studio.at(1400, 400));
      await gesture.up();
      await tester.pumpAndSettle();
      studio.expectCount(1);
      final shape = await single(studio);
      expect(shape.points.first.x, closeTo(600, .01));
      expect(shape.points.last.x, closeTo(1200, .01));
      expect(shape.points.last.y, closeTo(400, .01));
      await studio.finish();
    },
    skip: !available,
  );

  for (final (size, textScale) in [
    (const Size(800, 600), 1.5),
    (const Size(1280, 820), 1.5),
    (const Size(680, 520), 1.3),
  ]) {
    testWidgets(
      'the little circle stays where the click was, at $size with letters × $textScale',
      (tester) async {
        await loadInterfaceFont(tester);
        final studio = StudioDriver(tester);
        await studio.start(size: size, textScale: textScale);
        await studio.tap('tool-rectangle');
        final before = tester.getRect(surface);
        final where = studio.sheetCenter + studio.at(300, 300);
        await tester.tapAt(where);
        await tester.pumpAndSettle();
        final posed = anchor(tester);
        expect(posed, isNotNull);
        // The sentence of help has changed, and its height with it; the
        // sheet has not moved under the circle.
        final view = painter(tester).viewport;
        final mark =
            tester.getTopLeft(surface) +
            Offset(
              view.left + posed!.start.x * view.scale,
              view.top + posed.start.y * view.scale,
            );
        expect((mark - where).distance, lessThan(.75));
        // After the second click the sheet takes its place again.
        await tester.tapAt(mark + const Offset(60, 40));
        await tester.pumpAndSettle();
        studio.expectCount(1);
        expect(tester.getRect(surface), before);
        expect(tester.takeException(), isNull);
        await studio.finish();
      },
      skip: !available,
    );
  }

  test('only shapes that a start and an end define are made of two clicks', () {
    expect(madeOfTwoClicks(VectorKind.line), isTrue);
    expect(madeOfTwoClicks(VectorKind.rectangle), isTrue);
    expect(madeOfTwoClicks(VectorKind.ellipse), isTrue);
    expect(madeOfTwoClicks(VectorKind.stroke), isFalse);
    expect(madeOfTwoClicks(VectorKind.text), isFalse);
    expect(madeOfTwoClicks(VectorKind.stamp), isFalse);
  });
}
