// SPDX-License-Identifier: MIT
//! What an object of Color 1.1 may be, and how its paint changes and comes
//! back with undo.

use super::*;
use crate::test_support::*;

fn turned(rotation: f32, mirror: u32) -> EpObjectLook {
    EpObjectLook {
        rotation,
        mirror,
        ..PLAIN_LOOK
    }
}

const LINE: [EpPoint; 3] = [
    EpPoint { x: 10.0, y: 10.0 },
    EpPoint { x: 50.0, y: 20.0 },
    EpPoint { x: 90.0, y: 15.0 },
];

#[test]
fn a_look_must_fit_its_object() {
    let doc = Owned::new();
    let before = doc.state();
    let box_points = corners(10.0, 10.0, 60.0, 50.0);
    let gradient = EpObjectLook {
        gradient: 1,
        gradient_rgb: 0x00ff_0000,
        gradient_points: [0.0, 0.0, 1.0, 1.0],
        ..PLAIN_LOOK
    };
    for (spec, why) in [
        (
            Spec {
                points: &LINE,
                look: turned(f32::NAN, 0),
                ..Spec::default()
            },
            "rotation",
        ),
        (
            Spec {
                points: &LINE,
                look: turned(-std::f32::consts::PI, 0),
                ..Spec::default()
            },
            "-pi",
        ),
        (
            Spec {
                points: &LINE,
                look: turned(0.0, 4),
                ..Spec::default()
            },
            "mirror",
        ),
        (
            Spec {
                points: &LINE,
                look: EpObjectLook {
                    tool: 5,
                    ..PLAIN_LOOK
                },
                ..Spec::default()
            },
            "unknown tool",
        ),
        (
            Spec {
                points: &box_points,
                kind: 2,
                look: EpObjectLook {
                    tool: TOOL_FELT,
                    ..PLAIN_LOOK
                },
                ..Spec::default()
            },
            "tool of a rectangle",
        ),
        (
            Spec {
                points: &LINE,
                look: EpObjectLook {
                    tool: TOOL_FELT,
                    seed: 1,
                    ..PLAIN_LOOK
                },
                ..Spec::default()
            },
            "seed without scattering",
        ),
        (
            Spec {
                points: &box_points,
                kind: 2,
                look: gradient,
                ..Spec::default()
            },
            "no fill",
        ),
        (
            Spec {
                points: &box_points,
                kind: 2,
                fill: Some(1),
                look: EpObjectLook {
                    gradient_points: [0.5, 0.5, 0.5, 0.5],
                    ..gradient
                },
                ..Spec::default()
            },
            "flat gradient",
        ),
        (
            Spec {
                points: &box_points,
                kind: 2,
                fill: Some(1),
                look: EpObjectLook {
                    gradient_points: [0.0, 0.0, 1.5, 1.0],
                    ..gradient
                },
                ..Spec::default()
            },
            "outside the box",
        ),
        (
            Spec {
                points: &LINE,
                pressures: &[1, 0, 2],
                ..Spec::default()
            },
            "zero pressure",
        ),
        (
            Spec {
                points: &box_points,
                kind: 2,
                pressures: &[1, 2],
                ..Spec::default()
            },
            "pressures of a box",
        ),
        (
            Spec {
                points: &LINE,
                kind: KIND_CONTOUR,
                rings: &[3],
                ..Spec::default()
            },
            "one ring said",
        ),
        (
            Spec {
                points: &[LINE[0], LINE[1], LINE[2], LINE[0], LINE[1], LINE[2]],
                kind: KIND_CONTOUR,
                rings: &[3, 2],
                ..Spec::default()
            },
            "rings that do not add up",
        ),
        (
            Spec {
                points: &LINE,
                rings: &[3],
                ..Spec::default()
            },
            "rings of a stroke",
        ),
        (
            Spec {
                points: &LINE,
                kind: KIND_TEXT,
                ..Spec::default()
            },
            "text without characters",
        ),
        (
            Spec {
                points: &LINE,
                text: "abc",
                ..Spec::default()
            },
            "characters of a stroke",
        ),
        (
            Spec {
                points: &box_points,
                kind: KIND_TEXT,
                width: 20.0,
                param: FONT_COUNT,
                text: "abc",
                ..Spec::default()
            },
            "unknown font",
        ),
    ] {
        assert_eq!(doc.add(&spec), INVALID, "{why}");
        assert_eq!(doc.state(), before, "{why}");
    }
    // The same, made right, are accepted.
    assert_eq!(
        doc.add(&Spec {
            points: &LINE,
            look: turned(std::f32::consts::PI, 3),
            ..Spec::default()
        }),
        0
    );
    assert_eq!(
        doc.add(&Spec {
            points: &box_points,
            kind: 2,
            fill: Some(1),
            look: gradient,
            ..Spec::default()
        }),
        0
    );
    assert_eq!(
        doc.add(&Spec {
            points: &[LINE[0], LINE[1], LINE[2], LINE[0], LINE[1], LINE[2]],
            kind: KIND_CONTOUR,
            rings: &[3, 3],
            ..Spec::default()
        }),
        0
    );
    doc.assert_accounting();
}

