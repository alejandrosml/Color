// SPDX-License-Identifier: MIT
//! The eraser of Color 1.1, which cuts strokes: where it passes, the line of a
//! freehand stroke, of a line, of a hollow rectangle or ellipse goes, and what
//! is left of it stays as pieces; the objects the interface names are removed
//! whole, as the eraser always did. One rub is one command: the changes of
//! the calls of one gesture join the same batch, undone in one step.
//!
//! The pieces of a turned or mirrored object carry the turn in their points:
//! they no longer turn about the centre of a box that each piece would have
//! for itself. A hollow rectangle or ellipse becomes the freehand strokes of
//! its outline.

use super::*;

/// What a command of the eraser is, for merging the next call into it.
const ERASER_BATCH: u8 = 1;

/// The most pieces one call may make; beyond, it refuses rather than grow.
const MAX_PIECES: usize = 4096;

fn distance_to_segment(p: EpPoint, a: EpPoint, b: EpPoint) -> f64 {
    let (px, py) = (f64::from(p.x), f64::from(p.y));
    let (ax, ay) = (f64::from(a.x), f64::from(a.y));
    let (bx, by) = (f64::from(b.x), f64::from(b.y));
    let (dx, dy) = (bx - ax, by - ay);
    let length = dx * dx + dy * dy;
    let t = if length == 0.0 {
        0.0
    } else {
        (((px - ax) * dx + (py - ay) * dy) / length).clamp(0.0, 1.0)
    };
    (px - (ax + t * dx)).hypot(py - (ay + t * dy))
}

fn lerp(a: EpPoint, b: EpPoint, t: f64) -> EpPoint {
    EpPoint {
        x: (f64::from(a.x) + (f64::from(b.x) - f64::from(a.x)) * t) as f32,
        y: (f64::from(a.y) + (f64::from(b.y) - f64::from(a.y)) * t) as f32,
    }
}

/// The part of the segment from `a` to `b`, as an interval of its parameter,
/// whose points lie within `reach` of the segment from `e0` to `e1`. The
/// distance from a point moving along a segment to another segment is convex,
/// so that part is one interval; its ends are found by halving.
fn erased_interval(
    a: EpPoint,
    b: EpPoint,
    e0: EpPoint,
    e1: EpPoint,
    reach: f64,
) -> Option<(f64, f64)> {
    let at = |t: f64| distance_to_segment(lerp(a, b, t), e0, e1);
    // The nearest point, by golden-section search on the convex distance.
    let (mut low, mut high) = (0.0f64, 1.0f64);
    let ratio = 0.618_033_988_749_894_9;
    for _ in 0..60 {
        let m1 = high - ratio * (high - low);
        let m2 = low + ratio * (high - low);
        if at(m1) <= at(m2) {
            high = m2;
        } else {
            low = m1;
        }
    }
    let nearest = (low + high) / 2.0;
    if at(nearest) > reach {
        return None;
    }
    let edge = |mut inside: f64, mut outside: f64| {
        if at(outside) <= reach {
            return outside;
        }
        for _ in 0..50 {
            let middle = (inside + outside) / 2.0;
            if at(middle) <= reach {
                inside = middle;
            } else {
                outside = middle;
            }
        }
        inside
    };
    Some((edge(nearest, 0.0), edge(nearest, 1.0)))
}

/// The intervals of one segment of the line that the eraser takes, merged.
fn erased_on_segment(a: EpPoint, b: EpPoint, path: &[EpPoint], reach: f64) -> Vec<(f64, f64)> {
    let mut found = Vec::new();
    let pairs: Vec<(EpPoint, EpPoint)> = if path.len() == 1 {
        vec![(path[0], path[0])]
    } else {
        path.windows(2).map(|w| (w[0], w[1])).collect()
    };
    let (low_x, high_x) = (a.x.min(b.x) as f64 - reach, a.x.max(b.x) as f64 + reach);
    let (low_y, high_y) = (a.y.min(b.y) as f64 - reach, a.y.max(b.y) as f64 + reach);
    for (e0, e1) in pairs {
        // Far apart: nothing to search.
        if (e0.x.max(e1.x) as f64) < low_x
            || (e0.x.min(e1.x) as f64) > high_x
            || (e0.y.max(e1.y) as f64) < low_y
            || (e0.y.min(e1.y) as f64) > high_y
        {
            continue;
        }
        if let Some(interval) = erased_interval(a, b, e0, e1, reach) {
            found.push(interval);
        }
    }
    found.sort_by(|x, y| x.0.total_cmp(&y.0));
    let mut merged: Vec<(f64, f64)> = Vec::new();
    for (start, end) in found {
        match merged.last_mut() {
            Some(last) if start <= last.1 => last.1 = last.1.max(end),
            _ => merged.push((start, end)),
        }
    }
    merged
}

