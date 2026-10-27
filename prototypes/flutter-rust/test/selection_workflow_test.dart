// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/gestures.dart';

import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/color_palette.dart';
import 'package:edupaint_flutter_study/brush_width_control.dart';
import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  final surface = find.byKey(const Key('drawingSurface'));

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    if (key == 'openProject') {
      await waitForPreparedOpen(tester, allowSaveDecision: true);
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<MemoryFiles> start(
    WidgetTester tester,
    MemoryRecovery recovery, {
    Size size = const Size(1100, 760),
    int rgb = 0x477fb2,
    double width = 12,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seed = RustDocument();
    final files = MemoryFiles();
    try {
      seed.addShape(
        VectorKind.rectangle,
        const DocumentPoint(400, 250),
        const DocumentPoint(650, 500),
        rgb: rgb,
        width: width,
        fillRgb: 0xeebf4e,
      );
      files.projects[files.savePath!] = seed.exportProject();
    } finally {
      seed.dispose();
    }
    files.openPath = files.savePath;
    await tester.pumpWidget(
      EduPaintApp(files: files, recoveryStorage: recovery),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'openProject');
    await tap(tester, 'tool-select');
    expect(tester.takeException(), isNull);
    return files;
  }

  Offset point(WidgetTester tester, double x, double y) {
    final size = tester.getSize(surface);
    final viewport = DocumentViewport(
      viewWidth: size.width,
      viewHeight: size.height,
      padding: size.height >= 160 ? 28 : 8,
    );
    return tester.getTopLeft(surface) +
        Offset(
          viewport.left + x * viewport.scale,
          viewport.top + y * viewport.scale,
        );
  }

  Future<void> select(WidgetTester tester) async {
    await tester.tapAt(point(tester, 500, 350));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('deleteSelection')))
          .onPressed,
      isNotNull,
    );
  }

  Future<Uint8List> saved(WidgetTester tester, MemoryFiles files) async {
    await tap(tester, 'saveProject');
    return Uint8List.fromList(files.projects[files.savePath!]!);
  }

  List<StrokeData> objects(Uint8List bytes) {
    final document = RustDocument.fromProject(bytes);
    try {
      return document.strokes;
    } finally {
      document.dispose();
    }
  }

  for (final (size, textScale) in [
    for (final size in [const Size(1100, 760), const Size(680, 520)])
      for (final scale in [1.0, 1.5]) (size, scale),
    for (final size in [
      const Size(749, 520),
      const Size(750, 520),
      const Size(1100, 520),
    ])
      (size, 1.5),
  ]) {
    testWidgets(
      'selection controls stay reachable at $size with text $textScale',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final files = await start(tester, MemoryRecovery(), size: size);
        final beforeSelection = tester.getRect(surface);
        expect(beforeSelection.height, greaterThan(80));
        await select(tester);
        expect(tester.getRect(surface), beforeSelection);
        // A colour clicked while an element is chosen changes it at once.
        await tap(tester, 'color-d75e56');
        expect(find.byKey(const Key('applySelectionStyle')), findsNothing);
        expect(find.text('Appliquer'), findsNothing);
        final controls = [
          'selectionOrder',
          'duplicateSelection',
          'deleteSelection',
          'shrinkSelection',
          'growSelection',
        ];
        for (final key in controls) {
          await tester.ensureVisible(find.byKey(Key(key)));
          await tester.pumpAndSettle();
          final rect = tester.getRect(find.byKey(Key(key)));
          expect(rect.height, greaterThanOrEqualTo(48), reason: key);
          expect(rect.width, greaterThanOrEqualTo(48), reason: key);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
        }
        final controlsScroll = find.byKey(const Key('drawingControlsScroll'));
        if (size.height == 520 && textScale == 1.5) {
          expect(controlsScroll, findsOneWidget);
        }
        if (controlsScroll.evaluate().isNotEmpty) {
          final scrollable = tester.state<ScrollableState>(
            find
                .descendant(
                  of: controlsScroll,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.ensureVisible(find.byKey(const Key('color-33484d')));
          await tester.pumpAndSettle();
          final beforeScroll = scrollable.position.pixels;
          final maxScroll = scrollable.position.maxScrollExtent;
          // Without « Appliquer » the controls of the widest of these windows
          // fit: the narrower ones still scroll.
          if (size.height == 520 && textScale == 1.5 && size.width < 1100) {
            expect(maxScroll, greaterThan(0));
          }
          final dynamic drawing = tester
              .widget<CustomPaint>(
                find
                    .descendant(of: surface, matching: find.byType(CustomPaint))
                    .first,
              )
              .painter;
          final viewportBefore =
              (drawing.viewport as DocumentViewport).transform;
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: tester.getCenter(controlsScroll),
              scrollDelta: const Offset(0, 32),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            scrollable.position.pixels,
            closeTo((beforeScroll + 32).clamp(0, maxScroll), .001),
          );
          final dynamic afterScroll = tester
              .widget<CustomPaint>(
                find
                    .descendant(of: surface, matching: find.byType(CustomPaint))
                    .first,
              )
              .painter;
          final viewportAfter =
              (afterScroll.viewport as DocumentViewport).transform;
          expect(viewportAfter.scale, viewportBefore.scale);
          expect(viewportAfter.left, viewportBefore.left);
          expect(viewportAfter.top, viewportBefore.top);
          expect(tester.getRect(surface), beforeSelection);
          // Actual Tab traversal must reveal the action, including when clipped.
          final semantics = tester.ensureSemantics();
          try {
            final firstColor = find.descendant(
              of: find.byKey(const Key('color-33484d')),
              matching: find.byType(IconButton),
            );
            await tester.ensureVisible(firstColor);
            await tester.pumpAndSettle();
            final firstNode = tester.getSemantics(firstColor);
            firstNode.owner!.performAction(firstNode.id, SemanticsAction.focus);
            await tester.pumpAndSettle();
            final lastAction = find.byKey(const Key('growSelection'));
            // The row of colours is crossed one swatch at a time, and it
            // shows more of them in a wider window; a few controls follow.
            final swatches = find
                .byWidgetPredicate(
                  (widget) =>
                      widget.key is ValueKey<String> &&
                      (widget.key! as ValueKey<String>).value.startsWith(
                        'color-',
                      ),
                )
                .evaluate()
                .length;
            expect(swatches, inInclusiveRange(10, 24));
            for (var step = 0; step < swatches + 12; step++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pumpAndSettle();
              final data = tester.getSemantics(lastAction).getSemanticsData();
              if (data.flagsCollection.isFocused == Tristate.isTrue) {
                break;
              }
            }
            expect(
              tester.getSemantics(lastAction),
              isSemantics(
                label: 'Rendre l’élément plus grand',
                isButton: true,
                isFocused: true,
              ),
            );
            final visible = tester.getRect(controlsScroll);
            final focused = tester.getRect(lastAction);
            expect(focused.top, greaterThanOrEqualTo(visible.top));
            expect(focused.bottom, lessThanOrEqualTo(visible.bottom + .001));
            if (maxScroll > 0) {
              expect(scrollable.position.pixels, greaterThan(0));
            }
          } finally {
            semantics.dispose();
          }
        }
        final copy = tester.getRect(
          find.byKey(const Key('duplicateSelection')),
        );
        final erase = tester.getRect(find.byKey(const Key('deleteSelection')));
        expect(erase.left - copy.right, greaterThanOrEqualTo(8));
        await tester.tapAt(
          Offset((copy.right + erase.left) / 2, copy.center.dy),
        );
        await tester.pumpAndSettle();
        // Gaps must neither duplicate nor delete; the colour clicked above
        // is on the element, as one step to undo.
        expect(objects(await saved(tester, files)), hasLength(1));
        expect(objects(files.projects[files.savePath!]!).single.rgb, 0xd75e56);
        await tap(tester, 'undo');
        expect(objects(await saved(tester, files)).single.rgb, 0x477fb2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: !available,
      variant: TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }),
    );
  }

  testWidgets(
    'selection moves only on release, cancels with Escape and undoes as one action',
    (tester) async {
      final recovery = MemoryRecovery();
      final files = await start(tester, recovery);
      final original = files.projects[files.savePath!]!;
      await select(tester);
      final baseline = recovery.writes;
      var gesture = await tester.startGesture(point(tester, 500, 350));
      await gesture.moveTo(point(tester, 530, 390));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        recovery.writes,
        baseline,
        reason: 'A movement preview is not persisted.',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(await saved(tester, files), original);

      gesture = await tester.startGesture(point(tester, 500, 350));
      await gesture.moveTo(point(tester, 510, 360));
      await gesture.moveTo(point(tester, 560, 390));
      await gesture.up();
      await tester.pumpAndSettle();
      final moved = objects(await saved(tester, files)).single;
      expect(moved.points.first.x, closeTo(460, .001));
      expect(moved.points.first.y, closeTo(290, .001));
      await tap(tester, 'undo');
      expect(await saved(tester, files), original);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('deleteSelection')))
            .onPressed,
        isNull,
      );
      await tap(tester, 'redo');
      expect(
        objects(await saved(tester, files)).single.points.first.x,
        closeTo(460, .001),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'copy and delete preserve history even when the page becomes empty',
    (tester) async {
      final files = await start(tester, MemoryRecovery());
      final original = files.projects[files.savePath!]!;
      await select(tester);
      await tap(tester, 'duplicateSelection');
      final copied = objects(await saved(tester, files));
      expect(copied, hasLength(2));
      expect(copied.last.points.first.x, 424);
      await tap(tester, 'deleteSelection');
      expect(await saved(tester, files), original);
      await tap(tester, 'undo');
      expect(objects(await saved(tester, files)), hasLength(2));
      await tap(tester, 'undo');
      expect(await saved(tester, files), original);
      await select(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(objects(await saved(tester, files)), isEmpty);
      expect(
        tester.widget<IconButton>(find.byKey(const Key('undo'))).onPressed,
        isNotNull,
      );
      await tap(tester, 'undo');
      expect(await saved(tester, files), original);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'a colour and the fill box change the chosen element at once, one step each, and an imported wide stroke keeps its width',
    (tester) async {
      final files = await start(
        tester,
        MemoryRecovery(),
        rgb: 0x123456,
        width: 96,
      );
      final original = files.projects[files.savePath!]!;
      await select(tester);
      expect(
        tester.widget<ColorPalette>(find.byType(ColorPalette)).selectedRgb,
        0x123456,
      );
      await tap(tester, 'color-d75e56');
      final recoloured = objects(await saved(tester, files)).single;
      expect(recoloured.rgb, 0xd75e56);
      expect(
        recoloured.width,
        96,
        reason: 'Unchanged width outside slider range is preserved.',
      );
      expect(recoloured.fillRgb, 0xeebf4e);
      // The same colour again is no edit: nothing more to undo.
      await tap(tester, 'color-d75e56');
      await tap(tester, 'fillShapeCheckbox');
      final emptied = objects(await saved(tester, files)).single;
      expect(emptied.rgb, 0xd75e56);
      expect(emptied.width, 96);
      expect(emptied.fillRgb, isNull);
      expect(find.byKey(const Key('applySelectionStyle')), findsNothing);
      await tap(tester, 'undo');
      final refilled = objects(await saved(tester, files)).single;
      expect(refilled.rgb, 0xd75e56);
      expect(refilled.fillRgb, 0xeebf4e);
      await tap(tester, 'undo');
      expect(await saved(tester, files), original);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'Autres couleurs, a recent colour and the fill box ticked again change the chosen element at once',
    (tester) async {
      // A window tall enough for the line of recent colours.
      final files = await start(
        tester,
        MemoryRecovery(),
        size: const Size(1280, 1100),
      );
      final original = files.projects[files.savePath!]!;
      await select(tester);
      expect(find.text('RÉCENTES'), findsOneWidget);
      // A shade of the chooser, once confirmed there.
      await tap(tester, 'morePaintColors');
      expect(find.byKey(const Key('paintColorDialog')), findsOneWidget);
      await tap(tester, 'shade-ef9439');
      await tap(tester, 'confirmPaintColor');
      expect(find.byKey(const Key('paintColorDialog')), findsNothing);
      expect(objects(await saved(tester, files)).single.rgb, 0xef9439);
      // A colour of the row, then the shade again from the recent ones.
      await tap(tester, 'color-d75e56');
      expect(objects(await saved(tester, files)).single.rgb, 0xd75e56);
      final recent = find.byKey(const Key('recent-paint-color-ef9439'));
      expect(recent, findsOneWidget);
      await tester.ensureVisible(recent);
      await tester.tap(recent);
      await tester.pumpAndSettle();
      expect(objects(await saved(tester, files)).single.rgb, 0xef9439);
      // The inside taken away, then given back with its colour.
      await tap(tester, 'fillShapeCheckbox');
      expect(objects(await saved(tester, files)).single.fillRgb, isNull);
      await tap(tester, 'fillShapeCheckbox');
      expect(objects(await saved(tester, files)).single.fillRgb, 0xeebf4e);
      // Five changes, five steps back to the drawing as it was opened.
      for (var step = 0; step < 4; step++) {
        await tap(tester, 'undo');
      }
      // One step is left: the first colour given, still on the element.
      expect(objects(await saved(tester, files)).single.rgb, 0xef9439);
      await tap(tester, 'undo');
      expect(await saved(tester, files), original);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'a choice that the chosen element cannot take at that moment is not kept by the controls',
    (tester) async {
      final files = await start(tester, MemoryRecovery());
      final original = files.projects[files.savePath!]!;
      await select(tester);
      final palette = find.byType(ColorPalette);
      expect(tester.widget<ColorPalette>(palette).selectedRgb, 0x477fb2);

      // A finger holds the element; another one taps a colour. The element
      // is not changed under the first finger, and the palette goes on
      // showing the colour that the element has.
      final holding = await tester.startGesture(point(tester, 500, 350));
      await tester.pump();
      await tester.tap(find.byKey(const Key('color-d75e56')));
      await tester.pump();
      expect(tester.widget<ColorPalette>(palette).selectedRgb, 0x477fb2);
      await holding.up();
      await tester.pumpAndSettle();
      expect(await saved(tester, files), original);

      // The help asked for in the middle of a slide of the width: the slide
      // is given up, and the slider goes back to the width of the element.
      await select(tester);
      final width = find.byType(BrushWidthControl);
      expect(tester.widget<BrushWidthControl>(width).value, 12);
      final sliding = await tester.startGesture(tester.getCenter(width));
      await sliding.moveBy(const Offset(20, 0));
      await tester.pump();
      await sliding.moveBy(const Offset(8, 0));
      await tester.pump();
      expect(tester.widget<BrushWidthControl>(width).value, isNot(12));
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('helpDialog')), findsOneWidget);
      await sliding.up();
      await tester.tap(find.byKey(const Key('closeHelp')));
      await tester.pumpAndSettle();
      expect(tester.widget<BrushWidthControl>(width).value, 12);
      expect(await saved(tester, files), original);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'selection layout stays stable on a small window and empty click clears it',
    (tester) async {
      await start(tester, MemoryRecovery(), size: const Size(680, 520));
      final before = tester.getRect(surface);
      expect(
        before.height,
        greaterThan(80),
        reason: 'Small windows keep a usable drawing page.',
      );
      await select(tester);
      expect(
        tester.getRect(surface),
        before,
        reason: 'Selecting must not move the page beneath the pointer.',
      );
      expect(tester.takeException(), isNull);
      await tester.tapAt(point(tester, 100, 100));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('deleteSelection')))
            .onPressed,
        isNull,
      );
      expect(tester.getSize(surface).height, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'movement is clamped to the page and a new document clears selection',
    (tester) async {
      final files = await start(tester, MemoryRecovery());
      await select(tester);
      final gesture = await tester.startGesture(point(tester, 500, 350));
      await gesture.moveTo(point(tester, 0, 0) - const Offset(500, 500));
      await gesture.up();
      await tester.pumpAndSettle();
      final moved = objects(await saved(tester, files)).single;
      expect(moved.points.first.x, 0);
      expect(moved.points.first.y, 0);
      await tap(tester, 'newProject');
      await tap(tester, 'createNewSheet');
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('deleteSelection')))
            .onPressed,
        isNull,
      );
      expect(objects(await saved(tester, files)), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'a click on the width changes the chosen element at once; a slide changes it once, when it ends',
    (tester) async {
      final recovery = MemoryRecovery();
      final files = await start(tester, recovery);
      final original = files.projects[files.savePath!]!;
      await select(tester);
      final width = find.byType(BrushWidthControl);
      // A click on the track is one choice.
      await tester.tapAt(tester.getCenter(width));
      await tester.pumpAndSettle();
      final clicked = tester.widget<BrushWidthControl>(width).value;
      expect(clicked, isNot(12));
      final afterClick = await saved(tester, files);
      expect(objects(afterClick).single.width, clicked);
      // While the thumb slides, the element waits.
      await tester.pump(const Duration(milliseconds: 600));
      final baseline = recovery.writes;
      final thumb = Offset(
        tester.getTopLeft(width).dx +
            20 +
            (tester.getSize(width).width - 40) * (clicked - 2) / 46,
        tester.getCenter(width).dy,
      );
      final gesture = await tester.startGesture(thumb);
      // The first move only tells a slide from a click.
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(const Duration(milliseconds: 600));
      final sliding = tester.widget<BrushWidthControl>(width).value;
      expect(sliding, greaterThan(clicked));
      expect(
        recovery.writes,
        baseline,
        reason: 'A width that is still sliding is not an edit.',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      final slid = tester.widget<BrushWidthControl>(width).value;
      expect(objects(await saved(tester, files)).single.width, slid);
      expect(slid, greaterThan(clicked));
      await tap(tester, 'undo');
      expect(
        await saved(tester, files),
        afterClick,
        reason: 'The whole slide is one undo step.',
      );
      await tap(tester, 'undo');
      expect(await saved(tester, files), original);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'Save settles a held movement once and keyboard nudges respect focus',
    (tester) async {
      final files = await start(tester, MemoryRecovery());
      await select(tester);
      final gesture = await tester.startGesture(point(tester, 500, 350));
      await gesture.moveTo(point(tester, 530, 390));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final savedWhileHeld = files.projects[files.savePath!]!;
      expect(objects(savedWhileHeld).single.points.first.x, closeTo(430, .001));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(await saved(tester, files), savedWhileHeld);
      await select(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      final nudged = objects(await saved(tester, files)).single;
      expect(nudged.points.first.x, closeTo(431, .001));
      expect(nudged.points.first.y, closeTo(300, .001));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('deleteSelection')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets('About settles the captured movement before showing a modal', (
    tester,
  ) async {
    final files = await start(tester, MemoryRecovery());
    final original = files.projects[files.savePath!]!;
    await select(tester);
    final gesture = await tester.startGesture(point(tester, 500, 350));
    await gesture.moveTo(point(tester, 530, 390));
    tester
        .widget<EduPaintDesktopMenu>(find.byType(EduPaintDesktopMenu))
        .onAbout!();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    // The listener that captured pointer-down can still receive events while
    // a dialog overlays the page. They must no longer mutate the document.
    await gesture.moveTo(point(tester, 650, 500));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revenir au dessin'));
    await tester.pumpAndSettle();
    final moved = objects(await saved(tester, files)).single;
    expect(moved.points.first.x, closeTo(430, .001));
    expect(moved.points.first.y, closeTo(290, .001));
    await tap(tester, 'undo');
    expect(await saved(tester, files), original);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !available);

  testWidgets(
    'modified arrows in the width control never move the selected object',
    (tester) async {
      final recovery = MemoryRecovery();
      final files = await start(tester, recovery);
      final original = objects(files.projects[files.savePath!]!).single;
      await select(tester);
      final width = find.byType(BrushWidthControl);
      await tester.tapAt(tester.getCenter(width));
      await tester.pumpAndSettle();
      final before = tester.widget<BrushWidthControl>(width).value;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tester.widget<BrushWidthControl>(width).value, before + 1);
      // The click and the key have each changed the width of the element.
      await tester.pump(const Duration(milliseconds: 600));
      final widthEdits = recovery.writes;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (final arrow in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      ]) {
        await tester.sendKeyEvent(arrow);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        recovery.writes,
        widthEdits,
        reason:
            'Even cancelling arrow movements must not create document edits.',
      );
      final kept = objects(await saved(tester, files)).single;
      expect(
        [
          for (final point in kept.points) ...[point.x, point.y],
        ],
        [
          for (final point in original.points) ...[point.x, point.y],
        ],
        reason: 'The element has not moved.',
      );
      expect(kept.width, before + 1);
      expect(kept.rgb, original.rgb);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'clicking the empty page margin clears selection without editing',
    (tester) async {
      final files = await start(tester, MemoryRecovery());
      final original = files.projects[files.savePath!]!;
      await select(tester);
      await tester.tapAt(tester.getTopLeft(surface) + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('deleteSelection')))
            .onPressed,
        isNull,
      );
      expect(await saved(tester, files), original);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'copy after a fractional drag to the page edge remains valid and undoable',
    (tester) async {
      final files = await start(tester, MemoryRecovery());
      await select(tester);
      final gesture = await tester.startGesture(point(tester, 500, 350));
      // 650 + f32(538.7) is held more precisely by Rust than its f32 snapshot.
      // Clamping a subsequent copy from the snapshot used to exceed page width.
      await gesture.moveTo(point(tester, 1038.7, 638.7));
      await gesture.up();
      await tester.pumpAndSettle();
      final moved = await saved(tester, files);
      await tap(tester, 'duplicateSelection');
      expect(find.byType(SnackBar), findsNothing);
      final copied = await saved(tester, files);
      final data = objects(copied);
      expect(data, hasLength(2));
      expect(data.last.points.last.x, closeTo(1200, .001));
      expect(data.last.points.last.y, closeTo(800, .001));
      for (final object in data) {
        for (final point in object.points) {
          expect(point.x, inInclusiveRange(0, 1200));
          expect(point.y, inInclusiveRange(0, 800));
        }
      }
      await tap(tester, 'undo');
      expect(await saved(tester, files), moved);
      await tap(tester, 'redo');
      expect(await saved(tester, files), copied);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );
}
