// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'rust_document.dart';
import 'stamp_catalog.dart';
import 'text_layout.dart';

/// The opacity of the marker (felt): strokes laid over each other show
/// through, as the core's SVG says (MARKER_ALPHA).
const int markerAlpha = 217;

/// The stops of a gradient: as many as the SVG export writes.
const int gradientStops = 9;

/// The matrix that turns and mirrors an object as the core does: about the
/// centre of its box, the mirror first. Null when it does neither.
Float64List? objectTransform(ObjectLook look, Rect box) {
  if (!look.transforms) return null;
  final c = box.center;
  final cos = math.cos(look.rotation);
  final sin = math.sin(look.rotation);
  final sx = look.mirrorX ? -1.0 : 1.0;
  final sy = look.mirrorY ? -1.0 : 1.0;
  // p' = c + R·S·(p − c), column-major for Canvas.transform.
  final a = cos * sx, b = sin * sx, cc = -sin * sy, d = cos * sy;
  final tx = c.dx - a * c.dx - cc * c.dy;
  final ty = c.dy - b * c.dx - d * c.dy;
  return Float64List.fromList([
    a, b, 0, 0, //
    cc, d, 0, 0,
    0, 0, 1, 0,
    tx, ty, 0, 1,
  ]);
}

/// Where point [p] of the sheet is in the object's own drawing, before its
/// turn and mirror: what a hit test asks.
Offset untransformedPoint(ObjectLook look, Rect box, Offset p) {
  if (!look.transforms) return p;
  final c = box.center;
  final cos = math.cos(look.rotation);
  final sin = math.sin(look.rotation);
  final (dx, dy) = (p.dx - c.dx, p.dy - c.dy);
  // R⁻¹ then S⁻¹ (S is its own inverse).
  var u = dx * cos + dy * sin;
  var v = -dx * sin + dy * cos;
  if (look.mirrorX) u = -u;
  if (look.mirrorY) v = -v;
  return Offset(c.dx + u, c.dy + v);
}

/// The box that holds [box] once turned and mirrored as [look] says.
Rect transformedBounds(ObjectLook look, Rect box, [Rect? about]) {
  if (!look.transforms) return box;
  final centre = (about ?? box).center;
  final cos = math.cos(look.rotation);
  final sin = math.sin(look.rotation);
  var left = double.infinity, top = double.infinity;
  var right = double.negativeInfinity, bottom = double.negativeInfinity;
  for (final corner in [
    box.topLeft,
    box.topRight,
    box.bottomLeft,
    box.bottomRight,
  ]) {
    var u = corner.dx - centre.dx;
    var v = corner.dy - centre.dy;
    if (look.mirrorX) u = -u;
    if (look.mirrorY) v = -v;
    final x = centre.dx + u * cos - v * sin;
    final y = centre.dy + u * sin + v * cos;
    left = math.min(left, x);
    right = math.max(right, x);
    top = math.min(top, y);
    bottom = math.max(bottom, y);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// The paint of the inside of a filled shape: its colour, or its gradient
/// through Oklab, over the box of its points as SVG's objectBoundingBox.
Paint insidePaint(StrokeData data, Rect box) {
  final paint = Paint()
    ..color = Color(0xff000000 | data.fillRgb!)
    ..isAntiAlias = true;
  final look = data.look;
  if (!look.hasGradient || box.width == 0 || box.height == 0) return paint;
  final colours = _gradientColours(data.fillRgb!, look.gradientRgb);
  final stops = [
    for (var i = 0; i < gradientStops; i++) i / (gradientStops - 1),
  ];
  final unitToBox = Float64List.fromList([
    box.width, 0, 0, 0, //
    0, box.height, 0, 0,
    0, 0, 1, 0,
    box.left, box.top, 0, 1,
  ]);
  final [x0, y0, x1, y1] = look.gradientPoints;
  paint.shader = look.gradient == GradientKind.linear
      ? Gradient.linear(
          Offset(x0, y0),
          Offset(x1, y1),
          colours,
          stops,
          TileMode.clamp,
          unitToBox,
        )
      : Gradient.radial(
          Offset(x0, y0),
          math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)),
          colours,
          stops,
          TileMode.clamp,
          unitToBox,
        );
  return paint;
}

// The colours of a gradient, asked of the core once for each pair.
final _gradients = <(int, int), List<Color>>{};

List<Color> _gradientColours(int a, int b) {
  final known = _gradients[(a, b)];
  if (known != null) return known;
  if (_gradients.length > 256) _gradients.clear();
  return _gradients[(a, b)] = List.unmodifiable([
    for (final rgb in RustDocument.gradientColours(a, b, gradientStops))
      Color(0xff000000 | rgb),
  ]);
}

/// The marks of a stroke as paths, one for each group of marks of one colour
/// and opacity, as the SVG export writes them.
List<(Path, Paint)> markPaths(ObjectMarks marks, {int end = -1}) {
  final count = end < 0 ? marks.length : math.min(end, marks.length);
  final groups = <(Path, Paint)>[];
  final p = marks.points;
  var start = 0;
  while (start < count) {
    final group = marks.groups[start];
    final path = Path();
    var index = start;
    while (index < count && marks.groups[index] == group) {
      final first = marks.firsts[index] * 2;
      if (marks.shapes[index] == 1) {
        path.addOval(
          Rect.fromCircle(
            center: Offset(p[first], p[first + 1]),
            radius: marks.radii[index],
          ),
        );
      } else {
        path.moveTo(p[first], p[first + 1]);
        for (var k = 1; k < marks.counts[index]; k++) {
          path.lineTo(p[first + 2 * k], p[first + 2 * k + 1]);
        }
        path.close();
      }
      index++;
    }
    groups.add((
      path,
      Paint()
        ..color = Color(marks.alphas[start] << 24 | marks.rgbs[start])
        ..isAntiAlias = true,
    ));
    start = index;
  }
  return groups;
}

