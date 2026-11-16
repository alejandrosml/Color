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
        + text_of(pick(kids, (112, 115), 119, 124, (139, 333)))
    )
    write(out, 'fond', ground, sky + FADE)
    # The trunk of the oak is still; its crown sways (`chene`).
    assert kids[115].get('transform', '').startswith('translate(100.0 358.0)')
    assert kids[137].get('transform', '').startswith('translate(292.0 402.0)')  # the hedgehog
    left = (
        moved(pick(kids, (71, 89)), -6, 0)  # the spruce, clear of the sheet
        + text_of(pick(kids, 116))
        + moved(pick(kids, 120), 24, 0)  # the fern, inside the left edge
        + text_of(pick(kids, (125, 127), (130, 131)))
        + moved(pick(kids, (133, 134)), -8, 0)  # the poppies
        + text_of(pick(kids, 137))
        + moved(pick(kids, 138), -184, 0)  # the hedgehog, at the foot of the oak
    )
    write(out, 'gauche', left)
    assert kids[117].get('transform', '').startswith('translate(1000.0 354.0)')  # the beech
    right = (
        text_of(pick(kids, (90, 111), 117))
        + moved(pick(kids, 118), -18, 0)  # the beech, its crown inside the frame
        + moved(pick(kids, 121), -24, 0)  # the fern
        + moved(pick(kids, 122), 10, 0)  # the bush, clear of the sheet
        + text_of(pick(kids, 123, (128, 129)))
        + moved(pick(kids, 132), -34, 0)  # the daisy, out of the fern
        + moved(pick(kids, (135, 136)), 10, 0)  # the bluebells, with the bush
    )
    write(out, 'droite', right)
    write(out, 'chene', text_of(layer(source, 'c-foret-chene')))
    write(out, 'bouleau', text_of(layer(source, 'c-foret-bouleau')))
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


def campagne(mockups):
    source = mockups / 'serie-3' / 'decors'
    out = HERE / 'campagne'
    _, defs, kids = children(source / 'decor-campagne.svg')
    assert len(kids) == 227 and kids[0].get('fill') == 'url(#ciel)'
    sky = text_of([g for d in defs for g in d])
    # The sky, the hills and their fields, the far trees, the meadows, the
    # small flowers and the blades of grass.
    ground = text_of(pick(kids, 1, (3, 28), 54, (67, 227)))
    write(out, 'fond', ground, sky)
    assert kids[40].get('transform') == 'translate(208.0 326.0)'  # the trunk of the apple tree
    assert kids[55].get('transform', '').startswith('translate(84.0 372.0)')  # the cow
    # The pond, its duck and its ripples, in the corner.
    pond = (moved(pick(kids, 64), -468, 0) + moved(pick(kids, 65), -488, -1)
            + moved(pick(kids, 66), -446, -1))
    left = (
        text_of(pick(kids, 40))
        # The apple tree: a little smaller and to the left, so that its
        # crown, swaying, stays clear of the sheet (`pommier`).
        + scaled(pick(kids, 41), 208, 328, .92, -12)
        + text_of(pick(kids, (42, 49)))
        + moved(pick(kids, (50, 53)), 6, 0)  # the fence begins with a post
        + text_of(pick(kids, 55))
        + cow(kids[55])
        + text_of(pick(kids, (57, 59)))
        + pond
    )
    write(out, 'gauche', left)
    field = text_of(pick(kids, 29)).replace(
        'M980 322 L1061 300 L1061 356 L1000 356 Z', 'M980 322 L1046 302 L1057 356 L1000 356 Z')
    assert 'L1046 302' in field
    assert kids[59].get('transform') == 'translate(860.0 374.0) scale(0.780)'  # the tractor
    assert kids[38].get('transform') == 'translate(900.0 302.0) scale(1.120)'  # the windmill
    tractor = text_of(pick(kids, 60)).replace(
        'translate(860.0 374.0) scale(0.780)', 'translate(852.0 400.0) scale(1.120)')
    mill = text_of(pick(kids, 39)).replace(
        'translate(900.0 302.0) scale(1.120)', 'translate(900.0 302.0) scale(1.288)')
    right = (
        text_of(pick(kids, 2))  # the sun
        + field + text_of(pick(kids, (30, 36), 38))  # its last stubble left out
        + mill + tractor + text_of(pick(kids, (61, 63)))
    )
    write(out, 'droite', right)
    write(out, 'pommier', scaled(layer(source, 'c-campagne-pommier'), 208, 328, .92, -12))
    write(out, 'tournesols', moved(layer(source, 'c-campagne-fleurs'), -10, 0))
    copy(mockups / 'decors' / 'd-nuage.svg', out, 'nuage')
    copy(source / 'd-ailes.svg', out, 'ailes')
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
