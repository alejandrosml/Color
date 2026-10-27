//! History against a model: random edits, undo and redo, checking at every
//! position of the history that the exact internal state comes back (base
//! points, transform, revision, layer, text, style, layer table, paper,
//! project bytes, SVG), and that what the writer produces is accepted by the
//! reader and written back identically.
//!
//! Written by the independent reviewer of version 0.7.0 and kept as a test.
//! EDUPAINT_MODEL_SEEDS and EDUPAINT_MODEL_STEPS widen it (12 seeds of 300
//! steps by default; the review ran 12 000 seeds of 600 steps without a
//! failure). Since 0.7.5 it knows locked layers too: it runs on colouring
//! pages, checks that every command a lock forbids is refused, that no
//! command, undo or redo ever moves a layer past a locked one, and that undo
//! stops at the objects of the page.
use super::*;
use crate::test_support::*;

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        // splitmix64
        self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n.max(1) as u64) as usize
    }
    fn unit(&mut self) -> f64 {
        (self.next() >> 11) as f64 / (1u64 << 53) as f64
    }
    fn pick<T: Copy>(&mut self, values: &[T]) -> T {
        values[self.below(values.len())]
    }
}

#[derive(Clone, Debug, PartialEq)]
struct ObjState {
    points: Vec<(u32, u32)>,
    rgb: u32,
    width: u32,
    style: (u32, u32, u32),
    scale: u64,
    translation: (u64, u64),
    revision: u64,
    layer: u8,
    param: u32,
    text: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq)]
struct DocState {
    paper: u32,
    layers: Vec<(u8, bool, bool)>,
    objects: Vec<ObjState>,
    active_layer: u8,
    project: Vec<u8>,
    svg: String,
}

fn capture(doc: &Owned, with_active: bool) -> DocState {
    let d = doc.doc();
    let mut project = doc.project();
    let mut active_layer = d.active_layer;
    if !with_active {
        active_layer = 0;
        if project[8] >= 4 {
            // blank the active layer word and checksum
            for b in &mut project[44..48] {
                *b = 0;
            }
            let end = project.len() - 4;
            for b in &mut project[end..] {
                *b = 0;
            }
        }
    }
    DocState {
        paper: d.paper,
        layers: d
            .layers()
            .iter()
            .map(|l| (l.id, l.visible, l.locked))
            .collect(),
        objects: d
            .strokes
            .iter()
            .map(|s| ObjState {
                points: s
                    .points
                    .iter()
                    .map(|p| (p.x.to_bits(), p.y.to_bits()))
                    .collect(),
                rgb: s.rgb,
                width: s.width.to_bits(),
                style: (s.style.kind, s.style.fill_enabled, s.style.fill_rgb),
                scale: s.scale.to_bits(),
                translation: (s.translation[0].to_bits(), s.translation[1].to_bits()),
                revision: s.revision,
                layer: s.layer,
                param: s.param,
                text: s.text.clone(),
            })
            .collect(),
        active_layer,
        project,
        svg: doc.svg(),
    }
}

