#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Cuts the drawings of the mock-ups of November 2026 into the pieces of two
universes of Color (step 4 of Color 1.2, second part, 16 November 2026):
« La forêt » (art/univers/foret/) and « La campagne » (art/univers/campagne/).

    make_forest_and_country_art.py MOCKUPS

MOCKUPS is the folder `habillages-maquettes-2026-11-11` of the owner's Mac;
it is not in this repository. As for the other decors, the files written
here are the ones that count from now on; this tool is kept as the record
of how the cut was made.

The children of a drawing are numbered as `pick` numbers them: from one, in
the order of the file, its `<defs>` left out.

What the cut changes, for the rules of the owner (12 November 2026):

- nothing named lies under the sheet: the hedgehog of the forest goes to
  the foot of the oak; the pond of the countryside and its duck go to the
  bottom left corner, in front of the cow;
- nothing goes beyond the frame, at any level of movement: the beech of the
  forest (its crown went 10 units beyond the right edge) and the ferns move
  inside; the spruce, the poppies, the apple tree (moved and made a little
  smaller) and the sunflowers keep to the left of the sheet; the bush of the
  bluebells to its right; the fence of the countryside begins with a post,
  and the field of the scarecrow ends before the right edge;
- what moves is apart: the crowns of the trees, the sunflowers, the sails of
  the windmill, the clouds, the leaf, the butterfly, the robin, the hen,
  the swallows; the sun of the countryside is a piece of its own, so that a
  wide window does not show it twice in the mirrored ground;
- the light falling between the trees fades towards the top instead of
  being cut there (the decor stands at the bottom of the window).

