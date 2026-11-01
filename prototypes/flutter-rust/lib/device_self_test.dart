// SPDX-License-Identifier: MIT
// The trial that the launchers of the Mac run inside the iPhone and iPad
// simulators and the Android emulators: is the core there, does a drawing go
// through its file and back, does a picture come out of it, do Color's
// folders take files, does a sound start. Compiled only into the builds of
// trial (--dart-define=COLOR_SELF_TEST=true); a build for the stores holds
// nothing of it.
import 'dart:convert';
import 'dart:io';

import 'app_folders.dart';
import 'document_exports.dart';
import 'png_export.dart';
import 'rust_document.dart';
import 'studio_files.dart';
import 'studio_sounds.dart';

/// Whether this build is one of trial.
const deviceSelfTest = bool.fromEnvironment('COLOR_SELF_TEST');

/// The marker the launchers look for in the console of the device.
const selfTestMarker = 'COLOR-SELF-TEST';

/// The file of the results, in Color's own folder of the device.
const selfTestFile = 'color-essai.json';

/// Runs every check, prints one line per check and a last line with all of
/// them in JSON, each after [selfTestMarker]. Never throws: a failed check
/// is a line that says so.
Future<Map<String, Object?>> runDeviceSelfTest() async {
  final results = <String, Object?>{};
  Future<void> check(String name, Future<Object?> Function() run) async {
    try {
      final detail = await run();
      results[name] = {'ok': true, 'detail': detail};
    } catch (error) {
      results[name] = {'ok': false, 'error': '$error'};
    }
    // ignore: avoid_print
    print('$selfTestMarker $name ${jsonEncode(results[name])}');
  }

  results['system'] =
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  RustDocument? document;
  await check('core', () async {
    document = RustDocument();
    document!.addStroke(
      const [DocumentPoint(40, 60), DocumentPoint(400, 300)],
      rgb: 0x307eab,
      width: 14,
    );
    if (document!.count != 1) throw StateError('1 élément attendu');
    return 'library ${RustDocument.defaultLibraryPath}, ${document!.count} element';
  });
  await check('project', () async {
    final bytes = await prepareProjectBytes(document!);
    final reopened = RustDocument.fromProject(bytes);
    try {
      if (reopened.count != 1) {
        throw StateError('le projet relu a perdu le trait');
      }
    } finally {
      reopened.dispose();
    }
    return '${bytes.length} bytes';
  });
  await check('png', () async {
    final png = await exportDocumentPng(
      document!.visibleStrokes,
      width: document!.width,
      height: document!.height,
    );
    const signature = [0x89, 0x50, 0x4e, 0x47];
    for (var i = 0; i < signature.length; i++) {
      if (png[i] != signature[i]) throw StateError('pas une image PNG');
    }
    return '${png.length} bytes';
  });
  await check('folders', () async {
    final support = await applicationSupportFolder();
    final documents = await applicationDocumentsFolder();
    final temporary = await temporaryFolder();
    // The folders are where path_provider put them before 1.0.1 (P-01):
    // the drawings, the options and the copy of recovery of a person who
    // updates Color are there.
    final wrong = misplacedFolders(
      support: support.path,
      documents: documents.path,
      temporary: temporary.path,
    );
    if (wrong.isNotEmpty) throw StateError('dossiers déplacés : $wrong');
    final drawings = await const StudioFiles(mobile: true).ownDrawings();
    if (!drawings.path.startsWith(documents.path)) {
      throw StateError('les dessins sont hors des documents');
    }
    for (final folder in [drawings, temporary]) {
      final probe = File('${folder.path}/.essai-color');
      await probe.writeAsString('Color');
      final read = await probe.readAsString();
      await probe.delete();
      if (read != 'Color') throw StateError('fichier relu différent');
    }
    return {
      'support': support.path,
      'documents': documents.path,
      'temporary': temporary.path,
      'drawings': drawings.path,
    };
  });
  await check('sound', () async {
    // The core plays it where it has a player of its own (Android); 1 says
    // that the application plays it (iOS), which SystemSounds then asks.
    final answer = RustDocument.playSound(StudioSound.bravo.id);
    SystemSounds().play(StudioSound.click);
    return 'core answered $answer';
  });
  document?.dispose();
  final passed = results.values.whereType<Map>().every((r) => r['ok'] == true);
  results['passed'] = passed;
  // ignore: avoid_print
  print('$selfTestMarker RESULT ${jsonEncode(results)}');
  // The same, in a file of Color's own folder that the launcher reads from
  // the simulator or the emulator.
  try {
    final support = await applicationSupportFolder();
    await File('${support.path}${Platform.pathSeparator}$selfTestFile')
        .writeAsString(jsonEncode(results));
  } catch (_) {
    // The lines of the console remain.
  }
  return results;
}

/// The folders of [support], [documents] and [temporary] that are not where
/// path_provider gave them on this system: on the iPhone and the iPad,
/// Library/Application Support, Documents and Library/Caches of the
/// container; on Android, files, app_flutter and cache of the application;
/// on the Mac, the same as on the iPhone with the identifier of Color after
/// Application Support and Caches. Elsewhere none is checked.
List<String> misplacedFolders({
  required String support,
  required String documents,
  required String temporary,
  String? system,
}) {
  final on = system ?? Platform.operatingSystem;
  bool under(String path, String parent) {
    final at = path.lastIndexOf('/');
    return at > 0 && path.substring(0, at).endsWith(parent);
  }

  final checks = switch (on) {
    'ios' => {
      'support': support.endsWith('/Library/Application Support'),
      'documents': documents.endsWith('/Documents'),
      'temporary': temporary.endsWith('/Library/Caches'),
    },
    'android' => {
      'support': support.endsWith('/files'),
      'documents': documents.endsWith('/app_flutter'),
      'temporary': temporary.endsWith('/cache'),
    },
    'macos' => {
      'support': under(support, '/Library/Application Support'),
      'documents': documents.endsWith('/Documents'),
      'temporary': under(temporary, '/Library/Caches'),
    },
    _ => <String, bool>{},
  };
  return [
    for (final MapEntry(:key, :value) in checks.entries)
      if (!value) key,
  ];
}
