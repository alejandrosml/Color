# SPDX-License-Identifier: MIT
"""The things of « La ville » (Paris), step 4 of Color 1.2, fourth part,
16 November 2026: each one drawn at its real proportions, in metres (in
centimetres for the pigeon), its feet on y = 0, so that make_city_art.py
can lay it in the decor at the size its distance gives it.

Each function takes k, the number of units of the decor for one unit of the
drawing, and draws its strokes 1.8 units wide (or as asked) whatever k is.
The monuments are drawn from the front after their real measures (see
`tailles-reelles.md` of the report of this part); the pigeon and the boat
from the side, after drawings and photographs of real ones: a rock pigeon
(a small head, a short dark bill with a white cere, an orange eye, a green
and purple neck, two black bars across its grey wing, a dark band at the end
of its tail, short pink legs) and a sightseeing boat of the Seine (a long
low hull, a long glazed cabin, an open deck with its railing on the roof,
the wheelhouse at the front).
"""
import math

import letters

INK = '#293d4b'


def n(value):
    """Two decimals at most: the reader of the core refuses a long fraction
    after a letter of a path."""
    text = ('%.2f' % value).rstrip('0').rstrip('.')
    return '0' if text in ('-0', '') else text


def pts(points):
    return ' '.join('%s %s' % (n(x), n(y)) for x, y in points)


class Pen:
    """Writes the shapes of one drawing, its strokes as wide in the decor
    whatever the scale of the drawing."""

    def __init__(self, k):
        self.k = k
        self.out = []

    def w(self, width):
        return n(width / self.k)

    def path(self, d, fill='none', width=1.8, stroke=INK, extra=''):
        line = '' if width is None else ' stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"' % (stroke, self.w(width))
        self.out.append('<path d="%s" fill="%s"%s%s />' % (d, fill, line, extra))

    def poly(self, points, fill='none', width=1.8, stroke=INK, close=True, extra=''):
        d = 'M' + ' L'.join('%s %s' % (n(x), n(y)) for x, y in points) + (' Z' if close else '')
        self.path(d, fill, width, stroke, extra)

    def rect(self, x, y, w, h, fill, width=1.8, stroke=INK, extra=''):
        self.poly([(x, y), (x + w, y), (x + w, y + h), (x, y + h)], fill, width, stroke, extra=extra)

    def circle(self, x, y, r, fill, width=1.8, stroke=INK):
        line = '' if width is None else ' stroke="%s" stroke-width="%s"' % (stroke, self.w(width))
        self.out.append('<circle cx="%s" cy="%s" r="%s" fill="%s"%s />' % (n(x), n(y), n(r), fill, line))

    def ellipse(self, x, y, rx, ry, fill, width=1.8, stroke=INK):
        line = '' if width is None else ' stroke="%s" stroke-width="%s"' % (stroke, self.w(width))
        self.out.append('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s"%s />' % (n(x), n(y), n(rx), n(ry), fill, line))

    def lines(self, segments, stroke, width=1.2):
        d = ' '.join('M%s %s L%s %s' % (n(a), n(b), n(c), n(e)) for a, b, c, e in segments)
        if d:
            self.path(d, 'none', width, stroke)

    def text(self):
        return ''.join(self.out)


def placed(x, y, k, body):
    """A drawing laid with its feet at (x, y), k units of the decor to one
    of its own."""
    return '<g transform="translate(%s %s) scale(%s)">%s</g>' % (n(x), n(y), n(k), body)


def arc_points(cx, cy, rx, ry, start, end, steps=12):
    """Points along an ellipse, angles in degrees, y going up as the angle
    grows (the drawing's y goes down)."""
    out = []
    for i in range(steps + 1):
        a = math.radians(start + (end - start) * i / steps)
        out.append((cx + rx * math.cos(a), cy - ry * math.sin(a)))
    return out


def pointed_arch(cx, bottom, width, spring, apex):
    """A Gothic arch: straight sides from the bottom (a y) up to the
    springing (a height), then two arcs of circles centred on the
    springing line, meeting in a point at the apex (a height)."""
    half, rise = width / 2, apex - spring
    radius = (half * half + rise * rise) / (2 * half)
    centre = cx - half + radius  # of the left arc
    end = math.acos(max(-1, min(1, (cx - centre) / radius)))
    left = []
    for i in range(10):
        a = math.pi + (end - math.pi) * i / 9
        left.append((centre + radius * math.cos(a), -spring - radius * abs(math.sin(a))))
    right = [(2 * cx - x, y) for x, y in reversed(left[:-1])]
    return [(cx - half, bottom)] + left + right + [(cx + half, bottom)]


# --------------------------------------------------------------------------
# The Eiffel Tower, from the side: 330 m with its antennas; the base a
# square of 125 m; the first floor at 57.6 m, the second at 115.7 m, the
# third at 276.1 m.

