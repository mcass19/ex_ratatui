use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::widgets::Widget;

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
    pub style: Style,
}

pub fn render(buf: &mut Buffer, data: &WidgetListData, area: Rect) {
    // Render block and get inner area
    let inner_area = if let Some(ref block_data) = data.block {
        let block = block_data.to_block();
        let inner = block.inner(area);
        Widget::render(block, area, buf);
        inner
    } else {
        area
    };

    // Apply base style to the inner area
    let style_block = ratatui::widgets::Block::default().style(data.style);
    Widget::render(style_block, inner_area, buf);

    // Clamp scroll_offset to total content height
    let total_content: usize = data.items.iter().map(|item| item.height as usize).sum();
    let viewport_start = data.scroll_offset.min(total_content);
    let viewport_end = viewport_start + inner_area.height as usize;
    let mut item_bottom: usize = 0;

    for (idx, item) in data.items.iter().enumerate() {
        let item_top = item_bottom;
        item_bottom += item.height as usize;

        if item_bottom < viewport_start {
            continue;
        }
        if item_top >= viewport_end {
            break;
        }

        // Intersect item row range with viewport
        let top_clip = viewport_start.saturating_sub(item_top) as u16;
        let screen_y = item_top.saturating_sub(viewport_start) as u16;
        let visible_h = (item.height - top_clip).min(inner_area.height - screen_y);
        let dst = Rect::new(
            inner_area.x,
            inner_area.y + screen_y,
            inner_area.width,
            visible_h,
        );

        // If selected, fill background with highlight style
        if data.selected == Some(idx) {
            let highlight_block = ratatui::widgets::Block::default().style(data.highlight_style);
            Widget::render(highlight_block, dst, buf);
        }

        if top_clip > 0 {
            // Item partially above viewport: render full item to temp buffer, blit visible rows
            let full = Rect::new(0, 0, inner_area.width, item.height);
            let mut tmp = Buffer::empty(full);
            tmp.set_style(full, data.style);
            render_widget_data(&mut tmp, &item.widget, full);
            blit_rows(&tmp, top_clip, buf, dst);
        } else {
            render_widget_data(buf, &item.widget, dst);
        }
    }
}

/// Copy rows from `src` starting at `src_y` into `dst` at `dst_rect`.
fn blit_rows(src: &Buffer, src_y: u16, dst: &mut Buffer, dst_rect: Rect) {
    let w = dst_rect.width as usize;
    for row in 0..dst_rect.height {
        let si = (src_y + row) as usize * w;
        let di = dst.index_of(dst_rect.x, dst_rect.y + row);
        dst.content[di..di + w].clone_from_slice(&src.content[si..si + w]);
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
            text: ratatui::text::Text::from(text.to_string()),
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
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 5)))
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
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 5)))
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

        let mut data = WidgetListData {
            items: vec![
                WidgetListItem {
                    widget: make_paragraph("Line 1\nLine 2\nLine 3"),
                    height: 3,
                },
                WidgetListItem {
                    widget: make_paragraph("Line 4\nLine 5"),
                    height: 2,
                },
            ],
            selected: None,
            highlight_style: Style::default(),
            scroll_offset: 0,
            block: None,
            style: Style::default(),
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 3)))
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 30);
        let line1 = buffer_line(&terminal, 1, 30);
        let line2 = buffer_line(&terminal, 2, 30);
        assert!(
            line0.contains("Line 1"),
            "Expected 'Line 1' at row 0: {line0}"
        );
        assert!(
            line1.contains("Line 2"),
            "Expected 'Line 2' at row 1: {line1}"
        );
        assert!(
            line2.contains("Line 3"),
            "Expected 'Line 3' at row 2: {line2}"
        );

        data.scroll_offset = 1;
        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 3)))
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 30);
        let line1 = buffer_line(&terminal, 1, 30);
        let line2 = buffer_line(&terminal, 2, 30);
        assert!(
            line0.contains("Line 2"),
            "Expected 'Line 2' at row 0: {line0}"
        );
        assert!(
            line1.contains("Line 3"),
            "Expected 'Line 3' at row 1: {line1}"
        );
        assert!(
            line2.contains("Line 4"),
            "Expected 'Line 4' at row 2: {line2}"
        );

        data.scroll_offset = 2;
        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 3)))
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 30);
        let line1 = buffer_line(&terminal, 1, 30);
        let line2 = buffer_line(&terminal, 2, 30);
        assert!(
            line0.contains("Line 3"),
            "Expected 'Line 3' at row 0: {line0}"
        );
        assert!(
            line1.contains("Line 4"),
            "Expected 'Line 4' at row 1: {line1}"
        );
        assert!(
            line2.contains("Line 5"),
            "Expected 'Line 5' at row 2: {line2}"
        );

        data.scroll_offset = 3;
        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 3)))
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 30);
        let line1 = buffer_line(&terminal, 1, 30);
        let line2 = buffer_line(&terminal, 2, 30);
        assert!(
            line0.contains("Line 4"),
            "Expected 'Line 4' at row 0: {line0}"
        );
        assert!(
            line1.contains("Line 5"),
            "Expected 'Line 5' at row 1: {line1}"
        );
        assert!(line2.contains(""), "Expected empty at row 2: {line2}");

        data.scroll_offset = 4;
        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 3)))
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 30);
        let line1 = buffer_line(&terminal, 1, 30);
        let line2 = buffer_line(&terminal, 2, 30);
        assert!(
            line0.contains("Line 5"),
            "Expected 'Line 5' at row 0: {line0}"
        );
        assert!(line1.contains(""), "Expected empty at row 1: {line1}");
        assert!(line2.contains(""), "Expected empty at row 2: {line2}");

        data.scroll_offset = 5;
        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 3)))
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 30);
        let line1 = buffer_line(&terminal, 1, 30);
        let line2 = buffer_line(&terminal, 2, 30);
        assert!(line0.contains(""), "Expected empty at row 0: {line0}");
        assert!(line1.contains(""), "Expected empty at row 1: {line1}");
        assert!(line2.contains(""), "Expected empty at row 2: {line2}");
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
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 5)))
            .unwrap();
        // Should not panic
    }
}
