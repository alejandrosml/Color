use super::*;
use crate::test_support::*;

#[test]
fn text_validation_accepts_readable_lines_and_rejects_controls_and_bad_encodings() {
    for accepted in [
        "Bonjour",
        "a",
        "Été à Noël : cœur, garçon, où ?",
        "Première ligne\nDeuxième ligne",
        "\nTexte après une ligne vide\n",
        "  deux espaces devant",
        "5 < 6 & 7 > 2 \"guillemets\" 'apostrophe'",
        "日本語 العربية ελληνικά",
        "🎨 dessin 🖌",
        "\u{fffd}",
    ] {
        assert!(valid_text(accepted.as_bytes()), "{accepted:?}");
    }
    for rejected in [
        "",
        " ",
        "\n",
        " \n \u{a0}\n",
        "tab\tulation",
        "retour\rchariot",
        "nul\0",
        "échappement\u{1b}",
        "suppression\u{7f}",
        "c1\u{85}",
        "c1\u{9f}",
        "séparateur\u{2028}ligne",
        "séparateur\u{2029}paragraphe",
        "non-caractère\u{fffe}",
        "non-caractère\u{ffff}",
    ] {
        assert!(!valid_text(rejected.as_bytes()), "{rejected:?}");
    }
    // Invalid UTF-8: lone continuation, truncated sequence, surrogate, overlong.
    for rejected in [
        &b"a\x80"[..],
        &b"\xc3"[..],
        &b"\xed\xa0\x80"[..],
        &b"\xc0\xaf"[..],
        &b"\xf8\x88\x80\x80\x80"[..],
    ] {
        assert!(!valid_text(rejected), "{rejected:?}");
    }
    assert!(valid_text("a".repeat(MAX_TEXT_BYTES).as_bytes()));
    assert!(!valid_text("a".repeat(MAX_TEXT_BYTES + 1).as_bytes()));
    // "é" is two bytes: the bound counts bytes, never characters.
    assert!(valid_text("é".repeat(MAX_TEXT_BYTES / 2).as_bytes()));
    assert!(!valid_text(
        format!("{}a", "é".repeat(MAX_TEXT_BYTES / 2)).as_bytes()
    ));
    let lines = |count: usize| vec!["a"; count].join("\n");
    assert!(valid_text(lines(MAX_TEXT_LINES).as_bytes()));
    assert!(!valid_text(lines(MAX_TEXT_LINES + 1).as_bytes()));
}

#[test]
fn text_is_a_typed_object_with_exact_characters_bytes_and_svg_lines() {
    let doc = Owned::new();
    assert_eq!(doc.dot(5.0, 6.0), 0);
    let content = "Salut & <toi>\n\n  Été 🎨";
    assert_eq!(
        doc.text(corners(100.0, 200.0, 420.0, 344.0), 0x336699, 40.0, content),
        0
    );
    assert_eq!(doc.count(), 2);
    assert_eq!(doc.kind(1), KIND_TEXT);
    assert_eq!(
        doc.extra(1),
        EpObjectExtra {
            layer: 0,
            param: 0,
            text_bytes: content.len()
        }
    );
    assert_eq!(doc.object_text(1), content);
    let info = doc.info(1);
    assert_eq!(
        (info.rgb, info.width, info.point_count),
        (0x336699, 40.0, 2)
    );
    assert_eq!(doc.extra(0).text_bytes, 0);
    doc.assert_accounting();

    let svg = doc.svg();
    assert!(svg.contains(
        "<text font-family=\"'DejaVu Sans', Verdana, sans-serif\" font-size=\"40\" fill=\"#336699\" xml:space=\"preserve\">"
    ));
    // Baselines: top + (line * 1.2 + 1.2 * 1901 / 2384) * size; the empty
    // second line emits nothing but still advances the third.
    let first = 200.0 + 1.2 * 1901.0 / 2384.0 * 40.0;
    let third = 200.0 + (2.0 * 1.2 + 1.2 * 1901.0 / 2384.0) * 40.0;
    assert!(svg.contains(&format!(
        "<tspan x=\"100\" y=\"{first}\">Salut &amp; &lt;toi&gt;</tspan>"
    )));
    assert!(svg.contains(&format!("<tspan x=\"100\" y=\"{third}\">  Été 🎨</tspan>")));
    assert_eq!(svg.matches("<tspan").count(), 2);
    assert!(!svg.contains("<g "), "a single layer adds no group");

    let bytes = doc.project();
    assert_eq!(u16::from_le_bytes([bytes[8], bytes[9]]), 4);
    let reopened = Owned::from_project(&bytes);
    assert_eq!(reopened.project(), bytes);
    assert_eq!(reopened.svg(), svg);
    assert_eq!(reopened.object_text(1), content);
    assert_eq!(reopened.kind(1), KIND_TEXT);
    reopened.assert_accounting();
    // Loaded objects are undoable; removing the text returns to project v2.
    assert_eq!(reopened.undo(), 1);
    assert_eq!(reopened.project()[8], 2);
    assert_eq!(reopened.redo(), 1);
    assert_eq!(reopened.project(), bytes);
}

