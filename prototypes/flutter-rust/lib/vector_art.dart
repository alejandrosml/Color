// SPDX-License-Identifier: MIT
// Pictures kept as SVG files. The Rust core reads the files and describes
// each one as a short list of drawing instructions; this file reads that
// description once and paints it with the engine of the interface, at any
// size. Nothing here knows SVG: see src/art.rs of the core for the format.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'rust_document.dart';

const _unreadable = FormatException('Dessin de l’interface illisible.');

sealed class _Instruction {
  const _Instruction();
}

/// One outline with what paints it.
final class _Draw extends _Instruction {
  const _Draw(this.path, this.fill, this.stroke, this.strokeFirst);
  final Path path;
  final Paint? fill;
  final Paint? stroke;
  final bool strokeFirst;
}

/// The beginning of a group: what it holds is placed, clipped and, when the
/// group is not opaque, painted as a whole before it is laid on the rest.
final class _Open extends _Instruction {
  _Open(this.opacity, this.matrix);
  final double opacity;
  final Float64List? matrix;
  final clips = <Path>[];
}

final class _Close extends _Instruction {
  const _Close();
}

/// One picture: its size, and how to paint it.
class VectorPicture {
  VectorPicture._(this.key, this.width, this.height, this._instructions);

  /// The name of its file without `.svg`; `-` for a picture read on request.
  final String key;
  final double width;
  final double height;
  final List<_Instruction> _instructions;

  /// The pictures of one description text, in its order.
  static List<VectorPicture> parseAll(String text) {
    final pictures = <VectorPicture>[];
    String? key;
    var width = 0.0;
    var height = 0.0;
    var instructions = <_Instruction>[];
    final open = <_Open>[];
    // The outlines of the clip being read, to be joined when it ends.
    List<Path>? clip;
    void endClip() {
      final outlines = clip;
      if (outlines == null) return;
      clip = null;
      // Together the outlines are the clip; none hides everything.
      var whole = outlines.isEmpty ? Path() : outlines.first;
      for (final outline in outlines.skip(1)) {
        whole = Path.combine(PathOperation.union, whole, outline);
      }
      open.last.clips.add(whole);
    }

    for (final line in text.split('\n')) {
      if (line.isEmpty) continue;
      final letter = line[0];
      if (line.length > 1 && line[1] != ' ') throw _unreadable;
      if (letter == 'P') {
        final fields = line.split(' ');
        if (key != null || fields.length != 4 || fields[1].isEmpty) {
          throw _unreadable;
        }
        key = fields[1];
        width = _number(fields[2]);
        height = _number(fields[3]);
        if (width <= 0 || height <= 0) throw _unreadable;
        continue;
      }
      if (key == null) throw _unreadable;
      if (letter != 'K' && letter != 'C') endClip();
      switch (letter) {
        case 'G':
          final fields = line.split(' ');
          if (fields.length != 3) throw _unreadable;
          final opacity = _number(fields[1]);
          if (opacity < 0 || opacity > 1) throw _unreadable;
          final group = _Open(opacity, _matrix(fields[2]));
          open.add(group);
          instructions.add(group);
        case 'C':
          // A clip belongs to the group that was just opened.
          if (open.isEmpty || !identical(instructions.last, open.last)) {
            throw _unreadable;
          }
          endClip();
          clip = [];
        case 'K':
          final outlines = clip;
          final fields = _fields(line, 3);
          if (outlines == null) throw _unreadable;
          outlines.add(_path(fields[2])..fillType = _rule(fields[1]));
        case 'E':
          if (open.isEmpty || line.length != 1) throw _unreadable;
          open.removeLast();
          instructions.add(const _Close());
        case 'D':
          instructions.add(_draw(_fields(line, 5)));
        case 'X':
          if (open.isNotEmpty || line.length != 1) throw _unreadable;
          pictures.add(
            VectorPicture._(
              key,
              width,
              height,
              List.unmodifiable(instructions),
            ),
          );
          key = null;
          instructions = <_Instruction>[];
        default:
          throw _unreadable;
      }
    }
    if (key != null) throw _unreadable;
    return pictures;
  }

  /// The pictures of one description text that can be read, in its order.
  /// A picture that cannot — a paint the engine refuses, a description cut
  /// short — is left out alone: the others are not lost with it.
  static List<VectorPicture> parseEach(String text) {
    final pictures = <VectorPicture>[];
    final lines = <String>[];
    for (final line in text.split('\n')) {
      lines.add(line);
      if (line != 'X') continue;
      try {
        pictures.addAll(parseAll(lines.join('\n')));
      } catch (_) {
        // Not a picture this interface can paint.
      }
      lines.clear();
    }
    return pictures;
  }

  /// The picture of one SVG text, or null when the core refuses it.
  static VectorPicture? fromSvg(String svg) {
    final description = RustDocument.describeSvg(svg);
    if (description == null) return null;
    final pictures = parseAll(description);
    return pictures.length == 1 ? pictures.single : null;
  }

