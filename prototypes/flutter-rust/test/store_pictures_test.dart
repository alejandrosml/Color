// SPDX-License-Identifier: MIT
// Opt-in pictures for the App Store, drawn by the application's own widgets,
// with the real core and real fonts, at the sizes App Store Connect takes
// (« Screenshot specifications », read on 28 October 2026):
//   - iPhone with Dynamic Island, medium display: 2556 × 1179, on its side;
//   - iPad 13 inches: 2752 × 2064, on its side;
//   - Mac: 2880 × 1800 (16:10).
// Each device lays the studio out as it does: the telephone's two columns,
// the tablet's studio for a finger, the computer's window. The letters of
// the system are Roboto's here, as in the review pictures; the iPhone's
// island and the bar at the foot of its screen are left empty.
//
// The first picture is « Mon jardin » (Color 1.2): the gestures of
// support/my_garden.dart, each made through the controls of the studio — a
// finger on the telephone and the tablet, the mouse on the computer. The
// colours that the palette does not show are made in « Autres couleurs »;
// what is too small for the screen is drawn from closer, two fingers moved
// apart or ⌘ and the wheel.
//
//   COLOR_STORE_DIR=/absolute/output flutter test test/store_pictures_test.dart
//
// Without that variable the test is skipped and writes nothing. With
// COLOR_STORE_LANGUAGE=en, the pictures of the English page (Color 1.1).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/country_signs.dart';
import 'package:edupaint_flutter_study/language.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/replay_dialog.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_painters.dart';
import 'package:edupaint_flutter_study/text_layout.dart';
import 'package:edupaint_flutter_study/view_transform.dart';
import 'package:flutter/cupertino.dart' show CupertinoThumbPainter;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/my_garden.dart';
import 'support/review_fonts.dart';

class _Device {
  const _Device(
    this.name,
    this.pixels,
    this.ratio,
    this.padding, {
    required this.touch,
    required this.platform,
  });
  final String name;

  /// The picture App Store Connect takes, in pixels.
  final Size pixels;
  final double ratio;

  /// What the system keeps of the screen, in points: the island of the
  /// iPhone and the bar at its foot, the bars of the iPad.
  final EdgeInsets padding;
  final bool touch;
  final TargetPlatform platform;

  bool get phone => name == 'iphone';
}

const _devices = [
  _Device(
    'iphone',
    Size(2556, 1179),
    3,
    EdgeInsets.fromLTRB(59, 0, 59, 21),
    touch: true,
    platform: TargetPlatform.iOS,
  ),
  _Device(
    'ipad',
    Size(2752, 2064),
    2,
    EdgeInsets.fromLTRB(0, 24, 0, 20),
    touch: true,
    platform: TargetPlatform.iOS,
  ),
  _Device(
    'mac',
    Size(2880, 1800),
    2,
    EdgeInsets.zero,
    touch: false,
    platform: TargetPlatform.macOS,
  ),
];

const _boundaryKey = ValueKey('store-boundary');