fn check_invariants(doc: &Owned, context: &str) {
    doc.assert_accounting();
    let d = doc.doc();
    let (w, h) = (d.width as f32, d.height as f32);
    for index in 0..doc.count() {
        let points = doc.points(index);
        for p in &points {
            assert!(
                p.x.is_finite()
                    && p.y.is_finite()
                    && (0.0..=w).contains(&p.x)
                    && (0.0..=h).contains(&p.y),
                "{context}: point outside page {p:?} (object {index})"
            );
        }
        let kind = doc.kind(index);
        if kind != 0 {
            // Two points, or for a contour three and more with an extent.
            assert!(
                valid_shape_points(kind, &points),
                "{context}: degenerate shape {points:?}"
            );
        }
        let s = &d.strokes[index];
        assert!(valid_width(kind, s.width), "{context}: width {}", s.width);
        assert!(valid_param(kind, s.param), "{context}");
        assert!(valid_style(s.style), "{context}");
        assert_eq!(kind == KIND_TEXT, !s.text.is_empty(), "{context}");
        if kind == KIND_TEXT {
            assert!(valid_text(&s.text), "{context}");
            assert_eq!(s.scale, 1.0, "{context}: scaled text");
        }
        // exact f64 invariant used by the constrain helper
        for p in &s.points {
            let x = f64::from(p.x) * s.scale + s.translation[0];
            let y = f64::from(p.y) * s.scale + s.translation[1];
            assert!(
                (0.0..=f64::from(d.width)).contains(&x),
                "{context}: f64 x {x}"
            );
            assert!(
                (0.0..=f64::from(d.height)).contains(&y),
                "{context}: f64 y {y}"
            );
        }
    }
    // Writer output must always be accepted and be a fixed point.
    let bytes = doc.project();
    assert_eq!(bytes.len(), unsafe { ep_project_size(doc.0) });
    assert!(bytes.len() <= MAX_PROJECT_BYTES);
    let again = Owned::try_from_project(&bytes)
        .unwrap_or_else(|status| panic!("{context}: own output rejected ({status})"));
    assert_eq!(again.project(), bytes, "{context}: not a fixed point");
    assert_eq!(
        again.svg(),
        doc.svg(),
        "{context}: svg differs after reload"
    );
    if bytes[8] >= 4 {
        assert_eq!(again.layers(), doc.layers(), "{context}");
        assert_eq!(again.locks(), doc.locks(), "{context}");
        assert_eq!(again.active(), doc.active(), "{context}");
        assert_eq!(again.paper(), doc.paper(), "{context}");
        // Version 5 exactly when a lock or a contour asks for it.
        assert_eq!(
            bytes[8] == 5,
            d.needs_locked_project(),
            "{context}: version {}",
            bytes[8]
        );
    } else {
        // v2/v3 has no layer table: the single visible layer comes back as id 0.
        let strip =
            |l: Vec<(u32, bool, usize)>| l.into_iter().map(|(_, v, n)| (v, n)).collect::<Vec<_>>();
        assert_eq!(strip(again.layers()), strip(doc.layers()), "{context}");
        assert_eq!(doc.paper(), 0xffffff, "{context}");
    }
    for index in 0..doc.count() {
        let a = doc.points(index);
        let b = again.points(index);
        assert_eq!(
            a.iter()
                .map(|p| (p.x.to_bits(), p.y.to_bits()))
                .collect::<Vec<_>>(),
            b.iter()
                .map(|p| (p.x.to_bits(), p.y.to_bits()))
                .collect::<Vec<_>>(),
            "{context}"
        );
    }
    let svg_text = doc.svg();
    // The export must fit its up-front reservation (no unplanned reallocation).
    assert!(
        svg_text.len() < svg_capacity(d).unwrap(),
        "{context}: svg {} bytes exceeds reserved {}",
        svg_text.len() + 1,
        svg_capacity(d).unwrap()
    );
    // Revisions are non-zero and unique among visible objects.
    let mut revisions: Vec<u64> = d.strokes.iter().map(|s| s.revision).collect();
    revisions.sort_unstable();
    assert!(
        revisions.first().is_none_or(|r| *r != 0),
        "{context}: zero revision"
    );
    assert!(
        revisions.windows(2).all(|w| w[0] != w[1]),
        "{context}: duplicate revision"
    );
    assert!(
        revisions.last().is_none_or(|r| *r < d.next_revision),
        "{context}"
    );
    assert_eq!(doc.snapshot(), (bytes, svg_text), "{context}");
}

/// How many locked layers lie below layer `id`, which is in the stack.
fn locked_below(doc: &Owned, id: u8) -> usize {
    let layers = doc.doc().layers();
    let position = layers.iter().position(|layer| layer.id == id).unwrap();
    layers[..position]
        .iter()
        .filter(|layer| layer.locked)
        .count()
}

/// For every layer, how many locked layers lie below it.
fn layout(doc: &Owned) -> Vec<(u8, usize)> {
    let layers = doc.doc().layers();
    layers
        .iter()
        .map(|layer| (layer.id, locked_below(doc, layer.id)))
        .collect()
}

