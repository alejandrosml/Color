// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'rust_document.dart' show maxProjectBytes, RustDocument, PreparedProject;
import 'bounded_project_reader.dart' as bounded;
import 'file_operation_cleanup_exception.dart';
import 'recovery_location.dart';

final class _PreparedRecovery {
  const _PreparedRecovery(this.owner, this.nonce, this.path, this.byteLength);
  final Object owner;
  final String nonce;
  final String path;
  final int byteLength;
}

/// Bounded project I/O and a single, private recovery slot.
///
/// Keep one instance per recovery directory. Operations are ordered within this
/// instance, including reads and clears. This is not a cross-process lock.
/// Project bytes are opaque here; Rust validates their contents when opening.
class ProjectStorage {
  ProjectStorage({required this.recoveryDirectory});

  final Directory recoveryDirectory;
  Future<void> _pending = Future<void>.value();
  final Object _ticketOwner = Object();
  bool _documentRecoveryPending = false;
  _PreparedRecovery? _ownedPreparedRecovery;

  File get _recoveryFile => File(
    '${recoveryDirectory.path}${Platform.pathSeparator}recovery.edupaint',
  );

  /// Whether [path] names a file placed directly in the recovery folder.
  /// What is kept there is cleared when a drawing is saved or abandoned:
  /// the studio never takes such a path as the file of a project.
  bool owns(String path) => isPlacedIn(
    File(path).absolute.path,
    recoveryDirectory.absolute.path,
    separator: Platform.pathSeparator,
    caseSensitive: !Platform.isMacOS && !Platform.isWindows,
  );

  /// Returns null only when no recovery file exists; other errors propagate.
  Future<Uint8List?> readRecovery() => _enqueue(() async {
    try {
      return await readProject(_recoveryFile.path);
    } on FileSystemException catch (error) {
      if (_isMissing(error)) return null;
      rethrow;
    }
  });

  /// The whole read/prepare stays in the existing queue. No clear or write can
  /// overtake it; only a missing recovery file means absence.
  Future<PreparedProject?> readPreparedRecovery() => _enqueue(() async {
    try {
      return await RustDocument.loadProjectFile(_recoveryFile.path);
    } on FileSystemException catch (error) {
      if (_isMissing(error)) return null;
      rethrow;
    }
  });

  /// Captures the supplied bytes now, before waiting for earlier operations.
  Future<void> writeRecovery(Uint8List bytes) {
    final snapshot = _snapshot(bytes);
    return _enqueue(() async {
      await recoveryDirectory.create(recursive: true);
      await _writeAtomically(_recoveryFile.path, snapshot);
    });
  }

  /// One bounded prepare/commit/abandon operation in the existing I/O queue.
  /// Capture occurs at the queue head, not at invocation. The synchronous,
  /// side-effect-free guard must check document/store identity, generation and
  /// dirty state. False means abandoned without publication; errors propagate.
  /// A successful rename remains committed even if the guard changes afterwards;
  /// a queued clear then runs after it. This is still a single-process instance.
  Future<bool> writeRecoveryDocument(
    RustDocument document, {
    required bool Function() shouldCommit,
  }) {
    if (_documentRecoveryPending) {
      throw StateError('Une préparation de récupération est déjà en cours.');
    }
    _documentRecoveryPending = true;
    final result = _enqueue(
      () => _writeRecoveryDocument(document, shouldCommit),
    );
    return result.whenComplete(() => _documentRecoveryPending = false);
  }

  String _temporaryPath(String nonce) =>
      '${recoveryDirectory.absolute.path}${Platform.pathSeparator}.edupaint-$nonce.tmp';

