// SPDX-License-Identifier: MIT
//! Version 6 of the project: what it keeps, what it refuses, what it saves
//! of a damaged file, and that writing what was read gives the same bytes.

use super::*;
use crate::test_support::*;

const RGB_PNG: &[u8] = include_bytes!("../../test-fixtures/rgb-asymmetric.png");

fn zigzag_line(count: usize, step: f32) -> Vec<EpPoint> {
    (0..count)
        .map(|i| {
            let x = 20.0 + (i as f32 * step) % 1100.0;
            let y = 100.0 + ((i * 7) % 31) as f32 + (i / 1000) as f32;
            point(x, y.min(790.0))
        })
        .collect()
}

/// A drawing that uses everything version 6 adds, on three layers, one of
/// them hidden, with a coloured sheet.
fn rich() -> Owned {
    let doc = Owned::new();
    // Fewer points under Miri, which runs every mark of the chalk slowly.
    let free = zigzag_line(if cfg!(miri) { 40 } else { 400 }, 2.75);
    let pressures: Vec<u8> = (0..free.len()).map(|i| (i % 255 + 1) as u8).collect();
    assert_eq!(
        doc.add(&Spec {
            points: &free,
            look: EpObjectLook {
                tool: TOOL_CHALK,
                seed: 0xdead_beef,
                ..PLAIN_LOOK
            },
            pressures: &pressures,
            ..Spec::default()
        }),
        0
    );
    let box_points = corners(100.0, 100.0, 300.25, 260.5);
    assert_eq!(
        doc.add(&Spec {
            points: &box_points,
            kind: 2,
            fill: Some(0x00ff_8800),
            look: EpObjectLook {
                gradient: 1,
                gradient_rgb: 0x0000_88ff,
                gradient_points: [0.0, 0.0, 1.0, 0.5],
                rotation: 0.5,
                ..PLAIN_LOOK
            },
            ..Spec::default()
        }),
        0
    );
    assert_eq!(
        doc.add(&Spec {
            points: &corners(400.0, 300.0, 520.0, 380.0),
            kind: 3,
            look: EpObjectLook {
                mirror: 3,
                rotation: -1.25,
                ..PLAIN_LOOK
            },
            ..Spec::default()
        }),
        0
    );
    assert_eq!(
        doc.add(&Spec {
            points: &corners(600.0, 100.0, 760.0, 160.0),
            kind: KIND_TEXT,
            width: 40.0,
            param: 4,
            text: "Mon jardin\nété",
            quant: 10,
            ..Spec::default()
        }),
        0
    );
    assert_eq!(
        doc.add(&Spec {
            points: &corners(800.0, 500.0, 900.0, 600.0),
            kind: KIND_STAMP,
            width: 1.0,
            param: 7,
            look: EpObjectLook {
                rotation: std::f32::consts::PI,
                mirror: 1,
                ..PLAIN_LOOK
            },
            quant: EXACT_QUANT as u32,
            ..Spec::default()
        }),
        0
    );
    // A contour with a hole: a square ring and a smaller one inside it.
    let rings = [
        point(50.0, 500.0),
        point(250.0, 500.0),
        point(250.0, 700.0),
        point(50.0, 700.0),
        point(100.0, 550.0),
        point(200.0, 550.0),
        point(150.0, 650.0),
    ];
    assert_eq!(
        doc.add(&Spec {
            points: &rings,
            kind: KIND_CONTOUR,
            fill: Some(0x0011_aa22),
            rings: &[4, 3],
            ..Spec::default()
        }),
        0
    );
    unsafe {
        assert_eq!(ep_add_layer(doc.0), 1);
        assert_eq!(ep_add_layer(doc.0), 1);
    }
    let rainbow = zigzag_line(if cfg!(miri) { 12 } else { 50 }, 9.5);
    assert_eq!(
        doc.add(&Spec {
            points: &rainbow,
            look: EpObjectLook {
                tool: TOOL_RAINBOW,
                ..PLAIN_LOOK
            },
            width: 12.0,
            ..Spec::default()
        }),
        0
    );
    assert_eq!(
        doc.add(&Spec {
            points: &rainbow[..10],
            look: EpObjectLook {
                tool: TOOL_GRASS,
                seed: 7,
                ..PLAIN_LOOK
            },
            bottom: true,
            ..Spec::default()
        }),
        0
    );
    unsafe {
        let layer = ep_active_layer(doc.0);
        assert_eq!(ep_set_layer_visible(doc.0, 1, 0), 1, "{layer}");
    }
    assert_eq!(doc.set_paper(0x00ff_eecc), 1);
    doc.assert_accounting();
    doc
}

