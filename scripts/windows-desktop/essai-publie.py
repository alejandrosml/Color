#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Tries the published Color on the Windows machine that runs this script, as
a parent would get it: downloaded from the « Release » of GitHub, unzipped,
started, and used with the real pointer of Windows.

  essai-publie.py REPORT --architecture x64|arm64 --depot OWNER/REPO
                  --etiquette TAG

What it does, each step pictured in REPORT:
  1. downloads SHA256SUMS.txt and the archive of this processor from the
     release, and compares the fingerprint;
  2. unzips it in the Downloads folder and marks color.exe as downloaded from
     the Internet, as a browser and the Explorer would; starts it through the
     shell, to see what Windows says of a program it does not know;
  3. starts it for good; draws a trait on the sheet with the pointer;
  4. clicks « Imprimer »: the print dialog of Windows opens over the window;
     closed by its button « Annuler », then opened again and confirmed, on a
     printer made for the trial that writes a PDF file;
  5. asks the window to close, ends the program and starts it again: it must
     offer the drawing left.

Unlike recette.py, this script sends real pointer events: it is the only one
that does. Nothing reaches a printer of paper. essai.json says what was seen.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
import zipfile

from fenetres import (IDCANCEL, WM_CLOSE, WM_COMMAND, changed_pixels, client_size, close_first_run_screens, dialogs_of,
                      enlarge_screen, keep_on_top, main_window, on_screen, picture, pointer, screen_pixels, stop,
                      user32, visible_windows)

parser = argparse.ArgumentParser()
parser.add_argument('report')
parser.add_argument('--architecture', required=True, choices=['x64', 'arm64'])
parser.add_argument('--depot', required=True)
parser.add_argument('--etiquette', required=True)
arguments = parser.parse_args()
report = Path(arguments.report).resolve()
if report.exists():
    sys.exit('The report folder already exists: choose a new one.')
report.mkdir(parents=True)
here = Path(__file__).resolve().parent
record = {'scope': 'The published Color, downloaded from its release and used with the real pointer of Windows.',
          'release': f'https://github.com/{arguments.depot}/releases/tag/{arguments.etiquette}',
          'architecture': arguments.architecture, 'pictures': [], 'problems': []}
IDOK = 1


def shot(name):
    if picture(report / f'{name}.png'):
        record['pictures'].append(f'{name}.png')


def color_processes():
    listing = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq color.exe', '/FO', 'CSV', '/NH'], capture_output=True,
                             text=True, errors='replace').stdout
    return [int(line.split('","')[1]) for line in listing.splitlines() if line.lower().startswith('"color.exe"')]


def end_all():
    subprocess.run(['taskkill', '/F', '/IM', 'color.exe'], capture_output=True)
    time.sleep(1)


def start(program):
    process = subprocess.Popen([str(program)], cwd=program.parent)
    began = time.monotonic()
    window = None
    while time.monotonic() - began < 60 and process.poll() is None and window is None:
        time.sleep(.25)
        window = main_window(process.pid)
    return process, window, round(time.monotonic() - began, 1)


def click(window, x, y):
    at = on_screen(window['handle'], x, y)
    pointer('move', *at)
    time.sleep(.15)
    pointer('down', *at)
    time.sleep(.08)
    pointer('up', *at)


def await_dialog(pid, seconds=25):
    limit = time.monotonic() + seconds
    while time.monotonic() < limit:
        found = dialogs_of(pid)
        if found:
            return found[0]
        time.sleep(.2)
    return None