def eiffel_outer(h):
    """Half the width of the tower at the height h, from its four corners
    on the ground (62.5 m from the middle) to its top: the curve of the
    tower, nearly a falling exponential."""
    table = [(0, 62.5), (20, 51.5), (40, 42.6), (57.6, 36.2), (80, 29.6), (115.7, 21.4),
             (150, 15.8), (190, 11.4), (230, 8.4), (276.1, 6.2), (290, 5.2)]
    for (h0, x0), (h1, x1) in zip(table, table[1:]):
        if h0 <= h <= h1:
            t = (h - h0) / (h1 - h0)
            return math.exp(math.log(x0) * (1 - t) + math.log(x1) * t)
    return table[-1][1]


def eiffel(k, width=2.0):
    pen = Pen(k)
    body, dark, lattice = '#8b6f57', '#6c5642', '#6f5945'
    hs = [i * 5 for i in range(59)] + [290]
    outline = [(-eiffel_outer(h), -h) for h in hs] + [(eiffel_outer(h), -h) for h in reversed(hs)]
    # The opening under the first floor: the inner sides of the legs, then
    # the great arch between them, its top at 39 m.
    inner = [(-37.5, 0), (-33.8, -10), (-30.6, -20), (-29.2, -24)]
    arch = arc_points(0, -24, 29.2, 15, 180, 0, 16)
    opening1 = inner + arch[1:] + [(x * -1, y) for x, y in reversed(inner)]
    # Between the first and the second floor: the legs lean to each other,
    # the gap between them narrowing up to the second floor.
    opening2 = [(-21.6, -64), (-10.4, -110), (10.4, -110), (21.6, -64)]
    d = ('M' + ' L'.join('%s %s' % (n(x), n(y)) for x, y in outline) + ' Z '
         'M' + ' L'.join('%s %s' % (n(x), n(y)) for x, y in opening1) + ' Z '
         'M' + ' L'.join('%s %s' % (n(x), n(y)) for x, y in opening2) + ' Z')
    pen.path(d, body, width, extra=' fill-rule="evenodd"')
    # The lattice: crosses along each leg and up the shaft.
    segs = []
    for side in (-1, 1):
        for h in range(4, 50, 8):
            xo, xi = eiffel_outer(h), 37.5 - h * 0.28 if h < 24 else 30
            xo2, xi2 = eiffel_outer(h + 8), 37.5 - (h + 8) * 0.28 if h + 8 < 24 else 30
            segs.append((side * xo, -h, side * max(xi2, 23), -(h + 8)))
        for h in range(66, 108, 9):
            xo = eiffel_outer(h)
            xi = 21.6 - (h - 64) * (11.2 / 46)
            xo2 = eiffel_outer(h + 9)
            xi2 = 21.6 - (h + 9 - 64) * (11.2 / 46)
            segs.append((side * xo, -h, side * xi2, -(h + 9)))
            segs.append((side * xi, -h, side * xo2, -(h + 9)))
    for h in range(122, 270, 12):
        a, b = eiffel_outer(h), eiffel_outer(h + 12)
        segs.append((-a, -h, b, -(h + 12)))
        segs.append((a, -h, -b, -(h + 12)))
    pen.lines(segs, lattice, 1.0)
    # The floors, a little wider than the tower where they stand.
    for bottom, top, out in ((52, 63, 4.2), (111, 119, 3.2)):
        half = eiffel_outer((bottom + top) / 2) + out
        pen.rect(-half, -top, half * 2, top - bottom, dark, 1.6)
        pen.lines([(-half + 2, -(bottom + top) / 2, half - 2, -(bottom + top) / 2)], '#a48a70', 0.9)
    # The third floor, closed, then the lantern, its small dome and the
    # antennas up to 330 m.
    pen.rect(-8.6, -284, 17.2, 9, dark, 1.6)
    pen.poly([(-5.2, -284), (-3.4, -298), (3.4, -298), (5.2, -284)], body, 1.4)
    pen.path('M-3.6 -298 Q0 -305 3.6 -298 Z', dark, 1.2)
    pen.path('M0 -303 L0 -330', 'none', 1.4)
    return pen.text()


# --------------------------------------------------------------------------
# Notre-Dame de Paris, the west front: 41 m wide, its towers 69 m, the rose
# 9.6 m across, the spire behind, 96 m.

STONE, STONE_SHADE, STONE_DARK = '#ece2c9', '#dccfb0', '#c9b994'


