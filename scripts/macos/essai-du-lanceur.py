#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Try construire-color.py away from the Mac, with stand-ins for its tools.

  essai-du-lanceur.py [--keep FOLDER]

Nothing of macOS is needed and nothing is installed: Xcode, Flutter, Rust,
cargo, codesign and ditto are small scripts in a temporary folder, and the
project's recipe runs unchanged over a copy of these sources. What is tried
is the launcher itself: which sources it picks, what it refuses and how it
says so, what it hands over, and that a run never removes or changes what an
earlier one left. It says nothing about a real build: only the Mac does.

Exit code 0 when every expectation holds. --keep leaves the folders of the
trial in FOLDER, which must not exist, to look at them afterwards.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
COLOR = HERE.parent.parent
LAUNCHER = HERE / 'construire-color.py'
PINNED_FLUTTER = '9584c6713b324636289d067944a46fd6b49df14b'

BASH = '#!/bin/bash\n'
TOOLS = {
    'codesign': BASH + 'echo "codesign $*" >> "$COLOR_TRIAL_LOG"; exit 0\n',
    'lipo': BASH + 'echo arm64\n',
    'nice': BASH + 'shift 2; exec "$@"\n',
    'open': BASH + 'echo "open $*" >> "$COLOR_TRIAL_LOG"\n',
    'sw_vers': BASH + 'echo 27.0\n',
    'xcode-select': BASH + 'echo /Applications/Xcode.app/Contents/Developer\n',
    'xcodebuild': BASH + ('if [ "${TRIAL_XCODE:-ok}" = bad ]; then '
                          'echo "xcode-select: error: tool xcodebuild requires Xcode"; exit 1; fi\n'
                          'printf "Xcode 27.0\\nBuild version 27A000a\\n"\n'),
    # Copies a bundle, or packs it the way « ditto -c -k » does: links stay links.
    'ditto': '''#!/usr/bin/env python3
import os, shutil, stat, sys, zipfile
with open(os.environ['COLOR_TRIAL_LOG'], 'a') as log:
    log.write('ditto ' + ' '.join(sys.argv[1:]) + '\\n')
arguments = sys.argv[1:]
if arguments[0] != '-c':
    shutil.copytree(arguments[0], arguments[1], symlinks=True)
    sys.exit(0)
source, target = arguments[-2], arguments[-1]
parent = os.path.dirname(source)
with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as package:
    for root, folders, files in os.walk(source):
        for name in sorted(folders + files):
            path = os.path.join(root, name)
            relative = os.path.relpath(path, parent)
            if os.path.islink(path):
                entry = zipfile.ZipInfo(relative)
                entry.external_attr = (stat.S_IFLNK | 0o755) << 16
                package.writestr(entry, os.readlink(path))
                if name in folders:
                    folders.remove(name)
            elif os.path.isdir(path):
                package.write(path, relative + '/')
            else:
                package.write(path, relative)
''',
}
PATH_TOOLS = {
    # « cargo rustc » builds the core, as the recipe asks: from the folder of
    # the core, without the network, with the lock file as it is. Anything
    # else here is « cargo test ».
    'cargo': BASH + ('if [ "$1" = rustc ]; then\n'
                     '  echo "cargo $* [in $(basename "$PWD"), target=$CARGO_TARGET_DIR]" >> "$COLOR_TRIAL_LOG"\n'
                     '  case " $* " in *" --offline "*) ;; *) echo "cargo may reach the network" >&2; exit 64 ;; esac\n'
                     '  case " $* " in *" --frozen "*) ;; *) echo "cargo may rewrite the lock file" >&2; exit 64 ;; esac\n'
                     '  for needed in Cargo.toml Cargo.lock .cargo/config.toml vendor/usvg/Cargo.toml; do\n'
                     '    [ -f "$needed" ] || { echo "the folder of the core lacks $needed" >&2; exit 64; }\n'
                     '  done\n'
                     '  if [ "${TRIAL_CORE:-pass}" = fail ]; then\n'
                     '    echo "error: could not compile edupaint_core (lib) due to 1 previous error"; exit 101\n'
                     '  fi\n'
                     '  mkdir -p "$CARGO_TARGET_DIR/aarch64-apple-darwin/release"\n'
                     '  echo dylib > "$CARGO_TARGET_DIR/aarch64-apple-darwin/release/libedupaint_core.dylib"\n'
                     '  exit 0\nfi\n'
                     'if [ "${TRIAL_CARGO:-pass}" = fail ]; then\n'
                     "  printf 'running 113 tests\\ntest result: FAILED. 111 passed; 2 failed; 0 ignored; "
                     "0 measured; 0 filtered out; finished in 1.0s\\n'; exit 101\nfi\n"
                     "printf 'running 113 tests\\ntest result: ok. 113 passed; 0 failed; 0 ignored; "
                     "0 measured; 0 filtered out; finished in 1.0s\\n'\n"),
    'git': BASH + ('case "$*" in\n'
                   '  *"rev-parse HEAD"*) echo ' + PINNED_FLUTTER + ' ;;\n'
                   '  *"status --porcelain"*) : ;;\n'
                   '  *) echo "unexpected git call: $*" >&2; exit 64 ;;\n'
                   'esac\n'),
    # The Rust of Homebrew, or with TRIAL_RUSTC=rustup one that is not. The
    # recipe asks it its version only: cargo compiles.
    'rustc': BASH + ('if [ "$1" = "--version" ]; then\n'
                     '  if [ "${TRIAL_RUSTC:-homebrew}" = rustup ]; then echo "rustc 1.99.0 (b940084d7 2026-09-28)"\n'
                     '  else echo "rustc 1.99.0 (b940084d7 2026-09-28) (Homebrew)"; fi\n'
                     '  exit 0\nfi\n'
                     'echo "unexpected rustc call: $*" >&2; exit 64\n'),
}
# Homebrew, asked for its formula « rust » only, and never to change anything.
PATH_TOOLS['brew'] = BASH + r'''echo "brew $* [auto-update=${HOMEBREW_NO_AUTO_UPDATE:-on}]" >> "$COLOR_TRIAL_LOG"
[ "$*" = "info --json=v2 rust" ] || { echo "unexpected brew call: $*" >&2; exit 64; }
case "${TRIAL_BREW:-current}" in
  current) echo '{"formulae":[{"name":"rust","versions":{"stable":"1.99.0"},"installed":[{"version":"1.99.0"}],"outdated":false}],"casks":[]}' ;;
  newer) echo '{"formulae":[{"name":"rust","versions":{"stable":"1.100.0"},"installed":[{"version":"1.99.0"}],"outdated":true}],"casks":[]}' ;;
  broken) echo "Error: something about taps" >&2; exit 1 ;;
esac
'''
FLUTTER = BASH + r'''case "$1 $2" in
  "pub get") echo "Got dependencies!"; exit 0 ;;
  "analyze "*) echo "No issues found!"; exit 0 ;;
  "test "*)
    printf '00:01 +1: /stage/test/a_test.dart: first\n00:02 +2: /stage/test/a_test.dart: second\n'
    if [ "${TRIAL_TESTS:-pass}" = fail ]; then
      printf '00:03 +2 -1: /stage/test/gallery_storage_test.dart: a card is named after the saved path [E]\n'
      printf '  Expected: x\n00:04 +5 ~1 -2: /stage/test/native_exit_test.dart: quitting waits [E]\n'
      printf '00:05 +5 ~1 -2: Some tests failed.\n'
      exit 1
    fi
    printf '00:05 +700 ~6: All tests passed!\n'; exit 0 ;;
  "build macos")
    [ "${TRIAL_BUILD:-pass}" = fail ] && { echo "error: xcodebuild failed: something about signing"; exit 1; }
    version=$(sed -n 's/^version: *//p' pubspec.yaml)
    app="$PWD/build/macos/Build/Products/Release/Color.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks/App.framework/Versions/A"
    echo binary > "$app/Contents/MacOS/Color"; echo aot > "$app/Contents/Frameworks/App.framework/Versions/A/App"
    ln -s Versions/A/App "$app/Contents/Frameworks/App.framework/App"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Color</string>
<key>CFBundleExecutable</key><string>Color</string>
<key>CFBundleShortVersionString</key><string>${version%+*}</string>
<key>CFBundleVersion</key><string>${version#*+}</string>
<key>CFBundleIdentifier</key><string>org.edupaint.flutterstudy</string>
<key>LSMinimumSystemVersion</key><string>26.6</string>
</dict></plist>
PLIST
    echo "Built build/macos/Build/Products/Release/Color.app"; exit 0 ;;
esac
echo "unexpected flutter call: $*" >&2; exit 64
'''
DART = BASH + 'echo "self-test ok: $*"; exit 0\n'


