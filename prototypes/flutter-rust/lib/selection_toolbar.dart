// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'child_art.dart';
import 'rust_document.dart' show VectorKind;
import 'studio_colors.dart';
import 'platform_words.dart';

/// Where the chosen element goes among the others.
enum SelectionOrder { front, back, layerUp, layerDown }

/// Actions on the element chosen with « Choisir », with a short hint. Null
/// callbacks disable their buttons; the studio decides what is possible.
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({
    super.key,
    required this.compact,
    required this.selectedKind,
    this.keepsOwnColours = false,
    this.clickMoves = false,
    this.carried = false,
    required this.hasSeveralLayers,
    required this.canBringForward,
    required this.canSendBackward,
    required this.canMoveLayerUp,
    required this.canMoveLayerDown,
    required this.onOrder,
    required this.onShrink,
    required this.onGrow,
    required this.onEditText,
    required this.onDuplicate,
    required this.onDelete,
  });

  final bool compact;

  /// Kind of the chosen element; null when nothing is chosen.
  final VectorKind? selectedKind;

  /// The chosen element is a stamp painted in its own colours only: no
  /// colour can be applied to it.
  final bool keepsOwnColours;

  /// « Dessiner sans tenir le bouton » : the chosen element is taken with a
  /// click and posed with another, and [carried] while it follows the
  /// pointer. The hint says so, in place of « Glisse pour déplacer ».
  final bool clickMoves;
  final bool carried;

  final bool hasSeveralLayers;
  final bool canBringForward;
  final bool canSendBackward;
  final bool canMoveLayerUp;
  final bool canMoveLayerDown;
  final ValueChanged<SelectionOrder> onOrder;

  /// Make the chosen element smaller or larger, one notch at a time.
  final VoidCallback? onShrink;
  final VoidCallback? onGrow;
  final VoidCallback? onEditText;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  bool get _canChangeOrder =>
      canBringForward || canSendBackward || canMoveLayerUp || canMoveLayerDown;

  static final _actionStyle = OutlinedButton.styleFrom(
    minimumSize: const Size(48, 48),
    visualDensity: VisualDensity.standard,
    padding: const EdgeInsets.symmetric(horizontal: 6),
  );

  // One action on the chosen element. Its name is written when the names
  // of all fit on one line; otherwise its picture stands alone, and the
  // name stays the one a screen reader says and a pointer is shown.
  static Widget _action({
    required String key,
    required String name,
    required IconData icon,
    required VoidCallback? onPressed,
    required bool named,
  }) => named
      ? OutlinedButton.icon(
          key: Key(key),
          onPressed: onPressed,
          style: _actionStyle,
          icon: Icon(icon, size: 18),
          label: Text(name, style: const TextStyle(fontSize: 12)),
        )
      : Tooltip(
          message: name,
          excludeFromSemantics: true,
          child: OutlinedButton(
            key: Key(key),
            onPressed: onPressed,
            style: _actionStyle,
            child: Icon(icon, size: 20, semanticLabel: name),
          ),
        );

  // The width of a name as a button writes it.
  static double _nameWidth(BuildContext context, String name) {
    final painter = TextPainter(
      text: TextSpan(
        text: name,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// The width of the line of actions with every name written: paddings,
  /// pictures and gaps as the buttons below lay them out, and a small margin.
  double _namedWidth(BuildContext context) {
    double name(String text) => _nameWidth(context, text);
    final written = [
      56 + name('Ordre'),
      if (selectedKind == VectorKind.text) 38 + name('Modifier'),
      38 + name('Copier'),
      38 + name('Effacer'),
      100.0,
    ];
    return written.fold(0.0, (sum, width) => sum + width) +
        8 * (written.length - 1) +
        8;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
      // Under this width the sentence stands above the actions.
      final stacked = constraints.maxWidth < 540 * textScale;
      // The sentence keeps room for its picture and a few words.
      final hintWidth = (compact ? 32 : 56) + 12 + 132 * textScale;
      final actionsRoom = stacked
          ? constraints.maxWidth
          : math.max(48.0, constraints.maxWidth - hintWidth - 6);
      final named = _namedWidth(context) <= actionsRoom;
      final hint = Row(
        children: [
          // Above the actions of a small window, the words alone: the
          // picture would take from the sheet the height of a line.
          if (!(stacked && compact)) ...[
            EduIllustration(art: EduArt.mascot, size: compact ? 32 : 56),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              forTouch(
                selectedKind == null
                    ? 'Clique un élément pour le choisir.'
                    : carried
                    ? 'Bouge pour le déplacer. Clique pour le poser.'
                    : '${clickMoves ? 'Clique-le pour le prendre.' : 'Glisse pour déplacer.'} '
                          '${selectedKind == VectorKind.text
                              ? 'Modifier change les mots.'
                              : keepsOwnColours
                              ? 'Ce tampon garde ses couleurs.'
                              : selectedKind == VectorKind.stamp
                              ? 'Clique une couleur pour le colorier.'
                              : 'Une couleur cliquée le change aussitôt.'}',
              ),
              // Two lines at most: a longer sentence must not make the
              // row taller, and the sheet smaller, when an element is chosen.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: studioGreen),
            ),
          ),
        ],
      );
      final actions = <Widget>[
        Semantics(
          // Keep the disabled control separate; the popup supplies its label,
          // expansion state and activation without duplicate semantics actions.
          container: true,
          button: true,
          enabled: _canChangeOrder,
          child: PopupMenuButton<SelectionOrder>(
            key: const Key('selectionOrder'),
            tooltip: 'Ordre des éléments',
            enabled: _canChangeOrder,
            // Native menu commands can edit the document while this popup is
            // open: the studio resolves the intent against its current state.
            onSelected: onOrder,
            itemBuilder: (context) => [
              PopupMenuItem<SelectionOrder>(
                key: const Key('bringSelectionToFront'),
                value: SelectionOrder.front,
                enabled: canBringForward,
                child: const Text('Tout devant'),
              ),
              PopupMenuItem<SelectionOrder>(
                key: const Key('sendSelectionToBack'),
                value: SelectionOrder.back,
                enabled: canSendBackward,
                child: const Text('Tout derrière'),
              ),
              // Offered only when the drawing has several layers.
              if (hasSeveralLayers) ...[
                PopupMenuItem<SelectionOrder>(
                  key: const Key('moveSelectionLayerUp'),
                  value: SelectionOrder.layerUp,
                  enabled: canMoveLayerUp,
                  child: const Text('Vers le calque du dessus'),
                ),
                PopupMenuItem<SelectionOrder>(
                  key: const Key('moveSelectionLayerDown'),
                  value: SelectionOrder.layerDown,
                  enabled: canMoveLayerDown,
                  child: const Text('Vers le calque du dessous'),
                ),
              ],
            ],
            child: Container(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.layers_outlined,
                    size: 18,
                    // Without its written name, the picture carries it.
                    semanticLabel: named ? null : 'Ordre',
                    color: _canChangeOrder
                        ? studioInk
                        : Theme.of(context).disabledColor,
                  ),
                  if (named) ...[
                    const SizedBox(width: 4),
                    Text(
                      'Ordre',
                      style: TextStyle(
                        fontSize: 12,
                        color: _canChangeOrder
                            ? studioInk
                            : Theme.of(context).disabledColor,
                      ),
                    ),
                  ],
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
        ),
        if (selectedKind == VectorKind.text)
          _action(
            key: 'editSelectionText',
            name: 'Modifier',
            icon: Icons.edit_outlined,
            onPressed: onEditText,
            named: named,
          ),
        _action(
          key: 'duplicateSelection',
          name: 'Copier',
          icon: Icons.copy_rounded,
          onPressed: onDuplicate,
          named: named,
        ),
        _action(
          key: 'deleteSelection',
          name: 'Effacer',
          icon: Icons.delete_outline_rounded,
          onPressed: onDelete,
          named: named,
        ),
        // Two concrete notches instead of handles to catch or a number to type.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.outlined(
              key: const Key('shrinkSelection'),
              tooltip: 'Plus petit',
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onShrink,
              icon: const Icon(
                Icons.remove,
                size: 20,
                semanticLabel: 'Rendre l’élément plus petit',
              ),
            ),
            const SizedBox(width: 4),
            IconButton.outlined(
              key: const Key('growSelection'),
              tooltip: 'Plus grand',
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onGrow,
              icon: const Icon(
                Icons.add,
                size: 20,
                semanticLabel: 'Rendre l’élément plus grand',
              ),
            ),
          ],
        ),
      ];
      final buttons = Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: actions,
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [hint, const SizedBox(height: 4), buttons],
        );
      }
      // The actions take what the sentence leaves, and stand on two lines
      // when even their pictures need more: they never push each other out
      // of the window.
      return Row(
        children: [
          Expanded(child: hint),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: actionsRoom),
            child: buttons,
          ),
        ],
      );
    },
  );
}
