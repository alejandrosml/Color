// SPDX-License-Identifier: MIT
// The mutable document belongs to one isolate. Asynchronous export lends only
// a separate immutable snapshot to a worker, with an explicit bounded lifetime.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'file_operation_cleanup_exception.dart';
import 'bounded_project_reader.dart';
import 'borrowed_isolate_job.dart';

/// Bound of layered v4 and v5; v1/v2/v3 retain their smaller native bounds.
const int maxProjectBytes = 80_711_932;
const int maxBackgroundBytes = 68 * 1024 * 1024;
const int maxBackgroundDimension = 8192;
const int maxBackgroundPixels = 16 * 1024 * 1024;

/// Native limits of text objects: UTF-8 bytes, lines and size in document units.
const int maxTextBytes = 2048;
const int maxTextLines = 32;
const double minTextSize = 4;
const double maxTextSize = 2048;
const int maxLayers = 16;

/// Colour of the sheet of a new document.
const int whitePaper = 0xffffff;

/// Newest project format that this version of Color reads and writes:
/// version 5 brought locked layers and closed contours, those of the
/// colouring pages.
const int newestProjectVersion = 5;

/// The format version announced by the first bytes of a Color project, or
/// null when they are not the beginning of one. Only a hint to explain a
/// refusal: the core alone decides what is a valid project.
int? announcedProjectVersion(List<int> bytes) {
  const magic = [0x45, 0x44, 0x55, 0x50, 0x41, 0x49, 0x4e, 0x54]; // EDUPAINT
  if (bytes.length < 12) return null;
  for (var index = 0; index < magic.length; index++) {
    if (bytes[index] != magic[index]) return null;
  }
  // The two bytes after the version are flags that every version leaves at 0.
  if (bytes[10] != 0 || bytes[11] != 0) return null;
  return bytes[8] | bytes[9] << 8;
}

/// A project that the core refused and that announces a newer format: most
/// likely written by a later version of Color. Nothing was loaded from it.
class NewerProjectException extends FormatException {
  NewerProjectException(this.version)
    : super(
        'Ce projet Color annonce le format $version ; cette version de Color '
        'lit les formats 1 à $newestProjectVersion.',
      );
  final int version;
}

// What to throw when the core refuses project bytes.
FormatException _projectRefusal(List<int> bytes) {
  final version = announcedProjectVersion(bytes);
  return version != null && version > newestProjectVersion
      ? NewerProjectException(version)
      : const FormatException(
          'Ce fichier n’est pas un projet Color valide ou sa version est inconnue.',
        );
}

/// The index of each value is the native object kind.
enum VectorKind {
  stroke,
  line,
  rectangle,
  ellipse,
  text,
  stamp,

  /// A closed polygon of three points or more, the last joined to the
  /// first: the zones and the lines of a colouring page. No tool draws one;
  /// a page or a project of version 5 brings them.
  contour;

  /// Text and stamps are boxes without an outline width.
  bool get isBoxObject => this == text || this == stamp;

  /// Rectangles, ovals and contours may have an inside, of its own colour.
  bool get canFill => this == rectangle || this == ellipse || this == contour;
}

final class _EpDocument extends Opaque {}

final class _EpExportSnapshot extends Opaque {}

final class _EpPoint extends Struct {
  @Float()
  external double x;
  @Float()
  external double y;
}

final class _EpStrokeInfo extends Struct {
  @Uint32()
  external int rgb;
  @Float()
  external double width;
  @Size()
  external int pointCount;
}

final class _EpObjectStyle extends Struct {
  @Uint32()
  external int kind;
  @Uint32()
  external int fillEnabled;
  @Uint32()
  external int fillRgb;
}

final class _EpBackgroundInfo extends Struct {
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Size()
  external int byteCount;
}

final class _EpLayerInfo extends Struct {
  @Uint32()
  external int id;
  @Uint32()
  external int visible;
  @Size()
  external int objectCount;
}

final class _EpObjectExtra extends Struct {
  @Uint32()
  external int layer;
  @Uint32()
  external int param;
  @Size()
  external int textBytes;
}

/// One layer of the stack, bottom first. [id] is stable within a document.
class LayerData {
  const LayerData({
    required this.id,
    required this.visible,
    required this.objectCount,
    this.locked = false,
  });
  final int id;
  final bool visible;
  final int objectCount;

  /// A layer of a colouring page. The core keeps it whole: it is never the
  /// active layer, never removed nor moved, and its objects never change,
  /// except the colour of a fill that one already has (the paint pot's). It
  /// may be hidden and shown.
  final bool locked;

  @override
  bool operator ==(Object other) =>
      other is LayerData &&
      other.id == id &&
      other.visible == visible &&
      other.objectCount == objectCount &&
      other.locked == locked;
  @override
  int get hashCode => Object.hash(id, visible, objectCount, locked);
}

/// Immutable metadata; reading this does not copy the embedded PNG.
class BackgroundInfo {
  const BackgroundInfo({
    required this.width,
    required this.height,
    required this.byteCount,
  });
  final int width;
  final int height;
  final int byteCount;
}

class DocumentPoint {
  const DocumentPoint(this.x, this.y);
  final double x;
  final double y;
}

class StrokeData {
  StrokeData(
    List<DocumentPoint> points,
    this.rgb,
    this.width, {
    this.kind = VectorKind.stroke,
    this.fillRgb,
    this.layer = 0,
    this.text,
    this.stamp,
  }) : points = List.unmodifiable(points);
  final List<DocumentPoint> points;
  final int rgb;

  /// Outline width; the size of a text; always 1 for a stamp.
  final double width;
  final VectorKind kind;

  /// Colour of the inside of a rectangle, an oval or a contour; null for an
  /// element without one.
  final int? fillRgb;

  /// Identifier of the owning layer.
  final int layer;

  /// Characters of a text object, lines separated by a line feed.
  final String? text;

  /// Catalogue identifier of a stamp object.
  final int? stamp;

  /// Half of the painted outline around the control points.
  double get outlineRadius => kind.isBoxObject ? 0 : width / 2;

  /// Whether it has an inside of another colour than white: a zone of a
  /// colouring page, white when the page is made, once the paint pot has
  /// coloured it.
  bool get colouredInside => fillRgb != null && fillRgb != whitePaper;
}

class RustCoreException implements Exception {
  const RustCoreException(this.operation, this.code);
  final String operation;
  final int code;
  @override
  String toString() => code == -2
      ? 'Mémoire insuffisante pour $operation. Le dessin précédent est conservé.'
      : 'Le cœur a refusé $operation (code $code) : une limite du dessin est atteinte, ou la demande n’est pas valide. Le dessin précédent est conservé.';
}

/// The characters of a text exactly as the core holds them. The decoder
/// drops a byte-order mark at the very beginning; the core counts it as a
/// character like any other, and what is cached here must be what it stores.
String _decodeText(Uint8List bytes) {
  final text = utf8.decode(bytes);
  final marked =
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  return marked ? '\ufeff$text' : text;
}

