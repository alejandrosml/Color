// SPDX-License-Identifier: MIT
// Color on a telephone on its side: the sheet takes the whole height, the
// tools stand on its left under the button of the menu, the colours and what
// the tool chooses in a column that scrolls on its right, and the actions of
// the drawing wait in the menu. A tablet keeps its studio, whatever its
// window, and so does a telephone held upright.
import 'dart:io';

import 'package:edupaint_flutter_study/galets.dart';
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

  testWidgets('the sheet takes the whole height between the two rails', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start(size: iPhone, phone: true, padding: iPhoneInsets);
    for (final key in [
      'phoneMenu',
      'galetLeftRail',
      'galetRightRail',
      'toolDrawer',
      'saveProject',
      'railColour',
    ]) {
      expect(_key(key), findsOneWidget, reason: key);
    }
    // Nothing of a wider window: no line, no pebble at the top — they
    // would take the room of the sheet.
    for (final key in ['galetLine', 'galetColours', 'openUniverses']) {
      expect(_key(key), findsNothing, reason: key);
    }
    final surface = _key('drawingSurface');
    // Laid out for the screen itself, not scaled down.
    expect(_scaled(surface), isFalse);
    final sheet = tester.getRect(_key('sheetAtRest'));
    final tools = tester.getRect(_key('galetLeftRail'));
    final side = tester.getRect(_key('galetRightRail'));
    // The whole height of the room the island and the bar leave, but for
    // a thin margin: 534 by 356, as it was drawn.
    expect(sheet.height, closeTo(356, 1));
    expect(sheet.width, closeTo(534, 1));
    expect(sheet.left, greaterThan(tools.right));
    expect(sheet.right, lessThan(side.left));
    // Nothing under the island, nor under the bar at the foot.
    expect(tools.left, greaterThanOrEqualTo(59));
    expect(side.right, lessThanOrEqualTo(852 - 59));
    expect(tools.bottom, lessThanOrEqualTo(393 - 21));
    expect(side.bottom, lessThanOrEqualTo(393 - 21));
    // Four tools under the thumb, each a full target for a finger.
    for (final tool in [
      ToolGroup.brush,
      ToolGroup.fill,
      ToolGroup.stamp,
      ToolGroup.eraser,
    ]) {
      final button = tester.getRect(_key(tool.keyName));
      expect(button.width, greaterThanOrEqualTo(48), reason: tool.keyName);
      expect(button.height, greaterThanOrEqualTo(48), reason: tool.keyName);
      expect(button.top, greaterThanOrEqualTo(0), reason: tool.keyName);
      expect(button.bottom, lessThanOrEqualTo(393 - 21), reason: tool.keyName);
    }
    // Every tool waits in the drawer, with its name.
    await tester.tap(_key('toolDrawer'));
    await tester.pumpAndSettle();
    for (final tool in ToolGroup.values) {
      expect(_key('drawer-${tool.keyName}'), findsOneWidget);
      expect(find.text(tool.label), findsOneWidget, reason: tool.keyName);
    }
    await studio.closePanel();
    // Annuler and Rétablir are on the right, in view.
    expect(tester.getRect(_key('undo')).bottom, lessThan(393 - 21));
    await studio.drag(const Offset(-40, -20), const Offset(30, 20));
    await studio.expectPhoneCount(1);
    await tester.tap(_key('undo'));
    await tester.pumpAndSettle();
    await studio.expectPhoneCount(0);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

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
    expect(await drawingStatus(tester), contains('projet enregistré'));
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

  testWidgets('the drawer follows the tool', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start(size: smallAndroid, phone: true);

    await studio.tap('tool-rectangle');
    await studio.reveal('fillShapeCheckbox');
    expect(_key('fillShapeCheckbox'), findsOneWidget);
    expect(_key('paint-target-fill'), findsOneWidget);
    await studio.tap('fillShapeCheckbox');
    await studio.reveal('fillShapeCheckbox');
    expect(tester.widget<Checkbox>(_key('fillShapeCheckbox')).value, isTrue);
    await studio.closePanel();
    await studio.drag(const Offset(-60, -40), const Offset(20, 30));

    await studio.tap('tool-stamp');
    await studio.reveal('chooseStamp');
    expect(_key('fillShapeCheckbox'), findsNothing);
    expect(_key('chooseStamp'), findsOneWidget);
    await studio.tap('size-large');
    await studio.click(const Offset(70, 0));

    // A chosen element: what can be done with it stands at the foot of
    // the sheet, between the rails.
    await studio.tap('tool-select');
    await studio.click(const Offset(70, 0));
    expect(_key('deleteSelection'), findsOneWidget);
    final delete = tester.getRect(_key('deleteSelection'));
    expect(
      delete.left,
      greaterThan(tester.getRect(_key('galetLeftRail')).right),
    );
    expect(delete.right, lessThan(tester.getRect(_key('galetRightRail')).left));
    expect(delete.bottom, lessThanOrEqualTo(360));
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
        final screen = Rect.fromLTRB(
          insets.left,
          insets.top,
          size.width - insets.right,
          size.height - insets.bottom,
        );
        void onScreen(String when) {
          for (final element in find.byType(GaletButton).evaluate()) {
            final box = element.renderObject! as RenderBox;
            final rect = box.localToGlobal(Offset.zero) & box.size;
            final label = (element.widget as GaletButton).label;
            expect(rect.left, greaterThanOrEqualTo(screen.left), reason: label);
            expect(rect.right, lessThanOrEqualTo(screen.right), reason: label);
            expect(rect.top, greaterThanOrEqualTo(screen.top), reason: label);
            expect(
              rect.bottom,
              lessThanOrEqualTo(screen.bottom),
              reason: '$label with $when',
            );
            expect(rect.width, greaterThanOrEqualTo(48), reason: label);
            expect(rect.height, greaterThanOrEqualTo(48), reason: label);
          }
        }

        for (final tool in options.tools) {
          await studio.tap(tool.keyName);
          expect(tester.takeException(), isNull, reason: tool.keyName);
          // The tool in hand is always on the rail, shown as chosen, and
          // every button of the two rails stays on the screen.
          expect(isChosen(tester, tool.group.keyName), isTrue);
          onScreen(tool.keyName);
        }
        // The ten colours are one press away, all in view.
        await tester.tap(_key('railColour'));
        await tester.pumpAndSettle();
        for (final colour in galetColours) {
          final swatch = tester.getRect(
            _key('color-${colour.rgb.toRadixString(16)}'),
          );
          expect(screen.contains(swatch.topLeft), isTrue, reason: colour.name);
          expect(
            screen.contains(swatch.bottomRight - const Offset(1, 1)),
            isTrue,
            reason: colour.name,
          );
        }
        expect(tester.takeException(), isNull);
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

  testWidgets('a tablet in a small window is not a telephone', (tester) async {
    final studio = StudioDriver(tester);
    // The window of a tablet, as small as a telephone's screen on its side.
    await studio.start(size: const Size(700, 500));
    // Laid out for the smallest window of a computer — eight cells in each
    // rail, where a telephone has five or six —, and scaled down.
    expect(_key('galetLeftRail'), findsOneWidget);
    expect(_key('tool-line'), findsOneWidget);
    expect(_scaled(_key('drawingSurface')), isTrue);
    await studio.finish();
  }, skip: !available);

  testWidgets('a telephone held upright keeps the whole studio, scaled down', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start(size: const Size(393, 852), phone: true);
    // Taller than wide: the two lines of a tablet held upright.
    expect(_key('phoneMenu'), findsNothing);
    expect(_key('galetLine'), findsOneWidget);
    expect(_key('galetColours'), findsOneWidget);
    expect(_scaled(_key('drawingSurface')), isTrue);
    await studio.drag(const Offset(-30, -15), const Offset(20, 15));
    studio.expectCount(1);
    await studio.finish();
  }, skip: !available);
}
