//! The pictures of the interface and the colouring pages, as the interface
//! asks for them: read before the build from their SVG files (art.rs and
//! pages.rs, with the `svg` feature) and compiled in as they were written,
//! in `catalogues/` (R-01 of the retrospective of October 2026). The first
//! use takes no time, and the cores of the stores, built without the `svg`
//! feature, carry neither usvg nor the readers: the library is a third
//! lighter.
//!
//! - `interface.txt`: the descriptions of the pictures of the interface, the
//!   text of `ep_art_catalog`;
//! - `pages.txt`: the catalogue of the pages, the text of `ep_page_catalog`;
//! - `pages.bin`: the project (version 5) of the document of every page, in
//!   the order of their identifiers, each one after its length as four
//!   bytes, little-endian, the number of pages first, the same way;
//! - `univers.txt`: the universes of the studio (Color 1.2), one after the
//!   other, as universes.rs describes them; `ep_universe` hands over one.
//!
//! A test writes them again from the files and compares them to the byte;
//! after a change of a picture or of a page, or of how they are read:
//!
//! ```text
//! COLOR_REGENERATE_CATALOGUES=1 cargo test --offline catalogues
//! ```
use super::*;

/// Largest SVG text accepted from a caller.
pub const MAX_SVG_BYTES: usize = 1024 * 1024;

const INTERFACE: &str = include_str!("catalogues/interface.txt");
const PAGE_CATALOGUE: &str = include_str!("catalogues/pages.txt");
const PAGE_PROJECTS: &[u8] = include_bytes!("catalogues/pages.bin");
const UNIVERSES: &str = include_str!("catalogues/univers.txt");

/// The text of universe `index` in `univers.txt`: from its `U` line to the
/// line before the next one.
fn universe_text(index: u32) -> Option<&'static str> {
    let mut starts = UNIVERSES
        .match_indices("U ")
        .map(|(at, _)| at)
        .filter(|&at| at == 0 || UNIVERSES.as_bytes()[at - 1] == b'\n');
    let start = starts.nth(index as usize)?;
    let end = starts.next().unwrap_or(UNIVERSES.len());
    UNIVERSES.get(start..end)
}

/// The project of page `page`, as `pages.bin` holds it.
fn page_project(page: u32) -> Option<&'static [u8]> {
    let word = |at: usize| -> Option<usize> {
        let bytes = PAGE_PROJECTS.get(at..at.checked_add(4)?)?;
        Some(u32::from_le_bytes(bytes.try_into().ok()?) as usize)
    };
    if page as usize >= word(0)? {
        return None;
    }
    let mut at: usize = 4;
    for _ in 0..page {
        at = at.checked_add(4)?.checked_add(word(at)?)?;
    }
    let length = word(at)?;
    PAGE_PROJECTS.get(at + 4..(at + 4).checked_add(length)?)
}

/// Owned, NUL-terminated copy of [text], or NULL when memory is short.
pub(crate) fn owned_text(text: &str) -> *mut c_char {
    let mut bytes = Vec::new();
    if bytes.try_reserve_exact(text.len() + 1).is_err() {
        return ptr::null_mut();
    }
    bytes.extend_from_slice(text.as_bytes());
    bytes.push(0);
    // A description is made of numbers, letters and punctuation: no NUL.
    CString::from_vec_with_nul(bytes).map_or(ptr::null_mut(), CString::into_raw)
}

/// Number of pictures of the interface compiled into this core.
#[no_mangle]
pub extern "C" fn ep_art_count() -> u32 {
    INTERFACE
        .lines()
        .filter(|line| line.starts_with("P "))
        .count() as u32
}

/// Returns the pictures of the interface as owned, NUL-terminated ASCII text,
/// or NULL on allocation failure. One description per picture, in the order
/// of their keys; the format is documented at `art::describe`. Release with
/// ep_string_free only.
#[no_mangle]
pub extern "C" fn ep_art_catalog() -> *mut c_char {
    owned_text(INTERFACE)
}