def write():
    (report / 'essai.json').write_text(json.dumps(record, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


try:
    record['desktop'] = {'first_run_screens_ended': close_first_run_screens(), 'screen': enlarge_screen()}
    time.sleep(2)
    shot('00-bureau')

    # ---- 1. Downloaded, as its page offers it. ----------------------------
    base = f'https://github.com/{arguments.depot}/releases/download/{arguments.etiquette}/'
    sums = urllib.request.urlopen(base + 'SHA256SUMS.txt', timeout=120).read().decode('utf-8')
    wanted = [line.split() for line in sums.splitlines()
              if line.strip().endswith(f'-windows-{arguments.architecture}.zip')]
    if len(wanted) != 1:
        raise RuntimeError('SHA256SUMS.txt names no single archive for this processor: ' + sums)
    fingerprint, name = wanted[0]
    downloads = Path(os.environ['USERPROFILE']) / 'Downloads'
    downloads.mkdir(exist_ok=True)
    archive = downloads / name
    began = time.monotonic()
    with urllib.request.urlopen(base + name, timeout=600) as answer, archive.open('wb') as out:
        shutil.copyfileobj(answer, out)
    with archive.open('rb') as stream:
        found = hashlib.file_digest(stream, 'sha256').hexdigest()
    record['download'] = {'file': name, 'bytes': archive.stat().st_size, 'seconds': round(time.monotonic() - began, 1),
                          'sha256': found, 'as_published': found == fingerprint}
    if found != fingerprint:
        raise RuntimeError('the archive is not the one that was published')

    # ---- 2. Unzipped, and what Windows says of an unknown program. --------
    with zipfile.ZipFile(archive) as packed:
        packed.extractall(downloads)
    folder = downloads / name[:-len('.zip')]
    program = folder / 'color.exe'
    record['unzipped'] = {'folder': str(folder), 'files': sum(1 for path in folder.rglob('*') if path.is_file()),
                          'notice': (folder / 'LISEZMOI.txt').is_file()}
    # The mark that a browser leaves on a download, and the Explorer on what
    # it unzips from one: with it, Windows checks the program before starting it.
    with open(str(program) + ':Zone.Identifier', 'w', encoding='ascii') as mark:
        mark.write('[ZoneTransfer]\r\nZoneId=3\r\nHostUrl=' + base + name + '\r\n')
    before = {window['title'] for window in visible_windows()}
    # Through the shell, as a double click does — from a program apart: the
    # shell does not come back while its warning waits for an answer.
    shell = subprocess.Popen(['cmd', '/c', 'start', '', str(program)])
    time.sleep(15)
    shot('01-premier-lancement-fichier-marque')
    running = color_processes()
    record['first_start_with_the_mark_of_the_internet'] = {
        'color_started': bool(running),
        'the_shell_was_still_waiting': shell.poll() is None,
        'new_windows': [window for window in visible_windows() if window['title'] not in before],
        'note': 'What Windows shows here depends on the machine: the notice of Color says what a home '
                'computer shows (« Windows a protégé votre ordinateur »).'}
    subprocess.run(['taskkill', '/F', '/T', '/PID', str(shell.pid)], capture_output=True)
    end_all()
    subprocess.run(['taskkill', '/F', '/IM', 'smartscreen.exe'], capture_output=True)
    os.remove(str(program) + ':Zone.Identifier')

    # ---- 3. Started for good; a trait drawn with the pointer. -------------
    process, window, appeared = start(program)
    if window is None:
        raise RuntimeError('color.exe showed no window in a minute')
    time.sleep(6)
    keep_on_top(window['handle'])
    user32.SetForegroundWindow(window['handle'])
    time.sleep(1)
    wide, high = client_size(window['handle'])
    record['started'] = {'window_after_seconds': appeared, 'title': window['title'], 'class': window['class'],
                         'inside': [wide, high], 'screen': [user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)]}
    shot('02-atelier')
    seen_before = screen_pixels()
    # A zigzag in the middle of the sheet, with the brush that Color starts with.
    path = [(int(wide * (.45 + .03 * step)), int(high * (.50 + (.07 if step % 2 else -.07)))) for step in range(9)]
    first = on_screen(window['handle'], *path[0])
    pointer('move', *first)
    time.sleep(.3)
    pointer('down', *first)
    for (from_x, from_y), (to_x, to_y) in zip(path, path[1:]):
        for part in range(1, 9):
            at = on_screen(window['handle'], from_x + (to_x - from_x) * part // 8, from_y + (to_y - from_y) * part // 8)
            pointer('move', *at)
            time.sleep(.012)
    pointer('up', *on_screen(window['handle'], *path[-1]))
    time.sleep(1.5)
    shot('03-un-trait-au-pointeur')
    seen_after = screen_pixels()
    left, top = on_screen(window['handle'], int(wide * .40), int(high * .38))
    right, bottom = on_screen(window['handle'], int(wide * .75), int(high * .62))
    changed = changed_pixels(seen_before, seen_after, left, top, right, bottom) if seen_before and seen_after else None
    record['trait'] = {'pixels_changed_on_the_sheet': changed, 'seen': bool(changed and changed > 150)}
    if not record['trait']['seen']:
        record['problems'].append('no trait appeared under the pointer')

    # ---- 4. « Imprimer »: the dialog of Windows, cancelled, then confirmed.
    port = report / 'imprimante' / 'page.pdf'
    port.parent.mkdir()
    printer = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                              str(here / 'imprimante-d-essai.ps1'), str(port)], capture_output=True, text=True,
                             errors='replace')
    (report / 'imprimante.log').write_text(printer.stdout + printer.stderr, encoding='utf-8')
    record['printing'] = {'trial_printer_made': printer.returncode == 0}
    if printer.returncode == 0:
        user32.SetForegroundWindow(window['handle'])
        # The last button of the header, at the top right: « Imprimer ».
        click(window, wide - 50, 58)
        dialog = await_dialog(process.pid)
        if dialog is None:
            shot('04-pas-de-fenetre-d-impression')
            record['problems'].append('the click on « Imprimer » opened no print dialog')
        else:
            time.sleep(3)
            shot('04-fenetre-d-impression')
            record['printing']['dialog'] = {
                'title': dialog['title'], 'owned_by_the_window_of_color': dialog['owner'] == window['handle'],
                'window_of_color_disabled_meanwhile': not user32.IsWindowEnabled(window['handle'])}
            user32.PostMessageW(dialog['handle'], WM_COMMAND, IDCANCEL, 0)
            time.sleep(3)
            record['printing']['cancelled_leaves_no_page'] = not user32.IsWindow(dialog['handle']) and not port.exists()
            shot('05-apres-annuler')
            user32.SetForegroundWindow(window['handle'])
            click(window, wide - 50, 58)
            dialog = await_dialog(process.pid)
            if dialog is None:
                record['problems'].append('the second click on « Imprimer » opened no print dialog')
            else:
                time.sleep(3)
                user32.PostMessageW(dialog['handle'], WM_COMMAND, IDOK, 0)
                limit, last, steady = time.monotonic() + 90, 0, 0
                while time.monotonic() < limit and steady < 4:
                    time.sleep(.5)
                    size = port.stat().st_size if port.exists() else 0
                    steady = steady + 1 if size and size == last else 0
                    last = size
                time.sleep(1)
                shot('06-apres-imprimer')
                if port.exists() and port.read_bytes().startswith(b'%PDF'):
                    shutil.copy2(port, report / 'page-imprimee.pdf')
                    record['printing']['page'] = {'file': 'page-imprimee.pdf', 'bytes': port.stat().st_size}
                else:
                    record['problems'].append('confirmed in the dialog, but no PDF page was written')

    # ---- 5. Closed with a drawing left, started again. ---------------------
    user32.PostMessageW(window['handle'], WM_CLOSE, 0, 0)
    time.sleep(3)
    shot('07-fermeture-demandee')
    record['closing'] = {'still_running_three_seconds_after_the_request': process.poll() is None,
                         'windows': [{'title': w['title'], 'class': w['class']} for w in dialogs_of(process.pid)]}
    stop(process)
    end_all()
    process, window, appeared = start(program)
    if window:
        keep_on_top(window['handle'])
    time.sleep(8)
    shot('08-relance')
    record['started_again'] = {'window_after_seconds': appeared, 'running': process.poll() is None}
    stop(process)
    end_all()
    record['passed'] = (record['download']['as_published'] and record['trait']['seen']
                        and bool(record['printing'].get('page')) and not record['problems'])
except Exception as error:  # said, not lost
    import traceback
    record['passed'] = False
    record['problems'].append(''.join(traceback.format_exception(error))[-1500:])
    shot('99-arret')
    end_all()
write()
print(json.dumps(record, indent=2, ensure_ascii=False))
sys.exit(0 if record['passed'] else 1)
