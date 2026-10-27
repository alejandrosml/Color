//! Text objects: a box, a colour, a size and bounded UTF-8 characters.
//!
//! The interface lays the characters out with its bundled font and supplies
//! the resulting box; this core never measures glyphs. It validates and stores
//! the characters, and writes them as real SVG text with the metrics of font 0
//! so that an export and the sheet place every line at the same height.
use super::*;

/// Line height of font 0 (DejaVu Sans), as a multiple of the text size.
const LINE_HEIGHT: f64 = 1.2;
/// Distance from the top of a line to its baseline: the line height shared
/// between ascent and descent in the font's own 1901:483 proportion.
const BASELINE: f64 = LINE_HEIGHT * 1901.0 / 2384.0;

/// Whether a character leaves a mark by itself. White space does not, nor do
/// the characters that Unicode asks a renderer to ignore when nothing else
/// stands with them (Default_Ignorable_Code_Point: soft hyphen, zero-width
/// spaces and joiners, direction marks, variation selectors, the byte-order
/// mark, tags). They stay allowed inside a text, where joiners and selectors
/// have a job; a text made only of them would be an object nobody can see.
pub(super) fn leaves_a_mark(character: char) -> bool {
    !character.is_whitespace()
        && !matches!(
            character,
            '\u{ad}'
                | '\u{34f}'
                | '\u{61c}'
                | '\u{115f}'..='\u{1160}'
                | '\u{17b4}'..='\u{17b5}'
                | '\u{180b}'..='\u{180f}'
                | '\u{200b}'..='\u{200f}'
                | '\u{202a}'..='\u{202e}'
                | '\u{2060}'..='\u{206f}'
                | '\u{3164}'
                | '\u{fe00}'..='\u{fe0f}'
                | '\u{feff}'
                | '\u{ffa0}'
                | '\u{fff0}'..='\u{fff8}'
                | '\u{1bca0}'..='\u{1bca3}'
                | '\u{1d173}'..='\u{1d17a}'
                | '\u{e0000}'..='\u{e0fff}'
        )
}

/// One to 2048 bytes of UTF-8, at most 32 lines separated by U+000A, at least
/// one character that leaves a mark. Only characters valid in XML 1.0 are
/// accepted, and no other control or line/paragraph separator: the caller
/// normalizes them.
pub(super) fn valid_text(bytes: &[u8]) -> bool {
    if bytes.is_empty() || bytes.len() > MAX_TEXT_BYTES {
        return false;
    }
    let Ok(text) = std::str::from_utf8(bytes) else {
        return false;
    };
    let mut lines = 1;
    let mut visible = false;
    for character in text.chars() {
        match character {
            '\n' => {
                lines += 1;
                if lines > MAX_TEXT_LINES {
                    return false;
                }
            }
            '\u{2028}' | '\u{2029}' => return false,
            '\u{20}'..='\u{7e}'
            | '\u{a0}'..='\u{d7ff}'
            | '\u{e000}'..='\u{fffd}'
            | '\u{10000}'..='\u{10ffff}' => visible |= leaves_a_mark(character),
            _ => return false,
        }
    }
    visible
}

/// Markup around the characters of one text; escapes are counted separately.
pub(super) fn text_svg_bytes(text: &[u8]) -> usize {
    let lines = 1 + text.iter().filter(|byte| **byte == b'\n').count();
    256 + lines * 96
}

/// `x`/`y` are the top-left corner of the box; every line gets its own
/// baseline. The family list lets a viewer without DejaVu Sans fall back.
pub(super) fn write_text_svg(
    result: &mut String,
    text: &[u8],
    x: f64,
    y: f64,
    size: f32,
    rgb: u32,
) -> Option<()> {
    let text = std::str::from_utf8(text).ok()?;
    writeln!(
        result,
        "<text font-family=\"'DejaVu Sans', Verdana, sans-serif\" font-size=\"{}\" fill=\"#{:06x}\" xml:space=\"preserve\">",
        size, rgb
    )
    .ok()?;
    for (index, line) in text.split('\n').enumerate() {
        if line.is_empty() {
            continue;
        }
        let baseline = y + (index as f64 * LINE_HEIGHT + BASELINE) * f64::from(size);
        write!(result, "<tspan x=\"{}\" y=\"{}\">", x, baseline).ok()?;
        for character in line.chars() {
            match character {
                '&' => result.push_str("&amp;"),
                '<' => result.push_str("&lt;"),
                '>' => result.push_str("&gt;"),
                other => result.push(other),
            }
        }
        result.push_str("</tspan>\n");
    }
    result.push_str("</text>\n");
    Some(())
}

// Copies the caller's characters only after every scalar check has passed.
unsafe fn checked_text<'a>(utf8: *const u8, length: usize) -> Option<&'a [u8]> {
    if utf8.is_null() || !(1..=MAX_TEXT_BYTES).contains(&length) {
        return None;
    }
    let bytes = unsafe { slice::from_raw_parts(utf8, length) };
    valid_text(bytes).then_some(bytes)
}

