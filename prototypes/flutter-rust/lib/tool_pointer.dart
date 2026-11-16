// SPDX-License-Identifier: MIT
// « La pointe » (Color 1.2): the pointer of each tool. One rule for the
// child: the tool acts at the end of the tip, at the top left, and the tip
// has the colour that was chosen — white for the eraser, which paints
// nothing; « Choisir » keeps its arrow.
//
// The drawings are files of the core (art/interface/pointeur-*.svg), on the
// grid of 64 of the other pictures of the interface, the acting point at
// (3, 3). The brush, the paint pot and « Choisir » have a drawing of their
// own; every other tool shows its picture of the tool bar, smaller, behind
// the common tip. The interface paints them itself, where the pointer is:
// the pointer of the system is hidden meanwhile (see main.dart). Nothing
// here knows the studio: a tool and a colour make a pointer.
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'studio_tool.dart';
import 'vector_art.dart';

/// The side of a pointer on the screen, in logical pixels: the grid of its
/// drawing, one unit a pixel.
const toolPointerSide = 64.0;

/// Where the tool acts, in the drawing of its pointer.
const toolPointerTip = Offset(3, 3);

/// How a tool shows where it acts: the drawing of the tool, and the colour
/// its tip takes.
@immutable
final class ToolPointer {
  const ToolPointer(this.tool, this.rgb);
  final StudioTool tool;

  /// The colour the child chose, 0xRRGGBB.
  final int rgb;

  /// The colour of the tip: the chosen one for a tool that paints, white
  /// for the eraser.
  Color get tipColour => tool == StudioTool.eraser
      ? const Color(0xffffffff)
      : Color(0xff000000 | rgb);

  /// The picture of the core drawn whole for the tool, when it has one of
  /// its own.
  String? get _ownKey => switch (tool) {
    StudioTool.brush => 'pointeur-pinceau',
    StudioTool.fill => 'pointeur-remplir',
    StudioTool.select => 'pointeur-choisir',
    _ => null,
  };

  /// Where the picture of the tool bar lies behind the tip: its corner and
  /// its side on the grid of 64. The line is shown whole, with its two
  /// ends, beside the tip; the star of « Magie » a little larger.
  (double, double) get _iconPlace => switch (tool) {
    StudioTool.line => (23, 41),
    StudioTool.magic => (22, 42),
    _ => (24, 40),
  };

  static const _grid = Rect.fromLTWH(0, 0, 64, 64);
  static const _ink = Color(0xff293d4b);

  // The tip as its file draws it, for a core that has no catalogue of
  // pictures: a pointer is never nothing.
  static final _tip = Path()
    ..moveTo(3, 3)
    ..lineTo(20.4, 8.4)
    ..cubicTo(23.4, 9.4, 24.2, 13.2, 22, 15.4)
    ..lineTo(15.4, 22)
    ..cubicTo(13.2, 24.2, 9.4, 23.4, 8.4, 20.4)
    ..close();

  /// Paints the pointer so that it acts at [at]. [side] is its size on the
  /// screen.
  void paint(Canvas canvas, Offset at, {double side = toolPointerSide}) {
    final scale = side / 64;
    canvas.save();
    canvas.translate(
      at.dx - toolPointerTip.dx * scale,
      at.dy - toolPointerTip.dy * scale,
    );
    canvas.scale(scale);
    final catalog = VectorArtCatalog.instance;
    final tints = {'couleur': tipColour, 'couleur-pot': tipColour};
    final ownKey = _ownKey;
    final own = ownKey == null ? null : catalog?[ownKey];
    final tip = catalog?['pointeur-pointe'];
    if (own != null) {
      own.paint(canvas, _grid, tints: tints);
    } else if (ownKey == null && tip != null) {
      final (corner, size) = _iconPlace;
      catalog?[tool.art.svgKey]?.paint(
        canvas,
        Rect.fromLTWH(corner, corner, size, size),
      );
      tip.paint(canvas, _grid, tints: tints);
    } else {
      final halo = Paint()
        ..color = const Color(0xffffffff)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.4
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(_tip, halo);
      canvas.drawPath(
        _tip,
        Paint()
          ..color = tool == StudioTool.select
              ? const Color(0xffffcd62)
              : tipColour,
      );
      canvas.drawPath(
        _tip,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();
  }

  @override
  bool operator ==(Object other) =>
      other is ToolPointer && other.tool == tool && other.rgb == rgb;

  @override
  int get hashCode => Object.hash(tool, rgb);
}
