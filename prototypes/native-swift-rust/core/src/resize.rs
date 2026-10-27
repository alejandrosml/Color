//! Resizing one object: a constant-size change of its transform.
//!
//! Base points are never rewritten. A visible point is `base * scale +
//! translation`; resizing multiplies the scale and chooses the translation
//! that keeps the object's centre, moved only as far as needed to stay on the
//! page. Undo swaps the previous transform back, without allocating and
//! without inverting rounded coordinates.
use super::*;

/// Resizes the object at `index` by `factor` (1/64..64) around the centre of
/// its points, then moves it just enough to keep every point on the page.
/// `width` is the outline width it gets, in the usual 0.1..512 range: the
/// caller decides whether outlines follow the size. A stamp keeps its
/// constant 1.0. Texts are refused, because their box follows their
/// characters: use ep_set_text with a freshly measured box.
///
/// An object whose points all coincide (a dot) has no size: only its width
/// changes, any number of times. An object that has a size never loses it:
/// a factor that would bring all its points together is refused, as is one
/// that would take the sizes it has been given since it was drawn outside
/// 1e-9..1e9 times its original size.
///
/// Returns 1 changed, 0 nothing to change (factor 1, or a dot, with the
/// width it already has), -1 invalid input, an object of a locked layer, an
/// object that would not fit the page, an object that would lose its width,
/// its height or its extent, or limits, -2 allocation failure. No-op and
/// failure keep drawing, undo and redo; success clears redo and issues a new
/// revision for the object, even when the change is too small to move a
/// rounded coordinate.
///
/// # Safety
/// Non-null `document` must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_scale_object(
    document: *mut EpDocument,
    index: usize,
    factor: f32,
    width: f32,
) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return INVALID;
    };
    let kind = stroke.style.kind;
    if kind == KIND_TEXT
        || doc.locked(stroke.layer)
        || !factor.is_finite()
        || !(MIN_SCALE_FACTOR..=MAX_SCALE_FACTOR).contains(&factor)
        || !valid_width(kind, width)
    {
        return INVALID;
    }
    // A dot has nothing to scale, and a factor of one scales nothing: the
    // transform is kept exactly, so that neither can ever wear it out.
    let coincide = |scale: f64, translation: [f64; 2]| {
        let first = Stroke::transformed(stroke.points[0], scale, translation);
        stroke
            .points
            .iter()
            .all(|point| Stroke::transformed(*point, scale, translation) == first)
    };
    let (scale, translation) = if factor == 1.0 || coincide(stroke.scale, stroke.translation) {
        if width == stroke.width {
            return 0;
        }
        (stroke.scale, stroke.translation)
    } else {
        let Some((scale, translation)) =
            stroke.scaled_transform(f64::from(factor), doc.width, doc.height)
        else {
            return INVALID;
        };
        // What has a size keeps one: its points are never brought together.
        if coincide(scale, translation) {
            return INVALID;
        }
        (scale, translation)
    };
    let inverse = Edit::Scale {
        index,
        scale: stroke.scale,
        translation: stroke.translation,
        width: stroke.width,
        revision: stroke.revision,
    };
    if let Err(status) = doc.prepare_edit(0, 0, true) {
        return status;
    }
    let revision = doc.issue_revision();
    let stroke = &mut doc.strokes[index];
    stroke.scale = scale;
    stroke.translation = translation;
    stroke.width = width;
    stroke.revision = revision;
    doc.commit_edit(inverse, 0, 0);
    1
}

#[cfg(test)]
mod tests;
