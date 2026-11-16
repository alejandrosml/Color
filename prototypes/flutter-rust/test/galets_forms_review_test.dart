// SPDX-License-Identifier: MIT
// Opt-in review pictures of the pebbles in every window (Color 1.2, step
// G2): the line that gets shorter, the two lines of a window taller than
// wide, the rails and the drawer of a telephone and of a small window, the
// simplest interface, enlarged letters, and the colours of the older
// children. Drawn by the application's own widgets with real fonts: a way
// to LOOK, not a qualification. Nothing moves in a picture.
//
//   COLOR_REVIEW_DIR=/absolute/output flutter test test/galets_forms_review_test.dart
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

  /// [touch]: a tablet or a telephone, whose screen is [size]. [padding]:
  /// what the notch and the bars of the system keep of it.
  Future<void> start(
    WidgetTester tester,
    Size size, {
    String universe = 'classique',
    bool touch = false,
    EdgeInsets padding = EdgeInsets.zero,
    double textScale = 1,
    StudioOptions? options,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    debugTouchFirstOverride = touch;
    tester.view.display.size = touch ? size : const Size(1920, 1080);
    addTearDown(tester.view.display.resetSize);
    addTearDown(() => debugTouchFirstOverride = null);
    if (padding != EdgeInsets.zero) {
      final insets = FakeViewPadding(
        left: padding.left,
        top: padding.top,
        right: padding.right,
        bottom: padding.bottom,
      );
      tester.view.padding = insets;
      tester.view.viewPadding = insets;
    } else {
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    }
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDecorNow = () => testDecorTime;
    final store = StudioOptionsStore.memory(
      (options ?? StudioOptions.defaults).copyWith(universe: universe),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: EduPaintApp(
          files: MemoryFiles(),
          recoveryStorage: MemoryRecovery(),
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

  // A trait and a stamp: something on the sheet.
  Future<void> draw(WidgetTester tester) async {
    final sheet = tester.getRect(find.byKey(const Key('sheetAtRest')));
    Offset at(double x, double y) =>
        sheet.topLeft + Offset(sheet.width * x, sheet.height * y);
    final gesture = await tester.startGesture(
      at(.15, .35),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 20; i++) {
      await gesture.moveTo(
        at(.15 + .6 * i / 20, .35 + .2 * (i.isEven ? 1 : -1) * (i / 20)),
      );
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  const toddler = StudioOptions(level: InterfaceLevel.toddler);
  const grownUp = StudioOptions(grownUpColours: true);
  const iphone = EdgeInsets.fromLTRB(59, 0, 59, 21);

  testWidgets('review pictures of the pebbles in every window', (tester) async {
    await tester.runAsync(loadReviewFonts);
    // The shadows of the pebbles as a screen shows them: a test draws
    // them as plain shapes otherwise.
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);

    // ——— The line gets shorter ———
    await start(tester, const Size(1280, 720), universe: 'bureau');
    await draw(tester);
    await shot(tester, 'ligne-1280x720-bureau');
    await start(tester, const Size(1180, 820), touch: true);
    await draw(tester);
    await shot(tester, 'ligne-ipad-11');
    await start(tester, const Size(1100, 760));
    await draw(tester);
    await shot(tester, 'ligne-1100x760-neuf-couleurs');
    await hold(tester, 'color-1a1a1a');
    await shot(tester, 'ligne-1100x760-du-blanc-au-noir');
    await start(tester, const Size(1024, 768));
    await draw(tester);
    await shot(tester, 'ligne-1024x768-huit-couleurs');
    await hold(tester, 'color-ef9439');
    await shot(tester, 'ligne-1024x768-orange-et-marron');
    await tester.tapAt(const Offset(4, 300));
    await tester.pumpAndSettle();
    await tap(tester, 'myDrawing');
    await shot(tester, 'ligne-1024x768-mon-dessin');

    // ——— Two lines: a window taller than wide ———
    await start(tester, const Size(1024, 1366), touch: true);
    await draw(tester);
    await shot(tester, 'deux-lignes-ipad-13-en-hauteur');
    await tap(tester, 'galetWhich');
    await shot(tester, 'deux-lignes-ipad-13-lequel');
    await start(tester, const Size(744, 1133), touch: true);
    await draw(tester);
    await shot(tester, 'deux-lignes-ipad-mini-en-hauteur');
    await start(tester, const Size(700, 900));
    await draw(tester);
    await shot(tester, 'deux-lignes-fenetre-700x900');

    // ——— Rails and a drawer: a telephone, a small window ———
    await start(tester, const Size(852, 393), touch: true, padding: iphone);
    await draw(tester);
    await shot(tester, 'rails-iphone');
    await tap(tester, 'toolDrawer');
    await shot(tester, 'rails-iphone-tiroir');
    await tap(tester, 'drawer-tool-stamp');
    await tap(tester, 'toolDrawer');
    await shot(tester, 'rails-iphone-tiroir-tampon');
    await tester.tapAt(const Offset(430, 380));
    await tester.pumpAndSettle();
    await tap(tester, 'railColour');
    await shot(tester, 'rails-iphone-couleurs');
    await hold(tester, 'color-3370d1');
    await shot(tester, 'rails-iphone-nuances-du-bleu');
    await tester.tapAt(const Offset(430, 380));
    await tester.pumpAndSettle();
    await tap(tester, 'myDrawing');
    await shot(tester, 'rails-iphone-mon-dessin');
    await start(tester, const Size(640, 360), touch: true);
    await draw(tester);
    await shot(tester, 'rails-petit-telephone-640x360');
    await start(tester, const Size(680, 520));
    await draw(tester);
    await shot(tester, 'rails-fenetre-680x520');
    await tap(tester, 'toolDrawer');
    await shot(tester, 'rails-fenetre-680x520-tiroir');
    await start(tester, const Size(1000, 700));
    await draw(tester);
    await shot(tester, 'rails-fenetre-1000x700');
    await tap(tester, 'tool-select');
    // On the trait, where its tenth point lies.
    final sheet = tester.getRect(find.byKey(const Key('sheetAtRest')));
    await tester.tapAt(
      sheet.topLeft + Offset(sheet.width * .45, sheet.height * .45),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('galetSelection')), findsOneWidget);
    await shot(tester, 'rails-fenetre-1000x700-element-choisi');

    // ——— The simplest interface ———
    await start(tester, const Size(1366, 1024), touch: true, options: toddler);
    await draw(tester);
    await shot(tester, 'tout-petits-ipad-13');
    await tap(tester, 'tool-stamp');
    await tap(tester, 'galetWhich');
    await shot(tester, 'tout-petits-ipad-13-tampons');
    await start(tester, const Size(1024, 768), options: toddler);
    await draw(tester);
    await shot(tester, 'tout-petits-1024x768');
    await start(
      tester,
      const Size(852, 393),
      touch: true,
      padding: iphone,
      options: toddler,
    );
    await draw(tester);
    await shot(tester, 'tout-petits-iphone');
    await tap(tester, 'toolDrawer');
    await shot(tester, 'tout-petits-iphone-tiroir');

    // ——— Enlarged letters ———
    await start(tester, const Size(1280, 820), textScale: 2);
    await draw(tester);
    await shot(tester, 'lettres-200-1280x820');
    await tap(tester, 'myDrawing');
    await shot(tester, 'lettres-200-1280x820-mon-dessin');
    await tester.tapAt(const Offset(4, 400));
    await tester.pumpAndSettle();
    await tap(tester, 'galetWhich');
    await shot(tester, 'lettres-200-1280x820-lequel');
    await start(tester, const Size(680, 520), textScale: 2);
    await draw(tester);
    await shot(tester, 'lettres-200-680x520');
    await tap(tester, 'toolDrawer');
    await shot(tester, 'lettres-200-680x520-tiroir');

    // ——— Every colour, for the older children ———
    await start(tester, const Size(1440, 900), options: grownUp);
    await draw(tester);
    await tap(tester, 'everyColour');
    await shot(tester, 'grands-1440x900-toutes-les-couleurs');
    await start(tester, const Size(1024, 768), options: grownUp);
    await draw(tester);
    await tap(tester, 'everyColour');
    await shot(tester, 'grands-1024x768-toutes-les-couleurs');
    await start(
      tester,
      const Size(852, 393),
      touch: true,
      padding: iphone,
      options: grownUp,
    );
    await draw(tester);
    await tap(tester, 'railColour');
    await shot(tester, 'grands-iphone-couleurs');
    await tap(tester, 'everyColour');
    await shot(tester, 'grands-iphone-toutes-les-couleurs');
    await tester.pumpWidget(const SizedBox.shrink());
    debugDisableShadows = true;
  }, skip: !available);
}
