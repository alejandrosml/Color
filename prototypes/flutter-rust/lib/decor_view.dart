// SPDX-License-Identifier: MIT
// The decor of the universe, shown in the frame of the sheet and under it
// (Color 1.2), and the card that names one of its elements.
//
// What does not move is kept in one image, made again only when the frame,
// the universe or the moment of the day changes; the few pieces that move
// are painted over it, thirty times a second at most. In the calm mode,
// when the system asks for less motion, or while Color is not in front,
// nothing ticks at all: the decor is a still picture. A clock of the decor
// is then set once a minute, which is no movement but the time.
//
// Nothing must slow a trait down. While a gesture goes on on the sheet the
// decor rests: it stops where it is, and the whole of it — the pieces that
// move and the light too — is one image, which every image of the trait
// only lays down. So it is whenever nothing moves. And the decor waits for
// the first image of the studio to be shown before it paints itself: the
// sheet and the tools come first.
//
// The same view shows a decor that is looked at without a sheet, on the
// whole screen (decor_gaze.dart). And where the images of a decor that
// moves take too long to make — a computer without a graphics processor —
// it beats more slowly rather than hold the machine: the movement keeps its
// pace, with fewer images.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'decor.dart';
import 'decor_motion.dart';
import 'language.dart';

/// The time of the device, for the decor that follows it; a test gives its
/// own, and flutter_test_config.dart a fixed one for every test: a picture
/// of the studio is then the same at any hour.
@visibleForTesting
DateTime Function()? debugDecorNow;

/// The time a decor shows: [now], or the clock of the system — unless a
/// test fixed the time of every decor.
DateTime decorTime([DateTime Function()? now]) =>
    (debugDecorNow ?? now ?? DateTime.now)();

/// For tests: nothing of a decor moves by itself, whatever the options
/// say. flutter_test_config.dart sets it for every test — a decor that
/// moves never lets a test settle; the tests of the movement unset it.
@visibleForTesting
bool debugDecorStill = false;

/// For what times the images of a decor (test/live/studio_scenario.dart):
/// the decor beats at this pace whatever its images cost, so that each
/// image timed is one of the decor that moved.
@visibleForTesting
Duration? debugDecorBeat;

/// How many times a decor made the image of its still pieces, for the
/// tests: once per frame, universe and moment, never per image.
@visibleForTesting
int debugDecorStillImages = 0;

/// The decor of a universe in the frame of the sheet.
class DecorView extends StatefulWidget {
  const DecorView({
    super.key,
    required this.decor,
    required Rect this.sheetAtRest,
    required this.motion,
    this.now,
    this.resting,
    this.corners = 0,
    this.behind,
    this.clearTop = 0,
    this.smallest,
    this.onClock,
  }) : safe = EdgeInsets.zero,
       arrangement = null,
       waitsForFirstImage = true;

  /// The decor looked at without a sheet, on the whole of its frame
  /// ([DecorLayout.gaze]): [safe] is what the device hides at the edges.
  const DecorView.gaze({
    super.key,
    required this.decor,
    required this.motion,
    this.safe = EdgeInsets.zero,
    this.arrangement,
    this.now,
  }) : sheetAtRest = null,
       resting = null,
       corners = 0,
       behind = null,
       clearTop = 0,
       smallest = null,
       onClock = null,
       waitsForFirstImage = false;

  final Decor decor;

  /// What the device hides at the edges of the frame, for a decor that is
  /// looked at; and how its sides stand, when that is not left to the
  /// frame.
  final EdgeInsets safe;
  final DecorGazeArrangement? arrangement;

  /// What the pebbles keep of the top of the frame, and the smallest scale
  /// of the pieces in a frame that is the window ([DecorLayout]).
  final double clearTop;
  final double? smallest;

  /// Called when the decor looks at the clock again — at each minute of
  /// the device, and when Color comes back in front: what stands beside
  /// the decor in the same room, the ground under the line of the
  /// pebbles, follows the same hour.
  final VoidCallback? onClock;

  /// Around a sheet, the decor lets the first image of the studio go by
  /// before it paints itself; looked at, it is what the image is for.
  final bool waitsForFirstImage;

  /// Where this decor stands in [frame].
  DecorLayout layoutIn(Size frame) {
    final sheet = sheetAtRest;
    return sheet == null
        ? DecorLayout.gaze(
            frame: frame,
            safe: safe,
            decor: decor.size,
            decorSheet: decor.sheet,
            middle: decor.middleBox,
            arrangement: arrangement,
          )
        : DecorLayout(
            frame: frame,
            sheetAtRest: sheet,
            decor: decor.size,
            decorSheet: decor.sheet,
            clearTop: clearTop,
            smallest: smallest,
          );
  }

