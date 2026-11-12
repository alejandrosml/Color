// SPDX-License-Identifier: MIT
// What the sheet shows of a tool before it acts (Color 1.2): « la pointe »,
// the pointer of the tool where the mouse or the pointer of the keyboard
// is, and a preview of what a press would do there — the part the paint pot
// would colour, hatched; a dot of the size and colour of the trait; the
// round of the eraser; the stamp, see-through, at its size; the stroke
// where the first letter would be written.
//
// One layer over the sheet paints them, apart from the drawing: a pointer
// that moves paints this layer again and nothing of the sheet, and builds
// nothing. The studio says what to show (main.dart); nothing here knows a
// document, only prepared elements and the view.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'document_renderer.dart';
import 'rust_document.dart';
import 'tool_pointer.dart';
import 'viewport.dart';

/// What a press of the tool would do where the pointer is.
@immutable
sealed class ActionPreview {
  const ActionPreview();
}

/// A dot of the size of the trait, in its colour: where the brush, a line
/// or the outline of a shape would begin.
final class DotPreview extends ActionPreview {
  const DotPreview({
    required this.at,
    required this.width,
    required this.rgb,
    this.square = false,
    this.hollow = false,
    this.opacity = 1,
    this.mirrored = false,
  });

  /// Where the pointer is, in logical pixels of the frame of the sheet.
  final Offset at;

  /// The width of the trait, in units of the sheet.
  final double width;
  final int rgb;

  /// The marker ends square.
  final bool square;

  /// A tool that paints with colours of its own — the rainbow, confetti —
  /// shows its size only: a ring.
  final bool hollow;

  /// The marker shows through.
  final double opacity;

  /// The mirror of « Magie » draws twice: a second dot, in the mirror of
  /// the middle of the sheet.
  final bool mirrored;

  @override
  bool operator ==(Object other) =>
      other is DotPreview &&
      other.at == at &&
      other.width == width &&
      other.rgb == rgb &&
      other.square == square &&
      other.hollow == hollow &&
      other.opacity == opacity &&
      other.mirrored == mirrored;

  @override
  int get hashCode =>
      Object.hash(at, width, rgb, square, hollow, opacity, mirrored);
}

/// The round of the eraser: what it reaches around the pointer.
final class EraserPreview extends ActionPreview {
  const EraserPreview({required this.at, required this.radius});

  /// Where the pointer is, in logical pixels of the frame of the sheet.
  final Offset at;

  /// The reach of the eraser, in logical pixels.
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is EraserPreview && other.at == at && other.radius == radius;

  @override
  int get hashCode => Object.hash(at, radius);
}

/// The stamp a click would pose, see-through, at its size and in its place.
final class PosedStampPreview extends ActionPreview {
  const PosedStampPreview(this.element);

  /// The stamp as the sheet would hold it, in units of the sheet.
  final RenderedElement element;

  /// How much of the stamp shows before it is posed.
  static const opacity = .45;

  @override
  bool operator ==(Object other) =>
      other is PosedStampPreview &&
      other.element.controlBounds == element.controlBounds &&
      other.element.data.stamp == element.data.stamp &&
      other.element.data.rgb == element.data.rgb &&
      other.element.data.look == element.data.look;

  @override
  int get hashCode => Object.hash(
    element.controlBounds,
    element.data.stamp,
    element.data.rgb,
    element.data.look,
  );
}

/// The stroke where the first letter of a text would be written.
final class CaretPreview extends ActionPreview {
  const CaretPreview({
    required this.top,
    required this.height,
    required this.rgb,
  });

  /// The top of the first line, in units of the sheet.
  final DocumentPoint top;

  /// The height of a line, in units of the sheet.
  final double height;
  final int rgb;

  @override
  bool operator ==(Object other) =>
      other is CaretPreview &&
      other.top.x == top.x &&
      other.top.y == top.y &&
      other.height == height &&
      other.rgb == rgb;

  @override
  int get hashCode => Object.hash(top.x, top.y, height, rgb);
}

/// What the paint pot would colour, hatched in the colour it would pour.
/// What lies over it on the sheet stays as it is, and is left out of the
/// hatching: [ink], a picture of it with nothing under it, and [over], the
/// elements that are not in that picture.
final class PourPreview extends ActionPreview {
  /// An element takes the colour: its inside when [inside] — a rectangle,
  /// an oval, a shape, a zone poured before —, itself otherwise: a trait,
  /// a text, a stamp.
  const PourPreview.element(
    RenderedElement this.element, {
    required this.inside,
    required this.rgb,
    this.ink,
    this.over = const [],
  }) : zone = null;

  /// The zone that the lines around the pointer close: its rings, in units
  /// of the sheet. It is poured under the lines.
  const PourPreview.zone(
    Path this.zone, {
    required this.rgb,
    this.ink,
    this.over = const [],
  }) : element = null,
       inside = false;

  /// The paper itself, all of it: what is drawn stays as it is.
  const PourPreview.sheet({required this.rgb, this.ink, this.over = const []})
    : element = null,
      inside = false,
      zone = null;

