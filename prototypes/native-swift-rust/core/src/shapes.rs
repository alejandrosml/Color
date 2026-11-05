// SPDX-License-Identifier: MIT
//! The shapes of Color 1.1: the six new ones drawn in a box (triangle, star,
//! heart, diamond, hexagon, arrow), as closed contours; and the magnet shapes,
//! what a stroke drawn with the magnet tool looks like once the finger is
//! lifted, by geometric fitting alone: a line, a broken line, a rectangle, an
//! ellipse or a polygon. Nothing is recognised while the stroke is drawn,
//! nothing by holding still or by drawing over it again, and no network of
//! neurons: a few measures of the finished stroke, and the shape that fits.

use super::*;

pub(crate) const SHAPE_TRIANGLE: u32 = 0;
pub(crate) const SHAPE_STAR: u32 = 1;
#[cfg(test)]
pub(crate) const SHAPE_HEART: u32 = 2;
pub(crate) const SHAPE_DIAMOND: u32 = 3;
pub(crate) const SHAPE_HEXAGON: u32 = 4;
pub(crate) const SHAPE_ARROW: u32 = 5;
pub(crate) const SHAPE_COUNT: u32 = 6;

/// The most corners of a recognised polygon or broken line.
pub(crate) const MAX_CORNERS: usize = 12;
/// The most points of a shape's outline.
pub(crate) const MAX_OUTLINE_POINTS: usize = 1440;

type P = (f64, f64);

fn gap(a: P, b: P) -> f64 {
    (a.0 - b.0).hypot(a.1 - b.1)
}

// The outline of a shape, clockwise on the sheet (y down), in coordinates of
// its own; `sides` for its curves.
fn drawn(shape: u32, sides: usize) -> Vec<P> {
    match shape {
        SHAPE_TRIANGLE => vec![(0.5, 0.0), (1.0, 1.0), (0.0, 1.0)],
        SHAPE_DIAMOND => vec![(0.5, 0.0), (1.0, 0.5), (0.5, 1.0), (0.0, 0.5)],
        SHAPE_HEXAGON => vec![
            (0.25, 0.0),
            (0.75, 0.0),
            (1.0, 0.5),
            (0.75, 1.0),
            (0.25, 1.0),
            (0.0, 0.5),
        ],
        SHAPE_ARROW => vec![
            (0.0, 0.3),
            (0.6, 0.3),
            (0.6, 0.0),
            (1.0, 0.5),
            (0.6, 1.0),
            (0.6, 0.7),
            (0.0, 0.7),
        ],
        SHAPE_STAR => (0..10)
            .map(|i| {
                // Five points; the inner ones where the lines of a pentagram cross.
                let radius = if i % 2 == 0 {
                    1.0
                } else {
                    0.381_966_011_250_105_1
                };
                let angle =
                    -std::f64::consts::FRAC_PI_2 + std::f64::consts::PI * f64::from(i) / 5.0;
                (radius * angle.cos(), radius * angle.sin())
            })
            .collect(),
        // SHAPE_HEART, the only other one `outline` lets through.
        _ => (0..sides)
            .map(|i| {
                // The heart of the sixteen sines, its dip at the top first.
                let t = std::f64::consts::TAU * i as f64 / sides as f64;
                let x = 16.0 * t.sin().powi(3);
                let y = 13.0 * t.cos()
                    - 5.0 * (2.0 * t).cos()
                    - 2.0 * (3.0 * t).cos()
                    - (4.0 * t).cos();
                (x, -y)
            })
            .collect(),
    }
}

