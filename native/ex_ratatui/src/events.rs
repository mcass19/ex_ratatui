use std::time::Duration;

use crossterm::event::{
    self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton, MouseEvent,
    MouseEventKind,
};
use rustler::Error;

/// Tagged enum that encodes as Elixir tagged tuples:
///   {:key, code, modifiers, kind}
///   {:mouse, kind, button, x, y, modifiers}
///   {:resize, width, height}
///   {:paste, content}
#[derive(rustler::NifTaggedEnum)]
pub enum NifEvent {
    Key(String, Vec<String>, String),
    Mouse(String, String, u16, u16, Vec<String>),
    Resize(u16, u16),
    Paste(String),
}

#[rustler::nif(schedule = "DirtyIo")]
fn poll_event(timeout_ms: u64) -> Result<Option<NifEvent>, Error> {
    let timeout = Duration::from_millis(timeout_ms);

    let available = event::poll(timeout).map_err(|e| Error::Term(Box::new(format!("{e}"))))?;

    if !available {
        return Ok(None);
    }

    let event = event::read().map_err(|e| Error::Term(Box::new(format!("{e}"))))?;

    match event {
        Event::Key(key_event) => Ok(Some(convert_key_event(key_event))),
        Event::Mouse(mouse_event) => Ok(Some(convert_mouse_event(mouse_event))),
        Event::Resize(width, height) => Ok(Some(NifEvent::Resize(width, height))),
        Event::Paste(content) => Ok(Some(NifEvent::Paste(content))),
        _ => Ok(None), // FocusGained, FocusLost — ignore for now
    }
}

fn convert_key_event(event: KeyEvent) -> NifEvent {
    let code = convert_key_code(event.code);
    let modifiers = convert_modifiers(event.modifiers);
    let kind = match event.kind {
        KeyEventKind::Press => "press",
        KeyEventKind::Release => "release",
        KeyEventKind::Repeat => "repeat",
    };

    NifEvent::Key(code, modifiers, kind.to_string())
}

fn convert_key_code(code: KeyCode) -> String {
    match code {
        KeyCode::Char(c) => c.to_string(),
        KeyCode::F(n) => format!("f{n}"),
        KeyCode::Backspace => "backspace".into(),
        KeyCode::Enter => "enter".into(),
        KeyCode::Left => "left".into(),
        KeyCode::Right => "right".into(),
        KeyCode::Up => "up".into(),
        KeyCode::Down => "down".into(),
        KeyCode::Home => "home".into(),
        KeyCode::End => "end".into(),
        KeyCode::PageUp => "page_up".into(),
        KeyCode::PageDown => "page_down".into(),
        KeyCode::Tab => "tab".into(),
        KeyCode::BackTab => "back_tab".into(),
        KeyCode::Delete => "delete".into(),
        KeyCode::Insert => "insert".into(),
        KeyCode::Esc => "esc".into(),
        KeyCode::CapsLock => "caps_lock".into(),
        KeyCode::ScrollLock => "scroll_lock".into(),
        KeyCode::NumLock => "num_lock".into(),
        KeyCode::PrintScreen => "print_screen".into(),
        KeyCode::Pause => "pause".into(),
        KeyCode::Menu => "menu".into(),
        KeyCode::KeypadBegin => "keypad_begin".into(),
        KeyCode::Null => "null".into(),
        _ => "unknown".into(),
    }
}

fn convert_mouse_event(event: MouseEvent) -> NifEvent {
    let (kind, button) = match event.kind {
        MouseEventKind::Down(btn) => ("down", convert_mouse_button(btn)),
        MouseEventKind::Up(btn) => ("up", convert_mouse_button(btn)),
        MouseEventKind::Drag(btn) => ("drag", convert_mouse_button(btn)),
        MouseEventKind::Moved => ("moved", String::new()),
        MouseEventKind::ScrollDown => ("scroll_down", String::new()),
        MouseEventKind::ScrollUp => ("scroll_up", String::new()),
        MouseEventKind::ScrollLeft => ("scroll_left", String::new()),
        MouseEventKind::ScrollRight => ("scroll_right", String::new()),
    };

    let modifiers = convert_modifiers(event.modifiers);

    NifEvent::Mouse(kind.to_string(), button, event.column, event.row, modifiers)
}

fn convert_mouse_button(button: MouseButton) -> String {
    match button {
        MouseButton::Left => "left".into(),
        MouseButton::Right => "right".into(),
        MouseButton::Middle => "middle".into(),
    }
}

