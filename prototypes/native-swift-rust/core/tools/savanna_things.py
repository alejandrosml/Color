# SPDX-License-Identifier: MIT
"""The things of « La savane », step 4 of Color 1.2, fifth part, 16 November
2026: each one drawn at its real measures, in metres (the meerkat in
centimetres), its feet on y = 0, for make_savanna_art.py to lay it at the
size its distance gives it — as the city was (city_things.py).

The animals are drawn from the side after drawings of real ones, looked at
before drawing (the owner, 16 November 2026: « dessine les animaux d'après
de vrais dessins en 2D »):

- the giraffe: very long legs, the withers high and the back falling to
  the rump, a long neck, a small head with its ossicones, a tail with a
  dark tuft, patches of brown parted by pale lines;
- the African elephant: a huge head with ears shaped like Africa that
  cover its shoulder, a back hollow between the shoulder and the hip, legs
  like pillars, the trunk hanging nearly to the ground, the tusks curving
  forward;
- the plains zebra: a horse's body, a short upright mane, black stripes,
  upright on the body, slanting on the rump, across on the legs, a dark
  muzzle;
- the lion lying down, its head up: the forelegs stretched in front, the
  mane, the tail along the ground with its black tuft;
- the meerkat standing up on its hind legs, its tail behind for balance,
  its forepaws hanging in front of its chest, dark patches round its eyes.
"""
import math

from city_things import INK, Pen, n, placed  # noqa: F401  (placed is used by the layout)


def smooth(points, closed=True):
    """A smooth path through points (Catmull-Rom made into cubic Béziers)."""
    pts = list(points)
    count = len(pts)
    out = ['M%s %s' % (n(pts[0][0]), n(pts[0][1]))]
    last = count if closed else count - 1
    for i in range(last):
        p0 = pts[(i - 1) % count] if (closed or i > 0) else pts[i]
        p1 = pts[i]
        p2 = pts[(i + 1) % count]
        p3 = pts[(i + 2) % count] if (closed or i + 2 < count) else p2
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        out.append('C%s %s %s %s %s %s' % (n(c1[0]), n(c1[1]), n(c2[0]), n(c2[1]), n(p2[0]), n(p2[1])))
    if closed:
        out.append('Z')
    return ' '.join(out)


def _clip(pen, name, d):
    pen.out.append('<clipPath id="%s"><path d="%s" /></clipPath>' % (name, d))


# --------------------------------------------------------------------------
# The giraffe, facing right: 5.5 m to the top of its ossicones, 3.3 m at
# the withers.

GIRAFFE_BASE, GIRAFFE_PATCH, GIRAFFE_DARK = '#f2dcac', '#b9682e', '#7a4a26'


def _leg(pen, top, knee, foot, width, colour, hoof='#3b2e25', stroke=1.2):
    """A slender leg from the body to the hoof, bending at its knee."""
    (x0, y0), (x1, y1), (x2, y2) = top, knee, foot
    w0, w1, w2 = width
    d = 'M%s %s L%s %s L%s %s L%s %s L%s %s L%s %s Z' % (
        n(x0 - w0), n(y0), n(x1 - w1), n(y1), n(x2 - w2), n(y2), n(x2 + w2), n(y2), n(x1 + w1), n(y1), n(x0 + w0), n(y0))
    pen.path(d, colour, stroke)
    pen.path('M%s %s L%s %s L%s %s L%s %s Z' % (
        n(x2 - w2 - .02), n(y2), n(x2 - w2), n(y2 - .1), n(x2 + w2), n(y2 - .1), n(x2 + w2 + .02), n(y2)), hoof, None)


