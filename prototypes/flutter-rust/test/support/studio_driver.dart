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

  /// What « Mon dessin » holds between two rails: the menu of a telephone
  /// and of a small window.
  static const phoneMenuEntries = {
    'newProject',
    'openProject',
    'openGallery',
    'importImage',
    'exportImage',
    'printDrawing',
    'replayDrawing',
    'layersButton',
    'fitPage',
    'showHelp',
    'openUniverses',
    'openOptions',
    'aboutColor',
  };

  /// Opens the menu of a telephone, which must be closed.
  Future<void> openPhoneMenu() async {
    await tester.tap(find.byKey(const Key('phoneMenu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('phoneMenuDialog')), findsOneWidget);
  }

  /// Whether the pebbles stand in two rails beside the sheet: a telephone,
  /// a small window.
  bool get rails => pebbleRails();

  /// Opens « Mon dessin » : what the drawing holds and the last thing
  /// that happened to it are written there.
  Future<void> showStatus() => openMyDrawing();

  /// Opens « Mon dessin », where what is done with the whole drawing
  /// waits: a panel above a line, the menu between two rails.
  Future<void> openMyDrawing() => openMyDrawingOf(tester);

  /// Puts an open panel of the pebbles away, as a press beside it does.
  Future<void> closePanel() => closePebblePanel(tester);

  /// What « Mon dessin » says of the drawing: its name, what it holds and
  /// the last thing that happened to it.
  Future<String> status() => drawingStatus(tester);

  Future<void> reveal(String key) async {
    if (find.byKey(Key(key)).evaluate().isNotEmpty) return;
    await revealControl(tester, key);
  }

  Future<void> tap(String key) => pressControl(tester, key);

  Offset get sheetCenter =>
      tester.getCenter(find.byKey(const Key('drawingSurface')));

  /// The fitted view of a sheet of the given size, as the studio lays it out.
  ViewTransform view({double width = 1200, double height = 800}) {
    final size = tester.getSize(find.byKey(const Key('drawingSurface')));
    // The stage keeps the same room above and under the sheet at rest.
    final sheet = tester.getSize(find.byKey(const Key('sheetAtRest')));
    return ViewTransform.fit(
      viewWidth: size.width,
      viewHeight: size.height,
      padding: (size.height - sheet.height) / 2,
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

  /// What the studio says of the drawing, on the button « Mon dessin ».
  String get _pebbleCaption =>
      tester.widget<GaletButton>(find.byKey(const Key('myDrawing'))).label;

  void expectCount(int count) {
    final said = count <= 1 ? '$count élément · ' : '$count éléments · ';
    expect(_pebbleCaption, contains(': $said'));
  }

  /// As [expectCount]: a telephone says it on its button « Mon dessin »
  /// too.
  Future<void> expectPhoneCount(int count) async => expectCount(count);

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

  bool get isDirty => _pebbleCaption.contains('modifications non enregistrées');

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

/// The options of an adult who asked for « Toutes les couleurs, pour les
/// grands » : the field of every colour, the pipette, « Mélanger » and the
/// colours chosen last.
StudioOptionsStore grownUpOptions([StudioOptions? options]) {
  final store = StudioOptionsStore.memory(
    (options ?? StudioOptions.defaults).copyWith(grownUpColours: true),
  );
  addTearDown(store.dispose);
  return store;
}

/// Whether the pipette waits for a colour of the drawing: the companion
/// says so, whatever the window.
bool pipetteArmed(WidgetTester tester) => find
    .descendant(
      of: find.byKey(const Key('galetBubble')),
      matching: find.textContaining('reprendre'),
    )
    .evaluate()
    .isNotEmpty;

bool _shown(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

/// Whether the pebbles stand in two rails beside the sheet: a telephone, a
/// small window.
bool pebbleRails() => _shown('galetLeftRail');

/// What « Mon dessin » holds above a line.
const _inMyDrawing = {
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

/// What the « lequel » button of the pebbles opens stays open after these:
/// the panel is put away before anything else is done.
const _keepsPanelOpen = {
  'fillShapeCheckbox',
  'paint-target-stroke',
  'paint-target-fill',
  'turnStamp',
  'mirrorStamp',
};

/// The choices of « Formes »: they are shown once its button is chosen.
final _inShapes = {
  'tool-rectangle',
  'tool-ellipse',
  'tool-magnet',
  for (final shape in NewShape.values) 'shape-${shape.name}',
};

/// Opens « Mon dessin », where what is done with the whole drawing waits:
/// a panel above a line, the menu between two rails.
Future<void> openMyDrawingOf(WidgetTester tester) async {
  if (_shown('galetPanel-drawing') || _shown('phoneMenuDialog')) return;
  await tester.tap(find.byKey(const Key('myDrawing')));
  await tester.pumpAndSettle();
}

/// What « Mon dessin » says of the drawing — its name, what it holds, and
/// the last thing that happened to it, which the line under the sheet said
/// in the studio of before —, read as a person would: opened, read, put
/// away. Between two rails, what the top of the menu says.
Future<String> drawingStatus(WidgetTester tester) async {
  final wasOpen = _shown('galetPanel-drawing') || _shown('phoneMenuDialog');
  await openMyDrawingOf(tester);
  final said = <String>[];
  if (_shown('phoneMenuDialog')) {
    for (final text in tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('phoneMenuDialog')),
        matching: find.byType(Text),
      ),
    )) {
      said.add(text.data ?? '');
    }
    if (!wasOpen) {
      await tester.tap(find.byKey(const Key('closePhoneMenu')));
      await tester.pumpAndSettle();
    }
  } else {
    for (final key in const ['drawingCaption', 'drawingStatus']) {
      final text = find.byKey(Key(key));
      if (text.evaluate().isNotEmpty) {
        said.add(tester.widget<Text>(text).data ?? '');
      }
    }
    if (!wasOpen) await closePebblePanel(tester);
  }
  return said.join('\n');
}

/// Puts an open panel of the pebbles away, as a press beside it does.
Future<void> closePebblePanel(WidgetTester tester) async {
  final barrier = find.byKey(const Key('galetPanelBarrier'));
  if (barrier.evaluate().isEmpty) return;
  // In the middle of its top edge: no pebble stands there in any form, and
  // a tablet keeps the very top of its screen for its own bar.
  final all = tester.getRect(barrier);
  await tester.tapAt(Offset(all.center.dx, all.top + 2));
  await tester.pumpAndSettle();
}

GaletButton? _toolButton(WidgetTester tester, String key) {
  final button = find.byKey(Key(key));
  return button.evaluate().isEmpty ? null : tester.widget<GaletButton>(button);
}

/// Opens what holds the control [key] of the studio, as a person would
/// before pressing it, and gives the key to press — a shade of a colour
/// has its own among those of its family, and a tool its own in the drawer
/// of a rail.
Future<String> revealControl(WidgetTester tester, String key) async {
  if (_shown(key)) return key;
  final rails = pebbleRails();
  Future<void> open(String button) async {
    await tester.tap(find.byKey(Key(button)));
    await tester.pumpAndSettle();
  }

  final inMenu = rails
      // In a small window of a computer the loupes and the hand wait in
      // the menu too.
      ? {...StudioDriver.phoneMenuEntries, 'zoomOut', 'zoomIn', 'panPage'}
      : _inMyDrawing;
  if (inMenu.contains(key)) {
    await openMyDrawingOf(tester);
    return key;
  }
  if (key.startsWith('color-')) {
    if (rails && !_shown('galetPanel-colours')) await open('railColour');
    if (_shown(key)) return key;
    final rgb = int.parse(key.substring(6), radix: 16);
    final family = galetFamilyOf(rgb);
    expect(family, isNotNull, reason: 'the pebbles do not offer $key');
    var holder = galetColours[family!].rgb;
    if (!_shown('color-${holder.toRadixString(16)}')) {
      // A shorter line: white waits with black, brown with orange, pink
      // with red, violet with blue.
      holder = switch (holder) {
        0xffffff => 0x1a1a1a,
        0x79513e => 0xef9439,
        0xf4b7cf => 0xe83d48,
        _ => 0x3370d1,
      };
    }
    await tester.longPress(
      find.byKey(Key('color-${holder.toRadixString(16)}')),
    );
    await tester.pumpAndSettle();
    return 'nuance-${key.substring(6)}';
  }
  if (key == 'pickPaintColor' ||
      key == 'morePaintColors' ||
      key.startsWith('recent-')) {
    // « Toutes les couleurs », where an adult asked for it.
    if (rails && !_shown('everyColour')) await open('railColour');
    await open('everyColour');
    return key;
  }
  final setting =
      key.startsWith('size-') ||
      key.startsWith('width-') ||
      key.startsWith('brush-');
  final choice =
      _inShapes.contains(key) ||
      _keepsPanelOpen.contains(key) ||
      key == 'chooseStamp' ||
      key.startsWith('brushTip-') ||
      key.startsWith('magic-') ||
      key.startsWith('pour-') ||
      key.startsWith('stamp-');
  if (rails) {
    if (key.startsWith('tool-') && !_inShapes.contains(key)) {
      // A tool that the rail has no room for waits in the drawer.
      await open('toolDrawer');
      return 'drawer-$key';
    }
    if (_inShapes.contains(key) &&
        _toolButton(tester, 'tool-shapes')?.selected != true) {
      if (!_shown('tool-shapes')) await open('toolDrawer');
      await open(_shown('tool-shapes') ? 'tool-shapes' : 'drawer-tool-shapes');
    }
    if (setting || choice) {
      if (!_shown('galetPanel-drawer')) await open('toolDrawer');
      if (key.startsWith('stamp-')) await open('chooseStamp');
    }
    return key;
  }
  if (setting) {
    await open('galetSize');
  } else if (choice) {
    if (_inShapes.contains(key) &&
        !_shown('galetPanel-which') &&
        _toolButton(tester, 'tool-shapes')?.selected != true) {
      // « Formes » in hand first: its choices are those of « lequel ».
      await open('tool-shapes');
    }
    if (!_shown('galetPanel-which')) await open('galetWhich');
  }
  return key;
}

/// Presses the control [key] of the studio, opening first what holds it,
/// and lets the studio settle.
Future<void> pressControl(WidgetTester tester, String key) async {
  if (key == 'chooseStamp' && !pebbleRails()) {
    // Above a line the stamps are what « lequel » opens: no dialog, and
    // nothing more to press before the stamp itself.
    if (!_shown('galetPanel-which')) {
      await tester.tap(find.byKey(const Key('galetWhich')));
      await tester.pumpAndSettle();
    }
    return;
  }
  final pressed = await revealControl(tester, key);
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
  if (_keepsPanelOpen.contains(key)) await closePebblePanel(tester);
}

/// Where the point ([x], [y]) of a sheet [width] by [height] lies on the
/// screen, when the whole sheet is shown.
Offset sheetPoint(
  WidgetTester tester,
  double x,
  double y, {
  double width = 1200,
  double height = 800,
}) {
  final sheet = tester.getRect(find.byKey(const Key('sheetAtRest')));
  return sheet.topLeft +
      Offset(x * sheet.width / width, y * sheet.height / height);
}

/// The colour that the pebbles show as the one in hand: the swatch that is
/// chosen and ticked — of the line, of a rail, or the place of a colour
/// that the line does not offer.
int? colourInHand(WidgetTester tester) {
  for (final swatch in tester.widgetList<GaletSwatch>(
    find.byType(GaletSwatch),
  )) {
    if (swatch.chosen && swatch.ticked) return swatch.rgb;
  }
  // A shade is in hand: the swatch of its family keeps its ring without
  // the tick, and the dot of the size button is drawn in the very colour.
  final dots = find.descendant(
    of: find.byKey(const Key('galetSize')),
    matching: find.byType(Container),
  );
  for (final dot in tester.widgetList<Container>(dots)) {
    final decoration = dot.decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      return decoration.color!.toARGB32() & 0xffffff;
    }
  }
  return null;
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

/// What a press on the button [key] does, whatever the button is made of;
/// null when the button does not answer.
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
/// non enregistrées » — on its button « Mon dessin ».
String drawingCaption(WidgetTester tester) {
  final label = tester
      .widget<GaletButton>(find.byKey(const Key('myDrawing')))
      .label;
  return label.substring(label.indexOf(':') + 1).trim();
}

/// As [drawingCaption], for a helper that has no tester at hand.
String drawingCaptionNow() {
  final button =
      find.byKey(const Key('myDrawing')).evaluate().single.widget
          as GaletButton;
  return button.label.substring(button.label.indexOf(':') + 1).trim();
}

/// Presses the control [key] and lets the studio settle: what is done with
/// the whole drawing — Nouveau, Ouvrir, Imprimer, Aide, Options… — waits
/// in « Mon dessin », which is opened first.
Future<void> pressAction(WidgetTester tester, String key) async {
  final pressed = await revealControl(tester, key);
  await tester.tap(find.byKey(Key(pressed)));
  await tester.pumpAndSettle();
}
