// SPDX-License-Identifier: MIT
//! Version 6 of the project (Color 1.1), as docs/FORMAT-PROJET.md describes
//! it: a header with its own CRC, then blocks, each with its CRC — the
//! document, the layers, the objects of each layer (compressed in raw
//! DEFLATE when that makes them smaller), the background — and the CRC of
//! the whole file. Coordinates are integers of 1/2^q unit written as
//! differences, or exact float32 for an object that keeps them so.
//!
//! The writer writes into the caller's memory, after `bound` has said how
//! much it may need; only the compression borrows memory of its own, and
//! without it a block is simply kept as it is. The reader checks everything
//! before it gives a document, like the reader of the older versions; a
//! damaged file can still give back its intact layers (`load_damaged`).

use super::*;

pub(crate) const VERSION: u16 = 6;
const HEADER_BYTES: usize = 32;
const BLOCK_HEADER_BYTES: usize = 20;
const DOC_BYTES: usize = 24;

const TAG_DOC: [u8; 4] = *b"DOC6";
const TAG_LAYERS: [u8; 4] = *b"LAYS";
const TAG_OBJECTS: [u8; 4] = *b"OBJS";
const TAG_BACKGROUND: [u8; 4] = *b"BKGD";

const STORED: u8 = 0;
const DEFLATED: u8 = 1;

// The indicators of an object record.
const FILL: u32 = 1;
const GRADIENT: u32 = 1 << 1;
const ROTATION: u32 = 1 << 2;
const MIRROR: u32 = 1 << 3;
const TOOL: u32 = 1 << 4;
const SEED: u32 = 1 << 5;
const PRESSURES: u32 = 1 << 6;
const RINGS: u32 = 1 << 7;
const KNOWN_FLAGS: u32 = (1 << 8) - 1;

// The most an object record takes beside its points, its rings and its text:
// place, type, flags, colour, width, parameter, fineness, point count, fill,
// gradient, rotation, mirror, tool, seed, ring count, text length.
const RECORD_FIXED_BYTES: usize = 5 + 1 + 5 + 3 + 4 + 5 + 1 + 5 + 3 + 20 + 4 + 1 + 5 + 4 + 5 + 5;
// A point: two varints of at most 5 bytes, or two float32; and its pressure.
const POINT_BYTES: usize = 10 + 1;

/// The largest file of version 6 the limits allow: every object at its
/// largest record, every point at its largest, a ring for every three points.
pub(crate) const MAX_BYTES: usize = HEADER_BYTES
    + BLOCK_HEADER_BYTES * (2 + MAX_LAYERS + 1)
    + DOC_BYTES
    + 2 * MAX_LAYERS
    + 6 * MAX_LAYERS
    + MAX_STROKES * RECORD_FIXED_BYTES
    + MAX_TOTAL_POINTS * POINT_BYTES
    + 5 * (MAX_TOTAL_POINTS / 3)
    + MAX_TOTAL_TEXT_BYTES
    + MAX_BACKGROUND_BYTES
    + 4;

// ---------------------------------------------------------------- writing

/// How many bytes `write` may need for this drawing; a few more than the
/// file it writes. Reads the counters and the rings, never the points.
pub(crate) fn bound(doc: &EpDocument) -> usize {
    let background = doc.background.as_ref().map_or(0, |b| b.bytes.len());
    let blocks = 2 + doc.layer_count + usize::from(background != 0);
    let rings: usize = doc.strokes.iter().map(|s| s.extras.rings.len()).sum();
    HEADER_BYTES
        + BLOCK_HEADER_BYTES * blocks
        + DOC_BYTES
        + 2 * doc.layer_count
        + 6 * doc.layer_count
        + doc.strokes.len() * RECORD_FIXED_BYTES
        + doc.active_points * POINT_BYTES
        + 5 * rings
        + doc.active_text_bytes
        + background
        + 4
}

struct Output<'a> {
    bytes: &'a mut [u8],
    cursor: usize,
}

impl Output<'_> {
    // `bound` reserved room for everything; a write past it is a bug, and
    // is refused rather than allowed to panic.
    fn put(&mut self, data: &[u8]) -> Result<(), i32> {
        let end = self.cursor.checked_add(data.len()).ok_or(INVALID)?;
        self.bytes
            .get_mut(self.cursor..end)
            .ok_or(INVALID)?
            .copy_from_slice(data);
        self.cursor = end;
        Ok(())
    }

    fn u8(&mut self, value: u8) -> Result<(), i32> {
        self.put(&[value])
    }

    fn u32(&mut self, value: u32) -> Result<(), i32> {
        self.put(&value.to_le_bytes())
    }

    fn f32(&mut self, value: f32) -> Result<(), i32> {
        self.put(&value.to_le_bytes())
    }

    fn rgb(&mut self, rgb: u32) -> Result<(), i32> {
        self.put(&[(rgb >> 16) as u8, (rgb >> 8) as u8, rgb as u8])
    }

    fn varint(&mut self, mut value: u32) -> Result<(), i32> {
        let mut encoded = [0u8; 5];
        let mut length = 0;
        loop {
            let byte = (value & 0x7f) as u8;
            value >>= 7;
            if value == 0 {
                encoded[length] = byte;
                length += 1;
                break;
            }
            encoded[length] = byte | 0x80;
            length += 1;
        }
        self.put(&encoded[..length])
    }

    fn zigzag(&mut self, value: i32) -> Result<(), i32> {
        self.varint(((value << 1) ^ (value >> 31)) as u32)
    }
}

