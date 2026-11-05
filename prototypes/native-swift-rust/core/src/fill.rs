// SPDX-License-Identifier: MIT
//! The zone the paint pot of Color 1.1 fills: the pixels of a mask of the
//! drawing's ink that a touched point reaches without crossing ink, nor a gap
//! narrower than a disc of the chosen radius — the zone a child closed with
//! a line of her own, small holes included.
//!
//! How it works, step by step (docs/JALON-1.1.md says why this way):
//! 1. a pixel is ink when its byte is 128 or more;
//! 2. every pixel within the radius of the ink, or of the sheet's edge, is
//!    "narrow": a wave leaves the ink and carries from pixel to pixel where
//!    the nearest ink is, nearest pixels first, up to the radius;
//! 3. the zone's wide part is the 4-connected component of pixels that are
//!    not narrow where the touched point is, or else the one it reaches by
//!    the way whose narrowest place is the widest; with no way to any, the
//!    plain flood fill;
//! 4. every pixel of paper goes to the wide part that reaches it by the
//!    widest way, the nearer one on a tie: a watershed from all the wide parts
//!    of the sheet at once, level by level of the distance to the ink. A gap
//!    narrower than the disc is plugged at its narrowest, not crossed; inside
//!    corners and narrow ends go to the only part that reaches them;
//! 5. one more pixel under the ink, so that no white thread shows;
//! 6. its outline: marching squares on the pixel centres, then
//!    Ramer–Douglas–Peucker; an outer ring and the rings of its holes.
//!
//! Nothing here looks for the ends of lines or for gaps between paths: no gap
//! is ever found or drawn. A radius of 0 is the plain flood fill of old.
//!
//! Memory: about a dozen bytes per pixel at most, and nothing that aborts when
//! it is missing.

use super::*;
use std::collections::HashMap;

/// The largest mask: the interface draws a large sheet smaller.
pub(crate) const MAX_MASK_SIDE: u32 = 4096;
pub(crate) const MAX_RADIUS: u32 = 64;

// The flags of a pixel.
const INK: u8 = 1;
/// Within the radius of the ink.
const NARROW: u8 = 2;
/// The wide part of the zone.
const WIDE_ZONE: u8 = 4;
/// In the zone.
const ZONE: u8 = 8;
/// Reached first by the flood of another wide part of the sheet.
const OTHER: u8 = 16;
/// Seen by a search.
const SEEN: u8 = 32;

/// The clearance of a wide pixel.
const WIDE: u8 = u8::MAX;

struct Grid {
    width: usize,
    height: usize,
    cells: Vec<u8>,
}

impl Grid {
    fn neighbours4(&self, index: usize) -> [Option<usize>; 4] {
        let (x, y, w) = (index % self.width, index / self.width, self.width);
        [
            (x > 0).then(|| index - 1),
            (x + 1 < w).then(|| index + 1),
            (y > 0).then(|| index - w),
            (y + 1 < self.height).then(|| index + w),
        ]
    }

    fn clear(&mut self, flags: u8) {
        for cell in &mut self.cells {
            *cell &= !flags;
        }
    }
}

fn reserve<T: Clone>(length: usize, value: T) -> Result<Vec<T>, i32> {
    let mut values = Vec::new();
    values
        .try_reserve_exact(length)
        .map_err(|_| ALLOCATION_FAILURE)?;
    values.resize(length, value);
    Ok(values)
}

/// A push that reports missing memory instead of aborting.
fn push<T>(list: &mut Vec<T>, value: T) -> Result<(), i32> {
    if list.len() == list.capacity() {
        list.try_reserve(list.len().max(256))
            .map_err(|_| ALLOCATION_FAILURE)?;
    }
    list.push(value);
    Ok(())
}

