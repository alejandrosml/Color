//! Reproducible release-mode edit/history stress test, no external dependency.
//! rustc --edition=2021 -O core/benchmarks/object_edits.rs -o /tmp/color-object-edits
//! /tmp/color-object-edits
//! Timings cover the Rust command kernel only, excluding FFI snapshots, UI
//! rendering and input latency. Very short undo/redo timings are lower-bound
//! microbenchmarks, not an application responsiveness claim. Allocation counts
//! and the no-geometry-copy memory bound are the primary regression checks.

#[path = "../src/lib.rs"]
mod core;

use std::alloc::{GlobalAlloc, Layout, System};
use std::hint::black_box;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;

struct CountingAllocator;
static ALLOCATIONS: AtomicUsize = AtomicUsize::new(0);
static BYTES_REQUESTED: AtomicUsize = AtomicUsize::new(0);

unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        ALLOCATIONS.fetch_add(1, Ordering::Relaxed);
        BYTES_REQUESTED.fetch_add(layout.size(), Ordering::Relaxed);
        unsafe { System.alloc(layout) }
    }
    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        unsafe { System.dealloc(pointer, layout) }
    }
    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        ALLOCATIONS.fetch_add(1, Ordering::Relaxed);
        BYTES_REQUESTED.fetch_add(size, Ordering::Relaxed);
        unsafe { System.realloc(pointer, layout, size) }
    }
}

#[global_allocator]
static ALLOCATOR: CountingAllocator = CountingAllocator;

fn main() {
    const POINTS: usize = 100_000;
    const MOVES: usize = 2_000;
    let points: Vec<_> = (0..POINTS)
        .map(|index| core::EpPoint {
            x: 100.0 + (index % 1_000) as f32,
            y: 100.0 + (index / 1_000) as f32,
        })
        .collect();
    let document = core::ep_document_new(1200, 800);
    assert!(!document.is_null());
    unsafe {
        assert_eq!(
            core::ep_add_stroke(document, points.as_ptr(), points.len(), 0x123456, 3.0),
            0
        );
        let original_revision = core::ep_object_revision(document, 0);
        let allocation_start = ALLOCATIONS.load(Ordering::Relaxed);
        let byte_start = BYTES_REQUESTED.load(Ordering::Relaxed);
        let begin = Instant::now();
        for index in 0..MOVES {
            let delta = if index % 2 == 0 { 0.25 } else { -0.25 };
            assert_eq!(
                black_box(core::ep_move_object(
                    black_box(document),
                    black_box(0),
                    black_box(delta),
                    black_box(delta)
                )),
                1
            );
        }
        let move_ns = begin.elapsed().as_nanos() / MOVES as u128;
        let edit_allocations = ALLOCATIONS.load(Ordering::Relaxed) - allocation_start;
        let edit_bytes = BYTES_REQUESTED.load(Ordering::Relaxed) - byte_start;
        let moved_revision = core::ep_object_revision(black_box(document), 0);
        assert_ne!(moved_revision, original_revision);
        let history_allocation_start = ALLOCATIONS.load(Ordering::Relaxed);
        let begin = Instant::now();
        for _ in 0..MOVES {
            assert_eq!(black_box(core::ep_undo(black_box(document))), 1);
        }
        let undo_ns = begin.elapsed().as_nanos() / MOVES as u128;
        assert_eq!(
            core::ep_object_revision(black_box(document), 0),
            original_revision
        );
        let begin = Instant::now();
        for _ in 0..MOVES {
            assert_eq!(black_box(core::ep_redo(black_box(document))), 1);
        }
        let redo_ns = begin.elapsed().as_nanos() / MOVES as u128;
        assert_eq!(
            core::ep_object_revision(black_box(document), 0),
            moved_revision
        );
        let history_allocations = ALLOCATIONS.load(Ordering::Relaxed) - history_allocation_start;
        assert_eq!(history_allocations, 0, "undo/redo must not allocate");
        // Moving 100000 points 2000 times must allocate only a bounded command
        // vector, not repeated copies of the 800000-byte geometry.
        assert!(
            edit_bytes < 1_000_000,
            "move history unexpectedly copied geometry"
        );
        assert_eq!(core::ep_undo_count(document), MOVES + 1);
        core::ep_document_free(document);
        println!("{{\"scope\":\"Rust command kernel only; not UI latency\",\"black_box_barriers\":true,\"points\":{POINTS},\"moves\":{MOVES},\"mean_move_ns\":{move_ns},\"mean_undo_ns\":{undo_ns},\"mean_redo_ns\":{redo_ns},\"edit_allocation_calls\":{edit_allocations},\"edit_cumulative_requested_bytes\":{edit_bytes},\"undo_redo_allocation_calls\":{history_allocations}}}");
    }
}
