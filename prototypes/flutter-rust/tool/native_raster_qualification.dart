// SPDX-License-Identifier: MIT
// Dedicated qualification entrypoint. Never imported by the product UI.
// Build explicitly with --target=tool/native_raster_qualification.dart.
// COLOR_IMPORT_FIXTURES accepts an absolute directory or assets:<asset-prefix>.
// Add those assets only to the dedicated staging pubspec, never the product's.
// COLOR_IMPORT_REPORT optionally selects an absolute JSON file; the default is
// inside this app's sandbox temporary directory and is displayed in the window.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/native_diagnostics.dart';
import 'package:edupaint_flutter_study/native_exit.dart';
import 'package:edupaint_flutter_study/raster_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _fixtureLocation = String.fromEnvironment(
  'COLOR_IMPORT_FIXTURES',
  defaultValue: 'assets:test/fixtures/raster',
);
const _reportLocation = String.fromEnvironment('COLOR_IMPORT_REPORT');
const _diagnostics = MethodChannel('org.edupaint/diagnostics');
const _accepted = {
  'valid',
  'synthetic_metadata',
  'color_profile',
  'qualification',
};
const _realMacFixture = 'macos-release-rgba16.png';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _QualificationApp());
}

class _QualificationApp extends StatefulWidget {
  const _QualificationApp();
  @override
  State<_QualificationApp> createState() => _QualificationAppState();
}

class _QualificationAppState extends State<_QualificationApp> {
  String _message = 'Préparation de la qualification native…';
  String? _reportPath;
  int _completed = 0;
  int _total = 0;
  int? _resultCode;