/// A private cached path and paints, independent of the Rust document handle.
/// The caller supplies the document transform and paper clip before painting.
final class RenderedElement {
  factory RenderedElement(StrokeData data) {
    final points = data.points;
    // x then y of each point: the loops below read them in place.
    final c = data.coordinates;
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
    for (var i = 0; i < c.length; i += 2) {
      final x = c[i];
      final y = c[i + 1];
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
          TextLayout(text, size: data.width, rgb: data.rgb, font: data.font),
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
    final first = Offset(c[0], c[1]);
    final path = Path();
    final stroke = Paint()
      ..color = Color(0xff000000 | data.rgb)
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = data.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Paint? fill;
    if (data.kind == VectorKind.stroke) {
      if (data.fillRgb != null) {
        throw ArgumentError('Un trait ne peut pas avoir de remplissage.');
      }
      if (!data.marks.isEmpty) {
        // Chalk, airbrush, calligraphy, the magic tools, a pressed stroke:
        // the marks the core made, the same every time.
        return RenderedElement._marks(
          data,
          controlBounds,
          markPaths(data.marks),
        );
      }
      if (data.look.tool == BrushTool.felt) {
        stroke
          ..color = Color(markerAlpha << 24 | data.rgb)
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.bevel;
      }
      if (points.length == 1) {
        if (data.look.tool == BrushTool.felt) {
          path.addRect(Rect.fromCircle(center: first, radius: data.width / 2));
        } else {
          path.addOval(Rect.fromCircle(center: first, radius: data.width / 2));
        }
        stroke.style = PaintingStyle.fill;
      } else {
        path.moveTo(first.dx, first.dy);
        for (var i = 2; i < c.length; i += 2) {
          path.lineTo(c[i], c[i + 1]);
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
      final rings = data.rings;
      if (rings == null) {
        path.moveTo(first.dx, first.dy);
        for (var i = 2; i < c.length; i += 2) {
          path.lineTo(c[i], c[i + 1]);
        }
        path.close();
      } else {
        // The zone of the paint pot: an outer ring and its holes, even-odd.
        path.fillType = PathFillType.evenOdd;
        var at = 0;
        for (final ring in rings) {
          path.moveTo(c[2 * at], c[2 * at + 1]);
          for (var k = 1; k < ring; k++) {
            path.lineTo(c[2 * (at + k)], c[2 * (at + k) + 1]);
          }
          path.close();
          at += ring;
        }
      }
      fill = data.fillRgb == null ? null : insidePaint(data, controlBounds);
    } else {
      if (points.length != 2) {
        throw ArgumentError('Une forme nécessite deux points.');
      }
      final last = Offset(c[2], c[3]);
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
          fill = data.fillRgb == null ? null : insidePaint(data, bounds);
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
      _stamp = null,
      _markGroups = null,
      _transform = objectTransform(data.look, controlBounds);

  RenderedElement._box(this.data, this.controlBounds, this._text, this._stamp)
    : _path = null,
      _stroke = null,
      _fill = null,
      _markGroups = null,
      _transform = objectTransform(data.look, controlBounds);

  RenderedElement._marks(this.data, this.controlBounds, this._markGroups)
    : _path = null,
      _stroke = null,
      _fill = null,
      _text = null,
      _stamp = null,
      _transform = objectTransform(data.look, controlBounds);
  final StrokeData data;

  /// The paths of the marks of a stroke, by group; null for other elements.
  final List<(Path, Paint)>? _markGroups;

  /// The turn and mirror of the element about the centre of its box; null
  /// when it has neither.
  final Float64List? _transform;

  /// The box of the element as the sheet shows it, turned and mirrored.
  Rect get shownBounds => transformedBounds(data.look, controlBounds);

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
    final transform = _transform;
    if (transform != null) {
      canvas.save();
      canvas.transform(transform);
    }
    _paintUntransformed(canvas);
    if (transform != null) canvas.restore();
  }

  void _paintUntransformed(Canvas canvas) {
    final marks = _markGroups;
    if (marks != null) {
      for (final (path, paint) in marks) {
        canvas.drawPath(path, paint);
      }
      return;
    }
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
    final transform = _transform;
    if (transform != null) {
      canvas.save();
      canvas.transform(transform);
    }
    _paintProgressUntransformed(canvas, progress, overshoot);
    if (transform != null) canvas.restore();
  }

  void _paintProgressUntransformed(
    Canvas canvas,
    double progress,
    bool overshoot,
  ) {
    if (_markGroups != null) {
      // The marks appear in the order of the stroke.
      final marks = data.marks;
      for (final (path, paint) in markPaths(
        marks,
        end: (marks.length * progress).ceil(),
      )) {
        canvas.drawPath(path, paint);
      }
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
    final transform = _transform;
    if (transform != null) {
      canvas.save();
      canvas.transform(transform);
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
    if (transform != null) canvas.restore();
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
    final lineHeight = text.lineHeight * text.size;
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
