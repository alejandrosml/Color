// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:edupaint_flutter_study/document_exports.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

RustDocument _strokeDocument(int points) {
  final document = RustDocument();
  try {
    document.addStroke(
      List.generate(
        points,
        (index) => DocumentPoint(
          10 + (index % 100) * 4.0,
          10 + (index ~/ 100 % 100) * 4.0,
        ),
      ),
      rgb: 0x123456,
      width: 2,
    );
    return document;
  } catch (_) {
    document.dispose();
    rethrow;
  }
}

RustDocument _backgroundDocument() => RustDocument.fromBackgroundPng(
  File('test/fixtures/raster/rgba-asymmetric.png').readAsBytesSync(),
);

void _addRectangle(RustDocument document) => document.addShape(
  VectorKind.rectangle,
  const DocumentPoint(2, 3),
  const DocumentPoint(12, 14),
  rgb: 0x123456,
  width: 2,
  fillRgb: 0xabcdef,
);

Uint8List _expected(RustDocument document, bool svg) => svg
    ? Uint8List.fromList(utf8.encode(document.exportSvg()))
    : document.exportProject();

Future<Uint8List> _prepare(RustDocument document, bool svg) =>
    svg ? prepareSvgBytes(document) : prepareProjectBytes(document);

bool _usesWorker(RustDocument document, bool svg) =>
    svg ? svgExportUsesWorker(document) : projectExportUsesWorker(document);

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  group('native project size and export scheduling', () {
    test('the size bound follows visible edits without changing history', () {
      final document = RustDocument();
      try {
        final empty = document.projectByteLength;
        expect(empty, greaterThanOrEqualTo(document.exportProject().length));
        _addRectangle(document);
        final one = document.projectByteLength;
        expect(one, greaterThan(empty));
        document.duplicateObject(0, 10, 10);
        final two = document.projectByteLength;
        // Each rectangle asks the same room.
        expect(two - one, one - empty);
        document.undo();
        final snapshot = document.strokes;
        final before = document.exportProject();
        for (var index = 0; index < 3; index++) {
          expect(document.projectByteLength, one);
          expect(
            document.projectByteLength,
            greaterThanOrEqualTo(before.length),
          );
          expect(identical(document.strokes, snapshot), isTrue);
          expect(document.canUndo, isTrue);
          expect(document.canRedo, isTrue);
        }
        document.redo();
        expect(document.projectByteLength, two);
        document.moveObject(0, 3, 2);
        document.setObjectStyle(0, rgb: 0xabcdef, width: 4);
        expect(
          document.projectByteLength,
          greaterThanOrEqualTo(document.exportProject().length),
        );
        expect(document.projectByteLength, two);
        document.removeObject(1);
        expect(document.projectByteLength, one);
        document.undo();
        expect(document.projectByteLength, two);
      } finally {
        document.dispose();
      }
    });

    test('the size bound includes the unchanged PNG and visible vectors', () {
      final document = _backgroundDocument();
      try {
        final png = document.backgroundInfo!.byteCount;
        final imageOnly = document.projectByteLength;
        expect(imageOnly, greaterThan(png));
        expect(
          imageOnly,
          greaterThanOrEqualTo(document.exportProject().length),
        );
        _addRectangle(document);
        final withRectangle = document.projectByteLength;
        expect(withRectangle, greaterThan(imageOnly));
        expect(
          withRectangle,
          greaterThanOrEqualTo(document.exportProject().length),
        );
        document.undo();
        expect(document.projectByteLength, imageOnly);
        expect(document.canRedo, isTrue);
        document.redo();
        expect(document.projectByteLength, withRectangle);
      } finally {
        document.dispose();
      }
    });

    // The bound of a stroke grows by the same room for each point: the
    // strokes whose bound is the last one within a budget and the first
    // one beyond it.
    int pointsWithin(int budget) {
      final one = _strokeDocument(1);
      final two = _strokeDocument(2);
      try {
        final base = one.projectByteLength;
        final step = two.projectByteLength - base;
        return 1 + (budget - base) ~/ step;
      } finally {
        one.dispose();
        two.dispose();
      }
    }

    for (final scenario in [
      (
        name: 'project below 256 KiB',
        svg: false,
        budget: 256 * 1024,
        beyond: false,
      ),
      (
        name: 'project above 256 KiB',
        svg: false,
        budget: 256 * 1024,
        beyond: true,
      ),
      (name: 'SVG below 4 KiB', svg: true, budget: 4 * 1024, beyond: false),
      (name: 'SVG above 4 KiB', svg: true, budget: 4 * 1024, beyond: true),
    ]) {
      final worker = scenario.beyond;
      int points() => pointsWithin(scenario.budget) + (scenario.beyond ? 1 : 0);
      test(
        '${scenario.name}: captures exact bytes before edits and disposal',
        () async {
          final document = _strokeDocument(points());
          try {
            expect(
              document.projectByteLength,
              scenario.beyond
                  ? greaterThan(scenario.budget)
                  : lessThanOrEqualTo(scenario.budget),
            );
            expect(
              document.projectByteLength,
              greaterThanOrEqualTo(document.exportProject().length),
            );
            expect(_usesWorker(document, scenario.svg), worker);
            final expected = _expected(document, scenario.svg);
            final pending = _prepare(document, scenario.svg);
            document.moveObject(0, 2, 3);
            document.setObjectStyle(0, rgb: 0xff0000, width: 3);
            document.dispose();
            expect(await pending, orderedEquals(expected));
          } finally {
            document.dispose();
          }
        },
      );

      test(
        '${scenario.name}: actual route respects the worker job limit',
        () async {
          final document = _strokeDocument(points());
          try {
            final expected = _expected(document, scenario.svg);
            // Both jobs are captured synchronously and stay outstanding until
            // this isolate yields. Only the direct route can still prepare now.
            final first = document.exportProjectAsync();
            final second = document.exportProjectAsync();
            final prepared = _prepare(document, scenario.svg);
            if (worker) {
              await expectLater(prepared, throwsStateError);
            } else {
              expect(await prepared, orderedEquals(expected));
            }
            await Future.wait([first, second]);
            expect(
              await _prepare(document, scenario.svg),
              orderedEquals(expected),
            );
          } finally {
            document.dispose();
          }
        },
      );
    }

    for (final svg in [false, true]) {
      test(
        '${svg ? 'SVG' : 'project'} with tiny background always uses worker',
        () async {
          final document = _backgroundDocument();
          try {
            _addRectangle(document);
            expect(document.projectByteLength, lessThan(4 * 1024));
            expect(_usesWorker(document, svg), isTrue);
            final expected = _expected(document, svg);
            final first = document.exportProjectAsync();
            final second = document.exportProjectAsync();
            await expectLater(_prepare(document, svg), throwsStateError);
            await Future.wait([first, second]);
            final prepared = _prepare(document, svg);
            document.removeObject(0);
            document.dispose();
            expect(await prepared, orderedEquals(expected));
          } finally {
            document.dispose();
          }
        },
      );
    }

    test('empty document exports remain exact and independent', () async {
      final document = RustDocument();
      final project = document.exportProject();
      final svg = utf8.encode(document.exportSvg());
      final preparedProject = prepareProjectBytes(document);
      final preparedSvg = prepareSvgBytes(document);
      document.dispose();
      expect(await preparedProject, orderedEquals(project));
      expect(await preparedSvg, orderedEquals(svg));
    });

    test(
      'disposed documents fail without dereferencing a released handle',
      () async {
        final document = RustDocument()..dispose();
        expect(() => document.projectByteLength, throwsStateError);
        expect(() => projectExportUsesWorker(document), throwsStateError);
        expect(() => svgExportUsesWorker(document), throwsStateError);
        await expectLater(prepareProjectBytes(document), throwsStateError);
        await expectLater(prepareSvgBytes(document), throwsStateError);
      },
    );
  }, skip: !available);
}
