// SPDX-License-Identifier: MIT
// « Les galets » (Color 1.2): the studio of a wide window. The sheet comes
// first: two pebbles float at the top — the drawing and the universe on the
// left; the film, the layers, the view, Annuler, Rétablir and « Enregistrer »
// on the right — and one line at the bottom holds the tools, two settings
// (how big, and which one) and the ten elementary colours. Everything else
// is one press away, in a panel that opens beside its button.
//
// This file holds what the pebbles are made of and where they stand; the
// studio (main.dart) says what each button does. The owner chose this
// interface on 12 November 2026 (claude/color-interface-proposition.md).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'child_art.dart';
import 'color_palette.dart' show NamedPaintColor, paletteTickColor;
import 'decor.dart';
import 'language.dart';
import 'studio_colors.dart';
import 'vector_art.dart';

/// The ten elementary colours of the line, in the order of the rainbow, then
/// brown, black and white: those of the simplest interface, by the names a
/// small child gives them. One press takes the colour; nothing opens.
const galetColours = <NamedPaintColor>[
  NamedPaintColor('Rouge', 0xe83d48),
  NamedPaintColor('Orange', 0xef9439),
  NamedPaintColor('Jaune', 0xeebf4e),
  NamedPaintColor('Vert', 0x4db266),
  NamedPaintColor('Bleu', 0x3370d1),
  NamedPaintColor('Violet', 0x9385bc),
  NamedPaintColor('Rose', 0xf4b7cf),
  NamedPaintColor('Marron', 0x79513e),
  NamedPaintColor('Noir', 0x1a1a1a),
  NamedPaintColor('Blanc', 0xffffff),
];

/// The colour in hand when Color starts: the blue of the line.
const galetStartColour = 0x3370d1;

/// The family of each elementary colour, from the lightest to the darkest:
/// what a long press on its swatch opens. The colours that Color already
/// names have their place there. White has no family.
const galetFamilies = <List<NamedPaintColor>>[
  [
    NamedPaintColor('Rouge très clair', 0xf9c9c6),
    NamedPaintColor('Rouge clair', 0xf1908c),
    NamedPaintColor('Rouge', 0xe83d48),
    NamedPaintColor('Rouge foncé', 0xb52a35),
    NamedPaintColor('Bordeaux', 0x7b1d27),
  ],
  [
    NamedPaintColor('Orange très clair', 0xfbdcbc),
    NamedPaintColor('Orange clair', 0xf5b877),
    NamedPaintColor('Orange', 0xef9439),
    NamedPaintColor('Orange foncé', 0xc5712a),
    NamedPaintColor('Brun orangé', 0x94531f),
  ],
  [
    NamedPaintColor('Crème', 0xfff0b8),
    NamedPaintColor('Jaune clair', 0xf6d982),
    NamedPaintColor('Jaune', 0xeebf4e),
    NamedPaintColor('Ocre', 0xc79a2c),
    NamedPaintColor('Ocre foncé', 0x93701f),
  ],
  [
    NamedPaintColor('Menthe', 0xa4e0c1),
    NamedPaintColor('Vert clair', 0x7fcb8f),
    NamedPaintColor('Vert', 0x4db266),
    NamedPaintColor('Vert foncé', 0x2f854a),
    NamedPaintColor('Vert forêt', 0x245846),
  ],
  [
    NamedPaintColor('Ciel', 0xa8d8f0),
    NamedPaintColor('Bleu clair', 0x6ea4e3),
    NamedPaintColor('Bleu', 0x3370d1),
    NamedPaintColor('Bleu foncé', 0x2b56a6),
    NamedPaintColor('Bleu nuit', 0x283b78),
  ],
  [
    NamedPaintColor('Violet très clair', 0xded8ee),
    NamedPaintColor('Violet clair', 0xbbb0d8),
    NamedPaintColor('Violet', 0x9385bc),
    NamedPaintColor('Violet foncé', 0x6f5aa6),
    NamedPaintColor('Violet très foncé', 0x4a3a7a),
  ],
  [
    NamedPaintColor('Rose très clair', 0xfbe1eb),
    NamedPaintColor('Rose', 0xf4b7cf),
    NamedPaintColor('Rose vif', 0xe77fae),
    NamedPaintColor('Framboise', 0xc96d93),
    NamedPaintColor('Prune', 0x773f70),
  ],
  [
    NamedPaintColor('Teint clair', 0xfbeadb),
    NamedPaintColor('Pêche', 0xe69976),
    NamedPaintColor('Caramel', 0xc98a5e),
    NamedPaintColor('Marron', 0x79513e),
    NamedPaintColor('Marron foncé', 0x4d3226),
  ],
  [
    NamedPaintColor('Gris très clair', 0xc5cbcd),
    NamedPaintColor('Gris', 0x9aa3a5),
    NamedPaintColor('Gris foncé', 0x6b777a),
    NamedPaintColor('Encre', 0x33484d),
    NamedPaintColor('Noir', 0x1a1a1a),
  ],
  [],
];

/// The swatch of the line whose family holds [rgb]: itself for an
/// elementary colour; null for a colour that the line does not offer.
int? galetFamilyOf(int rgb) {
  for (var index = 0; index < galetColours.length; index++) {
    if (galetColours[index].rgb == rgb) return index;
  }
  for (var index = 0; index < galetFamilies.length; index++) {
    if (galetFamilies[index].any((shade) => shade.rgb == rgb)) return index;
  }
  return null;
}

/// The name of [rgb] among the colours of the line and their families;
/// null for any other colour.
String? galetColourName(int rgb) {
  for (final colour in galetColours) {
    if (colour.rgb == rgb) return colour.name;
  }
  for (final family in galetFamilies) {
    for (final shade in family) {
      if (shade.rgb == rgb) return shade.name;
    }
  }
  return null;
}

/// The five widths of a trait, in units of the document: five dots to
/// press instead of a slider to move (the owner, 12 November 2026).
const galetWidths = <double>[4, 8, 14, 24, 40];

/// The dot of [galetWidths] that [width] is closest to, as the eye sees
/// it: a width between two of them belongs to the nearer in proportion.
int galetWidthIndex(double width) {
  var best = 0;
  var distance = double.infinity;
  for (var index = 0; index < galetWidths.length; index++) {
    final ratio = (math.log(math.max(width, .1) / galetWidths[index])).abs();
    if (ratio < distance) {
      distance = ratio;
      best = index;
    }
  }
  return best;
}

