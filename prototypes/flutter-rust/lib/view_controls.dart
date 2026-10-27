// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

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
        tooltip: 'Éloigner la feuille',
        onPressed: onZoomOut,
        icon: const Icon(
          Icons.remove_circle_outline,
          semanticLabel: 'Éloigner la feuille',
        ),
      ),
      IconButton(
        key: const Key('zoomIn'),
        tooltip: 'Rapprocher la feuille',
        onPressed: onZoomIn,
        icon: const Icon(
          Icons.add_circle_outline,
          semanticLabel: 'Rapprocher la feuille',
        ),
      ),
      IconButton(
        key: const Key('fitPage'),
        tooltip: 'Voir toute la feuille',
        onPressed: onFit,
        icon: const Icon(
          Icons.fit_screen,
          semanticLabel: 'Voir toute la feuille',
        ),
      ),
      IconButton(
        key: const Key('panPage'),
        tooltip: 'Déplacer la feuille · maintenir Espace marche aussi',
        isSelected: panning,
        onPressed: onTogglePan,
        icon: const Icon(
          Icons.pan_tool_outlined,
          semanticLabel: 'Déplacer la feuille',
        ),
        selectedIcon: const Icon(
          Icons.pan_tool,
          semanticLabel: 'Déplacer la feuille',
        ),
      ),
      IconButton(
        key: const Key('bigSheet'),
        tooltip: bigSheet ? 'Retrouver tous les panneaux' : 'Dessiner en grand',
        isSelected: bigSheet,
        onPressed: onToggleBigSheet,
        icon: const Icon(
          Icons.open_in_full,
          semanticLabel: 'Dessiner en grand',
        ),
        selectedIcon: const Icon(
          Icons.close_fullscreen,
          semanticLabel: 'Retrouver tous les panneaux',
        ),
      ),
    ],
  );
}
