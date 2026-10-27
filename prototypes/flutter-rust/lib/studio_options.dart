// SPDX-License-Identifier: MIT
// The options of the studio: what an adult switches on or off to make Color
// as simple as the child needs. They are kept in a small file of Color's own
// folder and read before the first frame.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'recovery_location.dart';
import 'studio_tool.dart';

/// How much of Color is shown.
enum InterfaceLevel {
  /// Four tools, large colours, almost nothing to read.
  toddler('tout-petits', 'Très simplifiée'),

  /// Every tool to draw with, without the layers and the exports.
  child('enfants', 'Moyenne'),

  /// All of Color.
  full('complete', 'Complète');

  const InterfaceLevel(this.code, this.label);

  /// The name written in the options file; never translated or changed.
  final String code;
  final String label;

  /// One sentence for the adult who chooses: for whom, and what is shown.
  String get description => switch (this) {
    InterfaceLevel.toddler => 'Pour les tout-petits : quatre outils, de grandes couleurs, presque rien à lire.',
    InterfaceLevel.child => 'Pour les enfants : tous les outils pour dessiner, sans les calques ni les exports.',
    InterfaceLevel.full => 'Pour les plus grands : tout Color.',
  };
}

/// One state of the options. Immutable: a change makes another one.
@immutable
class StudioOptions {
  const StudioOptions({
    this.level = InterfaceLevel.full,
    this.printing = true,
    this.sounds = true,
    this.holdFree = false,
    this.screenKeyboard = false,
    this.guarded = false,
  });

  /// What a file that says nothing, or nothing readable, stands for: Color
  /// as it was before it had options, with its sounds.
  static const defaults = StudioOptions();

  final InterfaceLevel level;

  /// « Imprimer » is offered: its button, its menu entry and its shortcut.
  final bool printing;

  /// Small sounds answer what the child does.
  final bool sounds;

  /// Drawing without holding the button: a click starts a trait of the
  /// brush, takes the chosen element or the sheet; another click ends it.
  final bool holdFree;

  /// The text dialog shows keys to click.
  final bool screenKeyboard;

  /// A multiplication keeps the door of « Options », so that the youngest
  /// do not open them by chance. Off until an adult switches it on: by
  /// default everything is within reach.
  final bool guarded;

  StudioOptions copyWith({
    InterfaceLevel? level,
    bool? printing,
    bool? sounds,
    bool? holdFree,
    bool? screenKeyboard,
    bool? guarded,
  }) => StudioOptions(
    level: level ?? this.level,
    printing: printing ?? this.printing,
    sounds: sounds ?? this.sounds,
    holdFree: holdFree ?? this.holdFree,
    screenKeyboard: screenKeyboard ?? this.screenKeyboard,
    guarded: guarded ?? this.guarded,
  );

  /// The tools of the bar, in its order.
  List<StudioTool> get tools => level == InterfaceLevel.toddler
      ? const [
          StudioTool.brush,
          StudioTool.stamp,
          StudioTool.fill,
          StudioTool.eraser,
        ]
      : StudioTool.values;

  bool get _toddler => level == InterfaceLevel.toddler;
  bool get _full => level == InterfaceLevel.full;

  /// « Ouvrir » and « Sur une image »: a file to find on the computer.
  bool get opensFiles => !_toddler;

  /// « Exporter » and its formats.
  bool get exports => _full;
  bool get layers => _full;

  /// Zoom, the hand and « dessiner en grand ».
  bool get viewControls => !_toddler;

  /// The « ? » and « i » of the header. Both dialogs stay in the options
  /// dialog; F1 and the menu bar of the Mac open them too, at every level:
  /// they are read-only, and those are the roads of an adult.
  bool get headerHelp => !_toddler;

  /// The panel beside the sheet in wide windows.
  bool get inspector => !_toddler;

  /// The sentence of help under the colours, with the mascot.
  bool get toolHelp => !_toddler;

  /// The name of the drawing above the sheet and the captions on it.
  bool get captions => !_toddler;

  /// The line that says where the project is saved.
  bool get statusLine => _full;

  /// A few large colours and three sizes, instead of every colour, the
  /// pipette and the slider.
  bool get simpleControls => _toddler;

  Map<String, Object> toJson() => {
    'version': 1,
    'level': level.code,
    'printing': printing,
    'sounds': sounds,
    'holdFree': holdFree,
    'screenKeyboard': screenKeyboard,
    'guarded': guarded,
  };

