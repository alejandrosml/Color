//! Keeping a saved drawing through a power cut.
//!
//! A save writes a temporary file, flushes it, then gives it the name of the
//! drawing: a crash at any moment leaves the old drawing or the new one. A
//! power cut is harder. The flush of Dart is a plain fsync, which on Apple
//! systems leaves the data in the disk's own cache, and the new name lives
//! in the folder, which nothing flushed. This asks the system for both: the
//! file before it gets its name, its folder after. Only Rust's standard
//! library and the system are used: no other code.
use super::INVALID;
use std::ffi::{c_char, CStr};
#[cfg(unix)]
use std::fs::File;
use std::io;

/// The system refused: no such file, no permission, a disk that does not
/// flush. What was written stays as it was.
const SYSTEM_REFUSED: i32 = -3;

/// Asks the system to put the file or folder at `path`, written just before,
/// on permanent storage.
///
/// `full` = 1, for a save the person asked for: on Apple systems
/// F_FULLFSYNC, which also empties the disk's own cache; elsewhere fsync.
/// `full` = 0, for the recovery copy: on Apple systems F_BARRIERFSYNC, which
/// only keeps the order of the writes (the copy reaches the disk before its
/// new name), and costs much less; elsewhere fsync. A folder is flushed so
/// after a file got its name in it; on Windows, whose file system writes
/// names through its own journal, a folder is left alone.
///
/// Returns 0 done, -1 NULL, not UTF-8 or `full` neither 0 nor 1, -3 the
/// system refused. Nothing else is touched.
///
/// # Safety
/// Non-null `path` must be a NUL-terminated string, live for the call.
#[no_mangle]
pub unsafe extern "C" fn ep_sync_path(path: *const c_char, full: u32) -> i32 {
    if path.is_null() || full > 1 {
        return INVALID;
    }
    let Ok(path) = unsafe { CStr::from_ptr(path) }.to_str() else {
        return INVALID;
    };
    match sync(path, full == 1) {
        Ok(()) => 0,
        Err(_) => SYSTEM_REFUSED,
    }
}

#[cfg(target_vendor = "apple")]
fn sync(path: &str, full: bool) -> io::Result<()> {
    use std::os::fd::AsRawFd;
    // Opened for reading: a folder opens so as well, and flushing asks for no
    // more than that.
    let file = File::open(path)?;
    if full {
        // On Apple systems, std's sync_all is fcntl(F_FULLFSYNC).
        return file.sync_all();
    }
    extern "C" {
        // The system's own, in libSystem, which every program links to.
        fn fcntl(descriptor: i32, command: i32, ...) -> i32;
    }
    // <sys/fcntl.h> of macOS and iOS.
    const F_BARRIERFSYNC: i32 = 85;
    if unsafe { fcntl(file.as_raw_fd(), F_BARRIERFSYNC) } == -1 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

#[cfg(all(unix, not(target_vendor = "apple")))]
fn sync(path: &str, _full: bool) -> io::Result<()> {
    // fsync, through a descriptor opened for reading: Linux and Android
    // flush a folder so as well.
    File::open(path)?.sync_all()
}

#[cfg(windows)]
fn sync(path: &str, _full: bool) -> io::Result<()> {
    if std::fs::metadata(path)?.is_dir() {
        return Ok(());
    }
    // FlushFileBuffers needs a handle that may write.
    std::fs::OpenOptions::new()
        .write(true)
        .open(path)?
        .sync_all()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    fn sync_path(path: &str, full: u32) -> i32 {
        let path = CString::new(path).unwrap();
        unsafe { ep_sync_path(path.as_ptr(), full) }
    }

    #[test]
    #[cfg_attr(miri, ignore = "Miri cannot flush a folder (fsync of a directory)")]
    fn a_file_and_its_folder_are_flushed_and_left_as_they_were() {
        let folder = std::env::temp_dir().join(format!("color-sync-{}", std::process::id()));
        std::fs::create_dir_all(&folder).unwrap();
        let file = folder.join("dessin.edupaint");
        std::fs::write(&file, b"EDUPAINT").unwrap();
        for full in [0, 1] {
            assert_eq!(sync_path(file.to_str().unwrap(), full), 0);
            assert_eq!(sync_path(folder.to_str().unwrap(), full), 0);
        }
        assert_eq!(std::fs::read(&file).unwrap(), b"EDUPAINT");
        std::fs::remove_file(&file).unwrap();
        // Gone: the system refuses, nothing is created.
        assert_eq!(sync_path(file.to_str().unwrap(), 1), SYSTEM_REFUSED);
        assert!(!file.exists());
        std::fs::remove_dir(&folder).unwrap();
    }

    #[test]
    fn invalid_input_is_refused_before_the_system_is_asked() {
        assert_eq!(unsafe { ep_sync_path(std::ptr::null(), 1) }, INVALID);
        assert_eq!(sync_path(".", 2), INVALID);
        let not_utf8 = [0xffu8, 0xfe, 0];
        assert_eq!(
            unsafe { ep_sync_path(not_utf8.as_ptr().cast(), 1) },
            INVALID
        );
    }
}
