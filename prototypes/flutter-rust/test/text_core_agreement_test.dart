// SPDX-License-Identifier: MIT
// What the interface accepts, cuts and announces about a text must be what
// the core accepts and stores. Real Rust documents: no native function is
// faked. Found by the independent review of Color 0.7.0.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/text_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  // Whether the core takes [text] as the characters of a text object.
  bool coreAccepts(RustDocument document, String text) {
    try {
      document.addText(
        const DocumentPoint(10, 10),
        const DocumentPoint(200, 100),
        text: text,
        rgb: 0,
        size: 20,
      );
      return true;
    } on RustCoreException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  test('a character leaves a mark for the interface exactly when it does for the core', () {
    final document = RustDocument();
    try {
      // Both ends of every range of the two tables, their neighbours, and
      // ordinary characters around them.
      const edges = [
        0x09, 0x0d, 0x20, 0x21, 0x41, 0x85, 0xa0, 0xa1, 0xac, 0xad, 0xae, //
        0x34e, 0x34f, 0x350, 0x61b, 0x61c, 0x61d, 0x115e, 0x115f, 0x1160,
        0x1161, 0x1680, 0x1681, 0x17b3, 0x17b4, 0x17b5, 0x17b6, 0x180a,
        0x180b, 0x180f, 0x1810, 0x1fff, 0x2000, 0x200a, 0x200b, 0x200f,
        0x2010, 0x2027, 0x2028, 0x2029, 0x202a, 0x202e, 0x202f, 0x2030,
        0x205e, 0x205f, 0x2060, 0x206f, 0x2070, 0x2fff, 0x3000, 0x3001,
        0x3163, 0x3164, 0x3165, 0xfdff, 0xfe00, 0xfe0f, 0xfe10, 0xfefe,
        0xfeff, 0xff00, 0xff9f, 0xffa0, 0xffa1, 0xffef, 0xfff0, 0xfff8,
        0xfff9, 0x1bc9f, 0x1bca0, 0x1bca3, 0x1bca4, 0x1d172, 0x1d173,
        0x1d17a, 0x1d17b, 0xdffff, 0xe0000, 0xe0fff, 0xe1000, 0x1f3a8,
      ];
      for (final rune in edges) {
        final character = String.fromCharCode(rune);
        // Line ends and tabs are rewritten by the interface before the
        // core sees them: they are compared as what they become.
        final asStored = rune == 0x09 || (rune >= 0x0a && rune <= 0x0d)
            ? ' '
            : rune == 0x85 || rune == 0x2028 || rune == 0x2029
            ? ' '
            : character;
        expect(
          leavesAMark(rune),
          coreAccepts(document, asStored),
          reason: 'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}',
        );
        // What the interface would send for it alone is never refused.
        final normalized = normalizeTextInput(character);
        if (normalized != null) {
          expect(coreAccepts(document, normalized), isTrue, reason: '$rune');
        }
      }
      // A sample across the whole range, the same question each time.
      final random = math.Random(20261003);
      for (var round = 0; round < 3000; round++) {
        var rune = random.nextInt(0x110000);
        if (rune >= 0xd800 && rune <= 0xdfff) rune = 0x41;
        if (rune < 0x20 || (rune >= 0x7f && rune <= 0x9f)) continue;
        // Never sent: the interface drops them, the core refuses them.
        if (rune == 0x2028 || rune == 0x2029) continue;
        if (rune == 0xfffe || rune == 0xffff) continue;
        expect(
          leavesAMark(rune),
          coreAccepts(document, String.fromCharCode(rune)),
          reason: 'U+${rune.toRadixString(16)}',
        );
      }
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('nothing that shows nothing becomes a text', () {
    for (final empty in ['﻿', '​​', ' ­‍ ', '⁠\n️', '\u{e0001}']) {
      expect(normalizeTextInput(empty), isNull, reason: jsonEncode(empty));
    }
    // With something to see beside them, they stay where they were typed.
    expect(normalizeTextInput('a‍b'), 'a‍b');
    expect(normalizeTextInput('🏳️'), '🏳️');
  });

  test(
    'a byte-order mark never separates the cached text from the stored one',
    () {
      // The interface drops it from what is typed or pasted.
      expect(normalizeTextInput('﻿Bonjour'), 'Bonjour');
      expect(normalizeTextInput('Bon﻿jour'), 'Bonjour');
      final document = RustDocument();
      try {
        // A project made elsewhere may hold one: the cache says what the
        // core stores, and confirming the same words is not a change.
        document.addText(
          const DocumentPoint(10, 10),
          const DocumentPoint(200, 100),
          text: '﻿Bonjour',
          rgb: 0,
          size: 20,
        );
        final cached = document.strokes.single.text!;
        expect(cached, '﻿Bonjour');
        expect(document.exportSvg(), contains('﻿Bonjour'));
        expect(
          document.setText(
            0,
            const DocumentPoint(10, 10),
            const DocumentPoint(200, 100),
            text: cached,
            rgb: 0,
            size: 20,
          ),
          isFalse,
        );
        expect(document.undoCount, 1);
        final reopened = RustDocument.fromProject(document.exportProject());
        try {
          expect(reopened.strokes.single.text, '﻿Bonjour');
          expect(
            () => RenderedElement(reopened.strokes.single),
            returnsNormally,
          );
        } finally {
          reopened.dispose();
        }
        // Alone, it shows nothing: the core refuses it as it refuses spaces.
        expect(coreAccepts(document, '﻿'), isFalse);
        expect(document.count, 1);
      } finally {
        document.dispose();
      }
    },
    skip: !available,
  );

  test('the limits of a text are announced before anything is cut', () {
    final forty = List.generate(40, (i) => 'mot ${i + 1}').join('\n');
    expect(textExceedsLimits(forty), isTrue);
    // What normalization would do alone: thirty-two lines, the rest gone.
    expect(normalizeTextInput(forty)!.split('\n').last, 'mot 32');
    final thirtyTwo = List.generate(32, (i) => 'mot ${i + 1}').join('\n');
    expect(textExceedsLimits(thirtyTwo), isFalse);
    // Empty lines around the text do not count: they are tidied away.
    expect(textExceedsLimits('\n\n$thirtyTwo\n\n\n'), isFalse);
    expect(textExceedsLimits('é' * 1024), isFalse);
    expect(textExceedsLimits('é' * 1025), isTrue);
    // Which of the two it is decides what the dialog says.
    expect(textExcess(forty), TextExcess.lines);
    expect(textExcess('é' * 1025), TextExcess.length);
    expect(textExcess(thirtyTwo), isNull);
    expect(textExceedsLimits('a\r\nb'), isFalse);
    expect(textExceedsLimits(''), isFalse);
  });

  test('lines wider than the sheet are broken between words, others kept', () {
    // The test font: every character is a square as wide as the size.
    String? wrap(String text, {double width = 400}) =>
        wrapTextToWidth(text, size: 40, maxWidth: width);
    expect(wrap('un deux'), 'un deux');
    expect(wrap('un deux trois quatre'), 'un deux\ntrois\nquatre');
    // Exactly as wide as the sheet: not broken.
    expect(wrap('abcde fghi'), 'abcde fghi');
    expect(wrap('abcde fghij'), 'abcde\nfghij');
    // A line that fits is left exactly as typed, spaces included.
    expect(wrap('a  b\nun deux trois quatre'), 'a  b\nun deux\ntrois\nquatre');
    // Several spaces at a break are dropped; inside a line they stay.
    expect(wrap('a  b cdefgh   ij'), 'a  b\ncdefgh\nij');
    // A word wider than a whole line is cut, as late as possible.
    expect(
      wrap('abcdefghijklmnopqrstuvwxyz'),
      'abcdefghij\nklmnopqrst\nuvwxyz',
    );
    expect(wrap('ab abcdefghijklm'), 'ab\nabcdefghij\nklm');
    // Never in the middle of a character made of several code units.
    expect(wrap('🎨🎨🎨', width: 80), '🎨🎨\n🎨');
    expect(wrap('ééé', width: 80), 'éé\né');
    // Not even one character fits.
    expect(wrap('abc', width: 30), isNull);
    expect(wrap(''), '');
  });

  test('a placed text stands whole on the sheet, or is refused', () {
    PlacedText? place(
      String text, {
      double size = 40,
      double x = 0,
      double y = 0,
    }) => placeText(
      text,
      size: size,
      anchor: DocumentPoint(x, y),
      pageWidth: 400,
      pageHeight: 240,
    );
    // 48 units a line: five lines stand on 240 units, six do not.
    final five = place('un deux trois quatre cinq six sept huit')!;
    expect(five.text.split('\n'), hasLength(5));
    expect(five.second.y - five.first.y, closeTo(240, 1e-9));
    expect(five.first.y, 0);
    expect(place('un deux trois quatre cinq six sept huit neuf dix'), isNull);
    // Pushed back onto the sheet, as close to the anchor as possible.
    final pushed = place('abc', x: 390, y: 230)!;
    expect(pushed.text, 'abc');
    expect(pushed.second.x, closeTo(400, 1e-9));
    expect(pushed.second.y, closeTo(240, 1e-9));
    expect(pushed.first.x, closeTo(280, 1e-9));
    // Small letters: a long line broken once stands easily.
    expect(place('x ' * 60, size: 4)!.text.split('\n'), hasLength(2));
    final many = placeText(
      List.filled(40, 'abcdefghijkl').join(' '),
      size: 40,
      anchor: const DocumentPoint(0, 0),
      pageWidth: 480,
      pageHeight: 16384,
    );
    expect(many, isNull, reason: 'forty lines once broken');
    // What is placed is accepted by the core as it is.
    if (available) {
      final document = RustDocument(width: 400, height: 240);
      try {
        document.addText(
          five.first,
          five.second,
          text: five.text,
          rgb: 0,
          size: 40,
        );
        expect(document.strokes.single.text, five.text);
      } finally {
        document.dispose();
      }
    }
  });

  test('a layer identifier beyond the sixteen is refused before the core', () {
    final document = RustDocument();
    try {
      document.addLayer();
      document.addStroke(const [DocumentPoint(1, 1)], rgb: 0, width: 2);
      final layer = document.strokes.single.layer;
      // 2^32 would keep its low bits in a 32-bit parameter: layer 0.
      for (final id in [0x100000000, 0x100000001, maxLayers, -1]) {
        expect(() => document.setActiveLayer(id), throwsArgumentError);
        expect(() => document.setObjectLayer(0, id), throwsArgumentError);
      }
      expect(document.activeLayer, layer);
      expect(document.strokes.single.layer, layer);
      expect(document.undoCount, 2);
    } finally {
      document.dispose();
    }
  }, skip: !available);

  test('a refusal of the core is worded for any command', () {
    expect(
      const RustCoreException('l’ajout du calque', -1).toString(),
      allOf(contains('l’ajout du calque'), isNot(contains('trait'))),
    );
    expect(
      const RustCoreException('l’ajout du texte', -2).toString(),
      contains('Mémoire insuffisante'),
    );
  });
}
