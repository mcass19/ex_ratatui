// Several fields of ImageState / ProtocolCache are populated here but only
// read in the render path landing in the next chunk. Allow until then.
#![allow(dead_code)]

use std::sync::Mutex;

use image::DynamicImage;
use ratatui::layout::Rect;
use ratatui_image::protocol::StatefulProtocol;

use rustler::{Error, NifTaggedEnum, Resource, ResourceArc};

mod atoms {
    rustler::atoms! {
        decode_failed,
        unsupported_format,
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

pub struct ImageState {
    pub source: DynamicImage,
    pub requested_protocol: ProtocolKind,
    pub resize: ResizeKind,
    pub background: Option<(u8, u8, u8)>,
    pub cache: Option<ProtocolCache>,
}

pub struct ProtocolCache {
    pub active_protocol: ProtocolKind,
    pub stateful: StatefulProtocol,
    pub last_rect: Rect,
}

pub struct ImageResource {
    pub state: Mutex<ImageState>,
}

#[rustler::resource_impl]
impl Resource for ImageResource {}

#[rustler::nif]
fn image_new(bytes: rustler::Binary, opts: ImageOpts) -> Result<ResourceArc<ImageResource>, Error> {
    let source = image::load_from_memory(bytes.as_slice())
        .map_err(|e| Error::Term(Box::new((atoms::decode_failed(), format!("{e}")))))?;

    let state = ImageState {
        source,
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
        // Sanity check that the error formats to something non-empty; the NIF
        // will forward this message through `{:error, {:decode_failed, msg}}`.
        let msg = format!("{err}");
        assert!(!msg.is_empty());
    }
}
