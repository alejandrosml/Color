//! Transactional filling of an exclusively borrowed, already-owned candidate.
//! Ownership of the allocation never moves to the worker that fills it.
use super::*;

fn commit_loaded(candidate: &mut EpDocument, loaded: Result<EpDocument, i32>) -> i32 {
    match loaded {
        Ok(loaded) => {
            *candidate = loaded;
            0
        }
        Err(status) => status,
    }
}

/// Loads a complete project into an already-owned candidate. A rejected input
/// or allocation failure leaves all candidate content/history unchanged. The
/// application uses a private empty candidate, never its visible document.
/// Calls the established parser once; it retains its validation/construction
/// passes. PNG validation is structural: decode pixels before UI adoption.
///
/// # Safety
/// `candidate` must be live/aligned and exclusively borrowed for this call;
/// there must be no other reads, writes, destruction or outstanding references.
/// `bytes` must address `length` initialized immutable bytes in one allocation,
/// disjoint from all candidate-owned storage. The allocation's owner retains
/// ownership throughout; this function neither frees nor changes its address.
/// The caller may move this exclusive borrow between threads, but must observe
/// the end of the borrow before any subsequent access or destruction.
#[no_mangle]
pub unsafe extern "C" fn ep_document_load_project(
    candidate: *mut EpDocument,
    bytes: *const u8,
    length: usize,
) -> i32 {
    if candidate.is_null()
        || bytes.is_null()
        || !(PROJECT_MIN_BYTES..=MAX_PROJECT_BYTES).contains(&length)
    {
        return INVALID;
    }
    let loaded = load_project(unsafe { slice::from_raw_parts(bytes, length) });
    commit_loaded(unsafe { &mut *candidate }, loaded)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Owned(*mut EpDocument);
    impl Owned {
        fn new() -> Self {
            let pointer = ep_document_new(600, 400);
            assert!(!pointer.is_null());
            Self(pointer)
        }
        fn bytes(&self) -> Vec<u8> {
            let mut output = vec![0; unsafe { ep_project_size(self.0) }];
            assert_eq!(
                unsafe { ep_copy_project(self.0, output.as_mut_ptr(), output.len()) },
                0
            );
            output
        }
        fn state(&self) -> (Vec<u8>, usize, usize, u64) {
            (
                self.bytes(),
                unsafe { ep_undo_count(self.0) },
                unsafe { ep_redo_count(self.0) },
                unsafe { ep_object_revision(self.0, 0) },
            )
        }
        fn edited() -> Self {
            let document = Self::new();
            let points = [EpPoint { x: 10.0, y: 20.0 }, EpPoint { x: 30.0, y: 40.0 }];
            assert_eq!(
                unsafe { ep_add_stroke(document.0, points.as_ptr(), 2, 0x123456, 3.0) },
                0
            );
            assert_eq!(unsafe { ep_move_object(document.0, 0, 5.0, 6.0) }, 1);
            assert_eq!(unsafe { ep_undo(document.0) }, 1);
            document
        }
        fn load(&self, bytes: &[u8]) -> i32 {
            unsafe { ep_document_load_project(self.0, bytes.as_ptr(), bytes.len()) }
        }
    }
    impl Drop for Owned {
        fn drop(&mut self) {
            unsafe { ep_document_free(self.0) };
        }
    }
    macro_rules! fixture {
        ($name:literal) => {
            include_bytes!(concat!("../test-fixtures/import-project/", $name))
        };
    }

    #[test]
    fn load_independent_valid_versions_and_dimensions_exactly() {
        let cases: &[(&[u8], &[u8])] = &[
            (
                fixture!("legacy-v1.edupaint"),
                fixture!("legacy-v1.edupaint.normalized"),
            ),
            (
                fixture!("portrait-v2.edupaint"),
                fixture!("portrait-v2.edupaint.normalized"),
            ),
            (
                fixture!("empty-square-v2.edupaint"),
                fixture!("empty-square-v2.edupaint.normalized"),
            ),
            (
                fixture!("rgb-v3.edupaint"),
                fixture!("rgb-v3.edupaint.normalized"),
            ),
            (
                fixture!("rgba-v3.edupaint"),
                fixture!("rgba-v3.edupaint.normalized"),
            ),
            (
                fixture!("structural-png-undecodable.edupaint"),
                fixture!("structural-png-undecodable.edupaint.normalized"),
            ),
        ];
        for (input, expected) in cases {
            let document = Owned::edited();
            let address = document.0;
            assert_eq!(document.load(input), 0);
            assert_eq!(document.0, address);
            assert_eq!(document.bytes(), *expected);
            assert_eq!(unsafe { ep_redo_count(document.0) }, 0);
            assert_eq!(unsafe { ep_undo_count(document.0) }, unsafe {
                ep_stroke_count(document.0)
            });
        }
    }

    #[test]
    fn every_independent_rejection_preserves_content_and_history() {
        let cases: &[&[u8]] = &[
            fixture!("bad-project-crc.edupaint"),
            fixture!("bad-png-crc.edupaint"),
            fixture!("truncated.edupaint"),
            fixture!("unknown-version.edupaint"),
            fixture!("declared-length.edupaint"),
            fixture!("point-nan.edupaint"),
            fixture!("zero-rectangle.edupaint"),
            fixture!("unknown-style.edupaint"),
            fixture!("background-dimensions.edupaint"),
            fixture!("declared-point-count.edupaint"),
        ];
        let document = Owned::edited();
        let before = document.state();
        for input in cases {
            assert_eq!(document.load(input), INVALID);
            assert_eq!(document.state(), before);
        }
    }

    #[test]
    fn null_and_invalid_lengths_do_not_touch_candidate() {
        let document = Owned::edited();
        let before = document.state();
        let input = fixture!("portrait-v2.edupaint");
        unsafe {
            assert_eq!(
                ep_document_load_project(ptr::null_mut(), input.as_ptr(), input.len()),
                INVALID
            );
            assert_eq!(
                ep_document_load_project(document.0, ptr::null(), input.len()),
                INVALID
            );
            assert_eq!(
                ep_document_load_project(document.0, input.as_ptr(), 0),
                INVALID
            );
            assert_eq!(
                ep_document_load_project(document.0, input.as_ptr(), usize::MAX),
                INVALID
            );
        }
        assert_eq!(document.state(), before);
    }

    #[test]
    fn allocation_error_result_preserves_existing_state() {
        // Exercises the commit boundary, not an induced system OOM or allocator.
        let document = Owned::edited();
        let before = document.state();
        assert_eq!(
            commit_loaded(unsafe { &mut *document.0 }, Err(ALLOCATION_FAILURE)),
            ALLOCATION_FAILURE
        );
        assert_eq!(document.state(), before);
    }

    #[test]
    fn consecutive_loads_replace_background_and_dimensions_without_history_leaks() {
        let document = Owned::new();
        for input in [
            fixture!("rgba-v3.edupaint").as_slice(),
            fixture!("portrait-v2.edupaint").as_slice(),
            fixture!("empty-square-v2.edupaint").as_slice(),
        ] {
            assert_eq!(document.load(input), 0);
            assert_eq!(document.bytes(), input);
            assert_eq!(unsafe { ep_redo_count(document.0) }, 0);
        }
        assert_eq!(unsafe { ep_stroke_count(document.0) }, 0);
        assert_eq!(unsafe { ep_document_width(document.0) }, 1200);
        assert_eq!(unsafe { ep_document_height(document.0) }, 1200);
        assert_eq!(unsafe { ep_undo_count(document.0) }, 0);
    }
}
