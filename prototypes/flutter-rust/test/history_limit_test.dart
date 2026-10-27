// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'more than ten thousand edits remain synchronized through undo and redo',
    () {
      final document = RustDocument();
      try {
        document.addStroke(
          const [DocumentPoint(10, 10), DocumentPoint(20, 20)],
          rgb: 0,
          width: 4,
        );
        for (var index = 1; index <= 10000; index++) {
          expect(document.setObjectStyle(0, rgb: index, width: 4), isTrue);
        }
        // One insertion and 10,000 edits exceed the object-count limit while
        // remaining well within the native limit of 50,000 history commands.
        expect(document.count, 1);
        expect(document.strokes.single.rgb, 10000);
        expect(document.canUndo, isTrue);
        expect(document.canRedo, isFalse);
        final edited = document.exportSvg();
        for (var index = 10000; index > 0; index--) {
          expect(document.undo(), isTrue);
          expect(document.strokes.single.rgb, index - 1);
        }
        expect(document.undo(), isTrue);
        expect(document.count, 0);
        expect(document.canUndo, isFalse);
        expect(document.canRedo, isTrue);
        expect(document.undo(), isFalse);
        for (var index = 0; index <= 10000; index++) {
          expect(document.redo(), isTrue);
          expect(document.strokes.single.rgb, index);
        }
        expect(document.canUndo, isTrue);
        expect(document.canRedo, isFalse);
        expect(document.redo(), isFalse);
        expect(document.exportSvg(), edited);
      } finally {
        document.dispose();
      }
    },
    skip: Platform.environment['EDUPAINT_CORE_LIBRARY'] == null,
  );
}
