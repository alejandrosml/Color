// SPDX-License-Identifier: MIT
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/png_export.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

const _white = 0xffffffff;

void main() {
  testWidgets(
    'PNG has its signature, logical dimensions and opaque white paper',
    (tester) async {
      await tester.runAsync(() async {
        final bytes = await exportDocumentPng([], width: 1200, height: 800);
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final header = ByteData.sublistView(bytes);
        expect(header.getUint32(16), 1200);
        expect(header.getUint32(20), 800);
        final pixels = await _decode(bytes);
        expect((pixels.width, pixels.height), (1200, 800));
        expect(pixels.at(0, 0), _white);
        expect(pixels.at(600, 400), _white);
        expect(pixels.at(1199, 799), _white);
      });
    },
  );

  testWidgets(
    'real rasterizer paints strokes, round dots, all shapes and fills',
    (tester) async {
      await tester.runAsync(() async {
        final elements = [
          StrokeData(const [DocumentPoint(0, 0)], 0xff0000, 12),
          StrokeData(
            const [
              DocumentPoint(10, 12),
              DocumentPoint(30, 12),
              DocumentPoint(30, 30),
            ],
            0x000000,
            6,
          ),
          StrokeData(
            const [DocumentPoint(58, 28), DocumentPoint(38, 8)],
            0x0000ff,
            4,
            kind: VectorKind.rectangle,
            fillRgb: 0x00aa00,
          ),
          StrokeData(
            const [DocumentPoint(8, 38), DocumentPoint(28, 58)],
            0x800080,
            4,
            kind: VectorKind.ellipse,
            fillRgb: 0xffff00,
          ),
          StrokeData(
            const [DocumentPoint(38, 48), DocumentPoint(55, 48)],
            0xff00ff,
            6,
            kind: VectorKind.line,
          ),
        ];
        final pixels = await _decode(
          await exportDocumentPng(elements, width: 64, height: 64),
        );
        expect(
          pixels.at(0, 0),
          0xffff0000,
          reason: 'a one-point stroke at the paper edge is a clipped red disk',
        );
        expect(
          pixels.at(5, 5),
          _white,
          reason: 'the dot is round, not a square',
        );
        expect(pixels.at(20, 12), 0xff000000);
        expect(pixels.at(30, 22), 0xff000000);
        expect(pixels.at(15, 20), _white);
        expect(
          pixels.at(38, 18),
          0xff0000ff,
          reason: 'the rectangle keeps its outline',
        );
        expect(
          pixels.at(48, 18),
          0xff00aa00,
          reason: 'reverse corner order is normalized',
        );
        expect(pixels.at(18, 48), 0xffffff00);
        expect(pixels.at(18, 38), 0xff800080);
        expect(
          pixels.at(8, 38),
          _white,
          reason: 'an ellipse does not paint its bounding-box corner',
        );
        expect(
          pixels.at(36, 48),
          0xffff00ff,
          reason: 'line has a round cap beyond its endpoint',
        );
        expect(pixels.at(35, 44), _white);
        expect(pixels.at(63, 63), _white);
      });
    },
  );

  testWidgets(
    'passive PNG observations preserve encoded pixels even when they fail',
    (tester) async {
      await tester.runAsync(() async {
        final elements = [
          StrokeData(const [DocumentPoint(12, 12)], 0x123456, 8),
        ];
        final baseline = await exportDocumentPng(
          elements,
          width: 24,
          height: 24,
        );
        final phases = <PngExportPhase>[];
        final observed = await exportDocumentPng(
          elements,
          width: 24,
          height: 24,
          onPhase: (phase) {
            phases.add(phase);
            throw StateError('Unavailable observation sink');
          },
        );
        expect((await _decode(observed)).rgba, (await _decode(baseline)).rgba);
        expect(phases, PngExportPhase.values);
      });
    },
  );

  testWidgets('unfilled forms preserve the paper and element order', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final pixels = await _decode(
        await exportDocumentPng(
          [
            StrokeData(
              const [DocumentPoint(4, 4), DocumentPoint(28, 28)],
              0x0033ff,
              2,
              kind: VectorKind.rectangle,
            ),
            StrokeData(
              const [DocumentPoint(36, 4), DocumentPoint(60, 28)],
              0xff3300,
              2,
              kind: VectorKind.ellipse,
            ),
            StrokeData(const [DocumentPoint(16, 48)], 0xff0000, 14),
            StrokeData(const [DocumentPoint(16, 48)], 0x0000ff, 6),
          ],
          width: 64,
          height: 64,
        ),
      );
      expect(pixels.at(16, 16), _white);
      expect(pixels.at(48, 16), _white);
      expect(pixels.at(16, 48), 0xff0000ff);
      expect(pixels.at(21, 48), 0xffff0000);
    });
  });

  testWidgets('two-times export scales geometry and stroke width', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final pixels = await _decode(
        await exportDocumentPng(
          [
            StrokeData(
              const [DocumentPoint(10, 10), DocumentPoint(20, 10)],
              0x0088cc,
              4,
              kind: VectorKind.line,
            ),
          ],
          width: 40,
          height: 24,
          scale: 2,
        ),
      );
      expect((pixels.width, pixels.height), (80, 48));
      expect(pixels.at(30, 20), 0xff0088cc);
      expect(
        pixels.at(30, 17),
        0xff0088cc,
        reason: 'four logical pixels become eight physical pixels',
      );
      expect(pixels.at(30, 14), _white);
      expect(
        pixels.at(15, 10),
        _white,
        reason: 'the coordinates are scaled too',
      );
    });
  });

  testWidgets('encoding uses an immutable snapshot of the input list', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final elements = [
        StrokeData(const [DocumentPoint(16, 16)], 0xdd3311, 8),
      ];
      final pending = exportDocumentPng(elements, width: 32, height: 32);
      elements.clear();
      final pixels = await _decode(await pending);
      expect(pixels.at(16, 16), 0xffdd3311);
    });
  });

  testWidgets(
    'background alpha, vector order and owned handle survive asynchronous export',
    (tester) async {
      await tester.runAsync(() async {
        final bytes = await File('test/fixtures/raster/rgba-asymmetric.png')
            .readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final source = (await codec.getNextFrame()).image;
        codec.dispose();
        final pending = exportDocumentPng(
          [
            StrokeData(const [DocumentPoint(27, 4)], 0xdd3311, 6),
          ],
          width: 32,
          height: 24,
          scale: 2,
          background: source,
        );
        source.dispose();
        final pixels = await _decode(await pending);
        expect((pixels.width, pixels.height), (64, 48));
        expect(
          pixels.at(8, 8),
          _white,
          reason: 'transparent pixels reveal white paper',
        );
        expect(
          pixels.at(54, 8),
          0xffdd3311,
          reason: 'vector dot paints above green background',
        );
        expect(
          pixels.at(54, 38),
          0xfff0c323,
          reason: 'opaque yellow is retained',
        );
        // Sample inside the constant-alpha patch, away from its x=16 boundary:
        // at 2x scale medium filtering interpolates across that boundary.
        final blended = pixels.at(34, 24);
        for (final (shift, expected) in [(16, 217), (8, 177), (0, 167)]) {
          expect(
            (blended >> shift) & 255,
            closeTo(expected, 1),
            reason: 'half-alpha source-over rounding',
          );
        }
        expect(blended >> 24, 255);
      });
    },
  );

  testWidgets(
    'background dimensions are checked without disposing the caller handle',
    (tester) async {
      await tester.runAsync(() async {
        final bytes = await File('test/fixtures/raster/rgb-asymmetric.png')
            .readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final source = (await codec.getNextFrame()).image;
        codec.dispose();
        try {
          await expectLater(
            exportDocumentPng([], width: 31, height: 24, background: source),
            throwsArgumentError,
          );
          final pixels = await _decode(
            await exportDocumentPng(
              [],
              width: 32,
              height: 24,
              background: source,
            ),
          );
          expect(pixels.at(4, 4), 0xffe62328);
        } finally {
          source.dispose();
        }
      });
    },
  );

  test(
    'PNG dimension and pixel limits are checked before allocating an image',
    () async {
      expect(canExportDocumentPng(width: 1200, height: 800, scale: 2), isTrue);
      expect(canExportDocumentPng(width: 8192, height: 2048), isTrue);
      expect(canExportDocumentPng(width: 2048, height: 2048, scale: 2), isTrue);
      for (final args in [
        (0, 800, 1),
        (-1, 20, 1),
        (8193, 1, 1),
        (8192, 2049, 1),
        (4097, 4097, 1),
        (4097, 1, 2),
        (1200, 800, 0),
        (1200, 800, 3),
        (0x7fffffffffffffff, 1, 2),
      ]) {
        expect(
          canExportDocumentPng(width: args.$1, height: args.$2, scale: args.$3),
          isFalse,
        );
        await expectLater(
          exportDocumentPng(
            [],
            width: args.$1,
            height: args.$2,
            scale: args.$3,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test('element and point limits also bound the render snapshot', () async {
    final dot = StrokeData(const [DocumentPoint(2, 2)], 0, 2);
    final fullStroke = StrokeData(
      List.filled(100000, const DocumentPoint(2, 2)),
      0,
      2,
    );
    final tooLongStroke = StrokeData(
      List.filled(100001, const DocumentPoint(2, 2)),
      0,
      2,
    );
    for (final elements in [
      List.filled(10001, dot),
      List.filled(11, fullStroke),
      [tooLongStroke],
    ]) {
      await expectLater(
        exportDocumentPng(elements, width: 64, height: 64),
        throwsArgumentError,
      );
    }
  });

  test('invalid geometry is rejected before rasterization', () async {
    final invalid = [
      StrokeData(const [], 0, 2),
      StrokeData(const [DocumentPoint(double.nan, 2)], 0, 2),
      StrokeData(const [DocumentPoint(2, 2)], 0, double.infinity),
      StrokeData(const [DocumentPoint(2, 2)], -1, 2),
      StrokeData(const [DocumentPoint(65, 2)], 0, 2),
      StrokeData(
        const [DocumentPoint(2, 2), DocumentPoint(2, 2)],
        0,
        2,
        kind: VectorKind.line,
      ),
      StrokeData(
        const [DocumentPoint(2, 2), DocumentPoint(2, 8)],
        0,
        2,
        kind: VectorKind.rectangle,
      ),
      StrokeData(
        const [DocumentPoint(2, 2), DocumentPoint(8, 8)],
        0,
        2,
        kind: VectorKind.line,
        fillRgb: 0,
      ),
    ];
    for (final element in invalid) {
      await expectLater(
        exportDocumentPng([element], width: 64, height: 64),
        throwsArgumentError,
      );
    }
  });
}

final class _Pixels {
  _Pixels(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;
  int at(int x, int y) {
    final i = (y * width + x) * 4;
    return rgba[i + 3] << 24 | rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2];
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
