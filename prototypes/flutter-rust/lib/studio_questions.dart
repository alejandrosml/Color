// SPDX-License-Identifier: MIT
// The questions the studio asks before a drawing is replaced, and what it
// says about itself. Each returns an answer; the studio acts on it.
import 'package:flutter/material.dart';

import 'color_identity.dart';
import 'fit_to_screen.dart';
import 'french.dart';
import 'licences.dart';
import 'platform_words.dart';
import 'vector_art.dart';
import 'language.dart';

/// What to do with changes that are not saved.
enum KeepChanges { cancel, discard, save }

/// « Garder les modifications ? » Closing the dialog any other way than by
/// one of its buttons is « Annuler ».
Future<KeepChanges> showKeepChangesDialog(
  BuildContext context, {
  bool exports = true,
}) async =>
    await showDialog<KeepChanges>(
      context: context,
      builder: (dialogContext) => FitDialog(
        child: AlertDialog(
          title: Text(tr('Garder les modifications ?')),
          // An interface without « Exporter » does not speak of exported
          // pictures.
          content: Text(
            exports
                ? tr(
                    'Enregistre un projet Color pour pouvoir reprendre ce dessin. Une image exportée ne remplace pas le projet.',
                  )
                : tr(
                    'Enregistre un projet Color pour pouvoir reprendre ce dessin.',
                  ),
          ),
          actions: [
            TextButton(
              key: const Key('cancelChanges'),
              onPressed: () => Navigator.pop(dialogContext, KeepChanges.cancel),
              child: Text(tr('Annuler')),
            ),
            TextButton(
              key: const Key('discardChanges'),
              onPressed: () =>
                  Navigator.pop(dialogContext, KeepChanges.discard),
              child: Text(tr('Ne pas enregistrer')),
            ),
            FilledButton(
              key: const Key('saveChanges'),
              onPressed: () => Navigator.pop(dialogContext, KeepChanges.save),
              child: Text(tr('Enregistrer')),
            ),
          ],
        ),
      ),
    ) ??
    KeepChanges.cancel;

