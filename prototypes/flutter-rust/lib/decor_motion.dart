// SPDX-License-Identifier: MIT
// How the decor of a universe moves (Color 1.2): leaves that sway, a cat
// that breathes, a cloud behind the window. An adult chooses how much, in
// the options: not at all, hardly (the default), more, much more. Nothing
// ever blinks, at any level.
//
// A movement is a short list of poses along its period, as the mock-ups
// wrote them; between two poses the piece glides, slow at both ends. Two
// factors make a level: how wide a piece sways or swells (its reach), and
// how far it travels. Everything here is plain arithmetic on a time in
// seconds: the same time gives the same pose, which the tests rely on.
import 'dart:math' as math;
import 'dart:typed_data';

import 'language.dart';

/// How much the decor moves: what the adult chose in the options.
enum DecorMotion {
  /// Nothing moves: the calm mode.
  none('aucun', 'Aucun', 0, 0),

  /// The decor hardly moves: the default.
  low('faible', 'Faible', 1, 1),
  medium('moyen', 'Moyen', 2, 1.5),
  high('maximum', 'Maximum', 3.2, 2.2);

  const DecorMotion(this.code, this.frenchLabel, this.reach, this.travel);

  /// The name written in the options file; never translated or changed.
  final String code;
  final String frenchLabel;
  String get label => tr(frenchLabel);

  /// How wide a piece sways, turns or swells: a factor on the mock-up's
  /// angles and swellings.
  final double reach;

  /// How far a piece travels: a factor on the mock-up's distances.
  final double travel;

  /// A piece of level 2 is shown from « Moyen », one of level 3 at
  /// « Maximum »; one of level 1 always.
  int get rank => index;

  bool get moves => this != none;

  static DecorMotion fromCode(Object? code) => values.firstWhere(
    (motion) => motion.code == code,
    orElse: () => DecorMotion.low,
  );
}

/// Where a piece is at one moment of its movement, from its place at rest:
/// moved by ([dx], [dy]) units of the decor, turned by [turn] degrees,
/// leaned by [skew] degrees, stretched by [scaleX] and [scaleY], about its
/// origin; and how opaque it is.
class DecorPose {
  const DecorPose({
    this.dx = 0,
    this.dy = 0,
    this.turn = 0,
    this.skew = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.opacity = 1,
  });

  /// At rest: where the picture draws the piece.
  static const rest = DecorPose();

  final double dx;
  final double dy;
  final double turn;
  final double skew;
  final double scaleX;
  final double scaleY;
  final double opacity;

  bool get isRest =>
      dx == 0 &&
      dy == 0 &&
      turn == 0 &&
      skew == 0 &&
      scaleX == 1 &&
      scaleY == 1 &&
      opacity == 1;

  static double _mix(double a, double b, double t) => a + (b - a) * t;

  static DecorPose lerp(DecorPose a, DecorPose b, double t) => DecorPose(
    dx: _mix(a.dx, b.dx, t),
    dy: _mix(a.dy, b.dy, t),
    turn: _mix(a.turn, b.turn, t),
    skew: _mix(a.skew, b.skew, t),
    scaleX: _mix(a.scaleX, b.scaleX, t),
    scaleY: _mix(a.scaleY, b.scaleY, t),
    opacity: _mix(a.opacity, b.opacity, t),
  );

  /// The matrix of the pose about ([ox], [oy]), in the units of the decor:
  /// moved, then turned, leaned and stretched about the origin. Null at
  /// rest, where nothing is to be done.
  Float64List? matrixAbout(double ox, double oy) {
    if (dx == 0 &&
        dy == 0 &&
        turn == 0 &&
        skew == 0 &&
        scaleX == 1 &&
        scaleY == 1) {
      return null;
    }
    final angle = turn * math.pi / 180;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final lean = math.tan(skew * math.pi / 180);
    // Turn × lean × stretch: [a c; b d].
    final a = cos * scaleX;
    final b = sin * scaleX;
    final c = (cos * lean - sin) * scaleY;
    final d = (sin * lean + cos) * scaleY;
    // About the origin, then moved.
    final e = ox + dx - a * ox - c * oy;
    final f = oy + dy - b * ox - d * oy;
    return Float64List(16)
      ..[0] = a
      ..[1] = b
      ..[4] = c
      ..[5] = d
      ..[10] = 1
      ..[12] = e
      ..[13] = f
      ..[15] = 1;
  }

  @override
  bool operator ==(Object other) =>
      other is DecorPose &&
      other.dx == dx &&
      other.dy == dy &&
      other.turn == turn &&
      other.skew == skew &&
      other.scaleX == scaleX &&
      other.scaleY == scaleY &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(dx, dy, turn, skew, scaleX, scaleY, opacity);

  @override
  String toString() =>
      'DecorPose(dx: $dx, dy: $dy, turn: $turn, skew: $skew, '
      'scale: $scaleX × $scaleY, opacity: $opacity)';
}

// One pose of a movement: where along the period (0 to 1), and the pose for
// a reach and a travel.
typedef _Key = (double at, DecorPose Function(double reach, double travel));