#[test]
fn the_bottom_of_the_active_layer_is_under_what_it_holds() {
    let doc = Owned::new();
    assert_eq!(doc.stroke(&LINE, 1), 0);
    assert_eq!(doc.stroke(&LINE, 2), 0);
    unsafe { assert_eq!(ep_add_layer(doc.0), 1) };
    assert_eq!(doc.stroke(&LINE, 3), 0);
    assert_eq!(
        doc.add(&Spec {
            points: &LINE,
            rgb: 4,
            bottom: true,
            ..Spec::default()
        }),
        0
    );
    let colours: Vec<u32> = (0..doc.count()).map(|i| doc.info(i).rgb).collect();
    // Under the third stroke, on the new layer, above the first layer.
    assert_eq!(colours, [1, 2, 4, 3]);
    assert_eq!(doc.undo(), 1);
    let colours: Vec<u32> = (0..doc.count()).map(|i| doc.info(i).rgb).collect();
    assert_eq!(colours, [1, 2, 3]);
    assert_eq!(doc.redo(), 1);
    assert_eq!(doc.info(2).rgb, 4);
    doc.assert_accounting();
}

#[test]
fn a_zone_of_the_paint_pot_is_a_contour_that_says_so() {
    let doc = Owned::new();
    let zone = EpObjectLook {
        tool: TOOL_ZONE,
        ..PLAIN_LOOK
    };
    let square = [
        EpPoint { x: 10.0, y: 10.0 },
        EpPoint { x: 60.0, y: 10.0 },
        EpPoint { x: 60.0, y: 50.0 },
        EpPoint { x: 10.0, y: 50.0 },
    ];
    let before = doc.state();
    // Only a contour carries it; no brush draws with it.
    for (points, kind) in [(&LINE[..], 0), (&LINE[..2], 1), (&square[..2], 2)] {
        assert_eq!(
            doc.add(&Spec {
                points,
                kind,
                look: zone,
                ..Spec::default()
            }),
            INVALID,
            "kind {kind}"
        );
    }
    assert_eq!(doc.state(), before);
    assert_eq!(
        doc.add(&Spec {
            points: &square,
            kind: KIND_CONTOUR,
            fill: Some(0x00ff_8800),
            rgb: 0x00ff_8800,
            width: 0.5,
            look: zone,
            ..Spec::default()
        }),
        0
    );
    assert_eq!(doc.look(0).tool, TOOL_ZONE);
    // Kept by version 6, and read back the same.
    let bytes = doc.v6(true);
    let reopened = Owned::from_project(&bytes);
    assert_eq!(reopened.look(0).tool, TOOL_ZONE);
    assert_eq!(reopened.v6(true), bytes);
    // A zone is no stroke: the core paints it as the contour it is.
    let (mut marks, mut points) = (0usize, 0usize);
    let status = unsafe {
        crate::marks::ep_stroke_marks(
            square.as_ptr(),
            square.len(),
            std::ptr::null(),
            3.0,
            0,
            TOOL_ZONE,
            0,
            0,
            std::ptr::null_mut(),
            0,
            std::ptr::null_mut(),
            0,
            &mut marks,
            &mut points,
        )
    };
    assert_eq!(status, INVALID);
    doc.assert_accounting();
}

