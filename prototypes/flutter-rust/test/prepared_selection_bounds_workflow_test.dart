// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/selection_geometry.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';

EduPaintDesktopMenu _menu(WidgetTester tester) =>
    tester.widget<EduPaintDesktopMenu>(find.byType(EduPaintDesktopMenu));

dynamic _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find
          .descendant(
            of: find.byKey(const Key('drawingSurface')),
            matching: find.byType(CustomPaint),
          )
          .first,
    )
    .painter;

List<RenderedElement> _elements(WidgetTester tester) =>
    List<RenderedElement>.of(_painter(tester).strokes as List<RenderedElement>);

Future<void> _idle(WidgetTester tester) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (_menu(tester).onSave != null) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  fail('The studio did not become available.');
}

Future<void> _tap(WidgetTester tester, String key) async {
  final control = find.byKey(Key(key));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await _idle(tester);
}

void _checkBounds(WidgetTester tester) {
  final elements = _elements(tester);
  for (final element in elements) {
    expect(element.controlBounds, objectBounds(element.data));
  }
  final int? selected = _painter(tester).selectedIndex as int?;
  if (selected != null) {
    expect(
      _painter(tester).selectionBounds,
      objectBounds(elements[selected].data, includeStroke: true),
    );
  }
}

void main() {
  testWidgets(
    'studio bounds follow movement, order, style, undo, redo and document replacement',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 760);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final seed = RustDocument();
      final files = MemoryFiles()..openPath = '/initial.edupaint';
      try {
        seed.addStroke(
          const [DocumentPoint(50, 50), DocumentPoint(200, 80)],
          rgb: 0x123456,
          width: 5,
        );
        seed.addShape(
          VectorKind.rectangle,
          const DocumentPoint(400, 250),
          const DocumentPoint(650, 500),
          rgb: 0x477fb2,
          width: 12,
          fillRgb: 0xeebf4e,
        );
        files.projects[files.openPath!] = seed.exportProject();
      } finally {
        seed.dispose();
      }
      await tester.pumpWidget(
        EduPaintApp(files: files, recoveryStorage: MemoryRecovery()),
      );
      await _idle(tester);
      await _tap(tester, 'openProject');
      final initial = _elements(tester);
      expect(initial, hasLength(2));
      _checkBounds(tester);
      await _tap(tester, 'tool-select');
      final viewport = _painter(tester).viewport as DocumentViewport;
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const Key('drawingSurface'))) +
            Offset(
              viewport.left + 500 * viewport.scale,
              viewport.top + 350 * viewport.scale,
            ),
      );
      await tester.pumpAndSettle();
      expect(_painter(tester).selectedIndex, 1);
      _checkBounds(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final moved = _elements(tester);
      expect(identical(moved[0], initial[0]), isTrue);
      expect(identical(moved[1], initial[1]), isFalse);
      expect(
        moved[1].controlBounds,
        initial[1].controlBounds.shift(const Offset(1, 0)),
      );
      _checkBounds(tester);

      _menu(tester).onSendToBack!();
      await tester.pumpAndSettle();
      final reordered = _elements(tester);
      expect(identical(reordered[0], moved[1]), isTrue);
      expect(identical(reordered[1], moved[0]), isTrue);
      expect(_painter(tester).selectedIndex, 0);
      _checkBounds(tester);

      await _tap(tester, 'color-d75e56');
      final restyled = _elements(tester);
      expect(restyled[0].data.rgb, 0xd75e56);
      expect(identical(restyled[0], reordered[0]), isFalse);
      expect(identical(restyled[1], reordered[1]), isTrue);
      expect(restyled[0].controlBounds, reordered[0].controlBounds);
      _checkBounds(tester);

      for (var step = 0; step < 3; step++) {
        _menu(tester).onUndo!();
        await tester.pumpAndSettle();
        _checkBounds(tester);
      }
      expect(
        _elements(tester).map((e) => e.controlBounds),
        initial.map((e) => e.controlBounds),
      );
      for (var step = 0; step < 3; step++) {
        _menu(tester).onRedo!();
        await tester.pumpAndSettle();
        _checkBounds(tester);
      }
      expect(
        _elements(tester).map((e) => e.controlBounds),
        restyled.map((e) => e.controlBounds),
      );
      await _tap(tester, 'saveProject');

      final replacement = RustDocument(width: 640, height: 480);
      try {
        replacement.addShape(
          VectorKind.ellipse,
          const DocumentPoint(10, 20),
          const DocumentPoint(110, 90),
          rgb: 0,
          width: 2,
        );
        files.openPath = '/replacement.edupaint';
        files.projects[files.openPath!] = replacement.exportProject();
      } finally {
        replacement.dispose();
      }
      await _tap(tester, 'openProject');
      final current = _elements(tester);
      expect(current, hasLength(1));
      expect(
        current.single.controlBounds,
        const Rect.fromLTRB(10, 20, 110, 90),
      );
      expect(_painter(tester).selectedIndex, isNull);
      expect(initial.any((old) => identical(old, current.single)), isFalse);
      _checkBounds(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: Platform.environment['EDUPAINT_CORE_LIBRARY'] == null,
  );
}
