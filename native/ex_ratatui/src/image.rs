use std::sync::Mutex;

use image::{imageops, DynamicImage, GenericImageView, Rgba, RgbaImage};
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui_image::picker::{Picker, ProtocolType};
use ratatui_image::protocol::StatefulProtocol;
use ratatui_image::{FontSize, Resize, ResizeEncodeRender};

use rustler::{Env, Error, NifTaggedEnum, OwnedBinary, Resource, ResourceArc};

use crate::pixel_region::{self, PixelRegion};

mod atoms {
    rustler::atoms! {
        decode_failed,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, NifTaggedEnum)]
pub enum ProtocolKind {
    Auto,
    Halfblocks,
    Kitty,
    Sixel,
    Iterm2,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, NifTaggedEnum)]
pub enum ResizeKind {
    Fit,
    Crop,
    Scale,
}

#[derive(rustler::NifMap)]
pub struct ImageOpts {
    pub protocol: ProtocolKind,
    pub resize: ResizeKind,
    pub background: Option<(u8, u8, u8)>,
}

/// Per-transport capability hint used by `resolve_protocol`.
///
/// `CellOnly` is forced for `CellSession`-style transports where escape
/// sequences can't survive cell diffing. `Local` is populated from a
/// `Picker::from_query_stdio` probe in chunk 7. `RawTerminal` is what
/// `SSH`/`Distributed` use, carrying an optional hint from a session-level
/// opt. For chunk 3 the render path uses the conservative
/// `RawTerminal { hint }` is the default for byte-stream transports
/// (SSH / Distributed / custom). `Local` is set by the local terminal
/// once `image_probe_terminal/0` has cached a `Picker::from_query_stdio`
/// result via `terminal_set_local_probe/3`.
///
/// `PixelRegions` is a `CellSession` whose consumer declared its cell pixel
/// size: pixel-mode widgets rasterize to RGB8 and ship the bitmap out of
/// band (see `crate::pixel_region`) instead of encoding a terminal protocol.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransportCaps {
    CellOnly,
    PixelRegions {
        font_size: (u16, u16),
    },
    Local {
        picker_protocol: ProtocolKind,
        font_size: (u16, u16),
    },
    RawTerminal {
        hint: Option<ProtocolKind>,
    },
}

impl TransportCaps {
    pub fn font_size(&self) -> (u16, u16) {
        match self {
            TransportCaps::Local { font_size, .. } => *font_size,
            TransportCaps::PixelRegions { font_size } => *font_size,
            // 8x16 is a reasonable terminal default. Refined in chunk 7
            // when we probe the local terminal for the real cell pixel size.
            _ => (8, 16),
        }
    }
}

pub fn resolve_protocol(requested: ProtocolKind, caps: TransportCaps) -> ProtocolKind {
    match (requested, caps) {
        // Cell-based transports can only carry halfblocks. Forced fallback.
        (_, TransportCaps::CellOnly) => ProtocolKind::Halfblocks,
        // Pixel-region sessions never encode a protocol: the widget dispatch
        // turns any pixel request into a region, so the request passes
        // through untouched (an explicit `:halfblocks` stays a cell mode).
        (requested, TransportCaps::PixelRegions { .. }) => requested,
        (
            ProtocolKind::Auto,
            TransportCaps::Local {
                picker_protocol, ..
            },
        ) => picker_protocol,
        (ProtocolKind::Auto, TransportCaps::RawTerminal { hint: Some(h) }) => h,
        (ProtocolKind::Auto, TransportCaps::RawTerminal { hint: None }) => ProtocolKind::Halfblocks,
        (explicit, _) => explicit,
    }
}

fn to_protocol_type(kind: ProtocolKind) -> ProtocolType {
    match kind {
        ProtocolKind::Halfblocks | ProtocolKind::Auto => ProtocolType::Halfblocks,
        ProtocolKind::Kitty => ProtocolType::Kitty,
        ProtocolKind::Sixel => ProtocolType::Sixel,
        ProtocolKind::Iterm2 => ProtocolType::Iterm2,
    }
}

