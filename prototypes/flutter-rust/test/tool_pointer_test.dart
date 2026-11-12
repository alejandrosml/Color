// SPDX-License-Identifier: MIT
// « La pointe » (Color 1.2): the pointer of each tool, painted by the
// interface from the pictures of the core. The tool acts at the end of the
// tip, at the top left; the tip has the chosen colour, white for the
// eraser; « Choisir » keeps its yellow arrow.
//
// With COLOR_POINTER_SHEET=<folder>, the sheet of the pointers is written
// there as pointeurs.png, to be looked at.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/studio_tool.dart';
import 'package:edupaint_flutter_study/tool_pointer.dart';
import 'package:edupaint_flutter_study/vector_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pixels of [pointer] painted so that it acts at (20, 20) of an image
/// of 100 × 100, transparent where it paints nothing.
Future<ByteData> _painted(WidgetTester tester, ToolPointer pointer) async {
  final recorder = ui.PictureRecorder();
  pointer.paint(Canvas(recorder), const Offset(20, 20));
  final picture = recorder.endRecording();
  final bytes = await tester.runAsync(() async {
    final image = await picture.toImage(100, 100);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!;
  });
  picture.dispose();
  return bytes!;
}

/// 0xAARRGGBB of the pixel at ([x], [y]) of the grid of the pointer.
int _at(ByteData bytes, double x, double y) {
  // The acting point (3, 3) of the grid is at (20, 20) of the image.
  final offset = ((y + 17).round() * 100 + (x + 17).round()) * 4;
  return bytes.getUint8(offset + 3) << 24 |
      bytes.getUint8(offset) << 16 |
      bytes.getUint8(offset + 1) << 8 |
      bytes.getUint8(offset + 2);
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  const poppy = 0xd75e56;

  // A point well inside the coloured tip of each drawing, away from its
  // outline and from its glint.
  (double, double) inTip(StudioTool tool) => switch (tool) {
    StudioTool.brush => (13, 17),
    StudioTool.fill => (19, 23),
    StudioTool.select => (8, 22),
    _ => (12, 14),
  };

  testWidgets('every tool has its pointer, its tip in the chosen colour', (
    tester,
  ) async {
    expect(VectorArtCatalog.instance, isNotNull);
    for (final tool in StudioTool.values) {
      final bytes = await _painted(tester, ToolPointer(tool, poppy));
      final (x, y) = inTip(tool);
      final expected = switch (tool) {
        StudioTool.eraser => 0xffffffff,
        StudioTool.select => 0xffffcd62,
        _ => 0xff000000 | poppy,
      };
      expect(
        _at(bytes, x, y).toRadixString(16),
        expected.toRadixString(16),
        reason: '$tool',
      );
      // The pointer lies under and right of the point where it acts:
      // nothing is painted up and left of it, and its tip is there.
      expect(_at(bytes, -3, -3) >>> 24, 0, reason: '$tool');
      expect(_at(bytes, 4.5, 4.5) >>> 24, 0xff, reason: '$tool');
      // The tool is drawn behind the tip: something far from it too.
      var far = 0;
      for (var gy = 30.0; gy < 62; gy += 2) {
        for (var gx = 30.0; gx < 62; gx += 2) {
          if (_at(bytes, gx, gy) >>> 24 != 0) far++;
        }
      }
      if (tool != StudioTool.select) {
        expect(far, greaterThan(20), reason: '$tool');
      }
    }
  }, skip: !available);

  testWidgets('another colour changes the tip and nothing else', (
    tester,
  ) async {
    for (final tool in [StudioTool.brush, StudioTool.fill, StudioTool.text]) {
      final red = await _painted(tester, ToolPointer(tool, poppy));
      final blue = await _painted(tester, ToolPointer(tool, 0x477fb2));
      final (x, y) = inTip(tool);
      expect(_at(blue, x, y), 0xff477fb2, reason: '$tool');
      // The outline of the tip keeps its ink, the tool its colours.
      var same = 0, changed = 0;
      for (var offset = 0; offset < red.lengthInBytes; offset += 4) {
        if (red.getUint32(offset) == blue.getUint32(offset)) {
          if (red.getUint8(offset + 3) != 0) same++;
        } else {
          changed++;
        }
      }
      expect(changed, greaterThan(40), reason: '$tool');
      expect(same, greaterThan(changed), reason: '$tool');
    }
    // The paints of a picture are its own: the colour given once is not
    // kept for the next pointer.
    final again = await _painted(tester, ToolPointer(StudioTool.brush, poppy));
    final (x, y) = inTip(StudioTool.brush);
    expect(_at(again, x, y), 0xff000000 | poppy);
  }, skip: !available);

  testWidgets('the pictures of the tool bar keep their colours', (
    tester,
  ) async {
    // A tint is given for the time of one painting only.
    final catalog = VectorArtCatalog.instance!;
    final tip = catalog['pointeur-pointe']!;
    Future<int> middle(Map<String, Color> tints) async {
      final recorder = ui.PictureRecorder();
      tip.paint(
        Canvas(recorder),
        const Rect.fromLTWH(0, 0, 64, 64),
        tints: tints,
      );
      final picture = recorder.endRecording();
      final value = await tester.runAsync(() async {
        final image = await picture.toImage(64, 64);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.getUint32((14 * 64 + 12) * 4);
      });
      picture.dispose();
      return value!;
    }

    final own = await middle(const {});
    expect(own, 0xed8c88ff);
    expect(await middle(const {'couleur': Color(0xff4db266)}), 0x4db266ff);
    expect(await middle(const {}), own);
    expect(await middle(const {'autre': Color(0xff4db266)}), own);
  }, skip: !available);

  testWidgets('without the pictures of the core a plain tip is painted', (
    tester,
  ) async {
    VectorArtCatalog.debugUse(null);
    addTearDown(VectorArtCatalog.debugForget);
    for (final tool in [
      StudioTool.brush,
      StudioTool.eraser,
      StudioTool.select,
    ]) {
      final bytes = await _painted(tester, ToolPointer(tool, poppy));
      expect(_at(bytes, 12, 14), switch (tool) {
        StudioTool.eraser => 0xffffffff,
        StudioTool.select => 0xffffcd62,
        _ => 0xff000000 | poppy,
      }, reason: '$tool');
      expect(_at(bytes, -3, -3) >>> 24, 0, reason: '$tool');
    }
  });

  test('a pointer is its tool and its colour', () {
    expect(
      const ToolPointer(StudioTool.brush, poppy),
      const ToolPointer(StudioTool.brush, poppy),
    );
    expect(
      const ToolPointer(StudioTool.brush, poppy),
      isNot(const ToolPointer(StudioTool.fill, poppy)),
    );
    expect(
      const ToolPointer(StudioTool.brush, poppy),
      isNot(const ToolPointer(StudioTool.brush, 0x477fb2)),
    );
    expect(toolPointerTip, const Offset(3, 3));
  });

  testWidgets('the sheet of the pointers', (tester) async {
    final folder = Platform.environment['COLOR_POINTER_SHEET']!;
    const colours = [poppy, 0xeebf4e, 0x477fb2, 0x4db266, 0x263f43];
    const cell = 96.0;
    final tools = StudioTool.values;
    final size = Size(cell * tools.length, cell * (colours.length + 1));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(2);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    // The last row on a dark drawing: the white edge of the tip shows.
    canvas.drawRect(
      Rect.fromLTWH(0, cell * colours.length, size.width, cell),
      Paint()..color = const Color(0xff263f43),
    );
    for (final (column, tool) in tools.indexed) {
      for (var row = 0; row <= colours.length; row++) {
        final rgb = colours[row % colours.length];
        ToolPointer(
          tool,
          rgb,
        ).paint(canvas, Offset(column * cell + 16, row * cell + 16));
      }
    }
    final picture = recorder.endRecording();
    final png = await tester.runAsync(() async {
      final image = await picture.toImage(
        size.width.round() * 2,
        size.height.round() * 2,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    picture.dispose();
    File('$folder/pointeurs.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!);
  }, skip: !available || Platform.environment['COLOR_POINTER_SHEET'] == null);
}
