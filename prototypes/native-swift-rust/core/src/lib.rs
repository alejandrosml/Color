//! Independent EduPaint feasibility core: document geometry, history, and SVG.
//! No UI toolkit, Tux Paint engine, external dependency, or final renderer.
//!
//! Every document has one owning thread. All C calls must be serialized; raw
//! pointers must remain live/aligned and cannot alias document-owned storage.
//! Null is supported explicitly; dangling pointers cannot be validated here.
//! Immutable export snapshots have a separate cross-thread read-only contract.
#![deny(unsafe_op_in_unsafe_fn)]

use std::alloc::{alloc, Layout};
use std::ffi::{c_char, CString};
use std::fmt::Write;
use std::ptr;
use std::slice;
use std::sync::Arc;

#[cfg(feature = "svg")]
mod art;
#[cfg(feature = "svg")]
pub use art::*;
#[cfg(feature = "svg")]
mod pages;
#[cfg(feature = "svg")]
pub use pages::*;
mod background;
use background::{validate_canonical_png, BackgroundPng};
pub use background::{MAX_BACKGROUND_BYTES, MAX_BACKGROUND_DIMENSION, MAX_BACKGROUND_PIXELS};
mod export_snapshot;
pub use export_snapshot::*;
mod import_project;
pub use import_project::*;
mod layers;
pub use layers::*;
mod notices;
pub use notices::*;
mod paper;
pub use paper::*;
mod resize;
pub use resize::*;
mod sound;
pub use sound::*;
mod stamps;
pub use stamps::*;
mod text;
pub use text::*;
#[cfg(test)]
mod contour_tests;
#[cfg(test)]
mod history_model_tests;
#[cfg(test)]
mod layered_fixture_tests;
#[cfg(test)]
mod mutation_tests;
#[cfg(test)]
mod reader_oracle_tests;
#[cfg(test)]
mod test_support;

const MAX_DIMENSION: u32 = 16_384;
const MAX_STROKE_POINTS: usize = 100_000;
const MAX_STROKES: usize = 10_000;
const MAX_TOTAL_POINTS: usize = 1_000_000;
// Active geometry plus all detached history payload is bounded independently.
// At a limit, reject the edit; never silently discard the user's undo history.
const MAX_HISTORY_STEPS: usize = 50_000;
const MAX_RETAINED_POINTS: usize = 2_000_000;
const MAX_RETAINED_OBJECTS: usize = 20_000;
const PROJECT_MAGIC: &[u8; 8] = b"EDUPAINT";
const PROJECT_VERSION: u16 = 2;
const PROJECT_HEADER_BYTES: usize = 32;
const PROJECT_MIN_BYTES: usize = PROJECT_HEADER_BYTES + 4;
pub const MAX_VECTOR_PROJECT_BYTES: usize =
    PROJECT_MIN_BYTES + MAX_STROKES * 24 + MAX_TOTAL_POINTS * 8;
const HYBRID_PROJECT_VERSION: u16 = 3;
const HYBRID_PROJECT_HEADER_BYTES: usize = 48;
/// Largest v1/v2/v3 file. Version 4 has its own, slightly larger bound.
const MAX_HYBRID_PROJECT_BYTES: usize = MAX_VECTOR_PROJECT_BYTES + 16 + MAX_BACKGROUND_BYTES;
// Version 4 adds a layer table, text and stamp objects. It is written only
// when a document uses one of them; plain drawings keep their v2/v3 bytes.
const LAYERED_PROJECT_VERSION: u16 = 4;
// Version 5 keeps the layout of version 4; its layer table holds flags
// (visible, locked) and its records may be closed contours. It is written
// only when a document has a locked layer or a contour: everything else
// keeps its v2/v3/v4 bytes.
const LOCKED_PROJECT_VERSION: u16 = 5;
const LAYERED_PROJECT_HEADER_BYTES: usize = 56;
const LAYERED_OBJECT_BYTES: usize = 36;
const MAX_LAYERS: usize = 16;
const MAX_TEXT_BYTES: usize = 2048;
const MAX_TEXT_LINES: usize = 32;
const MAX_TOTAL_TEXT_BYTES: usize = 1 << 20;
const MAX_RETAINED_TEXT_BYTES: usize = 2 << 20;
const MIN_TEXT_SIZE: f32 = 4.0;
const MAX_TEXT_SIZE: f32 = 2048.0;
const KIND_TEXT: u32 = 4;
const KIND_STAMP: u32 = 5;
// A closed polygon: its points in order, the last one joined to the first.
// It is a list of points like a freehand stroke, and may be filled like a
// rectangle: the zones of the colouring pages are contours.
const KIND_CONTOUR: u32 = 6;
/// Colour of the sheet of a new document, and of every v1/v2/v3 project.
const WHITE_PAPER: u32 = 0x00ff_ffff;
// One resize multiplies an object's size by a factor in this range; the
// accumulated scale of its base points stays in a range where f64 is exact
// enough for f32 page coordinates.
const MIN_SCALE_FACTOR: f32 = 1.0 / 64.0;
const MAX_SCALE_FACTOR: f32 = 64.0;
const MIN_OBJECT_SCALE: f64 = 1.0e-9;
const MAX_OBJECT_SCALE: f64 = 1.0e9;
pub const MAX_PROJECT_BYTES: usize = LAYERED_PROJECT_HEADER_BYTES
    + MAX_LAYERS * 8
    + MAX_STROKES * LAYERED_OBJECT_BYTES
    + MAX_TOTAL_POINTS * 8
    + MAX_TOTAL_TEXT_BYTES
    + MAX_BACKGROUND_BYTES
    + 4;
const INVALID: i32 = -1;
const ALLOCATION_FAILURE: i32 = -2;

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EpPoint {
    pub x: f32,
    pub y: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EpStrokeInfo {
    pub rgb: u32,
    pub width: f32,
    pub point_count: usize,
}

/// Added separately: the established EpStrokeInfo layout remains unchanged.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EpObjectStyle {
    // 0 freehand, 1 line, 2 rectangle, 3 ellipse, 4 text, 5 stamp, 6 contour
    pub kind: u32,
    pub fill_enabled: u32, // exactly 0 or 1; only rectangles/ellipses/contours may fill
    pub fill_rgb: u32,     // 24-bit RGB; zero when fill is disabled
}

/// Immutable background metadata; visible-object indices remain vector-only.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EpBackgroundInfo {
    pub width: u32,
    pub height: u32,
    pub byte_count: usize,
}

const FREEHAND_STYLE: EpObjectStyle = EpObjectStyle {
    kind: 0,
    fill_enabled: 0,
    fill_rgb: 0,
};

fn valid_style(style: EpObjectStyle) -> bool {
    style.kind <= KIND_CONTOUR
        && style.fill_enabled <= 1
        && style.fill_rgb <= 0x00ff_ffff
        && (style.fill_enabled != 0 || style.fill_rgb == 0)
        && (matches!(style.kind, 2 | 3 | KIND_CONTOUR) || style.fill_enabled == 0)
}

// The historic `width` slot carries the outline width of drawn objects, the
// font size of a text and the constant 1.0 of a stamp, which has no outline.
fn valid_width(kind: u32, width: f32) -> bool {
    width.is_finite()
        && match kind {
            KIND_TEXT => (MIN_TEXT_SIZE..=MAX_TEXT_SIZE).contains(&width),
            KIND_STAMP => width == 1.0,
            _ => (0.1..=512.0).contains(&width),
        }
}

// `param` is the font of a text, the catalogue entry of a stamp, else zero.
fn valid_param(kind: u32, param: u32) -> bool {
    match kind {
        KIND_TEXT => param == 0,
        KIND_STAMP => (param as usize) < STAMPS.len(),
        _ => param == 0,
    }
}

struct Stroke {
    points: Vec<EpPoint>,
    rgb: u32,
    width: f32,
    style: EpObjectStyle,
    // Preserve base points; moving and resizing record only this constant-size
    // transform: a visible point is `base * scale + translation`. Undo swaps
    // the previous values, rather than inverting rounded f32 results.
    scale: f64,
    translation: [f64; 2],
    revision: u64,
    // Stable identifier of the owning layer, not its position in the stack.
    layer: u8,
    param: u32,
    // Validated UTF-8 of a text object; empty (never allocated) otherwise.
    text: Vec<u8>,
}

impl Stroke {
    // Owns no allocation: fills a slot whose object is detached by a layer.
    fn placeholder() -> Self {
        Self {
            points: Vec::new(),
            rgb: 0,
            width: 1.0,
            style: FREEHAND_STYLE,
            scale: 1.0,
            translation: [0.0; 2],
            revision: 0,
            layer: 0,
            param: 0,
            text: Vec::new(),
        }
    }

    fn extended(&self) -> bool {
        matches!(self.style.kind, KIND_TEXT | KIND_STAMP)
    }

    // Whether the object, seen through this transform, keeps what its kind
    // needs: a line its length, a box or a contour a width and a height. A
    // very small shape can collapse when translated to large f32 coordinates
    // or resized: a project that cannot be reopened must never be produced.
    fn keeps_its_shape(&self, scale: f64, translation: [f64; 2]) -> bool {
        match self.style.kind {
            0 => true,
            KIND_CONTOUR => contour_has_area(
                self.points
                    .iter()
                    .map(|point| Self::transformed(*point, scale, translation)),
            ),
            kind => valid_shape_points(
                kind,
                &[
                    Self::transformed(self.points[0], scale, translation),
                    Self::transformed(self.points[1], scale, translation),
                ],
            ),
        }
    }

    fn point_at(&self, index: usize) -> EpPoint {
        Self::transformed(self.points[index], self.scale, self.translation)
    }

    // An untouched axis returns its base value bit for bit; with a scale of
    // one this is exactly the historic `base + translation`.
    fn transformed(point: EpPoint, scale: f64, translation: [f64; 2]) -> EpPoint {
        let axis = |base: f32, offset: f64| {
            if scale == 1.0 && offset == 0.0 {
                base
            } else {
                (f64::from(base) * scale + offset) as f32
            }
        };
        EpPoint {
            x: axis(point.x, translation[0]),
            y: axis(point.y, translation[1]),
        }
    }

    fn moved_translation(&self, dx: f32, dy: f32, width: u32, height: u32) -> Option<[f64; 2]> {
        if !dx.is_finite() || !dy.is_finite() {
            return None;
        }
        let translation = [
            self.translation[0] + f64::from(dx),
            self.translation[1] + f64::from(dy),
        ];
        // Validate before changing any coordinate. Checking in f64 also rejects
        // a displacement just outside the page that would round back to f32.
        for point in &self.points {
            let base = [
                f64::from(point.x) * self.scale,
                f64::from(point.y) * self.scale,
            ];
            let x = base[0] + translation[0];
            let y = base[1] + translation[1];
            let incremental_x = (base[0] + self.translation[0]) + f64::from(dx);
            let incremental_y = (base[1] + self.translation[1]) + f64::from(dy);
            if !(0.0..=f64::from(width)).contains(&x)
                || !(0.0..=f64::from(height)).contains(&y)
                || !(0.0..=f64::from(width)).contains(&incremental_x)
                || !(0.0..=f64::from(height)).contains(&incremental_y)
            {
                return None;
            }
        }
        if !self.keeps_its_shape(self.scale, translation) {
            return None;
        }
        Some(translation)
    }

    // The transform after resizing by `factor` around the centre of the
    // current points, then moving the result just enough to keep it on the
    // page. None when the result cannot lie on the page or a shape would lose
    // its width or height: the caller then changes nothing.
    fn scaled_transform(&self, factor: f64, width: u32, height: u32) -> Option<(f64, [f64; 2])> {
        let scale = self.scale * factor;
        if !(MIN_OBJECT_SCALE..=MAX_OBJECT_SCALE).contains(&scale) {
            return None;
        }
        let page = [f64::from(width), f64::from(height)];
        let coordinate =
            |point: &EpPoint, axis: usize| f64::from(if axis == 0 { point.x } else { point.y });
        let mut translation = [0.0; 2];
        for axis in 0..2 {
            // Exact current extent, from base points and the present transform.
            let mut low = f64::INFINITY;
            let mut high = f64::NEG_INFINITY;
            for point in &self.points {
                let current = coordinate(point, axis) * self.scale + self.translation[axis];
                low = low.min(current);
                high = high.max(current);
            }
            let centre = (low + high) / 2.0;
            let half = (high - low) / 2.0 * factor;
            if half * 2.0 > page[axis] {
                return None;
            }
            // Keep the centre unless an edge of the page is in the way.
            let placed = centre.clamp(half, page[axis] - half);
            translation[axis] = (self.translation[axis] - centre) * factor + placed;
            // Rounding may leave the extreme point a hair outside the page:
            // move the whole object by that measured overshoot. Points are
            // never clipped one by one.
            for _ in 0..2 {
                let mut lowest = f64::INFINITY;
                let mut highest = f64::NEG_INFINITY;
                for point in &self.points {
                    let value = coordinate(point, axis) * scale + translation[axis];
                    lowest = lowest.min(value);
                    highest = highest.max(value);
                }
                if lowest < 0.0 {
                    translation[axis] -= lowest;
                } else if highest > page[axis] {
                    translation[axis] -= highest - page[axis];
                }
            }
        }
        for point in &self.points {
            for (axis, size) in page.into_iter().enumerate() {
                let value = coordinate(point, axis) * scale + translation[axis];
                if !(0.0..=size).contains(&value) {
                    return None;
                }
            }
        }
        if !self.keeps_its_shape(scale, translation) {
            return None;
        }
        Some((scale, translation))
    }
}

// Every command stores the inverse of its current state. Applying it swaps
// that inverse in place, making undo and redo allocation-free. Only insert /
// remove can own a point vector, transferred from or to the visible document.
enum Edit {
    Presence {
        index: usize,
        detached: Option<Stroke>,
    },
    Move {
        index: usize,
        translation: [f64; 2],
        revision: u64,
    },
    Order {
        from: usize,
        to: usize,
    },
    // Resizing: the previous transform and outline width of the object.
    Scale {
        index: usize,
        scale: f64,
        translation: [f64; 2],
        width: f32,
        revision: u64,
    },
    // The previous colour of the sheet.
    Paper {
        rgb: u32,
    },
    Style {
        index: usize,
        rgb: u32,
        width: f32,
        style: EpObjectStyle,
        revision: u64,
    },
    // Replaced content of a text: box, colour, size, font and characters.
    Text {
        index: usize,
        points: [EpPoint; 2],
        translation: [f64; 2],
        rgb: u32,
        width: f32,
        param: u32,
        text: Vec<u8>,
        revision: u64,
    },
    // Object currently at `from` returns to `to` and to the stored layer.
    ObjectLayer {
        from: usize,
        to: usize,
        layer: u8,
        revision: u64,
    },
    // `layer` is Some while the layer is absent from the document. Removing a
    // layer detaches its objects with their indices; capacity is kept for redo.
    LayerPresence {
        position: usize,
        layer: Option<Layer>,
        detached: Vec<(usize, Stroke)>,
        active: u8,
    },
    LayerOrder {
        from: usize,
        to: usize,
    },
    LayerVisibility {
        position: usize,
        visible: bool,
    },
}

/// Opaque to C; its fields are never exposed through the ABI.
pub struct EpDocument {
    width: u32,
    height: u32,
    background: Option<Arc<BackgroundPng>>,
    strokes: Vec<Stroke>,
    history: Vec<Edit>,
    cursor: usize,
    active_points: usize,
    retained_points: usize,
    retained_objects: usize,
    // Never reused within this document, including discarded redo branches.
    next_revision: u64,
    // Bottom to top. Objects of one layer keep their relative `strokes` order.
    layers: [Layer; MAX_LAYERS],
    layer_count: usize,
    // Receives new objects. A view state: serialized in v4, never undoable.
    active_layer: u8,
    active_text_bytes: usize,
    retained_text_bytes: usize,
    // Visible text and stamp objects: their presence requires project v4.
    active_extended: usize,
    // Visible closed contours: their presence requires project v5.
    active_contours: usize,
    // Colour of the sheet under the drawing, 24-bit RGB. Not white needs v4.
    paper: u32,
}

// Geometric growth avoids a realloc for each command while bounding requested
// capacities. Allocation failures can only change capacity, never content.
fn reserve_bounded<T>(values: &mut Vec<T>, needed: usize, limit: usize) -> Result<(), i32> {
    if needed > limit {
        return Err(INVALID);
    }
    if needed > values.capacity() {
        let capacity = needed.max(values.capacity().saturating_mul(2)).min(limit);
        values
            .try_reserve_exact(capacity - values.len())
            .map_err(|_| ALLOCATION_FAILURE)?;
    }
    Ok(())
}

impl EpDocument {
    // A white sheet with one visible layer, nothing drawn, no history.
    fn blank(width: u32, height: u32) -> Self {
        Self {
            width,
            height,
            background: None,
            strokes: Vec::new(),
            history: Vec::new(),
            cursor: 0,
            active_points: 0,
            retained_points: 0,
            retained_objects: 0,
            next_revision: 1,
            layers: DEFAULT_LAYERS,
            layer_count: 1,
            active_layer: 0,
            active_text_bytes: 0,
            retained_text_bytes: 0,
            active_extended: 0,
            active_contours: 0,
            paper: WHITE_PAPER,
        }
    }

    // Geometry and characters owned only by the redo branch: (points, objects,
    // text bytes). An undone layer edit owns no object, by construction.
    fn redo_payload(&self) -> (usize, usize, usize) {
        self.history[self.cursor..]
            .iter()
            .fold((0, 0, 0), |(points, objects, text), edit| match edit {
                Edit::Presence {
                    detached: Some(stroke),
                    ..
                } => (
                    points + stroke.points.len(),
                    objects + 1,
                    text + stroke.text.len(),
                ),
                Edit::Text { text: other, .. } => (points, objects, text + other.len()),
                _ => (points, objects, text),
            })
    }

    fn prepare_edit(
        &mut self,
        added_points: usize,
        added_objects: usize,
        new_revision: bool,
    ) -> Result<(), i32> {
        self.prepare_text_edit(added_points, added_objects, 0, new_revision)
    }

