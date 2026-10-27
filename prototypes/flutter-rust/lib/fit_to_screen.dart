// SPDX-License-Identifier: MIT
// The studio on a tablet or a telephone: inside the safe area of the screen,
// and scaled down whole when the screen, or the window of an iPad, is
// smaller than the studio needs.
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'platform_words.dart';
import 'studio_colors.dart';

/// The smallest room the studio is laid out for: the smallest window of
/// Color on a computer.
const studioMinimumSize = Size(680, 520);

/// The shortest side, in logical pixels, from which a screen is a tablet's.
const tabletShortestSide = 600.0;

/// On a telephone: the studio is laid out across the screen, and the bars
/// of the system give it their room until a swipe from the edge brings them
/// back. A tablet turns as it likes and keeps its bars. Nothing on a
/// computer.
Future<void> prepareTouchScreen() async {
  if (!touchFirst) return;
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return;
  final view = views.first;
  final size = view.physicalSize / view.devicePixelRatio;
  if (size.isEmpty || size.shortestSide >= tabletShortestSide) return;
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
/// [minimum], lays it out at a larger size and scales it down to fit: the
/// whole studio is seen and every button can be touched, smaller.
class FitToScreen extends StatelessWidget {
  const FitToScreen({
    super.key,
    required this.child,
    this.minimum = studioMinimumSize,
  });

  final Widget child;
  final Size minimum;

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
            final scale = fitScale(room, minimum: minimum);
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
