//! Per-connection terminal session with a pluggable writer and an injectable
//! event queue.
//!
//! Unlike [`crate::terminal::TerminalResource`], a [`SessionResource`] is
//! decoupled from the OS process stdin/stdout. It writes rendered frames into
//! an in-memory buffer that the Elixir side drains and ships over whatever
//! transport is in use (SSH channel, TCP socket, custom). Input bytes flow the
//! other way — parsed by a `vte`-based state machine into the same
//! `ExEvent` values the existing polling path emits — so transports can feed
//! raw bytes without knowing anything about ANSI.
//!
//! A `SessionResource` never touches real stdout, never enables raw mode, and
//! never enters the alt screen. Those are the transport's responsibility (for
//! SSH, the client already did it). This is what makes it safe to run many
//! concurrent sessions in one BEAM node without global state collisions.

use std::io::{self, Write};
use std::sync::{Arc, Mutex};

use ratatui::backend::{Backend, ClearType, CrosstermBackend, WindowSize};
use ratatui::buffer::Cell;
use ratatui::layout::{Position, Rect, Size};
use ratatui::{Terminal, TerminalOptions, Viewport};

use rustler::{Atom, Binary, Env, Error, OwnedBinary, Resource, ResourceArc, Term};

use crate::events::NifEvent;
use crate::image::TransportCaps;
use crate::rendering::{decode_render_commands, render_widget_data, RenderCommand};
use crate::session_input::InputParser;

mod atoms {
    rustler::atoms! {
        ok,
    }
}

/// A `Write`-implementing buffer shared between the ratatui backend and
/// Elixir. Crossterm writes ANSI bytes into the inner `Vec<u8>`; Elixir drains
/// it via `session_take_output` and ships the bytes over the transport.
///
/// The inner buffer is wrapped in `Arc<Mutex<_>>` so the clone stored on the
/// `SessionResource` and the clone owned by the `CrosstermBackend` point at
/// the same bytes.
#[derive(Clone)]
pub struct SharedWriter {
    buf: Arc<Mutex<Vec<u8>>>,
}

impl SharedWriter {
    pub fn new() -> Self {
        Self {
            buf: Arc::new(Mutex::new(Vec::new())),
        }
    }

    /// Drains the buffer, returning everything written since the last drain.
    /// Returns an empty `Vec` if the buffer is empty or the mutex is poisoned
    /// (the only path to poisoning is a panic while holding the lock, which
    /// would indicate a bug worth investigating but should not propagate to
    /// the BEAM as an NIF failure).
    #[allow(dead_code)]
    pub fn drain(&self) -> Vec<u8> {
        match self.buf.lock() {
            Ok(mut guard) => std::mem::take(&mut *guard),
            Err(_) => Vec::new(),
        }
    }
}

impl Default for SharedWriter {
    fn default() -> Self {
        Self::new()
    }
}

impl Write for SharedWriter {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        match self.buf.lock() {
            Ok(mut guard) => {
                guard.extend_from_slice(bytes);
                Ok(bytes.len())
            }
            Err(_) => Err(io::Error::other("session writer mutex poisoned")),
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

/// A [`Backend`] that wraps [`CrosstermBackend`] but answers size queries from
/// a cached value instead of probing the host tty.
///
/// ratatui's fixed-viewport [`Terminal::resize`] path clears the viewport via
/// `Backend::size` to choose the cheapest clear strategy.
/// `CrosstermBackend::size` delegates to `crossterm::terminal::size()`, which
/// ioctls the real terminal. Under the BEAM — and in CI, where the test
/// binary's stdout is a pipe rather than a tty — that query fails, surfacing
/// as `session resize: Resource temporarily unavailable (os error 11)`. A
/// session owns its dimensions (the transport dictates them), so there is
/// never a reason to ask the OS. We answer `size`/`window_size` from the
/// cached value and delegate every other method straight through to
/// crossterm, which only ever writes ANSI into the `SharedWriter`.
pub(crate) struct FixedSizeBackend {
    inner: CrosstermBackend<SharedWriter>,
    size: Size,
}

impl FixedSizeBackend {
    fn new(inner: CrosstermBackend<SharedWriter>, size: Size) -> Self {
        Self { inner, size }
    }

