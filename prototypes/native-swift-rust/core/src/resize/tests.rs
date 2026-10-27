use super::*;
use crate::test_support::*;

fn bounds(points: &[EpPoint]) -> (f32, f32, f32, f32) {
    points.iter().fold(
        (
            f32::INFINITY,
            f32::INFINITY,
            f32::NEG_INFINITY,
            f32::NEG_INFINITY,
        ),
        |(left, top, right, bottom), point| {
            (
                left.min(point.x),
                top.min(point.y),
                right.max(point.x),
                bottom.max(point.y),
            )
        },
    )
}

#[test]
fn a_shape_grows_and_shrinks_around_its_centre_in_one_reversible_step() {
    let doc = Owned::new();
    assert_eq!(
        doc.shape(2, corners(100.0, 200.0, 300.0, 280.0), 0x112233, 6.0),
        0
    );
    let before = doc.state();
    assert_eq!(doc.scale(0, 1.5, 9.0), 1);
    // 200 x 80 around (200, 240) becomes 300 x 120 around the same centre.
    assert_eq!(doc.points(0), corners(50.0, 180.0, 350.0, 300.0));
    assert_eq!(doc.info(0).width, 9.0);
    assert_eq!(unsafe { ep_object_revision(doc.0, 0) }, 2);
    let grown = doc.state();
    assert_eq!((grown.2, grown.3), (2, 0));
    assert!(grown
        .1
        .contains("<rect x=\"50\" y=\"180\" width=\"300\" height=\"120\""));
    assert!(grown.1.contains("stroke-width=\"9\""));
    assert_eq!(grown.0[8], 2, "resizing needs no new project version");

    // The file stores the points as they are now seen.
    let reopened = Owned::from_project(&grown.0);
    assert_eq!(reopened.points(0), corners(50.0, 180.0, 350.0, 300.0));
    assert_eq!(reopened.project(), grown.0);
    assert_eq!(reopened.svg(), grown.1);

    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.state().0, before.0);
    assert_eq!(doc.points(0), corners(100.0, 200.0, 300.0, 280.0));
    assert_eq!(unsafe { ep_object_revision(doc.0, 0) }, 1);
    assert_eq!(doc.redo(), 1);
    assert_eq!(doc.state(), grown);

    assert_eq!(doc.scale(0, 0.5, 4.5), 1);
    assert_eq!(doc.points(0), corners(125.0, 210.0, 275.0, 270.0));
    assert_eq!(doc.info(0).width, 4.5);
    doc.assert_accounting();
}

#[test]
fn every_point_of_a_freehand_stroke_follows_and_the_copy_is_resized_too() {
    let doc = Owned::new();
    let drawn = [
        point(100.0, 100.0),
        point(140.0, 180.0),
        point(200.0, 120.0),
        point(260.0, 200.0),
    ];
    assert_eq!(doc.stroke(&drawn, 0x445566), 0);
    assert_eq!(doc.scale(0, 2.0, 6.0), 1);
    // Centre (180, 150): every offset from it doubles.
    assert_eq!(
        doc.points(0),
        [
            point(20.0, 50.0),
            point(100.0, 210.0),
            point(220.0, 90.0),
            point(340.0, 250.0),
        ]
    );
    // Moving and resizing compose in any order, and undo returns exactly.
    assert_eq!(unsafe { ep_move_object(doc.0, 0, 10.0, -5.0) }, 1);
    assert_eq!(doc.scale(0, 0.5, 3.0), 1);
    assert_eq!(
        doc.points(0),
        [
            point(110.0, 95.0),
            point(150.0, 175.0),
            point(210.0, 115.0),
            point(270.0, 195.0),
        ]
    );
    // A copy carries the resized geometry and can be resized on its own.
    assert_eq!(unsafe { ep_duplicate_object(doc.0, 0, 100.0, 100.0) }, 1);
    assert_eq!(doc.points(1)[0], point(210.0, 195.0));
    assert_eq!(doc.scale(1, 2.0, 3.0), 1);
    assert_eq!(bounds(&doc.points(1)), (130.0, 145.0, 450.0, 345.0));
    assert_eq!(bounds(&doc.points(0)), (110.0, 95.0, 270.0, 195.0));
    let end = doc.state();
    for _ in 0..5 {
        assert_eq!(doc.undo(), 1);
        doc.assert_accounting();
    }
    assert_eq!(doc.points(0), drawn);
    for _ in 0..5 {
        assert_eq!(doc.redo(), 1);
    }
    assert_eq!(doc.state(), end);
    // The exported file and the constraint helper see the same geometry.
    let reopened = Owned::from_project(&end.0);
    assert_eq!(reopened.points(1), doc.points(1));
    let mut delta = point(-1.0, -1.0);
    assert_eq!(
        unsafe { ep_constrain_object_movement(doc.0, 1, 5000.0, 5000.0, &mut delta) },
        0
    );
    assert_eq!(delta, point(1200.0 - 450.0, 800.0 - 345.0));
    doc.assert_accounting();
}

