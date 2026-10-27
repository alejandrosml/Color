//! Stamp objects: a reference to one catalogue drawing, a box and a colour.
//!
//! The catalogue is the single source of every stamp's vector artwork. The
//! interface reads it once as text and paints the same paths that this core
//! writes into SVG exports; a project stores only the identifier, never a copy
//! of the artwork. Identifiers are positions in the catalogue: stamps may be
//! appended, never reordered or removed.
use super::*;

mod catalog;
pub(crate) use catalog::STAMPS;

/// Colour of one painted layer: the object's own colour, a darker shade or a
/// lighter tint derived from it with integer arithmetic, or a fixed colour.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum Paint {
    None,
    Primary,
    Dark,
    Light,
    Fixed(u32),
}

pub(crate) struct StampLayer {
    pub fill: Paint,
    pub stroke: Paint,
    /// Outline width on the 100 x 100 design grid; scaled with the stamp.
    pub width: f32,
    /// Absolute M, L, C, Q and Z commands, numbers separated by spaces.
    pub path: &'static str,
}

pub(crate) struct Stamp {
    /// Stable ASCII name, for interface labels and catalogue checks.
    pub key: &'static str,
    pub layers: &'static [StampLayer],
}

impl Paint {
    // Exact integer shades shared with the interface: dark = 7/10 of each
    // channel, light = the channel plus 6/10 of its distance to white.
    fn rgb(self, primary: u32) -> Option<u32> {
        let channels = |map: fn(u32) -> u32| {
            (map((primary >> 16) & 0xff) << 16)
                | (map((primary >> 8) & 0xff) << 8)
                | map(primary & 0xff)
        };
        match self {
            Paint::None => None,
            Paint::Primary => Some(primary),
            Paint::Dark => Some(channels(|c| c * 7 / 10)),
            Paint::Light => Some(channels(|c| c + (255 - c) * 6 / 10)),
            Paint::Fixed(rgb) => Some(rgb),
        }
    }

    fn code(self, output: &mut String) -> Option<()> {
        match self {
            Paint::None => output.push('-'),
            Paint::Primary => output.push('P'),
            Paint::Dark => output.push('D'),
            Paint::Light => output.push('L'),
            Paint::Fixed(rgb) => write!(output, "#{:06x}", rgb).ok()?,
        }
        Some(())
    }
}

fn write_paint(result: &mut String, name: &str, paint: Paint, primary: u32) -> Option<()> {
    match paint.rgb(primary) {
        Some(rgb) => write!(result, " {}=\"#{:06x}\"", name, rgb).ok(),
        None => write!(result, " {}=\"none\"", name).ok(),
    }
}

/// Upper bound of the SVG markup of one stamp, for the export reservation.
pub(super) fn stamp_svg_bytes(id: u32) -> usize {
    STAMPS.get(id as usize).map_or(0, |stamp| {
        256 + stamp
            .layers
            .iter()
            .map(|layer| layer.path.len() + 192)
            .sum::<usize>()
    })
}

/// Writes the catalogue paths in a group scaled from the 100 x 100 design
/// grid to the object's box. Outlines scale with the stamp, as on the sheet.
pub(super) fn write_stamp_svg(
    result: &mut String,
    id: u32,
    primary: u32,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
) -> Option<()> {
    let stamp = STAMPS.get(id as usize)?;
    writeln!(
        result,
        "<g transform=\"translate({} {}) scale({} {})\">",
        x,
        y,
        width / 100.0,
        height / 100.0
    )
    .ok()?;
    for layer in stamp.layers {
        write!(result, "<path d=\"{}\"", layer.path).ok()?;
        write_paint(result, "fill", layer.fill, primary)?;
        write_paint(result, "stroke", layer.stroke, primary)?;
        if layer.stroke != Paint::None {
            write!(
                result,
                " stroke-width=\"{}\" stroke-linecap=\"round\" stroke-linejoin=\"round\"",
                layer.width
            )
            .ok()?;
        }
        result.push_str("/>\n");
    }
    result.push_str("</g>\n");
    Some(())
}

// One line per stamp: `id|key|fill,stroke,width,path;fill,stroke,width,path`.
// Paints are `-` none, `P` colour, `D` shade, `L` tint or `#rrggbb`.
fn catalog_text() -> Option<CString> {
    let capacity = STAMPS
        .iter()
        .map(|stamp| {
            stamp.key.len()
                + 32
                + stamp
                    .layers
                    .iter()
                    .map(|layer| layer.path.len() + 48)
                    .sum::<usize>()
        })
        .sum::<usize>()
        + 1;
    let mut result = String::new();
    result.try_reserve_exact(capacity).ok()?;
    for (id, stamp) in STAMPS.iter().enumerate() {
        write!(result, "{}|{}|", id, stamp.key).ok()?;
        for (index, layer) in stamp.layers.iter().enumerate() {
            if index != 0 {
                result.push(';');
            }
            layer.fill.code(&mut result)?;
            result.push(',');
            layer.stroke.code(&mut result)?;
            write!(result, ",{},{}", layer.width, layer.path).ok()?;
        }
        result.push('\n');
    }
    let mut bytes = result.into_bytes();
    bytes.push(0);
    CString::from_vec_with_nul(bytes).ok()
}

/// Number of stamps of this core; valid identifiers are 0..count.
#[no_mangle]
pub extern "C" fn ep_stamp_count() -> u32 {
    STAMPS.len() as u32
}

/// Returns the whole catalogue as owned, NUL-terminated ASCII text, or NULL
/// on allocation failure. One line per stamp, in identifier order:
/// `id|key|fill,stroke,width,path;...`. Release with ep_string_free only.
#[no_mangle]
pub extern "C" fn ep_stamp_catalog() -> *mut c_char {
    catalog_text().map_or(ptr::null_mut(), CString::into_raw)
}

/// Adds a stamp on the active layer. `box_points` are two opposite corners,
/// inside the page, with a non-zero width and height: the artwork is scaled
/// to that box. `stamp` must be below ep_stamp_count; `rgb` is its colour.
/// Returns 0 on success, -1 invalid input/limits, -2 allocation failure;
/// failure leaves drawing and history unchanged, success clears redo.
///
/// # Safety
/// Same exclusive document rules as ep_add_stroke. Non-null `box_points`
/// must address two initialized, stable EpPoint values disjoint from the
/// document; they are copied.
#[no_mangle]
pub unsafe extern "C" fn ep_add_stamp(
    document: *mut EpDocument,
    box_points: *const EpPoint,
    stamp: u32,
    rgb: u32,
) -> i32 {
    let style = EpObjectStyle {
        kind: KIND_STAMP,
        fill_enabled: 0,
        fill_rgb: 0,
    };
    unsafe { add_object(document, box_points, 2, rgb, 1.0, style, stamp, &[]) }
}

#[cfg(test)]
mod tests;
