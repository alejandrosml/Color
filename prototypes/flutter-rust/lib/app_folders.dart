// SPDX-License-Identifier: MIT
// The folders of the system where Color keeps its files: its own folder, the
// documents of the device, and one for files that may go (P-01 of the
// retrospective of October 2026). path_provider found them before, and
// brought with it code in C (jni, compiled for Android, Linux and Windows)
// and in Objective-C (objective_c, on the iPhone, the iPad and the Mac),
// built into Color for three paths. They are now asked of the program that
// carries Color, which finds
// them exactly as path_provider did — in Swift on the iPhone, the iPad and
// the Mac, in Kotlin on Android —; on Linux and Windows, of the readers of
// path_provider for those systems, written in Dart, which the registrant of
// the plugins sets.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// The channel of the folders, answered by the program that carries Color.
const foldersChannel = MethodChannel('org.edupaint/folders');

/// The system gave no such folder.
class MissingFolderException implements Exception {
  const MissingFolderException(this.folder);

  /// Which one: `support`, `documents` or `temporary`.
  final String folder;

  @override
  String toString() => 'MissingFolderException: no $folder folder';
}

/// Whether the program that carries Color is asked, rather than the readers
/// of Linux and Windows.
bool get _askedOfHost =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

Future<String> _folder(
  String name,
  Future<String?> Function(PathProviderPlatform reader) read,
) async {
  final path = _askedOfHost
      ? await foldersChannel.invokeMethod<String>(name)
      : await read(PathProviderPlatform.instance);
  if (path == null || path.isEmpty) throw MissingFolderException(name);
  return path;
}

/// Color's own folder, made when it is missing: Application Support on the
/// iPhone and the iPad, with the identifier of Color after it on the Mac;
/// the files of the application on Android; on Linux and Windows, where
/// path_provider has it.
Future<Directory> applicationSupportFolder() async {
  final directory = Directory(
    await _folder('support', (reader) => reader.getApplicationSupportPath()),
  );
  // As path_provider did on the Apple systems; elsewhere it is there.
  await directory.create(recursive: true);
  return directory;
}

/// The documents: Documents on the Apple systems, the folder `app_flutter`
/// of the application on Android.
Future<Directory> applicationDocumentsFolder() async => Directory(
  await _folder('documents', (reader) => reader.getApplicationDocumentsPath()),
);

/// A folder for files that the system may take away: the caches of the
/// Apple systems, with the identifier of Color after them on the Mac; the
/// cache of the application on Android.
Future<Directory> temporaryFolder() async => Directory(
  await _folder('temporary', (reader) => reader.getTemporaryPath()),
);
