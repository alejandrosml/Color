#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build Color on this Mac with the project's own recipe, then hand the app over.

  construire-color.py TRAVAIL [SOURCES]

TRAVAIL is the delivery folder. It holds one or several folders of sources,
named Color-<version>-sources, and receives a journal and the finished app.
The newest sources are built, or the folder named SOURCES.

What this does, in order:
  1. checks what the build needs and says plainly what is missing;
  2. runs scripts/build-flutter-study.py unchanged: Rust core, analysis, the
     Dart/Rust bridge, the Flutter tests, the release build, local signature;
  3. if only the tests stop the recipe, still builds an application, clearly
     marked as not qualified, so that it can be looked at while the tests are;
  4. copies the application beside the sources, with a ZIP that keeps the
     links of its frameworks, then runs the tests of the Rust core;
  5. writes what happened in a journal that can be read from outside.

It deletes nothing of the user's and replaces no file of theirs: every run
has its own journal and hands its application over in a folder of its own.
The only folders it reuses from one run to the next are its working folders,
one set per version, which the recipe itself refreshes. It starts no window
but the one that shows the result in the Finder, sends no key or pointer
event, wakes no virtual machine and prints nothing on paper.

Written for the Python that a Mac may have: 3.8 or later.
"""
from pathlib import Path
import datetime
import hashlib
import json
import os
import platform
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import time
import zipfile

SOURCES_NAME = re.compile(r'^Color-(\d+)\.(\d+)\.(\d+)\+(\d+)-sources$')
PINNED_FLUTTER = '9584c6713b324636289d067944a46fd6b49df14b'
MINIMUM_FREE_BYTES = 4 * 1024 ** 3
# Where the previous builds of this Mac keep the pinned SDK, the dependency
# cache and their working folders. Another place can be named for a trial.
LOCAL = Path(os.environ.get(
    'COLOR_LOCAL_BUILD',
    os.path.expanduser('~/Color-construction')))
SDK = LOCAL / 'flutter-toolchain' / 'flutter'
PUB_CACHE = LOCAL / 'macos-clean-pub-cache'
CARGO_TARGET = LOCAL / 'macos-color-cargo-target'
TRIAL_TOOLS = os.environ.get('COLOR_TRIAL_TOOLS')  # a folder of stand-ins, for trials off the Mac
TRIAL_FREE_BYTES = os.environ.get('COLOR_TRIAL_FREE_BYTES')  # the free space such a trial pretends

# hashlib.file_digest came with Python 3.11; the recipe uses it. An older
# Python gets an equivalent before the recipe runs, the recipe is not edited.
RECIPE_RUNNER = (
    'import hashlib, runpy, sys\n'
    'if not hasattr(hashlib, "file_digest"):\n'
    '    def file_digest(stream, name, _size=262144):\n'
    '        digest = hashlib.new(name) if isinstance(name, str) else name()\n'
    '        while True:\n'
    '            block = stream.read(_size)\n'
    '            if not block:\n'
    '                return digest\n'
    '            digest.update(block)\n'
    '    hashlib.file_digest = file_digest\n'
    'sys.argv = sys.argv[1:]\n'
    'runpy.run_path(sys.argv[0], run_name="__main__")\n'
)

# During a trial off the Mac only: the recipe names codesign by its full
# path, which the stand-in then answers. Without a trial, nothing is added.
TRIAL_RUNNER = (
    'import os, subprocess\n'
    'class _StandIn(subprocess.Popen):\n'
    '    def __init__(self, args, *others, **named):\n'
    '        if not isinstance(args, (str, bytes)):\n'
    '            args = [str(part) for part in args]\n'
    '            stand_in = os.path.join(os.environ["COLOR_TRIAL_TOOLS"], os.path.basename(args[0]))\n'
    '            if args[0].startswith("/usr/bin/") and os.path.exists(stand_in):\n'
    '                args[0] = stand_in\n'
    '        super().__init__(args, *others, **named)\n'
    'subprocess.Popen = _StandIn\n'
)

PHASES = {
    'rust-dylib': 'Compilation du cœur Rust',
    'pub-get': 'Préparation des dépendances (hors ligne)',
    'analyze': 'Analyse du code',
    'dart-rust-bridge': 'Contrôle du pont entre l’interface et le cœur',
    'flutter-tests': 'Tests de l’interface — l’étape la plus longue',
    'macos-release-build': 'Compilation de l’application par Xcode',
    'sign-rust-library': 'Signature du cœur',
    'sign-app': 'Signature de l’application',
    'verify-signature': 'Vérification de la signature',
}


def tool(name, default):
    """The real tool of macOS, or its stand-in during a trial elsewhere."""
    return str(Path(TRIAL_TOOLS) / name) if TRIAL_TOOLS else default


CODESIGN = tool('codesign', '/usr/bin/codesign')
DITTO = tool('ditto', '/usr/bin/ditto')
LIPO = tool('lipo', '/usr/bin/lipo')
OPEN = tool('open', '/usr/bin/open')
SW_VERS = tool('sw_vers', '/usr/bin/sw_vers')
XCODEBUILD = tool('xcodebuild', '/usr/bin/xcodebuild')
XCODE_SELECT = tool('xcode-select', '/usr/bin/xcode-select')
NICE = tool('nice', '/usr/bin/nice')


class Build:
    """One version to build: its sources and the working folders of that version."""

    def __init__(self, folder, version):
        self.folder = folder
        self.version = version
        self.sources = folder / 'Color'
        # No « + » in the folders Xcode works in.
        name = 'macos-color-' + version.replace('+', '-')
        self.work = LOCAL / (name + '-work')
        self.output = LOCAL / (name + '-release')
        self.diagnostic_output = LOCAL / (name + '-diagnostic-release')


def now():
    return datetime.datetime.now(datetime.timezone.utc)


def stamp():
    return now().strftime('%Y%m%dT%H%M%SZ')


def sha256(path):
    digest = hashlib.sha256()
    with open(str(path), 'rb') as file:
        for block in iter(lambda: file.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


class Journal:
    """Everything said on the screen is also kept, with the state of the run."""

    def __init__(self, folder):
        self.folder = folder
        folder.mkdir(parents=True)
        self.text = (folder / 'journal.txt').open('a', encoding='utf-8')
        self.record = {'started_at_utc': now().isoformat(), 'phase': 'start', 'status': 'running'}
        self.state()

    def say(self, line=''):
        print(line, flush=True)
        self.text.write(line + '\n')
        self.text.flush()

    def keep(self, line):
        self.text.write(line + '\n')
        self.text.flush()

    def state(self, **fields):
        self.record.update(fields)
        self.record['updated_at_utc'] = now().isoformat()
        partial = self.folder / 'etat.json.partial'
        partial.write_text(json.dumps(self.record, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        os.replace(partial, self.folder / 'etat.json')


def output_of(command, timeout=60):
    """(exit code, text) of a short command; a missing tool is exit code None."""
    try:
        result = subprocess.run([str(part) for part in command], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, universal_newlines=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, str(error)
    return result.returncode, result.stdout.strip()


def homebrew_rust():
    """What Homebrew knows of its formula « rust » on this Mac, or None.

    Color is built with the Rust that Homebrew provides, so a newer release
    waiting there is worth a line. Homebrew's index is read as it stands on
    this Mac: nothing is fetched, installed or updated.
    """
    brew = shutil.which('brew')
    if brew is None and TRIAL_TOOLS is None:
        for candidate in ('/opt/homebrew/bin/brew', '/usr/local/bin/brew'):
            if os.access(candidate, os.X_OK):
                brew = candidate
                break
    if brew is None:
        return None
    environment = os.environ.copy()
    environment.update(HOMEBREW_NO_AUTO_UPDATE='1', HOMEBREW_NO_ANALYTICS='1', HOMEBREW_NO_ENV_HINTS='1')
    try:
        result = subprocess.run([brew, 'info', '--json=v2', 'rust'], env=environment,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                universal_newlines=True, timeout=60)
        formula = json.loads(result.stdout)['formulae'][0]
        return {'stable': str(formula['versions']['stable']),
                'installed': [str(entry['version']) for entry in formula.get('installed') or []],
                'outdated': bool(formula.get('outdated'))}
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, IndexError, TypeError, AttributeError):
        return None


def rust_remarks(said, rustc, homebrew, reference):
    """(remarks for the screen, lines for the journal only) about the Rust in use.

    The project follows the Rust of Homebrew, whatever its release: nothing
    here stops a build.
    """
    remarks, kept = [], []
    found = re.match(r'rustc (\d+\.\d+\.\d+)', said)
    release = found.group(1) if found else None
    if release is None:
        return ['La version de Rust n’a pas pu être lue dans « ' + said[:80] + ' ».'], kept
    if '(Homebrew)' not in said:
        remarks.append('Le Rust utilisé (' + said + ', ' + rustc + ') n’est pas celui de Homebrew. '
                       'Color suit le Rust de Homebrew : « brew install rust », dans le Terminal, l’installe.')
    elif homebrew is None:
        kept.append('  Homebrew n’a pas répondu : la version de Rust qu’il propose n’a pas été lue.')
    elif homebrew['outdated'] or (homebrew['stable'] != release
                                  and tuple(map(int, homebrew['stable'].split('.')[:3]))
                                  > tuple(map(int, release.split('.')))):
        remarks.append('Homebrew propose Rust ' + homebrew['stable'] + ' ; ce Mac a encore ' + release
                       + '. Color suit le Rust de Homebrew : pour le prendre, tape « brew upgrade rust » '
                       'dans le Terminal, puis relance. La construction continue avec ' + release + '.')
    else:
        kept.append('  Rust ' + release + ' est celui que Homebrew propose sur ce Mac.')
    if reference and reference != release:
        kept.append('  Les versions Linux et Windows de ces sources sont prévues avec Rust ' + reference
                    + ' (scripts/rust-reference.json) : à aligner sur ' + release + ' à leur prochaine construction.')
    return remarks, kept


def find_sources(travail, wanted=None):
    """(Build, problem): the sources named on the command line, or the newest."""
    found = []
    try:
        children = sorted(travail.iterdir())
    except OSError as error:
        return None, 'Le dossier ' + str(travail) + ' n’a pas pu être lu (' + str(error) + ').'
    for child in children:
        name = SOURCES_NAME.match(child.name)
        # An incomplete folder is not skipped for an older one: it is reported.
        if name and child.is_dir():
            numbers = tuple(int(part) for part in name.groups())
            found.append((numbers, child, '%d.%d.%d+%d' % numbers))
    if wanted is not None:
        for _, child, version in found:
            if child.name == wanted:
                return Build(child, version), None
        return None, 'Les sources « ' + wanted + ' » sont introuvables dans ' + str(travail) + '.'
    if not found:
        return None, ('Aucun dossier de sources (Color-<version>-sources) n’a été trouvé dans '
                      + str(travail) + '.')
    _, child, version = max(found)
    return Build(child, version), None


def check_everything(build, journal):
    """What the build needs. Returns (problems, warnings, facts)."""
    problems, warnings, facts = [], [], {}
    trial = TRIAL_TOOLS is not None
    facts['python'] = sys.version.split()[0]
    facts['machine'] = platform.machine()
    facts['sources_folder'] = build.folder.name
    try:
        facts['launcher_sha256'] = sha256(Path(__file__).resolve())
    except OSError:
        facts['launcher_sha256'] = 'inconnue'
    if not trial and sys.platform != 'darwin':
        problems.append('Ce programme construit Color pour le Mac : il doit être lancé sur le Mac.')
    if not trial and platform.machine() != 'arm64':
        problems.append('Ce Mac n’a pas de processeur Apple Silicon (arm64) : la recette vise M1 et suivants.')
    code, text = output_of([SW_VERS, '-productVersion'])
    facts['macos'] = text if code == 0 else 'inconnu'

    pubspec = build.sources / 'prototypes' / 'flutter-rust' / 'pubspec.yaml'
    recipe = build.sources / 'scripts' / 'build-flutter-study.py'
    if not pubspec.is_file() or not recipe.is_file():
        problems.append('Les sources de Color sont incomplètes dans ' + str(build.folder) + '.')
    else:
        found = re.search(r'^version:\s*(\S+)', pubspec.read_text(encoding='utf-8'), re.M)
        facts['sources_version'] = found.group(1) if found else 'inconnue'
        if facts['sources_version'] != build.version:
            problems.append('Le dossier ' + build.folder.name + ' contient la version '
                            + facts['sources_version'] + ', pas ' + build.version + '.')

    if not (SDK / 'bin' / 'flutter').is_file():
        problems.append('Le SDK Flutter est introuvable : ' + str(SDK) + '.')
    else:
        dart_sdk = SDK / 'bin' / 'cache' / 'dart-sdk'
        if not (dart_sdk / 'bin' / 'dart').exists():
            if dart_sdk.is_symlink():
                target = os.readlink(str(dart_sdk))
                if target.startswith('/Volumes/'):
                    disk = target.split('/')[2]
                    problems.append('Le disque « ' + disk + ' » n’est pas branché, ou pas lisible : une partie '
                                    'du SDK (Dart) s’y trouve. Branche-le, puis relance.')
                else:
                    problems.append('Le SDK Dart est introuvable : ' + target + '.')
            else:
                problems.append('Le SDK Dart est introuvable dans le SDK Flutter.')
        code, text = output_of(['git', '-C', SDK, 'rev-parse', 'HEAD'])
        facts['flutter_commit'] = text if code == 0 else 'inconnu'
        if code == 0 and text != PINNED_FLUTTER:
            problems.append('Le SDK Flutter n’est pas à la révision épinglée du projet (' + text[:10] + ').')
        elif code != 0:
            problems.append('La révision du SDK Flutter n’a pas pu être lue : ' + text.splitlines()[-1][:200]
                            if text else 'La révision du SDK Flutter n’a pas pu être lue.')
    if not PUB_CACHE.is_dir():
        problems.append('Le cache des dépendances est introuvable : ' + str(PUB_CACHE) + '.')

    code, text = output_of([XCODE_SELECT, '-p'])
    facts['xcode_developer_dir'] = text if code == 0 else 'inconnu'
    code, text = output_of([XCODEBUILD, '-version'], timeout=120)
    facts['xcode'] = ' '.join(text.split()) if code == 0 else 'inconnu'
    if code != 0:
        detail = (text or '').strip().splitlines()
        problems.append('Xcode ne répond pas (xcodebuild -version) : ' + (detail[-1][:300] if detail else 'absent')
                        + ' — si Xcode demande sa licence ou la fin de son installation, ouvre-le une fois, '
                        'puis relance.')

    rustc = shutil.which('rustc')
    if rustc is None:
        problems.append('Le compilateur Rust (rustc) est introuvable. Color suit le Rust de Homebrew : '
                        '« brew install rust », dans le Terminal, l’installe.')
    else:
        code, text = output_of([rustc, '--version'])
        facts['rustc'] = text if code == 0 else 'inconnu'
        facts['rustc_path'] = rustc
        if code != 0:
            problems.append('Le compilateur Rust ne répond pas : ' + text[:200])
        else:
            homebrew = homebrew_rust()
            facts['homebrew_rust'] = homebrew
            reference = None
            try:
                reference = json.loads((build.sources / 'scripts' / 'rust-reference.json')
                                       .read_text(encoding='utf-8')).get('rust_version')
            except (OSError, ValueError, AttributeError):
                pass
            facts['rust_reference'] = reference
            remarks, kept = rust_remarks(text, rustc, homebrew, reference)
            warnings.extend(remarks)
            for line in kept:
                journal.keep(line)

    try:
        free = (int(TRIAL_FREE_BYTES) if trial and TRIAL_FREE_BYTES
                else shutil.disk_usage(str(LOCAL if LOCAL.exists() else LOCAL.parent)).free)
        facts['free_bytes'] = free
        if free < MINIMUM_FREE_BYTES:
            problems.append('Il reste %.1f Go libres sur le disque ; la construction en demande au moins %d.'
                            % (free / 1024 ** 3, MINIMUM_FREE_BYTES // 1024 ** 3))
    except (OSError, ValueError) as error:
        warnings.append('La place libre n’a pas pu être mesurée : ' + str(error))
    for key in sorted(facts):
        journal.keep('  ' + key + ' = ' + str(facts[key]))
    return problems, warnings, facts


def recipe_environment(build, dylib):
    """The environment the recipe gives its own commands."""
    environment = os.environ.copy()
    environment.update(FLUTTER_SUPPRESS_ANALYTICS='true', CI='true', PUB_CACHE=str(PUB_CACHE),
                       XDG_CONFIG_HOME=str(build.work.parent / 'flutter-config'),
                       MACOSX_DEPLOYMENT_TARGET='26.6', EDUPAINT_CORE_LIBRARY=str(dylib))
    return environment


def run_recipe(build, report, journal):
    """The project's recipe, unchanged. Returns its result.json as a dict."""
    recipe = build.sources / 'scripts' / 'build-flutter-study.py'
    runner = (TRIAL_RUNNER if TRIAL_TOOLS else '') + RECIPE_RUNNER
    command = [NICE, '-n', '10', sys.executable, '-c', runner, str(recipe),
               '--sdk-dir', str(SDK), '--work-dir', str(build.work), '--output-dir', str(build.output),
               '--report-dir', str(report), '--pub-cache', str(PUB_CACHE),
               '--offline', '--test-concurrency', '2']
    journal.keep('$ ' + ' '.join(command[:4]) + ' … ' + ' '.join(command[6:]))
    started = time.time()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               universal_newlines=True, bufsize=1)
    last_lines = []
    for line in process.stdout:
        line = line.rstrip('\n')
        journal.keep('recette: ' + line)
        last_lines = (last_lines + [line])[-12:]
        if line in PHASES:
            journal.say('  [%4d s] %s…' % (time.time() - started, PHASES[line]))
            journal.state(phase=line)
    code = process.wait()
    result = {}
    try:
        result = json.loads((report / 'result.json').read_text(encoding='utf-8'))
    except (OSError, ValueError):
        pass
    result.setdefault('status', 'failed' if code else 'unknown')
    result['recipe_exit_code'] = code
    result['seconds'] = round(time.time() - started)
    result['last_lines'] = last_lines
    return result


