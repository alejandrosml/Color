//! Deterministic failure of each allocation in snapshot capture. Standalone to
//! avoid interfering with concurrent Rust unit-test allocator activity.
use edupaint_core::*;
use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering::SeqCst};
struct FaultAllocator;
static ARMED: AtomicBool = AtomicBool::new(false);
static FAIL_AT: AtomicUsize = AtomicUsize::new(usize::MAX);
static SEEN: AtomicUsize = AtomicUsize::new(0);
static LIVE_BYTES: AtomicUsize = AtomicUsize::new(0);
fn fail() -> bool {
    ARMED.load(SeqCst) && SEEN.fetch_add(1, SeqCst) == FAIL_AT.load(SeqCst)
}
unsafe impl GlobalAlloc for FaultAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if fail() {
            return std::ptr::null_mut();
        }
        let result = unsafe { System.alloc(layout) };
        if !result.is_null() {
            LIVE_BYTES.fetch_add(layout.size(), SeqCst);
        }
        result
    }
    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        LIVE_BYTES.fetch_sub(layout.size(), SeqCst);
        unsafe { System.dealloc(pointer, layout) }
    }
    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        if fail() {
            return std::ptr::null_mut();
        }
        let result = unsafe { System.realloc(pointer, layout, size) };
        if !result.is_null() {
            LIVE_BYTES.fetch_sub(layout.size(), SeqCst);
            LIVE_BYTES.fetch_add(size, SeqCst);
        }
        result
    }
}
#[global_allocator]
static ALLOCATOR: FaultAllocator = FaultAllocator;
fn main() {
    let png = include_bytes!("../test-fixtures/rgba-asymmetric.png");
    let mut status = 99;
    let doc = unsafe { ep_document_from_background_png(png.as_ptr(), png.len(), &mut status) };
    assert!(!doc.is_null());
    for n in 0..4 {
        let points = [EpPoint {
            x: n as f32,
            y: 2.0,
        }; 16];
        assert_eq!(
            unsafe { ep_add_stroke(doc, points.as_ptr(), points.len(), 0x123456, 2.0) },
            0
        );
    }
    let mut before = vec![0; unsafe { ep_project_size(doc) }];
    assert_eq!(
        unsafe { ep_copy_project(doc, before.as_mut_ptr(), before.len()) },
        0
    );
    let mut after = vec![0; before.len()];
    // Outer stroke vector, 4 independent point buffers, snapshot wrapper: six.
    for fail_at in 0..=6 {
        let baseline = LIVE_BYTES.load(SeqCst);
        status = 99;
        SEEN.store(0, SeqCst);
        FAIL_AT.store(fail_at, SeqCst);
        ARMED.store(true, SeqCst);
        let snapshot = unsafe { ep_export_snapshot_new(doc, &mut status) };
        ARMED.store(false, SeqCst);
        if fail_at < 6 {
            assert!(snapshot.is_null());
            assert_eq!(status, -2);
        } else {
            assert!(!snapshot.is_null());
            assert_eq!(status, 0);
            assert_eq!(
                SEEN.load(SeqCst),
                6,
                "no background control/buffer allocation in capture"
            );
            unsafe { ep_export_snapshot_free(snapshot) };
        }
        assert_eq!(
            LIVE_BYTES.load(SeqCst),
            baseline,
            "capture leak on allocation failure/success"
        );
        assert_eq!(
            unsafe { ep_copy_project(doc, after.as_mut_ptr(), after.len()) },
            0
        );
        assert_eq!(before, after);
        assert_eq!(unsafe { ep_undo_count(doc) }, 4);
    }
    unsafe { ep_document_free(doc) };
    println!("All six snapshot allocation failures return -2, leak no buffers and preserve document; success uses six allocations with no PNG copy/control allocation.");
}