#[test]
fn a_drawing_comes_back_whole_and_written_again_gives_the_same_bytes() {
    let doc = rich();
    for compress in [false, true] {
        let bytes = doc.v6(compress);
        assert_eq!(&bytes[..8], b"EDUPAINT");
        assert_eq!(u16::from_le_bytes([bytes[8], bytes[9]]), VERSION);
        let read = Owned::from_project(&bytes);
        read.assert_accounting();
        assert_eq!(read.count(), doc.count());
        assert_eq!(read.svg(), doc.svg());
        assert_eq!(read.layers(), doc.layers());
        assert_eq!(read.active(), doc.active());
        assert_eq!(read.paper(), doc.paper());
        for index in 0..doc.count() {
            assert_eq!(read.points(index), doc.points(index), "object {index}");
            assert_eq!(read.look(index), doc.look(index), "object {index}");
            assert_eq!(read.info(index), doc.info(index));
            assert_eq!(read.kind(index), doc.kind(index));
            assert_eq!(read.extra(index), doc.extra(index));
        }
        assert_eq!(read.v6(compress), bytes);
        assert_eq!(read.v6(!compress), doc.v6(!compress));
        // Every loaded object is undone, from the last, as for version 5.
        assert_eq!(unsafe { ep_undo_count(read.0) }, doc.count());
    }
    if cfg!(feature = "deflate") {
        assert!(doc.v6(true).len() < doc.v6(false).len());
    } else {
        assert_eq!(doc.v6(true), doc.v6(false));
    }
}

#[test]
fn the_older_writer_refuses_what_only_version_6_keeps_and_keeps_the_rest_as_before() {
    let doc = rich();
    assert_eq!(unsafe { ep_project_size(doc.0) }, 0);
    let mut bytes = vec![0; 1 << 16];
    assert_eq!(
        unsafe { ep_copy_project(doc.0, bytes.as_mut_ptr(), bytes.len()) },
        INVALID
    );
    // A drawing of before 1.1 is written by the older writer, byte for byte.
    let plain = Owned::new();
    assert_eq!(
        plain.stroke(&[point(1.5, 2.25), point(30.0, 40.0)], 0x123456),
        0
    );
    assert_eq!(
        plain.shape(2, corners(10.0, 10.0, 20.0, 30.0), 0xff, 2.0),
        0
    );
    let old = plain.project();
    assert_eq!(u16::from_le_bytes([old[8], old[9]]), 2);
    let reread = Owned::from_project(&plain.v6(true));
    assert_eq!(reread.project(), old);
}

#[test]
fn points_are_rounded_on_arrival_to_their_fineness() {
    let doc = Owned::new();
    let given = [
        point(10.03, 20.97),
        point(11.51, 21.49),
        point(1199.99, 799.99),
    ];
    assert_eq!(
        doc.add(&Spec {
            points: &given,
            ..Spec::default()
        }),
        0
    );
    let rounded = doc.points(0);
    assert_eq!(
        rounded,
        vec![point(10.0, 21.0), point(11.5, 21.5), point(1200.0, 800.0)]
    );
    assert_eq!(
        doc.add(&Spec {
            points: &given,
            quant: u32::from(EXACT_QUANT),
            ..Spec::default()
        }),
        0
    );
    assert_eq!(doc.points(1), given.to_vec());
    let read = Owned::from_project(&doc.v6(true));
    assert_eq!(read.points(0), rounded);
    assert_eq!(read.points(1), given.to_vec());
    // A box that rounding flattens is refused, not stored flat.
    assert_eq!(
        doc.add(&Spec {
            points: &corners(5.0, 5.0, 5.01, 9.0),
            kind: 2,
            ..Spec::default()
        }),
        INVALID
    );
    for quant in [11, 254, 256] {
        assert_eq!(
            doc.add(&Spec {
                points: &given,
                quant,
                ..Spec::default()
            }),
            INVALID,
            "{quant}"
        );
    }
}

