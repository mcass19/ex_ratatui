use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::widgets::{Block, Widget};

use crate::rendering::{render_widget_data, WidgetData};
use crate::widgets::block::BlockData;

pub struct ScrollViewData {
    pub widget: Box<WidgetData>,
    pub content_height: u16,
    pub scroll_offset: u16,
    pub style: Style,
    pub block: Option<BlockData>,
}

pub fn render(buf: &mut Buffer, data: &ScrollViewData, area: Rect) {
    let inner_area = if let Some(ref block_data) = data.block {
        let block = block_data.to_block().style(data.style);
        let inner = block.inner(area);
        Widget::render(block, area, buf);
        inner
    } else {
        let bg = Block::default().style(data.style);
        Widget::render(bg, area, buf);
        area
    };

    // Create virtual buffer for the full content
    let content_area = Rect::new(0, 0, inner_area.width, data.content_height);
    let mut virt_buf = Buffer::empty(content_area);
    virt_buf.set_style(content_area, data.style);

    // Render child widget into virtual buffer
    render_widget_data(&mut virt_buf, &data.widget, content_area);

    // Clamp offset so we don't scroll past the end
    let offset_y = data
        .scroll_offset
        .min(data.content_height.saturating_sub(inner_area.height));
    let visible_h = inner_area
        .height
        .min(data.content_height.saturating_sub(offset_y));

    // Blit visible portion from virtual buffer to real buffer (row-wise bulk copy)
    let w = inner_area.width as usize;
    for y in 0..visible_h {
        let src_row = (offset_y + y) as usize * w;
        let dst_idx = buf.index_of(inner_area.x, inner_area.y + y);
        buf.content[dst_idx..dst_idx + w].clone_from_slice(&virt_buf.content[src_row..src_row + w]);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rendering::WidgetData;
    use crate::test_utils::helpers::buffer_line;
    use crate::widgets::paragraph::ParagraphData;
    use ratatui::backend::TestBackend;
    use ratatui::layout::Alignment;
    use ratatui::style::Style;
    use ratatui::Terminal;

    fn make_paragraph(text: &str) -> Box<WidgetData> {
        Box::new(WidgetData::Paragraph(ParagraphData {
            text: text.to_string(),
            style: Style::default(),
            alignment: Alignment::Left,
            wrap: false,
            scroll: (0, 0),
            block: None,
        }))
    }

    fn make_scroll_view(
        widget: Box<WidgetData>,
        content_height: u16,
        scroll_offset: u16,
    ) -> ScrollViewData {
        ScrollViewData {
            widget,
            content_height,
            scroll_offset,
            style: Style::default(),
            block: None,
        }
    }

    #[test]
    fn test_render_no_scroll() {
        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = make_scroll_view(make_paragraph("Hello world"), 3, 0);

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 3)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 20);
        assert!(
            line.contains("Hello world"),
            "Expected 'Hello world' in: {line}"
        );
    }

    #[test]
    fn test_render_with_scroll_offset() {
        let backend = TestBackend::new(20, 2);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = make_scroll_view(make_paragraph("Line0\nLine1\nLine2"), 3, 1);

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 2)))
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 20);
        let line1 = buffer_line(&terminal, 1, 20);
        assert!(
            line0.contains("Line1"),
            "Expected 'Line1' at row 0: {line0}"
        );
        assert!(
            line1.contains("Line2"),
            "Expected 'Line2' at row 1: {line1}"
        );
    }

    #[test]
    fn test_scroll_offset_clamped() {
        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        // content_height=4, viewport=3, max offset=1, but we pass 100
        let data = make_scroll_view(make_paragraph("A\nB\nC\nD"), 4, 100);

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 3)))
            .unwrap();

        // Should clamp to offset 1, showing B, C, D
        let line0 = buffer_line(&terminal, 0, 20);
        assert!(
            line0.contains("B"),
            "Expected 'B' at row 0 after clamp: {line0}"
        );
    }

    #[test]
    fn test_content_smaller_than_viewport() {
        let backend = TestBackend::new(20, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = make_scroll_view(make_paragraph("Short"), 2, 0);

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 5)))
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 20);
        assert!(line0.contains("Short"), "Expected 'Short' in: {line0}");
    }

    #[test]
    fn test_render_with_block() {
        let backend = TestBackend::new(20, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ScrollViewData {
            widget: make_paragraph("Inside block"),
            content_height: 3,
            scroll_offset: 0,
            style: Style::default(),
            block: Some(BlockData {
                title: Some("Title".to_string()),
                borders: ratatui::widgets::Borders::ALL,
                border_type: ratatui::widgets::BorderType::Rounded,
                border_style: Style::default(),
                style: Style::default(),
                padding: ratatui::widgets::Padding::ZERO,
            }),
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 5)))
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 20);
        assert!(
            line0.contains("Title"),
            "Expected 'Title' in border: {line0}"
        );

        let line1 = buffer_line(&terminal, 1, 20);
        assert!(
            line1.contains("Inside block"),
            "Expected content in: {line1}"
        );
    }

    #[test]
    fn test_zero_content_height() {
        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = make_scroll_view(make_paragraph(""), 0, 0);

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 3)))
            .unwrap();
        // Should not panic
    }
}