pub fn from_protocol_type(t: ProtocolType) -> ProtocolKind {
    match t {
        ProtocolType::Halfblocks => ProtocolKind::Halfblocks,
        ProtocolType::Kitty => ProtocolKind::Kitty,
        ProtocolType::Sixel => ProtocolKind::Sixel,
        ProtocolType::Iterm2 => ProtocolKind::Iterm2,
    }
}

fn to_resize(kind: ResizeKind) -> Resize {
    match kind {
        ResizeKind::Fit => Resize::Fit(None),
        ResizeKind::Crop => Resize::Crop(None),
        ResizeKind::Scale => Resize::Scale(None),
    }
}

pub struct ImageState {
    pub source: DynamicImage,
    // Original encoded bytes, retained so `image_snapshot/1` can ship
    // them across a BEAM distribution boundary for re-decoding on the
    // receiving node. Adds ~PNG-size memory per image (typically much
    // smaller than the decoded `source` RGB buffer); without this we
    // couldn't render images over `ExRatatui.Distributed`.
    pub source_bytes: Vec<u8>,
    pub requested_protocol: ProtocolKind,
    pub resize: ResizeKind,
    pub background: Option<(u8, u8, u8)>,
    pub cache: Option<ProtocolCache>,
}

pub struct ProtocolCache {
    pub active_protocol: ProtocolKind,
    pub stateful: StatefulProtocol,
}

pub struct ImageResource {
    pub state: Mutex<ImageState>,
}

#[rustler::resource_impl]
impl Resource for ImageResource {}

pub struct ImageRenderData {
    pub resource: ResourceArc<ImageResource>,
}

pub fn render(buf: &mut Buffer, data: &ImageRenderData, area: Rect, caps: TransportCaps) {
    let mut state = match data.resource.state.lock() {
        Ok(s) => s,
        Err(_) => return,
    };
    render_state(buf, &mut state, area, caps);
}

pub fn render_state(buf: &mut Buffer, state: &mut ImageState, area: Rect, caps: TransportCaps) {
    if area.width == 0 || area.height == 0 {
        return;
    }

    // A surface with real pixels: any pixel request becomes a region. An
    // explicit `:halfblocks` is a cell mode and keeps the cell path.
    if let TransportCaps::PixelRegions { font_size } = caps {
        if state.requested_protocol != ProtocolKind::Halfblocks {
            render_region(buf, state, area, font_size);
            return;
        }
    }

    let resolved = resolve_protocol(state.requested_protocol, caps);

    // Rebuild the encoder state when the resolved protocol changes (or on
    // first render). `StatefulProtocol` then manages its own resize cache
    // across subsequent renders.
    let needs_rebuild = state
        .cache
        .as_ref()
        .map(|c| c.active_protocol != resolved)
        .unwrap_or(true);

    if needs_rebuild {
        let stateful = build_stateful_protocol(state, resolved, caps.font_size());
        state.cache = Some(ProtocolCache {
            active_protocol: resolved,
            stateful,
        });
    }

    let resize = to_resize(state.resize);
    if let Some(cache) = state.cache.as_mut() {
        cache.stateful.resize_encode_render(&resize, area, buf);
    }
}

