// SPDX-License-Identifier: MIT
// « Le dessin qui se refait tout seul » : the film of a drawing, redrawn
// element after element from the empty sheet, or from the page of a
// colouring page. It shows prepared elements and never touches the document.
//
// What the studio state needs to open it — this file imported, a method
// beside _showHelp, and a button or a menu entry that calls it:
//
//   import 'replay_dialog.dart';
//
//   Future<void> _showReplay() async {
//     // Same guard as the other dialogs: nothing is edited behind it.
//     if (!mounted || _busy || _confirmationOpen || _document == null) return;
//     _finishStroke();
//     final document = _document!;
//     final scene = ReplayScene.fromDocumentOrder(
//       all: _strokes,
//       paintOrder: document.paintOrder,
//       width: document.width,
//       height: document.height,
//       paperRgb: document.paperRgb,
//       background: _backgroundImage,
//       fixedLayers: document.lockedLayers,
//     );
//     await _guardedDialog<void>(() => showReplayDialog(context, scene: scene));
//   }
//
// The scene is read when the dialog opens: the elements are the immutable
// ones the studio already paints with, and the image is only borrowed. A
// sheet with nothing to see on it opens too, and says that it is empty. The
// page of a colouring page is on the sheet from the first frame, its zones
// white: those that the paint pot coloured take their colour one after the
// other, then the film redraws what the child drew.
import 'dart:math' as math;
import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';

import 'document_renderer.dart';
import 'fit_to_screen.dart';
import 'replay.dart';
import 'rust_document.dart' show whitePaper;
import 'studio_colors.dart';
import 'viewport.dart';

/// What a film shows: a sheet and the elements to redraw on it. Everything
/// is borrowed from the caller; nothing of it is changed or disposed here.
class ReplayScene {
  const ReplayScene({
    required this.width,
    required this.height,
    required this.paperRgb,
    required this.background,
    required this.elements,
    required this.paintRank,
    this.fixedCount = 0,
    this.recolouredCount = 0,
  });

  /// The scene of a document, from what the studio holds: [all] are the
  /// prepared elements by document index and [paintOrder] the indices of
  /// those of the visible layers, bottom first. The elements are revealed
  /// in the order of their indices — the pile of the drawing, from the one
  /// underneath to the one on top, which is the order they were made in as
  /// long as none was sent in front of or behind the others — and painted
  /// in the order of [paintOrder]; those of hidden layers are not in the
  /// film.
  ///
  /// The elements of [fixedLayers], the locked layers of a colouring page,
  /// are not revealed: they come first, in their painting order, and are on
  /// the sheet from the first frame (see [fixedCount]). Its zones that the
  /// paint pot coloured come next, in the order of their indices: white from
  /// the first frame, they take their colour in turn (see
  /// [recolouredCount]) before the other elements are revealed.
  factory ReplayScene.fromDocumentOrder({
    required List<RenderedElement> all,
    required List<int> paintOrder,
    required int width,
    required int height,
    required int paperRgb,
    required ui.Image? background,
    Set<int> fixedLayers = const {},
  }) {
    final rankOf = List<int>.filled(all.length, -1);
    final elements = <RenderedElement>[];
    final paintRank = <int>[];
    bool onPage(int index) => fixedLayers.contains(all[index].data.layer);
    bool coloured(int index) => onPage(index) && all[index].data.colouredInside;
    for (var rank = 0; rank < paintOrder.length; rank++) {
      final index = paintOrder[rank];
      if (index < 0 || index >= all.length || rankOf[index] != -1) {
        throw ArgumentError('L’ordre des éléments du dessin est invalide.');
      }
      rankOf[index] = rank;
      // The page as it was made, from the bottom of the pile to its top.
      if (onPage(index) && !coloured(index)) {
        elements.add(all[index]);
        paintRank.add(rank);
      }
    }
    final fixedCount = elements.length;
    // Then the zones that the paint pot coloured, white until their turn.
    for (var index = 0; index < all.length; index++) {
      if (rankOf[index] == -1 || !coloured(index)) continue;
      elements.add(all[index]);
      paintRank.add(rankOf[index]);
    }
    final recolouredCount = elements.length - fixedCount;
    // Then what the child drew, as it was made.
    for (var index = 0; index < all.length; index++) {
      if (rankOf[index] == -1 || onPage(index)) continue;
      elements.add(all[index]);
      paintRank.add(rankOf[index]);
    }
    return ReplayScene(
      width: width,
      height: height,
      paperRgb: paperRgb,
      background: background,
      elements: List.unmodifiable(elements),
      paintRank: List.unmodifiable(paintRank),
      fixedCount: fixedCount,
      recolouredCount: recolouredCount,
    );
  }