class _Bindings {
  _Bindings(this.library, this.path);
  final DynamicLibrary library;
  final String path;
  late final create = library
      .lookupFunction<
        Pointer<_EpDocument> Function(Uint32, Uint32),
        Pointer<_EpDocument> Function(int, int)
      >('ep_document_new');
  late final snapshotNew = library
      .lookupFunction<
        Pointer<_EpExportSnapshot> Function(
          Pointer<_EpDocument>,
          Pointer<Int32>,
        ),
        Pointer<_EpExportSnapshot> Function(
          Pointer<_EpDocument>,
          Pointer<Int32>,
        )
      >('ep_export_snapshot_new');
  late final snapshotFree = library
      .lookupFunction<
        Void Function(Pointer<_EpExportSnapshot>),
        void Function(Pointer<_EpExportSnapshot>)
      >('ep_export_snapshot_free');
  late final snapshotProjectSize = library
      .lookupFunction<
        Size Function(Pointer<_EpExportSnapshot>),
        int Function(Pointer<_EpExportSnapshot>)
      >('ep_export_snapshot_project_size');
  late final snapshotCopyProject = library
      .lookupFunction<
        Int32 Function(Pointer<_EpExportSnapshot>, Pointer<Uint8>, Size),
        int Function(Pointer<_EpExportSnapshot>, Pointer<Uint8>, int)
      >('ep_export_snapshot_copy_project');
  late final snapshotSvg = library
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<_EpExportSnapshot>),
        Pointer<Utf8> Function(Pointer<_EpExportSnapshot>)
      >('ep_export_snapshot_export_svg');
  late final free = library
      .lookupFunction<
        Void Function(Pointer<_EpDocument>),
        void Function(Pointer<_EpDocument>)
      >('ep_document_free');
  late final width = library
      .lookupFunction<
        Uint32 Function(Pointer<_EpDocument>),
        int Function(Pointer<_EpDocument>)
      >('ep_document_width');
  late final height = library
      .lookupFunction<
        Uint32 Function(Pointer<_EpDocument>),
        int Function(Pointer<_EpDocument>)
      >('ep_document_height');
  late final count = library
      .lookupFunction<
        Size Function(Pointer<_EpDocument>),
        int Function(Pointer<_EpDocument>)
      >('ep_stroke_count');
  late final objectRevision = library
      .lookupFunction<
        Uint64 Function(Pointer<_EpDocument>, Size),
        int Function(Pointer<_EpDocument>, int)
      >('ep_object_revision');
  late final undoCount = library
      .lookupFunction<
        Size Function(Pointer<_EpDocument>),
        int Function(Pointer<_EpDocument>)
      >('ep_undo_count');
  late final moveObject = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size, Float, Float),
        int Function(Pointer<_EpDocument>, int, double, double)
      >('ep_move_object');
  late final constrainObjectMovement = library
      .lookupFunction<
        Int32 Function(
          Pointer<_EpDocument>,
          Size,
          Float,
          Float,
          Pointer<_EpPoint>,
        ),
        int Function(
          Pointer<_EpDocument>,
          int,
          double,
          double,
          Pointer<_EpPoint>,
        )
      >('ep_constrain_object_movement');
  late final reorderObject = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size, Size),
        int Function(Pointer<_EpDocument>, int, int)
      >('ep_reorder_object');
  late final removeObject = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size),
        int Function(Pointer<_EpDocument>, int)
      >('ep_remove_object');
  late final duplicateObject = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size, Float, Float),
        int Function(Pointer<_EpDocument>, int, double, double)
      >('ep_duplicate_object');
  late final setObjectStyle = library
      .lookupFunction<
        Int32 Function(
          Pointer<_EpDocument>,
          Size,
          Uint32,
          Float,
          Uint32,
          Uint32,
        ),
        int Function(Pointer<_EpDocument>, int, int, double, int, int)
      >('ep_set_object_style');
  late final redoCount = library
      .lookupFunction<
        Size Function(Pointer<_EpDocument>),
        int Function(Pointer<_EpDocument>)
      >('ep_redo_count');
  late final add = library
      .lookupFunction<
        Int32 Function(
          Pointer<_EpDocument>,
          Pointer<_EpPoint>,
          Size,
          Uint32,
          Float,
        ),
        int Function(Pointer<_EpDocument>, Pointer<_EpPoint>, int, int, double)
      >('ep_add_stroke');
  late final addShape = library
      .lookupFunction<
        Int32 Function(
          Pointer<_EpDocument>,
          Pointer<_EpPoint>,
          Pointer<_EpObjectStyle>,
          Uint32,
          Float,
        ),
        int Function(
          Pointer<_EpDocument>,
          Pointer<_EpPoint>,
          Pointer<_EpObjectStyle>,
          int,
          double,
        )
      >('ep_add_shape');
  late final style = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size, Pointer<_EpObjectStyle>),
        int Function(Pointer<_EpDocument>, int, Pointer<_EpObjectStyle>)
      >('ep_object_style');
  late final undo = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>),
        int Function(Pointer<_EpDocument>)
      >('ep_undo');
  late final redo = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>),
        int Function(Pointer<_EpDocument>)
      >('ep_redo');
  late final info = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size, Pointer<_EpStrokeInfo>),
        int Function(Pointer<_EpDocument>, int, Pointer<_EpStrokeInfo>)
      >('ep_stroke_info');
  late final copyPoints = library
      .lookupFunction<
        Size Function(Pointer<_EpDocument>, Size, Pointer<_EpPoint>, Size),
        int Function(Pointer<_EpDocument>, int, Pointer<_EpPoint>, int)
      >('ep_copy_points');
  late final export = library
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<_EpDocument>),
        Pointer<Utf8> Function(Pointer<_EpDocument>)
      >('ep_export_svg');
  late final freeString = library
      .lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('ep_string_free');
  late final projectSize = library
      .lookupFunction<
        Size Function(Pointer<_EpDocument>),
        int Function(Pointer<_EpDocument>)
      >('ep_project_size');
  late final copyProject = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Pointer<Uint8>, Size),
        int Function(Pointer<_EpDocument>, Pointer<Uint8>, int)
      >('ep_copy_project');
  late final fromProject = library
      .lookupFunction<
        Pointer<_EpDocument> Function(Pointer<Uint8>, Size, Pointer<Int32>),
        Pointer<_EpDocument> Function(Pointer<Uint8>, int, Pointer<Int32>)
      >('ep_document_from_project');
  late final loadProject = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Pointer<Uint8>, Size),
        int Function(Pointer<_EpDocument>, Pointer<Uint8>, int)
      >('ep_document_load_project');
  late final fromBackgroundPng = library
      .lookupFunction<
        Pointer<_EpDocument> Function(Pointer<Uint8>, Size, Pointer<Int32>),
        Pointer<_EpDocument> Function(Pointer<Uint8>, int, Pointer<Int32>)
      >('ep_document_from_background_png');
  late final backgroundInfo = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Pointer<_EpBackgroundInfo>),
        int Function(Pointer<_EpDocument>, Pointer<_EpBackgroundInfo>)
      >('ep_background_info');
  late final copyBackgroundPng = library
      .lookupFunction<
        Size Function(Pointer<_EpDocument>, Pointer<Uint8>, Size),
        int Function(Pointer<_EpDocument>, Pointer<Uint8>, int)
      >('ep_copy_background_png');
  late final addText = library
      .lookupFunction<
        Int32 Function(
          Pointer<_EpDocument>,
          Pointer<_EpPoint>,
          Uint32,
          Float,
          Uint32,
          Pointer<Uint8>,
          Size,
        ),
        int Function(
          Pointer<_EpDocument>,
          Pointer<_EpPoint>,
          int,
          double,
          int,
          Pointer<Uint8>,
          int,
        )
      >('ep_add_text');
  late final setText = library
      .lookupFunction<
        Int32 Function(
          Pointer<_EpDocument>,
          Size,
          Pointer<_EpPoint>,
          Uint32,
          Float,
          Uint32,
          Pointer<Uint8>,
          Size,
        ),
        int Function(
          Pointer<_EpDocument>,
          int,
          Pointer<_EpPoint>,
          int,
          double,
          int,
          Pointer<Uint8>,
          int,
        )
      >('ep_set_text');
  late final copyObjectText = library
      .lookupFunction<
        Size Function(Pointer<_EpDocument>, Size, Pointer<Uint8>, Size),
        int Function(Pointer<_EpDocument>, int, Pointer<Uint8>, int)
      >('ep_copy_object_text');
  late final objectExtra = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size, Pointer<_EpObjectExtra>),
        int Function(Pointer<_EpDocument>, int, Pointer<_EpObjectExtra>)
      >('ep_object_extra');
  late final stampCount = library
      .lookupFunction<Uint32 Function(), int Function()>('ep_stamp_count');
  late final stampCatalog = library
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'ep_stamp_catalog',
      );
  late final addStamp = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Pointer<_EpPoint>, Uint32, Uint32),
        int Function(Pointer<_EpDocument>, Pointer<_EpPoint>, int, int)
      >('ep_add_stamp');
  late final layerCount = library
      .lookupFunction<
        Size Function(Pointer<_EpDocument>),
        int Function(Pointer<_EpDocument>)
      >('ep_layer_count');
  late final layerInfo = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size, Pointer<_EpLayerInfo>),
        int Function(Pointer<_EpDocument>, int, Pointer<_EpLayerInfo>)
      >('ep_layer_info');
  late final layerLocked = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size),
        int Function(Pointer<_EpDocument>, int)
      >('ep_layer_locked');
  late final activeLayer = library
      .lookupFunction<
        Uint32 Function(Pointer<_EpDocument>),
        int Function(Pointer<_EpDocument>)
      >('ep_active_layer');
  late final setActiveLayer = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Uint32),
        int Function(Pointer<_EpDocument>, int)
      >('ep_set_active_layer');
  late final addLayer = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>),
        int Function(Pointer<_EpDocument>)
      >('ep_add_layer');
  late final removeLayer = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size),
        int Function(Pointer<_EpDocument>, int)
      >('ep_remove_layer');
  late final reorderLayer = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size, Size),
        int Function(Pointer<_EpDocument>, int, int)
      >('ep_reorder_layer');
  late final setLayerVisible = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size, Uint32),
        int Function(Pointer<_EpDocument>, int, int)
      >('ep_set_layer_visible');
  late final setObjectLayer = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size, Uint32),
        int Function(Pointer<_EpDocument>, int, int)
      >('ep_set_object_layer');
  late final paperColor = library
      .lookupFunction<
        Uint32 Function(Pointer<_EpDocument>),
        int Function(Pointer<_EpDocument>)
      >('ep_paper_color');
  late final setPaperColor = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Uint32),
        int Function(Pointer<_EpDocument>, int)
      >('ep_set_paper_color');
  late final scaleObject = library
      .lookupFunction<
        Int32 Function(Pointer<_EpDocument>, Size, Float, Float),
        int Function(Pointer<_EpDocument>, int, double, double)
      >('ep_scale_object');
  late final artCount = library
      .lookupFunction<Uint32 Function(), int Function()>('ep_art_count');
  late final artCatalog = library
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'ep_art_catalog',
      );
  late final pictureFromSvg = library
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Uint8>, Size),
        Pointer<Utf8> Function(Pointer<Uint8>, int)
      >('ep_picture_from_svg');
  late final pageCount = library
      .lookupFunction<Uint32 Function(), int Function()>('ep_page_count');
  late final pageCatalog = library
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'ep_page_catalog',
      );
  late final fromPage = library
      .lookupFunction<
        Pointer<_EpDocument> Function(Uint32),
        Pointer<_EpDocument> Function(int)
      >('ep_document_from_page');
  late final soundCount = library
      .lookupFunction<Uint32 Function(), int Function()>('ep_sound_count');
  late final soundNames = library
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'ep_sound_names',
      );
  late final soundWavSize = library
      .lookupFunction<Size Function(Uint32), int Function(int)>(
        'ep_sound_wav_size',
      );
  late final copySoundWav = library
      .lookupFunction<
        Size Function(Uint32, Pointer<Uint8>, Size),
        int Function(int, Pointer<Uint8>, int)
      >('ep_copy_sound_wav');
  late final soundPlay = library
      .lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'ep_sound_play',
      );
  late final thirdPartyNotices = library
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'ep_third_party_notices',
      );
}

/// The name that stands for the program itself, where the core is linked
/// into the application rather than beside it: on iPhone and iPad.
const processCoreLibrary = '<application>';

/// Opens the core named [path]: a library beside the program, or the
/// program itself for [processCoreLibrary].
DynamicLibrary openCoreLibrary(String path) => path == processCoreLibrary
    ? DynamicLibrary.process()
    : DynamicLibrary.open(path);

/// Owns exactly one Rust document. Do not share its handle or use it concurrently.
/// No native pointer escapes this wrapper; all returned data is copied into Dart.
class RustDocument {
  /// Validates a bounded v1 to v5 file and owns a NEW document on success. The
  /// caller keeps its current document untouched until it chooses to replace
  /// it. For a project with an image the caller must also decode the
  /// background before adoption: native PNG validation checks structure and
  /// CRCs, not compressed pixels. A file of a later format than this program
  /// knows is refused with a [NewerProjectException].
  factory RustDocument.fromProject(Uint8List bytes, {String? libraryPath}) {
    if (bytes.length < 36 || bytes.length > maxProjectBytes) {
      throw const FormatException('La taille de ce projet Color est invalide.');
    }
    final path = libraryPath ?? defaultLibraryPath;
    final bindings = _Bindings(openCoreLibrary(path), path);
    Pointer<Uint8> buffer = nullptr;
    Pointer<_EpDocument> handle = nullptr;
    final status = calloc<Int32>();
    try {
      buffer = calloc<Uint8>(bytes.length);
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      handle = bindings.fromProject(buffer, bytes.length, status);
      if (handle == nullptr) {
        if (status.value == -2) {
          throw const RustCoreException('l’ouverture du projet', -2);
        }
        throw _projectRefusal(bytes);
      }
    } finally {
      calloc.free(status);
      calloc.free(buffer);
    }
    // Exactly one snapshot after the complete native import, never one per
    // imported stroke. Any failure releases this candidate, not the old doc.
    final document = RustDocument._(
      bindings,
      handle,
      bindings.width(handle),
      bindings.height(handle),
    );
    try {
      if (document.width < 1 ||
          document.width > 16384 ||
          document.height < 1 ||
          document.height > 16384) {
        throw StateError(
          'Dimensions du projet incompatibles avec le contrat C.',
        );
      }
      document._refresh();
      return document;
    } catch (_) {
      document.dispose();
      rethrow;
    }
  }

  /// Reads, validates and fills a private candidate off the calling isolate.
  /// The caller still must decode the transferred PNG before UI adoption.
  /// Owns the native allocation through worker exit, without any finalizer.
  static Future<PreparedProject> loadProjectFile(
    String projectPath, {
    String? libraryPath,
  }) =>
      _loadPreparedProject(projectPath: projectPath, libraryPath: libraryPath);

  /// Detached in-memory input, mainly for injected file providers/tests. Creating
  /// the transferable is an O(bytes) copy on this caller; real files must use
  /// loadProjectFile, whose reader allocates and copies only in its worker.
  static Future<PreparedProject> loadProjectBytes(
    Uint8List bytes, {
    String? libraryPath,
  }) {
    if (bytes.length < 36 || bytes.length > maxProjectBytes) {
      throw const FormatException('La taille de ce projet Color est invalide.');
    }
    final input = TransferableTypedData.fromList([bytes]);
    return _loadPreparedProject(input: input, libraryPath: libraryPath);
  }

  static Future<PreparedProject> _loadPreparedProject({
    String? projectPath,
    TransferableTypedData? input,
    String? libraryPath,
  }) async {
    final path = libraryPath ?? defaultLibraryPath;
    final bindings = _Bindings(openCoreLibrary(path), path);
    var candidate = bindings.create(1, 1);
    if (candidate == nullptr) {
      throw const RustCoreException('la préparation de l’ouverture', -2);
    }
    try {
      final loaded =
          await runBorrowedIsolate<_ProjectLoadRequest, _ProjectLoadResult>(
            _projectLoadWorker,
            _ProjectLoadRequest(path, candidate.address, projectPath, input),
            debugName: 'Color project loading',
          );
      // The worker has exited. This parent owns the same allocation throughout.
      if (loaded.width < 1 ||
          loaded.width > 16384 ||
          loaded.height < 1 ||
          loaded.height > 16384 ||
          loaded.width != bindings.width(candidate) ||
          loaded.height != bindings.height(candidate)) {
        throw StateError(
          'Dimensions du projet incompatibles avec le contrat C.',
        );
      }
      final document = RustDocument._(
        bindings,
        candidate,
        loaded.width,
        loaded.height,
      );
      document._installCache(loaded.cache);
      document._backgroundInfo = loaded.backgroundInfo;
      document._backgroundInfoLoaded = true;
      final prepared = PreparedProject._(document, loaded.background);
      candidate =
          nullptr; // Ownership has moved only within this parent isolate.
      return prepared;
    } finally {
      // Includes worker errors, unsendable results and wrapper-construction errors.
      if (candidate != nullptr) bindings.free(candidate);
    }
  }