/// The outline of a shape in the box of corners `a` and `b`, touching its four
/// sides; an arrow points from `a`'s side towards `b`'s.
pub(crate) fn outline(shape: u32, a: EpPoint, b: EpPoint) -> Option<Vec<EpPoint>> {
    let finite = [a.x, a.y, b.x, b.y].iter().all(|v| v.is_finite());
    if shape >= SHAPE_COUNT || !finite || a.x == b.x || a.y == b.y {
        return None;
    }
    let (low, high) = (
        (f64::from(a.x.min(b.x)), f64::from(a.y.min(b.y))),
        (f64::from(a.x.max(b.x)), f64::from(a.y.max(b.y))),
    );
    // The curves within a tenth of a unit, as for an ellipse.
    let radius = ((high.0 - low.0).max(high.1 - low.1) / 2.0).max(0.2);
    let sides = ((std::f64::consts::PI / (1.0 - 0.1 / radius).acos()).ceil() as usize * 2)
        .clamp(48, MAX_OUTLINE_POINTS);
    let mut points = drawn(shape, sides);
    if shape == SHAPE_ARROW && b.x < a.x {
        // Pointing left, still clockwise.
        points = points.iter().rev().map(|&(x, y)| (1.0 - x, y)).collect();
    }
    let (mut min, mut max) = (
        (f64::INFINITY, f64::INFINITY),
        (f64::NEG_INFINITY, f64::NEG_INFINITY),
    );
    for &(x, y) in &points {
        min = (min.0.min(x), min.1.min(y));
        max = (max.0.max(x), max.1.max(y));
    }
    Some(
        points
            .iter()
            .map(|&(x, y)| EpPoint {
                x: (low.0 + (x - min.0) / (max.0 - min.0) * (high.0 - low.0)) as f32,
                y: (low.1 + (y - min.1) / (max.1 - min.1) * (high.1 - low.1)) as f32,
            })
            .collect(),
    )
}

/// What a magnet stroke became.
#[derive(Debug, PartialEq)]
pub(crate) struct Recognised {
    /// 0 a broken line, 1 a line, 2 a rectangle, 3 an ellipse, 6 a polygon.
    pub(crate) kind: u32,
    /// The corners of a broken line or a polygon, the ends of a line, the
    /// corners of the box of a rectangle or an ellipse.
    pub(crate) points: Vec<P>,
    /// About the box's centre, clockwise on the sheet: an ellipse's only.
    pub(crate) rotation: f64,
}