/// Reads SVG text and returns its description, as ep_art_catalog does for
/// one picture, with the key `-`. NULL for a NULL pointer, more than
/// MAX_SVG_BYTES, text that is not UTF-8, an SVG that cannot be read, one
/// that uses what this version does not draw (masks, filters, patterns, blend
/// modes, embedded images, text), or exhausted memory; always NULL in a core
/// built without the `svg` feature, which reads no SVG: those of the stores.
/// No file is opened and nothing is fetched, whatever the SVG refers to.
/// Release with ep_string_free only.
///
/// # Safety
/// Non-null `svg` must address `len` initialized bytes that stay unchanged
/// for the whole call; they are only read.
#[no_mangle]
pub unsafe extern "C" fn ep_picture_from_svg(svg: *const u8, len: usize) -> *mut c_char {
    #[cfg(feature = "svg")]
    {
        unsafe { art::picture_from_svg(svg, len) }
    }
    #[cfg(not(feature = "svg"))]
    {
        let _ = (svg, len);
        ptr::null_mut()
    }
}

/// Number of universes of the studio compiled into this core (Color 1.2);
/// their indices are 0..count, in the order the child is shown them. The
/// first one is the universe of a studio that was told none.
#[no_mangle]
pub extern "C" fn ep_universe_count() -> u32 {
    UNIVERSES
        .lines()
        .filter(|line| line.starts_with("U "))
        .count() as u32
}

/// Returns universe `index` as owned, NUL-terminated ASCII text, or NULL for
/// an unknown index or when memory is short:
///
/// ```text
/// U <key>
/// M <its description, JSON on one line; beyond ASCII as \uXXXX>
/// ```
///
/// then each of its pictures, described as ep_art_catalog describes one,
/// from `P <name> <width> <height>` to `X`, in the order of their names. The
/// description says the name of the universe, its colours and shapes, the
/// pieces of its decor with the picture each one shows, how they move, and
/// what a child may ask the name of; the interface reads it, the core does
/// not. Release with ep_string_free only.
#[no_mangle]
pub extern "C" fn ep_universe(index: u32) -> *mut c_char {
    universe_text(index).map_or(ptr::null_mut(), owned_text)
}

/// Number of colouring pages of this core; identifiers are 0..count.
#[no_mangle]
pub extern "C" fn ep_page_count() -> u32 {
    PAGE_PROJECTS
        .get(..4)
        .and_then(|count| count.try_into().ok())
        .map_or(0, u32::from_le_bytes)
}

/// Returns the colouring pages as owned, NUL-terminated ASCII text, or NULL
/// when memory is short. For each page, in identifier order, one line
///
/// ```text
/// T <id> <key> <regions> <details> <title>
/// ```
///
/// then its thumbnail, described as ep_art_catalog describes a picture, from
/// `P <key> <width> <height>` to `X`; the width and the height are those of
/// the sheet that the page needs. `<regions>` counts its filled elements,
/// the zones that the paint pot colours, `<details>` its other elements:
/// lines, polylines, open paths and unfilled shapes; both count elements of
/// the file, not the lines of its document. `<title>`, the rest of
/// the line, is the UTF-8 of the French title with every byte outside
/// printable ASCII, and `%`, written `%XX`. Release with ep_string_free only.
#[no_mangle]
pub extern "C" fn ep_page_catalog() -> *mut c_char {
    owned_text(PAGE_CATALOGUE)
}

/// Creates a NEW document for colouring page `page`, of the size of the
/// page, or NULL for an unknown page or when memory is short. Its layers,
/// bottom to top: identifier 1, locked, the zones of the page, every filled
/// element filled with white inside a white outline of width 0.1;
/// identifier 0, active and empty, where the child draws; identifier 2,
/// locked, the lines of the page, no fill: the outline of every element as
/// its file draws it, without the parts that a filled element drawn after
/// it hides; an outline of which something is hidden becomes the freehand
/// pieces left. Paint goes under the lines and over the zones; the paint
/// pot colours a zone through ep_set_object_style, the one change a locked
/// layer accepts. Nothing of the page is in the history: the document
/// starts with no undo step. Released with ep_document_free.
#[no_mangle]
pub extern "C" fn ep_document_from_page(page: u32) -> *mut EpDocument {
    // The project that the page's document wrote when this core was built,
    // read as any project is: its checks hold for it too.
    match page_project(page).map(load_project) {
        Some(Ok(document)) => owned_document(document),
        _ => ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests;
