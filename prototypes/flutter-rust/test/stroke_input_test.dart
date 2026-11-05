// SPDX-License-Identifier: MIT
// What a trait keeps of the pointer (the techniques of the retrospective of
// October 2026, and its D-08): the 1€ filter on the samples of a finger or a
// pen, the samples that do not move dropped, the points that the eye cannot
// tell from a straight line taken out at the end, and a pen that takes the
// trait over from a hand resting on the screen.
import 'dart:io';
import 'dart:math' as math;

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/stroke_input.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_painters.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

Duration _ms(num milliseconds) =>
    Duration(microseconds: (milliseconds * 1000).round());

void main() {
  test('the string holds the brush until the pointer pulls it tight', () {
    final string = StringStabilizer(length: 10);
    expect(string.pull(0, 0), (0, 0));
    // A tremble shorter than the string: the brush does not move.
    expect(string.pull(6, -4), (0, 0));
    expect(string.pull(-3, 7), (0, 0));
    // Pulled: it follows, the string's length behind.
    final (x, y) = string.pull(30, 0);
    expect(x, closeTo(20, 1e-9));
    expect(y, closeTo(0, 1e-9));
    final (x2, y2) = string.pull(30, 40);
    expect(
      math.sqrt((30 - x2) * (30 - x2) + (40 - y2) * (40 - y2)),
      closeTo(10, 1e-9),
    );
  });

  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  group('the 1€ filter', () {
    test('keeps the first sample, and a pointer at rest where it is', () {
      final filter = OneEuroFilter();
      expect(filter.filter(10, 20, Duration.zero), (10.0, 20.0));
      for (var sample = 1; sample <= 30; sample++) {
        final (x, y) = filter.filter(10, 20, _ms(sample * 8));
        expect(x, 10);
        expect(y, 20);
      }
    });

    test('smooths the tremble of a slow finger', () {
      final filter = OneEuroFilter();
      final random = math.Random(5);
      var raw = 0.0;
      var smooth = 0.0;
      filter.filter(100, 100, Duration.zero);
      for (var sample = 1; sample <= 240; sample++) {
        // A finger that moves 30 px a second and trembles by a pixel.
        final x = 100 + sample * 8 * .03 + (random.nextDouble() * 2 - 1);
        final y = 100 + (random.nextDouble() * 2 - 1);
        final (fx, fy) = filter.filter(x, y, _ms(sample * 8));
        if (sample > 40) {
          raw += (y - 100).abs();
          smooth += (fy - 100).abs();
        }
        expect(fx, lessThan(x + 2));
      }
      expect(smooth, lessThan(raw / 2));
    });

    test('follows a quick finger closely', () {
      final filter = OneEuroFilter();
      filter.filter(0, 0, Duration.zero);
      var lag = 0.0;
      for (var sample = 1; sample <= 60; sample++) {
        // 1 500 px a second, a sample every 8 ms.
        final x = sample * 12.0;
        final (fx, _) = filter.filter(x, 0, _ms(sample * 8));
        lag = x - fx;
      }
      // Less than the lag of a 60 Hz frame at that speed (25 px).
      expect(lag, lessThan(25));
      expect(lag, greaterThanOrEqualTo(0));
    });

    test('a quick check mark keeps its corner', () {
      // 175 ms, a sample every 8 ms: down 42 px, then up 108 px.
      final filter = OneEuroFilter();
      const corner = Offset(30, 30);
      final samples = [
        for (var i = 0; i <= 21; i++)
          i <= 7
              ? corner * (i / 7)
              : corner + const Offset(60, -90) * ((i - 7) / 14),
      ];
      final kept = [
        for (final (i, sample) in samples.indexed)
          filter.filter(sample.dx, sample.dy, _ms(i * 8)),
      ];
      // The nearest the trait comes to the corner of the finger.
      final nearest = kept
          .map((p) => (Offset(p.$1, p.$2) - corner).distance)
          .reduce(math.min);
      expect(nearest, lessThan(4));
    });

    test('a sample at the same time as the one before is not smoothed', () {
      final filter = OneEuroFilter()..filter(0, 0, _ms(8));
      expect(filter.filter(50, 50, _ms(8)), (50.0, 50.0));
      expect(filter.filter(60, 60, _ms(4)), (60.0, 60.0));
    });
  });

  group('the points kept at the end of a trait', () {
    test('a straight trait keeps its two ends', () {
      final xs = [for (var i = 0; i <= 50; i++) i * 4.0];
      final ys = [for (var i = 0; i <= 50; i++) 10 + i * 2.0];
      expect(simplifiedIndices(xs, ys, .25), [0, 50]);
    });

    test('a corner, and what lies farther than the tolerance, stay', () {
      expect(simplifiedIndices([0, 50, 100], [0, 0, 0], .25), [0, 2]);
      expect(simplifiedIndices([0, 50, 100], [0, 40, 0], .25), [0, 1, 2]);
      expect(simplifiedIndices([0, 50, 100], [0, .3, 0], .25), [0, 1, 2]);
      expect(simplifiedIndices([0, 50, 100], [0, .2, 0], .25), [0, 2]);
      // A trait that comes back on itself keeps where it turned.
      expect(simplifiedIndices([0, 100, 20], [0, 0, 0], .25), [0, 1, 2]);
      // One point, two, none: as they are.
      expect(simplifiedIndices([3], [4], .25), [0]);
      expect(simplifiedIndices([3, 5], [4, 6], .25), [0, 1]);
      expect(simplifiedIndices([], [], .25), isEmpty);
    });

    test('a long zigzag of colouring is simplified in a time that grows '
        'with its points only', () {
      // Back and forth, 24 points a leg, as regular as a ruler.
      final xs = <double>[];
      final ys = <double>[];
      for (var i = 0; i < 100000; i++) {
        final leg = i ~/ 24, along = i % 24;
        xs.add(leg * 2.0 + along * .1);
        ys.add(leg.isEven ? along * 4.0 : (24 - along) * 4.0);
      }
      final watch = Stopwatch()..start();
      final kept = simplifiedIndices(xs, ys, .25);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(kept.first, 0);
      expect(kept.last, xs.length - 1);
      // Every corner stays, and the points between them go.
      expect(kept.length, lessThan(xs.length ~/ 10));
      for (var k = 1; k < kept.length; k++) {
        final a = kept[k - 1], b = kept[k];
        for (var i = a + 1; i < b; i++) {
          final dx = xs[b] - xs[a], dy = ys[b] - ys[a];
          final length = math.sqrt(dx * dx + dy * dy);
          final away =
              ((xs[i] - xs[a]) * dy - (ys[i] - ys[a]) * dx).abs() / length;
          expect(away, lessThanOrEqualTo(.26));
        }
      }
    });

    test('a long wobbly trait loses what the eye cannot see, quickly', () {
      final xs = <double>[];
      final ys = <double>[];
      for (var i = 0; i < 100000; i++) {
        xs.add(i * .5);
        ys.add(20 * math.sin(i / 400) + (i.isEven ? .05 : -.05));
      }
      final watch = Stopwatch()..start();
      final kept = simplifiedIndices(xs, ys, .25);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(kept.first, 0);
      expect(kept.last, xs.length - 1);
      expect(kept.length, lessThan(xs.length ~/ 20));
      // Every point taken out lies within the tolerance of what is kept.
      for (var k = 1; k < kept.length; k++) {
        final a = kept[k - 1], b = kept[k];
        for (var i = a + 1; i < b; i++) {
          final t = (xs[i] - xs[a]) / (xs[b] - xs[a]);
          final y = ys[a] + t * (ys[b] - ys[a]);
          expect((ys[i] - y).abs(), lessThanOrEqualTo(.26));
        }
      }
    });
  });

  group('in the studio', () {
    Future<RustDocument> trait(
      WidgetTester tester,
      StudioDriver studio,
      PointerDeviceKind kind,
      List<Offset> points,
    ) async {
      // The samples come every 8 ms, as a screen of 120 Hz gives them.
      final gesture = await tester.createGesture(kind: kind);
      await gesture.down(studio.sheetCenter + points.first);
      for (final (index, point) in points.indexed.skip(1)) {
        await tester.pump(const Duration(milliseconds: 8));
        await gesture.moveTo(
          studio.sheetCenter + point,
          timeStamp: Duration(milliseconds: 8 * index),
        );
      }
      await tester.pump(const Duration(milliseconds: 8));
      await gesture.up(timeStamp: Duration(milliseconds: 8 * points.length));
      await tester.pumpAndSettle();
      return studio.saved();
    }

    testWidgets('a mouse is followed exactly; its straight line keeps its '
        'ends', (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      final document = await trait(tester, studio, PointerDeviceKind.mouse, [
        for (var i = 0; i <= 10; i++) Offset(-200 + i * 40.0, 0),
      ]);
      addTearDown(document.dispose);
      final points = document.strokes.single.points;
      expect(points, hasLength(2));
      final scale = studio.view().scale;
      expect(points.first.x, closeTo(600 - 200 / scale, .01));
      expect(points.last.x, closeTo(600 + 200 / scale, .01));
      await studio.finish();
    }, skip: !available);

    testWidgets('a trembling finger draws a smoother trait, which ends under '
        'the finger', (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      final random = math.Random(3);
      final samples = [
        for (var i = 0; i <= 80; i++)
          Offset(-160 + i * 4.0, (random.nextDouble() * 2 - 1) * 1.5),
      ];
      final document = await trait(
        tester,
        studio,
        PointerDeviceKind.touch,
        samples,
      );
      addTearDown(document.dispose);
      final points = document.strokes.single.points;
      final scale = studio.view().scale;
      // How far the trait wanders, on average, from the line the finger
      // meant: a fifth less at least, at this speed (500 px a second).
      double wander(Iterable<double> ys) =>
          ys.map((y) => (y - 400).abs()).reduce((a, b) => a + b) /
          ys.length *
          scale;
      final raw = wander([
        for (final s in samples.skip(2).take(samples.length - 4))
          400 + s.dy / scale,
      ]);
      final drawn = wander([
        for (final p in points.skip(2).take(points.length - 4)) p.y,
      ]);
      expect(drawn, lessThan(raw * .8));
      // The end is where the finger left, not where the filter was.
      expect(points.last.x, closeTo(600 + samples.last.dx / scale, .01));
      await studio.finish();
    }, skip: !available);

    testWidgets('with « Trait tranquille » a trembling hand draws calm', (
      tester,
    ) async {
      final studio = StudioDriver(
        tester,
        options: StudioOptionsStore.memory(
          const StudioOptions(steadyHand: true),
        ),
      );
      await studio.start();
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(200, 400),
        kind: PointerDeviceKind.mouse,
      );
      // Along the sheet, trembling three units up and down at each step.
      for (var i = 1; i <= 60; i++) {
        await gesture.moveTo(
          studio.sheetCenter +
              studio.at(200 + i * 10.0, 400 + (i.isOdd ? 3 : -3)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final document = await studio.saved();
      try {
        final points = document.strokes.single.points;
        // After its first point, the trait no longer trembles.
        for (final point in points.skip(3)) {
          expect(point.y, closeTo(400, 1.5));
        }
        expect(points.last.x, greaterThan(700));
      } finally {
        document.dispose();
      }
      await studio.finish();
    }, skip: !available);

    testWidgets('moves the eye cannot see are not kept', (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      final document = await trait(tester, studio, PointerDeviceKind.mouse, [
        const Offset(-100, 0),
        const Offset(-99.8, .1),
        const Offset(-99.7, 0),
        const Offset(-50, 40),
        const Offset(0, 0),
      ]);
      addTearDown(document.dispose);
      // The two first moves are within 0.4 px of the start: dropped.
      expect(document.strokes.single.points, hasLength(3));
      await studio.finish();
    }, skip: !available);

    testWidgets('a pen stops two fingers of the resting hand that move the '
        'view', (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      final center = studio.sheetCenter;
      DocumentViewport viewport() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<DocumentPainter>()
          .single
          .viewport;
      final first = await tester.startGesture(
        center + const Offset(-150, 80),
        kind: PointerDeviceKind.touch,
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(-110, 100),
        kind: PointerDeviceKind.touch,
        pointer: 2,
      );
      await tester.pump();
      // Two contacts of the palm, which move apart: the view zooms.
      await first.moveBy(const Offset(-20, 0));
      await second.moveBy(const Offset(20, 0));
      await tester.pump();
      final zoomed = viewport();
      final pen = await tester.startGesture(
        center + const Offset(-100, -60),
        kind: PointerDeviceKind.stylus,
        pointer: 3,
      );
      await tester.pump();
      for (var step = 1; step <= 5; step++) {
        await pen.moveBy(const Offset(30, 10));
        await first.moveBy(const Offset(-8, 2));
        await second.moveBy(const Offset(8, -2));
        await tester.pump(const Duration(milliseconds: 8));
      }
      // The view stayed as the pen found it.
      final now = viewport();
      expect(now.scale, zoomed.scale);
      expect(now.left, zoomed.left);
      expect(now.top, zoomed.top);
      await pen.up();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final document = await studio.saved();
      addTearDown(document.dispose);
      // One trait, the pen's, where the pen drew on that view.
      expect(document.strokes, hasLength(1));
      final start = document.strokes.single.points.first;
      final local = tester.getTopLeft(find.byKey(const Key('drawingSurface')));
      final pressed = center + const Offset(-100, -60) - local;
      final expected = zoomed.point(pressed.dx, pressed.dy);
      expect(start.x, closeTo(expected.x, 1));
      expect(start.y, closeTo(expected.y, 1));
      await studio.finish();
    }, skip: !available);

    testWidgets('a pen takes the trait over from a resting hand', (
      tester,
    ) async {
      final studio = StudioDriver(tester);
      await studio.start();
      final center = studio.sheetCenter;
      final hand = await tester.startGesture(
        center + const Offset(-150, 80),
        kind: PointerDeviceKind.touch,
        pointer: 1,
      );
      await hand.moveBy(const Offset(10, 2));
      await tester.pump();
      final pen = await tester.startGesture(
        center + const Offset(-100, -60),
        kind: PointerDeviceKind.stylus,
        pointer: 2,
      );
      await tester.pump();
      for (var step = 1; step <= 6; step++) {
        await pen.moveBy(const Offset(30, 10));
        await hand.moveBy(const Offset(3, 1));
        await tester.pump(const Duration(milliseconds: 8));
      }
      // Another finger of the hand: no pinch while the pen draws.
      final other = await tester.startGesture(
        center + const Offset(-170, 100),
        kind: PointerDeviceKind.touch,
        pointer: 3,
      );
      await other.moveBy(const Offset(-20, 0));
      await tester.pump();
      await pen.moveBy(const Offset(30, 10));
      await pen.up();
      await other.up();
      await hand.up();
      await tester.pumpAndSettle();
      final document = await studio.saved();
      addTearDown(document.dispose);
      // One trait: the pen's, not the hand's.
      expect(document.strokes, hasLength(1));
      final first = document.strokes.single.points.first;
      final scale = studio.view().scale;
      expect(first.x, closeTo(600 - 100 / scale, 2));
      expect(first.y, closeTo(400 - 60 / scale, 2));
      await studio.finish();
    }, skip: !available);
  });
}