def notre_dame(k, width=1.8):
    """The west front: its body up to the great gallery (45 m), the two
    towers above it up to 69 m, the spire behind; the portals, the gallery
    of the kings at 20 m, the rose of 9.6 m between the great windows."""
    pen = Pen(k)
    # The spire behind the front, lead grey, from the roof to its top.
    pen.poly([(-3.6, -44), (-1.9, -78), (0, -96), (1.9, -78), (3.6, -44)], '#6f7f8c', 1.4)
    pen.lines([(-3.1, -54, 3.1, -54), (-2.5, -66, 2.5, -66), (-1.9, -78, 1.9, -78)], '#4d5a66', 0.9)
    pen.lines([(0, -96, 0, -99)], INK, 1.0)
    # The body of the front, up to the top of the great gallery.
    pen.rect(-20.5, -45, 41, 45, STONE, width)
    # The towers, from the gallery up to 69 m.
    for side in (-1, 1):
        x0 = 8 if side > 0 else -20.5
        pen.rect(x0, -69, 12.5, 24, STONE, width)
        # The two tall openings of each tower, under their pointed arches.
        cx = side * 14.25
        for dx in (-2.6, 2.6):
            pen.poly(pointed_arch(cx + dx, -48, 2.6, 60.5, 65.6), '#5d6470', 1.2)
        # The balustrade at the top.
        pen.lines([(x0 + 0.3, -67.3, x0 + 12.2, -67.3)], STONE_DARK, 0.9)
        pen.lines([(x0 + 0.8 + i * 1.4, -67.3, x0 + 0.8 + i * 1.4, -69) for i in range(9)], STONE_DARK, 0.7)
    # The buttresses: four, from the ground to the towers.
    for x in (-20.5, -8.5, 6.5, 18.5):
        pen.rect(x, -45, 2, 45, STONE_SHADE, 1.0)
    # The great gallery: an open arcade across the front (38 to 45 m).
    pen.rect(-20.5, -45, 41, 7, STONE_SHADE, 1.2)
    for i in range(16):
        x = -19.4 + i * 2.55
        pen.poly(pointed_arch(x + 1.1, -38.6, 1.5, 41, 43.4), '#8f8f93', 0.7)
    # The rose (9.6 m) in the middle, the great windows of the towers on
    # either side.
    pen.circle(0, -31, 4.8, '#7f9cc4', 1.4)
    pen.circle(0, -31, 1.4, '#d9e2ef', 0.9)
    pen.lines([(1.6 * math.cos(math.radians(a)), -31 - 1.6 * math.sin(math.radians(a)),
                4.6 * math.cos(math.radians(a)), -31 - 4.6 * math.sin(math.radians(a))) for a in range(0, 360, 30)],
              '#e8eef6', 0.8)
    for side in (-1, 1):
        cx = side * 14.25
        pen.poly(pointed_arch(cx, -24.4, 6.4, 30.5, 35.6), '#8fa5c2', 1.2)
        pen.lines([(cx, -24.4, cx, -32.4)], '#e8eef6', 0.8)
    # The gallery of the kings (20 to 23.6 m): a row of niches.
    pen.rect(-20.5, -23.6, 41, 3.6, STONE_SHADE, 1.2)
    pen.lines([(-19.5 + i * 1.44, -20.4, -19.5 + i * 1.44, -23) for i in range(28)], STONE_DARK, 0.8)
    # The three portals, the middle one higher and wider; their doors.
    for cx, w, top, door in ((0, 10, 17.4, 4.4), (-14.25, 7.4, 15, 3.4), (14.25, 7.4, 15, 3.4)):
        pen.poly(pointed_arch(cx, 0, w, top - w * .72, top), STONE_SHADE, 1.4)
        pen.poly(pointed_arch(cx, 0, w - 2.2, top - w * .72 - .4, top - 1.6), STONE_DARK, 1.0)
        pen.rect(cx - door / 2, -8.2, door, 8.2, '#8a5a3a', 1.2)
        pen.lines([(cx, 0, cx, -8.2)], '#5e3c26', 0.8)
    pen.lines([(-20.5, -0.6, 20.5, -0.6)], STONE_DARK, 1.0)
    return pen.text()


# --------------------------------------------------------------------------
# The Arc de triomphe, from the front: 49.54 m high, 44.82 m wide, its
# great arch 29.42 m high and 14.62 m wide.

def arc(k, width=1.8):
    pen = Pen(k)
    pen.rect(-22.41, -49.54, 44.82, 49.54, STONE, width)
    # The attic, the cornice, the frieze.
    pen.rect(-22.41, -49.54, 44.82, 8.14, STONE_SHADE, 1.4)
    pen.rect(-23.3, -41.4, 46.6, 2.2, STONE, 1.4)
    pen.rect(-22.41, -39.2, 44.82, 3.4, STONE_SHADE, 1.0)
    for i in range(7):
        pen.circle(-18 + i * 6, -46, 1.3, STONE_DARK, 0.8)
    # The great arch, round, springing at 22.11 m.
    archway = [(-7.31, 0), (-7.31, -22.11)] + arc_points(0, -22.11, 7.31, 7.31, 180, 0, 14)[1:-1] + [(7.31, -22.11), (7.31, 0)]
    pen.poly(archway, '#cfe0ee', 1.6)
    pen.lines([(-9.6, -22.11, -7.31, -22.11), (7.31, -22.11, 9.6, -22.11)], INK, 1.2)
    # The four great groups carved on the pillars, and the figures over
    # the arch.
    for side in (-1, 1):
        cx = side * 15
        pen.rect(cx - 4.2, -19, 8.4, 12.5, STONE_SHADE, 1.2)
        pen.path('M%s -8 C%s -13 %s -17 %s -17.8 C%s -16 %s -12 %s -8 Z' % (
            n(cx - 2.6), n(cx - 2.2), n(cx - 0.8), n(cx), n(cx + 1.2), n(cx + 2.4), n(cx + 2.8)), STONE_DARK, 0.8)
        pen.rect(cx - 4.2, -31.8, 8.4, 5.6, STONE_SHADE, 1.0)
        pen.path('M%s -29.4 Q%s -34 %s -32' % (n(side * 8.4), n(side * 4.5), n(side * 1.6)), 'none', 0.9, STONE_DARK)
    pen.lines([(-22.41, -1.4, 22.41, -1.4)], STONE_DARK, 1.0)
    return pen.text()