#[test]
fn a_new_object_may_go_just_above_one_of_its_layer() {
    let doc = Owned::new();
    assert_eq!(doc.stroke(&LINE, 1), 0);
    assert_eq!(doc.stroke(&LINE, 2), 0);
    unsafe { assert_eq!(ep_add_layer(doc.0), 1) };
    assert_eq!(doc.stroke(&LINE, 3), 0);
    assert_eq!(doc.stroke(&LINE, 4), 0);
    let state = (doc.v6(true), doc.svg());
    // Out of the drawing, on another layer than the active one, or in a
    // batch: refused, and nothing changes.
    for above in [4, 0, 1] {
        assert_eq!(
            doc.add(&Spec {
                points: &LINE,
                rgb: 9,
                above: Some(above),
                ..Spec::default()
            }),
            INVALID,
            "above {above}"
        );
    }
    assert_eq!(
        doc.add_all(&[
            Spec {
                points: &LINE,
                rgb: 9,
                above: Some(2),
                ..Spec::default()
            },
            Spec {
                points: &LINE,
                rgb: 10,
                ..Spec::default()
            },
        ]),
        INVALID
    );
    assert_eq!((doc.v6(true), doc.svg()), state);
    assert_eq!(
        doc.add(&Spec {
            points: &LINE,
            rgb: 5,
            above: Some(2),
            ..Spec::default()
        }),
        0
    );
    let colours: Vec<u32> = (0..doc.count()).map(|i| doc.info(i).rgb).collect();
    assert_eq!(colours, [1, 2, 3, 5, 4]);
    assert_eq!(doc.undo(), 1);
    assert_eq!((doc.v6(true), doc.svg()), state);
    assert_eq!(doc.redo(), 1);
    assert_eq!(doc.info(3).rgb, 5);
    doc.assert_accounting();
}

#[test]
fn paint_changes_together_and_comes_back_with_undo() {
    let doc = Owned::new();
    let box_points = corners(10.0, 10.0, 60.0, 50.0);
    assert_eq!(
        doc.add(&Spec {
            points: &box_points,
            kind: 3,
            ..Spec::default()
        }),
        0
    );
    let before = doc.state();
    let filled = EpObjectStyle {
        kind: 3,
        fill_enabled: 1,
        fill_rgb: 0x00aa_bbcc,
    };
    let gradient = EpObjectLook {
        gradient: 2,
        gradient_rgb: 0x0001_0203,
        gradient_points: [0.5, 0.5, 1.0, 0.5],
        rotation: 0.25,
        ..PLAIN_LOOK
    };
    unsafe {
        assert_eq!(ep_set_object_paint(doc.0, 0, &filled, &gradient), 1);
        assert_eq!(ep_set_object_paint(doc.0, 0, &filled, &gradient), 0);
        // A gradient is not taken from its fill by the older function.
        assert_eq!(
            ep_set_object_style(doc.0, 0, 0x0012_3456, 3.0, 0, 0),
            INVALID
        );
        // Another kind is refused.
        let other = EpObjectStyle { kind: 2, ..filled };
        assert_eq!(ep_set_object_paint(doc.0, 0, &other, &gradient), INVALID);
    }
    assert_eq!(doc.look(0), gradient);
    doc.assert_accounting();
    assert_eq!(unsafe { ep_project_size(doc.0) }, 0);
    assert_eq!(doc.undo(), 1);
    let after = doc.state();
    assert_eq!(
        (&after.0, &after.1, after.2),
        (&before.0, &before.1, before.2)
    );
    assert_eq!(doc.look(0), PLAIN_LOOK);
    doc.assert_accounting();
    assert_eq!(doc.redo(), 1);
    assert_eq!(doc.look(0), gradient);
    doc.assert_accounting();
}

#[test]
fn a_zone_of_a_page_changes_only_the_colour_and_gradient_of_its_fill() {
    let pointer = ep_document_from_page(0);
    assert!(!pointer.is_null());
    let doc = Owned(pointer);
    let zone = (0..doc.count())
        .find(|&index| {
            doc.kind(index) == KIND_CONTOUR && doc.doc().locked(doc.doc().strokes[index].layer)
        })
        .expect("a zone of the page");
    let fill = EpObjectStyle {
        kind: KIND_CONTOUR,
        fill_enabled: 1,
        fill_rgb: 0x00ff_0000,
    };
    let gradient = EpObjectLook {
        gradient: 1,
        gradient_rgb: 0x0000_00ff,
        gradient_points: [0.0, 0.0, 0.0, 1.0],
        ..PLAIN_LOOK
    };
    unsafe {
        assert_eq!(ep_set_object_paint(doc.0, zone, &fill, &gradient), 1);
        let turned = EpObjectLook {
            rotation: 1.0,
            ..gradient
        };
        assert_eq!(ep_set_object_paint(doc.0, zone, &fill, &turned), INVALID);
        let without = EpObjectStyle {
            fill_enabled: 0,
            fill_rgb: 0,
            ..fill
        };
        assert_eq!(
            ep_set_object_paint(doc.0, zone, &without, &PLAIN_LOOK),
            INVALID
        );
    }
    assert_eq!(doc.look(zone), gradient);
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.look(zone), PLAIN_LOOK);
    doc.assert_accounting();
}

