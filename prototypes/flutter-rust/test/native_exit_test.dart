// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:edupaint_flutter_study/native_exit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.edupaint/lifecycle');
  const codec = StandardMethodCodec();
  final readiness = <bool>[];

  Future<Object?> requestExit() {
    final result = Completer<Object?>();
    binding.channelBuffers.push(
      channel.name,
      codec.encodeMethodCall(const MethodCall('requestExit')),
      (ByteData? data) {
        if (data == null) {
          result.complete(null);
        } else {
          result.complete(codec.decodeEnvelope(data));
        }
      },
    );
    return result.future;
  }

  setUp(() {
    readiness.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'setHandlerReady');
      readiness.add(call.arguments as bool);
      return null;
    });
  });
  tearDown(() async {
    clearNativeExitHandler();
    await Future<void>.value();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('native exit reports readiness and the completed decision', () async {
    installNativeExitHandler(() async => AppExitResponse.cancel);
    expect(await requestExit(), {'response': 'cancel'});
    installNativeExitHandler(() async => AppExitResponse.exit);
    expect(await requestExit(), {'response': 'exit'});
    clearNativeExitHandler();
    await Future<void>.value();
    expect(readiness, [true, true, false]);
  }, skip: !Platform.isMacOS);

  test('native exit cancels when the decision throws', () async {
    installNativeExitHandler(
      () async => throw StateError('simulated save failure'),
    );
    expect(await requestExit(), {'response': 'cancel'});
  }, skip: !Platform.isMacOS);

  test('disposal cannot approve an outstanding native exit', () async {
    final decision = Completer<AppExitResponse>();
    installNativeExitHandler(() => decision.future);
    final reply = requestExit();
    await Future<void>.value();
    clearNativeExitHandler();
    decision.complete(AppExitResponse.exit);
    expect(await reply, {'response': 'cancel'});
  }, skip: !Platform.isMacOS);

  test(
    'reinstalling the same callback invalidates its older decision',
    () async {
      final decision = Completer<AppExitResponse>();
      Future<AppExitResponse> handler() => decision.future;
      installNativeExitHandler(handler);
      final reply = requestExit();
      await Future<void>.value();
      clearNativeExitHandler();
      installNativeExitHandler(handler);
      decision.complete(AppExitResponse.exit);
      expect(await reply, {'response': 'cancel'});
    },
    skip: !Platform.isMacOS,
  );
}
