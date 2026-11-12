// SPDX-License-Identifier: MIT
// Colours of the studio's own interface, never of a drawing. One place names
// them so that every panel uses the same ink and the readability test can
// check each text colour against the surfaces it is written on.
//
// Since Color 1.2 they are those of the universe the studio wears: a
// [StudioLook] holds them, with the shapes of its panels and buttons, and
// the names below read the look of the moment. « Classique » is the look
// Color always had. The sheet stays white, the tools keep their place and
// their pictures, and « Enregistrer » stays golden, whatever the look.
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The shadow under the panels of a look.
enum PanelShadow {
  /// None: a thin line around the panel is enough.
  none,

  /// A soft one, hardly seen: the panels of the desk by the window.
  soft,

  /// A sheet of paper laid on the table.
  paper;

  static PanelShadow named(Object? name) => values.firstWhere(
    (shadow) => shadow.name == name,
    orElse: () => PanelShadow.none,
  );
}

/// How the buttons of the tools are drawn.
enum ToolShape {
  /// A tile with a line around it, as Color always drew them.
  tile,

  /// A round sticker of colour under the picture, without a tile.
  sticker;

  static ToolShape named(Object? name) =>
      values.firstWhere((shape) => shape.name == name, orElse: () => tile);
}

/// The colours and the shapes of the studio in one universe. Immutable; the
/// default of every field is « Classique ».
@immutable
class StudioLook {
  const StudioLook({
    this.ink = const Color(0xff263f43),
    this.accent = const Color(0xff176c5f),
    this.background = const Color(0xfff2effa),
    this.line = const Color(0xffd8e2d9),
    this.surface = const Color(0xfffffefa),
    this.selected = const Color(0xffe4f0e4),
    this.sheetBackdrop = const Color(0xffe6e1f3),
    this.banner = const Color(0xffeee7fa),
    this.ideaCard = const Color(0xfffaeccb),
    this.previewBox = const Color(0xfff2f3e9),
    this.title = const Color(0xff6a4f99),
    this.warning = const Color(0xffb3261e),
    this.helpText = const Color(0xff675588),
    this.caption = const Color(0xff677870),
    this.inspectorCaption = const Color(0xff67786c),
    this.inspectorText = const Color(0xff66796d),
    this.documentCaption = const Color(0xff616f66),
    this.statusText = const Color(0xff5c706d),
    this.sheetTitle = const Color(0xff57685d),
    this.sheetCaption = const Color(0xff56685c),
    this.ideaTitle = const Color(0xff836626),
    this.ideaText = const Color(0xff7c673e),
    this.quietMark = const Color(0xff7d8f8a),
    this.swatchRing = const Color(0xff89938e),
    this.buttonRadius = 13,
    this.buttonDashed = false,
    this.buttonBorder = 1,
    this.panelRadius = 20,
    this.panelBorder = 1,
    this.panelShadow = PanelShadow.none,
    this.stageRadius = 20,
    this.stageBorder = 1,
    this.tool = ToolShape.tile,
    this.galetRadius = 999,
  });

  /// The look Color always had, and the one of a universe that says nothing.
  static const classic = StudioLook();

  /// Main text and icons.
  final Color ink;

  /// The chosen tool, the chosen layer, confirmations.
  final Color accent;

  /// Window background around the panels.
  final Color background;

  /// Outline of panels and quiet buttons.
  final Color line;

  /// Panels, toolbars and buttons at rest.
  final Color surface;

  /// A chosen tool, size or layer.
  final Color selected;

  /// The backdrop around the sheet, where no decor is drawn.
  final Color sheetBackdrop;

  /// The thin band above the header.
  final Color banner;

  /// The « une petite idée » card.
  final Color ideaCard;

  /// The example box of the inspector.
  final Color previewBox;

  /// The name « Color ».
  final Color title;

  /// What went wrong or could not be kept, written small in a dialog.
  final Color warning;

  /// Small sentences: the band and the help under the palette.
  final Color helpText;

  /// Small captions on panels (« OUTILS », the tool's explanation).
  final Color caption;
  final Color inspectorCaption;
  final Color inspectorText;

  /// The line under the drawing's name, on the window background.
  final Color documentCaption;

  /// The status line at the bottom, on the window background.
  final Color statusText;

  /// « MA FEUILLE » and the captions around the sheet, on its backdrop.
  final Color sheetTitle;
  final Color sheetCaption;

  /// Title and sentence of the idea card.
  final Color ideaTitle;
  final Color ideaText;

  /// Icons and dots of choices that are not the chosen one.
  final Color quietMark;

  /// The ring around a colour to choose. It alone separates the white colour
  /// from the panel, so it is drawn darker than a decorative line.
  final Color swatchRing;

  /// The corners of the buttons, the width of their line, and whether that
  /// line is made of dashes.
  final double buttonRadius;
  final bool buttonDashed;
  final double buttonBorder;

