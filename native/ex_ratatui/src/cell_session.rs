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
use ratatui::buffer::{Buffer, Cell, CellDiffOption};
use ratatui::layout::Rect;
use ratatui::Terminal;

use rustler::{Atom, Binary, Encoder, Env, Error, ResourceArc, Term};

use crate::events::NifEvent;
use crate::image::TransportCaps;
use crate::rendering::{decode_render_commands, render_widget_data, RenderCommand};
use crate::session_input::InputParser;
use crate::style::{encode_color, encode_modifiers};

mod atoms {
    rustler::atoms! {
        ok,
        // Map keys for take_cells / take_cells_diff payloads.
        width,
        height,
        cells,
        ops,
    }
}

/// Per-cell-session resource. Holds its own ratatui terminal (with a
/// [`TestBackend`] as the rendering target so the post-draw cell buffer is
/// directly readable), input parser, current size, and a snapshot of the
/// last buffer surfaced via [`cell_session_take_cells_diff`].
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
///
/// `prev_buffer` is `None` until the first `take_cells_diff` call, then
/// holds a clone of whatever buffer was returned. The next diff call uses
/// it as the comparison baseline and overwrites it with the new current
/// buffer. `take_cells` does **not** touch this slot — pure snapshots
/// stay stateless so consumers can mix snapshots and diffs without
/// surprising the diff baseline.
pub struct CellSessionResource {
    pub(crate) terminal: Mutex<Option<Terminal<TestBackend>>>,
    pub(crate) input: Mutex<InputParser>,
    pub(crate) size: Mutex<(u16, u16)>,
    pub(crate) prev_buffer: Mutex<Option<Buffer>>,
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
            prev_buffer: Mutex::new(None),
        })
    }

    /// Drops the inner ratatui `Terminal` and any cached diff baseline.
    /// Idempotent — calling `close` twice is a no-op. After close,
    /// draw/resize/take_cells/take_cells_diff return errors but
    /// `feed_input` keeps working so a transport can drain trailing input.
    pub fn close(&self) -> Result<(), String> {
        let mut guard = self
            .terminal
            .lock()
            .map_err(|_| "cell session terminal lock poisoned".to_string())?;
        *guard = None;

        // The cached diff baseline is meaningless once the terminal is
        // gone — wipe it so the resource doesn't carry a now-orphaned
        // Buffer until the BEAM garbage collector catches up. Lock
        // failures here are non-fatal; the resource is being torn down
        // and the BEAM heap will reclaim it regardless.
        if let Ok(mut prev_guard) = self.prev_buffer.lock() {
            *prev_guard = None;
        }
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
                    // CellSession only emits cells — terminal escape sequences
                    // (Kitty / Sixel / iTerm2) cannot survive cell diffing, so
                    // images are forced down the halfblocks path regardless of
                    // the user's requested protocol.
                    render_widget_data(
                        frame.buffer_mut(),
                        &command.widget,
                        command.area,
                        TransportCaps::CellOnly,
                    );
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

    /// Locks the terminal and runs `f` with a borrowed reference to the
    /// post-render `Buffer`. The buffer is the same one ratatui filled in
    /// during the most recent `draw` (or the empty default if no draw has
    /// happened yet).
    ///
    /// Returns the closure's result, or an error if the session is closed
    /// or the terminal lock is poisoned. Used by the NIF entry points
    /// that surface cells to Elixir, and exposed `pub(crate)` so unit
    /// tests can poke the buffer directly without needing a NIF env.
    pub(crate) fn with_buffer<F, R>(&self, f: F) -> Result<R, String>
    where
        F: FnOnce(&Buffer) -> R,
    {
        let guard = self
            .terminal
            .lock()
            .map_err(|_| "cell session terminal lock poisoned".to_string())?;
        let terminal = guard
            .as_ref()
            .ok_or_else(|| "cell session is closed".to_string())?;
        Ok(f(terminal.backend().buffer()))
    }
}

