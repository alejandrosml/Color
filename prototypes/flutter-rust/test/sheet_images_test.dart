// SPDX-License-Identifier: MIT
// F-01 and F-04 of the retrospective of October 2026: the drawing of the
// sheet kept as images between frames. At rest, and while a trait is drawn
// at the top of the drawing, the image is exactly the sheet painted element
// by element; what is drawn under a layer and the element being taken lie
// between two images; a trait that ends is drawn onto the image alone; a
// view that moves moves the images, which are made again where it stops.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/draft_stroke.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/sheet_images.dart';
import 'package:edupaint_flutter_study/studio_painters.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/studio_driver.dart';

const _side = 240.0;
const _ink = 0x2f3d4a;

RenderedElement _element(
  List<(double, double)> points,
  int layer, {
  int rgb = _ink,
  double width = 9,
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

/// Three elements on the layer underneath, two on the layer above.
final _drawing = [
  _element(
    [(20, 30), (150, 120)],
    0,
    kind: VectorKind.rectangle,
    width: 4,
    fillRgb: 0xeebf4e,
  ),
  _element([(30, 180), (70, 140), (110, 190), (150, 130), (200, 170)], 0),
  _element(
    [(120, 60), (220, 200)],
    0,
    kind: VectorKind.ellipse,
    rgb: 0x4f8fd8,
    width: 6,
  ),
  _element([(100, 10), (100, 230)], 1, width: 3),
  _element([(10, 220), (230, 20)], 1, rgb: 0xe83d48, width: 5),
];

/// The first three: those under what is drawn on the layer underneath.
const _depth = 3;

const _across = [
  DocumentPoint(15, 100),
  DocumentPoint(80, 90),
  DocumentPoint(140, 115),
  DocumentPoint(225, 95),
];

DocumentViewport _fit() => DocumentViewport(
  viewWidth: _side,
  viewHeight: _side,
  documentWidth: 240,
  documentHeight: 240,
  padding: 13.3,
);

DocumentViewport _zoomed(double factor, {double x = 120, double y = 120}) =>
    DocumentViewport.fromTransform(
      _fit().transform.zoomAt(factor, anchorX: x, anchorY: y),
    );

List<int> _all(List<RenderedElement> strokes) => [
  for (var index = 0; index < strokes.length; index++) index,
];

DocumentPainter _painter({
  List<RenderedElement>? strokes,
  List<int>? paintOrder,
  SheetImages? images,
  double pixelRatio = 1,
  DocumentViewport? viewport,
  bool viewMoving = false,
  List<DocumentPoint> draft = const [],
  int? draftDepth,
  int? selectedIndex,
  ValueNotifier<Offset>? selectionOffset,
}) {
  final elements = strokes ?? _drawing;
  return DocumentPainter(
    viewport: viewport ?? _fit(),
    paperRgb: 0xfffdf8,
    background: null,
    strokes: elements,
    paintOrder: paintOrder ?? _all(elements),
    draft: SheetDraft(
      points: draft,
      stroke: draft.isEmpty ? null : DraftStroke.through(draft),
      rgb: 0x5aa469,
    ),
    repaint: ValueNotifier(0),
    revision: 0,
    selectedIndex: selectedIndex,
    selectionBounds: null,
    selectionOffset: selectionOffset ?? ValueNotifier(Offset.zero),
    draftDepth: draftDepth,
    images: images,
    pixelRatio: pixelRatio,
    viewMoving: viewMoving,
  );
}

class _Pixels {
  _Pixels(this.rgba, this.width);
  final Uint8List rgba;
  final int width;

  /// Bytes that differ, and by how much at most.
  (int, int) compare(_Pixels other) {
    var count = 0;
    var most = 0;
    for (var offset = 0; offset < rgba.length; offset++) {
      final delta = (rgba[offset] - other.rgba[offset]).abs();
      if (delta == 0) continue;
      count++;
      if (delta > most) most = delta;
    }
    return (count, most);
  }

  /// The share of pixels where a channel differs by more than [levels].
  double farFrom(_Pixels other, int levels) {
    var far = 0;
    for (var offset = 0; offset < rgba.length; offset += 4) {
      for (var channel = 0; channel < 4; channel++) {
        if ((rgba[offset + channel] - other.rgba[offset + channel]).abs() >
            levels) {
          far++;
          break;
        }
      }
    }
    return far / (rgba.length / 4);
  }
}

Future<_Pixels> _render(
  WidgetTester tester,
  DocumentPainter painter, {
  double ratio = 1,
}) async => (await tester.runAsync(() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio);
  painter.paint(canvas, const Size(_side, _side));
  final picture = recorder.endRecording();
  final side = (_side * ratio).round();
  final image = await picture.toImage(side, side);
  picture.dispose();
  try {
    return _Pixels((await image.toByteData())!.buffer.asUint8List(), side);
  } finally {
    image.dispose();
  }
}))!;

