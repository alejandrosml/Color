// SPDX-License-Identifier: MIT
// « Mes dessins » on a real disk: its own folder, its bounds, and the files
// it never touches. Project and picture bytes are opaque to the album.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:edupaint_flutter_study/gallery_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory album;
  late GalleryStorage storage;

  // The cards of these tests are dated in October 2026; the album reads
  // them a month later. (A date from the future counts as now: see the test
  // of the clock.)
  DateTime later() => DateTime.utc(2026, 11, 1);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('color-gallery-test-');
    album = Directory('${root.path}/support/gallery');
    storage = GalleryStorage(now: later, directory: album);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Uint8List bytes(int length, [int seed = 1]) => Uint8List.fromList(
    List.generate(length, (index) => (index * 31 + seed) & 0xff),
  );

  DateTime day(int number, [int hour = 10]) =>
      DateTime.utc(2026, 10, number, hour);

  Future<void> remember(
    GalleryStorage album,
    String path, {
    Uint8List? project,
    Uint8List? thumbnail,
    DateTime? at,
    int count = 3,
    String? name,
  }) => album.remember(
    sourcePath: path,
    name: name ?? path.split('/').last,
    project: project ?? bytes(100),
    thumbnailPng: thumbnail ?? bytes(40, 7),
    width: 1200,
    height: 800,
    elementCount: count,
    savedAt: at,
  );

  // Every file below the test's root, relative to it, written with slashes
  // on every system.
  Future<List<String>> tree() async {
    final names = <String>[];
    await for (final item in root.list(recursive: true, followLinks: false)) {
      if (item is Directory) continue;
      names.add(
        item.path.substring(root.path.length + 1).replaceAll(r'\', '/'),
      );
    }
    return names..sort();
  }

  // Whether the volume of the test takes two names that differ only by
  // their case for one file, as the volumes of macOS and Windows usually do.
  // There, a name in capitals is no stranger beside its lower-case twin: it
  // is the same file.
  bool volumeIgnoresCase() {
    final probe = File('${album.path}/case-probe')..createSync(recursive: true);
    try {
      return File('${album.path}/CASE-PROBE').existsSync();
    } finally {
      probe.deleteSync();
    }
  }

  String id(String path) => GalleryStorage.idFor(path);
  String cardOf(String path) => 'support/gallery/${id(path)}.card';

  void write(String name, Object content) {
    final file = File('${album.path}/$name')..createSync(recursive: true);
    if (content is String) {
      file.writeAsStringSync(content);
    } else {
      file.writeAsBytesSync(content as List<int>);
    }
  }

  // A card made by hand: the format of the file is the contract.
  Uint8List card(
    String path, {
    int format = 1,
    String magic = 'COLORCRD',
    Object? name = 'dessin.edupaint',
    Object? savedAt = 1790000000000,
    Object? width = 1200,
    Object? height = 800,
    Object? count = 2,
    List<int>? description,
    int? announcedDescription,
    List<int>? thumbnail,
    int? announcedThumbnail,
    List<int> copy = const [],
    int? announcedCopy,
  }) {
    final words =
        description ??
        utf8.encode(
          jsonEncode({
            'name': name,
            'path': path,
            'savedAt': savedAt,
            'width': width,
            'height': height,
            'count': count,
          }),
        );
    final picture = thumbnail ?? bytes(40);
    final header = ByteData(24)
      ..setUint32(8, format, Endian.little)
      ..setUint32(12, announcedDescription ?? words.length, Endian.little)
      ..setUint32(16, announcedThumbnail ?? picture.length, Endian.little)
      ..setUint32(20, announcedCopy ?? copy.length, Endian.little);
    return Uint8List.fromList([
      ...magic.codeUnits,
      ...header.buffer.asUint8List().skip(8),
      ...words,
      ...picture,
      ...copy,
    ]);
  }

  test('a card is named after the saved path, the same way every time', () {
    // Published FNV-1a vectors, then a path with an accent, as UTF-8.
    expect(GalleryStorage.idFor(''), 'cbf29ce484222325');
    expect(GalleryStorage.idFor('a'), 'af63dc4c8601ec8c');
    expect(GalleryStorage.idFor('foobar'), '85944171f73967e8');
    expect(GalleryStorage.idFor('/dessins/été.edupaint'), 'fab4c4d8aaeeb718');
    expect(
      GalleryStorage.idFor('/a/b.edupaint'),
      isNot(GalleryStorage.idFor('/a/c.edupaint')),
    );
    expect(
      storage.cardPath('fab4c4d8aaeeb718'),
      '${album.path}${Platform.pathSeparator}fab4c4d8aaeeb718.card',
    );
    expect(() => storage.cardPath('../ailleurs'), throwsArgumentError);
  });

  test(
    'a missing folder is an empty album and reading creates nothing',
    () async {
      expect(await storage.list(), isEmpty);
      expect(await album.exists(), isFalse);
      expect(await tree(), isEmpty);
    },
  );

  test(
    'a saved drawing gets one card, one file, that can be read back',
    () async {
      final project = bytes(300, 3);
      final thumbnail = bytes(64, 9);
      await storage.remember(
        sourcePath: '/dessins/Chat été.edupaint',
        name: 'Chat été.edupaint',
        project: project,
        thumbnailPng: thumbnail,
        width: 800,
        height: 1200,
        elementCount: 12,
        savedAt: DateTime.utc(2026, 10, 3, 14, 5, 6, 789),
      );
      expect(await tree(), [cardOf('/dessins/Chat été.edupaint')]);
      final entry = (await storage.list()).single;
      expect(entry.id, id('/dessins/Chat été.edupaint'));
      expect(entry.name, 'Chat été.edupaint');
      expect(entry.sourcePath, '/dessins/Chat été.edupaint');
      expect(entry.savedAt, DateTime.utc(2026, 10, 3, 14, 5, 6, 789));
      expect(entry.savedAt.isUtc, isTrue);
      expect((entry.width, entry.height, entry.elementCount), (800, 1200, 12));
      expect(entry.copyBytes, 300);
      expect(entry.thumbnailBytes, 64);
      expect(entry.hasCopy, isTrue);
      expect(await storage.readThumbnail(entry), thumbnail);
      expect(await storage.readCopy(entry), project);

      // The file is not a project: nothing opens it as a drawing by mistake.
      final written = File('${root.path}/${cardOf(entry.sourcePath)}');
      expect(
        utf8.decode(written.readAsBytesSync().take(8).toList()),
        'COLORCRD',
      );
      // What the album writes is what a card made by hand looks like.
      expect(
        written.readAsBytesSync(),
        card(
          '/dessins/Chat été.edupaint',
          name: 'Chat été.edupaint',
          savedAt: DateTime.utc(
            2026,
            10,
            3,
            14,
            5,
            6,
            789,
          ).millisecondsSinceEpoch,
          width: 800,
          height: 1200,
          count: 12,
          thumbnail: thumbnail,
          copy: project,
        ),
      );

      // Another instance on the same folder reads the same album.
      final another = GalleryStorage(now: later, directory: album);
      expect((await another.list()).single.name, 'Chat été.edupaint');
    },
  );

  test(
    'the caller may reuse its buffers at once: bytes are captured',
    () async {
      final project = bytes(50);
      final thumbnail = bytes(30);
      final written = remember(
        storage,
        '/d/a.edupaint',
        project: project,
        thumbnail: thumbnail,
      );
      project.fillRange(0, project.length, 0);
      thumbnail.fillRange(0, thumbnail.length, 0);
      await written;
      final entry = (await storage.list()).single;
      expect(await storage.readCopy(entry), bytes(50));
      expect(await storage.readThumbnail(entry), bytes(30));
    },
  );

  test('saving the same file again replaces its card', () async {
    await remember(storage, '/d/a.edupaint', at: day(1), count: 1);
    await remember(
      storage,
      '/d/a.edupaint',
      project: bytes(20, 5),
      thumbnail: bytes(10, 6),
      at: day(2),
      count: 4,
    );
    final entry = (await storage.list()).single;
    expect(entry.savedAt, day(2));
    expect(entry.elementCount, 4);
    expect(await storage.readCopy(entry), bytes(20, 5));
    expect(await storage.readThumbnail(entry), bytes(10, 6));
    expect(await tree(), [cardOf('/d/a.edupaint')]);
  });

  test(
    'cards come most recent first, and equal moments in a fixed order',
    () async {
      await remember(storage, '/d/b.edupaint', at: day(2));
      await remember(storage, '/d/c.edupaint', at: day(3));
      await remember(storage, '/d/a.edupaint', at: day(1));
      expect((await storage.list()).map((entry) => entry.name), [
        'c.edupaint',
        'b.edupaint',
        'a.edupaint',
      ]);
      await remember(storage, '/d/a.edupaint', at: day(3));
      final first = (await storage.list()).take(2).map((entry) => entry.id);
      expect(first, [id('/d/a.edupaint'), id('/d/c.edupaint')]..sort());
    },
  );

  test('the album keeps its newest cards and lets the oldest go', () async {
    final small = GalleryStorage(now: later, directory: album, maxEntries: 3);
    for (var number = 1; number <= 5; number++) {
      await remember(small, '/d/$number.edupaint', at: day(number));
    }
    expect((await small.list()).map((entry) => entry.name), [
      '5.edupaint',
      '4.edupaint',
      '3.edupaint',
    ]);
    expect(
      await tree(),
      [
        for (var number = 3; number <= 5; number++)
          cardOf('/d/$number.edupaint'),
      ]..sort(),
    );
    // A card saved again becomes the newest and is kept.
    await remember(small, '/d/3.edupaint', at: day(6));
    await remember(small, '/d/6.edupaint', at: day(7));
    expect((await small.list()).map((entry) => entry.name), [
      '6.edupaint',
      '3.edupaint',
      '5.edupaint',
    ]);
  });

  test('the card just written is kept whatever the clock says', () async {
    // The clock was half a day ahead when three drawings were saved, then
    // it was set right.
    final small = GalleryStorage(
      directory: album,
      maxEntries: 3,
      now: () => day(19, 12),
    );
    for (var number = 1; number <= 3; number++) {
      await remember(small, '/d/$number.edupaint', at: day(20, number));
    }
    await remember(small, '/d/new.edupaint', at: day(19));
    var names = (await small.list()).map((entry) => entry.name).toList();
    expect(names, hasLength(3));
    expect(names, contains('new.edupaint'));
    // The oldest of the others left, as it would on any day.
    expect(names, isNot(contains('1.edupaint')));
    // The next save of another drawing keeps its own card in turn.
    await remember(small, '/d/next.edupaint', at: day(19, 11));
    names = (await small.list()).map((entry) => entry.name).toList();
    expect(names, hasLength(3));
    expect(names, contains('next.edupaint'));
  });

  test('a date far in the future holds no place in the album', () async {
    final small = GalleryStorage(
      directory: album,
      maxEntries: 3,
      now: () => day(19, 12),
    );
    await remember(small, '/d/1.edupaint', at: day(17));
    await remember(small, '/d/2.edupaint', at: day(18));
    // A card dated in the year 275760, and one dated the day after tomorrow.
    write(
      '${id('/d/far')}.card',
      card('/d/far', name: 'far.edupaint', savedAt: 8640000000000000),
    );
    write(
      '${id('/d/soon')}.card',
      card(
        '/d/soon',
        name: 'soon.edupaint',
        savedAt: day(21).millisecondsSinceEpoch,
      ),
    );
    // While there is room they are shown, after the drawings really saved.
    expect((await small.list()).map((entry) => entry.name), [
      '2.edupaint',
      '1.edupaint',
      'far.edupaint',
    ]);
    // In a full album they are the first to leave, not the last.
    await remember(small, '/d/3.edupaint', at: day(19));
    expect((await small.list()).map((entry) => entry.name), [
      '3.edupaint',
      '2.edupaint',
      '1.edupaint',
    ]);
    expect(await tree(), hasLength(3));
    // A clock a few hours ahead is not « far »: such a card ranks by its date.
    write(
      '${id('/d/ahead')}.card',
      card(
        '/d/ahead',
        name: 'ahead.edupaint',
        savedAt: day(20, 6).millisecondsSinceEpoch,
      ),
    );
    expect((await small.list()).first.name, 'ahead.edupaint');
  });

  test(
    'a project too large keeps its card and its picture, without a copy',
    () async {
      final small = GalleryStorage(
        now: later,
        directory: album,
        maxCopyBytes: 100,
      );
      await remember(small, '/d/big.edupaint', project: bytes(101));
      var entry = (await small.list()).single;
      expect(entry.hasCopy, isFalse);
      expect(entry.copyBytes, 0);
      expect(await small.readCopy(entry), isNull);
      expect(await small.readThumbnail(entry), bytes(40, 7));

      // At the limit the copy is kept; when the drawing grows past it, the
      // copy of the older, smaller state does not stay behind.
      await remember(small, '/d/big.edupaint', project: bytes(100));
      entry = (await small.list()).single;
      expect(entry.copyBytes, 100);
      await remember(small, '/d/big.edupaint', project: bytes(140));
      entry = (await small.list()).single;
      expect(entry.hasCopy, isFalse);
      expect(await small.readCopy(entry), isNull);
      expect(await tree(), [cardOf('/d/big.edupaint')]);
      expect(
        File('${root.path}/${cardOf('/d/big.edupaint')}').lengthSync(),
        lessThan(300),
      );
    },
  );

  test(
    'beyond the total, the oldest copies leave and their cards stay',
    () async {
      final small = GalleryStorage(
        now: later,
        directory: album,
        maxCopyBytes: 100,
        maxTotalCopyBytes: 250,
      );
      await remember(small, '/d/1.edupaint', project: bytes(100), at: day(1));
      await remember(small, '/d/2.edupaint', project: bytes(100), at: day(2));
      expect((await small.list()).map((entry) => entry.copyBytes), [100, 100]);
      await remember(small, '/d/3.edupaint', project: bytes(100), at: day(3));
      var entries = await small.list();
      expect(entries.map((entry) => entry.name), [
        '3.edupaint',
        '2.edupaint',
        '1.edupaint',
      ]);
      expect(entries.map((entry) => entry.copyBytes), [100, 100, 0]);
      expect(await small.readCopy(entries[2]), isNull);
      expect(await small.readThumbnail(entries[2]), bytes(40, 7));
      expect(entries[2].savedAt, day(1));
      // A smaller, older copy that still fits is kept.
      await remember(small, '/d/0.edupaint', project: bytes(40), at: day(1, 1));
      entries = await small.list();
      expect(entries.map((entry) => entry.copyBytes), [100, 100, 0, 40]);
      expect(await small.readCopy(entries[3]), bytes(40));
      expect(await tree(), hasLength(4));
    },
  );

  test('what is not a card of this album is left out, and left alone', () async {
    await remember(storage, '/d/good.edupaint', at: day(1));
    final strangers = <String, List<int>>{
      // Not a card at all.
      '/d/text': utf8.encode('bonjour'),
      '/d/empty': const [],
      '/d/short': card('/d/short').sublist(0, 23),
      '/d/magic': card('/d/magic', magic: 'COLORCRX'),
      // A card of a later version of Color.
      '/d/later': card('/d/later', format: 2),
      // Lengths that do not match the file.
      '/d/truncated': card('/d/truncated').sublist(0, 100),
      '/d/longer': [...card('/d/longer'), 0],
      '/d/more-picture': card('/d/more-picture', announcedThumbnail: 41),
      '/d/more-copy': card('/d/more-copy', announcedCopy: 10),
      // Bounds that are not this album's: perhaps another version's.
      '/d/no-picture': card('/d/no-picture', thumbnail: const []),
      '/d/huge-picture': card(
        '/d/huge-picture',
        thumbnail: Uint8List(512 * 1024 + 1),
      ),
      '/d/huge-copy': card(
        '/d/huge-copy',
        copy: Uint8List(8 * 1024 * 1024 + 1),
      ),
      '/d/wordy': card(
        '/d/wordy',
        description: utf8.encode(
          '{"name":"a","path":"/d/wordy","savedAt":1,"width":1,"height":1,"count":1}${' ' * (16 * 1024)}',
        ),
      ),
      // A description that does not hold together.
      '/d/list': card('/d/list', description: utf8.encode('[1, 2, 3]')),
      '/d/words': card('/d/words', description: utf8.encode('bonjour')),
      '/d/latin': card('/d/latin', description: const [0x7b, 0xe9, 0x7d]),
      '/d/name': card('/d/name', name: 7),
      '/d/date': card('/d/date', savedAt: '2026-10-03'),
      '/d/negative-date': card('/d/negative-date', savedAt: -1),
      '/d/far-date': card('/d/far-date', savedAt: 8640000000000001),
      '/d/width': card('/d/width', width: 0),
      '/d/height': card('/d/height', height: 16385),
      '/d/real-width': card('/d/real-width', width: 12.5),
      '/d/count': card('/d/count', count: 10001),
      // A description copied under the name of another path.
      '/d/other': card('/d/elsewhere'),
    };
    for (final MapEntry(key: path, value: content) in strangers.entries) {
      write('${id(path)}.card', content);
    }
    // Hand-made but coherent: accepted, the format is the contract.
    write(
      '${id('/d/fine')}.card',
      card('/d/fine', name: 'fine.edupaint', copy: bytes(10)),
    );
    // Other names, other places: not the album's.
    write('notes.txt', 'à garder');
    if (!volumeIgnoresCase()) {
      write('${id('/d/good.edupaint').toUpperCase()}.card', bytes(4));
    }
    write('${id('/d/good.edupaint')}.card.bak', bytes(4));
    write('${id('/d/good.edupaint')}.json', '{}');
    write('${id('/d/good.edupaint')}.png', bytes(4));
    write('${id('/d/good.edupaint')}.edupaint', bytes(4));
    write('Chat.edupaint', bytes(4));
    write('sous-dossier/${id('/d/good.edupaint')}.card', card('/d/x'));

    final entries = await storage.list();
    expect(entries.map((entry) => entry.name).toSet(), {
      'good.edupaint',
      'fine.edupaint',
    });
    expect(
      await storage.readCopy(
        entries.singleWhere((entry) => entry.name == 'fine.edupaint'),
      ),
      bytes(10),
    );
    // Reading them by their name gives nothing either.
    final laterFormat = GalleryEntry(
      id: id('/d/later'),
      name: 'x',
      sourcePath: '/d/later',
      savedAt: day(1),
      width: 1,
      height: 1,
      elementCount: 0,
      copyBytes: 0,
      thumbnailBytes: 40,
    );
    await expectLater(
      storage.readThumbnail(laterFormat),
      throwsA(isA<FileSystemException>()),
    );

    // Saves, and cards that leave, remove none of them.
    final before = await tree();
    final small = GalleryStorage(now: later, directory: album, maxEntries: 2);
    await remember(small, '/d/new.edupaint', at: day(2));
    await remember(small, '/d/newer.edupaint', at: day(3));
    final after = await tree();
    expect(
      after.toSet().containsAll(
        before.toSet()
          ..remove(cardOf('/d/good.edupaint'))
          ..remove(cardOf('/d/fine')),
      ),
      isTrue,
    );
    expect((await small.list()).map((entry) => entry.name), [
      'newer.edupaint',
      'new.edupaint',
    ]);
    expect(File('${album.path}/notes.txt').readAsStringSync(), 'à garder');
  });

  test('a card that this album could have written under larger bounds survives a smaller album', () async {
    final large = GalleryStorage(
      now: later,
      directory: album,
      maxCopyBytes: 200,
    );
    await remember(large, '/d/large.edupaint', project: bytes(150), at: day(1));
    final before = File('${root.path}/${cardOf('/d/large.edupaint')}')
        .readAsBytesSync();
    final small = GalleryStorage(
      now: later,
      directory: album,
      maxCopyBytes: 100,
    );
    expect(await small.list(), isEmpty);
    await remember(small, '/d/today.edupaint', at: day(2));
    expect(
      File('${root.path}/${cardOf('/d/large.edupaint')}').readAsBytesSync(),
      before,
    );
    // The larger album finds both again.
    expect((await large.list()).map((entry) => entry.name), [
      'today.edupaint',
      'large.edupaint',
    ]);
  });

  test(
    'a write that never finished is cleared once it is old, and only then',
    () async {
      // The age of a file is read on the real clock.
      storage = GalleryStorage(directory: album);
      await remember(storage, '/d/a.edupaint', at: day(1));
      const fresh = '.edupaint-00112233445566778899aabbccddeeff.tmp';
      const old = '.edupaint-ffeeddccbbaa99887766554433221100.tmp';
      const justUnder = '.edupaint-0123456789abcdef0123456789abcdef.tmp';
      // Old too, but not names of this program's writer. In capitals the
      // name is another file only where the volume tells cases apart.
      final foreign = [
        '.edupaint-short.tmp',
        if (!volumeIgnoresCase())
          '.edupaint-FFEEDDCCBBAA99887766554433221100.tmp',
        'edupaint-ffeeddccbbaa99887766554433221100.tmp',
        '.edupaint-ffeeddccbbaa99887766554433221100.tmp.txt',
      ];
      final now = DateTime.now();
      for (final name in [fresh, old, justUnder, ...foreign]) {
        write(name, bytes(12));
      }
      for (final name in [old, ...foreign]) {
        File('${album.path}/$name')
            .setLastModifiedSync(now.subtract(const Duration(minutes: 11)));
      }
      File('${album.path}/$justUnder').setLastModifiedSync(
        now.subtract(
          GalleryStorage.abandonedAfter - const Duration(minutes: 1),
        ),
      );
      // The same name outside the album's folder is not the album's.
      final elsewhere = File('${root.path}/support/$old')
        ..writeAsBytesSync(bytes(3))
        ..setLastModifiedSync(now.subtract(const Duration(days: 2)));

      // Reading never cleans.
      await storage.list();
      expect(File('${album.path}/$old').existsSync(), isTrue);

      await remember(storage, '/d/b.edupaint', at: day(2));
      expect(File('${album.path}/$old').existsSync(), isFalse);
      expect(File('${album.path}/$fresh').existsSync(), isTrue);
      expect(File('${album.path}/$justUnder').existsSync(), isTrue);
      for (final name in foreign) {
        expect(File('${album.path}/$name').existsSync(), isTrue, reason: name);
      }
      expect(elsewhere.existsSync(), isTrue);
      expect((await storage.list()).map((entry) => entry.name), [
        'b.edupaint',
        'a.edupaint',
      ]);
    },
  );

  test(
    'a card that cannot be read for a moment is left out, never cleared',
    () async {
      await remember(storage, '/d/held.edupaint', at: day(1));
      await remember(storage, '/d/free.edupaint', at: day(2));
      final held = id('/d/held.edupaint');
      final before = await tree();
      final outerZone = Zone.current;

      // Another program holds the card: it is absent from the list, and the
      // save that follows clears nothing of it.
      final small = GalleryStorage(now: later, directory: album, maxEntries: 2);
      await IOOverrides.runZoned(
        () async {
          final names = (await small.list()).map((entry) => entry.name);
          expect(names, ['free.edupaint']);
          await remember(small, '/d/new.edupaint', at: day(3));
          await expectLater(
            small.readThumbnail(
              GalleryEntry(
                id: held,
                name: 'held.edupaint',
                sourcePath: '/d/held.edupaint',
                savedAt: day(1),
                width: 1200,
                height: 800,
                elementCount: 3,
                copyBytes: 100,
                thumbnailBytes: 40,
              ),
            ),
            throwsA(isA<FileSystemException>()),
          );
        },
        createFile: (path) {
          final file = outerZone.run(() => File(path));
          return path.endsWith('$held.card') ? _HeldFile(file) : file;
        },
      );
      expect((await tree()).toSet().containsAll(before), isTrue);
      // Released, the card is back with everything it had.
      final entries = await storage.list();
      expect(entries.map((entry) => entry.name), [
        'new.edupaint',
        'free.edupaint',
        'held.edupaint',
      ]);
      expect(await storage.readCopy(entries.last), bytes(100));
      expect(await storage.readThumbnail(entries.last), bytes(40, 7));
    },
  );

  test('a refresh that fails leaves the card that was there', () async {
    await remember(storage, '/d/a.edupaint', at: day(1), count: 1);
    final before = File('${root.path}/${cardOf('/d/a.edupaint')}')
        .readAsBytesSync();
    final outerZone = Zone.current;
    // The disk refuses every new file: no temporary file can be created.
    await IOOverrides.runZoned(
      () async {
        await expectLater(
          remember(
            storage,
            '/d/a.edupaint',
            project: bytes(20, 5),
            at: day(2),
            count: 4,
          ),
          throwsA(isA<FileSystemException>()),
        );
      },
      createFile: (path) {
        final file = outerZone.run(() => File(path));
        return path.endsWith('.tmp') ? _FullDiskFile(file) : file;
      },
    );
    expect(await tree(), [cardOf('/d/a.edupaint')]);
    expect(
      File('${root.path}/${cardOf('/d/a.edupaint')}').readAsBytesSync(),
      before,
    );
    final entry = (await storage.list()).single;
    expect(entry.elementCount, 1);
    expect(entry.savedAt, day(1));
    expect(await storage.readCopy(entry), bytes(100));
  });

  test(
    'removing a card never touches the saved file, nor the other cards',
    () async {
      final saved = File('${root.path}/Documents/Chat.edupaint')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes(77, 4));
      final modified = saved.lastModifiedSync();
      await remember(storage, saved.path, project: bytes(77, 4), at: day(2));
      await remember(storage, '/d/other.edupaint', at: day(1));
      // Remembering reads and writes inside the album only.
      expect(saved.readAsBytesSync(), bytes(77, 4));
      expect(saved.lastModifiedSync(), modified);

      final entries = await storage.list();
      expect(entries.first.sourcePath, saved.path);
      await storage.forget(entries.first);
      expect((await storage.list()).single.name, 'other.edupaint');
      expect(
        await tree(),
        ['Documents/Chat.edupaint', cardOf('/d/other.edupaint')]..sort(),
      );
      expect(saved.readAsBytesSync(), bytes(77, 4));
      expect(saved.lastModifiedSync(), modified);

      // Removing it again, or after the album was emptied by hand, is quiet.
      await storage.forget(entries.first);
      await storage.forget(entries.last);
      await storage.forget(entries.last);
      expect(await storage.list(), isEmpty);
      expect(await tree(), ['Documents/Chat.edupaint']);
    },
  );

  test(
    'nothing in the album’s folder is taken for the file of a drawing',
    () async {
      expect(storage.owns('${album.path}/Chat.edupaint'), isTrue);
      expect(storage.owns('${album.path}/${id('/d/a')}.card'), isTrue);
      expect(storage.owns('${root.path}/support/Chat.edupaint'), isFalse);
      expect(storage.owns('${album.path}/sous-dossier/Chat.edupaint'), isFalse);
      expect(storage.owns('/d/a.edupaint'), isFalse);
      // A drawing saved there by hand gets no card, and stays where it is.
      write('Chat.edupaint', bytes(30, 2));
      expect(
        () => remember(storage, '${album.path}/Chat.edupaint'),
        throwsArgumentError,
      );
      await remember(storage, '/d/a.edupaint', at: day(1));
      await remember(storage, '/d/b.edupaint', at: day(2));
      expect(
        File('${album.path}/Chat.edupaint').readAsBytesSync(),
        bytes(30, 2),
      );
      expect((await storage.list()).map((entry) => entry.name), [
        'b.edupaint',
        'a.edupaint',
      ]);
    },
  );

  test('a link under the name of a card is never followed', () async {
    final outside = File('${root.path}/Documents/precious.card')
      ..createSync(recursive: true)
      ..writeAsBytesSync(card('/d/linked', name: 'precious', copy: bytes(10)));
    final before = outside.readAsBytesSync();
    await album.create(recursive: true);
    final link = Link('${album.path}/${id('/d/linked')}.card')
      ..createSync(outside.path);
    final entry = GalleryEntry(
      id: id('/d/linked'),
      name: 'precious',
      sourcePath: '/d/linked',
      savedAt: day(1),
      width: 1200,
      height: 800,
      elementCount: 2,
      copyBytes: 10,
      thumbnailBytes: 40,
    );
    // Not listed, and not read through its name.
    expect(await storage.list(), isEmpty);
    await expectLater(
      storage.readThumbnail(entry),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      storage.readCopy(entry),
      throwsA(isA<FileSystemException>()),
    );
    // Writing over the link is refused: the file outside keeps its bytes.
    await expectLater(
      remember(storage, '/d/linked', project: bytes(10, 9)),
      throwsA(isA<FileSystemException>()),
    );
    expect(outside.readAsBytesSync(), before);
    // Another save leaves the link alone.
    await remember(storage, '/d/a.edupaint');
    expect(link.existsSync(), isTrue);
    // Removing the card removes the link itself.
    await storage.forget(entry);
    expect(outside.readAsBytesSync(), before);
    expect(link.existsSync(), isFalse);
  }, skip: Platform.isWindows ? 'Links need a privilege on Windows.' : null);

  test('only the name of a card is ever read or removed', () async {
    final outside = File('${root.path}/support/precious.card')
      ..createSync(recursive: true)
      ..writeAsBytesSync(card('/d/x', copy: bytes(10)));
    final before = outside.readAsBytesSync();
    await remember(storage, '/d/a.edupaint');
    for (final hostile in [
      '../precious',
      '..${Platform.pathSeparator}precious',
      '',
      'precious',
      '0123456789abcdef/../../precious',
      '0123456789ABCDEF',
      '0123456789abcde',
      '0123456789abcdef0',
    ]) {
      final entry = GalleryEntry(
        id: hostile,
        name: 'x',
        sourcePath: '/d/x',
        savedAt: day(1),
        width: 1200,
        height: 800,
        elementCount: 2,
        copyBytes: 10,
        thumbnailBytes: 40,
      );
      await expectLater(storage.readThumbnail(entry), throwsArgumentError);
      await expectLater(storage.readCopy(entry), throwsArgumentError);
      await expectLater(storage.forget(entry), throwsArgumentError);
    }
    expect(outside.readAsBytesSync(), before);
    expect((await storage.list()).single.name, 'a.edupaint');
  });

  test(
    'a pipe under the name of a card stops neither the list nor a save',
    () async {
      await remember(storage, '/d/a.edupaint', at: day(1));
      final pipe = '${album.path}/${id('/d/pipe')}.card';
      final made = Process.runSync('mkfifo', [pipe]);
      if (made.exitCode != 0) {
        markTestSkipped('mkfifo is not available here.');
        return;
      }
      final listed = await storage.list().timeout(const Duration(seconds: 10));
      expect(listed.single.name, 'a.edupaint');
      await remember(
        storage,
        '/d/b.edupaint',
        at: day(2),
      ).timeout(const Duration(seconds: 10));
      expect(
        FileSystemEntity.typeSync(pipe, followLinks: false),
        FileSystemEntityType.pipe,
      );
    },
    skip: Platform.isWindows ? 'No named pipe in a folder on Windows.' : null,
  );

  test(
    'a request that the folder never answers fails alone; the next is served',
    () async {
      final quick = GalleryStorage(
        now: later,
        directory: album,
        operationTimeout: const Duration(milliseconds: 300),
      );
      await remember(quick, '/d/stalled.edupaint', at: day(1));
      await remember(quick, '/d/free.edupaint', at: day(2));
      final stalled = (await quick.list()).last;
      final outerZone = Zone.current;
      await IOOverrides.runZoned(
        () async {
          final copy = quick.readCopy(stalled);
          final listed = quick.list();
          await expectLater(copy, throwsA(isA<TimeoutException>()));
          // The stalled card is opened again by the list, which waits for it
          // no longer than its own time; the request after it is served.
          await expectLater(listed, throwsA(isA<TimeoutException>()));
        },
        createFile: (path) {
          final file = outerZone.run(() => File(path));
          return path.endsWith('${stalled.id}.card')
              ? _StalledFile(file)
              : file;
        },
      );
      expect((await quick.list()).map((entry) => entry.name), [
        'free.edupaint',
        'stalled.edupaint',
      ]);
    },
  );

  test(
    'a card that cannot be described is refused before anything is written',
    () async {
      Future<void> attempt({
        String path = '/d/a.edupaint',
        String name = 'a.edupaint',
        int thumbnail = 40,
        int width = 1200,
        int height = 800,
        int count = 1,
      }) => storage.remember(
        sourcePath: path,
        name: name,
        project: bytes(10),
        thumbnailPng: bytes(thumbnail),
        width: width,
        height: height,
        elementCount: count,
      );
      expect(() => attempt(path: ''), throwsArgumentError);
      expect(() => attempt(path: '/${'p' * 4096}'), throwsArgumentError);
      expect(() => attempt(name: ''), throwsArgumentError);
      expect(() => attempt(thumbnail: 0), throwsArgumentError);
      expect(() => attempt(thumbnail: 512 * 1024 + 1), throwsArgumentError);
      expect(() => attempt(width: 0), throwsArgumentError);
      expect(() => attempt(width: 16385), throwsArgumentError);
      expect(() => attempt(height: 0), throwsArgumentError);
      expect(() => attempt(height: 16385), throwsArgumentError);
      expect(() => attempt(count: -1), throwsArgumentError);
      expect(() => attempt(count: 10001), throwsArgumentError);
      expect(await album.exists(), isFalse);

      // The limits themselves are accepted, and a very long name is shortened.
      await storage.remember(
        sourcePath: '/${'p' * 4095}',
        name: 'n' * 300,
        project: Uint8List(0),
        thumbnailPng: bytes(GalleryStorage.maxThumbnailBytes),
        width: 16384,
        height: 1,
        elementCount: 10000,
      );
      final entry = (await storage.list()).single;
      expect(entry.name, 'n' * 255);
      expect(entry.sourcePath, hasLength(4096));
      expect(entry.hasCopy, isFalse);
      expect(
        (entry.width, entry.height, entry.elementCount),
        (16384, 1, 10000),
      );
    },
  );

  test('a name is shown on one line, well formed, never empty', () async {
    // Written by this album: tidied before it is stored.
    await remember(
      storage,
      '/d/a.edupaint',
      name: 'Chat\nnoir\u0007 \ud83d.edupaint',
      at: day(3),
    );
    // Written by hand, or damaged: tidied when it is read.
    write(
      '${id('/d/b')}.card',
      card(
        '/d/b',
        description: utf8.encode(
          '{"name":"Chien \\ud83d\\u2028.edupaint","path":"/d/b","savedAt":${day(2).millisecondsSinceEpoch},"width":1,"height":1,"count":0}',
        ),
      ),
    );
    write('${id('/d/c')}.card', card('/d/c', name: ' \n ', savedAt: 1));
    write('${id('/d/d')}.card', card('/d/d', name: 'n' * 300, savedAt: 0));
    final names = (await storage.list()).map((entry) => entry.name).toList();
    expect(names, [
      'Chat noir  �.edupaint',
      'Chien � .edupaint',
      'Dessin',
      'n' * 255,
    ]);
    for (final name in names) {
      // Well formed: written as UTF-8 and read back, it is the same.
      expect(utf8.decode(utf8.encode(name)), name);
    }
  });

  test(
    'requests made together are served in order, and one card is written once',
    () async {
      var writes = 0;
      final outerZone = Zone.current;
      await IOOverrides.runZoned(
        () async {
          final requests = [
            for (var number = 1; number <= 6; number++)
              remember(
                storage,
                '/d/a.edupaint',
                project: bytes(10 * number, number),
                thumbnail: bytes(5 * number, number),
                at: day(number),
                count: number,
              ),
          ];
          final listed = storage.list();
          await Future.wait(requests);
          final entry = (await listed).single;
          expect(entry.elementCount, 6);
          expect(await storage.readCopy(entry), bytes(60, 6));
          expect(await storage.readThumbnail(entry), bytes(30, 6));
        },
        createFile: (path) {
          if (path.endsWith('.tmp')) writes++;
          return outerZone.run(() => File(path));
        },
      );
      expect(await tree(), [cardOf('/d/a.edupaint')]);
      // The five saves that waited behind the sixth had nothing left to
      // write: one temporary file was made, for one card.
      expect(writes, 1);
      // Saves of different files each keep their card.
      await Future.wait([
        for (var number = 1; number <= 4; number++)
          remember(storage, '/d/$number.edupaint', at: day(number)),
      ]);
      expect(await storage.list(), hasLength(5));
    },
  );

  test(
    'a failure is reported to its caller and the next request is served',
    () async {
      await remember(storage, '/d/a.edupaint');
      final entry = (await storage.list()).single;
      File(storage.cardPath(entry.id)).deleteSync();
      final failed = storage.readThumbnail(entry);
      final copy = storage.readCopy(entry);
      final listed = storage.list();
      await expectLater(failed, throwsA(isA<FileSystemException>()));
      await expectLater(copy, throwsA(isA<FileSystemException>()));
      expect(await listed, isEmpty);
      await remember(storage, '/d/b.edupaint');
      expect((await storage.list()).single.name, 'b.edupaint');
    },
  );

  test(
    'a card refreshed since it was listed gives what it holds now',
    () async {
      await remember(storage, '/d/a.edupaint', project: bytes(100), at: day(1));
      final entry = (await storage.list()).single;
      // The same file is saved again while its card is shown.
      await remember(
        storage,
        '/d/a.edupaint',
        project: bytes(120, 3),
        thumbnail: bytes(50, 4),
        at: day(2),
      );
      expect(await storage.readCopy(entry), bytes(120, 3));
      expect(await storage.readThumbnail(entry), bytes(50, 4));
      // Its copy leaves with the next total: the old card says so too.
      final small = GalleryStorage(
        now: later,
        directory: album,
        maxCopyBytes: 200,
        maxTotalCopyBytes: 150,
      );
      await remember(small, '/d/b.edupaint', project: bytes(100), at: day(3));
      expect(await small.readCopy(entry), isNull);
      // Cut short behind its back, it is no card any more.
      final file = File(storage.cardPath(entry.id));
      file.writeAsBytesSync(file.readAsBytesSync().sublist(0, 60));
      await expectLater(
        storage.readCopy(entry),
        throwsA(isA<FileSystemException>()),
      );
      expect((await storage.list()).map((entry) => entry.name), ['b.edupaint']);
    },
  );

  test('the list never shows more cards than the album keeps', () async {
    for (var number = 0; number < 30; number++) {
      write(
        '${id('/d/$number')}.card',
        card('/d/$number', name: '$number.edupaint', savedAt: 1000 + number),
      );
    }
    final entries = await storage.list();
    expect(entries, hasLength(24));
    expect(entries.first.name, '29.edupaint');
    expect(entries.last.name, '6.edupaint');
    // The next save brings the folder back to its bounds.
    await remember(storage, '/d/new.edupaint', at: day(1));
    expect(await tree(), hasLength(24));
  });

  test('an album folder that cannot be created fails the card, not the caller’s file', () async {
    // The place of the folder is taken by a file.
    File('${root.path}/support').writeAsStringSync('occupé');
    await expectLater(
      remember(storage, '/d/a.edupaint'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await tree(), ['support']);
    expect(File('${root.path}/support').readAsStringSync(), 'occupé');
  });
}

/// A file that exists and that the system refuses to open, as when another
/// program holds it.
class _HeldFile implements File {
  _HeldFile(this.delegate);
  final File delegate;

  @override
  String get path => delegate.path;

  FileSystemException get _refusal => FileSystemException(
    'Injected refusal',
    path,
    const OSError('Permission denied', 13),
  );

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      Future.error(_refusal);

  @override
  Future<int> length() => Future.error(_refusal);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A file that the system never finishes opening, as on a folder that hangs.
class _StalledFile implements File {
  _StalledFile(this.delegate);
  final File delegate;

  @override
  String get path => delegate.path;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      Completer<RandomAccessFile>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A new file that a full disk refuses to create.
class _FullDiskFile implements File {
  _FullDiskFile(this.delegate);
  final File delegate;

  @override
  String get path => delegate.path;

  @override
  File get absolute => this;

  @override
  Directory get parent => delegate.parent;

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) =>
      Future.error(
        FileSystemException(
          'Injected full disk',
          path,
          const OSError('No space left on device', 28),
        ),
      );

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async => this;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