#[test]
fn an_object_near_an_edge_is_pushed_back_onto_the_page() {
    let doc = Owned::new();
    assert_eq!(doc.stamp(corners(0.0, 0.0, 100.0, 100.0), 2, 0xeebf4e), 0);
    assert_eq!(doc.scale(0, 2.0, 1.0), 1);
    // The centre would give -50..150: the stamp slides to 0..200 instead.
    assert_eq!(doc.points(0), corners(0.0, 0.0, 200.0, 200.0));
    assert!(doc
        .svg()
        .contains("<g transform=\"translate(0 0) scale(2 2)\">"));
    assert_eq!(
        doc.stamp(corners(1100.0, 700.0, 1200.0, 800.0), 2, 0xeebf4e),
        0
    );
    assert_eq!(doc.scale(1, 3.0, 1.0), 1);
    assert_eq!(doc.points(1), corners(900.0, 500.0, 1200.0, 800.0));
    // As large as the page allows, to the last unit.
    assert_eq!(doc.scale(0, 4.0, 1.0), 1);
    assert_eq!(doc.points(0), corners(0.0, 0.0, 800.0, 800.0));
    let full = doc.state();
    assert_eq!(doc.scale(0, 1.001, 1.0), INVALID);
    assert_eq!(doc.state(), full);
    // A stamp keeps its constant width slot.
    assert_eq!(doc.scale(0, 0.5, 2.0), INVALID);
    assert_eq!(doc.state(), full);
    doc.assert_accounting();
}

#[test]
fn points_that_rounding_would_leave_outside_are_brought_back_whole() {
    // Coordinates without an exact half, at each edge of an odd-sized page.
    let doc = Owned::sized(1001, 333);
    let near_edges = [
        point(0.1, 0.3),
        point(1000.9, 332.7),
        point(333.3, 111.1),
        point(0.7, 332.9),
    ];
    assert_eq!(doc.stroke(&near_edges, 0x010203), 0);
    for factor in [0.37, 1.0009, 0.9991, 0.73, 1.369, 0.5, 1.9] {
        let status = doc.scale(0, factor, 3.0);
        assert!(status == 1 || status == INVALID, "{factor}: {status}");
        for point in doc.points(0) {
            assert!((0.0..=1001.0).contains(&point.x), "{factor}: {point:?}");
            assert!((0.0..=333.0).contains(&point.y), "{factor}: {point:?}");
        }
        // Whatever was accepted is a project that reopens identically.
        let bytes = doc.project();
        assert_eq!(Owned::from_project(&bytes).project(), bytes);
    }
    doc.assert_accounting();
}

#[test]
fn invalid_requests_change_nothing() {
    let doc = Owned::new();
    assert_eq!(
        doc.shape(3, corners(100.0, 100.0, 300.0, 200.0), 0x112233, 6.0),
        0
    );
    assert_eq!(
        doc.text(corners(10.0, 10.0, 110.0, 58.0), 0x112233, 40.0, "mot"),
        0
    );
    assert_eq!(
        doc.shape(1, corners(500.0, 500.0, 500.0, 600.0), 0x112233, 6.0),
        0
    );
    let before = doc.state();
    for (index, factor, width) in [
        (9, 1.5, 6.0), // no such object
        (0, f32::NAN, 6.0),
        (0, f32::INFINITY, 6.0),
        (0, 0.0, 6.0),
        (0, -2.0, 6.0),
        (0, 1.0 / 65.0, 6.0), // below the smallest factor
        (0, 65.0, 6.0),       // above the largest factor
        (0, 1.5, 0.0),        // not an outline width
        (0, 1.5, 513.0),
        (0, 1.5, f32::NAN),
        (0, 7.0, 6.0),  // 1400 units wide: larger than the page
        (1, 1.5, 60.0), // a text is resized with its characters
    ] {
        assert_eq!(
            doc.scale(index, factor, width),
            INVALID,
            "{index} {factor} {width}"
        );
    }
    assert_eq!(
        unsafe { ep_scale_object(ptr::null_mut(), 0, 1.5, 6.0) },
        INVALID
    );
    // Factor one with the same width: nothing to do, and history says so.
    assert_eq!(doc.scale(0, 1.0, 6.0), 0);
    assert_eq!(doc.state(), before);
    // Factor one with another width is a real change of the outline.
    assert_eq!(doc.scale(0, 1.0, 8.0), 1);
    assert_eq!(doc.info(0).width, 8.0);
    assert_eq!(doc.points(0), corners(100.0, 100.0, 300.0, 200.0));
    // A vertical line keeps its zero width and scales its length.
    assert_eq!(doc.scale(2, 0.5, 6.0), 1);
    assert_eq!(doc.points(2), corners(500.0, 525.0, 500.0, 575.0));
    doc.assert_accounting();
}

