// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'vector_art.dart';

enum EduArt {
  brush,
  newPage,
  folder,
  save,
  exportImage,
  undo,
  redo,
  mascot,
  line,
  rectangle,
  ellipse,
  select,
  text,
  stamp,
  layers,
  fill,
  eraser,
  gallery,
  printer,
  // Kept as SVG files in the core: see vector_art.dart.
  options,
  film,
}

/// Original, resolution-independent artwork for a labelled control or helper.
/// The parent supplies its action name and accessibility semantics.
class EduIllustration extends StatelessWidget {
  const EduIllustration({super.key, required this.art, this.size = 32})
    : assert(size > 0 && size < double.infinity);

  final EduArt art;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _EduArtPainter(art)),
      ),
    ),
  );
}

/// The two little circles of the pictures of the line, the rectangle and
/// the oval: where the shape starts and where it ends. The sheet marks the
/// clicks of a shape made of two with the same colours and the same ink.
class ShapeMarkColours {
  const ShapeMarkColours._(this.start, this.end);
  final Color start;
  final Color end;

  static const ink = _EduArtPainter.ink;
  static const line = ShapeMarkColours._(
    _EduArtPainter.sunshine,
    _EduArtPainter.coral,
  );
  static const rectangle = line;
  static const oval = ShapeMarkColours._(
    _EduArtPainter.mint,
    _EduArtPainter.sunshine,
  );
}

class _EduArtPainter extends CustomPainter {
  const _EduArtPainter(this.art);
  final EduArt art;

  static const ink = Color(0xff293d4b);
  static const teal = Color(0xff43ac9c);
  static const mint = Color(0xffb7e6d2);
  static const purple = Color(0xff9a82c9);
  static const sunshine = Color(0xffffcd62);
  static const coral = Color(0xffed8c88);
  static const paper = Color(0xfffffcf0);

  Paint _fill(Color color) => Paint()..color = color;
  Paint _stroke([Color color = ink, double width = 2.5]) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _shape(Canvas canvas, Path path, Color color) {
    canvas.drawPath(path, _fill(color));
    canvas.drawPath(path, _stroke());
  }

  void _rounded(Canvas canvas, Rect rect, double radius, Color color) {
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(shape, _fill(color));
    canvas.drawRRect(shape, _stroke());
  }

  void _oval(Canvas canvas, Rect rect, Color color, {bool outline = true}) {
    canvas.drawOval(rect, _fill(color));
    if (outline) canvas.drawOval(rect, _stroke());
  }

