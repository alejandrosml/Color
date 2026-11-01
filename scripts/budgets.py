#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Les budgets de Color (Q-03 de la rétrospective d'octobre 2026) : ce
qu'une version ne dépasse pas sans qu'on l'ait décidé. Les références sont
dans budgets.json, à côté de ce fichier ; une mesure au-delà de sa
référence, marge comprise, arrête ce qui l'a faite. Une référence se change
dans budgets.json, avec la mesure qui la justifie, jamais en silence.

Ce que les recettes mesurent et donnent à vérifier :

  python3 budgets.py verifier tailles core-linux-x86_64 1116120
  python3 budgets.py aab Color.aab          # chaque ABI, et sa taille

Une mesure sans référence encore (null) est dite, pas refusée : la première
mesure d'une recette devient la référence quand on l'écrit dans le fichier.
Une référence prise sur un rendu (« rendu », le début du nom que glxinfo
donne au moteur de rendu) ne vaut que pour lui : le temps d'une image dépend
de la machine qui la dessine. Ailleurs, la mesure est dite, pas jugée.
"""
import json
import sys
import zipfile
from pathlib import Path

BUDGETS = Path(__file__).with_name('budgets.json')


def load(path=BUDGETS):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def check(kind, name, measured, budgets=None, renderer=None):
    """(bon, phrase) : `measured` reste-t-il dans la référence de `name`,
    dans la famille `kind` (tailles, images, demarrage), marge comprise ?
    Un nom inconnu, sans référence, ou dont la référence fut prise sur un
    autre rendu que `renderer`, n'arrête rien."""
    budgets = load() if budgets is None else budgets
    family = budgets.get(kind)
    if family is None:
        raise KeyError('famille de budgets inconnue : ' + kind)
    entry = family['entrees'].get(name)
    unit = family.get('unite', '')
    if entry is None or entry.get('reference') is None:
        return True, f'{name} : {measured} {unit}, pas encore de référence'
    expected = entry.get('rendu')
    if expected is not None and not (renderer or '').startswith(expected):
        return True, (f'{name} : {measured} {unit}, référence prise sur un autre rendu'
                      f' ({expected}), pas jugée ici')
    reference = entry['reference']
    tolerance = entry.get('marge', family['marge'])
    limit = reference * (1 + tolerance)
    change = (measured - reference) / reference if reference else 0.0
    sentence = (f'{name} : {measured} {unit}, référence {reference} {unit} '
                f'({change:+.1%}, marge {tolerance:.0%})')
    if measured > limit:
        return False, sentence + ' — AU-DELÀ DU BUDGET'
    return True, sentence


def aab_sizes(aab):
    """La taille compressée, dans l'App Bundle, de ce qu'un appareil de
    chaque ABI reçoit : ce qui est commun à toutes, plus ses bibliothèques.
    {abi: octets}."""
    common = 0
    libraries = {}
    with zipfile.ZipFile(aab) as bundle:
        for entry in bundle.infolist():
            if entry.is_dir():
                continue
            parts = entry.filename.split('/')
            if len(parts) >= 4 and parts[1] == 'lib':
                libraries[parts[2]] = libraries.get(parts[2], 0) + entry.compress_size
            elif not entry.filename.startswith(('META-INF/', 'BUNDLE-METADATA/')):
                common += entry.compress_size
    return {abi: common + size for abi, size in sorted(libraries.items())}


def aab_problems(aab, budgets=None):
    """What an App Bundle lacks: an ABI that the budgets name
    (android-aab-<abi>), or the core in the libraries of one of its ABIs. A
    budget bounds growth only: a bundle that lost a part is smaller, not
    better. A list of sentences, empty when nothing is missing."""
    budgets = load() if budgets is None else budgets
    expected = {name[len('android-aab-'):] for name in budgets['tailles']['entrees']
                if name.startswith('android-aab-')}
    with zipfile.ZipFile(aab) as bundle:
        names = bundle.namelist()
    present = {parts[2] for parts in (name.split('/') for name in names)
               if len(parts) >= 4 and parts[1] == 'lib'}
    problems = [f'ABI {abi} absente de l\'App Bundle' for abi in sorted(expected - present)]
    for abi in sorted(present):
        if not any(name.endswith(f'/lib/{abi}/libedupaint_core.so') for name in names):
            problems.append(f'ABI {abi} sans libedupaint_core.so')
    return problems


def main(arguments):
    if len(arguments) == 4 and arguments[0] == 'verifier':
        # A count of bytes stays a whole number in what is said.
        given = arguments[3]
        measured = int(given) if given.isdigit() else float(given)
        ok, sentence = check(arguments[1], arguments[2], measured)
        print(sentence)
        return 0 if ok else 1
    if len(arguments) == 2 and arguments[0] == 'aab':
        problems = aab_problems(arguments[1])
        for problem in problems:
            print(problem + ' — REFUSÉ')
        failed = bool(problems)
        for abi, size in aab_sizes(arguments[1]).items():
            ok, sentence = check('tailles', 'android-aab-' + abi, size)
            print(sentence)
            failed |= not ok
        return 1 if failed else 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
