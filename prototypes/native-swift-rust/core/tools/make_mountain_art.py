#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Cuts the drawing of the mountain of the mock-ups of November 2026 into the
pieces of « La montagne » (art/univers/montagne/), step 4 of Color 1.2, third
part, 16 November 2026.

    make_mountain_art.py MOCKUPS

MOCKUPS is the folder `habillages-maquettes-2026-11-11` of the owner's Mac;
it is not in this repository. As for the other decors, the files written here
are the ones that count from now on; this tool is kept as the record of how
the cut was made. The children of the drawing are numbered as `pick` numbers
them: from one, in the order of the file, its `<defs>` left out.

What the cut changes, for the rules of the owner (12 November 2026):

- the mountains of the mock-up stood across the sheet and beyond the edges
  of the frame: each side keeps its great mountain whole, narrowed to stand
  beside the sheet (its slopes steeper), with its peak and its snow, and a
  smaller one in front of it; the green slope at their foot ends on the
  meadow on both sides, instead of being cut by an edge;
- the distant mountains, pale, stay in the ground: they are seen under the
  sheet and between the two sides;
- the cable car went out of the frame on the right: it now goes from a
  station on the meadow, near the right edge, up to a station on the slope
  of the great mountain, smaller as it is further away, in one span, as at
  the Aiguille du Midi (its pylon was a tenth of a real one's height); its
  cabin goes up and down along that cable, smaller as it climbs;
- a spruce of each side is moved clear of the sheet; the eagle and the
  clouds start where their movement keeps them clear of it.

And for what the owner asked on seeing the mock-up (16 November 2026): the
ibex and the eagle are drawn again after drawings of real ones — the ibex
from the side, its horns thick and knotted, sweeping back over its back, its
legs slender with dark shanks, its beard; the golden eagle soaring, seen from
below, its long broad wings ending in spread « fingers », its tail spread,
its head turned to show its hooked beak and its golden nape.
"""
import math
import re
import sys
from pathlib import Path

from make_universe_art import HERE, children, copy, text_of, write
from make_sea_and_space_art import pick

INK = 'stroke="#293d4b" stroke-linecap="round" stroke-linejoin="round"'


def n(value):
    """A number as a drawing writes it: two decimals at most (the reader of
    the core refuses a long fraction after a letter of a path)."""
    return ('%.2f' % value).rstrip('0').rstrip('.')


def remap(text, fx, fy=lambda y: y):
    """The absolute `M x y` and `L x y` pairs of the paths in text, moved."""
    def one(match):
        return '%s%s %s' % (match.group(1), n(fx(float(match.group(2)))), n(fy(float(match.group(3)))))
    return re.sub(r'([ML])(-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?)', one, text)


def narrowed(elements, peak, k, to):
    """A great mountain made k times narrower about its peak, the peak moved
    to x = to: its slopes are steeper, its height is kept."""
    return remap(text_of(elements), lambda x: to + (x - peak) * k)


def smaller(elements, centre, base, k, to):
    """A small mountain made k times smaller about the middle of its base,
    that middle moved to x = to."""
    return remap(text_of(elements), lambda x: to + (x - centre) * k, lambda y: base + (y - base) * k)


def cubic(p0, p1, p2, p3, t):
    a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
    return (a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1])


# The top of the meadow, where the green slopes end: the curve of the
# meadow of the mock-up, followed point by point.
MEADOW = [((0, 322), (140, 306), (280, 334), (420, 320)),
          ((420, 320), (580, 306), (720, 338), (880, 318)),
          ((880, 318), (960, 310), (1020, 322), (1061, 314))]


def meadow_y(x):
    for segment in MEADOW:
        if segment[0][0] <= x <= segment[3][0]:
            low, high = 0.0, 1.0
            for _ in range(40):
                middle = (low + high) / 2
                if cubic(*segment, middle)[0] < x:
                    low = middle
                else:
                    high = middle
            return cubic(*segment, low)[1]
    raise ValueError(x)


def slope(left, right, top):
    """A green slope that rises from the meadow at x = left, keeps near the
    height `top`, and comes down to the meadow at x = right; its lower edge
    follows the meadow, 2 units under it."""
    width = right - left
    up = [(left, meadow_y(left)), (left + width * .1, top + 14), (left + width * .2, top),
          (left + width * .42, top + 3), (left + width * .64, top + 6), (left + width * .86, top + 2),
          (right, meadow_y(right))]
    d = 'M%s %s C%s %s %s %s %s %s C%s %s %s %s %s %s' % tuple(n(v) for p in up for v in p)
    steps = 24
    for i in range(steps, -1, -1):
        x = left + width * i / steps
        d += ' L%s %s' % (n(x), n(meadow_y(x) + 2))
    return '<path d="%s Z" fill="#5f9f86" />' % d


def station(x, y, flip=False, k=1):
    """A small station of the cable car, its floor at (x, y), k times its
    size: the one up on the mountain is further away, and smaller."""
    s = -k if flip else k
    return (
        '<g transform="translate(%s %s) scale(%s %s)">'
        '<path d="M-11 0 V-14 H11 V0 Z" fill="#e7e2d6" stroke-width="1.8" %s />'
        '<path d="M-13.6 -13.4 L0 -21 L13.6 -13.4 Z" fill="#b5463a" stroke-width="1.8" %s />'
        '<path d="M-6.4 -10 H-1 V-4.6 H-6.4 Z M2 -10 H7.4 V0 H2 Z" fill="#9fc6dc" stroke-width="1.3" %s />'
        '</g>') % (n(x), n(y), n(s), n(k), INK, INK, INK)


# The sizes of the mountain (16 November 2026), as a child standing on the
# meadow sees it: the horizon at y = 309, the eyes 1.2 m above the grass,
# so that what stands on the meadow at y is (y - 309.4) / 1.21 units to the
# metre. The chalet (7.6 m) and the small lake stand at the foot of the
# slope, far; the ibex (0.9 m at the withers) on its rock, nearer; the
# marmot, the edelweiss and the gentians in front, close.
CHALET_UP = -21  # its floor from 343 to 322: 10.4 units to the metre
ROCK_DOWN = 30  # the rock from 331 to 361: 42.6 units to the metre
IBEX = .8  # its withers 48 units of its drawing: 38 units, 0.9 m
MOUNTAIN_SMALL = (  # item, its feet, factor, then a move
    (225, 238, 389, .74, 0, 0),  # the marmot, 45 cm when it stands up
    (226, 172, 403.5, .2, 0, 0),  # an edelweiss, 10 cm
    (227, 186, 406.5, .2, 0, 0),  # another, 8 cm
    (228, 206, 404, .3, 0, 0),  # gentians, 10 cm
)
MOUNTAIN_SMALL_GROUND = (  # the flowers of the meadow, under the sheet too
    (232, 330, 404, .36, 0, 0),  # gentians
    (233, 450, 404, .25, 0, 0),  # an edelweiss
    (234, 600, 404, .36, 0, 0),
    (235, 720, 404, .25, 0, 0),
)
MOUNTAIN_SMALL_RIGHT = (
    (229, 826, 402, .3, 0, 0),  # gentians
    (230, 852, 405, .2, 0, 0),  # an edelweiss
)


def moved(elements, dx, dy):
    return '<g transform="translate(%s %s)">%s</g>' % (n(dx), n(dy), text_of(elements))


def small(kids, things):
    return ''.join(
        '<g transform="translate(%s %s) scale(%s) translate(%s %s)">%s</g>' % (
            n(x + dx), n(y + dy), f, n(-x), n(-y), text_of(pick(kids, i)))
        for i, x, y, f, dx, dy in things)


def lake(elements):
    """The lake of the mock-up, a pond in front of the meadow, made a small
    lake at the foot of the slope, beyond the chalet: as wide, much flatter,
    the spruces on its far shore."""
    text = text_of(elements)
    flat = text.replace('cx="194" cy="356" rx="60" ry="11"', 'cx="198" cy="324" rx="64" ry="5"')
    assert flat != text
    ripples = re.search(r'<path d="M150 354 q10 -3 20 0[^"]*"', flat)
    assert ripples
    return flat.replace(ripples.group(0), '<path d="M156 323.5 q8 -1.5 16 0 M196 326 q8 -1.5 16 0 M224 322.5 q6 -1.2 12 0"')


def montagne(mockups, ibex, eagle):
    source = mockups / 'serie-3' / 'decors'
    out = HERE / 'montagne'
    _, defs, kids = children(source / 'decor-montagne.svg')
    assert len(kids) == 398 and kids[0].get('fill') == 'url(#ciel)'
    sky = text_of([g for d in defs for g in d])
    assert kids[2].get('d') == 'M-70 322 L116 52 L300 322 Z'
    assert kids[6].get('d') == 'M760 322 L948 40 L1130 322 Z'
    assert kids[196].get('d', '').startswith('M0 322 C140 306')  # the meadow
    # The sky, the distant mountains, the meadows, the small flowers, the
    # pebbles and the blades of grass.
    ground = (text_of(pick(kids, 1, 2, 197, 223)) + small(kids, MOUNTAIN_SMALL_GROUND)
              + text_of(pick(kids, (236, 398))))
    write(out, 'fond', ground, sky)
    left = (
        narrowed(pick(kids, (3, 6)), 116, .70, 132)
        + smaller(pick(kids, (11, 14)), 250, 322, .62, 196)
        + slope(2, 262, 280)
        + text_of(pick(kids, (21, 84)))
        + '<g transform="translate(-12 0)">%s</g>' % text_of(pick(kids, (85, 100)))
        + lake(pick(kids, 201, 202))
        + moved(pick(kids, 203), 0, CHALET_UP)
        + text_of(pick(kids, (204, 219), 224))
        + small(kids, MOUNTAIN_SMALL)
    )
    write(out, 'gauche', left)
    # The cable: from a station on the meadow near the right edge, in one
    # span, up to a station on the slope of the great mountain.
    low, high = (1046, 314), (868, 166)
    top = (low[0], low[1] - 18), (high[0], high[1] - 9)  # the cable leaves each roof
    cable = '<path d="M%s %s L%s %s" fill="none" stroke="#293d4b" stroke-width="2" stroke-linecap="round" />' % (
        top[0][0], top[0][1], top[1][0], top[1][1])
    right = (
        narrowed(pick(kids, (7, 10)), 948, .70, 928)
        + smaller(pick(kids, (15, 18)), 820, 322, .62, 872)
        + slope(800, 1058, 274)
        + '<g transform="translate(6 0)">%s</g>' % text_of(pick(kids, (101, 116)))
        + text_of(pick(kids, (117, 196)))
        + station(*high, flip=True, k=.5) + cable + station(*low)
        + moved(pick(kids, 220, 221), 0, ROCK_DOWN)
        + '<g transform="translate(870 %s) scale(%s)">%s</g>' % (n(307 + ROCK_DOWN), IBEX, ibex)
        + small(kids, MOUNTAIN_SMALL_RIGHT)
        + text_of(pick(kids, 231))
    )
    write(out, 'droite', right)
    copy(mockups / 'decors' / 'd-nuage.svg', out, 'nuage')
    copy(source / 'd-cabine.svg', out, 'cabine')
    write(out, 'aigle', eagle, width=100, height=100)


if __name__ == '__main__':
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mountain_animals import eagle, ibex
    montagne(Path(sys.argv[1]), ibex(), eagle())
    for picture in sorted((HERE / 'montagne').glob('*.svg')):
        print('%-32s %7d' % (picture.relative_to(HERE), picture.stat().st_size))
