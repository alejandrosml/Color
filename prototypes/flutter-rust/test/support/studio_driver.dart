// SPDX-License-Identifier: MIT
// Shared gestures of the text, stamp and layer workflows. Real Rust documents;
// only native panels, disk writes and the recovery store are in memory.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/country_signs.dart';
import 'package:edupaint_flutter_study/desktop_menu.dart';
import 'package:edupaint_flutter_study/galets.dart';
import 'package:edupaint_flutter_study/kept_colours.dart';
import 'package:edupaint_flutter_study/gallery_storage.dart';
import 'package:edupaint_flutter_study/main.dart';
import 'package:edupaint_flutter_study/options_dialog.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/studio_printer.dart';
import 'package:edupaint_flutter_study/studio_sounds.dart';
import 'package:edupaint_flutter_study/view_transform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_files.dart';
import 'prepared_open_wait.dart';

class StudioDriver {
  StudioDriver(
    this.tester, {
    MemoryFiles? files,
    MemoryRecovery? recovery,
    this.gallery,
    this.printer,
    this.options,
    this.sounds,
    this.countrySigns = _inFrance,
    this.keptColours,
  }) : files = files ?? MemoryFiles(),
       recovery = recovery ?? MemoryRecovery();
  final WidgetTester tester;
  final MemoryFiles files;
  final MemoryRecovery recovery;

  /// « Mes dessins ». Without one the studio has no album, as before it
  /// existed.
  final GalleryStorage? gallery;

  /// What « Imprimer » reaches. Without one it is the real channel, which
  /// no test answers: the studio then says that printing is unavailable.
  final StudioPrinter? printer;

  /// The options of the adult. Without a store the studio keeps its own,
  /// with the defaults: the whole interface.
  final StudioOptionsStore? options;

  /// What hears the sounds. Without one the studio is silent.
  final SoundPlayer? sounds;

  /// Where the device says it is: in France unless a test says otherwise,
  /// so that the paint pot closes small gaps.
  final Future<CountrySigns> Function() countrySigns;

  /// The colours kept from an earlier session; none without them.
  final KeptColours? keptColours;

  static Future<CountrySigns> _inFrance() async =>
      CountrySigns(codes: const ['FR'], timeZones: const ['Europe/Paris']);

  /// Whether the studio stands on a telephone's screen.
  bool phone = false;

