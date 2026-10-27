//! Pictures kept as SVG files: read here, handed to the interface as a short
//! list of drawing instructions that it paints itself.
//!
//! The reading is done by usvg, the reading half of resvg, the only library
//! this core depends on: styles, reused shapes, units and transforms are
//! resolved there, and what comes back is a tree of plain outlines with their
//! paints. Nothing is rendered to pixels in the core: the interface draws the
//! outlines with its own engine, at any size.
//!
//! The pictures of the interface are files of `art/interface/`, compiled into
//! the library: a picture is changed by changing its file. Keys are the file
//! names without `.svg`. The small ones are drawn on a grid of 64. Two are
//! drawings on their own grid of 512, chosen by the owner among the studies
//! of the logo: « De face », the logo of « À propos » and of the icons, and
//! « Debout pour peindre », the companion of the main window.
//!
//! What a picture may use in this version: outlines with a plain colour or a
//! linear or radial gradient, strokes (dashes are cut here into the outline),
//! groups with an opacity or a clip path. Masks, filters, patterns, blend
//! modes, embedded images and text are refused: a picture is never handed
//! over with a part silently missing — except text, which usvg leaves out
//! without a word when it is built without fonts, as it is here.
use super::*;
use std::sync::OnceLock;
use usvg::tiny_skia_path::{Path as Outline, PathSegment, StrokeDash};

/// Largest SVG text accepted from a caller.
pub const MAX_SVG_BYTES: usize = 1024 * 1024;
/// Groups and outlines of one picture, clip outlines included.
const MAX_PICTURE_ITEMS: usize = 10_000;
/// Move, line and curve commands of one picture.
const MAX_PICTURE_SEGMENTS: usize = 400_000;
/// Nodes of the XML tree — elements and the texts between them — before
/// anything is converted. It also bounds how long a chain of references can
/// be, and with it how deep the library that follows them goes.
const MAX_XML_NODES: u32 = 20_000;
/// Elements inside elements, in the text itself: checked before the text is
/// handed to the XML reader, which goes one level down the stack per level.
const MAX_XML_DEPTH: usize = 80;
const MAX_GROUP_DEPTH: usize = 64;
/// Digits of the integer part of the largest number a picture may write,
/// its exponent counted: seven, so under ten million.
const MAX_NUMBER_DIGITS: i64 = 7;
const MAX_GRADIENT_STOPS: usize = 256;
/// The stack of the thread that reads a picture. The XML reader and usvg
/// follow nesting and references by calling themselves: on the costliest
/// files tried within the bounds above, a read took up to 25 MiB of stack in
/// an optimised build and 46 MiB in a plain one. The stack of the caller,
/// which may be small, is not used. Only touched pages are real.
const READER_STACK_BYTES: usize = 64 * 1024 * 1024;

/// The pictures of the interface, in the order of their keys.
static INTERFACE: &[(&str, &str)] = &[
    ("film", include_str!("../art/interface/film.svg")),
    ("logo", include_str!("../art/interface/logo.svg")),
    ("mascotte", include_str!("../art/interface/mascotte.svg")),
    ("options", include_str!("../art/interface/options.svg")),
];

/// Why a picture is not handed over.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum Refusal {
    /// Not an SVG that usvg reads, or one without a usable size.
    Unreadable,
    /// Reads, but uses something this version does not draw.
    Unsupported(&'static str),
    /// Beyond one of the bounds above.
    TooLarge,
    OutOfMemory,
}

struct Budget {
    items: usize,
    segments: usize,
}

impl Budget {
    fn item(&mut self) -> Result<(), Refusal> {
        self.items = self.items.checked_sub(1).ok_or(Refusal::TooLarge)?;
        Ok(())
    }
}

fn push(out: &mut String, text: &str) -> Result<(), Refusal> {
    out.try_reserve(text.len())
        .map_err(|_| Refusal::OutOfMemory)?;
    out.push_str(text);
    Ok(())
}

// Plain decimal notation, never an exponent: Rust writes the shortest digits
// that read back as the same f32.
fn number(out: &mut String, value: f32) -> Result<(), Refusal> {
    if !value.is_finite() {
        return Err(Refusal::Unreadable);
    }
    out.try_reserve(48).map_err(|_| Refusal::OutOfMemory)?;
    // Minus zero would only be noise for the reader.
    write!(out, "{}", if value == 0.0 { 0.0 } else { value }).map_err(|_| Refusal::OutOfMemory)
}

