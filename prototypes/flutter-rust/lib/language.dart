// SPDX-License-Identifier: MIT
// The language of the interface (Color 1.1): French, in which Color is
// written, or English. Every sentence of the interface is written in French
// in the code, and `tr` gives it in the language of the interface: in
// English, from the table of english.dart. A sentence missing from the table
// stays in French, which a test forbids.
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import 'english.dart';

enum AppLanguage {
  french('fr'),
  english('en');

  const AppLanguage(this.code);

  /// The code of the language, as a locale and the options file write it.
  final String code;

  Locale get locale => Locale(code);
}

/// What the adult chose in the options: the language of the device, or
/// one of those of Color, named in itself.
enum LanguageChoice {
  device('appareil'),
  french('fr'),
  english('en');

  const LanguageChoice(this.key);

  /// How the options file writes it.
  final String key;

  static LanguageChoice fromKey(Object? key) => values.firstWhere(
    (choice) => choice.key == key,
    orElse: () => LanguageChoice.device,
  );
}

/// The language of the device in a test: French, as the tests are written.
/// flutter_test_config.dart sets it; null reads the device.
@visibleForTesting
AppLanguage? debugDeviceLanguage;

/// The first language of Color among those the device prefers, in their
/// order; English when it prefers neither.
AppLanguage deviceLanguage([List<Locale>? preferred]) {
  final override = debugDeviceLanguage;
  if (override != null && preferred == null) return override;
  final locales = preferred ?? PlatformDispatcher.instance.locales;
  for (final locale in locales) {
    for (final language in AppLanguage.values) {
      if (locale.languageCode.toLowerCase() == language.code) return language;
    }
  }
  return AppLanguage.english;
}

/// The language that [choice] gives on this device.
AppLanguage languageOf(LanguageChoice choice) => switch (choice) {
  LanguageChoice.device => deviceLanguage(),
  LanguageChoice.french => AppLanguage.french,
  LanguageChoice.english => AppLanguage.english,
};

/// The language of the interface: the studio sets it from the options, and
/// rebuilds what it shows when it changes.
final appLanguage = ValueNotifier<AppLanguage>(AppLanguage.french);

bool get inEnglish => appLanguage.value == AppLanguage.english;

/// [french] in the language of the interface.
String tr(String french) =>
    inEnglish ? (englishWords[french] ?? french) : french;

/// [french] in the language of the interface, its {0}, {1}… replaced by
/// [values] in their order, in either language.
String trf(String french, List<Object?> values) => tr(
  french,
).replaceAllMapped(_placeholder, (match) => '${values[int.parse(match[1]!)]}');

final _placeholder = RegExp(r'\{(\d)\}');
