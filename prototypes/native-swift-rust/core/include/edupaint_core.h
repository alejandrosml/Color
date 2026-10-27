#ifndef EDUPAINT_CORE_H
#define EDUPAINT_CORE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

/* Independent feasibility demo: no Tux Paint drawing engine is included.
 * All access to a document must be serialized on one owning thread.
 * EpDocument is opaque and exclusively owned by the caller until freed.
 * Null pointers are handled as documented below; non-null pointers MUST be
 * live, correctly aligned and point to the promised number of initialized
 * elements (or writable elements for outputs). Rust cannot validate dangling
 * pointers. No concurrent document calls, pointer aliasing with document storage,
 * double frees, or use after free. Input points are copied, never retained.
 */
typedef struct EpDocument EpDocument;
typedef struct EpExportSnapshot EpExportSnapshot;
typedef struct EpPoint { float x; float y; } EpPoint;
typedef struct EpStrokeInfo {
    uint32_t rgb;       /* 0x00RRGGBB, opaque sRGB for this demo */
    float width;       /* Document units, not window pixels */
    size_t point_count;
} EpStrokeInfo;
typedef struct EpObjectStyle {
    uint32_t kind;         /* 0 freehand, 1 line, 2 rectangle, 3 ellipse, 4 text, 5 stamp,
                              6 contour */
    uint32_t fill_enabled; /* exactly 0 or 1; only rectangle/ellipse/contour may fill */
    uint32_t fill_rgb;     /* 0x00RRGGBB; must be zero when fill is disabled */
} EpObjectStyle;
/* One layer of the stack, bottom first. object_count is its visible content. */
typedef struct EpLayerInfo {
    uint32_t id;       /* stable within the document, 0..15 */
    uint32_t visible;  /* exactly 0 or 1 */
    size_t object_count;
} EpLayerInfo;
/* Layer, catalogue/font parameter and character count of one object. */
typedef struct EpObjectExtra {
    uint32_t layer;    /* identifier of the owning layer */
    uint32_t param;    /* stamp identifier, text font, zero otherwise */
    size_t text_bytes; /* UTF-8 length of a text, zero otherwise */
} EpObjectExtra;

/* Immutable normalized PNG background, separate from vector object indices. */
typedef struct EpBackgroundInfo {
    uint32_t width;
    uint32_t height;
    size_t byte_count;
} EpBackgroundInfo;
#define EP_MAX_BACKGROUND_BYTES ((size_t)71303168)
#define EP_MAX_BACKGROUND_DIMENSION ((uint32_t)8192)
#define EP_MAX_BACKGROUND_PIXELS ((uint64_t)16777216)
/* Copies a canonical PNG into a NEW document whose size equals the image.
 * NULL on failure; optional out_status: 0 success, -1 invalid, -2 allocation.
 * PNG policy: RGB/RGBA 8-bit, noninterlaced, validated chunk order/CRCs,
 * IHDR + contiguous IDAT + IEND; unique pre-IDAT sRGB/gAMA/cHRM/pHYs allowed.
 * gAMA must be 45455 and cHRM must be standard sRGB primaries/white point.
 * APNG, ICC profiles, text/private and unknown chunks are rejected. Normalize
 * source images and color profiles BEFORE calling. No pixel/zlib decoding is
 * performed here: even successful construction/project loading still requires
 * caller-side codec validation BEFORE adopting this candidate document.
 * length <= EP_MAX_BACKGROUND_BYTES; dimensions <=8192 and pixels <=16Mi.
 * Input is copied and can be freed after the call. out_status must be writable,
 * aligned and disjoint from input; status is written on failure as documented.
 * Background is immutable, never undoable, and unaffected by vector edits.
 * Its pixels/buffers use fallible allocations. The small std::sync::Arc control
 * allocation at PNG import/project load cannot report failure on stable Rust:
 * an OOM at that allocation aborts the process. Snapshot creation only clones
 * the existing Arc and does not allocate/copy background storage.
 */
EpDocument *ep_document_from_background_png(const uint8_t *bytes, size_t length,
                                           int32_t *out_status);
/* 1 present (writes metadata), 0 absent (output unchanged), -1 invalid pointers
 * (output unchanged). No allocation or document mutation. */
int32_t ep_background_info(const EpDocument *document, EpBackgroundInfo *out_info);
/* Copies complete PNG; returns its byte count, or 0 absent/invalid/too small.
 * No partial writes; excess capacity unchanged. Output disjoint from document. */
size_t ep_copy_background_png(const EpDocument *document, uint8_t *out_bytes,
                              size_t capacity);

/* Dimensions 1..16384 document units; NULL on invalid input/allocation failure. */
EpDocument *ep_document_new(uint32_t width, uint32_t height);
/* Accepts NULL. Consumes precisely one pointer returned by any document constructor. */
void ep_document_free(EpDocument *document);
/* Return 0 for NULL. */
uint32_t ep_document_width(const EpDocument *document);
uint32_t ep_document_height(const EpDocument *document);
size_t ep_stroke_count(const EpDocument *document);
/* Historic stroke/count/info/points APIs now enumerate every visible vector
 * object. Their signatures/layouts are unchanged. New renderers must query
 * ep_object_style to distinguish a shape's two control points from freehand.
 */
