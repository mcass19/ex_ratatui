//! Pixel regions: bitmaps that pixel-capable widgets hand to a
//! `CellSession` created with a font size, alongside the cell grid.
//!
//! A terminal graphics protocol smuggles its bytes through one cell's
//! symbol; a cell diff cannot carry that. On a surface that owns real
//! pixels (an e-ink panel, a browser canvas) we do not need the escape at
//! all — the consumer wants the bitmap and the rect it covers. So while a
//! `CellSession` draw runs with [`TransportCaps::PixelRegions`], widgets in
//! pixel mode rasterize to RGB8, blank the cells they cover, and push a
//! [`PixelRegion`] here. The session collects the regions when the draw
//! returns and ships the complete list with every snapshot and diff.
//!
//! The covered cells are blanked rather than flagged `Skip`: ratatui's
//! terminal never forwards skipped cells to its backend buffer, so a skip
//! flag would leave stale content under the region and never reach the
//! consumer. A blank cell is exactly what the consumer should paint before
//! blitting the bitmap on top.
//!
//! Collection is a thread-local scoped to a single draw. `render_widget_data`
//! runs on the thread that called the draw NIF (a dirty CPU scheduler), so
//! nothing can leak across sessions; pushes outside a draw are dropped.
//!
//! [`TransportCaps::PixelRegions`]: crate::image::TransportCaps::PixelRegions

use std::cell::RefCell;

use image::{DynamicImage, ImageFormat, RgbImage};
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use rustler::{Binary, Encoder, Env, Error, OwnedBinary, Term};

mod atoms {
    rustler::atoms! {
        x,
        y,
        width,
        height,
        pixel_width,
        pixel_height,
        format,
        data,
        rgb8,
        invalid_dimensions,
        invalid_angle,
        alloc_failed,
        encode_failed,
    }
}

/// `region_encode_png/3`: encodes a region's RGB8 bytes as a PNG, for
/// consumers that ship bitmaps over a text channel (a LiveView push, a
/// JSON API) where raw RGB would be several times heavier.
#[rustler::nif(schedule = "DirtyCpu")]
fn region_encode_png<'a>(
    env: Env<'a>,
    width: u32,
    height: u32,
    data: Binary<'a>,
) -> Result<Term<'a>, Error> {
    let png = encode_png(width, height, data.as_slice()).map_err(|e| match e {
        PngError::InvalidDimensions => Error::Term(Box::new(atoms::invalid_dimensions())),
        PngError::Encode(message) => Error::Term(Box::new((atoms::encode_failed(), message))),
    })?;
    Ok(bytes_to_binary(env, &png))
}

#[derive(Debug, PartialEq, Eq)]
enum PngError {
    InvalidDimensions,
    Encode(String),
}

fn encode_png(width: u32, height: u32, rgb: &[u8]) -> Result<Vec<u8>, PngError> {
    let image =
        RgbImage::from_raw(width, height, rgb.to_vec()).ok_or(PngError::InvalidDimensions)?;
    let mut out = Vec::new();
    DynamicImage::ImageRgb8(image)
        .write_to(&mut std::io::Cursor::new(&mut out), ImageFormat::Png)
        .map_err(|e| PngError::Encode(e.to_string()))?;
    Ok(out)
}

/// `rotate_rgb8/4`: rotates a region's bitmap clockwise, so a consumer
/// painting a panel mounted on its side keeps its flat row-by-row path
/// instead of gathering every destination row from a source column.
///
/// Returns `{rotated_data, width, height}` with the dimensions swapped at
/// 90 and 270.
#[rustler::nif(schedule = "DirtyCpu")]
fn rotate_rgb8<'a>(
    env: Env<'a>,
    width: u32,
    height: u32,
    angle: u32,
    data: Binary<'a>,
) -> Result<(Term<'a>, u32, u32), Error> {
    let (out_width, out_height) =
        rotated_dims(width, height, angle, data.len()).map_err(rotate_error_term)?;

    let mut owned =
        OwnedBinary::new(data.len()).ok_or_else(|| Error::Term(Box::new(atoms::alloc_failed())))?;

    rotate_rgb8_into(data.as_slice(), owned.as_mut_slice(), width, height, angle)
        .map_err(rotate_error_term)?;

    Ok((
        Binary::from_owned(owned, env).encode(env),
        out_width,
        out_height,
    ))
}

