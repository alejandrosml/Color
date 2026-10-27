// SPDX-License-Identifier: MIT
// The door of the options: a multiplication that a grown-up solves at a
// glance and a small child does not. It keeps a child from changing the
// options by chance, or by trying; it is not a lock, and nothing secret is
// behind it: a child who knows the tables gets in.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'studio_colors.dart';
import 'studio_text.dart';

/// How the door was left.
enum AdultGate {
  /// The result was given.
  opened,

  /// The person gave up: « Annuler » or Échap.
  givenUp,

  /// Three wrong results: the door closed by itself. It can be asked again.
  closedAfterWrongAnswers,
}

/// Asks the calculation. A wrong result brings another one, and the third
/// wrong one closes the door: trying every result is not a way in. A click
/// beside the dialog does not close it — the second click of a double click
/// on « Options » would.
Future<AdultGate> showAdultGate(
  BuildContext context, {
  math.Random? random,
}) async =>
    await showDialog<AdultGate>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdultGateDialog(random: random),
    ) ??
    AdultGate.givenUp;

/// The calculation asked at the door: two numbers from 6 to 9 to multiply.
/// The result always has two digits, is one of ten, and is learnt with the
/// tables, around nine years old.
@immutable
class AdultGateQuestion {
  const AdultGateQuestion(this.first, this.second);

  /// Another question than [previous], drawn with [random].
  factory AdultGateQuestion.draw(
    math.Random random, {
    AdultGateQuestion? previous,
  }) {
    while (true) {
      final question = AdultGateQuestion(
        6 + random.nextInt(4),
        6 + random.nextInt(4),
      );
      // Neither the same question, nor the same one turned round, whose
      // result would be the one just refused or just read.
      if (previous == null || question.answer != previous.answer) {
        return question;
      }
    }
  }

  final int first;
  final int second;
  int get answer => first * second;

  /// As written on the screen.
  String get text => '$first × $second = ?';

  /// As said by a screen reader.
  String get spoken => 'Combien font $first fois $second ?';
}

class AdultGateDialog extends StatefulWidget {
  const AdultGateDialog({super.key, this.random});

  /// Where the numbers come from; tests give their own.
  final math.Random? random;

  /// Wrong results after which the door closes by itself.
  static const tries = 3;

  /// Letters enlarged by the system are enlarged in this dialog as far as
  /// the height of the window leaves every key in view, and no further:
  /// the keys are what a person without a keyboard answers with.
  static double textScaleLimit(Size window) {
    final room = window.height - 2 * _inset - 10;
    var limit = _heights.first.$1;
    for (final (scale, height) in _heights) {
      if (height <= room) limit = scale;
    }
    return limit;
  }

  static const _inset = 16.0;
  // The height the dialog needs for letters enlarged that many times,
  // measured with DejaVu Sans. A test lays the dialog out in windows of
  // several sizes and fails if these no longer hold.
  static const _heights = [
    (1.0, 475.0),
    (1.25, 526.0),
    (1.5, 554.0),
    (1.75, 585.0),
    (2.0, 616.0),
    (2.5, 689.0),
    (3.0, 769.0),
  ];

  @override
  State<AdultGateDialog> createState() => _AdultGateDialogState();
}

class _AdultGateDialogState extends State<AdultGateDialog> {
  late final math.Random _random = widget.random ?? math.Random();
  late AdultGateQuestion _question = AdultGateQuestion.draw(_random);
  final _focus = FocusNode(debugLabel: 'Calcul des options');
  String _typed = '';
  int _wrong = 0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _digit(int digit) {
    // The result has two digits: a third one is a slip of the hand.
    if (_typed.length >= 2) return;
    setState(() => _typed += '$digit');
  }

  void _erase() {
    if (_typed.isEmpty) return;
    setState(() => _typed = _typed.substring(0, _typed.length - 1));
  }

