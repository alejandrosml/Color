// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'native_project_writer.dart';
import 'platform_words.dart';
import 'project_storage.dart';
import 'rust_document.dart';
import 'raster_source.dart' show maxRasterBytes;

/// A native save panel seam; returned paths are kept only in this process.
typedef StudioSaveChooser = Future<String?> Function({
  required String suggestedName,
  required String? initialDirectory,
  required List<XTypeGroup> acceptedTypeGroups,
  required String confirmButtonText,
});

/// A native open panel seam; choosing a file does not claim it was read.
typedef StudioOpenChooser = Future<String?> Function({
  required String? initialDirectory,
  required List<XTypeGroup> acceptedTypeGroups,
  required String confirmButtonText,
});

/// Bounded session memory: no per-project map and no persistence.
class StudioDestinationSession {
  String? _lastDirectory;
  String? _exportSource;
  String? _exportDirectory;
  String? _openDirectory;
  String? _imageDirectory;
}

/// Hands a file of Color's outbox to the system's panel of a tablet or a
/// telephone, which puts a copy where the person chooses: in Files, in a
/// cloud, in another application. The name the copy was given there, or
/// null when the person closed the panel.
typedef StudioHandOver = Future<String?> Function(
  String path,
  String name,
  String mimeType,
);

/// The person closed the system's panel without choosing where to put a
/// copy: nothing was written anywhere, and nothing is wrong.
class CopyNotHandedOver implements Exception {
  const CopyNotHandedOver();
  @override
  String toString() => 'La copie n’a été remise nulle part.';
}

const _handOverChannel = MethodChannel('org.edupaint/files');

/// Native dialogs and file I/O, injected separately from document state.
///
/// On a tablet or a telephone there is no panel to choose a folder: a
/// drawing is saved in Color's own folder of drawings, under its name, and
/// an exported image is handed to the system's panel, which places a copy.
class StudioFiles {
  const StudioFiles({
    this.saveChooser,
    this.openChooser,
    this.documentsDirectory,
    this.destinationSession,
    this.mobile,
    this.handOver,
    this.outboxDirectory,
  });

  final StudioSaveChooser? saveChooser;
  final StudioOpenChooser? openChooser;
  final Future<String?> Function()? documentsDirectory;
  final StudioDestinationSession? destinationSession;

  /// Whether this is the way of a tablet or a telephone; by default, the
  /// device's.
  final bool? mobile;

  /// Replaces the system's panel that receives copies; tests give one.
  final StudioHandOver? handOver;

  /// Replaces the folder where copies wait for that panel.
  final Future<String> Function()? outboxDirectory;

  bool get _mobile => mobile ?? touchFirst;

  // The names the system's panel gave the copies, by the path they waited
  // at: what the studio says it exported.
  static final _handedNames = <String, String>{};
  static final _sessionDestinations = StudioDestinationSession();

  StudioDestinationSession get _destinations =>
      destinationSession ?? _sessionDestinations;

  static const _projectType = XTypeGroup(
    label: 'Projet Color',
    extensions: ['edupaint'],
    uniformTypeIdentifiers: ['org.edupaint.project'],
  );

  Future<String?> chooseOpen() => _chooseSource(
    acceptedTypeGroups: const [_projectType],
    confirmButtonText: 'Ouvrir le dessin',
    isImage: false,
  );

  Future<String?> chooseSave({String? currentPath}) => _mobile
      ? _ownDrawingPath(currentPath)
      : _chooseDestination(
          currentPath: currentPath,
          suggestedName: _suggestedProjectName(currentPath),
          acceptedTypeGroups: const [_projectType],
          confirmButtonText: 'Enregistrer le dessin',
          isExport: false,
        );

  /// Color's own folder of drawings on a tablet or a telephone: « Dessins »
  /// in its documents.
  Future<Directory> ownDrawings() async {
    final base =
        await (documentsDirectory ?? _applicationDocuments)() ??
        (await getApplicationDocumentsDirectory()).path;
    final folder = Directory('$base${Platform.pathSeparator}Dessins');
    await folder.create(recursive: true);
    return folder;
  }

