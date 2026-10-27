// SPDX-License-Identifier: MIT
// The closed contour, object kind 6: the zones and the lines of a colouring
// page. Painted by the real engine and hit as the studio hits it; the
// elements are given by hand, no Rust library is needed.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/replay.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/selection_geometry.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _ink = 0x112233;
const _green = 0x00cc44;
const _white = 0xffffff;

StrokeData _contour(
  List<(double, double)> points, {
  int rgb = _ink,
  double width = 6,
  int? fillRgb,
  int layer = 0,
}) => StrokeData(
  [for (final (x, y) in points) DocumentPoint(x, y)],
  rgb,
  width,
  kind: VectorKind.contour,
  fillRgb: fillRgb,
  layer: layer,
);

/// A triangle whose last side, from its third point back to the first, is
/// the side that the contour closes by itself.
StrokeData _triangle({int? fillRgb}) =>
    _contour(const [(20, 20), (180, 20), (100, 160)], fillRgb: fillRgb);

/// A five-pointed star drawn in one go: its sides cross, and its middle is
/// gone round twice. The nonzero rule fills it; the even-odd rule would not.
StrokeData _star({int? fillRgb, double width = 2}) => _contour(
  [
    for (var point = 0; point < 5; point++)
      (
        100 + 80 * math.cos(-math.pi / 2 + point * 4 * math.pi / 5),
        100 + 80 * math.sin(-math.pi / 2 + point * 4 * math.pi / 5),
      ),
  ],
  fillRgb: fillRgb,
  width: width,
);

/// The pixels of [paint] on a white square of 200 by 200.
Future<_Pixels> _paint(
  WidgetTester tester,
  void Function(Canvas canvas) paint,
) async => (await tester.runAsync(() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xffffffff), BlendMode.src);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 200);
  picture.dispose();
  try {
    final bytes = (await image.toByteData())!;
    return _Pixels(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}))!;

class _Pixels {
  _Pixels(this.rgba);
  final Uint8List rgba;

  int at(int x, int y) {
    final offset = (y * 200 + x) * 4;
    return (rgba[offset] << 16) | (rgba[offset + 1] << 8) | rgba[offset + 2];
  }

  int differences(_Pixels other) {
    var count = 0;
    for (var offset = 0; offset < rgba.length; offset++) {
      if (rgba[offset] != other.rgba[offset]) count++;
    }
    return count;
  }
}

