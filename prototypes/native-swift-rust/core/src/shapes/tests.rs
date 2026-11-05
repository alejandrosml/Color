// SPDX-License-Identifier: MIT
//! The new shapes in their box, and the magnet shapes from strokes drawn as a
//! hand draws them: wobbling, unevenly sampled, a little short or a little
//! past their start.

use super::*;
use crate::test_support::*;

/// A hand that draws: its wobble and its noise are the same for a seed.
struct Hand(u32);

impl Hand {
    fn next(&mut self) -> f64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 17;
        self.0 ^= self.0 << 5;
        f64::from(self.0) / f64::from(u32::MAX) * 2.0 - 1.0
    }

    /// The ideal path as the hand draws it: `wobble` a share of its size,
    /// slow; a closed path started anywhere, ended `past` of its length
    /// beyond its start (short when negative).
    fn draw(&mut self, ideal: &[P], closed: bool, wobble: f64, past: f64) -> Vec<EpPoint> {
        let mut path = ideal.to_vec();
        if closed {
            path.push(ideal[0]);
        }
        let dense = resample(&path, 400);
        let (mut min, mut max) = ((f64::MAX, f64::MAX), (f64::MIN, f64::MIN));
        for p in &dense {
            min = (min.0.min(p.0), min.1.min(p.1));
            max = (max.0.max(p.0), max.1.max(p.1));
        }
        let size = (max.0 - min.0).hypot(max.1 - min.1);
        let start = if closed {
            ((self.next() + 1.0) * 199.0) as usize
        } else {
            0
        };
        let (phase_a, phase_b) = (self.next() * 3.0, self.next() * 3.0);
        let span = if closed {
            (400.0 * (1.0 + past)) as usize
        } else {
            400
        };
        let mut out = Vec::new();
        let mut i = 0;
        while i < span {
            let k = if closed {
                (start + i) % 399
            } else {
                i.min(399)
            };
            // The direction of the path here, for the wobble across it.
            let (before, after) = if k < 399 {
                (dense[k], dense[k + 1])
            } else {
                (dense[k - 1], dense[k])
            };
            let p = dense[k];
            let (dx, dy) = (after.0 - before.0, after.1 - before.1);
            let length = dx.hypot(dy).max(1e-9);
            let t = i as f64 / 400.0 * std::f64::consts::TAU;
            let offset =
                wobble * size * (0.6 * (2.0 * t + phase_a).sin() + 0.4 * (5.0 * t + phase_b).sin())
                    + 0.003 * size * self.next();
            out.push(point(
                (p.0 - dy / length * offset) as f32,
                (p.1 + dx / length * offset) as f32,
            ));
            // Unevenly: the hand slows and hurries.
            i += 1 + ((self.next() + 1.0) * 2.0) as usize;
        }
        out
    }
}

fn regular(sides: usize, centre: P, radius: P, turn: f64) -> Vec<P> {
    (0..sides)
        .map(|i| {
            let angle = turn + std::f64::consts::TAU * i as f64 / sides as f64;
            let (x, y) = (radius.0 * angle.cos(), radius.1 * angle.sin());
            let (sin, cos) = turn.sin_cos();
            let _ = (sin, cos);
            (centre.0 + x, centre.1 + y)
        })
        .collect()
}

fn turned(points: &[P], centre: P, angle: f64) -> Vec<P> {
    let (sin, cos) = angle.sin_cos();
    points
        .iter()
        .map(|p| {
            let (x, y) = (p.0 - centre.0, p.1 - centre.1);
            (centre.0 + x * cos - y * sin, centre.1 + x * sin + y * cos)
        })
        .collect()
}

fn rectangle(centre: P, w: f64, h: f64) -> Vec<P> {
    vec![
        (centre.0 - w / 2.0, centre.1 - h / 2.0),
        (centre.0 + w / 2.0, centre.1 - h / 2.0),
        (centre.0 + w / 2.0, centre.1 + h / 2.0),
        (centre.0 - w / 2.0, centre.1 + h / 2.0),
    ]
}

fn ellipse_points(centre: P, a: f64, b: f64, angle: f64) -> Vec<P> {
    turned(&regular(120, centre, (a, b), 0.0), centre, angle)
}

