use std::io::Stdout;
use std::sync::Mutex;

use crossterm::event::{DisableBracketedPaste, EnableBracketedPaste};
use crossterm::terminal::{self, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::ExecutableCommand;
use ratatui::backend::{CrosstermBackend, TestBackend};
use ratatui::Terminal;

use rustler::{Atom, Error, Resource, ResourceArc};

mod atoms {
    rustler::atoms! {
        ok,
    }
}

/// Supports both real (crossterm) and test (headless) terminals.
pub(crate) enum AnyTerminal {
    Crossterm(Terminal<CrosstermBackend<Stdout>>),
    Test(Terminal<TestBackend>),
}

/// Per-process terminal resource, wrapped in a ResourceArc for BEAM GC integration.
pub struct TerminalResource {
    pub terminal: Mutex<Option<AnyTerminal>>,
    is_crossterm: bool,
    // Set via `terminal_set_image_protocol/2`. Drives the image render path
    // when `:auto` is requested; falls back to halfblocks when None.
    // Read by `draw_frame` (in `rendering.rs`).
    pub image_protocol: Mutex<Option<crate::image::ProtocolKind>>,
    // Set via `terminal_set_local_probe/3` after running the
    // `image_probe_terminal/0` NIF. When `Some(_)`, `draw_frame` uses
    // `TransportCaps::Local { picker_protocol, font_size }` so `:auto`
    // images render with the detected protocol AND correct font size for
    // Kitty / Sixel / iTerm2 scaling.
    pub local_probe: Mutex<Option<(crate::image::ProtocolKind, (u16, u16))>>,
}

#[rustler::resource_impl]
impl Resource for TerminalResource {}

impl Drop for TerminalResource {
    fn drop(&mut self) {
        let mut guard = match self.terminal.lock() {
            Ok(g) => g,
            Err(_) => return,
        };

        if self.is_crossterm {
            if let Some(AnyTerminal::Crossterm(_)) = guard.take() {
                let _ = std::io::stdout().execute(DisableBracketedPaste);
                let _ = terminal::disable_raw_mode();
                let _ = std::io::stdout().execute(LeaveAlternateScreen);
            }
        }
    }
}

/// Draw a frame using the given terminal resource.
pub fn with_terminal_draw<F>(resource: &TerminalResource, f: F) -> Result<Atom, Error>
where
    F: FnOnce(&mut ratatui::Frame),
{
    let mut guard = resource
        .terminal
        .lock()
        .map_err(|_| Error::Term(Box::new("terminal lock poisoned")))?;
    let terminal = guard
        .as_mut()
        .ok_or_else(|| Error::Term(Box::new("terminal not initialized")))?;

    let draw_result = match terminal {
        AnyTerminal::Crossterm(t) => t.draw(f),
        AnyTerminal::Test(t) => t.draw(f).map_err(std::io::Error::other),
    };

    draw_result.map_err(|e| Error::Term(Box::new(format!("{e}"))))?;
    Ok(atoms::ok())
}

#[rustler::nif(schedule = "DirtyIo")]
fn init_terminal() -> Result<ResourceArc<TerminalResource>, Error> {
    terminal::enable_raw_mode().map_err(|e| Error::Term(Box::new(format!("{e}"))))?;

    if let Err(e) = std::io::stdout().execute(EnterAlternateScreen) {
        let _ = terminal::disable_raw_mode();
        return Err(Error::Term(Box::new(format!("{e}"))));
    }

    // Enable bracketed paste so the terminal wraps pasted content with
    // ESC[200~ / ESC[201~ markers. crossterm decodes those into
    // Event::Paste(String) on the receiver side. Best-effort: terminals
    // that don't support bracketed paste ignore the sequence and we
    // fall back to per-char Key events, the pre-bracketed-paste behavior.
    let _ = std::io::stdout().execute(EnableBracketedPaste);

    let backend = CrosstermBackend::new(std::io::stdout());
    let terminal = match Terminal::new(backend) {
        Ok(t) => t,
        Err(e) => {
            let _ = std::io::stdout().execute(DisableBracketedPaste);
            let _ = std::io::stdout().execute(LeaveAlternateScreen);
            let _ = terminal::disable_raw_mode();
            return Err(Error::Term(Box::new(format!("{e}"))));
        }
    };

    Ok(ResourceArc::new(TerminalResource {
        terminal: Mutex::new(Some(AnyTerminal::Crossterm(terminal))),
        is_crossterm: true,
        image_protocol: Mutex::new(None),
        local_probe: Mutex::new(None),
    }))
}

#[rustler::nif(schedule = "DirtyIo")]
fn restore_terminal(resource: ResourceArc<TerminalResource>) -> Result<Atom, Error> {
    let mut guard = resource
        .terminal
        .lock()
        .map_err(|_| Error::Term(Box::new("terminal lock poisoned")))?;

    match guard.take() {
        Some(AnyTerminal::Crossterm(_)) => {
            let _ = std::io::stdout().execute(DisableBracketedPaste);
            terminal::disable_raw_mode().map_err(|e| Error::Term(Box::new(format!("{e}"))))?;
            std::io::stdout()
                .execute(LeaveAlternateScreen)
                .map_err(|e| Error::Term(Box::new(format!("{e}"))))?;
        }
        Some(AnyTerminal::Test(_)) => {
            // No cleanup needed for test backend
        }
        None => {
            // Already cleaned up, safe no-op
        }
    }

    Ok(atoms::ok())
}

#[rustler::nif(schedule = "DirtyIo")]
fn terminal_size() -> Result<(u16, u16), Error> {
    terminal::size().map_err(|e| Error::Term(Box::new(format!("{e}"))))
}

#[rustler::nif]
fn init_test_terminal(width: u16, height: u16) -> Result<ResourceArc<TerminalResource>, Error> {
    let backend = TestBackend::new(width, height);
    let terminal = Terminal::new(backend).map_err(|e| Error::Term(Box::new(format!("{e}"))))?;

    Ok(ResourceArc::new(TerminalResource {
        terminal: Mutex::new(Some(AnyTerminal::Test(terminal))),
        is_crossterm: false,
        image_protocol: Mutex::new(None),
        local_probe: Mutex::new(None),
    }))
}

#[rustler::nif]
fn terminal_set_image_protocol(
    resource: ResourceArc<TerminalResource>,
    kind: crate::image::ProtocolKind,
) -> Result<Atom, Error> {
    let mut guard = resource
        .image_protocol
        .lock()
        .map_err(|_| Error::Term(Box::new("terminal image_protocol lock poisoned")))?;
    // `:auto` clears the hint (back to halfblocks fallback). Anything else
    // becomes the explicit hint for the render path's resolve_protocol.
    *guard = match kind {
        crate::image::ProtocolKind::Auto => None,
        explicit => Some(explicit),
    };
    Ok(atoms::ok())
}

#[rustler::nif]
fn terminal_set_local_probe(
    resource: ResourceArc<TerminalResource>,
    protocol: crate::image::ProtocolKind,
    font_size: (u16, u16),
) -> Result<Atom, Error> {
    let mut guard = resource
        .local_probe
        .lock()
        .map_err(|_| Error::Term(Box::new("terminal local_probe lock poisoned")))?;
    // `:auto` clears the cached probe — the render path will then fall
    // back to the `image_protocol` hint (if any) or halfblocks.
    *guard = match protocol {
        crate::image::ProtocolKind::Auto => None,
        kind => Some((kind, font_size)),
    };
    Ok(atoms::ok())
}

#[rustler::nif]
fn get_buffer_content(resource: ResourceArc<TerminalResource>) -> Result<String, Error> {
    let guard = resource
        .terminal
        .lock()
        .map_err(|_| Error::Term(Box::new("terminal lock poisoned")))?;

    match guard.as_ref() {
        Some(AnyTerminal::Test(t)) => {
            let buf = t.backend().buffer();
            let mut lines = Vec::new();
            for y in 0..buf.area.height {
                let line: String = (0..buf.area.width)
                    .map(|x| buf.cell((x, y)).map_or(" ", |c| c.symbol()).to_string())
                    .collect();
                lines.push(line.trim_end().to_string());
            }
            // Trim trailing empty lines
            while lines.last().is_some_and(|l| l.is_empty()) {
                lines.pop();
            }
            Ok(lines.join("\n"))
        }
        Some(AnyTerminal::Crossterm(_)) => Err(Error::Term(Box::new(
            "get_buffer_content requires a test terminal",
        ))),
        None => Err(Error::Term(Box::new("terminal not initialized"))),
    }
}