  // The first fields of a line, and what follows them as the last one.
  static List<String> _fields(String line, int count) {
    final fields = <String>[];
    var start = 0;
    while (fields.length < count - 1) {
      final end = line.indexOf(' ', start);
      if (end < 0) throw _unreadable;
      fields.add(line.substring(start, end));
      start = end + 1;
    }
    fields.add(line.substring(start));
    if (fields.any((field) => field.isEmpty)) throw _unreadable;
    return fields;
  }

  static double _number(String text) {
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) throw _unreadable;
    return value;
  }

  static PathFillType _rule(String code) => switch (code) {
    'n' => PathFillType.nonZero,
    'e' => PathFillType.evenOdd,
    _ => throw _unreadable,
  };

  // `-`, or the six numbers of an SVG matrix: a b c d e f.
  static Float64List? _matrix(String code) {
    if (code == '-') return null;
    final values = code.split(';').map(_number).toList();
    if (values.length != 6) throw _unreadable;
    return Float64List(16)
      ..[0] = values[0]
      ..[1] = values[1]
      ..[4] = values[2]
      ..[5] = values[3]
      ..[10] = 1
      ..[12] = values[4]
      ..[13] = values[5]
      ..[15] = 1;
  }

  static Color _colour(String code) {
    final value = code.length == 9 && code.startsWith('#')
        ? int.tryParse(code.substring(1), radix: 16)
        : null;
    if (value == null) throw _unreadable;
    // Written red, green, blue, alpha.
    return Color(((value & 0xff) << 24) | (value >> 8));
  }

  static TileMode _spread(String code) => switch (code) {
    'p' => TileMode.clamp,
    'm' => TileMode.mirror,
    'r' => TileMode.repeated,
    _ => throw _unreadable,
  };

  // A plain colour, or a gradient as a shader.
  static Paint _paint(String code) {
    final paint = Paint()..isAntiAlias = true;
    if (code.startsWith('#')) return paint..color = _colour(code);
    final fields = code.split(':');
    final linear = fields.first == 'L';
    if ((!linear && fields.first != 'R') ||
        fields.length != (linear ? 8 : 10)) {
      throw _unreadable;
    }
    final geometry = [
      for (final field in fields.sublist(1, fields.length - 3)) _number(field),
    ];
    final tile = _spread(fields[fields.length - 3]);
    final matrix = _matrix(fields[fields.length - 2]);
    final colours = <Color>[];
    final offsets = <double>[];
    for (final stop in fields.last.split('/')) {
      final parts = stop.split('=');
      if (parts.length != 2) throw _unreadable;
      final offset = _number(parts[0]);
      if (offset < 0 ||
          offset > 1 ||
          (offsets.isNotEmpty && offset < offsets.last)) {
        throw _unreadable;
      }
      offsets.add(offset);
      colours.add(_colour(parts[1]));
    }
    if (colours.length == 1) {
      // One stop is one colour everywhere.
      return paint..color = colours.single;
    }
    if (linear) {
      return paint
        ..shader = ui.Gradient.linear(
          Offset(geometry[0], geometry[1]),
          Offset(geometry[2], geometry[3]),
          colours,
          offsets,
          tile,
          matrix,
        );
    }
    var centre = Offset(geometry[0], geometry[1]);
    final radius = geometry[2];
    var focal = Offset(geometry[3], geometry[4]);
    final focalRadius = geometry[5];
    if (radius <= 0 || focalRadius < 0) throw _unreadable;
    final plain = focal == centre && focalRadius == 0;
    var placed = matrix;
    if (!plain && centre == Offset.zero && focal == Offset.zero) {
      // The engine refuses two circles that are both at the origin, which
      // is where a gradient placed by its matrix has them. Moved one unit
      // aside, and the matrix one unit back: the same gradient.
      centre = focal = const Offset(1, 0);
      placed = matrix == null
          ? (Float64List(16)
              ..[0] = 1
              ..[5] = 1
              ..[10] = 1
              ..[15] = 1)
          : Float64List.fromList(matrix);
      placed[12] -= placed[0];
      placed[13] -= placed[1];
    }
    return paint
      ..shader = ui.Gradient.radial(
        centre,
        radius,
        colours,
        offsets,
        tile,
        placed,
        plain ? null : focal,
        plain ? 0 : focalRadius,
      );
  }

  static _Draw _draw(List<String> fields) {
    final strokeFirst = switch (fields[1]) {
      'f' => false,
      's' => true,
      _ => throw _unreadable,
    };
    final path = _path(fields[4]);
    Paint? fill;
    if (fields[2] != '-') {
      final parts = fields[2].split(',');
      if (parts.length != 2) throw _unreadable;
      fill = _paint(parts[0])..style = PaintingStyle.fill;
      path.fillType = _rule(parts[1]);
    }
    Paint? stroke;
    if (fields[3] != '-') {
      final parts = fields[3].split(',');
      if (parts.length != 4 || parts[2].length != 2) throw _unreadable;
      final width = _number(parts[1]);
      final limit = _number(parts[3]);
      if (width <= 0 || limit < 1) throw _unreadable;
      stroke = _paint(parts[0])
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = switch (parts[2][0]) {
          'b' => StrokeCap.butt,
          'r' => StrokeCap.round,
          's' => StrokeCap.square,
          _ => throw _unreadable,
        }
        ..strokeJoin = switch (parts[2][1]) {
          'm' => StrokeJoin.miter,
          'r' => StrokeJoin.round,
          'b' => StrokeJoin.bevel,
          _ => throw _unreadable,
        }
        ..strokeMiterLimit = limit;
    }
    if (fill == null && stroke == null) throw _unreadable;
    return _Draw(path, fill, stroke, strokeFirst);
  }

  // Absolute M, L, Q, C and Z commands; numbers separated by single spaces.
  static Path _path(String data) {
    final tokens = data.split(' ');
    final path = Path();
    var index = 0;
    double next() {
      if (index >= tokens.length) throw _unreadable;
      return _number(tokens[index++]);
    }

    while (index < tokens.length) {
      switch (tokens[index++]) {
        case 'M':
          path.moveTo(next(), next());
        case 'L':
          path.lineTo(next(), next());
        case 'Q':
          path.quadraticBezierTo(next(), next(), next(), next());
        case 'C':
          path.cubicTo(next(), next(), next(), next(), next(), next());
        case 'Z':
          path.close();
        default:
          throw _unreadable;
      }
    }
    return path;
  }

  /// Paints the picture into [bounds] of the current canvas: as large as
  /// they allow, never distorted, in their middle.
  ///
  /// A stroke that the reduction would make thinner than [minimumStroke]
  /// logical pixels is drawn that wide: a sheet of 1200 units shown in a
  /// thumbnail keeps lines that can be seen. The reduction is that of the
  /// whole picture; a group that scales its content is not counted. Zero
  /// draws every stroke at its own width.
  void paint(Canvas canvas, Rect bounds, {double minimumStroke = 0}) {
    if (bounds.isEmpty) return;
    final scale = bounds.width / width < bounds.height / height
        ? bounds.width / width
        : bounds.height / height;
    // The paints belong to the picture: one that is widened here gets its
    // own width back once the outline is drawn.
    void drawStroke(Path path, Paint stroke) {
      final own = stroke.strokeWidth;
      if (own * scale < minimumStroke) {
        stroke.strokeWidth = minimumStroke / scale;
      }
      canvas.drawPath(path, stroke);
      stroke.strokeWidth = own;
    }

    canvas.save();
    canvas.translate(
      bounds.left + (bounds.width - width * scale) / 2,
      bounds.top + (bounds.height - height * scale) / 2,
    );
    canvas.scale(scale);
    // A picture ends at its own edges, as an SVG does: what it draws beyond
    // them is not shown, whatever lies beside it on the canvas.
    canvas.clipRect(Rect.fromLTWH(0, 0, width, height));
    // Whether each open group was given a layer of its own.
    final layered = <bool>[];
    for (final instruction in _instructions) {
      switch (instruction) {
        case _Draw(:final path, :final fill, :final stroke, :final strokeFirst):
          if (strokeFirst && stroke != null) drawStroke(path, stroke);
          if (fill != null) canvas.drawPath(path, fill);
          if (!strokeFirst && stroke != null) drawStroke(path, stroke);
        case _Open(:final opacity, :final matrix, :final clips):
          canvas.save();
          if (matrix != null) canvas.transform(matrix);
          for (final clip in clips) {
            canvas.clipPath(clip);
          }
          final layer = opacity < 1;
          if (layer) {
            canvas.saveLayer(
              null,
              Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
            );
          }
          layered.add(layer);
        case _Close():
          if (layered.removeLast()) canvas.restore();
          canvas.restore();
      }
    }
    canvas.restore();
  }
}