  /// Size of the sheet in the units of the drawing.
  final int width;
  final int height;

  /// Colour of the sheet itself.
  final int paperRgb;

  /// The image under the drawing, or null. Borrowed: never disposed here.
  final ui.Image? background;

  /// The elements to redraw, in the order they are revealed.
  final List<RenderedElement> elements;

  /// For each of [elements], its place in the painting order, 0 at the
  /// bottom: the film reveals in the order of the list and paints, as the
  /// sheet does, from the bottom to the top.
  final List<int> paintRank;

  /// How many of [elements], the first ones, are on the sheet from the first
  /// frame, in their places in the pile: the page of a colouring page, which
  /// the child did not draw. The film redraws the others.
  final int fixedCount;

  /// How many of [elements], after the [fixedCount] first ones, are zones of
  /// the page that the paint pot coloured. Each is on the sheet from the
  /// first frame, white as the page was made, and takes its colour in its
  /// turn, before the elements that the child drew are redrawn.
  final int recolouredCount;

  /// Whether the element at [index] is one of the zones that take their
  /// colour during the film.
  bool isRecoloured(int index) =>
      index >= fixedCount && index < fixedCount + recolouredCount;

  /// The film redraws nothing: no element, or the untouched page of a
  /// colouring page alone.
  bool get nothingToRedraw => elements.length == fixedCount;
}

/// The film of the drawing. Completes when the child comes back to the
/// drawing.
///
/// The film starts by itself. [onStarted] is called every time it starts,
/// when the dialog opens and at each « Revoir »; [onFinished] every time it
/// reaches its end, not when it is closed or started again before. A sheet
/// without any element to redraw has no film: neither is called.
Future<void> showReplayDialog(
  BuildContext context, {
  required ReplayScene scene,
  VoidCallback? onStarted,
  VoidCallback? onFinished,
}) => showDialog<void>(
  context: context,
  builder: (_) => FitDialog(
    child: ReplayDialog(
      scene: scene,
      onStarted: onStarted,
      onFinished: onFinished,
    ),
  ),
);

// Where the sheet lies in a box of the given size.
DocumentViewport _sheetIn(Size size, ReplayScene scene) => DocumentViewport(
  viewWidth: size.width,
  viewHeight: size.height,
  documentWidth: scene.width.toDouble(),
  documentHeight: scene.height.toDouble(),
  // Room for the shadow of the sheet.
  padding: size.shortestSide >= 160 ? 16 : 8,
);

// Enters the units of the drawing, clipped to the sheet as the studio clips
// it. One restore leaves them.
void _enterSheet(Canvas canvas, DocumentViewport viewport) {
  canvas.save();
  canvas.translate(viewport.left, viewport.top);
  canvas.scale(viewport.scale);
  canvas.clipRect(
    Rect.fromLTWH(0, 0, viewport.documentWidth, viewport.documentHeight),
  );
}

