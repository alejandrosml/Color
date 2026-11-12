// SPDX-License-Identifier: MIT
// The shapes of the studio in the look of the moment (Color 1.2): the
// corners and the line of its buttons, the frame and the shadow of its
// panels. « Classique » draws what Color always drew.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'studio_colors.dart';

/// A rounded rectangle whose line is made of dashes: the buttons of the
/// universe of paper, cut out along a dotted line.
class DashedRoundedBorder extends RoundedRectangleBorder {
  const DashedRoundedBorder({super.side, super.borderRadius});

  @override
  DashedRoundedBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => DashedRoundedBorder(
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  ShapeBorder scale(double t) =>
      DashedRoundedBorder(side: side.scale(t), borderRadius: borderRadius * t);

  // Between two of them, or to and from another shape: the shape of the
  // end, at once. A button never stays between two looks.
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => this;

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => t < 1 ? this : b;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    final box = borderRadius
        .resolve(textDirection)
        .toRRect(rect)
        .deflate(side.width / 2);
    final dashes = Path();
    for (final metric in (Path()..addRRect(box)).computeMetrics()) {
      // Whole dashes all around: none is cut where the line closes.
      final count = math.max(4, (metric.length / (side.width * 5)).round());
      final step = metric.length / count;
      for (var index = 0; index < count; index++) {
        dashes.addPath(
          metric.extractPath(index * step, index * step + step * .6),
          Offset.zero,
        );
      }
    }
    canvas.drawPath(
      dashes,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = side.width
        ..color = side.color,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DashedRoundedBorder &&
      other.side == side &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(DashedRoundedBorder, side, borderRadius);
}

/// The shape of a button in [look]: its corners, and dashes when the look
/// asks for them. Its line comes from the button.
OutlinedBorder studioButtonShape([StudioLook? look]) {
  final worn = look ?? studioLook.value;
  final corners = BorderRadius.circular(worn.buttonRadius);
  return worn.buttonDashed
      ? DashedRoundedBorder(borderRadius: corners)
      : RoundedRectangleBorder(borderRadius: corners);
}

/// The line of a quiet button in [look].
BorderSide studioButtonSide([StudioLook? look]) {
  final worn = look ?? studioLook.value;
  return BorderSide(color: worn.line, width: worn.buttonBorder);
}

/// What a panel of the studio is drawn on in the look of the moment: its
/// surface, its corners, its line and its shadow. [radius] is the radius
/// the panel has in « Classique »: a look with sharper corners sharpens it
/// in proportion. A panel of « Classique » without a line — the idea card —
/// says so with [line].
BoxDecoration studioPanel({
  Color? color,
  double radius = 20,
  bool line = true,
}) {
  final look = studioLook.value;
  return BoxDecoration(
    color: color ?? look.surface,
    borderRadius: BorderRadius.circular(
      radius * look.panelRadius / StudioLook.classic.panelRadius,
    ),
    border: line && look.panelBorder > 0
        ? Border.all(color: look.line, width: look.panelBorder)
        : null,
    boxShadow: switch (look.panelShadow) {
      PanelShadow.none => null,
      PanelShadow.soft => const [
        BoxShadow(
          color: Color(0x0f4a3a6e),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
        BoxShadow(
          color: Color(0x174a3a6e),
          blurRadius: 22,
          offset: Offset(0, 8),
        ),
      ],
      PanelShadow.paper => const [
        BoxShadow(color: Color(0x2e5a3c1e), offset: Offset(0, 2)),
        BoxShadow(
          color: Color(0x385a3c1e),
          blurRadius: 14,
          offset: Offset(0, 6),
        ),
      ],
    },
  );
}

/// The colours of the round stickers under the pictures of the tools, in a
/// look that draws them so: one per tool, in the order of the bar.
const _stickers = [
  Color(0xfff4b7cf),
  Color(0xffa4e0c1),
  Color(0xfffff0b8),
  Color(0xffa8d8f0),
  Color(0xfff3c3a6),
  Color(0xffd6cdee),
];

/// The picture of tool number [index] as the look of the moment shows it
/// in the bar: as it is on a tile, or on a round sticker of colour, with a
/// ring of the accent when it is the [chosen] one.
Widget studioToolPicture(
  Widget picture, {
  required int index,
  required bool chosen,
  required double size,
}) {
  final look = studioLook.value;
  if (look.tool != ToolShape.sticker) return picture;
  return Container(
    width: size + 12,
    height: size + 12,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _stickers[index % _stickers.length],
      shape: BoxShape.circle,
      border: chosen ? Border.all(color: look.accent, width: 3) : null,
      boxShadow: const [
        BoxShadow(color: Color(0x595a3c1e), offset: Offset(0, 1)),
      ],
    ),
    child: picture,
  );
}
