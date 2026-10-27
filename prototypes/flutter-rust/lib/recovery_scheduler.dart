// SPDX-License-Identifier: MIT
import 'dart:async';

/// Coalesces edits without retaining an encoded snapshot per request.
///
/// [writeLatest] captures the document only when invoked. At most one invocation
/// is active; edits made while it runs are represented by two booleans, not by
/// copies of the document. The first edit starts the delay, so continuous drawing
/// does not keep postponing recovery. This schedules I/O; it does not move
/// synchronous serialization off the UI isolate.
class RecoveryScheduler {
  RecoveryScheduler({
    required this.writeLatest,
    required this.onError,
    this.delay = const Duration(milliseconds: 400),
  });

  final Future<void> Function() writeLatest;
  final void Function(Object error, StackTrace stack) onError;
  final Duration delay;
  Timer? _timer;
  Future<void>? _active;
  bool _requested = false;
  bool _due = false;
  bool _disposed = false;

  void request() {
    if (_disposed) return;
    _requested = true;
    if (_due) return;
    _timer ??= Timer(delay, () {
      _timer = null;
      _due = true;
      _startIfReady();
    });
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
