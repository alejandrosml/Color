// SPDX-License-Identifier: MIT
// P-04 of the retrospective of October 2026: the functions that Dart looks
// up in the core, those that its header declares, and those that the
// program of the iPhone and the iPad exports are the same; a core that
// misses one is refused when it is first opened.
import 'dart:ffi';
import 'dart:io';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// The header of the core: in the sources, beside the application. A recipe
/// that tests a copy of the application kept elsewhere (the Mac's,
/// scripts/build-flutter-study.py) names it in EDUPAINT_CORE_HEADER.
File _header() => File(
  Platform.environment['EDUPAINT_CORE_HEADER'] ??
      '../native-swift-rust/core/include/edupaint_core.h',
);

Set<String> _declared() {
  final header = _header().readAsStringSync();
  // Outside comments, a name of the core followed by a parenthesis is a
  // declaration.
  final code = header.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return {
    for (final match in RegExp(
      r'(?<![A-Za-z0-9_])(ep_[A-Za-z0-9_]+)\s*\(',
    ).allMatches(code))
      match[1]!,
  };
}

void main() {
  final library = Platform.environment['EDUPAINT_CORE_LIBRARY'];

  test('Dart, the header and the program of the iPhone name the same '
      'functions', () {
    final declared = _declared();
    expect(declared, hasLength(68));
    expect(coreFunctionNames.toSet(), declared);
    expect(coreFunctionNames, hasLength(declared.length));
    // Every function that the bindings look up is one of them.
    final bindings = File('lib/rust_document.dart').readAsStringSync();
    final looked = {
      for (final match in RegExp(
        r">\('(ep_[a-z_0-9]+)'\)",
      ).allMatches(bindings))
        match[1]!,
    };
    expect(looked, isNotEmpty);
    expect(declared.containsAll(looked), isTrue, reason: '$looked');
    final exported = File('ios/Runner/core-symbols.txt')
        .readAsLinesSync()
        .where((line) => line.isNotEmpty)
        .toList();
    expect(exported.toSet(), {for (final name in declared) '_$name'});
    expect(exported, hasLength(declared.length));
  });

  test('a core misses none of them', () {
    expect(missingCoreFunctions(DynamicLibrary.open(library!)), isEmpty);
    expect(() => openCoreLibrary(library), returnsNormally);
  }, skip: library == null);

  test('a library that is not the core is refused when it is opened', () {
    // The C library of the system: none of the functions of the core.
    final other = Platform.isLinux ? 'libc.so.6' : null;
    if (other == null) return;
    expect(missingCoreFunctions(DynamicLibrary.open(other)), coreFunctionNames);
    expect(
      () => openCoreLibrary(other),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('ep_document_new'),
        ),
      ),
    );
    // And again: a refused library is not taken for a checked one.
    expect(() => openCoreLibrary(other), throwsStateError);
  }, skip: !Platform.isLinux);
}
