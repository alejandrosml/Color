// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/draft_stroke.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _side = 300;

/// A trait that turns often, crosses itself and comes back on itself:
/// [count] points inside the square.
List<DocumentPoint> _wander(int count) {
  final random = math.Random(31);
  var x = 150.0, y = 150.0, heading = 0.0;
  return [
    for (var i = 0; i < count; i++)
      () {
        heading += (random.nextDouble() - 0.5) * 1.6;
        x = (x + 3 * math.cos(heading)).clamp(12.0, _side - 12.0);
        y = (y + 3 * math.sin(heading)).clamp(12.0, _side - 12.0);
        return DocumentPoint(x, y);
      }(),
  ];
}

Paint _paint(double width) => Paint()
  ..color = const Color(0xff2a6fdb)
  ..isAntiAlias = true
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Future<Uint8List> _render(
  WidgetTester tester,
  void Function(Canvas canvas) draw,
) async => (await tester.runAsync(() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(_side, _side);
  picture.dispose();
  try {
    return (await image.toByteData())!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}))!;

void main() {
  test('a trait is cut in pieces of 256 points that share their ends', () {
    int piecesOf(int points) =>
        DraftStroke.through(_wander(points)).pieces.length;
    expect(piecesOf(1), 1);
    expect(piecesOf(2), 1);
    expect(piecesOf(256), 1);
    expect(piecesOf(257), 2);
    expect(piecesOf(511), 2);
    expect(piecesOf(512), 3);
    // Each piece after the first adds 255 points of its own.
    expect(piecesOf(100000), 1 + ((100000 - 256) / 255).ceil());

    final points = _wander(1000);
    final pieces = DraftStroke.through(points).pieces.toList();
    for (var index = 0; index < pieces.length; index++) {
      final metrics = pieces[index].computeMetrics().toList();
      expect(metrics, hasLength(1), reason: 'one line per piece');
      final start = metrics.single.getTangentForOffset(0)!.position;
      final first = points[index * (DraftStroke.pieceLength - 1)];
      // A path keeps its coordinates in single precision.
      expect(start.dx, closeTo(first.x, 1e-3), reason: 'piece $index');
      expect(start.dy, closeTo(first.y, 1e-3), reason: 'piece $index');
    }
  });

  testWidgets('the pieces paint what one path paints, edge pixels aside', (
    tester,
  ) async {
    for (final (count, width) in [(2000, 10.0), (700, 1.0), (300, 40.0)]) {
      final points = _wander(count);
      final whole = Path()..moveTo(points.first.x, points.first.y);
      for (final point in points.skip(1)) {
        whole.lineTo(point.x, point.y);
      }
      final once = await _render(
        tester,
        (canvas) => canvas.drawPath(whole, _paint(width)),
      );
      final inPieces = await _render(tester, (canvas) {
        for (final piece in DraftStroke.through(points).pieces) {
          canvas.drawPath(piece, _paint(width));
        }
      });
      // The same trait: only anti-aliased edge pixels may differ, where two
      // pieces overlap (where they meet, or where the trait crosses
      // itself). Painted twice, a half-covered pixel is a shade more opaque
      // than one painted once by the whole path, or a shade less.
      const ink = [0x2a, 0x6f, 0xdb, 0xff];
      bool full(Uint8List rgba, int pixel) =>
          List.generate(4, (i) => rgba[pixel * 4 + i]).toString() ==
          ink.toString();
      var touched = 0, different = 0, largest = 0, fullInOne = 0, inked = 0;
      for (var pixel = 0; pixel < _side * _side; pixel++) {
        if (full(once, pixel) != full(inPieces, pixel)) fullInOne++;
        var white = true;
        var gap = 0;
        for (var channel = 0; channel < 4; channel++) {
          final offset = pixel * 4 + channel;
          if (once[offset] != 0xff) white = false;
          gap = math.max(gap, (once[offset] - inPieces[offset]).abs());
        }
        if (!white) touched++;
        if (full(once, pixel)) inked++;
        if (gap > 0) different++;
        largest = math.max(largest, gap);
      }
      expect(touched, greaterThan(1000));
      expect(
        different,
        lessThan(touched ~/ 25),
        reason: '$count points, width $width: $different of $touched',
      );
      expect(largest, lessThan(128), reason: '$count points, width $width');
      // Measured on 31 October 2026: 2000 points of width 10, 494 edge
      // pixels of 35 853 differ, 51 of 32 134 full ones, by 65 / 255 at most.
      expect(fullInOne, lessThan(inked ~/ 200 + 1), reason: '$count, $width');
    }
  });
}
