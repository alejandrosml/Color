// SPDX-License-Identifier: MIT
// The dialog of the film alone, over scenes given by hand and painted by the
// real engine. Only the stamps and the film of a real document need the Rust
// library.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/document_renderer.dart';
import 'package:edupaint_flutter_study/replay.dart';
import 'package:edupaint_flutter_study/replay_dialog.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_colors.dart';
import 'package:edupaint_flutter_study/studio_painters.dart';
import 'package:edupaint_flutter_study/viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _sheetKey = Key('replaySheet');

/// The colour of a sheet that a white zone does not melt into.
const _cream = 0xfff4d6;

/// What the callbacks of one opening of the dialog have seen.
class _Seen {
  int started = 0;
  int finished = 0;
  int closed = 0;
}

/// The pixels of the sheet's box. Inside the sheet nothing is transparent:
/// the colours are those painted.
class _Shot {
  _Shot(this.size, this.width, this.height, this.rgba);

  /// The size the painters were given, of which the image is the pixels.
  final Size size;
  final int width;
  final int height;
  final Uint8List rgba;

  /// Red, green and blue of the pixel at a point of the box.
  int rgbAt(Offset point) {
    final offset = (point.dy.floor() * width + point.dx.floor()) * 4;
    return (rgba[offset] << 16) | (rgba[offset + 1] << 8) | rgba[offset + 2];
  }

  /// How many pixels differ from those of [other]: all of them, or only
  /// those whose centre is not in the rectangle [outside] of the box.
  int differences(_Shot other, {Rect? outside}) {
    if (other.width != width || other.height != height) return width * height;
    var count = 0;
    for (var offset = 0; offset < rgba.length; offset += 4) {
      if (outside != null) {
        final pixel = offset ~/ 4;
        final centre = Offset(pixel % width + .5, pixel ~/ width + .5);
        if (outside.contains(centre)) continue;
      }
      if (rgba[offset] != other.rgba[offset] ||
          rgba[offset + 1] != other.rgba[offset + 1] ||
          rgba[offset + 2] != other.rgba[offset + 2] ||
          rgba[offset + 3] != other.rgba[offset + 3]) {
        count++;
      }
    }
    return count;
  }
}

Future<_Shot> _pixelsOf(ui.Image image, Size size) async {
  try {
    final bytes = (await image.toByteData())!;
    return _Shot(
      size,
      image.width,
      image.height,
      Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
  } finally {
    image.dispose();
  }
}

/// What the dialog shows in the box of the sheet at this moment, with
/// [pixelRatio] pixels for a point of the box.
Future<_Shot> _shot(WidgetTester tester, {double pixelRatio = 1}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_sheetKey),
  );
  return (await tester.runAsync(
    () async => _pixelsOf(
      await boundary.toImage(pixelRatio: pixelRatio),
      boundary.size,
    ),
  ))!;
}

/// What [paint] paints in a box of the same size, with as many pixels.
Future<_Shot> _painted(
  WidgetTester tester,
  Size size,
  void Function(Canvas canvas, Size size) paint, {
  double pixelRatio = 1,
}) async => (await tester.runAsync(() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (pixelRatio != 1) canvas.scale(pixelRatio);
  paint(canvas, size);
  final picture = recorder.endRecording();
  try {
    return await _pixelsOf(
      await picture.toImage(
        (size.width * pixelRatio).ceil(),
        (size.height * pixelRatio).ceil(),
      ),
      size,
    );
  } finally {
    picture.dispose();
  }
}))!;

/// Where the dialog lays the sheet out in its box.
DocumentViewport _viewport(Size size, ReplayScene scene) => DocumentViewport(
  viewWidth: size.width,
  viewHeight: size.height,
  documentWidth: scene.width.toDouble(),
  documentHeight: scene.height.toDouble(),
  padding: size.shortestSide >= 160 ? 16 : 8,
);

/// The sheet as the studio paints it: by the studio's own painter, with the
/// elements in their painting order and nothing in progress.
void _paintAsStudio(
  Canvas canvas,
  Size size,
  ReplayScene scene, {
  List<RenderedElement>? strokes,
  List<int>? paintOrder,
}) {
  final byRank = List.filled(scene.elements.length, 0);
  for (final (index, rank) in scene.paintRank.indexed) {
    byRank[rank] = index;
  }
  DocumentPainter(
    viewport: _viewport(size, scene),
    paperRgb: scene.paperRgb,
    background: scene.background,
    strokes: strokes ?? scene.elements,
    paintOrder: paintOrder ?? byRank,
    draftStamp: 0,
    draft: null,
    draftPoints: const [],
    repaint: ValueNotifier(0),
    draftColor: 0,
    draftWidth: 1,
    draftKind: VectorKind.stroke,
    draftFillRgb: null,
    revision: 0,
    selectedIndex: null,
    selectionBounds: null,
    selectionOffset: ValueNotifier(Offset.zero),
  ).paint(canvas, size);
}

ReplayPlan _planOf(ReplayScene scene) => ReplayPlan(
  scene.elements,
  sheetDiagonal: math.sqrt(
    scene.width * scene.width + scene.height * scene.height,
  ),
  fixed: scene.fixedCount,
  recoloured: scene.recolouredCount,
);

/// One moment of a film by the plain way, which is what a film is: the empty
/// sheet as the studio paints it and then, from the bottom of the pile to
/// its top, every element as far as the film has redrawn it by then; a zone
/// of a page that takes its colour, as far as it has taken it. Nothing here
/// is the dialog's: neither its two pictures nor its way through the pile.
/// What the dialog shows is compared with this.
void _paintPlainly(
  Canvas canvas,
  Size size,
  ReplayScene scene,
  Duration elapsed, {
  bool overshoot = true,
}) {
  _paintAsStudio(canvas, size, scene, paintOrder: const []);
  final plan = _planOf(scene);
  final pile = List.generate(scene.elements.length, (index) => index)
    ..sort((a, b) => scene.paintRank[a].compareTo(scene.paintRank[b]));
  final sheet = _viewport(size, scene);
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  canvas.translate(sheet.left, sheet.top);
  canvas.scale(sheet.scale);
  canvas.clipRect(
    Rect.fromLTWH(0, 0, sheet.documentWidth, sheet.documentHeight),
  );
  for (final index in pile) {
    final progress = plan.progressAt(index, elapsed);
    if (scene.isRecoloured(index)) {
      scene.elements[index].paintRecolouring(
        canvas,
        progress,
        fromRgb: 0xffffff,
      );
    } else {
      scene.elements[index].paintProgress(
        canvas,
        progress,
        overshoot: overshoot,
      );
    }
  }
  canvas.restore();
}

RenderedElement _trait(
  List<DocumentPoint> points, {
  int rgb = 0x224466,
  double width = 12,
}) => RenderedElement(StrokeData(points, rgb, width));

RenderedElement _shape(
  VectorKind kind,
  double left,
  double top,
  double right,
  double bottom, {
  int rgb = 0x112233,
  double width = 6,
  int? fillRgb,
}) => RenderedElement(
  StrokeData(
    [DocumentPoint(left, top), DocumentPoint(right, bottom)],
    rgb,
    width,
    kind: kind,
    fillRgb: fillRgb,
  ),
);

RenderedElement _text(String text, double left, double top, double size) {
  final lines = text.split('\n');
  final widest = lines.map((line) => line.length).reduce(math.max);
  // With the font of the tests a letter is as wide as its size.
  return RenderedElement(
    StrokeData(
      [
        DocumentPoint(left, top),
        DocumentPoint(left + widest * size, top + lines.length * 1.2 * size),
      ],
      0x6a4f99,
      size,
      kind: VectorKind.text,
      text: text,
    ),
  );
}

ReplayScene _sceneOf(
  List<RenderedElement> elements, {
  List<int>? paintRank,
  int width = 300,
  int height = 200,
  int paperRgb = 0xfff4d6,
  ui.Image? background,
}) => ReplayScene(
  width: width,
  height: height,
  paperRgb: paperRgb,
  background: background,
  elements: elements,
  paintRank: paintRank ?? List.generate(elements.length, (index) => index),
);

/// A trait, a filled rectangle, a dot and a line: 2.39 s of film.
ReplayScene _smallScene() => _sceneOf([
  _trait(const [DocumentPoint(30, 40), DocumentPoint(270, 40)]),
  _shape(VectorKind.rectangle, 60, 80, 160, 160, fillRgb: 0x00cc44),
  _trait(const [DocumentPoint(230, 120)], rgb: 0xaa0000, width: 30),
  _shape(VectorKind.line, 200, 180, 280, 100, rgb: 0x477fb2, width: 8),
]);

