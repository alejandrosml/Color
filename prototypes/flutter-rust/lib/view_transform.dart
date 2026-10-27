// SPDX-License-Identifier: MIT
import 'dart:math' as math;

/// A position independent of Flutter, the document engine and physical pixels.
final class ViewPoint {
  const ViewPoint(this.x, this.y);
  final double x;
  final double y;
}

/// Immutable document-to-view transform in logical screen pixels.
///
/// Fit follows the available view size. A manual view keeps its scale and the
/// document point at the center when resized, except where keeping the paper
/// reachable requires constraining the origin. Zoom/pan never edit a document.
/// Device pixel ratio is intentionally absent: the renderer handles it.
final class ViewTransform {
  factory ViewTransform.fit({
    required double viewWidth,
    required double viewHeight,
    double documentWidth = 1200,
    double documentHeight = 800,
    double padding = 24,
  }) {
    _validateGeometry(
      viewWidth,
      viewHeight,
      documentWidth,
      documentHeight,
      padding,
    );
    final fitScale = math
        .min(
          math.max(1, viewWidth - padding * 2) / documentWidth,
          math.max(1, viewHeight - padding * 2) / documentHeight,
        )
        .clamp(minScale, maxScale)
        .toDouble();
    return ViewTransform._(
      viewWidth: viewWidth,
      viewHeight: viewHeight,
      documentWidth: documentWidth,
      documentHeight: documentHeight,
      padding: padding,
      scale: fitScale,
      left: (viewWidth - documentWidth * fitScale) / 2,
      top: (viewHeight - documentHeight * fitScale) / 2,
      isFit: true,
    );
  }

  const ViewTransform._({
    required this.viewWidth,
    required this.viewHeight,
    required this.documentWidth,
    required this.documentHeight,
    required this.padding,
    required this.scale,
    required this.left,
    required this.top,
    required this.isFit,
  });

  /// These absolute limits remain stable when the window is resized.
  static const double minScale = 1 / 16384;
  static const double maxScale = 64;
  static const double visiblePaperPixels = 48;
  static const double _maxViewDimension = 1000000;
  static const double _maxDocumentDimension = 16384;

  final double viewWidth;
  final double viewHeight;
  final double documentWidth;
  final double documentHeight;
  final double padding;
  final double scale;
  final double left;
  final double top;
  final bool isFit;

  double get width => documentWidth * scale;
  double get height => documentHeight * scale;
  ViewPoint get documentCenter => toDocument(viewWidth / 2, viewHeight / 2);

  ViewTransform resetToFit() => ViewTransform.fit(
    viewWidth: viewWidth,
    viewHeight: viewHeight,
    documentWidth: documentWidth,
    documentHeight: documentHeight,
    padding: padding,
  );

  ViewTransform resize({
    required double viewWidth,
    required double viewHeight,
    double? padding,
  }) {
    final nextPadding = padding ?? this.padding;
    _validateGeometry(
      viewWidth,
      viewHeight,
      documentWidth,
      documentHeight,
      nextPadding,
    );
    if (isFit) {
      return ViewTransform.fit(
        viewWidth: viewWidth,
        viewHeight: viewHeight,
        documentWidth: documentWidth,
        documentHeight: documentHeight,
        padding: nextPadding,
      );
    }
    final center = documentCenter;
    return _manual(
      viewWidth: viewWidth,
      viewHeight: viewHeight,
      padding: nextPadding,
      scale: scale,
      left: viewWidth / 2 - center.x * scale,
      top: viewHeight / 2 - center.y * scale,
    );
  }

  /// Keeps the document point below the anchor fixed unless pan bounds apply.
  ViewTransform zoomAt(
    double factor, {
    required double anchorX,
    required double anchorY,
  }) {
    _positiveFinite(factor, 'factor');
    // Clamp before multiplication, so even a finite factor near double.max
    // cannot overflow and contaminate the transform with infinity.
    final target = factor >= maxScale / scale
        ? maxScale
        : factor <= minScale / scale
        ? minScale
        : scale * factor;
    return withScale(target, anchorX: anchorX, anchorY: anchorY);
  }

