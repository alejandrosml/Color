// SPDX-License-Identifier: MIT
// The choices of the tools of Color 1.1, where the help is written: the
// tips of the brush, the magics, and in « Formes » the rectangle, the oval,
// the shapes of 1.1 and the magnet. Each choice shows what it draws, painted
// by the core as the sheet will paint it.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'document_renderer.dart' show insidePaint, markPaths, markerAlpha;
import 'galets.dart';
import 'rust_document.dart';
import 'studio_colors.dart';
import 'studio_tool.dart';
import 'language.dart';

/// The name of a tip of the brush, for the child.
String brushToolName(BrushTool tool) => switch (tool) {
  BrushTool.round => tr('Rond'),
  BrushTool.felt => tr('Feutre'),
  BrushTool.calligraphy => tr('Plume'),
  BrushTool.chalk => tr('Craie'),
  BrushTool.airbrush => tr('Aérographe'),
  BrushTool.rainbow => tr('Arc-en-ciel'),
  BrushTool.grass => tr('Herbe'),
  BrushTool.bricks => tr('Briques'),
  BrushTool.confetti => tr('Confettis'),
};

/// The name of a shape of 1.1, for the child.
String newShapeName(NewShape shape) => switch (shape) {
  NewShape.triangle => tr('Triangle'),
  NewShape.star => tr('Étoile'),
  NewShape.heart => tr('Cœur'),
  NewShape.diamond => tr('Losange'),
  NewShape.hexagon => tr('Hexagone'),
  NewShape.arrow => tr('Flèche'),
};

/// How the paint pot pours: one colour, or a gradient from the current
/// colour to the one chosen before it, along the zone or from its middle.
enum PourKind {
  plain('Une couleur'),
  linear('Dégradé'),
  radial('Dégradé rond');

  const PourKind(this.frenchLabel);
  final String frenchLabel;
  String get label => tr(frenchLabel);

  /// The look a poured inside takes, from [look], to [second].
  ObjectLook lookOf(ObjectLook look, int second) => switch (this) {
    plain => look.withGradient(GradientKind.none),
    linear => look.withGradient(
      GradientKind.linear,
      rgb: second,
      points: const [.5, 0, .5, 1],
    ),
    radial => look.withGradient(
      GradientKind.radial,
      rgb: second,
      points: const [.5, .5, 1, .5],
    ),
  };
}

/// The tips of the brush, in the order of their buttons.
const brushTips = [
  BrushTool.round,
  BrushTool.felt,
  BrushTool.calligraphy,
  BrushTool.chalk,
  BrushTool.airbrush,
];

/// How the choices of a tool are drawn among the pebbles (Color 1.2).
enum ToolVariantStyle {
  /// Large buttons, each with its name under what it draws: in a panel.
  tiles,

  /// Cells with what each draws, its name said and shown on demand: in
  /// the drawer of a rail, which has the width of a telephone.
  cells,
}

/// The choices of [tool]: nothing for a tool without any.
class ToolVariants extends StatelessWidget {
  const ToolVariants({
    super.key,
    required this.tool,
    required this.brush,
    required this.magic,
    required this.shape,
    required this.rgb,
    this.pour = PourKind.plain,
    this.secondRgb = 0xffffff,
    this.onBrush,
    this.onMagic,
    this.onShape,
    this.onTool,
    this.onPour,
    this.style = ToolVariantStyle.tiles,
    this.tileWidth = 104,
  });

  /// How each choice is drawn. The two buttons that turn a stamp are left
  /// to the panel, which has them with the stamps.
  final ToolVariantStyle style;

  /// The width of a tile: wider with enlarged letters.
  final double tileWidth;

  final StudioTool tool;
  final BrushTool brush;
  final Magic magic;
  final NewShape shape;

  /// The colour the choices are shown in: the current one.
  final int rgb;

  /// How the pot pours, and the second colour of its gradients.
  final PourKind pour;
  final int secondRgb;

  /// Null while the studio is busy: the choices are then disabled.
  final ValueChanged<BrushTool>? onBrush;
  final ValueChanged<Magic>? onMagic;
  final ValueChanged<NewShape>? onShape;

  /// The rectangle, the oval or the magnet chosen in « Formes ».
  final ValueChanged<StudioTool>? onTool;
  final ValueChanged<PourKind>? onPour;

