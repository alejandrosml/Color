// SPDX-License-Identifier: MIT
// Layout of text objects. The interface measures the characters with the
// bundled font and hands the resulting box to the core, which stores it; the
// same lines are painted on the sheet and in PNG exports. The core writes
// SVG baselines with the same line height and ascent share of this font, and
// every line is painted here on exactly that baseline.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart' show StringCharacters;

import 'rust_document.dart';

/// Bundled DejaVu Sans (font 0 of the project format), declared in pubspec.
const colorTextFontFamily = 'ColorSans';

/// Line height as a multiple of the text size, as in the core's SVG export.
const colorTextLineHeight = 1.2;

/// Distance from the top of a line to its baseline, as a multiple of the text
/// size: the line height shared in the font's own 1901:483 proportion, the
/// very expression of the core's SVG export.
const colorTextBaseline = colorTextLineHeight * 1901 / 2384;

/// A font a text may have: its family in pubspec, its name for the child,
/// and its metrics, the very ones of the core's SVG export (text.rs, FONTS):
/// the line height as a multiple of the size, and the distance from the top
/// of a line to its baseline, the line height shared between the font's
/// ascent and descent.
class TextFont {
  const TextFont(this.family, this.name, this.lineHeight, this.baseline);
  final String family;
  final String name;
  final double lineHeight;
  final double baseline;
}

/// Fonts 0 to 4 of the project format, in its order. What a font lacks of a
/// text is drawn with font 0.
const textFonts = <TextFont>[
  TextFont(
    colorTextFontFamily,
    'Bâton',
    colorTextLineHeight,
    colorTextBaseline,
  ),
  TextFont('ColorAtkinson', 'Lisible', 1.2, 1.2 * 950 / 1240),
  TextFont('ColorComic', 'Bande dessinée', 1.2, 1.2 * 900 / 1150),
  TextFont('ColorFredoka', 'Ronde', 1.2, 1.2 * 974 / 1210),
  // The school hand of France: its loops need the font's own line height.
  TextFont('ColorPlaywrite', 'Écriture', 2.852, 2.852 * 1927 / 2852),
];

// Unicode's Default_Ignorable_Code_Point: characters that a renderer shows
// as nothing when nothing else stands with them. The same table as the
// core's (text.rs): a text made only of them, and of white space, is refused
// there, so it must be « nothing » here too.
const _ignorable = [
  (0xad, 0xad),
  (0x34f, 0x34f),
  (0x61c, 0x61c),
  (0x115f, 0x1160),
  (0x17b4, 0x17b5),
  (0x180b, 0x180f),
  (0x200b, 0x200f),
  (0x202a, 0x202e),
  (0x2060, 0x206f),
  (0x3164, 0x3164),
  (0xfe00, 0xfe0f),
  (0xfeff, 0xfeff),
  (0xffa0, 0xffa0),
  (0xfff0, 0xfff8),
  (0x1bca0, 0x1bca3),
  (0x1d173, 0x1d17a),
  (0xe0000, 0xe0fff),
];

// Unicode's White_Space, the set of Rust's char::is_whitespace.
const _whiteSpace = [
  (0x09, 0x0d),
  (0x20, 0x20),
  (0x85, 0x85),
  (0xa0, 0xa0),
  (0x1680, 0x1680),
  (0x2000, 0x200a),
  (0x2028, 0x2029),
  (0x202f, 0x202f),
  (0x205f, 0x205f),
  (0x3000, 0x3000),
];

bool _within(List<(int, int)> ranges, int rune) =>
    ranges.any((range) => rune >= range.$1 && rune <= range.$2);

/// Whether a character leaves a mark by itself: neither white space nor one
/// of the characters that are shown as nothing. The core asks every text for
/// one such character.
bool leavesAMark(int rune) =>
    !_within(_whiteSpace, rune) && !_within(_ignorable, rune);

// Line ends become a single line feed, tabs become spaces, controls and the
// byte-order mark disappear, and the ends are tidied. No limit is applied.
List<String> _tidyLines(String raw) {
  final buffer = StringBuffer();
  var previousReturn = false;
  for (final rune in raw.runes) {
    final wasReturn = previousReturn;
    previousReturn = rune == 0x0d;
    if (rune == 0x0a) {
      if (!wasReturn) buffer.writeCharCode(0x0a);
    } else if (rune == 0x0d || rune == 0x2028 || rune == 0x2029) {
      buffer.writeCharCode(0x0a);
    } else if (rune == 0x09) {
      buffer.write(' ');
    } else if (rune < 0x20 ||
        (rune >= 0x7f && rune <= 0x9f) ||
        rune == 0xfeff ||
        rune == 0xfffe ||
        rune == 0xffff ||
        (rune >= 0xd800 && rune <= 0xdfff)) {
      // Dropped: controls, non-characters, unpaired surrogates, and the
      // byte-order mark that a pasted text may carry: it shows nothing and
      // the decoder of the characters read back would not return it.
    } else {
      buffer.writeCharCode(rune);
    }
  }
  var lines = buffer.toString().split('\n').map((line) => line.trimRight());
  lines = lines.skipWhile((line) => line.trim().isEmpty).toList().reversed;
  return lines
      .skipWhile((line) => line.trim().isEmpty)
      .toList()
      .reversed
      .toList();
}

