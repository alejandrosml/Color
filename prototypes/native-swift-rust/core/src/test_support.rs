//! Shared helpers of the layer, text, stamp, paper, resize, contour and page
//! tests. Every helper goes through the C functions, exactly as the interface
//! does.
use super::*;
use std::ffi::CStr;

pub(crate) struct Owned(pub *mut EpDocument);

/// Project bytes, SVG, undo count, redo count, layers and active layer.
pub(crate) type State = (Vec<u8>, String, usize, usize, Vec<(u32, bool, usize)>, u32);

impl Owned {
    pub fn new() -> Self {
        Self::sized(1200, 800)
    }
    pub fn sized(width: u32, height: u32) -> Self {
        let pointer = ep_document_new(width, height);
        assert!(!pointer.is_null());
        Self(pointer)
    }
    pub fn from_png(bytes: &[u8]) -> Self {
        let mut status = 99;
        let pointer =
            unsafe { ep_document_from_background_png(bytes.as_ptr(), bytes.len(), &mut status) };
        assert_eq!(status, 0);
        assert!(!pointer.is_null());
        Self(pointer)
    }
    pub fn doc(&self) -> &EpDocument {
        unsafe { &*self.0 }
    }
    pub fn paper(&self) -> u32 {
        unsafe { ep_paper_color(self.0) }
    }
    pub fn set_paper(&self, rgb: u32) -> i32 {
        unsafe { ep_set_paper_color(self.0, rgb) }
    }
    pub fn shape(&self, kind: u32, corners: [EpPoint; 2], rgb: u32, width: f32) -> i32 {
        let style = EpObjectStyle {
            kind,
            fill_enabled: 0,
            fill_rgb: 0,
        };
        unsafe { ep_add_shape(self.0, corners.as_ptr(), &style, rgb, width) }
    }
    pub fn scale(&self, index: usize, factor: f32, width: f32) -> i32 {
        unsafe { ep_scale_object(self.0, index, factor, width) }
    }
    pub fn points(&self, index: usize) -> Vec<EpPoint> {
        let mut points = vec![point(-1.0, -1.0); self.info(index).point_count];
        let copied = unsafe { ep_copy_points(self.0, index, points.as_mut_ptr(), points.len()) };
        assert_eq!(copied, points.len());
        points
    }
    /// Project bytes and SVG of an immutable export snapshot of this document.
    pub fn snapshot(&self) -> (Vec<u8>, String) {
        unsafe {
            let mut status = 99;
            let snapshot = ep_export_snapshot_new(self.0, &mut status);
            assert_eq!(status, 0);
            assert!(!snapshot.is_null());
            let mut bytes = vec![0; ep_export_snapshot_project_size(snapshot)];
            assert_eq!(
                ep_export_snapshot_copy_project(snapshot, bytes.as_mut_ptr(), bytes.len()),
                0
            );
            let raw = ep_export_snapshot_export_svg(snapshot);
            assert!(!raw.is_null());
            let svg = CStr::from_ptr(raw).to_str().unwrap().to_owned();
            ep_string_free(raw);
            ep_export_snapshot_free(snapshot);
            (bytes, svg)
        }
    }
    pub fn count(&self) -> usize {
        unsafe { ep_stroke_count(self.0) }
    }
    pub fn stroke(&self, points: &[EpPoint], rgb: u32) -> i32 {
        unsafe { ep_add_stroke(self.0, points.as_ptr(), points.len(), rgb, 3.0) }
    }
    pub fn dot(&self, x: f32, y: f32) -> i32 {
        self.stroke(&[point(x, y)], 0x112233)
    }
    pub fn text(&self, corners: [EpPoint; 2], rgb: u32, size: f32, text: &str) -> i32 {
        unsafe {
            ep_add_text(
                self.0,
                corners.as_ptr(),
                rgb,
                size,
                0,
                text.as_ptr(),
                text.len(),
            )
        }
    }
    pub fn set_text(
        &self,
        index: usize,
        corners: [EpPoint; 2],
        rgb: u32,
        size: f32,
        text: &str,
    ) -> i32 {
        unsafe {
            ep_set_text(
                self.0,
                index,
                corners.as_ptr(),
                rgb,
                size,
                0,
                text.as_ptr(),
                text.len(),
            )
        }
    }
    pub fn stamp(&self, corners: [EpPoint; 2], id: u32, rgb: u32) -> i32 {
        unsafe { ep_add_stamp(self.0, corners.as_ptr(), id, rgb) }
    }
    pub fn object_text(&self, index: usize) -> String {
        let extra = self.extra(index);
        let mut bytes = vec![0u8; extra.text_bytes];
        let copied = unsafe { ep_copy_object_text(self.0, index, bytes.as_mut_ptr(), bytes.len()) };
        assert_eq!(copied, extra.text_bytes);
        String::from_utf8(bytes).unwrap()
    }
    pub fn extra(&self, index: usize) -> EpObjectExtra {
        let mut extra = EpObjectExtra {
            layer: 99,
            param: 99,
            text_bytes: 99,
        };
        assert_eq!(unsafe { ep_object_extra(self.0, index, &mut extra) }, 0);
        extra
    }
    pub fn kind(&self, index: usize) -> u32 {
        let mut style = EpObjectStyle {
            kind: 99,
            fill_enabled: 99,
            fill_rgb: 99,
        };
        assert_eq!(unsafe { ep_object_style(self.0, index, &mut style) }, 0);
        style.kind
    }
    pub fn info(&self, index: usize) -> EpStrokeInfo {
        let mut info = EpStrokeInfo {
            rgb: 99,
            width: 99.0,
            point_count: 99,
        };
        assert_eq!(unsafe { ep_stroke_info(self.0, index, &mut info) }, 0);
        info
    }
    pub fn layers(&self) -> Vec<(u32, bool, usize)> {
        (0..unsafe { ep_layer_count(self.0) })
            .map(|position| {
                let mut info = EpLayerInfo {
                    id: 99,
                    visible: 99,
                    object_count: 99,
                };
                assert_eq!(unsafe { ep_layer_info(self.0, position, &mut info) }, 0);
                (info.id, info.visible == 1, info.object_count)
            })
            .collect()
    }
    pub fn active(&self) -> u32 {
        unsafe { ep_active_layer(self.0) }
    }
    pub fn undo(&self) -> i32 {
        unsafe { ep_undo(self.0) }
    }
    pub fn redo(&self) -> i32 {
        unsafe { ep_redo(self.0) }
    }
    pub fn svg(&self) -> String {
        unsafe {
            let raw = ep_export_svg(self.0);
            assert!(!raw.is_null());
            let result = CStr::from_ptr(raw).to_str().unwrap().to_owned();
            ep_string_free(raw);
            result
        }
    }
    pub fn project(&self) -> Vec<u8> {
        unsafe {
            let mut bytes = vec![0; ep_project_size(self.0)];
            assert_eq!(ep_copy_project(self.0, bytes.as_mut_ptr(), bytes.len()), 0);
            bytes
        }
    }
    pub fn try_from_project(bytes: &[u8]) -> Result<Self, i32> {
        let mut status = 99;
        let result = unsafe { ep_document_from_project(bytes.as_ptr(), bytes.len(), &mut status) };
        if result.is_null() {
            assert!(status == INVALID || status == ALLOCATION_FAILURE);
            Err(status)
        } else {
            assert_eq!(status, 0);
            Ok(Self(result))
        }
    }
    pub fn from_project(bytes: &[u8]) -> Self {
        Self::try_from_project(bytes).unwrap_or_else(|status| panic!("rejected: {status}"))
    }
    /// A sheet of 1200 x 800 whose only object is a closed contour: see
    /// `contour_project`.
    pub fn contour(points: &[EpPoint], rgb: u32, width: f32, fill: Option<u32>) -> Self {
        Self::from_project(&contour_project(points, rgb, width, fill))
    }
    /// Complete observable state: bytes, vector export, history and layers.
    pub fn state(&self) -> State {
        (
            self.project(),
            self.svg(),
            unsafe { ep_undo_count(self.0) },
            unsafe { ep_redo_count(self.0) },
            self.layers(),
            self.active(),
        )
    }
    /// Recomputes every counter from the structures that own the payloads.
    pub fn assert_accounting(&self) {
        let document = self.doc();
        let mut points: usize = document.strokes.iter().map(|s| s.points.len()).sum();
        let mut text: usize = document.strokes.iter().map(|s| s.text.len()).sum();
        let mut objects = document.strokes.len();
        assert_eq!(document.active_points, points);
        assert_eq!(document.active_text_bytes, text);
        assert_eq!(
            document.active_extended,
            document.strokes.iter().filter(|s| s.extended()).count()
        );
        assert_eq!(
            document.active_contours,
            document
                .strokes
                .iter()
                .filter(|s| s.style.kind == KIND_CONTOUR)
                .count()
        );
        for edit in &document.history {
            match edit {
                Edit::Presence {
                    detached: Some(stroke),
                    ..
                } => {
                    points += stroke.points.len();
                    text += stroke.text.len();
                    objects += 1;
                }
                Edit::LayerPresence { detached, .. } => {
                    for (_, stroke) in detached {
                        points += stroke.points.len();
                        text += stroke.text.len();
                        objects += 1;
                    }
                }
                Edit::Text { text: other, .. } => text += other.len(),
                _ => {}
            }
        }
        assert_eq!(document.retained_points, points);
        assert_eq!(document.retained_text_bytes, text);
        assert_eq!(document.retained_objects, objects);
        assert!(points <= MAX_RETAINED_POINTS && objects <= MAX_RETAINED_OBJECTS);
        assert!(text <= MAX_RETAINED_TEXT_BYTES);
        assert!(document.active_text_bytes <= MAX_TOTAL_TEXT_BYTES);
        assert!(document.history.len() <= MAX_HISTORY_STEPS);
        assert!((1..=MAX_LAYERS).contains(&document.layer_count));
        for stroke in &document.strokes {
            assert!(document.layers().iter().any(|l| l.id == stroke.layer));
        }
        assert!(document
            .layers()
            .iter()
            .any(|l| l.id == document.active_layer));
        // New objects never join a page.
        assert!(!document.locked(document.active_layer));
    }
    /// Lock of every layer, bottom first, as ep_layer_locked reports it.
    pub fn locks(&self) -> Vec<bool> {
        (0..unsafe { ep_layer_count(self.0) })
            .map(
                |position| match unsafe { ep_layer_locked(self.0, position) } {
                    0 => false,
                    1 => true,
                    other => panic!("ep_layer_locked({position}) = {other}"),
                },
            )
            .collect()
    }
    /// Objects of locked layers: undo never takes them away.
    pub fn pinned(&self) -> usize {
        let document = self.doc();
        document
            .strokes
            .iter()
            .filter(|s| document.locked(s.layer))
            .count()
    }
    /// Revision of every object, in list order.
    pub fn revisions(&self) -> Vec<u64> {
        (0..self.count())
            .map(|index| unsafe { ep_object_revision(self.0, index) })
            .collect()
    }
}

