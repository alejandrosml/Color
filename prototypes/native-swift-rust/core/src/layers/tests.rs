use super::*;
use crate::test_support::*;

fn add_layer(doc: &Owned) -> i32 {
    unsafe { ep_add_layer(doc.0) }
}

/// A colouring page with a drawing, written by the independent encoder:
/// layers 1 (zones, locked), 0 (active), 3 (hidden), 4 (hidden, locked),
/// 2 (lines, locked). Objects 0 and 1 are zones, 2 and 3 are drawn on layer
/// 0, 4 is a stamp on layer 3, 5 an ellipse on layer 4, 6 to 8 lines.
const PAGE: &[u8] = include_bytes!("../../test-fixtures/import-project/locked-page-v5.edupaint");
const PINNED: [usize; 6] = [0, 1, 5, 6, 7, 8];

fn page() -> Owned {
    Owned::from_project(PAGE)
}

fn ids(doc: &Owned) -> Vec<u32> {
    doc.layers().iter().map(|layer| layer.0).collect()
}

fn style(doc: &Owned, index: usize) -> EpObjectStyle {
    let mut style = EpObjectStyle {
        kind: 99,
        fill_enabled: 99,
        fill_rgb: 99,
    };
    assert_eq!(unsafe { ep_object_style(doc.0, index, &mut style) }, 0);
    style
}

#[test]
fn every_edit_of_an_object_of_a_locked_layer_is_refused_and_changes_nothing() {
    let doc = page();
    // A redo waiting survives every refusal too.
    assert_eq!(doc.dot(30.0, 30.0), 0);
    assert_eq!(doc.undo(), 1);
    let before = doc.state();
    let tokens = doc.revisions();
    let next = doc.doc().next_revision;
    let count = doc.count();
    for index in PINNED {
        let info = doc.info(index);
        let current = style(&doc, index);
        let mut delta = point(-7.0, -7.0);
        unsafe {
            assert_eq!(ep_remove_object(doc.0, index), INVALID, "remove {index}");
            for (dx, dy) in [(0.0, 0.0), (1.0, 1.0), (-1.0, 0.5)] {
                assert_eq!(ep_move_object(doc.0, index, dx, dy), INVALID);
            }
            assert_eq!(
                ep_constrain_object_movement(doc.0, index, 1.0, 1.0, &mut delta),
                INVALID
            );
            assert_eq!(delta, point(-7.0, -7.0));
            for factor in [1.0, 0.5, 2.0] {
                assert_eq!(doc.scale(index, factor, info.width), INVALID);
            }
            for to in [0, index, count - 1] {
                assert_eq!(ep_reorder_object(doc.0, index, to), INVALID, "{index}");
            }
            assert_eq!(ep_duplicate_object(doc.0, index, 0.0, 0.0), INVALID);
            assert_eq!(ep_duplicate_object(doc.0, index, 5.0, 5.0), INVALID);
            for layer in 0..5 {
                assert_eq!(ep_set_object_layer(doc.0, index, layer), INVALID);
            }
            // Its outline, and whether it is filled, stay as they are, even
            // when what is asked is what it already has.
            let (rgb, width) = (info.rgb, info.width);
            let (fill, fill_rgb) = (current.fill_enabled, current.fill_rgb);
            assert_eq!(
                ep_set_object_style(doc.0, index, rgb ^ 1, width, fill, fill_rgb),
                INVALID
            );
            assert_eq!(
                ep_set_object_style(doc.0, index, rgb, width * 2.0, fill, fill_rgb),
                INVALID
            );
            assert_eq!(ep_set_object_style(doc.0, index, rgb, width, 0, 0), INVALID);
            if fill == 0 {
                // A line of a page never gets a fill.
                assert_eq!(
                    ep_set_object_style(doc.0, index, rgb, width, 1, 0x123456),
                    INVALID
                );
            }
        }
    }
    // Nothing joins a locked layer either.
    unsafe {
        for layer in [1, 4, 2] {
            assert_eq!(ep_set_object_layer(doc.0, 2, layer), INVALID);
        }
        assert_eq!(ep_set_object_layer(doc.0, 2, 0), 0);
    }
    assert_eq!(doc.state(), before);
    assert_eq!(doc.revisions(), tokens);
    assert_eq!(doc.doc().next_revision, next);
    doc.assert_accounting();

    // A text of a locked layer keeps its characters.
    let source = Owned::new();
    assert_eq!(add_layer(&source), 1);
    let area = corners(10.0, 10.0, 110.0, 58.0);
    assert_eq!(source.text(area, 0, 40.0, "mot"), 0);
    unsafe {
        assert_eq!(ep_set_active_layer(source.0, 0), 0);
    }
    let locked = Owned::from_project(&locked_project(source.project(), &[1]));
    assert_eq!(locked.locks(), [false, true]);
    let before = locked.state();
    assert_eq!(locked.set_text(0, area, 0, 40.0, "mots"), INVALID);
    assert_eq!(locked.set_text(0, area, 0, 40.0, "mot"), INVALID);
    unsafe {
        assert_eq!(
            ep_set_object_style(locked.0, 0, 0x123456, 40.0, 0, 0),
            INVALID
        );
    }
    assert_eq!(locked.state(), before);
}

