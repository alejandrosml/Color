// SPDX-License-Identifier: MIT
use super::*;
use std::ffi::CString;
use std::ptr;

/// A4 at 600 dots per inch, with what the printer cannot reach on each side.
fn a4(left: i32, top: i32, right: i32, bottom: i32) -> PageGeometry {
    PageGeometry {
        area_width: 4960 - left - right,
        area_height: 7016 - top - bottom,
        paper_width: 4960,
        paper_height: 7016,
        offset_x: left,
        offset_y: top,
        dpi_x: 600,
        dpi_y: 600,
    }
}

#[test]
fn a_wide_image_fills_the_width_of_the_page_in_its_middle() {
    let place = place_on_page(400, 200, &a4(100, 100, 100, 100));
    assert_eq!(
        place,
        Place {
            left: 0,
            top: 2218,
            right: 4760,
            bottom: 4598
        }
    );
    // Twice as wide as high, as the image is.
    assert_eq!(place.right - place.left, 2 * (place.bottom - place.top));
}

#[test]
fn a_tall_image_fills_the_height_of_the_page_in_its_middle() {
    let place = place_on_page(200, 800, &a4(100, 100, 100, 100));
    assert_eq!(place.bottom - place.top, 6816);
    assert_eq!(place.right - place.left, 1704);
    assert_eq!(place.left, (4760 - 1704) / 2);
    assert_eq!(place.top, 0);
}

#[test]
fn unequal_margins_keep_the_image_in_the_middle_of_the_paper() {
    let page = a4(50, 80, 150, 20);
    let place = place_on_page(400, 200, &page);
    let on_paper_left = page.offset_x + place.left;
    let on_paper_right = page.paper_width - (page.offset_x + place.right);
    assert_eq!(on_paper_left, 150);
    assert_eq!(on_paper_right, 150);
    let on_paper_top = page.offset_y + place.top;
    let on_paper_bottom = page.paper_height - (page.offset_y + place.bottom);
    assert_eq!(on_paper_top, on_paper_bottom);
    assert!(place.left >= 0 && place.top >= 0);
    assert!(place.right <= page.area_width && place.bottom <= page.area_height);
}

#[test]
fn dots_that_are_not_square_do_not_distort_the_image() {
    let page = PageGeometry {
        area_width: 4960,
        area_height: 3508,
        paper_width: 4960,
        paper_height: 3508,
        offset_x: 0,
        offset_y: 0,
        dpi_x: 600,
        dpi_y: 300,
    };
    let place = place_on_page(100, 100, &page);
    // A square image: as many inches across as down.
    assert_eq!(place.right - place.left, 4960);
    assert_eq!(place.bottom - place.top, 2480);
    assert_eq!(place.top, (3508 - 2480) / 2);
}

#[test]
fn a_driver_that_describes_its_paper_wrongly_gets_the_middle_of_its_area() {
    // The area would end beyond the paper: nothing is deduced from it.
    let page = PageGeometry {
        area_width: 5000,
        area_height: 7000,
        paper_width: 4960,
        paper_height: 7016,
        offset_x: 10,
        offset_y: 10,
        dpi_x: 600,
        dpi_y: 600,
    };
    let place = place_on_page(100, 100, &page);
    assert_eq!(place.right - place.left, 5000);
    assert_eq!(place.bottom - place.top, 5000);
    assert_eq!(place.left, 0);
    assert_eq!(place.top, 1000);
}

#[test]
fn the_thinnest_image_still_gets_one_dot() {
    let place = place_on_page(8192, 1, &a4(100, 100, 100, 100));
    assert_eq!(place.right - place.left, 4760);
    assert_eq!(place.bottom - place.top, 1);
    let place = place_on_page(1, 8192, &a4(100, 100, 100, 100));
    assert_eq!(place.right - place.left, 1);
    assert_eq!(place.bottom - place.top, 6816);
}

