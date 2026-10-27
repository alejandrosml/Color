// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:edupaint_flutter_study/recovery_location.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the defaults are Color as it was, with its sounds', () {
    const options = StudioOptions();
    expect(options, StudioOptions.defaults);
    expect(options.level, InterfaceLevel.full);
    expect(options.printing, isTrue);
    expect(options.sounds, isTrue);
    expect(options.holdFree, isFalse);
    expect(options.screenKeyboard, isFalse);
    expect(options.tools, StudioTool.values);
    expect(options.opensFiles, isTrue);
    expect(options.exports, isTrue);
    expect(options.layers, isTrue);
    expect(options.viewControls, isTrue);
    expect(options.headerHelp, isTrue);
    expect(options.inspector, isTrue);
    expect(options.toolHelp, isTrue);
    expect(options.captions, isTrue);
    expect(options.statusLine, isTrue);
    expect(options.simpleControls, isFalse);
  });

  test('each level shows what its sentence promises', () {
    const toddler = StudioOptions(level: InterfaceLevel.toddler);
    expect(toddler.tools, [
      StudioTool.brush,
      StudioTool.stamp,
      StudioTool.fill,
      StudioTool.eraser,
    ]);
    expect(toddler.opensFiles, isFalse);
    expect(toddler.exports, isFalse);
    expect(toddler.layers, isFalse);
    expect(toddler.viewControls, isFalse);
    expect(toddler.headerHelp, isFalse);
    expect(toddler.inspector, isFalse);
    expect(toddler.toolHelp, isFalse);
    expect(toddler.captions, isFalse);
    expect(toddler.statusLine, isFalse);
    expect(toddler.simpleControls, isTrue);

    const child = StudioOptions(level: InterfaceLevel.child);
    expect(child.tools, StudioTool.values);
    expect(child.opensFiles, isTrue);
    expect(child.exports, isFalse);
    expect(child.layers, isFalse);
    expect(child.viewControls, isTrue);
    expect(child.headerHelp, isTrue);
    expect(child.inspector, isTrue);
    expect(child.toolHelp, isTrue);
    expect(child.captions, isTrue);
    expect(child.statusLine, isFalse);
    expect(child.simpleControls, isFalse);

    // The names written in the file never change; the labels are French.
    expect(InterfaceLevel.values.map((level) => level.code), [
      'tout-petits',
      'enfants',
      'complete',
    ]);
    for (final level in InterfaceLevel.values) {
      expect(level.label, isNotEmpty);
      expect(level.description, endsWith('.'));
    }
  });

  test('a change makes other options and leaves the first ones', () {
    const before = StudioOptions();
    final after = before.copyWith(
      level: InterfaceLevel.toddler,
      printing: false,
    );
    expect(before, StudioOptions.defaults);
    expect(after.level, InterfaceLevel.toddler);
    expect(after.printing, isFalse);
    expect(after.sounds, isTrue);
    expect(after, isNot(before));
    expect(
      after,
      before.copyWith(level: InterfaceLevel.toddler, printing: false),
    );
    expect(after.hashCode, after.copyWith().hashCode);
    for (final changed in [
      before.copyWith(sounds: false),
      before.copyWith(holdFree: true),
      before.copyWith(screenKeyboard: true),
      before.copyWith(level: InterfaceLevel.child),
    ]) {
      expect(changed, isNot(before));
      expect(StudioOptions.fromJson(changed.toJson()), changed);
    }
  });

  test('a file that says nothing readable keeps the defaults', () {
    for (final decoded in <Object?>[
      null,
      'bonjour',
      42,
      <Object?>[],
      <String, Object?>{},
      {'level': 'geant', 'printing': 'oui', 'sounds': 1, 'holdFree': null},
      {'version': 99, 'couleur': 'bleu'},
    ]) {
      expect(StudioOptions.fromJson(decoded), StudioOptions.defaults);
    }
    // A file written before the calculation became an option says nothing
    // of it: the options open without a calculation.
    expect(
      StudioOptions.fromJson({'version': 1, 'level': 'complete'}).guarded,
      isFalse,
    );
    // What is readable is kept, beside what is not.
    expect(
      StudioOptions.fromJson({
        'level': 'tout-petits',
        'printing': false,
        'sounds': 'non',
        'screenKeyboard': true,
        'plus tard': [1, 2, 3],
      }),
      const StudioOptions(
        level: InterfaceLevel.toddler,
        printing: false,
        screenKeyboard: true,
      ),
    );
  });

  test('the file lies beside the folders of Color on every system', () {
    expect(
      optionsFilePath('/home/a/.local/share/color', windows: false),
      '/home/a/.local/share/color/options.json',
    );
    // On Windows the name of the product changed; the folder did not.
    expect(
      optionsFilePath(
        r'C:\Users\a\AppData\Roaming\com.example\Color',
        windows: true,
      ),
      r'C:\Users\a\AppData\Roaming\com.example\edupaint_flutter_study\options.json',
    );
    // Only the last folder is the name of the product: a path of one
    // folder keeps its drive.
    expect(
      optionsFilePath(r'C:\x\Color', windows: true),
      r'C:\x\edupaint_flutter_study\options.json',
    );
  });

  group('on disk', () {
    late Directory folder;
    setUp(() => folder = Directory.systemTemp.createTempSync('color-options-'));
    tearDown(() => folder.deleteSync(recursive: true));

    test('options are written whole and read back', () async {
      // The folder of Color may not exist yet at the first launch.
      final file = File('${folder.path}/pas/encore/options.json');
      final storage = OptionsStorage(file: file);
      expect(await storage.read(), StudioOptions.defaults);
      const chosen = StudioOptions(
        level: InterfaceLevel.child,
        printing: false,
        sounds: false,
        holdFree: true,
        screenKeyboard: true,
        guarded: true,
      );
      await storage.write(chosen);
      expect(await storage.read(), chosen);
      expect(jsonDecode(file.readAsStringSync()), {
        'version': 1,
        'level': 'enfants',
        'printing': false,
        'sounds': false,
        'holdFree': true,
        'screenKeyboard': true,
        'guarded': true,
      });
      // Nothing is left beside the file. By their names: Windows lists a
      // folder with its own separator.
      expect(
        file.parent.listSync().map((entry) => entry.uri.pathSegments.last),
        ['options.json'],
      );
      await storage.write(StudioOptions.defaults);
      expect(await storage.read(), StudioOptions.defaults);
    });

    test(
      'a damaged or foreign file is the defaults, and is replaced',
      () async {
        final file = File('${folder.path}/options.json');
        final storage = OptionsStorage(file: file);
        for (final content in ['', '{', 'pas du JSON', '[1, 2]', '"texte"']) {
          file.writeAsStringSync(content);
          expect(await storage.read(), StudioOptions.defaults, reason: content);
        }
        file.writeAsBytesSync([0xff, 0xfe, 0x00, 0x80]);
        expect(await storage.read(), StudioOptions.defaults);
        file.writeAsStringSync(
          '{"level":"tout-petits"}${' ' * OptionsStorage.maxBytes}',
        );
        expect(await storage.read(), StudioOptions.defaults);
        await storage.write(const StudioOptions(level: InterfaceLevel.toddler));
        expect((await storage.read()).level, InterfaceLevel.toddler);
      },
    );

    test(
      'what is not an ordinary file is the defaults, without waiting',
      () async {
        // A folder at the place of the file.
        final taken = Directory('${folder.path}/options.json')..createSync();
        expect(
          await OptionsStorage(file: File(taken.path)).read(),
          StudioOptions.defaults,
        );
        // A pipe that nobody writes to: reading it would never end, and
        // the studio waits for its options before its first frame.
        final pipe = '${folder.path}/tube.json';
        final made = Process.runSync('mkfifo', [pipe]);
        if (made.exitCode != 0) {
          markTestSkipped('mkfifo is not available here.');
          return;
        }
        final watch = Stopwatch()..start();
        expect(
          await OptionsStorage(file: File(pipe)).read(),
          StudioOptions.defaults,
        );
        expect(watch.elapsed, lessThan(OptionsStorage.readTimeout));
        expect(
          FileSystemEntity.typeSync(pipe, followLinks: false),
          FileSystemEntityType.pipe,
        );
      },
      skip: Platform.isWindows ? 'No named pipe in a folder on Windows.' : null,
    );

    test('the store applies a change at once and keeps it', () async {
      final storage = OptionsStorage(file: File('${folder.path}/options.json'));
      final store = StudioOptionsStore(await storage.read(), storage: storage);
      addTearDown(store.dispose);
      var heard = 0;
      store.addListener(() => heard++);
      final first = store.change(
        store.value.copyWith(level: InterfaceLevel.toddler),
      );
      // Applied before the file is written.
      expect(store.value.level, InterfaceLevel.toddler);
      expect(heard, 1);
      final second = store.change(store.value.copyWith(sounds: false));
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(store.unsaved, isFalse);
      expect(
        await storage.read(),
        const StudioOptions(level: InterfaceLevel.toddler, sounds: false),
      );
      // The same options again: nothing to say, nothing to write.
      expect(await store.change(store.value), isTrue);
      expect(heard, 2);
    });

    test('a change that cannot be kept still applies, and says so', () async {
      // A folder where the file should be: nothing can be written there.
      final blocked = Directory('${folder.path}/options.json')..createSync();
      final store = StudioOptionsStore(
        StudioOptions.defaults,
        storage: OptionsStorage(file: File(blocked.path)),
      );
      addTearDown(store.dispose);
      var heard = 0;
      store.addListener(() => heard++);
      expect(
        await store.change(store.value.copyWith(printing: false)),
        isFalse,
      );
      expect(store.value.printing, isFalse);
      expect(store.unsaved, isTrue);
      // Once for the change, once for the news that it was not kept.
      expect(heard, 2);
      // The folder gives way: the next change is kept, and says so too.
      blocked.deleteSync();
      expect(await store.change(store.value.copyWith(sounds: false)), isTrue);
      expect(store.unsaved, isFalse);
      expect(heard, 4);
    });
  });

  test('a store without a file lasts as long as the studio', () async {
    final store = StudioOptionsStore.memory();
    addTearDown(store.dispose);
    expect(store.value, StudioOptions.defaults);
    expect(store.unsaved, isFalse);
    expect(await store.change(store.value.copyWith(holdFree: true)), isFalse);
    expect(store.value.holdFree, isTrue);
    expect(store.unsaved, isTrue);
  });
}