  /// Owns a new document whose immutable background is a canonical sRGB PNG.
  /// The caller must normalize and successfully decode the PNG first. Native
  /// validation checks bounded structure/CRCs, never decompresses pixels and
  /// cannot establish that an untagged image was actually converted to sRGB.
  factory RustDocument.fromBackgroundPng(
    Uint8List bytes, {
    String? libraryPath,
  }) {
    if (bytes.length < 57 || bytes.length > maxBackgroundBytes) {
      throw const FormatException('La taille de cette image est invalide.');
    }
    final path = libraryPath ?? defaultLibraryPath;
    final bindings = _Bindings(openCoreLibrary(path), path);
    Pointer<Uint8> buffer = nullptr;
    Pointer<_EpDocument> handle = nullptr;
    final status = calloc<Int32>();
    try {
      buffer = calloc<Uint8>(bytes.length);
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      handle = bindings.fromBackgroundPng(buffer, bytes.length, status);
      if (handle == nullptr) {
        if (status.value == -2) {
          throw const RustCoreException('l’importation de l’image', -2);
        }
        throw const FormatException(
          'Cette image PNG ne respecte pas le format normalisé de Color.',
        );
      }
    } finally {
      calloc.free(status);
      calloc.free(buffer);
    }
    final document = RustDocument._(
      bindings,
      handle,
      bindings.width(handle),
      bindings.height(handle),
    );
    try {
      if (document.backgroundInfo == null) {
        throw StateError('Le cœur n’a pas conservé le fond du document.');
      }
      document._refresh();
      return document;
    } catch (_) {
      document.dispose();
      rethrow;
    }
  }

  /// Owns a NEW document made of the colouring page [id] of the core, on the
  /// sheet of the page: under the layer where the child draws, which is
  /// active and empty, a locked layer holds the zones of the page; above it,
  /// another holds its lines. Nothing of the page is in the history: the
  /// document starts without a step to undo, and no undo takes the page
  /// away. The identifiers are those of [readPageCatalog], valid for this
  /// library only.
  factory RustDocument.fromPage(int id, {String? libraryPath}) {
    // The identifier is a 32-bit parameter: a larger number must not reach
    // it, which would silently keep its low bits.
    if (id < 0 || id > 0xffffffff) {
      throw ArgumentError('Page à colorier inconnue.');
    }
    final path = libraryPath ?? defaultLibraryPath;
    final bindings = _Bindings(openCoreLibrary(path), path);
    final handle = bindings.fromPage(id);
    if (handle == nullptr) {
      // An unknown page or a memory exhausted: the core says no more.
      throw StateError(
        'Le cœur ne peut pas préparer cette page à colorier : page inconnue '
        'ou mémoire insuffisante.',
      );
    }
    final document = RustDocument._(
      bindings,
      handle,
      bindings.width(handle),
      bindings.height(handle),
    );
    try {
      if (document.width < 1 ||
          document.width > 16384 ||
          document.height < 1 ||
          document.height > 16384) {
        throw StateError(
          'Dimensions de la page incompatibles avec le contrat C.',
        );
      }
      document._refresh();
      return document;
    } catch (_) {
      document.dispose();
      rethrow;
    }
  }

  factory RustDocument({
    String? libraryPath,
    int width = 1200,
    int height = 800,
  }) {
    if (width < 1 || width > 16384 || height < 1 || height > 16384) {
      throw ArgumentError('Dimensions de document hors limites.');
    }
    final path = libraryPath ?? defaultLibraryPath;
    final bindings = _Bindings(openCoreLibrary(path), path);
    final handle = bindings.create(width, height);
    if (handle == nullptr) {
      throw StateError('Le cœur Rust ne peut pas créer le document.');
    }
    final document = RustDocument._(bindings, handle, width, height);
    try {
      if (bindings.width(handle) != width ||
          bindings.height(handle) != height) {
        throw StateError('Dimensions du cœur incompatibles.');
      }
      document._refresh();
      return document;
    } catch (_) {
      document.dispose();
      rethrow;
    }
  }

  RustDocument._(this._bindings, this._handle, this.width, this.height);
  final _Bindings _bindings;
  Pointer<_EpDocument> _handle;
  final int width;
  final int height;
  List<StrokeData> _strokes = const [];
  Map<int, StrokeData> _snapshotByRevision = {};
  List<LayerData> _layers = const [];
  List<int> _paintOrder = const [];
  Set<int> _lockedLayers = const {};
  List<int> _unlockedPaintOrder = const [];
  List<int> _madePaintOrder = const [];
  int _madeCount = 0;
  int _activeLayer = 0;
  int _paperRgb = whitePaper;
  int _redoCount = 0;
  int _undoCount = 0;
  int _exportJobs = 0;
  bool _backgroundInfoLoaded = false;
  BackgroundInfo? _backgroundInfo;

  static String get defaultLibraryPath {
    final configured = Platform.environment['EDUPAINT_CORE_LIBRARY'];
    if (configured != null && configured.isNotEmpty) return configured;
    final executable = File(Platform.resolvedExecutable).parent;
    if (Platform.isMacOS) {
      return '${executable.parent.path}/Frameworks/libedupaint_core.dylib';
    }
    if (Platform.isWindows) return '${executable.path}\\edupaint_core.dll';
    if (Platform.isLinux) return '${executable.path}/lib/libedupaint_core.so';
    // iPhone and iPad: the core is linked into the application itself.
    if (Platform.isIOS) return processCoreLibrary;
    // Android: the system finds the library of the application by its name.
    if (Platform.isAndroid) return 'libedupaint_core.so';
    throw UnsupportedError(
      'Color ne sait pas où trouver son cœur sur ce système.',
    );
  }

  void _checkAlive() {
    if (_handle == nullptr) throw StateError('Document déjà libéré.');
  }

  List<StrokeData> get strokes {
    _checkAlive();
    return _strokes;
  }

  int get count => strokes.length;

  /// Layers from the bottom of the stack to its top.
  List<LayerData> get layers {
    _checkAlive();
    return _layers;
  }

  /// Identifier of the layer that receives new objects.
  int get activeLayer {
    _checkAlive();
    return _activeLayer;
  }

  /// Indices of the objects of visible layers, in painting order: bottom
  /// layer first, and inside a layer in object order. Hidden layers are
  /// absent, so painting, hit testing and image exports share one sequence.
  List<int> get paintOrder {
    _checkAlive();
    return _paintOrder;
  }

  /// [paintOrder] without the objects of locked layers: what the child has
  /// drawn and can still change, never the page. The same list as
  /// [paintOrder] when no layer is locked.
  List<int> get unlockedPaintOrder {
    _checkAlive();
    return _unlockedPaintOrder;
  }

  /// Identifiers of the locked layers: those of a colouring page.
  Set<int> get lockedLayers {
    _checkAlive();
    return _lockedLayers;
  }

  /// Whether the layer [id] is locked: one of a colouring page.
  bool isLockedLayer(int id) => lockedLayers.contains(id);

  /// Whether the object at [index] lies on a locked layer: it belongs to a
  /// colouring page, and only the colour of its inside may change.
  bool isLockedObject(int index) {
    final locked = lockedLayers;
    return locked.isNotEmpty && locked.contains(strokes[index].layer);
  }

  /// Whether the object at [index] is a zone of a colouring page that the
  /// paint pot coloured: on a locked layer, with an inside that is no longer
  /// the white of the page.
  bool isColouredZone(int index) =>
      isLockedObject(index) && strokes[index].colouredInside;

  /// [paintOrder] of what the child made: the objects of the layers that are
  /// not locked, and the zones of a colouring page that the paint pot
  /// coloured. What the film of the drawing has to show; the same list as
  /// [paintOrder] when no layer is locked.
  List<int> get madePaintOrder {
    _checkAlive();
    return _madePaintOrder;
  }

  /// How many objects the child made, on every layer, shown or hidden: all
  /// of them on a sheet without a page; on a colouring page, those of the
  /// layers that are not locked and the zones that the paint pot coloured,
  /// never the untouched zones nor the lines of the page. The number that
  /// the studio shows to the child.
  int get madeCount {
    _checkAlive();
    return _madeCount;
  }

  /// Colour of the sheet under the whole drawing; white for a new sheet.
  int get paperRgb {
    _checkAlive();
    return _paperRgb;
  }

  /// Objects of visible layers in painting order, for image exports.
  List<StrokeData> get visibleStrokes => [
    for (final index in paintOrder) _strokes[index],
  ];

  /// The catalogue text of the core: one stamp per line. See stamp_catalog.dart.
  static String readStampCatalog({String? libraryPath}) {
    final path = libraryPath ?? defaultLibraryPath;
    final bindings = _Bindings(openCoreLibrary(path), path);
    final text = bindings.stampCatalog();
    if (text == nullptr) {
      throw StateError('Le cœur ne peut pas fournir les tampons.');
    }
    try {
      final catalog = text.toDartString();
      // One line per stamp: the count the core announces is the count of
      // lines it wrote, or this library is not the one this program knows.
      final lines = catalog.split('\n').where((line) => line.isNotEmpty);
      if (lines.length != bindings.stampCount()) {
        throw StateError('Le catalogue de tampons du cœur est incohérent.');
      }
      return catalog;
    } finally {
      bindings.freeString(text); // Rust allocation: never free with calloc.
    }
  }

  // The functions below use no document: one set of bindings serves them
  // for the life of the process.
  static _Bindings? _processBindings;
  static _Bindings _process(String? libraryPath) {
    if (libraryPath != null) {
      return _Bindings(openCoreLibrary(libraryPath), libraryPath);
    }
    final path = defaultLibraryPath;
    final known = _processBindings;
    if (known != null && known.path == path) return known;
    return _processBindings = _Bindings(openCoreLibrary(path), path);
  }

  /// The pictures of the interface as the core describes them: one
  /// description after the other. See vector_art.dart.
  static String readArtCatalog({String? libraryPath}) {
    final bindings = _process(libraryPath);
    final text = bindings.artCatalog();
    if (text == nullptr) {
      throw StateError(
        'Le cœur ne peut pas fournir les dessins de l’interface.',
      );
    }
    try {
      final catalog = text.toDartString();
      // One « P » line per picture: the count the core announces is the
      // count of pictures it described.
      final pictures = catalog
          .split('\n')
          .where((line) => line.startsWith('P '))
          .length;
      if (pictures != bindings.artCount()) {
        throw StateError(
          'Les dessins de l’interface du cœur sont incohérents.',
        );
      }
      return catalog;
    } finally {
      bindings.freeString(text); // Rust allocation: never free with calloc.
    }
  }

  /// The colouring pages of the core: for each one a « T » line, then its
  /// thumbnail in the format of [readArtCatalog]. See coloring_pages.dart.
  /// Throws when the library has no pages to give: one older than this
  /// interface, or one built without its pictures.
  static String readPageCatalog({String? libraryPath}) {
    final bindings = _process(libraryPath);
    final text = bindings.pageCatalog();
    if (text == nullptr) {
      throw StateError('Le cœur ne peut pas fournir les pages à colorier.');
    }
    try {
      // ASCII by contract; the accents of the titles travel as %XX.
      final catalog = text.toDartString();
      // One « T » line per page: the count the core announces is the count
      // of pages it described.
      final pages = catalog
          .split('\n')
          .where((line) => line.startsWith('T '))
          .length;
      if (pages != bindings.pageCount()) {
        throw StateError('Les pages à colorier du cœur sont incohérentes.');
      }
      return catalog;
    } finally {
      bindings.freeString(text); // Rust allocation: never free with calloc.
    }
  }