  /// Whether [tool] has choices of its own.
  static bool offers(StudioTool tool) =>
      tool == StudioTool.brush ||
      tool == StudioTool.magic ||
      tool == StudioTool.fill ||
      tool == StudioTool.stamp ||
      tool.group == ToolGroup.shapes;

  @override
  Widget build(BuildContext context) {
    final choices = <Widget>[
      if (tool == StudioTool.brush)
        for (final tip in brushTips)
          _Choice(
            buttonKey: Key('brushTip-${tip.name}'),
            name: brushToolName(tip),
            selected: tip == brush,
            onPressed: onBrush == null ? null : () => onBrush!(tip),
            preview: _VariantPreview.brush(tip, rgb),
            style: style,
            tileWidth: tileWidth,
          ),
      if (tool == StudioTool.magic)
        for (final each in Magic.values)
          _Choice(
            buttonKey: Key('magic-${each.name}'),
            name: each.label,
            selected: each == magic,
            onPressed: onMagic == null ? null : () => onMagic!(each),
            preview: _VariantPreview.magic(each, rgb),
            style: style,
            tileWidth: tileWidth,
          ),
      if (tool == StudioTool.fill)
        for (final each in PourKind.values)
          _Choice(
            buttonKey: Key('pour-${each.name}'),
            name: each.label,
            selected: each == pour,
            onPressed: onPour == null ? null : () => onPour!(each),
            preview: _VariantPreview.pour(each, rgb, secondRgb),
            style: style,
            tileWidth: tileWidth,
          ),
      if (tool.group == ToolGroup.shapes) ...[
        for (final box in [StudioTool.rectangle, StudioTool.ellipse])
          _Choice(
            buttonKey: Key(box.keyName),
            name: box.label,
            selected: tool == box,
            onPressed: onTool == null ? null : () => onTool!(box),
            preview: _VariantPreview.box(box.kind!, rgb),
            style: style,
            tileWidth: tileWidth,
          ),
        for (final each in NewShape.values)
          _Choice(
            buttonKey: Key('shape-${each.name}'),
            name: newShapeName(each),
            selected: tool == StudioTool.shapes && each == shape,
            onPressed: onShape == null ? null : () => onShape!(each),
            preview: _VariantPreview.shape(each, rgb),
            style: style,
            tileWidth: tileWidth,
          ),
        _Choice(
          buttonKey: Key(StudioTool.magnet.keyName),
          name: StudioTool.magnet.label,
          selected: tool == StudioTool.magnet,
          onPressed: onTool == null ? null : () => onTool!(StudioTool.magnet),
          preview: _VariantPreview.magnet(rgb),
          style: style,
          tileWidth: tileWidth,
        ),
      ],
    ];
    if (choices.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 4, runSpacing: 4, children: choices);
  }

  /// What [tool] draws with the choices of the moment, small: the witness
  /// on the « lequel » button of the pebbles. Null for a tool without
  /// choices, or whose witness is not a drawing (the stamp).
  static CustomPainter? witness({
    required StudioTool tool,
    required BrushTool brush,
    required Magic magic,
    required NewShape shape,
    required int rgb,
    PourKind pour = PourKind.plain,
    int secondRgb = 0xffffff,
    Color? outline,
  }) {
    final preview = switch (tool) {
      StudioTool.brush => _VariantPreview.brush(brush, rgb),
      StudioTool.magic => _VariantPreview.magic(magic, rgb),
      StudioTool.fill => _VariantPreview.pour(pour, rgb, secondRgb),
      StudioTool.rectangle ||
      StudioTool.ellipse => _VariantPreview.box(tool.kind!, rgb),
      StudioTool.shapes => _VariantPreview.shape(shape, rgb),
      StudioTool.magnet => _VariantPreview.magnet(rgb),
      _ => null,
    };
    if (preview == null) return null;
    return outline == null ? preview : _Outlined(preview, outline);
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.buttonKey,
    required this.name,
    required this.selected,
    required this.onPressed,
    this.preview,
    this.style = ToolVariantStyle.tiles,
    this.tileWidth = 104,
  });

  final ToolVariantStyle style;
  final double tileWidth;

  /// The key of the button, which carries its name and its state for a
  /// screen reader, as the buttons of the line do.
  final Key buttonKey;
  final String name;
  final bool selected;
  final VoidCallback? onPressed;

  /// What it draws, painted.
  final _VariantPreview? preview;

  @override
  Widget build(BuildContext context) => switch (style) {
    ToolVariantStyle.tiles => GaletTile(
      key: buttonKey,
      name: name,
      selected: selected,
      onPressed: onPressed,
      width: tileWidth,
      picture: SizedBox(
        width: 61,
        height: 36,
        child: CustomPaint(painter: preview),
      ),
    ),
    ToolVariantStyle.cells => GaletButton(
      key: buttonKey,
      label: name,
      selected: selected,
      framed: true,
      onPressed: onPressed,
      width: 48,
      height: 48,
      child: SizedBox(
        width: 38,
        height: 24,
        child: CustomPaint(painter: preview),
      ),
    ),
  };
}

