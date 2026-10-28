// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'brush_width_control.dart';
import 'child_art.dart';
import 'size_choice.dart';
import 'stamp_catalog.dart';
import 'stamp_dialog.dart';

/// The width of a trait or of an outline: a slider and the number it shows.
class OutlineWidthControl extends StatelessWidget {
  const OutlineWidthControl({
    super.key,
    required this.value,
    required this.shown,
    required this.narrow,
    required this.onChanged,
    this.onChangeEnd,
    this.rail = false,
  });

  /// In the column of a telephone: the word and the number above the
  /// slider, which takes the whole width.
  final bool rail;

  /// Where the slider stands.
  final double value;

  /// The number written beside it: the width of the chosen element, or the
  /// value of the slider while a slide is giving it another one.
  final double shown;
  final bool narrow;
  final ValueChanged<double>? onChanged;

  /// The hand has left the slider, or a key or a click has changed it once.
  final VoidCallback? onChangeEnd;

  @override
  Widget build(BuildContext context) => rail
      ? Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Épaisseur', style: TextStyle(fontSize: 11)),
                ),
                Text('${shown.round()}', style: const TextStyle(fontSize: 11)),
              ],
            ),
            SizedBox(
              height: 48,
              child: BrushWidthControl(
                value: value,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ],
        )
      : _line();

  Widget _line() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Épaisseur', style: TextStyle(fontSize: 11)),
      const SizedBox(width: 8),
      SizedBox(
        width: narrow ? 80 : 100,
        height: 48,
        child: BrushWidthControl(
          value: value,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
      SizedBox(
        width: 24,
        child: Text('${shown.round()}', style: const TextStyle(fontSize: 11)),
      ),
    ],
  );
}

/// « Taille » for what is placed with a click: three concrete sizes for the
/// letters of a text or for a stamp, and for a stamp the button that chooses
/// which one.
class PlacedSizeControl extends StatelessWidget {
  const PlacedSizeControl({
    super.key,
    required this.size,
    required this.what,
    required this.onSizeChanged,
    this.forStamp = false,
    this.stamp,
    this.stampRgb = 0,
    this.onChooseStamp,
    this.rail = false,
  });

  /// In the column of a telephone: the stamp, then the sizes, one above
  /// the other.
  final bool rail;

  final ObjectSize size;

  /// « du texte » or « du tampon », for the spoken names of the sizes.
  final String what;
  final ValueChanged<ObjectSize>? onSizeChanged;

  /// Whether the button that chooses the stamp is shown; [stamp] is null
  /// when the catalogue could not be read.
  final bool forStamp;
  final StampArt? stamp;
  final int stampRgb;
  final VoidCallback? onChooseStamp;

  Widget _stampButton() => OutlinedButton(
    key: const Key('chooseStamp'),
    onPressed: onChooseStamp,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      visualDensity: VisualDensity.standard,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    // Named on the button itself, which keeps its own action.
    child: Semantics(
      label: 'Tampon ${stamp?.label ?? ''} · choisir un autre tampon',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stamp != null)
            StampPreview(stamp: stamp!, rgb: stampRgb, size: rail ? 44 : 34)
          else
            EduIllustration(art: EduArt.stamp, size: rail ? 44 : 34),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => rail
      ? Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (forStamp) ...[_stampButton(), const SizedBox(height: 8)],
            const Text('Taille', style: TextStyle(fontSize: 11)),
            const SizedBox(height: 4),
            SizeChoiceControl(
              value: size,
              what: what,
              onChanged: onSizeChanged,
              wrap: true,
            ),
          ],
        )
      : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (forStamp) ...[_stampButton(), const SizedBox(width: 10)],
            const Text('Taille', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 8),
            SizeChoiceControl(
              value: size,
              what: what,
              onChanged: onSizeChanged,
            ),
          ],
        );
}
