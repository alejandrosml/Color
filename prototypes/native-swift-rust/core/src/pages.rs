//! Colouring pages: original drawings kept as SVG files of `art/coloriages/`
//! and compiled into the library. A page makes a new document of three
//! layers, bottom to top: its zones, every filled element filled with white
//! and with no visible outline, which the paint pot of the interface colours
//! one by one; an empty layer, active, where the child draws; its lines, the
//! outline of every element without what a filled element drawn after it
//! hides on the sheet of the file (see clip.rs), so that the document looks
//! like the file. The zones and the lines are locked layers (see layers.rs)
//! and nothing of the page is in the history: paint goes under the lines and
//! over the zones, and no tool and no undo can take the page apart. Such a
//! drawing is saved as project v5.
//!
//! A page uses a small part of SVG, read here with the XML reader that usvg
//! brings: `rect` (x, y, width, height), `circle` (cx, cy, r), `ellipse`
//! (cx, cy, rx, ry), `line` (x1, y1, x2, y2), `polyline` (points) and `path`
//! (d), each with `fill` (`#ffffff` or `none`, always `none` for a line, a
//! polyline and an open path), `stroke` (`#rrggbb`) and `stroke-width`, in
//! plain decimal numbers; one `title`, the name shown to the child; at most
//! one `desc`; comments. The root gives the size of the sheet as
//! `viewBox="0 0 <width> <height>"`, may repeat it as `width` and `height`,
//! and may say `stroke-linecap="round"` and `stroke-linejoin="round"`, which
//! is how the sheet draws every outline: the thumbnail then looks like the
//! drawing. No transform, group, style or unit: what the file says is
//! exactly what the document receives. A file that says anything else is
//! refused whole, and so is one that draws beyond the sheet, outlines
//! included.
//!
//! The `d` of a path is one subpath: `M` or `m` first, then `L l H h V v C c
//! Q q` with the implicit repetition of SVG (the pairs after the first one of
//! a moveto are lines), and `Z` or `z` at the very end only. Arcs (`A a`) and
//! smooth curves (`S s T t`) are refused. Numbers are plain decimals
//! separated by white space or commas as in `points`; a letter may follow a
//! number directly. A closed path, ending with `Z`, is a contour: a zone
//! when it is filled, an outline otherwise. An open path is a freehand
//! detail. Curves are flattened when the page is read, the same way on every
//! machine: a cubic or quadratic segment becomes n points at equal steps of
//! its parameter, n being the length of its control polygon divided by 6,
//! rounded up and kept within 4..48, computed in f64 and stored in f32.
//! Consecutive points that coincide are kept once, and the last point of a
//! closed path is dropped when it is the first one again.
//!
//! The thumbnail of a page is its description by `art::describe`, with every
//! guard of that reader, as for the pictures of the interface.
use super::*;
use crate::art::{describe, owned_text};
use std::sync::OnceLock;
use usvg::roxmltree::{Document, Node, ParsingOptions};

mod clip;

/// The pages, in the order of their keys, which are their file names
/// without `.svg`. An identifier is a position in this table: it holds for
/// this library only, and no project ever stores one.
static PAGES: &[(&str, &str)] = &[
    ("bateau", include_str!("../art/coloriages/bateau.svg")),
    (
        "bonhomme-de-neige",
        include_str!("../art/coloriages/bonhomme-de-neige.svg"),
    ),
    ("chat", include_str!("../art/coloriages/chat.svg")),
    ("chenille", include_str!("../art/coloriages/chenille.svg")),
    ("dinosaure", include_str!("../art/coloriages/dinosaure.svg")),
    ("fleur", include_str!("../art/coloriages/fleur.svg")),
    ("fusee", include_str!("../art/coloriages/fusee.svg")),
    ("maison", include_str!("../art/coloriages/maison.svg")),
    ("poisson", include_str!("../art/coloriages/poisson.svg")),
    ("robot", include_str!("../art/coloriages/robot.svg")),
    ("tortue", include_str!("../art/coloriages/tortue.svg")),
    ("voiture", include_str!("../art/coloriages/voiture.svg")),
];

