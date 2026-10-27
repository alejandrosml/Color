#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check the sources of the libraries kept beside the Rust core of Color.

  check-vendored-sources.py CORE

CORE is the folder of the core (it holds Cargo.toml, Cargo.lock and vendor/).
Every library named in Cargo.lock must be in vendor/, whole and unchanged:
each of its files is compared with the SHA-256 that `cargo vendor` wrote
beside it, and the archive checksum of the library with the one of the lock
file. cargo makes the same comparison when it builds; this says the same
thing earlier, in plain words, and names what is missing — a copy that lost
its hidden files, for instance.

Reads only. Exit code 0 when everything is there. Written for the Python
that a Mac may have: 3.8 or later.
"""
from pathlib import Path
import hashlib
import json
import re
import sys


def sha256(path):
    digest = hashlib.sha256()
    with open(str(path), 'rb') as file:
        for block in iter(lambda: file.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def locked_packages(lock_text):
    """(name, version, checksum) of every package the lock takes from a registry."""
    packages = []
    for block in lock_text.split('[[package]]')[1:]:
        fields = dict(re.findall(r'^(\w+) = "([^"]*)"$', block, re.M))
        if fields.get('source', '').startswith('registry+'):
            packages.append((fields.get('name'), fields.get('version'), fields.get('checksum')))
    return packages


def check(core):
    """(problems, facts) for the folder of the core."""
    problems = []
    vendor = core / 'vendor'
    for needed in ('Cargo.toml', 'Cargo.lock', '.cargo/config.toml'):
        if not (core / needed).is_file():
            problems.append('fichier absent : ' + needed)
    if not vendor.is_dir():
        problems.append('dossier absent : vendor')
    if problems:
        return problems, {}
    # What makes cargo take the libraries in vendor/ and nowhere else.
    settings = re.sub(r'#[^\n]*', '', (core / '.cargo/config.toml').read_text(encoding='utf-8'))
    for wanted, pattern in (
            ('replace-with = "vendored-sources"', r'replace-with\s*=\s*"vendored-sources"'),
            ('directory = "vendor"', r'\[source\.vendored-sources\][^\[]*directory\s*=\s*"vendor"'),
            ('offline = true', r'\[net\][^\[]*offline\s*=\s*true')):
        if not re.search(pattern, settings):
            problems.append('.cargo/config.toml ne dit plus « ' + wanted + ' »')
    crates = {}
    files = 0
    for folder in sorted(path for path in vendor.iterdir() if path.is_dir()):
        # A folder that holds no library — cargo does not look at it either.
        if not (folder / 'Cargo.toml').is_file() and not (folder / '.cargo-checksum.json').is_file():
            continue
        try:
            record = json.loads((folder / '.cargo-checksum.json').read_text(encoding='utf-8'))
            listed, package = record['files'], record['package']
        except (OSError, ValueError, KeyError, TypeError):
            problems.append('vendor/' + folder.name + ' : sa liste de contrôle (.cargo-checksum.json) '
                            'est absente ou illisible')
            continue
        crates[package] = folder.name
        for name, digest in sorted(listed.items()):
            path = folder / name
            files += 1
            if not path.is_file():
                problems.append('fichier absent : vendor/' + folder.name + '/' + name)
            elif sha256(path) != digest:
                problems.append('fichier changé : vendor/' + folder.name + '/' + name)
    locked = locked_packages((core / 'Cargo.lock').read_text(encoding='utf-8'))
    for name, version, checksum in locked:
        if checksum not in crates:
            problems.append('bibliothèque absente de vendor/ ou d’une autre version : %s %s' % (name, version))
    wanted = set(checksum for _, _, checksum in locked)
    for package, folder in sorted(crates.items(), key=lambda item: item[1]):
        if package not in wanted:
            problems.append('vendor/' + folder + ' n’est pas nommée par Cargo.lock')
    return problems, {'crates': len(crates), 'files': files, 'locked': len(locked)}


def main(arguments):
    if len(arguments) != 2:
        print(__doc__)
        return 2
    core = Path(arguments[1]).resolve()
    problems, facts = check(core)
    if problems:
        print('Les sources des bibliothèques du cœur ne sont pas complètes dans ' + str(core) + ' :')
        for problem in problems[:40]:
            print('  - ' + problem)
        if len(problems) > 40:
            print('  … et %d autres.' % (len(problems) - 40))
        print('Dépose de nouveau les sources depuis leur archive, sans passer par une copie qui retire')
        print('les fichiers dont le nom commence par un point.')
        return 1
    print('%(crates)d bibliothèques, %(files)d fichiers contrôlés ; les %(locked)d bibliothèques de Cargo.lock '
          'sont là, entières.' % facts)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
