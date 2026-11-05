// SPDX-License-Identifier: MIT
// The letters of a text (Color 1.1): chosen in its dialog, kept for the next
// text, changed with the text in one step. Real Rust documents; only
// dialogs' destinations and storage are in memory.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  bool chosen(WidgetTester tester, int font) =>
      tester
          .getSemantics(find.byKey(Key('textFont-$font')))
          .flagsCollection
          .isSelected
          .toBoolOrNull() ??
      false;

  testWidgets('a text keeps the letters chosen for it', (tester) async {
    final handle = tester.ensureSemantics();
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-text');
    await studio.click(studio.at(300, 300));
    // Five fonts, the first one chosen.
    for (var font = 0; font < 5; font++) {
      expect(find.byKey(Key('textFont-$font')), findsOneWidget);
      expect(chosen(tester, font), font == 0);
    }
    await studio.tap('textFont-3');
    expect(chosen(tester, 3), isTrue);
    await studio.write('Ronde');
    await studio.tap('confirmText');
    studio.expectCount(1);
    // The next text begins with the same letters.
    await studio.click(studio.at(300, 550));
    expect(chosen(tester, 3), isTrue);
    await studio.tap('cancelText');
    var document = await studio.saved();
    try {
      expect(document.strokes.single.font, 3);
      expect(document.strokes.single.text, 'Ronde');
    } finally {
      document.dispose();
    }

    // Changed with « Choisir »: the dialog shows its letters, and the new
    // ones come with its words in one step.
    await studio.tap('tool-select');
    await studio.click(studio.at(330, 320));
    await studio.tap('editSelectionText');
    expect(chosen(tester, 3), isTrue);
    await studio.tap('textFont-4');
    await studio.tap('confirmText');
    document = await studio.saved();
    try {
      expect(document.strokes.single.font, 4);
      expect(await studio.svg(), contains('Playwrite FR Trad'));
    } finally {
      document.dispose();
    }
    await studio.tap('undo');
    document = await studio.saved();
    try {
      expect(document.strokes.single.font, 3);
    } finally {
      document.dispose();
    }
    handle.dispose();
    await studio.finish();
  }, skip: !available);
}