    fn prepare_text_edit(
        &mut self,
        added_points: usize,
        added_objects: usize,
        added_text: usize,
        new_revision: bool,
    ) -> Result<(), i32> {
        let (redo_points, redo_objects, redo_text) = self.redo_payload();
        if self.cursor >= MAX_HISTORY_STEPS
            || (new_revision && self.next_revision == u64::MAX)
            || added_points > MAX_RETAINED_POINTS - (self.retained_points - redo_points)
            || added_objects > MAX_RETAINED_OBJECTS - (self.retained_objects - redo_objects)
            || added_text > MAX_RETAINED_TEXT_BYTES - (self.retained_text_bytes - redo_text)
        {
            return Err(INVALID);
        }
        reserve_bounded(&mut self.history, self.cursor + 1, MAX_HISTORY_STEPS)
    }

    fn issue_revision(&mut self) -> u64 {
        let revision = self.next_revision;
        self.next_revision += 1; // preflight rejected exhaustion before mutation
        revision
    }

    fn commit_edit(&mut self, edit: Edit, added_points: usize, added_objects: usize) {
        self.commit_text_edit(edit, added_points, added_objects, 0);
    }

    fn commit_text_edit(
        &mut self,
        edit: Edit,
        added_points: usize,
        added_objects: usize,
        added_text: usize,
    ) {
        let (redo_points, redo_objects, redo_text) = self.redo_payload();
        self.history.truncate(self.cursor);
        self.retained_points = self.retained_points - redo_points + added_points;
        self.retained_objects = self.retained_objects - redo_objects + added_objects;
        self.retained_text_bytes = self.retained_text_bytes - redo_text + added_text;
        self.history.push(edit);
        self.cursor += 1;
    }

    // Counters of the visible drawing follow every attach/detach of an object.
    fn count_attached(&mut self, index: usize) {
        let stroke = &self.strokes[index];
        self.active_points += stroke.points.len();
        self.active_text_bytes += stroke.text.len();
        self.active_extended += usize::from(stroke.extended());
        self.active_contours += usize::from(stroke.style.kind == KIND_CONTOUR);
    }

    fn count_detached(&mut self, stroke: &Stroke) {
        self.active_points -= stroke.points.len();
        self.active_text_bytes -= stroke.text.len();
        self.active_extended -= usize::from(stroke.extended());
        self.active_contours -= usize::from(stroke.style.kind == KIND_CONTOUR);
    }

    fn apply_history(&mut self, slot: usize) {
        match &mut self.history[slot] {
            Edit::Presence { index, detached } => {
                let index = *index;
                if let Some(stroke) = detached.take() {
                    self.strokes.insert(index, stroke);
                    self.count_attached(index);
                } else {
                    let stroke = self.strokes.remove(index);
                    self.count_detached(&stroke);
                    if let Edit::Presence { detached, .. } = &mut self.history[slot] {
                        *detached = Some(stroke);
                    }
                }
            }
            Edit::Move {
                index,
                translation,
                revision,
            } => {
                std::mem::swap(&mut self.strokes[*index].translation, translation);
                std::mem::swap(&mut self.strokes[*index].revision, revision);
            }
            Edit::Order { from, to } => {
                reorder_strokes(&mut self.strokes, *from, *to);
                std::mem::swap(from, to);
            }
            Edit::Scale {
                index,
                scale,
                translation,
                width,
                revision,
            } => {
                let stroke = &mut self.strokes[*index];
                std::mem::swap(&mut stroke.scale, scale);
                std::mem::swap(&mut stroke.translation, translation);
                std::mem::swap(&mut stroke.width, width);
                std::mem::swap(&mut stroke.revision, revision);
            }
            Edit::Paper { rgb } => std::mem::swap(&mut self.paper, rgb),
            Edit::Style {
                index,
                rgb,
                width,
                style,
                revision,
            } => {
                let stroke = &mut self.strokes[*index];
                std::mem::swap(&mut stroke.rgb, rgb);
                std::mem::swap(&mut stroke.width, width);
                std::mem::swap(&mut stroke.style, style);
                std::mem::swap(&mut stroke.revision, revision);
            }
            Edit::Text {
                index,
                points,
                translation,
                rgb,
                width,
                param,
                text,
                revision,
            } => {
                let stroke = &mut self.strokes[*index];
                self.active_text_bytes = self.active_text_bytes - stroke.text.len() + text.len();
                std::mem::swap(&mut stroke.points[0], &mut points[0]);
                std::mem::swap(&mut stroke.points[1], &mut points[1]);
                std::mem::swap(&mut stroke.translation, translation);
                std::mem::swap(&mut stroke.rgb, rgb);
                std::mem::swap(&mut stroke.width, width);
                std::mem::swap(&mut stroke.param, param);
                std::mem::swap(&mut stroke.text, text);
                std::mem::swap(&mut stroke.revision, revision);
            }
            Edit::ObjectLayer {
                from,
                to,
                layer,
                revision,
            } => {
                reorder_strokes(&mut self.strokes, *from, *to);
                let stroke = &mut self.strokes[*to];
                std::mem::swap(&mut stroke.layer, layer);
                std::mem::swap(&mut stroke.revision, revision);
                std::mem::swap(from, to);
            }
            Edit::LayerPresence { .. } => self.apply_layer_presence(slot),
            Edit::LayerOrder { from, to } => {
                reorder_layers(&mut self.layers[..self.layer_count], *from, *to);
                std::mem::swap(from, to);
            }
            Edit::LayerVisibility { position, visible } => {
                std::mem::swap(&mut self.layers[*position].visible, visible);
            }
        }
    }
}

/// Creates a document with logical dimensions independent of any window.
#[no_mangle]
pub extern "C" fn ep_document_new(width: u32, height: u32) -> *mut EpDocument {
    if !(1..=MAX_DIMENSION).contains(&width) || !(1..=MAX_DIMENSION).contains(&height) {
        return ptr::null_mut();
    }
    owned_document(EpDocument::blank(width, height))
}

// Moves a finished document into memory of its own, which ep_document_free
// releases. Allocate explicitly so a recoverable allocation failure can
// return NULL; the document, with every allocation it already owns, is then
// dropped. This allocation uses the same global allocator/layout as
// Box::from_raw.
fn owned_document(document: EpDocument) -> *mut EpDocument {
    let pointer = unsafe { alloc(Layout::new::<EpDocument>()).cast::<EpDocument>() };
    if !pointer.is_null() {
        unsafe { pointer.write(document) };
    }
    pointer
}

/// Creates a new immutable-background document from a canonical PNG. Returns
/// NULL on error; optional out_status is 0 / -1 invalid / -2 allocation failure.
/// Structural checks do not decode pixels: the caller must still validate with
/// an image codec before adopting this candidate. Input bytes are copied once.
///
/// # Safety
/// bytes must address length initialized bytes; out_status, if non-null, must
/// be aligned, writable and disjoint from input. Ownership matches new/free.
#[no_mangle]
pub unsafe extern "C" fn ep_document_from_background_png(
    bytes: *const u8,
    length: usize,
    out_status: *mut i32,
) -> *mut EpDocument {
    let result = if bytes.is_null() || !(57..=MAX_BACKGROUND_BYTES).contains(&length) {
        Err(INVALID)
    } else {
        let bytes = unsafe { slice::from_raw_parts(bytes, length) };
        validate_canonical_png(bytes).and_then(|info| {
            BackgroundPng::copy_validated(info.width, info.height, bytes, crc32(bytes))
        })
    };
    let (document, status) = match result {
        Ok(background) => {
            let document = ep_document_new(background.width, background.height);
            if document.is_null() {
                (ptr::null_mut(), ALLOCATION_FAILURE)
            } else {
                unsafe {
                    // Stable std Arc has no fallible constructor. Only this
                    // small control allocation may abort on system OOM; the
                    // image buffer and document allocation remain fallible.
                    (*document).background = Some(Arc::new(background));
                }
                (document, 0)
            }
        }
        Err(status) => (ptr::null_mut(), status),
    };
    if !out_status.is_null() {
        unsafe {
            out_status.write(status);
        }
    }
    document
}

/// Returns 1 present, 0 absent, -1 invalid. Writes metadata only on 1; no
/// mutation/allocation. Vector indices and counts never include the background.
///
/// # Safety
/// Non-null document must be live/aligned; out_info must address a writable,
/// aligned EpBackgroundInfo, disjoint from document storage.
#[no_mangle]
pub unsafe extern "C" fn ep_background_info(
    document: *const EpDocument,
    out_info: *mut EpBackgroundInfo,
) -> i32 {
    let Some(document) = (unsafe { document.as_ref() }) else {
        return INVALID;
    };
    if out_info.is_null() {
        return INVALID;
    }
    let Some(background) = &document.background else {
        return 0;
    };
    unsafe {
        out_info.write(background.info());
    }
    1
}

/// Copies the entire immutable PNG and returns its size. Returns zero for
/// absent background, invalid inputs or insufficient capacity; no partial write.
///
/// # Safety
/// Non-null document must be live/aligned; out_bytes must address capacity
/// writable bytes, disjoint from document storage and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_copy_background_png(
    document: *const EpDocument,
    out_bytes: *mut u8,
    capacity: usize,
) -> usize {
    let Some(document) = (unsafe { document.as_ref() }) else {
        return 0;
    };
    let Some(background) = &document.background else {
        return 0;
    };
    if out_bytes.is_null() || capacity < background.bytes.len() {
        return 0;
    }
    unsafe {
        ptr::copy_nonoverlapping(background.bytes.as_ptr(), out_bytes, background.bytes.len());
    }
    background.bytes.len()
}

/// Consumes one document; NULL is a no-op.
///
/// # Safety
/// A non-null pointer must be a live, uniquely owned value returned by a
/// document constructor (`ep_document_new`, `ep_document_from_project`,
/// `ep_document_from_background_png`, `ep_document_from_page`), with no active
/// references or concurrent calls.
#[no_mangle]
pub unsafe extern "C" fn ep_document_free(document: *mut EpDocument) {
    if !document.is_null() {
        unsafe { drop(Box::from_raw(document)) };
    }
}

/// Returns zero for NULL.
///
/// # Safety
/// Non-null `document` must be live, aligned, and not concurrently accessed.
#[no_mangle]
pub unsafe extern "C" fn ep_document_width(document: *const EpDocument) -> u32 {
    unsafe { document.as_ref() }.map_or(0, |d| d.width)
}

/// Returns zero for NULL.
///
/// # Safety
/// Non-null `document` must be live, aligned, and not concurrently accessed.
#[no_mangle]
pub unsafe extern "C" fn ep_document_height(document: *const EpDocument) -> u32 {
    unsafe { document.as_ref() }.map_or(0, |d| d.height)
}

/// Returns zero for NULL.
///
/// # Safety
/// Non-null `document` must be live, aligned, and not concurrently accessed.
#[no_mangle]
pub unsafe extern "C" fn ep_stroke_count(document: *const EpDocument) -> usize {
    unsafe { document.as_ref() }.map_or(0, |d| d.strokes.len())
}

/// Returns zero for NULL.
///
/// # Safety
/// Non-null `document` must be live, aligned, and not concurrently accessed.
#[no_mangle]
pub unsafe extern "C" fn ep_redo_count(document: *const EpDocument) -> usize {
    unsafe { document.as_ref() }.map_or(0, |d| d.history.len() - d.cursor)
}

/// Number of undoable actions, not the number of visible objects; zero for NULL.
///
/// # Safety
/// Non-null `document` must be live, aligned, and not concurrently accessed.
#[no_mangle]
pub unsafe extern "C" fn ep_undo_count(document: *const EpDocument) -> usize {
    unsafe { document.as_ref() }.map_or(0, |d| d.cursor)
}

/// A nonzero content-state token unique within this document, or zero for an
/// invalid document/index. Unchanged objects keep tokens when indices shift.
/// Undo/redo restore exact prior tokens; branch edits never reuse them. Tokens
/// are not persisted, so callers must clear caches when replacing a document.
///
/// # Safety
/// Non-null document must be live, aligned and not concurrently accessed.
#[no_mangle]
pub unsafe extern "C" fn ep_object_revision(document: *const EpDocument, index: usize) -> u64 {
    unsafe { document.as_ref() }
        .and_then(|doc| doc.strokes.get(index))
        .map_or(0, |stroke| stroke.revision)
}

/// Copies a complete, valid stroke into the document and clears redo on success.
///
/// # Safety
/// `document` must be NULL or live, aligned, and exclusively accessible.
/// `points` must be NULL or point to `count` initialized, aligned EpPoint values
/// in one live allocation. That allocation must be disjoint from the document
/// and its storage, and remain unchanged for the entire call. Null, invalid
/// scalar values, and limits return errors; dangling pointers are caller errors.
#[no_mangle]
pub unsafe extern "C" fn ep_add_stroke(
    document: *mut EpDocument,
    points: *const EpPoint,
    count: usize,
    rgb: u32,
    width: f32,
) -> i32 {
    unsafe { add_object(document, points, count, rgb, width, FREEHAND_STYLE, 0, &[]) }
}

/// Adds an exact line, rectangle or ellipse, defined by exactly two points.
/// For rectangles/ellipses these are opposite bounding-box corners, any order.
/// Zero-length lines and zero-area rectangles/ellipses are rejected. A
/// contour has at least three points: two cannot make one, so kind 6 is
/// refused here like every kind outside 1..3.
///
/// # Safety
/// Same exclusive document/input rules as ep_add_stroke. Non-null points must
/// contain two initialized EpPoint values; non-null style must contain one
/// initialized EpObjectStyle. Both are copied and must remain stable/disjoint.
#[no_mangle]
pub unsafe extern "C" fn ep_add_shape(
    document: *mut EpDocument,
    points: *const EpPoint,
    style: *const EpObjectStyle,
    rgb: u32,
    width: f32,
) -> i32 {
    let Some(style) = (unsafe { style.as_ref() }) else {
        return INVALID;
    };
    if !(1..=3).contains(&style.kind) {
        return INVALID;
    }
    unsafe { add_object(document, points, 2, rgb, width, *style, 0, &[]) }
}

// What one new object must be, whoever adds it: `add_object` for the
// interface, the document of a colouring page for its zones and lines.
// `text` is already checked by the caller and is empty unless the object is
// a text. The limits of the whole document are checked by each caller.
fn valid_new_object(
    doc: &EpDocument,
    points: &[EpPoint],
    rgb: u32,
    width: f32,
    style: EpObjectStyle,
    param: u32,
    text: &[u8],
) -> bool {
    valid_style(style)
        && (1..=MAX_STROKE_POINTS).contains(&points.len())
        && rgb <= 0x00ff_ffff
        && valid_width(style.kind, width)
        && valid_param(style.kind, param)
        && (style.kind == KIND_TEXT) != text.is_empty()
        && points.iter().all(|point| {
            point.x.is_finite()
                && point.y.is_finite()
                && point.x >= 0.0
                && point.y >= 0.0
                && point.x <= doc.width as f32
                && point.y <= doc.height as f32
        })
        && (style.kind == 0 || valid_shape_points(style.kind, points))
}

// Shared by every constructor of a visible object. `text` is already checked
// by the caller and is empty unless the object is a text.
#[allow(clippy::too_many_arguments)]
unsafe fn add_object(
    document: *mut EpDocument,
    points: *const EpPoint,
    count: usize,
    rgb: u32,
    width: f32,
    style: EpObjectStyle,
    param: u32,
    text: &[u8],
) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    if points.is_null()
        || !(1..=MAX_STROKE_POINTS).contains(&count)
        || doc.strokes.len() >= MAX_STROKES
        || count > MAX_TOTAL_POINTS - doc.active_points
        || text.len() > MAX_TOTAL_TEXT_BYTES - doc.active_text_bytes
        // The active layer is never locked; should that ever break, nothing
        // new joins the page.
        || doc.locked(doc.active_layer)
    {
        return INVALID;
    }
    // count is bounded above, so the byte span cannot exceed isize::MAX.
    let input = unsafe { slice::from_raw_parts(points, count) };
    if !valid_new_object(doc, input, rgb, width, style, param, text) {
        return INVALID;
    }
    let mut owned_points = Vec::new();
    if owned_points.try_reserve_exact(count).is_err() {
        return ALLOCATION_FAILURE;
    }
    owned_points.extend_from_slice(input);
    let mut owned_text = Vec::new();
    if owned_text.try_reserve_exact(text.len()).is_err() {
        return ALLOCATION_FAILURE;
    }
    owned_text.extend_from_slice(text);
    if let Err(status) = doc.prepare_text_edit(count, 1, text.len(), true) {
        return status;
    }
    let needed = doc.strokes.len() + 1;
    if let Err(status) = reserve_bounded(&mut doc.strokes, needed, MAX_STROKES) {
        return status;
    }
    let index = doc.strokes.len();
    let revision = doc.issue_revision();
    doc.strokes.push(Stroke {
        points: owned_points,
        rgb,
        width,
        style,
        scale: 1.0,
        translation: [0.0; 2],
        revision,
        layer: doc.active_layer,
        param,
        text: owned_text,
    });
    doc.count_attached(index);
    doc.commit_text_edit(
        Edit::Presence {
            index,
            detached: None,
        },
        count,
        1,
        text.len(),
    );
    0
}

// A line needs two distinct points; a box (rectangle, ellipse, text, stamp)
// two corners with a width and a height; a contour three points or more
// whose extent has a width and a height.
fn valid_shape_points(kind: u32, points: &[EpPoint]) -> bool {
    if kind == KIND_CONTOUR {
        return points.len() >= 3 && contour_has_area(points.iter().copied());
    }
    if points.len() != 2 {
        return false;
    }
    if kind == 1 {
        points[0].x != points[1].x || points[0].y != points[1].y
    } else {
        points[0].x != points[1].x && points[0].y != points[1].y
    }
}

// Whether the box around these points has a width and a height. Points that
// all lie on one horizontal or vertical line enclose nothing: such a contour
// could never be seen, filled or picked.
fn contour_has_area(points: impl IntoIterator<Item = EpPoint>) -> bool {
    let mut low = [f32::INFINITY; 2];
    let mut high = [f32::NEG_INFINITY; 2];
    for point in points {
        low = [low[0].min(point.x), low[1].min(point.y)];
        high = [high[0].max(point.x), high[1].max(point.y)];
    }
    low[0] < high[0] && low[1] < high[1]
}

