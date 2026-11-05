// SPDX-License-Identifier: MIT
//! The zone of the paint pot: closed by the child's own lines, small gaps
//! plugged, wide ones not, holes kept.

use super::*;

struct Mask {
    width: usize,
    height: usize,
    bytes: Vec<u8>,
}

impl Mask {
    fn new(width: usize, height: usize) -> Self {
        Self {
            width,
            height,
            bytes: vec![0; width * height],
        }
    }

    fn ink(&mut self, x0: usize, y0: usize, x1: usize, y1: usize) {
        for y in y0..=y1 {
            for x in x0..=x1 {
                self.bytes[y * self.width + x] = 255;
            }
        }
    }

    /// The outline of a square, `thick` pixels thick, with an opening of
    /// `gap` pixels in the middle of its right side.
    fn square(&mut self, x0: usize, y0: usize, size: usize, thick: usize, gap: usize) {
        let x1 = x0 + size;
        let y1 = y0 + size;
        self.ink(x0, y0, x1, y0 + thick - 1);
        self.ink(x0, y1 - thick + 1, x1, y1);
        self.ink(x0, y0, x0 + thick - 1, y1);
        let middle = (y0 + y1) / 2;
        if gap == 0 {
            self.ink(x1 - thick + 1, y0, x1, y1);
        } else {
            self.ink(x1 - thick + 1, y0, x1, middle - gap / 2 - 1);
            self.ink(x1 - thick + 1, middle - gap / 2 + gap, x1, y1);
        }
    }

    fn zone(&self, x: u32, y: u32, radius: u32) -> Zone {
        zone(
            &self.bytes,
            self.width as u32,
            self.height as u32,
            x,
            y,
            radius,
        )
        .unwrap()
    }
}

/// The pixels inside rings by the even-odd rule, at pixel centres.
fn covered(rings: &[Vec<EpPoint>], width: usize, height: usize) -> Vec<bool> {
    let mut inside = vec![false; width * height];
    for y in 0..height {
        for x in 0..width {
            let (px, py) = (x as f32 + 0.5, y as f32 + 0.5);
            let mut crossings = 0;
            for ring in rings {
                for i in 0..ring.len() {
                    let (a, b) = (ring[i], ring[(i + 1) % ring.len()]);
                    if (a.y > py) != (b.y > py) {
                        let t = (py - a.y) / (b.y - a.y);
                        if px < a.x + t * (b.x - a.x) {
                            crossings += 1;
                        }
                    }
                }
            }
            inside[y * width + x] = crossings % 2 == 1;
        }
    }
    inside
}

/// Whether the centre of pixel (x, y) is inside the rings, even-odd.
fn contains(rings: &[Vec<EpPoint>], x: usize, y: usize) -> bool {
    let (px, py) = (x as f32 + 0.5, y as f32 + 0.5);
    let mut crossings = 0;
    for ring in rings {
        for i in 0..ring.len() {
            let (a, b) = (ring[i], ring[(i + 1) % ring.len()]);
            if (a.y > py) != (b.y > py) && px < a.x + (py - a.y) / (b.y - a.y) * (b.x - a.x) {
                crossings += 1;
            }
        }
    }
    crossings % 2 == 1
}

fn rings_of(zone: Zone) -> Vec<Vec<EpPoint>> {
    match zone {
        Zone::Rings(rings) => rings,
        Zone::OnInk => panic!("on ink"),
        Zone::WholeSheet => panic!("whole sheet"),
    }
}

