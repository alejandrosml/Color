// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/size_choice.dart';
import 'package:edupaint_flutter_study/text_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('typed characters are normalized to the form stored by the core', () {
    expect(normalizeTextInput('Bonjour'), 'Bonjour');
    expect(normalizeTextInput('  marge gardée'), '  marge gardée');
    expect(normalizeTextInput('fin coupée   '), 'fin coupée');
    // Every kind of line end becomes one line feed.
    expect(normalizeTextInput('a\r\nb\rc\nd e f'), 'a\nb\nc\nd\ne\nf');
    expect(normalizeTextInput('a\r\n\r\nb'), 'a\n\nb');
    expect(normalizeTextInput('tab\tulation'), 'tab ulation');
    // Controls, a deletion character and non-characters disappear.
    expect(
      normalizeTextInput('a\u0000b\u0007c\u001bd\u007fe\u0085f'),
      'abcdef',
    );
    expect(normalizeTextInput('x￾y￿z'), 'xyz');
    // An unpaired surrogate cannot be stored as UTF-8.
    expect(normalizeTextInput('a${String.fromCharCode(0xd800)}b'), 'ab');
    expect(normalizeTextInput('Été 🎨 cœur'), 'Été 🎨 cœur');
    // Empty lines around the text go; those inside it stay.
    expect(normalizeTextInput('\n\n  \nun\n\ndeux  \n \n'), 'un\n\ndeux');
  });

  test('nothing visible means no text at all', () {
    for (final empty in ['', ' ', '\n', ' \n\t \r\n', '\u00a0', '\u0000']) {
      expect(normalizeTextInput(empty), isNull, reason: jsonEncode(empty));
    }
  });

  test('normalized text never exceeds the limits of the core', () {
    final long = normalizeTextInput('é' * 5000)!;
    expect(utf8.encode(long).length, lessThanOrEqualTo(maxTextBytes));
    expect(utf8.encode(long).length, maxTextBytes);
    expect(long, 'é' * 1024);
    // A character is kept whole or not at all.
    final mixed = normalizeTextInput('a${'🎨' * 1000}')!;
    expect(utf8.encode(mixed).length, lessThanOrEqualTo(maxTextBytes));
    expect(mixed, 'a${'🎨' * 511}');
    final lines = normalizeTextInput(List.filled(50, 'x').join('\n'))!;
    expect(lines.split('\n'), hasLength(maxTextLines));
    // Cutting never leaves a dangling line end or continues after the cut.
    final cut = normalizeTextInput('${'a' * 2047}\nb\nc')!;
    expect(cut, 'a' * 2047);
  });

  test('layout gives the box that the core stores and exports', () {
    final one = TextLayout('abc', size: 40, rgb: 0x112233);
    expect(one.height, closeTo(48, 1e-9));
    expect(one.width, greaterThan(0));
    final two = TextLayout('abc\nabcdef', size: 40, rgb: 0x112233);
    expect(two.height, closeTo(96, 1e-9));
    expect(two.width, closeTo(one.width * 2, .01));
    expect([one.lineCount, two.lineCount], [1, 2]);
    expect(two.lineWidths, [closeTo(one.width, .01), closeTo(two.width, .01)]);
    final large = TextLayout('abc', size: 80, rgb: 0x112233);
    expect(large.width, closeTo(one.width * 2, .01));
    expect(() => TextLayout('abc', size: 3, rgb: 0), throwsArgumentError);
    expect(() => TextLayout('abc', size: 2049, rgb: 0), throwsArgumentError);
    expect(
      () => TextLayout('abc', size: double.nan, rgb: 0),
      throwsArgumentError,
    );
  });

  test('a text box starts at the click and is pushed back onto the page', () {
    final layout = TextLayout('abc', size: 40, rgb: 0);
    final inside = textBoxAt(
      const DocumentPoint(100, 200),
      layout,
      pageWidth: 1200,
      pageHeight: 800,
    )!;
    expect([inside.first.x, inside.first.y], [100, 200]);
    expect(inside.second.x, closeTo(100 + layout.width, 1e-9));
    expect(inside.second.y, closeTo(248, 1e-9));
    final pushed = textBoxAt(
      const DocumentPoint(1195, 795),
      layout,
      pageWidth: 1200,
      pageHeight: 800,
    )!;
    expect(pushed.second.x, closeTo(1200, 1e-9));
    expect(pushed.second.y, closeTo(800, 1e-9));
    expect(pushed.first.x, closeTo(1200 - layout.width, 1e-9));
    expect(
      textBoxAt(
        const DocumentPoint(0, 0),
        layout,
        pageWidth: layout.width - 1,
        pageHeight: 800,
      ),
      isNull,
    );
    expect(
      textBoxAt(
        const DocumentPoint(0, 0),
        layout,
        pageWidth: 1200,
        pageHeight: 47,
      ),
      isNull,
    );
  });

  test('size choices follow the sheet and stay inside the core limits', () {
    expect(
      [
        for (final size in ObjectSize.values)
          textSizeFor(size, width: 1200, height: 800),
      ],
      [32, 56, 96],
    );
    expect(
      [
        for (final size in ObjectSize.values)
          stampSizeFor(size, width: 1200, height: 800),
      ],
      [90, 150, 240],
    );
    // A portrait sheet uses its shorter side; a large photo scales up.
    expect(textSizeFor(ObjectSize.medium, width: 800, height: 1200), 56);
    expect(
      textSizeFor(ObjectSize.medium, width: 4096, height: 4096),
      closeTo(286.72, 1e-9),
    );
    expect(textSizeFor(ObjectSize.small, width: 16, height: 16), minTextSize);
    expect(
      textSizeFor(ObjectSize.large, width: 16384, height: 16384),
      closeTo(1966.08, 1e-9),
    );
    // A stamp is never larger than the sheet itself.
    expect(
      stampSizeFor(ObjectSize.large, width: 4, height: 100),
      closeTo(1.2, 1e-9),
    );
    expect(stampSizeFor(ObjectSize.large, width: 1200, height: 100), 30);
    expect(nearestTextSize(56, width: 1200, height: 800), ObjectSize.medium);
    expect(nearestTextSize(40, width: 1200, height: 800), ObjectSize.small);
    expect(nearestTextSize(500, width: 1200, height: 800), ObjectSize.large);
    expect(ObjectSize.values.map((size) => size.label), [
      'Petit',
      'Moyen',
      'Grand',
    ]);
  });
}
