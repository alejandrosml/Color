// SPDX-License-Identifier: MIT
// The decor of a universe (Color 1.2): what is drawn around the sheet. The
// core hands over its description and its pictures (src/universes.rs); this
// file reads them, says where each piece stands in a frame of any size, and
// paints them.
//
// A decor is drawn in a frame of its own (1061 × 407 for the first ones),
// the sheet in its middle. What stands on the left of the sheet stays
// against the left edge of the frame, what stands on its right against the
// right edge, what lies under it stays under its middle, and everything
// stands on the bottom edge. The ground fills the frame. A child must be
// able to see everything (the owner, 11 November 2026): when the sheet at
// rest leaves less room beside it than the decor was drawn for, the decor
// is made smaller rather than hidden under the sheet, and where even half
// its size does not fit, only its ground is shown.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'decor_motion.dart';
import 'studio_colors.dart';
import 'vector_art.dart';

/// The edge a piece of the decor keeps to when the frame is wider or
/// narrower than the drawing.
enum DecorAnchor {
  left,
  middle,
  right;

  static DecorAnchor named(Object? name) =>
      values.firstWhere((anchor) => anchor.name == name, orElse: () => left);
}

/// What a piece is, beyond a picture at its place.
enum DecorRole {
  /// A picture, still or moving.
  plain,

  /// The ground: it fills the frame, and is repeated, mirrored, on a frame
  /// wider than it.
  ground,

  /// The sky of the moment of the day: the picture `<name>-<moment>`.
  sky,

  /// The two hands of a clock, at the time of the device.
  clock,
}

Rect? _rect(Object? json) {
  if (json is! List || json.length != 4) return null;
  if (!json.every((value) => value is num && value.isFinite)) return null;
  final values = [for (final value in json) (value as num).toDouble()];
  if (values[2] <= 0 || values[3] <= 0) return null;
  return Rect.fromLTWH(values[0], values[1], values[2], values[3]);
}

Offset? _point(Object? json) {
  if (json is! List || json.length != 2) return null;
  if (!json.every((value) => value is num && value.isFinite)) return null;
  return Offset((json[0] as num).toDouble(), (json[1] as num).toDouble());
}

Set<DayMoment>? _moments(Object? json) {
  if (json is! List) return null;
  return {for (final name in json) ?DayMoment.named(name)};
}

/// One piece of a decor.
class DecorPiece {
  const DecorPiece({
    required this.role,
    required this.anchor,
    this.picture,
    this.at,
    this.clip,
    this.moments,
    this.move,
    this.level = 1,
    this.clock,
  });

  final DecorRole role;
  final DecorAnchor anchor;

  /// The name of its picture among those of the universe; null for a clock.
  final String? picture;

  /// Where the picture is laid, in the frame of the decor; null for a
  /// picture drawn in that frame itself, which covers it whole.
  final Rect? at;

  /// What the piece never leaves: a cloud stays behind its window.
  final Rect? clip;

  /// The moments of the day it is shown at; null for always.
  final Set<DayMoment>? moments;
  final DecorMove? move;

  /// Shown from this level of movement on: 1 always, 2 from « Moyen », 3
  /// at « Maximum ».
  final int level;
  final DecorClock? clock;

  /// A piece that is painted at every image, above the ones that are kept
  /// in one picture: one that moves, or that tells the time.
  bool get live => move != null || role == DecorRole.clock;

  static DecorPiece? fromJson(Object? json) {
    if (json is! Map) return null;
    final role = switch (json['role']) {
      'ground' => DecorRole.ground,
      'sky' => DecorRole.sky,
      'clock' => DecorRole.clock,
      null => DecorRole.plain,
      _ => null,
    };
    // A piece of a kind this version does not know is left out alone.
    if (role == null) return null;
    final picture = json['picture'];
    final clock = role == DecorRole.clock ? DecorClock.fromJson(json) : null;
    if (role == DecorRole.clock ? clock == null : picture is! String) {
      return null;
    }
    final level = json['level'];
    return DecorPiece(
      role: role,
      anchor: DecorAnchor.named(json['anchor']),
      picture: picture is String ? picture : null,
      at: _rect(json['at']),
      clip: _rect(json['clip']),
      moments: _moments(json['moments']),
      move: DecorMove.fromJson(json['move']),
      level: level is int && level >= 1 && level <= 3 ? level : 1,
      clock: clock,
    );
  }
}