#[test]
fn invalid_text_requests_preserve_drawing_and_both_history_directions() {
    let doc = Owned::new();
    assert_eq!(doc.dot(5.0, 6.0), 0);
    assert_eq!(doc.dot(7.0, 8.0), 0);
    assert_eq!(doc.undo(), 1);
    let before = doc.state();
    let good = corners(10.0, 10.0, 200.0, 60.0);
    for (corners, rgb, size, text) in [
        (corners(10.0, 10.0, 10.0, 60.0), 0, 20.0, "largeur nulle"),
        (corners(10.0, 10.0, 200.0, 10.0), 0, 20.0, "hauteur nulle"),
        (corners(-1.0, 10.0, 200.0, 60.0), 0, 20.0, "hors page"),
        (corners(10.0, 10.0, 1200.5, 60.0), 0, 20.0, "hors page"),
        (corners(10.0, f32::NAN, 200.0, 60.0), 0, 20.0, "nan"),
        (good, 0x0100_0000, 20.0, "couleur"),
        (good, 0, 3.9, "trop petit"),
        (good, 0, 2048.5, "trop grand"),
        (good, 0, f32::INFINITY, "infini"),
        (good, 0, 20.0, ""),
        (good, 0, 20.0, "  \n "),
        (good, 0, 20.0, "tab\t"),
    ] {
        assert_eq!(doc.text(corners, rgb, size, text), INVALID, "{text:?}");
        assert_eq!(doc.state(), before);
    }
    let text = "valide";
    unsafe {
        assert_eq!(
            ep_add_text(doc.0, good.as_ptr(), 0, 20.0, 1, text.as_ptr(), text.len()),
            INVALID,
            "unknown font"
        );
        assert_eq!(
            ep_add_text(doc.0, ptr::null(), 0, 20.0, 0, text.as_ptr(), text.len()),
            INVALID
        );
        assert_eq!(
            ep_add_text(doc.0, good.as_ptr(), 0, 20.0, 0, ptr::null(), text.len()),
            INVALID
        );
        assert_eq!(
            ep_add_text(doc.0, good.as_ptr(), 0, 20.0, 0, text.as_ptr(), 0),
            INVALID
        );
        assert_eq!(
            ep_add_text(doc.0, good.as_ptr(), 0, 20.0, 0, text.as_ptr(), usize::MAX),
            INVALID
        );
        assert_eq!(
            ep_add_text(
                ptr::null_mut(),
                good.as_ptr(),
                0,
                20.0,
                0,
                text.as_ptr(),
                text.len()
            ),
            INVALID
        );
        let invalid = b"mal\xffform\xe9";
        assert_eq!(
            ep_add_text(
                doc.0,
                good.as_ptr(),
                0,
                20.0,
                0,
                invalid.as_ptr(),
                invalid.len()
            ),
            INVALID
        );
    }
    assert_eq!(doc.state(), before);
    doc.assert_accounting();
}

