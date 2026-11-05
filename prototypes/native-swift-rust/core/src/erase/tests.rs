// SPDX-License-Identifier: MIT
//! The eraser that cuts: what it leaves of a line, what it removes whole, one
//! rub undone in one step.

use super::*;
use crate::test_support::*;

fn erase(
    doc: &Owned,
    path: &[EpPoint],
    radius: f32,
    cut: &[usize],
    removed: &[usize],
    merge: bool,
) -> i32 {
    unsafe {
        ep_erase(
            doc.0,
            path.as_ptr(),
            path.len(),
            radius,
            if cut.is_empty() {
                ptr::null()
            } else {
                cut.as_ptr()
            },
            cut.len(),
            if removed.is_empty() {
                ptr::null()
            } else {
                removed.as_ptr()
            },
            removed.len(),
            u32::from(merge),
        )
    }
}

fn horizontal(doc: &Owned) {
    let points: Vec<EpPoint> = (0..=10)
        .map(|i| point(100.0 + 20.0 * i as f32, 100.0))
        .collect();
    assert_eq!(doc.stroke(&points, 0x0011_2233), 0);
}

#[test]
fn a_rub_across_a_stroke_cuts_it_in_two_and_undo_brings_it_back_whole() {
    let doc = Owned::new();
    horizontal(&doc);
    let before = doc.state();
    // A vertical rub at x = 200, radius 9 (+ width/4 = 0.75).
    assert_eq!(
        erase(
            &doc,
            &[point(200.0, 50.0), point(200.0, 150.0)],
            9.0,
            &[0],
            &[],
            false
        ),
        1
    );
    doc.assert_accounting();
    assert_eq!(doc.count(), 2);
    let left = doc.points(0);
    let right = doc.points(1);
    assert_eq!(left.first(), Some(&point(100.0, 100.0)));
    assert!((left.last().unwrap().x - 190.25).abs() < 1e-3, "{left:?}");
    assert!(
        (right.first().unwrap().x - 209.75).abs() < 1e-3,
        "{right:?}"
    );
    assert_eq!(right.last(), Some(&point(300.0, 100.0)));
    assert_eq!(doc.info(0).rgb, 0x0011_2233);
    assert_eq!(unsafe { ep_undo_count(doc.0) }, 2);
    assert_eq!(doc.undo(), 1);
    let after = doc.state();
    assert_eq!((&after.0, &after.1), (&before.0, &before.1));
    doc.assert_accounting();
    assert_eq!(doc.redo(), 1);
    assert_eq!(doc.count(), 2);
    assert_eq!(doc.points(1), right);
    doc.assert_accounting();
}

#[test]
fn the_calls_of_one_gesture_are_one_command() {
    let doc = Owned::new();
    horizontal(&doc);
    assert_eq!(
        erase(
            &doc,
            &[point(150.0, 90.0), point(150.0, 110.0)],
            4.0,
            &[0],
            &[],
            false
        ),
        1
    );
    let pieces = doc.count();
    let cut: Vec<usize> = (0..pieces).collect();
    assert_eq!(
        erase(
            &doc,
            &[point(250.0, 90.0), point(250.0, 110.0)],
            4.0,
            &cut,
            &[],
            true
        ),
        1
    );
    assert_eq!(doc.count(), 3);
    assert_eq!(
        unsafe { ep_undo_count(doc.0) },
        2,
        "the stroke, then one rub"
    );
    doc.assert_accounting();
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.count(), 1);
    assert_eq!(doc.points(0).len(), 11);
    doc.assert_accounting();
    assert_eq!(doc.redo(), 1);
    assert_eq!(doc.count(), 3);
    doc.assert_accounting();
    // After an undo, a new rub never joins the old one.
    assert_eq!(doc.undo(), 1);
    assert_eq!(
        erase(
            &doc,
            &[point(150.0, 90.0), point(150.0, 110.0)],
            4.0,
            &[0],
            &[],
            true
        ),
        1
    );
    assert_eq!(unsafe { ep_undo_count(doc.0) }, 2);
    assert_eq!(unsafe { ep_redo_count(doc.0) }, 0);
}

