// SPDX-License-Identifier: MIT
import 'dart:typed_data';
import 'dart:ui';

import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/selection_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// The same object whose points change, as a subclass may do: the general
/// path (no prepared bounds) must follow it. Counts the reads of its
/// coordinates, which every loop over the points makes once.
class _ChangingStroke extends StrokeData {
  _ChangingStroke(List<DocumentPoint> value, {super.kind = VectorKind.line})
    : current = DocumentPoints.of(value),
      super(value, 0, 2);
  DocumentPoints current;
  int coordinateReads = 0;
  set geometry(List<DocumentPoint> value) => current = DocumentPoints.of(value);
  @override
  DocumentPoints get points => current;
  @override
  Float32List get coordinates {
    coordinateReads++;
    return current.coordinates;
  }
}

void main() {
  final examples = <StrokeData>[
    StrokeData(const [DocumentPoint(40, 50)], 0, 20),
    StrokeData(
      const [
        DocumentPoint(10, 10),
        DocumentPoint(80, 20),
        DocumentPoint(30, 90),
      ],
      0,
      4,
    ),
    for (final kind in [
      VectorKind.line,
      VectorKind.rectangle,
      VectorKind.ellipse,
    ])
      StrokeData(
        const [DocumentPoint(210, 120), DocumentPoint(10, 20)],
        0,
        12,
        kind: kind,
      ),
    StrokeData(
      const [DocumentPoint(20, 40), DocumentPoint(200, 80)],
      0,
      2,
      kind: VectorKind.rectangle,
      fillRgb: 0xffffff,
    ),
    StrokeData(
      const [DocumentPoint(10, 20), DocumentPoint(410, 40)],
      0,
      2,
      kind: VectorKind.ellipse,
      fillRgb: 0xffffff,
    ),
  ];

  test('prepared bounds retain control geometry without stroke inflation', () {
    for (final object in examples) {
      final prepared = RenderedElement(object);
      expect(prepared.controlBounds, objectBounds(object));
      expect(
        prepared.controlBounds.inflate(object.width / 2),
        objectBounds(object, includeStroke: true),
      );
      for (final movement in [
        const Offset(-1000, 1000),
        const Offset(5, 7),
        const Offset(1000, -1000),
      ]) {
        expect(
          clampBoundsMovement(
            prepared.controlBounds,
            movement,
            pageWidth: 1200,
            pageHeight: 800,
          ),
          clampObjectMovement(
            object,
            movement,
            pageWidth: 1200,
            pageHeight: 800,
          ),
        );
      }
    }
    // A painted single-point stroke is a disc, but its control bounds are a point.
    expect(
      RenderedElement(examples.first).controlBounds,
      const Rect.fromLTRB(40, 50, 40, 50),
    );
  });

  test(
    'prepared and fresh hit tests agree across kinds, order and screen scales',
    () {
      for (final objects in [examples, examples.reversed.toList()]) {
        final rendered = objects.map(RenderedElement.new).toList();
        for (final scale in [.25, .5, 1.0, 2.0, 4.0]) {
          for (final tolerance in [0.0, 7.0]) {
            for (final x in [
              -20.0,
              10.0,
              30.0,
              40.0,
              80.0,
              110.0,
              200.0,
              210.0,
              410.0,
              450.0,
            ]) {
              for (final y in [
                0.0,
                10.0,
                20.0,
                30.0,
                40.0,
                50.0,
                70.0,
                90.0,
                120.0,
                160.0,
              ]) {
                final point = DocumentPoint(x, y);
                final expected = hitTestObjects(
                  objects,
                  point,
                  scale: scale,
                  tolerancePixels: tolerance,
                );
                expect(
                  hitTestObjects(
                    objects,
                    point,
                    scale: scale,
                    tolerancePixels: tolerance,
                    preparedBounds: (index, object) {
                      expect(identical(rendered[index].data, object), isTrue);
                      return rendered[index].controlBounds;
                    },
                  ),
                  expected,
                  reason: 'scale=$scale tolerance=$tolerance point=($x,$y)',
                );
              }
            }
          }
        }
      }
    },
  );

  test('preparation reads the points once and repeated misses not at all', () {
    final object = _ChangingStroke(
      List.generate(
        512,
        (i) => DocumentPoint(i.toDouble(), (i % 10).toDouble()),
      ),
      kind: VectorKind.stroke,
    );
    final prepared = RenderedElement(object);
    // Validation, bounds and path read the same coordinates.
    expect(object.coordinateReads, 1);
    object.coordinateReads = 0;
    for (var click = 0; click < 8; click++) {
      expect(
        hitTestObjects(
          [object],
          const DocumentPoint(2000, 2000),
          scale: 1,
          preparedBounds: (index, data) => prepared.controlBounds,
        ),
        isNull,
      );
      clampBoundsMovement(
        prepared.controlBounds,
        const Offset(5, 7),
        pageWidth: 1200,
        pageHeight: 800,
      );
    }
    expect(object.coordinateReads, 0);
    expect(
      hitTestObjects([object], const DocumentPoint(2000, 2000), scale: 1),
      isNull,
    );
    expect(object.coordinateReads, greaterThanOrEqualTo(1));
  });

  test(
    'general path and null provider stay fresh for same-identity subclasses',
    () {
      final dot = _ChangingStroke(const [
        DocumentPoint(10, 10),
      ], kind: VectorKind.stroke);
      final old = RenderedElement(dot);
      dot.geometry = const [DocumentPoint(100, 100)];
      expect(old.controlBounds, const Rect.fromLTRB(10, 10, 10, 10));
      expect(objectBounds(dot), const Rect.fromLTRB(100, 100, 100, 100));
      expect(hitTestObjects([dot], const DocumentPoint(100, 100), scale: 1), 0);
      expect(
        hitTestObjects([dot], const DocumentPoint(10, 10), scale: 1),
        isNull,
      );
      final line = _ChangingStroke(const [
        DocumentPoint(10, 20),
        DocumentPoint(20, 20),
      ]);
      final observed = RenderedElement(line);
      line.geometry = const [DocumentPoint(100, 100), DocumentPoint(200, 100)];
      expect(observed.controlBounds, const Rect.fromLTRB(10, 20, 20, 20));
      expect(
        hitTestObjects(
          [line],
          const DocumentPoint(150, 100),
          scale: 1,
          preparedBounds: (index, object) => null,
        ),
        0,
      );
      expect(
        hitTestObjects([line], const DocumentPoint(15, 20), scale: 1),
        isNull,
      );
      expect(
        clampObjectMovement(
          line,
          const Offset(-200, 500),
          pageWidth: 300,
          pageHeight: 200,
        ),
        const Offset(-100, 100),
      );
    },
  );

  test('invalid point coordinates are still rejected during preparation', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      for (final point in [DocumentPoint(value, 0), DocumentPoint(0, value)]) {
        expect(
          () => RenderedElement(StrokeData([point], 0, 2)),
          throwsArgumentError,
        );
      }
    }
    expect(() => RenderedElement(StrokeData([], 0, 2)), throwsArgumentError);
  });
}
