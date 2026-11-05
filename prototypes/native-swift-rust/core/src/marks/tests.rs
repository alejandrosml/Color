// SPDX-License-Identifier: MIT
//! The marks of the brushes and magic tools: the same every time, never
//! changing at the start of a stroke that grows, clockwise, bounded.

use super::*;
use crate::test_support::*;

fn wave(count: usize) -> Vec<EpPoint> {
    (0..count)
        .map(|i| {
            let t = i as f32 / 10.0;
            point(30.0 + t * 12.0, 300.0 + 40.0 * (t * 0.7).sin())
        })
        .collect()
}

fn marks_of(points: &[EpPoint], pressures: &[u8], tool: u32, seed: u32, from: usize) -> Marks {
    let mut out = Marks::new();
    compute(
        &Stroked {
            points,
            pressures,
            width: 14.0,
            rgb: 0x00c0_4020,
            tool,
            seed,
        },
        from,
        &mut out,
    )
    .unwrap();
    out
}

/// A mark as its shape, colour, opacity, points and radius, bit for bit.
type Shape = (u32, u32, u32, Vec<(u32, u32)>, u32);

/// Each mark with its own points, apart from its group and its place.
fn shapes(marks: &Marks) -> Vec<Shape> {
    let mut found: Vec<_> = marks
        .marks
        .iter()
        .map(|mark| {
            let points = marks.points[mark.first as usize..(mark.first + mark.count) as usize]
                .iter()
                .map(|p| (p.x.to_bits(), p.y.to_bits()))
                .collect();
            (
                mark.shape,
                mark.rgb,
                mark.alpha,
                points,
                mark.radius.to_bits(),
            )
        })
        .collect();
    found.sort();
    found
}

const SCATTERING: [u32; 4] = [TOOL_CHALK, TOOL_AIRBRUSH, TOOL_GRASS, TOOL_CONFETTI];
const ALL: [u32; 7] = [
    TOOL_CALLIGRAPHY,
    TOOL_CHALK,
    TOOL_AIRBRUSH,
    TOOL_RAINBOW,
    TOOL_GRASS,
    TOOL_BRICKS,
    TOOL_CONFETTI,
];

#[test]
fn the_same_stroke_gives_the_same_marks_and_another_seed_other_ones() {
    let points = wave(200);
    for tool in ALL {
        let first = marks_of(&points, &[], tool, 11, 0);
        assert!(!first.marks.is_empty(), "{tool}");
        let again = marks_of(&points, &[], tool, 11, 0);
        assert_eq!(first.marks, again.marks, "{tool}");
        assert_eq!(first.points, again.points, "{tool}");
        if SCATTERING.contains(&tool) {
            assert_ne!(
                first.points,
                marks_of(&points, &[], tool, 12, 0).points,
                "{tool}"
            );
        }
    }
}

#[test]
fn the_start_of_a_growing_stroke_keeps_its_marks() {
    let points = wave(300);
    for tool in ALL {
        let whole = shapes(&marks_of(&points, &[], tool, 5, 0));
        for end in [2, 17, 120] {
            let start = shapes(&marks_of(&points[..end], &[], tool, 5, 0));
            // Every mark of the beginning is a mark of the whole stroke.
            let mut remaining = whole.clone();
            for mark in &start {
                let at = remaining.binary_search(mark);
                assert!(at.is_ok(), "tool {tool}, end {end}: {mark:?}");
                remaining.remove(at.unwrap());
            }
        }
        // And the marks from a segment on are those of the rest of the stroke.
        let tail = marks_of(&points, &[], tool, 5, 150);
        let head = marks_of(&points[..151], &[], tool, 5, 0);
        let mut both = shapes(&head);
        both.extend(shapes(&tail));
        both.sort();
        if tool != TOOL_BRICKS {
            assert_eq!(both, whole, "tool {tool}");
        }
    }
}

#[test]
fn every_polygon_turns_clockwise_and_groups_follow_each_other() {
    let points = wave(150);
    let pressures: Vec<u8> = (0..points.len()).map(|i| (40 + i % 200) as u8).collect();
    for (tool, pressures) in ALL.iter().map(|&tool| (tool, &[][..])).chain([
        (TOOL_ROUND, &pressures[..]),
        (TOOL_CALLIGRAPHY, &pressures[..]),
    ]) {
        let marks = marks_of(&points, pressures, tool, 9, 0);
        let mut last_group = 0;
        let mut colours = std::collections::BTreeMap::new();
        for mark in &marks.marks {
            assert!(
                mark.group == last_group || mark.group == last_group + 1,
                "{tool}"
            );
            last_group = mark.group;
            let colour = colours.entry(mark.group).or_insert((mark.rgb, mark.alpha));
            assert_eq!(*colour, (mark.rgb, mark.alpha), "one colour per group");
            assert!((1..=255).contains(&mark.alpha));
            if mark.shape == POLYGON {
                let corners =
                    &marks.points[mark.first as usize..(mark.first + mark.count) as usize];
                assert!(signed_area(corners) > 0.0, "tool {tool}");
            } else {
                assert_eq!(mark.count, 1);
                assert!(mark.radius > 0.0);
            }
        }
    }
}

