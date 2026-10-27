// SPDX-License-Identifier: MIT
// « Options » in the real studio: real Rust documents; only native panels,
// disk writes of drawings and the recovery store are in memory.
import 'dart:io';

import 'package:edupaint_flutter_study/color_palette.dart';
import 'package:edupaint_flutter_study/options_dialog.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_header.dart';
import 'package:edupaint_flutter_study/studio_inspector.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_tool.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_printer.dart';
import 'support/memory_gallery.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  Finder key(String name) => find.byKey(Key(name));

  // The tools that the bar shows, in its order.
  List<StudioTool> shownTools(WidgetTester tester) => [
    for (final tool in StudioTool.values)
      if (key(tool.keyName).evaluate().isNotEmpty) tool,
  ];

  StudioTool selectedTool(WidgetTester tester) {
    for (final tool in shownTools(tester)) {
      final selected = tester
          .getSemantics(key(tool.keyName))
          .flagsCollection
          .isSelected
          .toBoolOrNull();
      if (selected ?? false) return tool;
    }
    fail('No tool is announced as selected.');
  }

  Future<void> closeOptions(WidgetTester tester) async {
    await tester.tap(key('closeOptions'));
    await tester.pumpAndSettle();
    expect(key('optionsDialog'), findsNothing);
  }

  // Opens the options, taps the control [name] and closes them.
  Future<void> choose(StudioDriver studio, String name) async {
    await studio.openOptions();
    expect(key('optionsDialog'), findsOneWidget);
    await studio.tester.ensureVisible(key(name));
    await studio.tester.pumpAndSettle();
    await studio.tester.tap(key(name));
    await studio.tester.pumpAndSettle();
    await closeOptions(studio.tester);
  }

  Future<void> shortcut(
    WidgetTester tester,
    LogicalKeyboardKey letter, {
    bool shift = false,
  }) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(letter);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'by default the toothed wheel opens the options at once, and the calculation is one of them',
    (tester) async {
      final store = StudioOptionsStore.memory();
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start();
      expect(StudioOptions.defaults.guarded, isFalse);

      // No door: the options open at once.
      await studio.tap('openOptions');
      expect(key('adultGate'), findsNothing);
      expect(key('optionsDialog'), findsOneWidget);
      await tester.pump(OptionsDialog.settling);
      await tester.pump();
      await tester.ensureVisible(key('optionGuarded'));
      await tester.pumpAndSettle();
      await tester.tap(key('optionGuarded'));
      await tester.pumpAndSettle();
      expect(store.value, const StudioOptions(guarded: true));
      await closeOptions(tester);

      // Switched on, the calculation keeps the door from then on.
      await studio.tap('openOptions');
      expect(key('adultGate'), findsOneWidget);
      expect(key('optionsDialog'), findsNothing);
      await answerAdultGate(tester);
      expect(key('optionsDialog'), findsOneWidget);
      await tester.ensureVisible(key('optionGuarded'));
      await tester.pumpAndSettle();
      await tester.tap(key('optionGuarded'));
      await tester.pumpAndSettle();
      expect(store.value, StudioOptions.defaults);
      await closeOptions(tester);
      await studio.tap('openOptions');
      expect(key('adultGate'), findsNothing);
      expect(key('optionsDialog'), findsOneWidget);
      await tester.pump(OptionsDialog.settling);
      await tester.pump();
      await closeOptions(tester);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'guarded, the toothed wheel asks its calculation first, and shows the options to who answers',
    (tester) async {
      final store = StudioOptionsStore.memory(
        const StudioOptions(guarded: true),
      );
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start();
      await studio.drag(const Offset(-80, -40), const Offset(60, 30));
      studio.expectCount(1);

      // Giving up at the door: no options, nothing changed.
      await studio.tap('openOptions');
      expect(key('adultGate'), findsOneWidget);
      expect(key('optionsDialog'), findsNothing);
      await studio.tap('adultGateCancel');
      expect(key('adultGate'), findsNothing);
      expect(key('optionsDialog'), findsNothing);

      // A wrong result keeps the door shut.
      await studio.tap('openOptions');
      await typeAtAdultGate(tester, wrongAdultGateAnswer(tester));
      expect(key('adultGate'), findsOneWidget);
      expect(key('optionsDialog'), findsNothing);
      await answerAdultGate(tester);
      expect(key('adultGate'), findsNothing);
      expect(key('optionsDialog'), findsOneWidget);
      for (final control in [
        'level-toddler',
        'level-child',
        'level-full',
        'optionPrinting',
        'optionSounds',
        'optionHoldFree',
        'optionScreenKeyboard',
        'optionsHelp',
        'optionsAbout',
        'closeOptions',
      ]) {
        expect(key(control), findsOneWidget, reason: control);
      }
      // While the options are open the drawing cannot be edited behind
      // them: the menu bar of the Mac, whose keys do not pass through the
      // dialog, asks in vain.
      studio.menu.onUndo?.call();
      await tester.pump();
      await closeOptions(tester);
      studio.expectCount(1);
      expect(store.value, const StudioOptions(guarded: true));
      // The studio answers again at once.
      await shortcut(tester, LogicalKeyboardKey.keyZ);
      studio.expectCount(0);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'Imprimer switched off has no button, no shortcut and no menu entry',
    (tester) async {
      final printer = FakePrinter();
      final store = StudioOptionsStore.memory();
      addTearDown(store.dispose);
      final studio = StudioDriver(
        tester,
        printer: printer.call,
        options: store,
      );
      await studio.start(size: const Size(1280, 800));
      await studio.drag(const Offset(-80, -40), const Offset(60, 30));
      expect(key('printDrawing'), findsOneWidget);
      expect(studio.menu.onPrint, isNotNull);

      await choose(studio, 'optionPrinting');
      expect(store.value.printing, isFalse);
      expect(key('printDrawing'), findsNothing);
      expect(studio.menu.onPrint, isNull);
      await shortcut(tester, LogicalKeyboardKey.keyP);
      expect(printer.requests, isEmpty);
      // The other actions keep their line and their order.
      expect(
        tester.getRect(key('exportImage')).top,
        tester.getRect(key('newProject')).top,
      );

      await choose(studio, 'optionPrinting');
      expect(store.value.printing, isTrue);
      expect(key('printDrawing'), findsOneWidget);
      await printAndWait(
        tester,
        printer,
        press: () async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        },
      );
      expect(printer.requests, hasLength(1));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the simplest interface keeps four tools, large colours and three sizes',
    (tester) async {
      final printer = FakePrinter();
      final store = StudioOptionsStore.memory();
      addTearDown(store.dispose);
      final studio = StudioDriver(
        tester,
        printer: printer.call,
        gallery: MemoryGallery(),
        options: store,
      );
      await studio.start(size: const Size(1280, 800));
      expect(shownTools(tester), StudioTool.values);
      expect(find.byType(StudioInspector), findsOneWidget);

      await choose(studio, 'level-toddler');
      expect(store.value.level, InterfaceLevel.toddler);
      expect(shownTools(tester), [
        StudioTool.brush,
        StudioTool.stamp,
        StudioTool.fill,
        StudioTool.eraser,
      ]);
      // What needs a file panel, a format or a second thought is gone.
      for (final gone in [
        'openProject',
        'importImage',
        'exportImage',
        'showHelp',
        'zoomIn',
        'zoomOut',
        'fitPage',
        'panPage',
        'bigSheet',
        'layersButton',
        'fillShapeCheckbox',
        'morePaintColors',
        'pickPaintColor',
        'paintColorRow',
      ]) {
        expect(key(gone), findsNothing, reason: gone);
      }
      expect(find.byType(StudioInspector), findsNothing);
      expect(find.text('MA FEUILLE'), findsNothing);
      expect(find.textContaining('récupération'), findsNothing);
      expect(
        find.textContaining('Un petit atelier pour les grandes idées'),
        findsNothing,
      );
      // What stays: a new sheet, the album, saving, printing, the options,
      // undoing, and the film of the drawing.
      for (final kept in [
        'newProject',
        'openGallery',
        'saveProject',
        'printDrawing',
        'openOptions',
        'undo',
        'redo',
        'replayDrawing',
        'simplePaintColors',
        'brush-small',
        'brush-medium',
        'brush-large',
      ]) {
        expect(key(kept), findsOneWidget, reason: kept);
      }
      // Large targets: the tools, the colours.
      for (final tool in shownTools(tester)) {
        final size = tester.getSize(key(tool.keyName));
        expect(size.width, greaterThanOrEqualTo(96), reason: tool.name);
        expect(size.height, greaterThanOrEqualTo(96), reason: tool.name);
      }
      expect(tester.getSize(key('color-e83d48')), const Size.square(60));

      // Drawing works as ever: a colour, a size, a trait.
      await studio.tap('color-e83d48');
      await studio.tap('brush-large');
      await studio.drag(const Offset(-80, -40), const Offset(60, 30));
      // A stamp, then the pot on the sheet, then the eraser on the stamp.
      await studio.tap('tool-stamp');
      await studio.click(const Offset(120, 60));
      await studio.tap('tool-fill');
      await studio.tap('color-3370d1');
      await studio.click(const Offset(-200, 120));
      final document = await studio.saved();
      addTearDown(document.dispose);
      expect(document.strokes, hasLength(2));
      expect(document.strokes[0].kind, VectorKind.stroke);
      expect(document.strokes[0].rgb, 0xe83d48);
      expect(document.strokes[0].width, 30);
      expect(document.strokes[1].kind, VectorKind.stamp);
      expect(document.paperRgb, 0x3370d1);
      await studio.tap('tool-eraser');
      await studio.click(const Offset(120, 60));
      await studio.tap('undo');

      // The numbers follow the four tools; the others answer nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pumpAndSettle();
      expect(selectedTool(tester), StudioTool.stamp);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.pumpAndSettle();
      expect(selectedTool(tester), StudioTool.stamp);
      // No key reaches what the interface no longer shows.
      studio.files.openPath = '/drawings/ailleurs.edupaint';
      studio.files.svg = null;
      await shortcut(tester, LogicalKeyboardKey.keyO);
      await shortcut(tester, LogicalKeyboardKey.keyE, shift: true);
      expect(studio.files.svg, isNull);
      expect(find.textContaining('n’a pas pu être ouvert'), findsNothing);
      expect(studio.menu.onOpen, isNull);
      expect(studio.menu.onImportImage, isNull);
      expect(studio.menu.onExportSvg, isNull);
      expect(studio.menu.onExportPng, isNull);
      expect(studio.menu.onLayers, isNull);
      expect(studio.menu.onOptions, isNotNull);
      // Printing stays, since the options still offer it.
      await printAndWait(tester, printer);
      expect(printer.requests, hasLength(1));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the interface of children keeps every tool, without the layers and the exports',
    (tester) async {
      final store = StudioOptionsStore.memory(
        const StudioOptions(level: InterfaceLevel.child),
      );
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(1280, 800));
      expect(shownTools(tester), StudioTool.values);
      for (final gone in ['exportImage', 'layersButton']) {
        expect(key(gone), findsNothing, reason: gone);
      }
      for (final kept in [
        'newProject',
        'openProject',
        'importImage',
        'saveProject',
        'printDrawing',
        'showHelp',
        'openOptions',
        'zoomIn',
        'bigSheet',
        'pickPaintColor',
        'morePaintColors',
        'replayDrawing',
      ]) {
        expect(key(kept), findsOneWidget, reason: kept);
      }
      expect(find.byType(StudioInspector), findsOneWidget);
      expect(find.text('MA FEUILLE'), findsOneWidget);
      // The line that speaks of files and recovery copies is for adults.
      expect(find.textContaining('récupération'), findsNothing);
      expect(studio.menu.onLayers, isNull);
      expect(studio.menu.onExportSvg, isNull);
      expect(studio.menu.onOpen, isNotNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a level that no longer shows a tool or the view puts them away',
    (tester) async {
      final store = StudioOptionsStore.memory();
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(1280, 800));
      await studio.drag(const Offset(-80, -40), const Offset(60, 30));
      await studio.tap('tool-select');
      await studio.click(const Offset(-10, -5));
      expect(key('duplicateSelection'), findsOneWidget);
      await studio.tap('zoomIn');
      await studio.tap('zoomIn');
      expect(find.text('Toute la feuille'), findsNothing);

      await choose(studio, 'level-toddler');
      // « Choisir » is not one of the four: the pinceau takes over, and the
      // element is no longer chosen.
      expect(selectedTool(tester), StudioTool.brush);
      expect(key('duplicateSelection'), findsNothing);

      await choose(studio, 'level-full');
      // The sheet came back whole when its controls went away.
      expect(find.text('Toute la feuille'), findsOneWidget);
      expect(selectedTool(tester), StudioTool.brush);
      studio.expectCount(1);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a studio launched with the simplest interface draws with its colours and sizes',
    (tester) async {
      // The options already ask for it when the studio starts: nothing
      // changes them, so nothing but the start can fit the colour and size.
      final store = StudioOptionsStore.memory(
        const StudioOptions(level: InterfaceLevel.toddler),
      );
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(1280, 800));
      bool chosen(Finder control) =>
          tester
              .getSemantics(control)
              .flagsCollection
              .isSelected
              .toBoolOrNull() ??
          false;
      final colours = [
        for (final colour in simplePaintColors)
          // The button inside the swatch is what is announced.
          if (chosen(
            find.descendant(
              of: key('color-${colour.rgb.toRadixString(16).padLeft(6, '0')}'),
              matching: find.byType(IconButton),
            ),
          ))
            colour.rgb,
      ];
      expect(colours, hasLength(1));
      final sizes = [
        for (final size in ['brush-small', 'brush-medium', 'brush-large'])
          if (chosen(key(size))) size,
      ];
      expect(sizes, hasLength(1));
      await studio.drag(const Offset(-80, -40), const Offset(60, 30));
      final document = await studio.saved();
      addTearDown(document.dispose);
      // What is drawn is what the buttons show as chosen.
      expect(document.strokes.single.rgb, colours.single);
      expect(
        document.strokes.single.width,
        {
          'brush-small': 6.0,
          'brush-medium': 14.0,
          'brush-large': 30.0,
        }[sizes.single],
      );
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'without the layers, « Ordre » sends no element to another layer',
    (tester) async {
      final store = StudioOptionsStore.memory();
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(1280, 800));
      await studio.drag(const Offset(-80, -40), const Offset(60, 30));
      await studio.layers(() => studio.tap('addLayer'));
      // Two traits on the upper layer: the second can go behind the first.
      await studio.drag(const Offset(-200, 100), const Offset(-120, 160));
      await studio.drag(const Offset(-80, 60), const Offset(60, 120));
      await studio.tap('tool-select');
      await studio.click(const Offset(-10, 90));
      await studio.tap('selectionOrder');
      expect(key('sendSelectionToBack'), findsOneWidget);
      expect(key('moveSelectionLayerDown'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await store.change(store.value.copyWith(level: InterfaceLevel.child));
      await tester.pumpAndSettle();
      // The same element, on the upper layer; the sheet has changed its
      // place a little with the interface, so it is found again by its own
      // coordinates.
      final document = await studio.saved();
      addTearDown(document.dispose);
      final upper = document.strokes.last.points.first;
      await studio.tap('tool-select');
      await studio.click(studio.at(upper.x, upper.y));
      await studio.tap('selectionOrder');
      expect(key('sendSelectionToBack'), findsOneWidget);
      expect(key('moveSelectionLayerUp'), findsNothing);
      expect(key('moveSelectionLayerDown'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the options hear nothing for a moment after they open', (
    tester,
  ) async {
    // The dialog alone, where the clock of the test is exact: it opens
    // under the hand that has just pressed « Entrer » at the door.
    final store = StudioOptionsStore.memory();
    addTearDown(store.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (inner) {
            context = inner;
            return const Scaffold();
          },
        ),
      ),
    );
    final exits = <OptionsExit>[];
    showOptionsDialog(context, store: store).then(exits.add);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(key('optionsDialog'), findsOneWidget);
    // The second click of a double click, wherever it lands, and Entrée
    // still held: nothing changes, and the options stay open.
    for (final control in ['level-toddler', 'level-child']) {
      // In view, and under the pointer: only the moment refuses them.
      expect(key(control).hitTestable(), findsNothing);
      await tester.tap(key(control), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 20));
    expect(store.value, StudioOptions.defaults);
    expect(exits, isEmpty);
    // A moment later they answer the pointer; the key that is still held
    // closes nothing, however long it repeats.
    await tester.pump(OptionsDialog.settling);
    await tester.pump();
    expect(key('level-toddler').hitTestable(), findsOneWidget);
    for (var repeat = 0; repeat < 5; repeat++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(key('optionsDialog'), findsOneWidget);
    expect(exits, isEmpty);
    await tester.ensureVisible(key('optionSounds'));
    await tester.pumpAndSettle();
    await tester.tap(key('optionSounds'));
    await tester.pumpAndSettle();
    expect(store.value, const StudioOptions(sounds: false));
    // Pressed anew, Entrée is « Fermer », which holds the focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(exits, [OptionsExit.closed]);
  });

  testWidgets('three wrong results close the door, and the studio says so', (
    tester,
  ) async {
    final store = StudioOptionsStore.memory(const StudioOptions(guarded: true));
    addTearDown(store.dispose);
    final studio = StudioDriver(tester, options: store);
    await studio.start(size: const Size(1280, 800));
    await studio.tap('openOptions');
    for (var attempt = 0; attempt < 3; attempt++) {
      expect(key('adultGate'), findsOneWidget);
      await typeAtAdultGate(tester, wrongAdultGateAnswer(tester));
    }
    expect(key('adultGate'), findsNothing);
    expect(key('optionsDialog'), findsNothing);
    expect(find.textContaining('Trois résultats faux'), findsOneWidget);
    expect(store.value, const StudioOptions(guarded: true));
    // Asked again, the door opens to who knows.
    await studio.openOptions();
    expect(key('optionsDialog'), findsOneWidget);
    await closeOptions(tester);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'the « … » menu left open while the window widens does not lock the studio',
    (tester) async {
      final store = StudioOptionsStore.memory();
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(700, 600));
      await tester.tap(key('moreFileActions'));
      await tester.pumpAndSettle();
      expect(find.text('Options…'), findsOneWidget);
      // The window is made wider: the header no longer needs its menu, and
      // the button that opened it leaves with it.
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expect(key('moreFileActions'), findsNothing);
      // The menu is closed by a click beside it.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Options…'), findsNothing);
      // The studio draws, and its dialogs open.
      await studio.drag(const Offset(-80, -40), const Offset(60, 30));
      studio.expectCount(1);
      await studio.openOptions();
      expect(key('optionsDialog'), findsOneWidget);
      await closeOptions(tester);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'saving shows a tick on its button for a moment, in the quietest interface too',
    (tester) async {
      // No line of status and no sound: the tick is the only answer.
      final store = StudioOptionsStore.memory(
        const StudioOptions(level: InterfaceLevel.toddler, sounds: false),
      );
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(1280, 800));
      await studio.drag(const Offset(-80, -40), const Offset(60, 30));
      expect(key('savedTick'), findsNothing);
      final width = tester.getSize(key('saveProject')).width;
      await studio.tap('saveProject');
      expect(studio.files.projects, hasLength(1));
      expect(key('savedTick'), findsOneWidget);
      // The button did not change its size for it.
      expect(tester.getSize(key('saveProject')).width, width);
      await tester.pump(const Duration(seconds: 3));
      expect(key('savedTick'), findsNothing);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the simplest interface does not move its sheet, whatever the gesture',
    (tester) async {
      final store = StudioOptionsStore.memory(
        const StudioOptions(level: InterfaceLevel.toddler),
      );
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(1280, 800));
      final painter = find.descendant(
        of: key('drawingSurface'),
        matching: find.byType(CustomPaint),
      );
      (double, double, double) view() {
        final custom = tester.widget<CustomPaint>(painter.first);
        final viewport = (custom.painter! as dynamic).viewport;
        return (
          viewport.left as double,
          viewport.top as double,
          viewport.scale as double,
        );
      }

      final before = view();
      final centre = studio.sheetCenter;
      // The wheel, alone and with Ctrl.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: centre);
      addTearDown(mouse.removePointer);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: centre, scrollDelta: const Offset(0, 80)),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: centre, scrollDelta: const Offset(0, -80)),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(view(), before);
      // Two fingers on a trackpad.
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(pointer: 88, position: centre),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 88,
          position: centre,
          scale: 1.6,
          pan: const Offset(60, 40),
          panDelta: const Offset(60, 40),
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 88, position: centre),
      );
      await tester.pumpAndSettle();
      expect(view(), before);
      // Espace held while the mouse drags: a trait, not a move of the sheet.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await mouse.down(centre);
      await mouse.moveTo(centre + const Offset(80, 50));
      await mouse.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(view(), before);
      // The middle button.
      await mouse.down(centre);
      await mouse.up();
      final middle = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await middle.moveTo(centre + const Offset(-70, 30));
      await middle.up();
      await tester.pumpAndSettle();
      expect(view(), before);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the choices are kept for the next launch', (tester) async {
    final folder = Directory.systemTemp.createTempSync('color-options-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final storage = OptionsStorage(file: File('${folder.path}/options.json'));
    var store = StudioOptionsStore(StudioOptions.defaults, storage: storage);
    var studio = StudioDriver(tester, options: store);
    await studio.start(size: const Size(1280, 800));
    await studio.openOptions();
    for (final control in ['level-toddler', 'optionSounds', 'optionHoldFree']) {
      await tester.ensureVisible(key(control));
      await tester.pumpAndSettle();
      await tester.tap(key(control));
      await tester.pumpAndSettle();
    }
    const chosen = StudioOptions(
      level: InterfaceLevel.toddler,
      sounds: false,
      holdFree: true,
    );
    expect(store.value, chosen);
    // The file is written on the real clock, one step of the disk after the
    // other: the test lets both clocks turn until it is there.
    StudioOptions? kept;
    for (var turn = 0; turn < 200 && kept != chosen; turn++) {
      await tester.pump();
      kept = await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return storage.read();
      });
    }
    expect(kept, chosen);
    await tester.pumpAndSettle();
    expect(key('optionsUnsaved'), findsNothing);
    await closeOptions(tester);
    await studio.finish();
    store.dispose();

    // Another launch reads the file before its first frame.
    store = StudioOptionsStore(kept!, storage: storage);
    addTearDown(store.dispose);
    studio = StudioDriver(tester, options: store);
    await studio.start(size: const Size(1280, 800));
    expect(shownTools(tester), hasLength(4));
    expect(key('openProject'), findsNothing);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'choices that cannot be kept apply all the same, and the dialog says so',
    (tester) async {
      // A store without a file, as when Color finds no folder of its own.
      final store = StudioOptionsStore.memory();
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(1280, 800));
      await studio.openOptions();
      expect(key('optionsUnsaved'), findsNothing);
      await tester.tap(key('level-child'));
      await tester.pumpAndSettle();
      expect(key('optionsUnsaved'), findsOneWidget);
      await closeOptions(tester);
      expect(key('exportImage'), findsNothing);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the simplest interface keeps Comment faire ? and À propos in the options',
    (tester) async {
      final store = StudioOptionsStore.memory(
        const StudioOptions(level: InterfaceLevel.toddler),
      );
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(1280, 800));
      expect(key('showHelp'), findsNothing);

      await studio.openOptions();
      await tester.tap(key('optionsHelp'));
      await tester.pumpAndSettle();
      expect(key('optionsDialog'), findsNothing);
      expect(key('helpDialog'), findsOneWidget);
      // Only what this interface shows is explained.
      for (final tool in StudioTool.values) {
        expect(
          key('help-${tool.name}'),
          store.value.tools.contains(tool) ? findsOneWidget : findsNothing,
          reason: tool.name,
        );
      }
      for (final absent in ['help-picker', 'help-layers', 'help-big-sheet']) {
        expect(key(absent), findsNothing, reason: absent);
      }
      for (final present in ['help-film', 'help-print', 'help-options']) {
        expect(key(present), findsOneWidget, reason: present);
      }
      expect(find.text('1 à 4'), findsOneWidget);
      await tester.tap(key('closeHelp'));
      await tester.pumpAndSettle();

      await studio.openOptions();
      await tester.tap(key('optionsAbout'));
      await tester.pumpAndSettle();
      expect(find.text('Un dessin que tu peux retrouver.'), findsOneWidget);
      await tester.tap(find.text('Revenir au dessin'));
      await tester.pumpAndSettle();
      // Both dialogs gone, the studio draws again.
      await studio.drag(const Offset(-80, -40), const Offset(60, 30));
      final document = await studio.saved();
      addTearDown(document.dispose);
      expect(document.strokes, hasLength(1));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'in a narrow window the options wait in the « … » menu, and in the menu bar',
    (tester) async {
      final store = StudioOptionsStore.memory();
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(700, 600));
      expect(find.text('Color'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(StudioHeader),
          matching: key('openOptions'),
        ),
        findsNothing,
      );
      // The driver opens the « … » menu as a person would.
      await studio.openOptions();
      expect(key('optionsDialog'), findsOneWidget);
      await closeOptions(tester);

      // The menu bar of macOS opens them the same way: at once, without
      // a calculation unless the adult asked for one.
      studio.menu.onOptions!();
      await tester.pumpAndSettle();
      expect(key('adultGate'), findsNothing);
      expect(key('optionsDialog'), findsOneWidget);
      await tester.pump(OptionsDialog.settling);
      await tester.pump();
      // Asked again while they are open, the options do not open twice.
      studio.menu.onOptions?.call();
      await tester.pumpAndSettle();
      expect(key('optionsDialog'), findsOneWidget);
      await closeOptions(tester);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the simplest interface fits every window, at every size of letters',
    (tester) async {
      for (final size in const [
        Size(680, 520),
        Size(800, 600),
        Size(1100, 760),
        Size(1280, 850),
        Size(1700, 1000),
      ]) {
        for (final textScale in const [1.0, 1.5, 2.0]) {
          final store = StudioOptionsStore.memory(
            const StudioOptions(level: InterfaceLevel.toddler),
          );
          final studio = StudioDriver(
            tester,
            gallery: MemoryGallery(),
            options: store,
          );
          await studio.start(size: size, textScale: textScale);
          final where = '$size, text × $textScale';
          expect(tester.takeException(), isNull, reason: where);
          for (final tool in shownTools(tester)) {
            final rect = tester.getRect(key(tool.keyName));
            expect(rect.width, greaterThanOrEqualTo(48), reason: where);
            expect(rect.height, greaterThanOrEqualTo(48), reason: where);
          }
          expect(shownTools(tester), hasLength(4), reason: where);
          // The sheet keeps a real place in the window.
          final sheet = tester.getSize(key('drawingSurface'));
          expect(sheet.height, greaterThanOrEqualTo(96), reason: where);
          expect(sheet.width, greaterThanOrEqualTo(300), reason: where);
          await studio.drag(const Offset(-30, -20), const Offset(30, 20));
          expect(tester.takeException(), isNull, reason: where);
          await studio.finish();
          store.dispose();
        }
      }
    },
    skip: !available,
  );
}
