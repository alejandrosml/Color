// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'language.dart';

/// Routes macOS menu shortcuts to the same document actions as the toolbar.
/// Install once. Null document callbacks disable their corresponding items.
///
/// The menus are handed to the system again only when the commands offered
/// change, not at every build of the studio (F-03 of the retrospective of
/// October 2026: five traits sent the whole menu bar eleven times). An item
/// calls the command of the widget as it is when the item is chosen.
class EduPaintDesktopMenu extends StatefulWidget {
  const EduPaintDesktopMenu({
    super.key,
    required this.child,
    this.onAbout,
    this.onNew,
    this.onOpen,
    this.onImportImage,
    this.onSave,
    this.onSaveAs,
    this.onExportSvg,
    this.onExportPng,
    this.onPrint,
    this.onOptions,
    this.onUniverses,
    this.hasUniverses = false,
    this.onReplay,
    this.onUndo,
    this.onRedo,
    this.onDuplicate,
    this.onDelete,
    this.onBringToFront,
    this.onSendToBack,
    this.onLayers,
    this.onEditText,
    this.onGrow,
    this.onShrink,
    this.onHelp,
    this.onGallery,
    this.hasGallery = false,
    this.beforeCommand,
  });

  final Widget child;

  /// If omitted, use the standard system About panel.
  final VoidCallback? onAbout;
  final VoidCallback? onNew;
  final VoidCallback? onOpen;
  final VoidCallback? onImportImage;
  final VoidCallback? onSave;
  final VoidCallback? onSaveAs;
  final VoidCallback? onExportSvg;
  final VoidCallback? onExportPng;
  final VoidCallback? onPrint;

  /// « Options… », for the adult: behind a calculation if the adult chose one.
  final VoidCallback? onOptions;

  /// « Univers… » (Color 1.2): in the menu only when [hasUniverses] — the
  /// child chooses the universe; null while the studio is busy.
  final VoidCallback? onUniverses;
  final bool hasUniverses;

  /// « Revoir le dessin se faire tout seul ».
  final VoidCallback? onReplay;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onBringToFront;
  final VoidCallback? onSendToBack;
  final VoidCallback? onLayers;
  final VoidCallback? onEditText;
  final VoidCallback? onGrow;
  final VoidCallback? onShrink;
  final VoidCallback? onHelp;

  /// « Mes dessins… » is listed only when [hasGallery]: the album needs a
  /// private folder that may be unavailable.
  final VoidCallback? onGallery;
  final bool hasGallery;

  /// Called before any command of the menu: the studio settles there what a
  /// command must not find half done.
  final VoidCallback? beforeCommand;

  @override
  State<EduPaintDesktopMenu> createState() => _EduPaintDesktopMenuState();
}

class _EduPaintDesktopMenuState extends State<EduPaintDesktopMenu> {
  // The menus last handed to the system, and the commands they offer.
  List<PlatformMenuItem>? _menus;
  List<bool>? _offered;
  AppLanguage? _language;

  // Which commands the widget offers now.
  List<bool> _offeredNow() {
    final menu = widget;
    return [
      menu.onAbout != null,
      menu.onNew != null,
      menu.onOpen != null,
      menu.onImportImage != null,
      menu.onSave != null,
      menu.onSaveAs != null,
      menu.onExportSvg != null,
      menu.onExportPng != null,
      menu.onPrint != null,
      menu.onOptions != null,
      menu.onUniverses != null,
      menu.hasUniverses,
      menu.onReplay != null,
      menu.onUndo != null,
      menu.onRedo != null,
      menu.onDuplicate != null,
      menu.onDelete != null,
      menu.onBringToFront != null,
      menu.onSendToBack != null,
      menu.onLayers != null,
      menu.onEditText != null,
      menu.onGrow != null,
      menu.onShrink != null,
      menu.onHelp != null,
      menu.onGallery != null,
      menu.hasGallery,
    ];
  }

