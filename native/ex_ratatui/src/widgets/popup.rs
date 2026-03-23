use ratatui::layout::Rect;
use ratatui::widgets::Clear;
use ratatui::Frame;

use crate::rendering::{render_widget_data, WidgetData};
use crate::widgets::block::BlockData;

pub struct PopupData {
    pub content: Box<WidgetData>,
    pub block: Option<BlockData>,
    pub percent_width: u16,
    pub percent_height: u16,
    pub fixed_width: Option<u16>,
    pub fixed_height: Option<u16>,
}

fn centered_rect(area: Rect, data: &PopupData) -> Rect {
    let width = data
        .fixed_width
        .unwrap_or_else(|| area.width * data.percent_width / 100)
        .min(area.width);
    let height = data
        .fixed_height
        .unwrap_or_else(|| area.height * data.percent_height / 100)
        .min(area.height);
    let x = area.x + (area.width.saturating_sub(width)) / 2;
    let y = area.y + (area.height.saturating_sub(height)) / 2;
    Rect::new(x, y, width, height)
}

pub fn render(frame: &mut Frame, data: &PopupData, area: Rect) {
    let popup_area = centered_rect(area, data);

    // Clear the background under the popup
    frame.render_widget(Clear, popup_area);

    // Render the block border and get the inner area for content
    let content_area = if let Some(ref block_data) = data.block {
        let block = block_data.to_block();
        let inner = block.inner(popup_area);
        frame.render_widget(block, popup_area);
        inner
    } else {
        popup_area
    };

    // Render the inner content widget
    render_widget_data(frame, &data.content, content_area);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use crate::widgets::block::BlockData;
    use crate::widgets::paragraph::ParagraphData;
    use ratatui::backend::TestBackend;
    use ratatui::style::Style;
    use ratatui::widgets::{BorderType, Borders, Padding};
    use ratatui::Terminal;

    fn make_paragraph_content(text: &str) -> Box<WidgetData> {
        Box::new(WidgetData::Paragraph(ParagraphData {
            text: text.to_string(),
            style: Style::default(),
            alignment: ratatui::layout::Alignment::Left,
            wrap: false,
            scroll: (0, 0),
            block: None,
        }))
    }

    fn make_block(title: &str) -> BlockData {
        BlockData {
            title: Some(title.to_string()),
            borders: Borders::ALL,
            border_type: BorderType::Rounded,
            border_style: Style::default(),
            style: Style::default(),
            padding: Padding::zero(),
        }
    }

    #[test]
    fn test_centered_rect_percentage() {
        let area = Rect::new(0, 0, 100, 50);
        let data = PopupData {
            content: make_paragraph_content(""),
            block: None,
            percent_width: 60,
            percent_height: 60,
            fixed_width: None,
            fixed_height: None,
        };
        let result = centered_rect(area, &data);
        assert_eq!(result.width, 60);
        assert_eq!(result.height, 30);
        assert_eq!(result.x, 20);
        assert_eq!(result.y, 10);
    }

    #[test]
    fn test_centered_rect_fixed() {
        let area = Rect::new(0, 0, 100, 50);
        let data = PopupData {
            content: make_paragraph_content(""),
            block: None,
            percent_width: 60,
            percent_height: 60,
            fixed_width: Some(30),
            fixed_height: Some(10),
        };
        let result = centered_rect(area, &data);
        assert_eq!(result.width, 30);
        assert_eq!(result.height, 10);
        assert_eq!(result.x, 35);
        assert_eq!(result.y, 20);
    }

    #[test]
    fn test_centered_rect_fixed_overrides_percent() {
        let area = Rect::new(0, 0, 80, 40);
        let data = PopupData {
            content: make_paragraph_content(""),
            block: None,
            percent_width: 50,
            percent_height: 50,
            fixed_width: Some(20),
            fixed_height: Some(10),
        };
        let result = centered_rect(area, &data);
        assert_eq!(result.width, 20);
        assert_eq!(result.height, 10);
    }

    #[test]
    fn test_centered_rect_clamps_to_area() {
        let area = Rect::new(0, 0, 20, 10);
        let data = PopupData {
            content: make_paragraph_content(""),
            block: None,
            percent_width: 60,
            percent_height: 60,
            fixed_width: Some(100),
            fixed_height: Some(50),
        };
        let result = centered_rect(area, &data);
        assert_eq!(result.width, 20);
        assert_eq!(result.height, 10);
    }

    #[test]
    fn test_centered_rect_small_area() {
        let area = Rect::new(0, 0, 1, 1);
        let data = PopupData {
            content: make_paragraph_content(""),
            block: None,
            percent_width: 60,
            percent_height: 60,
            fixed_width: None,
            fixed_height: None,
        };
        let result = centered_rect(area, &data);
        assert!(result.width <= 1);
        assert!(result.height <= 1);
    }

    #[test]
    fn test_render_popup_clears_background() {
        let backend = TestBackend::new(40, 10);
        let mut terminal = Terminal::new(backend).unwrap();

        // First draw background text
        terminal
            .draw(|frame| {
                use ratatui::widgets::Paragraph;
                let bg = Paragraph::new("XXXXXXXXXX".repeat(4));
                frame.render_widget(bg, Rect::new(0, 0, 40, 10));
            })
            .unwrap();

        // Then draw popup over it
        let data = PopupData {
            content: make_paragraph_content("Hello"),
            block: None,
            percent_width: 50,
            percent_height: 50,
            fixed_width: None,
            fixed_height: None,
        };

        terminal
            .draw(|frame| {
                render(frame, &data, Rect::new(0, 0, 40, 10));
            })
            .unwrap();

        // Center area should contain our content, not the background
        let mid_line = buffer_line(&terminal, 2, 40);
        assert!(
            mid_line.contains("Hello"),
            "Expected 'Hello' in: {mid_line}"
        );
    }

    #[test]
    fn test_render_popup_with_paragraph_content() {
        let backend = TestBackend::new(40, 10);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = PopupData {
            content: make_paragraph_content("Popup text here"),
            block: None,
            percent_width: 80,
            percent_height: 80,
            fixed_width: None,
            fixed_height: None,
        };

        terminal
            .draw(|frame| {
                render(frame, &data, Rect::new(0, 0, 40, 10));
            })
            .unwrap();

        // Check all lines for our text
        let mut found = false;
        for y in 0..10 {
            let line = buffer_line(&terminal, y, 40);
            if line.contains("Popup text here") {
                found = true;
                break;
            }
        }
        assert!(found, "Expected 'Popup text here' somewhere in the popup");
    }

    #[test]
    fn test_render_popup_with_block() {
        let backend = TestBackend::new(40, 10);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = PopupData {
            content: make_paragraph_content("Inner"),
            block: Some(make_block("Dialog")),
            percent_width: 80,
            percent_height: 80,
            fixed_width: None,
            fixed_height: None,
        };

        terminal
            .draw(|frame| {
                render(frame, &data, Rect::new(0, 0, 40, 10));
            })
            .unwrap();

        let mut found_title = false;
        for y in 0..10 {
            let line = buffer_line(&terminal, y, 40);
            if line.contains("Dialog") {
                found_title = true;
                break;
            }
        }
        assert!(found_title, "Expected 'Dialog' title in the popup");
    }
}
