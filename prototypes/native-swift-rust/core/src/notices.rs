// SPDX-License-Identifier: MIT
//! The notices of what this core is built from: the libraries, with their
//! names, their versions, the licence each one is taken under and its text,
//! then the recordings some of its sounds are made of. A program that
//! carries the core carries them with it, and can show them.
//!
//! The notices of the libraries are `third-party-notices.txt`, written from
//! `vendor/` by `scripts/collect-core-licences.py` and compiled in. A core
//! built without its only dependency (no `svg` feature) has no library to
//! name. The credits of the recordings are `sons/notices.txt`, written by
//! `scripts/sons/preparer-les-sons.py` beside the sounds; every core plays
//! them, so every core names them.
use std::ffi::{c_char, CString};
use std::ptr;

/// Entries separated by a line of eighty hyphens, as in the NOTICES file of
/// Flutter: the name of the library, an empty line, then its notice.
#[cfg(feature = "svg")]
pub(crate) const THIRD_PARTY_NOTICES: &str = include_str!("../third-party-notices.txt");
#[cfg(not(feature = "svg"))]
pub(crate) const THIRD_PARTY_NOTICES: &str = "";

/// The recordings, in the same shape: « Sons enregistrés », an empty line,
/// then what the sound is, where it comes from and its licence.
pub(crate) const RECORDING_NOTICES: &str = include_str!("../sons/notices.txt");

/// The line between two entries.
pub(crate) const RULE: &str =
    "--------------------------------------------------------------------------------";

/// Returns the notices compiled into this core as owned, NUL-terminated
/// UTF-8 text, or NULL on allocation failure: those of its libraries, then
/// the credits of its recorded sounds. Entries are separated by a line of
/// eighty hyphens; each one starts with a name — of a library, or « Sons
/// enregistrés » — and an empty line. A core built without libraries names
/// only its recordings. Uses no document: any thread may call it. Release
/// with ep_string_free only.
#[no_mangle]
pub extern "C" fn ep_third_party_notices() -> *mut c_char {
    let parts: &[&str] = if THIRD_PARTY_NOTICES.is_empty() {
        &[RECORDING_NOTICES]
    } else {
        &[THIRD_PARTY_NOTICES, "\n", RULE, "\n", RECORDING_NOTICES]
    };
    let mut bytes = Vec::new();
    let length = parts.iter().map(|part| part.len()).sum::<usize>();
    if bytes.try_reserve_exact(length + 1).is_err() {
        return ptr::null_mut();
    }
    for part in parts {
        bytes.extend_from_slice(part.as_bytes());
    }
    bytes.push(0);
    // Licence texts hold no NUL; should one ever, the answer is NULL.
    CString::from_vec_with_nul(bytes).map_or(ptr::null_mut(), CString::into_raw)
}

#[cfg(test)]
mod tests;
