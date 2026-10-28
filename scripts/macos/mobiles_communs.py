# SPDX-License-Identifier: MIT
"""What the launchers for iPhone, iPad, Android and the stores share.

Everything they install lives in one folder of the Mac, MOBILES below, beside
the working folders of the Mac build: rustup and the Rust of Homebrew's
release with the targets of the telephones, a JDK, the Android SDK with its
NDK, its emulator and one system image, the emulators made from it, the
caches of Gradle. What Xcode downloads itself, the simulator of iOS, is
Xcode's. Nothing of the person's is touched; removing that folder removes
everything the launchers installed.

Written for the Python that a Mac may have: 3.8 or later.
"""
from pathlib import Path
import datetime
import fcntl
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
import traceback

LOCAL = Path(os.environ.get(
    'COLOR_LOCAL_BUILD',
    os.path.expanduser('~/Color-construction')))
FLUTTER_SDK = LOCAL / 'flutter-toolchain' / 'flutter'
PUB_CACHE = LOCAL / 'macos-clean-pub-cache'
FLUTTER_CONFIG = LOCAL / 'flutter-config'
MOBILES = LOCAL / 'mobiles'
RUSTUP_HOME = MOBILES / 'rust' / 'rustup'
CARGO_HOME = MOBILES / 'rust' / 'cargo'
CARGO_TARGET = MOBILES / 'cargo-target'
ANDROID_SDK = MOBILES / 'android-sdk'
# The preferences of the tools of Android, the emulators and the key that
# signs the builds of trial: here, and not in ~/.android.
ANDROID_USER_HOME = MOBILES / 'android-user'
JDK_FOLDER = MOBILES / 'jdk'
GRADLE_HOME = MOBILES / 'gradle'
# The releases of Java that Gradle 9.3 and the Android Gradle Plugin 9.1 of
# Flutter's template are made for, in the order they are preferred. The JDK
# of an old Android Studio, which Flutter would otherwise take first, is not
# one of them.
JAVA_RELEASES = (21, 17)
SOURCES_NAME = re.compile(r'^Color-(\d+)\.(\d+)\.(\d+)\+(\d+)-sources$')

IOS_TARGETS = ['aarch64-apple-ios', 'aarch64-apple-ios-sim']
ANDROID_TARGETS = [  # Rust target, Android ABI, clang of the NDK
    ('aarch64-linux-android', 'arm64-v8a', 'aarch64-linux-android'),
    ('armv7-linux-androideabi', 'armeabi-v7a', 'armv7a-linux-androideabi'),
    ('x86_64-linux-android', 'x86_64', 'x86_64-linux-android'),
]
ANDROID_API = 26
NDK_VERSION = '28.2.13676358'
ANDROID_PLATFORM = 'android-36'
BUILD_TOOLS = '36.0.0'
SYSTEM_IMAGE = 'system-images;android-36;google_apis;arm64-v8a'
CMDLINE_TOOLS = ('https://dl.google.com/android/repository/'
                 'commandlinetools-mac_arm64-16111833_latest.zip')
IOS_DEPLOYMENT_TARGET = '18.0'
BUNDLE_ID = 'fr.aisml.color'


LAUNCHER_NAMES = {
    'iphone-ipad': 'Essayer Color sur iPhone et iPad',
    'android': 'Essayer Color sur Android',
    'app-store': 'Envoyer Color vers l’App Store',
    'google-play': 'Préparer Color pour Google Play',
}


def hold_lock(what):
    """The lock of this kind of launcher, held as long as it runs. A second
    launcher of the same kind, from a second double click, stops at once:
    it would build in the working copy of the first. The lock goes with the
    process; its small file stays in MOBILES for the next time."""
    MOBILES.mkdir(parents=True, exist_ok=True)
    handle = (MOBILES / ('lanceur-%s.verrou' % what)).open('a')
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        print('« %s » tourne déjà dans une autre fenêtre du Terminal. Celle-ci '
              's’arrête sans rien faire ; l’autre continue.'
              % LAUNCHER_NAMES.get(what, what), flush=True)
        sys.exit(3)
    return handle


class Journal:
    """What a launcher did, on the screen and in its folder of the journal."""

    # The journal of the launcher that runs, for main_wrapper.
    current = None
    # The lock of the launcher that runs: see hold_lock.
    lock = None

    def __init__(self, travail, what):
        Journal.lock = hold_lock(what)
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        self.folder = travail / 'construction-mac' / 'journal' / (stamp + '-' + what)
        self.folder.mkdir(parents=True, exist_ok=True)
        self.captures = self.folder / 'captures'
        self.captures.mkdir(exist_ok=True)
        self._text = (self.folder / 'journal.txt').open('a', encoding='utf-8')
        self.facts = {'started_at_utc': stamp, 'what': what}
        Journal.current = self

    def say(self, line=''):
        print(line, flush=True)
        self.keep(line)

    def keep(self, line):
        self._text.write(line + '\n')
        self._text.flush()

    def state(self, **fields):
        self.facts.update(fields)
        (self.folder / 'etat.json').write_text(
            json.dumps(self.facts, indent=2, ensure_ascii=False, default=str) + '\n',
            encoding='utf-8')


