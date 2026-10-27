// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  final surface = find.byKey(const Key('drawingSurface'));

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    if (key == 'openProject') {
      await waitForPreparedOpen(tester, allowSaveDecision: true);
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<MemoryFiles> start(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seed = RustDocument();
    final files = MemoryFiles();
    try {
      for (final data in [
        (200.0, 200.0, 600.0, 500.0, 0x123456),
        (350.0, 260.0, 700.0, 600.0, 0xeebf4e),
        (500.0, 350.0, 850.0, 650.0, 0x176c5f),
      ]) {
        seed.addShape(
          VectorKind.rectangle,
          DocumentPoint(data.$1, data.$2),
          DocumentPoint(data.$3, data.$4),
          rgb: data.$5,
          width: 12,
          fillRgb: data.$5,
        );
      }
      files.projects[files.savePath!] = seed.exportProject();
    } finally {
      seed.dispose();
    }
    files.openPath = files.savePath;
    await tester.pumpWidget(
      EduPaintApp(files: files, recoveryStorage: MemoryRecovery()),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'openProject');
    await tap(tester, 'tool-select');
    return files;
  }

  Offset point(WidgetTester tester, double x, double y) {
    final size = tester.getSize(surface);
    final viewport = DocumentViewport(
      viewWidth: size.width,
      viewHeight: size.height,
      padding: size.height >= 160 ? 28 : 8,
    );
    return tester.getTopLeft(surface) +
        Offset(
          viewport.left + x * viewport.scale,
          viewport.top + y * viewport.scale,
        );
  }

  EduPaintDesktopMenu menu(WidgetTester tester) =>
      tester.widget<EduPaintDesktopMenu>(find.byType(EduPaintDesktopMenu));

  List<StrokeData> objects(Uint8List bytes) {
    final doc = RustDocument.fromProject(bytes);
    try {
      return doc.strokes;
    } finally {
      doc.dispose();
    }
  }

  testWidgets(
    'order exposes one enabled button with semantic and keyboard activation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await start(tester);
        final order = find.byKey(const Key('selectionOrder'));
        expect(
          tester.getSemantics(order),
          isSemantics(
            label: 'Ordre',
            tooltip: 'Ordre des éléments',
            isButton: true,
            isTextField: false,
            hasEnabledState: true,
            isEnabled: false,
            hasExpandedState: true,
            isExpanded: false,
            hasTapAction: false,
            isFocusable: false,
            hasFocusAction: false,
            hasSetTextAction: false,
          ),
        );
        await tester.tap(order);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('bringSelectionToFront')), findsNothing);

        await tester.tapAt(point(tester, 250, 250));
        await tester.pumpAndSettle();
        var node = tester.getSemantics(order);
        expect(
          node,
          isSemantics(
            label: 'Ordre',
            tooltip: 'Ordre des éléments',
            isButton: true,
            isTextField: false,
            hasEnabledState: true,
            isEnabled: true,
            hasExpandedState: true,
            isExpanded: false,
            isFocusable: true,
            hasFocusAction: true,
            hasTapAction: true,
            hasSetTextAction: false,
            children: const [],
          ),
        );
        // Role, visible label and the SDK action must merge into this one node.
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('bringSelectionToFront')), findsOneWidget);
        expect(find.byKey(const Key('sendSelectionToBack')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        node = tester.getSemantics(order);
        expect(node, isSemantics(isButton: true, isExpanded: false));
        node.owner!.performAction(node.id, SemanticsAction.focus);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(order), isSemantics(isFocused: true));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('bringSelectionToFront')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(order), isSemantics(isExpanded: false));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
    skip: !available,
  );

  testWidgets('order follows the chosen object and is one reversible edit', (
    tester,
  ) async {
    final files = await start(tester);
    final original = Uint8List.fromList(files.projects[files.savePath!]!);
    expect(menu(tester).onBringToFront, isNull);
    expect(menu(tester).onSendToBack, isNull);
    await tester.tapAt(point(tester, 250, 250));
    await tester.pumpAndSettle();
    expect(menu(tester).onSendToBack, isNull);
    await tap(tester, 'selectionOrder');
    expect(
      tester
          .widget<PopupMenuItem>(find.byKey(const Key('sendSelectionToBack')))
          .enabled,
      isFalse,
    );
    await tap(tester, 'bringSelectionToFront');
    expect(menu(tester).onBringToFront, isNull);
    expect(menu(tester).onSendToBack, isNotNull);
    expect(
      find.textContaining('3 éléments · modifications non enregistrées'),
      findsOneWidget,
    );
    await tap(tester, 'undo');
    expect(
      find.textContaining('3 éléments · projet enregistré'),
      findsOneWidget,
    );
    await tap(tester, 'saveProject');
    expect(files.projects[files.savePath!]!, original);
    await tap(tester, 'redo');
    await tap(tester, 'saveProject');
    expect(objects(files.projects[files.savePath!]!).map((s) => s.rgb), [
      0xeebf4e,
      0x176c5f,
      0x123456,
    ]);
    // The overlapping point now chooses the newly topmost rectangle.
    await tester.tapAt(point(tester, 550, 400));
    await tester.pumpAndSettle();
    await tap(tester, 'deleteSelection');
    await tap(tester, 'saveProject');
    expect(objects(files.projects[files.savePath!]!).map((s) => s.rgb), [
      0xeebf4e,
      0x176c5f,
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !available);

  testWidgets('ordering keeps the colour just given and the menu can cancel', (
    tester,
  ) async {
    final files = await start(tester);
    final original = Uint8List.fromList(files.projects[files.savePath!]!);
    await tester.tapAt(point(tester, 250, 250));
    await tester.pumpAndSettle();
    await tap(tester, 'selectionOrder');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tap(tester, 'saveProject');
    expect(files.projects[files.savePath!]!, original);
    // The colour is on the element at once, before it changes place.
    await tap(tester, 'color-d75e56');
    await tap(tester, 'saveProject');
    expect(objects(files.projects[files.savePath!]!).first.rgb, 0xd75e56);
    await tap(tester, 'selectionOrder');
    await tap(tester, 'bringSelectionToFront');
    await tap(tester, 'saveProject');
    expect(objects(files.projects[files.savePath!]!).last.rgb, 0xd75e56);
    menu(tester).onSendToBack!();
    await tester.pumpAndSettle();
    await tap(tester, 'saveProject');
    expect(objects(files.projects[files.savePath!]!).map((s) => s.rgb), [
      0xd75e56,
      0xeebf4e,
      0x176c5f,
    ]);
    expect(menu(tester).onSendToBack, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !available);

  testWidgets(
    'selection order stays usable in a small window and at large text',
    (tester) async {
      await start(tester);
      await tester.tapAt(point(tester, 250, 250));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(680, 520);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final order = find.byKey(const Key('selectionOrder'));
      expect(tester.getSize(order).height, greaterThanOrEqualTo(48));
      expect(
        tester
            .getRect(order)
            .overlaps(
              tester.getRect(find.byKey(const Key('duplicateSelection'))),
            ),
        isFalse,
      );
      await tap(tester, 'selectionOrder');
      await tap(tester, 'bringSelectionToFront');
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(1100, 760);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tap(tester, 'selectionOrder');
      await tap(tester, 'sendSelectionToBack');
      expect(menu(tester).onSendToBack, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );
  testWidgets('an open order popup resolves its intent after a native edit', (
    tester,
  ) async {
    final files = await start(tester);
    await tester.tapAt(point(tester, 250, 250));
    await tester.pumpAndSettle();
    await tap(tester, 'selectionOrder');
    // Simulate the still-available native Copy command while the popup lives.
    menu(tester).onDuplicate!();
    await tester.pumpAndSettle();
    await tap(tester, 'bringSelectionToFront');
    await tap(tester, 'saveProject');
    final ordered = objects(files.projects[files.savePath!]!);
    expect(ordered.map((s) => s.rgb), [0x123456, 0xeebf4e, 0x176c5f, 0x123456]);
    expect(ordered.last.points.first.x, 224);
    await tap(tester, 'undo');
    await tap(tester, 'saveProject');
    // Bringing an already topmost copy forward must not add a history step.
    expect(objects(files.projects[files.savePath!]!).length, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !available);
}