#[test]
fn a_moved_or_resized_object_is_written_by_its_visible_points_and_reads_back_stable() {
    let doc = Owned::new();
    assert_eq!(
        doc.add(&Spec {
            points: &corners(100.0, 100.0, 100.0625, 100.0625),
            kind: 1,
            ..Spec::default()
        }),
        0
    );
    assert_eq!(
        doc.add(&Spec {
            points: &zigzag_line(30, 3.0),
            ..Spec::default()
        }),
        0
    );
    unsafe {
        assert_eq!(ep_move_object(doc.0, 1, 0.3, 0.7), 1);
        // A tiny line made smaller still: rounded to its own fineness it would
        // be a point; the file gives it a finer one instead.
        assert_eq!(ep_scale_object(doc.0, 0, 0.25, 1.0), 1);
    }
    let first = doc.v6(true);
    let read = Owned::from_project(&first);
    assert_eq!(read.v6(true), first);
    let again = Owned::from_project(&read.v6(true));
    assert_eq!(again.v6(true), first);
    for index in 0..2 {
        for (a, b) in doc.points(index).iter().zip(read.points(index)) {
            assert!((a.x - b.x).abs() <= 1.0 / 32.0 && (a.y - b.y).abs() <= 1.0 / 32.0);
        }
    }
}

#[test]
#[cfg_attr(
    miri,
    ignore = "thousands of points through DEFLATE: too long under Miri"
)]
fn compression_makes_a_large_drawing_several_times_smaller() {
    let doc = Owned::new();
    for row in 0..20 {
        let points: Vec<EpPoint> = (0..5000)
            .map(|i| {
                let t = i as f32 / 5000.0;
                point(
                    50.0 + 1100.0 * t,
                    30.0 + row as f32 * 38.0 + 10.0 * (t * 60.0).sin(),
                )
            })
            .collect();
        assert_eq!(
            doc.add(&Spec {
                points: &points,
                ..Spec::default()
            }),
            0
        );
    }
    let older = doc.project().len();
    let raw = doc.v6(false).len();
    let compressed = doc.v6(true).len();
    assert!(raw * 3 < older, "{older} -> {raw}");
    if cfg!(feature = "deflate") {
        assert!(compressed * 5 < older, "{older} -> {compressed}");
    }
}

#[test]
fn a_background_is_kept_whole_beside_the_blocks() {
    let doc = Owned::from_png(RGB_PNG);
    let info = doc.doc().background.as_ref().unwrap().info();
    assert_eq!(
        doc.add(&Spec {
            points: &[point(1.0, 1.0), point(2.0, 3.0)],
            look: EpObjectLook {
                tool: TOOL_FELT,
                ..PLAIN_LOOK
            },
            ..Spec::default()
        }),
        0
    );
    let bytes = doc.v6(true);
    assert_eq!(
        &bytes[bytes.len() - 4 - RGB_PNG.len()..bytes.len() - 4],
        RGB_PNG
    );
    let read = Owned::from_project(&bytes);
    assert_eq!(read.doc().background.as_ref().unwrap().info(), info);
    assert_eq!(read.v6(true), bytes);
}

/// Recomputes the CRCs of a file changed on purpose: of every block, of the
/// header, of the whole file. Blocks are walked by their stored lengths.
fn resealed_v6(mut bytes: Vec<u8>) -> Vec<u8> {
    let end = bytes.len() - 4;
    let mut cursor = HEADER_BYTES;
    while cursor + BLOCK_HEADER_BYTES <= end {
        let stored = u32::from_le_bytes(bytes[cursor + 4..cursor + 8].try_into().unwrap()) as usize;
        let payload = cursor + BLOCK_HEADER_BYTES;
        if payload + stored > end {
            break;
        }
        let crc = crc32(&bytes[payload..payload + stored]);
        bytes[cursor + 16..cursor + 20].copy_from_slice(&crc.to_le_bytes());
        cursor = payload + stored;
    }
    let length = bytes.len() as u32;
    bytes[12..16].copy_from_slice(&length.to_le_bytes());
    let header = crc32(&bytes[..28]);
    bytes[28..32].copy_from_slice(&header.to_le_bytes());
    resealed(bytes)
}