/// Many elements of every kind that needs no library, all over the sheet.
List<RenderedElement> _manyElements(int count, {int seed = 11}) {
  final random = math.Random(seed);
  double x() => 15 + random.nextDouble() * 270;
  double y() => 15 + random.nextDouble() * 170;
  int colour() => random.nextInt(0x1000000);
  return [
    for (var index = 0; index < count; index++)
      switch (index % 6) {
        0 => _trait(
          [for (var point = 0; point < 4; point++) DocumentPoint(x(), y())],
          rgb: colour(),
          width: 4 + random.nextDouble() * 10,
        ),
        1 => _shape(
          VectorKind.rectangle,
          20 + random.nextDouble() * 120,
          20 + random.nextDouble() * 80,
          160 + random.nextDouble() * 120,
          110 + random.nextDouble() * 70,
          rgb: colour(),
          fillRgb: colour(),
        ),
        2 => _trait([DocumentPoint(x(), y())], rgb: colour(), width: 26),
        3 => _shape(
          VectorKind.ellipse,
          20 + random.nextDouble() * 120,
          20 + random.nextDouble() * 80,
          160 + random.nextDouble() * 120,
          110 + random.nextDouble() * 70,
          rgb: colour(),
          fillRgb: index % 12 == 3 ? colour() : null,
        ),
        4 => _shape(VectorKind.line, x(), y(), x(), y(), rgb: colour()),
        _ => _text('OO\nO', 20 + random.nextDouble() * 200, y() * .6, 24),
      },
  ];
}

