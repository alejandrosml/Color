//! The universes of the studio (Color 1.2): what dresses the workshop around
//! the sheet. Each one is a folder of `art/univers/`: `univers.json`, which
//! says its name, its colours, its shapes, the pieces of its decor, how they
//! move and what a child may ask the name of; and the pictures of those
//! pieces, SVG files drawn in the frame of the decor (1061 × 407 for the
//! first ones, the sheet in its middle). A universe may have no decor at
//! all — « Classique », the workshop as it always was: it then has no
//! picture, and only dresses the studio.
//!
//! Nothing of a decor goes beyond its frame (the owner, 12 November 2026):
//! only the ground reaches the edges. The interface checks every piece, at
//! its widest movement (test/universe_test.dart).
//!
//! As for the pictures of the interface, the folders are read before the
//! build, by the tests, and what they make is compiled in
//! (catalogues/univers.txt): one universe after the other,
//!
//! ```text
//! U <key>
//! M <univers.json on one line, in ASCII>
//! P <picture> <width> <height>      each picture, as art::describe writes
//! ...                               it, in the order of their names
//! X
//! ```
//!
//! The core does not read the JSON: the interface does. Here it is only
//! brought to one line of ASCII, so that the catalogue stays a text of
//! lines, like the others.
use super::*;

/// One universe: its key, its `univers.json`, its pictures by name.
pub(crate) type Universe = (
    &'static str,
    &'static str,
    &'static [(&'static str, &'static str)],
);

macro_rules! universe {
    ($key:literal, [$($picture:literal),* $(,)?]) => {
        (
            $key,
            include_str!(concat!("../art/univers/", $key, "/univers.json")),
            &[$((
                $picture,
                include_str!(concat!("../art/univers/", $key, "/", $picture, ".svg")),
            )),*],
        )
    };
}

/// The universes, in the order the child is shown them; the pictures of
/// each in the order of their names.
pub(crate) static UNIVERSES: &[Universe] = &[
    // The workshop of always: a look and no decor, so no picture.
    universe!("classique", []),
    universe!(
        "bureau",
        [
            "chat",
            "ciel-jour",
            "ciel-matin",
            "ciel-nuit",
            "ciel-soir",
            "crayons",
            "droite",
            "fenetre",
            "fond",
            "gauche",
            "milieu",
            "nuage",
            "plante",
            "rideau-droite",
            "rideau-gauche",
        ]
    ),
    universe!("papier", ["crayon", "droite", "etoile", "fond", "gauche"]),
];

/// `json` on one line of ASCII: the spaces and the ends of line between its
/// values are left out, and every character beyond ASCII is written
/// `\uXXXX` — two of them for a character beyond the first plane. None for
/// a text that is not written as JSON is: a string left open, a control
/// character inside one.
pub(crate) fn one_line(json: &str) -> Option<String> {
    let mut out = String::with_capacity(json.len());
    let mut inside = false;
    let mut escaped = false;
    for character in json.chars() {
        if inside {
            if (character as u32) < 0x20 {
                return None;
            }
            if escaped {
                escaped = false;
            } else if character == '\\' {
                escaped = true;
            } else if character == '"' {
                inside = false;
            }
        } else if character == '"' {
            inside = true;
        } else if character.is_ascii_whitespace() {
            continue;
        }
        if character.is_ascii() {
            out.push(character);
        } else {
            let mut units = [0u16; 2];
            for unit in character.encode_utf16(&mut units) {
                write!(out, "\\u{unit:04x}").ok()?;
            }
        }
    }
    (!inside && !out.is_empty()).then_some(out)
}

/// Every universe, one after the other, as `catalogues/univers.txt` holds
/// them; None if a manifest or a picture is refused, which the tests do not
/// let happen.
pub(crate) fn universe_catalogue() -> Option<String> {
    let mut out = String::new();
    for (key, manifest, pictures) in UNIVERSES {
        writeln!(out, "U {key}").ok()?;
        writeln!(out, "M {}", one_line(manifest)?).ok()?;
        for (name, svg) in pictures.iter() {
            art::describe(name, svg, &mut out).ok()?;
        }
    }
    Some(out)
}