    /// Updates the cached size. Called from [`SessionResource::resize`] before
    /// the underlying `Terminal::resize` so the clear path sees the new
    /// dimensions and takes the full-viewport fast path.
    fn set_size(&mut self, size: Size) {
        self.size = size;
    }
}

impl Backend for FixedSizeBackend {
    type Error = io::Error;

    fn draw<'a, I>(&mut self, content: I) -> io::Result<()>
    where
        I: Iterator<Item = (u16, u16, &'a Cell)>,
    {
        self.inner.draw(content)
    }

    fn append_lines(&mut self, n: u16) -> io::Result<()> {
        self.inner.append_lines(n)
    }

    fn hide_cursor(&mut self) -> io::Result<()> {
        self.inner.hide_cursor()
    }

    fn show_cursor(&mut self) -> io::Result<()> {
        self.inner.show_cursor()
    }

    fn get_cursor_position(&mut self) -> io::Result<Position> {
        self.inner.get_cursor_position()
    }

    fn set_cursor_position<P: Into<Position>>(&mut self, position: P) -> io::Result<()> {
        self.inner.set_cursor_position(position)
    }

    fn clear(&mut self) -> io::Result<()> {
        self.inner.clear()
    }

    fn clear_region(&mut self, clear_type: ClearType) -> io::Result<()> {
        self.inner.clear_region(clear_type)
    }

    /// Answered from the cached session size — never queries the host tty.
    fn size(&self) -> io::Result<Size> {
        Ok(self.size)
    }

    /// Answered from the cached session size. Pixel dimensions are reported as
    /// zero; the image render path uses the explicitly-configured font size
    /// rather than probing the terminal.
    fn window_size(&mut self) -> io::Result<WindowSize> {
        Ok(WindowSize {
            columns_rows: self.size,
            pixels: Size::new(0, 0),
        })
    }

    fn flush(&mut self) -> io::Result<()> {
        Backend::flush(&mut self.inner)
    }
}

/// Per-session resource. Holds its own terminal, writer, input parser
/// and current size. Protected by coarse mutexes because all NIF entry
/// points are short-running and the contention per session is effectively
/// zero (one BEAM process per session).
///
/// The `terminal` slot is an `Option` so `session_close` can drop the
/// underlying ratatui `Terminal` (and the backend's writer clone with it)
/// without waiting for the BEAM garbage collector. Subsequent operations on
/// a closed session surface a clear error instead of panicking.
pub struct SessionResource {
    pub(crate) terminal: Mutex<Option<Terminal<FixedSizeBackend>>>,
    pub(crate) writer: SharedWriter,
    pub(crate) input: Mutex<InputParser>,
    pub(crate) size: Mutex<(u16, u16)>,
    // Set via `session_set_image_protocol/2`. When `Some(_)` it becomes the
    // hint inside `TransportCaps::RawTerminal { hint: ... }` used by the
    // image render path, so `:auto` resolves to the user-chosen protocol
    // instead of falling back to halfblocks.
    pub(crate) image_protocol: Mutex<Option<crate::image::ProtocolKind>>,
    // Set via `session_set_image_font_size/2`. When both this and
    // `image_protocol` are set, `session_draw` emits
    // `TransportCaps::Local { picker_protocol, font_size }` so the
    // Kitty / Sixel / iTerm2 encoder uses the correct cell pixel size
    // for the client terminal. Without it the picker falls back to the
    // ratatui-image default `(8, 16)` which mis-scales on most
    // terminals (Kitty/Ghostty default to roughly `(10, 20)`).
    pub(crate) image_font_size: Mutex<Option<(u16, u16)>>,
}

#[rustler::resource_impl]
impl Resource for SessionResource {}

impl SessionResource {
    /// Creates a new session at the given size. Returns the bare struct; NIF
    /// entry points are responsible for wrapping it in a `ResourceArc`. This
    /// split lets unit tests exercise construction without going through the
    /// Rustler resource registry (which is only initialised at NIF load time).
    ///
    /// The underlying ratatui `Terminal` is built with a [`Viewport::Fixed`]
    /// viewport so autoresize is a no-op during draws, and its backend is a
    /// [`FixedSizeBackend`] so size queries are answered from the cached
    /// session dimensions rather than `crossterm::terminal::size()` (which
    /// ioctls the host tty, fails under the BEAM, and fundamentally violates
    /// the "transport controls the size" contract). Together these keep
    /// concurrent sessions from ever drifting into — or choking on — the
    /// host's terminal dimensions. The fixed-viewport `resize` path reaches
    /// `Backend::size` while clearing, so the backend override is what makes
    /// resize safe off a tty, not the viewport choice alone.
    ///
    /// No OS-level state is touched — no raw mode, no alt screen, no signal
    /// handlers.
    pub fn new(width: u16, height: u16) -> Result<Self, String> {
        let writer = SharedWriter::new();
        let backend = FixedSizeBackend::new(
            CrosstermBackend::new(writer.clone()),
            Size::new(width, height),
        );
        let options = TerminalOptions {
            viewport: Viewport::Fixed(Rect::new(0, 0, width, height)),
        };
        let terminal = Terminal::with_options(backend, options)
            .map_err(|e| format!("session terminal init: {e}"))?;

        Ok(Self {
            terminal: Mutex::new(Some(terminal)),
            writer,
            input: Mutex::new(InputParser::new()),
            size: Mutex::new((width, height)),
            image_protocol: Mutex::new(None),
            image_font_size: Mutex::new(None),
        })
    }

