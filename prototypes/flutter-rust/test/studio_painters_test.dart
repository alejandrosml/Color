// SPDX-License-Identifier: MIT
// The sheet of the studio paints what is being drawn on the active layer,
// under the layers above it: where the element lies once it is drawn, so
// that nothing jumps when the pointer is released. The elements are given by
// hand, no Rust library is needed.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/child_art.dart' show ShapeMarkColours;
import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/drawing_gesture.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_painters.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ink = 0x2f3d4a;
const _red = 0xd75e56;
const _yellow = 0xeebf4e;
const _white = 0xffffff;

RenderedElement _element(
  List<(double, double)> points,
  int layer, {
  int rgb = _ink,
  double width = 8,
  VectorKind kind = VectorKind.stroke,
  int? fillRgb,
}) => RenderedElement(
  StrokeData(
    [for (final (x, y) in points) DocumentPoint(x, y)],
    rgb,
    width,
    kind: kind,
    fillRgb: fillRgb,
    layer: layer,
  ),
);

/// The page of a colouring page, the child's layer between its two layers:
/// a zone that the paint pot coloured, under a line of the page across it.
const _pageLayers = [
  LayerData(id: 1, visible: true, objectCount: 1, locked: true),
  LayerData(id: 0, visible: true, objectCount: 0),
  LayerData(id: 2, visible: true, objectCount: 2, locked: true),
];
final _page = [
  _element(
    [(20, 20), (180, 180)],
    1,
    kind: VectorKind.rectangle,
    rgb: _white,
    width: .1,
    fillRgb: _yellow,
  ),
  _element([(100, 10), (100, 190)], 2),
  _element([(150, 10), (150, 190)], 2),
];
const _pageOrder = [0, 1, 2];

/// A trait across the sheet, through (100, 100).
const _across = [DocumentPoint(20, 100), DocumentPoint(180, 100)];

/// The sheet of 200 by 200 as the studio paints it, at a scale of 1, with
/// [draft] being drawn in red.
DocumentPainter _painter({
  required List<RenderedElement> strokes,
  required List<int> paintOrder,
  List<DocumentPoint> draft = const [],
  int? draftDepth,
  ShapeAnchor? anchor,
}) => DocumentPainter(
  viewport: DocumentViewport(
    viewWidth: 200,
    viewHeight: 200,
    documentWidth: 200,
    documentHeight: 200,
    padding: 0,
  ),
  paperRgb: _white,
  background: null,
  strokes: strokes,
  paintOrder: paintOrder,
  draftStamp: 0,
  draft: draft.isEmpty
      ? null
      : (Path()..addPolygon([
          for (final point in draft) Offset(point.x, point.y),
        ], false)),
  draftPoints: draft,
  repaint: ValueNotifier(0),
  draftColor: _red,
  draftWidth: 10,
  draftKind: VectorKind.stroke,
  draftFillRgb: null,
  revision: 0,
  selectedIndex: null,
  selectionBounds: null,
  selectionOffset: ValueNotifier(Offset.zero),
  draftDepth: draftDepth,
  anchor: anchor,
  anchorRgb: _red,
  anchorWidth: 10,
);

Future<_Pixels> _paint(WidgetTester tester, DocumentPainter painter) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(200, 200));
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

int _rgb(Color color) => color.toARGB32() & 0xffffff;

