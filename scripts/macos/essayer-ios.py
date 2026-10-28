#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Builds Color for iPhone and iPad on this Mac and tries it in the
simulators of Xcode, without a real device.

  essayer-ios.py TRAVAIL

TRAVAIL is the folder of the deliveries (Color-travail); the newest
Color-<version>-sources in it is built. In order:
  1. checks Xcode, and downloads the simulator of iOS if Xcode has none
     (several gigabytes, once);
  2. installs, once, the Rust of Homebrew's release with the targets of
     iOS, in the folder « mobiles » beside the other build folders;
  3. builds the core for the simulator and for devices, then Color for the
     simulator twice: a trial build that checks the core, the files, a
     picture and a sound on the device itself, and the normal build;
  4. creates, once, an iPad and an iPhone of the simulator named « Color
     iPad » and « Color iPhone », starts them, runs the trial on each, takes
     a picture of the screen, and leaves Color open on both;
  5. writes all of it in construction-mac/journal.

It installs nothing outside the folder « mobiles » except what Xcode itself
downloads, deletes nothing of the person's, and never touches a real device.
"""
from pathlib import Path
import json
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mobiles_communs import (BUNDLE_ID, IOS_TARGETS, MOBILES, Failure, Journal,  # noqa: E402
                             build_ios_core, check_flutter_sdk, ensure_rust, find_sources, flutter,
                             flutter_environment, main_wrapper, output, output_apart, read_json,
                             run, stage_app, summary_of_self_test)

SIMCTL = ['/usr/bin/xcrun', 'simctl']


FIRST_LAUNCH_ADVICE = (' Xcode doit sans doute finir son installation : ouvre Xcode une fois,'
                       ' accepte d’installer les composants qu’il propose, referme-le, puis'
                       ' relance ce lanceur.')


def simulators(journal):
    """What the simulator of Xcode knows, read in its JSON alone: just after
    Xcode changes, the simulator also writes messages beside it."""
    code, text, complaints = output_apart(SIMCTL + ['list', '-j'], timeout=600)
    if complaints.strip():
        journal.keep('simctl list, messages : ' + complaints.strip())
    if code == 0:
        try:
            return json.loads(text)
        except ValueError:
            journal.keep('simctl list, réponse illisible : ' + text[:2000])
    first_launch, _ = output(['/usr/bin/xcodebuild', '-checkFirstLaunchStatus'])
    raise Failure('Le simulateur de Xcode ne répond pas (xcrun simctl list, code %d) : %s.%s'
                  % (code, (complaints or text).strip()[-600:].rstrip('.') or 'aucun message',
                     FIRST_LAUNCH_ADVICE if first_launch != 0 else ''))


def ios_runtime(listing):
    runtimes = [runtime for runtime in listing.get('runtimes', [])
                if runtime.get('platform') == 'iOS' and runtime.get('isAvailable')]
    runtimes.sort(key=lambda runtime: [int(part) for part in
                                       runtime.get('version', '0').split('.') if part.isdigit()])
    return runtimes[-1] if runtimes else None


def device_type(listing, runtime, family):
    """The newest model of `family` ('iPad' or 'iPhone') that the runtime knows."""
    supported = {kind.get('identifier') for kind in runtime.get('supportedDeviceTypes', [])}
    kinds = [kind for kind in listing.get('devicetypes', [])
             if kind.get('identifier') in supported and kind.get('productFamily') == family]
    # The models whose pictures are the sizes the App Store requires: an iPad
    # of 13 inches (2732 × 2048 or 2752 × 2064), and the iPhone of the medium
    # size with the Dynamic Island, the plain « iPhone 17 » or « iPhone 16 »
    # (2622 × 1206 or 2556 × 1179).
    if family == 'iPad':
        preferred = ([kind for kind in kinds if '13-inch' in kind.get('name', '')
                      and 'Air' in kind.get('name', '')]
                     or [kind for kind in kinds if '13-inch' in kind.get('name', '')] or kinds)
    else:
        plain = [kind for kind in kinds if re.fullmatch(r'iPhone \d+', kind.get('name', ''))]
        plain.sort(key=lambda kind: int(kind['name'].split()[1]))
        preferred = (plain or [kind for kind in kinds if not re.search(
            r'\b(Pro|SE|Plus|Max|Air|mini)\b|\d+e\b', kind.get('name', ''))]
            or [kind for kind in kinds if 'SE' not in kind.get('name', '')] or kinds)
    if not preferred:
        raise Failure('Aucun modèle de %s dans le simulateur.' % family)
    return preferred[-1]


def device(journal, listing, runtime, name, family):
    """The simulator named `name`, created once."""
    for devices in listing.get('devices', {}).values():
        for found in devices:
            if found.get('name') == name and found.get('isAvailable', True):
                return found['udid']
    kind = device_type(listing, runtime, family)
    code, udid, complaints = output_apart(SIMCTL + ['create', name, kind['identifier'],
                                                    runtime['identifier']])
    udid = udid.strip()
    if code != 0 or not udid:
        raise Failure('Le simulateur « %s » n’a pas pu être créé : %s'
                      % (name, (complaints or udid).strip()[-600:]))
    journal.say('  « %s » créé : %s, iOS %s' % (name, kind.get('name'), runtime.get('version')))
    return udid


def boot(journal, udid):
    output(SIMCTL + ['boot', udid])  # already started: not an error
    run(journal, 'simulateur', SIMCTL + ['bootstatus', udid, '-b'], timeout=600)


def device_log(journal, udid, label, what):
    """What Color wrote in the log of the simulator in the last minutes: the
    lines of the trial, and why it stopped if it did."""
    code, text = output(SIMCTL + ['spawn', udid, 'log', 'show', '--style', 'compact', '--last', '4m',
                                  '--predicate', 'process == "Runner"'], timeout=180)
    (journal.folder / ('log-%s-%s.txt' % (label, what))).write_text(text, encoding='utf-8')


def trial_on(journal, udid, label, trial_app, normal_app):
    """The trial build, its results; then the normal build, open, and a picture."""
    output(SIMCTL + ['uninstall', udid, BUNDLE_ID])
    run(journal, 'simulateur', SIMCTL + ['install', udid, trial_app])
    # A start that fails is told by the results and the log, below.
    run(journal, 'simulateur', SIMCTL + ['launch', udid, BUNDLE_ID], check=False)
    code, container, _ = output_apart(SIMCTL + ['get_app_container', udid, BUNDLE_ID, 'data'])
    results = None
    for _ in range(60):
        time.sleep(2)
        if code == 0:
            results = read_json(Path(container.strip()) / 'Library' / 'Application Support'
                                / 'color-essai.json')
        if results:
            break
    (journal.folder / ('essai-integre-%s.json' % label)).write_text(
        json.dumps(results, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    device_log(journal, udid, label, 'essai')
    output(SIMCTL + ['terminate', udid, BUNDLE_ID])
    # The normal build, as it will be published.
    output(SIMCTL + ['uninstall', udid, BUNDLE_ID])
    run(journal, 'simulateur', SIMCTL + ['install', udid, normal_app])
    run(journal, 'simulateur', SIMCTL + ['launch', udid, BUNDLE_ID], check=False)
    time.sleep(8)
    output(SIMCTL + ['io', udid, 'screenshot', str(journal.captures / ('%s.png' % label))])
    device_log(journal, udid, label, 'normale')
    return results


def main():
    travail = Path(sys.argv[1]).resolve()
    journal = Journal(travail, 'iphone-ipad')
    sources, version = find_sources(travail)
    check_flutter_sdk()
    journal.say('Color %s pour iPhone et iPad, dans le simulateur de Xcode' % version)
    journal.state(version=version, sources=str(sources), status='started')

    journal.say('\n1. Xcode et le simulateur d’iOS')
    code, xcode = output(['/usr/bin/xcodebuild', '-version'])
    if code != 0:
        raise Failure('Xcode ne répond pas (xcodebuild -version).')
    journal.say('  ' + xcode.strip().replace('\n', ', '))
    first_launch, said = output(['/usr/bin/xcodebuild', '-checkFirstLaunchStatus'])
    journal.keep('xcodebuild -checkFirstLaunchStatus : code %d %s' % (first_launch, said.strip()))
    listing = simulators(journal)
    runtime = ios_runtime(listing)
    if runtime is None:
        journal.say('  Le simulateur d’iOS n’est pas encore installé : Xcode le télécharge'
                    ' (plusieurs gigaoctets, une seule fois)…')
        run(journal, 'simulateur-ios', ['/usr/bin/xcodebuild', '-downloadPlatform', 'iOS'],
            interactive=True)
        listing = simulators(journal)
        runtime = ios_runtime(listing)
        if runtime is None:
            raise Failure('Le simulateur d’iOS est toujours introuvable après son téléchargement.')
    journal.say('  iOS %s' % runtime.get('version'))

    journal.say('\n2. Rust pour iOS')
    cargo, rust_env = ensure_rust(journal, IOS_TARGETS)

    journal.say('\n3. Construction')
    work = stage_app(journal, sources, MOBILES / ('ios-color-%s-work' % version.replace('+', '-')))
    build_ios_core(journal, sources, work, cargo, rust_env)
    journal.say('  Cœur Rust pour iOS : construit')
    environment = flutter_environment()
    flutter(journal, 'flutter-precache', ['precache', '--ios'], work, environment)
    flutter(journal, 'flutter-pub-get', ['pub', 'get', '--offline'], work, environment)
    built = work / 'build' / 'ios' / 'iphonesimulator' / 'Runner.app'
    keep = MOBILES / 'ios-applications'
    keep.mkdir(parents=True, exist_ok=True)
    flutter(journal, 'flutter-build-ios', ['build', 'ios', '--simulator', '--debug', '--no-pub',
                                           '--dart-define=COLOR_SELF_TEST=true'], work, environment)
    trial_app = keep / 'Color-essai.app'
    shutil.rmtree(trial_app, ignore_errors=True)
    shutil.copytree(built, trial_app, symlinks=True)
    flutter(journal, 'flutter-build-ios', ['build', 'ios', '--simulator', '--debug', '--no-pub'],
            work, environment)
    normal_app = keep / 'Color.app'
    shutil.rmtree(normal_app, ignore_errors=True)
    shutil.copytree(built, normal_app, symlinks=True)
    journal.say('  Color pour le simulateur : construite (essai et normale)')

    journal.say('\n4. Dans le simulateur')
    listing = simulators(journal)
    ipad = device(journal, listing, runtime, 'Color iPad', 'iPad')
    iphone = device(journal, listing, runtime, 'Color iPhone', 'iPhone')
    simulator_window = open_simulator_window(journal)
    all_passed = True
    for label, udid in (('ipad', ipad), ('iphone', iphone)):
        boot(journal, udid)
        results = trial_on(journal, udid, label, trial_app, normal_app)
        journal.say('  %s :' % ('iPad' if label == 'ipad' else 'iPhone'))
        for line in summary_of_self_test(results):
            journal.say('  ' + line)
        all_passed = all_passed and bool(results and results.get('passed'))
    journal.state(status='passed' if all_passed else 'failed', ipad=ipad, iphone=iphone)
    journal.say('\nTerminé. Color est ouverte dans le simulateur, sur « Color iPad » et'
                ' « Color iPhone » : essaie-la avec la souris ou le trackpad.')
    if not simulator_window:
        journal.say('La fenêtre du simulateur ne s’est pas ouverte : dans Xcode, menu Xcode,'
                    ' « Open Developer Tool », « Simulator ».')
    journal.say('Journal et captures : ' + str(journal.folder))
    subprocess.call(['/usr/bin/open', str(journal.captures)])


def open_simulator_window(journal):
    """Shows the window of the simulator. The Mac does not always know
    Simulator.app by its name (« Unable to find application named
    'Simulator' » on the owner's Mac): it is opened at its place in Xcode
    first."""
    code, developer = output(['/usr/bin/xcode-select', '-p'])
    if code == 0 and developer.strip():
        app = Path(developer.strip().splitlines()[-1]) / 'Applications' / 'Simulator.app'
        if app.is_dir() and subprocess.call(['/usr/bin/open', str(app)]) == 0:
            journal.keep('Simulateur ouvert : ' + str(app))
            return True
    opened = subprocess.call(['/usr/bin/open', '-a', 'Simulator']) == 0
    journal.keep('Simulateur ouvert par son nom : ' + ('oui' if opened else 'non'))
    return opened


if __name__ == '__main__':
    main_wrapper(main)
