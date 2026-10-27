// SPDX-License-Identifier: MIT
// Real Rust documents through the Dart wrapper: no native function is faked.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/document_exports.dart';
import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/layers_dialog.dart';
import 'package:edupaint_flutter_study/png_export.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/selection_geometry.dart';
import 'package:edupaint_flutter_study/text_layout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

File fixture(String name) => File('test/fixtures/project-open/$name');

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  RustDocument sample() {
    final document = RustDocument();
    document.addStroke(const [DocumentPoint(10, 10)], rgb: 0x111111, width: 4);
    document.addLayer();
    document.addText(
      const DocumentPoint(100, 200),
      const DocumentPoint(420, 296),
      text: 'Été &\n<ici>',
      rgb: 0x336699,
      size: 40,
    );
    document.addStamp(
      const DocumentPoint(500, 100),
      const DocumentPoint(700, 300),
      stamp: 1,
      rgb: 0xd75e56,
    );
    document.setActiveLayer(0);
    document.addShape(
      VectorKind.rectangle,
      const DocumentPoint(480, 80),
      const DocumentPoint(720, 320),
      rgb: 0x222222,
      width: 4,
      fillRgb: 0xeeeeee,
    );
    return document;
  }

  test('snapshots expose layers, characters, stamps and the paint order', () {
    final document = sample();
    try {
      expect(document.layers, const [
        LayerData(id: 0, visible: true, objectCount: 2),
        LayerData(id: 1, visible: true, objectCount: 2),
      ]);
      expect(document.activeLayer, 0);
      expect(document.strokes.map((object) => object.kind), [
        VectorKind.stroke,
        VectorKind.text,
        VectorKind.stamp,
        VectorKind.rectangle,
      ]);
      expect(document.strokes.map((object) => object.layer), [0, 1, 1, 0]);
      // The rectangle was drawn last but lies on the lower layer.
      expect(document.paintOrder, [0, 3, 1, 2]);
      expect(document.visibleStrokes, [
        document.strokes[0],
        document.strokes[3],
        document.strokes[1],
        document.strokes[2],
      ]);
      final text = document.strokes[1];
      expect(text.text, 'Été &\n<ici>');
      expect(text.width, 40);
      expect(text.stamp, isNull);
      expect(text.outlineRadius, 0);
      final stamp = document.strokes[2];
      expect(stamp.stamp, 1);
      expect(stamp.text, isNull);
      expect(stamp.width, 1);
      expect(document.strokes[3].outlineRadius, 2);
      // Unchanged objects keep their snapshot when a layer changes.
      final before = document.strokes[1];
      expect(document.setLayerVisible(1, false), isTrue);
      expect(identical(document.strokes[1], before), isTrue);
      expect(document.paintOrder, [0, 3]);
      expect(document.visibleStrokes, hasLength(2));
      expect(document.layers[1].visible, isFalse);
      expect(document.setLayerVisible(1, false), isFalse);
      expect(document.undo(), isTrue);
      expect(document.paintOrder, [0, 3, 1, 2]);
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test(
    'hit testing follows layers: the upper layer wins, a hidden one is out',
    () {
      final document = sample();
      try {
        int? hit(double x, double y) => hitTestObjects(
          document.strokes,
          DocumentPoint(x, y),
          scale: 1,
          paintOrder: document.paintOrder,
        );
        // On the stamp's drawing, which lies above the filled rectangle.
        expect(hit(600, 200), 2);
        // In an empty corner of the stamp's box the rectangle is what is
        // seen under the pointer: it answers, not the stamp above it.
        expect(hit(505, 105), 3);
        // Alone, a stamp answers in its whole box: nothing else is there.
        expect(
          hitTestObjects(
            [document.strokes[2]],
            const DocumentPoint(505, 105),
            scale: 1,
          ),
          0,
        );
        // The whole box of a text answers, even between its glyphs.
        expect(hit(110, 290), 1);
        // The rectangle's margin is outside the stamp's box.
        expect(hit(490, 90), 3);
        expect(hit(900, 700), isNull);
        // Without layers the last index would win everywhere in the rectangle.
        expect(
          hitTestObjects(
            document.strokes,
            const DocumentPoint(600, 200),
            scale: 1,
          ),
          3,
        );
        expect(document.setLayerVisible(1, false), isTrue);
        expect(hit(600, 200), 3);
        expect(hit(110, 290), isNull);
        // Raising the lower layer reverses the answer in the overlap.
        expect(document.setLayerVisible(1, true), isTrue);
        expect(document.reorderLayer(0, 1), isTrue);
        expect(document.layers.map((layer) => layer.id), [1, 0]);
        expect(hit(600, 200), 3);
      } finally {
        document.dispose();
      }
    },
    skip: !available,
  );

  test('layer and text commands report changes, no-ops and refusals', () {
    final document = sample();
    try {
      expect(document.reorderLayer(0, 0), isFalse);
      expect(() => document.reorderLayer(0, 2), throwsRangeError);
      expect(() => document.setLayerVisible(2, true), throwsRangeError);
      expect(() => document.removeLayer(2), throwsRangeError);
      expect(() => document.setActiveLayer(7), throwsArgumentError);
      expect(() => document.setActiveLayer(-1), throwsArgumentError);
      expect(() => document.setObjectLayer(9, 0), throwsRangeError);
      expect(
        () => document.setObjectLayer(0, 7),
        throwsA(isA<RustCoreException>()),
      );
      expect(document.setObjectLayer(0, 0), isFalse);
      expect(document.setObjectLayer(0, 1), isTrue);
      // The moved object is now last, in front of the upper layer.
      expect(document.strokes.last.kind, VectorKind.stroke);
      expect(document.strokes.last.layer, 1);
      expect(document.paintOrder, [2, 0, 1, 3]);
      expect(document.undo(), isTrue);
      expect(document.strokes.first.kind, VectorKind.stroke);

      expect(
        document.setText(
          1,
          const DocumentPoint(100, 200),
          const DocumentPoint(420, 296),
          text: 'Été &\n<ici>',
          rgb: 0x336699,
          size: 40,
        ),
        isFalse,
      );
      expect(
        () => document.setText(
          0,
          const DocumentPoint(1, 1),
          const DocumentPoint(9, 9),
          text: 'pas un texte',
          rgb: 0,
          size: 20,
        ),
        throwsA(isA<RustCoreException>()),
      );
      expect(
        () => document.addText(
          const DocumentPoint(1, 1),
          const DocumentPoint(9, 9),
          text: '',
          rgb: 0,
          size: 20,
        ),
        throwsArgumentError,
      );
      expect(
        () => document.addText(
          const DocumentPoint(1, 1),
          const DocumentPoint(9, 9),
          text: 'x' * (maxTextBytes + 1),
          rgb: 0,
          size: 20,
        ),
        throwsArgumentError,
      );
      expect(
        () => document.addStamp(
          const DocumentPoint(1, 1),
          const DocumentPoint(9, 9),
          stamp: 60000,
          rgb: 0,
        ),
        throwsA(isA<RustCoreException>()),
      );
      expect(
        () => document.addStamp(
          const DocumentPoint(1, 1),
          const DocumentPoint(1, 9),
          stamp: 0,
          rgb: 0,
        ),
        throwsA(isA<RustCoreException>()),
      );
      // A text keeps its size and a stamp its constant in the style command.
      expect(document.setObjectStyle(1, rgb: 0xabcdef, width: 40), isTrue);
      expect(
        () => document.setObjectStyle(1, rgb: 0xabcdef, width: 12),
        throwsA(isA<RustCoreException>()),
      );
      expect(document.setObjectStyle(2, rgb: 0x00ff00, width: 1), isTrue);
      expect(document.strokes[2].rgb, 0x00ff00);
      // Sixteen layers at most, and never fewer than one.
      while (document.layers.length < maxLayers) {
        document.addLayer();
      }
      expect(document.addLayer, throwsA(isA<RustCoreException>()));
      while (document.layers.length > 1) {
        document.removeLayer(document.layers.length - 1);
      }
      expect(() => document.removeLayer(0), throwsA(isA<RustCoreException>()));
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('project, SVG and worker exports agree on a layered drawing', () async {
    final document = sample();
    try {
      final bytes = document.exportProject();
      expect(bytes[8], 4);
      expect(document.projectByteLength, bytes.length);
      expect(await document.exportProjectAsync(), bytes);
      expect(await prepareProjectBytes(document), bytes);
      final svg = document.exportSvg();
      expect(utf8.decode(await document.exportSvgBytesAsync()), svg);
      expect(utf8.decode(await prepareSvgBytes(document)), svg);
      expect(svg, contains('<g id="calque-1">'));
      expect(svg, contains('>Été &amp;</tspan>'));
      expect(svg, contains('>&lt;ici&gt;</tspan>'));
      expect(svg, contains('translate(500 100) scale(2 2)'));
      final reopened = RustDocument.fromProject(bytes);
      try {
        expect(reopened.exportProject(), bytes);
        expect(reopened.exportSvg(), svg);
        expect(reopened.layers, document.layers);
        expect(reopened.activeLayer, 0);
        expect(reopened.strokes[1].text, 'Été &\n<ici>');
        expect(reopened.strokes[2].stamp, 1);
      } finally {
        reopened.dispose();
      }
      // The same bytes through the worker used by Ouvrir and the recovery.
      final prepared = await RustDocument.loadProjectBytes(bytes);
      try {
        expect(prepared.document.exportProject(), bytes);
        expect(prepared.document.paintOrder, [0, 3, 1, 2]);
        expect(prepared.document.layers, document.layers);
        expect(prepared.document.strokes[1].text, 'Été &\n<ici>');
        expect(prepared.takeBackground(), isNull);
      } finally {
        prepared.dispose();
      }
    } finally {
      document.dispose();
    }
  }, skip: !available);

  for (final name in [
    'layers-text-stamp-v4.edupaint',
    'text-on-image-v4.edupaint',
    'locked-page-v5.edupaint',
    // Version 5 without anything of it: written back as version 4.
    'layers-only-v5.edupaint',
  ]) {
    test(
      'independent fixture $name loads from a real file unchanged',
      () async {
        final expected = await fixture('$name.normalized').readAsBytes();
        final prepared = await RustDocument.loadProjectFile(
          fixture(name).absolute.path,
        );
        try {
          expect(prepared.document.exportProject(), expected);
        } finally {
          prepared.dispose();
        }
        final direct = RustDocument.fromProject(
          await fixture(name).readAsBytes(),
        );
        try {
          expect(direct.exportProject(), expected);
        } finally {
          direct.dispose();
        }
      },
      skip: !available,
    );
  }

  test('the independent layered fixture has the described content', () async {
    final document = RustDocument.fromProject(
      await fixture('layers-text-stamp-v4.edupaint').readAsBytes(),
    );
    try {
      expect([document.width, document.height], [800, 1200]);
      expect(document.layers, const [
        LayerData(id: 0, visible: true, objectCount: 2),
        LayerData(id: 2, visible: false, objectCount: 1),
        LayerData(id: 1, visible: true, objectCount: 2),
      ]);
      expect(document.activeLayer, 1);
      expect(document.paintOrder, [0, 4, 2, 3]);
      expect(document.strokes[2].text, 'Été 🎨\n2 < 3 & 4');
      expect(document.strokes[3].stamp, 8);
      expect(document.strokes[1].fillRgb, 0xaabbcc);
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test(
    'the independent page fixture of version 5 has the described content',
    () async {
      final bytes = await fixture('locked-page-v5.edupaint').readAsBytes();
      final document = RustDocument.fromProject(bytes);
      try {
        expect([document.width, document.height], [1200, 800]);
        // Zones and lines locked around the drawing; a hidden layer, and a
        // hidden locked one.
        expect(document.layers, const [
          LayerData(id: 1, visible: true, objectCount: 2, locked: true),
          LayerData(id: 0, visible: true, objectCount: 2),
          LayerData(id: 3, visible: false, objectCount: 1),
          LayerData(id: 4, visible: false, objectCount: 1, locked: true),
          LayerData(id: 2, visible: true, objectCount: 3, locked: true),
        ]);
        expect(document.activeLayer, 0);
        expect(document.lockedLayers, {1, 4, 2});
        expect(document.strokes.map((object) => object.kind), [
          VectorKind.contour,
          VectorKind.rectangle,
          VectorKind.stroke,
          VectorKind.contour,
          VectorKind.stamp,
          VectorKind.ellipse,
          VectorKind.contour,
          VectorKind.rectangle,
          VectorKind.stroke,
        ]);
        expect(document.paintOrder, [0, 1, 2, 3, 6, 7, 8]);
        // What the eraser and « Choisir » reach: the drawing of the child.
        expect(document.unlockedPaintOrder, [2, 3]);
        // What the child made: the drawing, its hidden stamp too; no zone
        // of the page, all of them still white.
        expect(document.madeCount, 3);
        expect(document.madePaintOrder, [2, 3]);
        expect([
          for (var i = 0; i < document.count; i++) document.isColouredZone(i),
        ], everyElement(isFalse));
        expect(
          [for (var i = 0; i < document.count; i++) document.isLockedObject(i)],
          [true, true, false, false, false, true, true, true, true],
        );
        final zone = document.strokes[0];
        expect(zone.points, hasLength(5));
        expect(zone.fillRgb, 0xffffff);
        expect(zone.rgb, 0xffffff);
        expect(zone.width, closeTo(.1, 1e-6));
        expect(zone.outlineRadius, closeTo(.05, 1e-6));
        final drawn = document.strokes[3];
        expect(drawn.points.map((point) => (point.x, point.y)), [
          (700, 400),
          (900, 420.5),
          (820, 600),
          (690, 560),
        ]);
        expect(drawn.fillRgb, 0xaabbcc);
        expect(drawn.rgb, 0x336699);
        expect(document.strokes[6].fillRgb, isNull);
        // The objects of the locked layers are not in the history: only the
        // three others are steps to undo.
        expect(document.undoCount, 3);
        expect(document.exportProject()[8], 5);
        expect(document.exportSvg(), contains('<path d="M700 400 L900 420.5 '));
      } finally {
        document.dispose();
      }
    },
    skip: !available,
  );

  test('the core keeps a page whole whatever is asked; the paint pot changes the colour of a zone', () async {
    final document = RustDocument.fromProject(
      await fixture('locked-page-v5.edupaint').readAsBytes(),
    );
    try {
      final before = document.exportProject();
      Matcher refused() => throwsA(
        isA<RustCoreException>().having((error) => error.code, 'code', -1),
      );
      // Neither its objects…
      expect(() => document.removeObject(0), refused());
      expect(() => document.moveObject(7, 10, 10), refused());
      expect(() => document.duplicateObject(7, 10, 10), refused());
      expect(() => document.reorderObject(7, 0), refused());
      expect(() => document.scaleObject(1, 1.5, width: .1), refused());
      expect(() => document.setObjectLayer(7, 0), refused());
      expect(() => document.setObjectLayer(2, 1), refused());
      expect(
        () => document.setObjectStyle(7, rgb: 0xff0000, width: 6),
        refused(),
      );
      // A zone keeps its outline and its inside: only its colour changes.
      expect(
        () => document.setObjectStyle(0, rgb: 0xff0000, width: .1, fillRgb: 1),
        refused(),
      );
      expect(
        () => document.setObjectStyle(0, rgb: 0xffffff, width: .1),
        refused(),
      );
      // … nor its layers.
      expect(() => document.setActiveLayer(1), throwsArgumentError);
      expect(() => document.removeLayer(0), refused());
      expect(() => document.reorderLayer(0, 1), refused());
      expect(() => document.reorderLayer(4, 0), refused());
      expect(document.exportProject(), before);
      expect(document.undoCount, 3);

      // The paint pot's change, one step for Annuler.
      final zone = document.strokes[0];
      expect(
        document.setObjectStyle(
          0,
          rgb: zone.rgb,
          width: zone.width,
          fillRgb: 0xeebf4e,
        ),
        isTrue,
      );
      expect(document.strokes[0].fillRgb, 0xeebf4e);
      expect(document.undoCount, 4);
      // The coloured zone is something the child made; the white zones and
      // the lines of the page are not.
      expect(document.isColouredZone(0), isTrue);
      expect(document.isColouredZone(1), isFalse);
      expect(document.isColouredZone(3), isFalse, reason: 'not on the page');
      expect(document.madeCount, 4);
      expect(document.madePaintOrder, [0, 2, 3]);
      // Shown, hidden: a layer of the page may be.
      expect(document.setLayerVisible(3, true), isTrue);
      expect(document.paintOrder, [0, 1, 2, 3, 5, 6, 7, 8]);
      expect(document.madePaintOrder, [0, 2, 3]);
      expect(document.setLayerVisible(0, false), isTrue);
      expect(document.paintOrder, [2, 3, 5, 6, 7, 8]);
      // Hidden, the coloured zone still counts, but it is not shown.
      expect(document.madeCount, 4);
      expect(document.madePaintOrder, [2, 3]);
      // No layer passes a layer of the page, nor goes over it: the layers
      // between two of them are reordered among themselves only.
      final steps = document.undoCount;
      expect(() => document.reorderLayer(1, 4), refused());
      expect(() => document.reorderLayer(2, 3), refused());
      expect(() => document.reorderLayer(2, 0), refused());
      expect(document.layers.map((layer) => layer.id), [1, 0, 3, 4, 2]);
      expect(document.undoCount, steps);
      expect(document.reorderLayer(1, 2), isTrue);
      expect(document.layers.map((layer) => layer.id), [1, 3, 0, 4, 2]);
      expect(document.undo(), isTrue);
      expect(document.undo(), isTrue);
      expect(document.undo(), isTrue);
      expect(document.undo(), isTrue);
      expect(document.strokes[0].fillRgb, 0xffffff);
      expect(document.isColouredZone(0), isFalse);
      expect(document.madeCount, 3);
      expect(document.madePaintOrder, [2, 3]);
      expect(document.exportProject(), before);
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test(
    'a sheet without a page counts all its objects as made by the child',
    () {
      final document = sample();
      try {
        expect(document.madeCount, document.count);
        expect(identical(document.madePaintOrder, document.paintOrder), isTrue);
        // A grey inside on a sheet is not a zone of a page.
        expect(document.isColouredZone(3), isFalse);
        // Hidden objects still count, but they are not shown.
        expect(document.setLayerVisible(1, false), isTrue);
        expect(document.madeCount, 4);
        expect(document.madePaintOrder, [0, 3]);
      } finally {
        document.dispose();
      }
    },
    skip: !available,
  );

  test('an inside is coloured when it is no longer white', () {
    StrokeData object({int? fillRgb}) => StrokeData(
      const [DocumentPoint(0, 0), DocumentPoint(10, 10)],
      0x2f3d4a,
      2,
      kind: VectorKind.rectangle,
      fillRgb: fillRgb,
    );
    expect(object().colouredInside, isFalse);
    expect(object(fillRgb: whitePaper).colouredInside, isFalse);
    expect(object(fillRgb: 0xfffffe).colouredInside, isTrue);
    expect(object(fillRgb: 0).colouredInside, isTrue);
  });

  testWidgets('contours are painted in the PNG export, filled and outlined', (
    tester,
  ) async {
    // Read at once: real input and output never complete in the fake time
    // of a widget test.
    final document = RustDocument.fromProject(
      fixture('locked-page-v5.edupaint').readAsBytesSync(),
    );
    try {
      Future<List<int>> pixel(int x, int y) async {
        final png = (await tester.runAsync(
          () => exportDocumentPng(
            document.visibleStrokes,
            width: document.width,
            height: document.height,
          ),
        ))!;
        final image = (await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(png);
          return (await codec.getNextFrame()).image;
        }))!;
        final data = (await tester.runAsync(() => image.toByteData()))!;
        image.dispose();
        final offset = (y * document.width + x) * 4;
        return [
          data.getUint8(offset),
          data.getUint8(offset + 1),
          data.getUint8(offset + 2),
        ];
      }

      // The contour of the child: its inside, then its outline.
      expect(await pixel(780, 480), [0xaa, 0xbb, 0xcc]);
      expect(await pixel(800, 410), [0x33, 0x66, 0x99]);
      // The pentagon of the page: a white zone under an ink line.
      expect(await pixel(150, 270), [255, 255, 255]);
      expect(await pixel(200, 101), [0x2f, 0x3d, 0x4a]);
      // Its closing side, from the last point back to the first.
      expect(await pixel(150, 135), [0x2f, 0x3d, 0x4a]);
      expect(await pixel(130, 120), [255, 255, 255]);
    } finally {
      document.dispose();
    }
  }, skip: !available);

  for (final name in [
    'unknown-stamp-v4.edupaint',
    'duplicate-layers-v4.edupaint',
    'control-text-v4.edupaint',
    // A body of version 2 announced as version 5: a malformed version 5.
    'unknown-version-5.edupaint',
    'unknown-version.edupaint',
    'locked-active-v5.edupaint',
    'layer-flags-v5.edupaint',
    'flat-contour-v5.edupaint',
    'short-contour-v5.edupaint',
    'contour-in-v4.edupaint',
    'locked-in-v4.edupaint',
    'unknown-version-6.edupaint',
  ]) {
    test('rejected fixture $name is refused by both entries', () async {
      final bytes = await fixture(name).readAsBytes();
      expect(() => RustDocument.fromProject(bytes), throwsFormatException);
      await expectLater(
        RustDocument.loadProjectFile(fixture(name).absolute.path),
        throwsFormatException,
      );
    }, skip: !available);
  }

  test('a locked layer is told apart, and named « Page »', () {
    const plain = LayerData(id: 1, visible: true, objectCount: 2);
    const locked = LayerData(
      id: 1,
      visible: true,
      objectCount: 2,
      locked: true,
    );
    expect(plain.locked, isFalse);
    expect(locked, isNot(plain));
    expect(
      locked,
      const LayerData(id: 1, visible: true, objectCount: 2, locked: true),
    );
    expect(
      locked.hashCode,
      const LayerData(
        id: 1,
        visible: true,
        objectCount: 2,
        locked: true,
      ).hashCode,
    );
    // Without a page, a layer is named after its identifier, as before.
    const sheet = [
      LayerData(id: 0, visible: true, objectCount: 0),
      LayerData(id: 2, visible: true, objectCount: 0),
    ];
    expect(layerName(0, sheet), 'Calque 1');
    expect(layerName(2, sheet), 'Calque 3');
    // The layers of a page take no number: the child's are 1, 2, 3…
    const page = [
      LayerData(id: 1, visible: true, objectCount: 9, locked: true),
      LayerData(id: 0, visible: true, objectCount: 0),
      LayerData(id: 4, visible: true, objectCount: 0),
      LayerData(id: 3, visible: true, objectCount: 0),
      LayerData(id: 2, visible: true, objectCount: 9, locked: true),
    ];
    expect(layerName(1, page), pageLayerName);
    expect(layerName(2, page), 'Page');
    expect(layerName(0, page), 'Calque 1');
    expect(layerName(3, page), 'Calque 2');
    expect(layerName(4, page), 'Calque 3');
  });

  test('the Dart size bound is the bound of the layered format', () {
    expect(maxProjectBytes, 80711932);
    expect(
      () => RustDocument.fromProject(Uint8List(maxProjectBytes + 1)),
      throwsFormatException,
    );
  });

  test('rendered elements refuse inconsistent texts and stamps', () {
    StrokeData box(
      VectorKind kind, {
      String? text,
      int? stamp,
      double width = 1,
    }) => StrokeData(
      const [DocumentPoint(10, 10), DocumentPoint(90, 60)],
      0x123456,
      width,
      kind: kind,
      text: text,
      stamp: stamp,
    );
    expect(
      RenderedElement(box(VectorKind.text, text: 'ok', width: 20))
          .controlBounds,
      const Rect.fromLTRB(10, 10, 90, 60),
    );
    expect(
      RenderedElement(box(VectorKind.stamp, stamp: 0)).controlBounds,
      const Rect.fromLTRB(10, 10, 90, 60),
    );
    for (final invalid in [
      box(VectorKind.text, width: 20),
      box(VectorKind.text, text: '', width: 20),
      box(VectorKind.text, text: 'ok', width: 2),
      box(VectorKind.text, text: 'ok', width: 4000),
      box(VectorKind.stamp),
      box(VectorKind.stamp, stamp: 60000),
      box(VectorKind.stamp, stamp: -1),
      box(VectorKind.stamp, stamp: 0, width: 3),
      box(VectorKind.rectangle, text: 'ok', width: 3),
      box(VectorKind.line, stamp: 0, width: 3),
      StrokeData(
        const [DocumentPoint(10, 10)],
        0,
        1,
        kind: VectorKind.stamp,
        stamp: 0,
      ),
      StrokeData(
        const [DocumentPoint(10, 10), DocumentPoint(10, 60)],
        0,
        1,
        kind: VectorKind.stamp,
        stamp: 0,
      ),
    ]) {
      expect(() => RenderedElement(invalid), throwsArgumentError);
    }
  }, skip: !available);

  testWidgets(
    'PNG export paints visible layers in order and skips hidden ones',
    (tester) async {
      final document = RustDocument(width: 200, height: 120);
      try {
        // Bottom layer: a large filled square. Upper layer: a text over it.
        document.addShape(
          VectorKind.rectangle,
          const DocumentPoint(20, 20),
          const DocumentPoint(120, 100),
          rgb: 0x0000ff,
          width: 2,
          fillRgb: 0x0000ff,
        );
        document.addLayer();
        final layout = TextLayout('XX', size: 40, rgb: 0xff0000);
        document.addText(
          const DocumentPoint(30, 30),
          DocumentPoint(30 + layout.width, 30 + layout.height),
          text: 'XX',
          rgb: 0xff0000,
          size: 40,
        );
        Future<List<int>> pixel(int x, int y) async {
          final png = (await tester.runAsync(
            () => exportDocumentPng(
              document.visibleStrokes,
              width: document.width,
              height: document.height,
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
          ];
        }

        // The test font draws solid glyphs: red letters over the blue square.
        expect(await pixel(50, 60), [255, 0, 0]);
        expect(await pixel(110, 90), [0, 0, 255]);
        expect(await pixel(180, 110), [255, 255, 255]);
        expect(document.setLayerVisible(1, false), isTrue);
        expect(await pixel(50, 60), [0, 0, 255]);
        expect(document.setLayerVisible(1, true), isTrue);
        expect(document.setLayerVisible(0, false), isTrue);
        expect(await pixel(50, 60), [255, 0, 0]);
        expect(await pixel(110, 90), [255, 255, 255]);
        // Text below the square once the layers are exchanged.
        expect(document.setLayerVisible(0, true), isTrue);
        expect(document.reorderLayer(1, 0), isTrue);
        expect(await pixel(50, 60), [0, 0, 255]);
      } finally {
        document.dispose();
      }
    },
    skip: !available,
  );
}
