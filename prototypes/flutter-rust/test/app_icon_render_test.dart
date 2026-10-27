// SPDX-License-Identifier: MIT
// Opt-in tool: draws an icon tile from the studio's own brush, the one beside
// the name in the header.
//
//   COLOR_ICON_DIR=/absolute/output flutter test test/app_icon_render_test.dart
//
// Without that variable the test is skipped and writes nothing. It made the
// Linux icons up to 0.7.1. Since 0.7.2 every icon of Color — macOS, Windows,
// Linux — comes from the logo the owner chose, by
// scripts/icons/fabriquer-les-icones.py; this file is kept as a tool.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/child_art.dart';
import 'package:edupaint_flutter_study/studio_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tile of the icon, [side] pixels wide: a rounded sheet in the colour of
/// the studio's banner, the brush in its middle.
class ColorIconTile extends StatelessWidget {
  const ColorIconTile({super.key, required this.side});
  final double side;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: side,
    child: Padding(
      // The margin that desktop icon themes leave around a tile.
      padding: EdgeInsets.all(side * 0.04),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: studioBanner,
          borderRadius: BorderRadius.circular(side * 0.2),
          border: Border.all(
            color: studioTitle.withValues(alpha: 0.35),
            width: side / 64,
          ),
        ),
        child: Center(
          child: EduIllustration(art: EduArt.brush, size: side * 0.68),
        ),
      ),
    ),
  );
}

void main() {
  final output = Platform.environment['COLOR_ICON_DIR'];
  const boundaryKey = ValueKey('icon-boundary');

  testWidgets('the icon of the desktop entry is drawn from the brush', (
    tester,
  ) async {
    final folder = Directory(output!)..createSync(recursive: true);
    for (final side in const [16, 32, 48, 64, 128, 256, 512]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size.square(side.toDouble());
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: boundaryKey,
            child: ColorIconTile(side: side.toDouble()),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final bytes = await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage();
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          return data!.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      });
      File('${folder.path}/color-$side.png').writeAsBytesSync(bytes!);
      expect(tester.takeException(), isNull);
    }
  }, skip: output == null);
}
