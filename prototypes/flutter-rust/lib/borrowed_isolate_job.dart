// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:isolate';

/// A terminal value contains Dart data only, never a transferred native owner.
final class BorrowedJobValue<T> {
  const BorrowedJobValue(this.value);
  final T value;
}

final class BorrowedJobFailure {
  const BorrowedJobFailure(this.error, this.stack);
  final Object error;
  final StackTrace stack;
}

typedef BorrowedJobInvocation<T> = ({SendPort resultPort, T request});

/// Runs one borrower and returns only after its exit notification. The owner
/// keeps its native allocation alive around this entire Future, with no native
/// finalizer. The isolate handle is private and there is deliberately no timeout
/// or kill/cancel path. Abandonment means await completion, then free the owner.
/// If the owning isolate itself disappears, its native allocation may leak until
/// process exit; another isolate must never infer that it is safe to free it.
///
/// All terminal/error/exit events use one port. Success and caught failures are
/// sent with Isolate.exit, after the borrower's finally blocks have completed.
/// As in the installed SDK's Isolate.run, terminal data precedes the exit event
/// on this port. An exit without a terminal value is conservatively an error.
/// onError is *recorded*, never treated as permission to free before onExit.
/// The entry point is private cooperative code: it must not send null to forge
/// an exit notification, detach tasks, or start asynchronous native work. This
/// barrier does not drain system I/O that was already issued before a fatal error.
Future<O> runBorrowedIsolate<I, O>(
  void Function(BorrowedJobInvocation<I>) entry,
  I request, {
  String? debugName,
}) async {
  final port = ReceivePort();
  // Complete with a value even for failures: a very fast child can exit before
  // spawn's Future resolves, so no error Future is temporarily left unhandled.
  final done = Completer<({O? value, Object? error, StackTrace? stack})>();
  Object? terminal;
  Object? failure;
  StackTrace? failureStack;
  var terminalSeen = false;
  var exited = false;
  final subscription = port.listen((Object? event) {
    if (exited) return;
    if (event == null) {
      exited = true;
      if (failure != null) {
        done.complete((value: null, error: failure!, stack: failureStack));
      } else if (terminal is BorrowedJobValue<O>) {
        done.complete((
          value: (terminal as BorrowedJobValue<O>).value,
          error: null,
          stack: null,
        ));
      } else if (terminal is BorrowedJobFailure) {
        final value = terminal as BorrowedJobFailure;
        done.complete((value: null, error: value.error, stack: value.stack));
      } else {
        done.complete((
          value: null,
          error: StateError(
            'Le chargement s’est terminé sans résultat valide.',
          ),
          stack: StackTrace.empty,
        ));
      }
      return;
    }
    // Fatal asynchronous errors, including an unsendable Isolate.exit result.
    if (event is List &&
        event.length == 2 &&
        event[0] is String &&
        event[1] is String) {
      failure ??= RemoteError(event[0] as String, event[1] as String);
      failureStack ??= StackTrace.fromString(event[1] as String);
      return;
    }
    if (terminalSeen ||
        (event is! BorrowedJobValue<O> && event is! BorrowedJobFailure)) {
      failure ??= StateError('Réponse du chargement invalide ou répétée.');
      failureStack ??= StackTrace.empty;
      return;
    }
    terminalSeen = true;
    terminal = event;
  });
  try {
    // Install both listeners atomically at spawn, before any child execution.
    await Isolate.spawn<BorrowedJobInvocation<I>>(
      entry,
      (resultPort: port.sendPort, request: request),
      onError: port.sendPort,
      onExit: port.sendPort,
      errorsAreFatal: true,
      debugName: debugName,
    );
    final result = await done.future;
    if (result.error != null) {
      Error.throwWithStackTrace(
        result.error!,
        result.stack ?? StackTrace.empty,
      );
    }
    return result.value as O;
  } finally {
    // A failed spawn starts no borrower; all other paths await its exit above.
    await subscription.cancel();
    port.close();
  }
}
