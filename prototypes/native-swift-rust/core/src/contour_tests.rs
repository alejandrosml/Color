//! Closed contours (kind 6): a list of points like a freehand stroke, closed
//! and fillable like a rectangle. No function of the interface draws a new
//! one: a colouring page or a project of version 5 brings it, and
//! duplicating one copies it. These tests read them from version 5 bytes and
//! then go through the C functions, as the interface does.
use super::*;
use crate::test_support::*;

const INK: u32 = 0x112233;

fn square() -> Vec<EpPoint> {
    vec![
        point(100.0, 100.0),
        point(300.0, 100.0),
        point(300.0, 250.0),
        point(100.0, 250.0),
    ]
}

fn style(doc: &Owned, index: usize) -> EpObjectStyle {
    let mut style = EpObjectStyle {
        kind: 99,
        fill_enabled: 99,
        fill_rgb: 99,
    };
    assert_eq!(unsafe { ep_object_style(doc.0, index, &mut style) }, 0);
    style
}

fn contour_style(fill: Option<u32>) -> EpObjectStyle {
    EpObjectStyle {
        kind: KIND_CONTOUR,
        fill_enabled: u32::from(fill.is_some()),
        fill_rgb: fill.unwrap_or(0),
    }
}

#[test]
fn a_contour_needs_three_points_whose_extent_has_a_width_and_a_height() {
    let tiny = f32::from_bits(1);
    for (points, valid) in [
        (square(), true),
        (
            vec![point(0.0, 0.0), point(tiny, 0.0), point(0.0, tiny)],
            true,
        ),
        // A diagonal encloses nothing, but its box has a size, like a
        // rectangle's: the rule is the box, as for every other shape.
        (
            vec![point(0.0, 0.0), point(1.0, 1.0), point(2.0, 2.0)],
            true,
        ),
        (vec![point(0.0, 0.0), point(5.0, 5.0)], false),
        (
            vec![point(0.0, 10.0), point(5.0, 10.0), point(9.0, 10.0)],
            false,
        ),
        (
            vec![point(10.0, 0.0), point(10.0, 5.0), point(10.0, 9.0)],
            false,
        ),
        (vec![point(3.0, 3.0); 3], false),
        (Vec::new(), false),
    ] {
        assert_eq!(
            valid_shape_points(KIND_CONTOUR, &points),
            valid,
            "{points:?}"
        );
    }
    // Filled or not, in any 24-bit colour; never a kind beyond it.
    assert!(valid_style(contour_style(None)));
    assert!(valid_style(contour_style(Some(0))));
    assert!(valid_style(contour_style(Some(0xffffff))));
    for wrong in [
        contour_style(Some(0x1000000)),
        EpObjectStyle {
            kind: KIND_CONTOUR,
            fill_enabled: 0,
            fill_rgb: 1,
        },
        EpObjectStyle {
            kind: KIND_CONTOUR,
            fill_enabled: 2,
            fill_rgb: 0,
        },
        EpObjectStyle {
            kind: KIND_CONTOUR + 1,
            fill_enabled: 0,
            fill_rgb: 0,
        },
    ] {
        assert!(!valid_style(wrong), "{wrong:?}");
    }
    // What one added contour must be: on the page, an outline width, no
    // parameter and no characters.
    let doc = Owned::new();
    let check = |points: &[EpPoint], width: f32, param: u32, text: &[u8]| {
        valid_new_object(
            doc.doc(),
            points,
            INK,
            width,
            contour_style(Some(1)),
            param,
            text,
        )
    };
    assert!(check(&square(), 6.0, 0, &[]));
    let mut longest = vec![point(1.0, 2.0); MAX_STROKE_POINTS];
    longest[0] = point(3.0, 4.0);
    assert!(check(&longest, 0.1, 0, &[]));
    longest.push(point(5.0, 6.0));
    assert!(!check(&longest, 0.1, 0, &[]));
    assert!(!check(
        &[point(0.0, 0.0), point(1200.5, 0.0), point(5.0, 5.0)],
        6.0,
        0,
        &[]
    ));
    assert!(!check(&square(), 0.0, 0, &[]));
    assert!(!check(&square(), 512.5, 0, &[]));
    assert!(!check(&square(), 6.0, 1, &[]));
    assert!(!check(&square(), 6.0, 0, b"mot"));
    // Two points cannot make one: the function of two-point shapes refuses
    // kind 6 whatever they are, and changes nothing.
    assert_eq!(doc.dot(5.0, 5.0), 0);
    assert_eq!(doc.undo(), 1);
    let before = doc.state();
    let corners = [point(10.0, 10.0), point(50.0, 40.0)];
    for fill in [None, Some(0xffffff)] {
        assert_eq!(
            unsafe { ep_add_shape(doc.0, corners.as_ptr(), &contour_style(fill), INK, 6.0) },
            INVALID
        );
    }
    assert_eq!(doc.state(), before);
}

