//! Tests of the catalogues compiled into the core: what any core serves, with
//! or without the `svg` feature, and, with it, that they are exactly what
//! the readers write from the files today.
use super::*;
use crate::test_support::Owned;
use std::ffi::CStr;

fn text(pointer: *mut c_char) -> String {
    assert!(!pointer.is_null());
    let text = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .unwrap()
        .to_owned();
    unsafe { ep_string_free(pointer) };
    text
}

#[test]
fn every_core_serves_the_pictures_and_the_pages() {
    assert_eq!(ep_art_count(), 30);
    let art = text(ep_art_catalog());
    assert_eq!(
        art.lines().filter(|line| line.starts_with("P ")).count(),
        30
    );
    assert!(art.is_ascii() && art.ends_with("X\n"));
    let count = ep_page_count();
    assert_eq!(count, 12);
    let catalogue = text(ep_page_catalog());
    let titles: Vec<&str> = catalogue
        .lines()
        .filter(|line| line.starts_with("T "))
        .collect();
    assert_eq!(titles.len(), count as usize);
    for (id, line) in titles.iter().enumerate() {
        assert!(line.starts_with(&format!("T {id} ")), "{line}");
    }
    for id in 0..count {
        let document = Owned(ep_document_from_page(id));
        assert!(!document.0.is_null(), "page {id}");
        unsafe {
            assert_eq!(ep_layer_count(document.0), 3);
            assert_eq!(ep_active_layer(document.0), 0);
            assert_eq!(ep_undo_count(document.0), 0);
            assert!(ep_stroke_count(document.0) > 0);
        }
    }
    assert!(ep_document_from_page(count).is_null());
    assert!(ep_document_from_page(u32::MAX).is_null());
}

#[test]
fn every_core_serves_the_universes() {
    let count = ep_universe_count();
    assert_eq!(count, 2);
    let mut keys = Vec::new();
    for index in 0..count {
        let universe = text(ep_universe(index));
        assert!(universe.is_ascii() && universe.ends_with("X\n"), "{index}");
        let mut lines = universe.lines();
        let key = lines.next().unwrap().strip_prefix("U ").unwrap().to_owned();
        let manifest = lines.next().unwrap().strip_prefix("M ").unwrap();
        // The description names its own key, and is one object of JSON.
        assert!(
            manifest.starts_with('{') && manifest.ends_with('}'),
            "{key}"
        );
        assert!(manifest.contains(&format!("\"key\":\"{key}\"")), "{key}");
        // One universe only: no other begins in its text.
        assert_eq!(
            universe
                .lines()
                .filter(|line| line.starts_with("U "))
                .count(),
            1
        );
        assert_eq!(
            universe
                .lines()
                .filter(|line| line.starts_with("P "))
                .count(),
            universe.lines().filter(|line| *line == "X").count(),
            "{key}"
        );
        // Every decor has a ground.
        assert!(
            universe.lines().any(|line| line.starts_with("P fond ")),
            "{key}"
        );
        keys.push(key);
    }
    // The first one is the universe of a studio that was told none.
    assert_eq!(keys, ["bureau", "papier"]);
    assert!(ep_universe(count).is_null());
    assert!(ep_universe(u32::MAX).is_null());
}

#[cfg(not(feature = "svg"))]
#[test]
fn a_core_without_svg_reads_no_svg() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8"><rect width="4" height="4"/></svg>"#;
    assert!(unsafe { ep_picture_from_svg(svg.as_ptr(), svg.len()) }.is_null());
}

/// `pages.bin` for these projects, as its format is described.
#[cfg(feature = "svg")]
fn packed(projects: &[Vec<u8>]) -> Vec<u8> {
    let mut bytes = (projects.len() as u32).to_le_bytes().to_vec();
    for project in projects {
        bytes.extend_from_slice(&(project.len() as u32).to_le_bytes());
        bytes.extend_from_slice(project);
    }
    bytes
}

#[cfg(feature = "svg")]
#[test]
fn the_catalogues_are_those_that_the_files_make() {
    let interface = art::interface_catalogue().expect("every picture reads");
    let pages = pages::page_catalogue().expect("every page reads");
    let projects = packed(&pages::page_projects().expect("every page makes its document"));
    let universes = universes::universe_catalogue().expect("every universe reads");
    if std::env::var_os("COLOR_REGENERATE_CATALOGUES").is_some() {
        std::fs::write("src/catalogues/univers.txt", &universes).unwrap();
        std::fs::write("src/catalogues/interface.txt", &interface).unwrap();
        std::fs::write("src/catalogues/pages.txt", &pages).unwrap();
        std::fs::write("src/catalogues/pages.bin", &projects).unwrap();
        return;
    }
    let again = "written again by COLOR_REGENERATE_CATALOGUES=1 cargo test catalogues";
    assert!(
        INTERFACE == interface,
        "interface.txt is not what the files make: {again}"
    );
    assert!(
        PAGE_CATALOGUE == pages,
        "pages.txt is not what the files make: {again}"
    );
    assert!(
        PAGE_PROJECTS == projects.as_slice(),
        "pages.bin is not what the files make: {again}"
    );
    assert!(
        UNIVERSES == universes,
        "univers.txt is not what the files make: {again}"
    );
}

