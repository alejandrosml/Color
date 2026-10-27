//! Damaged files: thousands of reproducible mutations of real projects, with
//! the final checksum repaired so that each mutant reaches the validation
//! behind it. The parser must never panic or read out of bounds, and whatever
//! it accepts must be a drawing that every other function handles: what the
//! writer makes of it is read back as the same bytes, exports work, history
//! and counters stay coherent.
//!
//! What this does and does not cover, as measured by the independent review
//! of version 0.7.0: the accepted mutants are in-place changes of a real
//! file (colours, coordinates, widths, flags, dimensions); a mutant whose
//! length changed is always stopped by the size checks, so no accepted
//! mutant has another structure than its base, and some are the base
//! itself. Files with another structure, coherent or wrong in one place,
//! are the business of reader_oracle_tests.rs, which also checks that an
//! accepted file is the drawing its bytes describe.
//!
//! The generator is a fixed xorshift sequence: a failure names its seed and
//! round, and reproduces exactly.
use super::*;
use crate::test_support::*;

macro_rules! fixture {
    ($name:literal) => {
        include_bytes!(concat!("../test-fixtures/import-project/", $name)).as_slice()
    };
}

struct Sequence(u64);

impl Sequence {
    fn next(&mut self) -> u64 {
        // xorshift64*: enough variety for mutation choices, and reproducible.
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_f491_4f6c_dd1d)
    }
    fn below(&mut self, limit: usize) -> usize {
        (self.next() % limit.max(1) as u64) as usize
    }
}

// Values that sit on the edges of the format's own limits.
const EDGES: [u32; 20] = [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    15,
    16,
    17,
    255,
    256,
    0x00ff_ffff,
    0x0100_0000,
    0x7fff_ffff,
    0x8000_0000,
    u32::MAX,
    0x7f80_0000, // +infinity as f32
    0x7fc0_0000, // NaN as f32
    0xbf80_0000, // -1.0 as f32
];

// `region` is the number of leading bytes that mutations aim at: the whole
// payload, or what precedes an embedded image. A PNG has checksums of its
// own, exercised by the background tests; aiming there would only measure
// them again and leave the records almost untouched.
fn mutate(base: &[u8], region: usize, random: &mut Sequence) -> Vec<u8> {
    let mut bytes = base.to_vec();
    for _ in 0..1 + random.below(3) {
        // Never beyond the checksum, as it is after earlier mutations.
        let payload = region.min(bytes.len() - 4);
        match random.below(8) {
            // One bit, anywhere before the checksum.
            0 => {
                let at = random.below(payload);
                bytes[at] ^= 1 << random.below(8);
            }
            // One byte.
            1 => {
                let at = random.below(payload);
                bytes[at] = random.next() as u8;
            }
            // One aligned word set to an edge value: counts, kinds, colours,
            // widths and coordinates are all words at multiples of four.
            2 | 3 => {
                let at = 12 + 4 * random.below((payload - 12) / 4);
                if at + 4 <= payload {
                    let value = EDGES[random.below(EDGES.len())];
                    put_u32(&mut bytes, at, value);
                }
            }
            // One aligned word nudged by one.
            4 => {
                let at = 12 + 4 * random.below((payload - 12) / 4);
                if at + 4 <= payload {
                    let word = u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap());
                    let nudged = if random.below(2) == 0 {
                        word.wrapping_add(1)
                    } else {
                        word.wrapping_sub(1)
                    };
                    put_u32(&mut bytes, at, nudged);
                }
            }
            // A run of bytes removed, with the declared size following or not.
            5 => {
                let at = random.below(payload);
                let length = 1 + random.below(24).min(payload - at - 1);
                bytes.drain(at..at + length);
                if random.below(2) == 0 && bytes.len() >= 16 {
                    let total = bytes.len() as u32;
                    put_u32(&mut bytes, 12, total);
                }
            }
            // A run of bytes repeated.
            6 => {
                let at = random.below(payload);
                let length = 1 + random.below(24).min(payload - at - 1);
                let copy = bytes[at..at + length].to_vec();
                bytes.splice(at..at, copy);
                if random.below(2) == 0 {
                    let total = bytes.len() as u32;
                    put_u32(&mut bytes, 12, total);
                }
            }
            // Two words exchanged.
            _ => {
                let first = 12 + 4 * random.below((payload - 12) / 4);
                let second = 12 + 4 * random.below((payload - 12) / 4);
                if first + 4 <= payload && second + 4 <= payload {
                    for offset in 0..4 {
                        bytes.swap(first + offset, second + offset);
                    }
                }
            }
        }
        if bytes.len() < PROJECT_MIN_BYTES + 16 {
            // Too short to mutate further: keep what is left as the mutant.
            break;
        }
    }
    if bytes.len() < 8 {
        return base.to_vec();
    }
    resealed(bytes)
}

