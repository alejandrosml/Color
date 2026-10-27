// SPDX-License-Identifier: MIT
// The catalogue is read from the real Rust library, never from a copy.
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/color_palette.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/stamp_catalog.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('the core catalogue parses into stamps with French names', () {
    final text = RustDocument.readStampCatalog();
    final catalog = StampCatalog.parse(text);
    expect(catalog.stamps.length, greaterThanOrEqualTo(24));
    expect(
      catalog.stamps.length,
      text.split('\n').where((line) => line.isNotEmpty).length,
    );
    for (final (index, stamp) in catalog.stamps.indexed) {
      expect(stamp.id, index);
      expect(stamp.layers, isNotEmpty);
      expect(stamp.label, isNotEmpty);
      // Every stamp of this catalogue has a real name, not a raw key.
      expect(stamp.label, isNot(stamp.key), reason: stamp.key);
      expect(identical(catalog[index], stamp), isTrue);
    }
    expect(catalog.stamps.take(3).map((stamp) => stamp.key), [
      'etoile',
      'coeur',
      'soleil',
    ]);
    expect(catalog.stamps.take(3).map((stamp) => stamp.label), [
      'Étoile',
      'Cœur',
      'Soleil',
    ]);
    expect(
      catalog.stamps.map((stamp) => stamp.label).toSet(),
      hasLength(catalog.stamps.length),
    );
    expect(catalog[-1], isNull);
    expect(catalog[catalog.stamps.length], isNull);
    expect(identical(StampCatalog.instance, StampCatalog.instance), isTrue);
  }, skip: !available);

  test('shades use the exact integer arithmetic of the core', () {
    expect(stampDarkRgb(0x477fb2), 0x31587c);
    expect(stampLightRgb(0x477fb2), 0xb5cbe0);
    expect(stampDarkRgb(0xffffff), 0xb2b2b2);
    expect(stampLightRgb(0x000000), 0x999999);
    expect(stampDarkRgb(0), 0);
    expect(stampLightRgb(0xffffff), 0xffffff);
    expect(const StampPaint(StampTone.none).resolve(0x123456), isNull);
    expect(const StampPaint(StampTone.primary).resolve(0x123456), 0x123456);
    expect(const StampPaint(StampTone.fixed, 0x293d4b).resolve(0x1), 0x293d4b);
  });

  test('a malformed catalogue is refused instead of half understood', () {
    for (final text in [
      '',
      '\n',
      '0|cle',
      '1|cle|P,-,0,M 0 0 L 1 1',
      '0||P,-,0,M 0 0 L 1 1',
      '0|cle|',
      '0|cle|P,-,0',
      '0|cle|X,-,0,M 0 0 L 1 1',
      '0|cle|#12345,-,0,M 0 0 L 1 1',
      '0|cle|P,-,abc,M 0 0 L 1 1',
      '0|cle|P,-,17,M 0 0 L 1 1',
      '0|cle|P,-,0,M 0 0 H 4',
      '0|cle|P,-,0,M 0 0 L 1',
      '0|cle|P,-,0,M 0 x',
      '0|cle|P,-,0,M 0 0 L 1 1\n2|autre|P,-,0,M 0 0 L 1 1',
    ]) {
      expect(
        () => StampCatalog.parse(text),
        throwsFormatException,
        reason: text,
      );
    }
    final minimal = StampCatalog.parse(
      '0|nouveau|P,#293d4b,4,M 10 10 L 90 10 Q 90 90 50 90 C 20 90 10 60 10 10 Z\n',
    );
    expect(minimal.stamps.single.key, 'nouveau');
    // A stamp added to the core later is still shown, under its key.
    expect(minimal.stamps.single.label, 'Nouveau');
  });

  testWidgets('every stamp paints inside its box with the chosen colour', (
    tester,
  ) async {
    final catalog = StampCatalog.instance;
    await tester.runAsync(() async {
      for (final stamp in catalog.stamps) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        stamp.paint(canvas, const Rect.fromLTWH(20, 10, 60, 60), 0x00ff00);
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 80);
        final bytes = (await image.toByteData())!;
        var painted = 0;
        var outside = 0;
        for (var y = 0; y < 80; y++) {
          for (var x = 0; x < 100; x++) {
            if (bytes.getUint8((y * 100 + x) * 4 + 3) == 0) continue;
            painted++;
            // Outlines may exceed the box by half their width, never more.
            if (x < 16 || x > 84 || y < 6 || y > 74) outside++;
          }
        }
        expect(painted, greaterThan(300), reason: stamp.key);
        expect(outside, 0, reason: '${stamp.key} leaves its box');
        image.dispose();
        picture.dispose();
      }
    });
  }, skip: !available);

  // CIE L*a*b* of an sRGB colour, for a plain distance between two colours.
  List<double> lab(int rgb) {
    double linear(int channel) {
      final value = channel / 255;
      return value <= .04045
          ? value / 12.92
          : math.pow((value + .055) / 1.055, 2.4).toDouble();
    }

    final r = linear((rgb >> 16) & 0xff);
    final g = linear((rgb >> 8) & 0xff);
    final b = linear(rgb & 0xff);
    double f(double t) =>
        t > .008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
    final x = f((.4124 * r + .3576 * g + .1805 * b) / .95047);
    final y = f(.2126 * r + .7152 * g + .0722 * b);
    final z = f((.0193 * r + .1192 * g + .9505 * b) / 1.08883);
    return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
  }

  double distance(int first, int second) {
    final a = lab(first);
    final b = lab(second);
    return math.sqrt(
      math.pow(a[0] - b[0], 2) +
          math.pow(a[1] - b[1], 2) +
          math.pow(a[2] - b[2], 2),
    );
  }

  test(
    'no bow of the rainbow melts into a sheet filled with a named colour',
    () {
      // The measure itself: identical colours are at 0, black and white at 100.
      expect(distance(0xa8d8f0, 0xa8d8f0), 0);
      expect(distance(0x000000, 0xffffff), closeTo(100, .01));
      final rainbow = StampCatalog.instance[23]!;
      expect(rainbow.key, 'arcenciel');
      expect(rainbow.takesColour, isFalse);
      final bows = [
        for (final layer in rainbow.layers) layer.stroke.resolve(0x000000)!,
      ];
      expect(bows.toSet(), hasLength(4));
      for (final bow in bows) {
        for (final named in [...paintColors, ...morePaintColors]) {
          // The bows used to be « Prairie » and « Ciel » themselves, and a
          // near « Soleil » (at 6): on such a sheet, a bow was gone.
          expect(
            distance(bow, named.rgb),
            greaterThanOrEqualTo(15),
            reason: '${bow.toRadixString(16)} on ${named.name}',
          );
        }
      }
      // Two neighbours stay easy to tell apart.
      for (var index = 1; index < bows.length; index++) {
        expect(distance(bows[index - 1], bows[index]), greaterThan(30));
      }
    },
    skip: !available,
  );
}