# --------------------------------------------------------------------------
# A building of Haussmann's Paris, five bays wide (14.5 m), its ground
# floor and five floors under a cornice at 20 m, a zinc roof; on its ground
# floor the bakery, over three bays, and the great door of the building.

def building(k, width=1.8):
    pen = Pen(k)
    half = 7.25
    bays = (-5.8, -2.9, 0, 2.9, 5.8)
    # The chimneys behind the roof, then the roof of zinc with a dormer
    # over each bay.
    for x in (-4.6, 4.6):
        pen.rect(x - 0.6, -25.8, 1.2, 3.4, '#d9c7a8', 1.2)
        for dx in (-0.28, 0.28):
            pen.rect(x + dx - 0.16, -26.5, 0.32, 0.7, '#c46a4a', 0.8)
    pen.poly([(-7.45, -20.2), (-6.3, -24.2), (6.3, -24.2), (7.45, -20.2)], '#8f9dac', 1.6)
    pen.lines([(-6.4, -23.8, 6.4, -23.8)], '#a9b5c1', 0.8)
    for x in bays:
        pen.path('M%s -20.5 V-22.2 Q%s -23.2 %s -22.2 V-20.5 Z' % (n(x - 0.5), n(x), n(x + 0.5)), '#e9eef3', 1.1)
        pen.rect(x - 0.3, -22.0, 0.6, 1.2, '#7f9bb5', 0.7)
    # The front of pale stone, its cornice at 20 m.
    pen.rect(-half, -19.6, half * 2, 15.4, STONE, width)
    pen.rect(-7.6, -20.2, 15.2, 0.8, STONE_SHADE, 1.2)
    for y in (-7.0, -10.4, -13.4, -16.3):
        pen.lines([(-half, y, half, y)], STONE_DARK, 0.7)
    # The windows: tall, with their small railings; the long balconies of
    # the second and the fifth floors.
    floors = ((-6.6, 1.8, None), (-9.9, 2.5, 'long'), (-13.0, 2.3, 'small'), (-15.9, 2.2, 'small'), (-18.9, 2.1, 'long'))
    for top_down, h, balcony in floors:
        for x in bays:
            pen.rect(x - 0.6, top_down, 1.2, h, '#9cbfd8', 1.0)
            pen.lines([(x, top_down, x, top_down + h)], '#e9f1f7', 0.6)
            if balcony == 'small':
                pen.rect(x - 0.78, top_down + h - 0.75, 1.56, 0.75, 'none', 0.8, '#2f3a44')
                pen.lines([(x - 0.78 + i * 0.39, top_down + h - 0.75, x - 0.78 + i * 0.39, top_down + h) for i in range(1, 4)], '#2f3a44', 0.5)
        if balcony == 'long':
            y = top_down + h
            pen.rect(-6.9, y - 0.8, 13.8, 0.8, 'none', 0.9, '#2f3a44')
            pen.lines([(-6.9 + i * 0.6, y - 0.8, -6.9 + i * 0.6, y) for i in range(1, 23)], '#2f3a44', 0.5)
            pen.rect(-7.05, y, 14.1, 0.25, STONE_SHADE, 0.7)
    # The ground floor: its stone, the great door of the building and a
    # window behind its grille on the right.
    pen.rect(-half, -4.2, half * 2, 4.2, STONE_SHADE, width)
    pen.lines([(1.45, -2.8, half, -2.8), (1.45, -1.4, half, -1.4)], STONE_DARK, 0.6)
    pen.path('M1.75 0 V-3.2 Q2.9 -4.05 4.05 -3.2 V0 Z', '#2e4a44', 1.2)
    pen.lines([(2.9, 0, 2.9, -3.62)], '#1f3530', 0.8)
    pen.circle(2.6, -1.6, 0.07, '#d9b45a', None)
    pen.circle(3.2, -1.6, 0.07, '#d9b45a', None)
    pen.rect(5.2, -3.3, 1.2, 2.4, '#9cbfd8', 1.0)
    pen.lines([(5.2 + i * 0.3, -3.3, 5.2 + i * 0.3, -0.9) for i in range(1, 4)], '#2f3a44', 0.6)
    # The bakery, over three bays: its painted front and its sign, in
    # gold letters.
    pen.rect(-half, -4.2, 8.7, 4.2, '#2f5e50', width)
    pen.rect(-7.0, -4.05, 8.2, 0.82, '#2f5e50', 1.0, '#d9b45a')
    pen.path(letters.path_of('BOULANGERIE', 0.46, -2.9, -3.41, spacing=0.05), '#e9c46a', None)
    # The awning, red and white, scalloped.
    stripes = 9
    step = 8.2 / stripes
    for i in range(stripes):
        x0 = -7.0 + i * step
        pen.rect(x0, -3.2, step, 0.55, '#c8473c' if i % 2 == 0 else '#fbf6ee', None)
    scallops = ' '.join('Q%s -2.25 %s -2.65' % (n(-7.0 + i * step + step / 2), n(-7.0 + (i + 1) * step)) for i in range(stripes))
    pen.path('M-7 -3.2 H1.2 V-2.65 ' + scallops.replace('Q', 'Q', 1) + ' Z', 'none', 1.0)
    pen.path('M-7 -2.65 ' + scallops, 'none', 1.0)
    # The window full of bread, and the glass door.
    pen.rect(-6.8, -2.3, 5.9, 1.9, '#f3e3b8', 1.2)
    for i in range(5):
        x = -6.4 + i * 0.72
        pen.path('M%s -0.6 L%s -2.0' % (n(x), n(x + 0.55)), 'none', 2.6, '#c98a3d')
        pen.path('M%s -0.6 L%s -2.0' % (n(x), n(x + 0.55)), 'none', 0.9, '#e9b866')
    for x, y in ((-2.6, -0.75), (-1.5, -0.75), (-2.05, -1.4)):
        pen.path('M%s %s Q%s %s %s %s Q%s %s %s %s Z' % (
            n(x - 0.42), n(y), n(x), n(y - 0.62), n(x + 0.42), n(y), n(x), n(y - 0.28), n(x - 0.42), n(y)), '#e3a24d', 0.7)
    pen.rect(-0.6, -2.5, 1.65, 2.5, '#9cbfd8', 1.2)
    pen.lines([(0.22, -2.5, 0.22, 0)], '#2f5e50', 1.0)
    pen.circle(0.0, -1.2, 0.08, '#d9b45a', None)
    return pen.text()