  /// Says whether a gesture goes on on the sheet: the decor then stops
  /// where it is, and moves on when the gesture ends. Asked at each tick
  /// of the movement, so that no end of a gesture is missed.
  final bool Function()? resting;

  /// The radius of the corners of the frame, and the colour that lies
  /// behind the frame: the corners are painted over in that colour, which
  /// costs less at every image than cutting the decor round.
  final double corners;
  final Color? behind;

  /// Where the sheet lies in this frame when the whole of it is shown;
  /// null for a decor that is looked at without a sheet.
  final Rect? sheetAtRest;

  /// What the adult chose. The system's « Réduire les animations » stills
  /// the decor whatever this says.
  final DecorMotion motion;

  /// The time of the device; [DateTime.now] when null.
  final DateTime Function()? now;

  /// How often the pieces that move are painted again; less often where
  /// the images take too long to make ([slowerPeriods]).
  static const period = Duration(milliseconds: 33);

  /// The slower beats, for a machine that cannot make thirty images of a
  /// decor a second: fifteen, then ten.
  static const slowerPeriods = [
    Duration(milliseconds: 66),
    Duration(milliseconds: 100),
  ];

  @override
  State<DecorView> createState() => _DecorViewState();
}

class _DecorViewState extends State<DecorView> with WidgetsBindingObserver {
  /// Seconds of movement since the decor appeared: they stand still while
  /// nothing moves.
  final _seconds = ValueNotifier<double>(0);

  /// Counts the minutes that pass: the clock and the light follow.
  final _minutes = ValueNotifier<int>(0);
  final _still = _KeptImage();
  final _whole = _KeptImage();

  /// A gesture holds the decor where it is.
  final _rests = ValueNotifier<bool>(false);

  /// The first image of the studio has been shown: the decor may paint.
  late bool _shown = !widget.waitsForFirstImage;
  Timer? _moving;

  /// How often the decor beats now, and what the last images cost: the
  /// beat slows down where they take longer than it lasts, and comes back
  /// when they are quick again.
  Duration _period = DecorView.period;
  double _imageMillis = 0;
  bool _timed = false;
  Timer? _minute;
  bool _inFront = true;
  bool _calm = false;

  DateTime _now() => decorTime(widget.now);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _inFront = state == null || state == AppLifecycleState.resumed;
    if (!_shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  // What the images cost while the decor moves, as the engine reports it,
  // some of them at a time: a mean that forgets slowly.
  void _timings(List<FrameTiming> timings) {
    if (_moving == null || _rests.value || timings.isEmpty) return;
    if (debugDecorBeat != null) return;
    for (final timing in timings) {
      final cost =
          (timing.buildDuration + timing.rasterDuration).inMicroseconds / 1000;
      _imageMillis = _imageMillis == 0 ? cost : _imageMillis * .9 + cost * .1;
    }
    final next = decorBeatFor(_imageMillis, _period);
    if (next == _period) return;
    _period = next;
    _moving?.cancel();
    _moving = null;
    _settle();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _settle();
  }

  @override
  void didUpdateWidget(DecorView old) {
    super.didUpdateWidget(old);
    _settle();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inFront = state == AppLifecycleState.resumed;
    // Out of sight the graphics processor may go, and the image of the
    // still pieces with it: it is made again when the decor is next
    // painted, as the images of the sheet are.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _still.drop();
      _whole.drop();
    }
    if (inFront == _inFront) return;
    _inFront = inFront;
    // Back in front: the clock may have gone on without Color.
    if (inFront) {
      _minutes.value++;
      widget.onClock?.call();
    }
    _settle();
  }

