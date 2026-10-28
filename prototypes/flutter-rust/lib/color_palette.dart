// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/cupertino.dart'
    show CupertinoSlider, CupertinoThumbPainter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fit_to_screen.dart';
import 'studio_colors.dart';
import 'studio_text.dart';

enum PaintColorTarget { stroke, fill }

@immutable
class NamedPaintColor {
  const NamedPaintColor(this.name, this.rgb);
  final String name;
  final int rgb;
}

/// The original ten named colors remain the first, stable choices.
const paintColors = <NamedPaintColor>[
  NamedPaintColor('Encre', 0x33484d),
  NamedPaintColor('Blanc', 0xffffff),
  NamedPaintColor('Coquelicot', 0xd75e56),
  NamedPaintColor('Pêche', 0xe69976),
  NamedPaintColor('Soleil', 0xeebf4e),
  NamedPaintColor('Prairie', 0x78a66f),
  NamedPaintColor('Sapin', 0x388778),
  NamedPaintColor('Bleu denim', 0x477fb2),
  NamedPaintColor('Lavande', 0x9385bc),
  NamedPaintColor('Framboise', 0xc96d93),
];

/// More named colours. They join the row of the palette after the first ten,
/// in this order and as far as the row has room for them; the colour dialog
/// offers them all, whatever the width of the window.
const morePaintColors = <NamedPaintColor>[
  NamedPaintColor('Orange', 0xef9439),
  NamedPaintColor('Chocolat', 0x79513e),
  NamedPaintColor('Ciel', 0xa8d8f0),
  NamedPaintColor('Rose tendre', 0xf4b7cf),
  NamedPaintColor('Gris', 0x9aa3a5),
  NamedPaintColor('Rouge vif', 0xe83d48),
  NamedPaintColor('Vert vif', 0x4db266),
  NamedPaintColor('Bleu vif', 0x3370d1),
  NamedPaintColor('Crème', 0xfff0b8),
  NamedPaintColor('Menthe', 0xa4e0c1),
  NamedPaintColor('Prune', 0x773f70),
  NamedPaintColor('Vert forêt', 0x245846),
  NamedPaintColor('Bleu nuit', 0x283b78),
  NamedPaintColor('Noir', 0x1a1a1a),
];

/// The colours of the simplest interface: few, frank and far apart, each one
/// a named colour of the lists above.
const simplePaintColors = <NamedPaintColor>[
  NamedPaintColor('Noir', 0x1a1a1a),
  NamedPaintColor('Chocolat', 0x79513e),
  NamedPaintColor('Rouge vif', 0xe83d48),
  NamedPaintColor('Orange', 0xef9439),
  NamedPaintColor('Soleil', 0xeebf4e),
  NamedPaintColor('Vert vif', 0x4db266),
  NamedPaintColor('Bleu vif', 0x3370d1),
  NamedPaintColor('Lavande', 0x9385bc),
  NamedPaintColor('Rose tendre', 0xf4b7cf),
  NamedPaintColor('Blanc', 0xffffff),
];

/// The colour of the simplest interface that looks most like [rgb]: the
/// nearest in red, green and blue, green counting most as the eye does.
int nearestSimplePaintColor(int rgb) {
  int distance(int other) {
    final red = ((rgb >> 16) & 0xff) - ((other >> 16) & 0xff);
    final green = ((rgb >> 8) & 0xff) - ((other >> 8) & 0xff);
    final blue = (rgb & 0xff) - (other & 0xff);
    return 3 * red * red + 4 * green * green + 2 * blue * blue;
  }

  var best = simplePaintColors.first.rgb;
  for (final entry in simplePaintColors) {
    if (distance(entry.rgb) < distance(best)) best = entry.rgb;
  }
  return best;
}

/// Side of one swatch: the smallest comfortable target.
const paletteSwatchSize = 48.0;

/// Side of a swatch of the simplest interface.
const simpleSwatchSize = 60.0;

/// How many swatches fit side by side in [width] when at least [gap] apart.
int paletteRowCount(double width, double gap) => width.isFinite && width > 0
    ? ((width + gap) / (paletteSwatchSize + gap)).floor()
    : 0;

const _paletteInk = Color(0xff263f43);
const _paletteGreen = Color(0xff176c5f);

