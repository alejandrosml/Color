#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Try envoyer-app-store.py away from the Mac, with stand-ins for Xcode,
codesign, pkgutil and ditto (the script's run and output are replaced):

  - the Mac: the resource bundle of a Swift package loses the signature of the
    archive (by codesign, or by removing its folder when codesign leaves it);
    a bundle that holds code stops everything; Xcode without a device, then
    this Mac registered; another failure not retried;
  - before anything is sent: an export kept on the Mac, whose signatures are
    all read; one signed by another certificate, an application signed by a
    certificate of development, or a program without a signature stop the
    sending, and the version is not remembered as sent;
  - iOS, signed by hand: the same verification, and the export options;
  - since 1.0.1: the core of the Mac built alone as a cdylib (link-time
    optimization), its dSYM put in the archive and the library stripped
    before it is signed; without a dSYM, with one of another build (another
    UUID), or when strip fails, the library stays whole and Color is still
    sent; the symbols of the Dart code kept apart, for the Mac and for iOS.

  essai-de-l-envoi.py [FOLDER]

FOLDER, which must not exist, keeps the trial to look at it afterwards;
without it, a temporary folder is used and removed. Exit code 0 when every
expectation holds. It says nothing about a real sending: only the Mac does.
"""
import atexit
import importlib.util
import os
import plistlib
import shutil
import sys
import tempfile
from pathlib import Path

scripts = Path(__file__).resolve().parent
if len(sys.argv) > 1:
    trial = Path(sys.argv[1]).resolve()
    trial.mkdir(parents=True)
else:
    trial = Path(tempfile.mkdtemp(prefix='color-essai-envoi-'))
    atexit.register(shutil.rmtree, trial, True)
os.environ['COLOR_LOCAL_BUILD'] = str(trial / 'local')
sys.path.insert(0, str(scripts))
spec = importlib.util.spec_from_file_location('envoyer', scripts / 'envoyer-app-store.py')
envoyer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(envoyer)

VERSION = '1.0.1+40'
travail = trial / 'travail'
sources = travail / ('Color-%s-sources' % VERSION)
sources.mkdir(parents=True)
MACH_O = bytes.fromhex('cffaedfe') + b'\0' * 60
BUNDLE = 'file_selector_macos_file_selector_macos.bundle'
journals = []
calls = []
environments = []
behaviour = {}
failures = []


def expect(condition, what):
    print(('ok   ' if condition else 'FAIL ') + what)
    if not condition:
        failures.append(what)


def make_journal():
    envoyer.Journal.lock = None
    journals.append(envoyer.Journal(travail, 'app-store-essai-%d' % len(journals)))
    return journals[-1]


def mac_app(app, bundle_with_code=False):
    """What Xcode's archive of the Mac holds."""
    contents = app / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    (contents / 'MacOS' / 'Color').write_bytes(MACH_O)
    (contents / '_CodeSignature').mkdir()
    (contents / '_CodeSignature' / 'CodeResources').write_text('seal')
    framework = contents / 'Frameworks' / 'App.framework'
    (framework / 'Versions' / 'A' / '_CodeSignature').mkdir(parents=True)
    (framework / 'Versions' / 'A' / 'App').write_bytes(MACH_O)
    os.symlink('A', framework / 'Versions' / 'Current')
    os.symlink('Versions/Current/App', framework / 'App')
    bundle = contents / 'Resources' / BUNDLE / 'Contents'
    (bundle / '_CodeSignature').mkdir(parents=True)
    (bundle / '_CodeSignature' / 'CodeSignature').write_bytes(b'cms')
    (bundle / 'Resources').mkdir()
    (bundle / 'Resources' / 'PrivacyInfo.xcprivacy').write_text('<plist/>')
    info = {'CFBundlePackageType': 'BNDL', 'CFBundleIdentifier': 'file-selector.resources'}
    if bundle_with_code:
        info['CFBundleExecutable'] = 'Helper'
    (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))


def ios_app(app):
    app.mkdir(parents=True)
    (app / 'Color').write_bytes(MACH_O)
    (app / '_CodeSignature').mkdir()
    framework = app / 'Frameworks' / 'Flutter.framework'
    (framework / '_CodeSignature').mkdir(parents=True)
    (framework / 'Flutter').write_bytes(MACH_O)


