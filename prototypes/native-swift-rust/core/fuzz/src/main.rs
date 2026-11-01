// SPDX-License-Identifier: MIT
//! The fuzzer of the reader of projects of Color (Q-01 of the retrospective
//! of October 2026), guided by coverage and written in Rust only: neither
//! libFuzzer nor anything in C. A project comes from someone else, and the
//! reader is the part of the core that a stranger's file reaches.
//!
//! LLVM instruments the code it compiles when it is asked to: it counts
//! every edge taken in a table of eight-bit counters, and calls a function
//! before every comparison. Those functions, which libFuzzer usually
//! provides, are written here: the counters say when an input reached code
//! that no input had reached, and the comparisons give the values that the
//! reader expects — its magic word, its versions, its lengths — for the
//! mutations to try.
//!
//! Built and run from the folder of the core, a release build at once
//! (the instrumentation counts in both, the reader is faster in this one):
//!
//! ```text
//! RUSTFLAGS="-C passes=sancov-module \
//!   -C llvm-args=-sanitizer-coverage-level=3 \
//!   -C llvm-args=-sanitizer-coverage-inline-8bit-counters \
//!   -C llvm-args=-sanitizer-coverage-trace-compares" \
//! cargo run --release --offline --manifest-path fuzz/Cargo.toml -- \
//!   --seconds 1800 --corpus fuzz/corpus test-fixtures/import-project
//! ```
//!
//! Every input that reaches new code is kept in the corpus folder, named
//! after its content; the folders after the options seed it. The counters
//! and the comparisons are those of the reading alone: cleared before it,
//! taken right after, never those of the fuzzer's own work, which LLVM
//! instruments too. An input that makes the core panic, or the process
//! abort (an allocation that fails, a stack that overflows), is written to
//! `fuzz/crashes/` before the process stops, and `--run <file>` plays one
//! input again. Each input is read as
//! it is, and once more with its declared length and its CRC32 made right,
//! so that the mutations go past the checks of the header into the records.
//! What is read is then written back, read again and written again: the
//! two writings must be the same bytes.
#![deny(unsafe_op_in_unsafe_fn)]

use std::collections::HashSet;
use std::fs;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicPtr, AtomicU64, AtomicUsize, Ordering};
use std::time::{Duration, Instant};

use edupaint_core::{
    ep_copy_project, ep_document_free, ep_document_from_project, ep_export_svg, ep_project_size,
    ep_string_free,
};

// The tables of counters that LLVM hands over before main, one per module
// of code: their bounds, kept as they come.
const MAX_REGIONS: usize = 256;
static REGION_STARTS: [AtomicPtr<u8>; MAX_REGIONS] =
    [const { AtomicPtr::new(ptr::null_mut()) }; MAX_REGIONS];
static REGION_ENDS: [AtomicPtr<u8>; MAX_REGIONS] =
    [const { AtomicPtr::new(ptr::null_mut()) }; MAX_REGIONS];
static REGIONS: AtomicUsize = AtomicUsize::new(0);

/// Called by the code that LLVM adds, once per module, before main.
///
/// # Safety
/// `start..end` is a table of counters that lives as long as the program.
#[no_mangle]
pub unsafe extern "C" fn __sanitizer_cov_8bit_counters_init(start: *mut u8, end: *mut u8) {
    if start.is_null() || end <= start {
        return;
    }
    let index = REGIONS.fetch_add(1, Ordering::Relaxed);
    if index < MAX_REGIONS {
        REGION_STARTS[index].store(start, Ordering::Relaxed);
        REGION_ENDS[index].store(end, Ordering::Relaxed);
    }
}

/// Called by the code that LLVM adds with `-sanitizer-coverage-pc-table`;
/// not asked for, present for a build that would ask for it.
#[no_mangle]
pub extern "C" fn __sanitizer_cov_pcs_init(_start: *const usize, _end: *const usize) {}

