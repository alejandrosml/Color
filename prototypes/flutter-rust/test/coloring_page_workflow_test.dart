// SPDX-License-Identifier: MIT
// A colouring page chosen in « Nouveau », in the real studio with the real
// Rust core; only dialogs' destinations and storage are in memory. The page
// makes a document of its own: its zones on a locked layer under the layer
// where the child draws, its lines on another locked layer above it.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/coloring_pages.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/new_sheet_dialog.dart';
import 'package:edupaint_flutter_study/replay.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/selection_geometry.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/memory_gallery.dart';
import 'support/prepared_open_wait.dart';
import 'support/studio_driver.dart';

const _ink = 0x2f3d4a;
const _white = 0xffffff;
const _zones = 1;
const _drawing = 0;
const _lines = 2;

/// What the core makes of a page, read from a document of its own.
class _Page {
  _Page(ColoringPage page) {
    final document = RustDocument.fromPage(page.id);
    try {
      count = document.count;
      layers = document.layers;
      objects = document.strokes;
    } finally {
      document.dispose();
    }
  }
  late final int count;
  late final List<LayerData> layers;
  late final List<StrokeData> objects;

  Iterable<int> on(int layer) => [
    for (var index = 0; index < objects.length; index++)
      if (objects[index].layer == layer) index,
  ];
}

