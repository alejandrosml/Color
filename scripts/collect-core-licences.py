#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Write the notices of the libraries kept beside the Rust core of Color.

  collect-core-licences.py [--check] [--table]

Reads prototypes/native-swift-rust/core/vendor/ and writes
prototypes/native-swift-rust/core/third-party-notices.txt: for each library
its name, its version, the licence Color takes it under and the text of that
licence, copied from the library itself. The core compiles that file in and
hands it to the interface, which shows it in « À propos » ; the packages
carry it too.

Most of these libraries let one choose between two or three licences. Color
is under the MIT licence: it takes each of them under the first licence of
ACCEPTED that the library offers — short permissive licences, which go with
it. A library that offers none of them stops this script: that is a decision
for a person, not for a script.

--check   writes nothing; exit code 1 when the file is not what would be written
--table   prints the table of docs/BIBLIOTHEQUES-TIERCES.md and writes nothing

Run it after every change of vendor/. Reads only, except for the one file it
writes. Python 3.8 or later.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'prototypes/native-swift-rust/core'
OUTPUT = CORE / 'third-party-notices.txt'
RULE = '-' * 80

# In the order Color prefers them, with the files a library may keep the text
# in. Apache-2.0 alone is not here: Color has always taken the shorter licence
# a library offers, and a library under Apache-2.0 alone would need its NOTICE
# file looked at by a person first.
ACCEPTED = [
    ('MIT', ['LICENSE-MIT', 'LICENSE-MIT.md', 'LICENSE-MIT.txt', 'LICENSE', 'LICENSE.md', 'LICENSE.txt']),
    ('BSD-2-Clause', ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'LICENSE-BSD']),
    ('BSD-3-Clause', ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'LICENSE-BSD']),
    ('Zlib', ['LICENSE-ZLIB', 'LICENSE-ZLIB.md', 'LICENSE']),
    ('Unlicense', ['UNLICENSE', 'LICENSE']),
]
# What each text must say to be the licence it is taken for.
MARKS = {
    'MIT': 'Permission is hereby granted, free of charge',
    'BSD-2-Clause': 'Redistribution and use in source and binary forms',
    'BSD-3-Clause': 'Redistribution and use in source and binary forms',
    'Zlib': 'This software is provided \'as-is\'',
    'Unlicense': 'This is free and unencumbered software',
}


def manifest_field(text, name):
    """A field of the [package] table of a Cargo.toml written by cargo."""
    package = text.split('[package]', 1)[1]
    package = re.split(r'^\[', package, maxsplit=1, flags=re.M)[0]
    found = re.search(r'^' + name + r'\s*=\s*"([^"]*)"', package, re.M)
    return found.group(1) if found else None


def libraries():
    """One record per library of vendor/, sorted by name."""
    records = []
    for folder in sorted(path for path in (CORE / 'vendor').iterdir() if path.is_dir()):
        manifest = (folder / 'Cargo.toml').read_text(encoding='utf-8')
        name, version = manifest_field(manifest, 'name'), manifest_field(manifest, 'version')
        offered = manifest_field(manifest, 'license')
        if not name or not version or not offered:
            raise SystemExit('vendor/' + folder.name + ' : nom, version ou licence illisible dans Cargo.toml.')
        choices = [part.strip() for part in re.split(r'\s+OR\s+|/', offered)]
        if any(' AND ' in part or ' WITH ' in part for part in choices):
            raise SystemExit('vendor/%s : licence composée (%s), à lire par une personne.' % (folder.name, offered))
        taken = next(((licence, files) for licence, files in ACCEPTED if licence in choices), None)
        if taken is None:
            raise SystemExit('vendor/%s : aucune des licences proposées (%s) n’est de celles que Color accepte (%s).'
                             % (folder.name, offered, ', '.join(licence for licence, _ in ACCEPTED)))
        licence, files = taken
        # Alone in its library, a licence keeps the plain names; among
        # several, only the file named after it is the right one.
        if len(choices) > 1:
            files = [file for file in files if not file.startswith('LICENSE.') and file != 'LICENSE']
        source = next((folder / file for file in files if (folder / file).is_file()), None)
        if source is None:
            raise SystemExit('vendor/%s : le texte de la licence %s est introuvable (%s).'
                             % (folder.name, licence, ', '.join(files)))
        text = source.read_text(encoding='utf-8').replace('\r\n', '\n')
        text = '\n'.join(line.rstrip() for line in text.split('\n')).strip('\n')
        if MARKS[licence] not in ' '.join(text.split()):
            raise SystemExit('vendor/%s : %s ne ressemble pas à la licence %s.' % (folder.name, source.name, licence))
        if RULE in text:
            raise SystemExit('vendor/%s : %s contient la ligne qui sépare les notices.' % (folder.name, source.name))
        records.append({'name': name, 'version': version, 'offered': offered, 'licence': licence,
                        'file': source.name, 'text': text,
                        'repository': manifest_field(manifest, 'repository') or ''})
    return records


def notices(records):
    """The file: entries as in the NOTICES of Flutter, which the interface reads the same way."""
    entries = []
    for record in records:
        choice = ('licence %(licence)s' if record['offered'] == record['licence']
                  else 'licence %(licence)s, choisie parmi : %(offered)s') % record
        entries.append('%s\n\n%s %s — %s.\n\n%s\n' % (record['name'], record['name'], record['version'],
                                                    choice, record['text']))
    return ('\n' + RULE + '\n').join(entries)


def table(records):
    lines = ['| Bibliothèque | Version | Licences proposées | Licence retenue | Texte repris de |',
             '|---|---|---|---|---|']
    for record in records:
        lines.append('| `%(name)s` | %(version)s | %(offered)s | %(licence)s | `vendor/%(name)s/%(file)s` |' % record)
    return '\n'.join(lines)


def main(arguments):
    options = set(arguments[1:])
    if options - {'--check', '--table'}:
        print(__doc__)
        return 2
    records = libraries()
    if '--table' in options:
        print(table(records))
        return 0
    text = notices(records)
    if '--check' in options:
        current = OUTPUT.read_text(encoding='utf-8') if OUTPUT.is_file() else None
        if current != text:
            print(str(OUTPUT) + ' n’est pas à jour : relance collect-core-licences.py.')
            return 1
        print('%d bibliothèques : %s est à jour.' % (len(records), OUTPUT.name))
        return 0
    OUTPUT.write_text(text, encoding='utf-8')
    print('%d bibliothèques, %d octets : %s' % (len(records), len(text.encode('utf-8')), OUTPUT))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
