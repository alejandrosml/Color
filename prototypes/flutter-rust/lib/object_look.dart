// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'dart:typed_data';

/// What a freehand stroke is drawn with; [code] is the core's number for it
/// (EpObjectLook.tool). Only a freehand stroke has a tool other than [round].
enum BrushTool {
  /// The round brush of Color 1.0.
  round(0),

  /// The marker: square ends, slightly see-through.
  felt(1),

  /// A flat nib held at 45 degrees: thick and thin.
  calligraphy(2),

  /// Grains of chalk, the same every time for the same stroke.
  chalk(3),

  /// A cloud of fine drops.
  airbrush(4),

  /// Magic: the colours of the rainbow along the stroke.
  rainbow(16),

  /// Magic: blades of grass.
  grass(17),

  /// Magic: a wall of bricks.
  bricks(18),

  /// Magic: confetti of many colours.
  confetti(19);

  const BrushTool(this.code);

  /// The core's number for the tool.
  final int code;

  /// The tool of a core number, or null for a number this program does not
  /// know.
  static BrushTool? fromCode(int code) {
    for (final tool in values) {
      if (tool.code == code) return tool;
    }
    return null;
  }

  /// Tools whose marks are scattered: their stroke keeps a seed, so that
  /// the same stroke always shows the same marks.
  bool get scatters =>
      this == chalk || this == airbrush || this == grass || this == confetti;

  /// The magic tools, beside the brushes.
  bool get isMagic => code >= 16;

  /// Tools whose stroke the core paints as marks rather than as a line.
  bool get paintsMarks => this != round && this != felt;
}

/// How the inside of a filled shape is painted: one colour, or a gradient
/// from it to a second one, through Oklab.
enum GradientKind { none, linear, radial }

/// The look of an object that Color 1.1 adds (EpObjectLook): turn and mirror
/// about the centre of its box; the tool of a freehand stroke and its seed;
/// the gradient of a filled shape. Immutable.
class ObjectLook {
  const ObjectLook({
    this.rotation = 0,
    this.mirrorX = false,
    this.mirrorY = false,
    this.tool = BrushTool.round,
    this.zone = false,
    this.seed = 0,
    this.gradient = GradientKind.none,
    this.gradientRgb = 0,
    this.gradientPoints = const [0, 0, 0, 0],
  });

  /// Nothing more than Color 1.0 drew.
  static const plain = ObjectLook();

  /// The look of a zone the paint pot pours.
  static const pouredZone = ObjectLook(zone: true);

  /// Radians in ]−π, π], about the centre of the object's box, after the
  /// mirror; positive turns clockwise on the sheet.
  final double rotation;

  /// Mirrored left-right (bit 0 of the core's mirror).
  final bool mirrorX;

  /// Mirrored top-bottom (bit 1).
  final bool mirrorY;

  final BrushTool tool;

  /// A contour poured by the paint pot (the core's tool 32): a later pour
  /// sees through it, to fill within it or over it. [tool] is then round.
  final bool zone;

  /// Of a stroke whose tool [BrushTool.scatters]; 0 otherwise.
  final int seed;

  final GradientKind gradient;

  /// 0x00RRGGBB of the gradient's second colour; 0 without a gradient.
  final int gradientRgb;

  /// x0, y0, x1, y1 as fractions of the object's box: the line of a linear
  /// gradient, the centre and a point of the circle of a radial one.
  final List<double> gradientPoints;

  /// The mirror as the core keeps it.
  int get mirrorBits => (mirrorX ? 1 : 0) | (mirrorY ? 2 : 0);

  /// Whether the object is drawn turned or mirrored.
  bool get transforms => rotation != 0 || mirrorX || mirrorY;

  bool get hasGradient => gradient != GradientKind.none;

  bool get isPlain =>
      !transforms &&
      tool == BrushTool.round &&
      !zone &&
      seed == 0 &&
      !hasGradient;

