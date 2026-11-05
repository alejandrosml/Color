// SPDX-License-Identifier: MIT
// The slideshow of « Mes dessins » (Color 1.1): the pictures of the album
// one after the other, the whole screen for each, as a child shows them to
// the family. Nothing is opened, nothing changes: it only looks.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gallery_dialog.dart' show cardTitle, isThumbnailPng;
import 'gallery_storage.dart';
import 'studio_colors.dart';
import 'language.dart';

/// Shows [entries] from [start], a picture every [every].
Future<void> showSlideshow(
  BuildContext context, {
  required GalleryStorage storage,
  required List<GalleryEntry> entries,
  int start = 0,
  Duration every = const Duration(seconds: 4),
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.black,
  builder: (_) =>
      Slideshow(storage: storage, entries: entries, start: start, every: every),
);

class Slideshow extends StatefulWidget {
  const Slideshow({
    super.key,
    required this.storage,
    required this.entries,
    this.start = 0,
    this.every = const Duration(seconds: 4),
  });
  final GalleryStorage storage;
  final List<GalleryEntry> entries;
  final int start;
  final Duration every;

  @override
  State<Slideshow> createState() => _SlideshowState();
}

class _SlideshowState extends State<Slideshow> {
  late int _index = widget.start.clamp(0, widget.entries.length - 1);
  bool _playing = true;
  Timer? _timer;
  final _pictures = <String, Future<MemoryImage?>>{};
  final _decoded = <MemoryImage>[];

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final image in _decoded) {
      image.evict();
    }
    super.dispose();
  }

  // The next picture comes a whole interval after the last change, whoever
  // made it: a press on « Suivant » is never followed by a jump at once.
  void _restart() {
    _timer?.cancel();
    if (!_playing || widget.entries.length < 2) return;
    _timer = Timer(widget.every, () {
      if (mounted) _go(1);
    });
  }

  void _go(int step) {
    final count = widget.entries.length;
    setState(() => _index = (_index + step) % count);
    _restart();
  }

  void _togglePlaying() {
    setState(() => _playing = !_playing);
    _restart();
  }

  Future<MemoryImage?> _picture(GalleryEntry entry) =>
      _pictures.putIfAbsent(entry.id, () async {
        try {
          final bytes = await widget.storage.readThumbnail(entry);
          if (!isThumbnailPng(bytes)) return null;
          final image = MemoryImage(bytes);
          if (mounted) _decoded.add(image);
          return image;
        } catch (_) {
          return null;
        }
      });

  @override
  Widget build(BuildContext context) {
    final entry = widget.entries[_index];
    final several = widget.entries.length > 1;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.space): _togglePlaying,
      },
      child: Dialog.fullscreen(
        key: const Key('slideshow'),
        backgroundColor: Colors.black,
        child: Focus(
          autofocus: true,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FutureBuilder<MemoryImage?>(
                      key: ValueKey(entry.id),
                      future: _picture(entry),
                      builder: (context, snapshot) {
                        final image = snapshot.data;
                        if (image == null) {
                          return snapshot.connectionState ==
                                  ConnectionState.done
                              ? const Icon(
                                  Icons.image_not_supported,
                                  color: Colors.white54,
                                  size: 64,
                                )
                              : const SizedBox.shrink();
                        }
                        return Semantics(
                          image: true,
                          label: cardTitle(entry.name),
                          child: Image(
                            image: image,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.image_not_supported,
                              color: Colors.white54,
                              size: 64,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Text(
                  cardTitle(entry.name),
                  key: const Key('slideshowTitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (several) ...[
                        _button(
                          key: 'slideshowPrevious',
                          icon: Icons.skip_previous,
                          label: tr('Précédent'),
                          onPressed: () => _go(-1),
                        ),
                        _button(
                          key: 'slideshowPause',
                          icon: _playing ? Icons.pause : Icons.play_arrow,
                          label: _playing ? tr('Pause') : tr('Reprendre'),
                          onPressed: _togglePlaying,
                        ),
                        _button(
                          key: 'slideshowNext',
                          icon: Icons.skip_next,
                          label: tr('Suivant'),
                          onPressed: () => _go(1),
                        ),
                      ],
                      _button(
                        key: 'closeSlideshow',
                        icon: Icons.close,
                        label: tr('Fermer'),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button({
    required String key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => FilledButton.tonalIcon(
    key: Key(key),
    style: FilledButton.styleFrom(
      minimumSize: const Size(112, 52),
      backgroundColor: studioSurface,
      foregroundColor: studioInk,
    ),
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
  );
}
