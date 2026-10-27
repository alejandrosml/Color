// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:edupaint_flutter_study/viewport.dart';

void main() {
  test('resize preserves document coordinates at the center and corners', () {
    for (final size in [(720.0, 420.0), (960.0, 640.0), (1600.0, 1000.0)]) {
      final view = DocumentViewport(viewWidth: size.$1, viewHeight: size.$2);
      final center = view.point(size.$1 / 2, size.$2 / 2);
      expect(center.x, closeTo(600, .000001));
      expect(center.y, closeTo(400, .000001));
      final corner = view.point(view.left + view.width, view.top + view.height);
      expect(corner.x, closeTo(1200, .000001));
      expect(corner.y, closeTo(800, .000001));
      expect(view.width, lessThanOrEqualTo(size.$1 - 48));
      expect(view.height, lessThanOrEqualTo(size.$2 - 48));
    }
  });
  test('outside input is rejected at gesture start and clamped during a gesture', () {
    final view = DocumentViewport(viewWidth: 960, viewHeight: 700);
    expect(view.contains(0, 0), isFalse);
    final low = view.point(-500, -200);
    final high = view.point(5000, 2000);
    expect((low.x, low.y), (0.0, 0.0));
    expect((high.x, high.y), (1200.0, 800.0));
  });
}