/// No command, undo or redo changes how many locked layers lie below a layer
/// that stays: no layer ever passes a locked one. Returns the new layout.
fn assert_no_layer_passed(before: &[(u8, usize)], doc: &Owned, context: &str) -> Vec<(u8, usize)> {
    let after = layout(doc);
    for (id, below) in &after {
        if let Some((_, was)) = before.iter().find(|(other, _)| other == id) {
            assert_eq!(below, was, "{context}: layer {id} passed a locked layer");
        }
    }
    after
}

fn random_coordinate(rng: &mut Rng, size: u32) -> f32 {
    let s = size as f32;
    match rng.below(12) {
        0 => 0.0,
        1 => s,
        2 => -0.0,
        3 => f32::from_bits(1), // smallest subnormal
        4 => f32::MIN_POSITIVE,
        5 => s.next_down(),
        6 => (s / 2.0).next_up(),
        7 => (rng.unit() * 1e-3) as f32,
        _ => (rng.unit() * f64::from(size)) as f32,
    }
}

fn random_point(rng: &mut Rng, w: u32, h: u32) -> EpPoint {
    point(random_coordinate(rng, w), random_coordinate(rng, h))
}

const TEXTS: [&str; 8] = [
    "a",
    "Été\n2 < 3 & \"x\" > y",
    "ligne 1\nligne 2\n\nligne 4",
    "😀 emoji",
    " x ",
    "\n\n\nz",
    "]]> <!-- --> &amp;",
    "\u{a0}\u{3000}é",
];

fn run(seed: u64, steps: usize, w: u32, h: u32, with_active: bool) {
    run_on(Owned::sized(w, h), seed, steps, with_active);
}

