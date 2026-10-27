// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';

import 'package:edupaint_flutter_study/native_project_writer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = 'org.edupaint/files';
  const codec = StandardMethodCodec();

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMessageHandler(channel, null);
  });

  // Exercise both the initial codec buffer and its growth path, with a sliced
  // caller buffer so offset/length preservation is covered too.
  for (final length in [32, 128 * 1024]) {
    test(
      'Mac writer captures $length bytes before caller mutation and native reply',
      () async {
        final owner = Uint8List.fromList(
          List.generate(length + 9, (index) => (index * 37) & 255),
        );
        final input = Uint8List.sublistView(owner, 3, 3 + length);
        final expected = Uint8List.fromList(input);
        final releaseNativeRead = Completer<void>();
        ByteData? sent;
        MethodCall? decoded;
        binding.defaultBinaryMessenger.setMockMessageHandler(channel, (
          message,
        ) async {
          // Intercept RAW encoded bytes, not a mock MethodCall decoded early.
          // Delay decoding until after the caller has changed the original.
          sent = message;
          await releaseNativeRead.future;
          decoded = codec.decodeMethodCall(message);
          return codec.encodeSuccessEnvelope(null);
        });
        final pending = writeNativeProject('/virtual/Mon dessin.color', input);
        try {
          // No await between invocation and this mutation: a deferred encoder
          // retaining the caller's bytes would save the wrong document.
          owner.fillRange(0, owner.length, 0xee);
          expect(sent, isNotNull);
          expect(decoded, isNull);
          releaseNativeRead.complete();
          await pending;
          expect(decoded!.method, 'writeAtomic');
          final arguments = decoded!.arguments as Map<Object?, Object?>;
          expect(arguments['path'], '/virtual/Mon dessin.color');
          expect(arguments['bytes'], isA<Uint8List>());
          expect(arguments['bytes'], orderedEquals(expected));
          expect(input, everyElement(0xee));
        } finally {
          if (!releaseNativeRead.isCompleted) {
            releaseNativeRead.complete();
          }
          await pending;
        }
      },
      skip: !Platform.isMacOS,
    );
  }
}