#[test]
fn the_paint_pot_recolours_a_zone_of_a_page_in_one_reversible_step() {
    let doc = page();
    let before = doc.state();
    let tokens = doc.revisions();
    unsafe {
        // The outline passed back as it is, a fill the zone already has:
        // only its colour changes.
        assert_eq!(ep_set_object_style(doc.0, 0, 0xffffff, 0.1, 1, 0xff8800), 1);
        assert_eq!(ep_set_object_style(doc.0, 0, 0xffffff, 0.1, 1, 0xff8800), 0);
        assert_eq!(ep_set_object_style(doc.0, 1, 0xffffff, 0.1, 1, 0x000000), 1);
    }
    assert_eq!(
        style(&doc, 0),
        EpObjectStyle {
            kind: KIND_CONTOUR,
            fill_enabled: 1,
            fill_rgb: 0xff8800
        }
    );
    let painted = doc.revisions();
    assert!(painted[0] > tokens[0] && painted[1] > tokens[1]);
    assert_eq!(painted[2..], tokens[2..]);
    assert_eq!(unsafe { ep_undo_count(doc.0) }, 3 + 2);
    let svg = doc.svg();
    assert!(svg.contains("Z\" fill=\"#ff8800\" stroke=\"#ffffff\" stroke-width=\"0.1\""));
    assert!(svg.contains("height=\"200\" fill=\"#000000\" stroke=\"#ffffff\""));
    let bytes = doc.project();
    assert_eq!(bytes[8], 5);
    let reopened = Owned::from_project(&bytes);
    assert_eq!(reopened.project(), bytes);
    assert_eq!(style(&reopened, 0).fill_rgb, 0xff8800);
    // A colour that is not one, or a fill taken away, is still refused.
    unsafe {
        for (fill, colour) in [(1, 0x0100_0000), (0, 0), (2, 0), (0, 0xff8800)] {
            assert_eq!(
                ep_set_object_style(doc.0, 0, 0xffffff, 0.1, fill, colour),
                INVALID
            );
        }
    }
    assert_eq!(doc.project(), bytes);
    // Undo gives the white zones back, with their former tokens; redo paints.
    assert_eq!((doc.undo(), doc.undo()), (1, 1));
    assert_eq!((doc.state().0, doc.state().1), (before.0.clone(), before.1));
    assert_eq!(doc.revisions(), tokens);
    assert_eq!((doc.redo(), doc.redo()), (1, 1));
    assert_eq!(doc.project(), bytes);
    assert_eq!(doc.revisions(), painted);
    doc.assert_accounting();
}