#[test]
#[cfg_attr(
    miri,
    ignore = "tens of thousands of pixels, one by one: too long under Miri"
)]
fn a_closed_square_is_filled_inside_and_tucked_under_its_line() {
    let mut mask = Mask::new(200, 160);
    mask.square(40, 30, 80, 3, 0);
    let rings = rings_of(mask.zone(80, 70, 4));
    assert_eq!(rings.len(), 1);
    let inside = covered(&rings, 200, 160);
    // The whole inside, and a pixel under the line, nothing beyond it.
    for y in 33..=107 {
        for x in 43..=117 {
            assert!(inside[y * 200 + x], "({x}, {y})");
        }
    }
    for (index, &inside) in inside.iter().enumerate() {
        let (x, y) = (index % 200, index / 200);
        if inside {
            assert!(
                (41..=119).contains(&x) && (31..=109).contains(&y),
                "({x}, {y})"
            );
        }
    }
    // Outside, the zone is the rest of the sheet, the square's inside a hole
    // in it: as a pot of paint would leave it.
    let outside = rings_of(mask.zone(5, 5, 4));
    assert_eq!(outside.len(), 2);
    let painted = covered(&outside, 200, 160);
    assert!(painted[5 * 200 + 5]);
    assert!(!painted[70 * 200 + 80]);
    assert!(matches!(mask.zone(40, 30, 4), Zone::OnInk));
    // A sheet whose lines close nothing: its own colour changes instead.
    let mut open = Mask::new(200, 160);
    open.ink(20, 50, 180, 52);
    assert!(matches!(open.zone(5, 5, 4), Zone::WholeSheet));
    assert!(matches!(open.zone(5, 5, 0), Zone::WholeSheet));
    // However small what a line closes, it keeps its own colour.
    open.square(150, 100, 6, 1, 0);
    let rings = rings_of(open.zone(5, 5, 2));
    assert_eq!(
        rings.len(),
        3,
        "the sheet, the middle of the line, the little square's inside"
    );
    assert!(contains(&rings, 5, 5));
    assert!(!contains(&rings, 153, 103));
}

#[test]
fn the_outline_runs_on_the_edges_of_the_pixels() {
    let mut mask = Mask::new(20, 20);
    // Ink one pixel thick round the pixels 3 to 16.
    mask.square(2, 2, 15, 1, 0);
    for radius in [0, 1] {
        let rings = rings_of(mask.zone(10, 10, radius));
        assert_eq!(rings.len(), 1);
        let xs = rings[0].iter().map(|p| p.x);
        let ys = rings[0].iter().map(|p| p.y);
        // The inside and the pixel under the line: from the left edge of
        // pixel 2 to the right edge of pixel 17.
        assert_eq!(xs.clone().fold(f32::MAX, f32::min), 2.0);
        assert_eq!(xs.fold(f32::MIN, f32::max), 18.0);
        assert_eq!(ys.clone().fold(f32::MAX, f32::min), 2.0);
        assert_eq!(ys.fold(f32::MIN, f32::max), 18.0);
    }
}

#[test]
#[cfg_attr(
    miri,
    ignore = "tens of thousands of pixels, one by one: too long under Miri"
)]
fn wherever_a_gap_is_touched_one_side_is_filled_and_the_point_with_it() {
    let mut mask = Mask::new(220, 160);
    mask.square(40, 30, 80, 3, 5);
    let mut sides = [0, 0];
    for y in 64..=76 {
        for x in 110..=128 {
            if mask.bytes[y * 220 + x] != 0 {
                continue;
            }
            let rings = rings_of(mask.zone(x as u32, y as u32, 4));
            assert!(contains(&rings, x, y), "({x}, {y})");
            let (inner, outer) = (contains(&rings, 80, 70), contains(&rings, 180, 70));
            assert!(inner != outer, "({x}, {y}): one side, never both");
            sides[usize::from(outer)] += 1;
        }
    }
    assert!(sides[0] > 0 && sides[1] > 0);
}

#[test]
#[cfg_attr(
    miri,
    ignore = "tens of thousands of pixels, one by one: too long under Miri"
)]
fn a_room_does_not_spill_through_its_plugged_door_into_a_narrow_corridor() {
    let mut mask = Mask::new(240, 160);
    // A room with a door of 4 pixels in its right wall, opening on a
    // corridor 11 pixels high that leads to the open sheet.
    mask.square(40, 40, 60, 2, 4);
    mask.ink(101, 64, 200, 64);
    mask.ink(101, 76, 200, 76);
    let room = rings_of(mask.zone(70, 70, 8));
    assert!(contains(&room, 70, 70));
    assert!(!contains(&room, 150, 70), "not the corridor");
    assert!(!contains(&room, 230, 150), "nor the rest of the sheet");
    // Touched in the corridor, where no disc of 8 fits: the corridor goes
    // with the open sheet, where its widest way leads, not with the room.
    let corridor = rings_of(mask.zone(150, 70, 8));
    assert!(contains(&corridor, 150, 70));
    assert!(contains(&corridor, 230, 150));
    assert!(!contains(&corridor, 70, 70));
}

