// SPDX-License-Identifier: MIT
// Painters of the studio: the sheet with its drawing, and the small example
// of the inspector. They read prepared elements and never touch the document.
import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';

import 'child_art.dart' show ShapeMarkColours;
import 'document_renderer.dart';
import 'draft_stroke.dart';
import 'drawing_gesture.dart';
import 'rust_document.dart';
import 'sheet_images.dart';
import 'studio_colors.dart';
import 'viewport.dart';

/// How many of [paintOrder], the first ones, lie on the layer [activeLayer]
/// or under it: [layers] is the stack from the bottom up, and [paintOrder]
/// the indices of [strokes] on the visible layers, bottom layer first, as
/// the document gives them. What is being drawn is painted after these: see
/// [DocumentPainter.draftDepth]. All of them when the layer is unknown.
int draftDepthOf({
  required List<RenderedElement> strokes,
  required List<int> paintOrder,
  required List<LayerData> layers,
  required int activeLayer,
}) {
  final place = {
    for (var position = 0; position < layers.length; position++)
      layers[position].id: position,
  };
  final active = place[activeLayer];
  if (active == null) return paintOrder.length;
  // The paint order goes up the stack, one layer after the other: the first
  // element above the active layer is found by halving, not by a walk
  // through the whole drawing.
  var low = 0;
  var high = paintOrder.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    final layer = place[strokes[paintOrder[middle]].data.layer];
    if (layer != null && layer <= active) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

/// What is being drawn, as the painter of the sheet reads it at every
/// frame: a press and the moves of the pointer change it, and paint the
/// sheet again, without building the studio again (F-03 of the
/// retrospective of October 2026).
final class SheetDraft {
  SheetDraft({
    List<DocumentPoint>? points,
    this.stroke,
    this.kind = VectorKind.stroke,
    this.rgb = 0x477fb2,
    this.width = 12,
    this.fillRgb,
    this.stamp = 0,
  }) : points = points ?? [];

  /// Its points: those of a trait, or the two corners of a shape. Empty
  /// when nothing is being drawn.
  List<DocumentPoint> points;

  /// A trait as pieces of path, frozen as it goes.
  DraftStroke? stroke;
  VectorKind kind;
  int rgb;
  double width;
  int? fillRgb;

  /// The drawing of a stamp, and how it is turned and mirrored.
  int stamp;
  ObjectLook stampLook = ObjectLook.plain;

  /// What a trait is drawn with (Color 1.1), and the seed of its scattered
  /// marks.
  BrushTool tool = BrushTool.round;
  int seed = 0;

  /// The pressure of each point of a trait drawn with a stylus, 1 to 255;
  /// null without one.
  List<int>? pressures;

  /// The marks of the trait so far, as the core makes them, group by group:
  /// those of a tool of 1.1 or of a stylus. Empty for a trait painted as a
  /// line.
  final List<(Path, Paint)> marks = [];

  /// How many segments of the trait already have their marks in [marks].
  int markedSegments = 0;

  /// The width of the sheet when the trait is drawn twice, the second time
  /// in the mirror of the middle of the sheet; null otherwise.
  double? mirrorWidth;

  /// The shape of 1.1 being drawn in its box (kind contour).
  NewShape? shape;

  /// Forgets what the last trait was drawn with.
  void resetLook() {
    tool = BrushTool.round;
    seed = 0;
    pressures = null;
    marks.clear();
    markedSegments = 0;
    mirrorWidth = null;
    shape = null;
  }
}

class DocumentPainter extends CustomPainter {
  DocumentPainter({
    required this.viewport,
    required this.paperRgb,
    required this.background,
    required this.strokes,
    required this.paintOrder,
    required this.draft,
    required Listenable repaint,
    required this.revision,
    required this.selectedIndex,
    required this.selectionBounds,
    required this.selectionOffset,
    this.draftDepth,
    this.anchor,
    this.anchorDrawn = false,
    this.anchorRgb = 0,
    this.anchorWidth = 1,
    this.anchorFillRgb,
    this.anchorShape = NewShape.star,
    this.images,
    this.pixelRatio = 1,
    this.viewMoving = false,
  }) : super(repaint: repaint);
  final DocumentViewport viewport;

  /// The images that keep the drawing from one frame to the next, made for
  /// [pixelRatio] pixels of the screen per logical pixel; null paints every
  /// element at every frame.
  final SheetImages? images;
  final double pixelRatio;

  /// The view moves under a gesture of the hand, two fingers or a trackpad:
  /// the images follow it, and are made again once it stops.
  final bool viewMoving;

  /// Colour of the sheet itself, under an image background and the drawing.
  final int paperRgb;
  final ui.Image? background;
  final List<RenderedElement> strokes;

  /// Indices of [strokes] on visible layers, bottom layer first.
  final List<int> paintOrder;

  /// How many of [paintOrder], the first ones, are painted under what is
  /// being drawn: those of the active layer and of the layers under it, as
  /// [draftDepthOf] counts them. What is drawn goes to the top of the active
  /// layer, so it is painted where the element it becomes will lie, under
  /// the layers above: on a colouring page, under the lines of the page.
  /// Null paints it over the whole drawing.
  final int? draftDepth;

  /// What is being drawn, read at every frame.
  final SheetDraft draft;
  final int revision;
  final int? selectedIndex;
  final Rect? selectionBounds;
  final ValueNotifier<Offset> selectionOffset;

  /// The start of a shape posed by a click, with where the pointer hovers.
  final ShapeAnchor? anchor;

  /// The pointer is pressed for the end of that shape: the draft shows it.
  final bool anchorDrawn;
  final int anchorRgb;
  final double anchorWidth;
  final int? anchorFillRgb;

  /// The shape of 1.1 that two clicks are making.
  final NewShape anchorShape;

  Offset _onScreen(DocumentPoint point) => Offset(
    viewport.left + point.x * viewport.scale,
    viewport.top + point.y * viewport.scale,
  );

  // One of the two little circles of the tools' pictures, at one size on the
  // screen whatever the zoom.
  void _mark(Canvas canvas, DocumentPoint point, Color color) {
    final centre = _onScreen(point);
    canvas.drawCircle(centre, shapeMarkRadius, Paint()..color = color);
    canvas.drawCircle(
      centre,
      shapeMarkRadius,
      Paint()
        ..color = ShapeMarkColours.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  // The place of the chosen element in [paintOrder], -1 without one: once
  // for a painter, not at every frame.
  late final int _takenRank = selectedIndex == null
      ? -1
      : paintOrder.indexOf(selectedIndex!);

  @override
  void paint(Canvas canvas, Size size) {
    final waiting = anchor;
    final hovered = anchorDrawn ? null : waiting?.end;
    // The layers up to the active one, what is being drawn on it, then the
    // layers above it.
    final depth = (draftDepth ?? paintOrder.length).clamp(0, paintOrder.length);
    final taken = _takenRank;
    final drawing =
        (draft.stroke != null && draft.points.isNotEmpty) ||
        (waiting != null && hovered != null);
    // The chosen element is taken by the pointer and follows it.
    final dragging = taken >= 0 && selectionOffset.value != Offset.zero;
    final images = this.images;
    // At rest, and while something is drawn at the top of the drawing, one
    // image holds the whole drawing, exactly as painted element by element.
    // What is drawn under a layer, and the element being taken, lie between
    // two images. Never both: a tool that draws lets the chosen element go;
    // were it otherwise, the sheet is painted as without images.
    final kept =
        images != null &&
        !(drawing && dragging) &&
        images.paint(
          canvas,
          size,
          pixelRatio: pixelRatio,
          viewport: viewport,
          viewMoving: viewMoving,
          paperRgb: paperRgb,
          background: background,
          strokes: strokes,
          paintOrder: paintOrder,
          split: dragging
              ? taken
              : drawing
              ? depth
              : paintOrder.length,
          excluded: dragging ? taken : -1,
          paintLive: (canvas) => dragging
              ? _paintElement(canvas, selectedIndex!)
              : _paintDraft(canvas, waiting, hovered),
        );
    if (!kept) {
      paintSheetBase(
        canvas,
        size,
        viewport,
        paperRgb: paperRgb,
        background: background,
      );
      for (var rank = 0; rank < depth; rank++) {
        _paintElement(canvas, paintOrder[rank]);
      }
      _paintDraft(canvas, waiting, hovered);
      for (var rank = depth; rank < paintOrder.length; rank++) {
        _paintElement(canvas, paintOrder[rank]);
      }
      canvas
        ..restore()
        ..restore();
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (waiting != null) {
      // The little circle of the first click, and the one that follows the
      // pointer, in the colours of the picture of the tool.
      final colours = waiting.kind == VectorKind.ellipse
          ? ShapeMarkColours.oval
          : ShapeMarkColours.line;
      final end = anchorDrawn
          ? (draft.points.length == 2 ? draft.points.last : null)
          : hovered;
      if (end != null) _mark(canvas, end, colours.end);
      _mark(canvas, waiting.start, colours.start);
    }
    if (selectionBounds != null) {
      final bounds = selectionBounds!.shift(selectionOffset.value);
      final screenBounds = Rect.fromLTRB(
        viewport.left + bounds.left * viewport.scale,
        viewport.top + bounds.top * viewport.scale,
        viewport.left + bounds.right * viewport.scale,
        viewport.top + bounds.bottom * viewport.scale,
      ).inflate(5);
      final outline = RRect.fromRectAndRadius(
        screenBounds,
        const Radius.circular(5),
      );
      canvas.drawRRect(
        outline,
        Paint()
          ..color = const Color(0xdfffffff)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
      canvas.drawRRect(
        outline,
        Paint()
          ..color = studioGreen
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }

  // The element at [index] of [strokes], the chosen one where the pointer
  // is taking it.
  void _paintElement(Canvas canvas, int index) {
    if (index == selectedIndex) {
      canvas.save();
      canvas.translate(selectionOffset.value.dx, selectionOffset.value.dy);
      strokes[index].paint(canvas);
      canvas.restore();
    } else {
      strokes[index].paint(canvas);
    }
  }

  // What is being drawn on the active layer: the trait or the shape that
  // the pointer is making, and the shape that two clicks are making, as far
  // as the pointer [hovered] now is from the first click [waiting].
  void _paintDraft(
    Canvas canvas,
    ShapeAnchor? waiting,
    DocumentPoint? hovered,
  ) {
    final drawn = draft;
    final stroke = drawn.stroke;
    final points = drawn.points;
    if (stroke != null && points.isNotEmpty) {
      if (drawn.kind == VectorKind.stroke) {
        void trait() {
          if (drawn.marks.isNotEmpty || drawn.tool.paintsMarks) {
            for (final (path, paint) in drawn.marks) {
              canvas.drawPath(path, paint);
            }
          } else {
            _drawStroke(
              canvas,
              stroke,
              Offset(points.first.x, points.first.y),
              points.length == 1,
              Color(0xff000000 | drawn.rgb),
              drawn.width,
              felt: drawn.tool == BrushTool.felt,
            );
          }
        }

        trait();
        final mirror = drawn.mirrorWidth;
        if (mirror != null) {
          canvas.save();
          canvas.translate(mirror, 0);
          canvas.scale(-1, 1);
          trait();
          canvas.restore();
        }
      } else if (drawn.kind == VectorKind.contour) {
        final shape = drawn.shape;
        if (shape != null &&
            isUsableShape(drawn.kind, points.first, points.last)) {
          RenderedElement(
            StrokeData(
              RustDocument.shapeOutline(shape, points.first, points.last),
              drawn.rgb,
              drawn.width,
              kind: VectorKind.contour,
              fillRgb: drawn.fillRgb,
            ),
          ).paint(canvas);
        }
      } else if (isUsableShape(drawn.kind, points.first, points.last)) {
        RenderedElement(
          drawn.kind == VectorKind.stamp
              ? StrokeData(
                  points,
                  drawn.rgb,
                  1,
                  kind: VectorKind.stamp,
                  stamp: drawn.stamp,
                  look: drawn.stampLook,
                )
              : StrokeData(
                  points,
                  drawn.rgb,
                  drawn.width,
                  kind: drawn.kind,
                  fillRgb: drawn.fillRgb,
                ),
        ).paint(canvas);
      }
    }
    if (waiting != null &&
        hovered != null &&
        isUsableShape(waiting.kind, waiting.start, hovered)) {
      RenderedElement(
        StrokeData(
          waiting.kind == VectorKind.contour
              ? RustDocument.shapeOutline(anchorShape, waiting.start, hovered)
              : [waiting.start, hovered],
          anchorRgb,
          anchorWidth,
          kind: waiting.kind,
          fillRgb: anchorFillRgb,
        ),
      ).paint(canvas);
    }
  }

  void _drawStroke(
    Canvas canvas,
    DraftStroke stroke,
    Offset first,
    bool single,
    Color color,
    double width, {
    bool felt = false,
  }) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (single) {
      if (felt) {
        canvas.drawRect(
          Rect.fromCircle(center: first, radius: width / 2),
          paint..color = color.withAlpha(markerAlpha),
        );
      } else {
        canvas.drawCircle(first, width / 2, paint);
      }
      return;
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = felt ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = felt ? StrokeJoin.bevel : StrokeJoin.round;
    // The marker shows through, the trait once: its pieces are painted
    // opaque together, then laid on the sheet at the marker's opacity.
    if (felt) {
      canvas.saveLayer(null, Paint()..color = color.withAlpha(markerAlpha));
    }
    for (final piece in stroke.pieces) {
      canvas.drawPath(piece, paint);
    }
    if (felt) canvas.restore();
  }

  @override
  bool shouldRepaint(DocumentPainter old) =>
      old.revision != revision ||
      old.draftDepth != draftDepth ||
      !identical(old.background, background) ||
      old.viewport.scale != viewport.scale ||
      old.viewport.left != viewport.left ||
      old.viewport.top != viewport.top ||
      // The shape between two clicks is drawn with the choices of the
      // moment: a colour clicked meanwhile shows at once.
      !identical(old.anchor, anchor) ||
      old.anchorDrawn != anchorDrawn ||
      old.anchorRgb != anchorRgb ||
      old.anchorWidth != anchorWidth ||
      old.anchorFillRgb != anchorFillRgb ||
      old.anchorShape != anchorShape ||
      !identical(old.images, images) ||
      old.pixelRatio != pixelRatio ||
      old.viewMoving != viewMoving;
}

class ToolPreviewPainter extends CustomPainter {
  ToolPreviewPainter(
    this.color,
    this.width,
    this.kind,
    this.fillColor, {
    this.shape = NewShape.star,
  });
  final VectorKind kind;
  final Color? fillColor;
  final Color color;
  final double width;

  /// The shape shown for a contour, the kind « Formes » draws.
  final NewShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    if (kind != VectorKind.stroke) {
      final a = DocumentPoint(size.width * .2, size.height * .25);
      final b = DocumentPoint(size.width * .8, size.height * .75);
      List<DocumentPoint> points;
      if (kind == VectorKind.contour) {
        try {
          points = RustDocument.shapeOutline(shape, a, b);
        } catch (_) {
          // Without the core there is nothing exact to show.
          return;
        }
      } else {
        points = [a, b];
      }
      RenderedElement(
        StrokeData(
          points,
          color.toARGB32() & 0xffffff,
          (width / 2).clamp(2, 8).toDouble(),
          kind: kind,
          fillRgb: fillColor != null && kind != VectorKind.line
              ? fillColor!.toARGB32() & 0xffffff
              : null,
        ),
      ).paint(canvas);
      return;
    }
    final path = Path()
      ..moveTo(size.width * .13, size.height * .66)
      ..cubicTo(
        size.width * .4,
        -size.height * .02,
        size.width * .37,
        size.height * 1.02,
        size.width * .63,
        size.height * .35,
      )
      ..quadraticBezierTo(
        size.width * .75,
        size.height * .1,
        size.width * .87,
        size.height * .47,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width.clamp(2, 21).toDouble()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(ToolPreviewPainter old) =>
      color != old.color ||
      width != old.width ||
      kind != old.kind ||
      fillColor != old.fillColor ||
      shape != old.shape;
}

/// The pointer of the keyboard or the gamepad (Color 1.1): a ring with a
/// cross, filled while it is pressed.
class KeyPointerPainter extends CustomPainter {
  const KeyPointerPainter({required this.pressed});
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    final halo = Paint()
      ..color = const Color(0xffffffff)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    final ink = Paint()
      ..color = studioGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(centre, radius, halo);
    canvas.drawCircle(centre, radius, ink);
    for (final (a, b) in [
      (
        Offset(centre.dx - radius - 3, centre.dy),
        Offset(centre.dx - 4, centre.dy),
      ),
      (
        Offset(centre.dx + 4, centre.dy),
        Offset(centre.dx + radius + 3, centre.dy),
      ),
      (
        Offset(centre.dx, centre.dy - radius - 3),
        Offset(centre.dx, centre.dy - 4),
      ),
      (
        Offset(centre.dx, centre.dy + 4),
        Offset(centre.dx, centre.dy + radius + 3),
      ),
    ]) {
      canvas.drawLine(a, b, halo);
      canvas.drawLine(a, b, ink);
    }
    if (pressed) {
      canvas.drawCircle(centre, radius / 2, Paint()..color = studioGreen);
    }
  }

  @override
  bool shouldRepaint(KeyPointerPainter old) => old.pressed != pressed;
}