// Step 2: every pixel within `radius` of the ink, or of the sheet's edge (ink
// a pixel beyond each side: a gap between a line and the edge is a gap like
// any other), by a wave that leaves the ink and carries, from pixel to pixel,
// where its nearest ink is; squared distances in increasing order, the wave
// stopping at the radius. Returns the clearance of every pixel: its distance
// to that ink, rounded down, for a narrow one; WIDE for the others.
fn mark_narrow(grid: &mut Grid, radius: usize) -> Result<Vec<u8>, i32> {
    if radius == 0 {
        return Ok(Vec::new());
    }
    let (w, h) = (grid.width as isize, grid.height as isize);
    let reach = radius * radius;
    // The squared distance known, and where that ink is from the pixel.
    let mut known = reserve(grid.cells.len(), u16::MAX)?;
    let mut towards = reserve(grid.cells.len(), (0i8, 0i8))?;
    let mut buckets: Vec<Vec<u32>> = Vec::new();
    buckets
        .try_reserve_exact(reach + 1)
        .map_err(|_| ALLOCATION_FAILURE)?;
    buckets.resize_with(reach + 1, Vec::new);
    for y in 0..h {
        for x in 0..w {
            let index = (y * w + x) as usize;
            if grid.cells[index] & INK != 0 {
                // Ink is its own nearest ink; only ink beside paper moves.
                known[index] = 0;
                let edge = (-1..=1).any(|dy| {
                    (-1..=1).any(|dx| {
                        let (nx, ny) = (x + dx, y + dy);
                        nx >= 0
                            && ny >= 0
                            && nx < w
                            && ny < h
                            && grid.cells[(ny * w + nx) as usize] & INK == 0
                    })
                });
                if edge {
                    push(&mut buckets[0], index as u32)?;
                }
            } else if x == 0 || y == 0 || x == w - 1 || y == h - 1 {
                // The edge's ink, straight across.
                known[index] = 1;
                towards[index] = if x == 0 {
                    (-1, 0)
                } else if x == w - 1 {
                    (1, 0)
                } else if y == 0 {
                    (0, -1)
                } else {
                    (0, 1)
                };
                push(&mut buckets[1], index as u32)?;
            }
        }
    }
    for d in 0..=reach {
        let bucket = std::mem::take(&mut buckets[d]);
        for &index in &bucket {
            let index = index as usize;
            if usize::from(known[index]) != d {
                continue;
            }
            let (x, y) = ((index as isize) % w, (index as isize) / w);
            let (tx, ty) = towards[index];
            let (sx, sy) = (x + isize::from(tx), y + isize::from(ty));
            for dy in -1..=1 {
                for dx in -1..=1 {
                    let (nx, ny) = (x + dx, y + dy);
                    if (dx, dy) == (0, 0) || nx < 0 || ny < 0 || nx >= w || ny >= h {
                        continue;
                    }
                    let n = (ny * w + nx) as usize;
                    let (ox, oy) = (sx - nx, sy - ny);
                    let squared = (ox * ox + oy * oy) as usize;
                    if squared <= reach && squared < usize::from(known[n]) {
                        known[n] = squared as u16;
                        // Within the radius: each offset fits a byte.
                        towards[n] = (ox as i8, oy as i8);
                        push(&mut buckets[squared], n as u32)?;
                    }
                }
            }
        }
    }
    drop(towards);
    let mut clearance = reserve(grid.cells.len(), WIDE)?;
    for (index, &squared) in known.iter().enumerate() {
        if usize::from(squared) <= reach {
            grid.cells[index] |= NARROW;
            // Exact: the square root of a perfect square is.
            clearance[index] = f64::from(squared).sqrt() as u8;
        }
    }
    Ok(clearance)
}

/// Sets `flag` on the 4-connected pixels from `start` whose flags `pass`
/// accepts.
fn flood(grid: &mut Grid, start: usize, flag: u8, pass: impl Fn(u8) -> bool) -> Result<(), i32> {
    let mut stack = Vec::new();
    grid.cells[start] |= flag;
    push(&mut stack, start)?;
    while let Some(index) = stack.pop() {
        for n in grid.neighbours4(index).into_iter().flatten() {
            let cell = grid.cells[n];
            if cell & flag == 0 && pass(cell) {
                grid.cells[n] |= flag;
                push(&mut stack, n)?;
            }
        }
    }
    Ok(())
}

