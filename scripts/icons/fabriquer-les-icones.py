#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Draws every icon of Color from its logo, the study n° 8 « De face » that
the owner chose on 7 October 2026: the little character on his power
wheelchair, seen from the front, lifting his pencil.

    fabriquer-les-icones.py COLOR_FOLDER

COLOR_FOLDER is the Color folder of the project. Reads
prototypes/art/logo/color-logo-serre.svg (the tight crop, for icons) and
writes, replacing them:

  prototypes/flutter-rust/macos/Runner/Assets.xcassets/AppIcon.appiconset/
      app_icon_16.png … app_icon_1024.png — the rounded tile of macOS, on
      Apple's grid: a body of 824 points on 1024, with its shadow;
  prototypes/flutter-rust/windows/runner/resources/app_icon.ico — seven
      sizes, from 16 to 256 pixels, each drawn at its size;
  prototypes/flutter-rust/linux/packaging/icons/color-16.png … color-512.png
      — the tile with a narrow margin, as desktop themes draw them;
  prototypes/flutter-rust/ios/Runner/Assets.xcassets/AppIcon.appiconset/
      app_icon_1024.png — the whole square, opaque: iOS rounds it itself;
  prototypes/flutter-rust/android/app/src/main/res/mipmap-*/ — the tile for
      the older launchers, and the two layers of the adaptive icon of
      Android: the character alone, and the yellow behind it;
  docs/publication/icone-google-play-512.png, icone-app-store-1024.png and
      image-google-play-1024x500.png — the pictures of the stores.

