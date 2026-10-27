// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:edupaint_flutter_study/file_operation_cleanup_exception.dart';
import 'package:edupaint_flutter_study/project_storage.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

void add(RustDocument doc, [int rgb = 0x123456]) => doc.addShape(
  VectorKind.rectangle,
  const DocumentPoint(2, 3),
  const DocumentPoint(12, 14),
  rgb: rgb,
  width: 2,
  fillRgb: rgb,
);

class BarrierDocument implements RustDocument {
  final inner = RustDocument(width: 32, height: 24);
  @override
  void addShape(
    VectorKind kind,
    DocumentPoint start,
    DocumentPoint end, {
    required int rgb,
    required double width,
    int? fillRgb,
  }) => inner.addShape(
    kind,
    start,
    end,
    rgb: rgb,
    width: width,
    fillRgb: fillRgb,
  );
  @override
  Uint8List exportProject() => inner.exportProject();
  @override
  void dispose() => inner.dispose();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  final started = Completer<void>();
  final prepared = Completer<void>();
  final release = Completer<void>();
  int preparations = 0;
  @override
  Future<int> prepareProjectFile(String path) async {
    preparations++;
    final operation = inner.prepareProjectFile(path);
    started.complete();
    final size = await operation;
    prepared.complete();
    await release.future;
    return size;
  }
}