fn signed_area(points: &[EpPoint]) -> f64 {
    (0..points.len())
        .map(|i| {
            let (a, b) = (points[i], points[(i + 1) % points.len()]);
            f64::from(a.x) * f64::from(b.y) - f64::from(b.x) * f64::from(a.y)
        })
        .sum::<f64>()
        / 2.0
}

/// Each ideal corner has a recognised one near it.
fn near_corners(found: &[P], ideal: &[P], within: f64) -> bool {
    found.len() == ideal.len()
        && ideal
            .iter()
            .all(|i| found.iter().any(|f| gap(*f, *i) <= within))
}

#[test]
fn every_shape_fills_its_box_clockwise() {
    let (a, b) = (point(100.0, 50.0), point(400.0, 250.0));
    for shape in 0..SHAPE_COUNT {
        let points = outline(shape, a, b).unwrap();
        let xs = points.iter().map(|p| p.x);
        let ys = points.iter().map(|p| p.y);
        assert_eq!(xs.clone().fold(f32::MAX, f32::min), 100.0, "{shape}");
        assert_eq!(xs.fold(f32::MIN, f32::max), 400.0, "{shape}");
        assert_eq!(ys.clone().fold(f32::MAX, f32::min), 50.0, "{shape}");
        assert_eq!(ys.fold(f32::MIN, f32::max), 250.0, "{shape}");
        assert!(
            signed_area(&points) > 0.0,
            "{shape} turns clockwise on the sheet"
        );
        // The same box from its other corners.
        assert_eq!(
            outline(shape, point(100.0, 250.0), point(400.0, 50.0)).map(|p| p.len()),
            Some(points.len())
        );
    }
    // The arrow points the way it was drawn.
    let right = outline(SHAPE_ARROW, a, b).unwrap();
    let left = outline(SHAPE_ARROW, b, a).unwrap();
    assert!(right.contains(&point(400.0, 150.0)) && left.contains(&point(100.0, 150.0)));
    assert!(signed_area(&left) > 0.0);
    // A big heart has more points than a small one, never too many.
    let small = outline(SHAPE_HEART, point(0.0, 0.0), point(20.0, 20.0))
        .unwrap()
        .len();
    let big = outline(SHAPE_HEART, point(0.0, 0.0), point(4000.0, 4000.0))
        .unwrap()
        .len();
    assert!(small >= 48 && big > small && big <= MAX_OUTLINE_POINTS);
    // No box, no shape.
    assert!(outline(SHAPE_STAR, a, point(100.0, 90.0)).is_none());
    assert!(outline(SHAPE_COUNT, a, b).is_none());
    assert!(outline(SHAPE_STAR, a, point(f32::NAN, 9.0)).is_none());
}

#[test]
fn circles_and_ellipses_are_recognised_level_or_turned() {
    for seed in 1..=12 {
        let mut hand = Hand(seed * 7919);
        let past = [0.06, -0.04, 0.0][seed as usize % 3];
        let circle = recognise(&hand.draw(
            &ellipse_points((300.0, 300.0), 100.0, 100.0, 0.0),
            true,
            0.012,
            past,
        ))
        .unwrap();
        assert_eq!((circle.kind, circle.rotation), (3, 0.0), "seed {seed}");
        let (lo, hi) = (circle.points[0], circle.points[1]);
        assert!(
            (hi.0 - lo.0 - (hi.1 - lo.1)).abs() < 1e-9,
            "a circle, seed {seed}"
        );
        assert!(
            ((hi.0 - lo.0) / 2.0 - 100.0).abs() < 8.0,
            "seed {seed}: {circle:?}"
        );
        let level = recognise(&hand.draw(
            &ellipse_points((400.0, 300.0), 160.0, 70.0, 0.0),
            true,
            0.01,
            past,
        ))
        .unwrap();
        assert_eq!((level.kind, level.rotation), (3, 0.0), "seed {seed}");
        let tilted = recognise(&hand.draw(
            &ellipse_points((400.0, 300.0), 160.0, 70.0, 0.5),
            true,
            0.01,
            past,
        ))
        .unwrap();
        assert_eq!(tilted.kind, 3, "seed {seed}");
        assert!(
            (tilted.rotation - 0.5).abs() < 0.1,
            "seed {seed}: {tilted:?}"
        );
        let (lo, hi) = (tilted.points[0], tilted.points[1]);
        assert!(
            ((hi.0 - lo.0) / 2.0 - 160.0).abs() < 12.0 && ((hi.1 - lo.1) / 2.0 - 70.0).abs() < 8.0,
            "seed {seed}: {tilted:?}"
        );
        // Drawn by a hurried hand, a circle still; drawn round twice, too.
        let sloppy = recognise(&hand.draw(
            &ellipse_points((300.0, 300.0), 100.0, 100.0, 0.0),
            true,
            0.035,
            past,
        ))
        .unwrap();
        assert_eq!(sloppy.kind, 3, "seed {seed}: {sloppy:?}");
        let twice = recognise(&hand.draw(
            &ellipse_points((300.0, 300.0), 100.0, 100.0, 0.0),
            true,
            0.01,
            1.0,
        ))
        .unwrap();
        assert_eq!(twice.kind, 3, "seed {seed}: {twice:?}");
    }
}

