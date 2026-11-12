#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Cuts the drawings of the mock-ups of November 2026 into the pieces of a
universe of Color (art/univers/<key>/): the ground, what stands on the left
of the sheet, on its right and under it, and the small pictures that move.

    make_universe_art.py MOCKUPS

MOCKUPS is the folder `habillages-maquettes-2026-11-11` of the owner's Mac;
it is not in this repository. The files written here are the ones that
count from now on: a drawing is changed by changing its file in
art/univers/, then

    COLOR_REGENERATE_CATALOGUES=1 cargo test --offline catalogues

A decor is drawn in a frame of 1061 × 407, the sheet in its middle
(266–792 × 26–377). Every piece keeps the coordinates of that frame.

The desk and the paper were retouched in the repository since (step 3 bis,
12 November 2026: nothing goes beyond the frame, the curtain rod is whole
and apart from the curtains, the pencils of the desk stand on its left).
Running this tool again on the mock-ups would undo that: it is kept as the
record of how the first cut was made, and as a start for the next decors.
"""
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
W, H = 1061, 407
INK = '#293d4b'
HERE = Path(__file__).resolve().parent.parent / 'art' / 'univers'


def children(path):
    root = ET.parse(path).getroot()
    kids = list(root)
    defs = [kid for kid in kids if kid.tag == '{%s}defs' % NS]
    rest = [kid for kid in kids if kid.tag != '{%s}defs' % NS]
    return root, defs, rest


def text_of(elements):
    out = []
    for element in elements:
        text = ET.tostring(element, encoding='unicode')
        out.append(re.sub(r' xmlns="[^"]+"', '', text))
    return ''.join(out)


def write(folder, name, body, defs='', width=W, height=H):
    folder.mkdir(parents=True, exist_ok=True)
    head = '<svg xmlns="%s" viewBox="0 0 %s %s" width="%s" height="%s">' % (NS, width, height, width, height)
    (folder / (name + '.svg')).write_text(
        head + ('<defs>%s</defs>' % defs if defs else '') + body + '</svg>\n', encoding='utf-8')


def copy(source, folder, name):
    """A small picture as it is, with the size its viewBox gives."""
    text = Path(source).read_text(encoding='utf-8')
    box = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', text)
    width, height = box.group(1), box.group(2)
    text = re.sub(r' preserveAspectRatio="[^"]+"', '', text)
    if ' width="' not in text.split('>')[0]:
        text = text.replace('<svg ', '<svg width="%s" height="%s" ' % (width, height), 1)
    folder.mkdir(parents=True, exist_ok=True)
    (folder / (name + '.svg')).write_text(text.rstrip('\n') + '\n', encoding='utf-8')


def bureau(mockups):
    source = mockups / 'dessins' / 'bureau'
    out = HERE / 'bureau'
    _, defs, kids = children(source / 'decor-bureau.svg')
    grads = {g.get('id'): text_of([g]) for d in defs for g in d}
    # 0: the wall, with the opening of the window left empty. Here the wall
    # is whole: the sky is a piece laid on it, under the frame.
    wall = '<rect width="%d" height="%d" fill="url(#mur)"/>' % (W, H)
    assert kids[0].get('fill') == 'url(#mur)'
    sparkles = kids[1:221]
    assert all(k.get('fill') == '#e2d8f0' for k in sparkles)
    window = kids[221:228]
    assert window[0].get('fill') == '#fffaf0' and window[-1].get('y') == '238'
    desk = kids[228:260]
    assert desk[0].get('fill') == 'url(#bois)'
    left = kids[260:274]
    assert left[0].get('x') == '10.0' and left[-1].get('transform') == 'translate(216.0 344.0)'
    right = kids[274:328]
    assert right[0].get('fill') == '#388778' and right[-1].get('transform', '').startswith('translate(886.0')
    middle = kids[328:]
    assert middle[0].get('transform', '').startswith('translate(290.0') and len(middle) == 7
    write(out, 'fond', wall + text_of(sparkles) + text_of(desk), grads['mur'] + grads['bois'])
    write(out, 'fenetre', text_of(window))
    write(out, 'gauche', text_of(left))
    write(out, 'droite', text_of(right))
    write(out, 'milieu', text_of(middle))
    for name in ('rideaux', 'plante'):
        _, _, layer = children(source / ('c-bureau-%s.svg' % name))
        write(out, name, text_of(layer))
    copy(source / 'd-chat.svg', out, 'chat')
    for moment in ('matin', 'jour', 'soir', 'nuit'):
        copy(source / ('d-ciel-%s.svg' % moment), out, 'ciel-' + moment)
    copy(mockups / 'decors' / 'd-nuage.svg', out, 'nuage')


# Figures drawn as strokes, on a grid of 5.4 × 9: no font is needed, and the
# reader of the core takes no text.
FIGURES = {
    '0': 'M2.7 0 C0.9 0 0 2 0 4.5 C0 7 0.9 9 2.7 9 C4.5 9 5.4 7 5.4 4.5 C5.4 2 4.5 0 2.7 0 Z',
    '1': 'M0.6 2.2 L3 0 V9',
    '2': 'M0 2.3 C0 -0.7 5.2 -0.7 5.2 2.4 C5.2 4.8 0 6.4 0 9 H5.4',
    '3': 'M0.2 1.2 C1.6 -0.6 5 -0.3 5 2.2 C5 3.8 3.4 4.4 2 4.4 C3.6 4.4 5.3 5.1 5.3 6.8 C5.3 9.5 1.4 9.6 0 7.8',
    '4': 'M4 9 V0 L0 6.2 H5.4',
    '5': 'M5 0 H1 L0.4 4 C2 3 5.3 3.4 5.3 6.2 C5.3 9.4 1.4 9.6 0 7.8',
}


def papier(mockups):
    source = mockups / 'decors'
    out = HERE / 'papier'
    _, _, kids = children(source / 'decor-papier.svg')
    ground = kids[0:223]
    assert ground[0].get('fill') == '#d2b282' and ground[-1].get('stroke') == '#e6cfa6'
    rest = kids[223:]

    def where(element):
        """The side an element stands on: by the first number it writes."""
        spot = element.get('transform') or element.get('d') or ''
        number = re.search(r'-?\d+(?:\.\d+)?', spot)
        x = float(element.get('cx') or (number.group(0) if number else 0))
        return 'gauche' if x < W / 2 else 'droite'

    sides = {'gauche': [], 'droite': []}
    for element in rest:
        # The figures of the ruler were text: drawn as strokes instead.
        for holder in element.iter():
            for text in [kid for kid in holder if kid.tag == '{%s}text' % NS]:
                figure = ET.SubElement(holder, '{%s}path' % NS, {
                    'd': FIGURES[text.text.strip()],
                    'transform': 'translate(%.2f %.2f) scale(0.62)' % (float(text.get('x')), 14.6),
                    'fill': 'none', 'stroke': '#5f452d', 'stroke-width': '1.5',
                    'stroke-linecap': 'round', 'stroke-linejoin': 'round'})
                holder.remove(text)
                assert figure is not None
        sides[where(element)].append(element)
    assert len(sides['gauche']) + len(sides['droite']) == len(rest)
    write(out, 'fond', text_of(ground))
    write(out, 'gauche', text_of(sides['gauche']))
    # The shaving of the pencil lay half under the sheet (x = 790): moved
    # aside, so that a child sees it whole.
    right = text_of(sides['droite']).replace('translate(790.0 378.0)', 'translate(806.0 382.0)')
    assert 'translate(806.0 382.0)' in right
    write(out, 'droite', right)
    for name in ('crayon', 'etoile'):
        _, _, layer = children(source / ('c-papier-%s.svg' % name))
        write(out, name, text_of(layer))


if __name__ == '__main__':
    folder = Path(sys.argv[1])
    bureau(folder)
    papier(folder)
    for universe in sorted(HERE.iterdir()):
        for picture in sorted(universe.glob('*.svg')):
            print('%-28s %7d' % (picture.relative_to(HERE), picture.stat().st_size))