  /// The description of one SVG text, in the format of [readArtCatalog], or
  /// null when the core refuses it: not an SVG it reads, or one that uses
  /// what this version does not draw. Nothing the SVG refers to is opened.
  static String? describeSvg(String svg, {String? libraryPath}) {
    final bindings = _process(libraryPath);
    final bytes = utf8.encode(svg);
    final input = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final text = bindings.pictureFromSvg(input, bytes.length);
      if (text == nullptr) return null;
      try {
        return text.toDartString();
      } finally {
        bindings.freeString(text);
      }
    } finally {
      calloc.free(input);
    }
  }

  /// The notices of the libraries the core is built from, as the core
  /// carries them: entries separated by a line of eighty hyphens, each one
  /// the name of a library, an empty line, then its notice. Empty for a core
  /// that has no library, or none to name.
  static String thirdPartyNotices({String? libraryPath}) {
    final bindings = _process(libraryPath);
    final text = bindings.thirdPartyNotices();
    if (text == nullptr) return '';
    try {
      return text.toDartString();
    } finally {
      bindings.freeString(text); // Rust allocation: never free with calloc.
    }
  }

  /// The keys of the sounds of the core, in identifier order.
  static List<String> soundNames({String? libraryPath}) {
    final bindings = _process(libraryPath);
    final text = bindings.soundNames();
    if (text == nullptr) {
      throw StateError('Le cœur ne peut pas nommer ses sons.');
    }
    try {
      final names = <String>[];
      for (final line in text.toDartString().split('\n')) {
        if (line.isEmpty) continue;
        final fields = line.split('|');
        if (fields.length != 2 || int.tryParse(fields[0]) != names.length) {
          throw StateError('La liste des sons du cœur est incohérente.');
        }
        names.add(fields[1]);
      }
      if (names.length != bindings.soundCount()) {
        throw StateError('La liste des sons du cœur est incohérente.');
      }
      return names;
    } finally {
      bindings.freeString(text);
    }
  }

  /// The complete WAV file of one sound, owned by Dart; null for an
  /// identifier the core does not know.
  static Uint8List? soundWav(int id, {String? libraryPath}) {
    final bindings = _process(libraryPath);
    final size = bindings.soundWavSize(id);
    if (size == 0) return null;
    final buffer = calloc<Uint8>(size);
    try {
      if (bindings.copySoundWav(id, buffer, size) != size) return null;
      return Uint8List.fromList(buffer.asTypedList(size));
    } finally {
      calloc.free(buffer);
    }
  }

  /// Asks the core to play one sound through the system, without waiting.
  /// 0 handed to the system, 1 no player in the core on this system (the
  /// caller plays the WAV itself), -1 unknown identifier.
  static int playSound(int id, {String? libraryPath}) =>
      _process(libraryPath).soundPlay(id);

  /// Cached independently from vector snapshots because the background never
  /// changes for the lifetime of this document. No PNG bytes are copied here.
  BackgroundInfo? get backgroundInfo {
    _checkAlive();
    if (_backgroundInfoLoaded) return _backgroundInfo;
    final info = calloc<_EpBackgroundInfo>();
    try {
      final result = _bindings.backgroundInfo(_handle, info);
      if (result == 1) {
        final value = info.ref;
        if (value.width < 1 ||
            value.width > maxBackgroundDimension ||
            value.height < 1 ||
            value.height > maxBackgroundDimension ||
            value.width * value.height > maxBackgroundPixels ||
            value.width != width ||
            value.height != height ||
            value.byteCount < 57 ||
            value.byteCount > maxBackgroundBytes) {
          throw StateError('Le fond du projet viole le contrat C.');
        }
        _backgroundInfo = BackgroundInfo(
          width: value.width,
          height: value.height,
          byteCount: value.byteCount,
        );
      } else if (result != 0) {
        throw RustCoreException('la lecture des informations du fond', result);
      }
      _backgroundInfoLoaded = true;
      return _backgroundInfo;
    } finally {
      calloc.free(info);
    }
  }

  /// Returns detached bytes owned by Dart, or null for a vector-only document.
  /// Copy once for decoding; do not call this during painting or vector edits.
  Uint8List? copyBackgroundPng() {
    final info = backgroundInfo;
    if (info == null) return null;
    final buffer = calloc<Uint8>(info.byteCount);
    try {
      final copied = _bindings.copyBackgroundPng(
        _handle,
        buffer,
        info.byteCount,
      );
      if (copied != info.byteCount) {
        throw StateError('Le cœur n’a pas copié le fond complet.');
      }
      return Uint8List.fromList(buffer.asTypedList(copied));
    } finally {
      calloc.free(buffer);
    }
  }

  /// Cached native command counts, independent from visible object count.
  int get undoCount {
    _checkAlive();
    return _undoCount;
  }

  int get redoCount {
    _checkAlive();
    return _redoCount;
  }

  bool get canUndo {
    _checkAlive();
    return _undoCount > 0;
  }

  bool get canRedo {
    _checkAlive();
    return _redoCount > 0;
  }

  void addStroke(
    List<DocumentPoint> points, {
    required int rgb,
    required double width,
  }) {
    _checkAlive();
    if (points.isEmpty ||
        points.length > 100000 ||
        rgb < 0 ||
        rgb > 0xffffff ||
        !width.isFinite ||
        points.any((p) => !p.x.isFinite || !p.y.isFinite)) {
      throw ArgumentError('Trait non valide. Le document est inchangé.');
    }
    final buffer = calloc<_EpPoint>(points.length);
    try {
      for (var i = 0; i < points.length; i++) {
        buffer[i].x = points[i].x;
        buffer[i].y = points[i].y;
      }
      final result = _bindings.add(_handle, buffer, points.length, rgb, width);
      if (result != 0) throw RustCoreException('ce trait', result);
    } finally {
      calloc.free(buffer);
    }
    _refresh();
  }

  /// Adds an exact vector primitive. Rectangles and ellipses use opposite
  /// corners in either order. The Rust core also validates degenerate geometry.
  /// A contour has three points or more: no shape of two points makes one.
  void addShape(
    VectorKind kind,
    DocumentPoint start,
    DocumentPoint end, {
    required int rgb,
    required double width,
    int? fillRgb,
  }) {
    _checkAlive();
    if (kind == VectorKind.stroke ||
        kind == VectorKind.contour ||
        rgb < 0 ||
        rgb > 0xffffff ||
        !width.isFinite ||
        !start.x.isFinite ||
        !start.y.isFinite ||
        !end.x.isFinite ||
        !end.y.isFinite ||
        (fillRgb != null &&
            (fillRgb < 0 || fillRgb > 0xffffff || kind == VectorKind.line))) {
      throw ArgumentError('Forme non valide. Le document est inchangé.');
    }
    final style = calloc<_EpObjectStyle>();
    Pointer<_EpPoint> points = nullptr;
    try {
      points = calloc<_EpPoint>(2);
      points[0].x = start.x;
      points[0].y = start.y;
      points[1].x = end.x;
      points[1].y = end.y;
      style.ref.kind = kind.index;
      style.ref.fillEnabled = fillRgb == null ? 0 : 1;
      style.ref.fillRgb = fillRgb ?? 0;
      final result = _bindings.addShape(_handle, points, style, rgb, width);
      if (result != 0) {
        throw RustCoreException('cette forme', result);
      }
    } finally {
      calloc.free(points);
      calloc.free(style);
    }
    _refresh();
  }

  /// Fills two native corner points; the caller frees the returned buffer.
  Pointer<_EpPoint> _corners(DocumentPoint first, DocumentPoint second) {
    final points = calloc<_EpPoint>(2);
    points[0].x = first.x;
    points[0].y = first.y;
    points[1].x = second.x;
    points[1].y = second.y;
    return points;
  }

  static bool _validBox(DocumentPoint first, DocumentPoint second) =>
      first.x.isFinite &&
      first.y.isFinite &&
      second.x.isFinite &&
      second.y.isFinite;

  /// Adds a text whose laid-out box has the two given opposite corners.
  /// [text] must already be normalized: see normalizeTextInput.
  void addText(
    DocumentPoint first,
    DocumentPoint second, {
    required String text,
    required int rgb,
    required double size,
  }) {
    _checkAlive();
    final encoded = utf8.encode(text);
    if (!_validBox(first, second) ||
        rgb < 0 ||
        rgb > 0xffffff ||
        !size.isFinite ||
        encoded.isEmpty ||
        encoded.length > maxTextBytes) {
      throw ArgumentError('Texte non valide. Le document est inchangé.');
    }
    Pointer<_EpPoint> points = nullptr;
    Pointer<Uint8> bytes = nullptr;
    try {
      points = _corners(first, second);
      bytes = calloc<Uint8>(encoded.length);
      bytes.asTypedList(encoded.length).setAll(0, encoded);
      final result = _bindings.addText(
        _handle,
        points,
        rgb,
        size,
        0,
        bytes,
        encoded.length,
      );
      if (result != 0) throw RustCoreException('ce texte', result);
    } finally {
      calloc.free(bytes);
      calloc.free(points);
    }
    _refresh();
  }

  /// Replaces characters, box, colour and size of a text in one undo step.
  /// Returns false when nothing changed.
  bool setText(
    int index,
    DocumentPoint first,
    DocumentPoint second, {
    required String text,
    required int rgb,
    required double size,
  }) {
    _checkIndex(index);
    final encoded = utf8.encode(text);
    if (!_validBox(first, second) ||
        rgb < 0 ||
        rgb > 0xffffff ||
        !size.isFinite ||
        encoded.isEmpty ||
        encoded.length > maxTextBytes) {
      throw ArgumentError('Texte non valide. Le document est inchangé.');
    }
    Pointer<_EpPoint> points = nullptr;
    Pointer<Uint8> bytes = nullptr;
    try {
      points = _corners(first, second);
      bytes = calloc<Uint8>(encoded.length);
      bytes.asTypedList(encoded.length).setAll(0, encoded);
      return _finishObjectChange(
        _bindings.setText(
          _handle,
          index,
          points,
          rgb,
          size,
          0,
          bytes,
          encoded.length,
        ),
        'la modification du texte',
      );
    } finally {
      calloc.free(bytes);
      calloc.free(points);
    }
  }

  /// Adds the catalogue stamp [stamp], scaled into the box of two corners.
  void addStamp(
    DocumentPoint first,
    DocumentPoint second, {
    required int stamp,
    required int rgb,
  }) {
    _checkAlive();
    if (!_validBox(first, second) ||
        stamp < 0 ||
        stamp > 0xffffffff ||
        rgb < 0 ||
        rgb > 0xffffff) {
      throw ArgumentError('Tampon non valide. Le document est inchangé.');
    }
    Pointer<_EpPoint> points = nullptr;
    try {
      points = _corners(first, second);
      final result = _bindings.addStamp(_handle, points, stamp, rgb);
      if (result != 0) throw RustCoreException('ce tampon', result);
    } finally {
      calloc.free(points);
    }
    _refresh();
  }

  void _checkLayerPosition(int position) {
    _checkAlive();
    if (position < 0 || position >= _layers.length) {
      throw RangeError.index(position, _layers);
    }
  }

  /// Chooses where new objects go. Not an edit: nothing to undo or save.
  /// A locked layer never receives them: the core refuses it.
  void setActiveLayer(int id) {
    _checkAlive();
    if (_lockedLayers.contains(id)) {
      throw ArgumentError(
        'Ce calque est verrouillé : on ne dessine pas dessus.',
      );
    }
    // An identifier is one of 0..15; a larger number must not reach the
    // 32-bit parameter, which would silently keep its low bits.
    if (id < 0 ||
        id >= maxLayers ||
        _bindings.setActiveLayer(_handle, id) != 0) {
      throw ArgumentError('Calque inconnu.');
    }
    _activeLayer = id;
  }

  /// Adds an empty layer above the active one and makes it active.
  void addLayer() {
    _checkAlive();
    final result = _bindings.addLayer(_handle);
    if (result != 1) throw RustCoreException('l’ajout du calque', result);
    _refresh();
  }

  /// Removes a layer and its objects; undo restores both.
  void removeLayer(int position) {
    _checkLayerPosition(position);
    final result = _bindings.removeLayer(_handle, position);
    if (result != 1) {
      throw RustCoreException('la suppression du calque', result);
    }
    _refresh();
  }

  bool reorderLayer(int from, int to) {
    _checkLayerPosition(from);
    _checkLayerPosition(to);
    return _finishObjectChange(
      _bindings.reorderLayer(_handle, from, to),
      'le déplacement du calque',
    );
  }

  bool setLayerVisible(int position, bool visible) {
    _checkLayerPosition(position);
    return _finishObjectChange(
      _bindings.setLayerVisible(_handle, position, visible ? 1 : 0),
      'l’affichage du calque',
    );
  }

  /// Moves an object in front of the objects of another layer. Its index
  /// becomes the last one.
  bool setObjectLayer(int index, int layerId) {
    _checkIndex(index);
    if (layerId < 0 || layerId >= maxLayers) {
      throw ArgumentError('Calque inconnu.');
    }
    return _finishObjectChange(
      _bindings.setObjectLayer(_handle, index, layerId),
      'le changement de calque',
    );
  }

  /// Colours the sheet in one undo step. Returns false for the same colour.
  bool setPaperColor(int rgb) {
    _checkAlive();
    if (rgb < 0 || rgb > 0xffffff) throw ArgumentError('Couleur invalide.');
    return _finishObjectChange(
      _bindings.setPaperColor(_handle, rgb),
      'la couleur de la feuille',
    );
  }

  /// Resizes an object around its centre in one undo step; the core keeps it
  /// whole on the sheet. [width] is its new outline width (a stamp keeps 1).
  /// Texts are resized with setText, from a freshly measured box. Returns
  /// false when nothing changes; throws when the object would not fit.
  bool scaleObject(int index, double factor, {required double width}) {
    _checkIndex(index);
    if (!factor.isFinite || factor <= 0 || !width.isFinite) {
      throw ArgumentError('Taille invalide.');
    }
    return _finishObjectChange(
      _bindings.scaleObject(_handle, index, factor, width),
      'le changement de taille',
    );
  }

  void _checkIndex(int index) {
    _checkAlive();
    if (index < 0 || index >= count) throw RangeError.index(index, _strokes);
  }

  bool _finishObjectChange(int result, String operation) {
    if (result < 0) throw RustCoreException(operation, result);
    if (result > 1) throw StateError('Réponse de modification inattendue.');
    if (result == 1) _refresh();
    return result == 1;
  }

  /// A UI gesture can request native clamping at commit time. The core owns
  /// higher-precision transforms, so rounded Dart snapshots cannot determine
  /// the exact available distance at a page edge.
  bool moveObject(int index, double dx, double dy, {bool constrain = false}) {
    _checkIndex(index);
    if (!dx.isFinite || !dy.isFinite) {
      throw ArgumentError('Déplacement invalide.');
    }
    if (constrain) {
      final delta = _constrainMovement(index, dx, dy);
      dx = delta.dx;
      dy = delta.dy;
    }
    return _finishObjectChange(
      _bindings.moveObject(_handle, index, dx, dy),
      'le déplacement',
    );
  }

  /// Repositions an object at its final index: zero is backmost, count - 1
  /// frontmost. Content revisions are preserved, so cached StrokeData and their
  /// point lists are reused; only the ordered snapshot list changes.
  bool reorderObject(int from, int to) {
    _checkIndex(from);
    _checkIndex(to);
    return _finishObjectChange(
      _bindings.reorderObject(_handle, from, to),
      'le changement d’ordre',
    );
  }

  bool removeObject(int index) {
    _checkIndex(index);
    return _finishObjectChange(
      _bindings.removeObject(_handle, index),
      'la suppression',
    );
  }

  bool duplicateObject(
    int index,
    double dx,
    double dy, {
    bool constrain = false,
  }) {
    _checkIndex(index);
    if (!dx.isFinite || !dy.isFinite) {
      throw ArgumentError('Déplacement invalide.');
    }
    if (constrain) {
      final delta = _constrainMovement(index, dx, dy);
      dx = delta.dx;
      dy = delta.dy;
    }
    return _finishObjectChange(
      _bindings.duplicateObject(_handle, index, dx, dy),
      'la copie',
    );
  }

  ({double dx, double dy}) _constrainMovement(int index, double dx, double dy) {
    final output = calloc<_EpPoint>();
    try {
      final result = _bindings.constrainObjectMovement(
        _handle,
        index,
        dx,
        dy,
        output,
      );
      if (result != 0) {
        throw RustCoreException('le déplacement dans la feuille', result);
      }
      return (dx: output.ref.x, dy: output.ref.y);
    } finally {
      calloc.free(output);
    }
  }

  bool setObjectStyle(
    int index, {
    required int rgb,
    required double width,
    int? fillRgb,
  }) {
    _checkIndex(index);
    if (rgb < 0 ||
        rgb > 0xffffff ||
        !width.isFinite ||
        (fillRgb != null && (fillRgb < 0 || fillRgb > 0xffffff))) {
      throw ArgumentError('Style invalide.');
    }
    return _finishObjectChange(
      _bindings.setObjectStyle(
        _handle,
        index,
        rgb,
        width,
        fillRgb == null ? 0 : 1,
        fillRgb ?? 0,
      ),
      'le changement de style',
    );
  }

  bool undo() => _changeHistory(_bindings.undo, 'l’annulation');
  bool redo() => _changeHistory(_bindings.redo, 'le rétablissement');

  bool _changeHistory(
    int Function(Pointer<_EpDocument>) operation,
    String name,
  ) {
    _checkAlive();
    final result = operation(_handle);
    if (result < 0) throw RustCoreException(name, result);
    if (result > 1) {
      throw StateError('Réponse d’historique inattendue : $result.');
    }
    if (result == 1) _refresh();
    return result == 1;
  }

  // Refresh only changed objects after a mutation, never during a frame paint.
  void _refresh() {
    _checkAlive();
    _installCache(_readDocumentCache(_bindings, _handle, _snapshotByRevision));
  }

  void _installCache(_DocumentCache cache) {
    _strokes = cache.strokes;
    _snapshotByRevision = cache.byRevision;
    _layers = cache.layers;
    _paintOrder = cache.paintOrder;
    final locked = {
      for (final layer in cache.layers)
        if (layer.locked) layer.id,
    };
    _lockedLayers = Set.unmodifiable(locked);
    if (locked.isEmpty) {
      _unlockedPaintOrder = cache.paintOrder;
      _madePaintOrder = cache.paintOrder;
      _madeCount = cache.strokes.length;
    } else {
      final strokes = cache.strokes;
      _unlockedPaintOrder = List.unmodifiable([
        for (final index in cache.paintOrder)
          if (!locked.contains(strokes[index].layer)) index,
      ]);
      bool made(StrokeData object) =>
          !locked.contains(object.layer) || object.colouredInside;
      _madePaintOrder = List.unmodifiable([
        for (final index in cache.paintOrder)
          if (made(strokes[index])) index,
      ]);
      _madeCount = strokes.where(made).length;
    }
    _activeLayer = cache.activeLayer;
    _paperRgb = cache.paperRgb;
    _undoCount = cache.undo;
    _redoCount = cache.redo;
  }

  /// Captures the visible document before the first await. The worker never
  /// receives this mutable document: it borrows a separately owned snapshot.
  /// The caller may edit or dispose this document while the export proceeds.
  Future<Uint8List> exportProjectAsync() => _exportSnapshot(svg: false);

  /// Produces UTF-8 bytes off the caller's isolate, without a large intermediate
  /// Dart String or UTF-8 conversion on the interactive path.
  Future<Uint8List> exportSvgBytesAsync() => _exportSnapshot(svg: true);

  Future<Uint8List> _exportSnapshot({required bool svg}) async {
    _checkAlive();
    if (_exportJobs >= 2) {
      throw StateError('Deux préparations de ce dessin sont déjà en cours.');
    }
    _exportJobs++;
    Pointer<Int32> status = nullptr;
    Pointer<_EpExportSnapshot> snapshot = nullptr;
    try {
      status = calloc<Int32>();
      snapshot = _bindings.snapshotNew(_handle, status);
      if (snapshot == nullptr) {
        throw RustCoreException('la préparation de l’export', status.value);
      }
      final transferred = await _runExportWorker((
        path: _bindings.path,
        address: snapshot.address,
        svg: svg,
      ));
      return transferred.materialize().asUint8List();
    } finally {
      // Covers spawn failure, serialization error and successful transfer. The
      // synchronous worker has stopped borrowing before its future completes.
      if (snapshot != nullptr) _bindings.snapshotFree(snapshot);
      calloc.free(status);
      _exportJobs--;
    }
  }

  /// Captures now, then serializes/writes/flushes a new private temporary file
  /// entirely in a worker. Returns only its byte length, never encoded bytes.
  /// The caller owns a prepared file only after this future succeeds. On error,
  /// the worker cleans only a file whose exclusive creation it completed.
  /// The existing project format and two-export snapshot bound are unchanged.
  Future<int> prepareProjectFile(String temporaryPath) async {
    _checkAlive();
    if (_exportJobs >= 2) {
      throw StateError('Deux préparations de ce dessin sont déjà en cours.');
    }
    _exportJobs++;
    Pointer<Int32> status = nullptr;
    Pointer<_EpExportSnapshot> snapshot = nullptr;
    try {
      status = calloc<Int32>();
      snapshot = _bindings.snapshotNew(_handle, status);
      if (snapshot == nullptr) {
        throw RustCoreException(
          'la préparation de la récupération',
          status.value,
        );
      }
      return await _runProjectFileWorker((
        libraryPath: _bindings.path,
        address: snapshot.address,
        temporaryPath: temporaryPath,
      ));
    } finally {
      // Isolate.run completes after its asynchronous worker has stopped borrowing.
      if (snapshot != nullptr) _bindings.snapshotFree(snapshot);
      calloc.free(status);
      _exportJobs--;
    }
  }

  String exportSvg() {
    _checkAlive();
    final text = _bindings.export(_handle);
    if (text == nullptr) {
      throw StateError('Le cœur ne peut pas préparer le SVG.');
    }
    try {
      return text.toDartString();
    } finally {
      _bindings.freeString(text); // Rust allocation: never free with calloc.
    }
  }

  /// Exact serialized project size, without serializing or copying its data.
  /// Native metadata traversal is bounded by the document's object limit.
  int get projectByteLength {
    _checkAlive();
    final size = _bindings.projectSize(_handle);
    if (size < 36 || size > maxProjectBytes) {
      throw StateError('Taille du projet incompatible avec le contrat C.');
    }
    return size;
  }

  /// Returns an independent binary project with vectors, dimensions and any PNG.
  /// Undo remains available after reopening; redo history is not persisted.
  Uint8List exportProject() {
    final size = projectByteLength;
    final buffer = calloc<Uint8>(size);
    try {
      final result = _bindings.copyProject(_handle, buffer, size);
      if (result != 0) {
        throw RustCoreException('l’enregistrement du projet', result);
      }
      return Uint8List.fromList(buffer.asTypedList(size));
    } finally {
      calloc.free(buffer);
    }
  }

  void dispose() {
    if (_handle == nullptr) return;
    _bindings.free(_handle);
    _handle = nullptr;
    _strokes = const [];
    _snapshotByRevision = {};
    _layers = const [];
    _paintOrder = const [];
    _lockedLayers = const {};
    _unlockedPaintOrder = const [];
    _madePaintOrder = const [];
    _madeCount = 0;
    _activeLayer = 0;
    _redoCount = 0;
    _undoCount = 0;
    _backgroundInfo = null;
    _backgroundInfoLoaded = false;
  }
}

