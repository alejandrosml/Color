// SPDX-License-Identifier: MIT
// What Color asks of its runners to print, and how it reads their answers.
// The runner here is a mock of the channel: nothing is printed.

import 'package:edupaint_flutter_study/studio_files.dart';
import 'package:edupaint_flutter_study/studio_printer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.edupaint/print');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall call)? handler) {
    messenger.setMockMethodCallHandler(
      channel,
      handler == null
          ? null
          : (call) {
              calls.add(call);
              return handler(call);
            },
    );
  }

  setUp(calls.clear);
  tearDown(() => answer(null));

  // Two pixels by one: red, then blue.
  final image = Uint8List.fromList([255, 0, 0, 255, 0, 0, 255, 255]);
  Future<PrintOutcome> printIt() =>
      printWithSystemPanel(rgba: image, width: 2, height: 1, jobName: 'Zoé');

  test(
    'one call carries the pixels, their size and the name of the job',
    () async {
      answer((_) async => 'printed');
      expect(await printIt(), PrintOutcome.sent);
      final call = calls.single;
      expect(call.method, 'printImage');
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments.keys.toSet(), {'rgba', 'width', 'height', 'name'});
      expect(arguments['rgba'], image);
      expect(arguments['rgba'], isA<Uint8List>());
      expect(arguments['width'], 2);
      expect(arguments['height'], 1);
      expect(arguments['name'], 'Zoé');
    },
  );

  test('a panel that is closed without printing is no error', () async {
    answer((_) async => 'cancelled');
    expect(await printIt(), PrintOutcome.cancelled);
  });

  test('a system without a printer is told apart from a failure', () async {
    answer((_) async => throw PlatformException(code: noPrinterCode));
    expect(await printIt(), PrintOutcome.noPrinter);
    expect(noPrinterCode, 'NO_PRINTER');
  });

  test(
    'any other refusal of the system is thrown, with what it says',
    () async {
      answer(
        (_) async => throw PlatformException(
          code: 'PRINT_FAILED',
          message: 'Plus de papier.',
        ),
      );
      await expectLater(
        printIt(),
        throwsA(
          isA<PlatformException>()
              .having((error) => error.code, 'code', 'PRINT_FAILED')
              .having((error) => error.message, 'message', 'Plus de papier.'),
        ),
      );
    },
  );

  test('a runner that does not know the channel means: unavailable', () async {
    // No handler at all, as in a build without the native side.
    expect(await printIt(), PrintOutcome.unavailable);
    // A handler that does not know the method answers the same way.
    answer((_) async => throw MissingPluginException());
    expect(await printIt(), PrintOutcome.unavailable);
  });

  test(
    'an answer that is neither printed nor cancelled is a failure',
    () async {
      for (final Object? odd in ['done', null, 3]) {
        answer((_) async => odd);
        await expectLater(printIt(), throwsA(isA<PlatformException>()));
      }
    },
  );

  test('the pixels are the last entry of the message', () async {
    // Written last, 32 MiB of pixels make the message grow to their size
    // once, instead of being doubled by the entries written after them.
    answer((_) async => 'printed');
    await printIt();
    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments.keys.last, 'rgba');
  });

  test('the name of a job is the name of the drawing, on one line and of a decent length', () {
    expect(StudioFiles.printJobName(null), 'Mon dessin');
    expect(
      StudioFiles.printJobName('/dessins/Le chat de Zoé.edupaint'),
      'Le chat de Zoé',
    );
    expect(StudioFiles.printJobName(r'C:\Dessins\Été 🌞.EDUPAINT'), 'Été 🌞');
    // What only steers a display is not part of a name: line breaks, tabs,
    // marks that reverse the direction of the letters.
    expect(
      StudioFiles.printJobName('/dessins/deux\nlignes\tici.edupaint'),
      'deux lignes ici',
    );
    expect(
      StudioFiles.printJobName('/dessins/photo\u202egnp.exe.edupaint'),
      'photo gnp.exe',
    );
    expect(
      StudioFiles.printJobName('/dessins/ \u200f\u2066 .edupaint'),
      'Mon dessin',
    );
    // A print queue shows a short name: the first eighty characters, whole.
    final long = StudioFiles.printJobName('/dessins/${'é🌞' * 150}.edupaint');
    expect(long.runes, hasLength(80));
    expect(long, 'é🌞' * 40);
  });

  test('an image that does not have the announced size never leaves', () async {
    answer((_) async => 'printed');
    for (final (width, height) in [(2, 2), (0, 1), (1, 0), (-2, -1), (3, 1)]) {
      await expectLater(
        printWithSystemPanel(
          rgba: image,
          width: width,
          height: height,
          jobName: 'Zoé',
        ),
        throwsArgumentError,
        reason: '$width × $height',
      );
    }
    expect(calls, isEmpty);
  });
}
