// SPDX-License-Identifier: MIT
// The companion of the window, « Debout pour peindre » (logo n° 7), which
// moves (Color 1.1): touched, the child sits down in the chair, stands up
// again with it and gives a stroke of the brush. With the option « Le
// personnage réagit », it does so too when the child has saved a drawing or
// taken a new sheet. Its parts are the named groups of its SVG file; the
// core keeps their names, and this moves them. Never when the system asks
// for less motion.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'child_art.dart';
import 'vector_art.dart';

class Companion extends StatefulWidget {
  const Companion({super.key, required this.size, this.cue});

  final double size;

  /// Each change of its value plays the movement once: a reaction.
  final ValueListenable<int>? cue;

  /// How long the movement lasts.
  static const duration = Duration(milliseconds: 1400);

  /// How many times a companion began to move, for the tests.
  @visibleForTesting
  static int debugPlays = 0;

  /// How far the parts are moved at [t], from 0 to 1 along the movement:
  /// the matrices of the named groups of the picture, in its units.
  @visibleForTesting
  static Map<String, Float64List> movesAt(double t) {
    if (t <= 0 || t >= 1) return const {};
    // Seated, then standing again: how far down the seat is, 0 to 1.
    double ease(double x) => x * x * (3 - 2 * x);
    final down = t < .25
        ? ease(t / .25)
        : t < .40
        ? 1.0
        : t < .65
        ? 1 - ease((t - .40) / .25)
        : 0.0;
    // Then a stroke of the brush: the arm goes back, forth, and rests.
    final degrees = t < .65
        ? 0.0
        : t < .78
        ? -20 * ease((t - .65) / .13)
        : t < .90
        ? -20 + 34 * ease((t - .78) / .12)
        : 14 * (1 - ease((t - .90) / .10));
    final lowered = Matrix4.translationValues(0, _seatDrop * down, 0);
    final legs = Matrix4.translationValues(0, _feet, 0)
      ..multiply(Matrix4.diagonal3Values(1, 1 - .35 * down, 1))
      ..multiply(Matrix4.translationValues(0, -_feet, 0));
    final arm = lowered.clone()
      ..multiply(Matrix4.translationValues(_shoulder.dx, _shoulder.dy, 0))
      ..multiply(Matrix4.rotationZ(degrees * math.pi / 180))
      ..multiply(Matrix4.translationValues(-_shoulder.dx, -_shoulder.dy, 0));
    return {
      for (final part in _upperParts) part: lowered.storage,
      'raised-arm-and-brush': arm.storage,
      'legs-and-knee-support': legs.storage,
    };
  }

  // Where the parts of « Debout pour peindre » are, in the units of its
  // groups: how far the seat goes down, the line of the feet, the shoulder
  // the arm turns about.
  static const _seatDrop = 55.0;
  static const _feet = 438.0;
  static const _shoulder = Offset(330, 185);
  static const _upperParts = [
    'chair-back-and-headrest',
    'shirt-and-chest-support',
    'face-and-hair',
    'armrest-hand-and-joystick',
  ];

  @override
  State<Companion> createState() => _CompanionState();
}

class _CompanionState extends State<Companion>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: Companion.duration,
  );

  @override
  void initState() {
    super.initState();
    widget.cue?.addListener(_play);
  }

  @override
  void didUpdateWidget(Companion old) {
    super.didUpdateWidget(old);
    if (old.cue != widget.cue) {
      old.cue?.removeListener(_play);
      widget.cue?.addListener(_play);
    }
  }

  @override
  void dispose() {
    widget.cue?.removeListener(_play);
    _motion.dispose();
    super.dispose();
  }

  void _play() {
    if (!mounted || MediaQuery.maybeDisableAnimationsOf(context) == true) {
      return;
    }
    Companion.debugPlays++;
    _motion.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final picture = VectorArtCatalog.instance?['mascotte'];
    // Without the picture of the core, the drawing of before, still.
    if (picture == null) {
      return EduIllustration(art: EduArt.mascot, size: widget.size);
    }
    return ExcludeSemantics(
      child: GestureDetector(
        key: const Key('companion'),
        behavior: HitTestBehavior.opaque,
        onTap: _play,
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(painter: _CompanionPainter(picture, _motion)),
        ),
      ),
    );
  }
}

class _CompanionPainter extends CustomPainter {
  _CompanionPainter(this.picture, this.motion) : super(repaint: motion);
  final VectorPicture picture;
  final Animation<double> motion;

  @override
  void paint(Canvas canvas, Size size) => picture.paint(
    canvas,
    Offset.zero & size,
    moves: motion.isAnimating
        ? Companion.movesAt(motion.value)
        : const <String, Float64List>{},
  );

  @override
  bool shouldRepaint(_CompanionPainter old) =>
      old.picture != picture || old.motion != motion;
}