pub(crate) fn run_on(doc: Owned, seed: u64, steps: usize, with_active: bool) {
    let mut rng = Rng(seed);
    let (w, h) = (doc.doc().width, doc.doc().height);
    let loaded = unsafe { ep_undo_count(doc.0) };
    // The objects of locked layers: no command and no undo takes them away.
    let pinned = doc.pinned();
    let locked = |doc: &Owned, index: usize| doc.doc().locked(doc.doc().strokes[index].layer);
    let mut states = vec![capture(&doc, !with_active)];
    let mut cursor = 0usize;
    let mut arrangement = layout(&doc);
    for step in 0..steps {
        let context = format!("seed {seed:#x} step {step} page {w}x{h}");
        let count = doc.count();
        let layer_count = unsafe { ep_layer_count(doc.0) };
        let op = match std::env::var("EDUPAINT_MODEL_BIAS").as_deref() {
            Ok("layers") if rng.below(2) == 0 => {
                [15, 15, 15, 16, 17, 18, 19, 19, 19, 21, 22][rng.below(11)]
            }
            Ok("scale") if rng.below(2) == 0 => [7, 8, 9, 5, 6, 12, 21, 22][rng.below(8)],
            Ok("text") if rng.below(2) == 0 => {
                [3, 3, 14, 14, 14, 12, 11, 16, 21, 22][rng.below(10)]
            }
            _ => rng.below(24),
        };
        // returns Some(changed) for edits, None for undo/redo/view ops
        let mut changed: Option<bool> = None;
        let mut description = String::new();
        match op {
            0 | 1 => {
                let n = 1 + rng.below(5);
                let pts: Vec<_> = (0..n).map(|_| random_point(&mut rng, w, h)).collect();
                let status = doc.stroke(&pts, rng.below(0x100_0000) as u32);
                description = format!("stroke {pts:?} -> {status}");
                assert!(status == 0 || status == INVALID, "{context}: {description}");
                changed = Some(status == 0);
            }
            2 => {
                let kind = 1 + rng.below(3) as u32;
                let c = [random_point(&mut rng, w, h), random_point(&mut rng, w, h)];
                let fill = kind >= 2 && rng.below(2) == 0;
                let style = EpObjectStyle {
                    kind,
                    fill_enabled: fill as u32,
                    fill_rgb: if fill {
                        rng.below(0x100_0000) as u32
                    } else {
                        0
                    },
                };
                let width = rng.pick(&[0.1f32, 1.0, 3.5, 512.0]);
                let status = unsafe { ep_add_shape(doc.0, c.as_ptr(), &style, 0x123456, width) };
                description = format!("shape {kind} {c:?} -> {status}");
                assert!(status == 0 || status == INVALID, "{context}: {description}");
                changed = Some(status == 0);
            }
            3 => {
                let c = [random_point(&mut rng, w, h), random_point(&mut rng, w, h)];
                let size = rng.pick(&[4.0f32, 12.5, 40.0, 2048.0]);
                let text = rng.pick(&TEXTS);
                let status = doc.text(c, 0x336699, size, text);
                description = format!("text {c:?} -> {status}");
                assert!(status == 0 || status == INVALID, "{context}: {description}");
                changed = Some(status == 0);
            }
            4 => {
                let c = [random_point(&mut rng, w, h), random_point(&mut rng, w, h)];
                let id = rng.below(ep_stamp_count() as usize + 1) as u32;
                let status = doc.stamp(c, id, 0x477fb2);
                description = format!("stamp {id} {c:?} -> {status}");
                assert!(status == 0 || status == INVALID, "{context}: {description}");
                changed = Some(status == 0);
            }
            5 | 6 => {
                if count > 0 {
                    let index = rng.below(count);
                    let pinned = locked(&doc, index);
                    let (dx, dy) = match rng.below(4) {
                        0 => (
                            rng.unit() as f32 * 10.0 - 5.0,
                            rng.unit() as f32 * 10.0 - 5.0,
                        ),
                        1 => (1e-7, -1e-7),
                        2 => (w as f32, h as f32),
                        _ => {
                            let mut delta = point(0.0, 0.0);
                            let rdx = (rng.unit() * 2.0 - 1.0) as f32 * w as f32 * 2.0;
                            let rdy = (rng.unit() * 2.0 - 1.0) as f32 * h as f32 * 2.0;
                            let status = unsafe {
                                ep_constrain_object_movement(doc.0, index, rdx, rdy, &mut delta)
                            };
                            assert!(status == 0 || status == INVALID, "{context}");
                            assert!(!pinned || status == INVALID, "{context}: locked moves");
                            if status == 0 {
                                // contract: a constrained delta is accepted by the mover
                                let status =
                                    unsafe { ep_move_object(doc.0, index, delta.x, delta.y) };
                                assert!(
                                    status == 0 || status == 1,
                                    "{context}: constrained move rejected {status} {delta:?}"
                                );
                                changed = Some(status == 1);
                                description =
                                    format!("constrained move {index} {delta:?} -> {status}");
                            }
                            (f32::NAN, f32::NAN)
                        }
                    };
                    if changed.is_none() && !dx.is_nan() {
                        let status = unsafe { ep_move_object(doc.0, index, dx, dy) };
                        description = format!("move {index} {dx} {dy} -> {status}");
                        assert!((-1..=1).contains(&status), "{context}: {description}");
                        assert!(!pinned || status == INVALID, "{context}: {description}");
                        changed = Some(status == 1);
                    }
                }
            }
            7..=9 => {
                if count > 0 {
                    let index = rng.below(count);
                    let pinned = locked(&doc, index);
                    let factor = rng.pick(&[
                        1.0f32 / 64.0,
                        0.5,
                        0.37,
                        0.9991,
                        1.0,
                        1.0009,
                        1.369,
                        1.5,
                        2.0,
                        3.0,
                        64.0,
                    ]);
                    let current = doc.info(index).width;
                    let width = match rng.below(3) {
                        0 => current,
                        1 => (current * factor).clamp(0.1, 512.0),
                        _ => rng.pick(&[0.1f32, 1.0, 7.25, 512.0]),
                    };
                    let status = doc.scale(index, factor, width);
                    description = format!("scale {index} x{factor} w{width} -> {status}");
                    assert!((-1..=1).contains(&status), "{context}: {description}");
                    assert!(!pinned || status == INVALID, "{context}: {description}");
                    changed = Some(status == 1);
                }
            }
            10 => {
                if count > 0 {
                    let (from, to) = (rng.below(count), rng.below(count));
                    let pinned = locked(&doc, from);
                    let status = unsafe { ep_reorder_object(doc.0, from, to) };
                    description = format!("reorder {from}->{to} -> {status}");
                    if pinned {
                        assert_eq!(status, INVALID, "{context}: {description}");
                    } else {
                        assert!((0..=1).contains(&status), "{context}: {description}");
                    }
                    changed = Some(status == 1);
                }
            }
            11 => {
                if count > 0 {
                    let index = rng.below(count);
                    let pinned = locked(&doc, index);
                    let status = unsafe { ep_remove_object(doc.0, index) };
                    description = format!("remove {index} -> {status}");
                    assert_eq!(
                        status,
                        if pinned { INVALID } else { 1 },
                        "{context}: {description}"
                    );
                    changed = Some(status == 1);
                }
            }
            12 => {
                if count > 0 {
                    let index = rng.below(count);
                    let (dx, dy) = if rng.below(2) == 0 {
                        (0.0, 0.0)
                    } else {
                        (3.0, -2.0)
                    };
                    let pinned = locked(&doc, index);
                    let status = unsafe { ep_duplicate_object(doc.0, index, dx, dy) };
                    description = format!("duplicate {index} -> {status}");
                    assert!(status == 1 || status == INVALID, "{context}: {description}");
                    assert!(!pinned || status == INVALID, "{context}: {description}");
                    changed = Some(status == 1);
                }
            }
            13 => {
                if count > 0 {
                    let index = rng.below(count);
                    let kind = doc.kind(index);
                    let info = doc.info(index);
                    let filled = doc.doc().strokes[index].style.fill_enabled == 1;
                    let pinned = locked(&doc, index);
                    let (rgb, width, fill, fill_rgb) = if pinned && rng.below(2) == 0 {
                        // The paint pot on a zone of a page: the outline as
                        // it is, a new colour inside.
                        let colour = rng.below(0x100_0000) as u32;
                        (
                            info.rgb,
                            info.width,
                            u32::from(filled),
                            colour * u32::from(filled),
                        )
                    } else {
                        let width = if matches!(kind, KIND_TEXT | KIND_STAMP) {
                            info.width
                        } else {
                            rng.pick(&[0.1f32, 2.0, 512.0])
                        };
                        let fill = matches!(kind, 2 | 3 | KIND_CONTOUR) && rng.below(2) == 0;
                        let fill_rgb = if fill { 0xabcdef } else { 0 };
                        (rng.below(4) as u32, width, u32::from(fill), fill_rgb)
                    };
                    let status =
                        unsafe { ep_set_object_style(doc.0, index, rgb, width, fill, fill_rgb) };
                    description = format!("style {index} -> {status}");
                    if pinned && !(filled && fill == 1 && rgb == info.rgb && width == info.width) {
                        assert_eq!(status, INVALID, "{context}: {description}");
                    } else {
                        assert!((0..=1).contains(&status), "{context}: {description}");
                    }
                    changed = Some(status == 1);
                }
            }
            14 => {
                if count > 0 {
                    let index = rng.below(count);
                    let pinned = locked(&doc, index);
                    let c = [random_point(&mut rng, w, h), random_point(&mut rng, w, h)];
                    let text = rng.pick(&TEXTS);
                    let status =
                        doc.set_text(index, c, 0x010203, rng.pick(&[4.0f32, 33.0, 2048.0]), text);
                    description = format!("set_text {index} {c:?} -> {status}");
                    assert!((-1..=1).contains(&status), "{context}: {description}");
                    if doc.kind(index) != KIND_TEXT || pinned {
                        assert_eq!(status, INVALID, "{context}");
                    }
                    changed = Some(status == 1);
                }
            }
            15 => {
                let below = locked_below(&doc, doc.doc().active_layer);
                let status = unsafe { ep_add_layer(doc.0) };
                description = format!("add_layer -> {status}");
                assert!(status == 1 || status == INVALID, "{context}");
                if status == 1 {
                    // The new layer, now active, lies between the same
                    // locked layers as the one that was active.
                    assert_eq!(
                        locked_below(&doc, doc.doc().active_layer),
                        below,
                        "{context}: {description}"
                    );
                }
                changed = Some(status == 1);
            }
            16 => {
                let position = rng.below(layer_count);
                let pinned = doc.doc().layers()[position].locked;
                let status = unsafe { ep_remove_layer(doc.0, position) };
                description = format!("remove_layer {position} -> {status}");
                assert!(status == 1 || status == INVALID, "{context}");
                assert!(!pinned || status == INVALID, "{context}: {description}");
                changed = Some(status == 1);
            }
            17 => {
                let (from, to) = (rng.below(layer_count), rng.below(layer_count));
                // A locked layer anywhere from `from` to `to`: none moves,
                // none is passed.
                let pinned = doc.doc().layers()[from.min(to)..=from.max(to)]
                    .iter()
                    .any(|layer| layer.locked);
                let status = unsafe { ep_reorder_layer(doc.0, from, to) };
                description = format!("reorder_layer {from}->{to} -> {status}");
                if pinned {
                    assert_eq!(status, INVALID, "{context}: {description}");
                } else {
                    assert_eq!(status, i32::from(from != to), "{context}: {description}");
                }
                changed = Some(status == 1);
            }
            18 => {
                let position = rng.below(layer_count);
                let status = unsafe { ep_set_layer_visible(doc.0, position, rng.below(2) as u32) };
                description = format!("visible {position} -> {status}");
                assert!((0..=1).contains(&status), "{context}");
                changed = Some(status == 1);
            }
            19 => {
                if count > 0 {
                    let index = rng.below(count);
                    let layer = rng.below(MAX_LAYERS) as u32;
                    let pinned = locked(&doc, index) || doc.doc().locked(layer as u8);
                    let status = unsafe { ep_set_object_layer(doc.0, index, layer) };
                    description = format!("object_layer {index} -> {layer}: {status}");
                    assert!((-1..=1).contains(&status), "{context}");
                    assert!(!pinned || status == INVALID, "{context}: {description}");
                    changed = Some(status == 1);
                }
            }
            20 => {
                let status = doc.set_paper(rng.pick(&[0xffffffu32, 0, 0x123456, 0xfffffe]));
                description = format!("paper -> {status}");
                assert!((0..=1).contains(&status), "{context}");
                changed = Some(status == 1);
            }
            21 => {
                // several undos
                for _ in 0..1 + rng.below(4) {
                    if cursor == 0 && loaded != 0 {
                        break;
                    }
                    let status = doc.undo();
                    if cursor == 0 {
                        assert_eq!(status, 0, "{context}");
                    } else {
                        assert_eq!(status, 1, "{context}");
                        cursor -= 1;
                        check_invariants(&doc, &context);
                        arrangement = assert_no_layer_passed(&arrangement, &doc, &context);
                        assert_eq!(
                            capture(&doc, !with_active),
                            states[cursor],
                            "{context}: undo to {cursor}"
                        );
                    }
                }
            }
            22 => {
                for _ in 0..1 + rng.below(4) {
                    let status = doc.redo();
                    if cursor + 1 == states.len() {
                        assert_eq!(status, 0, "{context}");
                    } else {
                        assert_eq!(status, 1, "{context}");
                        cursor += 1;
                        check_invariants(&doc, &context);
                        arrangement = assert_no_layer_passed(&arrangement, &doc, &context);
                        assert_eq!(
                            capture(&doc, !with_active),
                            states[cursor],
                            "{context}: redo to {cursor}"
                        );
                    }
                }
            }
            _ => {
                if with_active {
                    let id = rng.below(MAX_LAYERS) as u32;
                    let before = capture(&doc, false);
                    let status = unsafe { ep_set_active_layer(doc.0, id) };
                    assert!(status == 0 || status == INVALID, "{context}");
                    assert_eq!(
                        capture(&doc, false),
                        before,
                        "{context}: active layer changed content"
                    );
                    if status == 0 {
                        assert_eq!(doc.active(), id);
                    }
                    if doc.doc().locked(id as u8) {
                        assert_eq!(status, INVALID, "{context}: a locked layer made active");
                    }
                }
            }
        }
        if let Some(changed) = changed {
            check_invariants(&doc, &format!("{context}: {description}"));
            arrangement =
                assert_no_layer_passed(&arrangement, &doc, &format!("{context}: {description}"));
            let now = capture(&doc, !with_active);
            if changed {
                states.truncate(cursor + 1);
                states.push(now);
                cursor += 1;
            } else {
                assert_eq!(
                    now, states[cursor],
                    "{context}: {description}: no-op/failure changed state"
                );
            }
            assert_eq!(
                unsafe { ep_undo_count(doc.0) },
                loaded + cursor,
                "{context}: {description}"
            );
            assert_eq!(
                unsafe { ep_redo_count(doc.0) },
                states.len() - 1 - cursor,
                "{context}: {description}"
            );
        }
    }
    // Whole history back and forth.
    while cursor > 0 {
        assert_eq!(doc.undo(), 1);
        cursor -= 1;
        doc.assert_accounting();
        let context = format!("seed {seed:#x}: final undo to {cursor}");
        arrangement = assert_no_layer_passed(&arrangement, &doc, &context);
        assert_eq!(capture(&doc, !with_active), states[cursor], "{context}");
    }
    // Below the model: the objects that came from the file, but for those of
    // a locked layer, which no undo takes away.
    for _ in 0..loaded {
        assert_eq!(doc.undo(), 1);
        doc.assert_accounting();
    }
    assert_eq!(doc.undo(), 0);
    assert_eq!(doc.count(), pinned);
    assert_eq!(doc.pinned(), pinned);
    for _ in 0..loaded {
        assert_eq!(doc.redo(), 1);
    }
    assert_eq!(
        capture(&doc, !with_active),
        states[0],
        "seed {seed:#x}: back to the loaded state"
    );
    if let Ok(dir) = std::env::var("EDUPAINT_MODEL_DUMP_DIR") {
        if seed.is_multiple_of(16) {
            std::fs::write(format!("{dir}/svg-{seed:x}-start.svg"), doc.svg()).unwrap();
        }
    }
    while cursor + 1 < states.len() {
        assert_eq!(doc.redo(), 1);
        cursor += 1;
        doc.assert_accounting();
        let context = format!("seed {seed:#x}: final redo to {cursor}");
        arrangement = assert_no_layer_passed(&arrangement, &doc, &context);
        assert_eq!(capture(&doc, !with_active), states[cursor], "{context}");
    }
    assert_eq!(doc.redo(), 0);
    if let Ok(dir) = std::env::var("EDUPAINT_MODEL_DUMP_DIR") {
        if seed.is_multiple_of(4) {
            std::fs::write(format!("{dir}/svg-{seed:x}-end.svg"), doc.svg()).unwrap();
        }
    }
}

