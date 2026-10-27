//! Deterministic differential validation against a deliberately simple model.
//! The model snapshots whole states; production uses ownership/inverse commands.
//! Coordinates use exact quarter-units, isolating history/order/cache correctness
//! from the separately unit-tested f32 rounding/translation contract.
//! rustc --edition=2021 -O core/benchmarks/differential_edits.rs -o /tmp/color-differential
//! /tmp/color-differential

#[path = "../src/lib.rs"]
mod core;

use std::collections::{HashMap, HashSet};
use std::ffi::CStr;
use std::fmt::Write;

const WIDTH: u32 = 1200;
const HEIGHT: u32 = 800;
const STEPS: usize = 6_000;
const SEEDS: [u64; 4] = [0x12345678, 0xc0102026, 0xdeadbeef01, 0xf00d098765];

#[derive(Clone, Debug, PartialEq)]
struct Object {
    state: u64,
    points: Vec<(f32, f32)>,
    kind: u32,
    rgb: u32,
    width: f32,
    fill: Option<u32>,
}

struct Model {
    // Full immutable snapshots make this structurally independent of the core.
    states: Vec<Vec<Object>>,
    cursor: usize,
    next_state: u64,
}

impl Model {
    fn new() -> Self {
        Self {
            states: vec![vec![]],
            cursor: 0,
            next_state: 1,
        }
    }
    fn objects(&self) -> &[Object] {
        &self.states[self.cursor]
    }
    fn fresh(&mut self) -> u64 {
        let result = self.next_state;
        self.next_state += 1;
        result
    }
    fn commit(&mut self, objects: Vec<Object>, counters: &mut Counters) {
        if self.cursor + 1 < self.states.len() {
            counters.branches += 1;
        }
        self.states.truncate(self.cursor + 1);
        self.states.push(objects);
        self.cursor += 1;
    }
    fn reload(&mut self) {
        let objects = self.objects().to_vec();
        self.states = (0..=objects.len())
            .map(|end| objects[..end].to_vec())
            .collect();
        self.cursor = objects.len();
    }
}

struct Generator(u64);
impl Generator {
    fn draw(&mut self, bound: usize) -> usize {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        (self.0 % bound as u64) as usize
    }
    fn color(&mut self) -> u32 {
        self.draw(0x1000000) as u32
    }
    fn delta(&mut self) -> f32 {
        (self.draw(161) as f32 - 80.0) / 4.0
    }
}

#[derive(Default)]
struct Counters {
    operations: usize,
    adds: usize,
    moves: usize,
    styles: usize,
    duplicates: usize,
    deletes: usize,
    undos: usize,
    redos: usize,
    noops: usize,
    invalid: usize,
    branches: usize,
    reloads: usize,
    checks: usize,
    undo_redo_sweeps: usize,
}

struct Document(*mut core::EpDocument);
impl Drop for Document {
    fn drop(&mut self) {
        unsafe { core::ep_document_free(self.0) };
    }
}
impl Document {
    fn new() -> Self {
        let pointer = core::ep_document_new(WIDTH, HEIGHT);
        assert!(!pointer.is_null());
        Self(pointer)
    }
    fn bytes(&self) -> Vec<u8> {
        unsafe {
            let mut bytes = vec![0; core::ep_project_size(self.0)];
            assert_eq!(
                core::ep_copy_project(self.0, bytes.as_mut_ptr(), bytes.len()),
                0
            );
            bytes
        }
    }
    fn svg(&self) -> String {
        unsafe {
            let text = core::ep_export_svg(self.0);
            assert!(!text.is_null());
            let svg = CStr::from_ptr(text).to_str().unwrap().to_owned();
            core::ep_string_free(text);
            svg
        }
    }
    fn reload(&mut self) {
        let bytes = self.bytes();
        let mut status = 99;
        let candidate =
            unsafe { core::ep_document_from_project(bytes.as_ptr(), bytes.len(), &mut status) };
        assert_eq!(status, 0);
        assert!(!candidate.is_null());
        unsafe { core::ep_document_free(self.0) };
        self.0 = candidate;
    }
}

