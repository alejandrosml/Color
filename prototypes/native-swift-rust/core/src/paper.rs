//! The colour of the sheet: one 24-bit colour under the whole drawing.
//!
//! A new document and every project older than v4 have a white sheet. The
//! colour is part of the drawing: changing it is an ordinary reversible
//! command, exports paint it first, and a sheet that is not white is stored
//! by project v4. An image background, when present, is painted over it.
use super::*;

/// Colour of the sheet, 24-bit RGB; `u32::MAX` for NULL.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently accessed.
#[no_mangle]
pub unsafe extern "C" fn ep_paper_color(document: *const EpDocument) -> u32 {
    unsafe { document.as_ref() }.map_or(u32::MAX, |doc| doc.paper)
}

/// Changes the colour of the sheet. Returns 1 changed, 0 same colour, -1 NULL
/// / not a 24-bit colour / history limits, -2 allocation failure. No-op and
/// failure keep drawing, undo and redo; success clears redo. Objects, their
/// indices and revisions are untouched.
///
/// # Safety
/// Non-null `document` must be live, aligned and exclusively accessible.
#[no_mangle]
pub unsafe extern "C" fn ep_set_paper_color(document: *mut EpDocument, rgb: u32) -> i32 {
    let Some(doc) = (unsafe { document.as_mut() }) else {
        return INVALID;
    };
    if rgb > WHITE_PAPER {
        return INVALID;
    }
    if doc.paper == rgb {
        return 0;
    }
    if let Err(status) = doc.prepare_edit(0, 0, false) {
        return status;
    }
    let previous = std::mem::replace(&mut doc.paper, rgb);
    doc.commit_edit(Edit::Paper { rgb: previous }, 0, 0);
    1
}

#[cfg(test)]
mod tests;
