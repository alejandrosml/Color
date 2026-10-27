// SPDX-License-Identifier: MIT
// The licences that Flutter does not find by itself: those of the Rust
// libraries the core is built from and the credits of the recordings some of
// its sounds are made of, which the core carries, and that of the font of the
// sheet, which comes with the application. They join the ones of Flutter and
// of its packages on the page « Licences » of « À propos ».
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'color_identity.dart';
import 'rust_document.dart';

/// The line that separates two notices, as in the NOTICES file of Flutter.
final _rule = '-' * 80;

/// Where the licence of the font of the sheet is kept in the application.
const fontLicenceAsset = 'fonts/LICENCE-DejaVu.txt';

/// The notices of [text], one entry per library: the lines before the first
/// empty line name the library, the rest is its notice. What does not have
/// that shape is left out: a notice is never shown under a wrong name.
List<LicenseEntry> coreLicenceEntries(String text) {
  final entries = <LicenseEntry>[];
  // A copy of the sources made with the line ends of Windows compiles the
  // notices with them: they are read all the same.
  for (final part in text.replaceAll('\r\n', '\n').split('\n$_rule\n')) {
    final split = part.indexOf('\n\n');
    if (split <= 0) continue;
    final names = part
        .substring(0, split)
        .split('\n')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final notice = part.substring(split + 2).trim();
    if (names.isEmpty || notice.isEmpty) continue;
    entries.add(LicenseEntryWithLineBreaks(names, notice));
  }
  return entries;
}

// Where the two texts come from. One collector is registered for the life
// of the process; it reads these when the page asks.
String Function() _coreNotices = RustDocument.thirdPartyNotices;
AssetBundle? _bundle;
bool _registered = false;

/// Adds those licences to the ones Flutter collects, once per process. What
/// cannot be read is left out: the page still opens with the rest.
/// [coreNotices] and [bundle] replace where the texts come from; tests give
/// them.
void registerColorLicences({
  String Function()? coreNotices,
  AssetBundle? bundle,
}) {
  if (coreNotices != null) _coreNotices = coreNotices;
  if (bundle != null) _bundle = bundle;
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(_licences);
}

Stream<LicenseEntry> _licences() async* {
  // Color's own licence first, with the name of its author.
  yield LicenseEntryWithLineBreaks(const ['Color'], colorLicenceText);
  var text = '';
  try {
    text = _coreNotices();
  } catch (_) {
    // A core that cannot name its libraries: nothing of it is shown.
  }
  yield* Stream.fromIterable(coreLicenceEntries(text));
  try {
    final font = await (_bundle ?? rootBundle).loadString(fontLicenceAsset);
    if (font.trim().isNotEmpty) {
      yield LicenseEntryWithLineBreaks(const [
        'DejaVu Sans (police des textes)',
      ], font.trim());
    }
  } catch (_) {
    // The file is not in this bundle: nothing to show for it.
  }
}
