// SPDX-License-Identifier: MIT
// The shade of a veil of the decor (Color 1.2, step 6): laid by
// « modulate » on the image that the decor keeps, where every pixel is
// opaque, it must give what « multiply » gave — the decor in the evening
// and at night is the same picture, pixel for pixel — and stay « multiply »
// anywhere else.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/decor.dart';
import 'package:edupaint_flutter_study/decor_motion.dart';
import 'package:edupaint_flutter_study/decor_view.dart';
import 'package:edupaint_flutter_study/universe.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  // Numbers that look drawn at random, the same at every run.
  double Function() numbers(int seed) {
    var state = (seed * 2654435761 + 1) & 0xffffffff;
    return () {
      state = (state * 1664525 + 1013904223) & 0xffffffff;
      return (state >> 8) / 0x1000000;
    };
  }

  Future<ByteData> pixelsOf(
    WidgetTester tester,
    Size frame,
    double ratio,
    void Function(Canvas canvas) paint,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(ratio);
    paint(canvas);
    final picture = recorder.endRecording();
    late ByteData bytes;
    await tester.runAsync(() async {
      final image = await picture.toImage(
        (frame.width * ratio).ceil(),
        (frame.height * ratio).ceil(),
      );
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    picture.dispose();
    return bytes;
  }

  // How many pixels differ, and by how much at most on one channel.
  (int, int) differences(ByteData a, ByteData b) {
    expect(a.lengthInBytes, b.lengthInBytes);
    var count = 0;
    var most = 0;
    for (var index = 0; index < a.lengthInBytes; index += 4) {
      if (a.getUint32(index) == b.getUint32(index)) continue;
      count++;
      for (var channel = 0; channel < 4; channel++) {
        final gap = (a.getUint8(index + channel) - b.getUint8(index + channel))
            .abs();
        if (gap > most) most = gap;
      }
    }
    return (count, most);
  }

  test(
    'the paint of a shade: modulate on what is opaque, multiply elsewhere',
    () {
      const shade = Color(0x8f1a205c);
      final on = veilShadePaint(shade, onOpaque: true);
      expect(on.blendMode, BlendMode.modulate);
      expect(on.color.a, 1);
      final a = shade.a;
      expect(on.color.r, closeTo(1 - a + a * shade.r, 1e-6));
      expect(on.color.g, closeTo(1 - a + a * shade.g, 1e-6));
      expect(on.color.b, closeTo(1 - a + a * shade.b, 1e-6));
      final off = veilShadePaint(shade, onOpaque: false);
      expect(off.blendMode, BlendMode.multiply);
      expect(off.color.toARGB32(), shade.toARGB32());
      // No shade at all changes nothing; a whole one is its colour.
      expect(
        veilShadePaint(
          const Color(0x00123456),
          onOpaque: true,
        ).color.toARGB32(),
        0xffffffff,
      );
      expect(
        veilShadePaint(
          const Color(0xff123456),
          onOpaque: true,
        ).color.toARGB32(),
        0xff123456,
      );
    },
  );

  testWidgets('on any opaque picture, any shade gives what multiply gave', (
    tester,
  ) async {
    // Every colour a channel can have under the shade, in bands, crossed
    // by a ramp; shades of every opacity, drawn at random, and the two of
    // the desk. Laid whole, and through the soft edge of a slanted outline.
    const frame = Size(256, 96);
    final random = numbers(7);
    var compared = 0;
    for (final shade in [
      const Color(0x8f1a205c),
      const Color(0x38e28046),
      const Color(0xff000000),
      const Color(0x00ffffff),
      const Color(0x01ffffff),
      const Color(0xfeffffff),
      for (var index = 0; index < 60; index++)
        Color.fromARGB(
          (random() * 256).floor(),
          (random() * 256).floor(),
          (random() * 256).floor(),
          (random() * 256).floor(),
        ),
    ]) {
      Future<ByteData> picture({required bool multiplies}) {
        return pixelsOf(tester, frame, 1, (canvas) {
          for (var value = 0; value < 256; value++) {
            canvas.drawRect(
              Rect.fromLTWH(value.toDouble(), 0, 1, 32),
              Paint()..color = Color.fromARGB(255, value, 255 - value, value),
            );
            canvas.drawRect(
              Rect.fromLTWH(value.toDouble(), 32, 1, 32),
              Paint()
                ..color = Color.fromARGB(255, value, value, (value * 7) % 256),
            );
            canvas.drawRect(
              Rect.fromLTWH(value.toDouble(), 64, 1, 32),
              Paint()
                ..color = Color.fromARGB(
                  255,
                  (value * 3) % 256,
                  (value * 5) % 256,
                  255 - value,
                ),
            );
          }
          final paint = veilShadePaint(shade, onOpaque: !multiplies);
          canvas.drawRect(const Rect.fromLTWH(0, 0, 256, 48), paint);
          canvas.drawPath(
            Path()
              ..fillType = PathFillType.evenOdd
              ..addRect(const Rect.fromLTWH(0, 48, 256, 48))
              ..addPolygon(const [
                Offset(20.3, 50.2),
                Offset(240.7, 60.9),
                Offset(130.1, 93.4),
              ], true),
            paint,
          );
        });
      }

      final before = await picture(multiplies: true);
      final after = await picture(multiplies: false);
      final (count, most) = differences(before, after);
      expect(
        (count, most),
        (0, 0),
        reason: 'shade $shade: $count pixels differ, by $most at most',
      );
      // And every pixel still lets nothing through.
      for (var index = 3; index < after.lengthInBytes; index += 4) {
        if (after.getUint8(index) != 255) fail('a pixel is not opaque');
      }
      compared++;
    }
    expect(compared, 66);
  });

  testWidgets(
    'the decor in the evening and at night is the picture multiply gave',
    (tester) async {
      // As the view makes its images: an opaque ground, the still pieces,
      // then the live ones and the light — the shade by multiply, as
      // before, and by modulate. Also in a frame that ends in the middle
      // of a pixel, and looked at on the whole frame.
      var compared = 0;
      for (final universe in UniverseCatalog.instance.universes) {
        final decor = universe.decor;
        if (decor == null) continue;
        for (final (frame, ratio, gaze) in [
          (const Size(1440, 900), 1.0, false),
          (const Size(1001, 701), 1.5, false),
          (const Size(1280, 800), 1.0, true),
          (const Size(701, 1101), 1.25, true),
        ]) {
          final layout = gaze
              ? DecorLayout.gaze(
                  frame: frame,
                  decor: decor.size,
                  decorSheet: decor.sheet,
                  middle: decor.middleBox,
                )
              : DecorLayout(
                  frame: frame,
                  sheetAtRest: Rect.fromCenter(
                    center: frame.center(Offset.zero),
                    width: frame.width * .5,
                    height: frame.height * .7,
                  ),
                  decor: decor.size,
                  decorSheet: decor.sheet,
                );
          final painting = DecorPainting(decor, layout);
          for (final moment in DayMoment.values) {
            if (decor.veils[moment]?.multiply == null) continue;
            final time = DateTime(
              2026,
              11,
              12,
              moment == DayMoment.soir ? 19 : 22,
              10,
            );
            expect(DayMoment.at(time), moment);
            Future<ByteData> picture({required bool? opaqueUnder}) => pixelsOf(
              tester,
              frame,
              ratio,
              (canvas) {
                canvas.save();
                canvas.scale(1 / ratio);
                canvas.drawColor(decor.top.withValues(alpha: 1), BlendMode.src);
                canvas.restore();
                painting.paintStill(canvas, moment);
                if (opaqueUnder == null) return;
                painting.paintLive(
                  canvas,
                  seconds: 3.7,
                  time: time,
                  motion: DecorMotion.high,
                  opaqueUnder: opaqueUnder,
                );
              },
            );

            final before = await picture(opaqueUnder: false);
            final after = await picture(opaqueUnder: true);
            final (count, most) = differences(before, after);
            expect(
              (count, most),
              (0, 0),
              reason:
                  '${universe.key}, $frame × $ratio, gaze $gaze, '
                  '${moment.name}: $count pixels differ, by $most at most',
            );
            // The shade does darken the room: this is not a picture
            // without it.
            final without = await picture(opaqueUnder: null);
            expect(differences(without, after).$1, greaterThan(100000));
            compared++;
          }
        }
      }
      // The desk by the window, in the evening and at night.
      expect(compared, greaterThanOrEqualTo(8));
    },
    skip: !available,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'the view shows the decor that multiply gave, at rest and moving',
    (tester) async {
      // The view itself, at night under the lamp and in the evening, in a
      // frame that ends in the middle of a pixel, around a sheet and
      // looked at: at rest, then image by image while it moves, taken
      // twice — the shade by multiply everywhere, as before, then as the
      // view lays it now. The same pixels.
      final decor = UniverseCatalog.instance.named('bureau').decor!;
      addTearDown(() {
        debugDecorStill = true;
        debugVeilMultiplies = false;
      });
      for (final (hour, ratio, gaze) in [
        (22, 1.0, false),
        (19, 1.5, false),
        (22, 1.25, true),
      ]) {
        const frame = Size(1001, 701);
        final time = DateTime(2026, 11, 12, hour, 10);
        debugDecorNow = () => time;
        tester.view.devicePixelRatio = ratio;
        tester.view.physicalSize = frame * ratio;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Future<List<ByteData>> images({required bool multiplies}) async {
          debugVeilMultiplies = multiplies;
          final taken = <ByteData>[];
          final key = GlobalKey();
          Future<void> take() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: ratio);
              taken.add(
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
              );
              image.dispose();
            });
          }

          for (final still in [true, false]) {
            debugDecorStill = still;
            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: key,
                    child: SizedBox.fromSize(
                      size: frame,
                      child: gaze
                          ? DecorView.gaze(
                              decor: decor,
                              motion: DecorMotion.high,
                            )
                          : DecorView(
                              decor: decor,
                              sheetAtRest: Rect.fromCenter(
                                center: frame.center(Offset.zero),
                                width: frame.width * .5,
                                height: frame.height * .7,
                              ),
                              motion: DecorMotion.high,
                            ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            if (still) {
              await take();
            } else {
              for (var image = 0; image < 6; image++) {
                await tester.pump(const Duration(milliseconds: 370));
                await take();
              }
            }
            await tester.pumpWidget(const SizedBox());
          }
          return taken;
        }

        final before = await images(multiplies: true);
        final after = await images(multiplies: false);
        expect(after.length, 7);
        for (var image = 0; image < after.length; image++) {
          expect(differences(before[image], after[image]), (
            0,
            0,
          ), reason: '$hour h, × $ratio, gaze $gaze, image $image');
          // It does move: not seven times the same image.
          if (image > 0) {
            expect(
              differences(after[image - 1], after[image]).$1,
              isNot(0),
              reason: '$hour h, × $ratio, gaze $gaze, image $image',
            );
          }
        }
        // And the room is in the shade: not the decor of the day.
        debugDecorNow = () => DateTime(2026, 11, 12, 14, 10);
        final byDay = await images(multiplies: false);
        expect(differences(byDay.first, after.first).$1, greaterThan(100000));
      }
    },
    skip: !available,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
