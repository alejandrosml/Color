// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'fit_to_screen.dart';
import 'french.dart';
import 'gallery_storage.dart';
import 'studio_colors.dart';

/// « Mes dessins » : the cards of the album. Returns the card to reopen, or
/// null when the dialog is closed. Removing a card happens here; opening is
/// left to the studio, which owns the current drawing.
///
/// [ready] completes when the cards of the saves just made are written: the
/// album is read after it, so that a drawing saved a moment ago is there.
Future<GalleryEntry?> showGalleryDialog(
  BuildContext context, {
  required GalleryStorage storage,
  DateTime Function() now = DateTime.now,
  Future<void>? ready,
  bool opensFiles = true,
}) => showDialog<GalleryEntry>(
  context: context,
  builder: (_) => FitDialog(
    child: GalleryDialog(
      storage: storage,
      now: now,
      ready: ready,
      opensFiles: opensFiles,
    ),
  ),
);

/// Whether [bytes] begin as a PNG picture no larger than a thumbnail of the
/// album. A small file can announce a picture of hundreds of megabytes: what
/// the album did not write is not handed to the decoder on its word.
bool isThumbnailPng(Uint8List bytes, {int maxSide = 1024}) {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  const header = [0x49, 0x48, 0x44, 0x52]; // IHDR
  if (bytes.length < 33) return false;
  for (var index = 0; index < 8; index++) {
    if (bytes[index] != signature[index]) return false;
  }
  for (var index = 0; index < 4; index++) {
    if (bytes[12 + index] != header[index]) return false;
  }
  final data = ByteData.sublistView(bytes);
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  return width >= 1 && width <= maxSide && height >= 1 && height <= maxSide;
}

/// The name written on a card: the file name without the extension of a
/// Color project, which says nothing to a child.
String cardTitle(String fileName) {
  const extension = '.edupaint';
  if (fileName.length <= extension.length ||
      !fileName.toLowerCase().endsWith(extension)) {
    return fileName;
  }
  final title = fileName.substring(0, fileName.length - extension.length);
  return title.trim().isEmpty ? fileName : title;
}

class GalleryDialog extends StatefulWidget {
  const GalleryDialog({
    super.key,
    required this.storage,
    this.now = DateTime.now,
    this.ready,
    this.opensFiles = true,
  });
  final GalleryStorage storage;
  final DateTime Function() now;
  final Future<void>? ready;

  /// The interface offers « Ouvrir » : a sentence may send the child there.
  final bool opensFiles;

  @override
  State<GalleryDialog> createState() => _GalleryDialogState();
}

class _GalleryDialogState extends State<GalleryDialog> {
  List<GalleryEntry>? _entries;
  bool _failed = false;
  // The picture of each card, read once; null for one that is not a
  // thumbnail of the album.
  final _thumbnails = <String, Future<MemoryImage?>>{};
  final _decoded = <MemoryImage>[];

  @override
  void initState() {
    super.initState();
    _load(after: widget.ready);
  }

  @override
  void dispose() {
    // The pictures of this opening do not stay in the cache of images.
    for (final image in _decoded) {
      image.evict();
    }
    super.dispose();
  }

  Future<MemoryImage?> _thumbnail(GalleryEntry entry) async {
    final bytes = await widget.storage.readThumbnail(entry);
    if (!isThumbnailPng(bytes)) return null;
    final image = MemoryImage(bytes);
    if (mounted) {
      _decoded.add(image);
    }
    return image;
  }

  Future<void> _load({Future<void>? after}) async {
    try {
      try {
        await after;
      } catch (_) {
        // A card that could not be made is simply not there.
      }
      final entries = await widget.storage.list();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _failed = false;
      });
    } catch (_) {
      // The album is a convenience: say that it cannot be shown, no more.
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _remove(GalleryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => FitDialog(
        child: AlertDialog(
          key: const Key('galleryForgetDialog'),
          title: Text('Retirer « ${cardTitle(entry.name)} » de la galerie ?'),
          content: const Text(
            'Sa carte disparaît d’ici, avec la copie que la galerie en gardait. Ton fichier enregistré reste à sa place.',
          ),
          actions: [
            TextButton(
              key: const Key('cancelGalleryForget'),
              style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const Key('confirmGalleryForget'),
              style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Retirer la carte'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.storage.forget(entry);
    } catch (_) {
      // The list below shows what is really left.
    }
    _thumbnails.remove(entry.id);
    await _load();
  }

  static const _nameStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  Widget _card(GalleryEntry entry) {
    final title = cardTitle(entry.name);
    final saved = savedMoment(entry.savedAt.toLocal(), now: widget.now());
    final thumbnail = _thumbnails.putIfAbsent(
      entry.id,
      () => _thumbnail(entry),
    );
    return SizedBox(
      width: 196,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            key: Key('gallery-open-${entry.id}'),
            onPressed: () => Navigator.pop(context, entry),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(8),
              backgroundColor: Colors.white,
              foregroundColor: studioInk,
              side: const BorderSide(color: studioSwatchRing),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            // One name for the whole card; the picture only illustrates it.
            child: Semantics(
              label: 'Reprendre $title, enregistré $saved',
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 3 / 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: studioSheetBackdrop,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: FutureBuilder<MemoryImage?>(
                          future: thumbnail,
                          builder: (context, snapshot) {
                            final image = snapshot.data;
                            if (image == null) {
                              return snapshot.connectionState ==
                                      ConnectionState.done
                                  ? const Icon(Icons.image_not_supported)
                                  : const SizedBox.shrink();
                            }
                            return Image(
                              image: image,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.image_not_supported),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Two lines are kept for every name, at any size of text:
                  // the cards of a row end together.
                  Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      const Text('\n', style: _nameStyle),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: _nameStyle,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    saved,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          Center(
            child: TextButton.icon(
              key: Key('gallery-forget-${entry.id}'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _remove(entry),
              icon: const Icon(Icons.close, size: 18),
              label: Text(
                'Retirer',
                semanticsLabel: 'Retirer $title de la galerie',
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return AlertDialog(
      key: const Key('galleryDialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      title: const Text('Mes dessins'),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_failed)
              Text(
                widget.opensFiles
                    ? 'La galerie ne peut pas être affichée pour le moment. Tes fichiers enregistrés ne sont pas concernés : retrouve-les avec Ouvrir.'
                    : 'La galerie ne peut pas être affichée pour le moment. Tes fichiers enregistrés ne sont pas concernés.',
                key: const Key('galleryUnavailable'),
              )
            else if (entries == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (entries.isEmpty)
              const Text(
                'Aucun dessin pour le moment. Dès que tu enregistres un dessin, il se range ici.',
                key: Key('galleryEmpty'),
              )
            else ...[
              const Text(
                'Tes dessins enregistrés sont rangés ici. Choisis-en un pour le reprendre.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [for (final entry in entries) _card(entry)],
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(16),
      actions: [
        FilledButton(
          key: const Key('closeGallery'),
          // Entrée returns to the drawing: it never replaces it by accident.
          autofocus: true,
          style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
          onPressed: () => Navigator.pop(context),
          child: const Text('Revenir au dessin'),
        ),
      ],
    );
  }
}
