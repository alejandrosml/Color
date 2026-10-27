// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';

import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_problem.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';

class _Files extends MemoryFiles {
  Object? readError;
  Completer<Uint8List>? readBarrier;
  int openPanels = 0;
  int writesAttempted = 0;
  int exports = 0;
  final documents = <RustDocument>[];

  @override
  Future<String?> chooseOpen() async {
    openPanels++;
    return super.chooseOpen();
  }

  @override
  Future<Uint8List> read(String path) async {
    if (readBarrier != null) return readBarrier!.future;
    if (readError != null) throw readError!;
    return super.read(path);
  }

  @override
  Future<PreparedProject> readPrepared(String path) async {
    final result = await super.readPrepared(path);
    documents.add(result.document);
    return result;
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    writesAttempted++;
    await super.write(path, bytes);
  }

  @override
  Future<String?> chooseExport({String? currentPath}) async {
    exports++;
    return super.chooseExport(currentPath: currentPath);
  }
}

class _Recovery extends MemoryRecovery {
  _Recovery();
  bool failClear = false;

  @override
  Future<void> clearRecovery() async {
    if (failClear) {
      throw const FileSystemException('cleanup-marker-for-details');
    }
    await super.clearRecovery();
  }
}

Uint8List _fixture(String name) =>
    File('test/fixtures/project-open/$name').readAsBytesSync();

EduPaintDesktopMenu _menu(WidgetTester tester) =>
    tester.widget<EduPaintDesktopMenu>(find.byType(EduPaintDesktopMenu));

Future<void> _mount(
  WidgetTester tester,
  _Files files,
  MemoryRecovery recovery,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 760);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(EduPaintApp(files: files, recoveryStorage: recovery));
  await waitForPreparedOpen(tester);
}

Future<void> _draw(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const Key('drawingSurface'))),
  );
  await gesture.moveBy(const Offset(30, -20));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  _menu(tester).onOpen!();
  await waitForPreparedOpen(tester);
}

Future<void> _details(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('showProblemDetails')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('problemDetailsDialog')), findsOneWidget);
}

Future<void> _closeDetails(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('problemDetailsDialog')), findsNothing);
}

