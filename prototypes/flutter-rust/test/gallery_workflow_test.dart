// SPDX-License-Identifier: MIT
// « Mes dessins » in the studio. Real Rust documents and real pictures; the
// native panels, the saved files and the recovery copy are in memory, and so
// is the album except in the last test, which uses a real folder.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/gallery_storage.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/memory_gallery.dart';
import 'support/prepared_open_wait.dart';
import 'support/studio_driver.dart';

const _saved = '/drawings/Mon dessin.edupaint';

// What the studio says of a drawing taken from the album's copy: it names
// the day of that copy.
final _fromGallery = find.textContaining(
  RegExp(
    r'^Dessin repris de la galerie, tel qu’il était aujourd’hui à \d+\u00a0h\u00a0\d\d · Enregistrer te demandera où le ranger\.$',
  ),
);

class _Files extends MemoryFiles {
  /// Paths this program can no longer read, as after a restart in a sandbox.
  final outOfReach = <String>{};

  /// What every save panel was given as the current place of the drawing.
  final suggestions = <String?>[];

  /// The image that « Sur une image » chooses.
  String? imagePath;
  final images = <String, Uint8List>{};

  @override
  Future<String?> chooseSave({String? currentPath}) {
    suggestions.add(currentPath);
    return super.chooseSave(currentPath: currentPath);
  }

  @override
  Future<String?> chooseImage() async => imagePath;

  @override
  Future<Uint8List> readImage(String path) async =>
      Uint8List.fromList(images[path]!);

