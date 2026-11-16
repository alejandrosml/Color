// SPDX-License-Identifier: MIT
// Colours of the studio's own interface, never of a drawing. One place names
// them so that every panel uses the same ink and the readability test can
// check each text colour against the surfaces it is written on.
//
// Since Color 1.2 they are those of the universe the studio wears: a
// [StudioLook] holds them, with the corners of its pebbles, and the names
// below read the look of the moment. « Classique » is the look Color
// always had. The sheet stays white, the tools keep their pictures, and
// « Enregistrer » stays golden, whatever the look.
//
// A look holds what the pebbles and their dialogs read, and no more: what
// only the studio of before read — the band, the idea card, the inspector,
// the shapes of its panels and buttons — went with it (step G3).
//
// A look also says what its pebbles are made of (« Les galets », step G3):
// light ones, as in most universes, or those of the night, for a universe
// whose sky is dark — the pebble takes the colour of the sky, its ink is
// light, and every picture keeps a light round under it.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

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
    this.previewBox = const Color(0xfff2f3e9),
    this.warning = const Color(0xffb3261e),
    this.caption = const Color(0xff677870),
    this.statusText = const Color(0xff5c706d),
    this.sheetTitle = const Color(0xff57685d),
    this.sheetCaption = const Color(0xff56685c),
    this.quietMark = const Color(0xff7d8f8a),
    this.swatchRing = const Color(0xff89938e),
    this.stageRadius = 20,
    this.stageBorder = 1,
    this.galetRadius = 999,
    this.night = false,
    this.galetDisc,
    this.galetEdge,
    this.shadow = const Color(0xff263f43),
    this.shadowDepth = 1,
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

  /// A box set a little apart on a dialog: the question of the door of
  /// the options, a key of the keyboard in the help.
  final Color previewBox;

  /// What went wrong or could not be kept, written small in a dialog.
  final Color warning;

  /// Small captions on a pebble, a panel or a dialog: the title of a
  /// panel, what « Mon dessin » says the drawing holds.
  final Color caption;

  /// The last thing that happened to the drawing, said small in « Mon
  /// dessin ».
  final Color statusText;

  /// « MA FEUILLE » and the captions around the sheet, on its backdrop:
  /// what the description of a universe says for them. Nothing is written
  /// around the sheet of the pebbles, and nothing reads them now.
  final Color sheetTitle;
  final Color sheetCaption;

  /// Icons and dots of choices that are not the chosen one.
  final Color quietMark;

  /// The ring around a colour to choose. It alone separates the white colour
  /// from the panel, so it is drawn darker than a decorative line.
  final Color swatchRing;

  /// The frame around the sheet: what the description of a universe says
  /// for it. The sheet of the pebbles has no frame, and nothing reads them
  /// now.
  final double stageRadius;
  final double stageBorder;

  /// The corners of the pebbles (« Les galets », Color 1.2) and of their
  /// buttons: all round unless a universe says less.
  final double galetRadius;

  /// Pebbles of the night (the owner, 12 November 2026): for a universe
  /// whose sky is dark. The surface of the pebbles is then dark and their
  /// ink light; the dialogs follow.
  final bool night;

  /// The light round under every picture of a pebble of the night: the
  /// pictures of Color are drawn with a dark line, for a light surface.
  /// Null in a look of light pebbles, where a picture stands on the pebble
  /// itself.
  final Color? galetDisc;

  /// The thin line around a pebble, a panel and the sheet, where a shadow
  /// alone would not part them from a dark sky; null for none.
  final Color? galetEdge;

  /// The tint of the shadows of the pebbles, of their panels and of the
  /// sheet, and how deep they are: 1 as in « Classique », more on a dark
  /// sky, where a light shadow is not seen.
  final Color shadow;
  final double shadowDepth;

  /// What is written on a full button, whose surface is [accent]: white,
  /// or the darker of the ink and of the surface where the accent is too
  /// light for white letters — the pebbles of the night.
  Color get onAccent {
    const white = Color(0xffffffff);
    if (contrast(white, accent) >= 4.5) return white;
    return surface.computeLuminance() < ink.computeLuminance() ? surface : ink;
  }

  /// The contrast between two colours as WCAG 2 measures it, from 1 to 21.
  static double contrast(Color a, Color b) {
    final first = a.computeLuminance();
    final second = b.computeLuminance();
    return (math.max(first, second) + .05) / (math.min(first, second) + .05);
  }

  /// What a description says, the rest as in « Classique »: `colours`, by
  /// the names of the fields above, written `#rrggbb`, and `shapes`; and
  /// `galets`, « nuit » for pebbles of the night, « clair » or nothing for
  /// light ones. What is unknown, or of another type, keeps its default: a
  /// description never stops the studio.
  factory StudioLook.fromJson(Object? json) {
    if (json is! Map) return classic;
    final colours = json['colours'];
    final shapes = json['shapes'];
    final night = json['galets'] == 'nuit';
    // A description that changes nothing is « Classique » itself.
    if ((colours is! Map || colours.isEmpty) &&
        (shapes is! Map || shapes.isEmpty) &&
        !night) {
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
      previewBox: colour('previewBox', c.previewBox),
      warning: colour('warning', c.warning),
      caption: colour('caption', c.caption),
      statusText: colour('statusText', c.statusText),
      sheetTitle: colour('sheetTitle', c.sheetTitle),
      sheetCaption: colour('sheetCaption', c.sheetCaption),
      quietMark: colour('quietMark', c.quietMark),
      swatchRing: colour('swatchRing', c.swatchRing),
      stageRadius: number('stageRadius', c.stageRadius, 40),
      stageBorder: number('stageBorder', c.stageBorder, 4),
      galetRadius: number('galetRadius', c.galetRadius, 999),
      night: night,
      // Pebbles of the night always have their rounds: a description that
      // forgets them gets the lightest of its ink and of white.
      galetDisc:
          (colours is Map ? parseColour(colours['galetDisc']) : null) ??
          (night ? nightDisc : null),
      galetEdge: colours is Map ? parseColour(colours['galetEdge']) : null,
      shadow: colour('shadow', c.shadow),
      shadowDepth: number('shadowDepth', c.shadowDepth, 4),
    );
  }

  /// The round under a picture in pebbles of the night that name none.
  static const nightDisc = Color(0xffeceeff);

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
    // The ring alone parts a colour from the pebble it is as light, or as
    // dark, as: white on light pebbles, black on those of the night.
    if (night)
      ('anneau de la couleur noire', swatchRing, const Color(0xff1a1a1a))
    else
      ('anneau de la couleur blanche', swatchRing, const Color(0xffffffff)),
    ('repère d’un choix au repos', quietMark, surface),
    ('contour d’un choix retenu', accent, selected),
    // The pebbles: the ring of the colour in hand, on the pebble; and, in
    // pebbles of the night, the round of a picture on the pebble and on a
    // chosen button, and the dark line of the pictures on their round.
    ('anneau de la couleur en main', accent, surface),
    if (galetDisc case final disc?) ...[
      ('pastille d’une image, sur un galet', disc, surface),
      ('pastille d’une image, sur un choix retenu', disc, selected),
      ('trait d’une image, sur sa pastille', pictureInk, disc),
    ],
  ];

  /// The dark line the pictures of the interface are drawn with
  /// (child_art.dart, and every file of the core's art/interface/).
  static const pictureInk = Color(0xff293d4b);

  /// Every text colour with the surface it is written on, for the
  /// readability test: the pebbles, what they open, and the dialogs.
  List<(String, Color, Color)> get textOnSurface => [
    ('texte courant, sur un galet', ink, surface),
    ('texte courant, sur un choix retenu', ink, selected),
    ('nom d’un outil choisi', accent, selected),
    ('bouton de texte, lien', accent, surface),
    ('titre d’un panneau, état du dessin', caption, surface),
    ('dernière nouvelle du dessin', statusText, surface),
    ('avertissement', warning, surface),
    ('avertissement, dans un encadré', warning, previewBox),
    ('texte courant, dans un encadré', ink, previewBox),
    ('bouton plein', onAccent, accent),
    ('Enregistrer', studioSaveInk, studioSaveFill),
    ('message d’un problème', surface, ink),
    // The captions of a sheet without pebbles around it.
    ('titre de la feuille', sheetTitle, sheetBackdrop),
    ('légendes de la feuille', sheetCaption, sheetBackdrop),
    ('titre de la feuille, sur un décor', sheetTitle, surface),
    ('légendes de la feuille, sur un décor', sheetCaption, surface),
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

/// A box set a little apart on a dialog.
Color get studioPreviewBox => studioLook.value.previewBox;

/// What went wrong or could not be kept, written small in a dialog.
Color get studioWarning => studioLook.value.warning;

/// Small captions on a pebble, a panel or a dialog.
Color get studioCaption => studioLook.value.caption;

/// The last thing that happened to the drawing, in « Mon dessin ».
Color get studioStatusText => studioLook.value.statusText;

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
