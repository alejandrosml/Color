// SPDX-License-Identifier: MIT
//! The marks of a freehand stroke drawn with a tool of Color 1.1, or with a
//! pressure: what the screen paints, what the SVG export writes and what the
//! film reveals are these same marks, made here once.
//!
//! A mark is a polygon or a circle, in the coordinates of the sheet, before
//! the object's mirror and rotation. Marks of one group share a colour and an
//! opacity and are filled together, as one path, by the non-zero rule: every
//! polygon turns clockwise on the sheet (whose y axis goes down), as a circle
//! does, so that overlapping marks of a group add up and never cut holes, and
//! a group shows no seam where its marks meet.
//!
//! Scattered marks (chalk, airbrush, grass, confetti) come at steps of the
//! length of the stroke, each step drawing its numbers from the stroke's seed
//! and its own rank: marks of the beginning of a stroke do not change while
//! it goes on, so that the stroke being drawn shows the marks it will keep.

use super::*;

/// A polygon of `count` points from `first`, or a circle centred on point
/// `first` of radius `radius`.
pub(crate) const POLYGON: u32 = 0;
pub(crate) const CIRCLE: u32 = 1;

/// One mark, as the C contract gives it.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EpMark {
    pub shape: u32,
    pub rgb: u32,
    /// Opacity, 1 to 255.
    pub alpha: u32,
    /// Marks of one group follow each other and are filled together.
    pub group: u32,
    pub first: u32,
    pub count: u32,
    pub radius: f32,
}

/// The most marks one stroke may give, and their points: beyond them a tool
/// stops adding marks rather than ask for unbounded memory.
const MAX_MARKS: usize = 400_000;
const MAX_MARK_POINTS: usize = 2_000_000;
/// The most steps a scattering tool takes along one stroke.
const MAX_STEPS: u64 = 2_000_000;

/// Whether a freehand stroke of this tool and these pressures is painted by
/// marks (else by the classic round or felt path).
pub(crate) fn has_marks(tool: u32, has_pressures: bool) -> bool {
    match tool {
        TOOL_ROUND => has_pressures,
        TOOL_FELT => false,
        _ => known_tool(tool),
    }
}

pub(crate) struct Marks {
    pub marks: Vec<EpMark>,
    pub points: Vec<EpPoint>,
    group: u32,
    open: Option<(u32, u32)>,
}

impl Marks {
    pub fn new() -> Self {
        Self {
            marks: Vec::new(),
            points: Vec::new(),
            group: 0,
            open: None,
        }
    }

    fn full(&self, points: usize) -> bool {
        self.marks.len() >= MAX_MARKS || self.points.len() + points > MAX_MARK_POINTS
    }

    // The group of this colour and opacity: the current one when it is the
    // same, a new one otherwise.
    fn group_of(&mut self, rgb: u32, alpha: u32) -> u32 {
        if self.open != Some((rgb, alpha)) {
            if self.open.is_some() {
                self.group += 1;
            }
            self.open = Some((rgb, alpha));
        }
        self.group
    }

    fn reserve(&mut self, marks: usize, points: usize) -> Result<(), i32> {
        self.marks
            .try_reserve(marks)
            .map_err(|_| ALLOCATION_FAILURE)?;
        self.points
            .try_reserve(points)
            .map_err(|_| ALLOCATION_FAILURE)
    }

    fn circle(&mut self, centre: EpPoint, radius: f32, rgb: u32, alpha: u32) -> Result<(), i32> {
        if !(radius > 0.0 && radius.is_finite()) || self.full(1) {
            return Ok(());
        }
        self.reserve(1, 1)?;
        let group = self.group_of(rgb, alpha);
        self.marks.push(EpMark {
            shape: CIRCLE,
            rgb,
            alpha,
            group,
            first: self.points.len() as u32,
            count: 1,
            radius,
        });
        self.points.push(centre);
        Ok(())
    }

