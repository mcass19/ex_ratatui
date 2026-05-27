use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::widgets::{Paragraph, Widget, Wrap};

use crate::widgets::block::BlockData;

pub struct MarkdownData {
    pub content: String,
    pub style: Style,
    pub block: Option<BlockData>,
    pub scroll: (u16, u16),
    pub wrap: bool,
}

pub fn render(buf: &mut Buffer, data: &MarkdownData, area: Rect) {
    let text = tui_markdown::from_str(&data.content);

    let mut widget = Paragraph::new(text).style(data.style);

    if data.wrap {
        widget = widget.wrap(Wrap { trim: true });
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

    fn make_data(content: &str) -> MarkdownData {
        MarkdownData {
            content: content.to_string(),
            style: Style::default(),
            block: None,
            scroll: (0, 0),
            wrap: true,
        }
    }

    #[test]
    fn test_render_plain_text() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make_data("Hello world");

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 40);
        assert!(
            line.contains("Hello world"),
            "Expected 'Hello world' in: {line}"
        );
    }

    #[test]
    fn test_render_heading() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make_data("# Title");

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("Title"), "Expected 'Title' in: {line}");
    }

    #[test]
    fn test_render_bold() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make_data("**bold text**");

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 40);
        assert!(
            line.contains("bold text"),
            "Expected 'bold text' in: {line}"
        );
    }

    #[test]
    fn test_render_inline_code() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make_data("use `code` here");

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("code"), "Expected 'code' in: {line}");
    }

    #[test]
    fn test_render_code_block() {
        let backend = TestBackend::new(40, 10);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make_data("```\nfn main() {}\n```");

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 40, 10)))
            .unwrap();

        let mut found = false;
        for y in 0..10 {
            let line = buffer_line(&terminal, y, 40);
            if line.contains("fn main") {
                found = true;
                break;
            }
        }
        assert!(found, "Expected 'fn main' somewhere in rendered code block");
    }

    #[test]
    fn test_render_bullet_list() {
        let backend = TestBackend::new(40, 10);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make_data("- item1\n- item2");

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 40, 10)))
            .unwrap();

        let mut found1 = false;
        let mut found2 = false;
        for y in 0..10 {
            let line = buffer_line(&terminal, y, 40);
            if line.contains("item1") {
                found1 = true;
            }
            if line.contains("item2") {
                found2 = true;
            }
        }
        assert!(found1, "Expected 'item1' in rendered list");
        assert!(found2, "Expected 'item2' in rendered list");
    }

    #[test]
    fn test_render_empty_content() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make_data("");

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();
        // Should not panic
    }

    #[test]
    fn test_render_with_block() {
        let backend = TestBackend::new(40, 10);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = MarkdownData {
            content: "Some markdown".to_string(),
            style: Style::default(),
            block: Some(BlockData {
                title: Some(ratatui::text::Line::from("Response")),
                borders: ratatui::widgets::Borders::ALL,
                border_type: ratatui::widgets::BorderType::Rounded,
                ..Default::default()
            }),
            scroll: (0, 0),
            wrap: true,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 40, 10)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("Response"), "Expected 'Response' in: {line}");
    }

    #[test]
    fn test_render_mixed_markdown() {
        let backend = TestBackend::new(60, 15);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make_data("# Heading\n\nSome **bold** and *italic* text.\n\n- bullet1\n- bullet2\n\n`inline code`");

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 60, 15)))
            .unwrap();

        let mut found_heading = false;
        let mut found_bold = false;
        for y in 0..15 {
            let line = buffer_line(&terminal, y, 60);
            if line.contains("Heading") {
                found_heading = true;
            }
            if line.contains("bold") {
                found_bold = true;
            }
        }
        assert!(found_heading, "Expected 'Heading' in rendered markdown");
        assert!(found_bold, "Expected 'bold' in rendered markdown");
    }
}