/// Encodes one ratatui `Cell` at position `(x, y)` as a tagged tuple
/// `{x, y, symbol, fg, bg, modifiers, skip}` — the on-the-wire shape for
/// every per-cell payload returned to Elixir.
///
/// The Elixir wrapper transforms these tuples into `%CellSession.Cell{}`
/// structs; keeping the NIF return shape as a flat tuple per cell avoids
/// a hash-map allocation per cell on the hot path (a 200x60 grid is
/// 12_000 cells per full-buffer call).
fn encode_cell<'a>(env: Env<'a>, x: u16, y: u16, cell: &Cell) -> Term<'a> {
    let symbol = cell.symbol().to_string();
    let fg = encode_color(env, cell.fg);
    let bg = encode_color(env, cell.bg);
    let mods = encode_modifiers(env, cell.modifier);
    let skip = cell.diff_option == CellDiffOption::Skip;
    (x, y, symbol, fg, bg, mods, skip).encode(env)
}

/// Walks every cell in `buffer` in row-major order and returns a `Vec` of
/// already-encoded cell tuples. Used as the full-buffer payload for both
/// `take_cells` and the first/post-resize call to `take_cells_diff`.
fn collect_all_cells<'a>(env: Env<'a>, buffer: &Buffer) -> Vec<Term<'a>> {
    let width = buffer.area.width;
    let cell_count = (width as usize).saturating_mul(buffer.area.height as usize);
    let row_width = (width as usize).max(1);

    let mut cells: Vec<Term<'a>> = Vec::with_capacity(cell_count);
    for (i, cell) in buffer.content().iter().enumerate() {
        // Row-major flat array: index i corresponds to (i % w, i / w).
        let x = (i % row_width) as u16;
        let y = (i / row_width) as u16;
        cells.push(encode_cell(env, x, y, cell));
    }
    cells
}

/// Returns the row-major flat-array indices of every cell that differs
/// between `prev` and `curr`. Pure function — no `Env`, no encoding,
/// trivially testable from cargo.
///
/// Caller MUST guarantee `prev.area == curr.area`; with mismatched areas
/// the zip silently truncates to the shorter content slice and the
/// returned indices would be meaningless. The single callsite in
/// `cell_session_take_cells_diff` checks the area before reaching here.
///
/// Cells are compared with `Cell`'s derived `PartialEq` — that includes
/// symbol, fg, bg, underline color, modifier bits, and the `skip` flag.
/// Equality is structural: two cells with identical visual output never
/// appear in the diff.
fn diff_indices(prev: &Buffer, curr: &Buffer) -> Vec<usize> {
    curr.content()
        .iter()
        .zip(prev.content().iter())
        .enumerate()
        .filter_map(|(i, (c, p))| if c != p { Some(i) } else { None })
        .collect()
}

/// Encodes only the cells that differ between `prev` and `curr` using the
/// same per-cell tuple shape `collect_all_cells` produces.
fn collect_changed_cells<'a>(env: Env<'a>, prev: &Buffer, curr: &Buffer) -> Vec<Term<'a>> {
    let row_width = (curr.area.width as usize).max(1);
    let indices = diff_indices(prev, curr);

    // Heuristic capacity: we now know exactly how many ops we'll emit.
    let mut ops: Vec<Term<'a>> = Vec::with_capacity(indices.len());
    let content = curr.content();
    for i in indices {
        let cell = &content[i];
        let x = (i % row_width) as u16;
        let y = (i / row_width) as u16;
        ops.push(encode_cell(env, x, y, cell));
    }
    ops
}

/// Wraps a Vec of cell tuples into the `%{width, height, cells: [...]}`
/// map shape `take_cells` returns. Map keys are atoms; everything else
/// is whatever `collect_all_cells` produced. `map_put` on a freshly
/// constructed map cannot fail (the only failure mode is calling it on
/// a non-map term), so the unwraps are safe.
fn encode_full_payload<'a>(env: Env<'a>, buffer: &Buffer) -> Term<'a> {
    let width = buffer.area.width;
    let height = buffer.area.height;
    let cells = collect_all_cells(env, buffer);

    Term::map_new(env)
        .map_put(atoms::width().encode(env), width.encode(env))
        .expect("map_put on fresh map cannot fail")
        .map_put(atoms::height().encode(env), height.encode(env))
        .expect("map_put on fresh map cannot fail")
        .map_put(atoms::cells().encode(env), cells.encode(env))
        .expect("map_put on fresh map cannot fail")
}