/// Pixel-region rendering. Mirrors ratatui-image's `Resize` semantics on
/// the decoded source (`Fit` never upscales, `Scale` always fills, `Crop`
/// clips bottom/right), anchors the picture at the area's top-left, and
/// ships it as an RGB8 region. With a `background` the region covers the
/// whole area and the colour fills what the picture does not; without one
/// the region only covers the cells the picture touches, padded to whole
/// cells in black. Either way the bitmap is an exact multiple of the cell
/// size (or the capped size), so consumers scale it uniformly.
fn render_region(buf: &mut Buffer, state: &ImageState, area: Rect, font_size: (u16, u16)) {
    let (fw, fh) = (font_size.0 as u32, font_size.1 as u32);
    let (target_w, target_h) = pixel_region::rect_pixel_dims(area, font_size);
    let picture = fit_source(&state.source, state.resize, target_w, target_h);
    let (pw, ph) = picture.dimensions();

    let (rect, canvas_w, canvas_h) = match state.background {
        Some(_) => (area, target_w, target_h),
        None => {
            let cols = pw.div_ceil(fw).min(area.width as u32) as u16;
            let rows = ph.div_ceil(fh).min(area.height as u32) as u16;
            let rect = Rect::new(area.x, area.y, cols, rows);
            (rect, cols as u32 * fw, rows as u32 * fh)
        }
    };

    if rect.width == 0 || rect.height == 0 {
        return;
    }

    let (r, g, b) = state.background.unwrap_or((0, 0, 0));
    let mut canvas = RgbaImage::from_pixel(canvas_w, canvas_h, Rgba([r, g, b, 255]));
    imageops::overlay(&mut canvas, &picture, 0, 0);
    let data = DynamicImage::ImageRgba8(canvas).to_rgb8().into_raw();

    pixel_region::blank_area(buf, rect);
    pixel_region::push(PixelRegion {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        pixel_width: canvas_w,
        pixel_height: canvas_h,
        data,
    });
}

/// The source picture sized for a `target_w × target_h` pixel box.
fn fit_source(
    source: &DynamicImage,
    resize: ResizeKind,
    target_w: u32,
    target_h: u32,
) -> DynamicImage {
    let (w, h) = source.dimensions();
    match resize {
        ResizeKind::Fit if w <= target_w && h <= target_h => source.clone(),
        ResizeKind::Fit | ResizeKind::Scale => {
            source.resize(target_w, target_h, imageops::FilterType::Nearest)
        }
        ResizeKind::Crop => source.crop_imm(0, 0, w.min(target_w), h.min(target_h)),
    }
}

fn build_stateful_protocol(
    state: &ImageState,
    protocol: ProtocolKind,
    font_size: (u16, u16),
) -> StatefulProtocol {
    // `Picker::from_fontsize` is deprecated in favor of `from_query_stdio`,
    // but we need an explicit font size for Kitty/Sixel/iTerm2 without the
    // blocking stdio probe inside the render path. Chunk 7 replaces this
    // with a `Picker` cached on the session at start-up (or on the resource
    // when distributed) and font size threaded through `TransportCaps`.
    #[allow(deprecated)]
    let mut picker = Picker::from_fontsize(FontSize::from(font_size));
    picker.set_protocol_type(to_protocol_type(protocol));
    if let Some((r, g, b)) = state.background {
        picker.set_background_color(Some(image::Rgba([r, g, b, 255])));
    }
    picker.new_resize_protocol(state.source.clone())
}

/// Encode an already-decoded image into `area` using a concrete graphics
/// `protocol` (Kitty/Sixel/iTerm2 — `Halfblocks`/`Auto` are expected to be
/// resolved away by the caller). `font_size` is the cell pixel size from the
/// transport probe. Used by `Viewport3D` pixel rendering, which generates its
/// image in-process rather than decoding consumer bytes.
///
/// Uses `Resize::Scale` so the image fills `area` (preserving aspect), scaling
/// up when the source is smaller than the render area — `Resize::Fit` would
/// leave a downsized source anchored in the corner.
pub fn render_image_protocol(
    buf: &mut Buffer,
    area: Rect,
    source: DynamicImage,
    protocol: ProtocolKind,
    font_size: (u16, u16),
) {
    if area.width == 0 || area.height == 0 {
        return;
    }

    #[allow(deprecated)]
    let mut picker = Picker::from_fontsize(FontSize::from(font_size));
    picker.set_protocol_type(to_protocol_type(protocol));
    let mut stateful = picker.new_resize_protocol(source);
    stateful.resize_encode_render(&Resize::Scale(None), area, buf);
}