Rect _box(StrokeData object) =>
    Rect.fromLTRB(left(object), top(object), right(object), bottom(object));

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  ColoringPage page(String key) =>
      ColoringPages.all.singleWhere((page) => page.key == key);

  // What the sheet shows: the elements its painter was given.
  int painted(WidgetTester tester) =>
      (_painter(tester) as dynamic).strokes.length as int;

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(Key(key))).onPressed != null;

  // A zone of the page whose middle no zone drawn after it covers: where a
  // child would pour the paint. The largest one.
  (int, DocumentPoint) freeZone(_Page made) {
    int? found;
    var largest = 0.0;
    var middle = const DocumentPoint(0, 0);
    final zones = made.on(_zones).toList();
    for (final index in zones) {
      final box = _box(made.objects[index]);
      final covered = zones
          .where((other) => other > index)
          .any(
            (other) =>
                _box(made.objects[other]).inflate(8).contains(box.center),
          );
      final area = box.width * box.height;
      if (!covered && area > largest) {
        found = index;
        largest = area;
        middle = DocumentPoint(box.center.dx, box.center.dy);
      }
    }
    return (found!, middle);
  }

  // A rectangular zone whose outline is a whole line of the page, with no
  // zone drawn after it near the middle of its top side.
  int outlinedZone(_Page made) {
    final zones = made.on(_zones).toList();
    for (final index in zones) {
      final zone = made.objects[index];
      if (zone.kind != VectorKind.rectangle) continue;
      final box = _box(zone);
      final outlined = made
          .on(_lines)
          .map((line) => made.objects[line])
          .any(
            (line) => line.kind == VectorKind.rectangle && _box(line) == box,
          );
      final top = Offset(box.center.dx, box.top);
      final near = zones
          .where((other) => other > index)
          .any((other) => _box(made.objects[other]).inflate(12).contains(top));
      if (outlined && !near) return index;
    }
    fail('No zone of the page is outlined by a whole line.');
  }

  testWidgets(
    'a page makes a sheet of its own: its zones and its lines locked around the layer of the child, nothing to undo',
    (tester) async {
      final house = page('maison');
      final made = _Page(house);
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('newProject');
      expect(find.text('Ou une page à colorier'), findsOneWidget);
      await studio.tap('page-maison');
      // A sheet without changes is replaced without a question.
      expect(find.byKey(const Key('newSheetDialog')), findsNothing);
      expect(find.byKey(const Key('saveChanges')), findsNothing);
      // The page is painted whole, but the child made nothing yet.
      studio.expectCount(0);
      expect(painted(tester), made.count);
      expect(studio.isDirty, isFalse);
      // The sheet starts clean: Annuler has no step to take, the page is
      // not one.
      expect(studio.menu.onUndo, isNull);
      expect(studio.menu.onRedo, isNull);
      expect(made.layers, [
        LayerData(
          id: _zones,
          visible: true,
          objectCount: house.regions,
          locked: true,
        ),
        const LayerData(id: _drawing, visible: true, objectCount: 0),
        LayerData(
          id: _lines,
          visible: true,
          objectCount: made.count - house.regions,
          locked: true,
        ),
      ]);
      // The child draws on the layer between them, the first of its own.
      expect(
        find.bySemanticsLabel('Calques : tu dessines sur Calque 1'),
        findsOneWidget,
      );

      final document = await studio.saved();
      try {
        expect((document.width, document.height), (house.width, house.height));
        expect(document.layers, made.layers);
        expect(document.activeLayer, _drawing);
        expect(document.lockedLayers, {_zones, _lines});
        expect(document.exportProject()[8], 5);
        // Reopened, the page is still out of the history.
        expect(document.undoCount, 0);
        for (final index in made.on(_zones)) {
          final zone = document.strokes[index];
          expect(zone.kind.canFill, isTrue);
          expect(zone.fillRgb, _white);
          // Only the inside shows: the outline is white and very thin.
          expect(zone.rgb, _white);
          expect(zone.width, closeTo(.1, 1e-6));
          expect(document.isLockedObject(index), isTrue);
        }
        for (final index in made.on(_lines)) {
          expect(document.strokes[index].fillRgb, isNull);
          expect(document.strokes[index].rgb, _ink);
        }
      } finally {
        document.dispose();
      }
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the pot colours a zone, also through a line of the page, and Annuler gives it its white back',
    (tester) async {
      final house = page('maison');
      final made = _Page(house);
      final (zone, middle) = freeZone(made);
      final outlined = outlinedZone(made);
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('newProject');
      await studio.tap('page-maison');
      await studio.tap('tool-fill');

      // In the middle of a zone, alone.
      await studio.tap('color-eebf4e');
      await studio.click(studio.at(middle.x, middle.y));
      // A coloured zone is what the child made.
      studio.expectCount(1);
      expect(studio.isDirty, isTrue);
      var document = await studio.saved();
      try {
        expect(document.strokes[zone].fillRgb, 0xeebf4e);
        // The outline of the zone stays as the page has it.
        expect(document.strokes[zone].rgb, _white);
        expect(document.strokes[zone].width, closeTo(.1, 1e-6));
        expect(
          made
              .on(_zones)
              .where((index) => document.strokes[index].fillRgb == _white),
          hasLength(house.regions - 1),
        );
        expect(document.paperRgb, whitePaper);
        // In the image too, the zone alone.
        expect(
          'fill="#eebf4e" stroke="#ffffff"'.allMatches(document.exportSvg()),
          hasLength(1),
        );
      } finally {
        document.dispose();
      }

      // On the line that draws the top of another zone, just inside it: the
      // line keeps its colour, the zone under it takes the paint.
      final box = _box(made.objects[outlined]);
      await studio.tap('color-9385bc');
      await studio.click(studio.at(box.center.dx, box.top + 1));
      studio.expectCount(2);
      document = await studio.saved();
      try {
        expect(document.strokes[outlined].fillRgb, 0x9385bc);
        expect(
          made.on(_lines).map((index) => document.strokes[index].rgb).toSet(),
          {_ink},
        );
      } finally {
        document.dispose();
      }

      // Annuler takes each colour back, and stops at the page.
      await studio.tap('undo');
      await studio.tap('undo');
      expect(studio.menu.onUndo, isNull);
      studio.expectCount(0);
      document = await studio.saved();
      try {
        for (final index in made.on(_zones)) {
          expect(document.strokes[index].fillRgb, _white, reason: '$index');
        }
      } finally {
        document.dispose();
      }
      await studio.tap('redo');
      await studio.tap('redo');
      document = await studio.saved();
      try {
        expect(document.strokes[zone].fillRgb, 0xeebf4e);
        expect(document.strokes[outlined].fillRgb, 0x9385bc);
      } finally {
        document.dispose();
      }
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'seen up close, a click on the outer half of a line colours the zone it draws, not the sheet',
    (tester) async {
      final house = page('maison');
      final made = _Page(house);
      final outlined = outlinedZone(made);
      final box = _box(made.objects[outlined]);
      final line =
          made.objects[made
              .on(_lines)
              .firstWhere((index) => _box(made.objects[index]) == box)];
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('newProject');
      await studio.tap('page-maison');
      await studio.tap('tool-fill');
      // Close enough that the line is wider than what the pointer reaches.
      while (_viewport(tester).scale < 1.5) {
        await studio.tap('zoomIn');
      }
      final scale = _viewport(tester).scale;
      final beyond = (precisePixels + .5) / scale;
      expect(beyond, lessThan(line.width / 2 - .5));
      await studio.tap('color-e69976');
      await tester.tapAt(_onScreen(tester, box.center.dx, box.top - beyond));
      await tester.pumpAndSettle();
      var document = await studio.saved();
      try {
        expect(document.strokes[outlined].fillRgb, 0xe69976);
        expect(document.paperRgb, whitePaper);
      } finally {
        document.dispose();
      }
      // Beside the line, the sheet itself.
      await studio.tap('color-9385bc');
      await tester.tapAt(
        _onScreen(tester, box.center.dx, box.top - line.width / 2 - 4),
      );
      await tester.pumpAndSettle();
      document = await studio.saved();
      try {
        expect(document.paperRgb, 0x9385bc);
        expect(document.strokes[outlined].fillRgb, 0xe69976);
      } finally {
        document.dispose();
      }
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the eraser and Choisir go through the page to what the child drew under it',
    (tester) async {
      final house = page('maison');
      final made = _Page(house);
      final box = _box(made.objects[outlinedZone(made)]);
      // A point on the left side of the zone's line, and a trait of the
      // child that passes under that line lower down.
      final onLine = Offset(box.left, box.top + 8);
      final crossing = Offset(box.left, box.top + box.height / 2);
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('newProject');
      await studio.tap('page-maison');
      await studio.tap('tool-stroke');
      await studio.drag(
        studio.at(crossing.dx - 60, crossing.dy),
        studio.at(crossing.dx + 60, crossing.dy),
      );
      studio.expectCount(1);
      final document = await studio.saved();
      final trait = document.strokes.last;
      document.dispose();
      expect(trait.layer, _drawing);

      // The eraser finds nothing of the page to take.
      await studio.tap('tool-eraser');
      await studio.click(studio.at(onLine.dx, onLine.dy));
      await studio.click(studio.at(box.center.dx, box.center.dy));
      studio.expectCount(1);
      // Where the trait passes under the line, the trait goes.
      await studio.click(studio.at(crossing.dx, crossing.dy));
      studio.expectCount(0);
      await studio.tap('undo');
      studio.expectCount(1);

      // Choisir sees through the page the same way.
      await studio.tap('tool-select');
      await studio.click(studio.at(onLine.dx, onLine.dy));
      expect(find.text('Clique un élément pour le choisir.'), findsOneWidget);
      await studio.click(studio.at(box.center.dx, box.center.dy));
      expect(find.text('Clique un élément pour le choisir.'), findsOneWidget);
      await studio.click(studio.at(crossing.dx, crossing.dy));
      expect(find.text('Clique un élément pour le choisir.'), findsNothing);
      // The page has no layer of its own to receive an element.
      await tester.tap(find.byKey(const Key('selectionOrder')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('moveSelectionLayerUp')), findsNothing);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      await studio.tap('deleteSelection');
      studio.expectCount(0);
      final after = await studio.saved();
      try {
        expect(after.strokes.length, made.count);
        expect(after.unlockedPaintOrder, isEmpty);
      } finally {
        after.dispose();
      }
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the panel shows the page locked: it is hidden and shown, never chosen, moved nor erased',
    (tester) async {
      final house = page('maison');
      final made = _Page(house);
      final handle = tester.ensureSemantics();
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('newProject');
      await studio.tap('page-maison');
      await studio.tap('layersButton');
      expect(find.text('Page'), findsNWidgets(2));
      expect(find.text('Calque 1'), findsOneWidget);
      expect(find.byKey(const Key('lockedPageNote')), findsOneWidget);
      // The page says that it is locked; how many elements made it is not
      // what the child did, and is not shown.
      expect(find.text('verrouillée'), findsNWidgets(2));
      expect(find.textContaining('éléments · verrouillée'), findsNothing);
      expect(find.text('0 élément · tu dessines ici'), findsOneWidget);
      // The lines above the drawing, the zones under it.
      double rowTop(int id) =>
          tester.getTopLeft(find.byKey(Key('layer-row-$id'))).dy;
      expect(rowTop(_lines), lessThan(rowTop(_drawing)));
      expect(rowTop(_drawing), lessThan(rowTop(_zones)));
      for (final id in [_zones, _lines]) {
        final row = tester
            .getSemantics(find.byKey(Key('layer-select-$id')))
            .getSemanticsData();
        expect(row.label, 'Page à colorier, verrouillée');
        expect(row.flagsCollection.isButton, isFalse);
        expect(row.hasAction(SemanticsAction.tap), isFalse);
        expect(enabled(tester, 'layer-visible-$id'), isTrue);
        expect(enabled(tester, 'layer-up-$id'), isFalse);
        expect(enabled(tester, 'layer-down-$id'), isFalse);
        expect(enabled(tester, 'layer-delete-$id'), isFalse);
      }
      expect(find.bySemanticsLabel('Cacher la page'), findsNWidgets(2));
      // The only layer to draw on is neither hidden nor erased, and does not
      // move: no layer passes the page, which lies on both sides of it.
      expect(enabled(tester, 'layer-visible-$_drawing'), isFalse);
      expect(enabled(tester, 'layer-delete-$_drawing'), isFalse);
      expect(enabled(tester, 'layer-up-$_drawing'), isFalse);
      expect(enabled(tester, 'layer-down-$_drawing'), isFalse);
      // A click on the page chooses nothing.
      await tester.tap(find.byKey(const Key('layer-select-$_lines')));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Calque 1, tu dessines sur ce calque'),
        findsOneWidget,
      );

      // Hidden and shown, as any layer: one step each for Annuler.
      await studio.tap('layer-visible-$_lines');
      expect(find.bySemanticsLabel('Montrer la page'), findsOneWidget);
      expect(find.text('verrouillée · cachée'), findsOneWidget);
      expect(find.text('verrouillée'), findsOneWidget);
      await studio.tap('closeLayers');
      expect(painted(tester), made.count);
      var document = await studio.saved();
      try {
        expect(document.layers.map((layer) => layer.visible), [
          true,
          true,
          false,
        ]);
        expect(document.layers.map((layer) => layer.locked), [
          true,
          false,
          true,
        ]);
        expect(document.paintOrder, made.on(_zones).toList());
      } finally {
        document.dispose();
      }
      await studio.tap('undo');
      expect(studio.menu.onUndo, isNull);

      // Another layer to draw on: the second, whatever the page's numbers.
      await studio.layers(() async {
        await studio.tap('addLayer');
        expect(find.text('Calque 2'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Calque 2, tu dessines sur ce calque'),
          findsOneWidget,
        );
        expect(enabled(tester, 'layer-delete-$_drawing'), isTrue);
        // Just above the first one, under the lines of the page: the two
        // change places between the zones and the lines, never past them.
        expect(rowTop(3), lessThan(rowTop(_drawing)));
        expect(rowTop(_lines), lessThan(rowTop(3)));
        expect(enabled(tester, 'layer-up-3'), isFalse);
        expect(enabled(tester, 'layer-down-3'), isTrue);
        expect(enabled(tester, 'layer-up-$_drawing'), isTrue);
        expect(enabled(tester, 'layer-down-$_drawing'), isFalse);
        await studio.tap('layer-down-3');
        expect(rowTop(_drawing), lessThan(rowTop(3)));
        expect(rowTop(3), lessThan(rowTop(_zones)));
        expect(enabled(tester, 'layer-up-3'), isTrue);
        expect(enabled(tester, 'layer-down-3'), isFalse);
        expect(enabled(tester, 'layer-up-$_drawing'), isFalse);
        expect(enabled(tester, 'layer-down-$_drawing'), isTrue);
        // The page itself stays where it is.
        for (final id in [_zones, _lines]) {
          expect(enabled(tester, 'layer-up-$id'), isFalse);
          expect(enabled(tester, 'layer-down-$id'), isFalse);
        }
        await studio.tap('layer-delete-$_drawing');
        expect(find.byKey(const Key('layer-row-$_drawing')), findsNothing);
        expect(enabled(tester, 'layer-delete-3'), isFalse);
        expect(enabled(tester, 'layer-up-3'), isFalse);
        expect(enabled(tester, 'layer-down-3'), isFalse);
      });
      document = await studio.saved();
      try {
        expect(document.layers.map((layer) => layer.id), [_zones, 3, _lines]);
        expect(document.activeLayer, 3);
        expect(document.lockedLayers, {_zones, _lines});
      } finally {
        document.dispose();
      }
      handle.dispose();
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'Ordre sends an element to the next layer to draw on, between the zones and the lines of the page',
    (tester) async {
      final made = _Page(page('maison'));
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('newProject');
      await studio.tap('page-maison');
      await studio.drag(studio.at(100, 300), studio.at(300, 360));
      // A second layer to draw on, just above the first one and under the
      // lines of the page, and the first one chosen again.
      await studio.layers(() async {
        await studio.tap('addLayer');
        await studio.tap('layer-select-$_drawing');
      });
      await studio.tap('tool-select');
      await studio.click(studio.at(200, 330));
      PopupMenuItem<Object?> item(String key) =>
          tester.widget<PopupMenuItem<Object?>>(find.byKey(Key(key)));
      Future<void> openOrder() async {
        await tester.tap(find.byKey(const Key('selectionOrder')));
        await tester.pumpAndSettle();
      }

      // Above: the new layer. Below: the zones of the page, which receive
      // nothing.
      await openOrder();
      expect(item('moveSelectionLayerUp').enabled, isTrue);
      expect(item('moveSelectionLayerDown').enabled, isFalse);
      await tester.tap(find.byKey(const Key('moveSelectionLayerUp')));
      await tester.pumpAndSettle();
      // On the new layer, the lines of the page above it: no further up.
      await openOrder();
      expect(item('moveSelectionLayerUp').enabled, isFalse);
      expect(item('moveSelectionLayerDown').enabled, isTrue);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      final document = await studio.saved();
      try {
        expect(document.layers.map((layer) => layer.id), [
          _zones,
          _drawing,
          3,
          _lines,
        ]);
        expect(document.strokes.last.layer, 3);
        expect(document.strokes.length, made.count + 1);
        // The page did not move.
        for (final index in made.on(_lines)) {
          expect(document.strokes[index].layer, _lines);
        }
      } finally {
        document.dispose();
      }
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'nothing passes a layer of the page, even in a drawing that has a layer to draw on above its lines',
    (tester) async {
      // A drawing made elsewhere: the child's layer 5 lies above the lines.
      // Two traits on each layer to draw on, so that « Ordre » has
      // something to offer for the lower one.
      (int, double, VectorKind, List<(double, double)>, int, int?) trait(
        double y,
        int layer,
      ) => (0xd75e56, 12, VectorKind.stroke, [(200, y), (500, y)], layer, null);
      const sheet = [(100.0, 100.0), (1100.0, 700.0)];
      final files = MemoryFiles()..openPath = '/drawings/au-dessus.edupaint';
      files.projects[files.openPath!] = _projectV5(
        layers: const [
          (_zones, _visibleFlag | _lockedFlag),
          (_drawing, _visibleFlag),
          (_lines, _visibleFlag | _lockedFlag),
          (5, _visibleFlag),
        ],
        active: _drawing,
        objects: [
          (_white, .1, VectorKind.rectangle, sheet, _zones, _white),
          trait(300, _drawing),
          trait(340, _drawing),
          (_ink, 6, VectorKind.rectangle, sheet, _lines, null),
          trait(500, 5),
          trait(540, 5),
        ],
      );
      final studio = StudioDriver(tester, files: files);
      await studio.start();
      await studio.tap('openProject');
      studio.expectCount(4);
      // Neither layer to draw on moves: the lines lie between them.
      await studio.layers(() async {
        for (final id in [_zones, _drawing, _lines, 5]) {
          expect(enabled(tester, 'layer-up-$id'), isFalse, reason: '$id');
          expect(enabled(tester, 'layer-down-$id'), isFalse, reason: '$id');
        }
      });
      // Nor does an element go from one to the other over the lines.
      await studio.tap('tool-select');
      PopupMenuItem<Object?> item(String key) =>
          tester.widget<PopupMenuItem<Object?>>(find.byKey(Key(key)));
      for (final y in [300.0, 500.0]) {
        await studio.click(studio.at(350, y));
        await tester.tap(find.byKey(const Key('selectionOrder')));
        await tester.pumpAndSettle();
        expect(item('moveSelectionLayerUp').enabled, isFalse, reason: '$y');
        expect(item('moveSelectionLayerDown').enabled, isFalse, reason: '$y');
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
      }
      expect(studio.isDirty, isFalse);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'erasing the last layer to draw on that is shown first shows another, never the page',
    (tester) async {
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('newProject');
      await studio.tap('page-maison');
      await studio.layers(() async {
        await studio.tap('addLayer');
        // The first layer hidden, the page hidden too: the new one is the
        // only layer shown to draw on.
        await studio.tap('layer-visible-$_drawing');
        await studio.tap('layer-visible-$_zones');
        expect(enabled(tester, 'layer-visible-3'), isFalse);
        expect(enabled(tester, 'layer-delete-3'), isTrue);
        await studio.tap('layer-delete-3');
        expect(
          find.bySemanticsLabel('Calque 1, tu dessines sur ce calque'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Cacher Calque 1'), findsOneWidget);
      });
      var document = await studio.saved();
      try {
        expect(document.layers.map((layer) => (layer.id, layer.visible)), [
          (_zones, false),
          (_drawing, true),
          (_lines, true),
        ]);
        expect(document.activeLayer, _drawing);
      } finally {
        document.dispose();
      }
      // The drawing goes on, on that layer.
      await studio.tap('tool-stroke');
      await studio.drag(studio.at(100, 300), studio.at(300, 360));
      document = await studio.saved();
      try {
        expect(document.strokes.last.layer, _drawing);
      } finally {
        document.dispose();
      }
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a trait being drawn passes under the lines of the page, where it stays once drawn; on a sheet, over the drawing as before',
    (tester) async {
      final made = _Page(page('maison'));
      final box = _box(made.objects[outlinedZone(made)]);
      // A trait of the child across the left line of an outlined zone.
      final y = box.top + box.height / 2;
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('newProject');
      await studio.tap('page-maison');
      await studio.tap('tool-stroke');
      await studio.tap('color-d75e56');
      final gesture = await tester.startGesture(
        studio.sheetCenter + studio.at(box.left - 60, y),
      );
      await gesture.moveTo(studio.sheetCenter + studio.at(box.left, y));
      await gesture.moveTo(studio.sheetCenter + studio.at(box.left + 60, y));
      await tester.pump();
      // Still being drawn: over the zone, under the line.
      var sheet = await _sheetNow(tester);
      expect(sheet(box.left - 40, y), 0xd75e56);
      expect(sheet(box.left + 40, y), 0xd75e56);
      expect(sheet(box.left, y), _ink);
      await gesture.up();
      await tester.pumpAndSettle();
      studio.expectCount(1);
      // Drawn: nothing moved.
      sheet = await _sheetNow(tester);
      expect(sheet(box.left - 40, y), 0xd75e56);
      expect(sheet(box.left + 40, y), 0xd75e56);
      expect(sheet(box.left, y), _ink);

      // On a sheet without a page, the trait being drawn covers the
      // drawing, as it always did, and as it does once drawn.
      await studio.newSheet('landscape');
      await studio.tap('tool-stroke');
      await studio.tap('color-9385bc');
      await studio.drag(studio.at(600, 200), studio.at(600, 600));
      await studio.tap('color-d75e56');
      final across = await tester.startGesture(
        studio.sheetCenter + studio.at(500, 400),
      );
      await across.moveTo(studio.sheetCenter + studio.at(600, 400));
      await across.moveTo(studio.sheetCenter + studio.at(700, 400));
      await tester.pump();
      sheet = await _sheetNow(tester);
      expect(sheet(600, 300), 0x9385bc);
      expect(sheet(600, 400), 0xd75e56);
      await across.up();
      await tester.pumpAndSettle();
      studio.expectCount(2);
      sheet = await _sheetNow(tester);
      expect(sheet(600, 300), 0x9385bc);
      expect(sheet(600, 400), 0xd75e56);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'the film shows the page white from its first frame, colours its zones in turn, then redraws what the child drew',
    (tester) async {
      final house = page('maison');
      final made = _Page(house);
      final (_, middle) = freeZone(made);
      final box = _box(made.objects[outlinedZone(made)]);
      final studio = StudioDriver(tester);
      await studio.start();
      await studio.tap('newProject');
      await studio.tap('page-maison');
      VoidCallback? replayButton() => tester
          .widget<IconButton>(find.byKey(const Key('replayDrawing')))
          .onPressed;
      // The page alone has nothing to show again.
      expect(replayButton(), isNull);
      expect(studio.menu.onReplay, isNull);
      // A zone that the paint pot coloured has.
      await studio.tap('tool-fill');
      await studio.tap('color-eebf4e');
      await studio.click(studio.at(middle.x, middle.y));
      expect(replayButton(), isNotNull);
      expect(studio.menu.onReplay, isNotNull);
      await studio.tap('undo');
      expect(replayButton(), isNull);
      await studio.tap('redo');
      expect(replayButton(), isNotNull);
      // A trait of the child, under the left line of an outlined zone.
      await studio.tap('tool-stroke');
      await studio.tap('color-d75e56');
      final y = box.top + box.height / 2;
      await studio.drag(
        studio.at(box.left - 60, y),
        studio.at(box.left + 60, y),
      );

      // Opened without waiting for the film to end: its first frame.
      await tester.tap(find.byKey(const Key('replayDrawing')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Le film de ton dessin commence.'), findsOneWidget);
      // The first frame: the page as it was made, white; nothing drawn.
      var shot = await _replayShot(tester);
      final sheet = _replaySheet(shot.size);
      Offset at(double x, double y) =>
          Offset(sheet.left + x * sheet.scale, sheet.top + y * sheet.scale);
      expect(shot.rgbAt(at(box.left, box.top + box.height / 4)), _ink);
      expect(shot.rgbAt(at(middle.x, middle.y)), _white);
      expect(shot.rgbAt(at(box.left - 40, y)), isNot(0xd75e56));
      // The zone takes its colour first…
      await tester.pump(ReplayPlan.zone + ReplayPlan.pause);
      shot = await _replayShot(tester);
      expect(shot.rgbAt(at(middle.x, middle.y)), 0xeebf4e);
      expect(shot.rgbAt(at(box.left - 40, y)), isNot(0xd75e56));
      // … then the trait, a short film however many lines the page has.
      await tester.pump(_oneTraitFilm);
      await tester.pump();
      expect(find.text('Ton dessin est fini.'), findsOneWidget);
      shot = await _replayShot(tester);
      expect(shot.rgbAt(at(box.left - 40, y)), 0xd75e56);
      // The line of the page stays over the trait.
      expect(shot.rgbAt(at(box.left, y)), _ink);
      expect(shot.rgbAt(at(middle.x, middle.y)), 0xeebf4e);
      await studio.tap('closeReplay');
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets(
    'a page drawing saved in version 5 opens again with its page locked, and so does its recovery copy',
    (tester) async {
      final house = page('maison');
      final made = _Page(house);
      final (zone, middle) = freeZone(made);
      final gallery = MemoryGallery();
      final studio = StudioDriver(tester, gallery: gallery);
      await studio.start();
      await studio.tap('newProject');
      await studio.tap('page-maison');
      await studio.tap('tool-fill');
      await studio.tap('color-eebf4e');
      await studio.click(studio.at(middle.x, middle.y));
      await studio.tap('tool-stroke');
      await studio.drag(studio.at(100, 300), studio.at(300, 360));
      // One coloured zone and one trait.
      studio.expectCount(2);
      // The copy of recovery is a project of version 5 too.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(studio.recovery.bytes, isNotNull);
      expect(studio.recovery.bytes![8], 5);
      await studio.tap('saveProject');
      final saved = studio.files.projects.values.single;
      expect(saved[8], 5);
      // The card of the album counts what the child made too.
      for (
        var attempt = 0;
        attempt < 500 && gallery.rememberCalls < 1;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await tester.pumpAndSettle();
      expect(gallery.entries.single.elementCount, 2);

      await studio.newSheet('landscape');
      studio.expectCount(0);
      studio.files.openPath = studio.files.savePath;
      await studio.tap('openProject');
      studio.expectCount(2);
      expect(studio.isDirty, isFalse);
      final document = RustDocument.fromProject(saved);
      try {
        expect(document.lockedLayers, {_zones, _lines});
        expect(document.layers.map((layer) => layer.objectCount), [
          house.regions,
          1,
          made.count - house.regions,
        ]);
        expect(document.strokes[zone].fillRgb, 0xeebf4e);
        // Only the trait of the child is a step to undo.
        expect(document.undoCount, 1);
        expect(document.exportProject(), saved);
      } finally {
        document.dispose();
      }
      // Reopened, the page is still out of the eraser's reach…
      await studio.tap('tool-eraser');
      await studio.click(studio.at(middle.x, middle.y));
      studio.expectCount(2);
      // … and of Annuler, which takes the trait and stops there.
      await studio.tap('undo');
      studio.expectCount(1);
      expect(studio.menu.onUndo, isNull);
      await studio.layers(() async {
        expect(find.text('Page'), findsNWidgets(2));
      });

      // The copy of recovery brings the page back locked as well.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(studio.recovery.bytes, isNotNull);
      await studio.finish();
      final recovered = studio.recovery.bytes!;
      expect(recovered[8], 5);
      await tester.pumpWidget(
        EduPaintApp(files: studio.files, recoveryStorage: studio.recovery),
      );
      await waitForPreparedOpen(tester, allowRecoveryDecision: true);
      // The question counts the coloured zone, not the page.
      expect(
        find.textContaining('Une copie locale contient 1 élément.'),
        findsOneWidget,
      );
      await studio.tap('restoreRecovery');
      studio.expectCount(1);
      await studio.layers(() async {
        expect(find.text('Page'), findsNWidgets(2));
        expect(enabled(tester, 'layer-delete-$_zones'), isFalse);
      });
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('a drawing with changes is kept or left first, as for a sheet', (
    tester,
  ) async {
    final robot = _Page(page('robot'));
    final studio = StudioDriver(tester);
    await studio.start();
    await studio.drag(studio.at(300, 300), studio.at(500, 400));
    studio.expectCount(1);
    await studio.tap('newProject');
    await studio.tap('page-robot');
    expect(find.byKey(const Key('saveChanges')), findsOneWidget);
    await studio.tap('cancelChanges');
    studio.expectCount(1);
    await studio.tap('newProject');
    await studio.tap('page-robot');
    await studio.tap('discardChanges');
    studio.expectCount(0);
    expect(painted(tester), robot.count);
    expect(studio.isDirty, isFalse);
    expect(studio.menu.onUndo, isNull);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  for (final level in InterfaceLevel.values) {
    testWidgets(
      'the pages are in « Nouveau » of the ${level.label} interface',
      (tester) async {
        final flower = page('fleur');
        final made = _Page(flower);
        final studio = StudioDriver(
          tester,
          options: StudioOptionsStore.memory(StudioOptions(level: level)),
        );
        await studio.start();
        await studio.tap('newProject');
        for (final offered in ColoringPages.all) {
          expect(find.byKey(Key('page-${offered.key}')), findsOneWidget);
        }
        await studio.tap('page-${flower.key}');
        expect(painted(tester), made.count);
        // Painted on the sheet of the page.
        expect(find.byType(NewSheetDialog), findsNothing);
        // The paint pot colours its zones in every interface.
        final (zone, middle) = freeZone(made);
        await studio.tap('tool-fill');
        await studio.tap('color-eebf4e');
        await tester.tapAt(_onScreen(tester, middle.x, middle.y));
        await tester.pumpAndSettle();
        final document = await studio.saved();
        try {
          expect(document.strokes[zone].fillRgb, 0xeebf4e);
          expect(document.strokes[zone].rgb, _white);
          expect(document.lockedLayers, {_zones, _lines});
        } finally {
          document.dispose();
        }
        expect(tester.takeException(), isNull);
        await studio.finish();
      },
      skip: !available,
    );
  }
}

CustomPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find
          .descendant(
            of: find.byKey(const Key('drawingSurface')),
            matching: find.byType(CustomPaint),
          )
          .first,
    )
    .painter!;

/// Where the studio shows the sheet now, zoomed or not.
DocumentViewport _viewport(WidgetTester tester) =>
    (_painter(tester) as dynamic).viewport as DocumentViewport;

/// What the studio shows of the sheet now: the colour at a point of the
/// sheet.
Future<int Function(double x, double y)> _sheetNow(WidgetTester tester) async {
  final canvas = find
      .descendant(
        of: find.byKey(const Key('drawingSurface')),
        matching: find.byType(RepaintBoundary),
      )
      .first;
  final boundary = tester.renderObject<RenderRepaintBoundary>(canvas);
  final origin = tester.getTopLeft(canvas);
  final shot = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return _ReplayShot(
        boundary.size,
        image.width,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  }))!;
  return (x, y) => shot.rgbAt(_onScreen(tester, x, y) - origin);
}

const _visibleFlag = 1;
const _lockedFlag = 2;

/// A project of version 5 written by hand from the description of the
/// format in edupaint_core.h, as tools/make_layered_fixtures.py writes its
/// files: a sheet of 1200 by 800, its [layers] as (identifier, flags) from
/// the bottom up, and its [objects] as (colour, width, kind, points, layer,
/// colour of the inside).
Uint8List _projectV5({
  required List<(int, int)> layers,
  required int active,
  required List<(int, double, VectorKind, List<(double, double)>, int, int?)>
  objects,
}) {
  final points = objects.fold(0, (sum, object) => sum + object.$4.length);
  final length = 56 + 8 * layers.length + 36 * objects.length + 8 * points + 4;
  final data = ByteData(length);
  var at = 0;
  void u32(int value) {
    data.setUint32(at, value, Endian.little);
    at += 4;
  }

  void f32(double value) {
    data.setFloat32(at, value, Endian.little);
    at += 4;
  }

  for (final byte in 'EDUPAINT'.codeUnits) {
    data.setUint8(at++, byte);
  }
  data.setUint16(at, 5, Endian.little);
  data.setUint16(at + 2, 0, Endian.little);
  at += 4;
  for (final value in [
    length,
    1200,
    800,
    objects.length,
    points,
    0,
    layers.length,
    0,
    active,
    0,
    0,
  ]) {
    u32(value);
  }
  for (final (id, flags) in layers) {
    u32(id);
    u32(flags);
  }
  for (final (rgb, width, kind, shape, layer, fill) in objects) {
    u32(rgb);
    f32(width);
    u32(shape.length);
    u32(kind.index);
    u32(fill == null ? 0 : 1);
    u32(fill ?? 0);
    u32(layer);
    u32(0);
    u32(0);
    for (final (x, y) in shape) {
      f32(x);
      f32(y);
    }
  }
  var crc = 0xffffffff;
  for (var index = 0; index < at; index++) {
    crc ^= data.getUint8(index);
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
  }
  u32(crc ^ 0xffffffff);
  return data.buffer.asUint8List();
}

/// Where a point of the sheet is on the screen.
Offset _onScreen(WidgetTester tester, double x, double y) {
  final viewport = _viewport(tester);
  return tester.getTopLeft(find.byKey(const Key('drawingSurface'))) +
      Offset(
        viewport.left + x * viewport.scale,
        viewport.top + y * viewport.scale,
      );
}

/// Longer than the film of one trait of the child, however long the trait.
const _oneTraitFilm = Duration(milliseconds: 2600);

/// The pixels of the sheet of the film, and the size they were painted at.
class _ReplayShot {
  _ReplayShot(this.size, this.width, this.rgba);
  final Size size;
  final int width;
  final List<int> rgba;

  int rgbAt(Offset point) {
    final offset = (point.dy.floor() * width + point.dx.floor()) * 4;
    return (rgba[offset] << 16) | (rgba[offset + 1] << 8) | rgba[offset + 2];
  }
}

Future<_ReplayShot> _replayShot(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('replaySheet')),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return _ReplayShot(
        boundary.size,
        image.width,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  }))!;
}

/// Where the film lays the sheet of the page out in its box.
DocumentViewport _replaySheet(Size size) => DocumentViewport(
  viewWidth: size.width,
  viewHeight: size.height,
  documentWidth: 1200,
  documentHeight: 800,
  padding: size.shortestSide >= 160 ? 16 : 8,
);