#[test]
fn boxes_are_recognised_square_and_straight() {
    for seed in 1..=12 {
        let mut hand = Hand(seed * 104_729);
        let past = [0.05, -0.03, 0.0][seed as usize % 3];
        let square =
            recognise(&hand.draw(&rectangle((300.0, 300.0), 200.0, 200.0), true, 0.006, past))
                .unwrap();
        assert_eq!(square.kind, 2, "seed {seed}: {square:?}");
        let (lo, hi) = (square.points[0], square.points[1]);
        assert!(
            (hi.0 - lo.0 - (hi.1 - lo.1)).abs() < 1e-9 && (hi.0 - lo.0 - 200.0).abs() < 10.0,
            "seed {seed}: {square:?}"
        );
        // A box drawn a little askew is put level.
        let askew = turned(
            &rectangle((300.0, 300.0), 260.0, 120.0),
            (300.0, 300.0),
            0.06,
        );
        let level = recognise(&hand.draw(&askew, true, 0.006, past)).unwrap();
        assert_eq!(level.kind, 2, "seed {seed}: {level:?}");
        // Turned for real, it stays turned, its corners square.
        let ideal = turned(
            &rectangle((300.0, 300.0), 260.0, 120.0),
            (300.0, 300.0),
            0.45,
        );
        let turned_box = recognise(&hand.draw(&ideal, true, 0.006, past)).unwrap();
        assert_eq!(turned_box.kind, KIND_CONTOUR, "seed {seed}: {turned_box:?}");
        assert!(
            near_corners(&turned_box.points, &ideal, 12.0),
            "seed {seed}: {turned_box:?}"
        );
        let sloppy =
            recognise(&hand.draw(&rectangle((300.0, 300.0), 200.0, 200.0), true, 0.02, past))
                .unwrap();
        assert_eq!(sloppy.kind, 2, "seed {seed}: {sloppy:?}");
        let triangle = [(300.0, 120.0), (460.0, 400.0), (140.0, 400.0)];
        let found = recognise(&hand.draw(&triangle, true, 0.02, past)).unwrap();
        assert_eq!(found.kind, KIND_CONTOUR, "seed {seed}: {found:?}");
        assert!(
            near_corners(&found.points, &triangle, 24.0),
            "seed {seed}: {found:?}"
        );
        let c = &turned_box.points;
        for j in 0..4 {
            let (u, v) = (
                (c[(j + 3) % 4].0 - c[j].0, c[(j + 3) % 4].1 - c[j].1),
                (c[(j + 1) % 4].0 - c[j].0, c[(j + 1) % 4].1 - c[j].1),
            );
            assert!(
                (u.0 * v.0 + u.1 * v.1).abs() < 1e-6 * u.0.hypot(u.1) * v.0.hypot(v.1),
                "a right angle"
            );
        }
    }
}

