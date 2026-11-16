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
    assert_eq!(ep_art_count(), 43);
    let art = text(ep_art_catalog());
    assert_eq!(
        art.lines().filter(|line| line.starts_with("P ")).count(),
        43
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
    assert_eq!(count, 10);
    let mut keys = Vec::new();
    for index in 0..count {
        let universe = text(ep_universe(index));
        // It ends with its last picture, or with its description when it
        // has no decor.
        assert!(universe.is_ascii() && universe.ends_with('\n'), "{index}");
        assert!(
            universe.ends_with("X\n") || universe.lines().count() == 2,
            "{index}"
        );
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
        // Every decor has a ground; a universe without a decor has no
        // picture at all.
        assert_eq!(
            universe.lines().any(|line| line.starts_with("P fond ")),
            manifest.contains("\"decor\":"),
            "{key}"
        );
        assert_eq!(
            universe.lines().any(|line| line.starts_with("P ")),
            manifest.contains("\"decor\":"),
            "{key}"
        );
        keys.push(key);
    }
    // « Classique », without a decor, comes first; the interface takes the
    // first one with a decor for a computer that was told none.
    assert_eq!(
        keys,
        [
            "classique",
            "bureau",
            "papier",
            "mer",
            "espace",
            "foret",
            "campagne",
            "ville",
            "montagne",
            "savane"
        ]
    );
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

/// A catalogue as a core with the `deflate` feature carries it: the length
/// of `raw` as four bytes, little-endian, then `raw` in raw DEFLATE, at the
/// level that makes it smallest. The same bytes for the same text as long
/// as miniz_oxide is the same version: the one kept in vendor/.
#[cfg(feature = "deflate")]
fn packed_catalogue(raw: &[u8]) -> Vec<u8> {
    let mut bytes = (raw.len() as u32).to_le_bytes().to_vec();
    bytes.extend_from_slice(&miniz_oxide::deflate::compress_to_vec(raw, 10));
    bytes
}

/// `univers.txt`, the text that is read and reviewed, and `pages.bin`,
/// whatever this core carries.
const UNIVERSES_TEXT: &str = include_str!("univers.txt");
const PAGE_PROJECTS_FILE: &[u8] = include_bytes!("pages.bin");

#[cfg(any(feature = "svg", feature = "deflate"))]
const WRITTEN_AGAIN: &str = "written again by COLOR_REGENERATE_CATALOGUES=1 cargo test catalogues";

#[cfg(feature = "svg")]
#[test]
fn the_catalogues_are_those_that_the_files_make() {
    let interface = art::interface_catalogue().expect("every picture reads");
    let pages = pages::page_catalogue().expect("every page reads");
    let projects = packed(&pages::page_projects().expect("every page makes its document"));
    let universes = universes::universe_catalogue().expect("every universe reads");
    if std::env::var_os("COLOR_REGENERATE_CATALOGUES").is_some() {
        std::fs::write("src/catalogues/univers.txt", &universes).unwrap();
        #[cfg(feature = "deflate")]
        {
            std::fs::write(
                "src/catalogues/univers.txt.packed",
                packed_catalogue(universes.as_bytes()),
            )
            .unwrap();
            std::fs::write(
                "src/catalogues/pages.bin.packed",
                packed_catalogue(&projects),
            )
            .unwrap();
        }
        std::fs::write("src/catalogues/interface.txt", &interface).unwrap();
        std::fs::write("src/catalogues/pages.txt", &pages).unwrap();
        std::fs::write("src/catalogues/pages.bin", &projects).unwrap();
        return;
    }
    let again = WRITTEN_AGAIN;
    assert!(
        INTERFACE == interface,
        "interface.txt is not what the files make: {again}"
    );
    assert!(
        PAGE_CATALOGUE == pages,
        "pages.txt is not what the files make: {again}"
    );
    assert!(
        PAGE_PROJECTS_FILE == projects.as_slice(),
        "pages.bin is not what the files make: {again}"
    );
    assert!(
        UNIVERSES_TEXT == universes,
        "univers.txt is not what the files make: {again}"
    );
}

/// What the core hands over is `univers.txt` to the byte, whether it
/// carries the text or unpacks it: each universe is what the reader of
/// before the packing cut out of the text, and one after the other they
/// are the whole text.
#[test]
fn the_universes_are_the_text_to_the_byte() {
    let starts: Vec<usize> = UNIVERSES_TEXT
        .match_indices("U ")
        .map(|(at, _)| at)
        .filter(|&at| at == 0 || UNIVERSES_TEXT.as_bytes()[at - 1] == b'\n')
        .collect();
    assert_eq!(ep_universe_count() as usize, starts.len());
    let mut served = String::new();
    for (index, &start) in starts.iter().enumerate() {
        let end = starts
            .get(index + 1)
            .copied()
            .unwrap_or(UNIVERSES_TEXT.len());
        let universe = text(ep_universe(index as u32));
        assert!(universe == UNIVERSES_TEXT[start..end], "universe {index}");
        served.push_str(&universe);
    }
    assert!(served == UNIVERSES_TEXT);
    let read = universes().expect("the universes are read");
    assert!(read.text == UNIVERSES_TEXT);
    assert_eq!(read.starts, starts);
    // Asked again, the same universes, and the same ones: read once.
    assert!(std::ptr::eq(read, universes().unwrap()));
    // Beyond the last one, nothing, whatever the number.
    for index in [starts.len() as u32, starts.len() as u32 + 1, u32::MAX] {
        assert!(universe_text(index).is_none());
    }
}

/// `univers.txt.packed` is `univers.txt`: unpacked, the same bytes; and packing
/// the text today gives the file, so that writing the catalogues again
/// changes nothing that did not change.
#[cfg(feature = "deflate")]
#[test]
fn the_packed_universes_are_the_text() {
    let again = WRITTEN_AGAIN;
    let raw = unpacked(PACKED_UNIVERSES).expect("univers.txt.packed unpacks");
    assert!(
        raw == UNIVERSES_TEXT.as_bytes(),
        "univers.txt.packed is not univers.txt: {again}"
    );
    assert!(
        packed_catalogue(UNIVERSES_TEXT.as_bytes()) == PACKED_UNIVERSES,
        "univers.txt.packed is not univers.txt as it is packed today: {again}"
    );
    assert!(PACKED_UNIVERSES.len() * 3 < UNIVERSES_TEXT.len());
}

/// What the core hands over of the pages is `pages.bin` to the byte,
/// whether it carries the file or unpacks it: their number, and the
/// project of each one, cut out of the file as its format says.
#[test]
fn the_page_projects_are_the_file_to_the_byte() {
    let word =
        |at: usize| u32::from_le_bytes(PAGE_PROJECTS_FILE[at..at + 4].try_into().unwrap()) as usize;
    let count = word(0);
    assert_eq!(ep_page_count() as usize, count);
    let mut at = 4;
    for page in 0..count {
        let length = word(at);
        let project = &PAGE_PROJECTS_FILE[at + 4..at + 4 + length];
        assert!(page_project(page as u32) == Some(project), "page {page}");
        at += 4 + length;
    }
    assert_eq!(at, PAGE_PROJECTS_FILE.len());
    let read = page_projects().expect("the pages are read");
    assert!(read == PAGE_PROJECTS_FILE);
    // Asked again, the same bytes, and the same ones: read once.
    assert!(std::ptr::eq(read, page_projects().unwrap()));
    for page in [count as u32, count as u32 + 1, u32::MAX] {
        assert!(page_project(page).is_none());
    }
}

/// `pages.bin.packed` is `pages.bin`, as `univers.txt.packed` is
/// `univers.txt`.
#[cfg(feature = "deflate")]
#[test]
fn the_packed_page_projects_are_the_file() {
    let again = WRITTEN_AGAIN;
    let raw = unpacked(PACKED_PAGE_PROJECTS).expect("pages.bin.packed unpacks");
    assert!(
        raw == PAGE_PROJECTS_FILE,
        "pages.bin.packed is not pages.bin: {again}"
    );
    assert!(
        packed_catalogue(PAGE_PROJECTS_FILE) == PACKED_PAGE_PROJECTS,
        "pages.bin.packed is not pages.bin as it is packed today: {again}"
    );
    assert!(PACKED_PAGE_PROJECTS.len() * 2 < PAGE_PROJECTS_FILE.len());
}

/// Threads that ask at the same moment — the first demand of all when this
/// test is run alone (`cargo test asked_at_the_same_moment`), where each of
/// them finds nothing kept and unpacks — are all given the same universes
/// and the same pages, whole: what one of them read is kept, the others'
/// released.
#[test]
fn the_catalogues_asked_at_the_same_moment_are_the_same_for_all() {
    use std::sync::{Arc, Barrier};
    const THREADS: usize = 16;
    let barrier = Arc::new(Barrier::new(THREADS));
    let asked: Vec<_> = (0..THREADS)
        .map(|thread| {
            let barrier = Arc::clone(&barrier);
            std::thread::spawn(move || {
                barrier.wait();
                // Half of them begin by a universe, the others by the count
                // or by a page: every way in.
                let mut universes = Vec::new();
                let first = (thread % 4 == 1).then(|| text(ep_universe(3)));
                let pages = if thread % 4 == 2 {
                    let document = ep_document_from_page(0);
                    assert!(!document.is_null());
                    unsafe { ep_document_free(document) };
                    ep_page_count()
                } else {
                    ep_page_count()
                };
                let count = ep_universe_count();
                for index in 0..count {
                    universes.push(text(ep_universe(index)));
                }
                if let Some(first) = first {
                    assert_eq!(first, universes[3]);
                }
                assert!(ep_universe(count).is_null());
                assert!(ep_document_from_page(pages).is_null());
                (universes, pages)
            })
        })
        .collect();
    let answers: Vec<_> = asked
        .into_iter()
        .map(|thread| thread.join().expect("no thread fails"))
        .collect();
    let (universes, pages) = &answers[0];
    assert_eq!(universes.concat(), UNIVERSES_TEXT);
    assert_eq!(
        pages.to_le_bytes(),
        *PAGE_PROJECTS_FILE.first_chunk::<4>().unwrap()
    );
    for answer in &answers {
        assert!(answer == &answers[0]);
    }
}

/// Bytes that look like a text with repetitions, different for each seed.
#[cfg(feature = "deflate")]
fn some_catalogue(seed: u32, length: usize) -> Vec<u8> {
    let mut state = seed.wrapping_mul(2_654_435_761).wrapping_add(1);
    let mut next = || {
        state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        state >> 16
    };
    let mut bytes = Vec::with_capacity(length);
    while bytes.len() < length {
        if bytes.len() > 16 && next() % 3 == 0 {
            // A piece said before, as a catalogue repeats its words.
            let from = next() as usize % (bytes.len() - 8);
            let count = 3 + next() as usize % 40;
            for at in from..(from + count).min(bytes.len()) {
                bytes.push(bytes[at]);
            }
        } else {
            bytes.push(b' ' + (next() % 95) as u8);
        }
    }
    bytes.truncate(length);
    bytes
}

/// Any catalogue comes back from its packing; and bytes that are not a
/// packed catalogue — cut short, longer, of another length than they say,
/// damaged — are refused or read as other bytes of the length they say,
/// without a panic and without borrowing more than that length.
#[cfg(feature = "deflate")]
#[test]
fn a_packed_catalogue_is_read_whole_or_refused() {
    for (seed, length) in [0usize, 1, 2, 63, 64, 65, 1000, 4096, 70_000]
        .into_iter()
        .enumerate()
    {
        let raw = some_catalogue(seed as u32, length);
        let whole = packed_catalogue(&raw);
        assert_eq!(
            unpacked(&whole).as_deref(),
            Some(raw.as_slice()),
            "{length}"
        );
        // Cut anywhere: refused.
        let step = (whole.len() / 300).max(1);
        for cut in (0..whole.len())
            .step_by(step)
            .chain(whole.len() - 4..whole.len())
        {
            assert!(unpacked(&whole[..cut]).is_none(), "{length} cut at {cut}");
        }
        // Anything after its end: refused.
        for more in [&[0u8][..], &[0xff], &[0, 0, 0, 0], &whole] {
            let longer = [&whole[..], more].concat();
            assert!(unpacked(&longer).is_none(), "{length}");
        }
        // Another length than the one it holds: refused, also the largest
        // lengths, for which nothing is borrowed.
        for said in [
            length.wrapping_sub(1) as u32,
            length as u32 + 1,
            MAX_PACKED_CATALOGUE_BYTES as u32,
            MAX_PACKED_CATALOGUE_BYTES as u32 + 1,
            u32::MAX,
        ] {
            let mut other = whole.clone();
            other[..4].copy_from_slice(&said.to_le_bytes());
            assert!(unpacked(&other).is_none(), "{length} said {said}");
        }
        // One bit turned, anywhere in the stream: never a panic, and never
        // more or fewer bytes than the length says.
        let step = ((whole.len() - 4) * 8 / 400).max(1);
        for bit in (0..(whole.len() - 4) * 8).step_by(step) {
            let mut damaged = whole.clone();
            damaged[4 + bit / 8] ^= 1 << (bit % 8);
            if let Some(read) = unpacked(&damaged) {
                assert_eq!(read.len(), length, "{length} bit {bit}");
            }
        }
    }
    assert!(unpacked(&[]).is_none());
    assert!(unpacked(&[0, 0, 0]).is_none());
}

#[cfg(feature = "deflate")]
#[test]
#[ignore = "a measure: cargo test --release unpacked_in_good_time -- --ignored --nocapture"]
fn the_catalogues_are_unpacked_in_good_time() {
    use std::time::Instant;
    // Through the functions of the core, as the interface asks: the count,
    // then every universe. The first round unpacks when this test runs
    // alone, as the measure asks.
    for round in 0..3 {
        let start = Instant::now();
        let count = ep_universe_count();
        let counted = start.elapsed();
        let mut bytes = 0;
        for index in 0..count {
            bytes += text(ep_universe(index)).len();
        }
        println!(
            "round {round}: count {counted:?}, count and {count} universes ({bytes} bytes) {:?}",
            start.elapsed()
        );
    }
    // The unpacking alone, with the check that it is text.
    let mut times: Vec<_> = (0..31)
        .map(|_| {
            let start = Instant::now();
            let text = String::from_utf8(unpacked(PACKED_UNIVERSES).unwrap()).unwrap();
            let time = start.elapsed();
            assert_eq!(text.len(), UNIVERSES_TEXT.len());
            time
        })
        .collect();
    times.sort();
    println!(
        "unpacking {} bytes into {}: fastest {:?}, median {:?}, slowest {:?} of {}",
        PACKED_UNIVERSES.len(),
        UNIVERSES_TEXT.len(),
        times[0],
        times[times.len() / 2],
        times[times.len() - 1],
        times.len()
    );
    assert!(times[times.len() / 2].as_millis() < 100);
    // The pages: their number, which unpacks when this test runs alone,
    // then the unpacking alone.
    for round in 0..2 {
        let start = Instant::now();
        let count = ep_page_count();
        println!(
            "round {round}: {count} pages counted in {:?}",
            start.elapsed()
        );
    }
    let mut times: Vec<_> = (0..31)
        .map(|_| {
            let start = Instant::now();
            let projects = unpacked(PACKED_PAGE_PROJECTS).unwrap();
            let time = start.elapsed();
            assert_eq!(projects.len(), PAGE_PROJECTS_FILE.len());
            time
        })
        .collect();
    times.sort();
    println!(
        "unpacking {} bytes into {}: fastest {:?}, median {:?}, slowest {:?} of {}",
        PACKED_PAGE_PROJECTS.len(),
        PAGE_PROJECTS_FILE.len(),
        times[0],
        times[times.len() / 2],
        times[times.len() - 1],
        times.len()
    );
    assert!(times[times.len() / 2].as_millis() < 100);
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
