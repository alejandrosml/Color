//! Tests of the pictures read from SVG. The library that reads them is pinned
//! to one exact version, kept in vendor/: descriptions are compared to the
//! letter, and a change of that library shows here first.
use super::*;
use std::ffi::CStr;

const HEAD: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50">"#;

fn picture(body: &str) -> String {
    format!("{HEAD}{body}</svg>")
}

fn read(svg: &str) -> Result<String, Refusal> {
    let mut out = String::new();
    describe("-", svg, &mut out).map(|()| out)
}

// The lines between the header and the end mark of a picture of 100 by 50.
fn lines(body: &str) -> Vec<String> {
    let text = read(&picture(body)).expect("the picture is read");
    let mut lines: Vec<String> = text.lines().map(str::to_owned).collect();
    assert_eq!(lines.remove(0), "P - 100 50");
    assert_eq!(lines.pop().as_deref(), Some("X"));
    lines
}

fn through_c(svg: &[u8]) -> Option<String> {
    let text = unsafe { ep_picture_from_svg(svg.as_ptr(), svg.len()) };
    if text.is_null() {
        return None;
    }
    let owned = unsafe { CStr::from_ptr(text) }.to_str().unwrap().to_owned();
    unsafe { ep_string_free(text) };
    Some(owned)
}

#[test]
fn the_catalogue_holds_exactly_the_files_of_the_interface_folder() {
    // Names that start with a dot are what a file manager leaves in a
    // folder it has shown (.DS_Store, ._film.svg): they are not pictures.
    let mut files: Vec<String> = std::fs::read_dir("art/interface")
        .expect("tests run from the folder of the core")
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .filter(|name| !name.starts_with('.'))
        .collect();
    files.sort();
    let keys: Vec<String> = INTERFACE
        .iter()
        .map(|(key, _)| format!("{key}.svg"))
        .collect();
    assert_eq!(
        files, keys,
        "one line of INTERFACE per file, in the order of the keys"
    );
    for (key, _) in INTERFACE {
        assert!(
            !key.is_empty()
                && key
                    .bytes()
                    .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-'),
            "{key}"
        );
    }
    assert_eq!(ep_art_count() as usize, INTERFACE.len());
}

#[test]
fn every_picture_of_the_interface_reads_on_its_grid() {
    let mut whole = String::new();
    for (key, svg) in INTERFACE {
        let mut out = String::new();
        describe(key, svg, &mut out).unwrap_or_else(|refusal| panic!("{key}: {refusal:?}"));
        // The small pictures are drawn on a grid of 64. The logo and the
        // companion of the window are drawings of 512, made of groups that
        // each keep their placement: their outlines are only asked to be
        // finite numbers.
        let (side, beyond): (f32, f32) = if matches!(*key, "logo" | "mascotte") {
            (512.0, f32::MAX)
        } else {
            (64.0, 2.0)
        };
        let mut lines = out.lines();
        assert_eq!(
            lines.next(),
            Some(format!("P {key} {side} {side}").as_str())
        );
        assert_eq!(out.lines().last(), Some("X"));
        let mut drawn = 0;
        for line in out.lines().filter(|line| line.starts_with("D ")) {
            drawn += 1;
            // Every number of every outline lies on the grid, strokes aside.
            let outline = line.splitn(5, ' ').nth(4).unwrap();
            for token in outline.split(' ') {
                if let Ok(value) = token.parse::<f32>() {
                    assert!((-beyond..=side + beyond).contains(&value), "{key}: {value}");
                }
            }
        }
        assert!(drawn > 0, "{key}");
        assert!(out.is_ascii(), "{key}");
        whole.push_str(&out);
    }
    assert_eq!(catalogue(), Some(whole.as_str()));
    let text = ep_art_catalog();
    assert!(!text.is_null());
    assert_eq!(unsafe { CStr::from_ptr(text) }.to_str().unwrap(), whole);
    unsafe { ep_string_free(text) };
}

