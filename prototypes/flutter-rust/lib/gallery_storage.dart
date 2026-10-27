// SPDX-License-Identifier: MIT
// « Mes dessins » : a small private album of the drawings that were saved.
//
// One card, one file, in Color's own folder beside the recovery copy:
//
//   8 bytes   « COLORCRD »
//   4 bytes   format of the card, little endian: 1
//   4 bytes   length of its description
//   4 bytes   length of its picture
//   4 bytes   length of its copy of the project, 0 when it keeps none
//   then the description (JSON, UTF-8), the picture (PNG) and the copy
//
// A card is written whole under a temporary name and then takes its place:
// it is never half an older drawing and half a newer one, and a refresh that
// fails leaves the card that was there. Its file is not a project: it cannot
// be opened or saved over as one by mistake.
//
// The album never reads, writes or removes a file that the user saved
// elsewhere, and saving never waits for it: a failure here costs a card, not
// a drawing. What it removes is only ever its own, and only what it knows:
// cards beyond its bounds, the card that the user asks to remove, and its
// writer's temporary files once they are plainly abandoned. A file that it
// cannot examine or does not understand (a card of a later version of Color,
// or anything else under a card's name) is left out and left alone.
//
// One instance per folder; its operations run one after another. This is not
// a lock between two running copies of Color: at worst a card is missing.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'project_storage.dart';
import 'recovery_location.dart';

/// One card of the album. Immutable description read from its folder.
class GalleryEntry {
  const GalleryEntry({
    required this.id,
    required this.name,
    required this.sourcePath,
    required this.savedAt,
    required this.width,
    required this.height,
    required this.elementCount,
    required this.copyBytes,
    required this.thumbnailBytes,
  });

  /// Sixteen hexadecimal digits derived from [sourcePath].
  final String id;

  /// File name of the saved project, shown under the thumbnail.
  final String name;

  /// Where the project was saved. It may no longer exist, or no longer be
  /// readable by this process.
  final String sourcePath;
  final DateTime savedAt;
  final int width;
  final int height;
  final int elementCount;

  /// Size of the project copy kept in the album; zero when the project was
  /// too large to be copied.
  final int copyBytes;
  final int thumbnailBytes;

  bool get hasCopy => copyBytes > 0;
}

// What one request to remember a save holds until its turn comes.
class _PendingCard {
  _PendingCard(this.card);
  Uint8List? card;
}

class GalleryStorage {
  GalleryStorage({
    required this.directory,
    this.maxEntries = 24,
    this.maxCopyBytes = 8 * 1024 * 1024,
    this.maxTotalCopyBytes = 64 * 1024 * 1024,
    this.operationTimeout = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : assert(maxEntries > 0 && maxCopyBytes > 0 && maxTotalCopyBytes > 0),
       _now = now ?? DateTime.now;

  final Directory directory;

  /// Older cards leave the album beyond this number.
  final int maxEntries;

  /// A larger project keeps its thumbnail and its place, without a copy.
  final int maxCopyBytes;

  /// Copies of the oldest cards are dropped beyond this total; their
  /// thumbnails stay.
  final int maxTotalCopyBytes;

  /// A request that the folder does not answer within this time fails, and
  /// the requests behind it are served: one stalled file never stops the
  /// album for the rest of the session.
  final Duration operationTimeout;
  final DateTime Function() _now;

  static const maxThumbnailBytes = 512 * 1024;
  static const _maxDescriptionBytes = 16 * 1024;
  static const _headerBytes = 24;
  static const _magic = [0x43, 0x4f, 0x4c, 0x4f, 0x52, 0x43, 0x52, 0x44];
  static const _cardFormat = 1;
  static final _identifier = RegExp(r'^[0-9a-f]{16}$');
  static final _cardFile = RegExp(r'^([0-9a-f]{16})\.card$');

  /// The name ProjectStorage gives to a file being written, before it takes
  /// its place. One that is still there long after was left by a write that
  /// never finished.
  static final _temporaryFile = RegExp(r'^\.edupaint-[0-9a-f]{32}\.tmp$');
  static const abandonedAfter = Duration(minutes: 10);

  Future<void> _pending = Future<void>.value();

  // The newest request to remember each card that has not been written yet:
  // saves made faster than the folder answers keep one card each to write.
  final _waiting = <String, _PendingCard>{};

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation().timeout(operationTimeout));
    // The queue goes on after a failure; the caller still receives it.
    _pending = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// A stable card name for a saved path: the same file keeps one card.
  /// FNV-1a over the UTF-8 path: a name, not a protection.
  static String idFor(String sourcePath) {
    // 64-bit arithmetic wraps by itself on the platforms Color runs on.
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(sourcePath)) {
      hash ^= byte;
      hash *= 0x100000001b3;
    }
    // Two halves: a negative 64-bit value has no hexadecimal form of its own.
    String half(int value) =>
        (value & 0xffffffff).toRadixString(16).padLeft(8, '0');
    return half(hash >> 32) + half(hash);
  }