  @override
  Future<Uint8List> read(String path) async {
    if (outOfReach.contains(path) || !projects.containsKey(path)) {
      throw FileSystemException('Simulated file out of reach', path);
    }
    return super.read(path);
  }
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  // The card is made after the save: it starts on the studio's clock and its
  // picture is encoded by the real engine. Wait on both, then let the studio
  // finish.
  Future<void> cardMade(
    WidgetTester tester,
    MemoryGallery gallery,
    int calls,
  ) async {
    for (
      var attempt = 0;
      attempt < 500 && gallery.rememberCalls < calls;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pumpAndSettle();
    expect(gallery.rememberCalls, calls);
  }

  Future<void> saveWithCard(
    StudioDriver studio,
    MemoryGallery gallery,
    int calls,
  ) async {
    await studio.tap('saveProject');
    await cardMade(studio.tester, gallery, calls);
  }

  // A rectangle with a red outline and a yellow inside, at 200..500 × 200..450.
  Future<void> yellowRectangle(StudioDriver studio) async {
    await studio.tap('tool-rectangle');
    await studio.tap('color-d75e56');
    await studio.tap('paint-target-fill');
    await studio.tap('color-eebf4e');
    await studio.drag(studio.at(200, 200), studio.at(500, 450));
  }

  Future<void> blueTrait(StudioDriver studio, [double y = 600]) async {
    await studio.tap('tool-stroke');
    await studio.tap('color-477fb2');
    await studio.drag(studio.at(700, y), studio.at(1000, y + 50));
  }

  int countIn(Uint8List project) {
    final document = RustDocument.fromProject(project);
    try {
      return document.count;
    } finally {
      document.dispose();
    }
  }

  /// Opens the album and chooses the card of [path].
  Future<void> reopen(StudioDriver studio, String path) async {
    final tester = studio.tester;
    await studio.tap('openGallery');
    expect(find.byKey(const Key('galleryDialog')), findsOneWidget);
    final card = find.byKey(Key('gallery-open-${GalleryStorage.idFor(path)}'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await waitForPreparedOpen(tester, allowSaveDecision: true);
  }

  String? problem(WidgetTester tester) {
    final message = find.byKey(const Key('problemMessage'));
    return message.evaluate().isEmpty
        ? null
        : tester.widget<Text>(message).data;
  }

  testWidgets('a studio without an album offers none', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start();
    expect(find.byKey(const Key('openGallery')), findsNothing);
    expect(studio.menu.hasGallery, isFalse);
    // Neither the help nor the information speaks of an album that is not
    // there.
    await studio.tap('showHelp');
    expect(find.byKey(const Key('help-gallery')), findsNothing);
    await studio.tap('closeHelp');
    studio.menu.onAbout!();
    await tester.pumpAndSettle();
    expect(find.textContaining('Les projets Color gardent'), findsOneWidget);
    expect(find.textContaining('Mes dessins range'), findsNothing);
    await tester.tap(find.text('Revenir au dessin'));
    await tester.pumpAndSettle();
    await studio.tap('tool-stroke');
    await studio.click();
    await studio.tap('saveProject');
    expect(find.textContaining('Projet enregistré'), findsWidgets);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'Enregistrer adds a card: the picture of the drawing and a copy of its bytes',
    (tester) async {
      final gallery = MemoryGallery();
      final studio = StudioDriver(tester, gallery: gallery);
      await studio.start();
      expect(find.byKey(const Key('openGallery')), findsOneWidget);
      expect(studio.menu.hasGallery, isTrue);
      // The help explains the album, and the information says what it keeps.
      await studio.tap('showHelp');
      final row = find.byKey(const Key('help-gallery'), skipOffstage: false);
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining(
            'Color en garde une copie',
            skipOffstage: false,
          ),
        ),
        findsOneWidget,
      );
      await studio.tap('closeHelp');
      studio.menu.onAbout!();
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'une petite image et une copie de chaque dessin enregistré',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Revenir au dessin'));
      await tester.pumpAndSettle();
      // Nothing was saved yet: nothing is in the album.
      await yellowRectangle(studio);
      expect(gallery.entries, isEmpty);

      await saveWithCard(studio, gallery, 1);
      expect(find.textContaining('Projet enregistré : $_saved'), findsWidgets);
      expect(problem(tester), isNull);
      final entry = gallery.entries.single;
      expect(entry.name, 'Mon dessin.edupaint');
      expect(entry.sourcePath, _saved);
      expect((entry.width, entry.height, entry.elementCount), (1200, 800, 1));
      expect(gallery.copyOf(entry), studio.files.projects[_saved]);
      expect(
        DateTime.now().toUtc().difference(entry.savedAt).inMinutes.abs(),
        lessThan(5),
      );

      final pixels = await _decode(tester, gallery.thumbnailOf(entry)!);
      expect((pixels.width, pixels.height), (320, 213));
      // One pixel for 3.75 units of the sheet.
      expect(pixels.at(10, 10), 0xffffffff, reason: 'paper');
      expect(pixels.at(93, 86), 0xffeebf4e, reason: 'inside of the rectangle');
      expect(pixels.at(53, 86), 0xffd75e56, reason: 'its outline');
      expect(pixels.at(250, 160), 0xffffffff, reason: 'paper again');

      // Saving the same file again refreshes the same card.
      await blueTrait(studio);
      await saveWithCard(studio, gallery, 2);
      final refreshed = gallery.entries.single;
      expect(refreshed.elementCount, 2);
      expect(gallery.copyOf(refreshed), studio.files.projects[_saved]);
      final again = await _decode(tester, gallery.thumbnailOf(refreshed)!);
      expect(again.at(226, 166), 0xff477fb2, reason: 'the new trait');
      expect(studio.files.saveDialogCount, 1);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the card shows the drawing as it was saved, even if drawing goes on meanwhile',
    (tester) async {
      final gallery = MemoryGallery();
      final studio = StudioDriver(tester, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await studio.tap('saveProject');
      // The picture is still being made; the child is already drawing again.
      expect(gallery.rememberCalls, 0);
      await blueTrait(studio);
      studio.expectCount(2);
      await cardMade(tester, gallery, 1);

      final entry = gallery.entries.single;
      expect(entry.elementCount, 1);
      expect(gallery.copyOf(entry), studio.files.projects[_saved]);
      final pixels = await _decode(tester, gallery.thumbnailOf(entry)!);
      expect(pixels.at(93, 86), 0xffeebf4e);
      expect(pixels.at(226, 166), 0xffffffff, reason: 'no trait yet');
      // The drawing itself still has both, and still has to be saved.
      studio.expectCount(2);
      expect(studio.isDirty, isTrue);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'each saved file has its card; a coloured portrait sheet keeps its shape',
    (tester) async {
      final gallery = MemoryGallery();
      final studio = StudioDriver(tester, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);

      await studio.newSheet('portrait');
      await studio.tap('tool-fill');
      await studio.tap('color-78a66f');
      await studio.click();
      studio.files.savePath = '/drawings/Forêt.edupaint';
      await saveWithCard(studio, gallery, 2);

      expect(gallery.entries.map((entry) => entry.name).toSet(), {
        'Mon dessin.edupaint',
        'Forêt.edupaint',
      });
      final forest = gallery.entries.firstWhere(
        (entry) => entry.name == 'Forêt.edupaint',
      );
      expect((forest.width, forest.height), (800, 1200));
      // A sheet that is only coloured has no element, and still a card.
      expect(forest.elementCount, 0);
      final pixels = await _decode(tester, gallery.thumbnailOf(forest)!);
      expect((pixels.width, pixels.height), (213, 320));
      expect(pixels.at(100, 160), 0xff78a66f);
      expect(pixels.at(0, 0), 0xff78a66f);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a card whose file is still readable reopens that file: Enregistrer writes to it',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);
      await studio.newSheet('square');
      studio.expectCount(0);
      expect(find.text('Mon dessin'), findsOneWidget);

      await reopen(studio, _saved);
      expect(find.byKey(const Key('galleryDialog')), findsNothing);
      studio.expectCount(1);
      expect(find.text('Mon dessin.edupaint'), findsOneWidget);
      expect(find.textContaining('projet enregistré'), findsOneWidget);
      expect(studio.isDirty, isFalse);
      expect(problem(tester), isNull);

      await blueTrait(studio);
      await saveWithCard(studio, gallery, 2);
      // No panel: the drawing went back to its own file.
      expect(files.saveDialogCount, 1);
      final document = RustDocument.fromProject(files.projects[_saved]!);
      try {
        expect(document.count, 2);
        expect((document.width, document.height), (1200, 800));
      } finally {
        document.dispose();
      }
      expect(gallery.entries.single.elementCount, 2);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'when the file is out of reach the album’s copy opens as a drawing without a file',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);
      final savedBytes = Uint8List.fromList(files.projects[_saved]!);
      await studio.newSheet('square');
      // As after Color was closed and opened again in its sandbox.
      files.outOfReach.add(_saved);

      await reopen(studio, _saved);
      studio.expectCount(1);
      expect(_fromGallery, findsOneWidget);
      // It is the drawing, not yet a file: its name is the default one.
      expect(find.text('Mon dessin'), findsOneWidget);
      expect(find.textContaining('nouvelle feuille'), findsOneWidget);
      expect(studio.isDirty, isFalse);
      expect(problem(tester), isNull);
      // Nothing was written anywhere by looking.
      expect(files.projects[_saved], savedBytes);
      expect(files.saveDialogCount, 1);

      // Enregistrer asks where, starting from the place it was saved before.
      files.outOfReach.clear();
      await blueTrait(studio);
      await saveWithCard(studio, gallery, 2);
      expect(files.saveDialogCount, 2);
      expect(files.suggestions, [null, _saved]);
      expect(find.text('Mon dessin.edupaint'), findsOneWidget);
      expect(gallery.entries.single.elementCount, 2);

      // Once it has a file again, the next save needs no panel.
      await studio.tap('tool-stroke');
      await studio.click(studio.at(100, 100));
      await saveWithCard(studio, gallery, 3);
      expect(files.saveDialogCount, 2);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the remembered place is forgotten with the drawing it belonged to',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);
      await studio.newSheet('square');
      files.outOfReach.add(_saved);
      await reopen(studio, _saved);
      expect(_fromGallery, findsOneWidget);

      // Another sheet: its first save must not point at the old drawing's file.
      await studio.newSheet('portrait');
      await studio.tap('tool-stroke');
      await studio.click();
      files.savePath = '/drawings/Autre.edupaint';
      await saveWithCard(studio, gallery, 2);
      expect(files.suggestions, [null, null]);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a damaged file gives way to the album’s copy; a damaged copy says so',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);
      await studio.newSheet('square');
      files.projects[_saved] = Uint8List.fromList('pas un dessin'.codeUnits);

      await reopen(studio, _saved);
      studio.expectCount(1);
      expect(_fromGallery, findsOneWidget);
      expect(problem(tester), isNull);
      // The damaged file was only read.
      expect(files.projects[_saved], 'pas un dessin'.codeUnits);

      // Now the copy cannot be read either: the drawing on screen stays.
      await blueTrait(studio);
      gallery.failCopy = true;
      await reopen(studio, _saved);
      expect(
        problem(tester),
        'Ce dessin n’a pas pu être repris. Le dessin actuel est conservé.',
      );
      studio.expectCount(2);
      expect(studio.isDirty, isTrue);
      expect(find.byKey(const Key('saveChanges')), findsNothing);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a drawing too large for a copy, whose file is out of reach, is explained',
    (tester) async {
      final gallery = MemoryGallery(maxCopyBytes: 40);
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);
      final entry = gallery.entries.single;
      expect(entry.hasCopy, isFalse);
      // Its picture is in the album all the same.
      expect(gallery.thumbnailOf(entry), isNotNull);

      // While its file can be read, the card works like any other.
      await blueTrait(studio);
      files.outOfReach.add(_saved);
      await reopen(studio, _saved);
      expect(
        problem(tester),
        contains('trop grand pour être gardé dans la galerie'),
      );
      expect(problem(tester), contains('Retrouve-le avec Ouvrir'));
      // Nothing was asked and nothing was replaced.
      expect(find.byKey(const Key('saveChanges')), findsNothing);
      studio.expectCount(2);
      expect(studio.isDirty, isTrue);

      files.outOfReach.clear();
      await reopen(studio, _saved);
      await studio.tap('discardChanges');
      studio.expectCount(1);
      expect(find.text('Mon dessin.edupaint'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'unsaved changes are asked about before a card replaces the drawing',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);
      await blueTrait(studio);
      expect(studio.isDirty, isTrue);

      // Annuler: the drawing and its changes stay.
      await reopen(studio, _saved);
      expect(find.text('Garder les modifications ?'), findsOneWidget);
      await studio.tap('cancelChanges');
      studio.expectCount(2);
      expect(studio.isDirty, isTrue);

      // Ne pas enregistrer: the saved state comes back.
      await reopen(studio, _saved);
      await studio.tap('discardChanges');
      studio.expectCount(1);
      expect(studio.isDirty, isFalse);
      expect(gallery.rememberCalls, 1);

      // Enregistrer: the changes go to the very file of the card, and it is
      // that new state which is reopened, not the one read before the answer.
      await blueTrait(studio);
      await studio.tap('tool-stroke');
      await studio.click(studio.at(100, 700));
      studio.expectCount(3);
      await reopen(studio, _saved);
      await tester.tap(find.byKey(const Key('saveChanges')));
      await waitForPreparedOpen(tester);
      await cardMade(tester, gallery, 2);
      studio.expectCount(3);
      expect(studio.isDirty, isFalse);
      expect(find.text('Mon dessin.edupaint'), findsOneWidget);
      expect(gallery.entries.single.elementCount, 3);
      expect(files.saveDialogCount, 1);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a file written by a newer Color is announced, not replaced by an older copy',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);
      await blueTrait(studio);
      files.projects[_saved] = File(
        'test/fixtures/project-open/unknown-version-6.edupaint',
      ).readAsBytesSync();

      await reopen(studio, _saved);
      expect(problem(tester), contains('version plus récente de Color'));
      expect(problem(tester), contains('Le dessin actuel est conservé'));
      expect(_fromGallery, findsNothing);
      studio.expectCount(2);
      expect(studio.isDirty, isTrue);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('an album that fails costs a card, never a save nor a message', (
    tester,
  ) async {
    final gallery = MemoryGallery()..failRemember = true;
    final files = _Files();
    final studio = StudioDriver(tester, files: files, gallery: gallery);
    await studio.start();
    await yellowRectangle(studio);
    await saveWithCard(studio, gallery, 1);
    expect(files.projects[_saved], isNotNull);
    expect(find.textContaining('Projet enregistré : $_saved'), findsWidgets);
    expect(studio.isDirty, isFalse);
    expect(problem(tester), isNull);
    expect(gallery.entries, isEmpty);

    // The album cannot even be listed: its dialog says so, the studio goes on.
    gallery.failList = true;
    await studio.tap('openGallery');
    expect(find.byKey(const Key('galleryUnavailable')), findsOneWidget);
    await studio.tap('closeGallery');
    studio.expectCount(1);

    // When it works again, the next save makes the card.
    gallery
      ..failRemember = false
      ..failList = false;
    await blueTrait(studio);
    await saveWithCard(studio, gallery, 2);
    expect(gallery.entries.single.elementCount, 2);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('a save that fails leaves no card', (tester) async {
    final gallery = MemoryGallery();
    final files = _Files()..failWrite = true;
    final studio = StudioDriver(tester, files: files, gallery: gallery);
    await studio.start();
    await yellowRectangle(studio);
    await studio.tap('saveProject');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(problem(tester), contains('Enregistrement non terminé'));
    expect(gallery.rememberCalls, 0);
    expect(gallery.entries, isEmpty);
    expect(studio.isDirty, isTrue);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'while the album is open, commands wait; behind another dialog, the album waits',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);
      await blueTrait(studio);

      studio.menu.onGallery!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('galleryDialog')), findsOneWidget);
      final menu = studio.menu;
      menu.onNew!();
      menu.onOpen!();
      menu.onSave!();
      menu.onAbout!();
      menu.onLayers!();
      menu.onHelp!();
      menu.onGallery!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      expect(files.saveDialogCount, 1);
      // Keys of the drawing do nothing behind the album.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      // Échap closes the album and nothing else.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('galleryDialog')), findsNothing);
      studio.expectCount(2);
      expect(studio.isDirty, isTrue);

      // Behind the help, the album does not open.
      await studio.tap('showHelp');
      studio.menu.onGallery!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('galleryDialog')), findsNothing);
      expect(find.byKey(const Key('helpDialog')), findsOneWidget);
      await studio.tap('closeHelp');

      // While a trait is being drawn, the album does not open over it.
      await studio.tap('tool-stroke');
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(300, 600),
      );
      await gesture.moveTo(studio.sheetCenter + studio.at(360, 640));
      studio.menu.onGallery!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('galleryDialog')), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      studio.expectCount(3);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'in a small window with enlarged text the album is in the « … » menu',
    (tester) async {
      final gallery = MemoryGallery();
      final studio = StudioDriver(tester, gallery: gallery);
      await studio.start(size: const Size(680, 520), textScale: 1.5);
      await studio.tap('tool-stamp');
      await studio.click();
      await saveWithCard(studio, gallery, 1);

      await tester.tap(find.byKey(const Key('moreFileActions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('openGallery')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('galleryDialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
      final card = find.byKey(
        Key('gallery-open-${GalleryStorage.idFor(_saved)}'),
      );
      expect(card, findsOneWidget);
      final close = tester.getRect(find.byKey(const Key('closeGallery')));
      expect(close.bottom, lessThanOrEqualTo(520));
      expect(close.height, greaterThanOrEqualTo(48));
      await studio.tap('closeGallery');
      expect(find.byKey(const Key('galleryDialog')), findsNothing);
      // The drawing can be used again at once.
      await studio.click(studio.at(200, 200));
      studio.expectCount(2);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a card removed in the album leaves the saved file and the drawing alone',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);
      final savedBytes = Uint8List.fromList(files.projects[_saved]!);

      await studio.tap('openGallery');
      await studio.tap('gallery-forget-${GalleryStorage.idFor(_saved)}');
      await studio.tap('confirmGalleryForget');
      expect(find.byKey(const Key('galleryEmpty')), findsOneWidget);
      await studio.tap('closeGallery');
      expect(gallery.entries, isEmpty);
      expect(files.projects[_saved], savedBytes);
      studio.expectCount(1);
      expect(find.text('Mon dessin.edupaint'), findsOneWidget);
      expect(studio.isDirty, isFalse);

      // The next save of the same file brings its card back.
      await blueTrait(studio);
      await saveWithCard(studio, gallery, 2);
      expect(gallery.entries.single.elementCount, 2);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the card’s own drawing, changed and saved in the question, stays as it was saved',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      // An earlier session: one element, saved, its card made.
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);
      // A new session in the sandbox: the file is out of reach until it is
      // named again in a panel. The drawing comes back from the album's copy.
      await studio.newSheet('square');
      files.outOfReach.add(_saved);
      await reopen(studio, _saved);
      expect(_fromGallery, findsOneWidget);
      studio.expectCount(1);
      // Two more traits, not yet saved; the same card is chosen again, and
      // the question answered with Enregistrer. The panel proposes the place
      // it was saved before, and the child accepts.
      await blueTrait(studio);
      await blueTrait(studio, 300);
      studio.expectCount(3);
      await reopen(studio, _saved);
      await tester.tap(find.byKey(const Key('saveChanges')));
      await waitForPreparedOpen(tester);
      await cardMade(tester, gallery, 2);
      expect(files.suggestions, [null, _saved]);
      expect(countIn(files.projects[_saved]!), 3);
      expect(gallery.entries.single.elementCount, 3);
      // What was read before the question, one element, is not what stays.
      studio.expectCount(3);
      expect(studio.isDirty, isFalse);
      expect(find.text('Mon dessin.edupaint'), findsOneWidget);
      expect(_fromGallery, findsNothing);
      // The next save goes to that file, with everything in it.
      await studio.tap('tool-stroke');
      await studio.click(studio.at(100, 700));
      await saveWithCard(studio, gallery, 3);
      expect(files.saveDialogCount, 2);
      expect(countIn(files.projects[_saved]!), 4);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a file that can be written but no longer read: the drawing just saved to it stays',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);
      await blueTrait(studio);
      await blueTrait(studio, 300);
      files.outOfReach.add(_saved);
      await reopen(studio, _saved);
      await tester.tap(find.byKey(const Key('saveChanges')));
      await waitForPreparedOpen(tester);
      await cardMade(tester, gallery, 2);
      expect(countIn(files.projects[_saved]!), 3);
      studio.expectCount(3);
      expect(studio.isDirty, isFalse);
      expect(find.text('Mon dessin.edupaint'), findsOneWidget);
      await studio.finish();
    },
    skip: !available,
  );

  for (final readable in [false, true]) {
    testWidgets(
      'another drawing saved over the card’s file in the question: the card’s drawing is kept as unsaved (file readable: $readable)',
      (tester) async {
        final gallery = MemoryGallery();
        final files = _Files();
        final studio = StudioDriver(tester, files: files, gallery: gallery);
        await studio.start();
        // Yesterday: « Mon dessin », three elements, saved; its card is made.
        await yellowRectangle(studio);
        await blueTrait(studio);
        await blueTrait(studio, 300);
        await saveWithCard(studio, gallery, 1);
        // Today: a new sheet with one trait, never saved.
        await studio.newSheet('square');
        if (!readable) files.outOfReach.add(_saved);
        await studio.tap('tool-stroke');
        await studio.click();
        studio.expectCount(1);

        // Yesterday's card is chosen; Enregistrer in the question; the panel
        // proposes its usual name, which is yesterday's file; accepted.
        await reopen(studio, _saved);
        await tester.tap(find.byKey(const Key('saveChanges')));
        await waitForPreparedOpen(tester);
        await cardMade(tester, gallery, 2);
        // The file and the only card of that path now hold today's sheet.
        expect(countIn(files.projects[_saved]!), 1);
        expect(gallery.entries.single.elementCount, 1);
        // Yesterday's drawing is on the sheet, and nowhere else: it is not
        // called saved, it has no file, and the studio says why.
        studio.expectCount(3);
        expect(studio.isDirty, isTrue);
        expect(find.text('Mon dessin'), findsOneWidget);
        expect(problem(tester), contains('il n’existe plus qu’ici'));
        expect(studio.recovery.bytes, isNotNull);

        // Enregistrer proposes a name of its own beside the other file.
        files.savePath = '/drawings/Mon dessin (version précédente).edupaint';
        await saveWithCard(studio, gallery, 3);
        expect(files.suggestions.last, files.savePath);
        expect(countIn(files.projects[files.savePath]!), 3);
        expect(countIn(files.projects[_saved]!), 1);
        expect(gallery.entries.map((entry) => entry.elementCount).toSet(), {
          1,
          3,
        });
        expect(studio.isDirty, isFalse);
        expect(tester.takeException(), isNull);
        await studio.finish();
      },
      skip: !available,
    );
  }

  testWidgets('quitting with Enregistrer waits for the card of that save', (
    tester,
  ) async {
    final gallery = MemoryGallery();
    final files = _Files();
    final studio = StudioDriver(tester, files: files, gallery: gallery);
    await studio.start();
    await yellowRectangle(studio);
    await saveWithCard(studio, gallery, 1);
    await blueTrait(studio);
    studio.expectCount(2);

    ui.AppExitResponse? response;
    unawaited(
      tester.binding.handleRequestAppExit().then((value) => response = value),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveChanges')));
    for (var attempt = 0; attempt < 300 && response == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (response != null) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    // The host ends the program on this answer: the card is already there.
    expect(response, ui.AppExitResponse.exit);
    expect(countIn(files.projects[_saved]!), 2);
    expect(gallery.rememberCalls, 2);
    expect(gallery.entries.single.elementCount, 2);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'an album that does not answer holds the exit three seconds, no more',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      // The album's folder hangs from now on.
      gallery.holdRemember = Completer<void>().future;
      await studio.tap('saveProject');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(find.textContaining('Projet enregistré : $_saved'), findsWidgets);

      ui.AppExitResponse? response;
      unawaited(
        tester.binding.handleRequestAppExit().then((value) => response = value),
      );
      await tester.pump(const Duration(milliseconds: 2900));
      expect(response, isNull);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(response, ui.AppExitResponse.exit);
      expect(gallery.rememberCalls, 0);
      expect(files.projects[_saved], isNotNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the album opened right after a save waits for its card', (
    tester,
  ) async {
    final gallery = MemoryGallery();
    final studio = StudioDriver(tester, gallery: gallery);
    await studio.start();
    await yellowRectangle(studio);
    await studio.tap('saveProject');
    expect(gallery.rememberCalls, 0);
    await tester.tap(find.byKey(const Key('openGallery')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Open at once, and not yet saying that it is empty.
    expect(find.byKey(const Key('galleryDialog')), findsOneWidget);
    expect(find.byKey(const Key('galleryEmpty')), findsNothing);
    await cardMade(tester, gallery, 1);
    expect(find.byKey(const Key('galleryEmpty')), findsNothing);
    expect(
      find.byKey(Key('gallery-open-${GalleryStorage.idFor(_saved)}')),
      findsOneWidget,
    );
    await studio.tap('closeGallery');
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'a drawing on an image: its card shows the image, and the studio keeps its own',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files()
        ..imagePath = '/images/source.png'
        ..images['/images/source.png'] = File(
          'test/fixtures/raster/rgb-asymmetric.png',
        ).readAsBytesSync();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      // With the square letters of the tests this action has no room on the
      // line of the header: it waits in the « … » menu.
      await studio.reveal('importImage');
      await tester.tap(find.byKey(const Key('importImage')));
      await waitForPreparedOpen(tester);
      await tester.tap(find.byKey(const Key('saveProject')));
      await waitForPreparedOpen(tester);
      await cardMade(tester, gallery, 1);
      final entry = gallery.entries.single;
      final pixels = await _decode(tester, gallery.thumbnailOf(entry)!);
      expect((pixels.width, pixels.height), (entry.width, entry.height));
      // The card is done with the image: the studio still paints and exports
      // with its own.
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      final exported = await _decode(tester, await studio.png());
      expect((exported.width, exported.height), (entry.width, entry.height));
      // The picture of the card is the picture of the sheet.
      for (final (x, y) in [
        (0, 0),
        (entry.width - 1, 0),
        (0, entry.height - 1),
        (entry.width ~/ 2, entry.height ~/ 2),
      ]) {
        expect(pixels.at(x, y), exported.at(x, y), reason: '$x, $y');
      }
      expect(pixels.at(0, 0), isNot(0xffffffff), reason: 'not bare paper');
      // A second save, a second picture, the same image still.
      await tester.tap(find.byKey(const Key('saveProject')));
      await waitForPreparedOpen(tester);
      await cardMade(tester, gallery, 2);
      final again = await _decode(tester, gallery.thumbnailOf(entry)!);
      expect(again.at(0, 0), pixels.at(0, 0));
      expect(tester.takeException(), isNull);
      await studio.finish();
      expect(tester.takeException(), isNull);
    },
    skip: !available,
  );

  testWidgets(
    'nothing is saved into Color’s own folders, and a file found there is not a drawing’s file',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      final recoveryFolder = studio.recovery.recoveryDirectory.path;
      for (final reserved in [
        '${gallery.directory.path}/Chat.edupaint',
        '$recoveryFolder/recovery.edupaint',
        '$recoveryFolder/Chat.edupaint',
      ]) {
        files.savePath = reserved;
        await studio.tap('saveProject');
        expect(
          problem(tester),
          contains('Ce dossier est celui où Color range ses propres copies'),
          reason: reserved,
        );
        expect(files.projects, isEmpty, reason: reserved);
        expect(studio.isDirty, isTrue);
      }
      expect(gallery.rememberCalls, 0);
      // Elsewhere, the save is the usual one.
      files.savePath = _saved;
      await saveWithCard(studio, gallery, 1);
      expect(studio.isDirty, isFalse);

      // A project that lies in the recovery folder, opened with Ouvrir, is
      // taken as a drawing that still has to be saved somewhere: the file
      // there is cleared by Color itself.
      final own = '$recoveryFolder/recovery.edupaint';
      files.projects[own] = Uint8List.fromList(files.projects[_saved]!);
      files.openPath = own;
      await studio.tap('openProject');
      studio.expectCount(1);
      expect(find.text('Mon dessin'), findsOneWidget);
      expect(studio.isDirty, isTrue);
      expect(problem(tester), contains('un dossier que Color vide lui-même'));
      final panels = files.saveDialogCount;
      files.savePath = '/drawings/Retrouvé.edupaint';
      await saveWithCard(studio, gallery, 2);
      expect(files.saveDialogCount, panels + 1);
      expect(files.projects['/drawings/Retrouvé.edupaint'], isNotNull);
      expect(files.projects[own], files.projects[_saved]);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'reopening a card clears the recovery copy of the drawing that it replaces',
    (tester) async {
      final gallery = MemoryGallery();
      final files = _Files();
      final studio = StudioDriver(tester, files: files, gallery: gallery);
      await studio.start();
      await yellowRectangle(studio);
      await saveWithCard(studio, gallery, 1);
      await blueTrait(studio);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(studio.recovery.bytes, isNotNull);
      await reopen(studio, _saved);
      await studio.tap('discardChanges');
      studio.expectCount(1);
      expect(studio.recovery.bytes, isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'on a real folder, the card of a save is complete and read by a later album',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('color-gallery-studio-'),
      ))!;
      addTearDown(() => root.deleteSync(recursive: true));
      final folder = Directory('${root.path}/gallery');
      final studio = StudioDriver(
        tester,
        gallery: GalleryStorage(directory: folder),
      );
      await studio.start();
      await yellowRectangle(studio);
      await studio.tap('saveProject');
      // Real disk and real engine: alternate the two clocks until the card,
      // which takes its place in one step, is there.
      final card = File('${folder.path}/${GalleryStorage.idFor(_saved)}.card');
      for (var attempt = 0; attempt < 400 && !card.existsSync(); attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(card.existsSync(), isTrue);
      // The album tidies its folder after the write: let it finish, on both
      // clocks, before the folder is looked at.
      for (var round = 0; round < 30; round++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pumpAndSettle();

      final (entry, thumbnail, copy) = (await tester.runAsync(() async {
        final later = GalleryStorage(directory: folder);
        final entry = (await later.list()).single;
        return (
          entry,
          await later.readThumbnail(entry),
          await later.readCopy(entry),
        );
      }))!;
      expect(entry.name, 'Mon dessin.edupaint');
      expect(entry.sourcePath, _saved);
      expect((entry.width, entry.height, entry.elementCount), (1200, 800, 1));
      expect(copy, studio.files.projects[_saved]);
      final pixels = await _decode(tester, thumbnail);
      expect((pixels.width, pixels.height), (320, 213));
      expect(pixels.at(93, 86), 0xffeebf4e);
      // Only the album's own card, and nothing beside its folder.
      expect(
        root
            .listSync(recursive: true)
            .whereType<File>()
            .map(
              (file) => file.path
                  .substring(root.path.length + 1)
                  .replaceAll(r'\', '/'),
            )
            .toSet(),
        {'gallery/${GalleryStorage.idFor(_saved)}.card'},
      );
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );
}

class _Pixels {
  _Pixels(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;

  /// Alpha, red, green and blue of one pixel, as 0xAARRGGBB.
  int at(int x, int y) {
    final offset = (y * width + x) * 4;
    return (rgba[offset + 3] << 24) |
        (rgba[offset] << 16) |
        (rgba[offset + 1] << 8) |
        rgba[offset + 2];
  }
}

Future<_Pixels> _decode(WidgetTester tester, Uint8List png) async =>
    (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      ui.Image? image;
      try {
        image = (await codec.getNextFrame()).image;
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        return _Pixels(
          image.width,
          image.height,
          Uint8List.fromList(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          ),
        );
      } finally {
        image?.dispose();
        codec.dispose();
      }
    }))!;
