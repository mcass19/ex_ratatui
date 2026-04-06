use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::widgets::{List, ListItem, ListState, StatefulWidget, Widget};

use crate::widgets::block::BlockData;

pub struct ListData {
    pub items: Vec<String>,
    pub style: Style,
    pub block: Option<BlockData>,
    pub highlight_style: Style,
    pub highlight_symbol: Option<String>,
    pub selected: Option<usize>,
}

pub fn render(buf: &mut Buffer, data: &ListData, area: Rect) {
    let items: Vec<ListItem> = data
        .items
        .iter()
        .map(|s| ListItem::new(s.as_str()))
        .collect();

    let mut list = List::new(items)
        .style(data.style)
        .highlight_style(data.highlight_style);

    if let Some(ref sym) = data.highlight_symbol {
        list = list.highlight_symbol(sym.as_str());
    }

    if let Some(ref block_data) = data.block {
        list = list.block(block_data.to_block());
    }

    if let Some(selected) = data.selected {
        let mut state = ListState::default();
        state.select(Some(selected));
        StatefulWidget::render(list, area, buf, &mut state);
    } else {
        Widget::render(list, area, buf);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use ratatui::widgets::{BorderType, Borders, Padding};
    use ratatui::Terminal;

    #[test]
    fn test_render_simple_list() {
        let backend = TestBackend::new(20, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ListData {
            items: vec!["Alpha".into(), "Beta".into(), "Gamma".into()],
            style: Style::default(),
            block: None,
            highlight_style: Style::default(),
            highlight_symbol: None,
            selected: None,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 5)))
            .unwrap();

        assert_eq!(buffer_line(&terminal, 0, 20), "Alpha");
        assert_eq!(buffer_line(&terminal, 1, 20), "Beta");
        assert_eq!(buffer_line(&terminal, 2, 20), "Gamma");
    }

    #[test]
    fn test_render_list_with_selection() {
        let backend = TestBackend::new(20, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ListData {
            items: vec!["One".into(), "Two".into(), "Three".into()],
            style: Style::default(),
            block: None,
            highlight_style: Style::default().fg(Color::Yellow),
            highlight_symbol: Some(">> ".to_string()),
            selected: Some(1),
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 5)))
            .unwrap();

        // Selected item (index 1 = "Two") should have highlight symbol
        let line = buffer_line(&terminal, 1, 20);
        assert!(line.contains("Two"));
        assert!(line.contains(">>"));

        // Selected item should have highlight color
        let buf = terminal.backend().buffer();
        // Find the 'T' in 'Two' — it's after ">> "
        let t_cell = buf.cell((3, 1)).unwrap();
        assert_eq!(t_cell.fg, Color::Yellow);
    }

    #[test]
    fn test_render_list_with_block() {
        let backend = TestBackend::new(20, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ListData {
            items: vec!["Item 1".into(), "Item 2".into()],
            style: Style::default(),
            block: Some(BlockData {
                title: Some("My List".to_string()),
                borders: Borders::ALL,
                border_style: Style::default(),
                border_type: BorderType::Plain,
                style: Style::default(),
                padding: Padding::ZERO,
            }),
            highlight_style: Style::default(),
            highlight_symbol: None,
            selected: None,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 5)))
            .unwrap();

        // Top border should contain title
        let top = buffer_line(&terminal, 0, 20);
        assert!(top.contains("My List"));

        // Items should be inside the border (row 1, 2)
        let line1 = buffer_line(&terminal, 1, 20);
        assert!(line1.contains("Item 1"));
    }
}
