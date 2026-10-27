// SPDX-License-Identifier: MIT
// Fictional paths and injected panels only: no native GUI or filesystem writes.
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:edupaint_flutter_study/studio_files.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

String _path(String suffix) =>
    '${Platform.isWindows ? r'C:\ColorOpenTest' : '/ColorOpenTest'}${Platform.pathSeparator}'
    '${suffix.replaceAll('/', Platform.pathSeparator)}';

class _Request {
  _Request(this.directory, this.groups, this.confirmText);
  final String? directory;
  final List<XTypeGroup> groups;
  final String confirmText;
}

class _Panels {
  final replies = Queue<Object?>();
  final saveReplies = Queue<Object?>();
  final requests = <_Request>[];
  final saveRequests = <_Request>[];
  int documentsLookups = 0;

  Future<String?> documents() async {
    documentsLookups++;
    return _path('Documents');
  }

  Future<String?> choose({
    required String? initialDirectory,
    required List<XTypeGroup> acceptedTypeGroups,
    required String confirmButtonText,
  }) async {
    requests.add(
      _Request(initialDirectory, acceptedTypeGroups, confirmButtonText),
    );
    final reply = replies.removeFirst();
    if (reply is Exception) throw reply;
    return reply as String?;
  }

  Future<String?> save({
    required String suggestedName,
    required String? initialDirectory,
    required List<XTypeGroup> acceptedTypeGroups,
    required String confirmButtonText,
  }) async {
    saveRequests.add(
      _Request(initialDirectory, acceptedTypeGroups, confirmButtonText),
    );
    final reply = saveReplies.removeFirst();
    if (reply is Exception) throw reply;
    return reply as String?;
  }

  StudioFiles files([StudioDestinationSession? memory]) => StudioFiles(
    openChooser: choose,
    saveChooser: save,
    documentsDirectory: documents,
    destinationSession: memory ?? StudioDestinationSession(),
  );
}

class _ReadFails extends StudioFiles {
  const _ReadFails({
    super.openChooser,
    super.documentsDirectory,
    super.destinationSession,
  });

  @override
  Future<Uint8List> read(String path) =>
      Future.error(const FileSystemException('Synthetic read failure'));
  @override
  Future<Uint8List> readImage(String path) =>
      Future.error(const FileSystemException('Synthetic image failure'));
}

