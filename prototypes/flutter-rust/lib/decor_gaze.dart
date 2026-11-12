// SPDX-License-Identifier: MIT
// « Les décors à contempler » (Color 1.2, asked by the owner on 12 November
// 2026): the decor of a universe on the whole screen, not to draw but to
// look at — as much movement as there is, and a touch on a thing gives its
// name and a line or two about it.
//
// On a tablet and a telephone the sheet takes the whole screen, and no
// decor is shown around it: this is where a decor is seen there. A
// computer offers it as well. The child opens it with the button
// « Regarder » of « Choisis ton univers »; an adult may take that button
// away in the options.
//
// What it holds to:
// - the decor moves at « Maximum », whatever the studio is set to — unless
//   the adult chose « Aucun », the calm mode, or the system asks for less
//   motion: then nothing moves at all;
// - one press on a thing names it (there is no drawing to protect here);
//   F2 and Maj + F2 go from one thing to the next; a screen reader meets
//   each thing as a button; the option that cuts the cards cuts them here;
// - the way out is one large button, « Mon dessin », always in the same
//   corner. It fades after a few seconds without a touch and comes back at
//   the first one, anywhere — and that touch is not lost: it names what it
//   touched as well. Faded, it is still there for a screen reader and for
//   switch control. Échap, Entrée and the back button of Android leave too.
// - no link ever leads outside (the children's category).
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'decor.dart';
import 'decor_motion.dart';
import 'decor_view.dart';
import 'language.dart';
import 'universe.dart';

/// Shows the decor of [universe] on the whole screen, and completes when
/// the child leaves it. Does nothing for a universe without a decor.
///
/// [motion] is what the adult chose for the decor of the studio: looked
/// at, a decor moves as much as it can, unless that is « Aucun ». [names]
/// says whether a touch names a thing.
Future<void> showDecorGaze(
  BuildContext context, {
  required Universe universe,
  required DecorMotion motion,
  required bool names,
  DateTime Function()? now,
}) {
  if (universe.decor == null) return Future.value();
  final calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  final fade = calm ? Duration.zero : const Duration(milliseconds: 220);
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'decorGaze'),
      fullscreenDialog: true,
      transitionDuration: fade,
      reverseTransitionDuration: fade,
      pageBuilder: (context, _, _) =>
          DecorGaze(universe: universe, motion: motion, names: names, now: now),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The decor of a universe on the whole screen, to look at.
class DecorGaze extends StatefulWidget {
  const DecorGaze({
    super.key,
    required this.universe,
    required this.motion,
    required this.names,
    this.now,
    this.arrangement,
  });

  /// A universe that has a decor.
  final Universe universe;

  /// What the adult chose for the decor of the studio.
  final DecorMotion motion;

  /// Whether a touch on a thing shows its card.
  final bool names;
  final DateTime Function()? now;

  /// How the two sides of the decor stand; left to the screen when null.
  final DecorGazeArrangement? arrangement;

  /// How long the button « Mon dessin » stays when the decor appears, and
  /// after the last touch; how long it takes to fade.
  static const firstShownFor = Duration(seconds: 8);
  static const shownFor = Duration(seconds: 4);
  static const fade = Duration(milliseconds: 300);

  /// The button is large: for small hands, and for hands that do not aim
  /// well.
  static const buttonHeight = 60.0;
  static const buttonWidth = 196.0;
  static const buttonInset = 12.0;

  /// How much a decor that is looked at moves, for what the adult chose:
  /// as much as it can, or not at all in the calm mode.
  static DecorMotion motionFor(DecorMotion chosen) =>
      chosen.moves ? DecorMotion.high : DecorMotion.none;

  @override
  State<DecorGaze> createState() => _DecorGazeState();
}

class _DecorGazeState extends State<DecorGaze> {
  final _focus = FocusNode(debugLabel: 'decorGaze');

  /// The button « Mon dessin » is in sight.
  bool _button = true;
  Timer? _hide;

  /// The pointers that are down: the button stays while one is.
  final _pointers = <int>{};

  /// The thing whose card is open.
  final _shownName = ValueNotifier<DecorName?>(null);
  Timer? _nameTimer;
  final _cursor = ValueNotifier<MouseCursor>(SystemMouseCursors.basic);

  /// The decor as the screen shows it now.
  DecorPainting? _painting;

  @override
  void initState() {
    super.initState();
    _hideAfter(DecorGaze.firstShownFor);
  }

