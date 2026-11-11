#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Builds, tests, tries and packs Color on the Windows machine that runs this
script: a real Windows, x64 or ARM64, with the tools of Microsoft.

  recette.py SOURCE FLUTTER REPORT --architecture x64|arm64
             [--sans-tests-interface] [--sans-scenario]

SOURCE   the Color folder (it holds prototypes/ and scripts/)
FLUTTER  the pinned Flutter SDK
REPORT   a folder that does not exist yet: logs, pictures, pages, packages
         and resultat.json

Needs the Rust of scripts/rust-reference.json (rustup), Visual Studio with
its C++ tools, and Python 3. The core is built by cargo from its own folder,
from vendor/ alone: nothing of it is downloaded.

What it does, in order: the core (the library of the tests, the library of
the stores, its tests); the print trial of the core on a printer « Microsoft
Print To PDF » that writes a file, made here for it — the print dialog of
Windows is opened and answered by the messages of its own buttons, three
pages are written; the tests of the interface; the released program, started
and pictured; the scenario of the studio (test/live/studio_scenario.dart)
played in its real window, in French, its print dialog seen and closed
without printing; the released program started again, which must offer the
drawing that the scenario left; then the archive to unzip and the package
MSIX for the Microsoft Store.

No key and no pointer event of the system is sent, and nothing reaches a
printer of paper. A phase that fails stops the recipe, except those said
« informative »; resultat.json says where it stopped.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import zipfile

from fenetres import (IDCANCEL, WM_COMMAND, client_size, close_first_run_screens, dialogs_of, enlarge_screen,
                      main_window, picture, resize_client, stop, user32)

parser = argparse.ArgumentParser()
parser.add_argument('source')
parser.add_argument('flutter')
parser.add_argument('report')
parser.add_argument('--architecture', required=True, choices=['x64', 'arm64'])
parser.add_argument('--sans-tests-interface', action='store_true')
parser.add_argument('--sans-scenario', action='store_true')
arguments = parser.parse_args()
source = Path(arguments.source).resolve()
flutter_sdk = Path(arguments.flutter).resolve()
report = Path(arguments.report).resolve()
if report.exists():
    sys.exit('The report folder already exists: choose a new one.')
report.mkdir(parents=True)
arch = arguments.architecture
target = {'x64': 'x86_64-pc-windows-msvc', 'arm64': 'aarch64-pc-windows-msvc'}[arch]
app = source / 'prototypes' / 'flutter-rust'
core = source / 'prototypes' / 'native-swift-rust' / 'core'
flutter = str(flutter_sdk / 'bin' / 'flutter.bat')
dart = str(flutter_sdk / 'bin' / 'dart.bat')
version = re.search(r'^version:\s*(\S+)', (app / 'pubspec.yaml').read_text(encoding='utf-8'), re.M)[1]
record = {
    'scope': 'Color built, tested, tried and packed on a real Windows by scripts/windows-desktop/recette.py. '
             'No key or pointer event of the system; the print dialog answered by the messages of its buttons; '
             'the only printer writes a PDF file.',
    'version': version,
    'architecture': arch,
    'rust_target': target,
    'phases': [],
}


class Stop(Exception):
    pass


