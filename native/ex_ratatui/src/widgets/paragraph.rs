use ratatui::buffer::Buffer;
use ratatui::layout::{Alignment, Rect};
use ratatui::style::Style;
use ratatui::text::Text;
use ratatui::widgets::{Paragraph, Widget, Wrap};

use crate::widgets::block::BlockData;

pub struct ParagraphData {
    pub text: Text<'static>,
    pub style: Style,
    pub alignment: Alignment,
    pub wrap: bool,
    pub scroll: (u16, u16),
    pub block: Option<BlockData>,
}

pub fn render(buf: &mut Buffer, data: &ParagraphData, area: Rect) {
    let mut widget = Paragraph::new(data.text.clone())
        .style(data.style)
        .alignment(data.alignment);

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
    use ratatui::style::{Color, Modifier};
    use ratatui::Terminal;

    #[test]
    fn test_render_plain_text() {
        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ParagraphData {
            text: Text::from("Hello"),
            style: Style::default(),
            alignment: Alignment::Left,
            wrap: false,
            scroll: (0, 0),
            block: None,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 3)))
            .unwrap();

        assert_eq!(buffer_line(&terminal, 0, 20), "Hello");
        assert_eq!(buffer_line(&terminal, 1, 20), "");
    }

    #[test]
    fn test_render_with_style() {
        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ParagraphData {
            text: Text::from("Styled"),
            style: Style::default()
                .fg(Color::Green)
                .add_modifier(Modifier::BOLD),
            alignment: Alignment::Left,
            wrap: false,
            scroll: (0, 0),
            block: None,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 3)))
            .unwrap();

        let buf = terminal.backend().buffer();
        let cell = buf.cell((0, 0)).unwrap();
        assert_eq!(cell.symbol(), "S");
        assert_eq!(cell.fg, Color::Green);
        assert!(cell.modifier.contains(Modifier::BOLD));
    }

    #[test]
    fn test_render_centered() {
        let backend = TestBackend::new(20, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ParagraphData {
            text: Text::from("Hi"),
            style: Style::default(),
            alignment: Alignment::Center,
            wrap: false,
            scroll: (0, 0),
            block: None,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 1)))
            .unwrap();

        // "Hi" centered in 20 chars = 9 spaces + "Hi" + 9 spaces
        let line = buffer_line(&terminal, 0, 20);
        assert!(line.contains("Hi"));
        // First char should be a space (centered)
        let buf = terminal.backend().buffer();
        assert_eq!(buf.cell((0, 0)).unwrap().symbol(), " ");
    }

    #[test]
    fn test_render_with_wrap() {
        let backend = TestBackend::new(10, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ParagraphData {
            text: Text::from("Hello world, this wraps"),
            style: Style::default(),
            alignment: Alignment::Left,
            wrap: true,
            scroll: (0, 0),
            block: None,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 10, 3)))
            .unwrap();

        // First line should have content
        let line0 = buffer_line(&terminal, 0, 10);
        assert!(!line0.is_empty());
        // Second line should also have content (wrapped)
        let line1 = buffer_line(&terminal, 1, 10);
        assert!(!line1.is_empty());
    }

    #[test]
    fn test_render_multiline() {
        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ParagraphData {
            text: Text::from("Line 1\nLine 2\nLine 3"),
            style: Style::default(),
            alignment: Alignment::Left,
            wrap: false,
            scroll: (0, 0),
            block: None,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 3)))
            .unwrap();

        assert_eq!(buffer_line(&terminal, 0, 20), "Line 1");
        assert_eq!(buffer_line(&terminal, 1, 20), "Line 2");
        assert_eq!(buffer_line(&terminal, 2, 20), "Line 3");
    }

    #[test]
    fn test_render_in_sub_area() {
        let backend = TestBackend::new(40, 10);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ParagraphData {
            text: Text::from("Offset"),
            style: Style::default(),
            alignment: Alignment::Left,
            wrap: false,
            scroll: (0, 0),
            block: None,
        };

        // Render at x=5, y=2
        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(5, 2, 20, 3)))
            .unwrap();

        let buf = terminal.backend().buffer();
        // Cell at (5, 2) should be 'O' from "Offset"
        assert_eq!(buf.cell((5, 2)).unwrap().symbol(), "O");
        // Cell at (0, 0) should be empty
        assert_eq!(buf.cell((0, 0)).unwrap().symbol(), " ");
    }

    #[test]
    fn test_render_rich_text_with_per_span_styles() {
        use ratatui::text::{Line, Span};

        let backend = TestBackend::new(20, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let text = Text::from(vec![Line::from(vec![
            Span::styled("error: ", Style::default().fg(Color::Red)),
            Span::styled("boom", Style::default().add_modifier(Modifier::BOLD)),
        ])]);

        let data = ParagraphData {
            text,
            style: Style::default(),
            alignment: Alignment::Left,
            wrap: false,
            scroll: (0, 0),
            block: None,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 1)))
            .unwrap();

        let buf = terminal.backend().buffer();
        assert_eq!(buf.cell((0, 0)).unwrap().fg, Color::Red);
        assert_eq!(buf.cell((7, 0)).unwrap().symbol(), "b");
        assert!(buf.cell((7, 0)).unwrap().modifier.contains(Modifier::BOLD));
    }
}