/// The letters of the pebbles: Atkinson Hyperlegible, made to be told
/// apart by eyes that read with difficulty.
TextStyle galetText(double size, {bool bold = false, Color? color}) =>
    TextStyle(
      fontFamily: 'ColorAtkinson',
      fontSize: size,
      height: 1.2,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color ?? studioInk,
      letterSpacing: 0,
    );

/// The width of [text] on one line in [style], as the screen writes it.
double galetTextWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width.ceilToDouble();
}

/// How the pebbles are laid out in a window (Color 1.2, step G2). Color
/// takes the form that shows the most: a line where it holds, two lines in
/// a window taller than wide, and rails where neither leaves the sheet
/// enough room.
enum GaletsForm {
  /// One line at the bottom: the tools, the two settings, the colours.
  line,

  /// Two lines at the bottom: the tools and their settings, then the
  /// colours.
  two,

  /// Two rails beside the sheet, and the rest in a drawer: a telephone on
  /// its side, and a window too small for a line.
  rails,
}

/// Where the pebbles and the sheet stand in a window.
@immutable
class GaletsLayout {
  const GaletsLayout._({
    required this.form,
    required this.window,
    required this.top,
    required this.lineTop,
    required this.band,
    required this.sheet,
    required this.stage,
    required this.bigSheet,
    required this.railLeft,
    required this.railRight,
    required this.railCells,
    required this.railCell,
    required this.railGap,
    required this.lineHigh,
    required this.padding,
  });

  /// The narrowest window whose line holds the nine tools, the two
  /// settings and the ten colours: narrower, the line gets shorter.
  static const minWidth = 1130.0;

  /// The lowest window that leaves a sheet between the pebbles of the top
  /// and a line: lower, the rails give the sheet the whole height.
  static const minHeight = 600.0;

  /// The room kept on each side of the window.
  static const side = 16.0;

  /// A cell of a pebble: the smallest comfortable target.
  static const cell = 48.0;

  /// A cell of the simplest interface, for the smallest hands.
  static const largeCell = 58.0;

  /// The height of a pebble of the top, and of the line.
  static const topHeight = cell + 12;
  static const lineHeight = cell + 16;

  /// Between the two lines of a window taller than wide.
  static const linesGap = 8.0;

  /// The width of a rail, and the largest cell it holds.
  static const railWidth = 60.0;
  static const railCellMost = 52.0;

  /// With a decor, the sheet takes no more than this share of the width:
  /// the decor keeps the room to be looked at on each side.
  static const sheetShareWithDecor = .65;

  /// With a decor, how much of its ground shows under the sheet.
  static const groundUnderSheet = 42.0;

  /// The form of the pebbles in a [window]. [phone]: a telephone on its
  /// side. [lineMin]: the narrowest window whose line, as short as it
  /// gets, holds what this interface shows. A line where it holds; else
  /// whichever of the two lines and of the rails leaves the larger sheet
  /// of [documentWidth] by [documentHeight].
  static GaletsForm formFor({
    required Size window,
    required bool phone,
    required double lineMin,
    required double documentWidth,
    required double documentHeight,
    EdgeInsets safe = EdgeInsets.zero,
  }) {
    if (phone) return GaletsForm.rails;
    if (window.width > window.height &&
        window.width >= lineMin &&
        window.height >= minHeight) {
      return GaletsForm.line;
    }
    Size sheetOf(GaletsForm form) => GaletsLayout(
      form: form,
      window: window,
      safe: safe,
      documentWidth: documentWidth,
      documentHeight: documentHeight,
      decor: false,
    ).sheet.size;
    final two = sheetOf(GaletsForm.two);
    final rails = sheetOf(GaletsForm.rails);
    // Two lines show every tool and every colour: they are kept unless
    // the rails leave a clearly larger sheet.
    return rails.width * rails.height > 1.15 * two.width * two.height
        ? GaletsForm.rails
        : GaletsForm.two;
  }