  /// [phone]: the screen is a telephone's, of [size], which the studio fills
  /// but for the [padding] of the system, the notch or the island of an
  /// iPhone and the bar at its foot.
  Future<void> start({
    Size size = const Size(1100, 760),
    double textScale = 1,
    bool phone = false,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    this.phone = phone;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    if (phone) {
      tester.view.display.size = size;
      addTearDown(tester.view.display.resetSize);
    }
    if (padding != EdgeInsets.zero) {
      final insets = FakeViewPadding(
        left: padding.left,
        top: padding.top,
        right: padding.right,
        bottom: padding.bottom,
      );
      tester.view.padding = insets;
      tester.view.viewPadding = insets;
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
    }
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      EduPaintApp(
        files: files,
        recoveryStorage: recovery,
        gallery: gallery,
        printer: printer ?? printWithSystemPanel,
        options: options,
        sounds: sounds ?? const SilentSounds(),
        countrySigns: countrySigns,
        keptColours: keptColours,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  /// « Options », opened as an adult opens it: when the adult has chosen a
  /// calculation at the door, it is read on the screen and answered on its
  /// keys; the options are then given the moment they take to listen.
  Future<void> openOptions() async {
    await tap('openOptions');
    if (find.byKey(const Key('adultGate')).evaluate().isNotEmpty) {
      await answerAdultGate(tester);
    } else if (find.byKey(const Key('optionsDialog')).evaluate().isNotEmpty) {
      await tester.pump(OptionsDialog.settling);
      await tester.pump();
    }
  }

  Future<void> finish() => tester.pumpWidget(const SizedBox.shrink());

  EduPaintDesktopMenu get menu =>
      tester.widget<EduPaintDesktopMenu>(find.byType(EduPaintDesktopMenu));

  /// The actions of the header that wait in its « … » menu when the window
  /// has no room for them on its line.
  static const _foldable = {
    'openGallery',
    'importImage',
    'printDrawing',
    'showHelp',
    'openOptions',
  };

  /// What the menu of a telephone holds.
  static const phoneMenuEntries = {
    'newProject',
    'openProject',
    'openGallery',
    'importImage',
    'saveProject',
    'exportImage',
    'printDrawing',
    'replayDrawing',
    'layersButton',
    'fitPage',
    'showHelp',
    'openOptions',
    'aboutColor',
  };

  /// Opens the menu of a telephone, which must be closed.
  Future<void> openPhoneMenu() async {
    await tester.tap(find.byKey(const Key('phoneMenu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('phoneMenuDialog')), findsOneWidget);
  }

  /// Opens the « … » menu of the header when the action [key] waits there
  /// rather than on the line, as a person would before choosing it; on a
  /// telephone, the menu where every action of the drawing waits.
  /// The choices of « Formes »: they are shown once its button is chosen.
  static final _inShapes = {
    'tool-rectangle',
    'tool-ellipse',
    'tool-magnet',
    for (final shape in NewShape.values) 'shape-${shape.name}',
  };

  /// Whether the studio is the one of the pebbles (Color 1.2): a wide
  /// window.
  bool get galets => find.byKey(const Key('galetLine')).evaluate().isNotEmpty;

  /// What « Mon dessin » holds in the studio of the pebbles.
  static const _inMyDrawing = {
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

  /// What the « lequel » button of the pebbles opens stays open after
  /// these: the panel is put away before anything else is done.
  static const _keepsPanelOpen = {
    'fillShapeCheckbox',
    'paint-target-stroke',
    'paint-target-fill',
    'turnStamp',
    'mirrorStamp',
  };

  /// In the studio of the pebbles, opens « Mon dessin » : what the
  /// drawing holds and the last thing that happened to it are written
  /// there, the line of state having gone with the panels. Nothing to do
  /// in the studio of before, which writes them under the sheet.
  Future<void> showStatus() => openMyDrawing();

  /// In the studio of the pebbles, opens « Mon dessin », where what is
  /// done with the whole drawing waits; nothing to do in the studio of
  /// before, whose header shows it.
  Future<void> openMyDrawing() async {
    if (!galets ||
        find.byKey(const Key('galetPanel-drawing')).evaluate().isNotEmpty) {
      return;
    }
    await tester.tap(find.byKey(const Key('myDrawing')));
    await tester.pumpAndSettle();
  }

  /// Puts an open panel of the pebbles away, as a press beside it does.
  Future<void> closePanel() async {
    if (find.byKey(const Key('galetPanelBarrier')).evaluate().isEmpty) return;
    await tester.tapAt(
      Offset(
        2,
        tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// In the studio of the pebbles: opens what holds [key], and gives the
  /// key to press — a shade of a colour has its own in the column of its
  /// family.
  Future<String> _revealAmongPebbles(String key) async {
    Future<void> open(String button) async {
      await tester.tap(find.byKey(Key(button)));
      await tester.pumpAndSettle();
    }

    if (_inMyDrawing.contains(key)) {
      await open('myDrawing');
    } else if (key.startsWith('color-')) {
      final rgb = int.parse(key.substring(6), radix: 16);
      final family = galetFamilyOf(rgb);
      expect(family, isNotNull, reason: 'the pebbles do not offer $key');
      await tester.longPress(
        find.byKey(Key('color-${galetColours[family!].rgb.toRadixString(16)}')),
      );
      await tester.pumpAndSettle();
      return 'nuance-${key.substring(6)}';
    } else if (key.startsWith('size-') || key.startsWith('width-')) {
      await open('galetSize');
    } else {
      if (_inShapes.contains(key) &&
          find.byKey(const Key('galetPanel-which')).evaluate().isEmpty) {
        // « Formes » in hand first: its choices are those of « lequel ».
        final shapes = tester.widget<GaletButton>(
          find.byKey(const Key('tool-shapes')),
        );
        if (!shapes.selected) await open('tool-shapes');
      }
      if (_inShapes.contains(key) ||
          _keepsPanelOpen.contains(key) ||
          key.startsWith('brushTip-') ||
          key.startsWith('magic-') ||
          key.startsWith('pour-') ||
          key.startsWith('stamp-')) {
        await open('galetWhich');
      }
    }
    return key;
  }

  Future<void> reveal(String key) async {
    if (find.byKey(Key(key)).evaluate().isNotEmpty) return;
    if (galets) {
      await _revealAmongPebbles(key);
      return;
    }
    if (_inShapes.contains(key)) {
      await tap('tool-shapes');
      return;
    }
    if (phone) {
      if (phoneMenuEntries.contains(key)) await openPhoneMenu();
      return;
    }
    if (!_foldable.contains(key)) return;
    final more = find.byKey(const Key('moreFileActions'));
    expect(more, findsOneWidget, reason: '$key is nowhere in the header');
    await tester.tap(more);
    await tester.pumpAndSettle();
  }

  Future<void> tap(String key) async {
    var pressed = key;
    if (key == 'chooseStamp' && galets) {
      // Among the pebbles the stamps are what « lequel » opens: no
      // dialog, and nothing more to press before the stamp itself.
      if (find.byKey(const Key('galetPanel-which')).evaluate().isEmpty) {
        await tester.tap(find.byKey(const Key('galetWhich')));
        await tester.pumpAndSettle();
      }
      return;
    }
    if (find.byKey(Key(key)).evaluate().isEmpty && galets) {
      pressed = await _revealAmongPebbles(key);
    } else {
      await reveal(key);
    }
    final control = find.byKey(Key(pressed));
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
    if (key == 'openProject') {
      await waitForPreparedOpen(tester, allowSaveDecision: true);
    } else if (key == 'restoreRecovery') {
      await waitForPreparedOpen(tester);
    } else {
      await tester.pumpAndSettle();
    }
    if (_keepsPanelOpen.contains(key)) await closePanel();
  }

  Offset get sheetCenter =>
      tester.getCenter(find.byKey(const Key('drawingSurface')));

  /// The fitted view of a sheet of the given size, as the studio lays it out.
  ViewTransform view({double width = 1200, double height = 800}) {
    final size = tester.getSize(find.byKey(const Key('drawingSurface')));
    return ViewTransform.fit(
      viewWidth: size.width,
      viewHeight: size.height,
      // A telephone shows no name around the sheet.
      padding: !phone && size.height >= 160 ? 28 : 8,
      documentWidth: width,
      documentHeight: height,
    );
  }

  /// Where a document point lies, relative to the centre of the sheet.
  Offset at(double x, double y, {double width = 1200, double height = 800}) {
    final scale = view(width: width, height: height).scale;
    return Offset((x - width / 2) * scale, (y - height / 2) * scale);
  }

  /// Presses and releases at [at], relative to the centre of the sheet.
  Future<void> click([Offset at = Offset.zero]) async {
    await tester.tapAt(sheetCenter + at);
    await tester.pumpAndSettle();
  }

  /// Presses and releases the paint pot at [at], then waits for what it
  /// pours: on the paper the pot reads the drawing as an image, which the
  /// engine makes outside the test's clock.
  Future<void> pour([Offset at = Offset.zero]) async {
    await tester.tapAt(sheetCenter + at);
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

  Future<void> drag(Offset from, Offset to) async {
    final gesture = await tester.startGesture(sheetCenter + from);
    await gesture.moveTo(sheetCenter + (from + to) / 2);
    await gesture.moveTo(sheetCenter + to);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// What the studio of the pebbles says of the drawing, on the button
  /// « Mon dessin »: the line of state went with the panels.
  String get _pebbleCaption =>
      tester.widget<GaletButton>(find.byKey(const Key('myDrawing'))).label;

  void expectCount(int count) {
    final said = count <= 1 ? '$count élément · ' : '$count éléments · ';
    if (galets) {
      expect(_pebbleCaption, contains(': $said'));
      return;
    }
    expect(find.textContaining(said), findsOneWidget);
  }

  /// On a telephone the count is read at the top of the menu, which is then
  /// closed again.
  Future<void> expectPhoneCount(int count) async {
    await openPhoneMenu();
    expectCount(count);
    await tester.tap(find.byKey(const Key('closePhoneMenu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('phoneMenuDialog')), findsNothing);
  }

  Future<String> svg() async {
    await tap('exportImage');
    await tap('exportSvg');
    expect(files.svg, isNotNull);
    return files.svg!;
  }

  /// Saves the project and reopens the written bytes in a fresh document
  /// that the caller disposes.
  Future<RustDocument> saved() async {
    await tap('saveProject');
    expect(files.projects, hasLength(1));
    return RustDocument.fromProject(files.projects.values.single);
  }

  /// Types into the text dialog, which must be open.
  Future<void> write(String text) async {
    await tester.enterText(find.byKey(const Key('textField')), text);
    await tester.pumpAndSettle();
  }

  /// The whole text gesture: click the sheet, type, confirm. [x] and [y] are
  /// a point of the sheet, resolved once the text tool is chosen: choosing a
  /// tool can change the room left to the sheet, and with it every position.
  Future<void> addText(
    String text, {
    Offset at = Offset.zero,
    double? x,
    double? y,
  }) async {
    await tap('tool-text');
    await click(x == null || y == null ? at : this.at(x, y));
    expect(find.byKey(const Key('textDialog')), findsOneWidget);
    await write(text);
    await tap('confirmText');
    expect(find.byKey(const Key('textDialog')), findsNothing);
  }

  bool get isDirty => galets
      ? _pebbleCaption.contains('modifications non enregistrées')
      : find
            .textContaining('modifications non enregistrées')
            .evaluate()
            .isNotEmpty;

  /// Exports a PNG through the interface. The engine encodes it outside the
  /// widget test's fake clock, so the wait runs on the real one.
  Future<Uint8List> png() async {
    files.png = null;
    await tap('exportImage');
    await tester.tap(find.byKey(const Key('exportPng')));
    await tester.pump();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 400 && files.png == null; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(files.png, isNotNull);
    return files.png!;
  }

  /// Red, green, blue and alpha of one pixel of an exported PNG.
  Future<List<int>> pixel(Uint8List png, int x, int y) async =>
      (await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(png);
        ui.Image? image;
        try {
          image = (await codec.getNextFrame()).image;
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final offset = (y * image.width + x) * 4;
          return List<int>.generate(4, (i) => data!.getUint8(offset + i));
        } finally {
          image?.dispose();
          codec.dispose();
        }
      }))!;

  /// Replaces the drawing by an empty sheet of the given shape name
  /// (`landscape`, `portrait` or `square`), abandoning unsaved changes.
  Future<void> newSheet(String shape) async {
    await tap('newProject');
    await tap('newSheet-$shape');
    await tap('createNewSheet');
    if (find.byKey(const Key('discardChanges')).evaluate().isNotEmpty) {
      await tap('discardChanges');
    }
  }

  /// Opens the layers panel, runs [steps] and returns to the drawing.
  Future<void> layers(Future<void> Function() steps) async {
    await tap('layersButton');
    expect(find.byKey(const Key('layersDialog')), findsOneWidget);
    await steps();
    await tap('closeLayers');
    expect(find.byKey(const Key('layersDialog')), findsNothing);
  }
}

double left(StrokeData object) =>
    object.points.map((p) => p.x).reduce((a, b) => a < b ? a : b);
double right(StrokeData object) =>
    object.points.map((p) => p.x).reduce((a, b) => a > b ? a : b);
double top(StrokeData object) =>
    object.points.map((p) => p.y).reduce((a, b) => a < b ? a : b);
double bottom(StrokeData object) =>
    object.points.map((p) => p.y).reduce((a, b) => a > b ? a : b);

/// The two numbers of the multiplication that the door of the options
/// shows.
(int, int) adultGateNumbers(WidgetTester tester) {
  final question = tester
      .widget<Text>(find.byKey(const Key('adultGateQuestion')))
      .data!;
  final match = RegExp(r'^(\d) × (\d) = \?$').firstMatch(question);
  expect(match, isNotNull, reason: question);
  return (int.parse(match![1]!), int.parse(match[2]!));
}

/// Types [answer] on the keys of the door: its second digit answers.
Future<void> typeAtAdultGate(WidgetTester tester, int answer) async {
  for (final digit in '$answer'.split('')) {
    await tester.tap(find.byKey(Key('adultGateDigit$digit')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Reads the multiplication and gives its result. When the options open
/// behind the door, they are given the moment they take before they listen.
Future<void> answerAdultGate(WidgetTester tester) async {
  final (first, second) = adultGateNumbers(tester);
  await typeAtAdultGate(tester, first * second);
  if (find.byKey(const Key('optionsDialog')).evaluate().isNotEmpty) {
    await tester.pump(OptionsDialog.settling);
    await tester.pump();
  }
}

/// A result that is not the one asked, with two digits like it.
int wrongAdultGateAnswer(WidgetTester tester) {
  final (first, second) = adultGateNumbers(tester);
  return first * second == 42 ? 43 : 42;
}

/// What a press on the button [key] does, whatever the button is made of —
/// one of the pebbles (Color 1.2) or one of the studio of before; null when
/// the button does not answer.
VoidCallback? onPressedOf(WidgetTester tester, String key) {
  final widget = tester.widget(find.byKey(Key(key)));
  return switch (widget) {
    GaletButton(:final onPressed) => onPressed,
    GaletPictureButton(:final onPressed) => onPressed,
    GaletSaveButton(:final onPressed) => onPressed,
    GaletTile(:final onPressed) => onPressed,
    GaletWideButton(:final onPressed) => onPressed,
    GaletSwatch(:final onPressed) => onPressed,
    IconButton(:final onPressed) => onPressed,
    ButtonStyleButton(:final onPressed) => onPressed,
    _ => throw StateError('$key is not a button: $widget'),
  };
}

/// Whether the button [key] shows itself as chosen, or as on.
bool isChosen(WidgetTester tester, String key) {
  final widget = tester.widget(find.byKey(Key(key)));
  return switch (widget) {
    GaletButton(:final selected) => selected,
    GaletPictureButton(:final selected) => selected,
    GaletTile(:final selected) => selected,
    GaletWideButton(:final selected) => selected,
    GaletSwatch(:final chosen) => chosen,
    IconButton(:final isSelected) => isSelected ?? false,
    _ => throw StateError('$key does not say whether it is chosen: $widget'),
  };
}

/// What the studio says its drawing holds — « 3 éléments · modifications
/// non enregistrées » — wherever it says so: on the button « Mon dessin »
/// of the pebbles, or under the name of the drawing in the studio of
/// before.
String drawingCaption(WidgetTester tester) {
  final pebble = find.byKey(const Key('myDrawing'));
  if (pebble.evaluate().isNotEmpty) {
    final label = tester.widget<GaletButton>(pebble).label;
    return label.substring(label.indexOf(':') + 1).trim();
  }
  return tester
      .widget<Text>(find.textContaining(RegExp(r'^\d+ éléments? · ')))
      .data!;
}

/// Presses the control [key] and lets the studio settle. In the studio of
/// the pebbles, what is done with the whole drawing — Nouveau, Ouvrir,
/// Imprimer, Aide, Options… — waits in « Mon dessin », which is opened
/// first.
Future<void> pressAction(WidgetTester tester, String key) async {
  if (find.byKey(Key(key)).evaluate().isEmpty) {
    final pebble = find.byKey(const Key('myDrawing'));
    if (pebble.evaluate().isNotEmpty) {
      await tester.tap(pebble);
      await tester.pumpAndSettle();
    }
  }
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}