def write_tool(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o755)


def make_local(folder, disk_missing=False, engine_stamp=True):
    """What the earlier builds left on the Mac: the SDK and the dependency cache."""
    sdk = folder / 'flutter-toolchain' / 'flutter'
    write_tool(sdk / 'bin' / 'flutter', FLUTTER)
    write_tool(sdk / 'bin' / 'dart', DART)
    cache = sdk / 'bin' / 'cache'
    cache.mkdir(parents=True)
    if engine_stamp:
        (cache / 'engine.stamp').write_text('06a2e2a110089dff50fe635cffd2a61e1b24fbcd\n')
    if disk_missing:
        (cache / 'dart-sdk').symlink_to('/Volumes/Disque Absent/Color/build/flutter-toolchain/dart-sdk')
    else:
        write_tool(cache / 'dart-sdk' / 'bin' / 'dart', DART)
    (folder / 'macos-clean-pub-cache').mkdir(parents=True)
    return folder


def make_sources(travail, version, pubspec_version=None, complete=True):
    """A folder of sources of that version: these very sources, under that number."""
    root = travail / ('Color-' + version + '-sources') / 'Color'
    root.mkdir(parents=True)
    if not complete:
        return root
    ignore = shutil.ignore_patterns('build', '.dart_tool', 'target', 'ephemeral', '__pycache__',
                                    '.flutter-plugins', '.flutter-plugins-dependencies')
    (root / 'scripts').mkdir()
    for name in ('build-flutter-study.py', 'check-vendored-sources.py', 'rust-reference.json'):
        shutil.copy2(str(COLOR / 'scripts' / name), str(root / 'scripts'))
    for part in ('prototypes/flutter-rust', 'prototypes/native-swift-rust/core'):
        shutil.copytree(str(COLOR / part), str(root / part), ignore=ignore)
    pubspec = root / 'prototypes' / 'flutter-rust' / 'pubspec.yaml'
    lines = pubspec.read_text(encoding='utf-8').splitlines()
    lines = ['version: ' + (pubspec_version or version) if line.startswith('version:') else line
             for line in lines]
    pubspec.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return root