    /// A polygon, turned clockwise on the sheet whatever order it is given
    /// in; a flat one is left out.
    fn polygon(&mut self, corners: &[EpPoint], rgb: u32, alpha: u32) -> Result<(), i32> {
        let area = signed_area(corners);
        if corners.len() < 3 || area == 0.0 || !area.is_finite() || self.full(corners.len()) {
            return Ok(());
        }
        self.reserve(1, corners.len())?;
        let group = self.group_of(rgb, alpha);
        let first = self.points.len() as u32;
        // Positive area with y down is clockwise on the screen.
        if area > 0.0 {
            self.points.extend_from_slice(corners);
        } else {
            self.points.extend(corners.iter().rev().copied());
        }
        self.marks.push(EpMark {
            shape: POLYGON,
            rgb,
            alpha,
            group,
            first,
            count: corners.len() as u32,
            radius: 0.0,
        });
        Ok(())
    }
}

/// Twice the signed area of a polygon, positive when it turns clockwise on a
/// sheet whose y axis goes down.
fn signed_area(corners: &[EpPoint]) -> f64 {
    let mut sum = 0.0;
    for (index, a) in corners.iter().enumerate() {
        let b = corners[(index + 1) % corners.len()];
        sum += f64::from(a.x) * f64::from(b.y) - f64::from(b.x) * f64::from(a.y);
    }
    sum
}

// SplitMix64: a small, well-mixed generator; one per step, from the seed and
// the step's rank, so that every step draws the same numbers every time.
struct Draw(u64);

impl Draw {
    fn at(seed: u32, rank: u64, salt: u64) -> Self {
        Self(u64::from(seed) ^ rank.wrapping_mul(0x9e37_79b9_7f4a_7c15) ^ salt.rotate_left(32))
    }

    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    fn unit(&mut self) -> f32 {
        (self.next() >> 40) as f32 / (1u64 << 24) as f32
    }

    /// Uniform in [low, high).
    fn between(&mut self, low: f32, high: f32) -> f32 {
        low + (high - low) * self.unit()
    }

    fn below(&mut self, count: u32) -> u32 {
        (self.next() % u64::from(count)) as u32
    }
}

fn add(a: EpPoint, b: EpPoint) -> EpPoint {
    point_at(a.x + b.x, a.y + b.y)
}

fn sub(a: EpPoint, b: EpPoint) -> EpPoint {
    point_at(a.x - b.x, a.y - b.y)
}

fn scaled(a: EpPoint, factor: f32) -> EpPoint {
    point_at(a.x * factor, a.y * factor)
}

fn point_at(x: f32, y: f32) -> EpPoint {
    EpPoint { x, y }
}

fn length(a: EpPoint) -> f32 {
    a.x.hypot(a.y)
}

/// A colour a little lighter (positive) or darker (negative), in sRGB.
fn shade(rgb: u32, amount: f32) -> u32 {
    let channel = |shift: u32| {
        let value = ((rgb >> shift) & 0xff) as f32;
        let target = if amount >= 0.0 { 255.0 } else { 0.0 };
        (value + (target - value) * amount.abs())
            .round()
            .clamp(0.0, 255.0) as u32
    };
    (channel(16) << 16) | (channel(8) << 8) | channel(0)
}

/// What one stroke is for the marks: its points and pressures, its width,
/// colour, tool and seed.
pub(crate) struct Stroked<'a> {
    pub points: &'a [EpPoint],
    pub pressures: &'a [u8],
    pub width: f32,
    pub rgb: u32,
    pub tool: u32,
    pub seed: u32,
}

impl Stroked<'_> {
    fn radius_at(&self, index: usize) -> f32 {
        let half = self.width / 2.0;
        match self.pressures.get(index) {
            Some(&pressure) => half * f32::from(pressure) / 255.0,
            None => half,
        }
    }
}