#[test]
fn a_round_stroke_without_pressures_and_a_marker_keep_their_classic_path() {
    let points = wave(40);
    assert!(marks_of(&points, &[], TOOL_ROUND, 0, 0).marks.is_empty());
    assert!(marks_of(&points, &[], TOOL_FELT, 0, 0).marks.is_empty());
    let pressures = vec![128u8; points.len()];
    assert!(marks_of(&points, &pressures, TOOL_FELT, 0, 0)
        .marks
        .is_empty());
    let pressed = marks_of(&points, &pressures, TOOL_ROUND, 0, 0);
    let circles = pressed.marks.iter().filter(|m| m.shape == CIRCLE).count();
    assert_eq!(circles, points.len());
    // The width follows the pressure: half the width × 128/255 here.
    assert!(pressed
        .marks
        .iter()
        .filter(|m| m.shape == CIRCLE)
        .all(|m| (m.radius - 7.0 * 128.0 / 255.0).abs() < 1e-5));
}

#[test]
fn a_dot_has_marks_too() {
    for tool in ALL {
        assert!(
            !marks_of(&[point(50.0, 50.0)], &[], tool, 3, 0)
                .marks
                .is_empty(),
            "{tool}"
        );
    }
}

#[test]
fn bricks_are_laid_once_on_a_wall_of_the_sheet() {
    let back_and_forth: Vec<EpPoint> = (0..200)
        .map(|i| point(100.0 + (i % 20) as f32 * 3.0, 100.0))
        .collect();
    let marks = marks_of(&back_and_forth, &[], TOOL_BRICKS, 0, 0);
    let mut seen = std::collections::BTreeSet::new();
    for mark in &marks.marks {
        let corner = marks.points[mark.first as usize];
        assert!(
            seen.insert((corner.x.to_bits(), corner.y.to_bits())),
            "a brick twice"
        );
    }
    // The same place gives the same bricks whatever stroke passes there.
    let other = marks_of(
        &[point(110.0, 100.0), point(140.0, 100.0)],
        &[],
        TOOL_BRICKS,
        77,
        0,
    );
    let first = |m: &Marks| -> std::collections::BTreeSet<_> {
        m.marks
            .iter()
            .map(|mark| {
                let p = m.points[mark.first as usize];
                (p.x.to_bits(), p.y.to_bits(), mark.rgb)
            })
            .collect()
    };
    assert!(first(&other).is_subset(&first(&marks)));
}

#[test]
fn confetti_have_their_own_colours() {
    let marks = marks_of(&wave(80), &[], TOOL_CONFETTI, 21, 0);
    let colours: std::collections::BTreeSet<u32> = marks.marks.iter().map(|m| m.rgb).collect();
    assert!(colours.len() >= 5);
    assert!(colours.iter().all(|c| CONFETTI.contains(c)));
}

#[test]
fn a_very_long_stroke_stops_adding_marks_at_the_bound() {
    let long: Vec<EpPoint> = (0..100_000)
        .map(|i| point(1.0 + (i % 1000) as f32, 1.0 + (i / 1000) as f32 * 7.0))
        .collect();
    let mut out = Marks::new();
    compute(
        &Stroked {
            points: &long,
            pressures: &[],
            width: 512.0,
            rgb: 0,
            tool: TOOL_AIRBRUSH,
            seed: 1,
        },
        0,
        &mut out,
    )
    .unwrap();
    assert!(out.marks.len() <= MAX_MARKS);
    assert!(out.points.len() <= MAX_MARK_POINTS);
}

/// What a scattering tool gathers before drawing stops at the bound of the
/// marks, however long the stroke: bounded memory, not only bounded marks.
#[test]
#[cfg_attr(miri, ignore = "four hundred thousand pushes: too long under Miri")]
fn what_a_tool_gathers_stops_at_the_bound_of_the_marks() {
    let mut gathered = Vec::new();
    let mut kept = 0usize;
    while collect(&mut gathered, ()).unwrap() {
        kept += 1;
    }
    assert_eq!(kept + 1, MAX_MARKS);
    assert_eq!(gathered.len(), MAX_MARKS);
    assert!(!collect(&mut gathered, ()).unwrap());
    assert_eq!(gathered.len(), MAX_MARKS);
}

