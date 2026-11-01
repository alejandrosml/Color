//! Sounds of the interface: small recipes rendered by this program, and a
//! few short recordings.
//!
//! Most sounds are recipes: a list of voices, each one a few sine partials
//! of a gliding pitch or noise through a gliding filter, with its own rise
//! and fall. One renderer turns a recipe into mono 16-bit samples at
//! 44 100 Hz, wrapped in a WAV file that stays in memory for the life of the
//! process. The noise comes from the generator written below; no sample,
//! table of data or code of a recipe comes from another program or sound
//! library.
//!
//! The tools that touch the sheet — the brush, the pencil of the shapes,
//! the stamp, the paint pot, the eraser and the typewriter — and the
//! selection of an element play a recording instead: a WAV file in `sons/`,
//! compiled in. Each one is a short extract of a recording that its author
//! dedicated to the public domain (CC0), cut, filtered, faded and scaled by
//! `scripts/sons/preparer-les-sons.py` to the format and the rules of the
//! sounds rendered here. `sons/PROVENANCE.md` says where each one comes from
//! and what was done to it; `sons/notices.txt` credits them in the notices
//! of the core. None comes from Tux Paint or EduPaint.
//!
//! Identifiers are positions in the catalogue and are used by the interface:
//! sounds may be appended, never reordered or removed.
//!
//! Rendering uses additions, multiplications and divisions of `f64`, integer
//! conversions and one rounding per sample; sine and exponential are short
//! series written here, never the mathematical library of the system. IEEE
//! 754 defines each of these operations exactly, so a sound has the same
//! samples on x86-64 and ARM64, under every system and at every optimisation
//! level. (A target that computes in x87 registers is not covered.) A
//! recording is the same bytes everywhere by nature.
//!
//! Playing is offered where the interface has no player of its own: winmm
//! on Windows, ALSA on Linux, AAudio on Android. Elsewhere the interface
//! reads the WAV bytes and plays them itself. These functions touch no document and may be
//! called from any thread.
use super::*;
use std::f64::consts::TAU;
use std::sync::OnceLock;

/// Frames per second of every sound: one channel, sixteen bits.
const RATE: u32 = 44_100;
/// RIFF, format and data headers in front of the samples of a WAV file.
const WAV_HEADER_BYTES: usize = 44;
/// No sound lasts longer than a second, nor asks for more memory than that.
const MAX_FRAMES: usize = RATE as usize;
/// Answers of ep_sound_play, beside -1 for an unknown identifier.
const STARTED: i32 = 0;
const NO_PLAYER: i32 = 1;

/// One sine of a timbre: its pitch as a multiple of the pitch of the voice,
/// its level, and its decay time as a multiple of the decay of the voice.
struct Partial(f64, f64, f64);

