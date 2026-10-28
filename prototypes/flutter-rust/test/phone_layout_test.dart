// SPDX-License-Identifier: MIT
// Color on a telephone on its side: the sheet takes the whole height, the
// tools stand on its left under the button of the menu, the colours and what
// the tool chooses in a column that scrolls on its right, and the actions of
// the drawing wait in the menu. A tablet keeps its studio, whatever its
// window, and so does a telephone held upright.
import 'dart:io';

import 'package:edupaint_flutter_study/color_palette.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

/// An iPhone 16 on its side: the island on one side, the same room kept on
/// the other, and the bar at its foot.
const iPhone = Size(852, 393);
const iPhoneInsets = EdgeInsets.fromLTRB(59, 0, 59, 21);

/// A common Android telephone, and a small one, without their bars: Color
/// gives them to the sheet.
const android = Size(915, 412);
const smallAndroid = Size(640, 360);

Finder _key(String key) => find.byKey(Key(key));

/// Whether [finder] is drawn scaled down, inside a [FittedBox].
bool _scaled(Finder finder) => find
    .ancestor(of: finder, matching: find.byType(FittedBox))
    .evaluate()
    .isNotEmpty;

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  setUp(() => debugTouchFirstOverride = true);
  tearDown(() => debugTouchFirstOverride = null);

  testWidgets(
    'the sheet takes the whole height between the tools and the colours',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: iPhone, phone: true, padding: iPhoneInsets);
      for (final key in ['phoneMenu', 'toolsRail', 'phoneSideRail']) {
        expect(_key(key), findsOneWidget, reason: key);
      }
      // Nothing of the studio of a computer: its bars would take the room
      // of the sheet.
      for (final key in ['documentToolbar', 'drawingControls', 'saveProject']) {
        expect(_key(key), findsNothing, reason: key);
      }
      final surface = _key('drawingSurface');
      // Laid out for the screen itself, not scaled down.
      expect(_scaled(surface), isFalse);
      final sheet = tester.getRect(surface);
      final tools = tester.getRect(_key('toolsRail'));
      final side = tester.getRect(_key('phoneSideRail'));
      // The whole height of the room the island and the bar leave, but for
      // a thin margin.
      expect(sheet.height, greaterThanOrEqualTo(393 - 21 - 14));
      expect(sheet.left, greaterThan(tools.right));
      expect(sheet.right, lessThan(side.left));
      // Nothing under the island, nor under the bar at the foot.
      expect(tools.left, greaterThanOrEqualTo(59));
      expect(side.right, lessThanOrEqualTo(852 - 59));
      expect(side.bottom, lessThanOrEqualTo(393 - 21));
      // Every tool is in view, a full target for a finger.
      for (final tool in StudioTool.values) {
        final button = tester.getRect(_key(tool.keyName));
        expect(button.width, greaterThanOrEqualTo(48), reason: tool.keyName);
        expect(button.height, greaterThanOrEqualTo(48), reason: tool.keyName);
        expect(button.top, greaterThanOrEqualTo(0), reason: tool.keyName);
        expect(
          button.bottom,
          lessThanOrEqualTo(393 - 21),
          reason: tool.keyName,
        );
      }
      // Annuler and Rétablir are at the top of the column, in view.
      expect(tester.getRect(_key('undo')).bottom, lessThan(side.top + 80));
      await studio.drag(const Offset(-40, -20), const Offset(30, 20));
      await studio.expectPhoneCount(1);
      await tester.tap(_key('undo'));
      await tester.pumpAndSettle();
      await studio.expectPhoneCount(0);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the menu holds the actions and closes after a choice', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start(size: android, phone: true);
    await studio.openPhoneMenu();
    for (final key in StudioDriver.phoneMenuEntries) {
      // No album is given to this studio.
      expect(
        _key(key),
        key == 'openGallery' ? findsNothing : findsOneWidget,
        reason: key,
      );
    }
    // All in view at once, without scrolling.
    for (final key in StudioDriver.phoneMenuEntries.difference({
      'openGallery',
    })) {
      final rect = tester.getRect(_key(key));
      expect(rect.top, greaterThanOrEqualTo(0), reason: key);
      expect(rect.bottom, lessThanOrEqualTo(412), reason: key);
    }
    // The whole sheet is already in view, and nothing is drawn to see
    // again.
    expect(tester.widget<OutlinedButton>(_key('fitPage')).onPressed, isNull);
    expect(
      tester.widget<OutlinedButton>(_key('replayDrawing')).onPressed,
      isNull,
    );
    await tester.tap(_key('closePhoneMenu'));
    await tester.pumpAndSettle();
    expect(_key('phoneMenuDialog'), findsNothing);

    await studio.drag(const Offset(-40, -20), const Offset(30, 20));
    // « Enregistrer » is chosen in the menu, which closes; the button of
    // the menu shows for a moment that the drawing is saved.
    await studio.tap('saveProject');
    expect(_key('phoneMenuDialog'), findsNothing);
    expect(studio.files.projects, hasLength(1));
    expect(_key('savedTick'), findsOneWidget);
    await studio.openPhoneMenu();
    expect(find.textContaining('projet enregistré'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(_key('replayDrawing')).onPressed,
      isNotNull,
    );
    await tester.tap(_key('closePhoneMenu'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('the menu opens the help, and « À propos » keeps the privacy '
      'policy within reach', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start(size: smallAndroid, phone: true);
    await studio.tap('showHelp');
    expect(_key('phoneMenuDialog'), findsNothing);
    expect(_key('helpDialog'), findsOneWidget);
    // A dialog keeps the room it has on a computer, scaled down to the
    // screen: every word of it is there.
    expect(_scaled(_key('helpDialog')), isTrue);
    final help = tester.getRect(_key('helpDialog'));
    expect(help.top, greaterThanOrEqualTo(0));
    expect(help.bottom, lessThanOrEqualTo(360));
    await tester.tap(_key('closeHelp'));
    await tester.pumpAndSettle();
    expect(_key('helpDialog'), findsNothing);

    await studio.tap('aboutColor');
    expect(_key('aboutPrivacy'), findsOneWidget);
    await tester.tap(_key('aboutPrivacy'));
    await tester.pumpAndSettle();
    expect(_key('privacyPolicy'), findsOneWidget);
    // Where the same policy and the help are published.
    expect(
      find.textContaining('https://alejandrosml.github.io/Color/'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('the simplest interface keeps « À propos » in its menu', (
    tester,
  ) async {
    final studio = StudioDriver(
      tester,
      options: StudioOptionsStore.memory(
        const StudioOptions(level: InterfaceLevel.toddler),
      ),
    );
    await studio.start(size: iPhone, phone: true, padding: iPhoneInsets);
    await studio.openPhoneMenu();
    for (final key in ['newProject', 'saveProject', 'aboutColor']) {
      expect(_key(key), findsOneWidget, reason: key);
    }
    // What the simplest interface leaves out of its top bar.
    for (final key in [
      'openProject',
      'importImage',
      'exportImage',
      'layersButton',
      'fitPage',
      'showHelp',
    ]) {
      expect(_key(key), findsNothing, reason: key);
    }
    await tester.tap(_key('closePhoneMenu'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('the column on the right follows the tool', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start(size: smallAndroid, phone: true);
    final side = tester.getRect(_key('phoneSideRail'));

    await studio.tap('tool-rectangle');
    expect(_key('fillShapeCheckbox'), findsOneWidget);
    expect(_key('paint-target-fill'), findsOneWidget);
    await studio.tap('fillShapeCheckbox');
    expect(tester.widget<Checkbox>(_key('fillShapeCheckbox')).value, isTrue);
    await studio.drag(const Offset(-60, -40), const Offset(20, 30));

    await studio.tap('tool-stamp');
    expect(_key('fillShapeCheckbox'), findsNothing);
    expect(_key('chooseStamp'), findsOneWidget);
    await studio.tap('size-large');
    await studio.click(const Offset(70, 0));

    // A chosen element: what can be done with it comes before the colours.
    await studio.tap('tool-select');
    await studio.click(const Offset(70, 0));
    expect(_key('deleteSelection'), findsOneWidget);
    final delete = tester.getRect(_key('deleteSelection'));
    expect(delete.top, lessThan(tester.getRect(_key('paintColorRail')).top));
    expect(delete.bottom, lessThanOrEqualTo(side.bottom));
    await studio.tap('deleteSelection');
    await studio.expectPhoneCount(1);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  for (final level in InterfaceLevel.values) {
    for (final (name, size, insets) in [
      ('iPhone', iPhone, iPhoneInsets),
      ('Android', android, EdgeInsets.zero),
      ('petit Android', smallAndroid, EdgeInsets.zero),
    ]) {
      testWidgets('every tool of « ${level.label} » fits a $name', (
        tester,
      ) async {
        final options = StudioOptions(level: level);
        final studio = StudioDriver(
          tester,
          options: StudioOptionsStore.memory(options),
        );
        await studio.start(size: size, phone: true, padding: insets);
        final scroll = find.descendant(
          of: _key('phoneSideRail'),
          matching: find.byType(Scrollable),
        );
        final lastColour =
            (options.simpleControls ? simplePaintColors : morePaintColors)
                .last
                .rgb
                .toRadixString(16);
        for (final tool in options.tools) {
          await studio.tap(tool.keyName);
          expect(tester.takeException(), isNull, reason: tool.keyName);
          for (final other in options.tools) {
            final rect = tester.getRect(_key(other.keyName));
            expect(
              rect.bottom,
              lessThanOrEqualTo(size.height - insets.bottom),
              reason: '${other.keyName} with ${tool.keyName}',
            );
          }
          // The end of the column is reached by scrolling it.
          await tester.scrollUntilVisible(
            _key('color-$lastColour'),
            120,
            scrollable: scroll,
          );
          expect(tester.takeException(), isNull, reason: tool.keyName);
          await tester.scrollUntilVisible(
            _key('undo'),
            -120,
            scrollable: scroll,
          );
        }
        await studio.finish();
      }, skip: !available);
    }
  }

  testWidgets('a dialog over the sheet keeps its room, scaled down', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start(size: iPhone, phone: true, padding: iPhoneInsets);
    await studio.tap('tool-text');
    await studio.click();
    expect(_key('textDialog'), findsOneWidget);
    expect(_scaled(_key('textDialog')), isTrue);
    final dialog = tester.getRect(_key('textDialog'));
    expect(dialog.top, greaterThanOrEqualTo(0));
    expect(dialog.bottom, lessThanOrEqualTo(393 - 21));
    await studio.write('Bonjour');
    await tester.tap(_key('confirmText'));
    await tester.pumpAndSettle();
    await studio.expectPhoneCount(1);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('a tablet keeps its studio, even in a small window', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    // The window of a tablet, as small as a telephone's screen on its side.
    await studio.start(size: const Size(700, 500));
    expect(_key('phoneMenu'), findsNothing);
    expect(_key('documentToolbar'), findsOneWidget);
    expect(_scaled(_key('drawingSurface')), isTrue);
    await studio.finish();
  }, skip: !available);

  testWidgets('a telephone held upright keeps the whole studio, scaled down', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start(size: const Size(393, 852), phone: true);
    expect(_key('phoneMenu'), findsNothing);
    expect(_key('documentToolbar'), findsOneWidget);
    expect(_scaled(_key('drawingSurface')), isTrue);
    await studio.drag(const Offset(-30, -15), const Offset(20, 15));
    studio.expectCount(1);
    await studio.finish();
  }, skip: !available);
}
