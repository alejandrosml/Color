// SPDX-License-Identifier: MIT
// Real Rust documents; only dialogs' destinations and storage are in memory.
import 'dart:io';
import 'dart:typed_data';

import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/prepared_open_wait.dart';
import 'support/studio_driver.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(Key(key))).onPressed != null;

  // A rectangle between two document points, outlined and filled with one
  // palette colour.
  Future<void> rectangle(
    StudioDriver studio,
    String color,
    Offset from,
    Offset to,
  ) async {
    await studio.tap('tool-rectangle');
    await studio.tap('color-$color');
    // Choosing a colour for the inside also turns the filling on.
    await studio.tap('paint-target-fill');
    await studio.tap('color-$color');
    await studio.drag(studio.at(from.dx, from.dy), studio.at(to.dx, to.dy));
  }

  testWidgets(
    'the panel starts with one layer; adding a layer is one undoable step',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('layersButton');
      expect(find.text('Mes calques'), findsOneWidget);
      expect(find.byKey(const Key('layer-row-0')), findsOneWidget);
      expect(find.text('Calque 1'), findsOneWidget);
      expect(find.text('0 élément · tu dessines ici'), findsOneWidget);
      // A single layer can be neither hidden, moved nor erased.
      expect(enabled(tester, 'layer-visible-0'), isFalse);
      expect(enabled(tester, 'layer-up-0'), isFalse);
      expect(enabled(tester, 'layer-down-0'), isFalse);
      expect(enabled(tester, 'layer-delete-0'), isFalse);

      await studio.tap('addLayer');
      expect(find.byKey(const Key('layer-row-1')), findsOneWidget);
      // The new layer is on top of the list and receives the drawing.
      expect(
        tester.getTopLeft(find.byKey(const Key('layer-row-1'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('layer-row-0'))).dy),
      );
      expect(find.text('0 élément · tu dessines ici'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Calque 2, tu dessines sur ce calque'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Dessiner sur Calque 1'), findsOneWidget);
      expect(enabled(tester, 'layer-delete-0'), isTrue);
      expect(enabled(tester, 'layer-visible-1'), isTrue);
      await studio.tap('closeLayers');
      studio.expectCount(0);
      expect(studio.isDirty, isTrue);
      expect(
        find.bySemanticsLabel('Calques : tu dessines sur Calque 2'),
        findsOneWidget,
      );

      var document = await studio.saved();
      try {
        expect(document.layers.map((layer) => layer.id), [0, 1]);
        expect(document.activeLayer, 1);
        expect(document.exportProject()[8], 4);
      } finally {
        document.dispose();
      }
      expect(studio.isDirty, isFalse);
      await studio.tap('undo');
      expect(studio.isDirty, isTrue);
      await studio.layers(() async {
        expect(find.byKey(const Key('layer-row-1')), findsNothing);
        expect(find.text('0 élément · tu dessines ici'), findsOneWidget);
      });
      await studio.tap('redo');
      // Back on the saved state: the history and the save point agree.
      expect(studio.isDirty, isFalse);
      await studio.layers(() async {
        expect(find.byKey(const Key('layer-row-1')), findsOneWidget);
      });
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'drawing lands on the chosen layer; a hidden layer leaves the sheet and the images, not the project',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await rectangle(
        studio,
        '477fb2',
        const Offset(100, 100),
        const Offset(500, 500),
      );
      await studio.layers(() => studio.tap('addLayer'));
      await rectangle(
        studio,
        'd75e56',
        const Offset(300, 300),
        const Offset(700, 700),
      );
      studio.expectCount(2);
      var png = await studio.png();
      expect(await studio.pixel(png, 200, 200), [0x47, 0x7f, 0xb2, 255]);
      expect(await studio.pixel(png, 400, 400), [0xd7, 0x5e, 0x56, 255]);
      var exported = await studio.svg();
      expect(exported, contains('<g id="calque-1">'));
      expect(exported, contains('<g id="calque-2">'));
      expect(
        exported.indexOf('calque-1'),
        lessThan(exported.indexOf('calque-2')),
      );

      await studio.layers(() async {
        expect(find.text('1 élément'), findsOneWidget);
        expect(find.text('1 élément · tu dessines ici'), findsOneWidget);
        await studio.tap('layer-visible-0');
        expect(find.text('1 élément · caché'), findsOneWidget);
        expect(find.bySemanticsLabel('Montrer Calque 1'), findsOneWidget);
        // The only layer still shown cannot be hidden as well.
        expect(enabled(tester, 'layer-visible-1'), isFalse);
      });
      // Hidden objects still belong to the drawing.
      studio.expectCount(2);
      png = await studio.png();
      expect(await studio.pixel(png, 200, 200), [255, 255, 255, 255]);
      expect(await studio.pixel(png, 400, 400), [0xd7, 0x5e, 0x56, 255]);
      exported = await studio.svg();
      expect(exported, isNot(contains('calque-1')));
      expect(exported, isNot(contains('#477fb2')));
      expect(exported, contains('<g id="calque-2">'));
      // A hidden object cannot be chosen through the sheet.
      await studio.tap('tool-select');
      await studio.click(studio.at(200, 200));
      expect(find.text('Clique un élément pour le choisir.'), findsOneWidget);

      final document = await studio.saved();
      try {
        expect(document.strokes, hasLength(2));
        expect(document.strokes.map((object) => object.layer), [0, 1]);
        expect(document.layers.map((layer) => layer.visible), [false, true]);
        expect(document.paintOrder, [1]);
      } finally {
        document.dispose();
      }
      await studio.layers(() => studio.tap('layer-visible-0'));
      png = await studio.png();
      expect(await studio.pixel(png, 200, 200), [0x47, 0x7f, 0xb2, 255]);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'moving a layer changes what is in front, on the sheet, in images and for Choisir',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await rectangle(
        studio,
        '477fb2',
        const Offset(100, 100),
        const Offset(500, 500),
      );
      await studio.layers(() => studio.tap('addLayer'));
      await rectangle(
        studio,
        'd75e56',
        const Offset(300, 300),
        const Offset(700, 700),
      );
      var png = await studio.png();
      expect(await studio.pixel(png, 400, 400), [0xd7, 0x5e, 0x56, 255]);

      await studio.layers(() async {
        await studio.tap('layer-up-0');
        // Calque 1 is now the first row of the list.
        expect(
          tester.getTopLeft(find.byKey(const Key('layer-row-0'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const Key('layer-row-1'))).dy),
        );
        expect(enabled(tester, 'layer-up-0'), isFalse);
        expect(enabled(tester, 'layer-down-0'), isTrue);
      });
      png = await studio.png();
      expect(await studio.pixel(png, 400, 400), [0x47, 0x7f, 0xb2, 255]);
      final exported = await studio.svg();
      expect(
        exported.indexOf('calque-2'),
        lessThan(exported.indexOf('calque-1')),
      );

      // Choisir takes what is seen in front: the blue rectangle of the layer
      // now on top, although it was drawn first.
      await studio.tap('tool-select');
      await studio.click(studio.at(400, 400));
      await studio.tap('deleteSelection');
      studio.expectCount(1);
      var document = await studio.saved();
      try {
        expect(document.strokes.single.rgb, 0xd75e56);
        expect(document.layers.map((layer) => layer.id), [1, 0]);
      } finally {
        document.dispose();
      }
      // Annuler: the rectangle returns, then the layers swap back.
      await studio.tap('undo');
      await studio.tap('undo');
      png = await studio.png();
      expect(await studio.pixel(png, 400, 400), [0xd7, 0x5e, 0x56, 255]);
      await studio.layers(() async {
        await studio.tap('layer-down-1');
        expect(enabled(tester, 'layer-down-1'), isFalse);
      });
      png = await studio.png();
      expect(await studio.pixel(png, 400, 400), [0x47, 0x7f, 0xb2, 255]);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'erasing a layer removes its elements in one step that Annuler restores',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.addText('fond');
      await studio.layers(() => studio.tap('addLayer'));
      await studio.tap('tool-stamp');
      await studio.click(studio.at(200, 200));
      await studio.click(studio.at(900, 600));
      studio.expectCount(3);
      final before = await studio.svg();

      await studio.layers(() async {
        expect(find.text('2 éléments · tu dessines ici'), findsOneWidget);
        await studio.tap('layer-delete-1');
        expect(find.byKey(const Key('layer-row-1')), findsNothing);
        expect(find.text('1 élément · tu dessines ici'), findsOneWidget);
        expect(enabled(tester, 'layer-delete-0'), isFalse);
      });
      studio.expectCount(1);
      // One plain layer again: the image has no layer groups any more.
      expect(await studio.svg(), isNot(contains('calque')));

      await studio.tap('undo');
      studio.expectCount(3);
      expect(await studio.svg(), before);
      final document = await studio.saved();
      try {
        expect(document.strokes.map((object) => object.layer), [0, 1, 1]);
        // The restored layer receives the drawing again.
        expect(document.activeLayer, 1);
      } finally {
        document.dispose();
      }
      await studio.tap('redo');
      studio.expectCount(1);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the drawing never continues on a hidden layer', (tester) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.layers(() async {
      await studio.tap('addLayer');
      // Hiding the layer that receives the drawing hands over to the other.
      await studio.tap('layer-visible-1');
      expect(
        find.bySemanticsLabel('Calque 1, tu dessines sur ce calque'),
        findsOneWidget,
      );
    });
    await studio.tap('tool-stamp');
    await studio.click();
    studio.expectCount(1);
    var document = await studio.saved();
    try {
      expect(document.strokes.single.layer, 0);
      expect(document.activeLayer, 0);
    } finally {
      document.dispose();
    }

    // Choosing a hidden layer shows it: one step for Annuler.
    await studio.layers(() async {
      await studio.tap('layer-select-1');
      expect(find.bySemanticsLabel('Cacher Calque 2'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Calque 2, tu dessines sur ce calque'),
        findsOneWidget,
      );
    });
    // Annuler hides it again, and the drawing moves back to a visible layer.
    await studio.tap('undo');
    await studio.click(studio.at(900, 200));
    studio.expectCount(2);
    document = await studio.saved();
    try {
      expect(document.layers.map((layer) => layer.visible), [true, false]);
      expect(document.strokes.map((object) => object.layer), [0, 0]);
    } finally {
      document.dispose();
    }

    // Erasing the last visible layer first shows its neighbour.
    await studio.layers(() async {
      await studio.tap('layer-delete-0');
      expect(find.byKey(const Key('layer-row-0')), findsNothing);
      expect(find.bySemanticsLabel('Cacher Calque 2'), findsOneWidget);
      expect(find.text('0 élément · tu dessines ici'), findsOneWidget);
    });
    studio.expectCount(0);
    await studio.click(studio.at(300, 500));
    studio.expectCount(1);
    // Each Annuler leaves something to see: the stamp, the erased layer…
    await studio.tap('undo');
    await studio.tap('undo');
    studio.expectCount(2);
    await studio.layers(() async {
      expect(find.bySemanticsLabel('Cacher Calque 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Cacher Calque 2'), findsOneWidget);
    });
    // … then Calque 2 hidden as before.
    await studio.tap('undo');
    await studio.layers(() async {
      expect(find.bySemanticsLabel('Montrer Calque 2'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Calque 1, tu dessines sur ce calque'),
        findsOneWidget,
      );
    });
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('Ordre sends the chosen element to the layer above or below', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await rectangle(
      studio,
      '477fb2',
      const Offset(100, 100),
      const Offset(500, 500),
    );
    // With a single layer the menu offers no layer move.
    await studio.tap('tool-select');
    await studio.click(studio.at(300, 300));
    await tester.tap(find.byKey(const Key('selectionOrder')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('moveSelectionLayerUp')), findsNothing);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    await studio.layers(() => studio.tap('addLayer'));
    await rectangle(
      studio,
      'd75e56',
      const Offset(300, 300),
      const Offset(700, 700),
    );
    await studio.tap('tool-select');
    await studio.click(studio.at(200, 200));
    await tester.tap(find.byKey(const Key('selectionOrder')));
    await tester.pumpAndSettle();
    expect(find.text('Vers le calque du dessus'), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuItem<Object?>>(
            find.byKey(const Key('moveSelectionLayerDown')),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('moveSelectionLayerUp')));
    await tester.pumpAndSettle();
    // The blue rectangle now covers the red one, and stays chosen.
    var png = await studio.png();
    expect(await studio.pixel(png, 400, 400), [0x47, 0x7f, 0xb2, 255]);
    var document = await studio.saved();
    try {
      expect(document.strokes.map((object) => object.layer), [1, 1]);
      expect(document.strokes.map((object) => object.rgb), [
        0xd75e56,
        0x477fb2,
      ]);
    } finally {
      document.dispose();
    }
    await studio.tap('duplicateSelection');
    studio.expectCount(3);
    await studio.tap('undo');
    await studio.tap('undo');
    png = await studio.png();
    expect(await studio.pixel(png, 400, 400), [0xd7, 0x5e, 0x56, 255]);

    // Sending an element to a hidden layer shows that layer.
    await studio.layers(() => studio.tap('layer-visible-0'));
    await studio.tap('tool-select');
    await studio.click(studio.at(600, 600));
    await tester.tap(find.byKey(const Key('selectionOrder')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('moveSelectionLayerDown')));
    await tester.pumpAndSettle();
    document = await studio.saved();
    try {
      expect(document.layers.map((layer) => layer.visible), [true, true]);
      expect(document.strokes.map((object) => object.layer), [0, 0]);
    } finally {
      document.dispose();
    }
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets('the panel offers eight layers and says when they are all used', (
    tester,
  ) async {
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.tap('layersButton');
    for (var layer = 1; layer < 8; layer++) {
      await studio.tap('addLayer');
    }
    expect(find.text('Tu as déjà 8 calques'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('addLayer')))
          .onPressed,
      isNull,
    );
    for (var layer = 0; layer < 8; layer++) {
      expect(
        find.byKey(Key('layer-row-$layer'), skipOffstage: false),
        findsOneWidget,
      );
    }
    await studio.tap('layer-delete-3');
    expect(find.text('Ajouter un calque'), findsOneWidget);
    // The freed number is used again.
    await studio.tap('addLayer');
    expect(
      find.byKey(const Key('layer-row-3'), skipOffstage: false),
      findsOneWidget,
    );
    await studio.tap('closeLayers');
    final document = await studio.saved();
    try {
      expect(document.layers, hasLength(8));
      expect(document.layers.map((layer) => layer.id).toSet(), {
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      });
    } finally {
      document.dispose();
    }
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'the panel blocks document commands and works in a small window with enlarged text',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start(size: const Size(680, 480), textScale: 2);
      await studio.tap('layersButton');
      expect(find.byKey(const Key('layersDialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
      final menu = studio.menu;
      menu.onNew!();
      menu.onOpen!();
      menu.onSave!();
      menu.onExportSvg!();
      menu.onAbout!();
      menu.onLayers!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      expect(studio.files.projects, isEmpty);
      expect(studio.files.saveDialogCount, 0);
      await studio.tap('addLayer');
      await studio.tap('addLayer');
      expect(tester.takeException(), isNull);
      await studio.tap('layer-visible-1');
      await studio.tap('layer-up-0');
      expect(tester.takeException(), isNull);
      await studio.tap('closeLayers');
      final document = await studio.saved();
      try {
        expect(document.layers.map((layer) => layer.id), [1, 0, 2]);
        expect(document.layers.map((layer) => layer.visible), [
          false,
          true,
          true,
        ]);
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'recovery and reopening keep layers, their order and the hidden ones',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await rectangle(
        studio,
        '477fb2',
        const Offset(100, 100),
        const Offset(500, 500),
      );
      await studio.layers(() async {
        await studio.tap('addLayer');
        await studio.tap('addLayer');
        await studio.tap('layer-visible-0');
        await studio.tap('layer-down-2');
      });
      await studio.addText('dessus', x: 650, y: 100);
      final before = await studio.svg();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(studio.recovery.bytes, isNotNull);
      await studio.finish();

      await tester.pumpWidget(
        EduPaintApp(files: studio.files, recoveryStorage: studio.recovery),
      );
      await waitForPreparedOpen(tester, allowRecoveryDecision: true);
      await studio.tap('restoreRecovery');
      studio.expectCount(2);
      expect(await studio.svg(), before);
      await studio.layers(() async {
        expect(find.text('1 élément · caché'), findsOneWidget);
        expect(find.text('1 élément · tu dessines ici'), findsOneWidget);
      });

      await studio.tap('saveProject');
      await studio.newSheet('landscape');
      studio.expectCount(0);
      await studio.layers(() async {
        // A new sheet starts again with its single layer.
        expect(find.byKey(const Key('layer-row-1')), findsNothing);
      });
      studio.files.openPath = studio.files.savePath;
      await studio.tap('openProject');
      studio.expectCount(2);
      expect(await studio.svg(), before);
      final document = RustDocument.fromProject(
        studio.files.projects.values.single,
      );
      try {
        expect(document.layers.map((layer) => layer.id), [0, 2, 1]);
        expect(document.layers.map((layer) => layer.visible), [
          false,
          true,
          true,
        ]);
        expect(document.activeLayer, 2);
        expect(document.strokes.map((object) => object.layer), [0, 2]);
      } finally {
        document.dispose();
      }
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a project whose layers are all hidden opens, explains itself and can be shown',
    (tester) async {
      // Color itself never writes such a project; another program could.
      final source = RustDocument();
      late final Uint8List bytes;
      try {
        source.addStroke(
          const [DocumentPoint(100, 100), DocumentPoint(300, 300)],
          rgb: 0x477fb2,
          width: 12,
        );
        source.addLayer();
        source.setLayerVisible(0, false);
        source.setLayerVisible(1, false);
        bytes = source.exportProject();
      } finally {
        source.dispose();
      }
      final files = MemoryFiles()..openPath = '/drawings/cache.edupaint';
      files.projects[files.openPath!] = bytes;
      final studio = StudioDriver(tester, files: files);
      await studio.start();
      await studio.tap('openProject');
      studio.expectCount(1);
      await studio.tap('tool-stroke');
      await studio.drag(studio.at(500, 500), studio.at(700, 600));
      // Nothing was drawn blind: the studio says why.
      studio.expectCount(1);
      expect(
        find.textContaining('Tous les calques sont cachés'),
        findsOneWidget,
      );
      expect(studio.isDirty, isFalse);
      await studio.layers(() async {
        await studio.tap('layer-select-0');
      });
      await studio.drag(studio.at(500, 500), studio.at(700, 600));
      studio.expectCount(2);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );
}