/// Wraps a Vec of cell tuples into the `%{width, height, ops: [...]}` map
/// shape `take_cells_diff` returns. The shape mirrors `encode_full_payload`
/// except for the `:ops` field name, which signals "these are deltas, not
/// the full grid." Width/height are still the FULL terminal dimensions —
/// consumers need them to size their viewport regardless of how many ops
/// fit in the diff.
fn encode_diff_payload<'a>(env: Env<'a>, width: u16, height: u16, ops: Vec<Term<'a>>) -> Term<'a> {
    Term::map_new(env)
        .map_put(atoms::width().encode(env), width.encode(env))
        .expect("map_put on fresh map cannot fail")
        .map_put(atoms::height().encode(env), height.encode(env))
        .expect("map_put on fresh map cannot fail")
        .map_put(atoms::ops().encode(env), ops.encode(env))
        .expect("map_put on fresh map cannot fail")
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

#[rustler::nif]
fn cell_session_take_cells<'a>(
    env: Env<'a>,
    resource: ResourceArc<CellSessionResource>,
) -> Result<Term<'a>, Error> {
    resource
        .with_buffer(|buffer| encode_full_payload(env, buffer))
        .map_err(nif_error)
}

#[rustler::nif]
fn cell_session_take_cells_diff<'a>(
    env: Env<'a>,
    resource: ResourceArc<CellSessionResource>,
) -> Result<Term<'a>, Error> {
    // Lock both the terminal and the diff baseline up front. Order matters:
    // we take the terminal lock first (matching the rest of the module), then
    // the prev_buffer lock. Every NIF that touches both follows this order
    // so we cannot deadlock against a concurrent caller.
    let term_guard = resource
        .terminal
        .lock()
        .map_err(|_| nif_error("cell session terminal lock poisoned".to_string()))?;
    let terminal = term_guard
        .as_ref()
        .ok_or_else(|| nif_error("cell session is closed".to_string()))?;
    let curr_buffer = terminal.backend().buffer();

    let mut prev_guard = resource
        .prev_buffer
        .lock()
        .map_err(|_| nif_error("cell session prev_buffer lock poisoned".to_string()))?;

    // Decide what to emit. Three cases:
    //   1. No prior baseline → first call after construction (or after a
    //      buffer-area change). Emit the full grid as ops so the consumer
    //      can paint a complete picture.
    //   2. Prior baseline at the same area → real diff. Emit only the
    //      cells that changed.
    //   3. Prior baseline at a different area → resize between calls.
    //      Same handling as case 1: the prior baseline is no longer a
    //      valid comparison reference.
    let ops = match prev_guard.as_ref() {
        Some(prev) if prev.area == curr_buffer.area => {
            collect_changed_cells(env, prev, curr_buffer)
        }
        _ => collect_all_cells(env, curr_buffer),
    };

    let width = curr_buffer.area.width;
    let height = curr_buffer.area.height;

    // Snapshot the current buffer for the next diff call. Cloning a
    // ratatui Buffer is a deep clone of its `Vec<Cell>`; for an 80x24
    // grid that's a sub-millisecond memcpy. Done while we still hold
    // both locks so the snapshot reflects exactly the state we just
    // diffed against.
    *prev_guard = Some(curr_buffer.clone());

    Ok(encode_diff_payload(env, width, height, ops))
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
    fn with_buffer_returns_default_grid_for_fresh_session() {
        // Before any draw, ratatui's `Terminal` already owns an empty
        // backend buffer at the construction dimensions. with_buffer
        // surfaces it so the take_cells NIF never has to special-case
        // "session has not yet drawn anything".
        let session = CellSessionResource::new(5, 3).unwrap();
        session
            .with_buffer(|buf| {
                assert_eq!(buf.area.width, 5);
                assert_eq!(buf.area.height, 3);
                assert_eq!(buf.content().len(), 5 * 3);
            })
            .unwrap();
    }

    #[test]
    fn with_buffer_after_close_errors() {
        let session = CellSessionResource::new(10, 5).unwrap();
        session.close().unwrap();
        let result = session.with_buffer(|_| ());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("closed"));
    }

    #[test]
    fn with_buffer_after_resize_reports_new_dimensions() {
        let session = CellSessionResource::new(20, 5).unwrap();
        session.resize(40, 10).unwrap();
        // A draw is needed for autoresize to settle the front buffer at
        // the new dimensions; until then `with_buffer` would still see
        // the old size from the unmodified backend buffer.
        session.draw(Vec::new()).unwrap();
        session
            .with_buffer(|buf| {
                assert_eq!(buf.area.width, 40);
                assert_eq!(buf.area.height, 10);
                assert_eq!(buf.content().len(), 40 * 10);
            })
            .unwrap();
    }

    #[test]
    fn with_buffer_observes_content_painted_via_terminal_draw() {
        // Paint "hi" directly using ratatui's set_string and verify that
        // with_buffer sees the resulting cells. We bypass the
        // RenderCommand pipeline here on purpose: the test covers the
        // cell-extraction path, not widget-decoding (which is tested
        // exhaustively elsewhere).
        let session = CellSessionResource::new(10, 1).unwrap();
        {
            let mut guard = session.terminal.lock().unwrap();
            let terminal = guard.as_mut().unwrap();
            terminal
                .draw(|frame| {
                    let buf = frame.buffer_mut();
                    buf.set_string(0, 0, "hi", ratatui::style::Style::default());
                })
                .unwrap();
        }

        session
            .with_buffer(|buf| {
                assert_eq!(buf.cell((0, 0)).unwrap().symbol(), "h");
                assert_eq!(buf.cell((1, 0)).unwrap().symbol(), "i");
                // Cells past the painted range remain at the default
                // single-space symbol — verify a couple to lock in the
                // "rest of the buffer is untouched" guarantee.
                assert_eq!(buf.cell((2, 0)).unwrap().symbol(), " ");
                assert_eq!(buf.cell((9, 0)).unwrap().symbol(), " ");
            })
            .unwrap();
    }

    #[test]
    fn with_buffer_observes_styled_content_painted_via_terminal_draw() {
        // Paint a single styled cell and verify both the symbol and the
        // style fields round-trip through the buffer. This is the test
        // that catches a regression where the buffer is read from the
        // wrong source (front vs back, or before autoresize lands).
        let session = CellSessionResource::new(5, 1).unwrap();
        {
            let mut guard = session.terminal.lock().unwrap();
            let terminal = guard.as_mut().unwrap();
            terminal
                .draw(|frame| {
                    let buf = frame.buffer_mut();
                    buf.set_string(
                        0,
                        0,
                        "X",
                        ratatui::style::Style::default()
                            .fg(ratatui::style::Color::Red)
                            .bg(ratatui::style::Color::Blue)
                            .add_modifier(ratatui::style::Modifier::BOLD),
                    );
                })
                .unwrap();
        }

        session
            .with_buffer(|buf| {
                let cell = buf.cell((0, 0)).unwrap();
                assert_eq!(cell.symbol(), "X");
                assert_eq!(cell.fg, ratatui::style::Color::Red);
                assert_eq!(cell.bg, ratatui::style::Color::Blue);
                assert!(cell.modifier.contains(ratatui::style::Modifier::BOLD));
            })
            .unwrap();
    }

    #[test]
    fn with_buffer_observes_wide_grapheme_in_leading_cell_only() {
        // A two-cell-wide grapheme (CJK ideograph) lands entirely in its
        // leading cell — `Cell::symbol()` returns the full multi-byte
        // grapheme cluster ("中"), not a half. The continuation cell
        // stays at the buffer's default symbol (" ") because ratatui's
        // `set_string` doesn't explicitly overwrite it.
        //
        // Consumers reconstructing a faithful display (HTML grid, font
        // rasteriser, screenshot tool) MUST detect wide-char layout
        // themselves by inspecting the leading cell's symbol width
        // (`unicode-width` crate or equivalent) and treating the next
        // `width - 1` cells as covered. The cell extraction path
        // surfaces what's in the buffer verbatim and does not synthesise
        // a continuation marker — that would mask information consumers
        // may want (the trailing cell still holds its prior style).
        let session = CellSessionResource::new(4, 1).unwrap();
        {
            let mut guard = session.terminal.lock().unwrap();
            let terminal = guard.as_mut().unwrap();
            terminal
                .draw(|frame| {
                    let buf = frame.buffer_mut();
                    buf.set_string(0, 0, "中a", ratatui::style::Style::default());
                })
                .unwrap();
        }

        session
            .with_buffer(|buf| {
                // Cell (0, 0) carries the full ideograph as a single
                // grapheme — multi-byte symbol, single cell index.
                let leading = buf.cell((0, 0)).unwrap();
                assert_eq!(leading.symbol(), "中");
                assert!(
                    leading.symbol().chars().count() >= 1,
                    "leading cell must hold the wide grapheme verbatim"
                );

                // Cell (1, 0) is the continuation slot — ratatui leaves
                // it at the default space, NOT an empty string. This is
                // the contract documented above.
                assert_eq!(buf.cell((1, 0)).unwrap().symbol(), " ");

                // Cell (2, 0) holds the trailing ASCII char (set_string
                // advances by the full grapheme width, so 'a' lands at
                // col 2 not col 1).
                assert_eq!(buf.cell((2, 0)).unwrap().symbol(), "a");
            })
            .unwrap();
    }

    #[test]
    fn fresh_session_has_no_diff_baseline() {
        // The diff baseline is `None` until the first `take_cells_diff`
        // call. Construction must NOT pre-snapshot a buffer — that would
        // flip the first diff call from "send full" to "send empty",
        // breaking new clients that need the initial paint.
        let session = CellSessionResource::new(10, 5).unwrap();
        let prev = session.prev_buffer.lock().unwrap();
        assert!(prev.is_none());
    }

    #[test]
    fn close_clears_diff_baseline() {
        // Once the terminal is dropped, the cached buffer references a
        // resource that no longer exists. Holding it would also waste
        // memory until BEAM GC reaps the resource. `close` wipes it.
        let session = CellSessionResource::new(10, 5).unwrap();

        // Force a baseline by hand (we can't call the Env-bound NIF
        // from cargo).
        {
            let mut prev = session.prev_buffer.lock().unwrap();
            *prev = Some(ratatui::buffer::Buffer::empty(Rect::new(0, 0, 10, 5)));
            assert!(prev.is_some());
        }

        session.close().unwrap();

        let prev = session.prev_buffer.lock().unwrap();
        assert!(prev.is_none(), "close must clear prev_buffer");
    }

    #[test]
    fn diff_indices_returns_empty_when_buffers_are_identical() {
        let area = Rect::new(0, 0, 4, 2);
        let prev = Buffer::empty(area);
        let curr = Buffer::empty(area);
        assert!(diff_indices(&prev, &curr).is_empty());
    }

    #[test]
    fn diff_indices_returns_only_changed_indices() {
        // Two empty 4x2 buffers, then mutate a single cell on `curr`.
        // The diff must report exactly that index — one op, not zero,
        // not all eight cells.
        let area = Rect::new(0, 0, 4, 2);
        let prev = Buffer::empty(area);
        let mut curr = Buffer::empty(area);

        // Mutate (col=2, row=1) → flat index 1*4 + 2 = 6.
        curr.cell_mut((2, 1))
            .unwrap()
            .set_symbol("X")
            .set_style(ratatui::style::Style::default().fg(ratatui::style::Color::Red));

        assert_eq!(diff_indices(&prev, &curr), vec![6]);
    }

    #[test]
    fn diff_indices_returns_all_indices_when_everything_changes() {
        // A buffer-wide background color change touches every cell.
        // The diff length must equal the cell count.
        let area = Rect::new(0, 0, 3, 2);
        let prev = Buffer::empty(area);
        let mut curr = Buffer::empty(area);
        let blue_bg = ratatui::style::Style::default().bg(ratatui::style::Color::Blue);
        for y in 0..area.height {
            for x in 0..area.width {
                curr.cell_mut((x, y)).unwrap().set_style(blue_bg);
            }
        }

        let indices = diff_indices(&prev, &curr);
        assert_eq!(indices.len(), 3 * 2);
        assert_eq!(indices, vec![0, 1, 2, 3, 4, 5]);
    }

    #[test]
    fn diff_indices_distinguishes_style_only_changes_from_no_change() {
        // Same symbol, different fg color — must show up in the diff.
        // This is the test that catches a regression where someone
        // compares only the symbol field.
        let area = Rect::new(0, 0, 2, 1);
        let mut prev = Buffer::empty(area);
        let mut curr = Buffer::empty(area);

        prev.cell_mut((0, 0)).unwrap().set_symbol("a");
        curr.cell_mut((0, 0))
            .unwrap()
            .set_symbol("a")
            .set_style(ratatui::style::Style::default().fg(ratatui::style::Color::Green));

        assert_eq!(diff_indices(&prev, &curr), vec![0]);
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