#[test]
fn replacing_a_text_is_one_reversible_command_restoring_exact_bytes() {
    let doc = Owned::new();
    assert_eq!(
        doc.text(corners(100.0, 100.0, 300.0, 148.0), 0x112233, 40.0, "avant"),
        0
    );
    unsafe {
        assert_eq!(ep_move_object(doc.0, 0, 12.5, -7.25), 1);
    }
    let first = doc.state();
    let original_revision = unsafe { ep_object_revision(doc.0, 0) };
    assert_eq!(
        doc.set_text(
            0,
            corners(20.0, 30.0, 500.0, 126.0),
            0x445566,
            80.0,
            "après\nplus long"
        ),
        1
    );
    let second = doc.state();
    assert_ne!(unsafe { ep_object_revision(doc.0, 0) }, original_revision);
    assert_eq!(doc.object_text(0), "après\nplus long");
    assert_eq!(doc.info(0).width, 80.0);
    assert_eq!(doc.info(0).rgb, 0x445566);
    doc.assert_accounting();
    // Both versions stay retained: the old one is owned by the command.
    assert_eq!(doc.doc().retained_text_bytes, 5 + "après\nplus long".len());

    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.state().0, first.0);
    assert_eq!(doc.state().1, first.1);
    assert_eq!(unsafe { ep_object_revision(doc.0, 0) }, original_revision);
    assert_eq!(doc.object_text(0), "avant");
    doc.assert_accounting();
    assert_eq!(doc.redo(), 1);
    assert_eq!(doc.state(), second);
    doc.assert_accounting();

    // Identical content is a no-op that keeps redo; so is every refusal.
    assert_eq!(doc.undo(), 1);
    let with_redo = doc.state();
    let moved = corners(112.5, 92.75, 312.5, 140.75);
    assert_eq!(doc.set_text(0, moved, 0x112233, 40.0, "avant"), 0);
    assert_eq!(doc.set_text(0, moved, 0x112233, 40.0, ""), INVALID);
    assert_eq!(doc.set_text(0, moved, 0x112233, 2.0, "avant"), INVALID);
    assert_eq!(doc.set_text(1, moved, 0x112233, 40.0, "avant"), INVALID);
    assert_eq!(
        doc.set_text(0, corners(1.0, 1.0, 1.0, 9.0), 0x112233, 40.0, "avant"),
        INVALID
    );
    assert_eq!(doc.state(), with_redo);

    // A new branch releases the characters owned by the discarded redo.
    assert_eq!(doc.set_text(0, moved, 0x112233, 40.0, "autre"), 1);
    assert_eq!(unsafe { ep_redo_count(doc.0) }, 0);
    assert_eq!(doc.doc().retained_text_bytes, 5 + 5);
    doc.assert_accounting();
}

#[test]
fn only_texts_can_be_replaced_and_their_size_is_not_an_outline_width() {
    let doc = Owned::new();
    assert_eq!(doc.dot(5.0, 6.0), 0);
    assert_eq!(
        doc.text(corners(100.0, 100.0, 300.0, 148.0), 0x112233, 40.0, "texte"),
        0
    );
    let before = doc.state();
    assert_eq!(
        doc.set_text(0, corners(1.0, 1.0, 9.0, 9.0), 0, 40.0, "x"),
        INVALID
    );
    unsafe {
        // Colour changes through the common style command; the size does not.
        assert_eq!(ep_set_object_style(doc.0, 1, 0x112233, 12.0, 0, 0), INVALID);
        assert_eq!(
            ep_set_object_style(doc.0, 1, 0x112233, 40.0, 1, 0x123456),
            INVALID
        );
        assert_eq!(doc.state(), before);
        assert_eq!(ep_set_object_style(doc.0, 1, 0x112233, 40.0, 0, 0), 0);
        assert_eq!(ep_set_object_style(doc.0, 1, 0xabcdef, 40.0, 0, 0), 1);
    }
    assert_eq!(doc.info(1).rgb, 0xabcdef);
    assert_eq!(doc.object_text(1), "texte");
    doc.assert_accounting();
}

#[test]
fn moving_duplicating_and_removing_texts_keeps_characters_and_counters() {
    let doc = Owned::new();
    assert_eq!(
        doc.text(
            corners(100.0, 100.0, 300.0, 148.0),
            0x112233,
            40.0,
            "copie-moi"
        ),
        0
    );
    unsafe {
        assert_eq!(ep_duplicate_object(doc.0, 0, 24.0, 24.0), 1);
        assert_eq!(doc.count(), 2);
        assert_eq!(doc.object_text(1), "copie-moi");
        assert_eq!(doc.kind(1), KIND_TEXT);
        assert_eq!(doc.doc().active_text_bytes, 18);
        doc.assert_accounting();
        // The box cannot leave the page, exactly like a rectangle.
        assert_eq!(ep_move_object(doc.0, 1, 2000.0, 0.0), INVALID);
        let mut delta = point(0.0, 0.0);
        assert_eq!(
            ep_constrain_object_movement(doc.0, 1, 2000.0, 0.0, &mut delta),
            0
        );
        assert_eq!(delta.x, 1200.0 - 324.0);
        assert_eq!(ep_remove_object(doc.0, 0), 1);
        assert_eq!(doc.doc().active_text_bytes, 9);
        assert_eq!(doc.doc().retained_text_bytes, 18);
        doc.assert_accounting();
        assert_eq!(doc.undo(), 1);
        assert_eq!(doc.object_text(0), "copie-moi");
        doc.assert_accounting();
        // Capacity is all or nothing, as for points.
        let mut small = [7u8; 8];
        assert_eq!(ep_copy_object_text(doc.0, 0, small.as_mut_ptr(), 8), 0);
        assert_eq!(small, [7u8; 8]);
        assert_eq!(ep_copy_object_text(doc.0, 0, ptr::null_mut(), 64), 0);
        assert_eq!(ep_copy_object_text(doc.0, 9, small.as_mut_ptr(), 8), 0);
        assert_eq!(
            ep_copy_object_text(ptr::null(), 0, small.as_mut_ptr(), 8),
            0
        );
    }
}

