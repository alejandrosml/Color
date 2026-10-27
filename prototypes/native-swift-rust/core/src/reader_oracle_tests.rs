//! The reader against an independent oracle.
//!
//! The oracle below decides whether a version 4 or 5 file is valid from the
//! format description in edupaint_core.h alone; it shares no code with the
//! reader. It was written by the independent reviewer of version 0.7.0 and
//! is kept as a test; its version 5 rules (layer flags, locked active layer,
//! closed contours) were added for 0.7.5 from the header text, again without
//! sharing code. A generator builds files that are coherent, or wrong in one
//! place (a count, a size, an identifier, a text, a limit, a flag, a
//! contour), and the reader must agree with the oracle on every one of them.
//! Mutating bytes at random, as mutation_tests.rs does, almost never produces
//! such files.
//!
//! EDUPAINT_ORACLE_ROUNDS sets the number of files (30 000 by default; the
//! review ran 2 300 000 without a disagreement).
use super::*;
use crate::test_support::*;

pub(crate) struct Rng(pub u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n.max(1) as u64) as usize
    }
    fn chance(&mut self, one_in: usize) -> bool {
        self.below(one_in) == 0
    }
    fn unit(&mut self) -> f64 {
        (self.next() >> 11) as f64 / (1u64 << 53) as f64
    }
}

// ---------- independent oracle ----------

pub(crate) fn le32(bytes: &[u8], at: usize) -> Option<u32> {
    let s = bytes.get(at..at.checked_add(4)?)?;
    Some(u32::from_le_bytes([s[0], s[1], s[2], s[3]]))
}

