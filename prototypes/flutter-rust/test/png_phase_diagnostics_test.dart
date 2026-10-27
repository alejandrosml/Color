// SPDX-License-Identifier: MIT
// Real Rust document and rasterizer. Only the chooser/writer and log sink are fake.
import 'dart:async';
import 'dart:io';

import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/native_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';

class _GatedFiles extends MemoryFiles {
  final chooser = Completer<String?>();
  final writer = Completer<void>();
  bool writerEntered = false;

  @override
  Future<String?> choosePng({String? currentPath}) => chooser.future;

  @override
  Future<void> writePng(String path, Uint8List bytes) async {
    writerEntered = true;
    await writer.future;
    await super.writePng(path, bytes);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.edupaint/diagnostics');
  final available =
      Platform.isMacOS && Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  final records = <Map<Object?, Object?>>[];
  List<Map<Object?, Object?>> getPhases() => records
      .where((r) => (r['event'] as String).startsWith('png-export:'))
      .toList();
  List<String> phaseNames() => getPhases()
      .map((r) => (r['event'] as String).substring('png-export:'.length))
      .toList();

  tearDown(() {
    clearNativeDiagnostics();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    records.clear();
  });

  Future<void> start(WidgetTester tester, _GatedFiles files) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'configure') return <String, Object>{'enabled': true};
      if (call.method == 'record') {
        records.add(call.arguments as Map<Object?, Object?>);
      }
      return null;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EduPaintApp(files: files, recoveryStorage: MemoryRecovery()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('exportImage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exportPng')));
    await tester.pumpAndSettle();
    expect(phaseNames(), ['started', 'busy-entered', 'choosePng-started']);
    expect(files.writerEntered, isFalse);
  }

  Future<void> waitForWriter(WidgetTester tester, _GatedFiles files) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 200 && !files.writerEntered; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(files.writerEntered, isTrue);
  }

  void expectIdleEnd() {
    final last = getPhases().last;
    expect(last['event'], 'png-export:finally-completed');
    final operation = last['operation'] as Map<Object?, Object?>;
    expect(operation['busy'], isFalse);
    expect(operation['mounted'], isTrue);
    expect(records.toString(), isNot(contains('/drawings/private-export.png')));
    expect(records.toString(), isNot(contains('private test error')));
  }

  testWidgets(
    'phase trace distinguishes pending chooser, renderer, writer and released busy',
    (tester) async {
      final files = _GatedFiles();
      await start(tester, files);
      files.chooser.complete('/drawings/private-export.png');
      await tester.pump();
      await waitForWriter(tester, files);
      expect(phaseNames(), [
        'started',
        'busy-entered',
        'choosePng-started',
        'choosePng-returned',
        'renderer-started',
        'snapshotStarted',
        'snapshotCompleted',
        'paintStarted',
        'paintCompleted',
        'toImageStarted',
        'toImageReturned',
        'toByteDataStarted',
        'toByteDataReturned',
        'bytesCopied',
        'cleanupStarted',
        'cleanupCompleted',
        'renderer-returned',
        'writer-started',
      ]);
      final pending = getPhases();
      final operationIds = pending
          .map((r) => (r['operation'] as Map)['id'])
          .toSet();
      expect(operationIds.length, 1);
      for (final phase in pending.skip(1)) {
        expect((phase['operation'] as Map)['busy'], isTrue);
        expect(phase.containsKey('lifecycleState'), isTrue);
        expect(phase.containsKey('framesEnabled'), isTrue);
        expect(phase.containsKey('completedFrameCount'), isTrue);
      }
      files.writer.complete();
      await tester.pumpAndSettle();
      expect(phaseNames().skip(pending.length), [
        'writer-returned',
        'status-applied',
        'finally-entered',
        'finally-completed',
      ]);
      expect(files.png, isNotNull);
      expectIdleEnd();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'cancelled chooser releases busy without allocating or writing PNG',
    (tester) async {
      final files = _GatedFiles();
      await start(tester, files);
      files.chooser.complete(null);
      await tester.pumpAndSettle();
      expect(phaseNames().skip(3), [
        'choosePng-returned',
        'finally-entered',
        'finally-completed',
      ]);
      expect((getPhases()[3]['operation'] as Map)['outcome'], 'cancelled');
      expect(files.writerEntered, isFalse);
      expectIdleEnd();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'chooser error is distinguishable without logging its private message',
    (tester) async {
      final files = _GatedFiles();
      await start(tester, files);
      files.chooser.completeError(
        const FileSystemException('private test error'),
      );
      await tester.pumpAndSettle();
      expect(phaseNames().skip(3), [
        'failed',
        'finally-entered',
        'finally-completed',
      ]);
      expect(files.writerEntered, isFalse);
      expectIdleEnd();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets('writer error is distinguishable and still releases busy', (
    tester,
  ) async {
    final files = _GatedFiles();
    await start(tester, files);
    files.chooser.complete('/drawings/private-export.png');
    await tester.pump();
    await waitForWriter(tester, files);
    files.writer.completeError(const FileSystemException('private test error'));
    await tester.pumpAndSettle();
    expect(phaseNames().skipWhile((p) => p != 'writer-started'), [
      'writer-started',
      'failed',
      'finally-entered',
      'finally-completed',
    ]);
    expect(files.png, isNull);
    expectIdleEnd();
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !available);
}
