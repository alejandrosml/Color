// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';

import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_questions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  const title = 'Un dessin que tu peux retrouver.';

  Future<void> start(WidgetTester tester, MemoryFiles files) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EduPaintApp(files: files, recoveryStorage: MemoryRecovery()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  EduPaintDesktopMenu menu(WidgetTester tester) =>
      tester.widget<EduPaintDesktopMenu>(find.byType(EduPaintDesktopMenu));

  Future<void> draw(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('drawingSurface'))),
    );
    await gesture.moveBy(const Offset(45, -20));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<Object?> requestNativeExit(WidgetTester tester) {
    const codec = StandardMethodCodec();
    final response = Completer<Object?>();
    tester.binding.channelBuffers.push(
      'org.edupaint/lifecycle',
      codec.encodeMethodCall(const MethodCall('requestExit')),
      (ByteData? bytes) =>
          response.complete(bytes == null ? null : codec.decodeEnvelope(bytes)),
    );
    return response.future;
  }

  testWidgets(
    'repeated About menu actions open one dialog and one close removes it',
    (tester) async {
      await start(tester, MemoryFiles());
      final callback = menu(tester).onAbout!;
      callback();
      callback();
      callback();
      await tester.pumpAndSettle();
      expect(find.text(title, skipOffstage: false), findsOneWidget);
      // The logo heads the dialog, drawn from the core's SVG, and says what
      // it shows.
      expect(find.byKey(const Key('aboutLogo')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('aboutLogo'))),
        const Size(112, 112),
      );
      expect(find.bySemanticsLabel(ColorLogo.description), findsOneWidget);
      callback();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      await tester.tap(find.text('Revenir au dessin'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      // Closing normally releases the guard and permits another explicit opening.
      menu(tester).onAbout!();
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      await tester.tap(find.text('Revenir au dessin'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'About blocks document commands and Escape restores save confirmation',
    (tester) async {
      final files = _ObservedFiles();
      await start(tester, files);
      await draw(tester);
      final commands = menu(tester);
      commands.onAbout!();
      await tester.pumpAndSettle();
      commands.onNew!();
      commands.onOpen!();
      commands.onSave!();
      commands.onExportSvg!();
      commands.onExportPng!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      expect(files.openDialogs, 0);
      expect(files.exportDialogs, 0);
      expect(files.saveDialogCount, 0);
      expect(files.projects, isEmpty);
      if (Platform.isMacOS) {
        expect(await requestNativeExit(tester), {'response': 'cancel'});
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      expect(find.textContaining('1 élément'), findsOneWidget);
      menu(tester).onNew!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createNewSheet')));
      await tester.pumpAndSettle();
      expect(find.text('Garder les modifications ?'), findsOneWidget);
      // About must not stack on a save/discard confirmation either.
      menu(tester).onAbout!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      expect(find.text(title, skipOffstage: false), findsNothing);
      await tester.tap(find.byKey(const Key('saveChanges')));
      await tester.pumpAndSettle();
      expect(find.textContaining('0 élément · '), findsOneWidget);
      final saved = RustDocument.fromProject(files.projects.values.single);
      try {
        expect(saved.count, 1);
      } finally {
        saved.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );
}

final class _ObservedFiles extends MemoryFiles {
  int openDialogs = 0;
  int exportDialogs = 0;
  @override
  Future<String?> chooseOpen() async {
    openDialogs++;
    return super.chooseOpen();
  }

  @override
  Future<String?> chooseExport({String? currentPath}) async {
    exportDialogs++;
    return super.chooseExport(currentPath: currentPath);
  }

  @override
  Future<String?> choosePng({String? currentPath}) async {
    exportDialogs++;
    return super.choosePng(currentPath: currentPath);
  }
}
