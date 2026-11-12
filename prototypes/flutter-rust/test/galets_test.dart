// SPDX-License-Identifier: MIT
// « Les galets » (Color 1.2), without a studio: where the pebbles put the
// sheet in a window, which windows they are offered in, the ten elementary
// colours and their families, the five widths of a trait.
import 'package:edupaint_flutter_study/color_palette.dart';
import 'package:edupaint_flutter_study/decor.dart';
import 'package:edupaint_flutter_study/galets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GaletsLayout laid(
    Size window, {
    bool decor = false,
    bool bigSheet = false,
    double width = 1200,
    double height = 800,
    EdgeInsets safe = EdgeInsets.zero,
  }) => GaletsLayout(
    window: window,
    safe: safe,
    documentWidth: width,
    documentHeight: height,
    decor: decor,
    bigSheet: bigSheet,
  );

  test('the pebbles are offered to a wide window, with ordinary letters', () {
    bool offered(
      Size window, {
      double textScale = 1,
      bool phone = false,
      bool simple = false,
    }) => GaletsLayout.offered(
      window: window,
      textScale: textScale,
      phone: phone,
      simple: simple,
    );
    expect(offered(const Size(1440, 900)), isTrue);
    expect(offered(const Size(1366, 1024)), isTrue);
    expect(offered(const Size(1130, 600)), isTrue);
    // Narrower, lower, taller than wide: the studio of before, until the
    // pebbles are laid out for these windows.
    expect(offered(const Size(1129, 900)), isFalse);
    expect(offered(const Size(1440, 599)), isFalse);
    expect(offered(const Size(1200, 1300)), isFalse);
    expect(offered(const Size(1440, 900), textScale: 1.3), isFalse);
    expect(offered(const Size(1440, 900), phone: true), isFalse);
    expect(offered(const Size(1440, 900), simple: true), isFalse);
  });

  test('on a Mac with a decor, the sheet is the one of the mock-up', () {
    final layout = laid(const Size(1440, 900), decor: true);
    // 936 × 624, its foot 42 points above the line of the ground, which
    // lies 96 points above the foot of the window.
    expect(layout.band, 96);
    expect(layout.sheet, const Rect.fromLTWH(252, 138, 936, 624));
    expect(layout.decorFrame, const Size(1440, 804));
    expect(layout.top, 14);
    expect(layout.lineTop, 820);
  });

  test('the stage holds the sheet in its middle, across the window', () {
    for (final window in const [
      Size(1440, 900),
      Size(1130, 600),
      Size(1920, 1080),
      Size(1366, 1024),
    ]) {
      for (final decor in [true, false]) {
        for (final (width, height) in [(1200.0, 800.0), (800.0, 1200.0)]) {
          final layout = laid(
            window,
            decor: decor,
            width: width,
            height: height,
          );
          expect(layout.stage.left, 0);
          expect(layout.stage.width, window.width);
          expect(layout.stage.center.dy, closeTo(layout.sheet.center.dy, 1e-9));
          expect(layout.sheet.center.dx, closeTo(window.width / 2, 1e-9));
          // The sheet keeps the shape of the document.
          expect(
            layout.sheet.width / layout.sheet.height,
            closeTo(width / height, 1e-9),
          );
          // Under the pebbles of the top, above the line.
          expect(
            layout.sheet.top,
            greaterThanOrEqualTo(layout.top + GaletsLayout.topHeight),
          );
          expect(layout.sheet.bottom, lessThanOrEqualTo(layout.lineTop));
          expect(layout.sheet.left, greaterThanOrEqualTo(GaletsLayout.side));
        }
      }
    }
  });

  test('without a decor the sheet takes the room; on one it leaves some', () {
    const window = Size(1440, 900);
    final plain = laid(window);
    final dressed = laid(window, decor: true);
    expect(plain.band, 0);
    expect(plain.sheet.width, greaterThan(dressed.sheet.width));
    expect(
      dressed.sheet.width,
      lessThanOrEqualTo(window.width * GaletsLayout.sheetShareWithDecor),
    );
    // An iPad of 13 inches on its side: more than two thirds of the screen.
    final ipad = laid(const Size(1366, 1024));
    expect(
      ipad.sheet.width * ipad.sheet.height / (1366 * 1024),
      greaterThan(.66),
    );
  });

  test('« dessiner en grand » gives the sheet the room of the pebbles', () {
    for (final decor in [true, false]) {
      const window = Size(1440, 900);
      final usual = laid(window, decor: decor);
      final big = laid(window, decor: decor, bigSheet: true);
      expect(big.sheet.width, greaterThan(usual.sheet.width + 8));
      expect(big.sheet.top, greaterThanOrEqualTo(big.top));
      expect(big.sheet.bottom, lessThanOrEqualTo(big.lineTop));
      // The small pebble that brings the others back covers no corner of
      // the sheet.
      final corner = Rect.fromLTWH(
        window.width - GaletsLayout.side - GaletsLayout.topHeight,
        big.top,
        GaletsLayout.topHeight,
        160,
      );
      expect(big.sheet.overlaps(corner), isFalse, reason: 'decor: $decor');
    }
    // A tablet's sheet already has the width of the screen: nothing to
    // gain there, and the studio does not offer it.
    const ipad = Size(1366, 1024);
    expect(
      laid(ipad, bigSheet: true).sheet.width,
      lessThanOrEqualTo(laid(ipad).sheet.width),
    );
  });

  test('a decor in a window: under the pebbles, beside the sheet', () {
    const decor = Size(1061, 407);
    const decorSheet = Rect.fromLTWH(266, 26, 526, 351);
    for (final window in const [
      Size(1440, 900),
      Size(1280, 720),
      Size(1920, 1080),
      Size(2560, 1440),
      Size(1600, 700),
    ]) {
      final layout = laid(window, decor: true);
      final around = DecorLayout(
        frame: layout.decorFrame,
        sheetAtRest: layout.sheet,
        decor: decor,
        decorSheet: decorSheet,
        clearTop: layout.decorClearTop,
        smallest: DecorLayout.smallestInWindow,
      );
      expect(around.pieces, isTrue, reason: '$window');
      expect(around.scale, greaterThanOrEqualTo(DecorLayout.smallestInWindow));
      // The left side ends before the sheet, the right one begins after.
      expect(
        around.place(decorSheet, DecorAnchor.left).left,
        lessThanOrEqualTo(layout.sheet.left + 1e-6),
        reason: '$window',
      );
      expect(
        around.place(decorSheet, DecorAnchor.right).right,
        greaterThanOrEqualTo(layout.sheet.right - 1e-6),
        reason: '$window',
      );
      // Nothing of it under the pebbles of the top.
      expect(
        around.top(DecorAnchor.left),
        greaterThanOrEqualTo(layout.decorClearTop - 1e-6),
        reason: '$window',
      );
      // What lies under the sheet is shown: the sheet leaves its band.
      expect(around.under, isTrue, reason: '$window');
    }
  });

  test('the frame of before keeps its rule of the share of the height', () {
    // The same room beside the sheet in a frame far taller than the decor:
    // too small a share for the studio of before, enough for the pebbles.
    const frame = Size(1440, 804);
    const sheet = Rect.fromLTWH(252, 138, 936, 624);
    const decor = Size(1061, 407);
    const decorSheet = Rect.fromLTWH(266, 26, 526, 351);
    final before = DecorLayout(
      frame: const Size(1440, 2000),
      sheetAtRest: sheet,
      decor: decor,
      decorSheet: decorSheet,
    );
    expect(before.pieces, isFalse);
    final window = DecorLayout(
      frame: frame,
      sheetAtRest: sheet,
      decor: decor,
      decorSheet: decorSheet,
      clearTop: 82,
      smallest: DecorLayout.smallestInWindow,
    );
    expect(window.pieces, isTrue);
    expect(window.scale, closeTo(252 / 269, 1e-9));
  });

  test('ten elementary colours, each one in its family of five', () {
    expect(galetColours, hasLength(10));
    expect(galetFamilies, hasLength(galetColours.length));
    expect(
      [for (final colour in galetColours) colour.frenchName],
      [
        'Rouge',
        'Orange',
        'Jaune',
        'Vert',
        'Bleu',
        'Violet',
        'Rose',
        'Marron',
        'Noir',
        'Blanc',
      ],
    );
    // They are the ten colours of the simplest interface.
    expect(
      {for (final colour in galetColours) colour.rgb},
      {for (final colour in simplePaintColors) colour.rgb},
    );
    final seen = <int>{};
    for (final (index, family) in galetFamilies.indexed) {
      final base = galetColours[index];
      if (base.frenchName == 'Blanc') {
        expect(family, isEmpty);
        continue;
      }
      expect(family, hasLength(5), reason: base.frenchName);
      expect(
        family.map((shade) => shade.rgb),
        contains(base.rgb),
        reason: base.frenchName,
      );
      // From the lightest to the darkest.
      final lights = [
        for (final shade in family)
          Color(0xff000000 | shade.rgb).computeLuminance(),
      ];
      for (var i = 1; i < lights.length; i++) {
        expect(
          lights[i],
          lessThan(lights[i - 1]),
          reason: '${base.frenchName}: ${family[i].frenchName}',
        );
      }
      for (final shade in family) {
        expect(seen.add(shade.rgb), isTrue, reason: shade.frenchName);
        expect(galetFamilyOf(shade.rgb), index);
        expect(galetColourName(shade.rgb), isNotNull);
      }
    }
    expect(galetFamilyOf(0xffffff), 9);
    // Four of the named colours of before are no longer offered.
    for (final rgb in [0xd75e56, 0x78a66f, 0x388778, 0x477fb2]) {
      expect(galetFamilyOf(rgb), isNull);
      expect(galetColourName(rgb), isNull);
    }
    // The others have their place in a family.
    final gone = {0xd75e56, 0x78a66f, 0x388778, 0x477fb2};
    for (final colour in [...paintColors, ...morePaintColors]) {
      if (gone.contains(colour.rgb)) continue;
      expect(galetFamilyOf(colour.rgb), isNotNull, reason: colour.frenchName);
    }
  });

  test('five widths, and the one a width is closest to', () {
    expect(galetWidths, [4, 8, 14, 24, 40]);
    for (final (index, width) in galetWidths.indexed) {
      expect(galetWidthIndex(width), index);
    }
    // The width of a new studio, 12, is the middle dot.
    expect(galetWidthIndex(12), 2);
    expect(galetWidthIndex(2), 0);
    expect(galetWidthIndex(48), 4);
    expect(galetWidthIndex(6), anyOf(0, 1));
  });
}
