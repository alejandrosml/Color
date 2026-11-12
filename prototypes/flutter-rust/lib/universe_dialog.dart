// SPDX-License-Identifier: MIT
// « Choisis ton univers » (Color 1.2): the child looks at the universes and
// takes one. The drawing does not change: the workshop dresses otherwise.
// Under each universe that has a decor, the button « Regarder » shows that
// decor on the whole screen (decor_gaze.dart), unless an adult took the
// button away.
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

/// What the child did in « Choisis ton univers »: took [universe] for the
/// workshop, or asked to look at its decor on the whole screen.
class UniverseChoice {
  const UniverseChoice.wear(this.universe) : watch = false;
  const UniverseChoice.watch(this.universe) : watch = true;
  final Universe universe;
  final bool watch;
}

/// Shows the universes of [catalog], [current] marked, and completes with
/// what the child did; null when the dialog was left without a choice.
/// [watch] says whether the button « Regarder » is offered.
Future<UniverseChoice?> showUniverseDialog(
  BuildContext context, {
  required UniverseCatalog catalog,
  required Universe current,
  bool watch = true,
  DateTime Function()? now,
}) => showDialog<UniverseChoice>(
  context: context,
  builder: (_) => FitDialog(
    child: UniverseDialog(
      catalog: catalog,
      current: current,
      watch: watch,
      now: now,
    ),
  ),
);

class UniverseDialog extends StatelessWidget {
  const UniverseDialog({
    super.key,
    required this.catalog,
    required this.current,
    this.watch = true,
    this.now,
  });
  final UniverseCatalog catalog;
  final Universe current;

  /// Whether a decor may be looked at on the whole screen from here.
  final bool watch;
  final DateTime Function()? now;

  /// The size of the picture of a card.
  static const picture = Size(232, 150);

  /// Three cards in a row; the list scrolls.
  static const perRow = 3;

  @override
  Widget build(BuildContext context) {
    final universes = catalog.universes;
    // A place for « Regarder » on every card as soon as one has it: the
    // cards of a row keep the same height.
    final watched =
        watch && universes.any((universe) => universe.decor != null);
    return AlertDialog(
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
        width: perRow * (picture.width + 4) + (perRow - 1) * 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var first = 0; first < universes.length; first += perRow) ...[
              if (first > 0) const SizedBox(height: 14),
              // The cards of one row are as tall as the tallest of them.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var index = first;
                      index < first + perRow && index < universes.length;
                      index++
                    ) ...[
                      if (index > first) const SizedBox(width: 14),
                      _UniverseCard(
                        universe: universes[index],
                        chosen: universes[index].key == current.key,
                        watched: watched,
                        now: now,
                        onTap: () => Navigator.pop(
                          context,
                          UniverseChoice.wear(universes[index]),
                        ),
                        onWatch: () => Navigator.pop(
                          context,
                          UniverseChoice.watch(universes[index]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
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
}

// One universe to take: a corner of its decor, the companion, its name and
// one line; and under them « Regarder », for a universe that has a decor.
// Each card wears the colours of its own universe.
class _UniverseCard extends StatelessWidget {
  const _UniverseCard({
    required this.universe,
    required this.chosen,
    required this.watched,
    required this.onTap,
    required this.onWatch,
    this.now,
  });
  final Universe universe;
  final bool chosen;

  /// Whether the cards have a place for « Regarder ».
  final bool watched;
  final VoidCallback onTap;
  final VoidCallback onWatch;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final look = universe.look;
    final size = UniverseDialog.picture;
    final taking = MergeSemantics(
      // One control for a screen reader: the name, the line, and whether
      // it is the universe of the moment.
      child: Semantics(
        button: true,
        selected: chosen,
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
                      crossAxisAlignment: CrossAxisAlignment.start,
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
    );
    return SizedBox(
      width: size.width + 4,
      child: Material(
        color: look.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: chosen ? look.accent : look.line, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: taking),
            if (watched)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                // A universe without a decor has nothing to look at: its
                // card keeps the place, empty.
                child: universe.decor == null
                    ? const SizedBox(height: watchHeight)
                    : OutlinedButton.icon(
                        key: Key('watch-${universe.key}'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(88, watchHeight),
                          foregroundColor: look.ink,
                          side: BorderSide(color: look.line, width: 2),
                          // The letters of the interface, named: a style
                          // without a family is drawn in another font.
                          textStyle: studioLabelStyle(
                            context,
                            16,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                        onPressed: onWatch,
                        icon: const Icon(Icons.visibility_rounded),
                        label: Text(
                          tr('Regarder'),
                          semanticsLabel: trf('Regarder le décor : {0}', [
                            universe.name,
                          ]),
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  /// The height of « Regarder »: a large button, easy to press.
  static const watchHeight = 48.0;

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
