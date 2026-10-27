//! Simple layers: an ordered stack of at most sixteen visible/hidden groups.
//!
//! Every object carries the stable identifier of its layer. The object list
//! keeps one global order; an object is painted with its layer, bottom layer
//! first, and inside a layer in list order. Layer edits are ordinary reversible
//! commands of the single history. The active layer only selects where new
//! objects go: it is a view state, saved in the project but never undoable.
//!
//! A layer may be locked: the zones and the lines of a colouring page are.
//! Only ep_document_from_page and a project of version 5 make one, and a lock
//! never changes afterwards. The core keeps a page whole whatever the
//! interface asks: a locked layer is never active, removed or moved, though
//! it may be hidden, and no other layer ever passes it: a layer moves only
//! among the layers between the same two locked layers, and a new layer
//! comes just above the active one. The drawing of a page thus stays above
//! its zones and below its lines; were it moved under the zones, their white
//! would hide it. The objects of a locked layer are never removed, moved,
//! resized, reordered, copied, sent to another layer, rewritten or
//! restyled, and nothing joins it. One change only is allowed, the paint
//! pot's: the colour of a fill that an object of the layer already has
//! (ep_set_object_style).
use super::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct Layer {
    pub id: u8,
    pub visible: bool,
    // Fixed from the creation of the layer: see the module documentation.
    pub locked: bool,
}

pub(super) const DEFAULT_LAYERS: [Layer; MAX_LAYERS] = [Layer {
    id: 0,
    visible: true,
    locked: false,
}; MAX_LAYERS];

/// One layer of the stack, bottom first. `object_count` is its visible content.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EpLayerInfo {
    pub id: u32,
    pub visible: u32, // exactly 0 or 1
    pub object_count: usize,
}

/// Layer, catalogue/font parameter and character count of one object.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EpObjectExtra {
    pub layer: u32,
    pub param: u32, // stamp identifier, text font, zero otherwise
    pub text_bytes: usize,
}

// Same rotation as object reordering, on the small fixed table.
pub(super) fn reorder_layers(layers: &mut [Layer], from: usize, to: usize) {
    if from < to {
        layers[from..=to].rotate_left(1);
    } else {
        layers[to..=from].rotate_right(1);
    }
}

impl EpDocument {
    pub(super) fn layers(&self) -> &[Layer] {
        &self.layers[..self.layer_count]
    }

    fn layer_position(&self, id: u8) -> Option<usize> {
        self.layers().iter().position(|layer| layer.id == id)
    }

    /// Whether layer `id` exists and is locked: its objects are a page's.
    pub(super) fn locked(&self, id: u8) -> bool {
        self.layers()
            .iter()
            .any(|layer| layer.id == id && layer.locked)
    }

    /// One visible layer and nothing else: the historic drawing model.
    pub(super) fn single_plain_layer(&self) -> bool {
        self.layer_count == 1 && self.layers[0].visible
    }

    /// Layers, texts, stamps and a coloured sheet are stored by project v4
    /// or later.
    pub(super) fn needs_layered_project(&self) -> bool {
        !self.single_plain_layer()
            || self.active_extended != 0
            || self.paper != WHITE_PAPER
            || self.needs_locked_project()
    }

    /// Locked layers and closed contours, whatever layer holds them and
    /// whether it is shown or not, are stored by project v5 only.
    pub(super) fn needs_locked_project(&self) -> bool {
        self.active_contours != 0 || self.layers().iter().any(|layer| layer.locked)
    }

    // The layer nearest to `position` that is not locked, below first, then
    // above; one always exists while the document holds a layer to draw on.
    fn nearest_unlocked(&self, position: usize) -> Option<u8> {
        let (below, above) = self.layers().split_at(position.min(self.layer_count));
        below
            .iter()
            .rev()
            .chain(above)
            .find(|layer| !layer.locked)
            .map(|layer| layer.id)
    }

    fn insert_layer(&mut self, position: usize, layer: Layer) {
        self.layers
            .copy_within(position..self.layer_count, position + 1);
        self.layers[position] = layer;
        self.layer_count += 1;
    }

    fn remove_layer_entry(&mut self, position: usize) -> Layer {
        let layer = self.layers[position];
        self.layers
            .copy_within(position + 1..self.layer_count, position);
        self.layer_count -= 1;
        layer
    }