#[cfg(feature = "svg")]
#[test]
fn a_description_is_brought_to_one_line_of_ascii() {
    let line =
        universes::one_line("{\n \"nom\": \"L\u{2019}\u{e9}t\u{e9} \\\" 1\",\n \"a\": [1, 2]\n}\n");
    assert_eq!(
        line.as_deref(),
        Some("{\"nom\":\"L\\u2019\\u00e9t\\u00e9 \\\" 1\",\"a\":[1,2]}")
    );
    // Beyond the first plane: the two halves.
    assert_eq!(
        universes::one_line("\"\u{1f3a8}\"").as_deref(),
        Some("\"\\ud83c\\udfa8\"")
    );
    assert_eq!(universes::one_line("\"open"), None);
    assert_eq!(universes::one_line("\"a\nb\""), None);
    assert_eq!(universes::one_line("  \n"), None);
    // Every universe of this core: its key is its folder, and each picture
    // that its description names is one of its files.
    for (key, manifest, pictures) in universes::UNIVERSES {
        let line = universes::one_line(manifest).expect(key);
        assert!(line.is_ascii() && !line.contains('\n'), "{key}");
        assert!(line.contains(&format!("\"key\":\"{key}\"")), "{key}");
        let mut sorted: Vec<&str> = pictures.iter().map(|(name, _)| *name).collect();
        sorted.sort_unstable();
        assert_eq!(
            sorted,
            pictures.iter().map(|(name, _)| *name).collect::<Vec<_>>(),
            "{key}: the pictures in the order of their names"
        );
        let mut rest = line.as_str();
        while let Some(at) = rest.find("\"picture\":\"") {
            rest = &rest[at + 11..];
            let name = &rest[..rest.find('"').unwrap()];
            assert!(
                pictures
                    .iter()
                    .any(|(file, _)| *file == name || file.starts_with(&format!("{name}-"))),
                "{key}: no picture {name}"
            );
        }
    }
}

/// The project that a document writes.
#[cfg(feature = "svg")]
fn written(document: *const EpDocument) -> Vec<u8> {
    let size = unsafe { ep_project_size(document) };
    let mut bytes = vec![0; size];
    assert_eq!(
        unsafe { ep_copy_project(document, bytes.as_mut_ptr(), size) },
        0
    );
    bytes
}

#[cfg(feature = "svg")]
#[test]
fn a_page_opens_as_the_document_that_its_file_makes() {
    for (id, svg) in pages::PAGES.iter().map(|(_, svg)| svg).enumerate() {
        let page = pages::read_page(svg).unwrap();
        let made = Owned(owned_document(pages::page_document(&page).unwrap()));
        let opened = Owned(ep_document_from_page(id as u32));
        assert!(!opened.0.is_null());
        assert_eq!(written(made.0), written(opened.0), "page {id}");
        unsafe {
            for document in [made.0, opened.0] {
                assert_eq!(ep_undo_count(document), 0);
                assert_eq!(ep_redo_count(document), 0);
                assert_eq!(ep_active_layer(document), 0);
            }
            assert_eq!(ep_layer_count(made.0), ep_layer_count(opened.0));
            for layer in 0..ep_layer_count(made.0) {
                let empty = EpLayerInfo {
                    id: 0,
                    visible: 0,
                    object_count: 0,
                };
                let (mut a, mut b) = (empty, empty);
                assert_eq!(ep_layer_info(made.0, layer, &mut a), 0);
                assert_eq!(ep_layer_info(opened.0, layer, &mut b), 0);
                assert_eq!(a, b, "page {id}, layer {layer}");
                assert_eq!(
                    ep_layer_locked(made.0, layer),
                    ep_layer_locked(opened.0, layer),
                    "page {id}, layer {layer}"
                );
            }
            let count = ep_stroke_count(made.0);
            assert_eq!(count, ep_stroke_count(opened.0));
            for index in 0..count {
                assert_eq!(
                    ep_object_revision(made.0, index),
                    ep_object_revision(opened.0, index),
                    "page {id}, object {index}"
                );
            }
        }
    }
}