  final RenderedElement? element;
  final bool inside;
  final Path? zone;
  final ui.Image? ink;
  final List<RenderedElement> over;

  /// The colour the pot would pour, 0xRRGGBB.
  final int rgb;

  bool get wholeSheet => element == null && zone == null;

  /// Whether the pointer at [point] of the sheet is still on what this
  /// preview shows: it then stays while the pointer moves, until the pot
  /// has looked again.
  bool covers(DocumentPoint point) {
    final at = Offset(point.x, point.y);
    final zone = this.zone;
    if (zone != null) return zone.contains(at);
    final element = this.element;
    if (element != null) {
      return element.shownBounds
          .inflate(element.data.width / 2 + 1)
          .contains(at);
    }
    return true;
  }
}

/// The two bands of the hatching, in logical pixels: seven of the colour,
/// seven of a veil, at 45 degrees, as the model of the pointers shows them.
const hatchBand = 7.0;

/// The paint that hatches in the colour [rgb], bands fixed on the screen. A
/// veil of white lies between the bands of the colour; between those of a
/// very light colour, which white would not show, a veil of ink.
Paint hatchPaint(int rgb) {
  final colour = Color(0xff000000 | rgb);
  final veil = colour.computeLuminance() > .8
      ? const Color(0x38293d4b)
      : const Color(0x8cffffff);
  final step = 2 * hatchBand / math.sqrt2;
  return Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.linear(
      Offset.zero,
      Offset(step, -step),
      [colour, colour, veil, veil, colour],
      const [0, .46, .54, .96, 1],
      TileMode.repeated,
    );
}

/// What the layer over the sheet shows now. The studio changes it; the
/// painter of the layer listens, and paints again without any build.
final class SheetHint extends ChangeNotifier {
  ToolPointer? _pointer;
  Offset? _mouseAt;
  Offset? _keyAt;
  ActionPreview? _preview;

  /// The pointer of the tool in hand; null where the pointer of the system
  /// stays: the hand that moves the sheet, the pipette.
  ToolPointer? get pointer => _pointer;
  set pointer(ToolPointer? value) {
    if (value == _pointer) return;
    _pointer = value;
    notifyListeners();
  }

  /// Where the mouse is, in logical pixels of the frame of the sheet; null
  /// when no mouse is over it.
  Offset? get mouseAt => _mouseAt;
  set mouseAt(Offset? value) {
    if (value == _mouseAt) return;
    _mouseAt = value;
    notifyListeners();
  }

  /// Where the pointer of the keyboard is; null when it is not shown.
  Offset? get keyAt => _keyAt;
  set keyAt(Offset? value) {
    if (value == _keyAt) return;
    _keyAt = value;
    notifyListeners();
  }

  /// What a press would do now; null when there is nothing to show.
  ActionPreview? get preview => _preview;
  set preview(ActionPreview? value) {
    if (value == _preview) return;
    _preview = value;
    notifyListeners();
  }
}

/// Paints the preview, then the pointers over it, in the frame of the sheet.
class SheetHintPainter extends CustomPainter {
  SheetHintPainter({required this.viewport, required this.hint})
    : super(repaint: hint);
  final DocumentViewport viewport;
  final SheetHint hint;

  static const _white = Color(0xffffffff);
  static const _ink = Color(0xff293d4b);

  Rect get _sheet => Rect.fromLTWH(
    viewport.left,
    viewport.top,
    viewport.width,
    viewport.height,
  );

  void _enterUnits(Canvas canvas) {
    canvas.translate(viewport.left, viewport.top);
    canvas.scale(viewport.scale);
  }

  Rect _onScreen(Rect units) => Rect.fromLTRB(
    viewport.left + units.left * viewport.scale,
    viewport.top + units.top * viewport.scale,
    viewport.left + units.right * viewport.scale,
    viewport.top + units.bottom * viewport.scale,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Offset.zero & size;
    canvas.save();
    canvas.clipRect(frame);
    final preview = hint.preview;
    if (preview != null) {
      final sheet = _sheet.intersect(frame);
      if (!sheet.isEmpty) {
        canvas.save();
        // The round of the eraser may lie beside the sheet, where a rub may
        // begin; everything else is shown on the sheet only.
        if (preview is! EraserPreview) canvas.clipRect(sheet);
        switch (preview) {
          case DotPreview():
            _paintDot(canvas, preview);
          case EraserPreview():
            _paintEraser(canvas, preview);
          case PosedStampPreview():
            _paintStamp(canvas, preview, sheet);
          case CaretPreview():
            _paintCaret(canvas, preview);
          case PourPreview():
            _paintPour(canvas, preview, sheet);
        }
        canvas.restore();
      }
    }
    final pointer = hint.pointer;
    if (pointer != null) {
      final key = hint.keyAt;
      if (key != null) pointer.paint(canvas, key);
      final mouse = hint.mouseAt;
      if (mouse != null) pointer.paint(canvas, mouse);
    }
    canvas.restore();
  }

