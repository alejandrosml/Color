// SPDX-License-Identifier: MIT
// The interface in English (Color 1.1): every sentence the code gives to
// `tr` or `trf` has its English, nothing is left in the table that the code
// no longer says, and the studio speaks English when it is asked to — by
// the options, or by a device that prefers English.
import 'dart:convert';
import 'dart:io';

import 'package:edupaint_flutter_study/color_palette.dart';
import 'package:edupaint_flutter_study/decor_motion.dart';
import 'package:edupaint_flutter_study/english.dart';
import 'package:edupaint_flutter_study/galets.dart';
import 'package:edupaint_flutter_study/language.dart';
import 'package:edupaint_flutter_study/new_sheet_dialog.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/size_choice.dart';
import 'package:edupaint_flutter_study/stamp_catalog.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_tool.dart';
import 'package:edupaint_flutter_study/text_layout.dart';
import 'package:edupaint_flutter_study/tool_variants.dart';
import 'package:edupaint_flutter_study/universe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

/// The French sentences given to `tr` and `trf` in [source]: the string
/// literals right after the opening parenthesis, adjacent ones joined, their
/// escapes read as Dart reads them.
List<String> sentencesOf(String source) {
  final found = <String>[];
  final call = RegExp(r'\btrf?\(\s*');
  for (final match in call.allMatches(source)) {
    var at = match.end;
    final buffer = StringBuffer();
    var pieces = 0;
    while (true) {
      // Spaces and comments between adjacent literals.
      final gap = RegExp(r'(\s|//[^\n]*\n)*').matchAsPrefix(source, at);
      if (gap != null) at = gap.end;
      if (at >= source.length || source[at] != "'") break;
      at++;
      while (source[at] != "'") {
        if (source[at] == r'\') {
          final next = source[at + 1];
          if (next == 'n') {
            buffer.write('\n');
            at += 2;
          } else if (next == 'u') {
            final hex = source.substring(at + 2, at + 6);
            buffer.writeCharCode(int.parse(hex, radix: 16));
            at += 6;
          } else {
            buffer.write(next);
            at += 2;
          }
        } else {
          buffer.write(source[at]);
          at++;
        }
      }
      at++;
      pieces++;
    }
    if (pieces > 0) found.add(buffer.toString());
  }
  return found;
}

/// The French that reaches `tr` through a value rather than a literal: the
/// names of the tools, the colours, the stamps, the fonts, the sizes, the
/// sheets, the pages to colour.
Set<String> frenchOfValues() => {
  for (final tool in StudioTool.values) ...[
    tool.frenchLabel,
    tool.frenchHelp,
    // What the companion says of it in the bubble of the pebbles.
    tool.frenchTip.$1,
    tool.frenchTip.$2,
  ],
  // The ten elementary colours of the pebbles and their shades.
  for (final colour in galetColours) colour.frenchName,
  for (final family in galetFamilies)
    for (final shade in family) shade.frenchName,
  for (final magic in Magic.values) magic.frenchLabel,
  for (final pour in PourKind.values) pour.frenchLabel,
  for (final size in ObjectSize.values) size.frenchLabel,
  for (final shape in NewSheetShape.values) shape.frenchLabel,
  for (final level in InterfaceLevel.values) level.frenchLabel,
  for (final colour in [
    ...paintColors,
    ...morePaintColors,
    ...simplePaintColors,
  ])
    colour.frenchName,
  ...StampArt.frenchLabels.values,
  for (final font in textFonts) font.name,
  // The titles of the pages, as the catalogue of the core writes them. A
  // recipe that tests a copy of the application kept elsewhere (the Mac's,
  // scripts/build-flutter-study.py) names the core in EDUPAINT_CORE_SOURCES.
  for (final line in File(
    '${Platform.environment['EDUPAINT_CORE_SOURCES'] ?? '../native-swift-rust/core'}'
    '/src/catalogues/pages.txt',
  ).readAsLinesSync())
    if (line.startsWith('T '))
      Uri.decodeComponent(line.split(' ').skip(5).join(' ').trim()),
  // The universes (Color 1.2): the levels of movement, and what the
  // description of each universe says — its name, its line, and the name
  // and the lines of everything a child may ask about in its decor.
  for (final motion in DecorMotion.values) motion.frenchLabel,
  Universe.plain.frenchName,
  Universe.plain.frenchAbout,
  for (final folder in Directory(
    '${Platform.environment['EDUPAINT_CORE_SOURCES'] ?? '../native-swift-rust/core'}'
    '/art/univers',
  ).listSync().whereType<Directory>())
    ...frenchOfUniverse(
      jsonDecode(File('${folder.path}/univers.json').readAsStringSync())
          as Map<String, dynamic>,
    ),
};