enum Source {
    Partials(&'static [Partial]),
    /// Noise through a low-pass filter; the pitch of the voice is its cutoff.
    Noise,
}

/// One layer of a sound. Times are milliseconds, pitches hertz.
struct Voice {
    source: Source,
    /// From the beginning of the sound.
    start: u32,
    length: u32,
    /// The pitch moves in a straight line from one to the other.
    from: f64,
    to: f64,
    /// Share in the mix; the whole sound is then scaled to its peak.
    level: f64,
    /// Rise from silence. Never under 3 ms: a faster one is heard as a click.
    attack: u32,
    /// Time constant of the exponential fall; 0 holds the level.
    decay: u32,
}

/// What a sound is made of.
enum Making {
    /// Voices rendered here, sample by sample.
    Recipe(&'static [Voice]),
    /// A complete WAV file prepared from a recording: a 44-byte header, then
    /// mono 16-bit samples at RATE. See `sons/PROVENANCE.md`.
    Recording(&'static [u8]),
}

struct Sound {
    /// Stable ASCII name, for the interface and the catalogue checks.
    key: &'static str,
    /// Largest absolute sample value: tonal sounds stay under -10 dBFS
    /// (10 362), noise, recordings and the tick of a stroke under -16 dBFS
    /// (5 193). A recording was scaled to it when it was prepared.
    peak: i16,
    making: Making,
}

const SINE: Source = Source::Partials(&[Partial(1.0, 1.0, 1.0)]);
/// The first three terms of a triangle wave: hollow, without edge.
const SOFT: Source = Source::Partials(&[
    Partial(1.0, 1.0, 1.0),
    Partial(3.0, -1.0 / 9.0, 1.0),
    Partial(5.0, 1.0 / 25.0, 1.0),
]);
/// A small bell: the higher a partial, the weaker and the sooner gone.
const BELL: Source = Source::Partials(&[
    Partial(1.0, 1.0, 1.0),
    Partial(2.0, 0.3, 0.6),
    Partial(3.0, 0.12, 0.35),
    Partial(4.0, 0.06, 0.2),
]);
/// A low hum and its harmonics up to the tenth. The third and fourth are the
/// strongest: a small loudspeaker cannot play the fundamental, and the ear
/// rebuilds it from them. Nothing above the tenth: a buzz without its edge.
/// The fourth and the eighth are turned over, which the ear hardly tells
/// but which keeps the ten from piling up into one spike at every turn.
const BUZZ: Source = Source::Partials(&[
    Partial(1.0, 0.5, 1.0),
    Partial(2.0, 0.8, 1.0),
    Partial(3.0, 1.0, 1.0),
    Partial(4.0, -0.9, 1.0),
    Partial(5.0, 0.7, 1.0),
    Partial(6.0, 0.5, 1.0),
    Partial(7.0, 0.35, 1.0),
    Partial(8.0, -0.22, 1.0),
    Partial(9.0, 0.12, 1.0),
    Partial(10.0, 0.05, 1.0),
]);

// Notes of the equal temperament built on A4 = 440 Hz.
const E4: f64 = 329.63;
const G4: f64 = 392.0;
const C5: f64 = 523.25;
const E5: f64 = 659.26;
const G5: f64 = 783.99;
const C6: f64 = 1046.5;

/// A voice that starts `start` ms into the sound and lasts `length` ms while
/// its pitch goes `from` → `to`. Full level, 4 ms of attack and no decay
/// unless the methods below say otherwise.
const fn voice(source: Source, start: u32, length: u32, from: f64, to: f64) -> Voice {
    Voice {
        source,
        start,
        length,
        from,
        to,
        level: 1.0,
        attack: 4,
        decay: 0,
    }
}

impl Voice {
    const fn level(mut self, level: f64) -> Self {
        self.level = level;
        self
    }
    const fn attack(mut self, ms: u32) -> Self {
        self.attack = ms;
        self
    }
    const fn decay(mut self, ms: u32) -> Self {
        self.decay = ms;
        self
    }
}

static SOUNDS: [Sound; 18] = [
    // A tool or a button is chosen: a short soft pop that goes up.
    Sound {
        key: "outil",
        peak: 7300,
        making: Making::Recipe(&[voice(SINE, 0, 70, 520.0, 780.0).decay(22)]),
    },
    // A colour is chosen: a round drop that goes down.
    Sound {
        key: "couleur",
        peak: 6500,
        making: Making::Recipe(&[voice(SINE, 0, 110, 660.0, 440.0).attack(6).decay(38)]),
    },
    // A brush passes once over a sheet: a soft swish. It is heard when the
    // brush touches the sheet, then again and again while it travels, so it
    // is the softest of all, and every one overlaps the next.
    Sound {
        key: "trait",
        peak: 3400,
        making: Making::Recording(include_bytes!("../sons/trait.wav")),
    },
    // A line, a rectangle or an oval is drawn: a pencil draws one quick
    // line on paper.
    Sound {
        key: "forme",
        peak: 4600,
        making: Making::Recording(include_bytes!("../sons/forme.wav")),
    },
    // A stamp pressed on a letter: one dull, short thump.
    Sound {
        key: "tampon",
        peak: 5000,
        making: Making::Recording(include_bytes!("../sons/tampon.wav")),
    },
    // The paint pot fills something: a bucket is emptied, a trickle, then
    // the flood.
    Sound {
        key: "pot",
        peak: 5000,
        making: Making::Recording(include_bytes!("../sons/pot.wav")),
    },
    // The eraser rubs the paper: a rubber eraser, back and forth.
    Sound {
        key: "gomme",
        peak: 4800,
        making: Making::Recording(include_bytes!("../sons/gomme.wav")),
    },
    // Undo: a glide down, back to where one was.
    Sound {
        key: "annuler",
        peak: 5200,
        making: Making::Recipe(&[voice(SINE, 0, 160, 700.0, 350.0).attack(8).decay(120)]),
    },
    // Redo: the same glide, up again.
    Sound {
        key: "retablir",
        peak: 6000,
        making: Making::Recipe(&[voice(SINE, 0, 160, 350.0, 700.0).attack(8).decay(120)]),
    },
    // A new sheet: paper drawn aside, noise that swells and brightens.
    Sound {
        key: "feuille",
        peak: 5000,
        making: Making::Recipe(&[voice(Source::Noise, 0, 250, 500.0, 4200.0).attack(170)]),
    },
    // The drawing was saved: three bells, C5 E5 G5, each left to ring.
    Sound {
        key: "enregistre",
        peak: 8800,
        making: Making::Recipe(&[
            voice(BELL, 0, 600, C5, C5).decay(170),
            voice(BELL, 130, 470, E5, E5).decay(160),
            voice(BELL, 260, 340, G5, G5).decay(120),
        ]),
    },
    // "This cannot be done here": two low notes going down a third, slow to
    // rise and quieter than the rest. A remark, never an alarm.
    Sound {
        key: "oups",
        peak: 6500,
        making: Making::Recipe(&[
            voice(SOFT, 0, 160, G4, G4).attack(12).decay(70),
            voice(SOFT, 140, 160, E4, E4).attack(12).decay(80),
        ]),
    },
    // The replay of the drawing starts: an arpeggio that climbs to C6.
    Sound {
        key: "film",
        peak: 7600,
        making: Making::Recipe(&[
            voice(BELL, 0, 200, C5, C5).decay(60),
            voice(BELL, 75, 200, E5, E5).decay(60),
            voice(BELL, 150, 200, G5, G5).decay(60),
            voice(BELL, 225, 225, C6, C6).decay(75),
        ]),
    },
    // The replay is finished: three quick steps up, then the chord they
    // lead to, held.
    Sound {
        key: "bravo",
        peak: 8800,
        making: Making::Recipe(&[
            voice(BELL, 0, 110, G4, G4).decay(45),
            voice(BELL, 90, 110, C5, C5).decay(45),
            voice(BELL, 180, 110, E5, E5).decay(45),
            voice(BELL, 270, 430, C5, C5).decay(170).level(0.7),
            voice(BELL, 282, 418, E5, E5).decay(170).level(0.7),
            voice(BELL, 294, 406, G5, G5).decay(170),
        ]),
    },
    // First click of a gesture made of two: the smallest sound of all.
    Sound {
        key: "clic",
        peak: 4100,
        making: Making::Recipe(&[voice(SINE, 0, 30, 1500.0, 1300.0).attack(3).decay(5)]),
    },
    // A text is placed: three strokes of a typewriter, without its bell.
    Sound {
        key: "texte",
        peak: 4950,
        making: Making::Recording(include_bytes!("../sons/texte.wav")),
    },
    // An element is selected: a short, gentle click.
    Sound {
        key: "choisir",
        peak: 3800,
        making: Making::Recording(include_bytes!("../sons/choisir.wav")),
    },
    // A print was sent: two short low hums, like a small machine starting.
    Sound {
        key: "imprime",
        peak: 3200,
        making: Making::Recipe(&[
            voice(BUZZ, 0, 130, 132.0, 126.0).attack(12),
            voice(BUZZ, 170, 130, 132.0, 126.0).attack(12),
        ]),
    },
];

/// The noise of this module: `state * a + c` on 64 bits. The two constants
/// are ours. Any odd `c` with any `a` that leaves 5 when divided by 8 makes
/// the state run through all its 2^64 values; its high bits are the good
/// ones, and only they are used.
struct Noise(u64);
const NOISE_A: u64 = 0x9a3c_d1e5_27b4_f86d;
const NOISE_C: u64 = 0x3b5f_0c8d_91e2_a467;

impl Noise {
    fn new(sound: u32) -> Self {
        let mut noise = Self(u64::from(sound));
        // The first states still look like the small seed they come from.
        for _ in 0..4 {
            noise.next();
        }
        noise
    }

    /// The next value, evenly spread over -1..1.
    fn next(&mut self) -> f64 {
        self.0 = self.0.wrapping_mul(NOISE_A).wrapping_add(NOISE_C);
        (self.0 >> 40) as f64 / 8_388_608.0 - 1.0
    }
}

/// sin(2πx) for x ≥ 0, in turns. The turn is folded into the quarter around
/// zero, where seven terms of the series are right to 1e-9, a hundred
/// thousand times finer than one step of a 16-bit sample.
fn sine(turns: f64) -> f64 {
    let turn = turns - (turns as i64) as f64;
    let folded = if turn < 0.25 {
        turn
    } else if turn < 0.75 {
        0.5 - turn
    } else {
        turn - 1.0
    };
    let angle = TAU * folded;
    let square = angle * angle;
    // x(1 - x²/(2·3)(1 - x²/(4·5)(1 - … x²/(12·13)))), from the inside out.
    let mut series = 1.0;
    let mut k = 12.0;
    while k >= 2.0 {
        series = 1.0 - series * square / (k * (k + 1.0));
        k -= 2.0;
    }
    angle * series
}

/// e^x for x ≤ 0. e^x is the 1024th power of e^(x/1024), and x/1024 is small
/// enough for eight terms of the series; ten squarings do the rest.
fn exp(x: f64) -> f64 {
    if x < -40.0 {
        return 0.0;
    }
    let small = x / 1024.0;
    let mut term = 1.0;
    let mut sum = 1.0;
    let mut n = 1.0;
    while n <= 8.0 {
        term *= small / n;
        sum += term;
        n += 1.0;
    }
    for _ in 0..10 {
        sum *= sum;
    }
    sum
}

/// From 0 to 1 while `position` goes from 0 to `length`, without a corner at
/// either end: a corner in an envelope is a click in the loudspeaker.
fn ease(position: usize, length: usize) -> f64 {
    if position >= length {
        return 1.0;
    }
    let x = position as f64 / length as f64;
    x * x * (3.0 - 2.0 * x)
}

fn frames(ms: u32) -> usize {
    ms as usize * RATE as usize / 1000
}

/// First frame of a voice, and the number of steps to its last one.
fn span(voice: &Voice) -> (usize, usize) {
    (frames(voice.start), frames(voice.length))
}

/// Frames of a whole sound. A recipe lasts up to the end of its last voice,
/// that final frame included, where every envelope is back at zero; a
/// recording has the frames that follow its header.
fn frame_count(sound: &Sound) -> usize {
    match sound.making {
        Making::Recipe(voices) => {
            let end = voices.iter().map(|voice| {
                let (first, steps) = span(voice);
                first + steps
            });
            end.max().unwrap_or(0) + 1
        }
        Making::Recording(wav) => wav.len().saturating_sub(WAV_HEADER_BYTES) / 2,
    }
}

/// Level of a voice at step `n` of `steps`, the exponential fall left aside:
/// the attack, then a release that takes the last quarter of the voice (5 to
/// 60 ms) down to exactly zero, which no exponential ever reaches.
fn envelope(voice: &Voice, n: usize, steps: usize) -> f64 {
    let release = (steps / 4).clamp(frames(5), frames(60));
    voice.level * ease(n, frames(voice.attack)) * ease(steps - n, release)
}

/// Exponential fall after `n` frames, for a time constant in milliseconds.
fn fall(n: usize, decay: f64) -> f64 {
    if decay <= 0.0 {
        return 1.0;
    }
    exp(-(n as f64) * 1000.0 / (decay * f64::from(RATE)))
}

fn add_partials(out: &mut [f64], voice: &Voice, partials: &[Partial]) {
    let steps = out.len() - 1;
    for (n, sample) in out.iter_mut().enumerate() {
        let seconds = n as f64 / f64::from(RATE);
        // Turns made so far by a pitch that moves in a straight line: the
        // time multiplied by the mean of the first pitch and the present one.
        let glide = (voice.to - voice.from) * (n as f64 / steps as f64);
        let turns = seconds * (voice.from + glide / 2.0);
        let mut value = 0.0;
        for Partial(ratio, level, share) in partials {
            value += level * fall(n, f64::from(voice.decay) * share) * sine(ratio * turns);
        }
        *sample += envelope(voice, n, steps) * value;
    }
}

fn add_noise(out: &mut [f64], voice: &Voice, noise: &mut Noise) {
    let steps = out.len() - 1;
    // Under 200 Hz filtered noise is a slow heave that small loudspeakers
    // cannot play and that would only take room from what they can.
    let heave = 1.0 - exp(-TAU * 200.0 / f64::from(RATE));
    let (mut soft, mut softer, mut slow) = (0.0, 0.0, 0.0);
    for (n, sample) in out.iter_mut().enumerate() {
        let cutoff = voice.from + (voice.to - voice.from) * (n as f64 / steps as f64);
        let open = 1.0 - exp(-TAU * cutoff / f64::from(RATE));
        // Two gentle low-pass filters in a row: hiss becomes breath.
        soft += open * (noise.next() - soft);
        softer += open * (soft - softer);
        slow += heave * (softer - slow);
        let value = fall(n, f64::from(voice.decay)) * (softer - slow);
        *sample += envelope(voice, n, steps) * value;
    }
}

/// The complete WAV file of a sound, or None for an unknown identifier or
/// when memory is exhausted. Every sample of a recipe is a function of the
/// recipe alone; a recording is copied as it was compiled in (the tests
/// check its header, its length and its samples).
fn render(id: u32) -> Option<Vec<u8>> {
    let sound = SOUNDS.get(id as usize)?;
    let count = frame_count(sound);
    if !(2..=MAX_FRAMES).contains(&count) || sound.peak <= 0 {
        return None;
    }
    let voices = match sound.making {
        Making::Recipe(voices) => voices,
        Making::Recording(file) => {
            let mut wav = Vec::new();
            wav.try_reserve_exact(file.len()).ok()?;
            wav.extend_from_slice(file);
            return Some(wav);
        }
    };
    let mut mix: Vec<f64> = Vec::new();
    mix.try_reserve_exact(count).ok()?;
    mix.resize(count, 0.0);
    let mut noise = Noise::new(id);
    for voice in voices {
        let (first, steps) = span(voice);
        let Some(out) = mix.get_mut(first..=first + steps) else {
            continue;
        };
        if steps == 0 {
            // Nothing to divide a glide or an envelope by.
            continue;
        }
        match voice.source {
            Source::Partials(partials) => add_partials(out, voice, partials),
            Source::Noise => add_noise(out, voice, &mut noise),
        }
    }
    // A burst that swings more to one side than to the other pushes the
    // loudspeaker without making a sound. Take the excess back along an arch
    // that is flat at both ends: the samples then sum to zero, and the first
    // and the last stay at zero.
    let arch = |n: usize| {
        let x = n as f64 / (count - 1) as f64;
        let bow = 4.0 * x * (1.0 - x);
        bow * bow
    };
    let excess = mix.iter().sum::<f64>() / (0..count).map(arch).sum::<f64>();
    let mut loudest = 0.0;
    for (n, value) in mix.iter_mut().enumerate() {
        *value -= excess * arch(n);
        if value.abs() > loudest {
            loudest = value.abs();
        }
    }
    if loudest <= 0.0 {
        return None;
    }
    let peak = i32::from(sound.peak);
    let scale = f64::from(peak) / loudest;
    let data = count * 2;
    let mut wav = Vec::new();
    wav.try_reserve_exact(WAV_HEADER_BYTES + data).ok()?;
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&((WAV_HEADER_BYTES - 8 + data) as u32).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    wav.extend_from_slice(&16u32.to_le_bytes()); // bytes of the format block
    wav.extend_from_slice(&1u16.to_le_bytes()); // plain PCM
    wav.extend_from_slice(&1u16.to_le_bytes()); // one channel
    wav.extend_from_slice(&RATE.to_le_bytes());
    wav.extend_from_slice(&(RATE * 2).to_le_bytes()); // bytes per second
    wav.extend_from_slice(&2u16.to_le_bytes()); // bytes per frame
    wav.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&(data as u32).to_le_bytes());
    for value in &mix {
        // The only rounding: to the nearest step, a half going away from
        // zero. The conversion itself cuts towards zero.
        let scaled = value * scale;
        let rounded = if scaled < 0.0 {
            (scaled - 0.5) as i32
        } else {
            (scaled + 0.5) as i32
        };
        wav.extend_from_slice(&(rounded.clamp(-peak, peak) as i16).to_le_bytes());
    }
    Some(wav)
}

/// The WAV file of each sound, rendered (or copied, for a recording) at its
/// first use. Windows plays these bytes after ep_sound_play has returned, and
/// the Linux threads read them while the interface goes on: they are never
/// moved nor freed.
static RENDERED: [OnceLock<Vec<u8>>; SOUNDS.len()] = [const { OnceLock::new() }; SOUNDS.len()];

fn wav(id: u32) -> Option<&'static [u8]> {
    let slot = RENDERED.get(id as usize)?;
    if slot.get().is_none() {
        // Nothing is kept of a failure: the next call tries again. Two
        // threads may both render; the bytes are the same and one copy stays.
        let _ = slot.set(render(id)?);
    }
    slot.get().map(Vec::as_slice)
}

// One line per sound: `id|key`.
fn names_text() -> Option<CString> {
    let capacity = SOUNDS
        .iter()
        .map(|sound| sound.key.len() + 12)
        .sum::<usize>()
        + 1;
    let mut result = String::new();
    result.try_reserve_exact(capacity).ok()?;
    for (id, sound) in SOUNDS.iter().enumerate() {
        writeln!(result, "{}|{}", id, sound.key).ok()?;
    }
    let mut bytes = result.into_bytes();
    bytes.push(0);
    CString::from_vec_with_nul(bytes).ok()
}

/// Number of sounds of this core; valid identifiers are 0..count.
#[no_mangle]
pub extern "C" fn ep_sound_count() -> u32 {
    SOUNDS.len() as u32
}

/// Returns the names of the sounds as owned, NUL-terminated ASCII text, or
/// NULL on allocation failure. One line per sound, in identifier order:
/// `id|key`. Release with ep_string_free only.
#[no_mangle]
pub extern "C" fn ep_sound_names() -> *mut c_char {
    names_text().map_or(ptr::null_mut(), CString::into_raw)
}

/// Exact byte count of the WAV file of a sound (mono, 16 bits, 44 100 Hz),
/// or 0 for an unknown identifier. Nothing is rendered or allocated.
#[no_mangle]
pub extern "C" fn ep_sound_wav_size(id: u32) -> usize {
    SOUNDS
        .get(id as usize)
        .map_or(0, |sound| WAV_HEADER_BYTES + 2 * frame_count(sound))
}

/// Copies the complete WAV file of a sound and returns its size. Returns 0
/// and writes nothing for an unknown identifier, a NULL output, a capacity
/// below ep_sound_wav_size, or when memory is exhausted. The first use of a
/// sound renders it, in a few milliseconds (a recording is only copied); the
/// bytes never change after.
///
/// # Safety
/// Non-null `out` must be writable for `capacity` bytes and exclusively
/// accessible during the call. Bytes beyond the returned size are untouched.
#[no_mangle]
pub unsafe extern "C" fn ep_copy_sound_wav(id: u32, out: *mut u8, capacity: usize) -> usize {
    let Some(bytes) = wav(id) else {
        return 0;
    };
    if out.is_null() || capacity < bytes.len() {
        return 0;
    }
    unsafe {
        ptr::copy_nonoverlapping(bytes.as_ptr(), out, bytes.len());
    }
    bytes.len()
}

/// Starts playing a sound through the system and returns without waiting
/// for its end. Returns 0 when the sound was handed to the system, 1 when
/// there is no way to play here and the caller must use its own, -1 for an
/// unknown identifier.
///
/// Windows: PlaySoundW of winmm, from memory and asynchronously; a new sound
/// interrupts the one that was playing (under Wine, the only place where it
/// was measured, such a call waits a few milliseconds for winmm to stop the
/// old sound). The first use of a sound renders it on the calling thread, in
/// a few milliseconds; ep_copy_sound_wav at start-up does it beforehand.
///
/// Linux: ALSA, loaded at run time, on a short-lived thread per sound; the
/// device is `default`, or the value that the environment variable
/// COLOR_ALSA_DEVICE had at the first call. At most four sounds play at once:
/// while four do, a new one is dropped and 0 is still returned, as it is for
/// a sound dropped because its device took over a second to open. Once the
/// library, one of its functions or the device is found missing, which only
/// the thread of the first sound can discover, every later call returns 1.
///
/// Android: AAudio, loaded at run time by the first call (Android 8 and
/// later). A thread of the core opens one output stream at low latency, at
/// the rate of the device, when a sound is asked for, and closes it three
/// seconds after the last one; its callback mixes up to four sounds, a fifth
/// is dropped and 0 is still returned. Nothing of AAudio but its loading
/// runs on the caller's thread: the call only hands the sound over. A stream
/// that cannot be opened, that the system takes away or that stops calling
/// back costs the sounds asked for meanwhile (0 still); the next one tries
/// again, half a second after a failed opening at the soonest. Once the
/// library or one of its functions is found missing, every later call
/// returns 1.
///
/// Elsewhere (macOS, iOS: the application plays the WAV bytes itself):
/// always 1.
#[no_mangle]
pub extern "C" fn ep_sound_play(id: u32) -> i32 {
    if id as usize >= SOUNDS.len() {
        return INVALID;
    }
    if play(id) {
        STARTED
    } else {
        NO_PLAYER
    }
}

/// Whether the sound was handed to the system. Here: there is no system.
#[cfg(not(any(target_os = "linux", target_os = "android", windows)))]
fn play(_id: u32) -> bool {
    false
}

#[cfg(windows)]
use winmm::play;

#[cfg(windows)]
mod winmm {
    use super::wav;
    use std::ffi::c_void;
    use std::ptr;

