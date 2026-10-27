//! What painting a page in the order of its file hides of its outlines.
//!
//! On the sheet of the file every element is painted over the ones before
//! it: a filled element covers with white whatever lies inside it. The
//! document of a page cannot paint in that order, since its lines all lie
//! above its zones so that the child's paint goes between them. The covered
//! parts are therefore taken away here, once, when a page is read: the
//! outline of every element loses what lies strictly inside a filled element
//! drawn after it. The outline of that covering element passes over every
//! cut, with the same round pen, so the document looks like the file;
//! only where a cut outline is wider than the one passing over its cut does
//! a little of its round end show.
//!
//! A covering element is taken exactly: the inside of a rectangle, of an
//! ellipse by its equation, of a contour by the nonzero rule. An outline is
//! a polyline: the four sides of a rectangle; an ellipse flattened into n
//! points, n being its perimeter divided by 3, rounded up, kept within
//! 32..256 and made a multiple of four so that its four extreme points are
//! exact; the points of a contour, a line, a polyline or an open path. Each
//! segment of an outline is cut where it crosses the boundary of a covering
//! element, and a part whose middle lies strictly inside one is hidden. The
//! parts left are joined into pieces, the last piece of a closed outline to
//! the first when they meet at its start, and a piece shorter than half a
//! unit is dropped. An outline of which nothing is hidden stays the element
//! it was; the pieces of the others are freehand strokes, which must fit in
//! the document with the zones, or the page is refused. Everything is
//! computed in f64 with + - * / and sqrt, sines and cosines from their
//! series, never the mathematics library of the system, and the points kept
//! are rounded once to the f32 of the document: a page gives the same lines
//! on every machine.
use super::*;
use std::f64::consts::{PI, TAU};

type Point = [f64; 2];

/// Work allowed for one page: segments of outlines tested against covering
/// elements, parts of segments classified, and edges of covering contours
/// visited. The pages of Color need less than 350 000, most of it for the
/// curves of their contours; beyond this bound a page is refused rather than
/// slow.
const MAX_CLIP_WORK: usize = 20_000_000;
/// The outline of an ellipse gets one point per this length of perimeter,
/// within the two bounds after it.
const ELLIPSE_STEP: f64 = 3.0;
const MIN_ELLIPSE_POINTS: f64 = 32.0;
const MAX_ELLIPSE_POINTS: f64 = 256.0;
/// A visible piece shorter than this would show hardly more than its ends.
const MIN_PIECE_LENGTH: f64 = 0.5;
const TOO_COMPLEX: Refused = "a page too complex to cut its outlines";

/// What the lines of a page may still take of its document once the zones
/// are in: objects and points.
pub(super) struct Room {
    pub objects: usize,
    pub points: usize,
}

impl Room {
    // Takes one line of `points` points, or refuses the page.
    fn take(&mut self, points: usize) -> Result<(), Refused> {
        self.objects = self.objects.checked_sub(1).ok_or(TOO_MANY_OBJECTS)?;
        self.points = self.points.checked_sub(points).ok_or(TOO_MANY_POINTS)?;
        Ok(())
    }
}

fn point(p: &EpPoint) -> Point {
    [f64::from(p.x), f64::from(p.y)]
}

// The point at `t` of the segment from `a` to `b`, kept within the box of
// the segment whatever the rounding: a point of a piece stays where its
// outline is, on the sheet.
fn lerp(a: Point, b: Point, t: f64) -> Point {
    let at = |axis: usize| {
        let value = a[axis] + t * (b[axis] - a[axis]);
        value.clamp(a[axis].min(b[axis]), a[axis].max(b[axis]))
    };
    [at(0), at(1)]
}

// The lowest and the highest corner of the box around points.
fn bounds(points: impl IntoIterator<Item = Point>) -> (Point, Point) {
    let mut low = [f64::INFINITY; 2];
    let mut high = [f64::NEG_INFINITY; 2];
    for p in points {
        for axis in 0..2 {
            low[axis] = low[axis].min(p[axis]);
            high[axis] = high[axis].max(p[axis]);
        }
    }
    (low, high)
}

// Whether two boxes share some inside. Boxes that only touch do not: what
// lies on a boundary is never strictly inside.
fn overlap(a: (Point, Point), b: (Point, Point)) -> bool {
    (0..2).all(|axis| a.0[axis] < b.1[axis] && b.0[axis] < a.1[axis])
}

// Whether two boxes meet, touching included: a crossing may be a corner.
fn meet(a: (Point, Point), b: (Point, Point)) -> bool {
    (0..2).all(|axis| a.0[axis] <= b.1[axis] && b.0[axis] <= a.1[axis])
}