#[test]
fn the_active_layer_is_never_a_locked_one() {
    let doc = page();
    assert_eq!(doc.locks(), [true, false, false, true, true]);
    unsafe {
        assert_eq!(ep_layer_locked(doc.0, 5), INVALID);
        assert_eq!(ep_layer_locked(doc.0, usize::MAX), INVALID);
        assert_eq!(ep_layer_locked(ptr::null(), 0), INVALID);
        let before = doc.state();
        for id in [1, 4, 2] {
            assert_eq!(ep_set_active_layer(doc.0, id), INVALID);
        }
        assert_eq!(doc.state(), before);
        // A hidden layer may receive objects; a locked one never.
        assert_eq!(ep_set_active_layer(doc.0, 3), 0);
        assert_eq!(ep_set_active_layer(doc.0, 0), 0);
        // A new layer goes just above the active one and is not locked.
        assert_eq!(add_layer(&doc), 1);
        assert_eq!(ids(&doc), [1, 0, 5, 3, 4, 2]);
        assert_eq!(doc.locks(), [true, false, false, false, true, true]);
        assert_eq!(doc.active(), 5);
        // Removing the active layer activates the nearest one that is not
        // locked: below first...
        assert_eq!(ep_remove_layer(doc.0, 2), 1);
        assert_eq!(doc.active(), 0);
        // ... then above, when only locked layers are below.
        assert_eq!(ep_remove_layer(doc.0, 1), 1);
        assert_eq!(ids(&doc), [1, 3, 4, 2]);
        assert_eq!(doc.active(), 3);
        // The last layer that is not locked stays, with its objects.
        let before = doc.state();
        assert_eq!(ep_remove_layer(doc.0, 1), INVALID);
        assert_eq!(doc.state(), before);
        doc.assert_accounting();
        // Undo returns to the layer that was active before each command.
        assert_eq!(doc.undo(), 1);
        assert_eq!(doc.active(), 0);
        assert_eq!(doc.undo(), 1);
        assert_eq!(doc.active(), 5);
        assert_eq!(doc.undo(), 1);
        assert_eq!(doc.active(), 0);
    }
    assert_eq!(doc.project(), PAGE);
    // Should the active layer ever be missing or locked, the fallback is
    // the highest layer that is not locked.
    let document = unsafe { &mut *doc.0 };
    for wrong in [9, 2, 1] {
        document.active_layer = wrong;
        document.ensure_active_layer();
        assert_eq!(document.active_layer, 3);
    }
    document.active_layer = 0;
    document.ensure_active_layer();
    assert_eq!(document.active_layer, 0);
    doc.assert_accounting();
}

#[test]
fn locked_layers_keep_their_place_no_layer_passes_them_but_they_can_be_hidden() {
    let doc = page();
    let before = doc.state();
    let locked = [0, 3, 4];
    unsafe {
        for position in locked {
            assert_eq!(ep_remove_layer(doc.0, position), INVALID);
        }
        // Nothing moves from, to or across a locked layer: the drawing goes
        // neither under the zones nor over the lines, nor past the hidden
        // locked layer between them.
        for from in 0..5 {
            for to in 0..5 {
                if (from.min(to)..=from.max(to)).any(|position| locked.contains(&position)) {
                    assert_eq!(ep_reorder_layer(doc.0, from, to), INVALID, "{from} {to}");
                }
            }
        }
        assert_eq!(doc.state(), before);
        // Between two locked layers, the others are reordered among
        // themselves, one undoable step each.
        assert_eq!(ep_reorder_layer(doc.0, 1, 1), 0);
        assert_eq!(ep_reorder_layer(doc.0, 1, 2), 1);
        assert_eq!(ids(&doc), [1, 3, 0, 4, 2]);
        assert_eq!(doc.locks(), [true, false, false, true, true]);
        let moved = doc.project();
        assert_eq!(Owned::from_project(&moved).project(), moved);
        assert_eq!(doc.undo(), 1);
        assert_eq!(doc.project(), PAGE);
        assert_eq!(doc.redo(), 1);
        assert_eq!(doc.project(), moved);
        assert_eq!(ep_reorder_layer(doc.0, 2, 1), 1);
        assert_eq!(ids(&doc), [1, 0, 3, 4, 2]);
        assert_eq!((doc.undo(), doc.undo()), (1, 1));
        assert_eq!(doc.project(), PAGE);
        // Hiding and showing a locked layer are ordinary commands.
        assert_eq!(ep_set_layer_visible(doc.0, 0, 0), 1);
        assert!(!doc.svg().contains("calque-2"));
        assert_eq!(ep_set_layer_visible(doc.0, 3, 1), 1);
        assert!(doc.svg().contains("<g id=\"calque-5\">"));
        let shown = doc.project();
        assert_eq!(shown[8], 5);
        assert_eq!(Owned::from_project(&shown).project(), shown);
        assert_eq!((doc.undo(), doc.undo()), (1, 1));
    }
    assert_eq!(doc.project(), PAGE);
    doc.assert_accounting();
}

#[test]
fn without_locked_layers_a_layer_goes_anywhere() {
    let doc = Owned::new();
    for _ in 0..3 {
        assert_eq!(add_layer(&doc), 1);
    }
    assert_eq!(ids(&doc), [0, 1, 2, 3]);
    unsafe {
        for from in 0..4 {
            for to in 0..4 {
                let order = ids(&doc);
                let status = ep_reorder_layer(doc.0, from, to);
                assert_eq!(status, i32::from(from != to), "{from} {to}");
                if status == 1 {
                    let mut expected = order.clone();
                    let layer = expected.remove(from);
                    expected.insert(to, layer);
                    assert_eq!(ids(&doc), expected);
                    assert_eq!(doc.undo(), 1);
                }
                assert_eq!(ids(&doc), order);
            }
        }
    }
    doc.assert_accounting();
}