def snapshot(folder):
    """Every file under the folder with its digest, links with their target."""
    found = {}
    for root, folders, files in os.walk(str(folder)):
        for name in folders + files:
            path = Path(root) / name
            relative = path.relative_to(folder).as_posix()
            if path.is_symlink():
                found[relative] = 'link:' + os.readlink(str(path))
            elif path.is_file():
                found[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    return found


class Trial:
    def __init__(self, root):
        self.root = root
        self.failures = []
        self.count = 0
        self.tools = root / 'tools'
        self.path = root / 'path'
        self.log = root / 'tools.log'
        for name, text in TOOLS.items():
            write_tool(self.tools / name, text)
        for name, text in PATH_TOOLS.items():
            write_tool(self.path / name, text)
        (root / 'home').mkdir()

    def expect(self, condition, label):
        self.count += 1
        if not condition:
            self.failures.append(label)
        print(('  ok      ' if condition else '  ÉCHEC   ') + label)

    def run(self, travail, local, *arguments, **settings):
        """One run of the launcher: (exit code, etat.json, what it printed, its journal folder)."""
        environment = {
            'PATH': str(self.path) + os.pathsep + '/usr/bin:/bin',
            'HOME': str(self.root / 'home'),
            'COLOR_TRIAL_TOOLS': str(self.tools),
            'COLOR_TRIAL_LOG': str(self.log),
            'COLOR_LOCAL_BUILD': str(local),
            'LC_ALL': 'C.UTF-8',
            'PYTHONIOENCODING': 'utf-8',
        }
        environment.update(settings)
        journals = travail / 'construction-mac' / 'journal'
        before = set(journals.iterdir()) if journals.is_dir() else set()
        result = subprocess.run([sys.executable, str(LAUNCHER), str(travail)] + list(arguments),
                                env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                universal_newlines=True, encoding='utf-8')
        new = sorted(set(journals.iterdir()) - before) if journals.is_dir() else []
        state = json.loads((new[-1] / 'etat.json').read_text(encoding='utf-8')) if new else {}
        return result.returncode, state, result.stdout, (new[-1] if new else None)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--keep')
    arguments = parser.parse_args()
    if arguments.keep:
        root = Path(arguments.keep).resolve()
        root.mkdir(parents=True)
    else:
        root = Path(tempfile.mkdtemp(prefix='color-essai-lanceur-'))
    trial = Trial(root)
    expect = trial.expect
    try:
        local = make_local(root / 'local')
        travail = root / 'travail'
        travail.mkdir()
        (travail / 'un dessin à moi.edupaint').write_text('à ne pas toucher\n', encoding='utf-8')

        print('1. Aucune source')
        code, state, said, _ = trial.run(travail, local)
        expect(code == 1 and state.get('status') == 'blocked', 'refus sans sources, état « blocked »')
        expect('Aucun dossier de sources' in said, 'le refus dit qu’il n’y a pas de sources')

        print('2. Une version, tout va bien')
        make_sources(travail, '0.7.0+28')
        code, state, said, journal = trial.run(travail, local)
        first = travail / 'Color 0.7.0+28 pour Mac'
        expect(code == 0 and state.get('status') == 'passed', 'construction réussie, état « passed »')
        expect(state.get('version') == '0.7.0+28', 'la version vient du dossier des sources')
        expect((first / 'Color.app' / 'Contents' / 'Info.plist').is_file(), 'application remise à côté des sources')
        expect((first / 'Color.app' / 'Contents' / 'Frameworks' / 'App.framework' / 'App').is_symlink(),
               'les liens du paquet restent des liens dans la copie')
        archive = state.get('archive') or {}
        expect((first / 'Color-0.7.0+28-mac.zip').is_file() and archive.get('links', 0) >= 1,
               'ZIP fait et relu : il garde au moins un lien')
        expect(archive.get('sha256') == hashlib.sha256(
            (first / 'Color-0.7.0+28-mac.zip').read_bytes()).hexdigest(), 'l’empreinte du ZIP est celle du fichier')
        notice = (first / 'LISEZMOI.txt').read_text(encoding='utf-8')
        expect('Double-clique sur Color.app' in notice and '700 réussis' in notice and '113 réussis' in notice,
               'la notice donne les tests de l’interface et du cœur')
        expect(state.get('flutter_tests', {}).get('passed') == 700
               and state.get('core_tests', {}).get('status') == 'passed', 'les tests sont comptés dans l’état')
        expect(state.get('facts', {}).get('launcher_sha256') == hashlib.sha256(LAUNCHER.read_bytes()).hexdigest(),
               'le journal garde l’empreinte du lanceur')
        expect((journal / 'recette' / 'result.json').is_file() and (journal / 'journal.txt').is_file(),
               'journal et rapport de la recette écrits')
        expect((local / 'macos-color-0.7.0-28-work').is_dir() and (local / 'macos-color-0.7.0-28-release').is_dir(),
               'dossiers de travail propres à la version, sans « + »')
        calls = trial.log.read_text()
        expect(calls.count('open -R') == 1 and str(first / 'Color.app') in calls,
               'le Finder montre l’application, une fois')
        expect('codesign --verify --deep --strict ' + str(first / 'Color.app') in calls,
               'la signature de la copie remise est vérifiée')

        builds = [line for line in calls.splitlines() if line.startswith('cargo rustc ')]
        expect(len(builds) == 1 and '--offline' in builds[0] and '--frozen' in builds[0]
               and '--target aarch64-apple-darwin' in builds[0] and '[in core,' in builds[0],
               'le cœur est compilé par cargo, depuis son dossier, sans réseau')
        expect('target=' + str(local / 'macos-color-cargo-target') + ']' in builds[0]
               and (local / 'macos-color-cargo-target').is_dir()
               and not (travail / 'Color-0.7.0+28-sources' / 'Color' / 'prototypes' / 'native-swift-rust'
                        / 'core' / 'target').exists(),
               'cargo travaille dans le dossier local des constructions, pas dans les sources')
        recipe = json.loads((journal / 'recette' / 'result.json').read_text(encoding='utf-8'))
        expect(recipe.get('core_vendored_sources', {}).get('crates', 0) >= 10
               and 'Cargo.lock' in recipe.get('core_source_files_sha256', {})
               and 'art/interface/options.svg' in recipe.get('core_source_files_sha256', {}),
               'le rapport garde l’empreinte du cœur, de ses dessins et de ses bibliothèques')

        said_checks = said.split('2. Recette du projet')[0]
        expect('remarque' not in said_checks, 'aucune remarque quand Rust est celui que Homebrew propose')
        expect('1.98.1' not in said and 'qualifié' not in said_checks,
               'plus aucune mention d’une version de Rust figée')
        expect(state.get('facts', {}).get('homebrew_rust') == {'stable': '1.99.0', 'installed': ['1.99.0'],
                                                             'outdated': False},
               'ce que Homebrew sait de Rust est gardé dans l’état')
        expect(state.get('facts', {}).get('rust_reference') == json.loads(
            (COLOR / 'scripts' / 'rust-reference.json').read_text(encoding='utf-8'))['rust_version'],
               'la référence des autres plateformes est lue dans les sources')
        expect('Rust 1.99.0 est celui que Homebrew propose' in (journal / 'journal.txt').read_text(encoding='utf-8'),
               'le journal dit que Rust est celui de Homebrew')
        calls = trial.log.read_text()
        expect('brew info --json=v2 rust [auto-update=1]' in calls
               and all(line.startswith('brew info ') for line in calls.splitlines() if line.startswith('brew ')),
               'Homebrew est seulement interrogé, sans mise à jour')

        print('3. La même version une seconde fois')
        before = snapshot(travail)
        code, state, said, _ = trial.run(travail, local)
        second = travail / 'Color 0.7.0+28 pour Mac (2)'
        after = snapshot(travail)
        expect(code == 0 and second.is_dir(), 'la seconde remise a son propre dossier, « (2) »')
        expect(all(after.get(path) == digest for path, digest in before.items()),
               'rien de ce qui existait n’a été retiré ni changé')

        print('4. Une version plus récente à côté')
        make_sources(travail, '0.7.0+29')
        before = snapshot(travail)
        code, state, said, _ = trial.run(travail, local)
        expect(code == 0 and state.get('version') == '0.7.0+29'
               and (travail / 'Color 0.7.0+29 pour Mac' / 'Color.app').is_dir(),
               'la plus récente est construite')
        expect(state.get('application', {}).get('build') == '29', 'l’application porte son numéro')
        expect((local / 'macos-color-0.7.0-29-work').is_dir(), 'elle a ses propres dossiers de travail')
        after = snapshot(travail)
        expect(all(after.get(path) == digest for path, digest in before.items()),
               'les remises précédentes sont intactes')
        code, state, said, _ = trial.run(travail, local, 'Color-0.7.0+28-sources')
        expect(code == 0 and state.get('version') == '0.7.0+28'
               and (travail / 'Color 0.7.0+28 pour Mac (3)').is_dir(), 'une version nommée est construite à la demande')
        code, state, said, _ = trial.run(travail, local, 'Color-9.9.9+99-sources')
        expect(code == 1 and state.get('status') == 'blocked' and 'introuvables' in said,
               'un nom de sources inconnu est refusé')

        print('5. Des tests de l’interface échouent')
        code, state, said, _ = trial.run(travail, local, TRIAL_TESTS='fail')
        unqualified = travail / 'Color 0.7.0+29 pour Mac - NON QUALIFIEE'
        expect(code == 1 and state.get('status') == 'built_not_qualified', 'état « built_not_qualified »')
        expect((unqualified / 'Color.app').is_dir(), 'une application est tout de même remise, dans un dossier à part')
        notice = (unqualified / 'LISEZMOI.txt').read_text(encoding='utf-8') if unqualified.is_dir() else ''
        expect('NON QUALIFIÉE' in notice and 'quitting waits' in notice, 'sa notice nomme les tests en échec')
        expect(state.get('flutter_tests', {}).get('failed') == 2, 'les échecs sont comptés')

        print('6. La compilation échoue')
        before = set(path.name for path in travail.iterdir())
        code, state, said, _ = trial.run(travail, local, TRIAL_BUILD='fail')
        expect(code == 1 and state.get('status') == 'failed', 'état « failed »')
        expect(set(path.name for path in travail.iterdir()) == before, 'rien n’est remis')
        expect('macos-release-build' in said and 'something about signing' in said,
               'l’étape et la fin de son journal sont affichées')

        print('6 bis. Le cœur ne se compile pas')
        before = set(path.name for path in travail.iterdir())
        code, state, said, _ = trial.run(travail, local, TRIAL_CORE='fail')
        expect(code == 1 and state.get('status') == 'failed' and set(path.name for path in travail.iterdir()) == before,
               'état « failed », rien n’est remis')
        expect('rust-dylib' in said and 'could not compile edupaint_core' in said,
               'l’étape du cœur et la fin de son journal sont affichées')

        print('6 ter. Une copie des sources a perdu des fichiers cachés')
        damaged = root / 'travail-3'
        damaged.mkdir()
        lost = make_sources(damaged, '0.7.0+29') / 'prototypes' / 'native-swift-rust' / 'core' / 'vendor'
        for hidden in sorted(lost.glob('*/.cargo-checksum.json'))[:2]:
            hidden.rename(hidden.with_name('liste-retiree.json'))
        code, state, said, _ = trial.run(damaged, local)
        expect(code == 1 and state.get('status') == 'failed' and 'rust-vendored-sources' in said
               and 'ne sont pas complètes' in said and '.cargo-checksum.json' in said,
               'la recette s’arrête avant cargo et dit ce qui manque')
        expect(not any(path.name.startswith('Color 0.7.0+29 pour Mac') for path in damaged.iterdir()),
               'rien n’est remis')

        print('7. Des tests du cœur échouent')
        code, state, said, _ = trial.run(travail, local, TRIAL_CARGO='fail')
        expect(code == 1 and state.get('status') == 'built_core_tests_failed', 'état « built_core_tests_failed »')
        expect('ATTENTION : les tests du cœur Rust' in
               (travail / 'Color 0.7.0+29 pour Mac (2)' / 'LISEZMOI.txt').read_text(encoding='utf-8'),
               'la notice de cette remise le dit')

        print('8. Ce qui manque est dit avant de commencer')
        before = set(path.name for path in travail.iterdir())
        code, state, said, _ = trial.run(travail, local, TRIAL_XCODE='bad')
        expect(code == 1 and state.get('status') == 'blocked' and 'Xcode ne répond pas' in said, 'Xcode absent')
        code, state, said, _ = trial.run(travail, local, COLOR_TRIAL_FREE_BYTES=str(3 * 1024 ** 3))
        expect(code == 1 and state.get('status') == 'blocked' and 'Il reste 3.0 Go libres' in said,
               'moins de 4 Go libres')
        code, state, said, _ = trial.run(travail, make_local(root / 'local-sans-disque', disk_missing=True))
        expect(code == 1 and state.get('status') == 'blocked' and 'Le disque « Disque Absent »' in said,
               'disque externe du SDK non branché, nommé')
        code, state, said, _ = trial.run(travail, root / 'nulle-part')
        expect(code == 1 and state.get('status') == 'blocked' and 'Le SDK Flutter est introuvable' in said,
               'SDK introuvable')
        expect(set(path.name for path in travail.iterdir()) == before, 'aucun de ces refus ne remet quoi que ce soit')
        # A recipe that stops outside its steps: its last words are shown.
        code, state, said, _ = trial.run(travail, make_local(root / 'local-sans-tampon', engine_stamp=False))
        expect(code == 1 and state.get('status') == 'failed' and 'engine.stamp' in said,
               'une recette qui s’arrête hors de ses étapes dit pourquoi')
        expect(set(path.name for path in travail.iterdir()) == before, 'et rien n’est remis')

        print('8 bis. Rust suit Homebrew')
        before = set(path.name for path in travail.iterdir())
        code, state, said, _ = trial.run(travail, local, TRIAL_BREW='newer')
        expect(code == 0 and state.get('status') == 'passed', 'un Rust plus récent chez Homebrew n’arrête rien')
        expect('Homebrew propose Rust 1.100.0 ; ce Mac a encore 1.99.0' in said and 'brew upgrade rust' in said,
               'la remarque nomme les deux versions et la commande')
        code, state, said, journal = trial.run(travail, local, TRIAL_BREW='broken')
        expect(code == 0 and 'remarque' not in said.split('2. Recette du projet')[0]
               and state.get('facts', {}).get('homebrew_rust') is None,
               'un Homebrew muet n’arrête rien et ne fait dire aucune remarque')
        expect('Homebrew n’a pas répondu' in (journal / 'journal.txt').read_text(encoding='utf-8'),
               'le journal garde que Homebrew n’a pas répondu')
        code, state, said, _ = trial.run(travail, local, TRIAL_RUSTC='rustup')
        expect(code == 0 and 'n’est pas celui de Homebrew' in said and 'brew install rust' in said,
               'un Rust qui ne vient pas de Homebrew est signalé, sans arrêter')
        expect(len(set(path.name for path in travail.iterdir()) - before) == 3,
               'chacun de ces trois passages a remis son application')

        print('9. Des sources abîmées')
        make_sources(travail, '0.8.0+30', complete=False)
        code, state, said, _ = trial.run(travail, local)
        expect(code == 1 and state.get('status') == 'blocked' and 'incomplètes' in said,
               'un dossier plus récent mais incomplet est signalé, pas contourné')
        other = root / 'travail-2'
        other.mkdir()
        make_sources(other, '0.7.0+31', pubspec_version='0.7.0+29')
        code, state, said, _ = trial.run(other, local)
        expect(code == 1 and state.get('status') == 'blocked' and 'contient la version 0.7.0+29' in said,
               'un dossier dont le nom ne dit pas la version est refusé')

        expect((travail / 'un dessin à moi.edupaint').read_text(encoding='utf-8') == 'à ne pas toucher\n',
               'le fichier déposé dans le dossier de travail est resté tel quel')
    finally:
        if not arguments.keep:
            shutil.rmtree(str(root), ignore_errors=True)
    print()
    if trial.failures:
        print('%d attente(s) sur %d non tenue(s) :' % (len(trial.failures), trial.count))
        for label in trial.failures:
            print('  - ' + label)
        return 1
    print('%d attentes tenues. Essai hors du Mac : le lanceur seul, pas une construction.' % trial.count)
    return 0


if __name__ == '__main__':
    sys.exit(main())
