// SPDX-License-Identifier: MIT
//! The notices compiled into the core are those of the libraries kept in
//! vendor/, then the credits of the recorded sounds, and the C header names
//! every function the core exports. Both are read from the folder of the
//! core, which is where tests run.
use super::*;
use std::collections::BTreeSet;
use std::ffi::CStr;
use std::fs;
use std::path::Path;

fn through_c() -> String {
    let text = ep_third_party_notices();
    assert!(!text.is_null());
    let copy = unsafe { CStr::from_ptr(text) }
        .to_str()
        .expect("the notices are UTF-8")
        .to_owned();
    unsafe { crate::ep_string_free(text) };
    copy
}

/// The libraries, then the recordings, as the interface reads them.
fn notices() -> String {
    if THIRD_PARTY_NOTICES.is_empty() {
        RECORDING_NOTICES.to_owned()
    } else {
        format!("{THIRD_PARTY_NOTICES}\n{RULE}\n{RECORDING_NOTICES}")
    }
}

#[test]
fn the_c_interface_hands_the_whole_text() {
    assert_eq!(through_c(), notices());
    // Twice: each call owns its own copy.
    assert_eq!(through_c(), notices());
}

#[test]
fn the_recordings_come_last_in_the_shape_of_the_libraries() {
    assert_eq!(RULE.len(), 80);
    assert!(RULE.bytes().all(|byte| byte == b'-'));
    assert!(through_c().ends_with(RECORDING_NOTICES));
    // Each entry is « Sons enregistrés », an empty line, then a credit that
    // names the sound, the page it comes from and a licence that asks no
    // attribution; sound/tests.rs checks them against the provenance.
    let entries: Vec<&str> = RECORDING_NOTICES.split(&format!("\n{RULE}\n")).collect();
    assert!(!entries.is_empty());
    for entry in entries {
        let credit = entry
            .strip_prefix("Sons enregistrés\n\nSon « ")
            .unwrap_or_else(|| panic!("{entry}"));
        assert!(credit.contains("\nhttps://"), "{entry}");
        assert!(
            credit.contains("\nLicence : CC0 1.0 universel")
                || credit.contains("\nLicence : domaine public, par la volonté de son auteur"),
            "{entry}"
        );
        assert!(!credit.contains("\n\n"), "{entry}");
    }
    assert!(RECORDING_NOTICES.ends_with('\n') && !RECORDING_NOTICES.ends_with("\n\n"));
}

#[cfg(not(feature = "svg"))]
#[test]
fn a_core_without_libraries_names_only_its_recordings() {
    assert_eq!(THIRD_PARTY_NOTICES, "");
    assert_eq!(through_c(), RECORDING_NOTICES);
}

// A field of the [package] table of a Cargo.toml as cargo writes it.
#[cfg(feature = "svg")]
fn field(manifest: &str, name: &str) -> String {
    let package = manifest
        .split("[package]")
        .nth(1)
        .expect("a [package] table");
    let package = package.split("\n[").next().unwrap();
    let start = format!("{name} = \"");
    package
        .lines()
        .find_map(|line| line.strip_prefix(start.as_str()))
        .and_then(|rest| rest.strip_suffix('"'))
        .unwrap_or_else(|| panic!("no {name} in a vendored Cargo.toml"))
        .to_owned()
}

