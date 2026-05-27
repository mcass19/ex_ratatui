use std::sync::Mutex;

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::widgets::Widget;
use ratatui_textarea::TextArea;

use rustler::{Atom, Error, Resource, ResourceArc};

use crate::widgets::block::BlockData;

mod atoms {
    rustler::atoms! {
        ok,
    }
}

pub struct TextareaResource {
    pub state: Mutex<TextArea<'static>>,
}

#[rustler::resource_impl]
impl Resource for TextareaResource {}

// -- Key code conversion --

fn string_to_key_code(key_code: &str) -> KeyCode {
    match key_code {
        "backspace" => KeyCode::Backspace,
        "enter" => KeyCode::Enter,
        "left" => KeyCode::Left,
        "right" => KeyCode::Right,
        "up" => KeyCode::Up,
        "down" => KeyCode::Down,
        "home" => KeyCode::Home,
        "end" => KeyCode::End,
        "page_up" => KeyCode::PageUp,
        "page_down" => KeyCode::PageDown,
        "tab" => KeyCode::Tab,
        "back_tab" => KeyCode::BackTab,
        "delete" => KeyCode::Delete,
        "insert" => KeyCode::Insert,
        "escape" | "esc" => KeyCode::Esc,
        "f1" => KeyCode::F(1),
        "f2" => KeyCode::F(2),
        "f3" => KeyCode::F(3),
        "f4" => KeyCode::F(4),
        "f5" => KeyCode::F(5),
        "f6" => KeyCode::F(6),
        "f7" => KeyCode::F(7),
        "f8" => KeyCode::F(8),
        "f9" => KeyCode::F(9),
        "f10" => KeyCode::F(10),
        "f11" => KeyCode::F(11),
        "f12" => KeyCode::F(12),
        "null" => KeyCode::Null,
        ch => {
            let mut chars = ch.chars();
            match (chars.next(), chars.next()) {
                (Some(c), None) => KeyCode::Char(c),
                _ => KeyCode::Null,
            }
        }
    }
}

fn modifiers_from_strings(mods: &[String]) -> KeyModifiers {
    let mut result = KeyModifiers::empty();
    for m in mods {
        match m.as_str() {
            "shift" => result |= KeyModifiers::SHIFT,
            "ctrl" | "control" => result |= KeyModifiers::CONTROL,
            "alt" => result |= KeyModifiers::ALT,
            "super" => result |= KeyModifiers::SUPER,
            "hyper" => result |= KeyModifiers::HYPER,
            "meta" => result |= KeyModifiers::META,
            _ => {}
        }
    }
    result
}

// -- NIF functions --

#[rustler::nif]
fn textarea_new() -> ResourceArc<TextareaResource> {
    ResourceArc::new(TextareaResource {
        state: Mutex::new(TextArea::default()),
    })
}

#[rustler::nif]
fn textarea_handle_key(
    resource: ResourceArc<TextareaResource>,
    key_code: String,
    modifiers: Vec<String>,
) -> Result<Atom, Error> {
    let mut textarea = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("textarea lock poisoned")))?;

    let code = string_to_key_code(&key_code);
    let mods = modifiers_from_strings(&modifiers);
    let key_event = KeyEvent::new(code, mods);
    textarea.input(key_event);

    Ok(atoms::ok())
}

#[rustler::nif]
fn textarea_insert_str(
    resource: ResourceArc<TextareaResource>,
    content: String,
) -> Result<Atom, Error> {
    let mut textarea = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("textarea lock poisoned")))?;

    // ratatui_textarea::TextArea::insert_str handles `\n` and `\r\n` as
    // newlines natively (lone `\r` is dropped). Multi-byte / multi-line
    // pasted content lands intact at the cursor.
    textarea.insert_str(&content);

    Ok(atoms::ok())
}

#[rustler::nif]
fn textarea_get_value(resource: ResourceArc<TextareaResource>) -> Result<String, Error> {
    let textarea = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("textarea lock poisoned")))?;
    Ok(textarea.lines().join("\n"))
}

#[rustler::nif]
fn textarea_set_value(
    resource: ResourceArc<TextareaResource>,
    value: String,
) -> Result<Atom, Error> {
    let mut textarea = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("textarea lock poisoned")))?;

    let lines: Vec<String> = value.split('\n').map(|s| s.to_string()).collect();
    *textarea = TextArea::new(lines);

    Ok(atoms::ok())
}