def fake_run(journal, name, command, cwd=None, env=None, timeout=None, interactive=False,
             check=True):
    command = [str(part) for part in command]
    calls.append((name, command))
    environments.append((name, env))
    answer = behaviour.get(name)
    if callable(answer):
        answer = answer(command)
    code, text = answer or (0, '')
    with (journal.folder / (name + '.log')).open('a', encoding='utf-8') as log:
        log.write('$ ' + ' '.join(command) + '\n' + text + '\n')
    tool = Path(command[0]).name
    if code == 0 and 'archive' in command and '-archivePath' in command:
        archive = Path(command[command.index('-archivePath') + 1])
        if '/app-store-macos/' in str(archive):
            mac_app(archive / 'Products' / 'Applications' / 'Color.app',
                    behaviour.get('bundle_with_code', False))
        else:
            ios_app(archive / 'Products' / 'Applications' / 'Color.app')
    elif code == 0 and '-exportArchive' in command:
        exported = Path(command[command.index('-exportPath') + 1])
        archive = Path(command[command.index('-archivePath') + 1])
        exported.mkdir(parents=True)
        kind = 'pkg' if '/app-store-macos/' in str(archive) else 'ipa'
        (exported / ('Color.' + kind)).write_text(str(archive))
    elif tool == 'pkgutil':
        archive = Path(Path(command[2]).read_text())
        shutil.copytree(archive / 'Products' / 'Applications' / 'Color.app',
                        Path(command[3]) / 'Color.pkg' / 'Payload' / 'Color.app', symlinks=True)
    elif tool == 'ditto':
        archive = Path(Path(command[3]).read_text())
        shutil.copytree(archive / 'Products' / 'Applications' / 'Color.app',
                        Path(command[4]) / 'Payload' / 'Color.app', symlinks=True)
    elif tool == 'xcrun' and command[1] == 'strip':
        if behaviour.get('strip_fails'):
            code = 1
        else:
            target = Path(command[-1])
            target.write_bytes(target.read_bytes() + b'stripped')
    elif tool == 'codesign' and '--remove-signature' in command:
        if behaviour.get('codesign_removes', True):
            shutil.rmtree(Path(command[-1]) / 'Contents' / '_CodeSignature')
        else:
            code = 1
    if check and code != 0:
        raise envoyer.Failure('« %s » a échoué (code %d)' % (name, code))
    return code


def fake_output(command, env=None, timeout=120):
    command = [str(part) for part in command]
    if command[0].endswith('codesign') and any(part.startswith('--extract-certificates=')
                                                 for part in command):
        item = command[-1]
        prefix = next(part for part in command if part.startswith('--extract-certificates='))
        prefix = prefix.split('=', 1)[1]
        if behaviour.get('unsigned') and item.endswith(behaviour['unsigned']):
            return 1, '%s: code object is not signed at all\n' % item
        if behaviour.get('development') and item.endswith(behaviour['development']):
            Path(prefix + '0').write_bytes(b'DEV')
            Path(prefix + '1').write_bytes(b'WWDR')
            return 0, 'Executable=%s\nAuthority=Apple Development: Essai (XYZ)\n' % item
        Path(prefix + '0').write_bytes(b'DIST')
        Path(prefix + '1').write_bytes(b'WWDR')
        return 0, 'Executable=%s\nAuthority=Apple Distribution: Essai (ABCDE12345)\n' % item
    if command[0].endswith('codesign'):
        return 0, 'Authority=Apple Development: Essai (XYZ)\n'
    if command[0].endswith('xcrun') and command[1] == 'dwarfdump':
        stale = behaviour.get('stale_dsym') and command[-1].endswith('.dSYM')
        uuid = '11111111-2222-3333-4444-555555555555' if stale else (
            'A1B2C3D4-0000-4000-8000-123456789ABC')
        return 0, 'UUID: %s (arm64) %s\n' % (uuid, command[-1])
    if 'find-identity' in command:
        return 0, behaviour.get('identities', '')
    if command[0].endswith('xcrun') and command[1] == 'nm':
        exported = [name for name in ('_ep_a', '_ep_b', '_ep_c', '_main_helper')
                    if name != behaviour.get('missing_export')]
        return 0, ''.join('0000000100001000 T %s\n' % name for name in exported)
    return 0, ''


work = trial / 'work'
(work / 'macos').mkdir(parents=True)
(work / 'ios' / 'Runner').mkdir(parents=True)
envoyer.run = fake_run
envoyer.output = fake_output
envoyer.flutter = lambda journal, name, arguments, work_, env, timeout=None: fake_run(
    journal, name, ['flutter'] + list(arguments))
