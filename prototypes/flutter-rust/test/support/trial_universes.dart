// SPDX-License-Identifier: MIT
// A universe for trials (Color 1.2, step G3): pebbles of the night, on a
// dark sky without a decor — what « L'espace » will wear when it is drawn
// (step 4 of the plan). It is in no catalogue of the application: the
// tests add it to the one they use, to look at the pebbles of the night,
// at their dialogs and at their contrasts before a real universe needs
// them. Its colours are those of the mock-ups the owner chose on 12
// November 2026 (« L'espace, galets de nuit »).
import 'package:edupaint_flutter_study/studio_colors.dart';
import 'package:edupaint_flutter_study/universe.dart';
import 'package:flutter_test/flutter_test.dart';

/// The description of the trial universe, as a file `univers.json` of the
/// core would write its look.
const nightTrialLook = <String, Object?>{
  'galets': 'nuit',
  'colours': {
    'ink': '#eef0ff',
    'accent': '#ffffff',
    'background': '#141842',
    'line': '#4b55c4',
    'surface': '#232a66',
    'selected': '#3d46a3',
    'sheetBackdrop': '#141842',
    'banner': '#232a66',
    'ideaCard': '#3d46a3',
    'previewBox': '#1a2052',
    'title': '#eef0ff',
    'warning': '#ffb4ab',
    'helpText': '#c9cdfa',
    'caption': '#c9cdfa',
    'inspectorCaption': '#c9cdfa',
    'inspectorText': '#c9cdfa',
    'documentCaption': '#c9cdfa',
    'statusText': '#c9cdfa',
    'sheetTitle': '#eef0ff',
    'sheetCaption': '#eef0ff',
    'ideaTitle': '#eef0ff',
    'ideaText': '#eef0ff',
    'quietMark': '#c9cdfa',
    'swatchRing': '#c9cdfa',
    'galetDisc': '#eceeff',
    'galetEdge': '#8f97f28c',
    'shadow': '#000000',
  },
  'shapes': {'shadowDepth': 2.6},
};

/// The key of the trial universe in the options.
const nightTrialKey = 'essai-de-nuit';

/// The trial universe: pebbles of the night, no decor.
Universe nightTrialUniverse() => Universe(
  key: nightTrialKey,
  frenchName: 'Essai de nuit',
  frenchAbout: 'Les galets de nuit, sur un ciel sombre.',
  look: StudioLook.fromJson(nightTrialLook),
);

/// From now to the end of the test, the catalogue of the application is
/// that of the core with the trial universe after its own.
void useTrialUniverses() {
  UniverseCatalog.debugUse(null);
  final own = UniverseCatalog.instance.universes;
  UniverseCatalog.debugUse(UniverseCatalog([...own, nightTrialUniverse()]));
  addTearDown(() => UniverseCatalog.debugUse(null));
}
