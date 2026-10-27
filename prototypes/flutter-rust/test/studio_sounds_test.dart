// SPDX-License-Identifier: MIT
// The sounds: what the core provides, how they reach a player, and when the
// studio asks for them. Nothing here makes any noise: the core is asked for
// bytes only, and the players are in memory.
import 'dart:io';
import 'dart:typed_data';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_sounds.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_printer.dart';
import 'support/recording_sounds.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('the sounds of the studio are those of the core, in its order', () {
    final names = RustDocument.soundNames();
    expect(names, [for (final sound in StudioSound.values) sound.key]);
    for (final sound in StudioSound.values) {
      expect(sound.id, sound.index, reason: sound.name);
    }
  }, skip: !available);

  test('each sound is a small WAV file: mono, 16 bits, 44 100 Hz', () {
    for (final sound in StudioSound.values) {
      final wav = RustDocument.soundWav(sound.id)!;
      final data = ByteData.sublistView(wav);
      String tag(int at) => String.fromCharCodes(wav.sublist(at, at + 4));
      expect(tag(0), 'RIFF', reason: sound.key);
      expect(tag(8), 'WAVE', reason: sound.key);
      expect(tag(12), 'fmt ', reason: sound.key);
      expect(tag(36), 'data', reason: sound.key);
      expect(data.getUint32(4, Endian.little), wav.length - 8);
      expect(data.getUint16(20, Endian.little), 1, reason: 'PCM');
      expect(data.getUint16(22, Endian.little), 1, reason: 'one channel');
      expect(data.getUint32(24, Endian.little), 44100);
      expect(data.getUint16(34, Endian.little), 16);
      final bytes = data.getUint32(40, Endian.little);
      expect(bytes, wav.length - 44);
      // Between a few hundredths of a second and one second.
      expect(bytes ~/ 2, inInclusiveRange(441, 44100), reason: sound.key);
    }
    expect(RustDocument.soundWav(StudioSound.values.length), isNull);
    expect(RustDocument.soundWav(1 << 20), isNull);
  }, skip: !available);

  group('the player of the application', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('org.edupaint/sound');
    late List<MethodCall> calls;
    // What the runner answers to « play ».
    Object? Function(MethodCall call)? runner;

    setUp(() {
      calls = [];
      runner = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            final answer = runner;
            if (answer == null) throw MissingPluginException();
            return answer(call);
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('where the core plays, the runner is never asked', () async {
      final asked = <int>[];
      final sounds = SystemSounds(
        core: (id) {
          asked.add(id);
          return 0;
        },
      );
      sounds.play(StudioSound.tool);
      sounds.play(StudioSound.saved);
      await Future<void>.delayed(Duration.zero);
      expect(asked, [0, 10]);
      expect(calls, isEmpty);
    });

    test(
      'where it does not, the runner gets the bytes once, then the name',
      () async {
        runner = (call) => true;
        final asked = <int>[];
        final sounds = SystemSounds(
          core: (id) {
            asked.add(id);
            return 1;
          },
        );
        sounds.play(StudioSound.stamp);
        await Future<void>.delayed(Duration.zero);
        sounds.play(StudioSound.fill);
        await Future<void>.delayed(Duration.zero);
        sounds.play(StudioSound.stamp);
        await Future<void>.delayed(Duration.zero);
        // The core said once that it has no player here.
        expect(asked, [4]);
        expect(calls.map((call) => call.method), ['play', 'play', 'play']);
        Map<Object?, Object?> arguments(int index) =>
            calls[index].arguments as Map<Object?, Object?>;
        expect(arguments(0)['id'], 4);
        expect(arguments(0)['wav'], RustDocument.soundWav(4));
        expect(arguments(1)['id'], 5);
        expect(arguments(1)['wav'], RustDocument.soundWav(5));
        expect(arguments(2)['id'], 4);
        expect(arguments(2).containsKey('wav'), isFalse);
      },
      skip: !available,
    );

    test('a runner that forgot a sound is handed it again', () async {
      var known = false;
      runner = (call) {
        final has = (call.arguments as Map).containsKey('wav') || known;
        return has;
      };
      final sounds = SystemSounds(core: (_) => 1);
      sounds.play(StudioSound.undo);
      await Future<void>.delayed(Duration.zero);
      // The runner starts again and knows nothing any more.
      known = false;
      sounds.play(StudioSound.redo);
      await Future<void>.delayed(Duration.zero);
      sounds.play(StudioSound.undo);
      await Future<void>.delayed(Duration.zero);
      sounds.play(StudioSound.redo);
      await Future<void>.delayed(Duration.zero);
      sounds.play(StudioSound.undo);
      await Future<void>.delayed(Duration.zero);
      final withBytes = [
        for (final call in calls) (call.arguments as Map).containsKey('wav'),
      ];
      // First time with bytes; the name alone is refused; then bytes again.
      expect(withBytes, [true, true, false, false, true]);
    }, skip: !available);

    test(
      'without any player the studio stays silent, and stops asking',
      () async {
        var asked = 0;
        final sounds = SystemSounds(
          core: (_) {
            asked++;
            return 1;
          },
        );
        sounds.play(StudioSound.tool);
        await Future<void>.delayed(Duration.zero);
        sounds.play(StudioSound.colour);
        sounds.play(StudioSound.saved);
        await Future<void>.delayed(Duration.zero);
        expect(asked, 1);
        expect(calls, hasLength(1));
        // A core that fails is silence too, not an error of the studio.
        final broken = SystemSounds(core: (_) => throw StateError('absent'));
        expect(() => broken.play(StudioSound.tool), returnsNormally);
        expect(() => broken.play(StudioSound.tool), returnsNormally);
      },
      skip: !available,
    );

    test('the same sound asked again at once is one sound', () async {
      final asked = <int>[];
      final sounds = SystemSounds(
        core: (id) {
          asked.add(id);
          return 0;
        },
      );
      for (var glide = 0; glide < 10; glide++) {
        sounds.play(StudioSound.erase);
      }
      sounds.play(StudioSound.undo);
      sounds.play(StudioSound.erase);
      expect(asked, [6, 7, 6]);
      await Future<void>.delayed(
        SystemSounds.sameSoundGap + const Duration(milliseconds: 20),
      );
      sounds.play(StudioSound.erase);
      expect(asked, [6, 7, 6, 6]);
    });
  });

  testWidgets('each thing the child does has its sound', (tester) async {
    final sounds = RecordingSounds();
    final printer = FakePrinter();
    final studio = StudioDriver(tester, sounds: sounds, printer: printer.call);
    await studio.start(size: const Size(1280, 800));
    expect(sounds.take(), isEmpty);

    // Places are points of the sheet of 1200 by 800 units.
    await studio.drag(studio.at(150, 150), studio.at(350, 300));
    expect(sounds.take(), [StudioSound.stroke]);
    await studio.tap('color-d75e56');
    expect(sounds.take(), [StudioSound.colour]);
    await studio.tap('tool-rectangle');
    expect(sounds.take(), [StudioSound.tool]);
    await studio.drag(studio.at(450, 150), studio.at(650, 300));
    expect(sounds.take(), [StudioSound.shape]);
    // A shape in two clicks: a tick, then the shape.
    await studio.click(studio.at(800, 150));
    expect(sounds.take(), [StudioSound.click]);
    await studio.click(studio.at(950, 300));
    expect(sounds.take(), [StudioSound.shape]);
    await studio.tap('tool-stamp');
    await studio.click(studio.at(1000, 600));
    expect(sounds.take(), [StudioSound.tool, StudioSound.stamp]);
    await studio.addText('Bonjour', x: 150, y: 600);
    expect(sounds.take(), [StudioSound.tool, StudioSound.text]);
    await studio.tap('tool-fill');
    await studio.click(studio.at(550, 225));
    expect(sounds.take(), [StudioSound.tool, StudioSound.fill]);
    await studio.tap('tool-select');
    await studio.click(studio.at(1000, 600));
    expect(sounds.take(), [StudioSound.tool, StudioSound.select]);
    // The same element again: it is already chosen.
    await studio.click(studio.at(1000, 600));
    expect(sounds.take(), isEmpty);
    await studio.tap('tool-eraser');
    await studio.click(studio.at(1000, 600));
    expect(sounds.take(), [StudioSound.tool, StudioSound.erase]);
    await studio.tap('undo');
    expect(sounds.take(), [StudioSound.undo]);
    await studio.tap('redo');
    expect(sounds.take(), [StudioSound.redo]);
    await studio.tap('saveProject');
    expect(sounds.take(), [StudioSound.saved]);
    await printAndWait(tester, printer);
    await tester.pumpAndSettle();
    expect(sounds.take(), [StudioSound.printed]);
    // A notice: the pot on a stamp that keeps its own colours says so.
    await studio.tap('tool-stamp');
    await studio.tap('chooseStamp');
    await studio.tap('stamp-arcenciel');
    await studio.click(studio.at(600, 600));
    await studio.tap('tool-fill');
    sounds.take();
    await studio.click(studio.at(600, 600));
    expect(sounds.take(), [StudioSound.notice]);
    await studio.newSheet('square');
    expect(sounds.take(), contains(StudioSound.sheet));
    await studio.finish();
  }, skip: !available);

  testWidgets('the brush is heard when it touches the sheet and while it '
      'travels, never when it lifts', (tester) async {
    final sounds = RecordingSounds();
    final studio = StudioDriver(tester, sounds: sounds);
    await studio.start(size: const Size(1280, 800));
    final gesture = await tester.startGesture(
      studio.sheetCenter + studio.at(100, 400),
    );
    expect(sounds.take(), [StudioSound.stroke]);
    // A long trait, sampled every 100 ms of the pointer's own time.
    for (var step = 1; step <= 8; step++) {
      await gesture.moveTo(
        studio.sheetCenter + studio.at(100.0 + step * 100, 400),
        timeStamp: Duration(milliseconds: step * 100),
      );
    }
    // Heard again at 400 ms and at 800 ms: each time its sound nears its end.
    expect(sounds.take(), [StudioSound.stroke, StudioSound.stroke]);
    // A pointer that stays where it is plays nothing more, however long.
    for (var step = 9; step <= 14; step++) {
      await gesture.moveTo(
        studio.sheetCenter + studio.at(900, 400),
        timeStamp: Duration(milliseconds: step * 100),
      );
    }
    expect(sounds.take(), isEmpty);
    await gesture.up(timeStamp: const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(sounds.take(), isEmpty);
    studio.expectCount(1);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'the film has its two sounds, and Sons switched off none at all',
    (tester) async {
      final sounds = RecordingSounds();
      final store = StudioOptionsStore.memory();
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, sounds: sounds, options: store);
      await studio.start(size: const Size(1280, 800));
      await studio.drag(const Offset(-200, -100), const Offset(-120, -40));
      sounds.take();
      await studio.tap('replayDrawing');
      expect(find.byKey(const Key('replayDialog')), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(sounds.take(), [StudioSound.film, StudioSound.bravo]);
      await studio.tap('closeReplay');

      await store.change(store.value.copyWith(sounds: false));
      await tester.pumpAndSettle();
      await studio.drag(const Offset(0, 0), const Offset(80, 60));
      await studio.tap('tool-stamp');
      await studio.click(const Offset(200, 100));
      await studio.tap('undo');
      await studio.tap('replayDrawing');
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      await studio.tap('closeReplay');
      expect(sounds.take(), isEmpty);

      await store.change(store.value.copyWith(sounds: true));
      await tester.pumpAndSettle();
      await studio.tap('tool-stroke');
      expect(sounds.take(), [StudioSound.tool]);
      await studio.finish();
    },
    skip: !available,
  );
}