envoyer.stage_app = lambda journal, sources_, target: work
envoyer.flutter_environment = lambda: {}
envoyer.core_folder = lambda sources_: trial
envoyer.ensure_rust = lambda journal, targets: (['cargo'], {})
dylib = envoyer.CARGO_TARGET / 'mac' / 'aarch64-apple-darwin' / 'release' / 'libedupaint_core.dylib'
dylib.parent.mkdir(parents=True)
dylib.write_bytes(MACH_O)
ios_lib = envoyer.CARGO_TARGET / 'aarch64-apple-ios' / 'release' / 'libedupaint_core.a'
ios_lib.parent.mkdir(parents=True)
ios_lib.write_bytes(b'lib')
archived_bundle = (envoyer.MOBILES / 'app-store-macos' / 'Color.xcarchive' / 'Products'
                   / 'Applications' / 'Color.app' / 'Contents' / 'Resources' / BUNDLE)
archived_core = archived_bundle.parent.parent / 'Frameworks' / 'libedupaint_core.dylib'
archived_dsym = (envoyer.MOBILES / 'app-store-macos' / 'Color.xcarchive' / 'dSYMs'
                 / 'libedupaint_core.dylib.dSYM')
# What rustc leaves beside the library with split debug information « packed ».
built_dsym = dylib.with_name(dylib.name + '.dSYM')
(built_dsym / 'Contents' / 'Resources' / 'DWARF').mkdir(parents=True)
(built_dsym / 'Contents' / 'Resources' / 'DWARF' / dylib.name).write_bytes(MACH_O)


def names():
    return [name for name, command in calls]


def case(title, settings, platform='macos'):
    calls.clear()
    environments.clear()
    behaviour.clear()
    behaviour.update(settings)
    journal = make_journal()
    print('\n# ' + title)
    try:
        (envoyer.mac if platform == 'macos' else envoyer.ios)(journal, sources, VERSION,
                                                            'ABCDE12345')
        return None
    except envoyer.Failure as failure:
        print('  Failure: ' + str(failure)[:200])
        return failure


def reset_sent():
    if envoyer.SENT_FILE.exists():
        envoyer.SENT_FILE.unlink()


# A. The Mac, everything right: the bundle unsigned, then checked, then sent.
reset_sent()
failure = case('Mac, bundle unsigned by codesign', {})
expect(failure is None, 'A: the Mac is sent')
expect(not (archived_bundle / 'Contents' / '_CodeSignature').exists()
       and (archived_bundle / 'Contents' / 'Resources' / 'PrivacyInfo.xcprivacy').exists(),
       'A: the bundle keeps its resources, not its signature')
removal = [i for i, (n, c) in enumerate(calls) if '--remove-signature' in c]
resign = [i for i, (n, c) in enumerate(calls) if n == 'signature' and '--preserve-metadata=entitlements,requirements,flags,runtime' in c]
expect(removal and resign and removal[0] < resign[0],
       'A: the signature is removed before Color is sealed again')
order = names()
expect('verification-macos' in order and 'envoi-macos' in order
       and order.index('verification-macos') < order.index('envoi-macos'),
       'A: verification export before the sending')
folder = envoyer.MOBILES / 'app-store-macos'
check = plistlib.loads((folder / 'ExportOptions-verification.plist').read_bytes())
sent = plistlib.loads((folder / 'ExportOptions.plist').read_bytes())
expect(check['destination'] == 'export' and sent['destination'] == 'upload'
       and check['signingStyle'] == sent['signingStyle'] == 'automatic',
       'A: export options, kept here then sent, both automatic for the Mac')
expect(any(n == 'verification-macos' and Path(c[0]).name == 'pkgutil' for n, c in calls),
       'A: the package is opened with pkgutil')
text = (journals[-1].folder / 'journal.txt').read_text(encoding='utf-8') \
    if (journals[-1].folder / 'journal.txt').exists() else ''
expect('Signatures relues : 5 éléments' in text,
       'A: five signed items read (application, its program, a framework and its program, the core)')
