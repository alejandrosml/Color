// SPDX-License-Identifier: MIT
// Real Rust documents; only dialogs' destinations and storage are in memory.
import 'dart:io';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  bool armed(WidgetTester tester) => tester
      .widget<IconButton>(find.byKey(const Key('pickPaintColor')))
      .isSelected!;

  // A rectangle with a red outline and a yellow inside, at 200..500 × 200..450.
  Future<void> twoColourRectangle(StudioDriver studio) async {
    await studio.tap('tool-rectangle');
    await studio.tap('color-d75e56');
    await studio.tap('paint-target-fill');
    await studio.tap('color-eebf4e');
    await studio.drag(studio.at(200, 200), studio.at(500, 450));
  }

  // The colour that the brush draws with now: a short trait is drawn at the
  // bottom of the sheet and read back from the saved project.
  Future<int> brushColour(StudioDriver studio) async {
    await studio.tap('tool-stroke');
    await studio.drag(studio.at(100, 700), studio.at(160, 720));
    final document = await studio.saved();
    try {
      return document.strokes.last.rgb;
    } finally {
      document.dispose();
    }
  }

  testWidgets(
    'the pipette takes the colour under the pointer and gives the tool back',
    (tester) async {
      final studio = StudioDriver(tester);
      // A window tall enough for the line of recent colours.
      await studio.start(size: const Size(1100, 1000));
      await twoColourRectangle(studio);
      await studio.tap('saveProject');
      await studio.tap('tool-stroke');
      await studio.tap('color-477fb2');
      expect(armed(tester), isFalse);

      await studio.tap('pickPaintColor');
      expect(armed(tester), isTrue);
      expect(
        find.textContaining('Clique sur une couleur de ton dessin'),
        findsOneWidget,
      );
      // Inside the rectangle: its inside colour, not its outline.
      await studio.click(studio.at(350, 325));
      expect(armed(tester), isFalse);
      // Reading a colour is not an edit.
      studio.expectCount(1);
      expect(studio.isDirty, isFalse);
      expect(find.textContaining('Soleil'), findsWidgets);
      expect(
        find.byKey(const Key('recent-paint-color-eebf4e')),
        findsOneWidget,
      );
      // The brush is still the tool, and now draws in that colour.
      expect(await brushColour(studio), 0xeebf4e);

      await studio.tap('pickPaintColor');
      // On the border the pipette reads the outline.
      await studio.click(studio.at(200, 325));
      expect(await brushColour(studio), 0xd75e56);

      await studio.tap('pickPaintColor');
      // On the bare sheet: the colour of the paper.
      await studio.click(studio.at(900, 100));
      expect(await brushColour(studio), whitePaper);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'Échap, the same button or another tool put the pipette away, colour unchanged',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await twoColourRectangle(studio);
      await studio.tap('tool-stroke');
      await studio.tap('color-477fb2');

      await studio.tap('pickPaintColor');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(armed(tester), isFalse);

      await studio.tap('pickPaintColor');
      await studio.tap('pickPaintColor');
      expect(armed(tester), isFalse);

      await studio.tap('pickPaintColor');
      await studio.tap('tool-line');
      expect(armed(tester), isFalse);

      // A click outside the sheet keeps the pipette ready.
      await studio.tap('pickPaintColor');
      await studio.click(studio.at(-80, 400));
      expect(armed(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await brushColour(studio), 0x477fb2);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a chosen element takes the picked colour at once, inside or outline',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await twoColourRectangle(studio);
      // An oval with a green outline and a blue inside.
      await studio.tap('tool-ellipse');
      await studio.tap('color-78a66f');
      await studio.tap('paint-target-fill');
      await studio.tap('color-477fb2');
      await studio.drag(studio.at(650, 200), studio.at(950, 450));
      studio.expectCount(2);

      // Choose the oval, then take the yellow of the rectangle for its inside.
      await studio.tap('tool-select');
      await studio.click(studio.at(800, 200));
      await studio.tap('paint-target-fill');
      await studio.tap('pickPaintColor');
      await studio.click(studio.at(350, 325));
      // The oval is still the chosen element, and its inside is yellow.
      expect(find.byKey(const Key('applySelectionStyle')), findsNothing);
      var document = await studio.saved();
      try {
        expect(document.strokes[1].fillRgb, 0xeebf4e);
        expect(document.strokes[1].rgb, 0x78a66f);
      } finally {
        document.dispose();
      }

      // Then the red of the rectangle's border for its outline.
      await studio.tap('paint-target-stroke');
      await studio.tap('pickPaintColor');
      await studio.click(studio.at(200, 325));
      document = await studio.saved();
      try {
        expect(document.strokes[1].rgb, 0xd75e56);
        expect(document.strokes[1].fillRgb, 0xeebf4e);
        // The rectangle that lent its colours is untouched.
        expect(document.strokes[0].rgb, 0xd75e56);
        expect(document.strokes[0].fillRgb, 0xeebf4e);
      } finally {
        document.dispose();
      }
      await studio.tap('undo');
      document = await studio.saved();
      try {
        expect(document.strokes[1].rgb, 0x78a66f);
        expect(document.strokes[1].fillRgb, 0xeebf4e);
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'with an element chosen, the pipette on bare paper changes nothing and stays ready',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await twoColourRectangle(studio);
      await studio.tap('tool-select');
      await studio.click(studio.at(350, 325));
      await studio.tap('pickPaintColor');
      // A click that misses every element: the chosen rectangle must not
      // turn the colour of the paper.
      await studio.click(studio.at(900, 100));
      expect(
        tester.widget<Text>(find.byKey(const Key('problemMessage'))).data,
        'Clique sur un élément de ton dessin pour reprendre sa couleur.',
      );
      expect(armed(tester), isTrue);
      final document = await studio.saved();
      try {
        expect(document.strokes.single.rgb, 0xd75e56);
        expect(document.strokes.single.fillRgb, 0xeebf4e);
      } finally {
        document.dispose();
      }
      // Nothing to undo but the rectangle itself.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await studio.tap('undo');
      studio.expectCount(0);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the pipette sees stamps, texts, coloured paper and only visible layers',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-fill');
      await studio.tap('color-e69976');
      await studio.click(studio.at(1000, 100));
      await studio.tap('tool-stamp');
      await studio.tap('color-9385bc');
      await studio.click(studio.at(300, 300));
      await studio.layers(() => studio.tap('addLayer'));
      await studio.tap('color-388778');
      await studio.addText('mot', x: 700, y: 300);

      await studio.tap('color-33484d');
      await studio.tap('pickPaintColor');
      await studio.click(studio.at(300, 300));
      expect(await brushColour(studio), 0x9385bc);
      await studio.tap('pickPaintColor');
      await studio.click(studio.at(720, 320));
      expect(await brushColour(studio), 0x388778);
      await studio.tap('pickPaintColor');
      await studio.click(studio.at(1100, 400));
      expect(await brushColour(studio), 0xe69976);

      // The text's layer hidden: the paper is what is seen there.
      await studio.layers(() => studio.tap('layer-visible-1'));
      await studio.tap('color-33484d');
      await studio.tap('pickPaintColor');
      await studio.click(studio.at(720, 320));
      expect(await brushColour(studio), 0xe69976);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'over a photograph the pipette asks for a drawn element and stays ready',
    (tester) async {
      final bytes = File('test/fixtures/project-open/text-on-image-v4.edupaint')
          .readAsBytesSync();
      final files = MemoryFiles()..openPath = '/drawings/photo.edupaint';
      files.projects[files.openPath!] = bytes;
      final studio = StudioDriver(tester, files: files);
      await studio.start();
      await studio.tap('openProject');
      await studio.tap('pickPaintColor');
      await studio.click(studio.at(30, 22, width: 32, height: 24));
      expect(
        find.textContaining('Clique sur un élément de ton dessin'),
        findsOneWidget,
      );
      expect(armed(tester), isTrue);
      // The red text of the fixture answers.
      await studio.click(studio.at(11, 6.75, width: 32, height: 24));
      expect(armed(tester), isFalse);
      expect(find.textContaining('Coquelicot'), findsWidgets);
      expect(studio.isDirty, isFalse);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the pipette is a full-size button in a small window too', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start(size: const Size(680, 520), textScale: 1.5);
    final button = find.byKey(const Key('pickPaintColor'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(
      find.bySemanticsLabel('Pipette : reprendre une couleur du dessin'),
      findsOneWidget,
    );
    await studio.tap('pickPaintColor');
    expect(armed(tester), isTrue);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);
}