/// The pictures of the interface, read from the core on first use.
class VectorArtCatalog {
  VectorArtCatalog(List<VectorPicture> pictures)
    : _pictures = {for (final picture in pictures) picture.key: picture};

  factory VectorArtCatalog.parse(String text) =>
      VectorArtCatalog(VectorPicture.parseEach(text));

  final Map<String, VectorPicture> _pictures;
  static VectorArtCatalog? _instance;
  static bool _unavailable = false;

  /// The catalogue of this process; null when the core cannot provide it —
  /// a library older than this interface. The interface then draws a plain
  /// shape in place of each picture rather than failing: see child_art.dart.
  static VectorArtCatalog? get instance {
    if (_instance == null && !_unavailable) {
      try {
        _instance = VectorArtCatalog.parse(RustDocument.readArtCatalog());
      } catch (_) {
        _unavailable = true;
      }
    }
    return _instance;
  }

  /// For tests: the catalogue this process uses from now on; null stands
  /// for a core that cannot provide one.
  @visibleForTesting
  static void debugUse(VectorArtCatalog? catalog) {
    _instance = catalog;
    _unavailable = catalog == null;
  }

  /// For tests: back to the catalogue of the core, read on next use.
  @visibleForTesting
  static void debugForget() {
    _instance = null;
    _unavailable = false;
  }

  Iterable<String> get keys => _pictures.keys;

  /// Null for a key this catalogue does not know.
  VectorPicture? operator [](String key) => _pictures[key];
}