String _detailsText(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const Key('problemDetailsText')))
    .data!;

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  for (final invalid in [
    'bad-project-crc.edupaint',
    'structural-png-undecodable.edupaint',
  ]) {
    testWidgets(
      'real invalid project $invalid has optional details and guarded unchanged drawing',
      (tester) async {
        final files = _Files();
        const original = '/drawings/old.edupaint';
        const broken = '/drawings/broken.edupaint';
        files.projects[original] = _fixture('portrait-v2.edupaint');
        files.projects[broken] = _fixture(invalid);
        files.openPath = original;
        await _mount(tester, files, MemoryRecovery());
        await _open(tester);
        await _draw(tester);
        final document = files.documents.single;
        final savedBytes = document.exportProject();
        final undo = document.undoCount;
        final redo = document.redoCount;
        final callbacks = _menu(tester);
        files.openPath = broken;
        await _open(tester);
        expect(
          find.text(
            'Ce projet n’a pas pu être ouvert. Le dessin actuel est conservé.',
          ),
          findsOneWidget,
        );
        expect(find.byType(SelectableText), findsNothing);
        expect(find.byKey(const Key('saveChanges')), findsNothing);
        await _details(tester);
        expect(_detailsText(tester), isNotEmpty);
        final panels = files.openPanels;
        callbacks.onOpen!();
        callbacks.onSave!();
        callbacks.onUndo!();
        callbacks.onExportSvg!();
        await tester.pump();
        expect(files.openPanels, panels);
        expect(files.writesAttempted, 0);
        expect(files.exports, 0);
        expect(document.exportProject(), savedBytes);
        expect(document.undoCount, undo);
        expect(document.redoCount, redo);
        await _closeDetails(tester);
        expect(document.exportProject(), savedBytes);
        callbacks.onExportSvg!();
        await waitForPreparedOpen(tester);
        expect(files.exportSourcePath, original);
        expect(files.exports, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: !available,
    );
  }

  testWidgets(
    'save failure and saved project with failed cleanup remain distinct',
    (tester) async {
      final files = _Files()..failWrite = true;
      final recovery = _Recovery();
      await _mount(tester, files, recovery);
      await _draw(tester);
      _menu(tester).onSave!();
      await waitForPreparedOpen(tester);
      expect(
        find.text('Enregistrement non terminé. Le dessin reste ouvert.'),
        findsOneWidget,
      );
      expect(files.projects, isEmpty);
      expect(
        find.textContaining('1 élément · modifications non enregistrées'),
        findsOneWidget,
      );
      await _details(tester);
      expect(_detailsText(tester), contains('Simulated denied write'));
      await _closeDetails(tester);
      expect(files.writesAttempted, 1);
      files.failWrite = false;
      recovery.failClear = true;
      _menu(tester).onSave!();
      await waitForPreparedOpen(tester);
      expect(files.projects[files.savePath], isNotNull);
      expect(
        find.text(
          'Le projet est enregistré. L’ancienne copie de récupération n’a pas pu être retirée.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('1 élément · projet enregistré'),
        findsOneWidget,
      );
      await _details(tester);
      expect(_detailsText(tester), contains('cleanup-marker-for-details'));
      await _closeDetails(tester);
      expect(files.writesAttempted, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'invalid recovery stays preserved with diagnostics hidden until requested',
    (tester) async {
      final original = _fixture('bad-project-crc.edupaint');
      final recovery = MemoryRecovery(original);
      await _mount(tester, _Files(), recovery);
      expect(
        find.text(
          'La récupération n’est pas disponible pour le moment. Enregistre régulièrement ton dessin.',
        ),
        findsOneWidget,
      );
      expect(find.byType(SelectableText), findsNothing);
      expect(recovery.bytes, original);
      await _details(tester);
      expect(_detailsText(tester), isNotEmpty);
      await _closeDetails(tester);
      await _draw(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(recovery.bytes, original);
      expect(recovery.writes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'cancelling file and unsaved-changes choices does not create an error',
    (tester) async {
      final files = _Files();
      await _mount(tester, files, MemoryRecovery());
      await _draw(tester);
      await _open(tester);
      expect(find.byKey(const Key('problemMessage')), findsNothing);
      files.openPath = '/drawings/other.edupaint';
      files.projects[files.openPath!] = _fixture('portrait-v2.edupaint');
      _menu(tester).onOpen!();
      await waitForPreparedOpen(tester, allowSaveDecision: true);
      await tester.tap(find.byKey(const Key('cancelChanges')));
      await waitForPreparedOpen(tester);
      expect(find.byKey(const Key('problemMessage')), findsNothing);
      expect(find.byKey(const Key('showProblemDetails')), findsNothing);
      expect(find.textContaining('1 élément'), findsOneWidget);
      expect(files.writesAttempted, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'repeated errors keep only latest details and busy press does not consume notice',
    (tester) async {
      final files = _Files()
        ..openPath = '/drawings/unreadable.edupaint'
        ..readError = const FileSystemException('first-read-marker');
      await _mount(tester, files, MemoryRecovery());
      await _open(tester);
      files.readError = const FileSystemException('latest-read-marker');
      await _open(tester);
      expect(find.byKey(const Key('problemMessage')), findsOneWidget);
      final action = tester
          .widget<TextButton>(find.byKey(const Key('showProblemDetails')))
          .onPressed!;
      files.readBarrier = Completer<Uint8List>();
      _menu(tester).onOpen!();
      await tester.pump();
      action();
      await tester.pump();
      expect(find.byKey(const Key('problemDetailsDialog')), findsNothing);
      expect(find.byKey(const Key('showProblemDetails')), findsOneWidget);
      files.readBarrier!.completeError(
        const FileSystemException('final-read-marker'),
      );
      await waitForPreparedOpen(tester);
      await _details(tester);
      expect(_detailsText(tester), contains('final-read-marker'));
      expect(_detailsText(tester), isNot(contains('first-read-marker')));
      expect(_detailsText(tester), isNot(contains('latest-read-marker')));
      await _closeDetails(tester);
      await tester.pump(const Duration(seconds: 20));
      expect(find.byKey(const Key('problemMessage')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'diagnostic notification stays accessible beyond its delay at 150 percent until explicitly closed',
    (tester) async {
      final files = _Files()
        ..openPath = '/drawings/unreadable.edupaint'
        ..readError = const FileSystemException('persistent-details-marker');
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _mount(tester, files, MemoryRecovery());
      await _open(tester);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('showProblemDetails')), findsOneWidget);
      expect(find.byKey(const Key('problemMessage')), findsOneWidget);
      expect(tester.takeException(), isNull);
      final close = find.descendant(
        of: find.byType(SnackBar),
        matching: find.byTooltip('Fermer'),
      );
      expect(close, findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('showProblemDetails')), findsNothing);
      expect(find.byKey(const Key('problemMessage')), findsNothing);
      expect(files.writesAttempted, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'late read failure after unmount creates no error UI or framework exception',
    (tester) async {
      final files = _Files()
        ..openPath = '/drawings/held.edupaint'
        ..readBarrier = Completer<Uint8List>();
      await _mount(tester, files, MemoryRecovery());
      _menu(tester).onOpen!();
      await tester.pump();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      files.readBarrier!.completeError(
        const FileSystemException('late-read-marker'),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('problemMessage')), findsNothing);
      expect(files.writesAttempted, 0);
    },
    skip: !available,
  );

  testWidgets(
    'long diagnostic fits a small dialog at 150 percent and closes by keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final longDiagnostic =
          'diagnostic-start\n${'ligne de diagnostic avec un symbole 🎨\n' * 500}diagnostic-end';
      final problem = StudioProblem.fromError(
        FileSystemException(longDiagnostic),
        message:
            'Ce projet n’a pas pu être ouvert. Le dessin actuel est conservé.',
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => StudioProblemDialog(problem: problem),
                  ),
                  child: const Text('Détails'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Détails'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final retained = _detailsText(tester);
      expect(retained, contains('diagnostic-start'));
      expect(retained, isNot(contains('diagnostic-end')));
      expect(retained.length, lessThanOrEqualTo(8192));
      expect(find.byKey(const Key('problemDetailsTruncated')), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final close = tester.getRect(
        find.byKey(const Key('closeProblemDetails')),
      );
      expect(close.bottom, lessThanOrEqualTo(300));
      expect(close.top, greaterThanOrEqualTo(0));
      await _closeDetails(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
