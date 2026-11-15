// SPDX-License-Identifier: MIT
// Opt-in review pictures of what the pebbles wear (Color 1.2, step G3): the
// same studio in each look — « Classique », the desk, the paper, and the
// pebbles of the night of the trial universe — with what its buttons open
// and with its dialogs, which are made of the same matter. A way to LOOK at
// a dress, not a qualification: nothing moves in a picture.
//
//   COLOR_REVIEW_DIR=/absolute/output flutter test test/galets_dress_review_test.dart
//
// Without that variable the test is skipped and writes nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/options_dialog.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_printer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_printer.dart';
import 'support/memory_files.dart';
import 'support/memory_gallery.dart';
import 'support/review_fonts.dart';
import 'support/studio_driver.dart';
import 'support/trial_universes.dart';

void main() {
  final output = Platform.environment['COLOR_REVIEW_DIR'];
  final available =
      output != null && Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  const boundaryKey = ValueKey('review-boundary');
  final printer = FakePrinter()..outcome = PrintOutcome.noPrinter;

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
    required String universe,
    bool phone = false,
    StudioOptions? options,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    if (phone) {
      debugTouchFirstOverride = true;
      tester.view.display.size = size;
      addTearDown(tester.view.display.resetSize);
      addTearDown(() => debugTouchFirstOverride = null);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          gallery: MemoryGallery(),
          // The system has no printing: « Imprimer » says so in a notice.
          printer: printer.call,
          options: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    if (find.byKey(Key(key)).evaluate().isEmpty) {
      await closePebblePanel(tester);
    }
    await pressControl(tester, key);
  }

  // Lets the real engine finish what the fake clock cannot run.
  Future<void> engine(WidgetTester tester) async {
    for (var turn = 0; turn < 12; turn++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  // Closes the dialog that is open, as a press of Échap does.
  Future<void> close(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
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

  // The shadows of the pebbles as a screen shows them: a test draws them
  // as plain shapes otherwise, and must leave that as it found it.
  Future<void> shadows(Future<void> Function() body) async {
    debugDisableShadows = false;
    try {
      await body();
    } finally {
      debugDisableShadows = true;
    }
  }

  const looks = [
    ('classique', 'classique'),
    ('bureau', 'bureau'),
    ('papier', 'papier'),
    ('nuit', nightTrialKey),
  ];

  testWidgets('review pictures of the pebbles in each look', (tester) async {
    await tester.runAsync(loadReviewFonts);
    useTrialUniverses();
    await shadows(() async {
      const mac = Size(1440, 900);
      for (final (name, key) in looks) {
        await start(
          tester,
          mac,
          universe: key,
          options: StudioOptions.defaults.copyWith(grownUpColours: true),
        );
        await draw(tester);
        await shot(tester, '$name-01-atelier');
        await tap(tester, 'myDrawing');
        await shot(tester, '$name-02-mon-dessin');
        await closePebblePanel(tester);
        await tap(tester, 'galetSize');
        await shot(tester, '$name-03-taille');
        await closePebblePanel(tester);
        await tap(tester, 'galetWhich');
        await shot(tester, '$name-04-sorte-de-trait');
        await closePebblePanel(tester);
        await tester.longPress(find.byKey(const Key('color-1a1a1a')));
        await tester.pumpAndSettle();
        await shot(tester, '$name-05-nuances-du-noir');
        await closePebblePanel(tester);
        await tap(tester, 'tool-stamp');
        await tap(tester, 'galetWhich');
        await shot(tester, '$name-06-tampons');
        await closePebblePanel(tester);
        await tap(tester, 'everyColour');
        await shot(tester, '$name-07-toutes-les-couleurs');
        await closePebblePanel(tester);
        await tap(tester, 'tool-select');
        final sheet = tester.getRect(find.byKey(const Key('sheetAtRest')));
        await tester.tapAt(
          sheet.topLeft + Offset(sheet.width * .3, sheet.height * .68),
        );
        await tester.pumpAndSettle();
        await shot(tester, '$name-08-element-choisi');
        await tester.pumpWidget(const SizedBox());
      }
    });
  }, skip: !available);

  testWidgets('review pictures of the dialogs in each look', (tester) async {
    await tester.runAsync(loadReviewFonts);
    useTrialUniverses();
    await shadows(() async {
      const mac = Size(1440, 900);
      for (final (name, key) in looks) {
        await start(
          tester,
          mac,
          universe: key,
          options: StudioOptions.defaults.copyWith(grownUpColours: true),
        );
        await draw(tester);
        await tap(tester, 'openOptions');
        if (find.byKey(const Key('adultGate')).evaluate().isNotEmpty) {
          await shot(tester, '$name-19-porte-des-adultes');
          await answerAdultGate(tester);
        }
        await tester.pump(OptionsDialog.settling);
        await tester.pumpAndSettle();
        await shot(tester, '$name-20-options');
        await close(tester);
        await tap(tester, 'layersButton');
        await shot(tester, '$name-21-calques');
        await close(tester);
        await tap(tester, 'replayDrawing');
        await tester.pump(const Duration(milliseconds: 1500));
        await shot(tester, '$name-22-film');
        await close(tester);
        await tap(tester, 'morePaintColors');
        await shot(tester, '$name-23-melanger');
        await close(tester);
        await tap(tester, 'newProject');
        await engine(tester);
        await shot(tester, '$name-24-nouveau');
        await close(tester);
        await tap(tester, 'tool-text');
        final sheet = tester.getRect(find.byKey(const Key('sheetAtRest')));
        await tester.tapAt(sheet.center);
        await tester.pumpAndSettle();
        await shot(tester, '$name-25-texte');
        await close(tester);
        await tap(tester, 'showHelp');
        await shot(tester, '$name-26-aide');
        await close(tester);
        await tap(tester, 'openUniverses');
        await engine(tester);
        await shot(tester, '$name-27-univers');
        await close(tester);
        await tap(tester, 'exportImage');
        await shot(tester, '$name-28-exporter');
        await close(tester);
        await tap(tester, 'aboutColor');
        await shot(tester, '$name-29-a-propos');
        await close(tester);
        await tap(tester, 'openGallery');
        await engine(tester);
        await shot(tester, '$name-30-mes-dessins');
        await close(tester);
        // A drawing that was not saved: « Nouveau » asks what to do with it.
        await tap(tester, 'newProject');
        await engine(tester);
        await tap(tester, 'createNewSheet');
        await shot(tester, '$name-31-garder-les-modifications');
        await close(tester);
        await close(tester);
        // The notice of a problem — no printer answers a test —, over the
        // top of the sheet.
        await printAndWait(tester, printer);
        await engine(tester);
        await shot(tester, '$name-32-un-probleme');
        await tester.pumpWidget(const SizedBox());
      }
    });
  }, skip: !available);

  testWidgets('review pictures of a telephone in each look', (tester) async {
    await tester.runAsync(loadReviewFonts);
    useTrialUniverses();
    await shadows(() async {
      const iphone = Size(852, 393);
      for (final (name, key) in looks) {
        await start(tester, iphone, universe: key, phone: true);
        await tester.tapAt(
          tester.getCenter(find.byKey(const Key('sheetAtRest'))),
        );
        await tester.pumpAndSettle();
        await shot(tester, '$name-40-telephone');
        await tap(tester, 'toolDrawer');
        await shot(tester, '$name-41-telephone-tiroir');
        await closePebblePanel(tester);
        await tap(tester, 'railColour');
        await shot(tester, '$name-42-telephone-couleurs');
        await closePebblePanel(tester);
        await tap(tester, 'myDrawing');
        await shot(tester, '$name-43-telephone-mon-dessin');
        await close(tester);
        await tap(tester, 'tool-stamp');
        await tap(tester, 'toolDrawer');
        await tap(tester, 'chooseStamp');
        await shot(tester, '$name-44-telephone-tampons');
        await close(tester);
        await tester.pumpWidget(const SizedBox());
      }
    });
  }, skip: !available);
}
