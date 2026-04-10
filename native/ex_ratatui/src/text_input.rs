use std::sync::Mutex;

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Paragraph, Widget};

use rustler::{Atom, Error, Resource, ResourceArc};

use crate::widgets::block::BlockData;

mod atoms {
    rustler::atoms! {
        ok,
    }
}

pub struct TextInputState {
    value: String,
    cursor: usize,
    viewport_offset: usize,
}

impl TextInputState {
    fn new() -> Self {
        Self {
            value: String::new(),
            cursor: 0,
            viewport_offset: 0,
        }
    }

    fn handle_key(&mut self, key_code: &str) {
        let chars: Vec<char> = self.value.chars().collect();
        let len = chars.len();

        match key_code {
            "backspace" => {
                if self.cursor > 0 {
                    self.cursor -= 1;
                    let byte_idx: usize = chars[..self.cursor].iter().map(|c| c.len_utf8()).sum();
                    let removed_len = chars[self.cursor].len_utf8();
                    self.value.drain(byte_idx..byte_idx + removed_len);
                }
            }
            "delete" => {
                if self.cursor < len {
                    let byte_idx: usize = chars[..self.cursor].iter().map(|c| c.len_utf8()).sum();
                    let removed_len = chars[self.cursor].len_utf8();
                    self.value.drain(byte_idx..byte_idx + removed_len);
                }
            }
            "left" => {
                if self.cursor > 0 {
                    self.cursor -= 1;
                }
            }
            "right" => {
                if self.cursor < len {
                    self.cursor += 1;
                }
            }
            "home" => {
                self.cursor = 0;
            }
            "end" => {
                self.cursor = len;
            }
            // Ignore special keys that aren't handled above
            "enter" | "escape" | "esc" | "tab" | "back_tab" | "up" | "down" | "page_up"
            | "page_down" | "insert" | "null" | "caps_lock" | "scroll_lock" | "num_lock"
            | "print_screen" | "pause" | "menu" | "keypad_begin" | "f1" | "f2" | "f3" | "f4"
            | "f5" | "f6" | "f7" | "f8" | "f9" | "f10" | "f11" | "f12" => {}
            ch => {
                if !ch.is_empty() && ch.chars().all(|c| !c.is_control()) {
                    let byte_idx: usize = chars[..self.cursor].iter().map(|c| c.len_utf8()).sum();
                    self.value.insert_str(byte_idx, ch);
                    self.cursor += ch.chars().count();
                }
            }
        }
    }
}

pub struct TextInputResource {
    pub state: Mutex<TextInputState>,
}

#[rustler::resource_impl]
impl Resource for TextInputResource {}

// -- NIF functions --

#[rustler::nif]
fn text_input_new() -> ResourceArc<TextInputResource> {
    ResourceArc::new(TextInputResource {
        state: Mutex::new(TextInputState::new()),
    })
}

#[rustler::nif]
fn text_input_handle_key(
    resource: ResourceArc<TextInputResource>,
    key_code: String,
) -> Result<Atom, Error> {
    let mut state = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("text_input lock poisoned")))?;
    state.handle_key(&key_code);
    Ok(atoms::ok())
}

#[rustler::nif]
fn text_input_get_value(resource: ResourceArc<TextInputResource>) -> Result<String, Error> {
    let state = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("text_input lock poisoned")))?;
    Ok(state.value.clone())
}

#[rustler::nif]
fn text_input_set_value(
    resource: ResourceArc<TextInputResource>,
    value: String,
) -> Result<Atom, Error> {
    let mut state = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("text_input lock poisoned")))?;
    let char_count = value.chars().count();
    state.value = value;
    state.cursor = char_count;
    state.viewport_offset = 0;
    Ok(atoms::ok())
}

#[rustler::nif]
fn text_input_cursor(resource: ResourceArc<TextInputResource>) -> Result<usize, Error> {
    let state = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("text_input lock poisoned")))?;
    Ok(state.cursor)
}

// -- Rendering --

pub struct TextInputRenderData {
    pub resource: ResourceArc<TextInputResource>,
    pub style: Style,
    pub cursor_style: Style,
    pub placeholder: Option<String>,
    pub placeholder_style: Style,
    pub block: Option<BlockData>,
}

pub fn render(buf: &mut Buffer, data: &TextInputRenderData, area: Rect) {
    let mut state = match data.resource.state.lock() {
        Ok(state) => state,
        Err(poisoned) => poisoned.into_inner(),
    };

    let opts = RenderOpts {
        style: data.style,
        cursor_style: data.cursor_style,
        placeholder: data.placeholder.as_deref(),
        placeholder_style: data.placeholder_style,
        block: data.block.as_ref(),
    };
    render_state(buf, &mut state, area, &opts);
}