size_t ep_redo_count(const EpDocument *document);
/* Number of undoable commands, independent of visible object count. */
size_t ep_undo_count(const EpDocument *document);
/* Nonzero content-state token unique within one document; 0 for NULL/invalid
 * index. Add/duplicate/move/resize/restyle, a replaced text and a change of
 * layer receive new tokens; unchanged objects retain their tokens when indices
 * shift. Undo/redo restore the exact state token;
 * tokens of discarded redo branches are never reused. No-op/failure preserves
 * tokens. Safe for immutable rendering caches scoped to this document only:
 * clear such caches on document replacement/load. Tokens are not serialized.
 * Exhausting uint64_t tokens rejects a new content edit with -1, not wrapping.
 */
uint64_t ep_object_revision(const EpDocument *document, size_t index);

/* Returns 0 on success, -1 invalid input/limits, -2 allocation failure.
 * points: 1..100000 finite points inside [0,width] x [0,height].
 * width: finite 0.1..512; rgb: 24 bits. Demo limit: 10000 active strokes,
 * 1000000 active points. Successful add clears redo. Failure leaves the
 * drawing/history unchanged. Input array must remain valid during the call.
 */
int32_t ep_add_stroke(EpDocument *document, const EpPoint *points,
                      size_t count, uint32_t rgb, float width);
/* Copies exactly two points and style. kind must be 1..3. Lines use endpoints;
 * rectangle/ellipse use opposite bounding-box corners in either order.
 * Zero-length line / zero-width or zero-height box is rejected. Bounds, RGB,
 * width, allocation and history guarantees match ep_add_stroke. The style and
 * two-point array must be live, stable, aligned and disjoint from document.
 * A contour (kind 6) has three points or more: it is refused here.
 */
int32_t ep_add_shape(EpDocument *document, const EpPoint *points,
                     const EpObjectStyle *style, uint32_t rgb, float width);
/* CONTOURS. A contour is a visible object of kind 6: a closed polygon of 3 to
 * 100000 points inside the page, the last joined to the first, whose box (the
 * smallest and largest x and y of its points) has a non-zero width and height.
 * Outline colour and width as a line (0.1..512); fill_enabled 0 or 1 with
 * fill_rgb as a rectangle; no parameter, no text. No function draws a new
 * one: the zones and lines of a colouring page are contours, and a v5 project
 * brings them; duplicating a contour of a layer that is not locked
 * (ep_duplicate_object) copies it. A contour is a list of points like a
 * freehand stroke for every other function: ep_copy_points gives all its
 * points, moving, constraining, resizing and duplicating take all of them,
 * and a move or a resize that would bring its box to a zero width or height
 * in f32 is refused. Exported as <path d="M x y L x y ... Z"> with the fill
 * and outline attributes of a rectangle; the default nonzero fill rule
 * applies.
 */
/* Object editing uses current visible indices. New editing functions return
 * 1 changed, 0 no-op, -1 invalid input/limits, -2 allocation failure. No-op and
 * failure preserve the drawing, undo and redo; success clears redo.
 * All edits, adds and loaded objects use the same reversible command history.
 * Limits: 50000 commands, 20000 retained objects, 2000000 retained points,
 * including geometry detached by deletion/undo. Active limits remain 10000
 * objects / 1000000 points. Hitting a limit rejects an edit atomically; it does
 * not discard old undo commands. Save/reopen retains the visible drawing but
 * starts a new history consisting of one add per loaded object outside a
 * locked layer: the objects of locked layers (a colouring page) are not in
 * the history, so that no undo takes them away.
 * Every editing function refuses (-1, nothing changed) an object of a locked
 * layer: see LAYERS below for the rules and the one exception.
 * Undo/redo transfer ownership or swap constant-size values without allocating
 * or copying point arrays. Move stores a double-precision translation and
 * restores its exact previous value on undo; exported coordinates remain f32.
 */
/* dx/dy finite; all translated control points must stay within page bounds.
 * Invalid moves are rejected, never clipped. Rounded degenerate shapes are
 * rejected. Movement too small to change any output point is a no-op.
 */
/* Nonmutating helper for UI movement constraints. Computes bounds from exact
 * internal coordinates and rounds the resulting f32 delta toward the interior.
 * This avoids false rejection when displayed f32 positions round toward the
 * page interior. Returns 0 success, -1 invalid pointers/index/nonfinite input,
 * an object of a locked layer (which never moves) or a rounded-degenerate
 * shape. Writes one EpPoint only on success; document,
 * revisions, history and output on failure are unchanged. Output must be live,
 * writable, aligned and disjoint from document-owned storage. Apply this result
 * immediately on the same serialized document thread. Strict move/duplicate
 * functions below retain their existing reject-without-clipping contract.
 */
