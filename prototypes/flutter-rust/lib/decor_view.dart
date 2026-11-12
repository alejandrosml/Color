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
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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

/// How many times a decor made the image of its still pieces, for the
/// tests: once per frame, universe and moment, never per image.
@visibleForTesting
int debugDecorStillImages = 0;

/// The decor of a universe in the frame of the sheet.
class DecorView extends StatefulWidget {
  const DecorView({
    super.key,
    required this.decor,
    required this.sheetAtRest,
    required this.motion,
    this.now,
  });

  final Decor decor;

  /// Where the sheet lies in this frame when the whole of it is shown.
  final Rect sheetAtRest;

  /// What the adult chose. The system's « Réduire les animations » stills
  /// the decor whatever this says.
  final DecorMotion motion;

  /// The time of the device; [DateTime.now] when null.
  final DateTime Function()? now;

  /// How often the pieces that move are painted again.
  static const period = Duration(milliseconds: 33);

  @override
  State<DecorView> createState() => _DecorViewState();
}

class _DecorViewState extends State<DecorView> with WidgetsBindingObserver {
  /// Seconds of movement since the decor appeared: they stand still while
  /// nothing moves.
  final _seconds = ValueNotifier<double>(0);

  /// Counts the minutes that pass: the clock and the light follow.
  final _minutes = ValueNotifier<int>(0);
  final _still = _StillImage();
  Timer? _moving;
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
    }
    if (inFront == _inFront) return;
    _inFront = inFront;
    // Back in front: the clock may have gone on without Color.
    if (inFront) _minutes.value++;
    _settle();
  }

  /// The system runs short of memory: the image goes, and is made again
  /// when the decor is next painted.
  @override
  void didHaveMemoryPressure() => _still.drop();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _moving?.cancel();
    _minute?.cancel();
    _still.drop();
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
      _moving ??= Timer.periodic(DecorView.period, (_) {
        _seconds.value += DecorView.period.inMicroseconds / 1e6;
      });
    } else {
      _moving?.cancel();
      _moving = null;
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
      if (_inFront && widget.decor.followsTheHour) _awaitMinute();
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final decor = widget.decor;
      final painting = DecorPainting(
        decor,
        DecorLayout(
          frame: constraints.biggest,
          sheetAtRest: widget.sheetAtRest,
          decor: decor.size,
          decorSheet: decor.sheet,
        ),
      );
      return CustomPaint(
        key: const Key('decor'),
        size: constraints.biggest,
        painter: _DecorPainter(
          painting: painting,
          seconds: _seconds,
          minutes: _minutes,
          // At rest in the calm mode: the pieces where their pictures draw
          // them, and those of the higher levels away.
          motion: _calm || debugDecorStill ? DecorMotion.none : widget.motion,
          now: _now,
          still: _still,
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
      );
    },
  );
}

/// The image of the still pieces of a decor, for one frame and one moment.
class _StillImage {
  ui.Image? _image;
  Decor? _decor;
  DecorLayout? _layout;
  DayMoment? _moment;
  double _ratio = 0;

  /// The longest side of the image, in pixels: beyond it the image is
  /// made at a lower ratio, and drawn enlarged.
  static const longest = 4096;

  ui.Image? imageFor(
    DecorPainting painting,
    DayMoment moment,
    double pixelRatio,
  ) {
    final frame = painting.layout.frame;
    if (frame.isEmpty) return null;
    final ratio = math.min(
      pixelRatio,
      longest / math.max(frame.width, frame.height),
    );
    if (_image != null &&
        identical(_decor, painting.decor) &&
        _layout == painting.layout &&
        _moment == moment &&
        _ratio == ratio) {
      return _image;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(ratio);
    painting.paintStill(canvas, moment);
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
    debugDecorStillImages++;
    _image?.dispose();
    _image = image;
    _decor = painting.decor;
    _layout = painting.layout;
    _moment = moment;
    _ratio = ratio;
    return image;
  }

  double get ratio => _ratio;

  /// Lets the image go; the next call of [imageFor] makes it again.
  void drop() {
    _image?.dispose();
    _image = null;
  }
}

class _DecorPainter extends CustomPainter {
  _DecorPainter({
    required this.painting,
    required this.seconds,
    required this.minutes,
    required this.motion,
    required this.now,
    required this.still,
    required this.pixelRatio,
  }) : super(repaint: Listenable.merge([seconds, minutes]));

  final DecorPainting painting;
  final ValueListenable<double> seconds;
  final ValueListenable<int> minutes;
  final DecorMotion motion;
  final DateTime Function() now;
  final _StillImage still;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final time = now();
    final image = still.imageFor(painting, DayMoment.at(time), pixelRatio);
    if (image != null) {
      canvas.save();
      canvas.scale(1 / still.ratio);
      canvas.drawImage(
        image,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.low,
      );
      canvas.restore();
    }
    painting.paintLive(
      canvas,
      seconds: seconds.value,
      time: time,
      motion: motion,
    );
  }

  @override
  bool shouldRepaint(_DecorPainter old) =>
      !identical(old.painting.decor, painting.decor) ||
      old.painting.layout != painting.layout ||
      old.motion != motion ||
      old.pixelRatio != pixelRatio;
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
  });

  final DecorPainting painting;
  final Rect sheetAtRest;

  /// The thing whose card is open, or null.
  final DecorName? shown;
  final ValueChanged<DecorName> onAsk;
  final VoidCallback onClose;

  /// How long a card stays when nobody closes it.
  static const shownFor = Duration(seconds: 9);
  static const cardWidth = 238.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final frame = constraints.biggest;
      final shown = this.shown;
      final layout = painting.layout;
      Widget? card;
      Rect? ring;
      if (shown != null && layout.pieces) {
        final box = layout.place(shown.at, shown.anchor);
        ring = box.inflate(3);
        final width = math.min(cardWidth, math.max(120.0, frame.width - 16));
        final double left;
        double? top;
        double? bottom;
        if (shown.anchor == DecorAnchor.middle) {
          // Under the sheet: the card stands just above the thing.
          left = (box.center.dx - width / 2).clamp(
            8.0,
            math.max(8.0, frame.width - width - 8),
          );
          bottom = math.max(8.0, frame.height - box.top + 8);
        } else {
          // Beside the sheet: on its edge, at the height of the thing.
          left =
              (shown.anchor == DecorAnchor.left
                      ? math.max(box.right + 8, sheetAtRest.left + 6)
                      : math.min(
                          box.left - 8 - width,
                          sheetAtRest.right - 6 - width,
                        ))
                  .clamp(8.0, math.max(8.0, frame.width - width - 8));
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
          if (layout.pieces)
            for (final name in painting.decor.names)
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
