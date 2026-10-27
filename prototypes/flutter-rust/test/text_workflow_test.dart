// SPDX-License-Identifier: MIT
// Real Rust documents; only dialogs' destinations and storage are in memory.
import 'dart:io';

import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/text_dialog.dart';
import 'package:edupaint_flutter_study/text_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  testWidgets(
    'the text tool opens its dialog on release and adds one undoable text',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-text');
      // Pressing alone shows nothing: writing starts when the pointer leaves.
      final gesture = await tester.startGesture(studio.sheetCenter);
      await tester.pump();
      expect(find.byKey(const Key('textDialog')), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('textDialog')), findsOneWidget);
      expect(find.text('Écris ton texte'), findsOneWidget);
      studio.expectCount(0);
      // Nothing to pose yet: the confirmation is disabled.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirmText')))
            .onPressed,
        isNull,
      );
      await studio.write('   ');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirmText')))
            .onPressed,
        isNull,
      );
      await studio.write('Bonjour');
      await studio.tap('confirmText');
      expect(find.byKey(const Key('textDialog')), findsNothing);
      studio.expectCount(1);
      expect(studio.isDirty, isTrue);

      final exported = await studio.svg();
      expect(exported, contains('>Bonjour</tspan>'));
      expect(exported, contains('fill="#477fb2"'));
      final document = await studio.saved();
      try {
        final text = document.strokes.single;
        expect(text.kind, VectorKind.text);
        expect(text.text, 'Bonjour');
        expect(text.rgb, 0x477fb2);
        expect(text.width, 56, reason: 'medium letters on a 1200 × 800 sheet');
        // The box starts where the pointer was released: the sheet's centre.
        expect(left(text), closeTo(600, .5));
        expect(top(text), closeTo(400, .5));
        final layout = TextLayout('Bonjour', size: 56, rgb: 0x477fb2);
        expect(right(text) - left(text), closeTo(layout.width, .01));
        expect(bottom(text) - top(text), closeTo(layout.height, .01));
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
    'cancelling or escaping the text dialog leaves drawing, history and recovery untouched',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stroke');
      await studio.drag(const Offset(-40, -20), const Offset(55, 35));
      await studio.tap('saveProject');
      final before = await studio.svg();
      expect(studio.recovery.bytes, isNull);
      await studio.tap('tool-text');

      await studio.click();
      await studio.write('abandonné');
      await studio.tap('cancelText');
      studio.expectCount(1);
      expect(studio.isDirty, isFalse);

      await studio.click();
      await studio.write('abandonné aussi');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('textDialog')), findsNothing);
      studio.expectCount(1);
      expect(studio.isDirty, isFalse);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(studio.recovery.bytes, isNull);
      expect(await studio.svg(), before);
      // The single stroke is still the only step to undo.
      await studio.tap('undo');
      studio.expectCount(0);
      expect(
        tester.widget<IconButton>(find.byKey(const Key('undo'))).onPressed,
        isNull,
      );
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'lines, letter size and colour are stored, and Enter starts a new line',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('color-d75e56');
      await studio.tap('tool-text');
      await studio.click(studio.at(100, 100));
      // Short lines: the test font makes every character one em wide, and a
      // text wider than the sheet is refused (see the test further down).
      await studio.write('un\na & <b>');
      await studio.tap('textDialogSize-large');
      await studio.tap('confirmText');
      studio.expectCount(1);
      final exported = await studio.svg();
      expect(exported, contains('font-size="96"'));
      expect(exported, contains('fill="#d75e56"'));
      expect(exported, contains('>un</tspan>'));
      expect(exported, contains('>a &amp; &lt;b&gt;</tspan>'));
      expect('<tspan'.allMatches(exported), hasLength(2));
      final document = await studio.saved();
      try {
        expect(document.strokes.single.text, 'un\na & <b>');
        expect(document.strokes.single.width, 96);
        expect(
          bottom(document.strokes.single) - top(document.strokes.single),
          closeTo(2 * 1.2 * 96, .01),
        );
      } finally {
        document.dispose();
      }
      // The size choice is remembered for the next text of this session.
      await studio.click(studio.at(100, 500));
      expect(
        tester
            .getSemantics(find.byKey(const Key('textDialogSize-large')))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
      // Control+Enter confirms without leaving the keyboard.
      await studio.write('clavier');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('textDialog')), findsNothing);
      studio.expectCount(2);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a chosen text is moved, recoloured, copied and edited, one undo step each',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.addText('Avant');
      await studio.tap('tool-select');
      // Anywhere in the text's box selects it, like a filled shape.
      await studio.click(const Offset(12, 8));
      expect(find.byKey(const Key('editSelectionText')), findsOneWidget);
      expect(
        find.text('Glisse pour déplacer. Modifier change les mots.'),
        findsOneWidget,
      );
      // The outline-width slider does not apply to a text.
      expect(find.text('Épaisseur'), findsNothing);

      await studio.tap('editSelectionText');
      expect(find.text('Change ton texte'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('textField')))
            .controller!
            .text,
        'Avant',
      );
      await studio.write('Après\ncoup');
      await studio.tap('confirmText');
      studio.expectCount(1);
      var exported = await studio.svg();
      expect(exported, contains('>Après</tspan>'));
      expect(exported, contains('>coup</tspan>'));
      expect(exported, isNot(contains('Avant')));
      // One Annuler returns the words, the box and the size together.
      await studio.tap('undo');
      exported = await studio.svg();
      expect(exported, contains('>Avant</tspan>'));
      expect(exported, isNot(contains('coup')));
      await studio.tap('redo');

      // Colour through the palette, at once, as for shapes.
      await studio.tap('tool-select');
      await studio.click(const Offset(12, 8));
      await studio.tap('color-78a66f');
      expect(find.byKey(const Key('applySelectionStyle')), findsNothing);
      exported = await studio.svg();
      expect(exported, contains('fill="#78a66f"'));
      expect(exported, contains('font-size="56"'));

      await studio.tap('duplicateSelection');
      studio.expectCount(2);
      // Moving: drag the copy, which stays selected.
      await studio.drag(const Offset(36, 32), const Offset(-60, -60));
      final document = await studio.saved();
      try {
        expect(document.strokes, hasLength(2));
        expect(document.strokes.map((object) => object.text), [
          'Après\ncoup',
          'Après\ncoup',
        ]);
        expect(document.strokes.map((object) => object.rgb).toSet(), {
          0x78a66f,
        });
        expect(left(document.strokes[0]), closeTo(600, .5));
        expect(left(document.strokes[1]), lessThan(left(document.strokes[0])));
        expect(top(document.strokes[1]), lessThan(top(document.strokes[0])));
      } finally {
        document.dispose();
      }
      // Keeping the same size choice keeps the exact size of an edited text.
      await studio.tap('editSelectionText');
      await studio.write('Encore');
      await studio.tap('confirmText');
      expect(await studio.svg(), contains('font-size="56"'));
      await studio.tap('editSelectionText');
      await studio.tap('textDialogSize-small');
      await studio.tap('confirmText');
      exported = await studio.svg();
      expect(exported, contains('font-size="32"'));
      expect(exported, contains('font-size="56"'));
      await studio.tap('deleteSelection');
      studio.expectCount(1);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a line wider than the sheet is broken; a text that cannot stand keeps its words in the dialog',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-text');
      await studio.click();
      // Forty wide letters at the large size are wider than 1200 units: the
      // line is broken, inside the word since it has no space.
      await studio.write('M' * 40);
      await studio.tap('textDialogSize-large');
      await studio.tap('confirmText');
      expect(find.byKey(const Key('textDialog')), findsNothing);
      studio.expectCount(1);
      var document = await studio.saved();
      try {
        final text = document.strokes.single;
        final lines = text.text!.split('\n');
        expect(lines.join(), 'M' * 40);
        expect(lines.length, greaterThan(1));
        expect(right(text), lessThanOrEqualTo(1200));
        expect(left(text), greaterThanOrEqualTo(0));
        // Every line but the last is as long as the sheet allows.
        final widest = TextLayout(lines.first, size: text.width, rgb: 0).width;
        expect(widest, lessThanOrEqualTo(1200));
        expect(
          TextLayout('${lines.first}M', size: text.width, rgb: 0).width,
          greaterThan(1200),
        );
      } finally {
        document.dispose();
      }

      // Two hundred and fifty of them need more lines of that size than the sheet is
      // tall: the dialog stays, with the reason and every typed letter.
      await studio.click(studio.at(100, 100));
      await studio.write('M' * 250);
      await studio.tap('confirmText');
      expect(find.byKey(const Key('textDialog')), findsOneWidget);
      expect(find.textContaining('trop grand pour la feuille'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('textField')))
            .controller!
            .text,
        'M' * 250,
      );
      studio.expectCount(1);
      // A click beside the dialog does not throw the words away either.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('textDialog')), findsOneWidget);
      // A smaller size: the reason goes, and the same words now stand.
      await studio.tap('textDialogSize-small');
      expect(find.textContaining('trop grand pour la feuille'), findsNothing);
      await studio.tap('confirmText');
      expect(find.byKey(const Key('textDialog')), findsNothing);
      studio.expectCount(2);
      // A text clicked near the edge is pushed back whole onto the sheet.
      await studio.click(studio.at(1190, 790));
      await studio.write('bord');
      await studio.tap('textDialogSize-small');
      await studio.tap('confirmText');
      studio.expectCount(3);
      document = await studio.saved();
      try {
        expect(document.strokes[1].text!.replaceAll('\n', ''), 'M' * 250);
        for (final text in document.strokes) {
          expect(right(text), lessThanOrEqualTo(1200));
          expect(bottom(text), lessThanOrEqualTo(800));
          expect(left(text), greaterThanOrEqualTo(0));
          expect(top(text), greaterThanOrEqualTo(0));
        }
        expect(document.strokes.last.text, 'bord');
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the text dialog blocks document commands and stays usable with enlarged text',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(680, 480), textScale: 2);
      await studio.tap('tool-text');
      await studio.click();
      expect(find.byKey(const Key('textDialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Menu commands arriving meanwhile neither stack a dialog nor write.
      final menu = studio.menu;
      menu.onNew!();
      menu.onOpen!();
      menu.onSave!();
      menu.onExportSvg!();
      menu.onAbout!();
      menu.onLayers!();
      menu.onUndo?.call();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      expect(studio.files.projects, isEmpty);
      expect(studio.files.saveDialogCount, 0);
      await studio.write('Grand');
      await studio.tap('textDialogSize-small');
      await studio.tap('confirmText');
      expect(tester.takeException(), isNull);
      studio.expectCount(1);
      // The guard is released: the same commands answer again.
      studio.menu.onUndo!();
      await tester.pumpAndSettle();
      studio.expectCount(0);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('recovery brings a text back and lets the drawing continue', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.addText('À reprendre');
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
    expect(await studio.svg(), contains('>À reprendre</tspan>'));
    await studio.addText('Suite', x: 100, y: 600);
    studio.expectCount(2);
    final document = await studio.saved();
    try {
      expect(document.strokes.map((object) => object.text), [
        'À reprendre',
        'Suite',
      ]);
    } finally {
      document.dispose();
    }
    expect(studio.recovery.bytes, isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('a saved text project reopens through Ouvrir with its words', (
    tester,
  ) async {
    final files = MemoryFiles();
    final studio = StudioDriver(tester, files: files);
    await studio.start();
    await studio.addText('Enregistré');
    await studio.tap('saveProject');
    final before = await studio.svg();
    await studio.tap('newProject');
    await studio.tap('createNewSheet');
    studio.expectCount(0);
    files.openPath = files.savePath;
    await studio.tap('openProject');
    studio.expectCount(1);
    expect(await studio.svg(), before);
    // A reopened text is still a text: it can be chosen and edited.
    await studio.tap('tool-select');
    await studio.click(const Offset(12, 8));
    await studio.tap('editSelectionText');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('textField')))
          .controller!
          .text,
      'Enregistré',
    );
    await studio.tap('cancelText');
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'more lines than a text may keep are announced in the dialog, not cut',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-text');
      await studio.click(studio.at(100, 20));
      final forty = List.generate(40, (index) => 'mot ${index + 1}').join('\n');
      await studio.write(forty);
      await studio.tap('textDialogSize-small');
      await studio.tap('confirmText');
      // Nothing was posed, nothing was dropped: the dialog says why.
      expect(find.byKey(const Key('textDialog')), findsOneWidget);
      expect(
        find.text('Ton texte a trop de lignes : il peut en avoir 32 au plus.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('textField')))
            .controller!
            .text,
        forty,
      );
      studio.expectCount(0);
      // The message leaves as soon as the text changes.
      final twenty = List.generate(
        20,
        (index) => 'mot ${index + 1}',
      ).join('\n');
      await studio.write(twenty);
      expect(find.textContaining('trop de lignes'), findsNothing);
      await studio.tap('confirmText');
      expect(find.byKey(const Key('textDialog')), findsNothing);
      studio.expectCount(1);
      final document = await studio.saved();
      try {
        expect(document.strokes.single.text, twenty);
      } finally {
        document.dispose();
      }
      // Échap gives up what is typed; a click beside the dialog does not.
      await studio.click(studio.at(600, 20));
      await studio.write('à abandonner');
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('textDialog')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('textDialog')), findsNothing);
      studio.expectCount(1);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a text longer than a child may type, from a project made elsewhere, keeps its words when changed',
    (tester) async {
      final source = RustDocument();
      // Twenty lines and 610 characters: more than the 280 that are typed.
      final long = List.generate(
        20,
        (index) => 'ligne ${index + 1} ${'x' * 21}',
      ).join('\n');
      final files = MemoryFiles()..openPath = '/drawings/long.edupaint';
      try {
        source.addText(
          const DocumentPoint(10, 10),
          const DocumentPoint(600, 500),
          text: long,
          rgb: 0,
          size: 16,
        );
        files.projects[files.openPath!] = source.exportProject();
      } finally {
        source.dispose();
      }
      expect(long.length, greaterThan(TextEntryDialog.typedCharacters));
      final studio = StudioDriver(tester, files: files);
      await studio.start();
      await studio.tap('openProject');
      await studio.tap('tool-select');
      await studio.click(studio.at(100, 100));
      await studio.tap('editSelectionText');
      // One more character at the end: nothing before it may be lost.
      await studio.write('$long!');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('textField')))
            .controller!
            .text,
        '$long!',
      );
      // Grown past what a project keeps, it is refused whole, with the
      // reason, and still nothing is cut.
      final tooLong = '$long!${' encore' * 220}';
      await studio.write(tooLong);
      await studio.tap('confirmText');
      expect(find.byKey(const Key('textDialog')), findsOneWidget);
      expect(find.text(TextEntryDialog.tooLong), findsOneWidget);
      final kept = tester
          .widget<TextField>(find.byKey(const Key('textField')))
          .controller!
          .text;
      expect(kept, startsWith('$long!'));
      expect(kept.length, greaterThan(maxTextBytes));
      studio.expectCount(1);
      await studio.write('$long!');
      await studio.tap('confirmText');
      expect(find.byKey(const Key('textDialog')), findsNothing);
      files.savePath = files.openPath;
      await studio.tap('saveProject');
      final document = RustDocument.fromProject(
        files.projects[files.openPath!]!,
      );
      try {
        expect(document.strokes.single.text, '$long!');
        // Its own size was kept: the choice shown was the nearest, unchanged.
        expect(document.strokes.single.width, 16);
      } finally {
        document.dispose();
      }
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );
}
