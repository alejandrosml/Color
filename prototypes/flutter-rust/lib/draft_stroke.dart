// SPDX-License-Identifier: MIT
// The trait being drawn, as the studio paints it while the finger moves.
import 'dart:ui';

import 'rust_document.dart' show DocumentPoint;

/// The trait in progress, in pieces: frozen ones of [pieceLength] points,
/// which never change again, and a live tail, the only one that grows.
///
/// One path that grew by a segment at each sample was copied whole at each
/// picture, since the picture keeps what it draws and a path changed after
/// it must be copied first: 100 000 points, 9.8 ms a picture (measured in
/// the retrospective of October 2026, F-05). A frozen piece is shared by the
/// pictures as it is; only the tail is copied.
///
/// Each piece starts at the last point of the one before. With round ends
/// and round joins, a stroke covers exactly what lies within half its width
/// of its line, so the pieces together cover what the whole trait would.
/// The colour of a trait is opaque: where two pieces overlap, it does not
/// darken; only anti-aliased edge pixels there may differ by a shade
/// (test/draft_stroke_test.dart).
class DraftStroke {
  DraftStroke(DocumentPoint first)
    : _tail = Path()..moveTo(first.x, first.y),
      _last = first;

  /// The trait through [points], in order: the first one starts it.
  factory DraftStroke.through(List<DocumentPoint> points) {
    final stroke = DraftStroke(points.first);
    for (final point in points.skip(1)) {
      stroke.lineTo(point);
    }
    return stroke;
  }

  /// Points of a piece, its first one, shared with the piece before,
  /// included.
  static const pieceLength = 256;

  final List<Path> _frozen = [];
  Path _tail;
  int _tailPoints = 1;
  DocumentPoint _last;

  /// The trait goes on to [point].
  void lineTo(DocumentPoint point) {
    if (_tailPoints == pieceLength) {
      _frozen.add(_tail);
      _tail = Path()..moveTo(_last.x, _last.y);
      _tailPoints = 1;
    }
    _tail.lineTo(point.x, point.y);
    _tailPoints++;
    _last = point;
  }

  /// The pieces in the order of the trait, the live tail last.
  Iterable<Path> get pieces sync* {
    yield* _frozen;
    yield _tail;
  }
}
