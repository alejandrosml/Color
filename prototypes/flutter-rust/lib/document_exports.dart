// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'rust_document.dart';

// Provisional scheduling budgets, not universal performance crossover points.
// The 2026-09-24 Mac AOT measurements showed cheap synchronous project exports
// up to 400 KB of tested rectangles, and worker benefits for larger SVG scenes.
// These smaller budgets deliberately retain headroom. Other point distributions,
// platforms, disk writes and downstream UI copies were not established by that
// benchmark. An embedded image always takes the worker path, even if tiny.
const _synchronousProjectBudget = 256 * 1024;
const _synchronousSvgBudget = 4 * 1024;

/// Whether project preparation uses an immutable snapshot and a worker isolate.
bool projectExportUsesWorker(RustDocument document) =>
    document.backgroundInfo != null ||
    document.projectByteLength > _synchronousProjectBudget;

/// Uses project size as a bounded scheduling proxy, not as the SVG output size.
bool svgExportUsesWorker(RustDocument document) =>
    document.backgroundInfo != null ||
    document.projectByteLength > _synchronousSvgBudget;

/// Captures the current visible state during this call, before any await.
/// Subsequent document edits or disposal cannot change the resulting bytes.
Future<Uint8List> prepareProjectBytes(RustDocument document) => Future.sync(() {
  if (!projectExportUsesWorker(document)) {
    return document.exportProject();
  }
  return document.exportProjectAsync();
});

/// Returns ready-to-write UTF-8 bytes; the worker avoids a large UI-side String.
/// Capture happens during this call, with the same lifetime as project exports.
Future<Uint8List> prepareSvgBytes(RustDocument document) => Future.sync(() {
  if (!svgExportUsesWorker(document)) {
    return Uint8List.fromList(utf8.encode(document.exportSvg()));
  }
  return document.exportSvgBytesAsync();
});
