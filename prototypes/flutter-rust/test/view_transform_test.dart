// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:edupaint_flutter_study/view_transform.dart';
import 'package:flutter_test/flutter_test.dart';

void expectPoint(
  ViewPoint actual,
  ViewPoint expected, [
  double tolerance = 1e-7,
]) {
  expect(actual.x, closeTo(expected.x, tolerance));
  expect(actual.y, closeTo(expected.y, tolerance));
}

void expectReachable(ViewTransform view) {
  final visibleWidth = math.max(
    0.0,
    math.min(view.viewWidth, view.left + view.width) - math.max(0.0, view.left),
  );
  final visibleHeight = math.max(
    0.0,
    math.min(view.viewHeight, view.top + view.height) - math.max(0.0, view.top),
  );
  expect(
    visibleWidth + 1e-7,
    greaterThanOrEqualTo(
      math.min(
        ViewTransform.visiblePaperPixels,
        math.min(view.width, view.viewWidth),
      ),
    ),
  );
  expect(
    visibleHeight + 1e-7,
    greaterThanOrEqualTo(
      math.min(
        ViewTransform.visiblePaperPixels,
        math.min(view.height, view.viewHeight),
      ),
    ),
  );
  expect(
    view.scale.isFinite && view.left.isFinite && view.top.isFinite,
    isTrue,
  );
}

