// SPDX-License-Identifier: MIT
// Run before the tests of every file: they are written in French, the
// language Color is written in, whatever the language of the machine that
// runs them. The test of the languages chooses English where it says so.
import 'dart:async';

import 'package:edupaint_flutter_study/language.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugDeviceLanguage = AppLanguage.french;
  setUp(() => appLanguage.value = AppLanguage.french);
  await testMain();
}