int32_t ep_constrain_object_movement(const EpDocument *document, size_t index,
                                    float dx, float dy, EpPoint *out_delta);
int32_t ep_move_object(EpDocument *document, size_t index, float dx, float dy);
/* Resizes one object by factor (1/64..64) around the centre of its points,
 * then moves it just enough to keep every point on the page; points are never
 * clipped one by one. width is the outline width it gets (0.1..512; the caller
 * decides whether outlines follow the size); a stamp keeps exactly 1.0. Texts
 * are refused: their box follows their characters, see ep_set_text. One
 * reversible command of constant size: base points are not rewritten.
 * An object whose points all coincide (a dot) has no size: only its width
 * changes, any number of times. An object that has a size never loses it: a
 * factor that would bring all its points together is refused, like one that
 * would take the product of all the factors it has received outside
 * 1e-9..1e9.
 * Returns 1 changed, 0 nothing to change (factor 1, or a dot, with the width
 * it already has), -1 invalid input / object that would not fit the page /
 * object that would lose its width, its height or its extent / limits,
 * -2 allocation failure. No-op and failure keep drawing, undo and redo. A
 * success is one undo step and a new revision even when the change is too
 * small to move a rounded coordinate.
 */
int32_t ep_scale_object(EpDocument *document, size_t index, float factor, float width);
/* Moves from to the final visible index to; both must be < ep_stroke_count.
 * 0 is backmost and count-1 frontmost, always above the immutable background.
 * Other objects retain their relative order; no geometry/style/revision changes.
 * Same valid index returns 0 before history-limit checks; invalid indices return
 * -1, including an empty document. No-op/failure preserves redo and snapshots.
 * History stores two inverse indices. Order/undo/redo move only object
 * descriptors (O(distance), at most 10000), never copy point arrays. A new edit
 * may allocate history capacity and release discarded redo-owned geometry.
 * Project format is unchanged: existing records already encode visible order.
 */
int32_t ep_reorder_object(EpDocument *document, size_t from, size_t to);
int32_t ep_remove_object(EpDocument *document, size_t index);
/* Appends an independent translated copy; dx=dy=0 still creates a copy. */
int32_t ep_duplicate_object(EpDocument *document, size_t index, float dx, float dy);
/* Keeps kind unchanged. RGB/width/fill validation matches add_shape; freehand
 * and lines require fill_enabled=0, fill_rgb=0; a contour may fill like a
 * rectangle. Identical style is a no-op. On an object of a locked layer only
 * the paint pot's change is accepted: an object whose fill is enabled may get
 * another fill_rgb, with its current rgb and width passed back unchanged and
 * fill_enabled 1 (a new revision, one undo step); anything else is -1.
 */
int32_t ep_set_object_style(EpDocument *document, size_t index, uint32_t rgb,
                           float width, uint32_t fill_enabled, uint32_t fill_rgb);
/* For a text or a stamp only the colour changes here: width must equal the
 * object's current EpStrokeInfo.width (text size, or 1 for a stamp) and fill
 * stays disabled. ep_set_text replaces a text's size together with its box.
 */

/* TEXT. A text is one visible object of kind 4 with exactly two points: opposite
 * corners of its laid-out box, inside the page, non-zero width and height. The
 * caller measures the characters with font 0 (DejaVu Sans, line height 1.2 x
 * size) and supplies the box; the core never measures glyphs. Lines start at
 * the box's top-left corner. EpStrokeInfo.width reports the text size.
 * size: finite, 4..2048 document units. font: must be 0. utf8: 1..2048 bytes of
 * valid UTF-8, at most 32 lines separated by U+000A, at least one character
 * that leaves a mark: neither white space nor one of Unicode's
 * Default_Ignorable_Code_Point (soft hyphen, zero-width spaces and joiners,
 * direction marks, variation selectors, U+FEFF, tags), which stay allowed
 * beside such a character and are stored as given. Other controls,
 * U+2028/U+2029 and characters invalid in XML 1.0
 * are rejected (normalize tabs and CR/LF before calling). No NUL terminator is
 * read or required. Visible texts hold at most 1 MiB, retained history 2 MiB.
 * Returns 0 on success, -1 invalid input/limits, -2 allocation failure. Failure
 * leaves drawing/history unchanged; success clears redo. Inputs are copied and
 * must stay live, unchanged and disjoint from the document during the call.
 */
#define EP_MAX_TEXT_BYTES ((size_t)2048)
int32_t ep_add_text(EpDocument *document, const EpPoint *box_points, uint32_t rgb,
                    float size, uint32_t font, const uint8_t *utf8, size_t length);
/* Replaces box, colour, size, font and characters of the text at index in ONE
 * reversible command. Validation as ep_add_text. Returns 1 changed, 0 identical
 * content, -1 invalid input / not a text / limits, -2 allocation failure.
 */
