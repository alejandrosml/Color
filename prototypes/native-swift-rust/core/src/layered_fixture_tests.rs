//! Version 4 and 5 files written by tools/make_layered_fixtures.py, an
//! encoder that shares no code with this core.
use super::*;
use crate::test_support::*;

macro_rules! fixture {
    ($name:literal) => {
        include_bytes!(concat!("../test-fixtures/import-project/", $name))
    };
}

#[test]
fn independent_layered_fixture_loads_exactly_and_serializes_to_the_same_bytes() {
    let input = fixture!("layers-text-stamp-v4.edupaint");
    assert_eq!(
        input.as_slice(),
        fixture!("layers-text-stamp-v4.edupaint.normalized").as_slice()
    );
    let doc = Owned::from_project(input);
    assert_eq!(doc.project(), input);
    assert_eq!(unsafe { ep_document_width(doc.0) }, 800);
    assert_eq!(unsafe { ep_document_height(doc.0) }, 1200);
    assert_eq!(doc.layers(), [(0, true, 2), (2, false, 1), (1, true, 2)]);
    assert_eq!(doc.active(), 1);
    assert_eq!(
        (0..5).map(|index| doc.kind(index)).collect::<Vec<_>>(),
        [0, 2, KIND_TEXT, KIND_STAMP, 3]
    );
    assert_eq!(
        (0..5)
            .map(|index| doc.extra(index).layer)
            .collect::<Vec<_>>(),
        [0, 2, 1, 1, 0]
    );
    assert_eq!(doc.object_text(2), "Été 🎨\n2 < 3 & 4");
    assert_eq!(doc.info(2).width, 40.0);
    assert_eq!(doc.extra(3).param, 8);
    assert_eq!(unsafe { ep_undo_count(doc.0) }, 5);
    assert_eq!(unsafe { ep_redo_count(doc.0) }, 0);
    doc.assert_accounting();

    // Visible layers only, bottom first: layer 0 then layer 1; never layer 2.
    let svg = doc.svg();
    let first = svg.find("<g id=\"calque-1\">").unwrap();
    let second = svg.find("<g id=\"calque-2\">").unwrap();
    assert!(!svg.contains("calque-3") && !svg.contains("<rect x="));
    let path = svg
        .find("<path d=\"M10 20 L30.5 40.25 L800 1200 \"")
        .unwrap();
    let ellipse = svg
        .find("<ellipse cx=\"650\" cy=\"200\" rx=\"50\" ry=\"100\"")
        .unwrap();
    let text = svg.find(">Été 🎨</tspan>").unwrap();
    let stamp = svg.find("translate(300 600) scale(2 2)").unwrap();
    assert!(first < path && path < ellipse && ellipse < second && second < text && text < stamp);
    assert!(svg.contains(">2 &lt; 3 &amp; 4</tspan>"));

    // Showing the hidden layer brings its rectangle back, between the others.
    unsafe {
        assert_eq!(ep_set_layer_visible(doc.0, 1, 1), 1);
    }
    let shown = doc.svg();
    let rectangle = shown
        .find("<rect x=\"20\" y=\"30\" width=\"80\" height=\"90\" fill=\"#aabbcc\"")
        .unwrap();
    assert!(shown.find("<g id=\"calque-3\">").unwrap() < rectangle);
    assert!(rectangle < shown.find("<g id=\"calque-2\">").unwrap());
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.project(), input);
}

#[test]
fn independent_text_over_image_fixture_keeps_png_and_characters() {
    let input = fixture!("text-on-image-v4.edupaint");
    let doc = Owned::from_project(input);
    assert_eq!(doc.project(), input);
    let mut info = EpBackgroundInfo {
        width: 0,
        height: 0,
        byte_count: 0,
    };
    assert_eq!(unsafe { ep_background_info(doc.0, &mut info) }, 1);
    assert_eq!(
        (info.width, info.height, info.byte_count),
        (32, 24, fixture!("rgb.png").len())
    );
    assert_eq!(doc.object_text(0), "ok");
    let svg = doc.svg();
    assert!(svg.find("<image ").unwrap() < svg.find("<text ").unwrap());
    // Without its only text the drawing is an ordinary version 3 project.
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.project()[8], 3);
    doc.assert_accounting();
}