#[test]
fn outlines_keep_their_paints() {
    assert_eq!(
        lines(r##"<rect x="10" y="5" width="30" height="20" fill="#43ac9c"/>"##),
        ["D f #43ac9cff,n - M 10 5 L 40 5 L 40 25 L 10 25 Z"]
    );
    assert_eq!(
        lines(
            r##"<path d="M10 10 L 90 40" fill="none" stroke="#293d4b" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>"##
        ),
        ["D f - #293d4bff,2.5,rr,4 M 10 10 L 90 40"]
    );
    assert_eq!(
        lines(
            r##"<path d="M0 0H10V10" fill="none" stroke="black" stroke-linecap="square" stroke-linejoin="bevel" stroke-miterlimit="7"/>"##
        ),
        ["D f - #000000ff,1,sb,7 M 0 0 L 10 0 L 10 10"]
    );
    // Curves stay curves: nothing is flattened on the way.
    assert_eq!(
        lines(r##"<path d="M0 0 Q 5 10 10 0 C 12 2 14 4 16 6"/>"##),
        ["D f #000000ff,n - M 0 0 Q 5 10 10 0 C 12 2 14 4 16 6"]
    );
    assert_eq!(
        lines(r##"<path d="M0 0H10V10H0Z M2 2H8V8H2Z" fill-rule="evenodd"/>"##),
        ["D f #000000ff,e - M 0 0 L 10 0 L 10 10 L 0 10 Z M 2 2 L 8 2 L 8 8 L 2 8 Z"]
    );
    assert_eq!(
        lines(r##"<rect width="10" height="10" fill="red" stroke="black" paint-order="stroke"/>"##),
        ["D s #ff0000ff,n #000000ff,1,bm,4 M 0 0 L 10 0 L 10 10 L 0 10 Z"]
    );
    // The colour of the text around an SVG is not known here: usvg takes
    // black for `currentColor`.
    assert_eq!(
        lines(r##"<rect width="10" height="10" fill="currentColor"/>"##),
        ["D f #000000ff,n - M 0 0 L 10 0 L 10 10 L 0 10 Z"]
    );
}

#[test]
fn opacities_become_alpha_or_a_group() {
    // Of one paint: its alpha. Of an element: a group painted as a whole.
    assert_eq!(
        lines(
            r##"<rect width="10" height="10" fill="#ffcd62" fill-opacity="0.5" stroke="red" stroke-opacity="0.25" opacity="0.5"/>"##
        ),
        [
            "G 0.5 -",
            "D f #ffcd6280,n #ff000040,1,bm,4 M 0 0 L 10 0 L 10 10 L 0 10 Z",
            "E"
        ]
    );
    assert_eq!(
        lines(
            r##"<g opacity="0.5"><rect width="10" height="10"/><rect x="5" width="10" height="10" fill="blue"/></g>"##
        ),
        [
            "G 0.5 -",
            "D f #000000ff,n - M 0 0 L 10 0 L 10 10 L 0 10 Z",
            "D f #0000ffff,n - M 5 0 L 15 0 L 15 10 L 5 10 Z",
            "E"
        ]
    );
}

#[test]
fn transforms_stay_on_their_groups() {
    // The matrix is the one of SVG: a b c d e f.
    assert_eq!(
        lines(r##"<g transform="translate(10 20) scale(2)"><rect width="10" height="10"/></g>"##),
        [
            "G 1 2;0;0;2;10;20",
            "D f #000000ff,n - M 0 0 L 10 0 L 10 10 L 0 10 Z",
            "E"
        ]
    );
    assert_eq!(
        lines(r##"<rect width="10" height="10" transform="matrix(1 2 3 4 5 6)"/>"##),
        [
            "G 1 1;2;3;4;5;6",
            "D f #000000ff,n - M 0 0 L 10 0 L 10 10 L 0 10 Z",
            "E"
        ]
    );
    // A view box and a size in millimetres are a transform of the whole.
    assert_eq!(
        read(
            r##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="10 10 100 50"><rect x="10" y="10" width="100" height="50"/></svg>"##
        )
        .unwrap(),
        "P - 200 100\nG 1 2;0;0;2;-20;-20\nD f #000000ff,n - M 10 10 L 110 10 L 110 60 L 10 60 Z\nE\nX\n"
    );
    let millimetres = read(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="210mm" height="148mm" viewBox="0 0 210 148"><rect width="210" height="148"/></svg>"##,
    )
    .unwrap();
    assert!(millimetres.starts_with("P - 793.7008 559.3701\nG 1 3.7795277;0;0;3.7795277;0;0\n"));
    assert_eq!(
        read(
            r##"<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64"/></svg>"##
        )
        .unwrap(),
        "P - 64 64\nD f #000000ff,n - M 0 0 L 64 0 L 64 64 L 0 64 Z\nX\n"
    );
}

#[test]
fn gradients_keep_their_geometry_and_their_stops() {
    // In the units of the box of the shape: the matrix carries the box.
    assert_eq!(
        lines(
            r##"<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff" stop-opacity="0.5"/></linearGradient></defs><rect x="10" y="10" width="80" height="30" fill="url(#g)" fill-opacity="0.5"/>"##
        ),
        ["D f L:0:0:1:0:p:80;0;0;30;10;10:0=#ff000080/1=#0000ff40,n - M 10 10 L 90 10 L 90 40 L 10 40 Z"]
    );
    assert_eq!(
        lines(
            r##"<defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="50" cy="25" r="20" fx="45" fy="20" spreadMethod="reflect" gradientTransform="scale(1 0.5)"><stop offset="0.2" stop-color="white"/><stop offset="1" stop-color="black"/></radialGradient></defs><rect width="100" height="50" stroke="url(#g)" fill="none" stroke-width="4"/>"##
        ),
        ["D f - R:50:25:20:45:20:0:m:1;0;0;0.5;0;0:0.2=#ffffffff/1=#000000ff,4,bm,4 M 0 0 L 100 0 L 100 50 L 0 50 Z"]
    );
    assert_eq!(
        lines(
            r##"<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="100" y2="0" spreadMethod="repeat"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient></defs><rect width="100" height="50" fill="url(#g)"/>"##
        ),
        ["D f L:0:0:100:0:r:-:0=#ff0000ff/1=#0000ffff,n - M 0 0 L 100 0 L 100 50 L 0 50 Z"]
    );
}

#[test]
fn clips_are_given_in_the_coordinates_of_what_they_clip() {
    // Two outlines make one clip, each with its own rule and placement.
    assert_eq!(
        lines(
            r##"<defs><clipPath id="c"><rect x="30" y="5" width="40" height="40"/><rect x="0" y="0" width="10" height="10" clip-rule="evenodd" transform="translate(5 5)"/></clipPath></defs><g clip-path="url(#c)"><rect width="100" height="50" fill="green"/></g>"##
        ),
        [
            "G 1 -",
            "C",
            "K n M 30 5 L 70 5 L 70 45 L 30 45 Z",
            "K e M 5 5 L 15 5 L 15 15 L 5 15 Z",
            "D f #008000ff,n - M 0 0 L 100 0 L 100 50 L 0 50 Z",
            "E"
        ]
    );
    // In the units of the box of the clipped shape.
    assert_eq!(
        lines(
            r##"<defs><clipPath id="c" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath></defs><rect x="20" y="10" width="60" height="30" fill="green" clip-path="url(#c)"/>"##
        ),
        [
            "G 1 -",
            "C",
            "K n M 20 10 L 50 10 L 50 40 L 20 40 Z",
            "D f #008000ff,n - M 20 10 L 80 10 L 80 40 L 20 40 Z",
            "E"
        ]
    );
    // A clip that is itself clipped: two clips that narrow each other.
    assert_eq!(
        lines(
            r##"<defs><clipPath id="a"><rect width="50" height="50"/></clipPath><clipPath id="b" clip-path="url(#a)"><rect x="25" width="50" height="50"/></clipPath></defs><rect width="100" height="50" clip-path="url(#b)"/>"##
        ),
        [
            "G 1 -",
            "C",
            "K n M 25 0 L 75 0 L 75 50 L 25 50 Z",
            "C",
            "K n M 0 0 L 50 0 L 50 50 L 0 50 Z",
            "D f #000000ff,n - M 0 0 L 100 0 L 100 50 L 0 50 Z",
            "E"
        ]
    );
}

#[test]
fn dashes_are_cut_into_the_stroke() {
    assert_eq!(
        lines(r##"<path d="M0 10 H 10" stroke="black" stroke-dasharray="2 2" fill="none"/>"##),
        ["D f - #000000ff,1,bm,4 M 0 10 L 2 10 M 4 10 L 6 10 M 8 10 L 10 10"]
    );
    // The inside keeps the whole outline; the order of painting is kept.
    let both = lines(
        r##"<rect width="10" height="10" fill="red" stroke="black" stroke-dasharray="5 5"/>"##,
    );
    assert_eq!(both.len(), 2);
    assert_eq!(both[0], "D f #ff0000ff,n - M 0 0 L 10 0 L 10 10 L 0 10 Z");
    assert!(both[1].starts_with("D f - #000000ff,1,bm,4 M "));
    let stroke_first = lines(
        r##"<rect width="10" height="10" fill="red" stroke="black" stroke-dasharray="5 5" paint-order="stroke"/>"##,
    );
    assert_eq!(stroke_first, [both[1].clone(), both[0].clone()]);
}

#[test]
fn what_drawing_programs_write_is_read() {
    // Styles in a sheet, a shape used four times, a gradient, millimetres,
    // a clip, a foreign namespace: nothing of it is left to the interface.
    let svg = r##"<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" width="210mm" height="148mm" viewBox="0 0 210 148">
  <style>.trait { fill: none; stroke: #222; stroke-width: 1.2 } .zone { fill: white; stroke: #222 }</style>
  <defs>
    <linearGradient id="ciel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9cf"/><stop offset="1" stop-color="#fff"/></linearGradient>
    <clipPath id="cadre"><rect x="5" y="5" width="200" height="138" rx="6"/></clipPath>
    <path id="petale" d="M0 0 C 6 -10 14 -10 20 0 C 14 10 6 10 0 0 Z"/>
  </defs>
  <g clip-path="url(#cadre)" inkscape:label="fond"><rect width="210" height="148" fill="url(#ciel)"/></g>
  <g id="fleur" transform="translate(100 70)">
    <use xlink:href="#petale" class="zone"/>
    <use xlink:href="#petale" class="zone" transform="rotate(90)"/>
    <use href="#petale" class="zone" transform="rotate(180)"/>
    <use href="#petale" class="zone" transform="rotate(270)"/>
    <circle r="5" class="zone" style="fill:#fc3"/>
  </g>
  <path class="trait" d="M100 80 q 5 30 -2 60" stroke-dasharray="4 2"/>
</svg>"##;
    let text = read(svg).unwrap();
    let count = |start: &str| text.lines().filter(|line| line.starts_with(start)).count();
    assert_eq!(count("D "), 7);
    assert_eq!(count("C"), 1);
    assert_eq!(
        count("D f #ffffffff,n #222222ff,1,bm,4 M 0 0 C 6 -10 14 -10 20 0 "),
        4
    );
    assert_eq!(count("D f #ffcc33ff,n #222222ff,1,bm,4 "), 1);
    assert_eq!(count("D f L:0:0:0:1:p:"), 1);
    assert_eq!(count("D f - #222222ff,1.2,bm,4 "), 1);
    assert_eq!(count("G "), count("E"));
}

#[test]
fn a_mark_of_origin_changes_nothing() {
    // The tool that delivers files to the owner inserts such a block right
    // after the opening tag of an SVG.
    let plain = picture(r##"<rect width="10" height="10" fill="#9a82c9"/>"##);
    let marked = plain.replace(
        HEAD,
        r#"<svg xmlns="http://www.w3.org/2000/svg" xmlns:c2pa="http://c2pa.org/manifest" viewBox="0 0 100 50"><metadata><c2pa:manifest>AAAA<rect/>&amp;]]&gt;BBBB</c2pa:manifest></metadata>"#,
    );
    assert_ne!(plain, marked);
    assert_eq!(read(&plain), read(&marked));
}

#[test]
fn what_is_not_drawn_is_refused_whole() {
    let refused = |body: &str| read(&picture(body)).unwrap_err();
    assert_eq!(
        refused(
            r##"<defs><mask id="m"><rect width="50" height="50" fill="white"/></mask></defs><rect width="100" height="50" mask="url(#m)"/>"##
        ),
        Refusal::Unsupported("a mask")
    );
    assert_eq!(
        refused(
            r##"<defs><filter id="f"><feGaussianBlur stdDeviation="2"/></filter></defs><rect width="100" height="50" filter="url(#f)"/>"##
        ),
        Refusal::Unsupported("a filter")
    );
    assert_eq!(
        refused(
            r##"<defs><pattern id="p" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="5" height="5"/></pattern></defs><rect width="100" height="50" fill="url(#p)"/>"##
        ),
        Refusal::Unsupported("a pattern")
    );
    assert_eq!(
        refused(
            r##"<rect width="10" height="10"/><rect width="10" height="10" fill="red" style="mix-blend-mode:multiply"/>"##
        ),
        Refusal::Unsupported("a blend mode")
    );
    assert_eq!(
        refused(r##"<text x="10" y="20">Bonjour</text><rect width="1" height="1"/>"##),
        Refusal::Unsupported("text")
    );
    assert_eq!(
        refused(
            r##"<defs><marker id="k" markerWidth="4" markerHeight="4"><path d="M0 0L4 2L0 4Z"/></marker></defs><path d="M0 0L10 10" stroke="black" marker-end="url(#k)"/>"##
        ),
        Refusal::Unsupported("a marker")
    );
    // Refused for being there, used or not: nothing is converted first.
    assert_eq!(
        refused(r##"<defs><filter id="f"><feFlood/></filter></defs><rect width="1" height="1"/>"##),
        Refusal::Unsupported("a filter")
    );
    // An image inside the file, or one on the disk: neither is opened.
    assert_eq!(
        refused(
            r##"<image width="10" height="10" href="data:image/png;base64,iVBORw0KGgo="/><rect width="1" height="1"/>"##
        ),
        Refusal::Unsupported("an embedded image")
    );
    assert_eq!(
        refused(
            r##"<image width="10" height="10" href="/etc/hostname"/><rect width="1" height="1"/>"##
        ),
        Refusal::Unsupported("an embedded image")
    );
    for nothing in [
        "",
        r##"<rect width="10" height="10" visibility="hidden"/>"##,
        r##"<rect width="10" height="10" display="none"/>"##,
        r##"<rect width="10" height="10" fill="none"/>"##,
    ] {
        assert_eq!(
            refused(nothing),
            Refusal::Unsupported("a picture that draws nothing"),
            "{nothing}"
        );
    }
    for unreadable in [
        "",
        "bonjour",
        "<svg",
        r#"<html xmlns="http://www.w3.org/1999/xhtml"><body/></html>"#,
        r#"<svg xmlns="http://www.w3.org/2000/svg" width="0" height="10"><rect width="1" height="1"/></svg>"#,
        r#"<svg xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1"/></svg><svg/>"#,
    ] {
        assert_eq!(read(unreadable), Err(Refusal::Unreadable), "{unreadable}");
    }
}

#[test]
fn bounds_are_kept() {
    // One outline too many.
    let mut body = String::new();
    for _ in 0..MAX_PICTURE_ITEMS {
        body.push_str(r#"<path d="M0 0H1V1Z"/>"#);
    }
    assert!(read(&picture(&body)).is_ok());
    body.push_str(r#"<path d="M0 0H1V1Z"/>"#);
    assert_eq!(read(&picture(&body)), Err(Refusal::TooLarge));
    // One segment too many, in few outlines.
    let mut long = String::from(r#"<path d="M0 0"#);
    for index in 0..MAX_PICTURE_SEGMENTS - 1 {
        long.push_str(if index % 2 == 0 { "h1" } else { "v1" });
    }
    assert!(read(&picture(&format!(r#"{long}"/>"#))).is_ok());
    assert_eq!(
        read(&picture(&format!(r#"{long}h1"/>"#))),
        Err(Refusal::TooLarge)
    );
    // Groups in groups.
    let nested = |depth: usize| {
        picture(&format!(
            r#"{}<rect width="1" height="1"/>{}"#,
            r#"<g opacity="0.9">"#.repeat(depth),
            "</g>".repeat(depth)
        ))
    };
    assert!(read(&nested(MAX_GROUP_DEPTH - 1)).is_ok());
    assert_eq!(read(&nested(MAX_GROUP_DEPTH + 2)), Err(Refusal::TooLarge));
    // Text beyond the size accepted from a caller.
    let mut huge = picture(r#"<rect width="1" height="1"/>"#);
    huge.push_str(&" ".repeat(MAX_SVG_BYTES + 1 - huge.len()));
    assert_eq!(huge.len(), MAX_SVG_BYTES + 1);
    assert_eq!(read(&huge), Err(Refusal::TooLarge));
    assert!(read(&huge[..MAX_SVG_BYTES]).is_ok());
}

#[test]
fn the_c_interface_answers_null_instead_of_failing() {
    let good = picture(r##"<rect width="10" height="10" fill="#9a82c9"/>"##);
    assert_eq!(
        through_c(good.as_bytes()).as_deref(),
        Some("P - 100 50\nD f #9a82c9ff,n - M 0 0 L 10 0 L 10 10 L 0 10 Z\nX\n")
    );
    assert!(unsafe { ep_picture_from_svg(ptr::null(), 10) }.is_null());
    assert!(unsafe { ep_picture_from_svg(good.as_ptr(), MAX_SVG_BYTES + 1) }.is_null());
    assert_eq!(through_c(b""), None);
    assert_eq!(through_c(&[0xff, 0xfe, b'<', b's']), None);
    let mut broken = good.clone().into_bytes();
    broken[20] = 0xc3; // the start of a character that never ends
    assert_eq!(through_c(&broken), None);
    assert_eq!(through_c(picture("<text>a</text>").as_bytes()), None);
}

// Any text at all gets an answer: the samples above, damaged a few thousand
// times each with a generator of our own, are read or refused, never more.
#[test]
fn damaged_pictures_are_read_or_refused() {
    let mut samples: Vec<String> = INTERFACE.iter().map(|(_, svg)| svg.to_string()).collect();
    samples.push(picture(
        r##"<defs><linearGradient id="g"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient><clipPath id="c"><circle cx="50" cy="25" r="20"/></clipPath></defs><g clip-path="url(#c)" opacity="0.5" transform="rotate(10)"><rect width="100" height="50" fill="url(#g)" stroke="black" stroke-dasharray="3 1"/></g>"##,
    ));
    let mut state = 0x9e37_79b9_7f4a_7c15_u64;
    let mut next = move |bound: usize| {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        (state % bound as u64) as usize
    };
    let pieces: [&[u8]; 12] = [
        b"<",
        b">",
        b"\"",
        b"/",
        b"url(#g)",
        b"-",
        b"e9",
        b"99999999",
        b"&",
        b"<g>",
        b"</g>",
        b" transform=\"scale(0)\"",
    ];
    let (mut read_whole, mut refused, mut compared) = (0, 0, 0);
    for sample in &samples {
        for _ in 0..2_000 {
            let mut bytes = sample.clone().into_bytes();
            for _ in 0..1 + next(3) {
                let at = next(bytes.len());
                match next(4) {
                    0 => bytes[at] = pieces[next(pieces.len())][0],
                    1 => {
                        let end = (at + 1 + next(24)).min(bytes.len());
                        bytes.drain(at..end);
                    }
                    2 => {
                        let piece = pieces[next(pieces.len())];
                        bytes.splice(at..at, piece.iter().copied());
                    }
                    _ => {
                        let end = (at + 1 + next(40)).min(bytes.len());
                        let copy = bytes[at..end].to_vec();
                        let to = next(bytes.len());
                        bytes.splice(to..to, copy);
                    }
                }
                if bytes.is_empty() {
                    break;
                }
            }
            if let Ok(text) = String::from_utf8(bytes) {
                match read(&text) {
                    Ok(_) => read_whole += 1,
                    Err(_) => refused += 1,
                }
                // The depth counted before the XML reader is the one that
                // reader goes down to, whenever it accepts the text: every
                // element above the deepest one is counted, and that one
                // too unless it is written `<a/>`.
                if let Ok(xml) = usvg::roxmltree::Document::parse(&text) {
                    let above = xml
                        .descendants()
                        .filter(|node| node.is_element())
                        .map(|node| node.ancestors().skip(1).filter(|a| a.is_element()).count())
                        .max()
                        .unwrap_or(0);
                    assert!(nesting_within(&text, above + 1), "{text}");
                    assert!(above == 0 || !nesting_within(&text, above - 1), "{text}");
                    compared += 1;
                }
            }
        }
    }
    // Both happen: the damage is neither harmless nor always fatal.
    assert!(
        read_whole > 100 && refused > 100,
        "{read_whole} read, {refused} refused"
    );
    assert!(compared > 100, "{compared} depths compared");
}

#[test]
fn nesting_is_counted_as_the_xml_reader_finds_it() {
    let depth = |text: &str| (0..=10).find(|limit| nesting_within(text, *limit));
    assert_eq!(depth(""), Some(0));
    assert_eq!(depth("no markup at all"), Some(0));
    assert_eq!(depth("<a/>"), Some(0));
    assert_eq!(depth("<a></a>"), Some(1));
    assert_eq!(depth("<a><b/><c><d/></c><e></e></a>"), Some(2));
    // A `>` or a `/` inside a quoted value closes nothing.
    assert_eq!(depth(r#"<a b=">" c='/>'><d e="/"></d></a>"#), Some(2));
    assert_eq!(depth(r#"<a b='"' c="'"><d/></a>"#), Some(1));
    // Comments, character data and instructions hold no element.
    assert_eq!(depth("<a><!-- <b><c><d> --><e/></a>"), Some(1));
    assert_eq!(depth("<a><![CDATA[<b><c><d>]]></a>"), Some(1));
    assert_eq!(depth("<?xml version=\"1.0\"?><?p <b><c> ?><a/>"), Some(0));
    assert_eq!(
        depth("<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"x.dtd\" [<!ELEMENT a (b)>]><a><b/></a>"),
        Some(1)
    );
    // Left open: counted as far as it goes, never less.
    assert_eq!(depth("<a><b><c>"), Some(3));
    assert_eq!(depth("<a><b"), Some(1));
    assert_eq!(depth("<a><!-- never closed <b><c>"), Some(1));
    // Too many closing tags do not hide what follows a refusal of the reader.
    assert_eq!(depth("</a></a><a><b><c/></b></a>"), Some(2));
    let deep = format!("{}{}", "<g>".repeat(11), "</g>".repeat(11));
    assert_eq!(depth(&deep), None);
}

#[test]
fn entities_are_refused_before_anything_expands() {
    // One entity of half a megabyte, named two thousand times: a gigabyte.
    let bomb = format!(
        r#"<!DOCTYPE svg [<!ENTITY a "{}">]><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><title>{}</title><rect width="1" height="1"/></svg>"#,
        "A".repeat(500_000),
        "&a;".repeat(2_000)
    );
    assert!(bomb.len() < MAX_SVG_BYTES);
    let started = std::time::Instant::now();
    assert_eq!(read(&bomb), Err(Refusal::Unsupported("entities")));
    assert_eq!(through_c(bomb.as_bytes()), None);
    assert!(started.elapsed().as_secs() < 5);
    // The same in an attribute, and the ordinary use of drawing programs.
    for text in [
        r#"<!DOCTYPE svg [<!ENTITY a "AAAA">]><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect id="&a;&a;" width="1" height="1"/></svg>"#,
        r#"<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd" [<!ENTITY ns_svg "http://www.w3.org/2000/svg">]><svg xmlns="&ns_svg;" viewBox="0 0 10 10"><rect width="1" height="1"/></svg>"#,
        r#"<!DOCTYPE svg [<!ENTITY % p "x">]><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="1" height="1"/></svg>"#,
    ] {
        assert_eq!(read(text), Err(Refusal::Unsupported("entities")), "{text}");
    }
    // A document type without entities is still read, and the five entities
    // that XML always has are not declared ones.
    let plain = r#"<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><title>a &amp; b &lt; c</title><rect width="1" height="1"/></svg>"#;
    assert!(read(plain).is_ok());
}

#[test]
fn numbers_of_ten_million_or_more_are_refused_before_anything_is_read() {
    // An elliptical arc of radius 6e93 — one damaged digit of a real drawing
    // — asked the library that turns arcs into curves for more memory than
    // the machine had: the whole program was stopped.
    let arc = |radius: &str| {
        picture(&format!(
            r##"<path d="M10 50 a40 {radius} 0 1 0 80 0 Z" fill="#f4cdb4"/>"##
        ))
    };
    assert_eq!(read(&arc("6e93")), Err(Refusal::TooLarge));
    for written in ["1e7", "1E+7", "10000000", ".5e9", "-2e7", "999999.9e2"] {
        assert_eq!(read(&arc(written)), Err(Refusal::TooLarge), "{written}");
    }
    // Under ten million, and whatever the way it is written, a number is read.
    for written in [
        "40",
        "9999999",
        "1234567.5",
        "1e6",
        "1E+06",
        "0.000001e12",
        "-5e5",
        "1.5e-3",
        "007",
    ] {
        assert!(read(&arc(written)).is_ok(), "{written}");
    }
    // Letters and digits of a name or of a colour are not a number.
    assert!(read(&picture(
        r##"<rect id="r99999999" width="10" height="10" fill="#ffe9ad"/>"##
    ))
    .is_ok());
    // Through the C interface too.
    let text = arc("6e93");
    assert!(through_c(text.as_bytes()).is_none());
}

#[test]
fn deep_texts_and_long_chains_are_refused_or_read_never_more() {
    // Elements inside elements: refused before the XML reader goes down.
    for depth in [MAX_XML_DEPTH + 1, 1_000, 100_000] {
        let text = picture(&format!(
            r#"{}<rect width="1" height="1"/>{}"#,
            "<g>".repeat(depth),
            "</g>".repeat(depth)
        ));
        assert_eq!(read(&text), Err(Refusal::TooLarge), "{depth}");
        assert_eq!(through_c(text.as_bytes()), None);
    }
    // Left open, as deep as a megabyte allows: the same.
    let open = format!("{HEAD}{}", "<g>".repeat(300_000));
    assert_eq!(read(&open), Err(Refusal::TooLarge));
    // The same from a thread with a very small stack: the depth of the
    // caller's stack is not what reads a picture.
    let small = std::thread::Builder::new()
        .stack_size(128 * 1024)
        .spawn(|| {
            let wide = picture(&format!(
                r#"{}<rect width="1" height="1"/>{}"#,
                "<g>".repeat(MAX_GROUP_DEPTH - 2),
                "</g>".repeat(MAX_GROUP_DEPTH - 2)
            ));
            // Groups that change nothing are not written: the header, the
            // outline and the end.
            read(&wide).map(|text| text.lines().count())
        })
        .unwrap()
        .join()
        .unwrap();
    assert_eq!(small, Ok(3));
    // Chains of references, each link sending the library one step down:
    // a clip that is clipped by the next, and a clip whose outline is.
    let links = 400;
    let mut chain = String::new();
    let mut inner = String::new();
    for index in 0..links {
        chain.push_str(&format!(
            r##"<clipPath id="c{index}" clip-path="url(#c{})"><rect width="50" height="50"/></clipPath>"##,
            index + 1
        ));
        inner.push_str(&format!(
            r##"<clipPath id="d{index}"><rect width="50" height="50" clip-path="url(#d{})"/></clipPath>"##,
            index + 1
        ));
    }
    chain.push_str(&format!(
        r##"<clipPath id="c{links}"><rect width="50" height="50"/></clipPath><rect width="10" height="10" clip-path="url(#c0)"/>"##
    ));
    inner.push_str(&format!(
        r##"<clipPath id="d{links}"><rect width="50" height="50"/></clipPath><rect width="10" height="10" clip-path="url(#d0)"/>"##
    ));
    // Shapes that use shapes that use shapes.
    let mut uses = String::from("<defs>");
    for index in 1..=links {
        uses.push_str(&format!(
            r##"<g id="g{index}"><use href="#g{}"/><rect width="1" height="1"/></g>"##,
            index + 1
        ));
    }
    uses.push_str(&format!(
        r##"<g id="g{}"><rect width="10" height="10"/></g></defs><use href="#g1"/>"##,
        links + 1
    ));
    for body in [&chain, &inner, &uses] {
        // Read or refused: the answer comes back, which is the assertion.
        let _ = read(&picture(body));
        let _ = through_c(picture(body).as_bytes());
    }
    // More nodes than a picture may have.
    let many = picture(&"<g/>".repeat(MAX_XML_NODES as usize + 1));
    assert_eq!(read(&many), Err(Refusal::Unreadable));
}

#[test]
fn an_outline_of_one_segment_has_no_inside() {
    // SVG gives a line no inside, whatever its `fill` says.
    assert_eq!(
        lines(r##"<line x1="1" y1="2" x2="30" y2="40" stroke="#ff0000" fill="#0000ff"/>"##),
        ["D f - #ff0000ff,1,bm,4 M 1 2 L 30 40"]
    );
    assert_eq!(
        lines(
            r##"<path d="M1 2L30 40Z" stroke="#ff0000" stroke-dasharray="4 2" fill="#0000ff"/>"##
        )
        .iter()
        .filter(|line| line.contains("#0000ffff"))
        .count(),
        0
    );
    // Alone, such an inside draws nothing at all.
    assert_eq!(
        read(&picture(r##"<path d="M1 2L30 40" fill="#0000ff"/>"##)),
        Err(Refusal::Unsupported("a picture that draws nothing"))
    );
    // Two segments enclose something, and so does one curve.
    assert_eq!(
        lines(r##"<path d="M0 0L10 0L10 10" fill="#0000ff"/>"##),
        ["D f #0000ffff,n - M 0 0 L 10 0 L 10 10"]
    );
    assert_eq!(
        lines(r##"<path d="M0 0Q10 10 20 0" fill="#0000ff"/>"##),
        ["D f #0000ffff,n - M 0 0 Q 10 10 20 0"]
    );
    // In an outline of several parts, one part with an inside is enough.
    assert_eq!(
        lines(r##"<path d="M0 0L5 5M10 0L20 0L20 10Z" fill="#0000ff"/>"##).len(),
        1
    );
}