/// Keeps `item` among what a scattering tool collects before it draws them,
/// as long as that stays under the bound of the marks: false once full,
/// which stops the steps. A stroke of any length then asks for bounded
/// memory, its first marks drawn and the others left out, as `Marks` does.
fn collect<T>(items: &mut Vec<T>, item: T) -> Result<bool, i32> {
    if items.len() >= MAX_MARKS {
        return Ok(false);
    }
    items.try_reserve(1).map_err(|_| ALLOCATION_FAILURE)?;
    items.push(item);
    Ok(items.len() < MAX_MARKS)
}

/// The steps of a scattering tool along the stroke, every `spacing` units of
/// its length, from the segment `from` on: the rank of the step, where it is,
/// the direction of the stroke there, the radius there.
fn steps(
    stroke: &Stroked<'_>,
    spacing: f32,
    from: usize,
    mut visit: impl FnMut(u64, EpPoint, EpPoint, f32) -> Result<bool, i32>,
) -> Result<(), i32> {
    let points = stroke.points;
    if points.len() == 1 {
        // A dot: its single step, if it is asked for.
        if from == 0 {
            visit(0, points[0], point_at(1.0, 0.0), stroke.radius_at(0))?;
        }
        return Ok(());
    }
    let spacing = f64::from(spacing.max(0.25));
    let mut travelled = 0.0f64;
    // However long the stroke, and however often it goes over the same
    // place (where the bricks have nothing more to lay), a bounded number
    // of steps.
    let mut visits = 0u64;
    for index in 0..points.len() - 1 {
        let a = points[index];
        let b = points[index + 1];
        let span = f64::from(length(sub(b, a)));
        let start = travelled;
        travelled += span;
        if index < from || span == 0.0 {
            continue;
        }
        let direction = scaled(sub(b, a), (1.0 / span) as f32);
        // The steps whose place along the stroke falls in this segment.
        let mut rank = (start / spacing).ceil() as u64;
        while (rank as f64) * spacing < travelled || (index == points.len() - 2 && rank == 0) {
            let along = ((rank as f64) * spacing - start).clamp(0.0, span);
            let t = (along / span) as f32;
            let at = add(a, scaled(sub(b, a), t));
            let radius = stroke.radius_at(index)
                + (stroke.radius_at(index + 1) - stroke.radius_at(index)) * t;
            visits += 1;
            if visits > MAX_STEPS || !visit(rank, at, direction, radius)? {
                return Ok(());
            }
            rank += 1;
        }
    }
    Ok(())
}

/// The quadrilateral between two circles, tangent to both on each side: with
/// a disc at every point, a stroke whose width changes from point to point.
fn tangent_quad(a: EpPoint, ra: f32, b: EpPoint, rb: f32) -> Option<[EpPoint; 4]> {
    let d = sub(b, a);
    let distance = length(d);
    if distance <= (ra - rb).abs() || distance == 0.0 {
        return None; // one circle holds the other: the discs suffice
    }
    let u = scaled(d, 1.0 / distance);
    let normal = point_at(-u.y, u.x);
    // The outer tangents of two circles of different radii lean by this sine.
    let s = (ra - rb) / distance;
    let c = (1.0 - s * s).max(0.0).sqrt();
    let side = |sign: f32| add(scaled(u, s), scaled(normal, sign * c));
    let (left, right) = (side(1.0), side(-1.0));
    Some([
        add(a, scaled(left, ra)),
        add(b, scaled(left, rb)),
        add(b, scaled(right, rb)),
        add(a, scaled(right, ra)),
    ])
}

// A disc at every point and, between two points, the quadrilateral tangent
// to both discs. The disc at a point ends the segment that reaches it (the
// first starts the stroke): the marks of segments from `from` on are then
// exactly what the stroke adds after its first `from` segments.
fn pressed(stroke: &Stroked<'_>, from: usize, out: &mut Marks) -> Result<(), i32> {
    let points = stroke.points;
    if from == 0 {
        out.circle(points[0], stroke.radius_at(0), stroke.rgb, 255)?;
    }
    for index in from..points.len().saturating_sub(1) {
        if let Some(quad) = tangent_quad(
            points[index],
            stroke.radius_at(index),
            points[index + 1],
            stroke.radius_at(index + 1),
        ) {
            out.polygon(&quad, stroke.rgb, 255)?;
        }
        out.circle(
            points[index + 1],
            stroke.radius_at(index + 1),
            stroke.rgb,
            255,
        )?;
    }
    Ok(())
}

