// SPDX-License-Identifier: MIT
// The studio on a tablet or a telephone: inside the safe area of the screen,
// and scaled down whole when the screen, or the window of an iPad, is
// smaller than the studio needs.
import 'dart:math' as math;
import 'dart:ui' show FlutterView;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'platform_words.dart';
import 'studio_colors.dart';

/// The smallest room the studio is laid out for: the smallest window of
/// Color on a computer.
const studioMinimumSize = Size(680, 520);

/// The shortest side, in logical pixels, from which a screen is a tablet's.
const tabletShortestSide = 600.0;

/// The smallest room the studio of a telephone is laid out for: a small
/// Android telephone on its side keeps its full size.
const phoneMinimumSize = Size(560, 320);

/// The whole screen that shows [view], in logical pixels, whatever the size
/// of its window: an iPad or an Android tablet that gives Color a small
/// window is still a tablet. Empty when the system says nothing of it.
Size screenSize(FlutterView view) {
  try {
    final display = view.display;
    if (display.devicePixelRatio > 0 && !display.size.isEmpty) {
      return display.size / display.devicePixelRatio;
    }
  } catch (_) {
    // A system that names no screen: the window stands for it.
  }
  return view.devicePixelRatio > 0
      ? view.physicalSize / view.devicePixelRatio
      : Size.zero;
}

/// Whether [view] is shown on a telephone's screen.
bool phoneScreen(FlutterView view) {
  final screen = screenSize(view);
  return !screen.isEmpty && screen.shortestSide < tabletShortestSide;
}

/// Whether the studio, in a [room] of that size on the screen of [view],
/// stands on a telephone on its side, for which it has a layout of its own:
/// the sheet in the middle, the tools on one side, the colours and choices
/// on the other. A tablet keeps the studio of a computer, whatever its
/// window, and so does a telephone held upright.
bool phoneRoom(FlutterView view, Size room) =>
    phoneScreen(view) && room.width >= room.height;

/// On a telephone: the studio is laid out across the screen, and the bars
/// of the system give it their room until a swipe from the edge brings them
/// back. A tablet turns as it likes and keeps its bars. Nothing on a
/// computer.
Future<void> prepareTouchScreen() async {
  if (!touchFirst) return;
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty || !phoneScreen(views.first)) return;
  try {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } catch (_) {
    // A system that refuses keeps its own way: Color still works.
  }
}

/// The scale at which a studio laid out for [minimum] fits in [room]: 1
/// when it fits as it is, smaller otherwise, never larger.
double fitScale(Size room, {Size minimum = studioMinimumSize}) {
  if (room.width <= 0 || room.height <= 0) return 1;
  return math.min(
    1,
    math.min(room.width / minimum.width, room.height / minimum.height),
  );
}

/// Places [child] inside the safe area and, on a screen smaller than
/// [minimum] — [phoneMinimum] for a telephone on its side, whose studio has
/// a layout of its own — lays it out at a larger size and scales it down to
/// fit: the whole studio is seen and every button can be touched, smaller.
class FitToScreen extends StatelessWidget {
  const FitToScreen({
    super.key,
    required this.child,
    this.minimum = studioMinimumSize,
    this.phoneMinimum = phoneMinimumSize,
  });

  final Widget child;
  final Size minimum;
  final Size phoneMinimum;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return ColoredBox(
      color: studioBackground,
      child: Padding(
        padding: media.padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final room = constraints.biggest;
            final scale = fitScale(
              room,
              minimum: phoneRoom(View.of(context), room)
                  ? phoneMinimum
                  : minimum,
            );
            final laidOut = Size(room.width / scale, room.height / scale);
            // Inside, the safe area is already kept: no padding is left
            // for the widgets below to keep a second time.
            final inner = MediaQuery(
              data: media.copyWith(
                size: laidOut,
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
                viewInsets: media.viewInsets / scale,
              ),
              child: child,
            );
            if (scale >= 1) return inner;
            return FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(size: laidOut, child: inner),
            );
          },
        ),
      ),
    );
  }
}

/// A dialog over the studio of a telephone on its side. The studio of a
/// telephone is laid out for its screen; a dialog keeps the room it has on
/// the smallest window of a computer, scaled down whole to the screen, as
/// the whole studio was before it had a layout of its own: every word and
/// every button of it is there, smaller. Elsewhere [child] is left as it is.
class FitDialog extends StatelessWidget {
  const FitDialog({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final room = media.size;
    if (!touchFirst || !phoneRoom(View.of(context), room)) return child;
    final scale = fitScale(room);
    if (scale >= 1) return child;
    final laidOut = Size(room.width / scale, room.height / scale);
    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: laidOut,
        child: MediaQuery(
          data: media.copyWith(
            size: laidOut,
            padding: media.padding / scale,
            viewPadding: media.viewPadding / scale,
            viewInsets: media.viewInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }
}