    // The receiving layer always exists and is never locked: fall back to the
    // highest layer that is not, the top of the stack when nothing is locked.
    fn ensure_active_layer(&mut self) {
        if self.layer_position(self.active_layer).is_none() || self.locked(self.active_layer) {
            if let Some(id) = self.nearest_unlocked(self.layer_count) {
                self.active_layer = id;
            }
        }
    }

    // Moves every object of `id` into `detached`, remembering its index. The
    // caller reserved the capacity: this never allocates, including for redo.
    fn detach_layer_objects(&mut self, id: u8, detached: &mut Vec<(usize, Stroke)>) {
        let mut write = 0;
        for read in 0..self.strokes.len() {
            if self.strokes[read].layer == id {
                let stroke = std::mem::replace(&mut self.strokes[read], Stroke::placeholder());
                self.count_detached(&stroke);
                detached.push((read, stroke));
            } else {
                if write != read {
                    self.strokes.swap(write, read);
                }
                write += 1;
            }
        }
        self.strokes.truncate(write);
    }

    // Exact inverse: a backward merge returns each object to its former index
    // in O(objects), without allocating; `detached` keeps its capacity.
    fn reattach_layer_objects(&mut self, detached: &mut Vec<(usize, Stroke)>) {
        let mut kept = self.strokes.len();
        let total = kept + detached.len();
        // Capacity never shrinks and once held all of these objects.
        self.strokes.resize_with(total, Stroke::placeholder);
        let mut remaining = detached.len();
        for position in (0..total).rev() {
            if remaining > 0 && detached[remaining - 1].0 == position {
                std::mem::swap(&mut self.strokes[position], &mut detached[remaining - 1].1);
                self.count_attached(position);
                remaining -= 1;
            } else {
                kept -= 1;
                if kept != position {
                    self.strokes.swap(position, kept);
                }
            }
        }
        detached.clear();
    }

    pub(super) fn apply_layer_presence(&mut self, slot: usize) {
        // Take the payload out of the command: its capacity returns below.
        let Edit::LayerPresence {
            position,
            layer,
            detached,
            active,
        } = &mut self.history[slot]
        else {
            return;
        };
        let position = *position;
        let entry = layer.take();
        let mut objects = std::mem::take(detached);
        let mut other_active = *active;
        let removed = match entry {
            Some(entry) => {
                self.insert_layer(position, entry);
                self.reattach_layer_objects(&mut objects);
                None
            }
            None => {
                let entry = self.remove_layer_entry(position);
                self.detach_layer_objects(entry.id, &mut objects);
                Some(entry)
            }
        };
        std::mem::swap(&mut self.active_layer, &mut other_active);
        self.ensure_active_layer();
        if let Edit::LayerPresence {
            layer,
            detached,
            active,
            ..
        } = &mut self.history[slot]
        {
            *layer = removed;
            *detached = objects;
            *active = other_active;
        }
    }
}

/// Number of layers, at least one for a live document; zero for NULL.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently accessed.
#[no_mangle]
pub unsafe extern "C" fn ep_layer_count(document: *const EpDocument) -> usize {
    unsafe { document.as_ref() }.map_or(0, |doc| doc.layer_count)
}

/// Describes the layer at `position`, zero being the bottom of the stack.
/// Returns 0 on success, -1 invalid document/position/output; no partial write.
/// Counting its objects visits the bounded object list once.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently accessed.
/// `out_info` must be writable/aligned for one EpLayerInfo, disjoint from
/// document-owned storage.
#[no_mangle]
pub unsafe extern "C" fn ep_layer_info(
    document: *const EpDocument,
    position: usize,
    out_info: *mut EpLayerInfo,
) -> i32 {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return INVALID;
    };
    let Some(layer) = doc.layers().get(position) else {
        return INVALID;
    };
    if out_info.is_null() {
        return INVALID;
    }
    let object_count = doc.strokes.iter().filter(|s| s.layer == layer.id).count();
    unsafe {
        out_info.write(EpLayerInfo {
            id: u32::from(layer.id),
            visible: u32::from(layer.visible),
            object_count,
        });
    }
    0
}