struct RenderOpts<'a> {
    style: Style,
    cursor_style: Style,
    placeholder: Option<&'a str>,
    placeholder_style: Style,
    block: Option<&'a BlockData>,
}

fn render_state(buf: &mut Buffer, state: &mut TextInputState, area: Rect, opts: &RenderOpts) {
    let inner_width = if opts.block.is_some() {
        area.width.saturating_sub(2) as usize
    } else {
        area.width as usize
    };

    if inner_width == 0 {
        return;
    }

    let chars: Vec<char> = state.value.chars().collect();
    let len = chars.len();

    // Adjust viewport to keep cursor visible
    if state.cursor < state.viewport_offset {
        state.viewport_offset = state.cursor;
    } else if state.cursor >= state.viewport_offset + inner_width {
        state.viewport_offset = state.cursor.saturating_sub(inner_width - 1);
    }

    let line = if chars.is_empty() {
        if let Some(placeholder) = opts.placeholder {
            let visible: String = placeholder.chars().take(inner_width).collect();
            if state.cursor == 0 {
                let mut spans = Vec::new();
                let mut pchars = visible.chars();
                if let Some(first) = pchars.next() {
                    spans.push(Span::styled(first.to_string(), opts.cursor_style));
                    let rest: String = pchars.collect();
                    if !rest.is_empty() {
                        spans.push(Span::styled(rest, opts.placeholder_style));
                    }
                }
                Line::from(spans)
            } else {
                Line::from(Span::styled(visible, opts.placeholder_style))
            }
        } else {
            Line::from(Span::styled(" ", opts.cursor_style))
        }
    } else {
        let visible_end = (state.viewport_offset + inner_width).min(len);
        let visible_chars = &chars[state.viewport_offset..visible_end];

        let cursor_in_view = state.cursor >= state.viewport_offset
            && state.cursor < state.viewport_offset + inner_width;

        if cursor_in_view {
            let cursor_local = state.cursor - state.viewport_offset;
            let mut spans = Vec::new();

            if cursor_local > 0 {
                let before: String = visible_chars[..cursor_local].iter().collect();
                spans.push(Span::styled(before, opts.style));
            }

            if state.cursor < len {
                let cursor_char = visible_chars[cursor_local].to_string();
                spans.push(Span::styled(cursor_char, opts.cursor_style));
            } else {
                spans.push(Span::styled(" ", opts.cursor_style));
            }

            if cursor_local + 1 < visible_chars.len() {
                let after: String = visible_chars[cursor_local + 1..].iter().collect();
                spans.push(Span::styled(after, opts.style));
            }

            Line::from(spans)
        } else {
            let text: String = visible_chars.iter().collect();
            Line::from(Span::styled(text, opts.style))
        }
    };

    let mut paragraph = Paragraph::new(line);

    if let Some(block_data) = opts.block {
        paragraph = paragraph.block(block_data.to_block());
    }

    paragraph.render(area, buf);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use ratatui::Terminal;

    fn new_state() -> TextInputState {
        TextInputState::new()
    }

    fn new_state_with(value: &str, cursor: usize) -> TextInputState {
        TextInputState {
            value: value.to_string(),
            cursor,
            viewport_offset: 0,
        }
    }

    #[test]
    fn test_insert_characters() {
        let mut state = new_state();
        state.handle_key("h");
        state.handle_key("e");
        state.handle_key("l");
        state.handle_key("l");
        state.handle_key("o");
        assert_eq!(state.value, "hello");
        assert_eq!(state.cursor, 5);
    }

    #[test]
    fn test_insert_mid_text() {
        let mut state = new_state_with("hllo", 1);
        state.handle_key("e");
        assert_eq!(state.value, "hello");
        assert_eq!(state.cursor, 2);
    }

    #[test]
    fn test_backspace() {
        let mut state = new_state_with("hello", 5);
        state.handle_key("backspace");
        assert_eq!(state.value, "hell");
        assert_eq!(state.cursor, 4);
    }

    #[test]
    fn test_backspace_at_start() {
        let mut state = new_state_with("hello", 0);
        state.handle_key("backspace");
        assert_eq!(state.value, "hello");
        assert_eq!(state.cursor, 0);
    }

    #[test]
    fn test_delete() {
        let mut state = new_state_with("hello", 0);
        state.handle_key("delete");
        assert_eq!(state.value, "ello");
        assert_eq!(state.cursor, 0);
    }

    #[test]
    fn test_delete_at_end() {
        let mut state = new_state_with("hello", 5);
        state.handle_key("delete");
        assert_eq!(state.value, "hello");
        assert_eq!(state.cursor, 5);
    }

    #[test]
    fn test_arrow_keys() {
        let mut state = new_state_with("hello", 5);
        state.handle_key("left");
        assert_eq!(state.cursor, 4);
        state.handle_key("left");
        assert_eq!(state.cursor, 3);
        state.handle_key("right");
        assert_eq!(state.cursor, 4);
    }

    #[test]
    fn test_home_end() {
        let mut state = new_state_with("hello", 3);
        state.handle_key("home");
        assert_eq!(state.cursor, 0);
        state.handle_key("end");
        assert_eq!(state.cursor, 5);
    }

    #[test]
    fn test_left_at_start() {
        let mut state = new_state_with("hi", 0);
        state.handle_key("left");
        assert_eq!(state.cursor, 0);
    }

    #[test]
    fn test_right_at_end() {
        let mut state = new_state_with("hi", 2);
        state.handle_key("right");
        assert_eq!(state.cursor, 2);
    }

    #[test]
    fn test_render_with_text() {
        let backend = TestBackend::new(20, 1);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut state = new_state_with("hello", 5);

        terminal
            .draw(|frame| {
                let opts = RenderOpts {
                    style: Style::default(),
                    cursor_style: Style::default().fg(Color::Black).bg(Color::White),
                    placeholder: None,
                    placeholder_style: Style::default(),
                    block: None,
                };
                render_state(
                    frame.buffer_mut(),
                    &mut state,
                    Rect::new(0, 0, 20, 1),
                    &opts,
                );
            })
            .unwrap();

        let line = buffer_line(&terminal, 0, 20);
        assert!(line.contains("hello"));
    }

    #[test]
    fn test_render_empty_with_placeholder() {
        let backend = TestBackend::new(30, 1);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut state = new_state();

        terminal
            .draw(|frame| {
                let opts = RenderOpts {
                    style: Style::default(),
                    cursor_style: Style::default().fg(Color::Black).bg(Color::White),
                    placeholder: Some("Type here..."),
                    placeholder_style: Style::default().fg(Color::DarkGray),
                    block: None,
                };
                render_state(
                    frame.buffer_mut(),
                    &mut state,
                    Rect::new(0, 0, 30, 1),
                    &opts,
                );
            })
            .unwrap();

        let line = buffer_line(&terminal, 0, 30);
        assert!(line.contains("Type here..."));
    }

    #[test]
    fn test_render_cursor_mid_text() {
        let backend = TestBackend::new(20, 1);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut state = new_state_with("abcdef", 3);

        terminal
            .draw(|frame| {
                let opts = RenderOpts {
                    style: Style::default(),
                    cursor_style: Style::default().fg(Color::Black).bg(Color::White),
                    placeholder: None,
                    placeholder_style: Style::default(),
                    block: None,
                };
                render_state(
                    frame.buffer_mut(),
                    &mut state,
                    Rect::new(0, 0, 20, 1),
                    &opts,
                );
            })
            .unwrap();

        let line = buffer_line(&terminal, 0, 20);
        assert!(line.contains("abcdef"));
    }

    #[test]
    fn test_viewport_scrolling() {
        let backend = TestBackend::new(5, 1);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut state = new_state_with("abcdefghij", 10);

        terminal
            .draw(|frame| {
                let opts = RenderOpts {
                    style: Style::default(),
                    cursor_style: Style::default().fg(Color::Black).bg(Color::White),
                    placeholder: None,
                    placeholder_style: Style::default(),
                    block: None,
                };
                render_state(frame.buffer_mut(), &mut state, Rect::new(0, 0, 5, 1), &opts);
            })
            .unwrap();

        let line = buffer_line(&terminal, 0, 5);
        assert!(line.contains("j"));
    }

    #[test]
    fn test_unicode_handling() {
        let mut state = new_state();
        state.handle_key("é");
        state.handle_key("🦀");
        assert_eq!(state.value, "é🦀");
        assert_eq!(state.cursor, 2);
        state.handle_key("backspace");
        assert_eq!(state.value, "é");
        assert_eq!(state.cursor, 1);
    }

    #[test]
    fn test_special_keys_ignored() {
        let mut state = new_state_with("hello", 5);
        for key in &[
            "enter",
            "escape",
            "esc",
            "tab",
            "back_tab",
            "up",
            "down",
            "page_up",
            "page_down",
            "insert",
            "f1",
            "f12",
            "caps_lock",
            "print_screen",
        ] {
            state.handle_key(key);
        }
        assert_eq!(state.value, "hello");
        assert_eq!(state.cursor, 5);
    }
}