/// Turns typed characters into the form stored by the core, or returns null
/// when nothing that leaves a mark remains. Line ends become a single line
/// feed, tabs become spaces, other control characters disappear and the ends
/// are tidied. The result is cut to the core's limits, never in the middle of
/// a character; [textExceedsLimits] tells beforehand whether it would be.
String? normalizeTextInput(String raw) {
  final kept = _tidyLines(raw);
  final result = StringBuffer();
  var bytes = 0;
  var count = 0;
  cut:
  for (final line in kept) {
    if (count == maxTextLines) break;
    if (count > 0) {
      if (bytes + 1 > maxTextBytes) break;
      result.writeCharCode(0x0a);
      bytes++;
    }
    for (final rune in line.runes) {
      final size = utf8.encode(String.fromCharCode(rune)).length;
      // Stop at the first character that does not fit: nothing after it.
      if (bytes + size > maxTextBytes) break cut;
      result.writeCharCode(rune);
      bytes += size;
    }
    count++;
  }
  final text = result.toString().trimRight();
  return text.runes.any(leavesAMark) ? text : null;
}

/// What a text has too much of to be kept whole.
enum TextExcess { lines, length }

/// Why [raw] cannot be kept whole, or null when it can: [normalizeTextInput]
/// would drop the end of such a text without a word.
TextExcess? textExcess(String raw) {
  final lines = _tidyLines(raw);
  if (lines.length > maxTextLines) return TextExcess.lines;
  if (utf8.encode(lines.join('\n')).length > maxTextBytes) {
    return TextExcess.length;
  }
  return null;
}

/// Whether [raw] holds more lines or more characters than a text may keep.
bool textExceedsLimits(String raw) => textExcess(raw) != null;

/// A laid-out text: its lines, ready to paint, and the size of its box.
class TextLayout {
  TextLayout._(this._lines, this.lineWidths, this.size, this.width, this.font);

  factory TextLayout(
    String text, {
    required double size,
    required int rgb,
    int font = 0,
  }) {
    if (!size.isFinite || size < minTextSize || size > maxTextSize) {
      throw ArgumentError('Taille de texte hors limites.');
    }
    if (font < 0 || font >= textFonts.length) {
      throw ArgumentError('Police inconnue.');
    }
    final face = textFonts[font];
    final lines = <Paragraph>[];
    final widths = <double>[];
    var widest = 0.0;
    for (final line in text.split('\n')) {
      final builder =
          ParagraphBuilder(
              ParagraphStyle(
                fontFamily: face.family,
                fontSize: size,
                height: face.lineHeight,
                textDirection: TextDirection.ltr,
              ),
            )
            ..pushStyle(
              TextStyle(
                color: Color(0xff000000 | rgb),
                fontFamily: face.family,
                fontFamilyFallback: const [colorTextFontFamily],
                fontSize: size,
                height: face.lineHeight,
              ),
            )
            ..addText(line);
      final paragraph = builder.build()
        ..layout(const ParagraphConstraints(width: double.infinity));
      final width = paragraph.longestLine.isFinite
          ? paragraph.longestLine
          : 0.0;
      lines.add(paragraph);
      widths.add(width);
      widest = math.max(widest, width);
    }
    // A box is never empty: a line of spaces still occupies a thin column.
    return TextLayout._(
      List.unmodifiable(lines),
      List.unmodifiable(widths),
      size,
      widest > 0 ? widest : size * .25,
      font,
    );
  }

  final List<Paragraph> _lines;

  /// Font 0 to 4 of the project format.
  final int font;

  /// Line height as a multiple of the size, for this font.
  double get lineHeight => textFonts[font].lineHeight;

  /// Width of every line, in the order of the text.
  final List<double> lineWidths;
  final double size;
  final double width;

  int get lineCount => _lines.length;

  /// Exactly what the core stores and writes: a whole number of lines.
  double get height => lineCount * lineHeight * size;