#[test]
fn polygons_keep_their_corners() {
    let star: Vec<P> = (0..10)
        .map(|i| {
            let r = if i % 2 == 0 { 150.0 } else { 60.0 };
            let angle = -std::f64::consts::FRAC_PI_2 + std::f64::consts::PI * f64::from(i) / 5.0;
            (300.0 + r * angle.cos(), 300.0 + r * angle.sin())
        })
        .collect();
    let shapes = [
        vec![(300.0, 120.0), (460.0, 400.0), (140.0, 400.0)],
        regular(
            5,
            (300.0, 300.0),
            (150.0, 150.0),
            -std::f64::consts::FRAC_PI_2,
        ),
        regular(6, (300.0, 300.0), (150.0, 150.0), 0.0),
        vec![
            (300.0, 100.0),
            (420.0, 300.0),
            (300.0, 500.0),
            (180.0, 300.0),
        ],
        star,
    ];
    for (n, ideal) in shapes.iter().enumerate() {
        for seed in 1..=8 {
            let mut hand = Hand(seed * 15_485_863 + n as u32);
            let drawn = hand.draw(ideal, true, 0.004, [0.04, -0.03][seed as usize % 2]);
            let found = recognise(&drawn).unwrap_or_else(|| panic!("shape {n}, seed {seed}"));
            assert_eq!(
                found.kind, KIND_CONTOUR,
                "shape {n}, seed {seed}: {found:?}"
            );
            assert!(
                near_corners(&found.points, ideal, 14.0),
                "shape {n}, seed {seed}: {found:?}"
            );
        }
    }
}

#[test]
fn lines_and_broken_lines_are_straightened() {
    for seed in 1..=10 {
        let mut hand = Hand(seed * 32_452_843);
        let line =
            recognise(&hand.draw(&[(100.0, 100.0), (500.0, 300.0)], false, 0.004, 0.0)).unwrap();
        assert_eq!(line.kind, 1, "seed {seed}");
        assert!(
            gap(line.points[0], (100.0, 100.0)) < 8.0 && gap(line.points[1], (500.0, 300.0)) < 8.0,
            "{line:?}"
        );
        // Nearly level: exactly level.
        let level =
            recognise(&hand.draw(&[(100.0, 200.0), (500.0, 215.0)], false, 0.003, 0.0)).unwrap();
        assert_eq!(level.kind, 1);
        assert_eq!(level.points[0].1, level.points[1].1, "{level:?}");
        let corner = [(100.0, 100.0), (100.0, 400.0), (400.0, 400.0)];
        let l_shape = recognise(&hand.draw(&corner, false, 0.003, 0.0)).unwrap();
        assert_eq!(l_shape.kind, 0, "seed {seed}: {l_shape:?}");
        assert!(
            near_corners(&l_shape.points, &corner, 10.0),
            "seed {seed}: {l_shape:?}"
        );
        let zigzag = [
            (100.0, 300.0),
            (200.0, 100.0),
            (300.0, 300.0),
            (400.0, 100.0),
            (500.0, 300.0),
        ];
        let found = recognise(&hand.draw(&zigzag, false, 0.002, 0.0)).unwrap();
        assert_eq!(found.kind, 0, "seed {seed}: {found:?}");
        assert!(
            near_corners(&found.points, &zigzag, 12.0),
            "seed {seed}: {found:?}"
        );
    }
}