  /// The pebbles in a [window] whose edges the device hides by [safe],
  /// around a sheet of [documentWidth] by [documentHeight] units.
  ///
  /// [decor]: a decor stands around the sheet, on a ground that the line
  /// covers at the bottom. [bigSheet]: « dessiner en grand » — the pebbles
  /// of the top go, but for a small one that brings them back, a column
  /// [corner] wide in the corner of the window.
  /// [padding]: what the stage keeps around the sheet when the whole of it
  /// is shown.
  factory GaletsLayout({
    GaletsForm form = GaletsForm.line,
    required Size window,
    EdgeInsets safe = EdgeInsets.zero,
    required double documentWidth,
    required double documentHeight,
    required bool decor,
    bool bigSheet = false,
    double corner = topHeight,
    double padding = 28,
    double lineHigh = lineHeight,
  }) {
    final ratio = documentWidth / documentHeight;
    Size fitted(double width, double height) {
      final w = math.max(1.0, math.min(width, height * ratio));
      return Size(w, w / ratio);
    }

    if (form == GaletsForm.rails) {
      // A rail on each side, the sheet between them on the whole height.
      final top = safe.top + (safe.top > 0 ? 4 : 7);
      final foot = safe.bottom > 0 ? safe.bottom + 4 : 7.0;
      final railLeft = math.max(8.0, safe.left + 2);
      final railRight = window.width - math.max(8.0, safe.right + 2);
      final room = window.height - top - foot;
      // As many cells as the height holds, a little smaller and closer
      // where it holds fewer than six of the largest.
      var railCell = railCellMost;
      var railGap = 7.0;
      var cells = ((room - 8 + railGap) / (railCell + railGap)).floor();
      if (cells < 6) {
        railCell = cell;
        railGap = 4;
        cells = ((room - 8 + railGap) / (railCell + railGap)).floor();
      }
      // The sheet in the middle of the window, as the stage shows it.
      final half = math.min(
        window.width / 2 - (railLeft + railCell + 8 + 10),
        railRight - railCell - 8 - 10 - window.width / 2,
      );
      final size = fitted(
        math.max(1.0, 2 * half),
        math.max(1.0, window.height - top - foot - 2),
      );
      final sheet = Rect.fromLTWH(
        (window.width - size.width) / 2,
        top + 1 + (window.height - top - foot - 2 - size.height) / 2,
        size.width,
        size.height,
      );
      const around = 8.0;
      return GaletsLayout._(
        form: form,
        window: window,
        top: top,
        lineTop: window.height,
        band: 0,
        sheet: sheet,
        stage: Rect.fromLTRB(
          0,
          math.max(0.0, sheet.top - around),
          window.width,
          math.min(window.height, sheet.bottom + around),
        ),
        bigSheet: false,
        railLeft: railLeft,
        railRight: railRight,
        railCells: math.max(3, cells),
        railCell: railCell,
        railGap: railGap,
        lineHigh: 0,
        padding: around,
      );
    }

    final top = safe.top + (safe.top > 0 ? 8 : 14);
    final foot = safe.bottom > 0 ? safe.bottom + 12 : side;
    final lines = form == GaletsForm.two ? 2 * lineHigh + linesGap : lineHigh;
    final lineTop = window.height - foot - lines;
    final band = decor ? window.height - lineTop + side : 0.0;
    final left = math.max(side, safe.left + 8);
    final right = window.width - math.max(side, safe.right + 8);
    final floor = decor
        ? window.height - band - groundUnderSheet
        : lineTop - 12;

    final ceiling = top + topHeight + 12;
    final wide = right - left;
    Rect sheet;
    if (bigSheet) {
      // Beside the small pebble, a column in the corner, the sheet climbs
      // to the top of the window.
      final size = fitted(math.max(1.0, wide - 2 * (corner + 8)), floor - top);
      sheet = Rect.fromLTWH(
        (window.width - size.width) / 2,
        decor ? floor - size.height : top + (floor - top - size.height) / 2,
        size.width,
        size.height,
      );
    } else {
      final size = fitted(
        decor ? math.min(wide, window.width * sheetShareWithDecor) : wide,
        math.max(1.0, floor - ceiling),
      );
      // On a ground, the sheet stands on it; without one, it floats in
      // the middle of its room.
      sheet = Rect.fromLTWH(
        (window.width - size.width) / 2,
        decor
            ? floor - size.height
            : ceiling + (floor - ceiling - size.height) / 2,
        size.width,
        size.height,
      );
    }
    return GaletsLayout._(
      form: form,
      window: window,
      top: top,
      lineTop: lineTop,
      band: band,
      sheet: sheet,
      // The stage holds the sheet in its middle, with [padding] above and
      // below it, across the whole window: a sheet seen from closer has
      // all that room.
      stage: Rect.fromLTRB(
        0,
        sheet.top - padding,
        window.width,
        sheet.bottom + padding,
      ),
      bigSheet: bigSheet,
      railLeft: left,
      railRight: right,
      railCells: 0,
      railCell: cell,
      railGap: 0,
      lineHigh: lineHigh,
      padding: padding,
    );
  }

  final GaletsForm form;
  final Size window;

  /// The top edge of the pebbles of the top, and of the line — of the
  /// upper one when there are two.
  final double top;
  final double lineTop;

  /// The height of the band at the bottom of the window where the ground
  /// of a decor goes on, plain, under the line; zero without a decor.
  final double band;

  /// Where the sheet lies when the whole of it is shown.
  final Rect sheet;

  /// The frame the sheet is drawn and touched in.
  final Rect stage;
  final bool bigSheet;

  /// With rails: the left edge of the left one and the right edge of the
  /// right one, how many cells the height holds, how large and how far
  /// apart.
  final double railLeft;
  final double railRight;
  final int railCells;
  final double railCell;
  final double railGap;

  /// The height of a line, and what the stage keeps around the sheet when
  /// the whole of it is shown.
  final double lineHigh;
  final double padding;

  /// The frame of a decor: the window, less the band of the bottom.
  Size get decorFrame => Size(window.width, window.height - band);

  /// What the pebbles of the top keep of the frame of a decor: its pieces
  /// stay below.
  double get decorClearTop => top + topHeight + 8;

  /// The sheet at rest, in the stage.
  Rect get sheetInStage => sheet.shift(-stage.topLeft);

  @override
  bool operator ==(Object other) =>
      other is GaletsLayout &&
      other.form == form &&
      other.window == window &&
      other.top == top &&
      other.lineTop == lineTop &&
      other.band == band &&
      other.sheet == sheet &&
      other.stage == stage &&
      other.bigSheet == bigSheet &&
      other.railCells == railCells &&
      other.lineHigh == lineHigh &&
      other.padding == padding;

  @override
  int get hashCode => Object.hash(
    form,
    window,
    top,
    lineTop,
    band,
    sheet,
    stage,
    bigSheet,
    railCells,
    lineHigh,
    padding,
  );
}

/// The colours a line shows when it has room for [places] of them, and
/// what a long press on each opens. With ten places, the ten elementary
/// colours and their families. With nine, white goes to the top of the
/// family of black — « du blanc au noir ». With eight, brown goes to the
/// bottom of the family of orange as well (the owner, 12 November 2026).
/// Where one more place is taken — by a colour that the line does not
/// offer, or by the button of every colour — pink goes to the top of the
/// family of red, then violet to the bottom of that of blue: no button is
/// ever drawn smaller to make room.
@immutable
class GaletPalette {
  const GaletPalette(this.places);

  /// Every colour in its own place.
  static const whole = GaletPalette(10);

  /// The fewest places a line is laid out for.
  static const fewest = 6;

  final int places;

  static const _red = 0;
  static const _orange = 1;
  static const _blue = 4;
  static const _violet = 5;
  static const _pink = 6;
  static const _brown = 7;
  static const _black = 8;
  static const _white = 9;

  bool get _whiteAway => places < 10;
  bool get _brownAway => places < 9;
  bool get _pinkAway => places < 8;
  bool get _violetAway => places < 7;

  bool _away(int index) =>
      (index == _white && _whiteAway) ||
      (index == _brown && _brownAway) ||
      (index == _pink && _pinkAway) ||
      (index == _violet && _violetAway);

  /// The swatches of the line: places in [galetColours], in its order.
  List<int> get shown => [
    for (var index = 0; index < galetColours.length; index++)
      if (!_away(index)) index,
  ];

  /// What a long press on the swatch [index] opens, from the lightest to
  /// the darkest; empty for a colour without a family.
  List<NamedPaintColor> family(int index) => [
    if (index == _black && _whiteAway) galetColours[_white],
    if (index == _red && _pinkAway) galetColours[_pink],
    ...galetFamilies[index],
    if (index == _orange && _brownAway) galetColours[_brown],
    if (index == _blue && _violetAway) galetColours[_violet],
  ];

