// SPDX-License-Identifier: MIT
// Color — Alejandro San Martin Lamas — https://github.com/alejandrosml
//
// What happens around a trait that is being drawn (étape 7 of Color 1.2):
// the universe changes, the window changes size, the calm of the system
// comes, the hour goes back, another finger opens the dialogue of the
// universes. The trait is never lost, nothing throws, and the studio
// answers afterwards.
import 'dart:io';

import 'package:edupaint_flutter_study/decor_view.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/studio_colors.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/universe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  final surface = find.byKey(const Key('drawingSurface'));

  Future<StudioOptionsStore> start(
    WidgetTester tester, {
    DateTime Function()? clock,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = StudioOptionsStore.memory(StudioOptions.defaults);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      EduPaintApp(
        files: MemoryFiles(),
        recoveryStorage: MemoryRecovery(),
        options: store,
        clock: clock,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return store;
  }

  testWidgets(
    'while a trait is drawn: the universe changes, then the window, then '
    'the calm of the system — the trait is whole, and the next one too',
    (tester) async {
      final store = await start(tester);
      expect(drawingCaption(tester), contains('0 élément'));
      final centre = tester.getCenter(surface);
      final gesture = await tester.startGesture(centre);
      await gesture.moveBy(const Offset(30, 10));
      await tester.pump();
      // Another universe, as the options of another window would write it.
      for (final universe in UniverseCatalog.instance.universes) {
        await store.change(store.value.copyWith(universe: universe.key));
        await tester.pump();
        await gesture.moveBy(const Offset(4, 3));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: universe.key);
        expect(studioLook.value, universe.look, reason: universe.key);
      }
      // The window becomes small, then tall, then large again.
      for (final size in const [
        Size(700, 500),
        Size(500, 900),
        Size(1440, 900),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();
        await gesture.moveBy(const Offset(-3, 2));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$size');
      }
      // The system asks for less motion, then no longer.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(5, 5));
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(drawingCaption(tester), contains('1 élément'));
      // The studio answers: another trait, and « Annuler » takes it back.
      await tester.dragFrom(
        tester.getCenter(surface) + const Offset(0, 80),
        const Offset(60, 20),
      );
      await tester.pump();
      expect(drawingCaption(tester), contains('2 éléments'));
      await tester.pumpWidget(const SizedBox());
    },
    skip: !available,
  );

  testWidgets(
    'another finger opens the universes while one draws: the trait is not '
    'lost, and the universe chosen is worn',
    (tester) async {
      final store = await start(tester);
      final centre = tester.getCenter(surface);
      final first = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.touch,
        pointer: 11,
      );
      await first.moveBy(const Offset(40, 12));
      await tester.pump();
      // The second finger presses « Univers ».
      final second = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('openUniverses'))),
        kind: PointerDeviceKind.touch,
        pointer: 12,
      );
      await tester.pump();
      await second.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      final dialog = find.byKey(const Key('universeDialog'));
      if (dialog.evaluate().isNotEmpty) {
        // The dialogue is open over a trait that is still held.
        await first.moveBy(const Offset(10, 10));
        await tester.pump();
        await tester.tap(find.byKey(const Key('universe-papier')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(store.value.universe, 'papier');
      }
      await first.moveBy(const Offset(6, 6));
      await first.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('universeDialog')), findsNothing);
      // What was drawn before the second finger is kept, in one piece.
      expect(drawingCaption(tester), contains('1 élément'));
      // And the studio answers.
      await tester.dragFrom(
        tester.getCenter(surface) + const Offset(0, 90),
        const Offset(60, 20),
      );
      await tester.pump();
      expect(drawingCaption(tester), contains('2 éléments'));
      await tester.pumpWidget(const SizedBox());
    },
    skip: !available,
  );

  testWidgets(
    'midnight, an hour that goes back, a long sleep: the decor follows the '
    'clock it is given, whichever way it goes',
    (tester) async {
      var now = DateTime(2026, 10, 24, 23, 59, 40);
      debugDecorNow = null;
      await start(tester, clock: () => now);
      final decor = find.byKey(const Key('decor'));
      expect(decor, findsOneWidget);
      for (final next in [
        DateTime(2026, 10, 25, 0, 0, 20), // midnight
        DateTime(2026, 10, 25, 2, 59, 59), // the night the hour changes
        DateTime(2026, 10, 25, 2, 0, 0), // … and goes back
        DateTime(2026, 10, 25, 14, 30), // the day
        DateTime(2026, 10, 24, 8, 0), // a clock set back a day
        DateTime(2031, 1, 1, 19, 30), // asleep for years
        DateTime(1970, 1, 1, 0, 0), // a device without its clock
      ]) {
        now = next;
        await tester.pump(const Duration(minutes: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: '$next');
      }
      // Hidden for a long time, then back in front.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(hours: 9));
      now = DateTime(2026, 10, 26, 7, 15);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      // The studio answers.
      await tester.dragFrom(tester.getCenter(surface), const Offset(60, 20));
      await tester.pump();
      expect(drawingCaption(tester), contains('1 élément'));
      await tester.pumpWidget(const SizedBox());
    },
    skip: !available,
  );
}
