// SPDX-License-Identifier: MIT
// The tools of Color 1.1 in the studio: the tips of the brush, the magics,
// the shapes in a box, the magnet that straightens, turning and mirroring
// a chosen element; each one undone in one step, and kept by version 6.
import 'dart:io';
import 'dart:math' as math;

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  // Draws through several points, as a hand does.
  Future<void> trace(StudioDriver studio, List<Offset> points) async {
    final tester = studio.tester;
    final gesture = await tester.startGesture(
      studio.sheetCenter + points.first,
    );
    for (final point in points.skip(1)) {
      await gesture.moveTo(studio.sheetCenter + point);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  List<Offset> wave(StudioDriver studio) => [
    for (var i = 0; i <= 30; i++)
      studio.at(300 + i * 15.0, 400 + 60 * math.sin(i / 5)),
  ];

  testWidgets('a tip of the brush draws with its own marks', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-stroke');
    expect(find.byKey(const Key('toolVariants')), findsOneWidget);
    await studio.tap('brushTip-chalk');
    await trace(studio, wave(studio));
    studio.expectCount(1);
    final document = await studio.saved();
    try {
      final chalk = document.strokes.single;
      expect(chalk.look.tool, BrushTool.chalk);
      expect(chalk.look.seed, isNot(0));
      expect(chalk.marks.isEmpty, isFalse);
    } finally {
      document.dispose();
    }
    // The marker: a line still, square and see-through.
    await studio.tap('brushTip-felt');
    await trace(studio, wave(studio));
    studio.expectCount(2);
    await studio.finish();
  }, skip: !available);

  testWidgets('the mirror draws twice, and Annuler takes both away', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-magic');
    await studio.tap('magic-mirror');
    await trace(studio, wave(studio));
    studio.expectCount(2);
    await studio.tap('undo');
    studio.expectCount(0);
    await studio.tap('redo');
    studio.expectCount(2);
    final document = await studio.saved();
    try {
      final [first, second] = document.strokes;
      // The second one is the first in the mirror of the middle of the sheet.
      expect(
        second.points.first.x,
        closeTo(document.width - first.points.first.x, .01),
      );
      expect(second.points.first.y, closeTo(first.points.first.y, .01));
    } finally {
      document.dispose();
    }
    await studio.finish();
  }, skip: !available);

  testWidgets('a rainbow is a stroke of its own tool', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-magic');
    await studio.tap('magic-rainbow');
    await trace(studio, wave(studio));
    final document = await studio.saved();
    try {
      expect(document.strokes.single.look.tool, BrushTool.rainbow);
      expect(document.strokes.single.marks.isEmpty, isFalse);
    } finally {
      document.dispose();
    }
    await studio.finish();
  }, skip: !available);

  testWidgets('a shape of 1.1 is drawn in its box, filled if asked', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-shapes');
    await studio.tap('shape-heart');
    await studio.drag(studio.at(400, 200), studio.at(700, 500));
    studio.expectCount(1);
    final document = await studio.saved();
    try {
      final heart = document.strokes.single;
      expect(heart.kind, VectorKind.contour);
      expect(heart.points.length, greaterThan(40));
      final xs = heart.points.map((p) => p.x);
      expect(xs.reduce(math.min), closeTo(400, 2));
      expect(xs.reduce(math.max), closeTo(700, 2));
    } finally {
      document.dispose();
    }
    await studio.finish();
  }, skip: !available);

  testWidgets('after a first click, the help of a heart speaks of a shape', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start(size: const Size(1280, 820));
    await studio.tap('tool-shapes');
    await studio.tap('shape-heart');
    await studio.click(studio.at(400, 200));
    studio.expectCount(0);
    expect(find.textContaining('ta forme se placera'), findsWidgets);
    expect(find.textContaining('ovale'), findsNothing);
    await studio.click(studio.at(700, 500));
    studio.expectCount(1);
    expect(find.textContaining('ta forme se placera'), findsNothing);
    await studio.finish();
  }, skip: !available);

  testWidgets('the magnet straightens a box drawn by hand', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-magnet');
    final square = <Offset>[
      for (var i = 0; i < 20; i++)
        studio.at(300 + i * 15.0, 200 + (i % 2) * 1.0),
      for (var i = 0; i < 20; i++)
        studio.at(600 + (i % 2) * 1.0, 200 + i * 15.0),
      for (var i = 0; i < 20; i++)
        studio.at(600 - i * 15.0, 500 - (i % 2) * 1.0),
      for (var i = 0; i < 20; i++)
        studio.at(300 - (i % 2) * 1.0, 500 - i * 15.0),
    ];
    await trace(studio, square);
    studio.expectCount(1);
    final document = await studio.saved();
    try {
      expect(document.strokes.single.kind, VectorKind.rectangle);
    } finally {
      document.dispose();
    }
    await studio.finish();
  }, skip: !available);

  testWidgets('a stamp is turned and mirrored before it is posed', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-stamp');
    await studio.click(studio.at(300, 400));
    // Two eighths of a turn, then the mirror.
    await studio.tap('turnStamp');
    await studio.tap('turnStamp');
    await studio.tap('mirrorStamp');
    await studio.click(studio.at(800, 400));
    studio.expectCount(2);
    final document = await studio.saved();
    try {
      final [plain, turned] = document.strokes;
      expect(plain.look.isPlain, isTrue);
      expect(turned.kind, VectorKind.stamp);
      expect(turned.look.rotation, closeTo(math.pi / 2, 1e-6));
      expect(turned.look.mirrorX, isTrue);
      expect(turned.stamp, plain.stamp);
    } finally {
      document.dispose();
    }
    // One step to take it back.
    await studio.tap('undo');
    studio.expectCount(1);
    await studio.finish();
  }, skip: !available);

  testWidgets('a chosen element turns and is mirrored, one step each', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-rectangle');
    await studio.drag(studio.at(400, 300), studio.at(600, 400));
    await studio.tap('tool-select');
    await studio.click(studio.at(400, 350));
    await studio.tap('turnSelection');
    await studio.tap('mirrorSelection');
    final document = await studio.saved();
    try {
      final look = document.strokes.single.look;
      expect(look.mirrorX, isTrue);
      expect(look.rotation, closeTo(-math.pi / 4, 1e-6));
    } finally {
      document.dispose();
    }
    await studio.tap('undo');
    await studio.tap('undo');
    final undone = RustDocument.fromProject(
      (await studio.saved().then((d) {
        final bytes = d.exportProject();
        d.dispose();
        return bytes;
      })),
    );
    try {
      expect(undone.strokes.single.look.transforms, isFalse);
    } finally {
      undone.dispose();
    }
    await studio.finish();
  }, skip: !available);
}
