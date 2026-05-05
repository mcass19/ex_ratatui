//! Per-connection terminal session that surfaces ratatui's rendered **cell
//! buffer** instead of ANSI bytes.
//!
//! [`crate::session::SessionResource`] is the right primitive when the
//! consumer is a real terminal (or anything that speaks ANSI). It uses a
//! [`ratatui::backend::CrosstermBackend`] over a shared in-memory writer and
//! drains encoded escape sequences via `session_take_output`.
//!
//! `CellSessionResource` is the right primitive when the consumer is *not* a
//! terminal — a Phoenix LiveView painting `<span>`s, an embedded device
//! rasterising glyphs to a framebuffer, an SVG/PNG exporter, a screenshot
//! tool. Those consumers don't want ANSI; they want the post-render
//! `Buffer`: per-cell `(symbol, fg, bg, modifiers, skip)` tuples that they
//! turn into pixels (or DOM, or vectors) themselves.
//!
//! The implementation is a deliberate near-copy of `SessionResource` with
//! exactly two changes:
//!
//!   1. The backend is [`ratatui::backend::TestBackend`] (which holds a
//!      `Buffer` in memory and never emits ANSI) instead of `CrosstermBackend`.
//!   2. There is no `SharedWriter` and no `take_output` — the buffer is the
//!      output, surfaced by `take_cells` (added in a follow-up chunk).
//!
//! Everything else — input parsing, lifecycle, resize, draw command decoding —
//! is the same `InputParser` / `RenderCommand` pipeline `SessionResource`
//! uses. That symmetry is intentional: an `ExRatatui.App` never sees the
//! difference, and the eventual transports built on top of either session
//! type share their event-handling glue.
//!
//! `CellSessionResource` touches no OS terminal state — no raw mode, no alt
//! screen, no signal handlers. It is safe to construct and drive concurrently
//! from `async: true` tests, `GenServer`s, or `LiveView` mounts.

use std::sync::Mutex;

use ratatui::backend::TestBackend;
use ratatui::layout::Rect;
use ratatui::Terminal;

use rustler::{Atom, Binary, Error, ResourceArc, Term};

use crate::events::NifEvent;
use crate::rendering::{decode_render_commands, render_widget_data, RenderCommand};
use crate::session_input::InputParser;

mod atoms {
    rustler::atoms! {
        ok,
    }
}

/// Per-cell-session resource. Holds its own ratatui terminal (with a
/// [`TestBackend`] as the rendering target so the post-draw cell buffer is
/// directly readable), input parser, and current size.
///
/// All fields are guarded by coarse mutexes for the same reason
/// `SessionResource` does it: NIF entry points are short-running and one
/// BEAM process owns each session, so contention is effectively zero and
/// the simpler locking story is worth more than the negligible perf gain
/// of a fancier scheme.
///
/// The `terminal` slot is an `Option` so `cell_session_close` can drop the
/// underlying ratatui `Terminal` deterministically without waiting for the
/// BEAM garbage collector. After close, draw/resize surface a clear error
/// while `feed_input` continues to work — same lifecycle contract as
/// `SessionResource`.
pub struct CellSessionResource {
    pub(crate) terminal: Mutex<Option<Terminal<TestBackend>>>,
    pub(crate) input: Mutex<InputParser>,
    pub(crate) size: Mutex<(u16, u16)>,
}

#[rustler::resource_impl]
impl rustler::Resource for CellSessionResource {}

impl CellSessionResource {
    /// Creates a new cell session at the given dimensions. Both must be at
    /// least `1`. Returns the bare struct; NIF entry points wrap it in a
    /// `ResourceArc`. The split lets unit tests exercise construction
    /// without going through Rustler's resource registry, which is only
    /// initialised at NIF load time.
    ///
    /// `TestBackend` does not require a viewport configuration the way
    /// `SessionResource` does: its dimensions are intrinsic to the backend
    /// itself, and ratatui's `Terminal::new` happily accepts it. There is
    /// no host-tty query path to defend against, so we don't need
    /// [`ratatui::Viewport::Fixed`] gymnastics here.
    pub fn new(width: u16, height: u16) -> Result<Self, String> {
        let backend = TestBackend::new(width, height);
        let terminal =
            Terminal::new(backend).map_err(|e| format!("cell session terminal init: {e}"))?;

        Ok(Self {
            terminal: Mutex::new(Some(terminal)),
            input: Mutex::new(InputParser::new()),
            size: Mutex::new((width, height)),
        })
    }