  static Future<String?> _applicationDocuments() async =>
      (await getApplicationDocumentsDirectory()).path;

  /// Where a drawing is saved without a panel: where it already is when it
  /// was saved there, otherwise under its name, made free with a number.
  Future<String> _ownDrawingPath(String? currentPath) async {
    final folder = await ownDrawings();
    if (currentPath != null &&
        File(currentPath).parent.absolute.path == folder.absolute.path) {
      return currentPath;
    }
    return _freeName(folder.path, drawingName(currentPath), '.edupaint');
  }

  static String _freeName(String folder, String stem, String extension) {
    for (var number = 1; ; number++) {
      final name = number == 1 ? '$stem$extension' : '$stem $number$extension';
      final path = '$folder${Platform.pathSeparator}$name';
      if (!File(path).existsSync()) return path;
    }
  }

  /// Where an exported copy waits for the system's panel.
  Future<String> _outboxPath(String name) async {
    final base =
        await outboxDirectory?.call() ?? (await getTemporaryDirectory()).path;
    final outbox = Directory('$base${Platform.pathSeparator}color-outbox');
    await outbox.create(recursive: true);
    return '${outbox.path}${Platform.pathSeparator}$name';
  }

  static bool _waitsInOutbox(String path) => path.contains(
    '${Platform.pathSeparator}color-outbox${Platform.pathSeparator}',
  );

  /// Writes [bytes] in the outbox, hands them to the system's panel and
  /// takes them back out of the outbox, whatever the person chose.
  Future<void> _handOverCopy(
    String path,
    Uint8List bytes,
    String mimeType,
  ) async {
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    try {
      final name = await (handOver ?? _systemHandOver)(
        path,
        fileName(path),
        mimeType,
      );
      if (name == null) throw const CopyNotHandedOver();
      _handedNames[path] = name;
    } finally {
      try {
        await file.delete();
      } on FileSystemException {
        // The temporary folder of the system empties itself.
      }
    }
  }

  static Future<String?> _systemHandOver(
    String path,
    String name,
    String mimeType,
  ) => _handOverChannel.invokeMethod<String>('saveAs', {
    'path': path,
    'name': name,
    'mime': mimeType,
  });

  /// What the studio says of a file it wrote: its path on a computer; on a
  /// tablet or a telephone, the name the system's panel gave the copy, or
  /// the name of the drawing in Color's folder.
  String shownPath(String path) =>
      _mobile ? (_handedNames[path] ?? fileName(path)) : path;