    /// Drops the inner ratatui `Terminal`, releasing the backend's clone of
    /// the `SharedWriter`. Idempotent — calling `close` twice is a no-op and
    /// does not surface an error. After `close`, the session still owns its
    /// writer handle so pending output can be drained by the caller, but any
    /// further draw/resize operation will return an error.
    pub fn close(&self) -> Result<(), String> {
        let mut guard = self
            .terminal
            .lock()
            .map_err(|_| "session terminal lock poisoned".to_string())?;
        *guard = None;
        Ok(())
    }

    /// Renders a list of `(widget, area)` commands into the session's
    /// terminal. Bytes land in the `SharedWriter` and stay there until the
    /// transport drains them via [`SessionResource::take_output`]. Returns
    /// an error if the session has been closed.
    pub fn draw(&self, commands: Vec<RenderCommand>) -> Result<(), String> {
        let mut guard = self
            .terminal
            .lock()
            .map_err(|_| "session terminal lock poisoned".to_string())?;
        let terminal = guard
            .as_mut()
            .ok_or_else(|| "session is closed".to_string())?;

        // Byte-stream session (SSH / Distributed / custom transport):
        // - With BOTH `image_protocol` and `image_font_size` set, we
        //   emit `Local { picker_protocol, font_size }` so the encoder
        //   gets correct cell pixel dimensions for accurate scaling.
        // - With only `image_protocol`, fall back to RawTerminal hint;
        //   font size defaults to ratatui-image's built-in (8, 16)
        //   inside the render path.
        // - With neither, `:auto` resolves to halfblocks per the
        //   `RawTerminal { hint: None }` default.
        let hint = self.image_protocol.lock().map(|g| *g).unwrap_or(None);
        let font_size = self.image_font_size.lock().map(|g| *g).unwrap_or(None);
        let caps = match (hint, font_size) {
            (Some(picker_protocol), Some(font_size)) => TransportCaps::Local {
                picker_protocol,
                font_size,
            },
            _ => TransportCaps::RawTerminal { hint },
        };

        terminal
            .draw(|frame| {
                for command in &commands {
                    render_widget_data(frame.buffer_mut(), &command.widget, command.area, caps);
                }
            })
            .map_err(|e| format!("session draw: {e}"))?;

        Ok(())
    }

