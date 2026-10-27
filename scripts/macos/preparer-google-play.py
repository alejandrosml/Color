#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepares Color for Google Play: the bundle (.aab) that the Play Console
takes, signed with the author's upload key.

  preparer-google-play.py TRAVAIL

The first time, it makes the upload key: a file and its password, kept in
« ~/Documents/Color - clé Google Play », outside the folders shared with
anyone; that folder is to be saved like a house key. Google Play keeps the
key that signs the application itself (« Play App Signing »): a lost upload
key can be replaced by asking Google, but it is simpler not to lose it.

Needs the tools that « Essayer Color sur Android » installs: run it first.
The bundle is written in Color-travail/google-play/. Nothing is sent:
the upload in the Play Console is the author's.
"""
from pathlib import Path
import os
import secrets
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mobiles_communs import (ANDROID_SDK, ANDROID_TARGETS, MOBILES, Failure, Journal,  # noqa: E402
                             android_environment, build_android_core, check_flutter_sdk,
                             ensure_rust, find_sources, flutter, flutter_environment, flutter_jdk,
                             installed_java_home, main_wrapper, output, run, stage_app)

KEYS = Path.home() / 'Documents' / 'Color - clé Google Play'


def java_home():
    found = installed_java_home()
    if not found:
        raise Failure('Aucun JDK 21 ou 17 : lance d’abord « Essayer Color sur Android »,'
                      ' qui en installe un dans « mobiles ».')
    return found


def upload_key(journal, java):
    """The keystore and its key.properties, made once."""
    properties = KEYS / 'key.properties'
    if properties.exists():
        return properties
    KEYS.mkdir(parents=True, exist_ok=True)
    os.chmod(KEYS, 0o700)
    password = secrets.token_urlsafe(24)
    store = KEYS / 'cle-envoi-google-play.jks'
    run(journal, 'cle', [Path(java) / 'bin' / 'keytool', '-genkeypair', '-keystore', store,
                         '-storetype', 'PKCS12', '-alias', 'envoi', '-keyalg', 'RSA',
                         '-keysize', '4096', '-validity', '10000',
                         '-dname', 'CN=Alejandro San Martin Lamas, C=FR',
                         '-storepass', password, '-keypass', password])
    properties.write_text('storeFile=%s\nstorePassword=%s\nkeyAlias=envoi\nkeyPassword=%s\n'
                          % (store, password, password))
    os.chmod(properties, 0o600)
    os.chmod(store, 0o600)
    journal.say('  Clé d’envoi créée dans « %s ». Garde une copie de ce dossier en lieu sûr.'
                % KEYS)
    return properties


def main():
    travail = Path(sys.argv[1]).resolve()
    journal = Journal(travail, 'google-play')
    sources, version = find_sources(travail)
    check_flutter_sdk()
    journal.say('Color %s pour Google Play' % version)
    if not (ANDROID_SDK / 'ndk').exists():
        raise Failure('Les outils d’Android manquent : lance d’abord « Essayer Color sur Android ».')
    java = java_home()
    environment = android_environment(java)
    properties = upload_key(journal, java)
    cargo, rust_env = ensure_rust(journal, [target for target, _, _ in ANDROID_TARGETS])
    work = stage_app(journal, sources, MOBILES / ('google-play-%s-work' % version.replace('+', '-')))
    build_android_core(journal, sources, work, cargo, rust_env)
    # Gradle reads the key where it is: neither it nor its passwords go into
    # the copy of work, which is in a folder shared with Claude.
    flutter_env = flutter_environment(dict(environment, COLOR_UPLOAD_KEY=str(properties)))
    flutter_jdk(journal, java, work, flutter_env)
    flutter(journal, 'flutter-pub-get', ['pub', 'get', '--offline'], work, flutter_env)
    flutter(journal, 'flutter-build-appbundle', ['build', 'appbundle', '--release', '--no-pub'],
            work, flutter_env)
    bundle = work / 'build' / 'app' / 'outputs' / 'bundle' / 'release' / 'app-release.aab'
    code, signer = output([Path(java) / 'bin' / 'keytool', '-printcert', '-jarfile', bundle])
    journal.keep(signer)
    if 'CN=Alejandro San Martin Lamas' not in signer:
        raise Failure('Le fichier n’est pas signé par ta clé d’envoi : la Play Console le refuserait.'
                      ' Détail : ' + str(journal.folder / 'journal.txt'))
    target = travail / 'google-play'
    target.mkdir(exist_ok=True)
    delivered = target / ('Color-%s.aab' % version)
    shutil.copy2(bundle, delivered)
    journal.state(version=version, status='prepared', bundle=str(delivered))
    journal.say('\nTerminé : ' + str(delivered))
    journal.say('Dans la Play Console : Tester > Tests fermés > Créer une version, puis'
                ' dépose ce fichier.')


if __name__ == '__main__':
    main_wrapper(main)