    #[link(name = "winmm")]
    extern "system" {
        // BOOL PlaySoundW(LPCWSTR, HMODULE, DWORD); with SND_MEMORY the first
        // argument is the address of a WAV file in memory.
        fn PlaySoundW(sound: *const c_void, module: *mut c_void, flags: u32) -> i32;
    }
    const SND_ASYNC: u32 = 0x0001;
    const SND_NODEFAULT: u32 = 0x0002;
    const SND_MEMORY: u32 = 0x0004;

    pub(super) fn play(id: u32) -> bool {
        let Some(wav) = wav(id) else {
            return false;
        };
        // Asynchronous: winmm reads these bytes after the call has returned,
        // which the cache allows for as long as the process lives. Without
        // SND_NODEFAULT a failure would play the system's own beep instead.
        let flags = SND_MEMORY | SND_ASYNC | SND_NODEFAULT;
        unsafe { PlaySoundW(wav.as_ptr().cast(), ptr::null_mut(), flags) != 0 }
    }
}

#[cfg(target_os = "linux")]
use alsa::play;

#[cfg(target_os = "linux")]
mod alsa {
    use super::{wav, RATE, WAV_HEADER_BYTES};
    use std::ffi::{c_char, c_int, c_long, c_uint, c_ulong, c_void, CStr, CString, OsString};
    use std::os::unix::ffi::OsStringExt;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::sync::{Mutex, OnceLock};
    use std::time::{Duration, Instant};
    use std::{mem, ptr, thread};

