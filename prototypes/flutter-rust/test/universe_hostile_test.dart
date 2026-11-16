// SPDX-License-Identifier: MIT
// Color — Alejandro San Martin Lamas — https://github.com/alejandrosml
//
// Descriptions of universes that are damaged (étape 7 of Color 1.2): each
// real one, with one or two of its values taken out or replaced by another
// kind of value — nothing, a number too large, a list too short, a text. A
// damaged description gives no universe, or a universe with what could be
// read of it; reading it and painting its decor never throw.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edupaint_flutter_study/decor.dart';
import 'package:edupaint_flutter_study/decor_motion.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/universe.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sequence that is the same at every run: a failure names its round.
class _Sequence {
  _Sequence(this._state);
  int _state;
  int below(int limit) {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return (_state >> 8) % limit;
  }
}

const _infinite = '@infini@';

/// What takes the place of a value.
const _hostile = <Object?>[
  null,
  true,
  0,
  -1,
  0.5,
  1e308,
  -1e308,
  _infinite,
  '',
  'x',
  '#12',
  '#ffffffff',
  <Object?>[],
  <Object?>[1],
  <Object?>[1, 2],
  <Object?>[1, 2, 3],
  <Object?>[0, 0, 0, 0],
  <Object?>[1, 2, 3, 4, 5],
  <Object?>[_infinite, _infinite],
  <Object?>[-5, -5, -5, -5],
  <Object?>['a', 'b'],
  <String, Object?>{},
  <String, Object?>{'a': 1},
];

/// Every place of [json]: the list or the map that holds a value, and its
/// index or its name there.
void _places(Object? json, List<(Object, Object)> into) {
  if (json is Map) {
    for (final key in json.keys.toList()) {
      into.add((json, key as Object));
      _places(json[key], into);
    }
  } else if (json is List) {
    for (var index = 0; index < json.length; index++) {
      into.add((json, index));
      _places(json[index], into);
    }
  }
}

void _damage(Object? json, _Sequence random) {
  final places = <(Object, Object)>[];
  _places(json, places);
  if (places.isEmpty) return;
  final (holder, at) = places[random.below(places.length)];
  final what = random.below(_hostile.length + 3);
  if (holder is Map) {
    if (what >= _hostile.length) {
      holder.remove(at);
    } else {
      holder[at] = jsonDecode(jsonEncode(_hostile[what]));
    }
  } else if (holder is List) {
    final index = at as int;
    if (what == _hostile.length) {
      holder.removeAt(index);
    } else if (what > _hostile.length) {
      holder.insert(index, holder[index]);
    } else {
      holder[index] = jsonDecode(jsonEncode(_hostile[what]));
    }
  }
}

