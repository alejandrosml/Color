// SPDX-License-Identifier: MIT
// The tool bar alone, at the sizes of real windows: every tool must stay in
// view and keep a comfortable target, whatever the room.
import 'package:edupaint_flutter_study/studio_tool.dart';
import 'package:edupaint_flutter_study/tool_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<StudioTool?> pump(
    WidgetTester tester, {
    required Size size,
    bool horizontal = false,
    double textScale = 1,
    StudioTool selected = StudioTool.brush,
    bool enabled = true,
  }) async {
    StudioTool? chosen;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, update) => horizontal
                  ? StudioToolBar(
                      selected: selected,
                      horizontal: true,
                      onSelected: enabled
                          ? (tool) => update(() => chosen = selected = tool)
                          : null,
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StudioToolBar(
                          selected: selected,
                          onSelected: enabled
                              ? (tool) => update(() => chosen = selected = tool)
                              : null,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Returned through a closure: the caller reads it after its taps.
    return chosen;
  }

  Rect rect(WidgetTester tester, StudioTool tool) =>
      tester.getRect(find.byKey(Key(tool.keyName)));

  // Every button lies whole inside the window and overlaps no other.
  void expectAllInView(WidgetTester tester, Size window) {
    final rects = [for (final tool in StudioTool.values) rect(tester, tool)];
    for (final (index, box) in rects.indexed) {
      final tool = StudioTool.values[index];
      expect(box.left, greaterThanOrEqualTo(0), reason: tool.name);
      expect(box.top, greaterThanOrEqualTo(0), reason: tool.name);
      // Shared widths are divisions: allow their last binary digit.
      expect(
        box.right,
        lessThanOrEqualTo(window.width + .001),
        reason: tool.name,
      );
      expect(
        box.bottom,
        lessThanOrEqualTo(window.height + .001),
        reason: tool.name,
      );
      expect(box.width, greaterThanOrEqualTo(48), reason: tool.name);
      expect(box.height, greaterThanOrEqualTo(44), reason: tool.name);
      for (final other in rects.skip(index + 1)) {
        expect(box.deflate(.001).overlaps(other), isFalse, reason: tool.name);
      }
    }
  }

  testWidgets('a tall window keeps one column of large buttons', (
    tester,
  ) async {
    const window = Size(400, 900);
    await pump(tester, size: window);
    expectAllInView(tester, window);
    final columns = {
      for (final tool in StudioTool.values) rect(tester, tool).left,
    };
    expect(columns, hasLength(1));
    expect(rect(tester, StudioTool.brush).height, 80);
    expect(rect(tester, StudioTool.brush).width, 76);
    expect(find.text('OUTILS'), findsOneWidget);
    // In the order of the number keys, top to bottom.
    final tops = [for (final tool in StudioTool.values) rect(tester, tool).top];
    expect(tops, [...tops]..sort());
  });

  testWidgets('a shorter window tightens the column before splitting it', (
    tester,
  ) async {
    // Room for nine buttons of 60 to 80 units, not for nine of 80.
    const window = Size(400, 700);
    await pump(tester, size: window);
    expectAllInView(tester, window);
    expect({
      for (final tool in StudioTool.values) rect(tester, tool).left,
    }, hasLength(1));
    final height = rect(tester, StudioTool.brush).height;
    expect(height, greaterThanOrEqualTo(60));
    expect(height, lessThan(80));
  });

  for (final height in [640.0, 560.0, 440.0]) {
    testWidgets('at a height of $height two columns keep every tool in view', (
      tester,
    ) async {
      final window = Size(400, height);
      await pump(tester, size: window);
      expectAllInView(tester, window);
      final columns = {
        for (final tool in StudioTool.values) rect(tester, tool).left,
      };
      expect(columns, hasLength(2));
      // Reading order: left then right, row after row.
      expect(
        rect(tester, StudioTool.brush).top,
        rect(tester, StudioTool.line).top,
      );
      expect(
        rect(tester, StudioTool.brush).left,
        lessThan(rect(tester, StudioTool.line).left),
      );
      expect(
        rect(tester, StudioTool.rectangle).top,
        greaterThan(rect(tester, StudioTool.brush).top),
      );
      expect(
        rect(tester, StudioTool.select).left,
        rect(tester, StudioTool.brush).left,
      );
      expect(rect(tester, StudioTool.brush).height, greaterThanOrEqualTo(60));
    });
  }

  testWidgets('a very short window scrolls instead of shrinking the buttons', (
    tester,
  ) async {
    await pump(tester, size: const Size(400, 300));
    expect(rect(tester, StudioTool.brush).height, greaterThanOrEqualTo(60));
    final last = find.byKey(Key(StudioTool.select.keyName));
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('enlarged text keeps the names on one line in the column', (
    tester,
  ) async {
    const window = Size(400, 900);
    await pump(tester, size: window, textScale: 2);
    expectAllInView(tester, window);
    for (final tool in StudioTool.values) {
      final name = find.descendant(
        of: find.byKey(Key(tool.keyName)),
        matching: find.text(tool.label),
      );
      expect(name, findsOneWidget);
      // One line: never taller than twice the enlarged letters.
      expect(tester.getSize(name).height, lessThan(30), reason: tool.name);
    }
  });

  testWidgets('the row shows names when they fit', (tester) async {
    const window = Size(1000, 200);
    await pump(tester, size: window, horizontal: true);
    expectAllInView(tester, window);
    for (final tool in StudioTool.values) {
      expect(find.text(tool.label), findsOneWidget);
    }
    expect(find.byKey(const Key('toolsScroll')), findsNothing);
  });

  for (final width in [740.0, 656.0, 500.0]) {
    testWidgets('at a width of $width the row keeps every picture in view', (
      tester,
    ) async {
      final window = Size(width, 200);
      await pump(tester, size: window, horizontal: true);
      expectAllInView(tester, window);
      expect(find.byKey(const Key('toolsScroll')), findsNothing);
      // The names are no longer written, and are still announced.
      final handle = tester.ensureSemantics();
      for (final tool in StudioTool.values) {
        expect(find.text(tool.label), findsNothing);
        expect(
          tester.getSemantics(find.byKey(Key(tool.keyName))).label,
          tool.label,
        );
        expect(find.byTooltip(tool.label), findsOneWidget);
      }
      handle.dispose();
    });
  }

  testWidgets('only a very narrow row scrolls, with full-size buttons', (
    tester,
  ) async {
    await pump(tester, size: const Size(360, 200), horizontal: true);
    expect(find.byKey(const Key('toolsScroll')), findsOneWidget);
    expect(rect(tester, StudioTool.brush).width, 48);
    final last = find.byKey(Key(StudioTool.select.keyName));
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    expect(tester.getRect(last).right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing reports the tool and a busy studio disables the bar', (
    tester,
  ) async {
    StudioTool? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudioToolBar(
            selected: StudioTool.brush,
            horizontal: true,
            onSelected: (tool) => chosen = tool,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('tool-eraser')));
    expect(chosen, StudioTool.eraser);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StudioToolBar(
            selected: StudioTool.brush,
            horizontal: true,
            onSelected: null,
          ),
        ),
      ),
    );
    for (final tool in StudioTool.values) {
      expect(
        tester.widget<OutlinedButton>(find.byKey(Key(tool.keyName))).onPressed,
        isNull,
      );
    }
  });
}
