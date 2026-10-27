// SPDX-License-Identifier: MIT
// The actions on a chosen element, measured with the test font on purpose:
// its square letters are wider than any real ones, the hardest case for a
// line of written buttons.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_gallery.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  testWidgets(
    'the actions on a chosen text stand on two lines rather than leave the window',
    (tester) async {
      final studio = StudioDriver(tester, gallery: MemoryGallery());
      // Narrow and tall: spacious controls in a narrow column.
      await studio.start(size: const Size(700, 900));
      await studio.addText('Mot');
      await studio.tap('tool-select');
      await studio.click();
      expect(tester.takeException(), isNull);
      final keys = [
        'selectionOrder',
        'editSelectionText',
        'duplicateSelection',
        'deleteSelection',
        'shrinkSelection',
        'growSelection',
      ];
      for (final width in [700.0, 760.0, 820.0, 900.0, 1000.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$width');
        final rects = <Rect>[];
        for (final key in keys) {
          final rect = tester.getRect(find.byKey(Key(key)));
          expect(rect.left, greaterThanOrEqualTo(0), reason: '$key $width');
          expect(rect.right, lessThanOrEqualTo(width), reason: '$key $width');
          expect(rect.height, greaterThanOrEqualTo(48), reason: '$key $width');
          expect(rect.width, greaterThanOrEqualTo(48), reason: '$key $width');
          for (final other in rects) {
            expect(
              rect.overlaps(other.deflate(.5)),
              isFalse,
              reason: '$key overlaps another action at $width',
            );
          }
          rects.add(rect);
        }
        // The sentence beside them keeps room for its words.
        final hint = find.textContaining('Glisse pour déplacer');
        expect(hint, findsOneWidget);
        expect(tester.getSize(hint).width, greaterThanOrEqualTo(100));
      }
      await studio.finish();
    },
    skip: !available,
  );
}
