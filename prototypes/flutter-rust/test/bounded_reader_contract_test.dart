// SPDX-License-Identifier: MIT
import 'package:edupaint_flutter_study/project_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bounded_reader_contracts.dart';

void main() {
  for (final scenario in boundedReadCases) {
    test('bounded reader: ${scenario.name}', () async {
      await runBoundedReadCase(ProjectStorage.readBoundedBytes, scenario);
    });
  }
}
