// SPDX-License-Identifier: MIT
// « Mon jardin », the drawing of the pictures of the App Store (Color 1.2):
// what a gifted child of twelve draws with Color, gesture after gesture — a
// rainbow painted with the brush over the hills, a house and its path, an
// apple tree, a fence, a bed of flowers, a pond, a cat, butterflies, a title.
//
// The drawing was first made as a mock-up, a list of 150 gestures that the
// owner of Color accepted on 11 November 2026 (mon-jardin-scenario.json, with
// the mock-ups of the worlds). This is that list as Color makes it, in the
// order a child makes it; test/store_pictures_test.dart plays it through the
// controls of the studio, on a telephone, a tablet and a computer.
//
// Where Color does not draw as the mock-up did:
// - an oval cannot leave the sheet: the two hills and the lawn are their
//   crests drawn with the brush from edge to edge, then the pot under each;
//   the sky is the paper itself, coloured by the pot on the empty sheet;
// - the pot pours under everything: the rainbow, painted after it, is sent
//   « Tout derrière », band after band, and its feet stand behind the hills;
// - a stamp turns by eighths of a turn only: the seven that the mock-up
//   leaned by a few degrees stand straight;
// - the brush is 48 units wide at most: the path, wider, is two strokes
//   side by side.
import 'dart:math' as math;
import 'dart:ui';

/// One gesture of the drawing.
sealed class Gesture {
  const Gesture();
}

/// The pot, in [rgb], on the point ([x], [y]): on the empty sheet it colours
/// the paper, elsewhere the zone that the lines around close.
class Pour extends Gesture {
  const Pour(this.rgb, this.x, this.y);
  final int rgb;
  final double x, y;
}

/// The crest of a hill, with the brush: the top of an oval too large for
/// the sheet — around ([x], [y]), [across] and [up] its two radii — from
/// [from] to [to] across the sheet.
class Crest extends Gesture {
  const Crest(
    this.rgb,
    this.width,
    this.x,
    this.y,
    this.across,
    this.up,
    this.from,
    this.to,
  );
  final int rgb;
  final int width;
  final double x, y, across, up, from, to;

  /// A point every few units: the brush follows them as they are.
  List<Offset> get points => [
    for (var step = 0; step <= 80; step++) _at(from + (to - from) * step / 80),
  ];

  Offset _at(double at) {
    final share = (at - x) / across;
    return Offset(at, y - up * math.sqrt(1 - share * share));
  }
}

/// A stroke of the brush, [width] units wide, through the points of [way],
/// « x,y x,y… », bent through them as a hand does.
class Brush extends Gesture {
  const Brush(this.rgb, this.width, this.way);
  final int rgb;
  final int width;
  final String way;

  List<Offset> get points => [
    for (final point in way.trim().split(' '))
      Offset(
        double.parse(point.split(',').first),
        double.parse(point.split(',').last),
      ),
  ];
}

/// A click of the brush: a dot.
class Dot extends Gesture {
  const Dot(this.rgb, this.width, this.x, this.y);
  final int rgb;
  final int width;
  final double x, y;
}

/// The element under ([x], [y]) chosen, then sent « Tout derrière ».
class Behind extends Gesture {
  const Behind(this.x, this.y);
  final double x, y;
}

/// A rectangle from one corner to the other, [inside] within, an outline of
/// [width] units in [line]; without a line it is all of its inside's colour.
class Box extends Gesture {
  const Box(
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.inside,
    this.line,
    this.width,
  );
  final double left, top, right, bottom;
  final int inside;
  final int? line;
  final int width;
}

/// An oval around ([x], [y]), [across] and [up] its two radii.
class Oval extends Gesture {
  const Oval(
    this.x,
    this.y,
    this.across,
    this.up,
    this.inside,
    this.line,
    this.width,
  );
  final double x, y, across, up;
  final int inside;
  final int? line;
  final int width;
}

/// The stamp [name] in [rgb], [side] units wide and high, centred on
/// ([x], [y]): dragged from one corner of its box to the other.
class Stamp extends Gesture {
  const Stamp(this.name, this.rgb, this.x, this.y, this.side);
  final String name;
  final int rgb;
  final double x, y, side;
}

/// The title, in large letters; ([x], [y]) is where its first letter stands
/// on its line, as the mock-up gave it.
class Words extends Gesture {
  const Words(this.x, this.y, this.size, this.rgb);
  final double x, y, size;
  final int rgb;
}

