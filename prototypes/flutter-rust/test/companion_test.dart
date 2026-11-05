// SPDX-License-Identifier: MIT
// The companion that moves (Color 1.1): touched, the child sits down in the
// chair, stands up again and gives a stroke of the brush; with the option,
// it does so when the child saves. Its parts are the named groups of its
// SVG file, which the core keeps.
import 'dart:io';

import 'package:edupaint_flutter_study/companion.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/vector_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('seated, standing again, then a stroke of the brush', () {
    expect(Companion.movesAt(0), isEmpty);
    expect(Companion.movesAt(1), isEmpty);
    // Down in the seat: the upper parts lowered, the legs folded.
    final seated = Companion.movesAt(.3);
    expect(seated['face-and-hair']![13], 55);
    expect(seated['legs-and-knee-support']![5], closeTo(.65, 1e-9));
    // Standing again, the arm swings: turned, not moved down.
    final painting = Companion.movesAt(.8);
    expect(painting['face-and-hair']![13], 0);
    final arm = painting['raised-arm-and-brush']!;
    expect(arm[1], isNot(0), reason: 'a turn');
    expect(Companion.movesAt(.99)['raised-arm-and-brush']![1], closeTo(0, .05));
  });

  test('the picture keeps the parts that move', () {
    final picture = VectorArtCatalog.instance!['mascotte']!;
    expect(
      picture.parts,
      containsAll([
        'chair-back-and-headrest',
        'raised-arm-and-brush',
        'legs-and-knee-support',
        'shirt-and-chest-support',
        'face-and-hair',
        'armrest-hand-and-joystick',
      ]),
    );
  }, skip: !available);

  testWidgets('touched, it moves; with the option, saving moves it too', (
    tester,
  ) async {
    final files = MemoryFiles()..savePath = '/drawings/Bonjour.edupaint';
    final store = StudioOptionsStore.memory();
    final studio = StudioDriver(tester, files: files, options: store);
    await studio.start();
    final companion = find.byKey(const Key('companion'));
    expect(companion, findsWidgets);
    final before = Companion.debugPlays;
    await tester.tap(companion.first);
    await tester.pump();
    expect(Companion.debugPlays, before + 1);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pump(Companion.duration);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    // Whether saving moves it: the save goes on outside the frames, and the
    // companion moves once it is done, for longer than these frames.
    Future<bool> movesWhenSaving() async {
      final before = Companion.debugPlays;
      await studio.tap('saveProject');
      return Companion.debugPlays > before;
    }

    // Still without the option…
    await studio.drag(studio.at(100, 100), studio.at(300, 200));
    expect(await movesWhenSaving(), isFalse);
    expect(files.projects['/drawings/Bonjour.edupaint'], isNotNull);
    // …and it stands up and paints with it.
    store.value = store.value.copyWith(companionReacts: true);
    await tester.pumpAndSettle();
    await studio.drag(studio.at(300, 300), studio.at(500, 300));
    expect(await movesWhenSaving(), isTrue);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);
}