def write_record(status):
    record['status'] = status
    record['completed_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (report / 'resultat.json').write_text(json.dumps(record, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def phase(name, command, cwd=None, env=None, informative=False):
    """Runs one command, its output in REPORT/<name>.log."""
    print(name, flush=True)
    started = time.monotonic()
    with (report / f'{name}.log').open('w', encoding='utf-8', errors='replace') as log:
        done = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
    entry = {'name': name, 'seconds': round(time.monotonic() - started, 1), 'exit_code': done.returncode}
    if informative:
        entry['informative'] = True
    record['phases'].append(entry)
    if done.returncode != 0 and not informative:
        tail = (report / f'{name}.log').read_text(encoding='utf-8', errors='replace')[-3000:]
        print(tail, flush=True)
        raise Stop(name)
    return done.returncode == 0


def text_of(name):
    return (report / f'{name}.log').read_text(encoding='utf-8', errors='replace')


def sha256(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def loaded_modules(pid):
    listing = subprocess.run(['tasklist', '/M', '/FI', f'PID eq {pid}', '/FO', 'LIST'], capture_output=True,
                             text=True, errors='replace').stdout.lower()
    return {name: name in listing for name in ['edupaint_core.dll', 'flutter_windows.dll']}


def imports_of(path):
    """The names of the libraries that a program of Windows asks for at its start (64 bits)."""
    data = Path(path).read_bytes()
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    sections_count, optional_size = struct.unpack_from('<H', data, pe + 6)[0], struct.unpack_from('<H', data, pe + 20)[0]
    optional = pe + 24
    if struct.unpack_from('<H', data, optional)[0] != 0x20B:
        return []
    import_rva = struct.unpack_from('<I', data, optional + 112 + 8)[0]
    sections = [struct.unpack_from('<IIII', data, optional + optional_size + 40 * index + 8)
                for index in range(sections_count)]

    def offset(rva):
        for size, address, raw_size, raw in sections:
            if address <= rva < address + max(size, raw_size):
                return rva - address + raw
        return None

    names, at = [], offset(import_rva)
    while at is not None:
        name_rva = struct.unpack_from('<I', data, at + 12)[0]
        if name_rva == 0:
            break
        start = offset(name_rva)
        names.append(data[start:data.index(b'\0', start)].decode('ascii', 'replace'))
        at += 20
    return names


def flutter_environment(extra=None):
    environment = os.environ.copy()
    environment.update({'FLUTTER_SUPPRESS_ANALYTICS': 'true', 'CI': 'true'})
    environment.pop('EDUPAINT_CORE_LIBRARY', None)
    environment.update(extra or {})
    return environment


try:
    # ---- The desktop: what a new Windows lays over it, and room for the window.
    record['desktop'] = {'first_run_screens_ended': close_first_run_screens(), 'screen': enlarge_screen()}
    time.sleep(2)
    record['desktop']['picture'] = 'desktop.png' if picture(report / 'desktop.png') else None

    # ---- The tools. -------------------------------------------------------
    rust_version = subprocess.check_output([sys.executable, str(source / 'scripts' / 'rust-reference.py'), '--version'],
                                           text=True).strip()
    rustc = subprocess.check_output(['rustup', 'which', '--toolchain', rust_version, 'rustc'], text=True).strip()
    cargo = subprocess.check_output(['rustup', 'which', '--toolchain', rust_version, 'cargo'], text=True).strip()
    phase('rust-reference', [sys.executable, str(source / 'scripts' / 'rust-reference.py'), '--verify', rustc])
    phase('rust-version', [rustc, '--version', '--verbose'])
    phase('flutter-version', [flutter, '--version'], env=flutter_environment())
    phase('flutter-doctor', [flutter, 'doctor', '-v'], env=flutter_environment(), informative=True)
    phase('windows-version', ['cmd', '/c', 'ver'])
    record['rustc'] = text_of('rust-version').splitlines()[0]
    record['windows'] = text_of('windows-version').strip()
    record['flutter_revision'] = subprocess.check_output(['git', '-C', str(flutter_sdk), 'rev-parse', 'HEAD'],
                                                         text=True).strip()

    # ---- The core. --------------------------------------------------------
    cargo_environment = os.environ.copy()
    cargo_environment.update({'RUSTC': rustc, 'CARGO_HOME': str(report / 'cargo-home'),
                              'CARGO_TARGET_DIR': str(report / 'cargo-target')})
    built = report / 'cargo-target' / target / 'release' / 'edupaint_core.dll'
    native = report / 'native'
    native.mkdir()
    phase('rust-vendored-sources', [sys.executable, str(source / 'scripts' / 'check-vendored-sources.py'), str(core)])
    build = [cargo, 'rustc', '--release', '--lib', '--offline', '--frozen', '--target', target]
    phase('rust-library-tests', build + ['--crate-type', 'cdylib'], cwd=core, env=cargo_environment)
    tests_core = native / 'edupaint_core.dll'
    shutil.copy2(built, tests_core)
    phase('rust-library', build + ['--no-default-features', '--features', 'deflate', '--crate-type', 'cdylib'],
          cwd=core, env=cargo_environment)
    bundled_core = native / 'edupaint_core-bundle.dll'
    shutil.copy2(built, bundled_core)
    record['core'] = {'bytes': bundled_core.stat().st_size, 'sha256': sha256(bundled_core),
                      'imports': imports_of(bundled_core)}
    # Its size against the budget of these sources (Q-03): beyond, the recipe stops.
    phase('core-budget', [sys.executable, str(source / 'scripts' / 'budgets.py'), 'verifier', 'tailles',
                          f'core-windows-{arch}', str(bundled_core.stat().st_size)])
    phase('rust-tests', [cargo, 'test', '--offline', '--frozen', '--target', target, '--', '--test-threads=1'],
          cwd=core, env=cargo_environment)
    passed = re.findall(r'test result: ok\. (\d+) passed; (\d+) failed; (\d+) ignored', text_of('rust-tests'))
    record['rust_tests'] = {'passed': sum(int(a) for a, _, _ in passed), 'failed': sum(int(b) for _, b, _ in passed),
                            'ignored': sum(int(c) for _, _, c in passed)}

    # ---- The print trial of the core, on a printer that writes a file. ----
    trial = report / 'print-trial'
    pages = trial / 'pages'
    pages.mkdir(parents=True)
    port = trial / 'port' / 'page.pdf'
    port.parent.mkdir()
    phase('print-trial-printer', ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                  str(source / 'scripts' / 'windows-desktop' / 'imprimante-d-essai.ps1'), str(port)])
    trial_environment = dict(cargo_environment, COLOR_PRINT_TRIAL_PORT=str(port), COLOR_PRINT_TRIAL_PAGES=str(pages))
    phase('print-trial', [cargo, 'test', '--offline', '--frozen', '--target', target, 'print_trial', '--',
                          '--ignored', '--test-threads=1', '--nocapture'], cwd=core, env=trial_environment)
    record['print_trial'] = {
        'tests': re.findall(r'test (print::tests::trial::\S+) \.\.\.', text_of('print-trial')),
        'result': re.findall(r'test result: (\w+)\. (\d+) passed; (\d+) failed', text_of('print-trial')),
        'dialogs': re.findall(r'dialog « (.*?) » opened in ([\d.]+) s', text_of('print-trial')),
        'pages': {page.name: page.stat().st_size for page in sorted(pages.glob('*.pdf'))},
    }

    # ---- The interface. ---------------------------------------------------
    phase('flutter-pub-get', [flutter, 'pub', 'get', '--enforce-lockfile'], cwd=app, env=flutter_environment())
    phase('flutter-analyze', [flutter, 'analyze', '--no-pub'], cwd=app, env=flutter_environment())
    phase('dart-rust-bridge', [dart, 'run', 'lib/rust_document.dart', '--self-test', str(bundled_core)], cwd=app,
          env=flutter_environment())
    if not arguments.sans_tests_interface:
        # Said « informative » only so that what failed is counted and named below before the recipe stops.
        phase('flutter-tests', [flutter, 'test', '--no-pub', '--reporter', 'expanded'], cwd=app,
              env=flutter_environment({'EDUPAINT_CORE_LIBRARY': str(tests_core)}), informative=True)
        last = re.findall(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?: (All tests passed!|Some tests failed\.)',
                          text_of('flutter-tests'))
        if last:
            done, skipped, failed, verdict = last[-1]
            record['flutter_tests'] = {'passed': int(done), 'skipped': int(skipped or 0), 'failed': int(failed or 0),
                                       'verdict': verdict}
            record['flutter_tests']['failing'] = sorted(set(re.findall(
                r'^\s+(\S.*\.dart: .*)$', text_of('flutter-tests').split('Failing tests:')[-1], re.M)))[:60] \
                if failed else []
        if record.get('flutter_tests', {}).get('verdict') != 'All tests passed!':
            raise Stop('flutter-tests')
    phase('windows-release-build', [flutter, 'build', 'windows', '--release', '--no-pub'], cwd=app,
          env=flutter_environment())
    bundle = app / 'build' / 'windows' / arch / 'runner' / 'Release'

    def finish_bundle(folder):
        """The core of the stores and the libraries of Visual C++ beside the program."""
        shutil.copy2(bundled_core, folder / 'edupaint_core.dll')
        wanted = set()
        for binary in list(folder.glob('*.exe')) + list(folder.glob('*.dll')):
            wanted |= {name.lower() for name in imports_of(binary)
                       if re.match(r'(vcruntime|msvcp|vccorlib|concrt)\d', name.lower())}
        vswhere = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Microsoft Visual Studio' \
            / 'Installer' / 'vswhere.exe'
        studio = subprocess.check_output([str(vswhere), '-latest', '-products', '*', '-property', 'installationPath'],
                                         text=True).strip()
        folders = sorted((Path(studio) / 'VC' / 'Redist' / 'MSVC').glob(f'*/{arch}/Microsoft.VC*.CRT'))
        copied = []
        for name in sorted(wanted):
            for runtime in reversed(folders):
                if (runtime / name).is_file():
                    shutil.copy2(runtime / name, folder / name)
                    copied.append(name)
                    break
        return {'asked_for': sorted(wanted), 'copied_beside_the_program': copied,
                'from': str(folders[-1]) if folders else None}

    record['visual_c_runtime'] = finish_bundle(bundle)
    # Every library that the program asks for at its start is beside it, or is Windows' own.
    system32 = Path(os.environ.get('SystemRoot', r'C:\Windows')) / 'System32'
    missing = {}
    for binary in sorted(list(bundle.glob('*.exe')) + list(bundle.glob('*.dll'))):
        for name in imports_of(binary):
            low = name.lower()
            beside = (bundle / name).is_file()
            of_windows = low.startswith(('api-ms-', 'ext-ms-')) or (
                (system32 / name).is_file() and not re.match(r'(vcruntime|msvcp|vccorlib|concrt)\d', low))
            if not beside and not of_windows:
                missing.setdefault(binary.name, []).append(name)
    record['libraries_missing_beside_the_program'] = missing
    record['bundle'] = {path.relative_to(bundle).as_posix(): path.stat().st_size
                        for path in sorted(bundle.rglob('*')) if path.is_file() and path.suffix in ('.exe', '.dll')}
    if missing:
        raise Stop('libraries: ' + json.dumps(missing))

    # ---- The released program, started and pictured. ----------------------
    print('launch', flush=True)
    process = subprocess.Popen([str(bundle / 'color.exe')], cwd=bundle, env=flutter_environment(),
                               stdout=(report / 'launch.log').open('w'), stderr=subprocess.STDOUT)
    started = time.monotonic()
    window = None
    while time.monotonic() - started < 60 and process.poll() is None and window is None:
        time.sleep(.25)
        window = main_window(process.pid)
    appeared = round(time.monotonic() - started, 1)
    time.sleep(12)
    launch = {'window_appeared_after_seconds': appeared if window else None,
              'survived_12_seconds_more': process.poll() is None,
              'screen': [user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)]}
    if window and process.poll() is None:
        launch.update({'window_class': window['class'], 'window_title': window['title'],
                       'client_size': client_size(window['handle']), 'modules': loaded_modules(process.pid),
                       'picture': 'launch.png' if picture(report / 'launch.png') else None})
    stop(process)
    record['launch'] = launch
    if not window or not launch['survived_12_seconds_more'] or not all(launch.get('modules', {'x': False}).values()):
        raise Stop('launch')

    # ---- The scenario of the studio, in its real window. ------------------
    if not arguments.sans_scenario:
        phase('scenario-build', [flutter, 'build', 'windows', '--profile', '--no-pub', '-t',
                                 'test/live/studio_scenario.dart'], cwd=app, env=flutter_environment())
        played = app / 'build' / 'windows' / arch / 'runner' / 'Profile'
        finish_bundle(played)
        folder = report / 'scenario'
        shots = folder / 'shots'
        shots.mkdir(parents=True)
        print('scenario', flush=True)
        outcome = {'pictures': [], 'window_sizes': []}
        process = subprocess.Popen(
            [str(played / 'color.exe')], cwd=played, stdout=(report / 'scenario.log').open('w'),
            stderr=subprocess.STDOUT,
            env=flutter_environment({'COLOR_SCENARIO_DIR': str(folder), 'COLOR_SCENARIO_LANGUAGE': 'fr'}))
        started = time.monotonic()
        awaited = None
        result_file = folder / 'result.json'
        while time.monotonic() - started < 900 and process.poll() is None:
            window = main_window(process.pid)
            for request in sorted(shots.glob('*.request')):
                name, done = request.stem, shots / f'{request.stem}.done'
                if done.exists():
                    continue
                if picture(folder / f'{name}.png'):
                    outcome['pictures'].append(f'{name}.png')
                done.write_text('')
            for request in sorted(shots.glob('*.resize')):
                name, done = request.stem, shots / f'{request.stem}.done'
                if done.exists():
                    continue
                width, height = (int(value) for value in request.read_text().split())
                answered = bool(window) and resize_client(window['handle'], width, height)
                if answered:
                    time.sleep(1)
                outcome['window_sizes'].append({'request': name, 'asked': f'{width} x {height}',
                                                'inside_one_second_later': client_size(window['handle']) if answered
                                                else None})
                done.write_text('resized' if answered else 'unavailable')
            for request in sorted(shots.glob('*.print')):
                name, done = request.stem, shots / f'{request.stem}.done'
                if done.exists():
                    continue
                awaited = {'name': name, 'before': {d['handle'] for d in dialogs_of(process.pid)},
                           'since': time.monotonic()}
                done.write_text('ready')
            if awaited is not None:
                closed = shots / f"{awaited['name']}.closed"
                new = [d for d in dialogs_of(process.pid) if d['handle'] not in awaited['before']]
                if new:
                    dialog = new[0]
                    # Leave the dialog the time to list its printers.
                    time.sleep(3)
                    seen = {'seen': True, 'dialog': {'class': dialog['class'], 'title': dialog['title'],
                                                     'owned_by_the_window_of_color': bool(window) and dialog['owner']
                                                     == window['handle']},
                            'window_of_color_disabled_meanwhile': bool(window) and not user32.IsWindowEnabled(
                                window['handle']),
                            'seconds_to_appear': round(time.monotonic() - awaited['since'] - 3, 1)}
                    if picture(folder / f"{awaited['name']}.png"):
                        outcome['pictures'].append(f"{awaited['name']}.png")
                    # Its own button « Annuler », by its message: nothing is confirmed, nothing is printed.
                    seen['asked_to_cancel'] = bool(user32.PostMessageW(dialog['handle'], WM_COMMAND, IDCANCEL, 0))
                    limit = time.monotonic() + 15
                    while user32.IsWindow(dialog['handle']) and time.monotonic() < limit:
                        time.sleep(.2)
                    seen['gone'] = not user32.IsWindow(dialog['handle'])
                    seen['confirmed_in_the_dialog'] = False
                    outcome['print_dialog'] = seen
                    closed.write_text(json.dumps(seen, ensure_ascii=False))
                    awaited = None
                elif time.monotonic() - awaited['since'] > 45:
                    outcome['print_dialog'] = {'seen': False, 'reason': 'no new dialog in 45 seconds'}
                    closed.write_text(json.dumps(outcome['print_dialog']))
                    awaited = None
            if result_file.exists():
                break
            time.sleep(.05)
        outcome['seconds'] = round(time.monotonic() - started, 1)
        time.sleep(2)
        outcome['still_running_at_the_end'] = process.poll() is None
        stop(process)
        if result_file.exists():
            scenario = json.loads(result_file.read_text(encoding='utf-8'))
            outcome['scenario'] = scenario
            steps = scenario.get('steps', [])
            outcome['steps'] = len(steps)
            outcome['steps_not_passed'] = [step.get('name') for step in steps if step.get('passed') is False]
            outcome['step_errors'] = {step.get('name'): str(step.get('error', ''))[:900] for step in steps
                                      if step.get('passed') is False}
            outcome['passed'] = scenario.get('passed') is True
        else:
            outcome['passed'] = False
            outcome['reason'] = 'the scenario wrote no result'
        # The released program, on the same profile: it must offer the drawing left.
        process = subprocess.Popen([str(bundle / 'color.exe')], cwd=bundle, env=flutter_environment(),
                                   stdout=(report / 'release-after-scenario.log').open('w'),
                                   stderr=subprocess.STDOUT)
        time.sleep(10)
        outcome['release_after_scenario'] = {
            'survived_10_seconds': process.poll() is None,
            'picture': 'release-finds-the-recovery.png'
            if picture(folder / 'release-finds-the-recovery.png') else None}
        stop(process)
        (report / 'scenario.json').write_text(json.dumps(outcome, indent=2, ensure_ascii=False) + '\n',
                                              encoding='utf-8')
        record['scenario'] = {key: outcome.get(key) for key in
                              ['passed', 'steps', 'steps_not_passed', 'step_errors', 'seconds', 'pictures', 'print_dialog',
                               'window_sizes', 'release_after_scenario', 'reason']}
        if not outcome['passed']:
            raise Stop('scenario')

    # ---- The packages. ----------------------------------------------------
    print('packages', flush=True)
    packages = report / 'packages'
    packages.mkdir()
    name = f'Color-{version}-windows-{arch}'
    notice = (source / 'scripts' / 'windows-desktop' / 'LISEZMOI-WINDOWS.txt').read_text(encoding='utf-8')
    extras = {'LISEZMOI.txt': notice.replace('@VERSION@', version).replace('@ARCHITECTURE@', arch).encode('utf-8'),
              'LICENSE.txt': (source / 'LICENSE').read_bytes(),
              'NOTICE.txt': (source / 'NOTICE').read_bytes(),
              'third-party-notices.txt': (core / 'third-party-notices.txt').read_bytes()}
    archive = packages / f'{name}.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as packed:
        for path in sorted(bundle.rglob('*')):
            if path.is_file():
                packed.write(path, f'{name}/{path.relative_to(bundle).as_posix()}')
        for extra, content in extras.items():
            packed.writestr(f'{name}/{extra}', content)
    record['packages'] = {'archive': {'file': archive.name, 'bytes': archive.stat().st_size, 'sha256': sha256(archive),
                                      'files': len(zipfile.ZipFile(archive).namelist())}}
    # The package of the Microsoft Store: the same files, a manifest and the logos.
    kits = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Windows Kits' / '10' / 'bin'
    makers = sorted(kits.glob(f'10.*/{arch}/makeappx.exe')) or sorted(kits.glob('10.*/x64/makeappx.exe'))
    if makers:
        staging = report / 'msix'
        shutil.copytree(bundle, staging)
        (staging / 'Assets').mkdir()
        for logo in (app / 'windows' / 'msix').glob('*.png'):
            shutil.copy2(logo, staging / 'Assets' / logo.name)
        numbers = re.match(r'(\d+)\.(\d+)\.(\d+)', version)
        manifest = (app / 'windows' / 'msix' / 'AppxManifest.xml').read_text(encoding='utf-8')
        (staging / 'AppxManifest.xml').write_text(
            manifest.replace('@VERSION@', '%s.%s.%s.0' % numbers.groups()).replace('@ARCHITECTURE@', arch),
            encoding='utf-8')
        package = packages / f'{name}.msix'
        if phase('msix', [str(makers[-1]), 'pack', '/o', '/d', str(staging), '/p', str(package)], informative=True):
            record['packages']['msix'] = {'file': package.name, 'bytes': package.stat().st_size,
                                          'sha256': sha256(package), 'signed': False, 'made_by': str(makers[-1])}
        shutil.rmtree(staging, ignore_errors=True)
    else:
        record['packages']['msix'] = {'made': False, 'reason': 'makeappx.exe was not found in the Windows Kits'}
    # Written as bytes: sha256sum, elsewhere, reads no carriage return.
    (packages / f'SHA256SUMS-{arch}.txt').write_bytes(''.join(
        f"{sha256(path)}  {path.name}\n" for path in sorted(packages.iterdir())
        if path.suffix in ('.zip', '.msix')).encode('utf-8'))
    write_record('passed')
except Stop as stopped:
    record['stopped_at'] = str(stopped)
    write_record('failed')
    print(f'STOPPED at {stopped}', flush=True)
    sys.exit(1)
except Exception as error:  # what this script did not foresee is said, not lost
    import traceback
    record['stopped_at'] = 'recette.py: ' + ''.join(traceback.format_exception(error))[-1500:]
    write_record('failed')
    raise
print(json.dumps({key: record.get(key) for key in ['status', 'version', 'architecture', 'rust_tests', 'flutter_tests',
                                                   'print_trial', 'launch', 'packages']}, indent=2, ensure_ascii=False))