typedef _ProjectFileRequest = ({
  String libraryPath,
  int address,
  String temporaryPath,
});

// Top-level scope captures only a sendable record, never the mutable document,
// the store, its callbacks or a large Dart buffer from the calling isolate.
Future<int> _runProjectFileWorker(_ProjectFileRequest request) =>
    Isolate.run(() => _prepareProjectFile(request));

Future<int> _prepareProjectFile(_ProjectFileRequest request) async {
  final bindings = _Bindings(
    openCoreLibrary(request.libraryPath),
    request.libraryPath,
  );
  final snapshot = Pointer<_EpExportSnapshot>.fromAddress(request.address);
  final size = bindings.snapshotProjectSize(snapshot);
  if (size < 36 || size > maxProjectBytes) {
    throw StateError('Taille du projet incompatible avec le contrat C.');
  }
  final temporary = File(request.temporaryPath);
  Pointer<Uint8> bytes = nullptr;
  RandomAccessFile? handle;
  var created = false;
  Object? failure;
  StackTrace? failureStack;
  final cleanupErrors = <Object>[];
  try {
    bytes = calloc<Uint8>(size);
    final status = bindings.snapshotCopyProject(snapshot, bytes, size);
    if (status != 0) {
      throw RustCoreException('la copie de récupération', status);
    }
    await temporary.parent.create(recursive: true);
    await temporary.create(exclusive: true);
    created = true;
    handle = await temporary.open(mode: FileMode.writeOnly);
    await handle.writeFrom(bytes.asTypedList(size));
    await handle.flush();
  } catch (error, stack) {
    failure = error;
    failureStack = stack;
  } finally {
    if (handle != null) {
      try {
        await handle.close();
      } catch (error, stack) {
        if (failure == null) {
          failure = error;
          failureStack = stack;
        } else {
          cleanupErrors.add(error);
        }
      }
    }
    calloc.free(bytes);
    if (failure != null && created) {
      try {
        await temporary.delete();
      } catch (error) {
        cleanupErrors.add(error);
      }
    }
  }
  if (failure != null) {
    Error.throwWithStackTrace(
      cleanupErrors.isEmpty
          ? failure
          : FileOperationCleanupException(failure, cleanupErrors),
      failureStack!,
    );
  }
  return size;
}