Color _color(int rgb) {
  RangeError.checkValueInInterval(rgb, 0, 0xffffff, 'rgb');
  return Color(0xff000000 | rgb);
}

/// The tick of a chosen swatch: ink or white, whichever stands out more on
/// the swatch. The worse of the two is never below 3.3 to 1.
Color paletteTickColor(int rgb) {
  final light = _color(rgb).computeLuminance();
  final withWhite = 1.05 / (light + .05);
  final withInk = (light + .05) / (_paletteInk.computeLuminance() + .05);
  return withInk > withWhite ? _paletteInk : Colors.white;
}

String paintColorName(int rgb) {
  for (final entry in [...paintColors, ...morePaintColors]) {
    if (entry.rgb == rgb) return entry.name;
  }
  final hsv = HSVColor.fromColor(_color(rgb));
  if (hsv.value < .12) return 'Noir';
  if (hsv.saturation < .12) return hsv.value > .9 ? 'Blanc cassé' : 'Gris';
  final hueName = _hueName(hsv.hue);
  return hsv.value < .48
      ? '$hueName foncé'
      : hsv.saturation < .45
      ? '$hueName doux'
      : hueName;
}

String _hueName(double hue) => switch (hue) {
  < 15 => 'Rouge',
  < 45 => 'Orange',
  < 75 => 'Jaune',
  < 165 => 'Vert',
  < 200 => 'Turquoise',
  < 260 => 'Bleu',
  < 305 => 'Violet',
  < 345 => 'Rose',
  _ => 'Rouge',
};

/// Session-only, newest-first history. A caller may retain one instance across
/// document changes and dispose it with the studio. No disk state is involved.
class RecentPaintColors extends ChangeNotifier {
  RecentPaintColors({this.capacity = 8}) {
    RangeError.checkValueInInterval(capacity, 1, 16, 'capacity');
  }
  final int capacity;
  List<int> _colors = const [];
  List<int> get colors => _colors;

  void remember(int rgb) {
    RangeError.checkValueInInterval(rgb, 0, 0xffffff, 'rgb');
    if (_colors.isNotEmpty && _colors.first == rgb) return;
    _colors = List.unmodifiable(
      [rgb, ..._colors.where((value) => value != rgb)].take(capacity),
    );
    notifyListeners();
  }
}

/// Palette only: it reports the colour chosen and edits nothing itself. The
/// parent owns the active target, passes that target's selectedRgb, and
/// decides what the choice changes — the chosen element, at once, if any.
///
/// Native desktop commands need the same modal guard as other studio dialogs:
/// use onDialogVisibilityChanged to block them while the custom chooser opens.
class ColorPalette extends StatefulWidget {
  const ColorPalette({
    super.key,
    required this.selectedRgb,
    required this.onColorSelected,
    this.canFill = false,
    this.target = PaintColorTarget.stroke,
    this.onTargetChanged,
    this.history,
    this.onDialogVisibilityChanged,
    this.compact = false,
    this.trailingControl,
    this.onPickFromDrawing,
    this.picking = false,
    this.simple = false,
    this.rail = false,
  });

  /// The width a rail of [columns] swatches takes, without its border.
  static double railWidth({required bool simple, int columns = 2}) =>
      columns * (simple ? simpleSwatchSize : paletteSwatchSize) +
      (columns - 1) * 8;

  final int selectedRgb;
  final ValueChanged<int>? onColorSelected;
  final bool canFill;
  final PaintColorTarget target;
  final ValueChanged<PaintColorTarget>? onTargetChanged;
  final RecentPaintColors? history;
  final ValueChanged<bool>? onDialogVisibilityChanged;

  /// Saves vertical space by placing recent choices inside the color dialog.
  final bool compact;
  final Widget? trailingControl;

  /// Arms or disarms the pipette: the parent then takes the colour under the
  /// next click on the sheet. Null hides the button.
  final VoidCallback? onPickFromDrawing;

  /// The pipette is waiting for that click.
  final bool picking;

  /// The simplest interface: a few large colours and [trailingControl],
  /// nothing to read, no dialog, no pipette, no second target.
  final bool simple;

  /// The column of a telephone, beside the sheet: every colour in two
  /// columns, and above them the controls as pictures, two by line.
  final bool rail;

  @override
  State<ColorPalette> createState() => _ColorPaletteState();
}

