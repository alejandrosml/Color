// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/selection_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('only changed content is copied; detached snapshots survive edits and disposal', () {
    final document = RustDocument();
    try {
      document.addStroke(
        const [DocumentPoint(10, 10), DocumentPoint(20, 30)],
        rgb: 0,
        width: 2,
      );
      final first = document.strokes.single;
      document.addShape(
        VectorKind.rectangle,
        const DocumentPoint(100, 100),
        const DocumentPoint(300, 200),
        rgb: 0x123456,
        width: 4,
      );
      expect(identical(document.strokes.first, first), isTrue);
      final rectangle = document.strokes.last;
      document.moveObject(1, 20, 30);
      expect(identical(document.strokes.first, first), isTrue);
      expect(identical(document.strokes.last, rectangle), isFalse);
      expect(
        rectangle.points.first.x,
        100,
        reason: 'Previously returned data is immutable.',
      );
      document.undo();
      expect(document.strokes.last.points.first.x, 100);
      expect(identical(document.strokes.first, first), isTrue);
      final beforeNoop = document.strokes;
      expect(document.moveObject(1, 0, 0), isFalse);
      expect(identical(document.strokes, beforeNoop), isTrue);
      expect(document.canRedo, isTrue);
      document.removeObject(0);
      final retained = document.strokes.single;
      expect(retained.kind, VectorKind.rectangle);
      document.undo();
      expect(
        identical(document.strokes.last, retained),
        isTrue,
        reason: 'Index shifts do not recopy unchanged content.',
      );
      expect(document.strokes.first.points.last.y, 30);
      document.setObjectStyle(1, rgb: 0xabcdef, width: 8, fillRgb: 0x998877);
      expect(retained.rgb, 0x123456);
      final editedSvg = document.exportSvg();
      final loaded = RustDocument.fromProject(document.exportProject());
      try {
        expect(loaded.exportSvg(), editedSvg);
      } finally {
        loaded.dispose();
      }
      document.dispose();
      expect(first.points.last.y, 30);
      expect(retained.points.first.x, 100);
      expect(
        () => first.points.add(const DocumentPoint(1, 1)),
        throwsUnsupportedError,
      );
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('native clamping handles hidden fractional transforms without weakening strict mutations', () {
    final document = RustDocument();
    try {
      document.addShape(
        VectorKind.rectangle,
        const DocumentPoint(400, 250),
        const DocumentPoint(650, 500),
        rgb: 0x123456,
        width: 12,
      );
      document.moveObject(0, 538.7, 288.7);
      final original = document.exportSvg();
      final delta = clampObjectMovement(
        document.strokes.single,
        const Offset(24, 24),
        pageWidth: 1200,
        pageHeight: 800,
      );
      expect(
        () => document.duplicateObject(0, delta.dx, delta.dy),
        throwsA(isA<RustCoreException>()),
      );
      expect(document.exportSvg(), original);
      expect(
        document.duplicateObject(0, delta.dx, delta.dy, constrain: true),
        isTrue,
      );
      final duplicate = document.exportSvg();
      expect(document.strokes.last.points.last.x, closeTo(1200, .001));
      expect(document.strokes.last.points.last.y, closeTo(800, .001));
      expect(document.undo(), isTrue);
      expect(document.exportSvg(), original);
      expect(document.redo(), isTrue);
      expect(document.exportSvg(), duplicate);

      // Exercise all edges repeatedly after non-binary fractional transforms.
      for (final requested in [
        const Offset(-2000.3, -2000.7),
        const Offset(2000.1, -2000.9),
        const Offset(2000.7, 2000.3),
        const Offset(-2000.9, 2000.1),
      ]) {
        expect(
          document.moveObject(1, requested.dx, requested.dy, constrain: true),
          isTrue,
        );
        for (final point in document.strokes.last.points) {
          expect(point.x, inInclusiveRange(0, 1200));
          expect(point.y, inInclusiveRange(0, 800));
        }
        final loaded = RustDocument.fromProject(document.exportProject());
        try {
          expect(loaded.exportSvg(), document.exportSvg());
        } finally {
          loaded.dispose();
        }
      }
    } finally {
      document.dispose();
    }
  }, skip: !available);
}
