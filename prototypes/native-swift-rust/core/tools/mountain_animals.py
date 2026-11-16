# SPDX-License-Identifier: MIT
"""The ibex and the eagle of « La montagne » (step 4 of Color 1.2, third part,
16 November 2026), drawn again after drawings of real ones, as the owner
asked on seeing the mock-up: make_mountain_art.py lays them in the decor.

The ibex of the Alps, from the side, looking to the left, its hooves on
y = 0: a deep chest, the back going down a little from the withers to the
rump, slender legs with dark shanks and the hock bent back, thick knotted
horns sweeping back over its back, a beard. The golden eagle soaring, seen
from below, in a square of 100.
"""
import math
INK = 'stroke="#293d4b" stroke-linecap="round" stroke-linejoin="round"'
BODY = '#b08a62'; BELLY = '#e3cfae'; LEG = '#7a5e44'; FAR = '#5e4836'
HORN = '#a38c6c'; HORN_FAR = '#7f6a50'; RIDGE = '#5a4a38'

def n(v):
    return ('%.2f' % v).rstrip('0').rstrip('.')

def bez(p0, p1, p2, p3, t):
    a = (1 - t) ** 3; b = 3 * (1 - t) ** 2 * t; c = 3 * (1 - t) * t * t; d = t ** 3
    return (a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1])

def leg_front(dx, fill):
    # The forearm under the chest, the knee, the slender shank, the hoof.
    d = ('M-23 -28 L-22.2 -15 C-22 -11.5 -21.6 -10 -21 -8.6 L-20.6 -1.4 Q-20.5 0 -19.2 0 H-16.6 '
         'Q-15.4 0 -15.5 -1.4 L-15.6 -8.6 C-15.4 -10.4 -15 -12 -15 -15 L-14.6 -28 Z')
    hoof = 'M-20.7 -2.6 H-15.5 L-15.5 -1.4 Q-15.4 0 -16.6 0 H-19.2 Q-20.5 0 -20.6 -1.4 Z'
    return ('<g transform="translate(%s 0)"><path d="%s" fill="%s" stroke-width="1.8" %s />'
            '<path d="%s" fill="#2f2a26" /></g>') % (n(dx), d, fill, INK, hoof)

def leg_hind(dx, fill):
    # The thigh under the rump, the hock bent back a third of the way up,
    # the slender shank.
    d = ('M13.6 -28 C14 -22 15.6 -17 17.4 -13 L17 -1.4 Q17 0 18.3 0 H20.9 Q22.2 0 22.2 -1.4 '
         'L22.3 -9.4 Q24.6 -11 24.2 -13.6 C26.4 -18.6 28.2 -23 28.4 -29 Z')
    hoof = 'M17 -2.6 H22.2 L22.2 -1.4 Q22.2 0 20.9 0 H18.3 Q17 0 17 -1.4 Z'
    return ('<g transform="translate(%s 0)"><path d="%s" fill="%s" stroke-width="1.8" %s />'
            '<path d="%s" fill="#2f2a26" /></g>') % (n(dx), d, fill, INK, hoof)

OUT = ((-29, -67), (-29.5, -82), (-20, -94), (-6, -96.5))
OUT2 = ((-6, -96.5), (6, -98), (15.5, -91), (18.6, -80))

def horn(dx, dy, fill, ridges=True):
    d = ('M%s %s C%s %s %s %s %s %s C%s %s %s %s %s %s '
         'C15 -84.6 9 -89 -1.6 -89 C-12.4 -89 -20.4 -80.5 -21.6 -66.6 Z') % tuple(
        n(v) for p in (OUT[0], OUT[1], OUT[2], OUT[3], OUT2[1], OUT2[2], OUT2[3]) for v in p)
    # Leaning back, about its root on the forehead.
    out = '<g transform="translate(%s %s) rotate(20 -25 -67)"><path d="%s" fill="%s" stroke-width="2" %s />' % (n(dx), n(dy), d, fill, INK)
    if ridges:
        marks = []
        # The knots: short strokes across the horn, from its front edge,
        # shorter towards the tip.
        for i in range(10):
            s = 0.08 + i * 0.1
            curve, t = (OUT, s * 2) if s < .5 else (OUT2, (s - .5) * 2)
            x, y = bez(*curve, t)
            x2, y2 = bez(*curve, min(1, t + .02))
            tx, ty = x2 - x, y2 - y
            l = math.hypot(tx, ty) or 1
            nx, ny = ty / l, -tx / l  # towards the inside of the arc
            length = 5.6 - 3.2 * s
            marks.append('M%s %s l%s %s' % (n(x), n(y), n(-nx * length), n(-ny * length)))
        out += '<path d="%s" fill="none" stroke="%s" stroke-width="1.3" stroke-linecap="round" />' % (' '.join(marks), RIDGE)
    return out + '</g>'