class _ColorPaletteState extends State<ColorPalette> {
  final _localHistory = RecentPaintColors();
  bool _dialogOpen = false;
  RecentPaintColors get _history => widget.history ?? _localHistory;
  bool get _enabled => widget.onColorSelected != null && !_dialogOpen;

  @override
  void dispose() {
    _localHistory.dispose();
    super.dispose();
  }

  void _choose(int rgb) {
    if (!_enabled) return;
    _history.remember(rgb);
    widget.onColorSelected!(rgb);
  }

  Future<void> _moreColors() async {
    if (!_enabled) return;
    // The parent may disable its controls while the modal guard is active.
    // Keep this authorized callback until the dialog closes and the guard is
    // released; the next parent rebuild need not have occurred yet.
    final onSelected = widget.onColorSelected!;
    setState(() => _dialogOpen = true);
    final visibilityChanged = widget.onDialogVisibilityChanged;
    visibilityChanged?.call(true);
    int? chosen;
    try {
      chosen = await showPaintColorDialog(
        context,
        initialRgb: widget.selectedRgb,
        recentColors: _history.colors,
      );
    } finally {
      visibilityChanged?.call(false);
      if (mounted) setState(() => _dialogOpen = false);
    }
    if (mounted && chosen != null) {
      _history.remember(chosen);
      onSelected(chosen);
    }
  }

