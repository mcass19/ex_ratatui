use std::sync::Mutex;

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Paragraph, Widget};

use unicode_width::UnicodeWidthChar;

use rustler::{Atom, Error, Resource, ResourceArc};

use crate::widgets::block::BlockData;

mod atoms {
    rustler::atoms! {
        ok,
    }
}

pub struct TextInputState {
    pub(crate) value: String,
    pub(crate) cursor: usize,
    pub(crate) viewport_offset: usize,
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

#[rustler::nif]
fn text_input_snapshot(
    resource: ResourceArc<TextInputResource>,
) -> Result<(String, usize, usize), Error> {
    let state = resource
        .state
        .lock()
        .map_err(|_| Error::Term(Box::new("text_input lock poisoned")))?;
    Ok((state.value.clone(), state.cursor, state.viewport_offset))
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

// Display-cell width of a single char. Control chars and zero-width chars are 0.
fn char_cells(c: char) -> usize {
    UnicodeWidthChar::width(c).unwrap_or(0)
}

// Cells reserved by the cursor: width of the char under it, or 1 cell when at end.
// Treat zero-width cursor positions as 1 cell so the cursor remains visible.
fn cursor_cells(chars: &[char], cursor: usize) -> usize {
    if cursor < chars.len() {
        char_cells(chars[cursor]).max(1)
    } else {
        1
    }
}

fn cells_in(chars: &[char]) -> usize {
    chars.iter().map(|&c| char_cells(c)).sum()
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

    // Adjust viewport so the cursor remains visible. Both the viewport offset
    // and the cursor are tracked in char units, but visibility is computed in
    // terminal cells so wide chars (CJK, emoji) consume two columns.
    if state.cursor < state.viewport_offset {
        state.viewport_offset = state.cursor;
    }
    let cursor_w = cursor_cells(&chars, state.cursor);
    while state.viewport_offset < state.cursor {
        let cells_to_cursor = cells_in(&chars[state.viewport_offset..state.cursor]);
        if cells_to_cursor + cursor_w <= inner_width {
            break;
        }
        state.viewport_offset += 1;
    }

    let line = if chars.is_empty() {
        if let Some(placeholder) = opts.placeholder {
            let visible = take_cells(placeholder.chars(), inner_width);
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
        let mut spans = Vec::new();
        let mut cells_used = 0usize;
        let mut idx = state.viewport_offset;

        // Before-cursor span (chars between viewport_offset and the cursor).
        let mut before = String::new();
        while idx < state.cursor && idx < len {
            let w = char_cells(chars[idx]);
            if cells_used + w > inner_width {
                break;
            }
            before.push(chars[idx]);
            cells_used += w;
            idx += 1;
        }
        if !before.is_empty() {
            spans.push(Span::styled(before, opts.style));
        }

        // Cursor span. Always emit when reachable from the viewport so the
        // cursor stays visible even when subsequent chars would overflow.
        if state.cursor >= state.viewport_offset {
            if state.cursor < len {
                spans.push(Span::styled(
                    chars[state.cursor].to_string(),
                    opts.cursor_style,
                ));
                cells_used += char_cells(chars[state.cursor]).max(1);
                idx = state.cursor + 1;
            } else {
                spans.push(Span::styled(" ", opts.cursor_style));
                cells_used += 1;
            }
        }

        // After-cursor span: keep appending while chars still fit in the viewport.
        let mut after = String::new();
        while idx < len {
            let w = char_cells(chars[idx]);
            if cells_used + w > inner_width {
                break;
            }
            after.push(chars[idx]);
            cells_used += w;
            idx += 1;
        }
        if !after.is_empty() {
            spans.push(Span::styled(after, opts.style));
        }

        Line::from(spans)
    };

    let mut paragraph = Paragraph::new(line);

    if let Some(block_data) = opts.block {
        paragraph = paragraph.block(block_data.to_block());
    }

    paragraph.render(area, buf);
}

// Take chars from `iter` while their cumulative display width fits in `max_cells`.
fn take_cells<I: IntoIterator<Item = char>>(iter: I, max_cells: usize) -> String {
    let mut out = String::new();
    let mut used = 0usize;
    for c in iter {
        let w = char_cells(c);
        if used + w > max_cells {
            break;
        }
        out.push(c);
        used += w;
    }
    out
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

    fn render_to_line(state: &mut TextInputState, width: u16) -> String {
        let backend = TestBackend::new(width, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        terminal
            .draw(|frame| {
                let opts = RenderOpts {
                    style: Style::default(),
                    cursor_style: Style::default().fg(Color::Black).bg(Color::White),
                    placeholder: None,
                    placeholder_style: Style::default(),
                    block: None,
                };
                render_state(frame.buffer_mut(), state, Rect::new(0, 0, width, 1), &opts);
            })
            .unwrap();

        buffer_line(&terminal, 0, width)
    }

    fn cursor_cell_index(terminal: &Terminal<TestBackend>, y: u16, width: u16) -> Option<u16> {
        let buf = terminal.backend().buffer();
        (0..width).find(|x| {
            buf.cell((*x, y))
                .map(|c| c.bg == Color::White)
                .unwrap_or(false)
        })
    }

    fn render_and_find_cursor(state: &mut TextInputState, width: u16) -> Option<u16> {
        let backend = TestBackend::new(width, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        terminal
            .draw(|frame| {
                let opts = RenderOpts {
                    style: Style::default(),
                    cursor_style: Style::default().fg(Color::Black).bg(Color::White),
                    placeholder: None,
                    placeholder_style: Style::default(),
                    block: None,
                };
                render_state(frame.buffer_mut(), state, Rect::new(0, 0, width, 1), &opts);
            })
            .unwrap();

        cursor_cell_index(&terminal, 0, width)
    }

    #[test]
    fn test_cursor_visible_with_cjk_at_end_fitting_viewport() {
        // 5 CJK chars × 2 cells = 10 cells, plus cursor = 11 cells.
        // With width 10, cursor should be visible at right edge after viewport scrolls.
        let mut state = new_state_with("测试测试测", 5);
        let cursor_pos = render_and_find_cursor(&mut state, 10);
        assert!(
            cursor_pos.is_some(),
            "cursor should be visible after viewport scrolls"
        );
    }

    #[test]
    fn test_cursor_visible_with_cjk_overflowing_viewport() {
        // Reproduces issue #45: 6 CJK chars × 2 cells = 12 cells overflows width 10.
        // Cursor at end (position 6) must remain visible by scrolling the viewport.
        let mut state = new_state_with("测试测试测试", 6);
        let cursor_pos = render_and_find_cursor(&mut state, 10);
        assert!(
            cursor_pos.is_some(),
            "cursor at end of CJK input must remain visible"
        );
    }

    #[test]
    fn test_cursor_visible_on_cjk_char_mid_text() {
        // Cursor highlights the 3rd CJK char ('试' at index 2, cells 4-5).
        let mut state = new_state_with("测试测试", 2);
        let cursor_pos = render_and_find_cursor(&mut state, 10);
        assert_eq!(cursor_pos, Some(4));
    }

    #[test]
    fn test_cjk_chars_truncated_at_viewport_boundary() {
        // 6 CJK chars (12 cells) overflow width 10. Only 5 wide chars fit
        // (cells 0-9), so the 6th must not appear in the output.
        let mut state = new_state_with("测试测试测试", 0);
        let line = render_to_line(&mut state, 10);
        let cjk_count = line.chars().filter(|c| char_cells(*c) == 2).count();
        assert_eq!(
            cjk_count, 5,
            "expected 5 CJK chars to fit in width 10, got {:?}",
            line
        );
    }

    #[test]
    fn test_issue_45_right_arrow_at_end_keeps_cursor_visible() {
        // Reproduces the exact steps from issue #45:
        //   1. width: 10
        //   2. value containing 6 double-width CJK chars (12 cells > 10)
        //   3. press right arrow at end
        // Cursor must remain visible.
        let mut state = new_state();
        for ch in ["测", "试", "测", "试", "测", "试"] {
            state.handle_key(ch);
        }
        state.handle_key("end");
        state.handle_key("right");

        let cursor_pos = render_and_find_cursor(&mut state, 10);
        assert!(
            cursor_pos.is_some(),
            "cursor must be visible after pressing right arrow at end of CJK input"
        );
    }

    #[test]
    fn test_viewport_scrolls_for_cjk_when_cursor_at_end() {
        // Initially cursor at end of overflowing CJK input (12 cells, width 10).
        // Viewport must scroll forward so the cursor is visible.
        let mut state = new_state_with("测试测试测试", 6);
        let _ = render_and_find_cursor(&mut state, 10);
        assert!(
            state.viewport_offset > 0,
            "viewport must scroll past first chars to keep cursor visible"
        );
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