/// Whether these points, as the file would hold them, keep what their kind
/// needs (Stroke::keeps_its_shape): a moved or resized object, rounded to its
/// fineness, must never become one the reader refuses.
fn keeps_shape_when_rounded(stroke: &Stroke, quant: u8) -> bool {
    let rounded = |index: usize| {
        let point = stroke.point_at(index);
        EpPoint {
            x: quantized(point.x, quant),
            y: quantized(point.y, quant),
        }
    };
    match stroke.style.kind {
        0 => true,
        KIND_CONTOUR => contour_has_area((0..stroke.points.len()).map(rounded)),
        kind => valid_shape_points(kind, &[rounded(0), rounded(1)]),
    }
}

/// The fineness the file gives this object: its own, or a finer one when
/// rounding its visible points to its own would flatten it, or exact.
fn written_quant(stroke: &Stroke) -> u8 {
    let own = stroke.extras.quant;
    if own == EXACT_QUANT || (stroke.scale == 1.0 && stroke.translation == [0.0; 2]) {
        // Never moved: its points are already multiples of its fineness.
        return own;
    }
    (own..=MAX_QUANT)
        .find(|&quant| keeps_shape_when_rounded(stroke, quant))
        .unwrap_or(EXACT_QUANT)
}

fn flags_of(stroke: &Stroke) -> u32 {
    let look = &stroke.extras.look;
    let mut flags = 0;
    if stroke.style.fill_enabled == 1 {
        flags |= FILL;
    }
    if look.gradient != 0 {
        flags |= GRADIENT;
    }
    if look.rotation != 0.0 {
        flags |= ROTATION;
    }
    if look.mirror != 0 {
        flags |= MIRROR;
    }
    if look.tool != TOOL_ROUND {
        flags |= TOOL;
    }
    if scattering_tool(look.tool) {
        flags |= SEED;
    }
    if !stroke.extras.pressures.is_empty() {
        flags |= PRESSURES;
    }
    if !stroke.extras.rings.is_empty() {
        flags |= RINGS;
    }
    flags
}

fn put_object(
    output: &mut Output<'_>,
    stroke: &Stroke,
    place: u32,
    sheet: [u32; 2],
) -> Result<(), i32> {
    let look = &stroke.extras.look;
    let flags = flags_of(stroke);
    let quant = written_quant(stroke);
    output.varint(place)?;
    output.u8(stroke.style.kind as u8)?;
    output.varint(flags)?;
    output.rgb(stroke.rgb)?;
    output.f32(stroke.width)?;
    output.varint(stroke.param)?;
    output.u8(quant)?;
    output.varint(stroke.points.len() as u32)?;
    if quant == EXACT_QUANT {
        for index in 0..stroke.points.len() {
            let point = stroke.point_at(index);
            output.f32(point.x)?;
            output.f32(point.y)?;
        }
    } else {
        let scale = f64::from(1u32 << quant);
        // Visible coordinates lie on the sheet; the clamp only keeps a file
        // valid should that ever not hold.
        let limits = [i64::from(sheet[0]) << quant, i64::from(sheet[1]) << quant];
        let integer = |value: f32, axis: usize| {
            ((f64::from(value) * scale).round() as i64).clamp(0, limits[axis])
        };
        let mut previous = [0i64; 2];
        for index in 0..stroke.points.len() {
            let point = stroke.point_at(index);
            let current = [integer(point.x, 0), integer(point.y, 1)];
            if index == 0 {
                output.varint(current[0] as u32)?;
                output.varint(current[1] as u32)?;
            } else {
                output.zigzag((current[0] - previous[0]) as i32)?;
                output.zigzag((current[1] - previous[1]) as i32)?;
            }
            previous = current;
        }
    }
    if flags & FILL != 0 {
        output.rgb(stroke.style.fill_rgb)?;
    }
    if flags & GRADIENT != 0 {
        output.u8(look.gradient as u8)?;
        output.rgb(look.gradient_rgb)?;
        for value in look.gradient_points {
            output.f32(value)?;
        }
    }
    if flags & ROTATION != 0 {
        output.f32(look.rotation)?;
    }
    if flags & MIRROR != 0 {
        output.u8(look.mirror as u8)?;
    }
    if flags & TOOL != 0 {
        output.varint(look.tool)?;
    }
    if flags & SEED != 0 {
        output.u32(look.seed)?;
    }
    if flags & PRESSURES != 0 {
        output.put(&stroke.extras.pressures)?;
    }
    if flags & RINGS != 0 {
        output.varint(stroke.extras.rings.len() as u32)?;
        for &ring in &stroke.extras.rings {
            output.varint(ring)?;
        }
    }
    if stroke.style.kind == KIND_TEXT {
        output.varint(stroke.text.len() as u32)?;
        output.put(&stroke.text)?;
    }
    Ok(())
}

