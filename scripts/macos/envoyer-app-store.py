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
  - for iPhone and iPad, either the « Apple Distribution » certificate of the
    team in this Mac's keychain (Xcode > Settings > Accounts > Manage
    Certificates) with the profile « Color App Store » made on
    developer.apple.com, and Color is signed for the App Store without any
    device; or one iPhone or iPad registered to the team, since Xcode signs
    an archive automatically with a profile of development, which needs a
    device: plugged into the Mac and trusted, it is registered here;
  - for the Mac, Xcode makes the profiles and certificates it lacks; the
    « Mac Installer Distribution » certificate, made beside « Apple
    Distribution », signs the package sent. Should Xcode ask for a device,
    this Mac is the one it registers.
A system already sent in this version is not sent again: App Store Connect
refuses the same build number twice, even after refusing the build itself.

In order, for each system:
  1. finds the team of the author among the certificates of this Mac, or
     asks for it once, and keeps it beside the build folders;
  2. builds the core and Color in Release, archives it with Xcode, which
     signs it for the team and makes the profiles it needs; on the Mac, the
     resource bundles of Swift packages lose the signature Xcode gave them,
     which App Store Connect refused (ITMS-90284, 1.0.0 (38));
  3. takes the quarantine marks off every file, as Apple asks;
  4. has Xcode sign the archive for the App Store into a package kept on
     this Mac, and reads every signature in it: all must be Color's, by a
     certificate of distribution, or nothing is sent;
  5. hands the archive to Xcode, which signs it again and sends it to App
     Store Connect, where TestFlight then offers it.
