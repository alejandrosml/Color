// SPDX-License-Identifier: MIT
// The menu of a telephone and of a small window: « Mon dessin » between two
// rails. What the panel of the same name holds above a line, and what waits
// in the pebble of the right there — the film of the drawing, the layers,
// the whole sheet —, in large buttons over the sheet, closed as soon as one
// is chosen. It is made of the matter of the pebbles (Color 1.2, step G3):
// their surface, their letters, their buttons.
import 'package:flutter/material.dart';

import 'galets.dart';
import 'studio_colors.dart';
import 'language.dart';

/// One button of the menu. [id] is the key of the button and what the menu
/// answers when it is chosen.
class PhoneMenuEntry {
  const PhoneMenuEntry({
    required this.id,
    required this.name,
    required this.picture,
    required this.enabled,
    this.filled = false,
  });

  final String id;
  final String name;
  final Widget Function(double size) picture;
  final bool enabled;

  /// « Enregistrer » stands out, as in the pebbles.
  final bool filled;
}

/// Shows the menu over the studio; the answer is the [PhoneMenuEntry.id] of
/// the chosen button, or null when the menu is closed without a choice.
Future<String?> showPhoneMenu(
  BuildContext context, {
  required String title,
  required String caption,
  required List<PhoneMenuEntry> entries,
}) => showDialog<String>(
  context: context,
  builder: (context) =>
      PhoneMenu(title: title, caption: caption, entries: entries),
);

class PhoneMenu extends StatelessWidget {
  const PhoneMenu({
    super.key,
    required this.title,
    required this.caption,
    required this.entries,
  });

  /// The name of the drawing, and what it holds.
  final String title;
  final String caption;
  final List<PhoneMenuEntry> entries;

  static const buttonSize = Size(96, 68);

  Widget _button(BuildContext context, PhoneMenuEntry entry) {
    final onPressed = entry.enabled
        ? () => Navigator.of(context).pop(entry.id)
        : null;
    return GaletButton(
      key: Key(entry.id),
      label: entry.name,
      onPressed: onPressed,
      fill: entry.filled ? studioSaveFill : null,
      width: buttonSize.width,
      height: buttonSize.height,
      corners: 18,
      tip: false,
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          entry.picture(30),
          const SizedBox(height: 5),
          // With enlarged letters the name takes the height that is left,
          // and no more: it is never cut.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                entry.name,
                maxLines: 1,
                softWrap: false,
                style: galetText(
                  13.5,
                  color: entry.filled ? studioSaveInk : studioInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('phoneMenuDialog'),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 4),
                const GaletPortrait(size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: galetText(17, bold: true),
                      ),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: galetText(13, color: studioCaption),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('closePhoneMenu'),
                  tooltip: tr('Fermer le menu'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, semanticLabel: tr('Fermer le menu')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [for (final entry in entries) _button(context, entry)],
            ),
          ],
        ),
      ),
    ),
  );
}
