// SPDX-License-Identifier: MIT
// An element drawn part of the way, as the film of a drawing shows it,
// painted by the real engine. Only the stamps need the Rust library.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _width = 200;
const _height = 120;

/// The pixels of a picture, colours not multiplied by their alpha.
class _Pixels {
  _Pixels(this.rgba);
  final Uint8List rgba;

  int alpha(int x, int y) => rgba[(y * _width + x) * 4 + 3];

  /// Red, green and blue of one pixel, as 0xRRGGBB.
  int rgb(int x, int y) {
    final offset = (y * _width + x) * 4;
    return (rgba[offset] << 16) | (rgba[offset + 1] << 8) | rgba[offset + 2];
  }

  /// Number of pixels that are painted at all.
  int get inked {
    var count = 0;
    for (var offset = 3; offset < rgba.length; offset += 4) {
      if (rgba[offset] != 0) count++;
    }
    return count;
  }

  /// The smallest rectangle around what is painted in the rows from [top]
  /// to [bottom], or null where nothing is.
  Rect? bounds({int top = 0, int bottom = _height}) {
    var left = _width;
    var right = -1;
    var first = _height;
    var last = -1;
    for (var y = top; y < bottom; y++) {
      for (var x = 0; x < _width; x++) {
        if (alpha(x, y) == 0) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < first) first = y;
        if (y > last) last = y;
      }
    }
    return right < 0
        ? null
        : Rect.fromLTRB(
            left.toDouble(),
            first.toDouble(),
            right + 1.0,
            last + 1.0,
          );
  }

  /// Whether every pixel fully painted here is painted in [other] too, at
  /// [atLeast] or more. Not 255: along an edge that both follow the engine
  /// rounds a pixel barely touched to 255 under a round end and to 253
  /// beside it.
  bool isWithin(_Pixels other, {int atLeast = 250}) {
    for (var offset = 3; offset < rgba.length; offset += 4) {
      if (rgba[offset] == 255 && other.rgba[offset] < atLeast) return false;
    }
    return true;
  }
}

