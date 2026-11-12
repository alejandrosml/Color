// SPDX-License-Identifier: MIT
// The universes of the studio as the core hands them over (Color 1.2):
// their descriptions read, their pictures found, their looks readable, and
// what the options keep of them.
import 'dart:convert';
import 'dart:io';

import 'package:edupaint_flutter_study/decor.dart';
import 'package:edupaint_flutter_study/decor_motion.dart';
import 'package:edupaint_flutter_study/rust_document.dart';
import 'package:edupaint_flutter_study/studio_colors.dart';
import 'package:edupaint_flutter_study/studio_options.dart';
import 'package:edupaint_flutter_study/universe.dart';
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

  test('the core has the desk by the window first, then paper and pencils', () {
    final catalog = UniverseCatalog.instance;
    expect([for (final u in catalog.universes) u.key], ['bureau', 'papier']);
    expect(catalog.first.frenchName, 'Classique');
    expect(catalog.universes[1].frenchName, 'Papier et crayons');
    expect(RustDocument.universeCount(), 2);
    expect(RustDocument.readUniverse(2), isNull);
    expect(RustDocument.readUniverse(-1), isNull);
    // Whoever names none, or one this Color does not know, gets the first.
    expect(catalog.named('').key, 'bureau');
    expect(catalog.named(null).key, 'bureau');
    expect(catalog.named('lune').key, 'bureau');
    expect(catalog.named('papier').key, 'papier');
  }, skip: !available);

  test('every piece has its picture, every movement is known', () {
    for (var index = 0; index < RustDocument.universeCount(); index++) {
      final json = described(index);
      final universe = UniverseCatalog.instance.universes[index];
      final decor = universe.decor!;
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
        ['fond', 'ciel', 'gauche', 'droite', 'milieu'],
      );
      expect(
        [for (final piece in decor.live) piece.picture ?? 'horloge'],
        ['nuage', 'fenetre', 'rideaux', 'plante', 'horloge', 'chat'],
      );
      expect(decor.followsTheHour, isTrue);
      expect(decor.hasMovement, isTrue);
      // The cloud passes behind the window in the morning and by day only.
      final cloud = decor.live.first;
      expect(cloud.moments, {DayMoment.matin, DayMoment.jour});
      expect(cloud.clip, const Rect.fromLTWH(37, 41, 166, 188));
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
      final clock = decor.live[4].clock!;
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
    for (final universe in catalog.universes) {
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

  test(
    'the options keep the universe, who chooses it, the movement and the cards',
    () {
      const defaults = StudioOptions.defaults;
      expect(defaults.universe, '');
      expect(defaults.universeFixed, isFalse);
      expect(defaults.decorMotion, DecorMotion.low);
      expect(defaults.decorNames, isTrue);
      final chosen = defaults.copyWith(
        universe: 'papier',
        universeFixed: true,
        decorMotion: DecorMotion.none,
        decorNames: false,
      );
      final json =
          jsonDecode(jsonEncode(chosen.toJson())) as Map<String, dynamic>;
      expect(json['universe'], 'papier');
      expect(json['universeFixed'], isTrue);
      expect(json['decorMotion'], 'aucun');
      expect(json['decorNames'], isFalse);
      expect(StudioOptions.fromJson(json), chosen);
      expect(chosen, isNot(defaults));
      expect(chosen.hashCode, StudioOptions.fromJson(json).hashCode);
      // A file of before Color 1.2 says nothing of them.
      final before = Map<String, dynamic>.of(json)
        ..remove('universe')
        ..remove('universeFixed')
        ..remove('decorMotion')
        ..remove('decorNames');
      final read = StudioOptions.fromJson(before);
      expect(
        (read.universe, read.universeFixed, read.decorMotion, read.decorNames),
        ('', false, DecorMotion.low, true),
      );
      // What is not a key of a universe stands for none.
      for (final wrong in [3, 'Papier', '../x', 'a b', '', 'x' * 41, null]) {
        expect(StudioOptions.fromJson({'universe': wrong}).universe, '');
      }
      expect(
        StudioOptions.fromJson({'decorMotion': 'max'}).decorMotion,
        DecorMotion.low,
      );
      expect(StudioOptions.fromJson({'decorNames': 'oui'}).decorNames, isTrue);
    },
  );
}