#[test]
fn pressures_and_rings_are_copied_whole_or_not_at_all() {
    let doc = Owned::new();
    assert_eq!(
        doc.add(&Spec {
            points: &LINE,
            pressures: &[9, 99, 199],
            ..Spec::default()
        }),
        0
    );
    let ring = [
        LINE[0],
        LINE[1],
        LINE[2],
        point(20.0, 30.0),
        point(40.0, 30.0),
        point(30.0, 45.0),
    ];
    assert_eq!(
        doc.add(&Spec {
            points: &ring,
            kind: KIND_CONTOUR,
            rings: &[3, 3],
            ..Spec::default()
        }),
        0
    );
    unsafe {
        assert_eq!(ep_object_pressure_count(doc.0, 0), 3);
        assert_eq!(ep_object_pressure_count(doc.0, 1), 0);
        assert_eq!(ep_object_pressure_count(doc.0, 2), 0);
        let mut pressures = [0u8; 3];
        assert_eq!(ep_copy_pressures(doc.0, 0, pressures.as_mut_ptr(), 3), 3);
        assert_eq!(pressures, [9, 99, 199]);
        let mut short = [0u8; 2];
        assert_eq!(ep_copy_pressures(doc.0, 0, short.as_mut_ptr(), 2), 0);
        assert_eq!(short, [0, 0]);
        assert_eq!(ep_object_ring_count(doc.0, 1), 2);
        let mut rings = [0u32; 2];
        assert_eq!(ep_copy_rings(doc.0, 1, rings.as_mut_ptr(), 2), 2);
        assert_eq!(rings, [3, 3]);
        assert_eq!(ep_copy_rings(doc.0, 0, rings.as_mut_ptr(), 2), 0);
        assert_eq!(ep_copy_rings(ptr::null(), 0, rings.as_mut_ptr(), 2), 0);
    }
    // A duplicate keeps them.
    unsafe { assert_eq!(ep_duplicate_object(doc.0, 0, 5.0, 5.0), 1) };
    assert_eq!(unsafe { ep_object_pressure_count(doc.0, 2) }, 3);
    doc.assert_accounting();
}