    extern "C" {
        fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
        fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    }
    /// `<dlfcn.h>`: resolve every symbol of the library while loading it.
    const RTLD_NOW: c_int = 2;

    // `<alsa/pcm.h>`. The three constants are those of the kernel, and
    // snd_pcm_sframes_t / snd_pcm_uframes_t are long / unsigned long.
    const SND_PCM_STREAM_PLAYBACK: c_int = 0;
    const SND_PCM_FORMAT_S16_LE: c_int = 2;
    const SND_PCM_ACCESS_RW_INTERLEAVED: c_int = 3;
    /// An opaque `snd_pcm_t`.
    pub(super) type Pcm = c_void;
    type Open = unsafe extern "C" fn(*mut *mut Pcm, *const c_char, c_int, c_int) -> c_int;
    type SetParams =
        unsafe extern "C" fn(*mut Pcm, c_int, c_int, c_uint, c_uint, c_int, c_uint) -> c_int;
    type Writei = unsafe extern "C" fn(*mut Pcm, *const c_void, c_ulong) -> c_long;
    type Recover = unsafe extern "C" fn(*mut Pcm, c_int, c_int) -> c_int;
    type Finish = unsafe extern "C" fn(*mut Pcm) -> c_int;

    /// The six functions of libasound that playing a sound takes.
    pub(super) struct Alsa {
        pub open: Open,
        pub set_params: SetParams,
        pub writei: Writei,
        pub recover: Recover,
        pub drain: Finish,
        pub close: Finish,
    }

    /// Sounds that may play at the same time; a fifth is not worth a thread.
    pub(super) const MAX_PLAYING: usize = 4;
    /// Stack of a playing thread. It runs ALSA and whatever stands behind
    /// `default` (PulseAudio, PipeWire), code that is not ours: 512 KiB is
    /// four times what every thread of a musl system gets, a quarter of
    /// Rust's own default, and costs nothing until it is touched.
    const STACK_BYTES: usize = 512 * 1024;
    /// Buffer asked of the device, in microseconds. A sound shorter than
    /// this starts when it is drained, at once.
    const LATENCY_US: c_uint = 100_000;
    /// A sound answers a gesture. One that could only start this long after
    /// it, because the device was held or slow to wake, would answer nothing.
    const TOO_LATE: Duration = Duration::from_secs(1);
    /// Failed writes forgiven to one sound before it is abandoned.
    pub(super) const PATIENCE: u32 = 8;

    static LIBRARY: OnceLock<Option<Alsa>> = OnceLock::new();
    static DEVICE: OnceLock<CString> = OnceLock::new();
    /// Set when the library, one of its functions or the device is missing.
    /// Never cleared: ALSA says why on the standard error, and must not say
    /// it again at every stroke of the brush.
    pub(super) static GIVEN_UP: AtomicBool = AtomicBool::new(false);
    pub(super) static PLAYING: AtomicUsize = AtomicUsize::new(0);
    /// Devices are opened one at a time: when the first opening fails, the
    /// threads that waited behind it give up without asking ALSA again.
    static OPENING: Mutex<()> = Mutex::new(());