/// One piece of a cut line: its points and, for a pressed stroke, theirs.
struct Piece {
    points: Vec<EpPoint>,
    pressures: Vec<u8>,
}

/// The pieces left of a polyline once the eraser has passed: None when it
/// was not touched.
fn cut_polyline(
    points: &[EpPoint],
    pressures: &[u8],
    path: &[EpPoint],
    reach: f64,
) -> Option<Vec<Piece>> {
    if points.len() == 1 {
        let gone = path
            .windows(2)
            .any(|w| distance_to_segment(points[0], w[0], w[1]) <= reach)
            || (path.len() == 1 && distance_to_segment(points[0], path[0], path[0]) <= reach);
        return gone.then(Vec::new);
    }
    let pressure_at = |index: usize, t: f64| -> u8 {
        if pressures.is_empty() {
            return 0;
        }
        let (a, b) = (f64::from(pressures[index]), f64::from(pressures[index + 1]));
        (a + (b - a) * t).round().clamp(1.0, 255.0) as u8
    };
    let mut touched = false;
    let mut pieces = Vec::new();
    let mut current: Option<Piece> = Some(Piece {
        points: vec![points[0]],
        pressures: pressures.first().map(|&p| vec![p]).unwrap_or_default(),
    });
    for index in 0..points.len() - 1 {
        let (a, b) = (points[index], points[index + 1]);
        let erased = erased_on_segment(a, b, path, reach);
        if erased.is_empty() {
            if let Some(piece) = &mut current {
                piece.points.push(b);
                if !pressures.is_empty() {
                    piece.pressures.push(pressures[index + 1]);
                }
            }
            continue;
        }
        touched = true;
        let mut kept_from = 0.0f64;
        for (start, end) in erased {
            if start > kept_from {
                // The line runs from where it was kept to where it is erased.
                let piece = current.get_or_insert_with(|| Piece {
                    points: vec![lerp(a, b, kept_from)],
                    pressures: if pressures.is_empty() {
                        Vec::new()
                    } else {
                        vec![pressure_at(index, kept_from)]
                    },
                });
                piece.points.push(lerp(a, b, start));
                if !pressures.is_empty() {
                    piece.pressures.push(pressure_at(index, start));
                }
            }
            if let Some(piece) = current.take() {
                pieces.push(piece);
            }
            kept_from = end;
        }
        if kept_from < 1.0 {
            let mut piece = Piece {
                points: vec![lerp(a, b, kept_from), b],
                pressures: Vec::new(),
            };
            if !pressures.is_empty() {
                piece.pressures = vec![pressure_at(index, kept_from), pressures[index + 1]];
            }
            current = Some(piece);
        }
    }
    if !touched {
        return None;
    }
    if let Some(piece) = current {
        pieces.push(piece);
    }
    // A piece reduced to nothing — a point, or points all in one place — goes.
    pieces.retain(|piece| piece.points.len() >= 2 && piece.points.windows(2).any(|w| w[0] != w[1]));
    Some(pieces)
}

