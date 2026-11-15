// SPDX-License-Identifier: MIT
// What the pebbles wear (Color 1.2, step G3): light pebbles or those of the
// night, read from the description of a universe; the round under each
// picture; the dialogs, made of the matter of the pebbles; the notice of a
// problem, which no longer covers the line; the actions of a chosen
// element, which no longer cover it.
import 'dart:io';

import 'package:edupaint_flutter_study/galets.dart';
import 'package:edupaint_flutter_study/studio_colors.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_printer.dart';
import 'package:edupaint_flutter_study/studio_theme.dart';
import 'package:edupaint_flutter_study/universe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_printer.dart';
import 'support/studio_driver.dart';
import 'support/trial_universes.dart';

Finder _key(String key) => find.byKey(Key(key));

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('a description says « nuit » : pebbles of the night', () {
    final night = StudioLook.fromJson(nightTrialLook);
    expect(night.night, isTrue);
    expect(night.surface, const Color(0xff232a66));
    expect(night.ink, const Color(0xffeef0ff));
    expect(night.galetDisc, const Color(0xffeceeff));
    // Written with how opaque it is: a thin line, half seen.
    expect(night.galetEdge, const Color(0x8c8f97f2));
    expect(night.shadow, const Color(0xff000000));
    expect(night.shadowDepth, 2.6);
    // White letters cannot be read on a white accent: the full buttons
    // are written in the dark of the pebble.
    expect(night.onAccent, night.surface);
    expect(StudioLook.classic.onAccent, const Color(0xffffffff));
    // Pebbles of the night that name no round still have one.
    final bare = StudioLook.fromJson({'galets': 'nuit'});
    expect(bare.night, isTrue);
    expect(bare.galetDisc, StudioLook.nightDisc);
    expect(bare.galetEdge, isNull);
    // « clair », or anything else, is the light pebbles of always.
    expect(
      identical(StudioLook.fromJson({'galets': 'clair'}), StudioLook.classic),
      isTrue,
    );
    expect(StudioLook.fromJson({'galets': 7}).night, isFalse);
  });

  test('every text of the pebbles of the night can be read', () {
    final look = nightTrialUniverse().look;
    for (final (name, text, surface) in look.textOnSurface) {
      expect(
        StudioLook.contrast(text, surface),
        greaterThanOrEqualTo(4.5),
        reason: name,
      );
    }
    for (final (name, mark, surface) in look.marksOnSurface) {
      expect(
        StudioLook.contrast(mark, surface),
        greaterThanOrEqualTo(3),
        reason: name,
      );
    }
    // The rounds are part of what is measured.
    expect(
      look.marksOnSurface.map((entry) => entry.$1),
      contains('trait d’une image, sur sa pastille'),
    );
  });

  test('the shadows of the pebbles follow the look', () {
    final night = nightTrialUniverse().look;
    final light = galetFloatShadow(StudioLook.classic);
    final dark = galetFloatShadow(night);
    // A thin line around a pebble of the night, which takes no room.
    expect(light, hasLength(2));
    expect(dark, hasLength(3));
    expect(dark.first.spreadRadius, 1.5);
    expect(dark.first.blurRadius, 0);
    expect(dark.first.color, night.galetEdge);
    // Deeper on a dark sky, and never opaque.
    expect(dark.last.color.a, greaterThan(light.last.color.a * 2));
    expect(galetPanelShadow(night).last.color.a, lessThanOrEqualTo(.72));
  });

  testWidgets('the pebbles of the night: a round under each picture, the '
      'same places', (tester) async {
    useTrialUniverses();
    Future<Map<String, Rect>> places(String universe) async {
      final store = StudioOptionsStore.memory(
        StudioOptions(universe: universe),
      );
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(1440, 900));
      final found = {
        for (final key in [
          'myDrawing',
          'openUniverses',
          'tool-stroke',
          'tool-stamp',
          'galetSize',
          'galetWhich',
          'color-e83d48',
          'saveProject',
          'sheetAtRest',
        ])
          key: tester.getRect(_key(key)),
      };
      return found;
    }

    final light = await places('classique');
    expect(_key('galetDisc'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    final night = await places(nightTrialKey);
    // Nothing moved: the rounds take no room.
    expect(night, light);
    expect(studioLook.value.night, isTrue);
    // One round under each of the nine tools, at least.
    expect(_key('galetDisc').evaluate().length, greaterThanOrEqualTo(9));
    final disc = tester.widget<DecoratedBox>(_key('galetDisc').first);
    expect((disc.decoration as BoxDecoration).color, const Color(0xffeceeff));
    // A round is larger than its picture, and stays inside its button.
    final tool = tester.getRect(_key('tool-line'));
    final round = tester.getRect(
      find.descendant(of: _key('tool-line'), matching: _key('galetDisc')),
    );
    expect(round.width, 40);
    expect(tool.contains(round.topLeft), isTrue);
    expect(tool.contains(round.bottomRight), isTrue);
    // The dialogs follow: a dark theme, the surface of the pebbles.
    final theme = Theme.of(tester.element(_key('tool-stroke')));
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.onSurface, const Color(0xffeef0ff));
    await pressControl(tester, 'layersButton');
    final dialog = tester.widget<Material>(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );
    expect(dialog.color, const Color(0xff232a66));
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !available);

  testWidgets('the dialogs are made of the matter of the pebbles', (
    tester,
  ) async {
    for (final universe in ['classique', 'papier']) {
      final store = StudioOptionsStore.memory(
        StudioOptions(universe: universe),
      );
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(1440, 900));
      final look = UniverseCatalog.instance.named(universe).look;
      final theme = Theme.of(tester.element(_key('tool-stroke')));
      expect(theme.brightness, Brightness.light, reason: universe);
      // The letters of the pebbles, everywhere.
      expect(theme.textTheme.bodyMedium!.fontFamily, studioFontFamily);
      expect(theme.textTheme.labelLarge!.fontFamily, studioFontFamily);
      await studio.tap('newProject');
      final dialog = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );
      // The surface of the universe, with no tint of its own, and the
      // corners of a panel: 26 points at most, 12 in the paper.
      expect(dialog.color, look.surface, reason: universe);
      final shape = dialog.shape! as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        BorderRadius.circular(universe == 'papier' ? 12 : 26),
        reason: universe,
      );
      // A full button has the shape of a button of a pebble, and stays a
      // target of 48 points.
      final button = find.byType(FilledButton).first;
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      final material = tester.widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first,
      );
      expect(
        (material.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(universe == 'papier' ? 12 : 24),
        reason: universe,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  }, skip: !available);

  testWidgets('the notice of a problem: a pebble over the top of the sheet, '
      'which goes by itself', (tester) async {
    final printer = FakePrinter()..outcome = PrintOutcome.noPrinter;
    final studio = StudioDriver(tester, printer: printer.call);
    await studio.start(size: const Size(1440, 900));
    await studio.drag(const Offset(-80, 0), const Offset(80, 30));
    expect(_key('galetNotice'), findsNothing);
    await printAndWait(tester, printer);
    await tester.pumpAndSettle();
    expect(_key('problemMessage'), findsOneWidget);
    final notice = tester.getRect(_key('galetNotice'));
    // Under the pebbles of the top, over the top of the sheet, in the
    // middle of the window: no button is under it.
    expect(notice.top, greaterThan(tester.getRect(_key('myDrawing')).bottom));
    expect(notice.bottom, lessThan(tester.getRect(_key('tool-stroke')).top));
    expect(notice.center.dx, closeTo(720, 1));
    for (final key in ['tool-stroke', 'color-e83d48', 'saveProject']) {
      expect(notice.overlaps(tester.getRect(_key(key))), isFalse, reason: key);
    }
    // It is read aloud when it appears, and can be closed.
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(_key('galetNotice'))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    semantics.dispose();
    expect(tester.getSize(_key('closeProblem')).height, 48);
    // Nothing more to say of this one: no « Détails », and it goes after
    // twelve seconds.
    expect(_key('showProblemDetails'), findsNothing);
    await tester.pump(const Duration(seconds: 11));
    expect(_key('galetNotice'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_key('galetNotice'), findsNothing);
    // Shown again, a press closes it at once.
    await printAndWait(tester, printer);
    await tester.pumpAndSettle();
    await tester.tap(_key('closeProblem'));
    await tester.pumpAndSettle();
    expect(_key('galetNotice'), findsNothing);
    await studio.finish();
  }, skip: !available);

  testWidgets('between two rails the notice stands over the sheet', (
    tester,
  ) async {
    final printer = FakePrinter()..outcome = PrintOutcome.noPrinter;
    final studio = StudioDriver(tester, printer: printer.call);
    await studio.start(size: const Size(680, 520));
    expect(studio.rails, isTrue);
    await studio.drag(const Offset(-40, 0), const Offset(40, 20));
    await printAndWait(tester, printer);
    await tester.pumpAndSettle();
    final notice = tester.getRect(_key('galetNotice'));
    final sheet = tester.getRect(_key('sheetAtRest'));
    expect(notice.left, greaterThanOrEqualTo(sheet.left - 1));
    expect(notice.right, lessThanOrEqualTo(sheet.right + 1));
    expect(notice.top, lessThan(40));
    for (final key in ['myDrawing', 'toolDrawer', 'saveProject']) {
      expect(notice.overlaps(tester.getRect(_key(key))), isFalse, reason: key);
    }
    await studio.finish();
  }, skip: !available);

  testWidgets('the actions of a chosen element never cover it', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start(size: const Size(1440, 900));
    final sheet = tester.getRect(_key('sheetAtRest'));
    // One trait in the middle of the sheet, one along its foot.
    await studio.drag(const Offset(-120, -40), const Offset(120, 0));
    final low = Offset(0, sheet.height / 2 - 14);
    await studio.drag(low + const Offset(-90, 0), low + const Offset(90, 0));
    await studio.tap('tool-select');
    // The one in the middle: its actions stand just above the line.
    await tester.tapAt(sheet.center + const Offset(0, -20));
    await tester.pumpAndSettle();
    final line = tester.getRect(_key('tool-stroke'));
    var actions = tester.getRect(_key('duplicateSelection'));
    expect(actions.bottom, lessThan(line.top));
    expect(actions.top, greaterThan(sheet.center.dy));
    // The one at the foot: they would cover it, and go to the top of the
    // sheet, under the pebbles.
    await tester.tapAt(sheet.center + low);
    await tester.pumpAndSettle();
    actions = tester.getRect(_key('duplicateSelection'));
    expect(actions.top, greaterThan(tester.getRect(_key('myDrawing')).bottom));
    expect(actions.bottom, lessThan(sheet.center.dy));
    expect(actions.bottom, lessThan(sheet.center.dy + low.dy - 20));
    // They still work from there.
    await studio.tap('duplicateSelection');
    studio.expectCount(3);
    await studio.finish();
  }, skip: !available);
}
