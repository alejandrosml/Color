// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import 'stamp_catalog.dart';
import 'studio_colors.dart';

/// A catalogue stamp drawn at any size, tinted with the current colour.
class StampPreview extends StatelessWidget {
  const StampPreview({
    super.key,
    required this.stamp,
    required this.rgb,
    this.size = 56,
  });
  final StampArt stamp;
  final int rgb;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _StampPainter(stamp, rgb)),
      ),
    ),
  );
}

class _StampPainter extends CustomPainter {
  const _StampPainter(this.stamp, this.rgb);
  final StampArt stamp;
  final int rgb;

  @override
  void paint(Canvas canvas, Size size) =>
      stamp.paint(canvas, Offset.zero & size, rgb);

  @override
  bool shouldRepaint(_StampPainter old) =>
      old.stamp.id != stamp.id || old.rgb != rgb;
}

/// Returns the chosen catalogue identifier, or null when cancelled.
Future<int?> showStampDialog(
  BuildContext context, {
  required StampCatalog catalog,
  required int selected,
  required int rgb,
}) => showDialog<int>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    key: const Key('stampDialog'),
    scrollable: true,
    insetPadding: const EdgeInsets.all(16),
    title: const Text('Choisis un tampon'),
    content: SizedBox(
      width: 560,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final stamp in catalog.stamps)
            OutlinedButton(
              key: Key('stamp-${stamp.key}'),
              autofocus: stamp.id == selected,
              onPressed: () => Navigator.pop(dialogContext, stamp.id),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(104, 104),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                backgroundColor: stamp.id == selected
                    ? studioSelected
                    : Colors.white,
                side: BorderSide(
                  color: stamp.id == selected ? studioGreen : studioLine,
                  width: stamp.id == selected ? 2 : 1,
                ),
              ),
              // One name on the button itself, which keeps its own action:
              // the picture and the written name under it only decorate.
              child: Semantics(
                label: 'Tampon ${stamp.label}',
                selected: stamp.id == selected,
                excludeSemantics: true,
                child: SizedBox(
                  width: 92,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StampPreview(stamp: stamp, rgb: rgb, size: 60),
                      const SizedBox(height: 6),
                      Text(
                        stamp.label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    actionsPadding: const EdgeInsets.all(16),
    actions: [
      TextButton(
        key: const Key('cancelStamp'),
        style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Annuler'),
      ),
    ],
  ),
);