  /// The swatch of this line that holds [rgb], itself or in its family;
  /// null for a colour that this line does not offer.
  int? swatchOf(int rgb) {
    for (final index in shown) {
      if (galetColours[index].rgb == rgb) return index;
    }
    for (final index in shown) {
      if (family(index).any((shade) => shade.rgb == rgb)) return index;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is GaletPalette && other.places == places;

  @override
  int get hashCode => places.hashCode;
}

/// How much larger than usual the system writes: 1 for ordinary letters.
double galetTextScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(15) / 15;

const _floatShadow = [
  BoxShadow(color: Color(0x24263f43), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x29263f43), blurRadius: 28, offset: Offset(0, 10)),
];
const _panelShadow = [
  BoxShadow(color: Color(0x29263f43), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x47263f43), blurRadius: 40, offset: Offset(0, 16)),
];

/// The corners of something [height] tall in the look of the moment: all
/// round in most universes, hardly round in the universe of paper.
BorderRadius galetCorners(double height, {double most = double.infinity}) =>
    BorderRadius.circular(
      math.min(math.min(height / 2, most), studioLook.value.galetRadius),
    );

/// A pebble: a light surface that floats over the frame of the sheet, its
/// buttons side by side.
class Galet extends StatelessWidget {
  const Galet({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(6),
    this.height = GaletsLayout.topHeight,
    this.gap = 2,
    this.vertical = false,
  });

  final List<Widget> children;
  final EdgeInsets padding;

  /// Its height; its width when it is [vertical], a column of buttons.
  final double height;
  final double gap;
  final bool vertical;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Container(
      height: vertical ? null : height,
      width: vertical ? height : null,
      padding: padding,
      decoration: BoxDecoration(
        color: studioSurface,
        borderRadius: galetCorners(height),
        boxShadow: _floatShadow,
      ),
      child: Flex(
        direction: vertical ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0 && gap > 0)
              SizedBox(
                width: vertical ? null : gap,
                height: vertical ? gap : null,
              ),
            child,
          ],
        ],
      ),
    ),
  );
}

/// The thin line between two groups of a pebble.
class GaletRule extends StatelessWidget {
  const GaletRule({super.key});

  /// What it takes of the pebble, its margins counted.
  static const width = 13.5;

  @override
  Widget build(BuildContext context) => Container(
    width: 1.5,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: studioLine,
  );
}

/// One button of a pebble or of a panel: [child] on a round surface that
/// takes the colour of a choice when [selected]. Its name is [label], said
/// by a screen reader and shown when a pointer stays over it.
class GaletButton extends StatefulWidget {
  const GaletButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.child,
    this.onLongPress,
    this.longPressLabel,
    this.selected = false,
    this.marksSelection = true,
    this.framed = false,
    this.expanded,
    this.fill,
    this.width,
    this.height = GaletsLayout.cell,
    this.padding = EdgeInsets.zero,
    this.corners,
    this.hint,
    this.tip = true,
    this.tipOnHold = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget child;

  /// A long press, a press of the second button of a mouse, or the arrow
  /// up of the keyboard; a screen reader offers it as [longPressLabel].
  final VoidCallback? onLongPress;
  final String? longPressLabel;

  final bool selected;

  /// Whether [selected] is told to a screen reader as a choice among
  /// others: not for a button that only opens something.
  final bool marksSelection;

  /// A chosen one among its likes in a panel: a line of the accent goes
  /// around it.
  final bool framed;

  /// For a button that opens a panel: whether it is open.
  final bool? expanded;

  /// The colour of the button when it is not the surface of its pebble.
  final Color? fill;

  /// Its width; as wide as [child] and [padding] ask when null, and never
  /// narrower than a cell.
  final double? width;
  final double height;
  final EdgeInsets padding;

  /// Its corners when they are not those of a round button.
  final double? corners;
  final String? hint;

  /// Whether the name is shown beside a pointer that stays over it, and
  /// under a finger that stays on it.
  final bool tip;
  final bool tipOnHold;

  @override
  State<GaletButton> createState() => _GaletButtonState();
}

class _GaletButtonState extends State<GaletButton> {
  // The keyboard is on this button: a screen reader is told so.
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final GaletButton(
      :label,
      :onPressed,
      :child,
      :onLongPress,
      :longPressLabel,
      :selected,
      :marksSelection,
      :framed,
      :expanded,
      :fill,
      :width,
      :height,
      :padding,
      :corners,
      :hint,
      :tip,
      :tipOnHold,
    ) = widget;
    final enabled = onPressed != null;
    final radius = galetCorners(height, most: corners ?? double.infinity);
    final long = onLongPress;
    Widget button = Material(
      color: fill ?? (selected ? studioSelected : Colors.transparent),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: framed && selected
            ? BorderSide(color: studioGreen, width: 2.5)
            : BorderSide.none,
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: radius),
        onTap: onPressed,
        onLongPress: enabled ? long : null,
        onSecondaryTap: enabled ? long : null,
        excludeFromSemantics: true,
        onFocusChange: (focused) {
          if (mounted && focused != _focused) {
            setState(() => _focused = focused);
          }
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: width ?? GaletsLayout.cell,
            maxWidth: width ?? double.infinity,
            minHeight: height,
            maxHeight: height,
          ),
          child: Padding(
            padding: padding,
            child: Center(widthFactor: 1, child: child),
          ),
        ),
      ),
    );
    if (!enabled) button = Opacity(opacity: .38, child: button);
    if (long != null && enabled) {
      // The equal of the long press for a keyboard.
      button = CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.arrowUp): long},
        child: button,
      );
    }
    if (tip) {
      button = Tooltip(
        message: label,
        excludeFromSemantics: true,
        triggerMode: tipOnHold && long == null
            ? TooltipTriggerMode.longPress
            : TooltipTriggerMode.manual,
        child: button,
      );
    }
    // The name, the state and the actions on the button itself, at its
    // root: a screen reader meets one control.
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      focusable: enabled,
      focused: enabled && _focused,
      selected: marksSelection && selected ? true : null,
      expanded: expanded,
      label: label,
      hint: hint,
      onTap: onPressed,
      onLongPress: enabled ? long : null,
      customSemanticsActions: long != null && enabled && longPressLabel != null
          ? {CustomSemanticsAction(label: longPressLabel): long}
          : null,
      excludeSemantics: true,
      child: button,
    );
  }
}