/// Largest text of one page: a page is a few kilobytes.
const MAX_PAGE_BYTES: usize = 64 * 1024;
/// Nodes of the XML tree of one page, elements and the texts between them,
/// before anything is read from it.
const MAX_PAGE_NODES: u32 = 4096;
/// Drawn elements of one page.
const MAX_PAGE_OBJECTS: usize = 500;
/// Bytes of the UTF-8 of a title, and of a description.
const MAX_TITLE_BYTES: usize = 120;
const MAX_DESC_BYTES: usize = 2048;
const SVG_NAMESPACE: &str = "http://www.w3.org/2000/svg";
const WHITE: u32 = 0x00ff_ffff;
/// A curve of a path gets one point per this length of its control polygon,
/// and never fewer or more points than the two bounds after it.
const CURVE_STEP: f64 = 6.0;
const MIN_CURVE_POINTS: f64 = 4.0;
const MAX_CURVE_POINTS: f64 = 48.0;
/// Identifiers of the three layers of the document of a page. The child
/// draws on 0, the identifier of the only layer of a new sheet.
const ZONES_LAYER: u8 = 1;
const DRAWING_LAYER: u8 = 0;
const LINES_LAYER: u8 = 2;
/// Outline of a zone: the thinnest there is, white, so that only its fill
/// shows; the line above it draws its edge.
const ZONE_WIDTH: f32 = 0.1;
// The zones of a page always fit in a document; its lines, which may be
// pieces of outlines, are counted when it is read.
const _: () = assert!(MAX_PAGE_OBJECTS <= MAX_STROKES);

/// Why a file is not a page: a few words for the tests, and for whoever
/// draws the next page.
pub(crate) type Refused = &'static str;
const TOO_MANY_OBJECTS: Refused = "more objects than a document holds";
const TOO_MANY_POINTS: Refused = "more points than a document holds";

/// One object of a page: an element as the file draws it, or a line of its
/// document.
pub(crate) struct PageObject {
    pub style: EpObjectStyle,
    pub rgb: u32,
    pub width: f32,
    pub points: Vec<EpPoint>,
}

/// A page read from its file.
pub(crate) struct Page {
    pub title: String,
    pub width: u32,
    pub height: u32,
    /// The drawn elements, in the order of the file.
    pub objects: Vec<PageObject>,
    /// Its lines layer, computed once: every outline in the order of the
    /// file, without what a filled element drawn after it hides.
    pub lines: Vec<PageObject>,
}

impl Page {
    /// Filled elements: the zones that the paint pot fills.
    pub fn regions(&self) -> usize {
        self.objects
            .iter()
            .filter(|object| object.style.fill_enabled == 1)
            .count()
    }

    /// Elements without a fill: lines, polylines, open paths, outlines.
    pub fn details(&self) -> usize {
        self.objects.len() - self.regions()
    }
}

// A plain decimal number: an optional minus sign, digits, an optional
// fraction. No exponent, unit or percentage: nothing that another reader of
// SVG could take for a different value.
fn number(text: &str) -> Result<f32, Refused> {
    const NOT_PLAIN: Refused = "a number that is not plain decimal";
    let text = text.trim_matches(|c: char| c.is_ascii_whitespace());
    let unsigned = text.strip_prefix('-').unwrap_or(text);
    let (whole, fraction) = unsigned.split_once('.').unwrap_or((unsigned, "0"));
    let digits = |part: &str| !part.is_empty() && part.bytes().all(|b| b.is_ascii_digit());
    if !digits(whole) || !digits(fraction) {
        return Err(NOT_PLAIN);
    }
    text.parse::<f32>()
        .ok()
        .filter(|value| value.is_finite())
        .ok_or(NOT_PLAIN)
}

// The fields of a list of numbers, as SVG writes them: separated by white
// space, by one comma, or by both. Two commas in a row leave an empty place,
// which SVG does not allow either.
fn fields(text: &str) -> Result<Vec<&str>, Refused> {
    let mut fields = Vec::new();
    for part in text.split(',') {
        let before = fields.len();
        fields.extend(part.split_ascii_whitespace());
        if fields.len() == before {
            return Err("an empty place in a list of numbers");
        }
    }
    Ok(fields)
}

fn colour(text: &str) -> Result<u32, Refused> {
    text.strip_prefix('#')
        .filter(|hex| hex.len() == 6 && hex.bytes().all(|b| b.is_ascii_hexdigit()))
        .and_then(|hex| u32::from_str_radix(hex, 16).ok())
        .ok_or("a colour that is not #rrggbb")
}