fn small() -> Owned {
    let doc = Owned::new();
    assert_eq!(
        doc.add(&Spec {
            points: &[point(10.0, 10.0), point(20.0, 15.0), point(30.0, 12.5)],
            look: EpObjectLook {
                tool: TOOL_AIRBRUSH,
                seed: 3,
                ..PLAIN_LOOK
            },
            pressures: &[10, 200, 255],
            ..Spec::default()
        }),
        0
    );
    assert_eq!(
        doc.add(&Spec {
            points: &corners(40.0, 40.0, 80.0, 90.0),
            kind: 3,
            fill: Some(0x00ab_cdef),
            look: EpObjectLook {
                gradient: 2,
                gradient_rgb: 0x0010_2030,
                gradient_points: [0.5, 0.5, 1.0, 0.5],
                ..PLAIN_LOOK
            },
            ..Spec::default()
        }),
        0
    );
    doc
}

#[test]
fn every_truncation_and_every_changed_byte_is_refused() {
    let bytes = small().v6(false);
    for length in 0..bytes.len() {
        assert!(
            Owned::try_from_project(&bytes[..length]).is_err(),
            "{length}"
        );
    }
    let mut longer = bytes.clone();
    longer.push(0);
    assert!(Owned::try_from_project(&longer).is_err());
    for index in 0..bytes.len() {
        for flip in [0x01, 0x80] {
            let mut changed = bytes.clone();
            changed[index] ^= flip;
            assert!(Owned::try_from_project(&changed).is_err(), "byte {index}");
        }
    }
}

// Byte offsets inside the uncompressed file of `small`.
fn first_object_offset(bytes: &[u8]) -> usize {
    // Header, DOC6, LAYS (one layer), then the OBJS header, layer id, count.
    let layers = HEADER_BYTES + BLOCK_HEADER_BYTES + DOC_BYTES;
    let stored = u32::from_le_bytes(bytes[layers + 4..layers + 8].try_into().unwrap()) as usize;
    layers + BLOCK_HEADER_BYTES + stored + BLOCK_HEADER_BYTES + 2
}

#[test]
fn a_file_with_its_crcs_repaired_is_still_checked_field_by_field() {
    let bytes = small().v6(false);
    let object = first_object_offset(&bytes);
    // Place 0, type 0, flags (tool, seed, pressures = 0x70), colour, width…
    assert_eq!(&bytes[object..object + 3], &[0, 0, 0x70]);
    let refused = |change: &dyn Fn(&mut Vec<u8>)| {
        let mut changed = bytes.clone();
        change(&mut changed);
        let changed = resealed_v6(changed);
        assert!(Owned::try_from_project(&changed).is_err());
    };
    // An unknown flag; the seed without its tool; a type beyond 6.
    refused(&|b| b[object + 2] |= 0x80);
    refused(&|b| b[object + 2] = 0x60);
    refused(&|b| b[object + 1] = 7);
    // A place that is not the first: the places no longer run 0, 1.
    refused(&|b| b[object] = 1);
    // A longer spelling of the same varint (0 written on two bytes).
    refused(&|b| {
        b[object] = 0x80;
        b.insert(object + 1, 0x00);
        let at = HEADER_BYTES + BLOCK_HEADER_BYTES + DOC_BYTES;
        let layers = u32::from_le_bytes(b[at + 4..at + 8].try_into().unwrap()) as usize;
        let objects = at + BLOCK_HEADER_BYTES + layers;
        for field in [objects + 4, objects + 8] {
            let value = u32::from_le_bytes(b[field..field + 4].try_into().unwrap()) + 1;
            b[field..field + 4].copy_from_slice(&value.to_le_bytes());
        }
    });
    // A fineness beyond 10 that is not 255.
    refused(&|b| b[object + 3 + 3 + 4 + 1] = 11);
    // A pressure of zero (the last byte before the second object's place).
    refused(&|b| {
        let second = b
            .windows(2)
            .rposition(|w| w == [0, 3])
            .expect("the ellipse record");
        b[second - 1] = 0;
    });
    // The document's counts no longer match the objects.
    refused(&|b| b[HEADER_BYTES + BLOCK_HEADER_BYTES] = 3);
    // A layer table that names an active layer it does not hold.
    refused(&|b| b[HEADER_BYTES + BLOCK_HEADER_BYTES + 16] = 5);
    // A compressed block that is not smaller, or flagged without being so.
    refused(&|b| b[HEADER_BYTES + 12] = DEFLATED);
    // The block count, the tag, the reserved bytes.
    refused(&|b| b[24] = 9);
    refused(&|b| b[HEADER_BYTES] = b'X');
    refused(&|b| b[HEADER_BYTES + 13] = 1);
    // The resealing itself keeps a sound file sound.
    assert!(Owned::try_from_project(&resealed_v6(bytes.clone())).is_ok());
}

