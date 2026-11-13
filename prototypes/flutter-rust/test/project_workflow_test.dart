// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  Future<void> start(
    WidgetTester tester,
    MemoryFiles files,
    MemoryRecovery recovery,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EduPaintApp(files: files, recoveryStorage: recovery),
    );
    await waitForPreparedOpen(tester, allowRecoveryDecision: true);
  }

  Future<void> draw(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('drawingSurface'))),
    );
    await gesture.moveBy(const Offset(60, -25));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    key = await revealControl(tester, key);
    if (key == 'exportSvg') await pressAction(tester, 'exportImage');
    await tester.tap(find.byKey(Key(key)));
    if (key == 'openProject') {
      await waitForPreparedOpen(tester, allowSaveDecision: true);
    } else if (key == 'restoreRecovery' || key == 'saveChanges') {
      await waitForPreparedOpen(tester);
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> finish(WidgetTester tester) async =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets(
    'save, new, reopen, resize and export preserve the real Rust drawing',
    (tester) async {
      final files = MemoryFiles();
      final recovery = MemoryRecovery();
      await start(tester, files, recovery);
      await draw(tester);
      await tap(tester, 'exportSvg');
      final before = files.svg;
      expect(files.exportSourcePath, isNull);
      await tap(tester, 'saveProject');
      expect(files.projects.length, 1);
      expect(await drawingStatus(tester), contains('projet enregistré'));
      await tap(tester, 'newProject');
      await tap(tester, 'createNewSheet');
      expect(drawingCaption(tester), contains('0 élément · '));
      files.openPath = files.savePath;
      await tap(tester, 'openProject');
      expect(drawingCaption(tester), contains('1 élément'));
      tester.view.physicalSize = const Size(680, 520);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tap(tester, 'exportSvg');
      expect(files.svg, before);
      expect(files.exportSourcePath, files.savePath);
      await tap(tester, 'undo');
      expect(drawingCaption(tester), contains('0 élément · '));
      await tap(tester, 'redo');
      expect(drawingCaption(tester), contains('1 élément'));
      await tap(tester, 'saveProject');
      expect(
        files.saveDialogCount,
        1,
        reason: 'Existing project saves to its chosen path.',
      );
      await finish(tester);
    },
    skip: !available,
  );

  testWidgets(
    'opening the current file after saving in the confirmation uses its new contents',
    (tester) async {
      final files = MemoryFiles();
      await start(tester, files, MemoryRecovery());
      await draw(tester);
      await tap(tester, 'saveProject');
      await draw(tester);
      files.openPath = files.savePath;
      await tap(tester, 'openProject');
      await tap(tester, 'saveChanges');
      expect(drawingCaption(tester), contains('2 éléments'));
      final reopened = RustDocument.fromProject(
        files.projects[files.savePath]!,
      );
      expect(reopened.count, 2);
      reopened.dispose();
      await finish(tester);
    },
    skip: !available,
  );

  testWidgets(
    'export stays dirty; cancel or failed save cannot abandon the drawing',
    (tester) async {
      final files = MemoryFiles();
      await start(tester, files, MemoryRecovery());
      await draw(tester);
      await tap(tester, 'exportSvg');
      await tap(tester, 'newProject');
      await tap(tester, 'createNewSheet');
      expect(find.byKey(const Key('saveChanges')), findsOneWidget);
      files.savePath = null;
      await tap(tester, 'saveChanges');
      expect(drawingCaption(tester), contains('1 élément'));
      files.savePath = '/drawings/new.edupaint';
      files.failWrite = true;
      await tap(tester, 'newProject');
      await tap(tester, 'createNewSheet');
      await tap(tester, 'saveChanges');
      expect(drawingCaption(tester), contains('1 élément'));
      expect(files.projects, isEmpty);
      await tap(tester, 'newProject');
      await tap(tester, 'createNewSheet');
      await tap(tester, 'cancelChanges');
      expect(drawingCaption(tester), contains('1 élément'));
      await finish(tester);
    },
    skip: !available,
  );

  testWidgets(
    'invalid opened project preserves the current document and recovery',
    (tester) async {
      final files = MemoryFiles();
      final recovery = MemoryRecovery();
      await start(tester, files, recovery);
      await draw(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      final before = Uint8List.fromList(recovery.bytes!);
      files.openPath = '/drawings/broken.edupaint';
      files.projects[files.openPath!] = Uint8List.fromList([1, 2, 3]);
      await tap(tester, 'openProject');
      expect(drawingCaption(tester), contains('1 élément'));
      expect(find.byKey(const Key('discardChanges')), findsNothing);
      expect(recovery.bytes, before);
      await finish(tester);
    },
    skip: !available,
  );

  testWidgets(
    'recovery restores a different document size and can be saved as a new project',
    (tester) async {
      final original = RustDocument(width: 640, height: 480);
      original.addStroke(
        const [DocumentPoint(30, 40), DocumentPoint(200, 180)],
        rgb: 0xe83d48,
        width: 13,
      );
      final bytes = original.exportProject();
      final svg = original.exportSvg();
      original.dispose();
      final recovery = MemoryRecovery(bytes);
      final files = MemoryFiles();
      await start(tester, files, recovery);
      await tap(tester, 'restoreRecovery');
      expect(drawingCaption(tester), contains('1 élément'));
      await tap(tester, 'exportSvg');
      expect(files.svg, svg);
      await tap(tester, 'saveProject');
      expect(recovery.bytes, isNull);
      final loaded = RustDocument.fromProject(files.projects.values.single);
      expect(loaded.exportSvg(), svg);
      loaded.dispose();
      await finish(tester);
    },
    skip: !available,
  );

  testWidgets(
    'unreadable recovery is retained and never replaced by the new drawing',
    (tester) async {
      final recovery = MemoryRecovery(Uint8List.fromList([1, 2, 3]));
      await start(tester, MemoryFiles(), recovery);
      await draw(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(recovery.bytes, [1, 2, 3]);
      expect(recovery.writes, 0);
      expect(drawingCaption(tester), contains('1 élément'));
      await finish(tester);
    },
    skip: !available,
  );
}
