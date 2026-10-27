//! Tests of the colouring pages: the files compiled into the core, what the
//! reader takes and refuses, paths and their curves, the catalogue, and the
//! document that a page makes. Documents are driven through the C functions.
use super::*;
use crate::test_support::{point, Owned};
use std::ffi::CStr;

/// The ink of every outline and detail of the pages drawn for Color.
const INK: u32 = 0x2f3d4a;

const HEAD: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 800">"#;
const RECT: &str = r##"<rect x="100" y="100" width="200" height="100" fill="#ffffff" stroke="#2f3d4a" stroke-width="6"/>"##;

fn page(body: &str) -> String {
    format!("{HEAD}<title>Essai</title>{body}</svg>")
}

fn all_pages() -> &'static [Page] {
    pages().expect("every page compiled into the core reads")
}

/// The document of compiled page `id`, through the C function.
fn from_page(id: u32) -> Owned {
    let pointer = ep_document_from_page(id);
    assert!(!pointer.is_null(), "page {id}");
    Owned(pointer)
}

/// The document of a page given as text, made as ep_document_from_page
/// makes the document of a compiled page.
fn document(svg: &str) -> Owned {
    let page = read_page(svg).unwrap_or_else(|why| panic!("{why}: {svg}"));
    let pointer = owned_document(page_document(&page).unwrap());
    assert!(!pointer.is_null());
    Owned(pointer)
}

