// SPDX-License-Identifier: MIT
// Opt-in review pictures of the studio of the pebbles (Color 1.2, « Les
// galets »), drawn by the application's own widgets with real fonts: a way
// to LOOK at the pebbles, at what their buttons open and at the decor in
// the whole window, not a qualification. Nothing moves in a picture.
//
//   COLOR_REVIEW_DIR=/absolute/output flutter test test/galets_review_test.dart
//
// Without that variable the test is skipped and writes nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/decor_view.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'flutter_test_config.dart';
import 'support/memory_files.dart';
import 'support/memory_gallery.dart';
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

  Future<void> start(
    WidgetTester tester,
    Size size, {
    String universe = '',
    bool tablet = false,
    StudioOptions? options,
    DateTime? hour,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    if (tablet) {
      debugTouchFirstOverride = true;
      tester.view.display.size = size;
      addTearDown(tester.view.display.resetSize);
      addTearDown(() => debugTouchFirstOverride = null);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDecorNow = () => hour ?? testDecorTime;
    addTearDown(() => debugDecorNow = () => testDecorTime);
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
          // With its album: « Mes dessins » is among what « Mon dessin »
          // opens.
          gallery: MemoryGallery(),
          options: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> hold(WidgetTester tester, String key) async {
    await tester.longPress(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  // A few traits, a shape and a stamp: something on the sheet.
  Future<void> draw(WidgetTester tester) async {
    final sheet = tester.getRect(find.byKey(const Key('sheetAtRest')));
    Offset at(double x, double y) =>
        sheet.topLeft + Offset(sheet.width * x, sheet.height * y);
    Future<void> trait(List<Offset> points) async {
      final gesture = await tester.startGesture(
        points.first,
        kind: PointerDeviceKind.mouse,
      );
      for (final point in points.skip(1)) {
        await gesture.moveTo(point);
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await tap(tester, 'color-3370d1');
    await trait([
      for (var i = 0; i <= 20; i++)
        at(.12 + .3 * i / 20, .3 + .12 * (i.isEven ? 1 : -1) * (i / 20)),
    ]);
    await tap(tester, 'color-e83d48');
    await tap(tester, 'tool-shapes');
    await trait([at(.55, .2), at(.7, .35), at(.82, .5)]);
    await tap(tester, 'color-4db266');
    await tap(tester, 'tool-stamp');
    await tester.tapAt(at(.3, .68));
    await tester.pumpAndSettle();
    await tap(tester, 'color-ef9439');
    await tap(tester, 'tool-stroke');
    await trait([at(.5, .75), at(.6, .62), at(.7, .78), at(.8, .64)]);
  }

  testWidgets('review pictures of the pebbles', (tester) async {
    await tester.runAsync(loadReviewFonts);
    // The shadows of the pebbles as a screen shows them: a test draws
    // them as plain shapes otherwise.
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    const mac = Size(1440, 900);
    const ipad = Size(1366, 1024);

    await start(tester, mac);
    await shot(tester, 'galets-mac-bureau-vide');
    await draw(tester);
    await shot(tester, 'galets-mac-bureau');
    await tap(tester, 'myDrawing');
    await shot(tester, 'galets-mac-mon-dessin');
    await tap(tester, 'myDrawing');
    await tap(tester, 'galetSize');
    await shot(tester, 'galets-mac-taille');
    await tap(tester, 'galetSize');
    await tap(tester, 'galetWhich');
    await shot(tester, 'galets-mac-sorte-de-trait');
    await tap(tester, 'galetWhich');
    await hold(tester, 'color-3370d1');
    await shot(tester, 'galets-mac-nuances-du-bleu');
    await tap(tester, 'nuance-a8d8f0');
    await shot(tester, 'galets-mac-ciel-choisi');
    await tap(tester, 'tool-stamp');
    await tap(tester, 'galetWhich');
    await shot(tester, 'galets-mac-tampons');
    await tap(tester, 'galetWhich');
    await tap(tester, 'tool-shapes');
    await tap(tester, 'galetWhich');
    await shot(tester, 'galets-mac-formes');
    await tap(tester, 'galetWhich');
    await tap(tester, 'tool-select');
    final sheet = tester.getRect(find.byKey(const Key('sheetAtRest')));
    await tester.tapAt(
      sheet.topLeft + Offset(sheet.width * .3, sheet.height * .68),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'galets-mac-element-choisi');
    await tap(tester, 'bigSheet');
    await shot(tester, 'galets-mac-en-grand');
    await tester.pumpWidget(const SizedBox());

    await start(tester, mac, universe: 'papier');
    await draw(tester);
    await shot(tester, 'galets-mac-papier');
    await tester.pumpWidget(const SizedBox());

    await start(tester, mac, universe: 'classique');
    await draw(tester);
    await shot(tester, 'galets-mac-classique');
    await tester.pumpWidget(const SizedBox());

    for (final (name, size) in [
      ('1920x1080', const Size(1920, 1080)),
      ('1280x720', const Size(1280, 720)),
      ('1180x820', const Size(1180, 820)),
    ]) {
      await start(tester, size);
      await draw(tester);
      await shot(tester, 'galets-fenetre-$name');
      await tester.pumpWidget(const SizedBox());
    }

    await start(
      tester,
      mac,
      universe: 'bureau',
      options: StudioOptions.defaults.copyWith(level: InterfaceLevel.child),
    );
    await shot(tester, 'galets-mac-moyenne');
    await tester.pumpWidget(const SizedBox());

    // The same room in the morning, in the evening and at night: the
    // ground under the line is tinted as the desk is.
    for (final (name, hours) in const [
      ('matin', 8),
      ('soir', 19),
      ('nuit', 22),
    ]) {
      await start(
        tester,
        mac,
        universe: 'bureau',
        hour: DateTime(2026, 11, 12, hours, 10),
      );
      await draw(tester);
      await shot(tester, 'galets-mac-bureau-$name');
      await tester.pumpWidget(const SizedBox());
    }

    // The tablet last: what Color reads of a device that is touched first
    // stays for the rest of a program.
    await start(tester, ipad, tablet: true);
    await draw(tester);
    await shot(tester, 'galets-ipad');
    await tap(tester, 'myDrawing');
    await shot(tester, 'galets-ipad-mon-dessin');
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
  }, skip: !available);
}
