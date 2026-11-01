#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Makes the font of Color's texts, fonts/DejaVuSans.ttf, from the whole
DejaVu Sans kept beside it in fonts/source/, which the application does not
carry: the scripts and signs a drawing of Color may hold, and no others.

  alleger-la-police.py [--verifier]

Kept: every Latin letter with its accents, Greek, Cyrillic, punctuation,
currencies, figures, arrows, mathematical and technical signs, boxes and
shapes, the symbols and dingbats (the ♥ and ★ of the keyboard of the
sheet among them, and those the emoji keyboards of the systems type as
text: ❤️ ⬅️ ⭐ ✂️…, with their variation selectors). Dropped: the other scripts of DejaVu (Arabic, Hebrew,
Armenian, Georgian, Lao, N'Ko, Tifinagh, the syllabics of Canada…), Braille
and the mathematical alphabets: on the rare drawing that holds them, the
system draws them with a font of its own, as it already does for the
scripts and emoji DejaVu does not have.

Every character kept keeps its glyph, its advance, its kerning and its
ligatures (all layout features stay); the font keeps its names, its hinting
and its vertical metrics: a line keeps its height and a text its width.
The retrospective of October 2026 (P-09) proposed it; measured here.

fontTools (pip install fonttools) is needed only to make the file: the
application carries the result. With --verifier, nothing is written: the
file made in memory must be byte for byte the one in fonts/.
"""
import hashlib
import io
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
FONTS = ROOT / 'prototypes' / 'flutter-rust' / 'fonts'
SOURCE = FONTS / 'source' / 'DejaVuSans.ttf'
TARGET = FONTS / 'DejaVuSans.ttf'
# The whole font, as the licence file names it.
SOURCE_SHA256 = '938c19b7604cd9d4e408d8edcd223730f3b91f00bb081aac29dfc0dca87954e2'

KEPT = [
    (0x0020, 0x007e),  # Basic Latin
    (0x00a0, 0x00ff),  # Latin-1
    (0x0100, 0x024f),  # Latin Extended A and B
    (0x0250, 0x02ff),  # IPA, spacing modifiers
    (0x0300, 0x036f),  # combining diacritical marks
    (0x0370, 0x03ff),  # Greek
    (0x0400, 0x052f),  # Cyrillic and its supplement
    (0x1d00, 0x1dbf),  # phonetic extensions
    (0x1e00, 0x1eff),  # Latin Extended Additional
    (0x1f00, 0x1fff),  # Greek Extended
    (0x2000, 0x206f),  # general punctuation
    (0x2070, 0x209f),  # superscripts and subscripts
    (0x20a0, 0x20cf),  # currencies
    (0x20d0, 0x20ff),  # combining marks for symbols
    (0x2100, 0x214f),  # letterlike symbols
    (0x2150, 0x218f),  # number forms
    (0x2190, 0x21ff),  # arrows
    (0x2200, 0x22ff),  # mathematical operators
    (0x2300, 0x23ff),  # miscellaneous technical
    (0x2400, 0x243f),  # control pictures
    (0x2460, 0x24ff),  # enclosed alphanumerics
    (0x2500, 0x259f),  # box drawing, block elements
    (0x25a0, 0x25ff),  # geometric shapes
    (0x2600, 0x26ff),  # miscellaneous symbols
    (0x2700, 0x27bf),  # dingbats
    (0x27c0, 0x27ff),  # mathematical symbols A, arrows A
    (0x2900, 0x297f),  # arrows B
    (0x2b00, 0x2bff),  # symbols and arrows (⬅ ⬆ ⬇ ⭐ ⭕ of the emoji keyboards)
    (0x2c60, 0x2c7f),  # Latin Extended C
    (0x2de0, 0x2dff),  # Cyrillic Extended A
    (0xa640, 0xa69f),  # Cyrillic Extended B
    (0xa720, 0xa7ff),  # Latin Extended D
    (0xfb00, 0xfb06),  # Latin ligatures
    (0xfe00, 0xfe0f),  # variation selectors, empty: ❤️ keeps its heart
    (0xfffd, 0xfffd),  # replacement character
]


def make(source_bytes):
    options = subset.Options()
    options.layout_features = ['*']
    options.name_IDs = ['*']
    options.name_languages = ['*']
    options.name_legacy = True
    options.legacy_kern = True
    options.hinting = True
    options.notdef_outline = True
    options.glyph_names = True
    options.symbol_cmap = True
    options.legacy_cmap = True
    options.recalc_bounds = False
    options.recalc_timestamp = False
    options.recalc_max_context = False
    # The date and the bounds of the whole font are kept: the same file at
    # every run.
    font = TTFont(io.BytesIO(source_bytes), recalcTimestamp=False, recalcBBoxes=False)
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=[code for low, high in KEPT for code in range(low, high + 1)])
    subsetter.subset(font)
    output = io.BytesIO()
    font.save(output)
    return output.getvalue()


def check(source_bytes, made):
    """Each character kept: the same glyph, advance and side bearing; the
    font: the same units and vertical metrics."""
    whole, light = TTFont(io.BytesIO(source_bytes)), TTFont(io.BytesIO(made))
    problems = []
    for table, fields in (('head', ['unitsPerEm']),
                          ('hhea', ['ascent', 'descent', 'lineGap']),
                          ('OS/2', ['sTypoAscender', 'sTypoDescender', 'sTypoLineGap',
                                    'usWinAscent', 'usWinDescent'])):
        for field in fields:
            if getattr(whole[table], field) != getattr(light[table], field):
                problems.append('%s.%s' % (table, field))
    whole_map, light_map = whole.getBestCmap(), light.getBestCmap()
    expected = {code for code in whole_map if any(low <= code <= high for low, high in KEPT)}
    if set(light_map) != expected:
        problems.append('%d characters missing, %d too many'
                        % (len(expected - set(light_map)), len(set(light_map) - expected)))
    for code in sorted(expected & set(light_map)):
        before = whole['hmtx'][whole_map[code]]
        after = light['hmtx'][light_map[code]]
        if before != after:
            problems.append('U+%04X: %s, was %s' % (code, after, before))
    return problems


def main():
    verify = '--verifier' in sys.argv[1:]
    source_bytes = SOURCE.read_bytes()
    if hashlib.sha256(source_bytes).hexdigest() != SOURCE_SHA256:
        raise SystemExit('fonts/source/DejaVuSans.ttf n’est pas la police attendue.')
    made = make(source_bytes)
    problems = check(source_bytes, made)
    if problems:
        raise SystemExit('Police allégée refusée : ' + '; '.join(problems[:10]))
    if verify:
        if TARGET.read_bytes() != made:
            raise SystemExit('fonts/DejaVuSans.ttf diffère de ce que ce script en fait.')
        print('fonts/DejaVuSans.ttf est bien celle que ce script fait.')
        return
    TARGET.chmod(0o644) if TARGET.exists() else None
    TARGET.write_bytes(made)
    TARGET.chmod(0o444)
    print('%s : %d octets (police entière : %d), SHA-256 %s'
          % (TARGET.relative_to(ROOT), len(made), len(source_bytes),
             hashlib.sha256(made).hexdigest()))


if __name__ == '__main__':
    main()
