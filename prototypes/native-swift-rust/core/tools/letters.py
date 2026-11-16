# SPDX-License-Identifier: MIT
"""Letters in a drawing (Color 1.2, 16 November 2026).

The reader of drawings of the core takes no text: a font would have to come
with it, on every platform, and be read by it. So a word that a decor shows
— the sign of a bakery, of the Metro — is written by the tool that makes the
drawing, with a font of the application (Atkinson Hyperlegible, under the
SIL Open Font Licence, `prototypes/flutter-rust/fonts/`), and turned there
into the outlines of its letters: the core reads them as it reads any shape.

    path_of(text, size, x, y, anchor='middle', bold=True, spacing=0.0)

gives the `d` of one path for the whole word: `size` is the height of a
capital letter, (x, y) the point of its baseline the anchor names. Two
decimals at most in every number (the reader of the core refuses a long
fraction after a letter of a path).
"""
from pathlib import Path

from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont

FONTS = Path(__file__).resolve().parents[3] / 'flutter-rust' / 'fonts' / 'source'
_fonts = {}


def _font(bold):
    name = 'AtkinsonHyperlegible-%s.ttf' % ('Bold' if bold else 'Regular')
    if name not in _fonts:
        _fonts[name] = TTFont(str(FONTS / name))
    return _fonts[name]


def _n(value):
    text = ('%.2f' % value).rstrip('0').rstrip('.')
    return '0' if text in ('-0', '') else text


class _Pen(BasePen):
    """Writes the outlines of a glyph, scaled and moved, y going down."""

    def __init__(self, glyphs, scale, dx, dy):
        super().__init__(glyphs)
        self.scale, self.dx, self.dy = scale, dx, dy
        self.out = []

    def _p(self, point):
        return '%s %s' % (_n(self.dx + point[0] * self.scale), _n(self.dy - point[1] * self.scale))

    def _moveTo(self, p):
        self.out.append('M' + self._p(p))

    def _lineTo(self, p):
        self.out.append('L' + self._p(p))

    def _curveToOne(self, p1, p2, p3):
        self.out.append('C%s %s %s' % (self._p(p1), self._p(p2), self._p(p3)))

    def _qCurveToOne(self, p1, p2):
        self.out.append('Q%s %s' % (self._p(p1), self._p(p2)))

    def _closePath(self):
        self.out.append('Z')


def width_of(text, size, bold=True, spacing=0.0):
    font = _font(bold)
    cap = font['OS/2'].sCapHeight or font['head'].unitsPerEm * .7
    scale = size / cap
    cmap, hmtx = font.getBestCmap(), font['hmtx']
    return sum(hmtx[cmap[ord(c)]][0] for c in text) * scale + spacing * (len(text) - 1)


def path_of(text, size, x, y, anchor='middle', bold=True, spacing=0.0):
    font = _font(bold)
    cap = font['OS/2'].sCapHeight or font['head'].unitsPerEm * .7
    scale = size / cap
    glyphs = font.getGlyphSet()
    cmap, hmtx = font.getBestCmap(), font['hmtx']
    width = width_of(text, size, bold, spacing)
    left = x - (width / 2 if anchor == 'middle' else width if anchor == 'end' else 0)
    out = []
    for c in text:
        name = cmap[ord(c)]
        pen = _Pen(glyphs, scale, left, y)
        glyphs[name].draw(pen)
        out.extend(pen.out)
        left += hmtx[name][0] * scale + spacing
    return ' '.join(out)