  /// The corners of the panels, the width of their line (none at zero) and
  /// their shadow.
  final double panelRadius;
  final double panelBorder;
  final PanelShadow panelShadow;

  /// The frame around the sheet.
  final double stageRadius;
  final double stageBorder;

  final ToolShape tool;

  /// The corners of the pebbles (« Les galets », Color 1.2) and of their
  /// buttons: all round unless a universe says less.
  final double galetRadius;

  /// What a description says, the rest as in « Classique »: `colours`, by
  /// the names of the fields above, written `#rrggbb`, and `shapes`. What is
  /// unknown, or of another type, keeps its default: a description never
  /// stops the studio.
  factory StudioLook.fromJson(Object? json) {
    if (json is! Map) return classic;
    final colours = json['colours'];
    final shapes = json['shapes'];
    // A description that changes nothing is « Classique » itself.
    if ((colours is! Map || colours.isEmpty) &&
        (shapes is! Map || shapes.isEmpty)) {
      return classic;
    }
    Color colour(String name, Color fallback) =>
        (colours is Map ? parseColour(colours[name]) : null) ?? fallback;
    double number(String name, double fallback, double most) {
      final value = shapes is Map ? shapes[name] : null;
      return value is num && value.isFinite && value >= 0 && value <= most
          ? value.toDouble()
          : fallback;
    }

    const c = classic;
    return StudioLook(
      ink: colour('ink', c.ink),
      accent: colour('accent', c.accent),
      background: colour('background', c.background),
      line: colour('line', c.line),
      surface: colour('surface', c.surface),
      selected: colour('selected', c.selected),
      sheetBackdrop: colour('sheetBackdrop', c.sheetBackdrop),
      banner: colour('banner', c.banner),
      ideaCard: colour('ideaCard', c.ideaCard),
      previewBox: colour('previewBox', c.previewBox),
      title: colour('title', c.title),
      warning: colour('warning', c.warning),
      helpText: colour('helpText', c.helpText),
      caption: colour('caption', c.caption),
      inspectorCaption: colour('inspectorCaption', c.inspectorCaption),
      inspectorText: colour('inspectorText', c.inspectorText),
      documentCaption: colour('documentCaption', c.documentCaption),
      statusText: colour('statusText', c.statusText),
      sheetTitle: colour('sheetTitle', c.sheetTitle),
      sheetCaption: colour('sheetCaption', c.sheetCaption),
      ideaTitle: colour('ideaTitle', c.ideaTitle),
      ideaText: colour('ideaText', c.ideaText),
      quietMark: colour('quietMark', c.quietMark),
      swatchRing: colour('swatchRing', c.swatchRing),
      buttonRadius: number('buttonRadius', c.buttonRadius, 40),
      buttonDashed: shapes is Map && shapes['buttonDashed'] == true,
      buttonBorder: number('buttonBorder', c.buttonBorder, 4),
      panelRadius: number('panelRadius', c.panelRadius, 40),
      panelBorder: number('panelBorder', c.panelBorder, 4),
      panelShadow: PanelShadow.named(shapes is Map ? shapes['panelShadow'] : 0),
      stageRadius: number('stageRadius', c.stageRadius, 40),
      stageBorder: number('stageBorder', c.stageBorder, 4),
      tool: ToolShape.named(shapes is Map ? shapes['tool'] : null),
      galetRadius: number('galetRadius', c.galetRadius, 999),
    );
  }

  /// `#rrggbb` or `#rrggbbaa`, as the descriptions of the universes write a
  /// colour; null for anything else.
  static Color? parseColour(Object? text) {
    if (text is! String || !text.startsWith('#')) return null;
    final digits = text.substring(1);
    final value = int.tryParse(digits, radix: 16);
    if (value == null) return null;
    if (digits.length == 6) return Color(0xff000000 | value);
    if (digits.length == 8) return Color(((value & 0xff) << 24) | (value >> 8));
    return null;
  }

  /// Rings and marks that identify a control, with the surface they stand
  /// on: the readability test asks three to one for these, as for any
  /// pictogram.
  List<(String, Color, Color)> get marksOnSurface => [
    ('anneau d’une couleur', swatchRing, surface),
    ('anneau de la couleur blanche', swatchRing, const Color(0xffffffff)),
    ('repère d’un choix au repos', quietMark, surface),
    ('contour d’un choix retenu', accent, selected),
  ];

