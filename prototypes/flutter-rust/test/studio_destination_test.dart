// SPDX-License-Identifier: MIT
// Paths are fictional; no native panel, file write or user directory is opened.
import 'dart:collection';
import 'dart:io';

import 'package:edupaint_flutter_study/studio_files.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

String _path(String suffix) =>
    '${Platform.isWindows ? r'C:\ColorTest' : '/ColorTest'}${Platform.pathSeparator}'
    '${suffix.replaceAll('/', Platform.pathSeparator)}';

class _Request {
  _Request(this.name, this.directory, this.groups, this.confirmText);
  final String name;
  final String? directory;
  final List<XTypeGroup> groups;
  final String confirmText;
}

class _Panels {
  final replies = Queue<Object?>();
  final requests = <_Request>[];
  int documentsLookups = 0;

  Future<String?> documents() async {
    documentsLookups++;
    return _path('Documents');
  }

  Future<String?> choose({
    required String suggestedName,
    required String? initialDirectory,
    required List<XTypeGroup> acceptedTypeGroups,
    required String confirmButtonText,
  }) async {
    requests.add(
      _Request(
        suggestedName,
        initialDirectory,
        acceptedTypeGroups,
        confirmButtonText,
      ),
    );
    final reply = replies.removeFirst();
    if (reply is Exception) throw reply;
    return reply as String?;
  }

  StudioFiles files([StudioDestinationSession? memory]) => StudioFiles(
    saveChooser: choose,
    documentsDirectory: documents,
    destinationSession: memory ?? StudioDestinationSession(),
  );
}

void main() {
  test(
    'unsaved PNG SVG and project panels share the last confirmed directory',
    () async {
      final panels = _Panels();
      final files = panels.files();
      panels.replies.addAll([
        _path('Exports/a.png'),
        _path('Vectors/a.svg'),
        _path('Projects/a.edupaint'),
        _path('Images/b.png'),
      ]);
      expect(await files.choosePng(), _path('Exports/a.png'));
      expect(await files.chooseExport(), _path('Vectors/a.svg'));
      expect(await files.chooseSave(), _path('Projects/a.edupaint'));
      expect(await files.choosePng(), _path('Images/b.png'));
      expect(panels.requests.map((r) => r.directory), [
        _path('Documents'),
        _path('Exports'),
        _path('Vectors'),
        _path('Projects'),
      ]);
      expect(panels.documentsLookups, 1);
      expect(panels.requests.map((r) => r.groups.single.extensions), [
        ['png'],
        ['svg'],
        ['edupaint'],
        ['png'],
      ]);
      expect(panels.requests.first.name, 'Mon dessin.png');
      expect(panels.requests[1].name, 'Mon dessin.svg');
      expect(
        panels.requests[2].name,
        Platform.isMacOS ? 'Mon dessin' : 'Mon dessin.edupaint',
      );
      expect(panels.requests[2].confirmText, 'Enregistrer le dessin');
    },
  );

  test(
    'cancelled and failed panels retain the previous explicit selection',
    () async {
      final panels = _Panels();
      final files = panels.files();
      panels.replies.addAll([
        _path('External/a.png'),
        null,
        const FileSystemException('Synthetic chooser failure'),
        null,
      ]);
      await files.choosePng();
      expect(await files.chooseSave(), isNull);
      await expectLater(
        files.chooseExport(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await files.choosePng(), isNull);
      expect(
        panels.requests.skip(1).map((r) => r.directory),
        List.filled(3, _path('External')),
      );
    },
  );

  test('current project wins on first export then PNG and SVG share its chosen export folder', () async {
    final panels = _Panels();
    final files = panels.files();
    final current = _path('ProjectOne/Mon soleil.EDUPAINT');
    panels.replies.addAll([
      _path('Unrelated/a.png'),
      _path('Album/sun.png'),
      _path('Album/sun.svg'),
      null,
    ]);
    await files.choosePng();
    await files.choosePng(currentPath: current);
    await files.chooseExport(currentPath: current);
    await files.chooseSave(currentPath: current);
    expect(panels.requests.map((r) => r.directory), [
      _path('Documents'),
      _path('ProjectOne'),
      _path('Album'),
      _path('ProjectOne'),
    ]);
    expect(panels.requests[1].name, 'Mon soleil.png');
    expect(panels.requests[2].name, 'Mon soleil.svg');
    expect(
      panels.requests[3].name,
      Platform.isMacOS ? 'Mon soleil' : 'Mon soleil.EDUPAINT',
    );
  });

  test('switching project uses its own folder and keeps only the latest export context', () async {
    final panels = _Panels();
    final files = panels.files();
    final first = _path('ProjectOne/a.edupaint');
    final second = _path('ProjectTwo/b.edupaint');
    panels.replies.addAll([
      _path('AlbumOne/a.png'),
      _path('AlbumTwo/b.svg'),
      null,
    ]);
    await files.choosePng(currentPath: first);
    await files.chooseExport(currentPath: second);
    await files.choosePng(currentPath: first);
    expect(panels.requests.map((r) => r.directory), [
      _path('ProjectOne'),
      _path('ProjectTwo'),
      _path('ProjectOne'),
    ]);
    expect(panels.documentsLookups, 0);
  });

  test('cancelling a different project export does not replace the remembered context', () async {
    final panels = _Panels();
    final files = panels.files();
    final first = _path('ProjectOne/a.edupaint');
    panels.replies.addAll([_path('Album/a.png'), null, null]);
    await files.choosePng(currentPath: first);
    await files.chooseExport(currentPath: _path('ProjectTwo/b.edupaint'));
    await files.choosePng(currentPath: first);
    expect(panels.requests.map((r) => r.directory), [
      _path('ProjectOne'),
      _path('ProjectTwo'),
      _path('Album'),
    ]);
  });

  test('lexically equivalent current paths share the export context without filesystem lookup', () async {
    final panels = _Panels();
    final files = panels.files();
    panels.replies.addAll([_path('Album/a.png'), null]);
    await files.choosePng(currentPath: _path('Projects/Unused/../a.edupaint'));
    await files.chooseExport(currentPath: _path('Projects/a.edupaint'));
    expect(panels.requests.map((r) => r.directory), [
      _path('Projects'),
      _path('Album'),
    ]);
  });

  test('session memory can be shared by replacements and isolated for another session', () async {
    final panels = _Panels();
    final memory = StudioDestinationSession();
    panels.replies.addAll([_path('External/a.png'), null, null]);
    await panels.files(memory).choosePng();
    await panels.files(memory).chooseSave();
    await panels.files().chooseSave();
    expect(panels.requests.map((r) => r.directory), [
      _path('Documents'),
      _path('External'),
      _path('Documents'),
    ]);
  });

  test(
    'unavailable Documents leaves the initial directory to the native panel',
    () async {
      final panels = _Panels();
      panels.replies.addAll([null, _path('External/a.png'), null]);
      final files = StudioFiles(
        saveChooser: panels.choose,
        documentsDirectory: () async => null,
        destinationSession: StudioDestinationSession(),
      );
      await files.choosePng();
      await files.choosePng();
      await files.chooseSave();
      expect(panels.requests.map((r) => r.directory), [
        null,
        null,
        _path('External'),
      ]);
    },
  );
}