# --------------------------------------------------------------------------
# The street furniture of Paris, green cast iron.

GREEN, GREEN_LIGHT, GREEN_DARK = '#2f6a4e', '#4a8a68', '#24523d'


def morris(k, height, across, width=1.8):
    """A Morris column: its base, the round shaft where the posters are
    put up, a frieze, its cornice, a dome of scales and its crown."""
    pen = Pen(k)
    H, r = height, across / 2
    shaft_top, frieze, cornice, dome_top = H * .66, H * .72, H * .76, H * .93
    pen.rect(-r * 1.08, -H * .06, r * 2.16, H * .06, GREEN_DARK, 1.4)
    pen.rect(-r, -shaft_top, r * 2, shaft_top - H * .06, '#f2ead8', width)
    # The posters: blocks of colour, no letters.
    posters = (('#e9b949', -r * .92, -shaft_top + H * .03, r * .78, H * .22),
               ('#d4573f', -r * .1, -shaft_top + H * .03, r * .96, H * .18),
               ('#5b86b8', -r * .1, -shaft_top + H * .24, r * .96, H * .3),
               ('#f7f3ea', -r * .92, -shaft_top + H * .28, r * .78, H * .26))
    for colour, x, y, w, h in posters:
        pen.rect(x, y, w, h, colour, 0.9)
    pen.lines([(-r * .7, -shaft_top + H * .12, -r * .3, -shaft_top + H * .12),
               (r * .15, -shaft_top + H * .4, r * .7, -shaft_top + H * .4)], '#ffffff', 1.0)
    pen.rect(-r * 1.02, -frieze, r * 2.04, frieze - shaft_top, GREEN, 1.4)
    pen.rect(-r * 1.14, -cornice, r * 2.28, cornice - frieze, GREEN_DARK, 1.4)
    dome = 'M%s %s C%s %s %s %s 0 %s C%s %s %s %s %s %s Z' % (
        n(-r * 1.02), n(-cornice), n(-r), n(-dome_top + H * .02), n(-r * .5), n(-dome_top), n(-dome_top),
        n(r * .5), n(-dome_top), n(r), n(-dome_top + H * .02), n(r * 1.02), n(-cornice))
    pen.path(dome, GREEN, 1.6)
    pen.lines([(x * r, -cornice, x * r * .35, -dome_top + H * .01) for x in (-.6, -.2, .2, .6)], GREEN_DARK, 0.8)
    pen.path('M%s %s Q0 %s %s %s' % (n(-r * .2), n(-dome_top), n(-H - .02), n(r * .2), n(-dome_top)), GREEN_DARK, 1.2)
    return pen.text()