    /// Drops the inner ratatui `Terminal`. Idempotent — calling `close`
    /// twice is a no-op. After close, draw/resize return errors but
    /// `feed_input` keeps working so a transport can drain trailing input.
    pub fn close(&self) -> Result<(), String> {
        let mut guard = self
            .terminal
            .lock()
            .map_err(|_| "cell session terminal lock poisoned".to_string())?;
        *guard = None;
        Ok(())
    }

    /// Renders a list of `(widget, area)` commands into the session's
    /// terminal. After this call returns, the rendered frame lives in
    /// `terminal.backend().buffer()` and is exposed to Elixir by the
    /// (forthcoming) `take_cells` / `take_cells_diff` paths. Returns an
    /// error if the session has been closed.
    pub fn draw(&self, commands: Vec<RenderCommand>) -> Result<(), String> {
        let mut guard = self
            .terminal
            .lock()
            .map_err(|_| "cell session terminal lock poisoned".to_string())?;
        let terminal = guard
            .as_mut()
            .ok_or_else(|| "cell session is closed".to_string())?;

        terminal
            .draw(|frame| {
                for command in &commands {
                    render_widget_data(frame.buffer_mut(), &command.widget, command.area);
                }
            })
            .map_err(|e| format!("cell session draw: {e}"))?;

        Ok(())
    }

    /// Resizes the session's terminal to `width x height`. The underlying
    /// `TestBackend` and ratatui terminal are reconfigured (which clears
    /// the back buffer), and the cached size is updated.
    ///
    /// `Terminal::resize` does *not* propagate to `TestBackend`'s internal
    /// dimensions on its own — Terminal only resizes its own front/back
    /// buffers and trusts the backend to report the same size on the next
    /// `autoresize`. `SessionResource` doesn't hit this because its
    /// `CrosstermBackend` has no buffer of its own. We do, so we have to
    /// resize the backend explicitly before `Terminal::resize` runs.
    ///
    /// Returns an error if the session has been closed — same rationale as
    /// `SessionResource::resize`: a transport calling resize on a dead
    /// session has a bug worth surfacing, not silently papering over.
    pub fn resize(&self, width: u16, height: u16) -> Result<(), String> {
        let mut terminal_guard = self
            .terminal
            .lock()
            .map_err(|_| "cell session terminal lock poisoned".to_string())?;
        let terminal = terminal_guard
            .as_mut()
            .ok_or_else(|| "cell session is closed".to_string())?;

        // Resize the backend's intrinsic buffer first so Terminal's
        // `autoresize` sees the new dimensions on the next draw, then
        // resize Terminal's own front/back buffers to match.
        terminal.backend_mut().resize(width, height);
        terminal
            .resize(Rect::new(0, 0, width, height))
            .map_err(|e| format!("cell session resize: {e}"))?;

        let mut size_guard = self
            .size
            .lock()
            .map_err(|_| "cell session size lock poisoned".to_string())?;
        *size_guard = (width, height);
        Ok(())
    }

    /// Returns the session's current `(width, height)`.
    pub fn current_size(&self) -> Result<(u16, u16), String> {
        let guard = self
            .size
            .lock()
            .map_err(|_| "cell session size lock poisoned".to_string())?;
        Ok(*guard)
    }

    /// Feeds raw transport bytes through the session's input parser and
    /// returns any newly-completed events. Identical semantics to
    /// `SessionResource::feed_input`: partial sequences buffer across calls,
    /// works after `close`, never blocks.
    pub fn feed_input(&self, bytes: &[u8]) -> Result<Vec<NifEvent>, String> {
        let mut parser = self
            .input
            .lock()
            .map_err(|_| "cell session input lock poisoned".to_string())?;
        let mut events = Vec::new();
        parser.feed(bytes, &mut events);
        Ok(events)
    }

