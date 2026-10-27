// SPDX-License-Identifier: MIT
import 'package:edupaint_flutter_study/studio_sounds.dart';

/// Hears what the studio asks to play, and plays nothing.
class RecordingSounds implements SoundPlayer {
  final played = <StudioSound>[];

  @override
  void play(StudioSound sound) => played.add(sound);

  /// What was asked since the last call, forgotten once told.
  List<StudioSound> take() {
    final heard = List<StudioSound>.of(played);
    played.clear();
    return heard;
  }
}
