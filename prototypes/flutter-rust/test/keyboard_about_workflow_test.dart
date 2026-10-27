// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:edupaint_flutter_study/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';

bool _focused(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isFocused ==
    Tristate.isTrue;

Future<void> _tabTo(
  WidgetTester tester,
  Finder finder, {
  int limit = 80,
}) async {
  for (var step = 0; step < limit; step++) {
    if (_focused(tester, finder)) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }
  fail('Keyboard traversal did not reach $finder within $limit Tabs.');
}

Future<void> _openAbout(WidgetTester tester) async {
  final more = find.byKey(const Key('moreFileActions'));
  await tester.tap(more);
  await tester.pumpAndSettle();
  final about = find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem && widget.value == 'about',
  );
  expect(about, findsOneWidget);
  await tester.tap(about);
  await tester.pumpAndSettle();
  expect(find.text('Un dessin que tu peux retrouver.'), findsOneWidget);
}

Rect _lastGlyph(WidgetTester tester) {
  final text = find.textContaining('Les projets Color gardent');
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  final length = paragraph.text.toPlainText().length;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: length - 1, extentOffset: length),
  );
  expect(boxes, isNotEmpty);
  return boxes.last.toRect().shift(paragraph.localToGlobal(Offset.zero));
}

Rect _readingClip(WidgetTester tester) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.textContaining('Les projets Color gardent'),
      matching: find.byType(RichText),
    ),
  );
  final viewport = RenderAbstractViewport.maybeOf(paragraph);
  final RenderBox box = viewport is RenderBox
      ? viewport as RenderBox
      : paragraph;
  return (box.localToGlobal(Offset.zero) & box.size).intersect(
    tester.getRect(find.byType(AlertDialog)),
  );
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  for (final height in [480.0, 520.0]) {
    testWidgets(
      'About text end reachable and keyboard return at 680x$height text200%',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(680, height);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final semantics = tester.ensureSemantics();
        try {
          final files = MemoryFiles();
          await tester.pumpWidget(
            EduPaintApp(files: files, recoveryStorage: MemoryRecovery()),
          );
          await waitForPreparedOpen(tester);
          final surface = find.byKey(const Key('drawingSurface'));
          final gesture = await tester.startGesture(tester.getCenter(surface));
          await gesture.moveBy(const Offset(24, -16));
          await gesture.up();
          await tester.pumpAndSettle();
          await _tabTo(tester, find.byKey(const Key('saveProject')));
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await waitForPreparedOpen(tester);
          final before = Uint8List.fromList(files.projects[files.savePath!]!);

          await _openAbout(tester);
          final dialog = find.byType(AlertDialog);
          final close = find.widgetWithText(TextButton, 'Revenir au dessin');
          expect(close.hitTestable(), findsOneWidget);
          final closeRect = tester.getRect(close);
          expect(closeRect.bottom, lessThanOrEqualTo(height));
          final initialEnd = _lastGlyph(tester);
          // Reach the actual last glyph with user scroll input, not by invoking a
          // controller or asserting a particular ScrollView implementation.
          for (
            var step = 0;
            step < 8 && _lastGlyph(tester).bottom > _readingClip(tester).bottom;
            step++
          ) {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: tester.getCenter(dialog),
                scrollDelta: const Offset(0, 240),
              ),
            );
            await tester.pumpAndSettle();
          }
          final end = _lastGlyph(tester);
          debugPrint(
            'ABOUT_END height=$height initial=$initialEnd final=$end action=$closeRect',
          );
          expect(end.top, greaterThanOrEqualTo(_readingClip(tester).top));
          expect(
            end.bottom,
            lessThanOrEqualTo(_readingClip(tester).bottom),
            reason:
                'The last glyph must be inside the visible content viewport.',
          );
          expect(
            end.bottom,
            lessThanOrEqualTo(closeRect.top),
            reason: 'The last sentence must be visible above the still available return action.',
          );
          expect(close.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _tabTo(tester, close, limit: 6);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(dialog, findsNothing);

          // Reopening and Escape release the modal guard and preserve this project.
          await _openAbout(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(dialog, findsNothing);
          await _tabTo(tester, find.byKey(const Key('saveProject')));
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await waitForPreparedOpen(tester);
          expect(files.projects[files.savePath!], before);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      },
      skip: !available,
    );
  }
}