def giraffe(k, uid='g'):
    pen = Pen(k)
    # The far legs, darker, then the body, the neck and the head.
    _leg(pen, (-0.62, -2.0), (-0.72, -1.05), (-0.62, 0), (.1, .07, .06), '#d8b98a')
    _leg(pen, (0.86, -2.0), (0.9, -1.0), (0.94, 0), (.1, .07, .06), '#d8b98a')
    body = smooth([(-0.95, -2.86), (-0.2, -3.08), (0.55, -3.3), (1.0, -4.0), (1.45, -4.75), (1.74, -5.12), (1.96, -4.98),
                   (1.98, -4.72), (1.66, -3.92), (1.38, -3.1), (1.26, -2.6), (1.02, -2.12), (0.45, -1.96), (-0.4, -1.92),
                   (-0.96, -2.02), (-1.12, -2.45)])
    head = smooth([(1.7, -5.18), (1.95, -5.24), (2.35, -4.98), (2.48, -4.8), (2.38, -4.7), (2.05, -4.74), (1.82, -4.9)])
    _clip(pen, uid + 'b', body)
    pen.path(body, GIRAFFE_BASE, 1.6)
    # The patches, brown, parted by pale lines, clipped to the body and the
    # neck: a grid of rounded polygons, a little uneven.
    patches = []
    for row in range(13):
        for col in range(10):
            cx = -1.15 + col * 0.36 + (0.18 if row % 2 else 0) + 0.05 * math.sin(row * 2.3 + col)
            cy = -5.2 + row * 0.27 + 0.04 * math.cos(col * 1.7 + row)
            r = 0.13 + 0.03 * ((row * 7 + col * 3) % 4) / 3
            pts = [(cx + r * math.cos(a) * (1 + .15 * math.sin(3 * a + row)), cy + r * .8 * math.sin(a)) for a in [i * math.pi / 3 for i in range(6)]]
            patches.append('M' + ' L'.join('%s %s' % (n(x), n(y)) for x, y in pts) + ' Z')
    pen.out.append('<g clip-path="url(#%sb)"><path d="%s" fill="%s" /></g>' % (uid, ' '.join(patches), GIRAFFE_PATCH))
    pen.path(body, 'none', 1.6)
    # The short mane along the back of the neck.
    pen.path('M0.62 -3.26 Q1.05 -4.0 1.42 -4.66 L1.7 -5.06', 'none', 2.2, '#8a5a32')
    # The near legs, in front of the body: knees, long shanks, hooves.
    _leg(pen, (-0.82, -2.1), (-0.95, -1.05), (-0.8, 0), (.12, .08, .065), GIRAFFE_BASE)
    _leg(pen, (0.7, -2.05), (0.72, -1.0), (0.74, 0), (.12, .08, .065), GIRAFFE_BASE)
    pen.lines([(-0.95, -1.05, -0.86, -0.95), (0.72, -1.0, 0.8, -0.9)], GIRAFFE_DARK, 0.6)
    # The tail, its dark tuft.
    pen.path('M-1.08 -2.7 Q-1.2 -2.1 -1.14 -1.55', 'none', 1.0, GIRAFFE_DARK)
    pen.path('M-1.2 -1.6 Q-1.14 -1.2 -1.08 -1.6 Z', '#3b2e25', 0.6)
    # The head: its ossicones, its ear, its eye, its muzzle.
    pen.path(head, GIRAFFE_BASE, 1.4)
    pen.lines([(1.84, -5.18, 1.8, -5.45), (1.95, -5.2, 1.94, -5.46)], '#5a3a22', 1.4)
    pen.circle(1.8, -5.47, .05, '#3b2e25', None)
    pen.circle(1.94, -5.48, .05, '#3b2e25', None)
    pen.path('M1.72 -5.1 L1.5 -5.2 L1.7 -5.02 Z', GIRAFFE_BASE, 0.9)
    pen.circle(2.07, -5.0, .045, '#2a211b', None)
    pen.path('M2.4 -4.86 Q2.46 -4.78 2.4 -4.72', 'none', 0.7, '#5a3a22')
    return pen.text()


# --------------------------------------------------------------------------
# The African elephant of the savanna, facing left: 3.3 m at the withers.