/// Points evenly spaced along the path, its ends included.
fn resample(path: &[P], count: usize) -> Vec<P> {
    let mut lengths = Vec::with_capacity(path.len());
    let mut total = 0.0;
    lengths.push(0.0);
    for w in path.windows(2) {
        total += gap(w[0], w[1]);
        lengths.push(total);
    }
    let mut out = Vec::with_capacity(count);
    let mut segment = 0;
    for k in 0..count {
        let target = total * k as f64 / (count - 1) as f64;
        while segment + 2 < path.len() && lengths[segment + 1] < target {
            segment += 1;
        }
        let span = lengths[segment + 1] - lengths[segment];
        let t = if span > 0.0 {
            ((target - lengths[segment]) / span).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let (a, b) = (path[segment], path[segment + 1]);
        out.push((a.0 + t * (b.0 - a.0), a.1 + t * (b.1 - a.1)));
    }
    out
}

/// The line through points: their centre and the unit direction along which
/// they spread most.
fn fit_line(points: &[P]) -> (P, P) {
    let n = points.len() as f64;
    let c = (
        points.iter().map(|p| p.0).sum::<f64>() / n,
        points.iter().map(|p| p.1).sum::<f64>() / n,
    );
    let (mut xx, mut xy, mut yy) = (0.0, 0.0, 0.0);
    for p in points {
        let (dx, dy) = (p.0 - c.0, p.1 - c.1);
        xx += dx * dx;
        xy += dx * dy;
        yy += dy * dy;
    }
    let angle = 0.5 * (2.0 * xy).atan2(xx - yy);
    (c, (angle.cos(), angle.sin()))
}

fn intersection(first: (P, P), second: (P, P)) -> Option<P> {
    let ((c1, d1), (c2, d2)) = (first, second);
    let cross = d1.0 * d2.1 - d1.1 * d2.0;
    // Lines within ten degrees of each other meet too far to say.
    if cross.abs() < 0.17 {
        return None;
    }
    let t = ((c2.0 - c1.0) * d2.1 - (c2.1 - c1.1) * d2.0) / cross;
    Some((c1.0 + t * d1.0, c1.1 + t * d1.1))
}

fn to_segment(p: P, a: P, b: P) -> f64 {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let length = dx * dx + dy * dy;
    let t = if length > 0.0 {
        (((p.0 - a.0) * dx + (p.1 - a.1) * dy) / length).clamp(0.0, 1.0)
    } else {
        0.0
    };
    gap(p, (a.0 + t * dx, a.1 + t * dy))
}

/// The corners Ramer–Douglas–Peucker keeps between `first` and `last` of an
/// open run of points, both kept.
fn corners_between(points: &[P], first: usize, last: usize, tolerance: f64, kept: &mut Vec<usize>) {
    let mut stack = vec![(first, last)];
    kept.push(first);
    kept.push(last);
    while let Some((a, b)) = stack.pop() {
        let mut farthest = (0.0, a);
        for i in a + 1..b {
            let d = to_segment(points[i], points[a], points[b]);
            if d > farthest.0 {
                farthest = (d, i);
            }
        }
        if farthest.0 > tolerance {
            kept.push(farthest.1);
            stack.push((a, farthest.1));
            stack.push((farthest.1, b));
        }
    }
    kept.sort_unstable();
    kept.dedup();
}

/// A polygon through the corners of a closed loop, its sides straightened by
/// the lines that fit them; with how far the points of its sides stray from
/// them on average, for the side that strays most, as a share of its length.
fn polygon(loop_points: &[P], tolerance: f64, size: f64) -> Option<(Vec<P>, f64)> {
    let n = loop_points.len();
    let c = (
        loop_points.iter().map(|p| p.0).sum::<f64>() / n as f64,
        loop_points.iter().map(|p| p.1).sum::<f64>() / n as f64,
    );
    // From the point farthest from the centre, surely a corner if any, and
    // the point farthest from it: two runs, each simplified.
    let start =
        (0..n).max_by(|&a, &b| gap(loop_points[a], c).total_cmp(&gap(loop_points[b], c)))?;
    let turned: Vec<P> = (0..=n).map(|i| loop_points[(start + i) % n]).collect();
    let far =
        (1..n).max_by(|&a, &b| gap(turned[a], turned[0]).total_cmp(&gap(turned[b], turned[0])))?;
    let mut indices = Vec::new();
    corners_between(&turned, 0, far, tolerance, &mut indices);
    corners_between(&turned, far, n, tolerance, &mut indices);
    indices.retain(|&i| i < n);
    // The points of side j, from its first corner to the next, a share of
    // them left out at each end.
    let side = |indices: &[usize], j: usize, share: usize| -> Vec<P> {
        let k = indices.len();
        let (a, b) = (
            indices[j],
            if j + 1 < k {
                indices[j + 1]
            } else {
                indices[0] + n
            },
        );
        let trim = (b - a) / share;
        (a + trim..=b - trim).map(|i| turned[i % n]).collect()
    };
    // Straighten: each corner where the lines of its two sides meet; corners
    // that barely turn, or end a side too short to mean one, are dropped and
    // the sides fitted again.
    for _ in 0..6 {
        let k = indices.len();
        if k < 3 {
            return None;
        }
        let lines: Vec<(P, P)> = (0..k).map(|j| fit_line(&side(&indices, j, 5))).collect();
        let corners: Vec<P> = (0..k)
            .map(|j| intersection(lines[(j + k - 1) % k], lines[j]).unwrap_or(turned[indices[j]]))
            .collect();
        let dropped: Vec<bool> = (0..k)
            .map(|j| {
                let (before, here, after) =
                    (corners[(j + k - 1) % k], corners[j], corners[(j + 1) % k]);
                let a = (here.1 - before.1).atan2(here.0 - before.0);
                let b = (after.1 - here.1).atan2(after.0 - here.0);
                let mut turn = (b - a).abs();
                if turn > std::f64::consts::PI {
                    turn = std::f64::consts::TAU - turn;
                }
                turn < 20f64.to_radians() || gap(before, here) < 0.06 * size
            })
            .collect();
        if let Some(first) = dropped.iter().position(|&d| d) {
            // One at a time: two neighbours may each look dropped because of
            // the other.
            indices.remove(first);
            continue;
        }
        let worst = (0..k)
            .map(|j| {
                let (a, b) = (corners[j], corners[(j + 1) % k]);
                let length = gap(a, b);
                let (dx, dy) = ((b.0 - a.0) / length, (b.1 - a.1) / length);
                let run = side(&indices, j, 10);
                run.iter()
                    .map(|p| ((p.0 - a.0) * dy - (p.1 - a.1) * dx).abs())
                    .sum::<f64>()
                    / run.len() as f64
                    / length
            })
            .fold(0.0, f64::max);
        return Some((corners, worst));
    }
    None
}

/// Whether two sides of a closed polygon that do not share a corner cross.
fn crosses_itself(corners: &[P]) -> bool {
    let k = corners.len();
    let side = |j: usize| (corners[j], corners[(j + 1) % k]);
    let turn = |a: P, b: P, c: P| (b.0 - a.0) * (c.1 - a.1) - (b.1 - a.1) * (c.0 - a.0);
    (0..k).any(|i| {
        (i + 2..k).any(|j| {
            if (j + 1) % k == i {
                return false;
            }
            let ((a, b), (c, d)) = (side(i), side(j));
            turn(a, b, c) * turn(a, b, d) < 0.0 && turn(c, d, a) * turn(c, d, b) < 0.0
        })
    })
}

/// The ellipse of the same area and moments as the closed loop: its centre,
/// semi-axes and the angle of the first; and how far the loop strays from
/// it, as a share of its radius at each point.
fn ellipse(loop_points: &[P]) -> Option<(P, f64, f64, f64, f64)> {
    let n = loop_points.len();
    let (mut area, mut cx, mut cy, mut xx, mut yy, mut xy) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    // Moments of the enclosed area by Green's formula, about the first point
    // to keep the sums small.
    let o = loop_points[0];
    for i in 0..n {
        let (a, b) = (loop_points[i], loop_points[(i + 1) % n]);
        let (x0, y0, x1, y1) = (a.0 - o.0, a.1 - o.1, b.0 - o.0, b.1 - o.1);
        let cross = x0 * y1 - x1 * y0;
        area += cross;
        cx += (x0 + x1) * cross;
        cy += (y0 + y1) * cross;
        xx += (x0 * x0 + x0 * x1 + x1 * x1) * cross;
        yy += (y0 * y0 + y0 * y1 + y1 * y1) * cross;
        xy += (x0 * y1 + 2.0 * x0 * y0 + 2.0 * x1 * y1 + x1 * y0) * cross;
    }
    area /= 2.0;
    if area.abs() < 1e-9 {
        return None;
    }
    let (mx, my) = (cx / (6.0 * area), cy / (6.0 * area));
    let (sxx, syy, sxy) = (
        xx / (12.0 * area) - mx * mx,
        yy / (12.0 * area) - my * my,
        xy / (24.0 * area) - mx * my,
    );
    let mean = (sxx + syy) / 2.0;
    let spread = (((sxx - syy) / 2.0).powi(2) + sxy * sxy).sqrt();
    let (major, minor) = (mean + spread, mean - spread);
    if minor <= 0.0 {
        return None;
    }
    let (a, b) = (2.0 * major.sqrt(), 2.0 * minor.sqrt());
    let angle = 0.5 * (2.0 * sxy).atan2(sxx - syy);
    let centre = (mx + o.0, my + o.1);
    let (sin, cos) = angle.sin_cos();
    let stray = loop_points
        .iter()
        .map(|p| {
            let (dx, dy) = (p.0 - centre.0, p.1 - centre.1);
            let (u, v) = (dx * cos + dy * sin, -dx * sin + dy * cos);
            ((u / a).powi(2) + (v / b).powi(2)).sqrt() - 1.0
        })
        .map(f64::abs)
        .sum::<f64>()
        / n as f64;
    Some((centre, a, b, angle, stray))
}

const SAMPLES: usize = 96;

/// What the stroke of the magnet tool looks like, or None when it looks
/// like nothing simple: it then stays as drawn.
pub(crate) fn recognise(points: &[EpPoint]) -> Option<Recognised> {
    let mut path: Vec<P> = Vec::with_capacity(points.len());
    for p in points {
        let p = (f64::from(p.x), f64::from(p.y));
        if !p.0.is_finite() || !p.1.is_finite() {
            return None;
        }
        if path.last() != Some(&p) {
            path.push(p);
        }
    }
    if path.len() < 2 {
        return None;
    }
    let (mut min, mut max) = (
        (f64::INFINITY, f64::INFINITY),
        (f64::NEG_INFINITY, f64::NEG_INFINITY),
    );
    for &(x, y) in &path {
        min = (min.0.min(x), min.1.min(y));
        max = (max.0.max(x), max.1.max(y));
    }
    let size = (max.0 - min.0).hypot(max.1 - min.1);
    if size < 4.0 {
        return None;
    }
    let samples = resample(&path, SAMPLES);
    // Closed when it comes back near its start after half its way; what goes
    // on past that point is left out.
    let back = (SAMPLES / 2..SAMPLES)
        .min_by(|&a, &b| gap(samples[a], samples[0]).total_cmp(&gap(samples[b], samples[0])))?;
    if gap(samples[back], samples[0]) <= 0.2 * size {
        let mut ring: Vec<P> = samples[..=back].to_vec();
        ring.push(samples[0]);
        let mut loop_points = resample(&ring, SAMPLES + 1);
        loop_points.pop();
        closed(&loop_points)
    } else {
        open(&samples, size)
    }
}

fn open(samples: &[P], size: f64) -> Option<Recognised> {
    let (first, last) = (samples[0], samples[samples.len() - 1]);
    let chord = gap(first, last);
    let length: f64 = samples.windows(2).map(|w| gap(w[0], w[1])).sum();
    let line = fit_line(samples);
    let straying = samples
        .iter()
        .map(|&p| to_segment(p, first, last))
        .fold(0.0, f64::max);
    if chord > 0.0 && straying <= 0.06 * chord + 1.0 && length <= 1.2 * chord {
        let project = |p: P| {
            let t = (p.0 - line.0 .0) * line.1 .0 + (p.1 - line.0 .1) * line.1 .1;
            (line.0 .0 + t * line.1 .0, line.0 .1 + t * line.1 .1)
        };
        let (mut a, mut b) = (project(first), project(last));
        // Nearly level or upright: exactly, about its middle.
        let middle = ((a.0 + b.0) / 2.0, (a.1 + b.1) / 2.0);
        let half = gap(a, b) / 2.0;
        let angle = (b.1 - a.1).atan2(b.0 - a.0);
        let quarter = std::f64::consts::FRAC_PI_2;
        let nearest = (angle / quarter).round() * quarter;
        if (angle - nearest).abs() < 6f64.to_radians() {
            let (sin, cos) = nearest.sin_cos();
            a = (middle.0 - half * cos, middle.1 - half * sin);
            b = (middle.0 + half * cos, middle.1 + half * sin);
        }
        return Some(Recognised {
            kind: 1,
            points: vec![a, b],
            rotation: 0.0,
        });
    }
    // A broken line: a few straight pieces, each long enough to mean it.
    let mut kept = Vec::new();
    corners_between(samples, 0, samples.len() - 1, 0.035 * size, &mut kept);
    let k = kept.len();
    if !(3..=7).contains(&k) {
        return None;
    }
    let lines: Vec<(P, P)> = kept
        .windows(2)
        .map(|w| {
            let trim = (w[1] - w[0]) / 5;
            fit_line(&samples[w[0] + trim..=w[1] - trim])
        })
        .collect();
    let mut corners = Vec::with_capacity(k);
    let project = |line: (P, P), p: P| {
        let t = (p.0 - line.0 .0) * line.1 .0 + (p.1 - line.0 .1) * line.1 .1;
        (line.0 .0 + t * line.1 .0, line.0 .1 + t * line.1 .1)
    };
    corners.push(project(lines[0], first));
    for j in 1..k - 1 {
        corners.push(intersection(lines[j - 1], lines[j]).unwrap_or(samples[kept[j]]));
    }
    corners.push(project(lines[k - 2], last));
    let error = samples
        .iter()
        .map(|&p| {
            corners
                .windows(2)
                .map(|w| to_segment(p, w[0], w[1]))
                .fold(f64::INFINITY, f64::min)
        })
        .sum::<f64>()
        / samples.len() as f64;
    let short = corners.windows(2).any(|w| gap(w[0], w[1]) < 0.1 * size);
    if error > 0.015 * size || short {
        return None;
    }
    Some(Recognised {
        kind: 0,
        points: corners,
        rotation: 0.0,
    })
}

fn closed(loop_points: &[P]) -> Option<Recognised> {
    let (mut min, mut max) = (
        (f64::INFINITY, f64::INFINITY),
        (f64::NEG_INFINITY, f64::NEG_INFINITY),
    );
    for &(x, y) in loop_points {
        min = (min.0.min(x), min.1.min(y));
        max = (max.0.max(x), max.1.max(y));
    }
    let size = (max.0 - min.0).hypot(max.1 - min.1);
    let ellipse = ellipse(loop_points);
    if let Some((corners, worst)) = polygon(loop_points, 0.035 * size, size) {
        let k = corners.len();
        // Straight sides, a little wobble allowed: a round thing traced
        // through a few corners has sides as bent as their arcs, on average
        // three times more than a hand's wobble.
        let limit = if k <= 4 { 0.02 } else { 0.017 };
        if (3..=MAX_CORNERS).contains(&k) && worst <= limit && !crosses_itself(&corners) {
            return Some(polygon_shape(&corners));
        }
    }
    let (centre, a, b, angle, stray) = ellipse?;
    if stray >= 0.06 {
        return None;
    }
    let (mut a, mut b, mut angle) = (a, b, angle);
    if b / a > 0.85 {
        // A circle meant.
        let r = (a + b) / 2.0;
        (a, b, angle) = (r, r, 0.0);
    } else if angle.abs() < 10f64.to_radians() {
        angle = 0.0;
    } else if angle.abs() > 80f64.to_radians() {
        (a, b, angle) = (b, a, 0.0);
    }
    Some(Recognised {
        kind: 3,
        points: vec![(centre.0 - a, centre.1 - b), (centre.0 + a, centre.1 + b)],
        rotation: angle,
    })
}

/// A polygon, or a rectangle when its four corners are square: level, a box;
/// turned, its four exact corners.
fn polygon_shape(corners: &[P]) -> Recognised {
    let k = corners.len();
    if k == 4 {
        let square = (0..4).all(|j| {
            let (before, here, after) = (corners[(j + 3) % 4], corners[j], corners[(j + 1) % 4]);
            let (u, v) = (
                (before.0 - here.0, before.1 - here.1),
                (after.0 - here.0, after.1 - here.1),
            );
            let cosine = (u.0 * v.0 + u.1 * v.1) / (u.0.hypot(u.1) * v.0.hypot(v.1));
            cosine.abs() < 15f64.to_radians().sin()
        });
        if square {
            // The sides' direction, a quarter turn being the same direction.
            let (mut s, mut c) = (0.0, 0.0);
            for j in 0..4 {
                let (a, b) = (corners[j], corners[(j + 1) % 4]);
                let angle = (b.1 - a.1).atan2(b.0 - a.0);
                s += (4.0 * angle).sin();
                c += (4.0 * angle).cos();
            }
            let mut angle = s.atan2(c) / 4.0;
            if angle.abs() < 8f64.to_radians() {
                angle = 0.0;
            }
            let (sin, cos) = angle.sin_cos();
            let along: Vec<P> = corners
                .iter()
                .map(|p| (p.0 * cos + p.1 * sin, -p.0 * sin + p.1 * cos))
                .collect();
            let (mut low, mut high) = (
                (f64::INFINITY, f64::INFINITY),
                (f64::NEG_INFINITY, f64::NEG_INFINITY),
            );
            for &(u, v) in &along {
                low = (low.0.min(u), low.1.min(v));
                high = (high.0.max(u), high.1.max(v));
            }
            let (mut w, mut h) = (high.0 - low.0, high.1 - low.1);
            let middle = ((low.0 + high.0) / 2.0, (low.1 + high.1) / 2.0);
            if (w - h).abs() <= 0.12 * w.max(h) {
                // A square meant.
                let side = (w + h) / 2.0;
                (w, h) = (side, side);
            }
            let back = |u: f64, v: f64| (u * cos - v * sin, u * sin + v * cos);
            if angle == 0.0 {
                return Recognised {
                    kind: 2,
                    points: vec![
                        (middle.0 - w / 2.0, middle.1 - h / 2.0),
                        (middle.0 + w / 2.0, middle.1 + h / 2.0),
                    ],
                    rotation: 0.0,
                };
            }
            let box_corners = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)];
            return Recognised {
                kind: KIND_CONTOUR,
                points: box_corners
                    .iter()
                    .map(|&(su, sv)| back(middle.0 + su * w / 2.0, middle.1 + sv * h / 2.0))
                    .collect(),
                rotation: 0.0,
            };
        }
    }
    Recognised {
        kind: KIND_CONTOUR,
        points: corners.to_vec(),
        rotation: 0.0,
    }
}