#[test]
fn the_svg_turns_mirrors_fills_and_marks_as_the_sheet_does() {
    let doc = Owned::new();
    assert_eq!(
        doc.add(&Spec {
            points: &corners(100.0, 100.0, 300.0, 200.0),
            kind: 2,
            fill: Some(0x00ff_0000),
            look: EpObjectLook {
                rotation: std::f32::consts::FRAC_PI_2,
                mirror: 1,
                gradient: 1,
                gradient_rgb: 0x0000_00ff,
                gradient_points: [0.0, 0.0, 1.0, 0.0],
                ..PLAIN_LOOK
            },
            ..Spec::default()
        }),
        0
    );
    let ring = [
        point(400.0, 400.0),
        point(600.0, 400.0),
        point(600.0, 600.0),
        point(400.0, 600.0),
        point(450.0, 450.0),
        point(550.0, 450.0),
        point(500.0, 550.0),
    ];
    assert_eq!(
        doc.add(&Spec {
            points: &ring,
            kind: KIND_CONTOUR,
            fill: Some(0x0012_ab34),
            rings: &[4, 3],
            ..Spec::default()
        }),
        0
    );
    assert_eq!(
        doc.add(&Spec {
            points: &LINE,
            look: EpObjectLook {
                tool: TOOL_FELT,
                ..PLAIN_LOOK
            },
            ..Spec::default()
        }),
        0
    );
    assert_eq!(
        doc.add(&Spec {
            points: &LINE,
            look: EpObjectLook {
                tool: TOOL_CONFETTI,
                seed: 5,
                ..PLAIN_LOOK
            },
            width: 20.0,
            ..Spec::default()
        }),
        0
    );
    assert_eq!(
        doc.add(&Spec {
            points: &corners(700.0, 100.0, 900.0, 150.0),
            kind: KIND_TEXT,
            width: 30.0,
            param: 4,
            text: "école",
            ..Spec::default()
        }),
        0
    );
    let svg = doc.svg();
    assert!(
        svg.contains(
            "<g transform=\"translate(200 150) rotate(90) scale(-1 1) translate(-200 -150)\">"
        ),
        "{svg}"
    );
    assert!(svg.contains("<linearGradient id=\"degrade-1\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\">"));
    assert!(svg.contains("fill=\"url(#degrade-1)\""));
    assert!(svg.contains("<stop offset=\"0\" stop-color=\"#ff0000\"/>"));
    assert!(svg.contains("<stop offset=\"1\" stop-color=\"#0000ff\"/>"));
    assert!(svg.contains("M400 400 L600 400 L600 600 L400 600 Z M450 450 L550 450 L500 550 Z\" fill-rule=\"evenodd\""));
    assert!(svg.contains("stroke-linecap=\"square\" stroke-linejoin=\"bevel\""));
    assert!(svg.contains(" A"), "the confetti's circles");
    assert!(svg.contains("font-family=\"'Playwrite FR Trad', cursive\""));
    // The first line's baseline: top + 2.852 × 1927/2852 × 30, as the
    // interface places it.
    let baseline = 100.0 + 2.852 * 1927.0 / 2852.0 * 30.0;
    assert!(
        svg.contains(&format!("<tspan x=\"700\" y=\"{baseline}\">école</tspan>")),
        "{svg}"
    );
    // The SVG of a drawing of before 1.1 is the same as ever.
    let plain = Owned::new();
    assert_eq!(plain.stroke(&LINE, 0x123456), 0);
    assert!(!plain.svg().contains("<g transform"));
}

#[test]
fn objects_added_together_are_one_step_to_undo() {
    let doc = Owned::new();
    assert_eq!(doc.dot(5.0, 5.0), 0);
    let left = [point(100.0, 100.0), point(200.0, 150.0)];
    let right = [point(1100.0, 100.0), point(1000.0, 150.0)];
    let before = doc.state();
    assert_eq!(
        doc.add_all(&[
            Spec {
                points: &left,
                ..Spec::default()
            },
            Spec {
                points: &right,
                look: EpObjectLook {
                    tool: TOOL_RAINBOW,
                    ..PLAIN_LOOK
                },
                ..Spec::default()
            },
        ]),
        0
    );
    assert_eq!(doc.count(), 3);
    assert_eq!(unsafe { ep_undo_count(doc.0) }, 2, "the dot, then both");
    doc.assert_accounting();
    assert_eq!(doc.undo(), 1);
    let undone = doc.state();
    assert_eq!((&undone.0, &undone.1), (&before.0, &before.1));
    doc.assert_accounting();
    assert_eq!(doc.redo(), 1);
    assert_eq!(doc.count(), 3);
    assert_eq!(doc.look(2).tool, TOOL_RAINBOW);
    doc.assert_accounting();
    // One that cannot join keeps the others out too.
    let state = (doc.v6(true), doc.svg());
    let nowhere = [point(f32::NAN, 1.0)];
    assert_eq!(
        doc.add_all(&[
            Spec {
                points: &left,
                ..Spec::default()
            },
            Spec {
                points: &nowhere,
                ..Spec::default()
            },
        ]),
        INVALID
    );
    assert_eq!((doc.v6(true), doc.svg()), state);
    assert_eq!(doc.add_all(&[]), INVALID);
    // At the bottom of the layer, in their order.
    assert_eq!(
        doc.add_all(&[
            Spec {
                points: &left,
                rgb: 0x0000_00aa,
                bottom: true,
                ..Spec::default()
            },
            Spec {
                points: &right,
                rgb: 0x0000_00bb,
                bottom: true,
                ..Spec::default()
            },
        ]),
        0
    );
    assert_eq!((doc.info(0).rgb, doc.info(1).rgb), (0xbb, 0xaa));
    assert_eq!(doc.undo(), 1);
    assert_eq!((doc.v6(true), doc.svg()), state);
    doc.assert_accounting();
}
