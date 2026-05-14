use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::Text;
use ratatui::widgets::{Paragraph, Widget, Wrap};

use crate::widgets::block::BlockData;
use crate::widgets::highlighter;

pub struct CodeBlockData {
    pub content: String,
    pub language: Option<String>,
    pub theme: String,
    pub style: Style,
    pub block: Option<BlockData>,
    pub scroll: (u16, u16),
    pub wrap: bool,
}

pub fn render(buf: &mut Buffer, data: &CodeBlockData, area: Rect) {
    let lines = highlighter::lines_for(&data.content, data.language.as_deref(), &data.theme);

    let mut widget = Paragraph::new(Text::from(lines)).style(data.style);

    if data.wrap {
        widget = widget.wrap(Wrap { trim: false });
    }

    if data.scroll != (0, 0) {
        widget = widget.scroll(data.scroll);
    }

    if let Some(ref block_data) = data.block {
        widget = widget.block(block_data.to_block());
    }

    widget.render(area, buf);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    fn make(content: &str, language: Option<&str>) -> CodeBlockData {
        CodeBlockData {
            content: content.to_string(),
            language: language.map(String::from),
            theme: "base16-ocean.dark".to_string(),
            style: Style::default(),
            block: None,
            scroll: (0, 0),
            wrap: false,
        }
    }

    #[test]
    fn renders_plain_when_language_nil() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make("hello world", None);
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();
        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("hello world"), "got: {line}");
    }

    #[test]
    fn renders_elixir_source_text() {
        let backend = TestBackend::new(60, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make("defmodule X do end", Some("elixir"));
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 60, 5)))
            .unwrap();
        let line = buffer_line(&terminal, 0, 60);
        assert!(line.contains("defmodule"), "got: {line}");
    }

    #[test]
    fn elixir_produces_distinct_colors() {
        let backend = TestBackend::new(60, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make("defmodule X do\n  def hi, do: :ok\nend", Some("elixir"));
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 60, 5)))
            .unwrap();

        let buffer = terminal.backend().buffer();
        let mut colors = std::collections::HashSet::new();
        for y in 0..3 {
            for x in 0..60 {
                if let Some(cell) = buffer.cell((x, y)) {
                    colors.insert(format!("{:?}", cell.fg));
                }
            }
        }
        assert!(colors.len() >= 2, "expected >=2 fg colors, got {colors:?}");
    }

    #[test]
    fn unknown_language_falls_back_to_plain() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make("anything goes", Some("not-a-language"));
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();
        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("anything goes"), "got: {line}");
    }

    #[test]
    fn renders_with_block() {
        let backend = TestBackend::new(40, 10);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = CodeBlockData {
            block: Some(BlockData {
                title: Some(ratatui::text::Line::from("code")),
                borders: ratatui::widgets::Borders::ALL,
                border_type: ratatui::widgets::BorderType::Rounded,
                border_style: Style::default(),
                style: Style::default(),
                padding: ratatui::widgets::Padding::ZERO,
            }),
            ..make("x = 1", Some("elixir"))
        };
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 40, 10)))
            .unwrap();
        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("code"), "got: {line}");
    }

    #[test]
    fn unknown_theme_falls_back_silently() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut data = make("x", Some("elixir"));
        data.theme = "not-a-theme".to_string();
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();
        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("x"), "got: {line}");
    }

    #[test]
    fn wrap_and_scroll_apply() {
        let backend = TestBackend::new(20, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = CodeBlockData {
            scroll: (1, 0),
            wrap: true,
            ..make("aaaaaaaaaa\nbbbbb\nccccc", None)
        };
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 20, 5)))
            .unwrap();
        // After scrolling 1 line down, line "bbbbb" should be at top
        let line = buffer_line(&terminal, 0, 20);
        assert!(line.contains("bbbbb"), "got: {line}");
    }
}