  /// Sets a manual scale, including 1 for one logical pixel per document unit.
  ViewTransform withScale(
    double targetScale, {
    required double anchorX,
    required double anchorY,
  }) {
    _positiveFinite(targetScale, 'targetScale');
    final anchor = toDocument(anchorX, anchorY);
    final nextScale = targetScale.clamp(minScale, maxScale).toDouble();
    return _manual(
      scale: nextScale,
      left: anchorX - anchor.x * nextScale,
      top: anchorY - anchor.y * nextScale,
    );
  }

  ViewTransform panBy(double dx, double dy) {
    _finite(dx, 'dx');
    _finite(dy, 'dy');
    if (dx == 0 && dy == 0) return this;
    return _manual(scale: scale, left: left + dx, top: top + dy);
  }

  /// Unclamped coordinates are needed for anchored zoom and view gestures.
  /// Drawing can request page-clamped coordinates explicitly.
  ViewPoint toDocument(double x, double y, {bool clampToPage = false}) {
    _finite(x, 'x');
    _finite(y, 'y');
    final dx = (x - left) / scale;
    final dy = (y - top) / scale;
    _finite(dx, 'document x');
    _finite(dy, 'document y');
    return ViewPoint(
      clampToPage ? dx.clamp(0, documentWidth).toDouble() : dx,
      clampToPage ? dy.clamp(0, documentHeight).toDouble() : dy,
    );
  }

  ViewPoint toView(double x, double y) {
    _finite(x, 'x');
    _finite(y, 'y');
    final vx = left + x * scale;
    final vy = top + y * scale;
    _finite(vx, 'view x');
    _finite(vy, 'view y');
    return ViewPoint(vx, vy);
  }

  bool contains(double x, double y) =>
      x.isFinite &&
      y.isFinite &&
      x >= left &&
      x <= left + width &&
      y >= top &&
      y <= top + height;

  ViewTransform _manual({
    required double scale,
    required double left,
    required double top,
    double? viewWidth,
    double? viewHeight,
    double? padding,
  }) {
    _finite(left, 'left');
    _finite(top, 'top');
    final vw = viewWidth ?? this.viewWidth;
    final vh = viewHeight ?? this.viewHeight;
    return ViewTransform._(
      viewWidth: vw,
      viewHeight: vh,
      documentWidth: documentWidth,
      documentHeight: documentHeight,
      padding: padding ?? this.padding,
      scale: scale,
      left: _boundedOrigin(left, documentWidth * scale, vw),
      top: _boundedOrigin(top, documentHeight * scale, vh),
      isFit: false,
    );
  }

  static double _boundedOrigin(
    double origin,
    double pageSize,
    double viewSize,
  ) {
    final visible = math.min(visiblePaperPixels, math.min(pageSize, viewSize));
    return origin.clamp(visible - pageSize, viewSize - visible).toDouble();
  }

  static void _validateGeometry(
    double vw,
    double vh,
    double dw,
    double dh,
    double padding,
  ) {
    for (final (name, value, maximum, positive) in [
      ('viewWidth', vw, _maxViewDimension, false),
      ('viewHeight', vh, _maxViewDimension, false),
      ('documentWidth', dw, _maxDocumentDimension, true),
      ('documentHeight', dh, _maxDocumentDimension, true),
      ('padding', padding, _maxViewDimension, false),
    ]) {
      if (!value.isFinite ||
          value < 0 ||
          (positive && value < 1) ||
          value > maximum) {
        throw ArgumentError.value(value, name, 'Dimension hors limites.');
      }
    }
  }

  static void _finite(double value, String name) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, name, 'Valeur non finie.');
    }
  }

  static void _positiveFinite(double value, String name) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, name, 'Valeur positive finie attendue.');
    }
  }
}
