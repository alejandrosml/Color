// SPDX-License-Identifier: MIT
// Reference images of the sheet: what the studio paints, pixel for pixel,
// with the real core and the font of the texts, in the states where a cache
// of the drawing could go wrong — a trait being drawn under a layer, an
// element taken and dragged, a view zoomed in, an element erased or undone,
// a colouring page being coloured. They were made before the drawing was
// cached (F-01 of the retrospective of October 2026) and every later change
// of the painting must paint them again exactly.
//
//   flutter test test/reference_images_test.dart
//   flutter test --update-goldens test/reference_images_test.dart   (remake)
//
// Remake them only for a change of the picture that is wanted, and look at
// each new image before keeping it. They were all remade on 12 November
// 2026 for the studio of the pebbles (Color 1.2, step G1): the sheet is
// larger there, the stage has the width of the window, a trait has one of
// five widths, and four colours of before gave way to those of the line.
//
// The pictures with a text have a second reference, made on the Mac
// (references/macos/): its font engine draws the edges of the letters a
// little differently — in the recipe of 2 November 2026, by up to 102
// levels, on at most 1 217 pixels of 432 234. THE FOUR OF THE MAC ARE NOT
// MADE YET FOR THE PEBBLES: they are those of Linux, put there on 12
// November 2026 so that the Mac compares pictures of the right size. Its
// recipe will refuse them at the letters: keep the pictures it paints
// (test/failures/), look at them, and run it again.
//
// The references are painted on Linux, on an x86-64 processor, and are
// compared there pixel for pixel, as on every x86-64 machine. Another
// processor rounds the edge of a shape another way: on Windows on ARM64,
// at step G1, 57 pixels of the 979 200 of the garden without its text
// (05) differed, at this new size of the sheet. Away from x86-64 a
// picture may differ from a reference painted on x86-64 by up to
// [_edgeTolerance] of its pixels; a reference painted on the machine
// itself (references/macos/) is still compared pixel for pixel.
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math' as math;

import 'package:edupaint_flutter_study/coloring_pages.dart';
import 'package:edupaint_flutter_study/country_signs.dart';
import 'package:edupaint_flutter_study/galets.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/text_layout.dart';
import 'package:edupaint_flutter_study/view_transform.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_files.dart';
import 'support/studio_driver.dart';

final _sheet = find.byKey(const Key('sheetPicture'));
final _surface = find.byKey(const Key('drawingSurface'));

class _Studio {
  _Studio(this.tester);
  final WidgetTester tester;
  double _width = 1200, _height = 800;

