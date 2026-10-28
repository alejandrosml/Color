// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'rust_document.dart' show maxTextSize, minTextSize;
import 'studio_colors.dart';

/// Three concrete sizes instead of a number to type or a technical slider.
enum ObjectSize {
  small('Petit'),
  medium('Moyen'),
  large('Grand');

  const ObjectSize(this.label);
  final String label;
}

/// Sizes are chosen for a sheet whose shorter side measures 800 units and
/// follow the sheet: a text on a large photo stays readable.
double _sheetScale(int width, int height) => math.min(width, height) / 800;

/// Height of the letters, in document units, for a sheet of this size.
double textSizeFor(ObjectSize size, {required int width, required int height}) {
  final base = switch (size) {
    ObjectSize.small => 32.0,
    ObjectSize.medium => 56.0,
    ObjectSize.large => 96.0,
  };
  return (base * _sheetScale(width, height))
      .clamp(minTextSize, maxTextSize)
      .toDouble();
}

/// The choice whose letter height is closest to an existing text's size.
ObjectSize nearestTextSize(
  double value, {
  required int width,
  required int height,
}) {
  var best = ObjectSize.medium;
  var distance = double.infinity;
  for (final size in ObjectSize.values) {
    final candidate = (textSizeFor(size, width: width, height: height) - value)
        .abs();
    if (candidate < distance) {
      distance = candidate;
      best = size;
    }
  }
  return best;
}

/// Side of a stamp placed with a single click, in document units.
double stampSizeFor(
  ObjectSize size, {
  required int width,
  required int height,
}) {
  final base = switch (size) {
    ObjectSize.small => 90.0,
    ObjectSize.medium => 150.0,
    ObjectSize.large => 240.0,
  };
  // Never larger than the sheet itself, however small that sheet is.
  return math.min(
    base * _sheetScale(width, height),
    math.min(width, height).toDouble(),
  );
}

/// Three large buttons. The parent names what is being sized.
class SizeChoiceControl extends StatelessWidget {
  const SizeChoiceControl({
    super.key,
    required this.value,
    required this.onChanged,
    required this.what,
    this.keyPrefix = 'size',
    this.wrap = false,
  });

  /// In a narrow column the three buttons go on to a second line.
  final bool wrap;

  final ObjectSize value;
  final ValueChanged<ObjectSize>? onChanged;

  /// Distinguishes two controls shown together, as a dialog over the studio.
  final String keyPrefix;

  /// Completes the spoken label, for example « du texte » or « du tampon ».
  final String what;

  @override
  Widget build(BuildContext context) {
    final buttons = [for (final size in ObjectSize.values) _button(size)];
    return wrap
        ? Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: buttons,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final button in buttons) ...[
                if (button != buttons.first) const SizedBox(width: 6),
                button,
              ],
            ],
          );
  }

  Widget _button(ObjectSize size) => Tooltip(
    message: size.label,
    excludeFromSemantics: true,
    child: OutlinedButton(
      key: Key('$keyPrefix-${size.name}'),
      onPressed: onChanged == null ? null : () => onChanged!(size),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        maximumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        backgroundColor: size == value ? studioSelected : studioSurface,
        side: BorderSide(
          color: size == value ? studioGreen : studioLine,
          width: size == value ? 2 : 1,
        ),
      ),
      // Named and marked as chosen on the button itself: a screen
      // reader then announces, and activates, one single control.
      child: Semantics(
        label: 'Taille $what : ${size.label}',
        selected: size == value,
        // A growing dot reads the same in every language and text size.
        child: Container(
          width: 10.0 + 10 * size.index,
          height: 10.0 + 10 * size.index,
          decoration: BoxDecoration(
            color: size == value ? studioGreen : studioQuietMark,
            shape: BoxShape.circle,
          ),
        ),
      ),
    ),
  );
}
