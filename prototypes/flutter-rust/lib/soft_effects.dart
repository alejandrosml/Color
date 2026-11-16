// SPDX-License-Identifier: MIT
// Color — Alejandro San Martin Lamas — https://github.com/alejandrosml
//
// The soft effects of Color 1.2 (step 5): small rewards, never in the way.
// Confetti when the drawing is saved, a splash where the paint pot pours,
// sparkles where a magic line ends, and the pebbles' buttons that bounce
// when pressed. Each one is short, painted above everything in an overlay
// that no pointer can touch, and none is shown when the adult chose
// « Aucun » for the movement of the decor or when the system asks for less
// motion: the same switch as the decor.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Whether the adult left the decor some movement: the studio says so
/// whenever its options change.
bool softEffectsMotion = true;

/// Whether soft effects may play here: not with less motion asked by the
/// system, nor when the adult turned the movement off.
bool softEffectsHere(BuildContext context) =>
    softEffectsMotion && MediaQuery.maybeDisableAnimationsOf(context) != true;

/// For the tests: the effects that were asked for, by kind.
@visibleForTesting
final softEffectLog = <String>[];

void _play(
  BuildContext context,
  String kind,
  Duration duration,
  CustomPainter Function(double t) painter,
) {
  softEffectLog.add(kind);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    // Nothing to press, nothing for a screen reader: a picture that goes.
    builder: (_) => ExcludeSemantics(
      child: IgnorePointer(
        child: _Effect(
          duration: duration,
          painter: painter,
          onDone: () {
            if (entry.mounted) entry.remove();
          },
        ),
      ),
    ),
  );
  overlay.insert(entry);
}

/// Confetti that fall from the top of the window for a moment, when the
/// drawing is saved.
void showConfetti(BuildContext context) {
  final random = math.Random(7);
  final size = MediaQuery.sizeOf(context);
  final pieces = [
    for (var i = 0; i < 36; i++)
      _Piece(
        x: size.width * (.45 + .55 * random.nextDouble()),
        y: -12 - 40 * random.nextDouble(),
        drift: (random.nextDouble() - .5) * 120,
        fall: size.height * (.35 + .25 * random.nextDouble()),
        turn: (random.nextDouble() - .5) * 8,
        colour: _confettiColours[i % _confettiColours.length],
      ),
  ];
  _play(
    context,
    'confetti',
    const Duration(milliseconds: 1400),
    (t) => _ConfettiPainter(pieces, t),
  );
}

/// A splash of paint where the pot poured, at [at] in the window.
void showSplash(BuildContext context, Offset at, Color colour) => _play(
  context,
  'splash',
  const Duration(milliseconds: 650),
  (t) => _SplashPainter(at, colour, t),
);

/// Sparkles where a magic line ends, at [at] in the window.
void showSparkles(BuildContext context, Offset at) => _play(
  context,
  'sparkles',
  const Duration(milliseconds: 900),
  (t) => _SparklesPainter(at, t),
);

const _confettiColours = [
  Color(0xffe63946),
  Color(0xfff4a261),
  Color(0xffe9c46a),
  Color(0xff2a9d8f),
  Color(0xff457b9d),
  Color(0xff9b5de5),
];

class _Piece {
  const _Piece({
    required this.x,
    required this.y,
    required this.drift,
    required this.fall,
    required this.turn,
    required this.colour,
  });
  final double x, y, drift, fall, turn;
  final Color colour;
}

class _Effect extends StatefulWidget {
  const _Effect({
    required this.duration,
    required this.painter,
    required this.onDone,
  });
  final Duration duration;
  final CustomPainter Function(double t) painter;
  final VoidCallback onDone;

  @override
  State<_Effect> createState() => _EffectState();
}

class _EffectState extends State<_Effect> with SingleTickerProviderStateMixin {
  late final AnimationController _time = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _time,
      builder: (context, _) => CustomPaint(
        painter: widget.painter(_time.value),
        size: Size.infinite,
      ),
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // They fade only in the last fifth: nothing blinks.
    final fade = t < .8 ? 1.0 : (1 - t) / .2;
    for (final piece in pieces) {
      final paint = Paint()
        ..color = piece.colour.withValues(alpha: piece.colour.a * fade);
      canvas.save();
      canvas.translate(
        piece.x + piece.drift * t,
        piece.y + piece.fall * Curves.easeIn.transform(t),
      );
      canvas.rotate(piece.turn * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-4, -2.5, 8, 5),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

class _SplashPainter extends CustomPainter {
  _SplashPainter(this.at, this.colour, this.t);
  final Offset at;
  final Color colour;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final grow = Curves.easeOut.transform(t);
    final fade = 1 - t;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * fade + 1
      ..color = colour.withValues(alpha: .8 * fade);
    canvas.drawCircle(at, 8 + 26 * grow, ring);
    final drop = Paint()..color = colour.withValues(alpha: .9 * fade);
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 + .4;
      final reach = 10 + 24 * grow;
      canvas.drawCircle(
        at +
            Offset(math.cos(angle) * reach, math.sin(angle) * reach - 6 * grow),
        3.2 * fade + .6,
        drop,
      );
    }
  }

  @override
  bool shouldRepaint(_SplashPainter old) => old.t != t;
}

class _SparklesPainter extends CustomPainter {
  _SparklesPainter(this.at, this.t);
  final Offset at;
  final double t;

  static Path _star(double r) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 - math.pi / 2;
      final reach = i.isEven ? r : r * .38;
      final p = Offset(math.cos(a) * reach, math.sin(a) * reach);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Each star grows and then goes, once.
    const places = [
      Offset(-18, -14),
      Offset(16, -20),
      Offset(22, 10),
      Offset(-14, 18),
      Offset(2, -30),
    ];
    for (var i = 0; i < places.length; i++) {
      final local = ((t - i * .08) / .7).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final r = 7 * math.sin(local * math.pi);
      final paint = Paint()
        ..color = const Color(0xffffd166).withValues(alpha: 1 - local * .6);
      canvas.save();
      canvas.translate(at.dx + places[i].dx, at.dy + places[i].dy);
      canvas.drawPath(_star(r), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SparklesPainter old) => old.t != t;
}

/// A button of the pebbles that bounces a little when it is pressed: down
/// to 92 % and back, in a fifth of a second. Nothing moves when the
/// effects are not allowed.
class BounceOnPress extends StatefulWidget {
  const BounceOnPress({super.key, required this.child});
  final Widget child;

  @override
  State<BounceOnPress> createState() => _BounceOnPressState();
}

class _BounceOnPressState extends State<BounceOnPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!softEffectsHere(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _press.forward(from: 0),
      child: AnimatedBuilder(
        animation: _press,
        child: widget.child,
        builder: (context, child) => Transform.scale(
          scale: 1 - .08 * math.sin(_press.value * math.pi),
          child: child,
        ),
      ),
    );
  }
}