/// A button that is a picture of the interface.
class GaletPictureButton extends StatelessWidget {
  const GaletPictureButton({
    super.key,
    required this.art,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.marksSelection = false,
    this.size = 30,
    this.cell = GaletsLayout.cell,
  });

  final EduArt art;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final bool marksSelection;
  final double size;

  /// How large the button is: a cell of a pebble, or of a rail.
  final double cell;

  @override
  Widget build(BuildContext context) => GaletButton(
    label: label,
    onPressed: onPressed,
    selected: selected,
    marksSelection: marksSelection,
    width: cell,
    height: cell,
    child: EduIllustration(art: art, size: size),
  );
}

/// A little arrow, down or up: this button opens something.
class GaletChevron extends StatelessWidget {
  const GaletChevron({super.key, this.up = false, this.size = 13, this.color});
  final bool up;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _ChevronPainter(up: up, color: color ?? studioQuietMark),
    ),
  );
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.up, required this.color});
  final bool up;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final path = up
        ? (Path()
            ..moveTo(6 * unit, 15 * unit)
            ..lineTo(12 * unit, 9 * unit)
            ..lineTo(18 * unit, 15 * unit))
        : (Path()
            ..moveTo(6 * unit, 9 * unit)
            ..lineTo(12 * unit, 15 * unit)
            ..lineTo(18 * unit, 9 * unit));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * unit
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.up != up || old.color != color;
}

/// The portrait of the companion in the pebble of the drawing: the logo
/// « De face ». When [cue] changes and the options let the companion
/// answer, it gives a little jump.
class GaletPortrait extends StatefulWidget {
  const GaletPortrait({super.key, this.size = 42, this.cue});
  final double size;
  final ValueListenable<int>? cue;

  static const duration = Duration(milliseconds: 520);

  @override
  State<GaletPortrait> createState() => _GaletPortraitState();
}

class _GaletPortraitState extends State<GaletPortrait>
    with SingleTickerProviderStateMixin {
  late final _jump = AnimationController(
    vsync: this,
    duration: GaletPortrait.duration,
  );

  @override
  void initState() {
    super.initState();
    widget.cue?.addListener(_play);
  }

  @override
  void didUpdateWidget(GaletPortrait old) {
    super.didUpdateWidget(old);
    if (old.cue != widget.cue) {
      old.cue?.removeListener(_play);
      widget.cue?.addListener(_play);
    }
  }

  @override
  void dispose() {
    widget.cue?.removeListener(_play);
    _jump.dispose();
    super.dispose();
  }

  void _play() {
    if (!mounted || MediaQuery.maybeDisableAnimationsOf(context) == true) {
      return;
    }
    _jump.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final picture = VectorArtCatalog.instance?['logo'];
    final portrait = picture == null
        ? EduIllustration(art: EduArt.mascot, size: widget.size)
        : SizedBox.square(
            dimension: widget.size,
            child: CustomPaint(painter: _PicturePainter(picture)),
          );
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _jump,
        child: portrait,
        builder: (context, child) => Transform.translate(
          // Up and down again, once.
          offset: Offset(0, -5 * math.sin(_jump.value * math.pi)),
          child: child,
        ),
      ),
    );
  }
}

class _PicturePainter extends CustomPainter {
  const _PicturePainter(this.picture);
  final VectorPicture picture;

  @override
  void paint(Canvas canvas, Size size) =>
      picture.paint(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_PicturePainter old) => !identical(old.picture, picture);
}

/// Whether [rgb] is so light that it would be lost on the surface of a
/// pebble: it is then drawn with a thin line around it.
bool galetPale(int rgb) {
  final colour = Color(0xff000000 | rgb).computeLuminance();
  final surface = studioSurface.computeLuminance();
  final ratio =
      (math.max(colour, surface) + .05) / (math.min(colour, surface) + .05);
  return ratio < 1.6;
}

/// A swatch of colour: a round of [rgb] in a cell; chosen, it wears a ring
/// of the accent and a tick. [hasShades]: a long press opens its family,
/// which the chosen one says with a little arrow above it.
class GaletSwatch extends StatelessWidget {
  const GaletSwatch({
    super.key,
    required this.rgb,
    required this.name,
    required this.onPressed,
    this.onShades,
    this.chosen = false,
    this.ticked = true,
    this.cell = GaletsLayout.cell,
    this.diameter = 32,
    this.expanded,
  });

  final int rgb;
  final String name;
  final VoidCallback? onPressed;

  /// For the swatch of a rail, which opens the colours: whether they are
  /// open.
  final bool? expanded;

  /// Opens the family of this colour; null for a colour without one.
  final VoidCallback? onShades;
  final bool chosen;

  /// Whether the chosen swatch is the very colour in hand: a swatch of the
  /// line whose shade is in hand keeps its ring without the tick.
  final bool ticked;
  final double cell;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final colour = Color(0xff000000 | rgb);
    final round = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        border: galetPale(rgb)
            ? Border.all(color: studioSwatchRing, width: 1.5)
            : null,
      ),
      child: chosen && ticked
          ? Icon(
              Icons.check_rounded,
              size: diameter * .62,
              color: paletteTickColor(rgb),
            )
          : null,
    );
    return GaletButton(
      label: name,
      onPressed: onPressed,
      onLongPress: onShades,
      longPressLabel: onShades == null ? null : tr('Nuances'),
      hint: onShades == null ? null : tr('Appui long : ses nuances'),
      selected: chosen,
      marksSelection: expanded == null,
      expanded: expanded,
      fill: Colors.transparent,
      width: cell,
      height: cell,
      tipOnHold: false,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (chosen)
            Container(
              width: diameter + 13,
              height: diameter + 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: studioGreen, width: 2.5),
              ),
            ),
          round,
          if (chosen && onShades != null)
            Positioned(
              top: -(cell - diameter) / 2 - 3,
              child: GaletChevron(up: true, size: 13, color: studioGreen),
            ),
        ],
      ),
    );
  }
}