#[test]
#[cfg(feature = "deflate")]
fn a_compressed_block_must_end_exactly_where_its_stream_ends() {
    let doc = Owned::new();
    assert_eq!(
        doc.add(&Spec {
            points: &zigzag_line(3000, 0.4),
            ..Spec::default()
        }),
        0
    );
    let bytes = doc.v6(true);
    let at = HEADER_BYTES + BLOCK_HEADER_BYTES + DOC_BYTES;
    let layers = u32::from_le_bytes(bytes[at + 4..at + 8].try_into().unwrap()) as usize;
    let objects = at + BLOCK_HEADER_BYTES + layers;
    assert_eq!(bytes[objects + 12], DEFLATED);
    let stored = u32::from_le_bytes(bytes[objects + 4..objects + 8].try_into().unwrap());
    // One byte more after the stream, counted in the stored length.
    let mut longer = bytes.clone();
    longer.insert(objects + BLOCK_HEADER_BYTES + stored as usize, 0);
    longer[objects + 4..objects + 8].copy_from_slice(&(stored + 1).to_le_bytes());
    assert!(Owned::try_from_project(&resealed_v6(longer)).is_err());
    // A raw length that the stream does not give.
    let mut wrong = bytes.clone();
    let raw = u32::from_le_bytes(wrong[objects + 8..objects + 12].try_into().unwrap());
    wrong[objects + 8..objects + 12].copy_from_slice(&(raw + 1).to_le_bytes());
    assert!(Owned::try_from_project(&resealed_v6(wrong)).is_err());
    assert!(Owned::try_from_project(&resealed_v6(bytes)).is_ok());
}

fn damaged(bytes: &[u8]) -> Result<(Owned, u32), i32> {
    let mut lost = 99;
    let mut status = 99;
    let pointer = unsafe {
        ep_document_from_damaged_project(bytes.as_ptr(), bytes.len(), &mut lost, &mut status)
    };
    if pointer.is_null() {
        Err(status)
    } else {
        assert_eq!(status, 0);
        Ok((Owned(pointer), lost))
    }
}

#[test]
fn a_damaged_file_gives_back_its_intact_layers() {
    let doc = rich();
    let bytes = doc.v6(true);
    assert_eq!(
        damaged(&bytes).err(),
        Some(INVALID),
        "a sound file is not damaged"
    );
    // Walk the blocks; damage the objects of the second layer.
    let mut cursor = HEADER_BYTES;
    let mut blocks = Vec::new();
    while cursor + 4 < bytes.len() {
        let stored = u32::from_le_bytes(bytes[cursor + 4..cursor + 8].try_into().unwrap()) as usize;
        blocks.push((cursor, stored));
        cursor += BLOCK_HEADER_BYTES + stored;
    }
    assert_eq!(blocks.len(), 2 + 3);
    let (second_layer, stored) = blocks[3];
    let mut broken = bytes.clone();
    broken[second_layer + BLOCK_HEADER_BYTES + stored / 2] ^= 0x55;
    assert!(Owned::try_from_project(&broken).is_err());
    let (saved, lost) = damaged(&broken).expect("the other layers are intact");
    assert_eq!(lost, 1 << 1);
    saved.assert_accounting();
    let lost_layer = doc.layers()[1].0;
    let kept: Vec<usize> = (0..doc.count())
        .filter(|&index| doc.extra(index).layer != lost_layer)
        .collect();
    assert_eq!(saved.count(), kept.len());
    for (to, &from) in kept.iter().enumerate() {
        assert_eq!(saved.points(to), doc.points(from));
        assert_eq!(saved.look(to), doc.look(from));
    }
    assert_eq!(saved.layers().len(), 3);
    // A damaged document block leaves nothing to stand on.
    let mut header_broken = bytes.clone();
    header_broken[HEADER_BYTES + BLOCK_HEADER_BYTES + 1] ^= 1;
    assert!(damaged(&header_broken).is_err());
    let mut first_broken = bytes;
    first_broken[3] ^= 1;
    assert!(damaged(&first_broken).is_err());
}