  @override
  void dispose() {
    _hide?.cancel();
    _nameTimer?.cancel();
    _shownName.dispose();
    _cursor.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _hideAfter(Duration delay) {
    _hide?.cancel();
    _hide = Timer(delay, () {
      _hide = null;
      if (mounted && _pointers.isEmpty) setState(() => _button = false);
    });
  }

  // Something was touched, or a key pressed: the button is there, and
  // stays for a while after the last of it.
  void _wake() {
    if (!_button) setState(() => _button = true);
    _hideAfter(DecorGaze.shownFor);
  }

  void _anyDown(PointerDownEvent event) {
    _pointers.add(event.pointer);
    _wake();
  }

  void _anyUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) _hideAfter(DecorGaze.shownFor);
  }

  void _leave() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _showName(DecorName name) {
    if (!mounted || !widget.names) return;
    _nameTimer?.cancel();
    _shownName.value = name;
    _nameTimer = Timer(DecorNameLayer.shownFor, _closeName);
  }

  void _closeName() {
    _nameTimer?.cancel();
    _nameTimer = null;
    if (mounted) _shownName.value = null;
  }

  // A press on the decor: one is enough here to ask the name of a thing;
  // a press on nothing puts the open card away.
  void _decorDown(PointerDownEvent event) {
    if (!widget.names) return;
    final under = _painting?.nameAt(event.localPosition);
    if (under == null) {
      _closeName();
    } else {
      _showName(under);
    }
  }

  void _decorHover(PointerHoverEvent event) {
    _cursor.value =
        widget.names && _painting?.nameAt(event.localPosition) != null
        ? SystemMouseCursors.help
        : SystemMouseCursors.basic;
    // A mouse that moves brings the button back, as a touch does.
    if (!_button) _wake();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _leave();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      // The button of the keyboard: there first, pressed then.
      if (_button) {
        _leave();
      } else {
        _wake();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2) {
      final painting = _painting;
      if (painting != null && widget.names) {
        final next = nextDecorName(
          painting,
          _shownName.value,
          HardwareKeyboard.instance.isShiftPressed ? -1 : 1,
        );
        if (next != null) _showName(next);
      }
      _wake();
      return KeyEventResult.handled;
    }
    // Any other key: the way out shows itself.
    _wake();
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final decor = widget.universe.decor;
    if (decor == null) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final calm = media.disableAnimations;
    // What the device hides: the pieces keep away from the sides and from
    // the top; they stand on the bottom edge with their ground.
    final safe = EdgeInsets.fromLTRB(
      media.viewPadding.left,
      media.viewPadding.top,
      media.viewPadding.right,
      0,
    );
    final view = DecorView.gaze(
      decor: decor,
      motion: DecorGaze.motionFor(widget.motion),
      safe: safe,
      arrangement: widget.arrangement,
      now: widget.now,
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: trf('{0} : le décor à regarder', [widget.universe.name]),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _key,
        child: Listener(
          // Every touch, wherever it falls, brings the button back.
          behavior: HitTestBehavior.translucent,
          onPointerDown: _anyDown,
          onPointerUp: _anyUp,
          onPointerCancel: _anyUp,
          child: ColoredBox(
            color: decor.top,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final frame = constraints.biggest;
                final painting = DecorPainting(decor, view.layoutIn(frame));
                _painting = painting;
                final button = Rect.fromLTWH(
                  safe.left + DecorGaze.buttonInset,
                  safe.top + DecorGaze.buttonInset,
                  DecorGaze.buttonWidth,
                  DecorGaze.buttonHeight,
                );
                return Stack(
                  children: [
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: RepaintBoundary(child: view),
                      ),
                    ),
                    Positioned.fill(
                      child: ValueListenableBuilder<MouseCursor>(
                        valueListenable: _cursor,
                        builder: (context, cursor, child) =>
                            MouseRegion(cursor: cursor, child: child),
                        child: Listener(
                          key: const Key('decorGazeSurface'),
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: _decorDown,
                          onPointerHover: _decorHover,
                        ),
                      ),
                    ),
                    if (widget.names)
                      Positioned.fill(
                        child: ValueListenableBuilder<DecorName?>(
                          valueListenable: _shownName,
                          builder: (context, shown, _) => DecorNameLayer(
                            painting: painting,
                            sheetAtRest: null,
                            shown: shown,
                            onAsk: _showName,
                            onClose: _closeName,
                            avoid: button,
                            safe: safe.copyWith(
                              bottom: media.viewPadding.bottom,
                            ),
                          ),
                        ),
                      ),
                    Positioned.fromRect(
                      rect: button,
                      child: _LeaveButton(
                        shown: _button,
                        fade: calm ? Duration.zero : DecorGaze.fade,
                        onLeave: _leave,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// « ← Mon dessin » : the way back. Its colours are its own, the same on
// every decor, as those of a card: a light button, dark letters. Faded, a
// press goes through it to the decor — and brings it back — but a screen
// reader and switch control still find it and can press it.
class _LeaveButton extends StatelessWidget {
  const _LeaveButton({
    required this.shown,
    required this.fade,
    required this.onLeave,
  });
  final bool shown;
  final Duration fade;
  final VoidCallback onLeave;

  static const paper = Color(0xfffffdf6);
  static const ink = Color(0xff22303f);

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('leaveDecorGaze'),
    container: true,
    button: true,
    label: tr('Mon dessin'),
    hint: tr('Revenir à mon dessin'),
    onTap: onLeave,
    child: ExcludeSemantics(
      child: IgnorePointer(
        ignoring: !shown,
        child: AnimatedOpacity(
          key: const Key('leaveDecorGazeFade'),
          opacity: shown ? 1 : 0,
          duration: fade,
          child: Material(
            color: paper,
            elevation: 6,
            shadowColor: const Color(0x99141e32),
            shape: const StadiumBorder(
              side: BorderSide(color: Color(0xff293d4b), width: 2.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              canRequestFocus: false,
              onTap: onLeave,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_back_rounded, size: 30, color: ink),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        tr('Mon dessin'),
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