fn block_header(
    output: &mut Output<'_>,
    tag: [u8; 4],
    stored: usize,
    raw: usize,
    compression: u8,
    crc: u32,
) -> Result<(), i32> {
    output.put(&tag)?;
    output.u32(stored as u32)?;
    output.u32(raw as u32)?;
    output.u8(compression)?;
    output.put(&[0; 3])?;
    output.u32(crc)
}

/// Compresses `raw` in raw DEFLATE when that makes it smaller: the
/// compressed bytes, or None to keep the block as it is — also when the
/// memory for them is missing.
#[cfg(feature = "deflate")]
fn deflated(raw: &[u8]) -> Option<Vec<u8>> {
    use miniz_oxide::deflate::core::{
        compress, create_comp_flags_from_zip_params, CompressorOxide, TDEFLFlush, TDEFLStatus,
    };
    if raw.len() < 64 {
        return None;
    }
    let mut compressed = Vec::new();
    compressed.try_reserve_exact(raw.len() - 1).ok()?;
    compressed.resize(raw.len() - 1, 0);
    // Level 6, raw DEFLATE (window bits < 0): deterministic for one version
    // of miniz_oxide, so that writing what was read gives the same bytes.
    let mut compressor = CompressorOxide::new(create_comp_flags_from_zip_params(6, -15, 0));
    let (status, read, written) =
        compress(&mut compressor, raw, &mut compressed, TDEFLFlush::Finish);
    if status != TDEFLStatus::Done || read != raw.len() || written >= raw.len() {
        return None;
    }
    compressed.truncate(written);
    Some(compressed)
}

#[cfg(not(feature = "deflate"))]
fn deflated(_raw: &[u8]) -> Option<Vec<u8>> {
    None
}

/// Writes the project of version 6 into `bytes` (at least `bound(doc)` of
/// them) and returns its length. `compress` false keeps every block as it
/// is: the file is then larger, still valid, and written without borrowing
/// memory.
pub(crate) fn write(doc: &EpDocument, bytes: &mut [u8], compress: bool) -> Result<usize, i32> {
    let mut output = Output { bytes, cursor: 0 };
    let background = doc.background.as_ref();
    let blocks = 2 + doc.layer_count + usize::from(background.is_some());
    // The header, whose size and CRC come last.
    output.put(PROJECT_MAGIC)?;
    output.put(&VERSION.to_le_bytes())?;
    output.put(&0u16.to_le_bytes())?;
    output.u32(0)?;
    output.u32(doc.width)?;
    output.u32(doc.height)?;
    output.u32(blocks as u32)?;
    output.u32(0)?;

    let mut document = [0u8; DOC_BYTES];
    document[0..4].copy_from_slice(&(doc.strokes.len() as u32).to_le_bytes());
    document[4..8].copy_from_slice(&(doc.active_points as u32).to_le_bytes());
    document[8..12].copy_from_slice(&(doc.active_text_bytes as u32).to_le_bytes());
    document[12..16].copy_from_slice(&paper_word(doc.paper).to_le_bytes());
    document[16] = doc.active_layer;
    document[17] = doc.layer_count as u8;
    document[20..24]
        .copy_from_slice(&(background.map_or(0, |b| b.bytes.len()) as u32).to_le_bytes());
    block_header(
        &mut output,
        TAG_DOC,
        DOC_BYTES,
        DOC_BYTES,
        STORED,
        crc32(&document),
    )?;
    output.put(&document)?;

    let mut layers = [0u8; 2 * MAX_LAYERS];
    for (position, layer) in doc.layers().iter().enumerate() {
        layers[2 * position] = layer.id;
        layers[2 * position + 1] = u8::from(layer.visible) | (u8::from(layer.locked) << 1);
    }
    let layers = &layers[..2 * doc.layer_count];
    block_header(
        &mut output,
        TAG_LAYERS,
        layers.len(),
        layers.len(),
        STORED,
        crc32(layers),
    )?;
    output.put(layers)?;

    for layer in doc.layers() {
        let start = output.cursor;
        // The block header, written again once its payload is known.
        output.put(&[0; BLOCK_HEADER_BYTES])?;
        let payload = output.cursor;
        let count = doc.strokes.iter().filter(|s| s.layer == layer.id).count();
        output.u8(layer.id)?;
        output.varint(count as u32)?;
        let mut previous: Option<usize> = None;
        for (index, stroke) in doc.strokes.iter().enumerate() {
            if stroke.layer != layer.id {
                continue;
            }
            let place = match previous {
                None => index,
                Some(previous) => index - previous - 1,
            };
            put_object(&mut output, stroke, place as u32, [doc.width, doc.height])?;
            previous = Some(index);
        }
        let raw = output.cursor - payload;
        let compressed = if compress {
            deflated(&output.bytes[payload..output.cursor])
        } else {
            None
        };
        let (stored, compression) = match compressed {
            Some(compressed) => {
                output.bytes[payload..payload + compressed.len()].copy_from_slice(&compressed);
                (compressed.len(), DEFLATED)
            }
            None => (raw, STORED),
        };
        let crc = crc32(&output.bytes[payload..payload + stored]);
        output.cursor = start;
        block_header(&mut output, TAG_OBJECTS, stored, raw, compression, crc)?;
        output.cursor = payload + stored;
    }

    if let Some(background) = background {
        block_header(
            &mut output,
            TAG_BACKGROUND,
            background.bytes.len(),
            background.bytes.len(),
            STORED,
            background.crc,
        )?;
        output.put(&background.bytes)?;
    }
    // The size and the header's own CRC, now that both are known; then the
    // CRC of everything, the image's part combined from the CRC it keeps:
    // the large image is not read again.
    let length = output.cursor + 4;
    output.bytes[12..16].copy_from_slice(&(length as u32).to_le_bytes());
    let header_crc = crc32(&output.bytes[..28]);
    output.bytes[28..32].copy_from_slice(&header_crc.to_le_bytes());
    let checksum = match background {
        Some(background) => crc32_combine(
            crc32(&output.bytes[..output.cursor - background.bytes.len()]),
            background.crc,
            background.bytes.len(),
        ),
        None => crc32(&output.bytes[..output.cursor]),
    };
    output.u32(checksum)?;
    Ok(length)
}

