use super::*;
use std::ffi::CStr;

// Identifiers are used by the interface. This list may only grow at its end.
const FROZEN_KEYS: [&str; 18] = [
    "outil",
    "couleur",
    "trait",
    "forme",
    "tampon",
    "pot",
    "gomme",
    "annuler",
    "retablir",
    "feuille",
    "enregistre",
    "oups",
    "film",
    "bravo",
    "clic",
    "texte",
    "choisir",
    "imprime",
];
// The length each of them was described with, in milliseconds; for a
// recording, that of its extract in sons/PROVENANCE.md.
const DESCRIBED_MS: [usize; 18] = [
    70, 110, 480, 320, 290, 900, 480, 160, 160, 250, 600, 300, 450, 700, 30, 390, 51, 300,
];
// 32 768 at -10 dBFS and at -16 dBFS, rounded down.
const TONAL_CEILING: i32 = 10_362;
const NOISE_CEILING: i32 = 5_193;

fn wav_file(id: u32) -> Vec<u8> {
    let mut bytes = vec![0u8; ep_sound_wav_size(id)];
    let copied = unsafe { ep_copy_sound_wav(id, bytes.as_mut_ptr(), bytes.len()) };
    assert_eq!(copied, bytes.len(), "sound {id}");
    bytes
}

fn word(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap())
}

fn half(bytes: &[u8], offset: usize) -> u16 {
    u16::from_le_bytes(bytes[offset..offset + 2].try_into().unwrap())
}

/// The samples of a sound as a player would read them, after every field
/// of the RIFF, format and data headers has been checked.
fn samples(id: u32) -> Vec<i16> {
    let bytes = wav_file(id);
    assert!(bytes.len() > WAV_HEADER_BYTES, "sound {id}");
    assert_eq!(&bytes[..4], b"RIFF");
    assert_eq!(word(&bytes, 4) as usize, bytes.len() - 8);
    assert_eq!(&bytes[8..16], b"WAVEfmt ");
    assert_eq!(word(&bytes, 16), 16, "bytes of the format block");
    assert_eq!(half(&bytes, 20), 1, "PCM");
    assert_eq!(half(&bytes, 22), 1, "one channel");
    assert_eq!(word(&bytes, 24), 44_100);
    assert_eq!(word(&bytes, 28), 88_200, "bytes per second");
    assert_eq!(half(&bytes, 32), 2, "bytes per frame");
    assert_eq!(half(&bytes, 34), 16, "bits per sample");
    assert_eq!(&bytes[36..40], b"data");
    let data = word(&bytes, 40) as usize;
    assert_eq!(data, bytes.len() - WAV_HEADER_BYTES);
    assert_eq!(data % 2, 0);
    let (pairs, odd) = bytes[WAV_HEADER_BYTES..].as_chunks::<2>();
    assert!(odd.is_empty());
    pairs.iter().map(|pair| i16::from_le_bytes(*pair)).collect()
}

fn peak(samples: &[i16]) -> i32 {
    samples
        .iter()
        .map(|sample| i32::from(*sample).abs())
        .max()
        .unwrap()
}

fn ms(milliseconds: usize) -> usize {
    milliseconds * RATE as usize / 1000
}

fn uses_noise(sound: &Sound) -> bool {
    match sound.making {
        Making::Recipe(voices) => voices
            .iter()
            .any(|voice| matches!(voice.source, Source::Noise)),
        // What a microphone heard counts as noise for every limit below.
        Making::Recording(_) => true,
    }
}

/// The key, the bytes compiled in, and the identifier of every recording.
fn recordings() -> Vec<(&'static str, &'static [u8], u32)> {
    SOUNDS
        .iter()
        .enumerate()
        .filter_map(|(id, sound)| match sound.making {
            Making::Recording(wav) => Some((sound.key, wav, id as u32)),
            Making::Recipe(_) => None,
        })
        .collect()
}

/// Where the energy of a stretch lies, from its steepness against its size:
/// 2·sin(π·f/rate) for a sine of frequency f.
fn centre(samples: &[i16]) -> f64 {
    let energy: f64 = samples.iter().map(|s| f64::from(*s).powi(2)).sum();
    let steepness: f64 = samples
        .windows(2)
        .map(|pair| (f64::from(pair[1]) - f64::from(pair[0])).powi(2))
        .sum();
    let centre = (steepness / energy).sqrt().min(2.0) / 2.0;
    centre.asin() * f64::from(RATE) / std::f64::consts::PI
}

/// The largest sample a sound may hold: noise, and the tick heard at every
/// stroke, stay a step lower than the sounds that have a pitch.
fn ceiling(sound: &Sound) -> i32 {
    if uses_noise(sound) || sound.key == "trait" {
        NOISE_CEILING
    } else {
        TONAL_CEILING
    }
}

/// Share of the power of a stretch that one frequency holds, by Goertzel's
/// recurrence: 1 for a steady sine of that frequency, next to nothing for
/// any other, and for noise.
fn share(samples: &[i16], hertz: f64) -> f64 {
    let turn = 2.0 * (TAU * hertz / f64::from(RATE)).cos();
    let (mut last, mut before) = (0.0, 0.0);
    let mut total = 0.0;
    for sample in samples {
        let value = f64::from(*sample);
        total += value * value;
        (last, before) = (value + turn * last - before, last);
    }
    let power = last * last + before * before - turn * last * before;
    2.0 * power / (samples.len() as f64 * total)
}

/// The frequency that holds most of a stretch, looked for every 4 Hz.
fn pitch(samples: &[i16], low: u32, high: u32) -> f64 {
    let mut best = (0.0, 0.0);
    for hertz in (low..=high).step_by(4) {
        let found = share(samples, f64::from(hertz));
        if found > best.1 {
            best = (f64::from(hertz), found);
        }
    }
    best.0
}