#[test]
fn a_new_layer_never_lands_beyond_a_locked_one() {
    let doc = page();
    unsafe {
        // Above the active layer, the drawing: under the hidden locked layer.
        assert_eq!(add_layer(&doc), 1);
        assert_eq!(ids(&doc), [1, 0, 5, 3, 4, 2]);
        // Should the active layer ever be missing or locked, no layer would
        // be added rather than one beyond a lock.
        let before = doc.state();
        for wrong in [9, 2, 4] {
            (*doc.0).active_layer = wrong;
            assert_eq!(add_layer(&doc), INVALID);
        }
        (*doc.0).active_layer = 5;
        assert_eq!(doc.state(), before);
    }
    doc.assert_accounting();
}

#[test]
fn nothing_new_ever_joins_a_locked_layer() {
    let doc = page();
    // New objects join the active layer; a copy stays beside its source.
    assert_eq!(doc.dot(20.0, 20.0), 0);
    assert_eq!(doc.extra(9).layer, 0);
    unsafe {
        assert_eq!(ep_duplicate_object(doc.0, 4, 10.0, 10.0), 1);
    }
    assert_eq!(doc.extra(10).layer, 3);
    // Should the active layer ever be a locked one, nothing would be added.
    let before = doc.state();
    unsafe {
        (*doc.0).active_layer = 1;
    }
    let area = corners(100.0, 100.0, 200.0, 150.0);
    assert_eq!(doc.dot(20.0, 20.0), INVALID);
    assert_eq!(doc.shape(2, area, 0, 2.0), INVALID);
    assert_eq!(doc.text(area, 0, 20.0, "non"), INVALID);
    assert_eq!(doc.stamp(area, 0, 0), INVALID);
    unsafe {
        (*doc.0).active_layer = 0;
    }
    assert_eq!(doc.state(), before);
    doc.assert_accounting();
}

#[test]
fn a_new_document_has_one_visible_layer_and_keeps_the_historic_format() {
    let doc = Owned::new();
    assert_eq!(doc.layers(), [(0, true, 0)]);
    assert_eq!(doc.active(), 0);
    assert_eq!(doc.dot(5.0, 6.0), 0);
    assert_eq!(doc.layers(), [(0, true, 1)]);
    assert_eq!(doc.extra(0).layer, 0);
    let bytes = doc.project();
    assert_eq!(bytes[8], 2, "a plain drawing is still a version 2 project");
    assert!(!doc.svg().contains("<g"));
    unsafe {
        assert_eq!(ep_layer_count(ptr::null()), 0);
        assert_eq!(ep_active_layer(ptr::null()), u32::MAX);
        let mut info = EpLayerInfo {
            id: 7,
            visible: 7,
            object_count: 7,
        };
        assert_eq!(ep_layer_info(doc.0, 1, &mut info), INVALID);
        assert_eq!(ep_layer_info(ptr::null(), 0, &mut info), INVALID);
        assert_eq!(ep_layer_info(doc.0, 0, ptr::null_mut()), INVALID);
        assert_eq!((info.id, info.visible, info.object_count), (7, 7, 7));
        let mut extra = EpObjectExtra {
            layer: 7,
            param: 7,
            text_bytes: 7,
        };
        assert_eq!(ep_object_extra(doc.0, 1, &mut extra), INVALID);
        assert_eq!(ep_object_extra(doc.0, 0, ptr::null_mut()), INVALID);
        assert_eq!(ep_object_extra(ptr::null(), 0, &mut extra), INVALID);
        assert_eq!(extra.layer, 7);
    }
    doc.assert_accounting();
}

