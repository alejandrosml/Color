// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';

import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/document_exports.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';

class _ObservedFiles extends MemoryFiles {
  String? exportPath = '/drawings/export.svg';
  Completer<void>? projectBarrier;
  Completer<void>? svgBarrier;
  int projectWrites = 0;
  int svgWrites = 0;
  int openDialogs = 0;
  int exportDialogs = 0;
  Uint8List? svgBytes;

  @override
  Future<String?> chooseOpen() async {
    openDialogs++;
    return super.chooseOpen();
  }

  @override
  Future<String?> chooseExport({String? currentPath}) async {
    exportDialogs++;
    return exportPath;
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    projectWrites++;
    if (projectBarrier != null) await projectBarrier!.future;
    await super.write(path, bytes);
  }

  @override
  Future<void> writeSvgBytes(String path, Uint8List bytes) async {
    svgWrites++;
    svgBytes = Uint8List.fromList(bytes);
    if (svgBarrier != null) await svgBarrier!.future;
    await super.writeSvgBytes(path, bytes);
  }

  @override
  Future<void> writeSvg(String path, String svg) =>
      throw StateError('The UI must use UTF-8 bytes, never a SVG String.');
}

class _ObservedRecovery extends MemoryRecovery {
  Completer<void>? firstBarrier;
  int clears = 0;
  final snapshots = <Uint8List>[];

  @override
  Future<void> writeRecovery(Uint8List bytes) async {
    snapshots.add(Uint8List.fromList(bytes));
    if (snapshots.length == 1 && firstBarrier != null) {
      await firstBarrier!.future;
    }
    await super.writeRecovery(bytes);
  }

  @override
  Future<void> clearRecovery() async {
    clears++;
    await super.clearRecovery();
  }
}

EduPaintDesktopMenu _menu(WidgetTester tester) =>
    tester.widget<EduPaintDesktopMenu>(find.byType(EduPaintDesktopMenu));
bool _idle(WidgetTester tester) => _menu(tester).onSave != null;

Future<void> _until(
  WidgetTester tester,
  bool Function() complete,
  String reason,
) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (complete()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  fail('Export workflow did not complete: $reason');
}

Uint8List _largeProject() {
  final document = RustDocument();
  try {
    document.addStroke(
      [
        for (var index = 0; index < 34000; index++)
          DocumentPoint(
            40 + (index % 1100).toDouble(),
            40 + (index ~/ 1100).toDouble(),
          ),
      ],
      rgb: 0x477fb2,
      width: 2,
    );
    expect(projectExportUsesWorker(document), isTrue);
    expect(svgExportUsesWorker(document), isTrue);
    return document.exportProject();
  } finally {
    document.dispose();
  }
}

int _objectCount(Uint8List bytes) {
  final document = RustDocument.fromProject(bytes);
  try {
    return document.count;
  } finally {
    document.dispose();
  }
}

Future<void> _mountLarge(
  WidgetTester tester,
  _ObservedFiles files,
  _ObservedRecovery recovery,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  files.openPath = '/drawings/source.edupaint';
  files.projects[files.openPath!] = _largeProject();
  await tester.pumpWidget(EduPaintApp(files: files, recoveryStorage: recovery));
  await tester.pumpAndSettle();
  _menu(tester).onOpen!();
  await _until(tester, () => _idle(tester), 'open large vector document');
  expect(find.textContaining('1 élément'), findsOneWidget);
}

Future<void> _draw(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const Key('drawingSurface'))),
  );
  await gesture.moveBy(const Offset(55, -25));
  await gesture.up();
  await tester.pump();
}

