// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'language.dart';

/// Zoom, fit and pan buttons of the sheet. They change the view only, never
/// the drawing. Null callbacks disable the buttons.
class ViewControls extends StatelessWidget {
  const ViewControls({
    super.key,
    required this.panning,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
    required this.onTogglePan,
    required this.bigSheet,
    required this.onToggleBigSheet,
  });

  final bool panning;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback? onFit;
  final VoidCallback? onTogglePan;

  /// The panels are put away to leave the whole window to the sheet.
  final bool bigSheet;
  final VoidCallback? onToggleBigSheet;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: const Key('zoomOut'),
        tooltip: tr('Éloigner la feuille'),
        onPressed: onZoomOut,
        icon: Icon(
          Icons.remove_circle_outline,
          semanticLabel: tr('Éloigner la feuille'),
        ),
      ),
      IconButton(
        key: const Key('zoomIn'),
        tooltip: tr('Rapprocher la feuille'),
        onPressed: onZoomIn,
        icon: Icon(
          Icons.add_circle_outline,
          semanticLabel: tr('Rapprocher la feuille'),
        ),
      ),
      IconButton(
        key: const Key('fitPage'),
        tooltip: tr('Voir toute la feuille'),
        onPressed: onFit,
        icon: Icon(
          Icons.fit_screen,
          semanticLabel: tr('Voir toute la feuille'),
        ),
      ),
      IconButton(
        key: const Key('panPage'),
        tooltip: tr('Déplacer la feuille · maintenir Espace marche aussi'),
        isSelected: panning,
        onPressed: onTogglePan,
        icon: Icon(
          Icons.pan_tool_outlined,
          semanticLabel: tr('Déplacer la feuille'),
        ),
        selectedIcon: Icon(
          Icons.pan_tool,
          semanticLabel: tr('Déplacer la feuille'),
        ),
      ),
      IconButton(
        key: const Key('bigSheet'),
        tooltip: bigSheet
            ? tr('Retrouver tous les panneaux')
            : tr('Dessiner en grand'),
        isSelected: bigSheet,
        onPressed: onToggleBigSheet,
        icon: Icon(Icons.open_in_full, semanticLabel: tr('Dessiner en grand')),
        selectedIcon: Icon(
          Icons.close_fullscreen,
          semanticLabel: tr('Retrouver tous les panneaux'),
        ),
      ),
    ],
  );
}
