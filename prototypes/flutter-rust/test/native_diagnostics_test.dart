// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edupaint_flutter_study/native_diagnostics.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.edupaint/diagnostics');
  final calls = <MethodCall>[];

  tearDown(() {
    clearNativeDiagnostics();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    calls.clear();
  });

  test('disabled diagnostics do not record or request a frame', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return <String, Object>{'enabled': false};
    });
    final scheduled = binding.hasScheduledFrame;
    await installNativeDiagnostics();
    recordNativeDiagnostics('disabled-action');
    expect(beginNativeDiagnosticOperation('png-export'), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((call) => call.method), ['configure']);
    expect(binding.hasScheduledFrame, scheduled);
  }, skip: !Platform.isMacOS);

  test('missing diagnostic plugin never prevents startup', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      throw MissingPluginException();
    });
    await installNativeDiagnostics();
    recordNativeDiagnostics('unavailable-action');
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((call) => call.method), ['configure']);
  }, skip: !Platform.isMacOS);

  test(
    'enabled observations report state without scheduling a frame',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'configure') {
          return <String, Object>{'enabled': true};
        }
        return null;
      });
      final scheduled = binding.hasScheduledFrame;
      await installNativeDiagnostics();
      recordNativeDiagnostics('test-action');
      await Future<void>.delayed(Duration.zero);
      final record = calls.last.arguments as Map<Object?, Object?>;
      expect(calls.last.method, 'record');
      expect(record['event'], 'test-action');
      expect(record['framesEnabled'], binding.framesEnabled);
      expect(record['hasScheduledFrame'], scheduled);
      expect(record['schedulerPhase'], binding.schedulerPhase.name);
      expect(binding.hasScheduledFrame, scheduled);
      clearNativeDiagnostics();
      final count = calls.length;
      recordNativeDiagnostics('disposed');
      await Future<void>.delayed(Duration.zero);
      expect(calls.length, count);
    },
    skip: !Platform.isMacOS,
  );

  test(
    'operations retain monotonic ordering and cannot cross sessions',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return call.method == 'configure'
            ? <String, Object>{'enabled': true}
            : null;
      });
      await installNativeDiagnostics();
      final first = beginNativeDiagnosticOperation('png-export')!;
      first.record('started', busy: false, mounted: true);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      first.record('writer-started', busy: true, mounted: true);
      final second = beginNativeDiagnosticOperation('png-export')!;
      second.record('started', busy: false, mounted: true);
      await Future<void>.delayed(Duration.zero);
      final records = calls
          .where((c) => c.method == 'record')
          .map((c) => c.arguments as Map<Object?, Object?>)
          .toList();
      for (var i = 1; i < records.length; i++) {
        expect(
          records[i]['sequence'] as int,
          greaterThan(records[i - 1]['sequence'] as int),
        );
        expect(
          records[i]['dartElapsedMicros'] as int,
          greaterThanOrEqualTo(records[i - 1]['dartElapsedMicros'] as int),
        );
      }
      final phases = records.where((r) => r['operation'] != null).toList();
      final firstStart = phases[0]['operation'] as Map<Object?, Object?>;
      final firstWrite = phases[1]['operation'] as Map<Object?, Object?>;
      final secondStart = phases[2]['operation'] as Map<Object?, Object?>;
      expect(firstWrite['id'], firstStart['id']);
      expect(
        firstWrite['elapsedMicros'] as int,
        greaterThan(firstStart['elapsedMicros'] as int),
      );
      expect(secondStart['id'], isNot(firstStart['id']));
      clearNativeDiagnostics();
      await installNativeDiagnostics();
      await Future<void>.delayed(Duration.zero);
      final count = calls.length;
      first.record('late-result', busy: false, mounted: false);
      second.record('late-result', busy: false, mounted: false);
      await Future<void>.delayed(Duration.zero);
      expect(calls.length, count);
    },
    skip: !Platform.isMacOS,
  );

  test(
    'a failed diagnostic write cannot block later operation phases',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'configure') {
          return <String, Object>{'enabled': true};
        }
        throw PlatformException(code: 'diagnostic-unavailable');
      });
      await installNativeDiagnostics();
      final operation = beginNativeDiagnosticOperation('png-export')!;
      final scheduled = binding.hasScheduledFrame;
      operation.record('writer-started', busy: true, mounted: true);
      operation.record('finally-completed', busy: false, mounted: true);
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.method, 'record');
      expect(
        (calls.last.arguments as Map)['event'],
        'png-export:finally-completed',
      );
      expect(binding.hasScheduledFrame, scheduled);
    },
    skip: !Platform.isMacOS,
  );

  test('hidden-state observations never request or force a frame', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'configure'
          ? <String, Object>{'enabled': true}
          : null;
    });
    await installNativeDiagnostics();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    final scheduled = binding.hasScheduledFrame;
    final operation = beginNativeDiagnosticOperation('png-export')!;
    try {
      operation.record('finally-completed', busy: false, mounted: true);
      await Future<void>.delayed(Duration.zero);
      final record = calls.last.arguments as Map<Object?, Object?>;
      expect(record['lifecycleState'], 'hidden');
      expect(record['framesEnabled'], isFalse);
      expect(record['hasScheduledFrame'], scheduled);
      expect((record['operation'] as Map)['busy'], isFalse);
      expect(binding.hasScheduledFrame, scheduled);
      expect(binding.framesEnabled, isFalse);
    } finally {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  }, skip: !Platform.isMacOS);
}
