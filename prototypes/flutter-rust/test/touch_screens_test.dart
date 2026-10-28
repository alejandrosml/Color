// SPDX-License-Identifier: MIT
// Color on a tablet or a telephone: the words of a finger, the studio scaled
// to the screen, two fingers that move the view, and the files of a device
// without a panel to choose a folder.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:edupaint_flutter_study/fit_to_screen.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/studio_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  tearDown(() => debugTouchFirstOverride = null);

  test('a finger touches where a mouse clicks, and has no Échap nor Maj', () {
    debugTouchFirstOverride = false;
    const brush =
        'Clique pour commencer ton trait, bouge, puis clique pour l’arrêter. Tu peux aussi glisser.';
    expect(forTouch(brush), brush);
    debugTouchFirstOverride = true;
    expect(
      forTouch(brush),
      'Touche pour commencer ton trait, bouge, puis touche pour l’arrêter. Tu peux aussi glisser.',
    );
    expect(
      forTouch(
        'Glisse pour créer un rectangle, ou clique un coin puis le coin d’en face. Avec la touche Maj, il devient un carré !',
      ),
      'Glisse pour créer un rectangle, ou touche un coin puis le coin d’en face.',
    );
    expect(
      forTouch(
        'Clique sur une couleur de ton dessin pour la reprendre. Échap garde ta couleur.',
      ),
      'Touche une couleur de ton dessin pour la reprendre.',
    );
    expect(
      forTouch('Clique-le pour le prendre.'),
      'Touche-le pour le prendre.',
    );
    expect(
      forTouch('Une couleur cliquée le change aussitôt.'),
      'Une couleur touchée le change aussitôt.',
    );
    expect(forTouch('Souris ou stylet.'), 'Doigt ou stylet.');
    expect(thisDevice, 'cet appareil');
    debugTouchFirstOverride = false;
    expect(thisDevice, 'cet ordinateur');
  });

  test(
    'the studio keeps its size on a large screen and shrinks on a small one',
    () {
      expect(fitScale(const Size(1180, 820)), 1);
      expect(fitScale(const Size(680, 520)), 1);
      // A short window on its side: the height decides.
      expect(fitScale(const Size(844, 390)), closeTo(390 / 520, 1e-9));
      // The studio of a telephone needs less room.
      expect(fitScale(const Size(844, 390), minimum: phoneMinimumSize), 1);
      expect(
        fitScale(const Size(480, 300), minimum: phoneMinimumSize),
        closeTo(480 / 560, 1e-9),
      );
      // A small window of an iPad: the width decides.
      expect(fitScale(const Size(340, 700)), closeTo(0.5, 1e-9));
      expect(fitScale(Size.zero), 1);
    },
  );

  group('on a tablet', () {
    setUp(() => debugTouchFirstOverride = true);

    // A telephone has a studio of its own: phone_layout_test.dart.
    testWidgets('in a small window the whole studio is there, scaled down, '
        'and a finger draws', (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(844, 390));
      expect(tester.takeException(), isNull);
      expect(find.byType(FitToScreen), findsOneWidget);
      expect(find.byType(FittedBox), findsWidgets);
      for (final key in ['tool-stroke', 'saveProject', 'undo']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      await studio.drag(const Offset(-40, -20), const Offset(30, 20));
      studio.expectCount(1);
      await studio.finish();
    }, skip: !available);

    testWidgets('two fingers move the view and draw nothing', (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(1180, 820));
      final center = studio.sheetCenter;
      final first = await tester.startGesture(
        center - const Offset(60, 0),
        kind: PointerDeviceKind.touch,
        pointer: 1,
      );
      await first.moveBy(const Offset(4, 0));
      await tester.pump();
      final second = await tester.startGesture(
        center + const Offset(60, 0),
        kind: PointerDeviceKind.touch,
        pointer: 2,
      );
      await tester.pump();
      for (var step = 0; step < 5; step++) {
        await first.moveBy(const Offset(-12, 3));
        await second.moveBy(const Offset(12, 3));
        await tester.pump();
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The trait the first finger began was let go.
      studio.expectCount(0);
      // The sheet is drawn larger than before: the fit button can bring it
      // back, which it only offers when the view moved.
      await studio.drag(const Offset(-20, -10), const Offset(20, 10));
      studio.expectCount(1);
      await studio.finish();
    }, skip: !available);
  });

  group('the files of a tablet', () {
    late Directory folder;
    setUp(() async {
      folder = await Directory.systemTemp.createTemp('color-mobile-files-');
    });
    tearDown(() async {
      await folder.delete(recursive: true);
    });

    StudioFiles files({StudioHandOver? handOver}) => StudioFiles(
      mobile: true,
      documentsDirectory: () async => '${folder.path}/documents',
      outboxDirectory: () async => '${folder.path}/temporary',
      handOver: handOver,
    );

    test('a drawing is saved in Color’s folder, under a free name', () async {
      final studio = files();
      final first = await studio.chooseSave();
      expect(first, '${folder.path}/documents/Dessins/Mon dessin.edupaint');
      await File(first!).writeAsBytes([1, 2, 3]);
      // Saved again, it stays where it is.
      expect(await studio.chooseSave(currentPath: first), first);
      // A new drawing takes the next free name.
      expect(
        await studio.chooseSave(),
        '${folder.path}/documents/Dessins/Mon dessin 2.edupaint',
      );
      // A drawing opened from elsewhere is saved in Color's folder, under
      // its own name.
      expect(
        await studio.chooseSave(currentPath: '/ailleurs/La mer.edupaint'),
        '${folder.path}/documents/Dessins/La mer.edupaint',
      );
      expect(studio.shownPath(first), 'Mon dessin.edupaint');
    });

    test('an image is handed to the system’s panel, then taken out', () async {
      final handed = <(String, String, String, List<int>)>[];
      final studio = files(
        handOver: (path, name, mime) async {
          handed.add((path, name, mime, await File(path).readAsBytes()));
          return 'Dessin pour mamie.png';
        },
      );
      final path = await studio.choosePng(currentPath: '/x/La mer.edupaint');
      expect(path, '${folder.path}/temporary/color-outbox/La mer.png');
      await studio.writePng(path!, Uint8List.fromList([9, 8, 7]));
      expect(handed.single.$2, 'La mer.png');
      expect(handed.single.$3, 'image/png');
      expect(handed.single.$4, [9, 8, 7]);
      expect(File(path).existsSync(), isFalse);
      expect(studio.shownPath(path), 'Dessin pour mamie.png');

      final svg = await studio.chooseExport();
      expect(svg, '${folder.path}/temporary/color-outbox/Mon dessin.svg');
      await studio.writeSvgBytes(svg!, Uint8List.fromList([60, 115]));
      expect(handed.last.$3, 'image/svg+xml');
    });

    test('a closed panel writes nothing and says nothing wrong', () async {
      final studio = files(handOver: (path, name, mime) async => null);
      final path = await studio.choosePng();
      await expectLater(
        studio.writePng(path!, Uint8List.fromList([1])),
        throwsA(isA<CopyNotHandedOver>()),
      );
      expect(File(path).existsSync(), isFalse);
    });
  });
}
