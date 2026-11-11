// SPDX-License-Identifier: MIT
//! « Imprimer » on Windows: the print dialog of the system and one image on
//! one page, asked of a thread of the core.
//!
//! Elsewhere the application prints itself (Swift on Apple systems, GTK on
//! Linux): the two functions exist everywhere and say so.
//!
//! The dialog of Windows runs its own loop of messages. It opens on a thread
//! of its own, over the window of the program, which Windows disables until
//! the dialog is closed: the program goes on drawing its frames meanwhile and
//! asks now and then what became of the request (`ep_print_result`). Nothing
//! is ever printed unless the person confirms it in that dialog.

// Away from 64-bit Windows only the two answers « not here » are used.
#![cfg_attr(not(all(windows, target_pointer_width = "64")), allow(dead_code))]

use std::ffi::{c_char, CStr};
use std::sync::Mutex;

/// What `ep_print_start` answers.
const STARTED: i32 = 0;
const BUSY: i32 = 1;
const INVALID: i32 = 2;
#[cfg_attr(all(windows, target_pointer_width = "64"), allow(dead_code))]
const NO_PRINTING_HERE: i32 = 3;

/// What `ep_print_result` answers.
const NOTHING_ASKED: i32 = 0;
const RUNNING: i32 = 1;
#[cfg(any(all(windows, target_pointer_width = "64"), test))]
const SENT: i32 = 2;
#[cfg(any(all(windows, target_pointer_width = "64"), test))]
const CANCELLED: i32 = 3;
#[cfg(any(all(windows, target_pointer_width = "64"), test))]
const NO_PRINTER: i32 = 4;
#[cfg(any(all(windows, target_pointer_width = "64"), test))]
const FAILED: i32 = 5;

/// The same bound as the picture that the application renders for a page
/// (lib/print_render.dart), with room to spare.
const MAXIMUM_DIMENSION: u32 = 8192;

/// Where the one request that can run at a time stands.
enum State {
    Idle,
    Running,
    /// The outcome and, for a failure, the error code of Windows.
    Done(i32, u32),
}

static STATE: Mutex<State> = Mutex::new(State::Idle);

fn state() -> std::sync::MutexGuard<'static, State> {
    // A thread that stopped while holding it left a state that still reads.
    STATE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Opens the print dialog of Windows for one image on one page, over the
/// window of the program, and returns at once; `ep_print_result` then says
/// what became of it.
///
/// `rgba` holds `width` x `height` opaque pixels of four bytes, rows from the
/// top: they are copied before the call returns. `job_name` is what the print
/// queue of Windows shows.
///
/// The page is proposed landscape for a wide image, portrait otherwise, also
/// when the person chooses another printer in the dialog. The image is as
/// large as the page allows, never distorted, in the middle of the paper.
/// Where Windows knows no printer, no dialog opens.
///
/// Returns 0 started, 1 a request is still running, 2 NULL, a dimension of
/// zero or above 8192, or a name that is not UTF-8, 3 no printing by the core
/// on this system (every system but 64-bit Windows).
///
/// # Safety
/// Non-null `rgba` must be readable for `width * height * 4` bytes; non-null
/// `job_name` must be a NUL-terminated string. Both live for the call.
#[no_mangle]
pub unsafe extern "C" fn ep_print_start(
    rgba: *const u8,
    width: u32,
    height: u32,
    job_name: *const c_char,
) -> i32 {
    if rgba.is_null()
        || job_name.is_null()
        || width < 1
        || height < 1
        || width > MAXIMUM_DIMENSION
        || height > MAXIMUM_DIMENSION
    {
        return INVALID;
    }
    let Ok(name) = unsafe { CStr::from_ptr(job_name) }.to_str() else {
        return INVALID;
    };
    start(rgba, width, height, name)
}

#[cfg(not(all(windows, target_pointer_width = "64")))]
fn start(_rgba: *const u8, _width: u32, _height: u32, _name: &str) -> i32 {
    NO_PRINTING_HERE
}