/// The movements a piece may be given, by the names of the mock-ups. Each
/// one ends where it begins: a period follows the other without a jump.
final Map<String, List<_Key>> _movements = {
  // A tree, a curtain, the leaves of a plant: half a degree each way.
  'balance': [
    (0, (reach, _) => DecorPose(turn: -.5 * reach)),
    (.5, (reach, _) => DecorPose(turn: .5 * reach)),
    (1, (reach, _) => DecorPose(turn: -.5 * reach)),
  ],
  // A pencil that rocks on the table.
  'bascule': [
    (0, (reach, _) => DecorPose(turn: -.5 * reach)),
    (.5, (reach, _) => DecorPose(turn: .6 * reach)),
    (1, (reach, _) => DecorPose(turn: -.5 * reach)),
  ],
  // Seaweed: a degree each way.
  'ondule': [
    (0, (reach, _) => DecorPose(turn: -reach)),
    (.5, (reach, _) => DecorPose(turn: reach)),
    (1, (reach, _) => DecorPose(turn: -reach)),
  ],
  // Grass that leans in the wind.
  'herbe': [
    (0, (reach, _) => DecorPose(skew: -2 * reach)),
    (.5, (reach, _) => DecorPose(skew: 2 * reach)),
    (1, (reach, _) => DecorPose(skew: -2 * reach)),
  ],
  // A drawing in chalk that comes and goes, never out of sight: the same
  // at every level, and slow — nothing blinks.
  'craie': [
    (0, (_, _) => const DecorPose(opacity: .5)),
    (.5, (_, _) => DecorPose.rest),
    (1, (_, _) => const DecorPose(opacity: .5)),
  ],
  // A sleeping cat: its back rises with its breath.
  'souffle': [
    (0, (_, _) => DecorPose.rest),
    (.5, (reach, _) => DecorPose(scaleY: 1 + .022 * reach)),
    (1, (_, _) => DecorPose.rest),
  ],
  // A cloud that drifts and comes back.
  'nuage': [
    (0, (_, _) => DecorPose.rest),
    (.5, (_, travel) => DecorPose(dx: 26 * travel)),
    (1, (_, _) => DecorPose.rest),
  ],
  // What floats: up a little and down again.
  'flotte': [
    (0, (_, _) => DecorPose.rest),
    (.5, (reach, _) => DecorPose(dy: -6 * reach)),
    (1, (_, _) => DecorPose.rest),
  ],
};

/// The names of the movements this version knows.
Iterable<String> get decorMovementNames => _movements.keys;

/// The movement of one piece: which one, how long a period lasts, how far
/// into it the piece is when the decor appears, and the point it turns
/// about, in the units of the decor.
class DecorMove {
  const DecorMove({
    required this.name,
    required this.seconds,
    this.delay = 0,
    this.originX = 0,
    this.originY = 0,
  });

  final String name;
  final double seconds;

  /// As the mock-ups write it: minus two seconds begins two seconds into
  /// the period.
  final double delay;
  final double originX;
  final double originY;

  /// What a description says, or null when it names no movement this
  /// version knows: the piece then stays still.
  static DecorMove? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final seconds = json['seconds'];
    if (name is! String || !_movements.containsKey(name)) return null;
    if (seconds is! num || !seconds.isFinite || seconds < 1) return null;
    final delay = json['delay'];
    final origin = json['origin'];
    final at = origin is List && origin.length == 2 && origin.every(_finite)
        ? origin
        : const [0, 0];
    return DecorMove(
      name: name,
      seconds: seconds.toDouble(),
      delay: delay is num && delay.isFinite ? delay.toDouble() : 0,
      originX: (at[0] as num).toDouble(),
      originY: (at[1] as num).toDouble(),
    );
  }

  static bool _finite(Object? value) => value is num && value.isFinite;

  // Slow at both ends, as « ease-in-out » is: the curve of the mock-ups,
  // a cubic Bézier through (.42, 0) and (.58, 1), solved for its time.
  static double _ease(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    // x(s) = 3(1-s)²s·.42 + 3(1-s)s²·.58 + s³ ; y(s) = 3(1-s)s² + s³.
    double x(double s) =>
        3 * (1 - s) * (1 - s) * s * .42 + 3 * (1 - s) * s * s * .58 + s * s * s;
    var low = 0.0;
    var high = 1.0;
    for (var step = 0; step < 24; step++) {
      final middle = (low + high) / 2;
      if (x(middle) < t) {
        low = middle;
      } else {
        high = middle;
      }
    }
    final s = (low + high) / 2;
    return 3 * (1 - s) * s * s + s * s * s;
  }

  /// The pose [seconds] after the decor appeared, at [motion]. At « Aucun »
  /// a piece is at rest, whatever the time.
  DecorPose poseAt(double seconds, DecorMotion motion) {
    if (!motion.moves) return DecorPose.rest;
    final keys = _movements[name];
    if (keys == null) return DecorPose.rest;
    final turns = (seconds - delay) / this.seconds;
    final phase = turns - turns.floorToDouble();
    for (var index = 1; index < keys.length; index++) {
      final (end, to) = keys[index];
      if (phase > end && index != keys.length - 1) continue;
      final (start, from) = keys[index - 1];
      final span = end - start;
      final local = span <= 0 ? 1.0 : ((phase - start) / span).clamp(0.0, 1.0);
      return DecorPose.lerp(
        from(motion.reach, motion.travel),
        to(motion.reach, motion.travel),
        _ease(local),
      );
    }
    return DecorPose.rest;
  }
}

/// The four moments of the day of the desk by the window, by the hour of
/// the device: the morning from six, the day from eleven, the evening from
/// five, the night from nine. The keys are those of the descriptions.
enum DayMoment {
  matin,
  jour,
  soir,
  nuit;

  static DayMoment at(DateTime time) {
    final hour = time.hour;
    return hour >= 6 && hour < 11
        ? matin
        : hour >= 11 && hour < 17
        ? jour
        : hour >= 17 && hour < 21
        ? soir
        : nuit;
  }

  static DayMoment? named(Object? name) {
    for (final moment in values) {
      if (moment.name == name) return moment;
    }
    return null;
  }
}

/// The angles of the hands of a clock at [time], in degrees from twelve,
/// clockwise: the small hand moves on with the minutes.
({double hour, double minute}) clockHands(DateTime time) =>
    (hour: (time.hour % 12) * 30 + time.minute * .5, minute: time.minute * 6.0);
