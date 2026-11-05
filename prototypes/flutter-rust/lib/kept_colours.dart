// SPDX-License-Identifier: MIT
// The colours a child chose last, kept from one session to the next
// (Color 1.1): those it mixed or invented come back with the others. A
// small file beside the options, couleurs.json; without it, they last as
// long as the session.
import 'dart:convert';
import 'dart:io';

import 'app_folders.dart';
import 'recovery_location.dart';

class KeptColours {
  KeptColours._(this._file, List<int> colours)
    : _colours = List.unmodifiable(colours);

  /// Colours that are not kept anywhere: for tests, and a studio without a
  /// folder of its own.
  KeptColours.memory([List<int> colours = const []]) : this._(null, colours);

  final File? _file;

  /// The latest first, at most [capacity]: those read, then those kept.
  List<int> get colours => _colours;
  List<int> _colours;

  static const capacity = 16;

  /// A file of colours is a few lines: anything larger is not one.
  static const _maxBytes = 4096;

  /// The colours of Color's folder. Never fails, and never waits more than
  /// two seconds: without the file there are none yet.
  static Future<KeptColours> open() async {
    try {
      final support = (await applicationSupportFolder().timeout(
        const Duration(seconds: 2),
      )).path;
      final options = optionsFilePath(support, windows: Platform.isWindows);
      final file = File(
        '${options.substring(0, options.length - 'options.json'.length)}'
        'couleurs.json',
      );
      return KeptColours._(file, await _read(file));
    } catch (_) {
      return KeptColours.memory();
    }
  }

  /// The colours kept in [file].
  static Future<KeptColours> openFile(File file) async =>
      KeptColours._(file, await _read(file));

  static Future<List<int>> _read(File file) async {
    try {
      if (await FileSystemEntity.type(file.path) != FileSystemEntityType.file ||
          await file.length() > _maxBytes) {
        return const [];
      }
      final json = jsonDecode(await file.readAsString());
      if (json is! Map || json['couleurs'] is! List) return const [];
      return [
        for (final value in json['couleurs'] as List)
          if (value is String &&
              RegExp(r'^#[0-9a-f]{6}$').hasMatch(value.toLowerCase()))
            int.parse(value.substring(1), radix: 16),
      ].take(capacity).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writing = Future<void>.value();

  /// Keeps [colours], one write after the other; a write that fails keeps
  /// the colours of before, and says nothing: they are a convenience.
  Future<void> keep(List<int> colours) {
    _colours = List.unmodifiable(colours.take(capacity));
    final file = _file;
    if (file == null) return Future<void>.value();
    final text =
        '${const JsonEncoder.withIndent('  ').convert({
          'couleurs': [for (final rgb in colours.take(capacity)) '#${rgb.toRadixString(16).padLeft(6, '0')}'],
        })}\n';
    return _writing = _writing.then((_) async {
      try {
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.nouveau');
        await temporary.writeAsString(text, flush: true);
        await temporary.rename(file.path);
      } catch (_) {}
    });
  }
}
