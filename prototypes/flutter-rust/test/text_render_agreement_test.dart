// SPDX-License-Identifier: MIT
// The sheet and the PNG export paint every line of a text where the SVG
// export writes its baseline. With the bundled font, whose letters sit on a
// baseline: the squares of the test font would hide a drift. Found by the
// independent review of Color 0.7.0: the engine rounds the height of a line
// to a whole number, and twelve small lines ended four units too high.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/png_export.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/size_choice.dart';
import 'package:edupaint_flutter_study/text_layout.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  testWidgets('PNG and SVG place every line of a text at the same height', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await File('fonts/DejaVuSans.ttf').readAsBytes();
      final loader = FontLoader(colorTextFontFamily)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    });
    // The three sizes of the studio on its usual sheet, one size reached
    // with « Plus petit », and one whose line height is a whole number.
    final sizes = [
      for (final choice in ObjectSize.values)
        textSizeFor(choice, width: 1200, height: 800),
      56 * 0.8,
      40.0,
    ];
    expect(sizes, [32, 56, 96, closeTo(44.8, 1e-9), 40]);
    for (final size in sizes) {
      final lines = (700 / (colorTextLineHeight * size)).floor();
      final document = RustDocument();
      try {
        final text = List.filled(lines, 'HHH').join('\n');
        final layout = TextLayout(text, size: size, rgb: 0);
        final box = textBoxAt(
          const DocumentPoint(100, 60),
          layout,
          pageWidth: 1200,
          pageHeight: 800,
        )!;
        document.addText(box.first, box.second, text: text, rgb: 0, size: size);
        final svgBaselines = RegExp(r'<tspan x="[^"]*" y="([^"]*)"')
            .allMatches(document.exportSvg())
            .map((match) => double.parse(match.group(1)!))
            .toList();
        expect(svgBaselines, hasLength(lines));
        final png = (await tester.runAsync(
          () => exportDocumentPng(
            document.visibleStrokes,
            width: document.width,
            height: document.height,
          ),
        ))!;
        final data = (await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(png);
          final image = (await codec.getNextFrame()).image;
          try {
            return await image.toByteData();
          } finally {
            image.dispose();
            codec.dispose();
          }
        }))!;
        // Dark pixels in the columns of the first letter.
        bool ink(int y) {
          for (var x = 100; x < 100 + size ~/ 2; x++) {
            if (data.getUint8((y * 1200 + x) * 4) < 128) return true;
          }
          return false;
        }

        // The foot of an H stands on the baseline: the row under the last
        // inked one of each line.
        final pngBaselines = <int>[
          for (var y = 0; y < 799; y++)
            if (ink(y) && !ink(y + 1)) y + 1,
        ];
        expect(pngBaselines, hasLength(lines), reason: 'size $size');
        for (var line = 0; line < lines; line++) {
          expect(
            pngBaselines[line],
            closeTo(svgBaselines[line], 1),
            reason: 'size $size, line ${line + 1} of $lines',
          );
        }
        // Nothing is painted outside the box that the core stores.
        final first = [
          for (var y = 0; y < 800; y++)
            if (ink(y)) y,
        ].first;
        expect(first, greaterThanOrEqualTo(box.first.y.floor()));
        expect(pngBaselines.last, lessThanOrEqualTo(box.second.y.ceil()));
      } finally {
        document.dispose();
      }
    }
  }, skip: !available);
}