#[cfg(all(windows, target_pointer_width = "64"))]
fn start(rgba: *const u8, width: u32, height: u32, name: &str) -> i32 {
    let mut state = state();
    if matches!(*state, State::Running) {
        return BUSY;
    }
    let length = width as usize * height as usize * 4;
    // SAFETY: the caller of ep_print_start answers for these bytes.
    let pixels = unsafe { std::slice::from_raw_parts(rgba, length) }.to_vec();
    let name: Vec<u16> = name.encode_utf16().chain(std::iter::once(0)).collect();
    *state = State::Running;
    drop(state);
    let spawned = std::thread::Builder::new()
        .name("color-print".to_string())
        .spawn(move || {
            let (outcome, code) = system::print_image(&pixels, width as i32, height as i32, &name);
            *self::state() = State::Done(outcome, code);
        });
    if spawned.is_err() {
        const ERROR_NOT_ENOUGH_MEMORY: u32 = 8;
        *self::state() = State::Done(FAILED, ERROR_NOT_ENOUGH_MEMORY);
    }
    STARTED
}

/// What became of the request of `ep_print_start`: 0 nothing was asked, 1 the
/// dialog is open or the page is on its way to the spooler, 2 the person
/// confirmed and the page was handed to Windows, 3 the person closed the
/// dialog without printing (or gave up naming the file of a printer that
/// writes one), 4 Windows knows no printer, 5 Windows refused — non-null
/// `error_code` then receives its code. An answer from 2 to 5 is given once:
/// the next call answers 0, and a new request can start.
///
/// # Safety
/// Non-null `error_code` must be writable.
#[no_mangle]
pub unsafe extern "C" fn ep_print_result(error_code: *mut u32) -> i32 {
    let mut state = state();
    match *state {
        State::Idle => NOTHING_ASKED,
        State::Running => RUNNING,
        State::Done(outcome, code) => {
            if !error_code.is_null() {
                unsafe { *error_code = code };
            }
            *state = State::Idle;
            outcome
        }
    }
}

/// The printable area of a page as a printer describes it, in its own dots.
#[cfg(any(all(windows, target_pointer_width = "64"), test))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct PageGeometry {
    /// The area that the printer can reach, where drawing starts at (0, 0).
    area_width: i32,
    area_height: i32,
    /// The whole sheet of paper, and where the area starts on it.
    paper_width: i32,
    paper_height: i32,
    offset_x: i32,
    offset_y: i32,
    /// Dots per inch across and down: they may differ.
    dpi_x: i32,
    dpi_y: i32,
}

/// A rectangle of the page, in the dots of the printer.
#[cfg(any(all(windows, target_pointer_width = "64"), test))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Place {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
}

/// Where an image of `width` x `height` pixels goes on `page`: as large as
/// the page allows, never distorted, in the middle of the paper. What the
/// printer cannot reach is rarely the same on each side: the image keeps to
/// the larger margin on both sides.
#[cfg(any(all(windows, target_pointer_width = "64"), test))]
// Not `clamp`, which stops the program for a room below one dot.
#[allow(clippy::manual_clamp)]
fn place_on_page(width: i32, height: i32, page: &PageGeometry) -> Place {
    let mut origin_x = 0;
    let mut origin_y = 0;
    let mut room_width = page.area_width;
    let mut room_height = page.area_height;
    let left = page.offset_x;
    let top = page.offset_y;
    let right = page.paper_width - page.offset_x - page.area_width;
    let bottom = page.paper_height - page.offset_y - page.area_height;
    // A driver that describes its paper coherently: keep to the larger margin
    // on both sides. Otherwise the middle of the printable area will do.
    if left >= 0 && top >= 0 && right >= 0 && bottom >= 0 {
        let across = (left - right).abs();
        let down = (top - bottom).abs();
        if across < room_width && down < room_height {
            origin_x = left.max(right) - left;
            origin_y = top.max(bottom) - top;
            room_width -= across;
            room_height -= down;
        }
    }
    // Compared in inches: the dots of a printer are not always square.
    let room_wide = f64::from(room_width) / f64::from(page.dpi_x);
    let room_high = f64::from(room_height) / f64::from(page.dpi_y);
    let shape = f64::from(width) / f64::from(height);
    let mut placed_width = room_width;
    let mut placed_height = room_height;
    if room_wide / room_high > shape {
        placed_width = (room_high * shape * f64::from(page.dpi_x)).round() as i32;
    } else {
        placed_height = (room_wide / shape * f64::from(page.dpi_y)).round() as i32;
    }
    let placed_width = placed_width.max(1).min(room_width);
    let placed_height = placed_height.max(1).min(room_height);
    let left = origin_x + (room_width - placed_width) / 2;
    let top = origin_y + (room_height - placed_height) / 2;
    Place {
        left,
        top,
        right: left + placed_width,
        bottom: top + placed_height,
    }
}

