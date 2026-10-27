// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';

import 'support/memory_files.dart';

class _SlowRecovery extends MemoryRecovery {
  final firstWrite = Completer<void>();
  final captured = <Uint8List>[];
  int clears = 0;

  @override
  Future<void> writeRecovery(Uint8List value) async {
    final snapshot = Uint8List.fromList(value);
    captured.add(snapshot);
    writes++;
    if (writes == 1) await firstWrite.future;
    bytes = snapshot;
  }

  @override
  Future<void> clearRecovery() async {
    clears++;
    bytes = null;
  }
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  Future<void> start(
    WidgetTester tester,
    MemoryFiles files,
    _SlowRecovery recovery,
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

  Future<void> draw(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('drawingSurface'))),
    );
    await gesture.moveBy(const Offset(60, -25));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
  }

  int objects(Uint8List bytes) {
    final document = RustDocument.fromProject(bytes);
    try {
      return document.count;
    } finally {
      document.dispose();
    }
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('saving during a slow recovery cancels pending old snapshots', (
    tester,
  ) async {
    final files = MemoryFiles();
    final recovery = _SlowRecovery();
    await start(tester, files, recovery);
    for (var i = 0; i < 21; i++) {
      await draw(tester);
    }
    expect(recovery.captured, hasLength(1));
    expect(objects(recovery.captured.single), 1);
    await tap(tester, 'saveProject');
    expect(objects(files.projects[files.savePath]!), 21);
    expect(
      recovery.clears,
      0,
      reason: 'Clear must wait for the active disk write.',
    );
    recovery.firstWrite.complete();
    await tester.pumpAndSettle();
    expect(recovery.clears, 1);
    expect(recovery.bytes, isNull);
    expect(recovery.captured, hasLength(1));
    expect(
      find.textContaining('21 éléments · projet enregistré'),
      findsOneWidget,
    );
    await draw(tester);
    expect(recovery.captured, hasLength(2));
    expect(objects(recovery.bytes!), 22);
    expect(
      find.textContaining('22 éléments · modifications non enregistrées'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !available);

  testWidgets('a new page cannot be overwritten by a pending old recovery', (
    tester,
  ) async {
    final recovery = _SlowRecovery();
    await start(tester, MemoryFiles(), recovery);
    await draw(tester);
    await draw(tester);
    await tap(tester, 'newProject');
    await tap(tester, 'createNewSheet');
    await tap(tester, 'discardChanges');
    expect(recovery.clears, 0);
    recovery.firstWrite.complete();
    await tester.pumpAndSettle();
    expect(recovery.clears, 1);
    expect(recovery.bytes, isNull);
    expect(find.textContaining('0 élément · nouvelle feuille'), findsOneWidget);
    await draw(tester);
    expect(recovery.captured, hasLength(2));
    expect(objects(recovery.bytes!), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !available);

  testWidgets(
    'disposing the studio while recovery writes never captures a freed document',
    (tester) async {
      final recovery = _SlowRecovery();
      await start(tester, MemoryFiles(), recovery);
      await draw(tester);
      await draw(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      recovery.firstWrite.complete();
      await tester.pump(const Duration(seconds: 1));
      expect(recovery.captured, hasLength(1));
      expect(objects(recovery.bytes!), 1);
      expect(tester.takeException(), isNull);
    },
    skip: !available,
  );
}
