// SPDX-License-Identifier: MIT
// The colours chosen last come back in the next session (Color 1.1), and
// two paints mix as paints do: blue and yellow make green.
import 'dart:io';

import 'package:edupaint_flutter_study/kept_colours.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('the colours are kept in a small file, and read back', () async {
    final folder = await Directory.systemTemp.createTemp('color-couleurs-');
    try {
      final file = File('${folder.path}/couleurs.json');
      final none = await KeptColours.openFile(file);
      expect(none.colours, isEmpty);
      await none.keep([0x3370d1, 0xeebf4e]);
      expect(await file.readAsString(), contains('#3370d1'));
      final again = await KeptColours.openFile(file);
      expect(again.colours, [0x3370d1, 0xeebf4e]);
      // What is not a file of colours gives none, and changes nothing.
      await file.writeAsString('{"couleurs": ["bleu", 12, "#zzzzzz"]}');
      expect((await KeptColours.openFile(file)).colours, isEmpty);
      await file.writeAsString('pas du JSON');
      expect((await KeptColours.openFile(file)).colours, isEmpty);
    } finally {
      await folder.delete(recursive: true);
    }
  });

  testWidgets('blue mixed with yellow is green, and it is kept', (
    tester,
  ) async {
    final kept = KeptColours.memory([0xf4b7cf]);
    final studio = StudioDriver(tester, keptColours: kept);
    await studio.start();
    // The blue of the start, then the paint.
    await studio.tap('morePaintColors');
    // A colour kept from before is among the recent ones.
    expect(find.byKey(const Key('dialog-recent-color-f4b7cf')), findsOneWidget);
    await studio.tap('mixPaint-eebf4e');
    await studio.tap('mixColours');
    await studio.tap('confirmPaintColor');
    // The colour mixed is kept, the latest first, with those of before.
    expect(kept.colours.first, isNot(0x477fb2));
    expect(kept.colours, contains(0xf4b7cf));
    await studio.tap('tool-stroke');
    await studio.drag(studio.at(300, 300), studio.at(600, 400));
    final saved = await studio.saved();
    try {
      final rgb = saved.strokes.single.rgb;
      final (r, g, b) = (rgb >> 16, (rgb >> 8) & 0xff, rgb & 0xff);
      expect(g, greaterThan(r));
      expect(g, greaterThan(b));
    } finally {
      saved.dispose();
    }
    await studio.finish();
  }, skip: !available);
}