// ---------------------------------------------------------------- reading

/// How strictly a file is read: a sound file must be whole and exact; a
/// damaged one gives back what its intact blocks hold.
#[derive(Clone, Copy, PartialEq)]
enum Reading {
    Whole,
    Damaged,
}

struct Input<'a> {
    bytes: &'a [u8],
    cursor: usize,
}

impl<'a> Input<'a> {
    fn take(&mut self, length: usize) -> Result<&'a [u8], i32> {
        let end = self.cursor.checked_add(length).ok_or(INVALID)?;
        let taken = self.bytes.get(self.cursor..end).ok_or(INVALID)?;
        self.cursor = end;
        Ok(taken)
    }

    fn u8(&mut self) -> Result<u8, i32> {
        Ok(self.take(1)?[0])
    }

    fn u32(&mut self) -> Result<u32, i32> {
        let bytes = self.take(4)?;
        Ok(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    fn f32(&mut self) -> Result<f32, i32> {
        Ok(f32::from_bits(self.u32()?))
    }

    fn rgb(&mut self) -> Result<u32, i32> {
        let bytes = self.take(3)?;
        Ok(u32::from(bytes[0]) << 16 | u32::from(bytes[1]) << 8 | u32::from(bytes[2]))
    }

    // LEB128 of at most 32 bits, in its shortest form only.
    fn varint(&mut self) -> Result<u32, i32> {
        let mut value = 0u32;
        for shift in (0..35).step_by(7) {
            let byte = self.u8()?;
            let bits = u32::from(byte & 0x7f);
            if shift == 28 && bits > 0x0f {
                return Err(INVALID);
            }
            value |= bits << shift;
            if byte & 0x80 == 0 {
                // A last byte of zero after another is a longer spelling.
                if byte == 0 && shift != 0 {
                    return Err(INVALID);
                }
                return Ok(value);
            }
        }
        Err(INVALID)
    }

    fn zigzag(&mut self) -> Result<i32, i32> {
        let value = self.varint()?;
        Ok((value >> 1) as i32 ^ -((value & 1) as i32))
    }
}

struct Block<'a> {
    tag: [u8; 4],
    stored: &'a [u8],
    raw_length: usize,
    compression: u8,
    // Whether the CRC of the block matches its bytes.
    intact: bool,
}

fn read_block<'a>(input: &mut Input<'a>) -> Result<Block<'a>, i32> {
    let tag: [u8; 4] = input.take(4)?.try_into().map_err(|_| INVALID)?;
    let stored_length = input.u32()? as usize;
    let raw_length = input.u32()? as usize;
    let compression = input.u8()?;
    if input.take(3)? != [0; 3] || compression > DEFLATED {
        return Err(INVALID);
    }
    let crc = input.u32()?;
    let stored = input.take(stored_length)?;
    if (compression == STORED && raw_length != stored_length)
        || (compression == DEFLATED && raw_length <= stored_length)
    {
        return Err(INVALID);
    }
    Ok(Block {
        tag,
        stored,
        raw_length,
        compression,
        intact: crc32(stored) == crc,
    })
}

/// The bytes of a block once decompressed: exactly its raw length, from a
/// stream that ends exactly with its stored bytes.
fn raw_bytes(block: &Block<'_>, limit: usize) -> Result<Vec<u8>, i32> {
    if block.raw_length > limit {
        return Err(INVALID);
    }
    let mut raw = Vec::new();
    raw.try_reserve_exact(block.raw_length)
        .map_err(|_| ALLOCATION_FAILURE)?;
    if block.compression == STORED {
        raw.extend_from_slice(block.stored);
        return Ok(raw);
    }
    inflate(block.stored, block.raw_length, raw)
}