#[test]
fn new_objects_join_the_active_layer_and_layers_paint_bottom_first() {
    let doc = Owned::new();
    assert_eq!(doc.dot(10.0, 10.0), 0); // index 0, layer 0
    assert_eq!(add_layer(&doc), 1);
    assert_eq!(doc.layers(), [(0, true, 1), (1, true, 0)]);
    assert_eq!(doc.active(), 1);
    assert_eq!(doc.dot(20.0, 20.0), 0); // index 1, layer 1
    unsafe {
        assert_eq!(ep_set_active_layer(doc.0, 0), 0);
        assert_eq!(ep_set_active_layer(doc.0, 2), INVALID);
        assert_eq!(ep_set_active_layer(doc.0, 256), INVALID);
        assert_eq!(ep_set_active_layer(ptr::null_mut(), 0), INVALID);
    }
    assert_eq!(doc.active(), 0);
    assert_eq!(doc.dot(30.0, 30.0), 0); // index 2, layer 0: painted below index 1
    assert_eq!(
        (0..3)
            .map(|index| doc.extra(index).layer)
            .collect::<Vec<_>>(),
        [0, 1, 0]
    );
    assert_eq!(doc.layers(), [(0, true, 2), (1, true, 1)]);
    let svg = doc.svg();
    let group = |id: u32| svg.find(&format!("<g id=\"calque-{id}\">")).unwrap();
    let at = |x: u32| svg.find(&format!("cx=\"{x}\"")).unwrap();
    assert!(group(1) < at(10) && at(10) < at(30) && at(30) < group(2) && group(2) < at(20));
    assert_eq!(svg.matches("</g>").count(), 2);

    let bytes = doc.project();
    assert_eq!(bytes[8], 4);
    let reopened = Owned::from_project(&bytes);
    assert_eq!(reopened.project(), bytes);
    assert_eq!(reopened.svg(), svg);
    assert_eq!(reopened.layers(), doc.layers());
    assert_eq!(reopened.active(), 0);
    reopened.assert_accounting();
    doc.assert_accounting();
}

#[test]
fn every_layer_command_is_undone_and_redone_to_identical_states() {
    let doc = Owned::new();
    let mut states = vec![doc.state()];
    let mut record = |doc: &Owned, status: i32| {
        assert!(status == 0 || status == 1, "{status}");
        doc.assert_accounting();
        states.push(doc.state());
    };
    record(&doc, doc.dot(10.0, 10.0));
    record(&doc, add_layer(&doc));
    record(
        &doc,
        doc.text(corners(50.0, 50.0, 250.0, 98.0), 0x123456, 40.0, "haut"),
    );
    record(
        &doc,
        doc.stamp(corners(300.0, 300.0, 400.0, 400.0), 3, 0xaa5500),
    );
    record(&doc, add_layer(&doc));
    record(&doc, doc.dot(20.0, 20.0));
    unsafe {
        record(&doc, ep_reorder_layer(doc.0, 2, 0));
        record(&doc, ep_set_layer_visible(doc.0, 1, 0));
        record(&doc, ep_set_object_layer(doc.0, 0, 1));
        record(&doc, ep_remove_layer(doc.0, 2));
        record(&doc, ep_set_layer_visible(doc.0, 1, 1));
        record(&doc, ep_move_object(doc.0, 0, 3.0, 4.0));
        record(&doc, ep_remove_layer(doc.0, 0));
    }
    assert_eq!(doc.layers().len(), 1);
    let last = states.len() - 1;
    for step in (0..last).rev() {
        assert_eq!(doc.undo(), 1);
        doc.assert_accounting();
        let (bytes, svg, undo, redo, layers, active) = doc.state();
        assert_eq!(svg, states[step].1, "step {step}");
        assert_eq!((undo, redo), (step, last - step));
        assert_eq!(layers, states[step].4, "step {step}");
        // Undo also returns to the layer that was active before each command.
        assert_eq!(active, states[step].5, "step {step}");
        assert_eq!(bytes, states[step].0, "step {step}");
    }
    assert_eq!(doc.undo(), 0);
    assert_eq!(doc.project()[8], 2, "the empty original is plain again");
    for (step, expected) in states.iter().enumerate().skip(1) {
        assert_eq!(doc.redo(), 1);
        doc.assert_accounting();
        let (bytes, svg, undo, redo, layers, active) = doc.state();
        assert_eq!((undo, redo), (step, last - step));
        // Redo also returns to the layer that was active after each command.
        assert_eq!(
            (&bytes, &svg, &layers, active),
            (&expected.0, &expected.1, &expected.4, expected.5),
            "step {step}"
        );
    }
    assert_eq!(doc.redo(), 0);
}

