// SPDX-License-Identifier: MIT
// The stamp artwork lives in the Rust core, which also writes it into SVG
// exports. This file parses the core's catalogue text once and paints the very
// same paths, so the sheet, the PNG export and the SVG export agree.
import 'dart:ui';

import 'rust_document.dart';

/// How one layer of a stamp is coloured.
enum StampTone { none, primary, dark, light, fixed }

@pragma('vm:prefer-inline')
int _channels(int rgb, int Function(int) map) =>
    (map((rgb >> 16) & 0xff) << 16) |
    (map((rgb >> 8) & 0xff) << 8) |
    map(rgb & 0xff);

/// Exact integer shades, identical to the core: a darker shade keeps 7/10 of
/// each channel, a lighter tint adds 6/10 of its distance to white.
int stampDarkRgb(int rgb) => _channels(rgb, (c) => c * 7 ~/ 10);
int stampLightRgb(int rgb) => _channels(rgb, (c) => c + (255 - c) * 6 ~/ 10);

class StampPaint {
  const StampPaint(this.tone, [this.fixedRgb = 0]);
  final StampTone tone;
  final int fixedRgb;

  /// Whether the chosen colour decides this paint.
  bool get tinted =>
      tone == StampTone.primary ||
      tone == StampTone.dark ||
      tone == StampTone.light;

  /// The opaque colour for a stamp tinted with [rgb], or null for no paint.
  int? resolve(int rgb) => switch (tone) {
    StampTone.none => null,
    StampTone.primary => rgb,
    StampTone.dark => stampDarkRgb(rgb),
    StampTone.light => stampLightRgb(rgb),
    StampTone.fixed => fixedRgb,
  };
}

class StampLayerArt {
  StampLayerArt(this.path, this.fill, this.stroke, this.width);

  /// On the 100 × 100 design grid. Shared by every object using this stamp:
  /// never modify it, transform the canvas instead.
  final Path path;
  final StampPaint fill;
  final StampPaint stroke;
  final double width;

  /// Points along the path, one design unit apart: enough to tell how far a
  /// pointer is from an outline. Computed once, when first asked for.
  late final List<Offset> _outline = [
    for (final metric in path.computeMetrics())
      for (var at = 0.0; at <= metric.length; at += 1)
        ?metric.getTangentForOffset(at)?.position,
  ];

  /// The opaque colour of this layer at [point] of the design grid for a
  /// stamp tinted with [rgb], within [reach] grid units: its outline where
  /// one is drawn there, its inside otherwise; null where it paints nothing.
  int? inkAt(Offset point, int rgb, double reach) {
    final outline = stroke.resolve(rgb);
    if (outline != null) {
      final radius = width / 2 + reach + .5;
      for (final sample in _outline) {
        if ((sample - point).distanceSquared <= radius * radius) {
          return outline;
        }
      }
    }
    final inside = fill.resolve(rgb);
    if (inside != null) {
      if (path.contains(point)) return inside;
      // Within reach of the inside: its nearest edge is sampled above.
      if (reach > 0) {
        for (final sample in _outline) {
          if ((sample - point).distanceSquared <= reach * reach) {
            return inside;
          }
        }
      }
    }
    return null;
  }
}

class StampArt {
  StampArt(this.id, this.key, List<StampLayerArt> layers)
    : layers = List.unmodifiable(layers);
  final int id;
  final String key;
  final List<StampLayerArt> layers;

  /// Whether the chosen colour shows anywhere on this stamp. A stamp painted
  /// in its own colours only, like the rainbow, keeps them: giving it another
  /// colour would change nothing that can be seen.
  late final bool takesColour = layers.any(
    (layer) => layer.fill.tinted || layer.stroke.tinted,
  );

  /// French name shown under the picture and announced to screen readers.
  String get label =>
      _labels[key] ?? '${key[0].toUpperCase()}${key.substring(1)}';

  static const _labels = {
    'etoile': 'Étoile',
    'coeur': 'Cœur',
    'soleil': 'Soleil',
    'lune': 'Lune',
    'nuage': 'Nuage',
    'fleur': 'Fleur',
    'arbre': 'Arbre',
    'maison': 'Maison',
    'chat': 'Chat',
    'poisson': 'Poisson',
    'papillon': 'Papillon',
    'ballon': 'Ballon',
    'voiture': 'Voiture',
    'bateau': 'Bateau',
    'fusee': 'Fusée',
    'pomme': 'Pomme',
    'sourire': 'Sourire',
    'eclair': 'Éclair',
    'champignon': 'Champignon',
    'couronne': 'Couronne',
    'goutte': 'Goutte',
    'oiseau': 'Oiseau',
    'chien': 'Chien',
    'arcenciel': 'Arc-en-ciel',
  };

