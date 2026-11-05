// SPDX-License-Identifier: MIT
// What Color 1.1 adds to the objects, through the functions of the core:
// turn and mirror, tools and their marks, pressures, gradients, fonts, holes,
// the eraser that cuts, the paint pot that closes small gaps, the new shapes
// and the magnet shapes; all kept by version 6.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

List<DocumentPoint> wave(int count) => [
  for (var i = 0; i < count; i++)
    DocumentPoint(100 + i * 6.0, 300 + 40 * math.sin(i / 8)),
];

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('an object keeps its turn, mirror, tool, seed and pressures', () {
    final document = RustDocument();
    try {
      final points = wave(40);
      document.addObject(
        VectorKind.stroke,
        points,
        rgb: 0x336699,
        width: 12,
        look: const ObjectLook(
          rotation: .5,
          mirrorX: true,
          tool: BrushTool.chalk,
          seed: 77,
        ),
        pressures: Uint8List.fromList([
          for (var i = 0; i < 40; i++) 40 + i * 5,
        ]),
      );
      final stroke = document.strokes.single;
      expect(stroke.look.rotation, closeTo(.5, 1e-6));
      expect(stroke.look.mirrorX, isTrue);
      expect(stroke.look.mirrorY, isFalse);
      expect(stroke.look.tool, BrushTool.chalk);
      expect(stroke.look.seed, 77);
      expect(stroke.pressures, hasLength(40));
      expect(stroke.pressures!.first, 40);
      // Chalk is painted as the grains the core scatters, always the same.
      expect(stroke.marks.isEmpty, isFalse);
      final again = RustDocument.strokeMarks(
        points,
        pressures: stroke.pressures,
        width: 12,
        rgb: 0x336699,
        tool: BrushTool.chalk,
        seed: 77,
      )!;
      expect(again.points, stroke.marks.points);
      // A round stroke without pressures is painted as a line, as in 1.0.
      expect(
        RustDocument.strokeMarks(
          points,
          width: 12,
          rgb: 0,
          tool: BrushTool.round,
        ),
        isNull,
      );
      // Version 6 keeps everything.
      final bytes = document.exportProject();
      expect(bytes[8], 6);
      expect(document.exportLegacyProject(), isNull);
      final reopened = RustDocument.fromProject(bytes);
      try {
        final kept = reopened.strokes.single;
        expect(kept.look, stroke.look);
        expect(kept.pressures, stroke.pressures);
        expect(kept.marks.points, stroke.marks.points);
        expect(reopened.exportProject(), bytes);
      } finally {
        reopened.dispose();
      }
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('a gradient is painted through Oklab, and undone in one step', () {
    final document = RustDocument();
    try {
      document.addShape(
        VectorKind.rectangle,
        const DocumentPoint(100, 100),
        const DocumentPoint(300, 200),
        rgb: 0x112233,
        width: 4,
        fillRgb: 0xff0000,
      );
      final look = ObjectLook.plain.withGradient(
        GradientKind.linear,
        rgb: 0x0000ff,
        points: const [0, 0, 1, 0],
      );
      expect(document.setObjectPaint(0, fillRgb: 0xff0000, look: look), isTrue);
      expect(document.strokes.single.look.gradient, GradientKind.linear);
      expect(document.strokes.single.look.gradientRgb, 0x0000ff);
      expect(document.exportSvg(), contains('linearGradient'));
      // The same paint again changes nothing.
      expect(
        document.setObjectPaint(0, fillRgb: 0xff0000, look: look),
        isFalse,
      );
      expect(document.undo(), isTrue);
      expect(document.strokes.single.look.hasGradient, isFalse);
      final stops = RustDocument.gradientColours(0xff0000, 0x0000ff, 9);
      expect(stops, hasLength(9));
      expect(stops.first, 0xff0000);
      expect(stops.last, 0x0000ff);
      // Its middle is Oklab's, not the dull grey of a mix of the numbers.
      expect(stops[4], 0x8c53a2);
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('blue and yellow mixed as paint give green', () {
    final green = RustDocument.mixColours(0x0000ff, 0xffff00, .5);
    final (r, g, b) = (green >> 16, (green >> 8) & 0xff, green & 0xff);
    expect(g, greaterThan(r));
    expect(g, greaterThan(b));
    expect(RustDocument.mixColours(0x0000ff, 0xffff00, 0), 0x0000ff);
    expect(RustDocument.mixColours(0x0000ff, 0xffff00, 1), 0xffff00);
  }, skip: !available);

  test('a text keeps its font, and a box of its font', () {
    final document = RustDocument();
    try {
      document.addText(
        const DocumentPoint(10, 10),
        const DocumentPoint(200, 70),
        text: 'Bonjour',
        rgb: 0x123456,
        size: 50,
        font: 4,
      );
      expect(document.strokes.single.font, 4);
      expect(document.exportSvg(), contains('Playwrite FR Trad'));
      final reopened = RustDocument.fromProject(document.exportProject());
      try {
        expect(reopened.strokes.single.font, 4);
      } finally {
        reopened.dispose();
      }
      expect(
        () => document.addText(
          const DocumentPoint(10, 10),
          const DocumentPoint(200, 70),
          text: 'Non',
          rgb: 0,
          size: 50,
          font: textFontCount,
        ),
        throwsArgumentError,
      );
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('the eraser cuts a stroke in two, and one undo brings it back', () {
    final document = RustDocument();
    try {
      document.addStroke(
        [for (var i = 0; i <= 10; i++) DocumentPoint(100 + 20.0 * i, 100)],
        rgb: 0x112233,
        width: 3,
      );
      expect(
        document.erase(
          const [DocumentPoint(200, 50), DocumentPoint(200, 150)],
          9,
          cut: const [0],
        ),
        1,
      );
      expect(document.count, 2);
      expect(
        document.erase(const [DocumentPoint(600, 600)], 9, cut: const [0, 1]),
        0,
      );
      expect(document.undo(), isTrue);
      expect(document.count, 1);
      expect(document.strokes.single.points, hasLength(11));
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('the paint pot finds the zone a line closes, gaps plugged', () {
    const w = 120, h = 100;
    final mask = Uint8List(w * h);
    void ink(int x0, int y0, int x1, int y1) {
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          mask[y * w + x] = 255;
        }
      }
    }

    // A square with a gap of 4 pixels in its right side.
    ink(20, 20, 80, 22);
    ink(20, 78, 80, 80);
    ink(20, 20, 22, 80);
    ink(78, 20, 80, 47);
    ink(78, 52, 80, 80);
    final inside = RustDocument.fillZone(mask, w, h, 50, 50, 4);
    expect(inside.rings, hasLength(1));
    // Every point of its outline inside the square, a pixel under the line.
    for (final point in inside.points!) {
      expect(point.x, inInclusiveRange(20, 81));
      expect(point.y, inInclusiveRange(20, 81));
    }
    // Without closing gaps, the paint runs out: the whole sheet.
    expect(RustDocument.fillZone(mask, w, h, 50, 50, 0).wholeSheet, isTrue);
    expect(RustDocument.fillZone(mask, w, h, 21, 21, 4).onInk, isTrue);
    // Outside, the sheet with the square as a hole.
    expect(RustDocument.fillZone(mask, w, h, 5, 5, 4).rings, hasLength(2));
    expect(
      () => RustDocument.fillZone(mask, w, h - 1, 5, 5, 4),
      throwsArgumentError,
    );
  }, skip: !available);

  test(
    'a zone with holes is a contour of rings, at the bottom of the layer',
    () {
      final document = RustDocument();
      try {
        document.addStroke(const [DocumentPoint(50, 50)], rgb: 0, width: 5);
        final outer = [
          const DocumentPoint(10, 10),
          const DocumentPoint(300, 10),
          const DocumentPoint(300, 300),
          const DocumentPoint(10, 300),
        ];
        final hole = [
          const DocumentPoint(100, 100),
          const DocumentPoint(100, 200),
          const DocumentPoint(200, 200),
          const DocumentPoint(200, 100),
        ];
        document.addObject(
          VectorKind.contour,
          [...outer, ...hole],
          rgb: 0xff8800,
          width: .5,
          fillRgb: 0xff8800,
          rings: const [4, 4],
          bottom: true,
        );
        expect(document.count, 2);
        // Under what the layer held.
        expect(document.strokes.first.kind, VectorKind.contour);
        expect(document.strokes.first.rings, [4, 4]);
        expect(document.exportSvg(), contains('fill-rule="evenodd"'));
      } finally {
        document.dispose();
      }
    },
    skip: !available,
  );

  test('the new shapes fill their box, and the magnet makes shapes', () {
    final star = RustDocument.shapeOutline(
      NewShape.star,
      const DocumentPoint(0, 0),
      const DocumentPoint(100, 100),
    );
    expect(star, hasLength(10));
    expect(star.first.x, 50);
    expect(star.first.y, 0);
    expect(
      () => RustDocument.shapeOutline(
        NewShape.heart,
        const DocumentPoint(0, 0),
        const DocumentPoint(0, 100),
      ),
      throwsArgumentError,
    );
    final document = RustDocument();
    try {
      // A square drawn by hand, a little short of its start.
      final drawn = <DocumentPoint>[
        for (var i = 0; i < 50; i++)
          DocumentPoint(200 + i * 4.0, 200 + (i % 3) * .4),
        for (var i = 0; i < 50; i++)
          DocumentPoint(400 + (i % 3) * .4, 200 + i * 4.0),
        for (var i = 0; i < 50; i++)
          DocumentPoint(400 - i * 4.0, 400 - (i % 3) * .4),
        for (var i = 0; i < 48; i++)
          DocumentPoint(200 - (i % 3) * .4, 400 - i * 4.0),
      ];
      final shape = document.recogniseShape(drawn)!;
      expect(shape.kind, VectorKind.rectangle);
      expect(shape.points, hasLength(2));
      expect(shape.rotation, 0);
      // A scribble stays as drawn.
      final random = math.Random(7);
      final scribble = [
        for (var i = 0; i < 80; i++)
          DocumentPoint(
            300 + random.nextDouble() * 200,
            300 + random.nextDouble() * 200,
          ),
      ];
      expect(document.recogniseShape(scribble), isNull);
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('the matrix of a turn and the point under it agree', () {
    const look = ObjectLook(rotation: math.pi / 2, mirrorY: true);
    expect(look.transforms, isTrue);
    expect(ObjectLook.plain.isPlain, isTrue);
    expect(normalAngle(3 * math.pi), closeTo(3.1415925, 1e-7));
    expect(
      normalAngle(-math.pi / 2 + 4 * math.pi),
      closeTo(-math.pi / 2, 1e-9),
    );
    // Mirrored twice the same way, nothing is mirrored.
    final twice = look.flippedLeftRight().flippedLeftRight();
    expect(twice.mirrorX, isFalse);
    expect(twice.rotation, closeTo(look.rotation, 1e-9));
  });
}