// Everything the studio does with an opened drawing must work on it.
fn exercise(doc: &Owned, context: &str) {
    doc.assert_accounting();
    // A page's objects stay through every command and every undo.
    let pinned = doc.pinned();
    let bytes = doc.project();
    assert_eq!(bytes.len(), unsafe { ep_project_size(doc.0) }, "{context}");
    // What was written is read back as the very same drawing.
    let again = Owned::try_from_project(&bytes)
        .unwrap_or_else(|status| panic!("{context}: own output rejected ({status})"));
    assert_eq!(again.project(), bytes, "{context}");
    let svg = doc.svg();
    assert!(svg.ends_with("</svg>\n"), "{context}");
    assert_eq!(again.svg(), svg, "{context}");
    assert_eq!(doc.snapshot(), (bytes.clone(), svg), "{context}");

    let count = doc.count();
    for index in 0..count {
        let info = doc.info(index);
        assert!(info.point_count >= 1, "{context}");
        assert_eq!(doc.points(index).len(), info.point_count, "{context}");
        let extra = doc.extra(index);
        if extra.text_bytes != 0 {
            assert!(!doc.object_text(index).is_empty(), "{context}");
        }
    }
    // Ordinary edits, then the whole history back and forth.
    if count > 0 {
        unsafe {
            let mut delta = point(0.0, 0.0);
            if ep_constrain_object_movement(doc.0, 0, 5.0, -5.0, &mut delta) == 0 {
                let status = ep_move_object(doc.0, 0, delta.x, delta.y);
                assert!((0..=1).contains(&status), "{context}: move {status}");
            }
            let status = ep_duplicate_object(doc.0, count - 1, 0.0, 0.0);
            assert!(status == 1 || status == INVALID, "{context}: copy {status}");
        }
        let status = doc.scale(0, 0.5, doc.info(0).width);
        assert!(
            (0..=1).contains(&status) || status == INVALID,
            "{context}: {status}"
        );
    }
    assert!((0..=1).contains(&doc.set_paper(0x123456)), "{context}");
    unsafe {
        let status = ep_add_layer(doc.0);
        assert!(
            status == 1 || status == INVALID,
            "{context}: layer {status}"
        );
    }
    doc.assert_accounting();
    let edited = doc.project();
    let mut steps = 0;
    while doc.undo() == 1 {
        steps += 1;
        assert!(steps <= MAX_HISTORY_STEPS, "{context}");
    }
    assert_eq!(
        doc.count(),
        pinned,
        "{context}: undo empties the drawing, but for its locked layers"
    );
    assert_eq!(doc.pinned(), pinned, "{context}");
    doc.assert_accounting();
    while doc.redo() == 1 {}
    assert_eq!(doc.project(), edited, "{context}");
    doc.assert_accounting();
}

fn storm(name: &str, base: &[u8], seed: u64, rounds: usize) -> (usize, usize) {
    // The untouched file is a valid drawing to begin with.
    let original = Owned::from_project(base);
    let mut info = EpBackgroundInfo {
        width: 0,
        height: 0,
        byte_count: 0,
    };
    let image = match unsafe { ep_background_info(original.0, &mut info) } {
        1 => info.byte_count,
        _ => 0,
    };
    let region = base.len() - 4 - image;
    exercise(&original, name);
    let mut random = Sequence(seed);
    let mut accepted = 0;
    let mut rejected = 0;
    for round in 0..rounds {
        let mutant = mutate(base, region, &mut random);
        match Owned::try_from_project(&mutant) {
            Ok(doc) => {
                accepted += 1;
                exercise(&doc, &format!("{name}, seed {seed:#x}, round {round}"));
            }
            Err(status) => {
                assert_eq!(status, INVALID, "{name}, seed {seed:#x}, round {round}");
                rejected += 1;
            }
        }
    }
    (accepted, rejected)
}

// A drawing that uses every feature of version 4, built through the API.
fn rich_project() -> Vec<u8> {
    let doc = Owned::new();
    assert_eq!(
        doc.stroke(&[point(10.0, 20.0), point(30.5, 40.25)], 0x112233),
        0
    );
    assert_eq!(
        doc.shape(2, corners(100.0, 120.0, 220.0, 230.0), 0x445566, 4.0),
        0
    );
    assert_eq!(unsafe { ep_add_layer(doc.0) }, 1);
    assert_eq!(
        doc.text(
            corners(300.0, 300.0, 700.0, 396.0),
            0x336699,
            40.0,
            "Été\n2 < 3"
        ),
        0
    );
    assert_eq!(
        doc.stamp(corners(800.0, 500.0, 1000.0, 700.0), 8, 0x477fb2),
        0
    );
    assert_eq!(unsafe { ep_add_layer(doc.0) }, 1);
    assert_eq!(
        doc.shape(3, corners(50.0, 600.0, 250.0, 700.0), 0x778899, 5.0),
        0
    );
    assert_eq!(unsafe { ep_set_layer_visible(doc.0, 1, 0) }, 1);
    assert_eq!(doc.scale(1, 1.5, 6.0), 1);
    assert_eq!(doc.set_paper(0xa8d8f0), 1);
    doc.project()
}

