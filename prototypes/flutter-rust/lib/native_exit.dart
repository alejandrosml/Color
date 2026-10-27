// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';

const _lifecycleChannel = MethodChannel('org.edupaint/lifecycle');
Future<AppExitResponse> Function()? _exitHandler;
int _handlerGeneration = 0;

/// Installs the single macOS decision handler, shared with Dart exit requests.
/// The native application delegate coalesces repeated Quit/close requests.
void installNativeExitHandler(Future<AppExitResponse> Function() handler) {
  if (!Platform.isMacOS) return;
  _exitHandler = handler;
  final generation = ++_handlerGeneration;
  _lifecycleChannel.setMethodCallHandler((call) async {
    if (call.method != 'requestExit') throw MissingPluginException();
    final current = _exitHandler;
    if (current == null) return <String, String>{'response': 'cancel'};
    try {
      final response = await current();
      // Disposal/replacement while waiting must never approve an obsolete view.
      final approved =
          generation == _handlerGeneration && response == AppExitResponse.exit;
      return <String, String>{'response': approved ? 'exit' : 'cancel'};
    } catch (_) {
      return <String, String>{'response': 'cancel'};
    }
  });
  _setNativeReady(true);
}

void clearNativeExitHandler() {
  if (!Platform.isMacOS) return;
  _exitHandler = null;
  _handlerGeneration++;
  _lifecycleChannel.setMethodCallHandler(null);
  _setNativeReady(false);
}

void _setNativeReady(bool ready) {
  // A test runner or an engine that is already shutting down may lack the
  // native channel. It must not turn registration/disposal into an exception.
  unawaited(
    _lifecycleChannel
        .invokeMethod<void>('setHandlerReady', ready)
        .catchError((Object _) {}),
  );
}
