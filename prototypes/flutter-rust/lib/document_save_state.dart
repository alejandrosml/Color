// SPDX-License-Identifier: MIT

/// A position on the current undo/redo branch. A cut invalidates it forever.
/// Only the saved point and at most one active save ticket retain such a mark.
final class _HistoryMark {
  _HistoryMark(this.depth);
  final int depth;
  bool reachable = true;
}

final class SaveTicket {
  SaveTicket._(this._owner, this._mark);
  final Object _owner;
  final _HistoryMark _mark;
}

enum SaveCompletion { currentSaved, earlierStateSaved, ignoredStale }

/// Constant-space save-point tracking for the current, non-pruning Rust history.
///
/// Call edit/undo/redo only AFTER a successful native operation, with its actual
/// undo and redo counts. A no-op or error must not advance this state. One native
/// operation corresponds to one history step; a new edit discards all redo.
/// Documents/backgrounds cannot be replaced without retiring this instance.
///
/// This identifies history positions, not arbitrary equal pixels/serialization.
/// Independently drawing an equal result remains conservatively dirty.
final class DocumentSaveState {
  DocumentSaveState({
    required int undoCount,
    int redoCount = 0,
    required bool initiallyClean,
    String? path,
  }) : _cursor = undoCount,
       _length = undoCount + redoCount,
       _path = path {
    _validateCounts(undoCount, redoCount);
    if (path != null && path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path');
    }
    if (initiallyClean) _saved = _HistoryMark(_cursor);
  }

  static const maxHistorySteps = 50000;
  final Object _owner = Object();
  int _cursor;
  int _length;
  String? _path;
  _HistoryMark? _saved;
  SaveTicket? _pending;
  Object _mutation = Object();
  bool _retired = false;
  bool _reliable = true;

  bool get isAlive => !_retired;
  bool get isDirty {
    _checkAlive();
    return !_reliable ||
        _saved == null ||
        !_saved!.reachable ||
        _saved!.depth != _cursor;
  }

  int get undoCount {
    _checkAlive();
    return _cursor;
  }

  int get redoCount {
    _checkAlive();
    return _length - _cursor;
  }

  String? get path {
    _checkAlive();
    return _path;
  }

  bool get saveInProgress {
    _checkAlive();
    return _pending != null;
  }

  /// Changed by every committed mutation, even when undo returns to a clean
  /// position. Keep this separate from dirty for asynchronous stale-work guards.
  Object get mutationToken {
    _checkAlive();
    return _mutation;
  }

  void _checkAlive() {
    if (_retired) throw StateError('The document session is retired.');
  }

  static void _validateCounts(int undo, int redo) {
    if (undo < 0 ||
        redo < 0 ||
        undo > maxHistorySteps ||
        redo > maxHistorySteps - undo) {
      throw ArgumentError('History counts exceed the native contract.');
    }
  }

  void _expectCounts(int undo, int redo, int expectedUndo, int expectedRedo) {
    _checkAlive();
    if (!_reliable) throw StateError('History must be resynchronized first.');
    try {
      _validateCounts(undo, redo);
      if (undo != expectedUndo || redo != expectedRedo) {
        throw StateError(
          'History tracking is out of sync; do not assume clean.',
        );
      }
    } catch (_) {
      _reliable =
          false; // Fail closed: never call an unknown current state clean.
      rethrow;
    }
  }

  void unchanged({required int undoCount, required int redoCount}) {
    _expectCounts(undoCount, redoCount, _cursor, _length - _cursor);
  }

  void editSucceeded({required int undoCount, required int redoCount}) {
    _expectCounts(undoCount, redoCount, _cursor + 1, 0);
    // A mark exactly AT the branch point survives: its state is the parent of
    // the new edit. Only strictly later states are discarded.
    final saved = _saved;
    final pending = _pending?._mark;
    if (saved != null && saved.depth > _cursor) saved.reachable = false;
    if (pending != null && pending.depth > _cursor) pending.reachable = false;
    _cursor++;
    _length = _cursor;
    _mutation = Object();
  }

  void undoSucceeded({required int undoCount, required int redoCount}) {
    _expectCounts(undoCount, redoCount, _cursor - 1, _length - _cursor + 1);
    _cursor--;
    _mutation = Object();
  }

  void redoSucceeded({required int undoCount, required int redoCount}) {
    _expectCounts(undoCount, redoCount, _cursor + 1, _length - _cursor - 1);
    _cursor++;
    _mutation = Object();
  }

  /// Capture immediately beside export snapshot creation, before the first
  /// await. The file-writing operation must be serialized (as by UI busy state).
  SaveTicket beginSave() {
    _checkAlive();
    if (!_reliable) {
      throw StateError('History must be resynchronized before saving.');
    }
    if (_pending != null) throw StateError('A project save is already active.');
    return _pending = SaveTicket._(_owner, _HistoryMark(_cursor));
  }

  bool _accepts(SaveTicket ticket) =>
      !_retired &&
      identical(ticket._owner, _owner) &&
      identical(ticket, _pending);

  /// Only call after the atomic project writer reports success. A successful
  /// write changes the disk baseline even if edits happened while awaiting it.
  /// Adopt its path and captured mark; never mark the newer current state clean.
  /// A lost redo branch remains dirty even if another state has the same depth.
  SaveCompletion completeSave(SaveTicket ticket, {required String path}) {
    if (!_accepts(ticket)) return SaveCompletion.ignoredStale;
    if (path.trim().isEmpty) throw ArgumentError.value(path, 'path');
    _saved = ticket._mark;
    _path = path;
    _pending = null;
    return isDirty
        ? SaveCompletion.earlierStateSaved
        : SaveCompletion.currentSaved;
  }

  /// Cancellation or failed serialization/write preserves the earlier baseline.
  void cancelSave(SaveTicket ticket) {
    if (_accepts(ticket)) _pending = null;
  }

  /// Retire before replacing/disposing its document. Await recovery drain before
  /// adopting a replacement which shares the same on-disk recovery slot.
  void retire() {
    _retired = true;
    _pending = null;
    _saved = null;
  }
}