  /// The system runs short of memory: the image goes, and is made again
  /// when the decor is next painted.
  @override
  void didHaveMemoryPressure() {
    _still.drop();
    _whole.drop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_timed) SchedulerBinding.instance.removeTimingsCallback(_timings);
    _moving?.cancel();
    _minute?.cancel();
    _still.drop();
    _whole.drop();
    _rests.dispose();
    _seconds.dispose();
    _minutes.dispose();
    super.dispose();
  }

  bool get _moves =>
      _inFront &&
      !_calm &&
      !debugDecorStill &&
      widget.motion.moves &&
      widget.decor.hasMovement;

  // Starts or stops what ticks, for the options, the system and the place
  // of Color of the moment.
  void _settle() {
    if (_moves) {
      final period = debugDecorBeat ?? _period;
      _moving ??= Timer.periodic(period, (_) {
        // A gesture on the sheet: the decor waits where it is.
        final rests = widget.resting?.call() ?? false;
        _rests.value = rests;
        if (!rests) _seconds.value += period.inMicroseconds / 1e6;
      });
      if (!_timed) {
        _timed = true;
        SchedulerBinding.instance.addTimingsCallback(_timings);
      }
    } else {
      _moving?.cancel();
      _moving = null;
      if (_timed) {
        _timed = false;
        SchedulerBinding.instance.removeTimingsCallback(_timings);
      }
    }
    if (_inFront && widget.decor.followsTheHour) {
      if (_minute == null) _awaitMinute();
    } else {
      _minute?.cancel();
      _minute = null;
    }
  }

  // One timer to the next minute of the device, then the next: never a
  // drift, whatever the moment Color was opened at.
  void _awaitMinute() {
    final now = _now();
    final left = Duration(
      seconds: 59 - now.second,
      milliseconds: 1000 - now.millisecond + 20,
    );
    _minute = Timer(left, () {
      _minute = null;
      if (!mounted) return;
      _minutes.value++;
      widget.onClock?.call();
      if (_inFront && widget.decor.followsTheHour) _awaitMinute();
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final decor = widget.decor;
      final painting = DecorPainting(
        decor,
        widget.layoutIn(constraints.biggest),
      );
      return CustomPaint(
        key: const Key('decor'),
        size: constraints.biggest,
        painter: _DecorPainter(
          painting: painting,
          shown: _shown,
          seconds: _seconds,
          minutes: _minutes,
          resting: _rests,
          moves: _moves,
          // At rest in the calm mode: the pieces where their pictures draw
          // them, and those of the higher levels away.
          motion: _calm || debugDecorStill ? DecorMotion.none : widget.motion,
          now: _now,
          still: _still,
          whole: _whole,
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
          corners: widget.corners,
          behind: widget.behind,
        ),
      );
    },
  );
}

/// The beat of a decor whose images cost [millis] each, when it beats
/// every [now]: one step slower when an image takes longer than nine
/// tenths of the beat, one step quicker when it takes less than a third of
/// the quicker beat — far enough apart for the beat not to waver.
@visibleForTesting
Duration decorBeatFor(double millis, Duration now) {
  const beats = [DecorView.period, ...DecorView.slowerPeriods];
  final at = beats.indexOf(now).clamp(0, beats.length - 1);
  if (at < beats.length - 1 && millis > beats[at].inMilliseconds * .9) {
    return beats[at + 1];
  }
  if (at > 0 && millis < beats[at - 1].inMilliseconds / 3) {
    return beats[at - 1];
  }
  return beats[at];
}

/// An image of a decor in its frame, kept until what it shows changes: its
/// still pieces, or the whole of it at rest.
class _KeptImage {
  ui.Image? _image;
  Object? _key;
  double _ratio = 1;

  /// The longest side of the image, in pixels: beyond it the image is
  /// made at a lower ratio, and drawn enlarged.
  static const longest = 4096;

  /// The image of what [paint] draws in [frame] over [ground], made again
  /// only when [key] is another; null for an empty frame. No pixel of it
  /// lets anything through: it is laid down without a blend.
  ui.Image? imageFor(
    Size frame,
    double pixelRatio,
    Object key,
    Color ground,
    void Function(Canvas canvas) paint, {
    VoidCallback? onMade,
  }) {
    if (frame.isEmpty) return null;
    final ratio = math.min(
      pixelRatio,
      longest / math.max(frame.width, frame.height),
    );
    if (_image != null && _key == key && _ratio == ratio) return _image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(ground.withValues(alpha: 1), BlendMode.src);
    canvas.scale(ratio);
    paint(canvas);
    final picture = recorder.endRecording();
    final ui.Image image;
    try {
      image = picture.toImageSync(
        math.max(1, (frame.width * ratio).ceil()),
        math.max(1, (frame.height * ratio).ceil()),
      );
    } finally {
      picture.dispose();
    }
    onMade?.call();
    _image?.dispose();
    _image = image;
    _key = key;
    _ratio = ratio;
    return image;
  }

