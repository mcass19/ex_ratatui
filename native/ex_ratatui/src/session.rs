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
use ratatui::Terminal;

use rustler::Resource;

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
pub struct SessionResource {
    #[allow(dead_code)]
    pub(crate) terminal: Mutex<Terminal<CrosstermBackend<SharedWriter>>>,
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
    /// No OS-level state is touched — no raw mode, no alt screen, no signal
    /// handlers.
    #[allow(dead_code)]
    pub fn new(width: u16, height: u16) -> Result<Self, String> {
        let writer = SharedWriter::new();
        let backend = CrosstermBackend::new(writer.clone());
        let mut terminal =
            Terminal::new(backend).map_err(|e| format!("session terminal init: {e}"))?;

        terminal
            .resize(ratatui::layout::Rect::new(0, 0, width, height))
            .map_err(|e| format!("session terminal resize: {e}"))?;

        Ok(Self {
            terminal: Mutex::new(terminal),
            writer,
            events: Mutex::new(VecDeque::new()),
            size: Mutex::new((width, height)),
        })
    }
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
    fn session_resource_writer_is_shared_with_backend() {
        let session = SessionResource::new(10, 5).unwrap();
        // Terminal construction and the initial resize push ANSI setup bytes
        // into the shared buffer via the backend. Drain them, then prove that
        // writes through a cloned handle are also visible — both directions
        // confirm the writer is a single shared buffer.
        let setup_bytes = session.writer.drain();
        assert!(!setup_bytes.is_empty(), "expected backend to emit setup");

        let mut writer_handle = session.writer.clone();
        writer_handle.write_all(b"hi").unwrap();
        assert_eq!(session.writer.drain(), b"hi");
    }
}
