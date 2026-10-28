// SPDX-License-Identifier: MIT
// The menu of a telephone: what the top bar of a computer holds, and what
// waits above its sheet — the film of the drawing, the layers, the whole
// sheet — in large buttons over the sheet, closed as soon as one is chosen.
import 'package:flutter/material.dart';

import 'child_art.dart';
import 'studio_colors.dart';

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

  /// « Enregistrer » stands out, as in the top bar.
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
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        entry.picture(28),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            entry.name,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(buttonSize),
      maximumSize: const WidgetStatePropertyAll(buttonSize),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    return entry.filled
        ? FilledButton(
            key: Key(entry.id),
            onPressed: onPressed,
            style: style.copyWith(
              backgroundColor: const WidgetStatePropertyAll(Color(0xffffd575)),
              foregroundColor: const WidgetStatePropertyAll(studioInk),
            ),
            child: content,
          )
        : OutlinedButton(
            key: Key(entry.id),
            onPressed: onPressed,
            style: style,
            child: content,
          );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('phoneMenuDialog'),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    backgroundColor: studioSurface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const EduIllustration(art: EduArt.brush, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
                IconButton(
                  key: const Key('closePhoneMenu'),
                  tooltip: 'Fermer le menu',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    semanticLabel: 'Fermer le menu',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final entry in entries) _button(context, entry)],
            ),
          ],
        ),
      ),
    ),
  );
}