// Slow bitwise CRC is independent of production's slicing-by-eight algorithm.
fn crc32(bytes: &[u8]) -> u32 {
    let mut crc = 0xffff_ffff;
    for byte in bytes {
        crc ^= u32::from(*byte);
        for _ in 0..8 {
            crc = if crc & 1 == 0 {
                crc >> 1
            } else {
                (crc >> 1) ^ 0xedb8_8320
            };
        }
    }
    crc ^ 0xffff_ffff
}

fn reference_project(objects: &[Object]) -> Vec<u8> {
    let points: usize = objects.iter().map(|object| object.points.len()).sum();
    let mut bytes = b"EDUPAINT\x02\x00\x00\x00".to_vec();
    for number in [
        36 + objects.len() as u32 * 24 + points as u32 * 8,
        WIDTH,
        HEIGHT,
        objects.len() as u32,
        points as u32,
    ] {
        bytes.extend_from_slice(&number.to_le_bytes());
    }
    for object in objects {
        for number in [
            object.rgb,
            object.width.to_bits(),
            object.points.len() as u32,
            object.kind,
            u32::from(object.fill.is_some()),
            object.fill.unwrap_or(0),
        ] {
            bytes.extend_from_slice(&number.to_le_bytes());
        }
        for (x, y) in &object.points {
            bytes.extend_from_slice(&x.to_bits().to_le_bytes());
            bytes.extend_from_slice(&y.to_bits().to_le_bytes());
        }
    }
    bytes.extend_from_slice(&crc32(&bytes).to_le_bytes());
    bytes
}

fn reference_svg(objects: &[Object]) -> String {
    let mut svg = format!("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 {WIDTH} {HEIGHT}\" width=\"{WIDTH}\" height=\"{HEIGHT}\">\n<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n");
    for object in objects {
        let (x, y) = object.points[0];
        if object.kind == 0 && object.points.len() == 1 {
            writeln!(
                svg,
                "<circle cx=\"{x}\" cy=\"{y}\" r=\"{}\" fill=\"#{:06x}\"/>",
                object.width / 2.0,
                object.rgb
            )
            .unwrap();
            continue;
        }
        if object.kind == 0 {
            svg.push_str("<path d=\"");
            for (index, (x, y)) in object.points.iter().enumerate() {
                write!(svg, "{}{x} {y} ", if index == 0 { 'M' } else { 'L' }).unwrap();
            }
            svg.push('"');
        } else {
            let (x2, y2) = object.points[1];
            let left = f64::from(x.min(x2));
            let top = f64::from(y.min(y2));
            let width = f64::from(x.max(x2)) - left;
            let height = f64::from(y.max(y2)) - top;
            match object.kind {
                1 => write!(svg, "<line x1=\"{x}\" y1=\"{y}\" x2=\"{x2}\" y2=\"{y2}\"").unwrap(),
                2 => write!(
                    svg,
                    "<rect x=\"{left}\" y=\"{top}\" width=\"{width}\" height=\"{height}\""
                )
                .unwrap(),
                3 => write!(
                    svg,
                    "<ellipse cx=\"{}\" cy=\"{}\" rx=\"{}\" ry=\"{}\"",
                    left + width / 2.0,
                    top + height / 2.0,
                    width / 2.0,
                    height / 2.0
                )
                .unwrap(),
                _ => unreachable!(),
            }
        }
        match object.fill {
            Some(fill) => write!(svg, " fill=\"#{fill:06x}\"").unwrap(),
            None => svg.push_str(" fill=\"none\""),
        }
        writeln!(svg, " stroke=\"#{:06x}\" stroke-width=\"{}\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>", object.rgb, object.width).unwrap();
    }
    svg.push_str("</svg>\n");
    svg
}

#[derive(Default)]
struct CacheAudit {
    // Both directions enforce a bijection, including retired redo branches.
    state_to_token: HashMap<u64, u64>,
    token_to_state: HashMap<u64, Object>,
}

