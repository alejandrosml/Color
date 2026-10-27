// SPDX-License-Identifier: MIT
// The times of the film of a drawing. No Rust library is needed: the
// elements are given by hand, and nothing is painted.
import 'dart:io';
import 'dart:math' as math;

import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/replay.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

const _ms = Duration.microsecondsPerMillisecond;

/// A trait along one line, as long as asked.
StrokeData _trait(double length, {double from = 0}) => StrokeData(
  [DocumentPoint(from, 10), DocumentPoint(from + length, 10)],
  0,
  4,
);

StrokeData _dot() => StrokeData(const [DocumentPoint(5, 5)], 0, 4);

StrokeData _shape(VectorKind kind, {int? fillRgb}) => StrokeData(
  const [DocumentPoint(10, 10), DocumentPoint(60, 40)],
  0,
  2,
  kind: kind,
  fillRgb: fillRgb,
);

StrokeData _text(String text) => StrokeData(
  const [DocumentPoint(10, 10), DocumentPoint(200, 58)],
  0,
  40,
  kind: VectorKind.text,
  text: text,
);

ReplayPlan _plan(
  List<StrokeData> elements, {
  double diagonal = 1000,
  Duration longest = const Duration(seconds: 24),
}) => ReplayPlan(
  elements.map(RenderedElement.new).toList(),
  sheetDiagonal: diagonal,
  longest: longest,
);

