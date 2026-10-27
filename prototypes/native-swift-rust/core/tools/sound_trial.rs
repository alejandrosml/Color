// SPDX-License-Identifier: MIT
//! Trial of the sounds through the built library, loaded as the interface
//! loads it: every call below goes through the exported C functions.
//! Standard library only; compile with rustc alone.
//!
//!   rustc --edition=2021 -O tools/sound_trial.rs -o sound_trial
//!   sound_trial LIBRARY list                sizes, lengths, time of rendering
//!   sound_trial LIBRARY wav FOLDER          one FOLDER/<id>-<key>.wav per sound
//!   sound_trial LIBRARY play ID|all [MS]    plays, waits for the end plus MS
//!   sound_trial LIBRARY burst ID COUNT [MS [GAP]]
//!                                           COUNT calls GAP ms apart (in a row
//!                                           unless GAP is given), then waits MS
//!
//! On Linux the device is `default` unless COLOR_ALSA_DEVICE names another:
//! `null` plays into nothing, `file:'/tmp/out.raw',raw` writes what was
//! played. The variable is read once per process. Where ep_sound_play
//! answers 1 (macOS), `wav` writes the files for the system's own player.
use std::ffi::{c_char, c_void, CStr};
use std::time::{Duration, Instant};

#[cfg(unix)]
mod library {
    use std::ffi::{c_char, c_int, c_void, CString};
    extern "C" {
        fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
        fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    }
    pub fn open(path: &str) -> *mut c_void {
        let path = CString::new(path).expect("path without NUL");
        unsafe { dlopen(path.as_ptr(), 2) }
    }
    pub fn symbol(library: *mut c_void, name: &str) -> *mut c_void {
        let name = CString::new(name).expect("name without NUL");
        unsafe { dlsym(library, name.as_ptr()) }
    }
}

#[cfg(windows)]
mod library {
    use std::ffi::{c_char, c_void, CString};
    use std::os::windows::ffi::OsStrExt;
    extern "system" {
        fn LoadLibraryW(name: *const u16) -> *mut c_void;
        fn GetProcAddress(module: *mut c_void, name: *const c_char) -> *mut c_void;
    }
    pub fn open(path: &str) -> *mut c_void {
        let wide: Vec<u16> = std::ffi::OsStr::new(path)
            .encode_wide()
            .chain(Some(0))
            .collect();
        unsafe { LoadLibraryW(wide.as_ptr()) }
    }
    pub fn symbol(library: *mut c_void, name: &str) -> *mut c_void {
        let name = CString::new(name).expect("name without NUL");
        unsafe { GetProcAddress(library, name.as_ptr()) }
    }
}

struct Core {
    count: unsafe extern "C" fn() -> u32,
    names: unsafe extern "C" fn() -> *mut c_char,
    wav_size: unsafe extern "C" fn(u32) -> usize,
    copy_wav: unsafe extern "C" fn(u32, *mut u8, usize) -> usize,
    play: unsafe extern "C" fn(u32) -> i32,
    string_free: unsafe extern "C" fn(*mut c_char),
}

impl Core {
    fn load(path: &str) -> Self {
        let library = library::open(path);
        assert!(!library.is_null(), "cannot load {path}");
        let find = |name: &str| {
            let symbol = library::symbol(library, name);
            assert!(!symbol.is_null(), "{path} does not export {name}");
            symbol
        };
        unsafe {
            Self {
                count: std::mem::transmute::<*mut c_void, unsafe extern "C" fn() -> u32>(find(
                    "ep_sound_count",
                )),
                names: std::mem::transmute::<*mut c_void, unsafe extern "C" fn() -> *mut c_char>(
                    find("ep_sound_names"),
                ),
                wav_size: std::mem::transmute::<*mut c_void, unsafe extern "C" fn(u32) -> usize>(
                    find("ep_sound_wav_size"),
                ),
                copy_wav: std::mem::transmute::<
                    *mut c_void,
                    unsafe extern "C" fn(u32, *mut u8, usize) -> usize,
                >(find("ep_copy_sound_wav")),
                play: std::mem::transmute::<*mut c_void, unsafe extern "C" fn(u32) -> i32>(find(
                    "ep_sound_play",
                )),
                string_free: std::mem::transmute::<*mut c_void, unsafe extern "C" fn(*mut c_char)>(
                    find("ep_string_free"),
                ),
            }
        }
    }

