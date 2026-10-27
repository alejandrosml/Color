// SPDX-License-Identifier: MIT
/// A failed file operation remains the primary error even if cleanup also fails.
class FileOperationCleanupException implements Exception {
  FileOperationCleanupException(this.primaryError, List<Object> cleanupErrors)
    : cleanupErrors = List.unmodifiable(cleanupErrors);
  final Object primaryError;
  final List<Object> cleanupErrors;
  @override
  String toString() =>
      '$primaryError (nettoyage incomplet : ${cleanupErrors.join("; ")})';
}