#[test]
fn random_edits_undo_and_redo_restore_the_exact_state() {
    let pages = [
        (1200u32, 800u32),
        (1, 1),
        (16384, 16384),
        (1001, 333),
        (2, 16384),
        (37, 5),
    ];
    let seeds: usize = std::env::var("EDUPAINT_MODEL_SEEDS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(12);
    let steps: usize = std::env::var("EDUPAINT_MODEL_STEPS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(300);
    for seed in 0..seeds as u64 {
        let (w, h) = pages[seed as usize % pages.len()];
        run(0x1000 + seed, steps, w, h, false);
    }
}

/// The model on a colouring page of version 5 with a drawing on it: locked
/// layers, contours, a hidden locked layer, objects outside the history.
#[test]
fn random_edits_on_a_locked_page_restore_the_exact_state() {
    let page = include_bytes!("../test-fixtures/import-project/locked-page-v5.edupaint");
    let steps: usize = std::env::var("EDUPAINT_MODEL_STEPS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(300);
    for seed in 0..6 {
        run_on(
            Owned::from_project(page),
            0x7a6e_0000 + seed,
            steps,
            seed % 2 == 0,
        );
    }
}

#[test]
fn random_edits_with_active_layer_changes_restore_the_exact_state() {
    let pages = [(1200u32, 800u32), (64, 64), (16384, 3)];
    let seeds: usize = std::env::var("EDUPAINT_MODEL_SEEDS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(12);
    let steps: usize = std::env::var("EDUPAINT_MODEL_STEPS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(300);
    for seed in 0..seeds as u64 {
        let (w, h) = pages[seed as usize % pages.len()];
        run(0x9000 + seed, steps, w, h, true);
    }
}
