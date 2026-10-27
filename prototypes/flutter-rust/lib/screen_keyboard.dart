// SPDX-License-Identifier: MIT
// A keyboard to click, for who writes with a pointer only. It types into a
// text field through its controller, where the caret is, and never takes
// the focus from that field: the caret stays in view while keys are pressed.
import 'package:flutter/material.dart';

import 'studio_colors.dart';
import 'studio_text.dart';
import 'text_layout.dart' show colorTextFontFamily;
import 'platform_words.dart';

/// Which keys the keyboard shows above its last row.
enum _Page { letters, accents, signs }

class ScreenKeyboard extends StatefulWidget {
  const ScreenKeyboard({
    super.key,
    required this.controller,
    required this.limit,
    this.onChanged,
  });

  /// The field that receives the characters.
  final TextEditingController controller;

  /// How many characters the field may hold: a key that would go beyond
  /// types nothing.
  final int limit;

  /// Called after a key changed the text while the field did not hold the
  /// focus. A field that holds it is told as by the keyboard of the computer,
  /// and calls its own `onChanged`.
  final VoidCallback? onChanged;

  /// Width of the ten keys of a row with their gaps.
  static const width = 10 * _keySize + 9 * _gap;
  static const _keySize = 48.0;
  static const _gap = 4.0;

  @override
  State<ScreenKeyboard> createState() => _ScreenKeyboardState();
}

class _ScreenKeyboardState extends State<ScreenKeyboard> {
  // The keys of a French keyboard, in its order. Every page has three rows
  // of ten keys, so that no key moves when the page changes.
  static const _letters = ['azertyuiop', 'qsdfghjklm', 'wxcvbn’-.,'];
  // The letters of French first, then those of first names from elsewhere.
  static const _accents = ['éèêëàâùûüç', 'îïôöœæÿ«»…', 'áíóúñãõäìò'];
  static const _signs = ['1234567890', '?!:;()+=♥★', '-×÷<>€%"/@'];

  var _page = _Page.letters;
  // Capitals for the next letter only, as on a telephone.
  var _capitals = false;
  TextEditingValue get _value => widget.controller.value;

  // Where the next character goes: the selection of the field, or its end
  // when the field was never clicked.
  TextSelection get _selection {
    final selection = _value.selection;
    return selection.isValid
        ? selection
        : TextSelection.collapsed(offset: _value.text.length);
  }

  // The field itself, when it is the one that holds the focus: a key then
  // types as the keyboard of the computer does, with the rules of the field,
  // and the caret is brought back into view.
  EditableTextState? get _field {
    final field = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    return field != null && field.widget.controller == widget.controller
        ? field
        : null;
  }