int32_t ep_set_text(EpDocument *document, size_t index, const EpPoint *box_points,
                    uint32_t rgb, float size, uint32_t font, const uint8_t *utf8,
                    size_t length);
/* Copies the complete UTF-8 of a text, without terminator. Returns its byte
 * count, or 0 for invalid document/index, an object without text, NULL output
 * or insufficient capacity. No partial write. Output disjoint from document. */
size_t ep_copy_object_text(const EpDocument *document, size_t index,
                           uint8_t *out_bytes, size_t capacity);
/* Returns 0 success, -1 invalid arguments. Output unchanged on error. */
int32_t ep_object_extra(const EpDocument *document, size_t index, EpObjectExtra *out_extra);

/* STAMPS. A stamp is one visible object of kind 5 referencing a drawing of the
 * built-in catalogue, scaled into the box of its two corner points and tinted
 * with its rgb. The catalogue is the only source of the artwork for both the
 * interface and SVG exports; projects store the identifier, never the paths.
 * Identifiers are stable: stamps are appended, never reordered or removed.
 * The catalogue belongs to the project format: version 4 knows exactly the
 * stamps 0..23, and a longer catalogue must come with a later format version,
 * so that an older reader reports a newer file instead of an invalid one.
 */
uint32_t ep_stamp_count(void);
/* Whole catalogue as owned NUL-terminated ASCII, NULL on allocation failure.
 * One line per stamp in identifier order: id|key|layer;layer;... where a layer
 * is fill,stroke,width,path. Paints: - none, P colour, D shade (7/10 of each
 * channel), L tint (channel + 6/10 of its distance to 255), or #rrggbb. Paths
 * use absolute M L C Q Z on a 100 x 100 grid, numbers separated by spaces.
 * The grid is mapped onto the object's box; coordinates run from -2 to 102
 * and outlines are up to 8 wide, so a drawing may pass its box by a few
 * hundredths of its size. Release ONLY with ep_string_free. */
char *ep_stamp_catalog(void);
/* box_points: two opposite corners inside the page, non-zero width and height.
 * stamp < ep_stamp_count(); rgb 24 bits. Same return values, history and input
 * guarantees as ep_add_shape. EpStrokeInfo.width of a stamp is always 1. */
int32_t ep_add_stamp(EpDocument *document, const EpPoint *box_points,
                     uint32_t stamp, uint32_t rgb);

/* LAYERS. A document owns 1..16 layers, bottom first. Every object belongs to
 * one layer (EpObjectExtra.layer). Painting order is layer by layer, and inside
 * a layer by visible index; ep_reorder_object therefore reorders an object
 * among the objects of its own layer. New objects join the ACTIVE layer;
 * duplicates stay on their source's layer. A hidden layer keeps its objects in
 * the project but is omitted from SVG exports; the interface omits it too.
 * Add / remove / reorder / show-hide / move-to-layer are ordinary reversible
 * commands with the limits and all-or-nothing guarantees of object edits. The
 * active layer is a view state: saved in the project, never part of history,
 * although undoing a layer addition/removal returns to the previously active
 * layer. Positions are indices in the stack; identifiers are stable handles
 * while the document lives, and are kept by a version 4 or 5 project. The
 * older formats have no layer table: a drawing reduced to one plain layer is
 * written in them and reopens with that layer as number 0.
 * A layer may be LOCKED: the zones and the lines of a colouring page are.
 * Only ep_document_from_page and a version 5 project make one, and no
 * function locks or unlocks a layer. The core keeps a page whole whatever the
 * interface asks (-1, drawing and history unchanged): a locked layer is never
 * the active layer, never removed and never moved, and NO OTHER LAYER PASSES
 * IT: a layer is reordered only among the layers between the same two locked
 * layers, and a new layer comes just above the active one, so the child's
 * drawing stays above a page's zones and below its lines. A locked layer may
 * be hidden and shown; its objects are never removed, moved or constrained,
 * resized, reordered (as `from`), duplicated, sent to another layer,
 * rewritten (ep_set_text) or restyled, and no object joins it. One
 * exception, the paint pot's: ep_set_object_style may change the colour of a
 * fill that such an object already has. The objects of locked layers are not
 * in the history: undo never takes them away.
 */
size_t ep_layer_count(const EpDocument *document); /* 0 for NULL */
/* 0 success, -1 invalid document/position/output; no partial write. */
int32_t ep_layer_info(const EpDocument *document, size_t position, EpLayerInfo *out_info);
/* Lock of the layer at position: 1 locked, 0 not, -1 NULL or position outside
 * the stack. Added beside EpLayerInfo, whose layout is unchanged. */
int32_t ep_layer_locked(const EpDocument *document, size_t position);
uint32_t ep_active_layer(const EpDocument *document); /* identifier; UINT32_MAX for NULL */
/* 0 success, -1 NULL, unknown identifier or locked layer. Not an edit: history
 * unchanged. */
