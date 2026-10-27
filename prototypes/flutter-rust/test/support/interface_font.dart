// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The letters of the interface, in place of the test font whose every glyph
/// is a square: DejaVu Sans, shipped with the project, under the names that
/// the theme asks for on Linux, on the Mac and on Windows. Wider than the
/// system fonts of the Mac and of Windows, it is a prudent stand-in for
/// them. Once loaded it serves every later test of the same file.
Future<void> loadInterfaceFont(WidgetTester tester) =>
    tester.runAsync(() async {
      final bytes = await File('fonts/DejaVuSans.ttf').readAsBytes();
      for (final family in ['Roboto', '.AppleSystemUIFont', 'Segoe UI']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
    });