  ObjectLook copyWith({
    double? rotation,
    bool? mirrorX,
    bool? mirrorY,
    BrushTool? tool,
    int? seed,
  }) => ObjectLook(
    rotation: rotation ?? this.rotation,
    mirrorX: mirrorX ?? this.mirrorX,
    mirrorY: mirrorY ?? this.mirrorY,
    tool: tool ?? this.tool,
    zone: zone,
    seed: seed ?? this.seed,
    gradient: gradient,
    gradientRgb: gradientRgb,
    gradientPoints: gradientPoints,
  );

  /// The same look with another gradient, or none.
  ObjectLook withGradient(
    GradientKind kind, {
    int rgb = 0,
    List<double> points = const [0, 0, 0, 0],
  }) => ObjectLook(
    rotation: rotation,
    mirrorX: mirrorX,
    mirrorY: mirrorY,
    tool: tool,
    zone: zone,
    seed: seed,
    gradient: kind,
    gradientRgb: kind == GradientKind.none ? 0 : rgb,
    gradientPoints: kind == GradientKind.none ? const [0, 0, 0, 0] : points,
  );

  /// Turned a further [angle] radians, kept in ]−π, π].
  ObjectLook turnedBy(double angle) =>
      copyWith(rotation: normalAngle(rotation + angle));

  /// Mirrored once more left-right, as the sheet shows it: the turn changes
  /// sides too, so that the drawing seen is the mirror of the one before.
  ObjectLook flippedLeftRight() =>
      copyWith(mirrorX: !mirrorX, rotation: normalAngle(-rotation));

  /// Mirrored once more top-bottom, as the sheet shows it.
  ObjectLook flippedTopBottom() =>
      copyWith(mirrorY: !mirrorY, rotation: normalAngle(-rotation));

  @override
  bool operator ==(Object other) =>
      other is ObjectLook &&
      other.rotation == rotation &&
      other.mirrorX == mirrorX &&
      other.mirrorY == mirrorY &&
      other.tool == tool &&
      other.zone == zone &&
      other.seed == seed &&
      other.gradient == gradient &&
      other.gradientRgb == gradientRgb &&
      _samePoints(other.gradientPoints, gradientPoints);

  @override
  int get hashCode => Object.hash(
    rotation,
    mirrorX,
    mirrorY,
    tool,
    zone,
    seed,
    gradient,
    gradientRgb,
    Object.hashAll(gradientPoints),
  );

  static bool _samePoints(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// [angle] brought into ]−π, π], as the core keeps a turn; a turn of almost
/// nothing is none.
double normalAngle(double angle) {
  var a = angle % (2 * math.pi);
  if (a > math.pi) a -= 2 * math.pi;
  if (a <= -math.pi) a += 2 * math.pi;
  if (a.abs() < 1e-6) return 0;
  // The core keeps single precision: an angle just above π in it is refused.
  if (a > 3.1415925) return 3.1415925;
  return a;
}

/// The marks of a stroke drawn with a tool of Color 1.1, as the core makes
/// them (EpMark): polygons and discs, grouped by colour and opacity, each
/// group filled at once. Immutable once made.
final class ObjectMarks {
  ObjectMarks({
    required this.shapes,
    required this.rgbs,
    required this.alphas,
    required this.groups,
    required this.firsts,
    required this.counts,
    required this.radii,
    required this.points,
  });

  static final empty = ObjectMarks(
    shapes: Uint32List(0),
    rgbs: Uint32List(0),
    alphas: Uint32List(0),
    groups: Uint32List(0),
    firsts: Uint32List(0),
    counts: Uint32List(0),
    radii: Float32List(0),
    points: Float32List(0),
  );

  /// 0 a polygon of its points, 1 a disc about its single point.
  final Uint32List shapes;
  final Uint32List rgbs;

  /// 1 to 255.
  final Uint32List alphas;

  /// Marks of one group follow each other and share colour and opacity.
  final Uint32List groups;

  /// Index of the mark's first point in [points], counted in points.
  final Uint32List firsts;
  final Uint32List counts;

  /// Of a disc; 0 for a polygon.
  final Float32List radii;

  /// x then y of every point of every mark.
  final Float32List points;

  int get length => shapes.length;
  bool get isEmpty => shapes.isEmpty;
}