// sin and cos of an angle within [0, π/4] from their series: there, the
// terms beyond x^19 are below the last bit of an f64.
fn sin_cos(x: f64) -> (f64, f64) {
    let square = x * x;
    let (mut sine, mut cosine) = (1.0, 1.0);
    let mut k = 18.0;
    while k >= 2.0 {
        sine = 1.0 - sine * square / (k * (k + 1.0));
        cosine = 1.0 - cosine * square / ((k - 1.0) * k);
        k -= 2.0;
    }
    (x * sine, cosine)
}

// The outline of the ellipse inside these corners, flattened as the module
// says, from its rightmost point on, its points rounded to the f32 of the
// document. The first quarter is computed, the others are its mirrors.
fn ellipse_outline(low: Point, high: Point) -> Vec<Point> {
    let centre = [(low[0] + high[0]) / 2.0, (low[1] + high[1]) / 2.0];
    let radius = [(high[0] - low[0]) / 2.0, (high[1] - low[1]) / 2.0];
    // Ramanujan's approximation of the perimeter: enough to count points.
    let (a, b) = (radius[0], radius[1]);
    let perimeter = PI * (3.0 * (a + b) - ((3.0 * a + b) * (a + 3.0 * b)).sqrt());
    let wanted = (perimeter / ELLIPSE_STEP)
        .ceil()
        .clamp(MIN_ELLIPSE_POINTS, MAX_ELLIPSE_POINTS) as usize;
    let quarter = wanted.div_ceil(4);
    let count = 4 * quarter;
    let mut first = Vec::with_capacity(quarter);
    for step in 0..quarter {
        // Angles beyond π/4 from their complement, for the series.
        first.push(if 2 * step <= quarter {
            let (sine, cosine) = sin_cos(TAU * step as f64 / count as f64);
            (cosine, sine)
        } else {
            sin_cos(TAU * (quarter - step) as f64 / count as f64)
        });
    }
    let mut outline = Vec::with_capacity(count);
    for turn in 0..4 {
        for &(c, s) in &first {
            let (x, y) = match turn {
                0 => (c, s),
                1 => (-s, c),
                2 => (-c, -s),
                _ => (s, -c),
            };
            let x = (centre[0] + radius[0] * x) as f32;
            let y = (centre[1] + radius[1] * y) as f32;
            outline.push([f64::from(x), f64::from(y)]);
        }
    }
    outline
}

// The outline of an element as the sheet strokes it, and whether its last
// point joins its first.
fn outline(object: &PageObject) -> (Vec<Point>, bool) {
    let points = || object.points.iter().map(point).collect::<Vec<_>>();
    match object.style.kind {
        2 => {
            let (low, high) = bounds(object.points.iter().map(point));
            let corners = vec![low, [high[0], low[1]], high, [low[0], high[1]]];
            (corners, true)
        }
        3 => {
            let (low, high) = bounds(object.points.iter().map(point));
            (ellipse_outline(low, high), true)
        }
        KIND_CONTOUR => (points(), true),
        _ => (points(), false),
    }
}

// The inside of a filled element, which covers what was drawn before it.
enum Cover<'a> {
    // Lowest and highest corner.
    Rectangle(Point, Point),
    // Centre and radii.
    Ellipse(Point, Point),
    // The points of a closed polygon.
    Contour(&'a [EpPoint]),
}

struct Occluder<'a> {
    cover: Cover<'a>,
    bounds: (Point, Point),
}

impl<'a> Occluder<'a> {
    // A filled element: a rectangle, an ellipse or a contour.
    fn of(object: &'a PageObject) -> Self {
        let bounds = bounds(object.points.iter().map(point));
        let (low, high) = bounds;
        let cover = match object.style.kind {
            2 => Cover::Rectangle(low, high),
            3 => Cover::Ellipse(
                [(low[0] + high[0]) / 2.0, (low[1] + high[1]) / 2.0],
                [(high[0] - low[0]) / 2.0, (high[1] - low[1]) / 2.0],
            ),
            _ => Cover::Contour(&object.points),
        };
        Self { cover, bounds }
    }