#[test]
fn independent_rejected_layered_fixtures_leave_a_candidate_untouched() {
    let candidate = Owned::new();
    assert_eq!(candidate.dot(5.0, 6.0), 0);
    assert_eq!(unsafe { ep_add_layer(candidate.0) }, 1);
    assert_eq!(
        candidate.text(corners(10.0, 10.0, 90.0, 40.0), 0, 20.0, "garde"),
        0
    );
    assert_eq!(candidate.undo(), 1);
    let before = candidate.state();
    let cases: &[&[u8]] = &[
        fixture!("unknown-stamp-v4.edupaint"),
        fixture!("duplicate-layers-v4.edupaint"),
        fixture!("control-text-v4.edupaint"),
        fixture!("unknown-version-5.edupaint"),
        // Historic file: version 4 announced over a version 2 body.
        fixture!("unknown-version.edupaint"),
    ];
    for input in cases {
        assert_eq!(
            unsafe { ep_document_load_project(candidate.0, input.as_ptr(), input.len()) },
            INVALID
        );
        assert!(Owned::try_from_project(input).is_err());
        assert_eq!(candidate.state(), before);
    }
    // The same candidate then adopts a valid layered file transactionally.
    let valid = fixture!("layers-text-stamp-v4.edupaint");
    assert_eq!(
        unsafe { ep_document_load_project(candidate.0, valid.as_ptr(), valid.len()) },
        0
    );
    assert_eq!(candidate.project(), valid);
    candidate.assert_accounting();
}

#[test]
fn independent_version_5_page_loads_exactly_and_serializes_to_the_same_bytes() {
    let input = fixture!("locked-page-v5.edupaint");
    assert_eq!(
        input.as_slice(),
        fixture!("locked-page-v5.edupaint.normalized").as_slice()
    );
    let doc = Owned::from_project(input);
    assert_eq!(doc.project(), input);
    assert_eq!(
        doc.layers(),
        [
            (1, true, 2),
            (0, true, 2),
            (3, false, 1),
            (4, false, 1),
            (2, true, 3)
        ]
    );
    assert_eq!(doc.locks(), [true, false, false, true, true]);
    assert_eq!(doc.active(), 0);
    assert_eq!(
        (0..9).map(|index| doc.kind(index)).collect::<Vec<_>>(),
        [
            KIND_CONTOUR,
            2,
            0,
            KIND_CONTOUR,
            KIND_STAMP,
            3,
            KIND_CONTOUR,
            2,
            0
        ]
    );
    assert_eq!(doc.points(3)[1], point(900.0, 420.5));
    assert_eq!(doc.info(0).width, 0.1);
    doc.assert_accounting();

    // The page is not in the history: only what was drawn on it is undone.
    assert_eq!(
        unsafe { (ep_undo_count(doc.0), ep_redo_count(doc.0)) },
        (3, 0)
    );
    assert_eq!(doc.pinned(), 6);
    for _ in 0..3 {
        assert_eq!(doc.undo(), 1);
        doc.assert_accounting();
    }
    assert_eq!(doc.undo(), 0);
    assert_eq!(doc.count(), 6);
    assert_eq!(doc.pinned(), 6);
    for _ in 0..3 {
        assert_eq!(doc.redo(), 1);
    }
    assert_eq!(doc.project(), input);

    // Zones, then the drawing, then the lines; hidden layers are left out.
    let svg = doc.svg();
    let zones = svg.find("<g id=\"calque-2\">").unwrap();
    let drawing = svg.find("<g id=\"calque-1\">").unwrap();
    let lines = svg.find("<g id=\"calque-3\">").unwrap();
    assert!(!svg.contains("calque-4") && !svg.contains("calque-5"));
    let zone = svg
        .find(
            "<path d=\"M200 100 L300 170 L260 290 L140 290 L100 170 Z\" fill=\"#ffffff\" \
             stroke=\"#ffffff\" stroke-width=\"0.1\"",
        )
        .unwrap();
    let painted = svg
        .find("<path d=\"M700 400 L900 420.5 L820 600 L690 560 Z\" fill=\"#aabbcc\"")
        .unwrap();
    let line = svg
        .find(
            "<path d=\"M200 100 L300 170 L260 290 L140 290 L100 170 Z\" fill=\"none\" \
             stroke=\"#2f3d4a\" stroke-width=\"6\"",
        )
        .unwrap();
    assert!(zones < zone && zone < drawing && drawing < painted && painted < lines && lines < line);
    assert_eq!(doc.snapshot(), (input.to_vec(), svg));
}