#[test]
#[cfg_attr(
    miri,
    ignore = "tens of thousands of pixels, one by one: too long under Miri"
)]
fn the_narrow_pixels_are_those_a_stamped_disc_would_give() {
    // Ink here and there, every radius: the distance of the parabolas gives
    // the very pixels within the radius of an ink pixel or of the edge.
    let (w, h) = (47usize, 31usize);
    let mut state = 0x2545_f491u32;
    let mut cells = vec![0u8; w * h];
    for cell in &mut cells {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        if state.is_multiple_of(37) {
            *cell = INK;
        }
    }
    for radius in [1usize, 2, 3, 5, 8, 13] {
        let mut grid = Grid {
            width: w,
            height: h,
            cells: cells.clone(),
        };
        let clearance = mark_narrow(&mut grid, radius).unwrap();
        for y in 0..h {
            for x in 0..w {
                // The ink, and the edge of the sheet a pixel beyond each side.
                let edge = (x + 1).min(w - x).min(y + 1).min(h - y).pow(2);
                let nearest = (0..h)
                    .flat_map(|iy| (0..w).map(move |ix| (ix, iy)))
                    .filter(|&(ix, iy)| cells[iy * w + ix] == INK)
                    .map(|(ix, iy)| x.abs_diff(ix).pow(2) + y.abs_diff(iy).pow(2))
                    .fold(edge, usize::min);
                let near = nearest <= radius * radius;
                assert_eq!(
                    grid.cells[y * w + x] & NARROW != 0,
                    near,
                    "radius {radius} at ({x}, {y})"
                );
                let expected = if near {
                    (nearest as f64).sqrt().floor() as u8
                } else {
                    WIDE
                };
                assert_eq!(
                    clearance[y * w + x],
                    expected,
                    "radius {radius} at ({x}, {y})"
                );
            }
        }
    }
}

#[test]
#[cfg_attr(
    miri,
    ignore = "tens of thousands of pixels, one by one: too long under Miri"
)]
fn a_gap_narrower_than_the_disc_is_plugged_and_a_wider_one_is_not() {
    let mut mask = Mask::new(220, 160);
    mask.square(40, 30, 80, 3, 5);
    // Radius 4: a disc of 9 pixels does not pass an opening of 5.
    let rings = rings_of(mask.zone(80, 70, 4));
    let inside = covered(&rings, 220, 160);
    let outside = (0..inside.len())
        .filter(|&i| inside[i])
        .filter(|&i| i % 220 > 125)
        .count();
    assert_eq!(outside, 0, "the fill stays in the square");
    // The plug: the opening itself is filled up to its middle at most.
    assert!(inside[70 * 220 + 118]);
    // Without a disc the fill goes out through the gap: the whole sheet.
    assert!(matches!(mask.zone(80, 70, 0), Zone::WholeSheet));
    // An opening wider than the disc is not closed.
    let mut wide = Mask::new(220, 160);
    wide.square(40, 30, 80, 3, 20);
    assert!(matches!(wide.zone(80, 70, 4), Zone::WholeSheet));
}

#[test]
#[cfg_attr(
    miri,
    ignore = "tens of thousands of pixels, one by one: too long under Miri"
)]
fn holes_are_kept_as_rings() {
    let mut mask = Mask::new(200, 200);
    mask.square(20, 20, 160, 2, 0);
    mask.square(80, 80, 40, 2, 0);
    let rings = rings_of(mask.zone(40, 40, 3));
    assert_eq!(rings.len(), 2);
    let inside = covered(&rings, 200, 200);
    assert!(inside[40 * 200 + 40]);
    assert!(
        !inside[100 * 200 + 100],
        "the inner square's inside is a hole"
    );
}