ELEPHANT, ELEPHANT_FAR, ELEPHANT_EAR = '#9c9893', '#7f7b76', '#8b8782'


def elephant(k):
    pen = Pen(k)
    # The far legs, darker; the body with its hollow back; the near legs.
    for x0, x1 in ((-0.62, -0.18), (0.78, 1.22)):
        pen.path('M%s -1.6 L%s 0 L%s 0 L%s -1.6 Z' % (n(x0), n(x0 + .02), n(x1 - .02), n(x1)), ELEPHANT_FAR, 1.2)
    body = smooth([(-1.05, -3.32), (-0.2, -3.08), (0.6, -3.12), (1.3, -3.2), (1.82, -2.8), (1.92, -2.1), (1.72, -1.45),
                   (1.1, -1.3), (0.2, -1.22), (-0.7, -1.32), (-1.35, -1.6), (-1.55, -2.5)])
    pen.path(body, ELEPHANT, 1.6)
    pen.path('M1.25 -2.9 Q1.55 -2.3 1.45 -1.6', 'none', 0.9, '#85817c')
    for x0, x1 in ((-1.28, -0.78), (0.98, 1.5)):
        pen.path('M%s -1.7 L%s -0.08 Q%s 0 %s 0 L%s 0 Q%s 0 %s -0.08 L%s -1.7 Z' % (
            n(x0), n(x0 + .03), n(x0 + .03), n(x0 + .1), n(x1 - .1), n(x1 - .03), n(x1 - .03), n(x1)), ELEPHANT, 1.4)
        pen.lines([(x0 + .12, -0.06, x0 + .12, -0.14), (x0 + .25, -0.06, x0 + .25, -0.15), (x1 - .12, -0.06, x1 - .12, -0.14)], '#e7e2d8', 0.8)
    # The tail and its tuft.
    pen.path('M1.88 -2.55 Q2.02 -2.0 1.96 -1.42', 'none', 1.0, '#6f6b66')
    pen.path('M1.92 -1.5 L2.02 -1.28 L1.92 -1.32 Z', '#3d3a36', 0.6)
    # The head, the trunk hanging nearly to the ground, the tusk.
    head = smooth([(-1.1, -3.38), (-1.75, -3.42), (-2.15, -3.05), (-2.25, -2.45), (-2.05, -2.05), (-1.6, -2.0), (-1.2, -2.4)])
    pen.path(head, ELEPHANT, 1.5)
    trunk = ('M-2.22 -2.5 C-2.4 -1.9 -2.42 -1.1 -2.36 -0.45 C-2.34 -0.22 -2.24 -0.12 -2.1 -0.2 '
             'C-2.04 -0.24 -2.1 -0.36 -2.16 -0.42 C-2.2 -1.1 -2.12 -1.7 -1.98 -2.12 Z')
    pen.path(trunk, ELEPHANT, 1.3)
    pen.lines([(-2.36, -1.0 + i * .18, -2.2, -1.02 + i * .18) for i in range(4)], '#85817c', 0.6)
    pen.path('M-2.04 -2.16 C-2.3 -1.98 -2.55 -1.82 -2.62 -1.55 C-2.54 -1.7 -2.3 -1.84 -2.0 -1.98 Z', '#f4efe2', 1.0)
    pen.circle(-1.82, -2.82, .045, '#2b2724', None)
    # The great ear, shaped like Africa, over the shoulder.
    ear = smooth([(-1.28, -3.46), (-0.78, -3.4), (-0.42, -3.1), (-0.34, -2.62), (-0.52, -2.18), (-0.82, -1.66), (-1.08, -1.98), (-1.3, -2.3), (-1.5, -2.82)])
    pen.path(ear, ELEPHANT_EAR, 1.4)
    pen.path('M-1.32 -3.1 Q-0.85 -2.8 -0.9 -2.1', 'none', 0.8, '#77736e')
    return pen.text()


# --------------------------------------------------------------------------
# The plains zebra, facing left: 1.3 m at the withers.