/// Computes a page-bounded f32 displacement from the object's exact current
/// geometry, without changing it. This avoids deriving limits from rounded
/// snapshot coordinates. Mutating move/duplicate APIs remain strictly bounded.
/// Returns 0 success, -1 invalid input, an object of a locked layer (which
/// never moves) or rounded-degenerate result. Output is unchanged on error;
/// document, revisions and history are always unchanged.
///
/// # Safety
/// Non-null document must be live, aligned and not concurrently accessed.
/// Non-null out_delta must be writable/aligned for one EpPoint and disjoint
/// from document-owned storage and other inputs.
#[no_mangle]
pub unsafe extern "C" fn ep_constrain_object_movement(
    document: *const EpDocument,
    index: usize,
    dx: f32,
    dy: f32,
    out_delta: *mut EpPoint,
) -> i32 {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return INVALID;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return INVALID;
    };
    if out_delta.is_null() || !dx.is_finite() || !dy.is_finite() || doc.locked(stroke.layer) {
        return INVALID;
    }
    let mut low = [f64::NEG_INFINITY; 2];
    let mut high = [f64::INFINITY; 2];
    for point in &stroke.points {
        for (axis, (base, size)) in [(point.x, doc.width), (point.y, doc.height)]
            .into_iter()
            .enumerate()
        {
            let current = f64::from(base) * stroke.scale + stroke.translation[axis];
            low[axis] = low[axis].max(-current);
            high[axis] = high[axis].min(f64::from(size) - current);
        }
    }
    let mut delta = [0.0f32; 2];
    for (axis, requested) in [dx, dy].into_iter().enumerate() {
        let rounded = f64::from(requested).clamp(low[axis], high[axis]) as f32;
        // Choose a representable value inside the exact interval. One adjacent
        // f32 step suffices because round-to-nearest chose one of its endpoints.
        // This is directed rounding, not an arbitrary epsilon or point clipping.
        delta[axis] = if f64::from(rounded) < low[axis] {
            rounded.next_up()
        } else if f64::from(rounded) > high[axis] {
            rounded.next_down()
        } else {
            rounded
        };
    }
    if stroke
        .moved_translation(delta[0], delta[1], doc.width, doc.height)
        .is_none()
    {
        return INVALID;
    }
    unsafe {
        out_delta.write(EpPoint {
            x: delta[0],
            y: delta[1],
        });
    }
    0
}

/// Translates one visible object without clipping. Returns 1 changed, 0 no-op,
/// -1 invalid input / an object of a locked layer / limits, -2 allocation
/// failure. No-op/error retains redo.
///
/// # Safety
/// Non-null document must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_move_object(
    document: *mut EpDocument,
    index: usize,
    dx: f32,
    dy: f32,
) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return INVALID;
    };
    if doc.locked(stroke.layer) {
        return INVALID;
    }
    let Some(next) = stroke.moved_translation(dx, dy, doc.width, doc.height) else {
        return INVALID;
    };
    if next == stroke.translation
        || stroke
            .points
            .iter()
            .enumerate()
            .all(|(i, point)| stroke.point_at(i) == Stroke::transformed(*point, stroke.scale, next))
    {
        return 0;
    }
    let previous = stroke.translation;
    let previous_revision = stroke.revision;
    if let Err(status) = doc.prepare_edit(0, 0, true) {
        return status;
    }
    doc.strokes[index].translation = next;
    doc.strokes[index].revision = doc.issue_revision();
    doc.commit_edit(
        Edit::Move {
            index,
            translation: previous,
            revision: previous_revision,
        },
        0,
        0,
    );
    1
}

// Callers validate both indices, or restore a validated history state first.
// Rotate only object descriptors; point buffers remain owned once and in place.
fn reorder_strokes(strokes: &mut [Stroke], from: usize, to: usize) {
    if from < to {
        strokes[from..=to].rotate_left(1);
    } else {
        strokes[to..=from].rotate_right(1);
    }
}

/// Moves one visible object to its final index, preserving all other relative
/// order. Index 0 is backmost; the last index is frontmost, above the fixed PNG.
/// Geometry, style and content revisions do not change. Returns 1 changed,
/// 0 valid same-index no-op, -1 invalid input / an object of a locked layer at
/// `from` / limits, -2 allocation failure. Objects of a locked layer may shift
/// in the list when another object passes them: their order among themselves,
/// which is all that paints them, never changes.
/// No-op/error retains undo and redo. Only the history reserve may allocate;
/// applying/undoing/redoing the order rotates at most 10000 object descriptors.
///
/// # Safety
/// Non-null document must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_reorder_object(
    document: *mut EpDocument,
    from: usize,
    to: usize,
) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    if from >= doc.strokes.len() || to >= doc.strokes.len() || doc.locked(doc.strokes[from].layer) {
        return INVALID;
    }
    if from == to {
        return 0;
    }
    if let Err(status) = doc.prepare_edit(0, 0, false) {
        return status;
    }
    reorder_strokes(&mut doc.strokes, from, to);
    doc.commit_edit(Edit::Order { from: to, to: from }, 0, 0);
    1
}

/// Removes one visible object, retaining its ownership for undo.
/// Returns 1 changed, -1 invalid index / an object of a locked layer /
/// limits, -2 allocation failure.
///
/// # Safety
/// Non-null document must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_remove_object(document: *mut EpDocument, index: usize) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    if index >= doc.strokes.len() || doc.locked(doc.strokes[index].layer) {
        return INVALID;
    }
    if let Err(status) = doc.prepare_edit(0, 0, false) {
        return status;
    }
    let stroke = doc.strokes.remove(index);
    doc.count_detached(&stroke);
    doc.commit_edit(
        Edit::Presence {
            index,
            detached: Some(stroke),
        },
        0,
        0,
    );
    1
}

/// Appends an independent copy of one object, translated by dx/dy. Copying is
/// necessary only for this new geometry; its later edits do not clone points.
/// Returns 1 changed, -1 invalid input / an object of a locked layer, whose
/// copy would join that layer / limits, -2 allocation failure.
///
/// # Safety
/// Non-null document must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_duplicate_object(
    document: *mut EpDocument,
    index: usize,
    dx: f32,
    dy: f32,
) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return INVALID;
    };
    if doc.locked(stroke.layer) {
        return INVALID;
    }
    let Some(translation) = stroke.moved_translation(dx, dy, doc.width, doc.height) else {
        return INVALID;
    };
    let count = stroke.points.len();
    let text_bytes = stroke.text.len();
    if doc.strokes.len() >= MAX_STROKES
        || count > MAX_TOTAL_POINTS - doc.active_points
        || text_bytes > MAX_TOTAL_TEXT_BYTES - doc.active_text_bytes
    {
        return INVALID;
    }
    let mut points = Vec::new();
    if points.try_reserve_exact(count).is_err() {
        return ALLOCATION_FAILURE;
    }
    points.extend_from_slice(&stroke.points);
    let mut text = Vec::new();
    if text.try_reserve_exact(text_bytes).is_err() {
        return ALLOCATION_FAILURE;
    }
    text.extend_from_slice(&stroke.text);
    // The copy stays on its source's layer, in front of that layer's objects.
    let mut duplicate = Stroke {
        points,
        rgb: stroke.rgb,
        width: stroke.width,
        style: stroke.style,
        scale: stroke.scale,
        translation,
        revision: 0,
        layer: stroke.layer,
        param: stroke.param,
        text,
    };
    if let Err(status) = doc.prepare_text_edit(count, 1, text_bytes, true) {
        return status;
    }
    let index = doc.strokes.len();
    if let Err(status) = reserve_bounded(&mut doc.strokes, index + 1, MAX_STROKES) {
        return status;
    }
    duplicate.revision = doc.issue_revision();
    doc.strokes.push(duplicate);
    doc.count_attached(index);
    doc.commit_text_edit(
        Edit::Presence {
            index,
            detached: None,
        },
        count,
        1,
        text_bytes,
    );
    1
}

/// Updates outline/fill without changing the object's kind. Identical style
/// is a no-op. Returns 1 changed, 0 no-op, -1 invalid / limits, -2 allocation.
/// An object of a locked layer keeps its outline and its kind of fill: only
/// the colour of a fill it already has may change, the same `rgb` and
/// `width` being passed back, as the paint pot does to a zone of a colouring
/// page. Any other change of such an object is -1.
///
/// # Safety
/// Non-null document must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_set_object_style(
    document: *mut EpDocument,
    index: usize,
    rgb: u32,
    width: f32,
    fill_enabled: u32,
    fill_rgb: u32,
) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return INVALID;
    };
    let style = EpObjectStyle {
        kind: stroke.style.kind,
        fill_enabled,
        fill_rgb,
    };
    // A text keeps its size and a stamp its constant width here: only their
    // colour changes. ep_set_text replaces a text's size together with its box.
    if rgb > 0x00ff_ffff
        || !valid_width(style.kind, width)
        || (stroke.extended() && width != stroke.width)
        || !valid_style(style)
    {
        return INVALID;
    }
    // A page keeps its drawing: on a locked layer, a filled zone may change
    // the colour inside it and nothing else, whatever the interface asks.
    if doc.locked(stroke.layer)
        && (stroke.style.fill_enabled != 1
            || fill_enabled != 1
            || rgb != stroke.rgb
            || width != stroke.width)
    {
        return INVALID;
    }
    if stroke.rgb == rgb && stroke.width == width && stroke.style == style {
        return 0;
    }
    let inverse = Edit::Style {
        index,
        rgb: stroke.rgb,
        width: stroke.width,
        style: stroke.style,
        revision: stroke.revision,
    };
    if let Err(status) = doc.prepare_edit(0, 0, true) {
        return status;
    }
    let revision = doc.issue_revision();
    let stroke = &mut doc.strokes[index];
    stroke.rgb = rgb;
    stroke.width = width;
    stroke.style = style;
    stroke.revision = revision;
    doc.commit_edit(inverse, 0, 0);
    1
}

/// Returns 1 changed, 0 empty history, -1 NULL.
///
/// # Safety
/// Non-null `document` must be live, aligned, and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_undo(document: *mut EpDocument) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    if doc.cursor == 0 {
        return 0;
    }
    doc.cursor -= 1;
    doc.apply_history(doc.cursor);
    1
}

/// Returns 1 changed, 0 empty redo, -1 NULL.
///
/// # Safety
/// Non-null `document` must be live, aligned, and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_redo(document: *mut EpDocument) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    if doc.cursor == doc.history.len() {
        return 0;
    }
    doc.apply_history(doc.cursor);
    doc.cursor += 1;
    1
}

/// Writes metadata only on success; returns zero or -1.
///
/// # Safety
/// Non-null `document` must be live, aligned, and not concurrently accessed.
/// Non-null `out_info` must be writable/aligned for one EpStrokeInfo, disjoint
/// from document storage, and exclusively accessible during the call.
#[no_mangle]
pub unsafe extern "C" fn ep_stroke_info(
    document: *const EpDocument,
    index: usize,
    out_info: *mut EpStrokeInfo,
) -> i32 {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return INVALID;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return INVALID;
    };
    if out_info.is_null() {
        return INVALID;
    }
    unsafe {
        out_info.write(EpStrokeInfo {
            rgb: stroke.rgb,
            width: stroke.width,
            point_count: stroke.points.len(),
        });
    }
    0
}

/// Copies the object's kind and optional fill without changing EpStrokeInfo.
/// Returns zero on success, -1 invalid document/index/output; no partial write.
///
/// # Safety
/// Document must be live and not concurrently accessed; output must be writable
/// for one aligned EpObjectStyle and disjoint from document-owned storage.
#[no_mangle]
pub unsafe extern "C" fn ep_object_style(
    document: *const EpDocument,
    index: usize,
    out_style: *mut EpObjectStyle,
) -> i32 {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return INVALID;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return INVALID;
    };
    if out_style.is_null() {
        return INVALID;
    }
    unsafe { out_style.write(stroke.style) };
    0
}

/// Copies a whole stroke or writes nothing and returns zero.
///
/// # Safety
/// Non-null `document` must be live, aligned, and not concurrently accessed.
/// Non-null `out_points` must be writable/aligned for `capacity` EpPoint values
/// in one live allocation, disjoint from document storage, and exclusively
/// accessible for this call. No partial copy is made for insufficient capacity.
#[no_mangle]
pub unsafe extern "C" fn ep_copy_points(
    document: *const EpDocument,
    index: usize,
    out_points: *mut EpPoint,
    capacity: usize,
) -> usize {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return 0;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return 0;
    };
    if out_points.is_null() || capacity < stroke.points.len() {
        return 0;
    }
    if stroke.scale == 1.0 && stroke.translation == [0.0; 2] {
        unsafe {
            ptr::copy_nonoverlapping(stroke.points.as_ptr(), out_points, stroke.points.len());
        }
    } else {
        for index in 0..stroke.points.len() {
            unsafe {
                out_points.add(index).write(stroke.point_at(index));
            }
        }
    }
    stroke.points.len()
}

// Called only after the entire SVG capacity (including base64) is reserved.
// Append directly into the final output, avoiding another full encoded asset.
fn append_base64(output: &mut String, bytes: &[u8]) {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for chunk in bytes.chunks(3) {
        let a = chunk[0];
        let b = chunk.get(1).copied().unwrap_or(0);
        let c = chunk.get(2).copied().unwrap_or(0);
        output.push(ALPHABET[(a >> 2) as usize] as char);
        output.push(ALPHABET[(((a & 3) << 4) | (b >> 4)) as usize] as char);
        output.push(if chunk.len() > 1 {
            ALPHABET[(((b & 15) << 2) | (c >> 6)) as usize] as char
        } else {
            '='
        });
        output.push(if chunk.len() > 2 {
            ALPHABET[(c & 63) as usize] as char
        } else {
            '='
        });
    }
}

// Bounded by construction: decimal f32 coordinates (including subnormal
// values), fixed markup, escaped text and catalogue paths of known length.
fn svg_capacity(doc: &EpDocument) -> Option<usize> {
    let mut capacity = doc
        .active_points
        .checked_mul(128)?
        .checked_add(doc.strokes.len().checked_mul(256)?)?
        .checked_add(512)?
        // Each layer group opens and closes once; `&quot;` is the longest escape.
        .checked_add(doc.layer_count.checked_mul(64)?)?
        .checked_add(doc.active_text_bytes.checked_mul(6)?)?;
    for stroke in &doc.strokes {
        capacity = capacity.checked_add(match stroke.style.kind {
            KIND_TEXT => text_svg_bytes(&stroke.text),
            KIND_STAMP => stamp_svg_bytes(stroke.param),
            _ => 0,
        })?;
    }
    if let Some(background) = &doc.background {
        capacity = capacity
            .checked_add(
                background
                    .bytes
                    .len()
                    .checked_add(2)?
                    .checked_div(3)?
                    .checked_mul(4)?,
            )?
            .checked_add(256)?;
    }
    Some(capacity)
}

fn write_object_svg(result: &mut String, stroke: &Stroke) -> Option<()> {
    if stroke.style.kind == KIND_TEXT || stroke.style.kind == KIND_STAMP {
        let a = stroke.point_at(0);
        let b = stroke.point_at(1);
        let x = f64::from(a.x.min(b.x));
        let y = f64::from(a.y.min(b.y));
        let width = f64::from(a.x.max(b.x)) - x;
        let height = f64::from(a.y.max(b.y)) - y;
        return if stroke.style.kind == KIND_TEXT {
            write_text_svg(result, &stroke.text, x, y, stroke.width, stroke.rgb)
        } else {
            write_stamp_svg(result, stroke.param, stroke.rgb, x, y, width, height)
        };
    }
    if stroke.style.kind != 0 {
        let a = stroke.point_at(0);
        let b = stroke.point_at(1);
        let x = f64::from(a.x.min(b.x));
        let y = f64::from(a.y.min(b.y));
        let width = f64::from(a.x.max(b.x)) - x;
        let height = f64::from(a.y.max(b.y)) - y;
        match stroke.style.kind {
            1 => write!(
                result,
                "<line x1=\"{}\" y1=\"{}\" x2=\"{}\" y2=\"{}\"",
                a.x, a.y, b.x, b.y
            )
            .ok()?,
            2 => write!(
                result,
                "<rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\"",
                x, y, width, height
            )
            .ok()?,
            3 => write!(
                result,
                "<ellipse cx=\"{}\" cy=\"{}\" rx=\"{}\" ry=\"{}\"",
                x + width / 2.0,
                y + height / 2.0,
                width / 2.0,
                height / 2.0
            )
            .ok()?,
            // The freehand path of all its points, closed back to the first,
            // with the fill and outline of the other shapes.
            KIND_CONTOUR => {
                result.push_str("<path d=\"");
                for index in 0..stroke.points.len() {
                    let point = stroke.point_at(index);
                    write!(
                        result,
                        "{}{} {} ",
                        if index == 0 { 'M' } else { 'L' },
                        point.x,
                        point.y
                    )
                    .ok()?;
                }
                result.push_str("Z\"");
            }
            _ => return None, // Internal invariant, never accepted from files.
        }
        if stroke.style.fill_enabled == 1 {
            write!(result, " fill=\"#{:06x}\"", stroke.style.fill_rgb).ok()?;
        } else {
            write!(result, " fill=\"none\"").ok()?;
        }
        writeln!(result, " stroke=\"#{:06x}\" stroke-width=\"{}\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>", stroke.rgb, stroke.width).ok()?;
    } else if stroke.points.len() == 1 {
        let point = stroke.point_at(0);
        writeln!(
            result,
            "<circle cx=\"{}\" cy=\"{}\" r=\"{}\" fill=\"#{:06x}\"/>",
            point.x,
            point.y,
            stroke.width / 2.0,
            stroke.rgb
        )
        .ok()?;
    } else {
        write!(result, "<path d=\"").ok()?;
        for index in 0..stroke.points.len() {
            let point = stroke.point_at(index);
            write!(
                result,
                "{}{} {} ",
                if index == 0 { 'M' } else { 'L' },
                point.x,
                point.y
            )
            .ok()?;
        }
        writeln!(
            result,
            "\" fill=\"none\" stroke=\"#{:06x}\" stroke-width=\"{}\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>",
            stroke.rgb, stroke.width
        )
        .ok()?;
    }
    Some(())
}