void main() {
  test('the contour is kind 6, and may have an inside like a shape', () {
    expect(VectorKind.contour.index, 6);
    expect(VectorKind.values, hasLength(7));
    expect(VectorKind.contour.isBoxObject, isFalse);
    expect(
      [
        for (final kind in VectorKind.values)
          if (kind.canFill) kind,
      ],
      [VectorKind.rectangle, VectorKind.ellipse, VectorKind.contour],
    );
    final triangle = _triangle(fillRgb: _green);
    expect(triangle.outlineRadius, 3);
    expect(objectBounds(triangle), const Rect.fromLTRB(20, 20, 180, 160));
    expect(
      objectBounds(triangle, includeStroke: true),
      const Rect.fromLTRB(17, 17, 183, 163),
    );
    expect(RenderedElement(triangle).controlBounds, objectBounds(triangle));
  });

  testWidgets('a contour is painted closed, its inside under its outline', (
    tester,
  ) async {
    final filled = await _paint(
      tester,
      RenderedElement(_triangle(fillRgb: _green)).paint,
    );
    expect(filled.at(100, 70), _green);
    // Its three sides, the closing one too: from (100, 160) back to (20, 20).
    expect(filled.at(100, 20), _ink);
    expect(filled.at(140, 90), _ink);
    expect(filled.at(60, 90), _ink);
    // Outside it the sheet is untouched.
    expect(filled.at(20, 150), _white);
    expect(filled.at(180, 150), _white);
    // A corner is round, where a mitred join would end in a point.
    expect(filled.at(19, 18), _ink);
    expect(filled.at(16, 17), _white);

    final hollow = await _paint(tester, RenderedElement(_triangle()).paint);
    expect(hollow.at(100, 70), _white);
    expect(hollow.at(60, 90), _ink);
  });

  testWidgets('the inside of a crossing contour follows the nonzero rule', (
    tester,
  ) async {
    final star = await _paint(
      tester,
      RenderedElement(_star(fillRgb: _green)).paint,
    );
    // The middle, gone round twice, is inside; so is a point of the star.
    expect(star.at(100, 100), _green);
    expect(star.at(100, 35), _green);
    // Between two points of the star, the sheet.
    expect(star.at(100, 175), _white);
  });

  testWidgets(
    'the film draws its outline from its first point, then its inside',
    (tester) async {
      final element = RenderedElement(_triangle(fillRgb: _green));
      final nothing = await _paint(
        tester,
        (canvas) => element.paintProgress(canvas, 0),
      );
      expect(nothing.at(100, 20), _white);
      // A third of the way: the first side is there, the inside is not.
      final started = await _paint(
        tester,
        (canvas) => element.paintProgress(canvas, .3),
      );
      expect(started.at(60, 20), _ink);
      expect(started.at(100, 70), _white);
      expect(started.at(60, 90), _white, reason: 'the closing side comes last');
      final whole = await _paint(
        tester,
        (canvas) => element.paintProgress(canvas, 1),
      );
      final painted = await _paint(tester, element.paint);
      expect(whole.differences(painted), 0);
      expect(whole.at(100, 70), _green);
      // As long as a rectangle or an oval.
      expect(
        ReplayPlan.naturalDuration(_triangle(), sheetDiagonal: 1000),
        ReplayPlan.shape,
      );
    },
  );

  testWidgets('a zone takes its colour from its middle to its edges', (
    tester,
  ) async {
    const cream = 0xfff4d6;
    // On a cream sheet, so that the white of the zone shows.
    Future<_Pixels> onCream(void Function(Canvas canvas) paint) =>
        _paint(tester, (canvas) {
          canvas.drawColor(const Color(0xff000000 | cream), BlendMode.src);
          paint(canvas);
        });
    final zone = RenderedElement(_triangle(fillRgb: _green));
    Future<_Pixels> at(double progress) => onCream(
      (canvas) => zone.paintRecolouring(canvas, progress, fromRgb: _white),
    );

    // At first the white zone of the page, as it was before the pot.
    final white = await onCream(
      RenderedElement(_triangle(fillRgb: _white)).paint,
    );
    expect(white.at(100, 75), _white);
    expect((await at(0)).differences(white), 0);
    expect((await at(double.nan)).differences(white), 0);
    // A quarter of the way: the colour fills the middle, not the corners.
    final quarter = await at(.25);
    expect(quarter.at(100, 75), _green);
    expect(quarter.at(35, 28), _white);
    expect(quarter.at(60, 90), _ink, reason: 'the outline stays in front');
    expect(quarter.at(20, 150), cream, reason: 'nothing outside the zone');
    expect((await at(.75)).at(35, 28), _green);
    // At the end, exactly the coloured zone.
    final coloured = await onCream(zone.paint);
    expect((await at(1)).differences(coloured), 0);
    expect(coloured.at(100, 75), _green);

    // A trait has no inside to colour: it is painted whole.
    final trait = RenderedElement(
      StrokeData(
        const [DocumentPoint(20, 100), DocumentPoint(180, 100)],
        _ink,
        6,
      ),
    );
    final whole = await onCream(
      (canvas) => trait.paintRecolouring(canvas, 0, fromRgb: _white),
    );
    expect(whole.differences(await onCream(trait.paint)), 0);
    expect(whole.at(100, 100), _ink);
  });

  test('a contour needs three points and a box of some width and height', () {
    for (final invalid in [
      _contour(const [(10, 10), (90, 60)]),
      // Three points on one line: a box of no height, or of no width.
      _contour(const [(10, 10), (50, 10), (90, 10)]),
      _contour(const [(10, 10), (10, 50), (10, 90)]),
      StrokeData(
        const [
          DocumentPoint(10, 10),
          DocumentPoint(90, 10),
          DocumentPoint(50, 60),
        ],
        0,
        2,
        kind: VectorKind.contour,
        text: 'non',
      ),
      StrokeData(
        const [
          DocumentPoint(10, 10),
          DocumentPoint(90, 10),
          DocumentPoint(50, 60),
        ],
        0,
        2,
        kind: VectorKind.contour,
        stamp: 0,
      ),
      _contour(const [(10, 10), (90, 10), (50, 60)], width: 0),
      _contour(const [(10, 10), (90, 10), (50, 60)], fillRgb: 0x1000000),
    ]) {
      expect(() => RenderedElement(invalid), throwsArgumentError);
    }
  });

  test(
    '« Choisir » and the eraser catch a contour by its inside or its outline',
    () {
      final filled = _triangle(fillRgb: _green);
      final hollow = _triangle();
      int? hit(StrokeData object, double x, double y, {bool inside = false}) =>
          hitTestObjects(
            [object],
            DocumentPoint(x, y),
            scale: 1,
            insideShapes: inside,
          );
      expect(hit(filled, 100, 70), 0);
      expect(hit(hollow, 100, 70), isNull);
      // On each side, the closing one too, and just beside them.
      for (final (x, y) in const [(100.0, 20.0), (140.0, 90.0), (60.0, 90.0)]) {
        expect(hit(hollow, x, y), 0, reason: '($x, $y)');
      }
      expect(hit(hollow, 52, 94), 0, reason: 'beside the closing side');
      expect(hit(hollow, 40, 110), isNull, reason: 'far from every side');
      expect(hit(filled, 20, 150), isNull);
      // The paint pot pours into what a hollow contour encloses.
      expect(hit(hollow, 100, 70, inside: true), 0);
      expect(hit(hollow, 20, 150, inside: true), isNull);
      // A crossing contour: the nonzero rule here too.
      expect(hit(_star(fillRgb: _green), 100, 100), 0);
      expect(hit(_star(), 100, 100), isNull);
      expect(hit(_star(), 100, 100, inside: true), 0);
      expect(hit(_star(fillRgb: _green), 100, 175), isNull);
    },
  );

  test('the pot fills the smallest contour around the pointer, in front of a filled one', () {
    final sky = _contour(const [
      (0, 0),
      (200, 0),
      (200, 200),
      (0, 200),
    ], fillRgb: 0xa8d8f0);
    final sun = _contour(const [(60, 60), (140, 60), (140, 140), (60, 140)]);
    final objects = [sky, sun];
    expect(
      hitTestObjects(
        objects,
        const DocumentPoint(100, 100),
        scale: 1,
        insideShapes: true,
      ),
      1,
    );
    // Outside the sun, the sky.
    expect(
      hitTestObjects(
        objects,
        const DocumentPoint(20, 100),
        scale: 1,
        insideShapes: true,
      ),
      0,
    );
    // What the paint order leaves out is not there for the pointer: the
    // sun out of reach, the sky under it answers.
    expect(
      hitTestObjects(
        objects,
        const DocumentPoint(100, 100),
        scale: 1,
        insideShapes: true,
        paintOrder: const [0],
      ),
      0,
    );
    expect(
      hitTestObjects(
        objects,
        const DocumentPoint(60, 100),
        scale: 1,
        paintOrder: const [0],
      ),
      0,
    );
  });

  test('the pipette reads the inside of a contour, or its outline', () {
    final triangle = _triangle(fillRgb: _green);
    expect(
      colourOfObjectAt(triangle, const DocumentPoint(100, 70), scale: 1),
      _green,
    );
    expect(
      colourOfObjectAt(triangle, const DocumentPoint(60, 90), scale: 1),
      _ink,
    );
    expect(
      colourOfObjectAt(_triangle(), const DocumentPoint(60, 90), scale: 1),
      _ink,
    );
  });
}