void _paint(Decor decor) {
  const frames = [Size(1280, 800), Size(390, 844), Size(40, 30)];
  for (final frame in frames) {
    final layouts = [
      DecorLayout(
        frame: frame,
        sheetAtRest: Rect.fromCenter(
          center: frame.center(Offset.zero),
          width: frame.width * .5,
          height: frame.height * .7,
        ),
        decor: decor.size,
        decorSheet: decor.sheet,
      ),
      DecorLayout.gaze(
        frame: frame,
        decor: decor.size,
        decorSheet: decor.sheet,
        middle: decor.middleBox,
      ),
    ];
    for (final layout in layouts) {
      final painting = DecorPainting(decor, layout);
      for (final hour in const [8, 14, 19, 23]) {
        final time = DateTime(2026, 11, 12, hour, 10);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painting.paintStill(canvas, DayMoment.at(time));
        for (final opaque in const [false, true]) {
          painting.paintLive(
            canvas,
            seconds: 12.5,
            time: time,
            motion: DecorMotion.high,
            opaqueUnder: opaque,
          );
        }
        recorder.endRecording().dispose();
      }
      // What a child may ask the name of, wherever it presses.
      for (final name in decor.names) {
        layout.place(name.at, name.anchor);
      }
    }
  }
}

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  test('a damaged description gives no universe or what could be read: never '
      'an exception, reading it or painting it', () {
    final random = _Sequence(20261116);
    var none = 0, read = 0, painted = 0;
    final count = RustDocument.universeCount();
    expect(count, greaterThan(0));
    for (var index = 0; index < count; index++) {
      final text = RustDocument.readUniverse(index)!;
      final first = text.indexOf('\n');
      final second = text.indexOf('\n', first + 1);
      final head = text.substring(0, first + 1);
      final described = text.substring(first + 3, second);
      final pictures = text.substring(second);
      for (var round = 0; round < 60; round++) {
        final json = jsonDecode(described);
        for (var times = 1 + random.below(2); times > 0; times--) {
          _damage(json, random);
        }
        // A number beyond what a double holds is read as the infinite.
        final damaged = jsonEncode(json).replaceAll('"$_infinite"', '1e999');
        final said = 'universe $index, round $round: $damaged';
        final Universe? universe;
        try {
          universe = Universe.parse('${head}M $damaged$pictures');
        } catch (error, stack) {
          fail('reading throws $error\n$stack\n$said');
        }
        if (universe == null) {
          none++;
          continue;
        }
        read++;
        final decor = universe.decor;
        if (decor == null) continue;
        try {
          _paint(decor);
          painted++;
        } catch (error, stack) {
          fail('painting throws $error\n$stack\n$said');
        }
      }
    }
    // The damage is neither always harmless nor always fatal.
    expect(none, greaterThan(5), reason: '$none refused, $read read');
    expect(painted, greaterThan(100), reason: '$painted painted');
  }, skip: !available);

  test('a number beyond any decor — the angle of the lamp, a place, a time — '
      'is not read: the decor is painted without it', () {
    // Found by the damaged descriptions above, on a longer run: the angle
    // of the lamp at -1e308 degrees, a number a double holds, became a
    // beam of points that are no numbers, which the canvas refuses.
    final text = RustDocument.readUniverse(1)!;
    final first = text.indexOf('\n');
    final second = text.indexOf('\n', first + 1);
    final pictures = text.substring(second);
    Map<String, dynamic> described() =>
        jsonDecode(text.substring(first + 3, second)) as Map<String, dynamic>;
    final lamp = described()['decor']['light']['lamp'] as Map<String, dynamic>;
    expect(lamp.keys, containsAll(['angle', 'half', 'rim', 'rimHalf']));
    Decor? decorOf(Map<String, dynamic> json) => Universe.parse(
      '${text.substring(0, first + 1)}M ${jsonEncode(json)}$pictures',
    )?.decor;
    expect(decorOf(described())!.lamp, isNotNull);
    for (final huge in const [1e308, -1e308, 1e7]) {
      for (final name in const ['angle', 'rim', 'rimHalf', 'bulbRadius']) {
        final json = described();
        json['decor']['light']['lamp'][name] = huge;
        final decor = decorOf(json)!;
        expect(decor.lamp, isNull, reason: '$name $huge');
        _paint(decor);
      }
      for (final change in <void Function(Map<String, dynamic> decor)>[
        (decor) => decor['light']['lamp']['pivot'] = [huge, huge],
        (decor) => decor['light']['lamp']['bulb'] = [huge, 0],
        (decor) => decor['light']['lamp']['hood'][3] = huge,
        (decor) => decor['light']['veils']['matin']['gradient'][0] = huge,
        (decor) => decor['sheet'] = [huge, huge, huge.abs(), huge.abs()],
        (decor) => decor['pieces'][1]['at'] = [0, 0, huge.abs(), huge.abs()],
        (decor) => decor['pieces'][6]['clip'] = [huge, huge, 5, 5],
        (decor) => decor['pieces'][6]['move']['seconds'] = huge.abs(),
        (decor) => decor['pieces'][8]['move']['delay'] = huge,
        (decor) => decor['pieces'][8]['move']['origin'] = [huge, huge],
        (decor) => decor['pieces'][11]['centre'] = [huge, huge],
        (decor) => decor['pieces'][11]['hour'] = [huge.abs(), huge.abs()],
        (decor) => decor['names'][0]['at'] = [huge, huge, 5, 5],
      ]) {
        final json = described();
        change(json['decor'] as Map<String, dynamic>);
        final decor = decorOf(json);
        if (decor != null) _paint(decor);
      }
      final json = described();
      json['decor']['size'] = [huge.abs(), huge.abs()];
      expect(decorOf(json), isNull);
    }
    // A number of a decor is read as before.
    final json = described();
    json['decor']['light']['lamp']['angle'] = -725.5;
    expect(decorOf(json)!.lamp!.angle, -725.5);
  }, skip: !available);

  test('a description cut anywhere, or of bytes of any kind, gives nothing or '
      'a universe, never an exception', () {
    final random = _Sequence(7);
    final text = RustDocument.readUniverse(1)!;
    final end = text.indexOf('\n', text.indexOf('\n') + 1) + 400;
    for (var cut = 0; cut < end; cut += 1 + random.below(9)) {
      Universe.parse(text.substring(0, cut));
      final bytes = text.substring(0, end).codeUnits.toList();
      for (var times = 0; times < 3; times++) {
        bytes[random.below(bytes.length)] = 32 + random.below(95);
      }
      Universe.parse(String.fromCharCodes(bytes));
    }
  }, skip: !available);
}
