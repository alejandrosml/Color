// SPDX-License-Identifier: MIT
// The fonts of the pictures made by the opt-in review and store tests: the
// application's own, and Roboto in place of the system's letters, so that
// every label is read, and measured, as on a real system.
import 'dart:io';

import 'package:flutter/services.dart';

Future<void> loadReviewFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    throw StateError('FLUTTER_ROOT is needed to find the interface fonts.');
  }
  final fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final bytes = await File(path).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    '$fonts/Roboto-Regular.ttf',
    '$fonts/Roboto-Medium.ttf',
    '$fonts/Roboto-Bold.ttf',
    '$fonts/Roboto-Black.ttf',
  ]);
  // Labels without an explicit family (the buttons of the top bar) ask the
  // engine for the system's default families; the test engine answers any
  // name it does not know with its box font. Give those names real glyphs,
  // the Apple ones included for pictures made as on iPhone, iPad and Mac.
  for (final family in const [
    'FlutterTest',
    'Ubuntu',
    'Cantarell',
    'DejaVu Sans',
    'Liberation Sans',
    'Arial',
    'Helvetica',
    'Helvetica Neue',
    '.AppleSystemUIFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    'Segoe UI',
  ]) {
    await load(family, [
      '$fonts/Roboto-Regular.ttf',
      '$fonts/Roboto-Medium.ttf',
      '$fonts/Roboto-Bold.ttf',
    ]);
  }
  await load('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
  await load('ColorSans', ['fonts/DejaVuSans.ttf']);
}
