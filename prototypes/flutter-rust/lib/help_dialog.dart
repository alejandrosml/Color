// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'child_art.dart';
import 'fit_to_screen.dart';
import 'studio_colors.dart';
import 'studio_options.dart';
import 'studio_tool.dart';
import 'platform_words.dart';
import 'language.dart';

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
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : tr('Ctrl');

  @override
  Widget build(BuildContext context) {
    final command = commandKey;
    return AlertDialog(
      key: const Key('helpDialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      title: Text(tr('Comment faire ?')),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // In the order of the bar, « Formes » with all it holds.
            for (final tool in [
              for (final group in options.groups)
                ...group.tools.where(options.tools.contains),
            ])
              _HelpRow(
                key: Key('help-${tool.name}'),
                picture: EduIllustration(art: tool.art, size: 40),
                title: tool.label,
                text: tool.help,
              ),
            if (!options.simpleControls)
              _HelpRow(
                key: Key('help-picker'),
                picture: Icon(Icons.colorize, size: 30),
                title: tr('Pipette'),
                text: tr(
                  'À côté des couleurs. Appuie dessus, puis clique sur une couleur de ton dessin pour la reprendre.',
                ),
              ),
            if (options.layers)
              _HelpRow(
                key: Key('help-layers'),
                picture: EduIllustration(art: EduArt.layers, size: 40),
                title: tr('Calques'),
                text: tr(
                  'Des feuilles transparentes posées l’une sur l’autre. Tu peux en cacher une, ou la passer devant.',
                ),
              ),
            if (options.viewControls)
              _HelpRow(
                key: Key('help-big-sheet'),
                picture: Icon(Icons.open_in_full, size: 28),
                title: tr('Dessiner en grand'),
                text: tr(
                  'Range les panneaux pour laisser toute la place à ta feuille. Le même bouton les fait revenir.',
                ),
              ),
            if (hasGallery)
              _HelpRow(
                key: Key('help-gallery'),
                picture: EduIllustration(art: EduArt.gallery, size: 40),
                title: tr('Mes dessins'),
                text: tr(
                  'Chaque dessin que tu enregistres y laisse une carte : Color en garde une copie. Clique sur une carte pour reprendre le dessin, ou sur Diaporama pour les voir l’un après l’autre.',
                ),
              ),
            _HelpRow(
              key: Key('help-film'),
              picture: EduIllustration(art: EduArt.film, size: 40),
              title: tr('Revoir ton dessin'),
              text: tr(
                'Ton dessin se refait tout seul sous tes yeux, élément par élément, de celui du dessous à celui du dessus. Il ne change pas.',
              ),
            ),
            if (options.printing)
              _HelpRow(
                key: Key('help-print'),
                picture: EduIllustration(art: EduArt.printer, size: 40),
                title: tr('Imprimer'),
                text: tr(
                  'Ouvre la fenêtre d’impression de ton ordinateur, avec ton dessin sur une page. Rien ne s’imprime avant que tu le confirmes là.',
                ),
              ),
            _HelpRow(
              key: Key('help-options'),
              picture: EduIllustration(art: EduArt.options, size: 40),
              title: tr('Options'),
              text: tr(
                'Pour les adultes : choisir la langue et ce que Color montre, couper les sons ou l’impression, régler l’accessibilité. Un calcul peut en garder l’entrée : c’est l’une des options.',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Avec le clavier'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _KeyRow(
              keys: trf('1 à {0}', [options.groups.length]),
              text: tr('Choisir un outil, dans leur ordre.'),
            ),
            _KeyRow(
              keys: '$command + Z',
              text: tr('Annuler le dernier geste.'),
            ),
            _KeyRow(
              keys: trf('Maj + {0} + Z', [command]),
              text: tr('Rétablir le geste annulé.'),
            ),
            _KeyRow(keys: '$command + S', text: tr('Enregistrer ton projet.')),
            if (options.opensFiles)
              _KeyRow(keys: '$command + O', text: tr('Ouvrir un projet.')),
            _KeyRow(
              keys: '$command + N',
              text: tr('Prendre une nouvelle feuille.'),
            ),
            if (options.printing)
              _KeyRow(keys: '$command + P', text: tr('Imprimer ton dessin.')),
            if (options.tools.contains(StudioTool.select)) ...[
              _KeyRow(
                keys: '$command + D',
                text: tr('Copier l’élément choisi.'),
              ),
              _KeyRow(
                keys: tr('Flèches'),
                text: tr(
                  'Déplacer l’élément choisi. Avec Maj, il va plus vite.',
                ),
              ),
              _KeyRow(keys: tr('Suppr'), text: tr('Effacer l’élément choisi.')),
            ],
            if (options.viewControls)
              _KeyRow(
                keys: tr('Espace'),
                text: tr('Maintenu, il permet de glisser la feuille.'),
              ),
            _KeyRow(
              keys: tr('Échap'),
              text: tr('Arrêter le geste en cours, sans rien changer.'),
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
          child: Text(tr('Revenir au dessin')),
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
