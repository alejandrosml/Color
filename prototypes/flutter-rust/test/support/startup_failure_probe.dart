// SPDX-License-Identifier: MIT
// Dedicated headless probe, run explicitly with a nonexistent core library path.
// This file is not an automatically discovered *_test.dart suite.
import 'dart:io';

import 'package:edupaint_flutter_study/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_files.dart';

void main() {
  testWidgets(
    'real missing library startup has simple UI and guarded optional details',
    (tester) async {
      final library = Platform.environment['EDUPAINT_CORE_LIBRARY'];
      expect(library, isNotNull);
      expect(
        File(library!).existsSync(),
        isFalse,
        reason: 'This explicit probe must use a missing library.',
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(640, 480);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(EduPaintApp(recoveryStorage: MemoryRecovery()));
      await tester.pumpAndSettle();
      expect(find.text('Color n’a pas pu démarrer.'), findsOneWidget);
      expect(find.textContaining('bibliothèque Rust'), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const Key('startupProblemDetails')),
      );
      await tester.tap(find.byKey(const Key('startupProblemDetails')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('problemDetailsDialog')), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(find.byKey(const Key('problemDetailsText')))
            .data,
        contains(library),
      );
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('problemDetailsDialog')), findsNothing);
      expect(find.text('Color n’a pas pu démarrer.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
