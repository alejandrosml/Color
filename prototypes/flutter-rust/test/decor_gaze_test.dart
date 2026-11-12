// SPDX-License-Identifier: MIT
// « Les décors à contempler » (Color 1.2): the decor of a universe on the
// whole screen, opened by the button « Regarder » of « Choisis ton
// univers ». It moves as much as it can, unless the calm mode says no; one
// press names a thing; and the way out is one large button, « Mon dessin »,
// that fades and comes back at any touch — always there for a screen
// reader.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/decor.dart';
import 'package:edupaint_flutter_study/decor_gaze.dart';
import 'package:edupaint_flutter_study/decor_motion.dart';
import 'package:edupaint_flutter_study/decor_view.dart';
import 'package:edupaint_flutter_study/language.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/studio_colors.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/universe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  const mac = Size(1440, 900);
  final surface = find.byKey(const Key('drawingSurface'));
  final gazeFinder = find.byType(DecorGaze);
  final leave = find.byKey(const Key('leaveDecorGaze'));
  final card = find.byKey(const Key('decorNameCard'));

  void sized(WidgetTester tester, Size size, {FakeViewPadding? padding}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    if (padding != null) {
      tester.view.viewPadding = padding;
      tester.view.padding = padding;
    }
    addTearDown(tester.view.reset);
  }

  Future<StudioOptionsStore> start(
    WidgetTester tester, {
    Size size = mac,
    StudioOptions options = StudioOptions.defaults,
    bool phone = false,
  }) async {
    sized(tester, size);
    if (phone) {
      tester.view.display.size = size;
      addTearDown(tester.view.display.resetSize);
    }
    final store = StudioOptionsStore.memory(options);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      EduPaintApp(
        files: MemoryFiles(),
        recoveryStorage: MemoryRecovery(),
        options: store,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return store;
  }

  // The decor alone, as the studio would open it.
  Future<void> gaze(
    WidgetTester tester, {
    String universe = 'bureau',
    Size size = const Size(1366, 1024),
    FakeViewPadding? padding,
    DecorMotion motion = DecorMotion.low,
    bool names = true,
    bool calm = false,
  }) async {
    sized(tester, size, padding: padding);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: calm),
            child: DecorGaze(
              universe: UniverseCatalog.instance.named(universe),
              motion: motion,
              names: names,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  DecorView viewOf(WidgetTester tester) =>
      tester.widget<DecorView>(find.byType(DecorView));
  DecorPainting paintingOf(WidgetTester tester) {
    final view = viewOf(tester);
    return DecorPainting(
      view.decor,
      view.layoutIn(tester.getSize(find.byKey(const Key('decor')))),
    );
  }

  // The middle, on the screen, of the named thing [key].
  Offset thing(WidgetTester tester, String key) {
    final painting = paintingOf(tester);
    final name = painting.decor.names.firstWhere((name) => name.key == key);
    return painting.layout.place(name.at, name.anchor).center;
  }

  bool buttonShown(WidgetTester tester) =>
      tester
          .widget<AnimatedOpacity>(find.byKey(const Key('leaveDecorGazeFade')))
          .opacity ==
      1;

  Future<void> close(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  // The decor as it is painted, pixel by pixel.
  Future<ByteData> picture(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
            of: find.byKey(const Key('decor')),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    late ByteData bytes;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    return bytes;
  }

  // The decor of the desk opened from a page, as the studio opens it: it
  // can be left.
  Future<void> opened(WidgetTester tester, {Size size = mac}) async {
    sized(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showDecorGaze(
                context,
                universe: UniverseCatalog.instance.named('bureau'),
                motion: DecorMotion.low,
                names: true,
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(gazeFinder, findsOneWidget);
  }

  testWidgets(
    '« Regarder » : under each universe that has a decor, and it opens the '
    'decor on the whole screen',
    (tester) async {
      final store = await start(tester);
      // A trait, to see that nothing of the drawing is touched.
      await tester.dragFrom(tester.getCenter(surface), const Offset(60, 20));
      await tester.pump();
      expect(find.textContaining('1 élément'), findsOneWidget);

      await tester.tap(find.byKey(const Key('openUniverses')));
      await tester.pumpAndSettle();
      // « Classique » has no decor: nothing to look at.
      expect(find.byKey(const Key('watch-classique')), findsNothing);
      expect(find.byKey(const Key('watch-bureau')), findsOneWidget);
      expect(find.byKey(const Key('watch-papier')), findsOneWidget);
      expect(find.text('Regarder'), findsNWidgets(2));
      // Large enough to press, and the three cards of the row as tall as
      // one another.
      expect(
        tester.getSize(find.byKey(const Key('watch-papier'))).height,
        greaterThanOrEqualTo(48),
      );
      final heights = {
        for (final key in ['classique', 'bureau', 'papier'])
          tester
              .getSize(
                find
                    .ancestor(
                      of: find.byKey(Key('universe-$key')),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .height,
      };
      expect(heights, hasLength(1));

      await tester.tap(find.byKey(const Key('watch-papier')));
      await tester.pumpAndSettle();
      // The decor of the paper, on the whole window; the dialog is gone.
      expect(gazeFinder, findsOneWidget);
      expect(find.byKey(const Key('universeDialog')), findsNothing);
      expect(tester.getSize(gazeFinder), mac);
      expect(tester.getSize(find.byKey(const Key('decor'))), mac);
      expect(
        viewOf(tester).decor,
        same(UniverseCatalog.instance.named('papier').decor),
      );
      expect(viewOf(tester).sheetAtRest, isNull);
      // Looking is not choosing: the studio wears what it wore.
      expect(store.value.universe, '');
      expect(
        identical(
          studioLook.value,
          UniverseCatalog.instance.named('bureau').look,
        ),
        isTrue,
      );
      // The way back: one large button, in sight.
      expect(find.text('Mon dessin'), findsOneWidget);
      expect(buttonShown(tester), isTrue);
      final button = tester.getRect(leave);
      expect(button.height, greaterThanOrEqualTo(56));
      expect(button.width, greaterThanOrEqualTo(160));
      expect(button.topLeft, const Offset(12, 12));

      await tester.tap(leave);
      await tester.pumpAndSettle();
      expect(gazeFinder, findsNothing);
      expect(find.byKey(const Key('universeDialog')), findsNothing);
      // The drawing is as it was, and the studio hears the keyboard again.
      expect(find.textContaining('1 élément'), findsOneWidget);
      expect(store.value.universe, '');
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();
      expect(card, findsOneWidget);
      await close(tester);
    },
    skip: !available,
  );

  testWidgets('an adult takes « Regarder » away', (tester) async {
    final store = await start(tester);
    await tester.tap(find.byKey(const Key('openOptions')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    final option = find.byKey(const Key('optionDecorWatch'));
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    expect(find.text('Bouton « Regarder »'), findsOneWidget);
    expect(store.value.decorWatch, isTrue);
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(store.value.decorWatch, isFalse);
    await tester.tap(find.byKey(const Key('closeOptions')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openUniverses')));
    await tester.pumpAndSettle();
    expect(find.text('Regarder'), findsNothing);
    expect(find.byKey(const Key('watch-bureau')), findsNothing);
    // The cards are still there to be taken.
    await tester.tap(find.byKey(const Key('universe-papier')));
    await tester.pumpAndSettle();
    expect(store.value.universe, 'papier');
    await close(tester);
  }, skip: !available);

  testWidgets(
    'on a tablet, where no decor is shown around the sheet, « Regarder » '
    'shows it',
    (tester) async {
      debugTouchFirstOverride = true;
      addTearDown(() => debugTouchFirstOverride = null);
      await start(tester, size: const Size(1180, 820), phone: true);
      await tester.pumpAndSettle();
      expect(find.byType(DecorView), findsNothing);
      final open = find.byKey(const Key('openUniverses'));
      expect(open, findsOneWidget);
      await tester.tap(open);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('watch-bureau')));
      await tester.pumpAndSettle();
      expect(gazeFinder, findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('decor'))),
        const Size(1180, 820),
      );
      // One touch on the cat: its card.
      await tester.tapAt(thing(tester, 'chat'));
      await tester.pump();
      expect(card, findsOneWidget);
      expect(find.text('Le chat'), findsOneWidget);
      // The back button of the device leaves, as « Mon dessin » does.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(gazeFinder, findsNothing);
      expect(surface, findsOneWidget);
      expect(find.byType(DecorView), findsNothing);
      await close(tester);
    },
    skip: !available,
  );

  testWidgets('looked at, a decor moves as much as it can — or not at all', (
    tester,
  ) async {
    expect(DecorGaze.motionFor(DecorMotion.low), DecorMotion.high);
    expect(DecorGaze.motionFor(DecorMotion.medium), DecorMotion.high);
    expect(DecorGaze.motionFor(DecorMotion.high), DecorMotion.high);
    expect(DecorGaze.motionFor(DecorMotion.none), DecorMotion.none);
    await gaze(tester);
    expect(viewOf(tester).motion, DecorMotion.high);
    expect(viewOf(tester).resting, isNull);
    await close(tester);
    // The calm mode of the adult: nothing moves here either.
    await gaze(tester, motion: DecorMotion.none);
    expect(viewOf(tester).motion, DecorMotion.none);
    await close(tester);

    // It does move: two images two seconds apart differ; in the calm mode,
    // and when the system asks for less motion, they are the same.
    debugDecorStill = false;
    Future<bool> moves({
      DecorMotion motion = DecorMotion.low,
      bool calm = false,
    }) async {
      await gaze(
        tester,
        universe: 'papier',
        size: const Size(800, 600),
        motion: motion,
        calm: calm,
      );
      final before = await picture(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final after = await picture(tester);
      await close(tester);
      for (var index = 0; index < before.lengthInBytes; index += 4) {
        if (before.getUint32(index) != after.getUint32(index)) return true;
      }
      return false;
    }

    expect(await moves(), isTrue);
    expect(await moves(motion: DecorMotion.none), isFalse);
    expect(await moves(calm: true), isFalse);
  }, skip: !available);

  testWidgets(
    'one press names a thing; a press on nothing puts the card away',
    (tester) async {
      await gaze(tester);
      expect(card, findsNothing);
      await tester.tapAt(thing(tester, 'chat'));
      await tester.pump();
      expect(card, findsOneWidget);
      expect(find.text('Le chat'), findsOneWidget);
      expect(find.byKey(const Key('decorNameRing')), findsOneWidget);
      // Another thing: its card takes the place of the first.
      await tester.tapAt(thing(tester, 'horloge'));
      await tester.pump();
      expect(find.text('Le chat'), findsNothing);
      expect(find.text('L’horloge'), findsOneWidget);
      // The pencils, which no sheet hides here.
      await tester.tapAt(thing(tester, 'crayons'));
      await tester.pump();
      expect(find.text('Les crayons de couleur'), findsOneWidget);
      // The card stands whole on the screen, beside its thing.
      final screen = Offset.zero & tester.getSize(gazeFinder);
      final shown = tester.getRect(card);
      expect(
        screen.contains(shown.topLeft) && screen.contains(shown.bottomRight),
        isTrue,
      );
      // A press on the wall, where nothing has a name.
      await tester.tapAt(screen.center - const Offset(0, 300));
      await tester.pump();
      expect(card, findsNothing);
      // A press on the card closes it; nine seconds do too.
      await tester.tapAt(thing(tester, 'ours'));
      await tester.pump();
      await tester.tap(card);
      await tester.pump();
      expect(card, findsNothing);
      await tester.tapAt(thing(tester, 'globe'));
      await tester.pump();
      expect(card, findsOneWidget);
      await tester.pump(DecorNameLayer.shownFor + const Duration(seconds: 1));
      expect(card, findsNothing);
      await close(tester);

      // The adult cut the cards: a press names nothing.
      await gaze(tester, names: false);
      await tester.tapAt(thing(tester, 'chat'));
      await tester.pump();
      expect(card, findsNothing);
      expect(find.byKey(const Key('decorName-chat')), findsNothing);
      await close(tester);
    },
    skip: !available,
  );

  testWidgets(
    '« Mon dessin » fades after a while, and comes back at any touch — '
    'which is not lost',
    (tester) async {
      await gaze(tester);
      expect(buttonShown(tester), isTrue);
      // It stays longer when the decor has just appeared.
      await tester.pump(DecorGaze.shownFor + const Duration(seconds: 1));
      expect(buttonShown(tester), isTrue);
      await tester.pump(DecorGaze.firstShownFor);
      await tester.pump();
      expect(buttonShown(tester), isFalse);
      await tester.pump(DecorGaze.fade);
      // Faded, a press where it was goes through to the decor: it does not
      // leave. And the button is back.
      final where = tester.getCenter(leave);
      await tester.tapAt(where);
      await tester.pump();
      expect(gazeFinder, findsOneWidget);
      expect(buttonShown(tester), isTrue);
      // Now it is there: a press on it leaves — tried further down. It
      // fades again four seconds after the last touch.
      await tester.pump(DecorGaze.shownFor + const Duration(milliseconds: 100));
      await tester.pump();
      expect(buttonShown(tester), isFalse);

      // The touch that brings it back names what it touched as well.
      await tester.tapAt(thing(tester, 'chat'));
      await tester.pump();
      expect(buttonShown(tester), isTrue);
      expect(find.text('Le chat'), findsOneWidget);

      // It stays as long as a finger is down, then four seconds.
      final finger = await tester.startGesture(
        thing(tester, 'plante'),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(seconds: 30));
      expect(buttonShown(tester), isTrue);
      await finger.up();
      await tester.pump(DecorGaze.shownFor - const Duration(milliseconds: 200));
      expect(buttonShown(tester), isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(buttonShown(tester), isFalse);

      // A mouse that moves brings it back too.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(600, 300));
      await mouse.moveTo(const Offset(640, 320));
      await tester.pump();
      expect(buttonShown(tester), isTrue);
      await mouse.removePointer();
      await close(tester);
    },
    skip: !available,
  );

  testWidgets('with less motion asked for, the button comes and goes at once', (
    tester,
  ) async {
    await gaze(tester, calm: true);
    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const Key('leaveDecorGazeFade')))
          .duration,
      Duration.zero,
    );
    expect(viewOf(tester).motion, DecorMotion.high);
    await close(tester);
    await gaze(tester);
    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const Key('leaveDecorGazeFade')))
          .duration,
      DecorGaze.fade,
    );
    await close(tester);
  }, skip: !available);

  testWidgets(
    'the keyboard: Échap leaves, Entrée too, F2 goes round the things',
    (tester) async {
      await opened(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(gazeFinder, findsNothing);

      // Entrée and Espace press the button: there first, pressed then.
      await opened(tester);
      await tester.pump(DecorGaze.firstShownFor + const Duration(seconds: 1));
      await tester.pump();
      expect(buttonShown(tester), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(gazeFinder, findsOneWidget);
      expect(buttonShown(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(gazeFinder, findsNothing);

      // F2 names the things one after the other, from left to right, and
      // Maj + F2 comes back; any key shows the way out.
      await opened(tester);
      await tester.pump(DecorGaze.firstShownFor + const Duration(seconds: 1));
      await tester.pump();
      expect(buttonShown(tester), isFalse);
      final seen = <String>[];
      for (var step = 0; step < 14; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pump();
        expect(card, findsOneWidget);
        final title = tester.widget<Text>(
          find.descendant(of: card, matching: find.byType(Text)).first,
        );
        seen.add(title.data!);
      }
      expect(seen.toSet(), hasLength(14));
      expect(seen.first, 'Le rideau');
      expect(buttonShown(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();
      expect(find.text(seen.first), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(find.text(seen.last), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(gazeFinder, findsNothing);
      await close(tester);
    },
    skip: !available,
  );

  testWidgets(
    'a screen reader always finds « Mon dessin », faded or not, and meets '
    'each thing',
    (tester) async {
      final handle = tester.ensureSemantics();
      await opened(tester, size: const Size(1366, 1024));
      // The view says what it is.
      expect(
        find.bySemanticsLabel(
          RegExp('Le bureau près de la fenêtre : le décor à regarder'),
        ),
        findsWidgets,
      );
      expect(
        tester.getSemantics(leave),
        isSemantics(
          label: 'Mon dessin',
          hint: 'Revenir à mon dessin',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // Each named thing is a button that can be asked about.
      for (final key in ['chat', 'horloge', 'crayons', 'fenetre']) {
        expect(
          tester.getSemantics(find.byKey(Key('decorName-$key'))),
          isSemantics(isButton: true, hasTapAction: true),
          reason: key,
        );
      }
      tester.semantics.tap(find.semantics.byLabel('Le chat'));
      await tester.pump();
      expect(card, findsOneWidget);
      expect(tester.getSemantics(card), isSemantics(isLiveRegion: true));

      // Faded, the button is still there for the reader, and its action
      // leaves — a press of a finger there would not.
      await tester.pump(DecorGaze.firstShownFor + const Duration(seconds: 2));
      await tester.pump(DecorGaze.fade);
      expect(buttonShown(tester), isFalse);
      expect(
        tester.getSemantics(leave),
        isSemantics(label: 'Mon dessin', isButton: true, hasTapAction: true),
      );
      expect(gazeFinder, findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('Mon dessin'));
      await tester.pumpAndSettle();
      expect(gazeFinder, findsNothing);
      handle.dispose();
      await close(tester);
    },
    skip: !available,
  );

  testWidgets('held upright or on its side: the decor follows the screen', (
    tester,
  ) async {
    const notch = FakeViewPadding(top: 47, bottom: 34);
    await gaze(tester, size: const Size(390, 844), padding: notch);
    var painting = paintingOf(tester);
    expect(painting.layout.arrangement, DecorGazeArrangement.stacked);
    // The button keeps away from what the screen hides.
    expect(tester.getRect(leave).topLeft, const Offset(12, 47 + 12));
    // Nothing named is cut by the screen, and everything can be touched.
    final screen = Offset.zero & tester.getSize(gazeFinder);
    for (final name in painting.names) {
      final box = painting.layout.place(name.at, name.anchor);
      expect(
        screen.contains(box.topLeft) &&
            screen.contains(box.bottomRight - const Offset(.01, .01)),
        isTrue,
        reason: name.key,
      );
    }
    expect(painting.names, hasLength(14));
    await tester.tapAt(thing(tester, 'chat'));
    await tester.pump();
    expect(find.text('Le chat'), findsOneWidget);
    final shown = tester.getRect(card);
    expect(
      screen.contains(shown.topLeft) && screen.contains(shown.bottomRight),
      isTrue,
    );
    // A card near the corner of the button does not cover it.
    await tester.tapAt(thing(tester, 'rideau'));
    await tester.pump();
    expect(find.text('Le rideau'), findsOneWidget);
    expect(tester.getRect(card).overlaps(tester.getRect(leave)), isFalse);

    // The telephone is turned: the same view, laid again.
    tester.view.physicalSize = const Size(844, 390);
    tester.view.viewPadding = const FakeViewPadding(left: 47, right: 47);
    tester.view.padding = const FakeViewPadding(left: 47, right: 47);
    await tester.pump();
    painting = paintingOf(tester);
    expect(painting.layout.arrangement, DecorGazeArrangement.beside);
    expect(tester.getRect(leave).topLeft, const Offset(47 + 12, 12));
    expect(
      painting.layout
          .place(const Rect.fromLTWH(0, 0, 266, 407), DecorAnchor.left)
          .left,
      47,
    );
    expect(gazeFinder, findsOneWidget);
    await close(tester);
  }, skip: !available);

  testWidgets('in English the button and the cards speak English', (
    tester,
  ) async {
    appLanguage.value = AppLanguage.english;
    await gaze(tester);
    expect(find.text('My drawing'), findsOneWidget);
    await tester.tapAt(thing(tester, 'chat'));
    await tester.pump();
    expect(find.text('The cat'), findsOneWidget);
    await close(tester);
  }, skip: !available);

  testWidgets(
    'a decor whose images take long beats more slowly, at the same pace',
    (tester) async {
      debugDecorStill = false;
      await gaze(tester, universe: 'papier', size: const Size(800, 600));
      // How many of the next [images] images, a beat apart, differ from
      // the one before.
      Future<int> changes(int images) async {
        var count = 0;
        var before = await picture(tester);
        for (var image = 0; image < images; image++) {
          await tester.pump(DecorView.period);
          final after = await picture(tester);
          for (var index = 0; index < before.lengthInBytes; index += 4) {
            if (before.getUint32(index) != after.getUint32(index)) {
              count++;
              break;
            }
          }
          before = after;
        }
        return count;
      }

      // Quick images: the decor moves at each beat.
      expect(await changes(6), 6);
      // The engine reports images of seventy milliseconds, as a computer
      // without a graphics processor makes them: the beat slows down, in
      // two steps, to one image in three.
      void report(int millis) {
        final micros = millis * 1000;
        tester.binding.platformDispatcher.onReportTimings!([
          for (var image = 0; image < 40; image++)
            ui.FrameTiming(
              vsyncStart: 0,
              buildStart: 0,
              buildFinish: 2000,
              rasterStart: 2000,
              rasterFinish: micros,
              rasterFinishWallTime: micros,
            ),
        ]);
      }

      report(70);
      report(70);
      await tester.pump();
      final slow = await changes(12);
      expect(slow, inInclusiveRange(3, 5));
      // Quick again: thirty images a second again.
      report(4);
      report(4);
      await tester.pump();
      expect(await changes(6), greaterThanOrEqualTo(5));
      await close(tester);
    },
    skip: !available,
  );

  test('the beat of a decor slows down where its images take too long', () {
    const quick = DecorView.period;
    final slow = DecorView.slowerPeriods.first;
    final slowest = DecorView.slowerPeriods.last;
    // Quick images: thirty a second.
    expect(decorBeatFor(8, quick), quick);
    expect(decorBeatFor(29, quick), quick);
    // Images that take longer than the beat: fifteen a second, then ten.
    expect(decorBeatFor(31, quick), slow);
    expect(decorBeatFor(68, slow), slowest);
    expect(decorBeatFor(200, slowest), slowest);
    // Back to a quicker beat only when the images are quick again: the
    // beat does not waver between two.
    expect(decorBeatFor(25, slow), slow);
    expect(decorBeatFor(10, slow), quick);
    expect(decorBeatFor(40, slowest), slowest);
    expect(decorBeatFor(20, slowest), slow);
  });
}