void main() {
  ViewTransform initial() => ViewTransform.fit(viewWidth: 960, viewHeight: 700);

  test(
    'fit starts centered and matches the existing logical-page transform',
    () {
      final view = initial();
      expect(view.isFit, isTrue);
      expect(view.scale, closeTo(.76, 1e-12));
      expect(view.left, closeTo(24, 1e-12));
      expect(view.top, closeTo(46, 1e-12));
      expectPoint(view.documentCenter, const ViewPoint(600, 400));
      expectPoint(view.toView(0, 0), ViewPoint(view.left, view.top));
      expect(view.contains(view.left, view.top), isTrue);
      expect(
        view.contains(view.left + view.width, view.top + view.height),
        isTrue,
      );
      expect(view.contains(0, 0), isFalse);
    },
  );

  test('fit recomputes on resize and retains paper dimensions', () {
    final original = initial();
    for (final (width, height) in [
      (300.0, 200.0),
      (1500.0, 950.0),
      (600.0, 900.0),
    ]) {
      final view = original.resize(viewWidth: width, viewHeight: height);
      expect(view.isFit, isTrue);
      expect(view.documentWidth, original.documentWidth);
      expect(view.documentHeight, original.documentHeight);
      expect(view.width, lessThanOrEqualTo(width - 48 + 1e-7));
      expect(view.height, lessThanOrEqualTo(height - 48 + 1e-7));
      expectPoint(view.documentCenter, const ViewPoint(600, 400));
    }
  });

  test('manual zoom fixes a chosen pointer anchor', () {
    final view = initial();
    const x = 291.2, y = 223.7;
    final documentAnchor = view.toDocument(x, y);
    final zoomed = view.zoomAt(2.5, anchorX: x, anchorY: y);
    expect(zoomed.isFit, isFalse);
    expect(zoomed.scale, closeTo(view.scale * 2.5, 1e-12));
    expectPoint(zoomed.toDocument(x, y), documentAnchor);
    expectPoint(
      zoomed.toView(documentAnchor.x, documentAnchor.y),
      const ViewPoint(x, y),
    );
    expectPoint(
      zoomed.zoomAt(1 / 2.5, anchorX: x, anchorY: y).documentCenter,
      view.documentCenter,
    );
  });

  test('coordinate mapping and inverse work at both scale limits', () {
    final original = initial();
    for (final scale in [
      ViewTransform.minScale,
      .1,
      1.0,
      8.0,
      ViewTransform.maxScale,
    ]) {
      final view = original
          .withScale(scale, anchorX: 480, anchorY: 350)
          .panBy(91.2, -34.7);
      for (var i = 0; i <= 100; i++) {
        final point = ViewPoint(12.0 * i, 8.0 * i);
        final screen = view.toView(point.x, point.y);
        expectPoint(view.toDocument(screen.x, screen.y), point);
      }
    }
  });

  test(
    'manual resize preserves scale and the document center when reachable',
    () {
      final view = initial()
          .zoomAt(3, anchorX: 230, anchorY: 180)
          .panBy(80, -15);
      final center = view.documentCenter;
      final resized = view.resize(
        viewWidth: 1400,
        viewHeight: 1000,
        padding: 12,
      );
      expect(resized.isFit, isFalse);
      expect(resized.scale, view.scale);
      expect(resized.padding, 12);
      expectPoint(resized.documentCenter, center);
      expectPoint(
        resized.resize(viewWidth: 960, viewHeight: 700).documentCenter,
        center,
      );
    },
  );

  test('pan uses logical screen displacement independent of zoom', () {
    for (final scale in [.5, 1.0, 4.0]) {
      final view = initial().withScale(scale, anchorX: 480, anchorY: 350);
      final panned = view.panBy(25, -30);
      expect(panned.left - view.left, closeTo(25, 1e-10));
      expect(panned.top - view.top, closeTo(-30, 1e-10));
      expect(panned.scale, scale);
      expectPoint(
        panned.toView(600, 400),
        ViewPoint(view.toView(600, 400).x + 25, view.toView(600, 400).y - 30),
      );
    }
    final fitted = initial();
    expect(identical(fitted.panBy(0, 0), fitted), isTrue);
    expect(fitted.isFit, isTrue);
  });

  test('pan limits leave a reachable patch at every extreme', () {
    for (final scale in [
      ViewTransform.minScale,
      .2,
      1.0,
      ViewTransform.maxScale,
    ]) {
      final view = initial().withScale(scale, anchorX: 480, anchorY: 350);
      for (final (dx, dy) in [
        (1e300, 1e300),
        (-1e300, 1e300),
        (1e300, -1e300),
        (-1e300, -1e300),
      ]) {
        expectReachable(view.panBy(dx, dy));
      }
    }
  });

  test(
    'shrinking an extreme manual view prioritizes keeping the paper visible',
    () {
      final view = initial()
          .zoomAt(2, anchorX: 480, anchorY: 350)
          .panBy(1e300, 1e300);
      final resized = view.resize(viewWidth: 64, viewHeight: 48);
      expect(resized.scale, view.scale);
      expectReachable(resized);
      // The old center was outside the page: preserving it exactly would make
      // the page disappear from this much smaller window.
      expect(
        resized.documentCenter.x,
        isNot(closeTo(view.documentCenter.x, 1e-7)),
      );
    },
  );

  test(
    'fit reset forgets manual zoom and pan but keeps current view geometry',
    () {
      final view = initial()
          .zoomAt(7, anchorX: 200, anchorY: 100)
          .panBy(-800, 300)
          .resize(viewWidth: 1300, viewHeight: 900, padding: 30);
      final reset = view.resetToFit();
      final expected = ViewTransform.fit(
        viewWidth: 1300,
        viewHeight: 900,
        padding: 30,
      );
      expect(reset.isFit, isTrue);
      expect(reset.scale, expected.scale);
      expect(reset.left, expected.left);
      expect(reset.top, expected.top);
    },
  );

  test('large finite zoom factors are clamped before multiplication', () {
    final view = initial();
    final largest = view.zoomAt(1e308, anchorX: 480, anchorY: 350);
    final smallest = view.zoomAt(1e-308, anchorX: 480, anchorY: 350);
    expect(largest.scale, ViewTransform.maxScale);
    expect(smallest.scale, ViewTransform.minScale);
    expectReachable(largest);
    expectReachable(smallest);
  });

  test(
    'drawing coordinates clamp explicitly while view coordinates remain free',
    () {
      final view = initial();
      final outside = view.toDocument(-100, -100);
      expect(outside.x, lessThan(0));
      expect(outside.y, lessThan(0));
      expectPoint(
        view.toDocument(-100, -100, clampToPage: true),
        const ViewPoint(0, 0),
      );
      expectPoint(
        view.toDocument(10000, 10000, clampToPage: true),
        const ViewPoint(1200, 800),
      );
    },
  );

  test('zero and tiny layout sizes retain finite recoverable transforms', () {
    for (final (width, height) in [
      (0.0, 0.0),
      (1.0, 1.0),
      (0.0, 64.0),
      (30.0, 20.0),
    ]) {
      final view = ViewTransform.fit(
        viewWidth: width,
        viewHeight: height,
        documentWidth: 16384,
        documentHeight: 16384,
      );
      final manual = view
          .zoomAt(3, anchorX: width / 2, anchorY: height / 2)
          .panBy(1000, -1000);
      expectReachable(manual);
      final restored = manual
          .resize(viewWidth: 960, viewHeight: 700)
          .resetToFit();
      expect(restored.scale.isFinite, isTrue);
      expectPoint(restored.documentCenter, const ViewPoint(8192, 8192));
    }
  });

  test(
    'nonfinite and invalid geometry are rejected before creating a state',
    () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -1.0,
      ]) {
        expect(
          () => ViewTransform.fit(viewWidth: value, viewHeight: 700),
          throwsArgumentError,
        );
        expect(
          () => ViewTransform.fit(
            viewWidth: 960,
            viewHeight: 700,
            padding: value,
          ),
          throwsArgumentError,
        );
      }
      for (final value in [
        0.0,
        0.5,
        -1.0,
        double.nan,
        double.infinity,
        16385.0,
      ]) {
        expect(
          () => ViewTransform.fit(
            viewWidth: 960,
            viewHeight: 700,
            documentWidth: value,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => ViewTransform.fit(viewWidth: 1000001, viewHeight: 700),
        throwsArgumentError,
      );
      final view = initial();
      for (final value in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => view.zoomAt(value, anchorX: 480, anchorY: 350),
          throwsArgumentError,
        );
        expect(
          () => view.withScale(value, anchorX: 480, anchorY: 350),
          throwsArgumentError,
        );
      }
      expect(() => view.panBy(double.infinity, 0), throwsArgumentError);
      expect(
        () => view.withScale(2, anchorX: double.nan, anchorY: 1),
        throwsArgumentError,
      );
      expect(() => view.toView(double.infinity, 0), throwsArgumentError);
      expect(() => view.toDocument(double.nan, 0), throwsArgumentError);
      expect(view.contains(double.nan, 0), isFalse);
      expect(view.isFit, isTrue);
    },
  );

  test(
    'many zoom/pan/resize sequences stay bounded and preserve inverse mapping',
    () {
      final random = math.Random(20260924);
      var view = initial();
      for (var i = 0; i < 1000; i++) {
        view = view
            .zoomAt(
              .5 + random.nextDouble() * 1.5,
              anchorX: view.viewWidth * random.nextDouble(),
              anchorY: view.viewHeight * random.nextDouble(),
            )
            .panBy(
              random.nextDouble() * 800 - 400,
              random.nextDouble() * 800 - 400,
            );
        if (i % 7 == 0) {
          view = view.resize(
            viewWidth: 50 + random.nextDouble() * 1800,
            viewHeight: 50 + random.nextDouble() * 1200,
          );
        }
        expectReachable(view);
        final documentPoint = ViewPoint(
          random.nextDouble() * 1200,
          random.nextDouble() * 800,
        );
        final screen = view.toView(documentPoint.x, documentPoint.y);
        expectPoint(view.toDocument(screen.x, screen.y), documentPoint);
        expect(view.documentWidth, 1200);
        expect(view.documentHeight, 800);
      }
    },
  );
}