#[test]
fn visible_and_retained_characters_are_bounded_atomically() {
    let doc = Owned::new();
    let full = "a".repeat(MAX_TEXT_BYTES);
    let area = corners(10.0, 10.0, 600.0, 400.0);
    for _ in 0..MAX_TOTAL_TEXT_BYTES / MAX_TEXT_BYTES {
        assert_eq!(doc.text(area, 0, 20.0, &full), 0);
    }
    assert_eq!(doc.doc().active_text_bytes, MAX_TOTAL_TEXT_BYTES);
    let limit = doc.project();
    assert_eq!(doc.text(area, 0, 20.0, "b"), INVALID);
    unsafe {
        assert_eq!(ep_duplicate_object(doc.0, 0, 1.0, 1.0), INVALID);
    }
    assert_eq!(doc.project(), limit);
    doc.assert_accounting();
    // Shortening one text frees visible room but its old value stays retained.
    assert_eq!(doc.set_text(0, area, 0, 20.0, "c"), 1);
    assert_eq!(
        doc.doc().active_text_bytes,
        MAX_TOTAL_TEXT_BYTES - MAX_TEXT_BYTES + 1
    );
    assert_eq!(doc.doc().retained_text_bytes, MAX_TOTAL_TEXT_BYTES + 1);
    // Fill the retained budget with replacements, then observe the refusal.
    let mut replacements = 0;
    loop {
        let value = if replacements % 2 == 0 {
            &full[1..]
        } else {
            &full[2..]
        };
        let status = doc.set_text(0, area, 0, 20.0, value);
        if status != 1 {
            assert_eq!(status, INVALID);
            break;
        }
        replacements += 1;
        assert!(replacements < 2000);
    }
    assert!(replacements > 400);
    let at_limit = doc.state();
    assert_eq!(doc.set_text(0, area, 0, 20.0, &full[3..]), INVALID);
    assert_eq!(doc.state(), at_limit);
    doc.assert_accounting();
    // Undo never allocates or fails at the limit, and frees nothing by itself.
    assert_eq!(doc.undo(), 1);
    doc.assert_accounting();
    // Branching releases the undone replacement: a new one fits again.
    assert_eq!(doc.set_text(0, area, 0, 20.0, "d"), 1);
    doc.assert_accounting();
}

#[test]
fn layered_files_reject_every_truncation_corruption_and_trailing_byte() {
    let doc = Owned::new();
    assert_eq!(doc.dot(5.0, 6.0), 0);
    assert_eq!(
        doc.text(corners(100.0, 100.0, 300.0, 148.0), 0x112233, 40.0, "é\nb"),
        0
    );
    let bytes = doc.project();
    assert_eq!(bytes[8], 4);
    for length in 0..bytes.len() {
        assert!(
            Owned::try_from_project(&bytes[..length]).is_err(),
            "{length}"
        );
    }
    for index in 0..bytes.len() {
        for bit in 0..8 {
            let mut corrupt = bytes.clone();
            corrupt[index] ^= 1 << bit;
            assert!(
                Owned::try_from_project(&corrupt).is_err(),
                "byte {index} bit {bit}"
            );
        }
    }
    let mut longer = bytes.clone();
    longer.push(0);
    assert!(Owned::try_from_project(&longer).is_err());
    assert!(Owned::try_from_project(&bytes).is_ok());
}

