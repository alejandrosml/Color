// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';

class _Files extends MemoryFiles {
  int preparedReads = 0;
  int panels = 0;
  bool failRead = false;
  Completer<PreparedProject>? held;
  final candidates = <RustDocument>[];
  @override
  Future<String?> chooseOpen() async {
    panels++;
    return super.chooseOpen();
  }

  @override
  Future<Uint8List> read(String path) async {
    if (failRead) {
      throw const FileSystemException('Synthetic provider read failure');
    }
    return super.read(path);
  }

  @override
  Future<PreparedProject> readPrepared(String path) async {
    preparedReads++;
    final prepared = await (held?.future ?? super.readPrepared(path));
    candidates.add(prepared.document);
    return prepared;
  }
}

class _Recovery extends MemoryRecovery {
  _Recovery([super.bytes]);
  bool failClear = false;
  @override
  Future<void> clearRecovery() async {
    if (failClear) {
      throw const FileSystemException('Synthetic recovery clear failure');
    }
    return super.clearRecovery();
  }
}

Uint8List _fixture(String name) =>
    File('test/fixtures/project-open/$name').readAsBytesSync();
EduPaintDesktopMenu _menu(WidgetTester tester) =>
    tester.widget<EduPaintDesktopMenu>(find.byType(EduPaintDesktopMenu));
ui.Image? _background(WidgetTester tester) {
  final painter =
      tester
              .widget<CustomPaint>(
                find
                    .descendant(
                      of: find.byKey(const Key('drawingSurface')),
                      matching: find.byType(CustomPaint),
                    )
                    .first,
              )
              .painter
          as dynamic;
  return painter.background as ui.Image?;
}

Future<void> _mount(
  WidgetTester tester,
  _Files files,
  MemoryRecovery recovery,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 760);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(EduPaintApp(files: files, recoveryStorage: recovery));
  await waitForPreparedOpen(tester, allowRecoveryDecision: true);
}

Future<void> _tap(
  WidgetTester tester,
  String key, {
  bool decision = false,
}) async {
  await tester.tap(find.byKey(Key(key)));
  await waitForPreparedOpen(tester, allowSaveDecision: decision);
}

Future<void> _draw(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const Key('drawingSurface'))),
  );
  await gesture.moveBy(const Offset(45, -20));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _export(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('exportImage')));
  await tester.pumpAndSettle();
  await _tap(tester, 'exportSvg');
}

Future<void> _disposed(WidgetTester tester, RustDocument document) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.pump();
    try {
      document.count;
    } on StateError {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  fail('Unadopted candidate was not disposed.');
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  for (final problem in ['read', 'native', 'pixels', 'clear', 'cancel']) {
    testWidgets(
      'failed/abandoned prepared opening preserves current image and history: $problem',
      (tester) async {
        final files = _Files();
        final recovery = _Recovery();
        const original = '/drawings/original.edupaint';
        const target = '/drawings/target.edupaint';
        files.projects[original] = _fixture('rgba-v3.edupaint');
        files.openPath = original;
        files.projects[target] = _fixture(
          problem == 'native'
              ? 'bad-project-crc.edupaint'
              : problem == 'pixels'
              ? 'structural-png-undecodable.edupaint'
              : 'portrait-v2.edupaint',
        );
        await _mount(tester, files, recovery);
        await _tap(tester, 'openProject');
        final old = files.candidates.single;
        await _draw(tester);
        await _export(tester);
        final oldSvg = files.svg;
        final oldImage = _background(tester);
        final oldUndo = old.undoCount;
        final oldRedo = old.redoCount;
        expect(oldImage, isNotNull);
        expect(old.count, 2);
        expect(files.exportSourcePath, original);
        files.openPath = target;
        files.failRead = problem == 'read';
        recovery.failClear = problem == 'clear';
        await _tap(
          tester,
          'openProject',
          decision: problem == 'clear' || problem == 'cancel',
        );
        if (problem == 'clear') await _tap(tester, 'discardChanges');
        if (problem == 'cancel') await _tap(tester, 'cancelChanges');
        expect(old.undoCount, oldUndo);
        expect(old.redoCount, oldRedo);
        expect(identical(_background(tester), oldImage), isTrue);
        expect(find.textContaining('2 éléments'), findsOneWidget);
        expect(find.byKey(const Key('saveChanges')), findsNothing);
        await _export(tester);
        expect(files.svg, oldSvg);
        expect(files.exportSourcePath, original);
        if (files.candidates.length > 1) {
          expect(() => files.candidates.last.count, throwsStateError);
        }
        await _tap(tester, 'undo');
        expect(old.count, 1);
        await _tap(tester, 'redo');
        expect(old.count, 2);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: !available,
    );
  }
  testWidgets(
    'normal open loads once and save confirmation reloads exactly once',
    (tester) async {
      final files = _Files();
      const path = '/drawings/portrait.edupaint';
      files.projects[path] = _fixture('portrait-v2.edupaint');
      files.openPath = path;
      await _mount(tester, files, MemoryRecovery());
      await _tap(tester, 'openProject');
      expect(files.preparedReads, 1);
      await _draw(tester);
      final expected = files.candidates.last.exportProject();
      await _tap(tester, 'openProject', decision: true);
      expect(files.preparedReads, 2);
      await _tap(tester, 'saveChanges');
      expect(files.preparedReads, 3);
      expect(files.candidates.last.exportProject(), expected);
      expect(files.projects[path], expected);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );
  testWidgets(
    'unmount while read is held drains and disposes candidate, duplicate open disabled',
    (tester) async {
      final files = _Files();
      await _mount(tester, files, MemoryRecovery());
      final prepared = await tester.runAsync(
        () => RustDocument.loadProjectBytes(_fixture('portrait-v2.edupaint')),
      );
      final document = prepared!.document;
      files.openPath = '/drawings/held.edupaint';
      files.held = Completer<PreparedProject>();
      await tester.tap(find.byKey(const Key('openProject')));
      await tester.pump();
      await tester.pump();
      expect(files.preparedReads, 1);
      expect(files.panels, 1);
      expect(_menu(tester).onOpen, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      files.held!.complete(prepared);
      await _disposed(tester, document);
      expect(tester.takeException(), isNull);
    },
    skip: !available,
  );
  testWidgets(
    'unmount during transferred background decoding disposes candidate',
    (tester) async {
      final files = _Files();
      await _mount(tester, files, MemoryRecovery());
      final prepared = await tester.runAsync(
        () => RustDocument.loadProjectBytes(_fixture('rgba-v3.edupaint')),
      );
      final document = prepared!.document;
      files.openPath = '/drawings/held-image.edupaint';
      files.held = Completer<PreparedProject>();
      await tester.tap(find.byKey(const Key('openProject')));
      await tester.pump();
      await tester.pump();
      files.held!.complete(prepared);
      await tester.pump();
      expect(
        prepared.takeBackground,
        throwsStateError,
        reason: 'The UI has consumed the transfer for decoding.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _disposed(tester, document);
      expect(tester.takeException(), isNull);
    },
    skip: !available,
  );
  testWidgets('undecodable recovery is kept and never adopted or overwritten', (
    tester,
  ) async {
    final bytes = _fixture('structural-png-undecodable.edupaint');
    final recovery = _Recovery(bytes);
    await _mount(tester, _Files(), recovery);
    expect(find.byKey(const Key('restoreRecovery')), findsNothing);
    expect(recovery.bytes, bytes);
    expect(recovery.writes, 0);
    expect(_background(tester), isNull);
    await _draw(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(recovery.bytes, bytes);
    expect(recovery.writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !available);
}