  /// The file of the card of a saved path, in this album's folder.
  String cardPath(String id) =>
      '${directory.path}${Platform.pathSeparator}${_checked(id)}.card';

  static String _checked(String id) {
    if (!_identifier.hasMatch(id)) {
      throw ArgumentError('Carte de galerie invalide.');
    }
    return id;
  }

  /// Whether [path] names a file placed directly in the album's folder.
  /// Nothing there is a place for a drawing: the studio never takes such a
  /// path as the file of a project.
  bool owns(String path) => isPlacedIn(
    File(path).absolute.path,
    directory.absolute.path,
    separator: Platform.pathSeparator,
    caseSensitive: !Platform.isMacOS && !Platform.isWindows,
  );

  /// A name fit to be shown: well-formed, on one line, never empty.
  static String _tidyName(String name) {
    final buffer = StringBuffer();
    for (final rune in name.runes) {
      final hidden =
          rune < 0x20 ||
          (rune >= 0x7f && rune <= 0x9f) ||
          rune == 0x2028 ||
          rune == 0x2029;
      // Half of a pair alone cannot be written or shown: the replacement
      // character stands for it.
      final lone = rune >= 0xd800 && rune <= 0xdfff;
      buffer.writeCharCode(
        hidden
            ? 0x20
            : lone
            ? 0xfffd
            : rune,
      );
    }
    final tidy = buffer.toString().trim();
    if (tidy.isEmpty) return 'Dessin';
    if (tidy.length <= 255) return tidy;
    // Never cut between the two halves of one character.
    final last = tidy.codeUnitAt(254);
    return tidy.substring(0, last >= 0xd800 && last <= 0xdbff ? 254 : 255);
  }

  /// Cards, most recently saved first, never more than the album keeps.
  /// Files that are not cards of this album, or that cannot be read, are
  /// left out; a missing folder is an empty album.
  Future<List<GalleryEntry>> list() => _enqueue(
    () async =>
        List<GalleryEntry>.unmodifiable((await _scan()).take(maxEntries)),
  );

  // A date more than a day ahead of the clock is not a moment that was: its
  // card ranks last and is the first to leave a full album, instead of
  // holding a place for ever. A clock that was a little ahead and was set
  // right changes nothing.
  static const _clockTolerance = Duration(days: 1);
  static final _longAgo = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  DateTime _ranked(GalleryEntry entry, DateTime now) =>
      entry.savedAt.isAfter(now.add(_clockTolerance))
      ? _longAgo
      : entry.savedAt;