/// The pixels as GDI prints them on every driver: rows from the bottom,
/// three bytes per pixel (blue, green, red), each row padded to four bytes.
/// `rgba` holds `width` x `height` pixels of four bytes, rows from the top.
#[cfg(any(all(windows, target_pointer_width = "64"), test))]
fn bottom_up_bgr(rgba: &[u8], width: usize, height: usize) -> Vec<u8> {
    let stride = (width * 3 + 3) & !3;
    let mut pixels = vec![0u8; stride * height];
    for y in 0..height {
        let from = &rgba[(height - 1 - y) * width * 4..][..width * 4];
        let to = &mut pixels[y * stride..][..width * 3];
        for x in 0..width {
            to[x * 3] = from[x * 4 + 2];
            to[x * 3 + 1] = from[x * 4 + 1];
            to[x * 3 + 2] = from[x * 4];
        }
    }
    pixels
}

/// The calls of Windows, written by hand as those of the sounds are: the
/// core takes no library for them.
#[cfg(all(windows, target_pointer_width = "64"))]
mod system {
    use super::{bottom_up_bgr, place_on_page, PageGeometry, CANCELLED, FAILED, NO_PRINTER, SENT};
    use std::ffi::c_void;
    use std::mem;
    use std::ptr;

    type Handle = *mut c_void;

    /// PRINTDLGW, as 64-bit Windows lays it out.
    #[repr(C)]
    struct PrintDialog {
        struct_size: u32,
        owner: Handle,
        dev_mode: Handle,
        dev_names: Handle,
        dc: Handle,
        flags: u32,
        from_page: u16,
        to_page: u16,
        min_page: u16,
        max_page: u16,
        copies: u16,
        instance: Handle,
        custom_data: isize,
        print_hook: Handle,
        setup_hook: Handle,
        print_template_name: *const u16,
        setup_template_name: *const u16,
        print_template: Handle,
        setup_template: Handle,
    }
    const _: () = assert!(mem::size_of::<PrintDialog>() == 120);

    /// The start of a DEVMODEW: the name of the device, which fields are
    /// set, and the orientation of the page. What follows is left alone.
    #[repr(C)]
    struct DeviceModeStart {
        device_name: [u16; 32],
        spec_version: u16,
        driver_version: u16,
        size: u16,
        driver_extra: u16,
        fields: u32,
        orientation: i16,
    }
    const _: () = assert!(mem::offset_of!(DeviceModeStart, fields) == 72);
    const _: () = assert!(mem::offset_of!(DeviceModeStart, orientation) == 76);

    /// DOCINFOW.
    #[repr(C)]
    struct DocumentInfo {
        size: i32,
        document_name: *const u16,
        output: *const u16,
        datatype: *const u16,
        kind: u32,
    }
    const _: () = assert!(mem::size_of::<DocumentInfo>() == 40);

    /// BITMAPINFOHEADER.
    #[repr(C)]
    struct BitmapHeader {
        size: u32,
        width: i32,
        height: i32,
        planes: u16,
        bit_count: u16,
        compression: u32,
        size_image: u32,
        x_pels_per_meter: i32,
        y_pels_per_meter: i32,
        colors_used: u32,
        colors_important: u32,
    }
    const _: () = assert!(mem::size_of::<BitmapHeader>() == 40);

    /// BITMAPINFO, with the one colour entry that its declaration holds.
    #[repr(C)]
    struct BitmapInfo {
        header: BitmapHeader,
        colors: [u32; 1],
    }

    #[link(name = "comdlg32")]
    extern "system" {
        fn PrintDlgW(dialog: *mut PrintDialog) -> i32;
        fn CommDlgExtendedError() -> u32;
    }

    #[link(name = "gdi32")]
    extern "system" {
        fn GetDeviceCaps(dc: Handle, index: i32) -> i32;
        fn StartDocW(dc: Handle, document: *const DocumentInfo) -> i32;
        fn StartPage(dc: Handle) -> i32;
        fn EndPage(dc: Handle) -> i32;
        fn EndDoc(dc: Handle) -> i32;
        fn AbortDoc(dc: Handle) -> i32;
        fn SetStretchBltMode(dc: Handle, mode: i32) -> i32;
        fn SetBrushOrgEx(dc: Handle, x: i32, y: i32, previous: *mut c_void) -> i32;
        #[allow(clippy::too_many_arguments)]
        fn StretchDIBits(
            dc: Handle,
            x: i32,
            y: i32,
            width: i32,
            height: i32,
            source_x: i32,
            source_y: i32,
            source_width: i32,
            source_height: i32,
            bits: *const c_void,
            info: *const BitmapInfo,
            usage: u32,
            operation: u32,
        ) -> i32;
        fn DeleteDC(dc: Handle) -> i32;
        fn ResetDCW(dc: Handle, mode: *const DeviceModeStart) -> Handle;
    }

