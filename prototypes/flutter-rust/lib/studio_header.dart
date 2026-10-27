// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'child_art.dart';
import 'studio_colors.dart';
import 'studio_text.dart';

// How generous the actions are: the room on each side of their words, the
// gap between two of them, the size of their pictures and of their letters.
typedef _Form = ({double padding, double gap, double picture, double text});

// One action of the header: a button of the line, or an entry of the « … »
// menu of a narrow window.
class _Action {
  const _Action({
    required this.id,
    required this.name,
    required this.menuName,
    required this.picture,
    required this.onPressed,
    this.filled = false,
  });

  /// The key of its button and of its menu entry.
  final String id;
  final String name;

  /// What the menu calls it.
  final String menuName;
  final Widget Function(double size) picture;
  final VoidCallback? onPressed;

  /// « Enregistrer » stands out: the one action never to forget.
  final bool filled;
}

/// The top bar: the name of the app and the actions on the whole drawing.
/// Null callbacks disable their buttons while the studio is busy. What the
/// options take away is not shown at all.
class StudioHeader extends StatelessWidget {
  const StudioHeader({
    super.key,
    required this.onNew,
    required this.onOpen,
    required this.onGallery,
    required this.hasGallery,
    required this.onImportImage,
    required this.onSave,
    required this.onExport,
    required this.onPrint,
    required this.onAbout,
    required this.onHelp,
    required this.onMenuVisibilityChanged,
    this.onOptions,
    this.showOpen = true,
    this.showImportImage = true,
    this.showExport = true,
    this.showPrint = true,
    this.showHelp = true,
    this.savedJustNow = false,
  });

  final VoidCallback? onNew;
  final VoidCallback? onOpen;

  /// « Mes dessins ». The button exists only when [hasGallery]: the album
  /// needs a private folder that may be unavailable.
  final VoidCallback? onGallery;
  final bool hasGallery;
  final VoidCallback? onImportImage;
  final VoidCallback? onSave;
  final VoidCallback? onExport;

  /// « Imprimer » opens the printing panel of the system.
  final VoidCallback? onPrint;
  final VoidCallback? onAbout;
  final VoidCallback? onHelp;

  /// The small-window menu is a popup: the studio guards it like a dialog.
  final ValueChanged<bool> onMenuVisibilityChanged;

  /// « Options », for the adult: the toothed wheel beside the name.
  final VoidCallback? onOptions;

  /// What the options leave in the header. « Nouveau », « Enregistrer » and
  /// « Options » are always there.
  final bool showOpen;
  final bool showImportImage;
  final bool showExport;
  final bool showPrint;

  /// The « ? » and the « i » beside the name.
  final bool showHelp;

  /// The drawing has just been saved: for a moment « Enregistrer » shows a
  /// tick in place of its picture. It is the only sign of it that every
  /// interface shows, with or without sounds.
  final bool savedJustNow;

  static const _Form _roomy = (padding: 20, gap: 10, picture: 30, text: 14);
  static const _Form _regular = (padding: 12, gap: 8, picture: 30, text: 14);
  static const _Form _tight = (padding: 8, gap: 6, picture: 26, text: 14);
  // Beside the name only: every action still written, a little smaller,
  // rather than a second line taken from the sheet.
  static const _Form _snug = (padding: 6, gap: 6, picture: 24, text: 13);
  // The line without the name, in a window too narrow for the others.
  static const _Form _small = (padding: 6, gap: 10, picture: 24, text: 12);

  static const _nameStyle = TextStyle(
    fontSize: 27,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
  );