expect(envoyer.sent_versions().get('macos') == VERSION, 'A: the Mac version is remembered')
core = [(c, e) for (n, c), (_, e) in zip(calls, environments) if n == 'coeur-mac']
expect(len(core) == 1 and '--crate-type' in core[0][0]
       and core[0][0][core[0][0].index('--crate-type') + 1] == 'cdylib'
       and core[0][0].index('--crate-type') < core[0][0].index('--')
       and core[0][1].get('CARGO_PROFILE_RELEASE_DEBUG') == 'line-tables-only'
       and core[0][1].get('CARGO_PROFILE_RELEASE_SPLIT_DEBUGINFO') == 'packed',
       'A: the core built alone as a cdylib, with line tables and its dSYM')
build = [c for n, c in calls if n == 'flutter-build-macos']
option = [part for part in build[0] if part.startswith('--split-debug-info=')] if build else []
expect(len(option) == 1 and Path(option[0].split('=', 1)[1]).is_dir()
       and str(journals[-1].folder) in option[0],
       'A: the symbols of the Dart code kept apart, in the journal')
expect((archived_dsym / 'Contents' / 'Resources' / 'DWARF' / 'libedupaint_core.dylib').exists(),
       'A: the dSYM of the core is in the archive')
strip = [i for i, (n, c) in enumerate(calls) if n == 'symboles-coeur' and 'strip' in c]
first_signature = next(i for i, (n, c) in enumerate(calls) if n == 'signature')
expect(strip and strip[0] < first_signature and calls[strip[0]][1][-3:-1] == ['-S', '-x']
       and archived_core.read_bytes().endswith(b'stripped'),
       'A: the core stripped of its local symbols before it is signed')

# B. codesign leaves the signature: its folder is removed.
reset_sent()
failure = case('Mac, codesign leaves the signature', {'codesign_removes': False})
expect(failure is None and not (archived_bundle / 'Contents' / '_CodeSignature').exists(),
       'B: the folder of the signature is removed, the Mac is sent')

# C. A library signed by another certificate: nothing is sent.
reset_sent()
failure = case('Mac, the core signed for development', {'development': 'libedupaint_core.dylib'})
expect(failure is not None and 'libedupaint_core.dylib' in str(failure)
       and 'envoi-macos' not in names(), 'C: refused before sending, the library named')
expect(envoyer.sent_versions().get('macos') != VERSION, 'C: the version is not remembered')

# D. A program without a signature: nothing is sent.
reset_sent()
failure = case('Mac, a program without a signature', {'unsigned': 'Versions/A/App'})
expect(failure is not None and 'sans signature' in str(failure)
       and 'envoi-macos' not in names(), 'D: refused before sending')

# E. Color itself signed for development: nothing is sent.
reset_sent()
failure = case('Mac, Color signed for development', {'development': 'Payload/Color.app'})
expect(failure is not None and 'certificat de distribution' in str(failure)
       and 'envoi-macos' not in names(), 'E: refused before sending')

# F. A bundle with code in the resources: stops before any export.
reset_sent()
failure = case('Mac, a bundle that holds code', {'bundle_with_code': True})
expect(failure is not None and BUNDLE in str(failure)
       and 'verification-macos' not in names() and 'envoi-macos' not in names(),
       'F: stopped before any export')

# G. No device, then this Mac registered.
attempts = []


def archive_macos(command):
    attempts.append(command)
    if len(attempts) == 1:
        return 65, 'error: Your team has no devices from which to generate a provisioning profile.'
    return 0, '** ARCHIVE SUCCEEDED **'


reset_sent()
failure = case('Mac, no device then this Mac', {'archive-macos': archive_macos})
archives = [c for n, c in calls if n == 'archive-macos']
expect(failure is None and len(archives) == 2 and 'generic/platform=macOS' in archives[0]
       and 'platform=macOS,arch=arm64' in archives[1]
       and '-allowProvisioningDeviceRegistration' in archives[1], 'G: this Mac registered')

# H. Another failure of the archive is not retried.
reset_sent()
failure = case('Mac, another failure', {'archive-macos': (65, 'error: No such module')})
expect(failure is not None and len([1 for n in names() if n == 'archive-macos']) == 1,
       'H: not retried')

# I. iOS by hand: verified, then sent.
reset_sent()
failure = case('iOS by hand', {'identities': '  1) 01 "Apple Distribution: Essai (ABCDE12345)"\n'},
               platform='ios')
order = names()
expect(failure is None and order.index('verification-ios') < order.index('envoi-ios'),
       'I: iOS verified before it is sent')