Everything is written in construction-mac/journal. Nothing is published:
submitting the version for review stays a click of the author's, in App
Store Connect.
"""
from pathlib import Path
import hashlib
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
# The profile with which Color is signed for the App Store of iOS without any
# device: made once on developer.apple.com (Profiles > + > App Store Connect,
# App ID fr.aisml.color, the « Apple Distribution » certificate of the team).
PROFILE_NAME = 'Color App Store'
NO_DEVICE_ADVICE = (
    'Apple demande qu’un iPhone ou un iPad soit inscrit à ton compte de développeur pour'
    ' signer la version iPhone et iPad de cette façon. Deux chemins, puis relance ce lanceur,'
    ' qui n’enverra pas une seconde fois ce qui est déjà parti :\n'
    '  - sans câble : dans Xcode, Settings… → Accounts → ton compte → Manage Certificates… →'
    ' « + » → Apple Distribution ; puis le profil « ' + PROFILE_NAME + ' » sur'
    ' https://developer.apple.com/account/resources/profiles/add (App Store Connect, App ID'
    ' fr.aisml.color, ce certificat) ;\n'
    '  - avec un câble : branche ton iPhone ou ton iPad au Mac, déverrouille-le et touche'
    ' « Se fier » : le lanceur l’inscrira.')
NO_PROFILE = re.compile(r'No profiles? for|doesn.t match|not found|No signing certificate',
                        re.IGNORECASE)

# The first bytes of a program or library of Apple: thin, in either order of
# bytes, or universal.
MACH_O_MAGICS = {bytes.fromhex(magic) for magic in (
    'feedface', 'feedfacf', 'cefaedfe', 'cffaedfe', 'cafebabe', 'cafebabf')}
# The certificates by which App Store Connect takes a build.
DISTRIBUTION = re.compile(r'(Apple Distribution|3rd Party Mac Developer Application'
                          r'|iPhone Distribution): ')


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


def export_options(journal, team_id, folder, manual=False, destination='upload'):
    """The options of xcodebuild -exportArchive: sent to App Store Connect, or,
    with destination « export », kept on this Mac to be checked."""
    options = folder / ('ExportOptions.plist' if destination == 'upload'
                        else 'ExportOptions-verification.plist')
    settings = {
        'method': 'app-store-connect',
        'destination': destination,
        'teamID': team_id,
        'signingStyle': 'automatic',
        'uploadSymbols': True,
        'manageAppVersionAndBuildNumber': False,
    }
    if manual:
        settings.update(signingStyle='manual', signingCertificate='Apple Distribution',
                        provisioningProfiles={'fr.aisml.color': PROFILE_NAME})
    with options.open('wb') as file:
        plistlib.dump(settings, file)
    return options


def archive_and_send(journal, work, platform, team_id, extra_settings=(), manual=False,
                     register_this_mac=False):
    """xcodebuild archive, then exportArchive to App Store Connect. A manual
    signing is set in Equipe.xcconfig, for Color's target only: on the
    command line it would reach the targets that take no profile. With
    `register_this_mac`, the archive is made for this Mac, which Xcode may
    then register to the team, as its window does."""
    folder = MOBILES / ('app-store-' + platform)
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    archive = folder / 'Color.xcarchive'
    project = work / platform / 'Runner.xcworkspace'
    destination = 'generic/platform=' + ('macOS' if platform == 'macos' else 'iOS')
    if register_this_mac:
        destination = 'platform=macOS,arch=arm64'
    command = ['/usr/bin/xcodebuild', '-workspace', project, '-scheme', 'Runner',
               '-configuration', 'Release', '-archivePath', archive,
               '-destination', destination,
               'archive', '-allowProvisioningUpdates', 'DEVELOPMENT_TEAM=' + team_id]
    if register_this_mac:
        command.append('-allowProvisioningDeviceRegistration')
    if not manual:
        command.append('CODE_SIGN_STYLE=Automatic')
    run(journal, 'archive-' + platform, command + list(extra_settings), cwd=work)
    return archive, folder


def distribution_identity(team_id):
    """The « Apple Distribution » identity of the team in the keychain of this
    Mac, with its private key: with it and PROFILE_NAME, Color is signed for
    the App Store of iOS without any registered device."""
    code, listing = output(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'])
    found = re.findall(r'"(Apple Distribution: [^"]*\(%s\))"' % re.escape(team_id), listing)
    return found[0] if found else None


def resource_bundles_unsigned(journal, app):
    """The resource bundles of Swift packages, in Contents/Resources: Xcode
    signs them with the identity of the archive, and its export for the App
    Store leaves them so, outside the places where it signs again. App Store
    Connect refused Color 1.0.0 (38) for the Mac because of one (ITMS-90284,
    28 October 2026: file_selector_macos_file_selector_macos.bundle « must be
    signed with the certificate that is contained in the provisioning
    profile »). They hold no code: without a signature of their own, they are
    sealed by Color's, like its other resources. A bundle there that holds
    code stops everything: it would need a signature of its own."""
    for bundle in sorted((app / 'Contents' / 'Resources').glob('*.bundle')):
        contents = bundle / 'Contents'
        signature = contents / '_CodeSignature'
        if not signature.exists():
            continue
        try:
            info = plistlib.loads((contents / 'Info.plist').read_bytes())
        except (OSError, ValueError):
            info = {}
        if info.get('CFBundleExecutable') or (contents / 'MacOS').exists():
            raise Failure('« %s », dans les ressources de Color, contient du code : il lui faudrait'
                          ' sa propre signature pour l’App Store. Rien n’est envoyé.' % bundle.name)
        run(journal, 'signature', ['/usr/bin/codesign', '--remove-signature', bundle], check=False)
        if signature.exists():
            shutil.rmtree(signature)
        journal.say('  « %s » : des ressources sans code, sa signature est retirée.' % bundle.name)


def mach_o(path):
    try:
        with path.open('rb') as file:
            return file.read(4) in MACH_O_MAGICS
    except OSError:
        return False


def signed_items(app):
    """What App Store Connect checks in `app`: the application, every program
    and library, and every bundle that carries a signature of its own."""
    items = [app]
    for path in sorted(app.rglob('*')):
        if path.is_symlink():
            continue
        if path.name == '_CodeSignature' and path.is_dir():
            holder = path.parent.parent if path.parent.name == 'Contents' else path.parent
            if holder not in items:
                items.append(holder)
        elif path.is_file() and mach_o(path) and path not in items:
            items.append(path)
    return items


def leaf_certificate(item, scratch):
    """The digest of the certificate that signed `item`, and what codesign says
    of it; None for what carries no signature."""
    for old in scratch.glob('certificat-*'):
        old.unlink()
    code, text = output(['/usr/bin/codesign', '-d', '-vv',
                         '--extract-certificates=' + str(scratch / 'certificat-'), item])
    leaf = scratch / 'certificat-0'
    if code != 0 or not leaf.exists():
        return None, text
    return hashlib.sha256(leaf.read_bytes()).hexdigest(), text


def check_signatures(journal, exported, platform):
    """Opens the package of an export kept on this Mac and reads every
    signature in it: each must be Color's, by a certificate of distribution.
    Otherwise nothing is sent, since App Store Connect takes a build number
    only once, even for a build it then refuses."""
    packages = sorted(exported.glob('*.pkg' if platform == 'macos' else '*.ipa'))
    if not packages:
        raise Failure('L’export de vérification n’a rien produit : ' + str(exported))
    opened = exported / 'ouvert'
    if platform == 'macos':
        run(journal, 'verification-' + platform,
            ['/usr/sbin/pkgutil', '--expand-full', packages[0], opened])
    else:
        run(journal, 'verification-' + platform,
            ['/usr/bin/ditto', '-x', '-k', packages[0], opened])
    apps = sorted(opened.rglob('*.app'), key=lambda path: len(path.parts))
    if not apps:
        raise Failure('Pas d’application dans ' + str(packages[0]))
    app = apps[0]
    run(journal, 'verification-' + platform,
        ['/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=2', app])
    scratch = exported / 'certificats'
    scratch.mkdir(exist_ok=True)
    reference, text = leaf_certificate(app, scratch)
    authority = re.search(r'^Authority=(.*)$', text, re.MULTILINE)
    if reference is None or not authority or not DISTRIBUTION.match(authority.group(1)):
        raise Failure('Color n’est pas signée par un certificat de distribution : %s. Rien'
                      ' n’est envoyé.' % (authority.group(1) if authority else text.strip()[-300:]))
    items = signed_items(app)
    wrong = []
    for item in items[1:]:
        digest, said = leaf_certificate(item, scratch)
        if digest != reference:
            other = re.search(r'^Authority=(.*)$', said, re.MULTILINE)
            wrong.append('%s (%s)' % (item.relative_to(app),
                                      other.group(1) if other else 'sans signature'))
    journal.keep('Signatures relues : %s' % ', '.join(str(item.relative_to(app.parent))
                                                    for item in items))
    if wrong:
        raise Failure('Signé autrement que Color, ce qu’App Store Connect refuserait : '
                      + ' ; '.join(wrong) + '. Rien n’est envoyé.')
    journal.say('  Signatures relues : %d éléments, tous par « %s ».'
                % (len(items), authority.group(1)))


def send(journal, archive, folder, team_id, platform, manual=False):
    # Apple refuses files that still carry the quarantine of a download.
    run(journal, 'quarantaine', ['/usr/bin/xattr', '-cr', archive], check=False)
    # First an export kept here, whose signatures are all read before anything
    # leaves this Mac.
    journal.say('  Export de vérification, signé pour l’App Store…')
    exported = folder / 'verification'
    options = export_options(journal, team_id, folder, manual, destination='export')
    run(journal, 'verification-' + platform,
        ['/usr/bin/xcodebuild', '-exportArchive', '-archivePath', archive, '-exportOptionsPlist',
         options, '-exportPath', exported, '-allowProvisioningUpdates'])
    check_signatures(journal, exported, platform)
    journal.say('  Envoi à App Store Connect…')
    options = export_options(journal, team_id, folder, manual)
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
    try:
        archive, folder = archive_and_send(journal, work, 'macos', team_id,
                                           ['CODE_SIGN_IDENTITY=Apple Development'])
    except Failure:
        log = journal.folder / 'archive-macos.log'
        text = log.read_text(encoding='utf-8', errors='replace') if log.exists() else ''
        if not NO_DEVICE.search(text):
            raise
        # A profile of development needs a registered device: for the Mac,
        # this Mac is one, which Xcode registers itself.
        journal.say('  Apple demande un appareil inscrit à ton compte : j’inscris ce Mac…')
        archive, folder = archive_and_send(journal, work, 'macos', team_id,
                                           ['CODE_SIGN_IDENTITY=Apple Development'],
                                           register_this_mac=True)
    app = archive / 'Products' / 'Applications' / 'Color.app'
    if not app.is_dir():
        raise Failure('L’archive ne contient pas Color.app : ' + str(archive))
    # The core goes beside the frameworks of Flutter, signed by the same
    # identity, and the application is sealed again with its entitlements.
    embedded = app / 'Contents' / 'Frameworks' / 'libedupaint_core.dylib'
    shutil.copy2(dylib, embedded)
    resource_bundles_unsigned(journal, app)
    code, description = output(['/usr/bin/codesign', '-dvv', app])
    identity = re.search(r'Authority=(Apple Development[^\n]*)', description)
    if not identity:
        raise Failure('La signature de l’archive est illisible : ' + description[-300:])
    run(journal, 'signature', ['/usr/bin/codesign', '--force', '--sign', identity.group(1), embedded])
    run(journal, 'signature', ['/usr/bin/codesign', '--force', '--sign', identity.group(1),
                               '--preserve-metadata=entitlements,requirements,flags,runtime', app])
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
    identity = distribution_identity(team_id)
    if identity:
        # Signed for the App Store from the start: no profile of development,
        # so no device is needed.
        (work / 'ios' / 'Runner' / 'Equipe.xcconfig').write_text(
            'DEVELOPMENT_TEAM = %s\nCODE_SIGN_STYLE = Manual\n'
            'CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution\n'
            'PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*] = %s\n' % (team_id, PROFILE_NAME))
    else:
        (work / 'ios' / 'Runner' / 'Equipe.xcconfig').write_text(
            'DEVELOPMENT_TEAM = %s\nCODE_SIGN_STYLE = Automatic\n' % team_id)
    flutter_env = flutter_environment()
    flutter(journal, 'flutter-precache', ['precache', '--ios'], work, flutter_env)
    flutter(journal, 'flutter-pub-get', ['pub', 'get', '--offline'], work, flutter_env)
    flutter(journal, 'flutter-config-ios', ['build', 'ios', '--release', '--no-pub',
                                            '--config-only'], work, flutter_env)
    if identity:
        journal.say('  Archive signée pour l’App Store, par « %s » et le profil « %s »…'
                    % (identity, PROFILE_NAME))
        try:
            archive, folder = archive_and_send(journal, work, 'ios', team_id, manual=True)
        except Failure:
            log = journal.folder / 'archive-ios.log'
            text = log.read_text(encoding='utf-8', errors='replace') if log.exists() else ''
            if PROFILE_NAME in text or NO_PROFILE.search(text):
                raise Failure('Le profil « %s » manque ou ne va pas avec le certificat « %s ».'
                              ' Crée-le sur https://developer.apple.com/account/resources/'
                              'profiles/add : App Store Connect, App ID fr.aisml.color, ce'
                              ' certificat, nom « %s ». Journal : %s'
                              % (PROFILE_NAME, identity, PROFILE_NAME, log))
            raise
    else:
        journal.say('  Archive signée par Xcode…')
        archive, folder = archive_ios(journal, work, team_id)
    send(journal, archive, folder, team_id, 'ios', manual=bool(identity))
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