fn verify(doc: &Document, model: &Model, cache: &mut CacheAudit, counters: &mut Counters) {
    let objects = model.objects();
    unsafe {
        assert_eq!(core::ep_stroke_count(doc.0), objects.len());
        assert_eq!(core::ep_undo_count(doc.0), model.cursor);
        assert_eq!(
            core::ep_redo_count(doc.0),
            model.states.len() - model.cursor - 1
        );
        assert_eq!(core::ep_object_revision(doc.0, objects.len()), 0);
        let mut visible_tokens = HashSet::new();
        for (index, object) in objects.iter().enumerate() {
            let token = core::ep_object_revision(doc.0, index);
            assert_ne!(token, 0);
            assert!(visible_tokens.insert(token));
            if let Some(expected) = cache.state_to_token.get(&object.state) {
                assert_eq!(*expected, token);
            } else {
                cache.state_to_token.insert(object.state, token);
            }
            if let Some(expected) = cache.token_to_state.get(&token) {
                assert_eq!(expected, object);
            } else {
                cache.token_to_state.insert(token, object.clone());
            }
            let mut info = core::EpStrokeInfo {
                rgb: 0,
                width: 0.0,
                point_count: 0,
            };
            let mut style = core::EpObjectStyle {
                kind: 99,
                fill_enabled: 99,
                fill_rgb: 99,
            };
            assert_eq!(core::ep_stroke_info(doc.0, index, &mut info), 0);
            assert_eq!(core::ep_object_style(doc.0, index, &mut style), 0);
            assert_eq!(
                (info.rgb, info.width, info.point_count),
                (object.rgb, object.width, object.points.len())
            );
            assert_eq!(
                (style.kind, style.fill_enabled, style.fill_rgb),
                (
                    object.kind,
                    u32::from(object.fill.is_some()),
                    object.fill.unwrap_or(0)
                )
            );
            let mut points = vec![core::EpPoint { x: -1.0, y: -1.0 }; object.points.len()];
            assert_eq!(
                core::ep_copy_points(doc.0, index, points.as_mut_ptr(), points.len()),
                points.len()
            );
            for (actual, expected) in points.iter().zip(&object.points) {
                assert_eq!(
                    (actual.x.to_bits(), actual.y.to_bits()),
                    (expected.0.to_bits(), expected.1.to_bits())
                );
            }
        }
    }
    assert_eq!(doc.bytes(), reference_project(objects));
    assert_eq!(doc.svg(), reference_svg(objects));
    counters.checks += 1;
}

fn accepted(status: i32, expected: i32, counters: &mut Counters) {
    assert_eq!(status, expected);
    if expected < 0 {
        counters.invalid += 1;
    } else if expected == 0 {
        counters.noops += 1;
    }
}

