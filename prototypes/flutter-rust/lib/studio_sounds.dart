// SPDX-License-Identifier: MIT
// The small sounds of the studio. They are made by the Rust core, which also
// plays them where it has a player of its own (Windows, Linux); elsewhere
// the runner of the system plays the WAV bytes it is handed (macOS, in
// Swift). A sound is never worth an error: whatever fails here is silence.
import 'package:flutter/services.dart';

import 'rust_document.dart';

/// The sounds of the core, by their identifiers: positions in its catalogue,
/// which only ever grows.
enum StudioSound {
  tool(0, 'outil'),
  colour(1, 'couleur'),
  stroke(2, 'trait'),
  shape(3, 'forme'),
  stamp(4, 'tampon'),
  fill(5, 'pot'),
  erase(6, 'gomme'),
  undo(7, 'annuler'),
  redo(8, 'retablir'),
  sheet(9, 'feuille'),
  saved(10, 'enregistre'),
  notice(11, 'oups'),
  film(12, 'film'),
  bravo(13, 'bravo'),
  click(14, 'clic'),
  text(15, 'texte'),
  select(16, 'choisir'),
  printed(17, 'imprime');

  const StudioSound(this.id, this.key);
  final int id;

  /// The name the core gives it: a test compares the two lists.
  final String key;
}

/// What plays the sounds of the studio.
abstract interface class SoundPlayer {
  /// Starts [sound] and returns at once; never throws.
  void play(StudioSound sound);
}

/// The player of a studio that makes no sound: tests, and whoever builds a
/// studio without saying otherwise.
class SilentSounds implements SoundPlayer {
  const SilentSounds();
  @override
  void play(StudioSound sound) {}
}

/// The player of the running application.
class SystemSounds implements SoundPlayer {
  SystemSounds({MethodChannel? channel, int Function(int id)? core})
    : _channel = channel ?? const MethodChannel('org.edupaint/sound'),
      _core = core ?? RustDocument.playSound;

  final MethodChannel _channel;
  final int Function(int id) _core;

  // The core said it has no player on this system: the runner is asked.
  bool _throughRunner = false;
  // Nothing plays sounds here: every later request is dropped at once.
  bool _mute = false;
  // The sounds whose bytes the runner already holds.
  final _handed = <int>{};
  StudioSound? _last;
  final _sinceLast = Stopwatch();

  /// The same sound asked again within this time is one sound: a glide of
  /// the eraser over ten elements is not ten noises on top of each other.
  static const sameSoundGap = Duration(milliseconds: 45);

  @override
  void play(StudioSound sound) {
    if (_mute) return;
    if (_last == sound &&
        _sinceLast.isRunning &&
        _sinceLast.elapsed < sameSoundGap) {
      return;
    }
    _last = sound;
    _sinceLast
      ..reset()
      ..start();
    try {
      if (!_throughRunner) {
        final answer = _core(sound.id);
        if (answer != 1) return;
        _throughRunner = true;
      }
      _askRunner(sound);
    } catch (_) {
      _mute = true;
    }
  }

  Future<void> _askRunner(StudioSound sound) async {
    try {
      // The bytes travel once; afterwards the identifier is enough.
      final known = _handed.contains(sound.id);
      final played = await _channel.invokeMethod<bool>('play', {
        'id': sound.id,
        if (!known) 'wav': RustDocument.soundWav(sound.id),
      });
      if (played == true) {
        _handed.add(sound.id);
      } else if (known) {
        // The runner no longer holds it: the next request hands it again.
        _handed.remove(sound.id);
      }
    } on MissingPluginException {
      // This runner plays no sound, and the core does not either.
      _mute = true;
    } catch (_) {
      // One sound lost.
    }
  }
}