def zebra(k, uid='z'):
    pen = Pen(k)
    white, black = '#fbfaf6', '#262626'
    for x, knee in ((-0.36, -0.42), (0.6, -0.4)):
        _leg(pen, (x, -0.8), (x - .02, knee), (x, 0), (.05, .035, .03), '#e9e7e1', '#262626', 1.0)
    body = smooth([(-0.55, -1.33), (0.1, -1.24), (0.55, -1.29), (0.82, -1.1), (0.8, -0.78), (0.55, -0.7), (0.0, -0.7),
                   (-0.5, -0.74), (-0.78, -0.92), (-0.8, -1.12)])
    neck = smooth([(-0.45, -1.34), (-0.8, -1.68), (-0.98, -1.86), (-1.14, -1.62), (-1.0, -1.34), (-0.86, -1.02), (-0.62, -0.96)])
    head = smooth([(-0.93, -1.9), (-1.12, -1.84), (-1.42, -1.44), (-1.53, -1.29), (-1.43, -1.2), (-1.2, -1.32), (-1.04, -1.5), (-0.92, -1.7)])
    _clip(pen, uid + 'b', body + ' ' + neck + ' ' + head)
    for part in (body, neck, head):
        pen.path(part, white, 1.3)
    stripes = []
    # Upright on the body, slanting on the rump, across the neck and head.
    for i in range(11):
        x = -0.72 + i * 0.11
        lean = 0.0 if x < 0.3 else (x - 0.3) * 0.9
        stripes.append('M%s -1.4 L%s -1.4 L%s -0.6 L%s -0.6 Z' % (n(x), n(x + .05), n(x + .05 + lean), n(x + lean)))
    # Across the neck: bands at right angles to it.
    ax, ay = -0.36, -0.52  # the neck, from its base towards the head
    length = math.hypot(ax, ay)
    ux, uy = ax / length, ay / length
    for i in range(8):
        cx, cy = -0.6 + ux * (0.02 + i * 0.1), -1.08 + uy * (0.02 + i * 0.1)
        px, py = -uy * 0.4, ux * 0.4
        w = 0.035
        stripes.append('M%s %s L%s %s L%s %s L%s %s Z' % (
            n(cx - px), n(cy - py), n(cx + px), n(cy + py), n(cx + px + ux * w * 2), n(cy + py + uy * w * 2), n(cx - px + ux * w * 2), n(cy - py + uy * w * 2)))
    for i in range(5):
        y = -1.84 + i * 0.1
        stripes.append('M-1.55 %s L-0.9 %s L-0.9 %s L-1.55 %s Z' % (n(y + .26), n(y - .02), n(y + .015), n(y + .295)))
    pen.out.append('<g clip-path="url(#%sb)"><path d="%s" fill="%s" /></g>' % (uid, ' '.join(stripes), black))
    for part in (body, neck, head):
        pen.path(part, 'none', 1.3)
    # The dark muzzle, the eye, the ears, the upright mane.
    pen.path('M-1.38 -1.46 L-1.52 -1.3 L-1.4 -1.21 L-1.26 -1.32 Z', black, 0.8)
    pen.circle(-1.1, -1.7, .03, black, None)
    pen.path('M-0.96 -1.86 L-0.9 -2.06 L-0.86 -1.84 Z', white, 0.8)
    pen.path('M-0.98 -1.92 L-0.56 -1.42 L-0.46 -1.36', 'none', 2.8, black)
    # The near legs, striped across, and the tail with its tuft.
    for x, knee in ((-0.5, -0.44), (0.46, -0.4)):
        _leg(pen, (x, -0.8), (x - .02, knee), (x, 0), (.055, .04, .032), white, '#262626', 1.0)
        pen.lines([(x - .05, -0.12 * j - 0.15, x + .05, -0.12 * j - 0.15) for j in range(5)], black, 0.9)
    pen.path('M0.8 -1.12 Q0.88 -0.85 0.84 -0.55', 'none', 0.9, black)
    pen.path('M0.79 -0.62 L0.86 -0.42 L0.89 -0.62 Z', black, 0.5)
    return pen.text()


