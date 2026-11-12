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

/// Where the pebbles and the sheet stand in a window.
@immutable
class GaletsLayout {
  const GaletsLayout._({
    required this.window,
    required this.top,
    required this.lineTop,
    required this.band,
    required this.sheet,
    required this.stage,
    required this.bigSheet,
  });

  /// The narrowest window whose line holds the nine tools, the two
  /// settings and the ten colours; and the lowest that leaves a sheet
  /// between the pebbles and the line.
  static const minWidth = 1130.0;
  static const minHeight = 600.0;

  /// The largest letters the pebbles are laid out for as they are.
  static const maxTextScale = 1.15;

  /// The room kept on each side of the window.
  static const side = 16.0;

  /// A cell of a pebble: the smallest comfortable target.
  static const cell = 48.0;

  /// The height of a pebble of the top, and of the line.
  static const topHeight = cell + 12;
  static const lineHeight = cell + 16;

  /// With a decor, the sheet takes no more than this share of the width:
  /// the decor keeps the room to be looked at on each side.
  static const sheetShareWithDecor = .65;

  /// With a decor, how much of its ground shows under the sheet.
  static const groundUnderSheet = 42.0;

  /// Whether the pebbles are the studio of this window (Color 1.2, step
  /// G1): a wide one, that is not a telephone, with ordinary letters and
  /// an interface that is not the simplest. The other windows keep the
  /// studio of before until the pebbles are laid out for them.
  static bool offered({
    required Size window,
    required double textScale,
    required bool phone,
    required bool simple,
  }) =>
      !phone &&
      !simple &&
      textScale <= maxTextScale &&
      window.width >= minWidth &&
      window.height >= minHeight &&
      window.width > window.height;

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
    required Size window,
    EdgeInsets safe = EdgeInsets.zero,
    required double documentWidth,
    required double documentHeight,
    required bool decor,
    bool bigSheet = false,
    double corner = topHeight,
    double padding = 28,
  }) {
    final top = safe.top + (safe.top > 0 ? 8 : 14);
    final foot = safe.bottom > 0 ? safe.bottom + 12 : side;
    final lineTop = window.height - foot - lineHeight;
    final band = decor ? window.height - lineTop + side : 0.0;
    final left = math.max(side, safe.left + 8);
    final right = window.width - math.max(side, safe.right + 8);
    final floor = decor
        ? window.height - band - groundUnderSheet
        : lineTop - 12;
    final ratio = documentWidth / documentHeight;

    Size fitted(double width, double height) {
      final w = math.max(1.0, math.min(width, height * ratio));
      return Size(w, w / ratio);
    }

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
        floor - ceiling,
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
    );
  }

  final Size window;

  /// The top edge of the pebbles of the top, and of the line.
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
      other.window == window &&
      other.top == top &&
      other.lineTop == lineTop &&
      other.band == band &&
      other.sheet == sheet &&
      other.stage == stage &&
      other.bigSheet == bigSheet;

  @override
  int get hashCode =>
      Object.hash(window, top, lineTop, band, sheet, stage, bigSheet);
}

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
class GaletButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
      selected: marksSelection && selected ? true : null,
      expanded: expanded,
      label: label,
      hint: hint,
      onTap: onPressed,
      onLongPress: enabled ? long : null,
      customSemanticsActions: long != null && enabled && longPressLabel != null
          ? {CustomSemanticsAction(label: longPressLabel!): long}
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
  });

  final EduArt art;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final bool marksSelection;
  final double size;

  @override
  Widget build(BuildContext context) => GaletButton(
    label: label,
    onPressed: onPressed,
    selected: selected,
    marksSelection: marksSelection,
    width: GaletsLayout.cell,
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
  });

  final int rgb;
  final String name;
  final VoidCallback? onPressed;

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
  });

  final VoidCallback? onPressed;
  final bool named;
  final bool savedJustNow;
  final bool unsaved;

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
      width: named ? null : GaletsLayout.cell,
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
  });

  final String strong;
  final String text;

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
        if (below)
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
    this.selected = false,
  });

  final String name;
  final Widget picture;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => GaletButton(
    label: name,
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
        Text(name, maxLines: 1, style: galetText(15)),
      ],
    ),
  );
}

/// What a button of the pebbles opens: the same light surface, a deeper
/// shadow, and a point towards its button. It stands above its button
/// ([above]) or under it, in the middle of it when the window leaves the
/// room, and never out of the window.
class GaletPanel extends StatelessWidget {
  const GaletPanel({
    super.key,
    required this.anchor,
    required this.above,
    required this.child,
    this.gap = 14,
    this.padding = const EdgeInsets.all(14),
    this.label,
  });

  /// The button it belongs to, in the frame this panel is laid in.
  final Rect anchor;
  final bool above;
  final Widget child;
  final double gap;
  final EdgeInsets padding;

  /// What a screen reader calls it.
  final String? label;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final frame = constraints.biggest;
      final room = above
          ? anchor.top - gap - 8
          : frame.height - anchor.bottom - gap - 8;
      final tailTop = above ? anchor.top - gap - 8 : anchor.bottom + gap - 8;
      final surface = BoxDecoration(
        color: studioSurface,
        borderRadius: galetCorners(double.infinity, most: 26),
        boxShadow: _panelShadow,
      );
      return Stack(
        children: [
          // The point first: the panel is laid over its inner half.
          Positioned(
            left: (anchor.center.dx - 8).clamp(20.0, frame.width - 36),
            top: tailTop,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: studioSurface,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: _floatShadow,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _PanelPlace(anchor: anchor, above: above, gap: gap),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(120.0, room),
                  maxWidth: math.max(120.0, frame.width - 24),
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
            left: (anchor.center.dx - 8).clamp(20.0, frame.width - 36),
            top: tailTop,
            child: IgnorePointer(
              child: ClipRect(
                clipper: _HalfClip(lower: above),
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: studioSurface,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

// The half of the point that goes beyond the panel.
class _HalfClip extends CustomClipper<Rect> {
  const _HalfClip({required this.lower});
  final bool lower;

  @override
  Rect getClip(Size size) => lower
      ? Rect.fromLTRB(-8, size.height / 2 - 1, size.width + 8, size.height + 8)
      : Rect.fromLTRB(-8, -8, size.width + 8, size.height / 2 + 1);

  @override
  bool shouldReclip(_HalfClip old) => old.lower != lower;
}

class _PanelPlace extends SingleChildLayoutDelegate {
  const _PanelPlace({
    required this.anchor,
    required this.above,
    required this.gap,
  });
  final Rect anchor;
  final bool above;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final left = (anchor.center.dx - child.width / 2)
        .clamp(12.0, math.max(12.0, size.width - 12 - child.width))
        .toDouble();
    final top = above
        ? math.max(8.0, anchor.top - gap - child.height)
        : anchor.bottom + gap;
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_PanelPlace old) =>
      old.anchor != anchor || old.above != above || old.gap != gap;
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
