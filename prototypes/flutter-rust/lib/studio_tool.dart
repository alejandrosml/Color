// SPDX-License-Identifier: MIT
import 'child_art.dart';
import 'rust_document.dart' show VectorKind;

/// What the pointer does on the sheet. Drawing tools create one kind of
/// object; the others act on the objects already there. The order is the
/// order of the buttons, and of the number keys 1 to 9.
enum StudioTool {
  brush(
    'Pinceau',
    EduArt.brush,
    VectorKind.stroke,
    'Choisis ta couleur et dessine librement. Annuler est là si tu changes d’idée !',
  ),
  line(
    'Ligne',
    EduArt.line,
    VectorKind.line,
    'Glisse du début au bout de ta ligne, ou clique le début puis clique le bout. Maj aide à la garder droite.',
  ),
  rectangle(
    'Rectangle',
    EduArt.rectangle,
    VectorKind.rectangle,
    'Glisse pour créer un rectangle, ou clique un coin puis le coin d’en face. Avec la touche Maj, il devient un carré !',
  ),
  ellipse(
    'Ovale',
    EduArt.ellipse,
    VectorKind.ellipse,
    'Glisse pour créer un ovale, ou clique deux fois, en biais : il se place entre tes deux clics. Avec la touche Maj, il devient un cercle !',
  ),
  text(
    'Texte',
    EduArt.text,
    VectorKind.text,
    'Clique là où ton texte doit commencer, puis écris-le. Tu pourras le déplacer avec Choisir.',
  ),
  stamp(
    'Tampon',
    EduArt.stamp,
    VectorKind.stamp,
    'Choisis un tampon, puis clique sur la feuille pour le poser. Glisse pour choisir toi-même sa taille.',
  ),
  fill(
    'Remplir',
    EduArt.fill,
    null,
    'Touche une forme ou une zone de ta page pour la remplir, ou la feuille pour la colorier. Un trait, un texte ou un tampon prend ta couleur ; l’arc-en-ciel garde les siennes.',
  ),
  eraser(
    'Gomme',
    EduArt.eraser,
    null,
    'Touche un élément pour l’effacer, ou glisse sur plusieurs. Annuler les fait revenir.',
  ),
  select(
    'Choisir',
    EduArt.select,
    null,
    'Clique un élément, puis glisse pour le déplacer. Clique une couleur ou change l’épaisseur : il change aussitôt. Échap annule le déplacement.',
  );

  const StudioTool(this.label, this.art, this.kind, this.help);

  /// Name on the button, and the tool's title in the inspector.
  final String label;
  final EduArt art;

  /// The kind of object this tool draws; null for a tool that draws nothing.
  final VectorKind? kind;

  /// One or two sentences that say what to do, shown beside the sheet and in
  /// « Comment faire ? ».
  final String help;

  /// Stable key of the tool's button: `tool-stroke`, `tool-select`…
  String get keyName => 'tool-${kind?.name ?? name}';

  /// Rectangles and ovals can be filled.
  bool get drawsFillableShape =>
      kind == VectorKind.rectangle || kind == VectorKind.ellipse;
}
