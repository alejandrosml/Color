// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';

final _surface = find.byKey(const Key('drawingSurface'));

class _ImageFiles extends MemoryFiles {
  final images = <String, Uint8List>{};
  String? imagePath;
  bool failImageRead = false;
  Completer<Uint8List>? pendingImageRead;
  int imageDialogs = 0;
  int imageReads = 0;
  int openDialogs = 0;
  int exportDialogs = 0;
  int projectWrites = 0;

  @override
  Future<String?> chooseImage() async {
    imageDialogs++;
    return imagePath;
  }

  @override
  Future<Uint8List> readImage(String path) async {
    imageReads++;
    if (failImageRead) {
      throw const FileSystemException('Simulated image read failure');
    }
    if (pendingImageRead case final pending?) {
      return pending.future;
    }
    return Uint8List.fromList(images[path]!);
  }

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

  @override
  Future<void> write(String path, Uint8List bytes) async {
    projectWrites++;
    return super.write(path, bytes);
  }
}

Uint8List _fixture(String name) =>
    File('test/fixtures/raster/$name').readAsBytesSync();

dynamic _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.descendant(of: _surface, matching: find.byType(CustomPaint)).first,
    )
    .painter;

DocumentViewport _viewport(WidgetTester tester) =>
    _painter(tester).viewport as DocumentViewport;

Offset _point(WidgetTester tester, double x, double y) {
  final viewport = _viewport(tester);
  return tester.getTopLeft(_surface) +
      Offset(
        viewport.left + x * viewport.scale,
        viewport.top + y * viewport.scale,
      );
}

bool _idle(WidgetTester tester) {
  final buttons = find.byKey(const Key('importImage'));
  return buttons.evaluate().isNotEmpty &&
      tester.widget<OutlinedButton>(buttons).onPressed != null;
}

/// Real image codecs and worker isolates need real event-loop turns. A busy
/// spinner deliberately never settles, so wait for an observable condition.
Future<void> _until(
  WidgetTester tester,
  bool Function() complete,
  String reason,
) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (complete()) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  fail('Image workflow did not complete: $reason');
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _idleAfterTap(WidgetTester tester, String key) async {
  await _tap(tester, key);
  await _until(tester, () => _idle(tester), key);
}

