// SPDX-License-Identifier: MIT
// The small picture of a card, painted and encoded by the real engine.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/gallery_storage.dart';
import 'package:edupaint_flutter_study/gallery_thumbnail.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

const _white = 0xffffffff;

void main() {
  test('the longer side measures 320 at most and nothing is enlarged', () {
    expect(thumbnailSize(1200, 800), (width: 320, height: 213));
    expect(thumbnailSize(800, 1200), (width: 213, height: 320));
    expect(thumbnailSize(800, 800), (width: 320, height: 320));
    expect(thumbnailSize(320, 200), (width: 320, height: 200));
    expect(thumbnailSize(100, 50), (width: 100, height: 50));
    expect(thumbnailSize(1, 1), (width: 1, height: 1));
    // A very long sheet keeps at least one pixel across.
    expect(thumbnailSize(16384, 1), (width: 320, height: 1));
    expect(thumbnailSize(1, 16384), (width: 1, height: 320));
    expect(thumbnailSize(16384, 16384), (width: 320, height: 320));
    expect(thumbnailSize(1200, 800, maxSide: 64), (width: 64, height: 43));
  });

  test('the largest picture fits the album even if it does not compress', () {
    final largest = thumbnailSize(16384, 16384);
    // Four bytes per pixel and one filter byte per line, before compression.
    final raw = largest.height * (largest.width * 4 + 1);
    expect(raw, lessThan(GalleryStorage.maxThumbnailBytes - 64 * 1024));
  });

  testWidgets('a white sheet gives a white picture of the sheet’s shape', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await renderThumbnail(const [], width: 1200, height: 800);
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final header = ByteData.sublistView(bytes);
      expect(header.getUint32(16), 320);
      expect(header.getUint32(20), 213);
      final pixels = await _decode(bytes);
      expect((pixels.width, pixels.height), (320, 213));
      expect(pixels.at(0, 0), _white);
      expect(pixels.at(160, 106), _white);
      expect(pixels.at(319, 212), _white);
      expect(bytes.length, lessThan(GalleryStorage.maxThumbnailBytes));
    });
  });

  testWidgets(
    'the picture shows the paper and the elements in their painting order',
    (tester) async {
      await tester.runAsync(() async {
        final elements = [
          // A large filled rectangle, then an oval painted over its corner.
          StrokeData(
            const [DocumentPoint(150, 150), DocumentPoint(600, 600)],
            0x477fb2,
            12,
            kind: VectorKind.rectangle,
            fillRgb: 0xeebf4e,
          ),
          StrokeData(
            const [DocumentPoint(450, 450), DocumentPoint(1050, 750)],
            0xd75e56,
            12,
            kind: VectorKind.ellipse,
            fillRgb: 0x78a66f,
          ),
          // A thick trait that leaves the sheet: it is cut at the edge.
          StrokeData(
            const [DocumentPoint(900, 150), DocumentPoint(1500, 150)],
            0x33484d,
            48,
          ),
        ];
        final pixels = await _decode(
          await renderThumbnail(
            elements,
            width: 1200,
            height: 800,
            paperRgb: 0xe69976,
          ),
        );
        expect((pixels.width, pixels.height), (320, 213));
        // 1200 units are 320 pixels: one pixel for 3.75 units.
        int at(double x, double y) =>
            pixels.at((x / 3.75).floor(), (y / 3.75).floor());
        expect(at(40, 40), 0xffe69976, reason: 'coloured paper');
        expect(at(1150, 500), 0xffe69976, reason: 'paper right of the oval');
        expect(at(300, 300), 0xffeebf4e, reason: 'inside of the rectangle');
        expect(at(750, 600), 0xff78a66f, reason: 'inside of the oval');
        expect(
          at(560, 590),
          0xff78a66f,
          reason: 'the oval, drawn later, covers the rectangle',
        );
        expect(at(1000, 150), 0xff33484d, reason: 'the trait');
        expect(at(1198, 150), 0xff33484d, reason: 'up to the edge');
      });
    },
  );

  testWidgets(
    'an image background is shown under the elements and stays the caller’s',
    (tester) async {
      await tester.runAsync(() async {
        // Left half red, right half blue, 4 × 2 pixels.
        final background = await _image(4, 2, (x, y) {
          return x < 2 ? 0xffff0000 : 0xff0000ff;
        });
        final elements = [
          StrokeData(
            const [DocumentPoint(180, 60), DocumentPoint(220, 100)],
            0x000000,
            2,
            kind: VectorKind.rectangle,
            fillRgb: 0x00ff00,
          ),
        ];
        final pixels = await _decode(
          await renderThumbnail(
            elements,
            width: 400,
            height: 200,
            background: background,
            maxSide: 200,
          ),
        );
        expect((pixels.width, pixels.height), (200, 100));
        expect(pixels.at(20, 50), 0xffff0000);
        expect(pixels.at(180, 50), 0xff0000ff);
        expect(pixels.at(100, 40), 0xff00ff00);
        // The caller's handle was only borrowed.
        expect(background.debugDisposed, isFalse);
        expect(background.width, 4);
        background.dispose();
      });
    },
  );

  testWidgets('a text and a stamp are part of the picture', (tester) async {
    await tester.runAsync(() async {
      final elements = [
        StrokeData(
          const [DocumentPoint(100, 100), DocumentPoint(500, 300)],
          0x6a4f99,
          160,
          kind: VectorKind.text,
          text: 'OO',
        ),
        StrokeData(
          const [DocumentPoint(700, 300), DocumentPoint(1000, 600)],
          0xd75e56,
          1,
          kind: VectorKind.stamp,
          stamp: 0,
        ),
      ];
      final pixels = await _decode(
        await renderThumbnail(elements, width: 1200, height: 800),
      );
      var violet = 0;
      var red = 0;
      for (var y = 0; y < pixels.height; y++) {
        for (var x = 0; x < pixels.width; x++) {
          final colour = pixels.at(x, y);
          if (colour == 0xff6a4f99) violet++;
          if (colour == 0xffd75e56) red++;
        }
      }
      expect(violet, greaterThan(40), reason: 'text ink');
      expect(red, greaterThan(40), reason: 'stamp ink');
      // Nothing is painted far from both.
      expect(pixels.at(10, 200), _white);
    });
  });

  testWidgets('a drawing that cannot be pictured is refused, nothing leaks', (
    tester,
  ) async {
    await tester.runAsync(() async {
      Future<Uint8List> attempt({
        List<StrokeData> elements = const [],
        int width = 1200,
        int height = 800,
        int paperRgb = whitePaper,
        int maxSide = 320,
      }) => renderThumbnail(
        elements,
        width: width,
        height: height,
        paperRgb: paperRgb,
        maxSide: maxSide,
      );
      await expectLater(attempt(width: 0), throwsArgumentError);
      await expectLater(attempt(width: 16385), throwsArgumentError);
      await expectLater(attempt(height: 0), throwsArgumentError);
      await expectLater(attempt(height: 16385), throwsArgumentError);
      await expectLater(attempt(maxSide: 15), throwsArgumentError);
      await expectLater(attempt(maxSide: 1025), throwsArgumentError);
      await expectLater(attempt(paperRgb: -1), throwsArgumentError);
      await expectLater(attempt(paperRgb: 0x1000000), throwsArgumentError);
      await expectLater(
        attempt(
          elements: [
            StrokeData(const [DocumentPoint(double.nan, 0)], 0, 4),
          ],
        ),
        throwsArgumentError,
      );
      final dot = StrokeData(const [DocumentPoint(1, 1)], 0, 4);
      await expectLater(
        attempt(elements: List.filled(10001, dot)),
        throwsArgumentError,
      );
      // The limits themselves are served.
      final long = await attempt(width: 16384, height: 1);
      final header = ByteData.sublistView(long);
      expect((header.getUint32(16), header.getUint32(20)), (320, 1));
    });
  });
}

Future<ui.Image> _image(
  int width,
  int height,
  int Function(int x, int y) argb,
) {
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final colour = argb(x, y);
      final offset = (y * width + x) * 4;
      pixels[offset] = (colour >> 16) & 0xff;
      pixels[offset + 1] = (colour >> 8) & 0xff;
      pixels[offset + 2] = colour & 0xff;
      pixels[offset + 3] = (colour >> 24) & 0xff;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

class _Pixels {
  _Pixels(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;

  /// Alpha, red, green and blue of one pixel, as 0xAARRGGBB.
  int at(int x, int y) {
    final offset = (y * width + x) * 4;
    return (rgba[offset + 3] << 24) |
        (rgba[offset] << 16) |
        (rgba[offset + 1] << 8) |
        rgba[offset + 2];
  }
}

Future<_Pixels> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return _Pixels(
      image.width,
      image.height,
      Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
  } finally {
    image?.dispose();
    codec.dispose();
  }
}