#[test]
fn layered_files_reject_invalid_values_even_with_a_valid_checksum() {
    let doc = Owned::new();
    assert_eq!(doc.dot(5.0, 6.0), 0);
    assert_eq!(
        doc.text(corners(100.0, 100.0, 300.0, 148.0), 0x112233, 40.0, "abc"),
        0
    );
    let bytes = doc.project();
    // Header 56, one layer 8, dot record 36 + 8, text record 36 + 16 + 3.
    let dot = 64;
    let text = dot + 44;
    assert_eq!(bytes.len(), text + 36 + 16 + 3 + 4);
    let check = |name: &str, change: &dyn Fn(&mut Vec<u8>)| {
        let mut altered = bytes.clone();
        change(&mut altered);
        assert!(
            Owned::try_from_project(&resealed(altered)).is_err(),
            "{name}"
        );
    };
    assert!(Owned::try_from_project(&resealed(bytes.clone())).is_ok());
    check("flags", &|b| b[10] = 1);
    check("declared size", &|b| put_u32(b, 12, 1));
    check("zero width", &|b| put_u32(b, 16, 0));
    check("object count", &|b| put_u32(b, 24, 3));
    check("point count", &|b| put_u32(b, 28, 4));
    check("background without bytes", &|b| put_u32(b, 32, 57));
    check("no layer", &|b| put_u32(b, 36, 0));
    check("seventeen layers", &|b| put_u32(b, 36, 17));
    check("text total", &|b| put_u32(b, 40, 4));
    check("unknown active layer", &|b| put_u32(b, 44, 1));
    check("reserved a", &|b| put_u32(b, 48, 1));
    check("reserved b", &|b| put_u32(b, 52, 1));
    check("layer identifier", &|b| put_u32(b, 56, 16));
    check("layer flags", &|b| put_u32(b, 60, 2));
    check("object on an unknown layer", &|b| put_u32(b, dot + 24, 1));
    check("object layer above a byte", &|b| put_u32(b, dot + 24, 256));
    check("parameter on a freehand", &|b| put_u32(b, dot + 28, 1));
    check("characters on a freehand", &|b| put_u32(b, dot + 32, 3));
    check("unknown kind", &|b| put_u32(b, text + 12, 7));
    // A contour exists in version 5 only.
    check("contour in version 4", &|b| {
        put_u32(b, text + 12, KIND_CONTOUR)
    });
    check("filled text", &|b| put_u32(b, text + 16, 1));
    check("text colour", &|b| put_u32(b, text, 0x0100_0000));
    check("text size", &|b| {
        b[text + 4..text + 8].copy_from_slice(&3.0f32.to_le_bytes())
    });
    check("unknown font", &|b| put_u32(b, text + 28, 1));
    check("text without characters", &|b| put_u32(b, text + 32, 0));
    check("text with one point", &|b| put_u32(b, text + 8, 1));
    check("degenerate box", &|b| {
        let first: [u8; 4] = b[text + 36..text + 40].try_into().unwrap();
        b[text + 44..text + 48].copy_from_slice(&first);
    });
    check("control character", &|b| b[text + 52] = b'\t');
    check("invalid utf-8", &|b| b[text + 52] = 0xff);
    check("only spaces", &|b| {
        b[text + 52..text + 55].copy_from_slice(b"   ")
    });
    // A text needs version 4: the same record kind is unknown to version 2.
    let plain = Owned::new();
    assert_eq!(plain.dot(5.0, 6.0), 0);
    let mut legacy = plain.project();
    assert_eq!(legacy[8], 2);
    put_u32(&mut legacy, 32 + 12, KIND_TEXT);
    assert!(Owned::try_from_project(&resealed(legacy)).is_err());
}

#[test]
fn snapshots_and_candidates_share_the_text_serializers() {
    let doc = Owned::new();
    assert_eq!(
        doc.text(
            corners(100.0, 100.0, 300.0, 148.0),
            0x112233,
            40.0,
            "instantané"
        ),
        0
    );
    let bytes = doc.project();
    let svg = doc.svg();
    unsafe {
        let mut status = 99;
        let snapshot = ep_export_snapshot_new(doc.0, &mut status);
        assert_eq!(status, 0);
        // The source may change or disappear: the snapshot is autonomous.
        assert_eq!(
            doc.set_text(0, corners(1.0, 1.0, 90.0, 40.0), 0, 20.0, "x"),
            1
        );
        assert_eq!(ep_export_snapshot_project_size(snapshot), bytes.len());
        let mut copy = vec![0; bytes.len()];
        assert_eq!(
            ep_export_snapshot_copy_project(snapshot, copy.as_mut_ptr(), copy.len()),
            0
        );
        assert_eq!(copy, bytes);
        let raw = ep_export_snapshot_export_svg(snapshot);
        assert_eq!(std::ffi::CStr::from_ptr(raw).to_str().unwrap(), svg);
        ep_string_free(raw);
        ep_export_snapshot_free(snapshot);
        // A private candidate adopts the same file transactionally.
        let candidate = Owned::sized(1, 1);
        assert_eq!(
            ep_document_load_project(candidate.0, bytes.as_ptr(), bytes.len()),
            0
        );
        assert_eq!(candidate.project(), bytes);
        candidate.assert_accounting();
    }
}

