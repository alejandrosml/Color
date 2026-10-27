// SPDX-License-Identifier: MIT
// Painters of the studio: the sheet with its drawing, and the small example
// of the inspector. They read prepared elements and never touch the document.
import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';

import 'child_art.dart' show ShapeMarkColours;
import 'document_renderer.dart';
import 'drawing_gesture.dart';
import 'rust_document.dart';
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

class DocumentPainter extends CustomPainter {
  DocumentPainter({
    required this.viewport,
    required this.paperRgb,
    required this.background,
    required this.strokes,
    required this.paintOrder,
    required this.draftStamp,
    required this.draft,
    required this.draftPoints,
    required Listenable repaint,
    required this.draftColor,
    required this.draftWidth,
    required this.draftKind,
    required this.draftFillRgb,
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
  }) : super(repaint: repaint);
  final DocumentViewport viewport;

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
  final int draftStamp;
  final Path? draft;
  final List<DocumentPoint> draftPoints;
  final VectorKind draftKind;
  final int? draftFillRgb;
  final int draftColor;
  final double draftWidth;
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

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final rect = Rect.fromLTWH(
      viewport.left,
      viewport.top,
      viewport.width,
      viewport.height,
    );
    canvas.drawShadow(Path()..addRect(rect), const Color(0x3323402c), 5, true);
    canvas.drawRect(rect, Paint()..color = Color(0xff000000 | paperRgb));
    canvas.save();
    canvas.translate(viewport.left, viewport.top);
    canvas.scale(viewport.scale);
    canvas.clipRect(
      Rect.fromLTWH(0, 0, viewport.documentWidth, viewport.documentHeight),
    );
    final image = background;
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, viewport.documentWidth, viewport.documentHeight),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    final waiting = anchor;
    final hovered = anchorDrawn ? null : waiting?.end;
    // The layers up to the active one, what is being drawn on it, then the
    // layers above it.
    final depth = (draftDepth ?? paintOrder.length).clamp(0, paintOrder.length);
    for (var rank = 0; rank < depth; rank++) {
      _paintElement(canvas, paintOrder[rank]);
    }
    _paintDraft(canvas, waiting, hovered);
    for (var rank = depth; rank < paintOrder.length; rank++) {
      _paintElement(canvas, paintOrder[rank]);
    }
    canvas.restore();
    if (waiting != null) {
      // The little circle of the first click, and the one that follows the
      // pointer, in the colours of the picture of the tool.
      final colours = waiting.kind == VectorKind.ellipse
          ? ShapeMarkColours.oval
          : ShapeMarkColours.line;
      final end = anchorDrawn
          ? (draftPoints.length == 2 ? draftPoints.last : null)
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
    if (draft != null && draftPoints.isNotEmpty) {
      if (draftKind == VectorKind.stroke) {
        _drawStroke(
          canvas,
          draft!,
          Offset(draftPoints.first.x, draftPoints.first.y),
          draftPoints.length == 1,
          Color(0xff000000 | draftColor),
          draftWidth,
        );
      } else if (isUsableShape(
        draftKind,
        draftPoints.first,
        draftPoints.last,
      )) {
        RenderedElement(
          draftKind == VectorKind.stamp
              ? StrokeData(
                  draftPoints,
                  draftColor,
                  1,
                  kind: VectorKind.stamp,
                  stamp: draftStamp,
                )
              : StrokeData(
                  draftPoints,
                  draftColor,
                  draftWidth,
                  kind: draftKind,
                  fillRgb: draftFillRgb,
                ),
        ).paint(canvas);
      }
    }
    if (waiting != null &&
        hovered != null &&
        isUsableShape(waiting.kind, waiting.start, hovered)) {
      RenderedElement(
        StrokeData(
          [waiting.start, hovered],
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
    Path path,
    Offset first,
    bool single,
    Color color,
    double width,
  ) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (single) {
      canvas.drawCircle(first, width / 2, paint);
      return;
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
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
      old.anchorFillRgb != anchorFillRgb;
}

class ToolPreviewPainter extends CustomPainter {
  ToolPreviewPainter(this.color, this.width, this.kind, this.fillColor);
  final VectorKind kind;
  final Color? fillColor;
  final Color color;
  final double width;
  @override
  void paint(Canvas canvas, Size size) {
    if (kind != VectorKind.stroke) {
      RenderedElement(
        StrokeData(
          [
            DocumentPoint(size.width * .2, size.height * .25),
            DocumentPoint(size.width * .8, size.height * .75),
          ],
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
      fillColor != old.fillColor;
}