#[test]
fn catalogue_identifiers_are_frozen_and_keys_are_unique_lowercase_ascii() {
    assert!(SOUNDS.len() >= FROZEN_KEYS.len());
    assert_eq!(ep_sound_count() as usize, SOUNDS.len());
    for (id, key) in FROZEN_KEYS.iter().enumerate() {
        assert_eq!(SOUNDS[id].key, *key, "sound {id} changed identity");
    }
    let mut keys: Vec<_> = SOUNDS.iter().map(|sound| sound.key).collect();
    keys.sort_unstable();
    keys.dedup();
    assert_eq!(keys.len(), SOUNDS.len(), "duplicate key");
    for sound in &SOUNDS {
        assert!(!sound.key.is_empty());
        assert!(sound.key.bytes().all(|byte| byte.is_ascii_lowercase()));
    }
}

#[test]
fn names_list_every_sound_once_and_are_released_by_the_string_free() {
    let raw = ep_sound_names();
    assert!(!raw.is_null());
    let text = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_owned();
    unsafe { ep_string_free(raw) };
    assert!(text.is_ascii());
    let lines: Vec<_> = text.lines().collect();
    assert_eq!(lines.len(), SOUNDS.len());
    for (id, line) in lines.iter().enumerate() {
        assert_eq!(*line, format!("{id}|{}", SOUNDS[id].key));
    }
    assert_eq!(text.len(), text.trim_end().len() + 1, "one final newline");
    // The first eighteen lines are the contract the interface was given.
    for (id, key) in FROZEN_KEYS.iter().enumerate() {
        assert_eq!(lines[id], format!("{id}|{key}"));
    }
}

#[test]
fn recipes_keep_to_the_rules_that_make_them_gentle() {
    for sound in &SOUNDS {
        let key = sound.key;
        assert!(
            (1000..=ceiling(sound)).contains(&i32::from(sound.peak)),
            "{key}"
        );
        // A second at most, its last frame of silence included.
        assert!(frame_count(sound) <= MAX_FRAMES, "{key}: over a second");
        let Making::Recipe(voices) = sound.making else {
            continue;
        };
        assert!(!voices.is_empty(), "{key}");
        for voice in voices {
            assert!(voice.attack >= 3, "{key}: an attack that clicks");
            assert!(voice.attack < voice.length, "{key}");
            assert!(voice.length >= 20, "{key}");
            assert!(voice.level.is_finite() && voice.level != 0.0, "{key}");
            for pitch in [voice.from, voice.to] {
                assert!((100.0..=5000.0).contains(&pitch), "{key}: {pitch} Hz");
            }
            if let Source::Partials(partials) = voice.source {
                assert!(!partials.is_empty(), "{key}");
                for Partial(ratio, level, decay) in partials {
                    assert!(*ratio >= 1.0 && level.is_finite() && *decay > 0.0);
                    // Far under half the rate: no partial can fold back.
                    let highest = ratio * voice.from.max(voice.to);
                    assert!(highest <= 6000.0, "{key}: a partial at {highest} Hz");
                }
            }
        }
    }
}

#[test]
fn every_sound_is_a_complete_wav_file_of_the_announced_size_and_length() {
    for id in 0..ep_sound_count() {
        let sound = &SOUNDS[id as usize];
        let samples = samples(id);
        assert_eq!(samples.len(), frame_count(sound), "{}", sound.key);
        assert_eq!(
            ep_sound_wav_size(id),
            WAV_HEADER_BYTES + 2 * samples.len(),
            "{}",
            sound.key
        );
        // Nobody listens to feedback for more than a second.
        assert!(samples.len() <= MAX_FRAMES, "{}", sound.key);
        if let Some(described) = DESCRIBED_MS.get(id as usize) {
            let length = samples.len() - 1;
            assert!(
                (ms(*described) * 9 / 10..=ms(*described) * 11 / 10).contains(&length),
                "{}: {length} frames for {described} ms",
                sound.key
            );
        }
    }
    assert_eq!(ep_sound_wav_size(ep_sound_count()), 0);
    assert_eq!(ep_sound_wav_size(u32::MAX), 0);
}

#[test]
fn levels_are_exactly_the_announced_peaks_and_no_sound_is_silent() {
    for id in 0..ep_sound_count() {
        let sound = &SOUNDS[id as usize];
        let samples = samples(id);
        // Scaled to its peak, to the unit: nothing clips, nothing surprises,
        // and the samples themselves keep under -10 dBFS or -16 dBFS.
        assert_eq!(peak(&samples), i32::from(sound.peak), "{}", sound.key);
        assert!(peak(&samples) <= ceiling(sound), "{}", sound.key);
        let energy: f64 = samples.iter().map(|s| f64::from(*s).powi(2)).sum();
        let rms = (energy / samples.len() as f64).sqrt();
        assert!(rms >= 500.0, "{}: rms {rms}", sound.key);
        assert!(rms >= f64::from(sound.peak) / 10.0, "{}", sound.key);
        // No constant push on the loudspeaker: the samples sum to zero, up
        // to what their rounding leaves.
        let sum: i64 = samples.iter().map(|s| i64::from(*s)).sum();
        assert!(
            sum.unsigned_abs() as usize <= samples.len() / 4,
            "{}: sum {sum}",
            sound.key
        );
    }
}

#[test]
fn every_sound_rises_from_silence_and_returns_to_it_without_a_click() {
    for id in 0..ep_sound_count() {
        let key = SOUNDS[id as usize].key;
        let samples = samples(id);
        let peak = peak(&samples);
        let level = |sample: &i16| i32::from(*sample).abs();
        assert_eq!((samples[0], samples[samples.len() - 1]), (0, 0), "{key}");
        // Half a millisecond in, a sound is still far from its peak, and it
        // has not reached half of it within a millisecond.
        let early = samples[..=ms(1) / 2].iter().map(level).max().unwrap();
        assert!(early * 5 <= peak, "{key}: {early} of {peak}");
        let half = samples.iter().position(|s| level(s) * 2 >= peak).unwrap();
        assert!(half >= ms(1), "{key}: half its peak after {half} frames");
        // The last two milliseconds are the end of a release, not a cut.
        let late = samples[samples.len() - ms(2)..]
            .iter()
            .map(level)
            .max()
            .unwrap();
        assert!(late * 50 <= peak, "{key}: {late} of {peak}");
        // And between two neighbours there is never a jump of the size of
        // the sound itself, except in a recording made of clicks.
        let step = samples
            .windows(2)
            .map(|pair| (i32::from(pair[1]) - i32::from(pair[0])).abs())
            .max()
            .unwrap();
        let sharp = CLICKS
            .iter()
            .find(|(clicks, _, _)| *clicks == key)
            .map_or(6, |(_, tenths, _)| *tenths);
        assert!(step * 10 <= peak * sharp, "{key}: a step of {step}");
    }
}