/// The outline of one of the shapes of 1.1 — 0 triangle, 1 star, 2 heart,
/// 3 diamond, 4 hexagon, 5 arrow — in the box of corners `a` and `b`, as the
/// points of a contour. Returns 0 with the points written; -1 for an unknown
/// shape, a box without a width or a height, or a capacity below the count,
/// which is written to non-NULL `out_count` whenever the shape is valid.
///
/// # Safety
/// `out_points` must be writable for `capacity` points; `out_count` NULL or
/// writable.
#[no_mangle]
pub unsafe extern "C" fn ep_shape_outline(
    shape: u32,
    a: EpPoint,
    b: EpPoint,
    out_points: *mut EpPoint,
    capacity: usize,
    out_count: *mut usize,
) -> i32 {
    let Some(points) = outline(shape, a, b) else {
        return INVALID;
    };
    if !out_count.is_null() {
        unsafe { out_count.write(points.len()) };
    }
    if out_points.is_null() || capacity < points.len() {
        return INVALID;
    }
    unsafe { slice::from_raw_parts_mut(out_points, points.len()) }.copy_from_slice(&points);
    0
}

/// What the stroke of `count` points drawn with the magnet tool becomes, by
/// geometric fitting, kept on the sheet of `document`: writes its kind to
/// `out_kind` (0 a broken line, 1 a line, 2 a rectangle, 3 an ellipse, 6 a
/// polygon), its points (up to 12: corners, ends, or a box's two corners) and
/// an ellipse's turn about its centre, clockwise in radians. Returns 1 when a
/// shape was recognised, 0 when the stroke stays as drawn, -1 for invalid
/// arguments or a capacity below 12.
///
/// # Safety
/// `document` must be live; `points` must address `count` points; outputs
/// writable, disjoint from the inputs.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn ep_recognise_shape(
    document: *const EpDocument,
    points: *const EpPoint,
    count: usize,
    out_kind: *mut u32,
    out_points: *mut EpPoint,
    capacity: usize,
    out_count: *mut usize,
    out_rotation: *mut f32,
) -> i32 {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return INVALID;
    };
    if points.is_null()
        || !(1..=MAX_STROKE_POINTS).contains(&count)
        || out_kind.is_null()
        || out_points.is_null()
        || capacity < MAX_CORNERS
        || out_count.is_null()
        || out_rotation.is_null()
    {
        return INVALID;
    }
    let points = unsafe { slice::from_raw_parts(points, count) };
    let Some(shape) = recognise(points) else {
        return 0;
    };
    let (width, height) = (f64::from(doc.width), f64::from(doc.height));
    let on_sheet: Vec<EpPoint> = shape
        .points
        .iter()
        .map(|&(x, y)| EpPoint {
            x: x.clamp(0.0, width) as f32,
            y: y.clamp(0.0, height) as f32,
        })
        .collect();
    // Kept on the sheet, a shape must keep what its kind needs.
    if on_sheet.len() > MAX_CORNERS
        || !(shape.kind == 0 || valid_shape_points(shape.kind, &on_sheet))
    {
        return 0;
    }
    unsafe {
        out_kind.write(shape.kind);
        slice::from_raw_parts_mut(out_points, on_sheet.len()).copy_from_slice(&on_sheet);
        out_count.write(on_sheet.len());
        out_rotation.write(shape.rotation as f32);
    }
    1
}

#[cfg(test)]
mod tests;
