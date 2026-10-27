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
  });

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
  Widget build(BuildContext context) => Row(
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
  });

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

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (forStamp) ...[
        OutlinedButton(
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
                  StampPreview(stamp: stamp!, rgb: stampRgb, size: 34)
                else
                  const EduIllustration(art: EduArt.stamp, size: 34),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
      ],
      const Text('Taille', style: TextStyle(fontSize: 11)),
      const SizedBox(width: 8),
      SizeChoiceControl(value: size, what: what, onChanged: onSizeChanged),
    ],
  );
}