/// Whether the layer at `position`, zero being the bottom of the stack, is
/// locked: 1 locked, 0 not, -1 for a NULL document or a position outside
/// the stack. Added beside ep_layer_info, whose layout stays unchanged.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently accessed.
#[no_mangle]
pub unsafe extern "C" fn ep_layer_locked(document: *const EpDocument, position: usize) -> i32 {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return INVALID;
    };
    doc.layers()
        .get(position)
        .map_or(INVALID, |layer| i32::from(layer.locked))
}

/// Identifier of the layer receiving new objects; `u32::MAX` for NULL.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently accessed.
#[no_mangle]
pub unsafe extern "C" fn ep_active_layer(document: *const EpDocument) -> u32 {
    unsafe { document.as_ref() }.map_or(u32::MAX, |doc| u32::from(doc.active_layer))
}

/// Chooses the layer receiving new objects. Returns 0 on success, -1 for a
/// NULL document, an unknown identifier or a locked layer. Not a drawing
/// edit: history, redo and object revisions are unchanged.
///
/// # Safety
/// Non-null `document` must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_set_active_layer(document: *mut EpDocument, id: u32) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    match u8::try_from(id) {
        Ok(id) if doc.layer_position(id).is_some() && !doc.locked(id) => {
            doc.active_layer = id;
            0
        }
        _ => INVALID,
    }
}

/// Adds an empty visible layer just above the active one and makes it active.
/// It is never locked. Returns 1 changed, -1 NULL / sixteen layers / history
/// limits, -2 allocation failure. Failure changes nothing; success clears redo.
///
/// # Safety
/// Non-null `document` must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_add_layer(document: *mut EpDocument) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    if doc.layer_count >= MAX_LAYERS {
        return INVALID;
    }
    // Smallest free identifier: at most sixteen layers, so one always exists.
    let Some(id) = (0..MAX_LAYERS as u8).find(|id| doc.layer_position(*id).is_none()) else {
        return INVALID;
    };
    // Just above the active layer, which always exists and is never locked:
    // the new layer lies between the same locked layers as the active one.
    let Some(active) = doc
        .layer_position(doc.active_layer)
        .filter(|&position| !doc.layers[position].locked)
    else {
        return INVALID;
    };
    let position = active + 1;
    if let Err(status) = doc.prepare_edit(0, 0, false) {
        return status;
    }
    let previous = doc.active_layer;
    doc.insert_layer(
        position,
        Layer {
            id,
            visible: true,
            locked: false,
        },
    );
    doc.active_layer = id;
    doc.commit_edit(
        Edit::LayerPresence {
            position,
            layer: None,
            detached: Vec::new(),
            active: previous,
        },
        0,
        0,
    );
    1
}

/// Removes the layer at `position` together with its objects, all restored by
/// undo. The last remaining layer cannot be removed, nor a locked layer, nor
/// the last layer that is not locked. If it was active, the nearest layer
/// that is not locked becomes active: below it first, then above (with no
/// locked layer, the layer below, or the new bottom). Returns 1 changed, -1
/// NULL / invalid position / last layer / locked layer / last unlocked layer
/// / history limits, -2 allocation failure.
///
/// # Safety
/// Non-null `document` must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_remove_layer(document: *mut EpDocument, position: usize) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    if position >= doc.layer_count || doc.layer_count == 1 {
        return INVALID;
    }
    let id = doc.layers[position].id;
    // A page keeps its layers, and the child keeps one layer to draw on.
    if doc.layers[position].locked
        || doc
            .layers()
            .iter()
            .all(|layer| layer.id == id || layer.locked)
    {
        return INVALID;
    }
    let count = doc.strokes.iter().filter(|s| s.layer == id).count();
    let mut detached = Vec::new();
    if detached.try_reserve_exact(count).is_err() {
        return ALLOCATION_FAILURE;
    }
    if let Err(status) = doc.prepare_edit(0, 0, false) {
        return status;
    }
    let previous = doc.active_layer;
    let layer = doc.remove_layer_entry(position);
    doc.detach_layer_objects(id, &mut detached);
    if previous == id {
        // Checked above: a layer that is not locked remains.
        doc.active_layer = doc.nearest_unlocked(position).unwrap_or(doc.layers[0].id);
    }
    doc.commit_edit(
        Edit::LayerPresence {
            position,
            layer: Some(layer),
            detached,
            active: previous,
        },
        0,
        0,
    );
    1
}

