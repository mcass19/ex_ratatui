//! ANSI input byte parser for [`crate::session::SessionResource`].
//!
//! Wraps a [`vte::Parser`] and translates the resulting state-machine
//! callbacks into [`NifEvent`] values that match what the local
//! [`crate::events::poll_event`] path emits. The whole point is that an
//! `App` consuming events can't tell — and shouldn't care — whether the
//! bytes came from a host PTY via crossterm or from an SSH channel via
//! this parser.
//!
//! The parser holds state across `feed` calls: a partial CSI sequence
//! (e.g. an `ESC [` arriving in one chunk and the rest in the next) is
//! buffered internally by `vte::Parser` until completion. The
//! `pending_ss3` flag tracks the same thing across the SS3 boundary
//! (`ESC O <key>`), which vte does not handle natively because `O`
//! terminates an escape sequence on its own.
//!
//! This intentionally only emits press events. Remote PTYs don't ship
//! key release/repeat info via raw bytes — that information lives in
//! kitty-protocol or win32-input-mode, neither of which is in scope for
//! the first SSH transport pass.

use vte::{Params, Parser, Perform};

use crate::events::NifEvent;

const KIND_PRESS: &str = "press";

/// Stateful per-session input parser. Construct one and reuse it across
/// transport reads — partial sequences are buffered until completion.
pub struct InputParser {
    parser: Parser,
    /// True after we've seen the `ESC O` half of an SS3 sequence and are
    /// waiting for the final byte. vte fires `esc_dispatch` for the `O`
    /// because `O` (0x4F) is a valid escape terminator on its own, then
    /// the next byte arrives via `print` or `execute`. We translate that
    /// next byte using [`ss3_final_to_code`] when this flag is set.
    pending_ss3: bool,
}

impl InputParser {
    pub fn new() -> Self {
        Self {
            parser: Parser::new(),
            pending_ss3: false,
        }
    }

    /// Feeds a chunk of raw transport bytes through the parser, appending
    /// any newly-completed events to `out`. Bytes that only partially form
    /// a sequence stay in the parser's internal buffer for the next call.
    pub fn feed(&mut self, bytes: &[u8], out: &mut Vec<NifEvent>) {
        let mut perf = InputPerformer {
            out,
            pending_ss3: self.pending_ss3,
        };
        self.parser.advance(&mut perf, bytes);
        self.pending_ss3 = perf.pending_ss3;
    }
}

impl Default for InputParser {
    fn default() -> Self {
        Self::new()
    }
}

/// Borrowed performer used for a single `feed` call. Holds a `&mut` to
/// the caller's output buffer and a copy of the SS3 latch so the parent
/// `InputParser` can take the latch back when the call returns.
struct InputPerformer<'a> {
    out: &'a mut Vec<NifEvent>,
    pending_ss3: bool,
}

impl InputPerformer<'_> {
    fn push_key(&mut self, code: impl Into<String>, modifiers: Vec<String>) {
        self.out
            .push(NifEvent::Key(code.into(), modifiers, KIND_PRESS.into()));
    }
}