#[test]
fn lines_stay_lines_and_hollow_boxes_become_their_outline() {
    let doc = Owned::new();
    assert_eq!(doc.shape(1, corners(100.0, 300.0, 500.0, 300.0), 1, 2.0), 0);
    assert_eq!(doc.shape(2, corners(600.0, 100.0, 800.0, 300.0), 2, 2.0), 0);
    assert_eq!(
        doc.add(&Spec {
            points: &corners(900.0, 100.0, 1100.0, 300.0),
            kind: 2,
            fill: Some(0x00ff_ff00),
            quant: u32::from(EXACT_QUANT),
            ..Spec::default()
        }),
        0
    );
    // Through the line, the hollow box's top edge and the filled box.
    let path = [point(300.0, 280.0), point(300.0, 320.0)];
    assert_eq!(erase(&doc, &path, 5.0, &[0], &[], false), 1);
    assert_eq!((doc.kind(0), doc.kind(1)), (1, 1));
    let top = [point(700.0, 90.0), point(700.0, 110.0)];
    assert_eq!(erase(&doc, &top, 5.0, &[2], &[], false), 1);
    // The rectangle's outline is now one freehand stroke going round from
    // the cut to the cut.
    let kinds: Vec<u32> = (0..doc.count()).map(|i| doc.kind(i)).collect();
    assert_eq!(kinds, [1, 1, 0, 2]);
    // The filled box is not cut: the interface removes it whole.
    let inside = [point(1000.0, 200.0)];
    assert_eq!(erase(&doc, &inside, 5.0, &[3], &[], false), 0);
    assert_eq!(erase(&doc, &inside, 5.0, &[], &[3], false), 1);
    assert_eq!(doc.count(), 3);
    doc.assert_accounting();
}

#[test]
fn a_dot_under_the_eraser_goes_and_an_untouched_stroke_stays() {
    let doc = Owned::new();
    assert_eq!(doc.dot(50.0, 50.0), 0);
    horizontal(&doc);
    let before = doc.state();
    assert_eq!(
        erase(&doc, &[point(400.0, 400.0)], 10.0, &[0, 1], &[], false),
        0
    );
    assert_eq!(doc.state(), before);
    assert_eq!(
        erase(&doc, &[point(52.0, 50.0)], 5.0, &[0, 1], &[], false),
        1
    );
    assert_eq!(doc.count(), 1);
    assert_eq!(doc.points(0).len(), 11);
    doc.assert_accounting();
}

#[test]
fn a_pressed_turned_chalk_stroke_keeps_its_pressures_tool_and_turn_in_its_pieces() {
    let doc = Owned::new();
    let points: Vec<EpPoint> = (0..=8)
        .map(|i| point(200.0 + 25.0 * i as f32, 400.0))
        .collect();
    let pressures: Vec<u8> = (0..=8).map(|i| 20 + i * 25).collect();
    assert_eq!(
        doc.add(&Spec {
            points: &points,
            pressures: &pressures,
            look: EpObjectLook {
                tool: TOOL_CHALK,
                seed: 3,
                rotation: std::f32::consts::FRAC_PI_2,
                ..PLAIN_LOOK
            },
            width: 8.0,
            quant: u32::from(EXACT_QUANT),
            ..Spec::default()
        }),
        0
    );
    // Turned a quarter, the stroke stands vertical about its centre (300, 400).
    assert_eq!(
        erase(
            &doc,
            &[point(280.0, 400.0), point(320.0, 400.0)],
            3.0,
            &[0],
            &[],
            false
        ),
        1
    );
    assert_eq!(doc.count(), 2);
    for index in 0..2 {
        let look = doc.look(index);
        assert_eq!((look.tool, look.seed, look.rotation), (TOOL_CHALK, 3, 0.0));
        let piece = doc.points(index);
        assert!(
            piece.iter().all(|p| (p.x - 300.0).abs() < 1e-3),
            "{piece:?}"
        );
        assert_eq!(
            unsafe { ep_object_pressure_count(doc.0, index) },
            piece.len()
        );
    }
    doc.assert_accounting();
    let bytes = doc.v6(true);
    assert_eq!(Owned::from_project(&bytes).v6(true), bytes);
}

#[test]
fn objects_out_of_reach_of_the_eraser_are_refused() {
    let doc = Owned::new();
    horizontal(&doc);
    unsafe { assert_eq!(ep_set_layer_visible(doc.0, 0, 0), 1) };
    let before = doc.state();
    assert_eq!(
        erase(&doc, &[point(200.0, 100.0)], 9.0, &[0], &[], false),
        INVALID
    );
    assert_eq!(
        erase(&doc, &[point(200.0, 100.0)], 9.0, &[5], &[], false),
        INVALID
    );
    assert_eq!(
        erase(&doc, &[point(200.0, 100.0)], 0.0, &[], &[], false),
        INVALID
    );
    assert_eq!(
        erase(&doc, &[point(f32::NAN, 100.0)], 9.0, &[], &[], false),
        INVALID
    );
    assert_eq!(doc.state(), before);
    // A page's lines and zones are never reached.
    let page = Owned(ep_document_from_page(0));
    let locked = (0..page.count())
        .find(|&i| page.doc().locked(page.doc().strokes[i].layer))
        .unwrap();
    assert_eq!(
        erase(&page, &[point(10.0, 10.0)], 9.0, &[locked], &[], false),
        INVALID
    );
    assert_eq!(
        erase(&page, &[point(10.0, 10.0)], 9.0, &[], &[locked], false),
        INVALID
    );
}

