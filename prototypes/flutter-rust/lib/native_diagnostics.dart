// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _channel = MethodChannel('org.edupaint/diagnostics');
_NativeDiagnostics? _observer;
int _generation = 0;

/// Enables passive diagnostics only when launched with --edupaint-diagnostics.
/// Does not activate the window, schedule a frame, or change lifecycle state.
Future<void> installNativeDiagnostics() async {
  if (!Platform.isMacOS) return;
  final generation = ++_generation;
  try {
    final config = await _channel.invokeMapMethod<String, Object?>('configure');
    if (generation != _generation || config?['enabled'] != true) return;
    _observer?.dispose();
    final observer = _NativeDiagnostics();
    _observer = observer;
    WidgetsBinding.instance.addObserver(observer);
    WidgetsBinding.instance.addTimingsCallback(observer.onTimings);
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'snapshot') throw MissingPluginException();
      recordNativeDiagnostics('native:${call.arguments}');
    });
    recordNativeDiagnostics('dart-installed');
  } catch (_) {
    // Diagnostic availability cannot prevent drawing or project recovery.
  }
}

void recordNativeDiagnostics(String event) => _recordNativeDiagnostics(event);

/// Returns null when disabled: normal exports allocate no diagnostic clock.
/// An operation belongs to its observer and cannot leak into a later session.
NativeDiagnosticOperation? beginNativeDiagnosticOperation(String name) {
  final observer = _observer;
  if (observer == null) return null;
  return NativeDiagnosticOperation._(name, observer, ++observer.operationCount);
}

final class NativeDiagnosticOperation {
  NativeDiagnosticOperation._(this._name, this._owner, this._id);

  final String _name;
  final _NativeDiagnostics _owner;
  final int _id;
  final Stopwatch _clock = Stopwatch()..start();

  /// Only phase names and scalar state; never pass paths, image data or errors.
  void record(
    String phase, {
    required bool busy,
    required bool mounted,
    String? outcome,
  }) {
    if (!identical(_observer, _owner)) return;
    _recordNativeDiagnostics(
      '$_name:$phase',
      operation: <String, Object?>{
        'id': _id,
        'elapsedMicros': _clock.elapsedMicroseconds,
        'busy': busy,
        'mounted': mounted,
        'outcome': ?outcome,
      },
    );
  }
}

void _recordNativeDiagnostics(String event, {Map<String, Object?>? operation}) {
  final observer = _observer;
  if (observer == null) return;
  final binding = WidgetsBinding.instance;
  unawaited(
    _channel
        .invokeMethod<void>('record', <String, Object?>{
          'event': event,
          'sequence': ++observer.eventCount,
          'dartElapsedMicros': observer._logClock.elapsedMicroseconds,
          'operation': ?operation,
          'lifecycleState': binding.lifecycleState?.name,
          'framesEnabled': binding.framesEnabled,
          'hasScheduledFrame': binding.hasScheduledFrame,
          'schedulerPhase': binding.schedulerPhase.name,
          'semanticsEnabled': binding.semanticsEnabled,
          'platformSemanticsEnabled':
              binding.platformDispatcher.semanticsEnabled,
          'completedFrameCount': observer.completedFrames,
        })
        .catchError((Object _) {}),
  );
}

void clearNativeDiagnostics() {
  _generation++;
  _observer?.dispose();
  _observer = null;
  if (Platform.isMacOS) _channel.setMethodCallHandler(null);
}

class _NativeDiagnostics with WidgetsBindingObserver {
  int completedFrames = 0;
  int eventCount = 0;
  int operationCount = 0;
  final _logClock = Stopwatch()..start();
  int _lastFrameLogMilliseconds = -1000;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    recordNativeDiagnostics('lifecycle:${state.name}');
  }

  @override
  void didChangeMetrics() => recordNativeDiagnostics('metrics');

  void onTimings(List<FrameTiming> timings) {
    completedFrames += timings.length;
    final now = _logClock.elapsedMilliseconds;
    if (now - _lastFrameLogMilliseconds >= 1000) {
      _lastFrameLogMilliseconds = now;
      recordNativeDiagnostics('frame-timings');
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(onTimings);
  }
}
