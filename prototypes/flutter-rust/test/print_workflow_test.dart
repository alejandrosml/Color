// SPDX-License-Identifier: MIT
// « Imprimer » : the studio prepares the picture of the sheet and hands it
// to the print panel of the system. Real Rust documents; the panel is a fake
// that keeps what it receives: nothing is ever printed here.
import 'dart:async';
import 'dart:io';

import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/studio_printer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_printer.dart';
import 'support/memory_files.dart';
import 'support/memory_gallery.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  String? message(WidgetTester tester) {
    final found = find.byKey(const Key('problemMessage'));
    return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
  }

  // A filled red rectangle with a blue outline, from (300, 200) to (700, 600).
  Future<void> rectangle(StudioDriver studio) async {
    await studio.tap('tool-rectangle');
    await studio.tap('paint-target-fill');
    await studio.tap('color-d75e56');
    await studio.drag(studio.at(300, 200), studio.at(700, 600));
    studio.expectCount(1);
  }

  testWidgets(
    'Imprimer hands the whole sheet to the panel: twice its size, opaque, as it is drawn',
    (tester) async {
      final printer = FakePrinter();
      final studio = StudioDriver(tester, printer: printer.call);
      await studio.start(size: const Size(1280, 820));
      await rectangle(studio);
      final statusBefore = studio.isDirty;
      expect(statusBefore, isTrue);

      await printAndWait(tester, printer);
      final request = printer.requests.single;
      // A sheet of 1200 by 800 units, at two pixels for one.
      expect(request.width, 2400);
      expect(request.height, 1600);
      expect(request.rgba, hasLength(2400 * 1600 * 4));
      // Inside the rectangle, its outline, and the paper beside it.
      expect(request.pixel(1000, 800), [0xd7, 0x5e, 0x56, 255]);
      expect(request.pixel(600, 800), [0x47, 0x7f, 0xb2, 255]);
      expect(request.pixel(100, 100), [255, 255, 255, 255]);
      expect(request.pixel(2399, 1599), [255, 255, 255, 255]);
      // Opaque everywhere: a printer has no transparency.
      for (var index = 3; index < request.rgba.length; index += 4096 * 4) {
        expect(request.rgba[index], 255);
      }
      // Before a first save the job is named as the drawing is.
      expect(request.jobName, 'Mon dessin');

      // The studio says so, and the project is exactly as it was.
      expect(
        find.text('Impression lancée · projet encore à enregistrer'),
        findsOneWidget,
      );
      expect(message(tester), isNull);
      studio.expectCount(1);
      expect(studio.isDirty, isTrue);
      await studio.tap('undo');
      studio.expectCount(0);
      expect(
        tester.widget<IconButton>(find.byKey(const Key('undo'))).onPressed,
        isNull,
        reason: 'Printing is not a step of the drawing.',
      );
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a saved drawing is printed under the name of its file, and stays saved',
    (tester) async {
      final printer = FakePrinter();
      final files = MemoryFiles()
        ..savePath = '/drawings/Le chat de Zoé.edupaint';
      final studio = StudioDriver(tester, files: files, printer: printer.call);
      await studio.start(size: const Size(1280, 820));
      await rectangle(studio);
      await studio.tap('saveProject');
      expect(studio.isDirty, isFalse);
      final saved = Uint8List.fromList(files.projects.values.single);

      await printAndWait(tester, printer);
      expect(printer.requests.single.jobName, 'Le chat de Zoé');
      expect(find.text('Impression lancée'), findsOneWidget);
      expect(studio.isDirty, isFalse);
      // Nothing was written anywhere by printing.
      expect(files.projects.values.single, saved);
      expect(files.png, isNull);
      expect(files.svg, isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('giving up in the panel changes nothing and says nothing', (
    tester,
  ) async {
    final printer = FakePrinter()..outcome = PrintOutcome.cancelled;
    final studio = StudioDriver(tester, printer: printer.call);
    await studio.start(size: const Size(1280, 820));
    await rectangle(studio);
    // The copy of recovery is written: the sentence of the studio is at rest
    // before the panel opens.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final sentence = find.textContaining('projet à enregistrer');
    expect(sentence, findsOneWidget);
    final before = tester.widget<Text>(sentence).data;
    await printAndWait(tester, printer);
    expect(printer.requests, hasLength(1));
    expect(tester.widget<Text>(sentence).data, before);
    expect(find.textContaining('Impression'), findsNothing);
    expect(message(tester), isNull);
    studio.expectCount(1);
    expect(studio.isDirty, isTrue);
    // The studio answers again at once.
    await studio.tap('tool-stroke');
    await studio.click(studio.at(100, 100));
    studio.expectCount(2);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'without a printer, or without a way to reach one, the studio says so in plain words',
    (tester) async {
      final printer = FakePrinter()..outcome = PrintOutcome.noPrinter;
      final studio = StudioDriver(tester, printer: printer.call);
      await studio.start(size: const Size(1280, 820));
      await rectangle(studio);
      await printAndWait(tester, printer);
      expect(
        message(tester),
        'Color ne trouve pas d’imprimante sur cet ordinateur. Demande à un adulte d’en installer une, puis recommence.',
      );
      // A notice, not a failure: nothing to open for details.
      expect(find.byKey(const Key('showProblemDetails')), findsNothing);
      expect(find.textContaining('Impression lancée'), findsNothing);

      printer.outcome = PrintOutcome.unavailable;
      await printAndWait(tester, printer);
      expect(
        message(tester),
        'Cette version de Color ne sait pas imprimer sur cet ordinateur. Tu peux exporter ton dessin en image, puis imprimer l’image.',
      );
      studio.expectCount(1);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a refusal of the system is told, with its details, and the drawing is kept',
    (tester) async {
      final printer = FakePrinter()
        ..failure = PlatformException(
          code: 'PRINT_FAILED',
          message: 'Le système a refusé l’impression.',
        );
      final studio = StudioDriver(tester, printer: printer.call);
      await studio.start(size: const Size(1280, 820));
      await rectangle(studio);
      await printAndWait(tester, printer);
      expect(message(tester), 'Le dessin n’a pas pu être imprimé.');
      expect(find.byKey(const Key('showProblemDetails')), findsOneWidget);
      expect(find.textContaining('Impression lancée'), findsNothing);
      studio.expectCount(1);
      // And the studio is not left waiting.
      printer
        ..failure = null
        ..outcome = PrintOutcome.sent;
      await printAndWait(tester, printer);
      expect(printer.requests, hasLength(2));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'while the image is prepared the studio says so, and takes no other command',
    (tester) async {
      final printer = FakePrinter();
      final studio = StudioDriver(tester, printer: printer.call);
      await studio.start(size: const Size(1280, 820));
      await rectangle(studio);
      await tester.tap(find.byKey(const Key('printDrawing')));
      // One frame: the sentence is on the sheet before the engine starts on
      // the image, and nothing has reached the printer yet.
      await tester.pump();
      expect(
        find.text('Préparation de ton dessin pour l’imprimante…'),
        findsOneWidget,
      );
      expect(printer.requests, isEmpty);
      expect(studio.menu.onSave, isNull);
      expect(studio.menu.onPrint, isNull);
      // Then the image arrives, the sentence goes and the studio is free.
      for (var turn = 0; turn < 400 && printer.requests.isEmpty; turn++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(printer.requests, hasLength(1));
      expect(
        find.text('Préparation de ton dessin pour l’imprimante…'),
        findsNothing,
      );
      expect(studio.menu.onSave, isNotNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'while the panel is open the studio waits: no drawing, no second panel, no exit',
    (tester) async {
      final printer = FakePrinter()..panel = Completer<void>();
      final studio = StudioDriver(tester, printer: printer.call);
      await studio.start(size: const Size(1280, 820));
      await rectangle(studio);
      await printAndWait(tester, printer);
      expect(printer.requests, hasLength(1));

      // The drawing shows behind the panel: no veil is left on the sheet.
      expect(find.textContaining('Préparation de ton dessin'), findsNothing);
      // The actions of the header wait.
      for (final key in ['newProject', 'openProject', 'exportImage']) {
        expect(
          tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed,
          isNull,
          reason: key,
        );
      }
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('printDrawing')))
            .onPressed,
        isNull,
      );
      expect(studio.menu.onPrint, isNull);
      // The sheet does not take a shape, and the keys do not print again.
      await studio.drag(studio.at(800, 100), studio.at(1000, 300));
      studio.expectCount(1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      // Long enough for a second image to be prepared and handed over, had
      // the keys been heard: a first one takes a few of these turns.
      for (var turn = 0; turn < 40; turn++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(printer.requests, hasLength(1));
      expect(find.textContaining('Préparation de ton dessin'), findsNothing);
      // Quitting waits for the panel too.
      final exit = await tester.binding.handleRequestAppExit();
      expect(exit.name, 'cancel');

      // The panel closes: everything answers again.
      printer.panel!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Impression lancée'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('printDrawing')))
            .onPressed,
        isNotNull,
      );
      expect(studio.menu.onPrint, isNotNull);
      await studio.drag(studio.at(800, 100), studio.at(1000, 300));
      studio.expectCount(2);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the keys and the menu print too, in the big sheet as well', (
    tester,
  ) async {
    final printer = FakePrinter();
    final studio = StudioDriver(tester, printer: printer.call);
    await studio.start(size: const Size(1280, 820));
    await rectangle(studio);

    Future<void> keys(LogicalKeyboardKey modifier) async {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(modifier);
    }

    await printAndWait(
      tester,
      printer,
      press: () => keys(LogicalKeyboardKey.controlLeft),
    );
    await printAndWait(
      tester,
      printer,
      press: () => keys(LogicalKeyboardKey.metaLeft),
    );
    await printAndWait(
      tester,
      printer,
      // The command starts and is not waited for: it needs the frames
      // that are pumped afterwards.
      press: () async {
        studio.menu.onPrint!();
      },
    );
    expect(printer.requests, hasLength(3));

    // With the panels put away there is no button: the keys remain.
    await studio.tap('bigSheet');
    expect(find.byKey(const Key('printDrawing')), findsNothing);
    await printAndWait(
      tester,
      printer,
      press: () => keys(LogicalKeyboardKey.controlLeft),
    );
    expect(printer.requests, hasLength(4));
    expect(printer.requests.last.width, 2400);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'in the smallest window with large letters Imprimer waits in the « … » menu',
    (tester) async {
      final printer = FakePrinter();
      final studio = StudioDriver(
        tester,
        gallery: MemoryGallery(),
        printer: printer.call,
      );
      await studio.start(size: const Size(680, 520), textScale: 2);
      // Not on the line of the header…
      expect(find.byKey(const Key('printDrawing')), findsNothing);
      // …but one press away, with what else waits there.
      await tester.tap(find.byKey(const Key('moreFileActions')));
      await tester.pumpAndSettle();
      expect(find.text('Imprimer…'), findsOneWidget);
      expect(find.text('Mes dessins'), findsOneWidget);
      expect(find.text('Dessiner sur une image…'), findsOneWidget);
      await printAndWait(tester, printer);
      expect(printer.requests.single.width, 2400);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'what is printed is what is seen: coloured paper and visible layers only',
    (tester) async {
      final printer = FakePrinter();
      final studio = StudioDriver(tester, printer: printer.call);
      await studio.start(size: const Size(1280, 820));
      // A coloured sheet, a rectangle on the first layer, another on a second.
      await studio.tap('tool-fill');
      await studio.tap('color-eebf4e');
      await studio.click(studio.at(1000, 100));
      await rectangle(studio);
      await studio.layers(() => studio.tap('addLayer'));
      await studio.tap('tool-rectangle');
      await studio.drag(studio.at(800, 200), studio.at(1100, 600));
      studio.expectCount(2);

      await printAndWait(tester, printer);
      var request = printer.requests.last;
      expect(request.pixel(100, 100), [0xee, 0xbf, 0x4e, 255]);
      expect(request.pixel(1000, 800), [0xd7, 0x5e, 0x56, 255]);
      expect(request.pixel(1900, 800), [0xd7, 0x5e, 0x56, 255]);

      // The second layer hidden: its rectangle is not printed either.
      await studio.layers(() => studio.tap('layer-visible-1'));
      await printAndWait(tester, printer);
      request = printer.requests.last;
      expect(request.pixel(1900, 800), [0xee, 0xbf, 0x4e, 255]);
      expect(request.pixel(1000, 800), [0xd7, 0x5e, 0x56, 255]);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a portrait sheet is handed over upright, and a first click that waits is not printed',
    (tester) async {
      final printer = FakePrinter();
      final studio = StudioDriver(tester, printer: printer.call);
      await studio.start(size: const Size(1280, 820));
      await studio.newSheet('portrait');
      await studio.tap('tool-line');
      // The start of a line made of two clicks: a mark on the screen only.
      await tester.tapAt(studio.sheetCenter);
      await tester.pumpAndSettle();
      await printAndWait(tester, printer);
      final request = printer.requests.single;
      expect(request.height, greaterThan(request.width));
      expect(request.pixel(request.width ~/ 2, request.height ~/ 2), [
        255,
        255,
        255,
        255,
      ]);
      // The sheet of the studio and the image have the same shape.
      final document = await studio.saved();
      try {
        expect(request.width, document.width * 2);
        expect(request.height, document.height * 2);
        expect(document.strokes, isEmpty);
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a studio left with the real channel, which nothing answers here, says that it cannot print',
    (tester) async {
      // No printer is injected: the request goes to the channel of the
      // runners, absent from a widget test, as on a system without one.
      final files = MemoryFiles();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 820);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        EduPaintApp(files: files, recoveryStorage: MemoryRecovery()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('printDrawing')));
      for (
        var attempt = 0;
        attempt < 400 && message(tester) == null;
        attempt++
      ) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(
        message(tester),
        startsWith('Cette version de Color ne sait pas imprimer'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );
}
