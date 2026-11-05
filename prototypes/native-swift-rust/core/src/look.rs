// SPDX-License-Identifier: MIT
//! What Color 1.1 adds to an object, read and changed through the C contract:
//! its look (rotation, mirror, tool of a freehand stroke and its seed,
//! gradient of a fill), the pressures of a freehand stroke and the rings of
//! a contour with holes. Version 6 of the project keeps them; the older
//! writer refuses a drawing that has any (`EpDocument::active_v6`).

use super::*;

/// Copies the look of the object at `index`. Returns 0, or -1 for NULL or an
/// index outside the drawing.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently mutated;
/// non-null `out_look` must be writable, aligned and disjoint from it.
#[no_mangle]
pub unsafe extern "C" fn ep_object_look(
    document: *const EpDocument,
    index: usize,
    out_look: *mut EpObjectLook,
) -> i32 {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return INVALID;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return INVALID;
    };
    if out_look.is_null() {
        return INVALID;
    }
    unsafe { out_look.write(stroke.extras.look) };
    0
}

/// Replaces the fill and the look of the object at `index` in one command
/// that undo reverses: the paint pot giving a gradient, Choisir turning or
/// mirroring an object, the pot taking a gradient away with its fill. The
/// kind stays (`style.kind` must be the object's), the outline colour and
/// width too. Returns 1 changed, 0 the same paint, -1 invalid, -2 memory.
///
/// An object of a locked layer — a zone of a colouring page — keeps its
/// fill on and its rotation, mirror and tool: only the colour of its fill and
/// its gradient may change, as ep_set_object_style lets the colour change.
///
/// # Safety
/// Non-null `document` must be live, aligned and exclusively accessible;
/// non-null `style` and `look` must each be one initialized value, disjoint
/// from the document and unchanged during the call.
#[no_mangle]
pub unsafe extern "C" fn ep_set_object_paint(
    document: *mut EpDocument,
    index: usize,
    style: *const EpObjectStyle,
    look: *const EpObjectLook,
) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    let (Some(&style), Some(&look)) = (unsafe { style.as_ref() }, unsafe { look.as_ref() }) else {
        return INVALID;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return INVALID;
    };
    if style.kind != stroke.style.kind
        || !valid_style(style)
        || !valid_look(style.kind, style.fill_enabled, &look)
    {
        return INVALID;
    }
    let current = stroke.extras.look;
    if doc.locked(stroke.layer)
        && (stroke.style.fill_enabled != 1
            || style.fill_enabled != 1
            || look.rotation != current.rotation
            || look.mirror != current.mirror
            || look.tool != current.tool
            || look.seed != current.seed)
    {
        return INVALID;
    }
    if stroke.style == style && current == look {
        return 0;
    }
    let inverse = Edit::Paint {
        index,
        style: stroke.style,
        look: current,
        revision: stroke.revision,
    };
    if let Err(status) = doc.prepare_edit(0, 0, true) {
        return status;
    }
    let revision = doc.issue_revision();
    let stroke = &mut doc.strokes[index];
    let before = usize::from(stroke.needs_v6());
    stroke.style = style;
    stroke.extras.look = look;
    stroke.revision = revision;
    let after = usize::from(stroke.needs_v6());
    doc.active_v6 = doc.active_v6 - before + after;
    doc.commit_edit(inverse, 0, 0);
    1
}

/// The number of pressures of the object at `index`: its point count for a
/// freehand stroke drawn with a pressure, else 0 (also for NULL or an index
/// outside the drawing).
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently mutated.
#[no_mangle]
pub unsafe extern "C" fn ep_object_pressure_count(
    document: *const EpDocument,
    index: usize,
) -> usize {
    unsafe { document.as_ref() }
        .and_then(|doc| doc.strokes.get(index))
        .map_or(0, |stroke| stroke.extras.pressures.len())
}

/// Copies the pressures of the object at `index`, one byte per point (1 to
/// 255: the width at a point is the stroke's width × pressure / 255).
/// Returns their count, or 0 when it has none, for NULL, for an index
/// outside the drawing or a capacity below the count; no partial write.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently mutated;
/// `out_pressures` must be writable for `capacity` bytes, disjoint from it.
#[no_mangle]
pub unsafe extern "C" fn ep_copy_pressures(
    document: *const EpDocument,
    index: usize,
    out_pressures: *mut u8,
    capacity: usize,
) -> usize {
    let Some(stroke) = (unsafe { document.as_ref() }).and_then(|doc| doc.strokes.get(index)) else {
        return 0;
    };
    let pressures = &stroke.extras.pressures;
    if pressures.is_empty() || out_pressures.is_null() || capacity < pressures.len() {
        return 0;
    }
    unsafe { slice::from_raw_parts_mut(out_pressures, pressures.len()) }.copy_from_slice(pressures);
    pressures.len()
}

/// The number of rings of the contour at `index` when it has holes (two or
/// more), else 0: a contour of one ring, any other kind, NULL, an index
/// outside the drawing.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently mutated.
#[no_mangle]
pub unsafe extern "C" fn ep_object_ring_count(document: *const EpDocument, index: usize) -> usize {
    unsafe { document.as_ref() }
        .and_then(|doc| doc.strokes.get(index))
        .map_or(0, |stroke| stroke.extras.rings.len())
}

/// Copies the point counts of the rings of the contour at `index`, in the
/// order of its points: the first ring is its first points, and so on. A
/// contour with rings is filled by the even-odd rule. Returns the ring count,
/// or 0 as ep_copy_pressures does; no partial write.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently mutated;
/// `out_rings` must be writable for `capacity` values, aligned, disjoint.
#[no_mangle]
pub unsafe extern "C" fn ep_copy_rings(
    document: *const EpDocument,
    index: usize,
    out_rings: *mut u32,
    capacity: usize,
) -> usize {
    let Some(stroke) = (unsafe { document.as_ref() }).and_then(|doc| doc.strokes.get(index)) else {
        return 0;
    };
    let rings = &stroke.extras.rings;
    if rings.is_empty() || out_rings.is_null() || capacity < rings.len() {
        return 0;
    }
    unsafe { slice::from_raw_parts_mut(out_rings, rings.len()) }.copy_from_slice(rings);
    rings.len()
}

#[cfg(test)]
mod tests;