Future<void> _mount(
  WidgetTester tester,
  _ImageFiles files,
  MemoryRecovery recovery, {
  bool expectRecovery = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(EduPaintApp(files: files, recoveryStorage: recovery));
  await _until(
    tester,
    () => expectRecovery
        ? find.byKey(const Key('restoreRecovery')).evaluate().isNotEmpty
        : _idle(tester),
    'startup/recovery',
  );
}

Future<void> _import(WidgetTester tester, {bool confirmation = false}) async {
  await _tap(tester, 'importImage');
  await _until(
    tester,
    () => confirmation
        ? find.byKey(const Key('cancelChanges')).evaluate().isNotEmpty
        : _idle(tester),
    'image import',
  );
}

Future<void> _draw(WidgetTester tester) async {
  await _idleAfterTap(tester, 'tool-stroke');
  final view = _viewport(tester);
  final gesture = await tester.startGesture(
    _point(tester, view.documentWidth * .3, view.documentHeight * .5),
  );
  await gesture.moveTo(
    _point(tester, view.documentWidth * .7, view.documentHeight * .5),
  );
  await gesture.up();
  await tester.pump();
}

Future<void> _flushRecovery(
  WidgetTester tester,
  MemoryRecovery recovery,
) async {
  await tester.pump(const Duration(milliseconds: 500));
  await _until(tester, () => recovery.bytes != null, 'recovery write');
}

Future<void> _exportSvg(WidgetTester tester, _ImageFiles files) async {
  files.svg = null;
  await _tap(tester, 'exportImage');
  await _until(
    tester,
    () => find.byKey(const Key('exportSvg')).evaluate().isNotEmpty,
    'export choices',
  );
  await _tap(tester, 'exportSvg');
  await _until(tester, () => files.svg != null && _idle(tester), 'SVG export');
}

Future<void> _exportPng(WidgetTester tester, _ImageFiles files) async {
  files.png = null;
  await _tap(tester, 'exportImage');
  await _until(
    tester,
    () => find.byKey(const Key('exportPng')).evaluate().isNotEmpty,
    'export choices',
  );
  await _tap(tester, 'exportPng');
  await _until(tester, () => files.png != null && _idle(tester), 'PNG export');
}

Future<List<int>> _pixel(Uint8List png, int x, int y) async {
  final codec = await ui.instantiateImageCodec(png);
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (y * image.width + x) * 4;
    return List<int>.generate(4, (index) => data!.getUint8(offset + index));
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

Future<(_ImageFiles, MemoryRecovery)> _dirtyBackground(
  WidgetTester tester,
) async {
  final files = _ImageFiles()
    ..imagePath = '/images/old.png'
    ..images['/images/old.png'] = _fixture('rgb-asymmetric.png')
    ..images['/images/new.jpg'] = _fixture('jpeg-exif-orientation-6.jpg');
  final recovery = MemoryRecovery();
  await _mount(tester, files, recovery);
  await _import(tester);
  await _draw(tester);
  await _flushRecovery(tester, recovery);
  files.imagePath = '/images/new.jpg';
  return (files, recovery);
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  for (final source in [
    (name: 'rgb-asymmetric.png', width: 32, height: 24, corner: [230, 35, 40]),
    (
      name: 'jpeg-exif-orientation-6.jpg',
      width: 24,
      height: 32,
      corner: [40, 80, 220],
    ),
  ]) {
    testWidgets(
      '${source.name}: background, vectors, exports, save, reopen and recovery',
      (tester) async {
        final bytes = _fixture(source.name);
        final original = Uint8List.fromList(bytes);
        final files = _ImageFiles()
          ..imagePath = '/images/source'
          ..images['/images/source'] = bytes;
        final recovery = MemoryRecovery();
        await _mount(tester, files, recovery);
        await _import(tester);
        expect(
          [_viewport(tester).documentWidth, _viewport(tester).documentHeight],
          [source.width, source.height],
        );
        final background = _painter(tester).background as ui.Image;
        expect(_painter(tester).strokes, isEmpty);

        await _idleAfterTap(tester, 'tool-select');
        await tester.tapAt(_point(tester, 4, 4));
        await tester.pump();
        expect(
          _painter(tester).selectedIndex,
          isNull,
          reason: 'The imported picture is not a vector object.',
        );
        expect(_painter(tester).strokes, isEmpty);
        await _exportPng(tester, files);
        final corner = await tester.runAsync(() => _pixel(files.png!, 4, 4));
        for (var channel = 0; channel < 3; channel++) {
          expect(corner![channel], closeTo(source.corner[channel], 3));
        }
        expect(corner![3], 255);
        await _draw(tester);
        expect(_painter(tester).strokes, hasLength(1));
        await _idleAfterTap(tester, 'undo');
        expect(_painter(tester).strokes, isEmpty);
        expect(identical(_painter(tester).background, background), isTrue);
        await _idleAfterTap(tester, 'redo');
        await _exportSvg(tester, files);
        expect(files.svg, contains('<image'));
        expect(files.svg, contains('<path'));
        final match = RegExp('href="data:image/png;base64,([^"]+)"')
            .firstMatch(files.svg!);
        expect(match, isNotNull);
        final embedded = base64Decode(match![1]!);
        await _idleAfterTap(tester, 'saveProject');
        final savedBytes = Uint8List.fromList(files.projects[files.savePath!]!);
        final saved = RustDocument.fromProject(savedBytes);
        try {
          expect(
            [saved.width, saved.height, saved.count],
            [source.width, source.height, 1],
          );
          expect(saved.copyBackgroundPng(), embedded);
        } finally {
          saved.dispose();
        }
        expect(
          files.images['/images/source'],
          original,
          reason: 'Import never writes back into the source image.',
        );
        files.images
            .clear(); // The original may move or disappear after import.
        await _tap(tester, 'newProject');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('newSheetDialog')), findsOneWidget);
        await _idleAfterTap(tester, 'createNewSheet');
        expect(_painter(tester).background, isNull);
        expect(background.debugDisposed, isTrue);
        files.openPath = files.savePath;
        await _idleAfterTap(tester, 'openProject');
        expect(_painter(tester).strokes, hasLength(1));
        expect(_painter(tester).background, isNotNull);
        await _draw(tester);
        await _flushRecovery(tester, recovery);
        final recoveredBytes = Uint8List.fromList(recovery.bytes!);
        await tester.pumpWidget(const SizedBox.shrink());
        await _mount(
          tester,
          files,
          MemoryRecovery(recoveredBytes),
          expectRecovery: true,
        );
        await _idleAfterTap(tester, 'restoreRecovery');
        expect(_painter(tester).strokes, hasLength(2));
        expect(_painter(tester).background, isNotNull);
        await _idleAfterTap(tester, 'saveProject');
        final restored = RustDocument.fromProject(
          files.projects[files.savePath!]!,
        );
        try {
          expect(restored.count, 2);
          expect(restored.copyBackgroundPng(), embedded);
        } finally {
          restored.dispose();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: !available,
    );
  }

  for (final failure in [
    'picker cancel',
    'read failure',
    'invalid image',
    'confirmation cancel',
    'save cancel',
    'save failure',
  ]) {
    testWidgets('$failure preserves the current hybrid drawing and recovery', (
      tester,
    ) async {
      final (files, recovery) = await _dirtyBackground(tester);
      final before = Uint8List.fromList(recovery.bytes!);
      final strokes = _painter(tester).strokes;
      final background = _painter(tester).background as ui.Image;
      if (failure == 'picker cancel') {
        files.imagePath = null;
      }
      if (failure == 'read failure') {
        files.failImageRead = true;
      }
      if (failure == 'invalid image') {
        files.images[files.imagePath!] = _fixture('invalid-truncated-ihdr.png');
      }
      final confirmation =
          failure == 'confirmation cancel' || failure.startsWith('save');
      await _import(tester, confirmation: confirmation);
      if (failure == 'confirmation cancel') {
        await _idleAfterTap(tester, 'cancelChanges');
      }
      if (failure == 'save cancel' || failure == 'save failure') {
        if (failure == 'save cancel') {
          files.savePath = null;
        }
        if (failure == 'save failure') {
          files.failWrite = true;
        }
        await _idleAfterTap(tester, 'saveChanges');
      }
      expect(find.byKey(const Key('cancelChanges')), findsNothing);
      expect(identical(_painter(tester).strokes, strokes), isTrue);
      expect(identical(_painter(tester).background, background), isTrue);
      expect(background.debugDisposed, isFalse);
      expect(recovery.bytes, before);
      expect(files.projects, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, skip: !available);
  }

  testWidgets(
    'structurally valid v3 with undecodable PNG cannot replace a modified drawing',
    (tester) async {
      final (files, recovery) = await _dirtyBackground(tester);
      final before = Uint8List.fromList(recovery.bytes!);
      final strokes = _painter(tester).strokes;
      final background = _painter(tester).background;
      final bad = RustDocument.fromBackgroundPng(_undecodablePng());
      try {
        files.openPath = '/drawings/bad-image.edupaint';
        files.projects[files.openPath!] = bad.exportProject();
      } finally {
        bad.dispose();
      }
      await _idleAfterTap(tester, 'openProject');
      expect(find.byKey(const Key('cancelChanges')), findsNothing);
      expect(identical(_painter(tester).strokes, strokes), isTrue);
      expect(identical(_painter(tester).background, background), isTrue);
      expect(recovery.bytes, before);
      expect(
        find.textContaining('Le dessin actuel est conservé.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'undecodable recovery is preserved and not overwritten by new drawing',
    (tester) async {
      final bad = RustDocument.fromBackgroundPng(_undecodablePng());
      final bytes = bad.exportProject();
      bad.dispose();
      final recovery = MemoryRecovery(bytes);
      await _mount(tester, _ImageFiles(), recovery);
      expect(find.byKey(const Key('restoreRecovery')), findsNothing);
      await _draw(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(recovery.bytes, bytes);
      expect(recovery.writes, 0);
      expect(_painter(tester).strokes, hasLength(1));
      expect(_painter(tester).background, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'native commands captured before import are guarded during the pending read',
    (tester) async {
      final (files, recovery) = await _dirtyBackground(tester);
      await _idleAfterTap(tester, 'tool-select');
      await tester.tapAt(_point(tester, 16, 12));
      await tester.pump();
      final commands = tester.widget<EduPaintDesktopMenu>(
        find.byType(EduPaintDesktopMenu),
      );
      final before = Uint8List.fromList(recovery.bytes!);
      final strokes = _painter(tester).strokes;
      final background = _painter(tester).background;
      final dialogs = (
        files.openDialogs,
        files.saveDialogCount,
        files.exportDialogs,
      );
      final pending = Completer<Uint8List>();
      files.pendingImageRead = pending;
      await _tap(tester, 'importImage');
      await _until(tester, () => files.imageReads == 2, 'pending image read');
      commands.onNew!();
      commands.onOpen!();
      commands.onImportImage!();
      commands.onSave!();
      commands.onSaveAs!();
      commands.onExportSvg!();
      commands.onExportPng!();
      commands.onUndo!();
      commands.onDuplicate?.call();
      commands.onDelete?.call();
      commands.onAbout?.call();
      await tester.pump();
      expect((
        files.openDialogs,
        files.saveDialogCount,
        files.exportDialogs,
      ), dialogs);
      expect(files.imageDialogs, 2);
      expect(files.projectWrites, 0);
      expect(identical(_painter(tester).strokes, strokes), isTrue);
      expect(identical(_painter(tester).background, background), isTrue);
      expect(recovery.bytes, before);
      if (Platform.isMacOS) {
        const codec = StandardMethodCodec();
        final exit = Completer<Object?>();
        tester.binding.channelBuffers.push(
          'org.edupaint/lifecycle',
          codec.encodeMethodCall(const MethodCall('requestExit')),
          (ByteData? data) {
            exit.complete(data == null ? null : codec.decodeEnvelope(data));
          },
        );
        await tester.pump();
        expect(await exit.future, {'response': 'cancel'});
      }
      pending.complete(_fixture('jpeg-exif-orientation-6.jpg'));
      await _until(
        tester,
        () => find.byKey(const Key('cancelChanges')).evaluate().isNotEmpty,
        'confirmation after read',
      );
      await _idleAfterTap(tester, 'cancelChanges');
      expect(recovery.bytes, before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !available,
  );

  testWidgets(
    'disposal during an image read discards its late result without decoding',
    (tester) async {
      final (files, recovery) = await _dirtyBackground(tester);
      final before = Uint8List.fromList(recovery.bytes!);
      final background = _painter(tester).background as ui.Image;
      final pending = Completer<Uint8List>();
      files.pendingImageRead = pending;
      await _tap(tester, 'importImage');
      await _until(tester, () => files.imageReads == 2, 'pending image read');
      var imagesCreated = 0;
      final previous = ui.Image.onCreate;
      ui.Image.onCreate = (image) {
        imagesCreated++;
        previous?.call(image);
      };
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        expect(background.debugDisposed, isTrue);
        pending.complete(_fixture('jpeg-exif-orientation-6.jpg'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        expect(imagesCreated, 0);
        expect(recovery.bytes, before);
        expect(files.projects, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        ui.Image.onCreate = previous;
      }
    },
    skip: !available,
  );
}

/// Keeps PNG lengths/CRCs and project structure valid, but destroys the zlib
/// pixel stream. Rust deliberately validates structure without decoding pixels.
Uint8List _undecodablePng() {
  final bytes = _fixture('rgb-asymmetric.png');
  final data = ByteData.sublistView(bytes);
  for (var cursor = 8; cursor < bytes.length;) {
    final length = data.getUint32(cursor);
    final type = String.fromCharCodes(bytes.sublist(cursor + 4, cursor + 8));
    if (type == 'IDAT') {
      bytes.fillRange(cursor + 8, cursor + 8 + length, 0);
      var crc = 0xffffffff;
      for (var index = cursor + 4; index < cursor + 8 + length; index++) {
        crc ^= bytes[index];
        for (var bit = 0; bit < 8; bit++) {
          crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
        }
      }
      data.setUint32(cursor + 8 + length, crc ^ 0xffffffff);
      return bytes;
    }
    cursor += length + 12;
  }
  throw StateError('Expected an IDAT chunk in the generated fixture.');
}