    impl Alsa {
        fn load() -> Option<Self> {
            // Never closed: a sound may be playing until the process ends.
            let library = unsafe { dlopen(c"libasound.so.2".as_ptr(), RTLD_NOW) };
            if library.is_null() {
                return None;
            }
            let find = |name: &CStr| {
                let symbol = unsafe { dlsym(library, name.as_ptr()) };
                (!symbol.is_null()).then_some(symbol)
            };
            // The addresses are those of functions with exactly these C
            // signatures; a data pointer and a function pointer have the
            // same size on every Linux target.
            unsafe {
                Some(Self {
                    open: mem::transmute::<*mut c_void, Open>(find(c"snd_pcm_open")?),
                    set_params: mem::transmute::<*mut c_void, SetParams>(find(
                        c"snd_pcm_set_params",
                    )?),
                    writei: mem::transmute::<*mut c_void, Writei>(find(c"snd_pcm_writei")?),
                    recover: mem::transmute::<*mut c_void, Recover>(find(c"snd_pcm_recover")?),
                    drain: mem::transmute::<*mut c_void, Finish>(find(c"snd_pcm_drain")?),
                    close: mem::transmute::<*mut c_void, Finish>(find(c"snd_pcm_close")?),
                })
            }
        }
    }

    fn device_name() -> CString {
        std::env::var_os("COLOR_ALSA_DEVICE")
            .map(OsString::into_vec)
            .filter(|name| !name.is_empty())
            .and_then(|name| CString::new(name).ok())
            .unwrap_or_else(|| c"default".to_owned())
    }

    /// One of the few places among the sounds that play at the same time.
    struct Turn;

    impl Turn {
        fn take() -> Option<Self> {
            // Counted only when granted: the count never passes the limit,
            // not even for the instant of a refusal.
            let mut playing = PLAYING.load(Ordering::Relaxed);
            while playing < MAX_PLAYING {
                let one_more = playing + 1;
                match PLAYING.compare_exchange_weak(
                    playing,
                    one_more,
                    Ordering::Relaxed,
                    Ordering::Relaxed,
                ) {
                    Ok(_) => return Some(Self),
                    Err(now) => playing = now,
                }
            }
            None
        }
    }

    impl Drop for Turn {
        fn drop(&mut self) {
            PLAYING.fetch_sub(1, Ordering::Relaxed);
        }
    }

    /// A device ready for mono 16-bit frames at RATE, or None.
    pub(super) fn open(alsa: &Alsa, device: &CStr) -> Option<*mut Pcm> {
        let mut pcm = ptr::null_mut();
        // Mode 0: blocking calls, which is what a thread of its own is for.
        if unsafe { (alsa.open)(&mut pcm, device.as_ptr(), SND_PCM_STREAM_PLAYBACK, 0) } < 0
            || pcm.is_null()
        {
            return None;
        }
        // One channel, ALSA's own resampling allowed (the 1) when the
        // device does not run at our rate.
        let set = unsafe {
            (alsa.set_params)(
                pcm,
                SND_PCM_FORMAT_S16_LE,
                SND_PCM_ACCESS_RW_INTERLEAVED,
                1,
                RATE,
                1,
                LATENCY_US,
            )
        };
        if set < 0 {
            unsafe { (alsa.close)(pcm) };
            return None;
        }
        Some(pcm)
    }

    /// Writes every frame, waits for the last one to be heard and closes
    /// the device. `frames` are little-endian 16-bit samples.
    pub(super) fn write(alsa: &Alsa, pcm: *mut Pcm, mut frames: &[u8]) {
        let mut patience = PATIENCE;
        while frames.len() >= 2 {
            let asked = (frames.len() / 2) as c_ulong;
            let written = unsafe { (alsa.writei)(pcm, frames.as_ptr().cast(), asked) };
            if written > 0 {
                // ALSA may take a part only: go on with the rest.
                let bytes = (written as usize).saturating_mul(2).min(frames.len());
                frames = &frames[bytes..];
                continue;
            }
            // An underrun, a suspended device, an interrupted call: ALSA
            // puts the device back on its feet (the 1: without a message)
            // and the same frames are offered again. Anything else, or a
            // device that keeps failing, ends this sound and no other.
            patience -= 1;
            if patience == 0 || unsafe { (alsa.recover)(pcm, written as c_int, 1) } < 0 {
                break;
            }
        }
        if frames.len() < 2 {
            unsafe { (alsa.drain)(pcm) };
        }
        unsafe { (alsa.close)(pcm) };
    }

    fn play_to_the_end(id: u32, device: &CStr, asked: Instant) {
        let Some(alsa) = LIBRARY.get_or_init(Alsa::load) else {
            GIVEN_UP.store(true, Ordering::Relaxed);
            return;
        };
        // The samples start at an even offset of their allocation.
        let Some(frames) = wav(id).and_then(|wav| wav.get(WAV_HEADER_BYTES..)) else {
            return;
        };
        let pcm = {
            let _alone = OPENING.lock();
            if GIVEN_UP.load(Ordering::Relaxed) || asked.elapsed() > TOO_LATE {
                return;
            }
            let Some(pcm) = open(alsa, device) else {
                GIVEN_UP.store(true, Ordering::Relaxed);
                return;
            };
            pcm
        };
        if asked.elapsed() > TOO_LATE {
            // The opening itself was the wait: a device held by another
            // program, or a sound server that had to be woken.
            unsafe { (alsa.close)(pcm) };
            return;
        }
        write(alsa, pcm, frames);
    }

    pub(super) fn play(id: u32) -> bool {
        if GIVEN_UP.load(Ordering::Relaxed) {
            return false;
        }
        // Read here, on the caller's thread, and once: the environment is
        // not something to read while another thread may be changing it.
        let device = DEVICE.get_or_init(device_name).as_c_str();
        let Some(turn) = Turn::take() else {
            // Four are playing: this one is dropped, and it is no failure.
            return true;
        };
        let asked = Instant::now();
        let thread = thread::Builder::new()
            .name("color-sound".to_owned())
            .stack_size(STACK_BYTES);
        let started = thread.spawn(move || {
            let _turn = turn;
            play_to_the_end(id, device, asked);
        });
        // Dropping the handle detaches the thread: nobody waits for a sound,
        // and the end of the process simply ends it. A thread that could not
        // be created has given its turn back with the closure.
        started.is_ok()
    }
}

#[cfg(target_os = "android")]
use aaudio::play;

/// What the player of Android does to the samples, apart from AAudio: here,
/// where the tests of every system reach it.
#[cfg_attr(not(any(target_os = "android", test)), allow(dead_code))]
mod mixing {
    use super::{RATE, WAV_HEADER_BYTES};
    use std::ptr;
    use std::sync::atomic::{AtomicBool, AtomicPtr, AtomicUsize, Ordering};
    use std::time::{Duration, Instant};

    /// The samples of a WAV file of the core, read as numbers from -1 to 1
    /// and brought from RATE to `rate` frames a second by drawing a straight
    /// line between two neighbours: the sounds of Color are short, and their
    /// highest partials stay far below what such a line blurs. None for a
    /// rate outside what a device plays.
    pub(super) fn ready_at(wav: &[u8], rate: u32) -> Option<Vec<f32>> {
        if !(8_000..=192_000).contains(&rate) {
            return None;
        }
        let samples: Vec<f32> = wav
            .get(WAV_HEADER_BYTES..)?
            .as_chunks::<2>()
            .0
            .iter()
            .map(|&pair| f32::from(i16::from_le_bytes(pair)) / 32_768.0)
            .collect();
        if samples.is_empty() {
            return Some(samples);
        }
        if rate == RATE {
            return Some(samples);
        }
        let length = (samples.len() as u64 * u64::from(rate)).div_ceil(u64::from(RATE)) as usize;
        let mut out = Vec::new();
        out.try_reserve_exact(length).ok()?;
        let last = samples.len() - 1;
        for frame in 0..length {
            // The place of this frame among the samples, as a whole number
            // of samples and a fraction of one, computed without rounding.
            let numerator = frame as u64 * u64::from(RATE);
            let at = (numerator / u64::from(rate)) as usize;
            let fraction = (numerator % u64::from(rate)) as f32 / rate as f32;
            let here = samples[at.min(last)];
            let next = samples[(at + 1).min(last)];
            out.push(here + (next - here) * fraction);
        }
        Some(out)
    }

