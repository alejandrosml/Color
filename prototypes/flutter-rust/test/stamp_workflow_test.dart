// SPDX-License-Identifier: MIT
// Real Rust documents; only dialogs' destinations and storage are in memory.
import 'dart:io';

import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/stamp_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  testWidgets(
    'a click poses the chosen stamp at the chosen size, in one undoable step',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stamp');
      // « How big? » is answered by three sizes, not by the outline slider.
      expect(find.text('Épaisseur'), findsNothing);
      expect(find.byKey(const Key('chooseStamp')), findsOneWidget);
      expect(find.byKey(const Key('size-medium')), findsOneWidget);

      await studio.click();
      studio.expectCount(1);
      expect(studio.isDirty, isTrue);
      final exported = await studio.svg();
      // The star's own outline, tinted with the current colour.
      expect(exported, contains('<path d="M 50 10 L 60.58 38.44'));
      expect(exported, contains('fill="#477fb2"'));
      expect(exported, contains('scale(1.5 1.5)'));
      final document = await studio.saved();
      try {
        final stamp = document.strokes.single;
        expect(stamp.kind, VectorKind.stamp);
        expect(stamp.stamp, 0);
        expect(stamp.rgb, 0x477fb2);
        expect(stamp.width, 1);
        expect(stamp.text, isNull);
        // A medium stamp measures 150 units, centred on the pointer.
        expect(left(stamp), closeTo(525, .5));
        expect(top(stamp), closeTo(325, .5));
        expect(right(stamp) - left(stamp), closeTo(150, .01));
        expect(bottom(stamp) - top(stamp), closeTo(150, .01));
        expect(document.exportProject()[8], 4);
      } finally {
        document.dispose();
      }
      await studio.tap('undo');
      studio.expectCount(0);
      await studio.tap('redo');
      studio.expectCount(1);
      expect(await studio.svg(), exported);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the chooser shows the whole catalogue; cancelling keeps the current stamp',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stamp');
      await studio.tap('chooseStamp');
      expect(find.byKey(const Key('stampDialog')), findsOneWidget);
      expect(find.text('Choisis un tampon'), findsOneWidget);
      final catalog = StampCatalog.instance;
      expect(catalog.stamps, hasLength(24));
      for (final stamp in catalog.stamps) {
        expect(
          find.byKey(Key('stamp-${stamp.key}'), skipOffstage: false),
          findsOneWidget,
          reason: stamp.key,
        );
      }
      // The current stamp is announced as selected.
      expect(
        tester
            .getSemantics(find.byKey(const Key('stamp-etoile')))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
      // Nothing is posed by choosing: the sheet is still empty.
      await studio.tap('stamp-chat');
      expect(find.byKey(const Key('stampDialog')), findsNothing);
      studio.expectCount(0);
      expect(studio.isDirty, isFalse);
      await studio.click();

      await studio.tap('chooseStamp');
      await studio.tap('cancelStamp');
      await studio.tap('chooseStamp');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stampDialog')), findsNothing);
      await studio.click(studio.at(200, 200));

      final document = await studio.saved();
      try {
        expect(document.strokes, hasLength(2));
        // Identifiers are positions in the catalogue and live in the files.
        expect(catalog[8]!.key, 'chat');
        expect(document.strokes.map((object) => object.stamp), [8, 8]);
      } finally {
        document.dispose();
      }
      // The button names the current stamp for screen readers.
      expect(
        find.bySemanticsLabel('Tampon Chat · choisir un autre tampon'),
        findsOneWidget,
      );
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the three sizes and the colour are applied, and stamps stay on the sheet',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('color-d75e56');
      await studio.tap('tool-stamp');
      await studio.tap('size-small');
      await studio.click(studio.at(300, 200));
      await studio.tap('size-large');
      await studio.click(studio.at(900, 600));
      await studio.tap('size-medium');
      // Near a corner the stamp is pushed back whole onto the sheet.
      await studio.click(studio.at(5, 5));
      await studio.click(studio.at(1195, 795));
      studio.expectCount(4);
      final document = await studio.saved();
      try {
        final stamps = document.strokes;
        expect(stamps.map((object) => object.rgb).toSet(), {0xd75e56});
        expect(left(stamps[0]), closeTo(255, .5));
        expect(top(stamps[0]), closeTo(155, .5));
        expect(right(stamps[0]) - left(stamps[0]), closeTo(90, .01));
        expect(left(stamps[1]), closeTo(780, .5));
        expect(top(stamps[1]), closeTo(480, .5));
        expect(bottom(stamps[1]) - top(stamps[1]), closeTo(240, .01));
        expect(left(stamps[2]), 0);
        expect(top(stamps[2]), 0);
        expect(right(stamps[2]), closeTo(150, .01));
        expect(right(stamps[3]), 1200);
        expect(bottom(stamps[3]), 800);
        expect(left(stamps[3]), closeTo(1050, .01));
      } finally {
        document.dispose();
      }
      // The shades of a stamp derive from its colour, as in the catalogue.
      final exported = await studio.svg();
      expect(exported, contains('fill="#d75e56"'));
      expect(exported, contains('fill="#efbebb"'));
      expect(exported, contains('stroke="#293d4b"'));
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'dragging sizes a square stamp, a tiny drag is a click, Escape abandons',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stamp');
      // The longer side of the drag wins: a stamp keeps its proportions.
      await studio.drag(studio.at(100, 100), studio.at(400, 300));
      studio.expectCount(1);
      // Towards the upper left as well.
      await studio.drag(studio.at(900, 700), studio.at(700, 580));
      studio.expectCount(2);
      // A hand that trembles while clicking still gets the chosen size.
      await studio.drag(studio.at(700, 300), studio.at(704, 303));
      studio.expectCount(3);

      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(200, 600),
      );
      await gesture.moveTo(studio.sheetCenter + studio.at(350, 700));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await gesture.up();
      await tester.pumpAndSettle();
      studio.expectCount(3);

      final document = await studio.saved();
      try {
        final stamps = document.strokes;
        expect(left(stamps[0]), closeTo(100, .5));
        expect(top(stamps[0]), closeTo(100, .5));
        expect(right(stamps[0]), closeTo(400, .5));
        expect(bottom(stamps[0]), closeTo(400, .5));
        expect(left(stamps[1]), closeTo(700, .5));
        expect(top(stamps[1]), closeTo(500, .5));
        expect(right(stamps[1]), closeTo(900, .5));
        expect(bottom(stamps[1]), closeTo(700, .5));
        expect(left(stamps[2]), closeTo(625, .5));
        expect(top(stamps[2]), closeTo(225, .5));
        expect(right(stamps[2]) - left(stamps[2]), closeTo(150, .01));
        for (final stamp in stamps) {
          expect(
            right(stamp) - left(stamp),
            closeTo(bottom(stamp) - top(stamp), .01),
          );
        }
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a chosen stamp answers by its whole box, changes colour, is copied, moved and erased',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stamp');
      await studio.tap('size-large');
      await studio.click();
      await studio.tap('tool-select');
      // A corner of the box, where the star is not painted, still selects it.
      await studio.click(studio.at(486, 286));
      expect(
        find.text('Glisse pour déplacer. Clique une couleur pour le colorier.'),
        findsOneWidget,
      );
      // A chosen stamp keeps its size and its drawing: neither control shows.
      expect(find.text('Épaisseur'), findsNothing);
      expect(find.byKey(const Key('chooseStamp')), findsNothing);
      expect(find.byKey(const Key('size-medium')), findsNothing);
      expect(find.byKey(const Key('editSelectionText')), findsNothing);
      expect(find.byKey(const Key('fillShapeCheckbox')), findsNothing);

      // A click on a colour colours it at once.
      await studio.tap('color-78a66f');
      expect(find.byKey(const Key('applySelectionStyle')), findsNothing);
      expect(await studio.svg(), contains('fill="#78a66f"'));
      await studio.tap('undo');
      expect(await studio.svg(), contains('fill="#477fb2"'));
      await studio.tap('redo');

      await studio.tap('tool-select');
      await studio.click(studio.at(486, 286));
      await studio.tap('duplicateSelection');
      studio.expectCount(2);
      // The copy stays chosen: drag it away by its middle.
      await studio.drag(studio.at(624, 424), studio.at(324, 224));
      final document = await studio.saved();
      try {
        final stamps = document.strokes;
        expect(stamps, hasLength(2));
        expect(stamps.map((object) => object.kind).toSet(), {VectorKind.stamp});
        expect(stamps.map((object) => object.rgb).toSet(), {0x78a66f});
        expect(left(stamps[0]), closeTo(480, .5));
        // 24 units for the copy, then 300 to the left and 200 upwards.
        expect(left(stamps[1]), closeTo(480 + 24 - 300, 1));
        expect(top(stamps[1]), closeTo(280 + 24 - 200, 1));
        expect(right(stamps[1]) - left(stamps[1]), closeTo(240, .01));
      } finally {
        document.dispose();
      }
      await studio.tap('deleteSelection');
      studio.expectCount(1);
      await studio.tap('undo');
      studio.expectCount(2);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('a stamp is painted in the PNG export with its colour', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('color-d75e56');
    await studio.tap('tool-stamp');
    await studio.tap('size-large');
    await studio.click();
    final png = await studio.png();
    // The middle of the star carries the chosen colour; the corner of its box
    // and the rest of the sheet stay white.
    expect(await studio.pixel(png, 600, 410), [0xd7, 0x5e, 0x56, 255]);
    expect(await studio.pixel(png, 484, 284), [255, 255, 255, 255]);
    expect(await studio.pixel(png, 100, 100), [255, 255, 255, 255]);
    // Exporting is not saving.
    expect(studio.isDirty, isTrue);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'stamp sizes follow the sheet: a square sheet gets larger stamps',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.newSheet('square');
      await studio.tap('tool-stamp');
      await studio.click();
      final document = await studio.saved();
      try {
        expect(document.width, 1200);
        expect(document.height, 1200);
        final stamp = document.strokes.single;
        // 150 units on an 800-unit side become 225 on a 1200-unit side.
        expect(right(stamp) - left(stamp), closeTo(225, .01));
        expect(left(stamp), closeTo(600 - 112.5, .5));
        expect(top(stamp), closeTo(600 - 112.5, .5));
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the stamp chooser blocks document commands and works with enlarged text',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(680, 480), textScale: 2);
      await studio.tap('tool-stamp');
      expect(tester.takeException(), isNull);
      await studio.tap('chooseStamp');
      expect(find.byKey(const Key('stampDialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Menu commands arriving meanwhile neither stack a dialog nor write.
      final menu = studio.menu;
      menu.onNew!();
      menu.onOpen!();
      menu.onSave!();
      menu.onExportSvg!();
      menu.onAbout!();
      menu.onLayers!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      expect(studio.files.projects, isEmpty);
      expect(studio.files.saveDialogCount, 0);
      // The last stamp of the catalogue is reached by scrolling the dialog.
      await studio.tap('stamp-arcenciel');
      expect(find.byKey(const Key('stampDialog')), findsNothing);
      expect(tester.takeException(), isNull);
      await studio.click();
      studio.expectCount(1);
      final document = await studio.saved();
      try {
        expect(document.strokes.single.stamp, 23);
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('recovery and reopening bring stamps back as stamps', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-stamp');
    await studio.tap('chooseStamp');
    await studio.tap('stamp-maison');
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
    studio.expectCount(1);
    expect(await studio.svg(), before);

    await studio.tap('saveProject');
    await studio.newSheet('landscape');
    studio.expectCount(0);
    studio.files.openPath = studio.files.savePath;
    await studio.tap('openProject');
    studio.expectCount(1);
    expect(await studio.svg(), before);
    // A reopened stamp is still one object that can be chosen as a whole.
    await studio.tap('tool-select');
    await studio.click(studio.at(530, 330));
    expect(
      find.text('Glisse pour déplacer. Clique une couleur pour le colorier.'),
      findsOneWidget,
    );
    await studio.finish();
  }, skip: !available);

  testWidgets('the stamp tool shows its stamp in the wide inspector', (
    tester,
  ) async {
    final files = MemoryFiles();
    final studio = StudioDriver(tester, files: files);
    await studio.start(size: const Size(1280, 820));
    await studio.tap('tool-stamp');
    expect(find.text('TAMPON'), findsOneWidget);
    expect(find.text('Un tampon, et hop !'), findsOneWidget);
    expect(
      find.textContaining('Choisis un tampon, puis clique sur la feuille'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);
}