  @override
  void initState() {
    super.initState();
    installNativeExitHandler(
      () async => _resultCode == null
          ? ui.AppExitResponse.cancel
          : ui.AppExitResponse.exit,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  @override
  void dispose() {
    clearNativeExitHandler();
    clearNativeDiagnostics();
    super.dispose();
  }

  Future<void> _run() async {
    final watch = Stopwatch()..start();
    final runId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    final report = <String, Object?>{
      'schema': 1,
      'status': 'in_progress',
      'run_id': runId,
      'started_at_utc': DateTime.now().toUtc().toIso8601String(),
      'scope':
          'Dedicated native Flutter target; real codecs and renderer. '
          'No product UI automation or claim of other-platform qualification.',
      'build_mode': kReleaseMode
          ? 'release'
          : (kProfileMode ? 'profile' : 'debug'),
      'operating_system': Platform.operatingSystem,
      'operating_system_version': Platform.operatingSystemVersion,
      'dart_version': Platform.version,
      'fixture_location': _fixtureLocation,
      'backend': 'Not inferred from image.colorSpace; retain native engine launch logs.',
      'checks_use_assert': false,
      'source_integrity':
          'Manifest byte lengths checked; expected SHA-256 values '
          'are recorded, not recomputed by this harness.',
    };
    final results = <Map<String, Object?>>[];
    report['fixtures'] = results;
    String? destination;
    var code = 1;
    try {
      destination = _reportLocation.isEmpty
          ? '${Directory.systemTemp.path}/Color-native-raster-qualification/result.json'
          : _reportLocation;
      _require(
        File(destination).isAbsolute,
        'The report path must be absolute.',
      );
      if (mounted) setState(() => _reportPath = destination);
      await _writeReport(destination, report);
      await installNativeDiagnostics();
      Map<String, Object?>? diagnosticConfig;
      try {
        diagnosticConfig = await _diagnostics.invokeMapMethod<String, Object?>(
          'configure',
        );
      } catch (error) {
        report['diagnostics_unavailable'] = error.toString();
      }
      report['native_diagnostics'] = diagnosticConfig;
      final manifestBytes = await _readFixture(
        'manifest.json',
        maximumBytes: 1024 * 1024,
      );
      final manifest =
          jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
      _require(manifest['schema'] == 1, 'Unsupported fixture manifest schema.');
      final entries = (manifest['fixtures'] as List)
          .cast<Map<String, dynamic>>();
      _require(
        entries.isNotEmpty && entries.length <= 128,
        'Invalid fixture count.',
      );
      final cases = <Map<String, dynamic>>[
        ...entries,
        {
          'file': _realMacFixture,
          'category': 'qualification',
          'expectation': 'authentic macOS release RGBA16 -> canonical sRGB8',
          'bytes': 91715,
          'display_size': [2400, 1600],
          'sha256': 'eb7737b0aad4fa9b9c873dd63a3b704b161aab24db7df5a69f8574538b9298c3',
          'outside_generated_manifest': true,
        },
      ];
      report['manifest_source'] = manifest['source'];
      report['reference_toolchain'] = manifest['toolchain'];
      report['fixture_count'] = cases.length;
      if (mounted) setState(() => _total = cases.length);
      // The importer has a global single-operation guard. Never parallelize cases
      // or reopen while normalization is still in progress.
      for (var index = 0; index < cases.length; index++) {
        final fixture = cases[index];
        final name = fixture['file'] as String;
        if (mounted) setState(() => _message = 'Vérification : $name');
        recordNativeDiagnostics('qualification-start:$runId:$index');
        results.add(await _qualifyFixture(fixture));
        recordNativeDiagnostics('qualification-end:$runId:$index');
        if (mounted) setState(() => _completed = index + 1);
        await WidgetsBinding.instance.endOfFrame;
      }
      if (diagnosticConfig?['enabled'] == true &&
          diagnosticConfig?['path'] is String) {
        await _collectDiagnostics(
          diagnosticConfig!['path']! as String,
          runId,
          results,
          report,
        );
      }
      final failures = results
          .where((entry) => entry['status'] == 'failed')
          .length;
      code = failures == 0 ? 0 : 1;
      report['passed'] = results.length - failures;
      report['failed'] = failures;
      report['status'] = code == 0 ? 'passed' : 'failed';
    } catch (error, stack) {
      report['status'] = 'failed';
      report['fatal_error'] = error.toString();
      report['fatal_stack'] = stack.toString();
    } finally {
      report['elapsed_microseconds'] = watch.elapsedMicroseconds;
      report['finished_at_utc'] = DateTime.now().toUtc().toIso8601String();
      report['exit_code'] = code;
      report['process_left_open'] = true;
      if (destination != null) {
        try {
          await _writeReport(destination, report);
        } catch (error) {
          code = 1;
          report['exit_code'] = code;
          report['report_write_error'] = error.toString();
        }
      }
      if (mounted) {
        setState(() {
          _resultCode = code;
          _message = code == 0
              ? 'Qualification réussie : ${results.length} cas.'
              : 'Qualification échouée. ${report['report_write_error'] ?? report['fatal_error'] ?? '${report['failed']} cas en échec.'}';
        });
      }
      // No exit(), SystemNavigator.pop(), or automatic window closing. The result
      // code is explicit in JSON and UI; the operator retains the final evidence.
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Color — qualification raster native',
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Qualification raster native',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Mode ${kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug')} · ${Platform.operatingSystem}',
              ),
              const SizedBox(height: 16),
              if (_resultCode == null)
                LinearProgressIndicator(
                  value: _total == 0 ? null : _completed / _total,
                ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(child: SelectableText(_message)),
              ),
              Text('Cas terminés : $_completed / $_total'),
              if (_resultCode != null)
                Text(
                  'Code de résultat : $_resultCode · fenêtre laissée ouverte',
                ),
              const SizedBox(height: 16),
              const Text('Rapport JSON :'),
              SelectableText(_reportPath ?? 'Emplacement en préparation…'),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<Map<String, Object?>> _qualifyFixture(
  Map<String, dynamic> fixture,
) async {
  final watch = Stopwatch()..start();
  final name = fixture['file'] as String;
  final accepted = _accepted.contains(fixture['category']);
  final report = <String, Object?>{
    'file': name,
    'expected': accepted ? 'accept' : 'reject_before_decoding',
    'expected_sha256_from_manifest': fixture['sha256'],
    'outside_generated_manifest': fixture['outside_generated_manifest'] == true,
  };
  ImportedBackground? normalized;
  ImportedBackground? reopened;
  final live = <ui.Image>{};
  final observed = <Map<String, Object?>>[];
  final previousCreate = ui.Image.onCreate;
  final previousDispose = ui.Image.onDispose;
  ui.Image.onCreate = (image) {
    live.add(image);
    observed.add({
      'width': image.width,
      'height': image.height,
      'color_space': image.colorSpace.name,
    });
    previousCreate?.call(image);
  };
  ui.Image.onDispose = (image) {
    live.remove(image);
    previousDispose?.call(image);
  };
  try {
    final bytes = await _readFixture(name);
    _require(
      bytes.length == fixture['bytes'],
      'Source byte count differs from the fixture manifest.',
    );
    report['source_bytes'] = bytes.length;
    if (name == _realMacFixture) {
      _require(
        bytes.length > 25 && bytes[24] == 16 && bytes[25] == 6,
        'The macOS source must really be RGBA16.',
      );
    }
    if (!accepted) {
      Object? failure;
      try {
        normalized = await normaliseRaster(bytes);
      } catch (error) {
        failure = error;
      }
      _require(
        failure is FormatException,
        'Expected FormatException before decode; observed $failure.',
      );
      _require(
        observed.isEmpty,
        'Rejected source created ${observed.length} decoded images.',
      );
      report['rejected_before_image'] = true;
      report['rejection'] = failure.toString();
    } else {
      normalized = await normaliseRaster(bytes);
      report['timings_microseconds'] = normalized.timingsMicroseconds;
      report['normalized_color_space'] = normalized.image.colorSpace.name;
      report['image_creation_sequence_normalization'] = List.of(observed);
      final expectedSize = (fixture['display_size'] as List).cast<int>();
      _require(
        normalized.width == expectedSize[0] &&
            normalized.height == expectedSize[1],
        'Decoded dimensions differ from the oriented reference.',
      );
      final png = _canonicalPng(normalized.pngBytes);
      report['canonical_png'] = png;
      _require(
        normalized.image.colorSpace == ui.ColorSpace.sRGB,
        'Normalized image is not tagged sRGB.',
      );
      _require(
        normalized.timingsMicroseconds.containsKey('quantize_srgb8'),
        'Explicit sRGB8 quantization did not run.',
      );
      final first = await _rawPixels(normalized.image);
      if (fixture['pixel_probes'] case final List probes) {
        report['pixel_probes'] = _checkProbes(
          first,
          normalized.width,
          normalized.height,
          probes,
          jpegTolerance: fixture['jpeg_tolerance'] as int?,
        );
      }
      reopened = await decodeCanonicalBackground(normalized.pngBytes);
      _require(
        reopened.width == normalized.width &&
            reopened.height == normalized.height,
        'Reopened dimensions differ.',
      );
      _require(
        reopened.image.colorSpace == ui.ColorSpace.sRGB,
        'Reopened image is not sRGB.',
      );
      final second = await _rawPixels(reopened.image);
      _require(
        listEquals(first, second),
        'Reopening changed normalized premultiplied pixels.',
      );
      report['reopened_pixels_identical'] = true;
    }
    report['status'] = 'passed';
  } catch (error, stack) {
    report['status'] = 'failed';
    report['error'] = error.toString();
    report['stack'] = stack.toString();
  } finally {
    reopened?.dispose();
    normalized?.dispose();
    report['live_image_handles_after_dispose'] = live.length;
    if (live.isNotEmpty) {
      report['status'] = 'failed';
      report['ownership_error'] =
          '${live.length} image handles remain after disposal.';
    }
    ui.Image.onCreate = previousCreate;
    ui.Image.onDispose = previousDispose;
    report['elapsed_microseconds'] = watch.elapsedMicroseconds;
  }
  return report;
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<Uint8List> _rawPixels(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('The engine returned no RGBA pixels.');
  _require(
    data.lengthInBytes == image.width * image.height * 4,
    'Unexpected RGBA byte count.',
  );
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

List<Map<String, Object?>> _checkProbes(
  Uint8List pixels,
  int width,
  int height,
  List<dynamic> probes, {
  int? jpegTolerance,
}) {
  final report = <Map<String, Object?>>[];
  for (final probe in probes.cast<Map<String, dynamic>>()) {
    final xy = (probe['xy'] as List).cast<int>();
    final expected = (probe['rgba'] as List).cast<int>();
    final white = (probe['rgb_on_white'] as List).cast<int>();
    _require(
      xy.length == 2 &&
          xy[0] >= 0 &&
          xy[0] < width &&
          xy[1] >= 0 &&
          xy[1] < height,
      'Reference probe lies outside the image.',
    );
    final tolerance =
        (jpegTolerance ?? probe['tolerance_per_channel'] as int) + 1;
    final offset = (xy[1] * width + xy[0]) * 4;
    final alpha = pixels[offset + 3];
    _require(
      (alpha - expected[3]).abs() <= 1,
      'Alpha mismatch at $xy: $alpha != ${expected[3]}.',
    );
    final visible = [
      for (var channel = 0; channel < 3; channel++)
        pixels[offset + channel] + 255 - alpha,
    ];
    for (var channel = 0; channel < 3; channel++) {
      _require(
        (visible[channel] - white[channel]).abs() <= tolerance,
        'LittleCMS/white probe mismatch at $xy channel $channel: ${visible[channel]} != ${white[channel]} (tolerance $tolerance).',
      );
    }
    report.add({
      'xy': xy,
      'alpha': alpha,
      'expected_alpha': expected[3],
      'rgb_on_white': visible,
      'expected_rgb_on_white': white,
      'tolerance': tolerance,
    });
  }
  return report;
}

Map<String, Object?> _canonicalPng(Uint8List bytes) {
  _require(
    bytes.length >= 33 &&
        listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]),
    'Missing PNG signature.',
  );
  final data = ByteData.sublistView(bytes);
  final types = <String>[];
  var cursor = 8;
  while (cursor < bytes.length) {
    _require(cursor <= bytes.length - 12, 'Truncated canonical PNG chunk.');
    final length = data.getUint32(cursor, Endian.big);
    _require(
      length <= bytes.length - cursor - 12,
      'Canonical PNG chunk exceeds its buffer.',
    );
    types.add(String.fromCharCodes(bytes.sublist(cursor + 4, cursor + 8)));
    cursor += 12 + length;
  }
  _require(
    types.length >= 4 &&
        types.first == 'IHDR' &&
        types[1] == 'sRGB' &&
        types.last == 'IEND' &&
        types.skip(2).take(types.length - 3).every((type) => type == 'IDAT'),
    'Unexpected canonical chunks: $types.',
  );
  _require(
    bytes[24] == 8 && (bytes[25] == 2 || bytes[25] == 6) && bytes[28] == 0,
    'Canonical output is not RGB/RGBA8 non-interlaced.',
  );
  return {
    'chunks': types,
    'bytes': bytes.length,
    'bit_depth': bytes[24],
    'color_type': bytes[25],
    'interlace': bytes[28],
    'width': data.getUint32(16, Endian.big),
    'height': data.getUint32(20, Endian.big),
  };
}

Future<Uint8List> _readFixture(
  String name, {
  int maximumBytes = maxRasterBytes,
}) async {
  _require(
    name.isNotEmpty &&
        !name.contains('/') &&
        !name.contains('\\') &&
        name != '..',
    'Invalid fixture name.',
  );
  if (_fixtureLocation.startsWith('assets:')) {
    final prefix = _fixtureLocation.substring(7).replaceAll(RegExp(r'/+$'), '');
    _require(prefix.isNotEmpty, 'Missing fixture asset prefix.');
    final data = await rootBundle.load('$prefix/$name');
    _require(
      data.lengthInBytes <= maximumBytes,
      'Fixture asset exceeds its byte limit.',
    );
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
  _require(
    Directory(_fixtureLocation).isAbsolute,
    'Fixture directory must be absolute or start with assets:.',
  );
  return _readBoundedFile('$_fixtureLocation/$name', maximumBytes);
}

Future<Uint8List> _readBoundedFile(String path, int maximumBytes) async {
  final file = await File(path).open();
  try {
    _require(
      await file.length() <= maximumBytes,
      'File exceeds its byte limit: $path',
    );
    final builder = BytesBuilder(copy: false);
    while (builder.length <= maximumBytes) {
      final remaining = maximumBytes + 1 - builder.length;
      final data = await file.read(remaining < 65536 ? remaining : 65536);
      if (data.isEmpty) return builder.takeBytes();
      builder.add(data);
    }
    throw StateError('File grew beyond its byte limit: $path');
  } finally {
    await file.close();
  }
}

Future<void> _writeReport(String path, Map<String, Object?> report) async {
  final file = File(path);
  final type = await FileSystemEntity.type(path, followLinks: false);
  _require(
    type == FileSystemEntityType.notFound || type == FileSystemEntityType.file,
    'Report destination must be a regular file.',
  );
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    flush: true,
  );
}

Future<void> _collectDiagnostics(
  String path,
  String runId,
  List<Map<String, Object?>> fixtures,
  Map<String, Object?> report,
) async {
  try {
    List<String> events = const [];
    final lastMarker = 'qualification-end:$runId:${fixtures.length - 1}';
    // The native diagnostics queue is asynchronous. Bound observation to 400 ms;
    // absence is reported as missing evidence, never invented or a pixel pass.
    for (var attempt = 0; attempt < 10; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final bytes = await _readBoundedFile(path, 3 * 1024 * 1024);
      events = [];
      for (final line in const LineSplitter().convert(
        utf8.decode(bytes, allowMalformed: true),
      )) {
        try {
          final entry = jsonDecode(line) as Map<String, dynamic>;
          if (entry['event'] case final String event) events.add(event);
        } catch (_) {
          /* Ignore a trailing partially flushed diagnostic line. */
        }
      }
      if (events.contains(lastMarker)) break;
    }
    int? active;
    final seen = <int>{};
    for (final event in events) {
      if (event.startsWith('qualification-start:$runId:')) {
        active = int.tryParse(event.split(':').last);
      } else if (event.startsWith('qualification-end:$runId:')) {
        if (active != null) seen.add(active);
        active = null;
      } else if (active != null &&
          active >= 0 &&
          active < fixtures.length &&
          event.startsWith('raster-')) {
        final item = fixtures[active];
        final trace =
            (item['native_raster_events'] ??= <String>[]) as List<String>;
        trace.add(event);
        final fields = event.split(':');
        if (fields.length == 3 && fields[0] != 'raster-png') {
          final spaces =
              (item['native_color_spaces'] ??= <String, String>{})
                  as Map<String, String>;
          spaces[fields[0]] = fields[2];
        }
      }
    }
    report['native_diagnostics_cases_observed'] = seen.length;
    report['native_diagnostics_complete'] = seen.length == fixtures.length;
  } catch (error) {
    report['native_diagnostics_read_error'] = error.toString();
  }
}