# --------------------------------------------------------------------------
# The lion lying down, its head up, facing left: 0.9 m high with its mane,
# 2 m long and its tail 1 m.

LION, LION_MANE, LION_PALE = '#d39a55', '#8a5226', '#ecc995'


def lion(k):
    pen = Pen(k)
    # The far foreleg, the body lying, the hind leg folded, the tail.
    pen.path('M-0.45 -0.32 L-1.18 -0.1 L-1.2 0 L-0.4 0 Z', '#c08746', 1.1)
    pen.path('M0.95 -0.28 Q1.4 -0.2 1.7 -0.12 Q1.85 -0.08 1.95 -0.2', 'none', 1.6, '#b98244')
    pen.path('M1.9 -0.24 Q2.06 -0.3 2.08 -0.16 Q2.02 -0.04 1.92 -0.1 Z', '#3b2a1c', 0.8)
    body = smooth([(-0.5, -0.78), (0.1, -0.8), (0.7, -0.74), (1.0, -0.52), (1.02, -0.18), (0.75, 0), (-0.2, 0), (-0.6, -0.25)])
    pen.path(body, LION, 1.5)
    pen.path('M0.48 -0.62 Q0.95 -0.62 0.92 -0.2 L0.55 -0.02 Q0.35 -0.25 0.48 -0.62 Z', '#c58c4b', 1.1)
    pen.path('M0.55 -0.02 L0.12 0 L0.1 -0.08 L0.48 -0.12 Z', LION, 1.0)
    # The near foreleg, stretched in front, its paw.
    pen.path('M-0.32 -0.3 L-1.24 -0.12 Q-1.36 -0.06 -1.3 0 L-0.3 0 Z', LION, 1.2)
    pen.lines([(-1.28, -0.02, -1.24, -0.08), (-1.21, -0.02, -1.18, -0.09)], '#8b5d2e', 0.6)
    # The mane round the head and down to the chest; the face.
    mane = smooth([(-0.36, -1.1), (-0.62, -1.24), (-0.95, -1.18), (-1.12, -0.92), (-1.08, -0.58), (-0.88, -0.3), (-0.55, -0.28), (-0.34, -0.6)])
    pen.path(mane, LION_MANE, 1.4)
    face = smooth([(-0.78, -1.02), (-1.0, -0.98), (-1.17, -0.84), (-1.22, -0.7), (-1.08, -0.62), (-0.88, -0.64), (-0.74, -0.8)])
    pen.path(face, LION, 1.2)
    pen.path('M-1.19 -0.72 L-1.12 -0.7 L-1.13 -0.66 Z', '#3b2a1c', None)
    pen.path('M-1.16 -0.64 Q-1.04 -0.6 -0.98 -0.66', 'none', 0.7, '#5c3a1e')
    pen.circle(-0.98, -0.86, .03, '#2a1d12', None)
    pen.path('M-0.74 -1.0 Q-0.72 -1.1 -0.64 -1.06 Q-0.64 -0.98 -0.7 -0.96 Z', LION, 0.8)
    return pen.text()


# --------------------------------------------------------------------------
# The meerkat, standing up, facing right, in centimetres: 30 cm high.