#[test]
fn a_contour_is_a_closed_path_in_the_svg_and_a_version_5_record() {
    let doc = Owned::contour(&square(), INK, 4.0, Some(0xaabbcc));
    assert_eq!(doc.kind(0), KIND_CONTOUR);
    assert_eq!(style(&doc, 0), contour_style(Some(0xaabbcc)));
    assert_eq!(
        doc.info(0),
        EpStrokeInfo {
            rgb: INK,
            width: 4.0,
            point_count: 4
        }
    );
    assert_eq!(doc.points(0), square());
    assert_eq!(doc.extra(0).layer, 0);
    let svg = doc.svg();
    assert!(
        svg.contains(
            "<path d=\"M100 100 L300 100 L300 250 L100 250 Z\" fill=\"#aabbcc\" \
             stroke=\"#112233\" stroke-width=\"4\" stroke-linecap=\"round\" \
             stroke-linejoin=\"round\"/>"
        ),
        "{svg}"
    );
    assert!(!svg.contains("<g"));
    // The writer gives back the very bytes it read, and so do snapshots.
    let bytes = doc.project();
    assert_eq!(bytes, contour_project(&square(), INK, 4.0, Some(0xaabbcc)));
    assert_eq!(u16::from_le_bytes([bytes[8], bytes[9]]), 5);
    assert_eq!(doc.snapshot(), (bytes.clone(), svg.clone()));
    let reopened = Owned::from_project(&bytes);
    assert_eq!(reopened.project(), bytes);
    assert_eq!(reopened.svg(), svg);
    // Without its fill, the inside of the outline stays empty.
    let outline = Owned::contour(&square(), INK, 4.0, None);
    assert!(outline.svg().contains(
        "<path d=\"M100 100 L300 100 L300 250 L100 250 Z\" fill=\"none\" stroke=\"#112233\""
    ));
    // A loaded contour is an ordinary added object: undo takes it away.
    assert_eq!(
        unsafe { (ep_undo_count(doc.0), ep_redo_count(doc.0)) },
        (1, 0)
    );
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.count(), 0);
    assert_eq!(doc.redo(), 1);
    assert_eq!(doc.project(), bytes);
    doc.assert_accounting();
}

#[test]
fn moving_constraining_and_duplicating_a_contour_take_all_its_points() {
    let doc = Owned::contour(&square(), INK, 4.0, Some(0xaabbcc));
    let original = doc.state();
    let token = unsafe { ep_object_revision(doc.0, 0) };
    unsafe {
        assert_eq!(ep_move_object(doc.0, 0, 10.0, 20.0), 1);
    }
    let moved: Vec<_> = square()
        .iter()
        .map(|p| point(p.x + 10.0, p.y + 20.0))
        .collect();
    assert_eq!(doc.points(0), moved);
    assert_ne!(unsafe { ep_object_revision(doc.0, 0) }, token);
    // The constraint counts every point, not the first two.
    let mut delta = point(-1.0, -1.0);
    unsafe {
        assert_eq!(
            ep_constrain_object_movement(doc.0, 0, 5000.0, 5000.0, &mut delta),
            0
        );
    }
    assert_eq!(delta, point(1200.0 - 310.0, 800.0 - 270.0));
    unsafe {
        assert_eq!(ep_move_object(doc.0, 0, delta.x, delta.y), 1);
        assert_eq!(ep_move_object(doc.0, 0, 0.5, 0.0), INVALID);
        assert_eq!(ep_move_object(doc.0, 0, 0.0, 0.5), INVALID);
    }
    assert_eq!(doc.points(0)[2], point(1200.0, 800.0));
    // A copy is a contour of its own, with the same fill, on the same layer.
    unsafe {
        assert_eq!(ep_duplicate_object(doc.0, 0, -500.0, -300.0), 1);
    }
    assert_eq!(doc.count(), 2);
    assert_eq!(style(&doc, 1), contour_style(Some(0xaabbcc)));
    assert_eq!(
        doc.points(1),
        [
            point(500.0, 350.0),
            point(700.0, 350.0),
            point(700.0, 500.0),
            point(500.0, 500.0)
        ]
    );
    assert_eq!(doc.extra(1).layer, 0);
    assert_eq!(doc.doc().active_contours, 2);
    let copied = doc.project();
    assert_eq!(copied[8], 5);
    assert_eq!(Owned::from_project(&copied).project(), copied);
    assert_eq!(doc.snapshot().0, copied);
    // Every step comes back exactly.
    for _ in 0..3 {
        assert_eq!(doc.undo(), 1);
    }
    assert_eq!(doc.state(), {
        let mut state = original.clone();
        state.3 = 3;
        state
    });
    assert_eq!(unsafe { ep_object_revision(doc.0, 0) }, token);
    for _ in 0..3 {
        assert_eq!(doc.redo(), 1);
    }
    assert_eq!(doc.project(), copied);
    doc.assert_accounting();
}