/// The hands of a clock of the decor: its centre, the length and the width
/// of each hand, their colour and that of the hub.
class DecorClock {
  const DecorClock({
    required this.centre,
    required this.hour,
    required this.minute,
    required this.ink,
    required this.hub,
  });
  final Offset centre;
  final Size hour;
  final Size minute;
  final Color ink;
  final Color hub;

  static DecorClock? fromJson(Map<Object?, Object?> json) {
    final centre = _point(json['centre']);
    final hour = _point(json['hour']);
    final minute = _point(json['minute']);
    if (centre == null || hour == null || minute == null) return null;
    if (hour.dx <= 0 || hour.dy <= 0 || minute.dx <= 0 || minute.dy <= 0) {
      return null;
    }
    return DecorClock(
      centre: centre,
      // Written length, then width.
      hour: Size(hour.dy, hour.dx),
      minute: Size(minute.dy, minute.dx),
      ink: StudioLook.parseColour(json['ink']) ?? const Color(0xff293d4b),
      hub: StudioLook.parseColour(json['hub']) ?? const Color(0xffd75e56),
    );
  }
}

/// What tints the room at one moment of the day.
class DecorVeil {
  const DecorVeil({this.multiply, this.gradient});

  /// A colour that darkens the room as a coloured glass would — outside
  /// the beam of the lamp, where colours stay bright.
  final Color? multiply;

  /// A light across the room: the angle of its line, in degrees from the
  /// top, clockwise, and its two colours.
  final (double angle, Color from, Color to)? gradient;

  static DecorVeil? fromJson(Object? json) {
    if (json is! Map) return null;
    final multiply = StudioLook.parseColour(json['multiply']);
    final list = json['gradient'];
    (double, Color, Color)? gradient;
    if (list is List && list.length == 3 && list[0] is num) {
      final from = StudioLook.parseColour(list[1]);
      final to = StudioLook.parseColour(list[2]);
      if (from != null && to != null && (list[0] as num).isFinite) {
        gradient = ((list[0] as num).toDouble(), from, to);
      }
    }
    if (multiply == null && gradient == null) return null;
    return DecorVeil(multiply: multiply, gradient: gradient);
  }
}

/// The lamp of the desk: where its head turns, the direction of its light
/// in degrees (to the right, then down), half the opening of its beam, how
/// far from the pivot the rim of its shade is and half the width of that
/// rim, its bulb, and the moments it is lit at.
class DecorLamp {
  const DecorLamp({
    required this.anchor,
    required this.pivot,
    required this.angle,
    required this.half,
    required this.rim,
    required this.rimHalf,
    required this.bulb,
    required this.bulbRadius,
    required this.moments,
  });
  final DecorAnchor anchor;
  final Offset pivot;
  final double angle;
  final double half;
  final double rim;
  final double rimHalf;
  final Offset bulb;
  final double bulbRadius;
  final Set<DayMoment> moments;

  static DecorLamp? fromJson(Object? json) {
    if (json is! Map) return null;
    final pivot = _point(json['pivot']);
    final bulb = _point(json['bulb']);
    double? number(String name) {
      final value = json[name];
      return value is num && value.isFinite ? value.toDouble() : null;
    }

    final angle = number('angle');
    final half = number('half');
    final rim = number('rim');
    final rimHalf = number('rimHalf');
    final radius = number('bulbRadius');
    if (pivot == null ||
        bulb == null ||
        angle == null ||
        half == null ||
        rim == null ||
        rimHalf == null ||
        radius == null ||
        half <= 0 ||
        half >= 80 ||
        radius <= 0) {
      return null;
    }
    return DecorLamp(
      anchor: DecorAnchor.named(json['anchor']),
      pivot: pivot,
      angle: angle,
      half: half,
      rim: rim,
      rimHalf: rimHalf,
      bulb: bulb,
      bulbRadius: radius,
      moments: _moments(json['moments']) ?? const {},
    );
  }
}

/// Something of the decor a child may ask the name of: where it is, its
/// name and one or two lines about it, in French; `tr` gives them in the
/// language of the interface.
class DecorName {
  const DecorName({
    required this.key,
    required this.anchor,
    required this.at,
    required this.frenchName,
    required this.frenchText,
  });
  final String key;
  final DecorAnchor anchor;
  final Rect at;
  final String frenchName;
  final String frenchText;

