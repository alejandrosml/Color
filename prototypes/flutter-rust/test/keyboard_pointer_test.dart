// SPDX-License-Identifier: MIT
// « Pointeur au clavier ou à la manette » (Color 1.1): the arrows move a
// pointer on the sheet, Entrée or the button A of a gamepad presses and
// releases it; a trait is drawn so, and an element chosen and moved. Real
// Rust documents; only dialogs' destinations and storage are in memory.
import 'dart:io';

import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, [
    int times = 1,
  ]) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('the arrows and Entrée draw a trait, then move it', (
    tester,
  ) async {
    final studio = StudioDriver(
      tester,
      options: StudioOptionsStore.memory(
        const StudioOptions(keyboardPointer: true),
      ),
    );
    await studio.start();
    final scale = studio.at(1, 0).dx - studio.at(0, 0).dx;
    // The pointer appears at the middle of the sheet's frame.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byKey(const Key('keyPointer')), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.arrowRight, 10);
    await press(tester, LogicalKeyboardKey.gameButtonA);
    studio.expectCount(1);
    var document = await studio.saved();
    final double startX;
    try {
      final trait = document.strokes.single;
      startX = trait.points.first.x;
      expect(trait.points.last.x - startX, closeTo(100 / scale, 1));
      expect(trait.points.last.y, closeTo(trait.points.first.y, .5));
    } finally {
      document.dispose();
    }
    // Choisir: pressed on the trait, three steps down, released.
    await studio.tap('tool-select');
    await press(tester, LogicalKeyboardKey.arrowLeft, 5);
    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.arrowDown, 3);
    await press(tester, LogicalKeyboardKey.enter);
    document = await studio.saved();
    try {
      final moved = document.strokes.single;
      expect(moved.points.first.x, closeTo(startX, 1));
      expect(moved.points.first.y - 400, closeTo(30 / scale, 2));
    } finally {
      document.dispose();
    }
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('without the option the arrows still nudge the chosen element', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.drag(studio.at(300, 300), studio.at(500, 300));
    await studio.tap('tool-select');
    await studio.click(studio.at(400, 300));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byKey(const Key('keyPointer')), findsNothing);
    final document = await studio.saved();
    try {
      expect(document.strokes.single.points.first.y, closeTo(301, .5));
    } finally {
      document.dispose();
    }
    await studio.finish();
  }, skip: !available);
}
