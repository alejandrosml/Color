#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""The hats of the companion, one for each universe that has its own
clothes (step 4 of Color 1.2, the end, 16 November 2026).

    make_hats.py

The mock-ups dressed the whole character for each universe (`m-….svg`,
58 kB each); in the application only the hat is kept, drawn here over the
head of `art/interface/logo.svg` (the companion seated, 512 × 512, that the
pebble « Mon dessin » shows): the head is a circle about (256, 142), the top
of its hair at y = 54. Each hat is written as `chapeau.svg` in the folder of
its universe, which names it (`"hat": "chapeau"` in its decor).
"""
import sys
from pathlib import Path

from make_universe_art import HERE

INK = 'stroke="#293d4b" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"'
THIN = 'stroke="#293d4b" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"'

HATS = {
    # A green bucket hat for the forest.
    'foret': (
        '<path d="M176 108 Q256 96 336 108 L328 122 Q256 112 184 122 Z" fill="#4f7f35" %s />'
        '<path d="M200 104 Q198 56 256 52 Q314 56 312 104 Q256 96 200 104 Z" fill="#5f9440" %s />'
        '<path d="M204 92 Q256 84 308 92" fill="none" stroke="#7fb05a" stroke-width="5" stroke-linecap="round" />'
    ) % (INK, INK),
    # A straw hat for the countryside, its red band.
    'campagne': (
        '<ellipse cx="256" cy="106" rx="104" ry="18" fill="#e8c66a" %s />'
        '<path d="M206 104 Q204 58 256 54 Q308 58 306 104 Q256 112 206 104 Z" fill="#efd27c" %s />'
        '<path d="M207 92 Q256 99 305 92 L306 102 Q256 110 206 102 Z" fill="#c8473c" />'
        '<path d="M170 106 Q256 122 342 106" fill="none" stroke="#c9a54e" stroke-width="4" stroke-linecap="round" />'
    ) % (INK, INK),
    # A beret for Paris, tilted, its little stalk.
    'ville': (
        '<path d="M190 98 Q186 58 248 50 Q318 46 334 82 Q338 100 306 102 Q250 108 190 98 Z" fill="#2b3a55" %s />'
        '<path d="M258 50 Q262 38 270 36" fill="none" %s />'
        '<path d="M196 96 Q256 104 318 98" fill="none" stroke="#3f5175" stroke-width="5" stroke-linecap="round" />'
    ) % (INK, INK),
    # A knitted hat with a pompom for the mountain.
    'montagne': (
        '<path d="M196 112 Q190 52 256 48 Q322 52 316 112 Z" fill="#c8473c" %s />'
        '<path d="M194 96 Q256 88 318 96 L318 116 Q256 108 194 116 Z" fill="#f4f1ea" %s />'
        '<path d="M222 60 L222 92 M246 52 L246 90 M270 52 L270 90 M294 60 L294 92" fill="none" stroke="#a83a2f" stroke-width="5" stroke-linecap="round" />'
        '<circle cx="256" cy="40" r="17" fill="#f4f1ea" %s />'
    ) % (INK, INK, INK),
    # A bush hat for the savanna: khaki, its wide brim and band.
    'savane': (
        '<path d="M170 110 Q256 92 342 110 Q336 124 256 118 Q176 124 170 110 Z" fill="#b8975e" %s />'
        '<path d="M208 106 Q204 60 256 54 Q308 60 304 106 Q256 100 208 106 Z" fill="#c9a96e" %s />'
        '<path d="M208 92 Q256 86 304 92 L305 102 Q256 96 207 102 Z" fill="#7a5a3e" />'
    ) % (INK, INK),
    # Under the sea, a diving mask pushed up on the forehead, its snorkel.
    'mer': (
        '<path d="M192 112 Q256 96 320 112" fill="none" stroke="#293d4b" stroke-width="10" stroke-linecap="round" />'
        '<rect x="208" y="74" width="96" height="40" rx="16" fill="#ff8a3d" %s />'
        '<rect x="216" y="81" width="36" height="26" rx="10" fill="#c7ecf8" %s />'
        '<rect x="260" y="81" width="36" height="26" rx="10" fill="#c7ecf8" %s />'
        '<path d="M330 150 L330 70 Q330 56 344 56" fill="none" stroke="#293d4b" stroke-width="16" stroke-linecap="round" />'
        '<path d="M330 150 L330 70 Q330 56 344 56" fill="none" stroke="#ffd166" stroke-width="9" stroke-linecap="round" />'
    ) % (INK, THIN, THIN),
    # In space, a helmet: a clear bubble round the head, its collar.
    'espace': (
        '<circle cx="256" cy="140" r="96" fill="#d8ecff" fill-opacity=".28" %s />'
        '<path d="M196 76 Q222 56 252 54" fill="none" stroke="#ffffff" stroke-width="8" stroke-linecap="round" />'
        '<path d="M190 214 Q256 238 322 214 L318 230 Q256 252 194 230 Z" fill="#dfe3ea" %s />'
    ) % (INK, INK),
}


def main():
    for key, body in HATS.items():
        out = HERE / key / 'chapeau.svg'
        out.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">%s</svg>\n' % body,
                       encoding='utf-8')
        print('%-28s %6d' % (out.relative_to(HERE), out.stat().st_size))


if __name__ == '__main__':
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    main()