  Future<String?> chooseImage() => _chooseSource(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Image PNG ou JPEG',
        extensions: ['png', 'jpg', 'jpeg'],
        uniformTypeIdentifiers: ['public.png', 'public.jpeg'],
      ),
    ],
    confirmButtonText: 'Dessiner sur cette image',
    isImage: true,
  );

  Future<String?> _chooseSource({
    required List<XTypeGroup> acceptedTypeGroups,
    required String confirmButtonText,
    required bool isImage,
  }) async {
    final memory = _destinations;
    final preferredDirectory = isImage
        ? memory._imageDirectory
        : memory._openDirectory;
    final initialDirectory =
        preferredDirectory ??
        await (documentsDirectory ?? _documentsDirectory)();
    final selected = await (openChooser ?? _nativeOpenChooser)(
      initialDirectory: initialDirectory,
      acceptedTypeGroups: acceptedTypeGroups,
      confirmButtonText: confirmButtonText,
    );
    // Remember an explicit choice only. Cancellation and panel errors leave
    // both memories untouched; a later read failure does not undo the choice.
    if (selected != null) {
      final directory = File(_absolutePath(selected)).parent.path;
      if (isImage) {
        memory._imageDirectory = directory;
      } else {
        memory._openDirectory = directory;
      }
    }
    return selected;
  }

  static Future<String?> _nativeOpenChooser({
    required String? initialDirectory,
    required List<XTypeGroup> acceptedTypeGroups,
    required String confirmButtonText,
  }) async => (await openFile(
    initialDirectory: initialDirectory,
    acceptedTypeGroups: acceptedTypeGroups,
    confirmButtonText: confirmButtonText,
  ))?.path;

  Future<Uint8List> readImage(String path) => ProjectStorage.readBoundedBytes(
    path,
    maximumBytes: maxRasterBytes,
    tooLargeMessage: 'Cette image dépasse la taille autorisée.',
  );

  Future<String?> chooseExport({String? currentPath}) => _mobile
      ? _outboxPath(_suggestedImageName(currentPath, '.svg'))
      : _chooseSvgDestination(currentPath);

  Future<String?> _chooseSvgDestination(String? currentPath) =>
      _chooseDestination(
        currentPath: currentPath,
        suggestedName: _suggestedImageName(currentPath, '.svg'),
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Dessin SVG',
            extensions: ['svg'],
            uniformTypeIdentifiers: ['public.svg-image'],
          ),
        ],
        confirmButtonText: 'Exporter l’image',
        isExport: true,
      );

  Future<Uint8List> read(String path) => ProjectStorage.readProject(path);

  /// Real files are read and parsed by the worker, without a UI-side byte copy.
  /// Injected providers override this explicitly rather than bypassing their I/O.
  Future<PreparedProject> readPrepared(String path) =>
      RustDocument.loadProjectFile(path);
  Future<String?> choosePng({String? currentPath}) => _mobile
      ? _outboxPath(_suggestedImageName(currentPath, '.png'))
      : _choosePngDestination(currentPath);

  Future<String?> _choosePngDestination(String? currentPath) =>
      _chooseDestination(
        currentPath: currentPath,
        suggestedName: _suggestedImageName(currentPath, '.png'),
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Image PNG',
            extensions: ['png'],
            uniformTypeIdentifiers: ['public.png'],
          ),
        ],
        confirmButtonText: 'Exporter l’image',
        isExport: true,
      );

  Future<String?> _chooseDestination({
    required String? currentPath,
    required String suggestedName,
    required List<XTypeGroup> acceptedTypeGroups,
    required String confirmButtonText,
    required bool isExport,
  }) async {
    final memory = _destinations;
    final context = currentPath == null ? null : _absolutePath(currentPath);
    // An existing project's own folder remains the default for Save As, or
    // the first export after switching project. Later exports in that context
    // reuse the last explicit PNG/SVG destination. Unsaved work uses the last
    // confirmed destination across all three save panels in this session.
    final String? preferredDirectory;
    if (isExport &&
        context != null &&
        context == memory._exportSource &&
        memory._exportDirectory != null) {
      preferredDirectory = memory._exportDirectory;
    } else if (context != null) {
      preferredDirectory = File(context).parent.path;
    } else {
      preferredDirectory = memory._lastDirectory;
    }
    final initialDirectory =
        preferredDirectory ??
        await (documentsDirectory ?? _documentsDirectory)();
    final selected = await (saveChooser ?? _nativeSaveChooser)(
      suggestedName: suggestedName,
      initialDirectory: initialDirectory,
      acceptedTypeGroups: acceptedTypeGroups,
      confirmButtonText: confirmButtonText,
    );
    // Cancellation and panel exceptions cannot change the remembered folder.
    // A confirmed choice is remembered even if the later write fails: choosing
    // a destination does not claim that the document was saved successfully.
    if (selected != null) {
      final directory = File(_absolutePath(selected)).parent.path;
      memory._lastDirectory = directory;
      if (isExport) {
        memory._exportSource = context;
        memory._exportDirectory = directory;
      }
    }
    return selected;
  }

  static String _absolutePath(String path) =>
      File(path).absolute.uri.normalizePath().toFilePath();

  static Future<String?> _nativeSaveChooser({
    required String suggestedName,
    required String? initialDirectory,
    required List<XTypeGroup> acceptedTypeGroups,
    required String confirmButtonText,
  }) async => (await getSaveLocation(
    suggestedName: suggestedName,
    initialDirectory: initialDirectory,
    acceptedTypeGroups: acceptedTypeGroups,
    confirmButtonText: confirmButtonText,
  ))?.path;

  Future<void> writePng(String path, Uint8List bytes) => _waitsInOutbox(path)
      ? _handOverCopy(path, bytes, 'image/png')
      : writeNativeProject(path, bytes);
  Future<void> write(String path, Uint8List bytes) =>
      writeNativeProject(path, bytes);
  Future<void> writeSvgBytes(String path, Uint8List bytes) =>
      _waitsInOutbox(path)
      ? _handOverCopy(path, bytes, 'image/svg+xml')
      : writeNativeProject(path, bytes);
  Future<void> writeSvg(String path, String svg) =>
      writeSvgBytes(path, Uint8List.fromList(utf8.encode(svg)));

  static Future<String?> _documentsDirectory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      // In the sandbox of the Mac, the folder Color is given is its own,
      // hidden in the Library: the panel opens on the person's Documents
      // instead. The panel may show it; Color itself may not look there,
      // so it is not asked whether that folder exists.
      final documents = userDocumentsOutsideSandbox(directory.path);
      if (documents != directory.path) return documents;
      return await directory.exists() ? directory.path : null;
    } catch (_) {
      // A missing desktop directory must not prevent the native picker opening.
      return null;
    }
  }

  /// The name of the drawing as a person reads it: the name of its file
  /// without the project's extension, or « Mon dessin » before a first save.
  static String drawingName(String? currentPath) =>
      _suggestedImageName(currentPath, '');

  /// The name under which the system lists a drawing that is printed: its
  /// [drawingName] on one line, without the characters that only steer a
  /// display, and short enough for a print queue.
  static String printJobName(String? currentPath) {
    final kept = StringBuffer();
    for (final rune in drawingName(currentPath).runes) {
      final steering =
          rune < 0x20 ||
          (rune >= 0x7f && rune < 0xa0) ||
          rune == 0x200e ||
          rune == 0x200f ||
          (rune >= 0x202a && rune <= 0x202e) ||
          (rune >= 0x2028 && rune <= 0x2029) ||
          (rune >= 0x2066 && rune <= 0x2069) ||
          rune == 0xfeff;
      kept.writeCharCode(steering ? 0x20 : rune);
    }
    final name = kept.toString().replaceAll(RegExp(' +'), ' ').trim();
    if (name.isEmpty) return 'Mon dessin';
    final runes = name.runes.toList();
    return runes.length <= 80
        ? name
        : String.fromCharCodes(runes.take(80)).trimRight();
  }

  static String _suggestedImageName(String? currentPath, String extension) {
    if (currentPath == null) return 'Mon dessin$extension';
    final name = fileName(currentPath);
    const projectExtension = '.edupaint';
    final stem =
        name.length > projectExtension.length &&
            name.toLowerCase().endsWith(projectExtension)
        ? name.substring(0, name.length - projectExtension.length)
        : name;
    return '$stem$extension';
  }

  static String _suggestedProjectName(String? currentPath) {
    final name = currentPath == null
        ? 'Mon dessin.edupaint'
        : fileName(currentPath);
    const extension = '.edupaint';
    // NSSavePanel adds the preferred extension of our registered UTType.
    // Other desktop selectors continue receiving a complete suggested name.
    if (Platform.isMacOS &&
        name.length > extension.length &&
        name.toLowerCase().endsWith(extension)) {
      return name.substring(0, name.length - extension.length);
    }
    return name;
  }

  static String fileName(String path) =>
      path.replaceAll('\\', '/').split('/').last;
}

/// The Documents folder of the person, when [path] is the one macOS gives a
/// sandboxed application in its container
/// (« `/Users/nom/Library/Containers/identifiant/Data/Documents` ») : a
/// panel that opened there would hide what is saved from the Finder. Any
/// other path is given back as it is.
String userDocumentsOutsideSandbox(String path) {
  const container = '/Library/Containers/';
  final at = path.indexOf(container);
  if (at <= 0 || !path.startsWith('/')) return path;
  return '${path.substring(0, at)}/Documents';
}
