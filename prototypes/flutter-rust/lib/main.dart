// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;
import 'dart:ui' as ui show Image;

import 'package:path_provider/path_provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'document_exports.dart';
import 'document_save_state.dart';
import 'png_export.dart';
import 'print_render.dart';
import 'selection_geometry.dart';
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
  runApp(EduPaintApp(options: options, sounds: SystemSounds()));
}

class EduPaintApp extends StatelessWidget {
  const EduPaintApp({
    super.key,
    this.files = const StudioFiles(),
    this.recoveryStorage,
    this.gallery,
    this.printer = printWithSystemPanel,
    this.options,
    this.sounds = const SilentSounds(),
  });
  final StudioFiles files;
  final ProjectStorage? recoveryStorage;

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
  Widget build(BuildContext context) => MaterialApp(
    title: 'Color',
    // French is the only language currently provided by the app.
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('fr')],
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: studioInk,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: studioLine),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
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
  });
  final StudioFiles files;
  final ProjectStorage? recoveryStorage;
  final GalleryStorage? gallery;
  final StudioPrinter printer;
  final StudioOptionsStore? options;
  final SoundPlayer sounds;
  @override
  State<DrawingStudio> createState() => _DrawingStudioState();
}

enum _HistoryChange { edit, undo, redo }

/// What goes on with the pointer while no button is held, between the click
/// that began it and the click that ends it: a trait, the move of the chosen
/// element, or the sheet under the hand.
enum _Latch { stroke, move, pan }

class _DrawingStudioState extends State<DrawingStudio> {
  RustDocument? _document;
  ui.Image? _backgroundImage;
  StudioProblem? _startupError;
  final _focus = FocusNode(debugLabel: 'Atelier Color');
  final _canvasRepaint = ValueNotifier<int>(0);
  final _viewRebuild = ValueNotifier<int>(0);
  final _recentColors = RecentPaintColors();
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
  List<DocumentPoint> _draft = [];
  Path? _draftPath;
  DocumentPoint? _draftRawEnd;
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
  VectorKind _draftKind = VectorKind.stroke;
  // The brush is heard when it touches the sheet, then again while it
  // travels: when it was last heard, and how far it went since.
  static const _brushHeardEvery = Duration(milliseconds: 340);
  Duration? _brushHeardAt;
  double _brushTravel = 0;
  Offset? _brushLastPosition;
  // Where the pointer went down with the text tool; the dialog opens on release.
  DocumentPoint? _textAnchor;
  ObjectSize _textSize = ObjectSize.medium;
  ObjectSize _stampSize = ObjectSize.medium;
  int _stampId = 0;
  int _draftStamp = 0;
  bool _filled = false;
  int? _draftFillRgb;
  int _color = 0x477fb2;
  int _draftColor = 0x477fb2;
  double _width = 12;
  double _draftWidth = 12;
  int _revision = 0;
  int _documentRevision = 0;
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
  String _status = 'Recherche d’un dessin à reprendre…';
  // The options of the adult; a studio that was given none keeps its own,
  // with the defaults, for as long as it lives.
  late final StudioOptionsStore _optionsStore =
      widget.options ?? StudioOptionsStore.memory();
  StudioOptions get _options => _optionsStore.value;