int _natural(StrokeData data, {double diagonal = 1000}) =>
    ReplayPlan.naturalDuration(data, sheetDiagonal: diagonal).inMicroseconds;

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('every kind of element has its own time', () {
    expect(_natural(_dot()), 250 * _ms);
    expect(_natural(_shape(VectorKind.line)), 400 * _ms);
    expect(_natural(_shape(VectorKind.rectangle)), 700 * _ms);
    expect(
      _natural(_shape(VectorKind.rectangle, fillRgb: 0x00ff00)),
      700 * _ms,
    );
    expect(_natural(_shape(VectorKind.ellipse)), 700 * _ms);
    expect(
      _natural(
        StrokeData(
          const [DocumentPoint(10, 10), DocumentPoint(60, 60)],
          0x112233,
          1,
          kind: VectorKind.stamp,
          stamp: 0,
        ),
      ),
      450 * _ms,
    );
    // The times that the plan is written with.
    expect(ReplayPlan.shortest.inMilliseconds, 250);
    expect(ReplayPlan.slowest.inMilliseconds, 2500);
    expect(ReplayPlan.diagonalTrait.inMilliseconds, 1200);
    expect(ReplayPlan.line.inMilliseconds, 400);
    expect(ReplayPlan.shape.inMilliseconds, 700);
    expect(ReplayPlan.stamp.inMilliseconds, 450);
    expect(ReplayPlan.zone, ReplayPlan.stamp);
    expect(ReplayPlan.textStart.inMilliseconds, 300);
    expect(ReplayPlan.textCharacter.inMilliseconds, 40);
    expect(ReplayPlan.pause.inMilliseconds, 80);
  });

  test('a trait takes the time of its length, between two bounds', () {
    // As long as the diagonal of the sheet: 1.2 s.
    expect(_natural(_trait(1000)), 1200 * _ms);
    expect(_natural(_trait(500)), 600 * _ms);
    expect(_natural(_trait(250)), 300 * _ms);
    // The same trait on a sheet twice as large is half as long a film.
    expect(_natural(_trait(1000), diagonal: 2000), 600 * _ms);
    // Never shorter than a dot, never longer than 2.5 s.
    expect(_natural(_trait(100)), 250 * _ms);
    expect(_natural(_trait(1)), 250 * _ms);
    expect(_natural(_trait(2083)), closeTo(2499.6 * _ms, 1));
    expect(_natural(_trait(2084)), 2500 * _ms);
    expect(_natural(_trait(50000)), 2500 * _ms);
    // The length is the way gone, not the distance between the ends: two
    // sides of 300 and 400 are 700, although the ends are 500 apart.
    final corner = StrokeData(
      const [
        DocumentPoint(0, 0),
        DocumentPoint(300, 0),
        DocumentPoint(300, 400),
      ],
      0,
      4,
    );
    expect(_natural(corner), 840 * _ms);
    final back = StrokeData(
      const [DocumentPoint(0, 0), DocumentPoint(400, 0), DocumentPoint(0, 0)],
      0,
      4,
    );
    expect(_natural(back), 960 * _ms);
    // A trait that goes nowhere is a dot.
    final still = StrokeData(
      const [DocumentPoint(7, 7), DocumentPoint(7, 7), DocumentPoint(7, 7)],
      0,
      4,
    );
    expect(_natural(still), 250 * _ms);
    // Coordinates beyond what can be squared are simply a long trait.
    final immense = StrokeData(
      const [DocumentPoint(-1e200, 0), DocumentPoint(1e200, 0)],
      0,
      4,
    );
    expect(_natural(immense), 2500 * _ms);
  });

  test('a text takes the time of its characters, up to the longest', () {
    expect(_natural(_text('a')), 340 * _ms);
    expect(_natural(_text('abc')), 420 * _ms);
    expect(_natural(_text('Bonjour le monde')), (300 + 16 * 40) * _ms);
    // An accented letter is one character, and so is the end of a line.
    expect(_natural(_text('été')), 420 * _ms);
    expect(_natural(_text('ab\ncd')), 500 * _ms);
    // So is a character that takes two places in the memory of the program.
    expect('🙂'.length, 2);
    expect(_natural(_text('🙂')), 340 * _ms);
    expect(_natural(_text('a🙂b')), 420 * _ms);
    expect(_natural(_text('x' * 55)), 2500 * _ms);
    expect(_natural(_text('x' * 54)), 2460 * _ms);
    expect(_natural(_text('x' * 2000)), 2500 * _ms);
  });

  test('a sheet without a diagonal cannot be timed', () {
    for (final diagonal in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => ReplayPlan.naturalDuration(_dot(), sheetDiagonal: diagonal),
        throwsArgumentError,
        reason: '$diagonal',
      );
      expect(() => _plan([_dot()], diagonal: diagonal), throwsArgumentError);
    }
    expect(() => _plan([_dot()], longest: Duration.zero), throwsArgumentError);
    expect(
      () => _plan([_dot()], longest: const Duration(seconds: -1)),
      throwsArgumentError,
    );
  });

  test('the elements follow each other, a short pause between two', () {
    final plan = _plan([
      _trait(1000),
      _dot(),
      _shape(VectorKind.line),
      _shape(VectorKind.ellipse),
      _text('abc'),
    ]);
    expect(plan.length, 5);
    final expected = [
      (0, 1200),
      (1280, 1530),
      (1610, 2010),
      (2090, 2790),
      (2870, 3290),
    ];
    for (final (index, (start, end)) in expected.indexed) {
      expect(plan.startOf(index).inMicroseconds, start * _ms, reason: '$index');
      expect(plan.endOf(index).inMicroseconds, end * _ms, reason: '$index');
    }
    // No pause before the first element nor after the last.
    expect(plan.total, const Duration(milliseconds: 3290));
    // A film that fits in its longest time is not stretched to fill it.
    expect(plan.total, lessThan(const Duration(seconds: 24)));
  });

  test('a stamp takes its place in a plan', () {
    final plan = _plan([
      _dot(),
      StrokeData(
        const [DocumentPoint(10, 10), DocumentPoint(60, 60)],
        0x112233,
        1,
        kind: VectorKind.stamp,
        stamp: 0,
      ),
    ]);
    expect(plan.startOf(1), const Duration(milliseconds: 330));
    expect(plan.endOf(1), const Duration(milliseconds: 780));
    expect(plan.total, const Duration(milliseconds: 780));
  }, skip: !available);

  test(
    'the progress of an element goes from 0 at its start to 1 at its end',
    () {
      final plan = _plan([_trait(1000), _shape(VectorKind.line)]);
      Duration at(int milliseconds) => Duration(milliseconds: milliseconds);
      // The first element: 0 to 1200 ms.
      expect(plan.progressAt(0, at(-5)), 0);
      expect(plan.progressAt(0, Duration.zero), 0);
      expect(plan.progressAt(0, at(300)), .25);
      expect(plan.progressAt(0, at(600)), .5);
      expect(plan.progressAt(0, at(1199)), closeTo(.99917, .00001));
      expect(plan.progressAt(0, at(1200)), 1);
      expect(plan.progressAt(0, at(1250)), 1);
      expect(plan.progressAt(0, at(99999)), 1);
      // The second waits for the first and for the pause: 1280 to 1680 ms.
      expect(plan.progressAt(1, Duration.zero), 0);
      expect(plan.progressAt(1, at(1200)), 0);
      expect(plan.progressAt(1, at(1280)), 0);
      expect(plan.progressAt(1, at(1380)), .25);
      expect(plan.progressAt(1, at(1480)), .5);
      expect(plan.progressAt(1, at(1680)), 1);
      expect(plan.progressAt(1, plan.total), 1);
      // One microsecond is a step.
      expect(
        plan.progressAt(1, const Duration(microseconds: 1280001)),
        closeTo(1 / 400000, 1e-12),
      );
      expect(
        plan.progressAt(1, const Duration(microseconds: 1679999)),
        lessThan(1),
      );
      // There is no element beyond the last.
      expect(() => plan.progressAt(2, at(0)), throwsRangeError);
      expect(() => plan.progressAt(-1, at(0)), throwsRangeError);
      expect(() => plan.startOf(2), throwsRangeError);
      expect(() => plan.endOf(2), throwsRangeError);
    },
  );

  test('the element being drawn is the last one that started', () {
    final plan = _plan([_trait(1000), _shape(VectorKind.line), _dot()]);
    // 0–1200, 1280–1680, 1760–2010.
    Duration at(int microseconds) => Duration(microseconds: microseconds);
    expect(plan.currentAt(at(-1)), -1);
    expect(plan.currentAt(Duration.zero), 0);
    expect(plan.currentAt(at(600000)), 0);
    expect(plan.currentAt(at(1200000)), 0);
    // During a pause it is still the element just completed.
    expect(plan.currentAt(at(1279999)), 0);
    expect(plan.currentAt(at(1280000)), 1);
    expect(plan.currentAt(at(1680000)), 1);
    expect(plan.currentAt(at(1759999)), 1);
    expect(plan.currentAt(at(1760000)), 2);
    expect(plan.currentAt(plan.total), 2);
    expect(plan.currentAt(const Duration(hours: 1)), 2);

    // The complete ones are the first ones.
    expect(plan.finishedAt(at(-1)), 0);
    expect(plan.finishedAt(Duration.zero), 0);
    expect(plan.finishedAt(at(1199999)), 0);
    expect(plan.finishedAt(at(1200000)), 1);
    expect(plan.finishedAt(at(1500000)), 1);
    expect(plan.finishedAt(at(1680000)), 2);
    expect(plan.finishedAt(at(2009999)), 2);
    expect(plan.finishedAt(plan.total), 3);
    expect(plan.finishedAt(const Duration(hours: 1)), 3);
  });

  test('the page of a colouring page is there from the start, in no time', () {
    final page = [
      _shape(VectorKind.rectangle, fillRgb: 0xffffff),
      StrokeData(
        const [
          DocumentPoint(10, 10),
          DocumentPoint(90, 10),
          DocumentPoint(50, 70),
        ],
        0x2f3d4a,
        6,
        kind: VectorKind.contour,
      ),
      _trait(800),
    ];
    final drawn = [_trait(1000), _shape(VectorKind.line), _dot()];
    final alone = _plan(drawn);
    final plan = ReplayPlan(
      [...page, ...drawn].map(RenderedElement.new).toList(),
      sheetDiagonal: 1000,
      fixed: page.length,
    );
    expect(plan.length, 6);
    for (var index = 0; index < page.length; index++) {
      expect(plan.startOf(index), Duration.zero);
      expect(plan.endOf(index), Duration.zero);
      expect(plan.progressAt(index, Duration.zero), 1);
    }
    // The film of what the child drew, as if the page were not there: no
    // pause before its first element.
    for (var index = 0; index < drawn.length; index++) {
      expect(plan.startOf(page.length + index), alone.startOf(index));
      expect(plan.endOf(page.length + index), alone.endOf(index));
    }
    expect(plan.total, alone.total);
    expect(plan.startOf(3), Duration.zero);
    // At the very start the page is complete and the first trait begins.
    expect(plan.finishedAt(Duration.zero), 3);
    expect(plan.currentAt(Duration.zero), 3);
    expect(plan.progressAt(3, Duration.zero), 0);
    expect(plan.finishedAt(plan.total), 6);

    // Hurried, the page still takes no time.
    final long = [for (var index = 0; index < 40; index++) _trait(5000)];
    final hurried = ReplayPlan(
      [...page, ...long].map(RenderedElement.new).toList(),
      sheetDiagonal: 1000,
      fixed: page.length,
    );
    expect(hurried.total, const Duration(seconds: 24));
    expect(hurried.endOf(2), Duration.zero);
    expect(hurried.startOf(3), Duration.zero);
    expect(hurried.endOf(42), hurried.total);

    // A page alone: nothing to redraw, a film of no length.
    final still = ReplayPlan(
      page.map(RenderedElement.new).toList(),
      sheetDiagonal: 1000,
      fixed: page.length,
    );
    expect(still.total, Duration.zero);
    expect(still.finishedAt(Duration.zero), 3);
    expect(still.currentAt(Duration.zero), 2);
    expect(still.progressAt(2, Duration.zero), 1);
    for (final fixed in [-1, 4]) {
      expect(
        () => ReplayPlan(
          page.map(RenderedElement.new).toList(),
          sheetDiagonal: 1000,
          fixed: fixed,
        ),
        throwsRangeError,
        reason: '$fixed',
      );
    }
  });

  test('the zones that the paint pot coloured take their colour in short steps, before the drawing', () {
    final page = [_shape(VectorKind.rectangle, fillRgb: 0xffffff), _trait(800)];
    // Two zones of the page, coloured: whatever their kind and their size,
    // a step as long as a stamp's.
    final zones = [
      _shape(VectorKind.ellipse, fillRgb: 0xeebf4e),
      StrokeData(
        const [
          DocumentPoint(10, 10),
          DocumentPoint(900, 10),
          DocumentPoint(500, 700),
        ],
        0xffffff,
        .1,
        kind: VectorKind.contour,
        fillRgb: 0x9385bc,
      ),
    ];
    final drawn = [_trait(1000), _dot()];
    final plan = ReplayPlan(
      [...page, ...zones, ...drawn].map(RenderedElement.new).toList(),
      sheetDiagonal: 1000,
      fixed: page.length,
      recoloured: zones.length,
    );
    expect(plan.length, 6);
    expect(plan.endOf(1), Duration.zero);
    final expected = [(0, 450), (530, 980), (1060, 2260), (2340, 2590)];
    for (final (offset, (start, end)) in expected.indexed) {
      final index = page.length + offset;
      expect(plan.startOf(index).inMicroseconds, start * _ms, reason: '$index');
      expect(plan.endOf(index).inMicroseconds, end * _ms, reason: '$index');
    }
    expect(plan.total, const Duration(milliseconds: 2590));
    // At the start the page is there, and the first zone begins.
    expect(plan.finishedAt(Duration.zero), 2);
    expect(plan.currentAt(Duration.zero), 2);
    // Zones alone: a short film.
    final coloured = ReplayPlan(
      [...page, ...zones].map(RenderedElement.new).toList(),
      sheetDiagonal: 1000,
      fixed: page.length,
      recoloured: zones.length,
    );
    expect(coloured.total, const Duration(milliseconds: 980));
    for (final recoloured in [-1, 5]) {
      expect(
        () => ReplayPlan(
          [...page, ...zones, ...drawn].map(RenderedElement.new).toList(),
          sheetDiagonal: 1000,
          fixed: page.length,
          recoloured: recoloured,
        ),
        throwsRangeError,
        reason: '$recoloured',
      );
    }
  });

  test('an empty sheet has a film of no length', () {
    final plan = _plan(const []);
    expect(plan.length, 0);
    expect(plan.total, Duration.zero);
    expect(plan.currentAt(Duration.zero), -1);
    expect(plan.currentAt(const Duration(seconds: 3)), -1);
    expect(plan.finishedAt(const Duration(seconds: 3)), 0);
    expect(() => plan.progressAt(0, Duration.zero), throwsRangeError);
  });

  test('a film that would be too long lasts exactly the longest time', () {
    // Forty long traits: 40 × 2.5 s and 39 pauses, 103.12 s when unhurried.
    final elements = List.generate(40, (index) => _trait(5000));
    final unhurried = _plan(elements, longest: const Duration(minutes: 10));
    expect(unhurried.total, const Duration(milliseconds: 103120));

    final plan = _plan(elements);
    expect(plan.length, 40);
    expect(plan.total, const Duration(seconds: 24));
    expect(plan.endOf(39), plan.total);
    expect(plan.progressAt(39, plan.total), 1.0);
    expect(plan.startOf(0), Duration.zero);
    // Every moment is the unhurried one by the same factor, to the
    // microsecond: the elements and the pauses are shortened alike.
    final factor = 24000000 / 103120000;
    for (var index = 0; index < 40; index++) {
      expect(
        plan.startOf(index).inMicroseconds,
        closeTo(unhurried.startOf(index).inMicroseconds * factor, .5),
        reason: 'start of $index',
      );
      expect(
        plan.endOf(index).inMicroseconds,
        closeTo(unhurried.endOf(index).inMicroseconds * factor, .5),
        reason: 'end of $index',
      );
    }
    // 2.5 s became 581.846 ms and 80 ms became 18.619 ms.
    expect(
      (plan.endOf(7) - plan.startOf(7)).inMicroseconds,
      closeTo(2500000 * factor, 1),
    );
    expect(
      (plan.startOf(8) - plan.endOf(7)).inMicroseconds,
      closeTo(80000 * factor, 1),
    );

    // Any other longest time is kept as exactly.
    for (final longest in const [
      Duration(seconds: 1),
      Duration(milliseconds: 7777),
      Duration(microseconds: 1234567),
      Duration(seconds: 103),
    ]) {
      final hurried = _plan(elements, longest: longest);
      expect(hurried.total, longest);
      expect(hurried.endOf(39), longest);
      expect(hurried.progressAt(39, longest), 1.0);
      expect(
        hurried.progressAt(39, longest - const Duration(microseconds: 1)),
        lessThan(1),
      );
    }
    // A film just as long as the longest time is not touched.
    final exact = _plan(elements, longest: unhurried.total);
    for (var index = 0; index < 40; index++) {
      expect(exact.startOf(index), unhurried.startOf(index));
      expect(exact.endOf(index), unhurried.endOf(index));
    }
  });

  test('time only moves a film forward', () {
    final random = math.Random(20261005);
    final elements = [
      for (var index = 0; index < 300; index++)
        switch (random.nextInt(5)) {
          0 => _dot(),
          1 => _trait(random.nextDouble() * 3000),
          2 => _shape(VectorKind.line),
          3 => _shape(VectorKind.rectangle),
          _ => _text('x' * (1 + random.nextInt(60))),
        },
    ];
    for (final plan in [
      _plan(elements),
      _plan(elements, longest: const Duration(hours: 1)),
      // So hurried that many elements start and end in one microsecond.
      _plan(elements, longest: const Duration(microseconds: 100)),
    ]) {
      // An element starts when the one before it has ended, never earlier.
      for (var index = 0; index < plan.length; index++) {
        expect(plan.startOf(index), lessThanOrEqualTo(plan.endOf(index)));
        if (index > 0) {
          expect(
            plan.startOf(index),
            greaterThanOrEqualTo(plan.endOf(index - 1)),
          );
        }
      }
      expect(plan.endOf(plan.length - 1), plan.total);

      final total = plan.total.inMicroseconds;
      final moments = [
        for (var step = 0; step <= 500; step++) total * step ~/ 500,
      ];
      final before = List<double>.filled(plan.length, 0);
      var current = -1;
      var finished = 0;
      for (final moment in moments) {
        final elapsed = Duration(microseconds: moment);
        final nowCurrent = plan.currentAt(elapsed);
        final nowFinished = plan.finishedAt(elapsed);
        expect(nowCurrent, greaterThanOrEqualTo(current));
        expect(nowFinished, greaterThanOrEqualTo(finished));
        current = nowCurrent;
        finished = nowFinished;
        // The complete ones, then at most one being drawn, then nothing.
        expect(finished, anyOf(current, current + 1));
        for (var index = 0; index < plan.length; index++) {
          final progress = plan.progressAt(index, elapsed);
          expect(progress, inInclusiveRange(0, 1));
          expect(progress, greaterThanOrEqualTo(before[index]));
          before[index] = progress;
          if (index < finished) expect(progress, 1);
          if (index > current) expect(progress, 0);
        }
      }
      expect(current, plan.length - 1);
      expect(finished, plan.length);
      expect(before, everyElement(1.0));
    }
  });

  test('ten thousand elements still make a film of 24 s, and a fast one', () {
    final random = math.Random(7);
    final watch = Stopwatch()..start();
    final elements = [
      for (var index = 0; index < 10000; index++)
        RenderedElement(
          index.isEven
              ? _trait(20 + random.nextDouble() * 900, from: index % 300)
              : _shape(VectorKind.line),
        ),
    ];
    final prepared = watch.elapsedMilliseconds;
    watch
      ..reset()
      ..start();
    final plan = ReplayPlan(elements, sheetDiagonal: 1442);
    final planned = watch.elapsedMilliseconds;
    expect(plan.length, 10000);
    expect(plan.total, const Duration(seconds: 24));
    expect(plan.progressAt(9999, plan.total), 1.0);
    expect(plan.endOf(9999), plan.total);

    // A frame of the film completes several elements.
    const frame = Duration(microseconds: 16667);
    final middle = plan.total ~/ 2;
    expect(
      plan.finishedAt(middle + frame) - plan.finishedAt(middle),
      greaterThan(3),
    );
    expect(plan.finishedAt(middle), inInclusiveRange(4000, 6000));

    // What the painter asks for every frame of the whole film: which
    // element is being drawn and how far, and how many are complete. Each
    // answer is found without walking the ten thousand.
    watch
      ..reset()
      ..start();
    var asked = 0;
    for (var round = 0; round < 70; round++) {
      for (
        var elapsed = Duration.zero;
        elapsed <= plan.total;
        elapsed += frame
      ) {
        final current = plan.currentAt(elapsed);
        final progress = plan.progressAt(current, elapsed);
        final finished = plan.finishedAt(elapsed);
        expect(finished, progress >= 1 ? current + 1 : current);
        asked++;
      }
    }
    final answered = watch.elapsedMilliseconds;
    expect(asked, greaterThan(100000));
    // Generous bounds for a slow machine: a walk of every start for every
    // question would be a thousand million steps, not a few millions.
    expect(planned, lessThan(2000), reason: 'plan of 10000: $planned ms');
    expect(
      answered,
      lessThan(5000),
      reason: '$asked questions: $answered ms (elements: $prepared ms)',
    );

    // The answers are those of a plain walk through the elements.
    for (final moment in [0, 1, 5000000, 11999999, 12000000, 23999999]) {
      final elapsed = Duration(microseconds: moment);
      var started = 0;
      var complete = 0;
      for (var index = 0; index < plan.length; index++) {
        if (plan.startOf(index) <= elapsed) started++;
        if (plan.endOf(index) <= elapsed) complete++;
      }
      expect(plan.currentAt(elapsed), started - 1, reason: '$moment');
      expect(plan.finishedAt(elapsed), complete, reason: '$moment');
    }
  });
}
