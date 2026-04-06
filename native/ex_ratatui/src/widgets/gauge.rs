use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::widgets::{Gauge, Widget};

use crate::widgets::block::BlockData;

pub struct GaugeData {
    pub ratio: f64,
    pub label: Option<String>,
    pub style: Style,
    pub block: Option<BlockData>,
    pub gauge_style: Style,
}

pub fn render(buf: &mut Buffer, data: &GaugeData, area: Rect) {
    let mut gauge = Gauge::default()
        .style(data.style)
        .gauge_style(data.gauge_style)
        .ratio(data.ratio.clamp(0.0, 1.0));

    if let Some(ref label) = data.label {
        gauge = gauge.label(label.as_str());
    }

    if let Some(ref block_data) = data.block {
        gauge = gauge.block(block_data.to_block());
    }

    gauge.render(area, buf);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use ratatui::Terminal;

    #[test]
    fn test_render_gauge_half() {
        let backend = TestBackend::new(20, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = GaugeData {
            ratio: 0.5,
            label: None,
            style: Style::default(),
            block: None,
            gauge_style: Style::default().fg(Color::Green),
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 1)))
            .unwrap();

        // Gauge should render something (not all empty)
        let line = buffer_line(&terminal, 0, 20);
        assert!(!line.is_empty());
    }

    #[test]
    fn test_render_gauge_with_label() {
        let backend = TestBackend::new(20, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = GaugeData {
            ratio: 0.75,
            label: Some("75%".to_string()),
            style: Style::default(),
            block: None,
            gauge_style: Style::default(),
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 1)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 20);
        assert!(line.contains("75%"));
    }

    #[test]
    fn test_render_gauge_clamped() {
        // ratio > 1.0 should be clamped to 1.0 without panic
        let backend = TestBackend::new(20, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = GaugeData {
            ratio: 1.5,
            label: None,
            style: Style::default(),
            block: None,
            gauge_style: Style::default(),
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 1)))
            .unwrap();

        // Should not panic — that's the test
    }
}
