// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

Future<Uint8List> readBoundedBytes(
  String path, {
  required int maximumBytes,
  required String tooLargeMessage,
}) async {
  if (maximumBytes < 1) throw ArgumentError.value(maximumBytes);
  final handle = await File(path).open();
  try {
    final initialLength = await handle.length();
    if (initialLength > maximumBytes) {
      throw FormatException(tooLargeMessage);
    }
    // A single BytesBuilder chunk can be returned without concatenation.
    if (initialLength <= 64 * 1024) {
      final builder = BytesBuilder(copy: false);
      while (builder.length <= maximumBytes) {
        final remaining = maximumBytes + 1 - builder.length;
        final chunk = await handle.read(min(64 * 1024, remaining));
        if (chunk.isEmpty) return builder.takeBytes();
        builder.add(chunk);
      }
      throw FormatException(tooLargeMessage);
    }

    // Allocation/zero-initialization is synchronous on the calling isolate.
    final initial = Uint8List(initialLength);
    var used = 0;
    while (used < initial.length) {
      final count = await handle.readInto(
        initial,
        used,
        min(initial.length, used + 64 * 1024),
      );
      if (count == 0) {
        // A truncated file must not keep a large unused backing buffer alive.
        return Uint8List.fromList(Uint8List.sublistView(initial, 0, used));
      }
      used += count;
    }

    // Reaching the original size is not EOF: the file may have grown.
    final probe = Uint8List(1);
    if (await handle.readInto(probe) == 0) return initial;
    if (initial.length == maximumBytes) {
      throw FormatException(tooLargeMessage);
    }

    // Growth is exceptional. Keep the original payload, then bounded blocks;
    // unlike geometric resizing, this does not repeatedly copy the prefix.
    final grown = BytesBuilder(copy: false);
    if (initial.isNotEmpty) grown.add(initial);
    grown.add(probe);
    while (grown.length <= maximumBytes) {
      final remaining = maximumBytes + 1 - grown.length;
      final chunk = Uint8List(min(64 * 1024, remaining));
      var chunkUsed = 0;
      // Fill short reads into the same block. One-byte reads cannot retain
      // one 64 KiB allocation per byte in the builder.
      while (chunkUsed < chunk.length) {
        final count = await handle.readInto(chunk, chunkUsed, chunk.length);
        if (count == 0) {
          if (chunkUsed > 0) {
            grown.add(
              Uint8List.fromList(Uint8List.sublistView(chunk, 0, chunkUsed)),
            );
          }
          return grown.takeBytes();
        }
        chunkUsed += count;
      }
      grown.add(chunk);
    }
    throw FormatException(tooLargeMessage);
  } finally {
    await handle.close();
  }
}
