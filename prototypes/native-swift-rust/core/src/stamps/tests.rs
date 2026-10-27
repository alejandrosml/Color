use super::*;
use crate::test_support::*;
use std::ffi::CStr;

// Identifiers are stored in project files. This list may only grow at its end.
const FROZEN_KEYS: [&str; 24] = [
    "etoile",
    "coeur",
    "soleil",
    "lune",
    "nuage",
    "fleur",
    "arbre",
    "maison",
    "chat",
    "poisson",
    "papillon",
    "ballon",
    "voiture",
    "bateau",
    "fusee",
    "pomme",
    "sourire",
    "eclair",
    "champignon",
    "couronne",
    "goutte",
    "oiseau",
    "chien",
    "arcenciel",
];

#[test]
fn catalogue_identifiers_are_frozen_and_every_path_uses_the_documented_subset() {
    assert!(STAMPS.len() >= FROZEN_KEYS.len());
    assert_eq!(ep_stamp_count() as usize, STAMPS.len());
    for (id, key) in FROZEN_KEYS.iter().enumerate() {
        assert_eq!(STAMPS[id].key, *key, "stamp {id} changed identity");
    }
    let mut keys: Vec<_> = STAMPS.iter().map(|stamp| stamp.key).collect();
    keys.sort_unstable();
    keys.dedup();
    assert_eq!(keys.len(), STAMPS.len(), "duplicate key");
    for stamp in STAMPS {
        assert!(!stamp.key.is_empty());
        assert!(stamp
            .key
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit()));
        assert!(!stamp.layers.is_empty(), "{}", stamp.key);
        for layer in stamp.layers {
            assert!(
                layer.fill != Paint::None || layer.stroke != Paint::None,
                "{}: invisible layer",
                stamp.key
            );
            assert!(layer.width.is_finite() && (0.0..=16.0).contains(&layer.width));
            assert_eq!(
                layer.stroke == Paint::None,
                layer.width == 0.0,
                "{}",
                stamp.key
            );
            for paint in [layer.fill, layer.stroke] {
                if let Paint::Fixed(rgb) = paint {
                    assert!(rgb <= 0x00ff_ffff);
                }
            }
            // Command letters are followed by exactly their number of operands.
            let mut tokens = layer.path.split(' ');
            let mut commands = 0;
            assert!(layer.path.starts_with("M "), "{}", stamp.key);
            while let Some(command) = tokens.next() {
                let operands = match command {
                    "M" | "L" => 2,
                    "Q" => 4,
                    "C" => 6,
                    "Z" => 0,
                    other => panic!("{}: unexpected token {other:?}", stamp.key),
                };
                for _ in 0..operands {
                    let value: f32 = tokens
                        .next()
                        .unwrap_or_else(|| panic!("{}: truncated path", stamp.key))
                        .parse()
                        .unwrap_or_else(|_| panic!("{}: not a number", stamp.key));
                    assert!((-10.0..=110.0).contains(&value), "{}: {value}", stamp.key);
                }
                commands += 1;
            }
            assert!(commands >= 2, "{}", stamp.key);
            assert!(!layer.path.contains(['"', '<', '>', '&', '|', ';', ',']));
        }
    }
}

#[test]
fn catalogue_text_lists_every_stamp_once_and_is_released_by_the_string_free() {
    let raw = ep_stamp_catalog();
    assert!(!raw.is_null());
    let text = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_owned();
    unsafe { ep_string_free(raw) };
    assert!(text.is_ascii());
    let lines: Vec<_> = text.lines().collect();
    assert_eq!(lines.len(), STAMPS.len());
    for (id, line) in lines.iter().enumerate() {
        let fields: Vec<_> = line.split('|').collect();
        assert_eq!(fields.len(), 3, "{line}");
        assert_eq!(fields[0], id.to_string());
        assert_eq!(fields[1], STAMPS[id].key);
        let layers: Vec<_> = fields[2].split(';').collect();
        assert_eq!(layers.len(), STAMPS[id].layers.len());
        for (layer, expected) in layers.iter().zip(STAMPS[id].layers) {
            let parts: Vec<_> = layer.splitn(4, ',').collect();
            assert_eq!(parts.len(), 4);
            for paint in &parts[..2] {
                assert!(
                    matches!(*paint, "-" | "P" | "D" | "L")
                        || (paint.len() == 7
                            && paint.starts_with('#')
                            && u32::from_str_radix(&paint[1..], 16).is_ok()),
                    "{paint}"
                );
            }
            assert_eq!(parts[2].parse::<f32>().unwrap(), expected.width);
            assert_eq!(parts[3], expected.path);
        }
    }
    assert_eq!(text.len(), text.trim_end().len() + 1, "one final newline");
}

