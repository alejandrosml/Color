// SPDX-License-Identifier: MIT
// « Régler le toucher » (Color 1.1): three targets to touch, one after the
// other; how far the finger landed from their centres, on average, is the
// shift the studio gives every finger on the sheet. For a child whose touch
// lands always a little beside what it aims at, or a screen that is read
// from a slant.
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'fit_to_screen.dart';
import 'studio_colors.dart';
import 'studio_options.dart';
import 'language.dart';

/// The shift found, or null when the dialog is left without keeping it.
/// [Offset.zero] when the adult asks for none.
Future<Offset?> showTouchCalibration(BuildContext context) =>
    showDialog<Offset>(
      context: context,
      builder: (_) => const FitDialog(child: TouchCalibrationDialog()),
    );

class TouchCalibrationDialog extends StatefulWidget {
  const TouchCalibrationDialog({super.key});

  /// Where the targets stand, as fractions of the area.
  static const targets = [Offset(.25, .3), Offset(.75, .45), Offset(.45, .75)];

  /// The shift of the touches given, each the target less where it landed;
  /// far misses, which aimed at nothing, are left out.
  static Offset shiftOf(List<Offset> misses) {
    final kept = [
      for (final miss in misses)
        if (miss.distance <= StudioOptions.maxTouchShift * 1.5) miss,
    ];
    if (kept.isEmpty) return Offset.zero;
    var sum = Offset.zero;
    for (final miss in kept) {
      sum += miss;
    }
    final mean = sum / kept.length.toDouble();
    double bound(double value) => value
        .clamp(-StudioOptions.maxTouchShift, StudioOptions.maxTouchShift)
        .roundToDouble();
    return Offset(bound(mean.dx), bound(mean.dy));
  }

  @override
  State<TouchCalibrationDialog> createState() => _TouchCalibrationState();
}

class _TouchCalibrationState extends State<TouchCalibrationDialog> {
  static const _area = Size(360, 270);
  final _misses = <Offset>[];

  bool get _done => _misses.length >= TouchCalibrationDialog.targets.length;

  void _touched(PointerDownEvent event, Size area) {
    if (_done) return;
    final target = TouchCalibrationDialog.targets[_misses.length];
    final centre = Offset(target.dx * area.width, target.dy * area.height);
    setState(() => _misses.add(centre - event.localPosition));
  }

  @override
  Widget build(BuildContext context) {
    final shift = TouchCalibrationDialog.shiftOf(_misses);
    return AlertDialog(
      key: const Key('touchCalibrationDialog'),
      title: Text(tr('Régler le toucher')),
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _done
                  ? (shift == Offset.zero
                        ? tr(
                            'Le doigt touche juste là où il vise : rien à régler.',
                          )
                        : trf(
                            'C’est fait : les traits du doigt seront décalés de {0} et {1} points.',
                            [shift.dx.round(), shift.dy.round()],
                          ))
                  : trf(
                      'Touche le centre de la cible avec le doigt, comme pour dessiner ({0} sur {1}).',
                      [
                        _misses.length + 1,
                        TouchCalibrationDialog.targets.length,
                      ],
                    ),
              key: const Key('touchCalibrationText'),
            ),
            const SizedBox(height: 12),
            // A fixed area, never stretched: the dialog measures what it
            // holds, and the targets are placed in it.
            Center(
              child: SizedBox.fromSize(
                size: _area,
                child: Listener(
                  key: const Key('touchCalibrationArea'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    // A finger is what is being measured.
                    if (event.kind == PointerDeviceKind.touch) {
                      _touched(event, _area);
                    }
                  },
                  child: CustomPaint(
                    painter: _TargetPainter(
                      _done
                          ? null
                          : TouchCalibrationDialog.targets[_misses.length],
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('resetTouchShift'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.pop(context, Offset.zero),
          child: Text(tr('Aucun réglage')),
        ),
        TextButton(
          key: const Key('cancelTouchCalibration'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Annuler')),
        ),
        if (_done)
          TextButton(
            key: const Key('againTouchCalibration'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => setState(_misses.clear),
            child: Text(tr('Recommencer')),
          ),
        FilledButton(
          key: const Key('keepTouchShift'),
          style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
          onPressed: _done ? () => Navigator.pop(context, shift) : null,
          child: Text(tr('Garder ce réglage')),
        ),
      ],
    );
  }
}

class _TargetPainter extends CustomPainter {
  const _TargetPainter(this.target);
  final Offset? target;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      Paint()..color = studioSheetBackdrop,
    );
    final at = target;
    if (at == null) return;
    final centre = Offset(at.dx * size.width, at.dy * size.height);
    final radius = math.min(size.width, size.height) * .09;
    final ring = Paint()
      ..color = studioGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(centre, radius, ring);
    canvas.drawCircle(centre, radius / 2, ring);
    canvas.drawCircle(centre, 3, Paint()..color = studioGreen);
  }

  @override
  bool shouldRepaint(_TargetPainter old) => old.target != target;
}
