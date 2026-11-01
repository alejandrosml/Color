// SPDX-License-Identifier: MIT
// What a frame of a trait being drawn costs to rasterize, with and without
// the images of the sheet (F-01), for drawings of growing size. Started on
// demand only:
//
//   COLOR_MEASURE=1 flutter test test/measure_sheet_frames_test.dart
//
// The rasterizer of the tests is the software one of the engine: the times
// are not those of a device, but they grow, or not, with the drawing as a
// device's do. One line of JSON per size of drawing.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/draft_stroke.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/sheet_images.dart';
import 'package:edupaint_flutter_study/studio_painters.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(1100, 700);
const _ratio = 2.0;
const _frames = 24;

List<RenderedElement> _drawing(int traits) {
  final random = math.Random(3);
  return [
    for (var trait = 0; trait < traits; trait++)
      () {
        var x = random.nextDouble() * 1200;
        var y = random.nextDouble() * 800;
        return RenderedElement(
          StrokeData(
            [
              for (var point = 0; point < 40; point++)
                DocumentPoint(
                  x = (x + random.nextDouble() * 24 - 12).clamp(0, 1200),
                  y = (y + random.nextDouble() * 24 - 12).clamp(0, 800),
                ),
            ],
            random.nextInt(0x1000000),
            6 + random.nextDouble() * 10,
          ),
        );
      }(),
  ];
}

DocumentPainter _frame(
  List<RenderedElement> strokes,
  List<DocumentPoint> draft,
  SheetImages? images,
) => DocumentPainter(
  viewport: DocumentViewport(
    viewWidth: _size.width,
    viewHeight: _size.height,
    padding: 28,
  ),
  paperRgb: 0xffffff,
  background: null,
  strokes: strokes,
  paintOrder: [for (var index = 0; index < strokes.length; index++) index],
  draft: SheetDraft(
    points: draft,
    stroke: DraftStroke.through(draft),
    rgb: 0xd75e56,
  ),
  repaint: ValueNotifier(0),
  revision: 0,
  selectedIndex: null,
  selectionBounds: null,
  selectionOffset: ValueNotifier(Offset.zero),
  images: images,
  pixelRatio: _ratio,
);

double _median(List<int> micros) {
  final sorted = [...micros]..sort();
  return sorted[sorted.length ~/ 2] / 1000;
}

void main() {
  final asked = Platform.environment['COLOR_MEASURE'] != null;

  testWidgets('a frame of a trait, with and without the images', (
    tester,
  ) async {
    for (final traits in [250, 1000, 2000, 4000]) {
      final strokes = _drawing(traits);
      final result = <String, Object>{'traits': traits};
      for (final kept in [false, true]) {
        final images = kept ? SheetImages() : null;
        final micros = <int>[];
        await tester.runAsync(() async {
          for (var frame = 0; frame < _frames + 2; frame++) {
            final draft = [
              for (var point = 0; point <= frame + 1; point++)
                DocumentPoint(100 + point * 30.0, 300 + (point % 3) * 20.0),
            ];
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder)..scale(_ratio);
            _frame(strokes, draft, images).paint(canvas, _size);
            final picture = recorder.endRecording();
            final watch = Stopwatch()..start();
            final image = await picture.toImage(
              (_size.width * _ratio).ceil(),
              (_size.height * _ratio).ceil(),
            );
            watch.stop();
            image.dispose();
            picture.dispose();
            // The first two frames make the images, then warm up.
            if (frame >= 2) micros.add(watch.elapsedMicroseconds);
          }
        });
        images?.dispose();
        result[kept ? 'withImagesMs' : 'withoutImagesMs'] = _median(micros);
      }
      // ignore: avoid_print
      print(jsonEncode(result));
    }
  }, skip: !asked);
}
