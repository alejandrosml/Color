// SPDX-License-Identifier: MIT
// The universes of the studio (Color 1.2): each one dresses the whole
// workshop — its colours, the shape of its buttons, the decor around the
// sheet. The sheet stays white, the tools keep their place and their
// pictures, « Enregistrer » stays golden: what a child relies on does not
// move. The child chooses with the button « Univers »; an adult may fix one
// in the options.
//
// A tablet and a telephone show no decor around the sheet, which takes the
// whole screen there: the child looks at the decor on the whole screen
// instead, with the button « Regarder » (decor_gaze.dart) — as on a
// computer, where both are offered.
//
// The core holds them (src/universes.rs): for each one a description in
// JSON and the pictures of its decor. Nothing here knows the studio: a
// universe is a look and a decor, which another application built on Color
// can wear as well.
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'decor.dart';
import 'language.dart';
import 'platform_words.dart';
import 'rust_document.dart';
import 'studio_colors.dart';

/// One universe: its name, what it looks like, and its decor.
class Universe {
  Universe({
    required this.key,
    required this.frenchName,
    required this.frenchAbout,
    this.look = StudioLook.classic,
    this.decor,
  });

  /// The name written in the options file; never translated or changed.
  final String key;
  final String frenchName;
  final String frenchAbout;
  String get name => tr(frenchName);

  /// One line under its name, where the child chooses.
  String get about => tr(frenchAbout);
  final StudioLook look;

  /// What is drawn around the sheet; null for a universe without a decor.
  final Decor? decor;

  /// The universe of a studio whose core has none: Color as it was before
  /// it had universes.
  static final plain = Universe(
    key: 'classique',
    frenchName: 'Classique',
    frenchAbout: 'L’atelier de toujours.',
  );

  /// The universe one text of the core describes — a « U » line, an « M »
  /// line, then its pictures — or null when it cannot be read.
  static Universe? parse(String text) {
    final first = text.indexOf('\n');
    if (first < 0 || !text.startsWith('U ')) return null;
    final second = text.indexOf('\n', first + 1);
    if (second < 0 || !text.startsWith('M ', first + 1)) return null;
    final key = text.substring(2, first);
    final Object? json;
    try {
      json = jsonDecode(text.substring(first + 3, second));
    } on FormatException {
      return null;
    }
    if (json is! Map || json['key'] != key || key.isEmpty) return null;
    final name = json['name'];
    final about = json['about'];
    if (name is! String || name.isEmpty) return null;
    return Universe(
      key: key,
      frenchName: name,
      frenchAbout: about is String ? about : '',
      look: StudioLook.fromJson(json['look']),
      decor: Decor.fromJson(
        json['decor'],
        pictures: text.substring(second + 1),
      ),
    );
  }
}

/// The universes of this Color, in the order the child is shown them.
class UniverseCatalog {
  UniverseCatalog(List<Universe> universes)
    : universes = List.unmodifiable(
        universes.isEmpty ? [Universe.plain] : universes,
      );

  /// Never empty: a core without universes gives [Universe.plain] alone.
  final List<Universe> universes;

  static UniverseCatalog? _instance;

  /// The catalogue of this process, read from the core on first use. A
  /// universe that cannot be read is left out alone.
  static UniverseCatalog get instance => _instance ??= _read();

  static UniverseCatalog _read() {
    final universes = <Universe>[];
    try {
      final count = RustDocument.universeCount();
      for (var index = 0; index < count; index++) {
        final text = RustDocument.readUniverse(index);
        final universe = text == null ? null : Universe.parse(text);
        if (universe != null &&
            universes.every((other) => other.key != universe.key)) {
          universes.add(universe);
        }
      }
    } catch (_) {
      // Without the library, or with one that has no universes: the
      // studio of before.
    }
    return UniverseCatalog(universes);
  }

  /// For tests: the catalogue this process uses from now on; null reads the
  /// core again on next use.
  @visibleForTesting
  static void debugUse(UniverseCatalog? catalog) => _instance = catalog;

  /// The universe an adult or a child chose; that of the device for a key
  /// that names none — another version of Color wrote it, or nobody chose
  /// yet.
  Universe named(String? key) => universes.firstWhere(
    (universe) => universe.key == key,
    orElse: () => ofDevice,
  );

  /// The universe of a studio that was told none (the owner, 12 November
  /// 2026). On a computer, the first one that has a decor: the desk by the
  /// window. On a tablet or a telephone, where no decor is shown around
  /// the sheet, the first one without a decor: « Classique », the workshop
  /// as it always was. The first one of all where there is no such one.
  Universe get ofDevice => universes.firstWhere(
    (universe) => (universe.decor == null) == touchFirst,
    orElse: () => universes.first,
  );

  /// The first universe, in the order the child is shown them.
  Universe get first => universes.first;
}

/// Dresses the studio in [universe]: its look becomes that of the moment,
/// and everything that is shown is built and painted again — also what was
/// built once and for all, which would otherwise keep the colours it was
/// built with. The state of every part, the drawing first, is kept.
void wearUniverse(Universe universe) {
  if (identical(studioLook.value, universe.look)) return;
  studioLook.value = universe.look;
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return;
  void build(Element element) {
    element.markNeedsBuild();
    element.visitChildren(build);
  }

  void paint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(paint);
  }

  root.visitChildren(build);
  // What is built again may keep a painter that says nothing changed: the
  // colours did. Everything that is shown is painted again with them, in
  // the frame that builds it again.
  final view = root.renderObject;
  if (view != null) paint(view);
  WidgetsBinding.instance.scheduleFrame();
}