#[test]
#[cfg_attr(
    miri,
    ignore = "tens of thousands of pixels, one by one: too long under Miri"
)]
fn a_narrow_place_is_filled_by_the_plain_flood() {
    let mut mask = Mask::new(120, 60);
    // A closed corridor 3 pixels high: no disc of radius 4 fits anywhere.
    mask.ink(10, 20, 100, 21);
    mask.ink(10, 25, 100, 26);
    mask.ink(10, 20, 11, 26);
    mask.ink(99, 20, 100, 26);
    let rings = rings_of(mask.zone(50, 23, 4));
    let inside = covered(&rings, 120, 60);
    assert!(inside[23 * 120 + 50]);
    assert!(!inside[10 * 120 + 50]);
}

#[test]
fn the_c_contract_says_how_much_room_the_outline_needs() {
    // A smaller sheet under Miri, which reads every pixel slowly: the
    // contract is the same.
    let n: usize = if cfg!(miri) { 24 } else { 100 };
    let side = n as u32;
    let mut mask = Mask::new(n, n);
    mask.square(n / 10, n / 10, n * 6 / 10, 2, 0);
    let (mut points, mut rings) = (0usize, 0usize);
    unsafe {
        let call = |out_points: *mut EpPoint,
                    pc,
                    out_rings: *mut u32,
                    rc,
                    points: &mut usize,
                    rings: &mut usize| {
            ep_fill_zone(
                mask.bytes.as_ptr(),
                side,
                side,
                side * 4 / 10,
                side * 4 / 10,
                3,
                out_points,
                pc,
                out_rings,
                rc,
                points,
                rings,
            )
        };
        assert_eq!(
            call(
                ptr::null_mut(),
                0,
                ptr::null_mut(),
                0,
                &mut points,
                &mut rings
            ),
            INVALID
        );
        assert!(points >= 4 && rings == 1);
        let mut out_points = vec![EpPoint { x: -1.0, y: -1.0 }; points];
        let mut out_rings = vec![0u32; rings];
        assert_eq!(
            call(
                out_points.as_mut_ptr(),
                points,
                out_rings.as_mut_ptr(),
                rings,
                &mut points,
                &mut rings
            ),
            1
        );
        assert_eq!(out_rings[0] as usize, points);
        assert!(out_points.iter().all(|p| p.x >= 0.0 && p.y >= 0.0));
        let on_ink = ep_fill_zone(
            mask.bytes.as_ptr(),
            side,
            side,
            side / 10,
            side / 10,
            3,
            ptr::null_mut(),
            0,
            ptr::null_mut(),
            0,
            ptr::null_mut(),
            ptr::null_mut(),
        );
        assert_eq!(on_ink, 0);
        for (x, y, radius) in [(side, 0, 3), (0, side, 3), (0, 0, MAX_RADIUS + 1)] {
            assert_eq!(
                ep_fill_zone(
                    mask.bytes.as_ptr(),
                    side,
                    side,
                    x,
                    y,
                    radius,
                    ptr::null_mut(),
                    0,
                    ptr::null_mut(),
                    0,
                    ptr::null_mut(),
                    ptr::null_mut()
                ),
                INVALID
            );
        }
    }
}

#[test]
#[ignore = "a measure: cargo test --release fill -- --ignored --nocapture"]
fn a_large_sheet_is_filled_in_good_time() {
    let (w, h) = (2048usize, 1536usize);
    let mut mask = Mask::new(w, h);
    for i in 0..40 {
        let (x, y) = (40 + (i % 8) * 240, 60 + (i / 8) * 290);
        mask.square(x, y, 180, 4, if i % 3 == 0 { 9 } else { 0 });
    }
    for radius in [0, 6, 24, 64] {
        let start = std::time::Instant::now();
        let outside = mask.zone(10, 10, radius);
        let inside = mask.zone(130, 150, radius);
        let rings = |zone: &Zone| match zone {
            Zone::Rings(rings) => rings.len(),
            _ => 0,
        };
        println!(
            "radius {radius}: {:?} for two fills ({} and {} rings)",
            start.elapsed(),
            rings(&outside),
            rings(&inside)
        );
    }
}
