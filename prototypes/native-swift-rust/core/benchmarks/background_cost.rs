//! Native document-only benchmark. No decoding, file writing or Flutter timing.
//! Compile against the optimized isolated rlib; pass one canonical PNG path.
use edupaint_core::*;
use std::hint::black_box;
use std::time::Instant;

struct Owned(*mut EpDocument);
impl Drop for Owned {
    fn drop(&mut self) {
        unsafe { ep_document_free(self.0) }
    }
}
fn from_png(bytes: &[u8]) -> Owned {
    let mut status = 99;
    let doc = unsafe { ep_document_from_background_png(bytes.as_ptr(), bytes.len(), &mut status) };
    assert_eq!(status, 0);
    assert!(!doc.is_null());
    Owned(doc)
}
fn measure(mut action: impl FnMut(), iterations: usize) -> (f64, Vec<f64>) {
    action(); // one warmup, separate from samples
    let mut samples = Vec::new();
    for _ in 0..iterations {
        let start = Instant::now();
        action();
        samples.push(start.elapsed().as_secs_f64() * 1000.0);
    }
    let mut sorted = samples.clone();
    sorted.sort_by(f64::total_cmp);
    (sorted[sorted.len() / 2], samples)
}
fn main() {
    let path = std::env::args().nth(1).expect("PNG path");
    let bytes = std::fs::read(path).unwrap();
    let doc = from_png(&bytes);
    let point = EpPoint { x: 1.0, y: 1.0 };
    for _ in 0..100 {
        assert_eq!(unsafe { ep_add_stroke(doc.0, &point, 1, 0x234567, 2.0) }, 0);
    }
    let mut project = vec![0; unsafe { ep_project_size(doc.0) }];
    assert_eq!(
        unsafe { ep_copy_project(doc.0, project.as_mut_ptr(), project.len()) },
        0
    );
    let iterations = if bytes.len() > 1024 * 1024 { 3 } else { 7 };
    let construct = measure(|| drop(black_box(from_png(black_box(&bytes)))), iterations);
    let save = measure(
        || {
            assert_eq!(
                unsafe {
                    ep_copy_project(
                        black_box(doc.0),
                        black_box(project.as_mut_ptr()),
                        project.len(),
                    )
                },
                0
            );
            black_box(project.last());
        },
        iterations,
    );
    let open = measure(
        || {
            let mut status = 99;
            let loaded = Owned(unsafe {
                ep_document_from_project(black_box(project.as_ptr()), project.len(), &mut status)
            });
            assert_eq!(status, 0);
            assert!(!loaded.0.is_null());
            black_box(loaded);
        },
        iterations,
    );
    let svg = measure(
        || {
            let output = unsafe { ep_export_svg(black_box(doc.0)) };
            assert!(!output.is_null());
            black_box(unsafe { *output });
            unsafe {
                ep_string_free(output);
            }
        },
        iterations,
    );
    let start = Instant::now();
    for _ in 0..10000 {
        assert_eq!(
            unsafe { ep_add_stroke(black_box(doc.0), black_box(&point), 1, 0x345678, 3.0) },
            0
        );
        assert_eq!(unsafe { ep_undo(black_box(doc.0)) }, 1);
    }
    let edit_ns = start.elapsed().as_nanos() as f64 / 10000.0;
    println!("{{\"png_bytes\":{},\"width\":{},\"height\":{},\"objects\":100,\"project_bytes\":{},\"iterations\":{},\"warmups\":1,\"construct_png_p50_ms\":{},\"construct_samples_ms\":{:?},\"copy_project_preallocated_p50_ms\":{},\"copy_project_samples_ms\":{:?},\"open_project_p50_ms\":{},\"open_project_samples_ms\":{:?},\"svg_alloc_free_p50_ms\":{},\"svg_samples_ms\":{:?},\"add_undo_batch_mean_ns\":{}}}",
        bytes.len(), unsafe { ep_document_width(doc.0) }, unsafe { ep_document_height(doc.0) }, project.len(), iterations,
        construct.0, construct.1, save.0, save.1, open.0, open.1, svg.0, svg.1, edit_ns);
}
