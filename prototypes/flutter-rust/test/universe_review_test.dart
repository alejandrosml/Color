// SPDX-License-Identifier: MIT
// Opt-in review pictures of the universes of the studio (Color 1.2), drawn
// by the application's own widgets with real fonts: a way to LOOK at a
// decor in a window of some size at some hour, around the sheet and on the
// whole screen, not a qualification. Nothing moves in a picture: the
// movement is not judged here.
//
//   COLOR_REVIEW_DIR=/absolute/output flutter test test/universe_review_test.dart
//
// Without that variable the test is skipped and writes nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/decor.dart';
import 'package:edupaint_flutter_study/decor_gaze.dart';
import 'package:edupaint_flutter_study/decor_motion.dart';
import 'package:edupaint_flutter_study/decor_view.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/universe.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'flutter_test_config.dart';
import 'support/memory_files.dart';
import 'support/review_fonts.dart';

void main() {
  final output = Platform.environment['COLOR_REVIEW_DIR'];
  final available =
      output != null && Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  const boundaryKey = ValueKey('review-boundary');

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<StudioOptionsStore> start(
    WidgetTester tester,
    Size size, {
    String universe = '',
    DateTime? time,
    // A device held in the hand: its screen is the size of its window.
    bool phone = false,
    StudioOptions? options,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    if (phone) {
      tester.view.display.size = size;
      addTearDown(tester.view.display.resetSize);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hour = time ?? testDecorTime;
    debugDecorNow = () => hour;
    final store = StudioOptionsStore.memory(
      (options ?? StudioOptions.defaults).copyWith(universe: universe),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: EduPaintApp(
          files: MemoryFiles(),
          recoveryStorage: MemoryRecovery(),
          options: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('review pictures of the universes', (tester) async {
    await tester.runAsync(loadReviewFonts);
    const mac = Size(1440, 900);
    // The desk by the window, at the four moments of its day.
    for (final (name, hour, minute) in [
      ('matin', 8, 0),
      ('jour', 14, 30),
      ('soir', 19, 30),
      ('nuit', 22, 10),
    ]) {
      await start(tester, mac, time: DateTime(2026, 11, 12, hour, minute));
      await shot(tester, 'univers-bureau-$name');
      await tester.pumpWidget(const SizedBox());
    }
    await start(tester, mac, universe: 'papier');
    await shot(tester, 'univers-papier');
    await tester.pumpWidget(const SizedBox());
    // Windows of other sizes: the decor keeps to the edges, or is made
    // smaller, or is not shown at all.
    for (final (name, size) in [
      ('large-1920x1080', const Size(1920, 1080)),
      ('portable-1280x720', const Size(1280, 720)),
      ('etroit-1024x768', const Size(1024, 768)),
      ('haut-900x1000', const Size(900, 1000)),
    ]) {
      for (final universe in ['bureau', 'papier']) {
        await start(tester, size, universe: universe);
        await shot(tester, 'fenetre-$universe-$name');
        await tester.pumpWidget(const SizedBox());
      }
    }
    // A card of the decor, and the choice of the universe.
    await start(tester, mac);
    final surface = tester.getTopLeft(find.byKey(const Key('drawingSurface')));
    final frame = tester.getSize(find.byKey(const Key('drawingSurface')));
    final cat = surface + Offset(frame.width - 70, frame.height - 80);
    await tester.tapAt(cat);
    await tester.tapAt(cat);
    await tester.pump();
    await shot(tester, 'fiche-du-chat');
    await tester.tap(find.byKey(const Key('decorNameCard')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('openUniverses')));
    await tester.pumpAndSettle();
    await shot(tester, 'choisis-ton-univers');
    await tester.tap(find.byKey(const Key('universe-papier')));
    await tester.pumpAndSettle();
    await shot(tester, 'apres-le-choix-du-papier');
    await tester.tap(find.byKey(const Key('openOptions')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.byKey(const Key('optionDecorNames')));
    await tester.pumpAndSettle();
    await shot(tester, 'options-univers-et-effets');
    await tester.pumpWidget(const SizedBox());
    // A telephone on its side, and two tablets: no decor around the sheet,
    // whatever their size. Nobody chose: « Classique »; then the paper,
    // whose colours and shapes the studio wears.
    debugTouchFirstOverride = true;
    addTearDown(() => debugTouchFirstOverride = null);
    await start(tester, const Size(844, 390), phone: true);
    await shot(tester, 'telephone-classique');
    await tester.pumpWidget(const SizedBox());
    await start(tester, const Size(1180, 820), phone: true);
    await shot(tester, 'tablette-11-classique');
    await tester.pumpWidget(const SizedBox());
    await start(
      tester,
      const Size(1366, 1024),
      universe: 'papier',
      phone: true,
    );
    await shot(tester, 'tablette-13-papier');
    // « Choisis ton univers » on the tablet, with « Regarder » under the
    // universes that have a decor; then the decor, opened from there.
    await tester.tap(find.byKey(const Key('openUniverses')));
    await tester.pumpAndSettle();
    await shot(tester, 'tablette-13-choisis-ton-univers');
    await tester.tap(find.byKey(const Key('watch-bureau')));
    await tester.pumpAndSettle();
    await shot(tester, 'tablette-13-regarder-depuis-l-atelier');
    await tester.pumpWidget(const SizedBox());
  }, skip: !available);

  // A decor that is looked at without a sheet, on the whole screen (« les
  // décors à contempler »): on a tablet, a telephone and a computer, held
  // either way. The telephone has what its screen hides at the edges.
  testWidgets('review pictures of the decors that are looked at', (
    tester,
  ) async {
    await tester.runAsync(loadReviewFonts);
    final catalog = UniverseCatalog.instance;
    Future<void> gaze(
      String name,
      Size size, {
      String universe = 'bureau',
      FakeViewPadding padding = FakeViewPadding.zero,
      DecorGazeArrangement? arrangement,
      DateTime? time,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.viewPadding = padding;
      tester.view.padding = padding;
      addTearDown(tester.view.reset);
      final hour = time ?? testDecorTime;
      debugDecorNow = () => hour;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: DecorGaze(
              key: ValueKey(name),
              universe: catalog.named(universe),
              motion: DecorMotion.low,
              names: true,
              arrangement: arrangement,
            ),
          ),
        ),
      );
      await tester.pump();
      await shot(tester, 'regarder-$name');
    }

    const notchSide = FakeViewPadding(left: 47, right: 47, bottom: 21);
    const notchTop = FakeViewPadding(top: 47, bottom: 34);
    for (final universe in ['bureau', 'papier']) {
      await gaze(
        '$universe-tablette-13-largeur',
        const Size(1366, 1024),
        universe: universe,
      );
      await gaze(
        '$universe-tablette-13-hauteur',
        const Size(1024, 1366),
        universe: universe,
      );
      await gaze(
        '$universe-tablette-11-largeur',
        const Size(1180, 820),
        universe: universe,
      );
      await gaze(
        '$universe-telephone-largeur',
        const Size(844, 390),
        universe: universe,
        padding: notchSide,
      );
      await gaze(
        '$universe-telephone-hauteur',
        const Size(390, 844),
        universe: universe,
        padding: notchTop,
      );
      await gaze(
        '$universe-mac-1440x900',
        const Size(1440, 900),
        universe: universe,
      );
      await gaze(
        '$universe-ecran-1920x1080',
        const Size(1920, 1080),
        universe: universe,
      );
    }
    // The other way to hold a telephone upright, to compare: the two sides
    // side by side at the bottom of the screen.
    await gaze(
      'bureau-telephone-hauteur-cote-a-cote',
      const Size(390, 844),
      padding: notchTop,
      arrangement: DecorGazeArrangement.beside,
    );
    // The night, and a card: one press on the cat.
    await gaze(
      'bureau-tablette-13-nuit',
      const Size(1366, 1024),
      time: DateTime(2026, 11, 12, 22, 10),
    );
    await gaze('bureau-tablette-11-fiche', const Size(1180, 820));
    await tester.tapAt(const Offset(1180 - 140, 820 - 150));
    await tester.pump();
    await shot(tester, 'regarder-bureau-tablette-11-fiche');
    // The button faded: what the child looks at after a few seconds.
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, 'regarder-bureau-tablette-11-sans-bouton');
  }, skip: !available);
}