def wallace(k, height, across, width=1.8):
    """A Wallace fountain: a tall pedestal, four caryatids back to back
    (three are seen) holding up a dome of scales, its point on top."""
    pen = Pen(k)
    H, r = height, across / 2
    pen.rect(-r, -H * .055, r * 2, H * .055, GREEN_DARK, 1.4)
    pen.poly([(-r * .86, -H * .055), (-r * .62, -H * .14), (-r * .52, -H * .4), (-r * .58, -H * .42),
              (r * .58, -H * .42), (r * .52, -H * .4), (r * .62, -H * .14), (r * .86, -H * .055)], GREEN, width)
    pen.lines([(-r * .2, -H * .07, -r * .17, -H * .4), (r * .2, -H * .07, r * .17, -H * .4)], GREEN_DARK, 0.9)
    pen.path('M%s %s q%s %s 0 %s q%s %s 0 %s' % (n(0), n(-H * .17), n(r * .12), n(-H * .04), n(-H * .08),
                                              n(-r * .12), n(-H * .04), n(-H * .08)), 'none', 0.9, GREEN_LIGHT)
    pen.rect(-r * .74, -H * .465, r * 1.48, H * .045, GREEN_DARK, 1.4)
    # The caryatids, back to back, their arms raised to the dome; the
    # one in the middle faces us.
    top, bottom = -H * .76, -H * .465
    for cx, w in ((-r * .5, r * .44), (r * .5, r * .44), (0, r * .52)):
        shoulders = top + H * .085
        robe = 'M%s %s C%s %s %s %s %s %s L%s %s C%s %s %s %s %s %s Z' % (
            n(cx - w * .62), n(bottom), n(cx - w * .5), n(bottom - H * .08), n(cx - w * .36), n(shoulders + H * .06), n(cx - w * .34), n(shoulders),
            n(cx + w * .34), n(shoulders), n(cx + w * .36), n(shoulders + H * .06), n(cx + w * .5), n(bottom - H * .08), n(cx + w * .62), n(bottom))
        pen.path(robe, GREEN_LIGHT, 1.0)
        pen.lines([(cx - w * .12, bottom, cx - w * .08, shoulders + H * .05), (cx + w * .14, bottom, cx + w * .1, shoulders + H * .06)], GREEN_DARK, 0.7)
        # The arms, up from the shoulders to the dome; the head between.
        pen.lines([(cx - w * .34, shoulders + H * .005, cx - w * .3, top + H * .005), (cx + w * .34, shoulders + H * .005, cx + w * .3, top + H * .005)], GREEN_LIGHT, 1.8)
        pen.circle(cx, shoulders - H * .028, w * .2, GREEN_LIGHT, 0.9)
    pen.rect(-r, -H * .76, r * 2, H * .025, GREEN_DARK, 1.4)
    dome = 'M%s %s C%s %s %s %s 0 %s C%s %s %s %s %s %s Z' % (
        n(-r * .96), n(-H * .76), n(-r * .9), n(-H * .87), n(-r * .4), n(-H * .93), n(-H * .935),
        n(r * .4), n(-H * .93), n(r * .9), n(-H * .87), n(r * .96), n(-H * .76))
    pen.path(dome, GREEN, 1.6)
    pen.path('M%s %s Q0 %s %s %s M%s %s Q0 %s %s %s' % (
        n(-r * .8), n(-H * .8), n(-H * .83), n(r * .8), n(-H * .8),
        n(-r * .55), n(-H * .87), n(-H * .895), n(r * .55), n(-H * .87)), 'none', 0.8, GREEN_DARK)
    pen.poly([(-r * .08, -H * .93), (0, -H), (r * .08, -H * .93)], GREEN_DARK, 1.0)
    return pen.text()


def lamp(k, height, width=1.8):
    """A street lamp of the quays: a fluted column on its base, the small
    arms where the lamplighter's ladder rested, the lantern and its cap."""
    pen = Pen(k)
    H = height
    pen.poly([(-.26, 0), (-.2, -.5), (.2, -.5), (.26, 0)], '#33433f', width)
    pen.poly([(-.12, -.5), (-.07, -H * .78), (.07, -H * .78), (.12, -.5)], '#3d4f4a', width)
    pen.lines([(-.03, -.6, -.02, -H * .76), (.03, -.6, .02, -H * .76)], '#5c706a', 0.6)
    pen.path('M-.32 %s H.32' % n(-H * .7), 'none', 1.4)
    pen.circle(-.32, -H * .7, .04, '#33433f', 0.8)
    pen.circle(.32, -H * .7, .04, '#33433f', 0.8)
    pen.rect(-.12, -H * .81, .24, H * .03, '#33433f', 1.2)
    lantern = [(-.14, -H * .81), (-.26, -H * .95), (.26, -H * .95), (.14, -H * .81)]
    pen.poly(lantern, '#fff1b8', 1.4)
    pen.lines([(0, -H * .81, 0, -H * .95)], '#33433f', 0.8)
    pen.poly([(-.3, -H * .95), (0, -H * .99), (.3, -H * .95)], '#33433f', 1.2)
    pen.path('M0 %s V%s' % (n(-H * .99), n(-H)), 'none', 1.2)
    return pen.text()