/// Step 3 from a narrow pixel: the wide pixel reached from `start` by the way
/// whose narrowest place is the widest — where the largest disc rolls from
/// the point; None when no way leads to any.
fn widest_way(grid: &Grid, clearance: &[u8], start: usize) -> Result<Option<usize>, i32> {
    let top = usize::from(clearance[start]);
    // One more than the widest narrowest place known on a way to a pixel.
    let mut best = reserve(grid.cells.len(), 0u8)?;
    let mut levels: Vec<Vec<u32>> = Vec::new();
    levels
        .try_reserve_exact(top + 1)
        .map_err(|_| ALLOCATION_FAILURE)?;
    levels.resize_with(top + 1, Vec::new);
    best[start] = top as u8 + 1;
    push(&mut levels[top], start as u32)?;
    for level in (0..=top).rev() {
        while let Some(index) = levels[level].pop() {
            let index = index as usize;
            if usize::from(best[index]) != level + 1 {
                continue;
            }
            for n in grid.neighbours4(index).into_iter().flatten() {
                let cell = grid.cells[n];
                if cell & INK != 0 {
                    continue;
                }
                if cell & NARROW == 0 {
                    return Ok(Some(n));
                }
                let to = level.min(usize::from(clearance[n]));
                if to + 1 > usize::from(best[n]) {
                    best[n] = (to + 1) as u8;
                    push(&mut levels[to], n as u32)?;
                }
            }
        }
    }
    Ok(None)
}

/// The nearest wide pixel of another part from `start`, through the pixels
/// the other parts own.
fn owner_of(grid: &mut Grid, start: usize) -> Result<Option<usize>, i32> {
    let mut queue = Vec::new();
    grid.cells[start] |= SEEN;
    push(&mut queue, start)?;
    let mut head = 0;
    let mut found = None;
    while head < queue.len() {
        let index = queue[head];
        head += 1;
        if grid.cells[index] & NARROW == 0 {
            found = Some(index);
            break;
        }
        for n in grid.neighbours4(index).into_iter().flatten() {
            let cell = grid.cells[n];
            if cell & (INK | SEEN) == 0 && cell & OTHER != 0 {
                grid.cells[n] |= SEEN;
                push(&mut queue, n)?;
            }
        }
    }
    for &index in &queue {
        grid.cells[index] &= !SEEN;
    }
    Ok(found)
}

// Step 4: the watershed. Wide pixels are the level above the radius, a
// narrow one is at its clearance; levels are flooded from the highest down,
// each pixel taken by the first part to reach it, and a pixel reached from a
// higher level waits at its own. Within a level the floods move together, a
// pixel a step: the nearer part wins a tie.
fn share(grid: &mut Grid, clearance: &[u8], radius: usize) -> Result<(), i32> {
    let mut levels: Vec<Vec<u32>> = Vec::new();
    levels
        .try_reserve_exact(radius + 2)
        .map_err(|_| ALLOCATION_FAILURE)?;
    levels.resize_with(radius + 2, Vec::new);
    for index in 0..grid.cells.len() {
        let cell = grid.cells[index];
        if cell & (INK | NARROW) != 0 {
            continue;
        }
        grid.cells[index] |= if cell & WIDE_ZONE != 0 { ZONE } else { OTHER };
        // Only the wide pixels beside a narrow one flood anything.
        let edge = grid
            .neighbours4(index)
            .into_iter()
            .flatten()
            .any(|n| grid.cells[n] & (INK | NARROW) == NARROW);
        if edge {
            push(&mut levels[radius + 1], index as u32)?;
        }
    }
    for level in (0..=radius + 1).rev() {
        let mut head = 0;
        while head < levels[level].len() {
            let index = levels[level][head] as usize;
            head += 1;
            let mine = grid.cells[index] & (ZONE | OTHER);
            for n in grid.neighbours4(index).into_iter().flatten() {
                if grid.cells[n] & (INK | ZONE | OTHER) != 0 {
                    continue;
                }
                grid.cells[n] |= mine;
                let to = level.min(usize::from(clearance[n]));
                push(&mut levels[to], n as u32)?;
            }
        }
        levels[level] = Vec::new();
    }
    Ok(())
}

