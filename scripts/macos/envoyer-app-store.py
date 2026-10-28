#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Builds Color for the App Store and sends it to App Store Connect: the Mac,
and iPhone with iPad, under the identifier fr.aisml.color.

  envoyer-app-store.py TRAVAIL [--mac-seulement | --ios-seulement]

Before the first sending, once:
  - the Apple Developer Program has accepted the author;
  - Xcode knows the author's Apple Account (Xcode > Settings > Accounts);
  - the app « Color » exists in App Store Connect (Apps > + > Nouvelle app),
    for macOS and iOS, with the identifier fr.aisml.color;
  - for iPhone and iPad, one iPhone or iPad is registered to the team: Xcode
    signs an archive for iOS with a profile of development, which needs a
    device. Plugged into the Mac and trusted, the device is registered here.
A system already sent in this version is not sent again: App Store Connect
refuses the same build number twice.

In order, for each system:
  1. finds the team of the author among the certificates of this Mac, or
     asks for it once, and keeps it beside the build folders;
  2. builds the core and Color in Release, archives it with Xcode, which
     signs it for the team and makes the profiles it needs;
  3. takes the quarantine marks off every file, as Apple asks;
  4. hands the archive to Xcode, which signs it for the App Store and
     sends it to App Store Connect, where TestFlight then offers it.