Future<Object?> _nativeExit(WidgetTester tester) {
  const codec = StandardMethodCodec();
  final result = Completer<Object?>();
  tester.binding.channelBuffers.push(
    'org.edupaint/lifecycle',
    codec.encodeMethodCall(const MethodCall('requestExit')),
    (ByteData? bytes) =>
        result.complete(bytes == null ? null : codec.decodeEnvelope(bytes)),
  );
  return result.future;
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  testWidgets('large project and SVG use real workers and the byte writer', (
    tester,
  ) async {
    final files = _ObservedFiles();
    final recovery = _ObservedRecovery();
    await _mountLarge(tester, files, recovery);
    final original = Uint8List.fromList(files.projects[files.openPath]!);
    await _draw(tester);
    _menu(tester).onSaveAs!();
    await _until(
      tester,
      () => files.projectWrites == 1 && _idle(tester),
      'worker save',
    );
    expect(_objectCount(files.projects[files.savePath]!), 2);
    expect(
      find.textContaining('2 éléments · projet enregistré'),
      findsOneWidget,
    );
    expect(recovery.bytes, isNull);
    expect(files.projects[files.openPath], original);
    _menu(tester).onExportSvg!();
    await _until(
      tester,
      () => files.svg != null && _idle(tester),
      'worker SVG bytes',
    );
    expect(files.svgBytes, isNotEmpty);
    expect(files.svg, contains('<svg'));
    expect(files.svgWrites, 1);
    expect(find.text('Préparation de ton image SVG…'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !available);

  testWidgets('cancelled destinations do not write or leave a busy state', (
    tester,
  ) async {
    final files = _ObservedFiles()..savePath = null;
    final recovery = _ObservedRecovery();
    await _mountLarge(tester, files, recovery);
    await _draw(tester);
    _menu(tester).onSaveAs!();
    await tester.pumpAndSettle();
    expect(files.projectWrites, 0);
    expect(find.text('Préparation de ton projet…'), findsNothing);
    files.exportPath = null;
    _menu(tester).onExportSvg!();
    await tester.pumpAndSettle();
    expect(files.svgWrites, 0);
    expect(_idle(tester), isTrue);
    expect(
      find.textContaining('modifications non enregistrées'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !available);

  testWidgets(
    'worker save failure keeps recovery, dirty state and confirmation open to retry',
    (tester) async {
      final files = _ObservedFiles();
      final recovery = _ObservedRecovery();
      await _mountLarge(tester, files, recovery);
      await _draw(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await _until(
        tester,
        () => recovery.bytes != null,
        'initial worker recovery',
      );
      final before = Uint8List.fromList(recovery.bytes!);
      files.failWrite = true;
      _menu(tester).onNew!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createNewSheet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveChanges')));
      await _until(
        tester,
        () => files.projectWrites == 1 && _idle(tester),
        'failed worker save',
      );
      expect(recovery.bytes, before);
      expect(
        recovery.clears,
        1,
        reason: 'Only opening the initial source cleared recovery.',
      );
      expect(
        find.textContaining('2 éléments · modifications non enregistrées'),
        findsOneWidget,
      );
      expect(find.textContaining('Enregistrement non terminé'), findsOneWidget);
      files.failWrite = false;
      _menu(tester).onSave!();
      await _until(
        tester,
        () => files.projectWrites == 2 && _idle(tester),
        'retry worker save',
      );
      expect(
        find.textContaining('2 éléments · projet enregistré'),
        findsOneWidget,
      );
      expect(recovery.bytes, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'native callbacks and drawing stay guarded throughout SVG byte writing',
    (tester) async {
      final files = _ObservedFiles()..svgBarrier = Completer<void>();
      final recovery = _ObservedRecovery();
      await _mountLarge(tester, files, recovery);
      await _draw(tester);
      final callbacks = _menu(tester);
      callbacks.onExportSvg!();
      await _until(
        tester,
        () => files.svgWrites == 1,
        'SVG prepared and writer held',
      );
      expect(find.text('Préparation de ton image SVG…'), findsOneWidget);
      callbacks.onNew!();
      callbacks.onOpen!();
      callbacks.onSave!();
      callbacks.onUndo!();
      callbacks.onExportSvg!();
      await _draw(tester);
      expect(files.openDialogs, 1);
      expect(files.projectWrites, 0);
      expect(files.exportDialogs, 1);
      expect(find.textContaining('2 éléments'), findsOneWidget);
      if (Platform.isMacOS) {
        expect(await _nativeExit(tester), {'response': 'cancel'});
      }
      files.svgBarrier!.complete();
      await _until(tester, () => _idle(tester), 'SVG writer released');
      expect(
        find.textContaining('modifications non enregistrées'),
        findsOneWidget,
      );
      expect(find.text('Préparation de ton image SVG…'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'disposal during project writing does not clear recovery or apply stale state',
    (tester) async {
      final files = _ObservedFiles()..projectBarrier = Completer<void>();
      final recovery = _ObservedRecovery();
      await _mountLarge(tester, files, recovery);
      await _draw(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await _until(
        tester,
        () => recovery.bytes != null,
        'recovery before disposal',
      );
      final before = Uint8List.fromList(recovery.bytes!);
      final clears = recovery.clears;
      _menu(tester).onSaveAs!();
      await _until(
        tester,
        () => files.projectWrites == 1,
        'worker save writer held',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      files.projectBarrier!.complete();
      await _until(
        tester,
        () => files.projects.containsKey(files.savePath),
        'write completes after disposal',
      );
      expect(recovery.bytes, before);
      expect(recovery.clears, clears);
      expect(_objectCount(files.projects[files.savePath]!), 2);
      expect(tester.takeException(), isNull);
    },
    skip: !available,
  );

  testWidgets(
    'editing while worker recovery writes coalesces one latest snapshot',
    (tester) async {
      final files = _ObservedFiles();
      final recovery = _ObservedRecovery()..firstBarrier = Completer<void>();
      await _mountLarge(tester, files, recovery);
      await _draw(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await _until(
        tester,
        () => recovery.snapshots.length == 1,
        'first worker recovery held',
      );
      expect(_objectCount(recovery.snapshots.first), 2);
      await _draw(tester);
      await _draw(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(recovery.snapshots, hasLength(1));
      recovery.firstBarrier!.complete();
      await _until(
        tester,
        () => recovery.writes == 2,
        'latest recovery snapshot',
      );
      expect(recovery.snapshots, hasLength(2));
      expect(_objectCount(recovery.bytes!), 4);
      expect(
        find.text('Copie de récupération à jour · projet à enregistrer.'),
        findsOneWidget,
      );
      expect(_idle(tester), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'new page invalidates old recovery and restores commands after a worker',
    (tester) async {
      final files = _ObservedFiles();
      final recovery = _ObservedRecovery()..firstBarrier = Completer<void>();
      await _mountLarge(tester, files, recovery);
      await _draw(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await _until(
        tester,
        () => recovery.snapshots.length == 1,
        'old recovery held',
      );
      _menu(tester).onNew!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createNewSheet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discardChanges')));
      await tester.pump();
      recovery.firstBarrier!.complete();
      await _until(
        tester,
        () => _idle(tester),
        'new page after old worker write',
      );
      expect(recovery.bytes, isNull);
      expect(
        find.textContaining('0 élément · nouvelle feuille'),
        findsOneWidget,
      );
      await _draw(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await _until(tester, () => recovery.bytes != null, 'new page recovery');
      expect(_objectCount(recovery.bytes!), 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );
}