#[test]
fn what_looks_like_nothing_simple_stays_as_drawn() {
    for seed in 1..=10u32 {
        let mut hand = Hand(seed * 49_979_687);
        // A scribble.
        let mut walk = vec![(300.0, 300.0)];
        for _ in 0..60 {
            let last = *walk.last().unwrap();
            walk.push((last.0 + hand.next() * 40.0, last.1 + hand.next() * 40.0));
        }
        assert!(
            recognise(&hand.draw(&walk, false, 0.0, 0.0)).is_none(),
            "seed {seed}"
        );
        // A heart: two points, two round lobes.
        let heart: Vec<P> = outline(SHAPE_HEART, point(100.0, 100.0), point(400.0, 380.0))
            .unwrap()
            .iter()
            .map(|p| (f64::from(p.x), f64::from(p.y)))
            .collect();
        let found = recognise(&hand.draw(&heart, true, 0.004, 0.02));
        assert!(found.is_none(), "seed {seed}: {found:?}");
        // A spiral.
        let spiral: Vec<P> = (0..200)
            .map(|i| {
                let t = f64::from(i) / 20.0;
                (300.0 + 10.0 * t * t.cos(), 300.0 + 10.0 * t * t.sin())
            })
            .collect();
        assert!(
            recognise(&hand.draw(&spiral, false, 0.002, 0.0)).is_none(),
            "seed {seed}"
        );
        // An eight, and a bow tie: what crosses itself is no polygon.
        let eight: Vec<P> = (0..120)
            .map(|i| {
                let t = std::f64::consts::TAU * f64::from(i) / 120.0;
                (300.0 + 150.0 * t.sin(), 300.0 + 120.0 * t.sin() * t.cos())
            })
            .collect();
        let found = recognise(&hand.draw(&eight, true, 0.004, 0.0));
        assert!(found.is_none(), "seed {seed}: {found:?}");
        let bow = [
            (100.0, 100.0),
            (400.0, 300.0),
            (400.0, 100.0),
            (100.0, 300.0),
        ];
        let found = recognise(&hand.draw(&bow, true, 0.002, 0.0));
        assert!(
            found
                .as_ref()
                .is_none_or(|f| f.kind != KIND_CONTOUR || !crosses_itself(&f.points)),
            "seed {seed}: {found:?}"
        );
    }
    // A dot, or nothing.
    assert!(recognise(&[point(10.0, 10.0), point(11.0, 11.0)]).is_none());
    assert!(recognise(&[point(10.0, 10.0)]).is_none());
    assert!(recognise(&[point(10.0, f32::NAN), point(100.0, 100.0)]).is_none());
}

#[test]
fn the_c_contract_keeps_shapes_on_the_sheet() {
    let doc = Owned::new();
    unsafe {
        let mut count = 0;
        assert_eq!(
            ep_shape_outline(
                SHAPE_STAR,
                point(0.0, 0.0),
                point(10.0, 10.0),
                ptr::null_mut(),
                0,
                &mut count
            ),
            INVALID
        );
        assert_eq!(count, 10);
        let mut out = vec![point(0.0, 0.0); count];
        assert_eq!(
            ep_shape_outline(
                SHAPE_STAR,
                point(0.0, 0.0),
                point(10.0, 10.0),
                out.as_mut_ptr(),
                count,
                &mut count
            ),
            0
        );
        assert_eq!(out[0], point(5.0, 0.0));
        // A circle drawn past the sheet's corner is kept on the sheet.
        let mut hand = Hand(5);
        let drawn = hand.draw(
            &ellipse_points((20.0, 20.0), 40.0, 40.0, 0.0),
            true,
            0.01,
            0.02,
        );
        let drawn: Vec<EpPoint> = drawn
            .iter()
            .map(|p| point(p.x.max(0.0), p.y.max(0.0)))
            .collect();
        let (mut kind, mut points, mut n, mut rotation) =
            (99, [point(-1.0, -1.0); MAX_CORNERS], 0, 9.0);
        let found = ep_recognise_shape(
            doc.0,
            drawn.as_ptr(),
            drawn.len(),
            &mut kind,
            points.as_mut_ptr(),
            MAX_CORNERS,
            &mut n,
            &mut rotation,
        );
        if found == 1 {
            assert!(points[..n].iter().all(|p| p.x >= 0.0 && p.y >= 0.0));
        }
        let line = [point(10.0, 10.0), point(300.0, 10.0)];
        assert_eq!(
            ep_recognise_shape(
                doc.0,
                line.as_ptr(),
                2,
                &mut kind,
                points.as_mut_ptr(),
                MAX_CORNERS,
                &mut n,
                &mut rotation
            ),
            1
        );
        assert_eq!((kind, n, rotation), (1, 2, 0.0));
        assert_eq!(&points[..2], &line);
        assert_eq!(
            ep_recognise_shape(
                doc.0,
                line.as_ptr(),
                2,
                &mut kind,
                points.as_mut_ptr(),
                MAX_CORNERS - 1,
                &mut n,
                &mut rotation
            ),
            INVALID
        );
        assert_eq!(
            ep_recognise_shape(
                ptr::null(),
                line.as_ptr(),
                2,
                &mut kind,
                points.as_mut_ptr(),
                MAX_CORNERS,
                &mut n,
                &mut rotation
            ),
            INVALID
        );
    }
}
