// SPDX-License-Identifier: MIT
// The printing of the system, in memory: what Color hands over is kept, and
// the test decides what the panel answers. Nothing is ever printed.
import 'dart:async';
import 'dart:typed_data';

import 'package:edupaint_flutter_study/studio_printer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One image handed to the panel of the system.
class PrintRequest {
  PrintRequest(this.rgba, this.width, this.height, this.jobName);
  final Uint8List rgba;
  final int width;
  final int height;
  final String jobName;

  /// Red, green, blue and alpha of the pixel at ([x], [y]) of the image.
  List<int> pixel(int x, int y) {
    final offset = (y * width + x) * 4;
    return rgba.sublist(offset, offset + 4);
  }
}

class FakePrinter {
  final requests = <PrintRequest>[];

  /// What the panel answers when it closes.
  PrintOutcome outcome = PrintOutcome.sent;

  /// What the system throws instead, when set.
  Object? failure;

  /// While set and not completed, the panel stays open.
  Completer<void>? panel;

  Future<PrintOutcome> call({
    required Uint8List rgba,
    required int width,
    required int height,
    required String jobName,
  }) async {
    requests.add(PrintRequest(rgba, width, height, jobName));
    final open = panel;
    if (open != null) await open.future;
    final thrown = failure;
    if (thrown != null) throw thrown;
    return outcome;
  }
}

/// Presses a control that prints and waits until the image has reached the
/// printer: the engine prepares it outside the fake clock of a widget test.
/// [press] defaults to a tap on the control whose key is [key].
Future<void> printAndWait(
  WidgetTester tester,
  FakePrinter printer, {
  String key = 'printDrawing',
  Future<void> Function()? press,
}) async {
  final before = printer.requests.length;
  if (press != null) {
    await press();
  } else {
    final control = find.byKey(Key(key));
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
  }
  for (
    var attempt = 0;
    attempt < 400 && printer.requests.length == before;
    attempt++
  ) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(
    printer.requests.length,
    before + 1,
    reason: 'The image never reached the printer.',
  );
  // With the panel closed at once, the studio is free again; with a panel
  // held open nothing moves on the screen, and this returns as well.
  await tester.pumpAndSettle();
}