int32_t ep_set_active_layer(EpDocument *document, uint32_t id);
/* Adds an empty visible layer, never locked, just above the active one and
 * activates it. 1 changed, -1 NULL / sixteen layers / limits, -2 allocation
 * failure. */
int32_t ep_add_layer(EpDocument *document);
/* Removes a layer WITH its objects; undo restores both at their exact indices
 * without copying point arrays. The last layer cannot be removed, nor a locked
 * layer, nor the last layer that is not locked. If it was active, the nearest
 * layer that is not locked becomes active: the one below first, then above
 * (without locked layers: the layer below, or the new bottom).
 * 1 changed, -1 invalid position / last layer / locked layer / last unlocked
 * layer / limits, -2 allocation. */
int32_t ep_remove_layer(EpDocument *document, size_t position);
/* Moves the layer at `from` to the final position `to`; the others keep their
 * order. Refused when a locked layer lies anywhere from `from` to `to`, both
 * included: locked layers keep their places and no layer passes one; the
 * layers between two locked layers are reordered among themselves.
 * 1 changed, 0 same position, -1 invalid / a locked layer in the way /
 * limits, -2 allocation. */
int32_t ep_reorder_layer(EpDocument *document, size_t from, size_t to);
/* visible exactly 0 or 1, locked layers included. 1 changed, 0 unchanged,
 * -1 invalid/limits, -2 allocation. */
int32_t ep_set_layer_visible(EpDocument *document, size_t position, uint32_t visible);
/* Moves an object to another layer, in front of that layer's objects: it becomes
 * the last visible index and receives a new revision. Nothing leaves or joins
 * a locked layer. 1 changed, 0 already there, -1 invalid index/layer/locked
 * layer/limits, -2 allocation. */
int32_t ep_set_object_layer(EpDocument *document, size_t index, uint32_t layer);
/* Colour of the sheet under the whole drawing, 24-bit RGB; white (0xffffff)
 * for a new document and for every v1/v2/v3 project; UINT32_MAX for NULL.
 */
uint32_t ep_paper_color(const EpDocument *document);
/* Changes the colour of the sheet: one reversible command. Exports paint it
 * first, under an image background when there is one. Returns 1 changed,
 * 0 same colour, -1 NULL / not a 24-bit colour / limits, -2 allocation
 * failure. Objects, their indices and revisions are untouched.
 */
int32_t ep_set_paper_color(EpDocument *document, uint32_t rgb);
/* Return 1 changed, 0 no operation, -1 NULL document. */
int32_t ep_undo(EpDocument *document);
int32_t ep_redo(EpDocument *document);
/* Return 0 success, -1 invalid document/index/output. Output unchanged on error. */
int32_t ep_stroke_info(const EpDocument *document, size_t index, EpStrokeInfo *out_info);
/* Returns 0 success, -1 invalid arguments. Output unchanged on error. */
int32_t ep_object_style(const EpDocument *document, size_t index, EpObjectStyle *out_style);
/* Copies the complete stroke. Returns count, or 0 for invalid/null input or
 * insufficient capacity. No partial writes. out_points must provide capacity
 * writable, aligned EpPoint slots, disjoint from document and other inputs.
 */
size_t ep_copy_points(const EpDocument *document, size_t index,
                      EpPoint *out_points, size_t capacity);
/* Returns an owned UTF-8, NUL-terminated SVG, or NULL on failure. Includes the
 * sheet's colour, embedded PNG data URI when present, then vector objects, and a
 * stable document viewBox. SVG is hybrid when an image is embedded. With several
 * layers (or a hidden one) each VISIBLE layer becomes a <g id="calque-N"> group,
 * bottom first, N being the layer's identifier plus one; a drawing with one
 * visible layer has no group. Texts are real
 * <text> elements, one <tspan> per line with an explicit baseline; stamps are
 * catalogue paths in a scaled group. Release ONLY with ep_string_free;
 * never with free(), and never modify/reallocate the returned buffer.
 */
char *ep_export_svg(const EpDocument *document);
/* Accepts NULL; otherwise consumes exactly one string returned by export. */
void ep_string_free(char *string);