#[cfg(feature = "deflate")]
fn inflate(stored: &[u8], raw_length: usize, mut raw: Vec<u8>) -> Result<Vec<u8>, i32> {
    use miniz_oxide::inflate::core::{decompress, inflate_flags, DecompressorOxide};
    use miniz_oxide::inflate::TINFLStatus;
    raw.resize(raw_length, 0);
    let mut decompressor = DecompressorOxide::new();
    // The whole stream is here and the output is exactly its size: nothing
    // may be left over on either side.
    let flags = inflate_flags::TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF;
    let (status, read, written) = decompress(&mut decompressor, stored, &mut raw, 0, flags);
    if status != TINFLStatus::Done || read != stored.len() || written != raw_length {
        return Err(INVALID);
    }
    Ok(raw)
}

#[cfg(not(feature = "deflate"))]
fn inflate(_stored: &[u8], _raw_length: usize, _raw: Vec<u8>) -> Result<Vec<u8>, i32> {
    Err(INVALID)
}

struct DocumentBlock {
    objects: usize,
    points: usize,
    text_bytes: usize,
    paper: u32,
    active_layer: u8,
    layer_count: usize,
    background_bytes: usize,
}

fn read_document_block(raw: &[u8]) -> Result<DocumentBlock, i32> {
    let mut input = Input {
        bytes: raw,
        cursor: 0,
    };
    let objects = input.u32()? as usize;
    let points = input.u32()? as usize;
    let text_bytes = input.u32()? as usize;
    let word = input.u32()?;
    let active_layer = input.u8()?;
    let layer_count = usize::from(input.u8()?);
    let reserved = [input.u8()?, input.u8()?];
    let background_bytes = input.u32()? as usize;
    // One spelling per colour, as in version 4: white is the zero word.
    let paper = if word == 0 {
        WHITE_PAPER
    } else if word >> 24 == 1 && word & WHITE_PAPER != WHITE_PAPER {
        word & WHITE_PAPER
    } else {
        return Err(INVALID);
    };
    if raw.len() != DOC_BYTES
        || objects > MAX_STROKES
        || points > MAX_TOTAL_POINTS
        || text_bytes > MAX_TOTAL_TEXT_BYTES
        || !(1..=MAX_LAYERS).contains(&layer_count)
        || reserved != [0, 0]
        || background_bytes > MAX_BACKGROUND_BYTES
    {
        return Err(INVALID);
    }
    Ok(DocumentBlock {
        objects,
        points,
        text_bytes,
        paper,
        active_layer,
        layer_count,
        background_bytes,
    })
}

fn read_layers(raw: &[u8], document: &DocumentBlock) -> Result<[Layer; MAX_LAYERS], i32> {
    if raw.len() != 2 * document.layer_count {
        return Err(INVALID);
    }
    let mut layers = DEFAULT_LAYERS;
    let mut active = false;
    for (position, &[id, flags]) in raw.as_chunks::<2>().0.iter().enumerate() {
        if usize::from(id) >= MAX_LAYERS
            || flags & !3 != 0
            || layers[..position].iter().any(|layer| layer.id == id)
        {
            return Err(INVALID);
        }
        layers[position] = Layer {
            id,
            visible: flags & 1 == 1,
            locked: flags & 2 == 2,
        };
        // New objects join the active layer: it is never a locked one.
        active |= id == document.active_layer && flags & 2 == 0;
    }
    if !active {
        return Err(INVALID);
    }
    Ok(layers)
}

/// One object, read and checked, with its place in the drawing.
struct ReadObject {
    place: usize,
    stroke: Stroke,
}