#[rustler::nif]
fn image_new(bytes: rustler::Binary, opts: ImageOpts) -> Result<ResourceArc<ImageResource>, Error> {
    let raw = bytes.as_slice();
    let source = image::load_from_memory(raw)
        .map_err(|e| Error::Term(Box::new((atoms::decode_failed(), format!("{e}")))))?;

    let state = ImageState {
        source,
        source_bytes: raw.to_vec(),
        requested_protocol: opts.protocol,
        resize: opts.resize,
        background: opts.background,
        cache: None,
    };

    Ok(ResourceArc::new(ImageResource {
        state: Mutex::new(state),
    }))
}

#[rustler::nif]
fn image_dimensions(resource: ResourceArc<ImageResource>) -> Result<(u32, u32), Error> {
    let state = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("image lock poisoned")))?;
    Ok((state.source.width(), state.source.height()))
}

/// Returns the data needed to reconstruct this image on another BEAM
/// node: a flat tuple `{bytes, protocol_atom, resize_atom, background}`
/// where `background` is either `nil` or `{r, g, b}`. The receiving
/// node decodes the bytes into a fresh `ImageResource` via the snapshot
/// branch of `decode_image`. Used by `ExRatatui.Distributed` — a NIF
/// resource ref can't cross node boundaries, so the runtime snapshots
/// stateful widgets before sending the render tree over the wire.
// Tuple shape returned by `image_snapshot/1` and accepted by the
// distributed branch of `decode_image`. Aliased so the NIF's return
// type isn't flagged as "very complex" by clippy.
pub type ImageSnapshot<'a> = (
    rustler::Binary<'a>,
    ProtocolKind,
    ResizeKind,
    Option<(u8, u8, u8)>,
);

#[rustler::nif]
fn image_snapshot<'a>(
    env: Env<'a>,
    resource: ResourceArc<ImageResource>,
) -> Result<ImageSnapshot<'a>, Error> {
    let state = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("image lock poisoned")))?;
    let mut owned = OwnedBinary::new(state.source_bytes.len()).unwrap_or_else(|| {
        OwnedBinary::new(0).expect("zero-length OwnedBinary allocation cannot fail")
    });
    if !state.source_bytes.is_empty() {
        owned.as_mut_slice().copy_from_slice(&state.source_bytes);
    }
    Ok((
        rustler::Binary::from_owned(owned, env),
        state.requested_protocol,
        state.resize,
        state.background,
    ))
}