/// « Enregistrer » : golden in every universe, with its name when the
/// window has room for it. [savedJustNow]: a tick stands for its picture.
/// [unsaved]: a small dot says that the drawing has changes to keep.
class GaletSaveButton extends StatelessWidget {
  const GaletSaveButton({
    super.key,
    required this.onPressed,
    required this.named,
    required this.savedJustNow,
    required this.unsaved,
    this.size = GaletsLayout.cell,
  });

  final VoidCallback? onPressed;
  final bool named;
  final bool savedJustNow;
  final bool unsaved;

  /// How large it is without its name: a cell of a pebble, or of a rail.
  final double size;

  static TextStyle get style => galetText(16, bold: true, color: studioSaveInk);

  /// Its width with its name, written [text] wide.
  static double namedWidth(double text) => 12 + 28 + 8 + text + 18;

  @override
  Widget build(BuildContext context) {
    final picture = savedJustNow
        ? Semantics(
            liveRegion: true,
            label: tr('Dessin enregistré'),
            child: Icon(
              Icons.check_circle,
              key: const Key('savedTick'),
              size: 28,
              color: StudioLook.classic.accent,
            ),
          )
        : Stack(
            clipBehavior: Clip.none,
            children: [
              const EduIllustration(art: EduArt.save, size: 28),
              if (unsaved)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    key: const Key('unsavedDot'),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xffd75e56),
                      shape: BoxShape.circle,
                      border: Border.all(color: studioSaveFill, width: 1.5),
                    ),
                  ),
                ),
            ],
          );
    final name = tr('Enregistrer');
    return GaletButton(
      label: unsaved ? '$name · ${tr('modifications non enregistrées')}' : name,
      onPressed: onPressed,
      fill: studioSaveFill,
      tip: !named,
      width: named ? null : size,
      height: named ? GaletsLayout.cell : size,
      padding: named
          ? const EdgeInsets.only(left: 12, right: 18)
          : EdgeInsets.zero,
      child: named
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                picture,
                const SizedBox(width: 8),
                Text(name, maxLines: 1, style: style),
              ],
            )
          : picture,
    );
  }
}

/// What Niko says, in a bubble beside the pebble of the drawing: a few
/// words in bold, then a short sentence.
class GaletBubble extends StatelessWidget {
  const GaletBubble({
    super.key,
    required this.strong,
    required this.text,
    required this.width,
    this.below = false,
    this.tail = true,
  });

  final String strong;
  final String text;

  /// Whether it points to the companion: not over the sheet between two
  /// rails, where the companion is not beside it.
  final bool tail;

  /// The width it takes, its tail not counted.
  final double width;

  /// Under the pebble of the drawing rather than beside it, where the
  /// window leaves no room there: its tail then points up, and its
  /// sentence may take three lines.
  final bool below;

  static TextStyle get style => galetText(15);
  static const padding = EdgeInsets.fromLTRB(18, 9, 18, 10);

  /// The widest a bubble grows before its sentence goes on to a second
  /// line, and the narrowest one worth showing.
  static const widest = 440.0;
  static const narrowest = 250.0;

  /// The width its words ask for on one line.
  static double wanted(BuildContext context, String strong, String text) =>
      galetTextWidth(
        context,
        strong.isEmpty ? text : '$strong $text',
        style.copyWith(fontWeight: FontWeight.w700),
      ) +
      padding.horizontal +
      2;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        // The tail, towards the companion.
        if (!tail)
          const SizedBox.shrink()
        else if (below)
          Positioned(
            left: 22,
            top: -5,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: studioSurface,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          )
        else
          Positioned(
            left: -5,
            top: 0,
            bottom: 0,
            child: Center(
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: studioSurface,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        Container(
          key: const Key('galetBubble'),
          width: width,
          padding: padding,
          decoration: BoxDecoration(
            color: studioSurface,
            borderRadius: galetCorners(double.infinity, most: 18),
            boxShadow: _floatShadow,
          ),
          // A sentence alone is one text, which a reader of the screen and
          // a test find whole.
          child: strong.isEmpty
              ? Text(
                  text,
                  maxLines: below ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                )
              : Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$strong ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: text),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
        ),
      ],
    ),
  );
}

/// The title of a panel, or of a part of one.
class GaletHeading extends StatelessWidget {
  const GaletHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(text, style: galetText(14, bold: true, color: studioCaption)),
  );
}

/// A large button of a panel: a picture above its name.
class GaletTile extends StatelessWidget {
  const GaletTile({
    super.key,
    required this.name,
    required this.picture,
    required this.onPressed,
    this.label,
    this.selected = false,
    this.width = 116,
    this.height = 84,
    this.fontSize = 15,
  });

  final String name;
  final Widget picture;
  final VoidCallback? onPressed;

  /// What a screen reader says when it is not [name].
  final String? label;
  final bool selected;
  final double width;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) => GaletButton(
    label: label ?? name,
    onPressed: onPressed,
    selected: selected,
    framed: true,
    width: width,
    height: height,
    corners: 18,
    tip: false,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        picture,
        const SizedBox(height: 5),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: galetText(
            fontSize,
            bold: selected,
            color: selected ? studioGreen : studioInk,
          ),
        ),
      ],
    ),
  );
}

/// A wide button of a panel: a picture, then its name.
class GaletWideButton extends StatelessWidget {
  const GaletWideButton({
    super.key,
    required this.name,
    required this.picture,
    required this.onPressed,
    this.label,
    this.selected = false,
  });

  final String name;
  final Widget picture;
  final VoidCallback? onPressed;

  /// What a screen reader says when it is more than [name].
  final String? label;
  final bool selected;

  @override
  Widget build(BuildContext context) => GaletButton(
    label: label ?? name,
    onPressed: onPressed,
    selected: selected,
    height: 52,
    corners: 18,
    tip: false,
    padding: const EdgeInsets.only(left: 10, right: 18),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        picture,
        const SizedBox(width: 10),
        // Where the room is short — enlarged letters in the drawer of a
        // rail — the name is written a little smaller, never cut.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(name, maxLines: 1, style: galetText(15)),
          ),
        ),
      ],
    ),
  );
}

/// On which side of its button a panel opens.
enum GaletPanelSide { above, below, right, left }

/// What a button of the pebbles opens: the same light surface, a deeper
/// shadow, and a point towards its button. It stands above its button or
/// under it, in the middle of it when the window leaves the room; beside a
/// button of a rail, at its height; and never out of the window.
class GaletPanel extends StatelessWidget {
  const GaletPanel({
    super.key,
    required this.anchor,
    required this.side,
    required this.child,
    this.gap = 14,
    this.padding = const EdgeInsets.all(14),
    this.label,
  });