// The six numbers of an SVG matrix (a b c d e f) joined by `;`, or `-` for
// a transform that changes nothing.
fn matrix(out: &mut String, transform: usvg::Transform) -> Result<(), Refusal> {
    if transform.is_identity() {
        return push(out, "-");
    }
    let values = [
        transform.sx,
        transform.ky,
        transform.kx,
        transform.sy,
        transform.tx,
        transform.ty,
    ];
    for (index, value) in values.into_iter().enumerate() {
        if index != 0 {
            push(out, ";")?;
        }
        number(out, value)?;
    }
    Ok(())
}

fn alpha(opacity: f32) -> u32 {
    (opacity.clamp(0.0, 1.0) * 255.0).round() as u32
}

fn colour(out: &mut String, colour: usvg::Color, opacity: f32) -> Result<(), Refusal> {
    out.try_reserve(9).map_err(|_| Refusal::OutOfMemory)?;
    write!(
        out,
        "#{:02x}{:02x}{:02x}{:02x}",
        colour.red,
        colour.green,
        colour.blue,
        alpha(opacity)
    )
    .map_err(|_| Refusal::OutOfMemory)
}

fn stops(out: &mut String, gradient: &usvg::BaseGradient, opacity: f32) -> Result<(), Refusal> {
    push(
        out,
        match gradient.spread_method() {
            usvg::SpreadMethod::Pad => "p:",
            usvg::SpreadMethod::Reflect => "m:",
            usvg::SpreadMethod::Repeat => "r:",
        },
    )?;
    matrix(out, gradient.transform())?;
    push(out, ":")?;
    let list = gradient.stops();
    if list.is_empty() || list.len() > MAX_GRADIENT_STOPS {
        return Err(Refusal::Unsupported(
            "a gradient without stops, or with too many",
        ));
    }
    for (index, stop) in list.iter().enumerate() {
        if index != 0 {
            push(out, "/")?;
        }
        number(out, stop.offset().get())?;
        push(out, "=")?;
        // The opacity of the fill or stroke applies to the whole gradient.
        colour(out, stop.color(), stop.opacity().get() * opacity)?;
    }
    Ok(())
}

// `#rrggbbaa`, `L:x1:y1:x2:y2:spread:matrix:stops` or
// `R:cx:cy:r:fx:fy:fr:spread:matrix:stops`, without a space or a comma.
fn paint(out: &mut String, paint: &usvg::Paint, opacity: f32) -> Result<(), Refusal> {
    match paint {
        usvg::Paint::Color(value) => colour(out, *value, opacity),
        usvg::Paint::LinearGradient(gradient) => {
            push(out, "L")?;
            for value in [gradient.x1(), gradient.y1(), gradient.x2(), gradient.y2()] {
                push(out, ":")?;
                number(out, value)?;
            }
            push(out, ":")?;
            stops(out, gradient, opacity)
        }
        usvg::Paint::RadialGradient(gradient) => {
            push(out, "R")?;
            for value in [
                gradient.cx(),
                gradient.cy(),
                gradient.r().get(),
                gradient.fx(),
                gradient.fy(),
                gradient.fr().get(),
            ] {
                push(out, ":")?;
                number(out, value)?;
            }
            push(out, ":")?;
            stops(out, gradient, opacity)
        }
        usvg::Paint::Pattern(_) => Err(Refusal::Unsupported("a pattern")),
    }
}

// Absolute M, L, Q, C and Z commands, numbers separated by single spaces:
// the grammar that the interface already reads for stamps.
fn outline(out: &mut String, data: &Outline, budget: &mut Budget) -> Result<(), Refusal> {
    fn command(
        out: &mut String,
        letter: &str,
        points: &[usvg::tiny_skia_path::Point],
    ) -> Result<(), Refusal> {
        push(out, letter)?;
        for point in points {
            push(out, " ")?;
            number(out, point.x)?;
            push(out, " ")?;
            number(out, point.y)?;
        }
        Ok(())
    }
    let mut first = true;
    for segment in data.segments() {
        budget.segments = budget.segments.checked_sub(1).ok_or(Refusal::TooLarge)?;
        if !first {
            push(out, " ")?;
        }
        first = false;
        match segment {
            PathSegment::MoveTo(a) => command(out, "M", &[a])?,
            PathSegment::LineTo(a) => command(out, "L", &[a])?,
            PathSegment::QuadTo(a, b) => command(out, "Q", &[a, b])?,
            PathSegment::CubicTo(a, b, c) => command(out, "C", &[a, b, c])?,
            PathSegment::Close => command(out, "Z", &[])?,
        }
    }
    if first {
        return Err(Refusal::Unreadable);
    }
    Ok(())
}

