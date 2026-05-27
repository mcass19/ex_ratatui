use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::symbols::bar;
use ratatui::widgets::{RenderDirection, Sparkline, Widget};

use crate::widgets::block::BlockData;

pub enum SparklineBarSet {
    NineLevels,
    ThreeLevels,
    Custom(Vec<String>),
}

pub struct SparklineData {
    pub data: Vec<Option<u64>>,
    pub style: Style,
    pub max: Option<u64>,
    pub direction: RenderDirection,
    pub bar_set: SparklineBarSet,
    pub absent_value_style: Style,
    pub absent_value_symbol: Option<String>,
    pub block: Option<BlockData>,
}

pub fn parse_direction(value: &str) -> Result<RenderDirection, rustler::Error> {
    match value {
        "left_to_right" => Ok(RenderDirection::LeftToRight),
        "right_to_left" => Ok(RenderDirection::RightToLeft),
        other => Err(crate::decode::invalid_field(
            "sparkline",
            "direction",
            &format!("unknown direction '{other}'"),
        )),
    }
}

pub fn render(buf: &mut Buffer, data: &SparklineData, area: Rect) {
    let bar_set = match &data.bar_set {
        SparklineBarSet::NineLevels => bar::NINE_LEVELS.clone(),
        SparklineBarSet::ThreeLevels => bar::THREE_LEVELS.clone(),
        SparklineBarSet::Custom(symbols) => build_custom_set(symbols),
    };

    let mut sparkline = Sparkline::default()
        .data(data.data.clone())
        .style(data.style)
        .absent_value_style(data.absent_value_style)
        .direction(data.direction)
        .bar_set(bar_set);

    if let Some(max) = data.max {
        sparkline = sparkline.max(max);
    }

    if let Some(ref symbol) = data.absent_value_symbol {
        sparkline = sparkline.absent_value_symbol(symbol.clone());
    }

    if let Some(ref block_data) = data.block {
        sparkline = sparkline.block(block_data.to_block());
    }

    sparkline.render(area, buf);
}

fn build_custom_set(symbols: &[String]) -> bar::Set<'_> {
    let n = symbols.len().max(1);
    let slot = |i: usize| symbols[((i * n) / 9).min(n - 1)].as_str();

    bar::Set {
        empty: slot(0),
        one_eighth: slot(1),
        one_quarter: slot(2),
        three_eighths: slot(3),
        half: slot(4),
        five_eighths: slot(5),
        three_quarters: slot(6),
        seven_eighths: slot(7),
        full: slot(8),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_to_string;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    fn base(data: Vec<Option<u64>>) -> SparklineData {
        SparklineData {
            data,
            style: Style::default(),
            max: None,
            direction: RenderDirection::LeftToRight,
            bar_set: SparklineBarSet::NineLevels,
            absent_value_style: Style::default(),
            absent_value_symbol: None,
            block: None,
        }
    }

    fn render_to_terminal(data: &SparklineData, width: u16, height: u16) -> Terminal<TestBackend> {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|frame| render(frame.buffer_mut(), data, Rect::new(0, 0, width, height)))
            .unwrap();
        terminal
    }

    #[test]
    fn renders_basic_left_to_right() {
        let data = base(vec![Some(0), Some(2), Some(5), Some(8), Some(3)]);
        let terminal = render_to_terminal(&data, 10, 1);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.trim().is_empty());
    }

    #[test]
    fn renders_right_to_left() {
        let mut data = base(vec![Some(1), Some(2), Some(8)]);
        data.direction = RenderDirection::RightToLeft;
        data.max = Some(8);

        let terminal = render_to_terminal(&data, 10, 1);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains('\u{2588}'));
    }

    #[test]
    fn auto_scales_when_max_is_none() {
        let data = base(vec![Some(5), Some(10), Some(15)]);
        let terminal = render_to_terminal(&data, 6, 1);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.trim().is_empty());
    }

    #[test]
    fn absent_value_renders_with_custom_symbol() {
        let mut data = base(vec![Some(1), None, Some(5)]);
        data.max = Some(5);
        data.absent_value_symbol = Some("?".to_string());

        let terminal = render_to_terminal(&data, 3, 1);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains('?'));
    }

    #[test]
    fn three_levels_preset_renders() {
        let mut data = base(vec![Some(0), Some(4), Some(8)]);
        data.max = Some(8);
        data.bar_set = SparklineBarSet::ThreeLevels;

        let terminal = render_to_terminal(&data, 3, 1);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.is_empty());
    }

    #[test]
    fn custom_bar_set_renders() {
        let mut data = base(vec![Some(0), Some(2), Some(5), Some(8)]);
        data.max = Some(8);
        data.bar_set =
            SparklineBarSet::Custom(vec![".".to_string(), "o".to_string(), "O".to_string()]);

        let terminal = render_to_terminal(&data, 4, 1);
        let rendered = buffer_to_string(&terminal);
        // The tallest bar should use the last custom glyph.
        assert!(rendered.contains('O'));
    }

    #[test]
    fn empty_data_renders_without_panic() {
        let data = base(vec![]);
        let _terminal = render_to_terminal(&data, 10, 1);
    }

    #[test]
    fn with_block_title_renders() {
        let mut data = base(vec![Some(1), Some(2), Some(3)]);
        data.block = Some(BlockData {
            title: Some(ratatui::text::Line::from("CPU")),
            borders: ratatui::widgets::Borders::ALL,
            ..Default::default()
        });

        let terminal = render_to_terminal(&data, 15, 3);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("CPU"));
    }

    #[test]
    fn parse_direction_accepts_both() {
        assert!(matches!(
            parse_direction("left_to_right"),
            Ok(RenderDirection::LeftToRight)
        ));
        assert!(matches!(
            parse_direction("right_to_left"),
            Ok(RenderDirection::RightToLeft)
        ));
    }

    #[test]
    fn parse_direction_rejects_unknown() {
        assert!(parse_direction("diagonal").is_err());
    }

    #[test]
    fn build_custom_set_spreads_symbols_across_levels() {
        let symbols = vec![
            " ".to_string(),
            "▂".to_string(),
            "▅".to_string(),
            "█".to_string(),
        ];
        let set = build_custom_set(&symbols);
        assert_eq!(set.empty, " ");
        assert_eq!(set.full, "█");
    }
}
