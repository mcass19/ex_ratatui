use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::Frame;

use crate::rendering::{render_widget_data, WidgetData};
use crate::widgets::block::BlockData;

pub struct WidgetListItem {
    pub widget: WidgetData,
    pub height: u16,
}

pub struct WidgetListData {
    pub items: Vec<WidgetListItem>,
    pub selected: Option<usize>,
    pub highlight_style: Style,
    pub scroll_offset: usize,
    pub block: Option<BlockData>,
    #[allow(dead_code)]
    pub style: Style,
}

pub fn render(frame: &mut Frame, data: &WidgetListData, area: Rect) {
    // Render block and get inner area
    let inner_area = if let Some(ref block_data) = data.block {
        let block = block_data.to_block();
        let inner = block.inner(area);
        frame.render_widget(block, area);
        inner
    } else {
        area
    };

    // Render items vertically starting from scroll_offset
    let mut y = inner_area.y;
    let max_y = inner_area.y + inner_area.height;

    for (idx, item) in data.items.iter().enumerate().skip(data.scroll_offset) {
        if y >= max_y {
            break;
        }

        let item_height = item.height.min(max_y - y);
        let item_area = Rect::new(inner_area.x, y, inner_area.width, item_height);

        // If selected, fill background with highlight style
        if data.selected == Some(idx) {
            let highlight_block = ratatui::widgets::Block::default().style(data.highlight_style);
            frame.render_widget(highlight_block, item_area);
        }

        render_widget_data(frame, &item.widget, item_area);

        y += item.height;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use crate::widgets::paragraph::ParagraphData;
    use ratatui::backend::TestBackend;
    use ratatui::layout::Alignment;
    use ratatui::Terminal;

    fn make_paragraph(text: &str) -> WidgetData {
        WidgetData::Paragraph(ParagraphData {
            text: text.to_string(),
            style: Style::default(),
            alignment: Alignment::Left,
            wrap: false,
            scroll: (0, 0),
            block: None,
        })
    }

    #[test]
    fn test_render_single_item() {
        let backend = TestBackend::new(30, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = WidgetListData {
            items: vec![WidgetListItem {
                widget: make_paragraph("Hello"),
                height: 1,
            }],
            selected: None,
            highlight_style: Style::default(),
            scroll_offset: 0,
            block: None,
            style: Style::default(),
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 30, 5)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 30);
        assert!(line.contains("Hello"), "Expected 'Hello' in: {line}");
    }

    #[test]
    fn test_render_multiple_items() {
        let backend = TestBackend::new(30, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = WidgetListData {
            items: vec![
                WidgetListItem {
                    widget: make_paragraph("Item 1"),
                    height: 1,
                },
                WidgetListItem {
                    widget: make_paragraph("Item 2"),
                    height: 1,
                },
                WidgetListItem {
                    widget: make_paragraph("Item 3"),
                    height: 1,
                },
            ],
            selected: None,
            highlight_style: Style::default(),
            scroll_offset: 0,
            block: None,
            style: Style::default(),
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 30, 5)))
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 30);
        let line1 = buffer_line(&terminal, 1, 30);
        let line2 = buffer_line(&terminal, 2, 30);
        assert!(line0.contains("Item 1"));
        assert!(line1.contains("Item 2"));
        assert!(line2.contains("Item 3"));
    }

    #[test]
    fn test_render_with_scroll() {
        let backend = TestBackend::new(30, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = WidgetListData {
            items: vec![
                WidgetListItem {
                    widget: make_paragraph("First"),
                    height: 1,
                },
                WidgetListItem {
                    widget: make_paragraph("Second"),
                    height: 1,
                },
                WidgetListItem {
                    widget: make_paragraph("Third"),
                    height: 1,
                },
            ],
            selected: None,
            highlight_style: Style::default(),
            scroll_offset: 1,
            block: None,
            style: Style::default(),
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 30, 3)))
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 30);
        assert!(
            line0.contains("Second"),
            "Expected 'Second' at top after scroll: {line0}"
        );
    }

    #[test]
    fn test_render_empty_list() {
        let backend = TestBackend::new(30, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = WidgetListData {
            items: vec![],
            selected: None,
            highlight_style: Style::default(),
            scroll_offset: 0,
            block: None,
            style: Style::default(),
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 30, 5)))
            .unwrap();
        // Should not panic
    }
}