void main() {
  test('what is being drawn lies over the active layer, under those above', () {
    int depth(List<LayerData> layers, int active, List<int> order) =>
        draftDepthOf(
          strokes: _page,
          paintOrder: order,
          layers: layers,
          activeLayer: active,
        );
    // Over the zones, under the lines.
    expect(depth(_pageLayers, 0, _pageOrder), 1);
    // The zones hidden, or the lines: what is left of the order.
    expect(depth(_pageLayers, 0, const [1, 2]), 0);
    expect(depth(_pageLayers, 0, const [0]), 1);
    expect(depth(_pageLayers, 0, const []), 0);
    // The child's layer above the page, or under it.
    const above = [
      LayerData(id: 1, visible: true, objectCount: 1, locked: true),
      LayerData(id: 2, visible: true, objectCount: 2, locked: true),
      LayerData(id: 0, visible: true, objectCount: 0),
    ];
    expect(depth(above, 0, _pageOrder), 3);
    const under = [
      LayerData(id: 0, visible: true, objectCount: 0),
      LayerData(id: 1, visible: true, objectCount: 1, locked: true),
      LayerData(id: 2, visible: true, objectCount: 2, locked: true),
    ];
    expect(depth(under, 0, _pageOrder), 0);
    // An unknown layer: over everything, as the studio always painted it.
    expect(depth(_pageLayers, 9, _pageOrder), 3);
    // Many elements on many layers: the count of those up to the active one.
    final many = [
      for (var index = 0; index < 1000; index++)
        _element([(10, 10), (20, 20)], index % 4),
    ];
    const four = [
      LayerData(id: 3, visible: true, objectCount: 250),
      LayerData(id: 0, visible: true, objectCount: 250),
      LayerData(id: 2, visible: true, objectCount: 250),
      LayerData(id: 1, visible: true, objectCount: 250),
    ];
    final order = [
      for (final layer in four)
        for (var index = 0; index < many.length; index++)
          if (many[index].data.layer == layer.id) index,
    ];
    for (final (position, layer) in four.indexed) {
      expect(
        draftDepthOf(
          strokes: many,
          paintOrder: order,
          layers: four,
          activeLayer: layer.id,
        ),
        250 * (position + 1),
      );
    }
  });

  testWidgets(
    'on a colouring page a trait being drawn passes under the lines, as it does once drawn',
    (tester) async {
      final depth = draftDepthOf(
        strokes: _page,
        paintOrder: _pageOrder,
        layers: _pageLayers,
        activeLayer: 0,
      );
      final drawing = await _paint(
        tester,
        _painter(
          strokes: _page,
          paintOrder: _pageOrder,
          draft: _across,
          draftDepth: depth,
        ),
      );
      // Under the line of the page, over its coloured zone.
      expect(drawing.at(100, 100), _ink);
      expect(drawing.at(60, 100), _red);
      expect(drawing.at(60, 60), _yellow);
      // Drawn, the trait is on the child's layer: the very same pixels.
      final drawn = await _paint(
        tester,
        _painter(
          strokes: [
            ..._page,
            _element([(20, 100), (180, 100)], 0, rgb: _red, width: 10),
          ],
          paintOrder: const [0, 3, 1, 2],
        ),
      );
      expect(drawn.differences(drawing), 0);
      // Painted over the whole drawing, it would cover the line, then jump
      // under it.
      final over = await _paint(
        tester,
        _painter(strokes: _page, paintOrder: _pageOrder, draft: _across),
      );
      expect(over.at(100, 100), _red);
    },
  );

  testWidgets(
    'the shape that two clicks make lies on the active layer too; its little circles stay on top',
    (tester) async {
      // A line from (40, 150) to the second line of the page, at (150, 150).
      final anchor = ShapeAnchor(const DocumentPoint(40, 150), VectorKind.line)
        ..end = const DocumentPoint(150, 150);
      final pixels = await _paint(
        tester,
        _painter(
          strokes: _page,
          paintOrder: _pageOrder,
          draftDepth: 1,
          anchor: anchor,
        ),
      );
      expect(pixels.at(70, 150), _red);
      expect(pixels.at(100, 150), _ink, reason: 'under the first line');
      // The circle of the pointer is over the second line.
      expect(pixels.at(150, 150), _rgb(ShapeMarkColours.line.end));
      expect(pixels.at(40, 150), _rgb(ShapeMarkColours.line.start));
    },
  );

  testWidgets('on a sheet without a page, a trait is drawn exactly as before', (
    tester,
  ) async {
    // One layer: what is being drawn goes over the whole drawing.
    const layers = [LayerData(id: 0, visible: true, objectCount: 1)];
    final sheet = [
      _element([(100, 10), (100, 190)], 0),
    ];
    const order = [0];
    final depth = draftDepthOf(
      strokes: sheet,
      paintOrder: order,
      layers: layers,
      activeLayer: 0,
    );
    expect(depth, order.length);
    final now = await _paint(
      tester,
      _painter(
        strokes: sheet,
        paintOrder: order,
        draft: _across,
        draftDepth: depth,
      ),
    );
    final before = await _paint(
      tester,
      _painter(strokes: sheet, paintOrder: order, draft: _across),
    );
    expect(now.differences(before), 0);
    expect(now.at(100, 100), _red);

    // Several layers: drawn on the lower one, it passes under the upper one,
    // where it lies once drawn; drawn on the upper one, over everything.
    const two = [
      LayerData(id: 0, visible: true, objectCount: 0),
      LayerData(id: 1, visible: true, objectCount: 1),
    ];
    final upper = [
      _element([(100, 10), (100, 190)], 1),
    ];
    Future<_Pixels> drawingOn(int layer) => _paint(
      tester,
      _painter(
        strokes: upper,
        paintOrder: order,
        draft: _across,
        draftDepth: draftDepthOf(
          strokes: upper,
          paintOrder: order,
          layers: two,
          activeLayer: layer,
        ),
      ),
    );
    expect((await drawingOn(0)).at(100, 100), _ink);
    expect((await drawingOn(1)).at(100, 100), _red);
  });
}