Future<ui.Image> _image(int width, int height, int Function(int x) argb) {
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final colour = argb(x);
      final offset = (y * width + x) * 4;
      pixels[offset] = (colour >> 16) & 0xff;
      pixels[offset + 1] = (colour >> 8) & 0xff;
      pixels[offset + 2] = colour & 0xff;
      pixels[offset + 3] = (colour >> 24) & 0xff;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Lets the dialog that was just asked for come into view. On return its
/// film is at its very beginning.
Future<void> _arrive(WidgetTester tester) async {
  // The dialog is built, still to come into view.
  await tester.pump();
  expect(find.byKey(const Key('replayDialog')), findsOneWidget);
  // It has come: the film starts with the frame after this one.
  await tester.pump(const Duration(milliseconds: 400));
  // The first frame of the film: its clock starts here, at zero.
  await tester.pump();
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  /// Shows the dialog over an empty page. On return the dialog is built and
  /// its film is at its very beginning: every later pump of a duration moves
  /// the film by that duration.
  Future<_Seen> open(
    WidgetTester tester,
    ReplayScene scene, {
    Size size = const Size(1100, 760),
    double textScale = 1,
    double pixelRatio = 1,
    bool lessMotion = false,
    ThemeData? theme,
  }) async {
    tester.view.devicePixelRatio = pixelRatio;
    tester.view.physicalSize = size * pixelRatio;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    if (lessMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    final seen = _Seen();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('show'),
              onPressed: () async {
                await showReplayDialog(
                  context,
                  scene: scene,
                  onStarted: () => seen.started++,
                  onFinished: () => seen.finished++,
                );
                seen.closed++;
              },
              child: const Text('Montrer'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('show')));
    await _arrive(tester);
    return seen;
  }

  /// The moment [elapsed] of the film of [scene], painted by the plain way.
  Future<_Shot> moment(
    WidgetTester tester,
    Size size,
    ReplayScene scene,
    Duration elapsed, {
    bool overshoot = true,
  }) => _painted(
    tester,
    size,
    (canvas, size) =>
        _paintPlainly(canvas, size, scene, elapsed, overshoot: overshoot),
  );

  testWidgets(
    'the film starts by itself, redraws the drawing and leaves it complete',
    (tester) async {
      final scene = _smallScene();
      final plan = _planOf(scene);
      expect(plan.total, const Duration(microseconds: 2388768));
      final seen = await open(tester, scene);
      expect(find.text('Ton dessin se refait tout seul'), findsOneWidget);
      expect(find.text('Le film de ton dessin commence.'), findsOneWidget);
      expect(find.text('Revoir'), findsOneWidget);
      expect(find.text('Revenir au dessin'), findsOneWidget);
      expect(seen.started, 1);
      expect(seen.finished, 0);

      // The film begins with the empty sheet, as the studio shows one.
      final first = await _shot(tester);
      final empty = await _painted(
        tester,
        first.size,
        (canvas, size) => _paintAsStudio(canvas, size, _sceneOf(const [])),
      );
      expect(first.differences(empty), 0);
      final sheet = _viewport(first.size, scene);
      Offset at(double x, double y) =>
          Offset(sheet.left + x * sheet.scale, sheet.top + y * sheet.scale);
      expect(first.rgbAt(at(150, 40)), 0xfff4d6);

      // Half a second later the trait is on its way, from its first point.
      await tester.pump(const Duration(milliseconds: 500));
      final early = await _shot(tester);
      expect(early.rgbAt(at(60, 40)), 0x224466);
      expect(early.rgbAt(at(170, 40)), 0x224466);
      expect(early.rgbAt(at(200, 40)), 0xfff4d6, reason: 'not there yet');
      expect(early.rgbAt(at(110, 120)), 0xfff4d6, reason: 'no rectangle yet');
      expect(seen.finished, 0);

      // The rectangle has its outline before its inside.
      await tester.pump(const Duration(milliseconds: 800));
      final later = await _shot(tester);
      expect(later.rgbAt(at(250, 40)), 0x224466, reason: 'the trait is whole');
      expect(later.rgbAt(at(110, 80)), 0x112233, reason: 'top of the outline');
      expect(later.rgbAt(at(110, 120)), 0xfff4d6, reason: 'no inside yet');
      expect(later.rgbAt(at(230, 120)), 0xfff4d6, reason: 'no dot yet');

      // To the end of the film, to the microsecond.
      await tester.pump(plan.total - const Duration(milliseconds: 1301));
      expect(seen.finished, 0);
      expect(find.text('Le film de ton dessin commence.'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(seen.finished, 1);
      await tester.pump();
      expect(find.text('Ton dessin est fini.'), findsOneWidget);
      expect(find.text('Le film de ton dessin commence.'), findsNothing);

      // The complete drawing stays: pixel for pixel the sheet of the studio.
      final last = await _shot(tester);
      final studio = await _painted(
        tester,
        last.size,
        (canvas, size) => _paintAsStudio(canvas, size, scene),
      );
      expect(last.differences(studio), 0);
      expect(last.rgbAt(at(110, 120)), 0x00cc44);
      expect(last.rgbAt(at(230, 120)), 0xaa0000);
      expect(last.rgbAt(at(240, 140)), 0x477fb2);
      expect(last.differences(empty), greaterThan(1000));

      // Nothing is called again, and nothing moves any more.
      await tester.pump(const Duration(seconds: 30));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect((await _shot(tester)).differences(studio), 0);
      expect(seen.started, 1);
      expect(seen.finished, 1);
      expect(seen.closed, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the film waits for the dialog to have come, and its callbacks may rebuild the page',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 760);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scene = _smallScene();
      final plan = _planOf(scene);
      var started = 0;
      var finished = 0;
      // The page under the dialog shows what the callbacks tell it: they
      // rebuild it, as the studio may want to.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => TextButton(
                key: const Key('show'),
                onPressed: () => showReplayDialog(
                  context,
                  scene: scene,
                  onStarted: () => update(() => started++),
                  onFinished: () => update(() => finished++),
                ),
                child: Text('$started films, $finished finis'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('show')));
      await tester.pump();
      expect(find.byKey(const Key('replayDialog')), findsOneWidget);
      // The dialog is coming into view: the film has not started.
      await tester.pump(const Duration(milliseconds: 40));
      expect(started, 0);
      expect(find.text('0 films, 0 finis'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 40));
      expect(started, 0);
      // It has come.
      await tester.pump(const Duration(milliseconds: 100));
      expect(started, 1);
      await tester.pump();
      expect(find.text('1 films, 0 finis'), findsOneWidget);
      // The first picture of the film is the empty sheet, in full view.
      final first = await _shot(tester);
      expect(
        first.differences(
          await _painted(
            tester,
            first.size,
            (canvas, size) => _paintAsStudio(canvas, size, _sceneOf(const [])),
          ),
        ),
        0,
      );
      await tester.pump(plan.total);
      expect(finished, 1);
      await tester.pump();
      expect(find.text('1 films, 1 finis'), findsOneWidget);
      await tester.tap(find.byKey(const Key('replayAgain')));
      await tester.pump();
      expect(find.text('2 films, 1 finis'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // « Revoir » before the dialog has quite come starts the film, once.
      await tester.tap(find.byKey(const Key('closeReplay')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('show')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(started, 2);
      await tester.tap(find.byKey(const Key('replayAgain')));
      await tester.pump();
      expect(started, 3);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(started, 3, reason: 'the film is not started again on arrival');
      expect(finished, 1);

      // A dialog closed before it has come has shown no film.
      await tester.tap(find.byKey(const Key('closeReplay')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('show')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('replayDialog')), findsNothing);
      expect(started, 3);
      expect(finished, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('« Revoir » starts the film again from the empty sheet', (
    tester,
  ) async {
    final scene = _smallScene();
    final plan = _planOf(scene);
    final seen = await open(tester, scene);
    final empty = await _shot(tester);

    // In the middle of the film.
    await tester.pump(const Duration(milliseconds: 1200));
    expect((await _shot(tester)).differences(empty), greaterThan(500));
    await tester.tap(find.byKey(const Key('replayAgain')));
    await tester.pump();
    expect(seen.started, 2);
    expect(seen.finished, 0, reason: 'a film started again did not end');
    expect((await _shot(tester)).differences(empty), 0);
    await tester.pump(const Duration(milliseconds: 500));
    final again = await _shot(tester);
    expect(
      again.differences(
        await moment(
          tester,
          again.size,
          scene,
          const Duration(milliseconds: 500),
        ),
      ),
      0,
    );

    // Once it has ended.
    await tester.pump(plan.total);
    await tester.pump();
    expect(seen.finished, 1);
    expect(find.text('Ton dessin est fini.'), findsOneWidget);
    final complete = await _shot(tester);
    await tester.tap(find.byKey(const Key('replayAgain')));
    await tester.pump();
    expect(seen.started, 3);
    expect(find.text('Le film de ton dessin commence.'), findsOneWidget);
    expect((await _shot(tester)).differences(empty), 0);
    await tester.pump(plan.total);
    await tester.pump();
    expect(seen.started, 3);
    expect(seen.finished, 2);
    expect(find.text('Ton dessin est fini.'), findsOneWidget);
    expect((await _shot(tester)).differences(complete), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the line under the status fills as the film goes, and nothing '
      'is to drag', (tester) async {
    final scene = _smallScene();
    final plan = _planOf(scene);
    final seen = await open(tester, scene);
    final line = find.descendant(
      of: find.byKey(const Key('replayProgress')),
      matching: find.byType(CustomPaint),
    );
    final size = tester.getSize(line);
    expect(size.height, 4);
    expect(size.width, tester.getSize(find.byKey(_sheetKey)).width);
    final track = studioLine.toARGB32() & 0xffffff;
    final filled = studioGreen.toARGB32() & 0xffffff;
    // The colours of the line at a quarter and at three quarters of it.
    Future<(int, int)> colours() async {
      final shot = await _painted(
        tester,
        size,
        tester.widget<CustomPaint>(line).painter!.paint,
      );
      return (
        shot.rgbAt(Offset(size.width * .25, 2)),
        shot.rgbAt(Offset(size.width * .75, 2)),
      );
    }

    expect(await colours(), (track, track));
    final half = plan.total * .5;
    await tester.pump(half);
    expect(await colours(), (filled, track));

    // It shows the time; it is not a handle on it. Neither it nor the sheet
    // answers a pointer that is dragged over them: the film goes its way.
    await tester.drag(line, Offset(size.width * .4, 0), warnIfMissed: false);
    await tester.drag(
      find.byKey(_sheetKey),
      const Offset(-200, 40),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(await colours(), (filled, track));
    final shot = await _shot(tester);
    expect(shot.differences(await moment(tester, shot.size, scene, half)), 0);
    expect(find.byType(Slider), findsNothing);
    expect(seen.started, 1);

    // A frame of the film paints the line again, and what moves on the
    // sheet: not the title and the status, which are written once.
    RenderObject pictureOf(Finder finder) {
      var node = tester.renderObject(finder);
      while (!node.isRepaintBoundary) {
        node = node.parent!;
      }
      return node;
    }

    final texts = pictureOf(find.text(ReplayDialog.title));
    expect(pictureOf(find.byKey(const Key('replayStatus'))), same(texts));
    expect(pictureOf(line), isNot(same(texts)));
    final pictures = find.descendant(
      of: find.byKey(_sheetKey),
      matching: find.byType(RepaintBoundary),
    );
    await tester.pump(const Duration(milliseconds: 16), EnginePhase.layout);
    expect(pictureOf(line).debugNeedsPaint, isTrue);
    expect(tester.renderObject(pictures.last).debugNeedsPaint, isTrue);
    expect(tester.renderObject(pictures.first).debugNeedsPaint, isFalse);
    expect(texts.debugNeedsPaint, isFalse);
    await tester.pump();

    await tester.pump(plan.total - half);
    expect(await colours(), (filled, filled));
    expect(seen.finished, 1);
    await tester.tap(find.byKey(const Key('replayAgain')));
    await tester.pump();
    expect(await colours(), (track, track));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Échap, Entrée and « Revenir au dessin » return to the drawing', (
    tester,
  ) async {
    final scene = _smallScene();
    final plan = _planOf(scene);
    final seen = await open(tester, scene);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replayDialog')), findsNothing);
    expect(seen.closed, 1);
    expect(seen.finished, 0, reason: 'closed before its end');

    // The way back is focused: Entrée closes.
    await tester.tap(find.byKey(const Key('show')));
    await _arrive(tester);
    expect(seen.started, 2);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replayDialog')), findsNothing);
    expect(seen.closed, 2);

    // The button, a moment before the film would have ended: the film
    // stops with the click, and does not end while the dialog goes away.
    await tester.tap(find.byKey(const Key('show')));
    await _arrive(tester);
    await tester.pump(plan.total - const Duration(milliseconds: 20));
    await tester.tap(find.byKey(const Key('closeReplay')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('replayDialog')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replayDialog')), findsNothing);
    expect(seen.started, 3);
    expect(seen.closed, 3);
    expect(seen.finished, 0);

    // Closed after its end, it has ended once.
    await tester.tap(find.byKey(const Key('show')));
    await _arrive(tester);
    await tester.pump(plan.total);
    await tester.pump();
    await tester.tap(find.byKey(const Key('closeReplay')));
    await tester.pumpAndSettle();
    expect(seen.started, 4);
    expect(seen.closed, 4);
    expect(seen.finished, 1);

    // A click beside the dialog closes it too.
    await tester.tap(find.byKey(const Key('show')));
    await _arrive(tester);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replayDialog')), findsNothing);
    expect(seen.closed, 5);
    expect(seen.finished, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the keyboard reaches « Revoir », and the dialog keeps the focus',
    (tester) async {
      final seen = await open(tester, _smallScene());
      BuildContext? focused() =>
          tester.binding.focusManager.primaryFocus?.context;
      bool within(String key) =>
          find
              .descendant(
                of: find.byKey(Key(key)),
                matching: find.byWidget(focused()!.widget),
              )
              .evaluate()
              .isNotEmpty ||
          tester.widget(find.byKey(Key(key))) == focused()!.widget;
      expect(within('closeReplay'), isTrue);
      // Tab goes round inside the dialog: the page under it is out of reach.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(within('replayAgain'), isTrue);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(seen.started, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(seen.started, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(within('closeReplay'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(within('replayAgain'), isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(within('closeReplay'), isTrue);
      expect(seen.closed, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(seen.closed, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the controls are large, named and announced; the sheet and its status too',
    (tester) async {
      // A theme of its own makes buttons compact on a desktop: these two
      // keep the size of a child's target.
      final seen = await open(tester, _smallScene());
      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        for (final (key, label) in [
          ('replayAgain', 'Revoir'),
          ('closeReplay', 'Revenir au dessin'),
        ]) {
          final control = find.byKey(Key(key));
          final size = tester.getSize(control);
          expect(size.height, greaterThanOrEqualTo(48), reason: key);
          expect(size.width, greaterThanOrEqualTo(88), reason: key);
          expect(
            tester.getSemantics(control),
            isSemantics(
              label: label,
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
              hasTapAction: true,
            ),
            reason: key,
          );
        }
        // The two targets do not touch.
        expect(
          tester.getRect(find.byKey(const Key('closeReplay'))).left -
              tester.getRect(find.byKey(const Key('replayAgain'))).right,
          greaterThanOrEqualTo(8),
        );
        expect(
          tester.getSemantics(find.byKey(const Key('closeReplay'))),
          isSemantics(isFocused: true),
        );

        // The title is a heading and the name of the dialog.
        final title = tester.getSemantics(
          find.text('Ton dessin se refait tout seul'),
        );
        expect(
          title,
          isSemantics(
            label: 'Ton dessin se refait tout seul',
            isHeader: true,
            namesRoute: true,
          ),
        );
        var scope = title.parent;
        while (scope != null && !scope.flagsCollection.scopesRoute) {
          scope = scope.parent;
        }
        expect(scope, isNotNull, reason: 'the dialog is a route of its own');

        // The sheet is one picture with a name.
        expect(find.bySemanticsLabel('Le film de ton dessin'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Le film de ton dessin')),
          isSemantics(label: 'Le film de ton dessin', isImage: true),
        );

        // The status is said when it changes.
        final status = find.byKey(const Key('replayStatus'));
        expect(
          tester.getSemantics(status),
          isSemantics(
            label: 'Le film de ton dessin commence.',
            isLiveRegion: true,
          ),
        );
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        expect(seen.finished, 1);
        expect(
          tester.getSemantics(status),
          isSemantics(label: 'Ton dessin est fini.', isLiveRegion: true),
        );
        // What the child reads is written with the apostrophe of books.
        for (final text in [
          ReplayDialog.title,
          ReplayDialog.sheetLabel,
          ReplayDialog.startedStatus,
          ReplayDialog.finishedStatus,
          ReplayDialog.emptyStatus,
          ReplayDialog.pageOnlyStatus,
        ]) {
          expect(text, isNot(contains("'")));
        }
        expect(ReplayDialog.emptyStatus, contains('n’y a'));
        expect(ReplayDialog.pageOnlyStatus, contains('n’y a'));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'in a small window with enlarged text the film shows and nothing overflows',
    (tester) async {
      final scene = _smallScene();
      final seen = await open(
        tester,
        scene,
        size: const Size(680, 520),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      const window = Rect.fromLTWH(0, 0, 680, 520);
      for (final key in ['replayAgain', 'closeReplay']) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(rect.height, greaterThanOrEqualTo(48), reason: key);
        expect(rect.width, greaterThanOrEqualTo(48), reason: key);
        expect(window.contains(rect.topLeft), isTrue, reason: key);
        expect(window.contains(rect.bottomRight), isTrue, reason: key);
      }
      // The sheet keeps a size worth looking at, in the proportions of the
      // drawing.
      final box = tester.getSize(find.byKey(_sheetKey));
      expect(box.height, greaterThanOrEqualTo(ReplayDialog.minSheetHeight));
      expect(box.width, greaterThan(300));
      final sheet = _viewport(box, scene);
      expect(sheet.width / sheet.height, closeTo(1.5, 1e-9));
      expect(sheet.height, greaterThanOrEqualTo(100));
      // What is under the title can be reached, and the film plays.
      await tester.ensureVisible(find.byKey(const Key('replayStatus')));
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const Key('replayStatus'))).bottom,
        lessThanOrEqualTo(520),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(seen.finished, 1);
      final last = await _shot(tester);
      expect(
        last.differences(
          await _painted(
            tester,
            last.size,
            (canvas, size) => _paintAsStudio(canvas, size, scene),
          ),
        ),
        0,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('closeReplay')));
      await tester.pumpAndSettle();
      expect(seen.closed, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (window, textScale) in const [
    (Size(1100, 760), 1.0),
    (Size(1920, 1080), 1.0),
    (Size(900, 700), 1.5),
    (Size(681, 521), 1.3),
    (Size(420, 640), 1.0),
    // The smallest window of the studio, and the largest text, each alone.
    (Size(680, 520), 1.0),
    (Size(1100, 760), 2.0),
  ]) {
    testWidgets('the sheet takes the room of a window of $window at text '
        '$textScale and keeps its proportions', (tester) async {
      for (final (width, height) in [(1200, 800), (800, 1200), (1200, 1200)]) {
        final scene = _sceneOf(
          [
            _trait([
              const DocumentPoint(100, 100),
              DocumentPoint(width - 100, height - 100),
            ]),
          ],
          width: width,
          height: height,
        );
        final where = '$width × $height';
        await open(tester, scene, size: window, textScale: textScale);
        expect(tester.takeException(), isNull, reason: where);
        final dialog = find.byKey(const Key('replayDialog'));
        // Most of the window is the dialog.
        final surface = tester.getRect(
          find.descendant(of: dialog, matching: find.byType(Material)).first,
        );
        expect(surface.width, window.width - 48, reason: where);
        expect(surface.height, window.height - 48, reason: where);
        // All of it is in view: nothing has to scroll.
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: dialog, matching: find.byType(Scrollable)),
        );
        expect(scroll.position.maxScrollExtent, 0, reason: where);
        // The box of the sheet takes all that the texts and the buttons
        // leave: nothing is lost between them.
        final box = tester.getRect(find.byKey(_sheetKey));
        final title = tester.getRect(find.text(ReplayDialog.title));
        final status = tester.getRect(find.byKey(const Key('replayStatus')));
        final progress = tester.getRect(
          find.byKey(const Key('replayProgress')),
        );
        final again = tester.getRect(find.byKey(const Key('replayAgain')));
        final close = tester.getRect(find.byKey(const Key('closeReplay')));
        expect(box.width, window.width - 96, reason: where);
        expect(title.top, closeTo(48, .01), reason: where);
        expect(box.top, closeTo(title.bottom + 16, .01), reason: where);
        expect(status.top, closeTo(box.bottom + 12, .01), reason: where);
        expect(progress.top, closeTo(status.bottom + 8, .01), reason: where);
        expect(
          math.min(again.top, close.top),
          closeTo(progress.bottom + 16, .01),
          reason: where,
        );
        expect(
          math.max(again.bottom, close.bottom),
          closeTo(window.height - 40, .01),
          reason: where,
        );
        expect(box.height, greaterThan(200), reason: where);
        for (final rect in [again, close]) {
          expect(rect.height, greaterThanOrEqualTo(48), reason: where);
          expect(rect.left, greaterThanOrEqualTo(48), reason: where);
          expect(rect.right, lessThanOrEqualTo(window.width - 48));
        }

        // In its box the paper has the proportions of the drawing, and
        // reaches the edges of the box in one direction, but for a margin.
        final shot = await _shot(tester);
        var left = shot.width;
        var right = -1;
        var top = shot.height;
        var bottom = -1;
        for (var y = 0; y < shot.height; y++) {
          for (var x = 0; x < shot.width; x++) {
            final offset = (y * shot.width + x) * 4;
            if (shot.rgba[offset] != 0xff ||
                shot.rgba[offset + 1] != 0xf4 ||
                shot.rgba[offset + 2] != 0xd6) {
              continue;
            }
            if (x < left) left = x;
            if (x > right) right = x;
            if (y < top) top = y;
            if (y > bottom) bottom = y;
          }
        }
        final paperWidth = right - left + 1;
        final paperHeight = bottom - top + 1;
        expect(
          paperWidth / paperHeight,
          closeTo(width / height, .02),
          reason: where,
        );
        expect(
          math.max(paperWidth / box.width, paperHeight / box.height),
          greaterThan(.8),
          reason: where,
        );
        // The sheet is in the middle of its box.
        expect((left + right + 1) / 2, closeTo(box.width / 2, 1));
        expect((top + bottom + 1) / 2, closeTo(box.height / 2, 1));

        await tester.tap(find.byKey(const Key('closeReplay')));
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
      }
    });
  }

  testWidgets('what lies under stays under, whenever it is redrawn', (
    tester,
  ) async {
    // The red square was made first, on the upper layer; the blue one after
    // it, on the lower layer: redrawn second, painted first.
    const red = 0xd75e56;
    const blue = 0x477fb2;
    final scene = _sceneOf(
      [
        _shape(VectorKind.rectangle, 60, 40, 200, 140, fillRgb: red),
        _shape(
          VectorKind.rectangle,
          120,
          90,
          260,
          180,
          rgb: 0x000000,
          fillRgb: blue,
        ),
      ],
      paintRank: const [1, 0],
    );
    final plan = _planOf(scene);
    await open(tester, scene);
    final box = tester.getSize(find.byKey(_sheetKey));
    final sheet = _viewport(box, scene);
    Offset at(double x, double y) =>
        Offset(sheet.left + x * sheet.scale, sheet.top + y * sheet.scale);

    await tester.pump(plan.endOf(0));
    var shot = await _shot(tester);
    expect(shot.rgbAt(at(160, 115)), red);
    expect(shot.rgbAt(at(230, 160)), 0xfff4d6);

    // The outline of the blue square is being drawn: where it passes under
    // the red one it does not show.
    await tester.pump(plan.startOf(1) - plan.endOf(0));
    await tester.pump(const Duration(milliseconds: 300));
    shot = await _shot(tester);
    expect(shot.rgbAt(at(230, 90)), 0x000000, reason: 'outline beside');
    expect(shot.rgbAt(at(160, 90)), red, reason: 'outline under the red');
    expect(
      shot.differences(
        await moment(
          tester,
          shot.size,
          scene,
          plan.startOf(1) + const Duration(milliseconds: 300),
        ),
      ),
      0,
    );

    // Its inside comes, under the red one too.
    await tester.pump(const Duration(milliseconds: 300));
    shot = await _shot(tester);
    expect(shot.rgbAt(at(160, 115)), red);
    expect(shot.rgbAt(at(230, 160)), isNot(0xfff4d6));
    expect(shot.rgbAt(at(230, 160)), isNot(blue));

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    shot = await _shot(tester);
    expect(shot.rgbAt(at(160, 115)), red);
    expect(shot.rgbAt(at(160, 90)), red);
    expect(shot.rgbAt(at(120, 115)), red, reason: 'left side under the red');
    expect(shot.rgbAt(at(230, 160)), blue);
    expect(shot.rgbAt(at(230, 180)), 0x000000);
    expect(
      shot.differences(
        await _painted(
          tester,
          shot.size,
          (canvas, size) => _paintAsStudio(canvas, size, scene),
        ),
      ),
      0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('what goes beyond the sheet is cut at its edge, all along', (
    tester,
  ) async {
    // A trait that leaves the sheet by its right edge, a big dot astride
    // its bottom edge and a filled square around its top left corner.
    final scene = _sceneOf([
      _trait(const [DocumentPoint(180, 60), DocumentPoint(340, 60)], width: 30),
      _trait(const [DocumentPoint(90, 205)], rgb: 0xaa0000, width: 70),
      _shape(
        VectorKind.rectangle,
        -40,
        -30,
        50,
        40,
        width: 10,
        fillRgb: 0x00cc44,
      ),
    ]);
    final plan = _planOf(scene);
    await open(tester, scene);
    final empty = await _shot(tester);
    final sheet = _viewport(empty.size, scene);
    Offset at(double x, double y) =>
        Offset(sheet.left + x * sheet.scale, sheet.top + y * sheet.scale);
    // The paper, with the pixels that its edge shares with what is around.
    final paper = Rect.fromLTWH(
      sheet.left,
      sheet.top,
      sheet.width,
      sheet.height,
    ).inflate(1);
    var elapsed = Duration.zero;
    for (final when in [
      plan.endOf(0) * .8,
      plan.endOf(0),
      plan.startOf(1) + (plan.endOf(1) - plan.startOf(1)) * .6,
      plan.startOf(2) + (plan.endOf(2) - plan.startOf(2)) * .5,
      plan.startOf(2) + (plan.endOf(2) - plan.startOf(2)) * .9,
      plan.total,
    ]) {
      await tester.pump(when - elapsed);
      elapsed = when;
      final shot = await _shot(tester);
      expect(
        shot.differences(empty, outside: paper),
        0,
        reason: 'beside the sheet at $when',
      );
      expect(
        shot.differences(await moment(tester, shot.size, scene, when)),
        0,
        reason: 'at $when',
      );
    }
    await tester.pump();
    // Each of the three reaches the edge it leaves the sheet by.
    final last = await _shot(tester);
    expect(last.rgbAt(at(298, 60)), 0x224466);
    expect(last.rgbAt(at(90, 198)), 0xaa0000);
    expect(last.rgbAt(at(2, 2)), 0x00cc44);
    expect(last.differences(empty), greaterThan(2000));
    expect(
      last.differences(
        await _painted(
          tester,
          last.size,
          (canvas, size) => _paintAsStudio(canvas, size, scene),
        ),
      ),
      0,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (name, ranks) in <(String, List<int> Function(int))>[
    ('one layer', (count) => List.generate(count, (index) => index)),
    (
      // Even elements on the lower layer, odd ones on the upper one.
      'two layers used in turn',
      (count) => [
        for (var index = 0; index < count; index++)
          index.isEven ? index ~/ 2 : (count + 1) ~/ 2 + index ~/ 2,
      ],
    ),
    (
      // The first third was drawn on the upper layer.
      'the upper layer first',
      (count) => [
        for (var index = 0; index < count; index++)
          index < count ~/ 3 ? count - count ~/ 3 + index : index - count ~/ 3,
      ],
    ),
    ('upside down', (count) => List.generate(count, (i) => count - 1 - i)),
    (
      'any order',
      (count) => List.generate(count, (i) => i)..shuffle(math.Random(3)),
    ),
  ]) {
    testWidgets(
      'at every moment the two pictures of the dialog are the film: $name',
      (tester) async {
        const count = 45;
        final scene = _sceneOf(_manyElements(count), paintRank: ranks(count));
        final plan = _planOf(scene);
        // More than 24 s unhurried: played faster, in 24 s exactly.
        expect(plan.total, const Duration(seconds: 24));
        final order = ReplayOrder(scene.paintRank);
        await open(tester, scene);
        // The pile, by the plain way: the elements sorted by their place.
        final pile = List.generate(count, (index) => index)
          ..sort((a, b) => scene.paintRank[a].compareTo(scene.paintRank[b]));
        // Moments anywhere in the elements, and some at the very end of
        // one: nothing is being drawn then, and the picture must be the
        // sheet of the studio with the elements complete so far.
        final rests = {
          for (final index in [0, 4, 9, 17, 26, 33, 40]) plan.endOf(index),
        };
        final moments = <Duration>{
          for (final milliseconds in [
            0,
            137,
            400,
            401,
            1900,
            3900,
            6000,
            8000,
            9400,
            12000,
            14000,
            16000,
            18000,
            19900,
            22000,
            23999,
            24000,
            25399,
            35398,
          ])
            Duration(milliseconds: milliseconds),
          ...rests,
        }.toList()..sort();
        var elapsed = Duration.zero;
        final kept = <int>{};
        var floating = 0;
        var rested = 0;
        for (final at in moments) {
          await tester.pump(at - elapsed);
          elapsed = at;
          final shot = await _shot(tester);
          expect(
            shot.differences(await moment(tester, shot.size, scene, elapsed)),
            0,
            reason: '$name at $elapsed',
          );
          final finished = plan.finishedAt(elapsed);
          if (rests.contains(at)) {
            expect(plan.progressAt(plan.currentAt(elapsed), elapsed), 1);
            final studio = await _painted(
              tester,
              shot.size,
              (canvas, size) => _paintAsStudio(
                canvas,
                size,
                scene,
                paintOrder: [
                  for (final index in pile)
                    if (index < finished) index,
                ],
              ),
            );
            expect(
              shot.differences(studio),
              0,
              reason: '$name with $finished complete',
            );
            rested++;
          }
          // What this compares: a kept picture and, most of the time,
          // complete elements painted over it with the one being drawn.
          kept.add(order.restingAt(finished));
          floating = math.max(floating, finished - order.restingAt(finished));
        }
        expect(rested, 7);
        expect(elapsed, greaterThan(plan.total));
        expect(
          kept.length,
          greaterThan(name == 'upside down' || name == 'any order' ? 1 : 3),
        );
        expect(kept, contains(count));
        if (name != 'one layer') expect(floating, greaterThan(3));
        // And the end is the sheet of the studio.
        await tester.pump();
        final last = await _shot(tester);
        expect(
          last.differences(
            await _painted(
              tester,
              last.size,
              (canvas, size) => _paintAsStudio(canvas, size, scene),
            ),
          ),
          0,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'the film stays the film when the window changes and when it starts again',
    (tester) async {
      // Two layers used in turn: most of the time one part of the pile is
      // kept and another is painted over it for every frame.
      const count = 30;
      final scene = _sceneOf(
        _manyElements(count, seed: 23),
        paintRank: [
          for (var index = 0; index < count; index++)
            index.isEven ? index ~/ 2 : count ~/ 2 + index ~/ 2,
        ],
      );
      final plan = _planOf(scene);
      final seen = await open(tester, scene);
      var elapsed = Duration.zero;
      Future<void> expectFilm(String when) async {
        final shot = await _shot(tester);
        expect(
          shot.differences(await moment(tester, shot.size, scene, elapsed)),
          0,
          reason: when,
        );
      }

      Future<void> wait(double share) async {
        final time = plan.total * share;
        await tester.pump(time);
        elapsed += time;
      }

      await wait(.4);
      await expectFilm('before');
      final large = tester.getSize(find.byKey(_sheetKey));

      // A smaller window, then a larger one: both pictures follow at once,
      // and the film goes on from where it was.
      tester.view.physicalSize = const Size(700, 540);
      await tester.pump();
      expect(tester.getSize(find.byKey(_sheetKey)).width, large.width - 400);
      await expectFilm('in a smaller window');
      await wait(.1);
      await expectFilm('later in the smaller window');
      tester.view.physicalSize = const Size(1300, 900);
      await tester.pump();
      await expectFilm('in a larger window');

      // Started again in the middle: what was kept is let go.
      await tester.tap(find.byKey(const Key('replayAgain')));
      await tester.pump();
      elapsed = Duration.zero;
      await expectFilm('started again');
      await wait(.3);
      await expectFilm('later in the second film');

      // Larger letters leave the sheet less room.
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      await tester.pump();
      await expectFilm('with larger letters');
      await wait(.45);
      await expectFilm('near the end');
      expect(seen.finished, 0);
      await wait(.25);
      await tester.pump();
      expect(seen.started, 2);
      expect(seen.finished, 1);
      final last = await _shot(tester);
      expect(
        last.differences(
          await _painted(
            tester,
            last.size,
            (canvas, size) => _paintAsStudio(canvas, size, scene),
          ),
        ),
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'on a screen of more pixels than points the two pictures are still the film',
    (tester) async {
      // One and a half pixels a point, and two: ratios that a number of the
      // engine holds exactly. At others the picture of a box that does not
      // lie at the origin of its layer is taken a hair aside, and compares
      // unequal with one made at the origin, whatever was painted in it.
      for (final pixelRatio in [1.5, 2.0]) {
        const count = 24;
        final scene = _sceneOf(
          _manyElements(count, seed: 31),
          paintRank: [
            for (var index = 0; index < count; index++)
              index.isEven ? index ~/ 2 : count ~/ 2 + index ~/ 2,
          ],
        );
        final plan = _planOf(scene);
        await open(
          tester,
          scene,
          size: const Size(903, 641),
          pixelRatio: pixelRatio,
        );
        var elapsed = Duration.zero;
        for (final share in [.07, .2, .2, .2, .2, .13]) {
          final time = plan.total * share;
          await tester.pump(time);
          elapsed += time;
          final shot = await _shot(tester, pixelRatio: pixelRatio);
          expect(shot.width, (shot.size.width * pixelRatio).ceil());
          expect(
            shot.differences(
              await _painted(
                tester,
                shot.size,
                (canvas, size) => _paintPlainly(canvas, size, scene, elapsed),
                pixelRatio: pixelRatio,
              ),
            ),
            0,
            reason: '$pixelRatio pixels a point at $elapsed',
          );
        }
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.text('Ton dessin est fini.'), findsOneWidget);
        final last = await _shot(tester, pixelRatio: pixelRatio);
        expect(
          last.differences(
            await _painted(
              tester,
              last.size,
              (canvas, size) => _paintAsStudio(canvas, size, scene),
              pixelRatio: pixelRatio,
            ),
          ),
          0,
          reason: '$pixelRatio pixels a point at the end',
        );
        await tester.tap(find.byKey(const Key('closeReplay')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'the scene of a document ends as the studio paints that document',
    (tester) async {
      // What the studio holds: every element by its index, and the indices
      // of those of the visible layers, lower layer first. Elements 2, 5,
      // 8… are on a hidden layer.
      final all = _manyElements(20, seed: 5);
      final paintOrder = [
        for (var index = 0; index < 20; index++)
          if (index % 3 == 1) index,
        for (var index = 0; index < 20; index++)
          if (index % 3 == 0) index,
      ];
      final background = (await tester.runAsync(
        () => _image(6, 4, (x) => x < 3 ? 0xffffe0e0 : 0xffe0e0ff),
      ))!;
      final scene = ReplayScene.fromDocumentOrder(
        all: all,
        paintOrder: paintOrder,
        width: 300,
        height: 200,
        paperRgb: 0xffffff,
        background: background,
      );
      expect(scene.elements, hasLength(14));
      await open(tester, scene);
      final first = await _shot(tester);
      final sheet = _viewport(first.size, scene);
      // The image is under the drawing from the first frame.
      expect(
        first.rgbAt(Offset(sheet.left + 30 * sheet.scale, sheet.top + 20)),
        0xffe0e0,
      );
      expect(
        first.rgbAt(Offset(sheet.left + 270 * sheet.scale, sheet.top + 20)),
        0xe0e0ff,
      );
      await tester.pump(const Duration(seconds: 24));
      await tester.pump();
      expect(find.text('Ton dessin est fini.'), findsOneWidget);
      final last = await _shot(tester);
      expect(
        last.differences(
          await _painted(
            tester,
            last.size,
            (canvas, size) => _paintAsStudio(
              canvas,
              size,
              scene,
              strokes: all,
              paintOrder: paintOrder,
            ),
          ),
        ),
        0,
      );

      // The image was borrowed: the dialog held it while it was open, and
      // gave back no more than it took.
      expect(background.debugGetOpenHandleStackTraces(), hasLength(2));
      await tester.tap(find.byKey(const Key('closeReplay')));
      await tester.pumpAndSettle();
      expect(background.debugDisposed, isFalse);
      expect(background.debugGetOpenHandleStackTraces(), hasLength(1));
      expect(background.width, 6);
      background.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the film of a real document shows its visible layers and leaves it as it was',
    (tester) async {
      final document = RustDocument(width: 600, height: 400);
      addTearDown(document.dispose);
      document.setPaperColor(0xfff4d6);
      // Made on an upper layer first, then under it, then on a third layer
      // that is hidden, then on the upper one again.
      document.addLayer();
      document.addShape(
        VectorKind.ellipse,
        const DocumentPoint(150, 100),
        const DocumentPoint(450, 300),
        rgb: 0x9a3b2f,
        width: 12,
        fillRgb: 0xffd84a,
      );
      document.addStamp(
        const DocumentPoint(60, 60),
        const DocumentPoint(180, 180),
        stamp: 2,
        rgb: 0xd75e56,
      );
      document.setActiveLayer(0);
      document.addShape(
        VectorKind.rectangle,
        const DocumentPoint(40, 40),
        const DocumentPoint(560, 360),
        rgb: 0x477fb2,
        width: 8,
        fillRgb: 0xd8effa,
      );
      document.addStroke(
        const [
          DocumentPoint(20, 330),
          DocumentPoint(300, 250),
          DocumentPoint(580, 330),
        ],
        rgb: 0x4e9a51,
        width: 24,
      );
      // A new layer comes above the active one: this one above them all.
      document.setActiveLayer(1);
      document.addLayer();
      expect(document.layers.map((layer) => layer.id), [0, 1, 2]);
      document.addText(
        const DocumentPoint(200, 150),
        const DocumentPoint(360, 198),
        text: 'OOOO',
        rgb: 0x6a4f99,
        size: 40,
      );
      expect(document.setLayerVisible(2, false), isTrue);
      document.setActiveLayer(1);
      document.addStroke(
        const [DocumentPoint(300, 200)],
        rgb: 0x224466,
        width: 60,
      );
      expect(document.paintOrder, [2, 3, 0, 1, 5]);
      final svg = document.exportSvg();
      final undoCount = document.undoCount;

      // What the studio holds, and what its state hands to the dialog.
      final strokes = document.strokes;
      final all = List<RenderedElement>.unmodifiable(
        strokes.map(RenderedElement.new),
      );
      final scene = ReplayScene.fromDocumentOrder(
        all: all,
        paintOrder: document.paintOrder,
        width: document.width,
        height: document.height,
        paperRgb: document.paperRgb,
        background: null,
      );
      expect(scene.elements.map((element) => element.data), [
        strokes[0],
        strokes[1],
        strokes[2],
        strokes[3],
        strokes[5],
      ]);
      expect(scene.paintRank, [2, 3, 0, 1, 4]);
      final plan = _planOf(scene);
      final seen = await open(tester, scene);
      final box = tester.getSize(find.byKey(_sheetKey));
      final sheet = _viewport(box, scene);
      Offset at(double x, double y) =>
          Offset(sheet.left + x * sheet.scale, sheet.top + y * sheet.scale);

      var elapsed = Duration.zero;
      for (var index = 0; index < plan.length; index++) {
        // In the middle of each element, then at its end.
        for (final when in [
          plan.startOf(index) + (plan.endOf(index) - plan.startOf(index)) * .5,
          plan.endOf(index),
        ]) {
          await tester.pump(when - elapsed);
          elapsed = when;
          final shot = await _shot(tester);
          expect(
            shot.differences(await moment(tester, shot.size, scene, when)),
            0,
            reason: 'element $index at $when',
          );
          if (index == 2 && when == plan.endOf(2)) {
            // The blue square came third and lies under the yellow oval.
            expect(shot.rgbAt(at(300, 200)), 0xffd84a);
            expect(shot.rgbAt(at(60, 300)), 0xd8effa);
          }
        }
      }
      await tester.pump();
      expect(seen.finished, 1);
      final last = await _shot(tester);
      expect(
        last.differences(
          await _painted(
            tester,
            last.size,
            (canvas, size) => _paintAsStudio(
              canvas,
              size,
              scene,
              strokes: all,
              paintOrder: document.paintOrder,
            ),
          ),
        ),
        0,
      );
      // The text of the hidden layer is nowhere, the dot made last is on top.
      expect(last.rgbAt(at(300, 200)), 0x224466);
      expect(last.rgbAt(at(220, 172)), 0xffd84a);
      expect(last.rgbAt(at(30, 30)), 0xfff4d6);

      // The film changed nothing of the drawing.
      await tester.tap(find.byKey(const Key('closeReplay')));
      await tester.pumpAndSettle();
      expect(document.exportSvg(), svg);
      expect(document.undoCount, undoCount);
      expect(document.paintOrder, [2, 3, 0, 1, 5]);
      for (final (index, stroke) in document.strokes.indexed) {
        expect(identical(stroke, strokes[index]), isTrue);
      }
      expect(tester.takeException(), isNull);
    },
    skip: !available,
  );

  testWidgets(
    'a film goes on although the studio lets go of the image meanwhile',
    (tester) async {
      final background = (await tester.runAsync(
        () => _image(6, 4, (x) => 0xff80c0ff),
      ))!;
      final scene = _sceneOf([
        _trait(const [DocumentPoint(30, 40), DocumentPoint(270, 40)]),
      ], background: background);
      final seen = await open(tester, scene);
      await tester.pump(const Duration(milliseconds: 300));
      background.dispose();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('replayAgain')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(seen.started, 2);
      expect(seen.finished, 1);
      final last = await _shot(tester);
      final sheet = _viewport(last.size, scene);
      expect(
        last.rgbAt(Offset(sheet.left + 150 * sheet.scale, sheet.top + 20)),
        0x80c0ff,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('closeReplay')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an empty sheet has no film, and says so', (tester) async {
    final scene = _sceneOf(const [], paperRgb: 0xa8d8f0);
    final seen = await open(tester, scene);
    expect(
      find.text('Ta feuille est encore vide : il n’y a rien à refaire.'),
      findsOneWidget,
    );
    expect(find.text('Le film de ton dessin commence.'), findsNothing);
    expect(find.text('Ton dessin est fini.'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('replayAgain')))
          .enabled,
      isFalse,
    );
    // Once the dialog has come, nothing moves.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    final shot = await _shot(tester);
    expect(
      shot.differences(
        await _painted(
          tester,
          shot.size,
          (canvas, size) => _paintAsStudio(canvas, size, scene),
        ),
      ),
      0,
    );
    final sheet = _viewport(shot.size, scene);
    expect(
      shot.rgbAt(Offset(sheet.left + sheet.width / 2, sheet.top + 20)),
      0xa8d8f0,
    );
    await tester.tap(find.byKey(const Key('replayAgain')), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
    expect(seen.started, 0);
    expect(seen.finished, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(seen.closed, 1);
    expect(tester.takeException(), isNull);
  });

  // A colouring page: two zones at the bottom, a line over the first one,
  // all locked; the child drew a trait across them, which lies between the
  // zones and the line, and may have coloured both zones with the paint pot.
  ReplayScene pageScene({bool coloured = true, bool drawn = true}) {
    const pentagon = [
      DocumentPoint(150, 30),
      DocumentPoint(230, 90),
      DocumentPoint(200, 175),
      DocumentPoint(100, 175),
      DocumentPoint(70, 90),
    ];
    final zone = RenderedElement(
      StrokeData(
        pentagon,
        0xffffff,
        .1,
        kind: VectorKind.contour,
        fillRgb: coloured ? 0xeebf4e : 0xffffff,
        layer: 1,
      ),
    );
    final corner = RenderedElement(
      StrokeData(
        const [DocumentPoint(240, 20), DocumentPoint(290, 60)],
        0xffffff,
        .1,
        kind: VectorKind.rectangle,
        fillRgb: coloured ? 0x9385bc : 0xffffff,
        layer: 1,
      ),
    );
    final line = RenderedElement(
      StrokeData(pentagon, 0x2f3d4a, 6, kind: VectorKind.contour, layer: 2),
    );
    final trait = _trait(const [
      DocumentPoint(20, 120),
      DocumentPoint(280, 120),
    ], rgb: 0xd75e56);
    return ReplayScene.fromDocumentOrder(
      all: [zone, corner, line, if (drawn) trait],
      paintOrder: drawn ? const [0, 1, 3, 2] : const [0, 1, 2],
      width: 300,
      height: 200,
      // A tinted sheet: a white zone shows on it.
      paperRgb: _cream,
      background: null,
      fixedLayers: const {1, 2},
    );
  }

  // Where a point of the page scene lies in a shot of the film.
  Offset Function(double x, double y) on(_Shot shot) {
    final sheet = _viewport(shot.size, pageScene());
    return (x, y) =>
        Offset(sheet.left + x * sheet.scale, sheet.top + y * sheet.scale);
  }

  testWidgets(
    'a page is on the sheet from the first frame, white; its zones take their colour in turn, then the trait is redrawn under its line',
    (tester) async {
      final scene = pageScene();
      expect(scene.fixedCount, 1);
      expect(scene.recolouredCount, 2);
      final plan = _planOf(scene);
      final trait = ReplayPlan.naturalDuration(
        scene.elements.last.data,
        sheetDiagonal: math.sqrt(300 * 300 + 200 * 200),
      );
      // The step of each zone, then the trait, with a pause between two.
      final step = ReplayPlan.zone + ReplayPlan.pause;
      expect(plan.total, step * 2 + trait);
      final seen = await open(tester, scene);
      expect(seen.started, 1);
      expect(find.text('Le film de ton dessin commence.'), findsOneWidget);
      // The first frame is the page as it was made, its zone white: as the
      // studio paints the untouched page.
      final first = await _shot(tester);
      expect(
        first.differences(
          await _painted(
            tester,
            first.size,
            (canvas, size) => _paintAsStudio(
              canvas,
              size,
              pageScene(coloured: false, drawn: false),
            ),
          ),
        ),
        0,
      );
      final at = on(first);
      expect(first.rgbAt(at(150, 102)), 0xffffff);
      expect(first.rgbAt(at(265, 40)), 0xffffff);
      expect(first.rgbAt(at(76, 108)), 0x2f3d4a);

      // The colour spreads from the middle of the first zone to its edges;
      // the other zone waits, white.
      await tester.pump(ReplayPlan.zone * .2);
      var shot = await _shot(tester);
      expect(
        shot.differences(
          await moment(tester, shot.size, scene, ReplayPlan.zone * .2),
        ),
        0,
      );
      expect(shot.rgbAt(at(150, 102)), 0xeebf4e);
      expect(shot.rgbAt(at(105, 170)), 0xffffff, reason: 'not there yet');
      expect(shot.rgbAt(at(76, 108)), 0x2f3d4a, reason: 'under the line');
      expect(shot.rgbAt(at(265, 40)), 0xffffff, reason: 'its turn is next');
      await tester.pump(ReplayPlan.zone * .8 + ReplayPlan.pause);
      shot = await _shot(tester);
      expect(shot.rgbAt(at(105, 170)), 0xeebf4e);
      expect(shot.rgbAt(at(265, 40)), 0xffffff);
      // Then the second zone, in its turn.
      await tester.pump(step);
      shot = await _shot(tester);
      expect(shot.rgbAt(at(265, 40)), 0x9385bc);
      expect(shot.rgbAt(at(30, 120)), _cream, reason: 'no trait yet');

      // While the trait is redrawn, the line of the page stays over it.
      await tester.pump(trait * .8);
      shot = await _shot(tester);
      expect(
        shot.differences(
          await moment(tester, shot.size, scene, step * 2 + trait * .8),
        ),
        0,
      );
      expect(shot.rgbAt(at(150, 120)), 0xd75e56);
      // Where the trait passes under the left side of the pentagon.
      expect(shot.rgbAt(at(80.6, 120)), 0x2f3d4a);
      expect(shot.rgbAt(at(270, 120)), _cream, reason: 'not there yet');

      await tester.pump(trait * .2);
      await tester.pump();
      expect(seen.finished, 1);
      expect(find.text('Ton dessin est fini.'), findsOneWidget);
      // The end is the sheet of the studio, pixel for pixel.
      final last = await _shot(tester);
      expect(
        last.differences(
          await _painted(
            tester,
            last.size,
            (canvas, size) => _paintAsStudio(canvas, size, scene),
          ),
        ),
        0,
      );
      expect(last.rgbAt(at(270, 120)), 0xd75e56);
      expect(last.rgbAt(at(105, 170)), 0xeebf4e);
      expect(last.rgbAt(at(265, 40)), 0x9385bc);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a page whose zones were coloured is a film, though nothing is drawn',
    (tester) async {
      final scene = pageScene(drawn: false);
      expect(scene.nothingToRedraw, isFalse);
      final total = ReplayPlan.zone * 2 + ReplayPlan.pause;
      expect(_planOf(scene).total, total);
      final seen = await open(tester, scene);
      expect(seen.started, 1);
      final at = on(await _shot(tester));
      expect((await _shot(tester)).rgbAt(at(150, 102)), 0xffffff);
      await tester.pump(total);
      await tester.pump();
      expect(seen.finished, 1);
      final last = await _shot(tester);
      expect(
        last.differences(
          await _painted(
            tester,
            last.size,
            (canvas, size) => _paintAsStudio(canvas, size, scene),
          ),
        ),
        0,
      );
      expect(last.rgbAt(at(150, 102)), 0xeebf4e);
      expect(last.rgbAt(at(265, 40)), 0x9385bc);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a page with nothing coloured nor drawn has no film, and says so',
    (tester) async {
      final scene = pageScene(coloured: false, drawn: false);
      expect(scene.nothingToRedraw, isTrue);
      final seen = await open(tester, scene);
      expect(find.text(ReplayDialog.pageOnlyStatus), findsOneWidget);
      expect(find.text(ReplayDialog.emptyStatus), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('replayAgain')))
            .enabled,
        isFalse,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      // The page is there, whole.
      final shot = await _shot(tester);
      expect(
        shot.differences(
          await _painted(
            tester,
            shot.size,
            (canvas, size) => _paintAsStudio(canvas, size, scene),
          ),
        ),
        0,
      );
      expect(seen.started, 0);
      expect(seen.finished, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('where the system asks for less motion the film is not hurried', (
    tester,
  ) async {
    final scene = _smallScene();
    final plan = _planOf(scene);
    final seen = await open(tester, scene, lessMotion: true);
    // Hurried as other animations are, it would be over in an eighth of
    // a second.
    await tester.pump(const Duration(milliseconds: 500));
    expect(seen.finished, 0);
    final shot = await _shot(tester);
    expect(
      shot.differences(
        await moment(
          tester,
          shot.size,
          scene,
          const Duration(milliseconds: 500),
        ),
      ),
      0,
    );
    await tester.pump(plan.total - const Duration(milliseconds: 501));
    expect(seen.finished, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(seen.finished, 1);
    await tester.pump();
    expect(find.text('Ton dessin est fini.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final lessMotion in [false, true]) {
    testWidgets(
      'a stamp grows ${lessMotion ? 'without a bounce where less motion is asked' : 'with a small bounce'}',
      (tester) async {
        final scene = _sceneOf([
          _trait(const [DocumentPoint(40, 40)], width: 20),
          RenderedElement(
            StrokeData(
              const [DocumentPoint(90, 40), DocumentPoint(210, 160)],
              0xd75e56,
              1,
              kind: VectorKind.stamp,
              stamp: 0,
            ),
          ),
        ]);
        final plan = _planOf(scene);
        expect(plan.total, const Duration(milliseconds: 780));
        final seen = await open(tester, scene, lessMotion: lessMotion);
        // Six tenths of the time of the stamp: where the bounce is widest.
        const there = Duration(milliseconds: 330 + 270);
        await tester.pump(there);
        final shot = await _shot(tester);
        final bouncing = await moment(tester, shot.size, scene, there);
        final calm = await moment(
          tester,
          shot.size,
          scene,
          there,
          overshoot: false,
        );
        expect(bouncing.differences(calm), greaterThan(200));
        expect(shot.differences(lessMotion ? calm : bouncing), 0);
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pump();
        expect(seen.finished, 1);
        final last = await _shot(tester);
        expect(
          last.differences(
            await _painted(
              tester,
              last.size,
              (canvas, size) => _paintAsStudio(canvas, size, scene),
            ),
          ),
          0,
        );
        expect(tester.takeException(), isNull);
      },
      skip: !available,
    );
  }

  testWidgets(
    'three thousand elements: the kept picture is renewed by steps, not for every frame',
    (tester) async {
      const count = 3000;
      final random = math.Random(1);
      final scene = _sceneOf([
        for (var index = 0; index < count; index++)
          index.isEven
              ? _trait(
                  [
                    DocumentPoint(
                      10 + random.nextDouble() * 280,
                      10 + random.nextDouble() * 180,
                    ),
                    DocumentPoint(
                      10 + random.nextDouble() * 280,
                      10 + random.nextDouble() * 180,
                    ),
                  ],
                  rgb: random.nextInt(0x1000000),
                  width: 3,
                )
              : _trait(
                  [
                    DocumentPoint(
                      10 + random.nextDouble() * 280,
                      10 + random.nextDouble() * 180,
                    ),
                  ],
                  rgb: random.nextInt(0x1000000),
                  width: 8,
                ),
      ]);
      final plan = _planOf(scene);
      expect(plan.total, const Duration(seconds: 24));
      await open(tester, scene);
      final pictures = find.descendant(
        of: find.byKey(_sheetKey),
        matching: find.byType(RepaintBoundary),
      );
      expect(pictures, findsNWidgets(2));
      final resting = tester.renderObject<RenderRepaintBoundary>(
        pictures.first,
      );
      final moving = tester.renderObject<RenderRepaintBoundary>(pictures.last);
      resting.debugResetMetrics();
      moving.debugResetMetrics();

      // Every frame of the film at sixty frames a second.
      const frame = Duration(microseconds: 16667);
      var frames = 0;
      var elapsed = Duration.zero;
      var severalAtOnce = 0;
      while (elapsed < plan.total) {
        final before = plan.finishedAt(elapsed);
        await tester.pump(frame);
        elapsed += frame;
        frames++;
        if (plan.finishedAt(elapsed) - before > 1) severalAtOnce++;
        if (frames == 700) {
          // In the middle, the two pictures are still the film.
          final shot = await _shot(tester);
          expect(
            shot.differences(await moment(tester, shot.size, scene, elapsed)),
            0,
          );
        }
      }
      await tester.pump();
      expect(frames, greaterThan(1400));
      expect(severalAtOnce, greaterThan(frames ~/ 4));
      // The picture of what moves was painted for every frame; the kept
      // one some sixty times in all, and it ends with every element.
      final movingPaints =
          moving.debugAsymmetricPaintCount + moving.debugSymmetricPaintCount;
      final restingPaints =
          resting.debugAsymmetricPaintCount + resting.debugSymmetricPaintCount;
      expect(movingPaints, greaterThanOrEqualTo(frames - 1));
      expect(restingPaints, inInclusiveRange(30, 90));
      expect(find.text('Ton dessin est fini.'), findsOneWidget);
      final last = await _shot(tester);
      expect(
        last.differences(
          await _painted(
            tester,
            last.size,
            (canvas, size) => _paintAsStudio(canvas, size, scene),
          ),
        ),
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a dialog that is there at once, with nobody to tell, plays its film too',
    (tester) async {
      // On a page of its own: nothing comes into view, nothing is to wait
      // for. And nobody listens to its start or to its end.
      final scene = _smallScene();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReplayDialog(scene: scene)),
        ),
      );
      expect(find.text('Le film de ton dessin commence.'), findsOneWidget);
      // The frame after the one that built it is the first of the film.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final shot = await _shot(tester);
      expect(
        shot.differences(
          await _painted(
            tester,
            shot.size,
            (canvas, size) => _paintPlainly(
              canvas,
              size,
              scene,
              const Duration(milliseconds: 600),
            ),
          ),
        ),
        0,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Ton dessin est fini.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('replayAgain')));
      await tester.pump();
      expect(find.text('Le film de ton dessin commence.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Taken away in the middle of its film, it leaves nothing running:
      // the clock of the film, which asked for every frame, is gone.
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.transientCallbackCount, greaterThanOrEqualTo(1));
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a scene whose pile is not one, or whose sheet cannot be laid '
      'out, is refused when it opens', (tester) async {
    final elements = _manyElements(3);
    for (final ranks in [
      [0, 1],
      [0, 0, 1],
      [0, 1, 3],
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReplayDialog(scene: _sceneOf(elements, paintRank: ranks)),
          ),
        ),
      );
      expect(tester.takeException(), isArgumentError, reason: '$ranks');
      expect(find.byKey(const Key('replayDialog')), findsNothing);
    }
    // Nor is a sheet that has no size, or one beyond what a sheet may be,
    // with or without anything drawn on it.
    for (final (width, height) in [(0, 200), (300, 0), (300, 20000)]) {
      for (final drawn in [elements, const <RenderedElement>[]]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReplayDialog(
                scene: _sceneOf(drawn, width: width, height: height),
              ),
            ),
          ),
        );
        expect(
          tester.takeException(),
          isArgumentError,
          reason: '$width × $height, ${drawn.length} elements',
        );
        // Refused before anything of it was built, not while it paints.
        expect(find.byKey(const Key('replayDialog')), findsNothing);
      }
    }
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
