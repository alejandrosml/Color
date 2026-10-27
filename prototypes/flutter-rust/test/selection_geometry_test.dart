// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'dart:ui';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/selection_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StrokeData shape(
    VectorKind kind, {
    int? fill,
    double width = 2,
    DocumentPoint start = const DocumentPoint(10, 20),
    DocumentPoint end = const DocumentPoint(210, 120),
  }) => StrokeData([start, end], 0x123456, width, kind: kind, fillRgb: fill);

  test('topmost painted element wins; hollow centers pass through', () {
    final back = shape(VectorKind.rectangle, fill: 0xffffff);
    final front = shape(VectorKind.ellipse);
    expect(
      hitTestObjects([back, front], const DocumentPoint(110, 70), scale: 1),
      0,
    );
    expect(
      hitTestObjects([back, front], const DocumentPoint(210, 70), scale: 1),
      1,
    );
    expect(
      hitTestObjects([front], const DocumentPoint(110, 70), scale: 1),
      isNull,
    );
    expect(
      hitTestObjects(
        [shape(VectorKind.rectangle)],
        const DocumentPoint(110, 70),
        scale: 1,
      ),
      isNull,
    );
    expect(
      hitTestObjects(
        [shape(VectorKind.ellipse, fill: 0)],
        const DocumentPoint(110, 70),
        scale: 1,
      ),
      0,
    );
  });

  test('line and freehand distance uses segments and rounded endpoints', () {
    final line = shape(VectorKind.line);
    expect(hitTestObjects([line], const DocumentPoint(110, 70), scale: 1), 0);
    expect(
      hitTestObjects([line], const DocumentPoint(15, 110), scale: 1),
      isNull,
    );
    expect(hitTestObjects([line], const DocumentPoint(5, 20), scale: 1), 0);
    final dot = StrokeData(const [DocumentPoint(10, 10)], 0, 20);
    expect(hitTestObjects([dot], const DocumentPoint(26, 10), scale: 1), 0);
    expect(
      hitTestObjects([dot], const DocumentPoint(28, 10), scale: 1),
      isNull,
    );
    final bent = StrokeData(
      const [
        DocumentPoint(10, 10),
        DocumentPoint(30, 10),
        DocumentPoint(30, 40),
      ],
      0,
      2,
    );
    expect(hitTestObjects([bent], const DocumentPoint(30, 30), scale: 1), 0);
    expect(
      hitTestObjects([bent], const DocumentPoint(10, 35), scale: 1),
      isNull,
    );
  });

  test('same logical screen tolerance at different page scales', () {
    final line = shape(
      VectorKind.line,
      start: const DocumentPoint(0, 50),
      end: const DocumentPoint(300, 50),
    );
    for (final scale in [.25, .5, 1.0, 2.0]) {
      expect(
        hitTestObjects(
          [line],
          DocumentPoint(150, 51 + 6 / scale),
          scale: scale,
        ),
        0,
      );
      expect(
        hitTestObjects(
          [line],
          DocumentPoint(150, 51 + 8 / scale),
          scale: scale,
        ),
        isNull,
      );
    }
  });

  test(
    'ellipse tolerance is geometric even for flat and reversed ellipses',
    () {
      for (final reversed in [false, true]) {
        final oval = shape(
          VectorKind.ellipse,
          start: reversed
              ? const DocumentPoint(410, 40)
              : const DocumentPoint(10, 20),
          end: reversed
              ? const DocumentPoint(10, 20)
              : const DocumentPoint(410, 40),
        );
        for (final angle in [0.0, .05, .4, math.pi / 2, math.pi]) {
          final edge = Offset(
            210 + 200 * math.cos(angle),
            30 + 10 * math.sin(angle),
          );
          final normal = Offset(math.cos(angle) / 200, math.sin(angle) / 10);
          final unit = normal / normal.distance;
          final near = edge + unit * 7;
          final far = edge + unit * 9;
          expect(
            hitTestObjects([oval], DocumentPoint(near.dx, near.dy), scale: 1),
            0,
          );
          expect(
            hitTestObjects([oval], DocumentPoint(far.dx, far.dy), scale: 1),
            isNull,
          );
        }
      }
    },
  );

  test('clamping preserves the full element and handles page edges', () {
    final rectangle = shape(VectorKind.rectangle);
    expect(
      clampObjectMovement(
        rectangle,
        const Offset(-100, 500),
        pageWidth: 300,
        pageHeight: 200,
      ),
      const Offset(-10, 80),
    );
    expect(
      clampObjectMovement(
        rectangle,
        const Offset(500, -100),
        pageWidth: 300,
        pageHeight: 200,
      ),
      const Offset(90, -20),
    );
    expect(
      clampObjectMovement(
        rectangle,
        const Offset(5, 7),
        pageWidth: 300,
        pageHeight: 200,
      ),
      const Offset(5, 7),
    );
    expect(
      objectBounds(rectangle, includeStroke: true),
      const Rect.fromLTRB(9, 19, 211, 121),
    );
  });
}
