use super::*;
use std::ffi::CStr;
use std::sync::Barrier;

const PNG: &[u8] = include_bytes!("../../test-fixtures/rgba-asymmetric.png");

struct OwnedDocument(*mut EpDocument);
impl Drop for OwnedDocument {
    fn drop(&mut self) {
        unsafe { ep_document_free(self.0) }
    }
}
fn document(background: bool) -> OwnedDocument {
    let mut status = 99;
    let pointer = if background {
        unsafe { ep_document_from_background_png(PNG.as_ptr(), PNG.len(), &mut status) }
    } else {
        status = 0;
        ep_document_new(32, 24)
    };
    assert_eq!(status, 0);
    assert!(!pointer.is_null());
    OwnedDocument(pointer)
}
fn snapshot(document: &OwnedDocument) -> Box<EpExportSnapshot> {
    let mut status = 99;
    let pointer = unsafe { ep_export_snapshot_new(document.0, &mut status) };
    assert_eq!(status, 0);
    assert!(!pointer.is_null());
    unsafe { Box::from_raw(pointer) }
}
fn snapshot_project(snapshot: &EpExportSnapshot) -> Vec<u8> {
    let mut bytes = vec![0; unsafe { ep_export_snapshot_project_size(snapshot) }];
    assert_eq!(
        unsafe { ep_export_snapshot_copy_project(snapshot, bytes.as_mut_ptr(), bytes.len()) },
        0
    );
    bytes
}
fn document_project(document: &OwnedDocument) -> Vec<u8> {
    let mut bytes = vec![0; unsafe { ep_project_size(document.0) }];
    assert_eq!(
        unsafe { ep_copy_project(document.0, bytes.as_mut_ptr(), bytes.len()) },
        0
    );
    bytes
}
fn svg_string(pointer: *mut c_char) -> String {
    assert!(!pointer.is_null());
    let text = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .unwrap()
        .to_owned();
    unsafe { ep_string_free(pointer) };
    text
}
fn populate(document: &OwnedDocument) {
    unsafe {
        let points = [EpPoint { x: 2.0, y: 3.0 }, EpPoint { x: 12.0, y: 14.0 }];
        assert_eq!(
            ep_add_stroke(document.0, points.as_ptr(), 2, 0x123456, 2.0),
            0
        );
        for kind in 1..=3 {
            let style = EpObjectStyle {
                kind,
                fill_enabled: u32::from(kind > 1),
                fill_rgb: if kind > 1 { 0xabcdef } else { 0 },
            };
            assert_eq!(
                ep_add_shape(document.0, points.as_ptr(), &style, 0x345678, 3.0),
                0
            );
        }
        assert_eq!(ep_move_object(document.0, 1, 0.1, 0.3), 1);
        assert_eq!(ep_remove_object(document.0, 0), 1);
        assert_eq!(ep_duplicate_object(document.0, 2, 1.1, 0.7), 1);
        assert_eq!(ep_undo(document.0), 1); // detached redo content must not be copied
    }
}

#[test]
fn exact_exports_survive_source_mutation_and_destruction_with_or_without_png() {
    for background in [false, true] {
        let doc = document(background);
        populate(&doc);
        let project = document_project(&doc);
        let svg = svg_string(unsafe { ep_export_svg(doc.0) });
        let captured = snapshot(&doc);
        assert_eq!(snapshot_project(&captured), project);
        assert_eq!(
            svg_string(unsafe { ep_export_snapshot_export_svg(&*captured) }),
            svg
        );
        assert!(captured.drawing.history.is_empty());
        assert_eq!(captured.drawing.history.capacity(), 0);
        assert_eq!(captured.drawing.cursor, 0);
        assert_eq!(captured.drawing.active_points, 6);
        unsafe {
            let source = &*doc.0;
            for (a, b) in source.strokes.iter().zip(&captured.drawing.strokes) {
                assert_ne!(a.points.as_ptr(), b.points.as_ptr());
                assert_eq!(a.points, b.points);
                assert_eq!(a.translation, b.translation);
            }
            assert_eq!(ep_redo(doc.0), 1);
            assert_eq!(ep_move_object(doc.0, 0, 1.0, 1.0), 1);
            assert_eq!(ep_set_object_style(doc.0, 1, 0x987654, 5.0, 0, 0), 1);
            assert_eq!(ep_remove_object(doc.0, 2), 1);
        }
        assert_ne!(document_project(&doc), project);
        drop(doc);
        assert_eq!(snapshot_project(&captured), project);
        assert_eq!(
            svg_string(unsafe { ep_export_snapshot_export_svg(&*captured) }),
            svg
        );
    }
}

#[test]
fn shared_background_keeps_exact_allocation_alive_until_last_snapshot_drops() {
    let doc = document(true);
    let source = unsafe { (&*doc.0).background.as_ref().unwrap() };
    let weak = Arc::downgrade(source);
    let bytes_pointer = source.bytes.as_ptr();
    let first = snapshot(&doc);
    let second = snapshot(&doc);
    for captured in [&first, &second] {
        let shared = captured.drawing.background.as_ref().unwrap();
        assert!(Arc::ptr_eq(source, shared));
        assert_eq!(shared.bytes.as_ptr(), bytes_pointer);
        assert_eq!(Arc::strong_count(shared), 3);
    }
    drop(doc);
    assert_eq!(weak.strong_count(), 2);
    assert_eq!(snapshot_project(&first), snapshot_project(&second));
    drop(first);
    assert_eq!(weak.strong_count(), 1);
    drop(second);
    assert_eq!(weak.strong_count(), 0);
    assert!(weak.upgrade().is_none());
}