def meerkat(k):
    pen = Pen(k)
    fur, dark, pale = '#c9a77c', '#4a3828', '#e9d6b4'
    pen.path('M-1.5 -3 Q-6 -1.6 -9.5 0 L-8 0 Q-5 -1.2 -1 -2 Z', fur, 0.6)
    pen.path('M-9.5 0 L-8 0 L-8.6 -0.5 Z', dark, None)
    body = smooth([(0.5, -24.5), (3.2, -21), (3.6, -13), (3.2, -6), (2, -2.2), (-1.6, -2.2), (-2.8, -6), (-2.6, -15), (-1.6, -22)])
    pen.path(body, fur, 0.7)
    pen.path(smooth([(1.6, -20), (2.6, -14), (2.2, -7), (0.6, -6), (0.4, -14)]), pale, None)
    pen.lines([(-1.2, -2.4, -1.6, 0), (1.6, -2.4, 2.4, 0)], dark, 0.9)
    pen.path('M2.6 -17.5 Q4.4 -15.6 4.0 -13.4', 'none', 0.9, fur)
    head = smooth([(-1.4, -25.5), (0.6, -29.6), (3.2, -29.2), (6.4, -27.0), (6.6, -26.2), (3.6, -24.6), (0.4, -24)])
    pen.path(head, fur, 0.7)
    pen.ellipse(3.0, -27.6, 1.0, 0.7, dark, None)
    pen.circle(3.1, -27.7, .35, '#f4ead8', None)
    pen.circle(6.5, -26.5, .5, dark, None)
    pen.path('M0.2 -28.6 Q-0.6 -29.4 -0.2 -28 Z', dark, 0.4)
    return pen.text()


# --------------------------------------------------------------------------
# Trees and a termite mound.

def baobab(k, height=20.0, trunk=5.0):
    """A baobab: a trunk like a great bottle, then short, thick branches
    spreading up and out like roots in the air, a few clusters of leaves at
    their ends (most of the year it has none)."""
    pen = Pen(k)
    H, r = height, trunk / 2
    bark, bark_dark = '#a89582', '#8c7a68'
    top = H * .58
    # Each branch: from the top of the trunk, its end, its thickness.
    branches = ((-1.0, -3.2, -6.6, 1.0), (-0.5, -5.0, -7.2, 0.8), (0.0, -0.4, -7.6, 0.75), (0.5, 4.2, -7.0, 0.85),
                (1.0, 6.0, -5.2, 0.9), (-0.8, -6.2, -4.2, 0.7))
    for x0, ex, ey, w in branches:
        sx, sy = x0, -top + 0.4
        tx, ty = ex, -top + ey
        mx, my = (sx + tx) / 2 + (0.4 if ex > 0 else -0.4), (sy + ty) / 2
        pen.path('M%s %s Q%s %s %s %s L%s %s Q%s %s %s %s Z' % (
            n(sx - w), n(sy), n(mx - w * .7), n(my), n(tx - w * .3), n(ty), n(tx + w * .3), n(ty),
            n(mx + w * .7), n(my), n(sx + w), n(sy)), bark, 1.4)
        for dx, dy, rx in ((-0.9, -0.3, 1.0), (0.4, -0.75, 1.1), (1.2, -0.15, .9)):
            pen.ellipse(tx + dx, ty + dy, rx, rx * .55, '#7aa451', 1.0)
    trunk_d = ('M%s 0 C%s %s %s %s %s %s L%s %s C%s %s %s %s %s 0 Z' % (
        n(-r), n(-r * 1.1), n(-H * .22), n(-r * .82), n(-H * .42), n(-r * .52), n(-top),
        n(r * .52), n(-top), n(r * .82), n(-H * .42), n(r * 1.1), n(-H * .22), n(r)))
    pen.path(trunk_d, bark, 1.8)
    pen.lines([(x * r, -H * .04, x * r * .66, -H * .5) for x in (-.55, -.15, .3, .62)], bark_dark, 0.9)
    return pen.text()