#[test]
fn the_pixels_are_turned_upside_down_in_blue_green_red_with_padded_rows() {
    // Two pixels by two: red, green above; blue, white below.
    let rgba = [
        255, 0, 0, 255, 0, 255, 0, 255, //
        0, 0, 255, 255, 255, 255, 255, 255,
    ];
    let pixels = bottom_up_bgr(&rgba, 2, 2);
    assert_eq!(
        pixels,
        [
            255, 0, 0, 255, 255, 255, 0, 0, // blue, white, padding
            0, 0, 255, 0, 255, 0, 0, 0, // red, green, padding
        ]
    );
    // A width that needs no padding, and one that needs three bytes.
    assert_eq!(bottom_up_bgr(&[0; 4 * 4], 4, 1).len(), 12);
    assert_eq!(bottom_up_bgr(&[0; 3 * 4 * 2], 3, 2).len(), 24);
}

#[test]
fn a_request_that_cannot_be_one_is_refused() {
    let name = CString::new("Zoé").unwrap();
    let pixels = [0u8; 16];
    unsafe {
        assert_eq!(ep_print_start(ptr::null(), 2, 2, name.as_ptr()), INVALID);
        assert_eq!(ep_print_start(pixels.as_ptr(), 2, 2, ptr::null()), INVALID);
        assert_eq!(
            ep_print_start(pixels.as_ptr(), 0, 2, name.as_ptr()),
            INVALID
        );
        assert_eq!(
            ep_print_start(pixels.as_ptr(), 2, 0, name.as_ptr()),
            INVALID
        );
        assert_eq!(
            ep_print_start(pixels.as_ptr(), 8193, 1, name.as_ptr()),
            INVALID
        );
        assert_eq!(
            ep_print_start(pixels.as_ptr(), 1, 8193, name.as_ptr()),
            INVALID
        );
        let not_utf8 = [0xffu8, 0xfe, 0];
        assert_eq!(
            ep_print_start(pixels.as_ptr(), 2, 2, not_utf8.as_ptr().cast()),
            INVALID
        );
    }
}

#[cfg(not(all(windows, target_pointer_width = "64")))]
#[test]
fn away_from_windows_the_core_does_not_print() {
    let name = CString::new("Zoé").unwrap();
    let pixels = [0u8; 16];
    unsafe {
        assert_eq!(
            ep_print_start(pixels.as_ptr(), 2, 2, name.as_ptr()),
            NO_PRINTING_HERE
        );
        let mut code = 7u32;
        assert_eq!(ep_print_result(&mut code), NOTHING_ASKED);
        assert_eq!(code, 7);
        assert_eq!(ep_print_result(ptr::null_mut()), NOTHING_ASKED);
    }
}

/// The trial on a real Windows: the dialog of the system opened over a
/// window of this test, answered by the messages of its own buttons (no key
/// and no pointer event), and the page that the printer of the recipe
/// writes. Asked for by name, by the recipe that prepared that printer:
///
///   cargo test --release print_trial -- --ignored --test-threads=1
///
/// COLOR_PRINT_TRIAL_PORT names the file that the default printer writes
/// (a printer « Microsoft Print To PDF » on a port that is a file), and
/// COLOR_PRINT_TRIAL_PAGES the folder that receives each page.
#[cfg(all(windows, target_pointer_width = "64"))]
mod trial {
    use super::super::*;
    use std::ffi::{c_void, CString};
    use std::path::PathBuf;
    use std::ptr;
    use std::time::{Duration, Instant};

    type Handle = *mut c_void;
    type WindowProcedure = unsafe extern "system" fn(Handle, u32, usize, isize) -> isize;

    #[repr(C)]
    struct WindowClass {
        style: u32,
        procedure: Option<WindowProcedure>,
        class_extra: i32,
        window_extra: i32,
        instance: Handle,
        icon: Handle,
        cursor: Handle,
        background: Handle,
        menu_name: *const u16,
        class_name: *const u16,
    }