/// Queries the local terminal for image-protocol capabilities and font
/// size via `Picker::from_query_stdio()`. Runs on a dirty IO scheduler
/// because it writes a query escape sequence to stdout and waits for the
/// terminal's response on stdin. Returns the detected protocol and
/// `{width, height}` cell pixel size on success, or an error tuple when
/// the probe couldn't complete (no TTY, no response, etc.).
///
/// Callers can pipe the result into `terminal_set_local_probe/3` to make
/// `protocol: :auto` images render using the detected protocol.
#[rustler::nif(schedule = "DirtyIo")]
fn image_probe_terminal() -> Result<(ProtocolKind, (u16, u16)), Error> {
    let picker = Picker::from_query_stdio()
        .map_err(|e| Error::Term(Box::new(format!("probe failed: {e:?}"))))?;
    let proto = from_protocol_type(picker.protocol_type());
    let fs = picker.font_size();
    Ok((proto, (fs.width, fs.height)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tiny_red_png() -> Vec<u8> {
        let buf = image::RgbImage::from_fn(2, 2, |_, _| image::Rgb([255, 0, 0]));
        let dynamic = DynamicImage::ImageRgb8(buf);
        let mut out: Vec<u8> = Vec::new();
        dynamic
            .write_to(&mut std::io::Cursor::new(&mut out), image::ImageFormat::Png)
            .expect("encode test PNG");
        out
    }

    #[test]
    fn decodes_png_bytes() {
        let bytes = tiny_red_png();
        let decoded =
            image::load_from_memory(&bytes).expect("png bytes should decode via image crate");
        assert_eq!(decoded.width(), 2);
        assert_eq!(decoded.height(), 2);
    }

    #[test]
    fn rejects_garbage_bytes() {
        let garbage = b"not an image, not even close";
        let err = image::load_from_memory(garbage).unwrap_err();
        let msg = format!("{err}");
        assert!(!msg.is_empty());
    }

    #[test]
    fn resolve_protocol_cell_only_always_halfblocks() {
        for requested in [
            ProtocolKind::Auto,
            ProtocolKind::Halfblocks,
            ProtocolKind::Kitty,
            ProtocolKind::Sixel,
            ProtocolKind::Iterm2,
        ] {
            assert_eq!(
                resolve_protocol(requested, TransportCaps::CellOnly),
                ProtocolKind::Halfblocks,
                "CellOnly must force halfblocks for {requested:?}",
            );
        }
    }

    #[test]
    fn resolve_protocol_auto_on_local_uses_picker() {
        let caps = TransportCaps::Local {
            picker_protocol: ProtocolKind::Kitty,
            font_size: (10, 20),
        };
        assert_eq!(
            resolve_protocol(ProtocolKind::Auto, caps),
            ProtocolKind::Kitty,
        );
    }

    #[test]
    fn resolve_protocol_auto_on_raw_terminal_uses_hint_or_halfblocks() {
        let with_hint = TransportCaps::RawTerminal {
            hint: Some(ProtocolKind::Sixel),
        };
        let no_hint = TransportCaps::RawTerminal { hint: None };
        assert_eq!(
            resolve_protocol(ProtocolKind::Auto, with_hint),
            ProtocolKind::Sixel,
        );
        assert_eq!(
            resolve_protocol(ProtocolKind::Auto, no_hint),
            ProtocolKind::Halfblocks,
        );
    }

    #[test]
    fn resolve_protocol_explicit_is_honored_outside_cell_only() {
        let local = TransportCaps::Local {
            picker_protocol: ProtocolKind::Halfblocks,
            font_size: (8, 16),
        };
        assert_eq!(
            resolve_protocol(ProtocolKind::Kitty, local),
            ProtocolKind::Kitty,
        );
        let raw = TransportCaps::RawTerminal { hint: None };
        assert_eq!(
            resolve_protocol(ProtocolKind::Iterm2, raw),
            ProtocolKind::Iterm2,
        );
    }

    fn fresh_state(protocol: ProtocolKind, resize: ResizeKind) -> ImageState {
        let bytes = tiny_red_png();
        let source = image::load_from_memory(&bytes).unwrap();
        ImageState {
            source,
            source_bytes: bytes,
            requested_protocol: protocol,
            resize,
            background: None,
            cache: None,
        }
    }

    #[test]
    fn render_state_halfblocks_paints_buffer() {
        let mut state = fresh_state(ProtocolKind::Halfblocks, ResizeKind::Fit);
        let area = Rect::new(0, 0, 4, 4);
        let mut buf = Buffer::empty(area);
        render_state(&mut buf, &mut state, area, TransportCaps::CellOnly);

        let any_painted = (0..area.width).any(|x| {
            (0..area.height).any(|y| {
                let cell = buf.cell((x, y)).expect("cell in bounds");
                cell.symbol() != " "
            })
        });
        assert!(
            any_painted,
            "halfblocks render should paint at least one cell"
        );

        let cache = state.cache.as_ref().expect("cache populated after render");
        assert_eq!(cache.active_protocol, ProtocolKind::Halfblocks);
    }

    #[test]
    fn render_state_noop_on_zero_area() {
        let mut state = fresh_state(ProtocolKind::Halfblocks, ResizeKind::Fit);
        let zero = Rect::new(0, 0, 0, 0);
        let mut buf = Buffer::empty(zero);
        render_state(&mut buf, &mut state, zero, TransportCaps::CellOnly);
        assert!(state.cache.is_none(), "no cache built for zero-area render");
    }

    #[test]
    fn render_state_cell_only_forces_halfblocks_even_when_kitty_requested() {
        let mut state = fresh_state(ProtocolKind::Kitty, ResizeKind::Fit);
        let area = Rect::new(0, 0, 4, 4);
        let mut buf = Buffer::empty(area);
        render_state(&mut buf, &mut state, area, TransportCaps::CellOnly);
        let cache = state.cache.as_ref().expect("cache populated");
        assert_eq!(cache.active_protocol, ProtocolKind::Halfblocks);
    }

    #[test]
    fn render_state_rebuilds_cache_when_caps_change_protocol() {
        let mut state = fresh_state(ProtocolKind::Auto, ResizeKind::Fit);
        let area = Rect::new(0, 0, 4, 4);
        let mut buf = Buffer::empty(area);
        render_state(&mut buf, &mut state, area, TransportCaps::CellOnly);
        assert_eq!(
            state.cache.as_ref().unwrap().active_protocol,
            ProtocolKind::Halfblocks,
        );

        // Now render with a Local cap that prefers Kitty — cache should rebuild.
        let local = TransportCaps::Local {
            picker_protocol: ProtocolKind::Kitty,
            font_size: (10, 20),
        };
        render_state(&mut buf, &mut state, area, local);
        assert_eq!(
            state.cache.as_ref().unwrap().active_protocol,
            ProtocolKind::Kitty,
        );
    }

    // ---- pixel regions --------------------------------------------------

    const REGION_CAPS: TransportCaps = TransportCaps::PixelRegions { font_size: (6, 8) };

    fn solid_png(width: u32, height: u32, rgb: [u8; 3]) -> Vec<u8> {
        let buf = image::RgbImage::from_fn(width, height, |_, _| image::Rgb(rgb));
        let mut out: Vec<u8> = Vec::new();
        DynamicImage::ImageRgb8(buf)
            .write_to(&mut std::io::Cursor::new(&mut out), image::ImageFormat::Png)
            .expect("encode test PNG");
        out
    }

    fn state_from(
        bytes: Vec<u8>,
        resize: ResizeKind,
        background: Option<(u8, u8, u8)>,
    ) -> ImageState {
        let source = image::load_from_memory(&bytes).unwrap();
        ImageState {
            source,
            source_bytes: bytes,
            requested_protocol: ProtocolKind::Auto,
            resize,
            background,
            cache: None,
        }
    }

    fn render_regions(state: &mut ImageState, area: Rect) -> (Buffer, Vec<PixelRegion>) {
        let mut buf = Buffer::empty(area);
        pixel_region::begin_collecting();
        render_state(&mut buf, state, area, REGION_CAPS);
        (buf, pixel_region::finish_collecting())
    }

    fn pixel(region: &PixelRegion, x: u32, y: u32) -> [u8; 3] {
        let i = ((y * region.pixel_width + x) * 3) as usize;
        [region.data[i], region.data[i + 1], region.data[i + 2]]
    }

    #[test]
    fn region_fit_keeps_a_small_source_at_native_size_padded_to_whole_cells() {
        let mut state = state_from(solid_png(2, 2, [255, 0, 0]), ResizeKind::Fit, None);
        let (buf, regions) = render_regions(&mut state, Rect::new(0, 0, 4, 4));

        assert_eq!(regions.len(), 1);
        let region = &regions[0];
        assert_eq!(
            (region.x, region.y, region.width, region.height),
            (0, 0, 1, 1)
        );
        assert_eq!((region.pixel_width, region.pixel_height), (6, 8));
        assert_eq!(region.data.len(), 6 * 8 * 3);
        assert_eq!(pixel(region, 0, 0), [255, 0, 0]);
        assert_eq!(pixel(region, 1, 1), [255, 0, 0]);
        assert_eq!(
            pixel(region, 2, 2),
            [0, 0, 0],
            "padding is black without a background"
        );
        assert_eq!(buf[(0, 0)].symbol(), " ");
        assert!(
            state.cache.is_none(),
            "no protocol encoder is built for a region"
        );
    }

    #[test]
    fn region_scale_fills_the_area_preserving_aspect() {
        let mut state = state_from(solid_png(2, 2, [0, 255, 0]), ResizeKind::Scale, None);
        let (_buf, regions) = render_regions(&mut state, Rect::new(0, 0, 4, 4));

        // 24x32 px box, square source -> 24x24 -> 4 cols x 3 rows of cells.
        let region = &regions[0];
        assert_eq!((region.width, region.height), (4, 3));
        assert_eq!((region.pixel_width, region.pixel_height), (24, 24));
        assert_eq!(pixel(region, 23, 23), [0, 255, 0]);
    }

    #[test]
    fn region_crop_clips_the_bottom_and_right() {
        let mut state = state_from(solid_png(10, 10, [0, 0, 255]), ResizeKind::Crop, None);
        let (_buf, regions) = render_regions(&mut state, Rect::new(0, 0, 1, 1));

        let region = &regions[0];
        assert_eq!((region.width, region.height), (1, 1));
        assert_eq!((region.pixel_width, region.pixel_height), (6, 8));
        assert!(region.data.chunks(3).all(|px| px == [0, 0, 255]));
    }

    #[test]
    fn region_with_background_covers_the_whole_area() {
        let mut state = state_from(
            solid_png(2, 2, [255, 0, 0]),
            ResizeKind::Fit,
            Some((1, 2, 3)),
        );
        let (buf, regions) = render_regions(&mut state, Rect::new(2, 1, 4, 4));

        let region = &regions[0];
        assert_eq!(
            (region.x, region.y, region.width, region.height),
            (2, 1, 4, 4)
        );
        assert_eq!((region.pixel_width, region.pixel_height), (24, 32));
        assert_eq!(pixel(region, 0, 0), [255, 0, 0]);
        assert_eq!(pixel(region, 23, 31), [1, 2, 3]);
        assert_eq!(buf[(5, 4)].symbol(), " ");
    }

    #[test]
    fn region_fit_downsizes_a_large_source() {
        let mut state = state_from(solid_png(100, 50, [9, 9, 9]), ResizeKind::Fit, None);
        let (_buf, regions) = render_regions(&mut state, Rect::new(0, 0, 4, 4));

        // 24x32 box, 2:1 source -> 24x12 -> 4 cols x 2 rows.
        let region = &regions[0];
        assert_eq!((region.width, region.height), (4, 2));
        assert_eq!((region.pixel_width, region.pixel_height), (24, 16));
    }

    #[test]
    fn region_is_capped_on_its_longest_side() {
        let mut state = state_from(
            solid_png(2, 2, [255, 0, 0]),
            ResizeKind::Scale,
            Some((0, 0, 0)),
        );
        let (_buf, regions) = render_regions(&mut state, Rect::new(0, 0, 300, 200));

        let region = &regions[0];
        assert_eq!((region.width, region.height), (300, 200));
        assert_eq!(
            region.pixel_width.max(region.pixel_height),
            pixel_region::MAX_DIM
        );
    }

    #[test]
    fn explicit_halfblocks_stays_a_cell_mode_on_a_pixel_region_session() {
        let mut state = fresh_state(ProtocolKind::Halfblocks, ResizeKind::Fit);
        let (buf, regions) = render_regions(&mut state, Rect::new(0, 0, 4, 4));

        assert!(regions.is_empty());
        assert_eq!(
            state.cache.as_ref().unwrap().active_protocol,
            ProtocolKind::Halfblocks
        );
        assert!((0..4).any(|x| buf[(x, 0)].symbol() != " "));
    }

    #[test]
    fn rgba_sources_blend_over_the_background() {
        let buf = image::RgbaImage::from_fn(2, 2, |_, _| image::Rgba([255, 255, 255, 0]));
        let mut bytes: Vec<u8> = Vec::new();
        DynamicImage::ImageRgba8(buf)
            .write_to(
                &mut std::io::Cursor::new(&mut bytes),
                image::ImageFormat::Png,
            )
            .unwrap();
        let mut state = state_from(bytes, ResizeKind::Fit, Some((10, 20, 30)));
        let (_buf, regions) = render_regions(&mut state, Rect::new(0, 0, 1, 1));

        // Fully transparent white over the background reads as the background.
        assert_eq!(pixel(&regions[0], 0, 0), [10, 20, 30]);
    }
}