#[test]
fn resizing_a_contour_scales_every_point_around_its_centre() {
    let doc = Owned::contour(&square(), INK, 4.0, None);
    let before = doc.state();
    // 200 x 150 around (200, 175) becomes 400 x 300 around the same centre.
    assert_eq!(doc.scale(0, 2.0, 8.0), 1);
    assert_eq!(
        doc.points(0),
        [
            point(0.0, 25.0),
            point(400.0, 25.0),
            point(400.0, 325.0),
            point(0.0, 325.0)
        ]
    );
    assert_eq!(doc.info(0).width, 8.0);
    assert!(doc
        .svg()
        .contains("<path d=\"M0 25 L400 25 L400 325 L0 325 Z\" fill=\"none\""));
    let grown = doc.project();
    assert_eq!(grown[8], 5);
    assert_eq!(Owned::from_project(&grown).points(0), doc.points(0));
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.state(), {
        let mut state = before.clone();
        state.3 = 1;
        state
    });
    assert_eq!(doc.redo(), 1);
    assert_eq!(doc.project(), grown);
    // Larger than the page: refused whole.
    let full = doc.state();
    assert_eq!(doc.scale(0, 4.0, 8.0), INVALID);
    assert_eq!(doc.state(), full);
    doc.assert_accounting();
}

#[test]
fn a_contour_never_collapses_when_resized_or_moved() {
    // A triangle half a unit wide: halving it again and again stops before
    // its extent loses its width or its height.
    let doc = Owned::contour(
        &[
            point(600.0, 400.0),
            point(600.5, 400.0),
            point(600.0, 400.5),
        ],
        INK,
        1.0,
        Some(0xffffff),
    );
    let mut accepted = 0;
    for _ in 0..40 {
        match doc.scale(0, 1.0 / 64.0, 1.0) {
            1 => accepted += 1,
            INVALID => break,
            other => panic!("unexpected status {other}"),
        }
        assert!(valid_shape_points(KIND_CONTOUR, &doc.points(0)));
        let bytes = doc.project();
        assert_eq!(Owned::from_project(&bytes).project(), bytes);
    }
    assert!((1..40).contains(&accepted), "{accepted}");
    let smallest = doc.state();
    assert_eq!(doc.scale(0, 1.0 / 64.0, 1.0), INVALID);
    assert_eq!(doc.state(), smallest);
    for _ in 0..accepted {
        assert_eq!(doc.undo(), 1);
    }
    assert_eq!(doc.points(0)[1], point(600.5, 400.0));

    // A contour one step of f32 wide collapses when moved far away, where
    // that step no longer exists: moving and copying it are refused.
    let tiny = f32::from_bits(1);
    let doc = Owned::contour(
        &[point(0.0, 0.0), point(tiny, 0.0), point(0.0, tiny)],
        INK,
        1.0,
        None,
    );
    let before = doc.state();
    let mut delta = point(-9.0, -9.0);
    unsafe {
        assert_eq!(ep_move_object(doc.0, 0, 100.0, 100.0), INVALID);
        assert_eq!(ep_duplicate_object(doc.0, 0, 100.0, 100.0), INVALID);
        assert_eq!(
            ep_constrain_object_movement(doc.0, 0, 100.0, 100.0, &mut delta),
            INVALID
        );
    }
    assert_eq!(delta, point(-9.0, -9.0));
    assert_eq!(doc.state(), before);
    doc.assert_accounting();
}