#[test]
fn removing_a_layer_detaches_its_objects_and_undo_restores_order_and_ownership() {
    let doc = Owned::new();
    assert_eq!(add_layer(&doc), 1);
    assert_eq!(add_layer(&doc), 1);
    // Interleave three layers so that removed objects are not contiguous.
    for index in 0..30u32 {
        unsafe {
            assert_eq!(ep_set_active_layer(doc.0, index % 3), 0);
        }
        let x = 10.0 + index as f32;
        if index % 5 == 0 {
            assert_eq!(
                doc.text(corners(x, 10.0, x + 50.0, 40.0), index, 20.0, "t"),
                0
            );
        } else {
            assert_eq!(doc.stroke(&[point(x, 5.0), point(x, 9.0)], index), 0);
        }
    }
    let identity = |doc: &Owned| -> Vec<_> {
        doc.doc()
            .strokes
            .iter()
            .map(|s| {
                (
                    s.revision,
                    s.points.as_ptr(),
                    s.text.as_ptr(),
                    s.layer,
                    s.rgb,
                )
            })
            .collect()
    };
    let before = doc.state();
    let before_identity = identity(&doc);
    let capacity = doc.doc().strokes.capacity();
    unsafe {
        assert_eq!(ep_remove_layer(doc.0, 1), 1);
    }
    assert_eq!(doc.count(), 20);
    assert_eq!(doc.layers(), [(0, true, 10), (2, true, 10)]);
    assert!(doc.doc().strokes.iter().all(|s| s.layer != 1));
    // Kept objects keep their relative order and their buffers.
    let kept: Vec<_> = before_identity
        .iter()
        .filter(|e| e.3 != 1)
        .copied()
        .collect();
    assert_eq!(identity(&doc), kept);
    doc.assert_accounting();
    assert_eq!(doc.doc().retained_objects, 30);
    let detached_capacity = match doc.doc().history.last() {
        Some(Edit::LayerPresence { detached, .. }) => {
            assert_eq!(detached.len(), 10);
            detached.capacity()
        }
        _ => panic!("layer removal must be the last command"),
    };

    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.state().0, before.0);
    assert_eq!(doc.state().1, before.1);
    assert_eq!(
        identity(&doc),
        before_identity,
        "no copy, exact former indices"
    );
    assert_eq!(doc.doc().strokes.capacity(), capacity);
    doc.assert_accounting();
    // The undone command keeps its capacity so that redo cannot allocate.
    match &doc.doc().history[doc.doc().cursor] {
        Edit::LayerPresence {
            detached, layer, ..
        } => {
            assert!(detached.is_empty() && layer.is_none());
            assert_eq!(detached.capacity(), detached_capacity);
        }
        _ => panic!("unexpected command"),
    }
    assert_eq!(doc.redo(), 1);
    assert_eq!(identity(&doc), kept);
    assert_eq!(doc.undo(), 1);
    assert_eq!(identity(&doc), before_identity);

    // A new edit discards the removal: nothing detached remains retained.
    assert_eq!(doc.dot(1.0, 1.0), 0);
    assert_eq!(doc.doc().retained_objects, 31);
    doc.assert_accounting();
}

#[test]
fn layer_limits_refusals_and_noops_preserve_everything() {
    let doc = Owned::new();
    assert_eq!(doc.dot(5.0, 6.0), 0);
    unsafe {
        assert_eq!(ep_remove_layer(doc.0, 0), INVALID, "last layer stays");
        for _ in 1..MAX_LAYERS {
            assert_eq!(add_layer(&doc), 1);
        }
        assert_eq!(ep_layer_count(doc.0), MAX_LAYERS);
        assert_eq!(doc.undo(), 1);
        let before = doc.state();
        assert_eq!(ep_remove_layer(doc.0, MAX_LAYERS), INVALID);
        assert_eq!(ep_reorder_layer(doc.0, 0, MAX_LAYERS), INVALID);
        assert_eq!(ep_reorder_layer(doc.0, MAX_LAYERS, 0), INVALID);
        assert_eq!(ep_reorder_layer(doc.0, 3, 3), 0);
        assert_eq!(ep_set_layer_visible(doc.0, 0, 1), 0);
        assert_eq!(ep_set_layer_visible(doc.0, 0, 2), INVALID);
        assert_eq!(ep_set_layer_visible(doc.0, MAX_LAYERS, 0), INVALID);
        assert_eq!(ep_set_object_layer(doc.0, 0, 0), 0);
        assert_eq!(ep_set_object_layer(doc.0, 0, 15), INVALID, "undone layer");
        assert_eq!(ep_set_object_layer(doc.0, 0, 300), INVALID);
        assert_eq!(ep_set_object_layer(doc.0, 1, 1), INVALID);
        for null in [
            ep_add_layer(ptr::null_mut()),
            ep_remove_layer(ptr::null_mut(), 0),
            ep_reorder_layer(ptr::null_mut(), 0, 1),
            ep_set_layer_visible(ptr::null_mut(), 0, 0),
            ep_set_object_layer(ptr::null_mut(), 0, 0),
        ] {
            assert_eq!(null, INVALID);
        }
        assert_eq!(doc.state(), before, "no-ops and refusals keep redo");
        assert_eq!(doc.redo(), 1);
        assert_eq!(add_layer(&doc), INVALID, "sixteen layers at most");
        assert_eq!(ep_layer_count(doc.0), MAX_LAYERS);
    }
    doc.assert_accounting();
}