/// Steps 3 and 4 from the wide pixel `wide`.
fn grow_from(grid: &mut Grid, clearance: &[u8], wide: usize, radius: usize) -> Result<(), i32> {
    flood(grid, wide, WIDE_ZONE, |cell| cell & (INK | NARROW) == 0)?;
    share(grid, clearance, radius)
}

/// Where a segment of the outline starts or ends: the middle of an edge of a
/// square of marching squares.
const TOP: u8 = 0;
const RIGHT: u8 = 1;
const BOTTOM: u8 = 2;
const LEFT: u8 = 3;

/// The segments of each case of marching squares (corners: 8 top-left, 4
/// top-right, 2 bottom-right, 1 bottom-left), the zone on the right of each.
/// At a saddle the two inside corners do not touch: the zone is 4-connected.
const SEGMENTS: [&[(u8, u8)]; 16] = [
    &[],
    &[(LEFT, BOTTOM)],
    &[(BOTTOM, RIGHT)],
    &[(LEFT, RIGHT)],
    &[(RIGHT, TOP)],
    &[(LEFT, BOTTOM), (RIGHT, TOP)],
    &[(BOTTOM, TOP)],
    &[(LEFT, TOP)],
    &[(TOP, LEFT)],
    &[(TOP, BOTTOM)],
    &[(TOP, LEFT), (BOTTOM, RIGHT)],
    &[(TOP, RIGHT)],
    &[(RIGHT, LEFT)],
    &[(RIGHT, BOTTOM)],
    &[(BOTTOM, LEFT)],
    &[],
];

// Step 6: marching squares on the pixel centres; the corner of a square is
// inside when its pixel is in the zone. Segments join into closed rings.
fn outline(grid: &Grid) -> Result<Vec<Vec<EpPoint>>, i32> {
    let (w, h) = (grid.width as isize, grid.height as isize);
    let inside = |x: isize, y: isize| {
        x >= 0 && y >= 0 && x < w && y < h && grid.cells[(y * w + x) as usize] & ZONE != 0
    };
    // Squares run one beyond each side so that every ring closes.
    let case = |x: isize, y: isize| {
        (usize::from(inside(x, y)) << 3)
            | (usize::from(inside(x + 1, y)) << 2)
            | (usize::from(inside(x + 1, y + 1)) << 1)
            | usize::from(inside(x, y + 1))
    };
    let mut count = 0usize;
    for y in -1..h {
        for x in -1..w {
            count += SEGMENTS[case(x, y)].len();
        }
    }
    // Points in half pixels: the centre of pixel (x, y) is (2x + 1, 2y + 1).
    let mut next: HashMap<(i64, i64), (i64, i64)> = HashMap::new();
    next.try_reserve(count).map_err(|_| ALLOCATION_FAILURE)?;
    for y in -1..h {
        for x in -1..w {
            let (cx, cy) = (2 * x as i64 + 1, 2 * y as i64 + 1);
            let middle = |edge: u8| match edge {
                TOP => (cx + 1, cy),
                RIGHT => (cx + 2, cy + 1),
                BOTTOM => (cx + 1, cy + 2),
                _ => (cx, cy + 1),
            };
            for &(from, to) in SEGMENTS[case(x, y)] {
                next.insert(middle(from), middle(to));
            }
        }
    }
    let mut starts: Vec<(i64, i64)> = Vec::new();
    starts
        .try_reserve_exact(next.len())
        .map_err(|_| ALLOCATION_FAILURE)?;
    starts.extend(next.keys().copied());
    starts.sort_unstable();
    let mut rings = Vec::new();
    for start in starts {
        if !next.contains_key(&start) {
            continue;
        }
        let mut ring = Vec::new();
        let mut at = start;
        while let Some(to) = next.remove(&at) {
            push(
                &mut ring,
                EpPoint {
                    x: at.0 as f32 / 2.0,
                    y: at.1 as f32 / 2.0,
                },
            )?;
            at = to;
            if at == start {
                break;
            }
        }
        if ring.len() >= 3 {
            push(&mut rings, ring)?;
        }
    }
    Ok(rings)
}