def run(journal, name, command, cwd=None, env=None, timeout=None, interactive=False, check=True):
    """Runs a command; its output goes to <name>.log in the journal. With
    `interactive`, the person sees it and answers it in the Terminal."""
    command = [str(part) for part in command]
    journal.keep('$ ' + ' '.join(command))
    started = time.time()
    if interactive:
        code = subprocess.call(command, cwd=cwd, env=env)
    else:
        with (journal.folder / (name + '.log')).open('a', encoding='utf-8') as log:
            log.write('$ ' + ' '.join(command) + '\n')
            log.flush()
            try:
                code = subprocess.call(command, cwd=cwd, env=env, stdout=log,
                                       stderr=subprocess.STDOUT, timeout=timeout)
            except subprocess.TimeoutExpired:
                code = 124
    journal.keep('  exit %d, %d s' % (code, time.time() - started))
    if check and code != 0:
        raise Failure('« %s » a échoué (code %d). Détail : %s'
                      % (name, code, 'ce que le Terminal a affiché ci-dessus' if interactive
                         else journal.folder / (name + '.log')))
    return code


def output(command, env=None, timeout=120):
    """The code and the whole text of a command, its messages of errors included."""
    try:
        done = subprocess.run([str(part) for part in command], env=env, timeout=timeout,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              universal_newlines=True)
        return done.returncode, done.stdout
    except (OSError, subprocess.TimeoutExpired) as error:
        return 127, str(error)


def output_apart(command, env=None, timeout=120):
    """The code, the output and the messages of errors of a command, apart: a
    tool that answers in JSON or with a path may also complain on the side,
    as the simulator of Xcode does just after Xcode changes."""
    try:
        done = subprocess.run([str(part) for part in command], env=env, timeout=timeout,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True)
        return done.returncode, done.stdout, done.stderr
    except (OSError, subprocess.TimeoutExpired) as error:
        return 127, '', str(error)


class Failure(Exception):
    """A step that cannot go on, said in plain words."""


def check_flutter_sdk():
    """The pinned Flutter of the Mac build, whose Dart may be on an external
    disk: said at once, before anything long, when that disk is missing."""
    if not (FLUTTER_SDK / 'bin' / 'flutter').is_file():
        raise Failure('Le SDK Flutter est introuvable : %s.' % FLUTTER_SDK)
    dart_sdk = FLUTTER_SDK / 'bin' / 'cache' / 'dart-sdk'
    if (dart_sdk / 'bin' / 'dart').exists():
        return
    if dart_sdk.is_symlink():
        target = os.readlink(str(dart_sdk))
        if target.startswith('/Volumes/'):
            raise Failure('Le disque « %s » n’est pas branché, ou pas lisible : une partie du'
                          ' SDK (Dart) s’y trouve. Branche-le, puis relance.' % target.split('/')[2])
        raise Failure('Le SDK Dart est introuvable : %s.' % target)
    raise Failure('Le SDK Dart est introuvable dans le SDK Flutter.')


def find_sources(travail):
    """The newest Color-<version>-sources folder of TRAVAIL, and its version."""
    found = []
    for child in sorted(travail.iterdir()):
        name = SOURCES_NAME.match(child.name)
        if name and child.is_dir():
            numbers = tuple(int(part) for part in name.groups())
            found.append((numbers, child, '%d.%d.%d+%d' % numbers))
    if not found:
        raise Failure('Aucun dossier Color-<version>-sources dans ' + str(travail) + '.')
    _, folder, version = max(found)
    return folder, version


def download(journal, url, target, sha256=None):
    """curl, then the fingerprint when one is known."""
    target.parent.mkdir(parents=True, exist_ok=True)
    run(journal, 'telechargements', ['/usr/bin/curl', '-fL', '--retry', '3', '-o', target, url])
    if sha256:
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        if digest != sha256.lower():
            raise Failure('Empreinte inattendue pour ' + url)
    return target


