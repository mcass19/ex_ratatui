use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::Paragraph;
use ratatui::Frame;

use crate::widgets::block::BlockData;

pub struct CheckboxData {
    pub label: String,
    pub checked: bool,
    pub style: Style,
    pub checked_style: Style,
    pub checked_symbol: Option<String>,
    pub unchecked_symbol: Option<String>,
    pub block: Option<BlockData>,
}

pub fn render(frame: &mut Frame, data: &CheckboxData, area: Rect) {
    let symbol = if data.checked {
        data.checked_symbol.as_deref().unwrap_or("[x]")
    } else {
        data.unchecked_symbol.as_deref().unwrap_or("[ ]")
    };

    let line = Line::from(vec![
        Span::styled(format!("{symbol} "), data.checked_style),
        Span::styled(data.label.clone(), data.style),
    ]);

    let mut paragraph = Paragraph::new(line);

    if let Some(ref block_data) = data.block {
        paragraph = paragraph.block(block_data.to_block());
    }

    frame.render_widget(paragraph, area);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use ratatui::Terminal;

    #[test]
    fn test_render_checkbox_checked() {
        let backend = TestBackend::new(30, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = CheckboxData {
            label: "Enable feature".into(),
            checked: true,
            style: Style::default(),
            checked_style: Style::default().fg(Color::Green),
            checked_symbol: None,
            unchecked_symbol: None,
            block: None,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 30, 1)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 30);
        assert!(line.contains("[x]"));
        assert!(line.contains("Enable feature"));
    }

    #[test]
    fn test_render_checkbox_unchecked() {
        let backend = TestBackend::new(30, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = CheckboxData {
            label: "Disabled option".into(),
            checked: false,
            style: Style::default(),
            checked_style: Style::default(),
            checked_symbol: None,
            unchecked_symbol: None,
            block: None,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 30, 1)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 30);
        assert!(line.contains("[ ]"));
        assert!(line.contains("Disabled option"));
    }

    #[test]
    fn test_render_checkbox_custom_symbols() {
        let backend = TestBackend::new(30, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = CheckboxData {
            label: "Custom".into(),
            checked: true,
            style: Style::default(),
            checked_style: Style::default(),
            checked_symbol: Some("✓".into()),
            unchecked_symbol: Some("✗".into()),
            block: None,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 30, 1)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 30);
        assert!(line.contains("✓"));
        assert!(line.contains("Custom"));
    }

    #[test]
    fn test_render_checkbox_unchecked_custom_symbol() {
        let backend = TestBackend::new(30, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = CheckboxData {
            label: "Off".into(),
            checked: false,
            style: Style::default(),
            checked_style: Style::default(),
            checked_symbol: Some("✓".into()),
            unchecked_symbol: Some("✗".into()),
            block: None,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 30, 1)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 30);
        assert!(line.contains("✗"));
    }
}
