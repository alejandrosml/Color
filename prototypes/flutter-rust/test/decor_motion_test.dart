// SPDX-License-Identifier: MIT
// The movement of the decor (Color 1.2): four levels, each one the same
// movement made wider and longer; nothing at « Aucun »; nothing that
// blinks; the four moments of the day and the hands of the clock.
import 'dart:math' as math;

import 'package:edupaint_flutter_study/decor_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sway = DecorMove(name: 'balance', seconds: 9);

  test('the four levels: none, hardly, more, much more', () {
    expect(
      [for (final motion in DecorMotion.values) motion.code],
      ['aucun', 'faible', 'moyen', 'maximum'],
    );
    expect(DecorMotion.fromCode('moyen'), DecorMotion.medium);
    // Hardly, by default: what a file does not say, or says wrongly.
    expect(DecorMotion.fromCode(null), DecorMotion.low);
    expect(DecorMotion.fromCode('beaucoup'), DecorMotion.low);
    expect(DecorMotion.fromCode(3), DecorMotion.low);
    // The factors of the mock-ups: reach ×1, ×2, ×3.2; travel ×1, ×1.5, ×2.2.
    expect(
      [for (final motion in DecorMotion.values) motion.reach],
      [0, 1, 2, 3.2],
    );
    expect(
      [for (final motion in DecorMotion.values) motion.travel],
      [0, 1, 1.5, 2.2],
    );
    expect(DecorMotion.none.moves, isFalse);
    expect(DecorMotion.values.skip(1).every((motion) => motion.moves), isTrue);
    expect(
      [for (final motion in DecorMotion.values) motion.rank],
      [0, 1, 2, 3],
    );
  });

  test('at « Aucun » a piece is at rest, whatever the time', () {
    for (final name in decorMovementNames) {
      final move = DecorMove(name: name, seconds: 7, delay: -2);
      for (var seconds = 0.0; seconds < 30; seconds += .37) {
        expect(
          move.poseAt(seconds, DecorMotion.none),
          DecorPose.rest,
          reason: name,
        );
      }
    }
    expect(DecorPose.rest.isRest, isTrue);
    expect(DecorPose.rest.matrixAbout(10, 20), isNull);
  });

  test('a sway goes half a degree each way, wider at each level', () {
    // The ends and the middle of a period, as the mock-up writes them.
    expect(sway.poseAt(0, DecorMotion.low).turn, closeTo(-.5, 1e-9));
    expect(sway.poseAt(4.5, DecorMotion.low).turn, closeTo(.5, 1e-9));
    expect(sway.poseAt(9, DecorMotion.low).turn, closeTo(-.5, 1e-9));
    expect(sway.poseAt(4.5, DecorMotion.medium).turn, closeTo(1, 1e-9));
    expect(sway.poseAt(4.5, DecorMotion.high).turn, closeTo(1.6, 1e-9));
    // A quarter of the way: the middle of the glide, slow at both ends.
    expect(sway.poseAt(2.25, DecorMotion.low).turn, closeTo(0, 1e-6));
    expect(sway.poseAt(.45, DecorMotion.low).turn, lessThan(-.45));
    // The same place at every level, only wider: never another movement.
    for (var seconds = 0.0; seconds < 9; seconds += .5) {
      final low = sway.poseAt(seconds, DecorMotion.low).turn;
      expect(
        sway.poseAt(seconds, DecorMotion.medium).turn,
        closeTo(2 * low, 1e-9),
      );
      expect(
        sway.poseAt(seconds, DecorMotion.high).turn,
        closeTo(3.2 * low, 1e-9),
      );
    }
  });

  test(
    'a period follows the other without a jump, and a delay begins inside',
    () {
      // A whole turn is where it began: the sails of a windmill.
      double turned(double a, double b) {
        final apart = (a - b) % 360;
        return math.min(apart, 360 - apart);
      }

      for (final name in decorMovementNames) {
        final move = DecorMove(name: name, seconds: 6);
        for (final motion in DecorMotion.values.skip(1)) {
          final start = move.poseAt(0, motion);
          final end = move.poseAt(6 - 1e-9, motion);
          expect(turned(end.turn, start.turn), lessThan(1e-5), reason: name);
          expect(end.dx, closeTo(start.dx, 1e-5), reason: name);
          expect(end.dy, closeTo(start.dy, 1e-5), reason: name);
          expect(end.scaleY, closeTo(start.scaleY, 1e-5), reason: name);
          expect(end.opacity, closeTo(start.opacity, 1e-5), reason: name);
          // Two periods later, the same pose, to within the rounding of
          // the time.
          final later = move.poseAt(13.25, motion);
          final now = move.poseAt(1.25, motion);
          expect(turned(later.turn, now.turn), lessThan(1e-9), reason: name);
          for (final (a, b) in [
            (later.dx, now.dx),
            (later.dy, now.dy),
            (later.skew, now.skew),
            (later.scaleX, now.scaleX),
            (later.scaleY, now.scaleY),
            (later.opacity, now.opacity),
          ]) {
            expect(a, closeTo(b, 1e-9), reason: name);
          }
        }
      }
      // Minus two seconds: two seconds into the period when the decor appears.
      const late = DecorMove(name: 'balance', seconds: 7, delay: -2);
      const onTime = DecorMove(name: 'balance', seconds: 7);
      expect(
        late.poseAt(0, DecorMotion.low).turn,
        closeTo(onTime.poseAt(2, DecorMotion.low).turn, 1e-9),
      );
    },
  );

  test(
    'what travels goes farther at each level, what breathes swells more',
    () {
      const cloud = DecorMove(name: 'nuage', seconds: 34);
      expect(cloud.poseAt(17, DecorMotion.low).dx, closeTo(26, 1e-9));
      expect(cloud.poseAt(17, DecorMotion.medium).dx, closeTo(39, 1e-9));
      expect(cloud.poseAt(17, DecorMotion.high).dx, closeTo(57.2, 1e-9));
      const breath = DecorMove(name: 'souffle', seconds: 4.6);
      expect(breath.poseAt(2.3, DecorMotion.low).scaleY, closeTo(1.022, 1e-9));
      expect(
        breath.poseAt(2.3, DecorMotion.high).scaleY,
        closeTo(1.0704, 1e-9),
      );
      expect(breath.poseAt(2.3, DecorMotion.low).scaleX, 1);
    },
  );

  test('nothing blinks, at any level', () {
    // What fades never goes out of sight, and never faster than a slow
    // breath: over a tenth of a second, less than a twentieth of its
    // opacity, at every level and for every movement.
    for (final name in decorMovementNames) {
      for (final seconds in [4.0, 6.0, 9.0]) {
        final move = DecorMove(name: name, seconds: seconds);
        for (final motion in DecorMotion.values.skip(1)) {
          var before = move.poseAt(0, motion).opacity;
          for (var time = .1; time < 2 * seconds; time += .1) {
            final now = move.poseAt(time, motion).opacity;
            expect(now, inInclusiveRange(.5, 1), reason: name);
            expect((now - before).abs(), lessThan(.05), reason: name);
            before = now;
          }
        }
      }
    }
    // And the chalk is the same at every level: a level never makes it
    // quicker or deeper.
    const chalk = DecorMove(name: 'craie', seconds: 6);
    expect(
      chalk.poseAt(1.5, DecorMotion.high).opacity,
      chalk.poseAt(1.5, DecorMotion.low).opacity,
    );
  });

  test('the forest and the countryside: sails that turn evenly, a leaf that '
      'comes back, a hen that pecks about its feet, two ways of flying', () {
    // A whole turn in its period, at an even pace, the same at every level.
    const sails = DecorMove(name: 'tourne', seconds: 28);
    for (final motion in DecorMotion.values.skip(1)) {
      expect(sails.poseAt(7, motion).turn, closeTo(90, 1e-9));
      expect(sails.poseAt(14, motion).turn, closeTo(180, 1e-9));
      expect(sails.poseAt(21, motion).turn, closeTo(270, 1e-9));
    }
    expect(sails.poseAt(7, DecorMotion.none), DecorPose.rest);
    // The leaf falls and is lifted again: never out of sight.
    const leaf = DecorMove(name: 'tombe', seconds: 15);
    expect(leaf.poseAt(7.5, DecorMotion.low).dy, closeTo(60, 1e-9));
    expect(leaf.poseAt(7.5, DecorMotion.high).dy, closeTo(132, 1e-9));
    expect(leaf.poseAt(15, DecorMotion.high).isRest, isTrue);
    // The hen stands still most of the time, then leans forward twice.
    const hen = DecorMove(name: 'picore', seconds: 5);
    expect(hen.poseAt(2, DecorMotion.low).isRest, isTrue);
    expect(hen.poseAt(3.9, DecorMotion.low).turn, closeTo(8, 1e-9));
    expect(hen.poseAt(4.6, DecorMotion.high).turn, closeTo(17.6, 1e-9));
    // A swallow of the left flies to the right, one of the right to the
    // left; the butterfly to the left; both rise.
    const right = DecorMove(name: 'vol', seconds: 9);
    const left = DecorMove(name: 'vol2', seconds: 9);
    const butterfly = DecorMove(name: 'papillon', seconds: 14);
    expect(right.poseAt(4.5, DecorMotion.low).dx, closeTo(50, 1e-9));
    expect(left.poseAt(4.5, DecorMotion.low).dx, closeTo(-50, 1e-9));
    expect(left.poseAt(4.5, DecorMotion.low).dy, closeTo(-16, 1e-9));
    expect(butterfly.poseAt(7, DecorMotion.high).dx, closeTo(-154, 1e-9));
    // The robin hops now and then, higher at each level.
    const robin = DecorMove(name: 'sautille', seconds: 7);
    expect(robin.poseAt(3, DecorMotion.low).isRest, isTrue);
    expect(robin.poseAt(.88 * 7, DecorMotion.medium).dy, closeTo(-12, 1e-9));
  });

  test('the mountain: an eagle that soars, a cabin that climbs its cable and '
      'is smaller up there', () {
    // The eagle goes round and comes back, further at each level.
    const eagle = DecorMove(name: 'plane', seconds: 16);
    expect(eagle.poseAt(0, DecorMotion.low).turn, closeTo(-4, 1e-9));
    expect(eagle.poseAt(8, DecorMotion.low).dx, closeTo(26, 1e-9));
    expect(eagle.poseAt(8, DecorMotion.high).dx, closeTo(57.2, 1e-9));
    expect(eagle.poseAt(16, DecorMotion.high).turn, closeTo(-4, 1e-9));
    // The cabin climbs the same cable at every level: up and to the left,
    // half as large at the top, and back to its station.
    const cabin = DecorMove(name: 'cabine', seconds: 22);
    for (final motion in DecorMotion.values.skip(1)) {
      final top = cabin.poseAt(11, motion);
      expect(top.dx, closeTo(-140, 1e-9));
      expect(top.dy, closeTo(-109.3, 1e-9));
      expect(top.scaleX, closeTo(.5, 1e-9));
      expect(top.scaleY, closeTo(.5, 1e-9));
      expect(cabin.poseAt(22, motion).isRest, isTrue);
      // Along the cable all the way: down 0.781 for each unit to the right.
      final half = cabin.poseAt(.22 * 22, motion);
      expect(half.dy / half.dx, closeTo(109.3 / 140, 1e-9));
    }
    expect(cabin.poseAt(11, DecorMotion.none), DecorPose.rest);
  });

  test('a pose turns its piece about its origin', () {
    const pose = DecorPose(turn: 90);
    final matrix = pose.matrixAbout(10, 20)!;
    // The origin stays where it is…
    double x(double px, double py) =>
        matrix[0] * px + matrix[4] * py + matrix[12];
    double y(double px, double py) =>
        matrix[1] * px + matrix[5] * py + matrix[13];
    expect(x(10, 20), closeTo(10, 1e-9));
    expect(y(10, 20), closeTo(20, 1e-9));
    // … and a point on its right goes under it.
    expect(x(15, 20), closeTo(10, 1e-9));
    expect(y(15, 20), closeTo(25, 1e-9));
    // A breath stretches upwards from the cushion: the bottom stays.
    final breath = const DecorPose(scaleY: 1.1).matrixAbout(0, 100)!;
    expect(breath[5] * 100 + breath[13], closeTo(100, 1e-9));
    expect(breath[5] * 50 + breath[13], closeTo(45, 1e-9));
    // A lean of 45 degrees moves what is above the origin sideways.
    final lean = const DecorPose(skew: 45).matrixAbout(0, 0)!;
    expect(lean[4], closeTo(math.tan(math.pi / 4), 1e-9));
  });

  test('a movement the description names wrongly leaves its piece still', () {
    expect(DecorMove.fromJson(null), isNull);
    expect(DecorMove.fromJson({'name': 'danse', 'seconds': 4}), isNull);
    expect(DecorMove.fromJson({'name': 'balance'}), isNull);
    // Faster than a second would be a flicker: refused.
    expect(DecorMove.fromJson({'name': 'balance', 'seconds': .2}), isNull);
    expect(
      DecorMove.fromJson({'name': 'balance', 'seconds': double.nan}),
      isNull,
    );
    final move = DecorMove.fromJson({
      'name': 'balance',
      'seconds': 9,
      'delay': -2,
      'origin': [119.9, 22],
    })!;
    expect(move.seconds, 9);
    expect(move.delay, -2);
    expect(move.originX, 119.9);
    expect(move.originY, 22);
    final plain = DecorMove.fromJson({
      'name': 'nuage',
      'seconds': 34,
      'origin': 'ici',
    })!;
    expect((plain.originX, plain.originY, plain.delay), (0, 0, 0));
  });

  test('the four moments of the day, by the hour of the device', () {
    DayMoment at(int hour, [int minute = 0]) =>
        DayMoment.at(DateTime(2026, 11, 12, hour, minute));
    expect(at(5, 59), DayMoment.nuit);
    expect(at(6), DayMoment.matin);
    expect(at(10, 59), DayMoment.matin);
    expect(at(11), DayMoment.jour);
    expect(at(16, 59), DayMoment.jour);
    expect(at(17), DayMoment.soir);
    expect(at(20, 59), DayMoment.soir);
    expect(at(21), DayMoment.nuit);
    expect(at(0), DayMoment.nuit);
    expect(at(23, 59), DayMoment.nuit);
    expect(DayMoment.named('soir'), DayMoment.soir);
    expect(DayMoment.named('midi'), isNull);
  });

  test('the hands of the clock are at the time', () {
    ({double hour, double minute}) at(int hour, int minute) =>
        clockHands(DateTime(2026, 11, 12, hour, minute, 42));
    expect(at(12, 0), (hour: 0, minute: 0));
    expect(at(3, 0), (hour: 90, minute: 0));
    expect(at(15, 0), (hour: 90, minute: 0));
    // Half past two: the small hand halfway between two and three.
    expect(at(14, 30), (hour: 75, minute: 180));
    expect(at(22, 10), (hour: 305, minute: 60));
    expect(at(23, 59), (hour: 359.5, minute: 354));
  });
}
