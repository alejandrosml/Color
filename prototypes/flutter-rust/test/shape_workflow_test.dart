// SPDX-License-Identifier: MIT
// Real Rust documents; only dialogs, disk writes and recovery storage are faked.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  Future<void> start(
    WidgetTester tester,
    MemoryFiles files,
    MemoryRecovery recovery, {
    Size size = const Size(1100, 760),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EduPaintApp(files: files, recoveryStorage: recovery),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final control = find.byKey(Key(key));
    await tester.ensureVisible(control);
    await tester.tap(control);
    if (key == 'openProject') {
      await waitForPreparedOpen(tester, allowSaveDecision: true);
    } else if (key == 'restoreRecovery') {
      await waitForPreparedOpen(tester);
    } else {
      await tester.pumpAndSettle();
    }
  }

  void expectCount(int count) => expect(
    find.textContaining(
      count <= 1 ? '$count élément · ' : '$count éléments · ',
    ),
    findsOneWidget,
  );

  Future<void> draw(
    WidgetTester tester, {
    Offset from = const Offset(-40, -20),
    Offset to = const Offset(55, 35),
  }) async {
    final center = tester.getCenter(find.byKey(const Key('drawingSurface')));
    final gesture = await tester.startGesture(center + from);
    await gesture.moveTo(center + to);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, bool enabled) async {
    final control = find.byKey(const Key('fillShapeCheckbox'));
    expect(control, findsOneWidget);
    final direct = tester.widget(control);
    final checkbox = direct is Checkbox
        ? direct
        : tester.widget<Checkbox>(
            find.descendant(of: control, matching: find.byType(Checkbox)),
          );
    if (checkbox.value != enabled) await tap(tester, 'fillShapeCheckbox');
  }

  Future<String> svg(WidgetTester tester, MemoryFiles files) async {
    await tap(tester, 'exportImage');
    await tap(tester, 'exportSvg');
    expect(files.svg, isNotNull);
    return files.svg!;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  Future<List<int>> canvasPixels(WidgetTester tester) async {
    final canvas = find.descendant(
      of: find.byKey(const Key('drawingSurface')),
      matching: find.byType(RepaintBoundary),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(canvas);
    return (await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        return bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      } finally {
        image.dispose();
      }
    }))!;
  }

  testWidgets(
    'all four tools preserve typed shapes and fill through save, reopen and history',
    (tester) async {
      final files = MemoryFiles();
      await start(tester, files, MemoryRecovery());
      await tap(tester, 'tool-stroke');
      await draw(tester);
      await tap(tester, 'tool-line');
      await draw(
        tester,
        from: const Offset(70, 30),
        to: const Offset(-60, -40),
      );
      await tap(tester, 'tool-rectangle');
      await fill(tester, true);
      await draw(
        tester,
        from: const Offset(90, 45),
        to: const Offset(-50, -30),
      );
      await tap(tester, 'tool-ellipse');
      await fill(tester, false);
      await draw(
        tester,
        from: const Offset(70, 40),
        to: const Offset(-65, -25),
      );
      expectCount(4);

      final before = await svg(tester, files);
      expect(_elements(before, 'path'), hasLength(1));
      final line = _elements(before, 'line').single;
      expect(_number(line, 'x1'), greaterThan(_number(line, 'x2')));
      final rectangle = _elements(before, 'rect').single;
      expect(_number(rectangle, 'width'), greaterThan(0));
      expect(_number(rectangle, 'height'), greaterThan(0));
      expect(_attribute(rectangle, 'fill'), isNot('none'));
      expect(_attribute(_elements(before, 'ellipse').single, 'fill'), 'none');

      await tap(tester, 'saveProject');
      final reopened = RustDocument.fromProject(files.projects.values.single);
      try {
        expect(reopened.count, 4);
        expect(reopened.exportSvg(), before);
      } finally {
        reopened.dispose();
      }
      await tap(tester, 'newProject');
      await tap(tester, 'createNewSheet');
      expectCount(0);
      files.openPath = files.savePath;
      await tap(tester, 'openProject');
      expectCount(4);
      expect(await svg(tester, files), before);
      await tap(tester, 'undo');
      expectCount(3);
      expect(_elements(await svg(tester, files), 'ellipse'), isEmpty);
      await tap(tester, 'redo');
      expectCount(4);
      expect(await svg(tester, files), before);
      await finish(tester);
    },
    skip: !available,
  );

  testWidgets('Shift constrains backwards drags to a square and a circle', (
    tester,
  ) async {
    final files = MemoryFiles();
    await start(tester, files, MemoryRecovery());
    for (final tool in ['rectangle', 'ellipse']) {
      await tap(tester, 'tool-$tool');
      await fill(tester, false);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      try {
        await draw(
          tester,
          from: const Offset(70, 25),
          to: const Offset(-40, -30),
        );
      } finally {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
    }
    expectCount(2);
    final exported = await svg(tester, files);
    final rectangle = _elements(exported, 'rect').single;
    expect(
      _number(rectangle, 'width'),
      closeTo(_number(rectangle, 'height'), .001),
    );
    final ellipse = _elements(exported, 'ellipse').single;
    expect(_number(ellipse, 'rx'), closeTo(_number(ellipse, 'ry'), .001));
    expect(_number(ellipse, 'rx'), greaterThan(0));
    await finish(tester);
  }, skip: !available);

  testWidgets(
    'Escape cancels a shape preview without changing history or recovery',
    (tester) async {
      final files = MemoryFiles();
      final recovery = MemoryRecovery();
      await start(tester, files, recovery);
      await tap(tester, 'tool-line');
      await draw(tester);
      await tap(tester, 'saveProject');
      final before = await svg(tester, files);
      expect(recovery.bytes, isNull);
      await tap(tester, 'tool-ellipse');
      final center = tester.getCenter(find.byKey(const Key('drawingSurface')));
      final gesture = await tester.startGesture(center - const Offset(35, 25));
      await gesture.moveTo(center + const Offset(50, 40));
      await tester.pump();
      expectCount(1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expectCount(1);
      expect(recovery.bytes, isNull);
      expect(await svg(tester, files), before);
      await tap(tester, 'undo');
      expectCount(0);
      await finish(tester);
    },
    skip: !available,
  );

  testWidgets(
    'Shift updates a stationary shape preview immediately and restores its original proportions',
    (tester) async {
      final files = MemoryFiles();
      await start(tester, files, MemoryRecovery());
      await tap(tester, 'tool-rectangle');
      await fill(tester, true);
      final center = tester.getCenter(find.byKey(const Key('drawingSurface')));
      final gesture = await tester.startGesture(
        center + const Offset(-60, -40),
      );
      await gesture.moveTo(center + const Offset(80, 20));
      await tester.pump();
      final unconstrained = await canvasPixels(tester);
      expectCount(0);

      // No pointer events between these frames: the keyboard must repaint alone.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      final constrained = await canvasPixels(tester);
      expect(
        listEquals(constrained, unconstrained),
        isFalse,
        reason: 'Pressing Shift must visibly change the stationary preview.',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        listEquals(await canvasPixels(tester), unconstrained),
        isTrue,
        reason: 'Releasing Shift must restore the unconstrained preview.',
      );
      expectCount(0);

      await gesture.up();
      await tester.pumpAndSettle();
      expectCount(1);
      final rectangle = _elements(await svg(tester, files), 'rect').single;
      expect(
        _number(rectangle, 'width') / _number(rectangle, 'height'),
        closeTo(140 / 60, .001),
      );
      await finish(tester);
    },
    skip: !available,
  );

  testWidgets(
    'compact toolbars remain usable and documents keep their geometry after resize',
    (tester) async {
      final files = MemoryFiles();
      await start(tester, files, MemoryRecovery(), size: const Size(680, 520));
      var count = 0;
      String? previous;
      for (final size in [const Size(680, 520), const Size(1280, 520)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Layout at $size');
        if (previous != null) expect(await svg(tester, files), previous);
        for (final tool in ['stroke', 'line', 'rectangle', 'ellipse']) {
          await tap(tester, 'tool-$tool');
          await draw(
            tester,
            from: const Offset(-15, -10),
            to: const Offset(18, 12),
          );
          expectCount(++count);
          expect(tester.takeException(), isNull, reason: '$tool at $size');
        }
        previous = await svg(tester, files);
      }
      await finish(tester);
    },
    skip: !available,
  );

  testWidgets(
    'PNG large-format option exports the current shapes without replacing the project',
    (tester) async {
      final files = MemoryFiles();
      await start(tester, files, MemoryRecovery());
      await tap(tester, 'tool-rectangle');
      await fill(tester, true);
      await draw(tester);
      await tap(tester, 'saveProject');
      final project = Uint8List.fromList(files.projects.values.single);
      await tap(tester, 'exportImage');
      await tap(tester, 'pngScale2');
      // Engine image encoding completes outside the widget test's fake clock.
      await tester.tap(find.byKey(const Key('exportPng')));
      await tester.pump();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 200 && files.png == null; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(files.png, isNotNull);
      final bytes = files.png!;
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final data = ByteData.sublistView(bytes);
      expect(data.getUint32(16), 2400);
      expect(data.getUint32(20), 1600);
      expect(files.projects.values.single, project);
      expectCount(1);
      await finish(tester);
    },
    skip: !available,
  );

  testWidgets(
    'recovery restores filled and outline shapes and permits continued drawing',
    (tester) async {
      final files = MemoryFiles();
      final recovery = MemoryRecovery();
      await start(tester, files, recovery);
      await tap(tester, 'tool-rectangle');
      await fill(tester, true);
      await draw(tester);
      await tap(tester, 'tool-ellipse');
      await fill(tester, false);
      await draw(
        tester,
        from: const Offset(65, 35),
        to: const Offset(-40, -20),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(recovery.bytes, isNotNull);
      final saved = RustDocument.fromProject(recovery.bytes!);
      late String original;
      try {
        expect(saved.count, 2);
        original = saved.exportSvg();
      } finally {
        saved.dispose();
      }
      await finish(tester);
      await tester.pumpWidget(
        EduPaintApp(files: files, recoveryStorage: recovery),
      );
      await waitForPreparedOpen(tester, allowRecoveryDecision: true);
      await tap(tester, 'restoreRecovery');
      expectCount(2);
      expect(await svg(tester, files), original);
      await tap(tester, 'tool-stroke');
      await draw(tester);
      expectCount(3);
      await tap(tester, 'saveProject');
      expect(recovery.bytes, isNull);
      final project = RustDocument.fromProject(files.projects.values.single);
      try {
        expect(project.count, 3);
        expect(_elements(project.exportSvg(), 'ellipse'), hasLength(1));
      } finally {
        project.dispose();
      }
      await finish(tester);
    },
    skip: !available,
  );
}

/// Restrict to painted document elements; the SVG's white backdrop has no stroke.
List<String> _elements(String svg, String element) =>
    RegExp('<$element\\b[^>]*>')
        .allMatches(svg)
        .map((match) => match.group(0)!)
        .where((tag) => tag.contains('stroke='))
        .toList();

String _attribute(String element, String name) =>
    RegExp('\\b$name="([^"]+)"').firstMatch(element)!.group(1)!;

double _number(String element, String name) =>
    double.parse(_attribute(element, name));
