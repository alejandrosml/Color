//! Structural validation only: the caller must decode successfully before
//! adopting a candidate document. No zlib, pixels, ICC or private Tux chunks
//! are decompressed by this dependency-free core.
use super::{crc32, EpBackgroundInfo, ALLOCATION_FAILURE, INVALID};

pub const MAX_BACKGROUND_DIMENSION: u32 = 8192;
pub const MAX_BACKGROUND_PIXELS: u64 = 16 * 1024 * 1024;
pub const MAX_BACKGROUND_BYTES: usize = 68 * 1024 * 1024;
const PNG_SIGNATURE: &[u8; 8] = b"\x89PNG\r\n\x1a\n";
const SRGB_CHROMATICITIES: [u32; 8] = [31270, 32900, 64000, 33000, 30000, 60000, 15000, 6000];

pub(super) struct BackgroundPng {
    pub width: u32,
    pub height: u32,
    pub bytes: Vec<u8>,
    pub crc: u32,
}

impl BackgroundPng {
    // Only called after validation; no duplicate PNG scan during project load.
    pub fn copy_validated(width: u32, height: u32, bytes: &[u8], crc: u32) -> Result<Self, i32> {
        let mut owned = Vec::new();
        owned
            .try_reserve_exact(bytes.len())
            .map_err(|_| ALLOCATION_FAILURE)?;
        owned.extend_from_slice(bytes);
        Ok(Self {
            width,
            height,
            bytes: owned,
            crc,
        })
    }

    pub fn info(&self) -> EpBackgroundInfo {
        EpBackgroundInfo {
            width: self.width,
            height: self.height,
            byte_count: self.bytes.len(),
        }
    }
}

fn be_u32(bytes: &[u8]) -> Result<u32, i32> {
    Ok(u32::from_be_bytes(bytes.try_into().map_err(|_| INVALID)?))
}

/// Accepted canonical PNG: 8-bit RGB/RGBA, no interlace, IHDR then optional
/// unique sRGB/gAMA/cHRM/pHYs then contiguous IDAT chunks and final empty IEND.
/// gAMA/cHRM, when present, must describe sRGB, not contradict the asset contract.
/// A profile-free PNG is treated as sRGB by the caller's normalization contract.
pub(super) fn validate_canonical_png(bytes: &[u8]) -> Result<EpBackgroundInfo, i32> {
    if !(57..=MAX_BACKGROUND_BYTES).contains(&bytes.len())
        || bytes.get(..8) != Some(PNG_SIGNATURE.as_slice())
    {
        return Err(INVALID);
    }
    let mut cursor = 8usize;
    let mut info = None;
    let mut metadata_seen = 0u8;
    let mut idat_seen = false;
    let mut idat_bytes = 0usize;
    while cursor < bytes.len() {
        let header_end = cursor.checked_add(8).ok_or(INVALID)?;
        let header = bytes.get(cursor..header_end).ok_or(INVALID)?;
        let length = be_u32(&header[..4])? as usize;
        let data_end = header_end.checked_add(length).ok_or(INVALID)?;
        let end = data_end.checked_add(4).ok_or(INVALID)?;
        let data = bytes.get(header_end..data_end).ok_or(INVALID)?;
        let stored_crc = be_u32(bytes.get(data_end..end).ok_or(INVALID)?)?;
        if crc32(&bytes[cursor + 4..data_end]) != stored_crc {
            return Err(INVALID);
        }
        let kind = &header[4..8];
        if info.is_none() && kind != b"IHDR" {
            return Err(INVALID);
        }
        match kind {
            b"IHDR" => {
                if info.is_some() || cursor != 8 || length != 13 {
                    return Err(INVALID);
                }
                let width = be_u32(&data[..4])?;
                let height = be_u32(&data[4..8])?;
                if !(1..=MAX_BACKGROUND_DIMENSION).contains(&width)
                    || !(1..=MAX_BACKGROUND_DIMENSION).contains(&height)
                    || u64::from(width) * u64::from(height) > MAX_BACKGROUND_PIXELS
                    || data[8] != 8
                    || !matches!(data[9], 2 | 6)
                    || data[10..13] != [0, 0, 0]
                {
                    return Err(INVALID);
                }
                info = Some(EpBackgroundInfo {
                    width,
                    height,
                    byte_count: bytes.len(),
                });
            }
            b"sRGB" | b"gAMA" | b"cHRM" | b"pHYs" => {
                if idat_seen {
                    return Err(INVALID);
                }
                let bit = match kind {
                    b"sRGB" => {
                        if length != 1 || data[0] > 3 {
                            return Err(INVALID);
                        }
                        1
                    }
                    b"gAMA" => {
                        if length != 4 || be_u32(data)? != 45455 {
                            return Err(INVALID);
                        }
                        2
                    }
                    b"cHRM" => {
                        if length != 32 {
                            return Err(INVALID);
                        }
                        // length == 32 was checked: eight exact big-endian words.
                        for (value, expected) in
                            data.as_chunks::<4>().0.iter().zip(SRGB_CHROMATICITIES)
                        {
                            if be_u32(value)? != expected {
                                return Err(INVALID);
                            }
                        }
                        4
                    }
                    _ => {
                        if length != 9 || data[8] > 1 {
                            return Err(INVALID);
                        }
                        8
                    }
                };
                if metadata_seen & bit != 0 {
                    return Err(INVALID);
                }
                metadata_seen |= bit;
            }
            b"IDAT" => {
                idat_seen = true;
                idat_bytes = idat_bytes.checked_add(length).ok_or(INVALID)?;
            }
            b"IEND" => {
                if length != 0 || !idat_seen || idat_bytes == 0 || end != bytes.len() {
                    return Err(INVALID);
                }
                return info.ok_or(INVALID);
            }
            // In particular reject APNG, compressed profiles/text, PLTE/tRNS,
            // private chunks and unknown critical/ancillary extensions.
            _ => return Err(INVALID),
        }
        cursor = end;
    }
    Err(INVALID)
}
