// SPDX-License-Identifier: MIT
// The drawing of the sheet kept as images: F-01 and F-04 of the retrospective
// of October 2026. Impeller keeps no rasterized picture from one frame to the
// next, so a sheet painted element by element costs, at every frame, as much
// as its drawing is large, and a child drawing over a big drawing feels it.
// What does not change while a pointer moves is rasterized once, here, into
// images of the size of the sheet on the screen; every frame then draws those
// images and what moves between them, whatever the size of the drawing.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'document_renderer.dart';
import 'viewport.dart';

/// The largest side of an image kept here, in pixels of the screen: what
/// the graphics processors that run Color accept. A sheet larger than that
/// on the screen is painted element by element, as without images.
const int maxSheetImageSide = 8192;

/// The shadow under the sheet, as the studio and the film paint it.
const Color sheetShadow = Color(0x3323402c);

/// The sheet before any element, in the area of [size]: its shadow, its
/// paper and, in the units of the drawing, its image. Leaves [canvas] in
/// those units, clipped to the sheet: two restores close what this opens.
void paintSheetBase(
  Canvas canvas,
  Size size,
  DocumentViewport viewport, {
  required int paperRgb,
  required ui.Image? background,
}) {
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  final rect = Rect.fromLTWH(
    viewport.left,
    viewport.top,
    viewport.width,
    viewport.height,
  );
  canvas.drawShadow(Path()..addRect(rect), sheetShadow, 5, true);
  canvas.drawRect(rect, Paint()..color = Color(0xff000000 | paperRgb));
  _enterUnits(canvas, viewport);
  if (background != null) {
    canvas.drawImageRect(
      background,
      Rect.fromLTWH(
        0,
        0,
        background.width.toDouble(),
        background.height.toDouble(),
      ),
      Rect.fromLTWH(0, 0, viewport.documentWidth, viewport.documentHeight),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }
}

/// The units of the drawing in the area of [size], clipped to the area and
/// to the sheet, as [paintSheetBase] leaves them: two restores close them.
void enterSheetUnits(Canvas canvas, Size size, DocumentViewport viewport) {
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  _enterUnits(canvas, viewport);
}

void _enterUnits(Canvas canvas, DocumentViewport viewport) {
  canvas.save();
  canvas.translate(viewport.left, viewport.top);
  canvas.scale(viewport.scale);
  canvas.clipRect(
    Rect.fromLTWH(0, 0, viewport.documentWidth, viewport.documentHeight),
  );
}

/// What [draw] paints, as an image of [width] by [height] pixels: made at
/// once, rasterized by the engine before it is first drawn.
ui.Image rasterizeSheet(int width, int height, void Function(Canvas) draw) {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(width, height);
  } finally {
    picture.dispose();
  }
}

/// Copies [image] exactly where it lies, pixel for pixel, as the first
/// thing of an image of the same size that adds to it.
void copySheetImage(Canvas canvas, ui.Image image) => canvas.drawImage(
  image,
  Offset.zero,
  Paint()
    ..blendMode = BlendMode.src
    ..filterQuality = FilterQuality.none,
);

/// Draws [image], made at [pixelRatio] pixels of the screen per logical
/// pixel with its first pixel at [left], [top], exactly on the pixels of
/// the screen it was made for.
void drawSheetImage(
  Canvas canvas,
  ui.Image image,
  double pixelRatio, {
  int left = 0,
  int top = 0,
}) {
  canvas.save();
  canvas.scale(1 / pixelRatio);
  canvas.drawImage(
    image,
    Offset(left.toDouble(), top.toDouble()),
    Paint()..filterQuality = FilterQuality.none,
  );
  canvas.restore();
}

/// One view of the sheet in an area: its size, the pixels of the screen per
/// logical pixel, and where the drawing lies.
@immutable
final class _View {
  _View(this.size, this.pixelRatio, DocumentViewport viewport)
    : left = viewport.left,
      top = viewport.top,
      scale = viewport.scale,
      documentWidth = viewport.documentWidth,
      documentHeight = viewport.documentHeight,
      width = (size.width * pixelRatio).ceil(),
      height = (size.height * pixelRatio).ceil();

  final Size size;
  final double pixelRatio;
  final double left;
  final double top;
  final double scale;
  final double documentWidth;
  final double documentHeight;

  /// The area in pixels of the screen.
  final int width;
  final int height;

