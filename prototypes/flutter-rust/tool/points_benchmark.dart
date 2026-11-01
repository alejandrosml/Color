// SPDX-License-Identifier: MIT
// Separate, manually started measurement of D-01. Never imported by main.
// Plain Dart, without Flutter: the document binding does not need it.
//
//   dart compile exe tool/points_benchmark.dart -o points_benchmark
//   EDUPAINT_CORE_LIBRARY=…/libedupaint_core.so ./points_benchmark make d.color
//   EDUPAINT_CORE_LIBRARY=…/libedupaint_core.so ./points_benchmark open d.color
//
// « make » writes one drawing of a million points (1 000 traits of 1 000
// points). « open », in a fresh process, opens it a number of times and reads
// its elements, as the studio does after an opening, and prints one line of
// JSON: the time of each opening, then how much the process grew while the
// elements of a single opening were kept.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:edupaint_flutter_study/rust_document.dart';

const _traits = 1000;
const _pointsPerTrait = 1000;
const _openings = 15;

void main(List<String> arguments) {
  if (arguments.length != 2 || !const {'make', 'open'}.contains(arguments[0])) {
    stderr.writeln('points_benchmark make|open <projet>');
    exitCode = 2;
    return;
  }
  final library = Platform.environment['EDUPAINT_CORE_LIBRARY'];
  final file = File(arguments[1]);
  if (arguments[0] == 'make') {
    final made = RustDocument(libraryPath: library, width: 1920, height: 1200);
    final random = math.Random(7);
    for (var trait = 0; trait < _traits; trait++) {
      var x = random.nextDouble() * 1900 + 10;
      var y = random.nextDouble() * 1180 + 10;
      final points = <DocumentPoint>[];
      for (var index = 0; index < _pointsPerTrait; index++) {
        x = (x + random.nextDouble() * 6 - 3).clamp(0, 1920).toDouble();
        y = (y + random.nextDouble() * 6 - 3).clamp(0, 1200).toDouble();
        points.add(DocumentPoint(x, y));
      }
      made.addStroke(points, rgb: random.nextInt(0x1000000), width: 6);
    }
    file.writeAsBytesSync(made.exportProject(), flush: true);
    made.dispose();
    return;
  }

  final project = file.readAsBytesSync();
  // The process before any opening, then holding one opening's elements.
  final before = ProcessInfo.currentRss;
  final kept = RustDocument.fromProject(project, libraryPath: library);
  final keptStrokes = kept.strokes;
  final holding = ProcessInfo.currentRss;
  var points = 0;
  for (final stroke in keptStrokes) {
    points += stroke.points.length;
  }

  final micros = <int>[];
  for (var opening = 0; opening < _openings; opening++) {
    final watch = Stopwatch()..start();
    final document = RustDocument.fromProject(project, libraryPath: library);
    final strokes = document.strokes;
    watch.stop();
    if (strokes.length != _traits) throw StateError('Ouverture incomplète.');
    micros.add(watch.elapsedMicroseconds);
    document.dispose();
  }
  kept.dispose();
  stdout.writeln(
    jsonEncode({
      'points': points,
      'projectBytes': project.length,
      'openingMicros': micros,
      'rssGrowthBytes': holding - before,
    }),
  );
}