typedef _ExportRequest = ({String path, int address, bool svg});

// Isolate closure deliberately lives in this small top-level scope. It captures
// only a sendable record, never a RustDocument, native binding or live pointer.
Future<TransferableTypedData> _runExportWorker(_ExportRequest request) =>
    Isolate.run(() => _serializeExportSnapshot(request));

TransferableTypedData _serializeExportSnapshot(_ExportRequest request) {
  final bindings = _Bindings(openCoreLibrary(request.path), request.path);
  final snapshot = Pointer<_EpExportSnapshot>.fromAddress(request.address);
  if (request.svg) {
    final text = bindings.snapshotSvg(snapshot);
    if (text == nullptr) {
      throw StateError('Le cœur n’a pas pu préparer le SVG.');
    }
    try {
      final length = text.length;
      // Same conservative bound as the native serializer's checked reserve:
      // points, objects, layer groups, escaped characters, text lines and the
      // catalogue markup of stamps (well below 32 KiB each).
      const vectorBound =
          1000000 * 128 +
          10000 * 256 +
          512 +
          maxLayers * 64 +
          (1 << 20) * 6 +
          10000 * (256 + maxTextLines * 96) +
          10000 * 32768;
      const imageBound = ((maxBackgroundBytes + 2) ~/ 3) * 4 + 256;
      if (length < 1 || length > vectorBound + imageBound) {
        throw StateError('Taille SVG incompatible avec le contrat C.');
      }
      return TransferableTypedData.fromList([
        text.cast<Uint8>().asTypedList(length),
      ]);
    } finally {
      bindings.freeString(text);
    }
  }
  final size = bindings.snapshotProjectSize(snapshot);
  if (size < 36 || size > maxProjectBytes) {
    throw StateError('Taille du projet incompatible avec le contrat C.');
  }
  final bytes = calloc<Uint8>(size);
  try {
    final status = bindings.snapshotCopyProject(snapshot, bytes, size);
    if (status != 0) throw RustCoreException('la copie du projet', status);
    return TransferableTypedData.fromList([bytes.asTypedList(size)]);
  } finally {
    calloc.free(bytes);
  }
}

/// Owns one unadopted candidate; the background may be consumed once for decode.
/// Disposing or taking the document is explicit. There is no native finalizer.
final class PreparedProject {
  PreparedProject._(this._document, this._background);
  RustDocument? _document;
  TransferableTypedData? _background;
  bool _backgroundTaken = false;

  RustDocument get document =>
      _document ??
      (throw StateError('Le projet préparé a déjà été consommé ou libéré.'));

  TransferableTypedData? takeBackground() {
    document; // Check that this preparation is still owned.
    if (_backgroundTaken) throw StateError('Le fond a déjà été consommé.');
    _backgroundTaken = true;
    final result = _background;
    _background = null;
    return result;
  }

  RustDocument takeDocument() {
    final result = document;
    _document = null;
    _background = null;
    return result;
  }

  void dispose() {
    _document?.dispose();
    _document = null;
    _background = null;
  }
}

final class _DocumentCache {
  const _DocumentCache(
    this.strokes,
    this.byRevision,
    this.undo,
    this.redo,
    this.layers,
    this.paintOrder,
    this.activeLayer,
    this.paperRgb,
  );
  final List<StrokeData> strokes;
  final Map<int, StrokeData> byRevision;
  final int undo;
  final int redo;
  final List<LayerData> layers;
  final List<int> paintOrder;
  final int activeLayer;
  final int paperRgb;
}

_DocumentCache _readDocumentCache(
  _Bindings bindings,
  Pointer<_EpDocument> handle,
  Map<int, StrokeData> previous,
) {
  final count = bindings.count(handle);
  final redo = bindings.redoCount(handle);
  final undo = bindings.undoCount(handle);
  if (count < 0 || count > 10000) {
    throw StateError('Nombre d’objets incompatible avec le contrat C.');
  }
  // Editing an existing object creates history without adding an object.
  // The C contract bounds the whole history, including the redo branch.
  if (undo < 0 || redo < 0 || undo + redo > 50000) {
    throw StateError('Nombre de commandes incompatible avec le contrat C.');
  }
  final snapshot = <StrokeData>[];
  final revisions = <int, StrokeData>{};
  final info = calloc<_EpStrokeInfo>();
  Pointer<_EpObjectStyle> style = nullptr;
  Pointer<_EpObjectExtra> extra = nullptr;
  try {
    style = calloc<_EpObjectStyle>();
    extra = calloc<_EpObjectExtra>();
    for (var index = 0; index < count; index++) {
      final revision = bindings.objectRevision(handle, index);
      if (revision == 0 || revisions.containsKey(revision)) {
        throw StateError('Révision d’objet incompatible avec le contrat C.');
      }
      final cached = previous[revision];
      if (cached != null) {
        snapshot.add(cached);
        revisions[revision] = cached;
        continue;
      }
      if (bindings.info(handle, index, info) != 0) {
        throw StateError('Impossible de lire le trait $index.');
      }
      if (bindings.style(handle, index, style) != 0 ||
          style.ref.kind < 0 ||
          style.ref.kind >= VectorKind.values.length ||
          style.ref.fillEnabled < 0 ||
          style.ref.fillEnabled > 1) {
        throw StateError('Style incompatible avec le contrat C.');
      }
      final length = info.ref.pointCount;
      if (length < 1 || length > 100000) {
        throw StateError('Nombre de points incompatible avec le contrat C.');
      }
      final kind = VectorKind.values[style.ref.kind];
      if (bindings.objectExtra(handle, index, extra) != 0 ||
          extra.ref.layer < 0 ||
          extra.ref.layer >= maxLayers ||
          extra.ref.textBytes < 0 ||
          extra.ref.textBytes > maxTextBytes ||
          (kind == VectorKind.text) != (extra.ref.textBytes > 0) ||
          (kind.isBoxObject && length != 2) ||
          (kind == VectorKind.contour && length < 3) ||
          (style.ref.fillEnabled == 1 && !kind.canFill)) {
        throw StateError('Élément incompatible avec le contrat C.');
      }
      String? text;
      if (kind == VectorKind.text) {
        final bytes = calloc<Uint8>(extra.ref.textBytes);
        try {
          if (bindings.copyObjectText(
                handle,
                index,
                bytes,
                extra.ref.textBytes,
              ) !=
              extra.ref.textBytes) {
            throw StateError('Copie de texte incomplète.');
          }
          // The core validated this UTF-8: a malformed sequence is a defect.
          text = _decodeText(bytes.asTypedList(extra.ref.textBytes));
        } finally {
          calloc.free(bytes);
        }
      }
      final points = calloc<_EpPoint>(length);
      try {
        if (bindings.copyPoints(handle, index, points, length) != length) {
          throw StateError('Copie de points incomplète.');
        }
        snapshot.add(
          StrokeData(
            [
              for (var i = 0; i < length; i++)
                DocumentPoint(points[i].x, points[i].y),
            ],
            info.ref.rgb,
            info.ref.width,
            kind: kind,
            fillRgb: style.ref.fillEnabled == 0 ? null : style.ref.fillRgb,
            layer: extra.ref.layer,
            text: text,
            stamp: kind == VectorKind.stamp ? extra.ref.param : null,
          ),
        );
        revisions[revision] = snapshot.last;
      } finally {
        calloc.free(points);
      }
    }
  } finally {
    calloc.free(info);
    calloc.free(style);
    calloc.free(extra);
  }
  // The small layer table is read after every change: visibility and order
  // are not object revisions.
  final layerCount = bindings.layerCount(handle);
  if (layerCount < 1 || layerCount > maxLayers) {
    throw StateError('Nombre de calques incompatible avec le contrat C.');
  }
  final layers = <LayerData>[];
  final layerInfo = calloc<_EpLayerInfo>();
  try {
    for (var position = 0; position < layerCount; position++) {
      // Beside the layer's description, whose layout has no room for it.
      final locked = bindings.layerLocked(handle, position);
      if (bindings.layerInfo(handle, position, layerInfo) != 0 ||
          layerInfo.ref.id < 0 ||
          layerInfo.ref.id >= maxLayers ||
          layerInfo.ref.visible < 0 ||
          layerInfo.ref.visible > 1 ||
          (locked != 0 && locked != 1) ||
          layers.any((layer) => layer.id == layerInfo.ref.id)) {
        throw StateError('Calque incompatible avec le contrat C.');
      }
      layers.add(
        LayerData(
          id: layerInfo.ref.id,
          visible: layerInfo.ref.visible == 1,
          objectCount: layerInfo.ref.objectCount,
          locked: locked == 1,
        ),
      );
    }
  } finally {
    calloc.free(layerInfo);
  }
  final activeLayer = bindings.activeLayer(handle);
  // New objects go to the active layer: a locked one never is.
  if (!layers.any((layer) => layer.id == activeLayer && !layer.locked)) {
    throw StateError('Calque actif incompatible avec le contrat C.');
  }
  // One bucket per layer keeps this linear in the number of objects.
  final buckets = {for (final layer in layers) layer.id: <int>[]};
  for (var index = 0; index < snapshot.length; index++) {
    final bucket = buckets[snapshot[index].layer];
    if (bucket == null) {
      throw StateError('Élément sur un calque inconnu.');
    }
    bucket.add(index);
  }
  final paintOrder = <int>[
    for (final layer in layers)
      if (layer.visible) ...buckets[layer.id]!,
  ];
  final paperRgb = bindings.paperColor(handle);
  if (paperRgb < 0 || paperRgb > 0xffffff) {
    throw StateError('Couleur de feuille incompatible avec le contrat C.');
  }
  return _DocumentCache(
    List.unmodifiable(snapshot),
    Map.unmodifiable(revisions),
    undo,
    redo,
    List.unmodifiable(layers),
    List.unmodifiable(paintOrder),
    activeLayer,
    paperRgb,
  );
}