  /// The button it belongs to, in the frame this panel is laid in.
  final Rect anchor;
  final GaletPanelSide side;
  final Widget child;
  final double gap;
  final EdgeInsets padding;

  /// What a screen reader calls it.
  final String? label;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final frame = constraints.biggest;
      final upright =
          side == GaletPanelSide.above || side == GaletPanelSide.below;
      final roomHigh = switch (side) {
        GaletPanelSide.above => anchor.top - gap - 8,
        GaletPanelSide.below => frame.height - anchor.bottom - gap - 8,
        _ => frame.height - 16,
      };
      final roomWide = switch (side) {
        GaletPanelSide.right => frame.width - anchor.right - gap - 8,
        GaletPanelSide.left => anchor.left - gap - 8,
        _ => frame.width - 24,
      };
      final tail = switch (side) {
        GaletPanelSide.above => Offset(
          (anchor.center.dx - 8).clamp(20.0, math.max(20.0, frame.width - 36)),
          anchor.top - gap - 8,
        ),
        GaletPanelSide.below => Offset(
          (anchor.center.dx - 8).clamp(20.0, math.max(20.0, frame.width - 36)),
          anchor.bottom + gap - 8,
        ),
        GaletPanelSide.right => Offset(
          anchor.right + gap - 8,
          (anchor.center.dy - 8).clamp(20.0, math.max(20.0, frame.height - 36)),
        ),
        GaletPanelSide.left => Offset(
          anchor.left - gap - 8,
          (anchor.center.dy - 8).clamp(20.0, math.max(20.0, frame.height - 36)),
        ),
      };
      final surface = BoxDecoration(
        color: studioSurface,
        borderRadius: galetCorners(double.infinity, most: 26),
        boxShadow: _panelShadow,
      );
      Widget point({required bool shadow}) => Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: studioSurface,
            borderRadius: BorderRadius.circular(3),
            boxShadow: shadow ? _floatShadow : null,
          ),
        ),
      );
      return Stack(
        children: [
          // The point first: the panel is laid over its inner half.
          Positioned(left: tail.dx, top: tail.dy, child: point(shadow: true)),
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _PanelPlace(anchor: anchor, side: side, gap: gap),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(upright ? 120.0 : 96.0, roomHigh),
                  maxWidth: math.max(120.0, roomWide),
                ),
                child: Semantics(
                  container: true,
                  scopesRoute: false,
                  explicitChildNodes: true,
                  label: label,
                  child: DecoratedBox(
                    decoration: surface,
                    child: ClipRRect(
                      borderRadius: galetCorners(double.infinity, most: 26),
                      child: SingleChildScrollView(
                        padding: padding,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The point again, without a shadow, over the edge of the panel:
          // the two make one shape.
          Positioned(
            left: tail.dx,
            top: tail.dy,
            child: IgnorePointer(
              child: ClipRect(
                clipper: _HalfClip(side),
                child: point(shadow: false),
              ),
            ),
          ),
        ],
      );
    },
  );
}

// The half of the point that goes beyond the panel, towards its button.
class _HalfClip extends CustomClipper<Rect> {
  const _HalfClip(this.side);
  final GaletPanelSide side;

  @override
  Rect getClip(Size size) => switch (side) {
    GaletPanelSide.above => Rect.fromLTRB(
      -8,
      size.height / 2 - 1,
      size.width + 8,
      size.height + 8,
    ),
    GaletPanelSide.below => Rect.fromLTRB(
      -8,
      -8,
      size.width + 8,
      size.height / 2 + 1,
    ),
    GaletPanelSide.right => Rect.fromLTRB(
      -8,
      -8,
      size.width / 2 + 1,
      size.height + 8,
    ),
    GaletPanelSide.left => Rect.fromLTRB(
      size.width / 2 - 1,
      -8,
      size.width + 8,
      size.height + 8,
    ),
  };

  @override
  bool shouldReclip(_HalfClip old) => old.side != side;
}

class _PanelPlace extends SingleChildLayoutDelegate {
  const _PanelPlace({
    required this.anchor,
    required this.side,
    required this.gap,
  });
  final Rect anchor;
  final GaletPanelSide side;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    double across() => (anchor.center.dx - child.width / 2)
        .clamp(12.0, math.max(12.0, size.width - 12 - child.width))
        .toDouble();
    double along() => (anchor.center.dy - child.height / 2)
        .clamp(8.0, math.max(8.0, size.height - 8 - child.height))
        .toDouble();
    return switch (side) {
      GaletPanelSide.above => Offset(
        across(),
        math.max(8.0, anchor.top - gap - child.height),
      ),
      GaletPanelSide.below => Offset(across(), anchor.bottom + gap),
      GaletPanelSide.right => Offset(anchor.right + gap, along()),
      GaletPanelSide.left => Offset(
        math.max(8.0, anchor.left - gap - child.width),
        along(),
      ),
    };
  }

  @override
  bool shouldRelayout(_PanelPlace old) =>
      old.anchor != anchor || old.side != side || old.gap != gap;
}

/// The field of colours of the older children (the setting of the adults,
/// off by default): every hue from left to right, from the lightest at the
/// top to the darkest at the bottom; a press or a slide takes the colour
/// under the finger. Under it, a band from white to black.
class GaletColourField extends StatelessWidget {
  const GaletColourField({
    super.key,
    required this.onColour,
    this.width = 336,
    this.height = 168,
    this.greys = 34,
  });

  /// Null while the studio is busy.
  final ValueChanged<int>? onColour;
  final double width;
  final double height;

  /// The height of the band of greys.
  final double greys;

  /// The colour at [at] in a field of [size]: the hue across, the
  /// lightness down, at full strength.
  static int colourAt(Offset at, Size size) {
    final hue = (at.dx / size.width).clamp(0.0, 1.0) * 359.999;
    final light = .92 - (at.dy / size.height).clamp(0.0, 1.0) * .74;
    return HSLColor.fromAHSL(1, hue, .86, light).toColor().toARGB32() &
        0xffffff;
  }

