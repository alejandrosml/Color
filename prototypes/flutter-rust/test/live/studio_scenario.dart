// SPDX-License-Identifier: MIT
// A recipe of the studio played inside the application itself, on the real
// engine and in the real window of the system it is built for. `flutter test`
// does not run it (its name does not end in _test.dart): it is built as the
// entry point of the application,
//
//   flutter build linux --profile -t test/live/studio_scenario.dart
//
// and launched with COLOR_SCENARIO_DIR set to a new folder. The scripts of
// scripts/linux-desktop do both and take the pictures.
//
// The gestures are made by the test framework inside the program: no key or
// pointer of the system is driven, and the real devices are ignored while it
// runs. Files are really written, by the application's own code, in the real
// folders that the system gives it; only the native file panels are replaced
// by scripted answers, through the seams of StudioFiles.
//
// The scenario cannot look at the screen. At each stage it writes
// `shots/<name>.request` and waits for `shots/<name>.done`, so that a script
// outside takes a passive picture of the display. Without such a script it
// goes on after a short wait. In the same way `shots/<name>.resize` holds a
// width and a height that the script asks the window manager for: the
// program does not resize itself. And `shots/<name>.print` says that the
// print dialog of the system is about to open: the script outside answers
// whether it can ask the window manager to close it, takes its picture when
// it is there, has it closed, and says so in `shots/<name>.closed`. Nothing
// is ever confirmed in that dialog: nothing is printed.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/app_folders.dart';
import 'package:edupaint_flutter_study/decor_gaze.dart';
import 'package:edupaint_flutter_study/decor_motion.dart';
import 'package:edupaint_flutter_study/decor_view.dart';
import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/galets.dart';
import 'package:edupaint_flutter_study/gallery_storage.dart';
import 'package:edupaint_flutter_study/language.dart';
import 'package:edupaint_flutter_study/licences.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/options_dialog.dart';
import 'package:edupaint_flutter_study/recovery_location.dart';
import 'package:edupaint_flutter_study/replay_dialog.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_files.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_painters.dart';
import 'package:edupaint_flutter_study/studio_sounds.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The start of Color, timed against its budget (Q-03 of the retrospective
  // of October 2026): the moment of main() on the clock of the timeline,
  // which the engine times its frames with, how long the process had run
  // then, and the first frame that the engine rasterizes.
  final mainAt = developer.Timeline.now;
  final runningBeforeMain = _processAgeMilliseconds();
  final binding = LiveTestWidgetsFlutterBinding.ensureInitialized();
  ui.FrameTiming? firstFrame;
  void firstFrameDrawn(List<ui.FrameTiming> timings) {
    if (firstFrame != null || timings.isEmpty) return;
    firstFrame = timings.reduce(
      (a, b) => a.frameNumber <= b.frameNumber ? a : b,
    );
    binding.removeTimingsCallback(firstFrameDrawn);
  }

  binding.addTimingsCallback(firstFrameDrawn);
  final folder = Platform.environment['COLOR_SCENARIO_DIR'];
  // Windows cannot be told a language for one program: the script outside
  // names the one of the scenario, which is written in French.
  if (Platform.environment['COLOR_SCENARIO_LANGUAGE'] == 'fr') {
    debugDeviceLanguage = AppLanguage.french;
  }

  testWidgets('the studio, played on the real engine', (tester) async {
    if (folder == null || folder.isEmpty) {
      fail('COLOR_SCENARIO_DIR names the folder of the scenario.');
    }
    // The decor of the universe (Color 1.2) stands still while the
    // scenario plays: one that moves never lets the studio settle, and
    // every step waits for that. Its movement has a step of its own, at
    // the end. And its hour is fixed — the afternoon — so that the
    // pictures and the frames of two runs can be compared; the last traits
    // are drawn at night, under the lamp, which costs the most to paint.
    debugDecorStill = true;
    debugDecorNow = () => DateTime(2026, 11, 12, 14, 30);
    // Where its images take long, a decor beats more slowly (Color 1.2):
    // not here, where each image that is timed must be one of a decor that
    // moved — thirty a second, whatever they cost.
    debugDecorBeat = DecorView.period;
    addTearDown(() {
      debugDecorStill = false;
      debugDecorNow = null;
      debugDecorBeat = null;
    });
    final root = Directory(folder);
    final shots = Directory('${root.path}/shots')..createSync(recursive: true);
    final drawings = Directory('${root.path}/Dessins')
      ..createSync(recursive: true);
    final project = '${drawings.path}/Recette.edupaint';
    final pngPath = '${drawings.path}/Recette.png';
    final svgPath = '${drawings.path}/Recette.svg';

    final steps = <Map<String, Object?>>[];
    final pictures = <Map<String, Object?>>[];
    final panels = <Map<String, Object?>>[];
    final record = <String, Object?>{
      'scope':
          'Gestures made by the test framework inside the program, on the '
          'real engine and window; no system key or pointer event; native '
          'file panels replaced by scripted answers.',
      'operating_system': Platform.operatingSystem,
      'operating_system_version': Platform.operatingSystemVersion,
      'executable': Platform.resolvedExecutable,
      'steps': steps,
      'pictures': pictures,
      'panels': panels,
    };

    // The number of the last frame that the engine says it has drawn: asked
    // for from the start, because the engine only measures frames built
    // while somebody listens.
    var lastFrameDrawn = -1;
    // The time each frame took to build and to rasterize, in microseconds,
    // and when its rasterization ended, by its number; those of the frames
    // from the press of each trait to the end of its settling are measured
    // against the budgets (Q-03), and the first frame of Color itself.
    final frameTimes = <int, (int, int, int)>{};
    final traitFrames = <(int, int)>[];
    // The step that drew each of them, to tell their frames apart.
    final traitSteps = <String>[];
    var stepNow = '';
    // The frames of the decor while it moves, apart: no budget yet. And
    // those of a decor that is looked at on the whole window, which moves
    // as much as it can.
    (int, int)? decorFrames;
    (int, int)? gazeFrames;
    // In the studio of the pebbles (Color 1.2, a wide window), whose decor
    // has the whole window: a long trait by day, the same at night, and the
    // decor that moves around the sheet. Apart from the traits of the
    // budgets, so that those stay the traits of the steps before.
    final pebbleDayFrames = <(int, int)>[];
    final pebbleNightFrames = <(int, int)>[];
    (int, int)? pebbleDecorFrames;
    // The last frame built before Color is: the frames of the test
    // framework come before it.
    int? beforeColor;
    void framesDrawn(List<ui.FrameTiming> timings) {
      for (final timing in timings) {
        if (timing.frameNumber > lastFrameDrawn) {
          lastFrameDrawn = timing.frameNumber;
        }
        frameTimes[timing.frameNumber] = (
          timing.buildDuration.inMicroseconds,
          timing.rasterDuration.inMicroseconds,
          timing.timestampInMicroseconds(ui.FramePhase.rasterFinish),
        );
      }
    }

    binding.addTimingsCallback(framesDrawn);
    addTearDown(() => binding.removeTimingsCallback(framesDrawn));

    // Answers of the native panels, in the order the scenario asks for them.
    final saveAnswers = <String?>[];
    final openAnswers = <String?>[];
    final files = StudioFiles(
      saveChooser:
          ({
            required String suggestedName,
            required String? initialDirectory,
            required List<XTypeGroup> acceptedTypeGroups,
            required String confirmButtonText,
          }) async {
            panels.add({
              'panel': 'save',
              'suggested_name': suggestedName,
              'initial_directory': initialDirectory,
              'button': confirmButtonText,
              'types': [
                for (final group in acceptedTypeGroups) ...?group.extensions,
              ],
            });
            return saveAnswers.removeAt(0);
          },
      openChooser:
          ({
            required String? initialDirectory,
            required List<XTypeGroup> acceptedTypeGroups,
            required String confirmButtonText,
          }) async {
            panels.add({
              'panel': 'open',
              'initial_directory': initialDirectory,
              'button': confirmButtonText,
              'types': [
                for (final group in acceptedTypeGroups) ...?group.extensions,
              ],
            });
            return openAnswers.removeAt(0);
          },
      documentsDirectory: () async => drawings.path,
      destinationSession: StudioDestinationSession(),
    );

    Future<void> settle() =>
        tester.pumpAndSettle(const Duration(milliseconds: 16));

    /// Waits on the real clock: files are written by workers of the program.
    Future<void> until(
      String what,
      bool Function() ready, {
      Duration limit = const Duration(seconds: 30),
      bool thenSettle = true,
    }) async {
      final watch = Stopwatch()..start();
      while (!ready()) {
        if (watch.elapsed > limit) fail('Waited too long for: $what');
        await tester.pump(const Duration(milliseconds: 25));
      }
      if (thenSettle) await settle();
    }

    /// Waits until the engine reports that it has drawn the frame built
    /// last. Building a frame is not showing it: a software renderer can
    /// spend a few hundred milliseconds on the first frame of a new layout,
    /// and a picture taken at once would show the frame before. Goes on
    /// after three seconds when the engine reports nothing.
    Future<void> shown() async {
      final built = tester.platformDispatcher.frameData.frameNumber;
      final watch = Stopwatch()..start();
      while (lastFrameDrawn < built &&
          watch.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    Future<void> shot(String name) async {
      await tester.pump();
      await shown();
      final done = File('${shots.path}/$name.done');
      File('${shots.path}/$name.request').writeAsStringSync('');
      final watch = Stopwatch()..start();
      while (!done.existsSync() && watch.elapsed < const Duration(seconds: 6)) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      pictures.add({'name': name, 'taken': done.existsSync()});
    }

    Size windowSize() =>
        tester.view.physicalSize / tester.view.devicePixelRatio;

    /// Asks the script outside to request a window whose content is [width]
    /// by [height]; false when nobody answers or no window manager is there.
    Future<bool> askWindowSize(String name, int width, int height) async {
      final done = File('${shots.path}/$name.done');
      File('${shots.path}/$name.resize').writeAsStringSync('$width $height');
      final watch = Stopwatch()..start();
      while (!done.existsSync() && watch.elapsed < const Duration(seconds: 6)) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      return done.existsSync() && done.readAsStringSync().trim() == 'resized';
    }

    /// Waits until the window has kept one size for half a second, then lays
    /// the studio out at that size.
    Future<Size> windowSettled() async {
      var size = windowSize();
      final still = Stopwatch()..start();
      final total = Stopwatch()..start();
      while (still.elapsed < const Duration(milliseconds: 500)) {
        if (total.elapsed > const Duration(seconds: 15)) {
          fail('The window keeps changing its size.');
        }
        await tester.pump(const Duration(milliseconds: 40));
        final now = windowSize();
        if (now != size) {
          size = now;
          still.reset();
        }
      }
      await binding.setSurfaceSize(size);
      await settle();
      return size;
    }

    Future<void> step(String name, Future<Object?> Function() body) async {
      stepNow = name;
      final watch = Stopwatch()..start();
      try {
        final detail = await body();
        final thrown = tester.takeException();
        if (thrown != null) fail('The interface reported: $thrown');
        steps.add({
          'name': name,
          'passed': true,
          'milliseconds': watch.elapsedMilliseconds,
          'detail': ?detail,
        });
      } catch (error, stack) {
        steps.add({
          'name': name,
          'passed': false,
          'milliseconds': watch.elapsedMilliseconds,
          'error': '$error',
          'stack': '$stack',
        });
        rethrow;
      }
    }

    Finder byKey(String key) => find.byKey(Key(key));

    bool inView(String key) => byKey(key).evaluate().isNotEmpty;

    /// Whether the pebbles stand in two rails beside the sheet: the
    /// smallest window. A wider one has a line.
    bool rails() => inView('galetLeftRail');

    /// What is done with the whole drawing waits in « Mon dessin », with
    /// the last thing that happened to it: a panel above a line, a menu
    /// between two rails.
    const inMyDrawing = {
      'newProject',
      'openProject',
      'openGallery',
      'importImage',
      'exportImage',
      'printDrawing',
      'showHelp',
      'openOptions',
      'aboutColor',
    };
    const inTheMenuOfRails = {
      'replayDrawing',
      'layersButton',
      'zoomOut',
      'zoomIn',
      'panPage',
      'fitPage',
      'openUniverses',
    };
    // What « lequel » opens stays open after these.
    const keepsPanelOpen = {
      'fillShapeCheckbox',
      'paint-target-stroke',
      'paint-target-fill',
    };

    /// What a button of the pebbles does when it is pressed; null when it
    /// does not answer.
    VoidCallback? onPressed(String key) => switch (tester.widget(byKey(key))) {
      GaletButton(:final onPressed) => onPressed,
      GaletPictureButton(:final onPressed) => onPressed,
      GaletSaveButton(:final onPressed) => onPressed,
      ButtonStyleButton(:final onPressed) => onPressed,
      final other => throw StateError('$key is not a button: $other'),
    };

    Future<void> openMyDrawing() async {
      if (inView('galetPanel-drawing') || inView('phoneMenuDialog')) return;
      await tester.tap(byKey('myDrawing'));
      await settle();
      expect(
        inView('galetPanel-drawing') || inView('phoneMenuDialog'),
        isTrue,
        reason: '« Mon dessin » is open',
      );
    }

    /// Puts an open panel of the pebbles away, as a press beside it does.
    Future<void> closePanel() async {
      if (!inView('galetPanelBarrier')) return;
      // In the middle of the top edge: no pebble stands there.
      await tester.tapAt(Offset(windowSize().width / 2, 2));
      await settle();
      expect(byKey('galetPanelBarrier'), findsNothing);
    }

    /// Opens what holds the control [key], as a child does, and gives the
    /// key to press: « Mon dessin », the size, « lequel », the shades of a
    /// colour, every colour — or, between two rails, the drawer and the
    /// colours.
    Future<String> reveal(String key) async {
      if (inView(key)) return key;
      Future<void> open(String button) async {
        await tester.tap(byKey(button));
        await settle();
      }

      if (inMyDrawing.contains(key) ||
          (rails() && inTheMenuOfRails.contains(key))) {
        await openMyDrawing();
        return key;
      }
      if (key.startsWith('color-')) {
        if (rails() && !inView('galetPanel-colours')) await open('railColour');
        if (inView(key)) return key;
        final rgb = int.parse(key.substring(6), radix: 16);
        var holder = galetColours[galetFamilyOf(rgb)!].rgb;
        if (!inView('color-${holder.toRadixString(16)}')) {
          holder = switch (holder) {
            0xffffff => 0x1a1a1a,
            0x79513e => 0xef9439,
            0xf4b7cf => 0xe83d48,
            _ => 0x3370d1,
          };
        }
        await tester.longPress(byKey('color-${holder.toRadixString(16)}'));
        await settle();
        return 'nuance-${key.substring(6)}';
      }
      if (key == 'pickPaintColor' || key == 'morePaintColors') {
        if (rails() && !inView('everyColour')) await open('railColour');
        await open('everyColour');
        return key;
      }
      final setting =
          key.startsWith('width-') ||
          key.startsWith('size-') ||
          key.startsWith('brush-');
      if (rails()) {
        if (key.startsWith('tool-') && !inView(key)) {
          await open('toolDrawer');
          if (inView('drawer-$key')) return 'drawer-$key';
          // A choice of « Formes » : its button first.
          await open('drawer-tool-shapes');
        }
        if (!inView('galetPanel-drawer')) await open('toolDrawer');
        return key;
      }
      await open(setting ? 'galetSize' : 'galetWhich');
      return key;
    }

    Future<void> tap(String key) async {
      final pressed = await reveal(key);
      final control = byKey(pressed);
      expect(control, findsOneWidget, reason: key);
      await tester.ensureVisible(control);
      await settle();
      await tester.tap(control);
      await settle();
      if (keepsPanelOpen.contains(key)) await closePanel();
    }

    final surface = byKey('drawingSurface');
    var sheetWidth = 1200.0;
    var sheetHeight = 800.0;

    /// Where a point of the sheet lies in the window, when the whole
    /// sheet is shown.
    Offset at(double x, double y) {
      final sheet = tester.getRect(byKey('sheetAtRest'));
      return sheet.topLeft +
          Offset(x * sheet.width / sheetWidth, y * sheet.height / sheetHeight);
    }

    Future<void> click(double x, double y) async {
      await tester.tapAt(at(x, y));
      await settle();
    }

    Future<void> drag(List<Offset> through, {List<(int, int)>? into}) async {
      final from = tester.platformDispatcher.frameData.frameNumber;
      final gesture = await tester.startGesture(
        at(through.first.dx, through.first.dy),
      );
      for (final point in through.skip(1)) {
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveTo(at(point.dx, point.dy));
      }
      await gesture.up();
      await settle();
      (into ?? traitFrames).add((
        from + 1,
        tester.platformDispatcher.frameData.frameNumber,
      ));
      if (into == null) traitSteps.add(stepNow);
    }

    /// What the drawing holds and whether it is saved, as the studio says
    /// it on « Mon dessin », to whoever cannot read the screen too.
    String? caption() {
      if (!inView('myDrawing')) return null;
      final label = tester.widget<GaletButton>(byKey('myDrawing')).label;
      return label.substring(label.indexOf(':') + 1).trim();
    }

    int shownCount() {
      final text = caption();
      expect(text, matches(RegExp(r'^\d+ éléments? · ')));
      return int.parse(text!.substring(0, text.indexOf(' ')));
    }

    bool holds(int elements) =>
        caption()?.startsWith(RegExp('$elements éléments? · ')) ?? false;

    bool dirty() => caption()!.contains('modifications non enregistrées');

    /// What the sheet paints: its elements, and the first click of a shape
    /// made of two when one waits.
    DocumentPainter painter() => tester
        .widgetList<CustomPaint>(
          find.descendant(of: surface, matching: find.byType(CustomPaint)),
        )
        .map((paint) => paint.painter)
        .whereType<DocumentPainter>()
        .single;

    int colourOf(VectorKind kind) => painter().strokes
        .map((element) => element.data)
        .singleWhere((data) => data.kind == kind)
        .rgb;

    bool studioReady() =>
        tester
            .widget<EduPaintDesktopMenu>(find.byType(EduPaintDesktopMenu))
            .onSave !=
        null;

    Map<String, Object?> describe(Uint8List bytes) {
      final document = RustDocument.fromProject(bytes);
      try {
        return {
          'format_version': bytes[8],
          'bytes': bytes.length,
          'layers': [
            for (final layer in document.layers)
              {
                'id': layer.id,
                'visible': layer.visible,
                'elements': layer.objectCount,
              },
          ],
          'elements': [
            for (final index in document.paintOrder)
              {
                'kind': document.strokes[index].kind.name,
                'layer': document.strokes[index].layer,
                'colour': document.strokes[index].rgb.toRadixString(16),
                if (document.strokes[index].fillRgb != null)
                  'inside': document.strokes[index].fillRgb!.toRadixString(16),
                if (document.strokes[index].text != null)
                  'text': document.strokes[index].text,
                if (document.strokes[index].stamp != null)
                  'stamp': document.strokes[index].stamp,
              },
          ],
        };
      } finally {
        document.dispose();
      }
    }

    Future<List<int>> pixel(ui.Image image, int x, int y) async {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final offset = (y * image.width + x) * 4;
      return List<int>.generate(4, (i) => data!.getUint8(offset + i));
    }

    var passed = false;
    try {
      late final String support;
      late final StudioOptionsStore studioOptions;
      late final String albumFolder;
      late final String recoveryFolder;

      await step('the studio starts with its own folders', () async {
        final logical = windowSize();
        // Lay the studio out at the size of the real window, pixel for pixel.
        await binding.setSurfaceSize(logical);
        // As main() starts it: the options of Color's own folder, read
        // before the first frame, and the sounds of the system.
        final options = await StudioOptionsStore.open();
        studioOptions = options;
        addTearDown(options.dispose);
        expect(options.storage, isNotNull);
        expect(options.value, StudioOptions.defaults);
        beforeColor = tester.platformDispatcher.frameData.frameNumber;
        await tester.pumpWidget(
          EduPaintApp(files: files, options: options, sounds: SystemSounds()),
        );
        await until('the studio to answer', studioReady);
        // Among the pebbles the last thing that happened is written in
        // « Mon dessin », the line under the sheet having gone.
        await openMyDrawing();
        await until(
          'the recovery to be ready',
          () => find
              .textContaining('récupération locale prête')
              .evaluate()
              .isNotEmpty,
        );
        await closePanel();
        support = (await applicationSupportFolder()).path;
        albumFolder = galleryDirectoryPath(
          support,
          windows: Platform.isWindows,
        );
        recoveryFolder = recoveryDirectoryPath(
          support,
          windows: Platform.isWindows,
        );
        expect(shownCount(), 0);
        await shot('01-studio');
        return {
          'window': '${logical.width.round()} × ${logical.height.round()}',
          'studio': rails() ? 'the pebbles, two rails' : 'the pebbles, a line',
          'device_pixel_ratio': tester.view.devicePixelRatio,
          'drawing_area':
              '${tester.getSize(surface).width.round()} × '
              '${tester.getSize(surface).height.round()}',
          'application_support': support,
        };
      });

      await step('brush, oval, rectangle with an inside, line', () async {
        await tap('tool-stroke');
        await drag(const [
          Offset(120, 690),
          Offset(350, 640),
          Offset(600, 700),
          Offset(850, 650),
          Offset(1080, 700),
        ]);
        expect(shownCount(), 1);
        // Since 1.1 the oval and the rectangle are choices of « Formes » :
        // what « lequel » opens. The scenario is the one of a wide
        // window: a line.
        expect(
          inView('galetLine'),
          isTrue,
          reason: 'a window of ${windowSize()}',
        );
        await tap('tool-shapes');
        await tap('tool-ellipse');
        await drag(const [
          Offset(880, 90),
          Offset(980, 180),
          Offset(1080, 290),
        ]);
        expect(shownCount(), 2);
        await tap('tool-rectangle');
        await tap('color-e83d48');
        await tap('paint-target-fill');
        await tap('color-eebf4e');
        await drag(const [
          Offset(180, 330),
          Offset(300, 450),
          Offset(480, 580),
        ]);
        expect(shownCount(), 3);
        await tap('tool-line');
        await tap('color-9385bc');
        await drag(const [
          Offset(620, 590),
          Offset(800, 590),
          Offset(1000, 590),
        ]);
        expect(shownCount(), 4);
        expect(dirty(), isTrue);
        await shot('02-shapes');
        return null;
      });

      await step('the eraser removes the line; undo and redo', () async {
        await tap('tool-eraser');
        await click(800, 590);
        expect(shownCount(), 3);
        await tap('undo');
        expect(shownCount(), 4);
        await tap('redo');
        expect(shownCount(), 3);
        await tap('undo');
        expect(shownCount(), 4);
        return null;
      });

      await step('a text with accents is typed and posed', () async {
        await tap('tool-text');
        await click(250, 200);
        expect(byKey('textDialog'), findsOneWidget);
        await tester.enterText(byKey('textField'), 'Vive l’été à Noël !');
        await settle();
        await shot('03-text-dialog');
        await tap('confirmText');
        expect(byKey('textDialog'), findsNothing);
        expect(shownCount(), 5);
        return null;
      });

      await step('a stamp is chosen and posed', () async {
        await tap('tool-stamp');
        // The stamps are what « lequel » opens beside its button: no
        // dialog among the pebbles.
        await tester.tap(byKey('galetWhich'));
        await settle();
        expect(byKey('galetPanel-which'), findsOneWidget);
        expect(byKey('stampDialog'), findsNothing);
        await shot('04-stamps');
        await tap('stamp-chat');
        expect(byKey('galetPanel-which'), findsNothing);
        await click(700, 400);
        expect(shownCount(), 6);
        return null;
      });

      await step('the pot fills the oval', () async {
        await tap('tool-fill');
        await tap('color-eebf4e');
        await click(980, 190);
        expect(shownCount(), 6);
        return null;
      });

      await step(
        'a second layer receives a trait and hides the first',
        () async {
          await tap('layersButton');
          expect(byKey('layersDialog'), findsOneWidget);
          await tap('addLayer');
          expect(byKey('layer-row-1'), findsOneWidget);
          await tap('closeLayers');
          await tap('tool-stroke');
          await tap('color-3370d1');
          await drag(const [
            Offset(150, 150),
            Offset(300, 100),
            Offset(450, 160),
          ]);
          expect(shownCount(), 7);
          await tap('layersButton');
          await tap('layer-visible-0');
          await shot('05-layers-first-hidden');
          await tap('closeLayers');
          await shot('06-only-second-layer');
          await tap('layersButton');
          await tap('layer-visible-0');
          await tap('closeLayers');
          return null;
        },
      );

      await step('a trait of the yellow of the rectangle', () async {
        // The pipette is for the older children, where an adult asked for
        // every colour (off by default): the yellow is taken on the line.
        expect(byKey('pickPaintColor'), findsNothing);
        expect(byKey('everyColour'), findsNothing);
        await tap('color-eebf4e');
        await tap('tool-stroke');
        await drag(const [Offset(100, 760), Offset(180, 770)]);
        expect(shownCount(), 8);
        await shot('07-drawing');
        return null;
      });

      late final Map<String, Object?> saved;
      await step('Enregistrer writes the project and its card', () async {
        saveAnswers.add(project);
        await tap('saveProject');
        await until(
          'the project to be written',
          () => File(project).existsSync() && !dirty(),
        );
        final bytes = File(project).readAsBytesSync();
        saved = describe(bytes);
        final elements = saved['elements']! as List;
        expect(elements, hasLength(8));
        // Version 6 of the format since 1.1.
        expect(saved['format_version'], 6);
        expect(
          [for (final Map element in elements) element['kind']],
          [
            'stroke',
            'ellipse',
            'rectangle',
            'line',
            'text',
            'stamp',
            'stroke',
            'stroke',
          ],
        );
        expect((elements[1] as Map)['inside'], 'eebf4e');
        expect((elements[2] as Map)['colour'], 'e83d48');
        expect((elements[2] as Map)['inside'], 'eebf4e');
        expect((elements[4] as Map)['text'], 'Vive l’été à Noël !');
        expect((elements[6] as Map)['layer'], 1);
        expect((elements[6] as Map)['colour'], '3370d1');
        expect((elements[7] as Map)['colour'], 'eebf4e');
        final card = File(
          '$albumFolder${Platform.pathSeparator}'
          '${GalleryStorage.idFor(project)}.card',
        );
        await until('the card of the album', card.existsSync);
        return {
          'project': saved,
          'card': card.path,
          'card_bytes': card.lengthSync(),
        };
      });

      await step('« Mes dessins » shows the card', () async {
        await tap('openGallery');
        expect(byKey('galleryDialog'), findsOneWidget);
        final card = byKey('gallery-open-${GalleryStorage.idFor(project)}');
        await until('the card in the album', () => card.evaluate().isNotEmpty);
        // The thumbnail is decoded by the engine: leave it the time to show.
        await tester.pump(const Duration(milliseconds: 600));
        await shot('08-gallery');
        await tap('closeGallery');
        expect(byKey('galleryDialog'), findsNothing);
        return null;
      });

      await step('PNG and SVG exports are written and read back', () async {
        saveAnswers.add(pngPath);
        await tap('exportImage');
        await shot('09-export-dialog');
        await tester.tap(byKey('exportPng'));
        await until(
          'the PNG to be written',
          () => File(pngPath).existsSync() && studioReady(),
          limit: const Duration(seconds: 60),
        );
        final png = File(pngPath).readAsBytesSync();
        final codec = await ui.instantiateImageCodec(png);
        final image = (await codec.getNextFrame()).image;
        final width = image.width;
        final height = image.height;
        // The inside of the rectangle, the paper, the filled oval.
        final inside = await pixel(
          image,
          330 * width ~/ 1200,
          455 * height ~/ 800,
        );
        final paper = await pixel(
          image,
          40 * width ~/ 1200,
          40 * height ~/ 800,
        );
        final oval = await pixel(
          image,
          980 * width ~/ 1200,
          190 * height ~/ 800,
        );
        image.dispose();
        codec.dispose();
        expect(inside, [0xee, 0xbf, 0x4e, 255]);
        expect(paper, [255, 255, 255, 255]);
        expect(oval, [0xee, 0xbf, 0x4e, 255]);

        saveAnswers.add(svgPath);
        await tap('exportImage');
        await tester.tap(byKey('exportSvg'));
        await until(
          'the SVG to be written',
          () => File(svgPath).existsSync() && studioReady(),
        );
        final svg = File(svgPath).readAsStringSync();
        expect(
          svg,
          startsWith('<?xml version="1.0" encoding="UTF-8"?>\n<svg '),
        );
        expect(svg, contains('Vive l’été à Noël !'));
        expect(svg.trimRight(), endsWith('</svg>'));
        return {
          'png': '$width × $height, ${png.length} bytes',
          'svg_bytes': svg.length,
        };
      });

      await step(
        'a new sheet, then the drawing comes back from the album',
        () async {
          await tap('newProject');
          expect(byKey('newSheetDialog'), findsOneWidget);
          await shot('10-new-sheet-dialog');
          await tap('newSheet-portrait');
          await tap('createNewSheet');
          sheetWidth = 800;
          sheetHeight = 1200;
          expect(shownCount(), 0);
          await shot('11-portrait-sheet');
          await tap('openGallery');
          final card = byKey('gallery-open-${GalleryStorage.idFor(project)}');
          await until(
            'the card in the album',
            () => card.evaluate().isNotEmpty,
          );
          await tester.tap(card);
          await until(
            'the drawing of the album',
            () =>
                byKey('galleryDialog').evaluate().isEmpty &&
                studioReady() &&
                holds(8),
          );
          sheetWidth = 1200;
          sheetHeight = 800;
          expect(shownCount(), 8);
          expect(dirty(), isFalse);
          return null;
        },
      );

      await step('Ouvrir reads the same file through the panel', () async {
        await tap('newProject');
        await tap('createNewSheet');
        expect(shownCount(), 0);
        openAnswers.add(project);
        await openMyDrawing();
        await tester.tap(byKey('openProject'));
        await until('the opened drawing', () => studioReady() && holds(8));
        expect(dirty(), isFalse);
        // Its name, which « Mon dessin » says with the last thing that
        // happened.
        await openMyDrawing();
        expect(find.textContaining('Recette'), findsWidgets);
        await closePanel();
        await shot('12-reopened');
        return null;
      });

      await step(
        'two clicks make a line; a little circle waits in between',
        () async {
          await tap('tool-line');
          await click(560, 120);
          // The first click draws nothing: it poses where the line starts.
          expect(shownCount(), 8);
          expect(dirty(), isFalse);
          final first = painter().anchor;
          expect(first, isNotNull);
          expect(first!.start.x, closeTo(560, .5));
          expect(first.start.y, closeTo(120, .5));
          await shot('12b-first-click');
          await click(760, 240);
          expect(painter().anchor, isNull);
          expect(shownCount(), 9);
          expect(dirty(), isTrue);
          await shot('12c-second-click');
          await tap('undo');
          expect(shownCount(), 8);
          expect(dirty(), isFalse);
          return null;
        },
      );

      await step(
        'a colour clicked changes the chosen rectangle at once',
        () async {
          await tap('tool-select');
          await click(330, 455);
          expect(colourOf(VectorKind.rectangle), 0xe83d48);
          // Its actions wait in a pebble above the line.
          expect(byKey('galetSelection'), findsOneWidget);
          await tap('color-4db266');
          // No button to press: the outline is green in the drawing.
          expect(byKey('applySelectionStyle'), findsNothing);
          expect(colourOf(VectorKind.rectangle), 0x4db266);
          expect(dirty(), isTrue);
          await shot('12d-recoloured-at-once');
          await tap('undo');
          expect(colourOf(VectorKind.rectangle), 0xe83d48);
          expect(dirty(), isFalse);
          return null;
        },
      );

      await step('Imprimer opens the print dialog of the system; closed there, nothing is printed', () async {
        const name = '12e-print-dialog';
        // Only somebody outside can close the dialog of the system: ask
        // first whether somebody is there.
        final answer = File('${shots.path}/$name.done');
        File('${shots.path}/$name.print').writeAsStringSync('');
        final asked = Stopwatch()..start();
        while (!answer.existsSync() &&
            asked.elapsed < const Duration(seconds: 6)) {
          await tester.pump(const Duration(milliseconds: 40));
        }
        if (!answer.existsSync() ||
            answer.readAsStringSync().trim() != 'ready') {
          return {
            'played': false,
            'reason': 'no script outside could ask a window manager to close the dialog',
          };
        }
        await openMyDrawing();
        expect(byKey('printDrawing'), findsOneWidget);
        await tester.tap(byKey('printDrawing'));
        final closed = File('${shots.path}/$name.closed');
        await until(
          'the print dialog to be seen and closed',
          closed.existsSync,
          limit: const Duration(seconds: 90),
          thenSettle: false,
        );
        await until(
          'the studio to answer again',
          studioReady,
          limit: const Duration(seconds: 30),
        );
        final outcome =
            jsonDecode(closed.readAsStringSync()) as Map<String, Object?>;
        expect(outcome['seen'], isTrue, reason: '$outcome');
        // Closed without printing: the studio neither says that the
        // drawing went to a printer nor reports a problem.
        await openMyDrawing();
        expect(find.textContaining('Impression lancée'), findsNothing);
        await closePanel();
        expect(byKey('problemMessage'), findsNothing);
        expect(shownCount(), 8);
        expect(dirty(), isFalse);
        return {'played': true, ...outcome};
      });

      await step('help, big sheet and zoom', () async {
        await tap('showHelp');
        expect(byKey('helpDialog'), findsOneWidget);
        await shot('13-help');
        await tap('closeHelp');
        // « Dessiner en grand » is offered where the sheet gains room by
        // it: among the pebbles, in a window lower than it is wide.
        final sheetBefore = tester.getRect(byKey('sheetAtRest'));
        final offered = byKey('bigSheet').evaluate().isNotEmpty;
        Rect? sheetInBig;
        if (offered) {
          await tap('bigSheet');
          sheetInBig = tester.getRect(byKey('sheetAtRest'));
          expect(sheetInBig.height, greaterThan(sheetBefore.height));
          await shot('14-big-sheet');
          await tap('bigSheet');
          expect(tester.getRect(byKey('sheetAtRest')), sheetBefore);
        }
        // « Voir toute la feuille » answers once the view has moved.
        expect(onPressed('fitPage'), isNull);
        await tap('zoomIn');
        await tap('zoomIn');
        expect(onPressed('fitPage'), isNotNull);
        await shot('15-zoomed');
        await tap('fitPage');
        expect(onPressed('fitPage'), isNull);
        return {
          'sheet':
              '${sheetBefore.width.round()} × ${sheetBefore.height.round()}',
          'big_sheet_offered': offered,
          if (sheetInBig != null)
            'sheet_in_big':
                '${sheetInBig.width.round()} × ${sheetInBig.height.round()}',
        };
      });

      await step('larger text of the system', () async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        await settle();
        // The pebbles stay: what is written follows the letters.
        expect(inView('galetLine'), isTrue);
        expect(shownCount(), 8);
        await shot('16-text-scale-1.3');
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await settle();
        expect(inView('galetLine'), isTrue);
        return null;
      });

      await step('a window smaller than the smallest is refused', () async {
        final before = windowSize();
        if (!await askWindowSize('17-smaller-window', 500, 400)) {
          return {
            'played': false,
            'reason': 'no window manager was asked by a script outside',
          };
        }
        await until(
          'the window to change',
          () => windowSize() != before,
          limit: const Duration(seconds: 10),
          thenSettle: false,
        );
        final small = await windowSettled();
        // What the window manager made of 500 × 400: the smallest content
        // that the program announces, where every tool is still in reach.
        expect(small, const Size(680, 520));
        // No line holds in a window this small: two rails beside the
        // sheet, and every tool in the drawer of the left one.
        expect(rails(), isTrue);
        expect(shownCount(), 8);
        final area = tester.getSize(byKey('sheetAtRest'));
        await shot('18-smallest-window');
        await tester.tap(byKey('toolDrawer'));
        await settle();
        expect(byKey('drawer-tool-magic'), findsOneWidget);
        await shot('19-smallest-window-drawer');
        await closePanel();
        await askWindowSize(
          '20-window-back',
          before.width.round(),
          before.height.round(),
        );
        await until(
          'the window to come back',
          () => windowSize() == before,
          limit: const Duration(seconds: 10),
          thenSettle: false,
        );
        expect(await windowSettled(), before);
        expect(inView('galetLine'), isTrue);
        return {
          'played': true,
          'asked': '500 × 400',
          'obtained': '${small.width.round()} × ${small.height.round()}',
          'form': 'two rails',
          'sheet': '${area.width.round()} × ${area.height.round()}',
        };
      });

      await step('an unsaved trait leaves a recovery copy', () async {
        await tap('tool-stroke');
        await drag(const [
          Offset(500, 300),
          Offset(560, 340),
          Offset(620, 300),
        ]);
        expect(shownCount(), 9);
        expect(dirty(), isTrue);
        final folder = Directory(recoveryFolder);
        await until(
          'the recovery copy',
          () =>
              folder.existsSync() &&
              folder.listSync().whereType<File>().any(
                (file) => !file.path.endsWith('.tmp') && file.lengthSync() > 0,
              ),
        );
        await shot('21-unsaved');
        return {
          'recovery': [
            for (final file in folder.listSync().whereType<File>())
              '${StudioFiles.fileName(file.path)} (${file.lengthSync()} bytes)',
          ],
        };
      });

      // The calculation at the door of the options, read on the screen.
      (int, int) doorNumbers() {
        final question = tester.widget<Text>(byKey('adultGateQuestion')).data!;
        final match = RegExp(r'^(\d) × (\d) = \?$').firstMatch(question);
        expect(match, isNotNull, reason: question);
        return (int.parse(match![1]!), int.parse(match[2]!));
      }

      // A result typed on the keys of the door: its second digit answers.
      Future<void> answerDoor(int result) async {
        for (final digit in '$result'.split('')) {
          await tap('adultGateDigit$digit');
        }
      }

      // The options, once the door is open, take a moment before they
      // listen: the hand that has just typed the answer is still there.
      Future<void> optionsListen() async {
        expect(byKey('optionsDialog'), findsOneWidget);
        await tester.pump(
          OptionsDialog.settling + const Duration(milliseconds: 150),
        );
        await settle();
      }

      Future<void> openOptions() async {
        await tap('openOptions');
        expect(byKey('adultGate'), findsOneWidget);
        final (first, second) = doorNumbers();
        await answerDoor(first * second);
        expect(byKey('adultGate'), findsNothing);
        await optionsListen();
      }

      Map<String, Object?> keptOptions() {
        final file = File(
          optionsFilePath(support, windows: Platform.isWindows),
        );
        if (!file.existsSync()) return const {};
        try {
          return (jsonDecode(file.readAsStringSync()) as Map)
              .cast<String, Object?>();
        } on FormatException {
          return const {};
        }
      }

      await step('Options opens at once, then behind the calculation the adult chose, not behind a wrong result', () async {
        // What the core answers when a sound is asked: 0 when it plays
        // it, 1 when this computer gives it nothing to play with.
        final coreSound = RustDocument.playSound(StudioSound.click.id);
        // By default the options open at once; the adult switches the
        // calculation on, and it keeps the door from then on.
        await tap('openOptions');
        expect(byKey('adultGate'), findsNothing);
        await optionsListen();
        await tester.ensureVisible(byKey('optionGuarded'));
        await settle();
        await tap('optionGuarded');
        await tap('closeOptions');
        expect(byKey('optionsDialog'), findsNothing);
        await tap('openOptions');
        expect(byKey('adultGate'), findsOneWidget);
        await shot('22-options-door');
        final (first, second) = doorNumbers();
        await answerDoor(first * second == 42 ? 43 : 42);
        expect(byKey('optionsDialog'), findsNothing);
        expect(byKey('adultGateWrong'), findsOneWidget);
        final (third, fourth) = doorNumbers();
        expect(third * fourth, isNot(first * second));
        await answerDoor(third * fourth);
        expect(byKey('adultGate'), findsNothing);
        await optionsListen();
        await shot('23-options');
        await tap('optionHoldFree');
        await tap('optionScreenKeyboard');
        await tap('closeOptions');
        expect(byKey('optionsDialog'), findsNothing);
        await until(
          'the options to be kept',
          () =>
              keptOptions()['holdFree'] == true &&
              keptOptions()['screenKeyboard'] == true,
        );
        return {
          'first_calculation': '$first × $second',
          'second_calculation': '$third × $fourth',
          'core_answer_to_a_sound': coreSound,
          'kept': keptOptions(),
        };
      });

      await step(
        'a trait without holding the button, a text on the keys of the screen',
        () async {
          final before = shownCount();
          await tap('tool-stroke');
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: at(300, 520));
          // A click meant as one, a moment after whatever came before.
          await tester.pump(const Duration(milliseconds: 450));
          await mouse.moveTo(at(300, 520));
          await mouse.down(at(300, 520));
          await mouse.up();
          await tester.pump(const Duration(milliseconds: 60));
          // The pointer alone, no button held.
          for (final point in const [
            Offset(380, 470),
            Offset(470, 545),
            Offset(560, 480),
          ]) {
            await mouse.moveTo(at(point.dx, point.dy));
            await tester.pump(const Duration(milliseconds: 40));
          }
          expect(shownCount(), before);
          // The companion says it in its bubble, beside « Mon dessin ».
          expect(
            find.textContaining(
              'Clique pour arrêter ton trait',
              findRichText: true,
            ),
            findsWidgets,
          );
          await shot('24-trait-without-holding');
          await mouse.down(at(560, 480));
          await mouse.up();
          await settle();
          await mouse.removePointer();
          await settle();
          expect(shownCount(), before + 1);

          await tap('tool-text');
          await click(820, 520);
          expect(byKey('textDialog'), findsOneWidget);
          expect(byKey('screenKeyboard'), findsOneWidget);
          await tap('key-capitals');
          await tap('key-O');
          await tap('key-u');
          await tap('key-i');
          await tap('keys-signs');
          await tap('key-!');
          await shot('25-screen-keyboard');
          expect(
            tester.widget<TextField>(byKey('textField')).controller!.text,
            'Oui!',
          );
          await tap('confirmText');
          expect(byKey('textDialog'), findsNothing);
          expect(shownCount(), before + 2);
          return {'elements': before + 2};
        },
      );

      await step(
        'the film redraws the drawing and leaves it as it was',
        () async {
          final before = shownCount();
          final control = byKey('replayDrawing');
          expect(control, findsOneWidget);
          await tester.ensureVisible(control);
          await settle();
          // The film moves until its end: nothing here waits for stillness
          // before it is over.
          await tester.tap(control);
          await until(
            'the film to open',
            () => byKey('replayDialog').evaluate().isNotEmpty,
            thenSettle: false,
          );
          final watch = Stopwatch()..start();
          // Frame after frame, as a screen asks for them: the clock of the
          // film only moves with the frames that are drawn.
          await until(
            'the film to be well under way',
            () => watch.elapsed > const Duration(milliseconds: 2500),
            thenSettle: false,
          );
          expect(find.text(ReplayDialog.startedStatus), findsOneWidget);
          await shot('26-film');
          await until(
            'the film to end',
            () => find.text(ReplayDialog.finishedStatus).evaluate().isNotEmpty,
            limit: const Duration(seconds: 45),
          );
          final seconds = watch.elapsedMilliseconds / 1000;
          await shot('27-film-ended');
          await tap('closeReplay');
          expect(byKey('replayDialog'), findsNothing);
          expect(shownCount(), before);
          return {'elements': before, 'seconds_until_its_end': seconds};
        },
      );

      await step('À propos says the version and lists the licences', () async {
        await tap('aboutColor');
        final version = tester.widget<Text>(byKey('aboutVersion')).data!;
        expect(version, matches(RegExp(r'^Color \d+\.\d+\.\d+ \(\d+\)$')));
        await tap('aboutLicences');
        expect(find.byType(LicensePage), findsOneWidget);
        // The licences of Flutter itself are read from the NOTICES file of
        // the bundle by the binding of an application; the binding of a test
        // registers none. Here: the file is in the bundle, and the registry
        // holds what Color adds to it.
        final notices = await rootBundle.load('NOTICES.Z');
        expect(notices.lengthInBytes, greaterThan(10000));
        final entries = await LicenseRegistry.licenses.toList();
        final names = <String>{for (final entry in entries) ...entry.packages};
        // What the core credits in its notices is listed, with Color and its
        // font. The core of the stores reads no SVG (R-01 of the
        // retrospective): no library is compiled into it, and only the
        // recordings of its sounds are credited; a core that reads SVG
        // credits usvg and the libraries it needs.
        final fromCore = <String>{
          for (final entry in coreLicenceEntries(
            RustDocument.thirdPartyNotices(),
          ))
            ...entry.packages,
        };
        expect(fromCore, contains('Sons enregistrés'));
        expect(
          names,
          containsAll(<String>{
            ...fromCore,
            'Color',
            'DejaVu Sans (police des textes)',
          }),
        );
        final readsSvg = fromCore.contains('usvg');
        if (readsSvg) {
          expect(names, containsAll(const ['roxmltree', 'tiny-skia-path']));
        }
        final opened = find.text(readsSvg ? 'usvg' : 'Sons enregistrés');
        await tester.scrollUntilVisible(
          opened,
          300,
          scrollable: find
              .descendant(
                of: find.byType(LicensePage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await settle();
        await tester.tap(opened);
        await settle();
        expect(
          find.textContaining(
            readsSvg ? 'usvg 0.48.1 — licence MIT' : 'CC0 1.0 universel',
          ),
          findsWidgets,
        );
        await shot('28-licences');
        // Out of the detail of one library when the window shows it on a
        // page of its own, then out of the page of the licences.
        while (find.byType(LicensePage).evaluate().isNotEmpty) {
          final back = find.byType(BackButton);
          expect(back, findsWidgets);
          await tester.tap(back.first);
          await settle();
        }
        await tester.tap(find.text('Revenir au dessin'));
        await settle();
        expect(byKey('aboutVersion'), findsNothing);
        return {
          'version': version,
          'core_reads_svg': readsSvg,
          'entries_added_by_color': names.length,
          'flutter_notices_in_the_bundle_bytes': notices.lengthInBytes,
        };
      });

      await step(
        'among the pebbles: a long trait by day, the same at night, the '
        'decor that moves — their frames timed',
        () async {
          // The decor of the pebbles has the whole window, and the ground
          // goes on under the line: what a trait costs there, and an image
          // of the decor that moves, measured apart from the traits of the
          // budgets. The drawing is left as it was.
          expect(inView('galetLine'), isTrue);
          final before = painter().strokes.length;
          final decor = tester.getSize(find.byKey(const Key('decor')));
          List<Offset> wave(double height) => [
            for (var i = 0; i <= 120; i++)
              Offset(
                sheetWidth * (.1 + .8 * i / 120),
                sheetHeight * (height + .12 * math.sin(i / 10)),
              ),
          ];
          // The decor looks at the hour again when the level of its
          // movement changes.
          Future<void> hour(int hours, int minutes) async {
            debugDecorNow = () => DateTime(2026, 11, 12, hours, minutes);
            await studioOptions.change(
              studioOptions.value.copyWith(decorMotion: DecorMotion.medium),
            );
            await studioOptions.change(
              studioOptions.value.copyWith(decorMotion: DecorMotion.low),
            );
            await settle();
          }

          await tap('tool-stroke');
          await drag(wave(.3), into: pebbleDayFrames);
          expect(painter().strokes.length, before + 1);
          await hour(22, 10);
          await drag(wave(.72), into: pebbleNightFrames);
          expect(painter().strokes.length, before + 2);
          await shot('28b-pebbles-at-night');
          // Three seconds of the decor as it moves by default, at night.
          debugDecorStill = false;
          await studioOptions.change(
            studioOptions.value.copyWith(decorMotion: DecorMotion.medium),
          );
          await studioOptions.change(
            studioOptions.value.copyWith(decorMotion: DecorMotion.low),
          );
          await tester.pump();
          final from = tester.platformDispatcher.frameData.frameNumber;
          for (var image = 0; image < 90; image++) {
            await tester.pump(DecorView.period);
          }
          await shown();
          final to = tester.platformDispatcher.frameData.frameNumber;
          pebbleDecorFrames = (from + 1, to);
          debugDecorStill = true;
          // The afternoon again, and the drawing as it was.
          await hour(14, 30);
          await tap('undo');
          await tap('undo');
          expect(painter().strokes.length, before);
          expect(to - from, greaterThan(30));
          return {
            'window':
                '${windowSize().width.round()} × '
                '${windowSize().height.round()}',
            'decor': '${decor.width.round()} × ${decor.height.round()}',
            'samples_of_each_trait': 121,
            'images_of_the_decor': to - from,
          };
        },
      );

      await step('the simplest interface, kept for the next launch', () async {
        await openOptions();
        await tap('level-toddler');
        await tap('closeOptions');
        expect(byKey('optionsDialog'), findsNothing);
        for (final shown in const [
          'tool-stroke',
          'tool-stamp',
          'tool-fill',
          'tool-eraser',
        ]) {
          expect(byKey(shown), findsOneWidget, reason: shown);
        }
        for (final hidden in const [
          'tool-line',
          'tool-shapes',
          'tool-rectangle',
          'tool-ellipse',
          'tool-text',
          'tool-select',
          'tool-magic',
          'showHelp',
          'layersButton',
          'bigSheet',
        ]) {
          expect(byKey(hidden), findsNothing, reason: hidden);
        }
        // Three sizes in view, and the ten colours.
        expect(byKey('brush-medium'), findsOneWidget);
        expect(find.byType(GaletSwatch), findsNWidgets(10));
        expect(byKey('replayDrawing'), findsOneWidget);
        await until(
          'the level to be kept',
          () => keptOptions()['level'] == InterfaceLevel.toddler.code,
        );
        // The same drawing, whole: nothing of it left with the interface.
        final before = painter().strokes.length;
        final drawn = DateTime.now();
        await tap('tool-stroke');
        await drag(const [
          Offset(160, 150),
          Offset(260, 110),
          Offset(360, 160),
        ]);
        expect(painter().strokes.length, before + 1);
        // The recovery copy follows: the released program is started on
        // this profile afterwards, and must offer this drawing in this
        // interface.
        final folder = Directory(recoveryFolder);
        await until(
          'the recovery copy to follow',
          () => folder.listSync().whereType<File>().any(
            (file) =>
                !file.path.endsWith('.tmp') &&
                file.lengthSync() > 0 &&
                file.lastModifiedSync().isAfter(drawn),
          ),
        );
        await shot('29-simplest-interface');
        return {'elements': before + 1, 'kept': keptOptions()};
      });

      await step('a long trait, its frames timed', () async {
        // More frames for the budgets of the frames (Q-03): a wave across
        // the sheet, a sample every 16 ms, on the drawing as it is.
        await tap('tool-stroke');
        final before = painter().strokes.length;
        await drag([
          for (var i = 0; i <= 120; i++)
            Offset(
              sheetWidth * (.1 + .8 * i / 120),
              sheetHeight * (.5 + .18 * math.sin(i / 10)),
            ),
        ]);
        expect(painter().strokes.length, before + 1);
        return {'samples': 121};
      });

      await step(
        'the same trait at night, under the lamp of the desk',
        () async {
          // Night falls on the desk by the window: the room is tinted, the
          // lamp is lit. The decor looks at the hour again when the level
          // of its movement changes.
          debugDecorNow = () => DateTime(2026, 11, 12, 22, 10);
          await studioOptions.change(
            studioOptions.value.copyWith(decorMotion: DecorMotion.medium),
          );
          await settle();
          expect(find.byKey(const Key('decor')), findsOneWidget);
          final before = painter().strokes.length;
          await drag([
            for (var i = 0; i <= 120; i++)
              Offset(
                sheetWidth * (.1 + .8 * i / 120),
                sheetHeight * (.72 + .12 * math.sin(i / 10)),
              ),
          ]);
          expect(painter().strokes.length, before + 1);
          await shot('30-night');
          return {'samples': 121};
        },
      );

      await step('the decor moves, its frames timed', () async {
        // Three seconds of the decor as it moves by default, nothing else
        // happening: what an image costs when only the curtains sway.
        debugDecorStill = false;
        await studioOptions.change(
          studioOptions.value.copyWith(decorMotion: DecorMotion.low),
        );
        await tester.pump();
        final from = tester.platformDispatcher.frameData.frameNumber;
        for (var image = 0; image < 90; image++) {
          await tester.pump(DecorView.period);
        }
        await shown();
        final to = tester.platformDispatcher.frameData.frameNumber;
        decorFrames = (from + 1, to);
        // And still again, for what waits for the studio to settle; the
        // options are left as an adult would find them, the movement at
        // its default: the released program starts on this profile next.
        debugDecorStill = true;
        await studioOptions.change(
          studioOptions.value.copyWith(decorMotion: DecorMotion.medium),
        );
        await studioOptions.change(
          studioOptions.value.copyWith(decorMotion: DecorMotion.low),
        );
        await settle();
        expect(studioOptions.value.decorMotion, DecorMotion.low);
        expect(to - from, greaterThan(30));
        return {'images': to - from};
      });

      await step(
        '« Regarder » : the desk on the whole window, its frames timed',
        () async {
          // « Choisis ton univers », then « Regarder » under the desk: its
          // decor on the whole window, at night, moving as much as it can —
          // the dearest image a decor has. The drawing is not touched.
          final before = painter().strokes.length;
          await tap('openUniverses');
          expect(byKey('watch-bureau'), findsOneWidget);
          expect(byKey('watch-classique'), findsNothing);
          // It moves from its first image: it never lets the studio settle,
          // so its images are pumped one by one.
          debugDecorStill = false;
          await tester.tap(byKey('watch-bureau'));
          for (var image = 0; image < 20; image++) {
            await tester.pump(DecorView.period);
          }
          expect(find.byType(DecorGaze), findsOneWidget);
          expect(byKey('universeDialog'), findsNothing);
          final view = tester.widget<DecorView>(
            find.descendant(
              of: find.byType(DecorGaze),
              matching: find.byType(DecorView),
            ),
          );
          expect(view.motion, DecorMotion.high);
          expect(tester.getSize(find.byType(DecorGaze)), windowSize());
          await shown();
          final from = tester.platformDispatcher.frameData.frameNumber;
          for (var image = 0; image < 90; image++) {
            await tester.pump(DecorView.period);
          }
          await shown();
          final to = tester.platformDispatcher.frameData.frameNumber;
          gazeFrames = (from + 1, to);
          // One press on the cat, at the bottom right: its card.
          final window = windowSize();
          final scale = view.layoutIn(window).scale;
          await tester.tapAt(
            Offset(
              window.width - (1061 - 989) * scale,
              window.height - (407 - 320) * scale,
            ),
          );
          await tester.pump(DecorView.period);
          expect(byKey('decorNameCard'), findsOneWidget);
          expect(find.text('Le chat'), findsOneWidget);
          await shot('31-decor-looked-at');
          // « Mon dessin » : back in the studio, the drawing as it was.
          debugDecorStill = true;
          await tester.tap(byKey('leaveDecorGaze'));
          for (var image = 0; image < 20; image++) {
            await tester.pump(DecorView.period);
          }
          await settle();
          expect(find.byType(DecorGaze), findsNothing);
          expect(surface, findsOneWidget);
          expect(painter().strokes.length, before);
          expect(to - from, greaterThan(30));
          return {'images': to - from};
        },
      );

      passed = true;
    } catch (error) {
      record['error'] = '$error';
      rethrow;
    } finally {
      record['passed'] = passed;
      // The last frames reported by the engine, then their times.
      try {
        await shown();
      } catch (_) {
        // The figures are those reported so far.
      }
      final micros = [
        for (final (first, last) in traitFrames)
          for (var number = first; number <= last; number++)
            ?frameTimes[number],
      ];
      record['frames'] = {
        'scope':
            'Frames built from the press of each trait that the scenario '
            'draws to the end of its settling, as the engine timed them '
            '(FrameTiming), in milliseconds.',
        'count': micros.length,
        if (micros.isNotEmpty) ...{
          'build_ms': _centiles([for (final (build, _, _) in micros) build]),
          'raster_ms': _centiles([for (final (_, raster, _) in micros) raster]),
        },
      };
      // The same frames trait by trait, in the order they were drawn: the
      // traits of a scenario are not all drawn in the same studio, at the
      // same hour or in the same window.
      record['frames_by_trait'] = [
        for (final (index, (first, last)) in traitFrames.indexed)
          () {
            final raster = [
              for (var number = first; number <= last; number++)
                if (frameTimes[number] case (_, final raster, _)) raster,
            ];
            return {
              'step': traitSteps[index],
              'count': raster.length,
              if (raster.isNotEmpty) 'raster_ms': _centiles(raster),
            };
          }(),
      ];
      final moving = [
        if (decorFrames case (final first, final last))
          for (var number = first; number <= last; number++)
            ?frameTimes[number],
      ];
      record['decor_frames'] = {
        'scope':
            'Frames built while the decor of the universe moves at its '
            'default level and nothing else happens, three seconds of them, '
            'at night under the lamp (FrameTiming), in milliseconds. No '
            'budget yet: a first measure.',
        'count': moving.length,
        if (moving.isNotEmpty) ...{
          'build_ms': _centiles([for (final (build, _, _) in moving) build]),
          'raster_ms': _centiles([for (final (_, raster, _) in moving) raster]),
        },
      };
      Map<String, Object?> timed(String scope, List<(int, int)> spans) {
        final times = [
          for (final (first, last) in spans)
            for (var number = first; number <= last; number++)
              ?frameTimes[number],
        ];
        return {
          'scope': scope,
          'count': times.length,
          if (times.isNotEmpty) ...{
            'build_ms': _centiles([for (final (build, _, _) in times) build]),
            'raster_ms': _centiles([
              for (final (_, raster, _) in times) raster,
            ]),
          },
        };
      }

      record['pebbles_frames'] = {
        'scope':
            'In the studio of the pebbles (Color 1.2), whose decor has the '
            'whole window: frames timed by the engine (FrameTiming), in '
            'milliseconds, apart from the traits of the budgets. No budget '
            'yet: a first measure.',
        'trait_by_day': timed(
          'One long trait, 121 samples, from its press to the end of its '
          'settling, the decor still, in the afternoon.',
          pebbleDayFrames,
        ),
        'trait_at_night': timed(
          'The same trait at night, under the lamp of the desk.',
          pebbleNightFrames,
        ),
        'decor_moving': timed(
          'Three seconds of the decor that moves at its default level, at '
          'night, nothing else happening.',
          [?pebbleDecorFrames],
        ),
      };
      final gazing = [
        if (gazeFrames case (final first, final last))
          for (var number = first; number <= last; number++)
            ?frameTimes[number],
      ];
      record['gaze_frames'] = {
        'scope':
            'Frames built while the decor of the desk is looked at on the '
            'whole window, at night, moving at « Maximum », three seconds '
            'of them (FrameTiming), in milliseconds. No budget yet: a '
            'first measure.',
        'count': gazing.length,
        if (gazing.isNotEmpty) ...{
          'build_ms': _centiles([for (final (build, _, _) in gazing) build]),
          'raster_ms': _centiles([for (final (_, raster, _) in gazing) raster]),
        },
      };
      // The first frame of Color: the first one built after it was given
      // to the test framework, whose own frames come first.
      final from = beforeColor;
      final colorFrames = from == null
          ? const <int>[]
          : (frameTimes.keys.where((number) => number > from).toList()..sort());
      final colorFirst = colorFrames.isEmpty
          ? null
          : frameTimes[colorFrames.first];
      final fromMain = colorFirst == null
          ? null
          : _hundredths(colorFirst.$3 - mainAt);
      final framework = firstFrame;
      record['startup'] = {
        'scope':
            'From main() of the scenario, and from the start of its process '
            '(Linux, to the hundredth of a second), to the end of the '
            'rasterization of the first frame of Color, after the frames of '
            'the test framework, on the clock of the timeline that the '
            'engine times its frames with. Between them: the start of the '
            'framework, and the options of Color read from its folder.',
        'first_frame_number': colorFrames.isEmpty ? null : colorFrames.first,
        'first_frame_of_the_framework_from_main_ms': framework == null
            ? null
            : _hundredths(
                framework.timestampInMicroseconds(ui.FramePhase.rasterFinish) -
                    mainAt,
              ),
        'first_frame_from_main_ms': fromMain,
        'process_age_at_main_ms': runningBeforeMain,
        'first_frame_from_process_start_ms':
            fromMain == null || runningBeforeMain == null
            ? null
            : _hundredths(((runningBeforeMain + fromMain) * 1000).round()),
      };
      File('${root.path}/result.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(record)}\n',
      );
    }
  });
}

/// How long this process had run, in milliseconds, as /proc tells it on
/// Linux (to the hundredth of a second); null elsewhere.
int? _processAgeMilliseconds() {
  if (!Platform.isLinux) return null;
  try {
    final stat = File('/proc/self/stat').readAsStringSync();
    // After the name of the program, between parentheses: the state is the
    // third field, the start (in hundredths of a second since the system
    // started) the twenty-second.
    final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
    final startTicks = int.parse(fields[19]);
    final uptime = double.parse(
      File('/proc/uptime').readAsStringSync().split(' ').first,
    );
    return ((uptime - startTicks / 100) * 1000).round();
  } catch (_) {
    return null;
  }
}

/// [micros] in milliseconds, to the hundredth.
double _hundredths(int micros) => (micros / 10).round() / 100;

/// The 50th, the 90th and the 99th centiles of [micros], by the nearest
/// rank, and the largest, in milliseconds to the hundredth.
Map<String, double> _centiles(List<int> micros) {
  final sorted = [...micros]..sort();
  double at(double rank) =>
      _hundredths(sorted[math.max(0, (rank * sorted.length).ceil() - 1)]);
  return {
    'p50': at(.5),
    'p90': at(.9),
    'p99': at(.99),
    'max': _hundredths(sorted.last),
  };
}