  static DecorName? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final name = json['name'];
    final text = json['text'];
    final at = _rect(json['at']);
    if (key is! String || name is! String || text is! String || at == null) {
      return null;
    }
    if (name.isEmpty || text.isEmpty) return null;
    return DecorName(
      key: key,
      anchor: DecorAnchor.named(json['anchor']),
      at: at,
      frenchName: name,
      frenchText: text,
    );
  }
}

/// The decor of one universe.
class Decor {
  Decor._({
    required this.size,
    required this.sheet,
    required this.top,
    required this.pieces,
    required this.veils,
    required this.lamp,
    required this.names,
    required String pictures,
  }) : _pictureText = pictures;

  /// The frame the decor is drawn in.
  final Size size;

  /// Where the sheet was when the decor was drawn, in that frame.
  final Rect sheet;

  /// What fills the frame above the ground, where the frame is taller.
  final Color top;

  /// The pieces, from the back to the front.
  final List<DecorPiece> pieces;
  final Map<DayMoment, DecorVeil> veils;
  final DecorLamp? lamp;

  /// What a child may ask the name of, the largest first: a small thing
  /// that lies on a large one is found before it.
  final List<DecorName> names;

  String? _pictureText;
  Map<String, VectorPicture>? _pictures;

  /// The pictures of the decor, by name: read on first use, and kept.
  Map<String, VectorPicture> get pictures {
    final kept = _pictures;
    if (kept != null) return kept;
    final text = _pictureText ?? '';
    _pictureText = null;
    return _pictures = {
      for (final picture in VectorPicture.parseEach(text)) picture.key: picture,
    };
  }

  /// Whether the decor follows the hour: a sky, a clock, a light or a
  /// piece of some moments only.
  late final bool followsTheHour =
      veils.isNotEmpty ||
      lamp != null ||
      pieces.any(
        (piece) =>
            piece.role == DecorRole.sky ||
            piece.role == DecorRole.clock ||
            piece.moments != null,
      );

  /// Whether anything of it moves at some level.
  late final bool hasMovement = pieces.any((piece) => piece.move != null);

  /// The pieces kept in one picture: the ground, and every piece before the
  /// first one that is [DecorPiece.live].
  late final List<DecorPiece> still = [
    for (final piece in pieces.takeWhile((piece) => !piece.live)) piece,
  ];

  /// The pieces painted at every image, above the still ones.
  late final List<DecorPiece> live = pieces.sublist(still.length);

  /// What a description says, with the text of the pictures it names; null
  /// when it describes no decor that can be shown: no frame, or no ground.
  static Decor? fromJson(Object? json, {required String pictures}) {
    if (json is! Map) return null;
    final size = _point(json['size']);
    if (size == null || size.dx < 16 || size.dy < 16) return null;
    final frame = Offset.zero & Size(size.dx, size.dy);
    final sheet = _rect(json['sheet']);
    final list = json['pieces'];
    final pieces = <DecorPiece>[
      if (list is List)
        for (final piece in list) ?DecorPiece.fromJson(piece),
    ];
    if (pieces.where((piece) => piece.role == DecorRole.ground).length != 1 ||
        pieces.first.role != DecorRole.ground) {
      return null;
    }
    final light = json['light'];
    final veils = <DayMoment, DecorVeil>{};
    if (light is Map && light['veils'] is Map) {
      (light['veils'] as Map).forEach((name, veil) {
        final moment = DayMoment.named(name);
        final read = DecorVeil.fromJson(veil);
        if (moment != null && read != null) veils[moment] = read;
      });
    }
    final named = json['names'];
    final names =
        <DecorName>[
          if (named is List)
            for (final name in named) ?DecorName.fromJson(name),
        ]..sort(
          (a, b) =>
              (a.at.width * a.at.height).compareTo(b.at.width * b.at.height),
        );
    return Decor._(
      size: frame.size,
      sheet: sheet != null && frame.contains(sheet.center)
          ? sheet.intersect(frame)
          : Rect.fromLTRB(
              frame.width * .25,
              frame.height * .06,
              frame.width * .75,
              frame.height * .93,
            ),
      top:
          StudioLook.parseColour(json['top']) ??
          StudioLook.classic.sheetBackdrop,
      pieces: List.unmodifiable(pieces),
      veils: Map.unmodifiable(veils),
      lamp: light is Map ? DecorLamp.fromJson(light['lamp']) : null,
      names: List.unmodifiable(names),
      pictures: pictures,
    );
  }
}