#[test]
fn a_shape_never_collapses_and_the_scale_stays_bounded() {
    let doc = Owned::new();
    assert_eq!(
        doc.shape(2, corners(600.0, 400.0, 600.5, 400.5), 0x112233, 1.0),
        0
    );
    let mut accepted = 0;
    for _ in 0..40 {
        match doc.scale(0, 1.0 / 64.0, 1.0) {
            1 => accepted += 1,
            INVALID => break,
            other => panic!("unexpected status {other}"),
        }
        let points = doc.points(0);
        assert!(points[0].x != points[1].x && points[0].y != points[1].y);
        let bytes = doc.project();
        assert_eq!(Owned::from_project(&bytes).project(), bytes);
    }
    assert!((1..40).contains(&accepted), "{accepted}");
    let small = doc.state();
    assert_eq!(doc.scale(0, 1.0 / 64.0, 1.0), INVALID);
    assert_eq!(doc.state(), small);
    for _ in 0..accepted {
        assert_eq!(doc.undo(), 1);
    }
    assert_eq!(doc.points(0), corners(600.0, 400.0, 600.5, 400.5));

    // A single dot has no size: only its width can change.
    let dot = Owned::new();
    assert_eq!(dot.dot(10.0, 20.0), 0);
    assert_eq!(dot.scale(0, 2.0, 3.0), 0);
    assert_eq!(dot.scale(0, 2.0, 6.0), 1);
    assert_eq!(dot.points(0), [point(10.0, 20.0)]);
    for _ in 0..200 {
        let status = dot.scale(0, 64.0, 6.0);
        assert!(status == 0 || status == INVALID, "{status}");
    }
    assert_eq!(dot.points(0), [point(10.0, 20.0)]);
    dot.assert_accounting();
    doc.assert_accounting();
}

#[test]
fn resizing_respects_layers_snapshots_and_the_history_limit() {
    let doc = Owned::new();
    assert_eq!(
        doc.shape(2, corners(100.0, 100.0, 200.0, 200.0), 0x112233, 4.0),
        0
    );
    assert_eq!(unsafe { ep_add_layer(doc.0) }, 1);
    assert_eq!(
        doc.stamp(corners(300.0, 300.0, 400.0, 400.0), 5, 0x445566),
        0
    );
    assert_eq!(doc.scale(1, 1.5, 1.0), 1);
    assert_eq!(doc.extra(1).layer, 1);
    assert_eq!(doc.extra(1).param, 5);
    assert_eq!(doc.points(1), corners(275.0, 275.0, 425.0, 425.0));
    let (bytes, svg) = doc.snapshot();
    assert_eq!((&bytes, &svg), (&doc.project(), &doc.svg()));
    // Removing and restoring the layer keeps the resized geometry.
    assert_eq!(unsafe { ep_remove_layer(doc.0, 1) }, 1);
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.points(1), corners(275.0, 275.0, 425.0, 425.0));

    let limited = Owned::new();
    assert_eq!(
        limited.shape(2, corners(100.0, 100.0, 200.0, 200.0), 0x112233, 4.0),
        0
    );
    for command in 1..MAX_HISTORY_STEPS {
        let factor = if command % 2 == 1 { 2.0 } else { 0.5 };
        assert_eq!(limited.scale(0, factor, 4.0), 1, "command {command}");
    }
    let full = limited.state();
    assert_eq!(full.2, MAX_HISTORY_STEPS);
    assert_eq!(limited.scale(0, 0.5, 4.0), INVALID);
    assert_eq!(limited.state(), full);
    limited.assert_accounting();
}

#[test]
fn a_dot_changes_width_any_number_of_times_and_never_wears_its_transform() {
    let doc = Owned::new();
    assert_eq!(doc.dot(10.0, 20.0), 0);
    let transform = |doc: &Owned| {
        let stroke = &doc.doc().strokes[0];
        (stroke.scale.to_bits(), stroke.translation.map(f64::to_bits))
    };
    let untouched = transform(&doc);
    // Sixty-four doublings would be far beyond the bound of 1e9 if the dot
    // carried a size: it carries none.
    for step in 0..64 {
        let width = if step % 2 == 0 { 6.0 } else { 3.0 };
        assert_eq!(doc.scale(0, 2.0, width), 1, "step {step}");
        assert_eq!(doc.points(0), [point(10.0, 20.0)]);
        assert_eq!(doc.info(0).width, width);
        assert_eq!(transform(&doc), untouched, "step {step}");
    }
    // The width it already has: nothing to change, whatever the factor.
    let before = doc.state();
    for factor in [0.5, 1.0, 2.0, 64.0] {
        assert_eq!(doc.scale(0, factor, 3.0), 0);
        assert_eq!(doc.state(), before);
    }
    // Several points at one place are a dot too.
    assert_eq!(doc.stroke(&[point(700.0, 300.0); 3], 0x00aa00), 0);
    for _ in 0..40 {
        assert_eq!(doc.scale(1, 64.0, 9.0), 1);
        assert_eq!(doc.scale(1, 64.0, 4.0), 1);
    }
    assert_eq!(doc.points(1), [point(700.0, 300.0); 3]);
    doc.assert_accounting();
}

