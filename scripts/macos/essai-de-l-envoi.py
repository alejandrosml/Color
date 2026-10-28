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
  - iOS, signed by hand: the same verification, and the export options.

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

VERSION = '1.0.0+39'
travail = trial / 'travail'
sources = travail / ('Color-%s-sources' % VERSION)
sources.mkdir(parents=True)
MACH_O = bytes.fromhex('cffaedfe') + b'\0' * 60
BUNDLE = 'file_selector_macos_file_selector_macos.bundle'
journals = []
calls = []
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
    if 'find-identity' in command:
        return 0, behaviour.get('identities', '')
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


def names():
    return [name for name, command in calls]


def case(title, settings, platform='macos'):
    calls.clear()
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

# J. iOS: a framework signed for development is caught too.
reset_sent()
failure = case('iOS, Flutter signed for development',
               {'identities': '  1) 01 "Apple Distribution: Essai (ABCDE12345)"\n',
                'development': 'Flutter.framework'}, platform='ios')
expect(failure is not None and 'Flutter.framework' in str(failure)
       and 'envoi-ios' not in names(), 'J: refused before sending')

print('\n%d failure(s)' % len(failures))
sys.exit(1 if failures else 0)
