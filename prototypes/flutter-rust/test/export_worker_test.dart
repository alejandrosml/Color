// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:edupaint_flutter_study/rust_document.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  RustDocument scene({bool background = false}) {
    final document = background
        ? RustDocument.fromBackgroundPng(
            File('test/fixtures/raster/rgba-asymmetric.png').readAsBytesSync(),
          )
        : RustDocument(width: 32, height: 24);
    document.addShape(
      VectorKind.rectangle,
      const DocumentPoint(2, 3),
      const DocumentPoint(12, 14),
      rgb: 0x123456,
      width: 2,
      fillRgb: 0xabcdef,
    );
    document.moveObject(0, 3, 2);
    document.setObjectStyle(0, rgb: 0xff0000, width: 3, fillRgb: 0xffee00);
    return document;
  }

  for (final background in [false, true]) {
    test(
      'worker exports exactly match synchronous v${background ? 3 : 2} exports',
      () async {
        final document = scene(background: background);
        try {
          final project = document.exportProject();
          final svg = document.exportSvg();
          final asynchronous = await document.exportProjectAsync();
          expect(asynchronous, orderedEquals(project));
          expect(utf8.decode(await document.exportSvgBytesAsync()), svg);
          final reopened = RustDocument.fromProject(asynchronous);
          try {
            expect(reopened.exportProject(), orderedEquals(project));
            expect(reopened.exportSvg(), svg);
            expect(reopened.copyBackgroundPng(), document.copyBackgroundPng());
          } finally {
            reopened.dispose();
          }
        } finally {
          document.dispose();
        }
      },
      skip: !available,
    );
  }

  test('two worker snapshots survive mutation and disposal of their source document', () async {
    final document = scene(background: true);
    final expectedProject = document.exportProject();
    final expectedSvg = document.exportSvg();
    final project = document.exportProjectAsync();
    final svg = document.exportSvgBytesAsync();
    document.duplicateObject(0, 2, 1);
    document.undo();
    document.removeObject(0);
    document.dispose();
    expect(await project, orderedEquals(expectedProject));
    expect(utf8.decode(await svg), expectedSvg);
  }, skip: !available);

  test('each captured revision is independent of subsequent edits', () async {
    final document = scene(background: true);
    try {
      final firstExpected = document.exportProject();
      final first = document.exportProjectAsync();
      document.duplicateObject(0, 2, 1);
      final secondExpected = document.exportProject();
      final second = document.exportProjectAsync();
      document.undo();
      expect(await first, orderedEquals(firstExpected));
      expect(await second, orderedEquals(secondExpected));
      expect(document.count, 1);
      expect(document.canRedo, isTrue);
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test(
    'outstanding exports are bounded and completed slots can be reused',
    () async {
      final document = scene(background: true);
      try {
        final first = document.exportProjectAsync();
        final second = document.exportSvgBytesAsync();
        await expectLater(document.exportProjectAsync(), throwsStateError);
        await first;
        await second;
        expect(
          await document.exportProjectAsync(),
          orderedEquals(document.exportProject()),
        );
      } finally {
        document.dispose();
      }
    },
    skip: !available,
  );

  test('export after disposal fails without starting a worker', () async {
    final document = scene();
    document.dispose();
    await expectLater(document.exportProjectAsync(), throwsStateError);
    await expectLater(document.exportSvgBytesAsync(), throwsStateError);
  }, skip: !available);
}
