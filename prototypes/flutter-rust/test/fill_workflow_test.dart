// SPDX-License-Identifier: MIT
// Real Rust documents; only dialogs' destinations and storage are in memory.
import 'dart:io';

import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  testWidgets(
    'one click of the paint pot fills a hollow shape, in one undoable step',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-rectangle');
      await studio.drag(studio.at(200, 200), studio.at(500, 450));
      await studio.tap('tool-ellipse');
      await studio.drag(studio.at(650, 200), studio.at(950, 450));
      await studio.tap('saveProject');

      await studio.tap('tool-fill');
      expect(find.text('Épaisseur'), findsNothing);
      expect(
        find.textContaining(
          'Touche une forme ou une zone de ta page pour la remplir',
        ),
        findsOneWidget,
      );
      await studio.tap('color-eebf4e');
      // The middle of a hollow rectangle: Choisir would find nothing there.
      await studio.click(studio.at(350, 325));
      expect(studio.isDirty, isTrue);
      await studio.tap('color-9385bc');
      // Inside the oval, well away from its outline.
      await studio.click(studio.at(800, 325));
      // The corner of the oval's box is outside the oval: that is the sheet.
      studio.expectCount(2);

      var document = await studio.saved();
      try {
        final rectangle = document.strokes[0];
        final oval = document.strokes[1];
        expect(rectangle.fillRgb, 0xeebf4e);
        expect(oval.fillRgb, 0x9385bc);
        // Outlines keep their colour and their width.
        expect(rectangle.rgb, 0x477fb2);
        expect(oval.rgb, 0x477fb2);
        expect(rectangle.width, 12);
        expect(document.paperRgb, whitePaper);
        // Filling shapes needs no new project version.
        expect(document.exportProject()[8], 2);
      } finally {
        document.dispose();
      }
      final exported = await studio.svg();
      expect(exported, contains('fill="#eebf4e" stroke="#477fb2"'));
      expect(exported, contains('fill="#9385bc" stroke="#477fb2"'));

      // The same colour again changes nothing: no step is added.
      await studio.click(studio.at(800, 325));
      await studio.tap('undo');
      document = await studio.saved();
      try {
        expect(document.strokes[0].fillRgb, 0xeebf4e);
        expect(document.strokes[1].fillRgb, isNull);
      } finally {
        document.dispose();
      }
      await studio.tap('undo');
      expect(await studio.svg(), isNot(contains('#eebf4e')));
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a trait, a line, a text and a stamp take the colour of the paint pot',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stroke');
      await studio.drag(studio.at(100, 100), studio.at(300, 150));
      await studio.tap('tool-line');
      await studio.drag(studio.at(100, 300), studio.at(300, 300));
      await studio.addText('mot', x: 500, y: 100);
      await studio.tap('tool-stamp');
      await studio.click(studio.at(900, 600));
      studio.expectCount(4);

      await studio.tap('tool-fill');
      await studio.tap('color-d75e56');
      await studio.click(studio.at(200, 125));
      await studio.click(studio.at(200, 300));
      await studio.click(studio.at(520, 120));
      await studio.click(studio.at(900, 600));
      final document = await studio.saved();
      try {
        expect(document.strokes.map((object) => object.rgb).toSet(), {
          0xd75e56,
        });
        expect(document.strokes.map((object) => object.fillRgb).toSet(), {
          null,
        });
        // Sizes are untouched: the text keeps its letters, the stamp its box.
        expect(document.strokes[2].width, 56);
        expect(document.strokes[2].text, 'mot');
        expect(document.strokes[3].width, 1);
      } finally {
        document.dispose();
      }
      // Four elements recoloured: four steps.
      for (var step = 0; step < 4; step++) {
        await studio.tap('undo');
      }
      expect(await studio.svg(), isNot(contains('#d75e56')));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'on the bare sheet the pot colours the paper, in the project and both images',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-rectangle');
      await studio.drag(studio.at(200, 200), studio.at(500, 450));
      final white = await studio.svg();
      await studio.tap('tool-fill');
      await studio.tap('color-e69976');
      await studio.click(studio.at(900, 600));
      studio.expectCount(1);
      expect(studio.isDirty, isTrue);

      final exported = await studio.svg();
      expect(
        exported,
        contains('<rect width="100%" height="100%" fill="#e69976"/>'),
      );
      final png = await studio.png();
      expect(await studio.pixel(png, 900, 600), [0xe6, 0x99, 0x76, 255]);
      // The hollow rectangle lets the paper show through.
      expect(await studio.pixel(png, 350, 325), [0xe6, 0x99, 0x76, 255]);
      expect(await studio.pixel(png, 200, 325), [0x47, 0x7f, 0xb2, 255]);

      var document = await studio.saved();
      try {
        expect(document.paperRgb, 0xe69976);
        expect(document.exportProject()[8], 4);
        expect(document.strokes.single.fillRgb, isNull);
      } finally {
        document.dispose();
      }
      // The sheet shown on screen has the same colour as the export.
      final sheet = find.descendant(
        of: find.byKey(const Key('drawingSurface')),
        matching: find.byType(CustomPaint),
      );
      final dynamic painter = tester.widget<CustomPaint>(sheet.first).painter;
      expect(painter.paperRgb, 0xe69976);

      await studio.tap('undo');
      expect(await studio.svg(), white);
      document = await studio.saved();
      try {
        expect(document.paperRgb, whitePaper);
        expect(document.exportProject()[8], 2);
      } finally {
        document.dispose();
      }
      await studio.tap('redo');
      expect(await studio.svg(), exported);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the pot colours what is seen in front, and a new sheet is white again',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-rectangle');
      await studio.drag(studio.at(200, 200), studio.at(600, 500));
      await studio.layers(() => studio.tap('addLayer'));
      await studio.tap('tool-ellipse');
      await studio.drag(studio.at(400, 300), studio.at(800, 600));
      await studio.tap('tool-fill');
      await studio.tap('color-78a66f');
      // Where both overlap, the oval of the upper layer is in front.
      await studio.click(studio.at(500, 400));
      await studio.tap('color-eebf4e');
      await studio.click(studio.at(1000, 100));
      var document = await studio.saved();
      try {
        expect(document.strokes[0].fillRgb, isNull);
        expect(document.strokes[1].fillRgb, 0x78a66f);
        expect(document.paperRgb, 0xeebf4e);
      } finally {
        document.dispose();
      }
      // With the upper layer hidden the same click reaches the rectangle.
      await studio.layers(() => studio.tap('layer-visible-1'));
      await studio.tap('tool-fill');
      await studio.tap('color-c96d93');
      await studio.click(studio.at(500, 400));
      document = await studio.saved();
      try {
        expect(document.strokes[0].fillRgb, 0xc96d93);
        expect(document.strokes[1].fillRgb, 0x78a66f);
      } finally {
        document.dispose();
      }

      await studio.newSheet('landscape');
      studio.expectCount(0);
      expect(
        await studio.svg(),
        contains('<rect width="100%" height="100%" fill="#ffffff"/>'),
      );
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('recovery and reopening keep the colour of the sheet', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-fill');
    await studio.tap('color-9385bc');
    await studio.click();
    final before = await studio.svg();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(studio.recovery.bytes, isNotNull);
    expect(studio.recovery.bytes![8], 4);
    await studio.finish();

    await tester.pumpWidget(
      EduPaintApp(files: studio.files, recoveryStorage: studio.recovery),
    );
    await waitForPreparedOpen(tester, allowRecoveryDecision: true);
    await studio.tap('restoreRecovery');
    expect(await studio.svg(), before);
    await studio.tap('saveProject');
    await studio.newSheet('landscape');
    studio.files.openPath = studio.files.savePath;
    await studio.tap('openProject');
    expect(await studio.svg(), before);
    final png = await studio.png();
    expect(await studio.pixel(png, 10, 10), [0x93, 0x85, 0xbc, 255]);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'under an image the paper cannot be seen: the pot says so and changes nothing',
    (tester) async {
      // A 32 × 24 photograph with one text, written by the fixture generator.
      final bytes = File('test/fixtures/project-open/text-on-image-v4.edupaint')
          .readAsBytesSync();
      final files = MemoryFiles()..openPath = '/drawings/photo.edupaint';
      files.projects[files.openPath!] = bytes;
      final studio = StudioDriver(tester, files: files);
      await studio.start();
      await studio.tap('openProject');
      studio.expectCount(1);
      await studio.tap('tool-fill');
      await studio.tap('color-78a66f');
      await studio.click(studio.at(30, 22, width: 32, height: 24));
      expect(
        find.textContaining('Une image couvre toute la feuille'),
        findsOneWidget,
      );
      expect(studio.isDirty, isFalse);
      final document = RustDocument.fromProject(bytes);
      try {
        // The fixture's text, written in red, can still take the colour.
        final text = document.strokes.single;
        await studio.click(
          studio.at(
            (left(text) + right(text)) / 2,
            (top(text) + bottom(text)) / 2,
            width: 32,
            height: 24,
          ),
        );
      } finally {
        document.dispose();
      }
      expect(studio.isDirty, isTrue);
      // Read on the sheet itself: preparing an export of a photograph runs
      // in a worker, which the workflow tests of images already cover.
      final dynamic painter = tester
          .widget<CustomPaint>(
            find
                .descendant(
                  of: find.byKey(const Key('drawingSurface')),
                  matching: find.byType(CustomPaint),
                )
                .first,
          )
          .painter;
      expect(painter.strokes.single.data.rgb, 0x78a66f);
      expect(painter.paperRgb, whitePaper);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );
}