/// The gestures of « Mon jardin », in order.
const myGarden = <Gesture>[
  // The sky: the pot, on the empty sheet, colours the paper.
  Pour(0xa8d8f0, 600, 120),
  // The two hills, then the lawn in front of them: three ovals larger than
  // the sheet in the mock-up. Their crests, from an edge of the sheet to the
  // crest of the lawn, or to the other edge; then the pot under each.
  Crest(0x5fa85a, 6, 230, 760, 560, 300, 1, 610.77),
  Crest(0x5fa85a, 6, 1010, 800, 540, 330, 675.16, 1199),
  Crest(0x4e9a52, 6, 600, 1010, 1100, 470, 1, 1199),
  Pour(0xa9db8f, 200, 530),
  Pour(0x9bd384, 1040, 540),
  Pour(0x7cc46c, 600, 700),
  // The sun.
  Stamp('soleil', 0xeebf4e, 1052, 128, 236),
  // The rainbow, painted with the brush, band after band, from the outside in.
  Brush(
    0xd75e56,
    25,
    '862,566 839,451 783,350 691,275 584,235 '
    '465,235 358,275 266,350 210,451 187,566',
  ),
  Brush(
    0xef9439,
    25,
    '839,566 817,459 766,365 680,295 580,258 '
    '469,258 370,295 283,365 232,459 210,566',
  ),
  Brush(
    0xeebf4e,
    25,
    '816,566 796,467 748,380 668,315 576,280 '
    '473,280 381,315 301,380 253,467 233,566',
  ),
  Brush(
    0x4db266,
    25,
    '793,566 774,475 731,394 656,335 572,303 '
    '477,303 393,335 318,394 275,475 256,566',
  ),
  Brush(
    0x477fb2,
    25,
    '770,566 752,483 713,409 645,355 568,326 '
    '481,326 404,355 336,409 297,483 279,566',
  ),
  Brush(
    0x9385bc,
    25,
    '747,566 731,490 695,424 634,375 564,348 '
    '485,348 416,375 354,424 318,490 302,566',
  ),
  // Each band taken at its top, the innermost first, and sent « Tout
  // derrière »: under the hills, which the pot poured under everything.
  Behind(524, 345),
  Behind(524, 322),
  Behind(524, 299),
  Behind(524, 276),
  Behind(524, 253),
  Behind(524, 230),
  // Two clouds, and two birds far away.
  Stamp('nuage', 0xffffff, 128, 250, 168),
  Stamp('nuage', 0xffffff, 800, 108, 204),
  Brush(0x33484d, 4, '588,142 604,150 620,141'),
  Brush(0x33484d, 4, '638,118 654,126 670,117'),
  // The fence: two rails, then the posts.
  Box(436, 492, 1200, 504, 0xd9a56e, 0x79513e, 4),
  Box(436, 524, 1200, 536, 0xd9a56e, 0x79513e, 4),
  Box(443, 470, 461, 554, 0xe6b780, 0x79513e, 4),
  Box(489, 470, 507, 554, 0xe6b780, 0x79513e, 4),
  Box(535, 470, 553, 554, 0xe6b780, 0x79513e, 4),
  Box(581, 470, 599, 554, 0xe6b780, 0x79513e, 4),
  Box(627, 470, 645, 554, 0xe6b780, 0x79513e, 4),
  Box(673, 470, 691, 554, 0xe6b780, 0x79513e, 4),
  Box(719, 470, 737, 554, 0xe6b780, 0x79513e, 4),
  Box(765, 470, 783, 554, 0xe6b780, 0x79513e, 4),
  Box(811, 470, 829, 554, 0xe6b780, 0x79513e, 4),
  Box(857, 470, 875, 554, 0xe6b780, 0x79513e, 4),
  Box(903, 470, 921, 554, 0xe6b780, 0x79513e, 4),
  Box(949, 470, 967, 554, 0xe6b780, 0x79513e, 4),
  Box(995, 470, 1013, 554, 0xe6b780, 0x79513e, 4),
  Box(1041, 470, 1059, 554, 0xe6b780, 0x79513e, 4),
  Box(1087, 470, 1105, 554, 0xe6b780, 0x79513e, 4),
  Box(1133, 470, 1151, 554, 0xe6b780, 0x79513e, 4),
  Box(1179, 470, 1197, 554, 0xe6b780, 0x79513e, 4),
  // The smoke, the house, and its path of sand and stones, which stops before the door.
  Oval(318, 262, 13, 9, 0xf4f4f1, 0xb3bbc0, 3),
  Oval(334, 238, 17, 11, 0xf4f4f1, 0xb3bbc0, 3),
  Oval(356, 208, 22, 14, 0xf4f4f1, 0xb3bbc0, 3),
  Stamp('maison', 0xd75e56, 250, 424, 326),
  Brush(0xdcc48c, 48, '262,604 269,636 323,674 355,732 331,809'),
  Brush(0xdcc48c, 48, '244,608 255,648 309,686 337,732 313,803'),
  Brush(0xf4e2b4, 48, '255,606 264,641 317,679 348,732 324,807'),
  Brush(0xf4e2b4, 48, '251,606 260,643 315,681 344,732 320,805'),
  Oval(256, 624, 16, 8, 0xcfd4d6, 0x8b9499, 4),
  Oval(296, 664, 18, 9, 0xcfd4d6, 0x8b9499, 4),
  Oval(336, 708, 19, 10, 0xcfd4d6, 0x8b9499, 4),
  Oval(334, 760, 20, 10, 0xcfd4d6, 0x8b9499, 4),
  // The apple tree, its apples, two on the grass, and two mushrooms.
  Stamp('arbre', 0x4db266, 664, 390, 380),
  Stamp('pomme', 0xe83d48, 573, 340, 50),
  Stamp('pomme', 0xe83d48, 632, 273, 50),
  Stamp('pomme', 0xe83d48, 705, 270, 50),
  Stamp('pomme', 0xe83d48, 768, 336, 50),
  Stamp('pomme', 0xe83d48, 642, 381, 50),
  Stamp('pomme', 0xe83d48, 718, 386, 50),
  Stamp('pomme', 0xe83d48, 586, 592, 46),
  Stamp('pomme', 0xe83d48, 548, 606, 40),
  Stamp('champignon', 0xd75e56, 728, 590, 62),
  Stamp('champignon', 0xd75e56, 766, 604, 44),
  // On the fence: the bird, and the balloon at the end of its string.
  Stamp('oiseau', 0x477fb2, 912, 432, 100),
  Brush(0x293d4b, 4, '1096,446 1088,462 1100,476'),
  Stamp('ballon', 0xef9439, 1094, 380, 132),
  // The bed of flowers.
  Box(826, 630, 1156, 734, 0x8f6040, 0x5e3b26, 6),
  Brush(0x7a4f33, 5, '846,646 860,650'),
  Brush(0x7a4f33, 5, '892,652 906,656'),
  Brush(0x7a4f33, 5, '938,646 952,650'),
  Brush(0x7a4f33, 5, '984,652 998,656'),
  Brush(0x7a4f33, 5, '1030,646 1044,650'),
  Brush(0x7a4f33, 5, '1076,652 1090,656'),
  Brush(0x7a4f33, 5, '1122,646 1136,650'),
  Stamp('fleur', 0xc96d93, 872, 626, 116),
  Stamp('fleur', 0xeebf4e, 954, 622, 116),
  Stamp('fleur', 0x9385bc, 1036, 626, 116),
  Stamp('fleur', 0xef9439, 1116, 622, 116),
  Stamp('fleur', 0xf4b7cf, 912, 668, 116),
  Stamp('fleur', 0xe83d48, 996, 672, 116),
  Stamp('fleur', 0x3370d1, 1078, 668, 116),
  // The pond, its fish, its reeds, its stones.
  Oval(566, 712, 176, 62, 0x8fd0ee, 0x477fb2, 6),
  Oval(520, 696, 72, 18, 0xc8eaf8, null, 0),
  Oval(486, 734, 28, 12, 0x5fb35f, 0x3f8a4c, 4),
  Stamp('poisson', 0xef9439, 624, 716, 84),
  Brush(0x3f8a4c, 8, '396,728 388,672'),
  Brush(0x79513e, 15, '388,672 386,650'),
  Brush(0x3f8a4c, 8, '412,724 410,652'),
  Brush(0x79513e, 15, '410,652 409,630'),
  Brush(0x3f8a4c, 8, '428,726 434,664'),
  Brush(0x79513e, 15, '434,664 436,642'),
  Oval(392, 746, 23, 12, 0xcfd4d6, 0x8b9499, 4),
  Oval(436, 764, 27, 13, 0xcfd4d6, 0x8b9499, 4),
  Oval(712, 760, 25, 12, 0xcfd4d6, 0x8b9499, 4),
  Oval(748, 730, 20, 11, 0xcfd4d6, 0x8b9499, 4),
  // The cat: a tail with the brush, a body of ovals, and its head, a stamp.
  Brush(0x293d4b, 27, '168,752 204,748 216,712'),
  Brush(0xef9439, 17, '168,752 204,748 216,712'),
  Oval(128, 722, 50, 56, 0xef9439, 0x293d4b, 6),
  Oval(128, 736, 24, 30, 0xffd9a8, null, 0),
  Oval(108, 774, 16, 10, 0xffd9a8, 0x293d4b, 5),
  Oval(148, 774, 16, 10, 0xffd9a8, 0x293d4b, 5),
  Stamp('chat', 0xef9439, 128, 650, 124),
  // The butterflies, and the way they came.
  Dot(0x293d4b, 5, 392, 470),
  Dot(0x293d4b, 5, 414, 452),
  Dot(0x293d4b, 5, 440, 458),
  Dot(0x293d4b, 5, 452, 480),
  Dot(0x293d4b, 5, 440, 498),
  Dot(0x293d4b, 5, 420, 492),
  Dot(0x293d4b, 5, 1010, 316),
  Dot(0x293d4b, 5, 992, 334),
  Dot(0x293d4b, 5, 968, 330),
  Dot(0x293d4b, 5, 958, 308),
  Dot(0x293d4b, 5, 972, 290),
  Stamp('papillon', 0xf4b7cf, 468, 440, 80),
  Stamp('papillon', 0x9385bc, 952, 262, 74),
  // Tufts of grass, and a few flowers in the lawn.
  Brush(0x3f8a4c, 5, '40,640 31,625'),
  Brush(0x3f8a4c, 5, '40,640 40,620'),
  Brush(0x3f8a4c, 5, '40,640 49,626'),
  Brush(0x3f8a4c, 5, '212,690 203,675'),
  Brush(0x3f8a4c, 5, '212,690 212,670'),
  Brush(0x3f8a4c, 5, '212,690 221,676'),
  Brush(0x3f8a4c, 5, '60,760 51,745'),
  Brush(0x3f8a4c, 5, '60,760 60,740'),
  Brush(0x3f8a4c, 5, '60,760 69,746'),
  Brush(0x3f8a4c, 5, '232,778 223,763'),
  Brush(0x3f8a4c, 5, '232,778 232,758'),
  Brush(0x3f8a4c, 5, '232,778 241,764'),
  Brush(0x3f8a4c, 5, '446,600 437,585'),
  Brush(0x3f8a4c, 5, '446,600 446,580'),
  Brush(0x3f8a4c, 5, '446,600 455,586'),
  Brush(0x3f8a4c, 5, '478,790 469,775'),
  Brush(0x3f8a4c, 5, '478,790 478,770'),
  Brush(0x3f8a4c, 5, '478,790 487,776'),
  Brush(0x3f8a4c, 5, '656,792 647,777'),
  Brush(0x3f8a4c, 5, '656,792 656,772'),
  Brush(0x3f8a4c, 5, '656,792 665,778'),
  Brush(0x3f8a4c, 5, '792,700 783,685'),
  Brush(0x3f8a4c, 5, '792,700 792,680'),
  Brush(0x3f8a4c, 5, '792,700 801,686'),
  Brush(0x3f8a4c, 5, '800,778 791,763'),
  Brush(0x3f8a4c, 5, '800,778 800,758'),
  Brush(0x3f8a4c, 5, '800,778 809,764'),
  Brush(0x3f8a4c, 5, '1168,600 1159,585'),
  Brush(0x3f8a4c, 5, '1168,600 1168,580'),
  Brush(0x3f8a4c, 5, '1168,600 1177,586'),
  Brush(0x3f8a4c, 5, '1180,770 1171,755'),
  Brush(0x3f8a4c, 5, '1180,770 1180,750'),
  Brush(0x3f8a4c, 5, '1180,770 1189,756'),
  Brush(0x3f8a4c, 5, '690,640 681,625'),
  Brush(0x3f8a4c, 5, '690,640 690,620'),
  Brush(0x3f8a4c, 5, '690,640 699,626'),
  Stamp('fleur', 0xeebf4e, 46, 690, 74),
  Stamp('fleur', 0xf4b7cf, 760, 668, 66),
  Stamp('fleur', 0xd75e56, 1172, 690, 70),
  Stamp('fleur', 0x9385bc, 470, 648, 64),
  // The title, underlined with the brush, and a heart.
  Words(44, 112, 96, 0xd75e56),
  Brush(0x9385bc, 9, '50,140 170,152 320,136 470,146'),
  Stamp('coeur', 0xc96d93, 548, 78, 62),
];