/// Where a decor stands in a frame: its scale, and whether its pieces are
/// shown or only its ground.
@immutable
class DecorLayout {
  const DecorLayout._({
    required this.frame,
    required this.decor,
    required this.scale,
    required this.middle,
    required this.pieces,
  });

  /// The decor in a [frame], around a sheet that lies at [sheetAtRest] when
  /// the whole of it is shown: as large as the height of the frame allows,
  /// and smaller when the sheet leaves less room beside it than the pieces
  /// of the sides need.
  factory DecorLayout({
    required Size frame,
    required Rect sheetAtRest,
    required Size decor,
    required Rect decorSheet,
  }) {
    final full = frame.height / decor.height;
    final room = math.max(
      0.0,
      math.min(sheetAtRest.left, frame.width - sheetAtRest.right),
    );
    final need = math.max(decorSheet.left, decor.width - decorSheet.right);
    final fitting = need <= 0 ? full : room / need;
    final pieces = fitting >= full * minimumShare;
    return DecorLayout._(
      frame: frame,
      decor: decor,
      scale: pieces ? math.min(full, fitting) : full,
      middle: Offset(sheetAtRest.center.dx, decorSheet.center.dx),
      pieces: pieces && frame.width > 0 && frame.height > 0,
    );
  }

  /// Below this share of the size the height allows, the pieces of a decor
  /// are too small to be looked at: only its ground is shown.
  static const minimumShare = .45;

  final Size frame;
  final Size decor;

  /// Pixels of the frame for one unit of the decor.
  final double scale;

  // The middle of the sheet at rest in the frame, and in the decor.
  final Offset middle;

  /// Whether the pieces are shown; the ground always is.
  final bool pieces;

  /// The left edge, in the frame, of what is drawn at x = 0 of the decor
  /// and keeps to [anchor].
  double left(DecorAnchor anchor) => switch (anchor) {
    DecorAnchor.left => 0,
    DecorAnchor.right => frame.width - decor.width * scale,
    DecorAnchor.middle => middle.dx - middle.dy * scale,
  };

  /// The top edge, in the frame, of what is drawn at y = 0 of the decor.
  double get top => frame.height - decor.height * scale;

  /// The place in the frame of [box] of the decor, for a piece that keeps
  /// to [anchor].
  Rect place(Rect box, DecorAnchor anchor) => Rect.fromLTWH(
    left(anchor) + box.left * scale,
    top + box.top * scale,
    box.width * scale,
    box.height * scale,
  );

  Offset point(Offset at, DecorAnchor anchor) =>
      Offset(left(anchor) + at.dx * scale, top + at.dy * scale);

  @override
  bool operator ==(Object other) =>
      other is DecorLayout &&
      other.frame == frame &&
      other.decor == decor &&
      other.scale == scale &&
      other.middle == middle &&
      other.pieces == pieces;

  @override
  int get hashCode => Object.hash(frame, decor, scale, middle, pieces);
}

/// Paints a decor. Nothing here keeps time or listens to anything: the
/// time, the moment and the level of movement are given at every call.
class DecorPainting {
  DecorPainting(this.decor, this.layout);
  final Decor decor;
  final DecorLayout layout;

  bool _shown(DecorPiece piece, DayMoment moment, DecorMotion motion) =>
      (piece.moments?.contains(moment) ?? true) &&
      (piece.level == 1 || motion.rank >= piece.level);

  // The frame of the decor, laid for [anchor]: one unit of the decor is
  // one unit of the canvas until the matching restore.
  void _enter(Canvas canvas, DecorAnchor anchor) {
    canvas.save();
    canvas.translate(layout.left(anchor), layout.top);
    canvas.scale(layout.scale);
  }