fn run_seed(seed: u64, counters: &mut Counters) {
    let mut doc = Document::new();
    let mut model = Model::new();
    let mut random = Generator(seed);
    let mut cache = CacheAudit::default();
    verify(&doc, &model, &mut cache, counters);
    for step in 0..STEPS {
        let count = model.objects().len();
        let mut action = random.draw(14);
        if count == 0 && action < 7 {
            action = 0;
        }
        if count >= 32 && (action == 0 || action == 1 || action == 4) {
            action = 5;
        }
        let index = random.draw(count + 2);
        let next = model.objects().to_vec();
        unsafe {
            match action {
                0 | 1 => {
                    let kind = if action == 0 {
                        0
                    } else {
                        1 + random.draw(3) as u32
                    };
                    let x = 100.0 + random.draw(3600) as f32 / 4.0;
                    let y = 100.0 + random.draw(2000) as f32 / 4.0;
                    let points = if kind == 0 {
                        (0..1 + random.draw(5))
                            .map(|i| (x + i as f32 * 3.25, y + i as f32 * 2.75))
                            .collect()
                    } else {
                        vec![(x, y), (x + 20.25, y + 10.75)]
                    };
                    let object = Object {
                        state: model.fresh(),
                        points,
                        kind,
                        rgb: random.color(),
                        width: 0.25 + random.draw(100) as f32 / 4.0,
                        fill: if kind >= 2 && random.draw(2) == 1 {
                            Some(random.color())
                        } else {
                            None
                        },
                    };
                    let points: Vec<_> = object
                        .points
                        .iter()
                        .map(|(x, y)| core::EpPoint { x: *x, y: *y })
                        .collect();
                    let status = if kind == 0 {
                        core::ep_add_stroke(
                            doc.0,
                            points.as_ptr(),
                            points.len(),
                            object.rgb,
                            object.width,
                        )
                    } else {
                        core::ep_add_shape(
                            doc.0,
                            points.as_ptr(),
                            &core::EpObjectStyle {
                                kind,
                                fill_enabled: u32::from(object.fill.is_some()),
                                fill_rgb: object.fill.unwrap_or(0),
                            },
                            object.rgb,
                            object.width,
                        )
                    };
                    assert_eq!(status, 0);
                    let mut next = next;
                    next.push(object);
                    model.commit(next, counters);
                    counters.adds += 1;
                }
                2 | 4 | 10 => {
                    let dx = if action == 10 || random.draw(5) == 0 {
                        0.0
                    } else {
                        random.delta()
                    };
                    let dy = if action == 10 || random.draw(5) == 0 {
                        0.0
                    } else {
                        random.delta()
                    };
                    let valid = next.get(index).is_some_and(|object| {
                        object.points.iter().all(|(x, y)| {
                            (0.0..=WIDTH as f32).contains(&(x + dx))
                                && (0.0..=HEIGHT as f32).contains(&(y + dy))
                        })
                    });
                    let expected = if !valid {
                        -1
                    } else if action != 4 && dx == 0.0 && dy == 0.0 {
                        0
                    } else {
                        1
                    };
                    let status = if action == 4 {
                        core::ep_duplicate_object(doc.0, index, dx, dy)
                    } else {
                        core::ep_move_object(doc.0, index, dx, dy)
                    };
                    accepted(status, expected, counters);
                    if expected == 1 {
                        let mut next = next;
                        let mut object = next[index].clone();
                        object.state = model.fresh();
                        for (x, y) in &mut object.points {
                            *x += dx;
                            *y += dy;
                        }
                        if action == 4 {
                            next.push(object);
                            counters.duplicates += 1;
                        } else {
                            next[index] = object;
                            counters.moves += 1;
                        }
                        model.commit(next, counters);
                    }
                }
                3 | 11 | 12 => {
                    let original = next.get(index);
                    let same = action == 11;
                    let rgb = if action == 12 {
                        0x1000000
                    } else if same {
                        original.map_or(0, |o| o.rgb)
                    } else {
                        random.color()
                    };
                    let width = if same {
                        original.map_or(1.0, |o| o.width)
                    } else {
                        0.25 + random.draw(100) as f32 / 4.0
                    };
                    let fill = if same {
                        original.and_then(|o| o.fill)
                    } else if original.is_some_and(|o| o.kind >= 2) && random.draw(2) == 1 {
                        Some(random.color())
                    } else {
                        None
                    };
                    let expected = if original.is_none() || action == 12 {
                        -1
                    } else if original
                        .is_some_and(|o| o.rgb == rgb && o.width == width && o.fill == fill)
                    {
                        0
                    } else {
                        1
                    };
                    accepted(
                        core::ep_set_object_style(
                            doc.0,
                            index,
                            rgb,
                            width,
                            u32::from(fill.is_some()),
                            fill.unwrap_or(0),
                        ),
                        expected,
                        counters,
                    );
                    if expected == 1 {
                        let mut next = next;
                        let object = &mut next[index];
                        object.rgb = rgb;
                        object.width = width;
                        object.fill = fill;
                        object.state = model.fresh();
                        model.commit(next, counters);
                        counters.styles += 1;
                    }
                }
                5 => {
                    let index = if count >= 32 {
                        random.draw(count)
                    } else {
                        index
                    };
                    let expected = if index < count { 1 } else { -1 };
                    accepted(core::ep_remove_object(doc.0, index), expected, counters);
                    if expected == 1 {
                        let mut next = next;
                        next.remove(index);
                        model.commit(next, counters);
                        counters.deletes += 1;
                    }
                }
                6 | 8 | 13 => {
                    let expected = if model.cursor > 0 { 1 } else { 0 };
                    accepted(core::ep_undo(doc.0), expected, counters);
                    if expected == 1 {
                        model.cursor -= 1;
                        counters.undos += 1;
                    }
                }
                7 | 9 => {
                    let expected = if model.cursor + 1 < model.states.len() {
                        1
                    } else {
                        0
                    };
                    accepted(core::ep_redo(doc.0), expected, counters);
                    if expected == 1 {
                        model.cursor += 1;
                        counters.redos += 1;
                    }
                }
                _ => unreachable!(),
            }
        }
        counters.operations += 1;
        verify(&doc, &model, &mut cache, counters);
        if step == 1999 || step == 3999 {
            doc.reload();
            model.reload();
            cache = CacheAudit::default();
            counters.reloads += 1;
            verify(&doc, &model, &mut cache, counters);
        }
    }
    // Check every reachable state in both directions, including states that
    // contain objects absent from the final visible list.
    unsafe {
        while model.cursor > 0 {
            assert_eq!(core::ep_undo(doc.0), 1);
            model.cursor -= 1;
            verify(&doc, &model, &mut cache, counters);
            counters.undo_redo_sweeps += 1;
        }
        assert_eq!(core::ep_undo(doc.0), 0);
        while model.cursor + 1 < model.states.len() {
            assert_eq!(core::ep_redo(doc.0), 1);
            model.cursor += 1;
            verify(&doc, &model, &mut cache, counters);
            counters.undo_redo_sweeps += 1;
        }
        assert_eq!(core::ep_redo(doc.0), 0);
    }
}

