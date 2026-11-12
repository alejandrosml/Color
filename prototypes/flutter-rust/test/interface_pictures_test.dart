// SPDX-License-Identifier: MIT
// Every picture of the interface is an SVG file of the core (Color 1.1):
// the eighteen that Dart drew before are written in files, shape for shape,
// and each file must draw what the Dart drawing drew — the drawing stays,
// for a core that has no catalogue. Pixel for pixel, but for the edges of
// the shapes, which two engines smooth a little differently.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/child_art.dart';
import 'package:edupaint_flutter_study/vector_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 128;

Future<Uint8List> _drawn(WidgetTester tester, EduArt art) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: Colors.white,
            child: EduIllustration(art: art, size: _size.toDouble()),
          ),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  });
  return bytes!;
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  testWidgets('each SVG file draws what Dart drew', (tester) async {
    final catalogue = VectorArtCatalog.instance;
    expect(catalogue, isNotNull);
    // Made as files from the start: they have no Dart drawing to match.
    const madeAsFiles = {
      EduArt.mascot,
      EduArt.options,
      EduArt.film,
      EduArt.magic,
      EduArt.shapes,
      EduArt.magnet,
      EduArt.universes,
    };
    for (final art in EduArt.values) {
      expect(catalogue!.keys, contains(art.svgKey), reason: art.name);
    }
    try {
      for (final art in EduArt.values) {
        if (madeAsFiles.contains(art)) continue;
        VectorArtCatalog.debugUse(catalogue);
        final fromFile = await _drawn(tester, art);
        VectorArtCatalog.debugUse(null);
        final fromDart = await _drawn(tester, art);
        expect(fromFile.length, fromDart.length);
        var differing = 0;
        var worst = 0;
        for (var i = 0; i < fromFile.length; i += 4) {
          var pixel = 0;
          for (var channel = 0; channel < 3; channel++) {
            final difference = (fromFile[i + channel] - fromDart[i + channel])
                .abs();
            if (difference > pixel) pixel = difference;
          }
          if (pixel > 24) differing++;
          if (pixel > worst) worst = pixel;
        }
        // Something is drawn: a picture, not an empty square.
        var inked = 0;
        for (var i = 0; i < fromDart.length; i += 4) {
          if (fromDart[i] < 200 || fromDart[i + 1] < 200) inked++;
        }
        expect(inked, greaterThan(_size * _size ~/ 10), reason: art.name);
        // At most one pixel in a hundred beyond a slight shade, on the
        // edges: the shapes, their colours and their lines are the same.
        expect(
          differing,
          lessThan(_size * _size ~/ 100),
          reason: '${art.name}: $differing pixels differ, up to $worst',
        );
      }
    } finally {
      VectorArtCatalog.debugForget();
    }
  }, skip: !available);
}
