// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Routes macOS menu shortcuts to the same document actions as the toolbar.
/// Install once. Null document callbacks disable their corresponding items.
class EduPaintDesktopMenu extends StatelessWidget {
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

  VoidCallback? _command(VoidCallback? command) {
    final before = beforeCommand;
    if (command == null || before == null) return command;
    return () {
      before();
      command();
    };
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return child;
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Color',
          menus: [
            PlatformMenuItemGroup(
              members: [
                if (onAbout != null)
                  PlatformMenuItem(
                    label: 'À propos de Color',
                    onSelected: _command(onAbout),
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
                  label: 'Options…',
                  onSelected: _command(onOptions),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                  ),
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
          label: 'Fichier',
          menus: [
            PlatformMenuItem(
              label: 'Nouveau',
              onSelected: _command(onNew),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
            ),
            PlatformMenuItem(
              label: 'Ouvrir…',
              onSelected: _command(onOpen),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
            ),
            if (hasGallery)
              PlatformMenuItem(
                label: 'Mes dessins…',
                onSelected: _command(onGallery),
              ),
            PlatformMenuItem(
              label: 'Enregistrer',
              onSelected: _command(onSave),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
              ),
            ),
            PlatformMenuItem(
              label: 'Dessiner sur une image…',
              onSelected: _command(onImportImage),
            ),
            PlatformMenuItem(
              label: 'Enregistrer sous…',
              onSelected: _command(onSaveAs),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
                shift: true,
              ),
            ),
            PlatformMenuItem(
              label: 'Exporter PNG…',
              onSelected: _command(onExportPng),
            ),
            PlatformMenuItem(
              label: 'Exporter SVG…',
              onSelected: _command(onExportSvg),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyE,
                meta: true,
                shift: true,
              ),
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Imprimer…',
                  onSelected: _command(onPrint),
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
          label: 'Édition',
          menus: [
            PlatformMenuItem(
              label: 'Annuler',
              onSelected: _command(onUndo),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
              ),
            ),
            PlatformMenuItem(
              label: 'Rétablir',
              onSelected: _command(onRedo),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
            ),
            PlatformMenuItem(
              label: 'Copier l’élément choisi',
              onSelected: _command(onDuplicate),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyD,
                meta: true,
              ),
            ),
            PlatformMenuItem(
              label: 'Placer tout devant',
              onSelected: _command(onBringToFront),
            ),
            PlatformMenuItem(
              label: 'Placer tout derrière',
              onSelected: _command(onSendToBack),
            ),
            PlatformMenuItem(
              label: 'Effacer l’élément choisi',
              onSelected: _command(onDelete),
              shortcut: const SingleActivator(LogicalKeyboardKey.backspace),
            ),
            PlatformMenuItem(
              label: 'Modifier le texte choisi…',
              onSelected: _command(onEditText),
            ),
            PlatformMenuItem(
              label: 'Rendre l’élément choisi plus grand',
              onSelected: _command(onGrow),
            ),
            PlatformMenuItem(
              label: 'Rendre l’élément choisi plus petit',
              onSelected: _command(onShrink),
            ),
            PlatformMenuItem(label: 'Calques…', onSelected: _command(onLayers)),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Revoir le dessin se faire tout seul',
                  onSelected: _command(onReplay),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Fenêtre',
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
          label: 'Aide',
          menus: [
            PlatformMenuItem(
              label: 'Comment faire ?',
              onSelected: _command(onHelp),
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