fn fill(out: &mut String, fill: Option<&usvg::Fill>) -> Result<(), Refusal> {
    let Some(fill) = fill else {
        return push(out, "-");
    };
    paint(out, fill.paint(), fill.opacity().get())?;
    push(
        out,
        match fill.rule() {
            usvg::FillRule::NonZero => ",n",
            usvg::FillRule::EvenOdd => ",e",
        },
    )
}

fn stroke(out: &mut String, stroke: Option<&usvg::Stroke>) -> Result<(), Refusal> {
    let Some(stroke) = stroke else {
        return push(out, "-");
    };
    paint(out, stroke.paint(), stroke.opacity().get())?;
    push(out, ",")?;
    number(out, stroke.width().get())?;
    push(
        out,
        match stroke.linecap() {
            usvg::LineCap::Butt => ",b",
            usvg::LineCap::Round => ",r",
            usvg::LineCap::Square => ",s",
        },
    )?;
    push(
        out,
        match stroke.linejoin() {
            // A clipped mitre is drawn as a plain one: the interface has no
            // other, and they differ only beyond the mitre limit.
            usvg::LineJoin::Miter | usvg::LineJoin::MiterClip => "m,",
            usvg::LineJoin::Round => "r,",
            usvg::LineJoin::Bevel => "b,",
        },
    )?;
    number(out, stroke.miterlimit().get())
}

// `D <order> <fill> <stroke> <outline>`: the order is `f` when the inside is
// painted first, `s` when the stroke is.
fn drawn(
    out: &mut String,
    order: &str,
    inside: Option<&usvg::Fill>,
    line: Option<&usvg::Stroke>,
    data: &Outline,
    budget: &mut Budget,
) -> Result<(), Refusal> {
    budget.item()?;
    push(out, "D ")?;
    push(out, order)?;
    push(out, " ")?;
    fill(out, inside)?;
    push(out, " ")?;
    stroke(out, line)?;
    push(out, " ")?;
    outline(out, data, budget)?;
    push(out, "\n")
}

// Whether an outline has an inside to paint: one straight segment, closed or
// not, has none. SVG gives a line no inside; an engine asked to paint the
// inside of such an outline may still leave a hairline along it.
fn has_inside(data: &Outline) -> bool {
    let mut segments = 0;
    for segment in data.segments() {
        match segment {
            PathSegment::MoveTo(_) => segments = 0,
            PathSegment::LineTo(_) => {
                segments += 1;
                if segments > 1 {
                    return true;
                }
            }
            PathSegment::QuadTo(..) | PathSegment::CubicTo(..) => return true,
            PathSegment::Close => {}
        }
    }
    false
}

fn path(out: &mut String, path: &usvg::Path, budget: &mut Budget) -> Result<(), Refusal> {
    let inside = path.fill().filter(|_| has_inside(path.data()));
    if !path.is_visible() || (inside.is_none() && path.stroke().is_none()) {
        return Ok(());
    }
    let stroke_first = path.paint_order() == usvg::PaintOrder::StrokeAndFill;
    let order = if stroke_first { "s" } else { "f" };
    let dashes = path
        .stroke()
        .and_then(|line| line.dasharray().map(|array| (line, array)));
    let Some((line, array)) = dashes else {
        return drawn(out, order, inside, path.stroke(), path.data(), budget);
    };
    // The interface draws no dashes: they are cut here, and the stroke gets
    // an outline of its own. Dashes that leave nothing leave no stroke.
    let mut copy = Vec::new();
    copy.try_reserve_exact(array.len())
        .map_err(|_| Refusal::OutOfMemory)?;
    copy.extend_from_slice(array);
    let cut =
        StrokeDash::new(copy, line.dashoffset()).and_then(|dash| path.data().dash(&dash, 1.0));
    if stroke_first {
        if let Some(cut) = &cut {
            drawn(out, "f", None, Some(line), cut, budget)?;
        }
    }
    if inside.is_some() {
        drawn(out, "f", inside, None, path.data(), budget)?;
    }
    if !stroke_first {
        if let Some(cut) = &cut {
            drawn(out, "f", None, Some(line), cut, budget)?;
        }
    }
    Ok(())
}