/// The nib of calligraphy: a flat pen held at 45 degrees.
fn calligraphy(stroke: &Stroked<'_>, from: usize, out: &mut Marks) -> Result<(), i32> {
    let nib = |index: usize| {
        let half = stroke.radius_at(index);
        point_at(
            half * std::f32::consts::FRAC_1_SQRT_2,
            -half * std::f32::consts::FRAC_1_SQRT_2,
        )
    };
    let points = stroke.points;
    if points.len() == 1 {
        let n = nib(0);
        // A dot of a flat pen: the nib itself, one unit thick.
        let across = point_at(
            0.5 * std::f32::consts::FRAC_1_SQRT_2,
            0.5 * std::f32::consts::FRAC_1_SQRT_2,
        );
        let p = points[0];
        return out.polygon(
            &[
                sub(sub(p, n), across),
                add(sub(p, n), across),
                add(add(p, n), across),
                sub(add(p, n), across),
            ],
            stroke.rgb,
            255,
        );
    }
    for index in from..points.len().saturating_sub(1) {
        let (a, b) = (points[index], points[index + 1]);
        let (na, nb) = (nib(index), nib(index + 1));
        // The nib swept from one point to the next: a parallelogram, a hair
        // longer at each end so that neighbours overlap instead of touching.
        let u = sub(b, a);
        let span = length(u);
        let lap = if span > 0.0 {
            scaled(u, 0.05 / span)
        } else {
            point_at(0.0, 0.0)
        };
        let (a, b) = (sub(a, lap), add(b, lap));
        out.polygon(
            &[sub(a, na), add(a, na), add(b, nb), sub(b, nb)],
            stroke.rgb,
            255,
        )?;
    }
    Ok(())
}

fn chalk(stroke: &Stroked<'_>, from: usize, out: &mut Marks) -> Result<(), i32> {
    let spacing = (stroke.width / 5.0).max(0.75);
    let mut grains = Vec::new();
    steps(stroke, spacing, from, |rank, at, direction, radius| {
        let mut draw = Draw::at(stroke.seed, rank, 3);
        let normal = point_at(-direction.y, direction.x);
        for _ in 0..3 {
            // More grains near the middle of the chalk than at its edges.
            let across = (draw.unit() + draw.unit() - 1.0) * radius;
            let along = draw.between(-0.5, 0.5) * spacing;
            let centre = add(at, add(scaled(normal, across), scaled(direction, along)));
            let size = draw.between(0.08, 0.17) * stroke.width.max(1.0);
            let level = draw.below(3);
            if !collect(&mut grains, (level, centre, size.max(0.4)))? {
                return Ok(false);
            }
        }
        Ok(true)
    })?;
    // Three opacities, three groups: lighter grains first.
    for (level, alpha) in [(0, 120), (1, 175), (2, 230)] {
        for &(grain, centre, size) in &grains {
            if grain == level {
                out.circle(centre, size, stroke.rgb, alpha)?;
            }
        }
    }
    Ok(())
}