    // Whether `p` lies strictly inside: a point on the boundary does not.
    // Nothing is decided once the work allowed is spent: the caller then
    // refuses the page.
    fn covers(&self, p: Point, work: &mut usize) -> bool {
        match &self.cover {
            Cover::Rectangle(low, high) => {
                low[0] < p[0] && p[0] < high[0] && low[1] < p[1] && p[1] < high[1]
            }
            Cover::Ellipse(centre, radius) => {
                let u = (p[0] - centre[0]) / radius[0];
                let v = (p[1] - centre[1]) / radius[1];
                u * u + v * v < 1.0
            }
            Cover::Contour(points) => {
                *work += points.len();
                if *work > MAX_CLIP_WORK {
                    return false;
                }
                // The winding number, and never inside on an edge.
                let mut winding = 0i64;
                for (index, start) in points.iter().enumerate() {
                    let a = point(start);
                    let b = point(&points[(index + 1) % points.len()]);
                    let side = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]);
                    if side == 0.0 && meet((p, p), bounds([a, b])) {
                        return false;
                    }
                    if a[1] <= p[1] {
                        if b[1] > p[1] && side > 0.0 {
                            winding += 1;
                        }
                    } else if b[1] <= p[1] && side < 0.0 {
                        winding -= 1;
                    }
                }
                winding != 0
            }
        }
    }

    // The parameters within (0, 1) where the segment from `a` to `b` may
    // cross the boundary. Extra ones only cut the segment where nothing
    // changes; the middle of each part decides.
    fn crossings(&self, a: Point, b: Point, out: &mut Vec<f64>, work: &mut usize) {
        let d = [b[0] - a[0], b[1] - a[1]];
        let mut push = |t: f64| {
            if t > 0.0 && t < 1.0 {
                out.push(t);
            }
        };
        match &self.cover {
            Cover::Rectangle(low, high) => {
                // The four lines of the sides.
                for axis in 0..2 {
                    if d[axis] != 0.0 {
                        for side in [low[axis], high[axis]] {
                            push((side - a[axis]) / d[axis]);
                        }
                    }
                }
            }
            Cover::Ellipse(centre, radius) => {
                // |(a + t·d - centre) / radius| = 1: a quadratic in t.
                let u = [
                    (a[0] - centre[0]) / radius[0],
                    (a[1] - centre[1]) / radius[1],
                ];
                let v = [d[0] / radius[0], d[1] / radius[1]];
                let qa = v[0] * v[0] + v[1] * v[1];
                let qb = 2.0 * (u[0] * v[0] + u[1] * v[1]);
                let qc = u[0] * u[0] + u[1] * u[1] - 1.0;
                let discriminant = qb * qb - 4.0 * qa * qc;
                if qa > 0.0 && discriminant >= 0.0 {
                    // The root without cancellation, then the other from it.
                    let q = -0.5 * (qb + qb.signum() * discriminant.sqrt());
                    push(q / qa);
                    if q != 0.0 {
                        push(qc / q);
                    }
                }
            }
            Cover::Contour(points) => {
                let segment = bounds([a, b]);
                *work += points.len();
                if *work > MAX_CLIP_WORK {
                    return;
                }
                for (index, start) in points.iter().enumerate() {
                    let p = point(start);
                    let q = point(&points[(index + 1) % points.len()]);
                    if !meet(segment, bounds([p, q])) {
                        continue;
                    }
                    let e = [q[0] - p[0], q[1] - p[1]];
                    let denominator = d[0] * e[1] - d[1] * e[0];
                    if denominator == 0.0 {
                        // Parallel: the edges next to it cut the segment.
                        continue;
                    }
                    let w = [p[0] - a[0], p[1] - a[1]];
                    let s = (w[0] * d[1] - w[1] * d[0]) / denominator;
                    if (0.0..=1.0).contains(&s) {
                        push((w[0] * e[1] - w[1] * e[0]) / denominator);
                    }
                }
            }
        }
    }
}

fn length(piece: &[Point]) -> f64 {
    piece
        .windows(2)
        .map(|pair| {
            let (dx, dy) = (pair[1][0] - pair[0][0], pair[1][1] - pair[0][1]);
            (dx * dx + dy * dy).sqrt()
        })
        .sum()
}