// The outlines of one clip, in the coordinates of the group that it clips:
// a `C` line, then one `K <rule> <outline>` line for each. Together they
// are the clip; a clip without any hides everything.
fn clip_outlines(
    out: &mut String,
    group: &usvg::Group,
    transform: usvg::Transform,
    depth: usize,
    budget: &mut Budget,
) -> Result<(), Refusal> {
    if depth > MAX_GROUP_DEPTH {
        return Err(Refusal::TooLarge);
    }
    for child in group.children() {
        match child {
            usvg::Node::Group(inner) => {
                if inner.clip_path().is_some() {
                    return Err(Refusal::Unsupported("a clip inside a clip"));
                }
                clip_outlines(
                    out,
                    inner,
                    transform.pre_concat(inner.transform()),
                    depth + 1,
                    budget,
                )?;
            }
            usvg::Node::Path(path) => {
                // Only the inside of a clip outline counts, never its stroke.
                let Some(inside) = path.fill() else { continue };
                if !path.is_visible() {
                    continue;
                }
                let Some(placed) = path.data().clone().transform(transform) else {
                    return Err(Refusal::Unreadable);
                };
                budget.item()?;
                push(
                    out,
                    match inside.rule() {
                        usvg::FillRule::NonZero => "K n ",
                        usvg::FillRule::EvenOdd => "K e ",
                    },
                )?;
                outline(out, &placed, budget)?;
                push(out, "\n")?;
            }
            usvg::Node::Image(_) => return Err(Refusal::Unsupported("an image in a clip")),
            usvg::Node::Text(_) => return Err(Refusal::Unsupported("text in a clip")),
        }
    }
    Ok(())
}

fn clip(out: &mut String, clip: &usvg::ClipPath, budget: &mut Budget) -> Result<(), Refusal> {
    let mut next = Some(clip);
    let mut chain = 0;
    // A clip may itself be clipped: each one narrows the group further.
    while let Some(clip) = next {
        chain += 1;
        if chain > MAX_GROUP_DEPTH {
            return Err(Refusal::TooLarge);
        }
        budget.item()?;
        push(out, "C\n")?;
        clip_outlines(out, clip.root(), clip.transform(), 0, budget)?;
        next = clip.clip_path();
    }
    Ok(())
}

// `G <opacity> <matrix>`, its clips, what it holds, then `E`. A group that
// changes nothing is not written: only what it holds is.
fn group(
    out: &mut String,
    group: &usvg::Group,
    depth: usize,
    budget: &mut Budget,
) -> Result<(), Refusal> {
    if depth > MAX_GROUP_DEPTH {
        return Err(Refusal::TooLarge);
    }
    if !group.filters().is_empty() {
        return Err(Refusal::Unsupported("a filter"));
    }
    if group.mask().is_some() {
        return Err(Refusal::Unsupported("a mask"));
    }
    if group.blend_mode() != usvg::BlendMode::Normal {
        return Err(Refusal::Unsupported("a blend mode"));
    }
    let opacity = group.opacity().get();
    let plain = opacity == 1.0 && group.transform().is_identity() && group.clip_path().is_none();
    if !plain {
        budget.item()?;
        push(out, "G ")?;
        number(out, opacity)?;
        push(out, " ")?;
        matrix(out, group.transform())?;
        push(out, "\n")?;
        if let Some(outline) = group.clip_path() {
            clip(out, outline, budget)?;
        }
    }
    for child in group.children() {
        match child {
            usvg::Node::Group(inner) => self::group(out, inner, depth + 1, budget)?,
            usvg::Node::Path(outline) => path(out, outline, budget)?,
            usvg::Node::Image(_) => return Err(Refusal::Unsupported("an embedded image")),
            usvg::Node::Text(_) => return Err(Refusal::Unsupported("text")),
        }
    }
    if !plain {
        push(out, "E\n")?;
    }
    Ok(())
}