#[allow(clippy::too_many_lines)]
fn read_object(
    input: &mut Input<'_>,
    previous_place: Option<usize>,
    layer: u8,
    width: u32,
    height: u32,
) -> Result<ReadObject, i32> {
    let step = input.varint()? as usize;
    let place = match previous_place {
        None => step,
        Some(previous) => previous
            .checked_add(1)
            .and_then(|next| next.checked_add(step))
            .ok_or(INVALID)?,
    };
    let kind = u32::from(input.u8()?);
    let flags = input.varint()?;
    let rgb = input.rgb()?;
    let stroke_width = input.f32()?;
    let param = input.varint()?;
    let quant = input.u8()?;
    let count = input.varint()? as usize;
    if kind > KIND_CONTOUR
        || flags & !KNOWN_FLAGS != 0
        || !(quant <= MAX_QUANT || quant == EXACT_QUANT)
        || !(1..=MAX_STROKE_POINTS).contains(&count)
        || !valid_width(kind, stroke_width)
        || !valid_param(kind, param)
    {
        return Err(INVALID);
    }
    let mut points = Vec::new();
    points
        .try_reserve_exact(count)
        .map_err(|_| ALLOCATION_FAILURE)?;
    if quant == EXACT_QUANT {
        for _ in 0..count {
            let x = input.f32()?;
            let y = input.f32()?;
            points.push(EpPoint { x, y });
        }
    } else {
        let scale = f64::from(1u32 << quant);
        let limits = [i64::from(width) << quant, i64::from(height) << quant];
        let mut current = [0i64; 2];
        for index in 0..count {
            if index == 0 {
                current = [i64::from(input.varint()?), i64::from(input.varint()?)];
            } else {
                current[0] += i64::from(input.zigzag()?);
                current[1] += i64::from(input.zigzag()?);
            }
            if !(0..=limits[0]).contains(&current[0]) || !(0..=limits[1]).contains(&current[1]) {
                return Err(INVALID);
            }
            points.push(EpPoint {
                x: (current[0] as f64 / scale) as f32,
                y: (current[1] as f64 / scale) as f32,
            });
        }
    }
    let style = EpObjectStyle {
        kind,
        fill_enabled: u32::from(flags & FILL != 0),
        fill_rgb: if flags & FILL != 0 { input.rgb()? } else { 0 },
    };
    let mut look = PLAIN_LOOK;
    if flags & GRADIENT != 0 {
        look.gradient = u32::from(input.u8()?);
        look.gradient_rgb = input.rgb()?;
        for value in &mut look.gradient_points {
            *value = input.f32()?;
        }
        if look.gradient == 0 {
            return Err(INVALID);
        }
    }
    if flags & ROTATION != 0 {
        look.rotation = input.f32()?;
        if look.rotation == 0.0 {
            return Err(INVALID);
        }
    }
    if flags & MIRROR != 0 {
        look.mirror = u32::from(input.u8()?);
        if look.mirror == 0 {
            return Err(INVALID);
        }
    }
    if flags & TOOL != 0 {
        look.tool = input.varint()?;
        if look.tool == TOOL_ROUND {
            return Err(INVALID);
        }
    }
    if flags & SEED != 0 {
        look.seed = input.u32()?;
    }
    // The seed is there exactly when the tool scatters its marks.
    if (flags & SEED != 0) != scattering_tool(look.tool) {
        return Err(INVALID);
    }
    let mut pressures = Vec::new();
    if flags & PRESSURES != 0 {
        pressures
            .try_reserve_exact(count)
            .map_err(|_| ALLOCATION_FAILURE)?;
        pressures.extend_from_slice(input.take(count)?);
    }
    let mut rings = Vec::new();
    if flags & RINGS != 0 {
        let ring_count = input.varint()? as usize;
        if !(2..=MAX_RINGS.min(count / 3)).contains(&ring_count) {
            return Err(INVALID);
        }
        rings
            .try_reserve_exact(ring_count)
            .map_err(|_| ALLOCATION_FAILURE)?;
        for _ in 0..ring_count {
            rings.push(input.varint()?);
        }
    }
    let mut text = Vec::new();
    if kind == KIND_TEXT {
        let length = input.varint()? as usize;
        if !(1..=MAX_TEXT_BYTES).contains(&length) {
            return Err(INVALID);
        }
        let bytes = input.take(length)?;
        if !text::valid_text(bytes) {
            return Err(INVALID);
        }
        text.try_reserve_exact(length)
            .map_err(|_| ALLOCATION_FAILURE)?;
        text.extend_from_slice(bytes);
    }
    if !valid_style(style)
        || !valid_look(kind, style.fill_enabled, &look)
        || !valid_extras(kind, count, &pressures, &rings)
        || !points.iter().all(|point| {
            point.x.is_finite()
                && point.y.is_finite()
                && (0.0..=width as f32).contains(&point.x)
                && (0.0..=height as f32).contains(&point.y)
        })
        || (kind != 0 && !valid_shape_points(kind, &points))
    {
        return Err(INVALID);
    }
    Ok(ReadObject {
        place,
        stroke: Stroke {
            points,
            rgb,
            width: stroke_width,
            style,
            scale: 1.0,
            translation: [0.0; 2],
            revision: 0,
            layer,
            param,
            text,
            extras: Extras {
                look,
                pressures,
                rings,
                quant,
            },
        },
    })
}

// The most raw bytes the objects of a drawing can take, from its totals.
fn objects_limit(document: &DocumentBlock) -> usize {
    6 + document.objects * RECORD_FIXED_BYTES
        + document.points * POINT_BYTES
        + 5 * (document.points / 3)
        + document.text_bytes
}

fn read_objects(
    raw: &[u8],
    layer: u8,
    width: u32,
    height: u32,
    objects: &mut Vec<ReadObject>,
) -> Result<(), i32> {
    let mut input = Input {
        bytes: raw,
        cursor: 0,
    };
    if input.u8()? != layer {
        return Err(INVALID);
    }
    let count = input.varint()? as usize;
    if count > MAX_STROKES - objects.len() {
        return Err(INVALID);
    }
    objects.try_reserve(count).map_err(|_| ALLOCATION_FAILURE)?;
    let mut previous = None;
    for _ in 0..count {
        let object = read_object(&mut input, previous, layer, width, height)?;
        previous = Some(object.place);
        objects.push(object);
    }
    if input.cursor != raw.len() {
        return Err(INVALID);
    }
    Ok(())
}

/// What `load` found missing in a damaged file: bit i for the layer at
/// position i of the table whose objects were lost, bit 16 for the image.
pub(crate) const LOST_BACKGROUND: u32 = 1 << 16;

