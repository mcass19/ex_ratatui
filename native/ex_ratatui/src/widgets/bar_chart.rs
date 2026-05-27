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

pub struct BarGroupData {
    pub label: Option<String>,
    pub bars: Vec<BarData>,
}

pub struct BarChartData {
    pub groups: Vec<BarGroupData>,
    pub bar_width: u16,
    pub bar_gap: u16,
    pub group_gap: u16,
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
    let mut chart = BarChart::default()
        .bar_width(data.bar_width)
        .bar_gap(data.bar_gap)
        .group_gap(data.group_gap)
        .bar_style(data.bar_style)
        .value_style(data.value_style)
        .label_style(data.label_style)
        .direction(data.direction);

    for group_data in &data.groups {
        let bars: Vec<Bar<'_>> = group_data
            .bars
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

        let mut group = BarGroup::default().bars(&bars);

        if let Some(ref label) = group_data.label {
            group = group.label(Line::from(label.clone()));
        }

        chart = chart.data(group);
    }

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

    fn anon_group(bars: Vec<BarData>) -> Vec<BarGroupData> {
        vec![BarGroupData { label: None, bars }]
    }

    #[test]
    fn renders_basic_vertical_chart_with_labels() {
        let data = BarChartData {
            groups: anon_group(vec![
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
            ]),
            bar_width: 6,
            bar_gap: 2,
            group_gap: 0,
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
            groups: anon_group(vec![BarData {
                label: "Go".to_string(),
                value: 60,
                style: None,
                text_value: None,
            }]),
            bar_width: 1,
            bar_gap: 0,
            group_gap: 0,
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
            groups: anon_group(vec![BarData {
                label: "Solo".to_string(),
                value: 42,
                style: None,
                text_value: None,
            }]),
            bar_width: 4,
            bar_gap: 1,
            group_gap: 0,
            bar_style: Style::default(),
            value_style: Style::default(),
            label_style: Style::default(),
            max: None,
            direction: Direction::Vertical,
            block: None,
        };

        let terminal = render_to_terminal(&data, 10, 5);
        let line = buffer_line(&terminal, 4, 10);
        assert!(line.contains("Solo"));
    }

    #[test]
    fn empty_data_renders_without_panic() {
        let data = BarChartData {
            groups: vec![],
            bar_width: 1,
            bar_gap: 1,
            group_gap: 0,
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
            groups: anon_group(vec![BarData {
                label: "Pct".to_string(),
                value: 80,
                style: None,
                text_value: Some("80%".to_string()),
            }]),
            bar_width: 5,
            bar_gap: 0,
            group_gap: 0,
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
    }

    #[test]
    fn per_bar_style_overrides_shared_style() {
        let red = Style::default().fg(Color::Red);
        let blue = Style::default().fg(Color::Blue);

        let data = BarChartData {
            groups: anon_group(vec![
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
            ]),
            bar_width: 4,
            bar_gap: 1,
            group_gap: 0,
            bar_style: blue,
            value_style: Style::default(),
            label_style: Style::default(),
            max: Some(30),
            direction: Direction::Vertical,
            block: None,
        };

        let terminal = render_to_terminal(&data, 12, 6);
        let buffer = terminal.backend().buffer();

        let bar_one_fg = buffer.cell((0, 0)).unwrap().fg;
        let bar_two_fg = buffer.cell((5, 0)).unwrap().fg;

        assert_eq!(bar_one_fg, Color::Blue);
        assert_eq!(bar_two_fg, Color::Red);
    }

    #[test]
    fn renders_with_block_title() {
        let data = BarChartData {
            groups: anon_group(vec![BarData {
                label: "A".to_string(),
                value: 1,
                style: None,
                text_value: None,
            }]),
            bar_width: 1,
            bar_gap: 0,
            group_gap: 0,
            bar_style: Style::default(),
            value_style: Style::default(),
            label_style: Style::default(),
            max: None,
            direction: Direction::Vertical,
            block: Some(BlockData {
                title: Some(Line::from("Traffic")),
                borders: ratatui::widgets::Borders::ALL,
                ..Default::default()
            }),
        };

        let terminal = render_to_terminal(&data, 20, 5);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("Traffic"));
    }

    #[test]
    fn renders_grouped_bars_with_group_labels() {
        let data = BarChartData {
            groups: vec![
                BarGroupData {
                    label: Some("Q1".to_string()),
                    bars: vec![
                        BarData {
                            label: "A".to_string(),
                            value: 10,
                            style: None,
                            text_value: None,
                        },
                        BarData {
                            label: "B".to_string(),
                            value: 20,
                            style: None,
                            text_value: None,
                        },
                    ],
                },
                BarGroupData {
                    label: Some("Q2".to_string()),
                    bars: vec![
                        BarData {
                            label: "A".to_string(),
                            value: 15,
                            style: None,
                            text_value: None,
                        },
                        BarData {
                            label: "B".to_string(),
                            value: 25,
                            style: None,
                            text_value: None,
                        },
                    ],
                },
            ],
            bar_width: 3,
            bar_gap: 1,
            group_gap: 3,
            bar_style: Style::default(),
            value_style: Style::default(),
            label_style: Style::default(),
            max: Some(30),
            direction: Direction::Vertical,
            block: None,
        };

        let terminal = render_to_terminal(&data, 40, 10);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("Q1"));
        assert!(rendered.contains("Q2"));
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
