// SPDX-License-Identifier: MIT
// The « Mes dessins » dialog alone, over an album kept in memory.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/french.dart';
import 'package:edupaint_flutter_study/gallery_dialog.dart';
import 'package:edupaint_flutter_study/gallery_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_gallery.dart';

// The moment the tests are run at, in local time like the device's clock.
final _now = DateTime(2026, 10, 3, 16, 30);

void main() {
  Future<void> remember(
    MemoryGallery gallery,
    String name,
    DateTime savedAt, {
    Uint8List? thumbnail,
  }) => gallery.remember(
    sourcePath: '/dessins/$name',
    name: name,
    project: Uint8List.fromList([1, 2, 3]),
    thumbnailPng: thumbnail ?? Uint8List.fromList([9, 9]),
    width: 1200,
    height: 800,
    elementCount: 2,
    savedAt: savedAt,
  );

  /// Shows the dialog over an empty page; the returned list receives its
  /// result once it is closed.
  Future<List<GalleryEntry?>> open(
    WidgetTester tester,
    MemoryGallery gallery, {
    Size size = const Size(1100, 760),
    double textScale = 1,
    Future<void>? ready,
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final results = <GalleryEntry?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('show'),
              onPressed: () async => results.add(
                await showGalleryDialog(
                  context,
                  storage: gallery,
                  now: () => _now,
                  ready: ready,
                ),
              ),
              child: const Text('Montrer'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('show')));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // A wheel turns while the album waits: it never settles by itself.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byKey(const Key('galleryDialog')), findsOneWidget);
    return results;
  }

  // The first bytes of a PNG picture that announces the given size.
  Uint8List pngHeader(int width, int height) {
    final bytes = Uint8List(64);
    bytes.setAll(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    ByteData.sublistView(bytes)
      ..setUint32(8, 13)
      ..setUint32(16, width)
      ..setUint32(20, height);
    bytes.setAll(12, 'IHDR'.codeUnits);
    return bytes;
  }

  String id(String name) => GalleryStorage.idFor('/dessins/$name');

  test(
    'a card is titled like its file, without the extension of a project',
    () {
      expect(cardTitle('Chat.edupaint'), 'Chat');
      expect(cardTitle('Mon chat Câlin.EDUPAINT'), 'Mon chat Câlin');
      expect(cardTitle('été.2026.edupaint'), 'été.2026');
      // Another extension, or none, is part of the name.
      expect(cardTitle('Chat.png'), 'Chat.png');
      expect(cardTitle('Chat'), 'Chat');
      expect(cardTitle('edupaint'), 'edupaint');
      // A name that would be empty stays as it is.
      expect(cardTitle('.edupaint'), '.edupaint');
      expect(cardTitle('  .edupaint'), '  .edupaint');
    },
  );

  test('the moment of a save is said as a child would say it', () {
    final now = DateTime(2026, 10, 3, 16, 30);
    String said(DateTime moment) =>
        savedMoment(moment, now: now).replaceAll('\u00a0', ' ');
    expect(said(DateTime(2026, 10, 3, 14, 5)), 'aujourd’hui à 14 h 05');
    expect(said(DateTime(2026, 10, 3, 0, 0)), 'aujourd’hui à 0 h 00');
    expect(said(DateTime(2026, 10, 3, 23, 59)), 'aujourd’hui à 23 h 59');
    expect(said(DateTime(2026, 10, 2, 9, 30)), 'hier à 9 h 30');
    expect(said(DateTime(2026, 10, 1, 8, 0)), 'le 1er octobre à 8 h 00');
    expect(said(DateTime(2026, 9, 30, 18, 45)), 'le 30 septembre à 18 h 45');
    expect(said(DateTime(2026, 8, 15, 12, 0)), 'le 15 août à 12 h 00');
    expect(said(DateTime(2025, 12, 25, 7, 7)), 'le 25 décembre 2025 à 7 h 07');
    // A clock that was set back: a later day is a date, never « hier ».
    expect(said(DateTime(2026, 10, 4, 10, 0)), 'le 4 octobre à 10 h 00');
    expect(said(DateTime(2027, 1, 1, 10, 0)), 'le 1er janvier 2027 à 10 h 00');
    // Yesterday across a month and a year.
    expect(
      savedMoment(
        DateTime(2026, 2, 28, 21, 15),
        now: DateTime(2026, 3, 1, 8, 0),
      ).replaceAll('\u00a0', ' '),
      'hier à 21 h 15',
    );
    expect(
      savedMoment(
        DateTime(2025, 12, 31, 21, 15),
        now: DateTime(2026, 1, 1, 0, 1),
      ).replaceAll('\u00a0', ' '),
      'hier à 21 h 15',
    );
    // The hour is one unbreakable piece.
    expect(
      savedMoment(DateTime(2026, 10, 3, 14, 5), now: now),
      'aujourd’hui à 14\u00a0h\u00a005',
    );
    // Every month has its name.
    expect(
      {
        for (var month = 1; month <= 12; month++)
          savedMoment(DateTime(2024, month, 10), now: now).split(' ')[2],
      },
      {
        'janvier',
        'février',
        'mars',
        'avril',
        'mai',
        'juin',
        'juillet',
        'août',
        'septembre',
        'octobre',
        'novembre',
        'décembre',
      },
    );
  });

  test('only a small PNG picture is taken for a thumbnail', () {
    expect(isThumbnailPng(pngHeader(320, 213)), isTrue);
    expect(isThumbnailPng(pngHeader(1, 1)), isTrue);
    expect(isThumbnailPng(pngHeader(1024, 1024)), isTrue);
    // A small file can announce a picture that would fill the memory.
    expect(isThumbnailPng(pngHeader(1025, 10)), isFalse);
    expect(isThumbnailPng(pngHeader(10, 1025)), isFalse);
    expect(isThumbnailPng(pngHeader(20000, 20000)), isFalse);
    expect(isThumbnailPng(pngHeader(0xffffffff, 1)), isFalse);
    expect(isThumbnailPng(pngHeader(0, 10)), isFalse);
    expect(isThumbnailPng(pngHeader(10, 0)), isFalse);
    // Not a PNG picture, or not enough of one.
    expect(isThumbnailPng(Uint8List(0)), isFalse);
    expect(isThumbnailPng(Uint8List.fromList([9, 9])), isFalse);
    expect(isThumbnailPng(pngHeader(320, 213).sublist(0, 32)), isFalse);
    expect(isThumbnailPng(pngHeader(320, 213)..[1] = 0x51), isFalse);
    expect(isThumbnailPng(pngHeader(320, 213)..[12] = 0x69), isFalse);
    expect(isThumbnailPng(pngHeader(2000, 10), maxSide: 2000), isTrue);
  });

  testWidgets(
    'a picture that is no thumbnail is not handed to the decoder; its card can be chosen',
    (tester) async {
      final gallery = MemoryGallery();
      await remember(
        gallery,
        'Géant.edupaint',
        DateTime(2026, 10, 2, 9, 30),
        thumbnail: pngHeader(20000, 20000),
      );
      final results = await open(tester, gallery);
      final card = find.byKey(Key('gallery-open-${id('Géant.edupaint')}'));
      expect(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.image_not_supported),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byType(Image)),
        findsNothing,
      );
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(results.single!.name, 'Géant.edupaint');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the pictures of the album leave the cache of images when it closes',
    (tester) async {
      final picture = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 8, 6),
          Paint()..color = const Color(0xff78a66f),
        );
        final recorded = recorder.endRecording();
        final image = await recorded.toImage(8, 6);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          return Uint8List.fromList(data!.buffer.asUint8List());
        } finally {
          image.dispose();
          recorded.dispose();
        }
      }))!;
      expect(isThumbnailPng(picture), isTrue);
      imageCache
        ..clear()
        ..clearLiveImages();
      final gallery = MemoryGallery();
      for (final name in ['Chat.edupaint', 'Maison.edupaint']) {
        await remember(
          gallery,
          name,
          DateTime(2026, 10, 2, 9, 30),
          thumbnail: picture,
        );
      }
      await open(tester, gallery);
      // The engine decodes on its own clock.
      for (var round = 0; round < 20; round++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.byIcon(Icons.image_not_supported), findsNothing);
      expect(imageCache.liveImageCount, 2);
      await tester.tap(find.byKey(const Key('closeGallery')));
      await tester.pumpAndSettle();
      expect(imageCache.liveImageCount, 0);
      expect(imageCache.currentSize, 0);
      expect(imageCache.pendingImageCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the album waits for the cards being made before it says what it holds',
    (tester) async {
      final gallery = MemoryGallery();
      final ready = Completer<void>();
      final results = await open(
        tester,
        gallery,
        ready: ready.future,
        settle: false,
      );
      // Not yet « Aucun dessin »: a card is on its way.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('galleryEmpty')), findsNothing);
      await remember(gallery, 'Chat.edupaint', DateTime(2026, 10, 3, 16, 29));
      ready.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byKey(Key('gallery-open-${id('Chat.edupaint')}')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('closeGallery')));
      await tester.pumpAndSettle();
      expect(results, [null]);

      // A card that could not be made is simply not there.
      final failed = Completer<void>();
      await open(tester, gallery, ready: failed.future, settle: false);
      failed.completeError(StateError('Simulated failed card'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('gallery-open-${id('Chat.edupaint')}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an empty album says how its cards come, and closes', (
    tester,
  ) async {
    final results = await open(tester, MemoryGallery());
    expect(find.text('Mes dessins'), findsOneWidget);
    expect(find.byKey(const Key('galleryEmpty')), findsOneWidget);
    expect(
      find.text(
        'Aucun dessin pour le moment. Dès que tu enregistres un dessin, il se range ici.',
      ),
      findsOneWidget,
    );
    // Nothing to choose from: the sentence about choosing is not shown.
    expect(find.textContaining('Choisis-en un'), findsNothing);
    await tester.tap(find.byKey(const Key('closeGallery')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('galleryDialog')), findsNothing);
    expect(results, [null]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards show the name and the moment, most recent first', (
    tester,
  ) async {
    final gallery = MemoryGallery();
    await remember(gallery, 'Chat.edupaint', DateTime(2026, 10, 2, 9, 30));
    await remember(gallery, 'Maison.edupaint', DateTime(2026, 10, 3, 14, 5));
    await remember(gallery, 'Fusée.edupaint', DateTime(2026, 9, 12, 18, 0));
    await open(tester, gallery);
    expect(find.byKey(const Key('galleryEmpty')), findsNothing);
    expect(find.textContaining('Choisis-en un'), findsOneWidget);

    final house = find.byKey(Key('gallery-open-${id('Maison.edupaint')}'));
    final cat = find.byKey(Key('gallery-open-${id('Chat.edupaint')}'));
    final rocket = find.byKey(Key('gallery-open-${id('Fusée.edupaint')}'));
    expect(tester.getTopLeft(house).dx, lessThan(tester.getTopLeft(cat).dx));
    expect(tester.getTopLeft(cat).dx, lessThan(tester.getTopLeft(rocket).dx));
    expect(tester.getTopLeft(house).dy, tester.getTopLeft(rocket).dy);

    for (final (card, name, moment) in [
      (house, 'Maison', 'aujourd’hui à 14\u00a0h\u00a005'),
      (cat, 'Chat', 'hier à 9\u00a0h\u00a030'),
      (rocket, 'Fusée', 'le 12 septembre à 18\u00a0h\u00a000'),
    ]) {
      // The name of the drawing, without the extension of its file.
      expect(
        find.descendant(of: card, matching: find.text(name)),
        findsOneWidget,
      );
      expect(find.text('$name.edupaint'), findsNothing);
      expect(
        find.descendant(of: card, matching: find.text(moment)),
        findsOneWidget,
      );
      // One name for the whole card, on the node that can be activated.
      final semantics = tester.getSemantics(card);
      expect(semantics.label, 'Reprendre $name, enregistré $moment');
      final data = semantics.getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: name);
      expect(data.flagsCollection.isButton, isTrue, reason: name);
      expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
      // Its way out of the album is a target of its own, named after it.
      final forget = find.byKey(Key('gallery-forget-${id('$name.edupaint')}'));
      expect(tester.getSize(forget).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(forget).height, greaterThanOrEqualTo(48));
      expect(
        find.descendant(of: forget, matching: find.text('Retirer')),
        findsOneWidget,
      );
      final removal = tester.getSemantics(forget);
      expect(removal.label, 'Retirer $name de la galerie');
      expect(
        removal.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: name,
      );
      // The card and its removal are two separate targets.
      expect(
        tester.getRect(forget).top,
        greaterThanOrEqualTo(tester.getRect(card).bottom),
      );
    }
    // A short name and a long one: the cards of a row end together.
    expect(tester.getSize(house).height, tester.getSize(rocket).height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing a card closes the dialog and returns it', (
    tester,
  ) async {
    final gallery = MemoryGallery();
    await remember(gallery, 'Chat.edupaint', DateTime(2026, 10, 2, 9, 30));
    await remember(gallery, 'Maison.edupaint', DateTime(2026, 10, 3, 14, 5));
    final results = await open(tester, gallery);
    await tester.tap(find.byKey(Key('gallery-open-${id('Chat.edupaint')}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('galleryDialog')), findsNothing);
    expect(results.single!.name, 'Chat.edupaint');
    expect(results.single!.sourcePath, '/dessins/Chat.edupaint');
    // Looking is not changing: the album is as it was.
    expect(gallery.entries, hasLength(2));
  });

  testWidgets('Entrée and Échap return to the drawing without choosing', (
    tester,
  ) async {
    final gallery = MemoryGallery();
    await remember(gallery, 'Chat.edupaint', DateTime(2026, 10, 2, 9, 30));
    final results = await open(tester, gallery);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('galleryDialog')), findsNothing);
    expect(results, [null]);

    await tester.tap(find.byKey(const Key('show')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('galleryDialog')), findsNothing);
    expect(results, [null, null]);
  });

  testWidgets(
    'removing a card asks first, says the file stays, and updates the album',
    (tester) async {
      final gallery = MemoryGallery();
      await remember(gallery, 'Chat.edupaint', DateTime(2026, 10, 2, 9, 30));
      await remember(gallery, 'Maison.edupaint', DateTime(2026, 10, 3, 14, 5));
      final results = await open(tester, gallery);
      final forgetCat = find.byKey(
        Key('gallery-forget-${id('Chat.edupaint')}'),
      );

      await tester.tap(forgetCat);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('galleryForgetDialog')), findsOneWidget);
      expect(find.text('Retirer « Chat » de la galerie ?'), findsOneWidget);
      // The copy kept by the album goes with the card; the file does not.
      expect(
        find.text(
          'Sa carte disparaît d’ici, avec la copie que la galerie en gardait. Ton fichier enregistré reste à sa place.',
        ),
        findsOneWidget,
      );
      for (final key in ['cancelGalleryForget', 'confirmGalleryForget']) {
        expect(tester.getSize(find.byKey(Key(key))).height, 48, reason: key);
      }
      await tester.tap(find.byKey(const Key('cancelGalleryForget')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('galleryForgetDialog')), findsNothing);
      expect(gallery.entries, hasLength(2));
      expect(forgetCat, findsOneWidget);

      // Échap in the question is « Annuler » too, and only closes the question.
      await tester.tap(forgetCat);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('galleryDialog')), findsOneWidget);
      expect(gallery.entries, hasLength(2));

      await tester.tap(forgetCat);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmGalleryForget')));
      await tester.pumpAndSettle();
      expect(gallery.entries.single.name, 'Maison.edupaint');
      expect(forgetCat, findsNothing);
      expect(
        find.byKey(Key('gallery-open-${id('Maison.edupaint')}')),
        findsOneWidget,
      );
      // The album is still open, and nothing was chosen.
      expect(find.byKey(const Key('galleryDialog')), findsOneWidget);
      expect(results, isEmpty);

      await tester.tap(
        find.byKey(Key('gallery-forget-${id('Maison.edupaint')}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmGalleryForget')));
      await tester.pumpAndSettle();
      expect(gallery.entries, isEmpty);
      expect(find.byKey(const Key('galleryEmpty')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an album that cannot be read says so and points to Ouvrir', (
    tester,
  ) async {
    final gallery = MemoryGallery()..failList = true;
    final results = await open(tester, gallery);
    expect(find.byKey(const Key('galleryUnavailable')), findsOneWidget);
    expect(find.textContaining('retrouve-les avec Ouvrir'), findsOneWidget);
    expect(find.byKey(const Key('galleryEmpty')), findsNothing);
    await tester.tap(find.byKey(const Key('closeGallery')));
    await tester.pumpAndSettle();
    expect(results, [null]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card whose picture is missing can still be chosen', (
    tester,
  ) async {
    final gallery = _NoPictureGallery();
    await remember(gallery, 'Chat.edupaint', DateTime(2026, 10, 2, 9, 30));
    final results = await open(tester, gallery);
    final card = find.byKey(Key('gallery-open-${id('Chat.edupaint')}'));
    expect(
      find.descendant(
        of: card,
        matching: find.byIcon(Icons.image_not_supported),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(results.single!.name, 'Chat.edupaint');
  });

  testWidgets(
    'in a small window with enlarged text every card and the way back are reachable',
    (tester) async {
      final gallery = MemoryGallery();
      for (var number = 1; number <= 7; number++) {
        await remember(
          gallery,
          'Mon très long nom de dessin numéro $number.edupaint',
          DateTime(2026, 9, number, 10, 0),
        );
      }
      final results = await open(
        tester,
        gallery,
        size: const Size(680, 520),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      final close = tester.getRect(find.byKey(const Key('closeGallery')));
      expect(close.bottom, lessThanOrEqualTo(520));
      expect(close.height, greaterThanOrEqualTo(48));
      // The oldest card is the last: it is reached by scrolling.
      final last = find.byKey(
        Key(
          'gallery-open-${id('Mon très long nom de dessin numéro 1.edupaint')}',
        ),
        skipOffstage: false,
      );
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      final rect = tester.getRect(last);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(680));
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(results.single!.name, endsWith('numéro 1.edupaint'));
      expect(tester.takeException(), isNull);
    },
  );
}

class _NoPictureGallery extends MemoryGallery {
  @override
  Future<Uint8List> readThumbnail(GalleryEntry entry) =>
      Future.error(const FormatException('Simulated damaged picture'));
}