fn airbrush(stroke: &Stroked<'_>, from: usize, out: &mut Marks) -> Result<(), i32> {
    let spacing = (stroke.width / 6.0).max(0.75);
    let mut dots = Vec::new();
    steps(stroke, spacing, from, |rank, at, _direction, radius| {
        let mut draw = Draw::at(stroke.seed, rank, 4);
        for _ in 0..8 {
            // Denser in the middle of the spray: the square root of a uniform
            // spreads evenly over the disc, its square gathers at the centre.
            let distance = radius * 1.3 * draw.unit().powf(0.75);
            let angle = draw.unit() * std::f32::consts::TAU;
            let centre = add(at, point_at(distance * angle.cos(), distance * angle.sin()));
            let size = (stroke.width / 26.0).max(0.45) * draw.between(0.7, 1.3);
            if !collect(&mut dots, (draw.below(2), centre, size))? {
                return Ok(false);
            }
        }
        Ok(true)
    })?;
    for (level, alpha) in [(0, 70), (1, 125)] {
        for &(dot, centre, size) in &dots {
            if dot == level {
                out.circle(centre, size, stroke.rgb, alpha)?;
            }
        }
    }
    Ok(())
}

/// A colour of the rainbow, from 0 (red) round to 1 (red again).
fn rainbow_colour(turn: f32) -> u32 {
    let hue = turn.rem_euclid(1.0) * 6.0;
    let x = 1.0 - (hue % 2.0 - 1.0).abs();
    let (r, g, b) = match hue as u32 {
        0 => (1.0, x, 0.0),
        1 => (x, 1.0, 0.0),
        2 => (0.0, 1.0, x),
        3 => (0.0, x, 1.0),
        4 => (x, 0.0, 1.0),
        _ => (1.0, 0.0, x),
    };
    let byte = |v: f32| (v * 255.0).round() as u32;
    (byte(r) << 16) | (byte(g) << 8) | byte(b)
}

fn rainbow(stroke: &Stroked<'_>, from: usize, out: &mut Marks) -> Result<(), i32> {
    let points = stroke.points;
    // Twenty-four colours round the rainbow, one turn every 12 widths.
    let turn_length = f64::from(stroke.width.max(1.0)) * 12.0;
    let colour_at = |travelled: f64| {
        let step = ((travelled / turn_length).rem_euclid(1.0) * 24.0).floor() as u32;
        rainbow_colour(step as f32 / 24.0)
    };
    if from == 0 {
        out.circle(points[0], stroke.radius_at(0), colour_at(0.0), 255)?;
    }
    // As for a pressed stroke: each segment brings its quadrilateral and the
    // disc that ends it, in the colour of where the segment starts.
    let mut travelled = 0.0f64;
    for index in 0..points.len().saturating_sub(1) {
        if index >= from {
            let colour = colour_at(travelled);
            if let Some(quad) = tangent_quad(
                points[index],
                stroke.radius_at(index),
                points[index + 1],
                stroke.radius_at(index + 1),
            ) {
                out.polygon(&quad, colour, 255)?;
            }
            out.circle(points[index + 1], stroke.radius_at(index + 1), colour, 255)?;
        }
        travelled += f64::from(length(sub(points[index + 1], points[index])));
    }
    Ok(())
}

fn grass(stroke: &Stroked<'_>, from: usize, out: &mut Marks) -> Result<(), i32> {
    let spacing = (stroke.width * 0.35).max(1.0);
    let mut blades = Vec::new();
    steps(stroke, spacing, from, |rank, at, _direction, radius| {
        let mut draw = Draw::at(stroke.seed, rank, 17);
        let height = radius * 2.0 * draw.between(0.9, 1.8);
        let base = (radius * 0.36).max(0.5);
        let lean = draw.between(-0.45, 0.45);
        let bend = draw.between(-0.25, 0.25);
        let foot = add(
            at,
            point_at(draw.between(-0.5, 0.5) * spacing, radius * 0.6),
        );
        // Upwards on the sheet, leaning and bending a little.
        let up = point_at(lean.sin(), -lean.cos());
        let middle = add(
            add(foot, scaled(up, height * 0.55)),
            point_at(bend * height * 0.3, 0.0),
        );
        let tip = add(
            add(foot, scaled(up, height)),
            point_at(bend * height * 0.6, 0.0),
        );
        let side = point_at(base, 0.0);
        let blade = [
            sub(foot, side),
            sub(middle, scaled(side, 0.55)),
            tip,
            add(middle, scaled(side, 0.55)),
            add(foot, side),
        ];
        collect(&mut blades, (draw.below(3), blade))
    })?;
    for (level, amount) in [(0, -0.25), (1, 0.0), (2, 0.22)] {
        let colour = shade(stroke.rgb, amount);
        for (blade_level, blade) in &blades {
            if *blade_level == level {
                out.polygon(blade, colour, 255)?;
            }
        }
    }
    Ok(())
}

