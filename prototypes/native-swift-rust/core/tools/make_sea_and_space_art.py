#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Cuts the drawings of the mock-ups of November 2026 into the pieces of two
universes of Color (step 4 of Color 1.2, 16 November 2026): « Sous la mer »
(art/univers/mer/) and « L'espace » (art/univers/espace/).

    make_sea_and_space_art.py MOCKUPS

MOCKUPS is the folder `habillages-maquettes-2026-11-11` of the owner's Mac;
it is not in this repository. As for the desk and the paper
(make_universe_art.py), the files written here are the ones that count from
now on; this tool is kept as the record of how the cut was made.

What the cut changes, for the rules of the owner (12 November 2026):

- nothing important lies under the sheet: the crab, the sea urchin and a shell
  of the sea bed are moved to the sides; a second urchin, a second starfish
  and a second shell are left out; the satellite, drawn above the sheet, flies next to
  the Earth;
- nothing goes beyond the frame, nor under the sheet: the tufts of grass,
  the small coral, the galaxy and a star that straddled an edge are moved
  inside, and so are the layers of seaweed;
- what moves is apart: the seahorse, the bubbles, the astronaut, four stars.
"""
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from make_universe_art import HERE, children, copy, text_of, write


def moved(elements, dx, dy):
    return '<g transform="translate(%s %s)">%s</g>' % (dx, dy, text_of(elements))


def pick(kids, *spans):
    """The children of a drawing by the place they have in its file, the
    `<defs>` counted: one number, or a first and a last."""
    out = []
    for span in spans:
        first, last = span if isinstance(span, tuple) else (span, span)
        out.extend(kids[first - 1:last])
    return out


def layer(source, name):
    _, _, kids = children(source / (name + '.svg'))
    return kids


def mer(mockups):
    source = mockups / 'serie-3' / 'decors'
    out = HERE / 'mer'
    _, defs, kids = children(source / 'decor-mer.svg')
    assert len(kids) == 123 and kids[0].get('fill') == 'url(#eau)'
    water = text_of([g for d in defs for g in d])
    # The water, its light, the far hills, the sand and its grains. In the
    # workshop the water goes on above the decor, plain (`top`): the three
    # lines of waves of the surface would cross the middle of the window,
    # and are left out; the rays of light fade towards the top instead of
    # being cut there.
    rays = text_of(pick(kids, (2, 4))).replace('fill="#ffffff"', 'fill="url(#rai)"')
    assert rays.count('url(#rai)') == 3
    fade = (
        '<linearGradient id="rai" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#ffffff" stop-opacity="0" />'
        '<stop offset=".5" stop-color="#ffffff" stop-opacity="1" />'
        '</linearGradient>'
    )
    ground = text_of(pick(kids, 1)) + rays + text_of(pick(kids, (10, 11), (15, 80)))
    write(out, 'fond', ground, water + fade)
    assert kids[93].get('transform', '').startswith('translate(322.0 405.0)')  # the crab
    assert kids[94].get('transform', '').startswith('translate(506.0 404.0)')  # the urchin
    left = (
        text_of(pick(kids, (12, 14), 81, 83, (100, 104), 88, 87, 89, 90))
        + moved(pick(kids, 86), -16, 0)
        + moved(pick(kids, (105, 109)), -24, 0)
        + moved(pick(kids, 94), -194, -2)
    )
    write(out, 'gauche', left)
    right = (
        text_of(pick(kids, 8, 9, 82, 84, 85, 92, 93))
        + moved(pick(kids, (110, 114)), 18, 0)
        + moved(pick(kids, (115, 119)), -8, 0)
        + moved(pick(kids, 95), 379, -4)
        + moved(pick(kids, 97), 305, -1)
    )
    write(out, 'droite', right)
    write(out, 'hippocampe', text_of(pick(kids, 91)))
    write(out, 'bulles-gauche', text_of(pick(kids, 120, 123)))
    write(out, 'bulles-droite', text_of(pick(kids, 121, 122)))
    # The seaweed: of the three stalks of the left, the one that stands
    # between the rock and the anemone is kept, where it hides nothing that
    # has a name (the short one covered the sponge and went beyond the left
    # edge); the stalk of the right, drawn in front of the octopus and beyond
    # the right edge, stands in front of the sea fan.
    stalks = layer(source, 'c-mer-algues-g')
    assert len(stalks) == 72
    write(out, 'algue-gauche', moved(stalks[:24], -14, 0))
    write(out, 'algue-droite', moved(layer(source, 'c-mer-algues-d'), -78, 0))
    copy(mockups / 'decors' / 'd-poisson-orange.svg', out, 'poisson-clown')
    copy(mockups / 'decors' / 'd-poisson-jaune.svg', out, 'poisson-papillon')
    copy(source / 'd-meduse.svg', out, 'meduse')
    copy(source / 'd-tortue.svg', out, 'tortue')


def espace(mockups):
    source = mockups / 'serie-3' / 'decors'
    out = HERE / 'espace'
    _, defs, kids = children(source / 'decor-espace.svg')
    assert len(kids) == 399 and kids[0].get('fill') == '#141842'
    shared = [g for d in defs for g in d]

    def used(body):
        """The shared definitions a piece names, and no other."""
        return text_of([g for g in shared if 'url(#%s)' % g.get('id') in body])

    # The sky, its three nebulas and its far stars; one bright star under
    # the sheet stays with them.
    ground = text_of(pick(kids, (1, 374), 378))
    # The sky goes on above the decor, mirrored (`"above": "ground"`), and
    # plain under the line of the pebbles: the blue nebula, which went
    # beyond the bottom edge, is moved up, whole inside the frame.
    low = 'cx="900" cy="318" rx="290" ry="170"'
    assert low in ground
    ground = ground.replace(low, 'cx="900" cy="228" rx="290" ry="170"')
    write(out, 'fond', ground, used(ground))
    left = (
        text_of(pick(kids, (380, 387)))
        + moved(pick(kids, 388), -6, 0)
        + text_of(pick(kids, (389, 394)))
    )
    # The planets are cut by a circle and the comet has a gradient: the
    # definitions go with the pieces that use them.
    write(out, 'gauche', left, used(left))
    right = text_of(pick(kids, 395, 396, 398, 399))
    write(out, 'droite', right, used(right))
    write(out, 'astronaute', text_of(pick(kids, 397)))
    write(out, 'etoiles-gauche', moved(pick(kids, 375), -8, 0) + text_of(pick(kids, 379)))
    write(out, 'etoiles-droite', text_of(pick(kids, 376, 377)))
    copy(mockups / 'decors' / 'd-satellite.svg', out, 'satellite')
    copy(source / 'd-soucoupe.svg', out, 'soucoupe')
    # The rocket of the mock-ups was turned by the page (48 degrees): here
    # the drawing is, so that it also leans when nothing moves.
    text = (mockups / 'decors' / 'd-fusee.svg').read_text(encoding='utf-8')
    body = re.search(r'<svg[^>]*>(.*)</svg>', text, re.S).group(1)
    write(out, 'fusee', '<g transform="rotate(48 50 50)">%s</g>' % body, width=100, height=100)


if __name__ == '__main__':
    folder = Path(sys.argv[1])
    mer(folder)
    espace(folder)
    for key in ('mer', 'espace'):
        for picture in sorted((HERE / key).glob('*.svg')):
            print('%-32s %7d' % (picture.relative_to(HERE), picture.stat().st_size))