// The colouring page of the third picture, and where the pot is poured on
// it, in the units of the page: in every zone of the page of Color 1.1.1,
// the point farthest from its lines (core/tools/page_zones.py), with the
// colours of the row that the tablet and the computer show at once, the way
// a child would colour it. The eggs and the eye stay white.
const _page = 'dinosaure';
const _pours = [
  (Offset(31, 30), 0xa8d8f0), // the sky: Ciel
  (Offset(557, 438), 0x78a66f), // the dinosaur: Prairie
  (Offset(918, 548), 0x78a66f), // its tail
  (Offset(571, 616), 0x78a66f), // its four legs
  (Offset(771, 627), 0x78a66f),
  (Offset(633, 613), 0x78a66f),
  (Offset(817, 604), 0x78a66f),
  (Offset(679, 469), 0x388778), // its spots: Sapin
  (Offset(787, 485), 0x388778),
  (Offset(599, 519), 0x388778),
  (Offset(635, 374), 0xef9439), // the plates of its back: Orange
  (Offset(717, 362), 0xef9439),
  (Offset(799, 378), 0xef9439),
  (Offset(597, 89), 0xef9439), // the rays of the sun
  (Offset(650, 109), 0xeebf4e), // the sun: Soleil
  (Offset(109, 262), 0x388778), // the five palm leaves: Sapin
  (Offset(130, 212), 0x388778),
  (Offset(187, 181), 0x388778),
  (Offset(279, 195), 0x388778),
  (Offset(278, 255), 0x388778),
  (Offset(176, 263), 0x79513e), // the coconuts: Chocolat
  (Offset(227, 267), 0x79513e),
  (Offset(995, 485), 0x79513e), // the volcano: Chocolat
  (Offset(949, 308), 0xd75e56), // its lava: Coquelicot
  (Offset(939, 202), 0x9aa3a5), // its smoke: Gris
  (Offset(984, 153), 0x9aa3a5),
  (Offset(1051, 102), 0x9aa3a5),
  (Offset(899, 696), 0xd75e56), // the stones: Coquelicot, Bleu denim
  (Offset(1064, 695), 0x477fb2),
  (Offset(155, 642), 0xe69976), // the trunk of the palm: Pêche
  (Offset(313, 649), 0xef9439), // the nest: Orange
  (Offset(488, 688), 0xeebf4e), // the sand, last: Soleil
];

class _Pictures {
  _Pictures(this.tester, this.device, this.output);
  final WidgetTester tester;
  final _Device device;
  final String output;
  int _count = 0;

  // What the hand holds, to ask the studio only for what changes: the tool,
  // the stamp, the colour of the trait and of the inside, where the next
  // colour goes, the width.
  String? _tool;
  String? _stamp;
  int? _ink;
  int? _inside;
  bool _toInside = false;
  int? _width;

  /// A finger on the glass of the telephone and of the tablet, the pointer
  /// of the mouse on the computer.
  PointerDeviceKind get _hand =>
      device.touch ? PointerDeviceKind.touch : PointerDeviceKind.mouse;

  Future<void> start({StudioOptionsStore? options}) async {
    final d = device;
    _tool = _stamp = null;
    _ink = _inside = _width = null;
    _toInside = false;
    tester.view.devicePixelRatio = d.ratio;
    tester.view.physicalSize = d.pixels;
    // The screen, which tells a telephone from a tablet.
    tester.view.display.size = d.pixels;
    tester.view.display.devicePixelRatio = d.ratio;
    final insets = FakeViewPadding(
      left: d.padding.left * d.ratio,
      top: d.padding.top * d.ratio,
      right: d.padding.right * d.ratio,
      bottom: d.padding.bottom * d.ratio,
    );
    tester.view.padding = insets;
    tester.view.viewPadding = insets;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.display.resetSize);
    addTearDown(tester.view.display.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _boundaryKey,
        child: EduPaintApp(
          files: MemoryFiles(),
          recoveryStorage: MemoryRecovery(),
          options: options,
          // The same pot on every machine: in France, it closes small gaps.
          countrySigns: () async => CountrySigns(codes: const ['FR']),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shot(String name) async {
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundaryKey),
    );
    _count++;
    final file = File(
      '$output/${device.name}-${_count.toString().padLeft(2, '0')}-$name.png',
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: device.ratio);
      expect(
        Size(image.width.toDouble(), image.height.toDouble()),
        device.pixels,
      );
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
  }