  void _replace(int start, int end, String with_) {
    final text = _value.text.replaceRange(start, end, with_);
    if (text.characters.length > widget.limit) return;
    final value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + with_.length),
    );
    final field = _field;
    if (field != null) {
      // The field tells its own listener.
      field.userUpdateTextEditingValue(value, SelectionChangedCause.keyboard);
      return;
    }
    widget.controller.value = value;
    widget.onChanged?.call();
  }

  void _type(String character) {
    final selection = _selection;
    _replace(selection.start, selection.end, character);
    if (_capitals) setState(() => _capitals = false);
  }

  void _erase() {
    final selection = _selection;
    if (!selection.isCollapsed) {
      _replace(selection.start, selection.end, '');
      return;
    }
    if (selection.start == 0) return;
    // One whole character, even when it is made of several code units.
    final before = _value.text.substring(0, selection.start).characters;
    final kept = before.skipLast(1).toString();
    _replace(kept.length, selection.start, '');
  }

  String _shown(String character) =>
      _capitals ? character.toUpperCase() : character;

  Widget _key({
    required Key key,
    required String spoken,
    required Widget child,
    required VoidCallback onPressed,
    double width = ScreenKeyboard._keySize,
    bool chosen = false,
  }) => SizedBox(
    width: width,
    height: ScreenKeyboard._keySize,
    child: OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(ScreenKeyboard._keySize),
        backgroundColor: chosen ? studioSelected : studioSurface,
        side: BorderSide(
          color: chosen ? studioGreen : studioLine,
          width: chosen ? 2 : 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: studioLabelStyle(
          context,
          18,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
      child: Semantics(
        label: spoken,
        selected: chosen ? true : null,
        excludeSemantics: true,
        child: child,
      ),
    ),
  );

  Widget _row(String characters) => Padding(
    padding: const EdgeInsets.only(bottom: ScreenKeyboard._gap),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (index, rune) in characters.runes.indexed) ...[
          if (index != 0) const SizedBox(width: ScreenKeyboard._gap),
          _key(
            key: Key('key-${_shown(String.fromCharCode(rune))}'),
            spoken:
                _spokenNames[String.fromCharCode(rune)] ??
                _shown(String.fromCharCode(rune)),
            onPressed: () => _type(_shown(String.fromCharCode(rune))),
            // In the letters of the sheet: the key shows what it will write,
            // and the font that comes with Color has every one of them.
            child: Text(
              _shown(String.fromCharCode(rune)),
              style: const TextStyle(fontFamily: colorTextFontFamily),
            ),
          ),
        ],
      ],
    ),
  );

  // What a screen reader says for the keys whose sign is not a word.
  static const _spokenNames = {
    '’': 'apostrophe',
    '-': 'trait d’union',
    '.': 'point',
    ',': 'virgule',
    '?': 'point d’interrogation',
    '!': 'point d’exclamation',
    ':': 'deux-points',
    ';': 'point-virgule',
    '(': 'parenthèse ouvrante',
    ')': 'parenthèse fermante',
    '+': 'plus',
    '=': 'égale',
    '♥': 'cœur',
    '★': 'étoile',
    '«': 'guillemet ouvrant',
    '»': 'guillemet fermant',
    '…': 'points de suspension',
    '×': 'multiplié par',
    '÷': 'divisé par',
    '<': 'plus petit que',
    '>': 'plus grand que',
    '€': 'euro',
    '%': 'pour cent',
    '"': 'guillemet droit',
    '/': 'barre oblique',
    '@': 'arobase',
  };

  Widget _pageKey(_Page page, String label, String spoken) => _key(
    key: Key('keys-${page.name}'),
    spoken: spoken,
    width: 64,
    chosen: _page == page,
    onPressed: () => setState(() => _page = page),
    child: Text(label, style: const TextStyle(fontSize: 14)),
  );

  // Keys are pressed with a pointer. A press on one of them is not a press
  // beside the field, and none of them takes the focus: the field keeps it,
  // with its caret.
  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    child: ExcludeFocus(
      child: Semantics(
        container: true,
        label: forTouch('Clavier à cliquer'),
        child: Column(
          key: const Key('screenKeyboard'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in switch (_page) {
              _Page.letters => _letters,
              _Page.accents => _accents,
              _Page.signs => _signs,
            })
              _row(row),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _key(
                  key: const Key('key-capitals'),
                  spoken: 'Majuscule pour la prochaine lettre',
                  chosen: _capitals,
                  onPressed: () => setState(() => _capitals = !_capitals),
                  child: const Icon(Icons.arrow_upward_rounded, size: 22),
                ),
                const SizedBox(width: ScreenKeyboard._gap),
                _pageKey(_Page.letters, 'abc', 'Les lettres'),
                const SizedBox(width: ScreenKeyboard._gap),
                _pageKey(_Page.accents, 'éàç', 'Les lettres accentuées'),
                const SizedBox(width: ScreenKeyboard._gap),
                _pageKey(_Page.signs, '123', 'Les chiffres et les signes'),
                const SizedBox(width: ScreenKeyboard._gap),
                _key(
                  key: const Key('key-space'),
                  spoken: 'Espace',
                  width: 132,
                  onPressed: () => _type(' '),
                  child: const Icon(Icons.space_bar_rounded, size: 24),
                ),
                const SizedBox(width: ScreenKeyboard._gap),
                _key(
                  key: const Key('key-newline'),
                  spoken: 'À la ligne',
                  width: 56,
                  onPressed: () => _type('\n'),
                  child: const Icon(Icons.keyboard_return_rounded, size: 22),
                ),
                const SizedBox(width: ScreenKeyboard._gap),
                _key(
                  key: const Key('key-erase'),
                  spoken: 'Effacer',
                  width: 56,
                  onPressed: _erase,
                  child: const Icon(Icons.backspace_outlined, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