  /// Lays the image down in the frame it was made for.
  void lay(Canvas canvas, ui.Image image, double pixelRatio) {
    canvas.save();
    canvas.scale(1 / _ratio);
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()
        // Pixel for pixel when it was made at the ratio of the screen:
        // nothing to smooth. It hides whatever lies under it.
        ..filterQuality = _ratio == pixelRatio
            ? FilterQuality.none
            : FilterQuality.low
        ..blendMode = BlendMode.src,
    );
    canvas.restore();
  }

  /// Lets the image go; the next call of [imageFor] makes it again.
  void drop() {
    _image?.dispose();
    _image = null;
    _key = null;
  }
}

class _DecorPainter extends CustomPainter {
  _DecorPainter({
    required this.painting,
    required this.shown,
    required this.seconds,
    required this.minutes,
    required this.resting,
    required this.moves,
    required this.motion,
    required this.now,
    required this.still,
    required this.whole,
    required this.pixelRatio,
    required this.corners,
    required this.behind,
  }) : super(repaint: Listenable.merge([seconds, minutes, resting]));

  final DecorPainting painting;
  final bool shown;
  final ValueListenable<double> seconds;
  final ValueListenable<int> minutes;
  final ValueListenable<bool> resting;

  /// Whether the decor ticks when no gesture holds it.
  final bool moves;
  final DecorMotion motion;
  final DateTime Function() now;
  final _KeptImage still;
  final _KeptImage whole;
  final double pixelRatio;
  final double corners;
  final Color? behind;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Offset.zero & size;
    if (!shown) {
      // Before the first image of the studio: the colour of the room.
      canvas.drawRect(frame, Paint()..color = painting.decor.top);
      _paintCorners(canvas, frame);
      return;
    }
    final time = now();
    final moment = DayMoment.at(time);
    final layout = painting.layout;
    final kept = still.imageFor(
      layout.frame,
      pixelRatio,
      (painting.decor, layout, moment),
      painting.decor.top,
      (canvas) => painting.paintStill(canvas, moment),
      onMade: () => debugDecorStillImages++,
    );
    void live(Canvas canvas) => painting.paintLive(
      canvas,
      seconds: seconds.value,
      time: time,
      motion: motion,
    );
    if (!moves || resting.value) {
      // At rest: the whole decor, its light too, is one image; every
      // image of a trait only lays it down.
      final image = whole.imageFor(
        layout.frame,
        pixelRatio,
        (
          painting.decor,
          layout,
          motion,
          seconds.value,
          time.day,
          time.hour,
          time.minute,
        ),
        painting.decor.top,
        (canvas) {
          if (kept != null) still.lay(canvas, kept, pixelRatio);
          live(canvas);
        },
      );
      if (image != null) whole.lay(canvas, image, pixelRatio);
    } else {
      // It moves: the image of what does not is not made again.
      whole.drop();
      if (kept != null) still.lay(canvas, kept, pixelRatio);
      live(canvas);
    }
    _paintCorners(canvas, frame);
  }

  // The round corners of the frame, painted over in the colour behind it.
  void _paintCorners(Canvas canvas, Rect frame) {
    final colour = behind;
    if (corners <= 0 || colour == null) return;
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(frame)
        ..addRRect(RRect.fromRectAndRadius(frame, Radius.circular(corners))),
      Paint()..color = colour,
    );
  }

  @override
  bool shouldRepaint(_DecorPainter old) =>
      !identical(old.painting.decor, painting.decor) ||
      old.painting.layout != painting.layout ||
      old.shown != shown ||
      old.moves != moves ||
      old.motion != motion ||
      old.pixelRatio != pixelRatio ||
      old.corners != corners ||
      old.behind != behind;
}

/// Hears what a child does beside the sheet, and says when it asks the
/// name of something of the decor: a double click, or with a finger a
/// double touch or a long one. It never takes a gesture from the sheet:
/// the studio tells it only of what happens beside it.
class DecorAsking {
  DecorAsking({required this.onAsk});
  final ValueChanged<DecorName> onAsk;

  /// Two presses this close in time and in place are one question.
  static const doubleWithin = Duration(milliseconds: 500);
  static const doubleSlop = 24.0;

  /// A finger that stays this long without moving asks too.
  static const longPress = Duration(milliseconds: 600);
  static const longSlop = 12.0;

  DecorName? _first;
  Offset _firstAt = Offset.zero;
  Duration _firstTime = Duration.zero;
  Timer? _held;
  Offset _heldAt = Offset.zero;

