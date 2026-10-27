// SPDX-License-Identifier: MIT
// The licences shown from « À propos » : those of the libraries of the Rust
// core and the credits of its recorded sounds, as the real core carries them,
// and that of the font of the sheet.
import 'dart:convert';
import 'dart:io';

import 'package:edupaint_flutter_study/color_identity.dart';
import 'package:edupaint_flutter_study/licences.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_questions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// A bundle that holds the given texts and nothing else.
class _Texts extends CachingAssetBundle {
  _Texts(this.texts);
  final Map<String, String> texts;

  @override
  Future<ByteData> load(String key) async {
    final text = texts[key];
    if (text == null) throw FlutterError('No asset $key');
    return ByteData.sublistView(utf8.encode(text));
  }
}

String _text(LicenseEntry entry) =>
    entry.paragraphs.map((paragraph) => paragraph.text).join('\n');

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  final rule = '-' * 80;

  test('notices are cut into one entry per library', () {
    final entries = coreLicenceEntries(
      'premiere\n\npremiere 1.0 — licence MIT.\n\nTexte un.\n'
      '\n$rule\n'
      'seconde\nautre-nom\n\nseconde 2.0 — licence BSD-2-Clause.\n\nTexte deux.\n',
    );
    expect(entries, hasLength(2));
    expect(entries[0].packages, ['premiere']);
    expect(_text(entries[0]), contains('premiere 1.0 — licence MIT.'));
    expect(_text(entries[0]), contains('Texte un.'));
    expect(entries[1].packages, ['seconde', 'autre-nom']);
    expect(_text(entries[1]), isNot(contains('Texte un.')));
  });

  test('the line ends of Windows change nothing', () {
    // A checkout that turned every line end into two characters must not
    // empty the page of the licences.
    final unix =
        'premiere\n\npremiere 1.0 — licence MIT.\n\nTexte un.\n'
        '\n$rule\n'
        'seconde\n\nseconde 2.0 — licence BSD-2-Clause.\n\nTexte deux.\n';
    final entries = coreLicenceEntries(unix.replaceAll('\n', '\r\n'));
    expect(entries, hasLength(2));
    expect(entries[0].packages, ['premiere']);
    expect(entries[1].packages, ['seconde']);
    expect(_text(entries[1]), contains('seconde 2.0 — licence BSD-2-Clause.'));
    expect(_text(entries[0]), isNot(contains('\r')));
    expect(_text(entries[1]), isNot(contains('Texte un.')));
  });

  test('what is not a notice is never shown under a name', () {
    expect(coreLicenceEntries(''), isEmpty);
    expect(coreLicenceEntries('un nom sans texte'), isEmpty);
    expect(coreLicenceEntries('\n\nun texte sans nom'), isEmpty);
    expect(coreLicenceEntries('nom\n\n   \n'), isEmpty);
    final entries = coreLicenceEntries(
      'abîmé\n$rule\nbonne\n\nbonne 1.0.\n\nSon texte.\n',
    );
    expect(entries.single.packages, ['bonne']);
  });

  test('the real core names each of its libraries once, with a text', () {
    final all = coreLicenceEntries(RustDocument.thirdPartyNotices());
    // After the libraries come the recorded sounds, all under one name: the
    // core checks them against their provenance, this page only shows them.
    const recordings = 'Sons enregistrés';
    final sounds = [
      for (final entry in all)
        if (entry.packages.contains(recordings)) entry,
    ];
    expect(sounds, isNotEmpty);
    for (final entry in sounds) {
      expect(entry.packages, [recordings]);
      final text = _text(entry);
      expect(text, startsWith('Son « '));
      expect(text, contains('https://'));
      expect(
        RegExp(r'Licence : (CC0 1\.0 universel|domaine public)').hasMatch(text),
        isTrue,
        reason: text,
      );
    }
    expect(all.sublist(all.length - sounds.length), sounds);
    final entries = all.sublist(0, all.length - sounds.length);
    final names = [for (final entry in entries) ...entry.packages];
    expect(names, hasLength(entries.length));
    expect(names.toSet(), hasLength(names.length));
    expect(names, containsAll(['usvg', 'roxmltree', 'kurbo', 'memchr']));
    expect(names, orderedEquals([...names]..sort()));
    for (final entry in entries) {
      final name = entry.packages.single;
      final text = _text(entry);
      // Its name and version first, then a licence that goes with Color's.
      expect(text, startsWith('$name '), reason: name);
      expect(
        RegExp(r' — licence (MIT|BSD-2-Clause|BSD-3-Clause|Zlib|Unlicense)[,.]')
            .hasMatch(text),
        isTrue,
        reason: name,
      );
      expect(text.length, greaterThan(400), reason: name);
    }
  }, skip: !available);

  test('the registry gives them with the licence of the font', () async {
    registerColorLicences(
      coreNotices: () => 'essai-un\n\nessai-un 1.0 — licence MIT.\n\nTexte.\n',
      bundle: _Texts({fontLicenceAsset: 'Fonts are (c) Bitstream.\n'}),
    );
    final entries = await LicenseRegistry.licenses.toList();
    final names = [for (final entry in entries) ...entry.packages];
    expect(names, contains('essai-un'));
    expect(names, contains('DejaVu Sans (police des textes)'));
    final font = entries.firstWhere(
      (entry) => entry.packages.first.startsWith('DejaVu'),
    );
    expect(_text(font), 'Fonts are (c) Bitstream.');
  });

  test('a core or a bundle that fails leaves the rest', () async {
    registerColorLicences(
      coreNotices: () => throw StateError('pas de cœur'),
      bundle: _Texts({fontLicenceAsset: 'Police seule.\n'}),
    );
    var entries = await LicenseRegistry.licenses.toList();
    // Color's own licence comes first, whatever fails after it.
    expect(entries.first.packages, ['Color']);
    expect(_text(entries.first), contains('Permission is hereby granted'));
    expect(entries.skip(1).single.packages, [
      'DejaVu Sans (police des textes)',
    ]);
    expect(_text(entries.skip(1).single), 'Police seule.');
    registerColorLicences(
      coreNotices: () => 'essai-deux\n\nessai-deux 2.0.\n\nTexte.\n',
      bundle: _Texts(const {}),
    );
    entries = await LicenseRegistry.licenses.toList();
    expect(entries.skip(1).single.packages, ['essai-deux']);
    // Registered once, whatever the number of calls: nothing is shown twice.
    registerColorLicences();
    registerColorLicences();
    expect(await LicenseRegistry.licenses.toList(), hasLength(2));
  });

  test('the licence of the font is in the bundle of the application', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('    - $fontLicenceAsset\n'));
    final licence = File(fontLicenceAsset).readAsStringSync();
    expect(licence, contains('Bitstream'));
    expect(licence, contains('DejaVu'));
  });

  testWidgets('« À propos » says the version and opens the licences', (
    tester,
  ) async {
    registerColorLicences(
      coreNotices: () =>
          'essai-page\n\nessai-page 3.0 — licence MIT.\n\nTexte de la page.\n',
      bundle: _Texts({fontLicenceAsset: 'Police de la page.\n'}),
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (inner) {
            context = inner;
            return const Scaffold();
          },
        ),
      ),
    );
    showAboutColorDialog(context, hasGallery: true, version: '0.7.1 (32)');
    await tester.pumpAndSettle();
    expect(find.text('Color 0.7.1 (32)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('aboutLicences')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Color'), findsWidgets);
    expect(find.text('0.7.1 (32)'), findsOneWidget);
    expect(find.text(colorLegalese), findsOneWidget);
    expect(find.text('essai-page'), findsOneWidget);
    expect(find.text('DejaVu Sans (police des textes)'), findsOneWidget);
    // Back to the dialog, which was not closed.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsNothing);
    expect(find.byKey(const Key('aboutLicences')), findsOneWidget);
  });

  testWidgets('without a version « À propos » does not show one', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (inner) {
            context = inner;
            return const Scaffold();
          },
        ),
      ),
    );
    showAboutColorDialog(context, hasGallery: false, version: '');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('aboutVersion')), findsNothing);
    expect(find.byKey(const Key('aboutLicences')), findsOneWidget);
  });

  test('the version is the one of pubspec.yaml, as the build gives it', () {
    // The Flutter tool hands the name and the number of the build to the
    // program, also to this test.
    final version = RegExp(
      r'^version: (\d+\.\d+\.\d+)\+(\d+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    expect(colorVersion, '${version[1]} (${version[2]})');
  });
}