/* Experimental little-endian EduPaint: v1/v2/v3/v4/v5 input. Output is v2
 * without a background (byte-for-byte compatible) and v3 with one, as long as
 * the drawing has a single visible layer, a white sheet and neither text,
 * stamp, contour nor locked layer; otherwise v4, or v5 as soon as the drawing
 * has a locked layer or a contour.
 * Visible objects only; editing history excluded. V3: 48-byte header, v2 object
 * records, PNG, final CRC32. Background dimensions must equal document and PNG
 * IHDR. V1/v2/v3 retain their own smaller size bounds.
 * V4: 56-byte header (magic, version 4, flags 0, total size, width, height,
 * object count, point count, PNG byte count or 0, layer count, text byte
 * count, active layer id, the sheet's colour, one reserved zero word; the
 * colour word is 0 for a white sheet and 0x01000000 | rgb otherwise, white
 * never being written with the marker), then one {id, visible}
 * pair of u32 per layer bottom first, then for each object a 36-byte record
 * {rgb, width, point count, kind, fill enabled, fill rgb, layer id, param,
 * text byte count} followed by its points and its UTF-8, then the optional
 * PNG and the final CRC32. A stamp identifier unknown to this core is rejected.
 * A version 4 file that uses none of these features is accepted, and written
 * back in the older format like any drawing that does not need version 4.
 * V5: everything of v4 (header, sizes, limits, records, stamps 0..23) with
 * version 5, and two additions. The second word of each layer entry is a set
 * of flags: bit 0 visible, bit 1 locked, every other bit zero (in v4 it stays
 * exactly 0 or 1); the active layer must not be a locked one. A record may be
 * of kind 6, a closed contour, in v5 only: 3 points or more, fill enabled 0
 * or 1 with its fill rgb as for a rectangle, outline width 0.1..512, param 0,
 * no text, and the box of its points (smallest to largest x, and y) of
 * non-zero width and height. V5 is written exactly when the document has a
 * locked layer or a contour (on any layer, shown or hidden); a v5 file with
 * neither is accepted, and written back as v4 or older like any drawing.
 * Backgroundless documents remain valid up to 16384 document units per axis.
 * Unknown versions (above 5)/flags/encodings are rejected, never silently
 * interpreted.
 */
#define EP_MAX_VECTOR_PROJECT_BYTES ((size_t)8240036)
#define EP_MAX_HYBRID_PROJECT_BYTES ((size_t)79543220)
#define EP_MAX_PROJECT_BYTES ((size_t)80711932)
/* Exact required capacity; 0 for NULL. No allocation/mutation. */
size_t ep_project_size(const EpDocument *document);
/* 0 success; -1 NULL/insufficient capacity, output unchanged on error.
 * Writes exactly ep_project_size bytes into caller-owned storage, leaving
 * excess capacity untouched. Buffer must be disjoint from document storage.
 */
int32_t ep_copy_project(const EpDocument *document, uint8_t *out_bytes, size_t capacity);
/* Validate first, then create a NEW document; never modifies another document.
 * NULL on failure. Optional out_status: 0 success, -1 invalid/unsupported/
 * corrupt file or limits, -2 allocation failure. Input remains unchanged.
 * length must be 36..EP_MAX_PROJECT_BYTES; bytes live and unchanged during call.
 * out_status, if supplied, must be writable/aligned and disjoint from bytes.
 * New document supports undo of every loaded object outside a locked layer,
 * last first; no redo initially. Objects of locked layers are not undoable.
 * Release its single ownership with ep_document_free, never C free().
 */
EpDocument *ep_document_from_project(const uint8_t *bytes, size_t length, int32_t *out_status);

/* Transactionally fills an already-owned candidate, retaining its address and
 * owner. Returns 0 on success, -1 invalid input, -2 allocation failure. Failure
 * preserves all previous content/history. The caller must exclusively borrow
 * candidate for the entire call; no concurrent access or destruction, and bytes
 * must not alias any candidate-owned storage. A cross-thread borrower must stop
 * before the owner accesses/frees candidate again. Decode PNG pixels before UI
 * adoption; native validation is structural only. */
int32_t ep_document_load_project(EpDocument *candidate, const uint8_t *bytes, size_t length);

/* Immutable autonomous export snapshot. Capture must run on the document owner
 * thread with no overlapping document calls. It copies the objects of the
 * drawing, those of hidden layers included since the project keeps them, and
 * nothing of the history (<=10000 objects / 1000000 points, at most 8 MB of
 * point payload and 1 MiB of text), with the layer table and the sheet's
 * colour. It preserves
 * transforms/style and shares immutable PNG storage by atomic reference count.
 * No undo/redo payload is copied. New captures allocate independently; callers
 * MUST bound outstanding snapshots rather than queue an unbounded series.
 * NULL on failure; optional out_status: 0 success, -1 NULL/invalid, -2 allocation.
 * Snapshot allocations and vector buffers are fallible, with no source changes.
 * out_status must be writable/aligned and disjoint from source storage.
 *
 * After synchronized publication, snapshot reads may run on any thread, even
 * simultaneously, while the original document is edited/freed on its owner
 * thread. The snapshot is immutable and NEVER exposes a mutable document handle.
 * The single owner MUST retain it until every worker has completed or failed
 * and can no longer access it. An Isolate.run worker may borrow this pointer;
 * its parent retains ownership and frees it only after that worker's completion.
 * Independent read calls require disjoint writable output buffers. Returned SVG
 * strings own their allocation independently and use ep_string_free.
 */