    #[repr(C)]
    struct Message {
        window: Handle,
        message: u32,
        wparam: usize,
        lparam: isize,
        time: u32,
        x: i32,
        y: i32,
        private: u32,
    }

    #[link(name = "user32")]
    extern "system" {
        fn RegisterClassW(class: *const WindowClass) -> u16;
        #[allow(clippy::too_many_arguments)]
        fn CreateWindowExW(
            extended_style: u32,
            class_name: *const u16,
            title: *const u16,
            style: u32,
            x: i32,
            y: i32,
            width: i32,
            height: i32,
            parent: Handle,
            menu: Handle,
            instance: Handle,
            parameter: *mut c_void,
        ) -> Handle;
        fn DefWindowProcW(window: Handle, message: u32, wparam: usize, lparam: isize) -> isize;
        fn DestroyWindow(window: Handle) -> i32;
        fn PeekMessageW(
            message: *mut Message,
            window: Handle,
            first: u32,
            last: u32,
            remove: u32,
        ) -> i32;
        fn TranslateMessage(message: *const Message) -> i32;
        fn DispatchMessageW(message: *const Message) -> isize;
        fn IsWindowEnabled(window: Handle) -> i32;
        fn PostMessageW(window: Handle, message: u32, wparam: usize, lparam: isize) -> i32;
        fn GetClassNameW(window: Handle, name: *mut u16, capacity: i32) -> i32;
        fn GetWindowTextW(window: Handle, text: *mut u16, capacity: i32) -> i32;
        fn EnumWindows(each: unsafe extern "system" fn(Handle, isize) -> i32, with: isize) -> i32;
        fn GetWindow(window: Handle, relation: u32) -> Handle;
    }

    #[link(name = "kernel32")]
    extern "system" {
        fn GetModuleHandleW(name: *const u16) -> Handle;
    }

    const WS_OVERLAPPEDWINDOW: u32 = 0x00CF_0000;
    const WS_VISIBLE: u32 = 0x1000_0000;
    const PM_REMOVE: u32 = 1;
    const WM_COMMAND: u32 = 0x0111;
    const IDOK: usize = 1;
    const IDCANCEL: usize = 2;
    const GW_OWNER: u32 = 4;

    fn wide(text: &str) -> Vec<u16> {
        text.encode_utf16().chain(std::iter::once(0)).collect()
    }

    /// A visible window of this test, as the window of Color is for the
    /// program: the dialog opens over it.
    fn window() -> Handle {
        let class_name = wide("ColorPrintTrial");
        let instance = unsafe { GetModuleHandleW(ptr::null()) };
        let class = WindowClass {
            style: 0,
            procedure: Some(DefWindowProcW),
            class_extra: 0,
            window_extra: 0,
            instance,
            icon: ptr::null_mut(),
            cursor: ptr::null_mut(),
            background: ptr::null_mut(),
            menu_name: ptr::null(),
            class_name: class_name.as_ptr(),
        };
        // Registered once per process: a second time fails, and does no harm.
        unsafe { RegisterClassW(&class) };
        let title = wide("Color — essai d’impression");
        let window = unsafe {
            CreateWindowExW(
                0,
                class_name.as_ptr(),
                title.as_ptr(),
                WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                40,
                40,
                640,
                420,
                ptr::null_mut(),
                ptr::null_mut(),
                instance,
                ptr::null_mut(),
            )
        };
        assert!(
            !window.is_null(),
            "the window of the trial could not be made"
        );
        window
    }

    /// Lets the window of the trial live for `time`.
    fn pump(time: Duration) {
        let until = Instant::now() + time;
        loop {
            // SAFETY: numbers, a handle and no more; zero is a value of each.
            let mut message: Message = unsafe { std::mem::zeroed() };
            while unsafe { PeekMessageW(&mut message, ptr::null_mut(), 0, 0, PM_REMOVE) } != 0 {
                unsafe {
                    TranslateMessage(&message);
                    DispatchMessageW(&message);
                }
            }
            if Instant::now() >= until {
                return;
            }
            std::thread::sleep(Duration::from_millis(15));
        }
    }

