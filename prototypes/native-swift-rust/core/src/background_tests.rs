use super::*;
use std::ffi::CStr;

const RGB: &[u8] = include_bytes!("../test-fixtures/rgb-asymmetric.png");
const RGBA: &[u8] = include_bytes!("../test-fixtures/rgba-asymmetric.png");

struct Owned(*mut EpDocument);
impl Owned {
    fn png(bytes: &[u8]) -> Self {
        let mut status = 77;
        let doc =
            unsafe { ep_document_from_background_png(bytes.as_ptr(), bytes.len(), &mut status) };
        assert_eq!(status, 0);
        assert!(!doc.is_null());
        Self(doc)
    }
    fn load(bytes: &[u8]) -> Self {
        let mut status = 77;
        let doc = unsafe { ep_document_from_project(bytes.as_ptr(), bytes.len(), &mut status) };
        assert_eq!(status, 0);
        assert!(!doc.is_null());
        Self(doc)
    }
    fn project(&self) -> Vec<u8> {
        let mut bytes = vec![0; unsafe { ep_project_size(self.0) }];
        assert_eq!(
            unsafe { ep_copy_project(self.0, bytes.as_mut_ptr(), bytes.len()) },
            0
        );
        bytes
    }
    fn background(&self) -> Vec<u8> {
        let mut info = EpBackgroundInfo {
            width: 0,
            height: 0,
            byte_count: 0,
        };
        assert_eq!(unsafe { ep_background_info(self.0, &mut info) }, 1);
        let mut bytes = vec![0; info.byte_count];
        assert_eq!(
            unsafe { ep_copy_background_png(self.0, bytes.as_mut_ptr(), bytes.len()) },
            bytes.len()
        );
        bytes
    }
    fn svg(&self) -> String {
        let pointer = unsafe { ep_export_svg(self.0) };
        assert!(!pointer.is_null());
        let result = unsafe { CStr::from_ptr(pointer) }
            .to_str()
            .unwrap()
            .to_owned();
        unsafe { ep_string_free(pointer) };
        result
    }
    fn dot(&self) {
        assert_eq!(
            unsafe { ep_add_stroke(self.0, &EpPoint { x: 2.0, y: 3.0 }, 1, 0x123456, 2.0) },
            0
        );
    }
}
impl Drop for Owned {
    fn drop(&mut self) {
        unsafe {
            ep_document_free(self.0);
        }
    }
}

fn reject_png(bytes: &[u8]) {
    let mut status = 77;
    let doc = unsafe { ep_document_from_background_png(bytes.as_ptr(), bytes.len(), &mut status) };
    assert!(doc.is_null());
    assert_eq!(status, INVALID);
}

fn reject_project(bytes: &[u8]) {
    let mut status = 77;
    let doc = unsafe { ep_document_from_project(bytes.as_ptr(), bytes.len(), &mut status) };
    assert!(doc.is_null());
    assert_eq!(status, INVALID);
}

fn fix_crc(bytes: &mut [u8]) {
    let end = bytes.len() - 4;
    let value = crc32(&bytes[..end]);
    bytes[end..].copy_from_slice(&value.to_le_bytes());
}

#[test]
fn combined_cached_crc_matches_direct_crc_and_recovers_the_background_crc() {
    let bytes: Vec<u8> = (0..8193usize)
        .map(|i| ((i * 197) ^ (i >> 3)) as u8)
        .collect();
    for len in [0, 1, 2, 7, 8, 9, 31, 255, 1024, 8193] {
        let whole = crc32(&bytes[..len]);
        for split in 0..=len {
            let prefix = crc32(&bytes[..split]);
            let suffix = crc32(&bytes[split..len]);
            assert_eq!(crc32_combine(prefix, suffix, len - split), whole);
            if split != len {
                assert_eq!(whole ^ crc32_combine(prefix, 0, len - split), suffix);
            }
        }
    }
    assert_eq!(
        crc32_combine(crc32(b"1234"), crc32(b"56789"), 5),
        0xcbf4_3926
    );
    for input in [RGB, RGBA] {
        let imported = Owned::png(input);
        imported.dot();
        let loaded = Owned::load(&imported.project());
        for doc in [imported, loaded] {
            assert_eq!(
                unsafe { (*doc.0).background.as_ref().unwrap().crc },
                crc32(input)
            );
            let bytes = doc.project();
            assert_eq!(
                u32::from_le_bytes(bytes[bytes.len() - 4..].try_into().unwrap()),
                crc32(&bytes[..bytes.len() - 4])
            );
        }
    }
}

