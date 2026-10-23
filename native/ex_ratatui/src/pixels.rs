//! `pack_rgb8/4`: turns a region's RGB8 bitmap into a panel's packed pixels
//! in one pass — nearest-neighbour resample onto the rect, clip, rotate and
//! pack — writing straight into the output with no intermediate copies.
//!
//! Consumers painting regions onto a framebuffer or an e-ink panel used to
//! do this per pixel in Elixir. Here a flat, a turned and a scaled region
//! cost the same: the sampling is two lookup tables computed once, and the
//! output rows are written in order, so only the reads are strided.

use rustler::{Binary, Encoder, Env, Error, NifMap, NifTaggedEnum, OwnedBinary, Term};

mod atoms {
    rustler::atoms! {
        invalid_dimensions,
        invalid_angle,
        invalid_clip,
    }
}

/// Bytes per pixel in the RGB8 bitmaps a region carries.
const BPP: usize = 3;

/// Bayer 4×4 ordered-dither matrix; the threshold at `(x, y)` is
/// `BAYER[y % 4][x % 4] * 16 + 8`.
const BAYER: [[u32; 4]; 4] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];

/// The packed layouts `pack_rgb8/4` writes.
#[derive(Clone, Copy, Debug, PartialEq, Eq, NifTaggedEnum)]
pub enum PixelFormat {
    /// No packing: `r, g, b`.
    Rgb8,
    /// `rrrrrggg gggbbbbb`, little-endian.
    Rgb565,
    /// `b, g, r, 255`.
    Xrgb8888,
    /// One byte per pixel, `0` or `255`, from Rec. 601 luma against a
    /// Bayer 4×4 threshold anchored at the panel origin.
    MonoBayer4,
}

impl PixelFormat {
    fn bytes_per_pixel(self) -> usize {
        match self {
            PixelFormat::Rgb8 => 3,
            PixelFormat::Rgb565 => 2,
            PixelFormat::Xrgb8888 => 4,
            PixelFormat::MonoBayer4 => 1,
        }
    }
}

/// Every key is filled by `ExRatatui.Pixels.pack_rgb8/5`, which owns the
/// defaults and the friendly validation.
#[derive(Clone, Copy, Debug, NifMap)]
pub struct PackOpts {
    pub format: PixelFormat,
    /// Resample target in the app's orientation, before rotation.
    pub scale_to: (u32, u32),
    /// The top-left part of the resampled image that is kept.
    pub clip: (u32, u32),
    /// Clockwise turn: 0, 90, 180 or 270.
    pub rotate: u32,
    /// Panel position of the output's top-left pixel, for the dither.
    pub origin: (u32, u32),
}

#[rustler::nif(schedule = "DirtyCpu")]
fn pack_rgb8<'a>(
    env: Env<'a>,
    width: u32,
    height: u32,
    data: Binary<'a>,
    opts: PackOpts,
) -> Result<(Term<'a>, u32, u32), Error> {
    let (_, _, len) = pack_dims(width, height, data.len(), &opts).map_err(pack_error_term)?;

    let mut owned = OwnedBinary::new(len);

    let (out_width, out_height) =
        pack_rgb8_into(data.as_slice(), owned.as_mut_slice(), width, height, &opts)
            .map_err(pack_error_term)?;

    Ok((
        Binary::from_owned(owned, env).encode(env),
        out_width,
        out_height,
    ))
}

fn pack_error_term(error: PackError) -> Error {
    match error {
        PackError::Dimensions => Error::Term(Box::new(atoms::invalid_dimensions())),
        PackError::Angle => Error::Term(Box::new(atoms::invalid_angle())),
        PackError::Clip => Error::Term(Box::new(atoms::invalid_clip())),
    }
}

/// Why a pack request was refused; each maps to an `:invalid_*` atom.
#[derive(Debug, PartialEq, Eq)]
enum PackError {
    Dimensions,
    Angle,
    Clip,
}

