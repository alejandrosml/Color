// SPDX-License-Identifier: MIT
// The layer over the sheet (Color 1.2), painted alone: the previews of
// what a tool would do — a dot, a ring, the round of the eraser, the stroke
// of a text, the hatching of the paint pot — on the sheet only, and the
// pointer of the tool over them.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/sheet_hint.dart';
import 'package:edupaint_flutter_study/studio_tool.dart';
import 'package:edupaint_flutter_study/tool_pointer.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Size(500, 300);

// A sheet of 400 × 300 units in a frame of 500 × 300 pixels: one pixel a
// unit, the sheet from x = 50 to x = 450.
final _viewport = DocumentViewport(
  viewWidth: _frame.width,
  viewHeight: _frame.height,
  documentWidth: 400,
  documentHeight: 300,
  padding: 0,
);

Future<ByteData> _painted(WidgetTester tester, SheetHint hint) async {
  final recorder = ui.PictureRecorder();
  SheetHintPainter(
    viewport: _viewport,
    hint: hint,
  ).paint(Canvas(recorder), _frame);
  final picture = recorder.endRecording();
  final bytes = await tester.runAsync(() async {
    final image = await picture.toImage(
      _frame.width.round(),
      _frame.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!;
  });
  picture.dispose();
  return bytes!;
}

/// 0xAARRGGBB of a pixel of the frame, colours not multiplied by alpha.
int _at(ByteData bytes, num x, num y) {
  final offset = (y.round() * _frame.width.round() + x.round()) * 4;
  final alpha = bytes.getUint8(offset + 3);
  int channel(int at) {
    final value = bytes.getUint8(offset + at);
    return alpha == 0 ? 0 : (value * 255 / alpha).round().clamp(0, 255);
  }

  return alpha << 24 | channel(0) << 16 | channel(1) << 8 | channel(2);
}

int _alpha(ByteData bytes, num x, num y) => _at(bytes, x, y) >>> 24;

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;
  const sun = 0xeebf4e;

  test('the sheet is where the test says', () {
    expect(_viewport.scale, 1);
    expect(_viewport.left, 50);
    expect(_viewport.top, 0);
  });

  testWidgets('nothing is painted while there is nothing to show', (
    tester,
  ) async {
    final bytes = await _painted(tester, SheetHint());
    for (var offset = 3; offset < bytes.lengthInBytes; offset += 4) {
      expect(bytes.getUint8(offset), 0);
    }
  });

  testWidgets('a dot of the width and the colour of the trait', (tester) async {
    final hint = SheetHint()
      ..preview = const DotPreview(at: Offset(200, 150), width: 30, rgb: sun);
    var bytes = await _painted(tester, hint);
    expect(_at(bytes, 200, 150), 0xff000000 | sun);
    expect(_at(bytes, 212, 150), 0xff000000 | sun);
    expect(_at(bytes, 200, 138), 0xff000000 | sun);
    // A thin ring around it, then nothing.
    expect(_alpha(bytes, 200 + 16, 150), greaterThan(0));
    expect(_alpha(bytes, 200 + 21, 150), 0);
    expect(_alpha(bytes, 200, 150 - 21), 0);

    // A tool with colours of its own shows its size only.
    hint.preview = const DotPreview(
      at: Offset(200, 150),
      width: 30,
      rgb: sun,
      hollow: true,
    );
    bytes = await _painted(tester, hint);
    expect(_alpha(bytes, 200, 150), 0);
    expect(_alpha(bytes, 200 + 16, 150), greaterThan(0));

    // The mirror draws twice: the same dot in the mirror of the middle of
    // the sheet, which is at x = 250.
    hint.preview = const DotPreview(
      at: Offset(200, 150),
      width: 30,
      rgb: sun,
      mirrored: true,
    );
    bytes = await _painted(tester, hint);
    expect(_at(bytes, 200, 150), 0xff000000 | sun);
    expect(_at(bytes, 300, 150), 0xff000000 | sun);
    expect(_alpha(bytes, 250, 150), 0);

    // The marker ends square and shows through.
    hint.preview = const DotPreview(
      at: Offset(200, 150),
      width: 30,
      rgb: sun,
      square: true,
      opacity: .85,
    );
    bytes = await _painted(tester, hint);
    expect(_alpha(bytes, 213, 163), inInclusiveRange(214, 219));
  });

  testWidgets('what is shown stops at the edge of the sheet', (tester) async {
    // A large dot astride the left edge of the sheet, at x = 50.
    final hint = SheetHint()
      ..preview = const DotPreview(at: Offset(55, 150), width: 60, rgb: sun);
    final bytes = await _painted(tester, hint);
    expect(_at(bytes, 60, 150), 0xff000000 | sun);
    expect(_alpha(bytes, 45, 150), 0);
    expect(_alpha(bytes, 30, 150), 0);
  });

  testWidgets('the round of the eraser, beside the sheet too', (tester) async {
    final hint = SheetHint()
      ..preview = const EraserPreview(at: Offset(200, 150), radius: 10);
    var bytes = await _painted(tester, hint);
    // A veil inside, a ring of ink on white at its reach, nothing beyond.
    expect(_alpha(bytes, 200, 150), inInclusiveRange(70, 110));
    // Ink on white: opaque and dark, whatever the edge of a pixel makes.
    bool inked(int pixel) =>
        pixel >>> 24 == 0xff && (pixel >> 16) & 0xff < 0x90;
    expect(inked(_at(bytes, 210, 150)), isTrue);
    expect(inked(_at(bytes, 200, 160)), isTrue);
    expect(_alpha(bytes, 215, 150), 0);
    // A rub may begin beside the sheet: its round is shown there.
    hint.preview = const EraserPreview(at: Offset(20, 150), radius: 10);
    bytes = await _painted(tester, hint);
    expect(inked(_at(bytes, 30, 150)), isTrue);
    expect(inked(_at(bytes, 20, 140)), isTrue);
  });

  testWidgets('the stroke of a text, of the height of its line', (
    tester,
  ) async {
    final hint = SheetHint()
      ..preview = const CaretPreview(
        top: DocumentPoint(100, 50),
        height: 80,
        rgb: sun,
      );
    final bytes = await _painted(tester, hint);
    // The sheet starts at x = 50: the stroke is at x = 150.
    expect(_at(bytes, 150, 60), 0xff000000 | sun);
    expect(_at(bytes, 150, 125), 0xff000000 | sun);
    expect(_alpha(bytes, 150, 140), 0);
    expect(_alpha(bytes, 150, 40), 0);
    expect(_alpha(bytes, 160, 90), 0);
  });

  testWidgets('the pot hatches the zone, and only the zone', (tester) async {
    final zone = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(const Rect.fromLTWH(100, 50, 200, 150))
      // A hole in it.
      ..addRect(const Rect.fromLTWH(180, 100, 40, 40));
    final hint = SheetHint()..preview = PourPreview.zone(zone, rgb: sun);
    final bytes = await _painted(tester, hint);
    // On the screen the zone goes from x = 150 to 350, y = 50 to 200.
    expect(_alpha(bytes, 140, 100), 0);
    expect(_alpha(bytes, 360, 100), 0);
    expect(_alpha(bytes, 250, 40), 0);
    expect(_alpha(bytes, 250, 210), 0);
    // Nothing in the hole.
    expect(_alpha(bytes, 250, 120), 0);
    // Bands of the colour and of a white veil, one after the other along a
    // line: both are met, each several times.
    var colour = 0, veil = 0, changes = 0;
    bool? last;
    for (var x = 155; x < 345; x++) {
      final pixel = _at(bytes, x, 70);
      final isColour = pixel == (0xff000000 | sun);
      final isVeil =
          pixel & 0xffffff == 0xffffff &&
          (pixel >>> 24) > 120 &&
          (pixel >>> 24) < 160;
      if (isColour) colour++;
      if (isVeil) veil++;
      if (isColour || isVeil) {
        if (last != null && last != isColour) changes++;
        last = isColour;
      }
    }
    expect(colour, greaterThan(60));
    expect(veil, greaterThan(60));
    // A band every seven pixels across, ten along a level line.
    expect(changes, inInclusiveRange(16, 22));

    // A very light colour is hatched with a veil of ink: white on white
    // would show nothing.
    hint.preview = PourPreview.zone(zone, rgb: 0xffffff);
    final light = await _painted(tester, hint);
    var dark = 0;
    for (var x = 155; x < 345; x++) {
      final pixel = _at(light, x, 70);
      if (pixel & 0xffffff != 0xffffff) dark++;
    }
    expect(dark, greaterThan(60));
  });

  testWidgets('on the paper the hatching leaves out what is drawn', (
    tester,
  ) async {
    // The drawing: a square of ink in the middle of the sheet.
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(150, 100, 100, 100),
      Paint()..color = Colors.black,
    );
    final drawing = recorder.endRecording();
    final ink = (await tester.runAsync(() => drawing.toImage(400, 300)))!;
    drawing.dispose();
    addTearDown(ink.dispose);
    final hint = SheetHint()..preview = PourPreview.sheet(rgb: sun, ink: ink);
    var bytes = await _painted(tester, hint);
    // The sheet is hatched from edge to edge…
    var painted = 0;
    for (var x = 55; x < 445; x += 3) {
      if (_alpha(bytes, x, 20) > 0) painted++;
    }
    expect(painted, 130);
    // … but for the square, at x = 200 to 300 on the screen…
    for (var x = 205; x < 295; x += 5) {
      expect(_alpha(bytes, x, 150), 0, reason: 'x = $x');
    }
    // … and nothing beside the sheet.
    expect(_alpha(bytes, 40, 150), 0);
    expect(_alpha(bytes, 460, 150), 0);

    // Without a drawing the whole sheet is hatched.
    hint.preview = const PourPreview.sheet(rgb: sun);
    bytes = await _painted(tester, hint);
    expect(_alpha(bytes, 250, 150), greaterThan(0));
  });

  testWidgets('an element is hatched: its inside, or itself', (tester) async {
    // A hollow rectangle: the pot would fill its inside.
    final frame = RenderedElement(
      StrokeData(
        const [DocumentPoint(100, 50), DocumentPoint(300, 200)],
        0x263f43,
        6,
        kind: VectorKind.rectangle,
      ),
    );
    final hint = SheetHint()
      ..preview = PourPreview.element(frame, inside: true, rgb: sun);
    var bytes = await _painted(tester, hint);
    var inside = 0;
    for (var x = 160; x < 340; x += 2) {
      if (_alpha(bytes, x, 125) > 0) inside++;
    }
    expect(inside, 90);
    expect(_alpha(bytes, 140, 125), 0);

    // What lies over it stays as it is: a square painted after the
    // rectangle, in the middle of it, is left out of the hatching.
    final square = RenderedElement(
      StrokeData(
        const [DocumentPoint(180, 100), DocumentPoint(220, 150)],
        0x263f43,
        2,
        kind: VectorKind.rectangle,
        fillRgb: 0xffffff,
      ),
    );
    hint.preview = PourPreview.element(
      frame,
      inside: true,
      rgb: sun,
      over: [square],
    );
    bytes = await _painted(tester, hint);
    for (var x = 232; x < 268; x += 3) {
      expect(_alpha(bytes, x, 125), 0, reason: 'x = $x');
    }
    var around = 0;
    for (var x = 160; x < 225; x += 2) {
      if (_alpha(bytes, x, 125) > 0) around++;
    }
    expect(around, greaterThan(28));

    // A trait takes the colour itself: the hatching follows the trait.
    final trait = RenderedElement(
      StrokeData(
        const [DocumentPoint(100, 100), DocumentPoint(300, 100)],
        0x263f43,
        20,
      ),
    );
    hint.preview = PourPreview.element(trait, inside: false, rgb: sun);
    bytes = await _painted(tester, hint);
    expect(_alpha(bytes, 250, 100), greaterThan(0));
    expect(_alpha(bytes, 250, 95), greaterThan(0));
    expect(_alpha(bytes, 250, 115), 0);
    expect(_alpha(bytes, 250, 85), 0);
    final preview = hint.preview as PourPreview;
    expect(preview.covers(const DocumentPoint(200, 100)), isTrue);
    expect(preview.covers(const DocumentPoint(200, 200)), isFalse);
  }, skip: !available);

  testWidgets('the pointers are painted over the preview, where they act', (
    tester,
  ) async {
    final hint = SheetHint()
      ..pointer = const ToolPointer(StudioTool.line, 0xd75e56)
      ..mouseAt = const Offset(200, 150)
      ..keyAt = const Offset(320, 80)
      ..preview = const DotPreview(at: Offset(200, 150), width: 60, rgb: sun);
    var bytes = await _painted(tester, hint);
    // The tip, in its colour, on the dot; one for the mouse, one for the
    // pointer of the keyboard.
    expect(_at(bytes, 209, 161), 0xffd75e56);
    expect(_at(bytes, 329, 91), 0xffd75e56);
    // The dot shows around the tip.
    expect(_at(bytes, 190, 140), 0xff000000 | sun);
    // The mouse leaves: its pointer goes, the other stays.
    hint.mouseAt = null;
    bytes = await _painted(tester, hint);
    expect(_at(bytes, 209, 161), 0xff000000 | sun);
    expect(_at(bytes, 329, 91), 0xffd75e56);
    // The pointer of a mouse may lie beside the sheet, in its frame.
    hint
      ..mouseAt = const Offset(10, 10)
      ..preview = null;
    bytes = await _painted(tester, hint);
    expect(_at(bytes, 19, 21), 0xffd75e56);
  }, skip: !available);

  test('the layer listens to what changes, and to nothing else', () {
    final hint = SheetHint();
    var heard = 0;
    hint.addListener(() => heard++);
    hint.mouseAt = const Offset(1, 2);
    hint.mouseAt = const Offset(1, 2);
    expect(heard, 1);
    hint.pointer = const ToolPointer(StudioTool.brush, 1);
    hint.pointer = const ToolPointer(StudioTool.brush, 1);
    expect(heard, 2);
    hint.preview = const DotPreview(at: Offset(3, 4), width: 5, rgb: 6);
    hint.preview = const DotPreview(at: Offset(3, 4), width: 5, rgb: 6);
    expect(heard, 3);
    hint.preview = const EraserPreview(at: Offset(3, 4), radius: 10);
    hint.preview = const EraserPreview(at: Offset(3, 4), radius: 10);
    expect(heard, 4);
    hint.preview = const CaretPreview(
      top: DocumentPoint(1, 2),
      height: 3,
      rgb: 4,
    );
    hint.preview = const CaretPreview(
      top: DocumentPoint(1, 2),
      height: 3,
      rgb: 4,
    );
    expect(heard, 5);
    hint.keyAt = const Offset(9, 9);
    hint.keyAt = null;
    hint.preview = null;
    hint.preview = null;
    expect(heard, 8);
    hint.dispose();
  });
}