#[test]
fn a_hollow_contour_becomes_its_outline_cut_once() {
    let doc = Owned::new();
    // A hollow triangle; filled, it would be removed whole by the interface.
    let triangle = [
        point(300.0, 100.0),
        point(400.0, 300.0),
        point(200.0, 300.0),
    ];
    assert_eq!(
        doc.add(&Spec {
            points: &triangle,
            kind: KIND_CONTOUR,
            width: 4.0,
            quant: u32::from(EXACT_QUANT),
            ..Spec::default()
        }),
        0
    );
    // Through its base: one piece going round from the cut to the cut.
    assert_eq!(
        erase(
            &doc,
            &[point(300.0, 280.0), point(300.0, 320.0)],
            5.0,
            &[0],
            &[],
            false
        ),
        1
    );
    assert_eq!(doc.count(), 1);
    assert_eq!(doc.kind(0), 0);
    let piece = doc.points(0);
    assert!(
        (piece[0].x - 294.0).abs() < 1e-3 && piece[0].y == 300.0,
        "{piece:?}"
    );
    assert!(piece.contains(&point(200.0, 300.0)) && piece.contains(&point(300.0, 100.0)));
    assert!((piece.last().unwrap().x - 306.0).abs() < 1e-3, "{piece:?}");
    doc.assert_accounting();
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.kind(0), KIND_CONTOUR);
}

/// The zone of the paint pot whose fill was taken away is a hollow contour:
/// cut, its outline is a plain freehand stroke — a freehand stroke cannot
/// carry the tool of a zone — and the drawing saved then reads back whole.
#[test]
fn the_outline_of_a_cut_zone_is_plain_and_saves_and_reads_back() {
    let doc = Owned::new();
    let square = [
        point(100.0, 100.0),
        point(300.0, 100.0),
        point(300.0, 300.0),
        point(100.0, 300.0),
    ];
    assert_eq!(
        doc.add(&Spec {
            points: &square,
            kind: KIND_CONTOUR,
            width: 4.0,
            look: EpObjectLook {
                tool: TOOL_ZONE,
                ..PLAIN_LOOK
            },
            ..Spec::default()
        }),
        0
    );
    assert_eq!(doc.look(0).tool, TOOL_ZONE);
    assert_eq!(
        erase(
            &doc,
            &[point(200.0, 80.0), point(200.0, 120.0)],
            5.0,
            &[0],
            &[],
            false
        ),
        1
    );
    assert_eq!(doc.kind(0), 0);
    assert_eq!(doc.look(0).tool, TOOL_ROUND);
    doc.assert_accounting();
    let read = Owned::from_project(&doc.v6(true));
    assert_eq!(read.count(), 1);
    assert_eq!(read.points(0), doc.points(0));
}

/// The outline of a hollow contour of the most points, cut once in its
/// closing side, would be one stroke longer than any stroke may be, which no
/// reader would take back: it is left whole. Cut where its points are, it
/// becomes its outline as any other.
#[test]
#[cfg_attr(miri, ignore = "a hundred thousand points: too long under Miri")]
fn a_contour_too_long_to_become_one_stroke_is_left_whole() {
    let doc = Owned::new();
    // Dense along the top, a long side back along the bottom.
    let mut outline = vec![point(100.0, 400.0)];
    outline.extend(
        (0..MAX_STROKE_POINTS - 2).map(|i| point(100.0 + i as f32 / 256.0, 100.0 + (i % 2) as f32)),
    );
    outline.push(point(500.0, 400.0));
    assert_eq!(outline.len(), MAX_STROKE_POINTS);
    assert_eq!(
        doc.add(&Spec {
            points: &outline,
            kind: KIND_CONTOUR,
            width: 4.0,
            quant: u32::from(EXACT_QUANT),
            ..Spec::default()
        }),
        0
    );
    // Through its long side: nothing is cut.
    assert_eq!(
        erase(
            &doc,
            &[point(300.0, 380.0), point(300.0, 420.0)],
            5.0,
            &[0],
            &[],
            false
        ),
        0
    );
    assert_eq!(doc.kind(0), KIND_CONTOUR);
    assert_eq!(doc.points(0).len(), MAX_STROKE_POINTS);
    // Through its dense side: one piece, a little shorter than the contour.
    assert_eq!(
        erase(
            &doc,
            &[point(300.0, 90.0), point(300.0, 110.0)],
            5.0,
            &[0],
            &[],
            false
        ),
        1
    );
    assert_eq!(doc.count(), 1);
    assert_eq!(doc.kind(0), 0);
    let piece = doc.points(0).len();
    assert!(piece < MAX_STROKE_POINTS, "{piece}");
    doc.assert_accounting();
    let read = Owned::from_project(&doc.v6(false));
    assert_eq!(read.points(0).len(), piece);
}