#[cfg(feature = "svg")]
fn squeezed(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

#[cfg(feature = "svg")]
#[test]
fn every_library_of_vendor_has_its_notice_and_no_other_has() {
    let mut entries: Vec<&str> = THIRD_PARTY_NOTICES.split(&format!("\n{RULE}\n")).collect();
    let mut named = BTreeSet::new();
    for entry in &entries {
        let name = entry.lines().next().unwrap();
        assert!(entry.starts_with(&format!("{name}\n\n{name} ")), "{name}");
        assert!(named.insert(name.to_owned()), "{name} is named twice");
    }
    let mut folders = BTreeSet::new();
    for folder in fs::read_dir("vendor").expect("vendor/ beside the tests") {
        let folder = folder.unwrap();
        if folder.file_name().to_string_lossy().starts_with('.') || !folder.path().is_dir() {
            continue;
        }
        let folder = folder.path();
        let manifest = fs::read_to_string(folder.join("Cargo.toml")).unwrap();
        let (name, version) = (field(&manifest, "name"), field(&manifest, "version"));
        let offered = field(&manifest, "license");
        let position = entries
            .iter()
            .position(|entry| entry.lines().next() == Some(name.as_str()))
            .unwrap_or_else(|| panic!("{name} has no notice: run collect-core-licences.py"));
        let entry = entries.remove(position);
        // Its version, and a licence that it offers and that goes with the
        // GPL version 2: never Apache-2.0 alone.
        let head = entry.lines().nth(2).unwrap();
        assert!(
            head.starts_with(&format!("{name} {version} — licence ")),
            "{head}"
        );
        let taken = head
            .split(" — licence ")
            .nth(1)
            .unwrap()
            .split([',', '.'])
            .next()
            .unwrap();
        assert!(
            ["MIT", "BSD-2-Clause", "BSD-3-Clause", "Zlib", "Unlicense"].contains(&taken),
            "{name}: {taken}"
        );
        assert!(
            offered.split(" OR ").any(|licence| licence == taken),
            "{name} does not offer {taken}: {offered}"
        );
        // The text is one of the licence files of the library, whole.
        let body = squeezed(entry.splitn(3, "\n\n").nth(2).unwrap());
        let found = fs::read_dir(&folder).unwrap().any(|file| {
            let file = file.unwrap().path();
            let name = file.file_name().unwrap().to_string_lossy().to_uppercase();
            (name.starts_with("LICENSE") || name.starts_with("UNLICENSE"))
                && fs::read_to_string(&file).is_ok_and(|text| squeezed(&text) == body)
        });
        assert!(
            found,
            "the notice of {name} is not one of its licence files"
        );
        folders.insert(name);
    }
    assert!(entries.is_empty(), "notices without a library in vendor/");
    assert_eq!(named, folders);
    assert!(folders.contains("usvg"));
}

// The names of the functions the sources export, and of those the header
// declares.
#[test]
fn the_c_header_declares_exactly_what_the_core_exports() {
    fn sources(folder: &Path, into: &mut BTreeSet<String>) {
        for entry in fs::read_dir(folder).unwrap() {
            let entry = entry.unwrap();
            // What a file manager leaves beside the sources (.DS_Store,
            // ._lib.rs) is not a source.
            if entry.file_name().to_string_lossy().starts_with('.') {
                continue;
            }
            let path = entry.path();
            if path.is_dir() {
                sources(&path, into);
            } else if path.extension().is_some_and(|extension| extension == "rs") {
                let text = fs::read_to_string(&path).unwrap();
                for part in text.split("extern \"C\" fn ").skip(1) {
                    let name: String = part
                        .chars()
                        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                        .collect();
                    if name.starts_with("ep_") {
                        into.insert(name);
                    }
                }
            }
        }
    }
    let mut exported = BTreeSet::new();
    sources(Path::new("src"), &mut exported);
    let header = fs::read_to_string("include/edupaint_core.h").unwrap();
    let mut declared = BTreeSet::new();
    // Outside comments, an `ep_` name followed by a parenthesis is a
    // declaration.
    let mut code = String::new();
    let mut rest = header.as_str();
    while let Some(start) = rest.find("/*") {
        code.push_str(&rest[..start]);
        rest = &rest[start..];
        let end = rest.find("*/").expect("a closed comment");
        rest = &rest[end + 2..];
    }
    code.push_str(rest);
    for (index, _) in code.match_indices("ep_") {
        let before = code[..index].chars().next_back();
        if before.is_some_and(|c| c.is_ascii_alphanumeric() || c == '_') {
            continue;
        }
        let name: String = code[index..]
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
            .collect();
        if code[index + name.len()..].starts_with('(') {
            declared.insert(name);
        }
    }
    let missing: Vec<_> = exported.difference(&declared).collect();
    let unknown: Vec<_> = declared.difference(&exported).collect();
    assert!(
        missing.is_empty(),
        "exported but not in the header: {missing:?}"
    );
    assert!(
        unknown.is_empty(),
        "in the header but not exported: {unknown:?}"
    );
    assert!(exported.len() >= 60);
}