/// The line of an object as the eraser sees it: the visible points, turned and
/// mirrored as the sheet shows them; the outline of a hollow box or of a
/// hollow contour of one ring (a star, a heart…), closed.
fn line_of(stroke: &Stroke) -> Option<Vec<EpPoint>> {
    let mut points: Vec<EpPoint> = match stroke.style.kind {
        0 | 1 => (0..stroke.points.len())
            .map(|i| stroke.point_at(i))
            .collect(),
        KIND_CONTOUR if stroke.style.fill_enabled == 0 && stroke.extras.rings.is_empty() => {
            let mut outline: Vec<EpPoint> = (0..stroke.points.len())
                .map(|i| stroke.point_at(i))
                .collect();
            outline.push(outline[0]);
            outline
        }
        2 | 3 if stroke.style.fill_enabled == 0 => {
            let (a, b) = (stroke.point_at(0), stroke.point_at(1));
            let (low, high) = (
                EpPoint {
                    x: a.x.min(b.x),
                    y: a.y.min(b.y),
                },
                EpPoint {
                    x: a.x.max(b.x),
                    y: a.y.max(b.y),
                },
            );
            if stroke.style.kind == 2 {
                vec![
                    low,
                    EpPoint {
                        x: high.x,
                        y: low.y,
                    },
                    high,
                    EpPoint {
                        x: low.x,
                        y: high.y,
                    },
                    low,
                ]
            } else {
                let (cx, cy) = ((low.x + high.x) / 2.0, (low.y + high.y) / 2.0);
                let (rx, ry) = ((high.x - low.x) / 2.0, (high.y - low.y) / 2.0);
                // Enough sides that the polygon stays within a tenth of a unit.
                let sides = ((std::f32::consts::PI / (1.0 - 0.1 / rx.max(ry).max(0.2)).acos())
                    .ceil() as usize)
                    .clamp(16, 720);
                (0..=sides)
                    .map(|i| {
                        let angle = std::f32::consts::TAU * i as f32 / sides as f32;
                        EpPoint {
                            x: cx + rx * angle.cos(),
                            y: cy + ry * angle.sin(),
                        }
                    })
                    .collect()
            }
        }
        _ => return None,
    };
    let look = stroke.extras.look;
    if look.rotation != 0.0 || look.mirror != 0 {
        let (low, high) = visible_box(stroke);
        let (cx, cy) = (
            (f64::from(low.x) + f64::from(high.x)) / 2.0,
            (f64::from(low.y) + f64::from(high.y)) / 2.0,
        );
        let (sin, cos) = f64::from(look.rotation).sin_cos();
        let (sx, sy) = (
            if look.mirror & 1 != 0 { -1.0 } else { 1.0 },
            if look.mirror & 2 != 0 { -1.0 } else { 1.0 },
        );
        for point in &mut points {
            let x = (f64::from(point.x) - cx) * sx;
            let y = (f64::from(point.y) - cy) * sy;
            point.x = (cx + x * cos - y * sin) as f32;
            point.y = (cy + x * sin + y * cos) as f32;
        }
    }
    Some(points)
}

/// What one object becomes: removed whole, or replaced by its pieces.
enum Change {
    Remove(usize),
    Cut(usize, Vec<Stroke>),
}