  /// Images of this view can be made: neither empty nor too large.
  bool get fits =>
      pixelRatio > 0 &&
      pixelRatio.isFinite &&
      width > 0 &&
      height > 0 &&
      width <= maxSheetImageSide &&
      height <= maxSheetImageSide;

  /// Where the sheet lies, in logical pixels of the area.
  Rect get sheet =>
      Rect.fromLTWH(left, top, documentWidth * scale, documentHeight * scale);

  /// Part of the sheet lies outside the area.
  bool get cutsSheet {
    final sheet = this.sheet;
    return sheet.left < 0 ||
        sheet.top < 0 ||
        sheet.right > size.width ||
        sheet.bottom > size.height;
  }

  @override
  bool operator ==(Object other) =>
      other is _View &&
      other.size == size &&
      other.pixelRatio == pixelRatio &&
      other.left == left &&
      other.top == top &&
      other.scale == scale &&
      other.documentWidth == documentWidth &&
      other.documentHeight == documentHeight;

  @override
  int get hashCode => Object.hash(
    size,
    pixelRatio,
    left,
    top,
    scale,
    documentWidth,
    documentHeight,
  );
}

/// How the elements handed for a frame differ from those of the images.
enum _Change { none, added, other }

/// The images of the sheet of the studio, for its painter. Two of them:
/// under, everything painted before what is drawn — the shadow, the paper,
/// the image of the sheet and the elements under it — over the whole area,
/// exactly as painted there; over, the elements above, on a transparent
/// ground, over the part of the area where the sheet lies. What lies between
/// them is painted at every frame: the trait being drawn, or the element
/// being taken.
///
/// An element added at the top of the elements under — a trait that ends,
/// a shape, a stamp — is drawn onto the image under, alone; anything else
/// makes the images again, once. While the view moves (two fingers, a
/// trackpad, the hand), the images are moved and scaled with it, and made
/// again where the gesture ends.
///
/// Owned by the studio, which disposes it.
final class SheetImages {
  ui.Image? _under;
  ui.Image? _over;
  int _overLeft = 0;
  int _overTop = 0;
  _View? _view;

  // What the images hold.
  int? _paperRgb;
  ui.Image? _background;
  List<RenderedElement> _underElements = const [];
  List<RenderedElement> _overElements = const [];

  // What was handed for the last frame: the same lists, the same elements.
  List<RenderedElement>? _strokes;
  List<int>? _paintOrder;
  int _split = -1;
  int _excluded = -1;

  // The whole sheet, small, for a move of the view that brings into sight
  // what the images do not hold: a sheet larger than the area, zoomed out
  // or moved. Made at the first such move, kept for the same elements.
  ui.Image? _whole;
  double _wholePixelsPerUnit = 1;

  /// Images made from nothing, and elements added onto the image under, by
  /// every sheet: what the tests count.
  @visibleForTesting
  static int debugFullBakes = 0;
  @visibleForTesting
  static int debugAdditions = 0;

  /// Paints every sheet element by element, as without images: what the
  /// tests compare the images with.
  @visibleForTesting
  static bool debugPaintWithoutImages = false;

  /// Images now held.
  @visibleForTesting
  int get debugImageCount =>
      (_under == null ? 0 : 1) +
      (_over == null ? 0 : 1) +
      (_whole == null ? 0 : 1);

  /// Lets go of every image: they are made again when the sheet is next
  /// painted. For a sheet out of sight, and when memory runs short.
  void drop() {
    _dropViewImages();
    _dropWhole();
    _strokes = null;
    _paintOrder = null;
  }

  void dispose() => drop();

  void _dropViewImages() {
    _under?.dispose();
    _under = null;
    _over?.dispose();
    _over = null;
    _view = null;
  }

  void _dropWhole() {
    _whole?.dispose();
    _whole = null;
  }

