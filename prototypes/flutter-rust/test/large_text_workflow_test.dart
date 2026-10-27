// SPDX-License-Identifier: MIT
// End-to-end widget actions with the actual native document and enlarged text.
// Window sizes are content sizes, not a claim about native title-bar geometry.
import 'dart:io';
import 'dart:convert';

import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget, reason: '$key is reachable');
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _draw(WidgetTester tester) async {
  final surface = find.byKey(const Key('drawingSurface'));
  expect(tester.getSize(surface).height, greaterThan(60));
  final gesture = await tester.startGesture(tester.getCenter(surface));
  await gesture.moveBy(const Offset(24, -16));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await _tap(tester, 'saveProject');
  await waitForPreparedOpen(tester);
}

// These two bounded curves deliberately scale action and title text differently.
class _NonlinearScale extends TextScaler {
  const _NonlinearScale(this.small, this.large);
  final double small;
  final double large;
  @override
  double scale(double fontSize) => fontSize * (fontSize <= 14 ? small : large);
  @override
  double get textScaleFactor => small;
}

Widget _withScale(EduPaintApp app, TextScaler scaler) => Builder(
  builder: (context) {
    final actual = app.build(context) as MaterialApp;
    return MaterialApp(
      theme: actual.theme,
      localizationsDelegates: actual.localizationsDelegates,
      supportedLocales: actual.supportedLocales,
      home: actual.home,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: child!,
      ),
    );
  },
);

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  for (final (size, factor, nonlinear) in <(Size, double, TextScaler?)>[
    (const Size(1280, 820), 2, null),
    (const Size(680, 520), 2, null),
    (const Size(680, 480), 2, null),
    (const Size(1261, 820), 1, null),
    (const Size(1262, 820), 1, null),
    (const Size(1261, 820), 1.5, null),
    (const Size(1262, 820), 1.5, null),
    (const Size(1280, 520), 1.5, null),
    (const Size(1280, 520), 2, null),
    (const Size(1280, 820), 2, const _NonlinearScale(2, 1.25)),
    (const Size(1280, 520), 1.5, const _NonlinearScale(1.5, 2)),
  ]) {
    testWidgets(
      'text $factor nonlinear=$nonlinear actions and preserved drawing at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = factor;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final files = MemoryFiles();
        final app = EduPaintApp(
          files: files,
          recoveryStorage: MemoryRecovery(),
        );
        await tester.pumpWidget(
          nonlinear == null ? app : _withScale(app, nonlinear),
        );
        await waitForPreparedOpen(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: 'Initial $size scale$factor',
        );
        final surface = tester.getRect(find.byKey(const Key('drawingSurface')));
        debugPrint(
          'LARGE_TEXT_METRIC ${jsonEncode({'width': size.width, 'height': size.height, 'textFactor': factor, 'nonlinear': nonlinear != null, 'canvasWidth': surface.width, 'canvasHeight': surface.height})}',
        );
        await _draw(tester);
        await _save(tester);
        final original = Uint8List.fromList(files.projects[files.savePath!]!);
        final saved = RustDocument.fromProject(original);
        try {
          expect(saved.count, 1);
        } finally {
          saved.dispose();
        }
        await _tap(tester, 'undo');
        await tester.pumpAndSettle();
        expect(find.textContaining('0 élément · '), findsOneWidget);
        await _tap(tester, 'redo');
        await tester.pumpAndSettle();
        expect(find.textContaining('1 élément'), findsOneWidget);

        // Use actual selection buttons, including lower controls revealed by scroll.
        await _tap(tester, 'tool-select');
        await tester.pumpAndSettle();
        await tester.tapAt(
          tester.getCenter(find.byKey(const Key('drawingSurface'))),
        );
        await tester.pumpAndSettle();
        // The colour changes the chosen stroke at once: one step to undo.
        await _tap(tester, 'color-d75e56');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('applySelectionStyle')), findsNothing);
        await _save(tester);
        expect(files.projects[files.savePath!], isNot(original));
        await _tap(tester, 'undo');
        await tester.pumpAndSettle();
        await _save(tester);
        expect(files.projects[files.savePath!], original);
        // Undo intentionally clears the selection; select the unchanged stroke again.
        await tester.tapAt(
          tester.getCenter(find.byKey(const Key('drawingSurface'))),
        );
        await tester.pumpAndSettle();
        await _tap(tester, 'duplicateSelection');
        await tester.pumpAndSettle();
        expect(find.textContaining('2 éléments'), findsOneWidget);
        await _tap(tester, 'selectionOrder');
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await _tap(tester, 'deleteSelection');
        await tester.pumpAndSettle();
        expect(find.textContaining('1 élément'), findsOneWidget);
        await _tap(tester, 'tool-stroke');
        await tester.pumpAndSettle();
        await _tap(
          tester,
          'openProject',
        ); // Canceled by the memory file chooser.
        await waitForPreparedOpen(tester);
        await _tap(tester, 'newProject');
        await tester.pumpAndSettle();
        await _tap(tester, 'newSheet-portrait');
        await tester.pumpAndSettle();
        await _tap(tester, 'cancelNewSheet');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('newSheetDialog')), findsNothing);
        await _tap(tester, 'morePaintColors');
        await tester.pumpAndSettle();
        await _tap(tester, 'cancelPaintColor');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('paintColorDialog')), findsNothing);
        await _tap(tester, 'exportImage');
        await tester.pumpAndSettle();
        await _tap(tester, 'exportSvg');
        await waitForPreparedOpen(tester);
        expect(files.svg, contains('<svg'));

        // Resizing a live document at enlarged text must preserve editable bytes.
        tester.view.physicalSize = size.width == 680
            ? const Size(1280, 820)
            : const Size(680, 520);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Resize after drawing');
        await _save(tester);
        expect(files.projects[files.savePath!], original);
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();

        // A genuine failed write exposes optional details without changing data.
        files.failWrite = true;
        await _save(tester);
        await _tap(tester, 'showProblemDetails');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('problemDetailsDialog')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('problemDetailsDialog')), findsNothing);
        expect(files.projects[files.savePath!], original);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: !available,
    );
  }
}
