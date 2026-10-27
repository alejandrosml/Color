// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  RustDocument scene({bool background = false}) {
    final document = background
        ? RustDocument.fromBackgroundPng(
            File('test/fixtures/raster/rgba-asymmetric.png').readAsBytesSync(),
          )
        : RustDocument(width: 32, height: 24);
    for (final rgb in [0x112233, 0x445566, 0x778899]) {
      document.addShape(
        VectorKind.rectangle,
        const DocumentPoint(2, 3),
        const DocumentPoint(12, 14),
        rgb: rgb,
        width: 2,
        fillRgb: rgb,
      );
    }
    document.moveObject(1, 0.1, 0.2);
    return document;
  }

  for (final background in [false, true]) {
    test(
      'order reuses content and roundtrips v${background ? 3 : 2} projects',
      () {
        final document = scene(background: background);
        try {
          final original = document.strokes;
          final project = document.exportProject();
          final png = document.copyBackgroundPng();
          final info = document.backgroundInfo;
          expect(document.reorderObject(0, 2), isTrue);
          for (var i = 0; i < 3; i++) {
            final previous = original[[1, 2, 0][i]];
            expect(identical(document.strokes[i], previous), isTrue);
            expect(
              identical(document.strokes[i].points, previous.points),
              isTrue,
            );
          }
          expect(original.map((s) => s.rgb), [0x112233, 0x445566, 0x778899]);
          expect(document.copyBackgroundPng(), png);
          expect(identical(document.backgroundInfo, info), isTrue);
          final ordered = document.exportProject();
          expect(ordered[8], background ? 3 : 2);
          final svg = document.exportSvg();
          expect(svg.indexOf('#445566'), lessThan(svg.indexOf('#778899')));
          expect(svg.indexOf('#778899'), lessThan(svg.indexOf('#112233')));
          final reopened = RustDocument.fromProject(ordered);
          try {
            expect(reopened.exportProject(), orderedEquals(ordered));
            expect(reopened.exportSvg(), svg);
            expect(reopened.strokes.map((s) => s.rgb), [
              0x445566,
              0x778899,
              0x112233,
            ]);
          } finally {
            reopened.dispose();
          }
          expect(document.undo(), isTrue);
          expect(document.exportProject(), orderedEquals(project));
          for (var i = 0; i < 3; i++) {
            expect(identical(document.strokes[i], original[i]), isTrue);
          }
          expect(document.redo(), isTrue);
          expect(document.exportProject(), orderedEquals(ordered));
          expect(document.reorderObject(2, 0), isTrue);
          expect(document.exportProject(), orderedEquals(project));
        } finally {
          document.dispose();
        }
      },
      skip: !available,
    );
  }

  test(
    'worker snapshots retain their captured order after edits and disposal',
    () async {
      final document = scene(background: true);
      try {
        final original = document.exportProject();
        final before = document.exportProjectAsync();
        document.reorderObject(0, 2);
        final expectedSvg = document.exportSvg();
        final after = document.exportSvgBytesAsync();
        document.reorderObject(2, 1);
        document.removeObject(0);
        document.dispose();
        expect(await before, orderedEquals(original));
        expect(utf8.decode(await after), expectedSvg);
      } finally {
        document.dispose();
      }
    },
    skip: !available,
  );

  test('no-op and invalid indices preserve snapshots, redo and content', () {
    final empty = RustDocument();
    expect(() => empty.reorderObject(0, 0), throwsRangeError);
    empty.dispose();
    expect(() => empty.reorderObject(0, 0), throwsStateError);
    final document = scene();
    try {
      document.reorderObject(0, 2);
      document.undo();
      final project = document.exportProject();
      final snapshot = document.strokes;
      expect(document.canRedo, isTrue);
      for (final indices in [(-1, 0), (0, -1), (3, 0), (0, 3), (3, 3)]) {
        expect(
          () => document.reorderObject(indices.$1, indices.$2),
          throwsRangeError,
        );
      }
      expect(document.reorderObject(1, 1), isFalse);
      expect(identical(document.strokes, snapshot), isTrue);
      expect(document.exportProject(), orderedEquals(project));
      expect(document.canRedo, isTrue);
      expect(document.redo(), isTrue);
      expect(document.strokes.last.rgb, 0x112233);
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('order interleaves with content edits, deletion and redo branches', () {
    final document = scene();
    try {
      final states = [document.exportProject()];
      final actions = <bool Function()>[
        () => document.reorderObject(0, 2),
        () => document.setObjectStyle(
          0,
          rgb: 0xabcdef,
          width: 3,
          fillRgb: 0x010203,
        ),
        () => document.removeObject(1),
        () => document.reorderObject(1, 0),
        () => document.duplicateObject(1, 2, 2),
        () => document.reorderObject(2, 0),
        () => document.moveObject(1, 0.1, 0.2),
      ];
      for (final action in actions) {
        expect(action(), isTrue);
        states.add(document.exportProject());
      }
      for (final state in states.take(states.length - 1).toList().reversed) {
        expect(document.undo(), isTrue);
        expect(document.exportProject(), orderedEquals(state));
      }
      for (final state in states.skip(1)) {
        expect(document.redo(), isTrue);
        expect(document.exportProject(), orderedEquals(state));
      }
      for (var i = 0; i < 3; i++) {
        expect(document.undo(), isTrue);
      }
      expect(document.count, 2);
      expect(document.reorderObject(0, 1), isTrue);
      expect(document.canRedo, isFalse);
      expect(document.redo(), isFalse);
    } finally {
      document.dispose();
    }
  }, skip: !available);
}
