// SPDX-License-Identifier: MIT
// The trial of the published Windows version (scripts/windows-desktop/
// essai-publie.py) prints with the real pointer of Windows: it clicks
// « Mon dessin », then its tile « Imprimer », at two points written in the
// script. Those points are read here and pressed in the same window — 1264 x
// 681 inside, in English, the language of the machines of GitHub, with the
// letters of the application —: when the header or the panel moves, this test
// fails before a published version is tried with the old points.
import 'dart:io';

import 'package:edupaint_flutter_study/language.dart';
import 'package:edupaint_flutter_study/studio_printer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_printer.dart';
import 'support/interface_font.dart';
import 'support/memory_gallery.dart';
import 'support/studio_driver.dart';

/// The point named [name] in the trial: `NAME = (x, y)`.
Offset pointOfTheTrial(String script, String name) {
  final found = RegExp(
    '^$name = \\((\\d+), (\\d+)\\)\$',
    multiLine: true,
  ).firstMatch(script);
  if (found == null) {
    throw StateError('essai-publie.py names no point $name');
  }
  return Offset(double.parse(found[1]!), double.parse(found[2]!));
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  testWidgets(
    'the points of the Windows trial press « Mon dessin », then « Imprimer »',
    (tester) async {
      final script = File('../../scripts/windows-desktop/essai-publie.py')
          .readAsStringSync();
      final myDrawing = pointOfTheTrial(script, 'MY_DRAWING');
      final printTile = pointOfTheTrial(script, 'PRINT_TILE');
      await loadInterfaceFont(tester);
      appLanguage.value = AppLanguage.english;
      // The album is there, as in the published version: « Mes dessins »
      // stands before « Imprimer » in the panel.
      final printer = FakePrinter()..outcome = PrintOutcome.cancelled;
      final studio = StudioDriver(
        tester,
        gallery: MemoryGallery(),
        printer: printer.call,
      );
      await studio.start(size: const Size(1264, 681));

      // Well inside, not on an edge: a few pixels of difference between two
      // machines still press the same thing.
      Rect inside(String key) =>
          tester.getRect(find.byKey(Key(key))).deflate(12);
      Future<void> pressBothPoints() async {
        expect(inside('myDrawing').contains(myDrawing), isTrue);
        await tester.tapAt(myDrawing);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('galetPanel-drawing')), findsOneWidget);
        expect(inside('printDrawing').contains(printTile), isTrue);
        await tester.tapAt(printTile);
      }

      // Cancelled, then confirmed, as the trial does: the panel has gone
      // with the first press, and the same two points reach it again.
      await printAndWait(tester, printer, press: pressBothPoints);
      expect(find.byKey(const Key('galetPanel-drawing')), findsNothing);
      printer.outcome = PrintOutcome.sent;
      await printAndWait(tester, printer, press: pressBothPoints);
      expect(printer.requests, hasLength(2));
      await studio.finish();
    },
    skip: !available,
  );
}
