// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:edupaint_flutter_study/recovery_scheduler.dart';

void main() {
  testWidgets('continuous edits are captured after the first delay', (
    tester,
  ) async {
    var revision = 0;
    final captured = <int>[];
    final scheduler = RecoveryScheduler(
      writeLatest: () async {
        captured.add(revision);
      },
      onError: (error, stack) => fail('$error\n$stack'),
    );
    addTearDown(scheduler.dispose);
    scheduler.request();
    for (var i = 1; i <= 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      revision = i;
      scheduler.request();
    }
    expect(captured, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(captured, [3]);
    await tester.pump(const Duration(seconds: 1));
    expect(captured, [3]);
  });

  testWidgets('slow storage retains only the latest requested revision', (
    tester,
  ) async {
    var revision = 0;
    var active = 0;
    var maxActive = 0;
    final captured = <int>[];
    final writes = <Completer<void>>[];
    final scheduler = RecoveryScheduler(
      writeLatest: () async {
        active++;
        if (active > maxActive) maxActive = active;
        captured.add(revision);
        final completion = Completer<void>();
        writes.add(completion);
        await completion.future;
        active--;
      },
      onError: (error, stack) => fail('$error\n$stack'),
    );
    addTearDown(scheduler.dispose);
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 400));
    expect(captured, [0]);
    for (var i = 1; i <= 1000; i++) {
      revision = i;
      scheduler.request();
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(captured, [0]);
    writes.first.complete();
    await tester.pump();
    expect(captured, [0, 1000]);
    expect(maxActive, 1);
    writes.last.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(captured, [0, 1000]);
    expect(active, 0);
  });

  testWidgets('an early write completion still respects the next delay', (
    tester,
  ) async {
    final first = Completer<void>();
    var count = 0;
    final scheduler = RecoveryScheduler(
      writeLatest: () {
        count++;
        return count == 1 ? first.future : Future.value();
      },
      onError: (error, stack) => fail('$error\n$stack'),
    );
    addTearDown(scheduler.dispose);
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 400));
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 100));
    first.complete();
    await tester.pump();
    expect(count, 1);
    await tester.pump(const Duration(milliseconds: 299));
    expect(count, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(count, 2);
  });

  testWidgets('clear waits for an active write and cancels old queued edits', (
    tester,
  ) async {
    final first = Completer<void>();
    final events = <String>[];
    var revision = 'old';
    final scheduler = RecoveryScheduler(
      writeLatest: () async {
        events.add('capture $revision');
        if (revision == 'old') await first.future;
        events.add('written');
      },
      onError: (error, stack) => fail('$error\n$stack'),
    );
    addTearDown(scheduler.dispose);
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 400));
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 400));
    final clear = scheduler.cancelAndWait().then((_) => events.add('clear'));
    await tester.pump();
    expect(events, ['capture old']);
    first.complete();
    await tester.pump();
    await clear;
    expect(events, ['capture old', 'written', 'clear']);
    revision = 'new';
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, [
      'capture old',
      'written',
      'clear',
      'capture new',
      'written',
    ]);
  });

  testWidgets('cancel before capture allocates no snapshot', (tester) async {
    var captures = 0;
    final scheduler = RecoveryScheduler(
      writeLatest: () async {
        captures++;
      },
      onError: (error, stack) => fail('$error\n$stack'),
    );
    addTearDown(scheduler.dispose);
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 399));
    await scheduler.cancelAndWait();
    await tester.pump(const Duration(seconds: 1));
    expect(captures, 0);
  });

  testWidgets('failed write reports its error and latest edits still recover', (
    tester,
  ) async {
    final failed = Completer<void>();
    final errors = <Object>[];
    var count = 0;
    final scheduler = RecoveryScheduler(
      writeLatest: () {
        count++;
        return count == 1 ? failed.future : Future.value();
      },
      onError: (error, stack) => errors.add(error),
    );
    addTearDown(scheduler.dispose);
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 400));
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 400));
    final error = StateError('Disk full');
    failed.completeError(error);
    await tester.pump();
    expect(errors, [error]);
    expect(count, 2);
    await scheduler.cancelAndWait();
  });

  testWidgets('synchronous capture failure does not poison future requests', (
    tester,
  ) async {
    final errors = <Object>[];
    var count = 0;
    final scheduler = RecoveryScheduler(
      writeLatest: () {
        count++;
        if (count == 1) throw StateError('Cannot export');
        return Future.value();
      },
      onError: (error, stack) => errors.add(error),
    );
    addTearDown(scheduler.dispose);
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 400));
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 400));
    expect(count, 2);
    expect(errors, hasLength(1));
  });

  testWidgets('dispose lets the active write finish without another capture', (
    tester,
  ) async {
    final first = Completer<void>();
    var captures = 0;
    final scheduler = RecoveryScheduler(
      writeLatest: () {
        captures++;
        return first.future;
      },
      onError: (error, stack) => fail('$error\n$stack'),
    );
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 400));
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 400));
    scheduler.dispose();
    scheduler.request();
    first.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(captures, 1);
  });

  test('the pause grows with the drawing, from 400 ms to 5 s', () {
    const kib = 1024, mib = 1024 * 1024;
    expect(recoveryDelayFor(0), const Duration(milliseconds: 400));
    expect(recoveryDelayFor(256 * kib), const Duration(milliseconds: 400));
    expect(recoveryDelayFor(256 * kib + 1).inMilliseconds, 400);
    expect(recoveryDelayFor(2 * mib + 128 * kib).inMilliseconds, 2700);
    expect(recoveryDelayFor(4 * mib), const Duration(seconds: 5));
    expect(recoveryDelayFor(68 * mib), const Duration(seconds: 5));
    var before = Duration.zero;
    for (var size = 0; size <= 5 * mib; size += 64 * kib) {
      final delay = recoveryDelayFor(size);
      expect(delay, greaterThanOrEqualTo(before), reason: '$size bytes');
      before = delay;
    }
  });

  testWidgets('the pause is asked for each time it starts', (tester) async {
    var delay = const Duration(seconds: 5);
    var writes = 0;
    final scheduler = RecoveryScheduler(
      writeLatest: () async => writes++,
      onError: (error, stack) => fail('$error\n$stack'),
      delayFor: () => delay,
    );
    addTearDown(scheduler.dispose);
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 4999));
    expect(writes, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(writes, 1);
    delay = const Duration(milliseconds: 400);
    scheduler.request();
    await tester.pump(const Duration(milliseconds: 400));
    expect(writes, 2);
  });

  testWidgets('a flush writes at once, after a write in progress', (
    tester,
  ) async {
    final events = <String>[];
    final first = Completer<void>();
    var revision = 1;
    final scheduler = RecoveryScheduler(
      writeLatest: () async {
        events.add('capture $revision');
        if (revision == 1) await first.future;
      },
      onError: (error, stack) => fail('$error\n$stack'),
      delayFor: () => const Duration(seconds: 5),
    );
    addTearDown(scheduler.dispose);
    // Nothing requested: nothing written.
    scheduler.flushNow();
    await tester.pump();
    expect(events, isEmpty);
    scheduler.request();
    scheduler.flushNow();
    await tester.pump();
    expect(events, ['capture 1']);
    // Requested while the first write lasts: written as soon as it ends,
    // not five seconds later.
    revision = 2;
    scheduler.request();
    scheduler.flushNow();
    await tester.pump();
    expect(events, ['capture 1']);
    first.complete();
    await tester.pump();
    expect(events, ['capture 1', 'capture 2']);
    await tester.pump(const Duration(seconds: 6));
    expect(events, ['capture 1', 'capture 2']);
  });
}