/// Adds a text on the active layer. `box_points` are two opposite corners of
/// its laid-out box, inside the page and with a non-zero width and height;
/// lines start at the box's top-left corner. `size` is finite, 4..2048
/// document units; `font` must be 0. `utf8` holds 1..2048 bytes of valid
/// UTF-8, at most 32 lines separated by U+000A, at least one visible
/// character, and no control character. Visible texts hold at most 1 MiB.
/// Returns 0 on success, -1 invalid input/limits, -2 allocation failure;
/// failure leaves drawing and history unchanged, success clears redo.
///
/// # Safety
/// Same exclusive document rules as ep_add_stroke. Non-null `box_points` must
/// address two initialized EpPoint values and non-null `utf8` `length`
/// initialized bytes; both are copied, stay unchanged during the call and are
/// disjoint from document-owned storage.
#[no_mangle]
pub unsafe extern "C" fn ep_add_text(
    document: *mut EpDocument,
    box_points: *const EpPoint,
    rgb: u32,
    size: f32,
    font: u32,
    utf8: *const u8,
    length: usize,
) -> i32 {
    let Some(text) = (unsafe { checked_text(utf8, length) }) else {
        return INVALID;
    };
    let style = EpObjectStyle {
        kind: KIND_TEXT,
        fill_enabled: 0,
        fill_rgb: 0,
    };
    unsafe { add_object(document, box_points, 2, rgb, size, style, font, text) }
}

/// Replaces box, colour, size, font and characters of the text at `index` in
/// one reversible command; validation matches ep_add_text. Returns 1 changed,
/// 0 identical content, -1 invalid input / not a text / a text of a locked
/// layer / limits, -2 allocation failure. No-op and failure preserve
/// drawing, undo and redo.
///
/// # Safety
/// Same pointer rules as ep_add_text.
#[no_mangle]
pub unsafe extern "C" fn ep_set_text(
    document: *mut EpDocument,
    index: usize,
    box_points: *const EpPoint,
    rgb: u32,
    size: f32,
    font: u32,
    utf8: *const u8,
    length: usize,
) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    let Some(text) = (unsafe { checked_text(utf8, length) }) else {
        return INVALID;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return INVALID;
    };
    if stroke.style.kind != KIND_TEXT
        || doc.locked(stroke.layer)
        || box_points.is_null()
        || rgb > 0x00ff_ffff
        || !valid_width(KIND_TEXT, size)
        || !valid_param(KIND_TEXT, font)
    {
        return INVALID;
    }
    let points = unsafe { slice::from_raw_parts(box_points, 2) };
    if points.iter().any(|point| {
        !point.x.is_finite()
            || !point.y.is_finite()
            || point.x < 0.0
            || point.y < 0.0
            || point.x > doc.width as f32
            || point.y > doc.height as f32
    }) || !valid_shape_points(KIND_TEXT, points)
    {
        return INVALID;
    }
    if stroke.point_at(0) == points[0]
        && stroke.point_at(1) == points[1]
        && stroke.rgb == rgb
        && stroke.width == size
        && stroke.param == font
        && stroke.text == text
    {
        return 0;
    }
    let active_without = doc.active_text_bytes - stroke.text.len();
    if text.len() > MAX_TOTAL_TEXT_BYTES - active_without {
        return INVALID;
    }
    let mut owned = Vec::new();
    if owned.try_reserve_exact(text.len()).is_err() {
        return ALLOCATION_FAILURE;
    }
    owned.extend_from_slice(text);
    if let Err(status) = doc.prepare_text_edit(0, 0, text.len(), true) {
        return status;
    }
    let revision = doc.issue_revision();
    let stroke = &mut doc.strokes[index];
    let previous = Edit::Text {
        index,
        points: [stroke.points[0], stroke.points[1]],
        translation: stroke.translation,
        rgb: stroke.rgb,
        width: stroke.width,
        param: stroke.param,
        text: std::mem::replace(&mut stroke.text, owned),
        revision: stroke.revision,
    };
    stroke.points[0] = points[0];
    stroke.points[1] = points[1];
    stroke.translation = [0.0; 2];
    stroke.rgb = rgb;
    stroke.width = size;
    stroke.param = font;
    stroke.revision = revision;
    doc.active_text_bytes = active_without + text.len();
    doc.commit_text_edit(previous, 0, 0, text.len());
    1
}

/// Copies the complete UTF-8 of a text object, without a terminator. Returns
/// its byte count, or 0 for an invalid document/index, an object without
/// text, a NULL output or an insufficient capacity. No partial write.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently accessed.
/// `out_bytes` must be writable for `capacity` bytes, disjoint from
/// document-owned storage and exclusively accessible during the call.
#[no_mangle]
pub unsafe extern "C" fn ep_copy_object_text(
    document: *const EpDocument,
    index: usize,
    out_bytes: *mut u8,
    capacity: usize,
) -> usize {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return 0;
    };
    let Some(stroke) = doc.strokes.get(index) else {
        return 0;
    };
    if out_bytes.is_null() || stroke.text.is_empty() || capacity < stroke.text.len() {
        return 0;
    }
    unsafe {
        ptr::copy_nonoverlapping(stroke.text.as_ptr(), out_bytes, stroke.text.len());
    }
    stroke.text.len()
}

#[cfg(test)]
mod tests;