void main() {
  setUp(() {
    SheetImages.debugFullBakes = 0;
    SheetImages.debugAdditions = 0;
    SheetImages.debugPaintWithoutImages = false;
  });

  testWidgets('at rest the image is the sheet painted element by element', (
    tester,
  ) async {
    for (final ratio in [1.0, 2.0, 3.0]) {
      for (final viewport in [_fit(), _zoomed(2.5, x: 70, y: 60)]) {
        final images = SheetImages();
        final direct = await _render(
          tester,
          _painter(viewport: viewport),
          ratio: ratio,
        );
        final kept = await _render(
          tester,
          _painter(images: images, pixelRatio: ratio, viewport: viewport),
          ratio: ratio,
        );
        expect(kept.compare(direct), (0, 0), reason: 'ratio $ratio');
        // One image holds it all.
        expect(images.debugImageCount, 1);
        // A chosen element that nothing takes stays in it.
        final chosen = await _render(
          tester,
          _painter(
            images: images,
            pixelRatio: ratio,
            viewport: viewport,
            selectedIndex: 1,
          ),
          ratio: ratio,
        );
        expect(chosen.compare(direct), (0, 0));
        expect(SheetImages.debugFullBakes, 1);
        images.dispose();
        expect(images.debugImageCount, 0);
        SheetImages.debugFullBakes = 0;
      }
    }
  });

  testWidgets('a trait drawn at the top lies over the image, exactly', (
    tester,
  ) async {
    final images = SheetImages();
    await _render(tester, _painter(images: images));
    expect(SheetImages.debugFullBakes, 1);
    for (var length = 2; length <= _across.length; length++) {
      final draft = _across.sublist(0, length);
      final direct = await _render(tester, _painter(draft: draft));
      final kept = await _render(
        tester,
        _painter(images: images, draft: draft),
      );
      expect(kept.compare(direct), (0, 0));
    }
    // Every frame of the trait drew the same image.
    expect(SheetImages.debugFullBakes, 1);
    images.dispose();
  });

  testWidgets('what is drawn under a layer lies between two images', (
    tester,
  ) async {
    final images = SheetImages();
    for (var length = 2; length <= _across.length; length++) {
      final draft = _across.sublist(0, length);
      final direct = await _render(
        tester,
        _painter(draft: draft, draftDepth: _depth),
      );
      final kept = await _render(
        tester,
        _painter(images: images, draft: draft, draftDepth: _depth),
      );
      // The layer above, laid as an image over the trait, rounds the edges
      // of its lines once more: never by more than one level.
      final (_, most) = kept.compare(direct);
      expect(most, lessThanOrEqualTo(1));
      expect(images.debugImageCount, 2);
    }
    expect(SheetImages.debugFullBakes, 1);
    images.dispose();
  });

  testWidgets('a trait that ends is drawn onto the image alone', (
    tester,
  ) async {
    final images = SheetImages();
    await _render(tester, _painter(images: images));
    final ended = [
      ..._drawing,
      _element([(15, 100), (80, 90), (140, 115), (225, 95)], 1, width: 12),
    ];
    final kept = await _render(
      tester,
      _painter(images: images, strokes: ended),
    );
    expect(SheetImages.debugFullBakes, 1);
    expect(SheetImages.debugAdditions, 1);
    expect(kept.compare(await _render(tester, _painter(strokes: ended))), (
      0,
      0,
    ));
    // Undone: the image is made again, once.
    final undone = await _render(
      tester,
      _painter(images: images, strokes: [..._drawing]),
    );
    expect(SheetImages.debugFullBakes, 2);
    expect(undone.compare(await _render(tester, _painter())), (0, 0));
    images.dispose();
  });

  testWidgets('the element being taken lies between two images', (
    tester,
  ) async {
    final images = SheetImages();
    final offset = ValueNotifier(const Offset(30, 12));
    for (final step in const [Offset(30, 12), Offset(44, 20), Offset(-8, 5)]) {
      offset.value = step;
      final direct = await _render(
        tester,
        _painter(selectedIndex: 1, selectionOffset: ValueNotifier(step)),
      );
      final kept = await _render(
        tester,
        _painter(images: images, selectedIndex: 1, selectionOffset: offset),
      );
      final (_, most) = kept.compare(direct);
      expect(most, lessThanOrEqualTo(1));
    }
    expect(SheetImages.debugFullBakes, 1);
    // Let go where it is: one image again, exactly the sheet.
    offset.value = Offset.zero;
    final dropped = await _render(
      tester,
      _painter(images: images, selectedIndex: 1, selectionOffset: offset),
    );
    expect(dropped.compare(await _render(tester, _painter())), (0, 0));
    expect(images.debugImageCount, 1);
    images.dispose();
  });

  testWidgets('the images follow a moving view and are made again after it', (
    tester,
  ) async {
    final images = SheetImages();
    await _render(tester, _painter(images: images));
    final closer = _zoomed(1.6, x: 90, y: 100);
    final moving = await _render(
      tester,
      _painter(images: images, viewport: closer, viewMoving: true),
    );
    expect(SheetImages.debugFullBakes, 1);
    final exact = await _render(tester, _painter(viewport: closer));
    // Enlarged, the image is softer, nothing more.
    expect(moving.farFrom(exact, 64), lessThan(.04));
    final settled = await _render(
      tester,
      _painter(images: images, viewport: closer),
    );
    expect(SheetImages.debugFullBakes, 2);
    expect(settled.compare(exact), (0, 0));
    images.dispose();
  });

  testWidgets('what the images did not hold comes from the whole sheet', (
    tester,
  ) async {
    final images = SheetImages();
    // Close to one corner: most of the sheet lies outside the area.
    await _render(
      tester,
      _painter(images: images, viewport: _zoomed(3, x: 40, y: 40)),
    );
    expect(images.debugImageCount, 1);
    final moving = await _render(
      tester,
      _painter(images: images, viewport: _fit(), viewMoving: true),
    );
    expect(SheetImages.debugFullBakes, 1);
    expect(images.debugImageCount, 2);
    final exact = await _render(tester, _painter());
    expect(moving.farFrom(exact, 64), lessThan(.05));
    images.dispose();
  });

  testWidgets('a sheet too large for images is painted as without them', (
    tester,
  ) async {
    final images = SheetImages();
    final recorder = ui.PictureRecorder();
    final kept = images.paint(
      Canvas(recorder),
      const Size(5000, 3000),
      pixelRatio: 2,
      viewport: _fit(),
      viewMoving: false,
      paperRgb: 0xffffff,
      background: null,
      strokes: _drawing,
      paintOrder: _all(_drawing),
      split: _drawing.length,
      paintLive: (_) {},
    );
    recorder.endRecording().dispose();
    expect(kept, isFalse);
    expect(images.debugImageCount, 0);
    // So is every sheet while the tests ask for it.
    SheetImages.debugPaintWithoutImages = true;
    final direct = await _render(tester, _painter());
    final without = await _render(tester, _painter(images: images));
    expect(without.compare(direct), (0, 0));
    expect(SheetImages.debugFullBakes, 0);
    images.dispose();
  });

  testWidgets('dropped images are made again at the next frame', (
    tester,
  ) async {
    final images = SheetImages();
    await _render(tester, _painter(images: images));
    images.drop();
    expect(images.debugImageCount, 0);
    final again = await _render(tester, _painter(images: images));
    expect(SheetImages.debugFullBakes, 2);
    expect(again.compare(await _render(tester, _painter())), (0, 0));
    images.dispose();
  });

  group('in the studio', () {
    final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

    testWidgets('each trait is drawn onto the image; undoing makes it again', (
      tester,
    ) async {
      final studio = StudioDriver(tester);
      await studio.start();
      SheetImages.debugFullBakes = 0;
      SheetImages.debugAdditions = 0;
      for (var trait = 0; trait < 4; trait++) {
        final y = -60.0 + trait * 40;
        final gesture = await tester.startGesture(
          studio.sheetCenter + Offset(-120, y),
        );
        for (var step = 1; step <= 6; step++) {
          await gesture.moveTo(
            studio.sheetCenter + Offset(-120 + step * 40, y),
          );
          await tester.pump();
        }
        await gesture.up();
        await tester.pumpAndSettle();
      }
      studio.expectCount(4);
      expect(SheetImages.debugFullBakes, 0);
      expect(SheetImages.debugAdditions, 4);
      await studio.tap('undo');
      studio.expectCount(3);
      expect(SheetImages.debugFullBakes, 1);
      await studio.finish();
    }, skip: !available);

    testWidgets('two fingers move the images; they are made again after', (
      tester,
    ) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1180, 820));
      await studio.drag(const Offset(-80, -30), const Offset(90, 40));
      SheetImages.debugFullBakes = 0;
      final center = studio.sheetCenter;
      final first = await tester.startGesture(
        center - const Offset(60, 0),
        kind: PointerDeviceKind.touch,
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(60, 0),
        kind: PointerDeviceKind.touch,
        pointer: 2,
      );
      await tester.pump();
      for (var step = 0; step < 6; step++) {
        await first.moveBy(const Offset(-10, 2));
        await second.moveBy(const Offset(10, 2));
        await tester.pump();
      }
      expect(SheetImages.debugFullBakes, 0);
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(SheetImages.debugFullBakes, 1);
      expect(tester.takeException(), isNull);
      await studio.finish();
    }, skip: !available);

    testWidgets('at a pixel ratio of 2 the sheet is the same with or without '
        'images', (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(2200, 1520);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        EduPaintApp(files: MemoryFiles(), recoveryStorage: MemoryRecovery()),
      );
      await tester.pumpAndSettle();
      final surface = find.byKey(const Key('drawingSurface'));
      final center = tester.getCenter(surface);
      for (final (from, to) in const [
        (Offset(-150, -40), Offset(120, 60)),
        (Offset(-60, 80), Offset(140, -70)),
        (Offset(30, -90), Offset(-110, 50)),
      ]) {
        final gesture = await tester.startGesture(center + from);
        await gesture.moveTo(center + (from + to) / 2 + const Offset(13, -7));
        await gesture.moveTo(center + to);
        await gesture.up();
        await tester.pumpAndSettle();
      }
      final boundary = tester.renderObject(
        find.byKey(const Key('sheetPicture')),
      ) as RenderRepaintBoundary;
      Future<Uint8List> picture() async => (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          return (await image.toByteData())!.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      }))!;
      final kept = await picture();
      SheetImages.debugFullBakes = 0;
      SheetImages.debugPaintWithoutImages = true;
      boundary.markNeedsPaint();
      await tester.pump();
      final direct = await picture();
      // Painted without them indeed: they were let go, and come back.
      SheetImages.debugPaintWithoutImages = false;
      boundary.markNeedsPaint();
      await tester.pump();
      expect(SheetImages.debugFullBakes, 1);
      expect(kept.length, direct.length);
      var differing = 0;
      for (var offset = 0; offset < kept.length; offset++) {
        if (kept[offset] != direct[offset]) differing++;
      }
      expect(differing, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    }, skip: !available);
  });
}