Needs rsvg-convert (librsvg) to turn the drawings into pixels. Writes
nothing else; the SVG of each tile is printed on demand with --svg.
"""
import math
import re
import struct
import subprocess
import sys
from pathlib import Path

TOP, BOTTOM = '#fff3cf', '#ffdf96'   # the tile: the yellow of the logo's sun, a little deeper below
EDGE = '#e9c46f'                       # a thin line round the tile, for light backgrounds


def squircle(x, y, w, h, n=5.0, steps=240):
    """A superellipse: the rounded square of application icons."""
    cx, cy, a, b = x + w / 2, y + h / 2, w / 2, h / 2
    points = []
    for k in range(steps):
        t = 2 * math.pi * k / steps
        ct, st = math.cos(t), math.sin(t)
        px = cx + a * (abs(ct) ** (2 / n)) * (1 if ct >= 0 else -1)
        py = cy + b * (abs(st) ** (2 / n)) * (1 if st >= 0 else -1)
        points.append(f'{px:.1f} {py:.1f}')
    return 'M' + ' L'.join(points) + ' Z'


def character(logo):
    """The drawing of the tight crop without its sun, and its viewBox."""
    text = logo.read_text()
    box = [float(v) for v in re.search(r'viewBox="([^"]+)"', text).group(1).split()]
    inner = text[text.index('>', text.index('<svg')) + 1:text.rindex('</svg>')]
    inner = re.sub(r'<title>.*?</title>|<desc>.*?</desc>', '', inner, flags=re.S)
    sun = re.search(r'<circle cx="256" cy="226" r="210" fill="#ffe9ad"/>', inner)
    if not sun:
        sys.exit('The sun of the logo was not found: has the logo changed?')
    return inner.replace(sun.group(0), '', 1), box


def tile(logo, body, shadow):
    """The icon on a canvas of 1024: a tile of `body` (x, y, side) holding
    the character, padded so that the pencil and the wheels breathe."""
    drawing, (bx, by, bw, bh) = character(logo)
    x, y, side = body
    inner = side * 0.80
    scale = inner / max(bw, bh)
    tx = x + (side - bw * scale) / 2 - bx * scale
    ty = y + (side - bh * scale) / 2 - by * scale + side * 0.015
    path = squircle(x, y, side, side)
    defs = (f'<linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{TOP}"/><stop offset="1" stop-color="{BOTTOM}"/></linearGradient>')
    shade = ''
    if shadow:
        defs += ('<filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">'
                 '<feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dy="12"/>'
                 '<feComponentTransfer><feFuncA type="linear" slope="0.30"/></feComponentTransfer>'
                 '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
        shade = ' filter="url(#shadow)"'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{defs}</defs>'
            f'<path d="{path}" fill="url(#tile)" stroke="{EDGE}" stroke-width="4"{shade}/>'
            f'<g transform="translate({tx:.2f} {ty:.2f}) scale({scale:.5f})">{drawing}</g></svg>')


def square(logo, fill, ratio):
    """The character on a square of 1024, centred, `ratio` of the side tall;
    behind it the yellow of the tile, or nothing (`fill` False)."""
    drawing, (bx, by, bw, bh) = character(logo)
    inner = 1024 * ratio
    scale = inner / max(bw, bh)
    tx = (1024 - bw * scale) / 2 - bx * scale
    ty = (1024 - bh * scale) / 2 - by * scale + 1024 * 0.012
    defs = (f'<linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{TOP}"/><stop offset="1" stop-color="{BOTTOM}"/></linearGradient>')
    back = '<rect width="1024" height="1024" fill="url(#tile)"/>' if fill else ''
    figure = '' if fill == 'only' else f'<g transform="translate({tx:.2f} {ty:.2f}) scale({scale:.5f})">{drawing}</g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{defs}</defs>{back}{figure}</svg>')


def banner(logo):
    """The feature graphic of Google Play, 1024 × 500: the character on the
    left, the name and one line on the right, on the yellow of the tile."""
    drawing, (bx, by, bw, bh) = character(logo)
    inner = 420
    scale = inner / max(bw, bh)
    tx = 70 + (inner - bw * scale) / 2 - bx * scale
    ty = (500 - bh * scale) / 2 - by * scale
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">'
            f'<defs><linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{TOP}"/><stop offset="1" stop-color="{BOTTOM}"/></linearGradient></defs>'
            '<rect width="1024" height="500" fill="url(#tile)"/>'
            f'<g transform="translate({tx:.2f} {ty:.2f}) scale({scale:.5f})">{drawing}</g>'
            '<text x="560" y="235" font-family="DejaVu Sans, Helvetica, sans-serif" font-size="112" '
            'font-weight="bold" fill="#293d4b">Color</text>'
            '<text x="563" y="300" font-family="DejaVu Sans, Helvetica, sans-serif" font-size="34" '
            'fill="#293d4b">un atelier de dessin</text>'
            '<text x="563" y="345" font-family="DejaVu Sans, Helvetica, sans-serif" font-size="34" '
            'fill="#293d4b">pour les enfants</text></svg>')


def opaque(data):
    """The PNG without its alpha channel, which the App Store refuses."""
    from io import BytesIO
    from PIL import Image
    image = Image.open(BytesIO(data)).convert('RGB')
    out = BytesIO()
    image.save(out, format='PNG', optimize=True)
    return out.getvalue()


def png(svg, size):
    return subprocess.run(['rsvg-convert', '-w', str(size), '-h', str(size), '-f', 'png'],
                          input=svg.encode(), check=True, capture_output=True).stdout


def ico(images):
    """An .ico file whose every image is a PNG: Windows reads these since
    Vista, and each size keeps the drawing made for it."""
    header = struct.pack('<HHH', 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries, blobs = b'', b''
    for size, data in images:
        side = 0 if size >= 256 else size
        entries += struct.pack('<BBBBHHII', side, side, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    return header + entries + blobs


def main():
    color = Path(sys.argv[1]).resolve()
    logo = color / 'prototypes/art/logo/color-logo-serre.svg'
    app = color / 'prototypes/flutter-rust'
    mac = tile(logo, (100, 100, 824), shadow=True)
    flat = tile(logo, (41, 41, 942), shadow=False)
    if '--svg' in sys.argv:
        print(mac if '--mac' in sys.argv else flat)
        return
    icons = app / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        (icons / f'app_icon_{size}.png').write_bytes(png(mac, size))
    linux = app / 'linux/packaging/icons'
    for size in [16, 32, 48, 64, 128, 256, 512]:
        (linux / f'color-{size}.png').write_bytes(png(flat, size))
    windows = app / 'windows/runner/resources/app_icon.ico'
    windows.write_bytes(ico([(size, png(flat, size)) for size in [16, 24, 32, 48, 64, 128, 256]]))
    # iOS and iPadOS: one image of 1024, opaque, the system makes the others.
    ios = app / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for old in ios.glob('*.png'):
        old.unlink()
    (ios / 'app_icon_1024.png').write_bytes(opaque(png(square(logo, True, 0.80), 1024)))
    (ios / 'Contents.json').write_text(
        '{\n  "images" : [\n    {\n      "filename" : "app_icon_1024.png",\n'
        '      "idiom" : "universal",\n      "platform" : "ios",\n'
        '      "size" : "1024x1024"\n    }\n  ],\n'
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
    # Android: the tile for older launchers; the adaptive icon in two layers,
    # the character within the circle every launcher keeps (66 of 108 dp).
    res = app / 'android/app/src/main/res'
    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    front = square(logo, False, 0.56)
    behind = square(logo, 'only', 0)
    for name, factor in densities.items():
        folder = res / f'mipmap-{name}'
        folder.mkdir(exist_ok=True)
        (folder / 'ic_launcher.png').write_bytes(png(flat, round(48 * factor)))
        (folder / 'ic_launcher_foreground.png').write_bytes(png(front, round(108 * factor)))
        (folder / 'ic_launcher_background.png').write_bytes(opaque(png(behind, round(108 * factor))))
    adaptive = res / 'mipmap-anydpi-v26'
    adaptive.mkdir(exist_ok=True)
    (adaptive / 'ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n')
    store = color / 'docs/publication'
    store.mkdir(parents=True, exist_ok=True)
    (store / 'icone-google-play-512.png').write_bytes(opaque(png(square(logo, True, 0.80), 512)))
    (store / 'icone-app-store-1024.png').write_bytes(opaque(png(square(logo, True, 0.80), 1024)))
    picture = subprocess.run(['rsvg-convert', '-w', '1024', '-h', '500', '-f', 'png'],
                             input=banner(logo).encode(), check=True, capture_output=True).stdout
    (store / 'image-google-play-1024x500.png').write_bytes(opaque(picture))
    print('macOS: 7 images; Linux: 7 images; Windows: 1 icon of 7 sizes; '
          'iOS: 1 image; Android: 3 images in 5 densities and the adaptive icon; '
          'stores: 2 images')


if __name__ == '__main__':
    main()