/// Validates a pack request and returns the output's width, height and
/// byte length.
fn pack_dims(
    width: u32,
    height: u32,
    len: usize,
    opts: &PackOpts,
) -> Result<(u32, u32, usize), PackError> {
    if !matches!(opts.rotate, 0 | 90 | 180 | 270) {
        return Err(PackError::Angle);
    }

    let expected = (width as usize)
        .checked_mul(height as usize)
        .and_then(|pixels| pixels.checked_mul(BPP))
        .ok_or(PackError::Dimensions)?;

    if len != expected {
        return Err(PackError::Dimensions);
    }

    let (scale_w, scale_h) = opts.scale_to;
    let (clip_w, clip_h) = opts.clip;

    if clip_w > scale_w || clip_h > scale_h {
        return Err(PackError::Clip);
    }

    // Kept pixels have to be sampled from somewhere.
    if clip_w > 0 && clip_h > 0 && (width == 0 || height == 0) {
        return Err(PackError::Dimensions);
    }

    let out_len = (clip_w as usize)
        .checked_mul(clip_h as usize)
        .and_then(|pixels| pixels.checked_mul(opts.format.bytes_per_pixel()))
        .ok_or(PackError::Dimensions)?;

    let (out_width, out_height) = if matches!(opts.rotate, 90 | 270) {
        (clip_h, clip_w)
    } else {
        (clip_w, clip_h)
    };

    Ok((out_width, out_height, out_len))
}

/// Writes the packed output for `src` into `dst`.
///
/// Logical pixel `(lx, ly)` (the app's orientation, after clipping) is
/// source `(lx * w / scale_w, ly * h / scale_h)`, floored, so a region
/// clipped at the grid edge samples as if it were whole. The logical image
/// is then turned clockwise with the same corner mapping as `rotate_rgb8/4`:
/// output `(px, py)` comes from logical `(py, ch - 1 - px)` at 90,
/// `(cw - 1 - px, ch - 1 - py)` at 180 and `(cw - 1 - py, px)` at 270.
fn pack_rgb8_into(
    src: &[u8],
    dst: &mut [u8],
    width: u32,
    height: u32,
    opts: &PackOpts,
) -> Result<(u32, u32), PackError> {
    let (out_width, out_height, out_len) = pack_dims(width, height, src.len(), opts)?;

    if dst.len() != out_len {
        return Err(PackError::Dimensions);
    }

    if out_len == 0 {
        return Ok((out_width, out_height));
    }

    let (clip_w, clip_h) = (opts.clip.0 as usize, opts.clip.1 as usize);

    // Byte offset of each logical column within a source row, and of each
    // logical row within the source.
    let col_offsets: Vec<usize> = (0..clip_w)
        .map(|lx| sample(lx, width, opts.scale_to.0) * BPP)
        .collect();
    let row_offsets: Vec<usize> = (0..clip_h)
        .map(|ly| sample(ly, height, opts.scale_to.1) * width as usize * BPP)
        .collect();

    let row_bytes = out_width as usize * opts.format.bytes_per_pixel();
    let (origin_x, origin_y) = opts.origin;

    for (py, row) in dst.chunks_exact_mut(row_bytes).enumerate() {
        // Each output row holds one logical row or column fixed and walks
        // the other axis, forwards or backwards.
        let panel = (origin_x, origin_y as usize + py);

        match opts.rotate {
            0 => pack_row(
                src,
                row,
                row_offsets[py],
                col_offsets.iter(),
                opts.format,
                panel,
            ),
            90 => pack_row(
                src,
                row,
                col_offsets[py],
                row_offsets.iter().rev(),
                opts.format,
                panel,
            ),
            180 => pack_row(
                src,
                row,
                row_offsets[clip_h - 1 - py],
                col_offsets.iter().rev(),
                opts.format,
                panel,
            ),
            _ => pack_row(
                src,
                row,
                col_offsets[clip_w - 1 - py],
                row_offsets.iter(),
                opts.format,
                panel,
            ),
        }
    }

    Ok((out_width, out_height))
}

/// Floor nearest: the source index for logical index `i` when `source`
/// pixels are stretched over `target`. Computed in `u64` so `i * source`
/// cannot overflow.
fn sample(i: usize, source: u32, target: u32) -> usize {
    (i as u64 * source as u64 / target as u64) as usize
}