fn svg(doc: &EpDocument) -> Option<CString> {
    let mut result = String::new();
    result.try_reserve_exact(svg_capacity(doc)?).ok()?;
    writeln!(result, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>").ok()?;
    writeln!(
        result,
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 {} {}\" width=\"{}\" height=\"{}\">",
        doc.width, doc.height, doc.width, doc.height
    )
    .ok()?;
    writeln!(
        result,
        "<rect width=\"100%\" height=\"100%\" fill=\"#{:06x}\"/>",
        doc.paper
    )
    .ok()?;
    if let Some(background) = &doc.background {
        write!(
            result,
            "<image x=\"0\" y=\"0\" width=\"{}\" height=\"{}\" href=\"data:image/png;base64,",
            background.width, background.height
        )
        .ok()?;
        append_base64(&mut result, &background.bytes);
        result.push_str("\"/>\n");
    }
    if doc.single_plain_layer() {
        // Unchanged output for every drawing without layers.
        for stroke in &doc.strokes {
            write_object_svg(&mut result, stroke)?;
        }
    } else {
        // Bottom to top; a hidden layer is left out, as on the sheet.
        for layer in doc.layers().iter().filter(|layer| layer.visible) {
            writeln!(result, "<g id=\"calque-{}\">", u32::from(layer.id) + 1).ok()?;
            for stroke in doc.strokes.iter().filter(|s| s.layer == layer.id) {
                write_object_svg(&mut result, stroke)?;
            }
            result.push_str("</g>\n");
        }
    }
    result.push_str("</svg>\n");
    // Content is fixed markup, formatted validated numbers or escaped validated
    // text without NUL. Append the sentinel ourselves to avoid allocating.
    let mut bytes = result.into_bytes();
    bytes.push(0);
    CString::from_vec_with_nul(bytes).ok()
}

/// Returns a Rust-owned, NUL-terminated UTF-8 SVG, or NULL on failure.
///
/// # Safety
/// Non-null `document` must be live, aligned, and not concurrently accessed.
/// The returned pointer must be released once with `ep_string_free`, never C
/// free(), and must not be modified or used after release.
#[no_mangle]
pub unsafe extern "C" fn ep_export_svg(document: *const EpDocument) -> *mut c_char {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return ptr::null_mut();
    };
    svg(doc).map_or(ptr::null_mut(), CString::into_raw)
}

/// Consumes a string returned by `ep_export_svg`; NULL is a no-op.
///
/// # Safety
/// Non-null `string` must be an unmodified, live result of `ep_export_svg`, with
/// its original terminating NUL, and must not have been freed previously.
#[no_mangle]
pub unsafe extern "C" fn ep_string_free(string: *mut c_char) {
    if !string.is_null() {
        unsafe { drop(CString::from_raw(string)) };
    }
}

// Standard CRC-32/ISO-HDLC, table calculated at compile time (no dependencies).
// This detects accidental corruption; it is not an authenticity signature.
const fn crc_tables() -> [[u32; 256]; 8] {
    let mut tables = [[0; 256]; 8];
    let mut index = 0;
    while index < 256 {
        let mut value = index as u32;
        let mut bit = 0;
        while bit < 8 {
            value = (value >> 1) ^ (0xedb8_8320 & 0u32.wrapping_sub(value & 1));
            bit += 1;
        }
        tables[0][index] = value;
        index += 1;
    }
    let mut slice = 1;
    while slice < 8 {
        index = 0;
        while index < 256 {
            let value = tables[slice - 1][index];
            tables[slice][index] = tables[0][(value & 0xff) as usize] ^ (value >> 8);
            index += 1;
        }
        slice += 1;
    }
    tables
}
const CRC_TABLES: [[u32; 256]; 8] = crc_tables();

fn crc32(bytes: &[u8]) -> u32 {
    let mut crc = u32::MAX;
    // Slicing-by-8 reduces the serial dependency chain with 8 KiB of immutable
    // tables. Explicit byte reads work on every alignment and endianness, with
    // no CPU-specific intrinsics or changes to the stored checksum convention.
    let (chunks, remainder) = bytes.as_chunks::<8>();
    for chunk in chunks {
        let first = u32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]) ^ crc;
        crc = CRC_TABLES[7][(first & 0xff) as usize]
            ^ CRC_TABLES[6][((first >> 8) & 0xff) as usize]
            ^ CRC_TABLES[5][((first >> 16) & 0xff) as usize]
            ^ CRC_TABLES[4][(first >> 24) as usize]
            ^ CRC_TABLES[3][chunk[4] as usize]
            ^ CRC_TABLES[2][chunk[5] as usize]
            ^ CRC_TABLES[1][chunk[6] as usize]
            ^ CRC_TABLES[0][chunk[7] as usize];
    }
    for byte in remainder {
        crc = CRC_TABLES[0][((crc ^ u32::from(*byte)) & 0xff) as usize] ^ (crc >> 8);
    }
    !crc
}

// CRC-32/ISO-HDLC concatenation over final (complemented) CRCs. Cache the
// powers of the zero-byte operator at compile time (8 KiB on 64-bit), avoiding
// matrix construction on every save, including small-image projects.
const fn crc_matrix_times(matrix: &[u32; 32], mut vector: u32) -> u32 {
    let mut sum = 0;
    let mut index = 0;
    while vector != 0 {
        if vector & 1 != 0 {
            sum ^= matrix[index];
        }
        vector >>= 1;
        index += 1;
    }
    sum
}
const fn crc_matrix_square(matrix: &[u32; 32]) -> [u32; 32] {
    let mut result = [0; 32];
    let mut index = 0;
    while index < 32 {
        result[index] = crc_matrix_times(matrix, matrix[index]);
        index += 1;
    }
    result
}
const fn crc_byte_powers() -> [[u32; 32]; usize::BITS as usize] {
    let mut bit = [0; 32];
    bit[0] = 0xedb8_8320;
    let mut index = 1;
    while index < 32 {
        bit[index] = 1 << (index - 1);
        index += 1;
    }
    let mut powers = [[0; 32]; usize::BITS as usize];
    powers[0] = crc_matrix_square(&crc_matrix_square(&crc_matrix_square(&bit)));
    index = 1;
    while index < powers.len() {
        powers[index] = crc_matrix_square(&powers[index - 1]);
        index += 1;
    }
    powers
}
const CRC_BYTE_POWERS: [[u32; 32]; usize::BITS as usize] = crc_byte_powers();
fn crc32_combine(mut left: u32, right: u32, mut right_len: usize) -> u32 {
    if right_len == 0 {
        return left;
    }
    let mut index = 0;
    while right_len != 0 {
        if right_len & 1 != 0 {
            left = crc_matrix_times(&CRC_BYTE_POWERS[index], left);
        }
        right_len >>= 1;
        index += 1;
    }
    left ^ right
}

fn project_size(doc: &EpDocument) -> usize {
    // Invariants are established by add/load and preserved by history moves.
    if doc.needs_layered_project() {
        return LAYERED_PROJECT_HEADER_BYTES
            + doc.layer_count * 8
            + doc.strokes.len() * LAYERED_OBJECT_BYTES
            + doc.active_points * 8
            + doc.active_text_bytes
            + doc.background.as_ref().map_or(0, |b| b.bytes.len())
            + 4;
    }
    PROJECT_MIN_BYTES
        + doc.strokes.len() * 24
        + doc.active_points * 8
        + doc
            .background
            .as_ref()
            .map_or(0, |background| 16 + background.bytes.len())
}

/// Returns the exact byte count for the visible drawing, or zero for NULL.
/// Redo is intentionally excluded. No allocation or mutation occurs.
///
/// # Safety
/// Non-null `document` must be live, aligned, and not concurrently accessed.
#[no_mangle]
pub unsafe extern "C" fn ep_project_size(document: *const EpDocument) -> usize {
    unsafe { document.as_ref() }.map_or(0, project_size)
}

/// Writes v2 without a background, v3 with one, v4 as soon as the drawing
/// uses layers, a text or a stamp, and v5 as soon as it has a locked layer
/// or a contour, into caller-owned memory. Returns zero
/// on success, -1 on NULL or insufficient capacity; output is unchanged on error.
/// No allocation occurs. Bytes after the exact project size are untouched.
///
/// # Safety
/// Non-null `document` must be live, aligned, and not concurrently accessed.
/// Non-null `out_bytes` must be writable for `capacity` bytes in one allocation,
/// disjoint from document storage, and exclusively accessible during this call.
#[no_mangle]
pub unsafe extern "C" fn ep_copy_project(
    document: *const EpDocument,
    out_bytes: *mut u8,
    capacity: usize,
) -> i32 {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return INVALID;
    };
    unsafe { copy_project(doc, out_bytes, capacity) }
}

// Shared serializer for exclusively owned documents and immutable snapshots.
// Only the output requires exclusive access; all drawing data is read-only.
unsafe fn copy_project(doc: &EpDocument, out_bytes: *mut u8, capacity: usize) -> i32 {
    let size = project_size(doc);
    if out_bytes.is_null() || capacity < size {
        return INVALID;
    }
    // Use only the bounded size, not a potentially unbounded caller capacity.
    let output = unsafe { slice::from_raw_parts_mut(out_bytes, size) };
    output[..8].copy_from_slice(PROJECT_MAGIC);
    if doc.needs_layered_project() {
        copy_layered_project(doc, output);
        return 0;
    }
    let version = if doc.background.is_some() {
        HYBRID_PROJECT_VERSION
    } else {
        PROJECT_VERSION
    };
    output[8..10].copy_from_slice(&version.to_le_bytes());
    output[10..12].copy_from_slice(&0u16.to_le_bytes());
    output[12..16].copy_from_slice(&(size as u32).to_le_bytes());
    output[16..20].copy_from_slice(&doc.width.to_le_bytes());
    output[20..24].copy_from_slice(&doc.height.to_le_bytes());
    output[24..28].copy_from_slice(&(doc.strokes.len() as u32).to_le_bytes());
    output[28..32].copy_from_slice(&(doc.active_points as u32).to_le_bytes());
    let mut cursor = PROJECT_HEADER_BYTES;
    if let Some(background) = &doc.background {
        output[32..36].copy_from_slice(&1u32.to_le_bytes());
        output[36..40].copy_from_slice(&(background.bytes.len() as u32).to_le_bytes());
        output[40..44].copy_from_slice(&background.width.to_le_bytes());
        output[44..48].copy_from_slice(&background.height.to_le_bytes());
        cursor = HYBRID_PROJECT_HEADER_BYTES;
    }
    for stroke in &doc.strokes {
        output[cursor..cursor + 4].copy_from_slice(&stroke.rgb.to_le_bytes());
        output[cursor + 4..cursor + 8].copy_from_slice(&stroke.width.to_le_bytes());
        output[cursor + 8..cursor + 12]
            .copy_from_slice(&(stroke.points.len() as u32).to_le_bytes());
        output[cursor + 12..cursor + 16].copy_from_slice(&stroke.style.kind.to_le_bytes());
        output[cursor + 16..cursor + 20].copy_from_slice(&stroke.style.fill_enabled.to_le_bytes());
        output[cursor + 20..cursor + 24].copy_from_slice(&stroke.style.fill_rgb.to_le_bytes());
        cursor += 24;
        for index in 0..stroke.points.len() {
            let point = stroke.point_at(index);
            output[cursor..cursor + 4].copy_from_slice(&point.x.to_le_bytes());
            output[cursor + 4..cursor + 8].copy_from_slice(&point.y.to_le_bytes());
            cursor += 8;
        }
    }
    // The immutable PNG checksum is cached once. Compute the changing vector
    // prefix and combine CRCs without rescanning the large image after its copy.
    let mut checksum = crc32(&output[..cursor]);
    if let Some(background) = &doc.background {
        output[cursor..cursor + background.bytes.len()].copy_from_slice(&background.bytes);
        cursor += background.bytes.len();
        checksum = crc32_combine(checksum, background.crc, background.bytes.len());
    }
    output[cursor..cursor + 4].copy_from_slice(&checksum.to_le_bytes());
    0
}

// The header word of the sheet's colour: zero for white, the only form of a
// white sheet, otherwise the colour with bit 24 set so that black is distinct.
fn paper_word(paper: u32) -> u32 {
    if paper == WHITE_PAPER {
        0
    } else {
        0x0100_0000 | paper
    }
}

// Version 4: header, layer table, 36-byte object records each followed by its
// points and characters, optional PNG, final CRC32 of everything before it.
// Version 5 is the same layout, written for a locked layer or a contour.
fn copy_layered_project(doc: &EpDocument, output: &mut [u8]) {
    fn put(output: &mut [u8], cursor: &mut usize, value: u32) {
        output[*cursor..*cursor + 4].copy_from_slice(&value.to_le_bytes());
        *cursor += 4;
    }
    let version = if doc.needs_locked_project() {
        LOCKED_PROJECT_VERSION
    } else {
        LAYERED_PROJECT_VERSION
    };
    output[8..10].copy_from_slice(&version.to_le_bytes());
    output[10..12].copy_from_slice(&0u16.to_le_bytes());
    let mut cursor = 12;
    let background_bytes = doc.background.as_ref().map_or(0, |b| b.bytes.len());
    for value in [
        output.len(),
        doc.width as usize,
        doc.height as usize,
        doc.strokes.len(),
        doc.active_points,
        background_bytes,
        doc.layer_count,
        doc.active_text_bytes,
        usize::from(doc.active_layer),
        paper_word(doc.paper) as usize,
        0,
    ] {
        put(output, &mut cursor, value as u32);
    }
    for layer in doc.layers() {
        put(output, &mut cursor, u32::from(layer.id));
        // Bit 0 visible, bit 1 locked: a locked layer makes the file v5, so
        // a v4 file keeps its 0/1 visibility word.
        put(
            output,
            &mut cursor,
            u32::from(layer.visible) | (u32::from(layer.locked) << 1),
        );
    }
    for stroke in &doc.strokes {
        put(output, &mut cursor, stroke.rgb);
        put(output, &mut cursor, stroke.width.to_bits());
        put(output, &mut cursor, stroke.points.len() as u32);
        put(output, &mut cursor, stroke.style.kind);
        put(output, &mut cursor, stroke.style.fill_enabled);
        put(output, &mut cursor, stroke.style.fill_rgb);
        put(output, &mut cursor, u32::from(stroke.layer));
        put(output, &mut cursor, stroke.param);
        put(output, &mut cursor, stroke.text.len() as u32);
        for index in 0..stroke.points.len() {
            let point = stroke.point_at(index);
            put(output, &mut cursor, point.x.to_bits());
            put(output, &mut cursor, point.y.to_bits());
        }
        output[cursor..cursor + stroke.text.len()].copy_from_slice(&stroke.text);
        cursor += stroke.text.len();
    }
    let mut checksum = crc32(&output[..cursor]);
    if let Some(background) = &doc.background {
        output[cursor..cursor + background.bytes.len()].copy_from_slice(&background.bytes);
        cursor += background.bytes.len();
        checksum = crc32_combine(checksum, background.crc, background.bytes.len());
    }
    output[cursor..cursor + 4].copy_from_slice(&checksum.to_le_bytes());
}

// All reads are bounds-checked before conversion, including on malformed input.
struct ProjectReader<'a> {
    bytes: &'a [u8],
    cursor: usize,
}
impl<'a> ProjectReader<'a> {
    fn u32(&mut self) -> Result<u32, i32> {
        let end = self.cursor.checked_add(4).ok_or(INVALID)?;
        let value = self.bytes.get(self.cursor..end).ok_or(INVALID)?;
        self.cursor = end;
        Ok(u32::from_le_bytes(value.try_into().map_err(|_| INVALID)?))
    }
    fn f32(&mut self) -> Result<f32, i32> {
        self.u32().map(f32::from_bits)
    }
    fn take(&mut self, length: usize) -> Result<&'a [u8], i32> {
        let end = self.cursor.checked_add(length).ok_or(INVALID)?;
        let value = self.bytes.get(self.cursor..end).ok_or(INVALID)?;
        self.cursor = end;
        Ok(value)
    }
}

struct ProjectHeader {
    version: u16,
    width: u32,
    height: u32,
    strokes: usize,
    points: usize,
    header_bytes: usize,
    background_start: usize,
    background_bytes: usize,
    background_crc: u32,
    layers: [Layer; MAX_LAYERS],
    layer_count: usize,
    active_layer: u8,
    text_bytes: usize,
    extended: usize,
    contours: usize,
    paper: u32,
}

// Fixed part of one object record, common to every version.
struct ObjectRecord {
    rgb: u32,
    width: f32,
    count: usize,
    style: EpObjectStyle,
    layer: u8,
    param: u32,
    text_bytes: usize,
}

fn read_record(reader: &mut ProjectReader<'_>, version: u16) -> Result<ObjectRecord, i32> {
    let rgb = reader.u32()?;
    let width = reader.f32()?;
    let count = reader.u32()? as usize;
    let style = read_style(reader, version)?;
    let (layer, param, text_bytes) = if version >= LAYERED_PROJECT_VERSION {
        let layer = reader.u32()?;
        (
            u8::try_from(layer).map_err(|_| INVALID)?,
            reader.u32()?,
            reader.u32()? as usize,
        )
    } else {
        (0, 0, 0)
    };
    Ok(ObjectRecord {
        rgb,
        width,
        count,
        style,
        layer,
        param,
        text_bytes,
    })
}

fn read_style(reader: &mut ProjectReader<'_>, version: u16) -> Result<EpObjectStyle, i32> {
    if version == 1 {
        return Ok(FREEHAND_STYLE);
    }
    Ok(EpObjectStyle {
        kind: reader.u32()?,
        fill_enabled: reader.u32()?,
        fill_rgb: reader.u32()?,
    })
}

