// SPDX-License-Identifier: MIT
// Sheet colour and resizing through the Dart wrapper, on real Rust documents:
// no native function is faked.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/document_exports.dart';
import 'package:edupaint_flutter_study/png_export.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/selection_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  List<double> box(StrokeData object) => [
    for (final point in object.points) ...[point.x, point.y],
  ];

  test('the sheet colour is read, changed, undone and stored by project 4', () {
    final document = RustDocument();
    try {
      expect(document.paperRgb, whitePaper);
      document.addStroke(const [DocumentPoint(5, 6)], rgb: 0x112233, width: 3);
      final plain = document.exportProject();
      expect(plain[8], 2);
      expect(document.setPaperColor(whitePaper), isFalse);
      expect(document.undoCount, 1);
      expect(document.setPaperColor(0xa8d8f0), isTrue);
      expect(document.paperRgb, 0xa8d8f0);
      expect(document.undoCount, 2);
      // The object snapshot is reused: colouring the sheet changed no object.
      final before = document.strokes.single;
      expect(document.setPaperColor(0x000000), isTrue);
      expect(identical(document.strokes.single, before), isTrue);
      expect(document.paperRgb, 0);
      final bytes = document.exportProject();
      expect(bytes[8], 4);
      expect(
        document.exportSvg(),
        contains('<rect width="100%" height="100%" fill="#000000"/>'),
      );
      final reopened = RustDocument.fromProject(bytes);
      try {
        expect(reopened.paperRgb, 0);
        expect(reopened.exportProject(), bytes);
      } finally {
        reopened.dispose();
      }
      expect(document.undo(), isTrue);
      expect(document.paperRgb, 0xa8d8f0);
      expect(document.undo(), isTrue);
      expect(document.paperRgb, whitePaper);
      expect(document.exportProject(), plain);
      expect(document.redo(), isTrue);
      expect(document.paperRgb, 0xa8d8f0);
      for (final invalid in [-1, 0x1000000]) {
        expect(() => document.setPaperColor(invalid), throwsArgumentError);
      }
      expect(document.paperRgb, 0xa8d8f0);
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('saves prepared by a worker carry the sheet colour', () async {
    final document = RustDocument();
    try {
      document.addStroke(const [DocumentPoint(5, 6)], rgb: 0x112233, width: 3);
      document.setPaperColor(0xeebf4e);
      final direct = document.exportProject();
      expect(await document.exportProjectAsync(), direct);
      expect(await prepareProjectBytes(document), direct);
      final svg = document.exportSvg();
      expect(String.fromCharCodes(await document.exportSvgBytesAsync()), svg);
      expect(svg, contains('fill="#eebf4e"/>'));
      // The same bytes load through the worker used by Ouvrir.
      final prepared = await RustDocument.loadProjectBytes(direct);
      try {
        expect(prepared.document.paperRgb, 0xeebf4e);
        expect(prepared.document.exportProject(), direct);
      } finally {
        prepared.dispose();
      }
    } finally {
      document.dispose();
    }
  }, skip: !available);

  testWidgets('PNG export paints the sheet colour under the drawing', (
    tester,
  ) async {
    final document = RustDocument(width: 200, height: 120);
    try {
      document.addShape(
        VectorKind.rectangle,
        const DocumentPoint(20, 20),
        const DocumentPoint(120, 100),
        rgb: 0x0000ff,
        width: 4,
      );
      document.setPaperColor(0x78a66f);
      Future<List<int>> pixel(int x, int y, {int? paper}) async {
        final png = (await tester.runAsync(
          () => exportDocumentPng(
            document.visibleStrokes,
            width: document.width,
            height: document.height,
            paperRgb: paper ?? document.paperRgb,
          ),
        ))!;
        final image = (await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(png);
          return (await codec.getNextFrame()).image;
        }))!;
        final data = (await tester.runAsync(() => image.toByteData()))!;
        image.dispose();
        final offset = (y * 200 + x) * 4;
        return [
          data.getUint8(offset),
          data.getUint8(offset + 1),
          data.getUint8(offset + 2),
          data.getUint8(offset + 3),
        ];
      }

      // Outside and inside the hollow rectangle: opaque paper.
      expect(await pixel(180, 110), [0x78, 0xa6, 0x6f, 255]);
      expect(await pixel(70, 60), [0x78, 0xa6, 0x6f, 255]);
      expect(await pixel(20, 60), [0, 0, 255, 255]);
      // Black paper is a colour like another; the default stays white.
      expect(await pixel(180, 110, paper: 0), [0, 0, 0, 255]);
      final white = (await tester.runAsync(
        () => exportDocumentPng(const [], width: 8, height: 8),
      ))!;
      final codec = (await tester.runAsync(
        () => ui.instantiateImageCodec(white),
      ))!;
      final frame = (await tester.runAsync(codec.getNextFrame))!;
      final data = (await tester.runAsync(() => frame.image.toByteData()))!;
      expect(data.getUint32(0), 0xffffffff);
      frame.image.dispose();
      codec.dispose();
      await expectLater(
        exportDocumentPng(const [], width: 8, height: 8, paperRgb: 0x1000000),
        throwsArgumentError,
      );
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('resizing keeps the centre, follows the outline and is one command', () {
    final document = RustDocument();
    try {
      document.addShape(
        VectorKind.rectangle,
        const DocumentPoint(100, 200),
        const DocumentPoint(300, 280),
        rgb: 0x112233,
        width: 6,
        fillRgb: 0x445566,
      );
      document.addStamp(
        const DocumentPoint(0, 0),
        const DocumentPoint(100, 100),
        stamp: 3,
        rgb: 0xeebf4e,
      );
      final stampBefore = document.strokes[1];
      expect(document.scaleObject(0, 1.5, width: 9), isTrue);
      expect(box(document.strokes[0]), [50, 180, 350, 300]);
      expect(document.strokes[0].width, 9);
      expect(document.strokes[0].fillRgb, 0x445566);
      // Only the resized object gets a new snapshot.
      expect(identical(document.strokes[1], stampBefore), isTrue);
      expect(document.undoCount, 3);
      expect(document.scaleObject(0, 1, width: 9), isFalse);
      expect(document.undoCount, 3);

      // A stamp in the corner is pushed back whole onto the sheet.
      expect(document.scaleObject(1, 2, width: 1), isTrue);
      expect(box(document.strokes[1]), [0, 0, 200, 200]);
      expect(document.strokes[1].stamp, 3);
      expect(
        document.exportSvg(),
        contains('<g transform="translate(0 0) scale(2 2)">'),
      );
      final bytes = document.exportProject();
      final reopened = RustDocument.fromProject(bytes);
      try {
        expect(box(reopened.strokes[0]), [50, 180, 350, 300]);
        expect(reopened.exportProject(), bytes);
      } finally {
        reopened.dispose();
      }
      expect(document.undo(), isTrue);
      expect(document.undo(), isTrue);
      expect(box(document.strokes[0]), [100, 200, 300, 280]);
      expect(document.strokes[0].width, 6);
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('requests the core refuses leave the object as it was', () {
    final document = RustDocument();
    try {
      document.addShape(
        VectorKind.ellipse,
        const DocumentPoint(100, 100),
        const DocumentPoint(300, 200),
        rgb: 0x112233,
        width: 6,
      );
      document.addText(
        const DocumentPoint(10, 10),
        const DocumentPoint(110, 58),
        text: 'mot',
        rgb: 0x112233,
        size: 40,
      );
      final before = document.exportProject();
      // Larger than the sheet, a width out of range, a text, a stamp width.
      for (final attempt in <void Function()>[
        () => document.scaleObject(0, 7, width: 6),
        () => document.scaleObject(0, 1.5, width: 600),
        () => document.scaleObject(1, 1.5, width: 60),
        () => document.scaleObject(0, 100, width: 6),
      ]) {
        expect(
          attempt,
          throwsA(isA<RustCoreException>().having((e) => e.code, 'code', -1)),
        );
      }
      for (final attempt in <void Function()>[
        () => document.scaleObject(0, 0, width: 6),
        () => document.scaleObject(0, -1, width: 6),
        () => document.scaleObject(0, double.nan, width: 6),
        () => document.scaleObject(0, 1.5, width: double.infinity),
      ]) {
        expect(attempt, throwsArgumentError);
      }
      expect(() => document.scaleObject(2, 1.5, width: 6), throwsRangeError);
      expect(document.exportProject(), before);
      expect(document.undoCount, 2);
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test(
    'the paint pot reaches the inside of hollow shapes; Choisir does not',
    () {
      final rectangle = StrokeData(
        const [DocumentPoint(100, 100), DocumentPoint(300, 200)],
        0x112233,
        4,
        kind: VectorKind.rectangle,
      );
      final oval = StrokeData(
        const [DocumentPoint(400, 100), DocumentPoint(600, 200)],
        0x112233,
        4,
        kind: VectorKind.ellipse,
      );
      final trait = StrokeData(
        const [DocumentPoint(100, 300), DocumentPoint(300, 300)],
        0x112233,
        4,
      );
      final objects = [rectangle, oval, trait];
      int? hit(double x, double y, {bool inside = false}) => hitTestObjects(
        objects,
        DocumentPoint(x, y),
        scale: 1,
        insideShapes: inside,
      );
      expect(hit(200, 150), isNull);
      expect(hit(200, 150, inside: true), 0);
      expect(hit(500, 150), isNull);
      expect(hit(500, 150, inside: true), 1);
      // The corner of the oval's box is outside the oval, even for the pot.
      expect(hit(405, 105, inside: true), isNull);
      // Outlines and traits answer the same way in both modes.
      expect(hit(100, 150), 0);
      expect(hit(100, 150, inside: true), 0);
      expect(hit(200, 300), 2);
      expect(hit(200, 300, inside: true), 2);
      expect(hit(200, 320, inside: true), isNull);
    },
  );

  test('the pipette tells the border of a filled shape from its inside', () {
    final filled = StrokeData(
      const [DocumentPoint(100, 100), DocumentPoint(300, 200)],
      0xd75e56,
      12,
      kind: VectorKind.rectangle,
      fillRgb: 0xeebf4e,
    );
    int at(double x, double y, {double scale = 1}) =>
        colourOfObjectAt(filled, DocumentPoint(x, y), scale: scale);
    expect(at(200, 150), 0xeebf4e);
    expect(at(100, 150), 0xd75e56);
    expect(at(105, 150), 0xd75e56);
    expect(at(110, 150), 0xeebf4e);
    expect(at(200, 204), 0xd75e56);
    // Zoomed in, the border is not widened by a tolerance in screen pixels.
    expect(at(108, 150, scale: 8), 0xeebf4e);
    final filledOval = StrokeData(
      const [DocumentPoint(100, 100), DocumentPoint(300, 200)],
      0x112233,
      10,
      kind: VectorKind.ellipse,
      fillRgb: 0x445566,
    );
    expect(
      colourOfObjectAt(filledOval, const DocumentPoint(200, 150), scale: 1),
      0x445566,
    );
    expect(
      colourOfObjectAt(filledOval, const DocumentPoint(200, 100), scale: 1),
      0x112233,
    );
    // Objects of a single colour answer with it everywhere.
    final stamp = StrokeData(
      const [DocumentPoint(0, 0), DocumentPoint(50, 50)],
      0x9385bc,
      1,
      kind: VectorKind.stamp,
      stamp: 2,
    );
    expect(
      colourOfObjectAt(stamp, const DocumentPoint(1, 1), scale: 1),
      0x9385bc,
    );
  });
}
