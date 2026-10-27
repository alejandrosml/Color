// SPDX-License-Identifier: MIT
// The image of a drawing as it goes to the printer: its size, and what is
// painted in it. No Rust library is needed: the elements are given by hand.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/print_render.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a sheet is printed at twice its size while that stays within bounds',
    () {
      // The three sheets that « Nouveau » offers.
      expect(printImageSize(1200, 800), (
        width: 2400,
        height: 1600,
        scale: 2.0,
      ));
      expect(printImageSize(800, 1200), (
        width: 1600,
        height: 2400,
        scale: 2.0,
      ));
      expect(printImageSize(1200, 1200), (
        width: 2400,
        height: 2400,
        scale: 2.0,
      ));
      // The largest sheets that are still doubled: both bounds at once,
      // and the largest square.
      expect(printImageSize(2048, 1024), (
        width: 4096,
        height: 2048,
        scale: 2.0,
      ));
      expect(printImageSize(1448, 1448).scale, 2.0);
      expect(printImageSize(1449, 1449).scale, lessThan(2));
      expect(printImageSize(2049, 1000).scale, lessThan(2));
    },
  );

  test(
    'a larger sheet is printed as large as the bounds allow, never distorted',
    () {
      for (final (width, height) in [
        (4000, 3000),
        (3000, 4000),
        (4096, 4096),
        (8192, 200),
        (200, 8192),
        (2049, 2048),
        (5000, 5000),
      ]) {
        final size = printImageSize(width, height);
        final where = '$width × $height';
        expect(size.scale, lessThan(2), reason: where);
        expect(size.width, lessThanOrEqualTo(maxPrintDimension), reason: where);
        expect(
          size.height,
          lessThanOrEqualTo(maxPrintDimension),
          reason: where,
        );
        expect(
          size.width * size.height,
          lessThanOrEqualTo(maxPrintPixels),
          reason: where,
        );
        expect(size.width, greaterThanOrEqualTo(1), reason: where);
        expect(size.height, greaterThanOrEqualTo(1), reason: where);
        // The shape of the sheet, within the rounding of one pixel.
        expect(
          (size.width / size.height - width / height).abs(),
          lessThan(1.5 * (width / height) / size.height + 1.5 / size.height),
          reason: where,
        );
      }
      // 32 MiB at most are handed to the system.
      expect(maxPrintPixels * 4, 32 * 1024 * 1024);
    },
  );

  test('a sheet without a size is refused', () {
    expect(() => printImageSize(0, 10), throwsArgumentError);
    expect(() => printImageSize(10, 0), throwsArgumentError);
    expect(() => printImageSize(-1, -1), throwsArgumentError);
  });

  testWidgets(
    'the image is the opaque sheet, with its elements where they are',
    (tester) async {
      final image = (await tester.runAsync(
        () => renderDocumentForPrint(
          [
            // A filled square in the top left quarter.
            StrokeData(
              const [DocumentPoint(10, 10), DocumentPoint(40, 40)],
              0x112233,
              2,
              kind: VectorKind.rectangle,
              fillRgb: 0xd75e56,
            ),
          ],
          width: 100,
          height: 60,
          paperRgb: 0xeebf4e,
        ),
      ))!;
      expect(image.width, 200);
      expect(image.height, 120);
      expect(image.rgba, hasLength(200 * 120 * 4));
      List<int> pixel(int x, int y) {
        final offset = (y * image.width + x) * 4;
        return image.rgba.sublist(offset, offset + 4);
      }

      // The inside of the square, twice as large as on the sheet.
      expect(pixel(50, 50), [0xd7, 0x5e, 0x56, 255]);
      // Its outline, on the edge at 10 units: 20 pixels.
      expect(pixel(20, 50), [0x11, 0x22, 0x33, 255]);
      // The coloured paper, up to the last pixel of each corner.
      for (final (x, y) in [
        (0, 0),
        (199, 0),
        (0, 119),
        (199, 119),
        (150, 90),
      ]) {
        expect(pixel(x, y), [0xee, 0xbf, 0x4e, 255], reason: '$x, $y');
      }
      for (var index = 3; index < image.rgba.length; index += 4) {
        expect(image.rgba[index], 255);
      }
    },
  );

  testWidgets('the image under a drawing is printed under it', (tester) async {
    final image = (await tester.runAsync(() async {
      // A background of 4 by 2 pixels: green on the left, blue on the right.
      final pixels = Uint8List.fromList([
        for (var y = 0; y < 2; y++)
          for (var x = 0; x < 4; x++) ...[
            0,
            x < 2 ? 200 : 0,
            x < 2 ? 0 : 200,
            255,
          ],
      ]);
      final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: 4,
        height: 2,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final background = (await codec.getNextFrame()).image;
      try {
        return await renderDocumentForPrint(
          [
            StrokeData(
              const [DocumentPoint(0, 1), DocumentPoint(4, 1)],
              0xffffff,
              .5,
              kind: VectorKind.line,
            ),
          ],
          width: 4,
          height: 2,
          background: background,
        );
      } finally {
        background.dispose();
        codec.dispose();
        descriptor.dispose();
        buffer.dispose();
      }
    }))!;
    expect(image.width, 8);
    expect(image.height, 4);
    List<int> pixel(int x, int y) {
      final offset = (y * image.width + x) * 4;
      return image.rgba.sublist(offset, offset + 4);
    }

    expect(pixel(0, 0), [0, 200, 0, 255]);
    expect(pixel(7, 0), [0, 0, 200, 255]);
    expect(pixel(0, 3), [0, 200, 0, 255]);
    expect(pixel(7, 3), [0, 0, 200, 255]);
  });

  testWidgets('what cannot be a drawing is refused before the engine works', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await expectLater(
        renderDocumentForPrint(const [], width: 0, height: 10),
        throwsArgumentError,
      );
      await expectLater(
        renderDocumentForPrint(
          const [],
          width: 10,
          height: 10,
          paperRgb: 0x1000000,
        ),
        throwsArgumentError,
      );
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        Uint8List.fromList(List.filled(16, 255)),
      );
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: 2,
        height: 2,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final background = (await codec.getNextFrame()).image;
      try {
        // A background that is not the size of the sheet.
        await expectLater(
          renderDocumentForPrint(
            const [],
            width: 10,
            height: 10,
            background: background,
          ),
          throwsArgumentError,
        );
      } finally {
        background.dispose();
        codec.dispose();
        descriptor.dispose();
        buffer.dispose();
      }
    });
  });

  testWidgets('an empty sheet is a white page', (tester) async {
    final image = (await tester.runAsync(
      () => renderDocumentForPrint(const [], width: 3, height: 5),
    ))!;
    expect(image.width, 6);
    expect(image.height, 10);
    expect(image.rgba.every((byte) => byte == 255), isTrue);
  });
}
