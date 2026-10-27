// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/rust_document.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';

class _ControlledRecovery extends MemoryRecovery {
  Completer<void>? nextWrite;
  Completer<void>? nextClear;
  int clearsStarted = 0;
  bool failNextClear = false;
  final captured = <Uint8List>[];
  @override
  Future<void> writeRecovery(Uint8List value) async {
    final snapshot = Uint8List.fromList(value);
    captured.add(snapshot);
    final barrier = nextWrite;
    nextWrite = null;
    if (barrier != null) await barrier.future;
    await super.writeRecovery(snapshot);
  }

  @override
  Future<void> clearRecovery() async {
    clearsStarted++;
    final barrier = nextClear;
    nextClear = null;
    if (barrier != null) await barrier.future;
    if (failNextClear) {
      failNextClear = false;
      throw const FileSystemException('Simulated recovery clear failure');
    }
    await super.clearRecovery();
  }
}

class _ImageFiles extends MemoryFiles {
  @override
  Future<String?> chooseImage() async => '/source.png';
  @override
  Future<Uint8List> readImage(String path) async =>
      File('test/fixtures/raster/rgb-asymmetric.png').readAsBytesSync();
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  EduPaintDesktopMenu menu(WidgetTester tester) =>
      tester.widget<EduPaintDesktopMenu>(find.byType(EduPaintDesktopMenu));
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
    await tester.pumpAndSettle();
  }

  Future<void> draw(WidgetTester tester, [double offset = 0]) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('drawingSurface'))) +
          Offset(offset, 0),
    );
    await gesture.moveBy(const Offset(50, -20));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> recover(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Future<void> action(WidgetTester tester, void Function()? callback) async {
    expect(callback, isNotNull);
    callback!();
    await tester.pumpAndSettle();
  }

  Future<void> workerAction(
    WidgetTester tester,
    void Function()? callback,
  ) async {
    expect(callback, isNotNull);
    callback!();
    for (var attempt = 0; attempt < 300; attempt++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (menu(tester).onSave != null) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    fail('Native image/worker action did not finish.');
  }

  int count(Uint8List bytes) {
    final document = RustDocument.fromProject(bytes);
    try {
      return document.count;
    } finally {
      document.dispose();
    }
  }

  testWidgets(
    'saved drawing + extra stroke + Undo is clean with exact SVG and no abandonment prompt',
    (tester) async {
      final files = MemoryFiles();
      final recovery = MemoryRecovery();
      await start(tester, files, recovery);
      await draw(tester);
      await action(tester, menu(tester).onSave);
      final saved = RustDocument.fromProject(files.projects[files.savePath]!);
      final expectedSvg = saved.exportSvg();
      saved.dispose();
      await draw(tester, 80);
      await recover(tester);
      expect(count(recovery.bytes!), 2);
      await action(tester, menu(tester).onUndo);
      expect(
        find.textContaining('1 élément · projet enregistré'),
        findsOneWidget,
      );
      await action(tester, menu(tester).onExportSvg);
      expect(files.svg, expectedSvg);
      await recover(tester);
      expect(recovery.bytes, isNull);
      await action(tester, menu(tester).onRedo);
      expect(
        find.textContaining('2 éléments · modifications non enregistrées'),
        findsOneWidget,
      );
      await action(tester, menu(tester).onUndo);
      await action(tester, menu(tester).onNew);
      await tester.tap(find.byKey(const Key('createNewSheet')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('saveChanges')), findsNothing);
      expect(
        find.textContaining('0 élément · nouvelle feuille'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'branch at same command depth is dirty and retains the close confirmation',
    (tester) async {
      final files = MemoryFiles();
      await start(tester, files, MemoryRecovery());
      await draw(tester);
      await draw(tester, 60);
      await action(tester, menu(tester).onSave);
      await action(tester, menu(tester).onUndo);
      await draw(tester, -80);
      expect(
        find.textContaining('2 éléments · modifications non enregistrées'),
        findsOneWidget,
      );
      await action(tester, menu(tester).onNew);
      await tester.tap(find.byKey(const Key('createNewSheet')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('saveChanges')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancelChanges')));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 éléments'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'opened state is a clean point but recovered state stays unsaved after redo',
    (tester) async {
      final source = RustDocument();
      source.addStroke(
        const [DocumentPoint(40, 40), DocumentPoint(80, 70)],
        rgb: 0x112233,
        width: 4,
      );
      final bytes = source.exportProject();
      source.dispose();
      final files = MemoryFiles()..openPath = '/saved.edupaint';
      files.projects[files.openPath!] = bytes;
      await start(tester, files, MemoryRecovery());
      await workerAction(tester, menu(tester).onOpen);
      await action(tester, menu(tester).onUndo);
      await action(tester, menu(tester).onRedo);
      expect(
        find.textContaining('1 élément · projet enregistré'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        EduPaintApp(
          files: MemoryFiles(),
          recoveryStorage: MemoryRecovery(bytes),
        ),
      );
      await waitForPreparedOpen(tester, allowRecoveryDecision: true);
      await tester.tap(find.byKey(const Key('restoreRecovery')));
      await waitForPreparedOpen(tester);
      await action(tester, menu(tester).onUndo);
      await action(tester, menu(tester).onRedo);
      expect(
        find.textContaining('1 élément · modifications non enregistrées'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'imported background stays unsaved after Undo; saved background retains exact clean point',
    (tester) async {
      final files = _ImageFiles();
      final recovery = MemoryRecovery();
      await start(tester, files, recovery);
      await workerAction(tester, menu(tester).onImportImage);
      expect(
        find.textContaining('0 élément · modifications non enregistrées'),
        findsOneWidget,
      );
      await draw(tester);
      await action(tester, menu(tester).onUndo);
      expect(
        find.textContaining('0 élément · modifications non enregistrées'),
        findsOneWidget,
      );
      files.savePath = null;
      await action(tester, menu(tester).onSaveAs);
      expect(files.projects, isEmpty);
      expect(
        find.textContaining('modifications non enregistrées'),
        findsOneWidget,
      );
      files.savePath = '/background.edupaint';
      await workerAction(tester, menu(tester).onSave);
      final saved = RustDocument.fromProject(files.projects[files.savePath]!);
      expect(saved.backgroundInfo, isNotNull);
      final originalPng = saved.copyBackgroundPng();
      saved.dispose();
      expect(
        find.textContaining('0 élément · projet enregistré'),
        findsOneWidget,
      );
      await draw(tester);
      await action(tester, menu(tester).onUndo);
      expect(
        find.textContaining('0 élément · projet enregistré'),
        findsOneWidget,
      );
      await action(tester, menu(tester).onRedo);
      expect(
        find.textContaining('1 élément · modifications non enregistrées'),
        findsOneWidget,
      );
      files.failWrite = true;
      await workerAction(tester, menu(tester).onSave);
      await action(tester, menu(tester).onUndo);
      expect(
        find.textContaining('0 élément · projet enregistré'),
        findsOneWidget,
      );
      final unchanged = RustDocument.fromProject(
        files.projects[files.savePath]!,
      );
      expect(unchanged.copyBackgroundPng(), originalPng);
      unchanged.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'cancelled and failed Save As preserve the previous saved point and destination',
    (tester) async {
      final files = MemoryFiles();
      await start(tester, files, MemoryRecovery());
      await draw(tester);
      await action(tester, menu(tester).onSave);
      final originalPath = files.savePath!;
      final originalBytes = Uint8List.fromList(files.projects[originalPath]!);
      await draw(tester, 80);
      files.savePath = null;
      await action(tester, menu(tester).onSaveAs);
      await action(tester, menu(tester).onUndo);
      expect(
        find.textContaining('1 élément · projet enregistré'),
        findsOneWidget,
      );
      await action(tester, menu(tester).onRedo);
      files.savePath = '/failed-save-as.edupaint';
      files.failWrite = true;
      await action(tester, menu(tester).onSaveAs);
      await action(tester, menu(tester).onUndo);
      expect(
        find.textContaining('1 élément · projet enregistré'),
        findsOneWidget,
      );
      files.failWrite = false;
      await action(tester, menu(tester).onExportSvg);
      expect(files.exportSourcePath, originalPath);
      expect(files.projects[originalPath], originalBytes);
      expect(files.projects.containsKey('/failed-save-as.edupaint'), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'failed recovery erase on initial clean sheet never claims a project was saved',
    (tester) async {
      final files = MemoryFiles();
      final recovery = _ControlledRecovery();
      await start(tester, files, recovery);
      await draw(tester);
      await recover(tester);
      expect(recovery.bytes, isNotNull);
      recovery.failNextClear = true;
      await action(tester, menu(tester).onUndo);
      await recover(tester);
      expect(files.projects, isEmpty);
      expect(
        find.textContaining('0 élément · nouvelle feuille'),
        findsOneWidget,
      );
      expect(find.textContaining('Dessin enregistré'), findsNothing);
      expect(find.textContaining('Ton dessin est enregistré'), findsNothing);
      expect(
        find.textContaining(
          'L’ancienne copie de récupération n’a pas pu être retirée',
        ),
        findsOneWidget,
      );
      expect(
        recovery.bytes,
        isNotNull,
        reason: 'A failed erase preserves the previous recovery.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'returning clean drains an old recovery write then removes its obsolete snapshot',
    (tester) async {
      final files = MemoryFiles();
      final recovery = _ControlledRecovery();
      await start(tester, files, recovery);
      await draw(tester);
      await action(tester, menu(tester).onSave);
      final before = recovery.clearsStarted;
      final barrier = Completer<void>();
      recovery.nextWrite = barrier;
      await draw(tester, 60);
      await recover(tester);
      expect(count(recovery.captured.last), 2);
      await action(tester, menu(tester).onUndo);
      await recover(tester);
      expect(
        recovery.clearsStarted,
        before,
        reason: 'The clean clear cannot overtake the active write.',
      );
      barrier.complete();
      await recover(tester);
      expect(recovery.bytes, isNull);
      expect(recovery.clearsStarted, before + 1);
      expect(
        find.textContaining('1 élément · projet enregistré'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets('new edit during clean recovery removal is written afterwards', (
    tester,
  ) async {
    final files = MemoryFiles();
    final recovery = _ControlledRecovery();
    await start(tester, files, recovery);
    await draw(tester);
    await action(tester, menu(tester).onSave);
    await draw(tester, 60);
    await recover(tester);
    final barrier = Completer<void>();
    recovery.nextClear = barrier;
    await action(tester, menu(tester).onUndo);
    await recover(tester);
    final captured = recovery.captured.length;
    await draw(tester, -80);
    await recover(tester);
    expect(
      recovery.captured.length,
      captured,
      reason: 'No newer write during a pending clear.',
    );
    barrier.complete();
    await recover(tester);
    expect(count(recovery.bytes!), 2);
    expect(recovery.captured.length, captured + 1);
    expect(
      find.textContaining('2 éléments · modifications non enregistrées'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !available);
}
