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
//   COLOR_STORE_DIR=/absolute/output flutter test test/store_pictures_test.dart
//
// Without that variable the test is skipped and writes nothing.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/coloring_pages.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/replay_dialog.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/view_transform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
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
// it, in the units of the page, with the colours of the row that the tablet
// and the computer show at once: the way a child would colour it.
const _page = 'dinosaure';
const _pours = [
  (Offset(31, 30), 0xa8d8f0), // the sky: Ciel
  (Offset(721, 563), 0x78a66f), // the dinosaur: Prairie
  (Offset(376, 194), 0x78a66f), // its head
  (Offset(983, 588), 0x78a66f), // its tail
  (Offset(576, 596), 0x78a66f), // its legs
  (Offset(757, 596), 0x78a66f),
  (Offset(680, 470), 0x388778), // its spots: Sapin
  (Offset(786, 485), 0x388778),
  (Offset(598, 519), 0x388778),
  (Offset(630, 366), 0xef9439), // the plates of its back: Orange
  (Offset(717, 363), 0xef9439),
  (Offset(803, 378), 0xef9439),
  (Offset(650, 141), 0xeebf4e), // the sun: Soleil
  (Offset(113, 210), 0x388778), // the palm leaves: Sapin
  (Offset(269, 194), 0x388778),
  (Offset(195, 120), 0x388778),
  (Offset(176, 260), 0x79513e), // the coconuts: Chocolat
  (Offset(228, 269), 0x79513e),
  (Offset(1016, 457), 0x79513e), // the volcano: Chocolat
  (Offset(950, 309), 0xd75e56), // its lava: Coquelicot
  (Offset(943, 202), 0x9aa3a5), // its smoke: Gris
  (Offset(988, 153), 0x9aa3a5),
  (Offset(1049, 103), 0x9aa3a5),
  (Offset(898, 700), 0xd75e56), // the stones: Coquelicot, Bleu denim
  (Offset(1065, 695), 0x477fb2),
  (Offset(163, 522), 0xe69976), // the trunk of the palm: Pêche
  (Offset(356, 654), 0xef9439), // the nest: Orange
  (Offset(146, 711), 0xeebf4e), // the sand, last: Soleil
];

class _Pictures {
  _Pictures(this.tester, this.device, this.output);
  final WidgetTester tester;
  final _Device device;
  final String output;
  int _count = 0;

  Future<void> start({StudioOptionsStore? options}) async {
    final d = device;
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

  Future<void> tap(String key) async {
    final control = find.byKey(Key(key));
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  /// A colour of the palette, in the column of the telephone too.
  Future<void> colour(int rgb) => tap('color-${rgb.toRadixString(16)}');

  Offset get _centre =>
      tester.getCenter(find.byKey(const Key('drawingSurface')));

  /// Where a point of a sheet of [width] × [height] lies on the screen.
  Offset at(double x, double y, {double width = 1200, double height = 800}) {
    final size = tester.getSize(find.byKey(const Key('drawingSurface')));
    final view = ViewTransform.fit(
      viewWidth: size.width,
      viewHeight: size.height,
      padding: !device.phone && size.height >= 160 ? 28 : 8,
      documentWidth: width,
      documentHeight: height,
    );
    return _centre +
        Offset((x - width / 2) * view.scale, (y - height / 2) * view.scale);
  }

  Future<void> click(double x, double y) async {
    await tester.tapAt(at(x, y));
    await tester.pumpAndSettle();
  }

  Future<void> drag(List<Offset> points) async {
    final gesture = await tester.startGesture(
      at(points.first.dx, points.first.dy),
    );
    for (final point in points.skip(1)) {
      await gesture.moveTo(at(point.dx, point.dy));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> stamp(
    String name,
    int rgb,
    double x,
    double y, {
    bool large = false,
  }) async {
    await tap('chooseStamp');
    await tap('stamp-$name');
    if (rgb >= 0) await colour(rgb);
    await tap(large ? 'size-large' : 'size-medium');
    await click(x, y);
  }

  /// A garden: the sky, the grass, the sun, a rainbow, a house, a tree,
  /// flowers, a cat, a butterfly, a balloon, a bird, and a title.
  Future<void> garden() async {
    await tap('tool-rectangle');
    await tap('paint-target-stroke');
    await colour(0xa8d8f0);
    await tap('paint-target-fill');
    await colour(0xa8d8f0);
    await drag(const [Offset(14, 14), Offset(600, 300), Offset(1186, 540)]);
    await tap('paint-target-stroke');
    await colour(0x78a66f);
    await tap('paint-target-fill');
    await colour(0x78a66f);
    await drag(const [Offset(14, 540), Offset(600, 680), Offset(1186, 786)]);
    await tap('tool-stamp');
    await stamp('soleil', 0xeebf4e, 1030, 140, large: true);
    await stamp('arcenciel', -1, 560, 170, large: true);
    await stamp('maison', 0xd75e56, 300, 450, large: true);
    await stamp('arbre', 0x388778, 760, 440, large: true);
    await stamp('chat', 0x79513e, 960, 600);
    await stamp('fleur', 0xc96d93, 130, 690);
    await stamp('fleur', 0xef9439, 520, 700);
    await stamp('fleur', 0x9385bc, 690, 690);
    await stamp('papillon', 0xf4b7cf, 1090, 470);
    await stamp('ballon', 0xd75e56, 140, 300);
    await stamp('oiseau', 0x477fb2, 330, 170);
    await tap('tool-text');
    await colour(0xd75e56);
    await click(40, 40);
    await tester.enterText(find.byKey(const Key('textField')), 'Mon jardin');
    await tester.pumpAndSettle();
    await tap('confirmText');
    await tap('tool-stroke');
  }

  /// Opens « Revoir ton dessin », lets the film run once to learn its
  /// length, then shows it again up to seven tenths of it.
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
    while (finished.evaluate().isEmpty && steps < 400) {
      await tester.pump(step);
      steps++;
    }
    expect(finished, findsOneWidget);
    // « Revoir », and the film stopped when the butterfly comes in.
    await tester.tap(find.byKey(const Key('replayAgain')));
    await tester.pump();
    for (var turn = 0; turn < steps * 0.7; turn++) {
      await tester.pump(step);
    }
  }

  /// A colouring page, coloured.
  Future<void> colouring() async {
    final page = ColoringPages.all.singleWhere((page) => page.key == _page);
    if (device.phone) await tap('phoneMenu');
    await tap('newProject');
    await tap('page-$_page');
    await tap('tool-fill');
    for (final (point, rgb) in _pours) {
      await colour(rgb);
      await tester.tapAt(
        at(
          point.dx,
          point.dy,
          width: page.width.toDouble(),
          height: page.height.toDouble(),
        ),
      );
      await tester.pumpAndSettle();
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
      }
    }, skip: !available);
  }
}
