// SPDX-License-Identifier: MIT
// The pile of a film: which elements lie under which, and what of it can be
// kept from one frame to the next. No Rust library is needed.
import 'dart:math' as math;

import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/replay.dart';
import 'package:edupaint_flutter_study/replay_dialog.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

RenderedElement _dot(double x) =>
    RenderedElement(StrokeData([DocumentPoint(x, 5)], 0, 4));

void main() {
  test('a drawing made on one layer is piled in the order it was made', () {
    final order = ReplayOrder([0, 1, 2, 3, 4]);
    expect(order.length, 5);
    for (var count = 0; count <= 5; count++) {
      // Everything revealed is settled: nothing will come under it.
      expect(order.settledAt(count), count);
      expect(order.reachAt(count), count);
      expect(order.restingAt(count), count);
    }
    expect(
      [for (var rank = 0; rank < 5; rank++) order.elementAt(rank)],
      [0, 1, 2, 3, 4],
    );
  });

  test('what is made later under the rest keeps the pile open', () {
    // Two layers. The child drew a, b on the upper one, then c, d on the
    // lower one, then e on the upper one again: made in the order
    // a b c d e, piled c d a b e.
    final order = ReplayOrder([2, 3, 0, 1, 4]);
    expect(
      [for (var rank = 0; rank < 5; rank++) order.elementAt(rank)],
      [2, 3, 0, 1, 4],
    );
    // While c and d are to come, a and b cannot be kept: they go over them.
    expect(order.settledAt(0), 0);
    expect(order.settledAt(1), 0);
    expect(order.settledAt(2), 0);
    // c is there: one place is settled, d still goes over c and under a.
    expect(order.settledAt(3), 1);
    // d is there: c d a b are in their places for good.
    expect(order.settledAt(4), 4);
    expect(order.settledAt(5), 5);
    // The places taken: a is third in the pile as soon as it is there.
    expect(
      [for (var count = 0; count <= 5; count++) order.reachAt(count)],
      [0, 3, 4, 4, 4, 5],
    );
  });

  test('a pile made upside down settles with its last element only', () {
    final order = ReplayOrder([3, 2, 1, 0]);
    expect(
      [for (var count = 0; count <= 4; count++) order.settledAt(count)],
      [0, 0, 0, 0, 4],
    );
    expect(
      [for (var count = 0; count <= 4; count++) order.reachAt(count)],
      [0, 4, 4, 4, 4],
    );
    expect(
      [for (var rank = 0; rank < 4; rank++) order.elementAt(rank)],
      [3, 2, 1, 0],
    );
  });

  test('an empty pile is a pile', () {
    final order = ReplayOrder(const []);
    expect(order.length, 0);
    expect(order.settledAt(0), 0);
    expect(order.reachAt(0), 0);
    expect(order.restingAt(0), 0);
    expect(() => order.settledAt(1), throwsRangeError);
    expect(() => order.elementAt(0), throwsRangeError);
  });

  test('places that are not those of a pile are refused', () {
    for (final ranks in [
      [0, 0],
      [1, 1],
      [0, 2],
      [1, 2],
      [-1, 0],
      [0, 1, 1],
      [3],
    ]) {
      expect(() => ReplayOrder(ranks), throwsArgumentError, reason: '$ranks');
    }
  });

  test('any pile: the settled part is what a plain look at it finds', () {
    final random = math.Random(42);
    for (var round = 0; round < 60; round++) {
      final count = 1 + random.nextInt(40);
      final ranks = List.generate(count, (index) => index);
      // Some piles nearly in order, as layers make them, some at random.
      if (round.isEven) {
        ranks.shuffle(random);
      } else {
        final cut = random.nextInt(count);
        final upper = ranks.sublist(0, cut);
        ranks
          ..removeRange(0, cut)
          ..addAll(upper);
      }
      final order = ReplayOrder(ranks);
      for (var rank = 0; rank < count; rank++) {
        expect(ranks[order.elementAt(rank)], rank);
      }
      var before = 0;
      for (var revealed = 0; revealed <= count; revealed++) {
        // The places all taken, from the bottom, by revealed elements.
        final taken = {for (final rank in ranks.take(revealed)) rank};
        var settled = 0;
        while (taken.contains(settled)) {
          settled++;
        }
        // Not one more: the element at the next place is still to come, or
        // an element still to come goes under what is there.
        final lowestToCome = ranks.skip(revealed).fold(count, math.min);
        settled = math.min(settled, lowestToCome);
        expect(order.settledAt(revealed), settled, reason: '$ranks');
        expect(
          order.reachAt(revealed),
          ranks.take(revealed).fold(-1, math.max) + 1,
        );
        // What is kept never holds more than what is settled, never
        // shrinks while the film goes on, and is everything at the end.
        final resting = order.restingAt(revealed);
        expect(resting, lessThanOrEqualTo(order.settledAt(revealed)));
        expect(resting, greaterThanOrEqualTo(before));
        before = resting;
      }
      expect(order.restingAt(count), count);
    }
  });

  test('the kept picture follows a small drawing element by element', () {
    final order = ReplayOrder(List.generate(12, (index) => index));
    expect(
      [for (var count = 0; count <= 12; count++) order.restingAt(count)],
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    );
  });

  test('the kept picture of a big drawing is renewed by steps', () {
    const count = 10000;
    final order = ReplayOrder(List.generate(count, (index) => index));
    final values = <int>{};
    var before = 0;
    var widest = 0.0;
    for (var finished = 0; finished <= count; finished++) {
      final resting = order.restingAt(finished);
      expect(resting, lessThanOrEqualTo(finished));
      expect(resting, greaterThanOrEqualTo(before));
      before = resting;
      values.add(resting);
      // What is complete and not kept is painted for every frame: never
      // more than an eighth of what is kept, beyond a few elements.
      if (finished - resting > 2) {
        widest = math.max(widest, (finished - resting) / resting);
      }
    }
    expect(order.restingAt(count), count);
    // Ten thousand elements, and the picture is painted afresh only some
    // seventy times: each time once for many frames of the film.
    expect(values.length, inInclusiveRange(40, 90));
    expect(widest, lessThanOrEqualTo(1 / 8));
    expect(values.take(20).toList(), [
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      18,
      20,
      22,
    ]);
  });

  group('the scene of a document', () {
    final all = [for (var index = 0; index < 6; index++) _dot(index * 10)];

    test('is revealed as it was made and piled as its layers are', () {
      // The lower layer holds the elements 3 and 4, the upper one 0 and 2;
      // 1 and 5 are on a hidden layer.
      final scene = ReplayScene.fromDocumentOrder(
        all: all,
        paintOrder: const [3, 4, 0, 2],
        width: 1200,
        height: 800,
        paperRgb: 0xfff4d6,
        background: null,
      );
      expect(scene.width, 1200);
      expect(scene.height, 800);
      expect(scene.paperRgb, 0xfff4d6);
      expect(scene.background, isNull);
      expect(scene.elements, hasLength(4));
      for (final (position, index) in [0, 2, 3, 4].indexed) {
        expect(identical(scene.elements[position], all[index]), isTrue);
      }
      expect(scene.paintRank, [2, 3, 0, 1]);
      // What the dialog makes of it.
      final order = ReplayOrder(scene.paintRank);
      expect(
        [for (var rank = 0; rank < 4; rank++) order.elementAt(rank)],
        [2, 3, 0, 1],
      );
      // The scene is a picture of that moment: it cannot be changed.
      expect(() => scene.elements.clear(), throwsUnsupportedError);
      expect(() => scene.paintRank[0] = 0, throwsUnsupportedError);
    });

    test('of one layer is piled as it is revealed', () {
      final scene = ReplayScene.fromDocumentOrder(
        all: all,
        paintOrder: const [0, 1, 2, 3, 4, 5],
        width: 800,
        height: 1200,
        paperRgb: 0xffffff,
        background: null,
      );
      expect(scene.elements, all);
      expect(scene.paintRank, [0, 1, 2, 3, 4, 5]);
    });

    test('keeps the page of a colouring page on the sheet from the start', () {
      // A page: its zones (layer 1) under the drawing of the child (layer
      // 0), its lines (layer 2) over it. The child drew 4 and 5; the
      // zones are 0 and 1, the lines 2 and 3; a hidden page layer holds 6.
      RenderedElement on(int layer, double x) => RenderedElement(
        StrokeData([DocumentPoint(x, 5)], 0, 4, layer: layer),
      );
      final page = [
        on(1, 0),
        on(1, 10),
        on(2, 20),
        on(2, 30),
        on(0, 40),
        on(0, 50),
        on(4, 60),
      ];
      final scene = ReplayScene.fromDocumentOrder(
        all: page,
        paintOrder: const [0, 1, 4, 5, 2, 3],
        width: 1200,
        height: 800,
        paperRgb: 0xffffff,
        background: null,
        fixedLayers: const {1, 2, 4},
      );
      // The page first, from the bottom of the pile to its top, then what
      // the film redraws, as it was made.
      expect(scene.fixedCount, 4);
      expect(scene.nothingToRedraw, isFalse);
      for (final (position, index) in [0, 1, 2, 3, 4, 5].indexed) {
        expect(identical(scene.elements[position], page[index]), isTrue);
      }
      expect(scene.paintRank, [0, 1, 4, 5, 2, 3]);
      // The zones rest under everything to come; the lines are above it.
      final order = ReplayOrder(scene.paintRank);
      expect(order.settledAt(4), 2);
      expect(order.reachAt(4), 6);
      expect(order.settledAt(6), 6);

      // Nothing drawn yet: the page alone, nothing to redraw.
      final untouched = ReplayScene.fromDocumentOrder(
        all: page,
        paintOrder: const [0, 1, 2, 3],
        width: 1200,
        height: 800,
        paperRgb: 0xffffff,
        background: null,
        fixedLayers: const {1, 2, 4},
      );
      expect(untouched.fixedCount, 4);
      expect(untouched.nothingToRedraw, isTrue);
      // Without locked layers, nothing is fixed.
      final plain = ReplayScene.fromDocumentOrder(
        all: page,
        paintOrder: const [0, 1, 4, 5, 2, 3],
        width: 1200,
        height: 800,
        paperRgb: 0xffffff,
        background: null,
      );
      expect(plain.fixedCount, 0);
      expect(plain.paintRank, [0, 1, 4, 5, 2, 3]);
    });

    test('colours the zones of the page that the paint pot coloured, in turn, before the drawing', () {
      RenderedElement zone(int layer, int fillRgb, double x) => RenderedElement(
        StrokeData(
          [DocumentPoint(x, 5), DocumentPoint(x + 8, 15)],
          0xffffff,
          .1,
          kind: VectorKind.rectangle,
          fillRgb: fillRgb,
          layer: layer,
        ),
      );
      RenderedElement dot(int layer, double x) => RenderedElement(
        StrokeData([DocumentPoint(x, 5)], 0, 4, layer: layer),
      );
      // The zones 0 (white), 1 and 4 (coloured) under the drawing 3, the line
      // 2 over it; the zone 5, coloured, on a hidden layer of the page.
      final all = [
        zone(1, 0xffffff, 0),
        zone(1, 0xeebf4e, 10),
        dot(2, 20),
        dot(0, 30),
        zone(1, 0x9385bc, 40),
        zone(4, 0xd75e56, 50),
      ];
      final scene = ReplayScene.fromDocumentOrder(
        all: all,
        paintOrder: const [0, 1, 4, 3, 2],
        width: 1200,
        height: 800,
        paperRgb: 0xffffff,
        background: null,
        fixedLayers: const {1, 2, 4},
      );
      // The untouched page, then the coloured zones as they were made, then
      // the drawing.
      expect(scene.fixedCount, 2);
      expect(scene.recolouredCount, 2);
      for (final (position, index) in [0, 2, 1, 4, 3].indexed) {
        expect(identical(scene.elements[position], all[index]), isTrue);
      }
      expect(scene.paintRank, [0, 4, 1, 2, 3]);
      expect(
        [for (var i = 0; i < 5; i++) scene.isRecoloured(i)],
        [false, false, true, true, false],
      );
      expect(scene.nothingToRedraw, isFalse);
      // A page whose only coloured zone is hidden has nothing to show.
      final hidden = ReplayScene.fromDocumentOrder(
        all: all,
        paintOrder: const [0, 2],
        width: 1200,
        height: 800,
        paperRgb: 0xffffff,
        background: null,
        fixedLayers: const {1, 2, 4},
      );
      expect(hidden.recolouredCount, 0);
      expect(hidden.nothingToRedraw, isTrue);
      // Coloured zones alone are a film.
      final coloured = ReplayScene.fromDocumentOrder(
        all: all,
        paintOrder: const [0, 1, 2],
        width: 1200,
        height: 800,
        paperRgb: 0xffffff,
        background: null,
        fixedLayers: const {1, 2, 4},
      );
      expect(coloured.fixedCount, 2);
      expect(coloured.recolouredCount, 1);
      expect(coloured.nothingToRedraw, isFalse);
    });

    test('with nothing to see is an empty film', () {
      for (final elements in [all, const <RenderedElement>[]]) {
        final scene = ReplayScene.fromDocumentOrder(
          all: elements,
          paintOrder: const [],
          width: 1200,
          height: 800,
          paperRgb: 0xffffff,
          background: null,
        );
        expect(scene.elements, isEmpty);
        expect(scene.paintRank, isEmpty);
      }
    });

    test('is refused when its order names an element twice or none', () {
      for (final paintOrder in [
        [0, 0],
        [0, 6],
        [-1],
        [2, 1, 2],
      ]) {
        expect(
          () => ReplayScene.fromDocumentOrder(
            all: all,
            paintOrder: paintOrder,
            width: 1200,
            height: 800,
            paperRgb: 0xffffff,
            background: null,
          ),
          throwsArgumentError,
          reason: '$paintOrder',
        );
      }
    });
  });
}