// The pieces of the object at `index` as new objects, or None when the eraser
// does not reach its line. Coordinates leave the sheet only if a turned
// object did; they are brought back onto it, as the sheet clips it.
fn pieces_of(
    doc: &EpDocument,
    index: usize,
    path: &[EpPoint],
    radius: f64,
) -> Result<Option<Vec<Stroke>>, i32> {
    let stroke = &doc.strokes[index];
    let Some(line) = line_of(stroke) else {
        return Ok(None);
    };
    let reach = radius + f64::from(stroke.width) / 4.0;
    // A freehand stroke keeps a pressure for each of its points, turned or
    // not; the outline of a box has none.
    let pressures: &[u8] = if stroke.style.kind == 0 {
        &stroke.extras.pressures
    } else {
        &[]
    };
    let Some(mut pieces) = cut_polyline(&line, pressures, path, reach) else {
        return Ok(None);
    };
    // The outline of a box is a loop: what is kept on both sides of its
    // starting corner is one piece.
    let closed = line.len() > 2 && line.first() == line.last();
    if closed
        && pieces.len() >= 2
        && pieces[0].points.first() == line.first()
        && pieces[pieces.len() - 1].points.last() == line.last()
    {
        let first = pieces.remove(0);
        let last = pieces.last_mut().expect("two pieces or more");
        last.points.extend_from_slice(&first.points[1..]);
        if !last.pressures.is_empty() {
            last.pressures.extend_from_slice(&first.pressures[1..]);
        }
    }
    let quant = stroke.extras.quant;
    let (width, height) = (doc.width as f32, doc.height as f32);
    let mut made = Vec::new();
    made.try_reserve(pieces.len())
        .map_err(|_| ALLOCATION_FAILURE)?;
    for piece in pieces {
        let points: Vec<EpPoint> = piece
            .points
            .iter()
            .map(|p| EpPoint {
                x: quantized(p.x.clamp(0.0, width), quant),
                y: quantized(p.y.clamp(0.0, height), quant),
            })
            .collect();
        let kind = if stroke.style.kind == 1 { 1 } else { 0 };
        if kind == 1 && points.len() != 2 {
            continue;
        }
        if !points.windows(2).any(|w| w[0] != w[1]) {
            continue;
        }
        // The outline of a loop of the largest contour, with its point of
        // return, would make a stroke longer than a stroke may be, which no
        // reader would take back: such an object is left whole.
        if points.len() > MAX_STROKE_POINTS {
            return Ok(None);
        }
        // A cut line stays a line; everything else becomes a freehand stroke
        // of the same colour, width, tool and seed — but for a tool that no
        // freehand stroke has, the zone of the paint pot: its outline becomes
        // a plain one, as a file must be able to say it again.
        let mut look = EpObjectLook {
            rotation: 0.0,
            mirror: 0,
            gradient: 0,
            gradient_rgb: 0,
            gradient_points: [0.0; 4],
            ..stroke.extras.look
        };
        if kind == 0 && !valid_look(0, 0, &look) {
            look.tool = TOOL_ROUND;
            look.seed = 0;
        }
        made.push(Stroke {
            points,
            rgb: stroke.rgb,
            width: stroke.width,
            style: EpObjectStyle {
                kind,
                fill_enabled: 0,
                fill_rgb: 0,
            },
            scale: 1.0,
            translation: [0.0; 2],
            revision: 0,
            layer: stroke.layer,
            param: 0,
            text: Vec::new(),
            extras: Extras {
                look: if kind == 0 { look } else { PLAIN_LOOK },
                pressures: piece.pressures,
                rings: Vec::new(),
                quant,
            },
        });
    }
    Ok(Some(made))
}

