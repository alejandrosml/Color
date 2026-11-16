// SPDX-License-Identifier: MIT
// What everything that is not a pebble is made of (Color 1.2, step G3): the
// dialogs, their buttons, their switches and their fields wear the matter
// of the pebbles — the surface of the universe, its round corners, its
// shadow, and the letters of the pebbles, Atkinson Hyperlegible. A dialog
// is a large panel: it looks like what a pebble opens.
//
// In a universe of the night the surface is dark and the ink light: the
// scheme of colours is a dark one, so that nothing the framework draws by
// itself — a field, a switch, a menu — is written dark on dark.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'galets.dart';
import 'studio_colors.dart';

/// The family of the letters of the interface, as pubspec.yaml names it.
const studioFontFamily = 'ColorAtkinson';

/// The shape of a button [height] tall in the look of the moment: that of
/// a button of a pebble — all round in most universes, hardly round in the
/// universe of paper.
OutlinedBorder studioRoundShape([double height = 48, StudioLook? look]) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        math.min(height / 2, (look ?? studioLook.value).galetRadius),
      ),
    );

/// The corners of a dialog, of a card or of a large tile in the look of
/// the moment: those of a panel of the pebbles, never rounder than [most].
BorderRadius studioPanelCorners([double most = 26]) =>
    galetCorners(double.infinity, most: most);

/// A quiet tile inside a dialog — a layer, a choice of the options, a card
/// of the album: a little apart from the surface of the dialog, as a chosen
/// button of a pebble is, but fainter; [chosen], it takes the colour of a
/// choice and a line of the accent.
BoxDecoration studioTile({bool chosen = false, double most = 18}) {
  final look = studioLook.value;
  return BoxDecoration(
    color: chosen
        ? look.selected
        : Color.alphaBlend(look.ink.withValues(alpha: .045), look.surface),
    borderRadius: studioPanelCorners(most),
    border: chosen ? Border.all(color: look.accent, width: 2.5) : null,
  );
}

/// The theme of the application in the look of the moment.
ThemeData studioTheme() {
  final look = studioLook.value;
  final onAccent = look.onAccent;
  final base = ColorScheme.fromSeed(
    seedColor: look.night ? look.selected : look.accent,
    brightness: look.night ? Brightness.dark : Brightness.light,
    surface: look.surface,
  );
  // What the framework reads without being asked: the ink on a surface,
  // the accent of a control, the quiet lines.
  final scheme = base.copyWith(
    primary: look.accent,
    onPrimary: onAccent,
    onSurface: look.ink,
    onSurfaceVariant: look.night ? look.caption : base.onSurfaceVariant,
    outline: look.night ? look.quietMark : base.outline,
    outlineVariant: look.line,
    error: look.warning,
    surfaceTint: Colors.transparent,
    // No tint of the seed in what floats: a dialog, a menu and a card are
    // the surface of the universe itself.
    surfaceContainerLowest: look.surface,
    surfaceContainerLow: look.surface,
    surfaceContainer: look.surface,
    surfaceContainerHigh: look.surface,
    shadow: look.shadow,
    scrim: const Color(0xff000000),
  );
  final letters = (look.night ? ThemeData.dark() : ThemeData.light()).textTheme
      .apply(
        fontFamily: studioFontFamily,
        bodyColor: look.ink,
        displayColor: look.ink,
      );
  TextStyle label(double size) => TextStyle(
    fontFamily: studioFontFamily,
    fontSize: size,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );
  const least = Size(48, 48);
  final round = studioRoundShape(48, look);
  final dialogShape = RoundedRectangleBorder(
    borderRadius: studioPanelCorners(),
    side: look.galetEdge == null
        ? BorderSide.none
        : BorderSide(color: look.galetEdge!, width: 1.5),
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: studioFontFamily,
    // The same generous controls on every platform. Left to itself the
    // framework makes them compact on desktop systems, eight pixels less
    // in each direction: too small for a child's hand, and not what the
    // layout of the studio is measured with.
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    colorScheme: scheme,
    scaffoldBackgroundColor: look.background,
    textTheme: letters.copyWith(
      // The title of a dialog: the bold of the pebbles.
      headlineSmall: letters.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleLarge: letters.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: look.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: look.shadow,
      elevation: look.night ? 18 : 12,
      shape: dialogShape,
      titleTextStyle: letters.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: look.ink,
      ),
      contentTextStyle: letters.bodyMedium?.copyWith(color: look.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: look.accent,
        foregroundColor: onAccent,
        minimumSize: least,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        textStyle: label(15),
        shape: round,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: look.ink,
        minimumSize: least,
        textStyle: label(14.5),
        side: BorderSide(
          color: look.night ? look.quietMark : look.line,
          width: 1.5,
        ),
        shape: round,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: look.accent,
        minimumSize: least,
        textStyle: label(14.5),
        shape: round,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: look.ink),
    ),
    iconTheme: IconThemeData(color: look.ink),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? onAccent : look.quietMark,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? look.accent : look.surface,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? look.accent
            : look.quietMark,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? look.accent
            : look.quietMark,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? look.accent : null,
      ),
      checkColor: WidgetStatePropertyAll(onAccent),
      side: BorderSide(color: look.quietMark, width: 2),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: look.accent,
      inactiveTrackColor: look.line,
      thumbColor: look.accent,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: look.surface,
      selectedColor: look.selected,
      checkmarkColor: look.accent,
      labelStyle: TextStyle(
        fontFamily: studioFontFamily,
        fontSize: 14,
        color: look.ink,
      ),
      side: BorderSide(color: look.night ? look.quietMark : look.line),
      shape: studioRoundShape(40, look),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      border: OutlineInputBorder(
        borderRadius: studioPanelCorners(14),
        borderSide: BorderSide(color: look.quietMark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: studioPanelCorners(14),
        borderSide: BorderSide(color: look.quietMark, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: studioPanelCorners(14),
        borderSide: BorderSide(color: look.accent, width: 2.5),
      ),
    ),
    // The name of a button beside a pointer that stays over it: a small
    // dark pebble (a light one on the dark pebbles of the night).
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: look.ink,
        borderRadius: studioPanelCorners(10),
      ),
      textStyle: TextStyle(
        fontFamily: studioFontFamily,
        fontSize: 13.5,
        color: look.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(look.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: studioPanelCorners(18)),
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: look.accent),
  );
}
