use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::Line;
use ratatui::widgets::{Tabs, Widget};

use crate::widgets::block::BlockData;

pub struct TabsData {
    pub titles: Vec<Line<'static>>,
    pub selected: Option<usize>,
    pub style: Style,
    pub highlight_style: Style,
    pub divider: Option<String>,
    pub block: Option<BlockData>,
    pub padding_left: u16,
    pub padding_right: u16,
}

pub fn render(buf: &mut Buffer, data: &TabsData, area: Rect) {
    let left = " ".repeat(data.padding_left as usize);
    let right = " ".repeat(data.padding_right as usize);

    let mut tabs = Tabs::new(data.titles.clone())
        .style(data.style)
        .highlight_style(data.highlight_style)
        .padding(left, right);

    if let Some(selected) = data.selected {
        tabs = tabs.select(selected);
    }

    if let Some(ref divider) = data.divider {
        tabs = tabs.divider(divider.as_str());
    }

    if let Some(ref block_data) = data.block {
        tabs = tabs.block(block_data.to_block());
    }

    tabs.render(area, buf);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use ratatui::Terminal;

    #[test]
    fn test_render_tabs_basic() {
        let backend = TestBackend::new(40, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = TabsData {
            titles: vec![Line::from("Tab1"), Line::from("Tab2"), Line::from("Tab3")],
            selected: Some(0),
            style: Style::default(),
            highlight_style: Style::default().fg(Color::Yellow),
            divider: None,
            block: None,
            padding_left: 1,
            padding_right: 1,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 40, 3)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("Tab1"));
        assert!(line.contains("Tab2"));
        assert!(line.contains("Tab3"));
    }

    #[test]
    fn test_render_tabs_with_divider() {
        let backend = TestBackend::new(40, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = TabsData {
            titles: vec![Line::from("A"), Line::from("B")],
            selected: None,
            style: Style::default(),
            highlight_style: Style::default(),
            divider: Some(" | ".into()),
            block: None,
            padding_left: 1,
            padding_right: 1,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 40, 1)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("|"));
    }

    #[test]
    fn test_render_tabs_no_selection() {
        let backend = TestBackend::new(30, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = TabsData {
            titles: vec![Line::from("One"), Line::from("Two")],
            selected: None,
            style: Style::default(),
            highlight_style: Style::default(),
            divider: None,
            block: None,
            padding_left: 1,
            padding_right: 1,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 1)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 30);
        assert!(line.contains("One"));
    }

    #[test]
    fn test_render_titles_with_rich_text_spans() {
        use ratatui::style::Modifier;
        use ratatui::text::Span;

        let backend = TestBackend::new(40, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = TabsData {
            titles: vec![
                Line::from(vec![
                    Span::styled("[", Style::default().fg(Color::Red)),
                    Span::styled(
                        "H",
                        Style::default()
                            .fg(Color::Yellow)
                            .add_modifier(Modifier::BOLD),
                    ),
                    Span::styled("ome]", Style::default().fg(Color::Red)),
                ]),
                Line::from("Docs"),
            ],
            selected: Some(0),
            style: Style::default(),
            highlight_style: Style::default(),
            divider: None,
            block: None,
            padding_left: 1,
            padding_right: 1,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 40, 1)))
            .unwrap();

        let buf = terminal.backend().buffer();
        // First title starts at col 1 (padding_left = 1)
        assert_eq!(buf.cell((1, 0)).unwrap().symbol(), "[");
        assert_eq!(buf.cell((1, 0)).unwrap().fg, Color::Red);
        let h_cell = buf.cell((2, 0)).unwrap();
        assert_eq!(h_cell.symbol(), "H");
        assert_eq!(h_cell.fg, Color::Yellow);
        assert!(h_cell.modifier.contains(Modifier::BOLD));
    }
}