/// What a choice draws, small.
class _VariantPreview extends CustomPainter {
  _VariantPreview.brush(BrushTool this.tool, this.rgb)
    : magic = null,
      shape = null,
      box = null,
      magnet = false,
      pour = null,
      secondRgb = 0;
  _VariantPreview.pour(PourKind this.pour, this.rgb, this.secondRgb)
    : tool = null,
      magic = null,
      shape = null,
      box = null,
      magnet = false;
  _VariantPreview.magic(Magic this.magic, this.rgb)
    : tool = switch (magic) {
        Magic.rainbow => BrushTool.rainbow,
        Magic.grass => BrushTool.grass,
        Magic.bricks => BrushTool.bricks,
        Magic.confetti => BrushTool.confetti,
        Magic.mirror => BrushTool.round,
      },
      shape = null,
      box = null,
      magnet = false,
      pour = null,
      secondRgb = 0;
  _VariantPreview.shape(NewShape this.shape, this.rgb)
    : tool = null,
      magic = null,
      box = null,
      magnet = false,
      pour = null,
      secondRgb = 0;
  _VariantPreview.box(VectorKind this.box, this.rgb)
    : tool = null,
      magic = null,
      shape = null,
      magnet = false,
      pour = null,
      secondRgb = 0;
  _VariantPreview.magnet(this.rgb)
    : tool = null,
      magic = null,
      shape = null,
      box = null,
      magnet = true,
      pour = null,
      secondRgb = 0;

  final BrushTool? tool;
  final Magic? magic;
  final NewShape? shape;

  /// A rectangle or an oval.
  final VectorKind? box;

  /// A shape drawn by hand, and the straight one it becomes.
  final bool magnet;

  /// What the pot pours, from [rgb] to [secondRgb].
  final PourKind? pour;
  final int secondRgb;
  final int rgb;