// The operands of recent comparisons, a pair in each place of a ring: what
// the mutations write into an input where one of them already is. Only those
// made while a project is read are kept: the fuzzer's own comparisons, which
// LLVM instruments too, would push the reader's out of the ring.
const COMPARISONS: usize = 4096;
static COMPARED: [AtomicU64; COMPARISONS * 2] = [const { AtomicU64::new(0) }; COMPARISONS * 2];
static NEXT_COMPARISON: AtomicUsize = AtomicUsize::new(0);
static RECORDING: AtomicBool = AtomicBool::new(false);

#[inline(always)]
fn compared(a: u64, b: u64) {
    if a == b || !RECORDING.load(Ordering::Relaxed) {
        return;
    }
    let slot = NEXT_COMPARISON.fetch_add(1, Ordering::Relaxed) % COMPARISONS;
    COMPARED[slot * 2].store(a, Ordering::Relaxed);
    COMPARED[slot * 2 + 1].store(b, Ordering::Relaxed);
}

#[no_mangle]
pub extern "C" fn __sanitizer_cov_trace_cmp1(a: u8, b: u8) {
    compared(a.into(), b.into());
}
#[no_mangle]
pub extern "C" fn __sanitizer_cov_trace_cmp2(a: u16, b: u16) {
    compared(a.into(), b.into());
}
#[no_mangle]
pub extern "C" fn __sanitizer_cov_trace_cmp4(a: u32, b: u32) {
    compared(a.into(), b.into());
}
#[no_mangle]
pub extern "C" fn __sanitizer_cov_trace_cmp8(a: u64, b: u64) {
    compared(a, b);
}
#[no_mangle]
pub extern "C" fn __sanitizer_cov_trace_const_cmp1(a: u8, b: u8) {
    compared(a.into(), b.into());
}
#[no_mangle]
pub extern "C" fn __sanitizer_cov_trace_const_cmp2(a: u16, b: u16) {
    compared(a.into(), b.into());
}
#[no_mangle]
pub extern "C" fn __sanitizer_cov_trace_const_cmp4(a: u32, b: u32) {
    compared(a.into(), b.into());
}
#[no_mangle]
pub extern "C" fn __sanitizer_cov_trace_const_cmp8(a: u64, b: u64) {
    compared(a, b);
}

/// A `match` on a value: `cases[0]` cases, of `cases[1]` bits, follow.
///
/// # Safety
/// `cases` is the table that LLVM made for this switch.
#[no_mangle]
pub unsafe extern "C" fn __sanitizer_cov_trace_switch(value: u64, cases: *const u64) {
    if cases.is_null() {
        return;
    }
    let count = unsafe { *cases } as usize;
    for index in 0..count.min(64) {
        compared(value, unsafe { *cases.add(2 + index) });
    }
}

/// Divisions and indices, should a build ask for them: nothing to learn.
#[no_mangle]
pub extern "C" fn __sanitizer_cov_trace_div4(_value: u32) {}
#[no_mangle]
pub extern "C" fn __sanitizer_cov_trace_div8(_value: u64) {}
#[no_mangle]
pub extern "C" fn __sanitizer_cov_trace_gep(_index: usize) {}

/// The counters of every region, as slices.
fn regions() -> Vec<&'static mut [u8]> {
    let count = REGIONS.load(Ordering::Relaxed).min(MAX_REGIONS);
    (0..count)
        .map(|index| {
            let start = REGION_STARTS[index].load(Ordering::Relaxed);
            let end = REGION_ENDS[index].load(Ordering::Relaxed);
            // The tables live as long as the program, and only this thread
            // runs instrumented code while they are read.
            unsafe { std::slice::from_raw_parts_mut(start, end.offset_from(start) as usize) }
        })
        .collect()
}