#[test]
fn what_has_a_size_never_loses_it_and_grows_back_from_its_smallest() {
    let doc = Owned::new();
    let drawn = [
        point(100.0, 100.0),
        point(900.0, 700.0),
        point(300.0, 650.0),
    ];
    assert_eq!(doc.stroke(&drawn, 0x0000ff), 0);
    let mut halvings = 0;
    while doc.scale(0, 0.5, 3.0) == 1 {
        halvings += 1;
        assert!(halvings < 64);
        // Never one point: there is always something left to enlarge.
        let points = doc.points(0);
        assert!(
            points.iter().any(|other| *other != points[0]),
            "collapsed after {halvings} halvings"
        );
    }
    assert!(halvings >= 10, "only {halvings} halvings were accepted");
    // The halving that would bring the points together is refused whole.
    let smallest = doc.state();
    assert_eq!(doc.scale(0, 0.5, 3.0), -1);
    assert_eq!(doc.state(), smallest);

    // A moderate factor applies at once, and every doubling is accepted
    // back to the drawn size.
    assert_eq!(doc.scale(0, 1.25, 3.0), 1);
    assert_eq!(doc.undo(), 1);
    assert_eq!((doc.state().0, doc.state().1), (smallest.0, smallest.1));
    for step in 0..halvings {
        assert_eq!(doc.scale(0, 2.0, 3.0), 1, "doubling {step}");
    }
    for (now, then) in doc.points(0).iter().zip(drawn) {
        assert!((now.x - then.x).abs() < 0.01 && (now.y - then.y).abs() < 0.01);
    }
    doc.assert_accounting();
}

#[test]
fn a_factor_of_one_changes_a_width_and_nothing_of_the_transform() {
    let doc = Owned::new();
    assert_eq!(
        doc.shape(2, corners(100.0, 200.0, 300.0, 280.0), 0x112233, 6.0),
        0
    );
    assert_eq!(doc.scale(0, 1.25, 7.5), 1);
    let stroke = &doc.doc().strokes[0];
    let transform = (stroke.scale.to_bits(), stroke.translation.map(f64::to_bits));
    let points = doc.points(0);
    let before = doc.state();
    assert_eq!(doc.scale(0, 1.0, 7.5), 0);
    assert_eq!(doc.state(), before);
    assert_eq!(doc.scale(0, 1.0, 12.0), 1);
    let stroke = &doc.doc().strokes[0];
    assert_eq!(
        (stroke.scale.to_bits(), stroke.translation.map(f64::to_bits)),
        transform
    );
    assert_eq!(doc.points(0), points);
    assert_eq!(doc.info(0).width, 12.0);
    assert_eq!(doc.undo(), 1);
    assert_eq!((doc.state().0, doc.state().1), (before.0, before.1));
    assert_eq!(doc.info(0).width, 7.5);
}

#[test]
fn a_resize_too_small_to_move_a_rounded_coordinate_is_still_kept() {
    let doc = Owned::new();
    // Two points one step of f32 apart: no coordinate can show a growth of a
    // tenth of a millionth, yet twenty-four million of them double the size.
    let near = f32::from_bits(500.0f32.to_bits() + 2);
    assert_eq!(doc.stroke(&[point(500.0, 400.0), point(near, 400.0)], 0), 0);
    let tiny = f32::from_bits(1.0f32.to_bits() + 1);
    let before = doc.state();
    let scale = doc.doc().strokes[0].scale;
    assert_eq!(doc.scale(0, tiny, 3.0), 1);
    assert!(doc.doc().strokes[0].scale > scale);
    assert_eq!(doc.points(0), [point(500.0, 400.0), point(near, 400.0)]);
    assert_eq!(unsafe { ep_object_revision(doc.0, 0) }, 2);
    assert_eq!(doc.undo(), 1);
    assert_eq!((doc.state().0, doc.state().1), (before.0, before.1));
    assert_eq!(doc.doc().strokes[0].scale, scale);
    assert_eq!(unsafe { ep_object_revision(doc.0, 0) }, 1);
    doc.assert_accounting();
}