// Independent bitwise CRC-32 (reflected 0xEDB88320).
fn slow_crc(bytes: &[u8]) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for &b in bytes {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xedb8_8320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

fn oracle_text_ok(bytes: &[u8]) -> bool {
    if bytes.is_empty() || bytes.len() > 2048 {
        return false;
    }
    let Ok(text) = std::str::from_utf8(bytes) else {
        return false;
    };
    if text.split('\n').count() > 32 {
        return false;
    }
    let mut visible = false;
    for c in text.chars() {
        let code = c as u32;
        if c == '\n' {
            continue;
        }
        // XML 1.0 Char minus controls, minus U+2028/2029
        let allowed = (0x20..=0x7e).contains(&code)
            || (0xa0..=0xd7ff).contains(&code)
            || (0xe000..=0xfffd).contains(&code)
            || (0x10000..=0x10ffff).contains(&code);
        if !allowed || code == 0x2028 || code == 0x2029 {
            return false;
        }
        if !c.is_whitespace()
            && !ORACLE_IGNORABLE
                .iter()
                .any(|(low, high)| (*low..=*high).contains(&code))
        {
            visible = true;
        }
    }
    visible
}

// Default_Ignorable_Code_Point, written again here on purpose rather than
// shared with text.rs.
const ORACLE_IGNORABLE: [(u32, u32); 17] = [
    (0xad, 0xad),
    (0x34f, 0x34f),
    (0x61c, 0x61c),
    (0x115f, 0x1160),
    (0x17b4, 0x17b5),
    (0x180b, 0x180f),
    (0x200b, 0x200f),
    (0x202a, 0x202e),
    (0x2060, 0x206f),
    (0x3164, 0x3164),
    (0xfe00, 0xfe0f),
    (0xfeff, 0xfeff),
    (0xffa0, 0xffa0),
    (0xfff0, 0xfff8),
    (0x1bca0, 0x1bca3),
    (0x1d173, 0x1d17a),
    (0xe0000, 0xe0fff),
];

#[derive(Debug, PartialEq, Clone, Copy)]
enum Verdict {
    Invalid(&'static str),
    Plain,   // valid, but needs no v4 feature: the writer would use v2/v3
    Layered, // valid, needs v4 and no v5 feature: written back as v4
    Locked,  // valid and canonical v5: a locked layer or a contour
}

fn oracle(bytes: &[u8], png_ok: &dyn Fn(&[u8], u32, u32) -> bool) -> Verdict {
    use Verdict::*;
    if bytes.len() < 36 || bytes.len() > 80_711_932 {
        return Invalid("length");
    }
    if &bytes[..8] != b"EDUPAINT"
        || !(bytes[8..10] == [4, 0] || bytes[8..10] == [5, 0])
        || bytes[10..12] != [0, 0]
    {
        return Invalid("magic/version/flags");
    }
    // Version 5: the same layout, layer flags with a lock bit, contours.
    let five = bytes[8] == 5;
    let word = |at: usize| le32(bytes, at);
    let Some(total) = word(12) else {
        return Invalid("short");
    };
    if total as usize != bytes.len() {
        return Invalid("total size");
    }
    if bytes.len() < 56 + 8 + 4 {
        return Invalid("short header");
    }
    let (w, h) = (word(16).unwrap(), word(20).unwrap());
    let objects = word(24).unwrap() as usize;
    let points = word(28).unwrap() as usize;
    let png = word(32).unwrap() as usize;
    let layers = word(36).unwrap() as usize;
    let text_total = word(40).unwrap() as usize;
    let active = word(44).unwrap();
    let paper = word(48).unwrap();
    let reserved = word(52).unwrap();
    if !(1..=16384).contains(&w) || !(1..=16384).contains(&h) {
        return Invalid("dimensions");
    }
    if objects > 10_000 || points > 1_000_000 || text_total > (1 << 20) || png > 71_303_168 {
        return Invalid("limits");
    }
    if !(1..=16).contains(&layers) {
        return Invalid("layer count");
    }
    if reserved != 0 {
        return Invalid("reserved");
    }
    if paper != 0 && (paper >> 24 != 1 || paper & 0xff_ffff == 0xff_ffff) {
        return Invalid("paper");
    }
    let mut at = 56usize;
    let mut ids = Vec::new();
    let mut locked_ids = Vec::new();
    let mut hidden = false;
    for _ in 0..layers {
        let (Some(id), Some(flags)) = (word(at), word(at + 4)) else {
            return Invalid("layer table truncated");
        };
        at += 8;
        // v4: exactly 0 or 1; v5: bit 0 visible, bit 1 locked, nothing else.
        let allowed = if five { 3 } else { 1 };
        if id >= 16 || flags > allowed || ids.contains(&id) {
            return Invalid("layer entry");
        }
        hidden |= flags & 1 == 0;
        if flags & 2 == 2 {
            locked_ids.push(id);
        }
        ids.push(id);
    }
    if !ids.contains(&active) {
        return Invalid("active layer");
    }
    if locked_ids.contains(&active) {
        return Invalid("locked active layer");
    }
    let Some(payload_end) = bytes.len().checked_sub(4) else {
        return Invalid("short");
    };
    if slow_crc(&bytes[..payload_end]) != word(payload_end).unwrap() {
        return Invalid("crc");
    }
    let Some(png_start) = payload_end.checked_sub(png) else {
        return Invalid("png size");
    };
    if png_start < at {
        return Invalid("png overlaps");
    }
    let mut seen_points = 0usize;
    let mut seen_text = 0usize;
    let mut extended = false;
    let mut contour = false;
    for _ in 0..objects {
        if at + 36 > png_start {
            return Invalid("record truncated");
        }
        let rgb = word(at).unwrap();
        let width = f32::from_bits(word(at + 4).unwrap());
        let count = word(at + 8).unwrap() as usize;
        let kind = word(at + 12).unwrap();
        let fill = word(at + 16).unwrap();
        let fill_rgb = word(at + 20).unwrap();
        let layer = word(at + 24).unwrap();
        let param = word(at + 28).unwrap();
        let text_bytes = word(at + 32).unwrap() as usize;
        at += 36;
        if rgb > 0xff_ffff || kind > 6 || fill > 1 || fill_rgb > 0xff_ffff {
            return Invalid("record scalars");
        }
        if kind == 6 && !five {
            return Invalid("contour before version 5");
        }
        if fill == 0 && fill_rgb != 0 {
            return Invalid("fill colour without fill");
        }
        if fill == 1 && !(kind == 2 || kind == 3 || kind == 6) {
            return Invalid("fill on a kind without fill");
        }
        let width_ok = width.is_finite()
            && match kind {
                4 => (4.0..=2048.0).contains(&width),
                5 => width == 1.0,
                _ => (0.1..=512.0).contains(&width),
            };
        if !width_ok {
            return Invalid("width");
        }
        if !ids.contains(&layer) {
            return Invalid("object layer");
        }
        let param_ok = match kind {
            5 => param < 24,
            _ => param == 0,
        };
        if !param_ok {
            return Invalid("param");
        }
        // Freehand: 1 point or more; contour: 3 or more; the rest exactly 2.
        let count_ok = match kind {
            0 => count >= 1,
            6 => count >= 3,
            _ => count == 2,
        };
        if !count_ok || count > 100_000 {
            return Invalid("point count");
        }
        if (kind == 4) != (text_bytes != 0) || text_bytes > 2048 {
            return Invalid("text bytes");
        }
        if at + count * 8 + text_bytes > png_start {
            return Invalid("object payload truncated");
        }
        let mut pts = Vec::new();
        for i in 0..count {
            let x = f32::from_bits(word(at + i * 8).unwrap());
            let y = f32::from_bits(word(at + i * 8 + 4).unwrap());
            if !x.is_finite()
                || !y.is_finite()
                || x < 0.0
                || y < 0.0
                || x > w as f32
                || y > h as f32
            {
                return Invalid("point");
            }
            pts.push((x, y));
        }
        at += count * 8;
        if kind == 1 && pts[0] == pts[1] {
            return Invalid("zero line");
        }
        if (2..=5).contains(&kind) && (pts[0].0 == pts[1].0 || pts[0].1 == pts[1].1) {
            return Invalid("zero box");
        }
        if kind == 6 {
            // The box around all the points needs a width and a height.
            let xs = pts.iter().map(|p| p.0);
            let ys = pts.iter().map(|p| p.1);
            let width = xs.clone().fold(f32::MIN, f32::max) - xs.fold(f32::MAX, f32::min);
            let height = ys.clone().fold(f32::MIN, f32::max) - ys.fold(f32::MAX, f32::min);
            if width <= 0.0 || height <= 0.0 {
                return Invalid("flat contour");
            }
        }
        if kind == 4 && !oracle_text_ok(&bytes[at..at + text_bytes]) {
            return Invalid("text");
        }
        at += text_bytes;
        seen_points += count;
        seen_text += text_bytes;
        extended |= kind == 4 || kind == 5;
        contour |= kind == 6;
    }
    if seen_points != points || seen_text != text_total {
        return Invalid("totals");
    }
    if at != png_start {
        return Invalid("trailing or missing bytes");
    }
    if png != 0 && !png_ok(&bytes[png_start..payload_end], w, h) {
        return Invalid("png");
    }
    if !locked_ids.is_empty() || contour {
        Locked
    } else if layers == 1 && !hidden && !extended && paper == 0 {
        Plain
    } else {
        Layered
    }
}

// ---------- generator ----------

fn push(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn random_text(rng: &mut Rng) -> Vec<u8> {
    match rng.below(24) {
        0 => Vec::new(),
        1 => b"a\tb".to_vec(),
        2 => vec![0xff, 0xfe],
        3 => b" \n ".to_vec(),
        4 => "\u{2028}x".as_bytes().to_vec(),
        5 => vec![b'x'; 2049],
        6 => vec![b'x'; 2048],
        7 => ("a\n".repeat(31) + "b").into_bytes(), // 32 lines
        8 => ("a\n".repeat(32) + "b").into_bytes(), // 33 lines
        9 => "a\n".repeat(32).into_bytes(),         // 33 lines, last one empty
        10 => "\u{7f}".as_bytes().to_vec(),
        11 => "\u{85}x".as_bytes().to_vec(),
        12 => "\u{fffe}".as_bytes().to_vec(),
        13 => "\u{fffd}".as_bytes().to_vec(),
        14 => vec![0xed, 0xa0, 0x80],         // surrogate encoded
        15 => vec![0xc0, 0xaf],               // overlong
        16 => "\u{a0}".as_bytes().to_vec(),   // only no-break space
        17 => "\u{200b}".as_bytes().to_vec(), // zero width space
        18 => b"x\0y".to_vec(),
        19 => "\u{10ffff}".as_bytes().to_vec(),
        20 => b"x\r\ny".to_vec(),
        _ => "Été\n2 < 3 & co".as_bytes().to_vec(),
    }
}

fn random_coordinate(rng: &mut Rng, size: u32) -> f32 {
    match rng.below(40) {
        0 => f32::NAN,
        1 => f32::INFINITY,
        2 => -1.0,
        3 => (size as f32).next_up(),
        4 => -0.0,
        5 => f32::from_bits(1),
        6 => -f32::from_bits(1),
        7 => size as f32,
        8 => 0.0,
        _ => (rng.unit() * f64::from(size.min(16384))) as f32,
    }
}

pub(crate) fn generate(rng: &mut Rng, png: &[u8], png_size: (u32, u32)) -> Vec<u8> {
    let with_png = rng.chance(6);
    let (w, h) = if with_png && !rng.chance(8) {
        png_size
    } else {
        match rng.below(30) {
            0 => (0, 10),
            1 => (16384, 16384),
            2 => (16385, 10),
            3 => (1, 1),
            _ => (100, 80),
        }
    };
    // Two files in five of version 4, the others of version 5 but now and
    // then one of a version to come.
    let version: u16 = match rng.below(60) {
        0 => 6,
        1..=24 => 4,
        _ => 5,
    };
    let layer_count = match rng.below(40) {
        0 => 0,
        1 => 17,
        2 => 16,
        _ => 1 + rng.below(3),
    };
    let mut ids: Vec<u32> = Vec::new();
    let mut unlocked: Vec<u32> = Vec::new();
    let mut table = Vec::new();
    for _ in 0..layer_count {
        let id = match rng.below(40) {
            0 => 16,
            1 => u32::MAX,
            2 => ids.first().copied().unwrap_or(0), // duplicate
            _ => {
                let mut id = rng.below(16) as u32;
                while ids.contains(&id) && ids.len() < 16 {
                    id = (id + 1) % 16;
                }
                id
            }
        };
        ids.push(id);
        let visible = match rng.below(30) {
            0 => [4u32, 0x8000_0000][rng.below(2)], // an unknown bit
            1..=6 => 0,
            _ => 1,
        };
        // Locked layers are for version 5; in version 4 the bit is wrong.
        let locked = if version == 4 {
            rng.chance(40)
        } else {
            rng.chance(2)
        };
        if !locked {
            unlocked.push(id);
        }
        table.push((id, visible | (u32::from(locked) << 1)));
    }
    // A valid file keeps one layer to draw on: unlock the last one, mostly.
    if version == 5 && unlocked.is_empty() && !rng.chance(20) {
        if let Some((id, flags)) = table.last_mut() {
            *flags &= !2;
            unlocked.push(*id);
        }
    }
    let active = if rng.chance(30) || ids.is_empty() {
        rng.below(18) as u32
    } else if rng.chance(20) || unlocked.is_empty() {
        ids[rng.below(ids.len())]
    } else {
        unlocked[rng.below(unlocked.len())]
    };
    let paper = match rng.below(30) {
        0 => 0x01ff_ffff,
        1 => 0x0012_3456,
        2 => 0x0200_0000 | 0x123456,
        3 => 0x0100_0000,
        4..=8 => 0x0100_0000 | (rng.below(0xff_ffff) as u32),
        _ => 0,
    };
    let reserved = if rng.chance(40) { 1 } else { 0 };
    let object_count = rng.below(5);
    let mut body = Vec::new();
    let (mut points_total, mut text_total) = (0usize, 0usize);
    for _ in 0..object_count {
        // Contours are for version 5, where they come more often.
        let kind = if rng.chance(60) {
            7
        } else if version == 5 && rng.chance(5) {
            6
        } else {
            rng.below(7) as u32
        };
        let rgb = if rng.chance(40) {
            0x0100_0000
        } else {
            rng.below(0x100_0000) as u32
        };
        let width = if rng.chance(15) {
            [
                f32::NAN,
                0.0,
                3.0,
                2049.0,
                3.9,
                513.0,
                0.09,
                f32::INFINITY,
                1.0,
            ][rng.below(9)]
        } else {
            match kind {
                4 => [4.0, 40.0, 2048.0][rng.below(3)],
                5 => 1.0,
                _ => [0.1, 3.0, 512.0][rng.below(3)],
            }
        };
        let count = if rng.chance(20) {
            [0usize, 1, 2, 3][rng.below(4)]
        } else {
            match kind {
                0 => 1 + rng.below(4),
                6 => 3 + rng.below(4),
                _ => 2,
            }
        };
        let (fill, fill_rgb) = match rng.below(12) {
            0 => (1, 0x112233),
            1 => (0, 0x112233),
            2 => (2, 0),
            3 => (1, 0x0100_0000),
            _ if matches!(kind, 2 | 3 | 6) && rng.chance(2) => (1, 0x445566),
            _ => (0, 0),
        };
        let layer = if rng.chance(25) || ids.is_empty() {
            [300u32, 15, 16, 0][rng.below(4)]
        } else {
            ids[rng.below(ids.len())]
        };
        let param = if rng.chance(20) {
            [24u32, 1, u32::MAX][rng.below(3)]
        } else if kind == 5 {
            rng.below(24) as u32
        } else {
            0
        };
        let text = if kind == 4 {
            random_text(rng)
        } else if rng.chance(25) {
            b"stray".to_vec()
        } else {
            Vec::new()
        };
        let declared_text = if rng.chance(40) {
            text.len() + 1
        } else {
            text.len()
        };
        push(&mut body, rgb);
        push(&mut body, width.to_bits());
        push(&mut body, count as u32);
        push(&mut body, kind);
        push(&mut body, fill);
        push(&mut body, fill_rgb);
        push(&mut body, layer);
        push(&mut body, param);
        push(&mut body, declared_text as u32);
        // A shape without a width, a height or both; for a contour, all its
        // points on one line.
        let degenerate = if rng.chance(15) {
            Some(rng.below(3))
        } else {
            None
        };
        let mut first = (0.0f32, 0.0f32);
        for i in 0..count {
            let mut x = random_coordinate(rng, w);
            let mut y = random_coordinate(rng, h);
            if i == 0 {
                first = (x, y);
            } else {
                match degenerate {
                    Some(0) => x = first.0,
                    Some(1) => y = first.1,
                    Some(_) => {
                        x = first.0;
                        y = first.1;
                    }
                    None => {}
                }
            }
            push(&mut body, x.to_bits());
            push(&mut body, y.to_bits());
        }
        body.extend_from_slice(&text);
        points_total += count;
        text_total += text.len();
    }
    let nudge = |rng: &mut Rng, value: usize| -> u32 {
        if rng.chance(40) {
            (value as u32).wrapping_add([1u32, u32::MAX][rng.below(2)])
        } else {
            value as u32
        }
    };
    let png_bytes: &[u8] = if with_png { png } else { &[] };
    let mut out = Vec::new();
    out.extend_from_slice(b"EDUPAINT");
    out.extend_from_slice(&version.to_le_bytes());
    out.extend_from_slice(&(if rng.chance(60) { 1u16 } else { 0u16 }).to_le_bytes());
    let total = 56 + table.len() * 8 + body.len() + png_bytes.len() + 4;
    push(&mut out, nudge(rng, total));
    push(&mut out, w);
    push(&mut out, h);
    push(&mut out, nudge(rng, object_count));
    push(&mut out, nudge(rng, points_total));
    push(&mut out, nudge(rng, png_bytes.len()));
    push(
        &mut out,
        if rng.chance(40) {
            layer_count as u32 + 1
        } else {
            layer_count as u32
        },
    );
    push(&mut out, nudge(rng, text_total));
    push(&mut out, active);
    push(&mut out, paper);
    push(&mut out, reserved);
    for (id, flags) in &table {
        push(&mut out, *id);
        push(&mut out, *flags);
    }
    out.extend_from_slice(&body);
    out.extend_from_slice(png_bytes);
    match rng.below(40) {
        0 => out.push(0),
        1 => {
            out.pop();
        }
        2 => out.extend_from_slice(&[0; 8]),
        _ => {}
    }
    let crc = slow_crc(&out);
    push(&mut out, if rng.chance(50) { crc ^ 1 } else { crc });
    // sometimes fix the declared total after the structural damage
    if rng.chance(2) && out.len() >= 16 {
        let len = out.len() as u32;
        out[12..16].copy_from_slice(&len.to_le_bytes());
        let end = out.len() - 4;
        let crc = slow_crc(&out[..end]);
        out[end..].copy_from_slice(&crc.to_le_bytes());
    }
    out
}

#[test]
fn the_reader_agrees_with_an_independent_oracle_on_structured_files() {
    // The PNG of a shipped fixture, and its size, for files with a background.
    let fixture = include_bytes!("../test-fixtures/import-project/text-on-image-v4.edupaint");
    let png_len = le32(fixture, 32).unwrap() as usize;
    let png = &fixture[fixture.len() - 4 - png_len..fixture.len() - 4];
    let png_size = (le32(fixture, 16).unwrap(), le32(fixture, 20).unwrap());
    let png_ok = |bytes: &[u8], w: u32, h: u32| bytes == png && (w, h) == png_size;

    let rounds: usize = std::env::var("EDUPAINT_ORACLE_ROUNDS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(30_000);
    let mut rng = Rng(0x5eed_0001);
    let (mut plain, mut layered, mut locked, mut invalid) = (0usize, 0usize, 0usize, 0usize);
    let mut lowered = 0usize;
    let mut reasons = std::collections::BTreeMap::<&'static str, usize>::new();
    let mut disagreements = Vec::new();
    for round in 0..rounds {
        let bytes = generate(&mut rng, png, png_size);
        let verdict = oracle(&bytes, &png_ok);
        let loaded = Owned::try_from_project(&bytes);
        match (&verdict, &loaded) {
            (Verdict::Invalid(reason), Err(status)) => {
                assert_eq!(*status, INVALID);
                invalid += 1;
                *reasons.entry(reason).or_default() += 1;
            }
            (Verdict::Invalid(reason), Ok(_)) => {
                if disagreements.len() < 10 {
                    disagreements.push(format!(
                        "round {round}: core ACCEPTS, oracle says invalid ({reason}): {bytes:02x?}"
                    ));
                }
            }
            (_, Err(status)) => {
                if disagreements.len() < 10 {
                    disagreements.push(format!("round {round}: core REJECTS ({status}), oracle says {verdict:?}: {bytes:02x?}"));
                }
            }
            (Verdict::Layered, Ok(doc)) => {
                layered += 1;
                let written = doc.project();
                if bytes[8] == 4 {
                    // canonical v4 is written back byte for byte
                    assert_eq!(written, bytes, "round {round}");
                } else {
                    // a v5 file without a lock or a contour comes back as v4,
                    // every other byte but the checksum unchanged
                    lowered += 1;
                    assert_eq!(written.len(), bytes.len(), "round {round}");
                    assert_eq!(written[8], 4, "round {round}");
                    let end = bytes.len() - 4;
                    assert_eq!(written[..8], bytes[..8], "round {round}");
                    assert_eq!(written[9..end], bytes[9..end], "round {round}");
                }
                doc.assert_accounting();
                assert!(doc.svg().ends_with("</svg>\n"));
                assert_eq!(doc.snapshot(), (written, doc.svg()));
            }
            (Verdict::Locked, Ok(doc)) => {
                locked += 1;
                // canonical v5 is written back byte for byte
                assert_eq!(doc.project(), bytes, "round {round}");
                doc.assert_accounting();
                assert!(doc.svg().ends_with("</svg>\n"));
                assert_eq!(doc.snapshot(), (bytes.clone(), doc.svg()));
            }
            (Verdict::Plain, Ok(doc)) => {
                plain += 1;
                let written = doc.project();
                assert!(written[8] == 2 || written[8] == 3, "round {round}");
                doc.assert_accounting();
            }
        }
    }
    eprintln!(
        "reader fuzz: {locked} canonical v5, {layered} v4 ({lowered} of them read as v5), \
         {plain} plain (down-converted), {invalid} invalid"
    );
    eprintln!("invalid reasons: {reasons:?}");
    for d in &disagreements {
        eprintln!("{d}");
    }
    assert!(
        disagreements.is_empty(),
        "{} disagreements",
        disagreements.len()
    );
    if rounds >= 30_000 {
        // Each outcome really occurs, or the comparison shows nothing.
        assert!(locked > 1000 && layered > 1000 && plain > 100 && invalid > 1000);
        assert!(lowered > 100);
    }
}

/// Random valid v4 and v5 files (accepted by the core), then the model-based
/// edit fuzz on top of each of them, including undo below the loaded state
/// and down to the objects of locked layers, which undo never takes away.
#[test]
fn edits_and_history_are_exact_on_random_loaded_projects() {
    let fixture = include_bytes!("../test-fixtures/import-project/text-on-image-v4.edupaint");
    let png_len = le32(fixture, 32).unwrap() as usize;
    let png = &fixture[fixture.len() - 4 - png_len..fixture.len() - 4];
    let png_size = (le32(fixture, 16).unwrap(), le32(fixture, 20).unwrap());
    let wanted: usize = std::env::var("EDUPAINT_MODEL_LOADED")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(40);
    let steps: usize = std::env::var("EDUPAINT_MODEL_STEPS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(150);
    let mut rng = Rng(0x10ad_ed00);
    let mut done = 0usize;
    let mut round = 0u64;
    while done < wanted {
        round += 1;
        let bytes = generate(&mut rng, png, png_size);
        let Ok(doc) = Owned::try_from_project(&bytes) else {
            continue;
        };
        if doc.count() == 0 && !done.is_multiple_of(3) {
            continue;
        }
        done += 1;
        crate::history_model_tests::run_on(doc, 0x7000 + round, steps, done.is_multiple_of(2));
    }
}