And for what the owner saw on the mock-up of the countryside (16 November
2026): the udder of the cow is drawn where it is on a cow, with its teats,
her four legs stand on one line, each with its hoof; the tractor is larger
than the sheep, and the windmill a little larger.
"""
import math
import sys
from pathlib import Path

from make_universe_art import HERE, children, copy, text_of, write
from make_sea_and_space_art import layer, moved, pick

# The rays of light, white, from nothing at the top to whole halfway down.
FADE = (
    '<linearGradient id="rai" x1="0" y1="0" x2="0" y2="1">'
    '<stop offset="0" stop-color="#ffffff" stop-opacity="0" />'
    '<stop offset=".5" stop-color="#ffffff" stop-opacity="1" />'
    '</linearGradient>'
)


def scaled(elements, x, y, factor, dx=0.0, dy=0.0):
    """Elements made `factor` times larger about (x, y), then moved."""
    return '<g transform="translate(%s %s) scale(%s) translate(%s %s)">%s</g>' % (
        x + dx, y + dy, factor, -x, -y, text_of(elements))


# The sizes of the forest (16 November 2026), seen as a child crouching in
# a clearing sees it: the small things of the forest floor, close, at
# FOREST_FRONT units per metre; the trees, some thirty metres away, whole,
# at about FOREST_TREES (an oak of 30 m; a birch of 25 m, made smaller).
# Each small thing is made its real size about its feet.
FOREST_FRONT, FOREST_TREES = 75, 7.7
BIRCH = .8  # 262 units high, made 210: 27 m beside the oak's 30
FOREST_SMALL = (  # item, its feet x and y, factor, then a move
    (125, 196, 393.5, .25, 0, 0),  # a small fly agaric, 8 cm
    (126, 214, 389, .28, 0, 0),  # the large fly agaric, 18 cm
    (127, 236, 394, .28, 0, 0),  # another, 12 cm
    (130, 166, 401, .77, 0, 0),  # an ox-eye daisy, 45 cm
    (131, 180, 405, .77, 0, 0),  # another, 35 cm
    (133, 250, 399, .7, -8, 0),  # a poppy, 45 cm
    (134, 262, 405, .7, -8, 0),  # another, 35 cm
    # The squirrel (22 cm sitting) leaves the foot of the oak, too far
    # for so small an animal, for the front; the hedgehog (25 cm long)
    # stays in front too.
    (137, 142, 362.5, .49, -6, 40.5),
    (138, 291.75, 404.5, .52, -184, 0),
)
FOREST_FLOWERS = (  # the small flowers of the clearing, each about its foot
    (139, 350, 402), (140, 470, 404), (141, 612, 402), (142, 722, 404),
    (143, 410, 404), (144, 566, 405), (145, 680, 404),
)
FOREST_SMALL_RIGHT = (
    (128, 928, 401, .33, 0, 0),  # a cep, 15 cm
    (129, 944, 404, .28, 0, 0),  # a small one, 8 cm
    (132, 1012, 373, .6, -34, 0),  # a daisy by the fern, 50 cm
    (135, 806, 401, .58, 10, 0),  # bluebells, 30 cm
    (136, 856, 403, .58, 10, 0),
)


def _small(kids, things):
    return ''.join(scaled(pick(kids, i), x, y, f, dx, dy) for i, x, y, f, dx, dy in things)


def foret(mockups):
    source = mockups / 'serie-3' / 'decors'
    out = HERE / 'foret'
    _, defs, kids = children(source / 'decor-foret.svg')
    assert len(kids) == 333 and kids[0].get('fill') == 'url(#ciel)'
    sky = text_of([g for d in defs for g in d])
    rays = text_of(pick(kids, 69, 70)).replace('fill="#ffffff"', 'fill="url(#rai)"')
    assert rays.count('url(#rai)') == 2
    # The sky, the far trees, the meadows, the rays, the patches of light,
    # the strip of grass, a pebble, the small flowers and the blades of
    # grass: the ground, under the sheet too.
    ground = (
        text_of(pick(kids, (1, 68))) + rays
        + text_of(pick(kids, (112, 115), 119, 124))
        + ''.join(scaled(pick(kids, i), x, y, .7) for i, x, y in FOREST_FLOWERS)
        + text_of(pick(kids, (146, 333)))
    )
    write(out, 'fond', ground, sky + FADE)
    # The trunk of the oak is still; its crown sways (`chene`).
    assert kids[115].get('transform', '').startswith('translate(100.0 358.0)')
    assert kids[136].get('transform', '').startswith('translate(142.0 360.0)')  # the squirrel
    assert kids[137].get('transform', '').startswith('translate(292.0 402.0)')  # the hedgehog
    left = (
        moved(pick(kids, (71, 89)), -6, 0)  # the spruce, clear of the sheet
        + text_of(pick(kids, 116))
        + moved(pick(kids, 120), 24, 0)  # the fern, inside the left edge
        + _small(kids, FOREST_SMALL)
    )
    write(out, 'gauche', left)
    assert kids[117].get('transform', '').startswith('translate(1000.0 354.0)')  # the beech
    right = (
        text_of(pick(kids, (90, 111)))
        + scaled(pick(kids, 117), 880, 362, BIRCH)  # the trunk of the birch
        + moved(pick(kids, 118), -18, 0)  # the beech, its crown inside the frame
        + moved(pick(kids, 121), -24, 0)  # the fern
        + moved(pick(kids, 122), 10, 0)  # the bush, clear of the sheet
        + text_of(pick(kids, 123))  # the stump
        + _small(kids, FOREST_SMALL_RIGHT)
    )
    write(out, 'droite', right)
    write(out, 'chene', text_of(layer(source, 'c-foret-chene')))
    write(out, 'bouleau', scaled(layer(source, 'c-foret-bouleau'), 880, 362, BIRCH))
    write(out, 'hetre', moved(layer(source, 'c-foret-hetre'), -18, 0))
    for name in ('nuage', 'feuille', 'papillon', 'rougegorge'):
        copy(mockups / 'decors' / ('d-%s.svg' % name), out, name)


# The cow, drawn again from the hips down (16 November 2026), after drawings
# of cows seen from the side: the legs as long as most of the depth of the
# body; the hind legs at the very back, under the rump, wide at the thigh,
# with the hock bent backwards a third of the way up; the front legs under
# the chest, behind it, with their knee; every leg ends in a hoof, the four
# on one line. The far legs, a shade darker, stand a little inwards and
# behind the near ones; the udder hangs in front of the hind legs, its back
# behind the near thigh, with two teats. In the units of her drawing: her
# body ends at y = -17, the ground is now y = 12, her tail is on the left.
INK = 'stroke="#293d4b" stroke-linecap="round" stroke-linejoin="round"'
HIND = ('M-39.8 -26 C-40.2 -16 -39.4 -8 -38.4 -1 Q-39.2 1.6 -37.5 3.2 L-36.9 9.6 '
        'L-29.3 9.6 L-29.7 3 C-29.6 -4 -27 -11 -23.8 -17.5 L-24 -26 Z')
FRONT = ('M21.6 -26 L22 -14 C22.3 -6 23 -2 23.3 1 L23.9 9.6 L31.7 9.6 L31.7 3 '
         'Q32.7 1 32.2 -1.2 C32.6 -8 32.7 -13 33 -20 L33 -26 Z')
HOOF = 'M%s 8.6 H%s L%s 10.6 Q%s 12.4 %s 12.4 H%s Q%s 12.4 %s 10.6 Z'


def _number(value):
    """A number as a drawing writes it: two decimals at most. (The reader
    of the core takes a long fraction after a letter for a number of its
    own, and refuses it as too large.)"""
    return ('%.2f' % value).rstrip('0').rstrip('.')


def _leg(outline, left, right, dx, colour):
    """A leg and its hoof, moved by dx; the hoof between left and right."""
    hoof = HOOF % tuple(_number(v + dx) for v in (
        left - .5, right + .5, right + .9, right + 1, right - .8, left + .9, left - 1, left - .9))
    return (
        '<g transform="translate(%s 0)"><path d="%s" fill="%s" stroke-width="2.2" %s /></g>'
        '<path d="%s" fill="#3a3f4a" stroke-width="1.6" %s />'
    ) % (_number(dx), outline, colour, INK, hoof, INK)


COW_TAIL = (
    '<path d="M-38 -42 C-47 -38 -46.5 -16 -44.5 -4" fill="none" stroke-width="4.4" %s />'
    '<path d="M-44.5 -4 l-3 7 l6 -2 Z" fill="#3a3f4a" stroke-width="1.2" %s />'
) % (INK, INK)
COW_FAR_LEGS = (
    _leg(HIND, -37, -29.3, 6., '#e9e5da') + _leg(FRONT, 23.9, 31.7, -6., '#e9e5da'))
COW_UDDER = (
    '<path d="M-22.6 -9.4 L-22.3 -3.4 Q-21.4 -1.9 -20.5 -3.4 L-20.2 -9.4 Z" '
    'fill="#f4b0a6" stroke-width="1.3" %s />'
    '<path d="M-15.2 -9.4 L-14.9 -3.4 Q-14 -1.9 -13.1 -3.4 L-12.8 -9.4 Z" '
    'fill="#f4b0a6" stroke-width="1.3" %s />'
    '<path d="M-27.5 -19 C-28.6 -11.5 -24.4 -7.6 -18.4 -7.4 C-12.2 -7.4 -9.2 -10.2 -9.8 -19 Z" '
    'fill="#f4b0a6" stroke-width="1.8" %s />'
) % (INK, INK, INK)
COW_NEAR_LEGS = (
    _leg(HIND, -37, -29.3, 0., '#fffdf6') + _leg(FRONT, 23.9, 31.7, 0., '#fffdf6'))


def cow(element):
    """The cow of the mock-up with her udder, her legs and her tail drawn
    again: they go under her body, which is laid over their tops."""
    parts = list(element)
    assert len(parts) == 31 and parts[7].tag.endswith('ellipse')
    body, head = parts[4:7], parts[12:]
    return '<g transform="%s">%s</g>' % (
        element.get('transform'),
        COW_TAIL + COW_FAR_LEGS + COW_UDDER + COW_NEAR_LEGS + text_of(body) + text_of(head))


# The tractor, drawn again (16 November 2026) after drawings of tractors
# seen from the side, and at the size of a real one beside the cow: a
# tractor of 100 hp with a cab, as Terre-net measured one (3.93 m long,
# 2.73 m high, 2.25 m between its axles, rear tyres 480/70 R34 of 1.54 m,
# front tyres 380/70 R24 of 1.14 m), while a Prim'Holstein cow stands
# 1.45 m at the withers (54 units of her drawing, outline included). Its
# numbers are decimetres, y up, the rear axle at x = 0 and the ground at
# y = 0; its group turns them into units: 3.72 units to the decimetre.
TRACTOR_SCALE = 3.72
RED, DARK_RED, METAL, GLASS = '#d9433b', '#b9382f', '#5b6168', '#bfe3f2'


def _xy(x, y):
    return '%s %s' % (_number(x), _number(-y))


def _poly(points):
    return 'M' + ' L'.join(_xy(x, y) for x, y in points) + ' Z'


def _path(d, fill, width, extra=''):
    return '<path d="%s" fill="%s" stroke-width="%s" %s%s />' % (d, fill, width, INK, extra)


def _line(points, colour, width):
    return '<path d="M%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" />' % (
        ' L'.join(_xy(x, y) for x, y in points), colour, width)


def _circle(x, y, r, fill, width=None):
    outline = '' if width is None else ' stroke-width="%s" %s' % (width, INK)
    return '<circle cx="%s" cy="%s" r="%s" fill="%s"%s />' % (
        _number(x), _number(-y), _number(r), fill, outline)


def _band(cx, cy, inner, outer, start, end, fill, width=None):
    """The band between two circles about (cx, cy), from the angle `start`
    over the top to the angle `end` (degrees, from the right, y up): a
    mudguard, or the shadow under one."""
    def at(r, a):
        return cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))
    d = 'M%s A%s %s 0 0 1 %s L%s A%s %s 0 0 0 %s Z' % (
        _xy(*at(outer, start)), _number(outer), _number(outer), _xy(*at(outer, end)),
        _xy(*at(inner, end)), _number(inner), _number(inner), _xy(*at(inner, start)))
    if width is None:
        return '<path d="%s" fill="%s" />' % (d, fill)
    return _path(d, fill, width)


def _wheel(cx, cy, r, lug, lugs, rim, hub, bolts):
    """A wheel seen from the side: the tyre and its bars, its yellow rim, the
    dish of the rim, the hub and its bolts."""
    step = 2 * math.pi / lugs
    outline = []
    for i in range(lugs):
        for f, radius in ((0, r - lug), (.12, r), (.5, r), (.62, r - lug)):
            a = (i + f) * step
            outline.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    parts = [
        _path(_poly(outline), '#3a3a3a', .5),
        '<circle cx="%s" cy="%s" r="%s" fill="none" stroke="#545454" stroke-width=".3" />' % (
            _number(cx), _number(-cy), _number(r - lug - .8)),
        _circle(cx, cy, rim, '#f4c430', .45),
        '<circle cx="%s" cy="%s" r="%s" fill="none" stroke="#d9a520" stroke-width=".5" />' % (
            _number(cx), _number(-cy), _number(rim * .72)),
        _circle(cx, cy, hub, '#c9ced3', .35),
    ]
    for i in range(bolts):
        a = 2 * math.pi * i / bolts
        parts.append(_circle(cx + hub * .62 * math.cos(a), cy + hub * .62 * math.sin(a), hub * .12, '#293d4b'))
    parts.append(_circle(cx, cy, hub * .32, '#293d4b'))
    return ''.join(parts)


def tractor(x):
    """The tractor, its rear axle at x, on the ground at y = 400, going to
    the right."""
    rear, front = (0, 7.7), (22.5, 5.7)
    parts = [
        # The hitch behind the rear wheel: its lower link and its top link.
        _line([(-2.5, 4.8), (-9, 4.2)], '#293d4b', 1.1), _line([(-2.5, 4.8), (-9, 4.2)], METAL, .55),
        _line([(-3, 9.6), (-8.6, 8.8)], '#293d4b', .9), _line([(-3, 9.6), (-8.6, 8.8)], '#8d97a1', .4),
        # The engine and the gearbox, low between the wheels; the weights
        # at the front.
        _path(_poly([(-1, 4.6), (26.6, 4.6), (28.4, 6.2), (28.4, 10.6), (-1, 10.6)]), METAL, .4),
        _path('M28.2 -5 H30.1 V-10 H28.2 Z', METAL, .45),
        _line([(28.85, 5.5), (28.85, 9.5)], '#3a3a3a', .25), _line([(29.5, 5.5), (29.5, 9.5)], '#3a3a3a', .25),
        # The cab: its glass on thick pillars, the seat and the steering
        # wheel inside, the door with its handle, the roof and its lights.
        _path(_poly([(-5.7, 12), (-6, 25), (10, 25), (10.4, 11), (6, 11)]), GLASS, .85),
        _path('M-2.2 -17 L-1.5 -21.2 Q-1.2 -21.8 -.5 -21.5 L-.1 -17 Z', METAL, .3),
        _line([(6.4, 16.9), (8.4, 18.5)], '#293d4b', .5), _line([(7.6, 17.6), (9.3, 14.4)], '#293d4b', .4),
        _line([(3, 11), (2.7, 25)], '#293d4b', .8),
        _line([(4.2, 15.6), (5.3, 15.6)], '#293d4b', .35),
        _path('M-6.9 -24.6 H11.1 V-25.9 Q11.1 -26.6 10.4 -26.6 H-6.2 Q-6.9 -26.6 -6.9 -25.9 Z', RED, .5),
        _path('M9.3 -24.9 H10.7 V-25.8 H9.3 Z', '#fff3c4', .25),
        _path('M-6.5 -24.9 H-5.1 V-25.8 H-6.5 Z', '#fff3c4', .25),
        # The bonnet, a little lower at the front, its grille, its lamp.
        _path('M10.4 -10.4 V-17.6 L25 -16.9 Q28.4 -16.8 28.9 -14.8 V-10.4 Z', RED, .5),
        _path('M25.9 -11.2 H28.3 V-14.2 H26.4 Z', '#3a3a3a', .3),
        _line([(26.5, 12.2), (27.9, 12.2)], '#6a6a6a', .25), _line([(26.6, 13.2), (27.9, 13.2)], '#6a6a6a', .25),
        _path('M26.9 -14.9 H28.5 V-15.9 H26.9 Z', '#fff3c4', .25),
        _line([(13, 15.9), (24.5, 15.3)], DARK_RED, .45),
        # The exhaust, up the front corner of the cab, as high as the roof.
        _path(_poly([(11.1, 17), (11.1, 26.8), (12, 27.3), (12, 17)]), '#8d97a1', .4),
        _path('M10.9 -18.2 H12.2 V-22.4 H10.9 Z', '#a9b0b7', .35),
        # The step up to the door.
        _path('M8 -4 H10.3 V-10.8 H8 Z', METAL, .4),
        _line([(8.4, 6), (9.9, 6)], '#8d97a1', .45), _line([(8.4, 8.4), (9.9, 8.4)], '#8d97a1', .45),
        # The rear wheel, the dark of its arch, its mudguard; the same at
        # the front.
        _band(*rear, 7.4, 8.4, 170, 35, '#2c3036'),
        _wheel(*rear, 7.7, .45, 22, 4.3, 1.5, 8),
        _band(*rear, 8.3, 9.6, 165, 40, DARK_RED, .5),
        _band(*front, 5.5, 6.25, 155, 25, '#2c3036'),
        _wheel(*front, 5.7, .38, 18, 3.05, 1.1, 6),
        _band(*front, 6.2, 6.9, 150, 25, DARK_RED, .4),
    ]
    return '<g transform="translate(%s 400) scale(%s)">%s</g>' % (_number(x), TRACTOR_SCALE, ''.join(parts))


SAILS = 82  # the half side of the place of the sails, in units
SAIL = 80  # the length of a sail from the hub, in units: 8.5 m


def sails():
    """The four sails of the windmill, as long as a real mill's: nearly as
    long as the tower is high (17 m from tip to tip, on a tower of 11 m),
    their tips passing three metres above the ground;
    a lattice along most of each whip, on the side that follows as they
    turn (to the right, `tourne`). In units: the picture is the place of
    the sails, the hub in its middle."""
    c = SAILS
    parts = []
    for angle in (20, 110, 200, 290):
        rungs = ' '.join('M-2 %s H-16' % _number(-r) for r in range(20, 78, 6))
        parts.append(
            '<g transform="translate(%d %d) rotate(%d)">'
            '<path d="M0 0 V-%d" fill="none" stroke-width="3.4" %s />'
            '<path d="M-2 -14 H-16 V-78 H-2 Z" fill="#fbf4e2" stroke-width="1.7" %s />'
            '<path d="%s M-9 -14 V-78" fill="none" stroke="#c9b68a" stroke-width="1" '
            'stroke-linecap="round" />'
            '</g>' % (c, c, angle, SAIL, INK, INK, rungs))
    parts.append('<circle cx="%d" cy="%d" r="6" fill="#7a5a3c" stroke-width="2.2" %s />' % (c, c, INK))
    return ''.join(parts)


def sun():
    """The sun as large as it looks in the sky: half a degree, a small
    disc of a few units, in its glow."""
    glow = (
        '<radialGradient id="eclat" cx="1016" cy="56" r="34" gradientUnits="userSpaceOnUse">'
        '<stop offset="0" stop-color="#fffbe8" stop-opacity="1" />'
        '<stop offset=".2" stop-color="#ffeea0" stop-opacity=".85" />'
        '<stop offset=".5" stop-color="#ffeea0" stop-opacity=".3" />'
        '<stop offset="1" stop-color="#ffeea0" stop-opacity="0" />'
        '</radialGradient>'
    )
    return glow, (
        '<circle cx="1016" cy="56" r="34" fill="url(#eclat)" />'
        '<circle cx="1016" cy="56" r="4" fill="#fffdf4" />'
    )


# The sizes of the countryside, in units of the decor per metre, by how far
# a thing stands (16 November 2026). The cow, 1.45 m at the withers, gives
# FRONT; a fence of 1.15 m gives FENCE; the house of 7 m, chimney
# included, gives FAR, and the tower of the windmill, its hub at 11 m,
# about as much.
FRONT, FENCE, FIELD, FAR = 37.2, 21, 20, 12
TRACTOR_AT = 836  # its rear axle; its hitch 8 units clear of the sheet
DUCK = .8  # 27 units long, made 21.6: a mallard of 58 cm
ROOSTER = .56  # 33 units high, made 18.5: a rooster of 50 cm
ROOSTER_TO = (6, 63)  # from the fence down to the meadow, left of the hen
HEN = .35  # 38.6 units high, made 13.5: a hen of 36 cm (the piece `poule`)
CHICKS = (  # each about its feet, made 4 units high (11 cm), near the hen
    (59, 206, 403.5, .255, 3, -2.5),
    (57, 222, 398, .22, -7, 1.5),
    (58, 238, 401.5, .255, -16, .5),
)
HOUSE_UP = -30  # the house at the foot of the hill
# The poppies, daisies and buttercups of the meadow, each about its foot:
# their flowers were three times too large (a poppy is 7 to 10 cm across).
COUNTRY_FLOWERS = ((67, 300), (68, 370), (69, 640), (70, 700), (71, 420), (72, 600), (73, 760))
SUNFLOWERS = .75  # 1.17 m high, their heads 30 cm across
MILL_UP = -10  # the windmill on top of its mound
SCARECROW = .65  # 58.5 units high, made 38: 1.9 m on its pole (FIELD)
EWE = .61  # 46 units long, made 28: a ewe of 1.4 m, head included (FIELD)
LAMB, LAMB_TO = .45, -10  # 35.5 units long, made 16: a lamb of two months
BALE, BALE_TO = 1.32, 18  # 28.5 units across, made 37.6: a round bale of 1.25 m


def campagne(mockups):
    """The countryside, every thing at its real size beside the others
    (16 November 2026). What stands on the meadow in front is at the size
    of the cow (FRONT); the fence and what is just behind it, smaller
    (FENCE); the sheep, the scarecrow and the field on the right, a little
    further (FIELD); the house and the windmill, at the foot of the hills,
    far (FAR)."""
    source = mockups / 'serie-3' / 'decors'
    out = HERE / 'campagne'
    _, defs, kids = children(source / 'decor-campagne.svg')
    assert len(kids) == 227 and kids[0].get('fill') == 'url(#ciel)'
    sky = text_of([g for d in defs for g in d])
    # The sky, the hills and their fields, the far trees, the meadows, the
    # small flowers and the blades of grass.
    ground = (text_of(pick(kids, 1, (3, 28), 54))
              + ''.join(scaled(pick(kids, i), x, 404, .65) for i, x in COUNTRY_FLOWERS)
              + text_of(pick(kids, (74, 227))))
    write(out, 'fond', ground, sky)
    assert kids[39].get('transform') == 'translate(86.0 322.0) scale(0.900)'  # the house
    assert kids[40].get('transform') == 'translate(208.0 326.0)'  # the trunk of the apple tree
    assert kids[54].get('transform') == 'translate(160.0 334.0) scale(0.620)'  # the rooster
    assert kids[55].get('transform', '').startswith('translate(84.0 372.0)')  # the cow
    assert kids[64].get('transform') == 'translate(516.0 399.0) scale(0.800)'  # the duck
    # The pond, its duck (a mallard, 58 cm long) and its ripples, in the
    # corner.
    pond = (moved(pick(kids, 64), -468, 0) + scaled(pick(kids, 65), 516, 398, DUCK, -488, -1)
            + moved(pick(kids, 66), -446, -1))
    # The chicks, a fortnight old (11 cm), each about its feet.
    chicks = ''.join(
        scaled(pick(kids, i), x, y, f, dx, dy) for i, x, y, f, dx, dy in CHICKS)
    left = (
        # The house, at the foot of the hill, far behind the fence: as
        # large as it is, it stands higher on the picture.
        moved(pick(kids, 40), 0, HOUSE_UP)
        # The apple tree: a little smaller and to the left, so that its
        # crown, swaying, stays clear of the sheet (`pommier`).
        + scaled(pick(kids, 41), 208, 328, .92, -12)
        + text_of(pick(kids, (42, 49)))
        + moved(pick(kids, (50, 53)), 6, 0)  # the fence begins with a post
        # The rooster comes down from the fence: on the meadow, beside the
        # hen, at the size of the cow and of the hen.
        + scaled(pick(kids, 55), 160, 335, ROOSTER, *ROOSTER_TO)
        + cow(kids[55])
        + chicks
        + pond
    )
    write(out, 'gauche', left)
    field = text_of(pick(kids, 29)).replace(
        'M980 322 L1061 300 L1061 356 L1000 356 Z', 'M980 322 L1046 302 L1057 356 L1000 356 Z')
    assert 'L1046 302' in field
    assert kids[37].get('transform') == 'translate(1034.0 334.0) scale(0.820)'  # the scarecrow
    assert kids[38].get('transform') == 'translate(900.0 302.0) scale(1.120)'  # the windmill
    assert kids[59].get('transform') == 'translate(860.0 374.0) scale(0.780)'  # the tractor
    assert kids[60].get('transform') == 'translate(972.0 330.0) scale(0.900)'  # the ewe
    assert kids[61].get('transform') == 'translate(1012.0 318.0) scale(-0.700 0.700)'  # the lamb
    assert kids[62].get('transform') == 'translate(958.0 372.0) scale(0.800)'  # the bale
    # The windmill on top of its mound; its sails are a piece of their own.
    mill = text_of(pick(kids, 39)).replace(
        'translate(900.0 302.0) scale(1.120)', 'translate(900.0 %s) scale(1.288)' % (302 + MILL_UP))
    glow, the_sun = sun()
    right = (
        the_sun
        + field + text_of(pick(kids, (30, 36)))  # its last stubble left out
        + scaled(pick(kids, 38), 1034, 336, SCARECROW)
        + mill
        + scaled(pick(kids, 61), 972, 333, EWE)
        + scaled(pick(kids, 62), 1012, 320, LAMB, LAMB_TO, 0)
        + scaled(pick(kids, 63), 961, 377, BALE, BALE_TO, 0)
        + tractor(TRACTOR_AT)
    )
    write(out, 'droite', right, glow)
    write(out, 'pommier', scaled(layer(source, 'c-campagne-pommier'), 208, 328, .92, -12))
    write(out, 'tournesols', scaled(layer(source, 'c-campagne-fleurs'), 244, 390.7, SUNFLOWERS, -10))
    copy(mockups / 'decors' / 'd-nuage.svg', out, 'nuage')
    write(out, 'ailes', sails(), width=2 * SAILS, height=2 * SAILS)
    copy(source / 'd-poule.svg', out, 'poule')
    # The swallow of the mock-ups looks to the left: the one of the left
    # side, which flies to the right, is turned round.
    copy(source / 'd-hirondelle.svg', out, 'hirondelle-droite')
    text = (out / 'hirondelle-droite.svg').read_text(encoding='utf-8')
    head, body = text.split('>', 1)
    body = body.rsplit('</svg>', 1)[0]
    (out / 'hirondelle-gauche.svg').write_text(
        head + '><g transform="translate(100 0) scale(-1 1)">' + body + '</g></svg>\n',
        encoding='utf-8')


if __name__ == '__main__':
    folder = Path(sys.argv[1])
    foret(folder)
    campagne(folder)
    for key in ('foret', 'campagne'):
        for picture in sorted((HERE / key).glob('*.svg')):
            print('%-32s %7d' % (picture.relative_to(HERE), picture.stat().st_size))
