// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

// D-01: the points of an element are one block of single-precision
// coordinates, x then y of each point, as the core keeps them.
void main() {
  test(
    'an element keeps its points as they were made, in single precision',
    () {
      final given = [
        const DocumentPoint(0.1, 2.5),
        const DocumentPoint(1e-3, 300.7),
      ];
      final stroke = StrokeData(given, 0, 2);
      given[0] = const DocumentPoint(9, 9);
      given.add(const DocumentPoint(5, 5));
      final single = Float32List.fromList([0.1, 2.5, 1e-3, 300.7]);
      expect(stroke.coordinates, single);
      expect(stroke.points, hasLength(2));
      expect(stroke.points[0].x, single[0]);
      expect(stroke.points[0].y, single[1]);
      expect(stroke.points.last.x, single[2]);
      expect(stroke.points.last.y, single[3]);
      expect(
        [for (final point in stroke.points) (point.x, point.y)],
        [(single[0], single[1]), (single[2], single[3])],
      );
    },
  );

  test('the points of an element cannot be changed through the list', () {
    final stroke = StrokeData(const [DocumentPoint(1, 2)], 0, 2);
    expect(
      () => stroke.points[0] = const DocumentPoint(3, 4),
      throwsUnsupportedError,
    );
    expect(
      () => stroke.points.add(const DocumentPoint(3, 4)),
      throwsUnsupportedError,
    );
    expect(() => stroke.points.length = 0, throwsUnsupportedError);
    expect(() => stroke.points.clear(), throwsUnsupportedError);
    expect(() => stroke.points.removeLast(), throwsUnsupportedError);
    expect(() => stroke.points[1], throwsRangeError);
    expect(() => stroke.points[-1], throwsRangeError);
    expect(stroke.points.single.x, 1);
  });

  test('points already kept are shared, not copied again', () {
    final stroke = StrokeData(
      const [DocumentPoint(1, 2), DocumentPoint(3, 4)],
      0,
      2,
    );
    final again = StrokeData(stroke.points, 0xff0000, 8);
    expect(identical(again.points, stroke.points), isTrue);
    expect(identical(again.coordinates, stroke.coordinates), isTrue);
  });

  test('adopted coordinates go by two', () {
    expect(() => DocumentPoints.adopt(Float32List(3)), throwsArgumentError);
    final points = DocumentPoints.adopt(Float32List.fromList([1, 2, 3, 4]));
    expect(points, hasLength(2));
    expect(points[1].x, 3);
    expect(points[1].y, 4);
    expect(DocumentPoints.adopt(Float32List(0)), isEmpty);
  });

  test(
    'a coordinate beyond single precision is refused like an infinite one',
    () {
      // The core keeps single precision: such a point could never be saved.
      for (final point in [
        const DocumentPoint(1e300, 0),
        const DocumentPoint(0, -1e300),
      ]) {
        expect(
          () => RenderedElement(StrokeData([point], 0, 2)),
          throwsArgumentError,
        );
      }
    },
  );
}
