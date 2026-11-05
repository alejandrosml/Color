// SPDX-License-Identifier: MIT
use super::*;

fn rgb(r: u32, g: u32, b: u32) -> u32 {
    (r << 16) | (g << 8) | b
}

#[test]
fn blue_and_yellow_give_green_as_the_reference_of_the_tool_computes() {
    // The colours tools/make_spectra.py's reference mixer gave on 2 November.
    let blue = rgb(0, 0, 255);
    let yellow = rgb(255, 255, 0);
    assert_eq!(ep_mix_colours(blue, yellow, 0.0), blue);
    assert_eq!(ep_mix_colours(blue, yellow, 0.25), rgb(0, 91, 98));
    assert_eq!(ep_mix_colours(blue, yellow, 0.5), rgb(57, 143, 84));
    assert_eq!(ep_mix_colours(blue, yellow, 0.75), rgb(167, 204, 65));
    assert_eq!(ep_mix_colours(blue, yellow, 1.0), yellow);
    assert_eq!(
        ep_mix_colours(rgb(255, 0, 0), yellow, 0.5),
        rgb(255, 68, 15)
    );
    assert_eq!(ep_mix_colours(rgb(255, 0, 0), blue, 0.5), rgb(74, 24, 43));
    assert_eq!(
        ep_mix_colours(0, rgb(255, 255, 255), 0.5),
        rgb(166, 166, 166)
    );
    // Green wins in the middle of blue and yellow: paint, not light.
    let middle = ep_mix_colours(blue, yellow, 0.5);
    assert!((middle >> 8) & 0xff > (middle >> 16) & 0xff && (middle >> 8) & 0xff > middle & 0xff);
}

#[test]
fn a_colour_mixed_with_itself_stays_itself_within_a_step() {
    for colour in [
        rgb(255, 255, 255),
        rgb(12, 200, 99),
        rgb(250, 120, 0),
        rgb(40, 40, 160),
    ] {
        let mixed = ep_mix_colours(colour, colour, 0.5);
        for shift in [0, 8, 16] {
            let (a, b) = ((colour >> shift) & 0xff, (mixed >> shift) & 0xff);
            assert!(a.abs_diff(b) <= 2, "{colour:06x} -> {mixed:06x}");
        }
    }
}

#[test]
fn odd_requests_give_the_first_colour() {
    assert_eq!(ep_mix_colours(0x0012_3456, 0x0100_0000, 0.5), 0x0012_3456);
    assert_eq!(ep_mix_colours(0x0012_3456, 0, f32::NAN), 0x0012_3456);
}

#[test]
fn a_gradient_goes_through_oklab_and_keeps_its_ends() {
    let mut colours = [0u32; 9];
    let (red, blue) = (rgb(255, 0, 0), rgb(0, 0, 255));
    assert_eq!(
        unsafe { ep_gradient_colours(red, blue, 9, colours.as_mut_ptr()) },
        0
    );
    assert_eq!(colours[0], red);
    assert_eq!(colours[8], blue);
    // Its middle is the purple of CSS's color-mix in oklab, lighter than the
    // #800080 of a mix of sRGB numbers.
    assert_eq!(colours[4], rgb(140, 83, 162));
    // From blue to yellow, a mix of sRGB numbers passes through grey; Oklab
    // keeps a colour.
    assert_eq!(
        unsafe { ep_gradient_colours(blue, rgb(255, 255, 0), 9, colours.as_mut_ptr()) },
        0
    );
    let middle = colours[4];
    let channel = |shift: u32| (middle >> shift) & 0xff;
    let (high, low) = (
        channel(16).max(channel(8)).max(channel(0)),
        channel(16).min(channel(8)).min(channel(0)),
    );
    assert!(high - low > 40, "{middle:06x}");
    // One colour gives one colour all along.
    let mut same = [0u32; 5];
    assert_eq!(
        unsafe { ep_gradient_colours(0x0055_aa33, 0x0055_aa33, 5, same.as_mut_ptr()) },
        0
    );
    assert!(same.iter().all(|&c| c == 0x0055_aa33));
    for count in [0, 1, 65] {
        assert_eq!(
            unsafe { ep_gradient_colours(red, blue, count, colours.as_mut_ptr()) },
            INVALID
        );
    }
    assert_eq!(
        unsafe { ep_gradient_colours(red, blue, 9, ptr::null_mut()) },
        INVALID
    );
}

#[test]
fn the_curves_are_those_the_tool_makes() {
    // tools/make_spectra.py --verifier compares them byte for byte; here, what
    // they must be: strictly between 0 and 1, white flat.
    for primary in PRIMARIES {
        assert!(primary.iter().all(|&r| r > 0.0 && r < 1.0));
    }
    assert!(PRIMARIES[0].iter().all(|&r| r == PRIMARIES[0][0]));
    let white = colour_of(&PRIMARIES[0]);
    assert_eq!(packed(white), rgb(255, 255, 255));
}