fn bricks(stroke: &Stroked<'_>, from: usize, out: &mut Marks) -> Result<(), i32> {
    // A wall drawn in the sheet, uncovered where the brush passes: bricks of
    // one width high and two long, every other row shifted by half a brick.
    let high = stroke.width.max(2.0);
    let long = high * 2.0;
    let mortar = (high * 0.08).max(0.5);
    let mut seen = std::collections::BTreeSet::new();
    let mut found = Vec::new();
    steps(stroke, high / 3.0, from, |_rank, at, _direction, radius| {
        let rows =
            ((at.y - radius) / high).floor() as i64..=((at.y + radius) / high).floor() as i64;
        for row in rows {
            let shift = if row.rem_euclid(2) == 1 {
                long / 2.0
            } else {
                0.0
            };
            let columns = ((at.x - radius - shift) / long).floor() as i64
                ..=((at.x + radius - shift) / long).floor() as i64;
            for column in columns {
                let left = column as f32 * long + shift;
                let top = row as f32 * high;
                // The brick is laid when the brush touches it.
                let nearest = point_at(at.x.clamp(left, left + long), at.y.clamp(top, top + high));
                if length(sub(nearest, at)) <= radius && seen.insert((row, column)) {
                    found.push((row, column, left, top));
                }
            }
        }
        Ok(seen.len() < 200_000)
    })?;
    for level in 0..3u64 {
        let amount = [-0.18, 0.0, 0.15][level as usize];
        let colour = shade(stroke.rgb, amount);
        for &(row, column, left, top) in &found {
            let mut draw = Draw::at(0, (row as u64) << 32 ^ (column as u64 & 0xffff_ffff), 18);
            if u64::from(draw.below(3)) != level {
                continue;
            }
            let (l, t) = (left + mortar / 2.0, top + mortar / 2.0);
            let (r, b) = (left + long - mortar / 2.0, top + high - mortar / 2.0);
            out.polygon(
                &[
                    point_at(l, t),
                    point_at(r, t),
                    point_at(r, b),
                    point_at(l, b),
                ],
                colour,
                255,
            )?;
        }
    }
    Ok(())
}

/// The colours of the confetti, whatever colour the brush has.
const CONFETTI: [u32; 8] = [
    0x00e5_3935,
    0x00fb_8c00,
    0x00fd_d835,
    0x0043_a047,
    0x0019_76d2,
    0x008e_24aa,
    0x00ec_407a,
    0x0000_acc1,
];