  @override
  void initState() {
    super.initState();
    _recoveryScheduler = RecoveryScheduler(
      writeLatest: _writeRecovery,
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
        message: 'Color n’a pas pu démarrer.',
      );
    }
    _optionsStore.addListener(_optionsChanged);
    if (_options.simpleControls) _fitSimpleControls();
    if (!_options.tools.contains(_tool)) _tool = StudioTool.brush;
    _lifecycle = AppLifecycleListener(
      onExitRequested: _requestExit,
      onHide: _keepWhenHidden,
      onPause: _keepWhenHidden,
    );
    installNativeExitHandler(() => _requestExit(finalNativeDecision: true));
    unawaited(installNativeDiagnostics());
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeRecovery());
  }

  @override
  void dispose() {
    _optionsStore.removeListener(_optionsChanged);
    if (widget.options == null) _optionsStore.dispose();
    _bounceTimer?.cancel();
    _savedTimer?.cancel();
    _phoneRail.dispose();
    _recoveryScheduler.dispose();
    clearNativeExitHandler();
    clearNativeDiagnostics();
    _lifecycle.dispose();
    _focus.dispose();
    _canvasRepaint.dispose();
    _viewRebuild.dispose();
    _recentColors.dispose();
    _selectionOffset.dispose();
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
    }
    final rendered = {for (final element in _strokes) element.data: element};
    _strokes = List.unmodifiable(
      _document!.strokes.map((data) => rendered[data] ?? RenderedElement(data)),
    );
    _revision++;
    _status = _dirty
        ? 'Modifications non enregistrées · préparation de la copie de récupération…'
        : (_currentPath == null
              ? 'Nouvelle feuille · récupération locale prête.'
              : 'Projet enregistré : $_currentPath');
    // A transition to clean must reconcile an older recovery in the same queue.
    _scheduleRecovery();
  }

  void _error(
    Object error, {
    String message = 'Cette action n’a pas pu être terminée.',
  }) {
    if (!mounted) return;
    _showProblem(StudioProblem.fromError(error, message: message));
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
                  child: const Text('Détails'),
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
          : _boundsForObject(
              _selectedIndex!,
              object,
            ).inflate(object.outlineRadius);
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

  /// The eraser removes the element it touches: one step for Annuler each.
  /// What an erased element was covering is uncovered, not erased: a click
  /// on a star keeps the sky behind it, and a glide that removes a large
  /// shape leaves what appears from under it. Those elements are out of the
  /// eraser's reach until the gesture ends: the child points at them with
  /// the next one. The page of a colouring page is never in its reach.
  void _eraseAt(DocumentPoint point, double scale) {
    final index = _objectAt(point, scale);
    if (index == null) return;
    final document = _document!;
    final object = document.strokes[index];
    if (_eraserShield.contains(object)) return;
    // Everything painted behind it that its outline or its box overlaps.
    final area = _boundsForObject(index, object).inflate(object.outlineRadius);
    final covered = <StrokeData>[];
    for (final other in document.unlockedPaintOrder) {
      if (other == index) break;
      final behind = document.strokes[other];
      if (_boundsForObject(
        other,
        behind,
      ).inflate(behind.outlineRadius).overlaps(area)) {
        covered.add(behind);
      }
    }
    try {
      if (document.removeObject(index)) {
        _eraserShield.addAll(covered);
        setState(_refreshAfterMutation);
        _sound(StudioSound.erase);
        // Also what is now under the pointer, however it got there.
        final uncovered = _objectAt(point, scale);
        if (uncovered != null) _eraserShield.add(document.strokes[uncovered]);
      }
    } catch (error) {
      _error(error);
    }
  }

  static const _imageCoversSheet =
      'Une image couvre toute la feuille. Touche un élément pour le colorier.';
  static const _stampKeepsColours = 'Ce tampon garde ses couleurs.';

  /// The paint pot gives the current colour to what it touches: the inside
  /// of a rectangle, an oval or a contour, the colour of any other element,
  /// or the sheet itself where nothing is drawn.
  ///
  /// On a colouring page it sees through the lines of the page, which keep
  /// their colour: a click on or near a line colours the zone under it. A
  /// zone receives the colour of its inside and nothing else, the one change
  /// that its locked layer accepts.
  void _fillAt(DocumentPoint point, double scale) {
    final document = _document!;
    // What the pot can colour, bottom first: everything seen but the lines
    // of a page, whose locked layer keeps them as they are.
    final order = document.lockedLayers.isEmpty
        ? document.paintOrder
        : [
            for (final index in document.paintOrder)
              if (!document.isLockedObject(index) ||
                  document.strokes[index].fillRgb != null)
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
    final before = document.undoCount;
    try {
      if (index == null) {
        if (_backgroundImage != null) {
          _showProblem(StudioProblem.notice(_imageCoversSheet));
          return;
        }
        document.setPaperColor(_color);
      } else {
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
            if (behind.layer == object.layer &&
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
        document.setObjectStyle(
          target,
          rgb: fills ? object.rgb : _color,
          width: object.width,
          fillRgb: fills ? _color : null,
        );
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

  static const _nothingToPick =
      'Clique sur un élément de ton dessin pour reprendre sa couleur.';

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
              ? 'Cet élément ne peut pas être plus grand sur cette feuille.'
              : 'Cet élément ne peut pas être plus petit.',
        ),
      );
    } catch (error) {
      _error(error);
    }
    _focus.requestFocus();
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
      _fillAt(point, viewport.scale);
      return;
    }
    if (_choosing) {
      final found = _objectAt(point, viewport.scale);
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
    setState(() {
      _pointer = event.pointer;
      _draftKind = kind;
      _draftStamp = _stampId;
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
      _draftPath = Path()..moveTo(_draft.first.x, _draft.first.y);
      _revision++;
    });
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
        _extendDraftTo(event.localPosition, viewport, at: event.timeStamp);
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
  }) {
    final raw = viewport.point(position.dx, position.dy);
    _draftRawEnd = raw;
    if (_draftKind == VectorKind.stroke) {
      if (_draft.length >= 100000) return;
      final previous = _draft.last;
      if (raw.x == previous.x && raw.y == previous.y) return;
      _draft.add(raw);
      _draftPath!.lineTo(raw.x, raw.y);
      _hearBrush(position, at);
    } else {
      _draft[1] = _shapeEndFrom(_draft.first, raw, _draftKind);
    }
    _revision++;
    // Pointer samples repaint the page without rebuilding the toolbars.
    _canvasRepaint.value++;
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
      // A quick hand leaves few samples: walk the whole way between two of
      // them, so that a thin line in between is not jumped over.
      final from = _eraserLast ?? event.localPosition;
      final to = event.localPosition;
      _eraserLast = to;
      final steps = ((to - from).distance / 5).ceil().clamp(1, 400);
      for (var step = 1; step <= steps; step++) {
        final position = Offset.lerp(from, to, step / steps)!;
        // Outside the sheet nothing is touched: positions are not pulled
        // back onto its edge, which would erase what lies there.
        if (viewport.contains(position.dx, position.dy)) {
          _eraseAt(viewport.point(position.dx, position.dy), viewport.scale);
        }
      }
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
    _extendDraftTo(event.localPosition, viewport, at: event.timeStamp);
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
    if (_erasing) {
      // Every erased element is already its own finished step.
      _erasing = false;
      _eraserLast = null;
      _eraserShield.clear();
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
    // A press that stayed where it began is a click, told on the screen.
    final clicked =
        released && _pressTravel < clickTravel(touch: _pressByTouch);
    _draft = [];
    _draftPath = null;
    _draftRawEnd = null;
    _pointer = null;
    _draftFromAnchor = false;
    _pressPosition = null;
    try {
      // One FFI call for the completed gesture; pressure is not handled yet.
      if (_draftKind == VectorKind.stroke) {
        // The brush was heard while it travelled: nothing when it lifts.
        _document!.addStroke(points, rgb: _draftColor, width: _draftWidth);
      } else if (_draftKind == VectorKind.stamp) {
        final box = _stampBox(points.first, points.last);
        _document!.addStamp(
          box.first,
          box.second,
          stamp: _draftStamp,
          rgb: _draftColor,
        );
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
        _document!.addShape(
          _draftKind,
          points.first,
          points.last,
          rgb: _draftColor,
          width: _draftWidth,
          fillRgb: _draftFillRgb,
        );
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
  PlacedText? _placeText(String text, double size, DocumentPoint anchor) {
    final document = _document!;
    return placeText(
      text,
      size: size,
      anchor: anchor,
      pageWidth: document.width.toDouble(),
      pageHeight: document.height.toDouble(),
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
        screenKeyboard: _options.screenKeyboard,
        problem: (text, choice) =>
            _placeText(text, sizeOf(choice), anchor) == null
            ? _textTooLarge
            : null,
      ),
    );
    if (entry == null || !mounted || !identical(document, _document)) return;
    _textSize = entry.size;
    try {
      final size = sizeOf(entry.size);
      final placed = _placeText(entry.text, size, anchor);
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
      );
      setState(_refreshAfterMutation);
      _sound(StudioSound.text);
    } catch (error) {
      _error(error, message: 'Ce texte n’a pas pu être posé.');
    }
  }

  static const _textTooLarge =
      'Ce texte est trop grand pour la feuille. Choisis une taille plus petite ou un texte plus court.';

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
        editing: true,
        screenKeyboard: _options.screenKeyboard,
        problem: (text, choice) =>
            _placeText(text, sizeOf(choice), anchor) == null
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
      final placed = _placeText(entry.text, size, anchor);
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
      );
      setState(() {
        if (changed) _refreshAfterMutation();
        _reselect(index);
      });
    } catch (error) {
      _error(error, message: 'Ce texte n’a pas pu être changé.');
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
      _error(error, message: 'Les tampons ne sont pas disponibles.');
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

  static const _allLayersHidden =
      'Tous les calques sont cachés. Ouvre les calques pour en montrer un.';
  // The same in an interface that does not show the layers.
  static const _allLayersHiddenElsewhere =
      'Tous les calques de ce dessin sont cachés. Un adulte peut en montrer un dans l’interface complète (Options).';

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
      _error(error, message: 'Ce changement de calque n’a pas pu être fait.');
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
    _draftPath = null;
    _draftRawEnd = null;
    _pointer = null;
    _shapeAnchor = null;
    _draftFromAnchor = false;
    _pressPosition = null;
    _erasing = false;
    _eraserLast = null;
    _eraserShield.clear();
    _textAnchor = null;
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
    final tools = _options.tools;
    return number >= 0 && number < tools.length ? tools[number] : null;
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

  KeyEventResult _shapeModifiers(FocusNode node, KeyEvent event) {
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
        final support = (await getApplicationSupportDirectory()).path;
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
              status: 'Dessin récupéré · enregistre-le pour choisir son emplacement.',
            );
            prepared.takeDocument();
            recoveredBackground = null;
          } else {
            await _clearRecovery();
            if (mounted) {
              setState(() {
                _status = 'Nouvelle feuille · récupération locale prête.';
              });
            }
          }
        } finally {
          recoveredBackground?.dispose();
          prepared.dispose();
        }
      } else if (mounted) {
        setState(() {
          _status = 'Nouvelle feuille · récupération locale prête.';
        });
      }
    } catch (error) {
      // Preserve an unreadable recovery file: do not overwrite it with a blank drawing.
      _storage = null;
      if (mounted) {
        setState(() {
          _status = 'Récupération indisponible · enregistre régulièrement ton dessin.';
        });
        _error(
          error,
          message: error is NewerProjectException
              ? 'La copie de récupération vient d’une version plus récente de Color : elle est conservée telle quelle. Enregistre régulièrement ton dessin.'
              : 'La récupération n’est pas disponible pour le moment. Enregistre régulièrement ton dessin.',
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

  void _scheduleRecovery() {
    if (_storage == null) {
      if (_dirty) {
        _status = 'Modifications non enregistrées · récupération locale indisponible.';
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
        setState(() {
          _status = 'Copie de récupération à jour · projet à enregistrer.';
        });
      } else {
        // Keep the completed older snapshot, then coalesce the latest edits.
        // The scheduler never keeps an encoded snapshot for every pointer event.
        _scheduleRecovery();
      }
    } catch (error) {
      if (belongsToCurrentDocument()) {
        setState(() {
          _status = _dirty
              ? 'Récupération non mise à jour · enregistre ton dessin.'
              : 'Ancienne copie de récupération encore présente.';
        });
        if (!_recoveryWarningShown) {
          _recoveryWarningShown = true;
          _error(
            error,
            message: _dirty
                ? 'Le dessin reste ouvert, mais sa copie de récupération n’a pas pu être écrite.'
                : 'L’ancienne copie de récupération n’a pas pu être retirée. Le dessin actuel reste ouvert.',
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
    if (_dirty) _scheduleRecovery();
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
      _error(error, message: 'Color n’a pas pu terminer la fermeture.');
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
    } catch (error) {
      _error(error, message: 'La nouvelle feuille n’a pas pu être préparée.');
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
    String? status,
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
      _revision++;
      _status =
          status ??
          (path == null
              ? 'Nouvelle feuille · récupération locale prête.'
              : 'Projet ouvert : $path');
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
      setState(() => _busyLabel = 'Préparation de ton image…');
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
        status: 'Ton image est le fond de la feuille. Dessine par-dessus, puis enregistre ton projet Color.',
      );
      candidate = null;
      candidateBackground = null;
      _scheduleRecovery();
    } catch (error) {
      _error(
        error,
        message: 'Cette image n’a pas pu être ouverte. Ton dessin actuel est conservé.',
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
    try {
      final path = await widget.files.chooseOpen();
      recordNativeDiagnostics('open-panel-returned');
      if (path == null || !mounted) return;
      setState(() => _busyLabel = 'Ouverture de ton dessin…');
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
        setState(() => _busyLabel = 'Ouverture de ton dessin…');
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
        status: own ? _ownFolderStatus : null,
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
      _error(
        error,
        message: error is NewerProjectException
            ? 'Ce dessin vient d’une version plus récente de Color. Installe la dernière version pour l’ouvrir. Le dessin actuel est conservé.'
            : 'Ce projet n’a pas pu être ouvert. Le dessin actuel est conservé.',
      );
    } finally {
      candidateBackground?.dispose();
      candidate?.dispose();
      _releaseBusy();
    }
  }

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
        _status = 'Des modifications restent à enregistrer.';
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
        setState(() => _busyLabel = 'Préparation de ton projet…');
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
          _status = _dirty
              ? 'Des modifications restent à enregistrer.'
              : 'Projet enregistré : ${widget.files.shownPath(path)}';
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
          message: 'Le projet est enregistré. L’ancienne copie de récupération n’a pas pu être retirée.',
        );
      }
      if (!unchanged() || clearingGeneration != _recoveryGeneration) {
        preserveLatest();
        return false;
      }
      setState(() {
        _status = 'Projet enregistré : ${widget.files.shownPath(path)}';
        _savedJustNow = true;
      });
      // A tick on the button for a moment: not every interface has the
      // line of the status, and the sounds may be off.
      _savedTimer?.cancel();
      _savedTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _savedJustNow = false);
      });
      _sound(StudioSound.saved);
      return true;
    } catch (error) {
      _error(
        error,
        message: 'Enregistrement non terminé. Le dessin reste ouvert.',
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

  static const _reservedFolder =
      'Ce dossier est celui où Color range ses propres copies. Choisis un autre endroit pour ton dessin.';

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

  static const _ownFolderStatus =
      'Ce dessin vient d’un dossier que Color vide lui-même : il n’est pas encore rangé. Enregistrer te demandera où le mettre.';

  // The copy of the album is the drawing as it was saved that day: say so,
  // in case a later save never reached the album.
  static String _galleryCopyStatus(GalleryEntry entry) =>
      'Dessin repris de la galerie, tel qu’il était ${savedMoment(entry.savedAt.toLocal(), now: DateTime.now())} · Enregistrer te demandera où le ranger.';

  static const _replacedStatus =
      'Ce dessin vient d’être remplacé sur le disque par celui que tu as enregistré : il n’existe plus qu’ici. Enregistre-le sous un autre nom pour le garder.';

  // Beside the file that took its place, under a name that tells them apart.
  static String _earlierVersionPath(String path) {
    final name = StudioFiles.fileName(path);
    const extension = '.edupaint';
    final stem = name.toLowerCase().endsWith(extension)
        ? name.substring(0, name.length - extension.length)
        : name;
    return '${path.substring(0, path.length - name.length)}'
        '$stem (version précédente)$extension';
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
      setState(() => _busyLabel = 'Ouverture de ton dessin…');
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
                  ? 'Ce dessin est trop grand pour être gardé dans la galerie, et son fichier n’est plus accessible d’ici. Retrouve-le avec Ouvrir.'
                  : 'Ce dessin est trop grand pour être gardé dans la galerie, et son fichier n’est plus accessible d’ici. Un adulte peut le retrouver avec Ouvrir, dans une interface plus complète.',
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
            ? _replacedStatus
            : path == null
            ? _galleryCopyStatus(entry)
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
            ? 'Ce dessin vient d’une version plus récente de Color. Installe la dernière version pour l’ouvrir. Le dessin actuel est conservé.'
            : 'Ce dessin n’a pas pu être repris. Le dessin actuel est conservé.',
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
          'Cette feuille est trop grande pour une image PNG. Choisis le format SVG.',
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
          _status =
              'Image PNG exportée (${document.width * scale} × ${document.height * scale}) : ${widget.files.shownPath(path)}${_dirty ? ' · projet encore à enregistrer' : ''}';
        });
        observe('status-applied');
      }
    } on CopyNotHandedOver {
      // The person closed the system's panel: nothing to say.
      observe('cancelled');
    } catch (error) {
      observe('failed');
      _error(error, message: 'L’image n’a pas pu être exportée.');
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
        setState(() => _busyLabel = 'Préparation de ton image SVG…');
        await WidgetsBinding.instance.endOfFrame;
        if (!unchanged()) return;
      }
      final bytes = await prepareSvgBytes(document);
      if (!unchanged()) return;
      await widget.files.writeSvgBytes(path, bytes);
      recordNativeDiagnostics('svg-written');
      if (unchanged()) {
        setState(() {
          _status =
              'Image SVG exportée : ${widget.files.shownPath(path)}${_dirty ? ' · projet encore à enregistrer' : ''}';
        });
      }
      // Export deliberately never marks the editable project as saved.
    } on CopyNotHandedOver {
      // The person closed the system's panel: nothing to say.
    } catch (error) {
      _error(error, message: 'L’image n’a pas pu être exportée.');
    } finally {
      _releaseBusy();
    }
  }

  static const _noPrinter =
      'Color ne trouve pas d’imprimante sur cet ordinateur. Demande à un adulte d’en installer une, puis recommence.';
  static const _printUnavailable =
      'Cette version de Color ne sait pas imprimer sur cet ordinateur. Tu peux exporter ton dessin en image, puis imprimer l’image.';
  // The same in an interface that does not offer « Exporter ».
  static const _printUnavailableWithoutExport =
      'Cette version de Color ne sait pas imprimer sur cet ordinateur. Demande à un adulte.';

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
      _busyLabel = 'Préparation de ton dessin pour l’imprimante…';
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
            _status =
                'Impression lancée${_dirty ? ' · projet encore à enregistrer' : ''}';
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
      _error(error, message: 'Le dessin n’a pas pu être imprimé.');
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

  static const _doorClosed =
      'Trois résultats faux : les options restent fermées. Clique de nouveau sur Options pour réessayer.';

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
    if (_startupError != null) {
      return StudioStartupProblem(
        onDetails: () => _showProblemDetails(_startupError!),
      );
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
                          child: const Text(
                            'Color · Un petit atelier pour les grandes idées',
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
                            final tools = _options.tools;
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
                                      selected: _tool,
                                      onSelected: _busy ? null : _selectTool,
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
                                            selected: _tool,
                                            onSelected: _busy
                                                ? null
                                                : _selectTool,
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
          ? 'modifications non enregistrées'
          : _currentPath == null
          ? 'nouvelle feuille'
          : 'projet enregistré'}';

  String get _documentTitle =>
      _currentPath == null ? 'Mon dessin' : StudioFiles.fileName(_currentPath!);

  // The studio of a telephone on its side. The sheet takes the whole
  // height, in the middle. On the left, the tools under the button of the
  // menu, all in view. On the right, a column that scrolls: Annuler and
  // Rétablir, the colours, the size and what the tool chooses. Everything
  // else — the actions on the drawing, its film, the layers, help and
  // options — is in the menu.
  Widget _phoneBody() {
    final simple = _options.simpleControls;
    const railSide = BorderSide(color: studioLine);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            color: studioSurface,
            border: Border(right: railSide),
          ),
          child: StudioToolBar(
            rail: true,
            leading: _phoneMenuButton(),
            selected: _tool,
            onSelected: _busy ? null : _selectTool,
            tools: _options.tools,
            large: simple,
          ),
        ),
        Expanded(
          child: Padding(padding: const EdgeInsets.all(6), child: _canvas()),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
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
              label: 'Dessin enregistré',
              child: const Icon(
                Icons.check_circle,
                key: Key('savedTick'),
                size: 30,
                color: studioGreen,
              ),
            )
          : const Tooltip(
              message: 'Menu',
              excludeFromSemantics: true,
              child: Icon(Icons.menu_rounded, size: 30, semanticLabel: 'Menu'),
            ),
    ),
  );

  Future<void> _openPhoneMenu() async {
    if (_busy || _confirmationOpen) return;
    _settleLatch();
    final entries = [
      PhoneMenuEntry(
        id: 'newProject',
        name: 'Nouveau',
        picture: (size) => EduIllustration(art: EduArt.newPage, size: size),
        enabled: true,
      ),
      if (_options.opensFiles)
        PhoneMenuEntry(
          id: 'openProject',
          name: 'Ouvrir',
          picture: (size) => EduIllustration(art: EduArt.folder, size: size),
          enabled: true,
        ),
      if (_gallery != null)
        PhoneMenuEntry(
          id: 'openGallery',
          name: 'Mes dessins',
          picture: (size) => EduIllustration(art: EduArt.gallery, size: size),
          enabled: true,
        ),
      if (_options.opensFiles)
        PhoneMenuEntry(
          id: 'importImage',
          name: 'Sur une image',
          picture: (size) =>
              Icon(Icons.add_photo_alternate_outlined, size: size),
          enabled: true,
        ),
      PhoneMenuEntry(
        id: 'saveProject',
        name: 'Enregistrer',
        picture: (size) => EduIllustration(art: EduArt.save, size: size),
        enabled: true,
        filled: true,
      ),
      if (_options.exports)
        PhoneMenuEntry(
          id: 'exportImage',
          name: 'Exporter',
          picture: (size) =>
              EduIllustration(art: EduArt.exportImage, size: size),
          enabled: true,
        ),
      if (_options.printing)
        PhoneMenuEntry(
          id: 'printDrawing',
          name: 'Imprimer',
          picture: (size) => EduIllustration(art: EduArt.printer, size: size),
          enabled: true,
        ),
      PhoneMenuEntry(
        id: 'replayDrawing',
        name: 'Revoir',
        picture: (size) => EduIllustration(art: EduArt.film, size: size),
        enabled: _canReplay,
      ),
      if (_options.layers)
        PhoneMenuEntry(
          id: 'layersButton',
          name: 'Calques',
          picture: (size) => EduIllustration(art: EduArt.layers, size: size),
          enabled: true,
        ),
      if (_options.viewControls)
        PhoneMenuEntry(
          id: 'fitPage',
          name: 'Toute la feuille',
          picture: (size) => Icon(Icons.fit_screen_outlined, size: size),
          enabled: _viewEnabled && _view != null && !_view!.isFit,
        ),
      if (_options.headerHelp)
        PhoneMenuEntry(
          id: 'showHelp',
          name: 'Aide',
          picture: (size) => Icon(Icons.help_outline, size: size),
          enabled: true,
        ),
      PhoneMenuEntry(
        id: 'openOptions',
        name: 'Options',
        picture: (size) => EduIllustration(art: EduArt.options, size: size),
        enabled: true,
      ),
      // Always there: the privacy policy is reached through it.
      PhoneMenuEntry(
        id: 'aboutColor',
        name: 'À propos',
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
          label: redo ? 'Rétablir le geste annulé' : 'Annuler le dernier geste',
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
                label: 'Remplir la forme',
                child: Row(
                  children: [
                    Checkbox(
                      key: const Key('fillShapeCheckbox'),
                      value: _filled,
                      onChanged: enabled
                          ? (value) => _setFilled(value ?? false)
                          : null,
                    ),
                    const Expanded(
                      child: Text('Remplir', style: TextStyle(fontSize: 12)),
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
      if ((!_bigSheet && _options.toolHelp) || _choosing) ...[
        SizedBox(height: compact ? 6 : 10),
        Row(
          children: [
            if (!_choosing) ...[
              EduIllustration(art: EduArt.mascot, size: compact ? 32 : 56),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: _choosing
                  ? _selectionToolbar(compact: compact || _bigSheet)
                  : Text(
                      _toolHelp,
                      style: TextStyle(
                        fontSize: compact ? 11 : 13,
                        color: studioHelpText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ],
        ),
      ],
      if (!_bigSheet && _options.statusLine) ...[
        const SizedBox(height: 8),
        // One line, whatever it says: a sentence that came and went on two
        // lines would change the height left to the sheet at every edit.
        Text(
          _status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: studioStatusText),
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
      );

  String get _toolHelp => forTouch(_mouseToolHelp);

  String get _mouseToolHelp => _picking
      ? 'Clique sur une couleur de ton dessin pour la reprendre. Échap garde ta couleur.'
      : _latch == _Latch.stroke
      ? 'Bouge pour dessiner. Clique pour arrêter ton trait. Échap l’enlève.'
      : _latch == _Latch.move
      ? 'Bouge pour déplacer l’élément. Clique pour le poser.'
      : _latch == _Latch.pan
      ? 'Bouge pour déplacer la feuille. Clique pour la lâcher.'
      : _panning
      ? (_options.holdFree
            ? 'Clique pour prendre la feuille, bouge, puis clique pour la lâcher. Les boutons + et − rapprochent ou éloignent ton dessin.'
            : 'Glisse pour déplacer la feuille. Les boutons + et − rapprochent ou éloignent ton dessin.')
      : _shapeAnchor != null
      ? switch (_shapeAnchor!.kind) {
          VectorKind.line => 'Clique maintenant là où ta ligne doit s’arrêter. Échap enlève le petit cercle.',
          VectorKind.rectangle => 'Clique maintenant le coin d’en face de ton rectangle. Échap enlève le petit cercle.',
          _ => 'Clique maintenant plus loin, en biais : ton ovale se placera entre tes deux clics. Échap enlève le petit cercle.',
        }
      : _holdFreeHelp ?? _tool.help;

  // What « dessiner sans tenir le bouton » changes in the sentence of a tool.
  String? get _holdFreeHelp => !_options.holdFree
      ? null
      : switch (_tool) {
          StudioTool.brush => 'Clique pour commencer ton trait, bouge, puis clique pour l’arrêter. Tu peux aussi glisser.',
          StudioTool.select => 'Clique un élément pour le choisir. Clique-le encore pour le prendre, bouge, puis clique pour le poser.',
          _ => null,
        };

  void _selectTool(StudioTool tool) {
    if (_busy || _confirmationOpen) return;
    _settleLatch();
    _cancelDraft();
    setState(() {
      _setSelection(null);
      _tool = tool;
      _panning = false;
      _picking = false;
      _colorTarget = PaintColorTarget.stroke;
    });
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

  void _endViewGesture() {
    if (_latch == _Latch.pan) _latch = null;
    _panPointer = null;
    _panLast = null;
    _panStart = null;
    _trackpadPointer = null;
    _trackpadScale = 1;
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

  Widget _canvas() => LayoutBuilder(
    builder: (context, constraints) {
      // A telephone gives the sheet all its room: no name around it.
      final showCaptions =
          _options.captions &&
          constraints.maxHeight >= 160 &&
          !_phoneLayout(context);
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
          padding: showCaptions ? 28 : 8,
          documentWidth: _document!.width.toDouble(),
          documentHeight: _document!.height.toDouble(),
        );
      } else if (!held) {
        _view = _view!.resize(
          viewWidth: constraints.maxWidth,
          viewHeight: constraints.maxHeight,
          padding: showCaptions ? 28 : 8,
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
          return DecoratedBox(
            decoration: BoxDecoration(
              color: studioSheetBackdrop,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: studioLine),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    label: forTouch(
                      'Feuille de dessin ${_document!.width} par ${_document!.height} unités. Souris ou stylet.',
                    ),
                    child: MouseRegion(
                      cursor: _panning || _spaceHeld || _choosing
                          ? SystemMouseCursors.grab
                          : SystemMouseCursors.precise,
                      onExit: (_) {
                        _forgetAnchorEnd();
                        // A gesture without a held button ends where the
                        // pointer leaves the frame of the sheet.
                        _endLatch();
                      },
                      child: Listener(
                        key: const Key('drawingSurface'),
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) {
                          if (!_fingerDown(event)) {
                            _pointerDown(event, viewport);
                          }
                        },
                        onPointerMove: (event) {
                          if (!_fingerMove(event)) {
                            _pointerMove(event, viewport);
                          }
                        },
                        onPointerHover: (event) =>
                            _pointerHover(event, viewport),
                        onPointerSignal: _pointerSignal,
                        onPointerPanZoomStart: _trackpadStart,
                        onPointerPanZoomUpdate: _trackpadUpdate,
                        onPointerPanZoomEnd: (event) {
                          if (_trackpadPointer == event.pointer) {
                            _endViewGesture();
                          }
                        },
                        onPointerUp: (event) {
                          if (_fingerUp(event)) return;
                          if (_panPointer == event.pointer) {
                            _pointerMove(event, viewport);
                            if (!_beginPanLatch()) _endViewGesture();
                          }
                          if (_pointer == event.pointer) {
                            _pointerMove(event, viewport);
                            _finishStroke(released: true);
                          }
                        },
                        onPointerCancel: (event) {
                          if (_fingerUp(event)) return;
                          if (_panPointer == event.pointer) _endViewGesture();
                          if (_pointer == event.pointer) _cancelDraft();
                        },
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: DocumentPainter(
                              viewport: viewport,
                              paperRgb: _document!.paperRgb,
                              background: _backgroundImage,
                              strokes: _strokes,
                              paintOrder: _document!.paintOrder,
                              draftStamp: _draftStamp,
                              draft: _draftPath,
                              draftPoints: _draft,
                              repaint: _canvasRepaint,
                              draftColor: _draftColor,
                              draftWidth: _draftWidth,
                              draftKind: _draftKind,
                              draftFillRgb: _draftFillRgb,
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
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showCaptions)
                  const Positioned(
                    top: 10,
                    left: 16,
                    child: IgnorePointer(
                      child: Text(
                        'MA FEUILLE',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          color: studioSheetTitle,
                        ),
                      ),
                    ),
                  ),
                if (showCaptions)
                  Positioned(
                    bottom: 9,
                    left: 16,
                    child: IgnorePointer(
                      child: Text(
                        '${_document!.width} × ${_document!.height} unités',
                        style: const TextStyle(
                          fontSize: 10,
                          color: studioSheetCaption,
                        ),
                      ),
                    ),
                  ),
                if (showCaptions)
                  Positioned(
                    bottom: 9,
                    right: 16,
                    child: IgnorePointer(
                      child: Text(
                        _view!.isFit
                            ? 'Toute la feuille'
                            : '${(viewport.scale * 100).round()} %',
                        style: TextStyle(
                          fontSize: 10,
                          color: studioSheetCaption,
                        ),
                      ),
                    ),
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
      decoration: BoxDecoration(
        color: studioSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: studioLine),
      ),
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
        trailingControl: _sizeControl(narrow, rail: rail),
      );

  StampArt? get _currentStamp {
    try {
      return StampCatalog.instance[_stampId];
    } catch (_) {
      // The catalogue comes from the core; the studio stays usable without it.
      return null;
    }
  }

  /// One place answers « how big? »: the outline of a trait or shape, the
  /// letters of a text, or a stamp placed with a click.
  Widget? _sizeControl(bool narrow, {bool rail = false}) {
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
        what: forStamp ? 'du tampon' : 'du texte',
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
        what: 'du trait',
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