  /// The grey at [x] of a band [width] wide: white on the left, black on
  /// the right.
  static int greyAt(double x, double width) {
    final level = (255 * (1 - (x / width).clamp(0.0, 1.0))).round();
    return level << 16 | level << 8 | level;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onColour != null;
    final corners = galetCorners(double.infinity, most: 14);
    Widget field(Key key, double high, int Function(Offset at) colour) =>
        ClipRRect(
          borderRadius: corners,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled
                ? (details) => onColour!(colour(details.localPosition))
                : null,
            onPanUpdate: enabled
                ? (details) => onColour!(colour(details.localPosition))
                : null,
            child: CustomPaint(
              size: Size(width, high),
              painter: _ColourFieldPainter(greys: high == greys),
            ),
          ),
        );
    return ExcludeSemantics(
      child: Opacity(
        opacity: enabled ? 1 : .38,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(
              const Key('colourField'),
              height,
              (at) => colourAt(at, Size(width, height)),
            ),
            const SizedBox(height: 8),
            field(const Key('greyBand'), greys, (at) => greyAt(at.dx, width)),
          ],
        ),
      ),
    );
  }
}

class _ColourFieldPainter extends CustomPainter {
  const _ColourFieldPainter({required this.greys});
  final bool greys;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Offset.zero & size;
    if (greys) {
      canvas.drawRect(
        frame,
        Paint()
          ..shader = ui.Gradient.linear(frame.centerLeft, frame.centerRight, [
            const Color(0xffffffff),
            const Color(0xff000000),
          ]),
      );
      return;
    }
    // The hues across, in thin bands from the lightest to the darkest.
    final bands = math.max(24, (size.width / 2).round());
    final step = size.width / bands;
    for (var band = 0; band < bands; band++) {
      final hue = (band + .5) / bands * 359.999;
      final strip = Rect.fromLTWH(band * step, 0, step + .6, size.height);
      canvas.drawRect(
        strip,
        Paint()
          ..shader = ui.Gradient.linear(
            strip.topCenter,
            strip.bottomCenter,
            [
              HSLColor.fromAHSL(1, hue, .86, .92).toColor(),
              HSLColor.fromAHSL(1, hue, .86, .55).toColor(),
              HSLColor.fromAHSL(1, hue, .86, .18).toColor(),
            ],
            const [0, .5, 1],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_ColourFieldPainter old) => old.greys != greys;
}

/// The ground of a decor, plain, in the band that the line covers at the
/// bottom of the window: two colours from its top to its bottom, and the
/// line of its front edge.
class GaletGround extends StatelessWidget {
  const GaletGround({
    super.key,
    required this.front,
    this.veil,
    this.above = Size.zero,
  });

  /// The colour at the top, the colour at the bottom, the line of the edge.
  final (Color, Color, Color) front;

  /// What tints the room above at this moment of the day: the ground under
  /// the line is in the same room, at the same hour.
  final DecorVeil? veil;

  /// The frame of the decor above, whose light goes on down here.
  final Size above;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      key: const Key('galetGround'),
      size: Size.infinite,
      painter: _GroundPainter(front, veil, above),
    ),
  );
}

class _GroundPainter extends CustomPainter {
  const _GroundPainter(this.front, this.veil, this.above);
  final (Color, Color, Color) front;
  final DecorVeil? veil;
  final Size above;

  @override
  void paint(Canvas canvas, Size size) {
    final band = Offset.zero & size;
    canvas.drawRect(
      band,
      Paint()
        ..shader = ui.Gradient.linear(band.topCenter, band.bottomCenter, [
          front.$1,
          front.$2,
        ]),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 2.5),
      Paint()..color = front.$3,
    );
    final gradient = veil?.gradient;
    if (gradient != null && !above.isEmpty) {
      // The light across the room, on its own line: the one of the frame
      // above, which ends where this ground starts.
      final (degrees, from, to) = gradient;
      final angle = degrees * math.pi / 180;
      final direction = Offset(math.sin(angle), -math.cos(angle));
      final half =
          (above.width * direction.dx.abs() +
              above.height * direction.dy.abs()) /
          2;
      final centre = Offset(above.width / 2, -above.height / 2);
      canvas.drawRect(
        band,
        Paint()
          ..shader = ui.Gradient.linear(
            centre - direction * half,
            centre + direction * half,
            [from, to],
          ),
      );
    }
    final multiply = veil?.multiply;
    if (multiply != null) {
      canvas.drawRect(
        band,
        Paint()
          ..color = multiply
          ..blendMode = BlendMode.multiply,
      );
    }
  }

  @override
  bool shouldRepaint(_GroundPainter old) =>
      old.front != front || old.veil != veil || old.above != above;
}

/// The shadow of the sheet on the frame, under the sheet wherever the view
/// shows it.
class GaletSheetShadow extends CustomPainter {
  const GaletSheetShadow(this.sheet);
  final Rect sheet;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      sheet.shift(const Offset(0, 2)),
      Paint()..color = const Color(0x1a263f43),
    );
    canvas.drawRect(
      sheet.shift(const Offset(0, 8)),
      Paint()
        ..color = const Color(0x33263f43)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(GaletSheetShadow old) => old.sheet != sheet;
}

/// Nine dots, three by three: « tous les outils », the button of a rail
/// that opens its drawer.
class GaletDots extends StatelessWidget {
  const GaletDots({super.key, this.size = 26, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _DotsPainter(color ?? studioInk)),
  );
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final step = size.width / 3;
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 3; column++) {
        canvas.drawCircle(
          Offset(step * (column + .5), step * (row + .5)),
          size.width * .095,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

/// A round of every hue: the button of « Toutes les couleurs ».
class GaletRainbow extends StatelessWidget {
  const GaletRainbow({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _RainbowPainter()),
  );
}

class _RainbowPainter extends CustomPainter {
  const _RainbowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Offset.zero & size;
    canvas.drawCircle(
      frame.center,
      size.width / 2,
      Paint()
        ..shader = ui.Gradient.sweep(
          frame.center,
          [
            for (var index = 0; index <= 6; index++)
              HSLColor.fromAHSL(1, index * 60 % 360, .86, .58).toColor(),
          ],
          [for (var index = 0; index <= 6; index++) index / 6],
        ),
    );
    // A light heart: the lightest of every colour is in the field too.
    canvas.drawCircle(
      frame.center,
      size.width * .2,
      Paint()..color = const Color(0xffffffff),
    );
  }

  @override
  bool shouldRepaint(_RainbowPainter old) => false;
}
