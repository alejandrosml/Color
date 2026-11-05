// SPDX-License-Identifier: MIT
// What changes with the device: a computer is clicked with a mouse, a tablet
// or a telephone is touched with a finger.
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'language.dart';

/// Replaces what [touchFirst] reads from the system, in tests only.
@visibleForTesting
bool? debugTouchFirstOverride;

/// Color is used with a finger first: on iPhone, iPad and Android. Read
/// from the system this program runs on, not from the platform Flutter
/// imitates in a test, which is Android there.
bool get touchFirst =>
    debugTouchFirstOverride ?? (Platform.isIOS || Platform.isAndroid);

/// « cet ordinateur », or « cet appareil » for a tablet or a telephone; in
/// English « this computer », « this device ».
String get thisDevice => inEnglish
    ? (touchFirst ? 'this device' : 'this computer')
    : (touchFirst ? 'cet appareil' : 'cet ordinateur');

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

// The same in English: a finger taps.
const _englishTouchWords = [
  ('Click', 'Tap'),
  ('click', 'tap'),
  ('clicked', 'tapped'),
  ('two clicks', 'two taps'),
  ('One click', 'One tap'),
  ('another click', 'another tap'),
  ('Mouse or stylus', 'Finger or stylus'),
];

/// [text] as a person with a finger reads it. On a computer it is given
/// back unchanged. On a tablet or a telephone « clique » becomes
/// « touche », « click » « tap », and the sentences about keys a finger does
/// not have — Échap, Maj, Esc, Shift — are left out.
String forTouch(String text) {
  if (!touchFirst) return text;
  final sentences = RegExp(r'[^.!?]+[.!?]*\s*').allMatches(text);
  final kept = [
    for (final sentence in sentences)
      if (!sentence[0]!.contains('Échap') &&
          !RegExp(r'(^|[^A-Za-zÀ-ÿ])(Maj|Esc|Shift)([^A-Za-zÀ-ÿ]|$)')
              .hasMatch(sentence[0]!))
        sentence[0]!,
  ];
  var result = kept.join().trim();
  if (result.isEmpty) result = text;
  // The longer phrases first, so that « two clicks » is not « two taps »
  // by halves; « clicked » before « click ».
  final words = inEnglish
      ? ([..._englishTouchWords]
          ..sort((a, b) => b.$1.length.compareTo(a.$1.length)))
      : _touchWords;
  for (final (mouse, finger) in words) {
    result = result.replaceAll(mouse, finger);
  }
  return result;
}