// The pieces of an outline that the occluders leave visible, or None when
// they hide none of it. The pieces never hold more than `room` points.
fn visible(
    outline: &[Point],
    closed: bool,
    occluders: &[&Occluder<'_>],
    room: usize,
    work: &mut usize,
) -> Result<Option<Vec<Vec<Point>>>, Refused> {
    if outline.len() == 1 {
        // A dot is hidden whole or not at all.
        let hidden = occluders.iter().any(|o| o.covers(outline[0], work));
        if *work > MAX_CLIP_WORK {
            return Err(TOO_COMPLEX);
        }
        return Ok(hidden.then(Vec::new));
    }
    let segments = if closed {
        outline.len()
    } else {
        outline.len() - 1
    };
    let mut hidden = false;
    let mut pieces: Vec<Vec<Point>> = Vec::new();
    let mut current: Vec<Point> = Vec::new();
    let mut produced = 0usize;
    let mut starts_at_start = false;
    let mut near: Vec<&Occluder<'_>> = Vec::new();
    let mut cuts = Vec::new();
    let mut kept: Vec<(f64, f64)> = Vec::new();
    for index in 0..segments {
        let (a, b) = (outline[index], outline[(index + 1) % outline.len()]);
        let extent = bounds([a, b]);
        near.clear();
        near.extend(occluders.iter().filter(|o| overlap(extent, o.bounds)));
        cuts.clear();
        cuts.extend([0.0, 1.0]);
        for occluder in &near {
            *work += 1;
            occluder.crossings(a, b, &mut cuts, work);
        }
        cuts.sort_by(f64::total_cmp);
        cuts.dedup();
        // The parts of the segment between cuts, hidden or kept by their
        // middle; consecutive kept parts are one.
        kept.clear();
        for part in cuts.windows(2) {
            let (t0, t1) = (part[0], part[1]);
            let middle = lerp(a, b, (t0 + t1) / 2.0);
            *work += near.len();
            if near.iter().any(|o| o.covers(middle, work)) {
                hidden = true;
            } else if let Some(last) = kept.last_mut().filter(|last| last.1 == t0) {
                last.1 = t1;
            } else {
                kept.push((t0, t1));
            }
        }
        if *work > MAX_CLIP_WORK {
            return Err(TOO_COMPLEX);
        }
        if kept.is_empty() && !current.is_empty() {
            pieces.push(std::mem::take(&mut current));
        }
        for &(t0, t1) in &kept {
            // A piece goes on through a corner; it starts anew after a cut.
            if t0 > 0.0 || current.is_empty() {
                if !current.is_empty() {
                    pieces.push(std::mem::take(&mut current));
                }
                starts_at_start |= index == 0 && t0 == 0.0;
                current.push(if t0 == 0.0 { a } else { lerp(a, b, t0) });
                produced += 1;
            }
            current.push(if t1 == 1.0 { b } else { lerp(a, b, t1) });
            produced += 1;
            if t1 < 1.0 {
                pieces.push(std::mem::take(&mut current));
            }
        }
        if produced > room {
            return Err(TOO_MANY_POINTS);
        }
    }
    // A piece still open here ends where the outline ends.
    let ends_at_end = !current.is_empty();
    if ends_at_end {
        pieces.push(current);
    }
    if !hidden {
        return Ok(None);
    }
    if closed && starts_at_start && ends_at_end && pieces.len() > 1 {
        // The last piece and the first meet at the start of the outline.
        let first = pieces.remove(0);
        if let Some(last) = pieces.last_mut() {
            last.extend(first.into_iter().skip(1));
        }
    }
    pieces.retain(|piece| length(piece) >= MIN_PIECE_LENGTH);
    Ok(Some(pieces))
}

/// The lines layer of a page: for each element in the order of the file,
/// its outline without fill when nothing drawn after it covers any of it,
/// otherwise the freehand pieces left visible, with its colour and width.
/// A page whose lines would not fit in `room` is refused.
pub(super) fn clip_outlines(
    objects: &[PageObject],
    mut room: Room,
) -> Result<Vec<PageObject>, Refused> {
    let occluders: Vec<Option<Occluder<'_>>> = objects
        .iter()
        .map(|object| (object.style.fill_enabled == 1).then(|| Occluder::of(object)))
        .collect();
    let mut work = 0usize;
    let mut lines = Vec::new();
    let mut later = Vec::new();
    for (index, object) in objects.iter().enumerate() {
        let (outline, closed) = outline(object);
        let extent = bounds(outline.iter().copied());
        later.clear();
        later.extend(
            occluders[index + 1..]
                .iter()
                .flatten()
                .filter(|occluder| overlap(extent, occluder.bounds)),
        );
        let pieces = if later.is_empty() {
            None
        } else {
            visible(&outline, closed, &later, room.points, &mut work)?
        };
        let Some(pieces) = pieces else {
            room.take(object.points.len())?;
            lines.push(PageObject {
                style: EpObjectStyle {
                    kind: object.style.kind,
                    fill_enabled: 0,
                    fill_rgb: 0,
                },
                rgb: object.rgb,
                width: object.width,
                points: object.points.clone(),
            });
            continue;
        };
        for piece in pieces {
            let mut points: Vec<EpPoint> = Vec::with_capacity(piece.len());
            for p in piece {
                let p = EpPoint {
                    x: p[0] as f32,
                    y: p[1] as f32,
                };
                if points.last() != Some(&p) {
                    points.push(p);
                }
            }
            if points.len() > MAX_STROKE_POINTS {
                return Err("an outline cut into more points than a stroke holds");
            }
            room.take(points.len())?;
            lines.push(PageObject {
                style: FREEHAND_STYLE,
                rgb: object.rgb,
                width: object.width,
                points,
            });
        }
    }
    Ok(lines)
}

#[cfg(test)]
mod tests;