fn png_chunk(kind: &[u8; 4], data: &[u8]) -> Vec<u8> {
    let mut chunk = Vec::new();
    chunk.extend_from_slice(&(data.len() as u32).to_be_bytes());
    chunk.extend_from_slice(kind);
    chunk.extend_from_slice(data);
    chunk.extend_from_slice(&crc32(&chunk[4..]).to_be_bytes());
    chunk
}

fn with_metadata(base: &[u8], kind: &[u8; 4], data: &[u8]) -> Vec<u8> {
    let mut output = base[..33].to_vec();
    output.extend(png_chunk(kind, data));
    output.extend_from_slice(&base[33..]);
    output
}

fn change_ihdr(base: &[u8], f: impl FnOnce(&mut [u8])) -> Vec<u8> {
    let mut data = base[16..29].to_vec();
    f(&mut data);
    let mut result = base[..8].to_vec();
    result.extend(png_chunk(b"IHDR", &data));
    result.extend_from_slice(&base[33..]);
    result
}

#[test]
fn authentic_png_background_is_owned_immutable_and_not_an_undoable_object() {
    for input in [RGB, RGBA] {
        let mut temporary = input.to_vec();
        let doc = Owned::png(&temporary);
        temporary.fill(0);
        assert_eq!(doc.background(), input);
        unsafe {
            assert_eq!(ep_document_width(doc.0), 32);
            assert_eq!(ep_document_height(doc.0), 24);
            assert_eq!(ep_stroke_count(doc.0), 0);
            assert_eq!(ep_object_revision(doc.0, 0), 0);
            assert_eq!(ep_undo_count(doc.0), 0);
            assert_eq!(ep_undo(doc.0), 0);
            assert_eq!(ep_redo(doc.0), 0);
        }
    }
}

#[test]
fn background_ffi_errors_do_not_write_output_or_read_oversized_input() {
    let doc = Owned::png(RGBA);
    let blank = Owned(ep_document_new(32, 24));
    let sentinel = EpBackgroundInfo {
        width: 91,
        height: 92,
        byte_count: 93,
    };
    let mut info = sentinel;
    let mut output = vec![0xa5; RGBA.len() + 7];
    let before = doc.project();
    unsafe {
        assert_eq!(ep_background_info(ptr::null(), &mut info), INVALID);
        assert_eq!(ep_background_info(blank.0, &mut info), 0);
        assert_eq!(ep_background_info(doc.0, ptr::null_mut()), INVALID);
        assert_eq!(info, sentinel);
        assert_eq!(
            ep_copy_background_png(ptr::null(), output.as_mut_ptr(), output.len()),
            0
        );
        assert_eq!(
            ep_copy_background_png(blank.0, output.as_mut_ptr(), output.len()),
            0
        );
        assert_eq!(
            ep_copy_background_png(doc.0, ptr::null_mut(), output.len()),
            0
        );
        assert_eq!(
            ep_copy_background_png(doc.0, output.as_mut_ptr(), RGBA.len() - 1),
            0
        );
        assert!(output.iter().all(|byte| *byte == 0xa5));
        assert_eq!(
            ep_copy_background_png(doc.0, output.as_mut_ptr(), output.len()),
            RGBA.len()
        );
        assert_eq!(&output[..RGBA.len()], RGBA);
        assert_eq!(&output[RGBA.len()..], &[0xa5; 7]);
        let mut status = 77;
        for (pointer, length) in [
            (ptr::null(), RGBA.len()),
            (RGBA.as_ptr(), 0),
            (RGBA.as_ptr(), usize::MAX),
            (RGBA.as_ptr(), MAX_BACKGROUND_BYTES + 1),
        ] {
            assert!(ep_document_from_background_png(pointer, length, &mut status).is_null());
            assert_eq!(status, INVALID);
        }
        let optional = ep_document_from_background_png(RGB.as_ptr(), RGB.len(), ptr::null_mut());
        assert!(!optional.is_null());
        ep_document_free(optional);
    }
    assert_eq!(doc.project(), before);
}