def acacia(k, height=7.0, crown=10.0):
    """An umbrella thorn: a trunk dividing into a few branches that reach
    up and out to a flat crown."""
    pen = Pen(k)
    H, c = height, crown / 2
    wood = '#7a5a3e'
    pen.path('M-0.18 0 L-0.12 %s L0.12 %s L0.18 0 Z' % (n(-H * .35), n(-H * .35)), wood, 1.4)
    for x in (-c * .62, -c * .25, c * .2, c * .58):
        pen.path('M0 %s Q%s %s %s %s' % (n(-H * .33), n(x * .4), n(-H * .5), n(x), n(-H * .72)), 'none', 2.2, wood)
    top = smooth([(-c, -H * .74), (-c * .7, -H * .9), (-c * .2, -H * .97), (c * .3, -H * .98), (c * .78, -H * .9), (c * 1.02, -H * .76),
                  (c * .6, -H * .7), (0, -H * .69), (-c * .6, -H * .7)])
    pen.path(top, '#88a650', 1.5)
    pen.path(smooth([(-c * .8, -H * .8), (-c * .3, -H * .92), (c * .4, -H * .92), (c * .8, -H * .82)], closed=False), 'none', 1.0, '#a8c46c')
    return pen.text()


def termite_mound(k, height=2.2, base=2.0):
    pen = Pen(k)
    H, b = height, base / 2
    mound = smooth([(-b, 0), (-b * .75, -H * .35), (-b * .45, -H * .62), (-b * .3, -H * .82), (-b * .12, -H), (b * .05, -H * .95),
                    (b * .18, -H * .7), (b * .42, -H * .74), (b * .52, -H * .52), (b * .82, -H * .3), (b, 0)])
    pen.path(mound, '#b8693f', 1.6)
    pen.path(smooth([(b * .2, -H * .66), (b * .45, -H * .5), (b * .7, -H * .24), (b * .85, -H * .04)], closed=False), 'none', 1.0, '#94512e')
    for x, y in ((-b * .3, -H * .4), (b * .1, -H * .25), (-b * .05, -H * .62)):
        pen.ellipse(x, y, .07, .09, '#6e3a22', None)
    return pen.text()


def vulture(k):
    """A vulture soaring, seen from below, in a square of 100 (2 m across
    its wings when drawn 100 units wide): broad wings fingered at their
    tips, a short tail, a small head."""
    pen = Pen(k)
    wing = ('M50 46 C38 40 22 38 6 42 L3 45 L8 46 L4 48 L10 48 L6 51 L13 50 L11 53 L20 50 C32 52 42 54 50 56 '
            'C58 54 68 52 80 50 L89 53 L87 50 L94 51 L90 48 L96 48 L92 46 L97 45 L94 42 C78 38 62 40 50 46 Z')
    pen.path(wing, '#4a3b30', 1.6)
    pen.path('M50 47 C40 44 26 43 14 45 C28 47 40 49 50 51 C60 49 72 47 86 45 C74 43 60 44 50 47 Z', '#d8cfbf', None)
    pen.path('M46 54 L44 64 L50 62 L56 64 L54 54 Z', '#4a3b30', 1.2)
    pen.ellipse(50, 42.5, 2.6, 3.4, '#d9c2a8', 1.0)
    return pen.text()


def grass_tuft(k, height=0.8, width=0.7, seed=0):
    pen = Pen(k)
    blades = []
    for i in range(9):
        x = -width / 2 + width * i / 8
        lean = ((i * 37 + seed * 11) % 7 - 3) * 0.06
        h = height * (0.65 + ((i * 13 + seed * 5) % 5) * 0.09)
        blades.append('M%s 0 Q%s %s %s %s' % (n(x), n(x + lean * .5), n(-h * .55), n(x + lean), n(-h)))
    pen.path(' '.join(blades), 'none', 1.3, '#a98a3e')
    pen.path(' '.join(blades[::2]), 'none', 0.8, '#d9bf6e')
    return pen.text()


def far_acacia(k, height=7.0):
    pen = Pen(k)
    H = height
    pen.path('M-0.15 0 L-0.1 %s L0.1 %s L0.15 0 Z' % (n(-H * .6), n(-H * .6)), '#a08868', None)
    pen.path(smooth([(-H * .7, -H * .62), (-H * .3, -H * .82), (H * .3, -H * .84), (H * .72, -H * .64), (0, -H * .58)]), '#c2b47a', None)
    return pen.text()