EpExportSnapshot *ep_export_snapshot_new(const EpDocument *document, int32_t *out_status);
/* NULL no-op. Consume exactly once, with NO overlapping snapshot calls/readers. */
void ep_export_snapshot_free(EpExportSnapshot *snapshot);
/* Exact byte count, zero for NULL. No allocation or mutation. */
size_t ep_export_snapshot_project_size(const EpExportSnapshot *snapshot);
/* Same bytes as ep_copy_project at capture time. 0 success, -1 invalid/too small.
 * No partial writes on error; bytes beyond required size remain unchanged. */
int32_t ep_export_snapshot_copy_project(const EpExportSnapshot *snapshot,
                                       uint8_t *out_bytes, size_t capacity);
/* Same SVG as ep_export_svg at capture time. NULL failure, owned UTF-8 otherwise. */
char *ep_export_snapshot_export_svg(const EpExportSnapshot *snapshot);

/* SOUNDS. Small sounds of the interface. Most are rendered by this core from
 * recipes of its own: sine partials, envelopes and the noise of its own
 * generator. The pencil, the eraser, the typewriter and the selection of an
 * element play a short recording instead: a WAV file compiled into the core,
 * prepared from a recording dedicated to the public domain by its author
 * (CC0); sons/PROVENANCE.md says where each one comes from, and
 * ep_third_party_notices credits them. Nothing comes from Tux Paint or EduPaint.
 * Each sound is mono, signed 16-bit, 44100 Hz, at most one second, and is
 * handed out as a complete WAV file: a 44-byte RIFF/fmt/data header, then the
 * samples. The first and the last sample are zero, the samples sum to zero
 * within rounding, the peak is at most -10 dBFS (-16 dBFS for noise, for the
 * recordings and for the tick of a stroke). Rendering uses IEEE 754 double
 * arithmetic only, never the math library of the system: the bytes of a sound
 * are meant to be the same on x86-64 and ARM64, and a test pins their
 * checksums.
 * Identifiers are positions in the list and are stable: sounds are appended,
 * never reordered or removed. This core knows 0..17:
 *  0 outil       a tool or a button is chosen     9 feuille     a new sheet
 *  1 couleur     a colour is chosen              10 enregistre  the drawing was saved
 *  2 trait       a stroke is finished            11 oups        a notice
 *  3 forme       a line/rectangle/oval is placed 12 film        the replay starts
 *  4 tampon      a stamp is placed               13 bravo       the replay is finished
 *  5 pot         the paint pot fills something   14 clic        first click of two
 *  6 gomme       the eraser removes an element   15 texte       a text is placed
 *  7 annuler     undo                            16 choisir     an element is selected
 *  8 retablir    redo                            17 imprime     a print was sent
 * These functions use no document and are exempt from the one-thread rule above:
 * any thread may call them at any time, also concurrently.
 */
uint32_t ep_sound_count(void);
/* Names as owned NUL-terminated ASCII, NULL on allocation failure. One line per
 * sound in identifier order: id|key. Release ONLY with ep_string_free. */
char *ep_sound_names(void);
/* Exact byte count of the WAV file of a sound; 0 for an unknown identifier.
 * No rendering, no allocation. */
size_t ep_sound_wav_size(uint32_t id);
/* Copies the complete WAV file; returns its byte count, or 0 for an unknown
 * identifier, NULL output, capacity below ep_sound_wav_size or exhausted
 * memory. No partial write; excess capacity unchanged. The first use of a
 * sound renders it, in a few milliseconds; its bytes never change afterwards. */
size_t ep_copy_sound_wav(uint32_t id, uint8_t *out, size_t capacity);
/* Starts playing a sound through the system and returns without waiting for
 * its end. 0 handed to the system (which is not a promise that it is heard),
 * 1 no player here: the caller plays the WAV bytes itself, -1 unknown
 * identifier.
 * Windows: PlaySoundW of winmm, from memory and asynchronous; a new sound
 * interrupts the previous one. Under Wine such a call waits a few milliseconds
 * for winmm to stop the old sound; Windows itself was not measured.
 * The first use of a sound renders it on the calling thread: copy the sounds
 * once at start-up to have that done before.
 * Linux: ALSA (libasound.so.2, loaded at run time) on a short-lived thread per
 * sound, which is the one that opens and writes the device; device `default`,
 * or the value the environment variable COLOR_ALSA_DEVICE had at the first
 * call. At most four sounds play at once: beyond that, and when the device
 * takes more than a second to open, the sound is dropped and 0 is still
 * returned. Once the library, one of its functions or the device is found
 * missing, which only the thread of the first sound can discover, every later
 * call returns 1 until the process ends: nothing is tried again.
 * macOS and every other system: always 1.
 * The library must stay loaded while a sound may still be playing.
 */
int32_t ep_sound_play(uint32_t id);