#[test]
fn restyling_a_contour_changes_its_outline_and_its_fill() {
    let doc = Owned::contour(&square(), INK, 4.0, None);
    let drawing = |doc: &Owned| (doc.project(), doc.svg());
    let mut states = vec![drawing(&doc)];
    unsafe {
        assert_eq!(ep_set_object_style(doc.0, 0, 0x445566, 6.0, 1, 0x00ff00), 1);
        states.push(drawing(&doc));
        assert!(doc
            .svg()
            .contains("Z\" fill=\"#00ff00\" stroke=\"#445566\" stroke-width=\"6\""));
        assert_eq!(style(&doc, 0), contour_style(Some(0x00ff00)));
        assert_eq!(ep_set_object_style(doc.0, 0, 0x445566, 6.0, 1, 0), 1);
        states.push(drawing(&doc));
        assert!(doc.svg().contains("Z\" fill=\"#000000\""));
        assert_eq!(ep_set_object_style(doc.0, 0, 0x445566, 6.0, 0, 0), 1);
        states.push(drawing(&doc));
        assert!(doc.svg().contains("Z\" fill=\"none\""));
        // The same style again is nothing to do; wrong values change nothing.
        let now = doc.state();
        assert_eq!(ep_set_object_style(doc.0, 0, 0x445566, 6.0, 0, 0), 0);
        for (rgb, width, enabled, fill) in [
            (0x1000000, 6.0, 0, 0),
            (0, 0.0, 0, 0),
            (0, f32::NAN, 0, 0),
            (0, 6.0, 0, 1),
            (0, 6.0, 2, 0),
            (0, 6.0, 1, 0x1000000),
        ] {
            assert_eq!(
                ep_set_object_style(doc.0, 0, rgb, width, enabled, fill),
                INVALID
            );
        }
        assert_eq!(doc.state(), now);
    }
    for expected in states[..states.len() - 1].iter().rev() {
        assert_eq!(doc.undo(), 1);
        assert_eq!(&drawing(&doc), expected);
    }
    for expected in states.iter().skip(1) {
        assert_eq!(doc.redo(), 1);
        assert_eq!(&drawing(&doc), expected);
    }
    doc.assert_accounting();
}

#[test]
fn only_a_contour_or_a_locked_layer_asks_for_version_5() {
    let doc = Owned::contour(&square(), INK, 4.0, Some(0xffffff));
    assert_eq!(doc.project()[8], 5);
    // Hidden, the contour is still in the drawing, and still needs v5.
    unsafe {
        assert_eq!(ep_set_layer_visible(doc.0, 0, 0), 1);
    }
    assert_eq!(doc.project()[8], 5);
    assert!(!doc.svg().contains("<path"));
    assert_eq!(doc.undo(), 1);
    // Without its contour the drawing is plain again: version 2, the bytes
    // of a new sheet.
    unsafe {
        assert_eq!(ep_remove_object(doc.0, 0), 1);
    }
    assert_eq!(doc.project(), Owned::new().project());
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.project()[8], 5);
    // With a text beside it: still version 5, which carries texts too.
    assert_eq!(
        doc.text(corners(500.0, 500.0, 700.0, 548.0), 0, 40.0, "cinq"),
        0
    );
    let both = doc.project();
    assert_eq!(both[8], 5);
    let reopened = Owned::from_project(&both);
    assert_eq!(reopened.project(), both);
    assert_eq!(reopened.object_text(1), "cinq");
    // A drawing with every feature of version 4 and none of version 5 keeps
    // writing version 4: the contour alone made the difference.
    unsafe {
        assert_eq!(ep_remove_object(doc.0, 0), 1);
    }
    assert_eq!(doc.project()[8], 4);
    doc.assert_accounting();
}

#[test]
fn malformed_contour_records_are_refused_even_with_a_valid_checksum() {
    let good = contour_project(&square(), INK, 4.0, Some(0xaabbcc));
    assert!(Owned::try_from_project(&good).is_ok());
    let record = 56 + 8;
    let check = |name: &str, change: &dyn Fn(&mut Vec<u8>)| {
        let mut bytes = good.clone();
        change(&mut bytes);
        assert_eq!(
            Owned::try_from_project(&resealed(bytes)).err(),
            Some(INVALID),
            "{name}"
        );
    };
    check("a contour in version 4", &|b| b[8] = 4);
    check("an unknown kind", &|b| {
        put_u32(b, record + 12, KIND_CONTOUR + 1)
    });
    check("a fill flag of 2", &|b| put_u32(b, record + 16, 2));
    check("a fill colour without fill", &|b| {
        put_u32(b, record + 16, 0);
        put_u32(b, record + 20, 1);
    });
    check("a fill colour beyond 24 bits", &|b| {
        put_u32(b, record + 20, 0x0100_0000)
    });
    check("a parameter", &|b| put_u32(b, record + 28, 1));
    check("a width of zero", &|b| put_u32(b, record + 4, 0));
    check("a point beyond the sheet", &|b| {
        b[record + 36..record + 40].copy_from_slice(&1200.5f32.to_le_bytes())
    });
    check("a point that is not a number", &|b| {
        b[record + 44..record + 48].copy_from_slice(&f32::NAN.to_le_bytes())
    });
    // Fewer than three points, or points on one line: no contour.
    for points in [
        vec![point(100.0, 100.0), point(200.0, 200.0)],
        vec![point(100.0, 100.0)],
        vec![
            point(100.0, 100.0),
            point(200.0, 100.0),
            point(300.0, 100.0),
        ],
        vec![
            point(100.0, 100.0),
            point(100.0, 200.0),
            point(100.0, 300.0),
        ],
    ] {
        assert_eq!(
            Owned::try_from_project(&contour_project(&points, INK, 4.0, None)).err(),
            Some(INVALID),
            "{points:?}"
        );
    }
}
