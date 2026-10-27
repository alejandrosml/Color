use super::*;
use crate::test_support::*;

const PNG: &[u8] = include_bytes!("../../test-fixtures/rgba-asymmetric.png");
// Header words of a version 4 project: the sheet's colour, then a reserve.
const PAPER_WORD: usize = 48;
const RESERVED_WORD: usize = 52;

fn word(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap())
}

#[test]
fn a_new_sheet_is_white_and_plain_drawings_keep_their_format() {
    let doc = Owned::new();
    assert_eq!(doc.paper(), 0x00ff_ffff);
    assert_eq!(unsafe { ep_paper_color(ptr::null()) }, u32::MAX);
    assert_eq!(doc.dot(5.0, 6.0), 0);
    assert_eq!(doc.project()[8], 2);
    assert!(doc
        .svg()
        .contains("<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>"));
    // Asking for the colour it already has changes nothing, not even history.
    let before = doc.state();
    assert_eq!(doc.set_paper(0x00ff_ffff), 0);
    assert_eq!(doc.set_paper(0x0100_0000), INVALID);
    assert_eq!(doc.set_paper(u32::MAX), INVALID);
    assert_eq!(unsafe { ep_set_paper_color(ptr::null_mut(), 0) }, INVALID);
    assert_eq!(doc.state(), before);
    doc.assert_accounting();
}

#[test]
fn colouring_the_sheet_is_one_reversible_command_stored_by_version_four() {
    let doc = Owned::new();
    assert_eq!(doc.dot(5.0, 6.0), 0);
    let white = doc.state();
    assert_eq!(doc.set_paper(0xa8d8f0), 1);
    assert_eq!(doc.paper(), 0xa8d8f0);
    assert_eq!(doc.set_paper(0xa8d8f0), 0);
    let bytes = doc.project();
    assert_eq!(bytes[8], 4, "a coloured sheet needs version 4");
    assert_eq!(word(&bytes, PAPER_WORD), 0x01a8_d8f0);
    assert_eq!(word(&bytes, RESERVED_WORD), 0);
    let svg = doc.svg();
    assert!(svg.contains("<rect width=\"100%\" height=\"100%\" fill=\"#a8d8f0\"/>"));
    assert!(!svg.contains("#ffffff"));
    // One layer and no text: still no layer group in the image.
    assert!(!svg.contains("<g"));
    // Objects are untouched: same revision, same geometry.
    assert_eq!(unsafe { ep_object_revision(doc.0, 0) }, 1);
    let sky = doc.state();
    assert_eq!((sky.2, sky.3), (2, 0));

    let reopened = Owned::from_project(&bytes);
    assert_eq!(reopened.paper(), 0xa8d8f0);
    assert_eq!(reopened.project(), bytes);
    assert_eq!(reopened.svg(), svg);
    // A reopened sheet colour is part of the file, not of its history.
    assert_eq!(reopened.undo(), 1);
    assert_eq!(reopened.paper(), 0xa8d8f0);
    reopened.assert_accounting();

    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.paper(), 0x00ff_ffff);
    let undone = doc.state();
    assert_eq!((&undone.0, &undone.1), (&white.0, &white.1));
    assert_eq!(undone.0[8], 2, "white again: the historic format again");
    assert_eq!(doc.redo(), 1);
    assert_eq!(doc.state(), sky);
    // The immutable snapshot used by background saves carries the colour.
    assert_eq!(doc.snapshot(), (bytes, svg));
    doc.assert_accounting();
}

#[test]
fn black_is_a_colour_and_white_returns_to_the_plain_project() {
    let doc = Owned::new();
    assert_eq!(doc.set_paper(0), 1);
    assert_eq!(doc.paper(), 0);
    let bytes = doc.project();
    assert_eq!((bytes[8], word(&bytes, PAPER_WORD)), (4, 0x0100_0000));
    assert!(doc.svg().contains("fill=\"#000000\"/>"));
    assert_eq!(Owned::from_project(&bytes).paper(), 0);
    assert_eq!(doc.set_paper(0x00ff_ffff), 1);
    assert_eq!(doc.project()[8], 2);
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.paper(), 0);
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.paper(), 0x00ff_ffff);
    assert_eq!(doc.undo(), 0);
    doc.assert_accounting();
}

