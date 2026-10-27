// SPDX-License-Identifier: MIT
// The actions on the whole drawing, at the top of the studio, measured with
// the real letters of the interface: « Imprimer » is the last of them, and
// the header takes one line wherever Color 0.7.0+30, with one action less,
// took one — from 1112 pixels with the album, from 956 without — and never
// more than two.
import 'dart:io';

import 'package:edupaint_flutter_study/studio_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/interface_font.dart';
import 'support/memory_gallery.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  // The actions in the order of the header, by their keys.
  const order = [
    'newProject',
    'openProject',
    'openGallery',
    'importImage',
    'saveProject',
    'exportImage',
    'printDrawing',
  ];

  // The actions that stand as buttons, from left to right.
  List<String> buttons(WidgetTester tester) {
    final shown = [
      for (final key in order)
        if (find.byKey(Key(key)).evaluate().isNotEmpty) key,
    ];
    for (final key in shown) {
      expect(
        tester.widget(find.byKey(Key(key))),
        isA<ButtonStyleButton>(),
        reason: key,
      );
    }
    return shown;
  }

  String? menuName(WidgetTester tester) {
    final menu = find.byKey(const Key('moreFileActions'));
    return menu.evaluate().isEmpty
        ? null
        : tester.widget<PopupMenuButton<String>>(menu).tooltip;
  }

  Future<void> resize(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '$width');
  }

  testWidgets(
    'with ordinary letters Imprimer is a button in every window, the last one, on one line of actions',
    (tester) async {
      await loadInterfaceFont(tester);
      final studio = StudioDriver(tester, gallery: MemoryGallery());
      await studio.start(size: const Size(1280, 800));
      var named = 0;
      for (var width = 680.0; width <= 1600; width += 10) {
        await resize(tester, width);
        final shown = buttons(tester);
        expect(shown.last, 'printDrawing', reason: '$width');
        expect(
          shown,
          containsAll([
            'newProject',
            'openProject',
            'saveProject',
            'exportImage',
          ]),
          reason: '$width',
        );
        // One line of actions, in the order of the header, none over another.
        final rects = [
          for (final key in shown) tester.getRect(find.byKey(Key(key))),
        ];
        for (var index = 0; index < rects.length; index++) {
          final rect = rects[index];
          final where = '${shown[index]} at $width';
          expect(rect.top, rects.first.top, reason: where);
          expect(rect.height, greaterThanOrEqualTo(48), reason: where);
          expect(rect.left, greaterThanOrEqualTo(16), reason: where);
          expect(rect.right, lessThanOrEqualTo(width - 16), reason: where);
          if (index > 0) {
            expect(
              rect.left,
              greaterThanOrEqualTo(rects[index - 1].right + 6),
              reason: where,
            );
          }
        }
        // The name of the app, when it is there, takes one more line at
        // most: never a third one from the sheet.
        final header = tester.getSize(find.byType(StudioHeader)).height;
        final name = find.text('Color');
        if (name.evaluate().isEmpty) {
          expect(header, lessThanOrEqualTo(70), reason: '$width');
          expect(menuName(tester), isNotNull, reason: '$width');
        } else {
          named++;
          expect(header, lessThanOrEqualTo(124), reason: '$width');
          expect(shown, order, reason: 'every action beside the name, $width');
          expect(menuName(tester), isNull, reason: '$width');
        }
        // Where the six actions of 0.7.0+30 stood beside the name, the
        // seven of today do too, once the toothed wheel of the options has
        // its 48 pixels beside the name: not one line more than that.
        if (width >= 1160) {
          expect(name, findsOneWidget, reason: '$width');
          expect(header, lessThanOrEqualTo(70), reason: '$width');
        }
      }
      // The name is there in the wider windows, as before.
      expect(named, greaterThan(40));
      await resize(tester, 1280);
      expect(find.text('Color'), findsOneWidget);
      // On one line with the actions at the size the studio opens with.
      expect(
        tester.getSize(find.byType(StudioHeader)).height,
        lessThanOrEqualTo(70),
      );
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'what has no room on the line waits in the « … » menu, whose name says what it holds',
    (tester) async {
      await loadInterfaceFont(tester);
      final studio = StudioDriver(tester, gallery: MemoryGallery());
      await studio.start(size: const Size(680, 800));
      // The smallest window: the four actions of every day, and Imprimer.
      expect(buttons(tester), [
        'newProject',
        'openProject',
        'saveProject',
        'exportImage',
        'printDrawing',
      ]);
      expect(menuName(tester), 'Galerie, image, aide, options et informations');
      await tester.tap(find.byKey(const Key('moreFileActions')));
      await tester.pumpAndSettle();
      expect(find.text('Mes dessins'), findsOneWidget);
      expect(find.text('Dessiner sur une image…'), findsOneWidget);
      expect(find.text('Imprimer…'), findsNothing);
      expect(find.text('Comment faire ?'), findsOneWidget);
      expect(find.text('À propos de Color'), findsOneWidget);
      await tester.tapAt(const Offset(5, 400));
      await tester.pumpAndSettle();

      // A little wider: « Mes dessins » joins the line, then the image.
      await resize(tester, 800);
      expect(buttons(tester), [
        'newProject',
        'openProject',
        'openGallery',
        'saveProject',
        'exportImage',
        'printDrawing',
      ]);
      expect(menuName(tester), 'Image, aide, options et informations');
      await resize(tester, 910);
      expect(buttons(tester), order);
      expect(menuName(tester), 'Aide, options et informations');
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'with letters twice as large the smallest window keeps its four actions, and the menu holds Imprimer',
    (tester) async {
      await loadInterfaceFont(tester);
      final studio = StudioDriver(tester, gallery: MemoryGallery());
      // The smallest window that the runners allow. With letters this large
      // its four actions take two lines, as they did before this version;
      // nothing overflows.
      await studio.start(size: const Size(680, 800), textScale: 2);
      expect(buttons(tester), [
        'newProject',
        'openProject',
        'saveProject',
        'exportImage',
      ]);
      expect(
        menuName(tester),
        'Galerie, image, impression, aide, options et informations',
      );
      expect(
        tester.getSize(find.byType(StudioHeader)).height,
        inInclusiveRange(120, 130),
      );
      // A few pixels wider, they are on one line.
      await resize(tester, 700);
      expect(
        tester.getSize(find.byType(StudioHeader)).height,
        lessThanOrEqualTo(70),
      );
      expect(buttons(tester), hasLength(4));
      // With room for it, Imprimer is the first to come back on the line.
      await resize(tester, 900);
      expect(buttons(tester), [
        'newProject',
        'openProject',
        'saveProject',
        'exportImage',
        'printDrawing',
      ]);
      expect(menuName(tester), 'Galerie, image, aide, options et informations');
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('without an album the header has six actions and no gap', (
    tester,
  ) async {
    await loadInterfaceFont(tester);
    final studio = StudioDriver(tester);
    await studio.start(size: const Size(1280, 800));
    expect(buttons(tester), [
      for (final key in order)
        if (key != 'openGallery') key,
    ]);
    // One line with the name from the width where 0.7.0+30 had one, plus
    // the 48 pixels of the toothed wheel of the options.
    for (var width = 1004.0; width <= 1600; width += 4) {
      await resize(tester, width);
      expect(find.text('Color'), findsOneWidget, reason: '$width');
      expect(
        tester.getSize(find.byType(StudioHeader)).height,
        lessThanOrEqualTo(70),
        reason: '$width',
      );
      expect(buttons(tester), hasLength(6), reason: '$width');
    }
    await resize(tester, 680);
    expect(buttons(tester), [
      'newProject',
      'openProject',
      'saveProject',
      'exportImage',
      'printDrawing',
    ]);
    expect(menuName(tester), 'Image, aide, options et informations');
    await tester.tap(find.byKey(const Key('moreFileActions')));
    await tester.pumpAndSettle();
    expect(find.text('Mes dessins'), findsNothing);
    await tester.tapAt(const Offset(5, 400));
    await tester.pumpAndSettle();
    await studio.finish();
  }, skip: !available);
}
