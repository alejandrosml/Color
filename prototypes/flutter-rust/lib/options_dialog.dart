// SPDX-License-Identifier: MIT
// « Options » : what an adult chooses for the child who draws. Every change
// applies at once, behind the dialog, and is kept for the next launches.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'studio_colors.dart';
import 'studio_options.dart';
import 'platform_words.dart';

/// How the options were left: closed, or towards one of the two dialogs
/// that the simplest interface no longer shows in its header.
enum OptionsExit { closed, help, about }

Future<OptionsExit> showOptionsDialog(
  BuildContext context, {
  required StudioOptionsStore store,
}) async =>
    await showDialog<OptionsExit>(
      context: context,
      builder: (_) => OptionsDialog(store: store),
    ) ??
    OptionsExit.closed;

class OptionsDialog extends StatefulWidget {
  const OptionsDialog({super.key, required this.store});
  final StudioOptionsStore store;

  /// For this long after it opens the dialog hears neither the pointer nor
  /// the keyboard. It opens under the hand that has just pressed « Entrer »
  /// at the door: the second click of a double click would switch whatever
  /// lies there, and Entrée held a moment too long would close it at once.
  static const settling = Duration(milliseconds: 400);

  @override
  State<OptionsDialog> createState() => _OptionsDialogState();
}

class _OptionsDialogState extends State<OptionsDialog> {
  StudioOptionsStore get store => widget.store;
  bool _ready = false;
  Timer? _settling;

  @override
  void initState() {
    super.initState();
    _settling = Timer(OptionsDialog.settling, () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _settling?.cancel();
    super.dispose();
  }

  static const _heading = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

  Widget _level(InterfaceLevel level, StudioOptions options) {
    final selected = options.level == level;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // One control for a screen reader: its name, its sentence, and
      // whether it is the one chosen among the three.
      child: MergeSemantics(
        child: Semantics(
          inMutuallyExclusiveGroup: true,
          checked: selected,
          child: Material(
            color: selected ? studioSelected : studioSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: selected ? studioGreen : studioLine,
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: Key('level-${level.name}'),
              onTap: () => store.change(options.copyWith(level: level)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selected ? studioGreen : studioInk,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              level.label,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              level.description,
                              style: const TextStyle(fontSize: 13, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _switch({
    required Key key,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile(
    key: key,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    title: Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 13, height: 1.3)),
    value: value,
    onChanged: onChanged,
  );

  @override
  Widget build(BuildContext context) => Focus(
    // Keys are swallowed while the dialog settles, wherever the focus is;
    // and a key held down presses nothing here, then or later: Entrée that
    // answered the door and is still held must not close what it opened.
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) => !_ready || event is KeyRepeatEvent
        ? KeyEventResult.handled
        : KeyEventResult.ignored,
    child: AbsorbPointer(absorbing: !_ready, child: _dialog(context)),
  );

  Widget _dialog(BuildContext context) => ValueListenableBuilder<StudioOptions>(
    valueListenable: store,
    builder: (context, options, _) => AlertDialog(
      key: const Key('optionsDialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      title: const Text('Options'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('L’interface', style: _heading),
            const SizedBox(height: 8),
            for (final level in InterfaceLevel.values) _level(level, options),
            const SizedBox(height: 8),
            const Text('Ce que Color propose', style: _heading),
            _switch(
              key: const Key('optionPrinting'),
              title: 'Imprimer',
              subtitle: 'Le bouton Imprimer, son menu et son raccourci.',
              value: options.printing,
              onChanged: (value) =>
                  store.change(options.copyWith(printing: value)),
            ),
            _switch(
              key: const Key('optionSounds'),
              title: 'Sons',
              subtitle: 'De petits sons répondent à ce que fait l’enfant.',
              value: options.sounds,
              onChanged: (value) =>
                  store.change(options.copyWith(sounds: value)),
            ),
            const SizedBox(height: 8),
            const Text('Accessibilité', style: _heading),
            _switch(
              key: const Key('optionHoldFree'),
              title: 'Dessiner sans tenir le bouton',
              subtitle: forTouch(
                'Un clic commence, un autre clic arrête : pour tracer au pinceau, pour déplacer un élément ou la feuille.',
              ),
              value: options.holdFree,
              onChanged: (value) =>
                  store.change(options.copyWith(holdFree: value)),
            ),
            _switch(
              key: const Key('optionScreenKeyboard'),
              title: 'Clavier à l’écran',
              subtitle: forTouch('Des touches à cliquer pour écrire un texte.'),
              value: options.screenKeyboard,
              onChanged: (value) =>
                  store.change(options.copyWith(screenKeyboard: value)),
            ),
            const SizedBox(height: 8),
            const Text('Pour l’adulte', style: _heading),
            _switch(
              key: const Key('optionGuarded'),
              title: 'Protéger les options par un calcul',
              subtitle: 'Une multiplication à résoudre avant d’ouvrir les options : les plus petits n’y entrent pas par hasard.',
              value: options.guarded,
              onChanged: (value) =>
                  store.change(options.copyWith(guarded: value)),
            ),
            if (store.unsaved)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Ces choix n’ont pas pu être gardés sur cet ordinateur : ils valent jusqu’à la fermeture de Color.',
                  key: Key('optionsUnsaved'),
                  style: TextStyle(fontSize: 13, color: studioWarning),
                ),
              ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(16),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          key: const Key('optionsHelp'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.pop(context, OptionsExit.help),
          child: const Text('Comment faire ?'),
        ),
        TextButton(
          key: const Key('optionsAbout'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.pop(context, OptionsExit.about),
          child: const Text('À propos'),
        ),
        FilledButton(
          key: const Key('closeOptions'),
          autofocus: true,
          style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
          onPressed: () => Navigator.pop(context, OptionsExit.closed),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}
