import 'package:edupaint_flutter_study/new_sheet_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'new sheet choices fit 680x520 at text $scale and expose radio semantics',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(680, 520);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          NewSheetShape? result;
          var closed = false;
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    key: const Key('open'),
                    onPressed: () async {
                      result = await showDialog<NewSheetShape>(
                        context: context,
                        builder: (_) => const NewSheetDialog(),
                      );
                      closed = true;
                    },
                    child: const Text('Ouvrir'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byKey(const Key('open')));
          await tester.pumpAndSettle();
          expect(find.text('Choisis la forme de ta feuille'), findsOneWidget);
          expect(find.textContaining('1200'), findsNothing);
          Finder? previous;
          for (final shape in NewSheetShape.values) {
            final choice = find.byKey(Key('newSheet-${shape.name}'));
            await tester.ensureVisible(choice);
            await tester.pumpAndSettle();
            final rect = tester.getRect(choice);
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.width, greaterThanOrEqualTo(48));
            if (previous != null) {
              expect(
                rect.top - tester.getRect(previous).bottom,
                greaterThanOrEqualTo(8),
              );
            }
            previous = choice;
            expect(
              tester.getSemantics(choice),
              isSemantics(
                label: shape.label,
                hasCheckedState: true,
                isChecked: shape == NewSheetShape.landscape,
                isInMutuallyExclusiveGroup: true,
                hasEnabledState: true,
                isEnabled: true,
                hasTapAction: true,
              ),
            );
            final preview = tester.getSize(
              find.byKey(Key('newSheetPreview-${shape.name}')),
            );
            expect(
              preview.width / preview.height,
              closeTo(shape.width / shape.height, .001),
            );
          }
          final landscape = find.byKey(const Key('newSheet-landscape'));
          final portrait = find.byKey(const Key('newSheet-portrait'));
          await tester.ensureVisible(landscape);
          await tester.pumpAndSettle();
          final first = tester.getRect(landscape);
          final second = tester.getRect(portrait);
          await tester.tapAt(
            Offset(first.center.dx, (first.bottom + second.top) / 2),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<RadioGroup<NewSheetShape>>(
                  find.byType(RadioGroup<NewSheetShape>),
                )
                .groupValue,
            NewSheetShape.landscape,
          );
          // The entire tile is active, including its top and bottom edges.
          await tester.tapAt(tester.getTopLeft(portrait) + const Offset(20, 1));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<RadioGroup<NewSheetShape>>(
                  find.byType(RadioGroup<NewSheetShape>),
                )
                .groupValue,
            NewSheetShape.portrait,
          );
          final square = find.byKey(const Key('newSheet-square'));
          await tester.ensureVisible(square);
          await tester.pumpAndSettle();
          final squareRect = tester.getRect(square);
          await tester.tapAt(
            Offset(squareRect.center.dx, squareRect.bottom - 1),
          );
          await tester.pumpAndSettle();
          expect(closed, isFalse);
          for (final key in ['cancelNewSheet', 'createNewSheet']) {
            final rect = tester.getRect(find.byKey(Key(key)));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.bottom, lessThanOrEqualTo(520));
          }
          final cancel = tester.getRect(
            find.byKey(const Key('cancelNewSheet')),
          );
          final create = tester.getRect(
            find.byKey(const Key('createNewSheet')),
          );
          expect(create.left - cancel.right, greaterThanOrEqualTo(8));
          await tester.tap(find.byKey(const Key('createNewSheet')));
          await tester.pumpAndSettle();
          expect(result, NewSheetShape.square);
          expect(closed, isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
      variant: TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }),
    );
  }

  testWidgets(
    'keyboard changes choice, tabs to create and Escape cancels; next opening resets',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(680, 520);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final results = <NewSheetShape?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open'),
                onPressed: () async => results.add(
                  await showDialog<NewSheetShape>(
                    context: context,
                    builder: (_) => const NewSheetDialog(),
                  ),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<NewSheetShape>>(
              find.byType(RadioGroup<NewSheetShape>),
            )
            .groupValue,
        NewSheetShape.portrait,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final radio = find.descendant(
        of: find.byKey(const Key('newSheet-square')),
        matching: find.byType(Radio<NewSheetShape>),
      );
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final focused = tester.getRect(radio);
      expect(focused.top, greaterThanOrEqualTo(viewport.top));
      expect(focused.bottom, lessThanOrEqualTo(viewport.bottom));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(results, [NewSheetShape.portrait]);
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<NewSheetShape>>(
              find.byType(RadioGroup<NewSheetShape>),
            )
            .groupValue,
        NewSheetShape.landscape,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(results, [NewSheetShape.portrait, null]);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );
}
