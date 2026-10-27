// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A bounded presentation value; never retains the originating exception.
class StudioProblem {
  StudioProblem._(this.message, this.details, this.detailsTruncated);

  factory StudioProblem.fromError(Object error, {required String message}) {
    String raw;
    try {
      raw = error.toString();
    } catch (_) {
      raw = 'Le diagnostic de ce problème n’est pas disponible.';
    }
    final truncated = raw.length > detailsLimit;
    var end = truncated ? detailsLimit : raw.length;
    if (truncated && (raw.codeUnitAt(end - 1) & 0xfc00) == 0xd800) {
      end--;
    }
    return StudioProblem._(
      message,
      truncated ? raw.substring(0, end) : raw,
      truncated,
    );
  }

  factory StudioProblem.notice(String message) =>
      StudioProblem._(message, null, false);

  static const detailsLimit = 8192;
  final String message;
  final String? details;
  final bool detailsTruncated;
}

class StudioProblemDialog extends StatelessWidget {
  const StudioProblemDialog({super.key, required this.problem});

  final StudioProblem problem;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
    },
    child: Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            Navigator.of(context).pop();
            return null;
          },
        ),
      },
      child: AlertDialog(
        key: const Key('problemDetailsDialog'),
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('Détails du problème'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(problem.message),
              const SizedBox(height: 16),
              const Text(
                'Ces informations peuvent aider à comprendre le problème.',
              ),
              if (problem.detailsTruncated) ...[
                const SizedBox(height: 12),
                const Text(
                  'Le diagnostic est très long : seul son début est affiché.',
                  key: Key('problemDetailsTruncated'),
                ),
              ],
              const SizedBox(height: 12),
              SelectableText(
                problem.details ?? '',
                key: const Key('problemDetailsText'),
                style: const TextStyle(fontSize: 13),
                // Selection is available; no copy action is added to the app.
                contextMenuBuilder: (_, _) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            key: const Key('closeProblemDetails'),
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer les détails'),
          ),
        ],
      ),
    ),
  );
}

class StudioStartupProblem extends StatelessWidget {
  const StudioStartupProblem({super.key, required this.onDetails});

  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 504),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.draw_outlined, size: 42),
                const SizedBox(height: 20),
                const Text(
                  'Color n’a pas pu démarrer.',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tu peux consulter les détails pour demander de l’aide.',
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  key: const Key('startupProblemDetails'),
                  onPressed: onDetails,
                  child: const Text('Détails'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
