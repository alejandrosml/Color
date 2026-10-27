import 'dart:io';

import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/new_sheet_dialog.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';

class _Recovery extends MemoryRecovery {
  int clears = 0;
  bool failClear = false;
  @override
  Future<void> clearRecovery() async {
    clears++;
    if (failClear) throw const FileSystemException('Test clear failure');
    await super.clearRecovery();
  }
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  final surface = find.byKey(const Key('drawingSurface'));
  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    if (key == 'openProject') {
      await waitForPreparedOpen(tester, allowSaveDecision: true);
    } else {
      await tester.pumpAndSettle();
    }
  }

  EduPaintDesktopMenu menu(WidgetTester tester) =>
      tester.widget(find.byType(EduPaintDesktopMenu));
  dynamic painter(WidgetTester tester) => tester
      .widget<CustomPaint>(
        find.descendant(of: surface, matching: find.byType(CustomPaint)).first,
      )
      .painter;
  Future<void> start(
    WidgetTester tester,
    MemoryFiles files,
    _Recovery recovery, {
    bool small = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = small
        ? const Size(680, 520)
        : const Size(1100, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (small) {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(
      EduPaintApp(files: files, recoveryStorage: recovery),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('newSheetDialog')), findsNothing);
    final viewport = painter(tester).viewport as DocumentViewport;
    expect((viewport.documentWidth, viewport.documentHeight), (1200.0, 800.0));
  }

  Future<void> draw(WidgetTester tester) async {
    final gesture = await tester.startGesture(tester.getCenter(surface));
    await gesture.moveBy(const Offset(20, 10));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, NewSheetShape shape) async {
    await tap(tester, 'newProject');
    await tap(tester, 'newSheet-${shape.name}');
    await tap(tester, 'createNewSheet');
  }

  Future<String> svg(WidgetTester tester, MemoryFiles files) async {
    menu(tester).onExportSvg!();
    await tester.pumpAndSettle();
    return files.svg!;
  }

  for (final escape in [false, true]) {
    testWidgets(
      'cancelling shape preserves saved destination, dirty history and recovery (Escape=$escape)',
      (tester) async {
        final files = MemoryFiles();
        final recovery = _Recovery();
        await start(tester, files, recovery);
        await draw(tester);
        await tap(tester, 'saveProject');
        await draw(tester);
        await tap(tester, 'zoomIn');
        final viewBefore =
            (painter(tester).viewport as DocumentViewport).transform;
        final before = await svg(tester, files);
        final recovered = Uint8List.fromList(recovery.bytes!);
        final writes = recovery.writes,
            clears = recovery.clears,
            dialogs = files.saveDialogCount;
        final saved = Uint8List.fromList(files.projects[files.savePath]!);
        final callbacks = menu(tester);
        await tap(tester, 'newProject');
        await tap(tester, 'newSheet-portrait');
        callbacks.onNew!();
        callbacks.onSave!();
        callbacks.onOpen!();
        callbacks.onUndo!();
        callbacks.onAbout!();
        for (final modifier in [
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.controlLeft,
        ]) {
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
          await tester.sendKeyUpEvent(modifier);
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('newSheetDialog')), findsOneWidget);
        expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
        expect(find.byKey(const Key('saveChanges')), findsNothing);
        if (escape) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        } else {
          await tap(tester, 'cancelNewSheet');
        }
        expect(files.saveDialogCount, dialogs);
        expect(recovery.writes, writes);
        expect(recovery.clears, clears);
        expect(recovery.bytes, recovered);
        expect(files.projects[files.savePath], saved);
        final viewAfter =
            (painter(tester).viewport as DocumentViewport).transform;
        expect(
          (viewAfter.scale, viewAfter.left, viewAfter.top),
          (viewBefore.scale, viewBefore.left, viewBefore.top),
        );
        expect(await svg(tester, files), before);
        expect(files.exportSourcePath, files.savePath);
        // Returning from the modal restores keyboard access to Nouveau.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('newSheetDialog')), findsOneWidget);
        expect(
          tester
              .widget<RadioGroup<NewSheetShape>>(
                find.byType(RadioGroup<NewSheetShape>),
              )
              .groupValue,
          NewSheetShape.landscape,
        );
        await tap(tester, 'cancelNewSheet');
        await tap(tester, 'undo');
        expect(
          find.textContaining('1 élément · projet enregistré'),
          findsOneWidget,
        );
        await tap(tester, 'redo');
        expect(await svg(tester, files), before);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: !available,
    );
  }

  for (final shape in NewSheetShape.values) {
    testWidgets(
      'new ${shape.label} preserves dimensions in viewport/project/SVG at 680x520 text150%',
      (tester) async {
        final files = MemoryFiles();
        final recovery = _Recovery();
        await start(tester, files, recovery, small: true);
        await tap(tester, 'zoomIn');
        expect(
          (painter(tester).viewport as DocumentViewport).transform.isFit,
          isFalse,
        );
        await choose(tester, shape);
        expect(find.byKey(const Key('saveChanges')), findsNothing);
        final viewport = painter(tester).viewport as DocumentViewport;
        expect(
          (viewport.documentWidth, viewport.documentHeight),
          (shape.width.toDouble(), shape.height.toDouble()),
        );
        expect(
          viewport.width / viewport.height,
          closeTo(shape.width / shape.height, .001),
        );
        expect(viewport.scale, greaterThan(0));
        expect(viewport.transform.isFit, isTrue);
        await draw(tester);
        final image = await svg(tester, files);
        expect(files.exportSourcePath, isNull);
        await tap(tester, 'saveProject');
        final loaded = RustDocument.fromProject(
          files.projects[files.savePath]!,
        );
        try {
          expect((loaded.width, loaded.height), (shape.width, shape.height));
          expect(loaded.count, 1);
          expect(loaded.exportSvg(), image);
          expect(
            image,
            contains('viewBox="0 0 ${shape.width} ${shape.height}"'),
          );
        } finally {
          loaded.dispose();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: !available,
    );
  }

  for (final outcome in [
    'save',
    'cancel-save',
    'failed-save',
    'cancel-confirmation',
    'discard',
  ]) {
    testWidgets('dirty new page transaction: $outcome', (tester) async {
      final files = MemoryFiles();
      final recovery = _Recovery();
      await start(tester, files, recovery);
      await draw(tester);
      final before = await svg(tester, files);
      final recovered = Uint8List.fromList(recovery.bytes!);
      await choose(tester, NewSheetShape.portrait);
      expect(find.byKey(const Key('saveChanges')), findsOneWidget);
      expect(files.saveDialogCount, 0);
      if (outcome == 'cancel-save') files.savePath = null;
      if (outcome == 'failed-save') files.failWrite = true;
      await tap(
        tester,
        outcome == 'cancel-confirmation'
            ? 'cancelChanges'
            : outcome == 'discard'
            ? 'discardChanges'
            : 'saveChanges',
      );
      final replaced = outcome == 'save' || outcome == 'discard';
      final viewport = painter(tester).viewport as DocumentViewport;
      expect((
        viewport.documentWidth,
        viewport.documentHeight,
      ), replaced ? (800.0, 1200.0) : (1200.0, 800.0));
      if (replaced) {
        expect(recovery.bytes, isNull);
        expect(
          find.textContaining('0 élément · nouvelle feuille'),
          findsOneWidget,
        );
        expect(menu(tester).onUndo, isNull);
        expect(menu(tester).onRedo, isNull);
        if (outcome == 'save') {
          final saved = RustDocument.fromProject(
            files.projects[files.savePath]!,
          );
          try {
            expect(saved.exportSvg(), before);
            expect((saved.width, saved.height), (1200, 800));
          } finally {
            saved.dispose();
          }
        }
        await svg(tester, files);
        expect(files.exportSourcePath, isNull);
      } else {
        expect(recovery.bytes, recovered);
        expect(recovery.clears, 0);
        files.failWrite = false;
        expect(await svg(tester, files), before);
        expect(menu(tester).onUndo, isNotNull);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, skip: !available);
  }

  testWidgets(
    'failed recovery clear keeps the old drawing after a shape is chosen',
    (tester) async {
      final files = MemoryFiles();
      final recovery = _Recovery();
      await start(tester, files, recovery);
      await draw(tester);
      final before = await svg(tester, files);
      final recovered = Uint8List.fromList(recovery.bytes!);
      recovery.failClear = true;
      await choose(tester, NewSheetShape.square);
      await tap(tester, 'discardChanges');
      expect(recovery.bytes, recovered);
      expect(recovery.clears, 1);
      expect(await svg(tester, files), before);
      expect(
        (painter(tester).viewport as DocumentViewport).documentHeight,
        800,
      );
      expect(menu(tester).onUndo, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  for (final selection in [false, true]) {
    for (final modifier in [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.controlLeft,
    ]) {
      testWidgets(
        'Nouveau ignores a held ${selection ? 'selection' : 'stroke'} with $modifier',
        (tester) async {
          final files = MemoryFiles();
          final recovery = _Recovery();
          await start(tester, files, recovery);
          if (selection) {
            final seed = RustDocument();
            try {
              seed.addShape(
                VectorKind.rectangle,
                const DocumentPoint(400, 250),
                const DocumentPoint(650, 500),
                rgb: 0x477fb2,
                width: 12,
                fillRgb: 0xeebf4e,
              );
              files.projects[files.savePath!] = seed.exportProject();
            } finally {
              seed.dispose();
            }
            files.openPath = files.savePath;
            await tap(tester, 'openProject');
            await tap(tester, 'tool-select');
          }
          final before = await svg(tester, files);
          final current = painter(tester);
          final viewport = current.viewport as DocumentViewport;
          final origin =
              tester.getTopLeft(surface) +
              Offset(
                viewport.left + 500 * viewport.scale,
                viewport.top + 350 * viewport.scale,
              );
          final gesture = await tester.startGesture(origin);
          await gesture.moveBy(const Offset(20, 10));
          await tester.pump();
          if (selection) {
            expect(painter(tester).selectedIndex, 0);
            expect(painter(tester).selectionOffset.value, isNot(Offset.zero));
          }
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
          await tester.sendKeyUpEvent(modifier);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('newSheetDialog')), findsNothing);
          expect(identical(painter(tester).strokes, current.strokes), isTrue);
          await gesture.up();
          await tester.pumpAndSettle();
          await tap(tester, 'newProject');
          expect(find.byKey(const Key('newSheetDialog')), findsOneWidget);
          await tap(tester, 'cancelNewSheet');
          expect(await svg(tester, files), isNot(before));
          await tap(tester, 'undo');
          expect(await svg(tester, files), before);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        skip: !available,
      );
    }
  }

  for (final trackpad in [false, true]) {
    testWidgets(
      'Nouveau ignores an active ${trackpad ? 'trackpad' : 'middle-button'} view gesture',
      (tester) async {
        final files = MemoryFiles();
        final recovery = _Recovery();
        await start(tester, files, recovery);
        final before = await svg(tester, files);
        final center = tester.getCenter(surface);
        TestGesture? mouse;
        if (trackpad) {
          await tester.sendEventToBinding(
            PointerPanZoomStartEvent(pointer: 44, position: center),
          );
          await tester.sendEventToBinding(
            PointerPanZoomUpdateEvent(
              pointer: 44,
              position: center,
              pan: const Offset(20, 10),
              panDelta: const Offset(20, 10),
            ),
          );
        } else {
          mouse = await tester.startGesture(
            center,
            buttons: kMiddleMouseButton,
            kind: PointerDeviceKind.mouse,
          );
          await mouse.moveBy(const Offset(20, 10));
        }
        await tester.pump();
        expect(
          (painter(tester).viewport as DocumentViewport).transform.isFit,
          isFalse,
        );
        menu(tester).onNew!();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('newSheetDialog')), findsNothing);
        expect(menu(tester).onUndo, isNull);
        if (trackpad) {
          await tester.sendEventToBinding(
            PointerPanZoomEndEvent(pointer: 44, position: center),
          );
        } else {
          await mouse!.up();
        }
        await tester.pumpAndSettle();
        await tap(tester, 'newProject');
        expect(find.byKey(const Key('newSheetDialog')), findsOneWidget);
        await tap(tester, 'cancelNewSheet');
        expect(await svg(tester, files), before);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: !available,
    );
  }

  testWidgets(
    'unmounting the shape chooser never clears recovery or creates a document',
    (tester) async {
      final files = MemoryFiles();
      final recovery = _Recovery();
      await start(tester, files, recovery);
      await draw(tester);
      final recovered = Uint8List.fromList(recovery.bytes!);
      await tap(tester, 'newProject');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(recovery.bytes, recovered);
      expect(recovery.clears, 0);
      expect(files.saveDialogCount, 0);
      expect(tester.takeException(), isNull);
    },
    skip: !available,
  );
}
