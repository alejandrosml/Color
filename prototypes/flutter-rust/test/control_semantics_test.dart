// SPDX-License-Identifier: MIT
// What a screen reader meets on the controls added with text, stamps, layers
// and the new tools: one node per control, with its name, its state and the
// action that activates it. No real screen reader is involved here.
import 'dart:io';

import 'package:edupaint_flutter_study/studio_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  // The node of a control: named, a button, and activable unless disabled.
  SemanticsData control(
    WidgetTester tester,
    String key, {
    required String label,
    bool tappable = true,
    bool? selected,
  }) {
    final data = tester.getSemantics(find.byKey(Key(key))).getSemanticsData();
    expect(data.label, label, reason: key);
    expect(data.flagsCollection.isButton, isTrue, reason: key);
    expect(data.hasAction(SemanticsAction.tap), tappable, reason: key);
    if (selected != null) {
      expect(
        data.flagsCollection.isSelected.toBoolOrNull(),
        selected,
        reason: key,
      );
    }
    return data;
  }

  Future<void> activate(WidgetTester tester, String key) async {
    final node = tester.getSemantics(find.byKey(Key(key)));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'tools announce their name and which one is chosen, on the button itself',
    (tester) async {
      final handle = tester.ensureSemantics();
      final studio = StudioDriver(tester);
      await studio.start();
      for (final tool in StudioTool.values) {
        control(
          tester,
          tool.keyName,
          label: tool.label,
          selected: tool == StudioTool.brush,
        );
      }
      await activate(tester, 'tool-eraser');
      control(tester, 'tool-eraser', label: 'Gomme', selected: true);
      control(tester, 'tool-stroke', label: 'Pinceau', selected: false);

      // In a narrow window the buttons keep their names without showing them.
      tester.view.physicalSize = const Size(700, 620);
      await tester.pumpAndSettle();
      expect(find.text('Gomme'), findsNothing);
      for (final tool in StudioTool.values) {
        control(
          tester,
          tool.keyName,
          label: tool.label,
          selected: tool == StudioTool.eraser,
        );
      }
      await activate(tester, 'tool-fill');
      control(tester, 'tool-fill', label: 'Remplir', selected: true);
      handle.dispose();
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'sizes, the stamp chooser and its stamps can be activated without a pointer',
    (tester) async {
      final handle = tester.ensureSemantics();
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('tool-stamp');
      control(
        tester,
        'size-medium',
        label: 'Taille du tampon : Moyen',
        selected: true,
      );
      control(
        tester,
        'size-large',
        label: 'Taille du tampon : Grand',
        selected: false,
      );
      await activate(tester, 'size-large');
      control(
        tester,
        'size-large',
        label: 'Taille du tampon : Grand',
        selected: true,
      );

      control(
        tester,
        'chooseStamp',
        label: 'Tampon Étoile · choisir un autre tampon',
      );
      await activate(tester, 'chooseStamp');
      expect(find.byKey(const Key('stampDialog')), findsOneWidget);
      control(tester, 'stamp-etoile', label: 'Tampon Étoile', selected: true);
      control(tester, 'stamp-coeur', label: 'Tampon Cœur', selected: false);
      await activate(tester, 'stamp-coeur');
      expect(find.byKey(const Key('stampDialog')), findsNothing);
      control(
        tester,
        'chooseStamp',
        label: 'Tampon Cœur · choisir un autre tampon',
      );
      // The stamp really is the one that was activated.
      await studio.click();
      final document = await studio.saved();
      try {
        expect(document.strokes.single.stamp, 1);
        expect(
          right(document.strokes.single) - left(document.strokes.single),
          closeTo(240, .01),
        );
      } finally {
        document.dispose();
      }

      await studio.tap('tool-text');
      control(
        tester,
        'size-medium',
        label: 'Taille du texte : Moyen',
        selected: true,
      );
      await studio.click(studio.at(100, 100));
      control(
        tester,
        'textDialogSize-medium',
        label: 'Taille du texte : Moyen',
        selected: true,
      );
      await activate(tester, 'textDialogSize-small');
      control(
        tester,
        'textDialogSize-small',
        label: 'Taille du texte : Petit',
        selected: true,
      );
      await studio.tap('cancelText');
      handle.dispose();
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a layer is chosen, hidden and moved through its announced actions',
    (tester) async {
      final handle = tester.ensureSemantics();
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('layersButton');
      await studio.tap('addLayer');
      // The layer that receives the drawing says so and offers no action.
      control(
        tester,
        'layer-select-1',
        label: 'Calque 2, tu dessines sur ce calque',
        tappable: false,
        selected: true,
      );
      control(
        tester,
        'layer-select-0',
        label: 'Dessiner sur Calque 1',
        selected: false,
      );
      await activate(tester, 'layer-select-0');
      control(
        tester,
        'layer-select-0',
        label: 'Calque 1, tu dessines sur ce calque',
        tappable: false,
        selected: true,
      );
      control(tester, 'layer-visible-1', label: 'Cacher Calque 2');
      await activate(tester, 'layer-visible-1');
      control(tester, 'layer-visible-1', label: 'Montrer Calque 2');
      control(tester, 'layer-up-0', label: 'Passer Calque 1 devant');
      await activate(tester, 'layer-up-0');
      await studio.tap('closeLayers');
      final document = await studio.saved();
      try {
        expect(document.layers.map((layer) => layer.id), [1, 0]);
        expect(document.layers.map((layer) => layer.visible), [false, true]);
        expect(document.activeLayer, 0);
      } finally {
        document.dispose();
      }
      handle.dispose();
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the pipette, the notches and the big sheet say what they do and whether they are on',
    (tester) async {
      final handle = tester.ensureSemantics();
      final studio = StudioDriver(tester);
      await studio.start();
      control(
        tester,
        'pickPaintColor',
        label: 'Pipette : reprendre une couleur du dessin',
        selected: false,
      );
      await activate(tester, 'pickPaintColor');
      control(
        tester,
        'pickPaintColor',
        label: 'Pipette : reprendre une couleur du dessin',
        selected: true,
      );
      await activate(tester, 'pickPaintColor');

      control(tester, 'bigSheet', label: 'Dessiner en grand', selected: false);
      await activate(tester, 'bigSheet');
      control(
        tester,
        'bigSheet',
        label: 'Retrouver tous les panneaux',
        selected: true,
      );
      await activate(tester, 'bigSheet');
      // The actions of the header, in a window with room for all of them
      // whatever the letters.
      tester.view.physicalSize = const Size(1500, 760);
      await tester.pumpAndSettle();
      control(tester, 'showHelp', label: 'Comment faire ?');
      control(tester, 'printDrawing', label: 'Imprimer');
      tester.view.physicalSize = const Size(1100, 760);
      await tester.pumpAndSettle();
      // Here some of them wait in a menu that says what it holds.
      final more = tester
          .getSemantics(
            find.descendant(
              of: find.byKey(const Key('moreFileActions')),
              matching: find.byType(IconButton),
            ),
          )
          .getSemanticsData();
      // Without an album, every action but the help has room on the line.
      expect(more.label, 'Aide, options et informations');
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const Key('moreFileActions')),
            )
            .tooltip,
        more.label,
      );
      expect(more.flagsCollection.isButton, isTrue);

      await studio.tap('tool-stamp');
      await studio.click();
      await studio.tap('tool-select');
      control(
        tester,
        'growSelection',
        label: 'Rendre l’élément plus grand',
        tappable: false,
      );
      await studio.click();
      control(tester, 'growSelection', label: 'Rendre l’élément plus grand');
      control(tester, 'shrinkSelection', label: 'Rendre l’élément plus petit');
      await activate(tester, 'growSelection');
      final document = await studio.saved();
      try {
        expect(
          right(document.strokes.single) - left(document.strokes.single),
          closeTo(187.5, .01),
        );
      } finally {
        document.dispose();
      }
      handle.dispose();
      await studio.finish();
    },
    skip: !available,
  );
}
