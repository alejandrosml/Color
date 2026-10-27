#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Builds Color for the App Store and sends it to App Store Connect: the Mac,
and iPhone with iPad, under the identifier fr.aisml.color.

  envoyer-app-store.py TRAVAIL [--mac-seulement | --ios-seulement]

Before the first sending, once:
  - the Apple Developer Program has accepted the author;
  - Xcode knows the author's Apple Account (Xcode > Réglages > Comptes);
  - the app « Color » exists in App Store Connect (Apps > + > Nouvelle app),
    for macOS and iOS, with the identifier fr.aisml.color.

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
    if TEAM_FILE.exists():
        kept = TEAM_FILE.read_text().strip()
        if TEAM.match(kept):
            return kept
    found = teams_of_this_mac()
    if len(found) == 1:
        chosen = found[0]
    else:
        journal.say('  Ton identifiant d’équipe Apple (Team ID) : 10 lettres et chiffres, sur'
                    ' https://developer.apple.com/account, rubrique « Membership details ».')
        if found:
            journal.say('  Équipes trouvées sur ce Mac : ' + ', '.join(found))
        chosen = input('  Team ID : ').strip().upper()
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
    journal.say('  Color pour le Mac : envoyée.')


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
    archive, folder = archive_and_send(journal, work, 'ios', team_id)
    journal.say('  Envoi à App Store Connect…')
    send(journal, archive, folder, team_id, 'ios')
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
    if which != '--ios-seulement':
        mac(journal, sources, version, team_id)
    if which != '--mac-seulement':
        ios(journal, sources, version, team_id)
    journal.state(status='sent')
    journal.say('\nTerminé. Dans une demi-heure environ, App Store Connect montre la version'
                ' dans TestFlight. Installe-la avec l’app TestFlight pour l’essayer, puis soumets-la'
                ' à la vérification d’Apple depuis App Store Connect.')
    journal.say('Journal : ' + str(journal.folder))


if __name__ == '__main__':
    main_wrapper(main)