    struct Search {
        owner: Handle,
        found: Handle,
    }

    /// The dialog that `owner` owns, if one is open: a window of the class
    /// of dialogs. Its title is returned with it.
    fn dialog_over(owner: Handle) -> Option<(Handle, String)> {
        unsafe extern "system" fn each(window: Handle, search: isize) -> i32 {
            // SAFETY: the address of the Search that dialog_over made.
            let search = unsafe { &mut *(search as *mut Search) };
            if unsafe { GetWindow(window, GW_OWNER) } != search.owner {
                return 1;
            }
            let mut class = [0u16; 32];
            let length = unsafe { GetClassNameW(window, class.as_mut_ptr(), 32) };
            if String::from_utf16_lossy(&class[..length.max(0) as usize]) == "#32770" {
                search.found = window;
                return 0;
            }
            1
        }
        let mut search = Search {
            owner,
            found: ptr::null_mut(),
        };
        unsafe { EnumWindows(each, &mut search as *mut Search as isize) };
        if search.found.is_null() {
            return None;
        }
        let mut title = [0u16; 128];
        let length = unsafe { GetWindowTextW(search.found, title.as_mut_ptr(), 128) };
        Some((
            search.found,
            String::from_utf16_lossy(&title[..length.max(0) as usize]),
        ))
    }

    /// Red and green above, blue and yellow below, in a dark frame at the
    /// edge of the image.
    fn picture(width: u32, height: u32) -> Vec<u8> {
        let mut pixels = Vec::with_capacity((width * height * 4) as usize);
        let frame = (width.min(height) / 20).max(2);
        for y in 0..height {
            for x in 0..width {
                let colour = if x < frame || y < frame || x >= width - frame || y >= height - frame
                {
                    [24, 24, 40]
                } else {
                    match (x < width / 2, y < height / 2) {
                        (true, true) => [220, 40, 40],
                        (false, true) => [40, 170, 70],
                        (true, false) => [40, 80, 220],
                        (false, false) => [240, 200, 40],
                    }
                };
                pixels.extend_from_slice(&[colour[0], colour[1], colour[2], 255]);
            }
        }
        pixels
    }

    fn environment(name: &str) -> PathBuf {
        PathBuf::from(
            std::env::var_os(name).unwrap_or_else(|| panic!("{name} is not set: see the recipe")),
        )
    }

    /// Asks for one page, answers the dialog with `button`, and returns the
    /// outcome with its error code.
    fn print(width: u32, height: u32, job: &str, button: usize) -> (i32, u32) {
        let owner = window();
        pump(Duration::from_millis(300));
        let pixels = picture(width, height);
        let name = CString::new(job).unwrap();
        assert_eq!(
            unsafe { ep_print_start(pixels.as_ptr(), width, height, name.as_ptr()) },
            STARTED
        );
        let asked = Instant::now();
        let dialog = loop {
            pump(Duration::from_millis(100));
            if let Some(found) = dialog_over(owner) {
                break found;
            }
            let mut code = 0;
            let now = unsafe { ep_print_result(&mut code) };
            assert_eq!(
                now, RUNNING,
                "no dialog, and the request ended: {now} (code {code})"
            );
            assert!(
                asked.elapsed() < Duration::from_secs(60),
                "the print dialog did not open in a minute"
            );
        };
        println!(
            "dialog « {} » opened in {:.1} s",
            dialog.1,
            asked.elapsed().as_secs_f64()
        );
        // The time for the dialog to list its printers.
        pump(Duration::from_secs(2));
        // While it is open: Windows has disabled the window under it, and a
        // second request is refused.
        assert_eq!(
            unsafe { IsWindowEnabled(owner) },
            0,
            "the window under the dialog is still enabled"
        );
        assert_eq!(
            unsafe { ep_print_start(pixels.as_ptr(), width, height, name.as_ptr()) },
            BUSY
        );
        assert_ne!(unsafe { PostMessageW(dialog.0, WM_COMMAND, button, 0) }, 0);
        let answered = Instant::now();
        let outcome = loop {
            pump(Duration::from_millis(100));
            let mut code = 0;
            let now = unsafe { ep_print_result(&mut code) };
            if now != RUNNING {
                break (now, code);
            }
            assert!(
                answered.elapsed() < Duration::from_secs(120),
                "the request did not end two minutes after the answer"
            );
        };
        // Answered once: the core has forgotten the request.
        assert_eq!(unsafe { ep_print_result(ptr::null_mut()) }, NOTHING_ASKED);
        pump(Duration::from_millis(300));
        assert_ne!(
            unsafe { IsWindowEnabled(owner) },
            0,
            "the window stayed disabled"
        );
        unsafe { DestroyWindow(owner) };
        pump(Duration::from_millis(100));
        outcome
    }

