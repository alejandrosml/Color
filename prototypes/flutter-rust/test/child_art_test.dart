// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/child_art.dart';
import 'package:edupaint_flutter_study/vector_art.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all artwork renders at small, control and helper sizes', (
    tester,
  ) async {
    for (final size in [24.0, 48.0, 112.0]) {
      for (final art in EduArt.values) {
        final key = UniqueKey();
        await tester.pumpWidget(
          Center(
            child: RepaintBoundary(
              key: key,
              child: EduIllustration(art: art, size: size),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$art at $size');
        expect(tester.getSize(find.byType(EduIllustration)), Size.square(size));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          expect(image.width, size.toInt());
          expect(image.height, size.toInt());
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          var painted = 0;
          var transparent = 0;
          for (var pixel = 3; pixel < bytes.lengthInBytes; pixel += 4) {
            if (bytes.getUint8(pixel) == 0) {
              transparent++;
            } else {
              painted++;
            }
          }
          expect(
            painted,
            greaterThan(size * size * .12),
            reason: '$art is visible',
          );
          expect(
            transparent,
            greaterThan(size * size * .15),
            reason: '$art has no opaque tile',
          );
          image.dispose();
        });
      }
    }
    if (const bool.fromEnvironment('EDUPAINT_ART_PREVIEW')) {
      await _writeMascotPreview(tester);
    }
  });

  testWidgets(
    'without the pictures of the core, a plain shape stands for each of them',
    (tester) async {
      // A core older than this interface has no catalogue of pictures.
      VectorArtCatalog.debugUse(null);
      addTearDown(VectorArtCatalog.debugForget);
      for (final art in [EduArt.options, EduArt.film]) {
        final key = UniqueKey();
        await tester.pumpWidget(
          Center(
            child: RepaintBoundary(
              key: key,
              child: EduIllustration(art: art, size: 28),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$art');
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          var painted = 0;
          for (var pixel = 3; pixel < bytes.lengthInBytes; pixel += 4) {
            if (bytes.getUint8(pixel) != 0) painted++;
          }
          // Never an empty place where a button is.
          expect(painted, greaterThan(28 * 28 * .2), reason: '$art');
          image.dispose();
        });
      }
    },
  );

  testWidgets('decorative art preserves only the parent action semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Semantics(
          label: 'Enregistrer mon dessin',
          button: true,
          child: const EduIllustration(art: EduArt.save),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Enregistrer mon dessin'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

/// Opt-in review artifact, drawn by the same vector painter as the application.
Future<void> _writeMascotPreview(WidgetTester tester) async {
  const key = ValueKey('mascot-preview');
  await tester.pumpWidget(
    const Center(
      child: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: Color(0xfff5f5ee),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Row(
              textDirection: TextDirection.ltr,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                EduIllustration(art: EduArt.mascot, size: 48),
                SizedBox(width: 28),
                EduIllustration(art: EduArt.mascot, size: 112),
                SizedBox(width: 28),
                EduIllustration(art: EduArt.mascot, size: 256),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final output = File('../art/mascotte-etude.png');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
  await tester.pumpWidget(
    const Center(
      child: RepaintBoundary(
        key: key,
        child: EduIllustration(art: EduArt.mascot, size: 512),
      ),
    ),
  );
  final transparent = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(key),
  );
  await tester.runAsync(() async {
    final image = await transparent.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File('../art/mascotte-edupaint.png')
        .writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}
