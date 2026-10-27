//! Native capture/export only; excludes Flutter, codec, file I/O and rendering.
use edupaint_core::*;
use std::{hint::black_box, time::Instant};
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let png = if args[1] == "-" {
        Vec::new()
    } else {
        std::fs::read(&args[1]).unwrap()
    };
    let point_count: usize = args[2].parse().unwrap();
    let per_stroke: usize = args.get(3).map_or(100_000, |s| s.parse().unwrap());
    assert!((1..=100_000).contains(&per_stroke));
    let mut status = 99;
    let doc = if png.is_empty() {
        ep_document_new(4096, 4096)
    } else {
        unsafe { ep_document_from_background_png(png.as_ptr(), png.len(), &mut status) }
    };
    assert!(!doc.is_null());
    let mut remaining = point_count;
    while remaining != 0 {
        let count = remaining.min(per_stroke);
        let points: Vec<_> = (0..count)
            .map(|n| EpPoint {
                x: 2.0 + (n % 20) as f32,
                y: 3.0 + (n % 15) as f32,
            })
            .collect();
        assert_eq!(
            unsafe { ep_add_stroke(doc, points.as_ptr(), points.len(), 0x123456, 2.0) },
            0
        );
        remaining -= count;
    }
    let mut captures = Vec::new();
    for n in 0..8 {
        let started = Instant::now();
        let captured = unsafe { ep_export_snapshot_new(black_box(doc), &mut status) };
        let elapsed = started.elapsed().as_secs_f64() * 1000.0;
        assert_eq!(status, 0);
        assert!(!captured.is_null());
        black_box(unsafe { ep_export_snapshot_project_size(captured) });
        unsafe { ep_export_snapshot_free(captured) };
        if n != 0 {
            captures.push(elapsed);
        }
    }
    let captured = unsafe { ep_export_snapshot_new(doc, &mut status) };
    assert!(!captured.is_null());
    let size = unsafe { ep_export_snapshot_project_size(captured) };
    let mut project = vec![0; size];
    let mut project_samples = Vec::new();
    let mut svg_samples = Vec::new();
    for n in 0..4 {
        let started = Instant::now();
        assert_eq!(
            unsafe {
                ep_export_snapshot_copy_project(
                    black_box(captured),
                    black_box(project.as_mut_ptr()),
                    size,
                )
            },
            0
        );
        let elapsed = started.elapsed().as_secs_f64() * 1000.0;
        black_box(project.last());
        if n != 0 {
            project_samples.push(elapsed);
        }
        let started = Instant::now();
        let svg = unsafe { ep_export_snapshot_export_svg(black_box(captured)) };
        assert!(!svg.is_null());
        black_box(unsafe { *svg });
        let elapsed = started.elapsed().as_secs_f64() * 1000.0;
        unsafe { ep_string_free(svg) };
        if n != 0 {
            svg_samples.push(elapsed);
        }
    }
    let mut sorted = captures.clone();
    sorted.sort_by(f64::total_cmp);
    println!("{{\"png_bytes\":{},\"visible_points\":{},\"visible_objects\":{},\"project_bytes\":{},\"snapshot_create_p50_ms\":{},\"snapshot_create_samples_ms\":{:?},\"project_copy_preallocated_samples_ms\":{:?},\"svg_create_samples_ms\":{:?},\"warmups\":1}}", png.len(), point_count, unsafe { ep_stroke_count(doc) }, size, sorted[sorted.len()/2], captures, project_samples, svg_samples);
    unsafe {
        ep_document_free(doc);
        ep_export_snapshot_free(captured);
    }
}
