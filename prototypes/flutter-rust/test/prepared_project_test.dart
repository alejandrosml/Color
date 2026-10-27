// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/raster_source.dart';
import 'package:edupaint_flutter_study/project_storage.dart';

File fixture(String name) => File('test/fixtures/project-open/$name');
void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  for (final name in [
    'legacy-v1.edupaint',
    'portrait-v2.edupaint',
    'rgba-v3.edupaint',
    'locked-page-v5.edupaint',
    'layers-only-v5.edupaint',
  ]) {
    test('prepared bytes capture and normalize $name', () async {
      final input = await fixture(name).readAsBytes();
      final expected = await fixture('$name.normalized').readAsBytes();
      final operation = RustDocument.loadProjectBytes(input);
      input.fillRange(
        0,
        input.length,
        0,
      ); // The caller's later edit is detached.
      final prepared = await operation;
      try {
        expect(prepared.document.exportProject(), expected);
      } finally {
        prepared.dispose();
      }
    }, skip: !available);
  }
  for (final name in ['portrait-v2.edupaint', 'rgb-v3.edupaint']) {
    test('prepared real file path loads $name', () async {
      final prepared = await RustDocument.loadProjectFile(
        fixture(name).absolute.path,
      );
      try {
        expect(
          prepared.document.exportProject(),
          await fixture('$name.normalized').readAsBytes(),
        );
      } finally {
        prepared.dispose();
      }
    }, skip: !available);
  }
  test(
    'a page drawing of version 5 is prepared with its locked layers',
    () async {
      final prepared = await RustDocument.loadProjectFile(
        fixture('locked-page-v5.edupaint').absolute.path,
      );
      try {
        final document = prepared.document;
        // Read in the worker, the locks come back with the layers.
        expect(document.layers.map((layer) => (layer.id, layer.locked)), [
          (1, true),
          (0, false),
          (3, false),
          (4, true),
          (2, true),
        ]);
        expect(document.lockedLayers, {1, 4, 2});
        expect(document.unlockedPaintOrder, [2, 3]);
        expect(document.strokes[3].kind, VectorKind.contour);
        expect(prepared.takeBackground(), isNull);
      } finally {
        prepared.dispose();
      }
    },
    skip: !available,
  );
  test('in-memory entry rejects invalid bounds and corrupt data', () async {
    expect(
      () => RustDocument.loadProjectBytes(Uint8List(3)),
      throwsFormatException,
    );
    await expectLater(
      RustDocument.loadProjectBytes(
        await fixture('bad-project-crc.edupaint').readAsBytes(),
      ),
      throwsFormatException,
    );
  }, skip: !available);
  for (final name in ['rgb', 'rgba']) {
    testWidgets('transferred canonical decode preserves $name pixels', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final prepared = await RustDocument.loadProjectFile(
          fixture('$name-v3.edupaint').absolute.path,
        );
        ImportedBackground? transferred;
        ImportedBackground? previous;
        try {
          transferred = await decodeTransferredCanonicalBackground(
            prepared.takeBackground()!,
          );
          previous = await decodeCanonicalBackground(
            await fixture('$name.png').readAsBytes(),
          );
          expect([transferred.width, transferred.height], [32, 24]);
          expect(
            (await transferred.image.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba,
            ))!.buffer.asUint8List(),
            (await previous.image.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba,
            ))!.buffer.asUint8List(),
          );
        } finally {
          transferred?.dispose();
          previous?.dispose();
          prepared.dispose();
        }
      });
    }, skip: !available);
  }
  testWidgets(
    'structurally valid but undecodable PNG is refused before adoption',
    (tester) async {
      await tester.runAsync(() async {
        final prepared = await RustDocument.loadProjectFile(
          fixture('structural-png-undecodable.edupaint').absolute.path,
        );
        try {
          expect(prepared.document.backgroundInfo, isNotNull);
          await expectLater(
            decodeTransferredCanonicalBackground(prepared.takeBackground()!),
            throwsA(anything),
          );
        } finally {
          prepared.dispose();
        }
        // An error releases the single image-preparation slot for a later import.
        final valid = await decodeTransferredCanonicalBackground(
          TransferableTypedData.fromList([
            await fixture('rgb.png').readAsBytes(),
          ]),
        );
        valid.dispose();
      });
    },
    skip: !available,
  );
  test('prepared recovery is queued before clear and after writes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'color-prepared-recovery-',
    );
    final storage = ProjectStorage(recoveryDirectory: directory);
    try {
      final bytes = await fixture('portrait-v2.edupaint').readAsBytes();
      final write = storage.writeRecovery(bytes);
      final read = storage.readPreparedRecovery();
      await write;
      final clear = storage.clearRecovery();
      final prepared = await read;
      expect(prepared, isNotNull);
      try {
        expect(prepared!.document.exportProject(), bytes);
      } finally {
        prepared?.dispose();
      }
      await clear;
      expect(await storage.readPreparedRecovery(), isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: !available);
  test('prepared recovery treats only absence as missing and preserves corrupt bytes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'color-prepared-recovery-error-',
    );
    final storage = ProjectStorage(recoveryDirectory: directory);
    final path = '${directory.path}${Platform.pathSeparator}recovery.edupaint';
    try {
      expect(await storage.readPreparedRecovery(), isNull);
      final bytes = await fixture('bad-project-crc.edupaint').readAsBytes();
      await storage.writeRecovery(bytes);
      await expectLater(storage.readPreparedRecovery(), throwsFormatException);
      expect(await File(path).readAsBytes(), bytes);
      await File(path).delete();
      await Directory(path).create();
      await expectLater(
        storage.readPreparedRecovery(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await Directory(path).exists(), isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: !available);
}