  /// A pointer came down at [position] on [under], or on nothing named.
  void down(Offset position, Duration time, DecorName? under) {
    _held?.cancel();
    _held = null;
    if (under == null) {
      _first = null;
      return;
    }
    if (identical(_first, under) &&
        time - _firstTime <= doubleWithin &&
        (position - _firstAt).distance <= doubleSlop) {
      _first = null;
      onAsk(under);
      return;
    }
    _first = under;
    _firstAt = position;
    _firstTime = time;
    _heldAt = position;
    _held = Timer(longPress, () {
      _held = null;
      _first = null;
      onAsk(under);
    });
  }

  void move(Offset position) {
    if (_held != null && (position - _heldAt).distance > longSlop) lift();
  }

  /// The pointer went up, or its gesture was taken away.
  void lift() {
    _held?.cancel();
    _held = null;
  }

  void dispose() => lift();
}

/// The named thing after [shown] — before it for a [step] below zero —
/// among those the frame shows, from left to right, then from top to
/// bottom: for the keyboard, F2 and Maj + F2. The first one (the last one
/// backwards) when none is shown; null when nothing has a name.
DecorName? nextDecorName(DecorPainting painting, DecorName? shown, int step) {
  final layout = painting.layout;
  final names = [...painting.names]
    ..sort((a, b) {
      final first = layout.place(a.at, a.anchor).center;
      final second = layout.place(b.at, b.anchor).center;
      final across = first.dx.compareTo(second.dx);
      return across != 0 ? across : first.dy.compareTo(second.dy);
    });
  if (names.isEmpty) return null;
  if (shown == null) return step > 0 ? names.first : names.last;
  return names[(names.indexOf(shown) + step) % names.length];
}

/// What is laid over the frame of the sheet for the names of the decor:
/// for a screen reader, each named thing, which it can ask about; and,
/// when one was asked, a dashed line around it and its card. The card goes
/// at a press, or by itself after [DecorNameLayer.shownFor].
class DecorNameLayer extends StatelessWidget {
  const DecorNameLayer({
    super.key,
    required this.painting,
    required this.sheetAtRest,
    required this.shown,
    required this.onAsk,
    required this.onClose,
    this.avoid,
    this.safe = EdgeInsets.zero,
  });

  final DecorPainting painting;

  /// Where the sheet lies when the whole of it is shown: a card stands on
  /// its edge. Null for a decor that is looked at without a sheet: a card
  /// then stands right beside its thing.
  final Rect? sheetAtRest;

  /// What a card must not cover — the button that leaves the decor — and
  /// what the device hides at the edges of the frame.
  final Rect? avoid;
  final EdgeInsets safe;

  /// The thing whose card is open, or null.
  final DecorName? shown;
  final ValueChanged<DecorName> onAsk;
  final VoidCallback onClose;

  /// How long a card stays when nobody closes it.
  static const shownFor = Duration(seconds: 9);
  static const cardWidth = 238.0;