  // Every card of the folder that this album understands, newest first.
  Future<List<GalleryEntry>> _scan() async {
    if (!await directory.exists()) return const [];
    final entries = <GalleryEntry>[];
    await for (final item in directory.list(followLinks: false)) {
      final match = _cardFile.firstMatch(item.uri.pathSegments.last);
      if (match == null) continue;
      try {
        final card = await _readCard(match.group(1)!);
        if (card != null) entries.add(card.entry);
      } on FileSystemException {
        // Refused for a moment, or for good: left out, and left alone.
      }
    }
    final now = _now().toUtc();
    entries.sort((a, b) {
      final byDate = _ranked(b, now).compareTo(_ranked(a, now));
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return entries;
  }

  static Future<Uint8List?> _readExactly(
    RandomAccessFile handle,
    int count,
  ) async {
    final bytes = Uint8List(count);
    var used = 0;
    while (used < count) {
      final read = await handle.readInto(bytes, used, count);
      if (read == 0) return null;
      used += read;
    }
    return bytes;
  }

  // The card of [id] as it is now, or null when there is none that this
  // album understands: no file, something that is not an ordinary file (a
  // link is never followed), a card of a later format, bounds that are not
  // this album's, a description that does not hold together. An ordinary
  // file that cannot be read is another matter: that error propagates.
  Future<({GalleryEntry entry, Uint8List? thumbnail, Uint8List? copy})?>
  _readCard(
    String id, {
    bool withThumbnail = false,
    bool withCopy = false,
  }) async {
    final path = cardPath(id);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final RandomAccessFile handle;
    try {
      handle = await File(path).open();
    } on FileSystemException catch (error) {
      if (_isMissing(error)) return null;
      rethrow;
    }
    try {
      final length = await handle.length();
      if (length < _headerBytes) return null;
      final header = await _readExactly(handle, _headerBytes);
      if (header == null) return null;
      for (var index = 0; index < _magic.length; index++) {
        if (header[index] != _magic[index]) return null;
      }
      final fields = ByteData.sublistView(header);
      final descriptionBytes = fields.getUint32(12, Endian.little);
      final thumbnailBytes = fields.getUint32(16, Endian.little);
      final copyBytes = fields.getUint32(20, Endian.little);
      if (fields.getUint32(8, Endian.little) != _cardFormat ||
          descriptionBytes < 2 ||
          descriptionBytes > _maxDescriptionBytes ||
          thumbnailBytes < 1 ||
          thumbnailBytes > maxThumbnailBytes ||
          copyBytes > maxCopyBytes ||
          length !=
              _headerBytes + descriptionBytes + thumbnailBytes + copyBytes) {
        return null;
      }
      final description = await _readExactly(handle, descriptionBytes);
      if (description == null) return null;
      final Object? data;
      try {
        data = jsonDecode(utf8.decode(description));
      } on FormatException {
        return null;
      }
      if (data is! Map<String, Object?>) return null;
      final name = data['name'];
      final sourcePath = data['path'];
      final savedAt = data['savedAt'];
      final width = data['width'];
      final height = data['height'];
      final count = data['count'];
      if (name is! String ||
          sourcePath is! String ||
          sourcePath.isEmpty ||
          sourcePath.length > 4096 ||
          idFor(sourcePath) != id ||
          savedAt is! int ||
          savedAt < 0 ||
          savedAt > 8640000000000000 ||
          width is! int ||
          width < 1 ||
          width > 16384 ||
          height is! int ||
          height < 1 ||
          height > 16384 ||
          count is! int ||
          count < 0 ||
          count > 10000) {
        return null;
      }
      Uint8List? thumbnail;
      if (withThumbnail) {
        thumbnail = await _readExactly(handle, thumbnailBytes);
        if (thumbnail == null) return null;
      }
      Uint8List? copy;
      if (withCopy && copyBytes > 0) {
        await handle.setPosition(
          _headerBytes + descriptionBytes + thumbnailBytes,
        );
        copy = await _readExactly(handle, copyBytes);
        if (copy == null) return null;
      }
      return (
        entry: GalleryEntry(
          id: id,
          name: _tidyName(name),
          sourcePath: sourcePath,
          savedAt: DateTime.fromMillisecondsSinceEpoch(savedAt, isUtc: true),
          width: width,
          height: height,
          elementCount: count,
          copyBytes: copyBytes,
          thumbnailBytes: thumbnailBytes,
        ),
        thumbnail: thumbnail,
        copy: copy,
      );
    } finally {
      await handle.close();
    }
  }

  static bool _isMissing(FileSystemException error) {
    final code = error.osError?.errorCode;
    // ENOENT, and ERROR_FILE_NOT_FOUND / ERROR_PATH_NOT_FOUND on Windows.
    return Platform.isWindows ? code == 2 || code == 3 : code == 2;
  }

  static Uint8List _encode({
    required String name,
    required String sourcePath,
    required DateTime savedAt,
    required int width,
    required int height,
    required int elementCount,
    required Uint8List thumbnail,
    required Uint8List? copy,
  }) {
    final description = utf8.encode(
      jsonEncode({
        'name': name,
        'path': sourcePath,
        'savedAt': savedAt.toUtc().millisecondsSinceEpoch,
        'width': width,
        'height': height,
        'count': elementCount,
      }),
    );
    if (description.length > _maxDescriptionBytes) {
      throw ArgumentError('Carte de galerie invalide.');
    }
    final copyBytes = copy?.length ?? 0;
    final card = Uint8List(
      _headerBytes + description.length + thumbnail.length + copyBytes,
    );
    card.setAll(0, _magic);
    ByteData.sublistView(card)
      ..setUint32(8, _cardFormat, Endian.little)
      ..setUint32(12, description.length, Endian.little)
      ..setUint32(16, thumbnail.length, Endian.little)
      ..setUint32(20, copyBytes, Endian.little);
    card.setAll(_headerBytes, description);
    card.setAll(_headerBytes + description.length, thumbnail);
    if (copy != null) {
      card.setAll(_headerBytes + description.length + thumbnail.length, copy);
    }
    return card;
  }

  /// Adds or refreshes the card of a project that has just been saved to
  /// [sourcePath]. The bytes are captured now; the card is written later,
  /// behind earlier operations, and replaces the previous one in one step.
  /// Of several saves of one file that wait together, the last is written.
  Future<void> remember({
    required String sourcePath,
    required String name,
    required Uint8List project,
    required Uint8List thumbnailPng,
    required int width,
    required int height,
    required int elementCount,
    DateTime? savedAt,
  }) {
    if (sourcePath.isEmpty ||
        sourcePath.length > 4096 ||
        owns(sourcePath) ||
        name.isEmpty ||
        thumbnailPng.isEmpty ||
        thumbnailPng.length > maxThumbnailBytes ||
        width < 1 ||
        width > 16384 ||
        height < 1 ||
        height > 16384 ||
        elementCount < 0 ||
        elementCount > 10000) {
      throw ArgumentError('Carte de galerie invalide.');
    }
    final id = idFor(sourcePath);
    final keepsCopy = project.isNotEmpty && project.length <= maxCopyBytes;
    final request = _PendingCard(
      _encode(
        name: _tidyName(name),
        sourcePath: sourcePath,
        savedAt: savedAt ?? _now(),
        width: width,
        height: height,
        elementCount: elementCount,
        thumbnail: thumbnailPng,
        copy: keepsCopy ? project : null,
      ),
    );
    // An older request for the same card that still waits has nothing left
    // to write, and lets go of its bytes.
    _waiting[id]?.card = null;
    _waiting[id] = request;
    return _enqueue(() async {
      final card = request.card;
      if (card == null) return;
      request.card = null;
      if (identical(_waiting[id], request)) _waiting.remove(id);
      await directory.create(recursive: true);
      await ProjectStorage.writeAtomicBytes(cardPath(id), card);
      await _prune(justWritten: id);
    });
  }

  // Keeps the newest cards, and the copies of the newest among them; then
  // removes the temporary files that an interrupted write left behind. The
  // card that was just written is the newest whatever the clock says.
  Future<void> _prune({required String justWritten}) async {
    final entries = await _scan();
    final ordered = [
      ...entries.where((entry) => entry.id == justWritten),
      ...entries.where((entry) => entry.id != justWritten),
    ];
    var copies = 0;
    for (final (rank, entry) in ordered.indexed) {
      if (rank >= maxEntries) {
        await _delete(cardPath(entry.id));
      } else if (entry.hasCopy) {
        if (copies + entry.copyBytes > maxTotalCopyBytes) {
          // The card stays, as a picture and a place to look for the file.
          await _dropCopy(entry.id);
        } else {
          copies += entry.copyBytes;
        }
      }
    }
    final now = _now();
    await for (final item in directory.list(followLinks: false)) {
      if (item is! File ||
          !_temporaryFile.hasMatch(item.uri.pathSegments.last)) {
        continue;
      }
      // Old enough that no running Color can still be writing it.
      try {
        if (now.difference(await item.lastModified()) > abandonedAfter) {
          await _delete(item.path);
        }
      } on FileSystemException {
        // It will be looked at again after a later save.
      }
    }
  }

  // Rewrites a card without its copy, in one step like any other write.
  Future<void> _dropCopy(String id) async {
    final card = await _readCard(id, withThumbnail: true);
    if (card == null || !card.entry.hasCopy) return;
    await ProjectStorage.writeAtomicBytes(
      cardPath(id),
      _encode(
        name: card.entry.name,
        sourcePath: card.entry.sourcePath,
        savedAt: card.entry.savedAt,
        width: card.entry.width,
        height: card.entry.height,
        elementCount: card.entry.elementCount,
        thumbnail: card.thumbnail!,
        copy: null,
      ),
    );
  }

  /// The thumbnail of a card as it is now, as PNG bytes.
  Future<Uint8List> readThumbnail(GalleryEntry entry) => _enqueue(() async {
    final card = await _readCard(_checked(entry.id), withThumbnail: true);
    if (card == null) {
      throw FileSystemException(
        'Carte de galerie absente.',
        cardPath(entry.id),
      );
    }
    return card.thumbnail!;
  });

  /// The project copy of a card as it is now, or null when it keeps none.
  /// A card refreshed by a later save gives its newer copy: it is the same
  /// drawing. The bytes are opaque here: the core validates them when the
  /// drawing is opened.
  Future<Uint8List?> readCopy(GalleryEntry entry) => _enqueue(() async {
    final card = await _readCard(_checked(entry.id), withCopy: true);
    if (card == null) {
      throw FileSystemException(
        'Carte de galerie absente.',
        cardPath(entry.id),
      );
    }
    return card.copy;
  });

  /// Removes one card from the album: its picture, its description and its
  /// copy. The file saved at [GalleryEntry.sourcePath] is never touched.
  Future<void> forget(GalleryEntry entry) =>
      _enqueue(() => _delete(cardPath(entry.id)));

  // Only ever called with the path of a file of this album's own folder,
  // under one of the names the album writes itself. A link is removed as a
  // link: what it points to is not this album's.
  static Future<void> _delete(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException catch (error) {
      if (!_isMissing(error)) rethrow;
    }
  }
}