/// « Reprendre ton dessin ? » about a local recovery copy holding [count]
/// elements. True to take it back; anything else lets the copy go. The
/// question must be answered: it cannot be dismissed by clicking beside it.
Future<bool> showRecoveryDialog(
  BuildContext context, {
  required int count,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => FitDialog(
        child: AlertDialog(
          title: Text(tr('Reprendre ton dessin ?')),
          content: Text(
            trf(
              'Une copie locale contient {0}. Tu peux la reprendre et l’enregistrer dans un fichier Color.',
              [elementCount(count)],
            ),
          ),
          actions: [
            TextButton(
              key: const Key('discardRecovery'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr('Supprimer cette copie')),
            ),
            FilledButton(
              key: const Key('restoreRecovery'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr('Reprendre le dessin')),
            ),
          ],
        ),
      ),
    ) ==
    true;

/// « Sauver ce qui reste ? » about a damaged drawing (Color 1.1): [lost]
/// says what could not be read. True to open what is left, as a drawing
/// still to be saved under a name of its own: the damaged file stays as it
/// is.
/// [lost] says what could not be read; null when only the end of the file
/// was damaged and the whole drawing could be read.
Future<bool> showRescueDialog(
  BuildContext context, {
  required String? lost,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => FitDialog(
        child: AlertDialog(
          key: const Key('rescueDialog'),
          title: Text(tr('Ce dessin est abîmé')),
          content: Text(
            lost == null
                ? tr(
                    'La fin du fichier est abîmée, mais tout le dessin a pu être lu. Le fichier abîmé reste tel qu’il est ; tu enregistreras le dessin sous un autre nom.',
                  )
                : trf(
                    'Une partie du fichier ne peut plus être lue : {0}. Color peut ouvrir tout le reste. Le fichier abîmé reste tel qu’il est ; tu enregistreras ce qui reste sous un autre nom.',
                    [lost],
                  ),
          ),
          actions: [
            TextButton(
              key: const Key('cancelRescue'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr('Annuler')),
            ),
            FilledButton(
              key: const Key('confirmRescue'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                lost == null
                    ? tr('Ouvrir le dessin')
                    : tr('Ouvrir ce qui reste'),
              ),
            ),
          ],
        ),
      ),
    ) ==
    true;

// What the build said of the version of this program: the Flutter tool
// writes both from pubspec.yaml. Empty in a test.
const _buildName = String.fromEnvironment('FLUTTER_BUILD_NAME');
const _buildNumber = String.fromEnvironment('FLUTTER_BUILD_NUMBER');

/// The version of this program, « 0.7.1 (32) », or nothing when its build
/// did not say.
String get colorVersion => _buildName.isEmpty
    ? ''
    : _buildNumber.isEmpty
    ? _buildName
    : '$_buildName ($_buildNumber)';

/// « À propos de Color » : what a project keeps, and what Color keeps beside
/// it. [hasGallery] adds the sentence about « Mes dessins ». « Licences »
/// opens the page of the licences of Color and of what it is made with.
Future<void> showAboutColorDialog(
  BuildContext context, {
  required bool hasGallery,
  String? version,
  bool exports = true,
  bool layers = true,
  bool images = true,
}) {
  final shownVersion = version ?? colorVersion;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => FitDialog(
      child: AlertDialog(
        scrollable: true,
        title: Text(tr('Un dessin que tu peux retrouver.')),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: ColorLogo(key: Key('aboutLogo'))),
              const SizedBox(height: 12),
              Text(
                // What the interface of the moment does not offer is not
                // spoken of: [exports], [layers] and [images] say what it does.
                trf(
                  'Les projets Color gardent les traits, les formes, les textes, les tampons, les calques, les couleurs, la taille et la couleur de la feuille et les images de fond.\n\n'
                  'Enregistrer permet de reprendre le projet. {0}Une copie locale prépare la récupération après une interruption ; elle ne remplace pas ton fichier enregistré.\n\n'
                  '{1}'
                  '{2}'
                  '{3}',
                  [
                    exports
                        ? tr(
                            'Exporter crée une image PNG ou SVG pour partager ton dessin. ',
                          )
                        : '',
                    hasGallery
                        ? trf(
                            'Mes dessins range, dans le dossier de Color sur {0}, une petite image et une copie de chaque dessin enregistré. Retirer une carte les enlève ; ton fichier enregistré reste à sa place.\n\n',
                            [thisDevice],
                          )
                        : '',
                    images
                        ? tr(
                            'Tu peux dessiner sur une image PNG ou JPEG. Son fond reste fixe. ',
                          )
                        : '',
                    layers
                        ? tr(
                            'Un calque caché reste dans le projet, mais pas dans les images exportées. ',
                          )
                        : '',
                  ],
                ).trimRight(),
              ),
              if (shownVersion.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  trf('Color {0}', [shownVersion]),
                  key: const Key('aboutVersion'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (colorCopyright.isNotEmpty) ...[
                SizedBox(height: shownVersion.isEmpty ? 14 : 4),
                Text(
                  trf('{0} · licence MIT', [colorCopyright]),
                  key: const Key('aboutAuthor'),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('aboutPrivacy'),
            onPressed: () => showPrivacyPolicy(dialogContext),
            child: Text(tr('Confidentialité')),
          ),
          TextButton(
            key: const Key('aboutLicences'),
            onPressed: () {
              registerColorLicences();
              showLicensePage(
                context: dialogContext,
                applicationName: tr('Color'),
                applicationVersion: shownVersion.isEmpty ? null : shownVersion,
                applicationLegalese: colorLegalese,
              );
            },
            child: Text(tr('Licences')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('Revenir au dessin')),
          ),
        ],
      ),
    ),
  );
}

/// The logo of Color — the study « De face », chosen by the owner on
/// 7 October 2026 — drawn from the core's picture « logo », at any size.
/// Nothing at all with a core that has no such picture.
class ColorLogo extends StatelessWidget {
  const ColorLogo({super.key, this.side = 112});
  final double side;

  static String get description => tr(
    'Le logo de Color : un enfant dans son fauteuil roulant électrique, '
    'vu de face, lève son crayon.',
  );

  @override
  Widget build(BuildContext context) {
    final picture = VectorArtCatalog.instance?['logo'];
    if (picture == null) return const SizedBox.shrink();
    return Semantics(
      label: description,
      image: true,
      child: CustomPaint(
        size: Size.square(side),
        painter: _PicturePainter(picture),
      ),
    );
  }
}

class _PicturePainter extends CustomPainter {
  _PicturePainter(this.picture);
  final VectorPicture picture;

  @override
  void paint(Canvas canvas, Size size) =>
      picture.paint(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_PicturePainter oldDelegate) =>
      oldDelegate.picture != picture;
}

/// « Confidentialité » : the privacy policy of Color, read in Color itself,
/// as the stores ask. The same text is published beside the sources.
Future<void> showPrivacyPolicy(BuildContext context) => showDialog<void>(
  context: context,
  builder: (dialogContext) => FitDialog(
    child: AlertDialog(
      key: const Key('privacyPolicy'),
      scrollable: true,
      title: Text(tr('Confidentialité')),
      content: SizedBox(
        width: 470,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(colorPrivacyPolicy),
            if (colorSupportAddress.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(
                trf('Aide et questions : {0}', [colorSupportAddress]),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(tr('Revenir')),
        ),
      ],
    ),
  ),
);