Future<_Pixels> _render(void Function(Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final saved = canvas.getSaveCount();
  draw(canvas);
  // Whatever was painted, the canvas is handed back as it was received.
  expect(canvas.getSaveCount(), saved);
  final picture = recorder.endRecording();
  final image = await picture.toImage(_width, _height);
  try {
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    return _Pixels(
      Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<_Pixels> _at(RenderedElement element, double progress) =>
    _render((canvas) => element.paintProgress(canvas, progress));

Future<_Pixels> _whole(RenderedElement element) => _render(element.paint);

RenderedElement _element(
  List<DocumentPoint> points, {
  int rgb = 0x224466,
  double width = 10,
  VectorKind kind = VectorKind.stroke,
  int? fillRgb,
  String? text,
  int? stamp,
}) => RenderedElement(
  StrokeData(
    points,
    rgb,
    width,
    kind: kind,
    fillRgb: fillRgb,
    text: text,
    stamp: stamp,
  ),
);

final _trait = _element(const [DocumentPoint(20, 60), DocumentPoint(180, 60)]);
final _corner = _element(const [
  DocumentPoint(20, 100),
  DocumentPoint(100, 100),
  DocumentPoint(100, 20),
]);
final _dot = _element(const [DocumentPoint(100, 60)], rgb: 0xaa0000, width: 40);
final _still = _element(const [
  DocumentPoint(100, 60),
  DocumentPoint(100, 60),
  DocumentPoint(100, 60),
], width: 40);
final _line = _element(
  const [DocumentPoint(180, 20), DocumentPoint(20, 100)],
  width: 8,
  kind: VectorKind.line,
);
final _box = _element(
  const [DocumentPoint(40, 20), DocumentPoint(160, 100)],
  rgb: 0x112233,
  width: 6,
  kind: VectorKind.rectangle,
);
final _filledBox = _element(
  const [DocumentPoint(40, 20), DocumentPoint(160, 100)],
  rgb: 0x112233,
  width: 6,
  kind: VectorKind.rectangle,
  fillRgb: 0x00cc44,
);
final _oval = _element(
  const [DocumentPoint(40, 20), DocumentPoint(160, 100)],
  rgb: 0x112233,
  width: 6,
  kind: VectorKind.ellipse,
);
final _filledOval = _element(
  const [DocumentPoint(160, 100), DocumentPoint(40, 20)],
  rgb: 0x112233,
  width: 6,
  kind: VectorKind.ellipse,
  fillRgb: 0xeebf4e,
);
// With the font of the tests every letter is a square as wide as the size.
final _word = _element(
  const [DocumentPoint(20, 20), DocumentPoint(100, 68)],
  rgb: 0x6a4f99,
  width: 40,
  kind: VectorKind.text,
  text: 'OO',
);
final _lines = _element(
  const [DocumentPoint(20, 20), DocumentPoint(100, 68)],
  rgb: 0x6a4f99,
  width: 20,
  kind: VectorKind.text,
  text: 'OO\nOOOO',
);

RenderedElement _stamp() => _element(
  const [DocumentPoint(60, 20), DocumentPoint(140, 100)],
  rgb: 0xd75e56,
  width: 1,
  kind: VectorKind.stamp,
  stamp: 0,
);

final _withoutLibrary = <String, RenderedElement>{
  'trait': _trait,
  'trait with a corner': _corner,
  'dot': _dot,
  'trait that goes nowhere': _still,
  'line': _line,
  'rectangle': _box,
  'filled rectangle': _filledBox,
  'oval': _oval,
  'filled oval': _filledOval,
  'text': _word,
  'text of two lines': _lines,
};

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  Future<void> expectEnds(String name, RenderedElement element) async {
    final empty = await _render((_) {});
    expect(empty.inked, 0);
    final whole = await _whole(element);
    expect(whole.inked, greaterThan(300), reason: '$name is visible');
    // Nothing before the element starts, whatever « before » is.
    for (final progress in [0.0, -0.0, -1.0, double.negativeInfinity]) {
      expect(
        (await _at(element, progress)).rgba,
        empty.rgba,
        reason: '$name at $progress',
      );
    }
    expect(
      (await _at(element, double.nan)).rgba,
      empty.rgba,
      reason: '$name at a progress that is not a number',
    );
    // From 1 on, the very pixels of the sheet.
    for (final progress in [1.0, 1.0000001, 2.5, double.infinity]) {
      expect(
        (await _at(element, progress)).rgba,
        whole.rgba,
        reason: '$name at $progress',
      );
    }
    // And the same without the bounce of the stamps.
    for (final progress in [0.0, 1.0]) {
      expect(
        (await _render(
          (canvas) => element.paintProgress(canvas, progress, overshoot: false),
        )).rgba,
        progress == 0 ? empty.rgba : whole.rgba,
        reason: '$name at $progress, without a bounce',
      );
    }
  }

  testWidgets('at 0 nothing is painted; at 1 exactly what the sheet shows', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final MapEntry(key: name, value: element)
          in _withoutLibrary.entries) {
        await expectEnds(name, element);
      }
    });
  });

  testWidgets('a stamp too is nothing at 0 and itself at 1', (tester) async {
    await tester.runAsync(() => expectEnds('stamp', _stamp()));
  }, skip: !available);

  testWidgets('on the way, what is drawn stays and more comes', (tester) async {
    await tester.runAsync(() async {
      for (final name in [
        'trait',
        'trait with a corner',
        'dot',
        'trait that goes nowhere',
        'line',
        'rectangle',
        'oval',
        'text',
        'text of two lines',
      ]) {
        final element = _withoutLibrary[name]!;
        _Pixels? before;
        for (final progress in [.05, .2, .35, .5, .65, .8, .95, 1.0]) {
          final now = await _at(element, progress);
          if (before != null) {
            expect(
              now.inked,
              greaterThan(before.inked),
              reason: '$name grows up to $progress',
            );
            expect(
              // The engine draws a curve within a quarter of a pixel, and
              // not the same quarter for a piece of an oval as for more of
              // it: along its edge a pixel may lose a part of its paint.
              before.isWithin(now, atLeast: name == 'oval' ? 160 : 250),
              isTrue,
              reason: '$name keeps at $progress what was drawn before',
            );
          }
          before = now;
        }
      }
    });
  });

  testWidgets('a trait at half its time is drawn up to half its length', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // From 20 to 180 along y = 60, ten wide: half of it ends at 100.
      final half = await _at(_trait, .5);
      for (final x in [20, 40, 60, 80, 99]) {
        expect(half.alpha(x, 60), 255, reason: 'inked at $x');
        expect(half.alpha(x, 56), 255, reason: 'the whole width at $x');
        expect(half.alpha(x, 63), 255, reason: 'the whole width at $x');
        expect(half.rgb(x, 60), 0x224466);
        expect(half.alpha(x, 52), 0, reason: 'nothing above the trait');
        expect(half.alpha(x, 67), 0, reason: 'nothing under the trait');
      }
      // The round tip of the brush goes half a width further, no more.
      expect(half.alpha(102, 60), 255);
      expect(half.alpha(104, 60), greaterThan(0));
      for (final x in [106, 110, 140, 179, 184]) {
        expect(half.alpha(x, 60), 0, reason: 'not yet at $x');
      }
      // The trait starts with the same round end as on the sheet.
      expect(half.alpha(17, 60), 255);
      expect(half.alpha(14, 60), 0);
      expect(half.bounds(), const Rect.fromLTRB(15, 55, 105, 65));

      final quarter = await _at(_trait, .25);
      expect(quarter.bounds(), const Rect.fromLTRB(15, 55, 65, 65));
      expect(
        (await _at(_trait, .75)).bounds(),
        const Rect.fromLTRB(15, 55, 145, 65),
      );
      expect(
        (await _whole(_trait)).bounds(),
        const Rect.fromLTRB(15, 55, 185, 65),
      );
    });
  });

  testWidgets('a trait follows its corners: its length is the way it goes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // 80 to the right, then 80 up.
      final half = await _at(_corner, .5);
      expect(half.alpha(60, 100), 255);
      expect(half.alpha(98, 100), 255);
      expect(half.alpha(100, 90), 0, reason: 'the way up is not started');
      expect(half.alpha(100, 60), 0);
      final later = await _at(_corner, .75);
      expect(later.alpha(60, 100), 255);
      expect(later.alpha(100, 80), 255);
      expect(later.alpha(100, 62), 255);
      expect(later.alpha(100, 50), 0);
      expect(later.alpha(100, 22), 0);
    });
  });

  testWidgets('a line grows from its first point', (tester) async {
    await tester.runAsync(() async {
      // First point top right, last point bottom left.
      final early = await _at(_line, .25);
      expect(early.alpha(176, 22), 255);
      expect(early.alpha(150, 35), 255);
      expect(early.alpha(100, 60), 0);
      expect(early.alpha(24, 98), 0);
      final late = await _at(_line, .6);
      expect(late.alpha(176, 22), 255);
      expect(late.alpha(100, 60), 255);
      expect(late.alpha(60, 80), 0);
      expect(late.alpha(24, 98), 0);
    });
  });

  testWidgets('a dot grows from its centre', (tester) async {
    await tester.runAsync(() async {
      for (final (name, element) in [
        ('dot', _dot),
        ('trait that goes nowhere', _still),
      ]) {
        // Forty wide in the end: a radius of 5, 10, 15, then 20.
        for (final (progress, radius) in [(.25, 5), (.5, 10), (.75, 15)]) {
          final pixels = await _at(element, progress);
          final where = '$name at $progress';
          expect(pixels.alpha(100, 60), 255, reason: where);
          expect(pixels.alpha(100 + radius - 3, 60), 255, reason: where);
          expect(pixels.alpha(100, 60 - radius + 2), 255, reason: where);
          expect(pixels.alpha(100 + radius + 2, 60), 0, reason: where);
          expect(pixels.alpha(100, 60 + radius + 2), 0, reason: where);
          final bounds = pixels.bounds()!;
          expect(bounds.center.dx, closeTo(100, .51), reason: where);
          expect(bounds.center.dy, closeTo(60, .51), reason: where);
          expect(bounds.width, closeTo(radius * 2, 2.1), reason: where);
          expect(bounds.height, closeTo(radius * 2, 2.1), reason: where);
        }
      }
      expect((await _at(_dot, .5)).rgb(100, 60), 0xaa0000);
    });
  });

  testWidgets(
    'a filled shape gets its outline first, then its inside appears',
    (tester) async {
      await tester.runAsync(() async {
        // The outline of the rectangle starts at its top left corner and
        // goes round by the right: 120, 80, 120 and 80 long.
        final half = await _at(_filledBox, .35);
        expect(half.alpha(100, 20), 255, reason: 'top side');
        expect(half.rgb(100, 20), 0x112233);
        expect(half.alpha(160, 60), 255, reason: 'right side');
        expect(half.alpha(100, 100), 0, reason: 'bottom side to come');
        expect(half.alpha(40, 60), 0, reason: 'left side to come');
        expect(half.alpha(100, 60), 0, reason: 'no inside yet');

        // At seven tenths the outline is closed and the inside starts.
        for (final progress in [.699, .7]) {
          final closed = await _at(_filledBox, progress);
          for (final (x, y) in [(100, 20), (160, 60), (100, 100), (40, 60)]) {
            expect(closed.alpha(x, y), 255, reason: '$x, $y at $progress');
            expect(closed.rgb(x, y), 0x112233);
          }
          expect(closed.alpha(40, 24), 255, reason: 'end of the outline');
          expect(closed.alpha(100, 60), 0, reason: 'inside at $progress');
        }

        // The inside comes evenly through the rest of the time.
        for (final (progress, alpha) in [(.76, 51), (.85, 128), (.94, 204)]) {
          final fading = await _at(_filledBox, progress);
          expect(
            fading.alpha(100, 60),
            closeTo(alpha, 2),
            reason: 'inside at $progress',
          );
          expect(fading.alpha(70, 40), fading.alpha(130, 80));
          // The colour of the inside, as far as so little of it tells.
          expect((fading.rgb(100, 60) >> 16) & 0xff, lessThan(8));
          expect((fading.rgb(100, 60) >> 8) & 0xff, closeTo(0xcc, 6));
          expect(fading.rgb(100, 60) & 0xff, closeTo(0x44, 6));
          // The outline stays whole, and over the inside.
          for (final (x, y) in [(100, 20), (160, 60), (100, 100), (40, 60)]) {
            expect(fading.alpha(x, y), 255);
            expect(fading.rgb(x, y), 0x112233);
          }
        }
        final whole = await _whole(_filledBox);
        expect(whole.alpha(100, 60), 255);
        expect(whole.rgb(100, 60), 0x00cc44);

        // The oval the same: its outline starts on the right and goes
        // round by the bottom.
        final ovalHalf = await _at(_filledOval, .35);
        expect(ovalHalf.alpha(100, 100), 255, reason: 'bottom of the oval');
        expect(ovalHalf.alpha(100, 20), 0, reason: 'top of the oval to come');
        expect(ovalHalf.alpha(100, 60), 0);
        final ovalFading = await _at(_filledOval, .85);
        expect(ovalFading.alpha(100, 20), 255);
        expect(ovalFading.alpha(100, 60), closeTo(128, 2));
        // Outside the oval, in the corner of its box, nothing.
        expect(ovalFading.alpha(46, 24), 0);
      });
    },
  );

  testWidgets('a shape without an inside takes all its time for its outline', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final half = await _at(_box, .5);
      expect(half.alpha(100, 20), 255, reason: 'top side');
      expect(half.alpha(160, 60), 255, reason: 'right side');
      expect(half.alpha(100, 100), 0, reason: 'bottom side to come');
      expect(half.alpha(40, 60), 0, reason: 'left side to come');
      // At 0.85 the bottom is done and the left side has started upwards.
      final late = await _at(_box, .85);
      expect(late.alpha(100, 100), 255);
      expect(late.alpha(40, 92), 255);
      expect(late.alpha(40, 60), 0);
      expect(late.alpha(40, 30), 0);
      for (final progress in [.5, .85, 1.0]) {
        expect((await _at(_box, progress)).alpha(100, 60), 0);
      }
      final ovalHalf = await _at(_oval, .5);
      expect(ovalHalf.alpha(100, 100), 255);
      expect(ovalHalf.alpha(100, 20), 0);
      expect(ovalHalf.alpha(100, 60), 0);
    });
  });

  testWidgets('a text is written from the left, line after line', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Two letters of forty, from 20 to 100.
      final whole = (await _whole(_word)).bounds()!;
      expect(whole.left, closeTo(20, 1));
      expect(whole.right, closeTo(100, 1));
      for (final (progress, right) in [(.25, 40), (.5, 60), (.75, 80)]) {
        final written = await _at(_word, progress);
        final bounds = written.bounds()!;
        expect(bounds.left, whole.left, reason: 'at $progress');
        expect(bounds.right, closeTo(right, 1), reason: 'at $progress');
        // Each letter at its full height as soon as it is there.
        expect(bounds.top, whole.top, reason: 'at $progress');
        expect(bounds.bottom, whole.bottom, reason: 'at $progress');
        expect(written.rgb(24, whole.center.dy.round()), 0x6a4f99);
      }

      // Two letters of twenty, then four under them: each line 24 high.
      // The second line is twice the first: a third of the time, then two.
      // The rows where the two lines meet are left out of both looks.
      final all = await _whole(_lines);
      final first = all.bounds(bottom: 43)!;
      final second = all.bounds(top: 46)!;
      expect(first.right, closeTo(60, 1));
      expect(second.right, closeTo(100, 1));

      final start = await _at(_lines, 1 / 6);
      expect(start.bounds(bottom: 43)!.right, closeTo(40, 1));
      expect(start.bounds(top: 44), isNull, reason: 'second line to come');

      final middle = await _at(_lines, .5);
      expect(middle.bounds(bottom: 43), first, reason: 'first line whole');
      final begun = middle.bounds(top: 46)!;
      expect(begun.left, second.left);
      expect(begun.right, closeTo(40, 1));
      expect(begun.top, second.top);
      expect(begun.bottom, second.bottom);

      final late = await _at(_lines, .75);
      expect(late.bounds(bottom: 43), first);
      expect(late.bounds(top: 46)!.right, closeTo(70, 1));
    });
  });

  testWidgets('a stamp grows from the centre of its box, with a small bounce', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final stamp = _stamp();
      final whole = (await _whole(stamp)).bounds()!;
      expect(whole.center.dx, closeTo(100, 3));
      expect(whole.center.dy, closeTo(60, 3));
      expect(whole.width, greaterThan(60));

      // Early it is small, around the centre of its box.
      final early = (await _at(stamp, .15)).bounds()!;
      expect(early.width, closeTo(whole.width * .57, 3));
      expect(early.height, closeTo(whole.height * .57, 3));
      expect((early.center - const Offset(100, 60)).distance, lessThan(4));
      expect(
        const Rect.fromLTRB(70, 30, 130, 90).contains(early.topLeft),
        isTrue,
      );
      expect(
        const Rect.fromLTRB(70, 30, 130, 90).contains(early.bottomRight),
        isTrue,
      );

      // On the way it is a little larger than it will be: the bounce.
      final bounce = (await _at(stamp, .6)).bounds()!;
      expect(bounce.width, greaterThan(whole.width + 4));
      expect(bounce.height, greaterThan(whole.height + 4));
      expect(bounce.width, lessThan(whole.width * 1.12 + 2));
      expect((bounce.center - whole.center).distance, lessThan(3));

      // Without the bounce it only grows, never past its size.
      var before = Rect.zero;
      for (final progress in [.1, .3, .5, .7, .85, .97]) {
        final calm = (await _render(
          (canvas) => stamp.paintProgress(canvas, progress, overshoot: false),
        )).bounds()!;
        final where = 'without a bounce at $progress';
        expect(
          calm.width,
          progress < .8
              ? greaterThan(before.width)
              : greaterThanOrEqualTo(before.width),
          reason: where,
        );
        expect(calm.width, lessThanOrEqualTo(whole.width), reason: where);
        expect(calm.height, lessThanOrEqualTo(whole.height), reason: where);
        expect((calm.center - whole.center).distance, lessThan(3));
        before = calm;
      }
      // Fast first, then slower: seven eighths of its size at half its time.
      final halfway = (await _render(
        (canvas) => stamp.paintProgress(canvas, .5, overshoot: false),
      )).bounds()!;
      expect(halfway.width, closeTo(whole.width * .875, 3));
      expect(halfway.height, closeTo(whole.height * .875, 3));
      // The colour of the stamp is its own all along.
      final colours = <int>{};
      final half = await _at(stamp, .5);
      for (var y = 0; y < _height; y++) {
        for (var x = 0; x < _width; x++) {
          if (half.alpha(x, y) == 255) colours.add(half.rgb(x, y));
        }
      }
      expect(colours, contains(0xd75e56));
    });
  }, skip: !available);

  testWidgets(
    'a long trait is measured once, not for every frame of its film',
    (tester) async {
      // Fifty thousand points: measuring them takes the engine far longer
      // than cutting a short piece of what is already measured.
      final points = [
        for (var index = 0; index < 50000; index++)
          DocumentPoint(10 + index * .0036, 60 + (index % 2) * 2),
      ];
      final long = _element(points, width: 4);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final watch = Stopwatch()..start();
      long.paintProgress(canvas, .0001);
      final first = watch.elapsedMicroseconds;
      watch
        ..reset()
        ..start();
      const frames = 200;
      for (var frame = 1; frame <= frames; frame++) {
        long.paintProgress(canvas, .0001 + frame * .000001);
      }
      final each = watch.elapsedMicroseconds / frames;
      recorder.endRecording().dispose();
      // The first frame measured the trait; each of the others costs a
      // small part of that. A frame that measured again would cost as much.
      expect(
        each,
        lessThan(first / 4),
        reason: 'first frame $first µs, then $each µs a frame',
      );
    },
  );
}