/// Appends the description of one picture to `out`:
///
/// ```text
/// P <key> <width> <height>
/// G <opacity> <matrix>          a group; `E` closes it
/// C                             a clip of the group just opened, then its
/// K <rule> <outline>            outlines; several clips narrow each other
/// D <order> <fill> <stroke> <outline>
/// E
/// X                             the end of the picture
/// ```
///
/// One instruction per line, fields separated by single spaces, the outline
/// last. `<fill>` is `-` or `<paint>,<rule>` with the rule `n` (non-zero) or
/// `e` (even-odd); `<stroke>` is `-` or `<paint>,<width>,<cap><join>,<limit>`
/// with caps `b`utt, `r`ound, `s`quare and joins `m`itre, `r`ound, `b`evel;
/// `<paint>` is `#rrggbbaa`, `L:x1:y1:x2:y2:<spread>:<matrix>:<stops>` or
/// `R:cx:cy:r:fx:fy:fr:<spread>:<matrix>:<stops>`, the spread `p`ad,
/// `m`irror or `r`epeat and the stops `offset=#rrggbbaa` joined by `/`.
/// A matrix is `-` or the six numbers of SVG joined by `;`. Outlines use
/// absolute `M`, `L`, `Q`, `C` and `Z` commands.
///
/// On a refusal `out` may hold a part of the description: the caller drops
/// it or truncates it.
pub(crate) fn describe(key: &str, svg: &str, out: &mut String) -> Result<(), Refusal> {
    if svg.len() > MAX_SVG_BYTES {
        return Err(Refusal::TooLarge);
    }
    // An entity is a text that the XML reader writes again wherever it is
    // named: a few thousand names of one long entity ask for more memory
    // than there is, and the allocator then stops the whole program. The
    // reader only guards against entities inside entities. No picture needs
    // one: a text that declares any is refused before it is read.
    if svg.contains("<!ENTITY") {
        return Err(Refusal::Unsupported("entities"));
    }
    if !nesting_within(svg, MAX_XML_DEPTH) {
        return Err(Refusal::TooLarge);
    }
    // The library turns an elliptical arc into curves in a number of pieces
    // that grows with its radius, without a bound: a radius of 6e93 — one
    // damaged digit of a real drawing — asks for more memory than there is.
    // No picture needs a number of ten million or more.
    if !numbers_within(svg, MAX_NUMBER_DIGITS) {
        return Err(Refusal::TooLarge);
    }
    // On a thread of its own, whose stack is known: see READER_STACK_BYTES.
    // A panic of the libraries ends that thread and is a refusal here.
    std::thread::scope(|scope| {
        std::thread::Builder::new()
            .stack_size(READER_STACK_BYTES)
            .spawn_scoped(scope, || read(key, svg, out))
            .map_err(|_| Refusal::OutOfMemory)?
            .join()
            .unwrap_or(Err(Refusal::Unreadable))
    })
}

/// Whether every number written in `text` stays within `limit` digits before
/// its decimal point, its exponent counted, whatever the way it is written:
/// `1e7`, `10000000` and `.5e8` have eight. Read on the text itself, before
/// anything else: a number begins where a digit or a point follows anything
/// but a letter, a digit, `#` or `_`, so names and colours (`r99999`,
/// `#ffe9ad`) are not numbers. A number in a comment counts too.
fn numbers_within(text: &str, limit: i64) -> bool {
    let bytes = text.as_bytes();
    let word = |byte: u8| byte.is_ascii_alphanumeric() || byte == b'#' || byte == b'_';
    let mut at = 0;
    while at < bytes.len() {
        let first = bytes[at];
        let starts = (first.is_ascii_digit() || first == b'.')
            && (at == 0 || !word(bytes[at - 1]) || bytes[at - 1].is_ascii_digit());
        if !starts || (at > 0 && bytes[at - 1].is_ascii_digit()) {
            // Inside a word, or the rest of a number already counted.
            at += 1;
            continue;
        }
        // The integer part, its leading zeros left aside.
        let mut digits: i64 = 0;
        while at < bytes.len() && bytes[at].is_ascii_digit() {
            if digits > 0 || bytes[at] != b'0' {
                digits += 1;
            }
            at += 1;
        }
        // The fraction: its leading zeros make the number smaller.
        let mut zeros: i64 = 0;
        let mut fraction = false;
        if at < bytes.len() && bytes[at] == b'.' {
            at += 1;
            while at < bytes.len() && bytes[at].is_ascii_digit() {
                if digits == 0 && !fraction && bytes[at] == b'0' {
                    zeros += 1;
                } else {
                    fraction = true;
                }
                at += 1;
            }
        }
        // The exponent, bounded so that its digits cannot overflow.
        let mut exponent: i64 = 0;
        if at + 1 < bytes.len() && (bytes[at] == b'e' || bytes[at] == b'E') {
            let mut next = at + 1;
            let negative = bytes[next] == b'-';
            if bytes[next] == b'-' || bytes[next] == b'+' {
                next += 1;
            }
            if next < bytes.len() && bytes[next].is_ascii_digit() {
                while next < bytes.len() && bytes[next].is_ascii_digit() {
                    exponent = (exponent * 10 + i64::from(bytes[next] - b'0')).min(1_000_000);
                    next += 1;
                }
                if negative {
                    exponent = -exponent;
                }
                at = next;
            }
        }
        // A number of `digits` digits before its point is under 10^digits;
        // a fraction alone, under 10^-zeros.
        let size = if digits > 0 {
            digits + exponent
        } else if fraction {
            exponent - zeros
        } else {
            continue;
        };
        if size > limit {
            return false;
        }
    }
    true
}

