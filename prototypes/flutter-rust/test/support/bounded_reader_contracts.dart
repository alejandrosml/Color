// SPDX-License-Identifier: MIT
// Shared deterministic contract cases; no native library or test-package dependency.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

typedef BoundedReader = Future<Uint8List> Function(
  String path, {
  required int maximumBytes,
  required String tooLargeMessage,
});

class BoundedReadCase {
  const BoundedReadCase(
    this.name, {
    required this.initial,
    required this.visible,
    required this.maximum,
    required this.expected,
    this.growthAt,
    this.growTo,
    this.shortRead,
    this.failLength = false,
    this.failReadAt,
    this.expectedError,
  });
  final String name;
  final int initial, visible, maximum, expected;
  final int? growthAt, growTo, shortRead, failReadAt;
  final bool failLength;
  final Type? expectedError;
}

class _ScriptedFile implements File {
  _ScriptedFile(this.handle);
  final _ScriptedHandle handle;
  int opens = 0;
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    opens++;
    return handle;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedHandle implements RandomAccessFile {
  _ScriptedHandle(this.scenario);
  final BoundedReadCase scenario;
  int positionBytes = 0, closes = 0, reads = 0;
  int lengthCalls = 0, readIntoCalls = 0;
  Uint8List? firstReadResult;
  @override
  Future<int> length() async {
    lengthCalls++;
    if (scenario.failLength) throw const FileSystemException('length failure');
    return scenario.initial;
  }

  int _count(int requested) {
    reads++;
    if (requested <= 0 || requested > scenario.maximum + 1 - positionBytes) {
      throw StateError('Read request exceeds remaining maximum+1 budget.');
    }
    if (scenario.failReadAt != null && positionBytes >= scenario.failReadAt!) {
      throw const FileSystemException('read failure');
    }
    var visible = scenario.visible;
    if (scenario.growthAt != null && positionBytes >= scenario.growthAt!) {
      visible = scenario.growTo!;
    }
    return min(
      min(requested, max(0, visible - positionBytes)),
      scenario.shortRead ?? requested,
    );
  }

  int _byte(int offset) => (offset * 37 + 17) & 255;
  @override
  Future<Uint8List> read(int count) async {
    final n = _count(count);
    final result = Uint8List.fromList(
      List.generate(n, (i) => _byte(positionBytes + i)),
    );
    firstReadResult ??= result;
    positionBytes += n;
    return result;
  }

  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) async {
    readIntoCalls++;
    final finish = end ?? buffer.length;
    final count = _count(finish - start);
    for (var i = 0; i < count; i++) {
      buffer[start + i] = _byte(positionBytes + i);
    }
    positionBytes += count;
    return count;
  }

