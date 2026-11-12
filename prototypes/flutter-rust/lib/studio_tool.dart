// SPDX-License-Identifier: MIT
import 'child_art.dart';
import 'rust_document.dart' show VectorKind;
import 'language.dart';

/// What the pointer does on the sheet. Drawing tools create one kind of
/// object; the others act on the objects already there. The bar shows them
/// by [ToolGroup]: the nine of Color 1.0 keep their order, the rectangle and
/// the oval now chosen in « Formes ».
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
  ),
  // Color 1.1: after the nine of 1.0, which keep their number keys.
  magic(
    'Magie',
    EduArt.magic,
    VectorKind.stroke,
    'Choisis une magie près des couleurs, puis glisse sur ta feuille : un arc-en-ciel, de l’herbe, des briques, des confettis, ou un miroir qui dessine deux fois !',
  ),
  shapes(
    'Formes',
    EduArt.shapes,
    VectorKind.contour,
    'Choisis une forme près des couleurs, puis glisse pour la dessiner : triangle, étoile, cœur, losange, hexagone ou flèche.',
  ),
  magnet(
    'Aimant',
    EduArt.magnet,
    VectorKind.stroke,
    'Dessine une forme à main levée : quand tu lèves le doigt, elle devient toute droite. Un rond devient un cercle, une boîte un rectangle !',
  );

  const StudioTool(this.frenchLabel, this.art, this.kind, this.frenchHelp);

  /// Name on the button, and the tool's title in the inspector, in French;
  /// [label] gives it in the language of the interface.
  final String frenchLabel;
  final EduArt art;

  /// The kind of object this tool draws; null for a tool that draws nothing.
  final VectorKind? kind;

  /// One or two sentences that say what to do, shown beside the sheet and in
  /// « Comment faire ? », in French; [help] gives them in the language of the
  /// interface.
  final String frenchHelp;

  String get label => tr(frenchLabel);
  String get help => tr(frenchHelp);

  /// What the companion says of the tool in its bubble (Color 1.2, « Les
  /// galets »): a few words, said in bold, then one short sentence, in
  /// French; [tip] gives them in the language of the interface. The whole
  /// of [frenchHelp] stays in « Comment faire ? ».
  (String, String) get frenchTip => switch (this) {
    brush => ('Un trait, une idée.', 'Choisis ta couleur et dessine !'),
    line => ('Tout droit !', 'Glisse du début au bout de ta ligne.'),
    rectangle => ('Un rectangle.', 'Glisse d’un coin au coin d’en face.'),
    ellipse => ('Un ovale.', 'Glisse en biais pour le dessiner.'),
    text => ('Des mots sur ta feuille.', 'Clique là où ils commencent.'),
    stamp => ('Un tampon, et hop !', 'Pose-le sur ta feuille.'),
    fill => ('De la couleur partout.', 'Clique une zone pour la remplir.'),
    eraser => ('On efface.', 'Clique ce que tu veux enlever.'),
    select => ('Choisis un élément.', 'Glisse-le pour le déplacer.'),
    magic => ('De la magie !', 'Glisse sur ta feuille.'),
    shapes => ('Une forme.', 'Glisse pour la dessiner.'),
    magnet => ('L’aimant redresse.', 'Dessine à main levée, il fait le reste.'),
  };

  (String, String) get tip => (tr(frenchTip.$1), tr(frenchTip.$2));

  /// Stable key of the tool's button: `tool-stroke`, `tool-select`… The
  /// tools of 1.1, two of which draw strokes too, by their own names. The
  /// rectangle, the oval and the magnet keep theirs in the choices of
  /// « Formes », whose button is `tool-shapes`.
  String get keyName => switch (this) {
    magic || shapes || magnet => 'tool-$name',
    _ => 'tool-${kind?.name ?? name}',
  };

  /// The button of the bar that holds this tool.
  ToolGroup get group => ToolGroup.of(this);

  /// Rectangles, ovals and the shapes of 1.1 can be filled.
  bool get drawsFillableShape =>
      kind == VectorKind.rectangle ||
      kind == VectorKind.ellipse ||
      this == shapes;
}

/// The buttons of the tool bar, in its order and that of the number keys 1
/// to 9, as Tux Paint has them: one for each tool, but « Formes », which
/// holds the rectangle, the oval, the shapes of Color 1.1 and the magnet,
/// chosen where the help is written.
enum ToolGroup {
  brush([StudioTool.brush]),
  line([StudioTool.line]),
  shapes([
    StudioTool.rectangle,
    StudioTool.ellipse,
    StudioTool.shapes,
    StudioTool.magnet,
  ]),
  text([StudioTool.text]),
  stamp([StudioTool.stamp]),
  fill([StudioTool.fill]),
  eraser([StudioTool.eraser]),
  select([StudioTool.select]),
  magic([StudioTool.magic]);

  const ToolGroup(this.tools);

  /// The tools of the button; the first is chosen when none was before.
  final List<StudioTool> tools;

  static ToolGroup of(StudioTool tool) {
    for (final group in values) {
      if (group.tools.contains(tool)) return group;
    }
    throw StateError('Outil sans bouton : $tool');
  }

  String get label => this == shapes ? tr('Formes') : tools.first.label;
  EduArt get art => this == shapes ? EduArt.shapes : tools.first.art;

  /// Stable key of the button: that of its tool, `tool-shapes` for
  /// « Formes ».
  String get keyName => this == shapes ? 'tool-shapes' : tools.first.keyName;

  /// What the button does, in « Comment faire ? ».
  String get help => this == shapes
      ? tr(
          'Choisis une forme près des couleurs : un rectangle, un ovale, un triangle, une étoile, un cœur… ou l’aimant, qui redresse ce que tu dessines.',
        )
      : tools.first.help;
}

/// The magic of the « Magie » tool.
enum Magic {
  rainbow('Arc-en-ciel'),
  grass('Herbe'),
  bricks('Briques'),
  confetti('Confettis'),

  /// Each stroke drawn twice, the second one in the mirror of the middle of
  /// the sheet.
  mirror('Miroir');

  const Magic(this.frenchLabel);
  final String frenchLabel;
  String get label => tr(frenchLabel);
}