// Separate floating-point corpus: unlike the quarter-unit differential model,
// this tracks immutable f32 base points plus exact f64 displacement sums. It
// checks the UI helper's contract and every resulting visible f32 coordinate,
// including repeated clipping at all four sides and undo/redo of duplicates.
fn run_nonquarter_constraints() -> usize {
    let mut checks = 0;
    for seed in SEEDS {
        let doc = Document::new();
        let mut random = Generator(seed);
        let base = [(90.1f32, 30.1f32), (100.1f32, 40.1f32)];
        let points = base.map(|(x, y)| core::EpPoint { x, y });
        let mut translation = [0.0f64; 2];
        unsafe {
            assert_eq!(
                core::ep_add_shape(
                    doc.0,
                    points.as_ptr(),
                    &core::EpObjectStyle {
                        kind: 3,
                        fill_enabled: 1,
                        fill_rgb: 0xffff00
                    },
                    0,
                    1.0
                ),
                0
            );
            for step in 0..2_000 {
                let request = match step % 8 {
                    0 => [10_000.0, 0.0],
                    1 => [0.0, 10_000.0],
                    2 => [-10_000.0, 0.0],
                    3 => [0.0, -10_000.0],
                    _ => [
                        (random.draw(3_000_000) as f32 / 317.39) - 4_500.0,
                        (random.draw(3_000_000) as f32 / 413.71) - 3_500.0,
                    ],
                };
                let before = doc.bytes();
                let before_token = core::ep_object_revision(doc.0, 0);
                let before_undo = core::ep_undo_count(doc.0);
                let before_redo = core::ep_redo_count(doc.0);
                let mut delta = core::EpPoint {
                    x: f32::NAN,
                    y: f32::NAN,
                };
                assert_eq!(
                    core::ep_constrain_object_movement(
                        doc.0, 0, request[0], request[1], &mut delta
                    ),
                    0,
                    "seed={seed}, step={step}, translation={translation:?}, request={request:?}"
                );
                assert_eq!(doc.bytes(), before);
                assert_eq!(core::ep_object_revision(doc.0, 0), before_token);
                assert_eq!(core::ep_undo_count(doc.0), before_undo);
                assert_eq!(core::ep_redo_count(doc.0), before_redo);
                let adjusted = [delta.x, delta.y];
                let next = [
                    translation[0] + f64::from(delta.x),
                    translation[1] + f64::from(delta.y),
                ];
                let expected = base.map(|(x, y)| {
                    (
                        (f64::from(x) + next[0]) as f32,
                        (f64::from(y) + next[1]) as f32,
                    )
                });
                for axis in 0..2 {
                    assert!(
                        adjusted[axis].is_finite() && adjusted[axis].abs() <= request[axis].abs()
                    );
                    assert!(
                        adjusted[axis] == 0.0
                            || adjusted[axis].is_sign_positive()
                                == request[axis].is_sign_positive()
                    );
                }
                for (x, y) in expected {
                    assert!(
                        (0.0..=WIDTH as f32).contains(&x) && (0.0..=HEIGHT as f32).contains(&y)
                    );
                }
                let duplicate = step % 7 == 0;
                let status = if duplicate {
                    core::ep_duplicate_object(doc.0, 0, delta.x, delta.y)
                } else {
                    core::ep_move_object(doc.0, 0, delta.x, delta.y)
                };
                assert!(
                    status >= 0,
                    "safe displacement rejected: seed={seed}, step={step}"
                );
                let index = usize::from(duplicate);
                let mut actual = [core::EpPoint { x: 0.0, y: 0.0 }; 2];
                assert_eq!(
                    core::ep_copy_points(doc.0, index, actual.as_mut_ptr(), 2),
                    2
                );
                for (point, expected) in actual.iter().zip(expected) {
                    assert_eq!(
                        (point.x.to_bits(), point.y.to_bits()),
                        (expected.0.to_bits(), expected.1.to_bits())
                    );
                }
                if status == 1 {
                    let after = doc.bytes();
                    assert_eq!(core::ep_undo(doc.0), 1);
                    assert_eq!(doc.bytes(), before);
                    assert_eq!(core::ep_object_revision(doc.0, 0), before_token);
                    assert_eq!(core::ep_redo(doc.0), 1);
                    assert_eq!(doc.bytes(), after);
                    if duplicate {
                        assert_eq!(core::ep_undo(doc.0), 1);
                    } else {
                        translation = next;
                    }
                }
                checks += 1;
            }
        }
    }
    checks
}