def metro(k, height, across, width=1.8):
    """A Metro entrance of Guimard, from the end where the stairs go down:
    two green stems like the stalks of a plant, bending in at the top,
    each holding an orange lamp like a bud; between them, under a curved
    arch, the frame of the sign (no letters); the ends of the railing on
    either side of the stairs."""
    pen = Pen(k)
    H, half = height, across / 2
    # The stairs going down, in the shadow, between the ends of the railing.
    pen.rect(-half + .42, -.8, across - .84, .8, '#8a867c', 1.2)
    pen.lines([(-half + .5, -.8 + i * .16, half - .5, -.8 + i * .16) for i in range(1, 5)], '#5f5c55', 0.9)
    for side in (-1, 1):
        x0 = -half if side < 0 else half - .42
        pen.rect(x0, -1.0, .42, 1.0, GREEN, 1.3)
        pen.ellipse(x0 + .21, -.52, .12, .26, GREEN_LIGHT, 0.8)
    # The stems, rising from the railing, bending in at the top to their
    # lamps; the arch between them and the sign it holds.
    arch = 'M%s %s C%s %s %s %s 0 %s C%s %s %s %s %s %s' % (
        n(-half + .2), n(-H * .66), n(-half + .3), n(-H * .79), n(-half * .5), n(-H * .82), n(-H * .82),
        n(half * .5), n(-H * .82), n(half - .3), n(-H * .79), n(half - .2), n(-H * .66))
    pen.path(arch, 'none', 4.2, INK)
    pen.path(arch, 'none', 2.6, GREEN)
    for side in (-1, 1):
        x0 = side * (half - .2)
        stem = 'M%s -1 L%s %s C%s %s %s %s %s %s' % (
            n(x0), n(x0), n(-H * .8), n(x0), n(-H * .9), n(x0 - side * .08), n(-H * .95), n(x0 - side * .3), n(-H * .955))
        pen.path(stem, 'none', 4.6, INK)
        pen.path(stem, 'none', 3.0, GREEN)
        cx, cy = x0 - side * .36, -H * .93
        pen.path('M%s %s C%s %s %s %s %s %s C%s %s %s %s %s %s Z' % (
            n(cx - .17), n(cy), n(cx - .19), n(cy - .26), n(cx - .07), n(cy - .4), n(cx), n(cy - .44),
            n(cx + .07), n(cy - .4), n(cx + .19), n(cy - .26), n(cx + .17), n(cy)), '#e2552c', 1.3)
        pen.ellipse(cx - .04, cy - .2, .05, .11, '#ffd27a', None)
        pen.path('M%s %s Q%s %s %s %s' % (n(cx - .17), n(cy), n(cx), n(cy + .07), n(cx + .17), n(cy)), 'none', 1.3, GREEN_DARK)
    plate_w, plate_h = half * 1.3, H * .09
    pen.rect(-plate_w / 2, -H * .762, plate_w, plate_h, '#2c5442', 1.4)
    pen.rect(-plate_w / 2 + .05, -H * .762 + .05, plate_w - .1, plate_h - .1, 'none', 0.7, '#e7d9a2')
    word = 'METROPOLITAIN'
    size = min(plate_h * .48, (plate_w - .3) / letters.width_of(word, 1, spacing=0.0) * 1.0)
    pen.path(letters.path_of(word, size, 0, -H * .762 + plate_h / 2 + size / 2, spacing=size * .04), '#f0d27a', None)
    pen.lines([(0, -H * .82, 0, -H * .76)], GREEN, 1.4)
    return pen.text()


# --------------------------------------------------------------------------
# A rock pigeon, in centimetres, looking to the left: 33 cm from its bill
# to the end of its tail, its head 23 cm above its toes.