    #[link(name = "winspool")]
    extern "system" {
        fn EnumPrintersW(
            flags: u32,
            name: *const u16,
            level: u32,
            buffer: *mut u8,
            size: u32,
            needed: *mut u32,
            returned: *mut u32,
        ) -> i32;
    }

    #[link(name = "kernel32")]
    extern "system" {
        fn GlobalLock(memory: Handle) -> *mut c_void;
        fn GlobalUnlock(memory: Handle) -> i32;
        fn GlobalFree(memory: Handle) -> Handle;
        fn GetLastError() -> u32;
        fn GetCurrentProcessId() -> u32;
    }

    #[link(name = "user32")]
    extern "system" {
        fn EnumWindows(each: unsafe extern "system" fn(Handle, isize) -> i32, with: isize) -> i32;
        fn GetWindowThreadProcessId(window: Handle, process: *mut u32) -> u32;
        fn IsWindowVisible(window: Handle) -> i32;
        fn GetWindow(window: Handle, relation: u32) -> Handle;
    }

    const PD_NOSELECTION: u32 = 0x0000_0004;
    const PD_NOPAGENUMS: u32 = 0x0000_0008;
    const PD_NOWARNING: u32 = 0x0000_0080;
    const PD_RETURNDC: u32 = 0x0000_0100;
    const PD_RETURNDEFAULT: u32 = 0x0000_0400;
    const PD_USEDEVMODECOPIESANDCOLLATE: u32 = 0x0004_0000;
    const PD_HIDEPRINTTOFILE: u32 = 0x0010_0000;
    const PDERR_NODEVICES: u32 = 0x1007;
    const PDERR_NODEFAULTPRN: u32 = 0x1008;
    const DM_ORIENTATION: u32 = 0x0000_0001;
    const DMORIENT_PORTRAIT: i16 = 1;
    const DMORIENT_LANDSCAPE: i16 = 2;
    const HORZRES: i32 = 8;
    const VERTRES: i32 = 10;
    const LOGPIXELSX: i32 = 88;
    const LOGPIXELSY: i32 = 90;
    const PHYSICALWIDTH: i32 = 110;
    const PHYSICALHEIGHT: i32 = 111;
    const PHYSICALOFFSETX: i32 = 112;
    const PHYSICALOFFSETY: i32 = 113;
    const HALFTONE: i32 = 4;
    const BI_RGB: u32 = 0;
    const DIB_RGB_COLORS: u32 = 0;
    const SRCCOPY: u32 = 0x00CC_0020;
    const PRINTER_ENUM_LOCAL: u32 = 0x0000_0002;
    const PRINTER_ENUM_CONNECTIONS: u32 = 0x0000_0004;
    const GW_OWNER: u32 = 4;
    const ERROR_INVALID_HANDLE: u32 = 6;
    const ERROR_PRINT_CANCELLED: u32 = 63;
    const ERROR_INVALID_PARAMETER: u32 = 87;
    const ERROR_INSUFFICIENT_BUFFER: u32 = 122;
    const ERROR_CANCELLED: u32 = 1223;

    /// True when Windows knows at least one printer, its own or a shared one.
    fn any_printer() -> bool {
        let mut needed = 0u32;
        let mut count = 0u32;
        // Asked without room for the answer: with a printer to describe, the
        // call fails for want of room; without any, it succeeds and writes
        // nothing.
        let listed = unsafe {
            EnumPrintersW(
                PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS,
                ptr::null(),
                4,
                ptr::null_mut(),
                0,
                &mut needed,
                &mut count,
            )
        };
        listed == 0 && unsafe { GetLastError() } == ERROR_INSUFFICIENT_BUFFER
    }

