#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check, by reading only, the application that one run of construire-color.py handed over.

  controler-la-remise.py JOURNAL [--remise DOSSIER] [--sortie APP] [--precedente APP]
                         [--droit-ajoute DROIT]... [--coeur-contient TEXTE]...
                         [--coeur-sans TEXTE]... [--interface-contient TEXTE]...
                         [--programme-contient TEXTE]... [--ecrire]

JOURNAL is the folder of that run, with its etat.json and recette/result.json.
The paths they name are those of the Mac; from another place that sees the
same folders, --remise gives the hand-over folder and --sortie the recipe's
own Color.app. --precedente names an earlier Color.app whose composition is
compared; --droit-ajoute names a right (an entitlement, such as
com.apple.security.print) that this version is expected to have in addition
to those of the earlier one. The TEXTE options look for a text in the Rust
core, in the compiled interface or in the program itself of the handed-over
copy: a way to see that a change is, or is no longer, in what was delivered.

It starts no program of the Mac, opens no application and does not verify
the signature: codesign did, during the build. With --ecrire the report is
also written into JOURNAL as controle-de-la-copie-remise.txt, never over an
existing one. Exit code 0 when every comparison holds.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import plistlib
import re
import sys

CORE = 'Contents/Frameworks/libedupaint_core.dylib'
INTERFACE = 'Contents/Frameworks/App.framework/Versions/A/App'
PROGRAM = 'Contents/MacOS/Color'


