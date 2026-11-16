#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Draws « La ville » (Paris), art/univers/ville/, step 4 of Color 1.2,
fourth part, 16 November 2026.

    make_city_art.py

Unlike the decors before it, this one is not cut out of the mock-up of
November 2026: in the mock-up every thing stood on the same quay, the Eiffel
Tower a hundred times taller than the Morris column beside it but only five
times as tall on the drawing, the pigeon as big as the fountain, the boat on
the Seine under the sheet, and two words written in letters (which the
reader of the core refuses). The things of the mock-up are kept, and its
colours; each one is drawn again in city_things.py at its real measures, and
laid here at the size its distance gives it, as the owner asked on seeing
the countryside (16 November 2026): what is further is smaller, and higher
on the drawing.

The view is that of a child standing on the pavement of a quay of the
Seine, the horizon at y = HORIZON, the eyes EYE metres above the ground:
something that stands on the ground with its feet at y is (y - HORIZON) /
EYE units to the metre. In front, the pigeon pecking at the child's feet;
a few steps away, on the pavement, the Morris column, the street lamp, the
Metro entrance and the Wallace fountain; at the corner of the quay, the
building with its bakery; beyond, the Seine and its boat; on the other bank,
Notre-Dame among the plane trees; far away, the Eiffel Tower and the Arc de
triomphe. The sizes and their sources are in SIZES, and in the report of
this part (`tailles-reelles.md`).
"""
import sys
from pathlib import Path

from make_universe_art import HERE, write
import city_things as things
from city_things import n, placed

HORIZON = 340.0
EYE = 1.2  # metres: a child standing


def feet(scale):
    """Where the feet of a thing at that scale stand."""
    return HORIZON + EYE * scale


# The real measures (metres), their sources in the report of this part.
SIZES = dict(
    eiffel=330,  # with its antennas; the first floor at 57.6 m, the second at 115.7 m
    notre_dame=69,  # its towers; the front 41 m wide, the spire 96 m
    arc=49.54,  # 44.82 m wide; its great arch 29.42 m high, 14.62 m wide
    building=25.8,  # to the top of its chimneys; the cornice at 20 m; five bays, 14.5 m
    morris=(4.0, 1.4),  # high with its dome, across (estimates: see the report)
    wallace=(2.71, .82),
    lamp=5.8,  # the great lamp of the quays: its post 5 m, its lantern 0.8 m
    metro=(4.2, 3.0),  # its lamps and sign, the width of the entrance
    boat=38.65,  # long, 5.07 m wide, about 4 m above the water
    pigeon=.23,  # its head above its toes (about 22 cm); 33 cm long (29 to 36)
)

# The scale of each thing, in units to the metre, from the furthest to the
# nearest: its feet stand at feet(scale).
EIFFEL, ARC, NOTRE_DAME, TREES, SKYLINE = .7, .85, 1.5, 1.5, 1.6
BOAT = 2.2  # on the river, nearer the far bank: 38.65 m long, 85 units
BOAT_WATERLINE = 347.8  # the water is lower than the street: its line is not feet(BOAT)
BUILDING = 8.5  # at the corner of the quay
STREET = 23.0  # the pavement a few steps away
PIGEON, PIGEON_2 = 50.0, 46.0  # at the child's feet

LEFT = dict(building=66, eiffel=178)
RIGHT = dict(notre_dame=826, lamp=866, metro=912, arc=970, morris=1012, wallace=1046)
BOAT_AT = 136  # its bow, at rest; it goes 16 units to the right and back (35 at most)
PIGEON_AT, PIGEON_2_AT = 38, 196  # their feet

SKY = '#bcdcf3'
FRONT = ('#ddd4c0', '#d6ccb6', '#b8aa8f')


def sky():
    return ('<linearGradient id="ciel" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="%s" /><stop offset=".62" stop-color="#d9e9f3" />'
            '<stop offset=".84" stop-color="#eaf1ef" /><stop offset="1" stop-color="#f1f1e8" /></linearGradient>'
            '<linearGradient id="trottoir" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#e7dfcd" /><stop offset="1" stop-color="%s" /></linearGradient>') % (SKY, FRONT[0])


def skyline():
    """The far city, pale: buildings of 18 to 25 m with their roofs and
    windows, seen across the river, at SKYLINE units to the metre."""
    out = []
    base = feet(SKYLINE)
    x = -6.0
    widths = (14, 18, 12, 16, 20, 13, 17, 15, 19, 12, 16, 14, 18, 15, 13, 17, 20, 14, 16, 12, 18, 15)
    heights = (21, 24, 18, 22, 25, 19, 23, 20, 24, 18, 22, 21, 25, 19, 20, 23, 24, 18, 22, 19, 25, 21)
    i = 0
    while x < 1070:
        w = widths[i % len(widths)] * SKYLINE
        h = heights[i % len(heights)] * SKYLINE
        roof = 3.5 * SKYLINE
        out.append('<path d="M%s %s V%s L%s %s H%s L%s %s V%s Z" fill="#d3dde6" />' % (
            n(x), n(base), n(base - h + roof), n(x + 3), n(base - h), n(x + w - 3), n(x + w), n(base - h + roof), n(base)))
        out.append('<path d="M%s %s H%s" fill="none" stroke="#c4d0db" stroke-width="1" />' % (n(x + 1), n(base - h + roof), n(x + w - 1)))
        cols = max(2, int(w // 9))
        for c in range(cols):
            wx = x + (c + .5) * w / cols - 1.4
            for r in range(3):
                wy = base - h + roof + 5 + r * 9.5
                if wy + 5 < base - 3:
                    out.append('<rect x="%s" y="%s" width="2.8" height="5" fill="#eef3f7" opacity=".8" />' % (n(wx), n(wy)))
        if i % 3 == 0:
            out.append('<rect x="%s" y="%s" width="4" height="6" fill="#c9a08a" />' % (n(x + w * .3), n(base - h - 4)))
        x += w + (2 if i % 4 == 0 else 0)
        i += 1
    return ''.join(out)


def river_and_quays():
    """The far quay, the Seine, our curb and the pavement, its slabs in
    rows that widen towards us."""
    far, near = feet(NOTRE_DAME), feet(BUILDING)
    out = ['<rect x="0" y="%s" width="1061" height="%s" fill="#e8dfcb" stroke="#293d4b" stroke-width="1" />' % (n(far), n(1)),
           '<rect x="0" y="%s" width="1061" height="%s" fill="#6fa8c9" />' % (n(far + 1), n(near - far - 1))]
    for x, dy in ((40, 2.6), (190, 5), (330, 1.8), (470, 4.4), (610, 3), (760, 5.2), (905, 2.2), (1010, 4)):
        out.append('<path d="M%s %s q4 -1.4 8 0" fill="none" stroke="#a9d0e6" stroke-width="1" stroke-linecap="round" />' % (
            n(x), n(far + 1 + dy)))
    out.append('<rect x="0" y="%s" width="1061" height="%s" fill="url(#trottoir)" />' % (n(near), n(407 - near)))
    out.append('<rect x="0" y="%s" width="1061" height="1.4" fill="#d3c8b0" />' % n(near))
    out.append('<path d="M0 %s H1061" fill="none" stroke="#293d4b" stroke-width="1.4" />' % n(near))
    rows = [near + 1.4]
    for scale in (11.25, 14, 18.75, 28, 56):
        rows.append(feet(scale))
    joints = []
    for i, (top, bottom) in enumerate(zip(rows, rows[1:])):
        if i:
            joints.append('M0 %s H1061' % n(top))
        scale = (top + bottom) / 2 - HORIZON
        step = 1.0 * scale / EYE
        x = (step / 2) * (i % 2)
        while x < 1061:
            joints.append('M%s %s V%s' % (n(x), n(top), n(min(bottom, 407))))
            x += step
    out.append('<path d="%s" fill="none" stroke="#c9bea6" stroke-width="1" stroke-linecap="round" />' % ' '.join(joints))
    return ''.join(out)


def ground():
    trees = ''.join(placed(x, feet(TREES), TREES, things.plane_tree(TREES)) for x in (110, 236, 330, 470, 612, 748, 880, 948, 1052))
    body = ('<rect width="1061" height="407" fill="url(#ciel)" />' + skyline() + trees + river_and_quays())
    return body


def left():
    return (placed(LEFT['eiffel'], feet(EIFFEL), EIFFEL, things.eiffel(EIFFEL))
            + placed(LEFT['building'], feet(BUILDING), BUILDING, things.building(BUILDING)))


def right():
    return (placed(RIGHT['notre_dame'], feet(NOTRE_DAME), NOTRE_DAME, things.notre_dame(NOTRE_DAME))
            + placed(RIGHT['arc'], feet(ARC), ARC, things.arc(ARC))
            + placed(RIGHT['lamp'], feet(STREET), STREET, things.lamp(STREET, SIZES['lamp']))
            + placed(RIGHT['metro'], feet(STREET), STREET, things.metro(STREET, *SIZES['metro']))
            + placed(RIGHT['morris'], feet(STREET), STREET, things.morris(STREET, *SIZES['morris']))
            + placed(RIGHT['wallace'], feet(STREET), STREET, things.wallace(STREET, *SIZES['wallace'])))


# The small pictures that move: their boxes in the decor.
BOAT_BOX = (88, 13)  # the boat, its waterline 1 unit above the bottom
PIGEON_BOX = (20, 13)


def boat_picture():
    return placed(1.5, BOAT_BOX[1] - 1, BOAT, things.boat(BOAT, SIZES['boat']))


PIGEON_FEET = (9.6, PIGEON_BOX[1] - .6)  # where its feet are in its box


def pigeon_picture(scale):
    """The pigeon turned to the right, as the hen of the countryside: it
    pecks by leaning forward about its feet (the movement `picore`)."""
    k = scale / 100
    return '<g transform="translate(%s %s) scale(%s %s)">%s</g>' % (
        n(PIGEON_FEET[0]), n(PIGEON_FEET[1]), n(-k), n(k), things.pigeon(k))


def ville():
    out = HERE / 'ville'
    write(out, 'fond', ground(), sky())
    write(out, 'gauche', left())
    write(out, 'droite', right())
    write(out, 'bateau', boat_picture(), width=BOAT_BOX[0], height=BOAT_BOX[1])
    write(out, 'pigeon', pigeon_picture(PIGEON), width=PIGEON_BOX[0], height=PIGEON_BOX[1])
    (out / 'nuage.svg').write_text((HERE / 'montagne' / 'nuage.svg').read_text(encoding='utf-8'), encoding='utf-8')


if __name__ == '__main__':
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    ville()
    for picture in sorted((HERE / 'ville').glob('*.svg')):
        print('%-32s %7d' % (picture.relative_to(HERE), picture.stat().st_size))