fn confetti(stroke: &Stroked<'_>, from: usize, out: &mut Marks) -> Result<(), i32> {
    let spacing = (stroke.width * 0.6).max(2.0);
    let mut pieces = Vec::new();
    steps(stroke, spacing, from, |rank, at, _direction, radius| {
        let mut draw = Draw::at(stroke.seed, rank, 19);
        for _ in 0..2 {
            let distance = radius * 1.4 * draw.unit().sqrt();
            let angle = draw.unit() * std::f32::consts::TAU;
            let centre = add(at, point_at(distance * angle.cos(), distance * angle.sin()));
            let size = stroke.width.max(2.0) * draw.between(0.12, 0.26);
            let turn = draw.unit() * std::f32::consts::PI;
            let colour = CONFETTI[draw.below(CONFETTI.len() as u32) as usize];
            let shape = draw.below(4);
            if !collect(&mut pieces, (colour, shape, centre, size, turn))? {
                return Ok(false);
            }
        }
        Ok(true)
    })?;
    for colour in CONFETTI {
        for &(piece_colour, shape, centre, size, turn) in &pieces {
            if piece_colour != colour {
                continue;
            }
            let (s, c) = turn.sin_cos();
            let corner = |x: f32, y: f32| add(centre, point_at(x * c - y * s, x * s + y * c));
            match shape {
                0 => out.circle(centre, size * 0.55, colour, 255)?,
                1 => out.polygon(
                    &[
                        corner(-size, -size * 0.45),
                        corner(size, -size * 0.45),
                        corner(size, size * 0.45),
                        corner(-size, size * 0.45),
                    ],
                    colour,
                    255,
                )?,
                2 => out.polygon(
                    &[
                        corner(0.0, -size),
                        corner(size * 0.87, size * 0.5),
                        corner(-size * 0.87, size * 0.5),
                    ],
                    colour,
                    255,
                )?,
                _ => out.polygon(
                    &[
                        corner(-size * 0.6, -size * 0.6),
                        corner(size * 0.6, -size * 0.6),
                        corner(size * 0.6, size * 0.6),
                        corner(-size * 0.6, size * 0.6),
                    ],
                    colour,
                    255,
                )?,
            }
        }
    }
    Ok(())
}

/// Adds to `out` the marks of `stroke` from its segment `from` on (0 for the
/// whole stroke). Nothing for a stroke painted the classic way.
pub(crate) fn compute(stroke: &Stroked<'_>, from: usize, out: &mut Marks) -> Result<(), i32> {
    if stroke.points.is_empty() || !has_marks(stroke.tool, !stroke.pressures.is_empty()) {
        return Ok(());
    }
    match stroke.tool {
        TOOL_ROUND => pressed(stroke, from, out),
        TOOL_CALLIGRAPHY => calligraphy(stroke, from, out),
        TOOL_CHALK => chalk(stroke, from, out),
        TOOL_AIRBRUSH => airbrush(stroke, from, out),
        TOOL_RAINBOW => rainbow(stroke, from, out),
        TOOL_GRASS => grass(stroke, from, out),
        TOOL_BRICKS => bricks(stroke, from, out),
        TOOL_CONFETTI => confetti(stroke, from, out),
        _ => Ok(()),
    }
}

/// The marks of an object of the document, from its visible points.
pub(crate) fn of_object(stroke: &Stroke) -> Result<Marks, i32> {
    let mut out = Marks::new();
    if stroke.style.kind != 0 {
        return Ok(out);
    }
    let mut points = Vec::new();
    points
        .try_reserve_exact(stroke.points.len())
        .map_err(|_| ALLOCATION_FAILURE)?;
    points.extend((0..stroke.points.len()).map(|index| stroke.point_at(index)));
    compute(
        &Stroked {
            points: &points,
            pressures: &stroke.extras.pressures,
            width: stroke.width,
            rgb: stroke.rgb,
            tool: stroke.extras.look.tool,
            seed: stroke.extras.look.seed,
        },
        0,
        &mut out,
    )?;
    Ok(out)
}

// ---------------------------------------------------------------- C contract

/// The number of marks of the object at `index`, and of their points in
/// `out_point_count` (optional): 0 for an object painted as before 1.1 — any
/// kind but a freehand stroke, a round stroke without pressures, a felt one —
/// for NULL and for an index outside the drawing. -1 is never returned: an
/// object whose marks cannot be made for lack of memory says 0.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently mutated;
/// non-null `out_point_count` must be writable and aligned.
#[no_mangle]
pub unsafe extern "C" fn ep_object_mark_count(
    document: *const EpDocument,
    index: usize,
    out_point_count: *mut usize,
) -> usize {
    let marks = unsafe { document.as_ref() }
        .and_then(|doc| doc.strokes.get(index))
        .and_then(|stroke| of_object(stroke).ok());
    let (marks, points) = marks.map_or((0, 0), |m| (m.marks.len(), m.points.len()));
    if !out_point_count.is_null() {
        unsafe { out_point_count.write(points) };
    }
    marks
}