def ibex():
    p = []
    p.append(leg_front(5.5, FAR))
    p.append(leg_hind(-5, FAR))
    p.append(horn(4, 1.2, HORN_FAR, ridges=False))
    p.append('<path d="M28 -40.6 C31.6 -44 33 -48.4 31.2 -51 C29 -48.6 27.6 -45.6 26 -42.4 Z" fill="#4a3a2c" '
             'stroke-width="1.4" %s />' % INK)
    p.append(leg_front(0, LEG))
    p.append(leg_hind(0, LEG))
    # The body and the neck in one outline: chest, throat, nape, withers,
    # back, rump, thigh, belly.
    p.append('<path d="M-26.8 -32 C-29.4 -38 -31.4 -48 -31 -58.6 L-20.2 -64.4 C-17.8 -56 -15.6 -50.6 -12 -47.8 '
             'C0 -47 16 -45 26 -42 C32.6 -40 34.6 -32.4 30.8 -27.2 C28.4 -23.8 22.6 -23 17.6 -23.6 '
             'L-15.6 -23.6 C-21.8 -23.6 -25.6 -27 -26.8 -32 Z" fill="%s" stroke-width="2.2" %s />' % (BODY, INK))
    p.append('<path d="M-14.6 -24.4 C-4 -27.4 9 -27.4 16.6 -24.4 Z" fill="%s" />' % BELLY)
    p.append('<path d="M-9 -36 C2 -34 13 -34.4 22 -36.6" fill="none" stroke="#9a7652" stroke-width="1.6" stroke-linecap="round" />')
    p.append('<path d="M-12 -47.8 C-14 -42 -14 -36 -12 -31" fill="none" stroke="#9a7652" stroke-width="1.4" stroke-linecap="round" />')
    # The head, held high: forehead, straight nose, muzzle, chin.
    p.append('<path d="M-20.4 -66.6 C-24 -70.6 -33.4 -69.4 -39.8 -62.4 C-42.2 -59.8 -41.8 -56.6 -38.8 -55.8 '
             'C-35.8 -55 -32.4 -55.8 -29.2 -57.2 C-25.6 -58.8 -21.4 -61 -20.4 -66.6 Z" '
             'fill="%s" stroke-width="2.2" %s />' % (BODY, INK))
    p.append('<path d="M-32.6 -56.4 C-33.8 -52.4 -33 -49.2 -31 -47 C-30 -50.4 -29.6 -53.6 -29.6 -57 Z" '
             'fill="#4a3a2c" stroke-width="1.2" %s />' % INK)
    p.append('<circle cx="-30.4" cy="-63.4" r="1.7" fill="#293d4b" /><circle cx="-30.9" cy="-64" r="0.6" fill="#ffffff" />')
    p.append('<circle cx="-38.8" cy="-59.6" r="0.8" fill="#293d4b" />')
    p.append(horn(0, 0, HORN))
    p.append('<path d="M-21.6 -64 L-13.4 -66.8 L-18.2 -60.6 Z" fill="%s" stroke-width="1.4" %s />' % (BODY, INK))
    return ''.join(p)

# The golden eagle: long broad wings held nearly straight, ending in six
# spread « fingers », a straight trailing edge, the tail spread, the head
# turned to show the hooked beak and the golden nape, the yellow feet tucked
# under the tail.

def feather(base, tip, width, fill):
    bx, by = base; tx, ty = tip
    dx, dy = tx - bx, ty - by
    l = math.hypot(dx, dy); ux, uy = dx / l, dy / l; px, py = -uy, ux
    w = width / 2
    m1 = (bx + dx * .55 + px * w, by + dy * .55 + py * w)
    m2 = (bx + dx * .55 - px * w, by + dy * .55 - py * w)
    return ('<path d="M%s %s Q%s %s %s %s Q%s %s %s %s Z" fill="%s" stroke-width="1.3" %s />') % (
        n(bx + px * w * .7), n(by + py * w * .7), n(m1[0]), n(m1[1]), n(tx), n(ty),
        n(m2[0]), n(m2[1]), n(bx - px * w * .7), n(by - py * w * .7), fill, INK)

