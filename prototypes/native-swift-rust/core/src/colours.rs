// SPDX-License-Identifier: MIT
//! Colours of Color 1.1: the mixer, which mixes as paint does (blue and
//! yellow give green), and the gradients, whose colours pass through the
//! Oklab space so that the middle of a gradient is never grey.
//!
//! The mixer follows the Kubelka–Munk theory of one constant: every colour
//! becomes a reflectance curve (a positive sum of the seven curves of
//! colours/spectra.rs, see tools/make_spectra.py), its absorption over
//! scattering K/S = (1 − R)² / 2R is averaged by the concentrations of the
//! two paints, each weighted by its luminance as a paint's tinting strength
//! follows its lightness, and the result turns back into a reflectance, then
//! into a colour under D65. The colour is then clamped into sRGB. Nothing is
//! interpolated along a curve of the RGB cube.
//!
//! Oklab: Björn Ottosson, « A perceptual color space for image processing »
//! (2020), the default interpolation space of CSS Color 4.

use super::*;

mod spectra;
use spectra::{OBSERVER, PRIMARIES, SAMPLES, XYZ_TO_RGB};

fn linear(channel: u32) -> f64 {
    let c = f64::from(channel) / 255.0;
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

fn encoded(linear: f64) -> u32 {
    let c = linear.clamp(0.0, 1.0);
    let c = if c <= 0.003_130_8 {
        12.92 * c
    } else {
        1.055 * c.powf(1.0 / 2.4) - 0.055
    };
    (c * 255.0).round() as u32
}

fn channels(rgb: u32) -> [f64; 3] {
    [
        linear((rgb >> 16) & 0xff),
        linear((rgb >> 8) & 0xff),
        linear(rgb & 0xff),
    ]
}

fn packed(rgb: [f64; 3]) -> u32 {
    (encoded(rgb[0]) << 16) | (encoded(rgb[1]) << 8) | encoded(rgb[2])
}

/// The reflectance curve of a colour: white for what its channels share,
/// then cyan, magenta or yellow, then red, green or blue.
fn reflectance(rgb: u32) -> [f64; SAMPLES] {
    let [mut r, mut g, mut b] = channels(rgb);
    let white = r.min(g).min(b);
    r -= white;
    g -= white;
    b -= white;
    let cyan = g.min(b);
    let magenta = r.min(b);
    let yellow = r.min(g);
    let red = (r - b).min(r - g).max(0.0);
    let green = (g - b).min(g - r).max(0.0);
    let blue = (b - g).min(b - r).max(0.0);
    let weights = [white, cyan, magenta, yellow, red, green, blue];
    let mut curve = [0.0; SAMPLES];
    for (weight, primary) in weights.iter().zip(PRIMARIES.iter()) {
        for (value, sample) in curve.iter_mut().zip(primary) {
            *value += weight * sample;
        }
    }
    curve.map(|value| value.clamp(1e-4, 1.0))
}

fn luminance(curve: &[f64; SAMPLES]) -> f64 {
    curve
        .iter()
        .zip(OBSERVER[1].iter())
        .map(|(r, y)| r * y)
        .sum::<f64>()
        .max(1e-4)
}

/// The colour of a reflectance curve under D65, in linear sRGB.
fn colour_of(curve: &[f64; SAMPLES]) -> [f64; 3] {
    let xyz = OBSERVER.map(|row| row.iter().zip(curve).map(|(o, r)| o * r).sum::<f64>());
    XYZ_TO_RGB.map(|row| row[0] * xyz[0] + row[1] * xyz[1] + row[2] * xyz[2])
}

/// `a` and `b` mixed as paint: `amount` 0 is all of `a`, 1 all of `b`.
pub(crate) fn mix_paint(a: u32, b: u32, amount: f64) -> u32 {
    if amount <= 0.0 {
        return a;
    }
    if amount >= 1.0 {
        return b;
    }
    let (ra, rb) = (reflectance(a), reflectance(b));
    let ks = |r: f64| (1.0 - r) * (1.0 - r) / (2.0 * r);
    let ca = (1.0 - amount) * (1.0 - amount) * luminance(&ra);
    let cb = amount * amount * luminance(&rb);
    let mut mixed = [0.0; SAMPLES];
    for (index, value) in mixed.iter_mut().enumerate() {
        let k = (ks(ra[index]) * ca + ks(rb[index]) * cb) / (ca + cb);
        *value = 1.0 + k - (k * k + 2.0 * k).sqrt();
    }
    packed(colour_of(&mixed))
}

fn oklab(rgb: u32) -> [f64; 3] {
    let [r, g, b] = channels(rgb);
    let l = (0.412_221_470_8 * r + 0.536_332_536_3 * g + 0.051_445_992_9 * b).cbrt();
    let m = (0.211_903_498_2 * r + 0.680_699_545_1 * g + 0.107_396_956_6 * b).cbrt();
    let s = (0.088_302_461_9 * r + 0.281_718_837_6 * g + 0.629_978_700_5 * b).cbrt();
    [
        0.210_454_255_3 * l + 0.793_617_785_0 * m - 0.004_072_046_8 * s,
        1.977_998_495_1 * l - 2.428_592_205_0 * m + 0.450_593_709_9 * s,
        0.025_904_037_1 * l + 0.782_771_766_2 * m - 0.808_675_766_0 * s,
    ]
}

fn from_oklab([lightness, a, b]: [f64; 3]) -> u32 {
    let l = lightness + 0.396_337_777_4 * a + 0.215_803_757_3 * b;
    let m = lightness - 0.105_561_345_8 * a - 0.063_854_172_8 * b;
    let s = lightness - 0.089_484_177_5 * a - 1.291_485_548_0 * b;
    let (l, m, s) = (l * l * l, m * m * m, s * s * s);
    packed([
        4.076_741_662_1 * l - 3.307_711_591_3 * m + 0.230_969_929_2 * s,
        -1.268_438_004_6 * l + 2.609_757_401_1 * m - 0.341_319_396_5 * s,
        -0.004_196_086_3 * l - 0.703_418_614_7 * m + 1.707_614_701_0 * s,
    ])
}

/// The colour at `t` (0 to 1) of a gradient from `a` to `b`, through Oklab.
pub(crate) fn gradient_colour(a: u32, b: u32, t: f64) -> u32 {
    if t <= 0.0 {
        return a;
    }
    if t >= 1.0 {
        return b;
    }
    let (from, to) = (oklab(a), oklab(b));
    from_oklab([0, 1, 2].map(|axis| from[axis] + (to[axis] - from[axis]) * t))
}

/// How many colours a gradient gives the screen and the SVG export: enough
/// that its steps in sRGB stay close to its course through Oklab.
pub(crate) const GRADIENT_STOPS: usize = 9;

// ---------------------------------------------------------------- C contract

/// `a` and `b` (0x00RRGGBB) mixed as paint, `amount` 0 being all of `a` and 1
/// all of `b`; a NaN amount, or colours beyond 24 bits, give `a`.
#[no_mangle]
pub extern "C" fn ep_mix_colours(a: u32, b: u32, amount: f32) -> u32 {
    if a > 0x00ff_ffff || b > 0x00ff_ffff || !amount.is_finite() {
        return a & 0x00ff_ffff;
    }
    mix_paint(a, b, f64::from(amount))
}

/// Writes `count` (2 to 64) colours evenly spaced along a gradient from `a`
/// to `b` through Oklab, `a` first and `b` last. Returns 0, or -1 for colours
/// beyond 24 bits, a count outside 2..64 or a NULL output.
///
/// # Safety
/// Non-null `out_colours` must be writable for `count` values and aligned.
#[no_mangle]
pub unsafe extern "C" fn ep_gradient_colours(
    a: u32,
    b: u32,
    count: u32,
    out_colours: *mut u32,
) -> i32 {
    if a > 0x00ff_ffff || b > 0x00ff_ffff || !(2..=64).contains(&count) || out_colours.is_null() {
        return INVALID;
    }
    let colours = unsafe { slice::from_raw_parts_mut(out_colours, count as usize) };
    for (index, colour) in colours.iter_mut().enumerate() {
        *colour = gradient_colour(a, b, index as f64 / f64::from(count - 1));
    }
    0
}

#[cfg(test)]
mod tests;
