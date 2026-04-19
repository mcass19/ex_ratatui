use ratatui::buffer::Buffer;
use ratatui::layout::{Direction, Rect};
use ratatui::style::Style;
use ratatui::text::Line;
use ratatui::widgets::{Bar, BarChart, BarGroup, Widget};

use crate::widgets::block::BlockData;

pub struct BarData {
    pub label: String,
    pub value: u64,
    pub style: Option<Style>,
    pub text_value: Option<String>,
}

pub struct BarChartData {
    pub data: Vec<BarData>,
    pub bar_width: u16,
    pub bar_gap: u16,
    pub bar_style: Style,
    pub value_style: Style,
    pub label_style: Style,
    pub max: Option<u64>,
    pub direction: Direction,
    pub block: Option<BlockData>,
}

pub fn parse_direction(value: &str) -> Result<Direction, rustler::Error> {
    match value {
        "vertical" => Ok(Direction::Vertical),
        "horizontal" => Ok(Direction::Horizontal),
        other => Err(crate::decode::invalid_field(
            "bar_chart",
            "direction",
            &format!("unknown direction '{other}'"),
        )),
    }
}

pub fn render(buf: &mut Buffer, data: &BarChartData, area: Rect) {
    let bars: Vec<Bar<'_>> = data
        .data
        .iter()
        .map(|b| {
            let mut bar = Bar::default()
                .label(Line::from(b.label.clone()))
                .value(b.value)
                .style(b.style.unwrap_or(data.bar_style));

            if let Some(ref text_value) = b.text_value {
                bar = bar.text_value(text_value.clone());
            }

            bar
        })
        .collect();

    let group = BarGroup::default().bars(&bars);

    let mut chart = BarChart::default()
        .data(group)
        .bar_width(data.bar_width)
        .bar_gap(data.bar_gap)
        .bar_style(data.bar_style)
        .value_style(data.value_style)
        .label_style(data.label_style)
        .direction(data.direction);

    if let Some(max) = data.max {
        chart = chart.max(max);
    }

    if let Some(ref block_data) = data.block {
        chart = chart.block(block_data.to_block());
    }

    chart.render(area, buf);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::{buffer_line, buffer_to_string};
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use ratatui::Terminal;

    fn render_to_terminal(data: &BarChartData, width: u16, height: u16) -> Terminal<TestBackend> {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|frame| render(frame.buffer_mut(), data, Rect::new(0, 0, width, height)))
            .unwrap();
        terminal
    }

    #[test]
    fn renders_basic_vertical_chart_with_labels() {
        let data = BarChartData {
            data: vec![
                BarData {
                    label: "Elixir".to_string(),
                    value: 80,
                    style: None,
                    text_value: None,
                },
                BarData {
                    label: "Rust".to_string(),
                    value: 95,
                    style: None,
                    text_value: None,
                },
            ],
            bar_width: 6,
            bar_gap: 2,
            bar_style: Style::default(),
            value_style: Style::default(),
            label_style: Style::default(),
            max: None,
            direction: Direction::Vertical,
            block: None,
        };

        let terminal = render_to_terminal(&data, 30, 10);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("Elixir"));
        assert!(rendered.contains("Rust"));
    }

    #[test]
    fn renders_horizontal_chart() {
        let data = BarChartData {
            data: vec![BarData {
                label: "Go".to_string(),
                value: 60,
                style: None,
                text_value: None,
            }],
            bar_width: 1,
            bar_gap: 0,
            bar_style: Style::default(),
            value_style: Style::default(),
            label_style: Style::default(),
            max: Some(100),
            direction: Direction::Horizontal,
            block: None,
        };

        let terminal = render_to_terminal(&data, 20, 3);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("Go"));
    }

    #[test]
    fn auto_scales_when_max_is_none() {
        let data = BarChartData {
            data: vec![BarData {
                label: "Solo".to_string(),
                value: 42,
                style: None,
                text_value: None,
            }],
            bar_width: 4,
            bar_gap: 1,
            bar_style: Style::default(),
            value_style: Style::default(),
            label_style: Style::default(),
            max: None,
            direction: Direction::Vertical,
            block: None,
        };

        let terminal = render_to_terminal(&data, 10, 5);
        let line = buffer_line(&terminal, 4, 10);
        // Bottom row should contain the label text
        assert!(line.contains("Solo"));
    }

    #[test]
    fn empty_data_renders_without_panic() {
        let data = BarChartData {
            data: vec![],
            bar_width: 1,
            bar_gap: 1,
            bar_style: Style::default(),
            value_style: Style::default(),
            label_style: Style::default(),
            max: None,
            direction: Direction::Vertical,
            block: None,
        };

        let _terminal = render_to_terminal(&data, 10, 3);
    }

    #[test]
    fn text_value_replaces_numeric_display() {
        let data = BarChartData {
            data: vec![BarData {
                label: "Pct".to_string(),
                value: 80,
                style: None,
                text_value: Some("80%".to_string()),
            }],
            bar_width: 5,
            bar_gap: 0,
            bar_style: Style::default(),
            value_style: Style::default(),
            label_style: Style::default(),
            max: Some(100),
            direction: Direction::Vertical,
            block: None,
        };

        let terminal = render_to_terminal(&data, 10, 5);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("80%"));
        // Raw "80" still appears inside "80%", so we can't assert against it.
    }

    #[test]
    fn per_bar_style_overrides_shared_style() {
        let red = Style::default().fg(Color::Red);
        let blue = Style::default().fg(Color::Blue);

        let data = BarChartData {
            data: vec![
                BarData {
                    label: "Default".to_string(),
                    value: 10,
                    style: None,
                    text_value: None,
                },
                BarData {
                    label: "Override".to_string(),
                    value: 20,
                    style: Some(red),
                    text_value: None,
                },
            ],
            bar_width: 4,
            bar_gap: 1,
            bar_style: blue,
            value_style: Style::default(),
            label_style: Style::default(),
            max: Some(30),
            direction: Direction::Vertical,
            block: None,
        };

        let terminal = render_to_terminal(&data, 12, 6);
        let buffer = terminal.backend().buffer();

        // With bar_width 4 and gap 1, bar 0 spans x=0..=3 and bar 1 spans x=5..=8.
        // The bar cells sit above the label/value rows at the bottom.
        let bar_one_fg = buffer.cell((0, 0)).unwrap().fg;
        let bar_two_fg = buffer.cell((5, 0)).unwrap().fg;

        assert_eq!(bar_one_fg, Color::Blue);
        assert_eq!(bar_two_fg, Color::Red);
    }

    #[test]
    fn renders_with_block_title() {
        let data = BarChartData {
            data: vec![BarData {
                label: "A".to_string(),
                value: 1,
                style: None,
                text_value: None,
            }],
            bar_width: 1,
            bar_gap: 0,
            bar_style: Style::default(),
            value_style: Style::default(),
            label_style: Style::default(),
            max: None,
            direction: Direction::Vertical,
            block: Some(BlockData {
                title: Some(Line::from("Traffic")),
                borders: ratatui::widgets::Borders::ALL,
                border_type: ratatui::widgets::BorderType::Plain,
                border_style: Style::default(),
                style: Style::default(),
                padding: ratatui::widgets::Padding::new(0, 0, 0, 0),
            }),
        };

        let terminal = render_to_terminal(&data, 20, 5);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("Traffic"));
    }

    #[test]
    fn parse_direction_accepts_vertical_and_horizontal() {
        assert!(matches!(
            parse_direction("vertical"),
            Ok(Direction::Vertical)
        ));
        assert!(matches!(
            parse_direction("horizontal"),
            Ok(Direction::Horizontal)
        ));
    }

    #[test]
    fn parse_direction_rejects_unknown() {
        assert!(parse_direction("diagonal").is_err());
    }
}
