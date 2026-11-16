// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:edupaint_flutter_study/color_palette.dart';
import 'package:edupaint_flutter_study/galets.dart';
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
    'cancelled custom choices never change selection or session history',
    (tester) async {
      final history = RecentPaintColors();
      addTearDown(history.dispose);
      final selected = <int>[];
      final dialogStates = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _Chooser(
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
          body: _Chooser(
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
              body: _Chooser(
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

  group('the named colours', () {
    const allColors = [...paintColors, ...morePaintColors];
    // Those of the pebbles (Color 1.2): the ten of the line and their
    // families.
    final ofThePebbles = [
      ...galetColours,
      for (final family in galetFamilies) ...family,
    ];

    test('every named colour has one name and one value', () {
      expect(paintColors, hasLength(10));
      expect(allColors.map((color) => color.rgb).toSet(), hasLength(24));
      expect(allColors.map((color) => color.name).toSet(), hasLength(24));
      for (final color in allColors) {
        expect(color.name.trim(), isNotEmpty);
        expect(paintColorName(color.rgb), color.name);
      }
    });

    test('the tick of a chosen swatch stands out on every colour', () {
      double contrast(Color first, Color second) {
        final a = first.computeLuminance();
        final b = second.computeLuminance();
        return (math.max(a, b) + .05) / (math.min(a, b) + .05);
      }

      for (final color in [...allColors, ...ofThePebbles]) {
        final swatch = Color(0xff000000 | color.rgb);
        expect(
          contrast(paletteTickColor(color.rgb), swatch),
          greaterThanOrEqualTo(3),
          reason: color.name,
        );
      }
      // Whatever the colour found in the field of the older children, too.
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
  });
}

/// A button that opens « Trouve ta couleur » as the studio does: once at a
/// time, the choice reported and remembered only when it is confirmed.
class _Chooser extends StatefulWidget {
  const _Chooser({
    required this.selectedRgb,
    required this.onColorSelected,
    this.history,
    this.onDialogVisibilityChanged,
  });
  final int selectedRgb;
  final ValueChanged<int> onColorSelected;
  final RecentPaintColors? history;
  final ValueChanged<bool>? onDialogVisibilityChanged;

  @override
  State<_Chooser> createState() => _ChooserState();
}

class _ChooserState extends State<_Chooser> {
  bool _open = false;

  Future<void> _choose() async {
    if (_open) return;
    _open = true;
    widget.onDialogVisibilityChanged?.call(true);
    int? chosen;
    try {
      chosen = await showPaintColorDialog(
        context,
        initialRgb: widget.selectedRgb,
        recentColors: widget.history?.colors ?? const [],
      );
    } finally {
      widget.onDialogVisibilityChanged?.call(false);
      _open = false;
    }
    if (chosen != null) {
      widget.history?.remember(chosen);
      widget.onColorSelected(chosen);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: const Key('morePaintColors'),
    onPressed: _choose,
    child: const Text('Mélanger'),
  );
}