fn rotate_error_term(error: RotateError) -> Error {
    match error {
        RotateError::InvalidDimensions => Error::Term(Box::new(atoms::invalid_dimensions())),
        RotateError::InvalidAngle => Error::Term(Box::new(atoms::invalid_angle())),
    }
}

#[derive(Debug, PartialEq, Eq)]
enum RotateError {
    InvalidDimensions,
    InvalidAngle,
}

/// Bytes per pixel in the RGB8 bitmaps a region carries.
const BPP: usize = 3;

/// Validates a rotation request and returns the destination dimensions.
fn rotated_dims(
    width: u32,
    height: u32,
    angle: u32,
    len: usize,
) -> Result<(u32, u32), RotateError> {
    if !matches!(angle, 90 | 180 | 270) {
        return Err(RotateError::InvalidAngle);
    }

    let expected = (width as usize)
        .checked_mul(height as usize)
        .and_then(|pixels| pixels.checked_mul(BPP))
        .ok_or(RotateError::InvalidDimensions)?;

    if len != expected {
        return Err(RotateError::InvalidDimensions);
    }

    if angle == 180 {
        Ok((width, height))
    } else {
        Ok((height, width))
    }
}

/// Writes the clockwise rotation of `src` into `dst`, both row-major RGB8.
///
/// The pixel landing at destination `(px, py)` comes from source
/// `(py, h - 1 - px)` at 90, `(w - 1 - px, h - 1 - py)` at 180 and
/// `(w - 1 - py, px)` at 270 — the corner mapping the consumer side uses.
/// Destination rows are walked in order, so the writes are sequential and
/// only the reads are strided.
fn rotate_rgb8_into(
    src: &[u8],
    dst: &mut [u8],
    width: u32,
    height: u32,
    angle: u32,
) -> Result<(u32, u32), RotateError> {
    let (out_width, out_height) = rotated_dims(width, height, angle, src.len())?;

    if dst.len() != src.len() {
        return Err(RotateError::InvalidDimensions);
    }

    // A zero-sized bitmap has nothing to copy, and the corner arithmetic
    // below would underflow on the empty axis.
    if src.is_empty() {
        return Ok((out_width, out_height));
    }

    let (w, h) = (width as usize, height as usize);
    let row_stride = w * BPP;
    let mut out = 0;

    for py in 0..(out_height as usize) {
        // Where this destination row starts in the source, and how far one
        // destination pixel moves within it.
        let (mut at, step): (usize, isize) = match angle {
            90 => (((h - 1) * w + py) * BPP, -(row_stride as isize)),
            180 => (((h - 1 - py) * w + w - 1) * BPP, -(BPP as isize)),
            _ => ((w - 1 - py) * BPP, row_stride as isize),
        };

        for _ in 0..(out_width as usize) {
            dst[out..out + BPP].copy_from_slice(&src[at..at + BPP]);
            out += BPP;
            // The final step of a row can run off either end; it is never
            // read again.
            at = at.wrapping_add_signed(step);
        }
    }

    Ok((out_width, out_height))
}

/// One bitmap covering a rect of cells. `data` is row-major RGB8 with no
/// padding, `pixel_width * pixel_height * 3` bytes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PixelRegion {
    pub x: u16,
    pub y: u16,
    pub width: u16,
    pub height: u16,
    pub pixel_width: u32,
    pub pixel_height: u32,
    pub data: Vec<u8>,
}

/// Longest bitmap side, in pixels, a region (or a terminal-protocol image)
/// is rendered at. Bounds the per-frame rasterize/encode/transmit cost
/// regardless of how large the cell rect is; consumers scale the bitmap up
/// to the rect when it hits.
pub const MAX_DIM: u32 = 1280;