/// Copies the marks of the object at `index` and their points. Returns 0, -1
/// for NULL, an index outside the drawing or capacities below the counts of
/// ep_object_mark_count (nothing is written then), -2 when memory is missing.
///
/// # Safety
/// As ep_object_mark_count; non-null outputs must be writable for their
/// capacities, aligned and disjoint from the document and from each other.
#[no_mangle]
pub unsafe extern "C" fn ep_copy_object_marks(
    document: *const EpDocument,
    index: usize,
    out_marks: *mut EpMark,
    mark_capacity: usize,
    out_points: *mut EpPoint,
    point_capacity: usize,
) -> i32 {
    let Some(stroke) = (unsafe { document.as_ref() }).and_then(|doc| doc.strokes.get(index)) else {
        return INVALID;
    };
    let marks = match of_object(stroke) {
        Ok(marks) => marks,
        Err(status) => return status,
    };
    unsafe { copy_out(&marks, out_marks, mark_capacity, out_points, point_capacity) }
}

unsafe fn copy_out(
    marks: &Marks,
    out_marks: *mut EpMark,
    mark_capacity: usize,
    out_points: *mut EpPoint,
    point_capacity: usize,
) -> i32 {
    if mark_capacity < marks.marks.len()
        || point_capacity < marks.points.len()
        || (!marks.marks.is_empty() && out_marks.is_null())
        || (!marks.points.is_empty() && out_points.is_null())
    {
        return INVALID;
    }
    if !marks.marks.is_empty() {
        unsafe { slice::from_raw_parts_mut(out_marks, marks.marks.len()) }
            .copy_from_slice(&marks.marks);
    }
    if !marks.points.is_empty() {
        unsafe { slice::from_raw_parts_mut(out_points, marks.points.len()) }
            .copy_from_slice(&marks.points);
    }
    0
}

/// The marks of a stroke being drawn, from its segment `from` on: what the
/// object will show once added, its first marks unchanged as it grows.
/// `pressures` is NULL or `count` bytes. Writes the marks and their points
/// when they fit and returns 0; otherwise writes nothing and returns -1, with
/// the counts needed in `out_mark_count` and `out_point_count` (both always
/// written when non-null). -1 also for NULL points or an unknown tool; -2
/// when memory is missing.
///
/// # Safety
/// `points` must address `count` initialized points, `pressures` NULL or
/// `count` bytes, outputs writable for their capacities; all disjoint.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn ep_stroke_marks(
    points: *const EpPoint,
    count: usize,
    pressures: *const u8,
    width: f32,
    rgb: u32,
    tool: u32,
    seed: u32,
    from: usize,
    out_marks: *mut EpMark,
    mark_capacity: usize,
    out_points: *mut EpPoint,
    point_capacity: usize,
    out_mark_count: *mut usize,
    out_point_count: *mut usize,
) -> i32 {
    if points.is_null()
        || !(1..=MAX_STROKE_POINTS).contains(&count)
        || !known_tool(tool)
        || !(0.1..=512.0).contains(&width)
        || rgb > 0x00ff_ffff
    {
        return INVALID;
    }
    let points = unsafe { slice::from_raw_parts(points, count) };
    let pressures: &[u8] = if pressures.is_null() {
        &[]
    } else {
        unsafe { slice::from_raw_parts(pressures, count) }
    };
    let mut marks = Marks::new();
    if let Err(status) = compute(
        &Stroked {
            points,
            pressures,
            width,
            rgb,
            tool,
            seed,
        },
        from,
        &mut marks,
    ) {
        return status;
    }
    if !out_mark_count.is_null() {
        unsafe { out_mark_count.write(marks.marks.len()) };
    }
    if !out_point_count.is_null() {
        unsafe { out_point_count.write(marks.points.len()) };
    }
    unsafe { copy_out(&marks, out_marks, mark_capacity, out_points, point_capacity) }
}

#[cfg(test)]
mod tests;