  /// What a decoded options file says. Whatever is missing, of another type
  /// or unknown keeps its default: a file written by another version of
  /// Color, or damaged, never stops the studio.
  factory StudioOptions.fromJson(Object? json) {
    if (json is! Map) return defaults;
    bool flag(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    final code = json['level'];
    return StudioOptions(
      level: InterfaceLevel.values.firstWhere(
        (level) => level.code == code,
        orElse: () => defaults.level,
      ),
      printing: flag('printing', defaults.printing),
      sounds: flag('sounds', defaults.sounds),
      holdFree: flag('holdFree', defaults.holdFree),
      screenKeyboard: flag('screenKeyboard', defaults.screenKeyboard),
      guarded: flag('guarded', defaults.guarded),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StudioOptions &&
      other.level == level &&
      other.printing == printing &&
      other.sounds == sounds &&
      other.holdFree == holdFree &&
      other.screenKeyboard == screenKeyboard &&
      other.guarded == guarded;

  @override
  int get hashCode =>
      Object.hash(level, printing, sounds, holdFree, screenKeyboard, guarded);

  @override
  String toString() => 'StudioOptions(${toJson()})';
}

/// The options file. Reading never fails: what cannot be read is the
/// defaults. Writing replaces the file whole or leaves it as it was.
class OptionsStorage {
  OptionsStorage({required this.file});
  final File file;

  /// An options file is a few lines: anything larger is not one.
  static const maxBytes = 16 * 1024;

  /// The studio waits for the options before its first frame: never longer
  /// than this, whatever stands at the place of the file.
  static const readTimeout = Duration(seconds: 2);

  Future<StudioOptions> read() async {
    try {
      return await _read().timeout(
        readTimeout,
        onTimeout: () => StudioOptions.defaults,
      );
    } catch (_) {
      return StudioOptions.defaults;
    }
  }

  Future<StudioOptions> _read() async {
    // An ordinary file only: a pipe or a device of that name would be read
    // without end.
    if (await FileSystemEntity.type(file.path) != FileSystemEntityType.file ||
        await file.length() > maxBytes) {
      return StudioOptions.defaults;
    }
    return StudioOptions.fromJson(jsonDecode(await file.readAsString()));
  }

  Future<void> write(StudioOptions options) async {
    await file.parent.create(recursive: true);
    // Written beside its place, then moved there: a write that is cut short
    // leaves the options of before.
    final temporary = File('${file.path}.nouveau');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(options.toJson())}\n',
      flush: true,
    );
    await temporary.rename(file.path);
  }
}

/// The options of the running studio. Listeners are told of every change.
class StudioOptionsStore extends ValueNotifier<StudioOptions> {
  StudioOptionsStore(super.value, {this.storage});

  /// Options that last as long as the studio: for a studio without a folder
  /// of its own, and for tests.
  StudioOptionsStore.memory([super.value = StudioOptions.defaults])
    : storage = null;

  /// Where the options are kept; null when they cannot be.
  final OptionsStorage? storage;

  /// The last change could not be written: it holds until Color closes.
  bool get unsaved => _unsaved;
  bool _unsaved = false;

  Future<void> _writing = Future<void>.value();
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The options of Color's own folder, read before the studio is built.
  /// Never fails: without that folder the options are the defaults, and
  /// last as long as the session.
  static Future<StudioOptionsStore> open() async {
    try {
      final support = (await getApplicationSupportDirectory().timeout(
        OptionsStorage.readTimeout,
      )).path;
      final storage = OptionsStorage(
        file: File(optionsFilePath(support, windows: Platform.isWindows)),
      );
      return StudioOptionsStore(await storage.read(), storage: storage);
    } catch (_) {
      return StudioOptionsStore.memory();
    }
  }

  /// Applies [options] at once and keeps them. Completes with false when
  /// they could not be written; they apply all the same.
  Future<bool> change(StudioOptions options) {
    if (options == value) return Future.value(!_unsaved);
    final storage = this.storage;
    // Said before the listeners hear of the change: they read it with it.
    if (storage == null) _unsaved = true;
    value = options;
    if (storage == null) return Future.value(false);
    // One write after the other, each with the options of its moment.
    final result = _writing.then((_) async {
      var kept = true;
      try {
        await storage.write(options);
      } catch (_) {
        kept = false;
      }
      if (_unsaved == kept) {
        _unsaved = !kept;
        // Whoever shows the options says whether they are kept.
        if (!_disposed) notifyListeners();
      }
      return kept;
    });
    _writing = result.then<void>((_) {});
    return result;
  }
}
