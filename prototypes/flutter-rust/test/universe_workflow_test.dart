// SPDX-License-Identifier: MIT
// The universes in the studio (Color 1.2): the decor around the sheet, the
// button « Univers » and what an adult fixes, the four levels of movement
// and the calm of the system, the light that follows an injected clock,
// and the cards that name the things of the decor.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/decor.dart';
import 'package:edupaint_flutter_study/decor_motion.dart';
import 'package:edupaint_flutter_study/decor_view.dart';
import 'package:edupaint_flutter_study/language.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/studio_colors.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_shapes.dart';
import 'package:edupaint_flutter_study/universe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'flutter_test_config.dart';
import 'support/memory_files.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  const mac = Size(1440, 900);
  final surface = find.byKey(const Key('drawingSurface'));
  final decorFinder = find.byKey(const Key('decor'));

  Future<StudioOptionsStore> start(
    WidgetTester tester, {
    Size size = mac,
    StudioOptions options = StudioOptions.defaults,
    DateTime Function()? clock,
    bool phone = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    if (phone) {
      tester.view.display.size = size;
      addTearDown(tester.view.display.resetSize);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = StudioOptionsStore.memory(options);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      EduPaintApp(
        files: MemoryFiles(),
        recoveryStorage: MemoryRecovery(),
        options: store,
        clock: clock,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return store;
  }

  // The decor as it is painted, pixel by pixel: red, green, blue, opacity.
  Future<(ByteData, int)> picture(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(of: decorFinder, matching: find.byType(RepaintBoundary))
          .first,
    );
    late ByteData bytes;
    late int width;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      width = image.width;
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    return (bytes, width);
  }

  Color pixel((ByteData, int) image, Offset at) {
    final (bytes, width) = image;
    final index = (at.dy.round() * width + at.dx.round()) * 4;
    return Color.fromARGB(
      bytes.getUint8(index + 3),
      bytes.getUint8(index),
      bytes.getUint8(index + 1),
      bytes.getUint8(index + 2),
    );
  }

  int differences((ByteData, int) a, (ByteData, int) b) {
    expect(a.$1.lengthInBytes, b.$1.lengthInBytes);
    var count = 0;
    for (var index = 0; index < a.$1.lengthInBytes; index += 4) {
      if (a.$1.getUint32(index) != b.$1.getUint32(index)) count++;
    }
    return count;
  }

  // The decor of the studio as its frame lays it.
  DecorPainting painting(WidgetTester tester) {
    final view = tester.widget<DecorView>(find.byType(DecorView));
    final frame = tester.getSize(decorFinder);
    return DecorPainting(
      view.decor,
      DecorLayout(
        frame: frame,
        sheetAtRest: view.sheetAtRest!,
        decor: view.decor.size,
        decorSheet: view.decor.sheet,
      ),
    );
  }

  // Where a point of the decor is, in its frame and on the screen.
  Offset inFrame(WidgetTester tester, Offset at, DecorAnchor anchor) =>
      painting(tester).layout.point(at, anchor);
  Offset onScreen(WidgetTester tester, Offset at, DecorAnchor anchor) =>
      tester.getTopLeft(surface) + inFrame(tester, at, anchor);

  const cat = Offset(989, 320);
  const curtain = Offset(22, 160);

  Future<void> doubleTap(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.tapAt(at);
    await tester.pump();
  }

  testWidgets(
    'the studio wears the first universe: its decor around the sheet',
    (tester) async {
      await start(tester);
      expect(decorFinder, findsOneWidget);
      expect(
        tester.widget<DecorView>(find.byType(DecorView)).motion,
        DecorMotion.low,
      );
      final shown = painting(tester);
      expect(shown.decor, same(UniverseCatalog.instance.named('bureau').decor));
      expect(shown.layout.pieces, isTrue);
      // The sheet is where it was: white, in the middle, over the decor.
      final view = tester.widget<DecorView>(find.byType(DecorView));
      final frame = tester.getSize(surface);
      expect(view.sheetAtRest!.center.dx, closeTo(frame.width / 2, .5));
      final image = await picture(tester);
      // The wall above the sheet, the wood of the desk under it.
      final wall = pixel(image, Offset(frame.width / 2, 6));
      expect(wall.r > .9 && wall.b > .93, isTrue, reason: '$wall');
      final wood = pixel(
        image,
        Offset(frame.width / 2 + 150, frame.height - 4),
      );
      expect(wood.r > wood.b + .15, isTrue, reason: '$wood');
      // The captions are written on pills: read on any picture.
      expect(find.byType(DecorCaption), findsNWidgets(3));
      expect(find.byKey(const Key('openUniverses')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !available,
  );

  testWidgets(
    'the child chooses a universe: the studio dresses at once, the drawing stays',
    (tester) async {
      final store = await start(tester);
      // A trait, to see that nothing of the drawing is touched.
      final centre = tester.getCenter(surface);
      await tester.dragFrom(centre, const Offset(60, 20));
      await tester.pump();
      expect(find.textContaining('1 élément'), findsOneWidget);
      expect(studioLook.value, UniverseCatalog.instance.named('bureau').look);

      await tester.tap(find.byKey(const Key('openUniverses')));
      await tester.pumpAndSettle();
      expect(find.text('Choisis ton univers'), findsOneWidget);
      expect(find.text('Classique'), findsOneWidget);
      expect(find.text('Papier et crayons'), findsOneWidget);
      // The universe of the moment is marked, and said to a screen reader.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Icon && widget.semanticLabel == 'Univers choisi',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('universe-papier')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('universeDialog')), findsNothing);
      expect(store.value.universe, 'papier');
      final paper = UniverseCatalog.instance.named('papier');
      expect(studioLook.value, paper.look);
      expect(painting(tester).decor, same(paper.decor));
      // The whole studio wears it: the background of the window, the buttons
      // cut out along a dotted line — also what was built once and for all.
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor ??
            Theme.of(tester.element(surface)).scaffoldBackgroundColor,
        paper.look.background,
      );
      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('newProject')),
      );
      final shape =
          (button.style?.shape ??
                  Theme.of(tester.element(surface))
                      .outlinedButtonTheme
                      .style!
                      .shape)!
              .resolve({});
      expect(shape, isA<DashedRoundedBorder>());
      final image = await picture(tester);
      final kraft = pixel(image, Offset(tester.getSize(surface).width / 2, 6));
      expect(
        (kraft.r - .82).abs() < .06 && kraft.b < .6,
        isTrue,
        reason: '$kraft',
      );
      // The drawing has not moved.
      expect(find.textContaining('1 élément'), findsOneWidget);

      // Left without a choice, nothing changes.
      await tester.tap(find.byKey(const Key('openUniverses')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('closeUniverses')));
      await tester.pumpAndSettle();
      expect(store.value.universe, 'papier');
      // And back to the desk.
      await tester.tap(find.byKey(const Key('openUniverses')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('universe-bureau')));
      await tester.pumpAndSettle();
      expect(store.value.universe, 'bureau');
      expect(studioLook.value.background, StudioLook.classic.background);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !available,
  );

  testWidgets('an adult fixes a universe: the button « Univers » goes', (
    tester,
  ) async {
    final store = await start(
      tester,
      options: const StudioOptions(universe: 'papier', universeFixed: true),
    );
    await tester.pumpAndSettle();
    expect(studioLook.value, UniverseCatalog.instance.named('papier').look);
    expect(find.byKey(const Key('openUniverses')), findsNothing);

    await tester.tap(find.byKey(const Key('openOptions')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Univers et effets'), findsOneWidget);
    Future<void> choose(String key) async {
      final chip = find.byKey(Key(key));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('universe-fixed-papier')))
          .selected,
      isTrue,
    );
    await choose('universe-fixed-bureau');
    expect(store.value.universe, 'bureau');
    expect(store.value.universeFixed, isTrue);
    // Behind the dialog the studio already wears the desk.
    expect(studioLook.value.background, StudioLook.classic.background);
    await choose('universe-child');
    expect(store.value.universeFixed, isFalse);
    expect(store.value.universe, 'bureau');
    // The movement, and the cards.
    for (final motion in DecorMotion.values) {
      await choose('motion-${motion.code}');
      expect(store.value.decorMotion, motion);
    }
    await choose('optionDecorNames');
    expect(store.value.decorNames, isFalse);
    await tester.tap(find.byKey(const Key('closeOptions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('openUniverses')), findsOneWidget);
    expect(
      tester.widget<DecorView>(find.byType(DecorView)).motion,
      DecorMotion.high,
    );
    await tester.pumpWidget(const SizedBox());
  }, skip: !available);

  testWidgets('four levels of movement: each one wider, nothing at « Aucun »', (
    tester,
  ) async {
    debugDecorStill = false;
    final store = await start(
      tester,
      options: const StudioOptions(decorMotion: DecorMotion.none),
    );
    final made = debugDecorStillImages;
    final rest = await picture(tester);
    // « Aucun »: time passes, nothing moves, and nothing ticks.
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(differences(rest, await picture(tester)), 0);

    // At each level the same moment of the sway, wider: more of the decor
    // differs from its rest.
    final moved = <DecorMotion, int>{};
    for (final motion in [
      DecorMotion.low,
      DecorMotion.medium,
      DecorMotion.high,
    ]) {
      await tester.pumpWidget(const SizedBox());
      store.value = store.value.copyWith(decorMotion: motion);
      await tester.pumpWidget(
        EduPaintApp(
          files: MemoryFiles(),
          recoveryStorage: MemoryRecovery(),
          options: store,
        ),
      );
      await tester.pump();
      // The middle of the sway of the curtains, nine seconds long: its
      // widest. The image of what does not move is made once.
      final before = debugDecorStillImages;
      for (var step = 0; step < 45; step++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(debugDecorStillImages - before, lessThanOrEqualTo(1));
      moved[motion] = differences(rest, await picture(tester));
    }
    expect(moved[DecorMotion.low], greaterThan(200));
    expect(moved[DecorMotion.medium], greaterThan(moved[DecorMotion.low]!));
    expect(moved[DecorMotion.high], greaterThan(moved[DecorMotion.medium]!));
    expect(debugDecorStillImages, greaterThan(made));

    // The adult asks for calm while the decor moves: it stops where its
    // pictures draw it.
    store.value = store.value.copyWith(decorMotion: DecorMotion.none);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(differences(rest, await picture(tester)), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  }, skip: !available);

  testWidgets('« Réduire les animations » of the system stills the decor', (
    tester,
  ) async {
    debugDecorStill = false;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await start(
      tester,
      options: const StudioOptions(decorMotion: DecorMotion.high),
    );
    final rest = await picture(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(differences(rest, await picture(tester)), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    // The system lets go: the decor moves again, as the adult chose.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pump();
    for (var step = 0; step < 45; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(differences(rest, await picture(tester)), greaterThan(200));
    await tester.pumpWidget(const SizedBox());
  }, skip: !available);

  testWidgets('out of sight, nothing ticks; back in front, the decor goes on', (
    tester,
  ) async {
    debugDecorStill = false;
    await start(tester);
    for (var step = 0; step < 10; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    final hidden = await picture(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(differences(hidden, await picture(tester)), 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    for (var step = 0; step < 30; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(differences(hidden, await picture(tester)), greaterThan(100));
    await tester.pumpWidget(const SizedBox());
  }, skip: !available);

  testWidgets('while a trait goes on the decor waits, then moves on', (
    tester,
  ) async {
    debugDecorStill = false;
    await start(
      tester,
      options: const StudioOptions(decorMotion: DecorMotion.high),
    );
    for (var step = 0; step < 10; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final made = debugDecorStillImages;
    // A trait begins on the sheet: at its next tick the decor stops, and
    // every image of the trait finds it as it was.
    final gesture = await tester.startGesture(
      tester.getCenter(surface),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 100));
    final held = await picture(tester);
    for (var step = 0; step < 20; step++) {
      await gesture.moveBy(const Offset(3, 1));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(differences(held, await picture(tester)), 0);
    expect(debugDecorStillImages, made);
    // The trait ends: the decor goes on from where it stopped.
    await gesture.up();
    for (var step = 0; step < 20; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(differences(held, await picture(tester)), greaterThan(100));
    expect(debugDecorStillImages, made);
    await tester.pumpWidget(const SizedBox());
  }, skip: !available);

  testWidgets('the first image leaves the decor for the next one', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = mac;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final decor = UniverseCatalog.instance.named('bureau').decor!;
    const behind = Color(0xff224466);
    final made = debugDecorStillImages;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              child: SizedBox.fromSize(
                size: decor.size,
                child: DecorView(
                  decor: decor,
                  sheetAtRest: decor.sheet,
                  motion: DecorMotion.low,
                  corners: 12,
                  behind: behind,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The first image: the colour of the room, and nothing of the decor
    // read or drawn yet.
    expect(debugDecorStillImages, made);
    final first = await picture(tester);
    final middle = decor.size.center(Offset.zero);
    expect(pixel(first, middle).toARGB32(), decor.top.toARGB32());
    expect(pixel(first, const Offset(1, 1)).toARGB32(), behind.toARGB32());
    // The next one: the decor, its corners in the colour behind the frame.
    await tester.pump();
    expect(debugDecorStillImages, made + 1);
    final second = await picture(tester);
    expect(differences(first, second), greaterThan(10000));
    for (final corner in [
      const Offset(1, 1),
      Offset(decor.size.width - 2, 1),
      Offset(1, decor.size.height - 2),
      Offset(decor.size.width - 2, decor.size.height - 2),
    ]) {
      expect(pixel(second, corner).toARGB32(), behind.toARGB32());
    }
    // And no pixel of it lets anything through.
    final (bytes, _) = second;
    for (var index = 3; index < bytes.lengthInBytes; index += 4) {
      if (bytes.getUint8(index) != 255) fail('a pixel is not opaque');
    }
    await tester.pumpWidget(const SizedBox());
  }, skip: !available);

  testWidgets(
    'the light follows the hour of the device, and the clock is at the time',
    (tester) async {
      // The clock of this test, not the fixed hour of the others.
      debugDecorNow = null;
      var now = DateTime(2026, 11, 12, 15, 0);
      await start(tester, clock: () => now);
      final clock = painting(tester).decor.live
          .firstWhere((piece) => piece.clock != null)
          .clock!;
      const ink = Color(0xff293d4b);
      bool dark(Color colour) =>
          colour.r < .35 && colour.g < .4 && colour.b < .45;
      Offset hand(WidgetTester tester, double dx, double dy) =>
          inFrame(tester, clock.centre + Offset(dx, dy), DecorAnchor.right);

      // Three o'clock: the large hand on twelve, the small one on three.
      var image = await picture(tester);
      expect(dark(pixel(image, hand(tester, 0, -12))), isTrue);
      expect(dark(pixel(image, hand(tester, 8, 0))), isTrue);
      expect(dark(pixel(image, hand(tester, -8, 0))), isFalse);
      expect(dark(pixel(image, hand(tester, 0, 12))), isFalse);
      // By day: the wall is light, the bulb is off, the cloud is in the sky.
      final wallAt = Offset(tester.getSize(surface).width / 2, 6);
      final bulb = inFrame(
        tester,
        const Offset(870.63, 265.52),
        DecorAnchor.right,
      );
      final day = pixel(image, wallAt);
      expect(day.computeLuminance(), greaterThan(.8));
      final made = debugDecorStillImages;

      // A minute passes: the large hand has moved on, nothing else is made
      // again.
      now = DateTime(2026, 11, 12, 15, 15);
      await tester.pump(const Duration(seconds: 61));
      image = await picture(tester);
      expect(dark(pixel(image, hand(tester, 12, 0))), isTrue);
      expect(dark(pixel(image, hand(tester, 0, -12))), isFalse);
      expect(debugDecorStillImages, made);

      // Five o'clock: the evening. The room is tinted, the lamp is lit, and
      // in its beam the colours stay bright.
      now = DateTime(2026, 11, 12, 17, 0);
      await tester.pump(const Duration(seconds: 61));
      image = await picture(tester);
      expect(debugDecorStillImages, made + 1);
      final evening = pixel(image, wallAt);
      expect(
        evening.computeLuminance(),
        lessThan(day.computeLuminance() - .05),
      );
      expect(evening.r, greaterThan(evening.b));
      final lit = pixel(image, bulb);
      expect(lit.computeLuminance(), greaterThan(.85));

      // Ten past ten at night: dark, but for the beam of the lamp.
      now = DateTime(2026, 11, 12, 22, 10);
      await tester.pump(const Duration(seconds: 61));
      image = await picture(tester);
      final night = pixel(image, wallAt);
      expect(night.computeLuminance(), lessThan(.3));
      expect(night.b, greaterThan(night.r));
      final frame = tester.getSize(surface);
      final inBeam = pixel(image, Offset(frame.width - 40, frame.height - 12));
      final outOfBeam = pixel(
        image,
        Offset(frame.width / 2 + 150, frame.height - 4),
      );
      expect(
        inBeam.computeLuminance(),
        greaterThan(outOfBeam.computeLuminance() + .2),
      );
      // The sheet is never tinted: it is not in this picture at all.
      expect(ink, isNotNull);

      // The morning comes back, with its warm light.
      now = DateTime(2026, 11, 13, 8, 0);
      await tester.pump(const Duration(seconds: 61));
      image = await picture(tester);
      final morning = pixel(image, wallAt);
      expect(morning.computeLuminance(), greaterThan(.7));
      expect(morning.r, greaterThan(day.r - .02));
      expect(morning.b, lessThan(day.b));
      await tester.pumpWidget(const SizedBox());
    },
    skip: !available,
  );

  testWidgets('a double click beside the sheet names what is there', (
    tester,
  ) async {
    await start(tester);
    final card = find.byKey(const Key('decorNameCard'));
    expect(card, findsNothing);
    // One click says nothing.
    await tester.tapAt(onScreen(tester, cat, DecorAnchor.right));
    await tester.pump();
    expect(card, findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await doubleTap(tester, onScreen(tester, cat, DecorAnchor.right));
    expect(card, findsOneWidget);
    expect(find.text('Le chat'), findsOneWidget);
    expect(find.textContaining('douze heures par jour'), findsOneWidget);
    expect(find.byKey(const Key('decorNameRing')), findsOneWidget);
    // A press on the card puts it away.
    await tester.tap(card);
    await tester.pump();
    expect(card, findsNothing);
    // Left alone, it goes after nine seconds.
    await doubleTap(tester, onScreen(tester, curtain, DecorAnchor.left));
    expect(find.text('Le rideau'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(card, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(card, findsNothing);
    // A press anywhere else puts it away too; Échap as well.
    await doubleTap(tester, onScreen(tester, cat, DecorAnchor.right));
    expect(card, findsOneWidget);
    await tester.tapAt(
      onScreen(tester, const Offset(600, 395), DecorAnchor.middle),
    );
    await tester.pump();
    expect(card, findsNothing);
    await doubleTap(tester, onScreen(tester, cat, DecorAnchor.right));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(card, findsNothing);
    // On the wall, where nothing has a name: nothing.
    await doubleTap(tester, tester.getTopLeft(surface) + const Offset(300, 8));
    expect(card, findsNothing);
    // Two clicks too far apart in time are two clicks.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final at = onScreen(tester, cat, DecorAnchor.right);
    await gesture.down(at, timeStamp: const Duration(seconds: 100));
    await gesture.up(timeStamp: const Duration(seconds: 100, milliseconds: 50));
    await gesture.down(at, timeStamp: const Duration(seconds: 101));
    await gesture.up(timeStamp: const Duration(seconds: 101, milliseconds: 50));
    await tester.pump();
    expect(card, findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  }, skip: !available);

  testWidgets(
    'the sheet is never asked for a name, and the tool is never stopped',
    (tester) async {
      await start(tester);
      final card = find.byKey(const Key('decorNameCard'));
      final centre = tester.getCenter(surface);
      // Two clicks on the sheet are two dots of the brush.
      await doubleTap(tester, centre);
      expect(card, findsNothing);
      expect(find.textContaining('2 éléments'), findsOneWidget);
      // A trait that begins on the decor and crosses the sheet is drawn.
      final from = onScreen(tester, cat, DecorAnchor.right);
      await tester.dragFrom(
        centre + const Offset(-80, 60),
        const Offset(160, -30),
      );
      await tester.pump();
      expect(find.textContaining('3 éléments'), findsOneWidget);
      // With the cards switched off, the decor answers nothing.
      final store = tester
          .widget<EduPaintApp>(find.byType(EduPaintApp))
          .options!;
      await store.change(store.value.copyWith(decorNames: false));
      await tester.pump();
      await doubleTap(tester, from);
      expect(card, findsNothing);
      expect(find.byKey(const Key('decorName-chat')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !available,
  );

  testWidgets(
    'a finger asks by two touches or a long one; the keyboard by F2',
    (tester) async {
      await start(tester);
      final card = find.byKey(const Key('decorNameCard'));
      final at = onScreen(tester, cat, DecorAnchor.right);
      // A long touch.
      final finger = await tester.startGesture(
        at,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(card, findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      expect(card, findsOneWidget);
      expect(find.text('Le chat'), findsOneWidget);
      await finger.up();
      await tester.tap(card);
      await tester.pump();
      // A finger that moves away was not asking.
      final moving = await tester.startGesture(
        at,
        kind: PointerDeviceKind.touch,
      );
      await moving.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(seconds: 1));
      expect(card, findsNothing);
      await moving.up();
      await tester.pump(const Duration(seconds: 1));

      // F2: the things of the decor, from left to right; Maj + F2 goes back.
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();
      expect(find.text('Le rideau'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();
      expect(find.text('Le rideau'), findsNothing);
      expect(card, findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(find.text('Le rideau'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(card, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !available,
  );

  testWidgets(
    'the simplest interface: what the sheet would hide is not shown; the '
    'pencils, beside the sheet, always are',
    (tester) async {
      final handle = tester.ensureSemantics();
      // How far the colours of the band that the sheet leaves under it go
      // from one another, along the sheet: the widest gap of red, green or
      // blue, out of 255. The grain of the wood is a few; an eraser or a
      // brush, many.
      Future<int> band() async {
        final frame = tester.getSize(decorFinder);
        final sheet = tester.widget<DecorView>(find.byType(DecorView));
        final below = (sheet.sheetAtRest!.bottom + frame.height) / 2;
        final image = await picture(tester);
        final low = [255, 255, 255];
        final high = [0, 0, 0];
        for (
          var x = sheet.sheetAtRest!.left + 4;
          x < sheet.sheetAtRest!.right - 4;
          x += 3
        ) {
          final colour = pixel(image, Offset(x, below)).toARGB32();
          for (var channel = 0; channel < 3; channel++) {
            final value = (colour >> (8 * channel)) & 0xff;
            if (value < low[channel]) low[channel] = value;
            if (value > high[channel]) high[channel] = value;
          }
        }
        return [
          for (var channel = 0; channel < 3; channel++)
            high[channel] - low[channel],
        ].reduce((a, b) => a > b ? a : b);
      }

      // With the captions, the eraser and the brush lie in the band under
      // the sheet. The pencils are on the left of the desk, in front of
      // the books: nothing that has a name lies under the sheet.
      await start(tester);
      final pencils = painting(tester).decor.names
          .firstWhere((name) => name.key == 'crayons');
      expect(pencils.anchor, DecorAnchor.left);
      expect(
        painting(tester).decor.names
            .where((name) => name.anchor == DecorAnchor.middle),
        isEmpty,
      );
      expect(painting(tester).layout.under, isTrue);
      expect(find.byKey(const Key('decorName-crayons')), findsOneWidget);
      expect(await band(), greaterThan(60));
      await tester.pumpWidget(const SizedBox());

      // In the simplest interface the sheet takes the band: nothing is
      // painted there. The pencils stay, a screen reader meets them, and
      // F2 goes round the fourteen things.
      await start(
        tester,
        options: const StudioOptions(level: InterfaceLevel.toddler),
      );
      final simple = painting(tester);
      expect(simple.layout.pieces, isTrue);
      expect(simple.layout.under, isFalse);
      expect(simple.names, hasLength(14));
      expect(find.byKey(const Key('decorName-crayons')), findsOneWidget);
      expect(find.byKey(const Key('decorName-chat')), findsOneWidget);
      // What is left of the band: the ground alone, the wood of the desk.
      expect(await band(), lessThan(8));
      final seen = <String>{};
      for (var step = 0; step < 15; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pump();
        expect(find.byKey(const Key('decorNameCard')), findsOneWidget);
        for (final name in simple.decor.names) {
          if (find.text(name.frenchName).evaluate().isNotEmpty) {
            seen.add(name.key);
          }
        }
      }
      expect(seen, hasLength(14));
      expect(seen, contains('crayons'));
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    },
    skip: !available,
  );

  testWidgets('a screen reader meets each named thing, and its card is read', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await start(tester);
    expect(painting(tester).names, hasLength(14));
    for (final name in painting(tester).decor.names) {
      expect(find.byKey(Key('decorName-${name.key}')), findsOneWidget);
    }
    final catNode = tester.getSemantics(
      find.byKey(const Key('decorName-chat')),
    );
    expect(catNode.label, 'Le chat');
    expect(catNode.hint, 'En savoir plus');
    expect(
      catNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    tester.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: catNode.id,
      ),
    );
    await tester.pump();
    final card = find.byKey(const Key('decorNameCard'));
    expect(card, findsOneWidget);
    expect(
      tester.getSemantics(card).getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  }, skip: !available);

  testWidgets('in English the decor speaks English', (tester) async {
    await start(
      tester,
      options: const StudioOptions(language: LanguageChoice.english),
    );
    await tester.pumpAndSettle();
    expect(find.text('Worlds'), findsOneWidget);
    await doubleTap(tester, onScreen(tester, cat, DecorAnchor.right));
    expect(find.text('The cat'), findsOneWidget);
    expect(find.textContaining('twelve hours a day'), findsOneWidget);
    await tester.tap(find.byKey(const Key('decorNameCard')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('openUniverses')));
    await tester.pumpAndSettle();
    expect(find.text('Choose your world'), findsOneWidget);
    expect(find.text('Paper and pencils'), findsOneWidget);
    await tester.tap(find.byKey(const Key('closeUniverses')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  }, skip: !available);

  testWidgets(
    'beside the sheet the pointer of the system shows; on it, « la pointe »',
    (tester) async {
      await start(tester);
      MouseCursor cursor() => tester
          .widget<MouseRegion>(
            find
                .ancestor(of: surface, matching: find.byType(MouseRegion))
                .first,
          )
          .cursor;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(surface));
      await mouse.moveTo(tester.getCenter(surface) + const Offset(4, 4));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.none);
      // On the wall beside the sheet: the arrow.
      await mouse.moveTo(tester.getTopLeft(surface) + const Offset(300, 8));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.basic);
      // On the cat: the arrow that asks.
      await mouse.moveTo(onScreen(tester, cat, DecorAnchor.right));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.help);
      await mouse.moveTo(tester.getCenter(surface));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.none);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
    skip: !available,
  );

  testWidgets(
    'over a decor the captions of the sheet stand along the sheet, and '
    'cover nothing of the decor',
    (tester) async {
      const captions = ['MA FEUILLE', '1200 × 800 unités', 'Toute la feuille'];
      for (final size in const [mac, Size(1920, 1080), Size(1024, 768)]) {
        await start(tester, size: size);
        final shown = painting(tester);
        final origin = tester.getTopLeft(surface);
        final sheet = tester
            .widget<DecorView>(find.byType(DecorView))
            .sheetAtRest!
            .shift(origin);
        for (final caption in captions) {
          final pill = tester.getRect(
            find.ancestor(
              of: find.text(caption),
              matching: find.byType(DecorCaption),
            ),
          );
          // Within the width of the sheet, just above or just under it:
          // the pieces of the decor stand beside the sheet, never there.
          expect(pill.left, greaterThanOrEqualTo(sheet.left - .5));
          expect(pill.right, lessThanOrEqualTo(sheet.right + .5));
          expect(
            pill.bottom <= sheet.top + .5 || pill.top >= sheet.bottom - .5,
            isTrue,
            reason: '$caption, $size',
          );
          for (final name in shown.names) {
            expect(
              pill.overlaps(
                shown.layout.place(name.at, name.anchor).shift(origin),
              ),
              isFalse,
              reason: '$caption sur ${name.key}, $size',
            );
          }
        }
        await tester.pumpWidget(const SizedBox());
      }
      // Without a decor they keep the corners of the frame, as always.
      await start(tester, size: const Size(900, 1000));
      expect(find.byType(DecorCaption), findsNothing);
      final frame = tester.getRect(surface);
      expect(
        tester.getTopLeft(find.text('MA FEUILLE')),
        frame.topLeft + const Offset(16, 10),
      );
      expect(
        frame.bottomRight -
            tester.getBottomRight(find.text('Toute la feuille')),
        const Offset(16, 9),
      );
      await tester.pumpWidget(const SizedBox());
    },
    skip: !available,
  );

  testWidgets('a narrow frame: the decor smaller, or no decor at all', (
    tester,
  ) async {
    await start(tester, size: const Size(1024, 768));
    final smaller = painting(tester);
    final frame = tester.getSize(decorFinder);
    expect(smaller.layout.pieces, isTrue);
    expect(smaller.layout.scale, lessThan(frame.height / 407));
    // Everything named stands beside the sheet at rest.
    final sheet = tester.widget<DecorView>(find.byType(DecorView)).sheetAtRest!;
    for (final name in smaller.decor.names) {
      if (name.anchor == DecorAnchor.middle) continue;
      final box = smaller.layout.place(name.at, name.anchor);
      expect(
        box.right <= sheet.left + .5 || box.left >= sheet.right - .5,
        isTrue,
        reason: name.key,
      );
    }
    await tester.pumpWidget(const SizedBox());

    // Where the pieces would be too small to be looked at, a ground alone
    // has no interest (the owner, 12 November 2026): no decor is shown,
    // the frame is plain, in the colour of the universe.
    await start(tester, size: const Size(900, 1000));
    expect(decorFinder, findsNothing);
    expect(find.byType(DecorView), findsNothing);
    // Nothing to ask about, and the pointer of the tool everywhere.
    expect(find.byKey(const Key('decorName-chat')), findsNothing);
    final stage = tester.getRect(surface);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.ancestor(of: surface, matching: find.byType(RepaintBoundary)).first,
    );
    late Color corner;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final origin = boundary.localToGlobal(Offset.zero);
      final at = stage.topLeft - origin + const Offset(40, 3);
      final index = (at.dy.round() * image.width + at.dx.round()) * 4;
      corner = Color.fromARGB(
        255,
        bytes.getUint8(index),
        bytes.getUint8(index + 1),
        bytes.getUint8(index + 2),
      );
      image.dispose();
    });
    expect(corner.toARGB32(), studioSheetBackdrop.toARGB32());
    // The studio still wears the universe: its colours and its shapes.
    expect(
      identical(
        studioLook.value,
        UniverseCatalog.instance.named('bureau').look,
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  }, skip: !available);

  testWidgets(
    'on a tablet and on a telephone, no decor around the sheet, whatever '
    'their size',
    (tester) async {
      debugTouchFirstOverride = true;
      addTearDown(() => debugTouchFirstOverride = null);
      // A telephone on its side, a tablet, and the largest of the tablets:
      // the sheet takes the screen. Nobody chose a universe: it is
      // « Classique », which has no decor.
      for (final size in const [
        Size(844, 390),
        Size(1180, 820),
        Size(1366, 1024),
      ]) {
        await start(tester, size: size, phone: true);
        await tester.pumpAndSettle();
        expect(decorFinder, findsNothing, reason: '$size');
        expect(find.byType(DecorView), findsNothing, reason: '$size');
        expect(find.byKey(const Key('decorName-chat')), findsNothing);
        expect(identical(studioLook.value, StudioLook.classic), isTrue);
        await tester.pumpWidget(const SizedBox());
      }
      // The child took the paper: the studio wears its colours and its
      // shapes, and still shows no decor around the sheet.
      for (final universe in ['papier', 'bureau']) {
        await start(
          tester,
          size: const Size(1366, 1024),
          options: StudioOptions(universe: universe),
          phone: true,
        );
        await tester.pumpAndSettle();
        expect(decorFinder, findsNothing, reason: universe);
        expect(find.byType(DecorView), findsNothing, reason: universe);
        expect(
          identical(
            studioLook.value,
            UniverseCatalog.instance.named(universe).look,
          ),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
      }
      expect(studioLook.value.buttonDashed, isFalse);
      expect(testDecorTime.hour, 14);
    },
    skip: !available,
  );
}