  /// Every small text colour with the darkest surface it is written on, for
  /// the readability test.
  List<(String, Color, Color)> get textOnSurface => [
    ('bandeau', helpText, banner),
    ('aide de l’outil', helpText, background),
    ('titre des outils', caption, surface),
    ('titre de l’inspecteur', inspectorCaption, surface),
    ('texte de l’inspecteur', inspectorText, surface),
    ('sous-titre du dessin', documentCaption, background),
    ('état', statusText, background),
    ('titre de la feuille', sheetTitle, sheetBackdrop),
    ('légendes de la feuille', sheetCaption, sheetBackdrop),
    ('titre de la feuille, sur un décor', sheetTitle, surface),
    ('légendes de la feuille, sur un décor', sheetCaption, surface),
    ('titre de l’idée', ideaTitle, ideaCard),
    ('texte de l’idée', ideaText, ideaCard),
    ('conseil de sélection', accent, background),
    ('texte courant', ink, background),
    ('texte courant, sur un panneau', ink, surface),
    ('nom d’un outil choisi', accent, selected),
    ('nom Color', title, surface),
    ('avertissement', warning, surface),
    ('bouton plein', const Color(0xffffffff), accent),
    ('Enregistrer', ink, studioSaveFill),
    // The pebbles (Color 1.2): what a panel says of the drawing, and
    // « Enregistrer », whose ink stays dark on its gold in every universe.
    ('dernière nouvelle du dessin', statusText, surface),
    ('Enregistrer, sur un galet', studioSaveInk, studioSaveFill),
  ];
}

/// The look the studio wears, and who is told when it changes.
class StudioLookNotifier extends ChangeNotifier
    implements ValueListenable<StudioLook> {
  StudioLook _value = StudioLook.classic;

  @override
  StudioLook get value => _value;

  set value(StudioLook look) {
    if (identical(look, _value)) return;
    _value = look;
    notifyListeners();
  }

  /// The look of a studio that is about to be built for the first time, or
  /// again: nobody is told, since everything that reads it is being built.
  /// Only the root of the application dresses the studio this way.
  void wearBeforeBuild(StudioLook look) => _value = look;
}

/// The look the studio wears: that of its universe. Whoever changes it also
/// asks the studio to build again (see universe.dart).
final studioLook = StudioLookNotifier();

/// « Enregistrer » is golden in every universe: the one action never to
/// forget keeps its colour.
const studioSaveFill = Color(0xffffd575);

/// The ink of « Enregistrer » on a pebble: dark on its gold, whatever the
/// ink of the universe — a universe of night writes in a light ink.
const studioSaveInk = Color(0xff263f43);

/// Main text and icons.
Color get studioInk => studioLook.value.ink;

/// Accent: the chosen tool, the chosen layer, confirmations.
Color get studioGreen => studioLook.value.accent;

/// Window background around the panels.
Color get studioBackground => studioLook.value.background;

/// Outline of panels and quiet buttons.
Color get studioLine => studioLook.value.line;

/// Panels, toolbars and buttons at rest.
Color get studioSurface => studioLook.value.surface;

/// A chosen tool, size or layer.
Color get studioSelected => studioLook.value.selected;

/// The backdrop around the sheet.
Color get studioSheetBackdrop => studioLook.value.sheetBackdrop;

/// The thin band above the header.
Color get studioBanner => studioLook.value.banner;

/// The « une petite idée » card.
Color get studioIdeaCard => studioLook.value.ideaCard;

/// The example box of the inspector.
Color get studioPreviewBox => studioLook.value.previewBox;

/// The colour of the name « Color ».
Color get studioTitle => studioLook.value.title;

/// What went wrong or could not be kept, written small in a dialog.
Color get studioWarning => studioLook.value.warning;

/// Small sentences: the band and the help under the palette.
Color get studioHelpText => studioLook.value.helpText;

/// Small captions on panels (« OUTILS », the tool's explanation).
Color get studioCaption => studioLook.value.caption;

/// Caption of the inspector's title.
Color get studioInspectorCaption => studioLook.value.inspectorCaption;

/// Explanation written in the inspector.
Color get studioInspectorText => studioLook.value.inspectorText;

/// The line under the drawing's name, on the window background.
Color get studioDocumentCaption => studioLook.value.documentCaption;

/// The status line at the bottom, on the window background.
Color get studioStatusText => studioLook.value.statusText;

/// « MA FEUILLE », on the sheet's backdrop.
Color get studioSheetTitle => studioLook.value.sheetTitle;

/// Size and zoom captions on the sheet's backdrop.
Color get studioSheetCaption => studioLook.value.sheetCaption;

/// Title and sentence of the idea card.
Color get studioIdeaTitle => studioLook.value.ideaTitle;
Color get studioIdeaText => studioLook.value.ideaText;

/// Icons and dots of choices that are not the chosen one.
Color get studioQuietMark => studioLook.value.quietMark;

/// The ring around a colour to choose.
Color get studioSwatchRing => studioLook.value.swatchRing;

/// Rings and marks of the look of the moment, for the readability test.
List<(String, Color, Color)> get studioMarkOnSurface =>
    studioLook.value.marksOnSurface;

/// Text colours of the look of the moment, for the readability test.
List<(String, Color, Color)> get studioTextOnSurface =>
    studioLook.value.textOnSurface;