    /// Adds `frames` frames of `samples`, from `position`, to every one of
    /// the `channels` of `out`. Returns the position after them.
    pub(super) fn mix_into(
        out: &mut [f32],
        channels: usize,
        samples: &[f32],
        position: usize,
    ) -> usize {
        let channels = channels.max(1);
        let frames = out.len() / channels;
        let Some(rest) = samples.get(position..) else {
            return position;
        };
        let taken = rest.len().min(frames);
        for (frame, &sample) in rest[..taken].iter().enumerate() {
            for value in &mut out[frame * channels..(frame + 1) * channels] {
                *value += sample;
            }
        }
        position + taken
    }

    /// A mix of numbers from -1 to 1 into 16-bit samples, the loud parts held
    /// at the limit rather than wrapped around.
    pub(super) fn to_i16(value: f32) -> i16 {
        (value.clamp(-1.0, 1.0) * 32_767.0) as i16
    }

    /// A sound made ready at the rate of a stream, kept for as long as the
    /// process runs.
    pub(super) struct Prepared {
        pub(super) samples: &'static [f32],
    }

    /// One place among the sounds that play: its sound and where it is in
    /// it. Taken by the thread of the sounds, which writes the sound and the
    /// position and sets `playing` last; given back by the callback, which
    /// clears `playing` after its last reading. The sound is one pointer, so
    /// that the samples of one sound are never read with the length of
    /// another.
    pub(super) struct Voice {
        sound: AtomicPtr<Prepared>,
        position: AtomicUsize,
        playing: AtomicBool,
    }

    impl Voice {
        pub(super) const fn new() -> Self {
            Self {
                sound: AtomicPtr::new(ptr::null_mut()),
                position: AtomicUsize::new(0),
                playing: AtomicBool::new(false),
            }
        }

        /// Plays `sound` from its start, unless the voice plays one already.
        pub(super) fn start(&self, sound: &'static Prepared) -> bool {
            if self.playing() {
                return false;
            }
            self.sound
                .store(ptr::from_ref(sound).cast_mut(), Ordering::Relaxed);
            self.position.store(0, Ordering::Relaxed);
            self.playing.store(true, Ordering::Release);
            true
        }

        pub(super) fn playing(&self) -> bool {
            self.playing.load(Ordering::Acquire)
        }

        pub(super) fn stop(&self) {
            self.playing.store(false, Ordering::Release);
        }
    }

    /// The frames that a stream asks for, in its format.
    pub(super) enum Output<'a> {
        Float(&'a mut [f32]),
        Short(&'a mut [i16]),
    }

    /// The voices that play, mixed into `out`: `channels` values a frame,
    /// as many whole frames as `out` holds. Advances them, and gives back
    /// those that end. Takes no lock and asks for no memory: the frames are
    /// mixed in pieces, on the stack.
    pub(super) fn fill(voices: &[Voice], channels: usize, mut out: Output<'_>) {
        const PIECE: usize = 1_024;
        let channels = channels.clamp(1, 8);
        let length = match &out {
            Output::Float(values) => values.len(),
            Output::Short(values) => values.len(),
        };
        let total = length / channels * channels;
        let mut done = 0;
        while done < total {
            // Whole frames in each piece.
            let count = (total - done).min(PIECE / channels * channels);
            let mut mix = [0f32; PIECE];
            let mix = &mut mix[..count];
            for voice in voices {
                if !voice.playing() {
                    continue;
                }
                let sound = voice.sound.load(Ordering::Relaxed);
                // Written by `start`, from a sound that lives as long as the
                // process, before `playing`.
                let Some(sound) = (unsafe { sound.as_ref() }) else {
                    voice.stop();
                    continue;
                };
                let position = voice.position.load(Ordering::Relaxed);
                let after = mix_into(mix, channels, sound.samples, position);
                voice.position.store(after, Ordering::Relaxed);
                if after >= sound.samples.len() {
                    voice.stop();
                }
            }
            match &mut out {
                Output::Float(values) => {
                    for (value, &mixed) in values[done..done + count].iter_mut().zip(mix.iter()) {
                        *value = mixed.clamp(-1.0, 1.0);
                    }
                }
                Output::Short(values) => {
                    for (value, &mixed) in values[done..done + count].iter_mut().zip(mix.iter()) {
                        *value = to_i16(mixed);
                    }
                }
            }
            done += count;
        }
    }

    /// After this long without a sound asked for, and none playing, the
    /// stream is closed.
    pub(super) const SILENCE: Duration = Duration::from_secs(3);
    /// A stream that has not called back for this long while sounds play is
    /// taken for lost: no sound of Color lasts a second.
    pub(super) const STALL: Duration = Duration::from_secs(1);

    /// Whether the thread of the sounds closes its stream: the system took
    /// it away (`lost`), it stopped calling back while sounds play, or no
    /// sound was asked for during SILENCE and none plays.
    pub(super) fn closes(
        now: Instant,
        last_asked: Option<Instant>,
        playing: bool,
        lost: bool,
        last_callback: Instant,
    ) -> bool {
        if lost {
            return true;
        }
        if playing {
            return now.saturating_duration_since(last_callback) >= STALL;
        }
        last_asked.is_none_or(|asked| now.saturating_duration_since(asked) >= SILENCE)
    }
}

/// AAudio of the NDK (Android 8 and later), opened with dlopen (P-02 of the
/// retrospective of October 2026, reworked after its review). One thread of
/// the core, for the life of the process, does everything AAudio asks for:
/// it opens one output stream at low latency when a sound is asked for,
/// gives each sound made ready at the rate of the device to one of four
/// voices, and closes the stream three seconds after the last sound, or as
/// soon as the system takes it away or it stops calling back. The stream's
/// callback mixes the voices. The caller of `play` only hands its sound
/// over: no binder call, no rendering of a sound, no wait on its thread,
/// which is the thread of the interface. A stream that cannot be opened
/// costs the sounds asked for meanwhile, and the next one tries again half a
/// second later at the soonest. A telephone without AAudio is silent, never
/// stopped.
#[cfg(target_os = "android")]
mod aaudio {
    use super::mixing::{closes, fill, ready_at, Output, Prepared, Voice};
    use super::{wav, SOUNDS};
    use std::ffi::{c_char, c_int, c_void, CStr};
    use std::sync::atomic::{AtomicBool, AtomicPtr, AtomicU32, AtomicU64, Ordering};
    use std::sync::{Condvar, Mutex, OnceLock};
    use std::time::{Duration, Instant};
    use std::{mem, ptr, thread};

    extern "C" {
        fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
        fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    }
    /// `<dlfcn.h>` of bionic: RTLD_NOW is 2 on 64-bit systems, 0 on 32-bit.
    #[cfg(target_pointer_width = "64")]
    const RTLD_NOW: c_int = 2;
    #[cfg(not(target_pointer_width = "64"))]
    const RTLD_NOW: c_int = 0;

    // `<aaudio/AAudio.h>`.
    const AAUDIO_OK: i32 = 0;
    const AAUDIO_DIRECTION_OUTPUT: i32 = 0;
    const AAUDIO_FORMAT_PCM_I16: i32 = 1;
    const AAUDIO_FORMAT_PCM_FLOAT: i32 = 2;
    const AAUDIO_SHARING_MODE_SHARED: i32 = 1;
    const AAUDIO_PERFORMANCE_MODE_LOW_LATENCY: i32 = 12;
    const AAUDIO_CALLBACK_RESULT_CONTINUE: i32 = 0;
    const AAUDIO_STREAM_STATE_UNINITIALIZED: i32 = 0;
    const AAUDIO_STREAM_STATE_STOPPING: i32 = 9;

