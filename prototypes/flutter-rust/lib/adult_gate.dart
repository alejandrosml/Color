// SPDX-License-Identifier: MIT
// The door of the options: a multiplication that a grown-up solves at a
// glance and a small child does not. It keeps a child from changing the
// options by chance, or by trying; it is not a lock, and nothing secret is
// behind it: a child who knows the tables gets in.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fit_to_screen.dart';
import 'studio_colors.dart';
import 'studio_text.dart';
import 'language.dart';

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
      builder: (_) => FitDialog(child: AdultGateDialog(random: random)),
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
  String get spoken => trf('Combien font {0} fois {1} ?', [first, second]);
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
    (1.0, 452.0),
    (1.25, 487.0),
    (1.5, 506.0),
    (1.75, 537.0),
    (2.0, 569.0),
    (2.5, 636.0),
    (3.0, 704.0),
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
    if (!mounted || _typed.length >= 2) return;
    setState(() => _typed += '$digit');
    // Every result has two digits: the second one answers, with nothing
    // else to press. The right one opens at once.
    if (_typed.length == 2) _answer();
  }

  void _erase() {
    if (_typed.isEmpty) return;
    setState(() => _typed = _typed.substring(0, _typed.length - 1));
  }

  void _answer() {
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
    // The focus comes back to the dialog itself, where the digits of the
    // keyboard are heard, and not to « Annuler ».
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
    // The digits as the keyboard writes them, whatever its layout: a French
    // keyboard gives them with Maj, a numeric pad without. Wherever the
    // focus is in the dialog. A key held down types once: a hand that rests
    // on it does not answer for itself.
    final character = event.character;
    final digit = character != null && character.length == 1
        ? int.tryParse(character)
        : null;
    if (digit != null) {
      if (event is KeyDownEvent) _digit(digit);
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
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
        // Giving up, at the top: below are only the keys of the answer.
        title: Row(
          children: [
            Expanded(child: Text(tr('Pour les adultes'))),
            TextButton(
              key: const Key('adultGateCancel'),
              style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed: () => Navigator.pop(context, AdultGate.givenUp),
              child: Text(tr('Annuler')),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                tr(
                  'Les options sont réservées aux adultes. Pour entrer, donne le résultat :',
                ),
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 10),
              // The calculation and its answer on one line, as on a
              // calculator: the second digit answers.
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  Semantics(
                    container: true,
                    label: _question.spoken,
                    excludeSemantics: true,
                    child: Text(
                      _question.text,
                      key: const Key('adultGateQuestion'),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  // What was typed, said again at every change.
                  Semantics(
                    container: true,
                    liveRegion: true,
                    label: _typed.isEmpty
                        ? tr('Aucun chiffre tapé')
                        : trf('Réponse tapée : {0}', [_typed]),
                    excludeSemantics: true,
                    child: Container(
                      key: const Key('adultGateAnswer'),
                      width: 88,
                      height: 52,
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
                ],
              ),
              SizedBox(
                height: 30,
                child: Center(
                  child: _wrong > 0 && _typed.isEmpty
                      ? Semantics(
                          liveRegion: true,
                          child: Text(
                            _wrong + 1 >= AdultGateDialog.tries
                                ? tr(
                                    'Ce n’est pas le bon résultat. Dernier essai avec cet autre calcul.',
                                  )
                                : tr(
                                    'Ce n’est pas le bon résultat. Voici un autre calcul.',
                                  ),
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
              // The keys of a calculator: nothing to type on a keyboard,
              // nothing to drag, nothing to confirm.
              for (final (index, row) in const [
                [7, 8, 9],
                [4, 5, 6],
                [1, 2, 3],
                [null, 0, -1],
              ].indexed)
                Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final (column, digit) in row.indexed) ...[
                        if (column > 0) const SizedBox(width: 8),
                        if (digit == null)
                          const SizedBox(width: 56, height: 56)
                        else if (digit < 0)
                          _keyButton(
                            key: const Key('adultGateErase'),
                            spoken: tr('Effacer le dernier chiffre'),
                            onPressed: _typed.isEmpty ? null : _erase,
                            child: const Icon(
                              Icons.backspace_outlined,
                              size: 22,
                            ),
                          )
                        else
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
      ),
    ),
  );
}