/// A counter read as one of eight classes of how many times its edge was
/// taken, as libFuzzer reads it: 1, 2, 3, 4 to 7, 8 to 15, 16 to 31, 32 to
/// 127, 128 and more.
fn class(count: u8) -> u8 {
    match count {
        0 => 0,
        1 => 1,
        2 => 2,
        3 => 3,
        4..=7 => 4,
        8..=15 => 5,
        16..=31 => 6,
        32..=127 => 7,
        _ => 8,
    }
}

/// What the inputs have reached so far: for every counter, the classes seen.
struct Coverage {
    seen: Vec<u16>,
    features: usize,
}

impl Coverage {
    fn new() -> Self {
        let size = regions().iter().map(|region| region.len()).sum();
        Self {
            seen: vec![0; size],
            features: 0,
        }
    }

    /// Clears every counter, for the next input.
    fn clear() {
        for region in regions() {
            region.fill(0);
        }
    }

    /// Takes what the last input reached and clears the counters: true when
    /// it reached something new.
    fn take(&mut self) -> bool {
        let mut new = false;
        let mut place = 0;
        for region in regions() {
            for counter in region.iter_mut() {
                if *counter != 0 {
                    let bit = 1u16 << class(*counter);
                    if let Some(seen) = self.seen.get_mut(place) {
                        if *seen & bit == 0 {
                            *seen |= bit;
                            self.features += 1;
                            new = true;
                        }
                    }
                    *counter = 0;
                }
                place += 1;
            }
        }
        new
    }
}

/// A small generator of pseudo-random numbers: xorshift64*.
struct Random(u64);

impl Random {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_f491_4f6c_dd1d)
    }

    fn below(&mut self, bound: usize) -> usize {
        if bound == 0 {
            0
        } else {
            (self.next() % bound as u64) as usize
        }
    }
}

/// The CRC32 of IEEE 802.3, the one the projects end with: computed here,
/// independently of the core's.
fn crc32(bytes: &[u8]) -> u32 {
    let mut table = [0u32; 256];
    for (index, entry) in table.iter_mut().enumerate() {
        let mut value = index as u32;
        for _ in 0..8 {
            value = if value & 1 != 0 {
                0xedb8_8320 ^ (value >> 1)
            } else {
                value >> 1
            };
        }
        *entry = value;
    }
    let mut crc = !0u32;
    for &byte in bytes {
        crc = table[((crc ^ u32::from(byte)) & 0xff) as usize] ^ (crc >> 8);
    }
    !crc
}

/// The same input with its declared length (bytes 12 to 15) and its CRC32
/// (the last four bytes) made right, when it is long enough to have them.
fn made_right(input: &[u8]) -> Option<Vec<u8>> {
    if input.len() < 20 {
        return None;
    }
    let mut fixed = input.to_vec();
    let length = fixed.len() as u32;
    fixed[12..16].copy_from_slice(&length.to_le_bytes());
    let end = fixed.len() - 4;
    let crc = crc32(&fixed[..end]);
    fixed[end..].copy_from_slice(&crc.to_le_bytes());
    Some(fixed)
}

/// The project that a document writes, or None.
///
/// # Safety
/// `document` is a live document of the core.
unsafe fn written(document: *const edupaint_core::EpDocument) -> Option<Vec<u8>> {
    let size = unsafe { ep_project_size(document) };
    if size == 0 {
        return None;
    }
    let mut bytes = vec![0u8; size];
    (unsafe { ep_copy_project(document, bytes.as_mut_ptr(), size) } == 0).then_some(bytes)
}