// The size of the sheet, from the root element.
fn sheet(root: Node<'_, '_>) -> Result<(u32, u32), Refused> {
    let mut size = None;
    for attribute in root.attributes() {
        match (attribute.namespace(), attribute.name(), attribute.value()) {
            (None, "viewBox", value) => {
                let dimension = |text: &str| {
                    text.parse::<u32>()
                        .ok()
                        .filter(|value| (1..=MAX_DIMENSION).contains(value))
                };
                if let ["0", "0", width, height] = fields(value)?.as_slice() {
                    size = dimension(width).zip(dimension(height));
                }
                if size.is_none() {
                    return Err("a viewBox other than 0 0 <width> <height>");
                }
            }
            // Checked once the viewBox is known.
            (None, "width" | "height", _) => {}
            (None, "stroke-linecap" | "stroke-linejoin", "round") => {}
            _ => return Err("an attribute of the root that a page does not use"),
        }
    }
    let (width, height) = size.ok_or("no viewBox")?;
    for (name, expected) in [("width", width), ("height", height)] {
        if let Some(value) = root.attribute(name) {
            if value.parse::<u32>() != Ok(expected) {
                return Err("a width or height other than the viewBox");
            }
        }
    }
    Ok((width, height))
}

// The text of a title or of a description: nothing but characters, without
// a control character, within `limit` bytes.
fn plain_text<'a>(node: Node<'a, '_>, limit: usize) -> Result<&'a str, Refused> {
    if node.attributes().next().is_some() || node.children().any(|child| !child.is_text()) {
        return Err("a title or a description that holds more than text");
    }
    let text = node.text().unwrap_or("").trim();
    if text.is_empty() || text.len() > limit || text.chars().any(char::is_control) {
        return Err("an empty, long or unprintable title or description");
    }
    Ok(text)
}

fn attribute<'a>(node: Node<'a, '_>, name: &str) -> Result<&'a str, Refused> {
    node.attribute(name).ok_or("a missing attribute")
}

fn numbers<const N: usize>(node: Node<'_, '_>, names: [&str; N]) -> Result<[f32; N], Refused> {
    let mut values = [0.0; N];
    for (value, name) in values.iter_mut().zip(names) {
        *value = number(attribute(node, name)?)?;
    }
    Ok(values)
}

// The two corners of the box of an ellipse.
fn ellipse(cx: f32, cy: f32, rx: f32, ry: f32) -> Result<(u32, Vec<EpPoint>), Refused> {
    if rx <= 0.0 || ry <= 0.0 {
        return Err("an empty circle or ellipse");
    }
    let corners = vec![
        EpPoint {
            x: cx - rx,
            y: cy - ry,
        },
        EpPoint {
            x: cx + rx,
            y: cy + ry,
        },
    ];
    Ok((3, corners))
}

// One point of a path, in the f32 of the document, unless it is the point
// just before it again.
fn add_point(points: &mut Vec<EpPoint>, (x, y): (f64, f64)) {
    let point = EpPoint {
        x: x as f32,
        y: y as f32,
    };
    if points.last() != Some(&point) {
        points.push(point);
    }
}

// A cubic (four control points) or quadratic (three) segment of a path,
// from the current point `control[0]`: its points at equal steps of the
// parameter, the start left out. The last step is exactly the end of the
// segment. Only + - * / and sqrt, which IEEE 754 rounds exactly, and no
// fused operation: a page gives the same points on every machine.
fn curve(points: &mut Vec<EpPoint>, control: &[(f64, f64)]) {
    let mut length = 0.0;
    for pair in control.windows(2) {
        let (dx, dy) = (pair[1].0 - pair[0].0, pair[1].1 - pair[0].1);
        length += (dx * dx + dy * dy).sqrt();
    }
    let steps = (length / CURVE_STEP)
        .ceil()
        .clamp(MIN_CURVE_POINTS, MAX_CURVE_POINTS) as usize;
    for step in 1..=steps {
        let t = step as f64 / steps as f64;
        let s = 1.0 - t;
        // The Bernstein weights of degree 3, or 2.
        let weights = if control.len() == 4 {
            [s * s * s, 3.0 * s * s * t, 3.0 * s * t * t, t * t * t]
        } else {
            [s * s, 2.0 * s * t, t * t, 0.0]
        };
        let (mut x, mut y) = (0.0, 0.0);
        for (weight, point) in weights.iter().zip(control) {
            x += weight * point.0;
            y += weight * point.1;
        }
        add_point(points, (x, y));
    }
}

