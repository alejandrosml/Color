// SPDX-License-Identifier: MIT
// Requires the real Rust library; the core is never replaced with a mock.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';

import 'support/memory_files.dart';

void main() {
  final libraryPath = Platform.environment['EDUPAINT_CORE_LIBRARY'];
  testWidgets(
    'real document: draw, resize, undo and redo without losing a stroke',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 820);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(EduPaintApp(recoveryStorage: MemoryRecovery()));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Scaffold)), const Size(1280, 820));
      expect(
        tester.takeException(),
        isNull,
        reason: 'Initial 1280×820 layout.',
      );
      expect(find.textContaining('0 élément · '), findsOneWidget);
      final center = tester.getCenter(find.byKey(const Key('drawingSurface')));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(65, -30));
      await gesture.up();
      await tester.pump();
      expect(find.textContaining('1 élément'), findsOneWidget);
      for (final size in [
        const Size(960, 780),
        const Size(680, 520),
        const Size(1280, 520),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(Scaffold)), size);
        expect(find.textContaining('1 élément'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'No overflow or render error at $size.',
        );
        final canvas = tester.getSize(find.byKey(const Key('drawingSurface')));
        expect(canvas.width, greaterThan(0));
        expect(canvas.height, greaterThan(0));
      }
      await tester.tap(find.byKey(const Key('undo')));
      await tester.pump();
      expect(find.textContaining('0 élément · '), findsOneWidget);
      await tester.tap(find.byKey(const Key('redo')));
      await tester.pump();
      expect(find.textContaining('1 élément'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: libraryPath == null,
  );
  test(
    'native error preserves the last snapshot and permits further editing',
    () {
      final document = RustDocument(libraryPath: libraryPath);
      try {
        document.addStroke(
          const [DocumentPoint(50, 80)],
          rgb: 0x123456,
          width: 10,
        );
        final original = document.exportSvg();
        expect(
          () => document.addStroke(
            const [DocumentPoint(-1, 80)],
            rgb: 0x123456,
            width: 10,
          ),
          throwsA(isA<RustCoreException>()),
        );
        expect(document.exportSvg(), original);
        expect(document.count, 1);
        document.addStroke(
          const [DocumentPoint(100, 120)],
          rgb: 0xabcdef,
          width: 4,
        );
        expect(document.count, 2);
        expect(document.undo(), isTrue);
        expect(document.exportSvg(), original);
      } finally {
        document.dispose();
      }
    },
    skip: libraryPath == null,
  );
}
