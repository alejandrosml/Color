// SPDX-License-Identifier: MIT
// The paint pot of Color 1.1 on the paper: it fills the zone that the lines
// drawn around close, a small gap plugged, as a contour of its own under the
// lines; again in it, it changes its colour; a window drawn in it gets a
// zone of its own. In the United States it closes no gap. Real Rust
// documents; only dialogs' destinations and storage are in memory.
import 'dart:io';
import 'dart:math' as math;

import 'package:edupaint_flutter_study/country_signs.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  Future<void> trace(StudioDriver studio, List<(double, double)> points) async {
    final tester = studio.tester;
    final (x0, y0) = points.first;
    final gesture = await tester.startGesture(
      studio.sheetCenter + studio.at(x0, y0),
    );
    for (final (x, y) in points.skip(1)) {
      await gesture.moveTo(studio.sheetCenter + studio.at(x, y));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  // The sides of a box drawn by hand, every 20 units, from its top-left
  // corner around to [gap] units short of it.
  List<(double, double)> box(
    double left,
    double top,
    double right,
    double bottom, {
    double gap = 0,
  }) => [
    for (var x = left; x < right; x += 20) (x, top),
    for (var y = top; y < bottom; y += 20) (right, y),
    for (var x = right; x > left; x -= 20) (x, bottom),
    for (var y = bottom; y > top + gap; y -= 20) (left, y),
    (left, top + gap),
  ];

  Rect bounds(StrokeData object) =>
      Rect.fromLTRB(left(object), top(object), right(object), bottom(object));

  testWidgets(
    'the pot fills a box drawn by hand, its small gap closed, under its line',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stroke');
      // A box whose line stops short of where it began: a gap of a few
      // millimetres on the screen.
      await trace(studio, box(300, 200, 600, 500, gap: 26));
      studio.expectCount(1);
      await studio.tap('tool-fill');
      await studio.tap('color-eebf4e');
      await studio.pour(studio.at(450, 350));
      studio.expectCount(2);

      var document = await studio.saved();
      try {
        final [zone, line] = document.strokes;
        expect(line.kind, VectorKind.stroke);
        expect(zone.kind, VectorKind.contour);
        expect(zone.look.zone, isTrue);
        expect(zone.fillRgb, 0xeebf4e);
        expect(zone.rgb, 0xeebf4e);
        // Inside the box, a little under its line, which stays in front.
        final inside = bounds(zone);
        final width = line.width;
        expect(inside.left, inInclusiveRange(300, 300 + width / 2));
        expect(inside.top, inInclusiveRange(200, 200 + width / 2));
        expect(inside.right, inInclusiveRange(600 - width / 2, 600));
        expect(inside.bottom, inInclusiveRange(500 - width / 2, 500));
        expect(document.paperRgb, whitePaper);
      } finally {
        document.dispose();
      }
      // One step: Annuler takes the zone away, Rétablir brings it back.
      await studio.tap('undo');
      studio.expectCount(1);
      await studio.tap('redo');
      studio.expectCount(2);

      // In the same zone again, another colour: the zone changes colour.
      await studio.tap('color-9385bc');
      await studio.pour(studio.at(500, 300));
      studio.expectCount(2);
      // A window drawn in it, then poured: a zone of its own, over the
      // first one, under the lines.
      await studio.tap('tool-stroke');
      await trace(studio, [
        for (var i = 0; i <= 40; i++)
          (
            450 + 50 * math.cos(i / 40 * 2 * math.pi),
            350 + 50 * math.sin(i / 40 * 2 * math.pi),
          ),
        (500, 360),
      ]);
      studio.expectCount(3);
      await studio.tap('tool-fill');
      await studio.tap('color-d75e56');
      await studio.pour(studio.at(450, 350));
      studio.expectCount(4);
      document = await studio.saved();
      try {
        final [outer, window, box, round] = document.strokes;
        expect(outer.look.zone, isTrue);
        expect(outer.fillRgb, 0x9385bc);
        expect(window.look.zone, isTrue);
        expect(window.fillRgb, 0xd75e56);
        expect(bounds(window).width, inInclusiveRange(80, 100));
        expect(box.kind, VectorKind.stroke);
        expect(round.kind, VectorKind.stroke);
        // The window's zone is kept by version 6 as a zone.
        expect(document.exportProject()[8], 6);
      } finally {
        document.dispose();
      }
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('in the United States the pot closes no gap', (tester) async {
    final studio = StudioDriver(
      tester,
      countrySigns: () async => CountrySigns(codes: const ['US']),
    );
    await studio.start();
    await studio.tap('tool-stroke');
    await trace(studio, box(300, 200, 600, 500, gap: 26));
    await studio.tap('tool-fill');
    await studio.tap('color-eebf4e');
    await studio.pour(studio.at(450, 350));
    // The paint runs out through the gap: the whole sheet takes it, as in
    // Color 1.0.
    studio.expectCount(1);
    var document = await studio.saved();
    try {
      expect(document.paperRgb, 0xeebf4e);
    } finally {
      document.dispose();
    }
    // A box that closes holds it, there as elsewhere.
    await studio.tap('tool-stroke');
    await trace(studio, box(700, 200, 900, 400, gap: -30));
    await studio.tap('tool-fill');
    await studio.tap('color-9385bc');
    await studio.pour(studio.at(800, 300));
    studio.expectCount(3);
    document = await studio.saved();
    try {
      expect(document.strokes.first.look.zone, isTrue);
      expect(document.strokes.first.fillRgb, 0x9385bc);
    } finally {
      document.dispose();
    }
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'the pot pours a gradient from its colour to the one chosen before',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-rectangle');
      await studio.drag(studio.at(200, 200), studio.at(500, 450));
      await studio.tap('tool-fill');
      expect(find.byKey(const Key('pour-plain')), findsOneWidget);
      await studio.tap('pour-linear');
      await studio.tap('color-eebf4e');
      await studio.tap('color-d75e56');
      // Inside the rectangle: its inside, from red to the yellow before.
      await studio.click(studio.at(350, 325));
      var document = await studio.saved();
      try {
        final box = document.strokes.single;
        expect(box.fillRgb, 0xd75e56);
        expect(box.look.gradient, GradientKind.linear);
        expect(box.look.gradientRgb, 0xeebf4e);
        expect(box.rgb, 0x477fb2);
      } finally {
        document.dispose();
      }
      expect(await studio.svg(), contains('linearGradient'));
      // One step.
      await studio.tap('undo');
      document = await studio.saved();
      try {
        expect(document.strokes.single.fillRgb, isNull);
        expect(document.strokes.single.look.hasGradient, isFalse);
      } finally {
        document.dispose();
      }
      // On the bare sheet a gradient is a zone of the whole sheet, under
      // the rest; the paper keeps its colour.
      await studio.tap('pour-radial');
      await studio.pour(studio.at(900, 600));
      document = await studio.saved();
      try {
        final [zone, box] = document.strokes;
        expect(zone.look.zone, isTrue);
        expect(zone.look.gradient, GradientKind.radial);
        expect(zone.rings, hasLength(2));
        expect(box.kind, VectorKind.rectangle);
        expect(document.paperRgb, whitePaper);
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('a gradient on an empty sheet covers it all', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-fill');
    await studio.tap('pour-linear');
    await studio.tap('color-9385bc');
    await studio.click(studio.at(600, 400));
    studio.expectCount(1);
    final document = await studio.saved();
    try {
      final zone = document.strokes.single;
      expect(zone.look.zone, isTrue);
      expect(zone.look.gradient, GradientKind.linear);
      expect(zone.look.gradientRgb, 0x477fb2);
      expect(zone.points, hasLength(4));
      expect(document.paperRgb, whitePaper);
    } finally {
      document.dispose();
    }
    await studio.finish();
  }, skip: !available);

  testWidgets('outside a shape the zone keeps a hole where the shape is', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('tool-rectangle');
    await studio.drag(studio.at(200, 200), studio.at(500, 450));
    await studio.tap('tool-fill');
    await studio.tap('color-78a66f');
    await studio.pour(studio.at(900, 600));
    studio.expectCount(2);
    final document = await studio.saved();
    try {
      final zone = document.strokes.first;
      expect(zone.look.zone, isTrue);
      expect(zone.rings, hasLength(2));
      // The whole sheet but the rectangle.
      final sheet = bounds(zone);
      expect(sheet.left, lessThan(1));
      expect(sheet.top, lessThan(1));
      expect(sheet.right, greaterThan(1199));
      expect(sheet.bottom, greaterThan(799));
      expect(document.strokes.last.kind, VectorKind.rectangle);
      expect(document.strokes.last.fillRgb, isNull);
      expect(document.paperRgb, whitePaper);
      expect(await studio.svg(), contains('fill-rule="evenodd"'));
    } finally {
      document.dispose();
    }
    await studio.finish();
  }, skip: !available);
}
