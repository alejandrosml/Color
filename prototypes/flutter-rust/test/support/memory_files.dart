// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:edupaint_flutter_study/project_storage.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/document_exports.dart';
import 'package:edupaint_flutter_study/studio_files.dart';

class MemoryRecovery extends ProjectStorage {
  MemoryRecovery([this.bytes])
    : super(recoveryDirectory: Directory('unused-in-memory-test'));
  Uint8List? bytes;
  int writes = 0;
  @override
  Future<Uint8List?> readRecovery() async =>
      bytes == null ? null : Uint8List.fromList(bytes!);
  @override
  Future<PreparedProject?> readPreparedRecovery() async {
    // Keep virtual dispatch through readRecovery for existing failure hooks.
    final captured = await readRecovery();
    return captured == null ? null : RustDocument.loadProjectBytes(captured);
  }

  @override
  Future<void> writeRecovery(Uint8List value) async {
    writes++;
    bytes = Uint8List.fromList(value);
  }

  @override
  Future<bool> writeRecoveryDocument(
    RustDocument document, {
    required bool Function() shouldCommit,
  }) async {
    if (!shouldCommit()) return false;
    final snapshot = await prepareProjectBytes(document);
    if (!shouldCommit()) return false;
    // Preserve existing slow-write test hooks. Real two-phase filesystem tests
    // exercise the production store separately; this class is only a UI fake.
    await writeRecovery(snapshot);
    return true;
  }

  @override
  Future<void> clearRecovery() async {
    bytes = null;
  }
}

class MemoryFiles extends StudioFiles {
  final Map<String, Uint8List> projects = {};
  String? openPath;
  String? savePath = '/drawings/Mon dessin.edupaint';
  String? svg;
  String? exportSourcePath;
  String? pngSourcePath;
  Uint8List? png;
  String? pngPath = '/drawings/export.png';
  bool failWrite = false;
  int saveDialogCount = 0;
  @override
  Future<String?> chooseOpen() async => openPath;
  @override
  Future<String?> chooseSave({String? currentPath}) async {
    saveDialogCount++;
    return savePath;
  }

  @override
  Future<String?> chooseExport({String? currentPath}) async {
    exportSourcePath = currentPath;
    return '/drawings/export.svg';
  }

  @override
  Future<String?> choosePng({String? currentPath}) async {
    pngSourcePath = currentPath;
    return pngPath;
  }

  @override
  Future<void> writePng(String path, Uint8List bytes) async {
    if (failWrite) throw const FileSystemException('Simulated denied write');
    png = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List> read(String path) async =>
      Uint8List.fromList(projects[path]!);
  @override
  Future<PreparedProject> readPrepared(String path) async =>
      RustDocument.loadProjectBytes(await read(path));
  @override
  Future<void> write(String path, Uint8List bytes) async {
    if (failWrite) throw const FileSystemException('Simulated denied write');
    projects[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeSvgBytes(String path, Uint8List bytes) async {
    if (failWrite) throw const FileSystemException('Simulated denied write');
    svg = utf8.decode(bytes);
  }
}