#[test]
fn version_5_without_a_lock_or_a_contour_is_written_back_as_version_4() {
    let input = fixture!("layers-only-v5.edupaint");
    let expected = fixture!("layers-only-v5.edupaint.normalized");
    assert_eq!(expected[8], 4);
    let doc = Owned::from_project(input);
    assert_eq!(doc.project(), expected);
    assert_eq!(doc.layers(), [(0, true, 1), (1, false, 1)]);
    assert_eq!(doc.locks(), [false, false]);
    assert_eq!(doc.active(), 1);
    assert_eq!(Owned::from_project(expected).project(), expected);
    doc.assert_accounting();
}

#[test]
fn independent_rejected_version_5_fixtures_leave_a_candidate_untouched() {
    let candidate = Owned::from_project(fixture!("locked-page-v5.edupaint"));
    assert_eq!(candidate.dot(5.0, 6.0), 0);
    assert_eq!(candidate.undo(), 1);
    let before = candidate.state();
    let cases: &[&[u8]] = &[
        fixture!("locked-active-v5.edupaint"),
        fixture!("layer-flags-v5.edupaint"),
        fixture!("flat-contour-v5.edupaint"),
        fixture!("short-contour-v5.edupaint"),
        fixture!("contour-in-v4.edupaint"),
        fixture!("locked-in-v4.edupaint"),
        fixture!("unknown-version-6.edupaint"),
    ];
    for input in cases {
        assert_eq!(
            unsafe { ep_document_load_project(candidate.0, input.as_ptr(), input.len()) },
            INVALID
        );
        assert!(Owned::try_from_project(input).is_err());
        assert_eq!(candidate.state(), before);
    }
    // Each is refused for its one defect: the same file without it reads.
    let page = fixture!("locked-page-v5.edupaint");
    let active = fixture!("locked-active-v5.edupaint");
    assert_eq!(active.len(), page.len());
    let mut repaired = active.to_vec();
    put_u32(&mut repaired, 44, 0);
    assert_eq!(resealed(repaired), page);
    let mut v5 = fixture!("contour-in-v4.edupaint").to_vec();
    v5[8] = 5;
    assert!(Owned::try_from_project(&resealed(v5)).is_ok());
    let mut v5 = fixture!("locked-in-v4.edupaint").to_vec();
    v5[8] = 5;
    assert!(Owned::try_from_project(&resealed(v5)).is_ok());
    let mut known = fixture!("unknown-version-6.edupaint").to_vec();
    known[8] = 2;
    assert!(Owned::try_from_project(&resealed(known)).is_ok());
}

#[test]
fn size_bounds_of_every_version_are_those_of_the_header() {
    assert_eq!(MAX_VECTOR_PROJECT_BYTES, 8_240_036);
    assert_eq!(MAX_HYBRID_PROJECT_BYTES, 79_543_220);
    assert_eq!(MAX_PROJECT_BYTES, 80_711_932);
    assert_eq!(MAX_TEXT_BYTES, 2048);
}