def stage_app(journal, sources, work):
    """A fresh copy of the application's sources, for one build."""
    app = sources / 'Color' / 'prototypes' / 'flutter-rust'
    if not app.is_dir():
        raise Failure('Sources de l’application introuvables : ' + str(app))
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(app, work, symlinks=True,
                    ignore=shutil.ignore_patterns('build', '.dart_tool', 'jniLibs', 'rust'))
    journal.keep('Copie de travail : ' + str(work))
    return work


def homebrew_rust_version():
    code, text = output(['/opt/homebrew/bin/rustc', '--version'])
    match = re.search(r'rustc (\d+\.\d+\.\d+)', text) if code == 0 else None
    if not match:
        raise Failure('Le Rust de Homebrew est introuvable (brew install rust).')
    return match.group(1)


def rust_environment():
    environment = os.environ.copy()
    environment.update(RUSTUP_HOME=str(RUSTUP_HOME), CARGO_HOME=str(CARGO_HOME),
                       CARGO_TARGET_DIR=str(CARGO_TARGET))
    return environment


def ensure_rust(journal, targets):
    """rustup in MOBILES, the release of Homebrew's Rust, and the targets."""
    version = homebrew_rust_version()
    rustup = CARGO_HOME / 'bin' / 'rustup'
    environment = rust_environment()
    if not rustup.exists():
        journal.say('  Installation de rustup (une fois)…')
        base = 'https://static.rust-lang.org/rustup/dist/aarch64-apple-darwin/rustup-init'
        init = MOBILES / 'rust' / 'rustup-init'
        download(journal, base + '.sha256', init.with_suffix('.sha256'))
        digest = init.with_suffix('.sha256').read_text().split()[0]
        download(journal, base, init, digest)
        init.chmod(0o755)
        run(journal, 'rustup', [init, '-y', '--no-modify-path', '--profile', 'minimal',
                                '--default-toolchain', 'none'], env=environment)
    code, installed = output([rustup, 'toolchain', 'list'], env=environment)
    if version not in installed:
        journal.say('  Rust %s pour les téléphones (une fois)…' % version)
        run(journal, 'rustup', [rustup, 'toolchain', 'install', version, '--profile', 'minimal'],
            env=environment)
    code, have = output([rustup, 'target', 'list', '--installed', '--toolchain', version],
                        env=environment)
    missing = [target for target in targets if target not in have.split()]
    if missing:
        run(journal, 'rustup', [rustup, 'target', 'add', '--toolchain', version] + missing,
            env=environment)
    return [str(rustup), 'run', version, 'cargo'], environment


def core_folder(sources):
    return sources / 'Color' / 'prototypes' / 'native-swift-rust' / 'core'


def build_ios_core(journal, sources, work, cargo, environment):
    """The core as two static libraries: devices, and the simulator of this Mac."""
    environment = dict(environment, IPHONEOS_DEPLOYMENT_TARGET=IOS_DEPLOYMENT_TARGET)
    for target, sdk in (('aarch64-apple-ios', 'iphoneos'), ('aarch64-apple-ios-sim', 'iphonesimulator')):
        run(journal, 'coeur-ios', cargo + ['rustc', '--release', '--lib', '--offline', '--frozen',
                                           '--target', target, '--crate-type', 'staticlib'],
            cwd=core_folder(sources), env=environment)
        place = work / 'ios' / 'rust' / sdk
        place.mkdir(parents=True, exist_ok=True)
        shutil.copy2(CARGO_TARGET / target / 'release' / 'libedupaint_core.a', place)


def build_android_core(journal, sources, work, cargo, environment):
    """One libedupaint_core.so per processor, linked by the NDK, 16 KB pages."""
    tools = ANDROID_SDK / 'ndk' / NDK_VERSION / 'toolchains' / 'llvm' / 'prebuilt' / 'darwin-x86_64' / 'bin'
    for target, abi, clang in ANDROID_TARGETS:
        variable = 'CARGO_TARGET_%s_LINKER' % target.upper().replace('-', '_')
        env = dict(environment, **{variable: str(tools / ('%s%d-clang' % (clang, ANDROID_API)))})
        run(journal, 'coeur-android', cargo + [
            'rustc', '--release', '--lib', '--offline', '--frozen', '--target', target,
            '--crate-type', 'cdylib', '--', '-C', 'link-arg=-Wl,-soname,libedupaint_core.so',
            '-C', 'link-arg=-Wl,-z,max-page-size=16384'], cwd=core_folder(sources), env=env)
        place = work / 'android' / 'app' / 'src' / 'main' / 'jniLibs' / abi
        place.mkdir(parents=True, exist_ok=True)
        shutil.copy2(CARGO_TARGET / target / 'release' / 'libedupaint_core.so', place)