def pigeon(k, width=0.6):
    pen = Pen(k)
    grey, wing, dark, head = '#8f9bab', '#b6c0cc', '#2f343b', '#6f7d90'
    # The legs, short and pink, the toes forward.
    pen.lines([(-2.4, -4.6, -2.8, 0), (0.4, -4.8, 0.4, 0)], '#d4706a', 0.9)
    pen.lines([(-2.8, 0, -5.2, 0), (0.4, 0, -1.9, 0), (-2.8, 0, -1.6, 0.1), (0.4, 0, 1.5, 0.1)], '#d4706a', 0.7)
    # The tail, dark at its end; the body, its back nearly level.
    pen.poly([(6, -14.4), (18, -12.8), (18, -10), (6.8, -9.6)], grey, width)
    pen.poly([(15.4, -13.1), (18, -12.8), (18, -10), (15.4, -10.1)], dark, None)
    pen.path('M-8.4 -21.2 C-4.8 -19.4 0 -17.2 7 -14 L7.6 -9.8 C4 -6.2 -1 -4.2 -4.6 -4.6 '
             'C-9.4 -5.2 -12.6 -9.4 -12 -13.6 C-11.6 -16.6 -10.6 -19 -8.4 -21.2 Z', grey, width)
    # The folded wing, pale, with its two black bars.
    pen.path('M-5.6 -16.2 C0 -17.6 6 -15.6 13.6 -12 C8 -9.8 2 -9.4 -2.6 -10.8 C-4.8 -11.8 -5.9 -13.8 -5.6 -16.2 Z', wing, 0.45)
    pen.path('M1.4 -16.6 C2.6 -15 3.2 -13.2 3.2 -10.4 M4.8 -15.8 C6 -14.2 6.6 -12.6 6.6 -10.4', 'none', 0.75, dark)
    # The neck, green and purple, and the small head.
    pen.path('M-12.3 -18.6 C-12.7 -16 -12.3 -14.1 -11.4 -12.6 C-9.6 -12.4 -7.6 -13.4 -6.4 -15.6 '
             'C-6.6 -17.6 -7.3 -19.5 -8.2 -21 Z', '#5e9f86', 0.45)
    pen.path('M-11.4 -12.6 C-9.6 -12.4 -7.6 -13.4 -6.4 -15.6 C-7.6 -15 -9.8 -14.6 -11.9 -14.8 C-11.9 -14 -11.7 -13.2 -11.4 -12.6 Z', '#8c6ea6', None)
    pen.ellipse(-10.3, -20.4, 2.9, 2.6, head, width)
    # The bill, short and dark, its white cere; the orange eye.
    pen.path('M-12.8 -21.1 L-15.4 -20.2 L-12.9 -19.6 Z', '#3a3d42', 0.4)
    pen.ellipse(-12.7, -20.95, .7, .45, '#f1efe8', None)
    pen.circle(-10.8, -21, .8, '#e8862b', None)
    pen.circle(-10.9, -21, .38, '#1f2328', None)
    return pen.text()


# --------------------------------------------------------------------------
# A sightseeing boat of the Seine, in metres, its bow to the left, its
# waterline on y = 0.

def boat(k, length, width=1.0):
    """Its deck 0.7 m above the water, a glazed saloon 2.1 m high, the
    railing of the open deck on its roof, about 4 m above the water in
    all (the bridges of Paris leave 6.36 m)."""
    pen = Pen(k)
    L = length
    # The hull: white, its red band at the waterline, the bow raked.
    hull = 'M0 -0.9 L%s -0.9 L%s 0 L%s 0 C%s -0.1 %s -0.5 0 -0.9 Z' % (n(L), n(L * .99), n(L * .05), n(L * .025), n(L * .008))
    pen.path(hull, '#f7f8f8', None)
    pen.path('M%s -0.32 L%s -0.32 L%s 0 L%s 0 C%s -0.05 %s -0.15 %s -0.32 Z' % (
        n(L * .02), n(L * .995), n(L * .99), n(L * .05), n(L * .035), n(L * .026), n(L * .02)), '#c8473c', None)
    pen.path(hull, 'none', width)
    # The long glazed saloon, its roof.
    pen.rect(L * .08, -3.0, L * .9, 2.1, '#eef2f4', width)
    for i in range(14):
        x = L * .1 + i * L * .062
        pen.rect(x, -2.75, L * .05, 1.55, '#8fbfdc', 0.45)
    pen.rect(L * .07, -3.15, L * .92, 0.15, '#dfe5e8', 0.6)
    # The open deck on its roof: its railing, and the wheelhouse at the
    # front.
    pen.lines([(L * .09, -4.0, L * .98, -4.0)], INK, 0.7)
    pen.lines([(L * .09 + i * L * .0593, -3.15, L * .09 + i * L * .0593, -4.0) for i in range(16)], INK, 0.4)
    pen.rect(L * .12, -4.4, L * .1, 1.25, '#f7f8f8', 0.8)
    pen.rect(L * .133, -4.2, L * .074, 0.55, '#5f8fb3', 0.45)
    return pen.text()


# --------------------------------------------------------------------------
# A plane tree of the quays, in metres: 25 m high.

def plane_tree(k, height=25, width=1.6):
    pen = Pen(k)
    H = height
    pen.poly([(-.6, 0), (-.45, -H * .42), (.45, -H * .42), (.6, 0)], '#b9ab8c', width)
    pen.ellipse(-.15, -H * .2, .25, .5, '#9c8f70', None)
    crown = ('M%s %s C%s %s %s %s %s %s C%s %s %s %s %s %s C%s %s %s %s %s %s C%s %s %s %s %s %s Z') % tuple(n(v) for v in (
        -H * .26, -H * .34,
        -H * .4, -H * .5, -H * .3, -H * .82, -H * .06, -H * .86,
        H * .02, -H * 1.02, H * .3, -H * .96, H * .3, -H * .74,
        H * .44, -H * .6, H * .34, -H * .3, H * .14, -H * .34,
        0, -H * .28, -H * .16, -H * .26, -H * .26, -H * .34))
    pen.path(crown, '#7fae5a', width)
    pen.path('M%s %s Q%s %s %s %s' % (n(-H * .1), n(-H * .7), n(0), n(-H * .78), n(H * .12), n(-H * .74)), 'none', 1.0, '#a5cc80')
    return pen.text()
