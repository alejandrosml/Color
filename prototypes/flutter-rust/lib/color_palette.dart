// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/cupertino.dart'
    show CupertinoSlider, CupertinoThumbPainter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fit_to_screen.dart';
import 'rust_document.dart' show RustDocument;
import 'studio_colors.dart';
import 'language.dart';

enum PaintColorTarget { stroke, fill }

@immutable
class NamedPaintColor {
  const NamedPaintColor(this.frenchName, this.rgb);

  /// Its name in French; [name] gives it in the language of the interface.
  final String frenchName;
  final int rgb;
  String get name => tr(frenchName);
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

const _paletteInk = Color(0xff263f43);

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
  if (hsv.value < .12) return tr('Noir');
  if (hsv.saturation < .12) {
    return hsv.value > .9 ? tr('Blanc cassé') : tr('Gris');
  }
  final hueName = _hueName(hsv.hue);
  // « Rouge foncé », but « Dark red ».
  final within = inEnglish ? hueName.toLowerCase() : hueName;
  return hsv.value < .48
      ? trf('{0} foncé', [within])
      : hsv.saturation < .45
      ? trf('{0} doux', [within])
      : hueName;
}

String _hueName(double hue) => switch (hue) {
  < 15 => tr('Rouge'),
  < 45 => tr('Orange'),
  < 75 => tr('Jaune'),
  < 165 => tr('Vert'),
  < 200 => tr('Turquoise'),
  < 260 => tr('Bleu'),
  < 305 => tr('Violet'),
  < 345 => tr('Rose'),
  _ => tr('Rouge'),
};

/// Session-only, newest-first history. A caller may retain one instance across
/// document changes and dispose it with the studio. No disk state is involved.
class RecentPaintColors extends ChangeNotifier {
  /// [initial]: the colours kept from an earlier session, the latest first.
  RecentPaintColors({this.capacity = 8, List<int> initial = const []})
    : _colors = List.unmodifiable(
        initial.where((rgb) => rgb >= 0 && rgb <= 0xffffff).take(capacity),
      ) {
    RangeError.checkValueInInterval(capacity, 1, 16, 'capacity');
  }
  final int capacity;
  List<int> _colors;
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

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    super.key,
    required this.rgb,
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final int rgb;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  static const size = paletteSwatchSize;

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
            color: selected ? studioGreen : studioSwatchRing,
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

  /// The paint mixed into the colour, and how much of it (Color 1.1).
  int _mixPaint = simplePaintColors.first.rgb;
  double _mixAmount = .5;

  /// The colour and the paint mixed as paints mix, by the core; null
  /// without it.
  int? get _mixed {
    try {
      return RustDocument.mixColours(_rgb, _mixPaint, _mixAmount);
    } catch (_) {
      return null;
    }
  }

  void _change(HSVColor color) => setState(() {
    _hsv = color;
    _rgb = color.toColor().toARGB32() & 0xffffff;
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('paintColorDialog'),
    title: Text(tr('Trouve ta couleur')),
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
            label: trf('Aperçu : {0}', [paintColorName(_rgb)]),
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
            Text(tr('Tes couleurs récentes'), style: TextStyle(fontSize: 12)),
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
                    label: trf('Couleur récente {0}, {1}', [
                      entry.$1 + 1,
                      paintColorName(entry.$2),
                    ]),
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
          Text(tr('Des nuances à essayer'), style: TextStyle(fontSize: 12)),
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
          Text(tr('Ou invente la tienne'), style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          _ColorAxisSlider(
            key: const Key('paintHue'),
            label: tr('Couleur'),
            value: _hsv.hue / 360,
            describe: (value) => _hueName(value * 360),
            onChanged: (value) => _change(_hsv.withHue(value * 360)),
          ),
          _ColorAxisSlider(
            key: const Key('paintIntensity'),
            label: tr('Intensité'),
            value: _hsv.saturation,
            describe: (value) => '${(value * 100).round()} %',
            onChanged: (value) => _change(_hsv.withSaturation(value)),
          ),
          _ColorAxisSlider(
            key: const Key('paintLightness'),
            label: tr('Clarté'),
            value: _hsv.value,
            describe: (value) => '${(value * 100).round()} %',
            onChanged: (value) => _change(_hsv.withValue(value)),
          ),
          // Last, as an idea to try: two paints mixed (Color 1.1).
          ..._mixer(),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const Key('cancelPaintColor'),
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Annuler')),
      ),
      FilledButton(
        key: const Key('confirmPaintColor'),
        onPressed: () => Navigator.pop(context, _rgb),
        child: Text(tr('Choisir cette couleur')),
      ),
    ],
  );

  // Two paints mixed as on a palette: blue and yellow make green, not the
  // grey of their numbers. Each « Mélanger » mixes once more.
  List<Widget> _mixer() {
    final mixed = _mixed;
    if (mixed == null) return const [];
    return [
      const SizedBox(height: 18),
      Text(tr('Mélange-la avec une peinture'), style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final paint in simplePaintColors)
            _ColorSwatch(
              key: Key('mixPaint-${paint.rgb.toRadixString(16)}'),
              rgb: paint.rgb,
              label: trf('Mélanger avec {0}', [paint.name]),
              selected: _mixPaint == paint.rgb,
              onPressed: () => setState(() => _mixPaint = paint.rgb),
            ),
        ],
      ),
      const SizedBox(height: 8),
      // The slider takes the width; its two ends are named under it, so
      // that enlarged letters never push it out of a narrow dialog.
      Slider(
        key: const Key('mixAmount'),
        value: _mixAmount,
        min: .1,
        max: .9,
        divisions: 8,
        semanticFormatterCallback: (value) =>
            trf('{0} % de peinture', [(value * 100).round()]),
        onChanged: (value) => setState(() => _mixAmount = value),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(tr('Un peu'), style: TextStyle(fontSize: 12))),
          Flexible(
            child: Text(
              tr('Beaucoup'),
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 14,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            key: const Key('mixPreview'),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _color(mixed),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xff9baea3)),
            ),
          ),
          FilledButton.tonal(
            key: const Key('mixColours'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => setState(() {
              _rgb = mixed;
              _hsv = HSVColor.fromColor(_color(mixed));
            }),
            child: Text(tr('Mélanger')),
          ),
        ],
      ),
    ];
  }
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
                            color: _focused ? studioGreen : Colors.transparent,
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
                            activeColor: studioGreen,
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