// The points of the `d` of a path, and whether it is closed: see the
// documentation of this module.
fn path(d: &str) -> Result<(bool, Vec<EpPoint>), Refused> {
    let blank = |text: &str| text.bytes().all(|byte| byte.is_ascii_whitespace());
    // A command is a letter and the numbers up to the next letter.
    let mut commands: Vec<(char, &str)> = Vec::new();
    let mut letter: Option<(char, usize)> = None;
    for (at, found) in d.char_indices().filter(|(_, c)| c.is_ascii_alphabetic()) {
        match letter {
            Some((previous, start)) => commands.push((previous, &d[start..at])),
            None if blank(&d[..at]) => {}
            None => return Err("a path that does not start with M"),
        }
        letter = Some((found, at + 1));
    }
    let (last, start) = letter.ok_or("a path without commands")?;
    commands.push((last, &d[start..]));

    let mut points = Vec::new();
    let mut current = (0.0f64, 0.0f64);
    let mut closed = false;
    let mut segments = 0usize;
    for (index, &(letter, numbers)) in commands.iter().enumerate() {
        if closed {
            return Err("something after the Z of a path");
        }
        let command = letter.to_ascii_uppercase();
        let arity = match command {
            'M' | 'L' => 2,
            'H' | 'V' => 1,
            'C' => 6,
            'Q' => 4,
            'Z' => 0,
            'A' => return Err("an arc in a path"),
            'S' | 'T' => return Err("a smooth curve (S or T) in a path"),
            _ => return Err("a letter that a path does not use"),
        };
        if (index == 0) != (command == 'M') {
            return Err("a path that is not one subpath from its M");
        }
        if command == 'Z' {
            if !blank(numbers) {
                return Err("numbers after the Z of a path");
            }
            closed = true;
            continue;
        }
        let values = fields(numbers)?
            .into_iter()
            .map(number)
            .collect::<Result<Vec<f32>, Refused>>()?;
        if values.len() % arity != 0 {
            return Err("a path command without all of its numbers");
        }
        // Relative numbers start from the end of the previous segment; the
        // first moveto of a path starts from the origin either way.
        let relative = letter.is_ascii_lowercase();
        for (group, value) in values.chunks_exact(arity).enumerate() {
            let origin = if relative { current } else { (0.0, 0.0) };
            let at = |i: usize| {
                (
                    origin.0 + f64::from(value[i]),
                    origin.1 + f64::from(value[i + 1]),
                )
            };
            let end = match command {
                'H' => (origin.0 + f64::from(value[0]), current.1),
                'V' => (current.0, origin.1 + f64::from(value[0])),
                'C' => {
                    curve(&mut points, &[current, at(0), at(2), at(4)]);
                    at(4)
                }
                'Q' => {
                    curve(&mut points, &[current, at(0), at(2)]);
                    at(2)
                }
                // M, and L: also every pair of a moveto after its first.
                _ => at(0),
            };
            if !matches!(command, 'C' | 'Q') {
                add_point(&mut points, end);
            }
            segments += usize::from(command != 'M' || group > 0);
            current = end;
        }
    }
    if segments == 0 {
        return Err("a path that draws nothing");
    }
    // The last segment of a closed path may come back to the start, which Z
    // joins anyway.
    if closed && points.len() > 1 && points.last() == points.first() {
        points.pop();
    }
    Ok((closed, points))
}

