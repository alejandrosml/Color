// SPDX-License-Identifier: MIT
// The colouring pages in « Nouveau »: the catalogue of the core as the
// interface reads it, and the section of the dialog that offers the pages.
import 'dart:io';

import 'package:edupaint_flutter_study/coloring_pages.dart';
import 'package:edupaint_flutter_study/new_sheet_dialog.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/interface_font.dart';

const _square =
    'D f #ffffffff,n #2f3d4aff,6,rr,4 '
    'M 100 100 L 1100 100 L 1100 700 L 100 700 Z';

// One page in the format of the core.
String _entry(int id, String key, String title, {String? picture}) =>
    'T $id $key 3 2 $title\n${picture ?? 'P $key 1200 800\n$_square\nX'}\n';

// The same names as the pages of the core, for a test that runs without it.
final _named = [
  _entry(0, 'bateau', 'Le bateau'),
  _entry(1, 'bonhomme-de-neige', 'Le bonhomme de neige'),
  _entry(2, 'chat', 'Le chat'),
  _entry(3, 'chenille', 'La chenille'),
  _entry(4, 'dinosaure', 'Le dinosaure'),
  _entry(5, 'fleur', 'La fleur'),
  _entry(6, 'fusee', 'La fus%C3%A9e'),
  _entry(7, 'maison', 'La maison'),
  _entry(8, 'poisson', 'Le poisson'),
  _entry(9, 'robot', 'Le robot'),
  _entry(10, 'tortue', 'La tortue'),
  _entry(11, 'voiture', 'La voiture'),
].join();