    /// Drains any bytes the backend has written into the shared buffer since
    /// the last call. Returns an empty `Vec` if nothing is pending. Safe to
    /// call after `close` — the writer handle survives until the resource is
    /// dropped, so anything the backend buffered before close is still
    /// recoverable.
    pub fn take_output(&self) -> Vec<u8> {
        self.writer.drain()
    }

    /// Resizes the session's viewport to `width x height`. The underlying
    /// ratatui terminal is reconfigured (which clears its back buffers
    /// and emits clear-screen ANSI into the writer for the transport to
    /// ship), and the cached size is updated so the next caller of
    /// [`SessionResource::current_size`] sees the new dimensions.
    ///
    /// Returns an error if the session has been closed. We deliberately
    /// don't fall back to "just update the cached size" — a transport
    /// that calls resize on a dead session has a bug to know about, not
    /// a silent state-only update to paper over.
    pub fn resize(&self, width: u16, height: u16) -> Result<(), String> {
        let mut terminal_guard = self
            .terminal
            .lock()
            .map_err(|_| "session terminal lock poisoned".to_string())?;
        let terminal = terminal_guard
            .as_mut()
            .ok_or_else(|| "session is closed".to_string())?;

        // Update the backend's cached size first so the clear-on-resize path
        // (which reads `Backend::size`) sees the new dimensions and takes the
        // full-viewport fast path instead of probing the tty.
        terminal.backend_mut().set_size(Size::new(width, height));
        terminal
            .resize(Rect::new(0, 0, width, height))
            .map_err(|e| format!("session resize: {e}"))?;

        let mut size_guard = self
            .size
            .lock()
            .map_err(|_| "session size lock poisoned".to_string())?;
        *size_guard = (width, height);
        Ok(())
    }

    /// Returns the session's current `(width, height)`. Useful for tests
    /// and for transports that want to snapshot the size after resize.
    pub fn current_size(&self) -> Result<(u16, u16), String> {
        let guard = self
            .size
            .lock()
            .map_err(|_| "session size lock poisoned".to_string())?;
        Ok(*guard)
    }

    /// Feeds raw transport bytes through the session's input parser and
    /// returns any newly-completed events. Bytes that only partially form
    /// a sequence stay buffered inside the parser for the next call —
    /// the SSH transport may chunk a single arrow-key press across two
    /// channel-data frames and we must not flush half-events.
    ///
    /// Safe to call after `close`: the parser is owned by the session,
    /// not the (now-dropped) terminal. This is intentional so a transport
    /// can drain trailing input bytes after deciding to shut the session
    /// down.
    pub fn feed_input(&self, bytes: &[u8]) -> Result<Vec<NifEvent>, String> {
        let mut parser = self
            .input
            .lock()
            .map_err(|_| "session input lock poisoned".to_string())?;
        let mut events = Vec::new();
        parser.feed(bytes, &mut events);
        Ok(events)
    }

    /// Replaces the input parser with a fresh one, discarding any
    /// partial escape sequence. Used after an Esc timeout to unstick
    /// the VTE state machine from the Escape state.
    pub fn reset_parser(&self) -> Result<(), String> {
        let mut parser = self
            .input
            .lock()
            .map_err(|_| "session input lock poisoned".to_string())?;
        *parser = InputParser::new();
        Ok(())
    }