/// However long the stroke and however small the spacing, a bounded number
/// of steps: here sixteen million asked, two million taken.
#[test]
#[cfg_attr(miri, ignore = "two million steps: too long under Miri")]
fn a_stroke_takes_a_bounded_number_of_steps() {
    let back_and_forth: Vec<EpPoint> = (0..1000)
        .map(|i| point(if i % 2 == 0 { 1.0 } else { 4001.0 }, 10.0))
        .collect();
    let stroke = Stroked {
        points: &back_and_forth,
        pressures: &[],
        width: 1.0,
        rgb: 0,
        tool: TOOL_BRICKS,
        seed: 1,
    };
    let mut visits = 0u64;
    steps(&stroke, 0.25, 0, |_, _, _, _| {
        visits += 1;
        Ok(true)
    })
    .unwrap();
    assert_eq!(visits, MAX_STEPS);
    // A long thin chalk stroke, then, gives at most the bound of its marks.
    for tool in [TOOL_CHALK, TOOL_AIRBRUSH, TOOL_GRASS, TOOL_CONFETTI] {
        let mut out = Marks::new();
        compute(&Stroked { tool, ..stroke }, 0, &mut out).unwrap();
        assert!(out.marks.len() <= MAX_MARKS, "{tool}");
        assert!(out.points.len() <= MAX_MARK_POINTS, "{tool}");
        assert!(!out.marks.is_empty(), "{tool}");
    }
}

#[test]
fn the_c_contract_gives_an_object_its_marks_or_none() {
    let doc = Owned::new();
    let points = wave(60);
    assert_eq!(
        doc.add(&Spec {
            points: &points,
            look: EpObjectLook {
                tool: TOOL_GRASS,
                seed: 42,
                ..PLAIN_LOOK
            },
            ..Spec::default()
        }),
        0
    );
    assert_eq!(doc.stroke(&points, 0x123456), 0);
    unsafe {
        let mut point_count = 0;
        let count = ep_object_mark_count(doc.0, 0, &mut point_count);
        assert!(count > 0 && point_count >= count);
        assert_eq!(ep_object_mark_count(doc.0, 1, &mut point_count), 0);
        assert_eq!(point_count, 0);
        assert_eq!(ep_object_mark_count(doc.0, 9, ptr::null_mut()), 0);
        let count = ep_object_mark_count(doc.0, 0, &mut point_count);
        let mut marks = vec![
            EpMark {
                shape: 9,
                rgb: 0,
                alpha: 0,
                group: 0,
                first: 0,
                count: 0,
                radius: 0.0
            };
            count
        ];
        let mut points_out = vec![point(-1.0, -1.0); point_count];
        assert_eq!(
            ep_copy_object_marks(
                doc.0,
                0,
                marks.as_mut_ptr(),
                count - 1,
                points_out.as_mut_ptr(),
                point_count
            ),
            INVALID
        );
        assert!(
            marks.iter().all(|m| m.shape == 9),
            "nothing written on refusal"
        );
        assert_eq!(
            ep_copy_object_marks(
                doc.0,
                0,
                marks.as_mut_ptr(),
                count,
                points_out.as_mut_ptr(),
                point_count
            ),
            0
        );
        let direct = marks_of_object(&doc, 0);
        assert_eq!(marks, direct.marks);
        assert_eq!(points_out, direct.points);
        // The stroke being drawn shows the marks the object keeps.
        let (mut needed_marks, mut needed_points) = (0, 0);
        assert_eq!(
            ep_stroke_marks(
                doc.points(0).as_ptr(),
                points.len(),
                ptr::null(),
                3.0,
                0x0012_3456,
                TOOL_GRASS,
                42,
                0,
                ptr::null_mut(),
                0,
                ptr::null_mut(),
                0,
                &mut needed_marks,
                &mut needed_points,
            ),
            INVALID
        );
        assert_eq!((needed_marks, needed_points), (count, point_count));
        let mut drawn = vec![marks[0]; needed_marks];
        let mut drawn_points = vec![point(0.0, 0.0); needed_points];
        assert_eq!(
            ep_stroke_marks(
                doc.points(0).as_ptr(),
                points.len(),
                ptr::null(),
                3.0,
                0x0012_3456,
                TOOL_GRASS,
                42,
                0,
                drawn.as_mut_ptr(),
                drawn.len(),
                drawn_points.as_mut_ptr(),
                drawn_points.len(),
                &mut needed_marks,
                &mut needed_points,
            ),
            0
        );
        assert_eq!(drawn, marks);
        assert_eq!(drawn_points, points_out);
    }
}

fn marks_of_object(doc: &Owned, index: usize) -> Marks {
    of_object(&doc.doc().strokes[index]).unwrap()
}