void main() {
  for (final image in [false, true]) {
    final label = image ? 'image' : 'project';
    Future<String?> choose(StudioFiles files) =>
        image ? files.chooseImage() : files.chooseOpen();
    test(
      '$label panel follows each confirmed directory in this session',
      () async {
        final panels = _Panels();
        final files = panels.files();
        panels.replies.addAll([_path('One/a.file'), _path('Two/b.file'), null]);
        expect(await choose(files), _path('One/a.file'));
        expect(await choose(files), _path('Two/b.file'));
        expect(await choose(files), isNull);
        expect(panels.requests.map((r) => r.directory), [
          _path('Documents'),
          _path('One'),
          _path('Two'),
        ]);
        expect(panels.documentsLookups, 1);
      },
    );
    test(
      '$label cancellation and panel failure preserve last choice',
      () async {
        final panels = _Panels();
        final files = panels.files();
        panels.replies.addAll([
          _path('Chosen/a.file'),
          null,
          const FileSystemException('Synthetic panel failure'),
          null,
        ]);
        await choose(files);
        expect(await choose(files), isNull);
        await expectLater(choose(files), throwsA(isA<FileSystemException>()));
        expect(await choose(files), isNull);
        expect(
          panels.requests.skip(1).map((r) => r.directory),
          List.filled(3, _path('Chosen')),
        );
        expect(panels.documentsLookups, 1);
      },
    );
    test(
      '$label initial cancellation or failure never creates a remembered folder',
      () async {
        final panels = _Panels();
        final files = panels.files();
        panels.replies.addAll([
          null,
          const FileSystemException('Synthetic panel failure'),
          null,
        ]);
        expect(await choose(files), isNull);
        await expectLater(choose(files), throwsA(isA<FileSystemException>()));
        expect(await choose(files), isNull);
        expect(
          panels.requests.map((r) => r.directory),
          List.filled(3, _path('Documents')),
        );
        expect(panels.documentsLookups, 3);
      },
    );
    test(
      '$label confirmed relative path remembers normalized absolute parent only',
      () async {
        final panels = _Panels();
        final files = panels.files();
        final selected = 'ColorOpenSession/unused/../choix/dessin.file';
        panels.replies.addAll([selected, null]);
        // The caller still receives exactly the selected path.
        expect(await choose(files), selected);
        await choose(files);
        expect(
          panels.requests.last.directory,
          '${Directory.current.path}${Platform.pathSeparator}ColorOpenSession${Platform.pathSeparator}choix',
        );
      },
    );
  }

  test('project and image panels have two independent memories', () async {
    final panels = _Panels();
    final files = panels.files();
    panels.replies.addAll([
      _path('Projects/a.edupaint'),
      _path('Photos/a.png'),
      _path('OtherProjects/b.edupaint'),
      null,
      null,
    ]);
    await files.chooseOpen();
    await files.chooseImage();
    await files.chooseOpen();
    await files.chooseImage();
    await files.chooseOpen();
    expect(panels.requests.map((r) => r.directory), [
      _path('Documents'),
      _path('Documents'),
      _path('Projects'),
      _path('Photos'),
      _path('OtherProjects'),
    ]);
    expect(panels.documentsLookups, 2);
  });

  test(
    'project and image panel types and child-facing labels stay unchanged',
    () async {
      final panels = _Panels();
      final files = panels.files();
      panels.replies.addAll([null, null]);
      await files.chooseOpen();
      await files.chooseImage();
      expect(panels.requests[0].confirmText, 'Ouvrir le dessin');
      expect(panels.requests[0].groups.single.label, 'Projet Color');
      expect(panels.requests[0].groups.single.extensions, ['edupaint']);
      expect(panels.requests[0].groups.single.uniformTypeIdentifiers, [
        'org.edupaint.project',
      ]);
      expect(panels.requests[1].confirmText, 'Dessiner sur cette image');
      expect(panels.requests[1].groups.single.label, 'Image PNG ou JPEG');
      expect(panels.requests[1].groups.single.extensions, [
        'png',
        'jpg',
        'jpeg',
      ]);
      expect(panels.requests[1].groups.single.uniformTypeIdentifiers, [
        'public.png',
        'public.jpeg',
      ]);
    },
  );

  test(
    'later project and image read failures do not undo explicit selections',
    () async {
      final panels = _Panels();
      final files = _ReadFails(
        openChooser: panels.choose,
        documentsDirectory: panels.documents,
        destinationSession: StudioDestinationSession(),
      );
      panels.replies.addAll([
        _path('BrokenProject/a.edupaint'),
        _path('BrokenImage/a.png'),
        null,
        null,
      ]);
      final project = await files.chooseOpen();
      await expectLater(
        files.read(project!),
        throwsA(isA<FileSystemException>()),
      );
      final image = await files.chooseImage();
      await expectLater(
        files.readImage(image!),
        throwsA(isA<FileSystemException>()),
      );
      await files.chooseOpen();
      await files.chooseImage();
      expect(panels.requests.map((r) => r.directory), [
        _path('Documents'),
        _path('Documents'),
        _path('BrokenProject'),
        _path('BrokenImage'),
      ]);
    },
  );

  test('memory can be shared by replacement adapters or isolated for another session', () async {
    final panels = _Panels();
    final memory = StudioDestinationSession();
    panels.replies.addAll([
      _path('Projects/a.edupaint'),
      _path('Photos/a.png'),
      null,
      null,
      null,
      null,
    ]);
    await panels.files(memory).chooseOpen();
    await panels.files(memory).chooseImage();
    await panels.files(memory).chooseOpen();
    await panels.files(memory).chooseImage();
    final other = panels.files();
    await other.chooseOpen();
    await other.chooseImage();
    expect(panels.requests.map((r) => r.directory), [
      _path('Documents'),
      _path('Documents'),
      _path('Projects'),
      _path('Photos'),
      _path('Documents'),
      _path('Documents'),
    ]);
  });

  test('open choices and existing save or export destinations never overwrite each other', () async {
    final panels = _Panels();
    final files = panels.files();
    panels.replies.addAll([
      _path('Opened/a.edupaint'),
      _path('Photos/a.png'),
      null,
      null,
    ]);
    panels.saveReplies.addAll([
      _path('Saved/a.edupaint'),
      _path('Exports/a.png'),
      null,
    ]);
    await files.chooseSave();
    await files.chooseOpen();
    await files.chooseImage();
    await files.choosePng();
    await files.chooseOpen();
    await files.chooseImage();
    await files.chooseExport();
    expect(panels.requests.map((r) => r.directory), [
      _path('Documents'),
      _path('Documents'),
      _path('Opened'),
      _path('Photos'),
    ]);
    expect(panels.saveRequests.map((r) => r.directory), [
      _path('Documents'),
      _path('Saved'),
      _path('Exports'),
    ]);
  });

  test('missing Documents lets each native panel pick its own default until confirmation', () async {
    final panels = _Panels();
    final files = StudioFiles(
      openChooser: panels.choose,
      documentsDirectory: () async => null,
      destinationSession: StudioDestinationSession(),
    );
    panels.replies.addAll([
      null,
      _path('SelectedImage/a.png'),
      _path('SelectedProject/a.edupaint'),
      null,
      null,
    ]);
    await files.chooseOpen();
    await files.chooseImage();
    await files.chooseOpen();
    await files.chooseImage();
    await files.chooseOpen();
    expect(panels.requests.map((r) => r.directory), [
      null,
      null,
      null,
      _path('SelectedImage'),
      _path('SelectedProject'),
    ]);
  });

  test(
    'injected Documents failure changes neither memory and does not call panel',
    () async {
      final panels = _Panels();
      final memory = StudioDestinationSession();
      final failing = StudioFiles(
        openChooser: panels.choose,
        destinationSession: memory,
        documentsDirectory: () async =>
            throw const FileSystemException('Synthetic lookup failure'),
      );
      await expectLater(
        failing.chooseOpen(),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        failing.chooseImage(),
        throwsA(isA<FileSystemException>()),
      );
      expect(panels.requests, isEmpty);
      final working = panels.files(memory);
      panels.replies.addAll([null, null]);
      await working.chooseOpen();
      await working.chooseImage();
      expect(panels.requests.map((r) => r.directory), [
        _path('Documents'),
        _path('Documents'),
      ]);
    },
  );

  test('confirmed result order determines the last folder if two injected panels overlap', () async {
    final first = Completer<String?>(), second = Completer<String?>();
    final requests = <String?>[];
    var index = 0;
    final files = StudioFiles(
      documentsDirectory: () async => _path('Documents'),
      destinationSession: StudioDestinationSession(),
      openChooser:
          ({
            required String? initialDirectory,
            required List<XTypeGroup> acceptedTypeGroups,
            required String confirmButtonText,
          }) {
            requests.add(initialDirectory);
            return switch (index++) {
              0 => first.future,
              1 => second.future,
              _ => Future.value(null),
            };
          },
    );
    final a = files.chooseOpen(), b = files.chooseOpen();
    second.complete(_path('Second/b.edupaint'));
    await b;
    first.complete(_path('First/a.edupaint'));
    await a;
    await files.chooseOpen();
    expect(requests, [_path('Documents'), _path('Documents'), _path('First')]);
  });
}