const _desktop = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
});

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  // The pages of the core when there is one; the same names otherwise.
  List<ColoringPage> offered() => available
      ? ColoringPages.parse(RustDocument.readPageCatalog())
      : ColoringPages.parse(_named);

  Future<void> open(
    WidgetTester tester,
    List<ColoringPage> pages,
    void Function(NewSheetChoice?) closed, {
    double text = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(text)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open'),
              onPressed: () async => closed(
                await showDialog<NewSheetChoice>(
                  context: context,
                  builder: (_) => NewSheetDialog(pages: pages),
                ),
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  // Whether the keyboard is on the page of [key].
  bool focusedOn(WidgetTester tester, String key) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    return find
        .ancestor(
          of: find.byElementPredicate((element) => element == focused),
          matching: find.byKey(Key(key)),
        )
        .evaluate()
        .isNotEmpty;
  }

  test('the catalogue of the core gives every page, its title decoded', () {
    final text = RustDocument.readPageCatalog();
    final pages = ColoringPages.parse(text);
    expect(pages, hasLength('\nT '.allMatches('\n$text').length));
    expect(pages.length, greaterThanOrEqualTo(6));
    expect(pages.map((page) => page.id), List.generate(pages.length, (i) => i));
    final titles = {for (final page in pages) page.key: page.title};
    expect(titles['fusee'], 'La fusée');
    expect(titles['bonhomme-de-neige'], 'Le bonhomme de neige');
    for (final page in pages) {
      // The landscape sheet that « Nouveau » proposes first.
      expect((page.width, page.height), (1200, 800), reason: page.key);
      expect(page.picture.key, page.key);
      expect(page.regions, greaterThanOrEqualTo(3), reason: page.key);
      expect(page.elementCount, page.regions + page.details);
    }
    // The pages of the process are those of the core.
    ColoringPages.debugUse(null);
    expect(ColoringPages.all.map((page) => page.key), titles.keys);
  }, skip: !available);

  test('every page makes a document of its own, locked around the layer of the child', () {
    final pages = offered();
    for (final page in pages) {
      final document = RustDocument.fromPage(page.id);
      try {
        expect((document.width, document.height), (page.width, page.height));
        // Zones under the drawing, lines over it; the drawing is empty.
        expect(document.layers.map((layer) => (layer.id, layer.locked)), [
          (1, true),
          (0, false),
          (2, true),
        ], reason: page.key);
        expect(document.layers.first.objectCount, page.regions);
        expect(document.layers[1].objectCount, 0);
        expect(document.layers.every((layer) => layer.visible), isTrue);
        expect(document.activeLayer, 0);
        expect(document.unlockedPaintOrder, isEmpty);
        expect(document.paintOrder, hasLength(document.count));
        // Nothing of the page is a step to undo.
        expect(document.canUndo, isFalse);
        expect(document.canRedo, isFalse);
        for (final zone in document.strokes.where((o) => o.layer == 1)) {
          expect(zone.kind.canFill, isTrue, reason: page.key);
          expect(zone.fillRgb, 0xffffff, reason: page.key);
        }
        for (final line in document.strokes.where((o) => o.layer == 2)) {
          expect(line.fillRgb, isNull, reason: page.key);
        }
      } finally {
        document.dispose();
      }
    }
    // A page the core does not have makes no document.
    expect(() => RustDocument.fromPage(pages.length), throwsStateError);
    expect(() => RustDocument.fromPage(-1), throwsArgumentError);
    expect(() => RustDocument.fromPage(1 << 32), throwsArgumentError);
  }, skip: !available);

  test('a page that cannot be read is left out alone', () {
    final pages = ColoringPages.parse(
      [
        _entry(0, 'un', 'Un'),
        // A title that is not %XX, or not UTF-8.
        _entry(1, 'deux', 'Deu%G1'),
        _entry(2, 'trois', 'Trois %C3'),
        // A picture of another key, of half units, or cut short.
        _entry(3, 'quatre', 'Quatre', picture: 'P autre 1200 800\n$_square\nX'),
        _entry(4, 'cinq', 'Cinq', picture: 'P cinq 1200.5 800\n$_square\nX'),
        _entry(5, 'six', 'Six', picture: 'P six 1200 800\n$_square'),
        // Fields that the core never writes.
        _entry(-1, 'sept', 'Sept'),
        _entry(8, 'Huit', 'Huit'),
        'T 9 neuf 3 2\nP neuf 1200 800\n$_square\nX\n',
        _entry(10, 'dix', 'Dix'),
        'G 1 -\n',
        _entry(11, 'onze', 'La f%C3%A9e'),
      ].join(),
    );
    expect(pages.map((page) => (page.id, page.key, page.title)), [
      (0, 'un', 'Un'),
      (10, 'dix', 'Dix'),
      (11, 'onze', 'La fée'),
    ]);
  });

  test('titles travel as printable ASCII and %XX bytes of UTF-8', () {
    expect(ColoringPages.decodeTitle('La fus%C3%A9e'), 'La fusée');
    expect(
      ColoringPages.decodeTitle('50 %25 d%E2%80%99%c3%a9t%C3%A9'),
      '50 % d’été',
    );
    for (final wrong in ['', ' ', '%', '%4', '%ZZ', '%C3', 'été', 'a\tb']) {
      expect(
        () => ColoringPages.decodeTitle(wrong),
        throwsFormatException,
        reason: wrong,
      );
    }
  });

  testWidgets('without pages the dialog offers the empty sheets only', (
    tester,
  ) async {
    await open(tester, const [], (_) {});
    expect(find.text('Ou une page à colorier'), findsNothing);
    expect(find.byKey(const Key('coloringPagesTitle')), findsNothing);
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'pages fit 680x520 at text $scale as large named buttons, chosen at once',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(680, 520);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // Real letters: the box font of the tests is far wider than they
        // are, and no title would fit the width of a page.
        await loadInterfaceFont(tester);
        final semantics = tester.ensureSemantics();
        try {
          final pages = offered();
          NewSheetChoice? result;
          var closed = false;
          await open(tester, pages, (choice) {
            result = choice;
            closed = true;
          }, text: scale);
          expect(find.text('Ou une page à colorier'), findsOneWidget);
          // The empty sheets come first, as before.
          final square = tester.getRect(
            find.byKey(const Key('newSheet-square')),
          );
          final heading = tester.getRect(
            find.byKey(const Key('coloringPagesTitle')),
          );
          expect(heading.top - square.bottom, greaterThanOrEqualTo(8));
          // Measured together, at one position of the scrolling.
          Rect? previous;
          for (final page in pages) {
            final rect = tester.getRect(find.byKey(Key('page-${page.key}')));
            // Far above the 48 pixels of any control: a picture to touch.
            expect(rect.width, greaterThanOrEqualTo(96), reason: page.key);
            expect(rect.height, greaterThanOrEqualTo(96), reason: page.key);
            if (previous != null) {
              final apart = rect.top < previous.bottom
                  ? rect.left - previous.right
                  : rect.top - previous.bottom;
              expect(apart, greaterThanOrEqualTo(8), reason: page.key);
            }
            previous = rect;
          }
          for (final page in pages) {
            final tile = find.byKey(Key('page-${page.key}'));
            await tester.ensureVisible(tile);
            await tester.pumpAndSettle();
            final data = tester.getSemantics(tile).getSemanticsData();
            expect(data.label, page.title);
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.hasAction(SemanticsAction.tap), isTrue);
            // The title is written whole under its picture.
            final title = find.descendant(
              of: tile,
              matching: find.text(page.title),
            );
            expect(
              tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
              isFalse,
              reason: page.key,
            );
            // The picture has the shape of the sheet of the page.
            final picture = tester.getSize(
              find.descendant(of: tile, matching: find.byType(AspectRatio)),
            );
            expect(
              picture.width / picture.height,
              closeTo(page.width / page.height, .01),
            );
            expect(picture.width, greaterThanOrEqualTo(96));
          }
          for (final key in ['cancelNewSheet', 'createNewSheet']) {
            final rect = tester.getRect(find.byKey(Key(key)));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.bottom, lessThanOrEqualTo(520));
          }
          expect(closed, isFalse);
          final chosen = pages[pages.length ~/ 2];
          await tester.ensureVisible(find.byKey(Key('page-${chosen.key}')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(Key('page-${chosen.key}')));
          await tester.pumpAndSettle();
          expect(closed, isTrue);
          expect(result, same(chosen));
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
      variant: _desktop,
    );
  }

  testWidgets(
    'the keyboard goes from the shapes to the pages, then to the buttons',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(680, 520);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pages = offered();
      final results = <NewSheetChoice?>[];
      await open(tester, pages, results.add, text: 1.5);
      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      // One stop for the shapes, then each page in reading order.
      for (final page in pages) {
        await press(LogicalKeyboardKey.tab);
        expect(focusedOn(tester, 'page-${page.key}'), isTrue, reason: page.key);
        // The page reached is seen in the dialog.
        final viewport = tester.getRect(find.byType(SingleChildScrollView));
        final rect = tester.getRect(find.byKey(Key('page-${page.key}')));
        expect(rect.top, greaterThanOrEqualTo(viewport.top - .5));
        expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + .5));
      }
      await press(LogicalKeyboardKey.tab);
      expect(focusedOn(tester, 'cancelNewSheet'), isTrue);
      await press(LogicalKeyboardKey.tab);
      expect(focusedOn(tester, 'createNewSheet'), isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(focusedOn(tester, 'page-${pages.last.key}'), isTrue);
      await press(LogicalKeyboardKey.enter);
      expect(results, [same(pages.last)]);
      expect(tester.takeException(), isNull);
    },
    variant: _desktop,
  );
}