  Future<void> start() async {
    // The same marks of « Magie » whichever test drew before.
    debugMarkSeeds = () => math.Random(11);
    addTearDown(() => debugMarkSeeds = null);
    tester.view.devicePixelRatio = 1;
    // The window of the pictures of the App Store for the Mac: its palette
    // shows every colour used here.
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EduPaintApp(
        files: MemoryFiles(),
        recoveryStorage: MemoryRecovery(),
        // The same pot on every machine: in France, it closes small gaps.
        countrySigns: () async => CountrySigns(codes: const ['FR']),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish() => tester.pumpWidget(const SizedBox.shrink());

  // The window is a wide one: the studio of the pebbles (Color 1.2). The
  // driver knows what each of them opens — the choices of a tool, the
  // shades of a colour, « Mon dessin ».
  late final _driver = StudioDriver(tester);

  Future<void> tap(String key) => _driver.tap(key);

  Future<void> colour(int rgb) => tap('color-${rgb.toRadixString(16)}');

  /// The width of the brush: the dot, of the five, that lies at [share] of
  /// their row.
  Future<void> brushWidth(double share) =>
      tap('width-${(share * (galetWidths.length - 1)).round()}');

  /// Where the point ([x], [y]) of the sheet lies on the screen, the whole
  /// sheet in view.
  Offset at(double x, double y) {
    final size = tester.getSize(_surface);
    final view = ViewTransform.fit(
      viewWidth: size.width,
      viewHeight: size.height,
      padding: 28,
      documentWidth: _width,
      documentHeight: _height,
    );
    return tester.getCenter(_surface) +
        Offset((x - _width / 2) * view.scale, (y - _height / 2) * view.scale);
  }

  Future<void> click(double x, double y) async {
    await tester.tapAt(at(x, y));
    await tester.pumpAndSettle();
  }

  Future<TestGesture> press(double x, double y) =>
      tester.startGesture(at(x, y), kind: PointerDeviceKind.mouse);

  Future<void> drag(List<Offset> points) async {
    final gesture = await press(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      await gesture.moveTo(at(point.dx, point.dy));
    }
    await gesture.up();
    // The mouse leaves: nothing hovers over the pictures.
    await gesture.removePointer();
    await tester.pumpAndSettle();
  }

  Future<void> shape(
    String tool,
    int stroke,
    int? fill,
    Offset a,
    Offset b,
  ) async {
    await tap('tool-$tool');
    // A line has an outline only: no choice between outline and inside.
    if (find.byKey(const Key('paint-target-stroke')).evaluate().isNotEmpty) {
      await tap('paint-target-stroke');
    }
    await colour(stroke);
    if (fill != null) {
      await tap('paint-target-fill');
      await colour(fill);
    }
    await drag([a, (a + b) / 2, b]);
  }

  Future<void> stamp(String name, int rgb, double x, double y) async {
    await tap('tool-stamp');
    await tap('chooseStamp');
    await tap('stamp-$name');
    await colour(rgb);
    await tap('size-large');
    await click(x, y);
  }

  /// Traits of three widths and colours that cross, a dot, a wave.
  Future<void> traits() async {
    await tap('tool-stroke');
    await brushWidth(0.8);
    await colour(0xe83d48);
    await drag([
      for (var step = 0; step <= 30; step++)
        Offset(120 + step * 32.0, 200 + 120 * math.sin(step / 4)),
    ]);
    await brushWidth(0.45);
    await colour(0x3370d1);
    await drag([
      for (var step = 0; step <= 30; step++)
        Offset(140 + step * 30.0, 620 - step * 14.0),
    ]);
    await brushWidth(0.1);
    await colour(0x2f854a);
    await drag([
      for (var step = 0; step <= 60; step++)
        Offset(
          600 + 260 * math.cos(step / 9.5),
          400 + 200 * math.sin(step / 9.5),
        ),
    ]);
    await brushWidth(0.95);
    await colour(0xeebf4e);
    await click(1000, 650);
  }

  /// Lines, rectangles and ovals, outlined and filled.
  Future<void> shapes() async {
    await shape(
      'line',
      0x3370d1,
      null,
      const Offset(80, 80),
      const Offset(520, 300),
    );
    await shape(
      'rectangle',
      0xe83d48,
      null,
      const Offset(620, 80),
      const Offset(1100, 300),
    );
    await shape(
      'rectangle',
      0x2f854a,
      0xa8d8f0,
      const Offset(80, 420),
      const Offset(500, 720),
    );
    await shape(
      'ellipse',
      0x79513e,
      0xeebf4e,
      const Offset(600, 400),
      const Offset(1120, 740),
    );
  }

  /// The garden of the pictures of the App Store: shapes, stamps, a text.
  Future<void> garden() async {
    await shape(
      'rectangle',
      0xa8d8f0,
      0xa8d8f0,
      const Offset(14, 14),
      const Offset(1186, 540),
    );
    await shape(
      'rectangle',
      0x4db266,
      0x4db266,
      const Offset(14, 540),
      const Offset(1186, 786),
    );
    await stamp('soleil', 0xeebf4e, 1030, 140);
    await stamp('maison', 0xe83d48, 300, 450);
    await stamp('arbre', 0x2f854a, 760, 440);
    await stamp('fleur', 0xc96d93, 130, 690);
    await tap('tool-text');
    await colour(0xe83d48);
    await click(40, 40);
    await tester.enterText(find.byKey(const Key('textField')), 'Mon jardin');
    await tester.pumpAndSettle();
    await tap('confirmText');
  }

  /// Presses the pot at ([x], [y]) and waits for what it pours: on the
  /// paper it reads the drawing as an image, made outside the test's clock.
  Future<void> pour(double x, double y) async {
    await tester.tapAt(at(x, y));
    await tester.pump();
    final pouring = find.byKey(const Key('pouring'));
    for (var attempt = 0; attempt < 300; attempt++) {
      if (pouring.evaluate().isEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(pouring, findsNothing);
    await tester.pumpAndSettle();
  }

  /// What Color 1.1 adds to the sheet: the magic of « Magie », a star of
  /// « Formes », a loop of the brush that the pot fills with a gradient on
  /// the paper, the round pot on a shape, and a stamp turned and mirrored.
  Future<void> newTools() async {
    await tap('tool-magic');
    await tap('magic-rainbow');
    await drag([
      for (var step = 0; step <= 24; step++)
        Offset(90 + step * 18.0, 680 - 90 * math.sin(step / 7.6)),
    ]);
    await tap('magic-grass');
    await colour(0x2f854a);
    await drag([
      const Offset(60, 770),
      const Offset(340, 770),
      const Offset(620, 770),
    ]);
    await tap('magic-bricks');
    await colour(0xe83d48);
    await drag([
      const Offset(700, 120),
      const Offset(900, 120),
      const Offset(1120, 120),
    ]);
    await tap('tool-shapes');
    await tap('shape-star');
    await colour(0xeebf4e);
    await drag([
      const Offset(720, 260),
      const Offset(820, 360),
      const Offset(940, 480),
    ]);
    // The round pot inside the star.
    await tap('tool-fill');
    await tap('pour-radial');
    await colour(0xe83d48);
    await click(830, 380);
    // A loop of the brush, filled with a gradient where it is paper.
    await tap('tool-stroke');
    await brushWidth(0.3);
    await colour(0x3370d1);
    await drag([
      for (var step = 0; step <= 48; step++)
        Offset(
          330 + 170 * math.cos(step / 7.5),
          330 + 130 * math.sin(step / 7.5),
        ),
    ]);
    await tap('tool-fill');
    await tap('pour-linear');
    await colour(0xeebf4e);
    await pour(330, 330);
    // A stamp turned twice and mirrored.
    await tap('tool-stamp');
    await tap('chooseStamp');
    await tap('stamp-poisson');
    await colour(0x3370d1);
    await tap('size-large');
    await tap('turnStamp');
    await tap('turnStamp');
    await tap('mirrorStamp');
    await click(1040, 640);
  }

  Future<void> page(String key) async {
    final page = ColoringPages.all.singleWhere((page) => page.key == key);
    await tap('newProject');
    await tap('page-$key');
    _width = page.width.toDouble();
    _height = page.height.toDouble();
  }

  /// [text]: the picture shows a text. The font engine of the system draws
  /// its glyphs (FreeType on Linux, Core Text on the Mac), each a little
  /// differently at the edges of the letters: such a picture has a
  /// reference of its own on the Mac, in references/macos/, made there.
  /// Every other pixel is the same on both (05, the garden without its
  /// text, has one reference for both). Elsewhere a picture with a text is
  /// not compared yet: no reference of its glyphs was made there.
  Future<void> expectPicture(String name, {bool text = false}) async {
    await tester.pump();
    if (text && !Platform.isLinux && !Platform.isMacOS) return;
    final folder = text && Platform.isMacOS ? 'references/macos' : 'references';
    await expectLater(_sheet, matchesGoldenFile('$folder/$name.png'));
  }
}

/// The share of the pixels of a picture that may differ, away from x86-64,
/// from a reference painted on x86-64: five in ten thousand — the edges
/// of a few shapes, never a shape.
const _edgeTolerance = .0005;

/// Whether this processor is the one the references were painted on.
/// COLOR_REFERENCES_AS_ELSEWHERE, set to anything, says no: to try on
/// x86-64 the comparison that another processor gets.
bool get _paintsAsTheReferences =>
    Platform.environment['COLOR_REFERENCES_AS_ELSEWHERE'] == null &&
    const {Abi.linuxX64, Abi.windowsX64, Abi.macosX64}.contains(Abi.current());

/// Compares as flutter_test does, but lets a picture differ from a
/// reference of x86-64 by [_edgeTolerance] of its pixels.
class _EdgeTolerantComparator extends LocalFileComparator {
  _EdgeTolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    final ownReference = golden.path.contains('macos/');
    if (result.passed ||
        (!ownReference && result.diffPercent <= _edgeTolerance)) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  setUpAll(() async {
    final bytes = File('fonts/DejaVuSans.ttf').readAsBytesSync();
    final loader = FontLoader(colorTextFontFamily)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    if (!_paintsAsTheReferences) {
      final exact = goldenFileComparator;
      addTearDown(() => goldenFileComparator = exact);
      goldenFileComparator = _EdgeTolerantComparator(
        (exact as LocalFileComparator).basedir.resolve(
          'reference_images_test.dart',
        ),
      );
    }
  });

  testWidgets('traits, a dot and a wave', (tester) async {
    final studio = _Studio(tester);
    await studio.start();
    await studio.traits();
    await studio.expectPicture('01-traits');
    await studio.finish();
  }, skip: !available);

  testWidgets('shapes, outlined and filled', (tester) async {
    final studio = _Studio(tester);
    await studio.start();
    await studio.shapes();
    await studio.expectPicture('02-formes');
    await studio.finish();
  }, skip: !available);

  testWidgets('the objects of 1.1, then a trait cut by the eraser', (
    tester,
  ) async {
    final studio = _Studio(tester);
    await studio.start();
    await studio.newTools();
    await studio.expectPicture('15-outils-1.1');
    // The eraser cuts the loop where it rubs, and Annuler mends it.
    await studio.tap('tool-eraser');
    await studio.drag([const Offset(480, 230), const Offset(520, 330)]);
    await studio.expectPicture('16-gomme-coupe');
    await studio.tap('undo');
    await studio.expectPicture('15-outils-1.1');
    await studio.finish();
  }, skip: !available);

  testWidgets('a garden, then an element erased, undone and redone', (
    tester,
  ) async {
    final studio = _Studio(tester);
    await studio.start();
    await studio.garden();
    await studio.expectPicture('03-jardin', text: true);
    await studio.tap('tool-eraser');
    await studio.click(300, 450);
    await studio.expectPicture('04-jardin-sans-maison', text: true);
    await studio.tap('undo');
    await studio.expectPicture('03-jardin', text: true);
    await studio.tap('undo');
    await studio.expectPicture('05-jardin-sans-texte');
    await studio.tap('redo');
    await studio.expectPicture('03-jardin', text: true);
    await studio.finish();
  }, skip: !available);

  testWidgets('the garden zoomed in, the sheet moved', (tester) async {
    final studio = _Studio(tester);
    await studio.start();
    await studio.garden();
    await studio.tap('zoomIn');
    await studio.tap('zoomIn');
    await studio.expectPicture('06-jardin-zoom', text: true);
    // The hand moves the sheet: a third of the view to the right.
    await studio.tap('panPage');
    final centre = tester.getCenter(_surface);
    final gesture = await tester.startGesture(centre);
    await gesture.moveTo(centre + const Offset(150, 40));
    await gesture.up();
    await tester.pumpAndSettle();
    await studio.expectPicture('07-jardin-deplace', text: true);
    await studio.finish();
  }, skip: !available);

  testWidgets('an element taken, then dragged', (tester) async {
    final studio = _Studio(tester);
    await studio.start();
    await studio.shapes();
    await studio.tap('tool-select');
    await studio.click(1000, 600);
    await studio.expectPicture('08-choisi');
    final gesture = await studio.press(1000, 600);
    await gesture.moveTo(studio.at(900, 520));
    await tester.pump();
    await studio.expectPicture('09-choisi-glisse');
    await gesture.up();
    await gesture.removePointer();
    await tester.pumpAndSettle();
    await studio.expectPicture('10-choisi-pose');
    await studio.finish();
  }, skip: !available);

  testWidgets('a trait being drawn on the layer under another', (tester) async {
    final studio = _Studio(tester);
    await studio.start();
    await studio.shape(
      'rectangle',
      0x3370d1,
      0xa8d8f0,
      const Offset(200, 150),
      const Offset(700, 550),
    );
    await studio.tap('layersButton');
    await studio.tap('addLayer');
    await studio.tap('closeLayers');
    await studio.shape(
      'ellipse',
      0xe83d48,
      0xeebf4e,
      const Offset(450, 300),
      const Offset(1000, 700),
    );
    // Back to the first layer: the trait goes under the oval.
    await studio.tap('layersButton');
    await studio.tap('layer-select-0');
    await studio.tap('closeLayers');
    await studio.tap('tool-stroke');
    await studio.brushWidth(0.8);
    await studio.colour(0x2f854a);
    final gesture = await studio.press(100, 500);
    for (var step = 1; step <= 20; step++) {
      await gesture.moveTo(studio.at(100 + step * 50.0, 500 - step * 8.0));
      await tester.pump();
    }
    await studio.expectPicture('11-trait-sous-un-calque');
    await gesture.up();
    await gesture.removePointer();
    await tester.pumpAndSettle();
    await studio.expectPicture('12-trait-pose-sous-un-calque');
    await studio.finish();
  }, skip: !available);

  testWidgets('the first click of a line, and where the pointer is', (
    tester,
  ) async {
    final studio = _Studio(tester);
    await studio.start();
    await studio.traits();
    await studio.tap('tool-line');
    await studio.colour(0x9385bc);
    await studio.click(200, 700);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: studio.at(700, 150));
    await mouse.moveTo(studio.at(800, 120));
    await tester.pump();
    await studio.expectPicture('13-ligne-en-deux-clics');
    await mouse.removePointer();
    await studio.finish();
  }, skip: !available);

  testWidgets('a colouring page being coloured, on a coloured sheet', (
    tester,
  ) async {
    final studio = _Studio(tester);
    await studio.start();
    await studio.page('dinosaure');
    await studio.tap('tool-fill');
    for (final (point, rgb) in const [
      (Offset(31, 30), 0xa8d8f0),
      (Offset(721, 563), 0x4db266),
      (Offset(650, 141), 0xeebf4e),
      (Offset(950, 309), 0xe83d48),
    ]) {
      await studio.colour(rgb);
      await studio.click(point.dx, point.dy);
    }
    await studio.expectPicture('14-coloriage');
    await studio.finish();
  }, skip: !available);
}
