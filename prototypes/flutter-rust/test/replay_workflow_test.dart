// SPDX-License-Identifier: MIT
// « Le dessin qui se refait tout seul » in the real studio: real Rust
// documents; only native panels, disk writes and recovery are in memory.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  VoidCallback? replayButton(WidgetTester tester) => tester
      .widget<IconButton>(find.byKey(const Key('replayDrawing')))
      .onPressed;

  testWidgets('an empty sheet has no film to show', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start();
    expect(replayButton(tester), isNull);
    expect(studio.menu.onReplay, isNull);
    await studio.drag(const Offset(-80, -40), const Offset(60, 30));
    expect(replayButton(tester), isNotNull);
    expect(studio.menu.onReplay, isNotNull);
    await studio.tap('undo');
    expect(replayButton(tester), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'the film plays over the studio, changes nothing and gives the studio back',
    (tester) async {
      final handle = tester.ensureSemantics();
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1280, 800));
      await studio.drag(studio.at(200, 200), studio.at(500, 400));
      await studio.tap('tool-stamp');
      await studio.click(studio.at(800, 500));
      await studio.addText('Coucou', x: 300, y: 600);
      studio.expectCount(3);
      final before = await studio.svg();
      expect(
        find.bySemanticsLabel('Revoir ton dessin se faire tout seul'),
        findsOneWidget,
      );

      await studio.tap('replayDrawing');
      expect(find.byKey(const Key('replayDialog')), findsOneWidget);
      // While the film plays the drawing cannot be edited behind it.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      studio.menu.onUndo?.call();
      studio.menu.onReplay?.call();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('replayDialog')), findsOneWidget);
      expect(find.text('Ton dessin est fini.'), findsOneWidget);
      await studio.tap('closeReplay');
      expect(find.byKey(const Key('replayDialog')), findsNothing);
      studio.expectCount(3);
      expect(await studio.svg(), before);

      // Échap leaves the film in the middle; the studio draws again.
      await studio.tap('replayDrawing');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('replayDialog')), findsNothing);
      await studio.tap('tool-stroke');
      await studio.drag(studio.at(900, 150), studio.at(1000, 250));
      studio.expectCount(4);
      // The menu bar opens the same film.
      studio.menu.onReplay!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('replayDialog')), findsOneWidget);
      await studio.tap('closeReplay');
      handle.dispose();
      await studio.finish();
    },
    skip: !available,
  );
}