/// What the description of one universe says in French.
List<String> frenchOfUniverse(Map<String, dynamic> universe) => [
  universe['name'] as String,
  universe['about'] as String,
  // A universe without a decor has nothing a child may ask about.
  for (final name
      in ((universe['decor'] as Map?)?['names'] as List?) ?? const []) ...[
    (name as Map)['name'] as String,
    name['text'] as String,
  ],
];

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('every sentence of the interface has its English, and no more', () {
    final used = <String>{};
    for (final file in Directory('lib').listSync()) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('english.dart') ||
          file.path.endsWith('language.dart')) {
        continue;
      }
      used.addAll(sentencesOf(file.readAsStringSync()));
    }
    used.addAll(frenchOfValues());
    expect(used.length, greaterThan(500));
    final missing = [
      for (final french in used)
        if (!englishWords.containsKey(french)) french,
    ];
    expect(missing, isEmpty, reason: 'sentences without their English');
    final unused = [
      for (final french in englishWords.keys)
        if (!used.contains(french)) french,
    ];
    expect(unused, isEmpty, reason: 'English that the code no longer says');
    // The same values to put in, the same spaces around.
    final placeholder = RegExp(r'\{\d\}');
    for (final MapEntry(key: french, value: english) in englishWords.entries) {
      Set<String> places(String text) => {
        for (final match in placeholder.allMatches(text)) match[0]!,
      };
      expect(places(english), places(french), reason: french);
      expect(english.trim().isNotEmpty, isTrue, reason: french);
      expect(english.startsWith(' '), french.startsWith(' '), reason: french);
      expect(english.endsWith(' '), french.endsWith(' '), reason: french);
    }
  });

  test('the device chooses: French first if it prefers it, else English', () {
    expect(deviceLanguage(const [Locale('fr', 'BE')]), AppLanguage.french);
    expect(
      deviceLanguage(const [Locale('de'), Locale('fr'), Locale('en')]),
      AppLanguage.french,
    );
    expect(deviceLanguage(const [Locale('en', 'US')]), AppLanguage.english);
    expect(deviceLanguage(const [Locale('es')]), AppLanguage.english);
    expect(deviceLanguage(const []), AppLanguage.english);
    // In the tests the device is French; the options decide otherwise.
    expect(languageOf(LanguageChoice.device), AppLanguage.french);
    expect(languageOf(LanguageChoice.english), AppLanguage.english);
    expect(
      StudioOptions.fromJson({'language': 'en'}).language,
      LanguageChoice.english,
    );
    expect(
      StudioOptions.fromJson({'language': 'klingon'}).language,
      LanguageChoice.device,
    );
  });

  test('a finger taps in English, and the keys it lacks are not spoken of', () {
    debugTouchFirstOverride = true;
    appLanguage.value = AppLanguage.english;
    try {
      expect(
        forTouch(
          'Click an element to select it. Esc cancels. Your two clicks.',
        ),
        'Tap an element to select it. Your two taps.',
      );
      expect(
        trf(
          'Une copie locale contient {0}. Tu peux la reprendre et '
          'l’enregistrer dans un fichier Color.',
          ['3 elements'],
        ),
        'A local copy holds 3 elements. You can take it back and save it in '
        'a Color file.',
      );
    } finally {
      debugTouchFirstOverride = null;
      appLanguage.value = AppLanguage.french;
    }
  });

  testWidgets('the studio speaks English when the options ask it to', (
    tester,
  ) async {
    final store = StudioOptionsStore.memory(
      const StudioOptions(language: LanguageChoice.english),
    );
    final studio = StudioDriver(tester, options: store);
    // A wide window: the tool in hand has its name written on the line.
    await studio.start(size: const Size(1440, 900));
    await tester.pumpAndSettle();
    expect(appLanguage.value, AppLanguage.english);
    expect(find.text('Brush'), findsWidgets);
    expect(
      tester.widget<GaletButton>(find.byKey(const Key('tool-eraser'))).label,
      'Eraser',
    );
    await studio.tap('tool-eraser');
    expect(find.text('Eraser'), findsWidgets);
    await studio.tap('tool-stroke');
    expect(find.text('Pinceau'), findsNothing);
    // A dialog, in English too.
    await studio.tap('newProject');
    expect(find.text('Choose the shape of your sheet'), findsOneWidget);
    expect(find.text('The rocket'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // Back to French, at once, the drawing kept.
    await studio.drag(studio.at(100, 100), studio.at(300, 200));
    expect(drawingCaption(tester), contains('1 element · '));
    store.value = store.value.copyWith(language: LanguageChoice.french);
    await tester.pumpAndSettle();
    expect(find.text('Pinceau'), findsWidgets);
    expect(find.text('Brush'), findsNothing);
    studio.expectCount(1);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('with the language of the device, a change of it is followed', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start(size: const Size(1440, 900));
    await tester.pumpAndSettle();
    expect(find.text('Pinceau'), findsWidgets);
    // The device now prefers English, while Color runs.
    debugDeviceLanguage = AppLanguage.english;
    try {
      tester.binding.platformDispatcher.localesTestValue = const [
        Locale('en', 'GB'),
      ];
      await tester.pumpAndSettle();
      expect(appLanguage.value, AppLanguage.english);
      expect(find.text('Brush'), findsWidgets);
      expect(find.text('Pinceau'), findsNothing);
    } finally {
      debugDeviceLanguage = AppLanguage.french;
      tester.binding.platformDispatcher.clearLocalesTestValue();
    }
    await tester.pumpAndSettle();
    expect(find.text('Pinceau'), findsWidgets);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('the line under the sheet follows a change of language', (
    tester,
  ) async {
    final store = StudioOptionsStore.memory(
      const StudioOptions(level: InterfaceLevel.full),
    );
    final studio = StudioDriver(tester, options: store);
    await studio.start();
    await tester.pumpAndSettle();
    expect(
      await drawingStatus(tester),
      contains('Nouvelle feuille · récupération locale prête.'),
    );
    // Said before the change, said again after it: in English…
    store.value = store.value.copyWith(language: LanguageChoice.english);
    await tester.pumpAndSettle();
    expect(
      await studio.status(),
      contains('New sheet · local recovery ready.'),
    );
    expect(await studio.status(), isNot(contains('récupération')));
    // …and, after a stroke, what the recovery says, again in French.
    await studio.drag(studio.at(100, 100), studio.at(300, 200));
    await tester.pumpAndSettle();
    final english = RegExp(r'(Changes not saved|Recovery copy up to date)');
    final french = RegExp(
      r'(Modifications non enregistrées|Copie de récupération à jour)',
    );
    expect(await studio.status(), contains(english));
    store.value = store.value.copyWith(language: LanguageChoice.french);
    await tester.pumpAndSettle();
    expect(await studio.status(), isNot(contains(english)));
    expect(await studio.status(), contains(french));
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);
}