// The recordings whose very nature is a click: the largest jump between two
// neighbours each may make, in tenths of its peak (6 for every other sound),
// and the highest centre its energy may have (4 kHz for every other noise).
// Each strike of a typewriter rises by 0.86 of the peak from one sample to
// the next, and the three strikes are centred on 4011 Hz: that edge is what
// makes them a typewriter, and it cannot be softened without dulling it.
// scripts/sons/preparer-les-sons.py allows the same jumps and no more.
const CLICKS: [(&str, i32, f64); 1] = [("texte", 9, 4100.0)];

#[test]
fn no_two_sounds_are_alike_and_a_second_rendering_gives_the_same_bytes() {
    let files: Vec<_> = (0..ep_sound_count()).map(wav_file).collect();
    for (id, file) in files.iter().enumerate() {
        for (other, earlier) in files[..id].iter().enumerate() {
            assert_ne!(
                file[WAV_HEADER_BYTES..],
                earlier[WAV_HEADER_BYTES..],
                "{id} and {other}"
            );
        }
        // Not the cache answering twice: the recipe rendered again.
        assert_eq!(render(id as u32).as_deref(), Some(file.as_slice()));
        assert_eq!(wav(id as u32), Some(file.as_slice()));
    }
    assert!(render(ep_sound_count()).is_none());
    assert!(wav(ep_sound_count()).is_none());
}

// CRC-32 of every WAV file. The samples are meant to be the same to the
// bit on every processor and system: this test says so wherever it runs.
// After a deliberate change of a recipe, or of a recording prepared again,
// copy the new values from its message.
const PINNED: [u32; 18] = [
    0x8471_6b01,
    0x66aa_0255,
    0x1ece_6300,
    0x7b67_90e4,
    0x1da8_e00b,
    0x9683_6db2,
    0x0e95_f18e,
    0xc687_247c,
    0x54f8_9590,
    0xc02e_efa0,
    0xcd56_5683,
    0x3f6d_db29,
    0x8056_fdd3,
    0x76d0_364b,
    0xdea3_39d9,
    0x56d9_d961,
    0x483a_47d8,
    0xe73b_4b7d,
];

#[test]
fn every_platform_renders_the_pinned_bytes() {
    let found: Vec<u32> = (0..ep_sound_count())
        .map(|id| crc32(&wav_file(id)))
        .collect();
    assert_eq!(found[..PINNED.len()], PINNED, "rendered: {found:#010x?}");
}

#[test]
fn copying_writes_the_whole_file_or_nothing_and_never_beyond_it() {
    const GUARD: u8 = 0xa5;
    for id in 0..ep_sound_count() {
        let expected = wav_file(id);
        let size = expected.len();
        let mut buffer = vec![GUARD; size + 64];
        unsafe {
            // One byte short: nothing is written, not even a header.
            assert_eq!(ep_copy_sound_wav(id, buffer.as_mut_ptr(), size - 1), 0);
            assert_eq!(ep_copy_sound_wav(id, buffer.as_mut_ptr(), 0), 0);
            assert!(buffer.iter().all(|byte| *byte == GUARD));
            assert_eq!(ep_copy_sound_wav(id, ptr::null_mut(), size), 0);
            assert_eq!(ep_copy_sound_wav(id, ptr::null_mut(), usize::MAX), 0);
            // The exact size, then more room than needed.
            assert_eq!(ep_copy_sound_wav(id, buffer.as_mut_ptr(), size), size);
            assert_eq!(buffer[..size], expected[..]);
            assert!(buffer[size..].iter().all(|byte| *byte == GUARD));
            buffer.fill(GUARD);
            let room = buffer.len();
            assert_eq!(ep_copy_sound_wav(id, buffer.as_mut_ptr(), room), size);
            assert_eq!(buffer[..size], expected[..]);
            assert!(buffer[size..].iter().all(|byte| *byte == GUARD));
        }
    }
    let mut buffer = vec![GUARD; 1 << 16];
    for unknown in [ep_sound_count(), ep_sound_count() + 1, u32::MAX] {
        let copied = unsafe { ep_copy_sound_wav(unknown, buffer.as_mut_ptr(), buffer.len()) };
        assert_eq!(copied, 0);
        assert!(buffer.iter().all(|byte| *byte == GUARD));
    }
}

#[test]
fn threads_asking_at_once_all_get_the_one_rendering() {
    // Rendered by whichever thread comes first; the others wait or lose.
    let files: Vec<Vec<(usize, Vec<u8>)>> = std::thread::scope(|scope| {
        let threads: Vec<_> = (0..4)
            .map(|_| {
                scope.spawn(|| {
                    (0..ep_sound_count())
                        .rev()
                        .map(|id| (wav(id).unwrap().as_ptr() as usize, wav_file(id)))
                        .collect()
                })
            })
            .collect();
        threads
            .into_iter()
            .map(|thread| thread.join().unwrap())
            .collect()
    });
    for other in &files[1..] {
        assert_eq!(*other, files[0]);
    }
    // The address handed to the players is the same for all, and for good.
    for (id, (address, file)) in files[0].iter().rev().enumerate() {
        assert_eq!(wav(id as u32).unwrap().as_ptr() as usize, *address);
        assert_eq!(wav(id as u32).unwrap(), file.as_slice());
    }
}