  /// About how tall a card is: the longest text, on five lines. For
  /// keeping a card off the button that leaves a decor.
  static const cardHeight = 150.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final frame = constraints.biggest;
      final shown = this.shown;
      final layout = painting.layout;
      Widget? card;
      Rect? ring;
      if (shown != null && layout.shows(shown.anchor)) {
        final box = layout.place(shown.at, shown.anchor);
        ring = box.inflate(3);
        final sheet = sheetAtRest;
        final room = Rect.fromLTRB(
          safe.left + 8,
          safe.top + 8,
          math.max(safe.left + 8, frame.width - safe.right - 8),
          math.max(safe.top + 8, frame.height - safe.bottom - 8),
        );
        final width = math.min(cardWidth, math.max(120.0, room.width));
        double left;
        double? top;
        double? bottom;
        double within(double x) =>
            x.clamp(room.left, math.max(room.left, room.right - width));
        if (sheet == null) {
          // No sheet: right beside the thing, on the side of the middle of
          // the frame when there is room for the card there. A thing of
          // the upper half has the top of its card at its own top; one of
          // the lower half, the bottom of its card at its own bottom: the
          // card grows towards the middle, and stays whole in the frame
          // however long its text is.
          final after = box.right + 10;
          final before = box.left - 10 - width;
          final inwards = box.center.dx <= frame.width / 2;
          final fitsAfter = after + width <= room.right;
          final fitsBefore = before >= room.left;
          final low = box.center.dy > frame.height / 2;
          double? above;
          double? below;
          if (fitsAfter || fitsBefore) {
            left = within(
              inwards
                  ? (fitsAfter ? after : before)
                  : (fitsBefore ? before : after),
            );
            if (low) {
              below = math.min(room.bottom, box.bottom);
            } else {
              above = math.max(room.top, box.top);
            }
          } else {
            // Neither side has room: the card goes above a thing of the
            // lower half and below one of the upper half, and leaves it in
            // sight.
            left = within(box.center.dx - width / 2);
            if (low) {
              below = math.max(room.top + 60, box.top - 10);
            } else {
              above = math.min(room.bottom - 60, box.bottom + 10);
            }
          }
          final kept = avoid;
          if (kept != null &&
              above != null &&
              Rect.fromLTWH(left, above, width, cardHeight).overlaps(kept)) {
            above = kept.bottom + 8;
          }
          top = above;
          bottom = below == null ? null : frame.height - below;
        } else if (shown.anchor == DecorAnchor.middle) {
          // Under the sheet: the card stands just above the thing.
          left = within(box.center.dx - width / 2);
          bottom = math.max(8.0, frame.height - box.top + 8);
        } else {
          // Beside the sheet: on its edge, at the height of the thing.
          left = within(
            shown.anchor == DecorAnchor.left
                ? math.max(box.right + 8, sheet.left + 6)
                : math.min(box.left - 8 - width, sheet.right - 6 - width),
          );
          top = box.top.clamp(8.0, math.max(8.0, frame.height - 130));
        }
        card = Positioned(
          left: left,
          top: top,
          bottom: bottom,
          width: width,
          child: _NameCard(name: shown, onClose: onClose),
        );
      }
      return Stack(
        children: [
          for (final name in painting.names)
            Positioned.fromRect(
              rect: layout.place(name.at, name.anchor),
              child: Semantics(
                key: Key('decorName-${name.key}'),
                container: true,
                button: true,
                label: tr(name.frenchName),
                hint: tr('En savoir plus'),
                onTap: () => onAsk(name),
                // Nothing to press here for a pointer: the frame of the
                // sheet hears it, and the tool in hand is never stopped.
                child: const IgnorePointer(child: SizedBox.expand()),
              ),
            ),
          if (ring != null)
            Positioned.fromRect(
              rect: ring.inflate(2),
              child: const IgnorePointer(
                child: CustomPaint(
                  key: Key('decorNameRing'),
                  painter: _RingPainter(),
                ),
              ),
            ),
          ?card,
        ],
      );
    },
  );
}

// A dashed white line with a dark edge: seen on any decor.
class _RingPainter extends CustomPainter {
  const _RingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(2),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..color = const Color(0xbf293d4b),
    );
    final path = Path()..addRRect(box);
    final dashes = Path();
    for (final metric in path.computeMetrics()) {
      // Whole dashes around the box: none is cut at the seam.
      final count = math.max(4, (metric.length / 14).round());
      final step = metric.length / count;
      for (var index = 0; index < count; index++) {
        dashes.addPath(
          metric.extractPath(index * step, index * step + step * .58),
          Offset.zero,
        );
      }
    }
    canvas.drawPath(
      dashes,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xffffffff),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => false;
}

// The card of one named thing: its name and one or two lines. It is read
// aloud when it appears, and a press anywhere on it closes it. Its colours
// are its own, the same in every universe: a light card, dark letters.
class _NameCard extends StatelessWidget {
  const _NameCard({required this.name, required this.onClose});
  final DecorName name;
  final VoidCallback onClose;

  static const paper = Color(0xfffffdf6);
  static const ink = Color(0xff22303f);
  static const text = Color(0xff37454f);

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('decorNameCard'),
    container: true,
    liveRegion: true,
    button: true,
    hint: tr('Fermer'),
    child: Material(
      color: paper,
      elevation: 6,
      shadowColor: const Color(0x99141e32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xff293d4b), width: 2.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onClose,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(name.frenchName),
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                tr(name.frenchText),
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.42,
                  color: text,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A pill of the look's surface under a caption written on a decor: the
/// name of the sheet and its size stay readable on any picture.
class DecorCaption extends StatelessWidget {
  const DecorCaption({super.key, required this.child, required this.color});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: child,
    ),
  );
}

/// What kind of pointer [kind] is for a decor: a finger asks by a long
/// touch as well as by two.
bool decorAsksByHolding(PointerDeviceKind kind) =>
    kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus;