final class _ProjectLoadRequest {
  const _ProjectLoadRequest(
    this.libraryPath,
    this.address,
    this.projectPath,
    this.input,
  );
  final String libraryPath;
  final int address;
  final String? projectPath;
  final TransferableTypedData? input;
}

final class _ProjectLoadResult {
  const _ProjectLoadResult(
    this.width,
    this.height,
    this.cache,
    this.backgroundInfo,
    this.background,
  );
  final int width;
  final int height;
  final _DocumentCache cache;
  final BackgroundInfo? backgroundInfo;
  final TransferableTypedData? background;
}

void _projectLoadWorker(
  BorrowedJobInvocation<_ProjectLoadRequest> invocation,
) async {
  Object result;
  try {
    result = BorrowedJobValue(await _loadProjectInWorker(invocation.request));
  } catch (error, stack) {
    result = BorrowedJobFailure(error, stack);
  }
  // Every native/input-file cleanup is finished before this terminal call.
  // If transmission itself throws, onError plus onExit still release the owner.
  Isolate.exit(invocation.resultPort, result);
}

Future<_ProjectLoadResult> _loadProjectInWorker(
  _ProjectLoadRequest request,
) async {
  final bindings = _Bindings(
    openCoreLibrary(request.libraryPath),
    request.libraryPath,
  );
  final candidate = Pointer<_EpDocument>.fromAddress(request.address);
  final bytes = request.input != null
      ? request.input!.materialize().asUint8List()
      : await readBoundedBytes(
          request.projectPath!,
          maximumBytes: maxProjectBytes,
          tooLargeMessage: 'Le projet dépasse la taille autorisée.',
        );
  if (bytes.length < 36 || bytes.length > maxProjectBytes) {
    throw const FormatException('La taille de ce projet Color est invalide.');
  }
  final input = calloc<Uint8>(bytes.length);
  try {
    input.asTypedList(bytes.length).setAll(0, bytes);
    final status = bindings.loadProject(candidate, input, bytes.length);
    if (status == -2) {
      throw const RustCoreException('l’ouverture du projet', -2);
    }
    if (status != 0) throw _projectRefusal(bytes);
  } finally {
    calloc.free(input);
  }
  final width = bindings.width(candidate);
  final height = bindings.height(candidate);
  if (width < 1 || width > 16384 || height < 1 || height > 16384) {
    throw StateError('Dimensions du projet incompatibles avec le contrat C.');
  }
  final cache = _readDocumentCache(bindings, candidate, const {});
  final info = calloc<_EpBackgroundInfo>();
  try {
    final status = bindings.backgroundInfo(candidate, info);
    if (status == 0) {
      return _ProjectLoadResult(width, height, cache, null, null);
    }
    if (status != 1) {
      throw RustCoreException('la lecture des informations du fond', status);
    }
    final value = info.ref;
    if (value.width != width ||
        value.height != height ||
        width > maxBackgroundDimension ||
        height > maxBackgroundDimension ||
        width * height > maxBackgroundPixels ||
        value.byteCount < 57 ||
        value.byteCount > maxBackgroundBytes) {
      throw StateError('Le fond du projet viole le contrat C.');
    }
    final backgroundInfo = BackgroundInfo(
      width: width,
      height: height,
      byteCount: value.byteCount,
    );
    final output = calloc<Uint8>(value.byteCount);
    try {
      final copied = bindings.copyBackgroundPng(
        candidate,
        output,
        value.byteCount,
      );
      if (copied != value.byteCount) {
        throw StateError('Le cœur n’a pas copié le fond complet.');
      }
      // Build the transferable in the worker, directly from the native copy.
      // No intermediate full Dart PNG or preparation copy on the UI isolate.
      final background = TransferableTypedData.fromList([
        output.asTypedList(copied),
      ]);
      return _ProjectLoadResult(
        width,
        height,
        cache,
        backgroundInfo,
        background,
      );
    } finally {
      calloc.free(output);
    }
  } finally {
    calloc.free(info);
  }
}

