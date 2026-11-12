// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;
import 'dart:ui' as ui show Image;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'rust_document.dart';
import 'viewport.dart';
import 'view_transform.dart';
import 'color_palette.dart';
import 'desktop_menu.dart';
import 'project_storage.dart';
import 'recovery_location.dart';
import 'recovery_scheduler.dart';
import 'studio_files.dart';
import 'child_art.dart';
import 'native_exit.dart';
import 'native_diagnostics.dart';
import 'drawing_gesture.dart';
import 'document_renderer.dart';
import 'draft_stroke.dart';
import 'document_exports.dart';
import 'document_save_state.dart';
import 'png_export.dart';
import 'print_render.dart';
import 'selection_geometry.dart';
import 'app_folders.dart';
import 'stroke_input.dart';
import 'sheet_images.dart';
import 'raster_source.dart';
import 'new_sheet_dialog.dart';
import 'coloring_pages.dart';
import 'studio_problem.dart';
import 'stamp_catalog.dart';
import 'stamp_dialog.dart';
import 'text_dialog.dart';
import 'text_layout.dart';
import 'size_choice.dart';
import 'layers_dialog.dart';
import 'studio_colors.dart';
import 'studio_tool.dart';
import 'tool_bar.dart';
import 'tool_variants.dart';
import 'view_controls.dart';
import 'studio_header.dart';
import 'selection_toolbar.dart';
import 'studio_inspector.dart';
import 'studio_layout.dart';
import 'studio_painters.dart';
import 'studio_printer.dart';
import 'export_dialog.dart';
import 'help_dialog.dart';
import 'french.dart';
import 'gallery_dialog.dart';
import 'gallery_storage.dart';
import 'gallery_thumbnail.dart';
import 'document_toolbar.dart';
import 'size_control.dart';
import 'studio_questions.dart';
import 'studio_options.dart';
import 'options_dialog.dart';
import 'adult_gate.dart';
import 'studio_sounds.dart';
import 'replay_dialog.dart';
import 'device_self_test.dart';
import 'fit_to_screen.dart';
import 'phone_menu.dart';
import 'platform_words.dart';
import 'country_signs.dart';
import 'kept_colours.dart';
import 'paint_pot.dart';
import 'language.dart';
import 'companion.dart';
import 'sheet_hint.dart';
import 'tool_pointer.dart';
import 'decor.dart';
import 'decor_gaze.dart';
import 'decor_motion.dart';
import 'decor_view.dart';
import 'studio_shapes.dart';
import 'universe.dart';
import 'universe_dialog.dart';
import 'galets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A telephone is turned on its side, and the bars of the system give the
  // studio their room.
  await prepareTouchScreen();
  // The builds of trial of the launchers check the device first; a build
  // for the stores has nothing of it.
  if (deviceSelfTest) await runDeviceSelfTest();
  // The options are read before the first frame: a studio set for a small
  // child never shows the whole interface first.
  final options = await StudioOptionsStore.open();
  // And in the language they ask for, from the first frame.
  appLanguage.value = languageOf(options.value.language);
  // And in the universe they name: the first frame wears its colours.
  studioLook.value = UniverseCatalog.instance
      .named(options.value.universe)
      .look;
  final kept = await KeptColours.open();
  runApp(
    EduPaintApp(options: options, sounds: SystemSounds(), keptColours: kept),
  );
}

/// Builds of the studio, for the tests that count them.
@visibleForTesting
int debugStudioBuilds = 0;

/// Where the seeds of the marks of « Magie » come from, in the tests that
/// compare pictures: the same seeds, the same grass. Null draws them at
/// random, as Color does.
@visibleForTesting
math.Random Function()? debugMarkSeeds;

class EduPaintApp extends StatelessWidget {
  const EduPaintApp({
    super.key,
    this.files = const StudioFiles(),
    this.recoveryStorage,
    this.gallery,
    this.printer = printWithSystemPanel,
    this.options,
    this.sounds = const SilentSounds(),
    this.countrySigns = readCountrySigns,
    this.keptColours,
    this.clock,
  });
  final StudioFiles files;
  final ProjectStorage? recoveryStorage;

  /// The time of the device, for a decor that follows it (Color 1.2): the
  /// clock of the system unless a test gives its own.
  final DateTime Function()? clock;

  /// Where the device says it is: the paint pot closes small gaps only
  /// where that is allowed (lib/country_signs.dart).
  final Future<CountrySigns> Function() countrySigns;

  /// The colours chosen last, kept from one session to the next; without
  /// them the recent colours last as long as the studio.
  final KeptColours? keptColours;

  /// What « Imprimer » asks: by default the print panel of the system.
  final StudioPrinter printer;

  /// The options of the studio and where they are kept. Without them the
  /// studio has the default ones, for as long as it lives.
  final StudioOptionsStore? options;

  /// What plays the sounds; silence unless the application says otherwise.
  final SoundPlayer sounds;

  /// The album of saved drawings. When neither this nor [recoveryStorage] is
  /// given, the studio keeps one in Color's own folder; a studio whose
  /// recovery is injected gets no album unless one is injected too.
  final GalleryStorage? gallery;
  @override
  Widget build(BuildContext context) {
    // Dressed before it is built: the first frame wears the universe that
    // the options name (Color 1.2), the first one when they name none.
    studioLook.wearBeforeBuild(
      UniverseCatalog.instance.named(options?.value.universe).look,
    );
    return ListenableBuilder(
      // A change of language builds the studio again, in the new one: its
      // state, the drawing first, is kept. A change of universe does the
      // same for its colours and the shapes of its buttons.
      listenable: Listenable.merge([appLanguage, studioLook]),
      builder: (context, _) => materialApp(appLanguage.value),
    );
  }

  /// The application in [language], as [build] makes it.
  @visibleForTesting
  MaterialApp materialApp(AppLanguage language) => MaterialApp(
    title: 'Color',
    // French, in which Color is written, and English (Color 1.1).
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: [
      for (final language in AppLanguage.values) language.locale,
    ],
    locale: language.locale,
    debugShowCheckedModeBanner: false,
    // On a tablet or a telephone: inside the safe area, and scaled down
    // whole on a screen smaller than the studio needs.
    builder: touchFirst
        ? (context, child) => FitToScreen(child: child ?? const SizedBox())
        : null,
    theme: ThemeData(
      useMaterial3: true,
      // The same generous controls on every platform. Left to itself the
      // framework makes them compact on desktop systems, eight pixels less
      // in each direction: too small for a child's hand, and not what the
      // layout of the studio is measured with.
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      colorScheme: ColorScheme.fromSeed(
        seedColor: studioGreen,
        surface: studioSurface,
      ),
      scaffoldBackgroundColor: studioBackground,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: studioInk,
        displayColor: studioInk,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: studioGreen,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          // The corners of the universe, never its dashes: a full button
          // has no line around it.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(studioLook.value.buttonRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: studioInk,
          minimumSize: const Size(48, 48),
          side: studioButtonSide(),
          shape: studioButtonShape(),
        ),
      ),
    ),
    home: DrawingStudio(
      files: files,
      recoveryStorage: recoveryStorage,
      gallery: gallery,
      printer: printer,
      options: options,
      sounds: sounds,
      countrySigns: countrySigns,
      keptColours: keptColours,
      clock: clock,
    ),
  );
}

class DrawingStudio extends StatefulWidget {
  const DrawingStudio({
    super.key,
    required this.files,
    this.recoveryStorage,
    this.gallery,
    this.printer = printWithSystemPanel,
    this.options,
    this.sounds = const SilentSounds(),
    this.countrySigns = readCountrySigns,
    this.keptColours,
    this.clock,
  });
  final StudioFiles files;
  final ProjectStorage? recoveryStorage;
  final GalleryStorage? gallery;

  /// The time of the device for the decor; null for the clock of the system.
  final DateTime Function()? clock;
  final StudioPrinter printer;
  final StudioOptionsStore? options;
  final SoundPlayer sounds;
  final Future<CountrySigns> Function() countrySigns;
  final KeptColours? keptColours;
  @override
  State<DrawingStudio> createState() => _DrawingStudioState();
}

/// What a native command did to the history: a new step, one undone, one
/// redone, or changes joined to the newest step (the eraser along a gesture).
enum _HistoryChange { edit, undo, redo, amend }

/// What goes on with the pointer while no button is held, between the click
/// that began it and the click that ends it: a trait, the move of the chosen
/// element, or the sheet under the hand.
enum _Latch { stroke, move, pan }

/// What a button of the pebbles opened (Color 1.2, galets.dart): the panel
/// of the drawing, the size, « lequel » — which trait, which stamp, which
/// shape —, or the shades of a colour.
enum _GaletPanel { drawing, size, which, shades }

/// What the paint pot does on the paper: it gives its colour to a zone it
/// poured before, or to the sheet ([zone] null), or it pours a new zone,
/// [points] and [rings], over the zone [above] or under everything.
final class _PotPaper {
  const _PotPaper.over(this.zone) : points = null, rings = null, above = null;
  const _PotPaper.zone(
    List<DocumentPoint> this.points,
    List<int> this.rings,
    this.above,
  ) : zone = null;
  final int? zone;
  final List<DocumentPoint>? points;
  final List<int>? rings;
  final int? above;
}

