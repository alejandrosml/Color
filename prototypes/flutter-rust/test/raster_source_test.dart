// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/raster_source.dart';
import 'package:flutter_test/flutter_test.dart';

final _fixtures = Directory(
  Platform.environment['COLOR_IMPORT_FIXTURES'] ??
      '${Directory.current.path}/test/fixtures/raster',
);

void main() {
  final manifest = jsonDecode(
    File('${_fixtures.path}/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final fixtures = (manifest['fixtures'] as List).cast<Map<String, dynamic>>();
  final timings = <String, Object?>{};

  tearDownAll(() async {
    final destination = Platform.environment['COLOR_IMPORT_REPORT'];
    if (destination == null) {
      return;
    }
    final output = File(destination);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Isolated Flutter test engine; small generated fixtures, not full application or platform qualification.',
        'fixture_count': fixtures.length,
        'timings_microseconds': timings,
      }),
    );
  });

  for (final fixture in fixtures) {
    final name = fixture['file'] as String;
    final accepted = {
      'valid',
      'synthetic_metadata',
      'color_profile',
      'qualification',
    }.contains(fixture['category']);
    testWidgets('${accepted ? 'normalizes' : 'rejects'} $name', (tester) async {
      await tester.runAsync(() async {
        final bytes = await File('${_fixtures.path}/$name').readAsBytes();
        if (!accepted) {
          var created = 0;
          final previous = ui.Image.onCreate;
          ui.Image.onCreate = (image) {
            created++;
            previous?.call(image);
          };
          final watch = Stopwatch()..start();
          try {
            await expectLater(
              normaliseRaster(bytes),
              throwsA(isA<FormatException>()),
            );
            expect(
              created,
              0,
              reason:
                  'Malformed input must fail before a decoded image exists.',
            );
            timings[name] = {
              'rejected_before_image': true,
              'total': watch.elapsedMicroseconds,
            };
          } finally {
            ui.Image.onCreate = previous;
          }
          return;
        }
        final result = await normaliseRaster(bytes);
        ImportedBackground? reopened;
        try {
          expect([result.width, result.height], fixture['display_size']);
          expect(_chunkTypes(result.pngBytes), [
            'IHDR',
            'sRGB',
            'IDAT',
            'IEND',
          ]);
          expect(result.pngBytes[24], 8);
          expect([2, 6], contains(result.pngBytes[25]));
          expect(result.pngBytes[28], 0);
          expect(result.image.colorSpace, ui.ColorSpace.sRGB);
          expect(result.timingsMicroseconds, contains('quantize_srgb8'));
          expect(() => result.pngBytes[0] = 0, throwsUnsupportedError);
          if (fixture['pixel_probes'] case final List probes) {
            await _checkProbes(
              result.image,
              probes,
              jpegTolerance: fixture['jpeg_tolerance'] as int?,
            );
          }
          reopened = await decodeCanonicalBackground(result.pngBytes);
          expect(
            [reopened.width, reopened.height],
            [result.width, result.height],
          );
          final first = await result.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final second = await reopened.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(
            first!.buffer.asUint8List(),
            second!.buffer.asUint8List(),
            reason:
                'First display and reopening use identical normalized pixels.',
          );
          timings[name] = result.timingsMicroseconds;
        } finally {
          reopened?.dispose();
          result.dispose();
          result.dispose();
        }
        expect(() => result.image, throwsStateError);
      });
    });
  }

  testWidgets(
    'input snapshot, independent image clone, and serialized operations',
    (tester) async {
      await tester.runAsync(() async {
        final bytes = await File('${_fixtures.path}/rgb-asymmetric.png')
            .readAsBytes();
        final pending = normaliseRaster(bytes);
        bytes.fillRange(0, bytes.length, 0);
        await expectLater(normaliseRaster(bytes), throwsStateError);
        final result = await pending;
        final clone = result.image.clone();
        result.dispose();
        try {
          expect(clone.width, 32);
          expect(
            await clone.toByteData(format: ui.ImageByteFormat.png),
            isNotNull,
          );
        } finally {
          clone.dispose();
        }
        await expectLater(normaliseRaster(bytes), throwsFormatException);
      });
    },
  );

  testWidgets('Mac release RGBA16 export normalizes to tagged sRGB8 and reopens', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Authentic GPU-generated PNG from the release application. A headless
      // test still cannot reproduce its GPU snapshot format; native app
      // qualification must also inspect the raster-rendered/raster-png events.
      final bytes = await File(
        '${Directory.current.path}/test/fixtures/raster/macos-release-rgba16.png',
      ).readAsBytes();
      expect(bytes[24], 16);
      expect(bytes[25], 6);
      final result = await normaliseRaster(bytes);
      ImportedBackground? reopened;
      try {
        expect((result.width, result.height), (2400, 1600));
        expect(result.pngBytes[24], 8);
        expect(result.pngBytes[25], 6);
        expect(result.pngBytes[28], 0);
        expect(result.image.colorSpace, ui.ColorSpace.sRGB);
        final chunks = _chunkTypes(result.pngBytes);
        expect(chunks.first, 'IHDR');
        expect(chunks.where((type) => type == 'sRGB'), hasLength(1));
        expect(chunks.last, 'IEND');
        expect(chunks.toSet(), {'IHDR', 'sRGB', 'IDAT', 'IEND'});
        expect(result.timingsMicroseconds, contains('quantize_srgb8'));
        reopened = await decodeCanonicalBackground(result.pngBytes);
        final first = await result.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final second = await reopened.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(
          first!.buffer.asUint8List(first.offsetInBytes, first.lengthInBytes),
          orderedEquals(
            second!.buffer.asUint8List(
              second.offsetInBytes,
              second.lengthInBytes,
            ),
          ),
        );
      } finally {
        reopened?.dispose();
        result.dispose();
      }
    });
  });

  testWidgets(
    'P3 alpha conversion releases intermediates and preserves clone ownership',
    (tester) async {
      await tester.runAsync(() async {
        final liveImages = <ui.Image>{};
        final livePictures = <ui.Picture>{};
        final previousImageCreate = ui.Image.onCreate;
        final previousImageDispose = ui.Image.onDispose;
        final previousPictureCreate = ui.Picture.onCreate;
        final previousPictureDispose = ui.Picture.onDispose;
        ui.Image.onCreate = (image) {
          liveImages.add(image);
          previousImageCreate?.call(image);
        };
        ui.Image.onDispose = (image) {
          liveImages.remove(image);
          previousImageDispose?.call(image);
        };
        ui.Picture.onCreate = (picture) {
          livePictures.add(picture);
          previousPictureCreate?.call(picture);
        };
        ui.Picture.onDispose = (picture) {
          livePictures.remove(picture);
          previousPictureDispose?.call(picture);
        };
        ImportedBackground? result;
        ui.Image? clone;
        try {
          final fixture = fixtures.singleWhere(
            (fixture) => fixture['file'] == 'icc-p3-alpha.png',
          );
          result = await normaliseRaster(
            await File('${_fixtures.path}/icc-p3-alpha.png').readAsBytes(),
          );
          expect(result.pngBytes[24], 8);
          expect(result.image.colorSpace, ui.ColorSpace.sRGB);
          // Independent LittleCMS references include transparent, opaque, and
          // half-transparent P3 colors. They catch relabeling and straight-alpha
          // pixels wrongly passed to the premultiplied raw descriptor.
          await _checkProbes(result.image, fixture['pixel_probes'] as List);
          expect(liveImages, {result.image});
          expect(livePictures, isEmpty);
          clone = result.image.clone();
          result.dispose();
          expect(liveImages, {clone});
          await _checkProbes(clone, fixture['pixel_probes'] as List);
          clone.dispose();
          clone = null;
          expect(liveImages, isEmpty);
        } finally {
          clone?.dispose();
          result?.dispose();
          ui.Image.onCreate = previousImageCreate;
          ui.Image.onDispose = previousImageDispose;
          ui.Picture.onCreate = previousPictureCreate;
          ui.Picture.onDispose = previousPictureDispose;
        }
      });
    },
  );

  testWidgets(
    'canonical reopening rejects source-only formats and ICC metadata',
    (tester) async {
      await tester.runAsync(() async {
        for (final name in [
          'jpeg-baseline.jpg',
          'palette-alpha.png',
          'gray-16-qualification.png',
          'icc-srgb.png',
          'synthetic-tuxpaint-private-chunks.png',
        ]) {
          await expectLater(
            decodeCanonicalBackground(
              await File('${_fixtures.path}/$name').readAsBytes(),
            ),
            throwsFormatException,
            reason: name,
          );
        }
        final result = await decodeCanonicalBackground(
          await File('${_fixtures.path}/rgba-asymmetric.png').readAsBytes(),
        );
        result.dispose();
      });
    },
  );
}

