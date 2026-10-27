// SPDX-License-Identifier: MIT
// The sheet comes first: whatever the window, the size of the text and the
// tool, the sheet keeps a height one can draw in, and no control is pushed
// out of the window.
import 'dart:io';

import 'package:edupaint_flutter_study/studio_layout.dart';
import 'package:edupaint_flutter_study/studio_tool.dart';
import 'package:edupaint_flutter_study/tool_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_gallery.dart';
import 'support/studio_driver.dart';

// The letters of the interface, in place of the test font whose every glyph
// is a square: DejaVu Sans, shipped with the project. Wider than the system
// fonts of the Mac and of Windows, it is a prudent stand-in for them. Once
// loaded it serves every later test of this file.
Future<void> _loadInterfaceFont(WidgetTester tester) =>
    tester.runAsync(() async {
      final bytes = await File('fonts/DejaVuSans.ttf').readAsBytes();
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    });

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  bool spacious(double width, double height, {double textScale = 1}) =>
      StudioLayout.spaciousControls(
        width: width,
        height: height,
        narrow: StudioLayout.toolsAbove(
          width: width,
          height: height,
          textScale: textScale,
        ),
        inspector: width >= 1120,
        textScale: textScale,
      );

  test('the tools stand above the sheet where a column would crowd it', () {
    bool above(double width, double height, [double textScale = 1]) =>
        StudioLayout.toolsAbove(
          width: width,
          height: height,
          textScale: textScale,
        );
    // A narrow window, whatever its height.
    expect(above(680, 451), isTrue);
    expect(above(749, 1200), isTrue);
    // A little wider: only while two columns of tools would be needed.
    expect(above(750, 451), isTrue);
    expect(above(819, 600), isTrue);
    expect(above(760, 900), isFalse);
    expect(above(819, 900), isFalse);
    // Wide enough for two columns and a sheet.
    expect(above(820, 451), isFalse);
    expect(above(1280, 451), isFalse);
    // Enlarged text needs more height for one column.
    expect(above(760, 700), isFalse);
    expect(above(760, 700, 2), isTrue);
  });

  test(
    'spacious controls need a comfortable sheet, and only ever more room',
    () {
      // A large window is spacious. A laptop's is not: there the sheet
      // comes first, and the controls keep to their compact form.
      expect(spacious(1280, 802), isTrue);
      expect(spacious(1280, 801), isFalse);
      expect(spacious(1440, 900), isTrue);
      expect(spacious(1280, 724), isFalse);
      expect(spacious(680, 451), isFalse);
      expect(spacious(760, 511), isFalse);
      for (final width in [
        680.0,
        749.0,
        750.0,
        900.0,
        1119.0,
        1120.0,
        1600.0,
      ]) {
        for (final textScale in [1.0, 1.3, 1.5, 2.0]) {
          // Once the controls are spacious, a taller window keeps them so,
          // as long as the tools stay where they are: when they move from
          // above the sheet to beside it, the count starts again.
          var seen = false;
          bool? above;
          for (var height = 300.0; height <= 1400; height += 4) {
            final aboveNow = StudioLayout.toolsAbove(
              width: width,
              height: height,
              textScale: textScale,
            );
            if (above != null && above != aboveNow) seen = false;
            above = aboveNow;
            final now = spacious(width, height, textScale: textScale);
            expect(
              !seen || now,
              isTrue,
              reason: 'spacious lost at $width × $height, text $textScale',
            );
            seen = seen || now;
          }
          expect(seen, isTrue, reason: '$width, text $textScale');
        }
        // Larger text never makes room.
        for (var height = 300.0; height <= 1400; height += 20) {
          if (!spacious(width, height)) {
            expect(spacious(width, height, textScale: 1.5), isFalse);
            expect(spacious(width, height, textScale: 2), isFalse);
          }
        }
      }
      // Text smaller than the reference is counted as the reference.
      expect(spacious(1280, 802, textScale: .8), isTrue);
      expect(spacious(1280, 801, textScale: .8), isFalse);
    },
  );

  test('the estimate of the spacious controls grows as the column narrows', () {
    expect(StudioLayout.spaciousControlsHeight(900, 1), 290);
    expect(StudioLayout.spaciousControlsHeight(640, 1), 290);
    expect(StudioLayout.spaciousControlsHeight(600, 1), 345);
    expect(StudioLayout.spaciousControlsHeight(520, 1), 400);
    var previous = 0.0;
    for (var width = 1400.0; width >= 300; width -= 10) {
      final height = StudioLayout.spaciousControlsHeight(width, 1);
      expect(height, greaterThanOrEqualTo(previous));
      expect(
        StudioLayout.spaciousControlsHeight(width, 1.5),
        greaterThan(height),
      );
      previous = height;
    }
    expect(StudioLayout.documentToolbarHeight(1), 48);
    expect(StudioLayout.documentToolbarHeight(2), 88);
  });

  test('the floor of the sheet is a share of the room, within bounds', () {
    expect(StudioLayout.sheetFloor(0), 0);
    expect(StudioLayout.sheetFloor(60), 60);
    expect(StudioLayout.sheetFloor(96), 96);
    expect(StudioLayout.sheetFloor(200), 96);
    expect(StudioLayout.sheetFloor(500), 150);
    expect(StudioLayout.sheetFloor(2000), 240);
    var previous = 0.0;
    for (var room = 0.0; room <= 1500; room += 7) {
      final floor = StudioLayout.sheetFloor(room);
      expect(floor, lessThanOrEqualTo(room));
      expect(floor, greaterThanOrEqualTo(previous));
      previous = floor;
    }
  });

  testWidgets('the width announced for the column of tools is its width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 1100);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final textScale in [1.0, 1.5, 2.0]) {
      for (var height = 200.0; height <= 1000; height += 37) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  height: height,
                  child: StudioToolBar(
                    selected: StudioTool.brush,
                    onSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getSize(find.byType(StudioToolBar)).width,
          StudioToolBar.widthFor(height, textScale),
          reason: 'height $height, text $textScale',
        );
        expect(tester.takeException(), isNull);
      }
    }
    // One column of tools, or two: nothing else.
    expect(StudioToolBar.widthFor(1000, 1), 98);
    expect(StudioToolBar.widthFor(700, 1), 98);
    expect(StudioToolBar.widthFor(500, 1), 180);
  });

  // Every tool, with an element chosen for « Choisir »: a text, whose
  // actions are the most numerous.
  Future<void> everyTool(
    StudioDriver studio,
    void Function(StudioTool tool) check,
  ) async {
    final tester = studio.tester;
    for (final tool in StudioTool.values) {
      await studio.tap(tool.keyName);
      if (tool == StudioTool.select) {
        await studio.click();
        expect(find.byKey(const Key('editSelectionText')), findsOneWidget);
      }
      expect(tester.takeException(), isNull, reason: tool.name);
      check(tool);
    }
  }

  for (final textScale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'the sheet keeps its place in every window and with every tool, text × $textScale',
      (tester) async {
        await _loadInterfaceFont(tester);
        final studio = StudioDriver(tester, gallery: MemoryGallery());
        await studio.start(size: const Size(1280, 900), textScale: textScale);
        // One text in the middle of the sheet, to be chosen later.
        await studio.addText('Mot');
        const widths = [680.0, 749.0, 750.0, 760.0, 900.0, 1119.0, 1120.0];
        const heights = [520.0, 580.0, 640.0, 700.0, 760.0, 820.0, 900.0];
        for (final width in [...widths, 1280.0, 1440.0]) {
          for (final height in heights) {
            tester.view.physicalSize = Size(width, height);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$width × $height');
            await everyTool(studio, (tool) {
              final where = '${tool.name} at $width × $height';
              final sheet = tester.getRect(
                find.byKey(const Key('drawingSurface')),
              );
              final region = tester.getRect(
                find.byKey(const Key('drawingControlsScroll')),
              );
              final controls = tester.getSize(
                find.byKey(const Key('drawingControls')),
              );
              // A sheet to draw in, entirely in the window, never under the
              // controls.
              expect(sheet.height, greaterThanOrEqualTo(96), reason: where);
              expect(sheet.width, greaterThanOrEqualTo(300), reason: where);
              expect(sheet.top, greaterThanOrEqualTo(0), reason: where);
              expect(
                sheet.bottom,
                lessThanOrEqualTo(region.top),
                reason: where,
              );
              expect(region.bottom, lessThanOrEqualTo(height), reason: where);
              expect(region.right, lessThanOrEqualTo(width), reason: where);
              // The controls are whole, or they scroll: never cut off.
              expect(
                controls.height <= region.height + .5 ||
                    tester
                            .state<ScrollableState>(
                              find
                                  .descendant(
                                    of: find.byKey(
                                      const Key('drawingControlsScroll'),
                                    ),
                                    matching: find.byType(Scrollable),
                                  )
                                  .first,
                            )
                            .position
                            .maxScrollExtent >
                        0,
                isTrue,
                reason: where,
              );
              if (textScale == 1) {
                // At the ordinary size of text nothing needs scrolling, and
                // the sheet is more than a strip.
                expect(
                  controls.height,
                  lessThanOrEqualTo(region.height + .5),
                  reason: where,
                );
                expect(sheet.height, greaterThanOrEqualTo(100), reason: where);
              }
            });
          }
        }
        expect(tester.takeException(), isNull);
        await studio.finish();
      },
      skip: !available,
    );
  }

  testWidgets('a window a little wider than narrow no longer loses its sheet', (
    tester,
  ) async {
    await _loadInterfaceFont(tester);
    final studio = StudioDriver(tester, gallery: MemoryGallery());
    // Tools beside the sheet in two columns, the palette on two lines: the
    // spacious controls alone would fill this window.
    await studio.start(size: const Size(760, 580));
    final sheet = tester.getSize(find.byKey(const Key('drawingSurface')));
    expect(sheet.height, greaterThanOrEqualTo(150));
    // The compact controls: no line of recent colours.
    expect(find.text('RÉCENTES'), findsNothing);
    // The sheet can be drawn on.
    await studio.tap('tool-stroke');
    await studio.drag(studio.at(300, 300), studio.at(700, 500));
    studio.expectCount(1);
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);

  testWidgets(
    'a taller window never gets a lower sheet than the smallest one',
    (tester) async {
      await _loadInterfaceFont(tester);
      final studio = StudioDriver(tester, gallery: MemoryGallery());
      await studio.start(size: const Size(1280, 520));
      final smallest = tester
          .getSize(find.byKey(const Key('drawingSurface')))
          .height;
      var spaciousSeen = false;
      for (var height = 540.0; height <= 1000; height += 20) {
        tester.view.physicalSize = Size(1280, height);
        await tester.pumpAndSettle();
        final sheet = tester
            .getSize(find.byKey(const Key('drawingSurface')))
            .height;
        expect(sheet, greaterThanOrEqualTo(smallest), reason: '$height');
        final spaciousNow = find.text('RÉCENTES').evaluate().isNotEmpty;
        // Spacious controls, once there, stay as the window grows.
        expect(!spaciousSeen || spaciousNow, isTrue, reason: '$height');
        spaciousSeen = spaciousSeen || spaciousNow;
      }
      expect(spaciousSeen, isTrue);
      expect(tester.takeException(), isNull);
      await studio.finish();
    },
    skip: !available,
  );

  testWidgets('the mascot of the side panel is shown whole, or not at all', (
    tester,
  ) async {
    await _loadInterfaceFont(tester);
    final studio = StudioDriver(tester, gallery: MemoryGallery());
    await studio.start(size: const Size(1280, 720));
    final mascot = find.byKey(const Key('inspectorMascot'));
    var shown = 0;
    var hidden = 0;
    for (final textScale in [1.0, 1.3, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      for (var height = 600.0; height <= 2000; height += 40) {
        tester.view.physicalSize = Size(1280, height);
        await tester.pumpAndSettle();
        for (final tool in StudioTool.values) {
          await studio.tap(tool.keyName);
          final where = '${tool.name} at 1280 × $height, text × $textScale';
          final size = tester.getSize(mascot);
          if (size == Size.zero) {
            hidden++;
            continue;
          }
          shown++;
          // Its full size, entirely above the bottom of the window.
          expect(size, const Size.square(104), reason: where);
          expect(
            tester.getRect(mascot).bottom,
            lessThanOrEqualTo(height),
            reason: where,
          );
        }
      }
      // A window tall enough always shows it.
      tester.view.physicalSize = const Size(1280, 2600);
      await tester.pumpAndSettle();
      expect(tester.getSize(mascot), const Size.square(104));
    }
    // The usual laptop window leaves it out rather than cut it in two; a
    // taller one has room for it.
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pumpAndSettle();
    expect(tester.getSize(mascot), Size.zero);
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();
    expect(tester.getSize(mascot), const Size.square(104));
    expect(shown, greaterThan(50));
    expect(hidden, greaterThan(50));
    expect(tester.takeException(), isNull);
    await studio.finish();
  }, skip: !available);
}