#[test]
fn shades_are_exact_integer_functions_of_the_chosen_colour() {
    assert_eq!(Paint::None.rgb(0x123456), None);
    assert_eq!(Paint::Primary.rgb(0x477fb2), Some(0x477fb2));
    assert_eq!(Paint::Fixed(0x293d4b).rgb(0x477fb2), Some(0x293d4b));
    // 0x47 = 71 -> 49, 0x7f = 127 -> 88, 0xb2 = 178 -> 124.
    assert_eq!(Paint::Dark.rgb(0x477fb2), Some(0x31587c));
    // 71 + 184 * 6 / 10 = 181, 127 + 128 * 6 / 10 = 203, 178 + 77 * 6 / 10 = 224.
    assert_eq!(Paint::Light.rgb(0x477fb2), Some(0xb5cbe0));
    assert_eq!(Paint::Dark.rgb(0xffffff), Some(0xb2b2b2));
    assert_eq!(Paint::Light.rgb(0x000000), Some(0x999999));
    assert_eq!(Paint::Dark.rgb(0x000000), Some(0x000000));
    assert_eq!(Paint::Light.rgb(0xffffff), Some(0xffffff));
}

#[test]
fn stamp_is_a_typed_reference_scaled_into_its_box_and_roundtrips_in_v4() {
    let doc = Owned::new();
    // Corners in any order, as for rectangles.
    assert_eq!(
        doc.stamp(corners(300.0, 260.0, 100.0, 60.0), 1, 0x477fb2),
        0
    );
    assert_eq!(doc.count(), 1);
    assert_eq!(doc.kind(0), KIND_STAMP);
    assert_eq!(
        doc.extra(0),
        EpObjectExtra {
            layer: 0,
            param: 1,
            text_bytes: 0
        }
    );
    let info = doc.info(0);
    assert_eq!((info.rgb, info.width, info.point_count), (0x477fb2, 1.0, 2));
    let svg = doc.svg();
    assert!(svg.contains("<g transform=\"translate(100 60) scale(2 2)\">"));
    let heart = &STAMPS[1];
    assert!(svg.contains(&format!(
        "<path d=\"{}\" fill=\"#477fb2\" stroke=\"#293d4b\" stroke-width=\"4\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>",
        heart.layers[0].path
    )));
    assert!(svg.contains(&format!(
        "<path d=\"{}\" fill=\"#b5cbe0\" stroke=\"none\"/>",
        heart.layers[1].path
    )));
    assert_eq!(svg.matches("<path").count(), heart.layers.len());
    doc.assert_accounting();

    let bytes = doc.project();
    assert_eq!(bytes[8], 4);
    assert_eq!(bytes.len(), 56 + 8 + 36 + 16 + 4);
    let reopened = Owned::from_project(&bytes);
    assert_eq!(reopened.project(), bytes);
    assert_eq!(reopened.svg(), svg);
    assert_eq!(reopened.extra(0).param, 1);

    unsafe {
        // Colour is a style; a stamp has neither outline width nor fill.
        assert_eq!(ep_set_object_style(doc.0, 0, 0xd75e56, 1.0, 0, 0), 1);
        assert_eq!(ep_set_object_style(doc.0, 0, 0xd75e56, 3.0, 0, 0), INVALID);
        assert_eq!(ep_set_object_style(doc.0, 0, 0xd75e56, 1.0, 1, 0), INVALID);
        assert_eq!(ep_duplicate_object(doc.0, 0, 24.0, 24.0), 1);
        assert_eq!(doc.extra(1).param, 1);
        assert_eq!(ep_move_object(doc.0, 1, 10.0, 0.0), 1);
    }
    assert!(doc.svg().contains("translate(134 84) scale(2 2)"));
    doc.assert_accounting();
}

