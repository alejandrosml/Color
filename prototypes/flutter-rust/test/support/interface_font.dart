// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The letters of the interface, in place of the test font whose every glyph
/// is a square. Since Color 1.2 the interface is written in Atkinson
/// Hyperlegible, which the application carries: the very font, with its
/// bold. DejaVu Sans stays under the names of the system fonts of Linux,
/// of the Mac and of Windows, for what a system still writes itself. Once
/// loaded they serve every later test of the same file.
Future<void> loadInterfaceFont(WidgetTester tester) =>
    tester.runAsync(() async {
      final bytes = await File('fonts/DejaVuSans.ttf').readAsBytes();
      for (final family in ['Roboto', '.AppleSystemUIFont', 'Segoe UI']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
      final own = FontLoader('ColorAtkinson');
      for (final file in [
        'fonts/AtkinsonHyperlegible.ttf',
        'fonts/AtkinsonHyperlegible-Bold.ttf',
      ]) {
        final face = await File(file).readAsBytes();
        own.addFont(Future.value(ByteData.sublistView(face)));
      }
      await own.load();
    });