Everything is written in construction-mac/journal. Nothing is published:
submitting the version for review stays a click of the author's, in App
Store Connect.
"""
from pathlib import Path
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mobiles_communs import (CARGO_TARGET, IOS_TARGETS, MOBILES, Failure, Journal,  # noqa: E402
                             check_flutter_sdk, core_folder, ensure_rust, find_sources, flutter,
                             flutter_environment, main_wrapper, output, run, stage_app)

TEAM_FILE = MOBILES / 'equipe-apple.txt'
TEAM = re.compile(r'^[A-Z0-9]{10}$')
# The last version sent for each system: App Store Connect refuses the same
# build number twice, so a second run sends only what is left.
SENT_FILE = MOBILES / 'app-store-envoyes.json'
# Xcode's words when the team has no iPhone or iPad to make the profile of
# development with which it signs an archive for iOS.
NO_DEVICE = re.compile(r'no devices? from which to generate|has no devices', re.IGNORECASE)
NO_DEVICE_ADVICE = (
    'Apple demande qu’un iPhone ou un iPad soit inscrit à ton compte de développeur avant de'
    ' signer la version iPhone et iPad. Branche ton iPhone ou ton iPad au Mac avec un câble,'
    ' déverrouille-le et touche « Se fier » s’il le demande, puis relance ce lanceur : il'
    ' l’inscrira, et n’enverra pas une seconde fois ce qui est déjà parti. Tu peux aussi'
    ' l’inscrire toi-même : https://developer.apple.com/account/resources/devices/add, avec'
    ' son identifiant (UDID), que le Finder montre en cliquant sous le nom de l’appareil.')


def teams_of_this_mac():
    """The teams of the signing certificates in the keychains of this Mac."""
    code, listing = output(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'])
    teams = set()
    for name in re.findall(r'"((?:Apple Development|Apple Distribution)[^"]*)"', listing):
        code, pem = output(['/usr/bin/security', 'find-certificate', '-c', name, '-p'])
        if code != 0:
            continue
        process = subprocess.run(['/usr/bin/openssl', 'x509', '-noout', '-subject'],
                                 input=pem, universal_newlines=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        match = re.search(r'OU\s*=\s*([A-Z0-9]{10})', process.stdout)
        if match:
            teams.add(match.group(1))
    return sorted(teams)


def team(journal):
    """The team of the author: the one kept beside the build folders, or the
    one the author confirms once. A certificate of this Mac is never taken
    without asking: it may be of a free « Personal Team », which cannot send
    anything to the App Store."""
    if TEAM_FILE.exists():
        kept = TEAM_FILE.read_text().strip()
        if TEAM.match(kept):
            return kept
    found = teams_of_this_mac()
    journal.say('  Ton identifiant d’équipe Apple (Team ID) : 10 lettres et chiffres, sur'
                ' https://developer.apple.com/account, rubrique « Membership details ».')
    if found:
        journal.say('  Équipes des certificats de ce Mac : ' + ', '.join(found)
                    + ' (une « Personal Team » gratuite ne peut rien envoyer).')
    proposal = found[0] if len(found) == 1 else ''
    prompt = '  Team ID%s : ' % (' (Entrée pour %s)' % proposal if proposal else '')
    chosen = input(prompt).strip().upper() or proposal
    if not TEAM.match(chosen):
        raise Failure('« %s » n’est pas un identifiant d’équipe Apple.' % chosen)
    MOBILES.mkdir(parents=True, exist_ok=True)
    TEAM_FILE.write_text(chosen + '\n')
    return chosen


def export_options(journal, team_id, folder):
    options = folder / 'ExportOptions.plist'
    with options.open('wb') as file:
        plistlib.dump({
            'method': 'app-store-connect',
            'destination': 'upload',
            'teamID': team_id,
            'signingStyle': 'automatic',
            'uploadSymbols': True,
            'manageAppVersionAndBuildNumber': False,
        }, file)
    return options


def archive_and_send(journal, work, platform, team_id, extra_settings=()):
    """xcodebuild archive, then exportArchive to App Store Connect."""
    folder = MOBILES / ('app-store-' + platform)
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    archive = folder / 'Color.xcarchive'
    project = work / platform / 'Runner.xcworkspace'
    command = ['/usr/bin/xcodebuild', '-workspace', project, '-scheme', 'Runner',
               '-configuration', 'Release', '-archivePath', archive,
               '-destination', 'generic/platform=' + ('macOS' if platform == 'macos' else 'iOS'),
               'archive', '-allowProvisioningUpdates', 'DEVELOPMENT_TEAM=' + team_id,
               'CODE_SIGN_STYLE=Automatic'] + list(extra_settings)
    run(journal, 'archive-' + platform, command, cwd=work)
    return archive, folder


def send(journal, archive, folder, team_id, platform):
    # Apple refuses files that still carry the quarantine of a download.
    run(journal, 'quarantaine', ['/usr/bin/xattr', '-cr', archive], check=False)
    options = export_options(journal, team_id, folder)
    run(journal, 'envoi-' + platform, ['/usr/bin/xcodebuild', '-exportArchive', '-archivePath',
                                       archive, '-exportOptionsPlist', options, '-exportPath',
                                       folder / 'export', '-allowProvisioningUpdates'])


def mac(journal, sources, version, team_id):
    journal.say('\nColor pour le Mac App Store')
    work = stage_app(journal, sources, MOBILES / ('app-store-mac-%s-work' % version.replace('+', '-')))
    environment = os.environ.copy()
    environment.update(MACOSX_DEPLOYMENT_TARGET='26.6', CARGO_TARGET_DIR=str(CARGO_TARGET / 'mac'))
    cargo = shutil.which('cargo', path='/opt/homebrew/bin') or 'cargo'
    run(journal, 'coeur-mac', [cargo, 'rustc', '--release', '--lib', '--offline', '--frozen',
                               '--target', 'aarch64-apple-darwin', '--',
                               '-C', 'link-arg=-Wl,-install_name,@rpath/libedupaint_core.dylib'],
        cwd=core_folder(sources), env=environment)
    dylib = CARGO_TARGET / 'mac' / 'aarch64-apple-darwin' / 'release' / 'libedupaint_core.dylib'
    flutter_env = flutter_environment()
    flutter(journal, 'flutter-pub-get', ['pub', 'get', '--offline'], work, flutter_env)
    flutter(journal, 'flutter-build-macos', ['build', 'macos', '--release', '--no-pub'], work,
            flutter_env)
    journal.say('  Archive signée par Xcode…')
    archive, folder = archive_and_send(journal, work, 'macos', team_id,
                                       ['CODE_SIGN_IDENTITY=Apple Development'])
    app = archive / 'Products' / 'Applications' / 'Color.app'
    if not app.is_dir():
        raise Failure('L’archive ne contient pas Color.app : ' + str(archive))
    # The core goes beside the frameworks of Flutter, signed by the same
    # identity, and the application is sealed again with its entitlements.
    embedded = app / 'Contents' / 'Frameworks' / 'libedupaint_core.dylib'
    shutil.copy2(dylib, embedded)
    code, description = output(['/usr/bin/codesign', '-dvv', app])
    identity = re.search(r'Authority=(Apple Development[^\n]*)', description)
    if not identity:
        raise Failure('La signature de l’archive est illisible : ' + description[-300:])
    run(journal, 'signature', ['/usr/bin/codesign', '--force', '--sign', identity.group(1), embedded])
    run(journal, 'signature', ['/usr/bin/codesign', '--force', '--sign', identity.group(1),
                               '--preserve-metadata=entitlements,requirements,flags,runtime', app])
    journal.say('  Envoi à App Store Connect…')
    send(journal, archive, folder, team_id, 'macos')
    remember_sent('macos', version)
    journal.say('  Color pour le Mac : envoyée.')


def sent_versions():
    try:
        return json.loads(SENT_FILE.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {}


def remember_sent(platform, version):
    sent = sent_versions()
    sent[platform] = version
    MOBILES.mkdir(parents=True, exist_ok=True)
    SENT_FILE.write_text(json.dumps(sent, indent=2) + '\n', encoding='utf-8')


def connected_ios_device(journal):
    """(UDID, name) of an iPhone or iPad plugged into this Mac and paired
    with it, or None."""
    # In the journal of this run: never the answer of an earlier one.
    listing = journal.folder / 'appareils.json'
    code, text = output(['/usr/bin/xcrun', 'devicectl', 'list', 'devices', '--json-output',
                         str(listing)])
    journal.keep('devicectl list devices : code %d' % code)
    if code != 0:
        return None
    try:
        devices = json.loads(listing.read_text(encoding='utf-8'))['result']['devices']
    except (OSError, ValueError, KeyError, TypeError):
        return None
    for device in devices:
        hardware = device.get('hardwareProperties', {})
        connection = device.get('connectionProperties', {})
        if hardware.get('platform') == 'iOS' and connection.get('pairingState') == 'paired':
            udid = hardware.get('udid')
            if udid:
                return udid, device.get('deviceProperties', {}).get('name', udid)
    return None


def archive_ios(journal, work, team_id):
    """The archive for iOS. A team without any iPhone or iPad cannot have the
    profile of development that Xcode signs an archive with: the device
    plugged into the Mac is then registered by a build for it, and the
    archive made again."""
    try:
        return archive_and_send(journal, work, 'ios', team_id)
    except Failure:
        log = journal.folder / 'archive-ios.log'
        text = log.read_text(encoding='utf-8', errors='replace') if log.exists() else ''
        if not NO_DEVICE.search(text):
            raise
    device = connected_ios_device(journal)
    if device is None:
        raise Failure(NO_DEVICE_ADVICE)
    udid, name = device
    journal.say('  Apple demande un appareil inscrit à ton compte : j’inscris « %s »…' % name)
    code = run(journal, 'appareil-ios',
               ['/usr/bin/xcodebuild', '-workspace', work / 'ios' / 'Runner.xcworkspace',
                '-scheme', 'Runner', '-configuration', 'Release', '-destination', 'id=' + udid,
                'build', '-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration',
                'DEVELOPMENT_TEAM=' + team_id, 'CODE_SIGN_STYLE=Automatic'],
               cwd=work, check=False)
    if code != 0:
        raise Failure('L’inscription de « %s » n’a pas abouti (journal : appareil-ios.log). '
                      % name + NO_DEVICE_ADVICE)
    return archive_and_send(journal, work, 'ios', team_id)


def ios(journal, sources, version, team_id):
    journal.say('\nColor pour iPhone et iPad')
    work = stage_app(journal, sources, MOBILES / ('app-store-ios-%s-work' % version.replace('+', '-')))
    cargo, rust_env = ensure_rust(journal, IOS_TARGETS)
    rust_env['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
    run(journal, 'coeur-ios', cargo + ['rustc', '--release', '--lib', '--offline', '--frozen',
                                       '--target', 'aarch64-apple-ios', '--crate-type', 'staticlib'],
        cwd=core_folder(sources), env=rust_env)
    place = work / 'ios' / 'rust' / 'iphoneos'
    place.mkdir(parents=True, exist_ok=True)
    shutil.copy2(CARGO_TARGET / 'aarch64-apple-ios' / 'release' / 'libedupaint_core.a', place)
    (work / 'ios' / 'Runner' / 'Equipe.xcconfig').write_text(
        'DEVELOPMENT_TEAM = %s\nCODE_SIGN_STYLE = Automatic\n' % team_id)
    flutter_env = flutter_environment()
    flutter(journal, 'flutter-precache', ['precache', '--ios'], work, flutter_env)
    flutter(journal, 'flutter-pub-get', ['pub', 'get', '--offline'], work, flutter_env)
    flutter(journal, 'flutter-config-ios', ['build', 'ios', '--release', '--no-pub',
                                            '--config-only'], work, flutter_env)
    journal.say('  Archive signée par Xcode…')
    archive, folder = archive_ios(journal, work, team_id)
    journal.say('  Envoi à App Store Connect…')
    send(journal, archive, folder, team_id, 'ios')
    remember_sent('ios', version)
    journal.say('  Color pour iPhone et iPad : envoyée.')


def main():
    travail = Path(sys.argv[1]).resolve()
    which = sys.argv[2] if len(sys.argv) > 2 else ''
    journal = Journal(travail, 'app-store')
    sources, version = find_sources(travail)
    check_flutter_sdk()
    journal.say('Color %s vers App Store Connect' % version)
    code, xcode = output(['/usr/bin/xcodebuild', '-version'])
    if code != 0:
        raise Failure('Xcode ne répond pas (xcodebuild -version).')
    team_id = team(journal)
    journal.say('  Équipe Apple : ' + team_id)
    journal.state(version=version, team=team_id, status='started')
    sent = sent_versions()
    for platform, wanted, build, label in (
            ('macos', which != '--ios-seulement', mac, 'le Mac'),
            ('ios', which != '--mac-seulement', ios, 'l’iPhone et l’iPad')):
        if not wanted:
            continue
        if sent.get(platform) == version:
            journal.say('\nColor %s pour %s est déjà partie : App Store Connect ne prend pas deux'
                        ' fois la même version.' % (version, label))
            continue
        build(journal, sources, version, team_id)
    journal.state(status='sent')
    journal.say('\nTerminé. Dans une demi-heure environ, App Store Connect montre la version'
                ' dans TestFlight. Installe-la avec l’app TestFlight pour l’essayer, puis soumets-la'
                ' à la vérification d’Apple depuis App Store Connect.')
    journal.say('Journal : ' + str(journal.folder))


if __name__ == '__main__':
    main_wrapper(main)