    /// Waits for the page that the printer writes, and moves it to the
    /// folder of the pages under `name`.
    fn keep_the_page(name: &str) -> u64 {
        let port = environment("COLOR_PRINT_TRIAL_PORT");
        let pages = environment("COLOR_PRINT_TRIAL_PAGES");
        std::fs::create_dir_all(&pages).unwrap();
        let asked = Instant::now();
        let mut last = 0;
        let mut steady = 0;
        // Written by the spooler after the page was handed to it: wait for a
        // file that has stopped growing.
        loop {
            std::thread::sleep(Duration::from_millis(500));
            let size = std::fs::metadata(&port).map(|file| file.len()).unwrap_or(0);
            steady = if size > 0 && size == last {
                steady + 1
            } else {
                0
            };
            last = size;
            if steady >= 4 {
                break;
            }
            assert!(
                asked.elapsed() < Duration::from_secs(90),
                "no page written to {} in ninety seconds",
                port.display()
            );
        }
        let bytes = std::fs::read(&port).unwrap();
        assert!(bytes.starts_with(b"%PDF"), "the page is not a PDF file");
        let kept = pages.join(format!("{name}.pdf"));
        std::fs::write(&kept, &bytes).unwrap();
        // The next page must not be mistaken for this one.
        let _ = std::fs::remove_file(&port);
        println!("{} : {} bytes", kept.display(), bytes.len());
        bytes.len() as u64
    }

    #[test]
    #[ignore = "opens the print dialog of Windows: asked for by the recipe"]
    fn print_trial_1_cancelled_in_the_dialog_nothing_is_printed() {
        let port = environment("COLOR_PRINT_TRIAL_PORT");
        let _ = std::fs::remove_file(&port);
        let outcome = print(600, 300, "Color — essai annulé", IDCANCEL);
        assert_eq!(outcome, (CANCELLED, 0));
        std::thread::sleep(Duration::from_secs(3));
        assert!(
            !port.exists(),
            "a page was written although the dialog was cancelled"
        );
    }

    #[test]
    #[ignore = "opens the print dialog of Windows: asked for by the recipe"]
    fn print_trial_2_a_wide_image_is_printed() {
        let outcome = print(600, 300, "Color — essai, feuille large", IDOK);
        assert_eq!(outcome, (SENT, 0));
        assert!(keep_the_page("large") > 500);
    }

    #[test]
    #[ignore = "opens the print dialog of Windows: asked for by the recipe"]
    fn print_trial_3_a_tall_image_is_printed() {
        let outcome = print(300, 600, "Color — essai, feuille haute", IDOK);
        assert_eq!(outcome, (SENT, 0));
        assert!(keep_the_page("haute") > 500);
    }

    #[test]
    #[ignore = "opens the print dialog of Windows: asked for by the recipe"]
    fn print_trial_4_a_square_image_is_printed() {
        let outcome = print(400, 400, "Color — essai, feuille carrée", IDOK);
        assert_eq!(outcome, (SENT, 0));
        assert!(keep_the_page("carree") > 500);
    }
}