expect(any(n == 'verification-ios' and Path(c[0]).name == 'ditto' for n, c in calls),
       'I: the ipa is opened with ditto')
folder = envoyer.MOBILES / 'app-store-ios'
check = plistlib.loads((folder / 'ExportOptions-verification.plist').read_bytes())
sent = plistlib.loads((folder / 'ExportOptions.plist').read_bytes())
expect(check['destination'] == 'export' and sent['destination'] == 'upload'
       and check['signingStyle'] == sent['signingStyle'] == 'manual'
       and sent['provisioningProfiles'] == {'fr.aisml.color': 'Color App Store'},
       'I: export options by hand, with « Color App Store »')
archives = [c for n, c in calls if n == 'archive-ios']
expect(len(archives) == 1 and 'CODE_SIGN_STYLE=Automatic' not in archives[0],
       'I: one archive, signed by hand')
expect(any(n == 'flutter-config-ios' and any(part.startswith('--split-debug-info=') for part in c)
           for n, c in calls), 'I: the symbols of the Dart code kept apart for iOS')

# J. iOS: a framework signed for development is caught too.
reset_sent()
failure = case('iOS, Flutter signed for development',
               {'identities': '  1) 01 "Apple Distribution: Essai (ABCDE12345)"\n',
                'development': 'Flutter.framework'}, platform='ios')
expect(failure is not None and 'Flutter.framework' in str(failure)
       and 'envoi-ios' not in names(), 'J: refused before sending')

# K. No dSYM beside the core: the library stays whole, Color is sent.
reset_sent()
shutil.move(built_dsym, trial / 'dsym-de-cote')
failure = case('Mac, no dSYM of the core', {})
text = (journals[-1].folder / 'journal.txt').read_text(encoding='utf-8')
expect(failure is None and 'pas de dSYM' in text and not archived_dsym.exists()
       and not any(n == 'symboles-coeur' for n in names())
       and not archived_core.read_bytes().endswith(b'stripped'),
       'K: without a dSYM, the core keeps its symbols and the Mac is sent')
shutil.move(trial / 'dsym-de-cote', built_dsym)

# K2. A dSYM left by an earlier build (another UUID): not joined, no strip.
reset_sent()
failure = case('Mac, a dSYM of another build', {'stale_dsym': True})
text = (journals[-1].folder / 'journal.txt').read_text(encoding='utf-8')
expect(failure is None and 'pas de dSYM de ce cœur' in text and not archived_dsym.exists()
       and not archived_core.read_bytes().endswith(b'stripped') and 'envoi-macos' in names(),
       'K2: a dSYM of another build is not joined, the core keeps its symbols')

# L. strip fails: the library stays whole, Color is sent.
reset_sent()
failure = case('Mac, strip fails', {'strip_fails': True})
text = (journals[-1].folder / 'journal.txt').read_text(encoding='utf-8')
expect(failure is None and 'strip a échoué' in text and 'envoi-macos' in names(),
       'L: when strip fails, the core keeps its symbols and the Mac is sent')

# M. iOS: the program of the archive exports every function of the core.
symbols = sources / 'Color' / 'prototypes' / 'flutter-rust' / 'ios' / 'Runner' / 'core-symbols.txt'
symbols.parent.mkdir(parents=True, exist_ok=True)
symbols.write_text('_ep_a\n_ep_b\n_ep_c\n')
reset_sent()
failure = case('iOS, every function of the core exported',
               {'identities': '  1) 01 "Apple Distribution: Essai (ABCDE12345)"\n'},
               platform='ios')
text = (journals[-1].folder / 'journal.txt').read_text(encoding='utf-8')
expect(failure is None and 'Les 3 fonctions du cœur sont exportées' in text
       and 'envoi-ios' in names(), 'M: the exports read with nm, then Color is sent')

# N. iOS: a function of the core missing from the exports: nothing is sent.
reset_sent()
failure = case('iOS, a function of the core not exported',
               {'identities': '  1) 01 "Apple Distribution: Essai (ABCDE12345)"\n',
                'missing_export': '_ep_b'}, platform='ios')
expect(failure is not None and '_ep_b' in str(failure)
       and not any(n.startswith(('verification-ios', 'envoi-ios')) for n in names()),
       'N: an export missing stops everything before the export and the sending')

print('\n%d failure(s)' % len(failures))
sys.exit(1 if failures else 0)
