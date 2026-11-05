// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:edupaint_flutter_study/adult_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/interface_font.dart';
import 'support/studio_driver.dart';

void main() {
  // The door over an empty page; what it answers is kept in [answers].
  Future<List<AdultGate>> open(
    WidgetTester tester, {
    math.Random? random,
  }) async {
    final answers = <AdultGate>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              key: const Key('ask'),
              onPressed: () async =>
                  answers.add(await showAdultGate(context, random: random)),
              child: const Text('Options'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('ask')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adultGate')), findsOneWidget);
    return answers;
  }

  Finder typed(String text) => find.descendant(
    of: find.byKey(const Key('adultGateAnswer')),
    matching: find.text(text),
  );

  test('the multiplication is one of the tables from 6 to 9', () {
    final random = math.Random(7);
    final seen = <String>{};
    final results = <int>{};
    AdultGateQuestion? previous;
    for (var turn = 0; turn < 500; turn++) {
      final question = AdultGateQuestion.draw(random, previous: previous);
      expect(question.first, inInclusiveRange(6, 9));
      expect(question.second, inInclusiveRange(6, 9));
      expect(question.answer, question.first * question.second);
      expect(question.answer, inInclusiveRange(36, 81));
      expect(question.text, '${question.first} × ${question.second} = ?');
      expect(
        question.spoken,
        'Combien font ${question.first} fois ${question.second} ?',
      );
      if (previous != null) {
        // Never the result that was just asked, even turned round.
        expect(question.answer, isNot(previous.answer));
      }
      seen.add(question.text);
      results.add(question.answer);
      previous = question;
    }
    expect(seen, hasLength(16));
    // Ten results, none much likelier than the others to a guess.
    expect(results, {36, 42, 48, 54, 49, 56, 63, 64, 72, 81});
  });

  testWidgets('the right result opens the door at its second digit', (
    tester,
  ) async {
    final answers = await open(tester, random: math.Random(1));
    final (first, second) = adultGateNumbers(tester);
    final answer = '${first * second}';
    // One digit: nothing answered yet, and no key to confirm.
    await tester.tap(find.byKey(Key('adultGateDigit${answer[0]}')));
    await tester.pumpAndSettle();
    expect(typed(answer[0]), findsOneWidget);
    expect(find.byKey(const Key('adultGateEnter')), findsNothing);
    expect(answers, isEmpty);
    // The second one answers: the door is gone at once.
    await tester.tap(find.byKey(Key('adultGateDigit${answer[1]}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adultGate')), findsNothing);
    expect(answers, [AdultGate.opened]);
  });

  testWidgets('a wrong result brings another calculation, twice', (
    tester,
  ) async {
    final answers = await open(tester, random: math.Random(2));
    for (var attempt = 1; attempt < AdultGateDialog.tries; attempt++) {
      final numbers = adultGateNumbers(tester);
      await typeAtAdultGate(tester, wrongAdultGateAnswer(tester));
      expect(find.byKey(const Key('adultGate')), findsOneWidget);
      expect(find.byKey(const Key('adultGateWrong')), findsOneWidget);
      final (first, second) = adultGateNumbers(tester);
      expect(first * second, isNot(numbers.$1 * numbers.$2));
      // The answer starts again from nothing.
      expect(typed('…'), findsOneWidget);
    }
    // The last try is announced.
    expect(find.textContaining('Dernier essai'), findsOneWidget);
    expect(answers, isEmpty);
    await answerAdultGate(tester);
    expect(answers, [AdultGate.opened]);
  });

  testWidgets('the third wrong result closes the door by itself', (
    tester,
  ) async {
    final answers = await open(tester, random: math.Random(6));
    for (var attempt = 0; attempt < AdultGateDialog.tries; attempt++) {
      expect(find.byKey(const Key('adultGate')), findsOneWidget);
      await typeAtAdultGate(tester, wrongAdultGateAnswer(tester));
    }
    expect(find.byKey(const Key('adultGate')), findsNothing);
    expect(answers, [AdultGate.closedAfterWrongAnswers]);
  });

  testWidgets('giving up closes the door; a click beside it does not', (
    tester,
  ) async {
    var answers = await open(tester);
    await tester.tap(find.byKey(const Key('adultGateCancel')));
    await tester.pumpAndSettle();
    expect(answers, [AdultGate.givenUp]);
    answers = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(answers, [AdultGate.givenUp]);
    answers = await open(tester);
    // A click beside the dialog — the second one of a double click on the
    // button that opened it — leaves it open.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adultGate')), findsOneWidget);
    expect(answers, isEmpty);
    await tester.tap(find.byKey(const Key('adultGateCancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('a first digit can be erased before it answers', (tester) async {
    final answers = await open(tester, random: math.Random(3));
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('adultGateErase')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('adultGateDigit1')));
    await tester.pump();
    expect(typed('1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('adultGateErase')));
    await tester.pump();
    expect(typed('…'), findsOneWidget);
    // Nothing was answered: no wrong result counted.
    expect(find.byKey(const Key('adultGateWrong')), findsNothing);
    await answerAdultGate(tester);
    expect(answers, [AdultGate.opened]);
  });

  testWidgets('a keyboard answers as well as the keys on the screen', (
    tester,
  ) async {
    final answers = await open(tester, random: math.Random(4));
    final (first, second) = adultGateNumbers(tester);
    final answer = '${first * second}';
    // A slip, taken back with the erase key of the keyboard.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9, character: '9');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    for (final digit in answer.split('')) {
      await tester.sendKeyEvent(
        LogicalKeyboardKey(0x30 + int.parse(digit)),
        character: digit,
      );
    }
    await tester.pumpAndSettle();
    expect(answers, [AdultGate.opened]);
  });

  testWidgets('digits are heard wherever the focus is', (tester) async {
    final answers = await open(tester, random: math.Random(8));
    Future<void> type(int number) async {
      for (final digit in '$number'.split('')) {
        await tester.sendKeyEvent(
          LogicalKeyboardKey(0x30 + int.parse(digit)),
          character: digit,
        );
      }
      await tester.pumpAndSettle();
    }

    // The focus on « Annuler »: a digit typed is still a digit of the
    // answer, and a wrong one brings another calculation.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await type(wrongAdultGateAnswer(tester));
    expect(find.byKey(const Key('adultGateWrong')), findsOneWidget);
    expect(answers, isEmpty);
    // The focus came back to the dialog: the next digits answer the new
    // calculation — they do not cancel.
    final (first, second) = adultGateNumbers(tester);
    await type(first * second);
    expect(answers, [AdultGate.opened]);
  });

  testWidgets('a key held down types once', (tester) async {
    final answers = await open(tester, random: math.Random(9));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1, character: '1');
    for (var repeat = 0; repeat < 5; repeat++) {
      await tester.sendKeyRepeatEvent(
        LogicalKeyboardKey.digit1,
        character: '1',
      );
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    // One digit, not an answer: no wrong result, the door still there.
    expect(typed('1'), findsOneWidget);
    expect(find.byKey(const Key('adultGateWrong')), findsNothing);
    expect(answers, isEmpty);
    await tester.tap(find.byKey(const Key('adultGateCancel')));
    await tester.pumpAndSettle();
    expect(answers, [AdultGate.givenUp]);
  });

  testWidgets('every key is large, named and in view in windows of all sizes', (
    tester,
  ) async {
    await loadInterfaceFont(tester);
    final handle = tester.ensureSemantics();
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final size in const [
      Size(680, 520),
      Size(800, 600),
      Size(1000, 700),
      Size(1280, 800),
    ]) {
      for (final scale in const [1.0, 1.5, 2.0, 3.0]) {
        final where = '$size, text × $scale';
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await open(tester, random: math.Random(5));
        expect(tester.takeException(), isNull, reason: where);
        for (final key in [
          for (var digit = 0; digit <= 9; digit++) 'adultGateDigit$digit',
          'adultGateErase',
          'adultGateCancel',
        ]) {
          final box = tester.getSize(find.byKey(Key(key)));
          expect(box.width, greaterThanOrEqualTo(48), reason: '$key, $where');
          expect(box.height, greaterThanOrEqualTo(48), reason: '$key, $where');
        }
        // Every key is in view and answers a click where it is seen:
        // nothing to scroll, with letters of any size.
        for (var digit = 0; digit <= 9; digit++) {
          await tester.tap(find.byKey(Key('adultGateDigit$digit')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('adultGateErase')));
          await tester.pump();
        }
        // The lowest keys, the last row of the calculator, in view.
        for (final key in ['adultGateDigit0', 'adultGateErase']) {
          expect(
            tester.getRect(find.byKey(Key(key))).bottom,
            lessThanOrEqualTo(size.height),
            reason: '$key, $where',
          );
        }
        await tester.tap(find.byKey(const Key('adultGateCancel')));
        await tester.pumpAndSettle();
      }
    }
    tester.view.physicalSize = const Size(680, 520);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await open(tester, random: math.Random(5));
    final (first, second) = adultGateNumbers(tester);
    expect(
      find.bySemanticsLabel('Combien font $first fois $second ?'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Effacer le dernier chiffre'), findsOneWidget);
    expect(find.bySemanticsLabel('Aucun chiffre tapé'), findsOneWidget);
    await tester.tap(find.byKey(const Key('adultGateDigit1')));
    await tester.pump();
    expect(find.bySemanticsLabel('Réponse tapée : 1'), findsOneWidget);
    handle.dispose();
  });

  test('enlarged letters are bounded by the height of the window', () {
    expect(AdultGateDialog.textScaleLimit(const Size(680, 520)), 1);
    expect(AdultGateDialog.textScaleLimit(const Size(680, 300)), 1);
    expect(AdultGateDialog.textScaleLimit(const Size(3000, 3000)), 3);
    var before = 0.0;
    for (var height = 300.0; height <= 1200; height += 10) {
      final limit = AdultGateDialog.textScaleLimit(Size(900, height));
      expect(limit, greaterThanOrEqualTo(before));
      before = limit;
    }
  });
}