    type Builder = c_void;
    type Stream = c_void;
    type DataCallback = unsafe extern "C" fn(*mut Stream, *mut c_void, *mut c_void, i32) -> i32;
    type ErrorCallback = unsafe extern "C" fn(*mut Stream, *mut c_void, i32);
    type CreateBuilder = unsafe extern "C" fn(*mut *mut Builder) -> i32;
    type SetInt = unsafe extern "C" fn(*mut Builder, i32);
    type SetDataCallback = unsafe extern "C" fn(*mut Builder, Option<DataCallback>, *mut c_void);
    type SetErrorCallback = unsafe extern "C" fn(*mut Builder, Option<ErrorCallback>, *mut c_void);
    type OpenStream = unsafe extern "C" fn(*mut Builder, *mut *mut Stream) -> i32;
    type DeleteBuilder = unsafe extern "C" fn(*mut Builder) -> i32;
    type StreamCall = unsafe extern "C" fn(*mut Stream) -> i32;
    type WaitForStateChange = unsafe extern "C" fn(*mut Stream, i32, *mut i32, i64) -> i32;

    /// The functions of libaaudio that the player takes.
    struct AAudio {
        create_builder: CreateBuilder,
        set_direction: SetInt,
        set_format: SetInt,
        set_channel_count: SetInt,
        set_sharing_mode: SetInt,
        set_performance_mode: SetInt,
        set_data_callback: SetDataCallback,
        set_error_callback: SetErrorCallback,
        open_stream: OpenStream,
        delete_builder: DeleteBuilder,
        request_start: StreamCall,
        request_stop: StreamCall,
        wait_for_state_change: WaitForStateChange,
        close: StreamCall,
        sample_rate: StreamCall,
        format: StreamCall,
        channel_count: StreamCall,
    }

    /// Sounds that play at the same time; a fifth is dropped.
    const VOICES: usize = 4;
    /// While a stream is open, the thread looks at it this often.
    const LOOK: Duration = Duration::from_millis(100);
    /// After a stream that could not be opened, the next try waits this long.
    const PATIENCE: Duration = Duration::from_millis(500);
    /// How long a stop is awaited before the stream is closed anyway.
    const STOPPING_NANOS: i64 = 100_000_000;
    /// Some versions of Android still call back a moment after a stop; Oboe
    /// waits as long before it closes a stream.
    const BEFORE_CLOSE: Duration = Duration::from_millis(10);
    /// In a layout, the flag of a stream of 16-bit samples.
    const SHORT: u32 = 1 << 8;

    static VOICE: [Voice; VOICES] = [const { Voice::new() }; VOICES];
    /// The layout of the last two streams, each read by its own callback
    /// only: its channels, and SHORT for 16-bit samples. A stream that still
    /// calls back a moment after the next one opened reads its own.
    static LAYOUT: [AtomicU32; 2] = [const { AtomicU32::new(1) }; 2];
    /// The open stream, whose loss alone counts, and that loss.
    static CURRENT: AtomicPtr<Stream> = AtomicPtr::new(ptr::null_mut());
    static LOST: AtomicBool = AtomicBool::new(false);
    /// Every call of a callback: a stream that stopped calling back is seen.
    static CALLBACKS: AtomicU64 = AtomicU64::new(0);

    static LIBRARY: OnceLock<Option<AAudio>> = OnceLock::new();

    /// What the caller hands to the thread of the sounds.
    struct Asked {
        sounds: Vec<u32>,
        /// When the last sound was asked for.
        last: Option<Instant>,
        /// Whether the thread runs.
        running: bool,
    }

    static ASKED: Mutex<Asked> = Mutex::new(Asked {
        sounds: Vec::new(),
        last: None,
        running: false,
    });
    static WAKE: Condvar = Condvar::new();

    /// The stream, while it is open: the thread of the sounds alone has it.
    struct Open {
        stream: *mut Stream,
        rate: u32,
    }

    impl AAudio {
        fn load() -> Option<Self> {
            // Never closed: a stream may be open until the process ends.
            let library = unsafe { dlopen(c"libaaudio.so".as_ptr(), RTLD_NOW) };
            if library.is_null() {
                return None;
            }
            let find = |name: &CStr| {
                let symbol = unsafe { dlsym(library, name.as_ptr()) };
                (!symbol.is_null()).then_some(symbol)
            };
            // The addresses are those of functions with exactly these C
            // signatures.
            unsafe {
                Some(Self {
                    create_builder: mem::transmute::<*mut c_void, CreateBuilder>(find(
                        c"AAudio_createStreamBuilder",
                    )?),
                    set_direction: mem::transmute::<*mut c_void, SetInt>(find(
                        c"AAudioStreamBuilder_setDirection",
                    )?),
                    set_format: mem::transmute::<*mut c_void, SetInt>(find(
                        c"AAudioStreamBuilder_setFormat",
                    )?),
                    set_channel_count: mem::transmute::<*mut c_void, SetInt>(find(
                        c"AAudioStreamBuilder_setChannelCount",
                    )?),
                    set_sharing_mode: mem::transmute::<*mut c_void, SetInt>(find(
                        c"AAudioStreamBuilder_setSharingMode",
                    )?),
                    set_performance_mode: mem::transmute::<*mut c_void, SetInt>(find(
                        c"AAudioStreamBuilder_setPerformanceMode",
                    )?),
                    set_data_callback: mem::transmute::<*mut c_void, SetDataCallback>(find(
                        c"AAudioStreamBuilder_setDataCallback",
                    )?),
                    set_error_callback: mem::transmute::<*mut c_void, SetErrorCallback>(find(
                        c"AAudioStreamBuilder_setErrorCallback",
                    )?),
                    open_stream: mem::transmute::<*mut c_void, OpenStream>(find(
                        c"AAudioStreamBuilder_openStream",
                    )?),
                    delete_builder: mem::transmute::<*mut c_void, DeleteBuilder>(find(
                        c"AAudioStreamBuilder_delete",
                    )?),
                    request_start: mem::transmute::<*mut c_void, StreamCall>(find(
                        c"AAudioStream_requestStart",
                    )?),
                    request_stop: mem::transmute::<*mut c_void, StreamCall>(find(
                        c"AAudioStream_requestStop",
                    )?),
                    wait_for_state_change: mem::transmute::<*mut c_void, WaitForStateChange>(find(
                        c"AAudioStream_waitForStateChange",
                    )?),
                    close: mem::transmute::<*mut c_void, StreamCall>(find(c"AAudioStream_close")?),
                    sample_rate: mem::transmute::<*mut c_void, StreamCall>(find(
                        c"AAudioStream_getSampleRate",
                    )?),
                    format: mem::transmute::<*mut c_void, StreamCall>(find(
                        c"AAudioStream_getFormat",
                    )?),
                    channel_count: mem::transmute::<*mut c_void, StreamCall>(find(
                        c"AAudioStream_getChannelCount",
                    )?),
                })
            }
        }

