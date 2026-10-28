// SPDX-License-Identifier: MIT
// Opt-in review pictures of the real studio, drawn by the application's own
// widgets with real fonts. They are a way to LOOK at a layout, not a
// qualification: no native window, GPU, panel or screen reader is involved.
//
//   COLOR_REVIEW_DIR=/absolute/output flutter test test/visual_review_test.dart
//
// Without that variable the test is skipped and writes nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/gallery_storage.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

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
    double text = 1,
    MemoryFiles? files,
    GalleryStorage? gallery,
    StudioOptionsStore? options,
    bool phone = false,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    // A telephone's screen, that the studio fills but for the island, the
    // notch and the bar of the system.
    if (phone) {
      tester.view.display.size = size;
      addTearDown(tester.view.display.resetSize);
      final insets = FakeViewPadding(
        left: padding.left,
        top: padding.top,
        right: padding.right,
        bottom: padding.bottom,
      );
      tester.view.padding = insets;
      tester.view.viewPadding = insets;
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
    }
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: EduPaintApp(
          files: files ?? MemoryFiles(),
          recoveryStorage: MemoryRecovery(),
          gallery: gallery,
          options: options,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Lets the real engine finish what the fake clock cannot run: the card of
  // a save, or the decoding of the pictures of a dialog.
  Future<void> engine(WidgetTester tester, [bool Function()? done]) async {
    for (var turn = 0; turn < 200; turn++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (done == null ? turn >= 12 : done()) break;
    }
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final control = find.byKey(Key(key));
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
    final center = tester.getCenter(find.byKey(const Key('drawingSurface')));
    final gesture = await tester.startGesture(center + from);
    await gesture.moveTo(center + (from + to) / 2);
    await gesture.moveTo(center + to);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> click(WidgetTester tester, Offset at) async {
    final center = tester.getCenter(find.byKey(const Key('drawingSurface')));
    await tester.tapAt(center + at);
    await tester.pumpAndSettle();
  }

  testWidgets('review pictures of text, stamps and layers', (tester) async {
    debugDisableShadows = false;
    try {
      await tester.runAsync(loadReviewFonts);
      await start(tester, const Size(1280, 820));
      await shot(tester, '01-atelier-vide');

      await tap(tester, 'tool-stroke');
      await drag(tester, const Offset(-180, 100), const Offset(-60, 40));
      await tap(tester, 'tool-rectangle');
      await drag(tester, const Offset(-185, 20), const Offset(-110, 80));

      await tap(tester, 'tool-stamp');
      await shot(tester, '02-outil-tampon');
      await tap(tester, 'chooseStamp');
      await shot(tester, '03-choix-du-tampon');
      await tap(tester, 'stamp-soleil');
      await tap(tester, 'color-eebf4e');
      await click(tester, const Offset(150, -85));
      await tap(tester, 'chooseStamp');
      await tap(tester, 'stamp-chat');
      await tap(tester, 'color-477fb2');
      await tap(tester, 'size-large');
      await click(tester, const Offset(40, 50));
      await tap(tester, 'chooseStamp');
      await tap(tester, 'stamp-fleur');
      await tap(tester, 'color-c96d93');
      await drag(tester, const Offset(120, 30), const Offset(180, 90));

      await tap(tester, 'tool-text');
      await shot(tester, '04-outil-texte');
      await click(tester, const Offset(-180, -110));
      await shot(tester, '05-dialogue-texte-vide');
      await tester.enterText(
        find.byKey(const Key('textField')),
        'Mon chat Câlin\net son soleil',
      );
      await tester.pumpAndSettle();
      await shot(tester, '06-dialogue-texte-rempli');
      await tap(tester, 'confirmText');
      await shot(tester, '07-dessin-avec-texte-et-tampons');

      await tap(tester, 'layersButton');
      await shot(tester, '08-calques-un-seul');
      await tap(tester, 'addLayer');
      await tap(tester, 'addLayer');
      await shot(tester, '09-calques-trois');
      await tap(tester, 'layer-visible-0');
      await shot(tester, '10-calques-premier-cache');
      await tap(tester, 'closeLayers');
      await shot(tester, '11-dessin-calque-cache');
      await tap(tester, 'layersButton');
      await tap(tester, 'layer-visible-0');
      await tap(tester, 'closeLayers');

      await tap(tester, 'tool-select');
      await click(tester, const Offset(-150, -95));
      await shot(tester, '12-texte-choisi');
      await tap(tester, 'editSelectionText');
      await shot(tester, '13-modifier-le-texte');
      await tap(tester, 'cancelText');
      await tester.tap(find.byKey(const Key('selectionOrder')));
      await tester.pumpAndSettle();
      await shot(tester, '14-menu-ordre-avec-calques');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // Narrow window: the tools become a row above the sheet.
      tester.view.physicalSize = const Size(700, 620);
      await tester.pumpAndSettle();
      await shot(tester, '15-fenetre-etroite');
      await tap(tester, 'tool-stamp');
      await shot(tester, '16-fenetre-etroite-tampon');
      tester.view.physicalSize = const Size(1280, 560);
      await tester.pumpAndSettle();
      await shot(tester, '17-fenetre-basse');
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDisableShadows = true;
    }
  }, skip: !available);

  testWidgets('review pictures of the new tools', (tester) async {
    debugDisableShadows = false;
    try {
      await tester.runAsync(loadReviewFonts);
      await start(tester, const Size(1280, 900));
      await shot(tester, '30-outils-une-colonne');
      await tap(tester, 'tool-rectangle');
      await drag(tester, const Offset(-200, -80), const Offset(-60, 40));
      await tap(tester, 'tool-ellipse');
      await drag(tester, const Offset(20, -60), const Offset(180, 60));
      await tap(tester, 'tool-stamp');
      await click(tester, const Offset(-120, 90));
      await tap(tester, 'tool-fill');
      await shot(tester, '31-outil-remplir');
      await tap(tester, 'color-eebf4e');
      await click(tester, const Offset(-130, -20));
      await tap(tester, 'color-a8d8f0'.replaceAll('a8d8f0', '9385bc'));
      await click(tester, const Offset(100, 0));
      await tap(tester, 'color-e69976');
      await click(tester, const Offset(230, -120));
      await shot(tester, '32-formes-remplies-et-feuille-coloriee');
      await tap(tester, 'tool-eraser');
      await shot(tester, '33-outil-gomme');
      await click(tester, const Offset(-120, 90));
      await shot(tester, '34-tampon-efface');
      await tap(tester, 'pickPaintColor');
      await shot(tester, '35-pipette-armee');
      await click(tester, const Offset(100, 0));
      await shot(tester, '36-couleur-reprise');
      await tap(tester, 'tool-select');
      await click(tester, const Offset(-130, -20));
      await shot(tester, '37-element-choisi-plus-grand-plus-petit');
      await tap(tester, 'growSelection');
      await tap(tester, 'growSelection');
      await shot(tester, '38-element-agrandi');
      await tap(tester, 'showHelp');
      await shot(tester, '39-comment-faire');
      await tap(tester, 'closeHelp');
      await tap(tester, 'bigSheet');
      await shot(tester, '40-dessiner-en-grand');
      await tap(tester, 'bigSheet');

      tester.view.physicalSize = const Size(1100, 760);
      await tester.pumpAndSettle();
      await shot(tester, '41-outils-deux-colonnes');
      tester.view.physicalSize = const Size(700, 620);
      await tester.pumpAndSettle();
      await shot(tester, '42-fenetre-etroite-outils');
      await tap(tester, 'bigSheet');
      await shot(tester, '43-fenetre-etroite-en-grand');
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDisableShadows = true;
    }
  }, skip: !available);

  testWidgets('review pictures of the gallery', (tester) async {
    debugDisableShadows = false;
    try {
      await tester.runAsync(loadReviewFonts);
      final gallery = MemoryGallery();
      final files = MemoryFiles();
      await start(
        tester,
        const Size(1280, 820),
        files: files,
        gallery: gallery,
      );
      await shot(tester, '50-atelier-avec-mes-dessins');
      await tap(tester, 'openGallery');
      await shot(tester, '51-mes-dessins-vide');
      await tap(tester, 'closeGallery');

      // Three drawings saved one after another, each under its own name.
      await tap(tester, 'tool-stamp');
      await tap(tester, 'chooseStamp');
      await tap(tester, 'stamp-soleil');
      await tap(tester, 'color-eebf4e');
      await tap(tester, 'size-large');
      await click(tester, const Offset(110, -70));
      await tap(tester, 'tool-rectangle');
      await tap(tester, 'color-388778');
      await tap(tester, 'paint-target-fill');
      await tap(tester, 'color-78a66f');
      await drag(tester, const Offset(-190, 60), const Offset(190, 125));
      files.savePath = '/dessins/Jardin.edupaint';
      await tap(tester, 'saveProject');
      await engine(tester, () => gallery.rememberCalls >= 1);

      await tap(tester, 'newProject');
      await tap(tester, 'newSheet-portrait');
      await tap(tester, 'createNewSheet');
      await tap(tester, 'tool-fill');
      await tap(tester, 'color-477fb2');
      await click(tester, Offset.zero);
      await tap(tester, 'tool-stamp');
      await tap(tester, 'chooseStamp');
      await tap(tester, 'stamp-chat');
      await tap(tester, 'color-33484d');
      await click(tester, const Offset(0, 20));
      files.savePath = '/dessins/Mon chat Câlin.edupaint';
      await tap(tester, 'saveProject');
      await engine(tester, () => gallery.rememberCalls >= 2);

      await tap(tester, 'newProject');
      await tap(tester, 'newSheet-landscape');
      await tap(tester, 'createNewSheet');
      await tap(tester, 'tool-ellipse');
      await tap(tester, 'color-d75e56');
      await tap(tester, 'paint-target-fill');
      await tap(tester, 'color-e69976');
      await drag(tester, const Offset(-120, -60), const Offset(120, 80));
      files.savePath =
          '/dessins/Un très grand ballon rouge pour la fête.edupaint';
      await tap(tester, 'saveProject');
      await engine(tester, () => gallery.rememberCalls >= 3);

      // Older cards, so that the three ways of saying a moment are seen.
      final cards = gallery.entries;
      Future<void> age(String name, DateTime savedAt) async {
        final card = cards.firstWhere((entry) => entry.name == name);
        await gallery.remember(
          sourcePath: card.sourcePath,
          name: card.name,
          project: gallery.copyOf(card)!,
          thumbnailPng: gallery.thumbnailOf(card)!,
          width: card.width,
          height: card.height,
          elementCount: card.elementCount,
          savedAt: savedAt,
        );
      }

      final now = DateTime.now();
      await age(
        'Mon chat Câlin.edupaint',
        DateTime(now.year, now.month, now.day - 1, 17, 40),
      );
      await age('Jardin.edupaint', DateTime(now.year, now.month - 1, 12, 9, 5));

      await tap(tester, 'openGallery');
      await engine(tester);
      await shot(tester, '52-mes-dessins-trois-cartes');
      final cat = GalleryStorage.idFor('/dessins/Mon chat Câlin.edupaint');
      await tap(tester, 'gallery-forget-$cat');
      await shot(tester, '53-retirer-une-carte');
      await tap(tester, 'cancelGalleryForget');
      await tap(tester, 'closeGallery');

      // The top bar at other widths: one line when everything fits.
      for (final width in const [1180.0, 1100.0, 1000.0, 860.0]) {
        tester.view.physicalSize = Size(width, 760);
        await tester.pumpAndSettle();
        await shot(tester, '54-barre-du-haut-${width.round()}');
      }
      tester.view.physicalSize = const Size(700, 620);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('moreFileActions')));
      await tester.pumpAndSettle();
      await shot(tester, '55-fenetre-etroite-menu');
      await tester.tap(find.byKey(const Key('openGallery')));
      await tester.pumpAndSettle();
      await engine(tester);
      await shot(tester, '56-fenetre-etroite-mes-dessins');
      await tap(tester, 'closeGallery');
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDisableShadows = true;
    }
  }, skip: !available);

  testWidgets('review pictures of window sizes', (tester) async {
    debugDisableShadows = false;
    try {
      await tester.runAsync(loadReviewFonts);
      await start(
        tester,
        const Size(1280, 820),
        files: MemoryFiles(),
        gallery: MemoryGallery(),
      );
      await tap(tester, 'tool-stamp');
      await click(tester, const Offset(40, 20));
      // The rainbow, small and large: four bows, no cloud at their feet.
      await tap(tester, 'chooseStamp');
      await tap(tester, 'stamp-arcenciel');
      await click(tester, const Offset(150, -70));
      await drag(tester, const Offset(90, 10), const Offset(210, 110));
      await tap(tester, 'tool-rectangle');
      await drag(tester, const Offset(-150, -60), const Offset(-40, 30));
      for (final size in const [
        // The row of colours takes more of them as the window widens.
        Size(2200, 1100),
        Size(1728, 1000),
        Size(1512, 900),
        Size(1280, 820),
        Size(1280, 720),
        Size(1280, 620),
        Size(1280, 560),
        Size(1000, 700),
        Size(1000, 600),
        Size(760, 760),
        Size(760, 580),
        Size(760, 540),
        Size(680, 520),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        await shot(
          tester,
          '60-fenetre-${size.width.round()}x${size.height.round()}',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDisableShadows = true;
    }
  }, skip: !available);

  testWidgets('review pictures with enlarged text', (tester) async {
    debugDisableShadows = false;
    try {
      await tester.runAsync(loadReviewFonts);
      await start(tester, const Size(1000, 700), text: 2);
      await tap(tester, 'tool-text');
      await shot(tester, '20-texte-200-atelier');
      await click(tester, const Offset(-40, -20));
      await shot(tester, '21-texte-200-dialogue');
      await tap(tester, 'cancelText');
      await tap(tester, 'tool-stamp');
      await tap(tester, 'chooseStamp');
      await shot(tester, '22-texte-200-tampons');
      await tap(tester, 'cancelStamp');
      await tap(tester, 'layersButton');
      await tap(tester, 'addLayer');
      await shot(tester, '23-texte-200-calques');
      await tap(tester, 'closeLayers');
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDisableShadows = true;
    }
  }, skip: !available);

  testWidgets('review pictures of the options and of the three interfaces', (
    tester,
  ) async {
    debugDisableShadows = false;
    try {
      await tester.runAsync(loadReviewFonts);
      final store = StudioOptionsStore.memory();
      addTearDown(store.dispose);
      await start(
        tester,
        const Size(1280, 800),
        gallery: MemoryGallery(),
        options: store,
      );
      await drag(tester, const Offset(-220, -120), const Offset(-40, 60));
      await tap(tester, 'tool-stamp');
      await click(tester, const Offset(140, 20));
      await tap(tester, 'tool-stroke');
      await shot(tester, '30-options-interface-complete');
      // The calculation at the door is an option, off by default.
      await store.change(store.value.copyWith(guarded: true));
      await tester.pumpAndSettle();
      await tap(tester, 'openOptions');
      await shot(tester, '31-options-le-calcul');
      final question = tester
          .widget<Text>(find.byKey(const Key('adultGateQuestion')))
          .data!;
      final numbers = RegExp(r'\d').allMatches(question).toList();
      final answer = int.parse(numbers[0][0]!) * int.parse(numbers[1][0]!);
      for (final digit in '$answer'.split('')) {
        await tap(tester, 'adultGateDigit$digit');
      }
      await shot(tester, '32-options-le-calcul-repondu');
      await tap(tester, 'adultGateEnter');
      await tester.pump(const Duration(milliseconds: 450));
      await shot(tester, '33-options-le-dialogue');
      await tap(tester, 'level-child');
      await tap(tester, 'closeOptions');
      await shot(tester, '34-options-interface-enfants');
      await store.change(store.value.copyWith(level: InterfaceLevel.toddler));
      await tester.pumpAndSettle();
      await shot(tester, '35-options-interface-tout-petits');
      await tap(tester, 'tool-stamp');
      await shot(tester, '36-options-tout-petits-tampon');
      await tester.pumpWidget(const SizedBox.shrink());
      for (final size in const [Size(680, 520), Size(1000, 700)]) {
        await start(tester, size, gallery: MemoryGallery(), options: store);
        await shot(
          tester,
          '37-options-tout-petits-${size.width.toInt()}x${size.height.toInt()}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
      // The keys to click of the text dialog, in a large and a small window.
      await store.change(
        const StudioOptions(level: InterfaceLevel.child, screenKeyboard: true),
      );
      for (final size in const [Size(1280, 800), Size(680, 520)]) {
        final name = '${size.width.toInt()}x${size.height.toInt()}';
        await start(tester, size, gallery: MemoryGallery(), options: store);
        await tap(tester, 'tool-text');
        await click(tester, Offset.zero);
        await shot(tester, '38-options-clavier-lettres-$name');
        await tap(tester, 'key-capitals');
        await tap(tester, 'key-L');
        await tap(tester, 'keys-accents');
        await tap(tester, 'key-é');
        await shot(tester, '39-options-clavier-accents-$name');
        await tap(tester, 'keys-signs');
        await tap(tester, 'key-♥');
        await shot(tester, '40-options-clavier-signes-$name');
        await tap(tester, 'cancelText');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    } finally {
      debugDisableShadows = true;
    }
  }, skip: !available);

  testWidgets('review pictures of a telephone on its side', (tester) async {
    debugDisableShadows = false;
    debugTouchFirstOverride = true;
    try {
      await tester.runAsync(loadReviewFonts);
      for (final (name, size, insets) in const [
        ('iphone', Size(852, 393), EdgeInsets.fromLTRB(59, 0, 59, 21)),
        ('android', Size(915, 412), EdgeInsets.zero),
        ('petit-android', Size(640, 360), EdgeInsets.zero),
      ]) {
        final store = StudioOptionsStore.memory();
        addTearDown(store.dispose);
        await start(
          tester,
          size,
          gallery: MemoryGallery(),
          options: store,
          phone: true,
          padding: insets,
        );
        await shot(tester, '70-$name-atelier-vide');
        await drag(tester, const Offset(-150, -70), const Offset(-40, 50));
        await tap(tester, 'tool-rectangle');
        await tap(tester, 'fillShapeCheckbox');
        await drag(tester, const Offset(-20, -60), const Offset(70, 20));
        await shot(tester, '71-$name-rectangle');
        await tap(tester, 'tool-stamp');
        await tap(tester, 'size-large');
        await click(tester, const Offset(110, 40));
        await shot(tester, '72-$name-tampon');
        await tap(tester, 'tool-select');
        await click(tester, const Offset(110, 40));
        await shot(tester, '73-$name-choisir');
        await tap(tester, 'phoneMenu');
        await shot(tester, '74-$name-menu');
        await tap(tester, 'closePhoneMenu');
        await tap(tester, 'tool-text');
        await click(tester, const Offset(-60, 80));
        await shot(tester, '75-$name-dialogue-texte');
        await tap(tester, 'cancelText');
        await tap(tester, 'tool-stroke');
        final scroll = find.descendant(
          of: find.byKey(const Key('phoneSideRail')),
          matching: find.byType(Scrollable),
        );
        await tester.drag(scroll, const Offset(0, -260));
        await tester.pumpAndSettle();
        await shot(tester, '76-$name-colonne-defilee');
        await tester.pumpWidget(const SizedBox.shrink());
        for (final level in [InterfaceLevel.child, InterfaceLevel.toddler]) {
          await store.change(store.value.copyWith(level: level));
          await start(
            tester,
            size,
            gallery: MemoryGallery(),
            options: store,
            phone: true,
            padding: insets,
          );
          await drag(tester, const Offset(-150, -70), const Offset(-40, 50));
          await shot(tester, '77-$name-interface-${level.code}');
          await tap(tester, 'phoneMenu');
          await shot(tester, '78-$name-menu-${level.code}');
          await tap(tester, 'closePhoneMenu');
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    } finally {
      debugDisableShadows = true;
      debugTouchFirstOverride = null;
    }
  }, skip: !available);
}
