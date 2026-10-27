#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""The Rust that Color is built with: the one Homebrew provides.

  rust-reference.py --version         the release named in rust-reference.json
  rust-reference.py --verify RUSTC    is this compiler that release?
  rust-reference.py --homebrew        is that release still Homebrew's?

The owner's Mac compiles Color with the Rust of Homebrew, whatever its
release. Linux and Windows are built elsewhere, with rustup: they take the
release written in rust-reference.json, which is changed by hand when
Homebrew moves on, after --homebrew has said so. Nothing is installed,
updated or downloaded here, except the few kilobytes that --homebrew reads
from Homebrew's public index.

Exit codes: 0 yes, 1 no, 2 the question could not be answered.
"""
from pathlib import Path
import argparse
import json
import subprocess
import sys
import urllib.request

REFERENCE = Path(__file__).with_name('rust-reference.json')
HOMEBREW_INDEX = 'https://formulae.brew.sh/api/formula/rust.json'


def reference():
    data = json.loads(REFERENCE.read_text(encoding='utf-8'))
    version, commit = data['rust_version'], data['rust_commit']
    parts = version.split('.')
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise ValueError('rust_version is not a release number: ' + repr(version))
    if len(commit) != 40 or any(letter not in '0123456789abcdef' for letter in commit):
        raise ValueError('rust_commit is not a full commit hash')
    return data


def verify(rustc, data):
    """Why this compiler is not the reference, or None when it is."""
    try:
        said = subprocess.run([rustc, '--version', '--verbose'], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, universal_newlines=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as error:
        return 'it does not answer (' + str(error) + ')'
    lines = said.stdout.splitlines()
    if said.returncode != 0:
        return 'it fails: ' + ' '.join(lines)[:200]
    if 'release: ' + data['rust_version'] not in lines:
        return 'its release is not ' + data['rust_version'] + ': ' + (lines[0] if lines else 'no answer')
    if 'commit-hash: ' + data['rust_commit'] not in lines:
        return 'its commit is not ' + data['rust_commit']
    return None


def homebrew_stable(url=HOMEBREW_INDEX):
    with urllib.request.urlopen(url, timeout=30) as answer:
        return json.loads(answer.read().decode('utf-8'))['versions']['stable']


def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument('--version', action='store_true')
    choice.add_argument('--verify', metavar='RUSTC')
    choice.add_argument('--homebrew', action='store_true')
    options = parser.parse_args(arguments)
    try:
        data = reference()
    except (OSError, ValueError, KeyError) as error:
        print('rust-reference.json cannot be used: ' + str(error), file=sys.stderr)
        return 2
    if options.version:
        print(data['rust_version'])
        return 0
    if options.verify:
        problem = verify(options.verify, data)
        if problem is None:
            print(options.verify + ' is Rust ' + data['rust_version'] + ', the reference of Color.')
            return 0
        print(options.verify + ' is not the reference of Color: ' + problem + '.', file=sys.stderr)
        return 1
    try:
        stable = homebrew_stable()
    except (OSError, ValueError, KeyError) as error:
        print('Homebrew\'s index did not answer (' + str(error) + '): nothing is known.', file=sys.stderr)
        return 2
    if stable == data['rust_version']:
        print('Homebrew provides Rust ' + stable + ': the reference of Color is current.')
        return 0
    print('Homebrew now provides Rust ' + stable + '; the reference of Color is ' + data['rust_version']
          + ' (observed on ' + str(data.get('observed_on')) + '). Change rust-reference.json and '
          'scripts/windows-desktop/toolchain-lock.json, install that toolchain, then rebuild.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
