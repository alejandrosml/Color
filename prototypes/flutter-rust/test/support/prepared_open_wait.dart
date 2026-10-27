// SPDX-License-Identifier: MIT
import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Project preparation uses real worker turns while the opening spinner keeps
/// animating. Wait for the studio or an explicitly expected decision instead of
/// settling that spinner. This helper never completes a held read/write itself.
Future<void> waitForPreparedOpen(
  WidgetTester tester, {
  bool allowSaveDecision = false,
  bool allowRecoveryDecision = false,
}) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    // Always rebuild once before observing callbacks, including after a tap.
    await tester.pump(const Duration(milliseconds: 10));
    final saveDecision =
        allowSaveDecision &&
        find.byKey(const Key('saveChanges')).evaluate().isNotEmpty;
    final recoveryDecision =
        allowRecoveryDecision &&
        find.byKey(const Key('restoreRecovery')).evaluate().isNotEmpty;
    final menu = tester.widget<EduPaintDesktopMenu>(
      find.byType(EduPaintDesktopMenu),
    );
    if (menu.onSave != null || saveDecision || recoveryDecision) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  fail('Project preparation did not reach the studio or expected decision.');
}
