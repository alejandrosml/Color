// SPDX-License-Identifier: MIT
// « Régler le toucher » (Color 1.1): three targets touched with a finger give
// the shift the studio then gives every finger on the sheet, never a mouse.
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/touch_calibration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('the shift is the mean miss, far misses left out, within bounds', () {
    expect(
      TouchCalibrationDialog.shiftOf(const [
        Offset(10, -6),
        Offset(12, -4),
        Offset(8, -5),
        Offset(300, 200),
      ]),
      const Offset(10, -5),
    );
    expect(TouchCalibrationDialog.shiftOf(const []), Offset.zero);
    expect(
      TouchCalibrationDialog.shiftOf(const [Offset(55, 0)]),
      const Offset(40, 0),
    );
    // Kept by the options file, within its bounds.
    final options = StudioOptions.fromJson({
      'touchShift': [12.0, -500],
    });
    expect((options.touchShiftX, options.touchShiftY), (12.0, -40.0));
    expect(StudioOptions.fromJson({'touchShift': 'à côté'}).touchShiftX, 0);
  });

  testWidgets('three touches give the shift, which the options keep', (
    tester,
  ) async {
    final store = StudioOptionsStore.memory();
    final studio = StudioDriver(tester, options: store);
    await studio.start();
    await studio.openOptions();
    await studio.tap('calibrateTouch');
    final area = tester.getRect(find.byKey(const Key('touchCalibrationArea')));
    // The finger lands 10 points left of each centre and 6 below it.
    for (final target in TouchCalibrationDialog.targets) {
      final centre =
          area.topLeft +
          Offset(target.dx * area.width, target.dy * area.height);
      await tester.tapAt(centre + const Offset(-10, 6));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('décalés de 10 et -6 points'), findsOneWidget);
    await tester.tap(find.byKey(const Key('keepTouchShift')));
    await tester.pumpAndSettle();
    expect((store.value.touchShiftX, store.value.touchShiftY), (10.0, -6.0));
    await studio.finish();
  }, skip: !available);

  testWidgets('a finger is shifted on the sheet, a mouse is not', (
    tester,
  ) async {
    final store = StudioOptionsStore.memory(
      const StudioOptions(touchShiftX: 20, touchShiftY: 0),
    );
    final studio = StudioDriver(tester, options: store);
    await studio.start();
    final scale = studio.at(1, 0).dx - studio.at(0, 0).dx;
    Future<double> firstX(PointerDeviceKind kind) async {
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(300, 300),
        kind: kind,
      );
      await gesture.moveTo(studio.sheetCenter + studio.at(500, 300));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(studio.sheetCenter + studio.at(700, 300));
      await gesture.up();
      await tester.pumpAndSettle();
      final document = await studio.saved();
      try {
        return document.strokes.last.points.first.x;
      } finally {
        document.dispose();
      }
    }

    expect(await firstX(PointerDeviceKind.touch), closeTo(300 + 20 / scale, 1));
    expect(await firstX(PointerDeviceKind.mouse), closeTo(300, 1));
    await studio.finish();
  }, skip: !available);
}
