// SPDX-License-Identifier: MIT
import 'dart:io';


import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/galets.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  final surface = find.byKey(const Key('drawingSurface'));

  // What holds the control is opened first: « Mon dessin », a panel, the
  // drawer of a rail.
  Future<void> tap(WidgetTester tester, String key) =>
      pressControl(tester, key);

  Future<MemoryFiles> start(
    WidgetTester tester,
    MemoryRecovery recovery, {
    Size size = const Size(1100, 760),
    int rgb = 0x3370d1,
    double width = 12,
    StudioOptions? options,
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
    final store = options == null ? null : StudioOptionsStore.memory(options);
    if (store != null) addTearDown(store.dispose);
    await tester.pumpWidget(
      EduPaintApp(files: files, recoveryStorage: recovery, options: store),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'openProject');
    await tap(tester, 'tool-select');
    expect(tester.takeException(), isNull);
    return files;
  }

  Offset point(WidgetTester tester, double x, double y) =>
      sheetPoint(tester, x, y);

  Future<void> select(WidgetTester tester) async {
    await tester.tapAt(point(tester, 500, 350));
    await tester.pumpAndSettle();
    expect(onPressedOf(tester, 'deleteSelection'), isNotNull);
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
        await tap(tester, 'color-e83d48');
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
        expect(objects(files.projects[files.savePath!]!).single.rgb, 0xe83d48);
        await tap(tester, 'undo');
        expect(objects(await saved(tester, files)).single.rgb, 0x3370d1);
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
      expect(find.byKey(const Key('deleteSelection')), findsNothing);
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
      expect(onPressedOf(tester, 'undo'), isNotNull);
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
      expect(colourInHand(tester), 0x123456);
      await tap(tester, 'color-e83d48');
      final recoloured = objects(await saved(tester, files)).single;
      expect(recoloured.rgb, 0xe83d48);
      expect(
        recoloured.width,
        96,
        reason: 'Unchanged width outside slider range is preserved.',
      );
      expect(recoloured.fillRgb, 0xeebf4e);
      // The same colour again is no edit: nothing more to undo.
      await tap(tester, 'color-e83d48');
      await tap(tester, 'fillShapeCheckbox');
      final emptied = objects(await saved(tester, files)).single;
      expect(emptied.rgb, 0xe83d48);
      expect(emptied.width, 96);
      expect(emptied.fillRgb, isNull);
      expect(find.byKey(const Key('applySelectionStyle')), findsNothing);
      await tap(tester, 'undo');
      final refilled = objects(await saved(tester, files)).single;
      expect(refilled.rgb, 0xe83d48);
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
      // « Toutes les couleurs, pour les grands » : where an adult asked
      // for it, the pebbles have « Mélanger » and the colours chosen last.
      final files = await start(
        tester,
        MemoryRecovery(),
        options: const StudioOptions(grownUpColours: true),
      );
      final original = files.projects[files.savePath!]!;
      await select(tester);
      // A shade of the chooser, once confirmed there.
      await tap(tester, 'morePaintColors');
      expect(find.byKey(const Key('paintColorDialog')), findsOneWidget);
      await tap(tester, 'shade-ef9439');
      await tap(tester, 'confirmPaintColor');
      expect(find.byKey(const Key('paintColorDialog')), findsNothing);
      expect(objects(await saved(tester, files)).single.rgb, 0xef9439);
      // A colour of the row, then the shade again from the recent ones.
      await tap(tester, 'color-e83d48');
      expect(objects(await saved(tester, files)).single.rgb, 0xe83d48);
      await tap(tester, 'recent-ef9439');
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
      expect(colourInHand(tester), 0x3370d1);

      // A finger holds the element; another one taps a colour. The element
      // is not changed under the first finger, and the palette goes on
      // showing the colour that the element has.
      final holding = await tester.startGesture(point(tester, 500, 350));
      await tester.pump();
      await tester.tap(find.byKey(const Key('color-e83d48')));
      await tester.pump();
      expect(colourInHand(tester), 0x3370d1);
      await holding.up();
      await tester.pumpAndSettle();
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
      expect(find.byKey(const Key('deleteSelection')), findsNothing);
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
      expect(find.byKey(const Key('deleteSelection')), findsNothing);
      expect(objects(await saved(tester, files)), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'a size of the panel changes the chosen element at once: one step for Annuler',
    (tester) async {
      final recovery = MemoryRecovery();
      final files = await start(tester, recovery);
      final original = files.projects[files.savePath!]!;
      await select(tester);
      await tap(tester, 'width-3');
      expect(find.byKey(const Key('galetPanel-size')), findsNothing);
      final resized = await saved(tester, files);
      expect(objects(resized).single.width, galetWidths[3]);
      // The same size again is no edit: nothing more to undo.
      await tap(tester, 'width-3');
      expect(await saved(tester, files), resized);
      await tap(tester, 'width-0');
      expect(objects(await saved(tester, files)).single.width, galetWidths[0]);
      await tap(tester, 'undo');
      expect(await saved(tester, files), resized);
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
      expect(find.byKey(const Key('deleteSelection')), findsNothing);
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
    'clicking the empty page margin clears selection without editing',
    (tester) async {
      final files = await start(tester, MemoryRecovery());
      final original = files.projects[files.savePath!]!;
      await select(tester);
      await tester.tapAt(tester.getTopLeft(surface) + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteSelection')), findsNothing);
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
