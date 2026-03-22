use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::widgets::LineGauge;
use ratatui::Frame;

use crate::widgets::block::BlockData;

pub struct LineGaugeData {
    pub ratio: f64,
    pub label: Option<String>,
    pub style: Style,
    pub filled_style: Style,
    pub unfilled_style: Style,
    pub block: Option<BlockData>,
}

pub fn render(frame: &mut Frame, data: &LineGaugeData, area: Rect) {
    let mut line_gauge = LineGauge::default()
        .style(data.style)
        .filled_style(data.filled_style)
        .unfilled_style(data.unfilled_style)
        .ratio(data.ratio.clamp(0.0, 1.0));

    if let Some(ref label) = data.label {
        line_gauge = line_gauge.label(label.as_str());
    }

    if let Some(ref block_data) = data.block {
        line_gauge = line_gauge.block(block_data.to_block());
    }

    frame.render_widget(line_gauge, area);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use ratatui::Terminal;

    #[test]
    fn test_render_line_gauge_half() {
        let backend = TestBackend::new(20, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = LineGaugeData {
            ratio: 0.5,
            label: None,
            style: Style::default(),
            filled_style: Style::default().fg(Color::Green),
            unfilled_style: Style::default(),
            block: None,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 20, 1)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 20);
        assert!(!line.is_empty());
    }

    #[test]
    fn test_render_line_gauge_with_label() {
        let backend = TestBackend::new(30, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = LineGaugeData {
            ratio: 0.75,
            label: Some("75%".to_string()),
            style: Style::default(),
            filled_style: Style::default(),
            unfilled_style: Style::default(),
            block: None,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 30, 1)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 30);
        assert!(line.contains("75%"));
    }

    #[test]
    fn test_render_line_gauge_clamped() {
        let backend = TestBackend::new(20, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = LineGaugeData {
            ratio: 1.5,
            label: None,
            style: Style::default(),
            filled_style: Style::default(),
            unfilled_style: Style::default(),
            block: None,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 20, 1)))
            .unwrap();
        // Should not panic
    }
}
