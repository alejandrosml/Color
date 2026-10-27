#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Authoring source of the Color stamp catalogue.

Writes src/stamps/catalog.rs (the catalogue compiled into the core) and, with
--preview FILE, an HTML sheet to look at every stamp. Original artwork drawn
for Color on a 100 x 100 grid; identifiers are positions in STAMPS and are
stored in project files: only ever APPEND a stamp, never reorder or remove.

Path data uses absolute M, L, C, Q and Z commands only, numbers separated by
spaces: the Flutter interface parses exactly this subset.
"""
import argparse
import math
import pathlib

INK = "#293d4b"
PAPER = "#fffcf0"
SUN = "#ffcd62"
CORAL = "#ed8c88"
SKY = "#a8d8f0"
LEAF = "#78a66f"
WOOD = "#9a6b4a"
TEAL = "#43ac9c"
PURPLE = "#9a82c9"
P, D, L, NONE = "P", "D", "L", "-"   # chosen colour, its shade, its tint, nothing
K = 0.5522847498


def n(value):
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def pts(*values):
    return " ".join(n(v) for v in values)


def ellipse(cx, cy, rx, ry):
    kx, ky = rx * K, ry * K
    return (f"M {pts(cx + rx, cy)} "
            f"C {pts(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry)} "
            f"C {pts(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy)} "
            f"C {pts(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry)} "
            f"C {pts(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy)} Z")


def circle(cx, cy, r):
    return ellipse(cx, cy, r, r)


def polygon(*points):
    first, *rest = points
    return f"M {pts(*first)} " + " ".join(f"L {pts(*p)}" for p in rest) + " Z"


def polyline(*points):
    first, *rest = points
    return f"M {pts(*first)} " + " ".join(f"L {pts(*p)}" for p in rest)


def star(cx, cy, outer, inner, count=5, turn=-90):
    points = []
    for index in range(count * 2):
        radius = outer if index % 2 == 0 else inner
        angle = math.radians(turn + index * 180 / count)
        points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return polygon(*points)


def layer(path, fill=NONE, stroke=INK, width=4):
    return (fill, stroke, width if stroke != NONE else 0, " ".join(path.split()))


def flat(path, fill):
    return layer(path, fill, NONE, 0)


def line(path, width=4, stroke=INK):
    return layer(path, NONE, stroke, width)


STAMPS = []


def stamp(key, *layers):
    STAMPS.append((key, layers))


# 0 -------------------------------------------------------------------------
stamp("etoile",
      layer(star(50, 53, 43, 18), P),
      flat(circle(41, 44, 4), L))

# 1
HEART = ("M 50 88 C 22 66 7 50 7 32 C 7 18 18 9 30 9 C 39 9 46 14 50 22 "
         "C 54 14 61 9 70 9 C 82 9 93 18 93 32 C 93 50 78 66 50 88 Z")
stamp("coeur",
      layer(HEART, P),
      flat(ellipse(28, 28, 8, 6), L))

# 2
RAYS = []
for index in range(8):
    a = math.radians(index * 45)
    b, c = a - 0.2, a + 0.2
    RAYS.append(polygon((50 + 31 * math.cos(b), 50 + 31 * math.sin(b)),
                        (50 + 46 * math.cos(a), 50 + 46 * math.sin(a)),
                        (50 + 31 * math.cos(c), 50 + 31 * math.sin(c))))
stamp("soleil",
      layer(" ".join(RAYS), P),
      layer(circle(50, 50, 25), P),
      flat(circle(42, 46, 3), INK),
      flat(circle(58, 46, 3), INK),
      line("M 40 56 C 44 63 56 63 60 56", 3))

# 3
stamp("lune",
      layer("M 66 8 C 38 8 14 30 14 54 C 14 78 36 94 62 92 C 74 91 84 86 90 78 "
            "C 64 82 44 68 44 46 C 44 30 52 16 66 8 Z", P),
      flat(circle(30, 52, 4), L),
      flat(circle(38, 70, 3), L))

# 4
stamp("nuage",
      layer("M 24 78 C 8 78 3 62 12 52 C 8 38 20 28 32 33 C 36 18 56 14 65 27 "
            "C 80 21 95 33 89 49 C 99 58 94 78 78 78 Z", P),
      line("M 30 66 C 36 70 46 70 52 66", 3, D))

# 5
PETALS = " ".join(circle(50 + 23 * math.cos(math.radians(a)),
                         50 + 23 * math.sin(math.radians(a)), 15)
                  for a in range(-90, 270, 60))
stamp("fleur",
      layer(PETALS, P),
      layer(circle(50, 50, 13), SUN),
      flat(circle(46, 46, 3), PAPER))

# 6
stamp("arbre",
      layer(polygon((43, 60), (57, 60), (60, 93), (40, 93)), WOOD),
      layer("M 30 66 C 12 66 6 48 18 38 C 14 22 30 10 44 16 C 54 4 76 10 78 26 "
            "C 94 30 96 52 82 60 C 76 70 60 70 54 64 C 48 70 36 70 30 66 Z", P),
      flat(circle(36, 34, 5), L),
      flat(circle(62, 44, 4), L))

# 7
stamp("maison",
      layer(polygon((22, 46), (78, 46), (78, 91), (22, 91)), P),
      layer(polygon((10, 49), (50, 13), (90, 49)), D),
      layer(polygon((44, 64), (58, 64), (58, 91), (44, 91)), WOOD),
      layer(polygon((27, 56), (39, 56), (39, 68), (27, 68)), SKY),
      layer(polygon((63, 56), (73, 56), (73, 68), (63, 68)), SKY),
      flat(circle(55, 78, 1.8), SUN))

# 8
stamp("chat",
      layer("M 18 44 L 14 12 L 38 24 C 46 21 54 21 62 24 L 86 12 L 82 44 "
            "C 90 62 76 86 50 86 C 24 86 10 62 18 44 Z", P),
      flat(polygon((21, 22), (33, 28), (23, 36)), L),
      flat(polygon((79, 22), (67, 28), (77, 36)), L),
      flat(ellipse(36, 52, 4, 6), INK),
      flat(ellipse(64, 52, 4, 6), INK),
      layer(polygon((45, 62), (55, 62), (50, 68)), CORAL, INK, 2.5),
      line("M 50 68 C 50 74 43 76 40 72 M 50 68 C 50 74 57 76 60 72", 2.5),
      line("M 28 64 L 8 60 M 28 69 L 9 73 M 72 64 L 92 60 M 72 69 L 91 73", 2.5))

# 9
stamp("poisson",
      layer(polygon((66, 50), (94, 30), (88, 50), (94, 70)), D),
      layer(ellipse(42, 50, 34, 23), P),
      layer("M 40 28 C 46 14 60 14 62 28 Z", D),
      flat(circle(24, 44, 6.5), PAPER),
      flat(circle(23, 44, 3), INK),
      line("M 12 56 C 16 60 22 61 26 58", 2.5),
      line("M 46 42 C 52 46 52 54 46 58", 2.5, D))

# 10
stamp("papillon",
      layer("M 50 46 C 34 12 4 12 8 40 C 10 56 34 56 50 50 Z "
            "M 50 46 C 66 12 96 12 92 40 C 90 56 66 56 50 50 Z", P),
      layer("M 50 54 C 32 54 14 62 20 80 C 26 94 46 84 50 60 Z "
            "M 50 54 C 68 54 86 62 80 80 C 74 94 54 84 50 60 Z", L),
      flat(circle(26, 32, 6), L),
      flat(circle(74, 32, 6), L),
      layer(ellipse(50, 52, 5, 21), INK, INK, 2),
      line("M 48 32 C 44 22 40 16 34 14 M 52 32 C 56 22 60 16 66 14", 2.5))

# 11
stamp("ballon",
      line("M 50 78 C 42 84 58 90 50 97", 3),
      layer(polygon((45, 71), (55, 71), (53, 79), (47, 79)), D),
      layer(ellipse(50, 40, 29, 33), P),
      flat(ellipse(39, 27, 7, 10), L))

# 12
stamp("voiture",
      layer("M 8 68 L 8 54 C 8 49 12 46 17 46 L 27 46 L 38 28 L 67 28 L 80 46 "
            "L 87 47 C 91 48 93 51 93 55 L 93 68 Z", P),
      layer(polygon((40, 33), (51, 33), (51, 46), (33, 46)), SKY, INK, 3),
      layer(polygon((56, 33), (65, 33), (74, 46), (56, 46)), SKY, INK, 3),
      layer(circle(29, 68, 11), INK),
      layer(circle(72, 68, 11), INK),
      flat(circle(29, 68, 4.5), PAPER),
      flat(circle(72, 68, 4.5), PAPER),
      flat(ellipse(88, 54, 2.5, 3), SUN))

# 13
stamp("bateau",
      line("M 48 62 L 48 12", 4),
      layer(polygon((53, 16), (53, 55), (86, 55)), PAPER),
      layer(polygon((43, 24), (43, 55), (20, 55)), L),
      layer(polygon((8, 62), (92, 62), (76, 86), (24, 86)), P),
      line("M 20 72 L 80 72", 3, D))

# 14
stamp("fusee",
      layer(polygon((36, 54), (18, 80), (36, 73)), D),
      layer(polygon((64, 54), (82, 80), (64, 73)), D),
      layer("M 40 73 C 42 84 46 91 50 97 C 54 91 58 84 60 73 Z", SUN),
      layer("M 50 5 C 68 20 71 46 66 73 L 34 73 C 29 46 32 20 50 5 Z", P),
      layer(circle(50, 37, 9.5), SKY),
      flat(circle(47, 34, 2.5), PAPER))

# 15
stamp("pomme",
      layer("M 50 32 C 38 21 13 27 13 53 C 13 77 32 94 50 87 C 68 94 87 77 87 53 "
            "C 87 27 62 21 50 32 Z", P),
      line("M 50 32 C 50 23 53 16 58 11", 4),
      layer("M 57 22 C 63 9 78 9 84 13 C 80 26 66 30 57 22 Z", LEAF, INK, 3),
      flat(ellipse(30, 46, 6, 9), L))

# 16
stamp("sourire",
      layer(circle(50, 50, 41), P),
      flat(circle(26, 58, 6), CORAL),
      flat(circle(74, 58, 6), CORAL),
      flat(ellipse(36, 42, 4.5, 6.5), INK),
      flat(ellipse(64, 42, 4.5, 6.5), INK),
      line("M 32 60 C 38 74 62 74 68 60", 4))

# 17
stamp("eclair",
      layer(polygon((58, 5), (20, 55), (45, 55), (36, 95), (82, 40), (55, 40), (68, 5)), P),
      line("M 54 16 L 36 44", 3, L))

# 18
stamp("champignon",
      layer("M 36 50 L 64 50 C 64 66 68 80 72 90 L 28 90 C 32 80 36 66 36 50 Z", PAPER),
      layer("M 8 54 C 8 26 28 9 50 9 C 72 9 92 26 92 54 Z", P),
      flat(circle(32, 31, 7.5), PAPER),
      flat(circle(58, 25, 6), PAPER),
      flat(circle(74, 42, 5.5), PAPER),
      flat(circle(48, 43, 4.5), PAPER))

# 19
stamp("couronne",
      layer(polygon((10, 82), (10, 32), (31, 54), (50, 20), (69, 54), (90, 32), (90, 82)), P),
      layer(polygon((10, 68), (90, 68), (90, 82), (10, 82)), D),
      layer(circle(10, 30, 6), CORAL, INK, 3),
      layer(circle(50, 18, 6), TEAL, INK, 3),
      layer(circle(90, 30, 6), PURPLE, INK, 3),
      flat(circle(30, 75, 3.5), SUN),
      flat(circle(50, 75, 3.5), SUN),
      flat(circle(70, 75, 3.5), SUN))

# 20
stamp("goutte",
      layer("M 50 6 C 36 28 20 46 20 62 C 20 80 34 93 50 93 C 66 93 80 80 80 62 "
            "C 80 46 64 28 50 6 Z", P),
      flat(ellipse(38, 62, 5, 10), L))

# 21
stamp("oiseau",
      layer(polygon((24, 58), (4, 46), (8, 68)), D),
      line("M 42 80 L 40 93 M 56 80 L 58 93", 3),
      layer(circle(50, 52, 29), P),
      layer("M 30 52 C 34 44 50 44 56 54 C 52 68 36 68 30 52 Z", D, INK, 3),
      layer(polygon((76, 44), (95, 50), (76, 57)), SUN, INK, 3),
      flat(circle(63, 42, 6), PAPER),
      flat(circle(64, 42, 3), INK))

# 22
stamp("chien",
      layer("M 22 30 C 8 30 4 50 10 64 C 14 72 24 66 26 54 Z", D),
      layer("M 78 30 C 92 30 96 50 90 64 C 86 72 76 66 74 54 Z", D),
      layer("M 50 14 C 72 14 82 30 82 50 C 82 72 68 88 50 88 C 32 88 18 72 18 50 "
            "C 18 30 28 14 50 14 Z", P),
      flat(ellipse(50, 66, 17, 14), L),
      flat(ellipse(37, 44, 4, 5.5), INK),
      flat(ellipse(63, 44, 4, 5.5), INK),
      flat(ellipse(50, 60, 7, 5), INK),
      line("M 50 65 C 50 73 42 76 39 71 M 50 65 C 50 73 58 76 61 71", 2.5))

# 23
# Four bows and nothing else: no cloud at their feet. The bows keep their own
# colours whatever colour is chosen, and sit in the middle of the box. Each
# shows 8 units of itself; the three outer ones reach 1 unit under the next,
# painted after them, so that no hairline of the sheet shows between two bows.
# Their colours are no colour of the palette of the interface, nor close to
# one: a bow must not vanish on a sheet filled with « Ciel » or « Prairie ».
# A test of the interface measures that distance.
BOWS = ("#f98a8d", "#ffe45c", "#93d36e", "#77aef0")
ARCS = []
for (radius, width), colour in zip(((39.5, 9), (31.5, 9), (23.5, 9), (16, 8)), BOWS):
    k = radius * K
    ARCS.append(line(f"M {pts(50 - radius, 70)} "
                     f"C {pts(50 - radius, 70 - k, 50 - k, 70 - radius, 50, 70 - radius)} "
                     f"C {pts(50 + k, 70 - radius, 50 + radius, 70 - k, 50 + radius, 70)}",
                     width, colour))
stamp("arcenciel", *ARCS)


def rust_paint(value):
    return {P: "Primary", D: "Dark", L: "Light", NONE: "None"}.get(value) or f"Fixed(0x{value[1:]})"


def write_rust(path):
    out = ["// SPDX-License-Identifier: MIT",
           "// Generated by tools/make_stamp_catalog.py: edit that file, not this one.",
           "// Identifiers are positions in STAMPS and live in project files:",
           "// append new stamps only.",
           "use super::{Paint::*, Stamp, StampLayer};",
           "",
           "pub(crate) static STAMPS: &[Stamp] = &["]
    for key, layers in STAMPS:
        out.append("    Stamp {")
        out.append(f"        key: \"{key}\",")
        out.append("        layers: &[")
        for fill, stroke, width, data in layers:
            out.append("            StampLayer {")
            out.append(f"                fill: {rust_paint(fill)},")
            out.append(f"                stroke: {rust_paint(stroke)},")
            out.append(f"                width: {float(width)},")
            out.append(f"                path: \"{data}\",")
            out.append("            },")
        out.append("        ],")
        out.append("    },")
    out.append("];")
    pathlib.Path(path).write_text("\n".join(out) + "\n")


def tone(rgb, role):
    r, g, b = (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255
    if role == D:
        r, g, b = r * 7 // 10, g * 7 // 10, b * 7 // 10
    elif role == L:
        r, g, b = r + (255 - r) * 6 // 10, g + (255 - g) * 6 // 10, b + (255 - b) * 6 // 10
    return f"#{r:02x}{g:02x}{b:02x}"


def svg_paint(value, rgb):
    if value == NONE:
        return "none"
    return tone(rgb, value) if value in (P, D, L) else value


def write_preview(path, colours=(0x477fb2, 0xd75e56, 0xeebf4e, 0x78a66f)):
    cells = []
    for index, (key, layers) in enumerate(STAMPS):
        rgb = colours[index % len(colours)]
        body = "".join(
            f'<path d="{data}" fill="{svg_paint(fill, rgb)}" stroke="{svg_paint(stroke, rgb)}" '
            f'stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>'
            for fill, stroke, width, data in layers)
        cells.append(f'<figure><svg viewBox="-4 -4 108 108" width="150" height="150">{body}</svg>'
                     f'<figcaption>{index} {key}</figcaption></figure>')
    html = ("<!doctype html><meta charset=utf-8><style>body{margin:16px;background:#fffefa;"
            "font:13px sans-serif;display:grid;grid-template-columns:repeat(6,170px);gap:6px}"
            "figure{margin:0;text-align:center}svg{background:#fff;border:1px solid #d8e2d9;"
            "border-radius:10px}</style>" + "".join(cells))
    pathlib.Path(path).write_text(html)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    root = pathlib.Path(__file__).resolve().parent.parent
    parser.add_argument("--output", default=str(root / "src/stamps/catalog.rs"))
    parser.add_argument("--preview")
    arguments = parser.parse_args()
    keys = [key for key, _ in STAMPS]
    assert len(set(keys)) == len(keys), "duplicate stamp key"
    write_rust(arguments.output)
    if arguments.preview:
        write_preview(arguments.preview)
    print(f"{len(STAMPS)} stamps")