#[test]
fn a_damaged_image_is_left_out_and_said() {
    let doc = Owned::from_png(RGB_PNG);
    assert_eq!(
        doc.add(&Spec {
            points: &[point(1.0, 1.0)],
            ..Spec::default()
        }),
        0
    );
    let mut bytes = doc.v6(true);
    let image = bytes.len() - 4 - RGB_PNG.len();
    bytes[image + 20] ^= 0x10;
    let (saved, lost) = damaged(&bytes).expect("the drawing is intact");
    assert_eq!(lost, LOST_BACKGROUND);
    assert!(saved.doc().background.is_none());
    assert_eq!(saved.count(), 1);
}

#[test]
fn a_file_damaged_only_in_its_last_crc_is_given_back_whole() {
    let doc = rich();
    let bytes = doc.v6(true);
    let mut broken = bytes.clone();
    let last = broken.len() - 1;
    broken[last] ^= 0x20;
    assert!(Owned::try_from_project(&broken).is_err());
    let (saved, lost) = damaged(&broken).expect("every block is intact");
    assert_eq!(lost, 0, "nothing is lost");
    saved.assert_accounting();
    assert_eq!(saved.v6(true), bytes, "the same drawing");
    // Intact blocks that contradict the document block are not a drawing
    // that Color wrote, damaged or not.
    let mut counted = bytes;
    counted[HEADER_BYTES + BLOCK_HEADER_BYTES] ^= 1;
    let mut counted = resealed_v6(counted);
    assert!(Owned::try_from_project(&counted).is_err());
    let last = counted.len() - 1;
    counted[last] ^= 0x20;
    assert_eq!(damaged(&counted).err(), Some(INVALID));
}

#[test]
fn a_snapshot_writes_what_its_document_writes() {
    let doc = rich();
    unsafe {
        let mut status = 99;
        let snapshot = ep_export_snapshot_new(doc.0, &mut status);
        assert_eq!(status, 0);
        let mut bytes = vec![0; ep_export_snapshot_project_bound(snapshot)];
        let mut length = 0;
        assert_eq!(
            ep_export_snapshot_write_project(
                snapshot,
                bytes.as_mut_ptr(),
                bytes.len(),
                1,
                &mut length
            ),
            0
        );
        bytes.truncate(length);
        assert_eq!(bytes, doc.v6(true));
        let mut short = vec![0; ep_export_snapshot_project_bound(snapshot) - 1];
        assert_eq!(
            ep_export_snapshot_write_project(
                snapshot,
                short.as_mut_ptr(),
                short.len(),
                1,
                &mut length
            ),
            INVALID
        );
        ep_export_snapshot_free(snapshot);
    }
}

#[test]
fn the_bound_is_never_too_small_and_never_far() {
    for doc in [Owned::new(), small(), rich()] {
        let bound = unsafe { ep_project_bound(doc.0) };
        let written = doc.v6(false).len();
        assert!(written <= bound);
        assert!(bound <= written + 200 * doc.count().max(1) + 11 * doc.doc().active_points + 400);
    }
    assert_eq!(unsafe { ep_project_bound(ptr::null()) }, 0);
}

#[test]
fn texts_of_the_other_fonts_need_version_6_and_versions_4_and_5_refuse_them() {
    let doc = Owned::new();
    assert_eq!(
        doc.text(corners(10.0, 10.0, 200.0, 60.0), 0x112233, 30.0, "Bonjour"),
        0
    );
    let v4 = doc.project();
    assert_eq!(u16::from_le_bytes([v4[8], v4[9]]), 4);
    unsafe {
        let text = "Bonjour";
        let box_points = corners(10.0, 10.0, 200.0, 60.0);
        assert_eq!(
            ep_set_text(
                doc.0,
                0,
                box_points.as_ptr(),
                0x112233,
                30.0,
                2,
                text.as_ptr(),
                text.len()
            ),
            1
        );
    }
    doc.assert_accounting();
    assert_eq!(unsafe { ep_project_size(doc.0) }, 0);
    let read = Owned::from_project(&doc.v6(true));
    assert_eq!(read.extra(0).param, 2);
    assert_eq!(doc.undo(), 1);
    doc.assert_accounting();
    assert_eq!(doc.project(), v4);
    // A version 4 file whose text names font 2 is refused.
    let mut forged = v4.clone();
    let record = 56 + 8;
    put_u32(&mut forged, record + 28, 2);
    assert!(Owned::try_from_project(&resealed(forged)).is_err());
}

