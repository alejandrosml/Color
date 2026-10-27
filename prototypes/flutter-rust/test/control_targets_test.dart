// SPDX-License-Identifier: MIT
import 'dart:ui' show SemanticsAction;

import 'package:edupaint_flutter_study/brush_width_control.dart';
import 'package:edupaint_flutter_study/color_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final desktopPlatforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
});

void main() {
  testWidgets('palette targets cover their edges and leave inactive gaps', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(680, 520);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final colors = <int>[];
    final targets = <PaintColorTarget>[];
    var rgb = 0x477fb2;
    var target = PaintColorTarget.stroke;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, update) => ColorPalette(
                compact: true,
                selectedRgb: rgb,
                canFill: true,
                target: target,
                onColorSelected: (value) {
                  colors.add(value);
                  update(() => rgb = value);
                },
                onTargetChanged: (value) {
                  targets.add(value);
                  update(() => target = value);
                },
              ),
            ),
          ),
        ),
      ),
    );
    final semantics = tester.ensureSemantics();
    try {
      final swatches = [
        for (final color in paintColors)
          find.byKey(Key('color-${color.rgb.toRadixString(16)}')),
      ];
      for (var index = 0; index < swatches.length; index++) {
        final rect = tester.getRect(swatches[index]);
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
        await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
        await tester.pumpAndSettle();
        expect(colors.last, paintColors[index].rgb);
        await tester.tapAt(Offset(rect.center.dx, rect.bottom - 1));
        await tester.pumpAndSettle();
        expect(colors.length, (index + 1) * 2);
        expect(
          tester.getSemantics(
            find.descendant(
              of: swatches[index],
              matching: find.byType(IconButton),
            ),
          ),
          isSemantics(
            label: paintColors[index].name,
            isButton: true,
            isSelected: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
      }
      final left = tester.getRect(swatches.first);
      final right = tester.getRect(swatches[1]);
      expect(right.left - left.right, greaterThanOrEqualTo(8));
      final before = colors.length;
      await tester.tapAt(Offset((left.right + right.left) / 2, left.center.dy));
      await tester.pumpAndSettle();
      expect(colors.length, before);
      final fill = find.byKey(const Key('paint-target-fill'));
      final stroke = find.byKey(const Key('paint-target-stroke'));
      final fillRect = tester.getRect(fill);
      final strokeRect = tester.getRect(stroke);
      expect(fillRect.height, greaterThanOrEqualTo(48));
      expect(strokeRect.height, greaterThanOrEqualTo(48));
      expect(fillRect.left - strokeRect.right, greaterThanOrEqualTo(8));
      await tester.tapAt(Offset(fillRect.center.dx, fillRect.top + 1));
      await tester.pumpAndSettle();
      expect(targets, [PaintColorTarget.fill]);
      await tester.tapAt(
        Offset((strokeRect.right + fillRect.left) / 2, fillRect.center.dy),
      );
      await tester.pumpAndSettle();
      expect(targets, hasLength(1));
      await tester.tapAt(Offset(strokeRect.center.dx, strokeRect.bottom - 1));
      await tester.pumpAndSettle();
      expect(targets, [PaintColorTarget.fill, PaintColorTarget.stroke]);
      final more = find.byKey(const Key('morePaintColors'));
      final moreRect = tester.getRect(more);
      expect(moreRect.width, greaterThanOrEqualTo(48));
      expect(moreRect.height, greaterThanOrEqualTo(48));
      await tester.tapAt(Offset(moreRect.center.dx, moreRect.top + 1));
      await tester.pumpAndSettle();
      expect(find.byType(PaintColorDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(colors.length, before);
      // Focus and keyboard activation must still reach the same one action.
      final node = tester.getSemantics(
        find.descendant(of: swatches.first, matching: find.byType(IconButton)),
      );
      node.owner!.performAction(node.id, SemanticsAction.focus);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(colors.length, before + 1);
      expect(colors.last, paintColors.first.rgb);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(colors.length, before + 2);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  }, variant: desktopPlatforms);

  testWidgets(
    'width target accepts upper and lower edge clicks but not its outside margin',
    (tester) async {
      var value = 12.0;
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, update) => SizedBox(
                  width: 140,
                  child: BrushWidthControl(
                    value: value,
                    onChanged: (next) {
                      changes++;
                      update(() => value = next);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final control = find.byKey(const Key('brushWidthSemantics'));
      final rect = tester.getRect(control);
      expect(rect.height, greaterThanOrEqualTo(48));
      await tester.tapAt(Offset(rect.left + 1, rect.top + 1));
      await tester.pumpAndSettle();
      expect(value, 2);
      await tester.tapAt(Offset(rect.right - 1, rect.bottom - 1));
      await tester.pumpAndSettle();
      expect(value, 48);
      expect(changes, 2);
      await tester.tapAt(Offset(rect.center.dx, rect.bottom + 4));
      await tester.pumpAndSettle();
      expect(changes, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(value, 47);
      expect(tester.takeException(), isNull);
    },
    variant: desktopPlatforms,
  );

  testWidgets(
    'custom color controls keep large targets in a narrow enlarged dialog',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 480);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      int? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColorPalette(
              compact: true,
              selectedRgb: 0x477fb2,
              onColorSelected: (value) => chosen = value,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('morePaintColors')));
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      try {
        final shade = find.byKey(const Key('shade-f4b7cf'));
        await tester.ensureVisible(shade);
        await tester.pumpAndSettle();
        expect(tester.getSize(shade), const Size(48, 48));
        for (final label in ['Couleur', 'Intensité', 'Clarté']) {
          final control = find.byKey(ValueKey('paintAxis-$label'));
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          final rect = tester.getRect(control);
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(
            tester.getSemantics(control),
            isSemantics(label: label, isSlider: true),
          );
        }
        final lightness = find.byKey(const ValueKey('paintAxis-Clarté'));
        final rect = tester.getRect(lightness);
        await tester.tapAt(Offset(rect.left + 1, rect.top + 1));
        await tester.pumpAndSettle();
        expect(tester.getSemantics(lightness), isSemantics(value: '0 %'));
        await tester.tapAt(Offset(rect.right - 1, rect.bottom - 1));
        await tester.pumpAndSettle();
        expect(tester.getSemantics(lightness), isSemantics(value: '100 %'));
        expect(chosen, isNull);
        await tester.tap(find.byKey(const Key('cancelPaintColor')));
        await tester.pumpAndSettle();
        expect(chosen, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    variant: desktopPlatforms,
  );
}
