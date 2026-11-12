// SPDX-License-Identifier: MIT
// The universes of the studio as the core hands them over (Color 1.2):
// their descriptions read, their pictures found, their looks readable, and
// what the options keep of them.
import 'dart:convert';
import 'dart:io';

import 'package:edupaint_flutter_study/decor.dart';
import 'package:edupaint_flutter_study/decor_motion.dart';
import 'package:edupaint_flutter_study/platform_words.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_colors.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/universe.dart';
import 'package:edupaint_flutter_study/vector_art.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'readability_test.dart' show contrast;

void main() {
  final available = Platform.environment['EDUPAINT_CORE_LIBRARY'] != null;

  // The description of universe [index], as the core wrote it.
  Map<String, dynamic> described(int index) {
    final text = RustDocument.readUniverse(index)!;
    final line = text.split('\n')[1];
    return jsonDecode(line.substring(2)) as Map<String, dynamic>;
  }

  // The universes that have a decor: « Classique » has none.
  List<Universe> decorated() => [
    for (final universe in UniverseCatalog.instance.universes)
      if (universe.decor != null) universe,
  ];

  test(
    'the core has « Classique », the desk by the window, paper and pencils',
    () {
      final catalog = UniverseCatalog.instance;
      expect(
        [for (final u in catalog.universes) u.key],
        ['classique', 'bureau', 'papier'],
      );
      expect(catalog.first.frenchName, 'Classique');
      expect(catalog.universes[1].frenchName, 'Le bureau près de la fenêtre');
      expect(catalog.universes[2].frenchName, 'Papier et crayons');
      expect(RustDocument.universeCount(), 3);
      expect(RustDocument.readUniverse(3), isNull);
      expect(RustDocument.readUniverse(-1), isNull);
      expect(catalog.named('papier').key, 'papier');
      expect(catalog.named('classique').key, 'classique');
      // « Classique » is the workshop of always, and has no decor.
      expect(catalog.first.decor, isNull);
      expect(catalog.first.look, same(StudioLook.classic));
    },
    skip: !available,
  );

  test('whoever names no universe gets that of the device', () {
    final catalog = UniverseCatalog.instance;
    addTearDown(() => debugTouchFirstOverride = null);
    // A computer: the first one with a decor, the desk by the window.
    debugTouchFirstOverride = false;
    expect(catalog.ofDevice.key, 'bureau');
    expect(catalog.named('').key, 'bureau');
    expect(catalog.named(null).key, 'bureau');
    expect(catalog.named('lune').key, 'bureau');
    // A tablet, a telephone: no decor around the sheet, so « Classique ».
    debugTouchFirstOverride = true;
    expect(catalog.ofDevice.key, 'classique');
    expect(catalog.named('').key, 'classique');
    expect(catalog.named('lune').key, 'classique');
    // What was chosen stays chosen, on either.
    expect(catalog.named('bureau').key, 'bureau');
    debugTouchFirstOverride = false;
    expect(catalog.named('classique').key, 'classique');
    // A catalogue where every universe has a decor, or none: the first.
    final one = UniverseCatalog([Universe.plain]);
    expect(one.ofDevice, same(Universe.plain));
    debugTouchFirstOverride = true;
    expect(UniverseCatalog([catalog.named('papier')]).ofDevice.key, 'papier');
  }, skip: !available);

  test('every piece has its picture, every movement is known', () {
    for (var index = 0; index < RustDocument.universeCount(); index++) {
      final json = described(index);
      final universe = UniverseCatalog.instance.universes[index];
      final decor = universe.decor;
      // A universe without a decor says nothing of one.
      expect(decor == null, json['decor'] == null, reason: universe.key);
      if (decor == null) continue;
      final pieces = (json['decor'] as Map)['pieces'] as List;
      // Nothing of the description was left out.
      expect(decor.pieces, hasLength(pieces.length), reason: universe.key);
      expect(
        decor.pieces.where((piece) => piece.move != null),
        hasLength(
          pieces.where((piece) => (piece as Map)['move'] != null).length,
        ),
        reason: universe.key,
      );
      expect(decor.pieces.first.role, DecorRole.ground);
      for (final piece in decor.pieces) {
        if (piece.role == DecorRole.clock) {
          expect(piece.clock, isNotNull);
          continue;
        }
        final names = piece.role == DecorRole.sky
            ? [
                for (final moment in DayMoment.values)
                  '${piece.picture}-${moment.name}',
              ]
            : [piece.picture!];
        for (final name in names) {
          expect(decor.pictures, contains(name), reason: universe.key);
        }
        // A picture laid somewhere keeps its shape.
        final at = piece.at;
        if (at != null) {
          final picture = decor.pictures[names.first]!;
          expect(
            at.width / at.height,
            closeTo(picture.width / picture.height, .02),
            reason: '${universe.key} ${piece.picture}',
          );
        } else {
          expect(decor.pictures[names.first]!.width, decor.size.width);
          expect(decor.pictures[names.first]!.height, decor.size.height);
        }
      }
      // And every picture of the core is a piece of the decor.
      final used = {
        for (final piece in decor.pieces)
          if (piece.role == DecorRole.sky)
            for (final moment in DayMoment.values)
              '${piece.picture}-${moment.name}'
          else
            ?piece.picture,
      };
      expect(decor.pictures.keys.toSet(), used, reason: universe.key);
    }
  }, skip: !available);

  test(
    'the desk: what is kept in one picture, what moves, what follows the hour',
    () {
      final decor = UniverseCatalog.instance.named('bureau').decor!;
      expect(decor.size, const Size(1061, 407));
      expect(decor.sheet, const Rect.fromLTWH(266, 26, 526, 351));
      expect(
        [for (final piece in decor.still) piece.picture],
        ['fond', 'ciel', 'gauche', 'crayons', 'droite', 'milieu'],
      );
      expect(
        [for (final piece in decor.live) piece.picture ?? 'horloge'],
        [
          'nuage',
          'fenetre',
          'rideau-gauche',
          'rideau-droite',
          'plante',
          'horloge',
          'chat',
        ],
      );
      // Each curtain sways about the middle of its own top, under the rod,
      // which goes with the window and does not move.
      expect(decor.live[1].move, isNull);
      expect(decor.live[2].move!.name, 'balance');
      expect(decor.live[2].move!.originX, 43);
      expect(decor.live[3].move!.originX, 217);
      expect(decor.live[3].move!.delay, isNot(decor.live[2].move!.delay));
      expect(decor.followsTheHour, isTrue);
      expect(decor.hasMovement, isTrue);
      // The cloud passes behind the window in the morning and by day only.
      final cloud = decor.live.first;
      expect(cloud.moments, {DayMoment.matin, DayMoment.jour});
      expect(cloud.clip, const Rect.fromLTWH(47, 41, 166, 188));
      expect(cloud.move!.name, 'nuage');
      // The lamp is lit in the evening and at night; the day has no veil.
      expect(decor.lamp!.moments, {DayMoment.soir, DayMoment.nuit});
      expect(decor.veils.keys.toSet(), {
        DayMoment.matin,
        DayMoment.soir,
        DayMoment.nuit,
      });
      expect(decor.veils[DayMoment.nuit]!.multiply, const Color(0x8f1a205c));
      expect(decor.veils[DayMoment.matin]!.gradient!.$1, 100);
      // The clock: 12, 3, 6, 9 are drawn; the hands are painted at the time.
      final clock = decor.live[5].clock!;
      expect(clock.centre, const Offset(848, 66));
      expect(clock.hour, const Size(3.6, 11));
      expect(clock.minute, const Size(2.6, 16.5));
    },
    skip: !available,
  );

  test('paper and pencils: a decor that does not follow the hour', () {
    final decor = UniverseCatalog.instance.named('papier').decor!;
    expect(decor.followsTheHour, isFalse);
    expect(decor.hasMovement, isTrue);
    expect(
      [for (final piece in decor.still) piece.picture],
      ['fond', 'gauche', 'droite'],
    );
    expect(
      [for (final piece in decor.live) piece.move!.name],
      ['craie', 'bascule'],
    );
    expect(decor.lamp, isNull);
    expect(decor.veils, isEmpty);
  }, skip: !available);

  test('what a child may ask about: fourteen things of the desk, eight of the paper', () {
    final catalog = UniverseCatalog.instance;
    expect(catalog.named('bureau').decor!.names, hasLength(14));
    expect(catalog.named('papier').decor!.names, hasLength(8));
    for (final universe in decorated()) {
      final decor = universe.decor!;
      final frame = Offset.zero & decor.size;
      final keys = <String>{};
      for (final name in decor.names) {
        expect(keys.add(name.key), isTrue, reason: name.key);
        expect(name.frenchName, isNotEmpty);
        // One or two lines, never a page.
        expect(
          name.frenchText.length,
          inInclusiveRange(20, 130),
          reason: name.key,
        );
        expect(
          frame.contains(name.at.topLeft) &&
              frame.contains(name.at.bottomRight - const Offset(.01, .01)),
          isTrue,
          reason: name.key,
        );
        // A child must see it whole: nothing named lies under the sheet.
        switch (name.anchor) {
          case DecorAnchor.left:
            expect(
              name.at.right,
              lessThanOrEqualTo(decor.sheet.left),
              reason: name.key,
            );
          case DecorAnchor.right:
            expect(
              name.at.left,
              greaterThanOrEqualTo(decor.sheet.right),
              reason: name.key,
            );
          case DecorAnchor.middle:
            expect(
              name.at.top,
              greaterThanOrEqualTo(decor.sheet.bottom),
              reason: name.key,
            );
        }
      }
      // The smallest first: a small thing on a large one is found.
      final areas = [
        for (final name in decor.names) name.at.width * name.at.height,
      ];
      expect(areas, [...areas]..sort());
    }
  }, skip: !available);

  // « Absolument tous les éléments dans l'écran en entier » (the owner,
  // 12 November 2026): nothing of a decor is cut by an edge of its frame.
  // Only the ground reaches the edges.
  test('nothing of a decor goes beyond its frame, at its widest movement', () {
    for (final universe in decorated()) {
      final decor = universe.decor!;
      final frame = Offset.zero & decor.size;
      bool inFrame(Rect box) =>
          box.left >= -.01 &&
          box.top >= -.01 &&
          box.right <= frame.right + .01 &&
          box.bottom <= frame.bottom + .01;
      // The ground does reach every edge: it is what fills the frame.
      final ground = decor.drawnBox(decor.pieces.first)!;
      expect(ground.left, lessThanOrEqualTo(0), reason: universe.key);
      expect(ground.top, lessThanOrEqualTo(0), reason: universe.key);
      expect(ground.right, greaterThanOrEqualTo(frame.right));
      expect(ground.bottom, greaterThanOrEqualTo(frame.bottom));
      var moving = 0;
      for (final piece in decor.pieces.skip(1)) {
        final what = '${universe.key} ${piece.picture ?? 'horloge'}';
        final clip = piece.clip;
        if (clip != null) expect(inFrame(clip), isTrue, reason: what);
        final move = piece.move;
        if (move != null) moving++;
        // Every level, along the whole of a period; every moment of the
        // day for what changes with it.
        final moments = piece.role == DecorRole.sky || piece.moments != null
            ? (piece.moments ?? DayMoment.values.toSet())
            : {DayMoment.jour};
        for (final moment in moments) {
          for (final motion in DecorMotion.values) {
            final steps = move == null || !motion.moves ? 1 : 48;
            for (var step = 0; step < steps; step++) {
              final pose =
                  move?.poseAt(move.seconds * step / steps, motion) ??
                  DecorPose.rest;
              final box = decor.drawnBox(piece, pose: pose, moment: moment);
              if (clip != null && box == null) continue;
              expect(box, isNotNull, reason: what);
              expect(
                inFrame(box!),
                isTrue,
                reason:
                    '$what, ${motion.code}, ${moment.name}, '
                    'pas $step : $box',
              );
              // And a child sees it whole: nothing of it is under the
              // sheet either.
              final beside = switch (piece.anchor) {
                DecorAnchor.left => box.right <= decor.sheet.left + .01,
                DecorAnchor.right => box.left >= decor.sheet.right - .01,
                DecorAnchor.middle => box.top >= decor.sheet.bottom - .01,
              };
              expect(beside, isTrue, reason: '$what, ${motion.code} : $box');
            }
          }
        }
      }
      expect(moving, greaterThan(0), reason: universe.key);
    }
  }, skip: !available);

  test('the box of what a picture draws: strokes, groups and clips', () {
    VectorPicture read(String body) => VectorPicture.fromSvg(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 60" '
      'width="100" height="60">$body</svg>',
    )!;
    void same(Rect? box, Rect expected) {
      expect(box, isNotNull);
      for (final (got, wanted) in [
        (box!.left, expected.left),
        (box.top, expected.top),
        (box.right, expected.right),
        (box.bottom, expected.bottom),
      ]) {
        expect(got, closeTo(wanted, .15), reason: '$box, not $expected');
      }
    }

    // A shape alone; then with a line around it, half of which is outside.
    same(
      read('<rect x="10" y="20" width="30" height="10" fill="#f00"/>')
          .drawnBounds(),
      const Rect.fromLTRB(10, 20, 40, 30),
    );
    same(
      read(
        '<rect x="10" y="20" width="30" height="10" fill="#f00" '
        'stroke="#000" stroke-width="4" stroke-linejoin="round"/>',
      ).drawnBounds(),
      const Rect.fromLTRB(8, 18, 42, 32),
    );
    // A curve counts for what it draws, not for its control point.
    same(
      read(
        '<path d="M0 50 Q50 -50 100 50" fill="none" stroke="#000" '
        'stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
      ).drawnBounds(),
      const Rect.fromLTRB(-1, -1, 101, 51),
    );
    // What goes beyond the picture is counted: it is what would be cut.
    same(
      read('<circle cx="95" cy="30" r="10" fill="#00f"/>').drawnBounds(),
      const Rect.fromLTRB(85, 20, 105, 40),
    );
    // A group that moves its content, and one that cuts it.
    same(
      read(
        '<g transform="translate(50 10) rotate(90)">'
        '<rect width="20" height="10" fill="#0a0"/></g>',
      ).drawnBounds(),
      const Rect.fromLTRB(40, 10, 50, 30),
    );
    same(
      read(
        '<defs><clipPath id="c"><rect x="20" y="0" width="30" height="60"/>'
        '</clipPath></defs><g clip-path="url(#c)">'
        '<rect x="0" y="25" width="100" height="10" fill="#0a0"/></g>',
      ).drawnBounds(),
      const Rect.fromLTRB(20, 25, 50, 35),
    );
    // Placed elsewhere: twice as large, moved.
    final placed = Float64List(16)
      ..[0] = 2
      ..[5] = 2
      ..[10] = 1
      ..[12] = 100
      ..[13] = -5
      ..[15] = 1;
    same(
      read('<rect x="10" y="20" width="30" height="10" fill="#f00"/>')
          .drawnBounds(placed: placed),
      const Rect.fromLTRB(120, 35, 180, 55),
    );
    // What a clip leaves nothing of draws nothing.
    expect(
      read(
        '<defs><clipPath id="c"><rect x="80" y="0" width="10" height="60"/>'
        '</clipPath></defs><g clip-path="url(#c)">'
        '<rect x="0" y="25" width="50" height="10" fill="#0a0"/></g>',
      ).drawnBounds(),
      isNull,
    );
  }, skip: !available);

  test('what lies under the sheet: its box, for a decor without a sheet', () {
    final desk = UniverseCatalog.instance.named('bureau').decor!;
    // The eraser, the brush and two drops of paint, in the middle.
    final box = desk.middleBox!;
    expect(box.left, closeTo(435.5, 1.5));
    expect(box.right, closeTo(627.5, 1.5));
    expect(box.top, greaterThanOrEqualTo(desk.sheet.bottom));
    expect(box.bottom, lessThanOrEqualTo(desk.size.height));
    expect(box.center.dx, closeTo(desk.sheet.center.dx, 4));
    // Nothing lies under the sheet of the paper.
    expect(UniverseCatalog.instance.named('papier').decor!.middleBox, isNull);
  }, skip: !available);

  test('the desk keeps the look of always; the paper has its own', () {
    final catalog = UniverseCatalog.instance;
    final desk = catalog.named('bureau').look;
    const classic = StudioLook.classic;
    expect(desk.ink, classic.ink);
    expect(desk.accent, classic.accent);
    expect(desk.background, classic.background);
    expect(desk.buttonRadius, classic.buttonRadius);
    expect(desk.buttonDashed, isFalse);
    expect(desk.tool, ToolShape.tile);
    // Softer shadows under its cards, and nothing else.
    expect(desk.panelShadow, PanelShadow.soft);
    final paper = catalog.named('papier').look;
    expect(paper.background, const Color(0xffd9bd92));
    expect(paper.buttonDashed, isTrue);
    expect(paper.buttonRadius, 5);
    expect(paper.panelShadow, PanelShadow.paper);
    expect(paper.tool, ToolShape.sticker);
    expect(paper, isNot(classic));
  }, skip: !available);

  test('every text of every universe can be read on its surface', () {
    final looks = {
      'Classique': StudioLook.classic,
      for (final universe in UniverseCatalog.instance.universes)
        universe.key: universe.look,
    };
    for (final MapEntry(key: universe, value: look) in looks.entries) {
      for (final (name, text, surface) in look.textOnSurface) {
        expect(
          contrast(text, surface),
          greaterThanOrEqualTo(name == 'nom Color' ? 3 : 4.5),
          reason:
              '$universe, $name : ${contrast(text, surface).toStringAsFixed(2)}',
        );
      }
      for (final (name, mark, surface) in look.marksOnSurface) {
        expect(
          contrast(mark, surface),
          greaterThanOrEqualTo(3),
          reason:
              '$universe, $name : ${contrast(mark, surface).toStringAsFixed(2)}',
        );
      }
    }
  }, skip: !available);

  test('a look says only what differs from « Classique »', () {
    expect(StudioLook.fromJson(null), StudioLook.classic);
    expect(StudioLook.fromJson('papier'), StudioLook.classic);
    final look = StudioLook.fromJson({
      'colours': {
        'ink': '#102030',
        'accent': 'rouge',
        'line': '#11223344',
        'title': 7,
      },
      'shapes': {
        'buttonRadius': 5,
        'panelRadius': -3,
        'stageBorder': 99,
        'tool': 'rond',
        'panelShadow': 'paper',
      },
    });
    expect(look.ink, const Color(0xff102030));
    // Written red, green, blue, then how opaque.
    expect(look.line, const Color(0x44112233));
    // What is not a colour, or out of bounds, keeps its default.
    expect(look.accent, StudioLook.classic.accent);
    expect(look.title, StudioLook.classic.title);
    expect(look.buttonRadius, 5);
    expect(look.panelRadius, StudioLook.classic.panelRadius);
    expect(look.stageBorder, StudioLook.classic.stageBorder);
    expect(look.tool, ToolShape.tile);
    expect(look.panelShadow, PanelShadow.paper);
    expect(StudioLook.parseColour('#fff'), isNull);
    expect(StudioLook.parseColour('ffffff'), isNull);
  });

  test('a description that cannot be read gives no universe, or no decor', () {
    expect(Universe.parse(''), isNull);
    expect(Universe.parse('U bureau\n'), isNull);
    expect(Universe.parse('U bureau\nM {pas du json}\n'), isNull);
    expect(Universe.parse('U bureau\nM []\n'), isNull);
    // The key of the description is the key of its line.
    expect(Universe.parse('U bureau\nM {"key":"papier","name":"X"}\n'), isNull);
    expect(Universe.parse('U bureau\nM {"key":"bureau"}\n'), isNull);
    // A universe without a decor is one: its look alone.
    final plain = Universe.parse('U nu\nM {"key":"nu","name":"Nu"}\n')!;
    expect(plain.decor, isNull);
    expect(plain.look, StudioLook.classic);
    expect(plain.frenchAbout, '');
    // A decor needs a frame and one ground, first.
    Decor? decor(Object? json) => Decor.fromJson(json, pictures: '');
    expect(decor(null), isNull);
    expect(
      decor({
        'size': [1061, 407],
      }),
      isNull,
    );
    expect(
      decor({
        'size': [1061, 407],
        'pieces': [
          {'picture': 'a'},
        ],
      }),
      isNull,
    );
    expect(
      decor({
        'size': [4, 4],
        'pieces': [
          {'picture': 'fond', 'role': 'ground'},
        ],
      }),
      isNull,
    );
    final read = decor({
      'size': [1061, 407],
      'pieces': [
        {'picture': 'fond', 'role': 'ground'},
        // A piece of a kind this version does not know is left out alone.
        {'picture': 'x', 'role': 'hologramme'},
        {'role': 'clock'},
        {
          'picture': 'a',
          'anchor': 'right',
          'level': 3,
          'move': {'name': 'danse', 'seconds': 3},
        },
      ],
      'names': [
        {
          'key': 'a',
          'at': [0, 0, 10, 10],
          'name': 'A',
          'text': 'Texte.',
        },
        {
          'key': 'b',
          'at': [0, 0, 0, 10],
          'name': 'B',
          'text': 'Texte.',
        },
        {
          'key': 'c',
          'at': [0, 0, 10, 10],
          'name': '',
          'text': 'Texte.',
        },
      ],
    })!;
    expect(read.pieces, hasLength(2));
    expect(read.pieces[1].anchor, DecorAnchor.right);
    expect(read.pieces[1].level, 3);
    expect(read.pieces[1].move, isNull);
    expect(read.names.single.key, 'a');
    expect(read.followsTheHour, isFalse);
    // Without a sheet of its own, the middle of the frame.
    expect(read.sheet.center.dx, closeTo(530.5, 1e-9));
    expect(UniverseCatalog(const []).universes.single.key, 'classique');
  });

  test('the options keep the universe, who chooses it, the movement, the cards '
      'and « Regarder »', () {
    const defaults = StudioOptions.defaults;
    expect(defaults.universe, '');
    expect(defaults.universeFixed, isFalse);
    expect(defaults.decorMotion, DecorMotion.low);
    expect(defaults.decorNames, isTrue);
    expect(defaults.decorWatch, isTrue);
    final chosen = defaults.copyWith(
      universe: 'papier',
      universeFixed: true,
      decorMotion: DecorMotion.none,
      decorNames: false,
      decorWatch: false,
    );
    final json =
        jsonDecode(jsonEncode(chosen.toJson())) as Map<String, dynamic>;
    expect(json['universe'], 'papier');
    expect(json['universeFixed'], isTrue);
    expect(json['decorMotion'], 'aucun');
    expect(json['decorNames'], isFalse);
    expect(json['decorWatch'], isFalse);
    expect(StudioOptions.fromJson(json), chosen);
    expect(chosen, isNot(chosen.copyWith(decorWatch: true)));
    expect(chosen, isNot(defaults));
    expect(chosen.hashCode, StudioOptions.fromJson(json).hashCode);
    // A file of before Color 1.2 says nothing of them.
    final before = Map<String, dynamic>.of(json)
      ..remove('universe')
      ..remove('universeFixed')
      ..remove('decorMotion')
      ..remove('decorNames')
      ..remove('decorWatch');
    final read = StudioOptions.fromJson(before);
    expect(
      (read.universe, read.universeFixed, read.decorMotion, read.decorNames),
      ('', false, DecorMotion.low, true),
    );
    expect(read.decorWatch, isTrue);
    // What is not a key of a universe stands for none.
    for (final wrong in [3, 'Papier', '../x', 'a b', '', 'x' * 41, null]) {
      expect(StudioOptions.fromJson({'universe': wrong}).universe, '');
    }
    expect(
      StudioOptions.fromJson({'decorMotion': 'max'}).decorMotion,
      DecorMotion.low,
    );
    expect(StudioOptions.fromJson({'decorNames': 'oui'}).decorNames, isTrue);
    expect(StudioOptions.fromJson({'decorWatch': 0}).decorWatch, isTrue);
  });
}
