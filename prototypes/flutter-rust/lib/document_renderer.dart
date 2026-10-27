// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'dart:ui';

import 'rust_document.dart';
import 'stamp_catalog.dart';
import 'text_layout.dart';

/// A private cached path and paints, independent of the Rust document handle.
/// The caller supplies the document transform and paper clip before painting.
final class RenderedElement {
  factory RenderedElement(StrokeData data) {
    final points = data.points;
    final (minimumWidth, maximumWidth) = switch (data.kind) {
      VectorKind.text => (minTextSize, maxTextSize),
      VectorKind.stamp => (1.0, 1.0),
      _ => (0.1, 512.0),
    };
    if (points.isEmpty ||
        points.length > 100000 ||
        !data.width.isFinite ||
        data.width < minimumWidth ||
        data.width > maximumWidth ||
        data.rgb < 0 ||
        data.rgb > 0xffffff ||
        (data.fillRgb != null &&
            (data.fillRgb! < 0 || data.fillRgb! > 0xffffff))) {
      throw ArgumentError('Un élément du dessin est invalide.');
    }
    // Keep the same validation traversal; prepare selection geometry here too.
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final point in points) {
      final x = point.x;
      final y = point.y;
      if (!x.isFinite || !y.isFinite) {
        throw ArgumentError('Un élément du dessin est invalide.');
      }
      left = math.min(left, x);
      right = math.max(right, x);
      top = math.min(top, y);
      bottom = math.max(bottom, y);
    }
    final controlBounds = Rect.fromLTRB(left, top, right, bottom);
    if (data.kind.isBoxObject) {
      if (points.length != 2 ||
          data.fillRgb != null ||
          controlBounds.width == 0 ||
          controlBounds.height == 0) {
        throw ArgumentError('Un élément du dessin est invalide.');
      }
      if (data.kind == VectorKind.text) {
        final text = data.text;
        if (text == null || text.isEmpty) {
          throw ArgumentError('Un texte doit contenir des caractères.');
        }
        return RenderedElement._box(
          data,
          controlBounds,
          TextLayout(text, size: data.width, rgb: data.rgb),
          null,
        );
      }
      final stamp = data.stamp == null
          ? null
          : StampCatalog.instance[data.stamp!];
      if (stamp == null) {
        throw ArgumentError('Ce tampon est inconnu.');
      }
      return RenderedElement._box(data, controlBounds, null, stamp);
    }
    if (data.text != null || data.stamp != null) {
      throw ArgumentError('Un élément du dessin est invalide.');
    }
    final first = Offset(points.first.x, points.first.y);
    final path = Path();
    final stroke = Paint()
      ..color = Color(0xff000000 | data.rgb)
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = data.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // The inside of a shape, painted before its outline.
    Paint? insideOf(int? rgb) => rgb == null
        ? null
        : (Paint()
            ..color = Color(0xff000000 | rgb)
            ..isAntiAlias = true);
    Paint? fill;
    if (data.kind == VectorKind.stroke) {
      if (data.fillRgb != null) {
        throw ArgumentError('Un trait ne peut pas avoir de remplissage.');
      }
      if (points.length == 1) {
        path.addOval(Rect.fromCircle(center: first, radius: data.width / 2));
        stroke.style = PaintingStyle.fill;
      } else {
        path.moveTo(first.dx, first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.x, point.y);
        }
      }
    } else if (data.kind == VectorKind.contour) {
      // A closed polygon, the last point joined to the first. Its inside
      // follows the nonzero rule, the default of a path as of SVG.
      if (points.length < 3) {
        throw ArgumentError('Un contour nécessite au moins trois points.');
      }
      if (controlBounds.width == 0 || controlBounds.height == 0) {
        throw ArgumentError(
          'La largeur et la hauteur doivent être non nulles.',
        );
      }
      path.moveTo(first.dx, first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.x, point.y);
      }
      path.close();
      fill = insideOf(data.fillRgb);
    } else {
      if (points.length != 2) {
        throw ArgumentError('Une forme nécessite deux points.');
      }
      final last = Offset(points.last.x, points.last.y);
      if (first == last) {
        throw ArgumentError('Une forme doit avoir une taille non nulle.');
      }
      switch (data.kind) {
        case VectorKind.line:
          if (data.fillRgb != null) {
            throw ArgumentError('Une ligne ne peut pas avoir de remplissage.');
          }
          path.moveTo(first.dx, first.dy);
          path.lineTo(last.dx, last.dy);
        case VectorKind.rectangle:
        case VectorKind.ellipse:
          final bounds = Rect.fromPoints(first, last);
          if (bounds.width == 0 || bounds.height == 0) {
            throw ArgumentError(
              'La largeur et la hauteur doivent être non nulles.',
            );
          }
          if (data.kind == VectorKind.rectangle) {
            path.addRect(bounds);
          } else {
            path.addOval(bounds);
          }
          fill = insideOf(data.fillRgb);
        case VectorKind.stroke:
        case VectorKind.text:
        case VectorKind.stamp:
        case VectorKind.contour:
          throw StateError('Cet élément a déjà été préparé.');
      }
    }
    return RenderedElement._(data, controlBounds, path, stroke, fill);
  }

  RenderedElement._(
    this.data,
    this.controlBounds,
    Path this._path,
    Paint this._stroke,
    this._fill,
  ) : _text = null,
      _stamp = null;

  RenderedElement._box(this.data, this.controlBounds, this._text, this._stamp)
    : _path = null,
      _stroke = null,
      _fill = null;
  final StrokeData data;

  /// Control-point bounds observed when this element was prepared, without the
  /// painted stroke width. Fresh for the studio's immutable Rust snapshots;
  /// not a live view of arbitrary StrokeData/DocumentPoint subclasses.
  final Rect controlBounds;
  final Path? _path;
  final Paint? _stroke;
  final Paint? _fill;

  /// Laid-out lines of a text; they start at the box's top-left corner.
  final TextLayout? _text;

  /// Shared catalogue artwork of a stamp, scaled into the box when painted.
  final StampArt? _stamp;

  void paint(Canvas canvas) {
    final text = _text;
    if (text != null) {
      text.paint(canvas, controlBounds.topLeft);
      return;
    }
    final stamp = _stamp;
    if (stamp != null) {
      stamp.paint(canvas, controlBounds, data.rgb);
      return;
    }
    final path = _path!;
    final fill = _fill;
    if (fill != null) canvas.drawPath(path, fill);
    canvas.drawPath(path, _stroke!);
  }

  /// The share of its time that a filled shape spends on its outline; its
  /// inside appears during the rest.
  static const _outlineShare = .7;

  /// The measure of the only contour of [_path], asked once: the film of
  /// the drawing cuts a piece of it for every frame, and measuring a long
  /// trait again each time would walk all its points. Null for a text, a
  /// stamp, and a trait whose points all lie at one place.
  late final PathMetric? _contour = _measureContour();

  PathMetric? _measureContour() {
    final path = _path;
    if (path == null) return null;
    for (final metric in path.computeMetrics()) {
      if (metric.length > 0) return metric;
    }
    return null;
  }

  /// Paints the element as far as the film of the drawing has redrawn it:
  /// nothing at 0, and from 1 on exactly what [paint] paints. In between, a
  /// trait and a line grow from their first point, a dot grows from its
  /// centre, a shape gets its outline and then its inside, a text is written
  /// line after line and a stamp grows from the centre of its box, a little
  /// past its size on the way when [overshoot] allows it.
  ///
  /// Called for every frame of the element being drawn: the path was
  /// measured once, and a frame makes no more than the piece of it to draw.
  void paintProgress(Canvas canvas, double progress, {bool overshoot = true}) {
    // A progress that is not a number paints nothing either.
    if (!(progress > 0)) return;
    if (progress >= 1) {
      paint(canvas);
      return;
    }
    final text = _text;
    if (text != null) {
      _writeText(canvas, text, progress);
      return;
    }
    final stamp = _stamp;
    if (stamp != null) {
      if (_scaleAroundCentre(
        canvas,
        overshoot ? _easeOutBack(progress) : _easeOut(progress),
      )) {
        stamp.paint(canvas, controlBounds, data.rgb);
        canvas.restore();
      }
      return;
    }
    final path = _path!;
    final stroke = _stroke!;
    if (stroke.style == PaintingStyle.fill) {
      // A dot: the only trait whose paint fills, the disc itself.
      canvas.drawCircle(
        controlBounds.center,
        stroke.strokeWidth / 2 * progress,
        stroke,
      );
      return;
    }
    final fill = _fill;
    if (fill == null || progress < _outlineShare) {
      final contour = _contour;
      if (contour == null) {
        // A trait that goes nowhere: its round ends make a disc of it.
        if (_scaleAroundCentre(canvas, progress)) {
          canvas.drawPath(path, stroke);
          canvas.restore();
        }
        return;
      }
      // The round end of the paint is the tip of the brush as it advances.
      final drawn = fill == null ? progress : progress / _outlineShare;
      canvas.drawPath(contour.extractPath(0, contour.length * drawn), stroke);
      return;
    }
    // The outline is closed; the inside appears under it, where [paint]
    // puts it.
    canvas.drawPath(
      path,
      Paint()
        ..color = fill.color.withValues(
          alpha: (progress - _outlineShare) / (1 - _outlineShare),
        )
        ..isAntiAlias = true,
    );
    canvas.drawPath(path, stroke);
  }

  /// Paints a zone of a colouring page as the film shows it taking the
  /// colour of the paint pot: at 0 with its inside [fromRgb], the white of
  /// the page, and from 1 on exactly what [paint] paints. In between, the
  /// colour spreads from the middle of its box to its edges, inside its
  /// outline, as poured paint would. An element without an inside has no
  /// colour to take: it is painted whole.
  void paintRecolouring(
    Canvas canvas,
    double progress, {
    required int fromRgb,
  }) {
    final path = _path;
    final fill = _fill;
    if (progress >= 1 || path == null || fill == null) {
      paint(canvas);
      return;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Color(0xff000000 | fromRgb)
        ..isAntiAlias = true,
    );
    // A progress that is not a number spreads nothing.
    if (progress > 0) {
      final box = controlBounds;
      // From the middle of the box, as far as its corners at the end.
      final corner = math.sqrt(box.width * box.width + box.height * box.height);
      canvas.save();
      canvas.clipPath(path);
      canvas.drawCircle(box.center, corner / 2 * _easeOut(progress), fill);
      canvas.restore();
    }
    canvas.drawPath(path, _stroke!);
  }

  // Saves the canvas and scales it around the centre of the box; the caller
  // paints and restores. False, with nothing saved, for a scale that leaves
  // nothing to see: a canvas scaled to nothing cannot be painted on.
  bool _scaleAroundCentre(Canvas canvas, double scale) {
    if (!(scale > 0)) return false;
    final centre = controlBounds.center;
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(scale);
    canvas.translate(-centre.dx, -centre.dy);
    return true;
  }

  // Writes the lines one after the other, each from its left: the lines
  // above the one being written are whole. Each line takes the share of the
  // time that its width is of all the widths, as a hand that writes evenly.
  void _writeText(Canvas canvas, TextLayout text, double progress) {
    final widths = text.lineWidths;
    var total = 0.0;
    for (final width in widths) {
      total += width;
    }
    if (total <= 0) return;
    var written = progress * total;
    var line = 0;
    while (line < widths.length - 1 && written >= widths[line]) {
      written -= widths[line];
      line++;
    }
    final origin = controlBounds.topLeft;
    final lineHeight = colorTextLineHeight * text.size;
    final top = origin.dy + line * lineHeight;
    // Around the box, room for what a letter may paint outside it.
    final margin = text.size / 2;
    if (line > 0) {
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(
          origin.dx - margin,
          origin.dy - margin,
          origin.dx + text.width + margin,
          top,
        ),
      );
      text.paint(canvas, origin);
      canvas.restore();
    }
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        origin.dx - margin,
        line == 0 ? top - margin : top,
        origin.dx + written,
        line == widths.length - 1
            ? top + lineHeight + margin
            : top + lineHeight,
      ),
    );
    text.paint(canvas, origin);
    canvas.restore();
  }
}

// Fast first, then slower: the size of a stamp that grows without a bounce.
double _easeOut(double t) {
  final rest = 1 - t;
  return 1 - rest * rest * rest;
}

// The same, a tenth past the size on the way and back: a small bounce.
double _easeOutBack(double t) {
  const back = 1.70158;
  final rest = t - 1;
  return 1 + (back + 1) * rest * rest * rest + back * rest * rest;
}