/// Packs one output row. Every pixel reads `src` at `base + offset`;
/// `panel` is the row's leftmost panel position, which only the dither
/// uses.
fn pack_row<'a, I>(
    src: &[u8],
    row: &mut [u8],
    base: usize,
    offsets: I,
    format: PixelFormat,
    (panel_x, panel_y): (u32, usize),
) where
    I: Iterator<Item = &'a usize>,
{
    let pixels = offsets.map(|offset| {
        let at = base + offset;
        (src[at], src[at + 1], src[at + 2])
    });

    match format {
        PixelFormat::Rgb8 => {
            for (out, (r, g, b)) in row.chunks_exact_mut(3).zip(pixels) {
                out.copy_from_slice(&[r, g, b]);
            }
        }
        PixelFormat::Rgb565 => {
            for (out, (r, g, b)) in row.chunks_exact_mut(2).zip(pixels) {
                let packed = ((r as u16 >> 3) << 11) | ((g as u16 >> 2) << 5) | (b as u16 >> 3);
                out.copy_from_slice(&packed.to_le_bytes());
            }
        }
        PixelFormat::Xrgb8888 => {
            for (out, (r, g, b)) in row.chunks_exact_mut(4).zip(pixels) {
                out.copy_from_slice(&[b, g, r, 255]);
            }
        }
        PixelFormat::MonoBayer4 => {
            let thresholds = BAYER[panel_y % 4].map(|t| t * 16 + 8);
            let phase = (panel_x % 4) as usize;

            for (i, (out, (r, g, b))) in row.iter_mut().zip(pixels).enumerate() {
                let luma = (299 * r as u32 + 587 * g as u32 + 114 * b as u32) / 1000;
                *out = if luma < thresholds[(phase + i) % 4] {
                    0
                } else {
                    255
                };
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FORMATS: [PixelFormat; 4] = [
        PixelFormat::Rgb8,
        PixelFormat::Rgb565,
        PixelFormat::Xrgb8888,
        PixelFormat::MonoBayer4,
    ];

    /// A `width * height` bitmap where every pixel is distinct, so a
    /// transposed or off-by-one sample cannot pass.
    fn bitmap(width: usize, height: usize) -> Vec<u8> {
        (0..(width * height))
            .flat_map(|i| {
                let i = i as u32;
                [(i * 7 + 1) as u8, (i * 13 + 50) as u8, (i * 29 + 100) as u8]
            })
            .collect()
    }

    fn opts(
        format: PixelFormat,
        scale_to: (u32, u32),
        clip: (u32, u32),
        rotate: u32,
        origin: (u32, u32),
    ) -> PackOpts {
        PackOpts {
            format,
            scale_to,
            clip,
            rotate,
            origin,
        }
    }

    /// Defaults as `ExRatatui.Pixels.pack_rgb8/5` fills them: no scaling,
    /// no clipping, no turn, origin `{0, 0}`.
    fn plain(format: PixelFormat, width: u32, height: u32) -> PackOpts {
        opts(format, (width, height), (width, height), 0, (0, 0))
    }

    fn pack(
        src: &[u8],
        width: u32,
        height: u32,
        opts: &PackOpts,
    ) -> Result<(Vec<u8>, u32, u32), PackError> {
        let (_, _, len) = pack_dims(width, height, src.len(), opts)?;
        let mut dst = vec![0; len];
        let (out_width, out_height) = pack_rgb8_into(src, &mut dst, width, height, opts)?;
        Ok((dst, out_width, out_height))
    }

    /// The obvious, slow path, straight from the contract: sample the
    /// clipped logical image into a `Vec`, rotate it pixel by pixel with the
    /// corner mapping, then pack each pixel at its panel position.
    fn reference_pack(src: &[u8], width: usize, height: usize, opts: &PackOpts) -> Vec<u8> {
        let (scale_w, scale_h) = (opts.scale_to.0 as usize, opts.scale_to.1 as usize);
        let (cw, ch) = (opts.clip.0 as usize, opts.clip.1 as usize);

        let mut logical = Vec::with_capacity(cw * ch);
        for ly in 0..ch {
            for lx in 0..cw {
                let (sx, sy) = (lx * width / scale_w, ly * height / scale_h);
                let at = (sy * width + sx) * BPP;
                logical.push((src[at], src[at + 1], src[at + 2]));
            }
        }

        let (out_w, out_h) = if matches!(opts.rotate, 90 | 270) {
            (ch, cw)
        } else {
            (cw, ch)
        };

        let mut out = Vec::new();
        for py in 0..out_h {
            for px in 0..out_w {
                let (lx, ly) = match opts.rotate {
                    0 => (px, py),
                    90 => (py, ch - 1 - px),
                    180 => (cw - 1 - px, ch - 1 - py),
                    _ => (cw - 1 - py, px),
                };
                let (r, g, b) = logical[ly * cw + lx];
                let (x, y) = (opts.origin.0 as usize + px, opts.origin.1 as usize + py);
                out.extend(reference_pixel(opts.format, r, g, b, x, y));
            }
        }

        out
    }

    fn reference_pixel(format: PixelFormat, r: u8, g: u8, b: u8, x: usize, y: usize) -> Vec<u8> {
        match format {
            PixelFormat::Rgb8 => vec![r, g, b],
            PixelFormat::Rgb565 => {
                let (r, g, b) = (r as u16, g as u16, b as u16);
                (((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3))
                    .to_le_bytes()
                    .to_vec()
            }
            PixelFormat::Xrgb8888 => vec![b, g, r, 255],
            PixelFormat::MonoBayer4 => {
                let luma = (299 * r as u32 + 587 * g as u32 + 114 * b as u32) / 1000;
                let threshold = BAYER[y % 4][x % 4] * 16 + 8;
                vec![if luma < threshold { 0 } else { 255 }]
            }
        }
    }

    #[test]
    fn matches_the_reference_over_a_grid_of_cases() {
        let sources = [(3, 2), (2, 5), (4, 4), (7, 3), (1, 1), (1, 4), (5, 1)];
        let scales = |w: u32, h: u32| {
            [
                (w, h),
                (w * 3, h * 2),
                (w * 2 + 1, h * 3 + 2),
                ((w / 2).max(1), (h / 2).max(1)),
                ((w * 2 / 3).max(1), h + 1),
            ]
        };

        for (w, h) in sources {
            let src = bitmap(w as usize, h as usize);

            for scale_to in scales(w, h) {
                let (sw, sh) = scale_to;
                let clips = [
                    (sw, sh),
                    (sw - sw / 3, sh),
                    (sw, sh - sh / 3),
                    ((sw / 2).max(1), (sh / 2).max(1)),
                ];

                for clip in clips {
                    for rotate in [0, 90, 180, 270] {
                        for format in FORMATS {
                            for origin in [(0, 0), (1, 3), (5, 2)] {
                                let opts = opts(format, scale_to, clip, rotate, origin);
                                let (packed, out_w, out_h) = pack(&src, w, h, &opts).unwrap();

                                assert_eq!(
                                    packed,
                                    reference_pack(&src, w as usize, h as usize, &opts),
                                    "{w}x{h} {opts:?}"
                                );

                                let expected_dims = if matches!(rotate, 90 | 270) {
                                    (clip.1, clip.0)
                                } else {
                                    clip
                                };
                                assert_eq!((out_w, out_h), expected_dims, "{w}x{h} {opts:?}");
                            }
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn rgb8_with_defaults_is_the_identity() {
        let src = bitmap(5, 3);
        assert_eq!(
            pack(&src, 5, 3, &plain(PixelFormat::Rgb8, 5, 3)).unwrap(),
            (src, 5, 3)
        );
    }

    #[test]
    fn rgb8_turns_like_rotate_rgb8() {
        // 2×1 red, blue turned 90: a 1×2 column, red on top.
        let src = [255, 0, 0, 0, 0, 255];
        let opts = opts(PixelFormat::Rgb8, (2, 1), (2, 1), 90, (0, 0));
        assert_eq!(
            pack(&src, 2, 1, &opts).unwrap(),
            (vec![255, 0, 0, 0, 0, 255], 1, 2)
        );

        let opts = PackOpts {
            rotate: 270,
            ..opts
        };
        assert_eq!(
            pack(&src, 2, 1, &opts).unwrap(),
            (vec![0, 0, 255, 255, 0, 0], 1, 2)
        );
    }

    #[test]
    fn upscaling_repeats_pixels() {
        let opts = opts(PixelFormat::Rgb8, (2, 2), (2, 2), 0, (0, 0));
        assert_eq!(
            pack(&[9, 8, 7], 1, 1, &opts).unwrap(),
            (vec![9, 8, 7, 9, 8, 7, 9, 8, 7, 9, 8, 7], 2, 2)
        );
    }

    #[test]
    fn a_clipped_region_samples_against_the_full_scale() {
        // 4 source columns over 8: each repeats twice. Keeping 3 of the 8
        // gives columns 0, 0, 1 — not the 4-over-3 resample of 0, 1, 2.
        let src = bitmap(4, 1);
        let opts = opts(PixelFormat::Rgb8, (8, 1), (3, 1), 0, (0, 0));
        let (packed, _, _) = pack(&src, 4, 1, &opts).unwrap();
        assert_eq!(packed, [&src[0..3], &src[0..3], &src[3..6]].concat());
    }

    #[test]
    fn rgb565_packs_little_endian() {
        let (packed, _, _) = pack(&[255, 0, 0], 1, 1, &plain(PixelFormat::Rgb565, 1, 1)).unwrap();
        assert_eq!(packed, [0, 248]);

        let (packed, _, _) = pack(&[0, 0, 255], 1, 1, &plain(PixelFormat::Rgb565, 1, 1)).unwrap();
        assert_eq!(packed, [31, 0]);
    }

    #[test]
    fn xrgb8888_packs_bgr_then_opaque() {
        let (packed, _, _) = pack(&[255, 0, 0], 1, 1, &plain(PixelFormat::Xrgb8888, 1, 1)).unwrap();
        assert_eq!(packed, [0, 0, 255, 255]);
    }

    #[test]
    fn mono_dithers_mid_grey_into_a_checkerboard() {
        let src = [128; 4 * 4 * 3];
        let (packed, _, _) = pack(&src, 4, 4, &plain(PixelFormat::MonoBayer4, 4, 4)).unwrap();

        #[rustfmt::skip]
        let expected = [
            255, 0, 255, 0,
            0, 255, 0, 255,
            255, 0, 255, 0,
            0, 255, 0, 255,
        ];
        assert_eq!(packed, expected);
    }

    #[test]
    fn mono_dither_is_anchored_at_the_origin() {
        // One pixel at panel (1, 0) meets threshold 8 * 16 + 8 = 136.
        let opts = opts(PixelFormat::MonoBayer4, (1, 1), (1, 1), 0, (1, 0));
        assert_eq!(pack(&[135; 3], 1, 1, &opts).unwrap().0, [0]);
        assert_eq!(pack(&[136; 3], 1, 1, &opts).unwrap().0, [255]);
    }

    #[test]
    fn an_empty_clip_returns_no_bytes_and_the_turned_dims() {
        let src = bitmap(2, 2);
        let opts = opts(PixelFormat::Rgb565, (4, 4), (0, 3), 90, (0, 0));
        assert_eq!(pack(&src, 2, 2, &opts).unwrap(), (vec![], 3, 0));

        let opts = PackOpts {
            clip: (0, 0),
            scale_to: (0, 0),
            ..opts
        };
        assert_eq!(pack(&[], 0, 0, &opts).unwrap(), (vec![], 0, 0));
    }

    #[test]
    fn rejects_a_byte_count_that_is_not_three_per_pixel() {
        assert_eq!(
            pack(&[0; 11], 2, 2, &plain(PixelFormat::Rgb8, 2, 2)),
            Err(PackError::Dimensions)
        );
    }

    #[test]
    fn rejects_unsupported_angles() {
        for rotate in [45, 360] {
            let opts = PackOpts {
                rotate,
                ..plain(PixelFormat::Rgb8, 2, 2)
            };
            assert_eq!(
                pack(&[0; 12], 2, 2, &opts),
                Err(PackError::Angle),
                "at {rotate}"
            );
        }
    }

    #[test]
    fn rejects_a_clip_larger_than_the_scale() {
        for clip in [(3, 2), (2, 3)] {
            let opts = opts(PixelFormat::Rgb8, (2, 2), clip, 0, (0, 0));
            assert_eq!(pack(&[0; 12], 2, 2, &opts), Err(PackError::Clip));
        }
    }

    #[test]
    fn rejects_kept_pixels_without_a_source() {
        let opts = opts(PixelFormat::Rgb8, (2, 2), (2, 2), 0, (0, 0));
        assert_eq!(pack(&[], 0, 2, &opts), Err(PackError::Dimensions));
    }

    #[test]
    fn rejects_dimensions_that_overflow_a_byte_count() {
        let huge = plain(PixelFormat::Rgb8, 1, 1);
        assert_eq!(
            pack_dims(u32::MAX, u32::MAX, 0, &huge),
            Err(PackError::Dimensions)
        );

        let huge_out = opts(
            PixelFormat::Xrgb8888,
            (u32::MAX, u32::MAX),
            (u32::MAX, u32::MAX),
            0,
            (0, 0),
        );
        assert_eq!(pack_dims(1, 1, 3, &huge_out), Err(PackError::Dimensions));
    }

    #[test]
    fn rejects_a_destination_of_the_wrong_size() {
        let mut dst = vec![0; 3];
        assert_eq!(
            pack_rgb8_into(&[0; 12], &mut dst, 2, 2, &plain(PixelFormat::Rgb565, 2, 2)),
            Err(PackError::Dimensions)
        );
    }
}
