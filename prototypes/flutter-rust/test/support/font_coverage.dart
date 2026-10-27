// SPDX-License-Identifier: MIT
import 'dart:typed_data';

/// Which characters a TrueType font can draw, read in its `cmap` table: the
/// Unicode subtables of formats 4 and 12, which is what DejaVu Sans carries.
class FontCoverage {
  FontCoverage(Uint8List bytes) : _data = ByteData.sublistView(bytes) {
    final tables = _data.getUint16(4);
    int? cmap;
    for (var index = 0; index < tables; index++) {
      final record = 12 + 16 * index;
      final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
      if (tag == 'cmap') cmap = _data.getUint32(record + 8);
    }
    if (cmap == null) throw const FormatException('font without a cmap table');
    final subtables = _data.getUint16(cmap + 2);
    for (var index = 0; index < subtables; index++) {
      final record = cmap + 4 + 8 * index;
      final platform = _data.getUint16(record);
      final encoding = _data.getUint16(record + 2);
      final offset = cmap + _data.getUint32(record + 4);
      final format = _data.getUint16(offset);
      final unicode =
          platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
      if (!unicode) continue;
      if (format == 12) _groups = offset;
      if (format == 4) _segments = offset;
    }
    if (_groups == null && _segments == null) {
      throw const FormatException('font without a Unicode character table');
    }
  }

  final ByteData _data;
  int? _groups;
  int? _segments;

  /// Whether the font has a glyph of its own for [codePoint].
  bool has(int codePoint) {
    final groups = _groups;
    if (groups != null) {
      final count = _data.getUint32(groups + 12);
      for (var index = 0; index < count; index++) {
        final group = groups + 16 + 12 * index;
        final start = _data.getUint32(group);
        final end = _data.getUint32(group + 4);
        if (codePoint >= start && codePoint <= end) {
          return _data.getUint32(group + 8) + (codePoint - start) != 0;
        }
      }
      return false;
    }
    if (codePoint > 0xffff) return false;
    final table = _segments!;
    final count = _data.getUint16(table + 6) ~/ 2;
    final ends = table + 14;
    final starts = ends + 2 * count + 2;
    final deltas = starts + 2 * count;
    final ranges = deltas + 2 * count;
    for (var index = 0; index < count; index++) {
      if (_data.getUint16(ends + 2 * index) < codePoint) continue;
      final start = _data.getUint16(starts + 2 * index);
      if (start > codePoint) return false;
      final delta = _data.getUint16(deltas + 2 * index);
      final range = _data.getUint16(ranges + 2 * index);
      if (range == 0) return (codePoint + delta) & 0xffff != 0;
      final glyph = _data.getUint16(
        ranges + 2 * index + range + 2 * (codePoint - start),
      );
      return glyph != 0 && (glyph + delta) & 0xffff != 0;
    }
    return false;
  }

  /// The characters of [text] that the font cannot draw.
  List<String> missing(String text) => [
    for (final rune in text.runes)
      if (!has(rune)) String.fromCharCode(rune),
  ];
}