#[test]
fn png_rejects_every_truncation_and_single_byte_corruption() {
    for length in 0..RGBA.len() {
        reject_png(&RGBA[..length]);
    }
    for index in 0..RGBA.len() {
        let mut bytes = RGBA.to_vec();
        bytes[index] ^= 0x40;
        reject_png(&bytes);
    }
    let mut trailing = RGBA.to_vec();
    trailing.push(0);
    reject_png(&trailing);
}

#[test]
fn canonical_png_checks_dimensions_format_order_metadata_and_chunk_crcs() {
    for width in [0, 8193, u32::MAX] {
        reject_png(&change_ihdr(RGB, |h| {
            h[..4].copy_from_slice(&width.to_be_bytes())
        }));
    }
    for height in [0, 8193, u32::MAX] {
        reject_png(&change_ihdr(RGB, |h| {
            h[4..8].copy_from_slice(&height.to_be_bytes())
        }));
    }
    reject_png(&change_ihdr(RGB, |h| {
        h[..4].copy_from_slice(&8192u32.to_be_bytes());
        h[4..8].copy_from_slice(&2049u32.to_be_bytes());
    }));
    for (offset, value) in [
        (8, 16),
        (8, 1),
        (9, 0),
        (9, 3),
        (9, 4),
        (10, 1),
        (11, 1),
        (12, 1),
    ] {
        reject_png(&change_ihdr(RGB, |h| h[offset] = value));
    }
    for kind in [
        b"acTL", b"fcTL", b"fdAT", b"iCCP", b"tEXt", b"zTXt", b"tpLL", b"PLTE", b"tRNS", b"abcd",
    ] {
        reject_png(&with_metadata(RGB, kind, &[0; 8]));
    }
    let mut allowed = with_metadata(RGBA, b"sRGB", &[0]);
    allowed = with_metadata(&allowed, b"gAMA", &45455u32.to_be_bytes());
    let chrm: Vec<u8> = [31270u32, 32900, 64000, 33000, 30000, 60000, 15000, 6000]
        .into_iter()
        .flat_map(u32::to_be_bytes)
        .collect();
    allowed = with_metadata(&allowed, b"cHRM", &chrm);
    allowed = with_metadata(&allowed, b"pHYs", &[0, 0, 0x0b, 0x13, 0, 0, 0x0b, 0x13, 1]);
    assert_eq!(Owned::png(&allowed).background(), allowed);
    reject_png(&with_metadata(&allowed, b"sRGB", &[0]));
    reject_png(&with_metadata(RGB, b"sRGB", &[4]));
    reject_png(&with_metadata(RGB, b"sRGB", &[]));
    reject_png(&with_metadata(RGB, b"gAMA", &100000u32.to_be_bytes()));
    let mut wrong_chrm = chrm.clone();
    wrong_chrm[3] ^= 1;
    reject_png(&with_metadata(RGB, b"cHRM", &wrong_chrm));
    reject_png(&with_metadata(RGB, b"pHYs", &[0; 8]));
    reject_png(&with_metadata(RGB, b"pHYs", &[2; 9]));
    reject_png(&with_metadata(RGB, b"IHDR", &RGB[16..29]));
    let mut late = RGB[..RGB.len() - 12].to_vec();
    late.extend(png_chunk(b"sRGB", &[0]));
    late.extend_from_slice(&RGB[RGB.len() - 12..]);
    reject_png(&late);
    let mut missing_idat = RGB[..33].to_vec();
    missing_idat.extend(png_chunk(b"IEND", &[]));
    reject_png(&missing_idat);
    let mut empty_idat = RGB[..33].to_vec();
    empty_idat.extend(png_chunk(b"IDAT", &[]));
    empty_idat.extend(png_chunk(b"IEND", &[]));
    reject_png(&empty_idat);
    let mut nonempty_iend = RGB[..RGB.len() - 12].to_vec();
    nonempty_iend.extend(png_chunk(b"IEND", &[0]));
    reject_png(&nonempty_iend);
}