/// Ramer–Douglas–Peucker on a closed ring, cut at the point farthest from its
/// first; without recursion, as a ring can be long.
fn simplified(ring: &[EpPoint], tolerance: f32) -> Result<Vec<EpPoint>, i32> {
    let n = ring.len();
    let gap = |a: EpPoint, b: EpPoint| (a.x - b.x).hypot(a.y - b.y);
    let far = (1..n)
        .max_by(|&a, &b| gap(ring[a], ring[0]).total_cmp(&gap(ring[b], ring[0])))
        .unwrap_or(0);
    let mut out = Vec::new();
    if far == 0 {
        out.try_reserve_exact(n).map_err(|_| ALLOCATION_FAILURE)?;
        out.extend_from_slice(ring);
        return Ok(out);
    }
    // Index n is the first point again, closing the ring.
    let at = |i: usize| ring[i % n];
    let mut kept = reserve(n, false)?;
    kept[0] = true;
    kept[far] = true;
    let mut stack = Vec::new();
    push(&mut stack, (0, far))?;
    push(&mut stack, (far, n))?;
    while let Some((first, last)) = stack.pop() {
        let (a, b) = (at(first), at(last));
        let (dx, dy) = (b.x - a.x, b.y - a.y);
        let length = dx.hypot(dy);
        let mut farthest = (0.0f32, first);
        for index in first + 1..last {
            let p = at(index);
            let distance = if length == 0.0 {
                gap(p, a)
            } else {
                ((p.x - a.x) * dy - (p.y - a.y) * dx).abs() / length
            };
            if distance > farthest.0 {
                farthest = (distance, index);
            }
        }
        if farthest.0 > tolerance {
            kept[farthest.1] = true;
            push(&mut stack, (first, farthest.1))?;
            push(&mut stack, (farthest.1, last))?;
        }
    }
    for (index, &keep) in kept.iter().enumerate() {
        if keep {
            push(&mut out, ring[index])?;
        }
    }
    Ok(out)
}

/// What `zone` found.
pub(crate) enum Zone {
    /// The touched point is ink.
    OnInk,
    /// The zone is all the paper of the sheet: no line closes anything, the
    /// sheet's own colour changes.
    WholeSheet,
    /// The rings of the zone's outline, in pixel coordinates.
    Rings(Vec<Vec<EpPoint>>),
}

pub(crate) fn zone(
    mask: &[u8],
    width: u32,
    height: u32,
    x: u32,
    y: u32,
    radius: u32,
) -> Result<Zone, i32> {
    let (w, h) = (width as usize, height as usize);
    let mut cells = reserve(w * h, 0u8)?;
    let mut paper = 0usize;
    for (cell, &byte) in cells.iter_mut().zip(mask) {
        if byte >= 128 {
            *cell = INK;
        } else {
            paper += 1;
        }
    }
    let mut grid = Grid {
        width: w,
        height: h,
        cells,
    };
    let start = y as usize * w + x as usize;
    if grid.cells[start] & INK != 0 {
        return Ok(Zone::OnInk);
    }
    if paper == grid.cells.len() {
        return Ok(Zone::WholeSheet);
    }
    let radius = radius as usize;
    let clearance = mark_narrow(&mut grid, radius)?;
    let wide = if radius == 0 {
        None
    } else if grid.cells[start] & NARROW == 0 {
        Some(start)
    } else {
        widest_way(&grid, &clearance, start)?
    };
    match wide {
        Some(wide) => {
            grow_from(&mut grid, &clearance, wide, radius)?;
            if grid.cells[start] & OTHER != 0 {
                // Another part reached the point first, on a tie of the
                // widest ways: that part is the zone.
                if let Some(owner) = owner_of(&mut grid, start)? {
                    grid.clear(WIDE_ZONE | ZONE | OTHER);
                    grow_from(&mut grid, &clearance, owner, radius)?;
                }
            }
            // At the very middle of a plugged gap: the point itself at least.
            grid.cells[start] = (grid.cells[start] & !OTHER) | ZONE;
        }
        // No room for the disc anywhere the point reaches, or no disc: the
        // plain flood fill, stopped by ink only.
        None => flood(&mut grid, start, ZONE, |cell| cell & INK == 0)?,
    }
    drop(clearance);
    let filled = grid.cells.iter().filter(|&&cell| cell & ZONE != 0).count();
    if filled == paper {
        return Ok(Zone::WholeSheet);
    }
    // Step 5: one pixel under the ink.
    let mut under = Vec::new();
    for index in 0..grid.cells.len() {
        if grid.cells[index] & INK != 0
            && grid
                .neighbours4(index)
                .into_iter()
                .flatten()
                .any(|n| grid.cells[n] & ZONE != 0)
        {
            push(&mut under, index)?;
        }
    }
    for index in under {
        grid.cells[index] |= ZONE;
    }
    let rings = outline(&grid)?;
    // Simplified, more if the outline would hold too many points.
    let mut tolerance = 0.35;
    loop {
        let mut candidate = Vec::new();
        for ring in &rings {
            let ring = simplified(ring, tolerance)?;
            if ring.len() >= 3 {
                push(&mut candidate, ring)?;
            }
        }
        let points: usize = candidate.iter().map(Vec::len).sum();
        if !candidate.is_empty() && points <= MAX_STROKE_POINTS && candidate.len() <= MAX_RINGS {
            return Ok(Zone::Rings(candidate));
        }
        if candidate.is_empty() || tolerance > 8.0 {
            return Err(INVALID);
        }
        tolerance *= 2.0;
    }
}

