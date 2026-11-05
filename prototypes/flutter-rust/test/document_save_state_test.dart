// SPDX-License-Identifier: MIT
// The save point follows changes joined to the newest step, as the eraser
// makes all along one gesture: never clean where the drawing changed.
import 'package:edupaint_flutter_study/document_save_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('changes joined to a step keep its parent clean', () {
    final state = DocumentSaveState(undoCount: 0, initiallyClean: true);
    state.editSucceeded(undoCount: 1, redoCount: 0);
    final token = state.mutationToken;
    state.amendSucceeded(undoCount: 1, redoCount: 0);
    expect(state.isDirty, isTrue);
    expect(state.mutationToken, isNot(same(token)));
    expect(state.undoCount, 1);
    // The step undone, its parent is the drawing saved.
    state.undoSucceeded(undoCount: 0, redoCount: 1);
    expect(state.isDirty, isFalse);
    state.redoSucceeded(undoCount: 1, redoCount: 0);
    expect(state.isDirty, isTrue);
  });

  test('a save of the step before more changes joined it is not current', () {
    final state = DocumentSaveState(undoCount: 0, initiallyClean: true);
    state.editSucceeded(undoCount: 1, redoCount: 0);
    state.completeSave(state.beginSave(), path: '/dessins/a.edupaint');
    expect(state.isDirty, isFalse);
    state.amendSucceeded(undoCount: 1, redoCount: 0);
    expect(state.isDirty, isTrue);
    // Neither does a save begun before the change, when it completes after.
    final ticket = state.beginSave();
    state.amendSucceeded(undoCount: 1, redoCount: 0);
    expect(
      state.completeSave(ticket, path: '/dessins/a.edupaint'),
      SaveCompletion.earlierStateSaved,
    );
    expect(state.isDirty, isTrue);
  });

  test('nothing to join, or counts that moved, are out of sync', () {
    final empty = DocumentSaveState(undoCount: 0, initiallyClean: true);
    expect(
      () => empty.amendSucceeded(undoCount: 0, redoCount: 0),
      throwsStateError,
    );
    // Once out of sync, never assumed clean again.
    expect(empty.isDirty, isTrue);

    final withRedo = DocumentSaveState(
      undoCount: 2,
      redoCount: 1,
      initiallyClean: true,
    );
    expect(
      () => withRedo.amendSucceeded(undoCount: 2, redoCount: 1),
      throwsStateError,
    );
    expect(withRedo.isDirty, isTrue);

    final moved = DocumentSaveState(undoCount: 1, initiallyClean: true);
    expect(
      () => moved.amendSucceeded(undoCount: 2, redoCount: 0),
      throwsStateError,
    );
    expect(moved.isDirty, isTrue);
  });
}