#[test]
fn identifiers_are_reused_and_a_new_layer_sits_above_the_active_one() {
    let doc = Owned::new();
    assert_eq!(add_layer(&doc), 1); // [0, 1]
    assert_eq!(add_layer(&doc), 1); // [0, 1, 2]
    unsafe {
        assert_eq!(ep_set_active_layer(doc.0, 0), 0);
        assert_eq!(add_layer(&doc), 1); // [0, 3, 1, 2]
        assert_eq!(
            doc.layers().iter().map(|l| l.0).collect::<Vec<_>>(),
            [0, 3, 1, 2]
        );
        assert_eq!(doc.active(), 3);
        assert_eq!(ep_remove_layer(doc.0, 2), 1); // removes id 1
        assert_eq!(doc.active(), 3);
        assert_eq!(add_layer(&doc), 1); // smallest free identifier is 1
        assert_eq!(
            doc.layers().iter().map(|l| l.0).collect::<Vec<_>>(),
            [0, 3, 1, 2]
        );
        assert_eq!(doc.active(), 1);
        // Removing the active layer activates the one below it.
        assert_eq!(ep_remove_layer(doc.0, 2), 1);
        assert_eq!(doc.active(), 3);
        assert_eq!(ep_set_active_layer(doc.0, 0), 0);
        assert_eq!(ep_remove_layer(doc.0, 0), 1);
        assert_eq!(doc.active(), 3, "the new bottom layer");
        // Undo returns to the layer that was active before each command.
        assert_eq!(doc.undo(), 1);
        assert_eq!(doc.active(), 0);
        assert_eq!(doc.undo(), 1);
        assert_eq!(doc.active(), 1);
        assert_eq!(doc.undo(), 1);
        assert_eq!(doc.active(), 3);
    }
    doc.assert_accounting();
}

#[test]
fn hidden_layers_stay_in_the_project_but_leave_the_exported_image() {
    let doc = Owned::new();
    assert_eq!(doc.dot(10.0, 10.0), 0);
    unsafe {
        assert_eq!(ep_set_layer_visible(doc.0, 0, 0), 1);
    }
    // One hidden layer is not the historic model: version 4, empty image.
    let bytes = doc.project();
    assert_eq!(bytes[8], 4);
    let svg = doc.svg();
    assert!(!svg.contains("<circle") && !svg.contains("<g"));
    let reopened = Owned::from_project(&bytes);
    assert_eq!(reopened.layers(), [(0, false, 1)]);
    assert_eq!(reopened.count(), 1);
    assert_eq!(reopened.project(), bytes);
    unsafe {
        assert_eq!(ep_set_layer_visible(reopened.0, 0, 1), 1);
    }
    assert!(reopened.svg().contains("<circle"));
    assert_eq!(reopened.project()[8], 2);
    // Drawing on a hidden layer is the interface's choice: the core allows it.
    assert_eq!(doc.dot(20.0, 20.0), 0);
    assert_eq!(doc.layers(), [(0, false, 2)]);
    doc.assert_accounting();
}

#[test]
fn moving_an_object_to_another_layer_puts_it_in_front_there() {
    let doc = Owned::new();
    for x in [10.0, 20.0, 30.0] {
        assert_eq!(doc.dot(x, 10.0), 0);
    }
    assert_eq!(add_layer(&doc), 1);
    assert_eq!(doc.dot(40.0, 10.0), 0);
    let first = unsafe { ep_object_revision(doc.0, 0) };
    let before = doc.state();
    unsafe {
        assert_eq!(ep_set_object_layer(doc.0, 0, 1), 1);
    }
    // Former index 0 is now the last object, above the layer's older content.
    assert_eq!(doc.extra(3).layer, 1);
    assert_ne!(unsafe { ep_object_revision(doc.0, 3) }, first);
    assert_eq!(doc.layers(), [(0, true, 2), (1, true, 2)]);
    let svg = doc.svg();
    let at = |x: u32| svg.find(&format!("cx=\"{x}\"")).unwrap();
    assert!(at(20) < at(30) && at(30) < at(40) && at(40) < at(10));
    assert_eq!(doc.undo(), 1);
    assert_eq!(doc.state().0, before.0);
    assert_eq!(unsafe { ep_object_revision(doc.0, 0) }, first);
    assert_eq!(doc.redo(), 1);
    assert_eq!(doc.svg(), svg);
    // Duplicating stays on the source's layer whatever the active layer is.
    unsafe {
        assert_eq!(ep_set_active_layer(doc.0, 0), 0);
        assert_eq!(ep_duplicate_object(doc.0, 3, 5.0, 5.0), 1);
    }
    assert_eq!(doc.extra(4).layer, 1);
    doc.assert_accounting();
}