/// Pixel size of `area` at `font_size`, with the longest side clamped to
/// [`MAX_DIM`] (aspect preserved). Never returns a zero dimension.
pub fn rect_pixel_dims(area: Rect, (fw, fh): (u16, u16)) -> (u32, u32) {
    let w = (area.width as u32 * fw as u32).max(1);
    let h = (area.height as u32 * fh as u32).max(1);
    let longest = w.max(h);

    if longest <= MAX_DIM {
        (w, h)
    } else {
        let scale = MAX_DIM as f32 / longest as f32;
        (
            ((w as f32 * scale) as u32).max(1),
            ((h as f32 * scale) as u32).max(1),
        )
    }
}

thread_local! {
    static COLLECTING: RefCell<Option<Vec<PixelRegion>>> = const { RefCell::new(None) };
}

/// Starts collecting regions on this thread. Any regions from an
/// unfinished previous collection are discarded.
pub fn begin_collecting() {
    COLLECTING.with(|slot| *slot.borrow_mut() = Some(Vec::new()));
}

/// Adds a region to the current collection. A no-op when no draw is
/// collecting, so widgets can push unconditionally once they know the
/// caps asked for regions.
pub fn push(region: PixelRegion) {
    COLLECTING.with(|slot| {
        if let Some(regions) = slot.borrow_mut().as_mut() {
            regions.push(region);
        }
    });
}

/// Ends the collection started by [`begin_collecting`] and returns what
/// was pushed. Returns an empty list when nothing was collecting.
pub fn finish_collecting() -> Vec<PixelRegion> {
    COLLECTING.with(|slot| slot.borrow_mut().take().unwrap_or_default())
}

/// Resets every cell in `area` to a default blank, so whatever was drawn
/// underneath does not linger and the consumer has a clean rect to blit
/// the region onto.
pub fn blank_area(buf: &mut Buffer, area: Rect) {
    let area = area.intersection(*buf.area());
    for y in area.top()..area.bottom() {
        for x in area.left()..area.right() {
            if let Some(cell) = buf.cell_mut((x, y)) {
                cell.reset();
            }
        }
    }
}

/// Encodes regions as the list of maps carried under the `:regions` key of
/// `take_cells` / `take_cells_diff` payloads. The bytes are copied into a
/// BEAM binary per region.
pub fn encode_regions<'a>(env: Env<'a>, regions: &[PixelRegion]) -> Term<'a> {
    regions
        .iter()
        .map(|region| encode_region(env, region))
        .collect::<Vec<Term<'a>>>()
        .encode(env)
}

fn encode_region<'a>(env: Env<'a>, region: &PixelRegion) -> Term<'a> {
    Term::map_new(env)
        .map_put(atoms::x().encode(env), region.x.encode(env))
        .expect("map_put on fresh map cannot fail")
        .map_put(atoms::y().encode(env), region.y.encode(env))
        .expect("map_put on fresh map cannot fail")
        .map_put(atoms::width().encode(env), region.width.encode(env))
        .expect("map_put on fresh map cannot fail")
        .map_put(atoms::height().encode(env), region.height.encode(env))
        .expect("map_put on fresh map cannot fail")
        .map_put(
            atoms::pixel_width().encode(env),
            region.pixel_width.encode(env),
        )
        .expect("map_put on fresh map cannot fail")
        .map_put(
            atoms::pixel_height().encode(env),
            region.pixel_height.encode(env),
        )
        .expect("map_put on fresh map cannot fail")
        .map_put(atoms::format().encode(env), atoms::rgb8().encode(env))
        .expect("map_put on fresh map cannot fail")
        .map_put(
            atoms::data().encode(env),
            bytes_to_binary(env, &region.data),
        )
        .expect("map_put on fresh map cannot fail")
}

