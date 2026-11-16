// SPDX-License-Identifier: MIT
// Color — Alejandro San Martin Lamas — https://github.com/alejandrosml
//
// The Kids category: nothing in Color leads out of it. A text that can be
// selected brings, on an iPhone or an iPad, the menu of the system with
// « Rechercher sur le Web » (Safari, on a search of the word), « Chercher »
// and « Partager » ; on Android, « Partager ». Color only offers what
// stays in it: cut, copy, paste, select all (étape 7 of Color 1.2).
import 'package:edupaint_flutter_study/color_identity.dart';
import 'package:edupaint_flutter_study/size_choice.dart';
import 'package:edupaint_flutter_study/studio_questions.dart';
import 'package:edupaint_flutter_study/text_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _inside = {
  ContextMenuButtonType.cut,
  ContextMenuButtonType.copy,
  ContextMenuButtonType.paste,
  ContextMenuButtonType.selectAll,
  ContextMenuButtonType.delete,
};

/// What the menu of the selection of the one text on screen offers, once
/// all of it is selected: the kinds of its buttons, and their words.
Future<(Set<ContextMenuButtonType>, List<String>)> _menu(
  WidgetTester tester,
) async {
  final state = tester.state<EditableTextState>(find.byType(EditableText));
  state.userUpdateTextEditingValue(
    state.textEditingValue.copyWith(
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: state.textEditingValue.text.length,
      ),
    ),
    SelectionChangedCause.longPress,
  );
  await tester.pump();
  expect(state.showToolbar(), isTrue);
  await tester.pump(const Duration(milliseconds: 300));
  // What the system would offer for this selection, were it not chosen.
  final offered = {for (final item in state.contextMenuButtonItems) item.type};
  final words = <String>[];
  for (final element
      in find
          .descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is AdaptiveTextSelectionToolbar ||
                  widget.runtimeType.toString().contains(
                    'TextSelectionToolbar',
                  ),
            ),
            matching: find.byType(Text),
          )
          .evaluate()) {
    words.add((element.widget as Text).data ?? '');
  }
  return (offered, words);
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the text of a child offers nothing that leaves Color '
        '($platform)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TextEntryDialog(
                initialText: 'dinosaure',
                initialSize: ObjectSize.values.first,
              ),
            ),
          ),
        );
        await tester.pump();
        final (offered, words) = await _menu(tester);
        // The system would have offered a way out: the test means something.
        expect(offered.difference(_inside), isNotEmpty);
        expect(words, isNotEmpty, reason: 'the menu is shown');
        for (final word in words) {
          expect(
            word.toLowerCase(),
            isNot(anyOf(contains('web'), contains('share'), contains('look'))),
            reason: '$words',
          );
        }
        expect(words.map((word) => word.toLowerCase()), contains('copy'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('the address of the help offers nothing that leaves Color '
        '($platform)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPrivacyPolicy(context),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('ouvrir'));
        await tester.pumpAndSettle();
        expect(find.textContaining(colorSupportAddress), findsOneWidget);
        final (offered, words) = await _menu(tester);
        expect(offered.difference(_inside), isNotEmpty);
        for (final word in words) {
          expect(
            word.toLowerCase(),
            isNot(anyOf(contains('web'), contains('share'), contains('look'))),
            reason: '$words',
          );
        }
        expect(words.map((word) => word.toLowerCase()), contains('copy'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