#[test]
fn mutated_layered_projects_never_break_the_core() {
    let rich = rich_project();
    let mut totals = (0, 0);
    for (name, base, seed) in [
        (
            "layers-text-stamp-v4",
            fixture!("layers-text-stamp-v4.edupaint"),
            0x9e37_79b9_7f4a_7c15,
        ),
        ("rich project", rich.as_slice(), 0x0123_4567_89ab_cdef),
        (
            "text-on-image-v4",
            fixture!("text-on-image-v4.edupaint"),
            0xfeed_face_cafe_beef,
        ),
    ] {
        let (accepted, rejected) = storm(name, base, seed, 6_000);
        eprintln!("{name}: {accepted} accepted, {rejected} rejected");
        // Both outcomes must really occur, or the storm tests nothing.
        assert!(accepted > 50, "{name}: only {accepted} mutants accepted");
        assert!(rejected > 500, "{name}: only {rejected} mutants rejected");
        totals.0 += accepted;
        totals.1 += rejected;
    }
    assert_eq!(totals.0 + totals.1, 18_000);
}

// A colouring page of version 5 with everything that can be done on it:
// zones painted, strokes and a text drawn, a contour resized, a hidden layer
// shown, a layer added. Built from the independent fixture through the API.
fn rich_page_project() -> Vec<u8> {
    let doc = Owned::from_project(fixture!("locked-page-v5.edupaint"));
    unsafe {
        assert_eq!(ep_set_object_style(doc.0, 0, 0xffffff, 0.1, 1, 0xf2c14e), 1);
        assert_eq!(ep_set_object_style(doc.0, 1, 0xffffff, 0.1, 1, 0x4e9af2), 1);
        assert_eq!(ep_set_layer_visible(doc.0, 2, 1), 1);
        assert_eq!(ep_add_layer(doc.0), 1);
    }
    assert_eq!(
        doc.stroke(&[point(600.0, 600.0), point(640.5, 610.25)], 0x112233),
        0
    );
    assert_eq!(
        doc.text(corners(300.0, 600.0, 500.0, 648.0), 0x336699, 40.0, "Été"),
        0
    );
    assert_eq!(doc.scale(3, 1.25, 4.0), 1);
    let bytes = doc.project();
    assert_eq!(bytes[8], 5);
    bytes
}

#[test]
fn mutated_version_5_projects_never_break_the_core() {
    let rich = rich_page_project();
    for (name, base, seed) in [
        (
            "locked-page-v5",
            fixture!("locked-page-v5.edupaint"),
            0x2468_ace0_1357_9bdf,
        ),
        ("rich page", rich.as_slice(), 0x0f1e_2d3c_4b5a_6978),
    ] {
        let (accepted, rejected) = storm(name, base, seed, 6_000);
        eprintln!("{name}: {accepted} accepted, {rejected} rejected");
        assert!(accepted > 50, "{name}: only {accepted} mutants accepted");
        assert!(rejected > 500, "{name}: only {rejected} mutants rejected");
    }
}

#[test]
fn mutated_historic_projects_never_break_the_core() {
    for (name, base, seed) in [
        (
            "legacy-v1",
            fixture!("legacy-v1.edupaint"),
            0x1111_2222_3333_4444,
        ),
        (
            "portrait-v2",
            fixture!("portrait-v2.edupaint"),
            0x5555_6666_7777_8888,
        ),
        ("rgb-v3", fixture!("rgb-v3.edupaint"), 0x9999_aaaa_bbbb_cccc),
    ] {
        let (accepted, rejected) = storm(name, base, seed, 4_000);
        eprintln!("{name}: {accepted} accepted, {rejected} rejected");
        assert!(accepted > 20, "{name}: only {accepted} mutants accepted");
        assert!(rejected > 300, "{name}: only {rejected} mutants rejected");
    }
}

// A guard on the existence of the checksum test rather than on its strength:
// CRC-32 detects every single flipped bit by construction.
#[test]
fn a_mutant_without_its_repaired_checksum_is_always_refused() {
    for (base, seed) in [
        (rich_project(), 0x0f0f_f0f0_1234_5678),
        (rich_page_project(), 0x5555_0f0f_aaaa_f0f0),
    ] {
        let mut random = Sequence(seed);
        for round in 0..2_000 {
            let mut mutant = base.clone();
            let at = random.below(mutant.len());
            let bit = 1 << random.below(8);
            mutant[at] ^= bit;
            assert_eq!(
                Owned::try_from_project(&mutant).err(),
                Some(INVALID),
                "round {round}: bit {bit:#x} at {at}"
            );
        }
    }
}