  // A thin ring, light then dark, that shows on any drawing.
  void _ring(
    Canvas canvas,
    Offset centre,
    double radius, {
    bool square = false,
  }) {
    void outline(double grow, Paint paint) {
      final rect = Rect.fromCircle(center: centre, radius: radius + grow);
      square ? canvas.drawRect(rect, paint) : canvas.drawOval(rect, paint);
    }

    outline(
      .75,
      Paint()
        ..color = const Color(0xe6ffffff)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..isAntiAlias = true,
    );
    outline(
      2,
      Paint()
        ..color = const Color(0x73293d4b)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = true,
    );
  }

  void _paintDot(Canvas canvas, DotPreview dot) {
    final radius = math.max(dot.width * viewport.scale / 2, 1.0);
    void one(Offset centre) {
      if (!dot.hollow) {
        final paint = Paint()
          ..color = Color(0xff000000 | dot.rgb).withValues(alpha: dot.opacity)
          ..isAntiAlias = true;
        final rect = Rect.fromCircle(center: centre, radius: radius);
        dot.square
            ? canvas.drawRect(rect, paint)
            : canvas.drawOval(rect, paint);
      }
      _ring(canvas, centre, radius, square: dot.square);
    }

    one(dot.at);
    if (dot.mirrored) {
      // The same point in the mirror of the middle of the sheet.
      one(Offset(2 * viewport.left + viewport.width - dot.at.dx, dot.at.dy));
    }
  }

  void _paintEraser(Canvas canvas, EraserPreview eraser) {
    canvas.drawCircle(
      eraser.at,
      eraser.radius,
      Paint()..color = const Color(0x59ffffff),
    );
    canvas.drawCircle(
      eraser.at,
      eraser.radius,
      Paint()
        ..color = _white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );
    canvas.drawCircle(
      eraser.at,
      eraser.radius,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _paintStamp(Canvas canvas, PosedStampPreview stamp, Rect sheet) {
    final bounds = _onScreen(stamp.element.shownBounds).inflate(2);
    canvas.saveLayer(
      bounds.intersect(sheet),
      Paint()..color = const Color.fromRGBO(0, 0, 0, PosedStampPreview.opacity),
    );
    _enterUnits(canvas);
    stamp.element.paint(canvas);
    canvas.restore();
  }

  void _paintCaret(Canvas canvas, CaretPreview caret) {
    final top = Offset(
      viewport.left + caret.top.x * viewport.scale,
      viewport.top + caret.top.y * viewport.scale,
    );
    final bottom = top.translate(0, math.max(caret.height * viewport.scale, 6));
    canvas.drawLine(
      top,
      bottom,
      Paint()
        ..color = _white
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      top,
      bottom,
      Paint()
        ..color = Color(0xff000000 | caret.rgb)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  // What would take the colour is painted opaque in a layer of its own,
  // then the hatching is laid where that layer holds something: its bands
  // stay those of the screen whatever the zoom and the turn of the element.
  void _paintPour(Canvas canvas, PourPreview pour, Rect sheet) {
    final element = pour.element;
    final zone = pour.zone;
    final Rect bounds;
    if (zone != null) {
      bounds = _onScreen(zone.getBounds()).inflate(1).intersect(sheet);
    } else if (element != null) {
      bounds = _onScreen(
        element.shownBounds.inflate(element.data.width / 2 + 1),
      ).inflate(1).intersect(sheet);
    } else {
      bounds = sheet;
    }
    if (bounds.isEmpty) return;
    final opaque = Paint()
      ..color = _white
      ..isAntiAlias = true;
    canvas.saveLayer(bounds, Paint());
    canvas.save();
    _enterUnits(canvas);
    final paper = Rect.fromLTWH(
      0,
      0,
      viewport.documentWidth,
      viewport.documentHeight,
    );
    if (zone != null) {
      canvas.drawPath(zone, opaque);
    } else if (element != null) {
      pour.inside ? element.paintInside(canvas, opaque) : element.paint(canvas);
    } else {
      canvas.drawRect(paper, opaque);
    }
    // What lies over it stays as it is: it is taken out of the hatching.
    final ink = pour.ink;
    if (ink != null) {
      canvas.drawImageRect(
        ink,
        Rect.fromLTWH(0, 0, ink.width.toDouble(), ink.height.toDouble()),
        paper,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..filterQuality = FilterQuality.low,
      );
    }
    if (pour.over.isNotEmpty) {
      canvas.saveLayer(paper, Paint()..blendMode = BlendMode.dstOut);
      for (final other in pour.over) {
        other.paint(canvas);
      }
      canvas.restore();
    }
    canvas.restore();
    canvas.drawRect(bounds, hatchPaint(pour.rgb)..blendMode = BlendMode.srcIn);
    canvas.restore();
  }

  @override
  bool shouldRepaint(SheetHintPainter old) =>
      !identical(old.hint, hint) ||
      old.viewport.scale != viewport.scale ||
      old.viewport.left != viewport.left ||
      old.viewport.top != viewport.top ||
      old.viewport.documentWidth != viewport.documentWidth ||
      old.viewport.documentHeight != viewport.documentHeight;
}