  static double _textWidth(
    BuildContext context,
    String text,
    TextStyle? style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// The width of one action as the buttons below lay it out: paddings,
  /// picture, the gap before the word, the word.
  static double _actionWidth(BuildContext context, String name, _Form form) =>
      2 * form.padding +
      form.picture +
      8 +
      _textWidth(context, name, studioLabelStyle(context, form.text));

  /// The width of a line of actions at one generosity.
  static double _lineWidth(
    BuildContext context,
    Iterable<_Action> actions,
    _Form form,
  ) {
    var width = 0.0;
    var count = 0;
    for (final action in actions) {
      width += _actionWidth(context, action.name, form);
      count++;
    }
    return width + form.gap * (count > 0 ? count - 1 : 0);
  }

  // Every action that the options leave, in the order of the line.
  List<_Action> get _actions => [
    _Action(
      id: 'newProject',
      name: 'Nouveau',
      menuName: 'Nouveau',
      picture: (size) => EduIllustration(art: EduArt.newPage, size: size),
      onPressed: onNew,
    ),
    if (showOpen)
      _Action(
        id: 'openProject',
        name: 'Ouvrir',
        menuName: 'Ouvrir…',
        picture: (size) => EduIllustration(art: EduArt.folder, size: size),
        onPressed: onOpen,
      ),
    if (hasGallery)
      _Action(
        id: 'openGallery',
        name: 'Mes dessins',
        menuName: 'Mes dessins',
        picture: (size) => EduIllustration(art: EduArt.gallery, size: size),
        onPressed: onGallery,
      ),
    if (showImportImage)
      _Action(
        id: 'importImage',
        name: 'Sur une image',
        menuName: 'Dessiner sur une image…',
        picture: (size) => Icon(Icons.add_photo_alternate_outlined, size: size),
        onPressed: onImportImage,
      ),
    _Action(
      id: 'saveProject',
      name: 'Enregistrer',
      menuName: 'Enregistrer',
      picture: (size) => EduIllustration(art: EduArt.save, size: size),
      onPressed: onSave,
      filled: true,
    ),
    if (showExport)
      _Action(
        id: 'exportImage',
        name: 'Exporter',
        menuName: 'Exporter…',
        picture: (size) => EduIllustration(art: EduArt.exportImage, size: size),
        onPressed: onExport,
      ),
    if (showPrint)
      _Action(
        id: 'printDrawing',
        name: 'Imprimer',
        menuName: 'Imprimer…',
        picture: (size) => EduIllustration(art: EduArt.printer, size: size),
        onPressed: onPrint,
      ),
  ];

  // In the small form these join the line while it has room, in this order,
  // and wait in the « … » menu otherwise; the others are always on the line.
  static const _joiners = ['printDrawing', 'openGallery', 'importImage'];

  // What the menu holds, said in its name.
  static const _heldNames = {
    'openGallery': 'galerie',
    'importImage': 'image',
    'printDrawing': 'impression',
  };

  // The values of the entries of the menu: older than the options, and
  // known to whoever drives the menu.
  static const _menuValues = {
    'openGallery': 'gallery',
    'importImage': 'image',
    'printDrawing': 'print',
  };

  Widget _button(_Action action, _Form form, TextStyle? text) {
    final padding = EdgeInsets.symmetric(horizontal: form.padding);
    // The tick takes the place and the size of the picture: nothing moves.
    final picture = savedJustNow && action.id == 'saveProject'
        ? Semantics(
            liveRegion: true,
            label: 'Dessin enregistré',
            child: Icon(
              Icons.check_circle,
              key: const Key('savedTick'),
              size: form.picture,
              color: studioGreen,
            ),
          )
        : action.picture(form.picture);
    return action.filled
        ? FilledButton.icon(
            key: Key(action.id),
            onPressed: action.onPressed,
            style: FilledButton.styleFrom(
              padding: padding,
              textStyle: text,
              backgroundColor: const Color(0xffffd575),
              foregroundColor: studioInk,
            ),
            icon: picture,
            label: Text(action.name),
          )
        : OutlinedButton.icon(
            key: Key(action.id),
            style: OutlinedButton.styleFrom(padding: padding, textStyle: text),
            onPressed: action.onPressed,
            icon: picture,
            label: Text(action.name),
          );
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: const BoxDecoration(
      color: studioSurface,
      border: Border(bottom: BorderSide(color: studioLine)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final all = _actions;
        // A few pixels are kept in hand everywhere below, since letters
        // differ between systems.
        bool fits(_Form form) =>
            _lineWidth(context, all, form) + 12 <= constraints.maxWidth;
        // The name of the app stands above one line of every action, or
        // beside it. A window too narrow for that line gets the small form:
        // one line without the name, and a « … » menu.
        final small = constraints.maxWidth < 750 || !fits(_tight);
        // The name of the app with its round buttons, as built below, in
        // the letters that the name is really written with.
        final titleWidth =
            36 +
            10 +
            _textWidth(
              context,
              'Color',
              DefaultTextStyle.of(context).style.merge(_nameStyle),
            ) +
            12 +
            (showHelp ? 96 : 0) +
            48;
        // One line of actions less is that much more room for the sheet:
        // the actions are as generous as one line beside the name allows,
        // down to a snug form, and only then take a line of their own.
        bool fitsBesideName(_Form form) =>
            titleWidth + 16 + _lineWidth(context, all, form) + 12 <=
            constraints.maxWidth;
        final form = small
            ? _small
            : constraints.maxWidth >= 1200 && fitsBesideName(_roomy)
            ? _roomy
            : fitsBesideName(_regular)
            ? _regular
            : fitsBesideName(_tight)
            ? _tight
            : fitsBesideName(_snug)
            ? _snug
            : fits(_regular)
            ? _regular
            : _tight;
        final actionText = studioLabelStyle(context, form.text);
        // In the small form the actions of every day are always there. The
        // others join them, in their order, while the line has room beside
        // the « … » menu, where they wait otherwise.
        final shown = <_Action>[];
        final held = <_Action>[];
        if (small) {
          for (final action in all) {
            if (!_joiners.contains(action.id)) shown.add(action);
          }
          var line = _lineWidth(context, shown, form) + 6 + 48 + 12;
          var joining = true;
          for (final id in _joiners) {
            for (final action in all.where((action) => action.id == id)) {
              final longer =
                  line + form.gap + _actionWidth(context, action.name, form);
              joining = joining && longer <= constraints.maxWidth;
              if (joining) {
                line = longer;
                shown.add(action);
              } else {
                held.add(action);
              }
            }
          }
          // The line keeps the order of the wide header.
          shown.sort((a, b) => all.indexOf(a).compareTo(all.indexOf(b)));
        } else {
          shown.addAll(all);
        }
        final actions = Wrap(
          spacing: form.gap,
          runSpacing: 8,
          children: [
            for (final action in shown) _button(action, form, actionText),
          ],
        );
        if (small) {
          final names = [
            for (final id in _heldNames.keys)
              if (held.any((action) => action.id == id)) _heldNames[id]!,
            if (showHelp) 'aide',
            'options',
            if (showHelp) 'informations',
          ];
          final listed = names.length == 1
              ? names.single
              : '${names.sublist(0, names.length - 1).join(', ')} et ${names.last}';
          final menuName = '${listed[0].toUpperCase()}${listed.substring(1)}';
          return Row(
            children: [
              Expanded(child: actions),
              const SizedBox(width: 6),
              _MenuWatch(
                onVisibilityChanged: onMenuVisibilityChanged,
                builder: (opened, closed) => PopupMenuButton<String>(
                  key: const Key('moreFileActions'),
                  // Open as long as one of its entries can answer.
                  enabled: [
                    for (final action in held) action.onPressed,
                    if (showHelp) onHelp,
                    if (showHelp) onAbout,
                    onOptions,
                  ].any((action) => action != null),
                  tooltip: menuName,
                  icon: Icon(Icons.more_horiz, semanticLabel: menuName),
                  onOpened: opened,
                  onCanceled: closed,
                  onSelected: (value) {
                    closed();
                    switch (value) {
                      case 'help':
                        onHelp?.call();
                      case 'about':
                        onAbout?.call();
                      case 'options':
                        onOptions?.call();
                      default:
                        for (final action in held) {
                          if (_menuValues[action.id] == value) {
                            action.onPressed?.call();
                          }
                        }
                    }
                  },
                  itemBuilder: (_) => [
                    // In the order the wide header shows them.
                    for (final action in all)
                      if (held.contains(action))
                        PopupMenuItem(
                          key: Key(action.id),
                          value: _menuValues[action.id],
                          enabled: action.onPressed != null,
                          child: Text(action.menuName),
                        ),
                    if (showHelp)
                      const PopupMenuItem(
                        key: Key('showHelp'),
                        value: 'help',
                        child: Text('Comment faire ?'),
                      ),
                    if (showHelp)
                      const PopupMenuItem(
                        value: 'about',
                        child: Text('À propos de Color'),
                      ),
                    PopupMenuItem(
                      key: const Key('openOptions'),
                      value: 'options',
                      enabled: onOptions != null,
                      child: const Text('Options…'),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        // The name is never squeezed: it keeps its own width, and the
        // actions go below it when both do not fit on one line.
        final title = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EduIllustration(art: EduArt.brush, size: 36),
            const SizedBox(width: 10),
            Text(
              'Color',
              maxLines: 1,
              style: _nameStyle.copyWith(color: studioTitle),
            ),
            const SizedBox(width: 12),
            if (showHelp) ...[
              IconButton(
                key: const Key('showHelp'),
                tooltip: 'Comment faire ?',
                onPressed: onHelp,
                icon: const Icon(
                  Icons.help_outline,
                  semanticLabel: 'Comment faire ?',
                ),
              ),
              IconButton(
                onPressed: onAbout,
                icon: const Icon(
                  Icons.info_outline,
                  semanticLabel: 'À propos de Color',
                ),
              ),
            ],
            IconButton(
              key: const Key('openOptions'),
              tooltip: 'Options, pour les adultes',
              onPressed: onOptions,
              icon: Semantics(
                label: 'Options, pour les adultes',
                child: const EduIllustration(art: EduArt.options, size: 28),
              ),
            ),
          ],
        );
        // One line when the name and every action fit, the name on the left
        // and the actions on the right; otherwise the actions take the lines
        // below. The layout decides from the real widths: letters differ
        // between systems, and the text can be enlarged.
        return SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 6,
            children: [title, actions],
          ),
        );
      },
    ),
  );
}

/// Tells the studio that the « … » menu is open or closed — also when the
/// button leaves the header while its menu is open, as it does when the
/// window is made wider: the menu then closes without telling its button,
/// which is no longer there, and the studio would wait for it for ever.
class _MenuWatch extends StatefulWidget {
  const _MenuWatch({required this.onVisibilityChanged, required this.builder});
  final ValueChanged<bool> onVisibilityChanged;
  final Widget Function(VoidCallback opened, VoidCallback closed) builder;

  @override
  State<_MenuWatch> createState() => _MenuWatchState();
}

class _MenuWatchState extends State<_MenuWatch> {
  bool _open = false;

  void _opened() {
    _open = true;
    widget.onVisibilityChanged(true);
  }

  void _closed() {
    if (!_open) return;
    _open = false;
    widget.onVisibilityChanged(false);
  }

  @override
  void dispose() {
    if (_open) {
      // After the frame that takes the button away, never inside it.
      final tell = widget.onVisibilityChanged;
      WidgetsBinding.instance.addPostFrameCallback((_) => tell(false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_opened, _closed);
}
