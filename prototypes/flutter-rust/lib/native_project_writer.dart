// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/services.dart';

import 'project_storage.dart';

const _filesChannel = MethodChannel('org.edupaint/files');

/// Atomically writes bytes to a user-selected file, for projects and exports.
/// Project-format validation and limits are the caller's responsibility.
Future<void> writeNativeProject(String path, Uint8List bytes) async {
  if (Platform.isMacOS) {
    // Foundation handles safe saves using the selected file's sandbox access.
    // The parent directory need not be writable by arbitrary Dart file I/O.
    // This channel's StandardMethodCodec copies the bytes into its message
    // synchronously, before invokeMethod first awaits the native response.
    // A caller may mutate its buffer after this call returns its Future.
    await _filesChannel.invokeMethod<void>('writeAtomic', {
      'path': path,
      'bytes': bytes,
    });
  } else {
    await ProjectStorage.writeAtomicBytes(path, bytes);
  }
}