#[test]
fn png_allows_contiguous_idat_but_does_not_claim_to_validate_compressed_pixels() {
    let length = u32::from_be_bytes(RGB[33..37].try_into().unwrap()) as usize;
    assert_eq!(&RGB[37..41], b"IDAT");
    let compressed = &RGB[41..41 + length];
    let half = compressed.len() / 2;
    let mut split = RGB[..33].to_vec();
    split.extend(png_chunk(b"IDAT", &compressed[..half]));
    split.extend(png_chunk(b"IDAT", &[]));
    split.extend(png_chunk(b"IDAT", &compressed[half..]));
    split.extend(png_chunk(b"IEND", &[]));
    assert_eq!(Owned::png(&split).background(), split);
    // Deliberately invalid zlib stream with valid structure/CRC: the documented
    // caller-side codec check must refuse this before document adoption.
    let mut structurally_valid = RGB[..33].to_vec();
    structurally_valid.extend(png_chunk(b"IDAT", &[0xff]));
    structurally_valid.extend(png_chunk(b"IEND", &[]));
    assert_eq!(
        Owned::png(&structurally_valid).background(),
        structurally_valid
    );
}

#[test]
fn v3_layout_is_exact_v2_records_then_owned_png_and_global_crc() {
    let hybrid = Owned::png(RGBA);
    hybrid.dot();
    let vector = Owned(ep_document_new(32, 24));
    vector.dot();
    let v2 = vector.project();
    let v3 = hybrid.project();
    assert_eq!(&v2[8..10], &2u16.to_le_bytes());
    assert_eq!(&v3[8..10], &3u16.to_le_bytes());
    assert_eq!(v3.len(), v2.len() + 16 + RGBA.len());
    assert_eq!(u32::from_le_bytes(v3[32..36].try_into().unwrap()), 1);
    assert_eq!(
        u32::from_le_bytes(v3[36..40].try_into().unwrap()) as usize,
        RGBA.len()
    );
    assert_eq!(&v3[40..48], &v3[16..24]);
    assert_eq!(&v3[48..48 + v2.len() - 36], &v2[32..v2.len() - 4]);
    assert_eq!(&v3[v3.len() - 4 - RGBA.len()..v3.len() - 4], RGBA);
    let loaded = Owned::load(&v3);
    assert_eq!(loaded.project(), v3);
    assert_eq!(loaded.svg(), hybrid.svg());
    assert_eq!(loaded.background(), RGBA);
    unsafe {
        assert_eq!(ep_undo_count(loaded.0), 1);
        assert_eq!(ep_undo(loaded.0), 1);
        assert_eq!(ep_undo(loaded.0), 0);
        assert_eq!(ep_stroke_count(loaded.0), 0);
    }
    assert_eq!(loaded.background(), RGBA);
    assert!(loaded.svg().contains("data:image/png;base64,"));
    unsafe {
        assert_eq!(ep_redo(loaded.0), 1);
    }
    assert_eq!(loaded.project(), v3);
}

#[test]
fn v3_mutations_and_history_never_copy_modify_or_detach_the_background() {
    let doc = Owned::png(RGBA);
    let base = unsafe { (*doc.0).background.as_ref().unwrap().bytes.as_ptr() };
    doc.dot();
    unsafe {
        assert_eq!(ep_move_object(doc.0, 0, 1.0, 2.0), 1);
        assert_eq!(ep_duplicate_object(doc.0, 0, 4.0, 3.0), 1);
        assert_eq!(ep_set_object_style(doc.0, 1, 0xffaabb, 3.5, 0, 0), 1);
        assert_eq!(ep_remove_object(doc.0, 0), 1);
        let edited = doc.project();
        for _ in 0..5 {
            assert_eq!(ep_undo(doc.0), 1);
            assert_eq!((*doc.0).background.as_ref().unwrap().bytes.as_ptr(), base);
            assert_eq!(doc.background(), RGBA);
        }
        assert_eq!(ep_undo(doc.0), 0);
        for _ in 0..5 {
            assert_eq!(ep_redo(doc.0), 1);
        }
        assert_eq!(doc.project(), edited);
        assert_eq!(ep_undo(doc.0), 1);
        assert_eq!(ep_set_object_style(doc.0, 0, 0x224466, 4.0, 0, 0), 1);
        assert_eq!(ep_redo_count(doc.0), 0);
        assert_eq!((*doc.0).background.as_ref().unwrap().bytes.as_ptr(), base);
        let before = doc.project();
        let revisions: Vec<_> = (0..ep_stroke_count(doc.0))
            .map(|index| ep_object_revision(doc.0, index))
            .collect();
        assert_eq!(ep_move_object(doc.0, 0, 999.0, 0.0), INVALID);
        assert_eq!(ep_remove_object(doc.0, 99), INVALID);
        assert_eq!(doc.project(), before);
        assert_eq!(
            (0..ep_stroke_count(doc.0))
                .map(|index| ep_object_revision(doc.0, index))
                .collect::<Vec<_>>(),
            revisions
        );
    }
    assert_eq!(doc.background(), RGBA);
}