  void _paintPicture(
    Canvas canvas,
    DecorPiece piece,
    VectorPicture picture,
    DecorPose pose,
  ) {
    _enter(canvas, piece.anchor);
    final clip = piece.clip;
    if (clip != null) canvas.clipRect(clip);
    final matrix = pose.matrixAbout(
      piece.move?.originX ?? 0,
      piece.move?.originY ?? 0,
    );
    if (matrix != null) canvas.transform(matrix);
    final faded = pose.opacity < 1;
    final box = piece.at ?? Offset.zero & decor.size;
    if (faded) {
      canvas.saveLayer(
        box.inflate(8),
        Paint()..color = Color.fromRGBO(0, 0, 0, pose.opacity.clamp(0.0, 1.0)),
      );
    }
    picture.paint(canvas, box);
    if (faded) canvas.restore();
    canvas.restore();
  }

  VectorPicture? _pictureOf(DecorPiece piece, DayMoment moment) {
    final name = piece.picture;
    if (name == null) return null;
    return decor.pictures[piece.role == DecorRole.sky
        ? '$name-${moment.name}'
        : name];
  }

  /// The ground and the still pieces, at [moment]: what is kept in one
  /// picture between two changes of the frame or of the moment.
  void paintStill(Canvas canvas, DayMoment moment) {
    final frame = Offset.zero & layout.frame;
    canvas.save();
    canvas.clipRect(frame);
    canvas.drawRect(frame, Paint()..color = decor.top);
    final ground = decor.pictures[decor.pieces.first.picture];
    if (ground != null) {
      // In the middle of the frame, on its bottom edge; on a wider frame,
      // again on each side, mirrored: its edges meet themselves.
      final width = decor.size.width * layout.scale;
      final first = layout.middle.dx - layout.middle.dy * layout.scale;
      final box = Offset.zero & decor.size;
      var tile = ((0 - first) / width).floor();
      while (first + tile * width < layout.frame.width) {
        canvas.save();
        canvas.translate(first + tile * width, layout.top);
        canvas.scale(layout.scale);
        if (tile.isOdd) {
          canvas.translate(decor.size.width, 0);
          canvas.scale(-1, 1);
        }
        ground.paint(canvas, box);
        canvas.restore();
        tile++;
      }
    }
    if (layout.pieces) {
      for (final piece in decor.still.skip(1)) {
        final picture = _pictureOf(piece, moment);
        if (picture == null || !_shown(piece, moment, DecorMotion.none)) {
          continue;
        }
        _paintPicture(canvas, piece, picture, DecorPose.rest);
      }
    }
    canvas.restore();
  }

  /// The live pieces, [seconds] after the decor appeared, at [time] of the
  /// device, then the light of that moment over the whole room.
  void paintLive(
    Canvas canvas, {
    required double seconds,
    required DateTime time,
    required DecorMotion motion,
  }) {
    final moment = DayMoment.at(time);
    final frame = Offset.zero & layout.frame;
    canvas.save();
    canvas.clipRect(frame);
    if (layout.pieces) {
      for (final piece in decor.live) {
        if (!_shown(piece, moment, motion)) continue;
        if (piece.clock case final clock?) {
          _paintClock(canvas, piece.anchor, clock, time);
          continue;
        }
        final picture = _pictureOf(piece, moment);
        if (picture == null) continue;
        _paintPicture(
          canvas,
          piece,
          picture,
          piece.move?.poseAt(seconds, motion) ?? DecorPose.rest,
        );
      }
    }
    _paintLight(canvas, moment);
    canvas.restore();
  }

