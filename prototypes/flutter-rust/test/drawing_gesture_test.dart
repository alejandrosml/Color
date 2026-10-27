// SPDX-License-Identifier: MIT
import 'package:edupaint_flutter_study/drawing_gesture.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('constrained line keeps its angle when clipped at a document edge', () {
    final end = shapeEnd(
      const DocumentPoint(95, 50),
      const DocumentPoint(100, 57),
      kind: VectorKind.line,
      constrain: true,
      documentWidth: 100,
      documentHeight: 100,
    );
    expect(end.x, closeTo(100, 1e-9));
    expect(end.y, closeTo(55, 1e-9));
  });

  test('backwards square remains square at the top edge', () {
    final end = shapeEnd(
      const DocumentPoint(70, 20),
      const DocumentPoint(10, 5),
      kind: VectorKind.rectangle,
      constrain: true,
      documentWidth: 100,
      documentHeight: 100,
    );
    expect(end.x, 50);
    expect(end.y, 0);
  });

  test(
    'clicks and flat rectangles are ignored, but a horizontal line is usable',
    () {
      const start = DocumentPoint(10, 20);
      expect(isUsableShape(VectorKind.line, start, start), isFalse);
      expect(
        isUsableShape(VectorKind.rectangle, start, const DocumentPoint(30, 20)),
        isFalse,
      );
      expect(
        isUsableShape(VectorKind.ellipse, start, const DocumentPoint(10, 60)),
        isFalse,
      );
      expect(
        isUsableShape(VectorKind.line, start, const DocumentPoint(30, 20)),
        isTrue,
      );
    },
  );
}
