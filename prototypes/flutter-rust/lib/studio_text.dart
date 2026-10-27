// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

/// The style of a button label of the given size, in the family of the rest
/// of the interface. A label style without a family is drawn in the engine's
/// default font, which the theme does not choose: naming the family keeps
/// the same letters everywhere, and lets a test load them.
TextStyle studioLabelStyle(BuildContext context, double fontSize) {
  final label = Theme.of(context).textTheme.labelLarge;
  return TextStyle(
    fontSize: fontSize,
    fontFamily: label?.fontFamily,
    fontFamilyFallback: label?.fontFamilyFallback,
  );
}