  /// The colour of the artwork at [point] for a stamp tinted with [rgb] and
  /// drawn in [bounds], within [reach] of the pointer: the part painted last
  /// answers first. Null where the stamp paints nothing: there the sheet, or
  /// what lies behind, is what one sees. [point], [bounds] and [reach] are in
  /// the units of the drawing.
  int? inkAt(Offset point, Rect bounds, int rgb, [double reach = 0]) {
    if (bounds.width <= 0 || bounds.height <= 0) return null;
    final local = Offset(
      (point.dx - bounds.left) * 100 / bounds.width,
      (point.dy - bounds.top) * 100 / bounds.height,
    );
    // The grid is not always scaled alike on both axes: take the tighter.
    final localReach =
        reach *
        100 /
        (bounds.width > bounds.height ? bounds.width : bounds.height);
    // First what is painted at the very point; only then what is near it. A
    // small part painted last must not answer for the large one under the
    // pointer just because it is within reach.
    for (final within in [0.0, if (localReach > 0) localReach]) {
      for (final layer in layers.reversed) {
        final colour = layer.inkAt(local, rgb, within);
        if (colour != null) return colour;
      }
    }
    return null;
  }

  /// Paints the stamp, tinted with [rgb], into [bounds] of the current canvas.
  void paint(Canvas canvas, Rect bounds, int rgb) {
    canvas.save();
    canvas.translate(bounds.left, bounds.top);
    canvas.scale(bounds.width / 100, bounds.height / 100);
    for (final layer in layers) {
      final fill = layer.fill.resolve(rgb);
      if (fill != null) {
        canvas.drawPath(
          layer.path,
          Paint()
            ..color = Color(0xff000000 | fill)
            ..isAntiAlias = true,
        );
      }
      final stroke = layer.stroke.resolve(rgb);
      if (stroke != null) {
        canvas.drawPath(
          layer.path,
          Paint()
            ..color = Color(0xff000000 | stroke)
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeWidth = layer.width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
    canvas.restore();
  }
}

/// The catalogue of this process, read from the core on first use.
class StampCatalog {
  StampCatalog(List<StampArt> stamps) : stamps = List.unmodifiable(stamps);

  /// Parses `id|key|fill,stroke,width,path;…` lines in identifier order.
  factory StampCatalog.parse(String text) {
    final stamps = <StampArt>[];
    for (final line in text.split('\n')) {
      if (line.isEmpty) continue;
      final fields = line.split('|');
      if (fields.length != 3 || int.tryParse(fields[0]) != stamps.length) {
        throw const FormatException('Catalogue de tampons illisible.');
      }
      final layers = <StampLayerArt>[];
      for (final description in fields[2].split(';')) {
        final parts = description.split(',');
        final width = parts.length == 4 ? double.tryParse(parts[2]) : null;
        if (width == null || !width.isFinite || width < 0 || width > 16) {
          throw const FormatException('Catalogue de tampons illisible.');
        }
        layers.add(
          StampLayerArt(
            _parsePath(parts[3]),
            _parsePaint(parts[0]),
            _parsePaint(parts[1]),
            width,
          ),
        );
      }
      if (fields[1].isEmpty || layers.isEmpty) {
        throw const FormatException('Catalogue de tampons illisible.');
      }
      stamps.add(StampArt(stamps.length, fields[1], layers));
    }
    if (stamps.isEmpty) {
      throw const FormatException('Catalogue de tampons vide.');
    }
    return StampCatalog(stamps);
  }

  final List<StampArt> stamps;
  static StampCatalog? _instance;

  /// One catalogue per isolate; only the interface isolate paints stamps.
  static StampCatalog get instance =>
      _instance ??= StampCatalog.parse(RustDocument.readStampCatalog());

  /// Null for an identifier this catalogue does not know.
  StampArt? operator [](int id) =>
      id >= 0 && id < stamps.length ? stamps[id] : null;

  static StampPaint _parsePaint(String code) {
    switch (code) {
      case '-':
        return const StampPaint(StampTone.none);
      case 'P':
        return const StampPaint(StampTone.primary);
      case 'D':
        return const StampPaint(StampTone.dark);
      case 'L':
        return const StampPaint(StampTone.light);
    }
    final rgb = code.length == 7 && code.startsWith('#')
        ? int.tryParse(code.substring(1), radix: 16)
        : null;
    if (rgb == null) {
      throw const FormatException('Couleur de tampon illisible.');
    }
    return StampPaint(StampTone.fixed, rgb);
  }

  // Absolute M, L, C, Q and Z commands; numbers separated by single spaces.
  static Path _parsePath(String data) {
    final tokens = data.split(' ');
    final path = Path();
    var index = 0;
    double next() {
      final value = index < tokens.length
          ? double.tryParse(tokens[index++])
          : null;
      if (value == null || !value.isFinite) {
        throw const FormatException('Tracé de tampon illisible.');
      }
      return value;
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
          throw const FormatException('Tracé de tampon illisible.');
      }
    }
    return path;
  }
}