def java_release(home):
    """The major release of the JDK at `home`, read in its file « release »."""
    try:
        text = (Path(home) / 'release').read_text(encoding='utf-8', errors='replace')
    except OSError:
        return None
    match = re.search(r'^JAVA_VERSION="(?:1\.)?(\d+)', text, re.MULTILINE)
    return int(match.group(1)) if match else None


def installed_java_home():
    """A JDK of one of JAVA_RELEASES, 21 first: one of this Mac's, else the one
    installed in MOBILES; None when there is none. The release is read in
    the JDK itself, whatever java_home answers."""
    homes = []
    code, listing, _ = output_apart(['/usr/libexec/java_home', '-X'])
    if code == 0 and listing.strip():
        try:
            homes += [jvm['JVMHomePath'] for jvm in plistlib.loads(listing.encode('utf-8'))
                      if isinstance(jvm, dict) and jvm.get('JVMHomePath')]
        except Exception:  # an unreadable list is a list without a JDK
            pass
    homes += [str(found) for found in sorted(JDK_FOLDER.glob('*/Contents/Home'))]
    for wanted in JAVA_RELEASES:
        for home in homes:
            if java_release(home) == wanted and (Path(home) / 'bin' / 'java').exists():
                return home
    return None


def flutter_jdk(journal, java_home, work, environment):
    """Tells Flutter which JDK to give Gradle. Without it, Flutter takes the
    JDK of Android Studio before JAVA_HOME, however old it is."""
    flutter(journal, 'flutter-config', ['config', '--jdk-dir=' + str(java_home)], work,
            environment)
    journal.say('  JDK pour Flutter et Gradle : %s (Java %s)' % (java_home, java_release(java_home)))


def android_environment(java_home):
    """The variables that send the tools of Android to MOBILES."""
    environment = os.environ.copy()
    environment.update(
        JAVA_HOME=str(java_home), ANDROID_HOME=str(ANDROID_SDK), ANDROID_SDK_ROOT=str(ANDROID_SDK),
        GRADLE_USER_HOME=str(GRADLE_HOME), ANDROID_USER_HOME=str(ANDROID_USER_HOME),
        ANDROID_EMULATOR_HOME=str(ANDROID_USER_HOME), ANDROID_AVD_HOME=str(ANDROID_USER_HOME / 'avd'))
    (ANDROID_USER_HOME / 'avd').mkdir(parents=True, exist_ok=True)
    return environment


def flutter_environment(extra=None):
    environment = os.environ.copy()
    environment.update(FLUTTER_SUPPRESS_ANALYTICS='true', PUB_CACHE=str(PUB_CACHE),
                       XDG_CONFIG_HOME=str(FLUTTER_CONFIG))
    environment['PATH'] = str(FLUTTER_SDK / 'bin') + ':' + environment.get('PATH', '')
    environment.pop('EDUPAINT_CORE_LIBRARY', None)
    if extra:
        environment.update(extra)
    return environment


def flutter(journal, name, arguments, work, environment, timeout=None):
    return run(journal, name, [FLUTTER_SDK / 'bin' / 'flutter'] + arguments, cwd=work,
               env=environment, timeout=timeout)


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return None


def summary_of_self_test(results):
    """One line per check, from what the trial build wrote."""
    if not isinstance(results, dict):
        return ['  essai intégré : aucun résultat lu']
    lines = []
    for name in ('core', 'project', 'png', 'folders', 'sound'):
        check = results.get(name)
        if isinstance(check, dict):
            lines.append('  %-8s %s' % (name, 'réussi' if check.get('ok') else
                                        'ÉCHEC : ' + str(check.get('error'))))
    lines.append('  => ' + ('tout réussi' if results.get('passed') else 'au moins un échec'))
    return lines


def main_wrapper(body):
    """Runs a launcher. Whatever stops it is said plainly on the screen and
    written in its journal: a Failure in its own words, anything else with
    its trace, so that the journal alone tells what happened."""
    try:
        body()
    except Failure as failure:
        stopped('ARRÊT : ' + str(failure), 'failed')
        sys.exit(1)
    except KeyboardInterrupt:
        stopped('Interrompu.', 'interrupted')
        sys.exit(130)
    except Exception:
        trace = traceback.format_exc()
        print(trace, flush=True)
        stopped('ARRÊT inattendu. La trace ci-dessus est aussi dans le journal.', 'failed', trace)
        sys.exit(1)


def stopped(message, status, trace=None):
    print('\n' + message, flush=True)
    journal = Journal.current
    if journal is None:
        return
    try:
        if trace:
            journal.keep(trace)
        journal.keep(message)
        journal.state(status=status, reason=message)
        print('Journal : ' + str(journal.folder), flush=True)
    except OSError:
        pass
