// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:edupaint_flutter_study/gallery_storage.dart';

/// The album without a folder, for tests of the interface. It keeps the same
/// cards under the same names as the real album; the folder, its bounds and
/// its cleaning are exercised on a real disk by gallery_storage_test.dart.
class MemoryGallery extends GalleryStorage {
  MemoryGallery({super.maxCopyBytes})
    : super(directory: Directory('unused-in-memory-gallery'));

  final _entries = <String, GalleryEntry>{};
  final _thumbnails = <String, Uint8List>{};
  final _copies = <String, Uint8List>{};

  /// Simulated failures of the album's folder.
  bool failRemember = false;
  bool failList = false;
  bool failCopy = false;

  /// While set, [remember] does not answer, as on a folder that hangs.
  Future<void>? holdRemember;

  /// Completed calls of [remember], successful or not.
  int rememberCalls = 0;

  /// Cards, most recently saved first, as [list] returns them.
  List<GalleryEntry> get entries {
    final sorted = _entries.values.toList()
      ..sort((a, b) {
        final byDate = b.savedAt.compareTo(a.savedAt);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    return List.unmodifiable(sorted);
  }

  Uint8List? thumbnailOf(GalleryEntry entry) => _thumbnails[entry.id];
  Uint8List? copyOf(GalleryEntry entry) => _copies[entry.id];

  @override
  Future<List<GalleryEntry>> list() async {
    if (failList) throw const FileSystemException('Simulated unreadable album');
    return entries;
  }

  @override
  Future<void> remember({
    required String sourcePath,
    required String name,
    required Uint8List project,
    required Uint8List thumbnailPng,
    required int width,
    required int height,
    required int elementCount,
    DateTime? savedAt,
  }) async {
    // Like the real album: nothing of its own folder gets a card.
    if (owns(sourcePath)) throw ArgumentError('Carte de galerie invalide.');
    await holdRemember;
    rememberCalls++;
    if (failRemember) throw const FileSystemException('Simulated full disk');
    final id = GalleryStorage.idFor(sourcePath);
    final keepsCopy = project.isNotEmpty && project.length <= maxCopyBytes;
    _entries[id] = GalleryEntry(
      id: id,
      name: name,
      sourcePath: sourcePath,
      savedAt: (savedAt ?? DateTime.now()).toUtc(),
      width: width,
      height: height,
      elementCount: elementCount,
      copyBytes: keepsCopy ? project.length : 0,
      thumbnailBytes: thumbnailPng.length,
    );
    _thumbnails[id] = Uint8List.fromList(thumbnailPng);
    if (keepsCopy) {
      _copies[id] = Uint8List.fromList(project);
    } else {
      _copies.remove(id);
    }
  }

  @override
  Future<Uint8List> readThumbnail(GalleryEntry entry) async {
    final bytes = _thumbnails[entry.id];
    if (bytes == null) throw const FileSystemException('Simulated missing');
    return Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> readCopy(GalleryEntry entry) async {
    if (failCopy) throw const FileSystemException('Simulated unreadable copy');
    final bytes = _copies[entry.id];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> forget(GalleryEntry entry) async {
    _entries.remove(entry.id);
    _thumbnails.remove(entry.id);
    _copies.remove(entry.id);
  }
}
