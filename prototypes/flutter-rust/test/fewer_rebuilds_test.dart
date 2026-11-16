// SPDX-License-Identifier: MIT
// F-03 of the retrospective of October 2026: a trait builds the studio once,
// when it ends. The press and the moves paint the sheet only; the copy of
// recovery written after it changes the line of status alone; and the menu
// bar of the Mac is sent again only when the commands it offers change.
import 'dart:io';

import 'package:edupaint_flutter_study/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/studio_driver.dart';

Future<void> _until(
  WidgetTester tester,
  bool Function() done,
  String reason,
) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  fail('Not reached: $reason');
}

Future<void> _trait(WidgetTester tester, Offset from, {int steps = 6}) async {
  final gesture = await tester.startGesture(from);
  await tester.pump();
  for (var step = 1; step <= steps; step++) {
    await gesture.moveTo(from + Offset(step * 30.0, step.isEven ? 8 : -8));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  testWidgets('a trait builds the studio once, when it ends', (tester) async {
    final recovery = MemoryRecovery();
    final studio = StudioDriver(tester, recovery: recovery);
    await studio.start();
    debugStudioBuilds = 0;
    final from = studio.sheetCenter - const Offset(120, 0);
    final gesture = await tester.startGesture(from);
    await tester.pump();
    // The press, then every move: the sheet only.
    expect(debugStudioBuilds, 0);
    for (var step = 1; step <= 8; step++) {
      await gesture.moveTo(from + Offset(step * 25.0, step.isEven ? 6 : -6));
      await tester.pump();
    }
    expect(debugStudioBuilds, 0);
    await gesture.up();
    await tester.pump();
    expect(debugStudioBuilds, 1);
    studio.expectCount(1);
    // The copy of recovery, written meanwhile, says so on its line alone.
    await _until(tester, () => recovery.writes >= 1, 'a copy of recovery');
    await tester.pump();
    expect(debugStudioBuilds, 1);
    // « Mon dessin » says it, once opened: the studio was not built again
    // to say it.
    expect(
      await studio.status(),
      contains('Copie de récupération à jour · projet à enregistrer.'),
    );
    await studio.finish();
  }, skip: !available);

  testWidgets('a shape is drawn the same way: the press builds nothing', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-rectangle');
    debugStudioBuilds = 0;
    await _trait(tester, studio.sheetCenter - const Offset(90, 40), steps: 4);
    expect(debugStudioBuilds, 1);
    studio.expectCount(1);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'the menu bar of the Mac is sent when what it offers changes',
    (tester) async {
      var sent = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.menu,
        (call) async {
          if (call.method == 'Menu.setMenus') sent++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.menu,
          null,
        ),
      );
      final studio = StudioDriver(tester);
      await studio.start();
      await tester.pumpAndSettle();
      // The first trait makes « Annuler » and the film possible: once.
      final before = sent;
      await _trait(tester, studio.sheetCenter - const Offset(120, 60));
      await tester.pumpAndSettle();
      expect(sent - before, lessThanOrEqualTo(1));
      // Four more change nothing of what the menus offer: nothing is sent.
      final after = sent;
      for (var trait = 0; trait < 4; trait++) {
        await _trait(tester, studio.sheetCenter + Offset(-120, trait * 30.0));
        await tester.pumpAndSettle();
      }
      expect(sent, after);
      studio.expectCount(5);
      // Undoing them all takes « Annuler » away: sent again.
      for (var trait = 0; trait < 5; trait++) {
        await studio.tap('undo');
      }
      expect(sent, greaterThan(after));
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    skip: !available,
  );
}