  // A picture kept as an SVG file, on the same grid of 64 units. Without
  // the catalogue of the core — a library older than this interface — a
  // plain shape stands for it: a control is never an empty place.
  void _picture(Canvas canvas, String key) {
    final picture = VectorArtCatalog.instance?[key];
    if (picture != null) {
      picture.paint(canvas, const Rect.fromLTWH(0, 0, 64, 64));
      return;
    }
    switch (key) {
      case 'film':
        _rounded(canvas, const Rect.fromLTWH(8, 14, 48, 36), 6, paper);
        _shape(
          canvas,
          Path()
            ..moveTo(26, 23)
            ..lineTo(42, 32)
            ..lineTo(26, 41)
            ..close(),
          teal,
        );
      default:
        // A wheel: a disc with its hub.
        _oval(canvas, const Rect.fromLTWH(10, 10, 44, 44), purple);
        _oval(canvas, const Rect.fromLTWH(24, 24, 16, 16), paper);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    switch (art) {
      case EduArt.brush:
        _brush(canvas);
      case EduArt.newPage:
        _page(canvas);
      case EduArt.folder:
        _folder(canvas);
      case EduArt.save:
        _folder(canvas, saved: true);
      case EduArt.exportImage:
        _export(canvas);
      case EduArt.undo:
        _history(canvas);
      case EduArt.redo:
        canvas.translate(64, 0);
        canvas.scale(-1, 1);
        _history(canvas);
      case EduArt.mascot:
        // The companion of the window is the study « Debout pour peindre »
        // of the logo, chosen by the owner on 8 October 2026: the core draws
        // it from its SVG. The drawing of before stands in for it when the
        // core has no such picture.
        final companion = VectorArtCatalog.instance?['mascotte'];
        if (companion != null) {
          companion.paint(canvas, const Rect.fromLTWH(0, 0, 64, 64));
        } else {
          _mascot(canvas);
        }
      case EduArt.line:
        _line(canvas);
      case EduArt.rectangle:
        _rectangle(canvas);
      case EduArt.ellipse:
        _ellipse(canvas);
      case EduArt.text:
        _text(canvas);
      case EduArt.stamp:
        _stamp(canvas);
      case EduArt.layers:
        _layers(canvas);
      case EduArt.fill:
        _bucket(canvas);
      case EduArt.eraser:
        _eraser(canvas);
      case EduArt.gallery:
        _gallery(canvas);
      case EduArt.printer:
        _printer(canvas);
      case EduArt.options:
        _picture(canvas, 'options');
      case EduArt.film:
        _picture(canvas, 'film');
      case EduArt.select:
        _shape(
          canvas,
          Path()
            ..moveTo(18, 10)
            ..lineTo(19, 48)
            ..lineTo(29, 39)
            ..lineTo(38, 56)
            ..lineTo(47, 51)
            ..lineTo(37, 35)
            ..lineTo(51, 32)
            ..close(),
          sunshine,
        );
        canvas.drawLine(
          const Offset(8, 13),
          const Offset(11, 17),
          _stroke(teal, 3),
        );
        canvas.drawLine(
          const Offset(27, 6),
          const Offset(27, 10),
          _stroke(purple, 3),
        );
    }
    canvas.restore();
  }

  void _brush(Canvas canvas) {
    _shape(
      canvas,
      Path()
        ..moveTo(29, 33)
        ..lineTo(45, 9)
        ..cubicTo(49, 3, 58, 10, 54, 15)
        ..lineTo(37, 39)
        ..close(),
      purple,
    );
    _shape(
      canvas,
      Path()
        ..moveTo(27, 31)
        ..lineTo(39, 40)
        ..lineTo(33, 47)
        ..lineTo(21, 39)
        ..close(),
      sunshine,
    );
    _shape(
      canvas,
      Path()
        ..moveTo(22, 39)
        ..cubicTo(9, 37, 15, 52, 6, 54)
        ..cubicTo(22, 61, 33, 54, 33, 47)
        ..close(),
      teal,
    );
    canvas.drawPath(
      Path()
        ..moveTo(14, 52)
        ..quadraticBezierTo(21, 53, 25, 47),
      _stroke(mint, 3),
    );
    canvas.drawCircle(const Offset(48, 13), 1.7, _fill(paper));
  }

  // A capital letter with its counter, and the cursor that follows it.
  void _text(Canvas canvas) {
    final letter = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(6, 55)
      ..lineTo(21, 9)
      ..lineTo(33, 9)
      ..lineTo(48, 55)
      ..lineTo(37, 55)
      ..lineTo(34.5, 46)
      ..lineTo(19.5, 46)
      ..lineTo(17, 55)
      ..close()
      ..moveTo(22.5, 37)
      ..lineTo(31.5, 37)
      ..lineTo(27, 22)
      ..close();
    _shape(canvas, letter, sunshine);
    canvas.drawPath(
      Path()
        ..moveTo(51, 12)
        ..lineTo(59, 12)
        ..moveTo(55, 12)
        ..lineTo(55, 52)
        ..moveTo(51, 52)
        ..lineTo(59, 52),
      _stroke(purple, 3.5),
    );
  }

  // A rubber stamp above the little star it has just printed.
  void _stamp(Canvas canvas) {
    _shape(
      canvas,
      Path()
        ..moveTo(26, 21)
        ..lineTo(38, 21)
        ..lineTo(42, 35)
        ..lineTo(22, 35)
        ..close(),
      purple,
    );
    _oval(canvas, const Rect.fromLTRB(22, 4, 42, 24), purple);
    _rounded(canvas, const Rect.fromLTRB(11, 33, 53, 45), 4, sunshine);
    final star = Path();
    for (var point = 0; point < 10; point++) {
      final angle = -math.pi / 2 + point * math.pi / 5;
      final radius = point.isEven ? 8.0 : 3.6;
      final x = 32 + math.cos(angle) * radius;
      final y = 55 + math.sin(angle) * radius;
      if (point == 0) {
        star.moveTo(x, y);
      } else {
        star.lineTo(x, y);
      }
    }
    canvas.drawPath(star..close(), _fill(coral));
    canvas.drawPath(star, _stroke(ink, 1.6));
  }

  // Three sheets laid on top of each other, the top one in front.
  void _layers(Canvas canvas) {
    Path sheet(double top) => Path()
      ..moveTo(32, top)
      ..lineTo(57, top + 12)
      ..lineTo(32, top + 24)
      ..lineTo(7, top + 12)
      ..close();
    _shape(canvas, sheet(31), teal);
    _shape(canvas, sheet(19), sunshine);
    _shape(canvas, sheet(7), coral);
  }

  // A tilted pot of paint with its handle, and the drop that falls from it.
  void _bucket(Canvas canvas) {
    canvas.save();
    canvas.translate(27, 35);
    canvas.rotate(-math.pi / 7);
    canvas.drawArc(
      const Rect.fromLTRB(-16, -31, 16, 3),
      math.pi,
      math.pi,
      false,
      _stroke(ink, 2.5),
    );
    _shape(
      canvas,
      Path()
        ..moveTo(-18, -13)
        ..lineTo(18, -13)
        ..lineTo(13, 20)
        ..lineTo(-13, 20)
        ..close(),
      teal,
    );
    _oval(canvas, const Rect.fromLTRB(-18, -18, 18, -8), sunshine);
    canvas.restore();
    _shape(
      canvas,
      Path()
        ..moveTo(52, 28)
        ..cubicTo(61, 41, 59, 53, 52, 53)
        ..cubicTo(45, 53, 43, 41, 52, 28)
        ..close(),
      coral,
    );
  }

  // Two drawings kept one behind the other: the album of saved pictures.
  void _gallery(Canvas canvas) {
    canvas.save();
    canvas.translate(30, 30);
    canvas.rotate(-math.pi / 14);
    _rounded(canvas, const Rect.fromLTRB(-22, -20, 20, 14), 4, mint);
    canvas.restore();
    _rounded(canvas, const Rect.fromLTRB(14, 20, 58, 56), 4, paper);
    _oval(canvas, const Rect.fromLTRB(40, 25, 52, 37), sunshine);
    final hill = Path()
      ..moveTo(17, 53)
      ..lineTo(29, 37)
      ..lineTo(38, 46)
      ..lineTo(44, 41)
      ..lineTo(55, 53)
      ..close();
    canvas.drawPath(hill, _fill(teal));
    canvas.drawPath(hill, _stroke(ink, 2));
  }

  // A printer: the blank sheet goes in at the top, the drawing comes out.
  void _printer(Canvas canvas) {
    _rounded(canvas, const Rect.fromLTRB(19, 7, 45, 26), 2, paper);
    _rounded(canvas, const Rect.fromLTRB(7, 22, 57, 46), 6, mint);
    _oval(canvas, const Rect.fromLTRB(44, 27, 51, 34), coral);
    _rounded(canvas, const Rect.fromLTRB(16, 37, 48, 58), 2, paper);
    canvas.drawLine(
      const Offset(22, 45),
      const Offset(42, 45),
      _stroke(teal, 3),
    );
    canvas.drawLine(
      const Offset(22, 51),
      const Offset(35, 51),
      _stroke(purple, 3),
    );
  }

  // A slanted rubber in its sleeve, above the trace it has just removed.
  void _eraser(Canvas canvas) {
    canvas.save();
    canvas.translate(33, 28);
    canvas.rotate(-math.pi / 5);
    _rounded(canvas, const Rect.fromLTRB(-24, -12, 24, 12), 5, coral);
    final sleeve = RRect.fromRectAndCorners(
      const Rect.fromLTRB(-7, -12, 24, 12),
      topRight: const Radius.circular(5),
      bottomRight: const Radius.circular(5),
    );
    canvas.drawRRect(sleeve, _fill(teal));
    canvas.drawRRect(sleeve, _stroke());
    canvas.restore();
    for (final x in const [8.0, 19.0, 30.0]) {
      canvas.drawLine(Offset(x, 56), Offset(x + 5, 56), _stroke(purple, 3.5));
    }
  }

  void _line(Canvas canvas) {
    const start = Offset(14, 49);
    const end = Offset(50, 15);
    canvas.drawLine(start, end, _stroke(ink, 8.5));
    canvas.drawLine(start, end, _stroke(teal, 5));
    _oval(canvas, const Rect.fromLTRB(7.5, 42.5, 20.5, 55.5), sunshine);
    _oval(canvas, const Rect.fromLTRB(43.5, 8.5, 56.5, 21.5), coral);
  }

  void _rectangle(Canvas canvas) {
    final outline = RRect.fromRectAndRadius(
      const Rect.fromLTRB(12, 16, 52, 48),
      const Radius.circular(2),
    );
    canvas.drawRRect(outline, _stroke(ink, 7));
    canvas.drawRRect(outline, _stroke(teal, 4));
    _oval(canvas, const Rect.fromLTRB(6.5, 10.5, 17.5, 21.5), sunshine);
    _oval(canvas, const Rect.fromLTRB(46.5, 42.5, 57.5, 53.5), coral);
  }

  void _ellipse(Canvas canvas) {
    const outline = Rect.fromLTRB(9, 17, 55, 47);
    canvas.drawOval(outline, _stroke(ink, 7));
    canvas.drawOval(outline, _stroke(purple, 4));
    _oval(canvas, const Rect.fromLTRB(3.5, 26.5, 14.5, 37.5), mint);
    _oval(canvas, const Rect.fromLTRB(49.5, 26.5, 60.5, 37.5), sunshine);
  }

  void _page(Canvas canvas) {
    _shape(
      canvas,
      Path()
        ..moveTo(17, 7)
        ..lineTo(39, 7)
        ..lineTo(51, 19)
        ..lineTo(51, 52)
        ..quadraticBezierTo(51, 57, 46, 57)
        ..lineTo(17, 57)
        ..quadraticBezierTo(12, 57, 12, 52)
        ..lineTo(12, 12)
        ..quadraticBezierTo(12, 7, 17, 7)
        ..close(),
      paper,
    );
    _shape(
      canvas,
      Path()
        ..moveTo(39, 7)
        ..lineTo(39, 19)
        ..lineTo(51, 19)
        ..close(),
      mint,
    );
    final star = Path();
    for (var point = 0; point < 10; point++) {
      final angle = -math.pi / 2 + point * math.pi / 5;
      final radius = point.isEven ? 12.0 : 5.9;
      final x = 31 + math.cos(angle) * radius;
      final y = 36 + math.sin(angle) * radius;
      if (point == 0) {
        star.moveTo(x, y);
      } else {
        star.lineTo(x, y);
      }
    }
    _shape(canvas, star..close(), sunshine);
  }

  void _folder(Canvas canvas, {bool saved = false}) {
    _shape(
      canvas,
      Path()
        ..moveTo(8, 18)
        ..quadraticBezierTo(8, 13, 13, 13)
        ..lineTo(25, 13)
        ..lineTo(31, 20)
        ..lineTo(51, 20)
        ..quadraticBezierTo(56, 20, 56, 25)
        ..lineTo(54, 48)
        ..lineTo(8, 48)
        ..close(),
      sunshine,
    );
    _shape(
      canvas,
      Path()
        ..moveTo(8, 29)
        ..lineTo(56, 29)
        ..lineTo(52, 50)
        ..quadraticBezierTo(51, 54, 47, 54)
        ..lineTo(16, 54)
        ..quadraticBezierTo(12, 54, 11, 50)
        ..close(),
      saved ? teal : mint,
    );
    if (saved) {
      _oval(canvas, const Rect.fromLTRB(33, 34, 60, 61), paper);
      canvas.drawPath(
        Path()
          ..moveTo(40, 47)
          ..lineTo(45, 52)
          ..lineTo(54, 42),
        _stroke(teal, 4),
      );
    } else {
      canvas.drawLine(
        const Offset(21, 41),
        const Offset(42, 41),
        _stroke(teal, 4),
      );
    }
  }

  void _export(Canvas canvas) {
    _rounded(canvas, const Rect.fromLTRB(8, 15, 49, 56), 6, paper);
    _oval(
      canvas,
      const Rect.fromLTRB(16, 22, 26, 32),
      sunshine,
      outline: false,
    );
    _shape(
      canvas,
      Path()
        ..moveTo(14, 48)
        ..lineTo(25, 35)
        ..lineTo(33, 43)
        ..lineTo(40, 36)
        ..lineTo(44, 48)
        ..close(),
      mint,
    );
    // Arrow leaving the picture: an export, not an upload to a cloud service.
    canvas.drawPath(
      Path()
        ..moveTo(37, 26)
        ..lineTo(56, 7)
        ..moveTo(42, 7)
        ..lineTo(56, 7)
        ..lineTo(56, 21),
      _stroke(purple, 6),
    );
  }

  void _history(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(46, 51)
        ..cubicTo(63, 30, 38, 17, 15, 26),
      _stroke(purple, 8),
    );
    _shape(
      canvas,
      Path()
        ..moveTo(9, 26)
        ..lineTo(24, 13)
        ..lineTo(24, 36)
        ..close(),
      teal,
    );
  }