class _DrawingStudioState extends State<DrawingStudio>
    with WidgetsBindingObserver {
  RustDocument? _document;
  ui.Image? _backgroundImage;
  StudioProblem? _startupError;
  final _focus = FocusNode(debugLabel: 'Atelier Color');
  final _canvasRepaint = ValueNotifier<int>(0);

  /// The drawing of the sheet kept as images between frames (F-01).
  final _sheetImages = SheetImages();

  /// The painter of the sheet was last made while the view moved: the end
  /// of the gesture makes it again, and the images with it.
  bool _paintedMoving = false;
  final _viewRebuild = ValueNotifier<int>(0);

  // Each change makes the companion stand up and paint (lib/companion.dart).
  final _companionCue = ValueNotifier<int>(0);

  /// The companion answers what the child just did, when the options say
  /// it may.
  void _react() {
    if (_options.companionReacts) _companionCue.value++;
  }

  late final _recentColors = RecentPaintColors(
    initial: widget.keptColours?.colours ?? const [],
  );
  ViewTransform? _view;
  // The view kept its size during a gesture although its room changed.
  bool _viewWaits = false;
  bool _panning = false;
  bool _spaceHeld = false;
  int? _panPointer;
  Offset? _panLast;
  int? _trackpadPointer;
  double _trackpadScale = 1;
  PaintColorTarget _colorTarget = PaintColorTarget.stroke;
  int _fillColor = 0x477fb2;
  late final AppLifecycleListener _lifecycle;
  List<RenderedElement> _strokes = const [];

  /// What is being drawn, read by the painter of the sheet at every frame:
  /// a press and the moves of the pointer change it and paint the sheet
  /// again, without building the studio again (F-03 of the retrospective of
  /// October 2026).
  final _drafting = SheetDraft();
  List<DocumentPoint> get _draft => _drafting.points;
  set _draft(List<DocumentPoint> points) => _drafting.points = points;
  DraftStroke? get _draftStroke => _drafting.stroke;
  set _draftStroke(DraftStroke? stroke) => _drafting.stroke = stroke;
  DocumentPoint? _draftRawEnd;

  /// The 1€ filter of a trait drawn with a finger or a pen, whose samples
  /// tremble; null for a mouse or a trackpad, which do not.
  OneEuroFilter? _steady;

  /// The string of « Trait tranquille », for the trait in progress.
  StringStabilizer? _string;

  /// Where the pointer of a filtered trait is, as it is: the trait ends
  /// there, not where its filter was.
  DocumentPoint? _draftSeen;

  /// The kind of the last pointer that pressed on the sheet, which is the
  /// one that holds it while [_pointer] is set: a pen takes the trait over
  /// from a finger, which was a hand resting on the screen (D-08).
  PointerDeviceKind? _drawingKind;

  static bool _isPen(PointerDeviceKind? kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;
  int? _pointer;
  // A click with a shape tool posed where the shape starts: the next click,
  // or the end of the next drag, says where it ends.
  ShapeAnchor? _shapeAnchor;
  // The press in progress ends the shape that the anchor started.
  bool _draftFromAnchor = false;
  // Where the press in progress began on the screen and how far the pointer
  // went from there: a click is told from a drag on the screen, where the
  // hand moves, not in the units of the sheet.
  Offset? _pressPosition;
  double _pressTravel = 0;
  bool _pressByTouch = false;
  // The press in progress began on the element that was already chosen.
  bool _pressOnChosen = false;
  // « Dessiner sans tenir le bouton » : a click began a gesture that goes on
  // with the pointer, no button held, until the next click.
  _Latch? _latch;
  // Stands for the pointer of such a gesture: no real pointer has this
  // number, and every guard that asks « is a gesture in progress? » holds.
  static const _latchPointer = -1;
  // Where the hand began to move the sheet, and how far it went since.
  Offset? _panStart;
  double _panTravel = 0;
  // Only a mouse has a pointer that moves without pressing: the press in
  // progress, or the one that took the sheet, was made with one.
  bool _pressByMouse = false;
  bool _panByMouse = false;
  // Where a click has just begun or ended a gesture without a held button,
  // or chosen an element. For a moment, a second press at that place is the
  // same click of a hand that pressed twice: it does nothing.
  Offset? _bounceAt;
  Timer? _bounceTimer;
  // The drawing was saved a moment ago: « Enregistrer » shows a tick.
  bool _savedJustNow = false;
  Timer? _savedTimer;

  /// The column of a telephone, on the right of the sheet: a new tool shows
  /// it from its top, where its choices are.
  final _phoneRail = ScrollController();
  static const _bounceTime = Duration(milliseconds: 350);
  static const _bounceReach = 24.0;
  StudioTool _tool = StudioTool.brush;
  bool get _choosing => _tool == StudioTool.select;
  // The pipette waits for a click on the sheet; the tool stays what it was.
  bool _picking = false;
  // How many guarded dialogs are open: the guard falls with the last one.
  int _guardedDialogs = 0;
  // The pointer is down with the eraser: every element it touches goes.
  bool _erasing = false;
  // Where the eraser was at its previous sample, in the canvas's own units.
  Offset? _eraserLast;
  // What this eraser gesture has uncovered: out of its reach until it ends.
  final _eraserShield = Set<StrokeData>.identity();
  // Color 1.1: the eraser cuts traits as it rubs. Where the press began, and
  // the traits under it, which a click takes whole; whether the press became
  // a rub; whether this gesture already made its one step for Annuler.
  DocumentPoint? _eraserPress;
  List<int> _eraserPressCut = const [];
  bool _eraserRubbed = false;
  bool _eraserCommitted = false;
  Duration? _eraserHeardAt;
  final _eraserClock = Stopwatch()..start();

  /// The radius of the eraser on the screen, in logical pixels.
  static const _eraserPixels = 10.0;
  // The panels are put away to leave the whole window to the sheet.
  bool _bigSheet = false;
  int? _selectedIndex;
  DocumentPoint? _selectionStart;
  Rect? _selectionDragBounds;
  StrokeData? _selectionBoundsObject;
  Rect? _selectionPaintBounds;
  final _selectionOffset = ValueNotifier<Offset>(Offset.zero);
  // The width slider is being moved for the chosen element: the element
  // takes the new width when the hand leaves the slider, in one step.
  bool _selectionWidthMoving = false;
  VectorKind get _draftKind => _drafting.kind;
  set _draftKind(VectorKind kind) => _drafting.kind = kind;
  // The brush is heard when it touches the sheet, then again while it
  // travels: when it was last heard, and how far it went since.
  static const _brushHeardEvery = Duration(milliseconds: 340);
  Duration? _brushHeardAt;
  double _brushTravel = 0;
  Offset? _brushLastPosition;
  // Where the pointer went down with the text tool; the dialog opens on release.
  DocumentPoint? _textAnchor;
  ObjectSize _textSize = ObjectSize.medium;

  /// The letters of the next text: those chosen last (one of textFonts).
  int _textFont = 0;
  ObjectSize _stampSize = ObjectSize.medium;
  int _stampId = 0;
  int get _draftStamp => _drafting.stamp;
  set _draftStamp(int stamp) => _drafting.stamp = stamp;
  bool _filled = false;
  // What the brush draws with, the magic of « Magie », the shape of
  // « Formes » (Color 1.1).
  BrushTool _brushTool = BrushTool.round;
  Magic _magic = Magic.rainbow;
  NewShape _newShape = NewShape.star;

  /// What « Formes » gives when it is chosen again: the shape tool used last.
  StudioTool _lastShapeTool = StudioTool.rectangle;

  /// How the next stamp is turned (an eighth of a turn at a time) and
  /// mirrored.
  int _stampEighths = 0;
  bool _stampMirrored = false;

  ObjectLook get _stampLook => ObjectLook(
    rotation: normalAngle(_stampEighths * math.pi / 4),
    mirrorX: _stampMirrored,
  );

  /// How the paint pot pours, and the colour chosen before the current one:
  /// the other end of its gradients.
  PourKind _pourKind = PourKind.plain;
  int _previousColor = 0xffffff;
  late final _seeds = debugMarkSeeds?.call() ?? math.Random();

  /// What a trait of the current tool is drawn with.
  BrushTool get _strokeTool => switch (_tool) {
    StudioTool.brush => _brushTool,
    StudioTool.magic => switch (_magic) {
      Magic.rainbow => BrushTool.rainbow,
      Magic.grass => BrushTool.grass,
      Magic.bricks => BrushTool.bricks,
      Magic.confetti => BrushTool.confetti,
      Magic.mirror => BrushTool.round,
    },
    _ => BrushTool.round,
  };

  // The pressure of a stylus that measures it, 1 to 255; null for a mouse,
  // a finger, or a pen that does not.
  static int? _pressureOf(PointerEvent event) {
    if (!_isPen(event.kind) || !(event.pressureMax > event.pressureMin)) {
      return null;
    }
    final share =
        ((event.pressure - event.pressureMin) /
                (event.pressureMax - event.pressureMin))
            .clamp(0.0, 1.0);
    return (1 + share * 254).round().clamp(1, 255);
  }

  int? get _draftFillRgb => _drafting.fillRgb;
  set _draftFillRgb(int? rgb) => _drafting.fillRgb = rgb;
  int _color = 0x477fb2;
  int get _draftColor => _drafting.rgb;
  set _draftColor(int rgb) => _drafting.rgb = rgb;
  double _width = 12;
  double get _draftWidth => _drafting.width;
  set _draftWidth(double width) => _drafting.width = width;
  int _revision = 0;
  int _documentRevision = 0;

  /// Where the device says it is; null until read, and then the pot closes
  /// no gap.
  CountrySigns? _countrySigns;

  /// The paint pot reads the drawing as an image: a second press waits.
  bool _pouring = false;
  // The revision whose recovery copy going out of sight last asked for.
  int? _hiddenRevision;
  DocumentSaveState? _saveState;
  bool get _dirty => _saveState?.isDirty ?? false;
  bool _busy = true;
  String? _busyLabel;
  int _successfulSaves = 0;
  String? get _currentPath => _saveState?.path;
  ProjectStorage? _storage;
  // « Mes dessins »; null when its private folder is not available.
  GalleryStorage? _gallery;
  // Where a drawing reopened from the album's copy was saved before: the
  // save panel starts there. Never written without the user's choice.
  String? _saveSuggestion;
  // Cards being made for saves that are already done. Quitting and the
  // album's dialog give them a moment; nothing else waits for them.
  final _cardsInProgress = <Future<void>>{};
  late final RecoveryScheduler _recoveryScheduler;
  int _recoveryGeneration = 0;
  bool _recoveryWarningShown = false;
  bool _confirmationOpen = false;

  /// What the line under the sheet says, with its own listenable: a sentence
  /// that changes alone, as when a copy of recovery has been written, does
  /// not build the studio again (F-03).
  final _statusLine = ValueNotifier<String>(
    tr('Recherche d’un dessin à reprendre…'),
  );
  // How the line is said, to say it again when the language changes: a
  // sentence of before stays in the language chosen in the options. Its
  // values are taken when it is said first.
  String Function() _statusSaid = () =>
      tr('Recherche d’un dessin à reprendre…');
  set _status(String Function() said) {
    _statusSaid = said;
    _statusLine.value = said();
  }

  void _sayStatusAgain() => _statusLine.value = _statusSaid();
  // The options of the adult; a studio that was given none keeps its own,
  // with the defaults, for as long as it lives.
  late final StudioOptionsStore _optionsStore =
      widget.options ?? StudioOptionsStore.memory();
  StudioOptions get _options => _optionsStore.value;

  // The universe the studio wears (Color 1.2): its look, and its decor
  // around the sheet. See universe.dart, decor.dart and decor_view.dart.

  /// The universe the options name; the first one when they name none.
  Universe get _universe => UniverseCatalog.instance.named(_options.universe);

  /// The child may change it: more than one to choose from, and no adult
  /// fixed one.
  bool get _choosesUniverse =>
      !_options.universeFixed && UniverseCatalog.instance.universes.length > 1;

  /// The decor as the frame of the sheet shows it; null without a decor.
  DecorPainting? _decorPainting;

  /// The thing of the decor whose card is open.
  final _shownName = ValueNotifier<DecorName?>(null);
  Timer? _nameTimer;
  late final _asking = DecorAsking(onAsk: _showName);

  /// The pointer of the system in the frame of the sheet: none on the
  /// sheet, where « la pointe » is drawn; an arrow beside it, over a decor,
  /// and the arrow that asks over what has a name.
  final _stageCursor = ValueNotifier<MouseCursor>(SystemMouseCursors.none);

  /// Whether the names of the decor can be asked for now.
  bool get _namesOffered =>
      _options.decorNames && (_decorPainting?.layout.pieces ?? false);

  void _showName(DecorName name) {
    if (!mounted || !_namesOffered || _busy || _confirmationOpen) return;
    _nameTimer?.cancel();
    _shownName.value = name;
    _nameTimer = Timer(DecorNameLayer.shownFor, _closeName);
  }

  void _closeName() {
    _nameTimer?.cancel();
    _nameTimer = null;
    _shownName.value = null;
  }

  // The next named thing of the decor, from left to right, for the
  // keyboard: F2 goes on, Maj + F2 back.
  void _nextName(int step) {
    final painting = _decorPainting;
    if (painting == null || !_namesOffered || _busy || _confirmationOpen) {
      return;
    }
    final next = nextDecorName(painting, _shownName.value, step);
    if (next != null) _showName(next);
  }

  // A pointer is at [at] in the frame of the sheet: beside the sheet, over
  // a decor, the pointer of the system shows, and « la pointe » of the
  // tool is not drawn — it is for the sheet.
  void _pointerOverDecor(Offset at, {required bool mouse}) {
    final viewport = _keyViewport;
    final painting = _decorPainting;
    final beside =
        painting != null &&
        painting.layout.pieces &&
        viewport != null &&
        !viewport.contains(at.dx, at.dy);
    _stageCursor.value = !beside
        ? SystemMouseCursors.none
        : _options.decorNames && painting.nameAt(at + _stageOrigin) != null
        ? SystemMouseCursors.help
        : SystemMouseCursors.basic;
    if (beside && mouse) _hint.mouseAt = null;
  }

  // A pointer came down in the frame of the sheet: beside the sheet, it
  // may be asking the name of something. Nothing is taken from the tool.
  void _decorDown(PointerDownEvent event) {
    final viewport = _keyViewport;
    if (viewport == null) return;
    final at = event.localPosition;
    _decorPressed(
      event,
      at + _stageOrigin,
      beside: !viewport.contains(at.dx, at.dy),
    );
  }

  // A pointer came down at [at] of the frame of the decor; [beside]: not
  // on the sheet.
  void _decorPressed(
    PointerDownEvent event,
    Offset at, {
    required bool beside,
  }) {
    final painting = _decorPainting;
    if (painting == null) return;
    final asks =
        _namesOffered &&
        !_busy &&
        !_confirmationOpen &&
        !_panning &&
        !_spaceHeld &&
        (event.buttons & kPrimaryButton) != 0 &&
        beside;
    final under = asks ? painting.nameAt(at) : null;
    // A press anywhere else puts the open card away.
    if (_shownName.value != null && !identical(under, _shownName.value)) {
      _closeName();
    }
    _asking.down(at, event.timeStamp, under);
  }

  /// Where the stage of the sheet begins in the frame of the decor: at its
  /// corner in the studio of before, where the stage is that frame; lower
  /// in the studio of the pebbles, where the decor has the whole window.
  Offset _stageOrigin = Offset.zero;

  /// The pointer of the system over the decor where the stage is not: an
  /// arrow, and the arrow that asks over what has a name.
  final _besideCursor = ValueNotifier<MouseCursor>(SystemMouseCursors.basic);
  // Ticks when the decor of the pebbles looks at the clock again: the
  // ground under the line is tinted as the room is.
  final _decorClock = ValueNotifier<int>(0);

  // ——— « Les galets » (Color 1.2, galets.dart) ———

  /// The frame of the pebbles, and the buttons that open a panel: a panel
  /// is laid beside its button, wherever the window put it.
  final _galetsFrame = GlobalKey(debugLabel: 'galets');
  final _drawingButton = GlobalKey(debugLabel: 'Mon dessin');
  final _sizeButton = GlobalKey(debugLabel: 'taille');
  final _whichButton = GlobalKey(debugLabel: 'lequel');
  late final _swatchButtons = [
    for (var index = 0; index < galetColours.length; index++)
      GlobalKey(debugLabel: 'godet $index'),
  ];

  /// The panel that is open, and for the shades, the swatch they belong to.
  _GaletPanel? _galetPanel;
  int _galetFamily = 0;

  /// « Univers » : the child chooses how the workshop is dressed, or looks
  /// at a decor on the whole screen. The drawing is not touched.
  Future<void> _openUniverses() async {
    _settleLatch();
    if (!_dialogAllowed || !_choosesUniverse) return;
    _finishStroke();
    _closeName();
    final chosen = await _guardedDialog<UniverseChoice>(
      () => showUniverseDialog(
        context,
        catalog: UniverseCatalog.instance,
        current: _universe,
        watch: _options.decorWatch,
        now: widget.clock,
      ),
    );
    if (!mounted || chosen == null) return;
    if (chosen.watch) {
      await _watchDecor(chosen.universe);
      return;
    }
    await _optionsStore.change(
      _options.copyWith(universe: chosen.universe.key),
    );
  }

  /// « Regarder » : the decor of [universe] on the whole screen, until the
  /// child comes back to the drawing (decor_gaze.dart). Nothing of the
  /// studio changes: neither the drawing nor the universe it wears.
  Future<void> _watchDecor(Universe universe) async {
    if (!mounted || universe.decor == null || !_options.decorWatch) return;
    await _guardedDialog<void>(
      () => showDecorGaze(
        context,
        universe: universe,
        motion: _options.decorMotion,
        names: _options.decorNames,
        now: widget.clock,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _recoveryScheduler = RecoveryScheduler(
      writeLatest: _writeRecovery,
      delayFor: _recoveryDelay,
      onError: (error, stack) => FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'Color recovery',
        ),
      ),
    );
    try {
      _document = RustDocument();
      _saveState = DocumentSaveState(
        undoCount: _document!.undoCount,
        redoCount: _document!.redoCount,
        initiallyClean: true,
      );
    } catch (error) {
      _startupError = StudioProblem.fromError(
        error,
        message: tr('Color n’a pas pu démarrer.'),
      );
    }
    _recentColors.addListener(
      () => widget.keptColours?.keep(_recentColors.colors),
    );
    widget.countrySigns().then(
      (signs) => _countrySigns = signs,
      onError: (Object _) {},
    );
    _optionsStore.addListener(_optionsChanged);
    appLanguage.addListener(_sayStatusAgain);
    // The language of the options: main() set it before the first frame;
    // another store, in a test, sets it after this one.
    if (appLanguage.value != languageOf(_options.language)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) appLanguage.value = languageOf(_options.language);
      });
    }
    // The universe of the options: the application dressed the studio
    // before it built it; a studio built alone, in a test, dresses itself
    // after its first frame.
    if (!identical(studioLook.value, _universe.look)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) wearUniverse(_universe);
      });
    }
    if (_options.simpleControls) _fitSimpleControls();
    if (!_options.tools.contains(_tool)) _tool = StudioTool.brush;
    _lifecycle = AppLifecycleListener(
      onExitRequested: _requestExit,
      onHide: () {
        // Out of sight the graphics processor may go: the images of the
        // sheet are made again when it is seen.
        _sheetImages.drop();
        _keepWhenHidden();
      },
      onPause: _keepWhenHidden,
    );
    WidgetsBinding.instance.addObserver(this);
    installNativeExitHandler(() => _requestExit(finalNativeDecision: true));
    unawaited(installNativeDiagnostics());
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeRecovery());
  }

  /// The device changed its languages while Color runs: with « Celle de
  /// l'appareil », Color speaks the new one at once, without a restart.
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (!mounted) return;
    appLanguage.value = languageOf(_options.language);
  }

  /// The system runs short of memory: the images of the sheet go, and are
  /// made again when the sheet is next painted.
  @override
  void didHaveMemoryPressure() {
    _sheetImages.drop();
    _canvasRepaint.value++;
  }

  @override
  void dispose() {
    _optionsStore.removeListener(_optionsChanged);
    appLanguage.removeListener(_sayStatusAgain);
    if (widget.options == null) _optionsStore.dispose();
    _bounceTimer?.cancel();
    _savedTimer?.cancel();
    _nameTimer?.cancel();
    _asking.dispose();
    _shownName.dispose();
    _stageCursor.dispose();
    _besideCursor.dispose();
    _pourHintTimer?.cancel();
    _pourHintSerial++;
    _forgetInk();
    _hint.dispose();
    _phoneRail.dispose();
    _recoveryScheduler.dispose();
    clearNativeExitHandler();
    clearNativeDiagnostics();
    _lifecycle.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    _canvasRepaint.dispose();
    _sheetImages.dispose();
    _viewRebuild.dispose();
    _decorClock.dispose();
    _companionCue.dispose();
    _recentColors.dispose();
    _selectionOffset.dispose();
    _statusLine.dispose();
    _saveState?.retire();
    _document?.dispose();
    _backgroundImage?.dispose();
    super.dispose();
  }

  // The adult changed an option: what is no longer offered is put away, so
  // that nothing stays in a state its controls can no longer leave.
  void _optionsChanged() {
    if (!mounted) return;
    final options = _options;
    appLanguage.value = languageOf(options.language);
    // The universe may be another: the studio wears it at once.
    wearUniverse(_universe);
    if (!options.decorNames || _shownName.value != null) _closeName();
    if (!options.tools.contains(_tool)) _cancelDraft();
    setState(() {
      if (!options.tools.contains(_tool)) {
        _setSelection(null);
        _tool = StudioTool.brush;
        _colorTarget = PaintColorTarget.stroke;
      }
      if (options.simpleControls) _fitSimpleControls();
      if (!options.viewControls) {
        _panning = false;
        _spaceHeld = false;
        _bigSheet = false;
        // Nothing would bring a zoomed sheet back: it is shown whole.
        if (_pointer == null) _view = _view?.resetToFit();
      }
    });
  }

  // The few colours and the three sizes of the simplest interface: the
  // current choices become the nearest of them, so that what is drawn is
  // what a button shows as chosen. Also at start-up, when that interface is
  // the one the options already ask for.
  void _fitSimpleControls() {
    _picking = false;
    if (!simplePaintColors.any((entry) => entry.rgb == _color)) {
      _color = nearestSimplePaintColor(_color);
    }
    _width = _width <= 9
        ? 6
        : _width <= 21
        ? 14
        : 30;
  }

  /// One of the small sounds, when the options want them.
  void _sound(StudioSound sound) {
    if (_options.sounds) widget.sounds.play(sound);
  }

  void _refreshAfterMutation({_HistoryChange change = _HistoryChange.edit}) {
    // Keep monotonic work invalidation independent from the reversible save point.
    _documentRevision++;
    _forgetInk();
    final document = _document!;
    final state = _saveState!;
    switch (change) {
      case _HistoryChange.edit:
        state.editSucceeded(
          undoCount: document.undoCount,
          redoCount: document.redoCount,
        );
      case _HistoryChange.undo:
        state.undoSucceeded(
          undoCount: document.undoCount,
          redoCount: document.redoCount,
        );
      case _HistoryChange.redo:
        state.redoSucceeded(
          undoCount: document.undoCount,
          redoCount: document.redoCount,
        );
      case _HistoryChange.amend:
        state.amendSucceeded(
          undoCount: document.undoCount,
          redoCount: document.redoCount,
        );
    }
    final rendered = {for (final element in _strokes) element.data: element};
    _strokes = List.unmodifiable(
      _document!.strokes.map((data) => rendered[data] ?? RenderedElement(data)),
    );
    _revision++;
    final savedAt = _currentPath;
    _status = _dirty
        ? () => tr(
            'Modifications non enregistrées · préparation de la copie de récupération…',
          )
        : (savedAt == null
              ? () => tr('Nouvelle feuille · récupération locale prête.')
              : () => trf('Projet enregistré : {0}', [savedAt]));
    // A transition to clean must reconcile an older recovery in the same queue.
    _scheduleRecovery();
  }

  void _error(Object error, {String? message}) {
    if (!mounted) return;
    _showProblem(
      StudioProblem.fromError(
        error,
        message: message ?? tr('Cette action n’a pas pu être terminée.'),
      ),
    );
  }

  void _showProblem(StudioProblem problem) {
    if (!mounted) return;
    _sound(StudioSound.notice);
    final messenger = ScaffoldMessenger.of(context);
    // Keep only the latest notification, never a queue of exception objects.
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: studioInk,
        persist: problem.details != null,
        showCloseIcon: problem.details != null,
        closeIconColor: Colors.white,
        duration: const Duration(seconds: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(problem.message, key: const Key('problemMessage')),
            if (problem.details != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('showProblemDetails'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  // A blocked press must not dismiss the notification.
                  onPressed: () => _showProblemDetails(problem),
                  child: Text(tr('Détails')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProblemDetails(StudioProblem problem) async {
    final startupWithoutDocument = _startupError != null && _document == null;
    if (!mounted ||
        (_busy && !startupWithoutDocument) ||
        _confirmationOpen ||
        _pointer != null ||
        _panPointer != null ||
        _trackpadPointer != null) {
      return;
    }
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    // No drawing mutation, finishing gesture, IO or retry belongs to this view.
    setState(() => _confirmationOpen = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => FitDialog(child: StudioProblemDialog(problem: problem)),
      );
    } finally {
      if (mounted) {
        setState(() => _confirmationOpen = false);
      } else {
        _confirmationOpen = false;
      }
    }
  }

  StrokeData? get _selectedObject =>
      _selectedIndex == null ? null : _document!.strokes[_selectedIndex!];

  Rect _boundsForObject(int index, StrokeData object) {
    // Only this studio's concrete RustDocument snapshots use prepared bounds.
    // Rendered elements are retained only for the current document, and an
    // order/index mismatch must never reuse another object's observation.
    final objects = _document?.strokes;
    if (objects != null &&
        index >= 0 &&
        index < objects.length &&
        index < _strokes.length &&
        identical(objects[index], object) &&
        identical(_strokes[index].data, object)) {
      return _strokes[index].controlBounds;
    }
    return objectBounds(object);
  }

  Rect? get _selectedPaintBounds {
    final object = _selectedObject;
    if (!identical(object, _selectionBoundsObject)) {
      _selectionBoundsObject = object;
      _selectionPaintBounds = object == null
          ? null
          : shownBounds(
              object,
              includeStroke: true,
              points: _boundsForObject(_selectedIndex!, object),
            );
    }
    return _selectionPaintBounds;
  }

  bool get _canEditSelection =>
      !_busy &&
      !_confirmationOpen &&
      _pointer == null &&
      _selectedIndex != null;

  /// The kind of object that the colours and sizes shown now apply to: the
  /// chosen element, or what the current tool draws.
  VectorKind? get _styledKind => _choosing ? _selectedObject?.kind : _tool.kind;
  bool get _canFill => _styledKind?.canFill ?? false;

  /// A stamp painted in its own colours only: no colour can be given to it.
  bool _keepsOwnColours(StrokeData object) =>
      object.kind == VectorKind.stamp &&
      stampArtOf(object)?.takesColour == false;

  void _setSelection(int? index) {
    _selectedIndex = index;
    _selectionStart = null;
    _selectionDragBounds = null;
    _selectionOffset.value = Offset.zero;
    _colorTarget = PaintColorTarget.stroke;
    _selectionWidthMoving = false;
    if (index != null) {
      final object = _document!.strokes[index];
      // The colour kept by a stamp that shows none of it is nobody's choice:
      // the current colours stay.
      if (!_keepsOwnColours(object)) {
        _color = object.rgb;
        _fillColor = object.fillRgb ?? object.rgb;
      }
      // A text's size and a stamp's constant are not outline widths.
      if (!object.kind.isBoxObject) {
        _width = object.width.clamp(2.0, 48.0).toDouble();
      }
      _filled = object.fillRgb != null;
    }
    _revision++;
  }

  // The chosen element is the same one, now at [index]: the colours and the
  // width shown stay the ones it has.
  void _reselect(int index) {
    _selectedIndex = index;
    _selectionStart = null;
    _selectionDragBounds = null;
    _selectionOffset.value = Offset.zero;
    _revision++;
  }

  void _finishSelectionDrag() {
    if (_selectionStart == null) return;
    final delta = _selectionOffset.value;
    _selectionStart = null;
    _selectionDragBounds = null;
    _selectionOffset.value = Offset.zero;
    _pointer = null;
    try {
      if (_selectedIndex != null &&
          delta != Offset.zero &&
          _document!.moveObject(
            _selectedIndex!,
            delta.dx,
            delta.dy,
            constrain: true,
          )) {
        _refreshAfterMutation();
      }
    } catch (error) {
      _error(error);
    }
    if (mounted) {
      setState(() {
        _revision++;
      });
    }
  }

  void _deleteSelection() {
    if (!_canEditSelection) return;
    try {
      if (_document!.removeObject(_selectedIndex!)) {
        setState(() {
          _setSelection(null);
          _refreshAfterMutation();
        });
      }
    } catch (error) {
      _error(error);
    }
    _focus.requestFocus();
  }

  void _nudgeSelection(Offset requested) {
    // Arrow shortcuts belong to the page. A focused control (for example the
    // width slider) must never move an object via a bubbling modified arrow.
    if (!_canEditSelection || !_focus.hasPrimaryFocus) return;
    final delta = clampBoundsMovement(
      _boundsForObject(_selectedIndex!, _selectedObject!),
      requested,
      pageWidth: _document!.width.toDouble(),
      pageHeight: _document!.height.toDouble(),
    );
    try {
      if (_document!.moveObject(
        _selectedIndex!,
        delta.dx,
        delta.dy,
        constrain: true,
      )) {
        setState(_refreshAfterMutation);
      }
    } catch (error) {
      _error(error);
    }
  }

  void _escape() {
    if (_busy || _confirmationOpen) return;
    // An open panel of the pebbles goes first.
    if (_galetPanel != null) {
      _closeGaletPanel();
      return;
    }
    if (_shownName.value != null) {
      _closeName();
      return;
    }
    if (_picking) {
      setState(() => _picking = false);
      return;
    }
    final wasDragging = _selectionStart != null;
    // The sheet held by the hand is a gesture too: Échap lets it go and
    // does nothing else.
    final hadGesture = _pointer != null || _panPointer != null;
    // The little circle of a shape begun with a click goes first.
    final hadAnchor = _shapeAnchor != null;
    _cancelDraft();
    if (wasDragging || hadGesture || hadAnchor) return;
    if (_selectedIndex != null) {
      setState(() => _setSelection(null));
    } else if (_bigSheet) {
      // Nothing else to stop: Échap brings the panels back.
      setState(() => _bigSheet = false);
    }
  }

  // Turns the chosen element about the centre of its box: one step to undo.
  void _turnSelection(double angle) {
    final index = _selectedIndex;
    if (index == null || !_canEditSelection) return;
    final object = _document!.strokes[index];
    _changeLook(index, object, object.look.turnedBy(angle));
  }

  // Shows the chosen element in a mirror, left and right swapped as the
  // sheet shows it: one step to undo.
  void _mirrorSelection() {
    final index = _selectedIndex;
    if (index == null || !_canEditSelection) return;
    final object = _document!.strokes[index];
    _changeLook(index, object, object.look.flippedLeftRight());
  }

  void _changeLook(int index, StrokeData object, ObjectLook look) {
    try {
      if (_document!.setObjectPaint(
        index,
        fillRgb: object.fillRgb,
        look: look,
      )) {
        setState(() {
          _refreshAfterMutation();
          _reselect(index);
        });
        _sound(StudioSound.select);
      }
    } catch (error) {
      _error(error, message: tr('Cet élément n’a pas pu être tourné.'));
    }
    _focus.requestFocus();
  }

  void _duplicateSelection() {
    if (!_canEditSelection) return;
    try {
      final bounds = _boundsForObject(_selectedIndex!, _selectedObject!);
      var delta = clampBoundsMovement(
        bounds,
        const Offset(24, 24),
        pageWidth: _document!.width.toDouble(),
        pageHeight: _document!.height.toDouble(),
      );
      if (delta == Offset.zero) {
        delta = clampBoundsMovement(
          bounds,
          const Offset(-24, -24),
          pageWidth: _document!.width.toDouble(),
          pageHeight: _document!.height.toDouble(),
        );
      }
      if (_document!.duplicateObject(
        _selectedIndex!,
        delta.dx,
        delta.dy,
        constrain: true,
      )) {
        setState(() {
          _refreshAfterMutation();
          _setSelection(_document!.count - 1);
        });
      }
    } catch (error) {
      _error(error);
    }
    _focus.requestFocus();
  }

  void _reorderSelection(int destination) {
    if (!_canEditSelection) return;
    try {
      if (_document!.reorderObject(_selectedIndex!, destination)) {
        setState(() {
          // Keep the same object selected.
          _selectedIndex = destination;
          _refreshAfterMutation();
        });
      }
    } catch (error) {
      _error(error);
    }
    _focus.requestFocus();
  }

  // Order shows only among the elements of one layer: « devant » and
  // « derrière » are offered when another element of the chosen one's layer
  // lies on that side of it, and not for a change nobody could see.
  bool _hasLayerMate({required bool inFront}) {
    final strokes = _document!.strokes;
    final index = _selectedIndex!;
    final layer = strokes[index].layer;
    final candidates = inFront ? strokes.skip(index + 1) : strokes.take(index);
    return candidates.any((other) => other.layer == layer);
  }

  bool get _canBringForward =>
      _canEditSelection && _hasLayerMate(inFront: true);
  bool get _canSendBackward =>
      _canEditSelection && _hasLayerMate(inFront: false);

  /// Gives the chosen element a colour, a width or an inside at once: one
  /// step for Annuler, and nothing when it already has them. What is not
  /// named stays as the element has it. The element stays chosen.
  ///
  /// False when the element cannot be changed at this moment — a gesture
  /// holds it, a dialog is open — or when the core refuses: the caller then
  /// leaves the palette and the slider as the element is.
  bool _styleSelection({
    int? rgb,
    double? width,
    bool changeFill = false,
    int? fillRgb,
  }) {
    if (!_canEditSelection) return false;
    final object = _selectedObject!;
    final newRgb = rgb ?? object.rgb;
    final newWidth = width ?? object.width;
    final newFill = changeFill ? fillRgb : object.fillRgb;
    if (newRgb == object.rgb &&
        newWidth == object.width &&
        newFill == object.fillRgb) {
      return true;
    }
    try {
      if (_document!.setObjectStyle(
        _selectedIndex!,
        rgb: newRgb,
        width: newWidth,
        fillRgb: newFill,
      )) {
        _refreshAfterMutation();
      }
      return true;
    } catch (error) {
      _error(error);
      return false;
    }
  }

  // The topmost visible element under the pointer among those of [order],
  // bottom first. By default as « Choisir » and the eraser see it: what the
  // child can change, never the locked page of a colouring page, through
  // which the pointer reaches what lies under it.
  int? _objectAt(
    DocumentPoint point,
    double scale, {
    double tolerancePixels = 7,
    bool insideShapes = false,
    bool inkOnly = false,
    List<int>? order,
  }) => hitTestObjects(
    _document!.strokes,
    point,
    scale: scale,
    tolerancePixels: tolerancePixels,
    preparedBounds: _boundsForObject,
    paintOrder: order ?? _document!.unlockedPaintOrder,
    insideShapes: insideShapes,
    inkOnly: inkOnly,
  );

  /// The eraser (Color 1.1). A press on a filled shape, a text or a stamp
  /// takes it whole, as a click on a trait does; rubbing cuts the traits and
  /// the outlines it crosses, and takes whole what it would take with a
  /// click. One gesture is one step for Annuler. What an element taken whole
  /// was covering is uncovered, not erased: a click on a star keeps the sky
  /// behind it. Those elements are out of the eraser's reach until the
  /// gesture ends; the traits under a trait that is cut stay in reach, so
  /// that a rub goes on through them. The page of a colouring page is never
  /// in its reach.
  void _eraseAt(DocumentPoint point, double scale) {
    final targets = _eraserTargetsAt(point, scale);
    _eraserPress = point;
    _eraserPressCut = targets.cut;
    final whole = targets.whole;
    if (whole != null) _erase([point], scale, removed: [whole]);
  }

  ({List<int> cut, int? whole}) _eraserTargetsAt(
    DocumentPoint point,
    double scale,
  ) => eraserTargets(
    _document!.strokes,
    point,
    reach: _eraserPixels / scale,
    paintOrder: _document!.unlockedPaintOrder,
    preparedBounds: _boundsForObject,
    shielded: _eraserShield.contains,
  );

  // A rub along [path], points of the sheet: what it cuts and what it takes
  // whole, gathered at each of its points before anything changes.
  void _rubAlong(List<DocumentPoint> path, double scale) {
    final cut = <int>{};
    final removed = <int>{};
    for (final point in path) {
      final targets = _eraserTargetsAt(point, scale);
      cut.addAll(targets.cut);
      if (targets.whole != null) removed.add(targets.whole!);
    }
    _erase(
      path,
      scale,
      cut: cut.difference(removed).toList(),
      removed: removed.toList(),
    );
  }

  void _erase(
    List<DocumentPoint> path,
    double scale, {
    List<int> cut = const [],
    List<int> removed = const [],
  }) {
    if (cut.isEmpty && removed.isEmpty) return;
    final document = _document!;
    // What lies behind what changes, before it changes: behind an element
    // taken whole, everything; behind a trait that is cut, what would be
    // taken whole.
    final changing = {...cut, ...removed};
    final behind = <StrokeData>[];
    for (final other in document.unlockedPaintOrder) {
      if (changing.contains(other)) continue;
      final object = document.strokes[other];
      final area = shownBounds(
        object,
        includeStroke: true,
        points: _boundsForObject(other, object),
      );
      for (final index in changing) {
        if (document.unlockedPaintOrder.indexOf(index) <
            document.unlockedPaintOrder.indexOf(other)) {
          continue;
        }
        final front = document.strokes[index];
        final covers = shownBounds(
          front,
          includeStroke: true,
          points: _boundsForObject(index, front),
        ).overlaps(area);
        if (covers && (removed.contains(index) || !erasesByCutting(object))) {
          behind.add(object);
          break;
        }
      }
    }
    try {
      final before = document.undoCount;
      final changed = document.erase(
        path,
        _eraserPixels / scale,
        cut: cut,
        removed: removed,
        merge: _eraserCommitted,
      );
      if (changed > 0) {
        _eraserCommitted = true;
        _eraserShield.addAll(behind);
        // After the first rub of a gesture, the core joins the others to its
        // step: one Annuler takes the whole gesture back.
        final change = document.undoCount == before
            ? _HistoryChange.amend
            : _HistoryChange.edit;
        setState(() => _refreshAfterMutation(change: change));
        final now = _eraserClock.elapsed;
        final heard = _eraserHeardAt;
        if (heard == null || now - heard >= _brushHeardEvery) {
          _sound(StudioSound.erase);
          _eraserHeardAt = now;
        }
      }
    } catch (error) {
      _error(error);
    }
  }

  static String get _imageCoversSheet => tr(
    'Une image couvre toute la feuille. Touche un élément pour le colorier.',
  );
  static String get _stampKeepsColours => tr('Ce tampon garde ses couleurs.');

  /// The paint pot gives the current colour to what it touches: the inside
  /// of a rectangle, an oval or a contour, the colour of any other element;
  /// on the paper, the zone that the lines around close (Color 1.1), or the
  /// sheet itself where no line closes anything.
  ///
  /// On a colouring page it sees through the lines of the page, which keep
  /// their colour: a click on or near a line colours the zone under it. A
  /// zone receives the colour of its inside and nothing else, the one change
  /// that its locked layer accepts.
  void _fillAt(DocumentPoint point, double scale) {
    if (_pouring) return;
    final document = _document!;
    final (:index, :order, :poured) = _potTouch(point, scale);
    if (index == null) {
      if (_backgroundImage != null) {
        _showProblem(StudioProblem.notice(_imageCoversSheet));
        return;
      }
      unawaited(_pour(point, scale, poured));
      return;
    }
    final before = document.undoCount;
    try {
      final object = document.strokes[index];
      if (_keepsOwnColours(object)) {
        // No change that nobody could see, and no step for Annuler.
        _showProblem(StudioProblem.notice(_stampKeepsColours));
        return;
      }
      final fills = object.kind.canFill;
      var target = index;
      if (fills && object.fillRgb == null) {
        // A frame that receives an inside must not hide what it was drawn
        // around: like paint poured inside an outline, the new inside
        // stays in front of what was seen through the frame under the
        // pointer, and goes behind every other element of its layer that
        // its box overlaps. Annuler takes the colour away, then, with one
        // more press that shows nothing, puts the frame back where it was.
        // Such a frame is never one of a page: those of a page that have
        // no inside are its lines, out of the pot's reach.
        final seen = hitTestObjects(
          document.strokes,
          point,
          scale: scale,
          tolerancePixels: precisePixels,
          preparedBounds: _boundsForObject,
          paintOrder: order.sublist(0, order.indexOf(index)),
        );
        final from =
            seen != null && document.strokes[seen].layer == object.layer
            ? seen + 1
            : 0;
        final area = _boundsForObject(index, object);
        for (var other = from; other < index; other++) {
          final behind = document.strokes[other];
          // A zone poured by the pot is paint on the paper: the frame stays
          // in front of it.
          if (behind.layer == object.layer &&
              !behind.look.zone &&
              _boundsForObject(
                other,
                behind,
              ).inflate(behind.outlineRadius).overlaps(area)) {
            document.reorderObject(index, other);
            target = other;
            break;
          }
        }
      }
      final look = fills
          ? _pourKind.lookOf(object.look, _previousColor)
          : object.look;
      if (look == object.look) {
        document.setObjectStyle(
          target,
          rgb: fills ? object.rgb : _color,
          width: object.width,
          fillRgb: fills ? _color : null,
        );
      } else {
        // A gradient, or one taken away: the inside and its look together.
        document.setObjectPaint(target, fillRgb: _color, look: look);
      }
    } catch (error) {
      _error(error);
    }
    // Whatever was done before a failure is reported, step by step.
    if (document.undoCount != before) {
      setState(() => _refreshAfterEdits(before));
      _sound(StudioSound.fill);
    }
  }

  /// What the paint pot touches at [point]: the element [index] under it,
  /// null on the paper; [order], what it can colour, bottom first; [poured],
  /// the zones it poured on the active layer. Nothing is changed: the pot
  /// that pours and the preview of what it would colour (Color 1.2) both
  /// ask here.
  ({int? index, List<int> order, Set<int> poured}) _potTouch(
    DocumentPoint point,
    double scale,
  ) {
    final document = _document!;
    // The zones the pot poured on this layer are paper to it: it fills
    // within them or over them.
    final poured = _pouredZones();
    // What the pot can colour, bottom first: everything seen but the lines
    // of a page, whose locked layer keeps them as they are.
    final order = document.lockedLayers.isEmpty && poured.isEmpty
        ? document.paintOrder
        : [
            for (final index in document.paintOrder)
              if (!poured.contains(index) &&
                  (!document.isLockedObject(index) ||
                      document.strokes[index].fillRgb != null))
                index,
          ];
    // The pot touches what is seen under the pointer, then the frame around
    // it; a neighbour that is only near is not what the child pointed at.
    final index =
        _objectAt(
          point,
          scale,
          tolerancePixels: precisePixels,
          insideShapes: true,
          order: order,
        ) ??
        _zoneAlongLine(point, scale);
    return (index: index, order: order, poured: poured);
  }

  /// The zones that the paint pot poured on the active layer.
  Set<int> _pouredZones() {
    final document = _document!;
    final layer = document.activeLayer;
    return {
      for (final index in document.paintOrder)
        if (document.strokes[index].layer == layer &&
            document.strokes[index].look.zone &&
            !document.isLockedObject(index))
          index,
    };
  }

  /// The pot on the paper, or on a zone it poured before: it finds the zone
  /// that the lines around [point] close, plugging gaps narrower than about
  /// three millimetres where that is allowed, and pours it as a contour of
  /// its own, under the lines, over the zones it overlaps. Where no line
  /// closes anything the sheet takes the colour, as in Color 1.0; the zone
  /// found again changes colour.
  Future<void> _pour(
    DocumentPoint point,
    double viewScale,
    Set<int> poured,
  ) async {
    final document = _document!;
    final found = _potPaperAt(point, viewScale, poured);
    final _PotPaper? paper;
    if (found is Future<_PotPaper?>) {
      // The pot reads the drawing as an image: a moment.
      setState(() => _pouring = true);
      try {
        paper = await found;
      } catch (error) {
        _error(error);
        return;
      } finally {
        _pouring = false;
        if (mounted) setState(() {});
      }
    } else {
      paper = found;
    }
    // Anything done meanwhile won: nothing to pour.
    if (paper == null || !mounted || !identical(_document, document)) return;
    final points = paper.points;
    if (points == null) {
      _pourOver(paper.zone);
      return;
    }
    try {
      final rings = paper.rings!;
      final before = document.undoCount;
      document.addObject(
        VectorKind.contour,
        points,
        rgb: _color,
        width: _zoneOutline,
        fillRgb: _color,
        look: _pourKind.lookOf(ObjectLook.pouredZone, _previousColor),
        rings: rings.length > 1 ? rings : null,
        quant: 4,
        bottom: paper.above == null,
        above: paper.above,
      );
      setState(() => _refreshAfterEdits(before));
      _sound(StudioSound.fill);
    } catch (error) {
      _error(error);
    }
  }

  /// What the pot would do on the paper at [point], or on a zone it poured
  /// before: null when it would do nothing — on the edge of a line —, or
  /// when the drawing changed while it was read. At once where no image of
  /// the drawing is needed; nothing is changed either way.
  FutureOr<_PotPaper?> _potPaperAt(
    DocumentPoint point,
    double viewScale,
    Set<int> poured,
  ) {
    final document = _document!;
    final under = poured.isEmpty
        ? null
        : _objectAt(
            point,
            viewScale,
            tolerancePixels: precisePixels,
            insideShapes: true,
            order: [
              for (final index in document.paintOrder)
                if (poured.contains(index)) index,
            ],
          );
    final ink = [
      for (final index in document.paintOrder)
        if (!poured.contains(index)) index,
    ];
    // A colouring page draws its zones itself: beside them is the sheet, as
    // in Color 1.0.
    if (ink.isEmpty || document.lockedLayers.isNotEmpty) {
      return _PotPaper.over(under);
    }
    return _potZoneAt(point, viewScale, poured, under, ink);
  }

  Future<_PotPaper?> _potZoneAt(
    DocumentPoint point,
    double viewScale,
    Set<int> poured,
    int? under,
    List<int> ink,
  ) async {
    final document = _document!;
    final revision = _documentRevision;
    final mask = await _inkMask(ink);
    // Anything done meanwhile wins: the drawing the zone was found in is
    // no longer the one shown.
    if (!mounted ||
        !identical(_document, document) ||
        revision != _documentRevision) {
      return null;
    }
    final (x, y) = mask.pixelAt(point);
    final zone = RustDocument.fillZone(
      mask.bytes,
      mask.width,
      mask.height,
      x,
      y,
      potRadius(
        viewScale: viewScale,
        mask: mask,
        closesGaps: potClosesGaps(_countrySigns, DateTime.now()),
      ),
    );
    if (zone.onInk || zone.wholeSheet) {
      // On the edge of a line, nothing to pour but what is under it.
      return zone.wholeSheet || under != null ? _PotPaper.over(under) : null;
    }
    final points = zonePointsOnSheet(
      zone,
      mask,
      sheetWidth: document.width,
      sheetHeight: document.height,
    );
    final rings = zone.rings!.toList();
    final pixel = 1 / math.min(mask.scaleX, mask.scaleY);
    if (under != null &&
        isSameZone(
          document.strokes[under],
          points,
          rings,
          tolerance: 2 * pixel + 1,
        )) {
      return _PotPaper.over(under);
    }
    // Over every zone poured before that it overlaps, under the rest.
    final box = shownBounds(
      StrokeData(points, _color, 1, kind: VectorKind.contour),
      includeStroke: false,
    );
    int? above;
    for (final index in poured) {
      if ((above == null || index > above) &&
          _boundsForObject(index, document.strokes[index]).overlaps(box)) {
        above = index;
      }
    }
    return _PotPaper.zone(points, rings, above);
  }

  // The ink of the drawing as the paint pot reads it, kept while the
  // drawing stays what it is: the preview of the pot asks for it each time
  // the pointer rests, and the press that follows finds it made (Color
  // 1.2). By the elements it holds, in their order.
  final _inkMasks = <String, Future<InkMask>>{};

  Future<InkMask> _inkMask(List<int> indices) {
    final document = _document!;
    if (_inkMasks.length >= 3) _forgetInk();
    return _inkMasks[indices.join(',')] ??= renderInkMask(
      [for (final index in indices) _strokes[index]],
      sheetWidth: document.width,
      sheetHeight: document.height,
      keepImage: true,
    );
  }

  /// The drawing changed, or the pot is put down: its images go, and with
  /// them the preview that was painted through one.
  void _forgetInk() {
    if (_inkMasks.isEmpty) return;
    if (_hint.preview is PourPreview) _hint.preview = null;
    for (final mask in _inkMasks.values) {
      unawaited(
        mask.then<void>((mask) => mask.image?.dispose(), onError: (_) {}),
      );
    }
    _inkMasks.clear();
  }

  /// The outline of a poured zone, in its colour: it hides the seam between
  /// the zone and the lines that close it.
  static const _zoneOutline = .5;

  /// The colour of the pot given to the zone [zone] poured before, or to the
  /// sheet when it is null. A gradient on the sheet of a drawing is a zone
  /// of the whole sheet, under everything: the paper has one colour.
  void _pourOver(int? zone) {
    final document = _document!;
    final before = document.undoCount;
    try {
      if (zone == null) {
        if (_pourKind == PourKind.plain || document.lockedLayers.isNotEmpty) {
          document.setPaperColor(_color);
        } else {
          final (w, h) = (
            document.width.toDouble(),
            document.height.toDouble(),
          );
          document.addObject(
            VectorKind.contour,
            [
              const DocumentPoint(0, 0),
              DocumentPoint(w, 0),
              DocumentPoint(w, h),
              DocumentPoint(0, h),
            ],
            rgb: _color,
            width: _zoneOutline,
            fillRgb: _color,
            look: _pourKind.lookOf(ObjectLook.pouredZone, _previousColor),
            quant: 4,
            bottom: true,
          );
        }
      } else {
        final object = document.strokes[zone];
        final look = _pourKind.lookOf(object.look, _previousColor);
        if (look == object.look) {
          document.setObjectStyle(
            zone,
            rgb: _color,
            width: object.width,
            fillRgb: _color,
          );
        } else {
          document.setObjectPaint(zone, fillRgb: _color, look: look);
        }
      }
    } catch (error) {
      _error(error);
    }
    if (document.undoCount != before) {
      setState(() => _refreshAfterEdits(before));
      _sound(StudioSound.fill);
    }
  }

  /// The zone of a colouring page drawn by the line of the page under the
  /// pointer, when the pointer is over no zone and nothing drawn: on the
  /// outer half of a thick outline, the pot colours the shape that the line
  /// draws, not the sheet around it. Null when the pointer is on no line of
  /// the page, or on one that no zone follows.
  int? _zoneAlongLine(DocumentPoint point, double scale) {
    final document = _document!;
    if (document.lockedLayers.isEmpty) return null;
    final strokes = document.strokes;
    final lines = <int>[];
    final zones = <int>[];
    for (final index in document.paintOrder) {
      if (!document.isLockedObject(index)) continue;
      (strokes[index].fillRgb == null ? lines : zones).add(index);
    }
    if (lines.isEmpty || zones.isEmpty) return null;
    final line = _objectAt(
      point,
      scale,
      tolerancePixels: precisePixels,
      order: lines,
    );
    if (line == null) return null;
    // The zone whose edge lies under the line, as far as half its width.
    return _objectAt(
      point,
      scale,
      tolerancePixels: precisePixels + strokes[line].width / 2 * scale,
      order: zones,
    );
  }

  void _togglePicking() {
    if (_busy || _confirmationOpen) return;
    // The pipette is one more way to choose a colour between the two clicks
    // of a shape: like a colour of the palette, it leaves the first click
    // waiting.
    _settleLatch();
    final waiting = _pointer == null ? _shapeAnchor : null;
    _cancelDraft();
    setState(() {
      _picking = !_picking;
      if (waiting != null) {
        _shapeAnchor = waiting
          ..end = null
          ..rawEnd = null;
      }
    });
    _focus.requestFocus();
  }

  static String get _nothingToPick =>
      tr('Clique sur un élément de ton dessin pour reprendre sa couleur.');

  /// The pipette reads the colour under the pointer and chooses it, exactly
  /// as a click in the palette would: a chosen element takes it at once.
  /// The element that lends its colour is never changed, and may be one of
  /// the page of a colouring page.
  void _pickColorAt(DocumentPoint point, double scale) {
    final document = _document!;
    // Only ink, under the pointer: the colour taken is the one seen there,
    // the page's too.
    final index = _objectAt(
      point,
      scale,
      tolerancePixels: precisePixels,
      inkOnly: true,
      order: document.paintOrder,
    );
    if (index == null && _backgroundImage != null) {
      // The pixels of a background image are not read: drawn elements answer.
      _showProblem(StudioProblem.notice(forTouch(_nothingToPick)));
      return;
    }
    final chosen = _selectedObject;
    if (index == null && chosen != null && !_keepsOwnColours(chosen)) {
      // A chosen element takes the picked colour at once: a click that
      // misses every element must not turn it the colour of the paper.
      _showProblem(StudioProblem.notice(forTouch(_nothingToPick)));
      return;
    }
    final rgb = index == null
        ? document.paperRgb
        : colourOfObjectAt(document.strokes[index], point, scale: scale);
    _recentColors.remember(rgb);
    setState(() {
      _picking = false;
      _chooseColor(rgb);
    });
    _sound(StudioSound.colour);
  }

  // Where a chosen colour goes: the inside of shapes when that target is
  // selected, the main colour otherwise. A chosen element takes it at once.
  void _chooseColor(int rgb) {
    final chosen = _selectedObject;
    if (_canFill && _colorTarget == PaintColorTarget.fill) {
      if (chosen != null && !_styleSelection(changeFill: true, fillRgb: rgb)) {
        return;
      }
      _fillColor = rgb;
      _filled = true;
    } else {
      // A stamp that keeps its own colours has nothing to take: the colour
      // is then a choice for what comes next.
      if (chosen != null &&
          !_keepsOwnColours(chosen) &&
          !_styleSelection(rgb: rgb)) {
        return;
      }
      if (rgb != _color) _previousColor = _color;
      _color = rgb;
    }
  }

  static const _growFactor = 1.25;
  static const _shrinkFactor = 0.8;
  // Below these sizes an element is hard to see and to catch again.
  static const _smallestExtent = 12.0;
  static const _smallestText = 12.0;

  /// Whether « Plus grand » (a factor above one) or « Plus petit » still has
  /// room: the element must fit the sheet and stay easy to catch.
  bool _canResizeSelection(double factor) {
    if (!_canEditSelection) return false;
    final document = _document!;
    final object = _selectedObject!;
    final bounds = _boundsForObject(_selectedIndex!, object);
    final isText = object.kind == VectorKind.text;
    if (bounds.longestSide == 0) {
      // A single dot has no size of its own: its width is its size.
      return factor > 1 ? object.width < 48 : object.width > 2;
    }
    if (factor > 1) {
      return bounds.width * factor <= document.width &&
          bounds.height * factor <= document.height &&
          (!isText || object.width * factor <= maxTextSize);
    }
    return isText
        ? object.width * factor >= _smallestText
        : bounds.longestSide * factor >= _smallestExtent;
  }

  /// One notch larger or smaller, around the element's centre: one step for
  /// Annuler. Outlines follow the size inside the range of the width slider.
  void _resizeSelection(double factor) {
    if (!_canResizeSelection(factor)) return;
    final document = _document!;
    final index = _selectedIndex!;
    final object = _selectedObject!;
    try {
      final bool changed;
      if (object.kind == VectorKind.text) {
        // A text is measured again at its new size: its box follows its words.
        final size = (object.width * factor)
            .clamp(minTextSize, maxTextSize)
            .toDouble();
        final layout = TextLayout(object.text!, size: size, rgb: object.rgb);
        final center = _boundsForObject(index, object).center;
        final box = textBoxAt(
          DocumentPoint(
            center.dx - layout.width / 2,
            center.dy - layout.height / 2,
          ),
          layout,
          pageWidth: document.width.toDouble(),
          pageHeight: document.height.toDouble(),
        );
        if (box == null) {
          _showProblem(StudioProblem.notice(_textTooLarge));
          return;
        }
        changed = document.setText(
          index,
          box.first,
          box.second,
          text: object.text!,
          rgb: object.rgb,
          size: size,
        );
      } else {
        final width = object.kind == VectorKind.stamp
            ? object.width
            : (object.width * factor)
                  .clamp(
                    math.min(object.width, 2.0),
                    math.max(object.width, 48.0),
                  )
                  .toDouble();
        changed = document.scaleObject(index, factor, width: width);
      }
      setState(() {
        if (changed) _refreshAfterMutation();
        // The slider follows the outline of the resized element.
        final resized = _selectedObject!;
        if (!resized.kind.isBoxObject) {
          _width = resized.width.clamp(2.0, 48.0).toDouble();
        }
      });
    } on RustCoreException {
      _showProblem(
        StudioProblem.notice(
          factor > 1
              ? tr('Cet élément ne peut pas être plus grand sur cette feuille.')
              : tr('Cet élément ne peut pas être plus petit.'),
        ),
      );
    } catch (error) {
      _error(error);
    }
    _focus.requestFocus();
  }

  // « La pointe » and the preview before a tool acts (Color 1.2).

  /// What the layer over the sheet shows: the pointer of the tool in hand,
  /// and what a press would do where it is. See sheet_hint.dart.
  final _hint = SheetHint();

  /// Where the pointer that the preview follows is, in the frame of the
  /// sheet: the mouse that hovers, the finger on the sheet, the pointer of
  /// the keyboard. Null when none is over the sheet.
  Offset? _hintAt;

  /// The pointer of the keyboard moved last: a mouse that leaves the sheet
  /// does not take its preview away.
  bool _hintByKey = false;

  /// That pointer is a finger. A finger does not hover: it shows a preview
  /// only of what it is doing — the pot it holds, the eraser it rubs with.
  bool _hintByFinger = false;

  /// A finger or a pen holds the paint pot on the sheet: the part it would
  /// colour is hatched and follows the finger; the paint flows where the
  /// finger is lifted. [_potAt] is where it is, in the frame of the sheet.
  bool _potHeld = false;
  Offset? _potAt;

  /// How long the pointer rests before the pot looks at what it would
  /// colour there: while it travels, nothing is read.
  static const _pourHintRest = Duration(milliseconds: 60);
  Timer? _pourHintTimer;
  int _pourHintSerial = 0;

  /// What the preview of the pot was last asked for: nothing is read again
  /// for the same point of the same drawing in the same colour.
  ({double x, double y, int revision, int rgb, PourKind kind})? _pourHintAsked;

  /// Where the pot has just poured: no preview there, over what the child
  /// has just coloured, until the pointer moves away.
  Offset? _pourHintQuiet;

  /// The pointer of the tool in hand; null where the pointer of the system
  /// says more: the hand that moves the sheet, the pipette.
  ToolPointer? get _toolPointer =>
      _panning || _spaceHeld || _picking ? null : ToolPointer(_tool, _color);

  /// A real pointer is on the sheet: the preview follows it, and « la
  /// pointe » when it is a mouse.
  void _hintFollows(PointerEvent event) {
    _hintAt = event.localPosition;
    _hintByKey = false;
    _hintByFinger = event.kind == PointerDeviceKind.touch;
    if (event.kind == PointerDeviceKind.mouse) {
      _hint.mouseAt = event.localPosition;
    }
    _pointerOverDecor(
      event.localPosition,
      mouse: event.kind == PointerDeviceKind.mouse,
    );
  }

  /// A finger or a pen left the sheet: nothing is under it any more. A
  /// mouse stays where it is.
  void _hintLifted(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse && !_hintByKey) _hintAt = null;
  }

  /// The mouse left the frame of the sheet.
  void _hintLeft() {
    if (!mounted) return;
    _hint.mouseAt = null;
    if (!_hintByKey && !_potHeld) _hintAt = null;
    _refreshHint();
  }

  void _dropPourHint() {
    _pourHintTimer?.cancel();
    _pourHintTimer = null;
    _pourHintSerial++;
    _pourHintAsked = null;
  }

  /// Says again what the layer over the sheet shows: after every move of a
  /// pointer, and at every build of the sheet — the tool, the colour, a
  /// size or the view may have changed. It builds nothing.
  void _refreshHint() {
    if (!mounted) return;
    final viewport = _keyViewport;
    final pointer = _toolPointer;
    _hint
      ..pointer = pointer
      ..keyAt = _options.keyboardPointer ? _keyPointerAt : null;
    final document = _document;
    if (_tool != StudioTool.fill) _dropPourHint();
    if (viewport == null ||
        document == null ||
        pointer == null ||
        _busy ||
        _confirmationOpen ||
        _viewMoving) {
      _dropPourHint();
      _hint.preview = null;
      return;
    }
    // The text waits for the pointer to be released: its stroke stays where
    // the press began.
    final anchor = _textAnchor;
    if (anchor != null) {
      _hint.preview = _caretAt(anchor);
      return;
    }
    final at = _hintAt;
    if (at == null) {
      _dropPourHint();
      _hint.preview = null;
      return;
    }
    final onSheet = viewport.contains(at.dx, at.dy);
    // Nothing is promised while a gesture goes on: what it makes is seen.
    final idle = _pointer == null && _latch == null && !_hintByFinger;
    switch (_tool) {
      case StudioTool.fill:
        if (onSheet && (idle || _potHeld)) {
          _pourHintAt(at, viewport.point(at.dx, at.dy), viewport.scale);
        } else {
          _dropPourHint();
          _hint.preview = null;
        }
      case StudioTool.eraser:
        _hint.preview = idle || _erasing
            ? EraserPreview(at: at, radius: _eraserPixels)
            : null;
      case StudioTool.select:
        _hint.preview = null;
      case StudioTool.text:
        _hint.preview = onSheet && idle
            ? _caretAt(viewport.point(at.dx, at.dy))
            : null;
      case StudioTool.stamp:
        _hint.preview = onSheet && idle
            ? _stampPreviewAt(viewport.point(at.dx, at.dy))
            : null;
      case StudioTool.brush ||
          StudioTool.magic ||
          StudioTool.magnet ||
          StudioTool.line ||
          StudioTool.rectangle ||
          StudioTool.ellipse ||
          StudioTool.shapes:
        // Between the two clicks of a shape, the shape itself is shown.
        _hint.preview = onSheet && idle && _shapeAnchor == null
            ? _dotAt(at)
            : null;
    }
  }

  // A dot of the size and colour of the trait the tool would begin.
  DotPreview _dotAt(Offset at) {
    final tool = _strokeTool;
    return DotPreview(
      at: at,
      width: _width,
      rgb: _color,
      square: tool == BrushTool.felt,
      opacity: tool == BrushTool.felt ? markerAlpha / 255 : 1,
      // The rainbow and the confetti have colours of their own.
      hollow: tool == BrushTool.rainbow || tool == BrushTool.confetti,
      mirrored: _tool == StudioTool.magic && _magic == Magic.mirror,
    );
  }

  // The stroke where the first letter of a text begun at [anchor] would be
  // written, at the size chosen last: the top of its first line, kept on
  // the sheet as the text will be.
  CaretPreview _caretAt(DocumentPoint anchor) {
    final document = _document!;
    final height =
        textSizeFor(_textSize, width: document.width, height: document.height) *
        textFonts[_textFont].lineHeight;
    return CaretPreview(
      top: DocumentPoint(
        anchor.x,
        anchor.y.clamp(0.0, math.max(0.0, document.height - height)).toDouble(),
      ),
      height: height,
      rgb: _color,
    );
  }

  // The stamp a click at [point] would pose: the chosen one, at the chosen
  // size, turned and mirrored as chosen, where [_stampBox] puts it.
  PosedStampPreview? _stampPreviewAt(DocumentPoint point) {
    try {
      final box = _stampBox(point, point);
      return PosedStampPreview(
        RenderedElement(
          StrokeData(
            [box.first, box.second],
            _color,
            1,
            kind: VectorKind.stamp,
            stamp: _stampId,
            look: _stampLook,
          ),
        ),
      );
    } catch (_) {
      // A stamp that cannot be shown is still posed by the click.
      return null;
    }
  }

  /// The preview of the paint pot for the pointer at [at], [point] of the
  /// sheet. What is shown stays while the pointer travels on it; the pot
  /// looks again once the pointer has rested, at once under a finger that
  /// has just come down.
  void _pourHintAt(Offset at, DocumentPoint point, double scale) {
    final quiet = _pourHintQuiet;
    if (quiet != null) {
      if ((at - quiet).distance < 4) {
        _dropPourHint();
        _hint.preview = null;
        return;
      }
      _pourHintQuiet = null;
    }
    final asked = _pourHintAsked;
    final same =
        asked != null &&
        asked.revision == _documentRevision &&
        asked.rgb == _color &&
        asked.kind == _pourKind;
    if (same && asked.x == point.x && asked.y == point.y) return;
    final shown = _hint.preview;
    if (!(same && shown is PourPreview && shown.covers(point))) {
      _hint.preview = null;
    }
    final first = asked == null && _potHeld;
    _pourHintAsked = (
      x: point.x,
      y: point.y,
      revision: _documentRevision,
      rgb: _color,
      kind: _pourKind,
    );
    final serial = ++_pourHintSerial;
    _pourHintTimer?.cancel();
    _pourHintTimer = Timer(
      first ? Duration.zero : _pourHintRest,
      () => unawaited(_showPourHint(serial, point, scale)),
    );
  }

  Future<void> _showPourHint(
    int serial,
    DocumentPoint point,
    double scale,
  ) async {
    _pourHintTimer = null;
    if (!mounted || serial != _pourHintSerial || _document == null) return;
    PourPreview? preview;
    try {
      preview = await _pourPreviewAt(point, scale);
    } catch (_) {
      // Without its preview the pot still pours.
    }
    if (!mounted || serial != _pourHintSerial) return;
    _hint.preview = preview;
  }

  /// More elements than this over what the pot would colour are left out
  /// of its hatching as one picture rather than one by one.
  static const _pourOverMost = 48;

  /// What the pot would colour at [point], found as [_fillAt] finds it;
  /// null where a press would change nothing that can be seen.
  Future<PourPreview?> _pourPreviewAt(DocumentPoint point, double scale) async {
    final document = _document!;
    if (_pouring) return null;
    final plain = _pourKind == PourKind.plain;
    final revision = _documentRevision;
    bool stale() =>
        !mounted ||
        !identical(document, _document) ||
        revision != _documentRevision;
    Future<PourPreview?> onElement(int index) async {
      final object = document.strokes[index];
      if (_keepsOwnColours(object)) return null;
      final fills = object.kind.canFill;
      if (plain &&
          !object.look.hasGradient &&
          (fills ? object.fillRgb : object.rgb) == _color) {
        return null;
      }
      // What is painted after it and lies on it hides a part of it.
      final seen = document.paintOrder;
      final area = _strokes[index].shownBounds.inflate(object.width / 2 + 1);
      final rank = seen.indexOf(index);
      final above = [
        for (final other in rank < 0 ? const <int>[] : seen.skip(rank + 1))
          if (_strokes[other].shownBounds
              .inflate(document.strokes[other].width / 2 + 1)
              .overlaps(area))
            other,
      ];
      ui.Image? ink;
      if (above.length > _pourOverMost) {
        ink = (await _inkMask(above)).image;
        if (stale()) return null;
      }
      return PourPreview.element(
        _strokes[index],
        inside: fills,
        rgb: _color,
        ink: ink,
        over: ink == null
            ? [for (final other in above) _strokes[other]]
            : const [],
      );
    }

    final (:index, order: _, :poured) = _potTouch(point, scale);
    if (index != null) return onElement(index);
    if (_backgroundImage != null) return null;
    final paper = await _potPaperAt(point, scale, poured);
    if (paper == null || stale()) return null;
    final points = paper.points;
    if (points != null) {
      final zone = Path()..fillType = PathFillType.evenOdd;
      var at = 0;
      for (final ring in paper.rings!) {
        zone.moveTo(points[at].x, points[at].y);
        for (var k = 1; k < ring; k++) {
          zone.lineTo(points[at + k].x, points[at + k].y);
        }
        zone.close();
        at += ring;
      }
      // It is poured under the lines that close it, which were just read.
      final mask = await _inkMask([
        for (final index in document.paintOrder)
          if (!poured.contains(index)) index,
      ]);
      if (stale()) return null;
      return PourPreview.zone(zone, rgb: _color, ink: mask.image);
    }
    final zone = paper.zone;
    if (zone != null) return onElement(zone);
    // The paper itself: all of it, but what is drawn on it.
    if (plain && document.paperRgb == _color) return null;
    final seen = document.paintOrder;
    if (seen.isEmpty) return PourPreview.sheet(rgb: _color);
    final mask = await _inkMask(seen);
    if (stale()) return null;
    return PourPreview.sheet(rgb: _color, ink: mask.image);
  }

  void _pointerDown(PointerDownEvent event, DocumentViewport viewport) {
    if (_latch != null) {
      // The click that ends what a click began. It does nothing else, and
      // the click that began it, pressed twice, does not end it at once.
      if ((event.buttons & kPrimaryButton) != 0 && !_isBounce(event)) {
        _endLatch();
        _guardBounce(event.localPosition);
      }
      return;
    }
    // A pen that comes down while the hand rests on the screen takes the
    // sheet (D-08): two fingers of the hand that were moving the view stop,
    // and what a finger was doing goes — a trait, a shape, the eraser, a
    // drag — except the first click of a shape, which the pen made.
    if (_isPen(event.kind)) {
      if (_pinching) {
        _pinching = false;
        _endViewGesture();
      }
      if (_pointer != null && _drawingKind == PointerDeviceKind.touch) {
        final anchor = _draftFromAnchor ? _shapeAnchor : null;
        _cancelDraft();
        if (anchor != null) {
          _shapeAnchor = anchor
            ..end = null
            ..rawEnd = null;
        }
      }
    }
    if (_busy ||
        _confirmationOpen ||
        _document == null ||
        _pointer != null ||
        _panPointer != null ||
        _trackpadPointer != null ||
        (event.buttons & (kPrimaryButton | kMiddleMouseButton)) == 0) {
      return;
    }
    // The click that has just ended such a gesture, or chosen an element,
    // pressed twice: no dot, no new trait, and the element is not taken.
    if (_isBounce(event)) return;
    _focus.requestFocus();
    _spaceHeld = HardwareKeyboard.instance.logicalKeysPressed.contains(
      LogicalKeyboardKey.space,
    );
    if (_options.viewControls &&
        (_panning || _spaceHeld || (event.buttons & kMiddleMouseButton) != 0)) {
      _panPointer = event.pointer;
      _panLast = event.localPosition;
      _panStart = event.localPosition;
      _panTravel = 0;
      _panByMouse = event.kind == PointerDeviceKind.mouse;
      return;
    }
    _pressByMouse = event.kind == PointerDeviceKind.mouse;
    _drawingKind = event.kind;
    final onSheet = viewport.contains(
      event.localPosition.dx,
      event.localPosition.dy,
    );
    if (_picking) {
      // Beside the sheet there is no colour to take: the pipette stays
      // ready, and the chosen element stays chosen.
      if (onSheet) {
        _pickColorAt(
          viewport.point(event.localPosition.dx, event.localPosition.dy),
          viewport.scale,
        );
      }
      return;
    }
    if (_tool == StudioTool.eraser) {
      // A glide may start beside the sheet and then cross it.
      setState(() {
        _pointer = event.pointer;
        _erasing = true;
        _eraserLast = event.localPosition;
        _eraserShield.clear();
        _eraserPress = null;
        _eraserPressCut = const [];
        _eraserRubbed = false;
        _eraserCommitted = false;
        _eraserHeardAt = null;
        _pressPosition = event.localPosition;
        _pressByTouch = event.kind == PointerDeviceKind.touch;
      });
      if (onSheet) {
        _eraseAt(
          viewport.point(event.localPosition.dx, event.localPosition.dy),
          viewport.scale,
        );
      }
      return;
    }
    if (!onSheet) {
      if (_choosing) setState(() => _setSelection(null));
      return;
    }
    final point = viewport.point(
      event.localPosition.dx,
      event.localPosition.dy,
    );
    if (_tool == StudioTool.fill) {
      if (event.kind == PointerDeviceKind.mouse) {
        // The mouse saw what would be coloured before it clicked.
        _pourHintQuiet = event.localPosition;
        _fillAt(point, viewport.scale);
        return;
      }
      // A finger or a pen shows it first: the part it would colour is
      // hatched under it, follows it, and takes the paint when it is lifted
      // (Color 1.2).
      _pointer = event.pointer;
      _potHeld = true;
      _potAt = event.localPosition;
      _pressPosition = event.localPosition;
      _pressTravel = 0;
      _pressByTouch = event.kind == PointerDeviceKind.touch;
      return;
    }
    if (_choosing) {
      final found = _objectAt(
        point,
        viewport.scale,
        tolerancePixels: reachPixels(
          touch: event.kind == PointerDeviceKind.touch,
          touchScreen: touchFirst,
        ),
      );
      if (found != null && found != _selectedIndex) _sound(StudioSound.select);
      _pressOnChosen = found != null && found == _selectedIndex;
      _pressPosition = event.localPosition;
      _pressTravel = 0;
      _pressByTouch = event.kind == PointerDeviceKind.touch;
      setState(() {
        final index = found;
        if (index != _selectedIndex) _setSelection(index);
        if (index != null) {
          _pointer = event.pointer;
          _selectionStart = point;
          _selectionDragBounds = _boundsForObject(index, _selectedObject!);
          _selectionOffset.value = Offset.zero;
        }
      });
      return;
    }
    if (!_followVisibleLayer(_document!)) {
      // Nothing drawn now could be seen: say so instead of drawing blind.
      _showProblem(
        StudioProblem.notice(
          _options.layers ? _allLayersHidden : _allLayersHiddenElsewhere,
        ),
      );
      return;
    }
    final kind = _tool.kind;
    if (kind == null) return;
    if (kind == VectorKind.text) {
      // Writing starts when the pointer is released, in its own dialog.
      setState(() {
        _pointer = event.pointer;
        _textAnchor = point;
      });
      return;
    }
    // A shape begun with a click ends where this press is released.
    final anchor = _shapeAnchor?.kind == kind ? _shapeAnchor : null;
    void begin() {
      _pointer = event.pointer;
      _draftKind = kind;
      _draftStamp = _stampId;
      _drafting.stampLook = _stampLook;
      _draftFillRgb = _filled && _tool.drawsFillableShape ? _fillColor : null;
      _pressPosition = event.localPosition;
      _pressTravel = 0;
      _pressByTouch = event.kind == PointerDeviceKind.touch;
      _draftFromAnchor = anchor != null;
      if (anchor != null) {
        anchor
          ..end = null
          ..rawEnd = null;
        _draft = [anchor.start, _shapeEndFrom(anchor.start, point, kind)];
      } else {
        _shapeAnchor = null;
        _draft = kind == VectorKind.stroke ? [point] : [point, point];
      }
      _draftRawEnd = point;
      _draftColor = _color;
      _draftWidth = _width;
      _draftStroke = DraftStroke(_draft.first);
      _draftSeen = null;
      _drafting.resetLook();
      if (kind == VectorKind.stroke) {
        final tool = _strokeTool;
        _drafting.tool = tool;
        _drafting.seed = tool.scatters ? 1 + _seeds.nextInt(1 << 30) : 0;
        if (_tool == StudioTool.magic && _magic == Magic.mirror) {
          _drafting.mirrorWidth = _document!.width.toDouble();
        }
        // The magnet straightens what is drawn: no pressure to keep.
        final pressure = _tool == StudioTool.magnet ? null : _pressureOf(event);
        if (pressure != null) _drafting.pressures = [pressure];
        _markDraft();
      } else if (kind == VectorKind.contour) {
        _drafting.shape = _newShape;
      }
      // A finger trembles, and a pen a little: their samples are smoothed;
      // a mouse is followed as it is.
      _steady =
          kind == VectorKind.stroke &&
              (event.kind == PointerDeviceKind.touch || _isPen(event.kind))
          ? (OneEuroFilter()..filter(
              event.localPosition.dx,
              event.localPosition.dy,
              event.timeStamp,
            ))
          : null;
      _string = kind == VectorKind.stroke && _options.steadyHand
          ? (StringStabilizer()
              ..pull(event.localPosition.dx, event.localPosition.dy))
          : null;
    }

    // Only the sheet changes when a press begins a trait or a shape: it is
    // painted again, and the studio is not built again (F-03). The two
    // clicks of a shape change what the sheet shows of them and what
    // « Annuler » offers: then it is.
    if (anchor != null || _shapeAnchor != null || _draftFromAnchor) {
      setState(() {
        begin();
        _revision++;
      });
    } else {
      begin();
      _canvasRepaint.value++;
    }
    if (kind == VectorKind.stroke) {
      _sound(StudioSound.stroke);
      _brushHeardAt = event.timeStamp;
      _brushTravel = 0;
      _brushLastPosition = event.localPosition;
    }
  }

  // Where a shape that starts at [start] ends when the pointer is at [raw]:
  // Maj straightens a line and squares a rectangle or an oval.
  DocumentPoint _shapeEndFrom(
    DocumentPoint start,
    DocumentPoint raw,
    VectorKind kind,
  ) => shapeEnd(
    start,
    raw,
    kind: kind,
    // A stamp keeps the proportions of its drawing.
    constrain:
        kind == VectorKind.stamp || HardwareKeyboard.instance.isShiftPressed,
    documentWidth: _document!.width.toDouble(),
    documentHeight: _document!.height.toDouble(),
  );

  /// The pointer moves with no button pressed: a shape begun with a click
  /// follows it, to show what the next click would make.
  void _pointerHover(PointerHoverEvent event, DocumentViewport viewport) {
    switch (_latch) {
      case _Latch.pan:
        _panTo(event.localPosition);
        return;
      case _Latch.move:
        _dragSelectionTo(event.localPosition, viewport);
        return;
      case _Latch.stroke:
        _extendDraftTo(
          event.localPosition,
          viewport,
          at: event.timeStamp,
          pressure: _pressureOf(event),
        );
        return;
      case null:
        break;
    }
    final anchor = _shapeAnchor;
    if (anchor == null || _pointer != null) return;
    final position = event.localPosition;
    // Nothing is promised where a click would draw nothing: beside the
    // sheet, while the hand moves the sheet, and on the little circle
    // itself, where a click takes it away.
    if (_busy ||
        _confirmationOpen ||
        _panning ||
        _spaceHeld ||
        !viewport.contains(position.dx, position.dy)) {
      _forgetAnchorEnd();
      return;
    }
    final raw = viewport.point(position.dx, position.dy);
    final away =
        math.sqrt(
          math.pow(raw.x - anchor.start.x, 2) +
              math.pow(raw.y - anchor.start.y, 2),
        ) *
        viewport.scale;
    if (away <= shapeMarkReach(touch: false)) {
      _forgetAnchorEnd();
      return;
    }
    anchor
      ..rawEnd = raw
      ..end = _shapeEndFrom(anchor.start, raw, anchor.kind);
    _canvasRepaint.value++;
  }

  // The pointer left the sheet: the preview of the shape begun with a click
  // goes; its little circle stays.
  void _forgetAnchorEnd() {
    final anchor = _shapeAnchor;
    if (anchor == null || anchor.end == null) return;
    anchor
      ..end = null
      ..rawEnd = null;
    _canvasRepaint.value++;
  }

  // The sheet follows the hand to [position].
  void _panTo(Offset position) {
    final delta = position - _panLast!;
    _panLast = position;
    _changeView(_view!.panBy(delta.dx, delta.dy));
  }

  // The chosen element follows the pointer to [position], inside the sheet.
  void _dragSelectionTo(Offset position, DocumentViewport viewport) {
    final raw = viewport.point(position.dx, position.dy);
    _selectionOffset.value = clampBoundsMovement(
      _selectionDragBounds!,
      Offset(raw.x - _selectionStart!.x, raw.y - _selectionStart!.y),
      pageWidth: _document!.width.toDouble(),
      pageHeight: _document!.height.toDouble(),
    );
    _canvasRepaint.value++;
  }

  // The trait or the shape in progress reaches [position], at the time [at]
  // of the pointer.
  void _extendDraftTo(
    Offset position,
    DocumentViewport viewport, {
    Duration? at,
    int? pressure,
  }) {
    var place = position;
    final steady = _steady;
    if (steady != null && at != null && _draftKind == VectorKind.stroke) {
      final (x, y) = steady.filter(position.dx, position.dy, at);
      place = Offset(x, y);
      _draftSeen = viewport.point(position.dx, position.dy);
    }
    final string = _string;
    if (string != null && _draftKind == VectorKind.stroke) {
      final (x, y) = string.pull(place.dx, place.dy);
      place = Offset(x, y);
    }
    final raw = viewport.point(place.dx, place.dy);
    _draftRawEnd = raw;
    if (_draftKind == VectorKind.stroke) {
      if (_draft.length >= 100000) return;
      final previous = _draft.last;
      // A move that the eye cannot see is not kept (D-08).
      final dx = (raw.x - previous.x) * viewport.scale;
      final dy = (raw.y - previous.y) * viewport.scale;
      if (dx * dx + dy * dy < unseenMovePixels * unseenMovePixels) return;
      _draft.add(raw);
      _draftStroke!.lineTo(raw);
      final pressures = _drafting.pressures;
      if (pressures != null) pressures.add(pressure ?? pressures.last);
      _markDraft();
      _hearBrush(position, at);
    } else {
      _draft[1] = _shapeEndFrom(_draft.first, raw, _draftKind);
    }
    _revision++;
    // Pointer samples repaint the page without rebuilding the toolbars.
    _canvasRepaint.value++;
  }

  // The marks of the trait being drawn, for a tool of 1.1 or a stylus: the
  // core gives those of the new segments only, the first ones never change
  // as the trait grows. A lone dot has marks of its own, made again once
  // the trait leaves it.
  void _markDraft() {
    final drawn = _drafting;
    if (!drawn.tool.paintsMarks && drawn.pressures == null) return;
    final points = drawn.points;
    if (points.isEmpty) return;
    final pressures = drawn.pressures;
    try {
      if (points.length == 1 || drawn.markedSegments == 0) {
        drawn.marks.clear();
      }
      final from = points.length == 1 ? 0 : drawn.markedSegments;
      final marks = RustDocument.strokeMarks(
        points,
        pressures: pressures == null ? null : Uint8List.fromList(pressures),
        width: drawn.width,
        rgb: drawn.rgb,
        tool: drawn.tool,
        seed: drawn.seed,
        from: from,
      );
      if (marks != null) drawn.marks.addAll(markPaths(marks));
      drawn.markedSegments = points.length - 1;
    } catch (_) {
      // Without the marks the trait is still drawn when it is finished.
    }
  }

  /// The brush keeps sounding while it travels on the sheet: once more each
  /// time its sound is nearly over, as long as the pointer has really moved.
  void _hearBrush(Offset position, Duration? at) {
    final last = _brushLastPosition;
    if (last != null) _brushTravel += (position - last).distance;
    _brushLastPosition = position;
    final heard = _brushHeardAt;
    if (at == null || heard == null) return;
    if (at - heard >= _brushHeardEvery && _brushTravel >= 8) {
      _sound(StudioSound.stroke);
      _brushHeardAt = at;
      _brushTravel = 0;
    }
  }

  void _pointerMove(PointerEvent event, DocumentViewport viewport) {
    if (_panPointer == event.pointer) {
      final start = _panStart;
      if (start != null) {
        _panTravel = math.max(
          _panTravel,
          (event.localPosition - start).distance,
        );
      }
      _panTo(event.localPosition);
      return;
    }
    if (_pointer == event.pointer && _selectionStart != null) {
      final pressed = _pressPosition;
      if (pressed != null) {
        _pressTravel = math.max(
          _pressTravel,
          (event.localPosition - pressed).distance,
        );
      }
      _dragSelectionTo(event.localPosition, viewport);
      return;
    }
    if (_pointer == event.pointer && _erasing) {
      final pressed = _pressPosition;
      // A press that stays where it began is a click: it takes a trait
      // whole when it is released. One that travels rubs.
      if (!_eraserRubbed &&
          pressed != null &&
          (event.localPosition - pressed).distance <
              clickTravel(touch: _pressByTouch)) {
        return;
      }
      _eraserRubbed = true;
      // A quick hand leaves few samples: walk the whole way between two of
      // them, so that a thin line in between is not jumped over.
      final from = _eraserLast ?? event.localPosition;
      final to = event.localPosition;
      _eraserLast = to;
      final steps = ((to - from).distance / 5).ceil().clamp(1, 400);
      final path = <DocumentPoint>[];
      for (var step = 0; step <= steps; step++) {
        final position = Offset.lerp(from, to, step / steps)!;
        // Outside the sheet nothing is touched: positions are not pulled
        // back onto its edge, which would erase what lies there.
        if (viewport.contains(position.dx, position.dy)) {
          path.add(viewport.point(position.dx, position.dy));
        } else if (path.isNotEmpty) {
          _rubAlong(path, viewport.scale);
          path.clear();
        }
      }
      if (path.isNotEmpty) _rubAlong(path, viewport.scale);
      return;
    }
    if (_pointer == event.pointer && _potHeld) {
      _potAt = event.localPosition;
      return;
    }
    if (_pointer != event.pointer || _draft.isEmpty) return;
    final pressed = _pressPosition;
    if (pressed != null) {
      _pressTravel = math.max(
        _pressTravel,
        (event.localPosition - pressed).distance,
      );
    }
    _extendDraftTo(
      event.localPosition,
      viewport,
      at: event.timeStamp,
      pressure: _pressureOf(event),
    );
  }

  /// The press that was just released was a click, and the options ask for
  /// gestures without a held button: what the press began goes on with the
  /// pointer until the next click. True when it does. A finger has no
  /// pointer that moves without touching: it keeps its own gestures.
  bool _beginLatch() {
    final pressed = _pressPosition;
    if (!_options.holdFree ||
        !_pressByMouse ||
        pressed == null ||
        _pressTravel >= clickTravel(touch: false)) {
      return false;
    }
    if (_selectionStart != null) {
      // A click chooses an element; a click on the chosen one takes it.
      if (!_pressOnChosen) {
        // The click that chose it did not mean to move it: the little way
        // a hand trembles while it clicks is not kept.
        _selectionOffset.value = Offset.zero;
        _guardBounce(pressed);
        return false;
      }
      _latch = _Latch.move;
    } else if (_draft.isNotEmpty &&
        _draftKind == VectorKind.stroke &&
        !_erasing &&
        _textAnchor == null) {
      _latch = _Latch.stroke;
    } else {
      return false;
    }
    _guardBounce(pressed);
    _pointer = _latchPointer;
    _pressPosition = null;
    // A trait begun this way was heard when the brush touched the sheet.
    if (_latch != _Latch.stroke) _sound(StudioSound.click);
    setState(() {
      _revision++;
    });
    return true;
  }

  /// The same for the hand that moves the sheet: a click with it takes the
  /// sheet, the next click lets it go.
  bool _beginPanLatch() {
    final pressed = _panStart;
    if (!_options.holdFree ||
        !_panning ||
        !_panByMouse ||
        pressed == null ||
        _panTravel >= clickTravel(touch: false)) {
      return false;
    }
    _guardBounce(pressed);
    _latch = _Latch.pan;
    _panPointer = _latchPointer;
    _panStart = null;
    _sound(StudioSound.click);
    setState(() {});
    return true;
  }

  /// Ends what a click began and keeps it: the trait is drawn, the element
  /// stays where it is, the sheet where the hand left it. By the next click,
  /// or when the pointer leaves the frame of the sheet.
  void _endLatch() {
    final latch = _latch;
    if (latch == null) return;
    _finishStroke();
    if (latch != _Latch.stroke) _sound(StudioSound.click);
    if (mounted) setState(() {});
  }

  /// A command asked while such a gesture goes on — by a key, a menu, a
  /// button reached without the mouse — first keeps what the gesture has
  /// made, as the next click would. Only Échap gives it up.
  void _settleLatch() {
    if (_latch != null) _endLatch();
  }

  void _guardBounce(Offset position) {
    _bounceAt = position;
    _bounceTimer?.cancel();
    _bounceTimer = Timer(_bounceTime, () => _bounceAt = null);
  }

  bool _isBounce(PointerDownEvent event) {
    final at = _bounceAt;
    return at != null &&
        _options.holdFree &&
        event.kind == PointerDeviceKind.mouse &&
        (event.localPosition - at).distance <= _bounceReach;
  }

  /// Ends the gesture in progress, keeping what it has drawn. [released] is
  /// true only when the pointer itself was released: a command that settles
  /// a gesture before it runs (a menu, a key, a dialog) must not open the
  /// text dialog under its own.
  void _finishStroke({bool released = false}) {
    if (released && _beginLatch()) return;
    _latch = null;
    _endViewGesture();
    _finishSelectionDrag();
    if (_potHeld) {
      // The finger that held the paint pot is lifted: the paint flows where
      // it was, on the sheet; beside the sheet, and when a command ended
      // the gesture, nothing is poured.
      final at = _potAt;
      final viewport = _keyViewport;
      _potHeld = false;
      _potAt = null;
      _pointer = null;
      _pressPosition = null;
      if (released &&
          at != null &&
          viewport != null &&
          viewport.contains(at.dx, at.dy)) {
        _fillAt(viewport.point(at.dx, at.dy), viewport.scale);
      }
      return;
    }
    if (_erasing) {
      // A click on a trait takes it whole; a rub already did its work.
      final press = _eraserPress;
      if (released &&
          !_eraserRubbed &&
          press != null &&
          _eraserPressCut.isNotEmpty) {
        _erase([press], _view?.scale ?? 1, removed: [_eraserPressCut.first]);
      }
      _erasing = false;
      _eraserLast = null;
      _eraserShield.clear();
      _eraserPress = null;
      _eraserPressCut = const [];
      _eraserRubbed = false;
      _eraserCommitted = false;
      _pointer = null;
      return;
    }
    final textAnchor = _textAnchor;
    if (textAnchor != null) {
      _textAnchor = null;
      _pointer = null;
      if (released) unawaited(_createText(textAnchor));
      return;
    }
    if (_draft.isEmpty) return;
    final points = _draft;
    final fromAnchor = _draftFromAnchor;
    final rawEnd = _draftRawEnd;
    final seen = _draftSeen;
    _steady = null;
    _string = null;
    _draftSeen = null;
    // A press that stayed where it began is a click, told on the screen.
    final clicked =
        released && _pressTravel < clickTravel(touch: _pressByTouch);
    _draft = [];
    _draftStroke = null;
    _draftRawEnd = null;
    _pointer = null;
    _draftFromAnchor = false;
    _pressPosition = null;
    try {
      // One FFI call for the completed gesture; pressure is not handled yet.
      if (_draftKind == VectorKind.stroke) {
        // The brush was heard while it travelled: nothing when it lifts.
        // A smoothed trait ends where the pointer is, not where its filter
        // was; then only the points that the eye can see are kept.
        final pressures = _drafting.pressures;
        if (seen != null &&
            (seen.x != points.last.x || seen.y != points.last.y)) {
          points.add(seen);
          pressures?.add(pressures.last);
        }
        _addTrait(points, pressures);
      } else if (_draftKind == VectorKind.stamp) {
        final box = _stampBox(points.first, points.last);
        final look = _drafting.stampLook;
        if (look.isPlain) {
          _document!.addStamp(
            box.first,
            box.second,
            stamp: _draftStamp,
            rgb: _draftColor,
          );
        } else {
          // Turned or mirrored before it is posed (Color 1.1).
          _document!.addObject(
            VectorKind.stamp,
            [box.first, box.second],
            rgb: _draftColor,
            width: 1,
            param: _draftStamp,
            look: look,
          );
        }
        _sound(StudioSound.stamp);
      } else {
        var makes = isUsableShape(_draftKind, points.first, points.last);
        if (fromAnchor) {
          // The second click of a shape made of two. Where it lands is told
          // on the screen, as the hand sees it, whatever the zoom.
          final end = rawEnd ?? points.last;
          final away =
              math.sqrt(
                math.pow(end.x - points.first.x, 2) +
                    math.pow(end.y - points.first.y, 2),
              ) *
              (_view?.scale ?? 1);
          if (away <= shapeMarkReach(touch: _pressByTouch)) {
            // On the little circle itself: the circle goes, nothing is
            // drawn. A double click leaves no speck on the sheet.
            _shapeAnchor = null;
            makes = false;
          } else if (makes) {
            _shapeAnchor = null;
          }
          // Elsewhere, where no shape can hold — level with the first click
          // for a rectangle or an oval — the circle keeps waiting.
        } else if (clicked && madeOfTwoClicks(_draftKind)) {
          // A click that did not move poses where the shape starts, and
          // draws nothing: a speck left by a trembling hand is not a shape.
          _shapeAnchor = ShapeAnchor(points.first, _draftKind);
          makes = false;
          _sound(StudioSound.click);
        }
        if (!makes) {
          if (mounted) {
            setState(() {
              _revision++;
            });
          }
          return;
        }
        if (_draftKind == VectorKind.contour) {
          // A shape of 1.1: its outline in the box of the two corners.
          _document!.addObject(
            VectorKind.contour,
            RustDocument.shapeOutline(
              _drafting.shape ?? _newShape,
              points.first,
              points.last,
            ),
            rgb: _draftColor,
            width: _draftWidth,
            fillRgb: _draftFillRgb,
          );
        } else {
          _document!.addShape(
            _draftKind,
            points.first,
            points.last,
            rgb: _draftColor,
            width: _draftWidth,
            fillRgb: _draftFillRgb,
          );
        }
        _sound(StudioSound.shape);
      }
      _refreshAfterMutation();
    } catch (error) {
      _error(error);
    }
    if (mounted) {
      setState(() {
        _revision++;
      });
    }
  }

  // A finished trait becomes what its tool makes of it: a trait painted as
  // a line, its marks (a tool of 1.1, a stylus), the same in the mirror of
  // the middle of the sheet, or, with the magnet, the shape it draws.
  void _addTrait(List<DocumentPoint> points, List<int>? pressures) {
    final document = _document!;
    final drawn = _drafting;
    if (_tool == StudioTool.magnet) {
      final shape = document.recogniseShape(points);
      if (shape != null) {
        _addMagnetShape(shape);
        return;
      }
    }
    final look = ObjectLook(tool: drawn.tool, seed: drawn.seed);
    // A trait painted as a line keeps the points the eye can see; marks
    // keep every point, so that the sheet shows what was drawn.
    final marked = drawn.tool.paintsMarks || pressures != null;
    final kept = marked ? points : _simplified(points);
    final pressed = pressures == null ? null : Uint8List.fromList(pressures);
    final mirror = drawn.mirrorWidth;
    if (mirror == null && look.isPlain && pressed == null) {
      document.addStroke(kept, rgb: _draftColor, width: _draftWidth);
      return;
    }
    document.addObjects([
      NewObject(
        VectorKind.stroke,
        kept,
        rgb: _draftColor,
        width: _draftWidth,
        look: look,
        pressures: pressed,
      ),
      if (mirror != null)
        NewObject(
          VectorKind.stroke,
          [for (final p in kept) DocumentPoint(mirror - p.x, p.y)],
          rgb: _draftColor,
          width: _draftWidth,
          look: look,
          pressures: pressed,
        ),
    ]);
  }

  // The shape the magnet found, as the shape tools make it: filled when
  // they would be.
  void _addMagnetShape(RecognisedShape shape) {
    final document = _document!;
    final fill = _filled ? _fillColor : null;
    final points = shape.points;
    switch (shape.kind) {
      case VectorKind.line:
        document.addShape(
          VectorKind.line,
          points.first,
          points.last,
          rgb: _draftColor,
          width: _draftWidth,
        );
      case VectorKind.rectangle || VectorKind.ellipse:
        document.addObject(
          shape.kind,
          points,
          rgb: _draftColor,
          width: _draftWidth,
          fillRgb: fill,
          look: ObjectLook(rotation: normalAngle(shape.rotation)),
        );
      case VectorKind.contour:
        document.addObject(
          VectorKind.contour,
          points,
          rgb: _draftColor,
          width: _draftWidth,
          fillRgb: fill,
        );
      default:
        // A broken line: a trait of straight pieces.
        document.addStroke(points, rgb: _draftColor, width: _draftWidth);
    }
    _sound(StudioSound.shape);
  }

  /// The points of a trait without those that lie within a quarter of a
  /// pixel of the line through the others, on the screen as it is: fewer
  /// points to paint, to touch, to save and to replay, and the same trait.
  List<DocumentPoint> _simplified(List<DocumentPoint> points) {
    if (points.length <= 2) return points;
    final scale = _view?.scale ?? 1;
    final kept = simplifiedIndices(
      [for (final point in points) point.x],
      [for (final point in points) point.y],
      simplifyPixels / scale,
    );
    return kept.length == points.length
        ? points
        : [for (final index in kept) points[index]];
  }

  static const _stampDragPixels = 18.0;

  /// A real drag sizes the stamp; a click places it at the chosen size,
  /// centred on the pointer and moved just enough to stay on the sheet.
  ({DocumentPoint first, DocumentPoint second}) _stampBox(
    DocumentPoint start,
    DocumentPoint end,
  ) {
    final document = _document!;
    final smallest = stampSizeFor(
      ObjectSize.small,
      width: document.width,
      height: document.height,
    );
    final dragged = math.max((end.x - start.x).abs(), (end.y - start.y).abs());
    // A drag is told from a click on the screen, where the hand moves: a
    // click that trembles by a few pixels poses the chosen size, not a speck.
    // In the units of the sheet the same tremble can be a large distance.
    final draggedPixels = dragged * (_view?.scale ?? 1);
    if (draggedPixels >= _stampDragPixels &&
        dragged >= smallest / 4 &&
        isUsableShape(_draftKind, start, end)) {
      return (first: start, second: end);
    }
    final side = stampSizeFor(
      _stampSize,
      width: document.width,
      height: document.height,
    );
    final left = (start.x - side / 2).clamp(0.0, document.width - side);
    final top = (start.y - side / 2).clamp(0.0, document.height - side);
    return (
      first: DocumentPoint(left.toDouble(), top.toDouble()),
      second: DocumentPoint(left + side, top + side),
    );
  }

  bool get _dialogAllowed =>
      mounted &&
      !_busy &&
      !_confirmationOpen &&
      _document != null &&
      _pointer == null &&
      _panPointer == null &&
      _trackpadPointer == null;

  // The end of an operation that held the studio: the keys of the sheet
  // (tools, arrows, Suppr) answer again at once, without a click on it,
  // wherever the focus was when the operation was asked for.
  void _releaseBusy() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _busyLabel = null;
    });
    _focus.requestFocus();
  }

  // Runs one modal dialog under the same guard as the other studio dialogs:
  // menu commands, gestures and exits are refused while it is open.
  Future<T?> _guardedDialog<T>(Future<T?> Function() show) async {
    _guardedDialogs++;
    setState(() => _confirmationOpen = true);
    try {
      return await show();
    } finally {
      // Should two of them ever be open, the guard falls with the last.
      _guardedDialogs--;
      if (_guardedDialogs == 0) {
        if (mounted) {
          setState(() => _confirmationOpen = false);
          _focus.requestFocus();
        } else {
          _confirmationOpen = false;
        }
      }
    }
  }

  // Where a confirmed text goes: its lines broken to the sheet's width, its
  // box as close as possible to the anchor. Null when it cannot stand on the
  // sheet at this size.
  PlacedText? _placeText(
    String text,
    double size,
    DocumentPoint anchor, {
    int font = 0,
  }) {
    final document = _document!;
    return placeText(
      text,
      size: size,
      anchor: anchor,
      pageWidth: document.width.toDouble(),
      pageHeight: document.height.toDouble(),
      font: font,
    );
  }

  // The sheet is never changed until the characters are confirmed, and the
  // dialog does not close on a text that the sheet cannot hold: the words
  // stay in it with the reason.
  Future<void> _createText(DocumentPoint anchor) async {
    _settleLatch();
    if (!_dialogAllowed) return;
    final document = _document!;
    double sizeOf(ObjectSize choice) =>
        textSizeFor(choice, width: document.width, height: document.height);
    final entry = await _guardedDialog(
      () => showTextEntryDialog(
        context,
        initialSize: _textSize,
        initialFont: _textFont,
        screenKeyboard: _options.screenKeyboard,
        problem: (text, choice, font) =>
            _placeText(text, sizeOf(choice), anchor, font: font) == null
            ? _textTooLarge
            : null,
      ),
    );
    if (entry == null || !mounted || !identical(document, _document)) return;
    _textSize = entry.size;
    _textFont = entry.font;
    try {
      final size = sizeOf(entry.size);
      final placed = _placeText(entry.text, size, anchor, font: entry.font);
      if (placed == null) {
        _showProblem(StudioProblem.notice(_textTooLarge));
        return;
      }
      document.addText(
        placed.first,
        placed.second,
        text: placed.text,
        rgb: _color,
        size: size,
        font: entry.font,
      );
      setState(_refreshAfterMutation);
      _sound(StudioSound.text);
    } catch (error) {
      _error(error, message: tr('Ce texte n’a pas pu être posé.'));
    }
  }

  static String get _textTooLarge => tr(
    'Ce texte est trop grand pour la feuille. Choisis une taille plus petite ou un texte plus court.',
  );

  bool get _canEditText =>
      _canEditSelection && _selectedObject?.kind == VectorKind.text;

  // Characters and size change together, in one step that Annuler reverses.
  Future<void> _editSelectedText() async {
    _settleLatch();
    if (!_canEditText || !_dialogAllowed) return;
    final document = _document!;
    final index = _selectedIndex!;
    final object = _selectedObject!;
    final currentSize = nearestTextSize(
      object.width,
      width: document.width,
      height: document.height,
    );
    // Keeping the same choice keeps the exact size of this text.
    double sizeOf(ObjectSize choice) => choice == currentSize
        ? object.width
        : textSizeFor(choice, width: document.width, height: document.height);
    final bounds = _boundsForObject(index, object);
    final anchor = DocumentPoint(bounds.left, bounds.top);
    final entry = await _guardedDialog(
      () => showTextEntryDialog(
        context,
        initialText: object.text ?? '',
        initialSize: currentSize,
        initialFont: object.font,
        editing: true,
        screenKeyboard: _options.screenKeyboard,
        problem: (text, choice, font) =>
            _placeText(text, sizeOf(choice), anchor, font: font) == null
            ? _textTooLarge
            : null,
      ),
    );
    if (entry == null ||
        !mounted ||
        !identical(document, _document) ||
        _selectedIndex != index ||
        !identical(_selectedObject, object)) {
      return;
    }
    try {
      final size = sizeOf(entry.size);
      final placed = _placeText(entry.text, size, anchor, font: entry.font);
      if (placed == null) {
        _showProblem(StudioProblem.notice(_textTooLarge));
        return;
      }
      final changed = document.setText(
        index,
        placed.first,
        placed.second,
        text: placed.text,
        rgb: object.rgb,
        size: size,
        font: entry.font,
      );
      setState(() {
        if (changed) _refreshAfterMutation();
        _reselect(index);
      });
    } catch (error) {
      _error(error, message: tr('Ce texte n’a pas pu être changé.'));
    }
  }

  Future<void> _chooseStamp() async {
    _settleLatch();
    if (!_dialogAllowed) return;
    try {
      final catalog = StampCatalog.instance;
      final chosen = await _guardedDialog(
        () => showStampDialog(
          context,
          catalog: catalog,
          selected: _stampId,
          rgb: _color,
        ),
      );
      if (chosen != null && mounted) setState(() => _stampId = chosen);
    } catch (error) {
      _error(error, message: tr('Les tampons ne sont pas disponibles.'));
    }
  }

  /// New objects always land on a layer that can be seen: when the layer
  /// that receives them is hidden, the nearest visible one takes over. A
  /// locked layer, which holds a colouring page, never does: nothing is
  /// drawn on it. Choosing where to draw is a view state, never an edit, so
  /// this is safe after an undo or when a project opens. False when every
  /// layer to draw on is hidden, which only a project written elsewhere can
  /// bring.
  static bool _followVisibleLayer(RustDocument document) {
    final layers = document.layers;
    final position = layers.indexWhere(
      (layer) => layer.id == document.activeLayer,
    );
    if (position < 0) return false;
    // The active layer is never a locked one: the core sees to it.
    if (layers[position].visible) return true;
    for (var distance = 1; distance < layers.length; distance++) {
      for (final other in [position + distance, position - distance]) {
        if (other >= 0 &&
            other < layers.length &&
            layers[other].visible &&
            !layers[other].locked) {
          document.setActiveLayer(layers[other].id);
          return true;
        }
      }
    }
    return false;
  }

  static String get _allLayersHidden =>
      tr('Tous les calques sont cachés. Ouvre les calques pour en montrer un.');
  // The same in an interface that does not show the layers.
  static String get _allLayersHiddenElsewhere => tr(
    'Tous les calques de ce dessin sont cachés. Un adulte peut en montrer un dans l’interface complète (Options).',
  );

  /// Reports every native command made since [before] undo steps, one by one:
  /// the save state follows the history a single step at a time.
  void _refreshAfterEdits(int before) {
    final document = _document!;
    for (var step = before + 1; step < document.undoCount; step++) {
      _saveState!.editSucceeded(undoCount: step, redoCount: 0);
    }
    if (document.undoCount > before) _refreshAfterMutation();
  }

  void _layerEdit(void Function(RustDocument document) edit) {
    final document = _document;
    if (document == null || _busy) return;
    final before = document.undoCount;
    try {
      edit(document);
    } catch (error) {
      _error(
        error,
        message: tr('Ce changement de calque n’a pas pu être fait.'),
      );
    }
    _followVisibleLayer(document);
    setState(() {
      // Choosing where to draw is not an edit: nothing to save or to undo.
      _refreshAfterEdits(before);
      _revision++;
    });
  }

  Future<void> _openLayers() async {
    _settleLatch();
    if (!_dialogAllowed || !_options.layers) return;
    _finishStroke();
    setState(() => _setSelection(null));
    await _guardedDialog<void>(
      () => showDialog<void>(
        context: context,
        builder: (_) => FitDialog(
          child: LayersDialog(
            actions: LayerPanelActions(
              layers: () => _document!.layers,
              activeLayer: () => _document!.activeLayer,
              // The page of a colouring page is locked: it can be hidden and
              // shown, never chosen, erased or moved. The panel offers none of
              // that; these guards keep a stale command from reaching the core.
              select: (id) => _layerEdit((document) {
                final position = document.layers.indexWhere(
                  (layer) => layer.id == id,
                );
                if (position < 0 || document.layers[position].locked) return;
                if (!document.layers[position].visible) {
                  document.setLayerVisible(position, true);
                }
                document.setActiveLayer(id);
              }),
              add: () => _layerEdit((document) => document.addLayer()),
              remove: (position) => _layerEdit((document) {
                final layers = document.layers;
                if (layers[position].locked) return;
                // The sheet never ends up with hidden layers only: before the
                // last visible layer to draw on goes, its nearest neighbour
                // that is one is shown. Two steps for Annuler, and each of them
                // leaves a sheet to see. The page is no layer to draw on.
                final others = [
                  for (var other = 0; other < layers.length; other++)
                    if (other != position && !layers[other].locked) other,
                ];
                if (others.isNotEmpty &&
                    layers[position].visible &&
                    !others.any((other) => layers[other].visible)) {
                  others.sort(
                    (a, b) =>
                        (a - position).abs().compareTo((b - position).abs()),
                  );
                  document.setLayerVisible(others.first, true);
                }
                document.removeLayer(position);
              }),
              // No layer passes the page: the core refuses such a move.
              move: (from, to) => _layerEdit((document) {
                if (!canMoveLayer(document.layers, from, to)) return;
                document.reorderLayer(from, to);
              }),
              setVisible: (position, visible) => _layerEdit(
                (document) => document.setLayerVisible(position, visible),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The position of the layer to which « Ordre » sends the chosen object:
  /// the one just above (+1) or below (-1) its own. Null when there is none,
  /// or when it is a locked layer of a colouring page: nothing joins the
  /// page, and nothing passes it, so that the drawing of the child stays
  /// above the zones of the page and under its lines.
  int? _selectionLayerTarget(int direction) {
    final layers = _document!.layers;
    final position = layers.indexWhere(
      (layer) => layer.id == _selectedObject!.layer,
    );
    if (position < 0) return null;
    final target = position + direction;
    if (target < 0 || target >= layers.length || layers[target].locked) {
      return null;
    }
    return target;
  }

  /// Sends the chosen object to the layer above (+1) or below (-1) its own.
  void _moveSelectionLayer(int direction) {
    if (!_canEditSelection || !_options.layers) return;
    final document = _document!;
    final layers = document.layers;
    final target = _selectionLayerTarget(direction);
    if (target == null) return;
    final before = document.undoCount;
    var moved = false;
    try {
      // An object never disappears into a hidden layer.
      if (!layers[target].visible) document.setLayerVisible(target, true);
      moved = document.setObjectLayer(_selectedIndex!, layers[target].id);
    } catch (error) {
      _error(error);
    }
    setState(() {
      _refreshAfterEdits(before);
      // The object is now the last one, in front of its new layer.
      if (moved) _reselect(document.count - 1);
    });
    _focus.requestFocus();
  }

  bool _canMoveSelectionLayer(int direction) =>
      _canEditSelection &&
      _options.layers &&
      _selectionLayerTarget(direction) != null;

  void _cancelDraft() {
    _latch = null;
    _endViewGesture();
    _draft = [];
    _draftStroke = null;
    _draftRawEnd = null;
    _steady = null;
    _string = null;
    _draftSeen = null;
    _pointer = null;
    _shapeAnchor = null;
    _draftFromAnchor = false;
    _pressPosition = null;
    _erasing = false;
    _eraserLast = null;
    _eraserShield.clear();
    _textAnchor = null;
    _potHeld = false;
    _potAt = null;
    _selectionStart = null;
    _selectionDragBounds = null;
    _selectionOffset.value = Offset.zero;
    if (mounted) {
      setState(() {
        _revision++;
      });
    }
  }

  // Annuler has something to take back: a step of the drawing, or the first
  // click of a shape made of two.
  bool get _canUndo => !_busy && (_document!.canUndo || _shapeAnchor != null);

  void _history(bool redo) {
    recordNativeDiagnostics(redo ? 'redo-request' : 'undo-request');
    if (_busy || _confirmationOpen || _document == null) return;
    // What a click began is kept first: Annuler then takes that back, and
    // not the step before it.
    _settleLatch();
    final waiting = _shapeAnchor;
    if (!redo && waiting != null) {
      // The click that waits for the end of a shape is the last thing done,
      // though not yet a step of the drawing: Annuler takes it back, alone,
      // with the second click if it is being made.
      _cancelDraft();
      return;
    }
    _cancelDraft();
    // Rétablir brings a step of the drawing back: a first click that waits
    // has nothing to do with it, and goes on waiting.
    if (waiting != null) {
      _shapeAnchor = waiting
        ..end = null
        ..rawEnd = null;
    }
    _setSelection(null);
    try {
      if (redo ? _document!.redo() : _document!.undo()) {
        // A layer hidden again by this step no longer receives the drawing.
        _followVisibleLayer(_document!);
        setState(
          () => _refreshAfterMutation(
            change: redo ? _HistoryChange.redo : _HistoryChange.undo,
          ),
        );
        recordNativeDiagnostics(redo ? 'redo-applied' : 'undo-applied');
        _sound(redo ? StudioSound.redo : StudioSound.undo);
      }
    } catch (error) {
      _error(error);
    }
  }

  static const _digitKeys = [
    PhysicalKeyboardKey.digit1,
    PhysicalKeyboardKey.digit2,
    PhysicalKeyboardKey.digit3,
    PhysicalKeyboardKey.digit4,
    PhysicalKeyboardKey.digit5,
    PhysicalKeyboardKey.digit6,
    PhysicalKeyboardKey.digit7,
    PhysicalKeyboardKey.digit8,
    PhysicalKeyboardKey.digit9,
  ];
  static const _numpadKeys = [
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  /// The tool of a number key, alone: 1 is the first tool of the bar. The
  /// top row is read by position, so that a French keyboard needs no Maj.
  StudioTool? _toolForKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return null;
    }
    var number = _digitKeys.indexOf(event.physicalKey);
    if (number < 0) number = _numpadKeys.indexOf(event.logicalKey);
    // The numbers follow the bar as the options show it.
    final groups = _options.groups;
    return number >= 0 && number < groups.length
        ? _toolOfGroup(groups[number])
        : null;
  }

  // The keys that are held with others and ask for nothing by themselves.
  static final _modifierKeys = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
  };

  /// The pointer of the keyboard or the gamepad (Color 1.1): where it is on
  /// the sheet, in pixels of its frame, and whether it is pressed.
  Offset? _keyPointerAt;
  bool _keyDown = false;
  DocumentViewport? _keyViewport;
  Size? _keySheetSize;
  final _keyClock = Stopwatch()..start();
  static const _keyPointerId = 0x4b4559;

  void _pointerUp(PointerUpEvent event, DocumentViewport viewport) {
    if (_fingerUp(event)) return;
    if (_panPointer == event.pointer) {
      _pointerMove(event, viewport);
      if (!_beginPanLatch()) _endViewGesture();
    }
    if (_pointer == event.pointer) {
      _pointerMove(event, viewport);
      _finishStroke(released: true);
    }
  }

  /// The arrows move the pointer, ten pixels at a time or two with Maj;
  /// Entrée, or the button A of a gamepad, presses it, and again releases
  /// it. True when the key was the pointer's.
  bool _keyPointerKey(KeyEvent event) {
    final viewport = _keyViewport;
    final size = _keySheetSize;
    if (viewport == null || size == null) return false;
    final key = event.logicalKey;
    final press =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA;
    final direction = switch (key) {
      LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight => const Offset(1, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -1),
      LogicalKeyboardKey.arrowDown => const Offset(0, 1),
      _ => null,
    };
    if (direction == null && !press) return false;
    if (event is KeyUpEvent) return true;
    final at = _keyPointerAt ?? size.center(Offset.zero);
    final time = _keyClock.elapsed;
    // What the tool would do is shown where this pointer is (Color 1.2).
    _hintByKey = true;
    _hintByFinger = false;
    if (press) {
      if (event is KeyRepeatEvent) return true;
      _hintAt = at;
      _keyDown = !_keyDown;
      if (_keyDown) {
        _pointerDown(
          PointerDownEvent(
            pointer: _keyPointerId,
            position: at,
            kind: PointerDeviceKind.mouse,
            buttons: kPrimaryButton,
            timeStamp: time,
          ),
          viewport,
        );
      } else {
        _pointerUp(
          PointerUpEvent(
            pointer: _keyPointerId,
            position: at,
            kind: PointerDeviceKind.mouse,
            timeStamp: time,
          ),
          viewport,
        );
      }
      setState(() => _keyPointerAt = at);
      return true;
    }
    final distance = HardwareKeyboard.instance.isShiftPressed ? 2.0 : 10.0;
    final next = Offset(
      (at.dx + direction!.dx * distance).clamp(0, size.width),
      (at.dy + direction.dy * distance).clamp(0, size.height),
    );
    _hintAt = next;
    if (_keyDown) {
      _pointerMove(
        PointerMoveEvent(
          pointer: _keyPointerId,
          position: next,
          delta: next - at,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
          timeStamp: time,
        ),
        viewport,
      );
    } else {
      _pointerHover(
        PointerHoverEvent(
          position: next,
          delta: next - at,
          kind: PointerDeviceKind.mouse,
          timeStamp: time,
        ),
        viewport,
      );
    }
    setState(() => _keyPointerAt = next);
    return true;
  }

  KeyEventResult _shapeModifiers(FocusNode node, KeyEvent event) {
    // The pointer of the keyboard takes its keys before anything else does:
    // the arrows are then its own, not those that nudge the chosen element.
    if (_options.keyboardPointer &&
        !_busy &&
        !_confirmationOpen &&
        _focus.hasFocus &&
        _keyPointerKey(event)) {
      return KeyEventResult.handled;
    }
    // « Dessiner sans tenir le bouton » : a key pressed while a gesture begun
    // with a click goes on first keeps what that gesture made; the command
    // of the key comes after. Échap gives the gesture up instead.
    if (event is KeyDownEvent &&
        _latch != null &&
        event.logicalKey != LogicalKeyboardKey.escape &&
        !_modifierKeys.contains(event.logicalKey)) {
      _endLatch();
    }
    if (event.logicalKey == LogicalKeyboardKey.space &&
        event is KeyUpEvent &&
        _spaceHeld) {
      setState(() => _spaceHeld = false);
    }
    if (event.logicalKey == LogicalKeyboardKey.space &&
        _focus.hasPrimaryFocus &&
        _options.viewControls) {
      if (!_busy && !_confirmationOpen) {
        final held = event is! KeyUpEvent;
        if (held != _spaceHeld) setState(() => _spaceHeld = held);
        return KeyEventResult.handled;
      }
    }
    // A number chooses a tool wherever the focus is in the studio: after the
    // width slider or a button was used too. None of its controls takes
    // numbers for itself; the fields that do live in dialogs, out of here.
    if (event is KeyDownEvent &&
        _focus.hasFocus &&
        !_busy &&
        !_confirmationOpen &&
        _pointer == null &&
        _panPointer == null) {
      final tool = _toolForKey(event);
      if (tool != null) {
        _selectTool(tool);
        return KeyEventResult.handled;
      }
    }
    if ((event.logicalKey == LogicalKeyboardKey.shiftLeft ||
            event.logicalKey == LogicalKeyboardKey.shiftRight) &&
        _draftKind != VectorKind.stroke &&
        _draft.length == 2 &&
        _draftRawEnd != null) {
      _draft[1] = _shapeEndFrom(_draft.first, _draftRawEnd!, _draftKind);
      _revision++;
      _canvasRepaint.value++;
    }
    // The same for the shape that follows the pointer between two clicks.
    final anchor = _shapeAnchor;
    if ((event.logicalKey == LogicalKeyboardKey.shiftLeft ||
            event.logicalKey == LogicalKeyboardKey.shiftRight) &&
        anchor != null &&
        anchor.rawEnd != null &&
        _pointer == null) {
      anchor.end = _shapeEndFrom(anchor.start, anchor.rawEnd!, anchor.kind);
      _canvasRepaint.value++;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _initializeRecovery() async {
    if (_document == null) return;
    try {
      _gallery = widget.gallery;
      if (widget.recoveryStorage == null) {
        final support = (await applicationSupportFolder()).path;
        _storage = ProjectStorage(
          recoveryDirectory: Directory(
            recoveryDirectoryPath(support, windows: Platform.isWindows),
          ),
        );
        _gallery ??= GalleryStorage(
          directory: Directory(
            galleryDirectoryPath(support, windows: Platform.isWindows),
          ),
        );
      } else {
        _storage = widget.recoveryStorage;
      }
      final prepared = await _storage!.readPreparedRecovery();
      if (prepared != null) {
        final recovered = prepared.document;
        ui.Image? recoveredBackground;
        try {
          if (!mounted) return;
          recoveredBackground = await _decodePreparedBackground(prepared);
          if (!mounted) return;
          // What the child made: a page that nobody coloured counts none.
          final restore = await showRecoveryDialog(
            context,
            count: recovered.madeCount,
          );
          if (!mounted) return;
          if (restore) {
            _replaceDocument(
              recovered,
              null,
              background: recoveredBackground,
              dirty: true,
              status: () => tr(
                'Dessin récupéré · enregistre-le pour choisir son emplacement.',
              ),
            );
            prepared.takeDocument();
            recoveredBackground = null;
          } else {
            await _clearRecovery();
            if (mounted) {
              setState(() {
                _status = () =>
                    tr('Nouvelle feuille · récupération locale prête.');
              });
            }
          }
        } finally {
          recoveredBackground?.dispose();
          prepared.dispose();
        }
      } else if (mounted) {
        setState(() {
          _status = () => tr('Nouvelle feuille · récupération locale prête.');
        });
      }
    } catch (error) {
      // Preserve an unreadable recovery file: do not overwrite it with a blank drawing.
      _storage = null;
      if (mounted) {
        setState(() {
          _status = () => tr(
            'Récupération indisponible · enregistre régulièrement ton dessin.',
          );
        });
        _error(
          error,
          message: error is NewerProjectException
              ? tr(
                  'La copie de récupération vient d’une version plus récente de Color : elle est conservée telle quelle. Enregistre régulièrement ton dessin.',
                )
              : tr(
                  'La récupération n’est pas disponible pour le moment. Enregistre régulièrement ton dessin.',
                ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  // Longer for a larger drawing, which each copy writes whole.
  Duration _recoveryDelay() {
    try {
      return recoveryDelayFor(_document?.projectByteLength ?? 0);
    } catch (_) {
      return recoveryDelayFor(0);
    }
  }

  void _scheduleRecovery() {
    if (_storage == null) {
      if (_dirty) {
        _status = () => tr(
          'Modifications non enregistrées · récupération locale indisponible.',
        );
      }
      return;
    }
    _recoveryScheduler.request();
  }

  Future<void> _writeRecovery() async {
    if (_document == null || _storage == null) return;
    final document = _document!;
    final storage = _storage!;
    final generation = _recoveryGeneration;
    final revision = _documentRevision;
    bool belongsToCurrentDocument() =>
        mounted &&
        identical(document, _document) &&
        identical(storage, _storage) &&
        generation == _recoveryGeneration;
    try {
      if (!_dirty) {
        // This clear is owned by the same single recovery invocation as writes.
        // An edit arriving while it awaits is coalesced behind it, never erased.
        await storage.clearRecovery();
        return;
      }
      final committed = await storage.writeRecoveryDocument(
        document,
        shouldCommit: () => belongsToCurrentDocument() && _dirty,
      );
      if (!committed || !belongsToCurrentDocument() || !_dirty) return;
      if (revision == _documentRevision) {
        _status = () =>
            tr('Copie de récupération à jour · projet à enregistrer.');
      } else {
        // Keep the completed older snapshot, then coalesce the latest edits.
        // The scheduler never keeps an encoded snapshot for every pointer event.
        _scheduleRecovery();
      }
    } catch (error) {
      if (belongsToCurrentDocument()) {
        setState(() {
          _status = _dirty
              ? () =>
                    tr('Récupération non mise à jour · enregistre ton dessin.')
              : () => tr('Ancienne copie de récupération encore présente.');
        });
        if (!_recoveryWarningShown) {
          _recoveryWarningShown = true;
          _error(
            error,
            message: _dirty
                ? tr(
                    'Le dessin reste ouvert, mais sa copie de récupération n’a pas pu être écrite.',
                  )
                : tr(
                    'L’ancienne copie de récupération n’a pas pu être retirée. Le dessin actuel reste ouvert.',
                  ),
          );
        }
      }
    }
  }

  // A tablet or a telephone may end Color without asking once it is out of
  // sight: the trait being drawn is finished and the recovery copy written,
  // so that the drawing is there when Color comes back.
  void _keepWhenHidden() {
    if (!touchFirst || _document == null || !mounted) return;
    _finishStroke();
    // Hidden, then paused, one after the other: one copy serves both.
    if (_dirty && _hiddenRevision != _documentRevision) {
      _hiddenRevision = _documentRevision;
      _scheduleRecovery();
      // Now, not after the pause: the system may end Color before it.
      _recoveryScheduler.flushNow();
    }
  }

  Future<bool> _clearRecovery({bool Function()? stillCurrent}) async {
    final storage = _storage;
    _recoveryGeneration++;
    await _recoveryScheduler.cancelAndWait();
    if (stillCurrent != null && !stillCurrent()) return false;
    await storage?.clearRecovery();
    return stillCurrent?.call() ?? true;
  }

  Future<bool> _confirmProceed() async {
    if (!_dirty) return true;
    if (_confirmationOpen || !mounted) return false;
    _confirmationOpen = true;
    try {
      final choice = await showKeepChangesDialog(
        context,
        exports: _options.exports,
      );
      if (!mounted) return false;
      if (choice == KeepChanges.save) return await _saveCurrent();
      return choice == KeepChanges.discard;
    } finally {
      _confirmationOpen = false;
    }
  }

  // The custom macOS delegate treats its accepted reply as final: it sets
  // terminationApproved and then terminates without consulting Dart again.
  // A framework lifecycle callback is only one observer's vote; another
  // observer may still cancel, so that path must release the busy state.
  Future<AppExitResponse> _requestExit({
    bool finalNativeDecision = false,
  }) async {
    recordNativeDiagnostics('exit-request');
    if (_document == null || _startupError != null) return AppExitResponse.exit;
    if (_busy || _confirmationOpen) return AppExitResponse.cancel;
    _finishStroke();
    setState(() {
      _busy = true;
    });
    var finalNativeExitApproved = false;
    try {
      if (!await _confirmProceed()) return AppExitResponse.cancel;
      await _clearRecovery();
      // The card of a save made in the question, or just before leaving,
      // is given the moment it needs: the program ends with this answer.
      await _cardsSettled(const Duration(seconds: 3));
      finalNativeExitApproved = finalNativeDecision;
      return AppExitResponse.exit;
    } catch (error) {
      _error(error, message: tr('Color n’a pas pu terminer la fermeture.'));
      return AppExitResponse.cancel;
    } finally {
      if (mounted) {
        setState(() {
          // Never admit another edit between final native approval and teardown.
          // Cancellation, failures and overridable framework votes stay usable.
          _busy = finalNativeExitApproved;
        });
      }
    }
  }

  Future<void> _newDrawing() async {
    _settleLatch();
    if (_busy ||
        _confirmationOpen ||
        _document == null ||
        _pointer != null ||
        _panPointer != null ||
        _trackpadPointer != null) {
      return;
    }
    setState(() {
      _busy = true;
    });
    RustDocument? replacement;
    try {
      final choice = await showDialog<NewSheetChoice>(
        context: context,
        builder: (_) =>
            FitDialog(child: NewSheetDialog(pages: ColoringPages.all)),
      );
      if (choice == null || !mounted) return;
      _finishStroke();
      if (!await _confirmProceed() || !mounted) return;
      // A page makes a document of its own, on its locked layers: the sheet
      // starts clean, with no step for « Annuler », which never takes the
      // page away.
      replacement = choice is ColoringPage
          ? RustDocument.fromPage(choice.id)
          : RustDocument(width: choice.width, height: choice.height);
      await _clearRecovery();
      if (!mounted) return;
      _replaceDocument(replacement, null);
      replacement = null;
      _sound(StudioSound.sheet);
      _react();
    } catch (error) {
      _error(
        error,
        message: tr('La nouvelle feuille n’a pas pu être préparée.'),
      );
    } finally {
      replacement?.dispose();
      _releaseBusy();
    }
  }

  /// The background is adopted with the document, after both are validated.
  /// Ownership remains with the caller if this method throws before adoption.
  void _replaceDocument(
    RustDocument replacement,
    String? path, {
    ui.Image? background,
    bool dirty = false,
    String Function()? status,
  }) {
    final strokes = List<RenderedElement>.unmodifiable(
      replacement.strokes.map(RenderedElement.new),
    );
    _followVisibleLayer(replacement);
    final tracking = DocumentSaveState(
      undoCount: replacement.undoCount,
      redoCount: replacement.redoCount,
      initiallyClean: !dirty,
      path: path,
    );
    final old = _document;
    final oldTracking = _saveState;
    final oldBackground = _backgroundImage;
    setState(() {
      _document = replacement;
      _saveSuggestion = null;
      _backgroundImage = background;
      _view = null;
      _panning = false;
      _spaceHeld = false;
      _shapeAnchor = null;
      _setSelection(null);
      _strokes = strokes;
      _saveState = tracking;
      _documentRevision++;
      _forgetInk();
      _revision++;
      _status =
          status ??
          (path == null
              ? () => tr('Nouvelle feuille · récupération locale prête.')
              : () => trf('Projet ouvert : {0}', [path]));
    });
    oldTracking?.retire();
    old?.dispose();
    oldBackground?.dispose();
  }

  Future<ui.Image?> _decodePreparedBackground(PreparedProject prepared) async {
    final document = prepared.document;
    final bytes = prepared.takeBackground();
    if (bytes == null) return null;
    final asset = await decodeTransferredCanonicalBackground(bytes);
    try {
      if (asset.width != document.width || asset.height != document.height) {
        throw const FormatException('Le fond ne correspond pas à la feuille.');
      }
      return asset.image.clone();
    } finally {
      asset.dispose();
    }
  }

  Future<void> _importImage() async {
    if (_busy || _confirmationOpen || _document == null) return;
    if (!_options.opensFiles) return;
    _finishStroke();
    setState(() => _busy = true);
    RustDocument? candidate;
    ImportedBackground? asset;
    ui.Image? candidateBackground;
    try {
      final path = await widget.files.chooseImage();
      if (path == null || !mounted) return;
      setState(() => _busyLabel = tr('Préparation de ton image…'));
      // Present the busy state before starting bounded parsing and decoding.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final bytes = await widget.files.readImage(path);
      if (!mounted) return;
      asset = await normaliseRaster(bytes);
      if (!mounted) return;
      candidate = RustDocument.fromBackgroundPng(asset.pngBytes);
      candidateBackground = asset.image.clone();
      asset.dispose();
      asset = null;
      setState(() => _busyLabel = null);
      if (!await _confirmProceed() || !mounted) return;
      await _clearRecovery();
      if (!mounted) return;
      _replaceDocument(
        candidate,
        null,
        background: candidateBackground,
        dirty: true,
        status: () => tr(
          'Ton image est le fond de la feuille. Dessine par-dessus, puis enregistre ton projet Color.',
        ),
      );
      candidate = null;
      candidateBackground = null;
      _scheduleRecovery();
    } catch (error) {
      _error(
        error,
        message: tr(
          'Cette image n’a pas pu être ouverte. Ton dessin actuel est conservé.',
        ),
      );
    } finally {
      asset?.dispose();
      candidateBackground?.dispose();
      candidate?.dispose();
      _releaseBusy();
    }
  }

  Future<void> _openProject() async {
    if (_busy || _confirmationOpen || _document == null) return;
    if (!_options.opensFiles) return;
    _finishStroke();
    setState(() {
      _busy = true;
    });
    PreparedProject? candidate;
    ui.Image? candidateBackground;
    String? opened;
    var rescued = false;
    try {
      final path = await widget.files.chooseOpen();
      recordNativeDiagnostics('open-panel-returned');
      if (path == null || !mounted) return;
      opened = path;
      setState(() => _busyLabel = tr('Ouverture de ton dessin…'));
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      // Parse a separate document before asking to abandon the current drawing.
      candidate = await widget.files.readPrepared(path);
      if (!mounted) return;
      candidateBackground = await _decodePreparedBackground(candidate);
      if (!mounted) return;
      setState(() => _busyLabel = null);
      final beforeConfirmation = _successfulSaves;
      if (!mounted || !await _confirmProceed() || !mounted) return;
      // Saving in the confirmation may have replaced this very file.
      // Otherwise keep the already validated snapshot, avoiding a second large
      // PNG decode in the common case of opening a clean document.
      if (_successfulSaves != beforeConfirmation) {
        candidate.dispose();
        candidate = null;
        candidateBackground?.dispose();
        candidateBackground = null;
        setState(() => _busyLabel = tr('Ouverture de ton dessin…'));
        candidate = await widget.files.readPrepared(path);
        if (!mounted) return;
        candidateBackground = await _decodePreparedBackground(candidate);
      }
      if (!mounted) return;
      // A file of Color's own folders is not the file of a drawing: Color
      // clears those folders by itself. Its drawing is taken without it,
      // as one that still has to be saved somewhere.
      final own = _inOwnFolder(path);
      await _clearRecovery();
      if (!mounted) return;
      _replaceDocument(
        candidate.document,
        own ? null : path,
        background: candidateBackground,
        dirty: own,
        status: own ? () => _ownFolderStatus : null,
      );
      candidate.takeDocument();
      candidate = null;
      candidateBackground = null;
      if (own) {
        _scheduleRecovery();
        _showProblem(StudioProblem.notice(_ownFolderStatus));
      }
      recordNativeDiagnostics('open-applied');
    } catch (error) {
      if (error is FormatException && opened != null && mounted) {
        // A drawing of 1.1 whose end does not check: what is intact may be
        // saved (Color 1.1).
        rescued = await _offerRescue(opened);
        if (rescued) return;
      }
      _error(
        error,
        message: error is NewerProjectException
            ? tr(
                'Ce dessin vient d’une version plus récente de Color. Installe la dernière version pour l’ouvrir. Le dessin actuel est conservé.',
              )
            : tr(
                'Ce projet n’a pas pu être ouvert. Le dessin actuel est conservé.',
              ),
      );
    } finally {
      candidateBackground?.dispose();
      candidate?.dispose();
      if (!rescued) _releaseBusy();
    }
  }

  /// What can be saved of the damaged drawing at [path], offered to the
  /// child: true when it was opened, as a drawing still to be saved under a
  /// name of its own. Releases the busy state when it opens it.
  Future<bool> _offerRescue(String path) async {
    DamagedProjectRescue? rescue;
    ui.Image? background;
    try {
      final bytes = await widget.files.read(path);
      if (!mounted) return false;
      rescue = RustDocument.fromDamagedProject(bytes);
      if (rescue == null) return false;
      final document = rescue.document;
      final png = rescue.lostImage ? null : document.copyBackgroundPng();
      if (png != null) {
        final asset = await decodeCanonicalBackground(png);
        try {
          if (asset.width == document.width &&
              asset.height == document.height) {
            background = asset.image.clone();
          }
        } finally {
          asset.dispose();
        }
      }
      if (!mounted) return false;
      final lost = [
        if (rescue.lostLayerCount == 1) tr('un calque'),
        if (rescue.lostLayerCount > 1)
          trf('{0} calques', [rescue.lostLayerCount]),
        if (rescue.lostImage || (png != null && background == null))
          tr('l’image du fond'),
      ];
      setState(() => _busyLabel = null);
      final open = await showRescueDialog(
        context,
        lost: lost.isEmpty ? null : lost.join(tr(' et ')),
      );
      if (!open || !mounted || !await _confirmProceed() || !mounted) {
        return false;
      }
      await _clearRecovery();
      if (!mounted) return false;
      _replaceDocument(
        document,
        null,
        background: background,
        dirty: true,
        status: () => _rescuedStatus,
      );
      rescue = null;
      background = null;
      _scheduleRecovery();
      _showProblem(StudioProblem.notice(_rescuedStatus));
      _releaseBusy();
      return true;
    } catch (_) {
      return false;
    } finally {
      background?.dispose();
      rescue?.document.dispose();
    }
  }

  static String get _rescuedStatus => tr(
    'Ce qui restait du dessin abîmé est ouvert. Enregistre-le sous un nouveau nom.',
  );

  // Called only while the surrounding operation owns the busy state.
  Future<bool> _saveCurrent({bool saveAs = false}) async {
    final document = _document;
    if (document == null || !mounted) return false;
    final initialRevision = _documentRevision;
    final tracking = _saveState!;
    SaveTicket? ticket;
    _GalleryCard? card;
    final storage = _storage;
    final generation = _recoveryGeneration;
    final previousLabel = _busyLabel;
    bool unchanged() =>
        mounted &&
        identical(document, _document) &&
        identical(tracking, _saveState) &&
        identical(storage, _storage) &&
        initialRevision == _documentRevision;
    void preserveLatest() {
      if (!mounted || !_dirty) return;
      setState(() {
        _status = () => tr('Des modifications restent à enregistrer.');
        _scheduleRecovery();
      });
    }

    try {
      // A cancelled native picker must not allocate an export snapshot.
      final path = !saveAs && _currentPath != null
          ? _currentPath
          : await widget.files.chooseSave(
              currentPath: _currentPath ?? _saveSuggestion,
            );
      recordNativeDiagnostics('save-destination-returned');
      if (path == null || !mounted) return false;
      if (_inOwnFolder(path)) {
        _showProblem(StudioProblem.notice(_reservedFolder));
        return false;
      }
      if (!unchanged() || generation != _recoveryGeneration) {
        preserveLatest();
        return false;
      }
      if (projectExportUsesWorker(document)) {
        setState(() => _busyLabel = tr('Préparation de ton projet…'));
        await WidgetsBinding.instance.endOfFrame;
        if (!unchanged() || generation != _recoveryGeneration) {
          preserveLatest();
          return false;
        }
      }
      // The helper captures before its first await. The revision checked above
      // therefore identifies exactly the bytes handed to the file writer.
      ticket = tracking.beginSave();
      // The picture of the album's card shows exactly these bytes: both are
      // captured here, before the first await.
      card = _gallery == null
          ? null
          : _GalleryCard(
              // What the sheet is painted with, in painting order: nothing
              // is prepared a second time for the picture.
              [for (final index in document.paintOrder) _strokes[index]],
              width: document.width,
              height: document.height,
              // What the child made, never the untouched page.
              count: document.madeCount,
              paperRgb: document.paperRgb,
              background: _backgroundImage?.clone(),
            );
      final bytes = await prepareProjectBytes(document);
      if (!unchanged() || generation != _recoveryGeneration) {
        preserveLatest();
        return false;
      }
      await widget.files.write(path, bytes);
      _successfulSaves++;
      recordNativeDiagnostics('project-written');
      final completion = tracking.completeSave(ticket, path: path);
      if (mounted &&
          identical(tracking, _saveState) &&
          completion != SaveCompletion.ignoredStale) {
        setState(() {
          final shown = widget.files.shownPath(path);
          _status = _dirty
              ? () => tr('Des modifications restent à enregistrer.')
              : () => trf('Projet enregistré : {0}', [shown]);
          _scheduleRecovery();
        });
      }
      // The drawing is saved, and says so. Its card is made afterwards and
      // the save never waits for it: an album that fails costs a card, not
      // a message to the child.
      final saved = card;
      card = null;
      if (saved != null) _startCard(path, bytes, saved);
      if (!unchanged() || generation != _recoveryGeneration) {
        preserveLatest();
        return false;
      }
      final clearingGeneration = _recoveryGeneration + 1;
      try {
        final cleared = await _clearRecovery(
          stillCurrent: () =>
              unchanged() && clearingGeneration == _recoveryGeneration,
        );
        if (!cleared) {
          preserveLatest();
          return false;
        }
      } catch (error) {
        _error(
          error,
          message: tr(
            'Le projet est enregistré. L’ancienne copie de récupération n’a pas pu être retirée.',
          ),
        );
      }
      if (!unchanged() || clearingGeneration != _recoveryGeneration) {
        preserveLatest();
        return false;
      }
      setState(() {
        final shown = widget.files.shownPath(path);
        _status = () => trf('Projet enregistré : {0}', [shown]);
        _savedJustNow = true;
      });
      // A tick on the button for a moment: not every interface has the
      // line of the status, and the sounds may be off.
      _savedTimer?.cancel();
      _savedTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _savedJustNow = false);
      });
      _sound(StudioSound.saved);
      _react();
      return true;
    } catch (error) {
      _error(
        error,
        message: tr('Enregistrement non terminé. Le dessin reste ouvert.'),
      );
      return false;
    } finally {
      card?.dispose();
      if (ticket != null) tracking.cancelSave(ticket);
      if (mounted && _busyLabel != previousLabel) {
        setState(() => _busyLabel = previousLabel);
      }
    }
  }

  static String get _reservedFolder => tr(
    'Ce dossier est celui où Color range ses propres copies. Choisis un autre endroit pour ton dessin.',
  );

  // Color's own folders hold its recovery copy and its album, which it
  // clears by itself: nothing there is the file of a drawing.
  bool _inOwnFolder(String path) =>
      (_storage?.owns(path) ?? false) || (_gallery?.owns(path) ?? false);

  void _startCard(String path, Uint8List project, _GalleryCard card) {
    late final Future<void> work;
    work = _rememberInGallery(
      path,
      project,
      card,
    ).whenComplete(() => _cardsInProgress.remove(work));
    _cardsInProgress.add(work);
  }

  /// Completes when the cards of the saves already made are written, or
  /// after [limit]: a card that is late is missing, nothing more.
  Future<void> _cardsSettled(Duration limit) async {
    if (_cardsInProgress.isEmpty) return;
    try {
      await Future.wait(_cardsInProgress.toList()).timeout(limit);
    } catch (_) {
      // Never an obstacle to what was waiting.
    }
  }

  Future<void> _rememberInGallery(
    String path,
    Uint8List project,
    _GalleryCard card,
  ) async {
    try {
      final gallery = _gallery;
      if (gallery == null) return;
      // After the frame that says the drawing is saved: the picture is the
      // album's business, not the save's.
      await Future<void>.delayed(Duration.zero);
      final thumbnail = await renderThumbnailOf(
        card.elements,
        width: card.width,
        height: card.height,
        paperRgb: card.paperRgb,
        background: card.background,
      );
      await gallery.remember(
        sourcePath: path,
        name: StudioFiles.fileName(path),
        project: project,
        thumbnailPng: thumbnail,
        width: card.width,
        height: card.height,
        elementCount: card.count,
      );
    } catch (_) {
      recordNativeDiagnostics('gallery-card-failed');
    } finally {
      card.dispose();
    }
  }

  Future<void> _openGallery() async {
    final gallery = _gallery;
    _settleLatch();
    if (gallery == null || !_dialogAllowed) return;
    _finishStroke();
    final entry = await _guardedDialog(
      () => showGalleryDialog(
        context,
        storage: gallery,
        // A drawing saved a moment ago has its card when the album opens.
        ready: _cardsSettled(const Duration(seconds: 3)),
        opensFiles: _options.opensFiles,
      ),
    );
    if (entry != null && mounted) await _openGalleryEntry(gallery, entry);
  }

  static String get _ownFolderStatus => tr(
    'Ce dessin vient d’un dossier que Color vide lui-même : il n’est pas encore rangé. Enregistrer te demandera où le mettre.',
  );

  // The copy of the album is the drawing as it was saved that day: say so,
  // in case a later save never reached the album.
  static String _galleryCopyStatus(GalleryEntry entry) => trf(
    'Dessin repris de la galerie, tel qu’il était {0} · Enregistrer te demandera où le ranger.',
    [savedMoment(entry.savedAt.toLocal(), now: DateTime.now())],
  );

  static String get _replacedStatus => tr(
    'Ce dessin vient d’être remplacé sur le disque par celui que tu as enregistré : il n’existe plus qu’ici. Enregistre-le sous un autre nom pour le garder.',
  );

  // Beside the file that took its place, under a name that tells them apart.
  static String _earlierVersionPath(String path) {
    final name = StudioFiles.fileName(path);
    const extension = '.edupaint';
    final stem = name.toLowerCase().endsWith(extension)
        ? name.substring(0, name.length - extension.length)
        : name;
    return trf(
      '{0}'
      '{1} (version précédente){2}',
      [path.substring(0, path.length - name.length), stem, extension],
    );
  }

  /// Reopens a card. The saved file itself when this program can still read
  /// it: Enregistrer then writes to it as usual. Otherwise the album's own
  /// copy, as a drawing without a file: nothing outside the album is touched
  /// until the user chooses a place again.
  Future<void> _openGalleryEntry(
    GalleryStorage gallery,
    GalleryEntry entry,
  ) async {
    if (_busy || _confirmationOpen || _document == null) return;
    setState(() => _busy = true);
    PreparedProject? candidate;
    ui.Image? candidateBackground;
    try {
      setState(() => _busyLabel = tr('Ouverture de ton dessin…'));
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      String? path = entry.sourcePath;
      try {
        candidate = await widget.files.readPrepared(entry.sourcePath);
      } catch (error) {
        // Moved, renamed, or simply out of reach: a sandboxed program loses
        // the files chosen in an earlier session. A newer format is not a
        // matter of reach: say so rather than open an older copy silently.
        if (error is NewerProjectException) rethrow;
        path = null;
        final copy = await gallery.readCopy(entry);
        if (!mounted) return;
        if (copy == null) {
          _showProblem(
            StudioProblem.notice(
              _options.opensFiles
                  ? tr(
                      'Ce dessin est trop grand pour être gardé dans la galerie, et son fichier n’est plus accessible d’ici. Retrouve-le avec Ouvrir.',
                    )
                  : tr(
                      'Ce dessin est trop grand pour être gardé dans la galerie, et son fichier n’est plus accessible d’ici. Un adulte peut le retrouver avec Ouvrir, dans une interface plus complète.',
                    ),
            ),
          );
          return;
        }
        candidate = await RustDocument.loadProjectBytes(copy);
      }
      if (!mounted) return;
      candidateBackground = await _decodePreparedBackground(candidate);
      if (!mounted) return;
      setState(() => _busyLabel = null);
      // Whether the drawing on the sheet is this card's own, opened from its
      // file or taken from its copy.
      final sameDrawing = (_currentPath ?? _saveSuggestion) == entry.sourcePath;
      final beforeConfirmation = _successfulSaves;
      if (!await _confirmProceed() || !mounted) return;
      // What was read before the question is the drawing as it was then. A
      // save made in the question may have written this card's very file.
      var replaced = false;
      if (_successfulSaves != beforeConfirmation &&
          _currentPath == entry.sourcePath) {
        // This card's drawing, further along, was just saved to its file:
        // it is the drawing asked for, in its newest state. It stays.
        if (sameDrawing) return;
        // Another drawing took its place on the disk, and soon in the album.
        // What was read is the only copy left: it is kept as a drawing still
        // to be saved, never shown as if it were safe.
        replaced = true;
      }
      await _clearRecovery();
      if (!mounted) return;
      _replaceDocument(
        candidate.document,
        replaced ? null : path,
        background: candidateBackground,
        dirty: replaced,
        status: replaced
            ? () => _replacedStatus
            : path == null
            ? () => _galleryCopyStatus(entry)
            : null,
      );
      if (replaced) {
        _saveSuggestion = _earlierVersionPath(entry.sourcePath);
        _scheduleRecovery();
        // Said where it stays in view: the line under the sheet soon speaks
        // of the recovery copy instead.
        _showProblem(StudioProblem.notice(_replacedStatus));
      } else if (path == null) {
        _saveSuggestion = entry.sourcePath;
      }
      candidate.takeDocument();
      candidate = null;
      candidateBackground = null;
    } catch (error) {
      _error(
        error,
        message: error is NewerProjectException
            ? tr(
                'Ce dessin vient d’une version plus récente de Color. Installe la dernière version pour l’ouvrir. Le dessin actuel est conservé.',
              )
            : tr(
                'Ce dessin n’a pas pu être repris. Le dessin actuel est conservé.',
              ),
      );
    } finally {
      candidateBackground?.dispose();
      candidate?.dispose();
      _releaseBusy();
    }
  }

  Future<void> _saveProject({bool saveAs = false}) async {
    if (_busy || _confirmationOpen || _document == null) return;
    _finishStroke();
    setState(() {
      _busy = true;
    });
    try {
      await _saveCurrent(saveAs: saveAs);
    } finally {
      _releaseBusy();
    }
  }

  Future<void> _chooseExport() async {
    if (_busy || _confirmationOpen || _document == null) return;
    if (!_options.exports) return;
    _finishStroke();
    final choice = await _guardedDialog(
      () => showExportDialog(
        context,
        width: _document!.width,
        height: _document!.height,
        hasBackground: _backgroundImage != null,
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case ExportChoice.svg:
        await _exportSvg();
      case ExportChoice.png:
        await _exportPng();
      case ExportChoice.largePng:
        await _exportPng(scale: 2);
    }
  }

  Future<void> _exportPng({int scale = 1}) async {
    if (_busy || _confirmationOpen || _document == null) return;
    if (!_options.exports) return;
    if (!canExportDocumentPng(
      width: _document!.width,
      height: _document!.height,
      scale: scale,
    )) {
      _showProblem(
        StudioProblem.notice(
          tr(
            'Cette feuille est trop grande pour une image PNG. Choisis le format SVG.',
          ),
        ),
      );
      return;
    }
    final diagnostic = beginNativeDiagnosticOperation('png-export');
    void observe(String phase, {String? outcome}) => diagnostic?.record(
      phase,
      busy: _busy,
      mounted: mounted,
      outcome: outcome,
    );
    observe('started');
    _finishStroke();
    setState(() {
      _busy = true;
    });
    observe('busy-entered');
    try {
      observe('choosePng-started');
      final path = await widget.files.choosePng(currentPath: _currentPath);
      observe(
        'choosePng-returned',
        outcome: path == null ? 'cancelled' : 'selected',
      );
      if (path == null || !mounted) return;
      final document = _document!;
      observe('renderer-started');
      final png = await exportDocumentPng(
        document.visibleStrokes,
        width: document.width,
        height: document.height,
        scale: scale,
        background: _backgroundImage,
        paperRgb: document.paperRgb,
        onPhase: diagnostic == null ? null : (phase) => observe(phase.name),
      );
      observe('renderer-returned');
      observe('writer-started');
      await widget.files.writePng(path, png);
      observe('writer-returned');
      if (mounted) {
        setState(() {
          final (width, height) = (
            document.width * scale,
            document.height * scale,
          );
          final shown = widget.files.shownPath(path);
          final unsaved = _dirty;
          _status = () => trf('Image PNG exportée ({0} × {1}) : {2}{3}', [
            width,
            height,
            shown,
            unsaved ? tr(' · projet encore à enregistrer') : '',
          ]);
        });
        observe('status-applied');
      }
    } on CopyNotHandedOver {
      // The person closed the system's panel: nothing to say.
      observe('cancelled');
    } catch (error) {
      observe('failed');
      _error(error, message: tr('L’image n’a pas pu être exportée.'));
    } finally {
      observe('finally-entered');
      _releaseBusy();
      observe('finally-completed');
    }
  }

  Future<void> _exportSvg() async {
    if (_busy || _confirmationOpen || _document == null) return;
    if (!_options.exports) return;
    _finishStroke();
    setState(() {
      _busy = true;
    });
    try {
      final path = await widget.files.chooseExport(currentPath: _currentPath);
      recordNativeDiagnostics('export-panel-returned');
      if (path == null || !mounted) return;
      final document = _document!;
      final revision = _documentRevision;
      final storage = _storage;
      final generation = _recoveryGeneration;
      bool unchanged() =>
          mounted &&
          identical(document, _document) &&
          identical(storage, _storage) &&
          revision == _documentRevision &&
          generation == _recoveryGeneration;
      if (svgExportUsesWorker(document)) {
        setState(() => _busyLabel = tr('Préparation de ton image SVG…'));
        await WidgetsBinding.instance.endOfFrame;
        if (!unchanged()) return;
      }
      final bytes = await prepareSvgBytes(document);
      if (!unchanged()) return;
      await widget.files.writeSvgBytes(path, bytes);
      recordNativeDiagnostics('svg-written');
      if (unchanged()) {
        setState(() {
          final shown = widget.files.shownPath(path);
          final unsaved = _dirty;
          _status = () => trf('Image SVG exportée : {0}{1}', [
            shown,
            unsaved ? tr(' · projet encore à enregistrer') : '',
          ]);
        });
      }
      // Export deliberately never marks the editable project as saved.
    } on CopyNotHandedOver {
      // The person closed the system's panel: nothing to say.
    } catch (error) {
      _error(error, message: tr('L’image n’a pas pu être exportée.'));
    } finally {
      _releaseBusy();
    }
  }

  static String get _noPrinter => tr(
    'Color ne trouve pas d’imprimante sur cet ordinateur. Demande à un adulte d’en installer une, puis recommence.',
  );
  static String get _printUnavailable => tr(
    'Cette version de Color ne sait pas imprimer sur cet ordinateur. Tu peux exporter ton dessin en image, puis imprimer l’image.',
  );
  // The same in an interface that does not offer « Exporter ».
  static String get _printUnavailableWithoutExport => tr(
    'Cette version de Color ne sait pas imprimer sur cet ordinateur. Demande à un adulte.',
  );

  // « Imprimer » hands the picture of the sheet to the print panel of the
  // system, where the person chooses the printer or gives up. Color itself
  // never sends anything to a printer, and printing changes nothing in the
  // project: it stays to be saved if it was.
  Future<void> _printDrawing() async {
    if (_busy || _confirmationOpen || _document == null) return;
    // Switched off in the options: neither its key nor its menu prints.
    if (!_options.printing) return;
    _finishStroke();
    setState(() {
      _busy = true;
      _busyLabel = tr('Préparation de ton dessin pour l’imprimante…');
    });
    try {
      // The label is on screen before the engine starts on the image.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final document = _document!;
      final image = await renderDocumentForPrint(
        document.visibleStrokes,
        width: document.width,
        height: document.height,
        background: _backgroundImage,
        paperRgb: document.paperRgb,
      );
      if (!mounted) return;
      // The drawing shows again behind the panel of the system.
      setState(() => _busyLabel = null);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final outcome = await widget.printer(
        rgba: image.rgba,
        width: image.width,
        height: image.height,
        jobName: StudioFiles.printJobName(_currentPath),
      );
      if (!mounted) return;
      switch (outcome) {
        case PrintOutcome.sent:
          setState(() {
            // Confirmed in the panel of the system, which may as well have
            // made a file of it: the studio only says what it knows.
            final unsaved = _dirty;
            _status = () => trf('Impression lancée{0}', [
              unsaved ? tr(' · projet encore à enregistrer') : '',
            ]);
          });
          _sound(StudioSound.printed);
        case PrintOutcome.cancelled:
          // Nothing happened: the status still says where the project stands.
          break;
        case PrintOutcome.noPrinter:
          _showProblem(StudioProblem.notice(_noPrinter));
        case PrintOutcome.unavailable:
          _showProblem(
            StudioProblem.notice(
              _options.exports
                  ? _printUnavailable
                  : _printUnavailableWithoutExport,
            ),
          );
      }
    } catch (error) {
      _error(error, message: tr('Le dessin n’a pas pu être imprimé.'));
    } finally {
      _releaseBusy();
    }
  }

  Future<void> _showAbout() async {
    // Native menu callbacks can arrive again while a Flutter dialog is open.
    if (!mounted || _busy || _confirmationOpen) return;
    _finishStroke();
    await _guardedDialog<void>(
      () => showAboutColorDialog(
        context,
        hasGallery: _gallery != null,
        exports: _options.exports,
        layers: _options.layers,
        images: _options.opensFiles,
      ),
    );
  }

  Future<void> _showHelp() async {
    // Same guard as the other dialogs: nothing is edited behind it.
    if (!mounted || _busy || _confirmationOpen) return;
    _finishStroke();
    await _guardedDialog<void>(
      () => showHelpDialog(
        context,
        hasGallery: _gallery != null,
        options: _options,
      ),
    );
  }

  /// « Options » : the choices of the adult, behind a calculation when the
  /// adult has asked for one. They apply at once; nothing of the drawing is
  /// touched.
  Future<void> _openOptions() async {
    _settleLatch();
    if (!_dialogAllowed) return;
    _finishStroke();
    var closedByItself = false;
    final exit = await _guardedDialog<OptionsExit>(() async {
      if (_options.guarded) {
        final door = await showAdultGate(context);
        if (!mounted || door != AdultGate.opened) {
          closedByItself = door == AdultGate.closedAfterWrongAnswers;
          return OptionsExit.closed;
        }
      }
      if (!mounted) return OptionsExit.closed;
      return showOptionsDialog(context, store: _optionsStore);
    });
    if (!mounted) return;
    if (closedByItself) {
      // The door never closes without a word.
      _showProblem(StudioProblem.notice(forTouch(_doorClosed)));
      return;
    }
    // The two dialogs that the simplest interface keeps only here.
    switch (exit) {
      case OptionsExit.help:
        await _showHelp();
      case OptionsExit.about:
        await _showAbout();
      case OptionsExit.closed || null:
        break;
    }
  }

  static String get _doorClosed => tr(
    'Trois résultats faux : les options restent fermées. Clique de nouveau sur Options pour réessayer.',
  );

  // The film has something to show on a layer that is seen: an element that
  // the child drew, or a zone of a colouring page that the paint pot
  // coloured. The rest of the page is there from its first frame.
  bool get _canReplay =>
      !_busy && !_confirmationOpen && _document!.madePaintOrder.isNotEmpty;

  /// « Le dessin qui se refait tout seul » : the elements of the sheet are
  /// redrawn one after the other, in a dialog. The drawing is not changed.
  /// The page of a colouring page is there from the first frame, its zones
  /// white: those that the paint pot coloured take their colour one after
  /// the other, then what the child drew is redrawn.
  Future<void> _showReplay() async {
    _settleLatch();
    if (!_dialogAllowed || _document!.madePaintOrder.isEmpty) return;
    _finishStroke();
    final document = _document!;
    final scene = ReplayScene.fromDocumentOrder(
      all: _strokes,
      paintOrder: document.paintOrder,
      width: document.width,
      height: document.height,
      paperRgb: document.paperRgb,
      background: _backgroundImage,
      fixedLayers: document.lockedLayers,
    );
    await _guardedDialog<void>(
      () => showReplayDialog(
        context,
        scene: scene,
        onStarted: () => _sound(StudioSound.film),
        onFinished: () => _sound(StudioSound.bravo),
      ),
    );
  }

  void _toggleBigSheet() {
    if (_busy || _confirmationOpen || !_options.viewControls) return;
    _finishStroke();
    setState(() => _bigSheet = !_bigSheet);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // The « retour » of Android does not close the studio: what a child
    // presses by chance there must not end the drawing.
    canPop: !touchFirst,
    child: _studio(context),
  );

  Widget _studio(BuildContext context) {
    debugStudioBuilds++;
    if (_startupError != null) {
      return StudioStartupProblem(
        onDetails: () => _showProblemDetails(_startupError!),
      );
    }
    // The studio of a wide window is made of pebbles (Color 1.2); the
    // others keep the panels of before.
    final galets = !_phoneLayout(context) && _galetsOffered(context);
    if (!galets) {
      _stageOrigin = Offset.zero;
      _galetPanel = null;
    }
    return EduPaintDesktopMenu(
      onAbout: _showAbout,
      onNew: _busy ? null : _newDrawing,
      onOpen: _busy || !_options.opensFiles ? null : _openProject,
      onImportImage: _busy || !_options.opensFiles ? null : _importImage,
      onSave: _busy ? null : _saveProject,
      onSaveAs: _busy ? null : () => _saveProject(saveAs: true),
      onExportSvg: _busy || !_options.exports ? null : _exportSvg,
      onExportPng:
          _busy ||
              !_options.exports ||
              !canExportDocumentPng(
                width: _document!.width,
                height: _document!.height,
              )
          ? null
          : _exportPng,
      onPrint: _busy || !_options.printing ? null : _printDrawing,
      onOptions: _busy ? null : _openOptions,
      onUniverses: _busy ? null : _openUniverses,
      hasUniverses: _choosesUniverse,
      onReplay: _canReplay ? _showReplay : null,
      onUndo: _canUndo ? () => _history(false) : null,
      onRedo: !_busy && _document!.canRedo ? () => _history(true) : null,
      onDuplicate: _canEditSelection ? _duplicateSelection : null,
      onDelete: _canEditSelection ? _deleteSelection : null,
      onBringToFront: _canBringForward
          ? () => _reorderSelection(_document!.count - 1)
          : null,
      onSendToBack: _canSendBackward ? () => _reorderSelection(0) : null,
      onLayers: _busy || !_options.layers ? null : _openLayers,
      onEditText: _canEditText ? _editSelectedText : null,
      onGrow: _canResizeSelection(_growFactor)
          ? () => _resizeSelection(_growFactor)
          : null,
      onShrink: _canResizeSelection(_shrinkFactor)
          ? () => _resizeSelection(_shrinkFactor)
          : null,
      onHelp: _busy ? null : _showHelp,
      hasGallery: _gallery != null,
      onGallery: _busy ? null : _openGallery,
      // The keys of the menu do not come through the studio's own.
      beforeCommand: _settleLatch,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f1): _showHelp,
          // The names of the decor, one after the other (Color 1.2).
          const SingleActivator(LogicalKeyboardKey.f2): () => _nextName(1),
          const SingleActivator(LogicalKeyboardKey.f2, shift: true): () =>
              _nextName(-1),
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
              _history(false),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
              _history(false),
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ): () =>
              _history(true),
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): () =>
              _history(true),
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
              _saveProject,
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            meta: true,
            shift: true,
          ): () =>
              _saveProject(saveAs: true),
          const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
              _openProject,
          const SingleActivator(LogicalKeyboardKey.keyO, control: true):
              _openProject,
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
              _newDrawing,
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _newDrawing,
          const SingleActivator(
            LogicalKeyboardKey.keyE,
            meta: true,
            shift: true,
          ): _exportSvg,
          const SingleActivator(
            LogicalKeyboardKey.keyE,
            control: true,
            shift: true,
          ): _exportSvg,
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ): () =>
              _saveProject(saveAs: true),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              _saveProject,
          const SingleActivator(LogicalKeyboardKey.keyP, meta: true):
              _printDrawing,
          const SingleActivator(LogicalKeyboardKey.keyP, control: true):
              _printDrawing,
          const SingleActivator(LogicalKeyboardKey.escape): _escape,
          const SingleActivator(LogicalKeyboardKey.delete): _deleteSelection,
          const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelection,
          const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
              _duplicateSelection,
          const SingleActivator(LogicalKeyboardKey.keyD, control: true):
              _duplicateSelection,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _nudgeSelection(const Offset(-1, 0)),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _nudgeSelection(const Offset(1, 0)),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              _nudgeSelection(const Offset(0, -1)),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              _nudgeSelection(const Offset(0, 1)),
          const SingleActivator(
            LogicalKeyboardKey.arrowLeft,
            shift: true,
          ): () =>
              _nudgeSelection(const Offset(-10, 0)),
          const SingleActivator(
            LogicalKeyboardKey.arrowRight,
            shift: true,
          ): () =>
              _nudgeSelection(const Offset(10, 0)),
          const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
              _nudgeSelection(const Offset(0, -10)),
          const SingleActivator(
            LogicalKeyboardKey.arrowDown,
            shift: true,
          ): () =>
              _nudgeSelection(const Offset(0, 10)),
        },
        child: Focus(
          focusNode: _focus,
          onKeyEvent: _shapeModifiers,
          onFocusChange: (focused) {
            if (!focused && _spaceHeld) setState(() => _spaceHeld = false);
          },
          autofocus: true,
          child: Scaffold(
            body: _phoneLayout(context)
                ? _phoneBody()
                : galets
                ? _galetsBody(context)
                : Column(
                    children: [
                      if (!_bigSheet &&
                          _options.captions &&
                          MediaQuery.sizeOf(context).height >= 620)
                        Container(
                          width: double.infinity,
                          color: studioBanner,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 5,
                          ),
                          child: Text(
                            tr(
                              'Color · Un petit atelier pour les grandes idées',
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: studioHelpText,
                            ),
                          ),
                        ),
                      if (!_bigSheet)
                        StudioHeader(
                          onNew: _busy ? null : _newDrawing,
                          onOpen: _busy ? null : _openProject,
                          hasGallery: _gallery != null,
                          onGallery: _busy ? null : _openGallery,
                          onImportImage: _busy ? null : _importImage,
                          onSave: _busy ? null : _saveProject,
                          onExport: _busy ? null : _chooseExport,
                          onPrint: _busy ? null : _printDrawing,
                          onAbout: _busy ? null : _showAbout,
                          onHelp: _busy ? null : _showHelp,
                          onMenuVisibilityChanged: _colorDialogChanged,
                          onOptions: _busy ? null : _openOptions,
                          onUniverses: _busy ? null : _openUniverses,
                          showUniverses: _choosesUniverse,
                          showOpen: _options.opensFiles,
                          showImportImage: _options.opensFiles,
                          showExport: _options.exports,
                          showPrint: _options.printing,
                          showHelp: _options.headerHelp,
                          savedJustNow: _savedJustNow,
                        ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final wide =
                                !_bigSheet &&
                                _options.inspector &&
                                constraints.maxWidth >= 1120;
                            final textScale =
                                MediaQuery.textScalerOf(context).scale(12) / 12;
                            final tools = _options.groups;
                            final largeTools = _options.simpleControls;
                            final narrow = StudioLayout.toolsAbove(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              textScale: textScale,
                              toolCount: tools.length,
                              largeTools: largeTools,
                            );
                            // The sheet comes first: the controls under it are
                            // spacious only when the sheet stays comfortable.
                            final short = !StudioLayout.spaciousControls(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              narrow: narrow,
                              inspector: wide,
                              textScale: textScale,
                              toolCount: tools.length,
                              largeTools: largeTools,
                            );
                            final gap = short ? 6.0 : 12.0;
                            return Padding(
                              padding: EdgeInsets.all(
                                narrow || short ? 12 : 20,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!narrow) ...[
                                    StudioToolBar(
                                      selected: _tool.group,
                                      onSelected: _busy ? null : _selectGroup,
                                      tools: tools,
                                      large: largeTools,
                                    ),
                                    const SizedBox(width: 18),
                                  ],
                                  Expanded(
                                    // Named, so that it stays the same column when
                                    // a window made much wider or narrower at once
                                    // gives it neighbours on both sides: what it
                                    // holds, an open colour dialog for one, must
                                    // not be forgotten.
                                    key: const ValueKey('studioColumn'),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (narrow) ...[
                                          StudioToolBar(
                                            selected: _tool.group,
                                            onSelected: _busy
                                                ? null
                                                : _selectGroup,
                                            horizontal: true,
                                            tools: tools,
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        KeyedSubtree(
                                          key: const Key('documentToolbar'),
                                          child: _documentToolbar(),
                                        ),
                                        SizedBox(height: gap),
                                        Expanded(
                                          child: LayoutBuilder(
                                            builder: (context, room) {
                                              // Whatever the controls need, the
                                              // sheet keeps its floor: they scroll
                                              // in what is left, and drawing stays
                                              // in its own region.
                                              final controlsRoom = math.max(
                                                0.0,
                                                room.maxHeight -
                                                    gap -
                                                    StudioLayout.sheetFloor(
                                                      room.maxHeight,
                                                    ),
                                              );
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Expanded(child: _canvas()),
                                                  SizedBox(height: gap),
                                                  ConstrainedBox(
                                                    constraints: BoxConstraints(
                                                      maxHeight: controlsRoom,
                                                    ),
                                                    child: Scrollbar(
                                                      thumbVisibility: true,
                                                      child:
                                                          SingleChildScrollView(
                                                            key: const Key(
                                                              'drawingControlsScroll',
                                                            ),
                                                            primary: true,
                                                            child:
                                                                _drawingControls(
                                                                  narrow,
                                                                  compact:
                                                                      short,
                                                                ),
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (wide) ...[
                                    const SizedBox(width: 18),
                                    StudioInspector(
                                      tool: _tool,
                                      help: _toolHelp,
                                      rgb: _color,
                                      width: _width,
                                      fillRgb: _filled ? _fillColor : null,
                                      stamp: _tool == StudioTool.stamp
                                          ? _currentStamp
                                          : null,
                                      shape: _newShape,
                                      companionCue: _companionCue,
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ——— « Les galets » (Color 1.2): the studio of a wide window ———
  //
  // The sheet first. Two pebbles at the top, one line at the bottom, and
  // what a button opens beside it (galets.dart). The decor of the universe
  // has the whole window behind the sheet, less the band of the line.

  /// Whether the studio of this window is made of pebbles.
  bool _galetsOffered(BuildContext context) => GaletsLayout.offered(
    window: MediaQuery.sizeOf(context),
    textScale: MediaQuery.textScalerOf(context).scale(12) / 12,
    phone: _phoneLayout(context),
    simple: _options.simpleControls,
  );

  void _openGaletPanel(_GaletPanel panel, {int family = 0}) {
    if (_busy || _confirmationOpen) return;
    _settleLatch();
    _finishStroke();
    _closeName();
    setState(() {
      final same =
          _galetPanel == panel &&
          (panel != _GaletPanel.shades || _galetFamily == family);
      _galetPanel = same ? null : panel;
      _galetFamily = family;
    });
  }

  void _closeGaletPanel() {
    if (_galetPanel == null || !mounted) return;
    setState(() => _galetPanel = null);
    _focus.requestFocus();
  }

  // What a button of a panel does: the panel goes, then the action.
  VoidCallback? _fromPanel(VoidCallback? action) => action == null
      ? null
      : () {
          if (_galetPanel != null) setState(() => _galetPanel = null);
          action();
        };

  /// Where [button] stands in the frame of the pebbles; null before it was
  /// laid out.
  Rect? _galetAnchor(GlobalKey button) {
    final box = button.currentContext?.findRenderObject();
    final frame = _galetsFrame.currentContext?.findRenderObject();
    if (box is! RenderBox || frame is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: frame) & box.size;
  }

  GlobalKey get _galetPanelButton => switch (_galetPanel!) {
    _GaletPanel.drawing => _drawingButton,
    _GaletPanel.size => _sizeButton,
    _GaletPanel.which => _whichButton,
    _GaletPanel.shades => _swatchButtons[_galetFamily],
  };

  /// The colour the swatches show as chosen: the inside of shapes when
  /// that is what a colour changes, the colour in hand otherwise.
  int get _galetColour =>
      _canFill && _colorTarget == PaintColorTarget.fill ? _fillColor : _color;

  void _pickGaletColour(int rgb) {
    if (_busy || _confirmationOpen) return;
    _recentColors.remember(rgb);
    setState(() {
      _galetPanel = null;
      // A colour chosen is the choice: the pipette that was waiting has
      // nothing left to fetch.
      _picking = false;
      _chooseColor(rgb);
    });
    _sound(StudioSound.colour);
    _focus.requestFocus();
  }

  /// What the size button sizes: nothing (null), the width of a trait, or
  /// one of the three sizes of a text or of a stamp.
  ({bool placed, bool forStamp})? get _galetSized {
    if (_tool == StudioTool.fill || _tool == StudioTool.eraser) return null;
    final kind = _styledKind;
    if (kind == VectorKind.text || kind == VectorKind.stamp) {
      // A chosen text changes size with its words (Modifier); a chosen
      // stamp keeps the size it was given.
      if (_choosing) return null;
      return (placed: true, forStamp: kind == VectorKind.stamp);
    }
    if (_choosing && (_selectedObject == null || kind!.isBoxObject)) {
      return null;
    }
    return (placed: false, forStamp: false);
  }

  /// The width the size button shows: that of the chosen element, or the
  /// one in hand.
  double get _galetWidth =>
      _selectedObject != null && _choosing ? _selectedObject!.width : _width;

  void _pickGaletWidth(double width) {
    if (_busy || _confirmationOpen) return;
    setState(() {
      _galetPanel = null;
      // The chosen element takes it at once: one step for Annuler.
      if (_selectedObject != null && !_styleSelection(width: width)) return;
      _width = width;
    });
    _sound(StudioSound.tool);
    _focus.requestFocus();
  }

  /// Whether « lequel » has something to offer: the choices of the tool,
  /// or the inside of a shape.
  bool get _galetWhichOffered =>
      (!_choosing && _hasVariants) ||
      (_canFill && (!_choosing || _selectedObject != null));

  String get _galetWhichName => switch (_tool) {
    StudioTool.brush => tr('Sorte de trait'),
    StudioTool.magic => tr('Sorte de magie'),
    StudioTool.fill => tr('Façon de remplir'),
    StudioTool.stamp => trf('Tampon {0} · choisir un autre tampon', [
      _currentStamp?.label ?? '',
    ]),
    StudioTool.select => tr('Remplir la forme'),
    _ when _tool.group == ToolGroup.shapes => tr('Sorte de forme'),
    _ => tr('Rien à choisir pour cet outil'),
  };

  String get _galetWhichTitle => switch (_tool) {
    StudioTool.stamp => tr('Choisis un tampon'),
    _ => _galetWhichName,
  };

  // The widths of what the pebbles hold, as their buttons are laid out
  // below: the studio chooses what is written from what fits.
  static const _galetGap = 2.0;
  static double _galetWide(List<double> cells, {double padding = 12}) =>
      padding +
      cells.fold(0.0, (sum, cell) => sum + cell) +
      _galetGap * math.max(0, cells.length - 1);

  Widget _galetsBody(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    final document = _document!;
    // No decor around the sheet on a tablet (the owner, 12 November 2026).
    final worn = touchFirst ? null : _universe.decor;
    GaletsLayout laid({required bool decor, bool? big}) => GaletsLayout(
      window: window,
      safe: MediaQuery.paddingOf(context),
      documentWidth: document.width.toDouble(),
      documentHeight: document.height.toDouble(),
      decor: decor,
      bigSheet: big ?? _bigSheet,
      padding: _options.captions ? 28 : 8,
    );
    // « Dessiner en grand » is offered where it gives the sheet more room:
    // a sheet that already has the width of the window gains nothing when
    // the pebbles of the top are put away.
    final bigGains =
        laid(decor: worn != null, big: true).sheet.width >
        laid(decor: worn != null, big: false).sheet.width + 8;
    if (_bigSheet && !bigGains) _bigSheet = false;
    var layout = laid(decor: worn != null);
    DecorLayout? around;
    if (worn != null) {
      around = DecorLayout(
        frame: layout.decorFrame,
        sheetAtRest: layout.sheet,
        decor: worn.size,
        decorSheet: worn.sheet,
        clearTop: layout.decorClearTop,
        smallest: DecorLayout.smallestInWindow,
      );
      // Where its pieces would be too small to be looked at, no decor:
      // the sheet takes the room.
      if (!around.pieces) {
        around = null;
        layout = laid(decor: false);
      }
    }
    final decor = around == null ? null : worn;
    final painting = decor == null ? null : DecorPainting(decor, around!);
    _decorPainting = painting;
    _stageOrigin = layout.stage.topLeft;
    final enabled = !_busy && !_confirmationOpen;

    // ——— What is written at the top, from what the window leaves ———
    final nameStyle = galetText(17, bold: true);
    final drawingText = galetTextWidth(context, tr('Mon dessin'), nameStyle);
    final universeText = galetTextWidth(context, tr('Univers'), galetText(16));
    final saveText = galetTextWidth(
      context,
      tr('Enregistrer'),
      GaletSaveButton.style,
    );
    final viewCells = !_options.viewControls
        ? 0
        // The loupes are for a mouse: two fingers do it on a tablet.
        : (touchFirst ? 3 : 5);
    final rightCells =
        1 + (_options.layers ? 1 : 0) + viewCells - (bigGains ? 0 : 1) + 2;
    double leftWide({required bool named, required bool universe}) =>
        _galetWide([
          named ? 91 + drawingText : 75,
          if (_choosesUniverse) ...[
            GaletRule.width,
            universe ? 60 + universeText : GaletsLayout.cell,
          ],
        ]);
    double rightWide({required bool named}) => _galetWide([
      for (var index = 0; index < rightCells; index++) GaletsLayout.cell,
      GaletRule.width,
      if (viewCells > 0) GaletRule.width,
      6,
      named ? GaletSaveButton.namedWidth(saveText) : GaletsLayout.cell,
    ], padding: 15);
    final across = window.width - 2 * GaletsLayout.side;
    var drawingNamed = true;
    var universeNamed = true;
    var saveNamed = true;
    bool fits() =>
        leftWide(named: drawingNamed, universe: universeNamed) +
            rightWide(named: saveNamed) +
            12 <=
        across;
    if (!fits()) universeNamed = false;
    if (!fits()) saveNamed = false;
    if (!fits()) drawingNamed = false;
    final leftWidth = leftWide(named: drawingNamed, universe: universeNamed);
    final rightWidth = rightWide(named: saveNamed);

    // ——— The bubble of the companion, when it has the room ———
    final tip = _galetTip;
    final tipStrong = tip.strong;
    final tipText = tip.text;
    Widget? bubble;
    Widget? bubbleBelow;
    if (!_bigSheet && _options.toolHelp) {
      final room = across - leftWidth - rightWidth - 18 - 18;
      final wanted = GaletBubble.wanted(context, tipStrong, tipText);
      final width = wanted <= room
          ? wanted
          : room >= GaletBubble.narrowest &&
                wanted <= 2 * math.min(room, GaletBubble.widest) - 60
          ? math.min(room, GaletBubble.widest)
          : null;
      if (width != null) {
        bubble = GaletBubble(strong: tipStrong, text: tipText, width: width);
      } else if (tip.urgent) {
        // What matters now — the second click of a shape, a gesture in
        // progress — is said whatever the window: under the pebble where
        // there is no room beside it.
        bubbleBelow = GaletBubble(
          strong: tipStrong,
          text: tipText,
          width: math.min(math.max(leftWidth, 340), across),
          below: true,
        );
      }
    }

    final panel = _galetPanel;
    final anchor = panel == null ? null : _galetAnchor(_galetPanelButton);
    if (panel != null) {
      // A button may have moved since it was last laid out: the panel
      // follows at the next image.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _galetPanel != panel) return;
        if (_galetAnchor(_galetPanelButton) != anchor) setState(() {});
      });
    }

    return Stack(
      key: _galetsFrame,
      children: [
        if (decor == null)
          Positioned.fill(child: ColoredBox(color: studioBackground))
        else ...[
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: layout.band,
            child: ValueListenableBuilder<MouseCursor>(
              valueListenable: _besideCursor,
              builder: (context, cursor, child) => MouseRegion(
                cursor: cursor,
                onHover: (event) => _besideCursor.value =
                    _options.decorNames &&
                        _namesOffered &&
                        painting!.nameAt(event.localPosition) != null
                    ? SystemMouseCursors.help
                    : SystemMouseCursors.basic,
                child: child,
              ),
              // Beside the stage of the sheet: what is pressed there may
              // be asking the name of something.
              child: Listener(
                key: const Key('decorBeside'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) =>
                    _decorPressed(event, event.localPosition, beside: true),
                onPointerMove: (event) => _asking.move(event.localPosition),
                onPointerUp: (_) => _asking.lift(),
                onPointerCancel: (_) => _asking.lift(),
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: RepaintBoundary(
                      child: DecorView(
                        decor: decor,
                        sheetAtRest: layout.sheet,
                        motion: _options.decorMotion,
                        now: widget.clock,
                        resting: () => _gestureOnSheet,
                        clearTop: layout.decorClearTop,
                        smallest: DecorLayout.smallestInWindow,
                        onClock: () => _decorClock.value++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The ground goes on, plain, under the line.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: layout.band,
            // In the same room as the decor, at the same hour: the shade
            // of the evening and of the night falls on it too.
            child: ValueListenableBuilder<int>(
              valueListenable: _decorClock,
              builder: (context, _, _) => GaletGround(
                front: decor.front,
                veil: decor.veils[DayMoment.at(decorTime(widget.clock))],
                above: layout.decorFrame,
              ),
            ),
          ),
        ],
        Positioned.fromRect(
          rect: layout.stage,
          child: _readAt(2, _canvas(galets: layout)),
        ),
        // Where the sheet lies when the whole of it is shown: nothing to
        // see or to touch, a mark for whoever measures the studio.
        Positioned.fromRect(
          rect: layout.sheet,
          child: const IgnorePointer(
            child: SizedBox.expand(key: Key('sheetAtRest')),
          ),
        ),
        // The names of the decor: what a screen reader may ask about, and
        // the card of the thing that was asked.
        if (painting != null && _namesOffered)
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: layout.band,
            // Read last: the room is around the studio, not before it.
            child: _readAt(
              5,
              ValueListenableBuilder<DecorName?>(
                valueListenable: _shownName,
                builder: (context, shown, _) => DecorNameLayer(
                  painting: painting,
                  sheetAtRest: layout.sheet,
                  shown: shown,
                  onAsk: _showName,
                  onClose: _closeName,
                ),
              ),
            ),
          ),
        // A press beside an open panel puts it away, and does nothing else.
        if (panel != null)
          Positioned.fill(
            child: Listener(
              key: const Key('galetPanelBarrier'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _closeGaletPanel(),
            ),
          ),
        if (!_bigSheet)
          Positioned(
            left: GaletsLayout.side,
            top: layout.top,
            child: _readAt(
              0,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _galetOfDrawing(
                    named: drawingNamed,
                    universeNamed: universeNamed,
                    nameWidth: drawingText,
                    universeWidth: universeText,
                  ),
                  if (bubble != null) ...[const SizedBox(width: 18), bubble],
                ],
              ),
            ),
          ),
        if (bubbleBelow != null)
          Positioned(
            left: GaletsLayout.side,
            top: layout.top + GaletsLayout.topHeight + 10,
            child: _readAt(.5, IgnorePointer(child: bubbleBelow)),
          ),
        Positioned(
          right: GaletsLayout.side,
          top: layout.top,
          child: _readAt(
            1,
            _bigSheet
                ? _galetOfBigSheet(enabled)
                : _galetOfActions(saveNamed: saveNamed, bigSheet: bigGains),
          ),
        ),
        // What can be done with the chosen element, just above the line.
        if (_choosing && _selectedObject != null)
          Positioned(
            left: GaletsLayout.side,
            right: GaletsLayout.side,
            bottom: window.height - layout.lineTop + 10,
            child: _readAt(3, Center(child: _galetOfSelection())),
          ),
        Positioned(
          left: GaletsLayout.side,
          right: GaletsLayout.side,
          top: layout.lineTop,
          height: GaletsLayout.lineHeight,
          child: Center(
            // The line never goes beyond the window: where one more colour
            // than its ten asks for a little more room than there is, it
            // is drawn a little smaller.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _readAt(4, _galetLine(context, across)),
            ),
          ),
        ),
        // An open panel is read just after the pebble of its button.
        if (panel != null && anchor != null)
          Positioned.fill(
            child: _readAt(
              panel == _GaletPanel.drawing ? .25 : 4.5,
              _galetPanelLayer(panel, anchor),
            ),
          ),
      ],
    );
  }

  /// The order in which a screen reader goes through the studio of the
  /// pebbles: « Mon dessin » and the pebbles of the top, the sheet, the
  /// actions of a chosen element, the line, then the things of the decor —
  /// which lie behind everything and would otherwise be read first.
  static Widget _readAt(double order, Widget child) =>
      Semantics(container: true, sortKey: OrdinalSortKey(order), child: child);

  /// What the companion says in its bubble: a few words in bold, then a
  /// sentence. [urgent]: what matters now — the pipette, a gesture in
  /// progress, the second click of a shape — is said whatever the window;
  /// the few words of the tool in hand only where the window has room for
  /// them. (What is done with a chosen element is said in its own pebble,
  /// beside its actions.)
  ({String strong, String text, bool urgent}) get _galetTip {
    if (_helpIsUrgent || _shapeAnchor != null) {
      return (strong: '', text: _toolHelp, urgent: true);
    }
    final (strong, text) = _tool.tip;
    // « Dessiner sans tenir le bouton » changes how a trait is made.
    final holdFree = _holdFreeHelp;
    return (
      strong: strong,
      text: forTouch(holdFree != null && !_choosing ? holdFree : text),
      urgent: false,
    );
  }

  /// The pebble of the drawing: the companion and « Mon dessin », which
  /// opens what is done with the whole drawing; then « Univers ».
  Widget _galetOfDrawing({
    required bool named,
    required bool universeNamed,
    required double nameWidth,
    required double universeWidth,
  }) {
    final open = _galetPanel == _GaletPanel.drawing;
    return Galet(
      gap: _galetGap,
      children: [
        KeyedSubtree(
          key: _drawingButton,
          child: GaletButton(
            key: const Key('myDrawing'),
            // The line of state went with the panels: what the drawing
            // holds, and whether it is saved, is said here and at the top
            // of the panel.
            label: trf('Mon dessin : {0}', [_documentCaption]),
            hint: tr('Nouveau, ouvrir, exporter, imprimer, aide, options'),
            tip: !named,
            onPressed: _busy
                ? null
                : () => _openGaletPanel(_GaletPanel.drawing),
            selected: open,
            marksSelection: false,
            expanded: open,
            width: named ? 91 + nameWidth : 75,
            padding: EdgeInsets.only(left: 4, right: named ? 12 : 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GaletPortrait(cue: _companionCue),
                SizedBox(width: named ? 10 : 6),
                if (named) ...[
                  Text(
                    tr('Mon dessin'),
                    maxLines: 1,
                    style: galetText(
                      17,
                      bold: true,
                      color: open ? studioGreen : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                GaletChevron(
                  up: open,
                  size: 15,
                  color: open ? studioGreen : null,
                ),
              ],
            ),
          ),
        ),
        if (_choosesUniverse) ...[
          const GaletRule(),
          GaletButton(
            key: const Key('openUniverses'),
            label: tr('Univers'),
            tip: !universeNamed,
            onPressed: _busy ? null : _fromPanel(_openUniverses),
            width: universeNamed ? 60 + universeWidth : GaletsLayout.cell,
            padding: universeNamed
                ? const EdgeInsets.only(left: 8, right: 14)
                : EdgeInsets.zero,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EduIllustration(art: EduArt.universes, size: 30),
                if (universeNamed) ...[
                  const SizedBox(width: 8),
                  Text(tr('Univers'), maxLines: 1, style: galetText(16)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The pebble of the right: the film and the layers; the view; Annuler
  /// and Rétablir; « Enregistrer ».
  Widget _galetOfActions({required bool saveNamed, required bool bigSheet}) {
    final view = _viewEnabled;
    return Galet(
      gap: _galetGap,
      padding: const EdgeInsets.fromLTRB(8, 6, 7, 6),
      children: [
        GaletPictureButton(
          key: const Key('replayDrawing'),
          art: EduArt.film,
          label: tr('Revoir ton dessin se faire tout seul'),
          onPressed: _canReplay ? _fromPanel(_showReplay) : null,
        ),
        if (_options.layers)
          GaletPictureButton(
            key: const Key('layersButton'),
            art: EduArt.layers,
            label: trf('Calques : tu dessines sur {0}', [
              layerName(_document!.activeLayer, _document!.layers),
            ]),
            onPressed: _busy || _confirmationOpen
                ? null
                : _fromPanel(_openLayers),
          ),
        const GaletRule(),
        if (_options.viewControls) ...[
          if (!touchFirst) ...[
            GaletPictureButton(
              key: const Key('zoomOut'),
              art: EduArt.zoomOut,
              label: tr('Éloigner la feuille'),
              onPressed: view ? _fromPanel(() => _zoom(1 / 1.25)) : null,
            ),
            GaletPictureButton(
              key: const Key('zoomIn'),
              art: EduArt.zoomIn,
              label: tr('Rapprocher la feuille'),
              onPressed: view ? _fromPanel(() => _zoom(1.25)) : null,
            ),
          ],
          // It answers only when the sheet is seen from closer, or moved:
          // at rest it says that the whole sheet is shown. The view
          // changes without building the studio again: it listens.
          ValueListenableBuilder<int>(
            valueListenable: _viewRebuild,
            builder: (context, _, _) => GaletPictureButton(
              key: const Key('fitPage'),
              art: EduArt.wholeSheet,
              label: tr('Voir toute la feuille'),
              onPressed: view && !(_view?.isFit ?? true)
                  ? _fromPanel(_fitView)
                  : null,
            ),
          ),
          GaletPictureButton(
            key: const Key('panPage'),
            art: EduArt.moveSheet,
            label: tr('Déplacer la feuille'),
            selected: _panning,
            marksSelection: true,
            onPressed: view ? _fromPanel(_togglePan) : null,
          ),
          if (bigSheet)
            GaletPictureButton(
              key: const Key('bigSheet'),
              art: EduArt.bigSheet,
              label: tr('Dessiner en grand'),
              onPressed: view ? _fromPanel(_toggleBigSheet) : null,
            ),
          const GaletRule(),
        ],
        ..._galetHistory(),
        const SizedBox(width: 6),
        GaletSaveButton(
          key: const Key('saveProject'),
          onPressed: _busy ? null : _fromPanel(_saveProject),
          named: saveNamed,
          savedJustNow: _savedJustNow,
          unsaved: _dirty,
        ),
      ],
    );
  }

  List<Widget> _galetHistory() => [
    GaletPictureButton(
      key: const Key('undo'),
      art: EduArt.undo,
      label: tr('Annuler le dernier geste'),
      onPressed: _canUndo ? _fromPanel(() => _history(false)) : null,
    ),
    GaletPictureButton(
      key: const Key('redo'),
      art: EduArt.redo,
      label: tr('Rétablir le geste annulé'),
      onPressed: !_busy && _document!.canRedo
          ? _fromPanel(() => _history(true))
          : null,
    ),
  ];

  /// « Dessiner en grand » : the pebbles of the top are put away, but for
  /// Annuler, Rétablir and the button that brings them back.
  Widget _galetOfBigSheet(bool enabled) => Galet(
    gap: _galetGap,
    vertical: true,
    children: [
      ..._galetHistory(),
      GaletPictureButton(
        key: const Key('bigSheet'),
        art: EduArt.bigSheet,
        label: tr('Retrouver tous les panneaux'),
        selected: true,
        marksSelection: true,
        onPressed: enabled ? _fromPanel(_toggleBigSheet) : null,
      ),
    ],
  );

  void _togglePan() {
    _finishStroke();
    setState(() => _panning = !_panning);
    _focus.requestFocus();
  }

  /// The actions on the chosen element, in a pebble of their own, after
  /// the sentence that says how it is moved and what a colour does to it.
  Widget _galetOfSelection() => RepaintBoundary(
    child: Container(
      key: const Key('galetSelection'),
      constraints: const BoxConstraints(maxWidth: 640),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: studioSurface,
        borderRadius: galetCorners(60),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24263f43),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x29263f43),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: _selectionToolbar(compact: true),
      ),
    ),
  );

  /// The line: the tools, the two settings — how big, and which one —,
  /// then the ten elementary colours. Only the tool in hand has its name
  /// written, and only where the window leaves the room.
  Widget _galetLine(BuildContext context, double across) {
    final enabled = !_busy && !_confirmationOpen;
    final groups = _options.groups;
    final chosen = _tool.group;
    final current = _galetColour;
    final family = galetFamilyOf(current);
    final toolStyle = galetText(16, bold: true, color: studioGreen);
    final nameWidth = galetTextWidth(context, chosen.label, toolStyle);
    // The longest name of a tool: the line keeps room for it, so that the
    // two settings and the colours stay where they are whatever the tool.
    final longestName = groups
        .map((group) => galetTextWidth(context, group.label, toolStyle))
        .fold(0.0, math.max);
    const cell = GaletsLayout.cell;
    final swatches = galetColours.length + (family == null ? 1 : 0);
    double wide({required bool named}) =>
        20 +
        (groups.length - 1) * cell +
        (named ? 70 + longestName : cell) +
        2 * GaletRule.width +
        52 +
        66 +
        swatches * cell +
        (groups.length + swatches + (named ? 4 : 3));
    final named = wide(named: true) <= across;
    // In the narrowest window the ends of the line give a little of their
    // room before any button is drawn smaller.
    final ends = (10 - math.max(0.0, wide(named: named) - across) / 2).clamp(
      4.0,
      10.0,
    );
    final sized = _galetSized;
    final pale = galetPale(_color);
    final sizeOpen = _galetPanel == _GaletPanel.size;
    final whichOpen = _galetPanel == _GaletPanel.which;
    final whichOffered = _galetWhichOffered;
    final stamp = _tool == StudioTool.stamp ? _currentStamp : null;
    final witness = ToolVariants.witness(
      tool: _tool,
      brush: _brushTool,
      magic: _magic,
      shape: _newShape,
      rgb: _color,
      pour: _pourKind,
      secondRgb: _previousColor,
      outline: pale ? studioSwatchRing : null,
    );
    // The dot of the size button: as large as the trait is wide, between
    // the smallest and the largest of the five.
    final dot = sized == null
        ? 9.0
        : sized.placed
        ? 10.0 + 4 * (sized.forStamp ? _stampSize : _textSize).index.toDouble()
        : (5 +
                  15 *
                      math.log(
                        _galetWidth.clamp(galetWidths.first, galetWidths.last) /
                            galetWidths.first,
                      ) /
                      math.log(galetWidths.last / galetWidths.first))
              .toDouble();
    return Galet(
      key: const Key('galetLine'),
      height: GaletsLayout.lineHeight,
      padding: EdgeInsets.symmetric(horizontal: ends, vertical: 8),
      gap: 1,
      children: [
        for (final group in groups)
          GaletButton(
            key: Key(group.keyName),
            label: group.label,
            selected: group == chosen,
            tip: !(named && group == chosen),
            onPressed: enabled ? () => _galetTool(group) : null,
            width: named && group == chosen ? 70 + nameWidth : cell,
            padding: named && group == chosen
                ? const EdgeInsets.only(left: 12, right: 18)
                : EdgeInsets.zero,
            child: named && group == chosen
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EduIllustration(art: group.art, size: 32),
                      const SizedBox(width: 8),
                      Text(group.label, maxLines: 1, style: toolStyle),
                    ],
                  )
                : EduIllustration(art: group.art, size: 30),
          ),
        // What a shorter name leaves of the room of the longest.
        if (named) SizedBox(width: longestName - nameWidth),
        const GaletRule(),
        KeyedSubtree(
          key: _sizeButton,
          child: GaletButton(
            key: const Key('galetSize'),
            label: sized == null
                ? tr('Rien à régler pour cet outil')
                : sized.placed
                ? (sized.forStamp
                      ? tr('Taille du tampon')
                      : tr('Taille du texte'))
                : tr('Taille du trait'),
            onPressed: enabled && sized != null
                ? () => _openGaletPanel(_GaletPanel.size)
                : null,
            selected: sizeOpen,
            marksSelection: false,
            expanded: sized == null ? null : sizeOpen,
            width: 52,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: Center(
                    child: Container(
                      width: dot,
                      height: dot,
                      decoration: BoxDecoration(
                        color: Color(0xff000000 | _color),
                        shape: BoxShape.circle,
                        border: pale
                            ? Border.all(color: studioSwatchRing, width: 1)
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                GaletChevron(color: sizeOpen ? studioGreen : null),
              ],
            ),
          ),
        ),
        KeyedSubtree(
          key: _whichButton,
          child: GaletButton(
            key: const Key('galetWhich'),
            label: whichOffered
                ? _galetWhichName
                : tr('Rien à choisir pour cet outil'),
            onPressed: enabled && whichOffered
                ? () => _openGaletPanel(_GaletPanel.which)
                : null,
            selected: whichOpen,
            marksSelection: false,
            expanded: whichOffered ? whichOpen : null,
            width: 66,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 32,
                  child: Center(
                    child: stamp != null
                        ? StampPreview(stamp: stamp, rgb: _color, size: 32)
                        : witness != null
                        ? CustomPaint(
                            size: const Size(34, 22),
                            painter: witness,
                          )
                        : Container(
                            width: 18,
                            height: 3,
                            decoration: BoxDecoration(
                              color: studioQuietMark,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 3),
                GaletChevron(color: whichOpen ? studioGreen : null),
              ],
            ),
          ),
        ),
        const GaletRule(),
        for (final (index, colour) in galetColours.indexed)
          KeyedSubtree(
            key: _swatchButtons[index],
            child: GaletSwatch(
              key: Key('color-${colour.rgb.toRadixString(16)}'),
              rgb: colour.rgb,
              name: colour.name,
              chosen: family == index,
              ticked: colour.rgb == current,
              onPressed: enabled ? () => _pickGaletColour(colour.rgb) : null,
              onShades: galetFamilies[index].isEmpty
                  ? null
                  : () => _openGaletPanel(_GaletPanel.shades, family: index),
            ),
          ),
        // A colour that the line does not offer — that of an element, of
        // an older drawing — takes the last place while it is in hand.
        if (family == null)
          GaletSwatch(
            key: Key('color-${current.toRadixString(16)}'),
            rgb: current,
            name: paintColorName(current),
            chosen: true,
            onPressed: enabled ? () => _pickGaletColour(current) : null,
          ),
      ],
    );
  }

  // A tool of the line: chosen, or — already in hand — its choices opened.
  void _galetTool(ToolGroup group) {
    if (_galetPanel != null) setState(() => _galetPanel = null);
    _selectGroup(group);
  }

  Widget _galetPanelLayer(_GaletPanel panel, Rect anchor) => GaletPanel(
    key: Key('galetPanel-${panel.name}'),
    anchor: anchor,
    above: panel != _GaletPanel.drawing,
    gap: panel == _GaletPanel.shades ? 16 : 14,
    padding: EdgeInsets.all(panel == _GaletPanel.shades ? 10 : 14),
    label: switch (panel) {
      _GaletPanel.drawing => tr('Mon dessin'),
      _GaletPanel.size => tr('Taille'),
      _GaletPanel.which => _galetWhichTitle,
      _GaletPanel.shades => tr('Nuances'),
    },
    child: switch (panel) {
      _GaletPanel.drawing => _galetDrawingPanel(),
      _GaletPanel.size => _galetSizePanel(),
      _GaletPanel.which => _galetWhichPanel(),
      _GaletPanel.shades => _galetShadesPanel(),
    },
  );

  static Widget _galetPanelRule() => Container(
    height: 1.5,
    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
    color: studioLine,
  );

  /// « Mon dessin » : what the drawing holds, then what is done with the
  /// whole of it, in large buttons; help, options and « À propos » under a
  /// line.
  Widget _galetDrawingPanel() {
    final free = !_busy;
    Widget tile(String key, String name, EduArt art, VoidCallback action) =>
        GaletTile(
          key: Key(key),
          name: name,
          picture: EduIllustration(art: art, size: 36),
          onPressed: free ? _fromPanel(action) : null,
        );
    final path = _currentPath;
    return SizedBox(
      width: 3 * 116 + 2 * 6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(6, 2, 6, _options.statusLine ? 3 : 10),
            child: Text(
              path == null
                  ? _documentCaption
                  : '$_documentTitle · $_documentCaption',
              key: const Key('drawingCaption'),
              style: galetText(14, color: studioCaption),
            ),
          ),
          // What the line under the sheet said in the studio of before:
          // the last thing that happened to the drawing.
          if (_options.statusLine)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
              child: ValueListenableBuilder<String>(
                valueListenable: _statusLine,
                builder: (context, status, _) => Text(
                  status,
                  key: const Key('drawingStatus'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: galetText(12.5, color: studioStatusText),
                ),
              ),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              tile('newProject', tr('Nouveau'), EduArt.newPage, _newDrawing),
              if (_options.opensFiles)
                tile('openProject', tr('Ouvrir'), EduArt.folder, _openProject),
              if (_gallery != null)
                tile(
                  'openGallery',
                  tr('Mes dessins'),
                  EduArt.gallery,
                  _openGallery,
                ),
              if (_options.opensFiles)
                tile(
                  'importImage',
                  tr('Sur une image'),
                  EduArt.onPicture,
                  _importImage,
                ),
              if (_options.exports)
                tile(
                  'exportImage',
                  tr('Exporter'),
                  EduArt.exportImage,
                  _chooseExport,
                ),
              if (_options.printing)
                tile(
                  'printDrawing',
                  tr('Imprimer'),
                  EduArt.printer,
                  _printDrawing,
                ),
            ],
          ),
          _galetPanelRule(),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (_options.headerHelp)
                tile('showHelp', tr('Aide'), EduArt.help, _showHelp),
              tile('openOptions', tr('Options'), EduArt.options, _openOptions),
              // Always there: the privacy policy is reached through it.
              tile('aboutColor', tr('À propos'), EduArt.about, _showAbout),
            ],
          ),
        ],
      ),
    );
  }

  /// The size: five dots as large as the trait they give; for a text or a
  /// stamp, three sizes.
  Widget _galetSizePanel() {
    final sized = _galetSized;
    if (sized == null) return const SizedBox.shrink();
    final colour = Color(0xff000000 | _color);
    final pale = galetPale(_color);
    Widget dot(double diameter) => Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        border: pale ? Border.all(color: studioSwatchRing, width: 1) : null,
      ),
    );
    if (sized.placed) {
      final value = sized.forStamp ? _stampSize : _textSize;
      final what = sized.forStamp ? tr('du tampon') : tr('du texte');
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GaletHeading(
            sized.forStamp ? tr('Taille du tampon') : tr('Taille du texte'),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final size in ObjectSize.values) ...[
                if (size != ObjectSize.values.first) const SizedBox(width: 4),
                GaletButton(
                  key: Key('size-${size.name}'),
                  label: trf('Taille {0} : {1}', [what, size.label]),
                  selected: size == value,
                  framed: true,
                  width: 60,
                  height: 60,
                  onPressed: () {
                    setState(() {
                      _galetPanel = null;
                      if (sized.forStamp) {
                        _stampSize = size;
                      } else {
                        _textSize = size;
                      }
                    });
                    _focus.requestFocus();
                  },
                  child: dot(12.0 + 8 * size.index),
                ),
              ],
            ],
          ),
        ],
      );
    }
    final chosen = galetWidthIndex(_galetWidth);
    const diameters = [5.0, 9.0, 14.0, 20.0, 28.0];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GaletHeading(tr('Taille du trait')),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, width) in galetWidths.indexed) ...[
              if (index > 0) const SizedBox(width: 4),
              GaletButton(
                key: Key('width-$index'),
                label: trf('Taille {0} sur {1}', [
                  index + 1,
                  galetWidths.length,
                ]),
                selected: index == chosen,
                framed: true,
                width: 60,
                height: 60,
                onPressed: () => _pickGaletWidth(width),
                child: dot(diameters[index]),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// « Lequel » : the sorts of trait, the magics, the shapes, how the pot
  /// pours, the stamps — each with its name —, and for what has an inside,
  /// whether it is filled and which colour a swatch then changes.
  Widget _galetWhichPanel() {
    final enabled = !_busy && !_confirmationOpen;
    final stamps = _tool == StudioTool.stamp;
    final variants = !_choosing && _hasVariants && !stamps;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GaletHeading(_galetWhichTitle),
        const SizedBox(height: 10),
        if (variants)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 5 * 104 + 4 * 4),
            child: _toolVariants(tiles: true),
          ),
        if (stamps) _galetStamps(enabled),
        if (_canFill) ...[
          if (variants) _galetPanelRule(),
          _galetInside(enabled),
        ],
      ],
    );
  }

  // The stamps of the catalogue, in the colour in hand, with their names;
  // then the two buttons that turn the next one.
  Widget _galetStamps(bool enabled) {
    StampCatalog? catalog;
    try {
      catalog = StampCatalog.instance;
    } catch (_) {
      // The catalogue comes from the core; the studio stays usable
      // without it.
    }
    final look = _stampLook;
    return SizedBox(
      width: 6 * 92 + 5 * 4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (catalog != null)
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final stamp in catalog.stamps)
                  GaletTile(
                    key: Key('stamp-${stamp.key}'),
                    name: stamp.label,
                    label: trf('Tampon {0}', [stamp.label]),
                    selected: stamp.id == _stampId,
                    width: 92,
                    height: 92,
                    fontSize: 13.5,
                    picture: StampPreview(stamp: stamp, rgb: _color, size: 54),
                    onPressed: enabled
                        ? () {
                            setState(() {
                              _galetPanel = null;
                              _stampId = stamp.id;
                            });
                            _sound(StudioSound.tool);
                            _focus.requestFocus();
                          }
                        : null,
                  ),
              ],
            ),
          _galetPanelRule(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GaletWideButton(
                key: const Key('turnStamp'),
                name: tr('Tourner'),
                selected: look.rotation != 0,
                picture: const EduIllustration(art: EduArt.turn, size: 32),
                onPressed: enabled
                    ? () {
                        setState(() => _stampEighths = (_stampEighths + 1) % 8);
                        _sound(StudioSound.tool);
                      }
                    : null,
              ),
              const SizedBox(width: 6),
              GaletWideButton(
                key: const Key('mirrorStamp'),
                name: tr('Retourner'),
                selected: look.mirrorX,
                picture: const EduIllustration(art: EduArt.mirror, size: 32),
                onPressed: enabled
                    ? () {
                        setState(() => _stampMirrored = !_stampMirrored);
                        _sound(StudioSound.tool);
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // The inside of a shape: filled or not, and which of its two colours a
  // swatch changes.
  Widget _galetInside(bool enabled) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        label: tr('Remplir la forme'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 48,
              child: Checkbox(
                key: const Key('fillShapeCheckbox'),
                value: _filled,
                onChanged: enabled
                    ? (value) => _setFilled(value ?? false)
                    : null,
              ),
            ),
            Text(tr('Remplir'), style: galetText(15)),
          ],
        ),
      ),
      const SizedBox(width: 18),
      for (final target in PaintColorTarget.values)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: GaletButton(
            key: ValueKey('paint-target-${target.name}'),
            label: target == PaintColorTarget.stroke
                ? tr('La couleur du trait')
                : tr('La couleur de l’intérieur'),
            selected: _colorTarget == target,
            framed: true,
            tip: false,
            height: 48,
            corners: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            onPressed: enabled
                ? () => setState(() => _colorTarget = target)
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: target == PaintColorTarget.fill
                        ? Color(0xff000000 | _fillColor)
                        : null,
                    border: Border.all(
                      color: target == PaintColorTarget.stroke
                          ? Color(0xff000000 | _color)
                          : studioSwatchRing,
                      width: target == PaintColorTarget.stroke ? 4 : 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  target == PaintColorTarget.stroke
                      ? tr('Trait')
                      : tr('Intérieur'),
                  style: galetText(15),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  /// The shades of a colour of the line, from the lightest to the darkest,
  /// in a small column right above its swatch.
  Widget _galetShadesPanel() {
    final enabled = !_busy && !_confirmationOpen;
    final current = _galetColour;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final shade in galetFamilies[_galetFamily])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: GaletSwatch(
              key: Key('nuance-${shade.rgb.toRadixString(16)}'),
              rgb: shade.rgb,
              name: shade.name,
              chosen: shade.rgb == current,
              cell: 52,
              diameter: 38,
              onPressed: enabled ? () => _pickGaletColour(shade.rgb) : null,
            ),
          ),
      ],
    );
  }

  /// A telephone on its side, as opposed to a tablet or a computer: the
  /// studio then has a layout of its own.
  bool _phoneLayout(BuildContext context) =>
      touchFirst && phoneRoom(View.of(context), MediaQuery.sizeOf(context));

  /// What the line above the sheet says of the drawing, and the menu of a
  /// telephone: how many elements, and whether they are saved. What the
  /// child made: the untouched zones and the lines of a colouring page are
  /// not counted, a zone that the paint pot coloured is.
  String get _documentCaption =>
      '${elementCount(_document!.madeCount)} · ${_dirty
          ? tr('modifications non enregistrées')
          : _currentPath == null
          ? tr('nouvelle feuille')
          : tr('projet enregistré')}';

  String get _documentTitle => _currentPath == null
      ? tr('Mon dessin')
      : StudioFiles.fileName(_currentPath!);

  // The studio of a telephone on its side. The sheet takes the whole
  // height, in the middle. On the left, the tools under the button of the
  // menu, all in view. On the right, a column that scrolls: Annuler and
  // Rétablir, the colours, the size and what the tool chooses. Everything
  // else — the actions on the drawing, its film, the layers, help and
  // options — is in the menu.
  Widget _phoneBody() {
    final simple = _options.simpleControls;
    final railSide = BorderSide(color: studioLine);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: studioSurface,
            border: Border(right: railSide),
          ),
          child: StudioToolBar(
            rail: true,
            leading: _phoneMenuButton(),
            selected: _tool.group,
            onSelected: _busy ? null : _selectGroup,
            tools: _options.groups,
            large: simple,
          ),
        ),
        Expanded(
          child: Padding(padding: const EdgeInsets.all(6), child: _canvas()),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: studioSurface,
            border: Border(left: railSide),
          ),
          child: SizedBox(
            width:
                ColorPalette.railWidth(simple: simple) +
                _phoneRailPadding.horizontal,
            child: _phoneSideRail(),
          ),
        ),
      ],
    );
  }

  // Room on the right of the column for its scrollbar.
  static const _phoneRailPadding = EdgeInsets.fromLTRB(8, 8, 14, 8);

  Widget _phoneMenuButton() => SizedBox(
    height: 48,
    child: OutlinedButton(
      key: const Key('phoneMenu'),
      onPressed: _busy || _confirmationOpen ? null : _openPhoneMenu,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: studioSurface,
        foregroundColor: studioInk,
      ),
      // The drawing has just been saved: the button of the menu, where
      // « Enregistrer » is, shows the tick for a moment.
      child: _savedJustNow
          ? Semantics(
              liveRegion: true,
              label: tr('Dessin enregistré'),
              child: Icon(
                Icons.check_circle,
                key: Key('savedTick'),
                size: 30,
                color: studioGreen,
              ),
            )
          : Tooltip(
              message: tr('Menu'),
              excludeFromSemantics: true,
              child: Icon(
                Icons.menu_rounded,
                size: 30,
                semanticLabel: tr('Menu'),
              ),
            ),
    ),
  );

  Future<void> _openPhoneMenu() async {
    if (_busy || _confirmationOpen) return;
    _settleLatch();
    final entries = [
      PhoneMenuEntry(
        id: 'newProject',
        name: tr('Nouveau'),
        picture: (size) => EduIllustration(art: EduArt.newPage, size: size),
        enabled: true,
      ),
      if (_options.opensFiles)
        PhoneMenuEntry(
          id: 'openProject',
          name: tr('Ouvrir'),
          picture: (size) => EduIllustration(art: EduArt.folder, size: size),
          enabled: true,
        ),
      if (_gallery != null)
        PhoneMenuEntry(
          id: 'openGallery',
          name: tr('Mes dessins'),
          picture: (size) => EduIllustration(art: EduArt.gallery, size: size),
          enabled: true,
        ),
      if (_options.opensFiles)
        PhoneMenuEntry(
          id: 'importImage',
          name: tr('Sur une image'),
          picture: (size) =>
              Icon(Icons.add_photo_alternate_outlined, size: size),
          enabled: true,
        ),
      PhoneMenuEntry(
        id: 'saveProject',
        name: tr('Enregistrer'),
        picture: (size) => EduIllustration(art: EduArt.save, size: size),
        enabled: true,
        filled: true,
      ),
      if (_options.exports)
        PhoneMenuEntry(
          id: 'exportImage',
          name: tr('Exporter'),
          picture: (size) =>
              EduIllustration(art: EduArt.exportImage, size: size),
          enabled: true,
        ),
      if (_options.printing)
        PhoneMenuEntry(
          id: 'printDrawing',
          name: tr('Imprimer'),
          picture: (size) => EduIllustration(art: EduArt.printer, size: size),
          enabled: true,
        ),
      PhoneMenuEntry(
        id: 'replayDrawing',
        name: tr('Revoir'),
        picture: (size) => EduIllustration(art: EduArt.film, size: size),
        enabled: _canReplay,
      ),
      if (_options.layers)
        PhoneMenuEntry(
          id: 'layersButton',
          name: tr('Calques'),
          picture: (size) => EduIllustration(art: EduArt.layers, size: size),
          enabled: true,
        ),
      if (_options.viewControls)
        PhoneMenuEntry(
          id: 'fitPage',
          name: tr('Toute la feuille'),
          picture: (size) => Icon(Icons.fit_screen_outlined, size: size),
          enabled: _viewEnabled && _view != null && !_view!.isFit,
        ),
      if (_options.headerHelp)
        PhoneMenuEntry(
          id: 'showHelp',
          name: tr('Aide'),
          picture: (size) => Icon(Icons.help_outline, size: size),
          enabled: true,
        ),
      if (_choosesUniverse)
        PhoneMenuEntry(
          id: 'openUniverses',
          name: tr('Univers'),
          picture: (size) => EduIllustration(art: EduArt.universes, size: size),
          enabled: true,
        ),
      PhoneMenuEntry(
        id: 'openOptions',
        name: tr('Options'),
        picture: (size) => EduIllustration(art: EduArt.options, size: size),
        enabled: true,
      ),
      // Always there: the privacy policy is reached through it.
      PhoneMenuEntry(
        id: 'aboutColor',
        name: tr('À propos'),
        picture: (size) => Icon(Icons.info_outline, size: size),
        enabled: true,
      ),
    ];
    _colorDialogChanged(true);
    String? chosen;
    try {
      chosen = await showPhoneMenu(
        context,
        title: _documentTitle,
        caption: _documentCaption,
        entries: entries,
      );
    } finally {
      _colorDialogChanged(false);
    }
    if (!mounted || chosen == null) return;
    switch (chosen) {
      case 'newProject':
        _newDrawing();
      case 'openProject':
        _openProject();
      case 'openGallery':
        _openGallery();
      case 'importImage':
        _importImage();
      case 'saveProject':
        _saveProject();
      case 'exportImage':
        _chooseExport();
      case 'printDrawing':
        _printDrawing();
      case 'replayDrawing':
        _showReplay();
      case 'layersButton':
        _openLayers();
      case 'fitPage':
        _fitView();
      case 'showHelp':
        _showHelp();
      case 'openUniverses':
        _openUniverses();
      case 'openOptions':
        _openOptions();
      case 'aboutColor':
        _showAbout();
    }
  }

  Widget _phoneSideRail() {
    final enabled = !_busy && !_confirmationOpen;
    Widget history(bool redo) => SizedBox.square(
      dimension: 48,
      child: IconButton.outlined(
        key: Key(redo ? 'redo' : 'undo'),
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: redo
            ? (!_busy && _document!.canRedo ? () => _history(true) : null)
            : (_canUndo ? () => _history(false) : null),
        icon: Semantics(
          label: redo
              ? tr('Rétablir le geste annulé')
              : tr('Annuler le dernier geste'),
          child: EduIllustration(
            art: redo ? EduArt.redo : EduArt.undo,
            size: 26,
          ),
        ),
      ),
    );
    return Scrollbar(
      controller: _phoneRail,
      thumbVisibility: true,
      child: SingleChildScrollView(
        key: const Key('phoneSideRail'),
        controller: _phoneRail,
        padding: _phoneRailPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [history(false), history(true)],
            ),
            // What can be done with the chosen element comes first: Copier
            // and Effacer must not wait under every colour.
            if (_choosing) ...[
              const SizedBox(height: 10),
              _selectionToolbar(compact: true, showHint: false),
            ],
            if (_canFill) ...[
              const SizedBox(height: 8),
              Semantics(
                label: tr('Remplir la forme'),
                child: Row(
                  children: [
                    Checkbox(
                      key: const Key('fillShapeCheckbox'),
                      value: _filled,
                      onChanged: enabled
                          ? (value) => _setFilled(value ?? false)
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        tr('Remplir'),
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            _palettePanel(true, rail: true),
          ],
        ),
      ),
    );
  }

  Widget _drawingControls(bool narrow, {required bool compact}) => Column(
    key: const Key('drawingControls'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // « Dessiner en grand » keeps the colours, in their tightest form.
      _palettePanel(narrow, compact: compact || _bigSheet),
      // The choices of a tool stay in « Dessiner en grand », as the actions
      // of a chosen element do; the sentences of help do not.
      if (_hasVariants || _choosing || (!_bigSheet && _options.toolHelp)) ...[
        SizedBox(height: compact ? 6 : 10),
        Row(
          children: [
            if (!_choosing && !_bigSheet) ...[
              Companion(size: compact ? 32 : 56, cue: _companionCue),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: _choosing
                  ? _selectionToolbar(compact: compact || _bigSheet)
                  : _hasVariants && (_bigSheet || !_options.toolHelp)
                  ? _toolVariants()
                  : _hasVariants
                  // Both are laid out, one is shown: the line keeps the
                  // height of the taller, and the sheet its size.
                  ? IndexedStack(
                      index: _helpIsUrgent ? 1 : 0,
                      children: [_toolVariants(), _helpText(compact)],
                    )
                  : _helpText(compact),
            ),
          ],
        ),
      ],
      if (!_bigSheet && _options.statusLine) ...[
        const SizedBox(height: 8),
        // One line, whatever it says: a sentence that came and went on two
        // lines would change the height left to the sheet at every edit.
        ValueListenableBuilder<String>(
          valueListenable: _statusLine,
          builder: (context, status, _) => Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: studioStatusText),
          ),
        ),
      ],
    ],
  );

  Widget _selectionToolbar({required bool compact, bool showHint = true}) =>
      SelectionToolbar(
        compact: compact,
        showHint: showHint,
        selectedKind: _selectedObject?.kind,
        keepsOwnColours:
            _selectedObject != null && _keepsOwnColours(_selectedObject!),
        clickMoves: _options.holdFree,
        carried: _latch == _Latch.move,
        // Without the layers of the complete interface, « Ordre » does not
        // send an element to another one, nor to the locked layers of a
        // colouring page.
        hasSeveralLayers:
            _options.layers &&
            _document!.layers.where((layer) => !layer.locked).length > 1,
        canBringForward: _canBringForward,
        canSendBackward: _canSendBackward,
        canMoveLayerUp: _canMoveSelectionLayer(1),
        canMoveLayerDown: _canMoveSelectionLayer(-1),
        onOrder: _orderSelection,
        onShrink: _canResizeSelection(_shrinkFactor)
            ? () => _resizeSelection(_shrinkFactor)
            : null,
        onGrow: _canResizeSelection(_growFactor)
            ? () => _resizeSelection(_growFactor)
            : null,
        onEditText: _canEditText ? _editSelectedText : null,
        onDuplicate: _canEditSelection ? _duplicateSelection : null,
        onDelete: _canEditSelection ? _deleteSelection : null,
        onTurn: _canEditSelection ? () => _turnSelection(math.pi / 4) : null,
        onMirror: _canEditSelection ? _mirrorSelection : null,
      );

  /// Whether the choices of the tool stand where its help would: for the
  /// tools of 1.1 that have some.
  bool get _hasVariants => ToolVariants.offers(_tool);

  /// Whether what the help says now matters more than the choices of the
  /// tool: the pipette, a latch, the sheet held.
  bool get _helpIsUrgent => _picking || _latch != null || _panning;

  Widget _helpText(bool compact) => Text(
    _toolHelp,
    style: TextStyle(
      fontSize: compact ? 11 : 13,
      color: studioHelpText,
      fontWeight: FontWeight.w500,
    ),
  );

  String get _toolHelp => forTouch(_mouseToolHelp);

  String get _mouseToolHelp => _picking
      ? tr(
          'Clique sur une couleur de ton dessin pour la reprendre. Échap garde ta couleur.',
        )
      : _latch == _Latch.stroke
      ? tr(
          'Bouge pour dessiner. Clique pour arrêter ton trait. Échap l’enlève.',
        )
      : _latch == _Latch.move
      ? tr('Bouge pour déplacer l’élément. Clique pour le poser.')
      : _latch == _Latch.pan
      ? tr('Bouge pour déplacer la feuille. Clique pour la lâcher.')
      : _panning
      ? (_options.holdFree
            ? tr(
                'Clique pour prendre la feuille, bouge, puis clique pour la lâcher. Les boutons + et − rapprochent ou éloignent ton dessin.',
              )
            : tr(
                'Glisse pour déplacer la feuille. Les boutons + et − rapprochent ou éloignent ton dessin.',
              ))
      : _shapeAnchor != null
      ? switch (_shapeAnchor!.kind) {
          VectorKind.line => tr(
            'Clique maintenant là où ta ligne doit s’arrêter. Échap enlève le petit cercle.',
          ),
          VectorKind.rectangle => tr(
            'Clique maintenant le coin d’en face de ton rectangle. Échap enlève le petit cercle.',
          ),
          VectorKind.ellipse => tr(
            'Clique maintenant plus loin, en biais : ton ovale se placera entre tes deux clics. Échap enlève le petit cercle.',
          ),
          // The shapes of 1.1, drawn in a box like a rectangle.
          _ => tr(
            'Clique maintenant plus loin, en biais : ta forme se placera entre tes deux clics. Échap enlève le petit cercle.',
          ),
        }
      : _holdFreeHelp ?? _tool.help;

  // What « dessiner sans tenir le bouton » changes in the sentence of a tool.
  String? get _holdFreeHelp => !_options.holdFree
      ? null
      : switch (_tool) {
          StudioTool.brush => tr(
            'Clique pour commencer ton trait, bouge, puis clique pour l’arrêter. Tu peux aussi glisser.',
          ),
          StudioTool.select => tr(
            'Clique un élément pour le choisir. Clique-le encore pour le prendre, bouge, puis clique pour le poser.',
          ),
          _ => null,
        };

  /// A finger's event where « Régler le toucher » says the finger meant to
  /// touch; any other pointer as it is.
  T _touchShifted<T extends PointerEvent>(T event) {
    final options = _options;
    if (event.kind != PointerDeviceKind.touch ||
        (options.touchShiftX == 0 && options.touchShiftY == 0)) {
      return event;
    }
    final shift = Matrix4.translationValues(
      options.touchShiftX,
      options.touchShiftY,
      0,
    );
    final transform = event.transform;
    if (transform != null) shift.multiply(transform);
    return event.transformed(shift) as T;
  }

  /// The tool a button of the bar gives: the one of its tools chosen last,
  /// the first at the start; the tool in hand when it is already its own.
  StudioTool _toolOfGroup(ToolGroup group) => _tool.group == group
      ? _tool
      : group == ToolGroup.shapes
      ? _lastShapeTool
      : group.tools.first;

  void _selectGroup(ToolGroup group) => _selectTool(_toolOfGroup(group));

  void _selectTool(StudioTool tool) {
    if (_busy || _confirmationOpen) return;
    if (tool.group == ToolGroup.shapes) _lastShapeTool = tool;
    _settleLatch();
    _cancelDraft();
    setState(() {
      _setSelection(null);
      _tool = tool;
      _panning = false;
      _picking = false;
      _colorTarget = PaintColorTarget.stroke;
    });
    // The pot put down keeps no image of the drawing.
    _pourHintQuiet = null;
    if (tool != StudioTool.fill) _forgetInk();
    _sound(StudioSound.tool);
    _focus.requestFocus();
    // The colours were scrolled to: the choices of the new tool are above.
    if (_phoneRail.hasClients && _phoneRail.offset > 0) {
      _phoneRail.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // Native menu commands can edit the document while the order popup is
  // open: resolve the intent against the current object count.
  void _orderSelection(SelectionOrder order) => switch (order) {
    SelectionOrder.front => _reorderSelection(_document!.count - 1),
    SelectionOrder.back => _reorderSelection(0),
    SelectionOrder.layerUp => _moveSelectionLayer(1),
    SelectionOrder.layerDown => _moveSelectionLayer(-1),
  };

  // The simplest interface leaves the view alone: the sheet stays whole,
  // whatever the wheel, the trackpad or the keyboard ask.
  bool get _viewEnabled =>
      !_busy &&
      !_confirmationOpen &&
      _document != null &&
      _options.viewControls;

  void _changeView(ViewTransform view) {
    _view = view;
    // The shape that follows the pointer between two clicks was drawn for
    // the view of before: it comes back at the next move of the pointer.
    _forgetAnchorEnd();
    _viewRebuild.value++;
  }

  /// A gesture goes on on the sheet — a trait, an element or the view
  /// taken, by a pointer, fingers or a trackpad, with or without a held
  /// button. The decor of a universe then stops where it is, until the
  /// gesture ends: nothing must slow a trait down (Color 1.2).
  bool get _gestureOnSheet =>
      _pointer != null ||
      _panPointer != null ||
      _trackpadPointer != null ||
      _latch != null ||
      _pinching ||
      _fingers.isNotEmpty;

  /// The hand, two fingers or a trackpad are moving the view.
  bool get _viewMoving =>
      _pinching || _panPointer != null || _trackpadPointer != null;

  void _endViewGesture() {
    if (_latch == _Latch.pan) _latch = null;
    _panPointer = null;
    _panLast = null;
    _panStart = null;
    _trackpadPointer = null;
    _trackpadScale = 1;
    // The images followed the view: they are made again where it stopped.
    if (_paintedMoving) _viewRebuild.value++;
    // The room of the sheet changed while a pointer held the view: every
    // end of a gesture comes through here, and the next build fits it.
    if (_viewWaits && mounted) setState(() {});
  }

  void _zoom(double factor) {
    if (!_viewEnabled || _view == null) return;
    _finishStroke();
    _changeView(
      _view!.zoomAt(
        factor,
        anchorX: _view!.viewWidth / 2,
        anchorY: _view!.viewHeight / 2,
      ),
    );
  }

  void _fitView() {
    if (!_viewEnabled || _view == null) return;
    _finishStroke();
    _changeView(_view!.resetToFit());
  }

  void _pointerSignal(PointerSignalEvent event) {
    if (!_viewEnabled ||
        _view == null ||
        _pointer != null ||
        _panPointer != null ||
        _trackpadPointer != null ||
        event is! PointerScrollEvent) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (signal) {
      final scroll = signal as PointerScrollEvent;
      if (HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed) {
        _changeView(
          _view!.zoomAt(
            math.exp((-scroll.scrollDelta.dy * .002).clamp(-4, 4)),
            anchorX: scroll.localPosition.dx,
            anchorY: scroll.localPosition.dy,
          ),
        );
      } else {
        _changeView(
          _view!.panBy(-scroll.scrollDelta.dx, -scroll.scrollDelta.dy),
        );
      }
    });
  }

  // The fingers on the sheet. Two of them zoom and move the view, as on
  // any tablet: the trait the first one had begun is let go, and no finger
  // draws again before all of them have left the screen.
  final _fingers = <int, Offset>{};
  bool _pinching = false;
  double _pinchDistance = 0;
  Offset _pinchFocus = Offset.zero;

  bool _drawsOrHolds(int pointer) =>
      pointer == _pointer || pointer == _panPointer;

  void _startPinch() {
    final points = _fingers.values.take(2).toList();
    _pinchDistance = (points[0] - points[1]).distance;
    _pinchFocus = (points[0] + points[1]) / 2;
  }

  /// A finger that comes down. True when it is no business of the tools:
  /// a second finger, which zooms and moves the view with the first.
  bool _fingerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return false;
    // A hand that rests while a pen draws: none of its fingers is heard,
    // and they make no gesture of two fingers (D-08).
    if (_pointer != null && _isPen(_drawingKind)) return true;
    _fingers[event.pointer] = event.localPosition;
    if (_fingers.length < 2 && !_pinching) return false;
    if (!_pinching && _viewEnabled && _view != null) {
      // What the first finger began is not kept: it was the start of a
      // gesture of two fingers.
      if (_pointer != null) _cancelDraft();
      _pinching = true;
    }
    if (_pinching && _fingers.length >= 2) _startPinch();
    return true;
  }

  bool _fingerMove(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.touch ||
        !_fingers.containsKey(event.pointer)) {
      return false;
    }
    _fingers[event.pointer] = event.localPosition;
    // While a pen draws, the hand that rests is not heard (D-08).
    if (_pointer != null && _isPen(_drawingKind)) return true;
    // Without the view to move, the finger that draws goes on drawing and
    // the others are not heard.
    if (!_pinching) {
      return _fingers.length >= 2 && !_drawsOrHolds(event.pointer);
    }
    if (_fingers.length < 2 || _view == null || !_viewEnabled) return true;
    final points = _fingers.values.take(2).toList();
    final distance = (points[0] - points[1]).distance;
    final focus = (points[0] + points[1]) / 2;
    var view = _view!;
    if (_pinchDistance > 0 && distance > 0) {
      view = view.zoomAt(
        distance / _pinchDistance,
        anchorX: focus.dx,
        anchorY: focus.dy,
      );
    }
    final moved = focus - _pinchFocus;
    _changeView(view.panBy(moved.dx, moved.dy));
    _pinchDistance = distance;
    _pinchFocus = focus;
    return true;
  }

  /// A finger that leaves. True when it was one of a gesture of several.
  bool _fingerUp(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch ||
        !_fingers.containsKey(event.pointer)) {
      return false;
    }
    final several =
        _pinching || (_fingers.length >= 2 && !_drawsOrHolds(event.pointer));
    _fingers.remove(event.pointer);
    if (_fingers.isEmpty && _pinching) {
      _pinching = false;
      _endViewGesture();
    } else if (_pinching && _fingers.length >= 2) {
      _startPinch();
    }
    return several;
  }

  void _trackpadStart(PointerPanZoomStartEvent event) {
    if (!_viewEnabled ||
        _view == null ||
        _pointer != null ||
        _panPointer != null ||
        _trackpadPointer != null) {
      return;
    }
    _trackpadPointer = event.pointer;
    _trackpadScale = 1;
  }

  void _trackpadUpdate(PointerPanZoomUpdateEvent event) {
    if (_trackpadPointer != event.pointer || !_viewEnabled) return;
    var view = _view!;
    if (event.scale.isFinite && event.scale > 0) {
      final anchor = event.localPosition + event.pan - event.panDelta;
      view = view.zoomAt(
        event.scale / _trackpadScale,
        anchorX: anchor.dx,
        anchorY: anchor.dy,
      );
      _trackpadScale = event.scale;
    }
    _changeView(view.panBy(event.panDelta.dx, event.panDelta.dy));
  }

  Widget _documentToolbar() => DocumentToolbar(
    title: _documentTitle,
    caption: _documentCaption,
    viewControls: !_options.viewControls
        ? null
        : ViewControls(
            panning: _panning,
            onZoomOut: _viewEnabled ? () => _zoom(1 / 1.25) : null,
            onZoomIn: _viewEnabled ? () => _zoom(1.25) : null,
            onFit: _viewEnabled ? _fitView : null,
            onTogglePan: _viewEnabled
                ? () {
                    _finishStroke();
                    setState(() => _panning = !_panning);
                    _focus.requestFocus();
                  }
                : null,
            bigSheet: _bigSheet,
            onToggleBigSheet: _viewEnabled ? _toggleBigSheet : null,
          ),
    showFill: _canFill,
    filled: _filled,
    onFilledChanged: _busy ? null : _setFilled,
    activeLayerName: layerName(_document!.activeLayer, _document!.layers),
    onLayers: _busy || _confirmationOpen ? null : _openLayers,
    onUndo: _canUndo ? () => _history(false) : null,
    onRedo: !_busy && _document!.canRedo ? () => _history(true) : null,
    showReplay: true,
    onReplay: _canReplay ? _showReplay : null,
    showTitle: _options.captions,
    showLayers: _options.layers,
  );

  void _setFilled(bool value) => setState(() {
    // The chosen shape gains or loses its inside at once.
    if (_selectedObject != null &&
        !_styleSelection(
          changeFill: true,
          fillRgb: value ? _fillColor : null,
        )) {
      return;
    }
    _filled = value;
  });

  /// The stage of the sheet: where it is drawn and touched. [galets]: in
  /// the studio of the pebbles, where the decor and its names are laid
  /// behind and over it, on the whole window, and nothing is written
  /// around the sheet.
  Widget _canvas({GaletsLayout? galets}) => LayoutBuilder(
    builder: (context, constraints) {
      // A telephone gives the sheet all its room: no name around it.
      final roomForCaptions =
          _options.captions &&
          constraints.maxHeight >= 160 &&
          !_phoneLayout(context);
      // The pebbles keep that room around the sheet, and write nothing
      // in it.
      final showCaptions = roomForCaptions && galets == null;
      final sheetPadding = roomForCaptions ? 28.0 : 8.0;
      // While a pointer is down the view keeps the size it had at the press.
      // A control that appears under the sheet, a sentence that wraps or a
      // window that is resized would otherwise slide the sheet under the
      // pointer, and the element or the trait with it. The view catches up
      // at the first build after the gesture.
      // The same between the two clicks of a shape: the little circle must
      // stay where the first click was, though the sentence of help changes.
      final held =
          _pointer != null ||
          _panPointer != null ||
          _trackpadPointer != null ||
          _shapeAnchor != null;
      if (_view == null) {
        _view = ViewTransform.fit(
          viewWidth: constraints.maxWidth,
          viewHeight: constraints.maxHeight,
          padding: sheetPadding,
          documentWidth: _document!.width.toDouble(),
          documentHeight: _document!.height.toDouble(),
        );
      } else if (!held) {
        _view = _view!.resize(
          viewWidth: constraints.maxWidth,
          viewHeight: constraints.maxHeight,
          padding: sheetPadding,
        );
        _viewWaits = false;
      } else if (_view!.viewWidth != constraints.maxWidth ||
          _view!.viewHeight != constraints.maxHeight) {
        // The end of the gesture asks for the build that catches up.
        _viewWaits = true;
      }
      return ValueListenableBuilder<int>(
        valueListenable: _viewRebuild,
        builder: (context, _, child) {
          final viewport = DocumentViewport.fromTransform(_view!);
          // What the pointer of the keyboard moves on (Color 1.1).
          _keyViewport = viewport;
          _keySheetSize = constraints.biggest;
          // The tool, the colour, a size or the view may have changed: the
          // pointer and the preview over the sheet follow (Color 1.2).
          _refreshHint();
          // The decor of the universe, around the sheet and under it
          // (Color 1.2): where the sheet lies when the whole of it is
          // shown says how large the decor may be.
          final look = studioLook.value;
          // None on a tablet or a telephone, whatever its size (the owner,
          // 12 November 2026): the sheet takes the screen there, and the
          // decor is looked at on the whole screen instead.
          final worn = touchFirst || galets != null ? null : _universe.decor;
          final rest = ViewTransform.fit(
            viewWidth: constraints.maxWidth,
            viewHeight: constraints.maxHeight,
            padding: sheetPadding,
            documentWidth: _document!.width.toDouble(),
            documentHeight: _document!.height.toDouble(),
          );
          final sheetAtRest = Rect.fromLTWH(
            rest.left,
            rest.top,
            rest.width,
            rest.height,
          );
          final layout = worn == null
              ? null
              : DecorLayout(
                  frame: constraints.biggest,
                  sheetAtRest: sheetAtRest,
                  decor: worn.size,
                  decorSheet: worn.sheet,
                );
          // And none where its pieces would be too small to be looked at:
          // a ground alone has no interest. The frame is then plain, in
          // the colour of the universe.
          final decor = layout != null && layout.pieces ? worn : null;
          final painting = decor == null || layout == null
              ? null
              : DecorPainting(decor, layout);
          // The studio of the pebbles lays the decor itself.
          if (galets == null) _decorPainting = painting;
          final corners = BorderRadius.circular(
            galets == null ? look.stageRadius : 0,
          );
          // The captions of the sheet stand in the corners of its frame.
          // Over a decor they would cover what stands there — the knob of
          // the curtain rod, the pencils on the desk — and a child must
          // see everything: they stand along the sheet at rest instead,
          // above its top left corner and under its bottom corners, in the
          // margin that the sheet keeps for them. Nothing of a decor that
          // has a name lies there.
          final onDecor = painting != null;
          final captionTop = onDecor
              ? math.max(4.0, sheetAtRest.top - 23)
              : 10.0;
          final captionBottom = onDecor
              ? math.max(4.0, constraints.maxHeight - sheetAtRest.bottom - 23)
              : 9.0;
          final captionLeft = onDecor ? math.max(4.0, sheetAtRest.left) : 16.0;
          final captionRight = onDecor
              ? math.max(4.0, constraints.maxWidth - sheetAtRest.right)
              : 16.0;
          // A caption on a decor is written on a pill of the surface.
          Widget caption(Widget text) => painting == null
              ? text
              : DecorCaption(
                  color: studioSurface.withValues(alpha: .94),
                  child: text,
                );
          return DecoratedBox(
            decoration: BoxDecoration(
              // A decor fills the frame: no backdrop is painted under it.
              // The pebbles have the whole window behind the stage.
              color: decor == null && galets == null
                  ? studioSheetBackdrop
                  : null,
              borderRadius: corners,
            ),
            child: Stack(
              children: [
                // Among the pebbles the sheet floats: its shadow, wherever
                // the view shows it.
                if (galets != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: GaletSheetShadow(
                          Rect.fromLTWH(
                            viewport.left,
                            viewport.top,
                            viewport.width,
                            viewport.height,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (decor != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: RepaintBoundary(
                          child: DecorView(
                            decor: decor,
                            sheetAtRest: sheetAtRest,
                            motion: _options.decorMotion,
                            now: widget.clock,
                            resting: () => _gestureOnSheet,
                            corners: look.stageRadius,
                            behind: studioBackground,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Semantics(
                    label: forTouch(
                      trf(
                        'Feuille de dessin {0} par {1} unités. Souris ou stylet.',
                        [_document!.width, _document!.height],
                      ),
                    ),
                    child: _StageMouseRegion(
                      // The interface draws the pointer of the tool itself,
                      // « la pointe » (Color 1.2): the pointer of the
                      // system shows only where it says more — the hand
                      // that moves the sheet, the pipette, and beside the
                      // sheet over a decor.
                      held: _panning || _spaceHeld
                          ? SystemMouseCursors.grab
                          : _picking
                          ? SystemMouseCursors.precise
                          : null,
                      beside: _stageCursor,
                      onEnter: (event) {
                        _hintFollows(event);
                        _refreshHint();
                      },
                      onExit: (_) {
                        _forgetAnchorEnd();
                        // A gesture without a held button ends where the
                        // pointer leaves the frame of the sheet.
                        _endLatch();
                        _hintLeft();
                        _asking.lift();
                      },
                      child: Listener(
                        key: const Key('drawingSurface'),
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (raw) {
                          final event = _touchShifted(raw);
                          _decorDown(event);
                          if (!_fingerDown(event)) {
                            _hintFollows(event);
                            _pointerDown(event, viewport);
                          }
                          _refreshHint();
                        },
                        onPointerMove: (raw) {
                          final event = _touchShifted(raw);
                          _asking.move(event.localPosition + _stageOrigin);
                          if (!_fingerMove(event)) {
                            _hintFollows(event);
                            _pointerMove(event, viewport);
                          }
                          _refreshHint();
                        },
                        onPointerHover: (event) {
                          _hintFollows(event);
                          _pointerHover(event, viewport);
                          _refreshHint();
                        },
                        onPointerSignal: _pointerSignal,
                        onPointerPanZoomStart: _trackpadStart,
                        onPointerPanZoomUpdate: _trackpadUpdate,
                        onPointerPanZoomEnd: (event) {
                          if (_trackpadPointer == event.pointer) {
                            _endViewGesture();
                          }
                        },
                        onPointerUp: (raw) {
                          final event = _touchShifted(raw);
                          _asking.lift();
                          _pointerUp(event, viewport);
                          _hintLifted(event);
                          _refreshHint();
                        },
                        onPointerCancel: (event) {
                          _asking.lift();
                          _hintLifted(event);
                          if (!_fingerUp(event)) {
                            if (_panPointer == event.pointer) {
                              _endViewGesture();
                            }
                            if (_pointer == event.pointer) _cancelDraft();
                          }
                          _refreshHint();
                        },
                        // The picture of the sheet, as the reference
                        // images of test/reference_images_test.dart take it.
                        child: RepaintBoundary(
                          key: const Key('sheetPicture'),
                          child: CustomPaint(
                            painter: DocumentPainter(
                              viewport: viewport,
                              paperRgb: _document!.paperRgb,
                              background: _backgroundImage,
                              strokes: _strokes,
                              paintOrder: _document!.paintOrder,
                              draft: _drafting,
                              repaint: _canvasRepaint,
                              revision: _revision,
                              selectedIndex: _selectedIndex,
                              selectionBounds: _selectedPaintBounds,
                              selectionOffset: _selectionOffset,
                              // What is being drawn lies on the active layer,
                              // under the layers above it: on a colouring
                              // page, under the lines of the page, as it will
                              // once the pointer is released.
                              draftDepth: draftDepthOf(
                                strokes: _strokes,
                                paintOrder: _document!.paintOrder,
                                layers: _document!.layers,
                                activeLayer: _document!.activeLayer,
                              ),
                              anchor: _shapeAnchor,
                              anchorDrawn: _draftFromAnchor,
                              anchorRgb: _color,
                              anchorWidth: _width,
                              anchorFillRgb: _filled && _tool.drawsFillableShape
                                  ? _fillColor
                                  : null,
                              anchorShape: _newShape,
                              images: _sheetImages,
                              pixelRatio: MediaQuery.devicePixelRatioOf(
                                context,
                              ),
                              viewMoving: _paintedMoving = _viewMoving,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showCaptions)
                  Positioned(
                    top: captionTop,
                    left: captionLeft,
                    child: IgnorePointer(
                      child: caption(
                        Text(
                          tr('MA FEUILLE'),
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: studioSheetTitle,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showCaptions)
                  Positioned(
                    bottom: captionBottom,
                    left: captionLeft,
                    child: IgnorePointer(
                      child: caption(
                        Text(
                          trf('{0} × {1} unités', [
                            _document!.width,
                            _document!.height,
                          ]),
                          style: TextStyle(
                            fontSize: 10,
                            color: studioSheetCaption,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showCaptions)
                  Positioned(
                    bottom: captionBottom,
                    right: captionRight,
                    child: IgnorePointer(
                      child: caption(
                        Text(
                          _view!.isFit
                              ? tr('Toute la feuille')
                              : '${(viewport.scale * 100).round()} %',
                          style: TextStyle(
                            fontSize: 10,
                            color: studioSheetCaption,
                          ),
                        ),
                      ),
                    ),
                  ),
                // « La pointe » of the tool, and what a press would do
                // where it is (Color 1.2): painted apart from the sheet,
                // which a pointer that moves never paints again.
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const Key('sheetHint'),
                        painter: SheetHintPainter(
                          viewport: viewport,
                          hint: _hint,
                        ),
                      ),
                    ),
                  ),
                ),
                // The names of the decor: what a screen reader may ask
                // about, and the card of the thing that was asked.
                if (painting != null && _namesOffered)
                  Positioned.fill(
                    child: ValueListenableBuilder<DecorName?>(
                      valueListenable: _shownName,
                      builder: (context, shown, _) => DecorNameLayer(
                        painting: painting,
                        sheetAtRest: sheetAtRest,
                        shown: shown,
                        onAsk: _showName,
                        onClose: _closeName,
                      ),
                    ),
                  ),
                // The line around the frame, over the decor.
                if (look.stageBorder > 0 && galets == null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: corners,
                          border: Border.all(
                            color: studioLine,
                            width: look.stageBorder,
                          ),
                        ),
                      ),
                    ),
                  ),
                // The pointer of the keyboard or the gamepad (Color 1.1).
                if (_options.keyboardPointer && _keyPointerAt != null)
                  Positioned(
                    left: _keyPointerAt!.dx - 14,
                    top: _keyPointerAt!.dy - 14,
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const Key('keyPointer'),
                        size: const Size.square(28),
                        painter: KeyPointerPainter(pressed: _keyDown),
                      ),
                    ),
                  ),
                // While the pot reads the drawing: nothing to see, it is quick;
                // the tests wait for it to go.
                if (_pouring)
                  const Positioned(
                    left: 0,
                    top: 0,
                    child: SizedBox.shrink(key: Key('pouring')),
                  ),
                if (_busyLabel != null)
                  Positioned.fill(
                    child: Semantics(
                      liveRegion: true,
                      child: ColoredBox(
                        color: const Color(0xeafffefa),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Flexible(child: Text(_busyLabel!)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    },
  );

  void _colorDialogChanged(bool open) {
    if (open) _finishStroke();
    if (mounted) setState(() => _confirmationOpen = open);
  }

  /// The colours and the size of what is drawn. [rail]: in the column of a
  /// telephone, which already gives them their surface.
  Widget _palettePanel(bool narrow, {bool compact = false, bool rail = false}) {
    final palette = _palette(narrow, compact: compact, rail: rail);
    if (rail) return palette;
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 16),
      decoration: studioPanel(radius: 18),
      child: palette,
    );
  }

  Widget _palette(bool narrow, {required bool compact, required bool rail}) =>
      ColorPalette(
        rail: rail,
        selectedRgb: _canFill && _colorTarget == PaintColorTarget.fill
            ? _fillColor
            : _color,
        canFill: _canFill,
        target: _colorTarget,
        compact: compact,
        history: _recentColors,
        onDialogVisibilityChanged: _colorDialogChanged,
        onTargetChanged: (target) => setState(() => _colorTarget = target),
        onColorSelected: _busy || _confirmationOpen
            ? null
            : (rgb) {
                if (!mounted) return;
                setState(() {
                  // A colour chosen in the palette is the choice: the pipette
                  // that was waiting has nothing left to fetch.
                  _picking = false;
                  _chooseColor(rgb);
                });
                _sound(StudioSound.colour);
              },
        onPickFromDrawing: _options.simpleControls ? null : _togglePicking,
        picking: _picking,
        simple: _options.simpleControls,
        trailingControl: rail ? _railControls(narrow) : _sizeOnly(narrow),
      );

  /// The rail of a telephone has no line of help: the choices of the tool
  /// stand there above the size, in a rail that scrolls.
  Widget? _railControls(bool narrow) {
    final size = _sizeOnly(narrow, rail: true);
    if (_choosing || !_hasVariants) return size;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolVariants(),
        if (size != null) ...[const SizedBox(height: 8), size],
      ],
    );
  }

  StampArt? get _currentStamp {
    try {
      return StampCatalog.instance[_stampId];
    } catch (_) {
      // The catalogue comes from the core; the studio stays usable without it.
      return null;
    }
  }

  /// The choices of a tool of 1.1, where the sentence of help stands: the
  /// tip of the brush, the magic, the shape. They take its place as the
  /// actions of a chosen element take it, so that the sheet keeps its size.
  Widget _toolVariants({bool tiles = false}) {
    final enabled = !_busy && !_confirmationOpen;
    return ToolVariants(
      key: const Key('toolVariants'),
      tiles: tiles,
      tool: _tool,
      brush: _brushTool,
      magic: _magic,
      shape: _newShape,
      rgb: _color,
      // In a panel of the pebbles, a choice made puts the panel away.
      onBrush: enabled
          ? (tip) {
              setState(() {
                _brushTool = tip;
                if (tiles) _galetPanel = null;
              });
              _sound(StudioSound.tool);
            }
          : null,
      onMagic: enabled
          ? (magic) {
              setState(() {
                _magic = magic;
                if (tiles) _galetPanel = null;
              });
              _sound(StudioSound.tool);
            }
          : null,
      onShape: enabled
          ? (shape) {
              setState(() {
                _newShape = shape;
                if (tiles) _galetPanel = null;
              });
              if (_tool == StudioTool.shapes) {
                _sound(StudioSound.tool);
              } else {
                _selectTool(StudioTool.shapes);
              }
            }
          : null,
      onTool: !enabled
          ? null
          : tiles
          ? (tool) {
              setState(() => _galetPanel = null);
              _selectTool(tool);
            }
          : _selectTool,
      pour: _pourKind,
      secondRgb: _previousColor,
      stamp: _tool == StudioTool.stamp ? _currentStamp : null,
      stampLook: _stampLook,
      onTurnStamp: enabled
          ? () {
              setState(() => _stampEighths = (_stampEighths + 1) % 8);
              _sound(StudioSound.tool);
            }
          : null,
      onMirrorStamp: enabled
          ? () {
              setState(() => _stampMirrored = !_stampMirrored);
              _sound(StudioSound.tool);
            }
          : null,
      onPour: enabled
          ? (kind) {
              setState(() {
                _pourKind = kind;
                if (tiles) _galetPanel = null;
              });
              _sound(StudioSound.tool);
            }
          : null,
    );
  }

  /// One place answers « how big? »: the outline of a trait or shape, the
  /// letters of a text, or a stamp placed with a click.
  Widget? _sizeOnly(bool narrow, {bool rail = false}) {
    // The paint pot and the eraser have nothing to size.
    if (_tool == StudioTool.fill || _tool == StudioTool.eraser) return null;
    final enabled = !_busy && !_confirmationOpen;
    final kind = _styledKind;
    if (kind == VectorKind.text || kind == VectorKind.stamp) {
      // A chosen text changes size with its words (Modifier); a chosen stamp
      // keeps the size it was given.
      if (_choosing) return null;
      final forStamp = kind == VectorKind.stamp;
      return PlacedSizeControl(
        size: forStamp ? _stampSize : _textSize,
        what: forStamp ? tr('du tampon') : tr('du texte'),
        onSizeChanged: enabled
            ? (size) => setState(() {
                if (forStamp) {
                  _stampSize = size;
                } else {
                  _textSize = size;
                }
              })
            : null,
        forStamp: forStamp,
        stamp: forStamp ? _currentStamp : null,
        stampRgb: _color,
        onChooseStamp: enabled ? _chooseStamp : null,
        rail: rail,
      );
    }
    if (_options.simpleControls) {
      // Three sizes to click instead of a slider to move.
      return SizeChoiceControl(
        keyPrefix: 'brush',
        wrap: rail,
        value: _width <= 9
            ? ObjectSize.small
            : _width <= 21
            ? ObjectSize.medium
            : ObjectSize.large,
        what: tr('du trait'),
        onChanged: enabled
            ? (size) => setState(
                () => _width = switch (size) {
                  ObjectSize.small => 6,
                  ObjectSize.medium => 14,
                  ObjectSize.large => 30,
                },
              )
            : null,
      );
    }
    return OutlineWidthControl(
      rail: rail,
      value: _width,
      shown: _selectedObject != null && !_selectionWidthMoving
          ? _selectedObject!.width
          : _width,
      narrow: narrow,
      onChanged: !enabled
          ? null
          : (value) => setState(() {
              _width = value;
              if (_selectedIndex != null) _selectionWidthMoving = true;
            }),
      // A slide of the slider is one change of the chosen element, made
      // when the hand leaves it: one step for Annuler, not one per notch.
      onChangeEnd: !enabled
          ? null
          : () {
              if (!_selectionWidthMoving) return;
              setState(() {
                _selectionWidthMoving = false;
                final chosen = _selectedObject;
                if (chosen != null &&
                    !chosen.kind.isBoxObject &&
                    !_styleSelection(width: _width)) {
                  // The element could not take it — a dialog opened during
                  // the slide: the slider goes back to what the element has.
                  _width = chosen.width.clamp(2.0, 48.0).toDouble();
                }
              });
            },
    );
  }
}

/// What the album needs to draw the card of a save, captured with its bytes.
class _GalleryCard {
  _GalleryCard(
    this.elements, {
    required this.width,
    required this.height,
    required this.count,
    required this.paperRgb,
    required this.background,
  });
  final List<RenderedElement> elements;
  final int width;
  final int height;
  final int count;
  final int paperRgb;

  /// An owned handle of the image background, released by [dispose].
  ui.Image? background;

  void dispose() {
    background?.dispose();
    background = null;
  }
}

/// The frame of the sheet for a mouse: its pointer is [held] while the
/// studio holds one — the hand, the pipette — and otherwise the one of
/// [beside], which changes when the pointer goes from the sheet to the
/// decor beside it. Only this region is built again then, not what it
/// holds.
class _StageMouseRegion extends StatelessWidget {
  const _StageMouseRegion({
    required this.held,
    required this.beside,
    required this.onEnter,
    required this.onExit,
    required this.child,
  });
  final MouseCursor? held;
  final ValueListenable<MouseCursor> beside;
  final PointerEnterEventListener onEnter;
  final PointerExitEventListener onExit;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MouseCursor>(
    valueListenable: beside,
    child: child,
    builder: (context, cursor, child) => MouseRegion(
      cursor: held ?? cursor,
      onEnter: onEnter,
      onExit: onExit,
      child: child,
    ),
  );
}