def wing(side):
    """side = -1 for the left wing, +1 for the right one."""
    def X(x):
        return 50 + side * (50 - x)
    parts = []
    # The six « fingers », from the tip of the wing towards the body.
    tips = [(1.5, 45.5), (2.2, 50.2), (3.8, 54.6), (6.6, 58.4), (10.4, 61.4), (14.8, 63.4)]
    bases = [(15, 43.6), (15.6, 46.4), (16.4, 49.2), (17.4, 52), (18.6, 54.6), (20, 57)]
    for (b, t) in zip(bases, tips):
        parts.append(feather((X(b[0]), b[1]), (X(t[0]), t[1]), 4.4, '#3f2e22'))
    # The arm of the wing: its leading edge to the wrist, its trailing edge
    # (the secondary feathers) back to the body.
    pts = [(46, 46.4), (36, 41.6), (26, 39.6), (18.6, 40.6), (14.6, 42.6), (15.6, 50), (18.4, 57.6),
           (24, 61.6), (30, 62.4), (36, 63), (42, 62.6), (46.4, 60), (46.6, 54)]
    d = 'M%s %s C%s %s %s %s %s %s C%s %s %s %s %s %s C%s %s %s %s %s %s C%s %s %s %s %s %s Z' % tuple(
        n(v) for (x, y) in pts for v in (X(x), y))
    parts.append('<path d="%s" fill="#6b4c32" stroke-width="2.2" %s />' % (d, INK))
    # The coverts, lighter, along the leading edge.
    cov = [(45, 47.8), (36, 44.4), (26, 43), (19, 44.6), (19.6, 47.6), (27, 47.2), (36, 48.6), (45, 51.6)]
    d2 = 'M%s %s C%s %s %s %s %s %s C%s %s %s %s %s %s Z' % tuple(
        n(v) for (x, y) in (cov[0], cov[1], cov[2], cov[3], cov[4], cov[5], cov[6]) for v in (X(x), y))
    parts.append('<path d="%s" fill="#8a6846" />' % d2)
    # The edge of the secondary feathers, scalloped.
    marks = ' '.join('M%s %s q%s 2.4 %s 0' % (n(X(x)), n(y), n(side * -1.8), n(side * -3.6))
                     for (x, y) in ((22, 59.6), (27.6, 61.2), (33.4, 61.8), (39.2, 61.8)))
    parts.append('<path d="%s" fill="none" stroke="#3f2e22" stroke-width="1.2" stroke-linecap="round" />' % marks)
    return ''.join(parts)

def eagle():
    p = []
    # The tail, spread, rounded at its end.
    p.append('<path d="M44.4 60 L39.6 78.6 C44 82 56 82 60.4 78.6 L55.6 60 Z" fill="#6b4c32" stroke-width="2" %s />' % INK)
    p.append('<path d="M45.6 66 L44 78 M50 66 V80 M54.4 66 L56 78" fill="none" stroke="#3f2e22" stroke-width="1.2" stroke-linecap="round" />')
    p.append(wing(-1))
    p.append(wing(+1))
    # The body, and the yellow feet tucked in.
    p.append('<ellipse cx="50" cy="54" rx="7.2" ry="12.6" fill="#5e4630" stroke="#293d4b" stroke-width="2.2" />')
    p.append('<path d="M45.6 62.6 q1.6 2.8 4.4 2.4 q2.8 0.4 4.4 -2.4" fill="none" stroke="#8a6846" stroke-width="1.6" stroke-linecap="round" />')
    p.append('<path d="M46.4 64.6 l-0.8 3.4 l2.2 -1.2 Z M53.6 64.6 l0.8 3.4 l-2.2 -1.2 Z" fill="#f4c430" stroke-width="1.1" %s />' % INK)
    # The head, turned to the left: the golden nape, the hooked beak.
    p.append('<path d="M44.6 40.6 C44 35.4 47.4 32.4 51.4 32.8 C55.4 33.2 57.2 36.6 56.4 40.4 C55.6 43.6 52.6 45 49.6 44.8 C46.8 44.6 45 43 44.6 40.6 Z" fill="#5e4630" stroke-width="2.2" %s />' % INK)
    p.append('<path d="M49.4 33.2 C53.4 32.8 56.4 35.4 56.4 39 C54.8 37.6 52.4 37 50.2 36.8 Z" fill="#d4a24c" />')
    p.append('<path d="M45.2 38.6 L40.2 38.8 C38.4 39 37.6 40.8 38.8 42.4 C39.2 41.2 40 40.8 41 40.8 L45 41.4 Z" fill="#4a4e57" stroke-width="1.3" %s />' % INK)
    p.append('<path d="M45.4 38.4 L43 38.6 L43.2 41.2 L45.4 41.6 Z" fill="#f4c430" stroke-width="1" %s />' % INK)
    p.append('<circle cx="47.4" cy="37.8" r="1.5" fill="#293d4b" /><circle cx="47" cy="37.3" r="0.5" fill="#ffffff" />')
    p.append('<path d="M45.6 36.2 Q47.4 35.2 49.4 36" fill="none" stroke="#293d4b" stroke-width="1.1" stroke-linecap="round" />')
    return ''.join(p)