#[test]
fn v3_rejects_truncations_corruption_and_forged_headers_even_after_global_crc_repair() {
    let doc = Owned::png(RGBA);
    doc.dot();
    let original = doc.project();
    for length in 0..original.len() {
        reject_project(&original[..length]);
    }
    for index in 0..original.len() {
        let mut bytes = original.clone();
        bytes[index] ^= 0x40;
        reject_project(&bytes);
    }
    for (offset, value) in [
        (12, u32::MAX),
        (16, 31),
        (20, 23),
        (24, 0),
        (24, u32::MAX),
        (28, 0),
        (28, u32::MAX),
        (32, 0),
        (32, 2),
        (36, 0),
        (36, u32::MAX),
        (36, MAX_BACKGROUND_BYTES as u32 + 1),
        (40, 31),
        (44, 23),
        (48, 0x01000000),
        (52, f32::NAN.to_bits()),
        (56, 0),
        (60, 4),
        (72, f32::INFINITY.to_bits()),
    ] {
        let mut bytes = original.clone();
        bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
        fix_crc(&mut bytes);
        reject_project(&bytes);
    }
    let png_start = original.len() - 4 - RGBA.len();
    let mut broken_png = original.clone();
    broken_png[png_start + 20] ^= 1;
    fix_crc(&mut broken_png);
    reject_project(&broken_png);
    let mut wrong_version = original.clone();
    wrong_version[8..10].copy_from_slice(&2u16.to_le_bytes());
    fix_crc(&mut wrong_version);
    reject_project(&wrong_version);
    assert_eq!(doc.project(), original);
}

#[test]
fn v3_copy_project_preserves_short_outputs_and_extra_capacity() {
    let doc = Owned::png(RGB);
    doc.dot();
    let expected = doc.project();
    let mut out = vec![0xa5; expected.len() + 13];
    unsafe {
        assert_eq!(
            ep_copy_project(doc.0, out.as_mut_ptr(), expected.len() - 1),
            INVALID
        );
        assert!(out.iter().all(|byte| *byte == 0xa5));
        assert_eq!(ep_copy_project(doc.0, out.as_mut_ptr(), out.len()), 0);
    }
    assert_eq!(&out[..expected.len()], expected);
    assert_eq!(&out[expected.len()..], &[0xa5; 13]);
}

#[test]
fn svg_background_is_autonomous_below_vectors_and_base64_is_exact() {
    for (bytes, expected) in [
        (b"".as_slice(), ""),
        (b"f", "Zg=="),
        (b"fo", "Zm8="),
        (b"foo", "Zm9v"),
        (b"foob", "Zm9vYg=="),
        (b"fooba", "Zm9vYmE="),
        (b"foobar", "Zm9vYmFy"),
    ] {
        let mut encoded = String::new();
        append_base64(&mut encoded, bytes);
        assert_eq!(encoded, expected);
    }
    let doc = Owned::png(RGBA);
    doc.dot();
    let svg = doc.svg();
    let start = svg.find("data:image/png;base64,").unwrap() + "data:image/png;base64,".len();
    let end = start + svg[start..].find('"').unwrap();
    let mut decoded = Vec::new();
    let mut buffer = 0u32;
    let mut bits = 0;
    for byte in svg.as_bytes()[start..end]
        .iter()
        .copied()
        .take_while(|c| *c != b'=')
    {
        let value = match byte {
            b'A'..=b'Z' => byte - b'A',
            b'a'..=b'z' => byte - b'a' + 26,
            b'0'..=b'9' => byte - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => panic!("invalid base64"),
        };
        buffer = (buffer << 6) | u32::from(value);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            decoded.push((buffer >> bits) as u8);
        }
    }
    assert_eq!(decoded, RGBA);
    assert!(svg.find("fill=\"#ffffff\"").unwrap() < svg.find("<image ").unwrap());
    assert!(svg.find("<image ").unwrap() < svg.find("<circle ").unwrap());
    assert!(svg.contains("<image x=\"0\" y=\"0\" width=\"32\" height=\"24\""));
    assert_eq!(svg.matches("data:image/png;base64,").count(), 1);
    assert!(!svg.contains("file:"));
}
