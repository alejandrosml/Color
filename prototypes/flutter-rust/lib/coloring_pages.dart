// SPDX-License-Identifier: MIT
// The colouring pages of the core: original drawings that a new sheet can
// start with. The core describes them in one ASCII text (see src/pages.rs of
// the core): for each page a line
//
//   T <id> <key> <regions> <details> <title>
//
// then its thumbnail, in the format that vector_art.dart reads, from « P » to
// « X ». The title is UTF-8 whose bytes outside printable ASCII, and « % »,
// are written %XX. Choosing a page asks the core for a new document made of
// it (RustDocument.fromPage): its zones and its lines on two locked layers,
// under and over the layer where the child draws.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'new_sheet_dialog.dart';
import 'rust_document.dart';
import 'vector_art.dart';

const _unreadable = FormatException('Page à colorier illisible.');

/// The colouring pages of the core, read on first use.
abstract final class ColoringPages {
  static List<ColoringPage>? _pages;

  /// The pages of this process; empty when the core has none to give: a
  /// library older than this interface, or one built without its pictures.
  /// « Nouveau » then offers the empty sheets only.
  static List<ColoringPage> get all => _pages ??= () {
    try {
      return List<ColoringPage>.unmodifiable(
        parse(RustDocument.readPageCatalog()),
      );
    } catch (_) {
      return const <ColoringPage>[];
    }
  }();

  /// For tests: the pages this process offers from now on; null reads the
  /// core again on next use.
  @visibleForTesting
  static void debugUse(List<ColoringPage>? pages) => _pages = pages;

  /// The pages of one catalogue text, in its order. A page that cannot be
  /// read is left out alone: the others are not lost with it.
  static List<ColoringPage> parse(String text) {
    final pages = <ColoringPage>[];
    String? head;
    final body = <String>[];
    for (final line in text.split('\n')) {
      if (line.startsWith('T ')) {
        // A page left unfinished is dropped with its lines.
        head = line;
        body.clear();
        continue;
      }
      if (head == null) continue;
      body.add(line);
      if (line != 'X') continue;
      try {
        pages.add(_page(head, body.join('\n')));
      } catch (_) {
        // Not a page that this interface can show.
      }
      head = null;
      body.clear();
    }
    return pages;
  }

  static final _key = RegExp(r'^[a-z]+(-[a-z]+)*$');

  static ColoringPage _page(String head, String description) {
    // Five fields separated by one space each, then the title.
    final fields = <String>[];
    var start = 0;
    while (fields.length < 5) {
      final end = head.indexOf(' ', start);
      if (end < 0) throw _unreadable;
      fields.add(head.substring(start, end));
      start = end + 1;
    }
    final id = int.tryParse(fields[1]);
    final key = fields[2];
    final regions = int.tryParse(fields[3]);
    final details = int.tryParse(fields[4]);
    if (fields[0] != 'T' ||
        id == null ||
        id < 0 ||
        id > 0xffffffff ||
        !_key.hasMatch(key) ||
        regions == null ||
        regions < 0 ||
        details == null ||
        details < 0 ||
        regions + details == 0) {
      throw _unreadable;
    }
    final title = decodeTitle(head.substring(start));
    final pictures = VectorPicture.parseAll(description);
    if (pictures.length != 1 || pictures.single.key != key) throw _unreadable;
    final picture = pictures.single;
    final width = picture.width.toInt();
    final height = picture.height.toInt();
    // The sheet of a document: whole units, as the core makes them.
    if (width != picture.width ||
        height != picture.height ||
        width > 16384 ||
        height > 16384) {
      throw _unreadable;
    }
    return ColoringPage(
      id: id,
      key: key,
      title: title,
      regions: regions,
      details: details,
      picture: picture,
      width: width,
      height: height,
    );
  }

  /// The title written in the catalogue: printable ASCII, and %XX for each
  /// other byte of its UTF-8, which is decoded here.
  @visibleForTesting
  static String decodeTitle(String text) {
    int hex(int unit) => switch (unit) {
      >= 0x30 && <= 0x39 => unit - 0x30,
      >= 0x41 && <= 0x46 => unit - 0x41 + 10,
      >= 0x61 && <= 0x66 => unit - 0x61 + 10,
      _ => throw _unreadable,
    };
    final bytes = <int>[];
    for (var index = 0; index < text.length; index++) {
      final unit = text.codeUnitAt(index);
      if (unit == 0x25) {
        if (index + 2 >= text.length) throw _unreadable;
        bytes.add(
          hex(text.codeUnitAt(index + 1)) << 4 |
              hex(text.codeUnitAt(index + 2)),
        );
        index += 2;
      } else if (unit >= 0x20 && unit < 0x7f) {
        bytes.add(unit);
      } else {
        throw _unreadable;
      }
    }
    // Throws on bytes that are not UTF-8.
    final title = utf8.decode(bytes).trim();
    if (title.isEmpty) throw _unreadable;
    return title;
  }
}
