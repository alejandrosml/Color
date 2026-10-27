// SPDX-License-Identifier: MIT
// What changes with the device: a computer is clicked with a mouse, a tablet
// or a telephone is touched with a finger.
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Replaces what [touchFirst] reads from the system, in tests only.
@visibleForTesting
bool? debugTouchFirstOverride;

/// Color is used with a finger first: on iPhone, iPad and Android. Read
/// from the system this program runs on, not from the platform Flutter
/// imitates in a test, which is Android there.
bool get touchFirst =>
    debugTouchFirstOverride ?? (Platform.isIOS || Platform.isAndroid);

/// « cet ordinateur », or « cet appareil » for a tablet or a telephone.
String get thisDevice => touchFirst ? 'cet appareil' : 'cet ordinateur';

// Words of the mouse, and what a finger does instead: the longer ones first.
const _touchWords = [
  ('Clique sur', 'Touche'),
  ('clique sur', 'touche'),
  ('Clique-le', 'Touche-le'),
  ('clique-le', 'touche-le'),
  ('cliquer', 'toucher'),
  ('cliquée', 'touchée'),
  ('Clique', 'Touche'),
  ('clique', 'touche'),
  ('deux clics', 'deux appuis'),
  ('Un clic', 'Un appui'),
  ('un autre clic', 'un autre appui'),
  ('Souris ou stylet', 'Doigt ou stylet'),
];

/// [text] as a person with a finger reads it. On a computer it is given
/// back unchanged. On a tablet or a telephone « clique » becomes
/// « touche », and the sentences about keys a finger does not have —
/// Échap, Maj — are left out.
String forTouch(String text) {
  if (!touchFirst) return text;
  final sentences = RegExp(r'[^.!?]+[.!?]*\s*').allMatches(text);
  final kept = [
    for (final sentence in sentences)
      if (!sentence[0]!.contains('Échap') &&
          !RegExp(r'(^|[^A-Za-zÀ-ÿ])Maj([^A-Za-zÀ-ÿ]|$)')
              .hasMatch(sentence[0]!))
        sentence[0]!,
  ];
  var result = kept.join().trim();
  if (result.isEmpty) result = text;
  for (final (mouse, finger) in _touchWords) {
    result = result.replaceAll(mouse, finger);
  }
  return result;
}