/// One rub of the eraser: cuts the line of the objects of `cut` that it
/// reaches along `path` (centres of the eraser, `radius` in units of the
/// sheet), and removes the objects of `removed` whole. Indices are those of
/// the drawing before the call; an index of a locked or hidden layer, or out
/// of the drawing, is refused. With `merge` 1 the changes join the last
/// command when it is a rub of the eraser and nothing was undone since: the
/// interface passes 1 for every call of a gesture after the first. Returns
/// the number of objects changed (0: the eraser touched nothing), -1 for
/// invalid arguments or limits, -2 when memory is missing; on error nothing
/// changes.
///
/// # Safety
/// Non-null `document` must be live, aligned and exclusively accessible;
/// `path` must address `count` points, `cut` and `removed` (NULL when their
/// count is 0) their counts of indices; all initialized, disjoint from the
/// document and unchanged during the call.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn ep_erase(
    document: *mut EpDocument,
    path: *const EpPoint,
    count: usize,
    radius: f32,
    cut: *const usize,
    cut_count: usize,
    removed: *const usize,
    removed_count: usize,
    merge: u32,
) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    if path.is_null()
        || !(1..=MAX_STROKE_POINTS).contains(&count)
        || !(radius.is_finite() && radius > 0.0 && radius <= 4096.0)
        || merge > 1
        || (cut_count != 0 && cut.is_null())
        || (removed_count != 0 && removed.is_null())
        || cut_count > MAX_STROKES
        || removed_count > MAX_STROKES
    {
        return INVALID;
    }
    let path = unsafe { slice::from_raw_parts(path, count) };
    if !path.iter().all(|p| p.x.is_finite() && p.y.is_finite()) {
        return INVALID;
    }
    let cut: &[usize] = if cut_count == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(cut, cut_count) }
    };
    let removed: &[usize] = if removed_count == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(removed, removed_count) }
    };
    let reachable = |index: usize| {
        doc.strokes.get(index).is_some_and(|stroke| {
            !doc.locked(stroke.layer)
                && doc
                    .layers()
                    .iter()
                    .any(|layer| layer.id == stroke.layer && layer.visible)
        })
    };
    if !cut.iter().chain(removed).all(|&index| reachable(index)) {
        return INVALID;
    }
    // Each object once, the highest index first: changing one never moves
    // an index still to come.
    let mut targets: Vec<(usize, bool)> = Vec::new();
    if targets.try_reserve(cut.len() + removed.len()).is_err() {
        return ALLOCATION_FAILURE;
    }
    targets.extend(removed.iter().map(|&index| (index, true)));
    targets.extend(
        cut.iter()
            .filter(|index| !removed.contains(index))
            .map(|&index| (index, false)),
    );
    targets.sort_unstable_by(|a, b| b.0.cmp(&a.0).then(b.1.cmp(&a.1)));
    targets.dedup_by_key(|target| target.0);
    let mut changes = Vec::new();
    let mut pieces_total = 0usize;
    let mut added_points = 0usize;
    for (index, whole) in targets {
        if whole {
            changes.push(Change::Remove(index));
            continue;
        }
        match pieces_of(doc, index, path, f64::from(radius)) {
            Ok(Some(pieces)) => {
                pieces_total += pieces.len();
                added_points += pieces.iter().map(|p| p.points.len()).sum::<usize>();
                changes.push(Change::Cut(index, pieces));
            }
            Ok(None) => {}
            Err(status) => return status,
        }
    }
    if changes.is_empty() {
        return 0;
    }
    let removed_points: usize = changes
        .iter()
        .map(|change| match change {
            Change::Remove(index) | Change::Cut(index, _) => doc.strokes[*index].points.len(),
        })
        .sum();
    let removed_objects = changes.len();
    if pieces_total > MAX_PIECES
        || doc.strokes.len() - removed_objects + pieces_total > MAX_STROKES
        || doc.active_points - removed_points + added_points > MAX_TOTAL_POINTS
    {
        return INVALID;
    }
    let merging = merge == 1
        && doc.cursor == doc.history.len()
        && matches!(
            doc.history.last(),
            Some(Edit::Batch {
                kind: ERASER_BATCH,
                ..
            })
        );
    if let Err(status) = doc.prepare_edit(added_points, pieces_total, true) {
        return status;
    }
    // Every reservation before the first change: never half a rub.
    if merging {
        if let Some(Edit::Batch { edits, .. }) = doc.history.last_mut() {
            if edits.try_reserve(removed_objects + pieces_total).is_err() {
                return ALLOCATION_FAILURE;
            }
        }
    }
    if doc.next_revision.checked_add(pieces_total as u64).is_none() {
        return INVALID;
    }
    let mut inverses = Vec::new();
    if inverses
        .try_reserve(removed_objects + pieces_total)
        .is_err()
        || doc.strokes.try_reserve(pieces_total).is_err()
    {
        return ALLOCATION_FAILURE;
    }
    let changed = removed_objects as i32;
    for change in changes {
        match change {
            Change::Remove(index) => {
                let stroke = doc.strokes.remove(index);
                doc.count_detached(&stroke);
                inverses.push(Edit::Presence {
                    index,
                    detached: Some(stroke),
                });
            }
            Change::Cut(index, pieces) => {
                let stroke = doc.strokes.remove(index);
                doc.count_detached(&stroke);
                inverses.push(Edit::Presence {
                    index,
                    detached: Some(stroke),
                });
                for (offset, mut piece) in pieces.into_iter().enumerate() {
                    piece.revision = doc.issue_revision();
                    doc.strokes.insert(index + offset, piece);
                    doc.count_attached(index + offset);
                    inverses.push(Edit::Presence {
                        index: index + offset,
                        detached: None,
                    });
                }
            }
        }
    }
    // Undo applies the inverses from the last change back to the first.
    inverses.reverse();
    if merging {
        if let Some(Edit::Batch { edits, .. }) = doc.history.last_mut() {
            // This call's changes came after the batch's: undone first.
            edits.splice(0..0, inverses);
        }
        doc.retained_points += added_points;
        doc.retained_objects += pieces_total;
    } else {
        doc.commit_edit(
            Edit::Batch {
                edits: inverses,
                kind: ERASER_BATCH,
            },
            added_points,
            pieces_total,
        );
    }
    changed
}

#[cfg(test)]
mod tests;