fn main() {
    let mut counters = Counters::default();
    for seed in SEEDS {
        // Panic diagnostics retain the precise deterministic failing seed.
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            run_seed(seed, &mut counters)
        }));
        if let Err(error) = result {
            eprintln!("Differential validation failed for seed={seed}");
            std::panic::resume_unwind(error);
        }
    }
    assert_eq!(counters.operations, SEEDS.len() * STEPS);
    assert!(counters.branches > 1_000 && counters.invalid > 1_000 && counters.noops > 1_000);
    assert!(
        counters.moves > 500
            && counters.styles > 500
            && counters.duplicates > 500
            && counters.deletes > 500
    );
    let boundary_checks = run_nonquarter_constraints();
    println!("{{\"status\":\"passed\",\"seeds\":{:?},\"operations\":{},\"state_export_cache_checks\":{},\"adds\":{},\"moves\":{},\"styles\":{},\"duplicates\":{},\"deletes\":{},\"undos\":{},\"redos\":{},\"noops\":{},\"invalid\":{},\"branches\":{},\"reloads\":{},\"additional_undo_redo_steps\":{},\"nonquarter_boundary_checks\":{}}}", SEEDS, counters.operations, counters.checks, counters.adds, counters.moves, counters.styles, counters.duplicates, counters.deletes, counters.undos, counters.redos, counters.noops, counters.invalid, counters.branches, counters.reloads, counters.undo_redo_sweeps, boundary_checks);
}
