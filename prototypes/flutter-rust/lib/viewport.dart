// SPDX-License-Identifier: MIT
import 'rust_document.dart' show DocumentPoint;
import 'view_transform.dart';

/// Adapter shared by drawing, hit testing and painting. Logical units never
/// depend on the display's physical pixel density.
class DocumentViewport {
  DocumentViewport({
    required double viewWidth,
    required double viewHeight,
    double documentWidth = 1200,
    double documentHeight = 800,
    double padding = 24,
  }) : transform = ViewTransform.fit(
         viewWidth: viewWidth,
         viewHeight: viewHeight,
         documentWidth: documentWidth,
         documentHeight: documentHeight,
         padding: padding,
       );
  const DocumentViewport.fromTransform(this.transform);
  final ViewTransform transform;
  double get scale => transform.scale;
  double get documentWidth => transform.documentWidth;
  double get documentHeight => transform.documentHeight;
  double get width => transform.width;
  double get height => transform.height;
  double get left => transform.left;
  double get top => transform.top;
  bool contains(double x, double y) => transform.contains(x, y);
  DocumentPoint point(double x, double y) {
    final p = transform.toDocument(x, y, clampToPage: true);
    return DocumentPoint(p.x, p.y);
  }
}