impl Perform for InputPerformer<'_> {
    fn print(&mut self, c: char) {
        // SS3 prefix consumed earlier — translate the next printable as an
        // SS3 final byte instead of treating it as text.
        if self.pending_ss3 {
            self.pending_ss3 = false;
            if let Some(code) = ss3_final_to_code(c) {
                self.push_key(code, Vec::new());
                return;
            }
            // Unknown SS3 final — fall through and treat as a plain print.
        }

        // vte 0.15 routes 0x7F (DEL) through `print` rather than
        // `execute` because it's outside the 0x00..=0x1F C0 range. Most
        // modern terminals send 0x7F for the Backspace key so we map it
        // here rather than emitting a literal DEL character.
        if c == '\x7F' {
            self.push_key("backspace", Vec::new());
            return;
        }

        self.push_key(c.to_string(), Vec::new());
    }

    fn execute(&mut self, byte: u8) {
        // C0 control bytes — Ctrl+letter and the named controls. The
        // arms for 0x08/0x09/0x0A/0x0D/0x1B come *before* the
        // 0x01..=0x1A range so that backspace/tab/enter/esc keep their
        // friendly names instead of being reported as Ctrl+H/I/J/M/[.
        match byte {
            0x00 => self.push_key(" ", vec!["ctrl".into()]),
            0x08 => self.push_key("backspace", Vec::new()),
            0x09 => self.push_key("tab", Vec::new()),
            0x0A | 0x0D => self.push_key("enter", Vec::new()),
            0x1B => self.push_key("esc", Vec::new()),
            b if (0x01..=0x1A).contains(&b) => {
                let letter = ((b - 1) + b'a') as char;
                self.push_key(letter.to_string(), vec!["ctrl".into()]);
            }
            _ => {}
        }
    }

    fn esc_dispatch(&mut self, intermediates: &[u8], _ignore: bool, byte: u8) {
        // SS3 (`ESC O X`): vte resolves `ESC O` as an esc_dispatch with
        // byte `'O'` and empty intermediates because 'O' falls in the
        // 0x30..=0x4F terminator range. We arm a flag and translate the
        // *next* printable as the SS3 final byte.
        if intermediates.is_empty() && byte == b'O' {
            self.pending_ss3 = true;
            return;
        }

        // Alt+key is sent as `ESC + key`. vte hands us the key via
        // esc_dispatch with empty intermediates and byte = key.
        if intermediates.is_empty() {
            if let Some(c) = ascii_alt_byte(byte) {
                self.push_key(c.to_string(), vec!["alt".into()]);
            }
        }
    }

    fn csi_dispatch(
        &mut self,
        params: &Params,
        _intermediates: &[u8],
        _ignore: bool,
        action: char,
    ) {
        if let Some(event) = csi_to_event(params, action) {
            self.out.push(event);
        }
    }
}

/// Translates the trailing byte of an SS3 sequence (`ESC O <byte>`) into
/// our event-name vocabulary. Returns `None` for unknown finals so the
/// caller can fall through to printing.
fn ss3_final_to_code(c: char) -> Option<&'static str> {
    Some(match c {
        'A' => "up",
        'B' => "down",
        'C' => "right",
        'D' => "left",
        'H' => "home",
        'F' => "end",
        'P' => "f1",
        'Q' => "f2",
        'R' => "f3",
        'S' => "f4",
        _ => return None,
    })
}

/// Returns `Some(c)` when the byte after a lone ESC looks like an
/// Alt-key payload (printable ASCII). Returns `None` for control bytes
/// and high bits, where the user almost certainly didn't type
/// Alt+<that>.
fn ascii_alt_byte(byte: u8) -> Option<char> {
    if (0x20..0x7F).contains(&byte) {
        Some(byte as char)
    } else {
        None
    }
}

/// Maps a fully-parsed CSI sequence into an event. Returns `None` if the
/// sequence isn't one we know how to translate — caller drops it on the
/// floor rather than synthesising garbage.
fn csi_to_event(params: &Params, action: char) -> Option<NifEvent> {
    // Cursor Position Report: `CSI <row> ; <col> R`. The client sends
    // this in response to `ESC[6n`, which the SSH subsystem transport
    // emits right after parking the cursor at `ESC[9999;9999H` so the
    // reported position is clamped to the terminal's real dimensions.
    // That roundtrip is the only way subsystem-dispatched handlers can
    // learn the client's pty size — OTP `:ssh` consumes pty_req before
    // the handler exists, so it never reaches us as a channel request.
    // Emit a Resize event with `(col, row)` to match the `(width,
    // height)` shape the rest of the pipeline uses.
    if action == 'R' {
        let mut iter = params.iter();
        let row: u16 = iter.next().and_then(|p| p.first().copied())?;
        let col: u16 = iter.next().and_then(|p| p.first().copied())?;
        return Some(NifEvent::Resize(col, row));
    }

    let modifiers = csi_modifiers(params);

    if let Some(code) = simple_csi_code(action) {
        return Some(NifEvent::Key(code.into(), modifiers, KIND_PRESS.into()));
    }

    // Tilde-terminated keys: `CSI <num> ~` → page_up, page_down, delete,
    // insert, F-keys, ...
    if action == '~' {
        let n = first_param(params)?;
        if let Some(code) = tilde_param_to_code(n) {
            return Some(NifEvent::Key(code.into(), modifiers, KIND_PRESS.into()));
        }
    }

    None
}