/// The zone the paint pot fills from pixel (`x`, `y`) of `mask`, a width ×
/// height image of the drawing's ink, one byte per pixel (ink at 128 or
/// more), `radius` 0 to 64 pixels: the narrowest gap it does not cross is
/// twice that (0: only ink stops it). Writes its outline: the points of its
/// rings, in pixel coordinates (0, 0 the top-left corner of the mask, a
/// pixel's centre at x + 0.5), and the point count of each ring, the outer
/// one and those of its holes (even-odd).
/// Returns 1 with the outline written; 0 when the point is on ink; 2 when
/// the zone is all the paper of the sheet, no line closing anything (the
/// sheet's own colour is what to change); -1 for an invalid request or
/// capacities below the counts — written to the non-NULL count outputs
/// whenever there is an outline; -2 when memory is missing.
///
/// # Safety
/// `mask` must address width × height initialized bytes; outputs must be
/// writable for their capacities; all disjoint.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn ep_fill_zone(
    mask: *const u8,
    width: u32,
    height: u32,
    x: u32,
    y: u32,
    radius: u32,
    out_points: *mut EpPoint,
    point_capacity: usize,
    out_rings: *mut u32,
    ring_capacity: usize,
    out_point_count: *mut usize,
    out_ring_count: *mut usize,
) -> i32 {
    if mask.is_null()
        || !(1..=MAX_MASK_SIDE).contains(&width)
        || !(1..=MAX_MASK_SIDE).contains(&height)
        || x >= width
        || y >= height
        || radius > MAX_RADIUS
    {
        return INVALID;
    }
    let mask = unsafe { slice::from_raw_parts(mask, width as usize * height as usize) };
    let rings = match zone(mask, width, height, x, y, radius) {
        Ok(Zone::OnInk) => return 0,
        Ok(Zone::WholeSheet) => return 2,
        Ok(Zone::Rings(rings)) => rings,
        Err(status) => return status,
    };
    let points: usize = rings.iter().map(Vec::len).sum();
    if !out_point_count.is_null() {
        unsafe { out_point_count.write(points) };
    }
    if !out_ring_count.is_null() {
        unsafe { out_ring_count.write(rings.len()) };
    }
    if out_points.is_null()
        || out_rings.is_null()
        || point_capacity < points
        || ring_capacity < rings.len()
    {
        return INVALID;
    }
    let out_points = unsafe { slice::from_raw_parts_mut(out_points, points) };
    let out_rings = unsafe { slice::from_raw_parts_mut(out_rings, rings.len()) };
    let mut cursor = 0;
    for (ring, count) in rings.iter().zip(out_rings.iter_mut()) {
        out_points[cursor..cursor + ring.len()].copy_from_slice(ring);
        cursor += ring.len();
        *count = ring.len() as u32;
    }
    1
}

#[cfg(test)]
mod tests;
