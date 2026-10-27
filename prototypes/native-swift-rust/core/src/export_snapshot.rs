//! Autonomous immutable exports. The hidden document-shaped value exists only
//! to reuse the exact serializers; it owns no edit/redo payload or history.
use super::*;

/// Opaque to C. Once published, no method exposes or mutates its drawing.
pub struct EpExportSnapshot {
    drawing: EpDocument,
}

fn capture(document: &EpDocument) -> Result<EpExportSnapshot, i32> {
    // Native constructors/editors establish these bounds; retain an explicit
    // guard here so the maximum captured allocation is visible and auditable.
    if document.strokes.len() > MAX_STROKES || document.active_points > MAX_TOTAL_POINTS {
        return Err(INVALID);
    }
    let mut strokes = Vec::new();
    strokes
        .try_reserve_exact(document.strokes.len())
        .map_err(|_| ALLOCATION_FAILURE)?;
    let mut point_count = 0usize;
    let mut text_bytes = 0usize;
    let mut extended = 0usize;
    let mut contours = 0usize;
    for stroke in &document.strokes {
        point_count = point_count
            .checked_add(stroke.points.len())
            .ok_or(INVALID)?;
        text_bytes = text_bytes.checked_add(stroke.text.len()).ok_or(INVALID)?;
        if stroke.points.len() > MAX_STROKE_POINTS
            || point_count > MAX_TOTAL_POINTS
            || stroke.text.len() > MAX_TEXT_BYTES
            || text_bytes > MAX_TOTAL_TEXT_BYTES
        {
            return Err(INVALID);
        }
        extended += usize::from(stroke.extended());
        contours += usize::from(stroke.style.kind == KIND_CONTOUR);
        let mut points = Vec::new();
        points
            .try_reserve_exact(stroke.points.len())
            .map_err(|_| ALLOCATION_FAILURE)?;
        points.extend_from_slice(&stroke.points);
        let mut text = Vec::new();
        text.try_reserve_exact(stroke.text.len())
            .map_err(|_| ALLOCATION_FAILURE)?;
        text.extend_from_slice(&stroke.text);
        strokes.push(Stroke {
            points,
            rgb: stroke.rgb,
            width: stroke.width,
            style: stroke.style,
            scale: stroke.scale,
            translation: stroke.translation,
            revision: stroke.revision,
            layer: stroke.layer,
            param: stroke.param,
            text,
        });
    }
    if point_count != document.active_points
        || text_bytes != document.active_text_bytes
        || extended != document.active_extended
        || contours != document.active_contours
    {
        return Err(INVALID);
    }
    Ok(EpExportSnapshot {
        drawing: EpDocument {
            width: document.width,
            height: document.height,
            background: document.background.as_ref().map(Arc::clone),
            strokes,
            history: Vec::new(),
            cursor: 0,
            active_points: point_count,
            retained_points: point_count,
            retained_objects: document.strokes.len(),
            next_revision: document.next_revision,
            layers: document.layers,
            layer_count: document.layer_count,
            active_layer: document.active_layer,
            active_text_bytes: text_bytes,
            retained_text_bytes: text_bytes,
            active_extended: extended,
            active_contours: contours,
            paper: document.paper,
        },
    })
}

/// Copies visible vector geometry, shares immutable PNG bytes, excludes history.
/// Returns NULL on failure, optional out_status: 0 success/-1 invalid/-2 OOM.
/// All snapshot allocations are fallible. Arc::clone does not allocate; the
/// small std Arc control allocation occurs earlier at background import/load.
///
/// # Safety
/// Non-null document must be live, aligned, owned by this thread and exclusively
/// accessible for this call. out_status must be writable/aligned and disjoint
/// from document storage. The result may be transferred across threads after
/// publication; free it exactly once, only after all readers have finished.
#[no_mangle]
pub unsafe extern "C" fn ep_export_snapshot_new(
    document: *const EpDocument,
    out_status: *mut i32,
) -> *mut EpExportSnapshot {
    let value = unsafe { document.as_ref() }
        .ok_or(INVALID)
        .and_then(capture);
    let (snapshot, status) = match value {
        Ok(value) => {
            let pointer =
                unsafe { alloc(Layout::new::<EpExportSnapshot>()).cast::<EpExportSnapshot>() };
            if pointer.is_null() {
                (ptr::null_mut(), ALLOCATION_FAILURE)
            } else {
                unsafe { pointer.write(value) };
                (pointer, 0)
            }
        }
        Err(code) => (ptr::null_mut(), code),
    };
    if !out_status.is_null() {
        unsafe { out_status.write(status) };
    }
    snapshot
}

/// Consumes one snapshot ownership; NULL is a no-op.
///
/// # Safety
/// Non-null pointer must be a live result of ep_export_snapshot_new. No reader
/// may be using it, or start using it, during/after this call. It is safe to
/// destroy the original document on its owner thread while snapshots exist.
#[no_mangle]
pub unsafe extern "C" fn ep_export_snapshot_free(snapshot: *mut EpExportSnapshot) {
    if !snapshot.is_null() {
        unsafe { drop(Box::from_raw(snapshot)) };
    }
}

/// Exact serialized size; 0 for NULL. No allocation/mutation.
///
/// # Safety
/// Non-null snapshot must remain live/aligned until this read completes.
#[no_mangle]
pub unsafe extern "C" fn ep_export_snapshot_project_size(
    snapshot: *const EpExportSnapshot,
) -> usize {
    unsafe { snapshot.as_ref() }.map_or(0, |snapshot| project_size(&snapshot.drawing))
}

/// Same output/status contract as ep_copy_project, using immutable captured data.
///
/// # Safety
/// Non-null snapshot must remain live/aligned until completion. out_bytes must
/// address capacity writable bytes disjoint from snapshot/source storage and
/// other concurrent outputs. Multiple readers may use this snapshot together.
#[no_mangle]
pub unsafe extern "C" fn ep_export_snapshot_copy_project(
    snapshot: *const EpExportSnapshot,
    out_bytes: *mut u8,
    capacity: usize,
) -> i32 {
    let Some(snapshot) = (unsafe { snapshot.as_ref() }) else {
        return INVALID;
    };
    unsafe { copy_project(&snapshot.drawing, out_bytes, capacity) }
}

/// Owned UTF-8 SVG or NULL; release exactly once with ep_string_free.
///
/// # Safety
/// Non-null snapshot must remain live/aligned until this read completes.
/// Parallel reads are allowed; every result has independent ownership.
#[no_mangle]
pub unsafe extern "C" fn ep_export_snapshot_export_svg(
    snapshot: *const EpExportSnapshot,
) -> *mut c_char {
    let Some(snapshot) = (unsafe { snapshot.as_ref() }) else {
        return ptr::null_mut();
    };
    svg(&snapshot.drawing).map_or(ptr::null_mut(), CString::into_raw)
}

#[cfg(test)]
mod tests;