/// Whether the elements of `text`, taken as XML, are nested at most `limit`
/// deep. Nothing is built. On a text that the XML reader accepts, the depth
/// counted is the real one; on a damaged text it is at least the depth of
/// what that reader walks before it stops at the damage.
fn nesting_within(text: &str, limit: usize) -> bool {
    fn find(bytes: &[u8], from: usize, what: &[u8]) -> Option<usize> {
        bytes
            .get(from..)?
            .windows(what.len())
            .position(|window| window == what)
            .map(|position| from + position)
    }
    let bytes = text.as_bytes();
    let mut depth = 0usize;
    let mut at = 0;
    while let Some(found) = find(bytes, at, b"<") {
        let rest = &bytes[found..];
        // What is skipped whole holds no element; left open, it is where
        // the reader stops.
        let skipped = if rest.starts_with(b"<!--") {
            Some((4, &b"-->"[..]))
        } else if rest.starts_with(b"<![CDATA[") {
            Some((9, &b"]]>"[..]))
        } else if rest.starts_with(b"<?") {
            Some((2, &b"?>"[..]))
        } else {
            None
        };
        if let Some((start, end)) = skipped {
            match find(bytes, found + start, end) {
                Some(position) => at = position + end.len(),
                None => return true,
            }
        } else if rest.starts_with(b"<!") {
            // A document type. Its declarations hold no element, and it is
            // walked on, not skipped: nothing after it is missed.
            at = found + 2;
        } else if rest.starts_with(b"</") {
            depth = depth.saturating_sub(1);
            at = found + 2;
        } else {
            // A start tag, to its `>` — which a quoted value may hold too.
            let mut end = found + 1;
            let mut quote = 0u8;
            while let Some(&byte) = bytes.get(end) {
                if quote != 0 {
                    if byte == quote {
                        quote = 0;
                    }
                } else if byte == b'"' || byte == b'\'' {
                    quote = byte;
                } else if byte == b'>' {
                    break;
                }
                end += 1;
            }
            if end >= bytes.len() {
                return true;
            }
            if bytes[end - 1] != b'/' {
                depth += 1;
                if depth > limit {
                    return false;
                }
            }
            at = end + 1;
        }
    }
    true
}