#[test]
fn snapshot_errors_do_not_write_buffers_or_change_source() {
    unsafe {
        let mut status = 99;
        assert!(ep_export_snapshot_new(ptr::null(), &mut status).is_null());
        assert_eq!(status, INVALID);
        assert!(ep_export_snapshot_new(ptr::null(), ptr::null_mut()).is_null());
        ep_export_snapshot_free(ptr::null_mut());
        assert_eq!(ep_export_snapshot_project_size(ptr::null()), 0);
        assert!(ep_export_snapshot_export_svg(ptr::null()).is_null());
        let doc = document(true);
        populate(&doc);
        let before = document_project(&doc);
        let captured = ep_export_snapshot_new(doc.0, ptr::null_mut());
        assert!(!captured.is_null());
        let mut bytes = vec![0x5a; before.len() + 17];
        assert_eq!(
            ep_export_snapshot_copy_project(ptr::null(), bytes.as_mut_ptr(), bytes.len()),
            INVALID
        );
        assert_eq!(
            ep_export_snapshot_copy_project(captured, ptr::null_mut(), bytes.len()),
            INVALID
        );
        assert_eq!(
            ep_export_snapshot_copy_project(captured, bytes.as_mut_ptr(), before.len() - 1),
            INVALID
        );
        assert!(bytes.iter().all(|&b| b == 0x5a));
        assert_eq!(
            ep_export_snapshot_copy_project(captured, bytes.as_mut_ptr(), bytes.len()),
            0
        );
        assert_eq!(&bytes[..before.len()], before);
        assert!(bytes[before.len()..].iter().all(|&b| b == 0x5a));
        assert_eq!(document_project(&doc), before);
        assert!(ep_redo_count(doc.0) > 0);
        ep_export_snapshot_free(captured);
    }
}

#[test]
fn two_reader_threads_export_while_original_is_edited_then_freed() {
    fn send_sync<T: Send + Sync>() {}
    send_sync::<EpExportSnapshot>();
    let doc = document(true);
    populate(&doc);
    let captured = snapshot(&doc);
    let project = snapshot_project(&captured);
    let svg = svg_string(unsafe { ep_export_snapshot_export_svg(&*captured) });
    let start = Barrier::new(3);
    let source_freed = Barrier::new(3);
    std::thread::scope(|scope| {
        for _ in 0..2 {
            let captured = &*captured;
            let project = &project;
            let svg = &svg;
            let start = &start;
            let source_freed = &source_freed;
            scope.spawn(move || {
                start.wait();
                for _ in 0..100 {
                    assert_eq!(&snapshot_project(captured), project);
                    assert_eq!(
                        &svg_string(unsafe { ep_export_snapshot_export_svg(captured) }),
                        svg
                    );
                }
                source_freed.wait();
                assert_eq!(&snapshot_project(captured), project);
                assert_eq!(
                    &svg_string(unsafe { ep_export_snapshot_export_svg(captured) }),
                    svg
                );
            });
        }
        start.wait();
        for _ in 0..100 {
            unsafe {
                assert_eq!(ep_move_object(doc.0, 0, 0.1, 0.1), 1);
                assert_eq!(ep_undo(doc.0), 1);
                assert_eq!(ep_set_object_style(doc.0, 1, 0x556677, 4.0, 0, 0), 1);
                assert_eq!(ep_undo(doc.0), 1);
            }
        }
        drop(doc);
        source_freed.wait();
    });
}

#[test]
fn snapshot_at_vector_limits_excludes_large_detached_history() {
    let doc = document(false);
    let points = vec![EpPoint { x: 2.0, y: 3.0 }; MAX_STROKE_POINTS];
    for _ in 0..10 {
        assert_eq!(
            unsafe { ep_add_stroke(doc.0, points.as_ptr(), points.len(), 0, 1.0) },
            0
        );
    }
    let captured = snapshot(&doc);
    assert_eq!(captured.drawing.active_points, MAX_TOTAL_POINTS);
    assert_eq!(snapshot_project(&captured), document_project(&doc));
    drop(captured);
    for _ in 0..10 {
        assert_eq!(unsafe { ep_remove_object(doc.0, 0) }, 1);
    }
    let empty = snapshot(&doc);
    assert!(empty.drawing.strokes.is_empty());
    assert_eq!(empty.drawing.active_points, 0);
    assert_eq!(empty.drawing.retained_points, 0);
    assert_eq!(empty.drawing.history.capacity(), 0);
    assert_eq!(snapshot_project(&empty).len(), PROJECT_MIN_BYTES);
}

#[test]
fn snapshot_at_object_limit_preserves_all_visible_order_and_revision_tokens() {
    let doc = document(false);
    let point = EpPoint { x: 2.0, y: 3.0 };
    for index in 0..MAX_STROKES {
        assert_eq!(
            unsafe { ep_add_stroke(doc.0, &point, 1, index as u32, 1.0) },
            0
        );
    }
    let captured = snapshot(&doc);
    assert_eq!(captured.drawing.strokes.len(), MAX_STROKES);
    assert_eq!(captured.drawing.active_points, MAX_STROKES);
    assert_eq!(snapshot_project(&captured), document_project(&doc));
    for (index, stroke) in captured.drawing.strokes.iter().enumerate() {
        assert_eq!(stroke.rgb, index as u32);
        assert_eq!(stroke.revision, unsafe { ep_object_revision(doc.0, index) });
    }
}