/// Reads [input] as a project and, when it is one, writes it, reads that
/// and writes it again: the two writings must be the same bytes. Exports it
/// as SVG too. Panics on any broken promise.
fn read(input: &[u8]) {
    let mut status = 0i32;
    let document = unsafe { ep_document_from_project(input.as_ptr(), input.len(), &mut status) };
    if document.is_null() {
        assert!(
            status == -1 || status == -2,
            "status {status} without a document"
        );
        return;
    }
    assert_eq!(status, 0, "a document with status {status}");
    let svg = unsafe { ep_export_svg(document) };
    if !svg.is_null() {
        unsafe { ep_string_free(svg) };
    }
    let first = unsafe { written(document) };
    unsafe { ep_document_free(document) };
    let Some(first) = first else {
        return;
    };
    let again = unsafe { ep_document_from_project(first.as_ptr(), first.len(), &mut status) };
    assert!(
        !again.is_null(),
        "a project written by the core is refused: {status}"
    );
    let second = unsafe { written(again) };
    unsafe { ep_document_free(again) };
    assert_eq!(Some(&first), second.as_ref(), "a second writing differs");
}

// The input being read, for the hook that writes it out if the core panics
// or the process aborts.
static CURRENT: std::sync::Mutex<Vec<u8>> = std::sync::Mutex::new(Vec::new());

/// Reads [input] as `read` does, as the only code the counters and the
/// comparisons see: they are cleared before, and taken right after by the
/// caller. What the fuzzer itself does between two readings — choosing,
/// mutating, repairing, counting — is never taken for the reader's.
fn observed(input: &[u8]) {
    Coverage::clear();
    RECORDING.store(true, Ordering::Relaxed);
    read(input);
    RECORDING.store(false, Ordering::Relaxed);
}

// Where an input that makes the process abort is written: an infallible
// allocation that fails, a stack that overflows, which no panic hook sees.
static CRASHES: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
const SIGABRT: i32 = 6;
extern "C" {
    fn signal(signum: i32, handler: extern "C" fn(i32)) -> usize;
}

/// The handler of SIGABRT: the input being read, written out as a panic's
/// would be. A process that aborts is going: done as best it can be.
extern "C" fn aborted(_signal: i32) {
    if let (Some(crashes), Ok(input)) = (CRASHES.get(), CURRENT.try_lock()) {
        let path = save(crashes, &input);
        eprintln!("abort: the input is in {}", path.display());
    }
}

fn name_of(input: &[u8]) -> String {
    // FNV-1a over the bytes: a name, not a security.
    let mut hash = 0xcbf2_9ce4_8422_2325u64;
    for &byte in input {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(0x0100_0000_01b3);
    }
    format!("{hash:016x}")
}

fn save(folder: &Path, input: &[u8]) -> PathBuf {
    let _ = fs::create_dir_all(folder);
    let path = folder.join(name_of(input));
    let _ = fs::write(&path, input);
    path
}

/// Values that readers of lengths and counts often meet at their edges.
const INTERESTING: [u64; 16] = [
    0,
    1,
    2,
    3,
    4,
    7,
    8,
    16,
    64,
    100,
    127,
    255,
    256,
    0x7fff,
    0xffff,
    0xffff_ffff,
];

