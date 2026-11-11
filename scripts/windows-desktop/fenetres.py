#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""What the recipes of Windows ask of Windows directly, through ctypes alone:
the windows of a program, a passive picture of the screen, a message to a
window, the size of a window. Used by recette.py and essai-publie.py."""
from pathlib import Path
import ctypes
import ctypes.wintypes as wt
import struct
import subprocess
import zlib

user32 = ctypes.WinDLL('user32', use_last_error=True)
gdi32 = ctypes.WinDLL('gdi32', use_last_error=True)
try:
    ctypes.WinDLL('shcore').SetProcessDpiAwareness(2)
except OSError:
    pass
EnumWindowsProc = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
user32.EnumWindows.argtypes = [EnumWindowsProc, wt.LPARAM]
user32.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
user32.IsWindowVisible.argtypes = [wt.HWND]
user32.IsWindow.argtypes = [wt.HWND]
user32.IsWindowEnabled.argtypes = [wt.HWND]
user32.GetWindow.argtypes = [wt.HWND, wt.UINT]
user32.GetWindow.restype = wt.HWND
user32.GetClassNameW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
user32.GetWindowTextW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
user32.PostMessageW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]
user32.GetClientRect.argtypes = [wt.HWND, ctypes.POINTER(wt.RECT)]
user32.GetWindowRect.argtypes = [wt.HWND, ctypes.POINTER(wt.RECT)]
user32.SetWindowPos.argtypes = [wt.HWND, wt.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.UINT]
user32.GetSystemMetrics.argtypes = [ctypes.c_int]
user32.GetDC.argtypes = [wt.HWND]
user32.GetDC.restype = wt.HDC
user32.ReleaseDC.argtypes = [wt.HWND, wt.HDC]
gdi32.CreateCompatibleDC.argtypes = [wt.HDC]
gdi32.CreateCompatibleDC.restype = wt.HDC
gdi32.CreateCompatibleBitmap.argtypes = [wt.HDC, ctypes.c_int, ctypes.c_int]
gdi32.CreateCompatibleBitmap.restype = wt.HBITMAP
gdi32.SelectObject.argtypes = [wt.HDC, wt.HGDIOBJ]
gdi32.SelectObject.restype = wt.HGDIOBJ
gdi32.BitBlt.argtypes = [wt.HDC, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wt.HDC, ctypes.c_int,
                         ctypes.c_int, wt.DWORD]
gdi32.GetDIBits.argtypes = [wt.HDC, wt.HBITMAP, wt.UINT, wt.UINT, ctypes.c_void_p, ctypes.c_void_p, wt.UINT]
gdi32.DeleteObject.argtypes = [wt.HGDIOBJ]
gdi32.DeleteDC.argtypes = [wt.HDC]
GW_OWNER, WM_CLOSE, WM_COMMAND, IDCANCEL = 4, 0x0010, 0x0111, 2


def windows_of(pid):
    """The visible top-level windows of the process: handle, class, title, owner."""
    found = []

    def each(window, _):
        owner_pid = wt.DWORD()
        user32.GetWindowThreadProcessId(window, ctypes.byref(owner_pid))
        if owner_pid.value == pid and user32.IsWindowVisible(window):
            name = ctypes.create_unicode_buffer(128)
            user32.GetClassNameW(window, name, 128)
            title = ctypes.create_unicode_buffer(256)
            user32.GetWindowTextW(window, title, 256)
            found.append({'handle': window, 'class': name.value, 'title': title.value,
                          'owner': user32.GetWindow(window, GW_OWNER)})
        return True

    user32.EnumWindows(EnumWindowsProc(each), 0)
    return found


def visible_windows():
    """The title and the class of every visible window that has a title, whatever its program."""
    seen = []

    def each(window, _):
        if user32.IsWindowVisible(window):
            title = ctypes.create_unicode_buffer(256)
            user32.GetWindowTextW(window, title, 256)
            name = ctypes.create_unicode_buffer(128)
            user32.GetClassNameW(window, name, 128)
            if title.value:
                seen.append({'title': title.value, 'class': name.value})
        return True

    user32.EnumWindows(EnumWindowsProc(each), 0)
    return seen


def main_window(pid):
    for window in windows_of(pid):
        if not window['owner'] and window['class'] != '#32770':
            return window
    return None


def dialogs_of(pid):
    return [window for window in windows_of(pid) if window['class'] == '#32770']


def client_size(handle):
    rect = wt.RECT()
    user32.GetClientRect(handle, ctypes.byref(rect))
    return [rect.right - rect.left, rect.bottom - rect.top]


def resize_client(handle, width, height):
    """Asks for a window whose inside is width x height."""
    outside, inside = wt.RECT(), wt.RECT()
    user32.GetWindowRect(handle, ctypes.byref(outside))
    user32.GetClientRect(handle, ctypes.byref(inside))
    frame_wide = (outside.right - outside.left) - (inside.right - inside.left)
    frame_high = (outside.bottom - outside.top) - (inside.bottom - inside.top)
    SWP_NOMOVE, SWP_NOZORDER, SWP_NOACTIVATE = 0x2, 0x4, 0x10
    return bool(user32.SetWindowPos(handle, None, 0, 0, width + frame_wide, height + frame_high,
                                    SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))


def screen_pixels():
    """The whole screen as it is: width, height and its pixels, rows from the
    top, four bytes each (blue, green, red, unused). None when Windows refuses."""
    width, height = user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)
    screen = user32.GetDC(None)
    memory = gdi32.CreateCompatibleDC(screen)
    bitmap = gdi32.CreateCompatibleBitmap(screen, width, height)
    previous = gdi32.SelectObject(memory, bitmap)
    copied = gdi32.BitBlt(memory, 0, 0, width, height, screen, 0, 0, 0x00CC0020)
    gdi32.SelectObject(memory, previous)
    # A BITMAPINFO that Windows may write in: rows from the top, four bytes per pixel.
    header = ctypes.create_string_buffer(struct.pack('<IiiHHIIiiII', 40, width, -height, 1, 32, 0, 0, 0, 0, 0, 0)
                                         + bytes(12), 52)
    pixels = ctypes.create_string_buffer(width * height * 4)
    lines = gdi32.GetDIBits(memory, bitmap, 0, height, pixels, header, 0)
    gdi32.DeleteObject(bitmap)
    gdi32.DeleteDC(memory)
    user32.ReleaseDC(None, screen)
    if not copied or lines != height:
        return None
    return width, height, pixels.raw


def picture(path):
    """A passive picture of the whole screen, as a PNG file."""
    seen = screen_pixels()
    if seen is None:
        return False
    width, height, raw = seen
    rows = bytearray()
    for y in range(height):
        row = raw[y * width * 4:(y + 1) * width * 4]
        rgb = bytearray(width * 3)
        rgb[0::3], rgb[1::3], rgb[2::3] = row[2::4], row[1::4], row[0::4]
        rows += b'\x00' + rgb

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

    Path(path).write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(bytes(rows), 6)) + chunk(b'IEND', b''))
    return True


def changed_pixels(before, after, left, top, right, bottom):
    """How many pixels of the rectangle differ between two readings of the screen."""
    width = before[0]
    count = 0
    for y in range(top, bottom):
        a = before[2][(y * width + left) * 4:(y * width + right) * 4]
        b = after[2][(y * width + left) * 4:(y * width + right) * 4]
        if a != b:
            count += sum(1 for x in range(0, len(a), 4) if a[x:x + 3] != b[x:x + 3])
    return count


user32.ClientToScreen.argtypes = [wt.HWND, ctypes.POINTER(wt.POINT)]
user32.SetForegroundWindow.argtypes = [wt.HWND]
user32.SetCursorPos.argtypes = [ctypes.c_int, ctypes.c_int]
user32.mouse_event.argtypes = [wt.DWORD, wt.DWORD, wt.DWORD, wt.DWORD, ctypes.c_size_t]


def on_screen(handle, x, y):
    """Where the point (x, y) of the inside of a window is on the screen."""
    point = wt.POINT(x, y)
    user32.ClientToScreen(handle, ctypes.byref(point))
    return point.x, point.y


def pointer(kind, x, y):
    """One event of the real pointer of Windows at a point of the screen:
    'move', 'down' or 'up'. Only essai-publie.py sends such events."""
    user32.SetCursorPos(x, y)
    user32.mouse_event({'move': 0x0001, 'down': 0x0002, 'up': 0x0004}[kind], 0, 0, 0, 0)


def stop(process):
    """Asks the window to close, then ends the program."""
    window = main_window(process.pid)
    if window:
        user32.PostMessageW(window['handle'], WM_CLOSE, 0, 0)
        try:
            process.wait(timeout=4)
        except subprocess.TimeoutExpired:
            pass
    if process.poll() is None:
        subprocess.run(['taskkill', '/F', '/T', '/PID', str(process.pid)], capture_output=True)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass


user32.EnumDisplaySettingsW.argtypes = [wt.LPCWSTR, wt.DWORD, ctypes.c_void_p]
user32.ChangeDisplaySettingsW.argtypes = [ctypes.c_void_p, wt.DWORD]
user32.ChangeDisplaySettingsW.restype = ctypes.c_long


def enlarge_screen(sizes=((1920, 1080), (1600, 900), (1440, 900), (1280, 800))):
    """Asks Windows for a larger screen, the first of `sizes` that it accepts,
    when the screen is smaller: the machines of GitHub start at 1024 x 768,
    where the window of Color does not fit. Returns the size of the screen."""
    for width, height in sizes:
        if user32.GetSystemMetrics(0) >= width and user32.GetSystemMetrics(1) >= height:
            break
        # A DEVMODEW (220 bytes) holding the mode of now, then the size asked for.
        mode = ctypes.create_string_buffer(220)
        struct.pack_into('<H', mode, 68, 220)
        if not user32.EnumDisplaySettingsW(None, 0xFFFFFFFF, mode):
            break
        struct.pack_into('<I', mode, 72, 0x00080000 | 0x00100000)
        struct.pack_into('<II', mode, 172, width, height)
        if user32.ChangeDisplaySettingsW(mode, 0) == 0:
            break
    return [user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)]


def close_first_run_screens():
    """Ends what a Windows never used yet lays over the desktop — « Choose
    privacy settings for your device », and the Start menu that Windows 11
    opens at the first session: they would hide the window of Color in the
    pictures and take the clicks meant for it. Windows starts the Start menu
    again, closed. Returns the names of the programs ended."""
    ended = []
    for name in ['WWAHost.exe', 'UserOOBEBroker.exe', 'CloudExperienceHostBroker.exe',
                 'StartMenuExperienceHost.exe', 'SearchHost.exe']:
        done = subprocess.run(['taskkill', '/F', '/IM', name], capture_output=True, text=True, errors='replace')
        if done.returncode == 0:
            ended.append(name)
    return ended
