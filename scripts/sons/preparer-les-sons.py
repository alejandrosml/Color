#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare the recorded sounds of the Rust core of Color from their originals.

  python3 -I preparer-les-sons.py ORIGINALS [--check]

ORIGINALS is a folder holding the original files named in RECORDINGS below,
as downloaded from the URLs given there. Each one must have the SHA-256
written beside it: an original that differs in any way is refused. A file
taken from an archive is read from the archive in memory, and checked too.
For a sound of Freesound, the file used is the preview in Ogg Vorbis that
Freesound gives to everyone: it hands the original only to a signed-in
account, and nobody signs in for this script.

For each recording the script decodes the original with FFmpeg, keeps one
channel (the mean of all of them), brings it to 44 100 Hz, takes the
direct current away, cuts what lies under 60 Hz — and, when the entry asks
for it, what lies above a softening frequency —, keeps the segment given
below, rises from silence and falls back to it along smooth curves so that
the first and the last samples are exactly zero, takes back what the
samples would push to one side, scales the loudest sample to the peak given
below and writes a mono 16-bit WAV file:
prototypes/native-swift-rust/core/sons/<key>.wav. The core compiles these
files in. The script also writes sons/PROVENANCE.md, which says where each
sound comes from and what was done to it, and sons/notices.txt, the credits
the core hands to « À propos » → « Licences ». Before writing anything it
checks every sound against the rules the tests of the core hold all sounds
to, and stops on the first one that breaks them.

--check   writes nothing; exit code 1 when a file is not what would be written

After decoding, every computation is an addition, a multiplication or a
division of Python floats, sines included (a short series written here,
never the mathematical library of the system): IEEE 754 makes the result
the same on every machine. Originals without loss (WAV, FLAC) decode to the
same numbers with any FFmpeg; a compressed one (Ogg Vorbis) gives the same
bytes with the same FFmpeg, and --check says when another one does not.

