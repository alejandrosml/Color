// SPDX-License-Identifier: MIT
// « Les galets » (Color 1.2): the studio of a wide window, with real Rust
// documents; only native panels, disk writes and recovery are in memory.
// Two pebbles at the top, one line at the bottom, what a button opens beside
// it; the decor of the universe in the whole window.
import 'dart:io';

import 'package:edupaint_flutter_study/decor.dart';
import 'package:edupaint_flutter_study/decor_motion.dart';
import 'package:edupaint_flutter_study/decor_view.dart';
import 'package:edupaint_flutter_study/galets.dart';
import 'package:edupaint_flutter_study/language.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_colors.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_tool.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_gallery.dart';
import 'support/review_fonts.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  const mac = Size(1440, 900);
  const ipad = Size(1366, 1024);

  Finder key(String name) => find.byKey(Key(name));

  // A studio on a tablet: touched first, on a screen of its own size.
  Future<StudioDriver> tablet(
    WidgetTester tester, {
    Size size = ipad,
    StudioOptionsStore? options,
  }) async {
    debugTouchFirstOverride = true;
    addTearDown(() => debugTouchFirstOverride = null);
    tester.view.display.size = size;
    addTearDown(tester.view.display.resetSize);
    final studio = StudioDriver(tester, options: options);
    await studio.start(size: size);
    return studio;
  }

  Rect sheet(WidgetTester tester) => tester.getRect(key('sheetAtRest'));

  testWidgets('a wide window is the studio of the pebbles; the others keep '
      'the studio of before', (tester) async {
    final store = StudioOptionsStore.memory();
    addTearDown(store.dispose);
    final studio = StudioDriver(tester, options: store);
    await studio.start(size: mac);
    expect(studio.galets, isTrue);
    // No header, no column of tools, no side panel, no line of state, and
    // nothing written around the sheet.
    for (final gone in ['drawingControls', 'documentToolbar', 'toolsRail']) {
      expect(key(gone), findsNothing, reason: gone);
    }
    expect(find.text('MA FEUILLE'), findsNothing);
    expect(find.textContaining('récupération'), findsNothing);
    // A trait, kept through every change of window.
    await studio.drag(studio.at(300, 300), studio.at(500, 400));
    studio.expectCount(1);
    for (final (size, pebbles) in const [
      (Size(1130, 600), true),
      (Size(1129, 900), false),
      (Size(1440, 599), false),
      (Size(900, 1000), false),
      (Size(1920, 1080), true),
      (Size(680, 520), false),
      (Size(1440, 900), true),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      expect(studio.galets, pebbles, reason: '$size');
      studio.expectCount(1);
    }
    // Large letters keep the studio of before.
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    await tester.pumpAndSettle();
    expect(studio.galets, isFalse);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pumpAndSettle();
    expect(studio.galets, isTrue);
    // So does the simplest interface.
    await store.change(store.value.copyWith(level: InterfaceLevel.toddler));
    await tester.pumpAndSettle();
    expect(studio.galets, isFalse);
    await store.change(store.value.copyWith(level: InterfaceLevel.child));
    await tester.pumpAndSettle();
    expect(studio.galets, isTrue);
    studio.expectCount(1);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('the sheet first: on a Mac it is three times what it was, on '
      'a tablet it has two thirds of the screen', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start(size: mac);
    // With the desk around it: 936 × 624, standing on the desk.
    expect(sheet(tester), const Rect.fromLTWH(252, 138, 936, 624));
    // The stage holds it in its middle, across the window.
    final stage = tester.getRect(key('drawingSurface'));
    expect(stage.width, mac.width);
    expect(stage.center.dy, closeTo(sheet(tester).center.dy, 1e-6));
    // The view of the studio is that sheet.
    expect(studio.view().scale, closeTo(936 / 1200, 1e-9));
    await studio.finish();

    final onTablet = await tablet(tester);
    final whole = sheet(tester);
    expect(
      whole.width * whole.height / (ipad.width * ipad.height),
      greaterThan(.66),
    );
    expect(find.byType(DecorView), findsNothing);
    expect(tester.takeException(), isNull);
    await onTablet.finish();
  }, skip: !available);

  testWidgets('every button of the pebbles is named, at least 48 points, '
      'in the window, and over no other', (tester) async {
    final store = StudioOptionsStore.memory();
    addTearDown(store.dispose);
    final studio = StudioDriver(
      tester,
      options: store,
      gallery: MemoryGallery(),
    );
    await studio.start(size: mac);
    // The colour of a new studio is not one of the ten of the line, where
    // it has a place of its own while it is in hand: in the narrowest
    // window, the line is then drawn a little smaller rather than cut.
    tester.view.physicalSize = const Size(1130, 600);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final squeezed = tester.getRect(key('galetLine'));
    expect(squeezed.left, greaterThanOrEqualTo(0));
    expect(squeezed.right, lessThanOrEqualTo(1130));
    expect(tester.getRect(key('color-477fb2')).width, greaterThan(44));
    // One of the ten in hand: every button has its full size.
    await tester.tap(key('color-3370d1'));
    await tester.pumpAndSettle();

    void measure(Size window, String where, {Finder? inside}) {
      final seen = <(String, Rect)>[];
      final buttons = inside == null
          ? find.byType(GaletButton)
          : find.descendant(of: inside, matching: find.byType(GaletButton));
      for (final element in buttons.evaluate()) {
        final button = element.widget as GaletButton;
        final box = element.renderObject! as RenderBox;
        final rect = Rect.fromPoints(
          box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)),
        );
        final name = '${button.label} ($where)';
        expect(button.label, isNotEmpty, reason: where);
        expect(rect.width, greaterThanOrEqualTo(48), reason: name);
        expect(rect.height, greaterThanOrEqualTo(48), reason: name);
        expect(rect.left, greaterThanOrEqualTo(0), reason: name);
        expect(rect.top, greaterThanOrEqualTo(0), reason: name);
        expect(rect.right, lessThanOrEqualTo(window.width), reason: name);
        expect(rect.bottom, lessThanOrEqualTo(window.height), reason: name);
        for (final (other, otherRect) in seen) {
          expect(
            rect.deflate(.5).overlaps(otherRect.deflate(.5)),
            isFalse,
            reason: '$name over $other',
          );
        }
        seen.add((name, rect));
      }
      expect(
        seen.length,
        greaterThanOrEqualTo(inside == null ? 25 : 2),
        reason: where,
      );
    }

    for (final size in const [
      Size(1130, 600),
      Size(1180, 820),
      // What Windows leaves of its window of 1280 by 720.
      Size(1264, 681),
      Size(1280, 720),
      mac,
      Size(1920, 1080),
      Size(2560, 1440),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      for (final group in ToolGroup.values) {
        await studio.tap(group.keyName);
        expect(tester.takeException(), isNull, reason: '${group.name} $size');
        measure(size, '${group.name} at $size');
        // The sheet is clear of the pebbles of the top and of the line.
        final line = tester.getRect(key('galetLine'));
        expect(sheet(tester).bottom, lessThanOrEqualTo(line.top));
        expect(
          sheet(tester).top,
          greaterThanOrEqualTo(tester.getRect(key('myDrawing')).bottom),
        );
        expect(line.left, greaterThanOrEqualTo(0));
        expect(line.right, lessThanOrEqualTo(size.width));
      }
      // What opens stays in the window too.
      for (final (tool, opener, panel) in const [
        ('tool-stroke', 'myDrawing', 'galetPanel-drawing'),
        ('tool-stroke', 'galetSize', 'galetPanel-size'),
        ('tool-stroke', 'galetWhich', 'galetPanel-which'),
        ('tool-stamp', 'galetWhich', 'galetPanel-which'),
        ('tool-stamp', 'galetSize', 'galetPanel-size'),
        ('tool-shapes', 'galetWhich', 'galetPanel-which'),
        ('tool-magic', 'galetWhich', 'galetPanel-which'),
        ('tool-fill', 'galetWhich', 'galetPanel-which'),
      ]) {
        await studio.tap(tool);
        await tester.tap(key(opener));
        await tester.pumpAndSettle();
        expect(key(panel), findsOneWidget, reason: '$opener, $tool, $size');
        expect(tester.takeException(), isNull, reason: '$opener $tool $size');
        // What is open lies over the rest, which waits behind it: its
        // buttons are measured among themselves.
        measure(size, '$opener of $tool at $size', inside: key(panel));
        final shown = tester.getRect(
          find.descendant(
            of: key(panel),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        expect(shown.left, greaterThanOrEqualTo(0), reason: '$opener $size');
        expect(shown.top, greaterThanOrEqualTo(0), reason: '$opener $size');
        expect(
          shown.right,
          lessThanOrEqualTo(size.width),
          reason: '$opener $size',
        );
        expect(
          shown.bottom,
          lessThanOrEqualTo(size.height),
          reason: '$opener $size',
        );
        await studio.closePanel();
        expect(key(panel), findsNothing);
      }
    }
    await studio.finish();
  }, skip: !available);

  testWidgets('« Mon dessin » says what the drawing holds, opens what is '
      'done with it, and a press beside it puts it away without drawing', (
    tester,
  ) async {
    final studio = StudioDriver(tester, gallery: MemoryGallery());
    await studio.start(size: mac);
    expect(drawingCaption(tester), '0 élément · nouvelle feuille');
    await studio.drag(studio.at(300, 300), studio.at(500, 400));
    expect(
      drawingCaption(tester),
      '1 élément · modifications non enregistrées',
    );
    // A dot on « Enregistrer » says it too.
    expect(key('unsavedDot'), findsOneWidget);

    await tester.tap(key('myDrawing'));
    await tester.pumpAndSettle();
    expect(key('galetPanel-drawing'), findsOneWidget);
    expect(
      tester.widget<Text>(key('drawingCaption')).data,
      '1 élément · modifications non enregistrées',
    );
    // The last thing that happened, as the line under the sheet said it.
    expect(key('drawingStatus'), findsOneWidget);
    for (final (action, name) in const [
      ('newProject', 'Nouveau'),
      ('openProject', 'Ouvrir'),
      ('openGallery', 'Mes dessins'),
      ('importImage', 'Sur une image'),
      ('exportImage', 'Exporter'),
      ('printDrawing', 'Imprimer'),
      ('showHelp', 'Aide'),
      ('openOptions', 'Options'),
      ('aboutColor', 'À propos'),
    ]) {
      expect(
        find.descendant(of: key(action), matching: find.text(name)),
        findsOneWidget,
        reason: action,
      );
    }
    // Under its button, in the window.
    final panel = tester.getRect(key('galetPanel-drawing'));
    expect(panel.size, mac);
    final caption = tester.getRect(key('drawingCaption'));
    expect(caption.top, greaterThan(tester.getRect(key('myDrawing')).bottom));

    // A press on the sheet puts it away, and draws nothing.
    await studio.click(studio.at(900, 500));
    expect(key('galetPanel-drawing'), findsNothing);
    studio.expectCount(1);
    // Échap too.
    await tester.tap(key('myDrawing'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(key('galetPanel-drawing'), findsNothing);
    // And its own button.
    await tester.tap(key('myDrawing'));
    await tester.pumpAndSettle();
    await tester.tap(key('myDrawing'));
    await tester.pumpAndSettle();
    expect(key('galetPanel-drawing'), findsNothing);

    // An action of the panel puts it away and is done.
    await studio.tap('showHelp');
    expect(key('galetPanel-drawing'), findsNothing);
    expect(key('helpDialog'), findsOneWidget);
    await studio.tap('closeHelp');
    // Enregistrer: the dot goes, a tick shows for a moment.
    await studio.tap('saveProject');
    expect(key('unsavedDot'), findsNothing);
    expect(drawingCaption(tester), contains('projet enregistré'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('ten elementary colours at one press; a long press opens the '
      'shades of one; the line says which family is in hand', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start(size: mac);
    GaletSwatch swatch(String name) => tester.widget<GaletSwatch>(key(name));

    // The ten of the line, in their order, from left to right.
    final lefts = [
      for (final colour in galetColours)
        tester.getRect(key('color-${colour.rgb.toRadixString(16)}')).left,
    ];
    expect(lefts, [...lefts]..sort());
    // The colour of a new studio is none of them: it has the last place
    // while it is in hand.
    expect(swatch('color-477fb2').chosen, isTrue);
    expect(tester.getRect(key('color-477fb2')).left, greaterThan(lefts.last));

    // One press takes a colour; nothing opens.
    await tester.tap(key('color-e83d48'));
    await tester.pumpAndSettle();
    expect(key('galetPanel-shades'), findsNothing);
    expect(swatch('color-e83d48').chosen, isTrue);
    expect(swatch('color-e83d48').ticked, isTrue);
    expect(key('color-477fb2'), findsNothing);
    await studio.drag(studio.at(200, 200), studio.at(400, 300));

    // A long press on the blue one: its five shades, from the lightest to
    // the darkest, in a column above it.
    await tester.longPress(key('color-3370d1'));
    await tester.pumpAndSettle();
    expect(key('galetPanel-shades'), findsOneWidget);
    // The long press chose nothing.
    expect(swatch('color-e83d48').chosen, isTrue);
    final blue = tester.getRect(key('color-3370d1'));
    final shades = [
      for (final shade in galetFamilies[4])
        tester.getRect(key('nuance-${shade.rgb.toRadixString(16)}')),
    ];
    expect(shades, hasLength(5));
    for (var index = 0; index < shades.length; index++) {
      expect(shades[index].center.dx, closeTo(blue.center.dx, 1));
      expect(shades[index].bottom, lessThan(blue.top));
      if (index > 0) {
        expect(
          shades[index].top,
          greaterThanOrEqualTo(shades[index - 1].bottom),
        );
      }
    }
    // A shade is taken at one press, and the column goes.
    await tester.tap(key('nuance-a8d8f0'));
    await tester.pumpAndSettle();
    expect(key('galetPanel-shades'), findsNothing);
    // The swatch of the line keeps its own colour and wears the ring,
    // without the tick: a shade of it is in hand.
    expect(swatch('color-3370d1').chosen, isTrue);
    expect(swatch('color-3370d1').ticked, isFalse);
    expect(swatch('color-e83d48').chosen, isFalse);
    await studio.drag(studio.at(200, 500), studio.at(400, 600));

    // The second button of a mouse opens the shades too.
    await tester.tap(key('color-4db266'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(key('galetPanel-shades'), findsOneWidget);
    expect(key('nuance-245846'), findsOneWidget);
    // Another long press, on another colour: its own shades.
    await tester.longPress(key('color-f4b7cf'));
    await tester.pumpAndSettle();
    expect(key('nuance-245846'), findsNothing);
    expect(key('nuance-c96d93'), findsOneWidget);
    // A press beside it puts the column away, and keeps the colour.
    await studio.click(studio.at(900, 400));
    expect(key('galetPanel-shades'), findsNothing);
    expect(swatch('color-3370d1').chosen, isTrue);
    // White has no shades.
    await tester.longPress(key('color-ffffff'));
    await tester.pumpAndSettle();
    expect(key('galetPanel-shades'), findsNothing);

    final document = await studio.saved();
    try {
      expect(document.strokes.map((stroke) => stroke.rgb), [
        0xe83d48,
        0xa8d8f0,
      ]);
    } finally {
      document.dispose();
    }
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('five dots for the width of a trait; three sizes for a stamp '
      'and a text; nothing to size for the pot and the eraser', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start(size: mac);
    // The width of a new studio is the middle dot.
    await tester.tap(key('galetSize'));
    await tester.pumpAndSettle();
    expect(find.text('Taille du trait'), findsOneWidget);
    for (var index = 0; index < galetWidths.length; index++) {
      expect(isChosen(tester, 'width-$index'), index == 2, reason: '$index');
    }
    await tester.tap(key('width-4'));
    await tester.pumpAndSettle();
    expect(key('galetPanel-size'), findsNothing);
    await studio.drag(studio.at(200, 200), studio.at(400, 300));
    await studio.tap('width-0');
    await studio.drag(studio.at(200, 500), studio.at(400, 600));

    // A stamp and a text: Petit, Moyen, Grand.
    await studio.tap('tool-stamp');
    await tester.tap(key('galetSize'));
    await tester.pumpAndSettle();
    expect(find.text('Taille du tampon'), findsOneWidget);
    expect(isChosen(tester, 'size-medium'), isTrue);
    await tester.tap(key('size-large'));
    await tester.pumpAndSettle();
    expect(key('galetPanel-size'), findsNothing);
    await studio.click(studio.at(800, 400));
    await studio.tap('tool-text');
    await tester.tap(key('galetSize'));
    await tester.pumpAndSettle();
    expect(find.text('Taille du texte'), findsOneWidget);
    await studio.closePanel();

    // The two settings keep their place whatever the tool; they do not
    // answer when the tool has nothing to set.
    final sizeAt = tester.getRect(key('galetSize')).left;
    for (final (tool, sized, which) in const [
      ('tool-fill', false, true),
      ('tool-eraser', false, false),
      ('tool-line', true, false),
      ('tool-text', true, false),
      ('tool-select', false, false),
      ('tool-stroke', true, true),
      ('tool-magic', true, true),
      ('tool-stamp', true, true),
      ('tool-shapes', true, true),
    ]) {
      await studio.tap(tool);
      expect(onPressedOf(tester, 'galetSize') != null, sized, reason: tool);
      expect(onPressedOf(tester, 'galetWhich') != null, which, reason: tool);
    }
    await studio.tap('tool-stroke');
    expect(tester.getRect(key('galetSize')).left, sizeAt);

    final document = await studio.saved();
    try {
      expect(document.strokes[0].width, 40);
      expect(document.strokes[1].width, 4);
      final stamp = document.strokes[2];
      expect(stamp.kind, VectorKind.stamp);
      // « Grand » : 240 units wide on a sheet of 1200 by 800.
      expect(right(stamp) - left(stamp), closeTo(240, .01));
    } finally {
      document.dispose();
    }
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('« lequel » : the sorts of trait with their names, the stamps, '
      'the shapes and their inside', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start(size: mac);

    // The brush: five sorts of trait, each with its name written.
    await tester.tap(key('galetWhich'));
    await tester.pumpAndSettle();
    expect(find.text('Sorte de trait'), findsOneWidget);
    for (final name in ['Rond', 'Feutre', 'Plume', 'Craie', 'Aérographe']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(isChosen(tester, 'brushTip-round'), isTrue);
    await tester.tap(key('brushTip-felt'));
    await tester.pumpAndSettle();
    // A choice made puts the panel away.
    expect(key('galetPanel-which'), findsNothing);
    await studio.drag(studio.at(200, 200), studio.at(400, 300));

    // The stamps: the twenty-four of them, in the colour in hand; the two
    // buttons that turn the next one leave the panel open.
    await studio.tap('tool-stamp');
    await tester.tap(key('galetWhich'));
    await tester.pumpAndSettle();
    expect(find.text('Choisis un tampon'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is GaletTile &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('stamp-'),
      ),
      findsNWidgets(24),
    );
    await tester.tap(key('turnStamp'));
    await tester.pumpAndSettle();
    expect(key('galetPanel-which'), findsOneWidget);
    expect(isChosen(tester, 'turnStamp'), isTrue);
    await tester.tap(key('stamp-chat'));
    await tester.pumpAndSettle();
    expect(key('galetPanel-which'), findsNothing);
    await studio.click(studio.at(800, 300));

    // « Formes » : the rectangle, the oval, the six shapes and the magnet;
    // under them, the inside of what is drawn.
    await studio.tap('tool-shapes');
    await tester.tap(key('galetWhich'));
    await tester.pumpAndSettle();
    expect(find.text('Sorte de forme'), findsOneWidget);
    for (final choice in [
      'tool-rectangle',
      'tool-ellipse',
      'tool-magnet',
      for (final shape in NewShape.values) 'shape-${shape.name}',
    ]) {
      expect(key(choice), findsOneWidget, reason: choice);
    }
    expect(key('fillShapeCheckbox'), findsOneWidget);
    await tester.tap(key('shape-heart'));
    await tester.pumpAndSettle();
    expect(key('galetPanel-which'), findsNothing);
    // The inside: its colour is the one a swatch changes once it is asked.
    await studio.tap('paint-target-fill');
    await tester.tap(key('color-eebf4e'));
    await tester.pumpAndSettle();
    await studio.drag(studio.at(700, 500), studio.at(900, 700));

    final document = await studio.saved();
    try {
      expect(document.strokes[0].look.tool, BrushTool.felt);
      final stamp = document.strokes[1];
      expect(stamp.kind, VectorKind.stamp);
      expect(stamp.look.rotation, isNot(0));
      final heart = document.strokes[2];
      expect(heart.kind, VectorKind.contour);
      expect(heart.fillRgb, 0xeebf4e);
      expect(heart.rgb, 0x477fb2);
    } finally {
      document.dispose();
    }
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('a chosen element has its actions in a pebble above the line; '
      'a colour, a width and its inside change it at once', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start(size: mac);
    await studio.tap('tool-rectangle');
    await studio.drag(studio.at(300, 200), studio.at(700, 600));
    await studio.tap('tool-select');
    expect(key('galetSelection'), findsNothing);
    await studio.click(studio.at(300, 400));
    // Its actions, and the sentence that says what to do with it.
    expect(key('galetSelection'), findsOneWidget);
    final pebble = tester.getRect(key('galetSelection'));
    expect(
      pebble.bottom,
      lessThanOrEqualTo(tester.getRect(key('galetLine')).top),
    );
    for (final action in [
      'selectionOrder',
      'turnSelection',
      'mirrorSelection',
      'duplicateSelection',
      'deleteSelection',
      'shrinkSelection',
      'growSelection',
    ]) {
      final rect = tester.getRect(key(action));
      expect(pebble.contains(rect.center), isTrue, reason: action);
      expect(rect.width, greaterThanOrEqualTo(48), reason: action);
      expect(rect.height, greaterThanOrEqualTo(48), reason: action);
    }
    expect(find.textContaining('Glisse pour déplacer'), findsOneWidget);

    Future<StrokeData> shape() async {
      final document = await studio.saved();
      try {
        return document.strokes.single;
      } finally {
        document.dispose();
      }
    }

    // A colour of the line, then a shade.
    await tester.tap(key('color-e83d48'));
    await tester.pumpAndSettle();
    expect((await shape()).rgb, 0xe83d48);
    await studio.tap('color-245846');
    expect((await shape()).rgb, 0x245846);
    // One of the five widths.
    await studio.tap('width-3');
    expect((await shape()).width, 24);
    // Its inside: filled, in the colour asked for, then emptied.
    await studio.tap('paint-target-fill');
    await tester.tap(key('color-ef9439'));
    await tester.pumpAndSettle();
    expect((await shape()).fillRgb, 0xef9439);
    expect((await shape()).rgb, 0x245846);
    await studio.tap('fillShapeCheckbox');
    expect((await shape()).fillRgb, isNull);
    // Each of these was one step for Annuler.
    await studio.tap('undo');
    expect((await shape()).fillRgb, 0xef9439);

    // Effacer: the pebble goes with the element.
    await studio.click(studio.at(300, 400));
    await studio.tap('deleteSelection');
    studio.expectCount(0);
    expect(key('galetSelection'), findsNothing);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('« dessiner en grand » puts the pebbles of the top away, but '
      'for a column in the corner, where the sheet gains room', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start(size: mac);
    await studio.tap('tool-stamp');
    await studio.click();
    final before = sheet(tester);
    final svg = await studio.svg();
    expect(isChosen(tester, 'bigSheet'), isFalse);

    await studio.tap('bigSheet');
    expect(isChosen(tester, 'bigSheet'), isTrue);
    for (final gone in [
      'myDrawing',
      'saveProject',
      'replayDrawing',
      'zoomIn',
    ]) {
      expect(key(gone), findsNothing, reason: gone);
    }
    // The line, Annuler and Rétablir stay at hand.
    for (final kept in [
      'galetLine',
      'tool-stroke',
      'color-e83d48',
      'undo',
      'redo',
    ]) {
      expect(key(kept), findsOneWidget, reason: kept);
    }
    final after = sheet(tester);
    expect(after.width, greaterThan(before.width + 100));
    // The column of the corner covers nothing of the sheet.
    for (final button in ['undo', 'redo', 'bigSheet']) {
      expect(after.overlaps(tester.getRect(key(button))), isFalse);
    }
    expect(tester.takeException(), isNull);
    // Drawing goes on: positions follow the larger sheet.
    await studio.click(studio.at(200, 200));
    studio.menu.onSave!();
    await tester.pumpAndSettle();
    expect(studio.files.projects, hasLength(1));

    // Échap brings the pebbles back when nothing else is to be stopped.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(isChosen(tester, 'bigSheet'), isFalse);
    expect(key('myDrawing'), findsOneWidget);
    expect(sheet(tester), before);
    await studio.tap('undo');
    expect(await studio.svg(), svg);
    await studio.finish();

    // A tablet's sheet already has the width of the screen: the button is
    // not offered there.
    final onTablet = await tablet(tester);
    expect(key('bigSheet'), findsNothing);
    expect(key('fitPage'), findsOneWidget);
    // Nor are the loupes: two fingers do it.
    expect(key('zoomIn'), findsNothing);
    expect(tester.takeException(), isNull);
    await onTablet.finish();
  }, skip: !available);

  testWidgets('the decor has the whole window; what is pressed twice beside '
      'the stage of the sheet is named too', (tester) async {
    final studio = StudioDriver(tester);
    // The stage of the sheet goes from one side of the window to the
    // other, a little above the sheet and a little under it: the pencils
    // on the desk lie under it, the rest of the decor beside the sheet.
    await studio.start(size: mac);
    final view = tester.widget<DecorView>(find.byType(DecorView));
    final frame = tester.getRect(key('decor'));
    expect(frame, const Rect.fromLTWH(0, 0, 1440, 804));
    final painting = DecorPainting(view.decor, view.layoutIn(frame.size));
    expect(painting.layout.pieces, isTrue);
    final stage = tester.getRect(key('drawingSurface'));
    // Nothing of the decor goes under the pebbles of the top.
    for (final name in painting.names) {
      final at = painting.layout.place(name.at, name.anchor);
      expect(
        at.top,
        greaterThanOrEqualTo(tester.getRect(key('myDrawing')).bottom),
        reason: name.key,
      );
      // Nor under the sheet.
      expect(at.overlaps(sheet(tester).deflate(1)), isFalse, reason: name.key);
    }
    final beside = [
      for (final name in painting.names)
        if (!stage.contains(painting.layout.place(name.at, name.anchor).center))
          name,
    ];
    final within = [
      for (final name in painting.names)
        if (stage.contains(painting.layout.place(name.at, name.anchor).center))
          name,
    ];
    expect(beside, isNotEmpty);
    expect(within, isNotEmpty);
    for (final name in [beside.first, within.first]) {
      final at = painting.layout.place(name.at, name.anchor).center;
      await tester.tapAt(at);
      await tester.tapAt(at);
      await tester.pump();
      expect(key('decorNameCard'), findsOneWidget, reason: name.key);
      expect(find.text(name.frenchName), findsOneWidget, reason: name.key);
      // The card stays whole in the window.
      final card = tester.getRect(key('decorNameCard'));
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(mac.width));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(key('decorNameCard'), findsNothing, reason: name.key);
      await tester.pump(const Duration(seconds: 1));
    }
    // The tool in hand is never stopped: a trait is drawn as before.
    await studio.drag(studio.at(300, 300), studio.at(500, 400));
    studio.expectCount(1);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('what matters now is said under the pebble where the window '
      'has no room beside it', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start(size: const Size(1280, 800));
    // The few words of the tool need room: none here.
    expect(key('galetBubble'), findsNothing);
    // The first click of a line waits for the second: it is said.
    await studio.tap('tool-line');
    await studio.click(studio.at(300, 300));
    final said = find.text(
      'Clique maintenant là où ta ligne doit s’arrêter. Échap enlève le petit cercle.',
    );
    expect(said, findsOneWidget);
    final bubble = tester.getRect(key('galetBubble'));
    expect(
      bubble.top,
      greaterThanOrEqualTo(tester.getRect(key('myDrawing')).bottom),
    );
    expect(bubble.left, greaterThanOrEqualTo(0));
    await studio.click(studio.at(600, 500));
    expect(said, findsNothing);
    expect(key('galetBubble'), findsNothing);
    studio.expectCount(1);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('with room beside the pebble, the companion says a few words '
      'of the tool in hand', (tester) async {
    // The letters of the pebbles, as a screen writes them: the squares of
    // the test font leave no room for any sentence.
    await tester.runAsync(loadReviewFonts);
    final store = StudioOptionsStore.memory();
    addTearDown(store.dispose);
    final studio = StudioDriver(tester, options: store);
    await studio.start(size: const Size(1600, 900));
    Finder says(String words) => find.textContaining(words, findRichText: true);
    expect(says('Un trait, une idée.'), findsOneWidget);
    expect(says('Choisis ta couleur et dessine'), findsOneWidget);
    final bubble = tester.getRect(key('galetBubble'));
    // Beside the pebble of the drawing, before the pebble of the right.
    expect(
      bubble.left,
      greaterThan(tester.getRect(key('openUniverses')).right),
    );
    expect(bubble.right, lessThan(tester.getRect(key('replayDrawing')).left));
    await studio.tap('tool-stamp');
    expect(says('Un tampon, et hop'), findsOneWidget);
    await studio.tap('tool-select');
    expect(says('Choisis un élément.'), findsOneWidget);
    // « Dessiner sans tenir le bouton » changes how a trait is made.
    await store.change(store.value.copyWith(holdFree: true));
    await tester.pumpAndSettle();
    await studio.tap('tool-stroke');
    expect(says('Clique pour commencer ton trait'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('a screen reader meets one control per button: its name, '
      'whether it is chosen, what it opens', (tester) async {
    final handle = tester.ensureSemantics();
    final studio = StudioDriver(tester);
    await studio.start(size: mac);
    SemanticsData data(String name) =>
        tester.getSemantics(key(name)).getSemanticsData();

    for (final group in ToolGroup.values) {
      final tool = data(group.keyName);
      expect(tool.label, group.label);
      expect(tool.flagsCollection.isButton, isTrue);
      expect(tool.hasAction(SemanticsAction.tap), isTrue);
      expect(
        tool.flagsCollection.isSelected.toBoolOrNull() ?? false,
        group == ToolGroup.brush,
        reason: group.name,
      );
    }
    // « Mon dessin » : what the drawing holds, and that it opens.
    final drawing = data('myDrawing');
    expect(drawing.label, 'Mon dessin : 0 élément · nouvelle feuille');
    expect(drawing.flagsCollection.isExpanded.toBoolOrNull(), isFalse);
    // The two settings.
    expect(data('galetSize').label, 'Taille du trait');
    expect(data('galetWhich').label, 'Sorte de trait');
    // A swatch: its name, and its shades as an action of its own.
    final red = data('color-e83d48');
    expect(red.label, 'Rouge');
    expect(red.hasAction(SemanticsAction.longPress), isTrue);
    expect(
      red.customSemanticsActionIds!.map(
        (id) => CustomSemanticsAction.getAction(id)!.label,
      ),
      ['Nuances'],
    );
    expect(
      data('color-ffffff').customSemanticsActionIds,
      anyOf(isNull, isEmpty),
    );
    // That action opens the shades, each one named.
    final node = tester.getSemantics(key('color-e83d48'));
    node.owner!.performAction(node.id, SemanticsAction.longPress);
    await tester.pumpAndSettle();
    expect(key('galetPanel-shades'), findsOneWidget);
    expect(data('nuance-7b1d27').label, 'Bordeaux');
    await studio.closePanel();
    // The actions of the right.
    expect(data('undo').label, 'Annuler le dernier geste');
    expect(data('undo').hasAction(SemanticsAction.tap), isFalse);
    expect(data('saveProject').label, 'Enregistrer');
    expect(data('layersButton').label, 'Calques : tu dessines sur Calque 1');
    expect(data('fitPage').label, 'Voir toute la feuille');
    handle.dispose();
    await studio.finish();
  }, skip: !available);

  testWidgets('a screen reader goes through the pebbles of the top, the '
      'sheet, the line, an open panel after its pebble, and the room last', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final studio = StudioDriver(tester);
    await studio.start(size: mac);
    List<String> read() {
      final labels = <String>[];
      void walk(SemanticsNode node) {
        final label = node.getSemanticsData().label;
        if (label.isNotEmpty) labels.add(label);
        node
            .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)
            .forEach(walk);
      }

      walk(tester.getSemantics(find.byType(MaterialApp)));
      return labels;
    }

    int place(List<String> labels, Pattern label) {
      final at = labels.indexWhere((said) => said.startsWith(label));
      expect(at, isNonNegative, reason: '$label in $labels');
      return at;
    }

    var labels = read();
    expect(place(labels, 'Mon dessin'), 0);
    final order = [
      for (final label in const [
        'Univers',
        'Annuler le dernier geste',
        'Enregistrer',
        'Feuille de dessin',
        'Pinceau',
        'Taille du trait',
        'Rouge',
        'Blanc',
        'La fenêtre',
        'Le chat',
      ])
        place(labels, label),
    ];
    expect(order, [...order]..sort(), reason: '$labels');
    // « lequel » open: its choices after the line, before the room.
    await tester.tap(key('galetWhich'));
    await tester.pumpAndSettle();
    labels = read();
    expect(place(labels, 'Feutre'), greaterThan(place(labels, 'Blanc')));
    expect(place(labels, 'Feutre'), lessThan(place(labels, 'La fenêtre')));
    await studio.closePanel();
    // « Mon dessin » open: what it holds just after its pebble.
    await tester.tap(key('myDrawing'));
    await tester.pumpAndSettle();
    labels = read();
    expect(place(labels, 'Nouveau'), greaterThan(place(labels, 'Univers')));
    expect(
      place(labels, 'Nouveau'),
      lessThan(place(labels, 'Annuler le dernier geste')),
    );
    await studio.closePanel();
    handle.dispose();
    await studio.finish();
  }, skip: !available);

  testWidgets('in English the pebbles speak English', (tester) async {
    final store = StudioOptionsStore.memory(
      const StudioOptions(language: LanguageChoice.english),
    );
    addTearDown(store.dispose);
    final studio = StudioDriver(tester, options: store);
    await studio.start(size: mac);
    await tester.pumpAndSettle();
    expect(
      tester.widget<GaletButton>(key('myDrawing')).label,
      startsWith('My drawing: '),
    );
    await tester.tap(key('myDrawing'));
    await tester.pumpAndSettle();
    for (final name in ['New', 'Open', 'Export', 'Print', 'Help', 'About']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    await studio.closePanel();
    expect(tester.widget<GaletSwatch>(key('color-e83d48')).name, 'Red');
    await tester.longPress(key('color-e83d48'));
    await tester.pumpAndSettle();
    expect(tester.widget<GaletSwatch>(key('nuance-7b1d27')).name, 'Burgundy');
    await studio.closePanel();
    await tester.tap(key('galetSize'));
    await tester.pumpAndSettle();
    expect(find.text('Size of the line'), findsOneWidget);
    await studio.closePanel();
    appLanguage.value = AppLanguage.french;
    await studio.finish();
  }, skip: !available);

  testWidgets('the pebbles wear the universe: its surface, its corners, and '
      'the ground that goes on under the line', (tester) async {
    final store = StudioOptionsStore.memory(
      const StudioOptions(universe: 'papier'),
    );
    addTearDown(store.dispose);
    final studio = StudioDriver(tester, options: store);
    await studio.start(size: mac);
    await tester.pumpAndSettle();
    BoxDecoration pebble(Finder galet) =>
        tester
                .widget<Container>(
                  find
                      .descendant(of: galet, matching: find.byType(Container))
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(pebble(key('galetLine')).color, studioSurface);
    expect(pebble(key('galetLine')).borderRadius, BorderRadius.circular(12));
    // The front of the ground, in the band of the line.
    final ground = tester.widget<GaletGround>(find.byType(GaletGround));
    expect(ground.front.$1, const Color(0xffc7a471));
    expect(ground.front.$3, const Color(0xff9f7d4b));
    expect(tester.getRect(find.byType(GaletGround)).height, 96);
    // « Classique » has no decor: a plain window, all round pebbles.
    await store.change(store.value.copyWith(universe: 'classique'));
    await tester.pumpAndSettle();
    expect(find.byType(GaletGround), findsNothing);
    expect(find.byType(DecorView), findsNothing);
    expect(pebble(key('galetLine')).borderRadius, BorderRadius.circular(32));
    // Without a decor the sheet takes the room.
    expect(sheet(tester).width, greaterThan(936));
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('the ground under the line is in the room of the decor: the '
      'shade of the night falls on it too, at the minute it falls', (
    tester,
  ) async {
    final before = debugDecorNow;
    addTearDown(() => debugDecorNow = before);
    debugDecorNow = () => DateTime(2026, 11, 12, 15);
    final studio = StudioDriver(tester);
    await studio.start(size: mac);
    GaletGround ground() =>
        tester.widget<GaletGround>(find.byType(GaletGround));
    final decor = tester.widget<DecorView>(find.byType(DecorView)).decor;
    // The afternoon tints nothing.
    expect(ground().veil, isNull);
    // The light of the frame above goes on down here.
    expect(ground().above, const Size(1440, 804));
    expect(tester.getRect(find.byType(GaletGround)).top, 804);
    // Night has come: the decor looks at the clock at each minute, and
    // the ground with it.
    debugDecorNow = () => DateTime(2026, 11, 12, 22, 10);
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    final night = decor.veils[DayMoment.nuit];
    expect(night?.multiply, isNotNull);
    expect(ground().veil, same(night));
    // And the morning, whose light crosses the room.
    debugDecorNow = () => DateTime(2026, 11, 13, 8);
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    expect(ground().veil, same(decor.veils[DayMoment.matin]));
    expect(ground().veil?.gradient, isNotNull);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('the keys of the tools, of Annuler and of the menu work as '
      'before, and a panel never keeps a command from the keyboard', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start(size: mac);
    await studio.drag(studio.at(300, 300), studio.at(500, 400));
    await tester.tap(key('galetWhich'));
    await tester.pumpAndSettle();
    expect(key('galetPanel-which'), findsOneWidget);
    // A command of the menu of the system: done, the panel put away or not.
    studio.menu.onUndo!();
    await tester.pumpAndSettle();
    studio.expectCount(0);
    await studio.closePanel();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    studio.expectCount(1);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);
}
