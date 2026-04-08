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

use std::collections::VecDeque;
use std::io::{self, Write};
use std::sync::{Arc, Mutex};

use ratatui::backend::CrosstermBackend;
use ratatui::layout::Rect;
use ratatui::{Terminal, TerminalOptions, Viewport};

use rustler::{Atom, Error, Resource, ResourceArc};

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

/// A rendered-to-buffer event placeholder. Replaced by a real `ExEvent`-equivalent
/// when the input parser lands — keeping it as a unit-like enum for now so the
/// module compiles before the parser is wired in.
#[allow(dead_code)]
pub enum SessionEvent {}

/// Per-session resource. Holds its own terminal, writer, event queue, and
/// current size. Protected by coarse mutexes because all NIF entry points
/// are short-running and the contention per session is effectively zero
/// (one BEAM process per session).
///
/// The `terminal` slot is an `Option` so `session_close` can drop the
/// underlying ratatui `Terminal` (and the backend's writer clone with it)
/// without waiting for the BEAM garbage collector. Subsequent operations on
/// a closed session surface a clear error instead of panicking.
pub struct SessionResource {
    pub(crate) terminal: Mutex<Option<Terminal<CrosstermBackend<SharedWriter>>>>,
    #[allow(dead_code)]
    pub(crate) writer: SharedWriter,
    #[allow(dead_code)]
    pub(crate) events: Mutex<VecDeque<SessionEvent>>,
    #[allow(dead_code)]
    pub(crate) size: Mutex<(u16, u16)>,
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
    /// viewport so it never calls `CrosstermBackend::size()` — that function
    /// would otherwise query the host tty via `crossterm::terminal::size()`,
    /// which fails under the BEAM (and fundamentally violates the whole
    /// "transport controls the size" contract). A fixed viewport also means
    /// autoresize is a no-op during draws, so concurrent sessions can never
    /// drift into the host's terminal dimensions.
    ///
    /// No OS-level state is touched — no raw mode, no alt screen, no signal
    /// handlers.
    pub fn new(width: u16, height: u16) -> Result<Self, String> {
        let writer = SharedWriter::new();
        let backend = CrosstermBackend::new(writer.clone());
        let options = TerminalOptions {
            viewport: Viewport::Fixed(Rect::new(0, 0, width, height)),
        };
        let terminal = Terminal::with_options(backend, options)
            .map_err(|e| format!("session terminal init: {e}"))?;

        Ok(Self {
            terminal: Mutex::new(Some(terminal)),
            writer,
            events: Mutex::new(VecDeque::new()),
            size: Mutex::new((width, height)),
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