  /// Paints the sheet in the area of [size]: the elements of [paintOrder],
  /// indices of [strokes], from the bottom up, with what [paintLive]
  /// paints, in the units of the drawing and clipped to the sheet, between
  /// the [split] first ones and the others. [excluded], a place in
  /// [paintOrder], is left out of the images: the element being taken,
  /// which [paintLive] paints where [split] is, its own place.
  ///
  /// False when no image can be made for such an area: the caller paints
  /// the sheet element by element.
  bool paint(
    Canvas canvas,
    Size size, {
    required double pixelRatio,
    required DocumentViewport viewport,
    required bool viewMoving,
    required int paperRgb,
    required ui.Image? background,
    required List<RenderedElement> strokes,
    required List<int> paintOrder,
    required int split,
    int excluded = -1,
    required void Function(Canvas canvas) paintLive,
  }) {
    final view = _View(size, pixelRatio, viewport);
    if (!view.fits || debugPaintWithoutImages) {
      drop();
      return false;
    }
    final change = _take(
      strokes,
      paintOrder,
      split,
      excluded,
      paperRgb,
      background,
    );
    if (change != _Change.none) _dropWhole();
    final under = _under;
    // An image that the engine could not make, the graphics processor
    // being away, is only known when it is drawn: then the canvas is left
    // as it was found, the sheet is painted without images, and they are
    // made again at the next frame.
    final saved = canvas.getSaveCount();
    try {
      if (change == _Change.added && under != null && _view == view) {
        _under = _addOnto(under, view, viewport, _underElements.last);
        under.dispose();
        debugAdditions++;
      } else if (change == _Change.none &&
          under != null &&
          _view != view &&
          viewMoving) {
        _paintMoved(canvas, view, viewport, paintLive);
        return true;
      } else if (change != _Change.none || under == null || _view != view) {
        _bake(view, viewport);
      }
      drawSheetImage(canvas, _under!, pixelRatio);
      enterSheetUnits(canvas, size, viewport);
      paintLive(canvas);
      canvas
        ..restore()
        ..restore();
      final over = _over;
      if (over != null) {
        drawSheetImage(
          canvas,
          over,
          pixelRatio,
          left: _overLeft,
          top: _overTop,
        );
      }
    } on ui.PictureRasterizationException {
      canvas.restoreToCount(saved);
      drop();
      return false;
    }
    return true;
  }

  // Keeps what is handed for this frame and says how it differs from what
  // the images hold.
  _Change _take(
    List<RenderedElement> strokes,
    List<int> paintOrder,
    int split,
    int excluded,
    int paperRgb,
    ui.Image? background,
  ) {
    final baseSame =
        paperRgb == _paperRgb && identical(background, _background);
    if (baseSame &&
        identical(strokes, _strokes) &&
        identical(paintOrder, _paintOrder) &&
        split == _split &&
        excluded == _excluded) {
      return _Change.none;
    }
    final at = excluded >= 0 ? excluded : split.clamp(0, paintOrder.length);
    final under = <RenderedElement>[
      for (var rank = 0; rank < at; rank++) strokes[paintOrder[rank]],
    ];
    final over = <RenderedElement>[
      for (
        var rank = excluded >= 0 ? at + 1 : at;
        rank < paintOrder.length;
        rank++
      )
        strokes[paintOrder[rank]],
    ];
    final change = !baseSame
        ? _Change.other
        : _sameElements(over, _overElements) &&
              _sameElements(under, _underElements)
        ? _Change.none
        : _sameElements(over, _overElements) &&
              under.length == _underElements.length + 1 &&
              _startsWith(under, _underElements)
        ? _Change.added
        : _Change.other;
    _strokes = strokes;
    _paintOrder = paintOrder;
    _split = split;
    _excluded = excluded;
    _paperRgb = paperRgb;
    _background = background;
    _underElements = under;
    _overElements = over;
    return change;
  }

  static bool _sameElements(List<RenderedElement> a, List<RenderedElement> b) =>
      a.length == b.length && _startsWith(a, b);

  static bool _startsWith(List<RenderedElement> a, List<RenderedElement> b) {
    if (a.length < b.length) return false;
    for (var index = 0; index < b.length; index++) {
      if (!identical(a[index], b[index])) return false;
    }
    return true;
  }

  // Makes both images for [view].
  void _bake(_View view, DocumentViewport viewport) {
    _dropViewImages();
    debugFullBakes++;
    _view = view;
    final paperRgb = _paperRgb!;
    final background = _background;
    _under = rasterizeSheet(view.width, view.height, (canvas) {
      canvas.scale(view.pixelRatio);
      paintSheetBase(
        canvas,
        view.size,
        viewport,
        paperRgb: paperRgb,
        background: background,
      );
      for (final element in _underElements) {
        element.paint(canvas);
      }
      canvas
        ..restore()
        ..restore();
    });
    if (_overElements.isEmpty) return;
    final sheet = view.sheet.intersect(Offset.zero & view.size);
    if (sheet.isEmpty) return;
    final ratio = view.pixelRatio;
    final left = math.max(0, (sheet.left * ratio).floor());
    final top = math.max(0, (sheet.top * ratio).floor());
    final right = math.min(view.width, (sheet.right * ratio).ceil());
    final bottom = math.min(view.height, (sheet.bottom * ratio).ceil());
    if (right <= left || bottom <= top) return;
    _overLeft = left;
    _overTop = top;
    _over = rasterizeSheet(right - left, bottom - top, (canvas) {
      canvas.translate(-left.toDouble(), -top.toDouble());
      canvas.scale(ratio);
      enterSheetUnits(canvas, view.size, viewport);
      for (final element in _overElements) {
        element.paint(canvas);
      }
      canvas
        ..restore()
        ..restore();
    });
  }