  Widget _rail(BuildContext context) {
    final swatches = Wrap(
      key: const Key('paintColorRail'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final swatch
            in widget.simple
                ? simplePaintColors
                : [...paintColors, ...morePaintColors])
          _ColorSwatch(
            key: Key('color-${swatch.rgb.toRadixString(16)}'),
            rgb: swatch.rgb,
            label: swatch.name,
            selected: widget.selectedRgb == swatch.rgb,
            onPressed: _enabled ? () => _choose(swatch.rgb) : null,
            size: widget.simple ? simpleSwatchSize : paletteSwatchSize,
          ),
      ],
    );
    if (widget.simple) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.trailingControl != null) ...[
            widget.trailingControl!,
            const SizedBox(height: 10),
          ],
          swatches,
        ],
      );
    }
    final effectiveTarget = widget.canFill
        ? widget.target
        : PaintColorTarget.stroke;
    Widget square(Widget child) => SizedBox.square(dimension: 48, child: child);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canFill) ...[
          Row(
            key: const Key('paintColorTarget'),
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final target in PaintColorTarget.values)
                square(
                  IconButton.outlined(
                    key: ValueKey('paint-target-${target.name}'),
                    tooltip: target == PaintColorTarget.stroke
                        ? 'La couleur du trait'
                        : 'La couleur de l’intérieur',
                    isSelected: effectiveTarget == target,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      visualDensity: VisualDensity.standard,
                    ),
                    onPressed: !_enabled || widget.onTargetChanged == null
                        ? null
                        : () => widget.onTargetChanged!(target),
                    icon: Icon(
                      target == PaintColorTarget.stroke
                          ? Icons.edit_outlined
                          : Icons.format_color_fill,
                      semanticLabel: target == PaintColorTarget.stroke
                          ? 'Trait'
                          : 'Intérieur',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (widget.onPickFromDrawing != null)
              square(
                IconButton.outlined(
                  key: const Key('pickPaintColor'),
                  tooltip: 'Pipette : reprendre une couleur du dessin',
                  isSelected: widget.picking,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    visualDensity: VisualDensity.standard,
                  ),
                  onPressed: _enabled ? widget.onPickFromDrawing : null,
                  icon: const Icon(
                    Icons.colorize,
                    semanticLabel: 'Pipette : reprendre une couleur du dessin',
                  ),
                ),
              ),
            square(
              IconButton.outlined(
                key: const Key('morePaintColors'),
                tooltip: 'Autres couleurs',
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  visualDensity: VisualDensity.standard,
                ),
                onPressed: _enabled ? _moreColors : null,
                icon: const Icon(
                  Icons.palette_outlined,
                  semanticLabel: 'Autres couleurs',
                ),
              ),
            ),
          ],
        ),
        if (widget.trailingControl != null) ...[
          const SizedBox(height: 10),
          widget.trailingControl!,
        ],
        const SizedBox(height: 10),
        swatches,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rail) return _rail(context);
    if (widget.simple) {
      return Wrap(
        key: const Key('simplePaintColors'),
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final swatch in simplePaintColors)
            _ColorSwatch(
              key: Key('color-${swatch.rgb.toRadixString(16)}'),
              rgb: swatch.rgb,
              label: swatch.name,
              selected: widget.selectedRgb == swatch.rgb,
              onPressed: _enabled ? () => _choose(swatch.rgb) : null,
              size: simpleSwatchSize,
            ),
          if (widget.trailingControl != null) widget.trailingControl!,
        ],
      );
    }
    final gap = widget.compact ? 8.0 : 9.0;
    final effectiveTarget = widget.canFill
        ? widget.target
        : PaintColorTarget.stroke;
    final tight = MediaQuery.sizeOf(context).width < 750;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.canFill)
              Wrap(
                key: const Key('paintColorTarget'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final target in PaintColorTarget.values)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: ChoiceChip(
                        key: ValueKey('paint-target-${target.name}'),
                        label: Text(
                          target == PaintColorTarget.stroke
                              ? 'Trait'
                              : 'Intérieur',
                          style: const TextStyle(fontSize: 12),
                        ),
                        avatar: Icon(
                          target == PaintColorTarget.stroke
                              ? Icons.edit_outlined
                              : Icons.format_color_fill,
                          size: 18,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        visualDensity: VisualDensity.standard,
                        selected: effectiveTarget == target,
                        onSelected: !_enabled || widget.onTargetChanged == null
                            ? null
                            : (_) => widget.onTargetChanged!(target),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                      ),
                    ),
                ],
              )
            else
              Text(
                widget.compact
                    ? paintColorName(widget.selectedRgb)
                    : 'COULEURS · ${paintColorName(widget.selectedRgb)}',
                style: const TextStyle(fontSize: 11, color: _paletteInk),
              ),
            if (widget.trailingControl != null) widget.trailingControl!,
            if (widget.onPickFromDrawing != null)
              IconButton.outlined(
                key: const Key('pickPaintColor'),
                tooltip: 'Pipette : reprendre une couleur du dessin',
                isSelected: widget.picking,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  visualDensity: VisualDensity.standard,
                ),
                onPressed: _enabled ? widget.onPickFromDrawing : null,
                icon: const Icon(
                  Icons.colorize,
                  semanticLabel: 'Pipette : reprendre une couleur du dessin',
                ),
              ),
            // With the pipette beside it, the written button would push the
            // row onto a second line in a narrow panel: its picture stays.
            if (widget.compact || (widget.onPickFromDrawing != null && tight))
              IconButton.outlined(
                key: const Key('morePaintColors'),
                tooltip: 'Autres couleurs',
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  visualDensity: VisualDensity.standard,
                ),
                onPressed: _enabled ? _moreColors : null,
                icon: const Icon(
                  Icons.palette_outlined,
                  semanticLabel: 'Autres couleurs',
                ),
              )
            else
              OutlinedButton.icon(
                key: const Key('morePaintColors'),
                onPressed: _enabled ? _moreColors : null,
                icon: const Icon(Icons.palette_outlined, size: 20),
                label: const Text('Autres couleurs'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  visualDensity: VisualDensity.standard,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: studioLabelStyle(context, 12),
                ),
              ),
          ],
        ),
        SizedBox(height: gap),
        LayoutBuilder(
          builder: (context, constraints) {
            Widget swatchOf(NamedPaintColor swatch) => _ColorSwatch(
              key: Key('color-${swatch.rgb.toRadixString(16)}'),
              rgb: swatch.rgb,
              label: swatch.name,
              selected: widget.selectedRgb == swatch.rgb,
              onPressed: _enabled ? () => _choose(swatch.rgb) : null,
            );
            final room = paletteRowCount(constraints.maxWidth, gap);
            if (room < paintColors.length) {
              // Too narrow for the first ten on one line: they wrap.
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [for (final swatch in paintColors) swatchOf(swatch)],
              );
            }
            // One full line: the first ten, then as many more colours as
            // fit, spread from one edge of the panel to the other.
            return Row(
              key: const Key('paintColorRow'),
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final swatch in [
                  ...paintColors,
                  ...morePaintColors,
                ].take(room))
                  swatchOf(swatch),
              ],
            );
          },
        ),
        if (!widget.compact) ...[
          SizedBox(height: gap),
          ListenableBuilder(
            listenable: _history,
            builder: (context, _) => Wrap(
              spacing: gap,
              runSpacing: gap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'RÉCENTES',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: .7,
                    color: _paletteInk,
                  ),
                ),
                if (_history.colors.isEmpty)
                  const SizedBox(
                    height: 48,
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        'Tes choix apparaîtront ici.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                for (final entry in _history.colors.indexed)
                  _ColorSwatch(
                    key: Key(
                      'recent-paint-color-${entry.$2.toRadixString(16)}',
                    ),
                    rgb: entry.$2,
                    label:
                        'Couleur récente ${entry.$1 + 1}, ${paintColorName(entry.$2)}',
                    selected: widget.selectedRgb == entry.$2,
                    onPressed: _enabled ? () => _choose(entry.$2) : null,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    super.key,
    required this.rgb,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.size = paletteSwatchSize,
  });
  final int rgb;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = _color(rgb);
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: Size.square(size),
          visualDensity: VisualDensity.standard,
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: .4),
          foregroundColor: paletteTickColor(rgb),
          side: BorderSide(
            color: selected ? _paletteGreen : studioSwatchRing,
            width: selected ? 3 : 1,
          ),
          padding: EdgeInsets.zero,
        ),
        icon: Semantics(
          label: label,
          selected: selected,
          child: selected
              ? const Icon(Icons.check_rounded, size: 22)
              : const SizedBox.square(dimension: 22),
        ),
      ),
    );
  }
}