#[test]
fn layered_files_reject_inconsistent_layer_tables() {
    let doc = Owned::new();
    assert_eq!(doc.dot(10.0, 10.0), 0);
    assert_eq!(add_layer(&doc), 1);
    assert_eq!(doc.dot(20.0, 20.0), 0);
    let bytes = doc.project();
    assert_eq!(bytes.len(), 56 + 16 + 2 * 44 + 4);
    let check = |name: &str, change: &dyn Fn(&mut Vec<u8>)| {
        let mut altered = bytes.clone();
        change(&mut altered);
        assert!(
            Owned::try_from_project(&resealed(altered)).is_err(),
            "{name}"
        );
    };
    check("duplicate identifier", &|b| put_u32(b, 64, 0));
    check("identifier out of range", &|b| put_u32(b, 64, 16));
    check("unknown flag", &|b| put_u32(b, 68, 3));
    check("active layer missing", &|b| put_u32(b, 44, 5));
    check("one layer too few", &|b| put_u32(b, 36, 1));
    check("one layer too many", &|b| put_u32(b, 36, 3));
    check("object on a missing layer", &|b| put_u32(b, 72 + 24, 9));
    // Valid changes of the same fields are accepted: the checks are specific.
    let mut hidden = bytes.clone();
    put_u32(&mut hidden, 68, 0);
    put_u32(&mut hidden, 44, 0);
    let reopened = Owned::from_project(&resealed(hidden));
    assert_eq!(reopened.layers(), [(0, true, 1), (1, false, 1)]);
    assert_eq!(reopened.active(), 0);
    reopened.assert_accounting();
}

#[test]
fn history_limits_apply_to_layer_commands_atomically() {
    let doc = Owned::new();
    assert_eq!(add_layer(&doc), 1);
    unsafe {
        // Alternate visibility until the command limit is reached.
        let mut commands = 1;
        while commands < MAX_HISTORY_STEPS {
            assert_eq!(
                ep_set_layer_visible(doc.0, 1, ((commands + 1) % 2) as u32),
                1
            );
            commands += 1;
        }
        let before = doc.state();
        assert!(!doc.layers()[1].1);
        assert_eq!(ep_set_layer_visible(doc.0, 1, 1), INVALID);
        assert_eq!(add_layer(&doc), INVALID);
        assert_eq!(ep_remove_layer(doc.0, 1), INVALID);
        assert_eq!(ep_reorder_layer(doc.0, 0, 1), INVALID);
        assert_eq!(doc.state(), before);
        assert_eq!(doc.undo(), 1);
        assert_eq!(ep_reorder_layer(doc.0, 0, 1), 1);
    }
    doc.assert_accounting();
}

#[test]
fn the_older_formats_keep_no_layer_identifier_and_reopen_the_only_layer_as_zero() {
    // One plain layer left, whose identifier is 1: the drawing needs nothing
    // of version 4 and stays readable by earlier versions of the program.
    let doc = Owned::new();
    assert_eq!(unsafe { ep_add_layer(doc.0) }, 1);
    assert_eq!(doc.dot(5.0, 6.0), 0);
    assert_eq!(unsafe { ep_remove_layer(doc.0, 0) }, 1);
    assert_eq!(doc.layers(), [(1, true, 1)]);
    let written = doc.project();
    assert_eq!(written[8], 2);
    let reopened = Owned::from_project(&written);
    assert_eq!(reopened.layers(), [(0, true, 1)]);
    assert_eq!(reopened.active(), 0);
    assert_eq!(reopened.project(), written);
    assert_eq!(reopened.svg(), doc.svg());

    // As soon as the drawing needs version 4, the identifier is kept.
    assert_eq!(doc.set_paper(0x123456), 1);
    let layered = doc.project();
    assert_eq!(layered[8], 4);
    assert_eq!(Owned::from_project(&layered).layers(), [(1, true, 1)]);
}
