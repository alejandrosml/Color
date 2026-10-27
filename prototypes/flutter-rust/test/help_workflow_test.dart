// SPDX-License-Identifier: MIT
// Real Rust documents; only dialogs' destinations and storage are in memory.
import 'dart:io';

import 'package:edupaint_flutter_study/help_dialog.dart';
import 'package:edupaint_flutter_study/studio_tool.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_printer.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  StudioTool selectedTool(WidgetTester tester) {
    for (final tool in StudioTool.values) {
      final selected = tester
          .getSemantics(find.byKey(Key(tool.keyName)))
          .flagsCollection
          .isSelected
          .toBoolOrNull();
      if (selected ?? false) return tool;
    }
    fail('No tool is announced as selected.');
  }

  testWidgets('every tool has a key, a name and a sentence of its own', (
    tester,
  ) async {
    expect(StudioTool.values, hasLength(9));
    expect(StudioTool.values.map((tool) => tool.keyName).toSet(), hasLength(9));
    expect(StudioTool.values.map((tool) => tool.label).toSet(), hasLength(9));
    expect(StudioTool.values.map((tool) => tool.help).toSet(), hasLength(9));
    for (final tool in StudioTool.values) {
      expect(tool.help.length, greaterThan(30), reason: tool.name);
      expect(tool.help, endsWith(tool.help.endsWith('!') ? '!' : '.'));
    }
    // Buttons created before the tools had a type keep their keys.
    expect(StudioTool.brush.keyName, 'tool-stroke');
    expect(StudioTool.select.keyName, 'tool-select');
    expect(StudioTool.eraser.keyName, 'tool-eraser');
    expect(StudioTool.fill.keyName, 'tool-fill');
  });

  testWidgets(
    'Comment faire ? explains every tool, closes by Entrée or Échap and changes nothing',
    (tester) async {
      final printer = FakePrinter();
      final studio = StudioDriver(tester, printer: printer.call);
      await studio.start();
      await studio.tap('tool-stamp');
      await studio.click();
      await studio.tap('saveProject');
      final before = await studio.svg();

      await studio.tap('showHelp');
      expect(find.byKey(const Key('helpDialog')), findsOneWidget);
      expect(find.text('Comment faire ?'), findsOneWidget);
      for (final tool in StudioTool.values) {
        final row = find.byKey(Key('help-${tool.name}'), skipOffstage: false);
        expect(row, findsOneWidget, reason: tool.name);
        expect(
          find.descendant(
            of: row,
            matching: find.text(tool.help, skipOffstage: false),
          ),
          findsOneWidget,
          reason: tool.name,
        );
      }
      for (final key in [
        'help-picker',
        'help-layers',
        'help-big-sheet',
        'help-print',
      ]) {
        expect(find.byKey(Key(key), skipOffstage: false), findsOneWidget);
      }
      // Printing is explained with its picture, and with its keys.
      expect(
        find.descendant(
          of: find.byKey(const Key('help-print'), skipOffstage: false),
          matching: find.textContaining(
            'Rien ne s’imprime avant que tu le confirmes',
            skipOffstage: false,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text('${HelpDialog.commandKey} + P', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.text('Imprimer ton dessin.', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Avec le clavier', skipOffstage: false), findsOneWidget);
      // While it is open, menu commands neither stack a dialog nor write.
      final menu = studio.menu;
      menu.onNew!();
      menu.onOpen!();
      menu.onSave!();
      menu.onAbout!();
      menu.onLayers!();
      menu.onHelp!();
      menu.onPrint!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      expect(studio.files.saveDialogCount, 1);
      expect(printer.requests, isEmpty);

      // The way back is focused: Entrée closes the help.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('helpDialog')), findsNothing);

      // F1 opens it from the keyboard, Échap closes it.
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('helpDialog')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('helpDialog')), findsNothing);

      // The menu of the Mac opens the same help.
      studio.menu.onHelp!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('helpDialog')), findsOneWidget);
      await studio.tap('closeHelp');

      studio.expectCount(1);
      expect(studio.isDirty, isFalse);
      expect(await studio.svg(), before);
      // The tool chosen before is still the tool.
      expect(selectedTool(tester), StudioTool.stamp);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the keys named in the help are those of this computer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HelpDialog())),
    );
    final command = defaultTargetPlatform == TargetPlatform.macOS
        ? '⌘'
        : 'Ctrl';
    expect(HelpDialog.commandKey, command);
    expect(find.text('$command + Z', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Maj + $command + Z', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('1 à 9', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets(
    'the help scrolls in a small window with enlarged text and stays closable',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(680, 480), textScale: 2);
      // In a narrow window the help is in the « … » menu of the top bar.
      await tester.tap(find.byKey(const Key('moreFileActions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('showHelp')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('helpDialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The last line is reached by scrolling, the way back stays in view.
      final last = find.text(
        'Arrêter le geste en cours, sans rien changer.',
        skipOffstage: false,
      );
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(480));
      final close = tester.getRect(find.byKey(const Key('closeHelp')));
      expect(close.bottom, lessThanOrEqualTo(480));
      expect(close.height, greaterThanOrEqualTo(48));
      await studio.tap('closeHelp');
      expect(find.byKey(const Key('helpDialog')), findsNothing);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the number keys choose the tools in their order, alone and on the page only',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      expect(selectedTool(tester), StudioTool.brush);
      const digits = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ];
      for (var number = 8; number >= 0; number--) {
        await tester.sendKeyEvent(digits[number]);
        await tester.pumpAndSettle();
        expect(selectedTool(tester), StudioTool.values[number]);
      }
      // The numeric keypad too.
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad7);
      await tester.pumpAndSettle();
      expect(selectedTool(tester), StudioTool.fill);
      // Zero and a number held with Ctrl are not tool keys.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(selectedTool(tester), StudioTool.fill);

      // A digit typed into a text is a character, not a command.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pumpAndSettle();
      expect(selectedTool(tester), StudioTool.text);
      await studio.click();
      expect(find.byKey(const Key('textDialog')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      await studio.write('1 2 3');
      await studio.tap('confirmText');
      expect(selectedTool(tester), StudioTool.text);
      studio.expectCount(1);

      // While a gesture is in progress the tool does not change under it.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(200, 600),
      );
      await gesture.moveTo(studio.sheetCenter + studio.at(300, 650));
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selectedTool(tester), StudioTool.brush);
      studio.expectCount(2);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );
}
