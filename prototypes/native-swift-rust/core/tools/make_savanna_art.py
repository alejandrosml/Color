#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Draws « La savane », art/univers/savane/, step 4 of Color 1.2, fifth part,
16 November 2026.

    make_savanna_art.py

As the city before it (make_city_art.py), the savanna is drawn again rather
than cut out of the mock-up of November 2026 (`decor-brousse.svg`), whose
animals were cartoons of sizes without relation to one another: the
elephant smaller than the zebra's head was high, the lion as large as the
elephant. Each thing is drawn at its real measures in savanna_things.py,
the animals after drawings of real ones, and laid here at the size its
distance gives it: the view of a child standing in the grass, the horizon
at y = HORIZON, the eyes EYE metres above the ground — what stands with its
feet at y is (y - HORIZON) / EYE units to the metre. Far away, the hills and
small umbrella thorns; the baobab and the acacia; the giraffe and the
elephant, nearer; the zebra; the termite mound; in front, the lion lying in
the grass and the meerkat on watch. The sizes and their sources:
`reports/flutter/color-1.2.0+43-etape-4d/tailles-reelles.md`.
"""
import sys
from pathlib import Path

from make_universe_art import HERE, write
import savanna_things as things
from city_things import n, placed

HORIZON = 330.0
EYE = 1.2


def feet(scale):
    return HORIZON + EYE * scale


SIZES = dict(
    baobab=(20.0, 5.0),  # high, its trunk across (Britannica: up to 23 m)
    acacia=(7.0, 10.0),  # high, its crown across (World Agroforestry)
    termite_mound=(1.6, 1.8),  # high, its base (Kenya: 0.24 to 1.75 m high, 1.7 to 4 m across, measured)
    giraffe=5.5,  # to its ossicones, a male; 3.3 m at the withers (Britannica)
    elephant=3.3,  # at the withers, a male (6.5 m long, trunk included)
    zebra=1.3,  # at the withers (San Diego Zoo Wildlife Alliance)
    lion=0.9,  # lying, its head up (estimate); 1.2 m at the withers, 2 m long and its tail 1 m
    meerkat=0.3,  # standing (estimate; 27 cm head and body)
    vulture=2.0,  # across its wings (The Peregrine Fund)
    grass=0.8,
)

# Units to the metre, from the furthest to the nearest: feet(scale).
FAR_TREES = 1.2
BAOBAB, ACACIA = 5.5, 6.0
ELEPHANT, GIRAFFE = 14.0, 14.0
ZEBRA = 20.0
TERMITES = 22.0
LION = 30.0
MEERKAT = 40.0
GRASS = 45.0

LEFT = dict(baobab=64, giraffe=170, termites=234, meerkat=206)
RIGHT = dict(acacia=846, lion=852, elephant=954, zebra=1030)
SUN = (1014, 66, 4, 34)  # its centre, the disc, its glow: half a degree

SKY = '#f3d9a4'
FRONT = ('#d6b062', '#cea758', '#b28e45')


def defs():
    return ('<linearGradient id="ciel" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="%s" /><stop offset=".7" stop-color="#f8e6c2" />'
            '<stop offset="1" stop-color="#fbedd2" /></linearGradient>'
            '<linearGradient id="plaine" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#e6c784" /><stop offset="1" stop-color="%s" /></linearGradient>') % (SKY, FRONT[0])


def ground():
    out = ['<rect width="1061" height="407" fill="url(#ciel)" />']
    # The far hills, pale, their line meeting itself at both edges.
    out.append('<path d="M0 322 C120 310 220 316 330 320 C450 324 560 308 690 314 C800 319 920 312 1061 322 V332 H0 Z" fill="#ecd4a4" />')
    out.append('<path d="M0 326 C160 319 300 324 450 325 C600 326 760 318 900 323 C980 326 1030 324 1061 326 V332 H0 Z" fill="#e5c991" />')
    out.append('<rect x="0" y="%s" width="1061" height="%s" fill="url(#plaine)" />' % (n(HORIZON), n(407 - HORIZON)))
    # Small umbrella thorns far away, on the horizon.
    for x in (110, 290, 400, 520, 640, 760, 905, 990):
        out.append(placed(x, feet(FAR_TREES), FAR_TREES, things.far_acacia(FAR_TREES)))
    # The grass: short strokes, smaller further away.
    strokes = []
    for row, y in enumerate((338, 346, 356, 368, 382, 398)):
        scale = (y - HORIZON) / EYE
        h = 0.35 * scale
        step = 1.6 * scale
        x = (row * 17) % 23
        while x < 1061:
            strokes.append('M%s %s l%s %s M%s %s l%s %s' % (n(x), n(y), n(-h * .3), n(-h), n(x + h * .4), n(y), n(h * .1), n(-h * .9)))
            x += step
    out.append('<path d="%s" fill="none" stroke="#c09a4e" stroke-width="1" stroke-linecap="round" />' % ' '.join(strokes))
    for x, y, r in ((300, 398, 3.4), (612, 394, 2.6), (760, 402, 3)):
        out.append('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="#b9b2a4" stroke="#293d4b" stroke-width="1" />' % (n(x), n(y), n(r * 1.5), n(r)))
    return ''.join(out)


def left():
    return (placed(LEFT['baobab'], feet(BAOBAB), BAOBAB, things.baobab(BAOBAB, *SIZES['baobab']))
            + placed(LEFT['giraffe'], feet(GIRAFFE), GIRAFFE, things.giraffe(GIRAFFE, 'girafe'))
            + placed(LEFT['termites'], feet(TERMITES), TERMITES, things.termite_mound(TERMITES, *SIZES['termite_mound']))
            + placed(LEFT['meerkat'], feet(MEERKAT), MEERKAT / 100, things.meerkat(MEERKAT / 100)))


def sun_glow():
    x, y, disc, glow = SUN
    return ('<radialGradient id="eclat" cx="%s" cy="%s" r="%s" gradientUnits="userSpaceOnUse">'
            '<stop offset="0" stop-color="#fffbe8" stop-opacity="1" />'
            '<stop offset=".2" stop-color="#ffe7a0" stop-opacity=".85" />'
            '<stop offset=".5" stop-color="#ffe7a0" stop-opacity=".3" />'
            '<stop offset="1" stop-color="#ffe7a0" stop-opacity="0" />'
            '</radialGradient>') % (n(x), n(y), n(glow))


def right():
    x, y, disc, glow = SUN
    sun = '<circle cx="%s" cy="%s" r="%s" fill="url(#eclat)" /><circle cx="%s" cy="%s" r="%s" fill="#fffdf4" />' % (
        n(x), n(y), n(glow), n(x), n(y), n(disc))
    return (sun
            + placed(RIGHT['acacia'], feet(ACACIA), ACACIA, things.acacia(ACACIA, *SIZES['acacia']))
            + placed(RIGHT['elephant'], feet(ELEPHANT), ELEPHANT, things.elephant(ELEPHANT))
            + placed(RIGHT['zebra'], feet(ZEBRA), ZEBRA, things.zebra(ZEBRA, 'zebre'))
            + placed(RIGHT['lion'], feet(LION), LION, things.lion(LION)))


VULTURE_BOX = 16  # its square: 2 m across the wings, about 7.5 units to the metre
GRASS_BOX = (36, 38)  # a tuft of tall grass, 0.8 m, in front


def grass_picture(seed):
    k = GRASS
    return placed(GRASS_BOX[0] / 2, GRASS_BOX[1] - 1, k, things.grass_tuft(k, SIZES['grass'], .7, seed))


def savane():
    out = HERE / 'savane'
    write(out, 'fond', ground(), defs())
    write(out, 'gauche', left())
    write(out, 'droite', right(), sun_glow())
    write(out, 'vautour', things.vulture(VULTURE_BOX / 100 * 1.0), width=100, height=100)
    write(out, 'herbes', grass_picture(1), width=GRASS_BOX[0], height=GRASS_BOX[1])
    write(out, 'herbes-droite', grass_picture(4), width=GRASS_BOX[0], height=GRASS_BOX[1])


if __name__ == '__main__':
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    savane()
    for picture in sorted((HERE / 'savane').glob('*.svg')):
        print('%-32s %7d' % (picture.relative_to(HERE), picture.stat().st_size))