  void _paintClock(
    Canvas canvas,
    DecorAnchor anchor,
    DecorClock clock,
    DateTime time,
  ) {
    final hands = clockHands(time);
    _enter(canvas, anchor);
    canvas.translate(clock.centre.dx, clock.centre.dy);
    final ink = Paint()
      ..color = clock.ink
      ..isAntiAlias = true;
    for (final (degrees, hand) in [
      (hands.hour, clock.hour),
      (hands.minute, clock.minute),
    ]) {
      canvas.save();
      canvas.rotate(degrees * math.pi / 180);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-hand.width / 2, -hand.height, hand.width, hand.height),
          const Radius.circular(2),
        ),
        ink,
      );
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, 3, Paint()..color = clock.hub);
    canvas.restore();
  }

  /// The beam of the lamp in the frame: from the two ends of the rim of its
  /// shade, outwards, far beyond the frame.
  Path? _beam(DecorLamp lamp) {
    if (!layout.pieces) return null;
    final angle = lamp.angle * math.pi / 180;
    final along = Offset(math.cos(angle), math.sin(angle));
    final across = Offset(-along.dy, along.dx);
    final rim = lamp.pivot + along * lamp.rim;
    final desk = rim + across * lamp.rimHalf;
    final wall = rim - across * lamp.rimHalf;
    final half = lamp.half * math.pi / 180;
    // Farther than any frame is wide, in units of the decor.
    final reach =
        (layout.frame.width + layout.frame.height) / layout.scale + 4000;
    Offset far(Offset from, double direction) =>
        from + Offset(math.cos(direction), math.sin(direction)) * reach;
    final points = [
      desk,
      far(desk, angle + half),
      far(wall, angle - half),
      wall,
    ];
    return Path()..addPolygon([
      for (final point in points) layout.point(point, lamp.anchor),
    ], true);
  }

  void _paintLight(Canvas canvas, DayMoment moment) {
    final frame = Offset.zero & layout.frame;
    final lamp = decor.lamp;
    final lit = lamp != null && lamp.moments.contains(moment);
    final beam = lit ? _beam(lamp) : null;
    final veil = decor.veils[moment];
    if (veil != null) {
      final gradient = veil.gradient;
      if (gradient != null) {
        final (degrees, from, to) = gradient;
        final angle = degrees * math.pi / 180;
        // The line of a gradient goes through the middle of the frame,
        // long enough for its ends to reach the corners.
        final direction = Offset(math.sin(angle), -math.cos(angle));
        final half =
            (frame.width * direction.dx.abs() +
                frame.height * direction.dy.abs()) /
            2;
        canvas.drawRect(
          frame,
          Paint()
            ..shader = ui.Gradient.linear(
              frame.center - direction * half,
              frame.center + direction * half,
              [from, to],
            ),
        );
      }
      final multiply = veil.multiply;
      if (multiply != null) {
        // The shade of the evening and of the night does not fall in the
        // beam of the lamp: there, colours stay bright.
        final shade = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(frame);
        if (beam != null) shade.addPath(beam, Offset.zero);
        canvas.drawPath(
          shade,
          Paint()
            ..color = multiply
            ..blendMode = BlendMode.multiply,
        );
      }
    }
    if (!lit || beam == null) return;
    final bulb = layout.point(lamp.bulb, lamp.anchor);
    final scale = layout.scale;
    canvas.drawPath(
      beam,
      Paint()
        ..shader = ui.Gradient.radial(
          bulb,
          280 * scale,
          const [
            Color(0x9efff0b4),
            Color(0x4dffe896),
            Color(0x24ffe28c),
            Color(0x12ffe28c),
          ],
          const [0, 80 / 280, 190 / 280, 1],
        ),
    );
    // The lit bulb: a glow that fades, a golden ring, and the bulb.
    final radius = lamp.bulbRadius * scale;
    void glow(double reach, Color colour) => canvas.drawCircle(
      bulb,
      radius + reach * scale,
      Paint()
        ..shader = ui.Gradient.radial(
          bulb,
          radius + reach * scale,
          [colour, colour.withValues(alpha: 0)],
          [radius / (radius + reach * scale), 1],
        ),
    );
    glow(40, const Color(0x80ffd66e));
    glow(15, const Color(0xf2ffe082));
    canvas.drawCircle(
      bulb,
      radius + 2 * scale,
      Paint()..color = const Color(0xfff4b942),
    );
    canvas.drawCircle(
      bulb,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          bulb + Offset(-.2 * radius, -.3 * radius),
          radius * 1.3,
          const [Color(0xffffffff), Color(0xfffff8d6), Color(0xffffe07a)],
          const [0, .42, 1],
        ),
    );
  }

  /// What a child may ask the name of at [position] of the frame: the
  /// smallest named thing there, or null. Nothing is named where the pieces
  /// are not shown.
  DecorName? nameAt(Offset position) {
    if (!layout.pieces) return null;
    for (final name in decor.names) {
      if (layout.place(name.at, name.anchor).inflate(3).contains(position)) {
        return name;
      }
    }
    return null;
  }

  /// The matrix that lays the frame of the decor for [anchor]: for whoever
  /// paints over the decor in its units.
  Float64List matrixFor(DecorAnchor anchor) => Float64List(16)
    ..[0] = layout.scale
    ..[5] = layout.scale
    ..[10] = 1
    ..[12] = layout.left(anchor)
    ..[13] = layout.top
    ..[15] = 1;
}