#[rustler::nif]
fn textarea_cursor(resource: ResourceArc<TextareaResource>) -> Result<(usize, usize), Error> {
    let textarea = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("textarea lock poisoned")))?;
    let cursor = textarea.cursor();
    Ok((cursor.0, cursor.1))
}

#[rustler::nif]
fn textarea_line_count(resource: ResourceArc<TextareaResource>) -> Result<usize, Error> {
    let textarea = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("textarea lock poisoned")))?;
    Ok(textarea.lines().len())
}

#[rustler::nif]
fn textarea_snapshot(
    resource: ResourceArc<TextareaResource>,
) -> Result<(String, usize, usize), Error> {
    let textarea = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("textarea lock poisoned")))?;
    let value = textarea.lines().join("\n");
    let cursor = textarea.cursor();
    Ok((value, cursor.0, cursor.1))
}

// -- Rendering --

pub struct TextareaRenderData {
    pub resource: ResourceArc<TextareaResource>,
    pub style: Style,
    pub cursor_style: Style,
    pub cursor_line_style: Style,
    pub placeholder: Option<String>,
    pub placeholder_style: Style,
    pub line_number_style: Option<Style>,
    pub block: Option<BlockData>,
}

pub fn render(buf: &mut Buffer, data: &TextareaRenderData, area: Rect) {
    // Render block manually to avoid lifetime issues with Mutex<TextArea<'static>>
    let inner_area = if let Some(ref block_data) = data.block {
        let block = block_data.to_block();
        let inner = block.inner(area);
        Widget::render(block, area, buf);
        inner
    } else {
        area
    };

    // Collect owned values before locking — TextArea<'static> is invariant
    let style = data.style;
    let cursor_style = data.cursor_style;
    let cursor_line_style = data.cursor_line_style;
    let placeholder: Option<String> = data.placeholder.clone();
    let placeholder_style = data.placeholder_style;
    let line_number_style = data.line_number_style;

    let mut textarea = match data.resource.state.lock() {
        Ok(textarea) => textarea,
        Err(poisoned) => poisoned.into_inner(),
    };

    textarea.set_style(style);
    textarea.set_cursor_style(cursor_style);
    textarea.set_cursor_line_style(cursor_line_style);
    textarea.remove_block();

    if let Some(ph) = placeholder {
        textarea.set_placeholder_text(ph);
        textarea.set_placeholder_style(placeholder_style);
    }

    if let Some(ln_style) = line_number_style {
        textarea.set_line_number_style(ln_style);
    } else {
        textarea.remove_line_number();
    }

    Widget::render(&*textarea, inner_area, buf);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    fn new_textarea() -> TextArea<'static> {
        TextArea::default()
    }

    fn input_key(textarea: &mut TextArea<'static>, code: &str, mods: &[&str]) {
        let key_code = string_to_key_code(code);
        let modifiers =
            modifiers_from_strings(&mods.iter().map(|s| s.to_string()).collect::<Vec<_>>());
        textarea.input(KeyEvent::new(key_code, modifiers));
    }

    fn input_char(textarea: &mut TextArea<'static>, code: &str) {
        input_key(textarea, code, &[]);
    }

    #[test]
    fn test_new_textarea_empty() {
        let textarea = new_textarea();
        assert_eq!(textarea.lines(), &[""]);
        assert_eq!(textarea.cursor(), (0, 0));
    }

    #[test]
    fn test_insert_characters() {
        let mut textarea = new_textarea();
        input_char(&mut textarea, "h");
        input_char(&mut textarea, "e");
        input_char(&mut textarea, "l");
        input_char(&mut textarea, "l");
        input_char(&mut textarea, "o");
        assert_eq!(textarea.lines().join("\n"), "hello");
        assert_eq!(textarea.cursor(), (0, 5));
    }

    #[test]
    fn test_enter_creates_newline() {
        let mut textarea = new_textarea();
        input_char(&mut textarea, "a");
        input_char(&mut textarea, "b");
        input_char(&mut textarea, "enter");
        input_char(&mut textarea, "c");
        assert_eq!(textarea.lines().join("\n"), "ab\nc");
        assert_eq!(textarea.cursor(), (1, 1));
    }

    #[test]
    fn test_multiline_value() {
        let lines = vec![
            "line1".to_string(),
            "line2".to_string(),
            "line3".to_string(),
        ];
        let textarea = TextArea::new(lines);
        assert_eq!(textarea.lines().join("\n"), "line1\nline2\nline3");
    }

    #[test]
    fn test_backspace_merges_lines() {
        let lines = vec!["hello".to_string(), "world".to_string()];
        let mut textarea = TextArea::new(lines);
        // Move cursor to start of second line
        use ratatui_textarea::CursorMove;
        textarea.move_cursor(CursorMove::Down);
        textarea.move_cursor(CursorMove::Head);
        // Backspace should merge with previous line
        input_char(&mut textarea, "backspace");
        assert_eq!(textarea.lines().join("\n"), "helloworld");
    }

    #[test]
    fn test_cursor_up_down() {
        let lines = vec!["abc".to_string(), "def".to_string()];
        let mut textarea = TextArea::new(lines);
        // Start at (0,0), move down
        input_char(&mut textarea, "down");
        assert_eq!(textarea.cursor().0, 1);
        input_char(&mut textarea, "up");
        assert_eq!(textarea.cursor().0, 0);
    }

    #[test]
    fn test_home_end_keys() {
        let lines = vec!["hello".to_string()];
        let mut textarea = TextArea::new(lines);
        input_char(&mut textarea, "end");
        assert_eq!(textarea.cursor(), (0, 5));
        input_char(&mut textarea, "home");
        assert_eq!(textarea.cursor(), (0, 0));
    }

    #[test]
    fn test_insert_str_multiline_paste() {
        let mut textarea = new_textarea();
        textarea.insert_str("line1\nline2\nline3");
        assert_eq!(textarea.lines(), &["line1", "line2", "line3"]);
        assert_eq!(textarea.cursor(), (2, 5));
    }

    #[test]
    fn test_insert_str_crlf_normalized() {
        let mut textarea = new_textarea();
        textarea.insert_str("a\r\nb");
        assert_eq!(textarea.lines(), &["a", "b"]);
    }

    #[test]
    fn test_insert_str_at_cursor_position() {
        let mut textarea = TextArea::new(vec!["hello world".to_string()]);
        use ratatui_textarea::CursorMove;
        textarea.move_cursor(CursorMove::Head);
        for _ in 0..5 {
            textarea.move_cursor(CursorMove::Forward);
        }
        textarea.insert_str(" cruel");
        assert_eq!(textarea.lines(), &["hello cruel world"]);
    }

    #[test]
    fn test_set_value_multiline() {
        let value = "line1\nline2\nline3";
        let lines: Vec<String> = value.split('\n').map(|s| s.to_string()).collect();
        let textarea = TextArea::new(lines);
        assert_eq!(textarea.lines().len(), 3);
    }

    #[test]
    fn test_line_count() {
        let textarea = new_textarea();
        assert_eq!(textarea.lines().len(), 1);

        let lines = vec!["a".to_string(), "b".to_string(), "c".to_string()];
        let textarea2 = TextArea::new(lines);
        assert_eq!(textarea2.lines().len(), 3);
    }

    #[test]
    fn test_render_with_text() {
        let backend = TestBackend::new(30, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let lines = vec!["hello world".to_string()];
        let textarea = TextArea::new(lines);

        terminal
            .draw(|frame| {
                frame.render_widget(&textarea, Rect::new(0, 0, 30, 5));
            })
            .unwrap();

        let line = buffer_line(&terminal, 0, 30);
        assert!(
            line.contains("hello world"),
            "Expected 'hello world' in: {line}"
        );
    }

    #[test]
    fn test_render_empty_with_placeholder() {
        let backend = TestBackend::new(30, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let mut textarea = new_textarea();
        textarea.set_placeholder_text("Type here...");

        terminal
            .draw(|frame| {
                frame.render_widget(&textarea, Rect::new(0, 0, 30, 5));
            })
            .unwrap();

        let line = buffer_line(&terminal, 0, 30);
        assert!(
            line.contains("Type here..."),
            "Expected placeholder in: {line}"
        );
    }
}