The originals are files from the Internet: run this script with python3 -I
from outside their folder, as above. Python 3.8 or later, ffmpeg and
ffprobe in the PATH. Nothing is downloaded here.
"""
from array import array
from pathlib import Path
import hashlib
import io
import json
import math
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'prototypes/native-swift-rust/core'
OUTPUT = CORE / 'sons'
RATE = 44100
# Frames of a millisecond, as the tests of the core count them.
MS = RATE // 1000
MAX_FRAMES = RATE
HIGH_PASS_HZ = 60.0
RULE = '-' * 80
TAU = 6.283185307179586

# The only two licences a recording may come under: neither asks anything
# of Color. The tests of the core recognise them by these names.
CC0 = {
    'name': 'CC0 1.0 universel (transfert dans le domaine public)',
    'url': 'https://creativecommons.org/publicdomain/zero/1.0/deed.fr',
}
# A work its author put in the public domain without CC0, as Wikimedia
# Commons marks it.
PD_AUTHOR = {
    'name': 'domaine public, par la volonté de son auteur (PD-author)',
    'url': 'https://commons.wikimedia.org/wiki/Template:PD-author',
}

# One entry per recorded sound of the catalogue of the core (src/sound.rs),
# under its key. Times are seconds in the original, fades milliseconds.
PENCIL_SOUNDS = {
    'page': 'https://opengameart.org/content/pencil-sounds',
    'url': 'https://opengameart.org/sites/default/files/pencil.zip',
    'original': 'pencil.zip',
    'sha256': 'e944c3a6261b4eda793247e90e0905a9b3a2bec48a4fab44fdd63a08109cd28a',
    'licence': CC0,
}

# The page of a sound of Freesound, and what its original is.
def freesound(user, number, original):
    return {
        'page': 'https://freesound.org/people/%s/sounds/%d/' % (user, number),
        'licence': CC0,
        'preview_of': original,
    }


RECORDINGS = [
    dict(freesound('Vrymaa', 753281, 'WAV, 48 kHz, 16 bits, mono, 1 min 0,7 s'), **{
        'key': 'trait',
        'tool': 'Pinceau',
        'heard': 'un pinceau qui passe une fois sur une feuille',
        'why': 'Un seul passage de pinceau, pris dans un enregistrement où l’on dessine, brosse, '
               'peint et vernit un vieux parchemin, de près, sans bruit de fond ni réverbération. '
               'Il revient sans cesse pendant qu’on peint : adouci au-dessus de 5 000 Hz.',
        'credit': '« Parchment - Draw & paint », enregistré par Vrymaa (Freesound, son n° 753281), '
                  'publié le 5 septembre 2024',
        'credit_short': '« Parchment - Draw & paint » de Vrymaa (Freesound)',
        'url': 'https://cdn.freesound.org/previews/753/753281_13973196-hq.ogg',
        'original': '753281_13973196-hq.ogg',
        'sha256': '7fbc6dad2d1a5bf08af4936aa7b1f4f92e9c52a9b63c81760f342da60259851b',
        'segment': (33.100, 33.580),
        'low_pass_hz': 5000.0,
        'fade_in_ms': 5,
        'fade_out_ms': 60,
        'peak': 3400,
    }),
    dict(PENCIL_SOUNDS, **{
        'key': 'forme',
        'tool': 'Ligne, rectangle, ovale',
        'heard': 'un crayon de papier qui trace un trait rapide sur une feuille',
        'why': 'Un seul trait, pris dans un enregistrement de crayon qui écrit sur du papier : '
               'le grain du papier, un appui qui enfle puis s’éteint.',
        'credit': '« pencil_write », enregistré par NachtmahrTV (Freesound, son n° 571800) et '
                  'republié par AntumDeluge dans « Pencil Sounds » sur OpenGameArt, le 29 novembre 2021',
        'credit_short': '« pencil_write » de NachtmahrTV, republié par AntumDeluge '
                        '(« Pencil Sounds », OpenGameArt)',
        'member': 'flac/pencil_write.flac',
        'member_sha256': 'aa835e94c7bafed9e096684a709f20de806083da5511e284d802bd16e244c025',
        'segment': (0.880, 1.200),
        'fade_in_ms': 5,
        'fade_out_ms': 30,
        'peak': 4600,
    }),
    dict(freesound('frank_the_noise', 160879, 'WAV, 48 kHz, 16 bits, stéréo, 1 min 56,5 s'), **{
        'key': 'tampon',
        'tool': 'Tampon',
        'heard': 'un tampon qu’on appuie d’un coup sur une lettre',
        'why': 'Un seul coup, pris parmi les dizaines d’un enregistrement qu’un ancien postier a fait '
               'pour retrouver le bruit des lettres qu’on tamponne au guichet : un coup sourd et bref, '
               'éteint en un cinquième de seconde.',
        'credit': '« stamp post office mail.wav », enregistré par frank_the_noise (Freesound, son '
                  'n° 160879), publié le 9 juillet 2012',
        'credit_short': '« stamp post office mail » de frank_the_noise (Freesound)',
        'url': 'https://cdn.freesound.org/previews/160/160879_1481750-hq.ogg',
        'original': '160879_1481750-hq.ogg',
        'sha256': 'b1bfc491e67d9e495ae2ac32d9289b2291a9915dd15c15913a4b62ee90dd8153',
        'segment': (57.582, 57.872),
        'fade_in_ms': 4,
        'fade_out_ms': 60,
        'peak': 5000,
    }),
    dict(freesound('13F_Panska_Koprivikova_Klara', 378317, 'WAV, 48 kHz, 16 bits, stéréo, 4,2 s'), **{
        'key': 'pot',
        'tool': 'Remplir',
        'heard': 'un seau d’eau qu’on vide, l’eau qui coule puis tombe à flots',
        'why': 'Le seau penche, un filet coule, puis le seau bascule et l’eau tombe à flots ; '
               'l’extrait s’éteint pendant qu’elle coule encore. Adouci au-dessus de 6 000 Hz : '
               'les éclaboussures y sifflaient.',
        'credit': '« pouring bucket », enregistré par 13F_Panska_Koprivikova_Klara (Freesound, son '
                  'n° 378317), publié le 29 janvier 2017',
        'credit_short': '« pouring bucket » de 13F_Panska_Koprivikova_Klara (Freesound)',
        'url': 'https://cdn.freesound.org/previews/378/378317_7020096-hq.ogg',
        'original': '378317_7020096-hq.ogg',
        'sha256': '3d43aaa1d3fe669443b7952e9654b413350620c5a697d9406c30d19076980c3d',
        'segment': (0.700, 1.600),
        'low_pass_hz': 6000.0,
        'fade_in_ms': 8,
        'fade_out_ms': 200,
        'peak': 5000,
    }),
    dict(freesound('jc144940', 180943, 'AIFF, 44,1 kHz, stéréo, 12,8 s'), **{
        'key': 'gomme',
        'tool': 'Gomme',
        'heard': 'une gomme qui efface du crayon sur une feuille, en trois allers-retours',
        'why': 'Une gomme en plastique qui efface un trait de crayon sur une feuille de cahier ; '
               'adouci au-dessus de 6 000 Hz, où le frottement sifflait. Elle remplace « pencil_erase » '
               'de « Pencil Sounds », qui était en fait un doigt frotté sur une vitre (« window finger '
               'rub », de damsur, Freesound n° 443241) : il grinçait au lieu de frotter.',
        'credit': '« eraser.aiff », enregistré par jc144940 (Freesound, son n° 180943), '
                  'publié le 15 mars 2013',
        'credit_short': '« eraser.aiff » de jc144940 (Freesound)',
        'url': 'https://cdn.freesound.org/previews/180/180943_2596329-hq.ogg',
        'original': '180943_2596329-hq.ogg',
        'sha256': 'd2b8c2fa7dd6dad8dcc2757178b51fcdb724ceec891480fa0e923ccbbb67b895',
        'segment': (7.900, 8.380),
        'low_pass_hz': 6000.0,
        'fade_in_ms': 5,
        'fade_out_ms': 40,
        'peak': 4800,
    }),
    {
        'key': 'texte',
        'tool': 'Texte',
        'heard': 'trois frappes d’une machine à écrire, sans la sonnette',
        'why': 'Trois touches d’une vraie machine à écrire, enregistrées de près au téléphone ; '
               'les frappes sont vives, comme sur la machine.',
        'credit': '« typewriter8 », enregistré au téléphone par Cassie-OrbitGames, « Typewriter '
                  'sounds » sur OpenGameArt, le 6 septembre 2025',
        'credit_short': '« typewriter8 » de Cassie-OrbitGames (« Typewriter sounds », OpenGameArt)',
        'page': 'https://opengameart.org/content/typewriter-sounds',
        'url': 'https://opengameart.org/sites/default/files/typewriter8.wav',
        'original': 'typewriter8.wav',
        'sha256': 'c29966383e602df84db68577758e34f830deb01aff6a208579ee943511217118',
        'licence': CC0,
        'segment': (0.030, 0.420),
        'fade_in_ms': 4,
        'fade_out_ms': 25,
        'peak': 4950,
        # A key strike is a click: from one sample to the next the sound
        # jumps by up to 0.86 of its peak, which no other sound may.
        'sharp': 9,
    },
    {
        'key': 'choisir',
        'tool': 'Choisir',
        'heard': 'un petit clic, bref et sourd',
        'why': 'Un clic pris en entier dans le jeu de sons d’interface de Kenney.',
        'credit': '« click2 », du « UI SFX Set » (UI Audio) de Kenney Vleugels, Kenney.nl',
        'credit_short': '« click2 » de Kenney (UI Audio, Kenney.nl)',
        'page': 'https://kenney.nl/assets/ui-audio',
        'url': 'https://kenney.nl/media/pages/assets/ui-audio/490d233f68-1677590494/kenney_ui-audio.zip',
        'original': 'kenney_ui-audio.zip',
        'sha256': '946fc23a63d535d693eb31b2eabb80c8c28d6351e2186b344ceb71b2cb1d5eb6',
        'member': 'Audio/click2.ogg',
        'member_sha256': 'c394b46bc6737f7f7edfbfa3031ce621b7a43d498d456d6198364eee9cd3e306',
        'licence': CC0,
        'segment': (0.000, 0.051),
        'fade_in_ms': 3,
        'fade_out_ms': 10,
        'peak': 3800,
    },
]


def fail(message):
    raise SystemExit('preparer-les-sons : ' + message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def original_bytes(folder, recording):
    """The bytes of the original, checked; for a member of an archive, the
    bytes of that member, checked as well."""
    path = Path(folder) / recording['original']
    if not path.is_file():
        fail('original absent : %s (à télécharger depuis %s)' % (path, recording['url']))
    data = path.read_bytes()
    if sha256(data) != recording['sha256']:
        fail('%s n’est pas l’original attendu (SHA-256 %s au lieu de %s).'
             % (path, sha256(data), recording['sha256']))
    member = recording.get('member')
    if member is None:
        return data
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        try:
            data = archive.read(member)
        except KeyError:
            fail('%s ne contient pas %s.' % (path, member))
    if sha256(data) != recording['member_sha256']:
        fail('%s de %s n’est pas le fichier attendu.' % (member, path))
    return data


def decode(data):
    """Rate, channels and the samples of the first audio stream, as floats
    at the rate of the original, the channels interleaved."""
    probe = subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', 'a:0', '-show_entries',
         'stream=sample_rate,channels', '-of', 'json', '-i', 'pipe:0'],
        input=data, capture_output=True, check=True)
    stream = json.loads(probe.stdout.decode('utf-8'))['streams'][0]
    rate, channels = int(stream['sample_rate']), int(stream['channels'])
    raw = subprocess.run(
        ['ffmpeg', '-v', 'error', '-nostdin', '-i', 'pipe:0', '-map', '0:a:0',
         '-f', 'f64le', '-acodec', 'pcm_f64le', 'pipe:1'],
        input=data, capture_output=True, check=True).stdout
    samples = array('d')
    samples.frombytes(raw[:len(raw) // 8 * 8])
    if sys.byteorder != 'little':
        samples.byteswap()
    return rate, channels, samples


def total(values):
    """The sum, one addition after the other. Not sum(): since Python 3.12
    it compensates the rounding of each addition, which changes the last
    bits of the result from one version of Python to the next."""
    result = 0.0
    for value in values:
        result += value
    return result


def mono(samples, channels):
    if channels == 1:
        return list(samples)
    count = len(samples) // channels
    return [total(samples[index * channels:(index + 1) * channels]) / channels
            for index in range(count)]


def sine(turns):
    """sin(2π·turns). The turn is folded into the quarter around zero, where
    seven terms of the series are right to 1e-9: the sine of src/sound.rs."""
    if turns < 0:
        return -sine(-turns)
    turn = turns - int(turns)
    if turn < 0.25:
        folded = turn
    elif turn < 0.75:
        folded = 0.5 - turn
    else:
        folded = turn - 1.0
    angle = TAU * folded
    square = angle * angle
    series = 1.0
    k = 12.0
    while k >= 2.0:
        series = 1.0 - series * square / (k * (k + 1.0))
        k -= 2.0
    return angle * series


def cosine(turns):
    return sine(abs(turns) + 0.25)


def resample(samples, source_rate, first, count):
    """count samples at 44 100 Hz from the frame `first` on, interpolated
    with a sinc limited by a Blackman window, 32 lobes each side. Below the
    rate of the original the sinc is widened so that nothing folds back."""
    if source_rate == RATE:
        return [samples[index] if 0 <= index < len(samples) else 0.0
                for index in range(first, first + count)]
    narrow = min(1.0, RATE / source_rate)
    half = int(32 / narrow) + 1
    kernels = {}
    out = []
    for frame in range(first, first + count):
        position = frame * source_rate
        base, phase = divmod(position, RATE)
        kernel = kernels.get(phase)
        if kernel is None:
            offset = phase / RATE
            kernel = []
            for tap in range(-half + 1, half + 1):
                distance = offset - tap
                if distance == 0:
                    value = narrow
                else:
                    x = narrow * distance
                    # sin(πx)/(πx) times the width of the band.
                    value = narrow * sine(x / 2.0) / (TAU / 2.0 * x)
                edge = distance / half
                window = 0.42 + 0.5 * cosine(edge / 2.0) + 0.08 * cosine(edge)
                kernel.append(value * window if abs(edge) < 1.0 else 0.0)
            kernels[phase] = kernel
        mixed = 0.0
        for tap, weight in zip(range(-half + 1, half + 1), kernel):
            index = base + tap
            if 0 <= index < len(samples):
                mixed += samples[index] * weight
        out.append(mixed)
    return out


def high_pass(samples):
    """A Butterworth filter of the second order at HIGH_PASS_HZ, run forth
    then back: no shift in time, twice the slope."""
    turns = HIGH_PASS_HZ / (2.0 * RATE)
    k = sine(turns) / cosine(turns)
    root2 = 1.4142135623730951
    norm = 1.0 / (1.0 + root2 * k + k * k)
    b0, b1, b2 = norm, -2.0 * norm, norm
    a1 = 2.0 * (k * k - 1.0) * norm
    a2 = (1.0 - root2 * k + k * k) * norm

    def run(values):
        out = []
        x1 = x2 = y1 = y2 = 0.0
        for x in values:
            y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, x, y1, y
            out.append(y)
        return out

    return run(run(samples)[::-1])[::-1]


def low_pass(samples, hertz):
    """A Butterworth filter of the second order at `hertz`, run forth then
    back like the high-pass: it softens what hisses above it."""
    turns = hertz / (2.0 * RATE)
    k = sine(turns) / cosine(turns)
    root2 = 1.4142135623730951
    norm = 1.0 / (1.0 + root2 * k + k * k)
    b0 = k * k * norm
    b1, b2 = 2.0 * b0, b0
    a1 = 2.0 * (k * k - 1.0) * norm
    a2 = (1.0 - root2 * k + k * k) * norm

    def run(values):
        out = []
        x1 = x2 = y1 = y2 = 0.0
        for x in values:
            y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, x, y1, y
            out.append(y)
        return out

    return run(run(samples)[::-1])[::-1]


def ease(position, length):
    """From 0 to 1 while position goes from 0 to length, without a corner at
    either end: the ease of src/sound.rs."""
    if position >= length:
        return 1.0
    x = position / length
    return x * x * (3.0 - 2.0 * x)


def prepare(recording, data):
    """The samples of the finished sound, 16-bit integers."""
    source_rate, channels, samples = decode(data)
    samples = mono(samples, channels)
    start, end = recording['segment']
    first, last = round(start * RATE), round(end * RATE)
    if not 0 <= first < last or last - first > MAX_FRAMES:
        fail('%s : segment %s impossible.' % (recording['key'], recording['segment']))
    if (len(samples) * RATE) // source_rate < last:
        fail('%s : le segment dépasse la fin de l’original.' % recording['key'])
    # The filter is run over a margin around the segment, so that the
    # segment has none of the filter's own start in it.
    margin = RATE // 4
    around_first = max(0, first - margin)
    around = resample(samples, source_rate, around_first, last + margin // 4 - around_first)
    mean = total(around) / len(around)
    around = high_pass([value - mean for value in around])
    if recording.get('low_pass_hz'):
        around = low_pass(around, recording['low_pass_hz'])
    part = around[first - around_first:last - around_first]
    count = len(part)
    rise = recording['fade_in_ms'] * MS
    fall = recording['fade_out_ms'] * MS
    if rise < 3 * MS or fall < 10 * MS or rise + fall > count:
        fail('%s : fondus impossibles.' % recording['key'])
    for index in range(count):
        part[index] *= ease(index, rise) * ease(count - 1 - index, fall)
    # A sound that swings more to one side than to the other pushes the
    # loudspeaker without making a sound: the excess is taken back along an
    # arch flat at both ends, as the core does with the sounds it makes.
    arch = []
    for index in range(count):
        x = index / (count - 1)
        bow = 4.0 * x * (1.0 - x)
        arch.append(bow * bow)
    excess = total(part) / total(arch)
    part = [value - excess * weight for value, weight in zip(part, arch)]
    loudest = max(abs(value) for value in part)
    peak = recording['peak']
    scale = peak / loudest
    out = []
    for value in part:
        scaled = value * scale
        rounded = int(scaled - 0.5) if scaled < 0 else int(scaled + 0.5)
        out.append(max(-peak, min(peak, rounded)))
    return out


def measures(samples, peak, sharp=6):
    """What the tests of the core check, and what they would say. `sharp` is
    the largest jump allowed between two neighbours, in tenths of the peak:
    6 for every sound, more for a recording made of clicks, which the tests
    of the core name one by one."""
    level = [abs(sample) for sample in samples]
    loudest = max(level)
    energy = sum(sample * sample for sample in samples)
    rms = (energy / len(samples)) ** 0.5
    steps = max(abs(b - a) for a, b in zip(samples, samples[1:]))
    early = max(level[:MS // 2 + 1])
    half = next(index for index, value in enumerate(level) if value * 2 >= loudest)
    late = max(level[len(samples) - 2 * MS:])
    balance = sum(samples)
    problems = []
    if loudest != peak:
        problems.append('crête %d au lieu de %d' % (loudest, peak))
    if samples[0] != 0 or samples[-1] != 0:
        problems.append('premier ou dernier échantillon non nul')
    if len(samples) > MAX_FRAMES:
        problems.append('plus d’une seconde')
    if early * 5 > loudest:
        problems.append('départ trop brusque (%d dans la première demi-milliseconde)' % early)
    if half < MS:
        problems.append('moitié de la crête atteinte en %d échantillons' % half)
    if late * 50 > loudest:
        problems.append('fin trop forte (%d dans les 2 dernières ms)' % late)
    if steps * 10 > loudest * sharp:
        problems.append('saut de %d entre deux échantillons' % steps)
    if rms < 500 or rms * 10 < loudest:
        problems.append('trop faible : valeur efficace %.0f' % rms)
    if abs(balance) > len(samples) // 4:
        problems.append('somme des échantillons %d' % balance)
    return {'frames': len(samples), 'rms': rms, 'step': steps, 'sum': balance,
            'late': late, 'early': early}, problems


def wav_bytes(samples):
    data = b''.join(struct.pack('<h', sample) for sample in samples)
    return (b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVEfmt '
            + struct.pack('<IHHIIHH', 16, 1, 1, RATE, RATE * 2, 2, 16)
            + b'data' + struct.pack('<I', len(data)) + data)


def seconds(value):
    return ('%.3f' % value).replace('.', ',')


def provenance(done):
    lines = [
        '# Provenance des sons enregistrés',
        '',
        'Écrit par [`scripts/sons/preparer-les-sons.py`](../../../../scripts/sons/preparer-les-sons.py) : '
        'ne pas modifier à la main. Les tests du cœur relisent ce fichier.',
        '',
        'Ces sons du catalogue de `src/sound.rs` sont des enregistrements, et non plus des recettes '
        'calculées par le cœur. Chacun est un court extrait d’un fichier publié sous **CC0** ou versé '
        'au **domaine public** par son auteur : aucune attribution n’est exigée, Color cite tout de '
        'même ses sources, ici et dans « À propos » → « Licences ». Aucun ne vient de Tux Paint ni '
        'd’EduPaint. Les originaux ne sont pas gardés dans le dépôt : chacun se retélécharge à '
        'l’adresse donnée et se reconnaît à son empreinte SHA-256. Pour un son de Freesound, le '
        'fichier utilisé est l’aperçu en Ogg Vorbis que le site publie pour tous : il ne donne '
        'l’original qu’à un compte connecté.',
        '',
        'Traitement commun, dans cet ordre : décodage par FFmpeg ; une seule voie, moyenne des voies '
        'de l’original ; passage à 44 100 Hz s’il le faut (sinus cardinal fenêtré par Blackman, '
        '32 lobes de part et d’autre) ; retrait de la composante continue ; passe-haut de Butterworth '
        'd’ordre 2 à 60 Hz, appliqué dans les deux sens ; pour certains, un passe-bas du même ordre, '
        'appliqué de même, nommé plus bas ; extrait ; montée et descente en courbe '
        '« smoothstep », qui partent de zéro et y reviennent exactement ; retrait, le long d’une arche '
        'nulle aux deux bouts, de ce qui pousserait le haut-parleur d’un côté (la somme des '
        'échantillons devient nulle) ; mise à l’échelle de l’échantillon le plus fort à la crête '
        'donnée ; arrondi au plus proche sur 16 bits. Fichier : WAV PCM, mono, 16 bits, 44 100 Hz, '
        'en-tête de 44 octets. Pour refaire les fichiers : placer les originaux dans un dossier, puis '
        '`python3 -I scripts/sons/preparer-les-sons.py DOSSIER` (`--check` vérifie sans rien écrire).',
    ]
    for recording, wav, facts in done:
        start, end = recording['segment']
        licence = recording['licence']
        lines += [
            '',
            '## « %s » — %s' % (recording['key'], recording['tool']),
            '',
            'Ce qu’on entend : %s. %s' % (recording['heard'], recording['why']),
            '',
            '- Enregistrement : %s' % recording['credit'],
            '- Page : <%s>' % recording['page'],
        ]
        if recording.get('preview_of'):
            lines += [
                '- Fichier original : <%s> — %s ; Freesound ne le donne qu’à un compte connecté'
                % (recording['page'], recording['preview_of']),
                '- Fichier utilisé : <%s> — l’aperçu en Ogg Vorbis que Freesound publie pour tous'
                % recording['url'],
                '- Licence : %s — <%s>' % (licence['name'], licence['url']),
                '- SHA-256 du fichier utilisé : `%s`' % recording['sha256'],
            ]
        else:
            lines += [
                '- Fichier original : <%s>%s' % (recording['url'], (
                    ' — membre `%s` de l’archive' % recording['member']) if recording.get('member') else ''),
                '- Licence : %s — <%s>' % (licence['name'], licence['url']),
                '- SHA-256 de l’original : `%s`' % recording['sha256'],
            ]
        if recording.get('member'):
            lines.append('- SHA-256 de `%s` : `%s`' % (recording['member'], recording['member_sha256']))
        if recording.get('low_pass_hz'):
            lines.append('- Adouci : passe-bas de Butterworth d’ordre 2 à %s Hz, appliqué dans les deux sens'
                         % '{:,.0f}'.format(recording['low_pass_hz']).replace(',', '\u202f'))
        lines += [
            '- Extrait : de %s s à %s s du fichier' % (seconds(start), seconds(end)),
            '- Montée %d ms, descente %d ms, crête %d (%s dBFS)' % (
                recording['fade_in_ms'], recording['fade_out_ms'], recording['peak'],
                ('%.1f' % (20 * math.log10(recording['peak'] / 32768))).replace('.', ',').replace('-', '−')),
            '- Fichier du cœur : `sons/%s.wav`, %d octets, %d échantillons (%s s)' % (
                recording['key'], len(wav), facts['frames'], seconds((facts['frames'] - 1) / RATE)),
            '- SHA-256 du fichier du cœur : `%s`' % sha256(wav),
        ]
    return '\n'.join(lines) + '\n'


def notices(done):
    """Entries of the page « Licences », as in the NOTICES file of Flutter:
    a name, an empty line, the notice."""
    entries = []
    for recording, wav, facts in done:
        licence = recording['licence']
        entries.append(
            'Sons enregistrés\n\n'
            'Son « %s » (%s) : extrait de %s\n'
            '%s\n'
            'Licence : %s — %s\n'
            'Aucune attribution n’est exigée ; Color cite ses sources.\n'
            % (recording['key'], recording['tool'], recording['credit_short'],
               recording['page'], licence['name'], licence['url']))
    return ('\n' + RULE + '\n').join(entries)


def main(arguments):
    options = [argument for argument in arguments[1:] if argument.startswith('--')]
    folders = [argument for argument in arguments[1:] if not argument.startswith('--')]
    if len(folders) != 1 or set(options) - {'--check'}:
        print(__doc__)
        return 2
    # Every original is checked before anything is computed.
    originals = [original_bytes(folders[0], recording) for recording in RECORDINGS]
    done = []
    for recording, data in zip(RECORDINGS, originals):
        samples = prepare(recording, data)
        facts, problems = measures(samples, recording['peak'], recording.get('sharp', 6))
        print('%-8s %6d échantillons, valeur efficace %5.0f, plus grand saut %5d, somme %+d'
              % (recording['key'], facts['frames'], facts['rms'], facts['step'], facts['sum']))
        if problems:
            fail('%s : %s.' % (recording['key'], ' ; '.join(problems)))
        done.append((recording, wav_bytes(samples), facts))
    files = {OUTPUT / ('%s.wav' % recording['key']): wav for recording, wav, _ in done}
    files[OUTPUT / 'PROVENANCE.md'] = provenance(done).encode('utf-8')
    files[OUTPUT / 'notices.txt'] = notices(done).encode('utf-8')
    if '--check' in options:
        stale = [path for path, data in files.items()
                 if not path.is_file() or path.read_bytes() != data]
        for path in stale:
            print('%s n’est pas ce que le script écrirait.' % path)
        if stale:
            return 1
        print('%d sons : les fichiers de %s sont à jour.' % (len(done), OUTPUT))
        return 0
    OUTPUT.mkdir(exist_ok=True)
    for path, data in files.items():
        path.write_bytes(data)
        print('%s, %d octets' % (path, len(data)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
