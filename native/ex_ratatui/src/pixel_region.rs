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