impl Drop for Owned {
    fn drop(&mut self) {
        unsafe { ep_document_free(self.0) };
    }
}

pub(crate) fn point(x: f32, y: f32) -> EpPoint {
    EpPoint { x, y }
}

pub(crate) fn corners(x0: f32, y0: f32, x1: f32, y1: f32) -> [EpPoint; 2] {
    [point(x0, y0), point(x1, y1)]
}

/// Rewrites the final checksum after a deliberate change of the payload.
pub(crate) fn resealed(mut bytes: Vec<u8>) -> Vec<u8> {
    let end = bytes.len() - 4;
    let checksum = crc32(&bytes[..end]);
    bytes[end..].copy_from_slice(&checksum.to_le_bytes());
    bytes
}

pub(crate) fn put_u32(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

/// Version 5 bytes of a sheet of 1200 x 800 whose only object, on its one
/// layer, is a closed contour of these points: the bytes of a freehand
/// stroke with its kind changed. No function of the interface draws a new
/// contour: a colouring page or a file brings it.
pub(crate) fn contour_project(
    points: &[EpPoint],
    rgb: u32,
    width: f32,
    fill: Option<u32>,
) -> Vec<u8> {
    let doc = Owned::new();
    assert_eq!(
        unsafe { ep_add_stroke(doc.0, points.as_ptr(), points.len(), rgb, width) },
        0
    );
    // A black sheet asks for version 4, whose records name their layer.
    assert_eq!(doc.set_paper(0), 1);
    let mut bytes = doc.project();
    assert_eq!(bytes[8], 4);
    bytes[8] = 5;
    // White again: the contour alone asks for version 5.
    put_u32(&mut bytes, 48, 0);
    let record = 56 + 8;
    put_u32(&mut bytes, record + 12, KIND_CONTOUR);
    if let Some(fill) = fill {
        put_u32(&mut bytes, record + 16, 1);
        put_u32(&mut bytes, record + 20, fill);
    }
    resealed(bytes)
}

/// The bytes of a version 4 project as version 5, with the layers at these
/// positions of the stack locked. The active layer must not be one of them.
pub(crate) fn locked_project(mut bytes: Vec<u8>, positions: &[usize]) -> Vec<u8> {
    assert_eq!(bytes[8], 4);
    bytes[8] = 5;
    for position in positions {
        let flags = 56 + position * 8 + 4;
        let word = u32::from_le_bytes(bytes[flags..flags + 4].try_into().unwrap());
        put_u32(&mut bytes, flags, word | 2);
    }
    resealed(bytes)
}