  Future<bool> _writeRecoveryDocument(
    RustDocument document,
    bool Function() shouldCommit,
  ) async {
    // A queued document may already have been disposed: do not touch it first.
    if (!shouldCommit()) return false;
    final random = Random.secure();
    final nonce = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final path = _temporaryPath(nonce);
    _PreparedRecovery? ticket;
    Object? failure;
    StackTrace? failureStack;
    var committed = false;
    try {
      // Native capture is synchronous at this call, before its first await.
      // A failed preparation owns its own cleanup. Never infer ownership merely
      // from the path: exclusive creation might have collided with another file.
      final size = await document.prepareProjectFile(path);
      ticket = _PreparedRecovery(_ticketOwner, nonce, path, size);
      _ownedPreparedRecovery = ticket;
      if (size < 36 || size > maxProjectBytes) {
        throw StateError('Taille de récupération préparée invalide.');
      }
      if (shouldCommit()) {
        await _checkDestination(_recoveryFile.path);
        // Last await before the commit decision. No await separates this guard
        // from starting rename; clear/read remain behind this whole operation.
        if (shouldCommit()) {
          _checkOwnedTicket(ticket);
          await File(ticket.path).rename(_recoveryFile.path);
          _ownedPreparedRecovery = null;
          ticket = null;
          committed = true;
        }
      }
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    } finally {
      if (ticket != null) {
        try {
          await _abandonRecovery(ticket);
        } catch (error, stack) {
          if (failure == null) {
            failure = error;
            failureStack = stack;
          } else {
            failure = FileOperationCleanupException(failure, [error]);
          }
        }
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    return committed;
  }

  void _checkOwnedTicket(_PreparedRecovery ticket) {
    if (!identical(ticket.owner, _ticketOwner) ||
        !identical(ticket, _ownedPreparedRecovery) ||
        ticket.path != _temporaryPath(ticket.nonce)) {
      throw StateError('Ticket de récupération étranger ou déjà consommé.');
    }
  }

  Future<void> _abandonRecovery(_PreparedRecovery ticket) async {
    _checkOwnedTicket(ticket);
    try {
      await File(ticket.path).delete();
    } finally {
      // A cleanup failure leaves an orphan, never an implicit second deletion.
      _ownedPreparedRecovery = null;
    }
  }

  /// Cannot be overtaken by a previously requested write on this instance.
  Future<void> clearRecovery() => _enqueue(() async {
    try {
      await _recoveryFile.delete();
    } on FileSystemException catch (error) {
      if (!_isMissing(error)) rethrow;
    }
  });

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    // An operation reports its own error, without poisoning later operations.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Reads at most the format limit plus one byte, including if a file grows.
  static Future<Uint8List> readProject(String path) => readBoundedBytes(
    path,
    maximumBytes: maxProjectBytes,
    tooLargeMessage: 'Le projet dépasse la taille autorisée.',
  );

  /// Shared bounded reader for self-contained projects and source images.
  /// Checks both the initial file length and bytes actually read as it grows.
  static Future<Uint8List> readBoundedBytes(
    String path, {
    required int maximumBytes,
    required String tooLargeMessage,
  }) => bounded.readBoundedBytes(
    path,
    maximumBytes: maximumBytes,
    tooLargeMessage: tooLargeMessage,
  );

  /// Flushes a temporary file on the same filesystem, then replaces the target.
  ///
  /// Requires write access to the destination directory. macOS user-selected
  /// file access alone may not provide this; use the native document writer
  /// for external sandboxed files. There is no delete-then-copy fallback and
  /// no claim of power-loss durability (the parent directory is not fsynced).
  static Future<void> writeProject(String path, Uint8List bytes) =>
      _writeAtomically(path, _snapshot(bytes));

  /// Same replacement protocol for exports whose format has a different limit.
  /// The caller is responsible for bounding these already-produced bytes.
  static Future<void> writeAtomicBytes(String path, Uint8List bytes) =>
      _writeAtomically(path, Uint8List.fromList(bytes));

  static Uint8List _snapshot(Uint8List bytes) {
    if (bytes.length > maxProjectBytes) {
      throw const FormatException('Le projet dépasse la taille autorisée.');
    }
    return Uint8List.fromList(bytes);
  }

  static Future<void> _writeAtomically(String path, Uint8List bytes) async {
    final target = File(path).absolute;
    await _checkDestination(target.path);
    final random = Random.secure();
    final token = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temporary = File(
      '${target.parent.path}${Platform.pathSeparator}.edupaint-$token.tmp',
    );
    // Exclusive creation prevents overwriting an existing temporary file.
    await temporary.create(exclusive: true);
    var replaced = false;
    try {
      final handle = await temporary.open(mode: FileMode.writeOnly);
      try {
        await handle.writeFrom(bytes);
        await handle.flush();
      } finally {
        await handle.close();
      }
      await _checkDestination(target.path);
      await temporary.rename(target.path);
      replaced = true;
    } finally {
      if (!replaced) {
        try {
          await temporary.delete();
        } on FileSystemException {
          // Preserve the original write/rename error. Never delete the target.
        }
      }
    }
  }

  static Future<void> _checkDestination(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException(
        'La destination doit être un fichier ordinaire, sans lien symbolique.',
        path,
      );
    }
  }

  static bool _isMissing(FileSystemException error) {
    final code = error.osError?.errorCode;
    return code == 2 || (Platform.isWindows && code == 3);
  }
}