fn mutate(input: &mut Vec<u8>, corpus: &[Vec<u8>], random: &mut Random) {
    let rounds = 1 + random.below(4);
    for _ in 0..rounds {
        let length = input.len();
        match random.below(11) {
            // A bit, then a byte.
            0 if length > 0 => {
                let at = random.below(length);
                input[at] ^= 1 << random.below(8);
            }
            1 if length > 0 => {
                let at = random.below(length);
                input[at] = random.next() as u8;
            }
            // A small number of 1, 2 or 4 bytes, little-endian.
            2 if length >= 4 => {
                let width = [1usize, 2, 4][random.below(3)];
                let at = random.below(length - width + 1);
                let value = INTERESTING[random.below(INTERESTING.len())];
                input[at..at + width].copy_from_slice(&value.to_le_bytes()[..width]);
            }
            // A number moved a little.
            3 if length >= 4 => {
                let at = random.below(length - 3);
                let mut word = [0u8; 4];
                word.copy_from_slice(&input[at..at + 4]);
                let delta = random.below(33) as i32 - 16;
                let value = u32::from_le_bytes(word).wrapping_add(delta as u32);
                input[at..at + 4].copy_from_slice(&value.to_le_bytes());
            }
            // Bytes inserted, removed, repeated.
            4 if length < 1 << 20 => {
                let at = random.below(length + 1);
                let count = 1 + random.below(16);
                let byte = random.next() as u8;
                input.splice(at..at, std::iter::repeat_n(byte, count));
            }
            5 if length > 1 => {
                let at = random.below(length);
                let count = 1 + random.below((length - at).min(32));
                input.drain(at..at + count);
            }
            6 if length > 1 => {
                let from = random.below(length);
                let count = 1 + random.below((length - from).min(64));
                let piece: Vec<u8> = input[from..from + count].to_vec();
                let at = random.below(input.len() + 1);
                input.splice(at..at, piece);
            }
            // A piece of another input of the corpus.
            7 if !corpus.is_empty() => {
                let other = &corpus[random.below(corpus.len())];
                if !other.is_empty() {
                    let from = random.below(other.len());
                    let count = 1 + random.below(other.len() - from);
                    let at = random.below(input.len() + 1);
                    let end = (at + count).min(input.len());
                    input.splice(at..end, other[from..from + count].iter().copied());
                }
            }
            // One side of a recent comparison replaced by the other one,
            // where the input holds it.
            8 | 9 => {
                let slot = random.below(COMPARISONS);
                let a = COMPARED[slot * 2].load(Ordering::Relaxed);
                let b = COMPARED[slot * 2 + 1].load(Ordering::Relaxed);
                let width = if a.max(b) <= 0xff {
                    1
                } else if a.max(b) <= 0xffff {
                    2
                } else if a.max(b) <= 0xffff_ffff {
                    4
                } else {
                    8
                };
                let (find, put) = if random.below(2) == 0 { (a, b) } else { (b, a) };
                let find = &find.to_le_bytes()[..width];
                let put = &put.to_le_bytes()[..width];
                if let Some(at) = input.windows(width).position(|window| window == find) {
                    input[at..at + width].copy_from_slice(put);
                } else if length >= width {
                    let at = random.below(length - width + 1);
                    input[at..at + width].copy_from_slice(put);
                }
            }
            // Cut at the end.
            _ if length > 1 => {
                input.truncate(random.below(length) + 1);
            }
            _ => input.push(random.next() as u8),
        }
    }
}

/// The inputs kept, what they reached, and how many readings were made.
struct Fuzzer {
    coverage: Coverage,
    corpus: Vec<Vec<u8>>,
    known: HashSet<String>,
    executions: u64,
    folder: PathBuf,
}

impl Fuzzer {
    /// Reads [input], and the same with its length and its CRC made right;
    /// keeps each one that reached new code.
    fn try_input(&mut self, input: &[u8]) {
        *CURRENT.lock().unwrap() = input.to_vec();
        observed(input);
        self.executions += 1;
        let new = self.coverage.take();
        if let Some(fixed) = made_right(input) {
            *CURRENT.lock().unwrap() = fixed.clone();
            observed(&fixed);
            self.executions += 1;
            if self.coverage.take() && self.known.insert(name_of(&fixed)) {
                save(&self.folder, &fixed);
                self.corpus.push(fixed);
            }
        }
        if new && self.known.insert(name_of(input)) {
            save(&self.folder, input);
            self.corpus.push(input.to_vec());
        }
    }
}

struct Options {
    seconds: u64,
    corpus: PathBuf,
    seeds: Vec<PathBuf>,
    run: Option<PathBuf>,
    seed: u64,
}