  /// Where the baseline of a line lies under the top of the box.
  double baselineOf(int line) =>
      (line * lineHeight + textFonts[font].baseline) * size;

  /// Paints the lines from the top-left corner of the box. Every line is
  /// placed by its own baseline: the engine rounds the height of a line to a
  /// whole number and makes a line taller when it borrows another font, and
  /// neither may move the lines that follow away from where an SVG export
  /// writes them.
  void paint(Canvas canvas, Offset topLeft) {
    for (final (index, paragraph) in _lines.indexed) {
      if (lineWidths[index] <= 0) continue;
      canvas.drawParagraph(
        paragraph,
        Offset(
          topLeft.dx,
          topLeft.dy + baselineOf(index) - paragraph.alphabeticBaseline,
        ),
      );
    }
  }
}

/// Opposite corners of a text box whose top-left corner is as close as
/// possible to [anchor] while the whole box stays on the page. Null when the
/// text is larger than the page.
({DocumentPoint first, DocumentPoint second})? textBoxAt(
  DocumentPoint anchor,
  TextLayout layout, {
  required double pageWidth,
  required double pageHeight,
}) {
  if (layout.width > pageWidth || layout.height > pageHeight) return null;
  final left = anchor.x.clamp(0.0, pageWidth - layout.width).toDouble();
  final top = anchor.y.clamp(0.0, pageHeight - layout.height).toDouble();
  return (
    first: DocumentPoint(left, top),
    second: DocumentPoint(left + layout.width, top + layout.height),
  );
}

double _widthOf(String line, double size, [int font = 0]) => line.isEmpty
    ? 0
    : TextLayout(line, size: size, rgb: 0, font: font).lineWidths.single;

// The longest beginning of [word] that fits, at least one character of it.
String _headThatFits(String word, double size, double maxWidth, int font) {
  final characters = word.characters.toList();
  var low = 1;
  var high = characters.length;
  while (low < high) {
    final middle = (low + high + 1) ~/ 2;
    if (_widthOf(characters.take(middle).join(), size, font) <= maxWidth) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  return characters.take(low).join();
}

/// Breaks the lines of [text] that are wider than [maxWidth] at [size]:
/// between words where it can, inside a word that is wider than a whole line
/// by itself. Lines that fit are left exactly as they are. Null when not even
/// one character fits in the width.
String? wrapTextToWidth(
  String text, {
  required double size,
  required double maxWidth,
  int font = 0,
}) {
  final result = <String>[];
  for (final line in text.split('\n')) {
    if (_widthOf(line, size, font) <= maxWidth) {
      result.add(line);
      continue;
    }
    var current = '';
    for (var word in line.split(' ')) {
      // Several spaces in a row give empty words: they keep their place
      // inside a line and are dropped where a line is broken.
      while (true) {
        final candidate = current.isEmpty ? word : '$current $word';
        if (_widthOf(candidate, size, font) <= maxWidth) {
          current = candidate;
          break;
        }
        if (current.isNotEmpty) {
          result.add(current.trimRight());
          current = '';
          continue;
        }
        // The word alone is wider than a line: cut it.
        final head = _headThatFits(word, size, maxWidth, font);
        if (_widthOf(head, size, font) > maxWidth) return null;
        result.add(head);
        word = word.substring(head.length);
        if (word.isEmpty) break;
      }
    }
    if (current.trimRight().isNotEmpty) result.add(current.trimRight());
  }
  return result.join('\n');
}

/// A text ready to stand on a sheet: its characters, with the line breaks it
/// needed, and the corners of its box.
class PlacedText {
  const PlacedText(this.text, this.first, this.second);
  final String text;
  final DocumentPoint first;
  final DocumentPoint second;
}

/// Places [text] at [size] on a page: lines wider than the page are broken,
/// then the box is brought as close as possible to [anchor]. Null when the
/// text cannot stand on the page at this size: too many lines once broken,
/// or too tall.
PlacedText? placeText(
  String text, {
  required double size,
  required DocumentPoint anchor,
  required double pageWidth,
  required double pageHeight,
  int font = 0,
}) {
  final wrapped = wrapTextToWidth(
    text,
    size: size,
    maxWidth: pageWidth,
    font: font,
  );
  if (wrapped == null ||
      '\n'.allMatches(wrapped).length + 1 > maxTextLines ||
      utf8.encode(wrapped).length > maxTextBytes) {
    return null;
  }
  final box = textBoxAt(
    anchor,
    TextLayout(wrapped, size: size, rgb: 0, font: font),
    pageWidth: pageWidth,
    pageHeight: pageHeight,
  );
  return box == null ? null : PlacedText(wrapped, box.first, box.second);
}