/* Pictures read from SVG. Present only in a core built with its `svg`
 * feature, which is how cargo builds it; a core compiled by rustc alone from
 * src/lib.rs has none of these three functions.
 * A picture is described as ASCII text, one instruction per line:
 *   P <key> <width> <height>   opens a picture; X ends it
 *   G <opacity> <matrix|->     opens a group; E ends it
 *   C, then K <n|e> <outline>  clips of the group just opened: several C
 *                              sections intersect, the K outlines of one C
 *                              are joined
 *   D <f|s> <fill> <stroke> <outline>   one drawn outline, fill first (f) or
 *                              stroke first (s); fill is - or <paint>,<n|e>;
 *                              stroke is - or <paint>,<width>,<cap><join>,<miter>
 * with paints #rrggbbaa, L:... (linear gradient) or R:... (radial gradient)
 * and outlines in absolute M L Q C Z. The exact grammar is documented in
 * src/art.rs. Masks, filters, patterns, blend modes, embedded images and text
 * are not drawn: an SVG that uses one of them is refused whole.
 * These functions use no document: any thread may call them. */
uint32_t ep_art_count(void);
/* Every picture of the interface compiled into the core, one description
 * after the other, in the order of their keys. NULL on allocation failure.
 * Release ONLY with ep_string_free. */
char *ep_art_catalog(void);
/* The description of one SVG text of len bytes, with the key `-`. NULL for a
 * NULL pointer, more than 1 MiB, text that is not UTF-8, an SVG that cannot
 * be read or that uses what is not drawn, or exhausted memory. No file is
 * opened and nothing is fetched, whatever the SVG refers to. The bytes are
 * only read. Release ONLY with ep_string_free. */
char *ep_picture_from_svg(const uint8_t *svg, size_t len);

/* COLOURING PAGES. Original drawings compiled into the core. A page makes a
 * NEW document of its size with three layers, bottom to top:
 *   identifier 1, locked: its ZONES, a copy of every filled element (filled
 *     rectangle, ellipse or closed path) filled with white (#ffffff), outline
 *     white (0x00ffffff) and 0.1 wide so that only the fill shows;
 *   identifier 0, active, empty: the DRAWING of the child;
 *   identifier 2, locked: its LINES, the outline of every element with the
 *     colour and width of the page and no fill (filled elements again, lines,
 *     freehand details, open paths and unfilled shapes) WITHOUT what the file
 *     paints over it: the parts of an outline that lie strictly inside a
 *     filled element drawn after it are taken away, so that the document
 *     looks like the file although all its lines lie above its zones. An
 *     outline of which nothing is hidden keeps its kind; one that loses a part
 *     becomes the freehand strokes left (kind 0, two points or more), an
 *     ellipse flattened into 32 to 256 points. Computed once when the core
 *     reads the page, the same on every machine.
 * Each in the order of the page's file. Paint goes under the lines and over
 * the zones; the paint pot colours a zone with ep_set_object_style, the one
 * change a locked layer accepts (see LAYERS). Zones and lines are rectangles,
 * ellipses, lines, freehand strokes and contours: pages may draw closed and
 * open paths, whose curves are flattened into points when the core reads
 * them. Such a document is saved as project v5. Present only in a core built
 * with its `svg` feature, like the pictures above. Identifiers are positions
 * in this core's catalogue, valid for this library only; a project never
 * stores one. These functions use no existing document: any thread may call
 * them; a document returned belongs to its caller's thread as any other. */
uint32_t ep_page_count(void);
/* Owned NUL-terminated ASCII, NULL on allocation failure. For each page, in
 * identifier order, one line
 *   T <id> <key> <regions> <details> <title>
 * then its thumbnail, described like one picture of ep_art_catalog, from
 * P <key> <width> <height> to X; width and height are those of the sheet the
 * page needs. <regions> counts its filled elements, the zones; <details> its
 * other elements: lines, polylines, open paths and unfilled shapes; both
 * count elements of the file, not the lines of its document. <title>,
 * the rest of the line, is the UTF-8 of the French title with every byte
 * outside printable ASCII, and `%` itself, written %XX (two capital
 * hexadecimal digits). Release ONLY with ep_string_free. */
char *ep_page_catalog(void);
/* A NEW document for page `page`, made as described above, or NULL for an
 * unknown page or exhausted memory. Nothing of the page is in the history:
 * the document starts with no undo step (ep_undo_count 0). Ownership as
 * ep_document_new: one owner, released with ep_document_free. */
EpDocument *ep_document_from_page(uint32_t page);

/* The notices of what this core is built from, as owned NUL-terminated
 * UTF-8: entries separated by a line of eighty hyphens. First the libraries,
 * each entry the name of a library, an empty line, then its version, the
 * licence it is taken under and the text of that licence; then the recorded
 * sounds, each entry « Sons enregistrés », an empty line, then the sound, the
 * page its recording comes from and its licence. A core built without
 * libraries names only its recordings; NULL on allocation failure. Uses no
 * document: any thread may call it. Release ONLY with ep_string_free. */
char *ep_third_party_notices(void);

#ifdef __cplusplus
}
#endif
#endif