def sha256(path):
    digest = hashlib.sha256()
    with open(str(path), 'rb') as file:
        for block in iter(lambda: file.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def inventory(app):
    """(files with their digest, links with their target, folders) of a bundle."""
    files, links, folders = {}, {}, []
    for root, names, leaves in os.walk(str(app)):
        base = Path(root)
        for name in list(names):
            path = base / name
            relative = path.relative_to(app).as_posix()
            if path.is_symlink():
                links[relative] = os.readlink(str(path))
                names.remove(name)
            else:
                folders.append(relative)
        for name in leaves:
            path = base / name
            relative = path.relative_to(app).as_posix()
            if path.is_symlink():
                links[relative] = os.readlink(str(path))
            else:
                files[relative] = sha256(path)
    return files, links, sorted(folders)


def entitlements(app):
    """The rights written in the signature of the program, read from the file."""
    data = (app / PROGRAM).read_bytes()
    return sorted({(key + b'=' + value).decode() for key, value in re.findall(
        rb'<key>(com\.apple\.[A-Za-z0-9._-]+)</key>\s*<(true|false)/>', data)})


def plist(app):
    with (app / 'Contents' / 'Info.plist').open('rb') as file:
        return plistlib.load(file)


def holds(data, text):
    """Whether the text is in the binary, as UTF-8 or as UTF-16."""
    return text.encode('utf-8') in data or text.encode('utf-16-le') in data


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('journal')
    parser.add_argument('--remise')
    parser.add_argument('--sortie')
    parser.add_argument('--precedente')
    parser.add_argument('--droit-ajoute', action='append', default=[])
    parser.add_argument('--coeur-contient', action='append', default=[])
    parser.add_argument('--coeur-sans', action='append', default=[])
    parser.add_argument('--interface-contient', action='append', default=[])
    parser.add_argument('--programme-contient', action='append', default=[])
    parser.add_argument('--ecrire', action='store_true')
    arguments = parser.parse_args()

    journal = Path(arguments.journal).resolve()
    target = journal / 'controle-de-la-copie-remise.txt'
    if arguments.ecrire and target.exists():
        sys.exit('déjà présent, non remplacé : ' + str(target))
    state = json.loads((journal / 'etat.json').read_text(encoding='utf-8'))
    result = json.loads((journal / 'recette' / 'result.json').read_text(encoding='utf-8'))
    version = state.get('version', 'inconnue')
    delivery = Path(arguments.remise or state['delivery'])
    delivered = delivery / 'Color.app'
    built = Path(arguments.sortie or result['app'])
    failures = []
    out = []
    say = out.append

    def verdict(condition, yes='oui', no='NON'):
        if not condition:
            failures.append(len(out))
        return yes if condition else no

    title = 'Contrôle de la copie remise de Color ' + version
    say(title)
    say('=' * len(title))
    say('')
    say('Fait le ' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d à %H:%M UTC')
        + ', en lecture seule. Aucun programme du Mac n’est lancé par ce contrôle,')
    say('l’application n’est pas ouverte et sa signature n’est pas vérifiée ici : codesign l’a')
    say('vérifiée pendant la construction (journal.txt).')
    say('')
    say('Journal          : ' + journal.name)
    say('Copie remise     : ' + state.get('delivery', str(delivery)) + '/Color.app')
    say('Sortie de recette: ' + result.get('app', str(built)))
    if arguments.precedente:
        say('Version comparée : …/' + '/'.join(Path(arguments.precedente).parts[-3:]))
    say('')

    d_files, d_links, d_folders = inventory(delivered)
    b_files, b_links, b_folders = inventory(built)
    say('1. La copie remise est-elle la sortie de la recette ?')
    say('   fichiers : %d dans la copie, %d dans la sortie ; contenus identiques : %s'
        % (len(d_files), len(b_files), verdict(d_files == b_files)))
    say('   liens    : %d et %d ; identiques : %s' % (len(d_links), len(b_links), verdict(d_links == b_links)))
    say('   dossiers : %d et %d ; identiques : %s'
        % (len(d_folders), len(b_folders), verdict(d_folders == b_folders)))
    say('')

    say('2. Les empreintes de la copie sont-elles celles de result.json ?')
    for key, relative in [('application_binary_sha256', PROGRAM), ('dart_aot_sha256', INTERFACE),
                          ('rust_dylib_sha256', CORE)]:
        actual = d_files.get(relative)
        say('   %-27s %s  %s' % (key, actual, verdict(result.get(key) == actual, 'identique',
                                                      'DIFFÉRENTE de ' + str(result.get(key)))))
    info = plist(delivered)
    numbers = '%s+%s' % (info.get('CFBundleShortVersionString'), info.get('CFBundleVersion'))
    say('   version inscrite dans l’application : %s  %s'
        % (numbers, verdict(numbers == version, 'celle du journal', 'PAS celle du journal, ' + version)))
    archive = delivery / ('Color-' + version + '-mac.zip')
    recorded = state.get('archive') or {}
    if archive.is_file():
        digest = sha256(archive)
        say('   %-27s %s  (%d octets)' % (archive.name, digest, archive.stat().st_size))
        if recorded.get('sha256'):
            say('   empreinte et taille notées par le lanceur : '
                + verdict(recorded.get('sha256') == digest and recorded.get('bytes') == archive.stat().st_size,
                          'les mêmes', 'DIFFÉRENTES')
                + ' ; entrées : %s, liens : %s' % (recorded.get('entries'), recorded.get('links')))
    else:
        say('   ' + archive.name + ' : ' + verdict(False, no='ABSENT'))
    say('')

    section = 3
    if arguments.precedente:
        previous = Path(arguments.precedente)
        p_files, p_links, _ = inventory(previous)
        old = plist(previous)
        say('%d. La composition est-elle celle de la version %s+%s ?'
            % (section, old.get('CFBundleShortVersionString'), old.get('CFBundleVersion')))
        only_new = sorted(set(d_files) - set(p_files))
        only_old = sorted(set(p_files) - set(d_files))
        say('   fichiers : %d (avant) et %d (maintenant)' % (len(p_files), len(d_files)))
        say('   présents seulement maintenant : ' + (', '.join(only_new) if only_new else 'aucun'))
        say('   présents seulement avant      : ' + (', '.join(only_old) if only_old else 'aucun'))
        say('   liens    : %d et %d ; identiques : %s' % (len(p_links), len(d_links), verdict(p_links == d_links)))
        changed = sorted(path for path in set(d_files) & set(p_files) if d_files[path] != p_files[path])
        say('   fichiers au contenu inchangé : %d ; au contenu différent : %d'
            % (len(set(d_files) & set(p_files)) - len(changed), len(changed)))
        for path in changed:
            say('     différent : ' + path)
        say('   Info.plist, clés différentes :')
        for key in sorted(set(old) | set(info)):
            if old.get(key) != info.get(key):
                say('     %s : %r -> %r' % (key, old.get(key), info.get(key)))
        say('     autres clés identiques : %d' % sum(1 for key in set(old) | set(info)
                                                      if old.get(key) == info.get(key)))
        before, after = entitlements(previous), entitlements(delivered)
        say('   droits inscrits dans la signature du programme (lus dans le fichier, sans codesign) :')
        say('     avant      : ' + ', '.join(before))
        if arguments.droit_ajoute:
            expected = sorted(set(before) | set(right + '=true' for right in arguments.droit_ajoute))
            say('     attendus   : ceux d’avant, et en plus ' + ', '.join(arguments.droit_ajoute))
            say('     maintenant : ' + ', '.join(after) + '  '
                + verdict(after == expected, 'ceux attendus', 'DIFFÉRENTS'))
        else:
            say('     maintenant : ' + ', '.join(after) + '  ' + verdict(before == after, 'les mêmes', 'DIFFÉRENTS'))
        say('')
        section += 1

    if (arguments.coeur_contient or arguments.coeur_sans or arguments.interface_contient
            or arguments.programme_contient):
        say('%d. Ce que la copie remise contient' % section)
        core = (delivered / CORE).read_bytes()
        interface = (delivered / INTERFACE).read_bytes()
        for text in arguments.coeur_contient:
            say('   cœur, présent attendu      : %s  « %s »' % (verdict(holds(core, text), 'présent', 'ABSENT'), text))
        for text in arguments.coeur_sans:
            say('   cœur, absent attendu       : %s  « %s »'
                % (verdict(not holds(core, text), 'absent', 'PRÉSENT'), text))
        for text in arguments.interface_contient:
            say('   interface, présent attendu : %s  « %s »'
                % (verdict(holds(interface, text), 'présent', 'ABSENT'), text))
        if arguments.programme_contient:
            program = (delivered / PROGRAM).read_bytes()
            for text in arguments.programme_contient:
                say('   programme, présent attendu : %s  « %s »'
                    % (verdict(holds(program, text), 'présent', 'ABSENT'), text))
        say('')

    say('Résultat : ' + ('toutes les comparaisons tiennent.' if not failures
                         else '%d comparaison(s) ne tiennent pas.' % len(failures)))
    text = '\n'.join(out) + '\n'
    if arguments.ecrire:
        with open(str(target), 'x', encoding='utf-8') as file:
            file.write(text)
    sys.stdout.write(text)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