  // A little wave across the button.
  static List<DocumentPoint> _wave(
    Size size, {
    double from = .1,
    double to = .9,
  }) => [
    for (var i = 0; i <= 24; i++)
      DocumentPoint(
        size.width * (from + (to - from) * i / 24),
        size.height * (.5 + .28 * math.sin(i / 24 * 2 * math.pi)),
      ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final colour = Color(0xff000000 | rgb);
    final outline = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    final pour = this.pour;
    if (pour != null) {
      final area = Rect.fromLTRB(
        size.width * .1,
        size.height * .12,
        size.width * .9,
        size.height * .88,
      );
      final inside = insidePaint(
        StrokeData(
          [
            area.topLeft,
            area.bottomRight,
          ].map((p) => DocumentPoint(p.dx, p.dy)).toList(),
          rgb,
          1,
          kind: VectorKind.rectangle,
          fillRgb: rgb,
          look: pour.lookOf(ObjectLook.plain, secondRgb),
        ),
        area,
      );
      final rounded = RRect.fromRectAndRadius(area, const Radius.circular(6));
      canvas.drawRRect(rounded, inside);
      canvas.drawRRect(
        rounded,
        Paint()
          ..color = studioLine
          ..style = PaintingStyle.stroke,
      );
      return;
    }
    final box = this.box;
    if (box != null) {
      final area = Rect.fromLTRB(
        size.width * .14,
        size.height * .18,
        size.width * .86,
        size.height * .82,
      );
      final inside = Paint()..color = colour.withAlpha(90);
      if (box == VectorKind.ellipse) {
        canvas.drawOval(area, inside);
        canvas.drawOval(area, outline);
      } else {
        canvas.drawRect(area, inside);
        canvas.drawRect(area, outline);
      }
      return;
    }
    if (magnet) {
      // A round drawn by hand, light, and the circle it becomes.
      final centre = size.center(Offset.zero);
      final radius = size.shortestSide * .36;
      final wobbly = Path();
      for (var i = 0; i <= 36; i++) {
        final angle = i / 36 * 2 * math.pi;
        final r = radius * (1 + .13 * math.sin(angle * 3 + .6));
        final point = centre + Offset(math.cos(angle), math.sin(angle)) * r;
        if (i == 0) {
          wobbly.moveTo(point.dx, point.dy);
        } else {
          wobbly.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        wobbly,
        Paint()
          ..color = colour.withAlpha(80)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(centre, radius, outline);
      return;
    }
    final shape = this.shape;
    if (shape != null) {
      final points = _outline(shape, size);
      if (points == null) return;
      final path = Path()..moveTo(points.first.x, points.first.y);
      for (final point in points.skip(1)) {
        path.lineTo(point.x, point.y);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = colour.withAlpha(90));
      canvas.drawPath(
        path,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
      return;
    }
    if (magic == Magic.mirror) {
      // A trait and its mirror, on each side of a dotted middle.
      final half = _wave(size, from: .06, to: .44);
      _line(canvas, half, colour, 3);
      _line(
        canvas,
        [for (final p in half) DocumentPoint(size.width - p.x, p.y)],
        colour,
        3,
      );
      final dots = Paint()..color = studioLine;
      for (var y = 2.0; y < size.height; y += 5) {
        canvas.drawCircle(Offset(size.width / 2, y), 1, dots);
      }
      return;
    }
    final tool = this.tool!;
    final points = _wave(size);
    if (tool.paintsMarks) {
      try {
        final marks = RustDocument.strokeMarks(
          points,
          width: tool == BrushTool.airbrush || tool == BrushTool.chalk ? 9 : 7,
          rgb: rgb,
          tool: tool,
          seed: 7,
        );
        if (marks != null) {
          for (final (path, paint) in markPaths(marks)) {
            canvas.drawPath(path, paint);
          }
          return;
        }
      } catch (_) {
        // Without the core, the plain trait stands for it.
      }
    }
    _line(
      canvas,
      points,
      tool == BrushTool.felt ? colour.withAlpha(markerAlpha) : colour,
      tool == BrushTool.felt ? 7 : 5,
      square: tool == BrushTool.felt,
    );
  }

  static List<DocumentPoint>? _outline(NewShape shape, Size size) {
    try {
      return RustDocument.shapeOutline(
        shape,
        DocumentPoint(size.width * .22, size.height * .08),
        DocumentPoint(size.width * .78, size.height * .92),
      );
    } catch (_) {
      return null;
    }
  }

  static void _line(
    Canvas canvas,
    List<DocumentPoint> points,
    Color colour,
    double width, {
    bool square = false,
  }) {
    final path = Path()..moveTo(points.first.x, points.first.y);
    for (final point in points.skip(1)) {
      path.lineTo(point.x, point.y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = square ? StrokeCap.square : StrokeCap.round
        ..strokeJoin = square ? StrokeJoin.bevel : StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_VariantPreview old) =>
      old.tool != tool ||
      old.magic != magic ||
      old.shape != shape ||
      old.box != box ||
      old.magnet != magnet ||
      old.pour != pour ||
      old.secondRgb != secondRgb ||
      old.rgb != rgb;
}

/// A preview with a thin line of [outline] around what it draws: a colour
/// as light as the surface of a pebble would be lost on it.
class _Outlined extends CustomPainter {
  const _Outlined(this.inner, this.outline);
  final _VariantPreview inner;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(
      null,
      Paint()..colorFilter = ColorFilter.mode(outline, BlendMode.srcIn),
    );
    for (final shift in const [
      Offset(-.9, 0),
      Offset(.9, 0),
      Offset(0, -.9),
      Offset(0, .9),
    ]) {
      canvas.save();
      canvas.translate(shift.dx, shift.dy);
      inner.paint(canvas, size);
      canvas.restore();
    }
    canvas.restore();
    inner.paint(canvas, size);
  }

  @override
  bool shouldRepaint(_Outlined old) =>
      old.outline != outline || inner.shouldRepaint(old.inner);
}
