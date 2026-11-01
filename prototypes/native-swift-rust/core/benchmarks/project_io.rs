//! Release-mode cost of saving and opening a project, CRC32 included, and of
//! importing a large PNG background (its CRC32 is computed once on import).
//! No file is written: the project goes to and from memory.
//!
//! rustc --edition=2021 -C opt-level=3 core/benchmarks/project_io.rs -o /tmp/color-project-io
//! /tmp/color-project-io [points] [canonical.png]
//!
//! `points` defaults to 300000, drawn as strokes of 100 points; the PNG is
//! optional (benchmarks/make_large_png.py writes a 64 MiB one). Each figure is
//! the median and the minimum of repeated runs after one warm-up run: an order
//! of magnitude and a slope on this machine, not a time on a phone.

#[path = "../src/lib.rs"]
mod core;

use core::*;
use std::hint::black_box;
use std::time::Instant;

struct Owned(*mut EpDocument);
impl Drop for Owned {
    fn drop(&mut self) {
        unsafe { ep_document_free(self.0) }
    }
}

fn measure(iterations: usize, mut action: impl FnMut()) -> (f64, f64) {
    action();
    let mut samples: Vec<f64> = (0..iterations)
        .map(|_| {
            let start = Instant::now();
            action();
            start.elapsed().as_secs_f64() * 1e3
        })
        .collect();
    samples.sort_by(f64::total_cmp);
    (samples[samples.len() / 2], samples[0])
}

fn drawing(points: usize) -> Owned {
    let document = Owned(unsafe { ep_document_new(2048, 1536) });
    assert!(!document.0.is_null());
    // A fixed linear congruential sequence: the same drawing on every run.
    let mut state = 0x2545_f491_u32;
    let mut next = move |limit: f32| {
        state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        (state >> 8) as f32 / (1u32 << 24) as f32 * limit
    };
    let mut left = points;
    while left > 0 {
        let count = left.min(100);
        let stroke: Vec<EpPoint> = (0..count)
            .map(|_| EpPoint {
                x: 1.0 + next(2046.0),
                y: 1.0 + next(1534.0),
            })
            .collect();
        let status = unsafe { ep_add_stroke(document.0, stroke.as_ptr(), count, 0x33_66_99, 6.0) };
        assert_eq!(status, 0);
        left -= count;
    }
    // One moved stroke: its points are written through the transform.
    assert_eq!(unsafe { ep_move_object(document.0, 0, 1.5, -0.5) }, 1);
    document
}

fn main() {
    let mut arguments = std::env::args().skip(1);
    let points: usize = arguments
        .next()
        .map_or(300_000, |text| text.parse().expect("points"));
    let png = arguments.next();

    let document = drawing(points);
    let size = unsafe { ep_project_size(document.0) };
    let mut project = vec![0u8; size];
    let (save_p50, save_min) = measure(41, || {
        let status = unsafe { ep_copy_project(document.0, project.as_mut_ptr(), project.len()) };
        assert_eq!(black_box(status), 0);
    });
    let (open_p50, open_min) = measure(41, || {
        let mut status = 99;
        let opened = Owned(unsafe {
            ep_document_from_project(project.as_ptr(), project.len(), &mut status)
        });
        assert_eq!(status, 0);
        black_box(opened.0);
    });
    let digest = project
        .iter()
        .fold(0xcbf2_9ce4_8422_2325_u64, |hash, byte| {
            (hash ^ u64::from(*byte)).wrapping_mul(0x0100_0000_01b3)
        });
    print!(
        "{{\"points\":{points},\"project_bytes\":{size},\"project_fnv1a\":\"{digest:016x}\",\
         \"save_p50_ms\":{save_p50:.3},\"save_min_ms\":{save_min:.3},\
         \"open_p50_ms\":{open_p50:.3},\"open_min_ms\":{open_min:.3}"
    );
    if let Some(path) = png {
        let bytes = std::fs::read(path).expect("png");
        let (import_p50, import_min) = measure(9, || {
            let mut status = 99;
            let imported = Owned(unsafe {
                ep_document_from_background_png(bytes.as_ptr(), bytes.len(), &mut status)
            });
            assert_eq!(status, 0);
            black_box(imported.0);
        });
        let with_background = Owned(unsafe {
            let mut status = 99;
            ep_document_from_background_png(bytes.as_ptr(), bytes.len(), &mut status)
        });
        let size = unsafe { ep_project_size(with_background.0) };
        let mut project = vec![0u8; size];
        let (save_p50, _) = measure(9, || {
            let status = unsafe {
                ep_copy_project(with_background.0, project.as_mut_ptr(), project.len())
            };
            assert_eq!(black_box(status), 0);
        });
        let (open_p50, _) = measure(9, || {
            let mut status = 99;
            let opened = Owned(unsafe {
                ep_document_from_project(project.as_ptr(), project.len(), &mut status)
            });
            assert_eq!(status, 0);
            black_box(opened.0);
        });
        print!(
            ",\"png_bytes\":{},\"import_png_p50_ms\":{import_p50:.3},\"import_png_min_ms\":{import_min:.3},\
             \"save_with_png_p50_ms\":{save_p50:.3},\"open_with_png_p50_ms\":{open_p50:.3}",
            bytes.len()
        );
    }
    println!("}}");
}