fn options() -> Options {
    let mut options = Options {
        seconds: 60,
        corpus: PathBuf::from("fuzz/corpus"),
        seeds: Vec::new(),
        run: None,
        seed: 0x00c0_10f0,
    };
    let mut arguments = std::env::args().skip(1);
    while let Some(argument) = arguments.next() {
        match argument.as_str() {
            "--seconds" => {
                options.seconds = arguments.next().and_then(|v| v.parse().ok()).unwrap_or(60);
            }
            "--corpus" => {
                options.corpus = arguments
                    .next()
                    .map(PathBuf::from)
                    .unwrap_or(options.corpus);
            }
            "--run" => options.run = arguments.next().map(PathBuf::from),
            "--seed" => {
                options.seed = arguments.next().and_then(|v| v.parse().ok()).unwrap_or(1);
            }
            other => options.seeds.push(PathBuf::from(other)),
        }
    }
    options
}

fn inputs_of(folder: &Path) -> Vec<Vec<u8>> {
    let Ok(entries) = fs::read_dir(folder) else {
        return Vec::new();
    };
    let mut paths: Vec<PathBuf> = entries
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.is_file())
        .collect();
    paths.sort();
    paths
        .into_iter()
        .filter_map(|path| fs::read(path).ok())
        .filter(|bytes| bytes.len() <= 1 << 20)
        .collect()
}

fn main() {
    let options = options();
    let crashes = options
        .corpus
        .parent()
        .unwrap_or(Path::new("."))
        .join("crashes");
    let _ = CRASHES.set(crashes.clone());
    unsafe { signal(SIGABRT, aborted) };
    {
        let crashes = crashes.clone();
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            if let Ok(input) = CURRENT.lock() {
                let path = save(&crashes, &input);
                eprintln!("panic: the input is in {}", path.display());
            }
            previous(info);
        }));
    }
    if let Some(path) = options.run {
        let input = fs::read(&path).expect("the input to play");
        *CURRENT.lock().unwrap() = input.clone();
        read(&input);
        if let Some(fixed) = made_right(&input) {
            read(&fixed);
        }
        println!("{} read without a panic", path.display());
        return;
    }
    if REGIONS.load(Ordering::Relaxed) == 0 {
        eprintln!("No counter from LLVM: build with the RUSTFLAGS of src/main.rs.");
        std::process::exit(2);
    }
    let mut fuzzer = Fuzzer {
        coverage: Coverage::new(),
        corpus: Vec::new(),
        known: HashSet::new(),
        executions: 0,
        folder: options.corpus.clone(),
    };
    Coverage::clear();
    let mut seeds = inputs_of(&options.corpus);
    for folder in &options.seeds {
        seeds.extend(inputs_of(folder));
    }
    let seeded = seeds.len();
    for seed in seeds {
        fuzzer.try_input(&seed);
        if fuzzer.known.insert(name_of(&seed)) {
            fuzzer.corpus.push(seed);
        }
    }
    println!(
        "{seeded} inputs to start from, {} kept, {} features",
        fuzzer.corpus.len(),
        fuzzer.coverage.features
    );
    let mut random = Random(options.seed | 1);
    let started = Instant::now();
    let budget = Duration::from_secs(options.seconds);
    let mut told = Instant::now();
    let mut input = Vec::new();
    while started.elapsed() < budget {
        if fuzzer.corpus.is_empty() {
            input.clear();
            input.extend_from_slice(b"EDUPAINT");
        } else {
            input.clone_from(&fuzzer.corpus[random.below(fuzzer.corpus.len())]);
        }
        mutate(&mut input, &fuzzer.corpus, &mut random);
        let snapshot = input.clone();
        fuzzer.try_input(&snapshot);
        if told.elapsed() >= Duration::from_secs(10) {
            told = Instant::now();
            println!(
                "{:>6} s · {} readings · {} inputs kept · {} features",
                started.elapsed().as_secs(),
                fuzzer.executions,
                fuzzer.corpus.len(),
                fuzzer.coverage.features
            );
            let _ = std::io::stdout().flush();
        }
    }
    let Fuzzer {
        coverage,
        corpus,
        executions,
        ..
    } = fuzzer;
    println!(
        "End after {} s: {executions} readings, {} inputs kept, {} features, no panic.",
        started.elapsed().as_secs(),
        corpus.len(),
        coverage.features
    );
}