#[test]
fn the_header_names_the_largest_file_the_readers_accept() {
    let header = include_str!("../../include/edupaint_core.h");
    let expected = format!("#define EP_MAX_READ_PROJECT_BYTES ((size_t){MAX_READ_PROJECT_BYTES})");
    assert!(header.contains(&expected), "{expected}");
    const { assert!(MAX_READ_PROJECT_BYTES >= MAX_PROJECT_BYTES) };
}

/// The drawing of the files of version 6 kept in test-fixtures/project-v6:
/// the rich one, with a zone of the paint pot and a text in another font.
fn kept() -> Owned {
    let doc = rich();
    let square = [
        point(900.0, 650.0),
        point(1000.0, 650.0),
        point(1000.0, 760.0),
        point(900.0, 760.0),
    ];
    assert_eq!(
        doc.add(&Spec {
            points: &square,
            kind: KIND_CONTOUR,
            fill: Some(0x00ff_d700),
            rgb: 0x00ff_d700,
            width: 0.5,
            look: EpObjectLook {
                tool: TOOL_ZONE,
                ..PLAIN_LOOK
            },
            ..Spec::default()
        }),
        0
    );
    let text = "Écrit à la main";
    let box_points = corners(300.0, 700.0, 700.0, 760.0);
    unsafe {
        assert_eq!(
            ep_add_text(
                doc.0,
                box_points.as_ptr(),
                0x0033_2211,
                36.0,
                3,
                text.as_ptr(),
                text.len()
            ),
            0
        );
    }
    doc.assert_accounting();
    doc
}

/// The drawing on an image of the files kept: an object on a background.
fn kept_on_image() -> Owned {
    let doc = Owned::from_png(RGB_PNG);
    assert_eq!(
        doc.add(&Spec {
            points: &[point(1.0, 1.0), point(2.5, 3.0)],
            look: EpObjectLook {
                tool: TOOL_CHALK,
                seed: 3,
                ..PLAIN_LOOK
            },
            ..Spec::default()
        }),
        0
    );
    doc
}

#[test]
#[ignore = "writes test-fixtures/project-v6 again: only when the format changes on purpose"]
fn write_the_kept_files_of_version_6() {
    let folder = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("test-fixtures/project-v6");
    std::fs::create_dir_all(&folder).unwrap();
    std::fs::write(folder.join("riche.edupaint"), kept().v6(false)).unwrap();
    std::fs::write(folder.join("riche-compresse.edupaint"), kept().v6(true)).unwrap();
    std::fs::write(folder.join("sur-image.edupaint"), kept_on_image().v6(false)).unwrap();
}

#[test]
#[cfg_attr(
    miri,
    ignore = "the files were written from the whole drawing: too long under Miri"
)]
fn the_kept_files_of_version_6_read_and_write_the_same_bytes() {
    // Written by write_the_kept_files_of_version_6 when the format was made:
    // a change of the reader or of the writer that would change what Color
    // 1.1 wrote shows here.
    const RICH: &[u8] = include_bytes!("../../test-fixtures/project-v6/riche.edupaint");
    const COMPRESSED: &[u8] =
        include_bytes!("../../test-fixtures/project-v6/riche-compresse.edupaint");
    const ON_IMAGE: &[u8] = include_bytes!("../../test-fixtures/project-v6/sur-image.edupaint");
    assert_eq!(kept().v6(false), RICH);
    assert_eq!(kept_on_image().v6(false), ON_IMAGE);
    for bytes in [RICH, ON_IMAGE] {
        let read = Owned::from_project(bytes);
        read.assert_accounting();
        assert_eq!(read.v6(false), bytes);
    }
    // Compressed by the miniz_oxide of vendor/: read without it, a block
    // that is compressed is refused, as the header says.
    if cfg!(feature = "deflate") {
        let read = Owned::from_project(COMPRESSED);
        assert_eq!(read.v6(false), RICH);
        assert_eq!(read.v6(true), COMPRESSED);
    } else {
        assert!(Owned::try_from_project(COMPRESSED).is_err());
    }
}