#[test]
fn glides_go_the_way_they_are_described() {
    let glide = |key: &str, early: (usize, usize), late: (usize, usize)| {
        let id = FROZEN_KEYS
            .iter()
            .position(|frozen| *frozen == key)
            .unwrap();
        let samples = samples(id as u32);
        (
            pitch(&samples[ms(early.0)..ms(early.1)], 200, 1400),
            pitch(&samples[ms(late.0)..ms(late.1)], 200, 1400),
        )
    };
    // Undo comes down from about 700 Hz towards 350, redo goes back up.
    let (start, end) = glide("annuler", (5, 45), (115, 155));
    assert!((600.0..=700.0).contains(&start), "{start}");
    assert!((350.0..=450.0).contains(&end), "{end}");
    let (start, end) = glide("retablir", (5, 45), (115, 155));
    assert!((350.0..=450.0).contains(&start), "{start}");
    assert!((600.0..=700.0).contains(&end), "{end}");
    // The pop of a tool rises, the drop of a colour falls.
    let (start, end) = glide("outil", (2, 22), (45, 68));
    assert!((520.0..=620.0).contains(&start), "{start}");
    assert!((680.0..=780.0).contains(&end), "{end}");
    let (start, end) = glide("couleur", (3, 33), (75, 108));
    assert!((580.0..=660.0).contains(&start), "{start}");
    assert!((440.0..=520.0).contains(&end), "{end}");
    // The click, alone or before the bell of a text, is a short high tick.
    let (start, _) = glide("clic", (1, 12), (1, 12));
    assert!((1300.0..=1500.0).contains(&start), "{start}");
}

#[test]
fn notes_sound_at_their_pitch_and_in_their_order() {
    let note = |key: &str, from: usize, to: usize| {
        let id = FROZEN_KEYS
            .iter()
            .position(|frozen| *frozen == key)
            .unwrap();
        pitch(&samples(id as u32)[ms(from)..ms(to)], 250, 1500)
    };
    let near = |found: f64, note: f64| (found - note).abs() <= 8.0;
    // A remark: G4, then the E4 a third below.
    assert!(near(note("oups", 10, 130), G4));
    assert!(near(note("oups", 165, 295), E4));
    // The replay starts: each new bell is the loudest thing as it rings in.
    for (index, expected) in [C5, E5, G5, C6].into_iter().enumerate() {
        let found = note("film", index * 75 + 3, index * 75 + 53);
        assert!(near(found, expected), "{index}: {found}");
    }
    // The three steps of the ta-da.
    for (index, expected) in [G4, C5, E5].into_iter().enumerate() {
        let found = note("bravo", index * 90 + 3, index * 90 + 70);
        assert!(near(found, expected), "{index}: {found}");
    }

    // Saved: C5 alone at first, then E5 joins, then G5; at the end the three
    // ring together and nothing rings between them.
    let saved = samples(10);
    let only_c = &saved[ms(5)..ms(125)];
    assert!(share(only_c, C5) > 0.5, "{}", share(only_c, C5));
    assert!(share(only_c, E5) < 0.01 && share(only_c, G5) < 0.01);
    let c_and_e = &saved[ms(135)..ms(255)];
    assert!(share(c_and_e, C5) > 0.1 && share(c_and_e, E5) > 0.1);
    assert!(share(c_and_e, G5) < 0.01);
    let chord = &saved[ms(270)..ms(590)];
    for sung in [C5, E5, G5] {
        assert!(share(chord, sung) > 0.02, "{sung}: {}", share(chord, sung));
    }
    for silent in [440.0, 590.0, 720.0, 880.0] {
        assert!(share(chord, silent) < 0.002, "{silent}");
    }
    // Bravo ends on the chord of C with its G on top, the strongest.
    let bravo = samples(13);
    let held = &bravo[ms(310)..ms(690)];
    assert!(share(held, G5) > share(held, C5) && share(held, G5) > share(held, E5));
    for sung in [C5, E5, G5] {
        assert!(share(held, sung) > 0.08, "{sung}: {}", share(held, sung));
    }
}

#[test]
fn noise_is_broad_and_soft_and_tones_are_never_shrill() {
    for id in 0..ep_sound_count() {
        let sound = &SOUNDS[id as usize];
        let samples = samples(id);
        // The steepness of a sound against its size tells where its energy
        // lies: 2·sin(π·f/rate) for a sine of frequency f.
        let energy: f64 = samples.iter().map(|s| f64::from(*s).powi(2)).sum();
        let steepness: f64 = samples
            .windows(2)
            .map(|pair| (f64::from(pair[1]) - f64::from(pair[0])).powi(2))
            .sum();
        let centre = (steepness / energy).sqrt().min(2.0) / 2.0;
        let centre = centre.asin() * f64::from(RATE) / std::f64::consts::PI;
        let limit = if uses_noise(sound) { 4000.0 } else { 2500.0 };
        let limit = CLICKS
            .iter()
            .find(|(clicks, _, _)| *clicks == sound.key)
            .map_or(limit, |(_, _, brightest)| *brightest);
        assert!(centre <= limit, "{}: centred on {centre} Hz", sound.key);
        assert!(centre >= 150.0, "{}: centred on {centre} Hz", sound.key);
    }
    // The rubs — brush, pencil, eraser — and the new sheet are noise: no
    // frequency stands out.
    for id in [2, 3, 6, 9] {
        let samples = samples(id);
        for hertz in (100..6000).step_by(50) {
            let found = share(&samples, f64::from(hertz));
            assert!(found < 0.05, "sound {id}: {found} at {hertz} Hz");
        }
    }
    // The hum of a print keeps under 2 kHz; its two bursts are apart.
    let print = samples(17);
    for hertz in (2000..8000).step_by(50) {
        assert!(share(&print, f64::from(hertz)) < 1e-4, "{hertz} Hz");
    }
    assert!(peak(&print[ms(135)..ms(165)]) * 50 <= peak(&print));
}

#[test]
fn the_brush_the_stamp_and_the_pot_sound_like_what_they_imitate() {
    // The brush is bright without being shrill.
    let brush = samples(2);
    assert!(
        (2000.0..=4000.0).contains(&centre(&brush)),
        "{}",
        centre(&brush)
    );
    // The stamp: one dull thump, at its loudest within 40 ms, centred low,
    // and all but gone a fifth of a second later.
    let stamp = samples(4);
    let loudest = stamp
        .iter()
        .position(|sample| i32::from(*sample).abs() == peak(&stamp))
        .unwrap();
    assert!(loudest < ms(40), "{loudest}");
    let press = centre(&stamp[..ms(60)]);
    assert!(press <= 1000.0, "{press}");
    let after = peak(&stamp[ms(200)..]);
    assert!(after * 10 < peak(&stamp), "{after}");
    // The pot pours: the water keeps landing for more than half a second,
    // as a broad noise where no bubble stands out for long.
    let pour = samples(5);
    let middle = &pour[ms(150)..ms(750)];
    assert!(peak(middle) * 3 > peak(&pour));
    for hertz in (200..3000).step_by(50) {
        let found = share(middle, f64::from(hertz));
        assert!(found < 0.05, "{found} at {hertz} Hz");
    }
}