#[test]
fn every_stamp_exports_within_its_reserved_markup_and_invalid_requests_change_nothing() {
    for id in 0..ep_stamp_count() {
        let doc = Owned::new();
        assert_eq!(doc.stamp(corners(0.0, 0.0, 1200.0, 800.0), id, 0xabcdef), 0);
        let mut markup = String::new();
        write_stamp_svg(&mut markup, id, 0xabcdef, 0.0, 0.0, 1200.0, 800.0).unwrap();
        assert!(markup.len() <= stamp_svg_bytes(id), "stamp {id}");
        assert!(doc.svg().contains(&markup));
        let reopened = Owned::from_project(&doc.project());
        assert_eq!(reopened.svg(), doc.svg());
    }
    let doc = Owned::new();
    assert_eq!(doc.dot(5.0, 6.0), 0);
    assert_eq!(doc.dot(7.0, 8.0), 0);
    assert_eq!(doc.undo(), 1);
    let before = doc.state();
    let good = corners(10.0, 10.0, 110.0, 110.0);
    assert_eq!(doc.stamp(good, ep_stamp_count(), 0), INVALID);
    assert_eq!(doc.stamp(good, u32::MAX, 0), INVALID);
    assert_eq!(doc.stamp(good, 0, 0x0100_0000), INVALID);
    assert_eq!(doc.stamp(corners(10.0, 10.0, 10.0, 110.0), 0, 0), INVALID);
    assert_eq!(doc.stamp(corners(10.0, 10.0, 1300.0, 110.0), 0, 0), INVALID);
    unsafe {
        assert_eq!(ep_add_stamp(doc.0, ptr::null(), 0, 0), INVALID);
        assert_eq!(ep_add_stamp(ptr::null_mut(), good.as_ptr(), 0, 0), INVALID);
    }
    assert_eq!(doc.state(), before);
    assert_eq!(stamp_svg_bytes(ep_stamp_count()), 0);

    // A file naming a stamp this core does not know is refused, not guessed.
    assert_eq!(doc.stamp(good, 0, 0x123456), 0);
    let mut bytes = doc.project();
    let record = 56 + 8 + 44;
    put_u32(&mut bytes, record + 28, ep_stamp_count());
    assert!(Owned::try_from_project(&resealed(bytes.clone())).is_err());
    put_u32(&mut bytes, record + 28, 0);
    bytes[record + 4..record + 8].copy_from_slice(&2.0f32.to_le_bytes());
    assert!(Owned::try_from_project(&resealed(bytes.clone())).is_err());
    bytes[record + 4..record + 8].copy_from_slice(&1.0f32.to_le_bytes());
    assert!(Owned::try_from_project(&resealed(bytes)).is_ok());
}

#[test]
fn the_rainbow_is_four_bows_and_has_no_cloud_at_its_feet() {
    let rainbow = &STAMPS[23];
    assert_eq!(rainbow.key, "arcenciel");
    assert_eq!(rainbow.layers.len(), 4, "four bows, nothing else");
    let (mut top, mut bottom) = (f32::MAX, f32::MIN);
    // (outer edge, inner edge) of each bow, from the outermost inwards.
    let mut edges = Vec::new();
    for layer in rainbow.layers {
        // An open bow in its own colour. The clouds that used to sit on its
        // feet were closed, filled shapes that took the chosen colour.
        assert_eq!(layer.fill, Paint::None);
        assert!(matches!(layer.stroke, Paint::Fixed(_)));
        assert!(!layer.path.contains('Z'));
        assert_eq!(layer.path.matches('M').count(), 1);
        // The highest and lowest points of a bow are points of its path.
        let numbers: Vec<f32> = layer
            .path
            .split(' ')
            .filter_map(|token| token.parse().ok())
            .collect();
        for y in numbers.iter().skip(1).step_by(2) {
            top = top.min(y - layer.width / 2.0);
            bottom = bottom.max(y + layer.width / 2.0);
        }
        // A bow starts at its left foot, on the line of the feet: its
        // radius is the distance from there to the middle of the box.
        let radius = 50.0 - numbers[0];
        edges.push((radius + layer.width / 2.0, radius - layer.width / 2.0));
    }
    // Alone in its box, the rainbow sits in the middle of it.
    assert!((top + bottom - 100.0).abs() <= 1.0, "{top} {bottom}");
    for pair in edges.windows(2) {
        let ((outer, inner), (next_outer, _)) = (pair[0], pair[1]);
        // Painted after it, the next bow covers the inner edge of this one:
        // no hairline of the sheet between two bows.
        assert!(next_outer > inner, "{inner} {next_outer}");
        assert!(next_outer - inner <= 1.0, "{inner} {next_outer}");
        // And every bow shows the same 8 units of itself.
        assert_eq!(outer - next_outer, 8.0);
    }
    let (outer, inner) = edges[3];
    assert_eq!(outer - inner, 8.0);
    // Four colours, no two alike wherever they are in the list.
    let colours: Vec<_> = rainbow.layers.iter().map(|layer| layer.stroke).collect();
    for (index, colour) in colours.iter().enumerate() {
        assert!(!colours[..index].contains(colour), "{colour:?} twice");
    }
}