// One drawn element: its kind, its two corners or its points, its paints.
fn object(node: Node<'_, '_>, name: &str, sheet: (u32, u32)) -> Result<PageObject, Refused> {
    const PAINT: [&str; 3] = ["fill", "stroke", "stroke-width"];
    let geometry: &[&str] = match name {
        "rect" => &["x", "y", "width", "height"],
        "circle" => &["cx", "cy", "r"],
        "ellipse" => &["cx", "cy", "rx", "ry"],
        "line" => &["x1", "y1", "x2", "y2"],
        "polyline" => &["points"],
        "path" => &["d"],
        _ => return Err("an element that a page does not use"),
    };
    if node.has_children() {
        return Err("something inside a drawn element");
    }
    for known in node.attributes() {
        let name = known.name();
        if known.namespace().is_some() || !(geometry.contains(&name) || PAINT.contains(&name)) {
            return Err("an attribute that a page does not use");
        }
    }
    let filled = match attribute(node, "fill")? {
        "none" => false,
        paint if colour(paint)? == WHITE => true,
        _ => return Err("a fill other than #ffffff or none"),
    };
    let rgb = colour(attribute(node, "stroke")?)?;
    let width = number(attribute(node, "stroke-width")?)?;
    let point = |x: f32, y: f32| EpPoint { x, y };
    let (kind, points) = match name {
        "rect" => {
            let [x, y, w, h] = numbers(node, ["x", "y", "width", "height"])?;
            if w <= 0.0 || h <= 0.0 {
                return Err("an empty rectangle");
            }
            (2, vec![point(x, y), point(x + w, y + h)])
        }
        "circle" => {
            let [cx, cy, r] = numbers(node, ["cx", "cy", "r"])?;
            ellipse(cx, cy, r, r)?
        }
        "ellipse" => {
            let [cx, cy, rx, ry] = numbers(node, ["cx", "cy", "rx", "ry"])?;
            ellipse(cx, cy, rx, ry)?
        }
        "line" => {
            let [x1, y1, x2, y2] = numbers(node, ["x1", "y1", "x2", "y2"])?;
            (1, vec![point(x1, y1), point(x2, y2)])
        }
        "path" => {
            let (closed, points) = path(attribute(node, "d")?)?;
            (if closed { KIND_CONTOUR } else { 0 }, points)
        }
        _ => {
            let values = fields(attribute(node, "points")?)?
                .into_iter()
                .map(number)
                .collect::<Result<Vec<f32>, Refused>>()?;
            if values.len() < 4 || values.len() % 2 != 0 {
                return Err("a polyline without pairs of at least two points");
            }
            let (pairs, _) = values.as_chunks::<2>();
            (0, pairs.iter().map(|&[x, y]| point(x, y)).collect())
        }
    };
    if filled && kind < 2 {
        return Err("a filled line, polyline or open path");
    }
    // The outline is drawn around the control points: half of it must lie
    // on the sheet too. The points of a path are computed: they are also
    // checked to be numbers.
    let half = width / 2.0;
    let (sheet_width, sheet_height) = (sheet.0 as f32, sheet.1 as f32);
    if points.iter().any(|p| {
        !p.x.is_finite()
            || !p.y.is_finite()
            || p.x - half < 0.0
            || p.y - half < 0.0
            || p.x + half > sheet_width
            || p.y + half > sheet_height
    }) {
        return Err("a drawing beyond the sheet");
    }
    let style = EpObjectStyle {
        kind,
        fill_enabled: u32::from(filled),
        fill_rgb: if filled { WHITE } else { 0 },
    };
    // What the document would refuse is refused here already: every page
    // that reads can be added to a sheet of its size.
    if !valid_style(style)
        || !valid_width(kind, width)
        || points.len() > MAX_STROKE_POINTS
        || (kind != 0 && !valid_shape_points(kind, &points))
    {
        return Err("an object that a document does not accept");
    }
    Ok(PageObject {
        style,
        rgb,
        width,
        points,
    })
}