    /// The window of this program that the dialog opens over: its first
    /// visible window that no other window owns. Null when it shows none.
    fn window_of_the_program() -> Handle {
        unsafe extern "system" fn each(window: Handle, found: isize) -> i32 {
            let mut process = 0u32;
            unsafe { GetWindowThreadProcessId(window, &mut process) };
            let ours = process == unsafe { GetCurrentProcessId() }
                && unsafe { IsWindowVisible(window) } != 0
                && unsafe { GetWindow(window, GW_OWNER) }.is_null();
            if ours {
                // SAFETY: `found` is the address that window_of_the_program gave.
                unsafe { *(found as *mut Handle) = window };
                return 0;
            }
            1
        }
        let mut found: Handle = ptr::null_mut();
        unsafe { EnumWindows(each, &mut found as *mut Handle as isize) };
        found
    }

    /// The name of the device of `mode`, without what follows its end.
    fn device_name(mode: &DeviceModeStart) -> Vec<u16> {
        let end = mode
            .device_name
            .iter()
            .position(|&unit| unit == 0)
            .unwrap_or(mode.device_name.len());
        mode.device_name[..end].to_vec()
    }

    fn free(memory: &mut Handle) {
        if !memory.is_null() {
            unsafe { GlobalFree(*memory) };
            *memory = ptr::null_mut();
        }
    }

    /// One page on the device that the person chose.
    fn print_on_device(
        device: Handle,
        rgba: &[u8],
        width: i32,
        height: i32,
        job_name: &[u16],
    ) -> (i32, u32) {
        let caps = |index| unsafe { GetDeviceCaps(device, index) };
        let page = PageGeometry {
            area_width: caps(HORZRES),
            area_height: caps(VERTRES),
            paper_width: caps(PHYSICALWIDTH),
            paper_height: caps(PHYSICALHEIGHT),
            offset_x: caps(PHYSICALOFFSETX),
            offset_y: caps(PHYSICALOFFSETY),
            dpi_x: caps(LOGPIXELSX),
            dpi_y: caps(LOGPIXELSY),
        };
        if page.area_width < 1 || page.area_height < 1 || page.dpi_x < 1 || page.dpi_y < 1 {
            return (FAILED, ERROR_INVALID_PARAMETER);
        }
        let place = place_on_page(width, height, &page);
        let pixels = bottom_up_bgr(rgba, width as usize, height as usize);
        // SAFETY: all its fields are numbers, for which zero is a value.
        let mut info: BitmapInfo = unsafe { mem::zeroed() };
        info.header.size = mem::size_of::<BitmapHeader>() as u32;
        info.header.width = width;
        info.header.height = height;
        info.header.planes = 1;
        info.header.bit_count = 24;
        info.header.compression = BI_RGB;

        let document = DocumentInfo {
            size: mem::size_of::<DocumentInfo>() as i32,
            document_name: job_name.as_ptr(),
            output: ptr::null(),
            datatype: ptr::null(),
            kind: 0,
        };
        if unsafe { StartDocW(device, &document) } <= 0 {
            // A printer that writes a file asks for its name here: giving up
            // there is giving up printing.
            let error = unsafe { GetLastError() };
            if error == ERROR_CANCELLED || error == ERROR_PRINT_CANCELLED {
                return (CANCELLED, 0);
            }
            return (FAILED, error);
        }
        let mut error = 0;
        let mut drawn = unsafe { StartPage(device) } > 0;
        if drawn {
            unsafe {
                SetStretchBltMode(device, HALFTONE);
                SetBrushOrgEx(device, 0, 0, ptr::null_mut());
            }
            let lines = unsafe {
                StretchDIBits(
                    device,
                    place.left,
                    place.top,
                    place.right - place.left,
                    place.bottom - place.top,
                    0,
                    0,
                    width,
                    height,
                    pixels.as_ptr().cast(),
                    &info,
                    DIB_RGB_COLORS,
                    SRCCOPY,
                )
            };
            drawn = lines > 0;
            // The reason of a failure is read at once: the next call
            // replaces it.
            let drawing_error = if drawn { 0 } else { unsafe { GetLastError() } };
            if unsafe { EndPage(device) } <= 0 {
                error = if drawn {
                    unsafe { GetLastError() }
                } else {
                    drawing_error
                };
                drawn = false;
            } else if !drawn {
                error = drawing_error;
            }
        } else {
            error = unsafe { GetLastError() };
        }
        if !drawn {
            unsafe { AbortDoc(device) };
            return (FAILED, error);
        }
        if unsafe { EndDoc(device) } <= 0 {
            return (FAILED, unsafe { GetLastError() });
        }
        (SENT, 0)
    }