fn bytes_to_binary<'a>(env: Env<'a>, bytes: &[u8]) -> Term<'a> {
    let mut owned = OwnedBinary::new(bytes.len()).unwrap_or_else(|| {
        OwnedBinary::new(0).expect("zero-length OwnedBinary allocation cannot fail")
    });
    if !bytes.is_empty() {
        owned.as_mut_slice().copy_from_slice(bytes);
    }
    Binary::from_owned(owned, env).encode(env)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A `width * height` bitmap where every pixel is distinct, so a
    /// rotation that is off by a transpose cannot pass.
    fn bitmap(width: usize, height: usize) -> Vec<u8> {
        (0..(width * height))
            .flat_map(|i| {
                let base = (i as u8) * 10 + 1;
                [base, base + 1, base + 2]
            })
            .collect()
    }

    /// The obvious, slow rotation, straight from the corner mapping. The
    /// consumer side keeps the same reference (raster's
    /// `RasterExRatatui.Test.Rotation.rotate_frame/5`), and the fast path
    /// has to agree with it byte for byte.
    fn reference_rotate(src: &[u8], width: usize, height: usize, angle: u32) -> Vec<u8> {
        let (out_width, out_height) = if angle == 180 {
            (width, height)
        } else {
            (height, width)
        };
        let mut out = Vec::with_capacity(src.len());

        for py in 0..out_height {
            for px in 0..out_width {
                let (x, y) = match angle {
                    90 => (py, height - 1 - px),
                    180 => (width - 1 - px, height - 1 - py),
                    _ => (width - 1 - py, px),
                };
                let at = (y * width + x) * BPP;
                out.extend_from_slice(&src[at..at + BPP]);
            }
        }

        out
    }

    fn rotate(
        src: &[u8],
        width: u32,
        height: u32,
        angle: u32,
    ) -> Result<(Vec<u8>, u32, u32), RotateError> {
        let mut dst = vec![0; src.len()];
        let (out_width, out_height) = rotate_rgb8_into(src, &mut dst, width, height, angle)?;
        Ok((dst, out_width, out_height))
    }

    #[test]
    fn rotate_matches_the_reference_on_a_non_square_bitmap() {
        let src = bitmap(3, 2);

        for angle in [90, 180, 270] {
            let (rotated, out_width, out_height) = rotate(&src, 3, 2, angle).unwrap();
            let expected_dims = if angle == 180 { (3, 2) } else { (2, 3) };

            assert_eq!((out_width, out_height), expected_dims, "dims at {angle}");
            assert_eq!(rotated, reference_rotate(&src, 3, 2, angle), "at {angle}");
        }
    }

    #[test]
    fn four_quarter_turns_are_the_identity() {
        let src = bitmap(3, 2);
        let mut current = (src.clone(), 3, 2);

        for _ in 0..4 {
            let (data, w, h) = current;
            let (rotated, out_w, out_h) = rotate(&data, w, h, 90).unwrap();
            current = (rotated, out_w, out_h);
        }

        assert_eq!(current, (src, 3, 2));
    }

    #[test]
    fn opposite_turns_cancel_out() {
        let src = bitmap(3, 2);

        let (once, w, h) = rotate(&src, 3, 2, 180).unwrap();
        assert_eq!(rotate(&once, w, h, 180).unwrap(), (src.clone(), 3, 2));

        let (quarter, w, h) = rotate(&src, 3, 2, 90).unwrap();
        assert_eq!(rotate(&quarter, w, h, 270).unwrap(), (src, 3, 2));
    }

    #[test]
    fn rotate_handles_single_row_and_single_column_bitmaps() {
        for (width, height) in [(4, 1), (1, 4)] {
            let src = bitmap(width, height);

            for angle in [90, 180, 270] {
                let (rotated, _, _) = rotate(&src, width as u32, height as u32, angle).unwrap();
                assert_eq!(
                    rotated,
                    reference_rotate(&src, width, height, angle),
                    "{width}x{height} at {angle}"
                );
            }
        }
    }

    #[test]
    fn rotate_returns_swapped_dimensions_for_an_empty_bitmap() {
        assert_eq!(rotate(&[], 0, 4, 90).unwrap(), (vec![], 4, 0));
        assert_eq!(rotate(&[], 3, 0, 180).unwrap(), (vec![], 3, 0));
    }

    #[test]
    fn rotate_rejects_a_byte_count_that_is_not_three_per_pixel() {
        assert_eq!(
            rotate(&[0; 11], 2, 2, 90),
            Err(RotateError::InvalidDimensions)
        );
        assert_eq!(
            rotate(&[0; 12], 2, 2, 90).map(|(_, w, h)| (w, h)),
            Ok((2, 2))
        );
    }

    #[test]
    fn rotate_rejects_a_destination_of_the_wrong_size() {
        let mut dst = vec![0; 3];
        assert_eq!(
            rotate_rgb8_into(&[0; 12], &mut dst, 2, 2, 90),
            Err(RotateError::InvalidDimensions)
        );
    }

    #[test]
    fn rotate_rejects_unsupported_angles() {
        for angle in [0, 45, 360] {
            assert_eq!(
                rotate(&[0; 12], 2, 2, angle),
                Err(RotateError::InvalidAngle),
                "at {angle}"
            );
        }
    }

    #[test]
    fn rotate_rejects_dimensions_that_overflow_a_byte_count() {
        assert_eq!(
            rotated_dims(u32::MAX, u32::MAX, 90, 0),
            Err(RotateError::InvalidDimensions)
        );
    }

    fn region(x: u16) -> PixelRegion {
        PixelRegion {
            x,
            y: 0,
            width: 1,
            height: 1,
            pixel_width: 2,
            pixel_height: 2,
            data: vec![0; 12],
        }
    }

    #[test]
    fn rect_pixel_dims_uses_native_resolution_when_small() {
        // 30x15 cells at 8x16 px = 240x240, under MAX_DIM.
        assert_eq!(
            rect_pixel_dims(Rect::new(0, 0, 30, 15), (8, 16)),
            (240, 240)
        );
    }

    #[test]
    fn rect_pixel_dims_clamps_longest_side_to_max() {
        // 400 cells * 8 px = 3200 wide, clamped to MAX_DIM (1280).
        let (w, h) = rect_pixel_dims(Rect::new(0, 0, 400, 50), (8, 16));
        assert_eq!(w.max(h), MAX_DIM);
        assert!(w >= 1 && h >= 1);
    }

    #[test]
    fn encode_png_round_trips_through_the_image_decoder() {
        let png = encode_png(2, 1, &[255, 0, 0, 0, 0, 255]).unwrap();
        let decoded = image::load_from_memory(&png).unwrap().to_rgb8();
        assert_eq!(decoded.dimensions(), (2, 1));
        assert_eq!(decoded.get_pixel(0, 0).0, [255, 0, 0]);
        assert_eq!(decoded.get_pixel(1, 0).0, [0, 0, 255]);
    }

    #[test]
    fn encode_png_rejects_mismatched_dimensions() {
        assert_eq!(
            encode_png(2, 2, &[0, 0, 0]),
            Err(PngError::InvalidDimensions)
        );
    }

    #[test]
    fn collects_pushes_between_begin_and_finish() {
        begin_collecting();
        push(region(1));
        push(region(2));
        let regions = finish_collecting();
        assert_eq!(regions.iter().map(|r| r.x).collect::<Vec<_>>(), vec![1, 2]);
    }

    #[test]
    fn pushes_outside_a_collection_are_dropped() {
        finish_collecting();
        push(region(9));
        assert!(finish_collecting().is_empty());
    }

    #[test]
    fn begin_discards_a_stale_collection() {
        begin_collecting();
        push(region(1));
        begin_collecting();
        assert!(finish_collecting().is_empty());
    }

    #[test]
    fn blank_area_resets_only_the_area() {
        let mut buf = Buffer::empty(Rect::new(0, 0, 4, 2));
        buf[(0, 0)]
            .set_symbol("a")
            .set_fg(ratatui::style::Color::Red);
        buf[(1, 1)].set_symbol("b");
        buf[(3, 1)].set_symbol("z");

        blank_area(&mut buf, Rect::new(0, 0, 2, 2));

        assert_eq!(buf[(0, 0)].symbol(), " ");
        assert_eq!(buf[(0, 0)].fg, ratatui::style::Color::Reset);
        assert_eq!(buf[(1, 1)].symbol(), " ");
        assert_eq!(buf[(3, 1)].symbol(), "z");
    }

    #[test]
    fn blank_area_clips_to_the_buffer() {
        let mut buf = Buffer::empty(Rect::new(0, 0, 2, 2));
        buf[(0, 0)].set_symbol("a");
        buf[(1, 1)].set_symbol("b");

        blank_area(&mut buf, Rect::new(1, 1, 10, 10));

        assert_eq!(buf[(1, 1)].symbol(), " ");
        assert_eq!(buf[(0, 0)].symbol(), "a");
    }
}