  // The image under with [element] drawn over it, exactly as if the whole
  // image had been made with it.
  static ui.Image _addOnto(
    ui.Image under,
    _View view,
    DocumentViewport viewport,
    RenderedElement element,
  ) => rasterizeSheet(view.width, view.height, (canvas) {
    copySheetImage(canvas, under);
    canvas.scale(view.pixelRatio);
    enterSheetUnits(canvas, view.size, viewport);
    element.paint(canvas);
    canvas
      ..restore()
      ..restore();
  });

  // A frame while the view moves: the images of the view they were made
  // for, moved and scaled as the drawing since then; beside them, what
  // they do not hold, from the small image of the whole sheet.
  void _paintMoved(
    Canvas canvas,
    _View now,
    DocumentViewport viewport,
    void Function(Canvas canvas) paintLive,
  ) {
    final then = _view!;
    final factor = now.scale / then.scale;
    Offset place(double x, double y) => Offset(
      now.left + (x - then.left) * factor,
      now.top + (y - then.top) * factor,
    );
    // Where the area of the images now lies.
    final held = Rect.fromPoints(
      place(0, 0),
      place(then.size.width, then.size.height),
    );
    final smooth = Paint()..filterQuality = FilterQuality.medium;
    canvas.save();
    canvas.clipRect(Offset.zero & now.size);
    canvas.save();
    canvas.clipRect(held, clipOp: ui.ClipOp.difference);
    canvas.drawShadow(Path()..addRect(now.sheet), sheetShadow, 5, true);
    if (then.cutsSheet) {
      final whole = _wholeImage(then);
      canvas.translate(now.left, now.top);
      canvas.scale(now.scale / _wholePixelsPerUnit);
      canvas.drawImage(whole, Offset.zero, smooth);
    }
    canvas.restore();
    void moved(ui.Image image, int left, int top) {
      canvas.save();
      canvas.translate(now.left, now.top);
      canvas.scale(factor);
      canvas.translate(-then.left, -then.top);
      canvas.scale(1 / then.pixelRatio);
      canvas.drawImage(image, Offset(left.toDouble(), top.toDouble()), smooth);
      canvas.restore();
    }

    moved(_under!, 0, 0);
    enterSheetUnits(canvas, now.size, viewport);
    paintLive(canvas);
    canvas
      ..restore()
      ..restore();
    final over = _over;
    if (over != null) moved(over, _overLeft, _overTop);
    canvas.restore();
  }

  // The whole sheet with every element of the images, as large as the
  // area of [view] allows.
  ui.Image _wholeImage(_View view) {
    final existing = _whole;
    if (existing != null) return existing;
    final perUnit = math.min(
      view.width / view.documentWidth,
      view.height / view.documentHeight,
    );
    final width = (view.documentWidth * perUnit).ceil().clamp(1, view.width);
    final height = (view.documentHeight * perUnit).ceil().clamp(1, view.height);
    final paperRgb = _paperRgb!;
    final background = _background;
    final elements = [..._underElements, ..._overElements];
    _wholePixelsPerUnit = perUnit;
    return _whole = rasterizeSheet(width, height, (canvas) {
      canvas.scale(perUnit);
      final sheet = Rect.fromLTWH(
        0,
        0,
        view.documentWidth,
        view.documentHeight,
      );
      canvas.clipRect(sheet);
      canvas.drawRect(sheet, Paint()..color = Color(0xff000000 | paperRgb));
      if (background != null) {
        canvas.drawImageRect(
          background,
          Rect.fromLTWH(
            0,
            0,
            background.width.toDouble(),
            background.height.toDouble(),
          ),
          sheet,
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
      for (final element in elements) {
        element.paint(canvas);
      }
    });
  }
}
