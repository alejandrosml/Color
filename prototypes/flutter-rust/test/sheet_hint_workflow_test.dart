// SPDX-License-Identifier: MIT
// « La pointe » and the preview before a tool acts (Color 1.2), in the
// studio: the pointer of the tool follows the mouse, the pointer of the
// system is hidden; before a press, the brush shows a dot of its size, the
// eraser its round, the stamp itself, the text its stroke, and the paint
// pot hatches what it would colour — under the mouse that hovers, under the
// pointer of the keyboard, and under a finger, which pours when it is
// lifted. Real Rust documents; only dialogs' destinations and storage are
// in memory.
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/sheet_hint.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_painters.dart';
import 'package:edupaint_flutter_study/studio_tool.dart';
import 'package:edupaint_flutter_study/tool_pointer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  SheetHint hintOf(WidgetTester tester) =>
      (tester.widget<CustomPaint>(find.byKey(const Key('sheetHint'))).painter!
              as SheetHintPainter)
          .hint;

  MouseCursor cursorOf(WidgetTester tester) => tester
      .widget<MouseRegion>(
        find
            .ancestor(
              of: find.byKey(const Key('drawingSurface')),
              matching: find.byType(MouseRegion),
            )
            .first,
      )
      .cursor;

  /// The insides of the elements the sheet shows now, in their order.
  List<int?> insides(WidgetTester tester) => [
    for (final element
        in (tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byKey(const Key('sheetPicture')),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .painter!
                as DocumentPainter)
            .strokes)
      element.data.fillRgb,
  ];

  /// Where a position of the screen lies in the frame of the sheet.
  Offset inFrame(WidgetTester tester, Offset global) =>
      global - tester.getTopLeft(find.byKey(const Key('drawingSurface')));

  Future<TestGesture> mouseAt(WidgetTester tester, Offset position) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: position);
    addTearDown(gesture.removePointer);
    await tester.pump();
    return gesture;
  }

  /// The pointer rests: the pot looks at what it would colour, which the
  /// engine reads outside the clock of the test. Waits for a preview of the
  /// pot when [shown], for the pot to have looked otherwise.
  Future<void> rest(WidgetTester tester, {bool shown = true}) async {
    await tester.pump(const Duration(milliseconds: 80));
    for (var attempt = 0; attempt < (shown ? 300 : 30); attempt++) {
      if (shown && hintOf(tester).preview is PourPreview) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pump();
  }

  Future<void> pressKey(
    WidgetTester tester,
    LogicalKeyboardKey key, [
    int times = 1,
  ]) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  // A box drawn by hand with the brush, closed.
  Future<void> drawBox(
    StudioDriver studio,
    double left,
    double top,
    double right,
    double bottom,
  ) async {
    final tester = studio.tester;
    final corners = [
      for (var x = left; x < right; x += 20) (x, top),
      for (var y = top; y < bottom; y += 20) (right, y),
      for (var x = right; x > left; x -= 20) (x, bottom),
      for (var y = bottom; y > top; y -= 20) (left, y),
      (left, top),
    ];
    final gesture = await tester.startGesture(
      studio.sheetCenter + studio.at(corners.first.$1, corners.first.$2),
    );
    for (final (x, y) in corners.skip(1)) {
      await gesture.moveTo(studio.sheetCenter + studio.at(x, y));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the pointer of the tool follows the mouse, with a dot of the trait',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stroke');
      await studio.tap('color-d75e56');
      final hint = hintOf(tester);
      // No mouse yet: nothing is shown, and no pointer is hidden.
      expect(hint.mouseAt, isNull);
      expect(hint.preview, isNull);

      final at = studio.sheetCenter + studio.at(400, 300);
      final mouse = await mouseAt(tester, at);
      await mouse.moveTo(at);
      await tester.pump();
      expect(cursorOf(tester), SystemMouseCursors.none);
      expect(hint.pointer, const ToolPointer(StudioTool.brush, 0xd75e56));
      expect(hint.mouseAt, inFrame(tester, at));
      final dot = hint.preview as DotPreview;
      expect(dot.at, inFrame(tester, at));
      expect(dot.rgb, 0xd75e56);
      expect(dot.width, 12);
      expect(dot.hollow, isFalse);

      // The pointer moves: so do they, and the studio is not built again.
      final next = studio.sheetCenter + studio.at(600, 500);
      await mouse.moveTo(next);
      await tester.pump();
      expect(hint.mouseAt, inFrame(tester, next));
      expect((hint.preview as DotPreview).at, inFrame(tester, next));

      // While the trait is drawn it is the trait that shows; the pointer
      // stays. Once released, the dot is back.
      await mouse.down(next);
      await tester.pump();
      expect(hint.preview, isNull);
      await mouse.moveTo(next + const Offset(40, 0));
      await tester.pump();
      expect(hint.preview, isNull);
      expect(hint.mouseAt, inFrame(tester, next + const Offset(40, 0)));
      await mouse.up();
      await tester.pumpAndSettle();
      studio.expectCount(1);
      expect(hint.preview, isA<DotPreview>());

      // Another colour, another size, another tool: at once, though the
      // mouse does not move.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pumpAndSettle();
      expect(hint.pointer!.tool, StudioTool.line);
      expect(hint.preview, isA<DotPreview>());

      // Beside the sheet, over the decor of the universe (Color 1.2), the
      // pointer of the system shows and « la pointe » is not drawn: it is
      // for the sheet. No dot where no trait would begin.
      final frame = tester.getRect(find.byKey(const Key('drawingSurface')));
      await mouse.moveTo(frame.topLeft + const Offset(3, 3));
      await tester.pump();
      expect(hint.mouseAt, isNull);
      expect(hint.preview, isNull);
      expect(cursorOf(tester), SystemMouseCursors.basic);
      // Back on the sheet, « la pointe » is back.
      await mouse.moveTo(next);
      await tester.pump();
      expect(hint.mouseAt, inFrame(tester, next));
      expect(cursorOf(tester), SystemMouseCursors.none);

      // Out of the frame: nothing is left.
      await mouse.moveTo(frame.topLeft - const Offset(30, 30));
      await tester.pump();
      expect(hint.mouseAt, isNull);
      expect(hint.preview, isNull);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('each tool shows what it would do', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start();
    final hint = hintOf(tester);
    final at = studio.sheetCenter + studio.at(400, 300);
    final mouse = await mouseAt(tester, at);
    await mouse.moveTo(at);
    await tester.pump();
    final scale = studio.at(1, 0).dx - studio.at(0, 0).dx;

    // The eraser: a round of its reach, a white tip.
    await studio.tap('tool-eraser');
    await mouse.moveTo(at);
    await tester.pump();
    expect(hint.pointer!.tipColour, const Color(0xffffffff));
    final round = hint.preview as EraserPreview;
    expect(round.at, inFrame(tester, at));
    expect(round.radius, 10);

    // The stamp: itself, where a click poses it — and the click does.
    await studio.tap('tool-stamp');
    await mouse.moveTo(at);
    await tester.pump();
    final stamp = hint.preview as PosedStampPreview;
    final box = stamp.element.controlBounds;
    expect(box.center.dx, closeTo(400, .01));
    expect(box.center.dy, closeTo(300, .01));
    await mouse.down(at);
    await mouse.up();
    await tester.pumpAndSettle();
    studio.expectCount(1);
    var document = await studio.saved();
    try {
      final posed = document.strokes.single;
      expect(posed.kind, VectorKind.stamp);
      expect(left(posed), closeTo(box.left, .01));
      expect(top(posed), closeTo(box.top, .01));
      expect(right(posed), closeTo(box.right, .01));
      expect(bottom(posed), closeTo(box.bottom, .01));
    } finally {
      document.dispose();
    }

    // The text: the stroke of its first letter, from where it would begin.
    await studio.tap('tool-text');
    final writing = studio.sheetCenter + studio.at(700, 500);
    await mouse.moveTo(writing);
    await tester.pump();
    final caret = hint.preview as CaretPreview;
    expect(caret.top.x, closeTo(700, 1 / scale));
    expect(caret.top.y, closeTo(500, 1 / scale));
    expect(caret.height, greaterThan(40));
    // At the foot of the sheet the text is brought back onto it: so is its
    // stroke.
    await mouse.moveTo(studio.sheetCenter + studio.at(700, 795));
    await tester.pump();
    final low = hint.preview as CaretPreview;
    expect(low.top.y + low.height, closeTo(800, .01));

    // « Choisir » keeps its arrow and promises nothing.
    await studio.tap('tool-select');
    await mouse.moveTo(at);
    await tester.pump();
    expect(hint.pointer!.tool, StudioTool.select);
    expect(hint.preview, isNull);
    expect(cursorOf(tester), SystemMouseCursors.none);

    // The magic that draws twice shows its two dots; the rainbow, which
    // has its own colours, a ring of its size.
    await studio.tap('tool-magic');
    await mouse.moveTo(at);
    await tester.pump();
    expect((hint.preview as DotPreview).hollow, isTrue);
    await studio.tap('magic-mirror');
    await mouse.moveTo(at);
    await tester.pump();
    final twice = hint.preview as DotPreview;
    expect(twice.mirrored, isTrue);
    expect(twice.hollow, isFalse);

    // The hand that moves the sheet has the pointer of the system.
    await studio.tap('panPage');
    await mouse.moveTo(at);
    await tester.pump();
    expect(cursorOf(tester), SystemMouseCursors.grab);
    expect(hint.pointer, isNull);
    expect(hint.preview, isNull);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'the paint pot hatches what it would colour under the mouse, then pours',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      final hint = hintOf(tester);
      await studio.tap('tool-stroke');
      await drawBox(studio, 300, 200, 600, 500);
      await studio.tap('tool-rectangle');
      await studio.drag(studio.at(800, 200), studio.at(1000, 400));
      studio.expectCount(2);
      await studio.tap('tool-fill');
      await studio.tap('color-eebf4e');

      // In the box drawn by hand: the zone that its line closes.
      final inBox = studio.sheetCenter + studio.at(450, 350);
      final mouse = await mouseAt(tester, inBox);
      await mouse.moveTo(inBox);
      await tester.pump();
      expect(hint.pointer, const ToolPointer(StudioTool.fill, 0xeebf4e));
      // Nothing is read while the pointer has not rested.
      expect(hint.preview, isNull);
      await rest(tester);
      var pour = hint.preview as PourPreview;
      expect(pour.rgb, 0xeebf4e);
      final zone = pour.zone!.getBounds();
      expect(zone.left, inInclusiveRange(300, 312));
      expect(zone.top, inInclusiveRange(200, 212));
      expect(zone.right, inInclusiveRange(588, 600));
      expect(zone.bottom, inInclusiveRange(488, 500));
      expect(pour.covers(const DocumentPoint(450, 350)), isTrue);
      expect(pour.covers(const DocumentPoint(700, 350)), isFalse);
      // Nothing was poured: the preview changes nothing.
      studio.expectCount(2);
      expect(studio.isDirty, isTrue);

      // The pointer travels in the zone: what is shown stays.
      await mouse.moveTo(studio.sheetCenter + studio.at(500, 400));
      await tester.pump();
      expect(identical(hint.preview, pour), isTrue);
      await rest(tester);
      expect((hint.preview as PourPreview).zone, isNotNull);

      // Out of it, on the paper around: what was shown goes at once; then
      // the paper is hatched, all of it but the box and the rectangle, which
      // are holes in it — the zone the pot would pour there.
      await mouse.moveTo(studio.sheetCenter + studio.at(700, 600));
      await tester.pump();
      expect(hint.preview, isNull);
      await rest(tester);
      pour = hint.preview as PourPreview;
      expect(pour.zone, isNotNull);
      expect(pour.covers(const DocumentPoint(700, 600)), isTrue);
      expect(pour.covers(const DocumentPoint(20, 20)), isTrue);
      expect(pour.covers(const DocumentPoint(450, 350)), isFalse);
      expect(pour.covers(const DocumentPoint(900, 300)), isFalse);

      // On the rectangle: its inside.
      await mouse.moveTo(studio.sheetCenter + studio.at(900, 300));
      await tester.pump();
      await rest(tester);
      pour = hint.preview as PourPreview;
      expect(pour.element!.data.kind, VectorKind.rectangle);
      expect(pour.inside, isTrue);

      // The click pours there, and for a moment nothing is hatched over
      // what was just coloured.
      await mouse.down(studio.sheetCenter + studio.at(900, 300));
      await mouse.up();
      await tester.pumpAndSettle();
      await rest(tester, shown: false);
      expect(hint.preview, isNull);
      studio.expectCount(2);
      // Back in the box: the click pours the zone that was shown.
      await mouse.moveTo(inBox);
      await tester.pump();
      await rest(tester);
      expect((hint.preview as PourPreview).zone, isNotNull);
      await mouse.down(inBox);
      await mouse.up();
      await tester.pump();
      await rest(tester, shown: false);
      await tester.pumpAndSettle();
      studio.expectCount(3);
      final document = await studio.saved();
      try {
        final [poured, _, rectangle] = document.strokes;
        expect(poured.look.zone, isTrue);
        expect(poured.fillRgb, 0xeebf4e);
        expect(rectangle.fillRgb, 0xeebf4e);
      } finally {
        document.dispose();
      }
      // Where the colour is already the pot's, nothing would change: no
      // hatching.
      await mouse.moveTo(studio.sheetCenter + studio.at(905, 305));
      await tester.pump();
      await rest(tester, shown: false);
      expect(hint.preview, isNull);
      // Another colour: the same place is hatched again.
      await studio.tap('color-d75e56');
      await mouse.moveTo(studio.sheetCenter + studio.at(906, 306));
      await tester.pump();
      await rest(tester);
      expect((hint.preview as PourPreview).rgb, 0xd75e56);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a finger holds the pot: it shows, follows, and pours when lifted',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      final hint = hintOf(tester);
      await studio.tap('tool-rectangle');
      await studio.drag(studio.at(200, 200), studio.at(400, 400));
      await studio.drag(studio.at(700, 200), studio.at(900, 400));
      studio.expectCount(2);
      await studio.tap('tool-fill');
      await studio.tap('color-eebf4e');

      // The finger comes down on the first rectangle: its inside is
      // hatched, nothing is poured, and no pointer is drawn for a finger.
      final finger = await tester.startGesture(
        studio.sheetCenter + studio.at(300, 300),
      );
      await tester.pump();
      await rest(tester);
      var pour = hint.preview as PourPreview;
      expect(left(pour.element!.data), closeTo(200, 1));
      expect(hint.mouseAt, isNull);
      expect(insides(tester), [null, null]);

      // It glides to the second one: the hatching changes place.
      await finger.moveTo(studio.sheetCenter + studio.at(800, 300));
      await tester.pump();
      expect(hint.preview, isNull);
      await rest(tester);
      pour = hint.preview as PourPreview;
      expect(left(pour.element!.data), closeTo(700, 1));

      expect(insides(tester), [null, null]);

      // It is lifted there: the paint flows there, and only there.
      await finger.up();
      await tester.pumpAndSettle();
      expect(hint.preview, isNull);
      expect(insides(tester), [null, 0xeebf4e]);

      // Lifted beside the sheet, the pot pours nothing.
      final frame = tester.getRect(find.byKey(const Key('drawingSurface')));
      final away = await tester.startGesture(
        studio.sheetCenter + studio.at(300, 300),
      );
      await tester.pump();
      await away.moveTo(frame.topLeft + const Offset(4, 4));
      await tester.pump();
      expect(hint.preview, isNull);
      await away.up();
      await tester.pumpAndSettle();
      expect(insides(tester), [null, 0xeebf4e]);

      // Échap gives the gesture up while the finger holds the pot: nothing
      // is shown any more, and the finger lifted afterwards pours nothing.
      final held = await tester.startGesture(
        studio.sheetCenter + studio.at(300, 300),
      );
      await tester.pump();
      await rest(tester);
      expect(hint.preview, isA<PourPreview>());
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(hint.preview, isNull);
      await held.up();
      await tester.pumpAndSettle();
      await rest(tester, shown: false);
      expect(hint.preview, isNull);
      expect(insides(tester), [null, 0xeebf4e]);
      studio.expectCount(2);

      // A quick tap pours as it always did.
      await studio.pour(studio.at(300, 300));
      expect(insides(tester), [0xeebf4e, 0xeebf4e]);
      final document = await studio.saved();
      try {
        expect(document.strokes.first.fillRgb, 0xeebf4e);
      } finally {
        document.dispose();
      }
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a second finger gives the pot up: the view moves, nothing is poured',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      final hint = hintOf(tester);
      await studio.tap('tool-rectangle');
      await studio.drag(studio.at(200, 200), studio.at(400, 400));
      await studio.tap('tool-fill');
      final first = await tester.startGesture(
        studio.sheetCenter + studio.at(300, 300),
      );
      await tester.pump();
      final second = await tester.startGesture(
        studio.sheetCenter + studio.at(500, 300),
      );
      await tester.pump();
      await second.moveTo(studio.sheetCenter + studio.at(600, 300));
      await tester.pump();
      expect(hint.preview, isNull);
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      await rest(tester, shown: false);
      expect(hint.preview, isNull);
      final document = await studio.saved();
      try {
        expect(document.strokes.single.fillRgb, isNull);
        expect(document.paperRgb, whitePaper);
      } finally {
        document.dispose();
      }
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the pointer of the keyboard has the tip and the preview', (
    tester,
  ) async {
    final studio = StudioDriver(
      tester,
      options: StudioOptionsStore.memory(
        const StudioOptions(keyboardPointer: true),
      ),
    );
    await studio.start();
    final hint = hintOf(tester);
    await studio.tap('tool-rectangle');
    final centre = studio.at(600, 400);
    await studio.drag(
      centre - const Offset(120, 90),
      centre + const Offset(120, 90),
    );
    await studio.tap('tool-stroke');
    expect(hint.keyAt, isNull);
    // The pointer appears at the middle of the frame, with the tip of the
    // brush and its dot.
    await pressKey(tester, LogicalKeyboardKey.arrowLeft);
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    final frame = tester.getSize(find.byKey(const Key('drawingSurface')));
    expect(hint.keyAt, frame.center(Offset.zero));
    expect(hint.pointer!.tool, StudioTool.brush);
    expect((hint.preview as DotPreview).at, hint.keyAt);
    expect(hint.mouseAt, isNull);

    // With the pot: the inside of the rectangle is hatched under it, and
    // Entrée pours there.
    await studio.tap('tool-fill');
    await studio.tap('color-eebf4e');
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await rest(tester);
    final pour = hint.preview as PourPreview;
    expect(pour.element!.data.kind, VectorKind.rectangle);
    expect(pour.inside, isTrue);
    await pressKey(tester, LogicalKeyboardKey.enter);
    await pressKey(tester, LogicalKeyboardKey.enter);
    final document = await studio.saved();
    try {
      expect(document.strokes.single.fillRgb, 0xeebf4e);
    } finally {
      document.dispose();
    }
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('on a colouring page the pot shows what it would colour', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    final hint = hintOf(tester);
    await studio.tap('newProject');
    await studio.tap('page-maison');
    studio.expectCount(0);
    await studio.tap('tool-fill');
    await studio.tap('color-d75e56');
    // The middle of the page lies in one of its zones, or on its paper:
    // the zone is hatched, or the paper but what the page draws on it.
    final mouse = await mouseAt(tester, studio.sheetCenter);
    await mouse.moveTo(studio.sheetCenter);
    await tester.pump();
    await rest(tester);
    final pour = hint.preview as PourPreview;
    expect(pour.rgb, 0xd75e56);
    if (pour.element != null) {
      expect(pour.inside, isTrue);
      expect(pour.element!.data.fillRgb, isNotNull);
    } else {
      expect(pour.wholeSheet, isTrue);
      expect(pour.ink, isNotNull);
    }
    // The page is as it was: the preview poured nothing.
    studio.expectCount(0);
    expect(studio.isDirty, isFalse);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);
}
