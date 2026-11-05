// SPDX-License-Identifier: MIT
// The choices of the tools of Color 1.1, where the help is written: the
// tips of the brush, the magics, and in « Formes » the rectangle, the oval,
// the shapes of 1.1 and the magnet. Each choice shows what it draws, painted
// by the core as the sheet will paint it.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'document_renderer.dart' show insidePaint, markPaths, markerAlpha;
import 'rust_document.dart';
import 'stamp_catalog.dart';
import 'stamp_dialog.dart';
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

/// The row of choices of [tool]: nothing for a tool without any.
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
    this.stamp,
    this.stampLook = ObjectLook.plain,
    this.onTurnStamp,
    this.onMirrorStamp,
    this.onBrush,
    this.onMagic,
    this.onShape,
    this.onTool,
    this.onPour,
  });

  final StudioTool tool;
  final BrushTool brush;
  final Magic magic;
  final NewShape shape;

  /// The colour the choices are shown in: the current one.
  final int rgb;

  /// How the pot pours, and the second colour of its gradients.
  final PourKind pour;
  final int secondRgb;

  /// The stamp a click poses, and how it is turned and mirrored; null when
  /// the catalogue is not there.
  final StampArt? stamp;
  final ObjectLook stampLook;
  final VoidCallback? onTurnStamp;
  final VoidCallback? onMirrorStamp;

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
          ),
      if (tool == StudioTool.magic)
        for (final each in Magic.values)
          _Choice(
            buttonKey: Key('magic-${each.name}'),
            name: each.label,
            selected: each == magic,
            onPressed: onMagic == null ? null : () => onMagic!(each),
            preview: _VariantPreview.magic(each, rgb),
          ),
      if (tool == StudioTool.stamp && stamp != null) ...[
        _Choice(
          buttonKey: const Key('turnStamp'),
          name: tr('Tourner le tampon'),
          selected: stampLook.rotation != 0,
          onPressed: onTurnStamp,
          picture: _turned(stamp!, stampLook, Icons.rotate_right),
        ),
        _Choice(
          buttonKey: const Key('mirrorStamp'),
          name: tr('Retourner le tampon'),
          selected: stampLook.mirrorX,
          onPressed: onMirrorStamp,
          picture: _turned(stamp!, stampLook, Icons.flip),
        ),
      ],
      if (tool == StudioTool.fill)
        for (final each in PourKind.values)
          _Choice(
            buttonKey: Key('pour-${each.name}'),
            name: each.label,
            selected: each == pour,
            onPressed: onPour == null ? null : () => onPour!(each),
            preview: _VariantPreview.pour(each, rgb, secondRgb),
          ),
      if (tool.group == ToolGroup.shapes) ...[
        for (final box in [StudioTool.rectangle, StudioTool.ellipse])
          _Choice(
            buttonKey: Key(box.keyName),
            name: box.label,
            selected: tool == box,
            onPressed: onTool == null ? null : () => onTool!(box),
            preview: _VariantPreview.box(box.kind!, rgb),
          ),
        for (final each in NewShape.values)
          _Choice(
            buttonKey: Key('shape-${each.name}'),
            name: newShapeName(each),
            selected: tool == StudioTool.shapes && each == shape,
            onPressed: onShape == null ? null : () => onShape!(each),
            preview: _VariantPreview.shape(each, rgb),
          ),
        _Choice(
          buttonKey: Key(StudioTool.magnet.keyName),
          name: StudioTool.magnet.label,
          selected: tool == StudioTool.magnet,
          onPressed: onTool == null ? null : () => onTool!(StudioTool.magnet),
          preview: _VariantPreview.magnet(rgb),
        ),
      ],
    ];
    if (choices.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: choices);
  }

  // The stamp as it will be posed, with the sign of what the button does.
  Widget _turned(StampArt art, ObjectLook look, IconData sign) => Stack(
    children: [
      Center(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationZ(look.rotation)
            ..multiply(Matrix4.diagonal3Values(look.mirrorX ? -1 : 1, 1, 1)),
          child: StampPreview(stamp: art, rgb: rgb, size: 30),
        ),
      ),
      Positioned(
        right: 0,
        bottom: 0,
        child: Icon(sign, size: 14, color: studioInk),
      ),
    ],
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.buttonKey,
    required this.name,
    required this.selected,
    required this.onPressed,
    this.preview,
    this.picture,
  });

  /// The key of the button, which carries its name and its state for a
  /// screen reader, as the buttons of the tool bar do.
  final Key buttonKey;
  final String name;
  final bool selected;
  final VoidCallback? onPressed;

  /// What it draws, painted; or [picture], made of widgets.
  final _VariantPreview? preview;
  final Widget? picture;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: name,
    excludeFromSemantics: true,
    child: OutlinedButton(
      key: buttonKey,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(52, 48),
        maximumSize: const Size(52, 48),
        padding: const EdgeInsets.all(4),
        backgroundColor: selected ? studioSelected : studioSurface,
        side: BorderSide(
          color: selected ? studioGreen : studioLine,
          width: selected ? 2 : 1,
        ),
      ),
      // The name and the state on the button itself: a screen reader meets
      // one control, which it can press.
      child: Semantics(
        selected: selected,
        label: name,
        child: ExcludeSemantics(
          child: SizedBox(
            width: 42,
            height: 38,
            child: picture ?? CustomPaint(painter: preview),
          ),
        ),
      ),
    ),
  );
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
