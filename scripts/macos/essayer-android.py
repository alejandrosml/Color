#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Builds Color for Android on this Mac and tries it in the emulator of the
Android SDK, on a tablet and a telephone, without a real device.

  essayer-android.py TRAVAIL

TRAVAIL is the folder of the deliveries (Color-travail); the newest
Color-<version>-sources in it is built. In order:
  1. installs, once, in the folder « mobiles » beside the other build
     folders: a JDK, the Android SDK with its NDK, its emulator and one
     system image of Android 16 (about 6 GB in all); the licences of Google
     are shown in the Terminal, and the person accepts them or not;
  2. installs, once, the Rust of Homebrew's release with Android's targets;
  3. builds the core for the three processors, then Color twice: a trial
     build that checks the core, the files, a picture and a sound on the
     device itself, and the normal build;
  4. creates, once, a tablet and a telephone of the emulator, starts them,
     runs the trial on each, takes a picture of the screen, and leaves Color
     open on both;
  5. writes all of it in construction-mac/journal.

It installs nothing outside the folder « mobiles », deletes nothing of the
person's, and never touches a real device.
"""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import time
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mobiles_communs import (ANDROID_PLATFORM, ANDROID_SDK, ANDROID_TARGETS,  # noqa: E402
                             BUILD_TOOLS, BUNDLE_ID, CMDLINE_TOOLS, JDK_FOLDER, MOBILES,
                             NDK_VERSION, SYSTEM_IMAGE, Failure, Journal, android_environment,
                             build_android_core, check_flutter_sdk, download, ensure_rust,
                             find_sources, flutter, flutter_environment, flutter_jdk,
                             installed_java_home, main_wrapper, output, run, stage_app,
                             summary_of_self_test)

ADB = ANDROID_SDK / 'platform-tools' / 'adb'
EMULATOR = ANDROID_SDK / 'emulator' / 'emulator'
SDKMANAGER = ANDROID_SDK / 'cmdline-tools' / 'latest' / 'bin' / 'sdkmanager'
AVDMANAGER = ANDROID_SDK / 'cmdline-tools' / 'latest' / 'bin' / 'avdmanager'
DEVICES = [  # name of the emulator, model of avdmanager, label, port
    ('Color_tablette', 'pixel_tablet', 'tablette', 5554),
    ('Color_telephone', 'pixel_9', 'telephone', 5556),
]


def java_home(journal):
    """A JDK 21 or 17: the Mac's own, or a Temurin 21 installed once in « mobiles »."""
    found = installed_java_home()
    if found:
        return found
    journal.say('  Installation d’un JDK (Temurin 21, une fois, dans « mobiles »)…')
    listing = MOBILES / 'temurin.json'
    download(journal, 'https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=aarch64'
                      '&image_type=jdk&os=mac&vendor=eclipse', listing)
    try:
        package = json.loads(listing.read_text())[0]['binary']['package']
    except (ValueError, KeyError, IndexError):
        raise Failure('La liste des JDK d’Adoptium est illisible.')
    archive = download(journal, package['link'], MOBILES / package['name'], package['checksum'])
    JDK_FOLDER.mkdir(parents=True, exist_ok=True)
    run(journal, 'jdk', ['/usr/bin/tar', '-xzf', archive, '-C', JDK_FOLDER])
    archive.unlink()
    found = installed_java_home()
    if not found:
        raise Failure('Le JDK téléchargé est introuvable après son extraction.')
    return found


def ensure_sdk(journal, environment):
    """The command-line tools, the licences (the person answers), the packages."""
    if not SDKMANAGER.exists():
        journal.say('  Installation des outils d’Android (une fois)…')
        archive = download(journal, CMDLINE_TOOLS, MOBILES / 'cmdline-tools.zip')
        place = ANDROID_SDK / 'cmdline-tools'
        place.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(place)
        archive.unlink()
        (place / 'cmdline-tools').rename(place / 'latest')
        for tool in (place / 'latest' / 'bin').iterdir():
            tool.chmod(0o755)
    wanted = ['platform-tools', 'emulator', 'platforms;' + ANDROID_PLATFORM,
              'build-tools;' + BUILD_TOOLS, 'ndk;' + NDK_VERSION, SYSTEM_IMAGE]
    missing = [package for package in wanted
               if not (ANDROID_SDK / package.replace(';', '/')).exists()]
    if missing:
        journal.say('  Les licences d’Android vont s’afficher : lis-les, puis réponds « y »'
                    ' à chacune pour les accepter (ou « n » pour arrêter).')
        run(journal, 'sdk-licences', [SDKMANAGER, '--sdk_root=' + str(ANDROID_SDK), '--licenses'],
            env=environment, interactive=True, check=False)
        journal.say('  Téléchargement des outils d’Android (environ 6 Go, une fois)…')
        run(journal, 'sdk-installation', [SDKMANAGER, '--sdk_root=' + str(ANDROID_SDK)] + missing,
            env=environment, interactive=True)


