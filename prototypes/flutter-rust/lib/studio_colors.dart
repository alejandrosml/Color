// SPDX-License-Identifier: MIT
// Colours of the studio's own interface, never of a drawing. One place names
// them so that every panel uses the same ink and the readability test can
// check each text colour against the surfaces it is written on.
import 'dart:ui';

/// Main text and icons.
const studioInk = Color(0xff263f43);

/// Accent: the chosen tool, the chosen layer, confirmations.
const studioGreen = Color(0xff176c5f);

/// Window background around the panels.
const studioBackground = Color(0xfff2effa);

/// Outline of panels and quiet buttons.
const studioLine = Color(0xffd8e2d9);

/// Panels, toolbars and buttons at rest.
const studioSurface = Color(0xfffffefa);

/// A chosen tool, size or layer.
const studioSelected = Color(0xffe4f0e4);

/// The backdrop around the sheet.
const studioSheetBackdrop = Color(0xffe6e1f3);

/// The thin band above the header.
const studioBanner = Color(0xffeee7fa);

/// The « une petite idée » card.
const studioIdeaCard = Color(0xfffaeccb);

/// The example box of the inspector.
const studioPreviewBox = Color(0xfff2f3e9);

/// Violet of the name « Color ».
const studioTitle = Color(0xff6a4f99);

/// What went wrong or could not be kept, written small in a dialog.
const studioWarning = Color(0xffb3261e);

/// Small violet sentences: the band and the help under the palette.
const studioHelpText = Color(0xff675588);

/// Small grey-green captions on panels (« OUTILS », the tool's explanation).
const studioCaption = Color(0xff677870);

/// Caption of the inspector's title.
const studioInspectorCaption = Color(0xff67786c);

/// Explanation written in the inspector.
const studioInspectorText = Color(0xff66796d);

/// The line under the drawing's name, on the window background.
const studioDocumentCaption = Color(0xff616f66);

/// The status line at the bottom, on the window background.
const studioStatusText = Color(0xff5c706d);

/// « MA FEUILLE », on the sheet's backdrop.
const studioSheetTitle = Color(0xff57685d);

/// Size and zoom captions on the sheet's backdrop.
const studioSheetCaption = Color(0xff56685c);

/// Title and sentence of the idea card.
const studioIdeaTitle = Color(0xff836626);
const studioIdeaText = Color(0xff7c673e);

/// Icons and dots of choices that are not the chosen one.
const studioQuietMark = Color(0xff7d8f8a);

/// The ring around a colour to choose. It alone separates the white colour
/// from the panel, so it is drawn darker than a decorative line.
const studioSwatchRing = Color(0xff89938e);

/// Rings and marks that identify a control, with the surface they stand on:
/// the readability test asks three to one for these, as for any pictogram.
const studioMarkOnSurface = <(String, Color, Color)>[
  ('anneau d’une couleur', studioSwatchRing, studioSurface),
  ('anneau de la couleur blanche', studioSwatchRing, Color(0xffffffff)),
  ('repère d’un choix au repos', studioQuietMark, studioSurface),
  ('contour d’un choix retenu', studioGreen, studioSelected),
];

/// Every small text colour with the darkest surface it is written on, for
/// the readability test.
const studioTextOnSurface = <(String, Color, Color)>[
  ('bandeau', studioHelpText, studioBanner),
  ('aide de l’outil', studioHelpText, studioBackground),
  ('titre des outils', studioCaption, studioSurface),
  ('titre de l’inspecteur', studioInspectorCaption, studioSurface),
  ('texte de l’inspecteur', studioInspectorText, studioSurface),
  ('sous-titre du dessin', studioDocumentCaption, studioBackground),
  ('état', studioStatusText, studioBackground),
  ('titre de la feuille', studioSheetTitle, studioSheetBackdrop),
  ('légendes de la feuille', studioSheetCaption, studioSheetBackdrop),
  ('titre de l’idée', studioIdeaTitle, studioIdeaCard),
  ('texte de l’idée', studioIdeaText, studioIdeaCard),
  ('conseil de sélection', studioGreen, studioBackground),
  ('texte courant', studioInk, studioBackground),
  ('nom Color', studioTitle, studioSurface),
  ('avertissement', studioWarning, studioSurface),
];
