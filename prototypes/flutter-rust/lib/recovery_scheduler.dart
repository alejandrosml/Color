// SPDX-License-Identifier: MIT
import 'dart:async';

/// The pause before a recovery copy, by the size of the project in bytes:
/// 400 ms up to 256 KiB, then longer in proportion, up to 5 s from 4 MiB.
/// Each copy writes the whole project, a photo behind the drawing included:
/// a large one written every 400 ms meant up to 68 MiB at each pause, 2.5 GB
/// over a session of 2 000 traits (estimated in the retrospective of
/// October 2026, R-02). Here a large drawing is written 5 to 12 times less
/// often; a small one, the most common, as often as before.
Duration recoveryDelayFor(int projectBytes) {
  const small = 256 * 1024, large = 4 * 1024 * 1024;
  const shortest = 400, longest = 5000;
  if (projectBytes <= small) return const Duration(milliseconds: shortest);
  if (projectBytes >= large) return const Duration(milliseconds: longest);
  final share = (projectBytes - small) / (large - small);
  return Duration(
    milliseconds: (shortest + share * (longest - shortest)).round(),
  );
}

/// Coalesces edits without retaining an encoded snapshot per request.
///
/// [writeLatest] captures the document only when invoked. At most one invocation
/// is active; edits made while it runs are represented by two booleans, not by
/// copies of the document. The first edit starts the delay, so continuous drawing
/// does not keep postponing recovery. This schedules I/O; it does not move
/// synchronous serialization off the UI isolate.
///
/// [delayFor], when given, says how long that delay is, each time it starts:
/// see [recoveryDelayFor]. Otherwise it is [delay].
class RecoveryScheduler {
  RecoveryScheduler({
    required this.writeLatest,
    required this.onError,
    this.delay = const Duration(milliseconds: 400),
    this.delayFor,
  });

  final Future<void> Function() writeLatest;
  final void Function(Object error, StackTrace stack) onError;
  final Duration delay;
  final Duration Function()? delayFor;
  Timer? _timer;
  Future<void>? _active;
  bool _requested = false;
  bool _due = false;
  bool _disposed = false;

  void request() {
    if (_disposed) return;
    _requested = true;
    if (_due) return;
    _timer ??= Timer(delayFor?.call() ?? delay, () {
      _timer = null;
      _due = true;
      _startIfReady();
    });
  }

  /// Writes what was requested now, without waiting for the delay: Color is
  /// going out of sight, and the system may end it before a timer fires. A
  /// write in progress finishes first; this one starts right after it.
  /// Nothing requested, nothing written.
  void flushNow() {
    if (_disposed || !_requested) return;
    _timer?.cancel();
    _timer = null;
    _due = true;
    _startIfReady();
  }

  void _startIfReady() {
    if (_disposed || _active != null || !_requested || !_due) return;
    _requested = false;
    _due = false;
    _active = _write();
  }

  Future<void> _write() async {
    try {
      // Future.sync also contains an error thrown before the first await.
      await Future<void>.sync(writeLatest);
    } catch (error, stack) {
      onError(error, stack);
    } finally {
      _active = null;
      _startIfReady();
    }
  }

  /// Cancels requests that have not captured a snapshot and waits for a write
  /// already in progress. Callers must stop edits until their subsequent clear
  /// or document replacement finishes. A write that has started is not aborted.
  Future<void> cancelAndWait() {
    _cancelPending();
    return _active ?? Future<void>.value();
  }

  void _cancelPending() {
    _timer?.cancel();
    _timer = null;
    _requested = false;
    _due = false;
  }

  void dispose() {
    _disposed = true;
    _cancelPending();
  }
}