#[test]
fn a_text_needs_one_character_that_leaves_a_mark() {
    let doc = Owned::new();
    let place = corners(100.0, 100.0, 400.0, 200.0);
    // Characters that renderers ignore when nothing stands with them, and
    // white space: alone or together, they are not a text.
    let unseen = [
        '\u{20}',
        '\u{a0}',
        '\u{1680}',
        '\u{2000}',
        '\u{200a}',
        '\u{202f}',
        '\u{205f}',
        '\u{3000}',
        '\u{ad}',
        '\u{34f}',
        '\u{61c}',
        '\u{115f}',
        '\u{1160}',
        '\u{17b4}',
        '\u{17b5}',
        '\u{180b}',
        '\u{180f}',
        '\u{200b}',
        '\u{200d}',
        '\u{200f}',
        '\u{202a}',
        '\u{202e}',
        '\u{2060}',
        '\u{2064}',
        '\u{206f}',
        '\u{3164}',
        '\u{fe00}',
        '\u{fe0f}',
        '\u{feff}',
        '\u{ffa0}',
        '\u{fff0}',
        '\u{fff8}',
        '\u{1bca0}',
        '\u{1bca3}',
        '\u{1d173}',
        '\u{1d17a}',
        '\u{e0000}',
        '\u{e0001}',
        '\u{e0fff}',
    ];
    let before = doc.state();
    let mut all = String::new();
    for character in unseen {
        assert!(!leaves_a_mark(character), "U+{:04X}", character as u32);
        assert_eq!(
            doc.text(place, 0, 20.0, &character.to_string()),
            -1,
            "U+{:04X} alone",
            character as u32
        );
        if all.len() + character.len_utf8() < 200 {
            all.push(character);
            all.push('\n');
        }
    }
    assert_eq!(doc.text(place, 0, 20.0, all.trim_end_matches('\n')), -1);
    assert_eq!(doc.state(), before);

    // Their neighbours on either side of each range do leave a mark.
    for character in [
        '!',
        '\u{ac}',
        '\u{ae}',
        '\u{34e}',
        '\u{350}',
        '\u{115e}',
        '\u{1161}',
        '\u{180a}',
        '\u{1810}',
        '\u{2010}',
        '\u{2030}',
        '\u{2070}',
        '\u{3163}',
        '\u{3165}',
        '\u{fdff}',
        '\u{fe10}',
        '\u{fefe}',
        '\u{ff9f}',
        '\u{ffa1}',
        '\u{ffef}',
        '\u{fff9}',
        '\u{1bc9f}',
        '\u{1bca4}',
        '\u{1d172}',
        '\u{1d17b}',
        '\u{dffff}',
        '\u{e1000}',
    ] {
        assert!(leaves_a_mark(character), "U+{:04X}", character as u32);
    }

    // Beside a character that is seen they are kept exactly: joiners and
    // selectors have a job there, and the byte-order mark is not this
    // core's to remove.
    for text in [
        "\u{feff}Bonjour",
        "a\u{200d}b",
        "\u{fe0f}\u{2764}\u{fe0f}",
        "é\u{ad}té",
    ] {
        let index = doc.count();
        assert_eq!(doc.text(place, 0, 20.0, text), 0, "{text:?}");
        assert_eq!(doc.object_text(index), text);
    }
    let reopened = Owned::from_project(&doc.project());
    assert_eq!(reopened.object_text(0), "\u{feff}Bonjour");
    assert!(doc.svg().contains("\u{feff}Bonjour"));

    // A file whose text leaves no mark is refused like any invalid text.
    let single = Owned::new();
    assert_eq!(single.text(place, 0, 20.0, "é"), 0);
    let mut bytes = single.project();
    let at = bytes
        .windows(2)
        .rposition(|pair| pair == "é".as_bytes())
        .unwrap();
    bytes[at..at + 2].copy_from_slice("\u{ad}".as_bytes());
    assert!(Owned::try_from_project(&resealed(bytes)).is_err());
}