// First pass validates the entire file without allocating document storage.
// The second pass constructs each stroke once, never calling add/snapshot.
fn validate_project(bytes: &[u8]) -> Result<ProjectHeader, i32> {
    if !(PROJECT_MIN_BYTES..=MAX_PROJECT_BYTES).contains(&bytes.len())
        || bytes.get(..8) != Some(PROJECT_MAGIC.as_slice())
        || bytes[10..12] != [0, 0]
    {
        return Err(INVALID);
    }
    let version = u16::from_le_bytes([bytes[8], bytes[9]]);
    if !(1..=LOCKED_PROJECT_VERSION).contains(&version) {
        return Err(INVALID);
    }
    // Versions 4 and 5 share their layout; 5 adds locks and contours.
    let layered = version >= LAYERED_PROJECT_VERSION;
    if !layered && bytes.len() > MAX_HYBRID_PROJECT_BYTES {
        return Err(INVALID);
    }
    let payload_end = bytes.len() - 4;
    let mut reader = ProjectReader { bytes, cursor: 12 };
    if reader.u32()? as usize != bytes.len() {
        return Err(INVALID);
    }
    let mut header = ProjectHeader {
        version,
        width: reader.u32()?,
        height: reader.u32()?,
        strokes: reader.u32()? as usize,
        points: reader.u32()? as usize,
        header_bytes: match version {
            LAYERED_PROJECT_VERSION | LOCKED_PROJECT_VERSION => LAYERED_PROJECT_HEADER_BYTES,
            HYBRID_PROJECT_VERSION => HYBRID_PROJECT_HEADER_BYTES,
            _ => PROJECT_HEADER_BYTES,
        },
        background_start: payload_end,
        background_bytes: 0,
        background_crc: 0,
        layers: DEFAULT_LAYERS,
        layer_count: 1,
        active_layer: 0,
        text_bytes: 0,
        extended: 0,
        contours: 0,
        paper: WHITE_PAPER,
    };
    if layered {
        header.background_bytes = reader.u32()? as usize;
        header.layer_count = reader.u32()? as usize;
        header.text_bytes = reader.u32()? as usize;
        let active_layer = reader.u32()?;
        let paper = reader.u32()?;
        if paper != 0 {
            // One spelling per colour: a white sheet is always the zero word.
            if paper >> 24 != 1 || paper & WHITE_PAPER == WHITE_PAPER {
                return Err(INVALID);
            }
            header.paper = paper & WHITE_PAPER;
        }
        if reader.u32()? != 0
            || header.background_bytes > MAX_BACKGROUND_BYTES
            || !(1..=MAX_LAYERS).contains(&header.layer_count)
            || header.text_bytes > MAX_TOTAL_TEXT_BYTES
        {
            return Err(INVALID);
        }
        header.header_bytes += header.layer_count * 8;
        // Version 4 knows the visibility bit only; version 5 adds the lock.
        let known_flags = if version == LOCKED_PROJECT_VERSION {
            3
        } else {
            1
        };
        let mut active_found = false;
        for position in 0..header.layer_count {
            let id = reader.u32()?;
            let flags = reader.u32()?;
            if id as usize >= MAX_LAYERS
                || flags & !known_flags != 0
                || header.layers[..position]
                    .iter()
                    .any(|layer| u32::from(layer.id) == id)
            {
                return Err(INVALID);
            }
            header.layers[position] = Layer {
                id: id as u8,
                visible: flags & 1 == 1,
                locked: flags & 2 == 2,
            };
            // New objects join the active layer: it is never a locked one.
            active_found |= id == active_layer && flags & 2 == 0;
        }
        if !active_found {
            return Err(INVALID);
        }
        header.active_layer = active_layer as u8;
        header.background_start = payload_end
            .checked_sub(header.background_bytes)
            .ok_or(INVALID)?;
    } else if version == HYBRID_PROJECT_VERSION {
        if reader.u32()? != 1 {
            return Err(INVALID);
        }
        header.background_bytes = reader.u32()? as usize;
        let background_width = reader.u32()?;
        let background_height = reader.u32()?;
        if !(1..=MAX_BACKGROUND_BYTES).contains(&header.background_bytes)
            || background_width != header.width
            || background_height != header.height
        {
            return Err(INVALID);
        }
        header.background_start = payload_end
            .checked_sub(header.background_bytes)
            .ok_or(INVALID)?;
    } else if bytes.len() > MAX_VECTOR_PROJECT_BYTES {
        return Err(INVALID);
    }
    let record_bytes = match version {
        1 => 12,
        LAYERED_PROJECT_VERSION | LOCKED_PROJECT_VERSION => LAYERED_OBJECT_BYTES,
        _ => 24,
    };
    if !(1..=MAX_DIMENSION).contains(&header.width)
        || !(1..=MAX_DIMENSION).contains(&header.height)
        || header.strokes > MAX_STROKES
        || header.points > MAX_TOTAL_POINTS
        || header.header_bytes
            + 4
            + header.strokes * record_bytes
            + header.points * 8
            + header.text_bytes
            + header.background_bytes
            != bytes.len()
    {
        return Err(INVALID);
    }
    let checksum = u32::from_le_bytes(bytes[payload_end..].try_into().map_err(|_| INVALID)?);
    if crc32(&bytes[..payload_end]) != checksum {
        return Err(INVALID);
    }
    if header.background_bytes != 0 {
        let info = validate_canonical_png(&bytes[header.background_start..payload_end])?;
        if info.width != header.width || info.height != header.height {
            return Err(INVALID);
        }
    }
    if header.background_bytes != 0 {
        // CRC(prefix || PNG) is already verified. Derive the PNG CRC without
        // another scan of its bytes; CRC combination is linear over GF(2).
        header.background_crc = checksum
            ^ crc32_combine(
                crc32(&bytes[..header.background_start]),
                0,
                header.background_bytes,
            );
    }

    // Exclude the background and checksum from the vector record reader.
    reader.bytes = &bytes[..header.background_start];
    let mut point_count = 0usize;
    let mut text_count = 0usize;
    for _ in 0..header.strokes {
        let record = read_record(&mut reader, version)?;
        let ObjectRecord {
            rgb,
            width,
            count,
            style,
            ..
        } = record;
        // A freehand stroke and a contour are lists of points; every other
        // kind has exactly two.
        let listed = matches!(style.kind, 0 | KIND_CONTOUR);
        if rgb > 0x00ff_ffff
            || !valid_style(style)
            // Texts and stamps exist only in v4/v5 records, which carry them;
            // contours only in v5.
            || (!layered && style.kind > 3)
            || (style.kind == KIND_CONTOUR && version != LOCKED_PROJECT_VERSION)
            || (style.kind == KIND_CONTOUR && count < 3)
            || (!listed && count != 2)
            || !valid_width(style.kind, width)
            || !valid_param(style.kind, record.param)
            || !header.layers[..header.layer_count]
                .iter()
                .any(|layer| layer.id == record.layer)
            || (style.kind == KIND_TEXT) == (record.text_bytes == 0)
            || record.text_bytes > MAX_TEXT_BYTES
            || record.text_bytes > header.text_bytes.saturating_sub(text_count)
            || !(1..=MAX_STROKE_POINTS).contains(&count)
            || count > header.points.saturating_sub(point_count)
        {
            return Err(INVALID);
        }
        point_count += count;
        text_count += record.text_bytes;
        header.extended += usize::from(matches!(style.kind, KIND_TEXT | KIND_STAMP));
        header.contours += usize::from(style.kind == KIND_CONTOUR);
        let mut shape_points = [EpPoint { x: 0.0, y: 0.0 }; 2];
        let mut shape_point_slots = shape_points.iter_mut();
        // The extent of a contour, gathered without storing its points.
        let mut low = [f32::INFINITY; 2];
        let mut high = [f32::NEG_INFINITY; 2];
        for _ in 0..count {
            let x = reader.f32()?;
            let y = reader.f32()?;
            if !x.is_finite()
                || !y.is_finite()
                || !(0.0..=header.width as f32).contains(&x)
                || !(0.0..=header.height as f32).contains(&y)
            {
                return Err(INVALID);
            }
            low = [low[0].min(x), low[1].min(y)];
            high = [high[0].max(x), high[1].max(y)];
            if !listed {
                *shape_point_slots.next().ok_or(INVALID)? = EpPoint { x, y };
            }
        }
        if (style.kind == KIND_CONTOUR && !(low[0] < high[0] && low[1] < high[1]))
            || (!listed && !valid_shape_points(style.kind, &shape_points))
        {
            return Err(INVALID);
        }
        if record.text_bytes != 0 && !valid_text(reader.take(record.text_bytes)?) {
            return Err(INVALID);
        }
    }
    if point_count != header.points
        || text_count != header.text_bytes
        || reader.cursor != header.background_start
    {
        return Err(INVALID);
    }
    Ok(header)
}

fn load_project(bytes: &[u8]) -> Result<EpDocument, i32> {
    let header = validate_project(bytes)?;
    let mut document = EpDocument {
        width: header.width,
        height: header.height,
        background: None,
        strokes: Vec::new(),
        history: Vec::new(),
        cursor: 0,
        active_points: header.points,
        retained_points: header.points,
        retained_objects: header.strokes,
        next_revision: header.strokes as u64 + 1,
        layers: header.layers,
        layer_count: header.layer_count,
        active_layer: header.active_layer,
        active_text_bytes: header.text_bytes,
        retained_text_bytes: header.text_bytes,
        active_extended: header.extended,
        active_contours: header.contours,
        paper: header.paper,
    };
    document
        .strokes
        .try_reserve_exact(header.strokes)
        .map_err(|_| ALLOCATION_FAILURE)?;
    // Undo of every loaded stroke must remain allocation-free, as for new docs.
    document
        .history
        .try_reserve_exact(header.strokes)
        .map_err(|_| ALLOCATION_FAILURE)?;
    let mut reader = ProjectReader {
        bytes,
        cursor: header.header_bytes,
    };
    for index in 0..header.strokes {
        let record = read_record(&mut reader, header.version)?;
        let mut points = Vec::new();
        points
            .try_reserve_exact(record.count)
            .map_err(|_| ALLOCATION_FAILURE)?;
        for _ in 0..record.count {
            points.push(EpPoint {
                x: reader.f32()?,
                y: reader.f32()?,
            });
        }
        let mut text = Vec::new();
        text.try_reserve_exact(record.text_bytes)
            .map_err(|_| ALLOCATION_FAILURE)?;
        text.extend_from_slice(reader.take(record.text_bytes)?);
        document.strokes.push(Stroke {
            points,
            rgb: record.rgb,
            width: record.width,
            style: record.style,
            scale: 1.0,
            translation: [0.0; 2],
            revision: index as u64 + 1,
            layer: record.layer,
            param: record.param,
            text,
        });
        // What a locked layer holds is a colouring page, which is not in
        // the history, as when ep_document_from_page made it: undo never
        // takes it away. Undone from the last, each other object leaves
        // from the index it was read at, since only objects after it have
        // gone; redo puts them back in the same order.
        if !document.locked(record.layer) {
            document.history.push(Edit::Presence {
                index,
                detached: None,
            });
        }
    }
    document.cursor = document.history.len();
    if header.background_bytes != 0 {
        document.background = Some(Arc::new(BackgroundPng::copy_validated(
            header.width,
            header.height,
            &bytes[header.background_start..bytes.len() - 4],
            header.background_crc,
        )?));
    }
    Ok(document)
}