  void _enter() {
    if (_typed.isEmpty) return;
    if (int.parse(_typed) == _question.answer) {
      Navigator.pop(context, AdultGate.opened);
      return;
    }
    if (_wrong + 1 >= AdultGateDialog.tries) {
      Navigator.pop(context, AdultGate.closedAfterWrongAnswers);
      return;
    }
    setState(() {
      _question = AdultGateQuestion.draw(_random, previous: _question);
      _typed = '';
      _wrong++;
    });
    // « Entrer » has just lost its answer and, with it, the focus: it comes
    // back to the dialog itself, where digits and Entrée are heard, and not
    // to « Annuler ».
    _focus.requestFocus();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context, AdultGate.givenUp);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _erase();
      return KeyEventResult.handled;
    }
    // Entrée answers when no key of the dialog holds the focus; on a key it
    // presses that key, as everywhere. A key held down answers once.
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
      if (event is KeyDownEvent) _enter();
      return KeyEventResult.handled;
    }
    // The digits as the keyboard writes them, whatever its layout: a French
    // keyboard gives them with Maj, a numeric pad without. Wherever the
    // focus is in the dialog.
    final character = event.character;
    final digit = character != null && character.length == 1
        ? int.tryParse(character)
        : null;
    if (digit != null) {
      _digit(digit);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _keyButton({
    required Key key,
    required String spoken,
    required Widget child,
    required VoidCallback? onPressed,
  }) => SizedBox(
    width: 56,
    height: 56,
    child: OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: studioSurface,
        // The letters of the interface, as on every other button.
        textStyle: studioLabelStyle(
          context,
          22,
        ).copyWith(fontWeight: FontWeight.w700),
      ),
      child: Semantics(label: spoken, excludeSemantics: true, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: AdultGateDialog.textScaleLimit(MediaQuery.sizeOf(context)),
    // Around the whole dialog: a digit typed while « Annuler » holds the
    // focus is a digit of the answer too.
    child: Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: AlertDialog(
        key: const Key('adultGate'),
        scrollable: true,
        insetPadding: const EdgeInsets.all(AdultGateDialog._inset),
        title: const Text('Pour les adultes'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Les options sont réservées aux adultes. Pour entrer, donne le résultat :',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 8),
              Semantics(
                container: true,
                label: _question.spoken,
                excludeSemantics: true,
                child: Text(
                  _question.text,
                  key: const Key('adultGateQuestion'),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // What was typed, said again at every change.
                  Semantics(
                    container: true,
                    liveRegion: true,
                    label: _typed.isEmpty
                        ? 'Aucun chiffre tapé'
                        : 'Réponse tapée : $_typed',
                    excludeSemantics: true,
                    child: Container(
                      key: const Key('adultGateAnswer'),
                      width: 120,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: studioPreviewBox,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _wrong > 0 && _typed.isEmpty
                              ? studioWarning
                              : studioSwatchRing,
                          width: _wrong > 0 && _typed.isEmpty ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        _typed.isEmpty ? '…' : _typed,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _keyButton(
                    key: const Key('adultGateErase'),
                    spoken: 'Effacer le dernier chiffre',
                    onPressed: _typed.isEmpty ? null : _erase,
                    child: const Icon(Icons.backspace_outlined, size: 22),
                  ),
                ],
              ),
              SizedBox(
                height: 32,
                child: Center(
                  child: _wrong > 0 && _typed.isEmpty
                      ? Semantics(
                          liveRegion: true,
                          child: Text(
                            _wrong + 1 >= AdultGateDialog.tries
                                ? 'Ce n’est pas le bon résultat. Dernier essai avec cet autre calcul.'
                                : 'Ce n’est pas le bon résultat. Voici un autre calcul.',
                            key: const Key('adultGateWrong'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: studioWarning,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
              // Two rows of keys to click: nothing to type on a keyboard,
              // nothing to drag, and the whole dialog in view in the
              // smallest window.
              for (final row in const [
                [1, 2, 3, 4, 5],
                [6, 7, 8, 9, 0],
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final digit in row) ...[
                        if (digit != row.first) const SizedBox(width: 8),
                        _keyButton(
                          key: Key('adultGateDigit$digit'),
                          spoken: '$digit',
                          onPressed: () => _digit(digit),
                          child: Text('$digit'),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.all(16),
        actions: [
          TextButton(
            key: const Key('adultGateCancel'),
            style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
            onPressed: () => Navigator.pop(context, AdultGate.givenUp),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('adultGateEnter'),
            style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
            onPressed: _typed.isEmpty ? null : _enter,
            child: const Text('Entrer'),
          ),
        ],
      ),
    ),
  );
}