/// Reads one page, or says why it is not one.
pub(crate) fn read_page(svg: &str) -> Result<Page, Refused> {
    if svg.len() > MAX_PAGE_BYTES {
        return Err("a text longer than MAX_PAGE_BYTES");
    }
    let xml = Document::parse_with_options(
        svg,
        ParsingOptions {
            // No page needs a document type, and without one no entity
            // can be declared.
            allow_dtd: false,
            nodes_limit: MAX_PAGE_NODES,
            ..Default::default()
        },
    )
    .map_err(|_| "not XML that this reader accepts")?;
    let root = xml.root_element();
    if root.tag_name().namespace() != Some(SVG_NAMESPACE) || root.tag_name().name() != "svg" {
        return Err("a root that is not an SVG element");
    }
    let size = sheet(root)?;
    let mut title = None;
    let mut described = false;
    let mut objects = Vec::new();
    for node in root.children() {
        if node.is_comment() {
            continue;
        }
        if node.is_text() {
            if node.text().is_some_and(|text| text.trim().is_empty()) {
                continue;
            }
            return Err("text outside the title and the description");
        }
        if !node.is_element() || node.tag_name().namespace() != Some(SVG_NAMESPACE) {
            return Err("something other than an SVG element");
        }
        match node.tag_name().name() {
            "title" if title.is_none() => title = Some(plain_text(node, MAX_TITLE_BYTES)?),
            "desc" if !described => {
                plain_text(node, MAX_DESC_BYTES)?;
                described = true;
            }
            "title" | "desc" => return Err("a second title or description"),
            name => {
                if objects.len() == MAX_PAGE_OBJECTS {
                    return Err("more than MAX_PAGE_OBJECTS drawn elements");
                }
                objects.push(object(node, name, size)?);
            }
        }
    }
    let title = title.ok_or("no title")?;
    if objects.is_empty() {
        return Err("a page that draws nothing");
    }
    // Its document holds every filled element as a zone, then the lines in
    // the room left. At most MAX_PAGE_OBJECTS zones of MAX_STROKE_POINTS
    // points each: no overflow.
    let zones = objects
        .iter()
        .filter(|object| object.style.fill_enabled == 1);
    let zone_points: usize = zones.clone().map(|object| object.points.len()).sum();
    let room = clip::Room {
        objects: MAX_STROKES - zones.count(),
        points: MAX_TOTAL_POINTS
            .checked_sub(zone_points)
            .ok_or(TOO_MANY_POINTS)?,
    };
    let lines = clip::clip_outlines(&objects, room)?;
    Ok(Page {
        title: title.to_owned(),
        width: size.0,
        height: size.1,
        objects,
        lines,
    })
}

// Every page, read once; None if one of the files compiled into the library
// is refused, which the tests of this module do not let happen.
fn pages() -> Option<&'static [Page]> {
    static READ: OnceLock<Option<Vec<Page>>> = OnceLock::new();
    READ.get_or_init(|| PAGES.iter().map(|(_, svg)| read_page(svg).ok()).collect())
        .as_deref()
}

fn append(out: &mut String, text: &str) -> Option<()> {
    out.try_reserve(text.len()).ok()?;
    out.push_str(text);
    Some(())
}

// A title in ASCII: every byte of its UTF-8 outside printable ASCII, and `%`
// itself, is written `%XX` in capitals. The whole catalogue stays ASCII.
fn escaped(out: &mut String, title: &str) -> Option<()> {
    for byte in title.bytes() {
        out.try_reserve(3).ok()?;
        if (0x20..0x7f).contains(&byte) && byte != b'%' {
            out.push(char::from(byte));
        } else {
            write!(out, "%{byte:02X}").ok()?;
        }
    }
    Some(())
}

// The text of ep_page_catalog, made once; None if a page is refused or
// memory is short.
fn catalogue() -> Option<&'static str> {
    static TEXT: OnceLock<Option<String>> = OnceLock::new();
    TEXT.get_or_init(|| {
        let mut out = String::new();
        for (id, ((key, svg), page)) in PAGES.iter().zip(pages()?).enumerate() {
            // Keys are short: see the tests.
            out.try_reserve(64).ok()?;
            write!(out, "T {id} {key} {} {} ", page.regions(), page.details()).ok()?;
            escaped(&mut out, &page.title)?;
            append(&mut out, "\n")?;
            describe(key, svg, &mut out).ok()?;
        }
        Some(out)
    })
    .as_deref()
}

/// Number of colouring pages of this core; identifiers are 0..count.
#[no_mangle]
pub extern "C" fn ep_page_count() -> u32 {
    PAGES.len() as u32
}

/// Returns the colouring pages as owned, NUL-terminated ASCII text, or NULL
/// when memory is short. For each page, in identifier order, one line
///
/// ```text
/// T <id> <key> <regions> <details> <title>
/// ```
///
/// then its thumbnail, described as ep_art_catalog describes a picture, from
/// `P <key> <width> <height>` to `X`; the width and the height are those of
/// the sheet that the page needs. `<regions>` counts its filled elements,
/// the zones that the paint pot colours, `<details>` its other elements:
/// lines, polylines, open paths and unfilled shapes; both count elements of
/// the file, not the lines of its document. `<title>`, the rest of
/// the line, is the UTF-8 of the French title with every byte outside
/// printable ASCII, and `%`, written `%XX`. Release with ep_string_free only.
#[no_mangle]
pub extern "C" fn ep_page_catalog() -> *mut c_char {
    // The libraries that read SVG are not ours: should one ever panic, the
    // answer is NULL.
    std::panic::catch_unwind(|| catalogue().map_or(ptr::null_mut(), owned_text))
        .unwrap_or(ptr::null_mut())
}