    /// The keys, in identifier order, checked against the announced count.
    fn keys(&self) -> Vec<String> {
        let raw = unsafe { (self.names)() };
        assert!(!raw.is_null(), "ep_sound_names returned NULL");
        let text = unsafe { CStr::from_ptr(raw) }
            .to_str()
            .expect("ASCII")
            .to_owned();
        unsafe { (self.string_free)(raw) };
        let keys: Vec<String> = text
            .lines()
            .enumerate()
            .map(|(id, line)| {
                let (number, key) = line.split_once('|').expect("id|key");
                assert_eq!(number, id.to_string());
                key.to_owned()
            })
            .collect();
        assert_eq!(keys.len(), unsafe { (self.count)() } as usize);
        keys
    }

    fn wav(&self, id: u32) -> Vec<u8> {
        let size = unsafe { (self.wav_size)(id) };
        assert!(size > 44, "sound {id} has no WAV file");
        let mut bytes = vec![0u8; size];
        let copied = unsafe { (self.copy_wav)(id, bytes.as_mut_ptr(), bytes.len()) };
        assert_eq!(copied, size);
        bytes
    }

    fn duration(&self, id: u32) -> Duration {
        let frames = (unsafe { (self.wav_size)(id) } - 44) / 2;
        Duration::from_micros(frames as u64 * 1_000_000 / 44_100)
    }
}

fn usage() -> ! {
    eprintln!(
        "usage: sound_trial LIBRARY list | wav FOLDER | play ID|all [MS] | burst ID COUNT [MS [GAP]]"
    );
    std::process::exit(2)
}

fn main() {
    let arguments: Vec<String> = std::env::args().collect();
    let argument = |index: usize| arguments.get(index).map(String::as_str);
    let (Some(path), Some(command)) = (argument(1), argument(2)) else {
        usage()
    };
    let number = |index: usize, default: u64| {
        argument(index).map_or(default, |text| text.parse().unwrap_or_else(|_| usage()))
    };
    let core = Core::load(path);
    let keys = core.keys();
    match command {
        "list" => {
            for (id, key) in keys.iter().enumerate() {
                let id = id as u32;
                // The first copy renders the sound, the second only copies.
                let before = Instant::now();
                core.wav(id);
                let first = before.elapsed();
                let before = Instant::now();
                core.wav(id);
                println!(
                    "{id}|{key}|{} bytes|{} ms|rendered in {} µs, then copied in {} µs",
                    unsafe { (core.wav_size)(id) },
                    core.duration(id).as_millis(),
                    first.as_micros(),
                    before.elapsed().as_micros()
                );
            }
        }
        "wav" => {
            let folder = std::path::PathBuf::from(argument(3).unwrap_or_else(|| usage()));
            std::fs::create_dir_all(&folder).expect("folder");
            for (id, key) in keys.iter().enumerate() {
                let file = folder.join(format!("{id}-{key}.wav"));
                std::fs::write(&file, core.wav(id as u32)).expect("write");
                println!("{}", file.display());
            }
        }
        "play" => {
            let which = argument(3).unwrap_or_else(|| usage());
            let ids: Vec<u32> = if which == "all" {
                (0..keys.len() as u32).collect()
            } else {
                vec![which.parse().unwrap_or_else(|_| usage())]
            };
            let pause = Duration::from_millis(number(4, 250));
            for id in ids {
                let before = Instant::now();
                let result = unsafe { (core.play)(id) };
                let took = before.elapsed();
                let key = keys.get(id as usize).map_or("?", String::as_str);
                println!(
                    "ep_sound_play({id} {key}) = {result} in {} µs",
                    took.as_micros()
                );
                if result == 0 {
                    std::thread::sleep(core.duration(id) + pause);
                }
            }
        }
        "burst" => {
            let id = number(3, u64::MAX) as u32;
            let count = number(4, 0) as usize;
            let wait = Duration::from_millis(number(5, 0));
            let gap = Duration::from_millis(number(6, 0));
            let mut results = [0usize; 3];
            let mut times = Vec::with_capacity(count);
            for _ in 0..count {
                let before = Instant::now();
                let result = unsafe { (core.play)(id) };
                times.push(before.elapsed());
                results[match result {
                    0 => 0,
                    1 => 1,
                    _ => 2,
                }] += 1;
                if !gap.is_zero() {
                    std::thread::sleep(gap);
                }
            }
            times.sort();
            println!(
                "{count} calls: {} returned 0, {} returned 1, {} something else; \
                 median {} µs, longest {} µs",
                results[0],
                results[1],
                results[2],
                times.get(count / 2).map_or(0, Duration::as_micros),
                times.last().map_or(0, Duration::as_micros)
            );
            std::thread::sleep(wait);
        }
        _ => usage(),
    }
}
