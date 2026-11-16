// SPDX-License-Identifier: MIT
// Run before the tests of every file: they are written in French, the
// language Color is written in, whatever the language of the machine that
// runs them. The test of the languages chooses English where it says so.
import 'dart:async';

import 'package:edupaint_flutter_study/decor_view.dart';
import 'package:edupaint_flutter_study/language.dart';
import 'package:edupaint_flutter_study/studio_colors.dart';
import 'package:flutter_test/flutter_test.dart';

/// The hour of every decor in the tests: half past two in the afternoon of
/// a day of November — the day, by the window of the desk. A picture of the
/// studio is the same whenever the tests run; a test of the hours gives its
/// own clock.
final testDecorTime = DateTime(2026, 11, 12, 14, 30);

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugDeviceLanguage = AppLanguage.french;
  setUp(() {
    appLanguage.value = AppLanguage.french;
    // Every test begins in « Classique », at the same hour, and with a
    // decor that stands still: one that moves never lets a test settle.
    // The tests of the movement and of the hours say otherwise.
    studioLook.value = StudioLook.classic;
    debugDecorNow = () => testDecorTime;
    debugDecorStill = true;
  });
  await testMain();
}
