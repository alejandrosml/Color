// SPDX-License-Identifier: MIT
// Regression checks for isolated native-exit admission proposal. No OS termination.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/memory_files.dart';

class _Files extends MemoryFiles {
  int opens = 0;
  int images = 0;
  int exports = 0;
  @override
  Future<String?> chooseOpen() async { opens++; return super.chooseOpen(); }
  @override
  Future<String?> chooseImage() async { images++; return null; }
  @override
  Future<String?> chooseExport({String? currentPath}) async { exports++; return super.chooseExport(currentPath: currentPath); }
  @override
  Future<String?> choosePng({String? currentPath}) async { exports++; return super.choosePng(currentPath: currentPath); }
}
class _Recovery extends MemoryRecovery {
  int clears = 0;
  bool failClear = false;
  @override
  Future<void> clearRecovery() async {
    clears++;
    if (failClear) throw const FileSystemException('Synthetic recovery clear failure');
    await super.clearRecovery();
  }
}
class _CancelObserver extends WidgetsBindingObserver {
  int requests = 0;
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    requests++;
    return AppExitResponse.cancel;
  }
}
const _channel = MethodChannel('org.edupaint/lifecycle');
const _codec = StandardMethodCodec();
Future<Object?> _nativeRequest(WidgetTester tester) {
  final result = Completer<Object?>();
  tester.binding.channelBuffers.push(
    _channel.name,
    _codec.encodeMethodCall(const MethodCall('requestExit')),
    (ByteData? bytes) => result.complete(bytes == null ? null : _codec.decodeEnvelope(bytes)),
  );
  return result.future;
}
Future<T> _settleReply<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  future.then((_) => done = true);
  for (var i = 0; i < 20 && !done; i++) {
    await tester.pump();
  }
  expect(done, isTrue, reason: 'bounded local callback must complete');
  return future;
}
EduPaintDesktopMenu _menu(WidgetTester tester) => tester.widget<EduPaintDesktopMenu>(find.byType(EduPaintDesktopMenu));
Future<void> _mount(WidgetTester tester, MemoryFiles files, _Recovery recovery) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 760);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
  await tester.pumpWidget(EduPaintApp(files: files, recoveryStorage: recovery));
  for (var i = 0; i < 20 && _menu(tester).onSave == null; i++) {
    await tester.pump();
  }
  expect(_menu(tester).onSave, isNotNull);
}
Future<void> _draw(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('drawingSurface'))));
  await gesture.moveBy(const Offset(30, -15));
  await gesture.up();
  await tester.pump();
}
void main() {
  final available = Platform.isMacOS && Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  testWidgets('final native exit approval refuses gestures and stale menu commands', (tester) async {
    final files = _Files(); final recovery = _Recovery();
    await _mount(tester, files, recovery);
    final stale = _menu(tester);
    expect(await _settleReply(tester, _nativeRequest(tester)), {'response': 'exit'});
    expect(recovery.clears, 1);
    expect(recovery.bytes, isNull);
    // We intentionally delay host termination after its exit response, allowing
    // the same event ordering as the queued AppKit completion/terminate blocks.
    expect(_menu(tester).onSave, isNull);
    expect(_menu(tester).onNew, isNull);
    // Callback objects can survive a rebuild. Their own admission checks matter.
    stale.onSave!(); stale.onSaveAs!(); stale.onNew!(); stale.onOpen!();
    stale.onImportImage!(); stale.onExportSvg!(); stale.onExportPng!();
    await tester.pump();
    expect(find.byKey(const Key('createNewSheet')), findsNothing);
    expect(files.saveDialogCount, 0);
    expect(files.opens, 0); expect(files.images, 0); expect(files.exports, 0);
    expect(files.projects, isEmpty);
    expect(files.png, isNull); expect(files.svg, isNull);
    await _draw(tester);
    expect(find.textContaining('0 élément · nouvelle feuille'), findsOneWidget);
    expect(recovery.writes, 0, reason: 'the recovery debounce has not elapsed');
    expect(recovery.bytes, isNull);
    // This simulates view teardown only; no process, VM or application is quit.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(recovery.bytes, isNull);
    expect(recovery.writes, 0);
    expect(files.projects, isEmpty);
    expect(tester.takeException(), isNull);
  }, skip: !available);
  testWidgets('cancelled native exit keeps admission and the existing dirty drawing', (tester) async {
    final files = _Files(); final recovery = _Recovery();
    await _mount(tester, files, recovery); await _draw(tester);
    final reply = _nativeRequest(tester);
    await tester.pump(); await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('cancelChanges')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancelChanges')));
    expect(await _settleReply(tester, reply), {'response': 'cancel'});
    expect(recovery.clears, 0);
    expect(_menu(tester).onSave, isNotNull);
    await _draw(tester);
    expect(find.textContaining('2 éléments · modifications non enregistrées'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  }, skip: !available);
  testWidgets('native exit recovery error returns cancel and restores editing', (tester) async {
    final files = _Files(); final recovery = _Recovery();
    await _mount(tester, files, recovery);
    recovery.failClear = true;
    expect(await _settleReply(tester, _nativeRequest(tester)), {'response': 'cancel'});
    expect(recovery.clears, 1);
    expect(_menu(tester).onSave, isNotNull);
    await _draw(tester);
    expect(find.textContaining('1 élément · modifications non enregistrées'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  }, skip: !available);
  testWidgets('framework aggregate can cancel after the studio voted exit', (tester) async {
    final files = _Files(); final recovery = _Recovery();
    await _mount(tester, files, recovery);
    final later = _CancelObserver(); tester.binding.addObserver(later);
    addTearDown(() => tester.binding.removeObserver(later));
    final reply = tester.binding.handleRequestAppExit();
    expect(await _settleReply(tester, reply), AppExitResponse.cancel);
    expect(later.requests, 1);
    expect(recovery.clears, 1, reason: 'Studio exit vote completed before a later veto');
    expect(_menu(tester).onSave, isNotNull);
    await _draw(tester);
    expect(find.textContaining('1 élément · modifications non enregistrées'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  }, skip: !available);
}
