// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:edupaint_flutter_study/color_palette.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  final surface = find.byKey(const Key('drawingSurface'));
  dynamic painter(WidgetTester tester) => tester
      .widget<CustomPaint>(
        find.descendant(of: surface, matching: find.byType(CustomPaint)).first,
      )
      .painter;
  DocumentViewport viewport(WidgetTester tester) =>
      painter(tester).viewport as DocumentViewport;
  Offset point(WidgetTester tester, double x, double y) {
    final v = viewport(tester);
    return tester.getTopLeft(surface) +
        Offset(v.left + x * v.scale, v.top + y * v.scale);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    if (key == 'openProject') {
      await waitForPreparedOpen(tester, allowSaveDecision: true);
    } else if (key == 'restoreRecovery') {
      await waitForPreparedOpen(tester);
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> mount(
    WidgetTester tester,
    MemoryFiles files,
    MemoryRecovery recovery,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EduPaintApp(files: files, recoveryStorage: recovery),
    );
    await waitForPreparedOpen(tester, allowRecoveryDecision: true);
  }

  Future<(MemoryFiles, MemoryRecovery)> start(
    WidgetTester tester, {
    MemoryFiles? observedFiles,
  }) async {
    final files = observedFiles ?? MemoryFiles();
    final recovery = MemoryRecovery();
    final seed = RustDocument();
    try {
      seed.addShape(
        VectorKind.rectangle,
        const DocumentPoint(450, 250),
        const DocumentPoint(750, 550),
        rgb: 0x477fb2,
        width: 8,
        fillRgb: 0xeebf4e,
      );
      files.projects[files.savePath!] = seed.exportProject();
    } finally {
      seed.dispose();
    }
    files.openPath = files.savePath;
    await mount(tester, files, recovery);
    await tap(tester, 'openProject');
    return (files, recovery);
  }

  Future<void> exportSvg(WidgetTester tester) async {
    await tap(tester, 'exportImage');
    await tap(tester, 'exportSvg');
  }

  Future<void> exportPng(WidgetTester tester) async {
    await tap(tester, 'exportImage');
    await tester.tap(find.byKey(const Key('exportPng')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 180)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'view icon buttons expose action labels beyond their hover tooltips',
    (tester) async {
      await start(tester);
      final semantics = tester.ensureSemantics();
      try {
        for (final entry in {
          'zoomOut': 'Éloigner la feuille',
          'zoomIn': 'Rapprocher la feuille',
          'fitPage': 'Voir toute la feuille',
          'panPage': 'Déplacer la feuille',
        }.entries) {
          expect(
            tester
                .getSemantics(find.byKey(Key(entry.key)))
                .getSemanticsData()
                .label,
            entry.value,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
    skip: !available,
  );

  testWidgets(
    'view gestures preserve project, exports, recovery and rendered object cache',
    (tester) async {
      final (files, recovery) = await start(tester);
      final original = List<int>.of(files.projects[files.savePath!]!);
      final paths = painter(tester).strokes;
      await exportSvg(tester);
      final svg = files.svg;
      await exportPng(tester);
      final png = List<int>.of(files.png!);
      final writes = recovery.writes;
      final initial = viewport(tester).scale;
      await tap(tester, 'zoomIn');
      await tap(tester, 'zoomIn');
      expect(viewport(tester).scale, closeTo(initial * 1.5625, 1e-9));
      await tap(tester, 'panPage');
      await tester.drag(surface, const Offset(60, -25));
      await tester.pumpAndSettle();
      expect(identical(painter(tester).strokes, paths), isTrue);
      expect(find.textContaining('projet enregistré'), findsOneWidget);
      await tap(tester, 'saveProject');
      expect(files.projects[files.savePath!], original);
      await exportSvg(tester);
      expect(files.svg, svg);
      await exportPng(tester);
      expect(files.png, png);
      expect(recovery.writes, writes);
      final beforeResize = viewport(tester).transform;
      tester.view.physicalSize = const Size(1000, 740);
      await tester.pumpAndSettle();
      final afterResize = viewport(tester).transform;
      expect(afterResize.scale, beforeResize.scale);
      expect(
        afterResize.documentCenter.x,
        closeTo(beforeResize.documentCenter.x, 1e-7),
      );
      expect(
        afterResize.documentCenter.y,
        closeTo(beforeResize.documentCenter.y, 1e-7),
      );
      await tap(tester, 'fitPage');
      expect(viewport(tester).transform.isFit, isTrue);
      await tap(tester, 'zoomIn');
      await tap(tester, 'openProject');
      expect(viewport(tester).transform.isFit, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'selection remains aligned after zoom and pan and commits one move',
    (tester) async {
      final (files, _) = await start(tester);
      await tap(tester, 'zoomIn');
      await tap(tester, 'zoomIn');
      await tap(tester, 'panPage');
      await tester.drag(surface, const Offset(-25, 30));
      await tester.pumpAndSettle();
      await tap(tester, 'tool-select');
      final scale = viewport(tester).scale;
      final gesture = await tester.startGesture(point(tester, 600, 400));
      await gesture.moveBy(Offset(30 * scale, 20 * scale));
      await gesture.up();
      await tester.pumpAndSettle();
      await tap(tester, 'saveProject');
      final edited = RustDocument.fromProject(files.projects[files.savePath!]!);
      try {
        expect(edited.count, 1);
        expect(edited.strokes.single.points.first.x, closeTo(480, .001));
        expect(edited.strokes.single.points.first.y, closeTo(270, .001));
      } finally {
        edited.dispose();
      }
      await tap(tester, 'undo');
      await tap(tester, 'saveProject');
      final restored = RustDocument.fromProject(
        files.projects[files.savePath!]!,
      );
      try {
        expect(restored.strokes.single.points.first.x, 450);
      } finally {
        restored.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'Space, middle mouse, wheel and trackpad move the view without drawing',
    (tester) async {
      final (_, recovery) = await start(tester);
      final initial = viewport(tester).transform;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.drag(surface, const Offset(20, 10));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(viewport(tester).left, closeTo(initial.left + 20, 1e-7));
      final middle = await tester.startGesture(
        tester.getCenter(surface),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await middle.moveBy(const Offset(12, 5));
      await middle.up();
      await tester.pump();
      final beforeWheel = viewport(tester).transform;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(surface),
          scrollDelta: const Offset(0, -50),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(viewport(tester).scale, greaterThan(beforeWheel.scale));
      final beforeTrackpad = viewport(tester).scale;
      final location = tester.getCenter(surface);
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(pointer: 88, position: location),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 88,
          position: location,
          scale: 1.2,
          pan: const Offset(10, 20),
          panDelta: const Offset(10, 20),
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 88, position: location),
      );
      await tester.pumpAndSettle();
      expect(viewport(tester).scale, closeTo(beforeTrackpad * 1.2, 1e-8));
      expect(find.textContaining('1 élément'), findsOneWidget);
      expect(find.textContaining('projet enregistré'), findsOneWidget);
      expect(recovery.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'outline and inside are coloured independently, at once, one step each',
    (tester) async {
      final (files, _) = await start(tester);
      await tap(tester, 'tool-select');
      await tester.tapAt(point(tester, 600, 400));
      await tester.pumpAndSettle();
      final original = List<int>.of(files.projects[files.savePath!]!);
      // The rectangle that `start` opens: blue outline, yellow inside.
      const insideBefore = 0xeebf4e;
      ({int rgb, int? fillRgb}) colours() {
        final document = RustDocument.fromProject(
          files.projects[files.savePath!]!,
        );
        try {
          final shape = document.strokes.single;
          return (rgb: shape.rgb, fillRgb: shape.fillRgb);
        } finally {
          document.dispose();
        }
      }

      // The outline first: the inside is untouched.
      await tap(tester, 'color-d75e56');
      await tap(tester, 'saveProject');
      expect(colours(), (rgb: 0xd75e56, fillRgb: insideBefore));
      // Then the inside: the outline keeps its new colour.
      await tap(tester, 'paint-target-fill');
      await tap(tester, 'color-78a66f');
      await tap(tester, 'saveProject');
      expect(colours(), (rgb: 0xd75e56, fillRgb: 0x78a66f));
      expect(find.byKey(const Key('applySelectionStyle')), findsNothing);
      await tap(tester, 'undo');
      await tap(tester, 'saveProject');
      expect(colours(), (rgb: 0xd75e56, fillRgb: insideBefore));
      await tap(tester, 'undo');
      await tap(tester, 'saveProject');
      expect(files.projects[files.savePath!], original);
      expect(
        tester.widget<ColorPalette>(find.byType(ColorPalette)).history!.colors,
        containsAll([0xd75e56, 0x78a66f]),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'recovered page dimensions define the real bottom-right drawing coordinates',
    (tester) async {
      final seed = RustDocument(width: 640, height: 480);
      seed.addStroke(
        const [DocumentPoint(30, 40), DocumentPoint(200, 180)],
        rgb: 0xd75e56,
        width: 13,
      );
      final original = seed.exportProject();
      seed.dispose();
      final files = MemoryFiles();
      await mount(tester, files, MemoryRecovery(original));
      await tap(tester, 'restoreRecovery');
      final view = viewport(tester);
      expect(view.documentWidth, 640);
      expect(view.documentHeight, 480);
      expect(view.transform.isFit, isTrue);
      // These points are near the actual recovered page edge, not the edge of
      // the initial 1200 x 800 document that existed during startup.
      final gesture = await tester.startGesture(point(tester, 600, 430));
      await gesture.moveTo(point(tester, 625, 465));
      await gesture.up();
      await tester.pumpAndSettle();
      await tap(tester, 'saveProject');
      final saved = RustDocument.fromProject(files.projects[files.savePath!]!);
      try {
        expect(saved.width, 640);
        expect(saved.height, 480);
        expect(saved.count, 2);
        final stroke = saved.strokes.last;
        expect(stroke.kind, VectorKind.stroke);
        expect(stroke.points.first.x, closeTo(600, .001));
        expect(stroke.points.first.y, closeTo(430, .001));
        expect(stroke.points.last.x, closeTo(625, .001));
        expect(stroke.points.last.y, closeTo(465, .001));
      } finally {
        saved.dispose();
      }
      await tap(tester, 'undo');
      await tap(tester, 'saveProject');
      expect(files.projects[files.savePath!], original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'releasing Space after palette focus lets the next drag draw instead of pan',
    (tester) async {
      final (files, _) = await start(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tap(tester, 'color-d75e56');
      final swatchIcon = find.descendant(
        of: find.byKey(const Key('color-d75e56')),
        matching: find.byIcon(Icons.check_rounded),
      );
      // Explicitly exercise keyboard/accessibility focus inside the palette,
      // whose ancestor still has focus but no longer has primary focus.
      final paletteFocus = Focus.of(tester.element(swatchIcon));
      paletteFocus.requestFocus();
      await tester.pump();
      expect(paletteFocus.hasPrimaryFocus, isTrue);
      final studioFocus = tester
          .widgetList<Focus>(find.byType(Focus))
          .map((widget) => widget.focusNode)
          .whereType<FocusNode>()
          .singleWhere((node) => node.debugLabel == 'Atelier Color');
      expect(studioFocus.hasFocus, isTrue);
      expect(studioFocus.hasPrimaryFocus, isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      final before = viewport(tester).transform;
      final gesture = await tester.startGesture(point(tester, 200, 180));
      await gesture.moveTo(point(tester, 260, 220));
      await gesture.up();
      await tester.pumpAndSettle();
      final after = viewport(tester).transform;
      expect(after.left, before.left);
      expect(after.top, before.top);
      expect(after.scale, before.scale);
      await tap(tester, 'saveProject');
      final saved = RustDocument.fromProject(files.projects[files.savePath!]!);
      try {
        expect(saved.count, 2);
        expect(saved.strokes.last.kind, VectorKind.stroke);
        expect(saved.strokes.last.rgb, 0xd75e56);
        expect(saved.strokes.last.points.first.x, closeTo(200, .001));
        expect(saved.strokes.last.points.last.x, closeTo(260, .001));
      } finally {
        saved.dispose();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'custom color modal guards captured menu commands and releases them on close',
    (tester) async {
      final files = _ObservedViewFiles();
      final (_, recovery) = await start(tester, observedFiles: files);
      await tap(tester, 'tool-select');
      await tester.tapAt(point(tester, 600, 400));
      await tester.pumpAndSettle();
      final original = List<int>.of(files.projects[files.savePath!]!);
      final before = painter(tester).strokes;
      final initialColor = tester
          .widget<ColorPalette>(find.byType(ColorPalette))
          .selectedRgb;
      final commands = tester.widget<EduPaintDesktopMenu>(
        find.byType(EduPaintDesktopMenu),
      );
      final openDialogs = files.openDialogs;
      final writes = recovery.writes;
      await tap(tester, 'morePaintColors');
      // Native menu callbacks may already have been captured before the
      // widget rebuild disables a control. The actions themselves must guard.
      commands.onNew!();
      commands.onOpen!();
      commands.onSave!();
      commands.onSaveAs!();
      commands.onExportSvg!();
      commands.onExportPng!();
      commands.onUndo!();
      commands.onDuplicate!();
      commands.onDelete!();
      commands.onAbout!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      expect(find.byKey(const Key('paintColorDialog')), findsOneWidget);
      expect(files.openDialogs, openDialogs);
      expect(files.saveDialogCount, 0);
      expect(files.exportDialogs, 0);
      expect(files.projects[files.savePath!], original);
      expect(recovery.writes, writes);
      expect(identical(painter(tester).strokes, before), isTrue);
      await tap(tester, 'shade-a8d8f0');
      await tap(tester, 'cancelPaintColor');
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      expect(
        tester.widget<ColorPalette>(find.byType(ColorPalette)).selectedRgb,
        initialColor,
      );
      commands.onSaveAs!();
      await tester.pumpAndSettle();
      expect(files.saveDialogCount, 1);
      expect(files.projects[files.savePath!], original);
      await tap(tester, 'tool-stroke');
      await tap(tester, 'morePaintColors');
      await tap(tester, 'shade-a8d8f0');
      await tap(tester, 'confirmPaintColor');
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      expect(
        tester.widget<ColorPalette>(find.byType(ColorPalette)).selectedRgb,
        0xa8d8f0,
      );
      final gesture = await tester.startGesture(point(tester, 200, 180));
      await gesture.moveTo(point(tester, 260, 220));
      await gesture.up();
      await tester.pumpAndSettle();
      await tap(tester, 'saveProject');
      final saved = RustDocument.fromProject(files.projects[files.savePath!]!);
      try {
        expect(saved.count, 2);
        expect(saved.strokes.last.rgb, 0xa8d8f0);
      } finally {
        saved.dispose();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );
}

final class _ObservedViewFiles extends MemoryFiles {
  int openDialogs = 0;
  int exportDialogs = 0;

  @override
  Future<String?> chooseOpen() async {
    openDialogs++;
    return super.chooseOpen();
  }

  @override
  Future<String?> chooseExport({String? currentPath}) async {
    exportDialogs++;
    return super.chooseExport(currentPath: currentPath);
  }

  @override
  Future<String?> choosePng({String? currentPath}) async {
    exportDialogs++;
    return super.choosePng(currentPath: currentPath);
  }
}
