// SPDX-License-Identifier: MIT
// The slideshow of « Mes dessins » (Color 1.1): the drawings of the album one
// after the other, the latest first, by themselves or with the buttons; it
// opens nothing and changes nothing.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_gallery.dart';
import 'support/studio_driver.dart';

// One yellow pixel, a picture of the album as small as can be.
final _picture = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00,
  0x0c, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x78, 0xb7, 0xdf, 0x0f,
  0x00, 0x04, 0x9a, 0x01, 0xfc, 0x68, 0x44, 0x97, 0xe8, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  String shown(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('slideshowTitle'))).data!;

  testWidgets('the slideshow shows the drawings one after the other', (
    tester,
  ) async {
    final gallery = MemoryGallery();
    for (final (name, day) in [('Un', 1), ('Deux', 2), ('Trois', 3)]) {
      await gallery.remember(
        sourcePath: '/drawings/$name.edupaint',
        name: '$name.edupaint',
        project: Uint8List(0),
        thumbnailPng: _picture,
        width: 1200,
        height: 800,
        elementCount: 1,
        savedAt: DateTime.utc(2026, 11, day),
      );
    }
    final studio = StudioDriver(tester, gallery: gallery);
    await studio.start();
    await studio.tap('openGallery');
    await studio.tap('gallerySlideshow');
    expect(find.byKey(const Key('slideshow')), findsOneWidget);
    // The latest first, then the buttons, both ways and around.
    expect(shown(tester), 'Trois');
    await studio.tap('slideshowNext');
    expect(shown(tester), 'Deux');
    await studio.tap('slideshowPrevious');
    await studio.tap('slideshowPrevious');
    expect(shown(tester), 'Un');
    // By itself, a picture every four seconds after the last change.
    await tester.pump(const Duration(seconds: 3));
    expect(shown(tester), 'Un');
    await tester.pump(const Duration(seconds: 1));
    expect(shown(tester), 'Trois');
    // Paused, it waits.
    await studio.tap('slideshowPause');
    await tester.pump(const Duration(seconds: 12));
    expect(shown(tester), 'Trois');
    await studio.tap('closeSlideshow');
    expect(find.byKey(const Key('slideshow')), findsNothing);
    expect(find.byKey(const Key('galleryDialog')), findsOneWidget);
    await studio.tap('closeGallery');
    // Nothing was opened, nothing changed.
    studio.expectCount(0);
    expect(studio.isDirty, isFalse);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);
}