/// Run with the real dylib: dart run lib/rust_document.dart --self-test /path/to/lib.
/// Throws on failure even when assertions are disabled. Opens no GUI.
void main(List<String> arguments) {
  if (arguments.isEmpty || arguments.first != '--self-test') {
    stdout.writeln(
      'Usage: dart run lib/rust_document.dart --self-test [library-path]',
    );
    exitCode = 64;
    return;
  }
  void check(bool value, String description) {
    if (!value) throw StateError('FAIL: $description');
  }

  final document = RustDocument(
    libraryPath: arguments.length > 1 ? arguments[1] : null,
  );
  try {
    check(
      document.width == 1200 && document.height == 800 && document.count == 0,
      'empty document',
    );
    document.addStroke(
      const [DocumentPoint(10, 20), DocumentPoint(300, 180)],
      rgb: 0x307eab,
      width: 12,
    );
    final snapshot = document.strokes;
    final svg = document.exportSvg();
    check(
      document.count == 1 && snapshot.single.points.last.x == 300,
      'FFI point buffers',
    );
    check(
      svg.contains('0 0 1200 800') && svg.contains('#307eab'),
      'SVG ownership and content',
    );
    check(document.undo() && document.count == 0 && document.canRedo, 'undo');
    check(snapshot.single.points.last.y == 180, 'detached Dart snapshot');
    check(document.redo() && document.exportSvg() == svg, 'redo preserves SVG');
    var rejected = false;
    try {
      // A finite value deliberately outside Rust's width limit reaches the ABI.
      document.addStroke(const [DocumentPoint(10, 20)], rgb: 0, width: 600);
    } on RustCoreException catch (error) {
      rejected = error.code == -1;
    }
    check(
      rejected && document.exportSvg() == svg,
      'native rejection leaves document intact',
    );
    document.undo();
    document.addStroke(const [DocumentPoint(80, 90)], rgb: 0xff0000, width: 4);
    check(
      !document.canRedo && document.exportSvg().contains('<circle'),
      'branch history and single point',
    );

    final libraryPath = arguments.length > 1 ? arguments[1] : null;
    // What uses no document: the pictures read from SVG, the sounds and the
    // notices of the libraries. A core compiled by rustc alone has none of
    // the first: the application needs the one cargo builds.
    final catalogue = RustDocument.readArtCatalog(libraryPath: libraryPath);
    check(
      catalogue.contains('P options 64 64\n') &&
          catalogue.contains('P film 64 64\n'),
      'pictures of the interface read from their SVG files',
    );
    final described = RustDocument.describeSvg(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
      '<rect width="4" height="4" fill="#ff0000"/></svg>',
      libraryPath: libraryPath,
    );
    check(
      described != null &&
          described.startsWith('P - 10 10\n') &&
          described.contains('#ff0000ff'),
      'an SVG text is described',
    );
    check(
      RustDocument.describeSvg('<svg', libraryPath: libraryPath) == null,
      'a damaged SVG is refused',
    );
    final pages = RustDocument.readPageCatalog(libraryPath: libraryPath);
    check(
      pages.startsWith('T 0 ') && pages.contains(' La fus%C3%A9e\n'),
      'colouring pages and their titles',
    );
    final coloured = RustDocument.fromPage(0, libraryPath: libraryPath);
    try {
      check(
        coloured.count > 3 &&
            !coloured.canUndo &&
            coloured.layers.map((layer) => layer.locked).join(',') ==
                'true,false,true' &&
            !coloured.isLockedLayer(coloured.activeLayer) &&
            coloured.unlockedPaintOrder.isEmpty &&
            coloured.exportProject()[8] == 5,
        'a colouring page makes its own document, locked, with nothing to undo',
      );
      var pageKept = false;
      try {
        coloured.removeObject(0);
      } on RustCoreException catch (error) {
        pageKept = error.code == -1 && coloured.isLockedObject(0);
      }
      check(pageKept, 'an object of a locked layer is not removed');
    } finally {
      coloured.dispose();
    }
    final sounds = RustDocument.soundNames(libraryPath: libraryPath);
    final wav = RustDocument.soundWav(0, libraryPath: libraryPath);
    check(
      sounds.length == 18 &&
          sounds.first == 'outil' &&
          wav != null &&
          wav.length > 44 &&
          String.fromCharCodes(wav.sublist(0, 4)) == 'RIFF',
      'sounds and the bytes of a WAV file',
    );
    check(
      RustDocument.soundWav(sounds.length, libraryPath: libraryPath) == null,
      'unknown sound',
    );
    final notices = RustDocument.thirdPartyNotices(libraryPath: libraryPath);
    check(
      notices.startsWith('arrayref\n\n') && notices.contains('\nusvg\n\nusvg '),
      'notices of the libraries of the core',
    );
    final project = document.exportProject();
    final projectSvg = document.exportSvg();
    final reopened = RustDocument.fromProject(
      project,
      libraryPath: libraryPath,
    );
    try {
      check(
        reopened.exportSvg() == projectSvg &&
            reopened.width == 1200 &&
            reopened.height == 800,
        'project preserves exact SVG and dimensions',
      );
      check(
        reopened.exportProject().join(',') == project.join(','),
        'deterministic project roundtrip',
      );
      check(
        !reopened.canRedo &&
            reopened.undo() &&
            reopened.count == 0 &&
            reopened.redo(),
        'loaded drawing supports undo and redo',
      );
      check(reopened.exportSvg() == projectSvg, 'loaded redo preserves SVG');
      project[0] ^= 1;
      check(
        reopened.exportSvg() == projectSvg,
        'loaded project owns independent points',
      );
      var corruptRejected = false;
      try {
        RustDocument.fromProject(project, libraryPath: libraryPath).dispose();
      } on FormatException {
        corruptRejected = true;
      }
      check(
        corruptRejected && document.exportSvg() == projectSvg,
        'invalid project leaves current drawing unchanged',
      );
      project[0] ^= 1;
      for (var length = 0; length < project.length; length++) {
        var truncatedRejected = false;
        try {
          RustDocument.fromProject(
            Uint8List.sublistView(project, 0, length),
            libraryPath: libraryPath,
          ).dispose();
        } on FormatException {
          truncatedRejected = true;
        }
        check(truncatedRejected, 'truncated project rejected at $length');
      }
      final withTrailing = Uint8List(project.length + 1)..setAll(0, project);
      var trailingRejected = false;
      try {
        RustDocument.fromProject(
          withTrailing,
          libraryPath: libraryPath,
        ).dispose();
      } on FormatException {
        trailingRejected = true;
      }
      check(trailingRejected, 'trailing data rejected');
      document.undo();
      final undone = RustDocument.fromProject(
        document.exportProject(),
        libraryPath: libraryPath,
      );
      try {
        check(
          undone.count == 0 && !undone.canRedo,
          'redo history intentionally excluded',
        );
      } finally {
        undone.dispose();
      }
      document.redo();
    } finally {
      reopened.dispose();
    }
    final portrait = RustDocument(
      libraryPath: libraryPath,
      width: 480,
      height: 640,
    );
    try {
      portrait.addStroke(
        const [DocumentPoint(480, 640)],
        rgb: 0xabcdef,
        width: 0.1,
      );
      final loadedPortrait = RustDocument.fromProject(
        portrait.exportProject(),
        libraryPath: libraryPath,
      );
      try {
        check(
          loadedPortrait.width == 480 &&
              loadedPortrait.height == 640 &&
              loadedPortrait.exportSvg() == portrait.exportSvg(),
          'nondefault dimensions roundtrip',
        );
      } finally {
        loadedPortrait.dispose();
      }
    } finally {
      portrait.dispose();
    }
    final shapes = RustDocument(libraryPath: libraryPath);
    try {
      shapes.addStroke(const [DocumentPoint(4, 6)], rgb: 0, width: 2);
      shapes.addShape(
        VectorKind.line,
        const DocumentPoint(10, 20),
        const DocumentPoint(50, 80),
        rgb: 0x112233,
        width: 3,
      );
      shapes.addShape(
        VectorKind.rectangle,
        const DocumentPoint(100, 120),
        const DocumentPoint(20, 30),
        rgb: 0x445566,
        width: 4,
        fillRgb: 0xaabbcc,
      );
      shapes.addShape(
        VectorKind.ellipse,
        const DocumentPoint(100, 120),
        const DocumentPoint(20, 30),
        rgb: 0x778899,
        width: 5,
        fillRgb: 0xabcdef,
      );
      final expected = shapes.exportSvg();
      check(
        shapes.strokes.map((s) => s.kind).join(',') ==
            VectorKind.values.take(4).join(','),
        'mixed vector kinds through C ABI',
      );
      check(
        shapes.strokes[2].fillRgb == 0xaabbcc &&
            shapes.strokes[1].fillRgb == null,
        'optional vector fill through C ABI',
      );
      check(
        expected.contains('<line ') &&
            expected.contains('<rect x="20" y="30" width="80" height="90"') &&
            expected.contains('<ellipse cx="60" cy="75" rx="40" ry="45"'),
        'exact SVG primitives, reversed corners',
      );
      final shapeBytes = shapes.exportProject();
      check(shapeBytes[8] == 2, 'new project version 2');
      final loadedShapes = RustDocument.fromProject(
        shapeBytes,
        libraryPath: libraryPath,
      );
      try {
        check(
          loadedShapes.exportSvg() == expected &&
              loadedShapes.strokes.last.kind == VectorKind.ellipse,
          'mixed vector project roundtrip',
        );
        check(
          loadedShapes.strokes.last.fillRgb == 0xabcdef,
          'fill preserved after reopen',
        );
        for (var i = 0; i < 4; i++) {
          check(loadedShapes.undo(), 'loaded shape undo');
        }
        for (var i = 0; i < 4; i++) {
          check(loadedShapes.redo(), 'loaded shape redo');
        }
        check(
          loadedShapes.exportSvg() == expected,
          'mixed history preserves exact SVG',
        );
      } finally {
        loadedShapes.dispose();
      }
      var degenerateRejected = false;
      try {
        shapes.addShape(
          VectorKind.ellipse,
          const DocumentPoint(10, 20),
          const DocumentPoint(10, 80),
          rgb: 0,
          width: 2,
        );
      } on RustCoreException catch (error) {
        degenerateRejected = error.code == -1;
      }
      check(
        degenerateRejected && shapes.exportSvg() == expected,
        'degenerate shape rejected without mutation',
      );
    } finally {
      shapes.dispose();
    }
    const legacyHex =
        '4544555041494e540100000040000000b0040000200300000100000002000000ccbbaa00000060400200000000004841000009420000964400004844421231d9';
    final legacy = Uint8List.fromList([
      for (var i = 0; i < legacyHex.length; i += 2)
        int.parse(legacyHex.substring(i, i + 2), radix: 16),
    ]);
    final loadedLegacy = RustDocument.fromProject(
      legacy,
      libraryPath: libraryPath,
    );
    try {
      check(
        loadedLegacy.count == 1 &&
            loadedLegacy.strokes.single.kind == VectorKind.stroke &&
            loadedLegacy.strokes.single.fillRgb == null,
        'legacy v1 imported as freehand',
      );
      check(
        loadedLegacy.exportProject()[8] == 2 &&
            loadedLegacy.exportSvg().contains('M12.5 34.25 L1200 800 '),
        'legacy project upgraded without changing geometry',
      );
    } finally {
      loadedLegacy.dispose();
    }
    final layered = RustDocument(libraryPath: libraryPath);
    try {
      check(
        layered.layers.length == 1 &&
            layered.layers.single.visible &&
            layered.activeLayer == 0 &&
            layered.paintOrder.isEmpty,
        'one visible layer by default',
      );
      layered.addStroke(const [DocumentPoint(10, 10)], rgb: 0x111111, width: 4);
      layered.addLayer();
      layered.addText(
        const DocumentPoint(100, 200),
        const DocumentPoint(420, 296),
        text: 'Été &\n<ici>',
        rgb: 0x336699,
        size: 40,
      );
      final catalog = RustDocument.readStampCatalog(libraryPath: libraryPath);
      check(
        catalog.split('\n').where((line) => line.isNotEmpty).length >= 24 &&
            catalog.startsWith('0|etoile|'),
        'stamp catalogue text',
      );
      layered.addStamp(
        const DocumentPoint(500, 100),
        const DocumentPoint(700, 300),
        stamp: 1,
        rgb: 0xd75e56,
      );
      layered.setActiveLayer(0);
      layered.addStroke(const [DocumentPoint(20, 20)], rgb: 0x222222, width: 4);
      check(
        layered.strokes.map((s) => s.layer).join(',') == '0,1,1,0' &&
            layered.paintOrder.join(',') == '0,3,1,2' &&
            layered.layers.map((l) => l.objectCount).join(',') == '2,2',
        'objects join the active layer and paint layer by layer',
      );
      check(
        layered.strokes[1].kind == VectorKind.text &&
            layered.strokes[1].text == 'Été &\n<ici>' &&
            layered.strokes[1].width == 40 &&
            layered.strokes[2].kind == VectorKind.stamp &&
            layered.strokes[2].stamp == 1,
        'text characters and stamp identifier through C ABI',
      );
      final layeredSvg = layered.exportSvg();
      check(
        layeredSvg.contains('<g id="calque-1">') &&
            layeredSvg.contains('>Été &amp;</tspan>') &&
            layeredSvg.contains('>&lt;ici&gt;</tspan>') &&
            layeredSvg.contains('translate(500 100) scale(2 2)'),
        'layer groups, escaped text lines and scaled stamp in SVG',
      );
      final layeredBytes = layered.exportProject();
      check(layeredBytes[8] == 4, 'layers, text and stamps use project 4');
      final reopenedLayers = RustDocument.fromProject(
        layeredBytes,
        libraryPath: libraryPath,
      );
      try {
        check(
          reopenedLayers.exportSvg() == layeredSvg &&
              reopenedLayers.exportProject().join(',') ==
                  layeredBytes.join(',') &&
              reopenedLayers.layers.length == 2 &&
              reopenedLayers.activeLayer == 0 &&
              reopenedLayers.strokes[1].text == 'Été &\n<ici>',
          'layered project roundtrip',
        );
      } finally {
        reopenedLayers.dispose();
      }
      check(
        layered.setLayerVisible(1, false) &&
            layered.paintOrder.join(',') == '0,3' &&
            !layered.exportSvg().contains('<text'),
        'a hidden layer leaves painting and export',
      );
      check(
        layered.setText(
              1,
              const DocumentPoint(100, 200),
              const DocumentPoint(300, 248),
              text: 'Autre',
              rgb: 0x336699,
              size: 40,
            ) &&
            layered.strokes[1].text == 'Autre' &&
            layered.undo() &&
            layered.strokes[1].text == 'Été &\n<ici>',
        'text replacement is one undoable command',
      );
      check(
        layered.undo() && layered.layers[1].visible && layered.redo(),
        'layer visibility is undoable',
      );
      layered.removeLayer(1);
      check(
        layered.count == 2 &&
            layered.layers.length == 1 &&
            layered.exportProject()[8] == 2 &&
            layered.undo() &&
            layered.count == 4 &&
            layered.exportSvg().contains('<g id="calque-2">') == false,
        'removing a layer removes its objects until undo',
      );
      var invalidTextRejected = false;
      try {
        layered.addText(
          const DocumentPoint(1, 1),
          const DocumentPoint(50, 50),
          text: 'tab\tinterdit',
          rgb: 0,
          size: 20,
        );
      } on RustCoreException catch (error) {
        invalidTextRejected = error.code == -1;
      }
      check(invalidTextRejected && layered.count == 4, 'control rejected');
    } finally {
      layered.dispose();
    }
    final sheet = RustDocument(libraryPath: libraryPath);
    try {
      sheet.addShape(
        VectorKind.rectangle,
        const DocumentPoint(100, 200),
        const DocumentPoint(300, 280),
        rgb: 0x112233,
        width: 6,
      );
      check(
        sheet.paperRgb == whitePaper &&
            !sheet.setPaperColor(whitePaper) &&
            sheet.setPaperColor(0xa8d8f0) &&
            sheet.paperRgb == 0xa8d8f0 &&
            sheet.exportProject()[8] == 4 &&
            sheet.exportSvg().contains(
              '<rect width="100%" height="100%" fill="#a8d8f0"/>',
            ),
        'sheet colour through C ABI, project 4 and SVG',
      );
      final coloured = RustDocument.fromProject(
        sheet.exportProject(),
        libraryPath: libraryPath,
      );
      try {
        check(coloured.paperRgb == 0xa8d8f0, 'sheet colour roundtrip');
      } finally {
        coloured.dispose();
      }
      check(
        sheet.undo() &&
            sheet.paperRgb == whitePaper &&
            sheet.exportProject()[8] == 2,
        'sheet colour is one undoable command',
      );
      check(
        sheet.scaleObject(0, 1.5, width: 9) &&
            sheet.strokes.single.points.first.x == 50 &&
            sheet.strokes.single.points.first.y == 180 &&
            sheet.strokes.single.points.last.x == 350 &&
            sheet.strokes.single.points.last.y == 300 &&
            sheet.strokes.single.width == 9 &&
            !sheet.scaleObject(0, 1, width: 9) &&
            sheet.undo() &&
            sheet.strokes.single.points.first.x == 100 &&
            sheet.strokes.single.width == 6,
        'resizing around the centre is one undoable command',
      );
      var oversizedRejected = false;
      try {
        sheet.scaleObject(0, 7, width: 6);
      } on RustCoreException catch (error) {
        oversizedRejected = error.code == -1;
      }
      check(
        oversizedRejected && sheet.strokes.single.points.first.x == 100,
        'an object larger than the sheet is refused unchanged',
      );
    } finally {
      sheet.dispose();
    }
    document.dispose();
    document.dispose();
    var useAfterDisposeRejected = false;
    try {
      document.exportSvg();
    } on StateError {
      useAfterDisposeRejected = true;
    }
    check(useAfterDisposeRejected, 'disposed handle guarded');
    stdout.writeln(
      'PASS: Dart → C ABI → Rust; points, snapshots, SVG, history, native error, disposal, project roundtrip, dimensions, corruption, truncations, trailing bytes, exact shapes, optional fill, v2 roundtrip, legacy v1 import, layers, text, stamps, v4 roundtrip, sheet colour and resizing, pictures read from SVG, colouring pages on locked layers, sounds, notices of the libraries.',
    );
  } finally {
    document.dispose();
  }
}
