#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Makes src/colours/spectra.rs: what the colour mixer of Color 1.1 needs to
mix colours as paint does (blue and yellow give green), with the
Kubelka–Munk theory of one constant.

  make_spectra.py [--verifier]

Seven reflectance curves, sampled from 380 to 730 nm every 10 nm, one for
each of white, cyan, magenta, yellow, red, green and blue: any colour of the
sRGB cube is a positive sum of them (white for what its three channels share,
then cyan, magenta or yellow, then red, green or blue), so that it has a
smooth curve of its own, which the mixer turns into absorption over
scattering, mixes, and turns back into a colour.

Each curve is the smoothest one, in the sense of Scott Allen Burns' method
« Least Hyperbolic Tangent Slope Squared » (Generating Reflectance Curves from
sRGB Triplets, 2015–2019), that has exactly its colour under the D65
illuminant for the CIE 1931 standard observer: a reflectance (tanh z + 1)/2
between 0 and 1, whose z changes as little as possible from one wavelength
to the next. The method is published, and its numbers are computed here,
from the CIE tables: nothing is copied from another mixer.

numpy and colour-science (pip install colour-science) are needed to make
the file only: the core carries the result. With --verifier, nothing is
written: the file made in memory must be byte for byte the one in src/.
"""
import sys
from pathlib import Path

import numpy as np
import colour

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'src' / 'colours' / 'spectra.rs'
WAVELENGTHS = np.arange(380, 740, 10)

# sRGB of the seven primaries, and the margin that keeps a reflectance of
# hyperbolic tangents strictly between 0 and 1.
PRIMARIES = [('W', (1, 1, 1)), ('C', (0, 1, 1)), ('M', (1, 0, 1)), ('Y', (1, 1, 0)),
             ('R', (1, 0, 0)), ('G', (0, 1, 0)), ('B', (0, 0, 1))]
EPSILON = 1e-4

# XYZ (D65) to linear sRGB, IEC 61966-2-1.
XYZ_TO_RGB = np.array([[3.2404542, -1.5371385, -0.4985314],
                       [-0.9692660, 1.8760108, 0.0415560],
                       [0.0556434, -0.2040259, 1.0572252]])


def observer():
    """Rows x, y, z of the colour matching functions weighted by D65, scaled
    so that a perfect white reflector has Y = 1."""
    cmfs = colour.MSDS_CMFS['CIE 1931 2 Degree Standard Observer'][WAVELENGTHS]
    d65 = colour.SDS_ILLUMINANTS['D65'][WAVELENGTHS]
    weighted = (cmfs * d65[:, None]).T
    return weighted / weighted[1].sum()


def lhtss(to_rgb, rgb, iterations=2000):
    """The reflectance of smoothest hyperbolic-tangent slope whose linear sRGB
    is rgb (Burns, Newton's method on the Lagrangian). The steps are damped,
    never moving z by more than one at a time: from z = 0, the saturated
    primaries would otherwise overshoot."""
    n = to_rgb.shape[1]
    d = np.diag(np.full(n, 4.0)) - np.diag(np.full(n - 1, 2.0), 1) - np.diag(np.full(n - 1, 2.0), -1)
    d[0, 0] = d[-1, -1] = 2.0
    z = np.zeros(n)
    lam = np.zeros(3)
    for _ in range(iterations):
        r0 = (np.tanh(z) + 1) / 2
        r1 = np.diag(1 / np.cosh(z) ** 2 / 2)
        r2 = np.diag(-(1 / np.cosh(z) ** 2) * np.tanh(z))
        f = np.concatenate([d @ z + r1 @ to_rgb.T @ lam, to_rgb @ r0 - rgb])
        j = np.block([[d + np.diag(r2 @ to_rgb.T @ lam), r1 @ to_rgb.T],
                      [to_rgb @ r1, np.zeros((3, 3))]])
        step = np.linalg.solve(j, -f)
        largest = np.max(np.abs(step[:n]))
        if largest > 1.0:
            step = step / largest
        z += step[:n]
        lam += step[n:]
        if np.max(np.abs(f)) < 1e-12:
            return (np.tanh(z) + 1) / 2
    raise SystemExit('LHTSS did not converge for %s' % (rgb,))


def literal(value):
    """The shortest decimal that gives this float64 back, as Rust reads it."""
    text = repr(float(value))
    return text if ('.' in text or 'e' in text) else text + '.0'


def make():
    xyz = observer()
    to_rgb = XYZ_TO_RGB @ xyz
    curves = []
    for name, rgb in PRIMARIES:
        if name == 'W':
            # White reflects everything: the flattest curve, constant. The
            # observer's white is not exactly (1, 1, 1), which a curve below 1
            # could not reach; this one gives 0.9991, 1.0002, 0.9992.
            curve = np.full(len(WAVELENGTHS), 1 - EPSILON)
        else:
            target = np.clip(np.array(rgb, dtype=float), EPSILON, 1 - EPSILON)
            curve = lhtss(to_rgb, target)
            assert np.allclose(to_rgb @ curve, target, atol=1e-9), name
        assert np.all((curve > 0) & (curve < 1)), name
        curves.append((name, curve))
    lines = [
        '// SPDX-License-Identifier: MIT',
        '// Made by tools/make_spectra.py from the CIE 1931 2-degree observer and the',
        '// D65 illuminant (colour-science); do not edit by hand.',
        '',
        '/// The wavelengths sampled, in nanometres: 380 to 730 every 10.',
        'pub(crate) const SAMPLES: usize = %d;' % len(WAVELENGTHS),
        '',
        '/// The reflectances of white, cyan, magenta, yellow, red, green and blue.',
        '#[rustfmt::skip]',
        'pub(crate) const PRIMARIES: [[f64; SAMPLES]; 7] = [',
    ]
    for name, curve in curves:
        lines.append('    // %s' % name)
        lines.append('    [')
        for start in range(0, len(curve), 4):
            lines.append('        ' + ' '.join(literal(v) + ',' for v in curve[start:start + 4]))
        lines.append('    ],')
    lines.append('];')
    lines.append('')
    lines.append('/// x, y and z of the observer under D65 at each wavelength; y sums to 1.')
    lines.append('#[rustfmt::skip]')
    lines.append('pub(crate) const OBSERVER: [[f64; SAMPLES]; 3] = [')
    for row in xyz:
        lines.append('    [')
        for start in range(0, len(row), 4):
            lines.append('        ' + ' '.join(literal(v) + ',' for v in row[start:start + 4]))
        lines.append('    ],')
    lines.append('];')
    lines.append('')
    lines.append('/// XYZ (D65) to linear sRGB.')
    lines.append('#[rustfmt::skip]')
    lines.append('pub(crate) const XYZ_TO_RGB: [[f64; 3]; 3] = [')
    for row in XYZ_TO_RGB:
        lines.append('    [' + ', '.join(literal(v) for v in row) + '],')
    lines.append('];')
    return '\n'.join(lines) + '\n'


def main():
    text = make()
    if sys.argv[1:] == ['--verifier']:
        if TARGET.read_text() != text:
            raise SystemExit('%s does not match tools/make_spectra.py' % TARGET)
        print('%s matches.' % TARGET)
        return
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(text)
    print('%s written.' % TARGET)


if __name__ == '__main__':
    main()