/// SHA-256 (FIPS 180-4) of `bytes`, in lowercase hexadecimal: the
/// provenance of a recording names the file of the core by it.
fn sha256(bytes: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a_2f98,
        0x7137_4491,
        0xb5c0_fbcf,
        0xe9b5_dba5,
        0x3956_c25b,
        0x59f1_11f1,
        0x923f_82a4,
        0xab1c_5ed5,
        0xd807_aa98,
        0x1283_5b01,
        0x2431_85be,
        0x550c_7dc3,
        0x72be_5d74,
        0x80de_b1fe,
        0x9bdc_06a7,
        0xc19b_f174,
        0xe49b_69c1,
        0xefbe_4786,
        0x0fc1_9dc6,
        0x240c_a1cc,
        0x2de9_2c6f,
        0x4a74_84aa,
        0x5cb0_a9dc,
        0x76f9_88da,
        0x983e_5152,
        0xa831_c66d,
        0xb003_27c8,
        0xbf59_7fc7,
        0xc6e0_0bf3,
        0xd5a7_9147,
        0x06ca_6351,
        0x1429_2967,
        0x27b7_0a85,
        0x2e1b_2138,
        0x4d2c_6dfc,
        0x5338_0d13,
        0x650a_7354,
        0x766a_0abb,
        0x81c2_c92e,
        0x9272_2c85,
        0xa2bf_e8a1,
        0xa81a_664b,
        0xc24b_8b70,
        0xc76c_51a3,
        0xd192_e819,
        0xd699_0624,
        0xf40e_3585,
        0x106a_a070,
        0x19a4_c116,
        0x1e37_6c08,
        0x2748_774c,
        0x34b0_bcb5,
        0x391c_0cb3,
        0x4ed8_aa4a,
        0x5b9c_ca4f,
        0x682e_6ff3,
        0x748f_82ee,
        0x78a5_636f,
        0x84c8_7814,
        0x8cc7_0208,
        0x90be_fffa,
        0xa450_6ceb,
        0xbef9_a3f7,
        0xc671_78f2,
    ];
    let mut state: [u32; 8] = [
        0x6a09_e667,
        0xbb67_ae85,
        0x3c6e_f372,
        0xa54f_f53a,
        0x510e_527f,
        0x9b05_688c,
        0x1f83_d9ab,
        0x5be0_cd19,
    ];
    let mut message = bytes.to_vec();
    message.push(0x80);
    while message.len() % 64 != 56 {
        message.push(0);
    }
    message.extend_from_slice(&(bytes.len() as u64 * 8).to_be_bytes());
    let (blocks, rest) = message.as_chunks::<64>();
    assert!(rest.is_empty());
    for block in blocks {
        let mut words = [0u32; 64];
        for (word, four) in words.iter_mut().zip(block.as_chunks::<4>().0) {
            *word = u32::from_be_bytes(*four);
        }
        for n in 16..64 {
            let (before, far) = (words[n - 2], words[n - 15]);
            let s0 = far.rotate_right(7) ^ far.rotate_right(18) ^ (far >> 3);
            let s1 = before.rotate_right(17) ^ before.rotate_right(19) ^ (before >> 10);
            words[n] = words[n - 16]
                .wrapping_add(s0)
                .wrapping_add(words[n - 7])
                .wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = state;
        for (constant, word) in K.iter().zip(words) {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let choice = (e & f) ^ (!e & g);
            let first = h
                .wrapping_add(s1)
                .wrapping_add(choice)
                .wrapping_add(*constant)
                .wrapping_add(word);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let majority = (a & b) ^ (a & c) ^ (b & c);
            let second = s0.wrapping_add(majority);
            (h, g, f, e) = (g, f, e, d.wrapping_add(first));
            (d, c, b, a) = (c, b, a, first.wrapping_add(second));
        }
        for (value, added) in state.iter_mut().zip([a, b, c, d, e, f, g, h]) {
            *value = value.wrapping_add(added);
        }
    }
    state.iter().map(|word| format!("{word:08x}")).collect()
}