/// Moves a layer to its final `to` position; other layers keep their order.
/// Locked layers keep their places: -1 when one lies anywhere from `from`
/// to `to`, both included. A locked layer is therefore never moved and no
/// layer passes one; the layers between two locked layers are reordered
/// among themselves. Returns 1 changed, 0 same position, -1 invalid / a
/// locked layer in the way / limits, -2 allocation. Objects, their indices
/// and revisions are untouched.
///
/// # Safety
/// Non-null `document` must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_reorder_layer(
    document: *mut EpDocument,
    from: usize,
    to: usize,
) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    if from >= doc.layer_count || to >= doc.layer_count {
        return INVALID;
    }
    // The drawing of a page under its zones would vanish under their white,
    // and above its lines it would cover them: nothing crosses a lock.
    if doc.layers[from.min(to)..=from.max(to)]
        .iter()
        .any(|layer| layer.locked)
    {
        return INVALID;
    }
    if from == to {
        return 0;
    }
    if let Err(status) = doc.prepare_edit(0, 0, false) {
        return status;
    }
    reorder_layers(&mut doc.layers[..doc.layer_count], from, to);
    doc.commit_edit(Edit::LayerOrder { from: to, to: from }, 0, 0);
    1
}

/// Shows (`visible` 1) or hides (0) a layer, locked or not. A hidden layer
/// keeps its objects but is left out of exports. Returns 1 changed, 0
/// unchanged, -1 invalid / limits, -2 allocation failure.
///
/// # Safety
/// Non-null `document` must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_set_layer_visible(
    document: *mut EpDocument,
    position: usize,
    visible: u32,
) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    if position >= doc.layer_count || visible > 1 {
        return INVALID;
    }
    let previous = doc.layers[position].visible;
    if previous == (visible == 1) {
        return 0;
    }
    if let Err(status) = doc.prepare_edit(0, 0, false) {
        return status;
    }
    doc.layers[position].visible = visible == 1;
    doc.commit_edit(
        Edit::LayerVisibility {
            position,
            visible: previous,
        },
        0,
        0,
    );
    1
}

/// Moves one object to another layer, in front of that layer's objects (it
/// becomes the last visible index). Nothing leaves or joins a locked layer.
/// Returns 1 changed, 0 already there, -1 invalid index / layer / a locked
/// layer on either side / limits, -2 allocation failure.
///
/// # Safety
/// Non-null `document` must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_set_object_layer(
    document: *mut EpDocument,
    index: usize,
    layer: u32,
) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return INVALID;
    };
    let Ok(layer) = u8::try_from(layer) else {
        return INVALID;
    };
    if doc.layer_position(layer).is_none() || doc.locked(stroke.layer) || doc.locked(layer) {
        return INVALID;
    }
    if stroke.layer == layer {
        return 0;
    }
    let inverse = Edit::ObjectLayer {
        from: doc.strokes.len() - 1,
        to: index,
        layer: stroke.layer,
        revision: stroke.revision,
    };
    if let Err(status) = doc.prepare_edit(0, 0, true) {
        return status;
    }
    let last = doc.strokes.len() - 1;
    reorder_strokes(&mut doc.strokes, index, last);
    let revision = doc.issue_revision();
    let stroke = &mut doc.strokes[last];
    stroke.layer = layer;
    stroke.revision = revision;
    doc.commit_edit(inverse, 0, 0);
    1
}

/// Layer, parameter and text length of one object. Returns 0 on success, -1
/// for an invalid document, index or output; no partial write.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently accessed.
/// `out_extra` must be writable/aligned for one EpObjectExtra and disjoint
/// from document-owned storage.
#[no_mangle]
pub unsafe extern "C" fn ep_object_extra(
    document: *const EpDocument,
    index: usize,
    out_extra: *mut EpObjectExtra,
) -> i32 {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return INVALID;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return INVALID;
    };
    if out_extra.is_null() {
        return INVALID;
    }
    unsafe {
        out_extra.write(EpObjectExtra {
            layer: u32::from(stroke.layer),
            param: stroke.param,
            text_bytes: stroke.text.len(),
        });
    }
    0
}

#[cfg(test)]
mod tests;
