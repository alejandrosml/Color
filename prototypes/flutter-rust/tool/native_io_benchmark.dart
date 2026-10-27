// SPDX-License-Identifier: MIT
// Separate, manually started qualification entrypoint. Never imported by main.
// No product code or SDK change is needed to compare the two channel payloads.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/native_diagnostics.dart';
import 'package:edupaint_flutter_study/native_exit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _files = MethodChannel('org.edupaint/files');
const _payloadBytes = 67 * 1024 * 1024;
const _warmupsPerVariant = 2;
const _measurementsPerVariant = 5;
const _timerPeriod = Duration(milliseconds: 8);
const _diskBudgetBytes = 160 * 1024 * 1024;
const _variants = ['baseline_copy', 'direct_bytes'];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BenchmarkApp());
}

class _BenchmarkApp extends StatefulWidget {
  const _BenchmarkApp();
  @override
  State<_BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<_BenchmarkApp> {
  bool _running = false;
  String _message = 'Prêt. Aucune mesure ne démarre avant le bouton Run.';
  String? _reportPath;
  int? _resultCode;

  @override
  void initState() {
    super.initState();
    installNativeExitHandler(
      () async =>
          _running ? ui.AppExitResponse.cancel : ui.AppExitResponse.exit,
    );
  }

  @override
  void dispose() {
    clearNativeExitHandler();
    clearNativeDiagnostics();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _resultCode = null;
      _message = 'Préparation des données — hors mesure…';
    });
    File? cleanupTarget;
    File? reportOutput;
    final frames = _FrameObservations();
    final rows = <Map<String, Object?>>[];
    final report = <String, Object?>{
      'schema': 1,
      'status': 'in_progress',
      'started_at_utc': DateTime.now().toUtc().toIso8601String(),
      'scope':
          'Native macOS MethodChannel -> existing Foundation atomic writer. '
          'Opaque data; this does not benchmark project serialization, drawing, '
          'input latency, power-loss durability or a user-selected file grant.',
      'build_mode': kReleaseMode
          ? 'release'
          : (kProfileMode ? 'profile' : 'debug'),
      'operating_system': Platform.operatingSystem,
      'frames_enabled_at_start': WidgetsBinding.instance.framesEnabled,
      'lifecycle_at_start': WidgetsBinding.instance.lifecycleState?.name,
      'dart_version': Platform.version,
      'payload_bytes': _payloadBytes,
      'payload_generation':
          'Deterministic xorshift32 seed 0x6d2b79f5; each byte is state & 255. '
          'Generation and transfer finish before observers and warmups start.',
      'target': 'One file in a unique app sandbox temporary directory per run; reused for every write.',
      'planned_peak_payload_files_bytes': 2 * _payloadBytes,
      'disk_budget_bytes': _diskBudgetBytes,
      'disk_scope':
          'One existing target plus one atomic replacement payload: 134 MiB. '
          'No per-iteration payload files, no payload in JSON. Foundation/OS metadata '
          'is not measured; the target is removed after final readback.',
      'warmups_per_variant': _warmupsPerVariant,
      'measurements_per_variant': _measurementsPerVariant,
      'order': 'baseline_copy, direct_bytes repeated twice for warmup, then five times for measurement.',
      'variants': {
        'baseline_copy': 'Uint8List.fromList(payload), then the existing writeAtomic MethodChannel.',
        'direct_bytes': 'The same payload directly into the same writeAtomic MethodChannel.',
      },
      'protocol': {
        'call_return_us':
            'Elapsed synchronous call time until the writer returns its Future. '
            'Includes Dart defensive copy where present and StandardMethodCodec encoding.',
        'first_microtask_yield_us':
            'Elapsed time to the first queued microtask after invocation. '
            'This is not a rendered frame or an input-response measurement.',
        'total_us': 'Call through acknowledgement of the completed Foundation write, observed by Dart.',
        'timer':
            'Periodic 8 ms Dart timer. Callback gaps and the unfinished tail are frozen/cancelled '
            'immediately when the write Future completes, before readback, RSS reads or report generation.',
        'timer_overrun':
            'max(0, callback gap - 8 ms), including any overdue final tail. '
            'A sampling indicator of event-loop delay, not a display frame metric.',
        'frames':
            'Separate overall observation of a lightweight progress animation. '
            'Release callbacks are batched about once per second, so they are never attributed '
            'to the variant active when a callback is delivered. Includes warmup, both variants, '
            'between-write pauses, readback verification and a final 1.2 s callback drain. '
            'A delivered batch may contain frames begun shortly before collection.',
        'rss':
            'Public dart:io ProcessInfo, sampled outside each timed interval. '
            'maxRss is the process lifetime high-watermark, not a per-write peak or GPU allocation count.',
        'verification':
            'Streamed byte-for-byte readback after the first warmup write and the last '
            'measured write, outside timed intervals; 256 KiB read chunks, no second full-file buffer.',
        'settling':
            '120 ms between writes plus one completed Flutter frame; no forced GC, '
            'filesystem cache purge or extrapolation to cold disks.',
        'limitations':
            'Fixed alternating order and five samples per variant. GC, OS cache, '
            'thermal state and system work can affect results. No fluidity promise before evidence.',
      },
      'operations': rows,
    };
    var code = 1;
    var ownsTarget = false;
    try {
      if (!Platform.isMacOS) {
        throw StateError(
          'macOS is required for this Foundation-channel comparison.',
        );
      }
      if (2 * _payloadBytes >= _diskBudgetBytes) {
        throw StateError('Payload plan exceeds the disk budget.');
      }
      final directory = await Directory.systemTemp.createTemp(
        'Color-native-io-benchmark-',
      );
      final target = File('${directory.path}/payload.bin');
      final output = File('${directory.path}/result.json');
      cleanupTarget = target;
      reportOutput = output;
      await _requireRegularOrAbsent(target);
      ownsTarget = true;
      if (await target.exists()) {
        // Only this harness's one known target is reset, before the timed run.
        await target.delete();
      }
      if (mounted) setState(() => _reportPath = output.path);
      await _writeJson(output, report);
      await installNativeDiagnostics();
      await WidgetsBinding.instance.endOfFrame;
      final prepare = Stopwatch()..start();
      final transfer = await Isolate.run(_generatePayload);
      final payload = transfer.materialize().asUint8List();
      if (payload.length != _payloadBytes) {
        throw StateError('Unexpected payload length.');
      }
      report['preparation_us_excluded'] = prepare.elapsedMicroseconds;
      report['rss_after_preparation'] = _rss();
      frames.start();
      recordNativeDiagnostics('native-io-benchmark-start');
      var index = 0;
      final count = 2 * (_warmupsPerVariant + _measurementsPerVariant);
      for (
        var round = 0;
        round < _warmupsPerVariant + _measurementsPerVariant;
        round++
      ) {
        for (final variant in _variants) {
          final warmup = round < _warmupsPerVariant;
          if (mounted) {
            setState(
              () => _message =
                  '${warmup ? 'Échauffement' : 'Mesure'} '
                  '${index + 1} / $count · $variant',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 120));
          await WidgetsBinding.instance.endOfFrame;
          final row = await _measureWrite(target.path, payload, variant);
          row['index'] = index;
          row['warmup'] = warmup;
          row['round_within_phase'] = warmup
              ? round + 1
              : round - _warmupsPerVariant + 1;
          rows.add(row);
          if (row['status'] != 'passed') {
            throw StateError(
              'The native write failed; later writes are not attempted.',
            );
          }
          if (index == 0 || index == count - 1) {
            final verification = await _verifyBytes(target, payload);
            verification['after_operation_index'] = index;
            report[index == 0
                    ? 'first_write_verification'
                    : 'last_write_verification'] =
                verification;
          }
          index++;
        }
      }
      if (mounted) {
        setState(() => _message = 'Collecte des temps de frame — hors mesure…');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      frames.stop();
      report['frames_overall'] = frames.toJson();
      report['summary'] = _summaries(rows);
      report['rss_after_run'] = _rss();
      report['status'] = 'passed';
      code = 0;
    } catch (error) {
      report['status'] = 'failed';
      report['failure'] = _publicError(error);
    } finally {
      frames.stop();
      report['frames_overall'] ??= frames.toJson();
      try {
        if (ownsTarget &&
            cleanupTarget != null &&
            await cleanupTarget.exists()) {
          await cleanupTarget.delete();
        }
        report['payload_target_cleanup_attempted'] = ownsTarget;
        report['payload_target_removed'] = ownsTarget;
      } catch (error) {
        report['payload_target_removed'] = false;
        report['cleanup_error'] = _publicError(error);
        report['status'] = 'failed';
        code = 1;
      }
      report['finished_at_utc'] = DateTime.now().toUtc().toIso8601String();
      report['frames_enabled_at_finish'] =
          WidgetsBinding.instance.framesEnabled;
      report['lifecycle_at_finish'] =
          WidgetsBinding.instance.lifecycleState?.name;
      report['exit_code'] = code;
      report['process_left_open'] = true;
      try {
        final output = reportOutput;
        if (output == null) {
          throw StateError('The report directory could not be created.');
        }
        await _writeJson(output, report);
      } catch (error) {
        code = 1;
        report['report_write_error'] = _publicError(error);
      }
      recordNativeDiagnostics('native-io-benchmark-finished:$code');
      if (mounted) {
        setState(() {
          _running = false;
          _resultCode = code;
          _message = code == 0
              ? 'Mesures terminées. Consulte le rapport pour comparer les deux variantes.'
              : 'Mesure interrompue ou rapport non écrit. Aucun résultat de performance n’est annoncé.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Color — qualification écriture native',
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Écriture native macOS · copie / octets directs',
                style: TextStyle(fontSize: 22),
              ),
              const SizedBox(height: 12),
              Text(
                'Mode ${kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug')} · 67 MiB · 2 échauffements + 5 mesures par variante',
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('runBenchmark'),
                onPressed: _running ? null : _run,
                child: const Text('Run — lancer la mesure'),
              ),
              const SizedBox(height: 16),
              if (_running) const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(child: SelectableText(_message)),
              ),
              if (_resultCode != null)
                Text(
                  'Code de résultat : $_resultCode · fenêtre laissée ouverte',
                ),
              const Text('Rapport local :'),
              SelectableText(
                _reportPath ??
                    'Créé après Run, dans le dossier temporaire du sandbox.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

TransferableTypedData _generatePayload() {
  final data = Uint8List(_payloadBytes);
  var state = 0x6d2b79f5;
  for (var index = 0; index < data.length; index++) {
    state ^= (state << 13) & 0xffffffff;
    state ^= state >>> 17;
    state ^= (state << 5) & 0xffffffff;
    state &= 0xffffffff;
    data[index] = state & 255;
  }
  return TransferableTypedData.fromList([data]);
}

Future<void> _baselineWrite(String path, Uint8List bytes) async {
  await _files.invokeMethod<void>('writeAtomic', {
    'path': path,
    'bytes': Uint8List.fromList(bytes),
  });
}

Future<void> _directWrite(String path, Uint8List bytes) async {
  await _files.invokeMethod<void>('writeAtomic', {
    'path': path,
    'bytes': bytes,
  });
}

Future<Map<String, Object?>> _measureWrite(
  String path,
  Uint8List payload,
  String variant,
) async {
  final before = _rss();
  final watch = Stopwatch();
  final firstYield = Completer<int>();
  final timer = _DeadlineObservations(watch)..start();
  int? returned;
  int? yielded;
  Object? failure;
  scheduleMicrotask(() => firstYield.complete(watch.elapsedMicroseconds));
  watch.start();
  try {
    final operation = variant == 'baseline_copy'
        ? _baselineWrite(path, payload)
        : _directWrite(path, payload);
    returned = watch.elapsedMicroseconds;
    // Install the error handler immediately, even if native rejection occurs
    // before the microtask probe resumes. Neither branch returns payload bytes.
    final completion = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace _) {
        failure = error;
      },
    );
    yielded = await firstYield.future;
    await completion;
  } catch (error) {
    failure = error;
  }
  final total = watch.elapsedMicroseconds;
  watch.stop();
  timer.freeze(
    total,
  ); // Freeze before RSS queries, JSON, cleanup or verification.
  final after = _rss();
  return {
    'variant': variant,
    'status': failure == null ? 'passed' : 'failed',
    'call_return_us': returned,
    'first_microtask_yield_us': yielded,
    'total_us': total,
    'timer': timer.toJson(),
    'rss_before': before,
    'rss_after': after,
    if (failure != null) 'failure': _publicError(failure!),
  };
}

class _DeadlineObservations {
  _DeadlineObservations(this.watch);
  final Stopwatch watch;
  Timer? _timer;
  int _last = 0;
  int _ticks = 0;
  int _maxGap = 0;
  int _maxOverrun = 0;
  int _tail = 0;

