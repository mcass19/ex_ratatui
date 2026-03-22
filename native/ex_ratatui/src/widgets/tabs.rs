use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::widgets::Tabs;
use ratatui::Frame;

use crate::widgets::block::BlockData;

pub struct TabsData {
    pub titles: Vec<String>,
    pub selected: Option<usize>,
    pub style: Style,
    pub highlight_style: Style,
    pub divider: Option<String>,
    pub block: Option<BlockData>,
    pub padding_left: u16,
    pub padding_right: u16,
}

pub fn render(frame: &mut Frame, data: &TabsData, area: Rect) {
    let mut tabs = Tabs::new(data.titles.clone())
        .style(data.style)
        .highlight_style(data.highlight_style)
        .padding(" ", " ");

    if data.padding_left > 0 || data.padding_right > 0 {
        let left = " ".repeat(data.padding_left as usize);
        let right = " ".repeat(data.padding_right as usize);
        tabs = tabs.padding(left, right);
    }

    if let Some(selected) = data.selected {
        tabs = tabs.select(selected);
    }

    if let Some(ref divider) = data.divider {
        tabs = tabs.divider(divider.as_str());
    }

    if let Some(ref block_data) = data.block {
        tabs = tabs.block(block_data.to_block());
    }

    frame.render_widget(tabs, area);
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
            titles: vec!["Tab1".into(), "Tab2".into(), "Tab3".into()],
            selected: Some(0),
            style: Style::default(),
            highlight_style: Style::default().fg(Color::Yellow),
            divider: None,
            block: None,
            padding_left: 1,
            padding_right: 1,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 40, 3)))
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
            titles: vec!["A".into(), "B".into()],
            selected: None,
            style: Style::default(),
            highlight_style: Style::default(),
            divider: Some(" | ".into()),
            block: None,
            padding_left: 1,
            padding_right: 1,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 40, 1)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("|"));
    }

    #[test]
    fn test_render_tabs_no_selection() {
        let backend = TestBackend::new(30, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = TabsData {
            titles: vec!["One".into(), "Two".into()],
            selected: None,
            style: Style::default(),
            highlight_style: Style::default(),
            divider: None,
            block: None,
            padding_left: 1,
            padding_right: 1,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 30, 1)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 30);
        assert!(line.contains("One"));
    }
}