fn convert_modifiers(modifiers: KeyModifiers) -> Vec<String> {
    let mut result = Vec::new();
    if modifiers.contains(KeyModifiers::SHIFT) {
        result.push("shift".into());
    }
    if modifiers.contains(KeyModifiers::CONTROL) {
        result.push("ctrl".into());
    }
    if modifiers.contains(KeyModifiers::ALT) {
        result.push("alt".into());
    }
    if modifiers.contains(KeyModifiers::SUPER) {
        result.push("super".into());
    }
    if modifiers.contains(KeyModifiers::HYPER) {
        result.push("hyper".into());
    }
    if modifiers.contains(KeyModifiers::META) {
        result.push("meta".into());
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::KeyEventState;

    fn make_key(code: KeyCode, modifiers: KeyModifiers, kind: KeyEventKind) -> KeyEvent {
        KeyEvent {
            code,
            modifiers,
            kind,
            state: KeyEventState::NONE,
        }
    }

    #[test]
    fn test_convert_char_key() {
        let event = make_key(KeyCode::Char('q'), KeyModifiers::NONE, KeyEventKind::Press);
        match convert_key_event(event) {
            NifEvent::Key(code, mods, kind) => {
                assert_eq!(code, "q");
                assert!(mods.is_empty());
                assert_eq!(kind, "press");
            }
            _ => panic!("expected Key"),
        }
    }

    #[test]
    fn test_convert_special_keys() {
        let cases = vec![
            (KeyCode::Enter, "enter"),
            (KeyCode::Esc, "esc"),
            (KeyCode::Backspace, "backspace"),
            (KeyCode::Tab, "tab"),
            (KeyCode::Up, "up"),
            (KeyCode::Down, "down"),
            (KeyCode::Left, "left"),
            (KeyCode::Right, "right"),
            (KeyCode::Home, "home"),
            (KeyCode::End, "end"),
            (KeyCode::PageUp, "page_up"),
            (KeyCode::PageDown, "page_down"),
            (KeyCode::Delete, "delete"),
            (KeyCode::Insert, "insert"),
            (KeyCode::F(1), "f1"),
            (KeyCode::F(12), "f12"),
        ];

        for (key_code, expected) in cases {
            let event = make_key(key_code, KeyModifiers::NONE, KeyEventKind::Press);
            match convert_key_event(event) {
                NifEvent::Key(code, _, _) => {
                    assert_eq!(code, expected, "failed for key: {expected}");
                }
                _ => panic!("expected Key"),
            }
        }
    }

    #[test]
    fn test_convert_key_with_modifiers() {
        let event = make_key(
            KeyCode::Char('c'),
            KeyModifiers::CONTROL | KeyModifiers::SHIFT,
            KeyEventKind::Press,
        );
        match convert_key_event(event) {
            NifEvent::Key(code, mods, _) => {
                assert_eq!(code, "c");
                assert!(mods.contains(&"ctrl".to_string()));
                assert!(mods.contains(&"shift".to_string()));
                assert_eq!(mods.len(), 2);
            }
            _ => panic!("expected Key"),
        }
    }

    #[test]
    fn test_convert_key_event_kinds() {
        for (kind, expected) in [
            (KeyEventKind::Press, "press"),
            (KeyEventKind::Release, "release"),
            (KeyEventKind::Repeat, "repeat"),
        ] {
            let event = make_key(KeyCode::Char('a'), KeyModifiers::NONE, kind);
            match convert_key_event(event) {
                NifEvent::Key(_, _, k) => assert_eq!(k, expected),
                _ => panic!("expected Key"),
            }
        }
    }

    #[test]
    fn test_convert_mouse_down() {
        let event = MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Left),
            column: 10,
            row: 20,
            modifiers: KeyModifiers::NONE,
        };
        match convert_mouse_event(event) {
            NifEvent::Mouse(kind, button, x, y, mods) => {
                assert_eq!(kind, "down");
                assert_eq!(button, "left");
                assert_eq!(x, 10);
                assert_eq!(y, 20);
                assert!(mods.is_empty());
            }
            _ => panic!("expected Mouse"),
        }
    }

    #[test]
    fn test_convert_mouse_scroll() {
        let event = MouseEvent {
            kind: MouseEventKind::ScrollUp,
            column: 5,
            row: 3,
            modifiers: KeyModifiers::NONE,
        };
        match convert_mouse_event(event) {
            NifEvent::Mouse(kind, button, _, _, _) => {
                assert_eq!(kind, "scroll_up");
                assert!(button.is_empty());
            }
            _ => panic!("expected Mouse"),
        }
    }

    #[test]
    fn test_convert_mouse_with_modifiers() {
        let event = MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Right),
            column: 0,
            row: 0,
            modifiers: KeyModifiers::ALT,
        };
        match convert_mouse_event(event) {
            NifEvent::Mouse(_, button, _, _, mods) => {
                assert_eq!(button, "right");
                assert_eq!(mods, vec!["alt"]);
            }
            _ => panic!("expected Mouse"),
        }
    }

    #[test]
    fn test_convert_all_modifiers() {
        let all = KeyModifiers::SHIFT
            | KeyModifiers::CONTROL
            | KeyModifiers::ALT
            | KeyModifiers::SUPER
            | KeyModifiers::HYPER
            | KeyModifiers::META;
        let result = convert_modifiers(all);
        assert_eq!(
            result,
            vec!["shift", "ctrl", "alt", "super", "hyper", "meta"]
        );
    }

    #[test]
    fn test_convert_no_modifiers() {
        let result = convert_modifiers(KeyModifiers::NONE);
        assert!(result.is_empty());
    }

    #[test]
    fn test_convert_all_mouse_buttons() {
        assert_eq!(convert_mouse_button(MouseButton::Left), "left");
        assert_eq!(convert_mouse_button(MouseButton::Right), "right");
        assert_eq!(convert_mouse_button(MouseButton::Middle), "middle");
    }

    #[test]
    fn test_paste_variant_constructs() {
        // The Event::Paste -> NifEvent::Paste mapping in poll_event is a
        // direct rebind; this just pins the variant shape and string
        // ownership so future refactors of NifEvent can't silently drop
        // the contents.
        match NifEvent::Paste("hello\nworld".into()) {
            NifEvent::Paste(content) => assert_eq!(content, "hello\nworld"),
            _ => panic!("expected Paste"),
        }
    }
}