// The objects of the document of a page, in this order, each with its layer,
// style, colour, width and points: every filled element as a zone, white
// inside a white hairline that the line above it covers; then the lines of
// the page, read once with it.
fn page_objects(
    page: &Page,
) -> impl Iterator<Item = (u8, EpObjectStyle, u32, f32, &[EpPoint])> + '_ {
    let zones = page
        .objects
        .iter()
        .filter(|object| object.style.fill_enabled == 1)
        .map(|object| {
            let style = EpObjectStyle {
                kind: object.style.kind,
                fill_enabled: 1,
                fill_rgb: WHITE,
            };
            (
                ZONES_LAYER,
                style,
                WHITE,
                ZONE_WIDTH,
                object.points.as_slice(),
            )
        });
    let lines = page.lines.iter().map(|line| {
        (
            LINES_LAYER,
            line.style,
            line.rgb,
            line.width,
            line.points.as_slice(),
        )
    });
    zones.chain(lines)
}

/// The document of a page: a sheet of its size whose layers are, bottom to
/// top, its zones (locked), the drawing of the child (active) and its lines
/// (locked). Every object is checked as an added object would be, which
/// `read_page` has made sure of already. Nothing is in the history: the
/// document starts without an undo step, and its objects, all on locked
/// layers, never enter it. Err(-1) for what a document refuses, Err(-2)
/// when memory is short.
pub(crate) fn page_document(page: &Page) -> Result<EpDocument, i32> {
    let mut document = EpDocument::blank(page.width, page.height);
    let (mut count, mut points) = (0usize, 0usize);
    for (_, style, rgb, width, object) in page_objects(page) {
        if !valid_new_object(&document, object, rgb, width, style, 0, &[]) {
            return Err(INVALID);
        }
        count += 1;
        points += object.len();
    }
    if count > MAX_STROKES || points > MAX_TOTAL_POINTS {
        return Err(INVALID);
    }
    document
        .strokes
        .try_reserve_exact(count)
        .map_err(|_| ALLOCATION_FAILURE)?;
    for (layer, style, rgb, width, object) in page_objects(page) {
        let mut copy = Vec::new();
        copy.try_reserve_exact(object.len())
            .map_err(|_| ALLOCATION_FAILURE)?;
        copy.extend_from_slice(object);
        let revision = document.issue_revision();
        document.strokes.push(Stroke {
            points: copy,
            rgb,
            width,
            style,
            scale: 1.0,
            translation: [0.0; 2],
            revision,
            layer,
            param: 0,
            text: Vec::new(),
        });
        document.count_attached(document.strokes.len() - 1);
    }
    document.retained_points = document.active_points;
    document.retained_objects = document.strokes.len();
    let layer = |id, locked| Layer {
        id,
        visible: true,
        locked,
    };
    document.layers[..3].copy_from_slice(&[
        layer(ZONES_LAYER, true),
        layer(DRAWING_LAYER, false),
        layer(LINES_LAYER, true),
    ]);
    document.layer_count = 3;
    document.active_layer = DRAWING_LAYER;
    Ok(document)
}

/// Creates a NEW document for colouring page `page`, of the size of the
/// page, or NULL for an unknown page or when memory is short. Its layers,
/// bottom to top: identifier 1, locked, the zones of the page, every filled
/// element filled with white inside a white outline of width 0.1;
/// identifier 0, active and empty, where the child draws; identifier 2,
/// locked, the lines of the page, no fill: the outline of every element as
/// its file draws it, without the parts that a filled element drawn after
/// it hides; an outline of which something is hidden becomes the freehand
/// pieces left. Paint goes under the lines and over the zones; the paint
/// pot colours a zone through ep_set_object_style, the one change a locked
/// layer accepts. Nothing of the page is in the history: the document
/// starts with no undo step. Released with ep_document_free.
#[no_mangle]
pub extern "C" fn ep_document_from_page(page: u32) -> *mut EpDocument {
    // Read outside any document: a panic of the XML reader is a NULL.
    let Ok(Some(pages)) = std::panic::catch_unwind(pages) else {
        return ptr::null_mut();
    };
    match pages.get(page as usize).map(page_document) {
        Some(Ok(document)) => owned_document(document),
        _ => ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests;