#[test]
fn the_sheet_colour_lies_under_layers_and_under_an_image() {
    let doc = Owned::from_png(PNG);
    assert_eq!(doc.dot(4.0, 5.0), 0);
    assert_eq!(doc.project()[8], 3);
    assert_eq!(doc.set_paper(0x123456), 1);
    let bytes = doc.project();
    assert_eq!(bytes[8], 4);
    assert_eq!(word(&bytes, PAPER_WORD), 0x0112_3456);
    // The image is stored once, after the records, exactly as it was given.
    let end = bytes.len() - 4;
    assert_eq!(&bytes[end - PNG.len()..end], PNG);
    let svg = doc.svg();
    let paper = svg.find("fill=\"#123456\"/>").unwrap();
    let image = svg.find("<image ").unwrap();
    let dot = svg.find("<circle ").unwrap();
    assert!(paper < image && image < dot);
    let reopened = Owned::from_project(&bytes);
    assert_eq!(reopened.project(), bytes);
    assert_eq!(reopened.svg(), svg);
    assert_eq!(doc.snapshot(), (bytes, svg));

    // With layers: the paper stays the first thing painted.
    let layered = Owned::new();
    assert_eq!(layered.dot(1.0, 1.0), 0);
    assert_eq!(unsafe { ep_add_layer(layered.0) }, 1);
    assert_eq!(layered.set_paper(0xeebf4e), 1);
    let svg = layered.svg();
    assert!(svg.find("fill=\"#eebf4e\"/>").unwrap() < svg.find("<g id=\"calque-1\">").unwrap());
    // Hiding every object does not hide the sheet's colour.
    assert_eq!(unsafe { ep_set_layer_visible(layered.0, 0, 0) }, 1);
    assert!(layered.svg().contains("fill=\"#eebf4e\"/>"));
    layered.assert_accounting();
}

#[test]
fn files_spell_each_sheet_colour_in_exactly_one_way() {
    let doc = Owned::new();
    assert_eq!(doc.dot(5.0, 6.0), 0);
    assert_eq!(doc.set_paper(0x336699), 1);
    let good = doc.project();
    let altered = |offset: usize, value: u32| {
        let mut bytes = good.clone();
        put_u32(&mut bytes, offset, value);
        Owned::try_from_project(&resealed(bytes)).map(|doc| doc.paper())
    };
    assert_eq!(altered(PAPER_WORD, 0x0133_6699), Ok(0x336699));
    assert_eq!(altered(PAPER_WORD, 0x0100_0000), Ok(0));
    // Zero is the white sheet; this file then merely uses version 4 early.
    assert_eq!(altered(PAPER_WORD, 0), Ok(0x00ff_ffff));
    for forged in [
        0x01ff_ffff, // white must be spelled zero
        0x0033_6699, // a colour without its marker
        0x0233_6699,
        0x8133_6699,
        u32::MAX,
    ] {
        assert_eq!(altered(PAPER_WORD, forged), Err(INVALID), "{forged:#x}");
    }
    assert_eq!(altered(RESERVED_WORD, 1), Err(INVALID));
    // Without the repaired checksum the change is caught even earlier.
    let mut torn = good.clone();
    put_u32(&mut torn, PAPER_WORD, 0x0100_0000);
    assert_eq!(Owned::try_from_project(&torn).err(), Some(INVALID));
}

#[test]
fn the_history_limit_refuses_a_new_colour_without_losing_anything() {
    let doc = Owned::new();
    for command in 0..MAX_HISTORY_STEPS {
        assert_eq!(doc.set_paper((command % 2) as u32), 1, "command {command}");
    }
    let full = doc.state();
    assert_eq!(full.2, MAX_HISTORY_STEPS);
    assert_eq!(doc.set_paper(0x123456), INVALID);
    assert_eq!(doc.state(), full);
    // Room returns as soon as a step is undone, on a new branch.
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.set_paper(0x123456), 1);
    assert_eq!(doc.paper(), 0x123456);
    assert_eq!(doc.redo(), 0);
    doc.assert_accounting();
}
