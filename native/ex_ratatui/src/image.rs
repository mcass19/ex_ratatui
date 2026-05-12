use std::sync::Mutex;

use image::DynamicImage;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui_image::picker::{Picker, ProtocolType};
use ratatui_image::protocol::StatefulProtocol;
use ratatui_image::{FontSize, Resize, ResizeEncodeRender};

use rustler::{Env, Error, NifTaggedEnum, OwnedBinary, Resource, ResourceArc};

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
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransportCaps {
    CellOnly,
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
}