    /// Replaces the input parser with a fresh one, discarding any partial
    /// escape sequence. Used after an Esc timeout to unstick the VTE state
    /// machine from the Escape state.
    pub fn reset_parser(&self) -> Result<(), String> {
        let mut parser = self
            .input
            .lock()
            .map_err(|_| "cell session input lock poisoned".to_string())?;
        *parser = InputParser::new();
        Ok(())
    }
}

/// Converts a domain error string into a `rustler::Error::Term` carrying a
/// BEAM-friendly binary, so NIF signatures stay tidy.
fn nif_error(message: String) -> Error {
    Error::Term(Box::new(message))
}

#[rustler::nif]
fn cell_session_new(width: u16, height: u16) -> Result<ResourceArc<CellSessionResource>, Error> {
    let session = CellSessionResource::new(width, height).map_err(nif_error)?;
    Ok(ResourceArc::new(session))
}

#[rustler::nif]
fn cell_session_close(resource: ResourceArc<CellSessionResource>) -> Result<Atom, Error> {
    resource.close().map_err(nif_error)?;
    Ok(atoms::ok())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn cell_session_draw(
    resource: ResourceArc<CellSessionResource>,
    commands: Term<'_>,
) -> Result<Atom, Error> {
    let render_commands = decode_render_commands(commands)?;
    resource.draw(render_commands).map_err(nif_error)?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn cell_session_feed_input(
    resource: ResourceArc<CellSessionResource>,
    bytes: Binary<'_>,
) -> Result<Vec<NifEvent>, Error> {
    resource.feed_input(bytes.as_slice()).map_err(nif_error)
}

#[rustler::nif]
fn cell_session_reset_parser(resource: ResourceArc<CellSessionResource>) -> Result<Atom, Error> {
    resource.reset_parser().map_err(nif_error)?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn cell_session_resize(
    resource: ResourceArc<CellSessionResource>,
    width: u16,
    height: u16,
) -> Result<Atom, Error> {
    resource.resize(width, height).map_err(nif_error)?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn cell_session_size(resource: ResourceArc<CellSessionResource>) -> Result<(u16, u16), Error> {
    resource.current_size().map_err(nif_error)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cell_session_resource_new_succeeds_at_reasonable_sizes() {
        let session = CellSessionResource::new(80, 24).unwrap();
        let size = *session.size.lock().unwrap();
        assert_eq!(size, (80, 24));
    }

    #[test]
    fn cell_session_resource_new_succeeds_at_minimum_size() {
        // 1x1 is the smallest valid size; both Session and CellSession
        // must accept it so transports that report shrunken-to-the-bone
        // remote terminals don't choke on session creation.
        let session = CellSessionResource::new(1, 1).unwrap();
        assert_eq!(session.current_size().unwrap(), (1, 1));
    }

    #[test]
    fn cell_session_resource_close_is_idempotent() {
        let session = CellSessionResource::new(10, 5).unwrap();
        assert!(session.terminal.lock().unwrap().is_some());

        session.close().unwrap();
        assert!(session.terminal.lock().unwrap().is_none());

        // Second close is a no-op — must not surface an error.
        session.close().unwrap();
        assert!(session.terminal.lock().unwrap().is_none());
    }

    #[test]
    fn cell_session_resource_draw_with_empty_commands_succeeds() {
        // ratatui's frame setup runs even with zero widgets, populating the
        // backend's buffer with a default-styled grid. We don't yet expose
        // that buffer (take_cells lands in the next chunk), so for now we
        // just assert draw doesn't error and the buffer is reachable.
        let session = CellSessionResource::new(20, 5).unwrap();
        assert!(session.draw(Vec::new()).is_ok());

        let guard = session.terminal.lock().unwrap();
        let terminal = guard.as_ref().unwrap();
        let buffer = terminal.backend().buffer();
        assert_eq!(buffer.area.width, 20);
        assert_eq!(buffer.area.height, 5);
    }

    #[test]
    fn cell_session_resource_draw_after_close_errors() {
        let session = CellSessionResource::new(20, 5).unwrap();
        session.close().unwrap();
        let result = session.draw(Vec::new());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("closed"));
    }

    #[test]
    fn cell_session_resource_resize_updates_cached_size() {
        let session = CellSessionResource::new(80, 24).unwrap();
        assert_eq!(session.current_size().unwrap(), (80, 24));

        session.resize(120, 40).unwrap();
        assert_eq!(session.current_size().unwrap(), (120, 40));
    }

    #[test]
    fn cell_session_resource_resize_propagates_to_backend_buffer() {
        // Resize then draw — confirm the underlying TestBackend's buffer
        // dimensions reflect the new size, not the original.
        let session = CellSessionResource::new(20, 5).unwrap();
        session.resize(40, 10).unwrap();
        session.draw(Vec::new()).unwrap();

        let guard = session.terminal.lock().unwrap();
        let buffer = guard.as_ref().unwrap().backend().buffer();
        assert_eq!(buffer.area.width, 40);
        assert_eq!(buffer.area.height, 10);
    }

    #[test]
    fn cell_session_resource_resize_after_close_errors() {
        let session = CellSessionResource::new(20, 5).unwrap();
        session.close().unwrap();
        let result = session.resize(40, 10);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("closed"));
    }

    #[test]
    fn cell_session_resource_feed_input_round_trips_a_keystroke() {
        let session = CellSessionResource::new(20, 5).unwrap();
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
    fn cell_session_resource_feed_input_buffers_partial_csi_across_calls() {
        // Same guarantee SessionResource makes — verifies CellSession
        // wires through to a single InputParser instance, not a fresh one
        // per call.
        let session = CellSessionResource::new(20, 5).unwrap();
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
    fn cell_session_resource_feed_input_works_after_close() {
        let session = CellSessionResource::new(20, 5).unwrap();
        session.close().unwrap();
        let events = session.feed_input(b"a").unwrap();
        assert_eq!(events.len(), 1);
    }

    #[test]
    fn cell_session_resource_reset_parser_drops_buffered_escape() {
        let session = CellSessionResource::new(20, 5).unwrap();
        // Bare ESC stays in the parser as the start of a sequence...
        assert!(session.feed_input(b"\x1b").unwrap().is_empty());
        // ...until reset_parser drops it.
        session.reset_parser().unwrap();
        // Next byte is parsed fresh, not as a continuation.
        let events = session.feed_input(b"a").unwrap();
        assert_eq!(events.len(), 1);
        match &events[0] {
            NifEvent::Key(code, _, _) => assert_eq!(code, "a"),
            _ => panic!("expected Key event"),
        }
    }

    #[test]
    fn cell_session_resource_concurrent_sessions_are_independent() {
        // Verifies that two CellSessionResource instances hold genuinely
        // separate state — input partials, sizes, and terminal buffers
        // must not bleed across.
        let a = CellSessionResource::new(20, 5).unwrap();
        let b = CellSessionResource::new(40, 10).unwrap();

        // Drive a partial CSI on `a` and a complete keystroke on `b`.
        assert!(a.feed_input(b"\x1b[").unwrap().is_empty());
        let b_events = b.feed_input(b"x").unwrap();
        assert_eq!(b_events.len(), 1);

        // Resize `a`; `b` must keep its original size.
        a.resize(60, 15).unwrap();
        assert_eq!(a.current_size().unwrap(), (60, 15));
        assert_eq!(b.current_size().unwrap(), (40, 10));

        // Finish `a`'s partial — it's still buffered after the resize and
        // unrelated b.feed_input calls.
        let a_events = a.feed_input(b"A").unwrap();
        assert_eq!(a_events.len(), 1);
        match &a_events[0] {
            NifEvent::Key(code, _, _) => assert_eq!(code, "up"),
            _ => panic!("expected Key event"),
        }
    }
}