// What `describe` does once the text has passed its first guards, on the
// thread made for it.
fn read(key: &str, svg: &str, out: &mut String) -> Result<(), Refusal> {
    use std::sync::atomic::{AtomicBool, Ordering};
    let xml = usvg::roxmltree::Document::parse_with_options(
        svg,
        usvg::roxmltree::ParsingOptions {
            // Files of drawing programs often open with a document type.
            // One that declares entities never comes this far.
            allow_dtd: true,
            nodes_limit: MAX_XML_NODES,
            ..Default::default()
        },
    )
    .map_err(|_| Refusal::Unreadable)?;
    // What this version does not draw is refused before anything is
    // converted: built without fonts, usvg would leave text out without a
    // word, and masks, patterns, filters and markers are what lets a file
    // send it down the longest chains of references.
    for node in xml.descendants().filter(|node| node.is_element()) {
        let unsupported = match node.tag_name().name() {
            "text" => "text",
            "mask" => "a mask",
            "pattern" => "a pattern",
            "filter" => "a filter",
            "marker" => "a marker",
            _ => continue,
        };
        return Err(Refusal::Unsupported(unsupported));
    }
    // No file is ever opened and no image decoded on behalf of a picture; an
    // image that was asked for is remembered, to refuse the picture.
    let asked = AtomicBool::new(false);
    let options = usvg::Options {
        image_href_resolver: usvg::ImageHrefResolver {
            resolve_data: Box::new(|_, _, _| {
                asked.store(true, Ordering::Relaxed);
                None
            }),
            resolve_string: Box::new(|_, _| {
                asked.store(true, Ordering::Relaxed);
                None
            }),
        },
        ..Default::default()
    };
    let tree = usvg::Tree::from_xmltree(&xml, &options).map_err(|_| Refusal::Unreadable)?;
    if asked.load(Ordering::Relaxed) {
        return Err(Refusal::Unsupported("an embedded image"));
    }
    let size = tree.size();
    push(out, "P ")?;
    push(out, key)?;
    push(out, " ")?;
    number(out, size.width())?;
    push(out, " ")?;
    number(out, size.height())?;
    push(out, "\n")?;
    let mut budget = Budget {
        items: MAX_PICTURE_ITEMS,
        segments: MAX_PICTURE_SEGMENTS,
    };
    let before = out.len();
    group(out, tree.root(), 0, &mut budget)?;
    if !out[before..].lines().any(|line| line.starts_with("D ")) {
        return Err(Refusal::Unsupported("a picture that draws nothing"));
    }
    push(out, "X\n")
}

// Every picture of the interface, one description after the other; None if
// one of the files compiled into the library is refused, which the tests of
// this module do not let happen.
fn catalogue() -> Option<&'static str> {
    static TEXT: OnceLock<Option<String>> = OnceLock::new();
    TEXT.get_or_init(|| {
        let mut out = String::new();
        for (key, svg) in INTERFACE {
            describe(key, svg, &mut out).ok()?;
        }
        Some(out)
    })
    .as_deref()
}

// Also the catalogue of the colouring pages: see pages.rs.
pub(crate) fn owned_text(text: &str) -> *mut c_char {
    let mut bytes = Vec::new();
    if bytes.try_reserve_exact(text.len() + 1).is_err() {
        return ptr::null_mut();
    }
    bytes.extend_from_slice(text.as_bytes());
    bytes.push(0);
    // A description is made of numbers, letters and punctuation: no NUL.
    CString::from_vec_with_nul(bytes).map_or(ptr::null_mut(), CString::into_raw)
}

/// Number of pictures of the interface compiled into this core.
#[no_mangle]
pub extern "C" fn ep_art_count() -> u32 {
    INTERFACE.len() as u32
}

/// Returns the pictures of the interface as owned, NUL-terminated ASCII text,
/// or NULL on allocation failure. One description per picture, in the order
/// of their keys; the format is documented at `describe`. Release with
/// ep_string_free only.
#[no_mangle]
pub extern "C" fn ep_art_catalog() -> *mut c_char {
    // The library that reads SVG is not ours: should it ever panic, the
    // answer is NULL. What a text may ask of memory and of the stack is
    // bounded by the guards of `describe`.
    std::panic::catch_unwind(|| catalogue().map_or(ptr::null_mut(), owned_text))
        .unwrap_or(ptr::null_mut())
}

/// Reads SVG text and returns its description, as ep_art_catalog does for
/// one picture, with the key `-`. NULL for a NULL pointer, more than
/// MAX_SVG_BYTES, text that is not UTF-8, an SVG that cannot be read, one
/// that uses what this version does not draw (masks, filters, patterns, blend
/// modes, embedded images, text), or exhausted memory. No file is opened and
/// nothing is fetched, whatever the SVG refers to. Release with
/// ep_string_free only.
///
/// # Safety
/// Non-null `svg` must address `len` initialized bytes that stay unchanged
/// for the whole call; they are only read.
#[no_mangle]
pub unsafe extern "C" fn ep_picture_from_svg(svg: *const u8, len: usize) -> *mut c_char {
    if svg.is_null() || len > MAX_SVG_BYTES {
        return ptr::null_mut();
    }
    let bytes = unsafe { slice::from_raw_parts(svg, len) };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return ptr::null_mut();
    };
    std::panic::catch_unwind(|| {
        let mut out = String::new();
        match describe("-", text, &mut out) {
            Ok(()) => owned_text(&out),
            Err(_) => ptr::null_mut(),
        }
    })
    .unwrap_or(ptr::null_mut())
}

#[cfg(test)]
mod tests;