class ObservedFile implements File {
  ObservedFile(this.file, {this.renameHook, this.deleteHook});
  final File file;
  final Future<File> Function(File, String)? renameHook;
  final Future<FileSystemEntity> Function(File)? deleteHook;
  @override
  String get path => file.path;
  @override
  File get absolute => ObservedFile(
    file.absolute,
    renameHook: renameHook,
    deleteHook: deleteHook,
  );
  @override
  Directory get parent => file.parent;
  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await file.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      file.open(mode: mode);
  @override
  Future<File> rename(String path) =>
      renameHook?.call(file, path) ?? file.rename(path);
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      deleteHook?.call(file) ?? file.delete(recursive: recursive);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  late Directory directory;
  late ProjectStorage storage;
  late File target;
  late Uint8List old;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'color-two-phase-only-test-',
    );
    storage = ProjectStorage(recoveryDirectory: directory);
    target = File('${directory.path}/recovery.edupaint');
    final seed = RustDocument(width: 32, height: 24);
    try {
      add(seed, 0xabcdef);
      old = seed.exportProject();
    } finally {
      seed.dispose();
    }
    await target.writeAsBytes(old);
  });
  tearDown(() async {
    // Only this test's fresh synthetic directory is removed; no user recovery.
    await directory.delete(recursive: true);
  });
  Future<List<FileSystemEntity>> temporaries() =>
      directory.list().where((p) => p.path.endsWith('.tmp')).toList();

  for (final background in [false, true]) {
    test(
      'real worker commits exact v${background ? 3 : 2}, SVG and PNG',
      () async {
        final doc = background
            ? RustDocument.fromBackgroundPng(
                File('test/fixtures/raster/rgba-asymmetric.png')
                    .readAsBytesSync(),
              )
            : RustDocument(width: 32, height: 24);
        try {
          add(doc);
          final bytes = doc.exportProject();
          final svg = doc.exportSvg();
          expect(
            await storage.writeRecoveryDocument(doc, shouldCommit: () => true),
            isTrue,
          );
          final recovered = (await storage.readRecovery())!;
          expect(recovered, orderedEquals(bytes));
          final reopened = RustDocument.fromProject(recovered);
          try {
            expect(reopened.exportSvg(), svg);
            expect(reopened.copyBackgroundPng(), doc.copyBackgroundPng());
          } finally {
            reopened.dispose();
          }
          expect(await temporaries(), isEmpty);
        } finally {
          doc.dispose();
        }
      },
      skip: !available,
    );
  }

  test('false initial guard never touches a disposed document', () async {
    final doc = RustDocument();
    doc.dispose();
    expect(
      await storage.writeRecoveryDocument(doc, shouldCommit: () => false),
      isFalse,
    );
    expect(await target.readAsBytes(), old);
    expect(await temporaries(), isEmpty);
  }, skip: !available);

  for (final boundary in [1, 2, 3]) {
    test(
      'throwing guard at decision $boundary cleans only its prepared file',
      () async {
        final doc = RustDocument();
        add(doc);
        var calls = 0;
        final failure = StateError('guard-$boundary');
        try {
          await expectLater(
            storage.writeRecoveryDocument(
              doc,
              shouldCommit: () {
                calls++;
                if (calls == boundary) throw failure;
                return true;
              },
            ),
            throwsA(same(failure)),
          );
          expect(calls, boundary);
          expect(await target.readAsBytes(), old);
          expect(await temporaries(), isEmpty);
          expect(
            await storage.writeRecoveryDocument(doc, shouldCommit: () => true),
            isTrue,
          );
        } finally {
          doc.dispose();
        }
      },
      skip: !available,
    );
  }

  test(
    'guard false after the last destination await never publishes',
    () async {
      final doc = RustDocument();
      add(doc);
      var calls = 0;
      try {
        expect(
          await storage.writeRecoveryDocument(
            doc,
            shouldCommit: () => ++calls < 3,
          ),
          isFalse,
        );
        expect(calls, 3);
        expect(await target.readAsBytes(), old);
        expect(await temporaries(), isEmpty);
      } finally {
        doc.dispose();
      }
    },
    skip: !available,
  );

  test('one pending preparation only; clear waits for abandonment', () async {
    final doc = BarrierDocument();
    add(doc);
    var current = true;
    try {
      final operation = storage.writeRecoveryDocument(
        doc,
        shouldCommit: () => current,
      );
      await doc.prepared.future;
      expect(
        () => storage.writeRecoveryDocument(doc, shouldCommit: () => true),
        throwsStateError,
      );
      expect(doc.preparations, 1);
      current = false;
      var cleared = false;
      final clear = storage.clearRecovery().then((_) => cleared = true);
      await Future<void>.delayed(Duration.zero);
      expect(cleared, isFalse);
      expect(await temporaries(), hasLength(1));
      doc.release.complete();
      expect(await operation, isFalse);
      await clear;
      expect(await storage.readRecovery(), isNull);
      expect(await temporaries(), isEmpty);
    } finally {
      if (!doc.release.isCompleted) doc.release.complete();
      doc.dispose();
    }
  }, skip: !available);

  test(
    'captured native snapshot survives disposal during preparation',
    () async {
      final doc = BarrierDocument();
      add(doc);
      final expected = doc.exportProject();
      final operation = storage.writeRecoveryDocument(
        doc,
        shouldCommit: () => true,
      );
      await doc.started.future;
      doc.dispose();
      await doc.prepared.future;
      doc.release.complete();
      expect(await operation, isTrue);
      expect(await target.readAsBytes(), orderedEquals(expected));
    },
    skip: !available,
  );

  test(
    'snapshot captures at queue head after prior operation, not invocation',
    () async {
      final doc = RustDocument(width: 32, height: 24);
      add(doc);
      final atRename = Completer<void>();
      final release = Completer<void>();
      final outer = Zone.current;
      var renames = 0;
      try {
        await IOOverrides.runZoned(
          () async {
            final prior = storage.writeRecovery(old);
            await atRename.future;
            final operation = storage.writeRecoveryDocument(
              doc,
              shouldCommit: () => true,
            );
            add(doc, 0xabcdef);
            final expected = doc.exportProject();
            release.complete();
            await prior;
            expect(await operation, isTrue);
            expect(await target.readAsBytes(), orderedEquals(expected));
          },
          createFile: (path) => ObservedFile(
            outer.run(() => File(path)),
            renameHook: (file, path) async {
              if (++renames == 1) {
                atRename.complete();
                await release.future;
              }
              return file.rename(path);
            },
          ),
        );
      } finally {
        if (!release.isCompleted) release.complete();
        doc.dispose();
      }
    },
    skip: !available,
  );

  test(
    'successful in-flight rename returns true then queued clear removes it',
    () async {
      final doc = RustDocument();
      add(doc);
      var current = true;
      final renamed = Completer<void>();
      final release = Completer<void>();
      final outer = Zone.current;
      try {
        await IOOverrides.runZoned(
          () async {
            final operation = storage.writeRecoveryDocument(
              doc,
              shouldCommit: () => current,
            );
            await renamed.future;
            current = false;
            final clear = storage.clearRecovery();
            release.complete();
            expect(await operation, isTrue);
            await clear;
            expect(await storage.readRecovery(), isNull);
          },
          createFile: (path) => ObservedFile(
            outer.run(() => File(path)),
            renameHook: (file, path) async {
              final result = await file.rename(path);
              renamed.complete();
              await release.future;
              return result;
            },
          ),
        );
      } finally {
        if (!release.isCompleted) release.complete();
        doc.dispose();
      }
    },
    skip: !available,
  );

  for (final cleanupFails in [false, true]) {
    test(
      'rename failure preserves target; cleanup failure=$cleanupFails stays secondary',
      () async {
        final doc = RustDocument();
        add(doc);
        final outer = Zone.current;
        final primary = FileSystemException('rename-primary');
        final cleanup = FileSystemException('cleanup-secondary');
        try {
          await IOOverrides.runZoned(
            () async {
              await expectLater(
                storage.writeRecoveryDocument(doc, shouldCommit: () => true),
                cleanupFails
                    ? throwsA(
                        isA<FileOperationCleanupException>()
                            .having(
                              (e) => e.primaryError,
                              'primary',
                              same(primary),
                            )
                            .having(
                              (e) => e.cleanupErrors.single,
                              'cleanup',
                              same(cleanup),
                            ),
                      )
                    : throwsA(same(primary)),
              );
            },
            createFile: (path) => ObservedFile(
              outer.run(() => File(path)),
              renameHook: (_, _) async => throw primary,
              deleteHook: cleanupFails ? (_) async => throw cleanup : null,
            ),
          );
          expect(await target.readAsBytes(), old);
          expect(await temporaries(), hasLength(cleanupFails ? 1 : 0));
          expect(
            await storage.writeRecoveryDocument(doc, shouldCommit: () => true),
            isTrue,
          );
        } finally {
          doc.dispose();
        }
      },
      skip: !available,
    );
  }

  test(
    'worker collision never removes pre-existing file and releases export slot',
    () async {
      final doc = RustDocument();
      add(doc);
      final collision = File('${directory.path}/owned-elsewhere.tmp');
      await collision.writeAsString('preserve this pre-existing file');
      try {
        await expectLater(
          doc.prepareProjectFile(collision.path),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          await collision.readAsString(),
          'preserve this pre-existing file',
        );
        expect(
          await doc.exportProjectAsync(),
          orderedEquals(doc.exportProject()),
        );
        expect(
          await storage.writeRecoveryDocument(doc, shouldCommit: () => true),
          isTrue,
        );
      } finally {
        doc.dispose();
      }
    },
    skip: !available,
  );
}
