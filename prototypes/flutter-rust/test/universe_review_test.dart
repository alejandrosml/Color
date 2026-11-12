// SPDX-License-Identifier: MIT
// Opt-in review pictures of the universes of the studio (Color 1.2), drawn
// by the application's own widgets with real fonts: a way to LOOK at a
// decor in a window of some size at some hour, not a qualification. Nothing
// moves in a picture: the movement is not judged here.
//
//   COLOR_REVIEW_DIR=/absolute/output flutter test test/universe_review_test.dart
//
// Without that variable the test is skipped and writes nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/decor_view.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
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
    // smaller, or leaves its ground alone.
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
    // A telephone on its side, and a tablet.
    debugTouchFirstOverride = true;
    addTearDown(() => debugTouchFirstOverride = null);
    await start(tester, const Size(844, 390), phone: true);
    await shot(tester, 'telephone-bureau');
    await tester.pumpWidget(const SizedBox());
    await start(tester, const Size(1180, 820), phone: true);
    await shot(tester, 'tablette-bureau');
  }, skip: !available);
}
