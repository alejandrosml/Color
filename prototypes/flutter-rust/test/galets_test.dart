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

  test(
    'a line where it holds, two lines in a tall window, rails elsewhere',
    () {
      GaletsForm form(
        Size window, {
        bool phone = false,
        double lineMin = 1021,
      }) => GaletsLayout.formFor(
        window: window,
        phone: phone,
        lineMin: lineMin,
        documentWidth: 1200,
        documentHeight: 800,
      );
      expect(form(const Size(1440, 900)), GaletsForm.line);
      expect(form(const Size(1366, 1024)), GaletsForm.line);
      expect(form(const Size(1130, 600)), GaletsForm.line);
      expect(form(const Size(1024, 768)), GaletsForm.line);
      // Too low for a sheet between the top and a line, or too narrow for
      // the shortest line: the rails leave the sheet the whole height.
      expect(form(const Size(1440, 599)), GaletsForm.rails);
      expect(form(const Size(1020, 768)), GaletsForm.rails);
      expect(form(const Size(680, 520)), GaletsForm.rails);
      // Taller than wide: two lines show every tool and every colour.
      expect(form(const Size(1024, 1366)), GaletsForm.two);
      expect(form(const Size(744, 1133)), GaletsForm.two);
      expect(form(const Size(900, 1000)), GaletsForm.two);
      // A telephone on its side, whatever its size.
      expect(form(const Size(1440, 900), phone: true), GaletsForm.rails);
      expect(form(const Size(734, 372), phone: true), GaletsForm.rails);
      // The simplest interface has four tools: its line holds in less.
      expect(form(const Size(900, 700), lineMin: 805), GaletsForm.line);
    },
  );

  test('between two rails the sheet has the height of the window', () {
    GaletsLayout rails(Size window) => GaletsLayout(
      form: GaletsForm.rails,
      window: window,
      documentWidth: 1200,
      documentHeight: 800,
      decor: false,
    );
    // An iPhone on its side, inside its safe area: six cells, as drawn.
    final iphone = rails(const Size(734, 372));
    expect(iphone.railCells, 6);
    expect(iphone.railCell, GaletsLayout.railCellMost);
    expect(iphone.sheet.width, closeTo(534, .5));
    expect(iphone.sheet.height, closeTo(356, .5));
    expect(iphone.sheet.center.dx, closeTo(367, .01));
    // The smallest telephone: five cells, of the smallest comfortable size.
    final small = rails(const Size(560, 320));
    expect(small.railCells, 5);
    expect(small.railCell, GaletsLayout.cell);
    // The smallest window of a computer: eight.
    final window = rails(const Size(680, 520));
    expect(window.railCells, 8);
    for (final layout in [iphone, small, window]) {
      // The rails stand beside the sheet, never on it, and in the window.
      final rail = layout.railCell + 8;
      expect(layout.sheet.left, greaterThanOrEqualTo(layout.railLeft + rail));
      expect(layout.sheet.right, lessThanOrEqualTo(layout.railRight - rail));
      expect(layout.railLeft, greaterThanOrEqualTo(0));
      expect(layout.railRight, lessThanOrEqualTo(layout.window.width));
      expect(
        layout.top +
            8 +
            layout.railCells * layout.railCell +
            (layout.railCells - 1) * layout.railGap,
        lessThanOrEqualTo(layout.window.height),
      );
      expect(layout.stage.contains(layout.sheet.center), isTrue);
    }
  });

  test('two lines leave the sheet the room between the top and the upper '
      'one', () {
    final layout = GaletsLayout(
      form: GaletsForm.two,
      window: const Size(1024, 1366),
      documentWidth: 1200,
      documentHeight: 800,
      decor: false,
    );
    expect(
      layout.lineTop,
      1366 -
          GaletsLayout.side -
          2 * GaletsLayout.lineHeight -
          GaletsLayout.linesGap,
    );
    expect(layout.sheet.bottom, lessThanOrEqualTo(layout.lineTop - 12));
    expect(layout.sheet.top, greaterThanOrEqualTo(layout.top + 60));
    expect(layout.sheet.width, closeTo(1024 - 2 * GaletsLayout.side, .01));
  });

  test('a shorter line puts white with black, then brown with orange', () {
    const white = 0xffffff, black = 0x1a1a1a, brown = 0x79513e;
    const orange = 0xef9439;
    int rgbOf(int index) => galetColours[index].rgb;
    // Ten places: every colour in its own, with its own family.
    expect(GaletPalette.whole.shown, hasLength(10));
    for (var index = 0; index < 10; index++) {
      expect(GaletPalette.whole.family(index), galetFamilies[index]);
    }
    // Nine: « du blanc au noir ».
    const nine = GaletPalette(9);
    expect(nine.shown.map(rgbOf), isNot(contains(white)));
    expect(nine.shown, hasLength(9));
    final greys = nine.family(nine.swatchOf(black)!);
    expect(greys.first.rgb, white);
    expect(greys.last.rgb, black);
    expect(nine.swatchOf(white), nine.swatchOf(black));
    expect(nine.swatchOf(brown), isNot(nine.swatchOf(orange)));
    // Eight: brown at the bottom of the oranges, too.
    const eight = GaletPalette(8);
    expect(eight.shown, hasLength(8));
    expect(eight.shown.map(rgbOf), isNot(contains(brown)));
    expect(eight.shown.map(rgbOf), contains(0xf4b7cf), reason: 'pink stays');
    expect(eight.family(eight.swatchOf(orange)!).last.rgb, brown);
    expect(eight.swatchOf(brown), eight.swatchOf(orange));
    expect(eight.swatchOf(white), eight.swatchOf(black));
    // One place less — a colour of elsewhere in hand, or the button of
    // every colour: pink with the reds, then violet with the blues.
    const pink = 0xf4b7cf, red = 0xe83d48, violet = 0x9385bc, blue = 0x3370d1;
    const seven = GaletPalette(7);
    expect(seven.shown, hasLength(7));
    expect(seven.shown.map(rgbOf), isNot(contains(pink)));
    expect(seven.family(seven.swatchOf(red)!).first.rgb, pink);
    expect(seven.swatchOf(pink), seven.swatchOf(red));
    const six = GaletPalette(GaletPalette.fewest);
    expect(six.shown, hasLength(6));
    expect(six.family(six.swatchOf(blue)!).last.rgb, violet);
    expect(six.swatchOf(violet), six.swatchOf(blue));
    // Every elementary colour stays one long press away, whatever the
    // line.
    for (var places = GaletPalette.fewest; places <= 10; places++) {
      for (final colour in galetColours) {
        expect(
          GaletPalette(places).swatchOf(colour.rgb),
          isNotNull,
          reason: '${colour.name} with $places places',
        );
      }
    }
    // A colour that no swatch of the line holds.
    expect(eight.swatchOf(0x123456), isNull);
    expect(eight.swatchOf(0xe69976), isNull, reason: 'a shade of brown');
    expect(GaletPalette.whole.swatchOf(0xe69976), isNotNull);
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