  @override
  Future<void> close() async {
    closes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const boundedReadCases = [
  BoundedReadCase('empty', initial: 0, visible: 0, maximum: 10, expected: 0),
  BoundedReadCase(
    'small stable',
    initial: 9,
    visible: 9,
    maximum: 10,
    expected: 9,
  ),
  BoundedReadCase(
    'one full block',
    initial: 65536,
    visible: 65536,
    maximum: 70000,
    expected: 65536,
  ),
  BoundedReadCase(
    'several blocks',
    initial: 140003,
    visible: 140003,
    maximum: 150000,
    expected: 140003,
  ),
  BoundedReadCase(
    'exact limit',
    initial: 10,
    visible: 10,
    maximum: 10,
    expected: 10,
  ),
  BoundedReadCase(
    'oversized initial length',
    initial: 11,
    visible: 3,
    maximum: 10,
    expected: 0,
    expectedError: FormatException,
  ),
  BoundedReadCase(
    'grows within limit',
    initial: 4,
    visible: 4,
    growthAt: 4,
    growTo: 9,
    maximum: 10,
    expected: 9,
  ),
  BoundedReadCase(
    'grows across several blocks',
    initial: 65535,
    visible: 65535,
    growthAt: 65535,
    growTo: 140003,
    maximum: 150000,
    expected: 140003,
  ),
  BoundedReadCase(
    'grows over limit',
    initial: 4,
    visible: 4,
    growthAt: 4,
    growTo: 20,
    maximum: 10,
    expected: 0,
    expectedError: FormatException,
  ),
  BoundedReadCase(
    'zero reported size then content',
    initial: 0,
    visible: 9,
    maximum: 10,
    expected: 9,
  ),
  BoundedReadCase(
    'shrinks to zero',
    initial: 10,
    visible: 0,
    maximum: 10,
    expected: 0,
  ),
  BoundedReadCase(
    'shrinks after length',
    initial: 10,
    visible: 3,
    maximum: 10,
    expected: 3,
  ),
  BoundedReadCase(
    'partial one-byte reads',
    initial: 4,
    visible: 4,
    growthAt: 4,
    growTo: 9,
    maximum: 10,
    expected: 9,
    shortRead: 1,
  ),
  BoundedReadCase(
    'partial growth beyond limit',
    initial: 4,
    visible: 4,
    growthAt: 4,
    growTo: 30,
    maximum: 10,
    expected: 0,
    shortRead: 1,
    expectedError: FormatException,
  ),
  BoundedReadCase(
    'length error closes',
    initial: 4,
    visible: 4,
    maximum: 10,
    expected: 0,
    failLength: true,
    expectedError: FileSystemException,
  ),
  BoundedReadCase(
    'read error closes',
    initial: 10,
    visible: 10,
    maximum: 10,
    expected: 0,
    shortRead: 2,
    failReadAt: 4,
    expectedError: FileSystemException,
  ),
  BoundedReadCase(
    'probe error closes',
    initial: 4,
    visible: 4,
    maximum: 10,
    expected: 0,
    failReadAt: 4,
    expectedError: FileSystemException,
  ),
  BoundedReadCase(
    'growth read error closes',
    initial: 4,
    visible: 4,
    growthAt: 4,
    growTo: 9,
    maximum: 10,
    expected: 0,
    shortRead: 1,
    failReadAt: 5,
    expectedError: FileSystemException,
  ),
  BoundedReadCase(
    'invalid maximum never opens',
    initial: 0,
    visible: 0,
    maximum: 0,
    expected: 0,
    expectedError: ArgumentError,
  ),
  BoundedReadCase(
    'threshold minus one exact cap',
    initial: 65535,
    visible: 65535,
    maximum: 65535,
    expected: 65535,
  ),
  BoundedReadCase(
    'threshold exact cap',
    initial: 65536,
    visible: 65536,
    maximum: 65536,
    expected: 65536,
  ),
  BoundedReadCase(
    'threshold plus one exact cap',
    initial: 65537,
    visible: 65537,
    maximum: 65537,
    expected: 65537,
  ),
  BoundedReadCase(
    'threshold oversized refused before reads',
    initial: 65537,
    visible: 3,
    maximum: 65536,
    expected: 0,
    expectedError: FormatException,
  ),
  BoundedReadCase(
    'small grows past threshold',
    initial: 4,
    visible: 4,
    growthAt: 4,
    growTo: 65538,
    maximum: 70000,
    expected: 65538,
  ),
  BoundedReadCase(
    'small grows past threshold and cap',
    initial: 4,
    visible: 4,
    growthAt: 4,
    growTo: 70001,
    maximum: 70000,
    expected: 0,
    expectedError: FormatException,
  ),
  BoundedReadCase(
    'large grows several blocks',
    initial: 65537,
    visible: 65537,
    growthAt: 65537,
    growTo: 140003,
    maximum: 150000,
    expected: 140003,
  ),
  BoundedReadCase(
    'large grows past cap',
    initial: 65537,
    visible: 65537,
    growthAt: 65537,
    growTo: 65541,
    maximum: 65540,
    expected: 0,
    expectedError: FormatException,
  ),
  BoundedReadCase(
    'large shrinks to zero',
    initial: 65537,
    visible: 0,
    maximum: 70000,
    expected: 0,
  ),
  BoundedReadCase(
    'large shrinks below threshold',
    initial: 65537,
    visible: 3,
    maximum: 70000,
    expected: 3,
  ),
  BoundedReadCase(
    'large shrinks at threshold',
    initial: 65537,
    visible: 65536,
    maximum: 70000,
    expected: 65536,
  ),
  BoundedReadCase(
    'large partial reads',
    initial: 65537,
    visible: 65537,
    maximum: 70000,
    expected: 65537,
    shortRead: 32768,
  ),
  BoundedReadCase(
    'large initial read error closes',
    initial: 65537,
    visible: 65537,
    maximum: 70000,
    expected: 0,
    shortRead: 32768,
    failReadAt: 32768,
    expectedError: FileSystemException,
  ),
  BoundedReadCase(
    'large probe error closes',
    initial: 65537,
    visible: 65537,
    maximum: 70000,
    expected: 0,
    failReadAt: 65537,
    expectedError: FileSystemException,
  ),
  BoundedReadCase(
    'large growth read error closes',
    initial: 65537,
    visible: 65537,
    growthAt: 65537,
    growTo: 70000,
    maximum: 70000,
    expected: 0,
    shortRead: 32768,
    failReadAt: 65538,
    expectedError: FileSystemException,
  ),
];

Future<void> runBoundedReadCase(
  BoundedReader reader,
  BoundedReadCase test,
) async {
  final handle = _ScriptedHandle(test);
  final file = _ScriptedFile(handle);
  Object? error;
  Uint8List? result;
  await IOOverrides.runZoned(() async {
    try {
      result = await reader(
        'scenario',
        maximumBytes: test.maximum,
        tooLargeMessage: 'limit',
      );
    } catch (caught) {
      error = caught;
    }
  }, createFile: (_) => file);
  void require(bool value, String message) {
    if (!value) throw StateError('${test.name}: $message');
  }

  require(error?.runtimeType == test.expectedError, 'unexpected error $error');
  require(file.opens == (test.maximum < 1 ? 0 : 1), 'one open');
  require(handle.lengthCalls == file.opens, 'one length query');
  require(handle.closes == file.opens, 'close exactly once');
  require(handle.positionBytes <= max(0, test.maximum + 1), 'maximum+1 budget');
  if (test.expectedError == null) {
    final bytes = result!;
    require(bytes.length == test.expected, 'wrong length');
    require(
      bytes.buffer.lengthInBytes == bytes.length,
      'unused backing retained',
    );
    for (var i = 0; i < bytes.length; i++) {
      require(bytes[i] == ((i * 37 + 17) & 255), 'wrong byte $i');
    }
    // Preserve the actual no-copy return contract of a single complete block.
    if (test.initial > 0 &&
        test.initial <= 65536 &&
        test.visible == test.initial &&
        test.growthAt == null &&
        test.shortRead == null) {
      require(
        identical(bytes, handle.firstReadResult),
        'single full block was copied',
      );
      require(handle.readIntoCalls == 0, 'small path changed its I/O strategy');
    }
  }
  if (test.initial > test.maximum && test.maximum > 0) {
    require(handle.reads == 0, 'oversized initial source was read');
  }
}
