// SPDX-License-Identifier: MIT
// A project written by a later version of Color: refused whole, and said so.
import 'dart:io';
import 'dart:typed_data';

import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/studio_driver.dart';

Uint8List fixture(String name) =>
    File('test/fixtures/project-open/$name').readAsBytesSync();

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('version 5 is the newest that this Color knows', () {
    expect(newestProjectVersion, 5);
  });

  test('the announced version is read from a Color header only', () {
    expect(announcedProjectVersion(fixture('portrait-v2.edupaint')), 2);
    expect(announcedProjectVersion(fixture('rgb-v3.edupaint')), 3);
    expect(
      announcedProjectVersion(fixture('layers-text-stamp-v4.edupaint')),
      4,
    );
    expect(announcedProjectVersion(fixture('locked-page-v5.edupaint')), 5);
    expect(announcedProjectVersion(fixture('unknown-version-5.edupaint')), 5);
    expect(announcedProjectVersion(fixture('unknown-version-6.edupaint')), 6);
    // Two bytes, little-endian.
    final far = fixture('portrait-v2.edupaint');
    far[8] = 0x34;
    far[9] = 0x12;
    expect(announcedProjectVersion(far), 0x1234);
    // Not a Color project: no version is guessed.
    expect(announcedProjectVersion(fixture('rgb.png')), isNull);
    expect(announcedProjectVersion(const []), isNull);
    expect(announcedProjectVersion('EDUPAINT'.codeUnits), isNull);
    final flagged = fixture('portrait-v2.edupaint')..[10] = 1;
    expect(announcedProjectVersion(flagged), isNull);
    final renamed = fixture('portrait-v2.edupaint')..[0] = 0x65;
    expect(announcedProjectVersion(renamed), isNull);
  });

  test('a newer project is refused with its own error, nothing is loaded', () {
    final newer = fixture('unknown-version-6.edupaint');
    expect(
      () => RustDocument.fromProject(newer),
      throwsA(
        isA<NewerProjectException>()
            .having((error) => error.version, 'version', 6)
            .having((error) => error.message, 'message', contains('format 6'))
            .having(
              (error) => error.message,
              'message',
              contains('les formats 1 à 5'),
            ),
      ),
    );
    // A damaged project of a known version keeps the ordinary refusal. The
    // body of version 2 announced as version 5 was a newer project until
    // Color read version 5: it is now a malformed version 5 file.
    for (final name in [
      'bad-project-crc.edupaint',
      'truncated.edupaint',
      'unknown-stamp-v4.edupaint',
      'unknown-version-5.edupaint',
      'locked-active-v5.edupaint',
    ]) {
      expect(
        () => RustDocument.fromProject(fixture(name)),
        throwsA(allOf(isFormatException, isNot(isA<NewerProjectException>()))),
        reason: name,
      );
    }
  }, skip: !available);

  test('the worker used by Ouvrir reports the newer format too', () async {
    await expectLater(
      RustDocument.loadProjectBytes(fixture('unknown-version-6.edupaint')),
      throwsA(
        isA<NewerProjectException>().having((e) => e.version, 'version', 6),
      ),
    );
    for (final name in [
      'bad-project-crc.edupaint',
      'unknown-version-5.edupaint',
    ]) {
      await expectLater(
        RustDocument.loadProjectBytes(fixture(name)),
        throwsA(allOf(isFormatException, isNot(isA<NewerProjectException>()))),
        reason: name,
      );
    }
  }, skip: !available);

  testWidgets(
    'the studio says that the drawing comes from a newer Color and keeps the current one',
    (tester) async {
      final files = MemoryFiles()..openPath = '/drawings/demain.edupaint';
      files.projects[files.openPath!] = fixture('unknown-version-6.edupaint');
      files.projects['/drawings/abime.edupaint'] = fixture(
        'bad-project-crc.edupaint',
      );
      final studio = StudioDriver(tester, files: files);
      await studio.start();
      await studio.tap('tool-stamp');
      await studio.click();
      studio.expectCount(1);

      await studio.tap('openProject');
      expect(
        find.text(
          'Ce dessin vient d’une version plus récente de Color. Installe la dernière version pour l’ouvrir. Le dessin actuel est conservé.',
        ),
        findsOneWidget,
      );
      // The details name both formats, for whoever helps.
      expect(find.byKey(const Key('showProblemDetails')), findsOneWidget);
      studio.expectCount(1);
      expect(studio.isDirty, isTrue);

      files.openPath = '/drawings/abime.edupaint';
      await studio.tap('openProject');
      expect(
        find.text(
          'Ce projet n’a pas pu être ouvert. Le dessin actuel est conservé.',
        ),
        findsOneWidget,
      );
      studio.expectCount(1);

      // A page drawing of version 5 is no newer drawing: it opens.
      files.openPath = '/drawings/page.edupaint';
      files.projects[files.openPath!] = fixture('locked-page-v5.edupaint');
      await studio.tap('openProject');
      if (find.byKey(const Key('discardChanges')).evaluate().isNotEmpty) {
        await studio.tap('discardChanges');
      }
      // What the child made: the three objects of the layers that are not
      // locked; the zones of the page are white, untouched.
      studio.expectCount(3);
      expect(find.textContaining('version plus récente'), findsNothing);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );
}
