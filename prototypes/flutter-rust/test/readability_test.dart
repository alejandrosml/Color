// SPDX-License-Identifier: MIT
// Measured readability of the studio's own texts and marks. The ratios are
// the WCAG 2 contrast ratios: 4.5 to 1 for small text, 3 to 1 for the marks
// that identify a control. A measure of colours, not a test with readers.
import 'dart:io';
import 'dart:math' as math;

import 'package:edupaint_flutter_study/french.dart';
import 'package:edupaint_flutter_study/studio_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double contrast(Color a, Color b) {
  final first = _luminance(a);
  final second = _luminance(b);
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('the contrast measure agrees with known pairs', () {
    expect(contrast(Colors.black, Colors.white), closeTo(21, .001));
    expect(contrast(Colors.white, Colors.white), 1);
    // The grey #767676 is the classic 4.54 to 1 on white.
    expect(contrast(const Color(0xff767676), Colors.white), closeTo(4.54, .01));
  });

  test('every small text of the studio reaches 4.5 to 1 on its surface', () {
    expect(studioTextOnSurface, hasLength(greaterThanOrEqualTo(14)));
    for (final (name, text, surface) in studioTextOnSurface) {
      expect(
        contrast(text, surface),
        greaterThanOrEqualTo(4.5),
        reason: '$name : ${contrast(text, surface).toStringAsFixed(2)}',
      );
    }
  });

  test('the marks that identify a control reach 3 to 1', () {
    for (final (name, mark, surface) in studioMarkOnSurface) {
      expect(
        contrast(mark, surface),
        greaterThanOrEqualTo(3),
        reason: '$name : ${contrast(mark, surface).toStringAsFixed(2)}',
      );
    }
  });

  test('text colours are named: no panel writes with a colour of its own', () {
    // A literal colour inside a TextStyle would escape the table above. The
    // colour of a drawn text is computed from the drawing: it is not literal.
    final literal = RegExp(r'color:\s*(const\s+)?Color\(0x[0-9a-fA-F]{8}\)');
    var styles = 0;
    for (final file in Directory('lib').listSync().whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in 'TextStyle('.allMatches(source)) {
        // The arguments of this TextStyle, up to its closing parenthesis.
        var depth = 1;
        var end = match.end;
        while (depth > 0 && end < source.length) {
          final character = source[end++];
          if (character == '(') depth++;
          if (character == ')') depth--;
        }
        styles++;
        expect(
          literal.hasMatch(source.substring(match.end, end)),
          isFalse,
          reason: '${file.path} gives a TextStyle a literal colour',
        );
      }
    }
    expect(styles, greaterThan(40));
  });

  testWidgets('the studio writes its captions with the measured colours', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start(size: const Size(1280, 820));
    Color? colorOf(Finder finder) => tester.widget<Text>(finder).style?.color;
    expect(colorOf(find.text('OUTILS')), studioCaption);
    expect(colorOf(find.text('MA FEUILLE')), studioSheetTitle);
    expect(colorOf(find.text('1200 × 800 unités')), studioSheetCaption);
    expect(colorOf(find.text('Toute la feuille')), studioSheetCaption);
    expect(colorOf(find.text('PINCEAU')), studioInspectorCaption);
    expect(colorOf(find.text('UNE PETITE IDÉE')), studioIdeaTitle);
    expect(
      colorOf(find.textContaining('0 élément · nouvelle feuille')),
      studioDocumentCaption,
    );
    expect(
      colorOf(find.textContaining('Nouvelle feuille · récupération')),
      studioStatusText,
    );
    expect(
      colorOf(find.textContaining('Un petit atelier pour les grandes idées')),
      studioHelpText,
    );
    await studio.finish();
  }, skip: !available);

  test('French counts: the plural starts at two', () {
    expect(elementCount(0), '0 élément');
    expect(elementCount(1), '1 élément');
    expect(elementCount(2), '2 éléments');
    expect(elementCount(10000), '10000 éléments');
  });
}
