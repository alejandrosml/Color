// SPDX-License-Identifier: MIT
// The font of the texts is a subset of DejaVu Sans (scripts/alleger-la-police
// .py): what it keeps must lay out exactly as the whole font did, and the
// whole font, kept in fonts/source/, must not be carried by the application.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _samples = [
  'Le petit chat dort sur la chaise, près de la fenêtre.',
  'AVATAR Tour Wagon Yoyo « Ça va ? » — 1 234,56 € … ½ ¾',
  'ÉÈÊËÀÂÙÛÜÇÎÏÔÖŒÆŸ éèêëàâùûüçîïôöœæÿ áíóúñãõäìò',
  'fi fl ffi ffl ﬁ ﬂ',
  'azertyuiop qsdfghjklm wxcvbn’-., ?!:;()+=♥★ -×÷<>€%"/@',
  // The English keyboard of Color 1.1.
  r'qwertyuiop asdfghjkl’ zxcvbnm-., $ £',
  'Ελληνικά: αβγδε ΑΒΓΔΕ ἀρχή',
  'Кириллица: привет мир ЖЩЮЯ',
  '← ↑ → ↓ ⇒ ∞ ≠ ≤ ≥ ∑ √ ■ □ ● ○ ☺ ☼ ✓ ✔ ✿ ❤',
  'x² H₂O ℃ № ™ ① ② ③',
  // What an emoji keyboard types as text, variation selector included.
  '⬅️⬆️⬇️ ❤️ ✂️ ☀️ ␣',
];

Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

TextPainter _laid(String text, String family, double size) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(fontFamily: family, fontSize: size),
  ),
  textDirection: TextDirection.ltr,
)..layout();

void main() {
  testWidgets('the kept characters lay out as with the whole font', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await _load('ColorSansLight', 'fonts/DejaVuSans.ttf');
      await _load('ColorSansWhole', 'fonts/source/DejaVuSans.ttf');
    });
    for (final size in [11.0, 32.0, 96.0]) {
      for (final text in _samples) {
        final light = _laid(text, 'ColorSansLight', size);
        final whole = _laid(text, 'ColorSansWhole', size);
        expect(light.width, whole.width, reason: '$size: $text');
        expect(light.height, whole.height, reason: '$size: $text');
        final lightLine = light.computeLineMetrics().single;
        final wholeLine = whole.computeLineMetrics().single;
        expect(lightLine.baseline, wholeLine.baseline, reason: text);
        expect(lightLine.ascent, wholeLine.ascent, reason: text);
        expect(lightLine.descent, wholeLine.descent, reason: text);
        // Every character in the same place: kerning and ligatures kept.
        for (var offset = 0; offset < text.length; offset++) {
          expect(
            light.getOffsetForCaret(ui.TextPosition(offset: offset), Rect.zero),
            whole.getOffsetForCaret(ui.TextPosition(offset: offset), Rect.zero),
            reason: '$size: $text at $offset',
          );
        }
        light.dispose();
        whole.dispose();
      }
    }
  });

  test('the application carries the light font only', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- asset: fonts/DejaVuSans.ttf'));
    // Declared nowhere: not as a font, nor as an asset, nor through the
    // whole folder fonts/.
    final declared = RegExp(
      r'^\s*-\s*(asset:\s*)?fonts/(source|\s*$)',
      multiLine: true,
    );
    expect(declared.hasMatch(pubspec), isFalse);
    final light = File('fonts/DejaVuSans.ttf').lengthSync();
    final whole = File('fonts/source/DejaVuSans.ttf').lengthSync();
    expect(light, lessThan(whole * 0.7));
  });
}
