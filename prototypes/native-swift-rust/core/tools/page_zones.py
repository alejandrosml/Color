#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Where to pour on a colouring page: for each closed, filled element of its
SVG file, the point of what shows of it that lies farthest from its lines —
under the elements drawn after it — with the comment that names its group,
how far the nearest line is and how many units of the sheet show.

  page_zones.py art/coloriages/dinosaure.svg

The pictures of the App Store colour a page this way
(flutter-rust/test/store_pictures_test.dart, _pours): after a page is drawn
again, its points are found again here.

Needs rsvg-convert, and Python with numpy, scipy and Pillow: a tool of the
work, which no recipe runs.
"""
import pathlib
import re
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image
from scipy import ndimage

SHAPE = r'<(?:path|circle|ellipse|rect|polygon|polyline)\b[^>]*/>'


def mask(head, element, line):
    """Where [element] paints, a pixel per unit: its inside, and its line
    too when [line] is true."""
    drawn = re.sub(r'fill="(?!none)[^"]*"', 'fill="#000"', element)
    drawn = re.sub(r'stroke="[^"]*"', 'stroke="#000"' if line else 'stroke="none"', drawn)
    with tempfile.TemporaryDirectory() as folder:
        source = pathlib.Path(folder, 'shape.svg')
        picture = pathlib.Path(folder, 'shape.png')
        source.write_text(f'{head}<rect width="100%" height="100%" fill="#fff"/>{drawn}</svg>',
                          encoding='utf-8')
        subprocess.run(['rsvg-convert', str(source), '-o', str(picture)], check=True)
        return np.array(Image.open(picture).convert('L')) < 128


def main(path):
    svg = pathlib.Path(path).read_text(encoding='utf-8')
    head = re.search(r'<svg[^>]*>', svg).group(0)
    group, shapes = '', []
    for comment, element in re.findall(rf'<!--(.*?)-->|({SHAPE})', svg, flags=re.S):
        if comment:
            group = ' '.join(comment.split())
        else:
            shapes.append((group, element))
    covers = [mask(head, element, line=True) for _, element in shapes]
    for index, (group, element) in enumerate(shapes):
        if 'fill="#ffffff"' not in element:
            continue
        inside = mask(head, element, line=False)
        seen = inside.copy()
        for later in covers[index + 1:]:
            seen &= ~later
        # Its own line takes half of its width inside.
        seen &= ~(covers[index] & ~ndimage.binary_erosion(inside, iterations=4))
        if not seen.any():
            print(f'{group:44.44s} hidden')
            continue
        reach = ndimage.distance_transform_edt(seen)
        y, x = np.unravel_index(reach.argmax(), reach.shape)
        print(f'{group:44.44s} ({x}, {y})  reach {reach.max():.0f}  shows {int(seen.sum())}')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
