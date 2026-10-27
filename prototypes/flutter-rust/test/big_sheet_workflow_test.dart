// SPDX-License-Identifier: MIT
// Real Rust documents; only dialogs' destinations and storage are in memory.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  final surface = find.byKey(const Key('drawingSurface'));

  bool big(WidgetTester tester) =>
      tester.widget<IconButton>(find.byKey(const Key('bigSheet'))).isSelected!;

  for (final size in const [Size(1280, 820), Size(1100, 760), Size(700, 620)]) {
    testWidgets(
      'Dessiner en grand puts the panels away and gives their room to the sheet at $size',
      (tester) async {
        final studio = StudioDriver(tester);
        await studio.start(size: size);
        await studio.tap('tool-stamp');
        await studio.click();
        final before = tester.getSize(surface);
        final svg = await studio.svg();
        expect(big(tester), isFalse);

        await studio.tap('bigSheet');
        expect(big(tester), isTrue);
        // The top bar, the side panel, the mascot's advice and the status go.
        expect(find.byKey(const Key('saveProject')), findsNothing);
        expect(find.byKey(const Key('showHelp')), findsNothing);
        expect(find.text('UNE PETITE IDÉE'), findsNothing);
        expect(find.textContaining('Choisis un tampon, puis'), findsNothing);
        // The tools, the colours, the layers and Annuler stay at hand.
        for (final key in [
          'tool-stroke',
          'tool-select',
          'color-477fb2',
          'pickPaintColor',
          'layersButton',
          'undo',
          'chooseStamp',
        ]) {
          expect(find.byKey(Key(key)), findsOneWidget, reason: key);
        }
        final after = tester.getSize(surface);
        expect(after.height, greaterThan(before.height + 100));
        expect(after.width, greaterThanOrEqualTo(before.width));
        expect(tester.takeException(), isNull);

        // Drawing goes on: positions follow the larger sheet.
        await studio.click(studio.at(200, 200));
        studio.expectCount(2);
        // The keyboard still saves: the window has no button for it now.
        studio.menu.onSave!();
        await tester.pumpAndSettle();
        expect(studio.files.projects, hasLength(1));
        expect(studio.isDirty, isFalse);

        await studio.tap('bigSheet');
        expect(big(tester), isFalse);
        expect(find.byKey(const Key('saveProject')), findsOneWidget);
        expect(tester.getSize(surface), before);
        // The drawing was never touched by the change of view.
        await studio.tap('undo');
        expect(await studio.svg(), svg);
        expect(tester.takeException(), isNull);
        await studio.finish();
      },
      skip: !available,
    );
  }

  testWidgets(
    'Échap leaves the big sheet only when nothing else is to be stopped',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stamp');
      await studio.click();
      await studio.tap('bigSheet');
      await studio.tap('tool-select');
      await studio.click();
      // In the big sheet the chosen element keeps its actions.
      expect(find.byKey(const Key('growSelection')), findsOneWidget);
      expect(find.byKey(const Key('deleteSelection')), findsOneWidget);

      // First Échap: the element is no longer chosen. The sheet stays big.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(big(tester), isTrue);
      expect(find.text('Clique un élément pour le choisir.'), findsOneWidget);

      // A gesture in progress is stopped first, too.
      await studio.tap('tool-stroke');
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(200, 600),
      );
      await gesture.moveTo(studio.sheetCenter + studio.at(300, 650));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(big(tester), isTrue);
      studio.expectCount(1);

      // Nothing left to stop: Échap brings the panels back.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(big(tester), isFalse);
      expect(find.byKey(const Key('saveProject')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the big sheet works in the smallest window with enlarged text', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start(size: const Size(680, 520), textScale: 2);
    final before = tester.getSize(surface);
    await studio.tap('bigSheet');
    expect(tester.takeException(), isNull);
    expect(tester.getSize(surface).height, greaterThan(before.height));
    await studio.tap('tool-rectangle');
    await studio.drag(studio.at(300, 200), studio.at(700, 500));
    studio.expectCount(1);
    await studio.tap('tool-select');
    await studio.click(studio.at(300, 350));
    for (final key in ['growSelection', 'deleteSelection', 'bigSheet']) {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(Key(key)));
      expect(rect.height, greaterThanOrEqualTo(40), reason: key);
      expect(rect.bottom, lessThanOrEqualTo(520), reason: key);
    }
    await studio.tap('bigSheet');
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);
}
