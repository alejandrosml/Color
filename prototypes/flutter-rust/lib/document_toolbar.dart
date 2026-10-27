// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'child_art.dart';
import 'studio_colors.dart';

/// The line above the sheet: the name of the drawing and what it holds, then
/// the view, the filling of shapes, the film of the drawing, the layers and
/// the two history buttons. Null callbacks disable their controls; the studio
/// decides what is possible, and the options what is shown at all.
class DocumentToolbar extends StatelessWidget {
  const DocumentToolbar({
    super.key,
    required this.title,
    required this.caption,
    required this.viewControls,
    required this.showFill,
    required this.filled,
    required this.onFilledChanged,
    required this.activeLayerName,
    required this.onLayers,
    required this.onUndo,
    required this.onRedo,
    this.onReplay,
    this.showReplay = false,
    this.showTitle = true,
    this.showLayers = true,
  });

  /// The file name of the drawing, or its default name.
  final String title;

  /// How many elements, and whether they are saved.
  final String caption;

  /// Zoom, hand and « dessiner en grand », built by the studio; null when
  /// the options leave the view alone.
  final Widget? viewControls;

  /// « Remplir » is shown for the tools and elements that have an inside.
  final bool showFill;
  final bool filled;
  final ValueChanged<bool>? onFilledChanged;

  /// Said by the layers button: the layer that receives what is drawn.
  final String activeLayerName;
  final VoidCallback? onLayers;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  /// « Le dessin qui se refait tout seul ».
  final VoidCallback? onReplay;
  final bool showReplay;

  /// The name of the drawing and its caption.
  final bool showTitle;
  final bool showLayers;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // The written name of the checkbox leaves first when room is short;
      // its spoken name and its tooltip stay.
      final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final nameFill = constraints.maxWidth >= 600 * textScale;
      final fillCheckbox = Checkbox(
        key: const Key('fillShapeCheckbox'),
        value: filled,
        onChanged: onFilledChanged == null
            ? null
            : (value) => onFilledChanged!(value ?? false),
      );
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (viewControls != null) ...[
            viewControls!,
            const SizedBox(width: 6),
          ],
          if (showFill)
            Semantics(
              label: 'Remplir la forme',
              child: nameFill
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        fillCheckbox,
                        const Text('Remplir', style: TextStyle(fontSize: 12)),
                      ],
                    )
                  : Tooltip(
                      message: 'Remplir',
                      excludeFromSemantics: true,
                      child: fillCheckbox,
                    ),
            ),
          if (showReplay) ...[
            const SizedBox(width: 10),
            IconButton.outlined(
              key: const Key('replayDrawing'),
              tooltip: 'Revoir ton dessin se faire tout seul',
              onPressed: onReplay,
              icon: Semantics(
                label: 'Revoir ton dessin se faire tout seul',
                child: const EduIllustration(art: EduArt.film, size: 28),
              ),
            ),
          ],
          if (showLayers) ...[
            const SizedBox(width: 10),
            IconButton.outlined(
              key: const Key('layersButton'),
              tooltip: 'Calques',
              onPressed: onLayers,
              icon: Semantics(
                label: 'Calques : tu dessines sur $activeLayerName',
                child: const EduIllustration(art: EduArt.layers, size: 28),
              ),
            ),
          ],
          const SizedBox(width: 10),
          IconButton.outlined(
            key: const Key('undo'),
            onPressed: onUndo,
            icon: Semantics(
              label: 'Annuler le dernier geste',
              child: const EduIllustration(art: EduArt.undo, size: 28),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.outlined(
            key: const Key('redo'),
            onPressed: onRedo,
            icon: Semantics(
              label: 'Rétablir le geste annulé',
              child: const EduIllustration(art: EduArt.redo, size: 28),
            ),
          ),
        ],
      );
      return Row(
        children: [
          Expanded(
            child: !showTitle
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: studioDocumentCaption,
                        ),
                      ),
                    ],
                  ),
          ),
          // Whatever the window, the controls never push each other out: in
          // a very narrow one this strip scrolls, Annuler staying in view.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: SingleChildScrollView(
              key: const Key('documentControlsScroll'),
              scrollDirection: Axis.horizontal,
              reverse: true,
              primary: false,
              child: controls,
            ),
          ),
        ],
      );
    },
  );
}
