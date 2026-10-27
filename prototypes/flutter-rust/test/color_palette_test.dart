// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:edupaint_flutter_study/color_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  test(
    'recent choices are bounded, unique and reordered without mutable leakage',
    () {
      final history = RecentPaintColors();
      addTearDown(history.dispose);
      for (var value = 0; value < 12; value++) {
        history.remember(value);
      }
      expect(history.colors, [11, 10, 9, 8, 7, 6, 5, 4]);
      final detached = history.colors;
      history.remember(7);
      expect(history.colors, [7, 11, 10, 9, 8, 6, 5, 4]);
      expect(detached.first, 11);
      expect(() => history.colors.add(1), throwsUnsupportedError);
      expect(() => history.remember(0x1000000), throwsRangeError);
      expect(() => history.remember(-1), throwsRangeError);
      expect(() => RecentPaintColors(capacity: 0), throwsRangeError);
    },
  );

  testWidgets(
    'named colors, target and recent swatches route choices to the parent',
    (tester) async {
      final history = RecentPaintColors();
      addTearDown(history.dispose);
      var rgb = 0x477fb2;
      var target = PaintColorTarget.stroke;
      final selected = <(PaintColorTarget, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Padding(
                padding: const EdgeInsets.all(16),
                child: ColorPalette(
                  selectedRgb: rgb,
                  target: target,
                  canFill: true,
                  history: history,
                  onTargetChanged: (value) => update(() => target = value),
                  onColorSelected: (value) {
                    selected.add((target, value));
                    update(() => rgb = value);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final semantics = tester.ensureSemantics();
      try {
        for (final swatch in paintColors) {
          expect(find.byTooltip(swatch.name), findsOneWidget);
          expect(
            tester
                .getSemantics(
                  find.descendant(
                    of: find.byKey(
                      Key('color-${swatch.rgb.toRadixString(16)}'),
                    ),
                    matching: find.byType(IconButton),
                  ),
                )
                .getSemanticsData()
                .label,
            swatch.name,
          );
        }
        expect(paintColors, hasLength(10));
        await tap(tester, 'paint-target-fill');
        await tap(tester, 'color-d75e56');
        expect(selected.last, (PaintColorTarget.fill, 0xd75e56));
        await tap(tester, 'paint-target-stroke');
        await tap(tester, 'color-78a66f');
        await tap(tester, 'recent-paint-color-d75e56');
        expect(selected.last, (PaintColorTarget.stroke, 0xd75e56));
        expect(history.colors, [0xd75e56, 0x78a66f]);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'cancelled custom choices never change selection or session history',
    (tester) async {
      final history = RecentPaintColors();
      addTearDown(history.dispose);
      final selected = <int>[];
      final dialogStates = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColorPalette(
              selectedRgb: 0x123456,
              history: history,
              onColorSelected: selected.add,
              onDialogVisibilityChanged: dialogStates.add,
            ),
          ),
        ),
      );
      await tap(tester, 'morePaintColors');
      expect(find.byKey(const Key('paintColorDialog')), findsOneWidget);
      await tap(tester, 'shade-ef9439');
      await tap(tester, 'cancelPaintColor');
      expect(selected, isEmpty);
      expect(history.colors, isEmpty);
      expect(dialogStates, [true, false]);
      await tap(tester, 'morePaintColors');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      expect(history.colors, isEmpty);
      expect(dialogStates, [true, false, true, false]);
    },
  );

  testWidgets('a shade is returned exactly once after explicit confirmation', (
    tester,
  ) async {
    final history = RecentPaintColors();
    addTearDown(history.dispose);
    final selected = <int>[];
    final dialogStates = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPalette(
            selectedRgb: 0x123456,
            history: history,
            onColorSelected: selected.add,
            onDialogVisibilityChanged: dialogStates.add,
          ),
        ),
      ),
    );
    final callback = tester
        .widget<OutlinedButton>(find.byKey(const Key('morePaintColors')))
        .onPressed!;
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tap(tester, 'shade-a8d8f0');
    expect(selected, isEmpty);
    await tap(tester, 'confirmPaintColor');
    expect(selected, [0xa8d8f0]);
    expect(history.colors, [0xa8d8f0]);
    expect(dialogStates, [true, false]);
  });

  testWidgets(
    'custom color sliders expose focus and keyboard adjustment without committing',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        int? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ColorPalette(
                selectedRgb: 0xd75e56,
                onColorSelected: (rgb) => selected = rgb,
              ),
            ),
          ),
        );
        await tap(tester, 'morePaintColors');
        final axis = find.byKey(const ValueKey('paintAxis-Clarté'));
        await tester.ensureVisible(axis);
        await tester.pumpAndSettle();
        var node = tester.getSemantics(axis);
        final before = node.getSemanticsData();
        expect(before.flagsCollection.isSlider, isTrue);
        expect(before.label, 'Clarté');
        expect(before.hasAction(SemanticsAction.decrease), isTrue);
        node.owner!.performAction(node.id, SemanticsAction.focus);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        node = tester.getSemantics(axis);
        expect(node.getSemanticsData().value, isNot(before.value));
        expect(
          node.getSemanticsData().flagsCollection.isFocused,
          Tristate.isTrue,
        );
        expect(selected, isNull);
        await tap(tester, 'confirmPaintColor');
        expect(selected, isNotNull);
        expect(selected, isNot(0xd75e56));
        expect(selected!, inInclusiveRange(0, 0xffffff));
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets(
    'palette and custom chooser fit a narrow window without overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 480);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final history = RecentPaintColors();
      addTearDown(history.dispose);
      for (final swatch in paintColors) {
        history.remember(swatch.rgb);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ColorPalette(
                  compact: true,
                  selectedRgb: 0x123456,
                  canFill: true,
                  history: history,
                  onColorSelected: (_) {},
                  onTargetChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tap(tester, 'morePaintColors');
      expect(tester.takeException(), isNull);
      await tap(tester, 'shade-283b78');
      await tap(tester, 'confirmPaintColor');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled controls cannot choose a color or open a dialog', (
    tester,
  ) async {
    final history = RecentPaintColors();
    addTearDown(history.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPalette(
            selectedRgb: 0x477fb2,
            onColorSelected: null,
            canFill: true,
            history: history,
            onTargetChanged: (_) => fail('Disabled target changed.'),
          ),
        ),
      ),
    );
    await tap(tester, 'color-d75e56');
    await tap(tester, 'paint-target-fill');
    await tap(tester, 'morePaintColors');
    expect(history.colors, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets(
    'compact palette keeps recent colors available without adding a row',
    (tester) async {
      final history = RecentPaintColors()..remember(0xabcdef);
      addTearDown(history.dispose);
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 680,
              child: ColorPalette(
                compact: true,
                selectedRgb: 0x477fb2,
                history: history,
                onColorSelected: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('recent-paint-color-abcdef')), findsNothing);
      expect(
        tester.getSize(find.byType(ColorPalette)).height,
        lessThanOrEqualTo(110),
      );
      await tap(tester, 'morePaintColors');
      await tap(tester, 'dialog-recent-color-abcdef');
      expect(selected, isNull);
      await tap(tester, 'confirmPaintColor');
      expect(selected, 0xabcdef);
    },
  );
  testWidgets(
    'parent modal guard can disable palette until a confirmed color returns',
    (tester) async {
      var guarded = false;
      int? selected;
      final history = RecentPaintColors();
      addTearDown(history.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => ColorPalette(
                selectedRgb: 0x123456,
                history: history,
                onColorSelected: guarded
                    ? null
                    : (value) {
                        expect(guarded, isFalse);
                        update(() => selected = value);
                      },
                onDialogVisibilityChanged: (isOpen) =>
                    update(() => guarded = isOpen),
              ),
            ),
          ),
        ),
      );
      await tap(tester, 'morePaintColors');
      expect(guarded, isTrue);
      await tap(tester, 'shade-a8d8f0');
      await tap(tester, 'confirmPaintColor');
      expect(guarded, isFalse);
      expect(selected, 0xa8d8f0);
      expect(history.colors, [0xa8d8f0]);
    },
  );

  group('the row of named colours', () {
    const allColors = [...paintColors, ...morePaintColors];

    Future<void> pumpPalette(
      WidgetTester tester,
      double width, {
      bool compact = false,
      int selectedRgb = 0x477fb2,
      ValueChanged<int>? onColorSelected,
      RecentPaintColors? history,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width < 320 ? 320 : width, 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: ColorPalette(
                  compact: compact,
                  selectedRgb: selectedRgb,
                  history: history,
                  onColorSelected: onColorSelected ?? (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // The swatches of the row, from left to right then top to bottom.
    List<(int, Rect)> swatches(WidgetTester tester) {
      final found = <(int, Rect)>[
        for (final color in allColors)
          if (find
              .byKey(Key('color-${color.rgb.toRadixString(16)}'))
              .evaluate()
              .isNotEmpty)
            (
              color.rgb,
              tester.getRect(
                find.byKey(Key('color-${color.rgb.toRadixString(16)}')),
              ),
            ),
      ];
      found.sort((a, b) {
        final byLine = a.$2.top.compareTo(b.$2.top);
        return byLine != 0 ? byLine : a.$2.left.compareTo(b.$2.left);
      });
      return found;
    }

    test('whole swatches are counted, with the gap between them', () {
      // Ten swatches of 48 and nine gaps of 9 need 561.
      expect(paletteRowCount(561, 9), 10);
      expect(paletteRowCount(560.5, 9), 9);
      expect(paletteRowCount(618, 9), 11);
      expect(paletteRowCount(552, 8), 10);
      expect(paletteRowCount(48, 9), 1);
      expect(paletteRowCount(47.9, 9), 0);
      expect(paletteRowCount(0, 9), 0);
      expect(paletteRowCount(-20, 9), 0);
      expect(paletteRowCount(double.infinity, 9), 0);
      expect(paletteRowCount(double.nan, 9), 0);
    });

    test('every named colour has one name and one value', () {
      expect(paintColors, hasLength(10));
      expect(allColors.map((color) => color.rgb).toSet(), hasLength(24));
      expect(allColors.map((color) => color.name).toSet(), hasLength(24));
      for (final color in allColors) {
        expect(color.name.trim(), isNotEmpty);
        expect(paintColorName(color.rgb), color.name);
      }
      // The order in which the added colours join the row is a choice,
      // written here on its own: the most wanted first.
      expect(morePaintColors.map((color) => color.name), [
        'Orange',
        'Chocolat',
        'Ciel',
        'Rose tendre',
        'Gris',
        'Rouge vif',
        'Vert vif',
        'Bleu vif',
        'Crème',
        'Menthe',
        'Prune',
        'Vert forêt',
        'Bleu nuit',
        'Noir',
      ]);
      expect(morePaintColors.first.rgb, 0xef9439);
      expect(morePaintColors[4].rgb, 0x9aa3a5);
      expect(morePaintColors.last.rgb, 0x1a1a1a);
    });

    test('the tick of a chosen swatch stands out on every colour', () {
      double contrast(Color first, Color second) {
        final a = first.computeLuminance();
        final b = second.computeLuminance();
        return (math.max(a, b) + .05) / (math.min(a, b) + .05);
      }

      for (final color in allColors) {
        final swatch = Color(0xff000000 | color.rgb);
        expect(
          contrast(paletteTickColor(color.rgb), swatch),
          greaterThanOrEqualTo(3),
          reason: color.name,
        );
      }
      // Whatever the colour found with the sliders, too.
      for (var grey = 0; grey < 256; grey++) {
        final rgb = (grey << 16) | (grey << 8) | grey;
        expect(
          contrast(paletteTickColor(rgb), Color(0xff000000 | rgb)),
          greaterThanOrEqualTo(3),
          reason: '$grey',
        );
      }
      // White on the dark swatches, ink on the light ones.
      expect(paletteTickColor(0x33484d), Colors.white);
      expect(paletteTickColor(0xffffff), isNot(Colors.white));
      expect(paletteTickColor(0xef9439), isNot(Colors.white));
    });

    testWidgets(
      'the first ten stay first; more colours join as the panel widens, from edge to edge',
      (tester) async {
        for (final compact in [false, true]) {
          final gap = compact ? 8.0 : 9.0;
          for (final width in <double>[561, 600, 680, 834, 1000, 1300, 1600]) {
            await pumpPalette(tester, width, compact: compact);
            expect(tester.takeException(), isNull, reason: '$width');
            final row = swatches(tester);
            final expected = paletteRowCount(width, gap).clamp(0, 24);
            expect(expected, greaterThanOrEqualTo(10));
            expect(
              row.map((entry) => entry.$1),
              allColors.take(expected).map((color) => color.rgb),
              reason: 'compact $compact, width $width',
            );
            // One line, as wide as the panel: the first swatch touches its
            // left edge, the last its right edge.
            expect(row.map((entry) => entry.$2.top).toSet(), hasLength(1));
            expect(row.first.$2.left, moreOrLessEquals(0, epsilon: .01));
            expect(row.last.$2.right, moreOrLessEquals(width, epsilon: .01));
            final gaps = [
              for (var index = 1; index < row.length; index++)
                row[index].$2.left - row[index - 1].$2.right,
            ];
            for (final between in gaps) {
              expect(between, greaterThanOrEqualTo(gap - .01));
              expect(between, moreOrLessEquals(gaps.first, epsilon: .01));
            }
            for (final entry in row) {
              expect(entry.$2.width, moreOrLessEquals(48, epsilon: .01));
              expect(entry.$2.height, moreOrLessEquals(48, epsilon: .01));
            }
          }
        }
      },
    );

    testWidgets(
      'a very wide panel shows all the colours, still from edge to edge',
      (tester) async {
        await pumpPalette(tester, 2400);
        final row = swatches(tester);
        expect(
          row.map((entry) => entry.$1),
          allColors.map((color) => color.rgb),
        );
        expect(row.first.$2.left, moreOrLessEquals(0, epsilon: .01));
        expect(row.last.$2.right, moreOrLessEquals(2400, epsilon: .01));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a panel too narrow for ten keeps the ten, on two lines', (
      tester,
    ) async {
      await pumpPalette(tester, 400);
      expect(tester.takeException(), isNull);
      final row = swatches(tester);
      expect(
        row.map((entry) => entry.$1),
        paintColors.map((color) => color.rgb),
      );
      expect(row.map((entry) => entry.$2.top).toSet(), hasLength(2));
      expect(find.byKey(const Key('paintColorRow')), findsNothing);
    });

    testWidgets(
      'a colour that joined the row is chosen, named and remembered like the first ten',
      (tester) async {
        final history = RecentPaintColors();
        addTearDown(history.dispose);
        final chosen = <int>[];
        var rgb = 0x477fb2;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 600);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => ColorPalette(
                  selectedRgb: rgb,
                  history: history,
                  onColorSelected: (value) {
                    chosen.add(value);
                    update(() => rgb = value);
                  },
                ),
              ),
            ),
          ),
        );
        final semantics = tester.ensureSemantics();
        try {
          expect(find.byTooltip('Orange'), findsOneWidget);
          await tap(tester, 'color-ef9439');
          expect(chosen, [0xef9439]);
          expect(history.colors, [0xef9439]);
          expect(find.text('COULEURS · Orange'), findsOneWidget);
          expect(
            tester.getSemantics(
              find.descendant(
                of: find.byKey(const Key('color-ef9439')),
                matching: find.byType(IconButton),
              ),
            ),
            isSemantics(
              label: 'Orange',
              isButton: true,
              isSelected: true,
              isEnabled: true,
              hasTapAction: true,
            ),
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'the colour dialog offers every added colour, whatever the row could show',
      (tester) async {
        int? chosen;
        // 600 wide: the row holds the first ten and nothing more.
        await pumpPalette(tester, 600, onColorSelected: (rgb) => chosen = rgb);
        expect(swatches(tester), hasLength(10));
        await tap(tester, 'morePaintColors');
        for (final color in morePaintColors) {
          final shade = find.byKey(Key('shade-${color.rgb.toRadixString(16)}'));
          expect(shade, findsOneWidget, reason: color.name);
          expect(
            find.descendant(of: shade, matching: find.byTooltip(color.name)),
            findsOneWidget,
          );
        }
        await tap(tester, 'shade-9aa3a5');
        await tap(tester, 'confirmPaintColor');
        expect(chosen, 0x9aa3a5);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'in the smallest window the shades of the dialog take two lines, and the sliders are announced',
      (tester) async {
        final history = RecentPaintColors();
        addTearDown(history.dispose);
        for (final rgb in [0x112233, 0x445566, 0x778899]) {
          history.remember(rgb);
        }
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(680, 520);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ColorPalette(
                selectedRgb: 0x477fb2,
                history: history,
                onColorSelected: (_) {},
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('morePaintColors')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final tops = {
          for (final color in morePaintColors)
            tester
                .getRect(
                  find.byKey(Key('shade-${color.rgb.toRadixString(16)}')),
                )
                .top,
        };
        expect(tops, hasLength(2));
        // What follows the shades shows at once, without scrolling: the
        // heading of the sliders is inside the window.
        final heading = tester.getRect(find.text('Ou invente la tienne'));
        expect(heading.bottom, lessThan(520));
        final dialog = tester.getRect(
          find.byKey(const Key('paintColorDialog')),
        );
        expect(heading.top, greaterThan(dialog.top));
        expect(heading.bottom, lessThan(dialog.bottom));
      },
    );
  });
}
