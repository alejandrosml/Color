// SPDX-License-Identifier: MIT
// Color — Alejandro San Martin Lamas — https://github.com/alejandrosml
//
// The menu of a selected text. Left to itself, a text that can be selected
// brings the menu of the system: on an iPhone or an iPad, « Chercher »,
// « Rechercher sur le Web » — Safari, on a search of the selected word —
// and « Partager » ; on Android, « Partager » and what other applications
// add. Color is in the Kids category: nothing in it leads out of it. Its
// menu only holds what stays in Color (étape 7 of Color 1.2).
import 'package:flutter/material.dart';

/// What a menu of Color may offer: nothing here opens another application.
const insideMenuButtons = {
  ContextMenuButtonType.cut,
  ContextMenuButtonType.copy,
  ContextMenuButtonType.paste,
  ContextMenuButtonType.selectAll,
  ContextMenuButtonType.delete,
};

/// The menu of the selection of [state], drawn by Color and never by the
/// system, with only the buttons of [insideMenuButtons]; nothing at all
/// when none of them applies.
Widget insideContextMenu(BuildContext context, EditableTextState state) {
  final items = [
    for (final item in state.contextMenuButtonItems)
      if (insideMenuButtons.contains(item.type)) item,
  ];
  if (items.isEmpty) return const SizedBox.shrink();
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: items,
  );
}
