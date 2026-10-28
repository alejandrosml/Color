// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'child_art.dart';
import 'fit_to_screen.dart';
import 'studio_colors.dart';
import 'studio_options.dart';
import 'studio_tool.dart';
import 'platform_words.dart';

/// « Comment faire ? » : every tool with its picture and the same sentence as
/// beside the sheet, then the keys that do the same things. Nothing here
/// changes the drawing. Only what the options offer is explained.
Future<void> showHelpDialog(
  BuildContext context, {
  bool hasGallery = false,
  StudioOptions options = StudioOptions.defaults,
}) => showDialog<void>(
  context: context,
  builder: (_) => FitDialog(
    child: HelpDialog(hasGallery: hasGallery, options: options),
  ),
);

class HelpDialog extends StatelessWidget {
  const HelpDialog({
    super.key,
    this.hasGallery = false,
    this.options = StudioOptions.defaults,
  });

  /// « Mes dessins » is explained only where the album exists.
  final bool hasGallery;

  /// What the adult chose: the tools and the actions that are shown.
  final StudioOptions options;

  /// The key that accompanies letters in shortcuts on this computer.
  static String get commandKey =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl';

  @override
  Widget build(BuildContext context) {
    final command = commandKey;
    return AlertDialog(
      key: const Key('helpDialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      title: const Text('Comment faire ?'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final tool in options.tools)
              _HelpRow(
                key: Key('help-${tool.name}'),
                picture: EduIllustration(art: tool.art, size: 40),
                title: tool.label,
                text: tool.help,
              ),
            if (!options.simpleControls)
              const _HelpRow(
                key: Key('help-picker'),
                picture: Icon(Icons.colorize, size: 30),
                title: 'Pipette',
                text: 'À côté des couleurs. Appuie dessus, puis clique sur une couleur de ton dessin pour la reprendre.',
              ),
            if (options.layers)
              const _HelpRow(
                key: Key('help-layers'),
                picture: EduIllustration(art: EduArt.layers, size: 40),
                title: 'Calques',
                text: 'Des feuilles transparentes posées l’une sur l’autre. Tu peux en cacher une, ou la passer devant.',
              ),
            if (options.viewControls)
              const _HelpRow(
                key: Key('help-big-sheet'),
                picture: Icon(Icons.open_in_full, size: 28),
                title: 'Dessiner en grand',
                text: 'Range les panneaux pour laisser toute la place à ta feuille. Le même bouton les fait revenir.',
              ),
            if (hasGallery)
              const _HelpRow(
                key: Key('help-gallery'),
                picture: EduIllustration(art: EduArt.gallery, size: 40),
                title: 'Mes dessins',
                text: 'Chaque dessin que tu enregistres y laisse une carte : Color en garde une copie. Clique sur une carte pour reprendre le dessin.',
              ),
            const _HelpRow(
              key: Key('help-film'),
              picture: EduIllustration(art: EduArt.film, size: 40),
              title: 'Revoir ton dessin',
              text: 'Ton dessin se refait tout seul sous tes yeux, élément par élément, de celui du dessous à celui du dessus. Il ne change pas.',
            ),
            if (options.printing)
              const _HelpRow(
                key: Key('help-print'),
                picture: EduIllustration(art: EduArt.printer, size: 40),
                title: 'Imprimer',
                text: 'Ouvre la fenêtre d’impression de ton ordinateur, avec ton dessin sur une page. Rien ne s’imprime avant que tu le confirmes là.',
              ),
            const _HelpRow(
              key: Key('help-options'),
              picture: EduIllustration(art: EduArt.options, size: 40),
              title: 'Options',
              text: 'Pour les adultes : choisir ce que Color montre, couper les sons ou l’impression, régler l’accessibilité. Un calcul peut en garder l’entrée : c’est l’une des options.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Avec le clavier',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _KeyRow(
              keys: '1 à ${options.tools.length}',
              text: 'Choisir un outil, dans leur ordre.',
            ),
            _KeyRow(keys: '$command + Z', text: 'Annuler le dernier geste.'),
            _KeyRow(
              keys: 'Maj + $command + Z',
              text: 'Rétablir le geste annulé.',
            ),
            _KeyRow(keys: '$command + S', text: 'Enregistrer ton projet.'),
            if (options.opensFiles)
              _KeyRow(keys: '$command + O', text: 'Ouvrir un projet.'),
            _KeyRow(
              keys: '$command + N',
              text: 'Prendre une nouvelle feuille.',
            ),
            if (options.printing)
              _KeyRow(keys: '$command + P', text: 'Imprimer ton dessin.'),
            if (options.tools.contains(StudioTool.select)) ...[
              _KeyRow(keys: '$command + D', text: 'Copier l’élément choisi.'),
              const _KeyRow(
                keys: 'Flèches',
                text: 'Déplacer l’élément choisi. Avec Maj, il va plus vite.',
              ),
              const _KeyRow(keys: 'Suppr', text: 'Effacer l’élément choisi.'),
            ],
            if (options.viewControls)
              const _KeyRow(
                keys: 'Espace',
                text: 'Maintenu, il permet de glisser la feuille.',
              ),
            const _KeyRow(
              keys: 'Échap',
              text: 'Arrêter le geste en cours, sans rien changer.',
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(16),
      actions: [
        FilledButton(
          key: const Key('closeHelp'),
          autofocus: true,
          style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
          onPressed: () => Navigator.pop(context),
          child: const Text('Revenir au dessin'),
        ),
      ],
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({
    super.key,
    required this.picture,
    required this.title,
    required this.text,
  });
  final Widget picture;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    // One sentence for a screen reader: the picture only decorates.
    child: MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            height: 44,
            child: Center(child: ExcludeSemantics(child: picture)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  forTouch(text),
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.keys, required this.text});
  final String keys;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: MergeSemantics(
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: studioPreviewBox,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: studioSwatchRing),
            ),
            child: Text(
              keys,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    ),
  );
}