def emulator_device(journal, environment, name, model):
    """The emulator named `name`, created once."""
    code, listing = output([EMULATOR, '-list-avds'], env=environment)
    if name in listing.split():
        return
    journal.say('  Création de l’émulateur « %s »…' % name)
    # The model asked for, or an older one that every avdmanager knows.
    fallbacks = {'pixel_tablet': ['pixel_tablet', 'pixel_c'],
                 'pixel_9': ['pixel_9', 'pixel_7', 'pixel_6']}.get(model, [model])
    for candidate in fallbacks:
        process = subprocess.run([str(AVDMANAGER), 'create', 'avd', '-n', name, '-k', SYSTEM_IMAGE,
                                  '-d', candidate], input='no\n', universal_newlines=True,
                                 env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        journal.keep(process.stdout)
        if process.returncode == 0:
            return
    raise Failure('L’émulateur « %s » n’a pas pu être créé.' % name)


def start(journal, environment, name, port):
    """Starts the emulator in its window and waits until Android is ready."""
    serial = 'emulator-%d' % port
    code, devices = output([ADB, 'devices'], env=environment)
    if serial not in devices:
        log = (journal.folder / ('emulateur-%s.log' % name)).open('w')
        subprocess.Popen([str(EMULATOR), '-avd', name, '-port', str(port), '-no-snapshot-save',
                          '-no-boot-anim'], env=environment, stdout=log, stderr=subprocess.STDOUT,
                         start_new_session=True)
    run(journal, 'adb', [ADB, '-s', serial, 'wait-for-device'], env=environment, timeout=600)
    for _ in range(150):
        code, booted = output([ADB, '-s', serial, 'shell', 'getprop', 'sys.boot_completed'],
                              env=environment)
        if booted.strip() == '1':
            return serial
        time.sleep(2)
    raise Failure('L’émulateur « %s » n’a pas fini de démarrer.' % name)


def trial_on(journal, environment, serial, label, trial_apk, normal_apk):
    adb = [ADB, '-s', serial]
    output(adb + ['uninstall', BUNDLE_ID], env=environment)
    run(journal, 'adb', adb + ['install', '-r', trial_apk], env=environment)
    output(adb + ['logcat', '-c'], env=environment)
    run(journal, 'adb', adb + ['shell', 'am', 'start', '-n', BUNDLE_ID + '/.MainActivity'],
        env=environment)
    results = None
    for _ in range(60):
        time.sleep(2)
        code, text = output(adb + ['shell', 'run-as', BUNDLE_ID, 'cat', 'files/color-essai.json'],
                            env=environment)
        if code == 0:
            try:
                results = json.loads(text)
                break
            except ValueError:
                pass
    code, log = output(adb + ['logcat', '-d', '-s', 'flutter:I', 'AndroidRuntime:E'],
                       env=environment)
    (journal.folder / ('logcat-%s.txt' % label)).write_text(log, encoding='utf-8')
    (journal.folder / ('essai-integre-%s.json' % label)).write_text(
        json.dumps(results, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    output(adb + ['uninstall', BUNDLE_ID], env=environment)
    run(journal, 'adb', adb + ['install', '-r', normal_apk], env=environment)
    run(journal, 'adb', adb + ['shell', 'am', 'start', '-n', BUNDLE_ID + '/.MainActivity'],
        env=environment)
    time.sleep(10)
    capture(journal, environment, serial, label)
    return results


PNG_SIGNATURE = b'\x89PNG\r\n\x1a\n'


def capture(journal, environment, serial, label):
    """A picture of the emulator's screen, in captures/<label>.png. Android
    sometimes gives back nothing at the first asking: the screen is woken and
    the picture asked again, then through a file of the emulator, and only a
    real picture is kept."""
    adb = [str(ADB), '-s', serial]
    quiet = dict(env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                 timeout=60)
    for attempt in range(5):
        if attempt:
            time.sleep(3)
        try:
            subprocess.run(adb + ['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP'], **quiet)
            picture = subprocess.run(adb + ['exec-out', 'screencap', '-p'], env=environment,
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                     timeout=60).stdout
            if not picture.startswith(PNG_SIGNATURE):
                inside = '/data/local/tmp/color-capture.png'
                subprocess.run(adb + ['shell', 'screencap', '-p', inside], **quiet)
                picture = subprocess.run(adb + ['exec-out', 'cat', inside], env=environment,
                                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                         timeout=60).stdout
        except subprocess.TimeoutExpired:
            continue
        if picture.startswith(PNG_SIGNATURE) and len(picture) > 1024:
            (journal.captures / ('%s.png' % label)).write_bytes(picture)
            journal.keep('  capture %s : %d octets, essai %d' % (label, len(picture), attempt + 1))
            return True
    journal.say('  (La capture de l’écran « %s » est restée vide : regarde l’émulateur lui-même.)'
                % label)
    return False


def main():
    travail = Path(sys.argv[1]).resolve()
    journal = Journal(travail, 'android')
    sources, version = find_sources(travail)
    check_flutter_sdk()
    journal.say('Color %s pour Android, dans l’émulateur' % version)
    journal.state(version=version, sources=str(sources), status='started')

    journal.say('\n1. Les outils d’Android')
    MOBILES.mkdir(parents=True, exist_ok=True)
    environment = android_environment(java_home(journal))
    ensure_sdk(journal, environment)
    journal.say('  JDK : ' + environment['JAVA_HOME'])

    journal.say('\n2. Rust pour Android')
    cargo, rust_env = ensure_rust(journal, [target for target, _, _ in ANDROID_TARGETS])
    rust_env.update(ANDROID_HOME=str(ANDROID_SDK))

    journal.say('\n3. Construction')
    work = stage_app(journal, sources, MOBILES / ('android-color-%s-work' % version.replace('+', '-')))
    build_android_core(journal, sources, work, cargo, rust_env)
    journal.say('  Cœur Rust pour Android : construit (3 processeurs)')
    flutter_env = flutter_environment(environment)
    flutter_jdk(journal, environment['JAVA_HOME'], work, flutter_env)
    flutter(journal, 'flutter-precache', ['precache', '--android'], work, flutter_env)
    flutter(journal, 'flutter-pub-get', ['pub', 'get', '--offline'], work, flutter_env)
    keep = MOBILES / 'android-applications'
    keep.mkdir(parents=True, exist_ok=True)
    outputs = work / 'build' / 'app' / 'outputs' / 'flutter-apk'
    flutter(journal, 'flutter-build-apk', ['build', 'apk', '--debug', '--no-pub',
                                           '--dart-define=COLOR_SELF_TEST=true'], work, flutter_env)
    trial_apk = keep / 'Color-essai.apk'
    shutil.copy2(outputs / 'app-debug.apk', trial_apk)
    flutter(journal, 'flutter-build-apk', ['build', 'apk', '--release', '--no-pub'], work, flutter_env)
    normal_apk = keep / ('Color-%s.apk' % version)
    shutil.copy2(outputs / 'app-release.apk', normal_apk)
    journal.say('  Color pour Android : construite (essai et normale) — ' + str(normal_apk))

    journal.say('\n4. Dans l’émulateur')
    all_passed = True
    for name, model, label, port in DEVICES:
        emulator_device(journal, environment, name, model)
        serial = start(journal, environment, name, port)
        results = trial_on(journal, environment, serial, label, trial_apk, normal_apk)
        journal.say('  %s :' % ('Tablette' if label == 'tablette' else 'Téléphone'))
        for line in summary_of_self_test(results):
            journal.say('  ' + line)
        all_passed = all_passed and bool(results and results.get('passed'))
    journal.state(status='passed' if all_passed else 'failed', apk=str(normal_apk))
    journal.say('\nTerminé. Color est ouverte dans les deux émulateurs : essaie-la avec la'
                ' souris (un clic vaut un doigt).')
    journal.say('Journal et captures : ' + str(journal.folder))
    subprocess.call(['/usr/bin/open', str(journal.captures)])


if __name__ == '__main__':
    main_wrapper(main)