  bool _shown(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

  Future<void> tap(String key) async {
    final control = find.byKey(Key(key));
    // The rectangle and the oval are chosen in « Formes ».
    if (control.evaluate().isEmpty &&
        (key == 'tool-rectangle' || key == 'tool-ellipse')) {
      await tap('tool-shapes');
    }
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  /// A tool taken, when the hand does not hold it already. Taking a tool
  /// lets go of the element that was chosen, and the next colour is the
  /// colour of the trait again.
  Future<void> hold(String tool) async {
    if (_tool == tool) return;
    await tap(tool);
    _tool = tool;
    _toInside = false;
  }

  /// A colour: in the palette when it is there, or else found in « Autres
  /// couleurs » — among the recent ones, among the shades, or made with the
  /// three slides, each clicked where the colour lies.
  Future<void> colour(int rgb) async {
    final hex = rgb.toRadixString(16);
    if (_shown('color-$hex')) return tap('color-$hex');
    await tap('morePaintColors');
    for (final known in ['dialog-recent-color-$hex', 'shade-$hex']) {
      if (_shown(known)) {
        await tap(known);
        return tap('confirmPaintColor');
      }
    }
    final wanted = HSVColor.fromColor(Color(0xff000000 | rgb));
    await _slide(_axis('paintHue'), wanted.hue / 360);
    await _slide(_axis('paintIntensity'), wanted.saturation);
    await _slide(_axis('paintLightness'), wanted.value);
    await tap('confirmPaintColor');
  }

  /// The slide of one of the three axes of a colour, under its name.
  Finder _axis(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('paintAxis-'),
    ),
  );

  /// A click on a slide where [share] of its way lies, as its thumb goes:
  /// 8 pixels of track and the radius of the thumb are left at both ends.
  Future<void> _slide(Finder slide, double share) async {
    await tester.ensureVisible(slide);
    await tester.pumpAndSettle();
    final box = tester.getRect(slide);
    const inset = 8.0 + CupertinoThumbPainter.radius;
    await tester.tapAt(
      Offset(box.left + inset + (box.width - 2 * inset) * share, box.center.dy),
    );
    await tester.pumpAndSettle();
  }

  /// The colour of the trait, of a stamp, of the pot, of the letters.
  Future<void> ink(int rgb) async {
    if (_ink == rgb && !_toInside) return;
    if (_toInside) {
      await tap('paint-target-stroke');
      _toInside = false;
    }
    if (_ink == rgb) return;
    await colour(rgb);
    _ink = rgb;
  }

  /// The colours of a rectangle or an oval: its outline, then its inside.
  Future<void> paints(int line, int inside) async {
    await ink(line);
    if (_inside == inside) return;
    await tap('paint-target-fill');
    _toInside = true;
    await colour(inside);
    _inside = inside;
  }

  /// The width of the trait, from 2 to 48 units, clicked on its slide.
  Future<void> width(int units) async {
    if (_width == units) return;
    await _slide(
      find.byKey(const Key('brushWidthSemantics')),
      (units - 2) / 46,
    );
    _width = units;
  }

  /// The view of the sheet, as the studio paints it: where the sheet is
  /// on the screen, and how large.
  ViewTransform get _view {
    final picture = tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byKey(const Key('sheetPicture')),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    return (picture.painter! as DocumentPainter).viewport.transform;
  }

  /// Where a point of the sheet lies on the screen, the view as it is.
  Offset at(double x, double y) {
    final view = _view;
    return tester.getTopLeft(find.byKey(const Key('sheetPicture'))) +
        Offset(view.left + x * view.scale, view.top + y * view.scale);
  }

  /// The whole sheet in view again.
  Future<void> wholeSheet() async {
    if (_view.isFit) return;
    // On the telephone « Toute la feuille » is in the menu.
    if (device.phone) await tap('phoneMenu');
    await tap('fitPage');
    expect(_view.isFit, isTrue);
  }

  /// Before a gesture on [box] of the sheet, which must travel [pixels] on
  /// the screen along its longer side to be a drag and not a click: on a
  /// small screen a child looks closer to draw something small, with two
  /// fingers moved apart, or the wheel of the mouse and ⌘; the whole sheet
  /// comes back for what is large.
  Future<void> see(Rect box, {double pixels = 0}) async {
    final wanted = pixels == 0 ? 0.0 : pixels / box.longestSide;
    var view = _view;
    final surface = tester.getRect(find.byKey(const Key('sheetPicture')));
    bool visible() {
      final onScreen = Rect.fromPoints(
        at(box.left, box.top),
        at(box.right, box.bottom),
      );
      return surface.deflate(4).contains(onScreen.topLeft) &&
          surface.deflate(4).contains(onScreen.bottomRight);
    }

    if (view.scale >= wanted && (view.isFit || visible())) return;
    await wholeSheet();
    view = _view;
    if (view.scale >= wanted) return;
    final factor = wanted / view.scale * 1.15;
    final focus = at(box.center.dx, box.center.dy);
    if (device.touch) {
      // Two fingers, one on each side, moved apart.
      const apart = Offset(24, 0);
      final first = await tester.startGesture(focus - apart, pointer: 31);
      final second = await tester.startGesture(focus + apart, pointer: 32);
      await first.moveTo(focus - apart * factor);
      await second.moveTo(focus + apart * factor);
      await first.up();
      await second.up();
    } else {
      // The pointer over the place, ⌘ held, the wheel turned.
      final mouse = TestPointer(33, PointerDeviceKind.mouse)..hover(focus);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendEventToBinding(
        mouse.scroll(Offset(0, -math.log(factor) / .002)),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    }
    await tester.pumpAndSettle();
    expect(_view.scale, greaterThanOrEqualTo(wanted));
    expect(visible(), isTrue);
  }

  Future<void> click(double x, double y) async {
    await tester.tapAt(at(x, y), kind: _hand);
    await tester.pumpAndSettle();
  }

  Future<void> drag(List<Offset> points) async {
    final gesture = await tester.startGesture(
      at(points.first.dx, points.first.dy),
      kind: _hand,
    );
    for (final point in points.skip(1)) {
      await gesture.moveTo(at(point.dx, point.dy));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// The pot at a point of the sheet, then what it pours: on the paper the
  /// pot reads the drawing as an image, which the engine makes outside the
  /// clock of the test.
  Future<void> pour(double x, double y) async {
    await tester.tapAt(at(x, y), kind: _hand);
    await tester.pump();
    final pouring = find.byKey(const Key('pouring'));
    for (var turn = 0; turn < 600 && pouring.evaluate().isNotEmpty; turn++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(pouring, findsNothing);
    await tester.pumpAndSettle();
  }

  /// The way of a brush through [points]: a supple curve, as a hand draws
  /// it, a point every dozen units.
  static List<Offset> _supple(List<Offset> points) {
    if (points.length < 3) return points;
    final all = [points.first, ...points, points.last];
    final way = [points.first];
    for (var index = 1; index < all.length - 2; index++) {
      final [before, from, to, after] = all.sublist(index - 1, index + 3);
      final leave = from + (to - before) / 6;
      final arrive = to - (after - from) / 6;
      final steps = math.max(2, ((to - from).distance / 12).ceil());
      for (var step = 1; step <= steps; step++) {
        final t = step / steps;
        final u = 1 - t;
        way.add(
          from * (u * u * u) +
              leave * (3 * u * u * t) +
              arrive * (3 * u * t * t) +
              to * (t * t * t),
        );
      }
    }
    return way;
  }

  static Rect _around(List<Offset> points) => points
      .skip(1)
      .fold(
        Rect.fromPoints(points.first, points.first),
        (box, point) => box.expandToInclude(Rect.fromPoints(point, point)),
      );

  /// A rectangle or an oval, dragged from one corner of [box] to the other.
  Future<void> _boxed(
    String tool,
    Rect box,
    int inside,
    int? line,
    int outline,
  ) async {
    await hold(tool);
    await paints(line ?? inside, inside);
    // Without a line, the thinnest outline, in the colour of the inside,
    // and a box that much smaller.
    await width(line == null ? 2 : outline);
    if (line == null) box = box.deflate(1);
    // Twice what tells a drag from a click.
    await see(box, pixels: device.touch ? 24 : 12);
    await drag([box.topLeft, box.center, box.bottomRight]);
  }

  /// One gesture of « Mon jardin », made with the controls of the studio.
  Future<void> make(Gesture gesture) async {
    switch (gesture) {
      case Pour(:final rgb, :final x, :final y):
        await hold('tool-fill');
        await ink(rgb);
        await wholeSheet();
        await pour(x, y);
      case Crest(:final rgb, width: final wide, :final points):
        await hold('tool-stroke');
        await ink(rgb);
        await width(wide);
        await wholeSheet();
        await drag(points);
      case Brush(:final rgb, width: final wide, :final points):
        await hold('tool-stroke');
        await ink(rgb);
        await width(wide);
        await see(_around(points));
        await drag(_supple(points));
      case Dot(:final rgb, width: final wide, :final x, :final y):
        await hold('tool-stroke');
        await ink(rgb);
        await width(wide);
        await see(Rect.fromCircle(center: Offset(x, y), radius: 1));
        await click(x, y);
      case Behind(:final x, :final y):
        await hold('tool-select');
        await wholeSheet();
        await click(x, y);
        await tap('selectionOrder');
        await tap('sendSelectionToBack');
      case Box(
        :final left,
        :final top,
        :final right,
        :final bottom,
        :final inside,
        :final line,
        width: final wide,
      ):
        await _boxed(
          'tool-rectangle',
          Rect.fromLTRB(left, top, right, bottom),
          inside,
          line,
          wide,
        );
      case Oval(
        :final x,
        :final y,
        :final across,
        :final up,
        :final inside,
        :final line,
        width: final wide,
      ):
        await _boxed(
          'tool-ellipse',
          Rect.fromCenter(
            center: Offset(x, y),
            width: 2 * across,
            height: 2 * up,
          ),
          inside,
          line,
          wide,
        );
      case Stamp(:final name, :final rgb, :final x, :final y, :final side):
        await hold('tool-stamp');
        if (_stamp != name) {
          await tap('chooseStamp');
          await tap('stamp-$name');
          _stamp = name;
        }
        await ink(rgb);
        // Its box, moved just enough to stay on the sheet.
        var box = Rect.fromCenter(
          center: Offset(x, y),
          width: side,
          height: side,
        );
        box = box.shift(
          Offset(
            math.max(0, -box.left) - math.max(0, box.right - 1200),
            math.max(0, -box.top) - math.max(0, box.bottom - 800),
          ),
        );
        // A drag sizes a stamp from 18 pixels on: a little more than that.
        await see(box, pixels: 24);
        await drag([box.topLeft, box.center, box.bottomRight]);
      case Words(:final x, :final y, :final size, :final rgb):
        await hold('tool-text');
        await ink(rgb);
        expect(size, 96, reason: 'the large letters of a sheet of 800');
        await tap('size-large');
        await wholeSheet();
        // The click is the top left corner of the text; the mock-up gave
        // the line its letters stand on, in the round letters of Color.
        final round = textFonts.indexWhere((font) => font.name == 'Ronde');
        await click(x, y - textFonts[round].baseline * size);
        await tap('textFont-$round');
        await tester.enterText(
          find.byKey(const Key('textField')),
          inEnglish ? 'My garden' : 'Mon jardin',
        );
        await tester.pumpAndSettle();
        await tap('confirmText');
    }
  }

  /// « Mon jardin »: every gesture of test/support/my_garden.dart, then the
  /// whole sheet in view and the brush in the hand.
  Future<void> garden() async {
    for (final gesture in myGarden) {
      await make(gesture);
    }
    await wholeSheet();
    await hold('tool-stroke');
    // Every gesture left its element, but the first, which coloured the
    // paper, and those that sent an element behind. The telephone keeps
    // this count in its menu.
    final made = myGarden.where((gesture) => gesture is! Behind).length - 1;
    if (!device.phone) {
      expect(find.textContaining(RegExp('^$made ')), findsOneWidget);
    }
  }

  /// Opens « Revoir ton dessin », lets the film run once to learn its
  /// length, then shows it again up to eight tenths of it.
  Future<void> film() async {
    if (device.phone) await tap('phoneMenu');
    // Not settled: settling would play the whole film.
    final open = find.byKey(const Key('replayDrawing'));
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pump();
    const step = Duration(milliseconds: 50);
    final finished = find.text(ReplayDialog.finishedStatus);
    var steps = 0;
    while (finished.evaluate().isEmpty && steps < 600) {
      await tester.pump(step);
      steps++;
    }
    expect(finished, findsOneWidget);
    // « Revoir », and the film stopped at eight tenths: the cat is there,
    // the butterflies have just come in; the grass and the title are to come.
    await tester.tap(find.byKey(const Key('replayAgain')));
    await tester.pump();
    for (var turn = 0; turn < steps * 0.8; turn++) {
      await tester.pump(step);
    }
  }

  /// A colouring page, coloured.
  Future<void> colouring() async {
    if (device.phone) await tap('phoneMenu');
    await tap('newProject');
    await tap('page-$_page');
    await tap('tool-fill');
    for (final (point, rgb) in _pours) {
      await colour(rgb);
      await click(point.dx, point.dy);
    }
  }

  /// A rainbow with the brush, grass, stars and a heart: the very simple
  /// interface of the youngest.
  Future<void> rainbow() async {
    await tap('tool-stroke');
    const centre = Offset(600, 640);
    for (final (radius, rgb) in const [
      (430.0, 0xe83d48), // Rouge vif
      (395.0, 0xef9439), // Orange
      (360.0, 0xeebf4e), // Soleil
      (325.0, 0x4db266), // Vert vif
      (290.0, 0x3370d1), // Bleu vif
      (255.0, 0x9385bc), // Lavande
    ]) {
      await colour(rgb);
      await drag([
        for (var step = 0; step <= 24; step++)
          centre +
              Offset(
                -radius * math.cos(math.pi * step / 24),
                -radius * math.sin(math.pi * step / 24),
              ),
      ]);
    }
    await colour(0x4db266);
    await drag([
      for (var step = 0; step <= 24; step++)
        Offset(40 + step * 46.0, 730 + 18 * math.sin(step * 1.3)),
    ]);
    await tap('tool-stamp');
    await colour(0xeebf4e);
    await click(150, 150);
    await click(1060, 200);
    await tap('chooseStamp');
    await tap('stamp-coeur');
    await colour(0xf4b7cf);
    await click(600, 560);
  }
}

void main() {
  final output = Platform.environment['COLOR_STORE_DIR'];
  final available =
      output != null && Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  for (final device in _devices) {
    testWidgets('pictures for the App Store: ${device.name}', (tester) async {
      debugDisableShadows = false;
      debugTouchFirstOverride = device.touch;
      debugDefaultTargetPlatformOverride = device.platform;
      if (Platform.environment['COLOR_STORE_LANGUAGE'] == 'en') {
        debugDeviceLanguage = AppLanguage.english;
      }
      try {
        await tester.runAsync(loadReviewFonts);
        final pictures = _Pictures(tester, device, output!);

        // 1. A drawing of the child's own.
        await pictures.start();
        await pictures.garden();
        await pictures.shot('dessin');

        // 2. Its film.
        await pictures.film();
        await pictures.shot('film');
        await tester.pumpWidget(const SizedBox.shrink());

        // 3. A colouring page.
        await pictures.start();
        await pictures.colouring();
        await pictures.shot('coloriage');
        await tester.pumpWidget(const SizedBox.shrink());

        // 4. The very simple interface of the youngest.
        final store = StudioOptionsStore.memory();
        addTearDown(store.dispose);
        await store.change(store.value.copyWith(level: InterfaceLevel.toddler));
        await pictures.start(options: store);
        await pictures.rainbow();
        await pictures.shot('tout-petits');
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDisableShadows = true;
        debugTouchFirstOverride = null;
        debugDefaultTargetPlatformOverride = null;
        debugDeviceLanguage = AppLanguage.french;
      }
    }, skip: !available);
  }
}