Future<void> _checkProbes(
  ui.Image image,
  List<dynamic> probes, {
  int? jpegTolerance,
}) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(data, isNotNull);
  final bytes = data!.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  for (final probe in probes.cast<Map<String, dynamic>>()) {
    final xy = (probe['xy'] as List).cast<int>();
    final expected = (probe['rgba'] as List).cast<int>();
    final white = (probe['rgb_on_white'] as List).cast<int>();
    // Premultiplication quantization can change RGB under a small alpha. Compare
    // visible source-over-white appearance and alpha, never hidden alpha=0 RGB.
    final tolerance =
        (jpegTolerance ?? probe['tolerance_per_channel'] as int) + 1;
    final offset = (xy[1] * image.width + xy[0]) * 4;
    final alpha = bytes[offset + 3];
    expect(alpha, closeTo(expected[3], 1), reason: 'alpha at $xy');
    for (var channel = 0; channel < 3; channel++) {
      final visible = bytes[offset + channel] + 255 - alpha;
      expect(
        visible,
        closeTo(white[channel], tolerance),
        reason: 'visible channel $channel at $xy',
      );
    }
  }
}

List<String> _chunkTypes(Uint8List bytes) {
  final types = <String>[];
  for (var cursor = 8; cursor < bytes.length;) {
    final length = ByteData.sublistView(bytes).getUint32(cursor);
    types.add(String.fromCharCodes(bytes.sublist(cursor + 4, cursor + 8)));
    cursor += 12 + length;
  }
  return types;
}