fn read(bytes: &[u8], reading: Reading) -> Result<(EpDocument, u32), i32> {
    if bytes.len() < HEADER_BYTES + 4 || bytes.len() > MAX_BYTES {
        return Err(INVALID);
    }
    let mut input = Input { bytes, cursor: 0 };
    let magic = input.take(8)?;
    let version = u16::from_le_bytes([input.u8()?, input.u8()?]);
    let flags = u16::from_le_bytes([input.u8()?, input.u8()?]);
    let size = input.u32()? as usize;
    let width = input.u32()?;
    let height = input.u32()?;
    let block_count = input.u32()? as usize;
    let header_crc = input.u32()?;
    if magic != PROJECT_MAGIC
        || version != VERSION
        || flags != 0
        || size != bytes.len()
        || !(1..=MAX_DIMENSION).contains(&width)
        || !(1..=MAX_DIMENSION).contains(&height)
        || crc32(&bytes[..28]) != header_crc
    {
        return Err(INVALID);
    }
    let body_end = bytes.len() - 4;
    let stored_crc = u32::from_le_bytes(bytes[body_end..].try_into().map_err(|_| INVALID)?);
    let whole = reading == Reading::Whole;
    input.bytes = &bytes[..body_end];

    let document_block = read_block(&mut input)?;
    if document_block.tag != TAG_DOC
        || document_block.compression != STORED
        || !document_block.intact
    {
        return Err(INVALID);
    }
    let document = read_document_block(document_block.stored)?;
    let has_background = document.background_bytes != 0;
    if block_count != 2 + document.layer_count + usize::from(has_background) {
        return Err(INVALID);
    }
    let layer_block = read_block(&mut input)?;
    if layer_block.tag != TAG_LAYERS || layer_block.compression != STORED || !layer_block.intact {
        return Err(INVALID);
    }
    let layers = read_layers(layer_block.stored, &document)?;

    let limit = objects_limit(&document);
    let mut objects: Vec<ReadObject> = Vec::new();
    let mut lost = 0u32;
    for (position, layer) in layers[..document.layer_count].iter().enumerate() {
        let block = read_block(&mut input)?;
        if block.tag != TAG_OBJECTS {
            return Err(INVALID);
        }
        let mut found = Vec::new();
        let result = if block.intact {
            raw_bytes(&block, limit)
                .and_then(|raw| read_objects(&raw, layer.id, width, height, &mut found))
        } else {
            Err(INVALID)
        };
        match result {
            Ok(()) => {
                objects
                    .try_reserve(found.len())
                    .map_err(|_| ALLOCATION_FAILURE)?;
                objects.append(&mut found);
            }
            Err(ALLOCATION_FAILURE) => return Err(ALLOCATION_FAILURE),
            Err(status) if whole => return Err(status),
            Err(_) => lost |= 1 << position,
        }
    }
    let mut background = None;
    if has_background {
        let block = read_block(&mut input)?;
        if block.tag != TAG_BACKGROUND || block.compression != STORED {
            return Err(INVALID);
        }
        let checked = if block.intact && block.stored.len() == document.background_bytes {
            validate_canonical_png(block.stored).and_then(|(info, crc)| {
                if info.width != width || info.height != height {
                    Err(INVALID)
                } else {
                    BackgroundPng::copy_validated(width, height, block.stored, crc)
                }
            })
        } else {
            Err(INVALID)
        };
        match checked {
            Ok(png) => background = Some(Arc::new(png)),
            Err(ALLOCATION_FAILURE) => return Err(ALLOCATION_FAILURE),
            Err(status) if whole => return Err(status),
            Err(_) => lost |= LOST_BACKGROUND,
        }
    }
    if input.cursor != body_end {
        return Err(INVALID);
    }
    // A damaged file whose every block is intact is whole but for its last
    // four bytes: it is read as a whole one, and given back entire.
    let complete = whole || lost == 0;
    if complete {
        // Every byte once more, for the CRC of the file: the blocks were
        // each checked, this says that nothing else changed between them.
        let computed = match &background {
            Some(png) => crc32_combine(
                crc32(&bytes[..body_end - png.bytes.len()]),
                png.crc,
                png.bytes.len(),
            ),
            None => crc32(&bytes[..body_end]),
        };
        // A sound file is the other reader's: it is not damaged.
        if (computed == stored_crc) != whole {
            return Err(INVALID);
        }
    }

    // The places: exactly 0 .. objects in a whole file; in a damaged one,
    // those of the intact layers, kept in their order.
    objects.sort_unstable_by_key(|object| object.place);
    let points: usize = objects.iter().map(|o| o.stroke.points.len()).sum();
    let text_bytes: usize = objects.iter().map(|o| o.stroke.text.len()).sum();
    if objects
        .windows(2)
        .any(|pair| pair[0].place == pair[1].place)
        || points > MAX_TOTAL_POINTS
        || text_bytes > MAX_TOTAL_TEXT_BYTES
    {
        return Err(INVALID);
    }
    if complete
        && (objects.len() != document.objects
            || objects
                .last()
                .is_some_and(|last| last.place + 1 != objects.len())
            || points != document.points
            || text_bytes != document.text_bytes)
    {
        return Err(INVALID);
    }
    let mut built = EpDocument::blank(width, height);
    built.layers = layers;
    built.layer_count = document.layer_count;
    built.active_layer = document.active_layer;
    built.paper = document.paper;
    built.background = background;
    built
        .strokes
        .try_reserve_exact(objects.len())
        .map_err(|_| ALLOCATION_FAILURE)?;
    built
        .history
        .try_reserve_exact(objects.len())
        .map_err(|_| ALLOCATION_FAILURE)?;
    for (index, mut object) in objects.into_iter().enumerate() {
        object.stroke.revision = index as u64 + 1;
        let unlocked = !built.locked(object.stroke.layer);
        built.strokes.push(object.stroke);
        built.count_attached(index);
        // As for the older versions: the page of a locked layer is not in
        // the history; every other object is undone from the last.
        if unlocked {
            built.history.push(Edit::Presence {
                index,
                detached: None,
            });
        }
    }
    built.cursor = built.history.len();
    built.retained_points = built.active_points;
    built.retained_objects = built.strokes.len();
    built.retained_text_bytes = built.active_text_bytes;
    built.next_revision = built.strokes.len() as u64 + 1;
    Ok((built, lost))
}