// The sheet before any element, exactly as the painter of the studio paints
// it: its shadow, its paper and, in the units of the drawing, its image.
// Leaves the canvas in those units: two restores close what this opens.
void _paintUnderDrawing(
  Canvas canvas,
  Size size,
  ReplayScene scene,
  ui.Image? background,
) {
  final viewport = _sheetIn(size, scene);
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  final rect = Rect.fromLTWH(
    viewport.left,
    viewport.top,
    viewport.width,
    viewport.height,
  );
  canvas.drawShadow(Path()..addRect(rect), const Color(0x3323402c), 5, true);
  canvas.drawRect(rect, Paint()..color = Color(0xff000000 | scene.paperRgb));
  _enterSheet(canvas, viewport);
  if (background != null) {
    canvas.drawImageRect(
      background,
      Rect.fromLTWH(
        0,
        0,
        background.width.toDouble(),
        background.height.toDouble(),
      ),
      Rect.fromLTWH(0, 0, viewport.documentWidth, viewport.documentHeight),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }
}

// Paints the revealed elements whose place in the pile is in [from, to), the
// lowest first. The elements before [current] in the order of the film are
// complete, [current] is at [progress], those after it are not there yet,
// except the zones of a page that take their colour: white until their turn.
void _paintRevealed(
  Canvas canvas,
  ReplayScene scene,
  ReplayOrder order, {
  required int from,
  required int to,
  required int current,
  required double progress,
  required bool overshoot,
}) {
  final elements = scene.elements;
  for (var rank = from; rank < to; rank++) {
    final index = order.elementAt(rank);
    if (index < current) {
      elements[index].paint(canvas);
    } else if (scene.isRecoloured(index)) {
      elements[index].paintRecolouring(
        canvas,
        index == current ? progress : 0,
        fromRgb: whitePaper,
      );
    } else if (index == current) {
      elements[index].paintProgress(canvas, progress, overshoot: overshoot);
    }
  }
}

// One more than the highest place in the pile of a zone that takes its
// colour during the film, 0 without any: up to there the pile is never
// empty, the zones being white before their turn.
int _recolouredReach(ReplayScene scene) {
  var reach = 0;
  for (var index = scene.fixedCount; scene.isRecoloured(index); index++) {
    reach = math.max(reach, scene.paintRank[index] + 1);
  }
  return reach;
}

/// The dialog of the film: the sheet where the drawing redraws itself, and
/// under it the two ways on, « Revoir » and « Revenir au dessin ». Nothing
/// to drag: a child who steers the pointer with a joystick uses all of it.
///
/// The scene given when the dialog opens is its film for as long as it is
/// open.
class ReplayDialog extends StatefulWidget {
  const ReplayDialog({
    super.key,
    required this.scene,
    this.onStarted,
    this.onFinished,
  });
  final ReplayScene scene;

  /// Called every time the film starts.
  final VoidCallback? onStarted;

  /// Called every time the film reaches its end.
  final VoidCallback? onFinished;

  static const title = 'Ton dessin se refait tout seul';
  static const sheetLabel = 'Le film de ton dessin';
  static const startedStatus = 'Le film de ton dessin commence.';
  static const finishedStatus = 'Ton dessin est fini.';
  static const emptyStatus =
      'Ta feuille est encore vide : il n’y a rien à refaire.';
  // A colouring page on which nothing is coloured nor drawn yet: the page
  // itself is not redrawn.
  static const pageOnlyStatus =
      'Tu n’as encore rien colorié ni dessiné sur ta page : il n’y a rien à refaire.';

  /// The least height of the box of the sheet, in a window so small that
  /// the film must scroll to be seen whole.
  static const minSheetHeight = 120.0;

  @override
  State<ReplayDialog> createState() => _ReplayDialogState();
}

class _ReplayDialogState extends State<ReplayDialog>
    with SingleTickerProviderStateMixin {
  late final _Film _film;
  late final AnimationController _clock;

  // What the kept part of the picture holds: it is painted again only when
  // this changes.
  late final ValueNotifier<int> _resting;

  // A handle of this dialog's own on the borrowed image: the film goes on
  // even if the studio lets go of its handle meanwhile.
  ui.Image? _background;

  // The dialog coming into view. The film waits for the end of it: its
  // first picture, the empty sheet or the page, is one that the child sees.
  Animation<double>? _arrival;
  bool _begun = false;
  bool _finished = false;

  // The scene given when the dialog opened is its film: see ReplayDialog.
  bool get _empty => _film.scene.nothingToRedraw;

  @override
  void initState() {
    super.initState();
    final scene = widget.scene;
    if (scene.elements.length != scene.paintRank.length ||
        scene.fixedCount < 0 ||
        scene.fixedCount > scene.elements.length) {
      throw ArgumentError('L’ordre des éléments du dessin est invalide.');
    }
    // What can refuse a scene comes first: nothing is left open behind it.
    // A sheet that cannot be laid out is refused here, once, by what lays
    // it out, and not by the painters at every frame.
    _sheetIn(const Size.square(320), scene);
    final order = ReplayOrder(scene.paintRank);
    // The page of a colouring page is complete from the first frame.
    final plan = ReplayPlan(
      scene.elements,
      sheetDiagonal: math.sqrt(
        scene.width * scene.width + scene.height * scene.height,
      ),
      fixed: scene.fixedCount,
      recoloured: scene.recolouredCount,
    );
    _background = scene.background?.clone();
    _clock = AnimationController(
      vsync: this,
      duration: plan.total,
      // The child asked for this film: it is not hurried where the system
      // asks for less motion; only the bounce of the stamps is left out.
      animationBehavior: AnimationBehavior.preserve,
    )..addListener(_tick);
    _film = _Film(scene, _background, plan, order, _clock);
    _resting = ValueNotifier(_film.resting);
    // A dialog that does not come into view, or is there already, starts
    // its film at once. After the first frame: a callback of the studio may
    // rebuild it, which nothing may do while this dialog is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_begun && (_arrival?.isCompleted ?? true)) _play();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arrival = ModalRoute.of(context)?.animation;
    if (identical(arrival, _arrival)) return;
    _arrival?.removeStatusListener(_arrived);
    _arrival = arrival?..addStatusListener(_arrived);
  }

  @override
  void dispose() {
    _arrival?.removeStatusListener(_arrived);
    _clock.dispose();
    _resting.dispose();
    _background?.dispose();
    super.dispose();
  }

  void _arrived(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_begun) _play();
  }

  // From the empty sheet, or the page, the first time and at every
  // « Revoir ».
  void _play() {
    _begun = true;
    if (_empty) return;
    if (_finished) setState(() => _finished = false);
    _clock.forward(from: 0);
    widget.onStarted?.call();
  }

  // Every frame of the film. Its end is the frame that shows the complete
  // drawing: the clock itself says « completed » only one frame later.
  void _tick() {
    _resting.value = _film.resting;
    if (_clock.value < 1 || _finished) return;
    setState(() => _finished = true);
    widget.onFinished?.call();
  }

  // The sheet on its backdrop, as in the studio. Two pictures, one on the
  // other: what rests is kept from frame to frame, and only what moves is
  // painted for each of them.
  Widget _sheet({required bool overshoot}) => Semantics(
    container: true,
    image: true,
    label: ReplayDialog.sheetLabel,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: studioSheetBackdrop,
        borderRadius: BorderRadius.circular(16),
      ),
      child: RepaintBoundary(
        key: const Key('replaySheet'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                isComplex: true,
                painter: _RestingPainter(_film, _resting),
                size: Size.infinite,
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                willChange: true,
                painter: _MovingPainter(_film, overshoot: overshoot),
                size: Size.infinite,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // One sentence when the film starts and one when it ends, for the eyes
  // and for a screen reader, over a thin line that fills as the film goes.
  List<Widget> _status() => [
    Semantics(
      container: true,
      liveRegion: true,
      child: Text(
        _empty
            ? (_film.scene.fixedCount > 0
                  ? ReplayDialog.pageOnlyStatus
                  : ReplayDialog.emptyStatus)
            : _finished
            ? ReplayDialog.finishedStatus
            : ReplayDialog.startedStatus,
        key: const Key('replayStatus'),
        style: const TextStyle(fontSize: 13),
      ),
    ),
    const SizedBox(height: 8),
    SizedBox(
      key: const Key('replayProgress'),
      height: 4,
      // A picture of its own: it changes with every frame, and the title
      // and the status beside it are not painted again for that.
      child: RepaintBoundary(
        child: CustomPaint(painter: _ProgressPainter(_clock)),
      ),
    ),
  ];

  Widget _buttons() => OverflowBar(
    alignment: MainAxisAlignment.end,
    spacing: 12,
    overflowSpacing: 8,
    overflowAlignment: OverflowBarAlignment.end,
    children: [
      OutlinedButton.icon(
        key: const Key('replayAgain'),
        // The size of a child's target whatever the theme makes of buttons.
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(88, 48),
          visualDensity: VisualDensity.standard,
        ),
        onPressed: _empty ? null : _play,
        icon: const Icon(Icons.replay),
        label: const Text('Revoir'),
      ),
      FilledButton(
        key: const Key('closeReplay'),
        // Entrée returns to the drawing, as in the other dialogs.
        autofocus: true,
        style: FilledButton.styleFrom(
          minimumSize: const Size(88, 48),
          visualDensity: VisualDensity.standard,
        ),
        onPressed: () => Navigator.pop(context),
        child: const Text('Revenir au dessin'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // Where the system asks for less motion the stamps grow without a bounce.
    final overshoot = !MediaQuery.disableAnimationsOf(context);
    return PopScope(
      // Closed is closed, by a button, by Échap or by a click beside the
      // dialog: the film stops there, and does not end while the dialog
      // goes away.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _clock.stop();
      },
      child: Dialog(
        key: const Key('replayDialog'),
        insetPadding: const EdgeInsets.all(24),
        // Its title is the name of this dialog for a screen reader.
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  // The sheet takes all the room that the texts leave. In a
                  // window too small to leave it enough, it keeps a size
                  // worth looking at and this part scrolls under the
                  // buttons, which stay.
                  child: LayoutBuilder(
                    builder: (context, room) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: room.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Semantics(
                                container: true,
                                header: true,
                                namesRoute: true,
                                child: Text(
                                  ReplayDialog.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: ReplayDialog.minSheetHeight,
                                  ),
                                  child: _sheet(overshoot: overshoot),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ..._status(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buttons(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// One film: its scene, its times, its pile and its clock, for the painters.
class _Film {
  _Film(this.scene, this.background, this.plan, this.order, this.clock);
  final ReplayScene scene;
  final ui.Image? background;
  final ReplayPlan plan;
  final ReplayOrder order;

  /// From 0 at the empty sheet, or the page, to 1 at the complete drawing.
  final Animation<double> clock;

  /// Up to there the pile has something to paint from the first frame on:
  /// the zones that take their colour are white before their turn.
  late final int recolouredReach = _recolouredReach(scene);

  Duration get elapsed =>
      Duration(microseconds: (plan.total.inMicroseconds * clock.value).round());

  /// How many elements at the bottom of the pile are in the kept picture.
  /// All of them are complete and nothing comes under them any more, so the
  /// kept picture followed by the other revealed elements, lowest first, is
  /// the whole pile in its order.
  int get resting => order.restingAt(plan.finishedAt(elapsed));
}

// The part of the picture that is kept between frames: the sheet and the
// elements at the bottom of the pile that will not change any more.
class _RestingPainter extends CustomPainter {
  _RestingPainter(this.film, Listenable resting) : super(repaint: resting);
  final _Film film;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scene = film.scene;
    final elements = scene.elements;
    final order = film.order;
    _paintUnderDrawing(canvas, size, scene, film.background);
    final resting = film.resting;
    for (var rank = 0; rank < resting; rank++) {
      elements[order.elementAt(rank)].paint(canvas);
    }
    canvas
      ..restore()
      ..restore();
  }

  @override
  bool shouldRepaint(_RestingPainter old) => !identical(old.film, film);
}

// The part painted for every frame: the element being redrawn, and the
// complete ones that are not in the kept picture yet.
class _MovingPainter extends CustomPainter {
  _MovingPainter(this.film, {required this.overshoot})
    : super(repaint: film.clock);
  final _Film film;
  final bool overshoot;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final elapsed = film.elapsed;
    final current = film.plan.currentAt(elapsed);
    if (current < 0) return;
    final from = film.resting;
    final to = math.max(film.order.reachAt(current + 1), film.recolouredReach);
    if (from >= to) return;
    // The very clips of the kept picture, the one of the box too although
    // the sheet lies inside it: an element is painted alike in either
    // picture, and nothing shows when it passes from this one to the other.
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _enterSheet(canvas, _sheetIn(size, film.scene));
    _paintRevealed(
      canvas,
      film.scene,
      film.order,
      from: from,
      to: to,
      current: current,
      progress: film.plan.progressAt(current, elapsed),
      overshoot: overshoot,
    );
    canvas
      ..restore()
      ..restore();
  }

  @override
  bool shouldRepaint(_MovingPainter old) =>
      !identical(old.film, film) || old.overshoot != overshoot;
}

// A thin line that fills as the film goes: how much of it is left to see.
class _ProgressPainter extends CustomPainter {
  _ProgressPainter(this.clock) : super(repaint: clock);
  final Animation<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = studioLine,
    );
    if (clock.value <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * clock.value, size.height),
        radius,
      ),
      Paint()..color = studioGreen,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) => !identical(old.clock, clock);
}
