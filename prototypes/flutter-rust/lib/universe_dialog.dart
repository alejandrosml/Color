// SPDX-License-Identifier: MIT
// « Choisis ton univers » (Color 1.2): the child looks at the universes and
// takes one. The drawing does not change: the workshop dresses otherwise.
import 'package:flutter/material.dart';

import 'child_art.dart';
import 'decor.dart';
import 'decor_motion.dart';
import 'decor_view.dart';
import 'fit_to_screen.dart';
import 'language.dart';
import 'studio_colors.dart';
import 'studio_text.dart';
import 'universe.dart';
import 'vector_art.dart';

/// Shows the universes of [catalog], [current] marked, and completes with
/// the one the child took; null when the dialog was left without a choice.
Future<Universe?> showUniverseDialog(
  BuildContext context, {
  required UniverseCatalog catalog,
  required Universe current,
  DateTime Function()? now,
}) => showDialog<Universe>(
  context: context,
  builder: (_) => FitDialog(
    child: UniverseDialog(catalog: catalog, current: current, now: now),
  ),
);

class UniverseDialog extends StatelessWidget {
  const UniverseDialog({
    super.key,
    required this.catalog,
    required this.current,
    this.now,
  });
  final UniverseCatalog catalog;
  final Universe current;
  final DateTime Function()? now;

  /// The size of the picture of a card.
  static const picture = Size(232, 150);

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('universeDialog'),
    scrollable: true,
    insetPadding: const EdgeInsets.all(16),
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Choisis ton univers')),
        const SizedBox(height: 4),
        Text(
          tr(
            'Ton dessin ne change pas : c’est l’atelier qui s’habille autrement.',
          ),
          style: TextStyle(fontSize: 14, color: studioInk),
        ),
      ],
    ),
    content: SizedBox(
      width: 3 * (picture.width + 4) + 2 * 14,
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final universe in catalog.universes)
            _UniverseCard(
              universe: universe,
              chosen: universe.key == current.key,
              now: now,
              onTap: () => Navigator.pop(context, universe),
            ),
        ],
      ),
    ),
    actionsPadding: const EdgeInsets.all(16),
    actions: [
      OutlinedButton.icon(
        key: const Key('closeUniverses'),
        autofocus: true,
        style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.undo_rounded),
        label: Text(tr('Retour à mon dessin')),
      ),
    ],
  );
}

// One universe to take: a corner of its decor, the companion, its name and
// one line. Each card wears the colours of its own universe.
class _UniverseCard extends StatelessWidget {
  const _UniverseCard({
    required this.universe,
    required this.chosen,
    required this.onTap,
    this.now,
  });
  final Universe universe;
  final bool chosen;
  final VoidCallback onTap;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final look = universe.look;
    final size = UniverseDialog.picture;
    return SizedBox(
      width: size.width + 4,
      // One control for a screen reader: the name, the line, and whether
      // it is the universe of the moment.
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: chosen,
          child: Material(
            color: look.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: chosen ? look.accent : look.line,
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: Key('universe-${universe.key}'),
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.fromSize(
                    size: size,
                    child: ExcludeSemantics(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _CornerPainter(universe, decorTime(now)),
                            ),
                          ),
                          Positioned(
                            right: 8,
                            bottom: 6,
                            child: Container(
                              width: 86,
                              height: 86,
                              decoration: const BoxDecoration(
                                color: Color(0xf2ffffff),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: _companion(74),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                universe.name,
                                style: studioLabelStyle(context, 17).copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: look.ink,
                                ),
                              ),
                            ),
                            if (chosen)
                              Icon(
                                Icons.check_circle,
                                color: look.accent,
                                semanticLabel: tr('Univers choisi'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          universe.about,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: look.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _companion(double size) {
    final picture = VectorArtCatalog.instance?['mascotte'];
    return picture == null
        ? EduIllustration(art: EduArt.mascot, size: size)
        : SizedBox.square(
            dimension: size,
            child: CustomPaint(painter: _PicturePainter(picture)),
          );
  }
}

class _PicturePainter extends CustomPainter {
  const _PicturePainter(this.picture);
  final VectorPicture picture;

  @override
  void paint(Canvas canvas, Size size) =>
      picture.paint(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_PicturePainter old) => old.picture != picture;
}

// The left corner of the decor of a universe, as tall as the card; the
// backdrop of its look for a universe without a decor. Still: nothing
// moves where the child chooses.
class _CornerPainter extends CustomPainter {
  const _CornerPainter(this.universe, this.time);
  final Universe universe;
  final DateTime time;

  @override
  void paint(Canvas canvas, Size size) {
    final decor = universe.decor;
    if (decor == null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = universe.look.sheetBackdrop,
      );
      return;
    }
    // A frame as wide as the decor at the height of the card: its left
    // part is what the card shows.
    final frame = Size(
      decor.size.width * size.height / decor.size.height,
      size.height,
    );
    final scale = frame.height / decor.size.height;
    final painting = DecorPainting(
      decor,
      DecorLayout(
        frame: frame,
        sheetAtRest: Rect.fromLTWH(
          decor.sheet.left * scale,
          decor.sheet.top * scale,
          decor.sheet.width * scale,
          decor.sheet.height * scale,
        ),
        decor: decor.size,
        decorSheet: decor.sheet,
      ),
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    painting.paintStill(canvas, DayMoment.at(time));
    painting.paintLive(
      canvas,
      seconds: 0,
      time: time,
      motion: DecorMotion.none,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.universe != universe || DayMoment.at(old.time) != DayMoment.at(time);
}