  void _mascot(Canvas canvas) {
    const skin = Color(0xfff4cdb4);
    const hair = Color(0xff6c4843);
    const chair = Color(0xff30363c);
    const gold = Color(0xffd5b64b);
    // Original simplified design inspired by the supplied front-wheel-drive
    // powered chair: front/right drive wheel, rear/left caster and gold trim.
    // Keep this geometry aligned with prototypes/art/mascotte-edupaint.svg.
    canvas.drawPath(
      Path()
        ..moveTo(12, 16)
        ..lineTo(16, 18)
        ..lineTo(19, 25),
      _stroke(chair, 3),
    );
    _rounded(canvas, const Rect.fromLTRB(6, 9, 17, 18), 3, chair);
    _shape(
      canvas,
      Path()
        ..moveTo(18, 19)
        ..lineTo(24, 20)
        ..lineTo(25, 40)
        ..quadraticBezierTo(23, 44, 17, 44)
        ..lineTo(12, 42)
        ..lineTo(15, 25)
        ..quadraticBezierTo(16, 20, 18, 19)
        ..close(),
      chair,
    );
    _rounded(canvas, const Rect.fromLTRB(17, 39, 43, 45), 3, chair);
    canvas.drawLine(
      const Offset(21, 44),
      const Offset(23, 49),
      _stroke(chair, 4),
    );
    _shape(
      canvas,
      Path()
        ..moveTo(14, 46)
        ..quadraticBezierTo(23, 43, 43, 46)
        ..lineTo(49, 51)
        ..lineTo(44, 59)
        ..lineTo(15, 59)
        ..quadraticBezierTo(10, 55, 14, 46)
        ..close(),
      chair,
    );
    _shape(
      canvas,
      Path()
        ..moveTo(18, 48)
        ..lineTo(29, 47)
        ..quadraticBezierTo(32, 48, 32, 52)
        ..lineTo(30, 57)
        ..lineTo(17, 57)
        ..lineTo(16, 54)
        ..lineTo(26, 54)
        ..lineTo(27, 50)
        ..lineTo(18, 51)
        ..close(),
      gold,
    );
    // The rear caster sits behind the motor base, opposite the footplate.
    canvas.drawPath(
      Path()
        ..moveTo(18, 46)
        ..lineTo(11, 47)
        ..lineTo(10, 53),
      _stroke(gold, 3),
    );
    _oval(canvas, const Rect.fromLTRB(4, 50, 16, 62), chair);
    _oval(canvas, const Rect.fromLTRB(7, 53, 13, 59), gold, outline: false);
    canvas.drawCircle(const Offset(10, 56), 1.3, _fill(chair));

    // Bent legs, light shoes and the forward footplate make the seated pose clear.
    _shape(
      canvas,
      Path()
        ..moveTo(27, 37)
        ..lineTo(39, 37)
        ..quadraticBezierTo(47, 36, 49, 41)
        ..lineTo(54, 49)
        ..lineTo(46, 52)
        ..lineTo(41, 45)
        ..lineTo(28, 45)
        ..quadraticBezierTo(24, 43, 27, 37)
        ..close(),
      purple,
    );
    _rounded(canvas, const Rect.fromLTRB(51, 48, 61, 53), 2, paper);
    canvas.drawLine(
      const Offset(49, 55),
      const Offset(61, 55),
      _stroke(chair, 3),
    );
    // Large front drive wheel: a gold ring and three broad spokes stay readable.
    _oval(canvas, const Rect.fromLTRB(31, 40, 53, 62), chair);
    canvas.drawCircle(const Offset(42, 51), 7.2, _stroke(gold, 2.2));
    canvas.drawPath(
      Path()
        ..moveTo(42, 46)
        ..lineTo(42, 51)
        ..lineTo(46.4, 53.5)
        ..moveTo(42, 51)
        ..lineTo(37.6, 53.5),
      _stroke(gold, 2.5),
    );
    canvas.drawCircle(const Offset(42, 51), 1.8, _fill(gold));

    _rounded(canvas, const Rect.fromLTRB(27, 22, 34, 30), 2, skin);
    _shape(
      canvas,
      Path()
        ..moveTo(24, 27)
        ..quadraticBezierTo(29, 25, 35, 27)
        ..lineTo(40, 38)
        ..quadraticBezierTo(34, 43, 24, 39)
        ..close(),
      teal,
    );
    canvas.drawPath(
      Path()
        ..moveTo(27, 28)
        ..quadraticBezierTo(30, 31, 34, 28),
      _stroke(mint, 2.4),
    );

    // One hand reaches the joystick in front; the other lifts a coloured pencil.
    _rounded(canvas, const Rect.fromLTRB(17, 35, 43, 40), 2, chair);
    _shape(
      canvas,
      Path()
        ..moveTo(24, 28)
        ..quadraticBezierTo(20, 28, 21, 34)
        ..quadraticBezierTo(21, 39, 27, 38)
        ..lineTo(34, 38)
        ..quadraticBezierTo(39, 38, 38, 34)
        ..quadraticBezierTo(36, 32, 33, 34)
        ..lineTo(27, 33)
        ..lineTo(27, 30)
        ..close(),
      skin,
    );
    canvas.drawLine(
      const Offset(36, 31),
      const Offset(36, 36),
      _stroke(chair, 2.5),
    );
    canvas.drawCircle(const Offset(36, 30), 2.2, _fill(chair));

    canvas.save();
    canvas.translate(49, 19);
    canvas.rotate(.28);
    _rounded(canvas, const Rect.fromLTRB(-2.6, -9, 2.6, 12), 1, sunshine);
    _rounded(canvas, const Rect.fromLTRB(-2.6, 8, 2.6, 12), 1, coral);
    _shape(
      canvas,
      Path()
        ..moveTo(-2.6, -9)
        ..lineTo(0, -15)
        ..lineTo(2.6, -9)
        ..close(),
      paper,
    );
    canvas.drawLine(
      const Offset(0, -15),
      const Offset(0, -13),
      _stroke(ink, 2),
    );
    canvas.restore();
    _shape(
      canvas,
      Path()
        ..moveTo(36, 28)
        ..quadraticBezierTo(38, 25, 42, 28)
        ..lineTo(44, 25)
        ..quadraticBezierTo(43, 21, 48, 22)
        ..quadraticBezierTo(52, 24, 47, 29)
        ..lineTo(43, 34)
        ..quadraticBezierTo(39, 35, 36, 31)
        ..close(),
      skin,
    );

    _oval(canvas, const Rect.fromLTRB(19, 5, 41, 27), skin);
    _shape(
      canvas,
      Path()
        ..moveTo(19, 16)
        ..cubicTo(14, 5, 24, 0, 32, 4)
        ..cubicTo(39, 1, 45, 9, 39, 14)
        ..lineTo(36, 9)
        ..quadraticBezierTo(27, 15, 24, 10)
        ..lineTo(23, 17)
        ..close(),
      hair,
    );
    canvas.drawCircle(const Offset(27, 17), 1.4, _fill(ink));
    canvas.drawCircle(const Offset(35, 17), 1.4, _fill(ink));
    canvas.drawPath(
      Path()
        ..moveTo(28, 21)
        ..quadraticBezierTo(31.5, 25, 35, 21),
      _stroke(ink, 1.8),
    );
  }

  @override
  bool shouldRepaint(covariant _EduArtPainter oldDelegate) =>
      oldDelegate.art != art;
}
