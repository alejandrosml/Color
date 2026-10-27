// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:edupaint_flutter_study/project_storage.dart';
import 'package:edupaint_flutter_study/rust_document.dart' show maxProjectBytes;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late ProjectStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('edupaint-storage-test-');
    storage = ProjectStorage(
      recoveryDirectory: Directory('${directory.path}/recovery'),
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'project create and replacement leave only the final complete file',
    () async {
      // The separator of the system: the listing below is compared with it.
      final path =
          '${directory.path}${Platform.pathSeparator}Dessin été.edupaint';
      await ProjectStorage.writeProject(path, Uint8List.fromList([1, 2, 3]));
      await ProjectStorage.writeProject(path, Uint8List.fromList([4, 5]));
      expect(await ProjectStorage.readProject(path), [4, 5]);
      expect(await directory.list().map((entry) => entry.path).toList(), [
        path,
      ]);
    },
  );

  test(
    'failed rename preserves original bytes and cleans the temporary file',
    () async {
      final path =
          '${directory.path}${Platform.pathSeparator}original.edupaint';
      await File(path).writeAsBytes([1, 2, 3]);
      final outerZone = Zone.current;
      await IOOverrides.runZoned(
        () async {
          await expectLater(
            ProjectStorage.writeProject(path, Uint8List.fromList([9, 8])),
            throwsA(isA<FileSystemException>()),
          );
        },
        createFile: (filePath) {
          final file = outerZone.run(() => File(filePath));
          return filePath.contains('.edupaint-')
              ? _RenameFailureFile(file)
              : file;
        },
      );
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      expect(await directory.list().map((entry) => entry.path).toList(), [
        path,
      ]);
    },
  );

  test(
    'failed replacement refuses directories and preserves their contents',
    () async {
      final target = await Directory('${directory.path}/document.edupaint')
          .create();
      final original = await File('${target.path}/original')
          .writeAsString('keep');
      await expectLater(
        ProjectStorage.writeProject(target.path, Uint8List.fromList([9])),
        throwsA(isA<FileSystemException>()),
      );
      expect(await original.readAsString(), 'keep');
      expect(await directory.list().length, 1);
    },
  );

  test(
    'a symbolic link destination is rejected without touching its target',
    () async {
      final original = await File('${directory.path}/original')
          .writeAsString('keep');
      final link = await Link('${directory.path}/linked.edupaint')
          .create(original.path);
      await expectLater(
        ProjectStorage.writeProject(link.path, Uint8List.fromList([9])),
        throwsA(isA<FileSystemException>()),
      );
      expect(await link.target(), original.path);
      expect(await original.readAsString(), 'keep');
    },
    skip: Platform.isWindows
        ? 'Creating symlinks may need Windows developer privileges.'
        : false,
  );

  test('reads accept the byte cap and reject a larger file', () async {
    final path = '${directory.path}/large.edupaint';
    await File(path).writeAsBytes(Uint8List(maxProjectBytes));
    expect((await ProjectStorage.readProject(path)).length, maxProjectBytes);
    await File(path).writeAsBytes([1], mode: FileMode.append);
    await expectLater(ProjectStorage.readProject(path), throwsFormatException);
  });

  test('oversized writes never replace a previous valid file', () async {
    final path = '${directory.path}/original.edupaint';
    await File(path).writeAsBytes([4, 5]);
    expect(
      () => ProjectStorage.writeProject(path, Uint8List(maxProjectBytes + 1)),
      throwsFormatException,
    );
    expect(await File(path).readAsBytes(), [4, 5]);
  });

  test('missing recovery is null and repeated clear is harmless', () async {
    expect(await storage.readRecovery(), isNull);
    await storage.clearRecovery();
    await storage.writeRecovery(Uint8List.fromList([3, 2, 1]));
    expect(await storage.readRecovery(), [3, 2, 1]);
    await storage.clearRecovery();
    await storage.clearRecovery();
    expect(await storage.readRecovery(), isNull);
  });

  test(
    'queued write, clear, write, read observes only the last snapshot',
    () async {
      final pending = <Future<void>>[
        storage.writeRecovery(Uint8List(maxProjectBytes)),
        storage.clearRecovery(),
        storage.writeRecovery(Uint8List.fromList([7, 8])),
      ];
      expect(await storage.readRecovery(), [7, 8]);
      await Future.wait(pending);
      expect(await storage.recoveryDirectory.list().length, 1);
    },
  );

  test('queued clear prevents an older write returning at restart', () async {
    final write = storage.writeRecovery(Uint8List(maxProjectBytes));
    final clear = storage.clearRecovery();
    expect(await storage.readRecovery(), isNull);
    await Future.wait([write, clear]);
  });

  test('write captures bytes before asynchronous work', () async {
    final data = Uint8List.fromList([1, 2]);
    final operation = storage.writeRecovery(data);
    data[0] = 99;
    await operation;
    expect(await storage.readRecovery(), [1, 2]);
  });

  test('failed recovery operation does not poison the queue', () async {
    final blocker = await File(storage.recoveryDirectory.path)
        .writeAsString('keep');
    await expectLater(
      storage.writeRecovery(Uint8List.fromList([1])),
      throwsA(isA<FileSystemException>()),
    );
    expect(await blocker.readAsString(), 'keep');
    await blocker.delete();
    await storage.writeRecovery(Uint8List.fromList([2]));
    expect(await storage.readRecovery(), [2]);
  });

  test('recovery I/O errors are not reported as absent recovery', () async {
    await storage.recoveryDirectory.create();
    await Directory('${storage.recoveryDirectory.path}/recovery.edupaint')
        .create();
    await expectLater(
      storage.readRecovery(),
      throwsA(isA<FileSystemException>()),
    );
  });
}

/// Real file I/O up to the replacement boundary, then a deterministic failure.
class _RenameFailureFile implements File {
  _RenameFailureFile(this.delegate);
  final File delegate;

  @override
  String get path => delegate.path;

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await delegate.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      delegate.open(mode: mode);

  @override
  Future<File> rename(String newPath) async =>
      throw FileSystemException('Injected replacement failure', newPath);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      delegate.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