/// Returns only a confirmed RGB value. Cancelling leaves the caller untouched.
Future<int?> showPaintColorDialog(
  BuildContext context, {
  required int initialRgb,
  List<int> recentColors = const [],
}) => showDialog<int>(
  context: context,
  builder: (_) => FitDialog(
    child: PaintColorDialog(
      initialRgb: initialRgb,
      recentColors: List.unmodifiable(recentColors.take(8)),
    ),
  ),
);

class PaintColorDialog extends StatefulWidget {
  const PaintColorDialog({
    super.key,
    required this.initialRgb,
    this.recentColors = const [],
  });
  final int initialRgb;
  final List<int> recentColors;

  @override
  State<PaintColorDialog> createState() => _PaintColorDialogState();
}

class _PaintColorDialogState extends State<PaintColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(_color(widget.initialRgb));
  late int _rgb = widget.initialRgb;

  void _change(HSVColor color) => setState(() {
    _hsv = color;
    _rgb = color.toColor().toARGB32() & 0xffffff;
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('paintColorDialog'),
    title: const Text('Trouve ta couleur'),
    scrollable: true,
    insetPadding: const EdgeInsets.all(16),
    content: SizedBox(
      // Seven swatches side by side: the fourteen shades take two lines.
      width: 384,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            key: const Key('paintColorPreview'),
            label: 'Aperçu : ${paintColorName(_rgb)}',
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _color(_rgb),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xff9baea3)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    paintColorName(_rgb),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          if (widget.recentColors.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('Tes couleurs récentes', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in widget.recentColors.take(8).indexed)
                  _ColorSwatch(
                    key: Key(
                      'dialog-recent-color-${entry.$2.toRadixString(16)}',
                    ),
                    rgb: entry.$2,
                    label:
                        'Couleur récente ${entry.$1 + 1}, ${paintColorName(entry.$2)}',
                    selected: _rgb == entry.$2,
                    onPressed: () => setState(() {
                      _rgb = entry.$2;
                      _hsv = HSVColor.fromColor(_color(entry.$2));
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          const Text('Des nuances à essayer', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final swatch in morePaintColors)
                _ColorSwatch(
                  key: Key('shade-${swatch.rgb.toRadixString(16)}'),
                  rgb: swatch.rgb,
                  label: swatch.name,
                  selected: _rgb == swatch.rgb,
                  onPressed: () => setState(() {
                    _rgb = swatch.rgb;
                    _hsv = HSVColor.fromColor(_color(swatch.rgb));
                  }),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Ou invente la tienne', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          _ColorAxisSlider(
            key: const Key('paintHue'),
            label: 'Couleur',
            value: _hsv.hue / 360,
            describe: (value) => _hueName(value * 360),
            onChanged: (value) => _change(_hsv.withHue(value * 360)),
          ),
          _ColorAxisSlider(
            key: const Key('paintIntensity'),
            label: 'Intensité',
            value: _hsv.saturation,
            describe: (value) => '${(value * 100).round()} %',
            onChanged: (value) => _change(_hsv.withSaturation(value)),
          ),
          _ColorAxisSlider(
            key: const Key('paintLightness'),
            label: 'Clarté',
            value: _hsv.value,
            describe: (value) => '${(value * 100).round()} %',
            onChanged: (value) => _change(_hsv.withValue(value)),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const Key('cancelPaintColor'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        key: const Key('confirmPaintColor'),
        onPressed: () => Navigator.pop(context, _rgb),
        child: const Text('Choisir cette couleur'),
      ),
    ],
  );
}

class _ColorAxisIntent extends Intent {
  const _ColorAxisIntent(this.delta);
  final double delta;
}

class _ColorAxisSlider extends StatefulWidget {
  const _ColorAxisSlider({
    super.key,
    required this.label,
    required this.value,
    required this.describe,
    required this.onChanged,
  });
  final String label;
  final double value;
  final String Function(double value) describe;
  final ValueChanged<double> onChanged;

  @override
  State<_ColorAxisSlider> createState() => _ColorAxisSliderState();
}

class _ColorAxisSliderState extends State<_ColorAxisSlider> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  double _bounded(double value) => value.clamp(0.0, 1.0).toDouble();
  void _change(double value) {
    final bounded = _bounded(value);
    if (bounded != widget.value) widget.onChanged(bounded);
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.label, style: const TextStyle(fontSize: 12)),
              ),
              Text(
                widget.describe(widget.value),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
          FocusableActionDetector(
            focusNode: _focus,
            includeFocusSemantics: false,
            onFocusChange: (focused) => setState(() => _focused = focused),
            shortcuts: {
              const SingleActivator(LogicalKeyboardKey.arrowRight):
                  _ColorAxisIntent(rtl ? -.01 : .01),
              const SingleActivator(LogicalKeyboardKey.arrowLeft):
                  _ColorAxisIntent(rtl ? .01 : -.01),
              const SingleActivator(LogicalKeyboardKey.arrowUp):
                  const _ColorAxisIntent(.01),
              const SingleActivator(LogicalKeyboardKey.arrowDown):
                  const _ColorAxisIntent(-.01),
              const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
                  _ColorAxisIntent(rtl ? -.1 : .1),
              const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
                  _ColorAxisIntent(rtl ? .1 : -.1),
            },
            actions: {
              _ColorAxisIntent: CallbackAction<_ColorAxisIntent>(
                onInvoke: (intent) {
                  _change(widget.value + intent.delta);
                  return null;
                },
              ),
            },
            child: Semantics(
              key: ValueKey('paintAxis-${widget.label}'),
              container: true,
              excludeSemantics: true,
              slider: true,
              label: widget.label,
              value: widget.describe(widget.value),
              increasedValue: widget.value < 1
                  ? widget.describe(_bounded(widget.value + .01))
                  : null,
              decreasedValue: widget.value > 0
                  ? widget.describe(_bounded(widget.value - .01))
                  : null,
              enabled: true,
              focusable: true,
              focused: _focused,
              onFocus: _focus.requestFocus,
              onIncrease: widget.value < 1
                  ? () => _change(widget.value + .01)
                  : null,
              onDecrease: widget.value > 0
                  ? () => _change(widget.value - .01)
                  : null,
              child: SizedBox(
                height: 48,
                child: LayoutBuilder(
                  builder: (context, constraints) => Listener(
                    onPointerDown: (_) => _focus.requestFocus(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTapUp: (details) {
                        const inset = 8.0 + CupertinoThumbPainter.radius;
                        var fraction = _bounded(
                          (details.localPosition.dx - inset) /
                              math.max(1, constraints.maxWidth - 2 * inset),
                        );
                        if (rtl) fraction = 1 - fraction;
                        _change(fraction);
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _focused
                                ? _paletteGreen
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: CupertinoSlider(
                            value: widget.value,
                            min: 0,
                            max: 1,
                            divisions: 100,
                            activeColor: _paletteGreen,
                            onChanged: _change,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