    /// Sets the image-protocol hint used by `:auto` resolution during render.
    /// Pass `None` to clear (back to halfblocks fallback).
    pub fn set_image_protocol(
        &self,
        kind: Option<crate::image::ProtocolKind>,
    ) -> Result<(), String> {
        let mut guard = self
            .image_protocol
            .lock()
            .map_err(|_| "session image_protocol lock poisoned".to_string())?;
        *guard = kind;
        Ok(())
    }

    /// Sets the cell pixel dimensions used when the protocol hint is
    /// honored. Pass `None` to clear and let the render path fall back
    /// to ratatui-image's built-in default.
    pub fn set_image_font_size(&self, size: Option<(u16, u16)>) -> Result<(), String> {
        let mut guard = self
            .image_font_size
            .lock()
            .map_err(|_| "session image_font_size lock poisoned".to_string())?;
        *guard = size;
        Ok(())
    }
}

/// Converts a domain error string into a `rustler::Error::Term` carrying a
/// BEAM-friendly binary. Keeps the NIF signatures tidy.
fn nif_error(message: String) -> Error {
    Error::Term(Box::new(message))
}

#[rustler::nif]
fn session_new(width: u16, height: u16) -> Result<ResourceArc<SessionResource>, Error> {
    let session = SessionResource::new(width, height).map_err(nif_error)?;
    Ok(ResourceArc::new(session))
}

#[rustler::nif]
fn session_close(resource: ResourceArc<SessionResource>) -> Result<Atom, Error> {
    resource.close().map_err(nif_error)?;
    Ok(atoms::ok())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn session_draw(resource: ResourceArc<SessionResource>, commands: Term<'_>) -> Result<Atom, Error> {
    let render_commands = decode_render_commands(commands)?;
    resource.draw(render_commands).map_err(nif_error)?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn session_feed_input(
    resource: ResourceArc<SessionResource>,
    bytes: Binary<'_>,
) -> Result<Vec<NifEvent>, Error> {
    resource.feed_input(bytes.as_slice()).map_err(nif_error)
}

#[rustler::nif]
fn session_reset_parser(resource: ResourceArc<SessionResource>) -> Result<Atom, Error> {
    resource.reset_parser().map_err(nif_error)?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn session_set_image_protocol(
    resource: ResourceArc<SessionResource>,
    kind: crate::image::ProtocolKind,
) -> Result<Atom, Error> {
    // `:auto` clears the hint (back to halfblocks fallback). Anything
    // else is stored as an explicit hint so `:auto` per-image resolves
    // to the user-chosen terminal protocol.
    let hint = match kind {
        crate::image::ProtocolKind::Auto => None,
        explicit => Some(explicit),
    };
    resource.set_image_protocol(hint).map_err(nif_error)?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn session_set_image_font_size(
    resource: ResourceArc<SessionResource>,
    size: (u16, u16),
) -> Result<Atom, Error> {
    // (0, 0) clears the stored font size; any positive pair stores it.
    let stored = match size {
        (0, 0) => None,
        (w, h) => Some((w, h)),
    };
    resource.set_image_font_size(stored).map_err(nif_error)?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn session_resize(
    resource: ResourceArc<SessionResource>,
    width: u16,
    height: u16,
) -> Result<Atom, Error> {
    resource.resize(width, height).map_err(nif_error)?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn session_size(resource: ResourceArc<SessionResource>) -> Result<(u16, u16), Error> {
    resource.current_size().map_err(nif_error)
}

#[rustler::nif]
fn session_take_output<'a>(env: Env<'a>, resource: ResourceArc<SessionResource>) -> Binary<'a> {
    let bytes = resource.take_output();
    // OwnedBinary::new returns None only on allocator failure, in which case
    // there's nothing useful we can hand the BEAM — fall back to an empty
    // binary so the caller doesn't have to special-case the error.
    let mut owned = OwnedBinary::new(bytes.len()).unwrap_or_else(|| {
        OwnedBinary::new(0).expect("zero-length OwnedBinary allocation cannot fail")
    });
    if !bytes.is_empty() {
        owned.as_mut_slice().copy_from_slice(&bytes);
    }
    Binary::from_owned(owned, env)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shared_writer_accumulates_writes() {
        let mut writer = SharedWriter::new();
        writer.write_all(b"hello").unwrap();
        writer.write_all(b" world").unwrap();

        let drained = writer.drain();
        assert_eq!(drained, b"hello world");
    }

    #[test]
    fn shared_writer_drain_is_idempotent_when_empty() {
        let writer = SharedWriter::new();
        assert!(writer.drain().is_empty());
        assert!(writer.drain().is_empty());
    }

    #[test]
    fn shared_writer_clones_share_backing_buffer() {
        let mut a = SharedWriter::new();
        let b = a.clone();

        a.write_all(b"from a").unwrap();
        let drained = b.drain();

        assert_eq!(drained, b"from a");
        // After drain, both views should see an empty buffer.
        assert!(a.drain().is_empty());
    }

    #[test]
    fn session_resource_new_succeeds_at_reasonable_sizes() {
        let session = SessionResource::new(80, 24).unwrap();
        let size = *session.size.lock().unwrap();
        assert_eq!(size, (80, 24));
    }

    #[test]
    fn session_resource_writer_starts_empty() {
        // Fixed-viewport construction must not push any bytes into the buffer.
        // This matters because the transport may not be ready to drain yet —
        // an SSH channel sees its first bytes only after the first draw.
        let session = SessionResource::new(10, 5).unwrap();
        assert!(session.writer.drain().is_empty());
    }

    #[test]
    fn session_resource_writer_is_shared_with_backend() {
        // Writes through a handle cloned off `session.writer` must be visible
        // via the session's own handle. This is the guarantee that lets
        // `session_take_output` (future NIF) drain bytes the backend wrote.
        let session = SessionResource::new(10, 5).unwrap();
        let mut writer_handle = session.writer.clone();
        writer_handle.write_all(b"hi").unwrap();
        assert_eq!(session.writer.drain(), b"hi");
    }

    #[test]
    fn session_resource_close_is_idempotent() {
        let session = SessionResource::new(10, 5).unwrap();
        assert!(session.terminal.lock().unwrap().is_some());

        session.close().unwrap();
        assert!(session.terminal.lock().unwrap().is_none());

        // Second close is a no-op and must not error.
        session.close().unwrap();
        assert!(session.terminal.lock().unwrap().is_none());
    }

    #[test]
    fn session_resource_draw_writes_ansi_into_writer() {
        let session = SessionResource::new(20, 5).unwrap();
        // Empty command list still triggers a frame flush, which queues the
        // initial buffer-clear and cursor moves. The shared writer must
        // contain those bytes after draw returns.
        session.draw(Vec::new()).unwrap();
        let bytes = session.take_output();
        assert!(
            !bytes.is_empty(),
            "expected draw to emit ANSI bytes into the writer"
        );
    }

    #[test]
    fn session_resource_take_output_is_idempotent() {
        let session = SessionResource::new(20, 5).unwrap();
        session.draw(Vec::new()).unwrap();
        let _ = session.take_output();
        // A second drain with no intervening writes returns nothing.
        assert!(session.take_output().is_empty());
    }

    #[test]
    fn session_resource_draw_after_close_errors() {
        let session = SessionResource::new(20, 5).unwrap();
        session.close().unwrap();
        let result = session.draw(Vec::new());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("closed"));
    }

    #[test]
    fn session_resource_resize_updates_cached_size() {
        let session = SessionResource::new(80, 24).unwrap();
        assert_eq!(session.current_size().unwrap(), (80, 24));

        session.resize(120, 40).unwrap();
        assert_eq!(session.current_size().unwrap(), (120, 40));
    }

    #[test]
    fn session_resource_resize_renders_at_new_dimensions() {
        // Resize then draw an empty frame and confirm the writer holds
        // bytes — this proves the underlying ratatui terminal accepted
        // the new viewport rather than choking on the change.
        let session = SessionResource::new(20, 5).unwrap();
        session.resize(40, 10).unwrap();
        session.draw(Vec::new()).unwrap();
        assert!(!session.take_output().is_empty());
    }

    #[test]
    fn session_resource_resize_after_close_errors() {
        let session = SessionResource::new(20, 5).unwrap();
        session.close().unwrap();
        let result = session.resize(40, 10);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("closed"));
    }

    #[test]
    fn fixed_size_backend_answers_size_from_cache_not_the_tty() {
        // Regression: the fixed-viewport resize path reads `Backend::size`
        // while clearing. If that delegated to `crossterm::terminal::size()`
        // it would ioctl the host tty and fail off a real terminal (e.g. CI,
        // where stdout is a pipe) with EAGAIN. The backend must answer from
        // its cached dimensions, and `set_size` must update them.
        let mut backend =
            FixedSizeBackend::new(CrosstermBackend::new(SharedWriter::new()), Size::new(20, 5));
        assert_eq!(backend.size().unwrap(), Size::new(20, 5));
        assert_eq!(
            backend.window_size().unwrap(),
            WindowSize {
                columns_rows: Size::new(20, 5),
                pixels: Size::new(0, 0),
            }
        );

        backend.set_size(Size::new(40, 10));
        assert_eq!(backend.size().unwrap(), Size::new(40, 10));
        assert_eq!(
            backend.window_size().unwrap().columns_rows,
            Size::new(40, 10)
        );
    }

    #[test]
    fn session_resource_feed_input_round_trips_a_keystroke() {
        let session = SessionResource::new(20, 5).unwrap();
        let events = session.feed_input(b"a").unwrap();
        assert_eq!(events.len(), 1);
        match &events[0] {
            NifEvent::Key(code, mods, kind) => {
                assert_eq!(code, "a");
                assert!(mods.is_empty());
                assert_eq!(kind, "press");
            }
            _ => panic!("expected Key event"),
        }
    }

    #[test]
    fn session_resource_feed_input_buffers_partial_csi_across_calls() {
        // Sanity check that the SessionResource really shares the same
        // parser across feed_input calls — a partial CSI must not flush
        // until completion. This is the same guarantee
        // session_input::tests::buffers_partial_csi_across_feeds verifies
        // at the parser level, but reproducing it here proves the
        // session is wiring through to a single InputParser instance
        // rather than constructing a fresh one per call.
        let session = SessionResource::new(20, 5).unwrap();
        assert!(session.feed_input(b"\x1b").unwrap().is_empty());
        assert!(session.feed_input(b"[").unwrap().is_empty());
        let events = session.feed_input(b"A").unwrap();
        assert_eq!(events.len(), 1);
        match &events[0] {
            NifEvent::Key(code, _, _) => assert_eq!(code, "up"),
            _ => panic!("expected Key event"),
        }
    }

    #[test]
    fn session_resource_feed_input_works_after_close() {
        let session = SessionResource::new(20, 5).unwrap();
        session.close().unwrap();
        // Closing dropped the terminal, but the input parser is still
        // alive — a transport may want to drain trailing input after
        // tearing down rendering.
        let events = session.feed_input(b"a").unwrap();
        assert_eq!(events.len(), 1);
    }

    #[test]
    fn session_resource_close_preserves_writer_for_final_drain() {
        let session = SessionResource::new(10, 5).unwrap();
        // Simulate the transport buffering bytes that have been written but
        // not yet drained. Closing the session (which drops the backend) must
        // not wipe those bytes — the transport still needs to ship them.
        let mut handle = session.writer.clone();
        handle.write_all(b"unshipped").unwrap();

        session.close().unwrap();

        let final_bytes = session.writer.drain();
        assert_eq!(final_bytes, b"unshipped");
    }
}