        /// A started stream at the rate of the device, its callback mixing
        /// the voices with the layout of `slot`, or None.
        fn open(&self, slot: usize) -> Option<Open> {
            // Cleared before the stream exists: its own loss is never erased.
            LOST.store(false, Ordering::Release);
            let mut builder = ptr::null_mut();
            if unsafe { (self.create_builder)(&mut builder) } != AAUDIO_OK || builder.is_null() {
                return None;
            }
            let mut stream = ptr::null_mut();
            let opened = unsafe {
                (self.set_direction)(builder, AAUDIO_DIRECTION_OUTPUT);
                (self.set_format)(builder, AAUDIO_FORMAT_PCM_FLOAT);
                (self.set_channel_count)(builder, 1);
                (self.set_sharing_mode)(builder, AAUDIO_SHARING_MODE_SHARED);
                (self.set_performance_mode)(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
                // The slot of its layout, handed back to the callback.
                (self.set_data_callback)(builder, Some(render), slot as *mut c_void);
                (self.set_error_callback)(builder, Some(lost), ptr::null_mut());
                let opened = (self.open_stream)(builder, &mut stream);
                (self.delete_builder)(builder);
                opened
            };
            if opened != AAUDIO_OK || stream.is_null() {
                return None;
            }
            CURRENT.store(stream, Ordering::Release);
            let rate = unsafe { (self.sample_rate)(stream) };
            let format = unsafe { (self.format)(stream) };
            let channels = unsafe { (self.channel_count)(stream) };
            let usable = (8_000..=192_000).contains(&rate)
                && (1..=8).contains(&channels)
                && (format == AAUDIO_FORMAT_PCM_FLOAT || format == AAUDIO_FORMAT_PCM_I16);
            // Written before the callback can run: it starts with the stream.
            let short = if format == AAUDIO_FORMAT_PCM_I16 {
                SHORT
            } else {
                0
            };
            LAYOUT[slot].store(channels as u32 | short, Ordering::Release);
            if !usable || unsafe { (self.request_start)(stream) } != AAUDIO_OK {
                CURRENT.store(ptr::null_mut(), Ordering::Release);
                unsafe { (self.close)(stream) };
                return None;
            }
            Some(Open {
                stream,
                rate: rate as u32,
            })
        }

        /// Stops the stream, waits until it has stopped and a moment more,
        /// closes it, and gives every voice back.
        fn shut(&self, open: Open) {
            CURRENT.store(ptr::null_mut(), Ordering::Release);
            unsafe {
                // requestStop only asks: the stream is stopping, then stopped.
                if (self.request_stop)(open.stream) == AAUDIO_OK {
                    let mut next = AAUDIO_STREAM_STATE_UNINITIALIZED;
                    (self.wait_for_state_change)(
                        open.stream,
                        AAUDIO_STREAM_STATE_STOPPING,
                        &mut next,
                        STOPPING_NANOS,
                    );
                }
            }
            thread::sleep(BEFORE_CLOSE);
            unsafe { (self.close)(open.stream) };
            for voice in &VOICE {
                voice.stop();
            }
        }
    }

    /// The callback of a stream, on a thread of AAudio: the voices that
    /// play, mixed into the frames asked for, in the layout of its own
    /// stream (`user` is its slot).
    unsafe extern "C" fn render(
        _stream: *mut Stream,
        user: *mut c_void,
        audio: *mut c_void,
        frames: i32,
    ) -> i32 {
        CALLBACKS.fetch_add(1, Ordering::Relaxed);
        if audio.is_null() || frames <= 0 {
            return AAUDIO_CALLBACK_RESULT_CONTINUE;
        }
        let layout = LAYOUT[user as usize % 2].load(Ordering::Acquire);
        let channels = ((layout & 0xff) as usize).clamp(1, 8);
        let total = frames as usize * channels;
        // AAudio hands `frames` frames of its stream's layout.
        let out = if layout & SHORT != 0 {
            Output::Short(unsafe { std::slice::from_raw_parts_mut(audio.cast::<i16>(), total) })
        } else {
            Output::Float(unsafe { std::slice::from_raw_parts_mut(audio.cast::<f32>(), total) })
        };
        fill(&VOICE, channels, out);
        AAUDIO_CALLBACK_RESULT_CONTINUE
    }

    /// Called by AAudio, on a thread of its own, when a stream is lost: the
    /// thread of the sounds closes it, as AAudio asks.
    unsafe extern "C" fn lost(stream: *mut Stream, _user: *mut c_void, _error: i32) {
        if stream == CURRENT.load(Ordering::Acquire) {
            LOST.store(true, Ordering::Release);
        }
    }

    /// Sound `id` ready at `rate`, made once, kept for as long as the process
    /// runs: a few hundred kilobytes, and another set only when the device
    /// changes rate (a headset plugged in).
    fn prepared(
        ready: &mut Vec<(u32, u32, &'static Prepared)>,
        id: u32,
        rate: u32,
    ) -> Option<&'static Prepared> {
        if let Some(&(_, _, sound)) = ready.iter().find(|(r, i, _)| *r == rate && *i == id) {
            return Some(sound);
        }
        // Every sound at eight rates: a guard, never reached; past it a sound
        // is dropped rather than made again.
        if ready.len() >= SOUNDS.len() * 8 {
            return None;
        }
        let samples: &'static [f32] = Vec::leak(ready_at(wav(id)?, rate)?);
        let sound: &'static Prepared = Box::leak(Box::new(Prepared { samples }));
        ready.push((rate, id, sound));
        Some(sound)
    }

    /// The thread of the sounds.
    fn run(aaudio: &'static AAudio) {
        let mut open: Option<Open> = None;
        let mut retry_at: Option<Instant> = None;
        let mut openings = 0usize;
        let mut ready = Vec::new();
        let mut callbacks = 0u64;
        let mut called_back = Instant::now();
        loop {
            let (sounds, last) = {
                let Ok(mut asked) = ASKED.lock() else {
                    return;
                };
                // Closed and nothing asked for: the thread sleeps.
                while asked.sounds.is_empty() && open.is_none() {
                    asked = match WAKE.wait(asked) {
                        Ok(asked) => asked,
                        Err(_) => return,
                    };
                }
                if asked.sounds.is_empty() {
                    asked = match WAKE.wait_timeout(asked, LOOK) {
                        Ok((asked, _)) => asked,
                        Err(_) => return,
                    };
                }
                (mem::take(&mut asked.sounds), asked.last)
            };
            if !sounds.is_empty()
                && open.is_none()
                && retry_at.is_none_or(|at| Instant::now() >= at)
            {
                match aaudio.open(openings % 2) {
                    Some(stream) => {
                        open = Some(stream);
                        openings = openings.wrapping_add(1);
                        retry_at = None;
                        callbacks = CALLBACKS.load(Ordering::Relaxed);
                        called_back = Instant::now();
                    }
                    None => retry_at = Some(Instant::now() + PATIENCE),
                }
            }
            let Some(rate) = open.as_ref().map(|stream| stream.rate) else {
                // No stream: these sounds are lost, not the sounds.
                continue;
            };
            for id in sounds {
                if let Some(sound) = prepared(&mut ready, id, rate) {
                    // Four playing: this one is dropped, and it is no failure.
                    let _ = VOICE.iter().any(|voice| voice.start(sound));
                }
            }
            let now = Instant::now();
            let count = CALLBACKS.load(Ordering::Relaxed);
            if count != callbacks {
                callbacks = count;
                called_back = now;
            }
            let playing = VOICE.iter().any(Voice::playing);
            if closes(
                now,
                last,
                playing,
                LOST.load(Ordering::Acquire),
                called_back,
            ) {
                if let Some(stream) = open.take() {
                    aaudio.shut(stream);
                }
            }
        }
    }

    pub(super) fn play(id: u32) -> bool {
        let Some(aaudio) = LIBRARY.get_or_init(AAudio::load).as_ref() else {
            // No AAudio on this telephone: nothing here plays sounds.
            return false;
        };
        // From here on a sound that does not start is that sound lost, not
        // the end of the sounds: the next one tries again.
        let Ok(mut asked) = ASKED.lock() else {
            return true;
        };
        if !asked.running {
            // AAudio's own code runs on this thread: a stack of its own size.
            asked.running = thread::Builder::new()
                .name("color-sound".to_owned())
                .stack_size(256 * 1024)
                .spawn(move || run(aaudio))
                .is_ok();
            if !asked.running {
                return true;
            }
        }
        if asked.sounds.len() < VOICES {
            asked.sounds.push(id);
        }
        asked.last = Some(Instant::now());
        drop(asked);
        WAKE.notify_one();
        true
    }
}

#[cfg(test)]
mod tests;