  void start() {
    _timer = Timer.periodic(_timerPeriod, (_) {
      final now = watch.elapsedMicroseconds;
      final gap = now - _last;
      _last = now;
      _ticks++;
      if (gap > _maxGap) _maxGap = gap;
      final overrun = gap - _timerPeriod.inMicroseconds;
      if (overrun > _maxOverrun) _maxOverrun = overrun;
    });
  }

  void freeze(int operationEnd) {
    _timer?.cancel();
    _timer = null;
    _tail = operationEnd - _last;
    final overrun = _tail - _timerPeriod.inMicroseconds;
    if (overrun > _maxOverrun) _maxOverrun = overrun;
  }

  Map<String, Object?> toJson() => {
    'period_us': _timerPeriod.inMicroseconds,
    'delivered_callbacks': _ticks,
    'max_delivered_callback_gap_us': _maxGap,
    'final_unfinished_gap_us': _tail,
    'max_deadline_overrun_including_final_tail_us': _maxOverrun,
    'frozen_at_operation_end': true,
  };
}

class _FrameObservations {
  bool _active = false;
  int _count = 0;
  int _buildSum = 0;
  int _rasterSum = 0;
  int _totalSum = 0;
  int _maxBuild = 0;
  int _maxRaster = 0;
  int _maxTotal = 0;