/// A path element with the ink and outline of the pages.
fn path_element(d: &str, fill: &str) -> String {
    format!(r##"<path d="{d}" fill="{fill}" stroke="#2f3d4a" stroke-width="6"/>"##)
}

/// The one object of a page made of one path.
fn read_path(d: &str, fill: &str) -> Result<PageObject, Refused> {
    let mut page = read_page(&page(&path_element(d, fill)))?;
    assert_eq!(page.objects.len(), 1);
    Ok(page.objects.remove(0))
}

/// The bits of points, added: a pin on every one of them.
fn bits(points: &[EpPoint]) -> u64 {
    points
        .iter()
        .map(|p| u64::from(p.x.to_bits()) + u64::from(p.y.to_bits()))
        .sum()
}

fn catalogue_text() -> String {
    let raw = ep_page_catalog();
    assert!(!raw.is_null());
    let text = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_owned();
    unsafe { ep_string_free(raw) };
    text
}

// The reverse of `escaped`, as the interface decodes a title.
fn unescape(text: &str) -> String {
    let mut bytes = Vec::new();
    let mut rest = text.as_bytes();
    while let Some((&byte, after)) = rest.split_first() {
        if byte == b'%' {
            let hex = std::str::from_utf8(&after[..2]).unwrap();
            bytes.push(u8::from_str_radix(hex, 16).unwrap());
            rest = &after[2..];
        } else {
            bytes.push(byte);
            rest = after;
        }
    }
    String::from_utf8(bytes).unwrap()
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

#[test]
fn the_table_holds_exactly_the_files_of_the_pages_folder() {
    // Names that start with a dot are what a file manager leaves in a
    // folder it has shown: they are not pages.
    let mut files: Vec<String> = std::fs::read_dir("art/coloriages")
        .expect("tests run from the folder of the core")
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .filter(|name| !name.starts_with('.'))
        .collect();
    files.sort();
    let keys: Vec<String> = PAGES.iter().map(|(key, _)| format!("{key}.svg")).collect();
    assert_eq!(
        files, keys,
        "one line of PAGES per file, in the order of the keys"
    );
    for (key, svg) in PAGES {
        assert!(
            (1..=32).contains(&key.len())
                && key.bytes().all(|b| b.is_ascii_lowercase() || b == b'-')
                && !key.starts_with('-')
                && !key.ends_with('-'),
            "{key}"
        );
        let file = std::fs::read_to_string(format!("art/coloriages/{key}.svg")).unwrap();
        assert_eq!(*svg, file);
    }
    assert!(PAGES.len() >= 6);
    assert_eq!(ep_page_count() as usize, PAGES.len());
}

#[test]
fn every_page_reads_on_the_landscape_sheet_of_nouveau() {
    for ((key, svg), page) in PAGES.iter().zip(all_pages()) {
        // The sheet that « Nouveau » proposes first.
        assert_eq!((page.width, page.height), (1200, 800), "{key}");
        assert!(!page.title.is_empty(), "{key}");
        // Only what a page may use, whatever the reader of this module says.
        let xml = Document::parse(svg).unwrap();
        let allowed = [
            "svg", "title", "desc", "rect", "circle", "ellipse", "line", "polyline", "path",
        ];
        for node in xml.descendants().filter(|node| node.is_element()) {
            assert!(
                allowed.contains(&node.tag_name().name()),
                "{key}: {:?}",
                node.tag_name()
            );
        }
        // One object per drawn element, in the order of the file.
        let drawn = xml
            .root_element()
            .children()
            .filter(|node| {
                node.is_element() && !["title", "desc"].contains(&node.tag_name().name())
            })
            .count();
        assert_eq!(page.objects.len(), drawn, "{key}");
    }
}

#[test]
fn every_page_is_drawn_for_small_hands() {
    for ((key, _), page) in PAGES.iter().zip(all_pages()) {
        assert!(page.regions() >= 3, "{key}: {} regions", page.regions());
        assert!(page.objects.len() <= 60, "{key}: a page stays simple");
        for object in &page.objects {
            let low_x = object
                .points
                .iter()
                .map(|p| p.x)
                .fold(f32::INFINITY, f32::min);
            let low_y = object
                .points
                .iter()
                .map(|p| p.y)
                .fold(f32::INFINITY, f32::min);
            let high_x = object
                .points
                .iter()
                .map(|p| p.x)
                .fold(f32::NEG_INFINITY, f32::max);
            let high_y = object
                .points
                .iter()
                .map(|p| p.y)
                .fold(f32::NEG_INFINITY, f32::max);
            let half = object.width / 2.0;
            // Nothing touches the edge of the sheet, outline included.
            assert!(
                low_x - half >= 30.0
                    && low_y - half >= 30.0
                    && high_x + half <= 1170.0
                    && high_y + half <= 770.0,
                "{key}: {:?} is too close to the edge",
                object.points
            );
            assert_eq!(object.rgb, INK, "{key}: every line has the dark ink");
            if object.style.fill_enabled == 1 {
                assert_eq!(
                    object.style.fill_rgb, WHITE,
                    "{key}: a region is white, ready for the paint pot"
                );
                assert_eq!(object.width, 6.0, "{key}: the outline of a region");
                assert!(
                    high_x - low_x >= 60.0 && high_y - low_y >= 60.0,
                    "{key}: {:?} is too small for a small hand",
                    object.points
                );
            } else {
                assert_eq!(object.style.fill_rgb, 0, "{key}");
            }
        }
    }
}

#[test]
fn every_page_makes_a_document_of_zones_drawing_and_lines() {
    for (id, page) in all_pages().iter().enumerate() {
        let doc = from_page(id as u32);
        let size = unsafe { (ep_document_width(doc.0), ep_document_height(doc.0)) };
        assert_eq!(size, (page.width, page.height));
        // One zone per filled element; the lines, outlines that later shapes
        // may cut into pieces, are tested with clip.rs.
        let (zones, lines) = (page.regions(), page.lines.len());
        assert_eq!(
            doc.layers(),
            [(1, true, zones), (0, true, 0), (2, true, lines)]
        );
        assert_eq!(doc.locks(), [true, false, true]);
        assert_eq!(doc.active(), 0);
        // Nothing of the page is in the history.
        assert_eq!(
            unsafe { (ep_undo_count(doc.0), ep_redo_count(doc.0)) },
            (0, 0)
        );
        assert_eq!(doc.undo(), 0);
        assert_eq!(doc.count(), zones + lines);
        assert_eq!(doc.pinned(), zones + lines);
        // The zones: every filled element, white, without a visible outline.
        let filled = page.objects.iter().filter(|o| o.style.fill_enabled == 1);
        for (index, object) in filled.enumerate() {
            let expected = EpObjectStyle {
                kind: object.style.kind,
                fill_enabled: 1,
                fill_rgb: WHITE,
            };
            assert_eq!(style(&doc, index), expected);
            let info = doc.info(index);
            assert_eq!((info.rgb, info.width), (WHITE, 0.1));
            assert_eq!(doc.points(index), object.points);
            assert_eq!(doc.extra(index).layer, 1);
        }
        // The lines read with the page, in their order, without a fill.
        for (offset, line) in page.lines.iter().enumerate() {
            let index = zones + offset;
            assert_eq!(style(&doc, index), line.style);
            assert_eq!(line.style.fill_enabled, 0);
            let info = doc.info(index);
            assert_eq!((info.rgb, info.width), (line.rgb, line.width));
            assert_eq!(doc.points(index), line.points);
            assert_eq!(doc.extra(index).layer, 2);
            // A piece is never a dot, which the SVG would draw filled.
            assert!(line.style.kind != 0 || line.points.len() > 1);
        }
        // Every object of the page is content with a token of its own.
        let mut tokens = doc.revisions();
        tokens.sort_unstable();
        tokens.dedup();
        assert_eq!(tokens.len(), doc.count());
        assert!(!tokens.contains(&0));
        let svg = doc.svg();
        let white = "fill=\"#ffffff\" stroke=\"#ffffff\" stroke-width=\"0.1\"";
        assert_eq!(svg.matches(white).count(), zones);
        assert_eq!(
            svg.matches("fill=\"none\" stroke=\"#2f3d4a\"").count(),
            lines
        );
        let order = [
            "<g id=\"calque-2\">",
            "<g id=\"calque-1\">",
            "<g id=\"calque-3\">",
        ]
        .map(|group| svg.find(group).unwrap());
        assert!(order[0] < order[1] && order[1] < order[2]);
        // Saved as version 5, reopened with its locks and without history.
        let bytes = doc.project();
        assert_eq!(u16::from_le_bytes([bytes[8], bytes[9]]), 5);
        let reopened = Owned::from_project(&bytes);
        assert_eq!(reopened.project(), bytes);
        assert_eq!(reopened.svg(), svg);
        assert_eq!(reopened.locks(), [true, false, true]);
        assert_eq!(unsafe { ep_undo_count(reopened.0) }, 0);
        assert_eq!(doc.snapshot(), (bytes, svg));
        doc.assert_accounting();
    }
}

#[test]
fn the_child_draws_between_the_zones_and_the_lines_of_a_page() {
    // The house, whose ground is the first zone of its file.
    let house = PAGES.iter().position(|(key, _)| *key == "maison").unwrap();
    let doc = from_page(house as u32);
    let zones = all_pages()[house].regions();
    let page = doc.project();
    assert_eq!(
        doc.stroke(&[point(500.0, 500.0), point(520.0, 540.0)], 0xd75e56),
        0
    );
    let index = doc.count() - 1;
    assert_eq!(doc.extra(index).layer, 0);
    let svg = doc.svg();
    let at = |text: &str| svg.find(text).unwrap();
    assert!(at("<g id=\"calque-2\">") < at("<g id=\"calque-1\">"));
    assert!(at("<g id=\"calque-1\">") < at("stroke=\"#d75e56\""));
    assert!(at("stroke=\"#d75e56\"") < at("<g id=\"calque-3\">"));
    unsafe {
        // The paint pot colours the ground, the first zone of the file...
        assert_eq!(ep_set_object_style(doc.0, 0, WHITE, 0.1, 1, 0x7ac143), 1);
        // ... and nothing else of the page moves or goes.
        assert_eq!(ep_remove_object(doc.0, 0), INVALID);
        assert_eq!(ep_remove_object(doc.0, zones), INVALID);
        assert_eq!(ep_move_object(doc.0, zones, 5.0, 5.0), INVALID);
        assert_eq!(
            ep_set_object_style(doc.0, zones, 0xff0000, 6.0, 0, 0),
            INVALID
        );
        assert_eq!(ep_remove_object(doc.0, index), 1);
        assert_eq!(doc.undo(), 1);
    }
    assert!(doc
        .svg()
        .contains("fill=\"#7ac143\" stroke=\"#ffffff\" stroke-width=\"0.1\""));
    // Undo takes the paint and the stroke away, and stops at the page.
    assert_eq!((doc.undo(), doc.undo(), doc.undo()), (1, 1, 0));
    assert_eq!(doc.project(), page);
    assert_eq!(doc.project(), from_page(house as u32).project());
    doc.assert_accounting();
}

#[test]
fn no_layer_ever_goes_under_the_zones_or_over_the_lines_of_a_page() {
    let ids = |doc: &Owned| doc.layers().iter().map(|layer| layer.0).collect::<Vec<_>>();
    for id in 0..ep_page_count() {
        let doc = from_page(id);
        let page = doc.project();
        let before = doc.state();
        unsafe {
            // Under the zones the drawing would vanish under their white,
            // over the lines it would cover them; the page itself stays.
            for (from, to) in [(1, 0), (1, 2), (0, 1), (0, 2), (2, 0), (2, 1)] {
                assert_eq!(ep_reorder_layer(doc.0, from, to), INVALID, "{id}");
            }
            assert_eq!(ep_reorder_layer(doc.0, 1, 1), 0);
        }
        assert_eq!(doc.state(), before);
        // New layers come above the active one, between the zones and the
        // lines, where they are reordered among themselves.
        unsafe {
            assert_eq!(ep_add_layer(doc.0), 1);
            assert_eq!(ep_add_layer(doc.0), 1);
            assert_eq!(ids(&doc), [1, 0, 3, 4, 2]);
            assert_eq!(ep_reorder_layer(doc.0, 3, 1), 1);
            assert_eq!(ids(&doc), [1, 4, 0, 3, 2]);
            for from in 1..4 {
                for to in [0, 4] {
                    assert_eq!(ep_reorder_layer(doc.0, from, to), INVALID, "{id}");
                }
            }
        }
        assert_eq!(doc.undo(), 1);
        assert_eq!(ids(&doc), [1, 0, 3, 4, 2]);
        assert_eq!(doc.redo(), 1);
        // Removing layers, and adding them up to sixteen, keeps the zones at
        // the bottom and the lines at the top.
        unsafe {
            assert_eq!(ep_remove_layer(doc.0, 2), 1);
            assert_eq!(ids(&doc), [1, 4, 3, 2]);
            while ep_add_layer(doc.0) == 1 {
                let order = ids(&doc);
                assert_eq!((order[0], order[order.len() - 1]), (1, 2), "{id}");
            }
        }
        assert_eq!(doc.layers().len(), MAX_LAYERS);
        let locks = doc.locks();
        assert!(locks[0] && locks[MAX_LAYERS - 1]);
        assert!(locks[1..MAX_LAYERS - 1].iter().all(|locked| !locked));
        doc.assert_accounting();
        // Undo goes back to the page as it came.
        while doc.undo() == 1 {}
        assert_eq!(doc.project(), page);
        doc.assert_accounting();
    }
}

#[test]
fn an_unknown_page_makes_no_document_and_two_documents_are_independent() {
    for id in [ep_page_count(), ep_page_count() + 1, u32::MAX] {
        assert!(ep_document_from_page(id).is_null(), "{id}");
    }
    let first = from_page(0);
    let second = from_page(0);
    assert_eq!(first.project(), second.project());
    assert_eq!(first.dot(600.0, 400.0), 0);
    assert_ne!(first.project(), second.project());
    assert_eq!(second.count(), first.count() - 1);
}

#[test]
fn a_page_with_paths_makes_contour_zones_and_details() {
    let svg = page(
        &[
            path_element("M100 100 L300 100 L200 300 Z", "#ffffff"),
            path_element("M400 100 Q500 0 600 100 Q500 200 400 100 Z", "none"),
            path_element("M700 100 C700 200 900 200 900 100", "none"),
            // Clear of the curve: no outline is cut here (see clip.rs).
            RECT.replace("x=\"100\" y=\"100\"", "x=\"950\" y=\"300\""),
        ]
        .concat(),
    );
    let read = read_page(&svg).unwrap();
    assert_eq!((read.regions(), read.details()), (2, 2));
    let kinds: Vec<u32> = read.objects.iter().map(|o| o.style.kind).collect();
    assert_eq!(kinds, [KIND_CONTOUR, KIND_CONTOUR, 0, 2]);
    let doc = document(&svg);
    assert_eq!(doc.layers(), [(1, true, 2), (0, true, 0), (2, true, 4)]);
    assert_eq!(
        (0..6).map(|index| doc.kind(index)).collect::<Vec<_>>(),
        [KIND_CONTOUR, 2, KIND_CONTOUR, KIND_CONTOUR, 0, 2]
    );
    let triangle = "<path d=\"M100 100 L300 100 L200 300 Z\"";
    let svg = doc.svg();
    assert!(svg.contains(&format!(
        "{triangle} fill=\"#ffffff\" stroke=\"#ffffff\" stroke-width=\"0.1\""
    )));
    assert!(svg.contains(&format!(
        "{triangle} fill=\"none\" stroke=\"#2f3d4a\" stroke-width=\"6\""
    )));
    // The lens closes on its start: 48 points per curve, its last dropped.
    assert_eq!(doc.info(3).point_count, 96);
    assert_eq!(doc.info(4).point_count, 49);
    unsafe {
        assert_eq!(ep_set_object_style(doc.0, 0, WHITE, 0.1, 1, 0x3366cc), 1);
    }
    let bytes = doc.project();
    assert_eq!(bytes[8], 5);
    assert_eq!(Owned::from_project(&bytes).project(), bytes);
    doc.assert_accounting();
}

#[test]
fn random_edits_on_page_documents_restore_the_exact_state() {
    for id in 0..ep_page_count() {
        crate::history_model_tests::run_on(
            from_page(id),
            0x5a6e_0000 + u64::from(id),
            120,
            id % 2 == 0,
        );
    }
    let svg = page(
        &[
            path_element("M100 100 L300 100 L200 300 Z", "#ffffff"),
            path_element("M400 100 Q500 0 600 100 Q500 200 400 100 Z", "#ffffff"),
            path_element("M700 100 C700 200 900 200 900 100", "none"),
        ]
        .concat(),
    );
    for seed in 0..4 {
        crate::history_model_tests::run_on(document(&svg), 0x5a6e_1000 + seed, 200, seed % 2 == 1);
    }
}

#[test]
fn the_catalogue_is_ascii_and_describes_every_page() {
    let text = catalogue_text();
    assert!(text.is_ascii());
    let mut lines = text.lines();
    for (id, ((key, _), page)) in PAGES.iter().zip(all_pages()).enumerate() {
        let head = lines.next().expect("one head line per page");
        let fields: Vec<&str> = head.splitn(6, ' ').collect();
        let expected = [
            "T".to_owned(),
            id.to_string(),
            key.to_string(),
            page.regions().to_string(),
            page.details().to_string(),
        ];
        assert_eq!(fields[..5], expected, "{head}");
        assert_eq!(unescape(fields[5]), page.title);
        // Its thumbnail: one drawn outline per object of the page.
        assert_eq!(lines.next(), Some(format!("P {key} 1200 800").as_str()));
        let mut drawn = 0;
        for line in lines.by_ref() {
            if line == "X" {
                break;
            }
            assert!(line.starts_with("D "), "{key}: {line}");
            drawn += 1;
        }
        assert_eq!(drawn, page.objects.len(), "{key}");
    }
    assert_eq!(lines.next(), None);
    // A title with an accent travels in ASCII.
    assert!(text.contains("\nT 6 fusee "), "{text}");
    assert!(text.contains(" La fus%C3%A9e\n"));
    let mut out = String::new();
    escaped(&mut out, "50 % d’été").unwrap();
    assert_eq!(out, "50 %25 d%E2%80%99%C3%A9t%C3%A9");
    assert_eq!(unescape(&out), "50 % d’été");
}

#[test]
fn the_reader_takes_what_a_page_may_say() {
    let svg = format!(
        concat!(
            r#"<?xml version="1.0" encoding="UTF-8"?><!-- un essai -->"#,
            r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0,0,800,1200" width="800" height="1200""#,
            r#" stroke-linecap="round" stroke-linejoin="round">"#,
            "\n  {}\n  <!-- une note -->\n  <title> La f&#233;e </title>",
            r##"<circle cx="400" cy="300" r="50" fill="#FFFFFF" stroke="#102030" stroke-width="4.5"/>"##,
            r##"<ellipse cx="400" cy="600" rx="80" ry="40" fill="none" stroke="#2f3d4a" stroke-width="6"/>"##,
            r##"<line x1="10" y1="20" x2="30.5" y2="40" fill="none" stroke="#2f3d4a" stroke-width="6"/>"##,
            r##"<polyline points=" 10,10 20 20,30,10 " fill="none" stroke="#2f3d4a" stroke-width="2"/>"##,
            "<desc>Rien qu’un essai.</desc></svg>"
        ),
        RECT
    );
    let read = read_page(&svg).unwrap();
    assert_eq!(
        (read.width, read.height, read.title.as_str()),
        (800, 1200, "La fée")
    );
    let found: Vec<(u32, u32, u32, f32, Vec<EpPoint>)> = read
        .objects
        .iter()
        .map(|o| {
            (
                o.style.kind,
                o.style.fill_enabled,
                o.rgb,
                o.width,
                o.points.clone(),
            )
        })
        .collect();
    assert_eq!(
        found,
        vec![
            (
                2,
                1,
                INK,
                6.0,
                vec![point(100.0, 100.0), point(300.0, 200.0)]
            ),
            (
                3,
                1,
                0x102030,
                4.5,
                vec![point(350.0, 250.0), point(450.0, 350.0)]
            ),
            (
                3,
                0,
                INK,
                6.0,
                vec![point(320.0, 560.0), point(480.0, 640.0)]
            ),
            (1, 0, INK, 6.0, vec![point(10.0, 20.0), point(30.5, 40.0)]),
            (
                0,
                0,
                INK,
                2.0,
                vec![point(10.0, 10.0), point(20.0, 20.0), point(30.0, 10.0)]
            ),
        ]
    );
    // Regions are the filled elements: the ellipse without a fill is a detail.
    assert_eq!((read.regions(), read.details()), (2, 3));
}

#[test]
fn the_reader_refuses_anything_else_whole() {
    let paint = r##"fill="none" stroke="#2f3d4a" stroke-width="6""##;
    let white = r##"fill="#ffffff" stroke="#2f3d4a" stroke-width="6""##;
    let rect = |extra: &str| page(&RECT.replace("/>", &format!(" {extra}/>")));
    let refused = [
        // Elements that a page does not use.
        page(&format!(r#"<path d="M 10 10 A 5 5 0 0 1 90 90" {paint}/>"#)),
        page(&format!(r#"<path d="M 10 10 L 90 90" id="a" {paint}/>"#)),
        page(&format!(r#"<path {paint}/>"#)),
        page(&format!(r#"<path d="M 10 10 L 90 90" {white}/>"#)),
        page(&format!("<g>{RECT}</g>")),
        page(r#"<text x="10" y="10">A</text>"#),
        page(&format!(r#"<polygon points="10,10 90,10 50,90" {white}/>"#)),
        page(&format!(r##"<use href="#a"/>{RECT}"##)),
        page(&RECT.replace("/>", "><title>Non</title></rect>")),
        // Attributes that it does not use, or values it does not read.
        rect(r#"transform="rotate(10)""#),
        rect(r#"rx="10""#),
        rect(r#"id="mur""#),
        rect(r#"style="fill:red""#),
        rect(r#"opacity="0.5""#),
        rect(r#"xml:space="preserve""#),
        page(&RECT.replace("#ffffff", "#ff0000")),
        page(&RECT.replace("#ffffff", "white")),
        page(&RECT.replace("stroke=\"#2f3d4a\"", "stroke=\"none\"")),
        page(&RECT.replace("stroke=\"#2f3d4a\" ", "")),
        page(&RECT.replace("fill=\"#ffffff\" ", "")),
        page(&RECT.replace("stroke-width=\"6\"", "stroke-width=\"6px\"")),
        page(&RECT.replace("stroke-width=\"6\"", "stroke-width=\"0\"")),
        page(&RECT.replace("stroke-width=\"6\"", "stroke-width=\"600\"")),
        page(&RECT.replace("x=\"100\"", "x=\"1e2\"")),
        page(&RECT.replace("x=\"100\"", "x=\"10%\"")),
        page(&RECT.replace("x=\"100\"", "x=\".5\"")),
        page(&RECT.replace("x=\"100\"", "x=\"100.\"")),
        page(&RECT.replace("x=\"100\"", "x=\"+100\"")),
        page(&RECT.replace("x=\"100\"", "x=\"NaN\"")),
        // Shapes without a size, and lines that cannot be filled.
        page(&RECT.replace("width=\"200\"", "width=\"0\"")),
        page(&RECT.replace("height=\"100\"", "height=\"-100\"")),
        page(&format!(r#"<circle cx="50" cy="50" r="0" {white}/>"#)),
        page(&format!(
            r#"<ellipse cx="50" cy="50" rx="30" ry="0" {white}/>"#
        )),
        page(&format!(
            r#"<line x1="10" y1="10" x2="10" y2="10" {paint}/>"#
        )),
        page(&format!(
            r#"<line x1="10" y1="10" x2="90" y2="10" {white}/>"#
        )),
        page(&format!(
            r#"<polyline points="10,10 90,10 50,90" {white}/>"#
        )),
        page(&format!(r#"<polyline points="10,10" {paint}/>"#)),
        page(&format!(r#"<polyline points="10,10 20" {paint}/>"#)),
        page(&format!(r#"<polyline points="10,,10 20,20" {paint}/>"#)),
        // Beyond the sheet, outline included.
        page(&RECT.replace("x=\"100\"", "x=\"1100\"")),
        page(&RECT.replace("y=\"100\"", "y=\"2\"")),
        page(&format!(r#"<circle cx="1180" cy="400" r="20" {white}/>"#)),
        page(&format!(
            r#"<line x1="-10" y1="10" x2="90" y2="10" {paint}/>"#
        )),
        page(&format!(r#"<polyline points="10,10 1199,799" {paint}/>"#)),
        // The document around the drawing.
        format!("{HEAD}{RECT}</svg>"),
        page(&format!("<title>Encore</title>{RECT}")),
        page(&format!("<desc>a</desc><desc>b</desc>{RECT}")),
        page(""),
        format!("{HEAD}<title> </title>{RECT}</svg>"),
        format!("{HEAD}<title>Un <tspan>mot</tspan></title>{RECT}</svg>"),
        format!("{HEAD}<title lang=\"fr\">Mot</title>{RECT}</svg>"),
        format!("{HEAD}<title>Un\u{7}son</title>{RECT}</svg>"),
        page(&format!("Bonjour{RECT}")),
        page(&format!("<?essai rien?>{RECT}")),
        page(&format!("<![CDATA[x]]>{RECT}")),
        format!(
            "<!DOCTYPE svg [<!ENTITY a \"b\">]>{}",
            page(&format!("<desc>&a;</desc>{RECT}"))
        ),
        page(RECT).replace("http://www.w3.org/2000/svg", "http://example.com/svg"),
        page(RECT)
            .replace("<svg", "<svg:svg")
            .replace("</svg>", "</svg:svg>"),
        page(RECT).replace("0 0 1200 800", "10 0 1200 800"),
        page(RECT).replace("0 0 1200 800", "0 0 1200.5 800"),
        page(RECT).replace("0 0 1200 800", "0 0 1200"),
        page(RECT).replace("0 0 1200 800", "0 0 0 800"),
        page(RECT).replace("0 0 1200 800", "0 0 99999 800"),
        page(RECT).replace(" viewBox=\"0 0 1200 800\"", ""),
        page(RECT).replace("viewBox", "width=\"1000\" viewBox"),
        page(RECT).replace("viewBox", "stroke=\"#000000\" viewBox"),
        page(RECT).replace("viewBox", "stroke-linecap=\"butt\" viewBox"),
        page(RECT).replace("viewBox", "transform=\"scale(2)\" viewBox"),
        "<rect/>".to_owned(),
        String::new(),
        // Bounds of the reader.
        page(&format!(
            "<desc>{}</desc>{RECT}",
            "a".repeat(MAX_PAGE_BYTES)
        )),
        page(&RECT.repeat(MAX_PAGE_OBJECTS + 1)),
        page(&"<!-- - -->".repeat(MAX_PAGE_NODES as usize)),
    ];
    for svg in &refused {
        assert!(read_page(svg).is_err(), "read: {svg}");
    }
    // The same text without the change that refuses it reads.
    assert!(read_page(&page(RECT)).is_ok());
    assert!(read_page(&page(&RECT.repeat(MAX_PAGE_OBJECTS))).is_ok());
}

#[test]
fn paths_are_read_absolute_or_relative_with_their_lines_on_the_axes() {
    let triangle = vec![
        point(100.0, 100.0),
        point(200.0, 100.0),
        point(200.0, 200.0),
    ];
    for d in [
        "M 100 100 L 200 100 L 200 200 Z",
        "M100,100L200,100L200,200Z",
        "m100 100 l100 0 0 100 z",
        // After a moveto, more pairs are lines.
        "M100 100 200 100 200 200 Z",
        "m100,100 100,0 0,100z",
        "M100 100 H200 V200 Z",
        "M100 100 h100 v100 z",
        // Back to the start before Z, which joins it anyway: dropped.
        "M 100 100 L 200 100 L 200 200 L 100 100 Z",
        // The same point twice in a row is kept once.
        "M100 100 L100 100 L200 100 L200 200 L200 200 Z",
        "  M100 100 L200 100 L200 200 Z \n",
    ] {
        let object = read_path(d, "#ffffff").unwrap_or_else(|why| panic!("{why}: {d}"));
        assert_eq!(
            object.style,
            EpObjectStyle {
                kind: KIND_CONTOUR,
                fill_enabled: 1,
                fill_rgb: WHITE
            },
            "{d}"
        );
        assert_eq!(object.points, triangle, "{d}");
        assert_eq!((object.rgb, object.width), (INK, 6.0));
    }
    // A closed outline without a fill is a detail of the lines.
    let outline = read_path("M100 100 H200 V200 H100 Z", "none").unwrap();
    assert_eq!(
        outline.style,
        EpObjectStyle {
            kind: KIND_CONTOUR,
            fill_enabled: 0,
            fill_rgb: 0
        }
    );
    assert_eq!(outline.points.len(), 4);
    // An open path is a freehand detail, even when it comes back to its
    // start; a path of one place is a dot.
    let open = read_path("M10 10 L50 10 L50 50", "none").unwrap();
    assert_eq!(open.style, FREEHAND_STYLE);
    assert_eq!(
        open.points,
        [point(10.0, 10.0), point(50.0, 10.0), point(50.0, 50.0)]
    );
    assert_eq!(
        read_path("M10 10 L50 10 L10 10", "none")
            .unwrap()
            .points
            .len(),
        3
    );
    assert_eq!(
        read_path("M10 10 L10 10", "none").unwrap().points,
        [point(10.0, 10.0)]
    );
    // Decimals, a negative relative number, a letter right after a number.
    let decimals = read_path("M100.5 100.25l-0.5 99.75L300 200Z", "#ffffff").unwrap();
    assert_eq!(
        decimals.points,
        [
            point(100.5, 100.25),
            point(100.0, 200.0),
            point(300.0, 200.0)
        ]
    );
}

#[test]
fn curves_are_flattened_into_the_same_points_every_time() {
    // Control polygon 400 long: 67 steps of 6, kept at 48. The values were
    // computed apart, in Python, with the same formula in IEEE doubles.
    let cubic = read_path("M100 100 C100 200 300 200 300 100", "none").unwrap();
    assert_eq!(cubic.points.len(), 1 + 48);
    assert_eq!(cubic.points[0], point(100.0, 100.0));
    assert_eq!(cubic.points[1], point(100.2568, 106.11979));
    assert_eq!(cubic.points[2], point(101.01273, 111.979164));
    assert_eq!(cubic.points[24], point(200.0, 175.0));
    assert_eq!(cubic.points[47], point(299.7432, 106.11979));
    assert_eq!(cubic.points[48], point(300.0, 100.0));
    assert_eq!(bits(&cubic.points[1..]), 108_177_547_226);
    // The same curve in relative numbers is the same points.
    let relative = read_path("m100 100 c0 100 200 100 200 0", "none").unwrap();
    assert_eq!(relative.points, cubic.points);
    // A quadratic segment whose control polygon is 60 long: ten steps.
    let quadratic = read_path("M100 100 Q130 100 130 130", "none").unwrap();
    assert_eq!(quadratic.points.len(), 1 + 10);
    assert_eq!(quadratic.points[1], point(105.7, 100.3));
    assert_eq!(quadratic.points[5], point(122.5, 107.5));
    assert_eq!(quadratic.points[10], point(130.0, 130.0));
    assert_eq!(bits(&quadratic.points[1..]), 22_450_896_896);
    assert_eq!(
        read_path("m100 100 q30 0 30 30", "none").unwrap().points,
        quadratic.points
    );
    // Never fewer than four steps, never more than forty-eight.
    let short = read_path("M100 100 C101 100 102 100 103 101", "none").unwrap();
    assert_eq!(short.points.len(), 1 + 4);
    assert_eq!(short.points[1], point(100.75, 100.015625));
    assert_eq!(bits(&short.points[1..]), 8_964_415_488);
    let seven = read_path("M100 100 C120 100 120 100 120 120", "none").unwrap();
    assert_eq!(seven.points.len(), 1 + 7);
    assert_eq!(seven.points[1], point(107.40525, 100.05831));
    assert_eq!(bits(&seven.points[1..]), 15_706_619_904);
    let long = read_path("M100 100 Q200 300 300 100", "none").unwrap();
    assert_eq!(long.points.len(), 1 + 48);
    assert_eq!(long.points[24], point(200.0, 200.0));
    assert_eq!(bits(&long.points[1..]), 108_245_407_064);
    // A closed curved zone, read again and again: the same bits.
    let lens = "M400 100 Q500 0 600 100 Q500 200 400 100 Z";
    let first = read_path(lens, "#ffffff").unwrap();
    assert_eq!(first.style.kind, KIND_CONTOUR);
    assert_eq!(first.points.len(), 96);
    for _ in 0..3 {
        assert_eq!(
            bits(&read_path(lens, "#ffffff").unwrap().points),
            bits(&first.points)
        );
    }
}

#[test]
fn the_reader_refuses_the_paths_a_page_does_not_use() {
    let white = "#ffffff";
    for (d, fill) in [
        // Arcs and smooth curves.
        ("M10 10 A5 5 0 0 1 20 20", "none"),
        ("M10 10 a5 5 0 0 1 10 10", "none"),
        ("M10 10 S20 20 30 10", "none"),
        ("M10 10 s10 10 20 0", "none"),
        ("M10 10 Q20 20 30 10 T50 10", "none"),
        ("M10 10 Q20 20 30 10 t20 0", "none"),
        // One subpath, from its M; Z at the very end only.
        ("M10 10 L20 20 M30 30 L40 40", "none"),
        ("M10 10 L20 20 m5 5", "none"),
        ("M10 10 L20 10 L20 20 Z L30 30", "none"),
        ("M10 10 L20 10 L20 20 Z Z", "none"),
        ("M10 10 L50 10 L50 50 Z M60 60 L90 60 L90 90 Z", white),
        ("M10 10 L20 10 L20 20 z 5", "none"),
        ("L10 10 L20 20", "none"),
        ("10 10 L20 20", "none"),
        ("Z", "none"),
        ("", "none"),
        (" ", "none"),
        ("M10 10", "none"),
        // Numbers: complete, plain and well separated.
        ("M10 10 L20", "none"),
        ("M10 10 C20 20 30 30 40", "none"),
        ("M10 10 Q20 20 30", "none"),
        ("M10 10 H", "none"),
        ("M10 10 H20 V", "none"),
        ("M1e1 10 L20 20", "none"),
        ("M10 10 L20 20e0", "none"),
        ("M+10 10 L20 20", "none"),
        ("M.5 10 L20 20", "none"),
        ("M10. 10 L20 20", "none"),
        ("M10,,10 L20 20", "none"),
        ("M,10 10 L20 20", "none"),
        ("M10 10, L20 20", "none"),
        ("M10-10 L20 20", "none"),
        ("M10 10 L20 NaN", "none"),
        ("M10 10 X20 20", "none"),
        ("M10 10 L20 20 é", "none"),
        // A fill on an open path; contours without an inside.
        ("M10 10 L20 20", white),
        ("M10 10 H50 V50", white),
        ("M10 10 L20 10 L30 10 Z", white),
        ("M10 10 L20 20 Z", white),
        ("M10 10 L10 10 Z", "none"),
        // Beyond the sheet, outline included, curves included.
        ("M2 10 L50 10 L50 50 Z", white),
        ("M10 10 L1199 10 L50 50 Z", "none"),
        ("M10 10 L50 10 l2000 0", "none"),
        ("M10 10 C10 -100 50 -100 50 10", "none"),
        (
            "M10 10 L50 10 l340282350000000000000000000000000000000 0",
            "none",
        ),
    ] {
        assert!(read_path(d, fill).is_err(), "read: {d} {fill}");
    }
    // The same paths without what refuses them read.
    for (d, fill) in [
        ("M10 10 Q20 20 30 10", "none"),
        ("M10 10 L20 20", "none"),
        ("M10 10 L50 10 L50 50 Z", white),
        ("M10 10 L20 10 L20 20 z", "none"),
        ("M10 10 C10 20 50 20 50 10", "none"),
    ] {
        assert!(read_path(d, fill).is_ok(), "read: {d} {fill}");
    }
}

#[test]
fn a_path_holds_at_most_the_points_of_one_stroke() {
    // Pairs of curves there and back, 48 points each: 96 points a pair.
    let wave = |pairs: usize| {
        let mut d = String::from("M400 400 c");
        for _ in 0..pairs {
            d.push_str(" 0 300 300 300 300 0 0 -300 -300 -300 -300 0");
        }
        d
    };
    let largest = wave(1041);
    let read = read_path(&largest, "none").unwrap();
    assert_eq!(read.points.len(), 1 + 96 * 1041);
    assert!(read.points.len() <= MAX_STROKE_POINTS);
    let svg = page(&path_element(&wave(1042), "none"));
    assert!(svg.len() <= MAX_PAGE_BYTES);
    assert!(read_page(&svg).is_err());
}