  // The command that [of] picks in the widget, as the widget is when the
  // item is chosen; null, a disabled item, when it offers none now.
  VoidCallback? _command(VoidCallback? Function(EduPaintDesktopMenu menu) of) {
    if (of(widget) == null) return null;
    return () {
      final command = of(widget);
      if (command == null) return;
      widget.beforeCommand?.call();
      command();
    };
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return widget.child;
    }
    final offered = _offeredNow();
    // Made again when what is offered changes, or the language: the menu
    // bar speaks the language just chosen, at once.
    if (_menus == null ||
        !listEquals(offered, _offered) ||
        appLanguage.value != _language) {
      _menus = _items();
      _offered = offered;
      _language = appLanguage.value;
    }
    return PlatformMenuBar(menus: _menus!, child: widget.child);
  }

  List<PlatformMenuItem> _items() {
    final hasGallery = widget.hasGallery;
    return [
      PlatformMenu(
        label: tr('Color'),
        menus: [
          PlatformMenuItemGroup(
            members: [
              if (widget.onAbout != null)
                PlatformMenuItem(
                  label: tr('À propos de Color'),
                  onSelected: _command((menu) => menu.onAbout),
                )
              else if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.about,
              ))
                const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.about,
                ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: tr('Options…'),
                onSelected: _command((menu) => menu.onOptions),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.comma,
                  meta: true,
                ),
              ),
              if (widget.hasUniverses)
                PlatformMenuItem(
                  label: tr('Univers…'),
                  onSelected: _command((menu) => menu.onUniverses),
                ),
            ],
          ),
          if (PlatformProvidedMenuItem.hasMenu(
            PlatformProvidedMenuItemType.quit,
          ))
            // Native termination follows the app's existing exit-request path.
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.quit,
            ),
        ],
      ),
      PlatformMenu(
        label: tr('Fichier'),
        menus: [
          PlatformMenuItem(
            label: tr('Nouveau'),
            onSelected: _command((menu) => menu.onNew),
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyN,
              meta: true,
            ),
          ),
          PlatformMenuItem(
            label: tr('Ouvrir…'),
            onSelected: _command((menu) => menu.onOpen),
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyO,
              meta: true,
            ),
          ),
          if (hasGallery)
            PlatformMenuItem(
              label: tr('Mes dessins…'),
              onSelected: _command((menu) => menu.onGallery),
            ),
          PlatformMenuItem(
            label: tr('Enregistrer'),
            onSelected: _command((menu) => menu.onSave),
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
            ),
          ),
          PlatformMenuItem(
            label: tr('Dessiner sur une image…'),
            onSelected: _command((menu) => menu.onImportImage),
          ),
          PlatformMenuItem(
            label: tr('Enregistrer sous…'),
            onSelected: _command((menu) => menu.onSaveAs),
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
              shift: true,
            ),
          ),
          PlatformMenuItem(
            label: tr('Exporter PNG…'),
            onSelected: _command((menu) => menu.onExportPng),
          ),
          PlatformMenuItem(
            label: tr('Exporter SVG…'),
            onSelected: _command((menu) => menu.onExportSvg),
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyE,
              meta: true,
              shift: true,
            ),
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: tr('Imprimer…'),
                onSelected: _command((menu) => menu.onPrint),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyP,
                  meta: true,
                ),
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: tr('Édition'),
        menus: [
          PlatformMenuItem(
            // « Annuler » undoes here; in English that is « Undo », not the
            // « Cancel » of the dialogs.
            label: inEnglish ? 'Undo' : 'Annuler',
            onSelected: _command((menu) => menu.onUndo),
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
            ),
          ),
          PlatformMenuItem(
            label: tr('Rétablir'),
            onSelected: _command((menu) => menu.onRedo),
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
              shift: true,
            ),
          ),
          PlatformMenuItem(
            label: tr('Copier l’élément choisi'),
            onSelected: _command((menu) => menu.onDuplicate),
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyD,
              meta: true,
            ),
          ),
          PlatformMenuItem(
            label: tr('Placer tout devant'),
            onSelected: _command((menu) => menu.onBringToFront),
          ),
          PlatformMenuItem(
            label: tr('Placer tout derrière'),
            onSelected: _command((menu) => menu.onSendToBack),
          ),
          PlatformMenuItem(
            label: tr('Effacer l’élément choisi'),
            onSelected: _command((menu) => menu.onDelete),
            shortcut: const SingleActivator(LogicalKeyboardKey.backspace),
          ),
          PlatformMenuItem(
            label: tr('Modifier le texte choisi…'),
            onSelected: _command((menu) => menu.onEditText),
          ),
          PlatformMenuItem(
            label: tr('Rendre l’élément choisi plus grand'),
            onSelected: _command((menu) => menu.onGrow),
          ),
          PlatformMenuItem(
            label: tr('Rendre l’élément choisi plus petit'),
            onSelected: _command((menu) => menu.onShrink),
          ),
          PlatformMenuItem(
            label: tr('Calques…'),
            onSelected: _command((menu) => menu.onLayers),
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: tr('Revoir le dessin se faire tout seul'),
                onSelected: _command((menu) => menu.onReplay),
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: tr('Fenêtre'),
        menus: [
          for (final type in const [
            PlatformProvidedMenuItemType.minimizeWindow,
            PlatformProvidedMenuItemType.zoomWindow,
            PlatformProvidedMenuItemType.toggleFullScreen,
            PlatformProvidedMenuItemType.arrangeWindowsInFront,
          ])
            if (PlatformProvidedMenuItem.hasMenu(type))
              PlatformProvidedMenuItem(type: type),
        ],
      ),
      PlatformMenu(
        label: tr('Aide'),
        menus: [
          PlatformMenuItem(
            label: tr('Comment faire ?'),
            onSelected: _command((menu) => menu.onHelp),
          ),
        ],
      ),
    ];
  }
}