/// Creates a new document from a complete, validated project. Never modifies an
/// existing document. NULL on failure; optional out_status is 0 success,
/// -1 invalid/unsupported/corrupt file, -2 allocation failure. Bytes are copied.
///
/// # Safety
/// Non-null `bytes` must point to `length` initialized bytes in one live
/// allocation, unchanged for the call. Non-null `out_status` must be writable,
/// aligned and disjoint from those input bytes. Returned ownership is identical
/// to `ep_document_new`: one owner, released with `ep_document_free`.
#[no_mangle]
pub unsafe extern "C" fn ep_document_from_project(
    bytes: *const u8,
    length: usize,
    out_status: *mut i32,
) -> *mut EpDocument {
    let result = if bytes.is_null() || !(PROJECT_MIN_BYTES..=MAX_PROJECT_BYTES).contains(&length) {
        Err(INVALID)
    } else {
        load_project(unsafe { slice::from_raw_parts(bytes, length) })
    };
    let (pointer, status) = match result {
        Ok(document) => {
            // On failure the local document (with every partial allocation) drops.
            let pointer = owned_document(document);
            (
                pointer,
                if pointer.is_null() {
                    ALLOCATION_FAILURE
                } else {
                    0
                },
            )
        }
        Err(status) => (ptr::null_mut(), status),
    };
    if !out_status.is_null() {
        unsafe { out_status.write(status) };
    }
    pointer
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    struct Owned(*mut EpDocument);
    impl Owned {
        fn new() -> Self {
            let pointer = ep_document_new(1200, 800);
            assert!(!pointer.is_null());
            Self(pointer)
        }
        fn add(&self, points: &[EpPoint], rgb: u32, width: f32) -> i32 {
            unsafe { ep_add_stroke(self.0, points.as_ptr(), points.len(), rgb, width) }
        }
        fn shape(&self, points: &[EpPoint; 2], style: EpObjectStyle, rgb: u32, width: f32) -> i32 {
            unsafe { ep_add_shape(self.0, points.as_ptr(), &style, rgb, width) }
        }
        fn svg(&self) -> String {
            unsafe {
                let raw = ep_export_svg(self.0);
                assert!(!raw.is_null());
                let result = CStr::from_ptr(raw).to_str().unwrap().to_owned();
                ep_string_free(raw);
                result
            }
        }
        fn project(&self) -> Vec<u8> {
            unsafe {
                let mut bytes = vec![0; ep_project_size(self.0)];
                assert_eq!(ep_copy_project(self.0, bytes.as_mut_ptr(), bytes.len()), 0);
                bytes
            }
        }
        fn from_project(bytes: &[u8]) -> Self {
            let mut status = 99;
            let result =
                unsafe { ep_document_from_project(bytes.as_ptr(), bytes.len(), &mut status) };
            assert_eq!(status, 0);
            assert!(!result.is_null());
            Self(result)
        }
    }
    impl Drop for Owned {
        fn drop(&mut self) {
            unsafe { ep_document_free(self.0) };
        }
    }
    fn point(x: f32, y: f32) -> EpPoint {
        EpPoint { x, y }
    }

    fn assert_retention(doc: &Owned) {
        let document = unsafe { &*doc.0 };
        let active_points: usize = document
            .strokes
            .iter()
            .map(|stroke| stroke.points.len())
            .sum();
        let mut points = active_points;
        let mut objects = document.strokes.len();
        for edit in &document.history {
            if let Edit::Presence {
                detached: Some(stroke),
                ..
            } = edit
            {
                points += stroke.points.len();
                objects += 1;
            }
        }
        assert_eq!(document.active_points, active_points);
        assert_eq!(document.retained_points, points);
        assert_eq!(document.retained_objects, objects);
        assert!(points <= MAX_RETAINED_POINTS && objects <= MAX_RETAINED_OBJECTS);
        assert!(document.history.len() <= MAX_HISTORY_STEPS);
        assert!(document.strokes.capacity() <= MAX_STROKES);
        assert!(document.history.capacity() <= MAX_HISTORY_STEPS);
    }

    #[test]
    fn reordering_preserves_point_ownership_revisions_and_serialized_content() {
        let doc = Owned::new();
        for (index, rgb) in [0x112233, 0x445566, 0x778899].into_iter().enumerate() {
            let x = 10.0 + index as f32 * 30.0;
            assert_eq!(
                doc.add(&[point(x, 20.0), point(x + 10.0, 40.0)], rgb, 3.0),
                0
            );
        }
        unsafe {
            assert_eq!(ep_move_object(doc.0, 1, 0.1, 0.2), 1);
            let original = doc.project();
            let original_svg = doc.svg();
            let next_revision = (*doc.0).next_revision;
            let capacity = (*doc.0).strokes.capacity();
            let content: Vec<_> = (*doc.0)
                .strokes
                .iter()
                .map(|s| {
                    (
                        s.revision,
                        s.points.as_ptr(),
                        s.translation,
                        s.style,
                        s.rgb,
                        s.width.to_bits(),
                    )
                })
                .collect();
            assert_eq!(ep_reorder_object(doc.0, 0, 2), 1);
            for (index, original_index) in [1, 2, 0].into_iter().enumerate() {
                let s = &(&(*doc.0).strokes)[index];
                assert_eq!(
                    (
                        s.revision,
                        s.points.as_ptr(),
                        s.translation,
                        s.style,
                        s.rgb,
                        s.width.to_bits()
                    ),
                    content[original_index]
                );
            }
            assert_eq!((*doc.0).next_revision, next_revision);
            assert_eq!((*doc.0).strokes.capacity(), capacity);
            assert_eq!(ep_stroke_count(doc.0), 3);
            let front = doc.project();
            assert_ne!(front, original);
            assert_eq!(u16::from_le_bytes([front[8], front[9]]), PROJECT_VERSION);
            assert_eq!(Owned::from_project(&front).project(), front);
            let svg = doc.svg();
            assert!(svg.find("#445566").unwrap() < svg.find("#778899").unwrap());
            assert!(svg.find("#778899").unwrap() < svg.find("#112233").unwrap());
            assert_eq!(ep_reorder_object(doc.0, 2, 1), 1);
            assert_eq!((&(*doc.0).strokes)[0].revision, content[1].0);
            assert_eq!((&(*doc.0).strokes)[1].revision, content[0].0);
            assert_eq!((&(*doc.0).strokes)[2].revision, content[2].0);
            assert_eq!(ep_reorder_object(doc.0, 1, 0), 1);
            assert_eq!(doc.project(), original);
            for _ in 0..3 {
                assert_eq!(ep_undo(doc.0), 1);
            }
            assert_eq!(doc.project(), original);
            assert_eq!(doc.svg(), original_svg);
            assert_eq!(ep_redo(doc.0), 1);
            assert_eq!(doc.project(), front);
            assert_retention(&doc);
        }
    }

    #[test]
    fn order_history_composes_with_content_presence_and_redo_branches() {
        let doc = Owned::new();
        for rgb in [0x111111, 0x222222, 0x333333] {
            assert_eq!(
                doc.add(&[point(10.0, 10.0), point(20.0, 30.0)], rgb, 2.0),
                0
            );
        }
        let mut states = vec![doc.project()];
        unsafe {
            macro_rules! changed {
                ($action:expr) => {{
                    assert_eq!($action, 1);
                    states.push(doc.project());
                    assert_retention(&doc);
                }};
            }
            changed!(ep_reorder_object(doc.0, 0, 2));
            changed!(ep_set_object_style(doc.0, 0, 0xabcdef, 4.0, 0, 0));
            changed!(ep_remove_object(doc.0, 1));
            changed!(ep_reorder_object(doc.0, 1, 0));
            changed!(ep_duplicate_object(doc.0, 1, 5.0, 10.0));
            changed!(ep_reorder_object(doc.0, 2, 0));
            changed!(ep_move_object(doc.0, 1, 0.1, 0.2));
            for state in states[..states.len() - 1].iter().rev() {
                assert_eq!(ep_undo(doc.0), 1);
                assert_eq!(&doc.project(), state);
                assert_retention(&doc);
            }
            for state in states.iter().skip(1) {
                assert_eq!(ep_redo(doc.0), 1);
                assert_eq!(&doc.project(), state);
                assert_retention(&doc);
            }
            // Undo move, order and duplicate: redo owns the duplicate's buffer.
            for _ in 0..3 {
                assert_eq!(ep_undo(doc.0), 1);
            }
            let retained = (*doc.0).retained_objects;
            assert_eq!(ep_stroke_count(doc.0), 2);
            assert_eq!(ep_reorder_object(doc.0, 0, 1), 1);
            assert_eq!(ep_redo_count(doc.0), 0);
            assert_eq!((*doc.0).retained_objects, retained - 1);
            assert_retention(&doc);
        }
    }

    #[test]
    fn order_noops_and_refusals_preserve_history_even_when_revisions_exhausted() {
        let doc = Owned::new();
        unsafe {
            assert_eq!(ep_reorder_object(ptr::null_mut(), 0, 0), INVALID);
            assert_eq!(ep_reorder_object(doc.0, 0, 0), INVALID);
            assert_eq!(doc.add(&[point(1.0, 1.0)], 1, 1.0), 0);
            assert_eq!(ep_reorder_object(doc.0, 0, 0), 0);
            assert_eq!(doc.add(&[point(2.0, 2.0)], 2, 1.0), 0);
            assert_eq!(ep_reorder_object(doc.0, 0, 1), 1);
            assert_eq!(ep_undo(doc.0), 1);
            let original = doc.project();
            let counts = (ep_undo_count(doc.0), ep_redo_count(doc.0));
            let capacity = (*doc.0).history.capacity();
            for (from, to) in [(2, 0), (0, 2), (2, 2), (usize::MAX, 0), (0, usize::MAX)] {
                assert_eq!(ep_reorder_object(doc.0, from, to), INVALID);
            }
            assert_eq!(ep_reorder_object(doc.0, 0, 0), 0);
            assert_eq!(doc.project(), original);
            assert_eq!((ep_undo_count(doc.0), ep_redo_count(doc.0)), counts);
            assert_eq!((*doc.0).history.capacity(), capacity);
            (*doc.0).next_revision = u64::MAX;
            assert_eq!(ep_reorder_object(doc.0, 1, 0), 1);
            assert_eq!((*doc.0).next_revision, u64::MAX);
            assert_eq!(ep_redo_count(doc.0), 0);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(doc.project(), original);
            assert_retention(&doc);
        }
    }

    #[test]
    fn order_history_limit_is_atomic_and_a_noop_still_succeeds() {
        let doc = Owned::new();
        assert_eq!(doc.add(&[point(1.0, 1.0)], 1, 1.0), 0);
        assert_eq!(doc.add(&[point(2.0, 2.0)], 2, 1.0), 0);
        unsafe {
            for _ in 2..MAX_HISTORY_STEPS {
                assert_eq!(ep_reorder_object(doc.0, 0, 1), 1);
            }
            let before = doc.project();
            assert_eq!(ep_reorder_object(doc.0, 0, 1), INVALID);
            assert_eq!(ep_reorder_object(doc.0, 0, 0), 0);
            assert_eq!(doc.project(), before);
            assert_eq!(ep_undo_count(doc.0), MAX_HISTORY_STEPS);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_reorder_object(doc.0, 1, 0), 1);
            assert_eq!(ep_redo_count(doc.0), 0);
            assert_retention(&doc);
        }
    }

    #[test]
    fn full_document_can_reorder_without_new_geometry_or_object_capacity() {
        let doc = Owned::new();
        for rgb in 0..MAX_STROKES {
            assert_eq!(doc.add(&[point(1.0, 1.0)], rgb as u32, 1.0), 0);
        }
        unsafe {
            let capacity = (*doc.0).strokes.capacity();
            let first_points = (&(*doc.0).strokes)[0].points.as_ptr();
            assert_eq!(ep_reorder_object(doc.0, 0, MAX_STROKES - 1), 1);
            assert_eq!(
                (&(*doc.0).strokes)[MAX_STROKES - 1].points.as_ptr(),
                first_points
            );
            assert_eq!((&(*doc.0).strokes)[0].rgb, 1);
            assert_eq!((*doc.0).strokes.capacity(), capacity);
            assert_eq!((*doc.0).active_points, MAX_STROKES);
            assert_eq!((*doc.0).retained_objects, MAX_STROKES);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!((&(*doc.0).strokes)[0].points.as_ptr(), first_points);
            assert_retention(&doc);
        }
    }

    #[test]
    fn content_revisions_track_exact_states_and_survive_visible_index_shifts() {
        let doc = Owned::new();
        assert_eq!(doc.add(&[point(10.0, 20.0)], 0x123456, 4.0), 0);
        assert_eq!(doc.add(&[point(30.0, 40.0)], 0x654321, 5.0), 0);
        unsafe {
            assert_eq!(ep_object_revision(ptr::null(), 0), 0);
            assert_eq!(ep_object_revision(doc.0, usize::MAX), 0);
            let first = ep_object_revision(doc.0, 0);
            let second = ep_object_revision(doc.0, 1);
            assert_ne!(first, 0);
            assert_ne!(first, second);
            assert_eq!(ep_remove_object(doc.0, 0), 1);
            assert_eq!(ep_object_revision(doc.0, 0), second);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_object_revision(doc.0, 0), first);
            assert_eq!(ep_object_revision(doc.0, 1), second);
            assert_eq!(ep_move_object(doc.0, 0, 2.0, 3.0), 1);
            let moved = ep_object_revision(doc.0, 0);
            assert!(moved > second);
            assert_eq!(ep_object_revision(doc.0, 1), second);
            assert_eq!(ep_set_object_style(doc.0, 0, 0xff00ff, 6.0, 0, 0), 1);
            let restyled = ep_object_revision(doc.0, 0);
            assert!(restyled > moved);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_object_revision(doc.0, 0), moved);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_object_revision(doc.0, 0), first);
            assert_eq!(ep_redo(doc.0), 1);
            assert_eq!(ep_object_revision(doc.0, 0), moved);
            assert_eq!(ep_redo(doc.0), 1);
            assert_eq!(ep_object_revision(doc.0, 0), restyled);
            assert_eq!(ep_duplicate_object(doc.0, 0, 0.0, 0.0), 1);
            let duplicate = ep_object_revision(doc.0, 2);
            assert!(duplicate > restyled);
            assert_eq!(ep_object_revision(doc.0, 0), restyled);
            assert_eq!(ep_object_revision(doc.0, 1), second);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_object_revision(doc.0, 2), 0);
            let next_before = (*doc.0).next_revision;
            assert_eq!(ep_move_object(doc.0, 0, 0.0, 0.0), 0);
            assert_eq!(ep_set_object_style(doc.0, 0, 0xff00ff, 6.0, 0, 0), 0);
            assert_eq!(ep_move_object(doc.0, 0, -1000.0, 0.0), INVALID);
            assert_eq!(ep_set_object_style(doc.0, 0, 0x1000000, 6.0, 0, 0), INVALID);
            assert_eq!(ep_object_revision(doc.0, 0), restyled);
            assert_eq!((*doc.0).next_revision, next_before);
            assert_eq!(ep_redo(doc.0), 1);
            assert_eq!(ep_object_revision(doc.0, 2), duplicate);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_move_object(doc.0, 1, 1.0, 1.0), 1);
            assert!(ep_object_revision(doc.0, 1) > duplicate);
            assert_eq!(ep_redo_count(doc.0), 0);
            let loaded = Owned::from_project(&doc.project());
            assert_eq!(loaded.project(), doc.project());
            assert_ne!(
                ep_object_revision(loaded.0, 0),
                ep_object_revision(loaded.0, 1)
            );
            assert_retention(&doc);
        }
    }

    #[test]
    fn revision_exhaustion_rejects_content_edits_without_wrapping_or_mutation() {
        let doc = Owned::new();
        assert_eq!(doc.add(&[point(10.0, 20.0)], 0, 1.0), 0);
        unsafe {
            (*doc.0).next_revision = u64::MAX - 1;
            assert_eq!(ep_move_object(doc.0, 0, 1.0, 1.0), 1);
            assert_eq!(ep_object_revision(doc.0, 0), u64::MAX - 1);
            let before = doc.project();
            assert_eq!(ep_move_object(doc.0, 0, 1.0, 1.0), INVALID);
            assert_eq!(ep_set_object_style(doc.0, 0, 1, 1.0, 0, 0), INVALID);
            assert_eq!(ep_duplicate_object(doc.0, 0, 0.0, 0.0), INVALID);
            assert_eq!(doc.add(&[point(30.0, 40.0)], 0, 1.0), INVALID);
            assert_eq!(doc.project(), before);
            assert_eq!(ep_undo_count(doc.0), 2);
            assert_eq!(ep_object_revision(doc.0, 0), u64::MAX - 1);
            assert_eq!(ep_move_object(doc.0, 0, 0.0, 0.0), 0);
            assert_eq!(ep_remove_object(doc.0, 0), 1);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_object_revision(doc.0, 0), u64::MAX - 1);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_object_revision(doc.0, 0), 1);
            assert_eq!(ep_redo(doc.0), 1);
            assert_eq!(ep_object_revision(doc.0, 0), u64::MAX - 1);
            assert_eq!((*doc.0).next_revision, u64::MAX);
        }
    }

    #[test]
    fn constrain_movement_repairs_snapshot_rounding_without_weakening_strict_edits() {
        let doc = Owned::new();
        assert_eq!(
            doc.shape(
                &[point(400.0, 200.0), point(650.0, 400.0)],
                EpObjectStyle {
                    kind: 3,
                    fill_enabled: 1,
                    fill_rgb: 0xffff00
                },
                0,
                1.0
            ),
            0
        );
        unsafe {
            assert_eq!(ep_move_object(doc.0, 0, 538.7, 388.7), 1);
            let mut points = [point(0.0, 0.0); 2];
            assert_eq!(ep_copy_points(doc.0, 0, points.as_mut_ptr(), 2), 2);
            let requested = point(1200.0 - points[1].x, 800.0 - points[1].y);
            // Reproduces the actual UI failure: snapshot-derived limits can be
            // looser than the retained exact geometry by a fraction of one ULP.
            assert_eq!(
                ep_duplicate_object(doc.0, 0, requested.x, requested.y),
                INVALID
            );
            let before = doc.project();
            let token = ep_object_revision(doc.0, 0);
            let undo = ep_undo_count(doc.0);
            let next_revision = (*doc.0).next_revision;
            let mut bounded = point(-999.0, -999.0);
            assert_eq!(
                ep_constrain_object_movement(doc.0, 0, requested.x, requested.y, &mut bounded),
                0
            );
            assert!(bounded.x <= requested.x && bounded.y <= requested.y);
            assert_eq!(doc.project(), before);
            assert_eq!(ep_object_revision(doc.0, 0), token);
            assert_eq!(ep_undo_count(doc.0), undo);
            assert_eq!((*doc.0).next_revision, next_revision);
            assert_eq!(ep_duplicate_object(doc.0, 0, bounded.x, bounded.y), 1);
            assert_eq!(ep_copy_points(doc.0, 1, points.as_mut_ptr(), 2), 2);
            assert!(points[1].x <= 1200.0 && points[1].y <= 800.0);
            assert_eq!(Owned::from_project(&doc.project()).project(), doc.project());
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(doc.project(), before);
            assert_eq!(
                ep_constrain_object_movement(doc.0, 0, requested.x, requested.y, &mut bounded),
                0
            );
            assert_eq!(ep_redo_count(doc.0), 1);
            assert_eq!(ep_move_object(doc.0, 0, bounded.x, bounded.y), 1);
            assert_eq!(ep_redo_count(doc.0), 0);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(doc.project(), before);
            assert_eq!(ep_object_revision(doc.0, 0), token);
        }
    }

    #[test]
    fn constrained_offsets_cover_all_edges_after_nonquarter_translations() {
        for request in [
            point(-10000.0, 0.0),
            point(10000.0, 0.0),
            point(0.0, -10000.0),
            point(0.0, 10000.0),
            point(10000.0, 10000.0),
            point(-10000.0, -10000.0),
        ] {
            let doc = Owned::new();
            assert_eq!(
                doc.shape(
                    &[point(100.1, 200.3), point(200.7, 300.9)],
                    EpObjectStyle {
                        kind: 2,
                        fill_enabled: 0,
                        fill_rgb: 0
                    },
                    0,
                    1.0
                ),
                0
            );
            unsafe {
                assert_eq!(ep_move_object(doc.0, 0, 0.1234567, 0.7654321), 1);
                assert_eq!(ep_move_object(doc.0, 0, -90.3333, -180.2222), 1);
                let before = doc.project();
                let mut bounded = point(0.0, 0.0);
                assert_eq!(
                    ep_constrain_object_movement(doc.0, 0, request.x, request.y, &mut bounded),
                    0
                );
                assert_eq!(doc.project(), before);
                assert_eq!(ep_move_object(doc.0, 0, bounded.x, bounded.y), 1);
                let mut output = [point(0.0, 0.0); 2];
                assert_eq!(ep_copy_points(doc.0, 0, output.as_mut_ptr(), 2), 2);
                for p in output {
                    assert!((0.0..=1200.0).contains(&p.x) && (0.0..=800.0).contains(&p.y));
                }
                assert_eq!(Owned::from_project(&doc.project()).project(), doc.project());
                assert_eq!(ep_undo(doc.0), 1);
                assert_eq!(doc.project(), before);
            }
        }
    }

    #[test]
    fn movement_constraint_failures_preserve_output_and_every_document_state() {
        let doc = Owned::new();
        assert_eq!(doc.add(&[point(10.1, 20.3)], 0, 1.0), 0);
        unsafe {
            assert_eq!(ep_duplicate_object(doc.0, 0, 1.1, 1.3), 1);
            assert_eq!(ep_undo(doc.0), 1);
            let before = doc.project();
            let token = ep_object_revision(doc.0, 0);
            let next_revision = (*doc.0).next_revision;
            let sentinel = point(-99.0, 99.0);
            let mut output = sentinel;
            assert_eq!(
                ep_constrain_object_movement(ptr::null(), 0, 0.0, 0.0, &mut output),
                INVALID
            );
            for index in [1, usize::MAX] {
                assert_eq!(
                    ep_constrain_object_movement(doc.0, index, 0.0, 0.0, &mut output),
                    INVALID
                );
            }
            for request in [
                point(f32::NAN, 0.0),
                point(0.0, f32::INFINITY),
                point(f32::NEG_INFINITY, 0.0),
            ] {
                assert_eq!(
                    ep_constrain_object_movement(doc.0, 0, request.x, request.y, &mut output),
                    INVALID
                );
            }
            assert_eq!(
                ep_constrain_object_movement(doc.0, 0, 0.0, 0.0, ptr::null_mut()),
                INVALID
            );
            assert_eq!(output, sentinel);
            assert_eq!(
                ep_constrain_object_movement(doc.0, 0, 0.0, -0.0, &mut output),
                0
            );
            assert_eq!(output, point(0.0, -0.0));
            assert_eq!(doc.project(), before);
            assert_eq!(ep_undo_count(doc.0), 1);
            assert_eq!(ep_redo_count(doc.0), 1);
            assert_eq!(ep_object_revision(doc.0, 0), token);
            assert_eq!((*doc.0).next_revision, next_revision);
        }
    }

    #[test]
    fn movement_constraint_rejects_rounded_degenerate_shapes_without_mutation() {
        let doc = Owned::new();
        assert_eq!(
            doc.shape(
                &[point(0.0, 0.0), point(f32::EPSILON, 1.0)],
                EpObjectStyle {
                    kind: 2,
                    fill_enabled: 0,
                    fill_rgb: 0
                },
                0,
                1.0
            ),
            0
        );
        unsafe {
            let before = doc.project();
            let mut output = point(-99.0, 99.0);
            assert_eq!(
                ep_constrain_object_movement(doc.0, 0, 1199.0, 0.0, &mut output),
                INVALID
            );
            assert_eq!(output, point(-99.0, 99.0));
            assert_eq!(doc.project(), before);
            assert_eq!(ep_undo_count(doc.0), 1);
            assert_eq!(
                ep_constrain_object_movement(doc.0, 0, 0.1, 0.1, &mut output),
                0
            );
            assert_eq!(ep_move_object(doc.0, 0, output.x, output.y), 1);
            assert_eq!(Owned::from_project(&doc.project()).project(), doc.project());
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(doc.project(), before);
        }
    }

    #[test]
    fn mixed_edit_commands_restore_every_state_and_branch_at_visible_indices() {
        let doc = Owned::new();
        let mut states = vec![doc.project()];
        assert_eq!(
            doc.add(&[point(10.1, 20.2), point(30.3, 40.4)], 0x123456, 4.0),
            0
        );
        states.push(doc.project());
        assert_eq!(
            doc.shape(
                &[point(200.0, 100.0), point(300.0, 250.0)],
                EpObjectStyle {
                    kind: 2,
                    fill_enabled: 1,
                    fill_rgb: 0xaabbcc
                },
                0x112233,
                5.0
            ),
            0
        );
        states.push(doc.project());
        unsafe {
            assert_eq!(ep_move_object(doc.0, 0, 0.15, 0.25), 1);
            states.push(doc.project());
            assert_eq!(ep_set_object_style(doc.0, 1, 0xff0000, 10.0, 0, 0), 1);
            states.push(doc.project());
            assert_eq!(ep_duplicate_object(doc.0, 1, 250.0, 200.0), 1);
            states.push(doc.project());
            assert_eq!(ep_remove_object(doc.0, 0), 1);
            states.push(doc.project());
            assert_eq!(ep_move_object(doc.0, 1, -100.0, 25.0), 1);
            states.push(doc.project());
            assert_eq!(ep_duplicate_object(doc.0, 0, 0.0, 0.0), 1);
            states.push(doc.project());
            assert_eq!(ep_remove_object(doc.0, 1), 1);
            states.push(doc.project());
            assert_eq!(ep_set_object_style(doc.0, 1, 0x00ff00, 2.0, 1, 0xffffff), 1);
            states.push(doc.project());
            assert_eq!(ep_undo_count(doc.0), states.len() - 1);
            assert_ne!(ep_stroke_count(doc.0), ep_undo_count(doc.0));
            for _ in 0..10 {
                for expected in states[..states.len() - 1].iter().rev() {
                    assert_eq!(ep_undo(doc.0), 1);
                    assert_eq!(&doc.project(), expected);
                    assert_retention(&doc);
                }
                assert_eq!(ep_undo(doc.0), 0);
                for expected in states.iter().skip(1) {
                    assert_eq!(ep_redo(doc.0), 1);
                    assert_eq!(&doc.project(), expected);
                    assert_retention(&doc);
                }
                assert_eq!(ep_redo(doc.0), 0);
            }
            let loaded = Owned::from_project(&doc.project());
            assert_eq!(loaded.project(), doc.project());
            assert_eq!(loaded.svg(), doc.svg());
            assert_eq!(ep_undo_count(loaded.0), ep_stroke_count(loaded.0));
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_undo(doc.0), 1);
            let branch_start = doc.project();
            assert_eq!(ep_remove_object(doc.0, 1), 1);
            assert_eq!(ep_redo_count(doc.0), 0);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(doc.project(), branch_start);
            assert_retention(&doc);
        }
    }

    #[test]
    fn invalid_and_noop_edits_preserve_geometry_and_both_history_directions() {
        let doc = Owned::new();
        assert_eq!(doc.add(&[point(10.0, 20.0)], 0x123456, 4.0), 0);
        unsafe {
            assert_eq!(ep_duplicate_object(doc.0, 0, 20.0, 0.0), 1);
            assert_eq!(ep_undo(doc.0), 1);
            let before = doc.project();
            for (dx, dy) in [
                (f32::NAN, 0.0),
                (0.0, f32::INFINITY),
                (-10.01, 0.0),
                (1190.01, 0.0),
                (0.0, -20.01),
                (0.0, 780.01),
            ] {
                assert_eq!(ep_move_object(doc.0, 0, dx, dy), INVALID);
                assert_eq!(ep_duplicate_object(doc.0, 0, dx, dy), INVALID);
            }
            for index in [1, usize::MAX] {
                assert_eq!(ep_move_object(doc.0, index, 0.0, 0.0), INVALID);
                assert_eq!(ep_remove_object(doc.0, index), INVALID);
                assert_eq!(ep_duplicate_object(doc.0, index, 0.0, 0.0), INVALID);
                assert_eq!(ep_set_object_style(doc.0, index, 0, 1.0, 0, 0), INVALID);
            }
            for width in [0.0, 0.09, 512.01, f32::NAN, f32::INFINITY] {
                assert_eq!(ep_set_object_style(doc.0, 0, 0, width, 0, 0), INVALID);
            }
            for (rgb, enabled, fill) in [
                (0x1000000, 0, 0),
                (0, 0, 1),
                (0, 1, 0x1000000),
                (0, 2, 0),
                (0, 1, 0),
            ] {
                assert_eq!(
                    ep_set_object_style(doc.0, 0, rgb, 1.0, enabled, fill),
                    INVALID
                );
            }
            assert_eq!(ep_move_object(doc.0, 0, 0.0, -0.0), 0);
            assert_eq!(ep_move_object(doc.0, 0, f32::MIN_POSITIVE, 0.0), 0);
            assert_eq!(ep_set_object_style(doc.0, 0, 0x123456, 4.0, 0, 0), 0);
            assert_eq!(doc.project(), before);
            assert_eq!(ep_undo_count(doc.0), 1);
            assert_eq!(ep_redo_count(doc.0), 1);
            assert_eq!(ep_undo_count(ptr::null()), 0);
            assert_eq!(ep_move_object(ptr::null_mut(), 0, 0.0, 0.0), INVALID);
            assert_eq!(ep_remove_object(ptr::null_mut(), 0), INVALID);
            assert_eq!(ep_duplicate_object(ptr::null_mut(), 0, 0.0, 0.0), INVALID);
            assert_eq!(
                ep_set_object_style(ptr::null_mut(), 0, 0, 1.0, 0, 0),
                INVALID
            );
            assert_eq!(ep_redo(doc.0), 1);
            assert_eq!(ep_stroke_count(doc.0), 2);
            assert_retention(&doc);
        }
    }

    #[test]
    fn moving_keeps_points_owned_once_and_undo_restores_exact_float_bits() {
        let doc = Owned::new();
        let points = [
            point(-0.0, 0.0),
            point(10.12345, 70.23456),
            point(f32::from_bits(1), 20.0),
        ];
        assert_eq!(doc.add(&points, 0x123456, 3.0), 0);
        let original = doc.project();
        assert_eq!(Owned::from_project(&original).project(), original);
        let pointer = unsafe { (&(*doc.0).strokes)[0].points.as_ptr() };
        unsafe {
            for _ in 0..100 {
                assert_eq!(ep_move_object(doc.0, 0, 0.1, 0.2), 1);
                assert_eq!((&(*doc.0).strokes)[0].points.as_ptr(), pointer);
                assert_eq!((&(*doc.0).strokes)[0].points, points);
            }
            let moved = doc.project();
            assert_eq!(Owned::from_project(&moved).project(), moved);
            let mut copied = [point(-9.0, -9.0); 3];
            assert_eq!(ep_copy_points(doc.0, 0, copied.as_mut_ptr(), 3), 3);
            assert!(copied[0].x > 9.99 && copied[0].y > 19.99);
            assert_eq!(ep_remove_object(doc.0, 0), 1);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!((&(*doc.0).strokes)[0].points.as_ptr(), pointer);
            for _ in 0..100 {
                assert_eq!(ep_undo(doc.0), 1);
            }
            assert_eq!(doc.project(), original);
            for _ in 0..100 {
                assert_eq!(ep_redo(doc.0), 1);
            }
            assert_eq!(doc.project(), moved);
            assert_retention(&doc);
        }
    }

    #[test]
    fn movement_checks_exact_page_edges_and_shape_float_collapse() {
        let doc = Owned::new();
        assert_eq!(
            doc.shape(
                &[point(10.0, 20.0), point(20.0, 40.0)],
                EpObjectStyle {
                    kind: 3,
                    fill_enabled: 1,
                    fill_rgb: 0x00ff00
                },
                0,
                1.0
            ),
            0
        );
        unsafe {
            assert_eq!(ep_move_object(doc.0, 0, -10.0, -20.0), 1);
            let corner = doc.project();
            assert_eq!(ep_move_object(doc.0, 0, -f32::MIN_POSITIVE, 0.0), INVALID);
            assert_eq!(doc.project(), corner);
            assert_eq!(ep_move_object(doc.0, 0, 1190.0, 780.0), 1);
            assert!(doc.svg().contains("cx=\"1195\" cy=\"790\""));
            assert_eq!(ep_move_object(doc.0, 0, 0.01, 0.0), INVALID);
            assert_eq!(Owned::from_project(&doc.project()).project(), doc.project());
        }
        let tiny = Owned::new();
        assert_eq!(
            tiny.shape(
                &[point(0.0, 0.0), point(f32::from_bits(1), f32::from_bits(1))],
                EpObjectStyle {
                    kind: 2,
                    fill_enabled: 0,
                    fill_rgb: 0
                },
                0,
                1.0
            ),
            0
        );
        unsafe {
            assert_eq!(ep_move_object(tiny.0, 0, 100.0, 100.0), INVALID);
            assert_eq!(ep_duplicate_object(tiny.0, 0, 100.0, 100.0), INVALID);
            assert_eq!(ep_undo_count(tiny.0), 1);
        }
    }

    #[test]
    fn history_command_limit_rejects_atomically_and_allows_branching() {
        let doc = Owned::new();
        assert_eq!(doc.add(&[point(10.0, 20.0)], 0, 1.0), 0);
        unsafe {
            for index in 1..MAX_HISTORY_STEPS {
                assert_eq!(
                    ep_set_object_style(doc.0, 0, 1 + (index % 2) as u32, 1.0, 0, 0),
                    1
                );
            }
            let before = doc.project();
            assert_eq!(ep_move_object(doc.0, 0, 1.0, 0.0), INVALID);
            assert_eq!(ep_remove_object(doc.0, 0), INVALID);
            assert_eq!(ep_duplicate_object(doc.0, 0, 1.0, 0.0), INVALID);
            assert_eq!(doc.add(&[point(1.0, 1.0)], 0, 1.0), INVALID);
            assert_eq!(ep_move_object(doc.0, 0, 0.0, 0.0), 0);
            assert_eq!(doc.project(), before);
            assert_eq!(ep_undo_count(doc.0), MAX_HISTORY_STEPS);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_set_object_style(doc.0, 0, 0xabcdef, 1.0, 0, 0), 1);
            assert_eq!(ep_redo_count(doc.0), 0);
            assert_retention(&doc);
        }
    }

    #[test]
    fn detached_history_points_are_bounded_and_branch_releases_payload() {
        let doc = Owned::new();
        let points = vec![point(10.0, 20.0); MAX_STROKE_POINTS];
        unsafe {
            for _ in 0..MAX_RETAINED_POINTS / MAX_STROKE_POINTS {
                assert_eq!(doc.add(&points, 0, 1.0), 0);
                assert_eq!(ep_remove_object(doc.0, 0), 1);
            }
            assert_eq!(ep_stroke_count(doc.0), 0);
            assert_eq!(doc.add(&[point(1.0, 1.0)], 0, 1.0), INVALID);
            assert_retention(&doc);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_duplicate_object(doc.0, 0, 0.0, 0.0), INVALID);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(doc.add(&[point(1.0, 1.0)], 0, 1.0), 0);
            assert_eq!(
                (*doc.0).retained_points,
                MAX_RETAINED_POINTS - MAX_STROKE_POINTS + 1
            );
            assert_eq!(ep_redo_count(doc.0), 0);
            assert_retention(&doc);
        }
    }

    #[test]
    fn detached_history_objects_are_bounded_even_with_tiny_geometry() {
        let doc = Owned::new();
        unsafe {
            for _ in 0..MAX_RETAINED_OBJECTS {
                assert_eq!(doc.add(&[point(10.0, 20.0)], 0, 1.0), 0);
                assert_eq!(ep_remove_object(doc.0, 0), 1);
            }
            let before = doc.project();
            assert_eq!(doc.add(&[point(1.0, 1.0)], 0, 1.0), INVALID);
            assert_eq!(doc.project(), before);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_duplicate_object(doc.0, 0, 0.0, 0.0), INVALID);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(doc.add(&[point(1.0, 1.0)], 0, 1.0), 0);
            assert_eq!((*doc.0).retained_objects, MAX_RETAINED_OBJECTS);
            assert_retention(&doc);
        }
    }

    #[test]
    fn history_branch_clears_redo_and_restores_exact_strokes() {
        let doc = Owned::new();
        let first = [point(10.0, 20.0), point(30.0, 40.0)];
        let second = [point(70.0, 80.0)];
        assert_eq!(doc.add(&first, 0x123456, 4.0), 0);
        let original = doc.svg();
        assert_eq!(doc.add(&second, 0xff0000, 6.0), 0);
        let both = doc.svg();
        unsafe {
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_redo_count(doc.0), 1);
            assert_eq!(doc.svg(), original);
            assert_eq!(ep_redo(doc.0), 1);
            assert_eq!(doc.svg(), both);
            assert_eq!(ep_undo(doc.0), 1);
        }
        assert_eq!(doc.add(&[point(1.0, 2.0)], 0x00ff00, 2.0), 0);
        unsafe {
            assert_eq!(ep_redo_count(doc.0), 0);
            assert_eq!(ep_redo(doc.0), 0);
            assert_eq!(ep_stroke_count(doc.0), 2);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_undo(doc.0), 0);
            assert_eq!(ep_redo(doc.0), 1);
            assert_eq!(ep_redo(doc.0), 1);
            assert_eq!(ep_redo(doc.0), 0);
        }
    }

    #[test]
    fn invalid_input_does_not_change_drawing_or_redo() {
        let doc = Owned::new();
        assert_eq!(doc.add(&[point(1.0, 2.0)], 0, 2.0), 0);
        unsafe { assert_eq!(ep_undo(doc.0), 1) };
        let original = doc.svg();
        for invalid in [
            point(f32::NAN, 1.0),
            point(1.0, f32::INFINITY),
            point(-0.1, 1.0),
            point(1200.01, 1.0),
            point(1.0, 800.01),
        ] {
            assert_eq!(doc.add(&[invalid], 0, 1.0), INVALID);
        }
        for invalid in [f32::NAN, f32::INFINITY, 0.0, 0.09, 512.01] {
            assert_eq!(doc.add(&[point(1.0, 1.0)], 0, invalid), INVALID);
        }
        assert_eq!(doc.add(&[], 0, 1.0), INVALID);
        assert_eq!(doc.add(&[point(1.0, 1.0)], 0x1000000, 1.0), INVALID);
        unsafe {
            assert_eq!(ep_add_stroke(doc.0, ptr::null(), 1, 0, 1.0), INVALID);
            assert_eq!(
                ep_add_stroke(doc.0, ptr::null(), usize::MAX, 0, 1.0),
                INVALID
            );
            assert_eq!(ep_redo_count(doc.0), 1);
            assert_eq!(ep_stroke_count(doc.0), 0);
        }
        assert_eq!(doc.svg(), original);
    }

    #[test]
    fn svg_keeps_logical_dimensions_and_single_point_is_visible() {
        let doc = Owned::new();
        assert_eq!(doc.add(&[point(20.0, 30.0)], 0x123456, 8.0), 0);
        let result = doc.svg();
        assert!(result.contains("viewBox=\"0 0 1200 800\""));
        assert!(result.contains("width=\"1200\" height=\"800\""));
        assert!(result.contains("fill=\"#ffffff\""));
        assert!(result.contains("<circle cx=\"20\" cy=\"30\" r=\"4\" fill=\"#123456\"/>"));
        assert_eq!(result.matches("xmlns=").count(), 1);
        assert_eq!(result, doc.svg());
        unsafe {
            assert_eq!(ep_document_width(doc.0), 1200);
            assert_eq!(ep_document_height(doc.0), 800);
        }
    }

    #[test]
    fn output_capacity_is_all_or_nothing_and_input_is_copied() {
        let doc = Owned::new();
        let mut input = [point(2.0, 3.0), point(4.0, 5.0)];
        let original = input;
        assert_eq!(doc.add(&input, 0xaabbcc, 9.0), 0);
        input[0].x = 100.0;
        let sentinel = point(-9.0, -9.0);
        let mut output = [sentinel; 3];
        let mut info = EpStrokeInfo {
            rgb: 42,
            width: 42.0,
            point_count: 42,
        };
        unsafe {
            assert_eq!(ep_copy_points(doc.0, 0, output.as_mut_ptr(), 1), 0);
            assert_eq!(output, [sentinel; 3]);
            assert_eq!(ep_copy_points(doc.0, 1, output.as_mut_ptr(), 3), 0);
            assert_eq!(ep_copy_points(doc.0, 0, output.as_mut_ptr(), 3), 2);
            assert_eq!(&output[..2], &original);
            assert_ne!(output[0], input[0]);
            assert_eq!(output[2], sentinel);
            assert_eq!(ep_stroke_info(doc.0, 1, &mut info), INVALID);
            assert_eq!(info.point_count, 42);
            assert_eq!(ep_stroke_info(doc.0, 0, &mut info), 0);
            assert_eq!(
                info,
                EpStrokeInfo {
                    rgb: 0xaabbcc,
                    width: 9.0,
                    point_count: 2
                }
            );
            assert_eq!(ep_stroke_info(doc.0, 0, ptr::null_mut()), INVALID);
            assert_eq!(ep_copy_points(doc.0, 0, ptr::null_mut(), 2), 0);
        }
    }

    #[test]
    fn nulls_and_dimensions_are_handled_without_dereferencing() {
        assert!(ep_document_new(0, 800).is_null());
        assert!(ep_document_new(800, 0).is_null());
        assert!(ep_document_new(MAX_DIMENSION + 1, 800).is_null());
        assert!(ep_document_new(800, MAX_DIMENSION + 1).is_null());
        unsafe {
            ep_document_free(ptr::null_mut());
            ep_string_free(ptr::null_mut());
            assert_eq!(ep_document_width(ptr::null()), 0);
            assert_eq!(ep_document_height(ptr::null()), 0);
            assert_eq!(ep_stroke_count(ptr::null()), 0);
            assert_eq!(ep_redo_count(ptr::null()), 0);
            assert_eq!(ep_undo(ptr::null_mut()), INVALID);
            assert_eq!(ep_redo(ptr::null_mut()), INVALID);
            assert_eq!(ep_stroke_info(ptr::null(), 0, ptr::null_mut()), INVALID);
            assert_eq!(ep_copy_points(ptr::null(), 0, ptr::null_mut(), 0), 0);
            assert!(ep_export_svg(ptr::null()).is_null());
            assert_eq!(
                ep_add_stroke(ptr::null_mut(), ptr::null(), 1, 0, 1.0),
                INVALID
            );
        }
    }

    #[test]
    fn point_and_document_limits_are_enforced_without_mutation() {
        let doc = Owned::new();
        let batch = vec![point(0.0, 800.0); MAX_STROKE_POINTS];
        for _ in 0..MAX_TOTAL_POINTS / MAX_STROKE_POINTS {
            assert_eq!(doc.add(&batch, 0, 0.1), 0);
        }
        assert_eq!(doc.add(&[point(0.0, 0.0)], 0, 1.0), INVALID);
        unsafe {
            assert_eq!(ep_stroke_count(doc.0), 10);
            assert_eq!(ep_undo(doc.0), 1);
        }
        assert_eq!(doc.add(&[point(1200.0, 800.0)], 0xffffff, 512.0), 0);
        assert_eq!(unsafe { ep_redo_count(doc.0) }, 0);
        let oversized = vec![point(0.0, 0.0); MAX_STROKE_POINTS + 1];
        assert_eq!(doc.add(&oversized, 0, 1.0), INVALID);
    }

    fn reject_project(bytes: &[u8]) {
        let mut status = 99;
        let pointer = unsafe { ep_document_from_project(bytes.as_ptr(), bytes.len(), &mut status) };
        assert!(pointer.is_null());
        assert_eq!(status, INVALID);
    }

    fn repair_checksum(bytes: &mut [u8]) {
        let end = bytes.len() - 4;
        let checksum = crc32(&bytes[..end]);
        bytes[end..].copy_from_slice(&checksum.to_le_bytes());
    }

    #[test]
    fn project_crc_matches_independent_bitwise_reference_for_every_prefix_and_alignment() {
        fn reference(bytes: &[u8]) -> u32 {
            let mut crc = u32::MAX;
            for byte in bytes {
                crc ^= u32::from(*byte);
                for _ in 0..8 {
                    crc = if crc & 1 != 0 {
                        (crc >> 1) ^ 0xedb8_8320
                    } else {
                        crc >> 1
                    };
                }
            }
            !crc
        }
        assert_eq!(crc32(b""), 0);
        assert_eq!(crc32(b"123456789"), 0xcbf4_3926);
        assert_eq!(
            crc32(b"The quick brown fox jumps over the lazy dog"),
            0x414f_a339
        );
        let mut bytes = [0; 1032];
        let mut seed = 1234u32;
        for byte in &mut bytes {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            *byte = (seed >> 24) as u8;
        }
        for offset in 0..8 {
            for length in 0..=1024 {
                let prefix = &bytes[offset..offset + length];
                assert_eq!(crc32(prefix), reference(prefix));
            }
        }
        for repeated in [0, 0xff, 0x55, 0xaa] {
            bytes.fill(repeated);
            assert_eq!(crc32(&bytes), reference(&bytes));
        }
    }

    #[test]
    fn project_roundtrip_is_exact_and_preserves_loaded_undo() {
        let source = Owned::new();
        let points = [
            point(-0.0, 0.0),
            point(f32::MIN_POSITIVE, 32.125),
            point(1200.0, 800.0),
        ];
        assert_eq!(source.add(&points, 0x102030, 0.1), 0);
        assert_eq!(source.add(&[point(8.0, 9.0)], 0xffffff, 512.0), 0);
        let visible_svg = source.svg();
        assert_eq!(source.add(&[point(50.0, 60.0)], 0, 3.0), 0);
        unsafe { assert_eq!(ep_undo(source.0), 1) };
        let mut bytes = source.project();
        let loaded = Owned::from_project(&bytes);
        assert_eq!(loaded.svg(), visible_svg);
        assert_eq!(loaded.project(), bytes);
        bytes.fill(0); // Imported data does not borrow the source buffer.
        unsafe {
            assert_eq!(ep_stroke_count(loaded.0), 2);
            assert_eq!(ep_redo_count(loaded.0), 0);
            assert_eq!(ep_undo(loaded.0), 1);
            assert_eq!(ep_undo(loaded.0), 1);
            assert_eq!(ep_undo(loaded.0), 0);
            assert_eq!(ep_redo(loaded.0), 1);
            assert_eq!(ep_redo(loaded.0), 1);
            assert_eq!(ep_redo(loaded.0), 0);
        }
        assert_eq!(loaded.svg(), visible_svg);
        unsafe { assert_eq!(ep_undo(loaded.0), 1) };
        assert_eq!(loaded.add(&[point(1.0, 1.0)], 0, 1.0), 0);
        unsafe { assert_eq!(ep_redo_count(loaded.0), 0) };
        assert_eq!(source.svg(), visible_svg);
        unsafe { assert_eq!(ep_redo_count(source.0), 1) };
    }

    #[test]
    fn project_empty_and_variable_dimensions_roundtrip() {
        assert_eq!(crc32(b"123456789"), 0xcbf4_3926); // Published CRC-32 check value.
        for (width, height) in [(1, 1), (640, 480), (16_384, 16_384), (800, 1200)] {
            let source = Owned(ep_document_new(width, height));
            let bytes = source.project();
            assert_eq!(bytes.len(), PROJECT_MIN_BYTES);
            let loaded = Owned::from_project(&bytes);
            assert_eq!(loaded.project(), bytes);
            assert_eq!(loaded.svg(), source.svg());
            unsafe {
                assert_eq!(ep_document_width(loaded.0), width);
                assert_eq!(ep_document_height(loaded.0), height);
                assert_eq!(ep_undo(loaded.0), 0);
            }
            assert_eq!(loaded.add(&[point(width as f32, height as f32)], 0, 1.0), 0);
            assert_eq!(Owned::from_project(&loaded.project()).svg(), loaded.svg());
        }
    }

    #[test]
    fn project_rejects_every_truncation_and_single_byte_corruption() {
        let source = Owned::new();
        assert_eq!(
            source.add(&[point(5.0, 6.0), point(7.0, 8.0)], 0xabcdef, 12.0),
            0
        );
        let svg = source.svg();
        let bytes = source.project();
        for length in 0..bytes.len() {
            reject_project(&bytes[..length]);
        }
        for index in 0..bytes.len() {
            let mut corrupt = bytes.clone();
            corrupt[index] ^= 0x80;
            reject_project(&corrupt);
        }
        let mut trailing = bytes.clone();
        trailing.push(0);
        reject_project(&trailing);
        assert_eq!(source.svg(), svg);
        assert_eq!(source.project(), bytes);
    }

    #[test]
    fn project_rejects_invalid_values_even_with_valid_checksum() {
        let source = Owned::new();
        assert_eq!(source.add(&[point(5.0, 6.0)], 0xabcdef, 12.0), 0);
        let bytes = source.project();
        let replacements = [
            (12, u32::MAX), // byte length
            (16, 0),
            (16, MAX_DIMENSION + 1),
            (20, 0),
            (20, MAX_DIMENSION + 1),
            (24, MAX_STROKES as u32 + 1),
            (24, 0),
            (24, u32::MAX),
            (28, MAX_TOTAL_POINTS as u32 + 1),
            (28, 0),
            (28, u32::MAX),
            (32, 0x01000000), // RGB
            (36, f32::NAN.to_bits()),
            (36, f32::INFINITY.to_bits()),
            (36, 0.0f32.to_bits()),
            (36, 512.1f32.to_bits()),
            (40, 0),
            (40, MAX_STROKE_POINTS as u32 + 1),
            (40, u32::MAX),
            (44, 4), // unknown kind
            (48, 2), // invalid fill flag
            (48, 1), // freehand cannot be filled
            (52, 1), // disabled fill must use canonical zero color
            (56, f32::NAN.to_bits()),
            (56, f32::NEG_INFINITY.to_bits()),
            (56, (-0.1f32).to_bits()),
            (56, 1200.1f32.to_bits()),
            (60, f32::NAN.to_bits()),
            (60, 800.1f32.to_bits()),
        ];
        for (offset, value) in replacements {
            let mut invalid = bytes.clone();
            invalid[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
            repair_checksum(&mut invalid);
            reject_project(&invalid);
        }
        for offset in [0, 8, 9, 10, 11] {
            // magic, future version, unknown flags
            let mut invalid = bytes.clone();
            invalid[offset] ^= 1;
            repair_checksum(&mut invalid);
            reject_project(&invalid);
        }
        // Header declares one extra point, making total length consistent, but
        // the stroke still has one point: trailing payload must be rejected.
        let mut trailing = bytes[..bytes.len() - 4].to_vec();
        trailing.extend_from_slice(&[0; 12]);
        let length = trailing.len() as u32;
        trailing[12..16].copy_from_slice(&length.to_le_bytes());
        trailing[28..32].copy_from_slice(&2u32.to_le_bytes());
        repair_checksum(&mut trailing);
        reject_project(&trailing);
    }

    #[test]
    fn project_ffi_null_limits_and_capacity_are_all_or_nothing() {
        let source = Owned::new();
        let mut status = 99;
        let mut output = [0xa5; PROJECT_MIN_BYTES + 4];
        unsafe {
            assert_eq!(ep_project_size(ptr::null()), 0);
            assert_eq!(
                ep_copy_project(ptr::null(), output.as_mut_ptr(), output.len()),
                INVALID
            );
            assert_eq!(
                ep_copy_project(source.0, ptr::null_mut(), output.len()),
                INVALID
            );
            assert_eq!(
                ep_copy_project(source.0, output.as_mut_ptr(), PROJECT_MIN_BYTES - 1),
                INVALID
            );
            assert!(output.iter().all(|value| *value == 0xa5));
            assert_eq!(
                ep_copy_project(source.0, output.as_mut_ptr(), output.len()),
                0
            );
            assert_eq!(&output[PROJECT_MIN_BYTES..], &[0xa5; 4]);
            assert!(
                ep_document_from_project(ptr::null(), PROJECT_MIN_BYTES, &mut status).is_null()
            );
            assert_eq!(status, INVALID);
            // The length guard must run before attempting to read the buffer.
            assert!(ep_document_from_project(output.as_ptr(), usize::MAX, &mut status).is_null());
            assert!(ep_document_from_project(
                output.as_ptr(),
                MAX_PROJECT_BYTES + 1,
                ptr::null_mut()
            )
            .is_null());
            assert_eq!(status, INVALID);
            let without_status =
                ep_document_from_project(output.as_ptr(), PROJECT_MIN_BYTES, ptr::null_mut());
            assert!(!without_status.is_null());
            ep_document_free(without_status);
        }
    }

    #[test]
    fn project_load_at_point_limit_and_many_strokes_preserves_history() {
        let source = Owned::new();
        let batch = vec![point(0.0, 800.0); MAX_STROKE_POINTS];
        for _ in 0..MAX_TOTAL_POINTS / MAX_STROKE_POINTS {
            assert_eq!(source.add(&batch, 0xffffff, 0.1), 0);
        }
        let bytes = source.project();
        let loaded = Owned::from_project(&bytes);
        assert_eq!(loaded.project(), bytes);
        assert_eq!(loaded.add(&[point(1.0, 1.0)], 0, 1.0), INVALID);
        let many = Owned::new();
        let small_batch = vec![point(1.0, 1.0); MAX_TOTAL_POINTS / MAX_STROKES];
        for _ in 0..MAX_STROKES {
            assert_eq!(many.add(&small_batch, 0, 1.0), 0);
        }
        let largest_project = many.project();
        assert_eq!(largest_project.len(), MAX_VECTOR_PROJECT_BYTES);
        let loaded_many = Owned::from_project(&largest_project);
        assert_eq!(loaded_many.add(&[point(1.0, 1.0)], 0, 1.0), INVALID);
        unsafe {
            for _ in 0..MAX_STROKES {
                assert_eq!(ep_undo(loaded_many.0), 1);
            }
            assert_eq!(ep_undo(loaded_many.0), 0);
            for _ in 0..MAX_STROKES {
                assert_eq!(ep_redo(loaded_many.0), 1);
            }
            assert_eq!(ep_redo(loaded_many.0), 0);
        }
        assert_eq!(loaded_many.project(), many.project());
    }

    fn shape_style(kind: u32, fill: Option<u32>) -> EpObjectStyle {
        EpObjectStyle {
            kind,
            fill_enabled: u32::from(fill.is_some()),
            fill_rgb: fill.unwrap_or(0),
        }
    }

    #[test]
    fn exact_shapes_svg_mixed_history_and_project_v2_roundtrip() {
        let doc = Owned::new();
        assert_eq!(doc.add(&[point(1.0, 2.0)], 0, 2.0), 0);
        assert_eq!(
            doc.shape(
                &[point(10.0, 20.0), point(30.0, 40.0)],
                shape_style(1, None),
                0x123456,
                3.0
            ),
            0
        );
        let reverse_corners = [point(100.0, 120.0), point(20.0, 30.0)];
        assert_eq!(
            doc.shape(
                &reverse_corners,
                shape_style(2, Some(0xffaabb)),
                0xabcdef,
                4.0
            ),
            0
        );
        assert_eq!(
            doc.shape(
                &reverse_corners,
                shape_style(3, Some(0x112233)),
                0x010203,
                5.0
            ),
            0
        );
        let expected_svg = doc.svg();
        assert!(expected_svg.contains(
            "<line x1=\"10\" y1=\"20\" x2=\"30\" y2=\"40\" fill=\"none\" stroke=\"#123456\""
        ));
        assert!(expected_svg.contains("<rect x=\"20\" y=\"30\" width=\"80\" height=\"90\" fill=\"#ffaabb\" stroke=\"#abcdef\""));
        assert!(expected_svg.contains(
            "<ellipse cx=\"60\" cy=\"75\" rx=\"40\" ry=\"45\" fill=\"#112233\" stroke=\"#010203\""
        ));
        assert!(!expected_svg.contains("<polygon"));
        assert!(!expected_svg.contains("<path"));
        assert!(expected_svg.find("<line").unwrap() < expected_svg.find("<ellipse").unwrap());
        let bytes = doc.project();
        assert_eq!(&bytes[8..10], &2u16.to_le_bytes());
        let loaded = Owned::from_project(&bytes);
        assert_eq!(loaded.svg(), expected_svg);
        assert_eq!(loaded.project(), bytes);
        unsafe {
            for (index, style) in [
                FREEHAND_STYLE,
                shape_style(1, None),
                shape_style(2, Some(0xffaabb)),
                shape_style(3, Some(0x112233)),
            ]
            .into_iter()
            .enumerate()
            {
                let mut actual = FREEHAND_STYLE;
                assert_eq!(ep_object_style(loaded.0, index, &mut actual), 0);
                assert_eq!(actual, style);
            }
            for _ in 0..4 {
                assert_eq!(ep_undo(loaded.0), 1);
            }
            assert_eq!(ep_stroke_count(loaded.0), 0);
            for _ in 0..4 {
                assert_eq!(ep_redo(loaded.0), 1);
            }
        }
        assert_eq!(loaded.svg(), expected_svg);
        unsafe {
            assert_eq!(ep_undo(loaded.0), 1);
        }
        assert_eq!(
            loaded.shape(&reverse_corners, shape_style(2, None), 0, 0.1),
            0
        );
        unsafe {
            assert_eq!(ep_redo_count(loaded.0), 0);
        }
    }

    #[test]
    fn invalid_shapes_preserve_document_and_redo() {
        let doc = Owned::new();
        let valid_points = [point(10.0, 20.0), point(30.0, 40.0)];
        assert_eq!(doc.shape(&valid_points, shape_style(3, Some(0)), 0, 1.0), 0);
        unsafe {
            assert_eq!(ep_undo(doc.0), 1);
        }
        let original = doc.project();
        for style in [
            shape_style(0, None),
            shape_style(4, None),
            shape_style(1, Some(1)),
            shape_style(2, Some(0x1000000)),
            EpObjectStyle {
                kind: 2,
                fill_enabled: 2,
                fill_rgb: 0,
            },
            EpObjectStyle {
                kind: 3,
                fill_enabled: 0,
                fill_rgb: 1,
            },
        ] {
            assert_eq!(doc.shape(&valid_points, style, 0, 1.0), INVALID);
        }
        for kind in 1..=3 {
            for invalid_points in [
                [point(1.0, 1.0), point(1.0, 1.0)],
                [point(f32::NAN, 1.0), point(2.0, 3.0)],
                [point(1.0, 1.0), point(1201.0, 2.0)],
                [point(1.0, 1.0), point(2.0, f32::INFINITY)],
            ] {
                assert_eq!(
                    doc.shape(&invalid_points, shape_style(kind, None), 0, 1.0),
                    INVALID
                );
            }
        }
        for kind in 2..=3 {
            for invalid_points in [
                [point(1.0, 1.0), point(1.0, 2.0)],
                [point(1.0, 1.0), point(2.0, 1.0)],
            ] {
                assert_eq!(
                    doc.shape(&invalid_points, shape_style(kind, None), 0, 1.0),
                    INVALID
                );
            }
        }
        assert_eq!(
            doc.shape(&valid_points, shape_style(1, None), 0x1000000, 1.0),
            INVALID
        );
        assert_eq!(
            doc.shape(&valid_points, shape_style(1, None), 0, f32::NAN),
            INVALID
        );
        unsafe {
            assert_eq!(
                ep_add_shape(doc.0, valid_points.as_ptr(), ptr::null(), 0, 1.0),
                INVALID
            );
            assert_eq!(
                ep_add_shape(doc.0, ptr::null(), &shape_style(1, None), 0, 1.0),
                INVALID
            );
            assert_eq!(
                ep_add_shape(
                    ptr::null_mut(),
                    valid_points.as_ptr(),
                    &shape_style(1, None),
                    0,
                    1.0
                ),
                INVALID
            );
            let mut untouched = shape_style(3, Some(0xabcdef));
            assert_eq!(ep_object_style(doc.0, 0, &mut untouched), INVALID);
            assert_eq!(untouched, shape_style(3, Some(0xabcdef)));
            assert_eq!(ep_object_style(ptr::null(), 0, &mut untouched), INVALID);
            assert_eq!(ep_object_style(doc.0, 0, ptr::null_mut()), INVALID);
            assert_eq!(ep_redo_count(doc.0), 1);
        }
        assert_eq!(doc.project(), original);
    }

    #[test]
    fn v1_golden_fixture_loads_as_freehand_and_upgrades_to_v2() {
        // Independent fixture built from the published v1 layout and zlib CRC32.
        let hex = "4544555041494e540100000040000000b0040000200300000100000002000000ccbbaa00000060400200000000004841000009420000964400004844421231d9";
        let bytes: Vec<u8> = (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect();
        let doc = Owned::from_project(&bytes);
        unsafe {
            let mut style = shape_style(3, Some(0));
            assert_eq!(ep_object_style(doc.0, 0, &mut style), 0);
            assert_eq!(style, FREEHAND_STYLE);
            assert_eq!(ep_document_width(doc.0), 1200);
            assert_eq!(ep_document_height(doc.0), 800);
        }
        assert!(doc.svg().contains("<path d=\"M12.5 34.25 L1200 800 "));
        assert!(doc
            .svg()
            .contains("stroke=\"#aabbcc\" stroke-width=\"3.5\""));
        let upgraded = doc.project();
        assert_eq!(&upgraded[8..10], &2u16.to_le_bytes());
        assert_eq!(upgraded.len(), bytes.len() + 12);
        assert_eq!(Owned::from_project(&upgraded).svg(), doc.svg());
        unsafe {
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!(ep_redo(doc.0), 1);
        }
        for length in 0..bytes.len() {
            reject_project(&bytes[..length]);
        }
    }

    #[test]
    fn malformed_shape_files_fail_even_with_valid_crc() {
        let doc = Owned::new();
        assert_eq!(
            doc.shape(
                &[point(10.0, 20.0), point(40.0, 70.0)],
                shape_style(3, Some(0xffaa22)),
                0x010203,
                2.5
            ),
            0
        );
        let bytes = doc.project();
        for (offset, value) in [
            (40, 1),
            (40, 3),
            (44, 4),
            (44, 1),
            (44, 0),
            (48, 2),
            (52, 0x1000000),
            (56, f32::NAN.to_bits()),
            (60, f32::NEG_INFINITY.to_bits()),
            (64, 10.0f32.to_bits()),
            (68, 20.0f32.to_bits()),
            (64, 1200.1f32.to_bits()),
        ] {
            let mut bad = bytes.clone();
            bad[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
            repair_checksum(&mut bad);
            reject_project(&bad);
        }
        for length in 0..bytes.len() {
            reject_project(&bytes[..length]);
        }
        for index in 0..bytes.len() {
            let mut bad = bytes.clone();
            bad[index] ^= 1;
            reject_project(&bad);
        }
        let mut trailing = bytes.clone();
        trailing.push(0);
        reject_project(&trailing);
        assert_eq!(doc.project(), bytes);
    }
}

#[cfg(test)]
mod background_tests;