    /// Opens the print dialog of Windows over the window of the program for
    /// one image on one page, and returns when the dialog is closed and, if
    /// confirmed, the page handed to the spooler: the outcome and, for a
    /// failure, the code of Windows.
    pub(super) fn print_image(
        rgba: &[u8],
        width: i32,
        height: i32,
        job_name: &[u16],
    ) -> (i32, u32) {
        // Without a printer no dialog opens: Color explains it in its own
        // words, rather than Windows offering to install one.
        if !any_printer() {
            return (NO_PRINTER, 0);
        }
        let wanted = if width > height {
            DMORIENT_LANDSCAPE
        } else {
            DMORIENT_PORTRAIT
        };
        // The printer whose page was turned before the dialog opened.
        let mut turned_printer: Vec<u16> = Vec::new();

        // SAFETY: handles, numbers and addresses, for which zero is a value.
        let mut dialog: PrintDialog = unsafe { mem::zeroed() };
        dialog.struct_size = mem::size_of::<PrintDialog>() as u32;
        // The settings of the printer that Windows proposes, asked without
        // any window, to turn its page the way the drawing is before the
        // dialog opens. The person can still decide otherwise there.
        dialog.flags = PD_RETURNDEFAULT;
        if unsafe { PrintDlgW(&mut dialog) } != 0 && !dialog.dev_mode.is_null() {
            let mode = unsafe { GlobalLock(dialog.dev_mode) }.cast::<DeviceModeStart>();
            if !mode.is_null() {
                // SAFETY: Windows wrote a DEVMODEW there, which starts so.
                let mode = unsafe { &mut *mode };
                if mode.fields & DM_ORIENTATION != 0 {
                    mode.orientation = wanted;
                    turned_printer = device_name(mode);
                }
                unsafe { GlobalUnlock(dialog.dev_mode) };
            }
        } else {
            // No proposed printer is not yet no printer: the dialog will tell.
            free(&mut dialog.dev_mode);
            free(&mut dialog.dev_names);
        }

        // One page, the whole drawing: no page numbers, no selection. Should
        // the printers have gone meanwhile, the dialog says nothing itself.
        dialog.owner = window_of_the_program();
        dialog.flags = PD_RETURNDC
            | PD_NOPAGENUMS
            | PD_NOSELECTION
            | PD_HIDEPRINTTOFILE
            | PD_NOWARNING
            | PD_USEDEVMODECOPIESANDCOLLATE;
        dialog.copies = 1;
        // The first call did not ask for a device: nothing says what it left
        // here.
        dialog.dc = ptr::null_mut();
        let mut result = (CANCELLED, 0);
        if unsafe { PrintDlgW(&mut dialog) } != 0 {
            if dialog.dc.is_null() {
                result = (FAILED, ERROR_INVALID_HANDLE);
            } else {
                // Another printer chosen in the dialog starts from its own
                // settings: its page is turned the way the drawing is, as
                // the first one was.
                let mode = if dialog.dev_mode.is_null() {
                    ptr::null_mut()
                } else {
                    unsafe { GlobalLock(dialog.dev_mode) }.cast::<DeviceModeStart>()
                };
                if !mode.is_null() {
                    // SAFETY: as above.
                    let mode = unsafe { &mut *mode };
                    if device_name(mode) != turned_printer
                        && mode.fields & DM_ORIENTATION != 0
                        && mode.orientation != wanted
                    {
                        mode.orientation = wanted;
                        unsafe { ResetDCW(dialog.dc, mode) };
                    }
                    unsafe { GlobalUnlock(dialog.dev_mode) };
                }
                result = print_on_device(dialog.dc, rgba, width, height, job_name);
            }
        } else {
            // Zero is the person closing the dialog.
            let error = unsafe { CommDlgExtendedError() };
            if error == PDERR_NODEFAULTPRN || error == PDERR_NODEVICES {
                result = (NO_PRINTER, 0);
            } else if error != 0 {
                result = (FAILED, error);
            }
        }
        if !dialog.dc.is_null() {
            unsafe { DeleteDC(dialog.dc) };
        }
        free(&mut dialog.dev_mode);
        free(&mut dialog.dev_names);
        result
    }
}

#[cfg(test)]
mod tests;