/// Reads a whole, sound project of version 6.
pub(crate) fn load(bytes: &[u8]) -> Result<EpDocument, i32> {
    read(bytes, Reading::Whole).map(|(document, _)| document)
}

/// Reads what a damaged project of version 6 still holds: its header,
/// document and layer blocks must be intact; the objects of a damaged layer
/// and a damaged image are left out and said in the returned mask, empty
/// when only the last four bytes, the CRC of the file, were damaged. A file
/// that is not damaged, or not of version 6, is refused here.
pub(crate) fn load_damaged(bytes: &[u8]) -> Result<(EpDocument, u32), i32> {
    read(bytes, Reading::Damaged)
}

// ---------------------------------------------------------------- C contract

/// How many bytes ep_write_project may need for this drawing: a little more
/// than the file it writes, which a compression makes smaller still. Zero for
/// NULL. Reads counters only; no allocation.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently mutated.
#[no_mangle]
pub unsafe extern "C" fn ep_project_bound(document: *const EpDocument) -> usize {
    unsafe { document.as_ref() }.map_or(0, bound)
}

/// Writes the drawing as a project of version 6 into `out_bytes`, which must
/// hold at least ep_project_bound bytes, and its length into `out_length`.
/// `compress` 1 compresses the objects of each layer when that makes them
/// smaller, borrowing memory for it (a layer is kept as it is if memory is
/// missing); 0 writes every block as it is, with no allocation. Returns 0, or
/// -1 for NULL or a capacity below the bound, leaving `out_length` unchanged.
/// Bytes after the written length are unspecified.
///
/// # Safety
/// Non-null `document` must be live, aligned and not concurrently mutated;
/// `out_bytes` must be writable for `capacity` bytes, disjoint from it and
/// from `out_length`, which must be writable and aligned.
#[no_mangle]
pub unsafe extern "C" fn ep_write_project(
    document: *const EpDocument,
    out_bytes: *mut u8,
    capacity: usize,
    compress: u32,
    out_length: *mut usize,
) -> i32 {
    let Some(doc) = (unsafe { document.as_ref() }) else {
        return INVALID;
    };
    unsafe { write_into(doc, out_bytes, capacity, compress, out_length) }
}

// Shared by the document and its immutable snapshots.
pub(crate) unsafe fn write_into(
    doc: &EpDocument,
    out_bytes: *mut u8,
    capacity: usize,
    compress: u32,
    out_length: *mut usize,
) -> i32 {
    let needed = bound(doc);
    if out_bytes.is_null() || out_length.is_null() || capacity < needed || compress > 1 {
        return INVALID;
    }
    let output = unsafe { slice::from_raw_parts_mut(out_bytes, needed) };
    match write(doc, output, compress == 1) {
        Ok(length) => {
            unsafe { out_length.write(length) };
            0
        }
        Err(status) => status,
    }
}

/// Reads again a project of version 6 whose CRC no longer matches its bytes:
/// the objects of every intact layer, in their order, and the image if it is
/// intact. `out_lost` (optional) receives bit i for the layer at position i
/// of the table whose objects were lost, and bit 16 for a lost image; 0 when
/// only the CRC of the file was damaged, the drawing being whole. NULL
/// when nothing can be saved — header, document or layer block damaged — or
/// when the file is not damaged (ep_document_from_project reads it), with
/// `out_status` -1; -2 when memory is missing.
///
/// # Safety
/// As ep_document_from_project; non-null `out_lost` must be writable,
/// aligned and disjoint from the input bytes.
#[no_mangle]
pub unsafe extern "C" fn ep_document_from_damaged_project(
    bytes: *const u8,
    length: usize,
    out_lost: *mut u32,
    out_status: *mut i32,
) -> *mut EpDocument {
    let result = if bytes.is_null() || !(PROJECT_MIN_BYTES..=MAX_BYTES).contains(&length) {
        Err(INVALID)
    } else {
        load_damaged(unsafe { slice::from_raw_parts(bytes, length) })
    };
    let (pointer, status) = match result {
        Ok((document, lost)) => {
            if !out_lost.is_null() {
                unsafe { out_lost.write(lost) };
            }
            (owned_document(document), 0)
        }
        Err(status) => (ptr::null_mut(), status),
    };
    if !out_status.is_null() {
        unsafe { out_status.write(status) };
    }
    pointer
}

#[cfg(test)]
mod tests;