  void start() {
    _active = true;
    WidgetsBinding.instance.addTimingsCallback(_observe);
  }

  void stop() {
    if (!_active) return;
    _active = false;
    WidgetsBinding.instance.removeTimingsCallback(_observe);
  }

  void _observe(List<ui.FrameTiming> timings) {
    for (final timing in timings) {
      _count++;
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      final total = timing.totalSpan.inMicroseconds;
      _buildSum += build;
      _rasterSum += raster;
      _totalSum += total;
      if (build > _maxBuild) _maxBuild = build;
      if (raster > _maxRaster) _maxRaster = raster;
      if (total > _maxTotal) _maxTotal = total;
    }
  }

  Map<String, Object?> toJson() => {
    'count': _count,
    'mean_build_us': _count == 0 ? null : _buildSum / _count,
    'mean_raster_us': _count == 0 ? null : _rasterSum / _count,
    'mean_total_span_us': _count == 0 ? null : _totalSum / _count,
    'max_build_us': _maxBuild,
    'max_raster_us': _maxRaster,
    'max_total_span_us': _maxTotal,
    'per_variant_attribution': false,
    'complete_drain_guaranteed': false,
  };
}

Map<String, Object?> _rss() {
  try {
    return {
      'current_bytes': ProcessInfo.currentRss,
      'process_lifetime_max_bytes': ProcessInfo.maxRss,
    };
  } catch (_) {
    return {'available': false};
  }
}

Future<Map<String, Object?>> _verifyBytes(File file, Uint8List expected) async {
  final watch = Stopwatch()..start();
  final handle = await file.open();
  var offset = 0;
  try {
    if (await handle.length() != expected.length) {
      throw StateError('Verification length mismatch.');
    }
    while (offset < expected.length) {
      final remaining = expected.length - offset;
      final bytes = await handle.read(remaining < 262144 ? remaining : 262144);
      if (bytes.isEmpty) throw StateError('Verification found early EOF.');
      for (var index = 0; index < bytes.length; index++) {
        if (bytes[index] != expected[offset + index]) {
          throw StateError('Verification byte mismatch.');
        }
      }
      offset += bytes.length;
    }
    if ((await handle.read(1)).isNotEmpty) {
      throw StateError('Verification found trailing bytes.');
    }
  } finally {
    await handle.close();
  }
  return {
    'exact_byte_equality': true,
    'bytes_checked': offset,
    'elapsed_us_excluded_from_write_measurements': watch.elapsedMicroseconds,
  };
}

Map<String, Object?> _summaries(List<Map<String, Object?>> rows) {
  final summaries = <String, Object?>{};
  for (final variant in _variants) {
    final selected = rows
        .where((row) => row['variant'] == variant && row['warmup'] == false)
        .toList();
    final summary = <String, Object?>{'samples': selected.length};
    for (final field in [
      'call_return_us',
      'first_microtask_yield_us',
      'total_us',
    ]) {
      final values = selected.map((row) => row[field] as int).toList()..sort();
      summary[field] = {
        'min': values.first,
        'median': values[values.length ~/ 2],
        'max': values.last,
      };
    }
    summaries[variant] = summary;
  }
  return summaries;
}

Map<String, Object?> _publicError(Object error) => {
  'type': error.runtimeType.toString(),
  if (error is PlatformException) 'platform_code': error.code,
  if (error is PlatformException && error.details is Map)
    'native': {
      for (final key in ['domain', 'code'])
        if ((error.details as Map)[key] case final String value)
          key: value
        else if ((error.details as Map)[key] case final num value)
          key: value,
    },
  // No error.toString(): native messages may contain private absolute paths.
};

Future<void> _requireRegularOrAbsent(File file) async {
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw StateError('The benchmark target must be a regular file.');
  }
}

Future<void> _writeJson(File file, Map<String, Object?> value) async {
  await _requireRegularOrAbsent(file);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    flush: true,
  );
}
