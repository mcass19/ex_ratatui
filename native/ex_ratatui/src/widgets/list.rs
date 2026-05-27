use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::Text;
use ratatui::widgets::{List, ListDirection, ListItem, ListState, StatefulWidget, Widget};

use crate::widgets::block::BlockData;

pub struct ListData {
    pub items: Vec<Text<'static>>,
    pub style: Style,
    pub block: Option<BlockData>,
    pub highlight_style: Style,
    pub highlight_symbol: Option<String>,
    pub selected: Option<usize>,
    pub direction: ListDirection,
    pub scroll_padding: usize,
    pub repeat_highlight_symbol: bool,
}

impl Default for ListData {
    fn default() -> Self {
        Self {
            items: Vec::new(),
            style: Style::default(),
            block: None,
            highlight_style: Style::default(),
            highlight_symbol: None,
            selected: None,
            direction: ListDirection::TopToBottom,
            scroll_padding: 0,
            repeat_highlight_symbol: false,
        }
    }
}

pub fn render(buf: &mut Buffer, data: &ListData, area: Rect) {
    let items: Vec<ListItem> = data
        .items
        .iter()
        .map(|t| ListItem::new(t.clone()))
        .collect();

    let mut list = List::new(items)
        .style(data.style)
        .highlight_style(data.highlight_style)
        .direction(data.direction)
        .scroll_padding(data.scroll_padding)
        .repeat_highlight_symbol(data.repeat_highlight_symbol);

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

pub fn parse_list_direction(s: &str) -> Result<ListDirection, rustler::Error> {
    match s {
        "top_to_bottom" => Ok(ListDirection::TopToBottom),
        "bottom_to_top" => Ok(ListDirection::BottomToTop),
        other => Err(rustler::Error::Term(Box::new(format!(
            "unknown list direction: {other}"
        )))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use ratatui::widgets::Borders;
    use ratatui::Terminal;

    #[test]
    fn test_render_simple_list() {
        let backend = TestBackend::new(20, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ListData {
            items: vec![Text::from("Alpha"), Text::from("Beta"), Text::from("Gamma")],
            ..Default::default()
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
            items: vec![Text::from("One"), Text::from("Two"), Text::from("Three")],
            highlight_style: Style::default().fg(Color::Yellow),
            highlight_symbol: Some(">> ".to_string()),
            selected: Some(1),
            ..Default::default()
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
            items: vec![Text::from("Item 1"), Text::from("Item 2")],
            block: Some(BlockData {
                title: Some(ratatui::text::Line::from("My List")),
                borders: Borders::ALL,
                ..Default::default()
            }),
            ..Default::default()
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

    #[test]
    fn test_render_items_with_rich_text_spans() {
        use ratatui::style::Modifier;
        use ratatui::text::{Line, Span};

        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let item = Text::from(vec![Line::from(vec![
            Span::styled("error: ", Style::default().fg(Color::Red)),
            Span::styled("boom", Style::default().add_modifier(Modifier::BOLD)),
        ])]);

        let data = ListData {
            items: vec![item],
            ..Default::default()
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 3)))
            .unwrap();

        let buf = terminal.backend().buffer();
        assert_eq!(buf.cell((0, 0)).unwrap().fg, Color::Red);
        let bold_cell = buf.cell((7, 0)).unwrap();
        assert_eq!(bold_cell.symbol(), "b");
        assert!(bold_cell.modifier.contains(Modifier::BOLD));
    }

    #[test]
    fn test_render_bottom_to_top_reverses_item_order() {
        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ListData {
            items: vec![
                Text::from("first"),
                Text::from("second"),
                Text::from("third"),
            ],
            direction: ListDirection::BottomToTop,
            ..Default::default()
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 3)))
            .unwrap();

        // BottomToTop puts the first item at the bottom of the area.
        assert_eq!(buffer_line(&terminal, 2, 20), "first");
        assert_eq!(buffer_line(&terminal, 1, 20), "second");
        assert_eq!(buffer_line(&terminal, 0, 20), "third");
    }

    #[test]
    fn test_scroll_padding_keeps_selected_item_off_the_edge() {
        let backend = TestBackend::new(10, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        // 10 items, 5-row viewport. Selecting the last item with scroll_padding 2
        // should leave 2 rows of context after it (impossible at the bottom, so
        // we get whatever rows we have above) — the test just verifies the
        // builder accepts the value and renders without panicking.
        let items: Vec<Text> = (0..10).map(|i| Text::from(format!("item {i}"))).collect();

        let data = ListData {
            items,
            scroll_padding: 2,
            selected: Some(9),
            ..Default::default()
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 10, 5)))
            .unwrap();

        // Selected item ("item 9") must be inside the viewport.
        let last_line = buffer_line(&terminal, 4, 10);
        assert!(last_line.contains("item 9"));
    }

    #[test]
    fn test_repeat_highlight_symbol_on_multi_line_item() {
        use ratatui::text::Line;

        let backend = TestBackend::new(20, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let multi = Text::from(vec![Line::from("line one"), Line::from("line two")]);

        let data = ListData {
            items: vec![multi, Text::from("other")],
            highlight_symbol: Some(">> ".to_string()),
            selected: Some(0),
            repeat_highlight_symbol: true,
            ..Default::default()
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 5)))
            .unwrap();

        // Both wrapped rows of the selected item carry the highlight symbol.
        assert!(buffer_line(&terminal, 0, 20).contains(">> "));
        assert!(buffer_line(&terminal, 1, 20).contains(">> "));
    }

    #[test]
    fn test_parse_list_direction() {
        assert_eq!(
            parse_list_direction("top_to_bottom").unwrap(),
            ListDirection::TopToBottom
        );
        assert_eq!(
            parse_list_direction("bottom_to_top").unwrap(),
            ListDirection::BottomToTop
        );
        assert!(parse_list_direction("sideways").is_err());
    }
}