#[test]
fn the_digest_of_the_provenance_is_sha_256() {
    assert_eq!(
        sha256(b""),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    );
    assert_eq!(
        sha256(b"abc"),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
    // Two blocks: the padding no longer fits in the first one.
    assert_eq!(
        sha256(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
    );
}

#[test]
fn recordings_are_plain_wav_files_of_a_second_at_most() {
    let found = recordings();
    assert!(!found.is_empty());
    for (key, wav, id) in found {
        // The header the core writes for its own sounds, to the byte: what
        // a player reads is exactly what samples() checked field by field.
        let frames = frame_count(&SOUNDS[id as usize]);
        assert_eq!(wav.len(), WAV_HEADER_BYTES + 2 * frames, "{key}");
        let data = (2 * frames) as u32;
        let mut header = Vec::new();
        header.extend_from_slice(b"RIFF");
        header.extend_from_slice(&(36 + data).to_le_bytes());
        header.extend_from_slice(b"WAVEfmt ");
        header.extend_from_slice(&16u32.to_le_bytes()); // bytes of the format block
        header.extend_from_slice(&1u16.to_le_bytes()); // plain PCM
        header.extend_from_slice(&1u16.to_le_bytes()); // one channel
        header.extend_from_slice(&RATE.to_le_bytes());
        header.extend_from_slice(&(RATE * 2).to_le_bytes()); // bytes per second
        header.extend_from_slice(&2u16.to_le_bytes()); // bytes per frame
        header.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
        header.extend_from_slice(b"data");
        header.extend_from_slice(&data.to_le_bytes());
        assert_eq!(wav[..WAV_HEADER_BYTES], header[..], "{key}");
        assert!((2..=MAX_FRAMES).contains(&frames), "{key}: {frames} frames");
        // Served as compiled in, by every path.
        assert_eq!(wav_file(id), wav, "{key}");
    }
    // Only a recording may be made of clicks.
    for (key, _, _) in CLICKS {
        assert!(recordings().iter().any(|(recorded, _, _)| *recorded == key));
    }
}

/// The section of sons/PROVENANCE.md about one sound.
fn provenance_of(key: &str) -> Option<&'static str> {
    let heading = format!("\n## « {key} » — ");
    let start = PROVENANCE.find(&heading)? + 1;
    let rest = &PROVENANCE[start..];
    Some(&rest[..rest[3..].find("\n## ").map_or(rest.len(), |end| end + 3)])
}

const PROVENANCE: &str = include_str!("../../sons/PROVENANCE.md");
const RECORDING_NOTICES: &str = include_str!("../../sons/notices.txt");

#[test]
fn each_recording_is_credited_under_a_free_licence_with_the_bytes_compiled_in() {
    let found = recordings();
    // Each section of the provenance is a sound of the catalogue that plays a
    // recording, and each of these has its section.
    assert_eq!(PROVENANCE.matches("\n## « ").count(), found.len());
    for (key, wav, _) in &found {
        let section = provenance_of(key).unwrap_or_else(|| panic!("{key} has no provenance"));
        // CC0 or a dedication to the public domain, nothing that asks more.
        let licence = section
            .lines()
            .find_map(|line| line.strip_prefix("- Licence : "))
            .unwrap_or_else(|| panic!("{key}: no licence"));
        assert!(
            licence.starts_with("CC0 1.0 universel")
                || licence.starts_with("domaine public, par la volonté de son auteur"),
            "{key}: {licence}"
        );
        assert!(!licence.contains("BY"), "{key}: {licence}");
        // The file of the core is the one that was prepared and described.
        let described = format!("- SHA-256 du fichier du cœur : `{}`", sha256(wav));
        assert!(
            section.contains(&described),
            "{key}: not the bytes described"
        );
        for field in [
            "- Page : <https://",
            "- Fichier original : <https://",
            "- Extrait : de ",
        ] {
            assert!(section.contains(field), "{key}: {field}");
        }
        // And « Licences » credits it, with the page it comes from.
        let page = section
            .lines()
            .find_map(|line| line.strip_prefix("- Page : <"))
            .and_then(|rest| rest.strip_suffix('>'))
            .unwrap();
        let entry = RECORDING_NOTICES
            .split(&format!("\n{}\n", "-".repeat(80)))
            .find(|entry| entry.contains(&format!("Son « {key} » (")))
            .unwrap_or_else(|| panic!("{key} is not in sons/notices.txt"));
        assert!(entry.starts_with("Sons enregistrés\n\n"), "{key}");
        assert!(entry.contains(&format!("\n{page}\n")), "{key}");
    }
    // Nothing is credited twice, and nothing that is not played.
    assert_eq!(
        RECORDING_NOTICES.matches("Sons enregistrés\n\n").count(),
        found.len()
    );
}

#[test]
fn the_series_agree_with_the_mathematical_library() {
    // Only this test calls the system's sine and exponential.
    for step in 0..200_000 {
        let turns = f64::from(step) * 0.000_731 + f64::from(step / 1000);
        let expected = (TAU * (turns - turns.floor())).sin();
        assert!((sine(turns) - expected).abs() < 1e-9, "{turns}");
    }
    for (turns, expected) in [(0.0, 0.0), (0.25, 1.0), (0.5, 0.0), (0.75, -1.0)] {
        assert!((sine(turns) - expected).abs() < 1e-9);
        assert!((sine(turns + 440.0) - expected).abs() < 1e-9);
    }
    for step in 0..=40_000 {
        let x = -f64::from(step) / 1000.0;
        let expected = x.exp();
        assert!((exp(x) - expected).abs() <= expected * 1e-12, "{x}");
    }
    assert_eq!(exp(0.0), 1.0);
    assert_eq!(exp(-41.0), 0.0);
    // An envelope starts at zero, ends at one and has no corner at either.
    assert_eq!(
        (ease(0, 100), ease(100, 100), ease(250, 100)),
        (0.0, 1.0, 1.0)
    );
    assert_eq!(ease(50, 100), 0.5);
    assert!(ease(1, 100) < 0.001 && ease(99, 100) > 0.999);
    assert_eq!(ease(0, 0), 1.0);
}

#[test]
fn the_noise_generator_is_even_and_without_memory() {
    // The two conditions of a full period on 64 bits.
    assert_eq!(NOISE_A % 8, 5);
    assert_eq!(NOISE_C % 2, 1);
    for sound in [0, 2, 6, 9, 4_000_000_000] {
        let mut noise = Noise::new(sound);
        let values: Vec<f64> = (0..100_000).map(|_| noise.next()).collect();
        assert!(values.iter().all(|value| (-1.0..1.0).contains(value)));
        let count = values.len() as f64;
        let mean = values.iter().sum::<f64>() / count;
        let variance = values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / count;
        // Evenly spread over -1..1: a mean of zero, a variance of a third.
        assert!(mean.abs() < 0.01, "{sound}: mean {mean}");
        assert!((variance - 1.0 / 3.0).abs() < 0.01, "{sound}: {variance}");
        // No value tells anything about the next ones: white, not coloured.
        for lag in [1, 2, 3, 7, 64, 441] {
            let together: f64 = values
                .iter()
                .zip(&values[lag..])
                .map(|(a, b)| (a - mean) * (b - mean))
                .sum();
            let correlation = together / (count * variance);
            assert!(correlation.abs() < 0.02, "{sound}: lag {lag} {correlation}");
        }
        let mut bins = [0u32; 16];
        for value in &values {
            bins[((value + 1.0) * 8.0) as usize] += 1;
        }
        assert!(
            bins.iter().all(|bin| (5850..=6650).contains(bin)),
            "{bins:?}"
        );
    }
    // Two sounds do not share their noise.
    let (mut one, mut other) = (Noise::new(6), Noise::new(9));
    assert!((0..64).any(|_| one.next() != other.next()));
}

#[test]
fn playing_refuses_unknown_identifiers_and_nothing_is_heard_unasked() {
    assert_eq!(ep_sound_play(ep_sound_count()), INVALID);
    assert_eq!(ep_sound_play(u32::MAX), INVALID);
    // Where the core has no player there is nothing to hear: every known
    // identifier is answered with "play the WAV bytes yourself".
    #[cfg(not(any(target_os = "linux", target_os = "android", windows)))]
    for id in 0..ep_sound_count() {
        assert_eq!(ep_sound_play(id), NO_PLAYER, "sound {id}");
    }
    // A known identifier would be heard on the machine that runs the tests.
    // On Windows only the trial below plays one, when asked. On Linux it is
    // played here only when the harness names the device that swallows
    // everything: `COLOR_ALSA_DEVICE=null`, read once per process.
    #[cfg(target_os = "linux")]
    if std::env::var("COLOR_ALSA_DEVICE").as_deref() == Ok("null") {
        use super::alsa::{GIVEN_UP, MAX_PLAYING, PLAYING};
        use std::sync::atomic::Ordering;
        use std::time::{Duration, Instant};
        let quiet = || {
            let limit = Instant::now() + Duration::from_secs(20);
            while PLAYING.load(Ordering::Relaxed) != 0 {
                assert!(Instant::now() < limit, "a sound never ended");
                std::thread::sleep(Duration::from_millis(1));
            }
        };
        for id in 0..ep_sound_count() {
            assert_eq!(ep_sound_play(id), STARTED, "sound {id}");
            quiet();
        }
        // Library found, device opened, every frame written and drained.
        assert!(!GIVEN_UP.load(Ordering::Relaxed));
        // Many at once: handed over or dropped, never more than four threads.
        for round in 0..200 {
            assert_eq!(ep_sound_play(round % ep_sound_count()), STARTED);
            assert!(PLAYING.load(Ordering::Relaxed) <= MAX_PLAYING);
        }
        quiet();
        assert!(!GIVEN_UP.load(Ordering::Relaxed));
    }
}

/// Plays through the real system: never part of a normal run.
/// `COLOR_SOUND_TRIAL=all` (or a list such as `0,13`) with `--ignored
/// --nocapture`; on Linux, COLOR_ALSA_DEVICE chooses the device.
#[test]
#[ignore = "plays sounds: set COLOR_SOUND_TRIAL=all or a list of identifiers"]
fn trial_through_the_system() {
    let Ok(wanted) = std::env::var("COLOR_SOUND_TRIAL") else {
        println!("COLOR_SOUND_TRIAL is not set: nothing played");
        return;
    };
    let ids: Vec<u32> = if wanted == "all" {
        (0..ep_sound_count()).collect()
    } else {
        wanted
            .split(',')
            .map(|id| id.trim().parse().expect("identifiers"))
            .collect()
    };
    for id in ids {
        let before = std::time::Instant::now();
        let result = ep_sound_play(id);
        let took = before.elapsed();
        let key = SOUNDS.get(id as usize).map_or("?", |sound| sound.key);
        println!("ep_sound_play({id} {key}) = {result} in {took:?}");
        if id < ep_sound_count() {
            assert!(result == STARTED || result == NO_PLAYER);
            let frames = (ep_sound_wav_size(id) - WAV_HEADER_BYTES) / 2;
            let length = frames as u64 * 1000 / u64::from(RATE);
            std::thread::sleep(std::time::Duration::from_millis(length + 250));
        } else {
            assert_eq!(result, INVALID);
        }
    }
}

/// The ALSA calls, against a device that is a script and a diary.
#[cfg(target_os = "linux")]
mod alsa_calls {
    use super::super::alsa::{open, write, Alsa, Pcm, PATIENCE};
    use std::cell::Cell;
    use std::ffi::{c_char, c_int, c_long, c_uint, c_ulong, c_void, CStr, CString};
    use std::ptr;

    const EINTR: c_long = -4;
    const ENODEV: c_long = -19;
    const EPIPE: c_long = -32;
    const ESTRPIPE: c_long = -86;

    #[derive(Default)]
    struct Fake {
        open_answer: c_int,
        leave_null: bool,
        params_answer: c_int,
        opened: Vec<(CString, c_int, c_int)>,
        params: Vec<(c_int, c_int, c_uint, c_uint, c_int, c_uint)>,
        /// Answers of the next writes: frames taken at most, or an error.
        /// Once used up, a write takes all it is offered.
        script: Vec<c_long>,
        offered: Vec<usize>,
        heard: Vec<u8>,
        recover_fails: bool,
        recovered: Vec<c_int>,
        drained: u32,
        closed: u32,
    }

    thread_local! {
        static DEVICE: Cell<*mut Fake> = const { Cell::new(ptr::null_mut()) };
    }

    unsafe extern "C" fn fake_open(
        pcm: *mut *mut Pcm,
        name: *const c_char,
        stream: c_int,
        mode: c_int,
    ) -> c_int {
        let device = DEVICE.with(Cell::get);
        let fake = unsafe { &mut *device };
        let name = unsafe { CStr::from_ptr(name) }.to_owned();
        fake.opened.push((name, stream, mode));
        if fake.open_answer == 0 && !fake.leave_null {
            unsafe { *pcm = device.cast() };
        }
        fake.open_answer
    }

    unsafe extern "C" fn fake_set_params(
        pcm: *mut Pcm,
        format: c_int,
        access: c_int,
        channels: c_uint,
        rate: c_uint,
        resample: c_int,
        latency: c_uint,
    ) -> c_int {
        let fake = unsafe { &mut *pcm.cast::<Fake>() };
        fake.params
            .push((format, access, channels, rate, resample, latency));
        fake.params_answer
    }

    unsafe extern "C" fn fake_writei(
        pcm: *mut Pcm,
        data: *const c_void,
        frames: c_ulong,
    ) -> c_long {
        let fake = unsafe { &mut *pcm.cast::<Fake>() };
        let offered = frames as usize;
        fake.offered.push(offered);
        let answer = if fake.script.is_empty() {
            offered as c_long
        } else {
            fake.script.remove(0)
        };
        if answer > 0 {
            // A device never takes more than it was offered; one that claims
            // to have is believed only as far as the frames go.
            let taken = (answer as usize).min(offered);
            let bytes = unsafe { std::slice::from_raw_parts(data.cast::<u8>(), taken * 2) };
            fake.heard.extend_from_slice(bytes);
        }
        answer
    }

    unsafe extern "C" fn fake_recover(pcm: *mut Pcm, error: c_int, silent: c_int) -> c_int {
        let fake = unsafe { &mut *pcm.cast::<Fake>() };
        assert_eq!(silent, 1, "ALSA must not print at every underrun");
        fake.recovered.push(error);
        if fake.recover_fails {
            error
        } else {
            0
        }
    }

    unsafe extern "C" fn fake_drain(pcm: *mut Pcm) -> c_int {
        let fake = unsafe { &mut *pcm.cast::<Fake>() };
        assert_eq!(fake.closed, 0, "drained after being closed");
        fake.drained += 1;
        0
    }

    unsafe extern "C" fn fake_close(pcm: *mut Pcm) -> c_int {
        let fake = unsafe { &mut *pcm.cast::<Fake>() };
        fake.closed += 1;
        0
    }

    const ALSA: Alsa = Alsa {
        open: fake_open,
        set_params: fake_set_params,
        writei: fake_writei,
        recover: fake_recover,
        drain: fake_drain,
        close: fake_close,
    };

    fn played(script: &[c_long], recover_fails: bool, frames: &[u8]) -> Fake {
        let mut fake = Fake {
            script: script.to_vec(),
            recover_fails,
            ..Fake::default()
        };
        write(&ALSA, ptr::from_mut(&mut fake).cast(), frames);
        assert_eq!(fake.closed, 1, "a device is closed once, whatever happened");
        fake
    }

    fn frames(count: usize) -> Vec<u8> {
        (0..count * 2).map(|byte| (byte * 7 + 3) as u8).collect()
    }

    #[test]
    fn a_device_is_opened_for_mono_16_bit_playback_at_our_rate() {
        let mut fake = Fake::default();
        DEVICE.with(|device| device.set(&mut fake));
        let pcm = open(&ALSA, c"essai").expect("opened");
        assert_eq!(pcm.cast::<Fake>(), ptr::from_mut(&mut fake));
        // Playback, blocking; S16_LE, interleaved, one channel, 44 100 Hz,
        // ALSA's resampling allowed, a tenth of a second of buffer.
        assert_eq!(fake.opened, [(c"essai".to_owned(), 0, 0)]);
        assert_eq!(fake.params, [(2, 3, 1, 44_100, 1, 100_000)]);
        assert_eq!((fake.drained, fake.closed), (0, 0));
    }

    #[test]
    fn a_device_that_cannot_be_opened_or_set_is_given_up_and_not_left_open() {
        let mut fake = Fake {
            open_answer: -2,
            ..Fake::default()
        };
        DEVICE.with(|device| device.set(&mut fake));
        assert!(open(&ALSA, c"absent").is_none());
        assert_eq!(fake.opened.len(), 1);
        assert!(fake.params.is_empty());
        assert_eq!(fake.closed, 0, "nothing was opened: nothing to close");

        let mut fake = Fake {
            leave_null: true,
            ..Fake::default()
        };
        DEVICE.with(|device| device.set(&mut fake));
        assert!(open(&ALSA, c"vide").is_none());
        assert!(fake.params.is_empty());

        let mut fake = Fake {
            params_answer: -22,
            ..Fake::default()
        };
        DEVICE.with(|device| device.set(&mut fake));
        assert!(open(&ALSA, c"sourd").is_none());
        assert_eq!(fake.params.len(), 1);
        assert_eq!(fake.closed, 1, "opened, refused our format: closed again");
    }

    #[test]
    fn every_frame_is_written_once_and_in_order_however_the_device_takes_them() {
        let sound = frames(1000);
        // All at once.
        let fake = played(&[], false, &sound);
        assert_eq!(fake.heard, sound);
        assert_eq!(fake.offered, [1000]);
        assert_eq!((fake.drained, fake.recovered.len()), (1, 0));
        // In pieces: each write offers exactly what is left.
        let fake = played(&[100, 1, 7, 500], false, &sound);
        assert_eq!(fake.heard, sound);
        assert_eq!(fake.offered, [1000, 900, 899, 892, 392]);
        assert_eq!(fake.drained, 1);
        // Underrun, suspended device, interrupted call: after each, ALSA
        // prepares the device and the same frames are offered again.
        let fake = played(&[100, EPIPE, 50, ESTRPIPE, EINTR, 400], false, &sound);
        assert_eq!(fake.heard, sound);
        assert_eq!(fake.offered, [1000, 900, 900, 850, 850, 850, 450]);
        assert_eq!(fake.recovered, [-32, -86, -4]);
        assert_eq!(fake.drained, 1);
        // A device that claims more than it was offered does no harm.
        let fake = played(&[5000], false, &sound);
        assert_eq!(fake.heard, sound);
        assert_eq!(fake.drained, 1);
        // An odd byte is not a frame; an empty sound is drained and closed.
        let fake = played(&[], false, &sound[..1999]);
        assert_eq!(fake.heard, sound[..1998]);
        let fake = played(&[], false, &[]);
        assert!(fake.offered.is_empty());
        assert_eq!(fake.drained, 1);
    }

    #[test]
    fn a_device_that_fails_ends_its_sound_without_draining_or_insisting() {
        let sound = frames(1000);
        // Unplugged: ALSA cannot recover, nothing more is offered.
        let fake = played(&[100, ENODEV, 100], true, &sound);
        assert_eq!(fake.heard, sound[..200]);
        assert_eq!(fake.offered, [1000, 900]);
        assert_eq!(fake.recovered, [-19]);
        assert_eq!(fake.drained, 0, "frames are left: nothing to wait for");
        // Stuck: it takes nothing and says so forever. Patience has an end.
        let stuck = vec![0; 1000];
        let fake = played(&stuck, false, &sound);
        assert!(fake.heard.is_empty());
        assert_eq!(fake.offered.len(), PATIENCE as usize);
        assert_eq!(fake.drained, 0);
        // Underruns without end are not played to the end either, but what
        // was taken between them was taken once.
        let mut script = Vec::new();
        for _ in 0..PATIENCE {
            script.extend([10, EPIPE]);
        }
        let fake = played(&script, false, &sound);
        assert_eq!(fake.heard, sound[..PATIENCE as usize * 20]);
        assert_eq!(fake.drained, 0);
    }
}
