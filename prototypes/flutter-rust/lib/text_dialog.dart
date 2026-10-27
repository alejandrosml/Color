// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'rust_document.dart' show maxTextBytes, maxTextLines;
import 'screen_keyboard.dart';
import 'size_choice.dart';
import 'text_layout.dart';

/// What the child confirmed: normalized characters and a size choice.
class TextEntry {
  const TextEntry(this.text, this.size);
  final String text;
  final ObjectSize size;
}

/// Says why a text cannot stand on the sheet at a size, or null when it can.
typedef TextProblem = String? Function(String text, ObjectSize size);

/// Asks for the characters of a new or existing text. Returns null when the
/// dialog is cancelled; the caller's drawing is never touched from here.
///
/// [problem] is asked when the text is confirmed: while it answers, the
/// dialog stays open with that sentence and every typed word. A click beside
/// the dialog does not close it either: only Annuler and Échap give up what
/// was typed.
Future<TextEntry?> showTextEntryDialog(
  BuildContext context, {
  String initialText = '',
  required ObjectSize initialSize,
  bool editing = false,
  TextProblem? problem,
  bool screenKeyboard = false,
}) => showDialog<TextEntry>(
  context: context,
  barrierDismissible: false,
  builder: (_) => TextEntryDialog(
    initialText: initialText,
    initialSize: initialSize,
    editing: editing,
    problem: problem,
    screenKeyboard: screenKeyboard,
  ),
);

class TextEntryDialog extends StatefulWidget {
  const TextEntryDialog({
    super.key,
    this.initialText = '',
    required this.initialSize,
    this.editing = false,
    this.problem,
    this.screenKeyboard = false,
  });
  final String initialText;
  final ObjectSize initialSize;
  final bool editing;
  final TextProblem? problem;

  /// Keys to click under the field, for who writes with a pointer only.
  final bool screenKeyboard;

  /// What a child may type in a new text. A text that is already longer,
  /// from a project made elsewhere, is not held to it: it may be changed
  /// and grow up to what a project keeps, and is never cut.
  static const typedCharacters = 280;

  /// With the keys to click, everything must stay in view without scrolling:
  /// who writes with a pointer only may have nothing to scroll with. Letters
  /// enlarged by the system are enlarged in this dialog as far as the height
  /// of the window allows, and no further.
  static double keysTextScaleLimit(Size window) {
    // What the dialog may take of the window, less a margin for letters a
    // little taller than those it was measured with.
    final room = window.height - 2 * _inset - 10;
    var limit = _heights.first.$1;
    for (final (scale, height) in _heights) {
      if (height <= room) limit = scale;
    }
    return limit;
  }

  static const _inset = 16.0;
  // The height the dialog with its keys needs for letters enlarged that many
  // times, measured with DejaVu Sans. From about one and a half the two
  // buttons go under the sizes. A test lays the dialog out in windows of
  // several sizes and fails if these no longer hold.
  static const _heights = [
    (1.0, 478.0),
    (1.25, 502.0),
    (1.5, 580.0),
    (1.75, 604.0),
    (2.0, 626.0),
    (2.5, 684.0),
    (3.0, 806.0),
  ];
  static const tooManyLines =
      'Ton texte a trop de lignes : il peut en avoir $maxTextLines au plus.';
  static const tooLong =
      'Ton texte est trop long pour être gardé en entier. Raccourcis-le un peu.';

  @override
  State<TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<TextEntryDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  late ObjectSize _size = widget.initialSize;

  /// Why the last confirmation was not accepted; cleared by the next change.
  String? _problem;

  String? get _text => normalizeTextInput(_controller.text);

  // A text that came longer than a child types is not stopped at that
  // length. No character holds less than one byte: one more of them than a
  // project keeps bytes is already too long, and confirming says so. The
  // field takes that one and no more, so that a text pasted far too long is
  // announced, not cut to the limit without a word.
  late final _limit =
      widget.initialText.characters.length > TextEntryDialog.typedCharacters
      ? maxTextBytes + 1
      : TextEntryDialog.typedCharacters;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _text;
    if (text == null) return;
    // Nothing is dropped without a word: the end of a text that is too
    // long would otherwise be cut by the normalization.
    final problem = switch (textExcess(_controller.text)) {
      TextExcess.lines => TextEntryDialog.tooManyLines,
      TextExcess.length => TextEntryDialog.tooLong,
      null => widget.problem?.call(text, _size),
    };
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.pop(context, TextEntry(text, _size));
  }

  @override
  Widget build(BuildContext context) {
    final dialog = _dialog(context);
    if (!widget.screenKeyboard) return dialog;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: TextEntryDialog.keysTextScaleLimit(
        MediaQuery.sizeOf(context),
      ),
      child: dialog,
    );
  }

  Widget _dialog(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): _confirm,
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _confirm,
      // The barrier does not close this dialog; Échap still gives up.
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.pop(context),
    },
    child: AlertDialog(
      key: const Key('textDialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.all(TextEntryDialog._inset),
      title: Text(widget.editing ? 'Change ton texte' : 'Écris ton texte'),
      content: SizedBox(
        width: widget.screenKeyboard ? ScreenKeyboard.width + 8 : 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('textField'),
              controller: _controller,
              autofocus: true,
              minLines: 2,
              // With the keys the field keeps its height, and a longer text
              // scrolls inside: a key must not slide from under the pointer
              // because a line was added.
              maxLines: widget.screenKeyboard ? 2 : 5,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(_limit)],
              // A sign that the letters of the interface do not have is
              // shown in those of the sheet, where it will be drawn.
              style: const TextStyle(
                fontSize: 20,
                fontFamilyFallback: [colorTextFontFamily],
              ),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Ton texte',
                hintText: 'Écris ici…',
                helperText: 'La touche Entrée passe à la ligne.',
                helperMaxLines: 3,
                errorText: _problem,
                errorMaxLines: 4,
              ),
              onChanged: (_) => setState(() => _problem = null),
            ),
            if (widget.screenKeyboard) ...[
              const SizedBox(height: 10),
              Center(
                child: ScreenKeyboard(
                  controller: _controller,
                  limit: _limit,
                  onChanged: () => setState(() => _problem = null),
                ),
              ),
            ],
            if (!widget.screenKeyboard) ...[
              const SizedBox(height: 16),
              _sizeChoice(),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(16),
      actionsOverflowButtonSpacing: 8,
      // With the keys, the sizes stand beside the two buttons: the field,
      // the keys and the buttons are then all in view in the smallest
      // window, for who cannot scroll.
      actionsAlignment: widget.screenKeyboard
          ? MainAxisAlignment.spaceBetween
          : null,
      actions: widget.screenKeyboard
          ? [
              _sizeChoice(label: 'Taille'),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _cancelButton(),
                  const SizedBox(width: 8),
                  _confirmButton(),
                ],
              ),
            ]
          : [_cancelButton(), _confirmButton()],
    ),
  );

  Widget _sizeChoice({String label = 'Taille des lettres'}) => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(label),
      SizeChoiceControl(
        keyPrefix: 'textDialogSize',
        value: _size,
        what: 'du texte',
        onChanged: (size) => setState(() {
          _size = size;
          _problem = null;
        }),
      ),
    ],
  );

  Widget _cancelButton() => TextButton(
    key: const Key('cancelText'),
    style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
    onPressed: () => Navigator.pop(context),
    child: const Text('Annuler'),
  );

  Widget _confirmButton() => FilledButton(
    key: const Key('confirmText'),
    style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
    onPressed: _text == null ? null : _confirm,
    child: Text(widget.editing ? 'Changer le texte' : 'Poser le texte'),
  );
}
