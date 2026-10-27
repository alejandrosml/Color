// SPDX-License-Identifier: MIT
// The keyboard to click of the text dialog. Real Rust documents in the
// workflow tests; only native panels, disk writes and recovery in memory.
import 'dart:io';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/screen_keyboard.dart';
import 'package:edupaint_flutter_study/size_choice.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/text_dialog.dart';
import 'package:edupaint_flutter_study/text_layout.dart'
    show colorTextFontFamily;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/font_coverage.dart';
import 'support/interface_font.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  Finder key(String name) => find.byKey(Key(name));

  // What the field and the keyboard said of their changes, in order.
  final heard = <String>[];
  setUp(heard.clear);

  // The keyboard under a field of its own.
  Future<TextEditingController> pump(
    WidgetTester tester, {
    String text = '',
    int limit = 280,
    bool focused = true,
  }) async {
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                key: const Key('field'),
                controller: controller,
                autofocus: focused,
                maxLines: 3,
                onChanged: (_) => heard.add('field'),
              ),
              ScreenKeyboard(
                controller: controller,
                limit: limit,
                onChanged: () => heard.add('keys'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> press(WidgetTester tester, List<String> keys) async {
    for (final name in keys) {
      await tester.tap(key('key-$name'));
      await tester.pump();
    }
  }

  testWidgets('letters, capitals, accents, signs, space and a new line', (
    tester,
  ) async {
    final controller = await pump(tester);
    // After the capitals key, the keys show capitals and are named by them.
    await tester.tap(key('key-capitals'));
    await tester.pump();
    expect(key('key-l'), findsNothing);
    await press(tester, ['L', 'e', 'a']);
    expect(controller.text, 'Lea');
    // The capital was for one letter only.
    expect(key('key-L'), findsNothing);
    await press(tester, ['erase', 'erase']);
    await tester.tap(key('keys-accents'));
    await tester.pump();
    await press(tester, ['é']);
    await tester.tap(key('keys-letters'));
    await tester.pump();
    await press(tester, ['a', 'space', 'a', 'space']);
    await tester.tap(key('keys-signs'));
    await tester.pump();
    await press(tester, ['7', 'space']);
    await tester.tap(key('keys-letters'));
    await tester.pump();
    await press(tester, ['a', 'n', 's', 'space']);
    await tester.tap(key('keys-signs'));
    await tester.pump();
    await press(tester, ['!', 'newline', '♥']);
    expect(controller.text, 'Léa a 7 ans !\n♥');
    expect(controller.selection.baseOffset, controller.text.length);
    // Capital accents exist too, and the letters of other languages.
    await tester.tap(key('keys-accents'));
    await tester.pump();
    await press(tester, ['capitals', 'É', 'œ', 'ñ']);
    expect(controller.text, endsWith('Éœñ'));
    await tester.tap(key('keys-signs'));
    await tester.pump();
    await press(tester, ['newline', '3', '×', '2', '=', '6', '€']);
    expect(controller.text, endsWith('\n3×2=6€'));
    // The field said every change itself, as for a key of the computer.
    expect(heard.toSet(), {'field'});
  });

  testWidgets('no key moves when the page changes', (tester) async {
    await pump(tester);
    final rows = <String, Rect>{};
    final keys = <String, Set<Key>>{};
    for (final page in ['letters', 'accents', 'signs']) {
      await tester.tap(key('keys-$page'));
      await tester.pump();
      rows[page] = tester.getRect(key('key-capitals'));
      expect(tester.getRect(key('keys-$page')), isNotNull);
      final buttons = find.descendant(
        of: key('screenKeyboard'),
        matching: find.byType(OutlinedButton),
      );
      // Three rows of ten characters and the row of seven other keys.
      expect(buttons, findsNWidgets(37), reason: page);
      keys[page] = {
        for (final button in buttons.evaluate()) button.widget.key!,
      };
      // No two keys of a page have the same name.
      expect(keys[page], hasLength(37), reason: page);
      for (final other in ['space', 'newline', 'erase']) {
        rows['$page-$other'] = tester.getRect(key('key-$other'));
      }
    }
    expect(rows['accents'], rows['letters']);
    expect(rows['signs'], rows['letters']);
    for (final other in ['space', 'newline', 'erase']) {
      expect(rows['accents-$other'], rows['letters-$other']);
      expect(rows['signs-$other'], rows['letters-$other']);
    }
  });

  testWidgets('the font of the sheet has the sign of every key', (
    tester,
  ) async {
    final font = FontCoverage(File('fonts/DejaVuSans.ttf').readAsBytesSync());
    // The reader itself: letters are there, Japanese is not.
    expect(font.missing('aZ9é€'), isEmpty);
    expect(font.missing('aあ\u{10FFFF}'), ['あ', '\u{10FFFF}']);
    await pump(tester);
    final signs = <String>{};
    for (final page in ['letters', 'accents', 'signs']) {
      for (final capitals in [false, true]) {
        await tester.tap(key('keys-$page'));
        await tester.pump();
        if (capitals) {
          await tester.tap(key('key-capitals'));
          await tester.pump();
        }
        final buttons = find.descendant(
          of: key('screenKeyboard'),
          matching: find.byType(OutlinedButton),
        );
        for (final button in buttons.evaluate()) {
          final name = (button.widget.key! as ValueKey<String>).value;
          if (!name.startsWith('key-')) continue;
          final sign = name.substring(4);
          if (sign.characters.length != 1) continue;
          signs.add(sign);
          // What the key shows is what it is named after, in that font.
          final label = tester.widget<Text>(
            find.descendant(of: key(name), matching: find.byType(Text)),
          );
          expect(label.data, sign);
          expect(label.style?.fontFamily, colorTextFontFamily);
        }
        if (capitals) {
          await tester.tap(key('key-capitals'));
          await tester.pump();
        }
      }
    }
    // Thirty keys on each page, the hyphen on two of them; twenty-six
    // letters and twenty-seven accented ones have a capital of their own.
    expect(signs, hasLength(90 - 1 + 26 + 27));
    expect(signs, containsAll(['a', 'A', 'é', 'É', 'œ', 'Œ', 'ñ', '♥', '€']));
    expect(font.missing(signs.join()), isEmpty);
  });

  testWidgets('keys also type in a field that does not hold the focus', (
    tester,
  ) async {
    final controller = await pump(tester, text: 'ab', focused: false);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isFalse);
    // Never clicked: the characters go to the end.
    await press(tester, ['c', 'erase', 'd']);
    expect(controller.text, 'abd');
    expect(controller.selection.baseOffset, 3);
    expect(heard, ['keys', 'keys', 'keys']);
    // The limit of the field is kept there too.
    final short = await pump(tester, text: 'abc', limit: 3, focused: false);
    heard.clear();
    await press(tester, ['d']);
    expect(short.text, 'abc');
    expect(heard, isEmpty);
  });

  testWidgets('keys type where the caret is, and erase whole characters', (
    tester,
  ) async {
    final controller = await pump(tester, text: 'chat');
    controller.selection = const TextSelection.collapsed(offset: 2);
    await press(tester, ['o']);
    expect(controller.text, 'choat');
    expect(controller.selection.baseOffset, 3);
    await press(tester, ['erase']);
    expect(controller.text, 'chat');
    expect(controller.selection.baseOffset, 2);
    // A selection is replaced by the key, or removed by Effacer.
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    await press(tester, ['r']);
    expect(controller.text, 'crt');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    await press(tester, ['erase']);
    expect(controller.text, 't');
    expect(controller.selection.baseOffset, 0);
    // Nothing before the caret: nothing to erase.
    await press(tester, ['erase']);
    expect(controller.text, 't');
    // A character made of two code units goes in one press.
    controller.value = const TextEditingValue(
      text: 'a😀',
      selection: TextSelection.collapsed(offset: 3),
    );
    await press(tester, ['erase']);
    expect(controller.text, 'a');
  });

  testWidgets('the field keeps its limit, its focus and its caret', (
    tester,
  ) async {
    final controller = await pump(tester, text: 'abc', limit: 4);
    controller.selection = const TextSelection.collapsed(offset: 3);
    await press(tester, ['d', 'e', 'f']);
    expect(controller.text, 'abcd');
    final field = tester.widget<TextField>(key('field'));
    expect(field.controller, controller);
    // Pressed with a mouse, as on a desktop: the field is still the one
    // that has the focus, and no key took it.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(key('key-erase')));
    addTearDown(mouse.removePointer);
    await mouse.down(tester.getCenter(key('key-erase')));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(controller.text, 'abc');
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasPrimaryFocus, isTrue);
  });

  testWidgets(
    'the caret stays in view when the text is longer than the field',
    (tester) async {
      final controller = await pump(tester);
      // The field shows three lines.
      for (var line = 0; line < 8; line++) {
        await press(tester, ['a', 'newline']);
      }
      await press(tester, ['z']);
      await tester.pumpAndSettle();
      expect(controller.text, '${'a\n' * 8}z');
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final field = editable.renderEditable;
      final caret = field.getLocalRectForCaret(
        TextPosition(offset: controller.text.length),
      );
      expect(caret.top, greaterThanOrEqualTo(0));
      expect(caret.bottom, lessThanOrEqualTo(field.size.height + 0.5));
      final scrolled = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(EditableText),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrolled.position.pixels, greaterThan(0));
    },
  );

  testWidgets('every key is large and named', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    for (final page in ['letters', 'accents', 'signs']) {
      await tester.tap(key('keys-$page'));
      await tester.pump();
      for (final element
          in find
              .descendant(
                of: key('screenKeyboard'),
                matching: find.byType(OutlinedButton),
              )
              .evaluate()) {
        final size = element.size!;
        expect(size.width, greaterThanOrEqualTo(48), reason: page);
        expect(size.height, greaterThanOrEqualTo(48), reason: page);
      }
    }
    await tester.tap(key('keys-signs'));
    await tester.pump();
    for (final name in ['Espace', 'Effacer', 'À la ligne', 'cœur', 'étoile']) {
      expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
    }
    expect(find.bySemanticsLabel('Les lettres accentuées'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Majuscule pour la prochaine lettre'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets(
    'with the option the text dialog has its keys, and a text is written with a pointer only',
    (tester) async {
      final store = StudioOptionsStore.memory(
        const StudioOptions(screenKeyboard: true),
      );
      addTearDown(store.dispose);
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: const Size(1280, 800));
      await studio.tap('tool-text');
      await studio.click(studio.at(300, 300));
      expect(key('textDialog'), findsOneWidget);
      expect(key('screenKeyboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Nothing to confirm yet.
      expect(tester.widget<FilledButton>(key('confirmText')).onPressed, isNull);
      await press(tester, ['capitals', 'B', 'r', 'a', 'v', 'o']);
      expect(
        tester.widget<FilledButton>(key('confirmText')).onPressed,
        isNotNull,
      );
      await studio.tap('confirmText');
      expect(key('textDialog'), findsNothing);
      final document = await studio.saved();
      addTearDown(document.dispose);
      expect(document.strokes.single.kind, VectorKind.text);
      expect(document.strokes.single.text, 'Bravo');

      // The same keys change an existing text.
      await studio.tap('tool-select');
      await studio.click(studio.at(310, 310));
      await studio.tap('editSelectionText');
      expect(key('screenKeyboard'), findsOneWidget);
      await tester.tap(key('keys-signs'));
      await tester.pump();
      await press(tester, ['!']);
      await studio.tap('confirmText');
      final changed = await studio.saved();
      addTearDown(changed.dispose);
      expect(changed.strokes.single.text, 'Bravo!');
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the dialog with its keys fits small windows and large letters', (
    tester,
  ) async {
    // Real letters, wider than those of the Mac and of Windows: the widths
    // of the test font would say nothing of what fits.
    await loadInterfaceFont(tester);
    for (final size in const [
      Size(680, 520),
      Size(800, 600),
      Size(1000, 700),
      Size(1280, 800),
    ]) {
      for (final textScale in const [1.0, 1.5, 2.0]) {
        final store = StudioOptionsStore.memory(
          const StudioOptions(screenKeyboard: true),
        );
        final studio = StudioDriver(tester, options: store);
        await studio.start(size: size, textScale: textScale);
        await studio.tap('tool-text');
        await studio.click();
        final where = '$size, text × $textScale';
        expect(key('screenKeyboard'), findsOneWidget, reason: where);
        expect(tester.takeException(), isNull, reason: where);
        // The row of ten keys is whole inside the window.
        expect(tester.getRect(key('key-a')).left, greaterThanOrEqualTo(0));
        expect(
          tester.getRect(key('key-p')).right,
          lessThanOrEqualTo(size.width),
          reason: where,
        );
        {
          // Nothing to scroll for, with letters of any size: the field,
          // every key, the sizes and the two buttons are in view, and each
          // of them can be clicked.
          final window = Offset.zero & size;
          for (final name in [
            'textField',
            'key-a',
            'key-capitals',
            'key-erase',
            'textDialogSize-small',
            'textDialogSize-large',
            'cancelText',
            'confirmText',
          ]) {
            final rect = tester.getRect(key(name));
            expect(
              window.contains(rect.topLeft) &&
                  window.contains(rect.bottomRight - const Offset(1, 1)),
              isTrue,
              reason: '$name at $rect, $where',
            );
            expect(
              key(name).hitTestable(),
              findsOneWidget,
              reason: '$name, $where',
            );
          }
        }
        await studio.tap('cancelText');
        await studio.finish();
        store.dispose();
      }
    }
  }, skip: !available);

  testWidgets('no key slides from under the pointer while lines are added', (
    tester,
  ) async {
    await loadInterfaceFont(tester);
    for (final size in const [Size(680, 520), Size(1280, 800)]) {
      final store = StudioOptionsStore.memory(
        const StudioOptions(screenKeyboard: true),
      );
      final studio = StudioDriver(tester, options: store);
      await studio.start(size: size);
      await studio.tap('tool-text');
      await studio.click();
      final places = {
        for (final name in ['key-a', 'key-newline', 'key-erase', 'confirmText'])
          name: tester.getRect(key(name)),
      };
      // Six lines, written by clicking one and the same place twice a line.
      final newline = tester.getCenter(key('key-newline'));
      final letter = tester.getCenter(key('key-a'));
      for (var line = 0; line < 6; line++) {
        await tester.tapAt(letter);
        await tester.pump();
        await tester.tapAt(newline);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(key('textField')).controller!.text,
        'a\n' * 6,
        reason: '$size',
      );
      for (final entry in places.entries) {
        expect(tester.getRect(key(entry.key)), entry.value, reason: '$size');
      }
      await studio.tap('cancelText');
      await studio.finish();
      store.dispose();
    }
  }, skip: !available);

  test('enlarged letters are bounded by the height of the window', () {
    expect(TextEntryDialog.keysTextScaleLimit(const Size(680, 520)), 1);
    expect(TextEntryDialog.keysTextScaleLimit(const Size(680, 400)), 1);
    expect(TextEntryDialog.keysTextScaleLimit(const Size(800, 600)), 1.25);
    expect(
      TextEntryDialog.keysTextScaleLimit(const Size(1280, 800)),
      greaterThanOrEqualTo(2),
    );
    expect(TextEntryDialog.keysTextScaleLimit(const Size(3000, 3000)), 3);
    // Never smaller in a taller window.
    var before = 0.0;
    for (var height = 300.0; height <= 1200; height += 10) {
      final limit = TextEntryDialog.keysTextScaleLimit(Size(900, height));
      expect(limit, greaterThanOrEqualTo(before));
      before = limit;
    }
  });

  testWidgets('changing a text fits the smallest window too', (tester) async {
    await loadInterfaceFont(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(680, 520);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TextEntryDialog(
            initialText: 'Bonjour',
            initialSize: ObjectSize.medium,
            editing: true,
            screenKeyboard: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Changer le texte'), findsOneWidget);
    for (final name in [
      'textField',
      'key-a',
      'key-capitals',
      'key-erase',
      'textDialogSize-small',
      'textDialogSize-large',
      'cancelText',
      'confirmText',
    ]) {
      final rect = tester.getRect(key(name));
      expect(rect.top, greaterThanOrEqualTo(0), reason: name);
      expect(rect.bottom, lessThanOrEqualTo(520), reason: name);
      expect(key(name).hitTestable(), findsOneWidget, reason: name);
    }
    // The sizes and the two buttons share one row.
    expect(
      tester.getRect(key('textDialogSize-small')).center.dy,
      tester.getRect(key('confirmText')).center.dy,
    );
  });

  testWidgets('without the option the text dialog is as it was', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-text');
    await studio.click();
    expect(key('textDialog'), findsOneWidget);
    expect(key('screenKeyboard'), findsNothing);
    await studio.tap('cancelText');
    await studio.finish();
  }, skip: !available);
}