fn simple_csi_code(action: char) -> Option<&'static str> {
    Some(match action {
        'A' => "up",
        'B' => "down",
        'C' => "right",
        'D' => "left",
        'H' => "home",
        'F' => "end",
        'Z' => "back_tab",
        _ => return None,
    })
}

fn tilde_param_to_code(n: u16) -> Option<&'static str> {
    Some(match n {
        1 | 7 => "home",
        2 => "insert",
        3 => "delete",
        4 | 8 => "end",
        5 => "page_up",
        6 => "page_down",
        11 => "f1",
        12 => "f2",
        13 => "f3",
        14 => "f4",
        15 => "f5",
        17 => "f6",
        18 => "f7",
        19 => "f8",
        20 => "f9",
        21 => "f10",
        23 => "f11",
        24 => "f12",
        _ => return None,
    })
}

fn first_param(params: &Params) -> Option<u16> {
    params.iter().next()?.first().copied()
}

/// Parses an xterm-style modifier mask out of the second CSI parameter.
/// Sequences without a second parameter return an empty modifier list.
///
/// xterm encoding: `value - 1` is a bitfield with bit 0 = shift, bit 1 =
/// alt, bit 2 = ctrl, bit 3 = meta. So `CSI 1 ; 5 A` carries `5 - 1 = 4
/// = 0b100 = ctrl`, yielding `Ctrl+Up`.
fn csi_modifiers(params: &Params) -> Vec<String> {
    let mut iter = params.iter();
    let _first = iter.next();
    let second = match iter.next().and_then(|p| p.first().copied()) {
        Some(v) => v,
        None => return Vec::new(),
    };
    if second == 0 {
        return Vec::new();
    }
    let mask = second.saturating_sub(1);
    let mut out = Vec::new();
    if mask & 1 != 0 {
        out.push("shift".into());
    }
    if mask & 2 != 0 {
        out.push("alt".into());
    }
    if mask & 4 != 0 {
        out.push("ctrl".into());
    }
    if mask & 8 != 0 {
        out.push("meta".into());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Convenience: feed `bytes` through a fresh parser and return the
    /// resulting events. Used by tests that don't care about cross-call
    /// state.
    fn parse(bytes: &[u8]) -> Vec<NifEvent> {
        let mut parser = InputParser::new();
        let mut events = Vec::new();
        parser.feed(bytes, &mut events);
        events
    }

    fn unwrap_key(event: &NifEvent) -> (&str, &[String], &str) {
        match event {
            NifEvent::Key(code, mods, kind) => (code.as_str(), mods.as_slice(), kind.as_str()),
            NifEvent::Mouse(_, _, _, _, _) => panic!("expected Key event, got Mouse"),
            NifEvent::Resize(_, _) => panic!("expected Key event, got Resize"),
            NifEvent::Paste(_) => panic!("expected Key event, got Paste"),
        }
    }

    #[test]
    fn parses_plain_ascii_char() {
        let events = parse(b"a");
        assert_eq!(events.len(), 1);
        let (code, mods, kind) = unwrap_key(&events[0]);
        assert_eq!(code, "a");
        assert!(mods.is_empty());
        assert_eq!(kind, "press");
    }

    #[test]
    fn parses_multiple_chars_in_one_feed() {
        let events = parse(b"hi");
        assert_eq!(events.len(), 2);
        assert_eq!(unwrap_key(&events[0]).0, "h");
        assert_eq!(unwrap_key(&events[1]).0, "i");
    }

    #[test]
    fn parses_ctrl_letter() {
        // Ctrl+C is 0x03.
        let events = parse(&[0x03]);
        assert_eq!(events.len(), 1);
        let (code, mods, _) = unwrap_key(&events[0]);
        assert_eq!(code, "c");
        assert_eq!(mods, &["ctrl".to_string()]);
    }

    #[test]
    fn parses_named_controls_over_ctrl_letter() {
        // 0x09 is Tab, not Ctrl+I.
        assert_eq!(unwrap_key(&parse(&[0x09])[0]).0, "tab");
        // 0x0A is Enter (LF), not Ctrl+J.
        assert_eq!(unwrap_key(&parse(&[0x0A])[0]).0, "enter");
        // 0x0D is Enter (CR), not Ctrl+M.
        assert_eq!(unwrap_key(&parse(&[0x0D])[0]).0, "enter");
        // 0x08 is Backspace.
        assert_eq!(unwrap_key(&parse(&[0x08])[0]).0, "backspace");
        // 0x7F is also Backspace (modern xterm).
        assert_eq!(unwrap_key(&parse(&[0x7F])[0]).0, "backspace");
    }

    #[test]
    fn parses_ctrl_space() {
        // Ctrl+Space is 0x00.
        let events = parse(&[0x00]);
        let (code, mods, _) = unwrap_key(&events[0]);
        assert_eq!(code, " ");
        assert_eq!(mods, &["ctrl".to_string()]);
    }

    #[test]
    fn parses_csi_arrow_keys() {
        for (bytes, expected) in [
            (b"\x1b[A".as_slice(), "up"),
            (b"\x1b[B".as_slice(), "down"),
            (b"\x1b[C".as_slice(), "right"),
            (b"\x1b[D".as_slice(), "left"),
            (b"\x1b[H".as_slice(), "home"),
            (b"\x1b[F".as_slice(), "end"),
        ] {
            let events = parse(bytes);
            assert_eq!(events.len(), 1, "for input {bytes:?}");
            let (code, mods, _) = unwrap_key(&events[0]);
            assert_eq!(code, expected, "for input {bytes:?}");
            assert!(mods.is_empty(), "expected no modifiers for {bytes:?}");
        }
    }

    #[test]
    fn parses_csi_with_modifiers() {
        // CSI 1 ; 5 A — Ctrl+Up.
        let events = parse(b"\x1b[1;5A");
        let (code, mods, _) = unwrap_key(&events[0]);
        assert_eq!(code, "up");
        assert_eq!(mods, &["ctrl".to_string()]);
    }

    #[test]
    fn parses_csi_shift_alt_combination() {
        // CSI 1 ; 4 D — Alt+Shift+Left (mask = 4 - 1 = 0b011).
        let events = parse(b"\x1b[1;4D");
        let (code, mods, _) = unwrap_key(&events[0]);
        assert_eq!(code, "left");
        assert!(mods.contains(&"shift".to_string()));
        assert!(mods.contains(&"alt".to_string()));
        assert!(!mods.contains(&"ctrl".to_string()));
    }

    #[test]
    fn parses_tilde_terminated_keys() {
        for (bytes, expected) in [
            (b"\x1b[2~".as_slice(), "insert"),
            (b"\x1b[3~".as_slice(), "delete"),
            (b"\x1b[5~".as_slice(), "page_up"),
            (b"\x1b[6~".as_slice(), "page_down"),
            (b"\x1b[15~".as_slice(), "f5"),
            (b"\x1b[17~".as_slice(), "f6"),
            (b"\x1b[24~".as_slice(), "f12"),
        ] {
            let events = parse(bytes);
            assert_eq!(events.len(), 1, "for input {bytes:?}");
            assert_eq!(unwrap_key(&events[0]).0, expected, "for input {bytes:?}");
        }
    }

    #[test]
    fn parses_ss3_function_keys() {
        for (bytes, expected) in [
            (b"\x1bOP".as_slice(), "f1"),
            (b"\x1bOQ".as_slice(), "f2"),
            (b"\x1bOR".as_slice(), "f3"),
            (b"\x1bOS".as_slice(), "f4"),
            (b"\x1bOA".as_slice(), "up"),
            (b"\x1bOH".as_slice(), "home"),
        ] {
            let events = parse(bytes);
            assert_eq!(events.len(), 1, "for input {bytes:?}");
            assert_eq!(unwrap_key(&events[0]).0, expected, "for input {bytes:?}");
        }
    }

    #[test]
    fn parses_alt_letter() {
        // ESC + 'a' → Alt+a.
        let events = parse(b"\x1ba");
        assert_eq!(events.len(), 1);
        let (code, mods, _) = unwrap_key(&events[0]);
        assert_eq!(code, "a");
        assert_eq!(mods, &["alt".to_string()]);
    }

    #[test]
    fn buffers_partial_csi_across_feeds() {
        // The transport may chunk an escape sequence anywhere. The
        // parser must hold state across feed calls and only emit the
        // event when the sequence is complete — otherwise SSH (which
        // ships chars one at a time during interactive use) would
        // generate spurious key events for every byte of every escape.
        let mut parser = InputParser::new();
        let mut events = Vec::new();

        parser.feed(b"\x1b", &mut events);
        assert!(events.is_empty(), "lone ESC must not flush yet");

        parser.feed(b"[", &mut events);
        assert!(events.is_empty(), "ESC [ is still incomplete");

        parser.feed(b"A", &mut events);
        assert_eq!(events.len(), 1);
        assert_eq!(unwrap_key(&events[0]).0, "up");
    }

    #[test]
    fn buffers_partial_ss3_across_feeds() {
        // Same idea but for SS3: ESC O P arriving as three separate
        // chunks must produce one F1 event, not three garbage events.
        let mut parser = InputParser::new();
        let mut events = Vec::new();

        parser.feed(b"\x1b", &mut events);
        parser.feed(b"O", &mut events);
        assert!(events.is_empty(), "ESC O alone must not flush");

        parser.feed(b"P", &mut events);
        assert_eq!(events.len(), 1);
        assert_eq!(unwrap_key(&events[0]).0, "f1");
    }

    #[test]
    fn unknown_csi_action_is_dropped() {
        // CSI X (some private final byte) — we don't know it, so we
        // emit nothing rather than fabricating an event.
        let events = parse(b"\x1b[X");
        assert!(events.is_empty());
    }

    #[test]
    fn parses_cpr_response_as_resize() {
        // CSI 30 ; 100 R — client reports cursor at row 30, col 100.
        // That's the Cursor Position Report response triggered by
        // `ESC[9999;9999H\e[6n`, which the SSH subsystem transport
        // fires on channel_up to discover the client's real pty size.
        // Emit as Resize(col=100, row=30) to match (width, height).
        let events = parse(b"\x1b[30;100R");
        assert_eq!(events.len(), 1);
        match &events[0] {
            NifEvent::Resize(w, h) => {
                assert_eq!(*w, 100);
                assert_eq!(*h, 30);
            }
            _ => panic!("expected Resize event"),
        }
    }

    #[test]
    fn cpr_response_without_both_params_is_dropped() {
        // A malformed CPR with only a row (no col) should not produce
        // a garbage Resize with a zero width — drop it cleanly.
        let events = parse(b"\x1b[42R");
        assert!(events.is_empty());
    }

    #[test]
    fn cpr_response_buffered_across_feeds() {
        // The client may deliver the CPR response one byte at a time
        // over the SSH channel. Ensure the parser reassembles it and
        // emits the Resize event only when the sequence is complete.
        let mut parser = InputParser::new();
        let mut events = Vec::new();

        for byte in b"\x1b[25;80R" {
            parser.feed(&[*byte], &mut events);
        }

        assert_eq!(events.len(), 1);
        match &events[0] {
            NifEvent::Resize(w, h) => {
                assert_eq!(*w, 80);
                assert_eq!(*h, 25);
            }
            _ => panic!("expected Resize event"),
        }
    }

    #[test]
    fn empty_feed_produces_no_events() {
        let events = parse(b"");
        assert!(events.is_empty());
    }

    #[test]
    fn parses_mixed_text_and_controls() {
        // Realistic interactive line: "hi\n" — two prints then enter.
        let events = parse(b"hi\n");
        assert_eq!(events.len(), 3);
        assert_eq!(unwrap_key(&events[0]).0, "h");
        assert_eq!(unwrap_key(&events[1]).0, "i");
        assert_eq!(unwrap_key(&events[2]).0, "enter");
    }
}
