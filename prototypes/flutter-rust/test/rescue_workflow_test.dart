// SPDX-License-Identifier: MIT
// A drawing of Color 1.1 whose file is damaged (Color 1.1): Ouvrir offers to
// open what is intact, as a drawing to save under another name; the damaged
// file stays as it is. Real Rust documents; only dialogs' destinations and
// storage are in memory.
import 'dart:io';
import 'dart:typed_data';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  // Two layers, a trait on the first and a rectangle on the second, then a
  // byte of the last layer's objects changed: its block no longer checks.
  Uint8List damaged() {
    final document = RustDocument();
    try {
      document.addStroke(
        const [DocumentPoint(100, 100), DocumentPoint(300, 200)],
        rgb: 0x112233,
        width: 8,
      );
      document.addLayer();
      document.addShape(
        VectorKind.rectangle,
        const DocumentPoint(500, 300),
        const DocumentPoint(800, 600),
        rgb: 0xe83d48,
        width: 6,
      );
      final bytes = document.exportProject();
      bytes[bytes.length - 10] ^= 0x5a;
      return bytes;
    } finally {
      document.dispose();
    }
  }

  test('the core saves the intact layers of a damaged file', () {
    final bytes = damaged();
    expect(() => RustDocument.fromProject(bytes), throwsFormatException);
    final rescue = RustDocument.fromDamagedProject(bytes)!;
    try {
      expect(rescue.lostLayerCount, 1);
      expect(rescue.lostImage, isFalse);
      expect(rescue.document.strokes.single.kind, VectorKind.stroke);
      expect(rescue.document.layers, hasLength(2));
    } finally {
      rescue.document.dispose();
    }
    // A file that is not damaged has nothing to rescue.
    final whole = RustDocument();
    try {
      expect(RustDocument.fromDamagedProject(whole.exportProject()), isNull);
    } finally {
      whole.dispose();
    }
  }, skip: !available);

  testWidgets('a file damaged only at its very end opens whole', (
    tester,
  ) async {
    final files = MemoryFiles()..openPath = '/drawings/Fin.edupaint';
    final document = RustDocument();
    final Uint8List bytes;
    try {
      document.addStroke(
        const [DocumentPoint(100, 100), DocumentPoint(300, 200)],
        rgb: 0x112233,
        width: 8,
      );
      bytes = document.exportProject();
    } finally {
      document.dispose();
    }
    // The last byte is the file's CRC: every block is still intact.
    bytes[bytes.length - 1] ^= 0x20;
    final rescue = RustDocument.fromDamagedProject(bytes)!;
    expect((rescue.lostLayerCount, rescue.lostImage), (0, false));
    rescue.document.dispose();
    files.projects[files.openPath!] = bytes;
    final studio = StudioDriver(tester, files: files);
    await studio.start();
    await studio.tap('openProject');
    expect(find.byKey(const Key('rescueDialog')), findsOneWidget);
    expect(find.textContaining('tout le dessin a pu être lu'), findsOneWidget);
    expect(find.text('Ouvrir le dessin'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmRescue')));
    await tester.pumpAndSettle();
    studio.expectCount(1);
    expect(studio.isDirty, isTrue);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('Ouvrir offers what is left of a damaged drawing', (
    tester,
  ) async {
    final files = MemoryFiles()..openPath = '/drawings/Abîmé.edupaint';
    final bytes = damaged();
    files.projects[files.openPath!] = bytes;
    final studio = StudioDriver(tester, files: files);
    await studio.start();
    await studio.tap('openProject');
    expect(find.byKey(const Key('rescueDialog')), findsOneWidget);
    expect(find.textContaining('un calque'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmRescue')));
    await tester.pumpAndSettle();
    studio.expectCount(1);
    // A drawing to save under another name: the damaged file is untouched.
    expect(studio.isDirty, isTrue);
    files.savePath = '/drawings/Sauvé.edupaint';
    await studio.tap('saveProject');
    expect(files.projects['/drawings/Abîmé.edupaint'], bytes);
    final saved = RustDocument.fromProject(
      files.projects['/drawings/Sauvé.edupaint']!,
    );
    try {
      expect(saved.strokes.single.rgb, 0x112233);
    } finally {
      saved.dispose();
    }
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);
}