def test_summary(report):
    """(passed, skipped, failed, names of failed tests) from the log of the Flutter tests."""
    try:
        text = (report / 'flutter-tests.log').read_text(encoding='utf-8', errors='replace')
    except OSError:
        return None
    text = text.replace('\r', '\n')
    counts = re.findall(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?: (?:All tests passed!|Some tests failed\.)', text)
    passed, skipped, failed = (int(value or 0) for value in counts[-1]) if counts else (0, 0, 0)
    names = []
    for line in text.splitlines():
        found = re.match(r'^\d+:\d+ \+\d+(?: ~\d+)?(?: -\d+)?: (.+) \[E\]\s*$', line)
        if found and found.group(1) not in names:
            names.append(found.group(1))
    return passed, skipped, failed, names


def logged(name, command, folder, journal, cwd=None, environment=None):
    """Run one command with its output in a log of the journal; True on success."""
    journal.keep('$ ' + ' '.join(str(part) for part in command))
    with (folder / (name + '.log')).open('w') as log:
        code = subprocess.call([str(part) for part in command], cwd=str(cwd) if cwd else None,
                               env=environment, stdout=log, stderr=subprocess.STDOUT)
    journal.keep('  exit ' + str(code))
    return code == 0


def diagnostic_build(build, journal, folder):
    """The steps of the recipe that follow the tests, in a folder of their own.

    Only used when the tests alone stopped the recipe: the staging is the
    recipe's, analysed and resolved, and the Rust library is the one it built.
    """
    dylib = build.output / 'libedupaint_core.dylib'
    environment = recipe_environment(build, dylib)
    flutter = SDK / 'bin' / 'flutter'
    if not logged('diagnostic-macos-release-build',
                  [NICE, '-n', '10', flutter, 'build', 'macos', '--release', '--no-pub'],
                  folder, journal, cwd=build.work, environment=environment):
        return None
    built = build.work / 'build' / 'macos' / 'Build' / 'Products' / 'Release' / 'Color.app'
    # One folder per run, named like its journal: nothing is ever replaced.
    target = build.diagnostic_output / journal.folder.name
    if target.exists() or not built.is_dir():
        return None
    target.mkdir(parents=True)
    app = target / 'Color.app'
    # ditto keeps the links of the frameworks, as the recipe's copy does.
    if not logged('diagnostic-copy', [DITTO, built, app], folder, journal):
        return None
    marker = app / 'Contents' / 'Resources' / 'edupaint-diagnostics.enabled'
    if marker.exists():
        return None  # a diagnostics build is not what is handed over here
    embedded = app / 'Contents' / 'Frameworks' / 'libedupaint_core.dylib'
    shutil.copy2(str(dylib), str(embedded))
    steps = [
        ('diagnostic-sign-rust-library', [CODESIGN, '--force', '--sign', '-', embedded]),
        ('diagnostic-sign-app', [CODESIGN, '--force', '--sign', '-', '--entitlements',
                                 build.work / 'macos' / 'Runner' / 'Release.entitlements', app]),
        ('diagnostic-verify-signature', [CODESIGN, '--verify', '--deep', '--strict', app]),
    ]
    for name, command in steps:
        if not logged(name, command, folder, journal, cwd=build.work, environment=environment):
            return None
    return app


def describe(app):
    """Version, identifier and architectures of a built application."""
    with (app / 'Contents' / 'Info.plist').open('rb') as file:
        info = plistlib.load(file)
    binary = app / 'Contents' / 'MacOS' / info.get('CFBundleExecutable', 'Color')
    code, architectures = output_of([LIPO, '-archs', binary])
    return {
        'name': info.get('CFBundleName'),
        'version': info.get('CFBundleShortVersionString'),
        'build': info.get('CFBundleVersion'),
        'identifier': info.get('CFBundleIdentifier'),
        'minimum_macos': info.get('LSMinimumSystemVersion'),
        'architectures': architectures if code == 0 else 'inconnues',
    }


def new_folder(parent, name):
    """A folder that did not exist: the name, or the name with the first free number."""
    candidate = parent / name
    number = 2
    while candidate.exists():
        candidate = parent / (name + ' (' + str(number) + ')')
        number += 1
    candidate.mkdir(parents=True)
    return candidate


def describe_archive(archive):
    """What the ZIP holds, read back: its size, its digest, its entries and its links."""
    facts = {'bytes': archive.stat().st_size, 'sha256': sha256(archive)}
    with zipfile.ZipFile(str(archive)) as package:
        entries = package.infolist()
    facts['entries'] = len(entries)
    facts['links'] = sum(1 for entry in entries if stat.S_ISLNK(entry.external_attr >> 16))
    return facts


def hand_over(app, travail, title, version, journal, folder):
    """Copy the application beside the sources, with a ZIP; returns (folder, archive facts)."""
    delivery = new_folder(travail, title)
    copy = delivery / 'Color.app'
    if not logged('remise-copie', [DITTO, app, copy], folder, journal):
        return None, None
    if not logged('remise-signature', [CODESIGN, '--verify', '--deep', '--strict', copy], folder, journal):
        return None, None
    archive = delivery / ('Color-' + version + '-mac.zip')
    packed = None
    if logged('remise-zip', [DITTO, '-c', '-k', '--sequesterRsrc', '--keepParent', copy, archive],
              folder, journal):
        try:
            packed = describe_archive(archive)
            journal.keep('  ZIP : %(bytes)d octets, %(entries)d entrées dont %(links)d liens, sha256 %(sha256)s'
                         % packed)
        except (OSError, zipfile.BadZipFile) as error:
            journal.say('  (le ZIP n’a pas pu être relu : ' + str(error) + ')')
    else:
        journal.say('  (le ZIP n’a pas pu être fait ; l’application, elle, est en place)')
    return delivery, packed


def core_tests(build, journal, folder):
    """The tests of the Rust core, which the recipe does not run. Never fatal."""
    cargo = shutil.which('cargo')
    if cargo is None:
        journal.say('  cargo est introuvable : tests du cœur non exécutés.')
        return {'status': 'not_run', 'reason': 'cargo not found'}
    core = build.sources / 'prototypes' / 'native-swift-rust' / 'core'
    environment = os.environ.copy()
    environment['CARGO_TARGET_DIR'] = str(CARGO_TARGET)
    outcome = {}
    for name, extra in [('debug', []), ('release', ['--release'])]:
        log_name = 'rust-tests-' + name
        ok = logged(log_name, [NICE, '-n', '10', cargo, 'test', '--offline'] + extra, folder, journal,
                    cwd=core, environment=environment)
        text = (folder / (log_name + '.log')).read_text(encoding='utf-8', errors='replace')
        results = re.findall(r'test result: \w+\. (\d+) passed; (\d+) failed', text)
        passed = sum(int(p) for p, _ in results)
        failed = sum(int(f) for _, f in results)
        outcome[name] = {'ok': ok, 'passed': passed, 'failed': failed}
        journal.say('  cœur Rust, %s : %d réussis, %d en échec%s'
                    % (name, passed, failed, '' if ok else ' — voir ' + log_name + '.log'))
    outcome['status'] = 'passed' if all(outcome[n]['ok'] for n in ('debug', 'release')) else 'failed'
    return outcome


def write_notice(delivery, version, qualified, facts, tests, failed_names, core, journal_folder):
    title = 'Color ' + version + ' pour ce Mac'
    lines = [title, '=' * len(title), '']
    if qualified:
        lines += ['Double-clique sur Color.app pour l’ouvrir.', '',
                  'Cette application a été construite sur ce Mac par la recette du projet :',
                  'analyse, tests, compilation par Xcode, signature locale.',
                  'La construction ne l’ouvre pas : son essai à l’écran reste à faire.']
    else:
        lines += ['ATTENTION : application NON QUALIFIÉE.', '',
                  'Des tests de l’interface ont échoué sur ce Mac. L’application a tout de',
                  'même été compilée et signée pour que tu puisses la regarder, mais elle',
                  'n’a pas passé la recette du projet. Tests en échec :']
        lines += ['  - ' + name for name in failed_names[:40]] or ['  (voir flutter-tests.log)']
    if tests:
        lines += ['', 'Tests de l’interface : %d réussis, %d ignorés, %d en échec.' % tests[:3]]
    if core.get('status') == 'not_run':
        lines += ['Tests du cœur Rust : non exécutés (cargo introuvable).']
    else:
        lines += ['Tests du cœur Rust : %d réussis, %d en échec (debug) ; %d réussis, %d en échec (release).'
                  % (core['debug']['passed'], core['debug']['failed'],
                     core['release']['passed'], core['release']['failed'])]
        if core.get('status') != 'passed':
            lines += ['ATTENTION : les tests du cœur Rust n’ont pas tous réussi sur ce Mac.']
    lines += ['', 'Signature locale seulement : ni identité de développeur, ni notarisation.',
              'Cette application est faite pour ce Mac ; pour la donner à quelqu’un d’autre,',
              'il faudrait une signature de distribution.', '',
              'Depuis la version 1.0, Color porte l’identifiant fr.aisml.color, celui de',
              'l’App Store. Elle ne retrouve donc pas la copie de récupération ni',
              '« Mes dessins » des versions 0.x ; les dessins que tu as enregistrés',
              's’ouvrent toujours avec « Ouvrir ».', '',
              'macOS : ' + str(facts.get('macos')), 'Xcode : ' + str(facts.get('xcode')),
              'Rust : ' + str(facts.get('rustc')), '',
              'Journal de la construction : ' + str(journal_folder), '']
    (delivery / 'LISEZMOI.txt').write_text('\n'.join(lines), encoding='utf-8')


def main(arguments):
    if len(arguments) not in (2, 3):
        print(__doc__)
        return 2
    travail = Path(arguments[1]).resolve()
    # One journal per run; two runs in the same second get two folders.
    name = stamp()
    place = travail / 'construction-mac' / 'journal' / name
    number = 2
    while place.exists():
        place = place.with_name(name + '-' + str(number))
        number += 1
    journal = Journal(place)
    folder = journal.folder
    build, problem = find_sources(travail, arguments[2] if len(arguments) == 3 else None)
    if build is None:
        journal.say('Construction de Color pour ce Mac')
        journal.say('')
        journal.say('La construction ne peut pas commencer :')
        journal.say('  - ' + problem)
        journal.state(status='blocked', problems=[problem])
        return 1
    version = build.version
    journal.state(version=version)
    journal.say('Construction de Color ' + version + ' pour ce Mac')
    journal.say('Compte cinq à dix minutes. Tu peux continuer à travailler ; laisse simplement')
    journal.say('cette fenêtre ouverte. Rien n’est supprimé ni remplacé dans tes dossiers.')
    journal.say('')
    journal.say('1. Vérifications')
    journal.say('  sources : ' + build.folder.name)
    try:
        problems, warnings, facts = check_everything(build, journal)
    except OSError as error:
        problems, warnings, facts = ['Un dossier nécessaire n’a pas pu être lu (' + str(error) + '). Si macOS a '
                                     'demandé une autorisation pour Terminal, accepte-la, puis relance.'], [], {}
    journal.state(phase='checks', facts=facts)
    for warning in warnings:
        journal.say('  remarque : ' + warning)
    if problems:
        journal.say('')
        journal.say('La construction ne peut pas commencer :')
        for problem in problems:
            journal.say('  - ' + problem)
        journal.state(status='blocked', problems=problems)
        return 1
    journal.say('  macOS %s, %s, %s' % (facts.get('macos'), facts.get('xcode'), facts.get('rustc')))
    journal.say('  tout ce qu’il faut est là.')

    journal.say('')
    journal.say('2. Recette du projet')
    report = folder / 'recette'
    result = run_recipe(build, report, journal)
    tests = test_summary(report)
    journal.state(recipe=dict((key, result.get(key)) for key in
                              ('status', 'phase', 'exit_code', 'recipe_exit_code', 'seconds', 'reason')),
                  flutter_tests=None if tests is None else
                  {'passed': tests[0], 'skipped': tests[1], 'failed': tests[2], 'failed_names': tests[3]})
    qualified = result.get('status') == 'passed' and result.get('recipe_exit_code') == 0
    app = None
    if qualified:
        app = build.output / 'Color.app'
        journal.say('  recette réussie en %d s' % result['seconds']
                    + ('' if tests is None else ' : %d tests réussis, %d ignorés.' % tests[:2]))
    elif result.get('phase') == 'flutter-tests' and tests is not None:
        journal.say('')
        journal.say('  Les tests de l’interface ont arrêté la recette : %d réussis, %d en échec.'
                    % (tests[0], tests[2]))
        for name in tests[3][:12]:
            journal.say('    - ' + name)
        journal.say('  Je compile tout de même une application, marquée « non qualifiée ».')
        journal.state(phase='diagnostic-build')
        app = diagnostic_build(build, journal, folder)
        if app is None:
            journal.say('  La compilation de secours a échoué aussi : voir les journaux diagnostic-*.log.')
    else:
        journal.say('')
        journal.say('  La recette s’est arrêtée à l’étape « %s ».' % result.get('phase', 'inconnue'))
        log = report / (str(result.get('phase')) + '.log')
        if log.is_file():
            journal.say('  Fin de son journal :')
            for line in log.read_text(encoding='utf-8', errors='replace').splitlines()[-25:]:
                journal.say('    ' + line[:300])
        elif result.get('reason'):
            journal.say('  ' + str(result.get('reason')))
        else:
            # The recipe stopped outside its steps: what it said last tells why.
            journal.say('  Ses derniers mots :')
            for line in result.get('last_lines', []):
                journal.say('    ' + line[:300])

    delivery = None
    if app is not None and app.is_dir():
        journal.say('')
        journal.say('3. Remise de l’application')
        journal.state(phase='hand-over')
        description = describe(app)
        journal.state(application=description)
        title = 'Color ' + version + ' pour Mac' + ('' if qualified else ' - NON QUALIFIEE')
        delivery, packed = hand_over(app, travail, title, version, journal, folder)
        if delivery is None:
            journal.say('  La copie de l’application a échoué ; elle reste ici : ' + str(app))
        else:
            journal.state(archive=packed)
            journal.say('  %s %s (%s), %s' % (description['name'], description['version'],
                                               description['build'], description['architectures']))
            journal.say('  déposée dans : ' + str(delivery))

    journal.say('')
    journal.say('4. Tests du cœur Rust')
    journal.state(phase='core-tests')
    core = core_tests(build, journal, folder)
    journal.state(core_tests=core)
    core_ok = core.get('status') in ('passed', 'not_run')
    if delivery is not None:
        write_notice(delivery, version, qualified, facts, tests, tests[3] if tests else [], core, folder)

    journal.say('')
    if delivery is not None and qualified and core_ok:
        status = 'passed'
        journal.say('Terminé. Color.app est prête : double-clique dessus dans la fenêtre du Finder qui s’ouvre.')
    elif delivery is not None and qualified:
        status = 'built_core_tests_failed'
        journal.say('Terminé, avec réserve : l’application a passé la recette, mais des tests du cœur Rust')
        journal.say('ont échoué sur ce Mac (voir rust-tests-*.log dans le journal).')
    elif delivery is not None:
        status = 'built_not_qualified'
        journal.say('Terminé, avec réserve : l’application est là, mais des tests ont échoué (voir LISEZMOI.txt).')
    else:
        status = 'failed'
        journal.say('La construction n’a pas abouti. Le journal est dans : ' + str(folder))
    journal.state(status=status, phase='end', delivery=None if delivery is None else str(delivery),
                  finished_at_utc=now().isoformat())
    if delivery is not None:
        # Shows the application in the Finder; does not start it.
        subprocess.call([OPEN, '-R', str(delivery / 'Color.app')])
    return 0 if status == 'passed' else 1


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv))
    except KeyboardInterrupt:
        print('\nConstruction interrompue. Rien n’a été supprimé de tes dossiers ; elle peut être relancée.')
        sys.exit(130)
    except OSError as error:
        print('\nLa construction s’est arrêtée sur une erreur de fichier : ' + str(error))
        print('Si macOS a demandé une autorisation pour Terminal (dossier Documents, disque externe),')
        print('accepte-la, puis relance.')
        sys.exit(1)
