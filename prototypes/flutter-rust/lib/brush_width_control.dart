// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// A bounded desktop control without Material Slider's value-indicator overlay.
class BrushWidthControl extends StatefulWidget {
  const BrushWidthControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  }) : assert(value >= 2 && value <= 48);

  final double value;
  final ValueChanged<double>? onChanged;

  /// Called when one change is over: at the end of a slide, and after each
  /// click, key or assistive action. A slide calls [onChanged] at every
  /// notch and this once.
  final VoidCallback? onChangeEnd;

  @override
  State<BrushWidthControl> createState() => _BrushWidthControlState();
}

class _WidthIntent extends Intent {
  const _WidthIntent(this.delta);
  final int delta;
}

class _BrushWidthControlState extends State<BrushWidthControl> {
  final _focus = FocusNode(debugLabel: 'Épaisseur du pinceau');
  bool _focused = false;
  bool get _enabled => widget.onChanged != null;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _change(double value) {
    final next = value.roundToDouble().clamp(2.0, 48.0);
    if (_enabled && next != widget.value) widget.onChanged!(next);
  }

  // One change made at once, not a slide: it is over as soon as it is made.
  void _changeOnce(double value) {
    _change(value);
    if (_enabled) widget.onChangeEnd?.call();
  }

  String _units(double value) => '${value.round()} unités de document';

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final canIncrease = _enabled && widget.value < 48;
    final canDecrease = _enabled && widget.value > 2;
    return FocusableActionDetector(
      focusNode: _focus,
      enabled: _enabled,
      includeFocusSemantics: false,
      onFocusChange: (focused) => setState(() => _focused = focused),
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowRight): _WidthIntent(
          rtl ? -1 : 1,
        ),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _WidthIntent(
          rtl ? 1 : -1,
        ),
        const SingleActivator(LogicalKeyboardKey.arrowUp): const _WidthIntent(
          1,
        ),
        const SingleActivator(LogicalKeyboardKey.arrowDown): const _WidthIntent(
          -1,
        ),
      },
      actions: <Type, Action<Intent>>{
        _WidthIntent: CallbackAction<_WidthIntent>(
          onInvoke: (intent) {
            _changeOnce(widget.value + intent.delta);
            return null;
          },
        ),
      },
      child: Semantics(
        key: const Key('brushWidthSemantics'),
        container: true,
        // Replace Cupertino's percentage semantics with the same slider role,
        // document units, focus and adjustment actions; retain pointer input.
        excludeSemantics: true,
        slider: true,
        label: 'Épaisseur du pinceau',
        value: _units(widget.value),
        increasedValue: canIncrease ? _units(widget.value + 1) : null,
        decreasedValue: canDecrease ? _units(widget.value - 1) : null,
        enabled: _enabled,
        focusable: _enabled,
        focused: _enabled && _focused,
        onFocus: _enabled ? _focus.requestFocus : null,
        onIncrease: canIncrease ? () => _changeOnce(widget.value + 1) : null,
        onDecrease: canDecrease ? () => _changeOnce(widget.value - 1) : null,
        child: SizedBox(
          height: 48,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Listener(
                onPointerDown: _enabled ? (_) => _focus.requestFocus() : null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTapUp: !_enabled
                      ? null
                      : (details) {
                          // Cupertino uses 8 logical pixels of track padding plus its
                          // public thumb radius. A click also works away from the thumb.
                          const inset = 8.0 + CupertinoThumbPainter.radius;
                          var fraction =
                              ((details.localPosition.dx - inset) /
                                      math.max(
                                        1.0,
                                        constraints.maxWidth - 2 * inset,
                                      ))
                                  .clamp(0.0, 1.0);
                          if (rtl) fraction = 1 - fraction;
                          _changeOnce(2 + 46 * fraction);
                        },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _enabled && _focused
                            ? const Color(0xff176c5f)
                            : const Color(0x00000000),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: CupertinoSlider(
                        value: widget.value,
                        min: 2,
                        max: 48,
                        divisions: 46,
                        activeColor: const Color(0xff176c5f),
                        onChanged: _enabled ? _change : null,
                        onChangeEnd: _enabled
                            ? (_) => widget.onChangeEnd?.call()
                            : null,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
