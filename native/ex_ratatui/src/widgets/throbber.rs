use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::Frame;
use throbber_widgets_tui::{self, ThrobberState, WhichUse};

use crate::widgets::block::BlockData;

pub struct ThrobberData {
    pub label: Option<String>,
    pub style: Style,
    pub throbber_style: Style,
    pub throbber_set: throbber_widgets_tui::Set,
    pub step: i8,
    pub block: Option<BlockData>,
}

pub fn render(frame: &mut Frame, data: &ThrobberData, area: Rect) {
    let inner_area = if let Some(ref block_data) = data.block {
        let block = block_data.to_block();
        let inner = block.inner(area);
        frame.render_widget(block, area);
        inner
    } else {
        area
    };

    let mut throbber = throbber_widgets_tui::Throbber::default()
        .style(data.style)
        .throbber_style(data.throbber_style)
        .throbber_set(data.throbber_set.clone())
        .use_type(WhichUse::Spin);

    if let Some(ref label) = data.label {
        throbber = throbber.label(label.as_str());
    }

    let mut state = ThrobberState::default();
    state.calc_step(data.step);

    frame.render_stateful_widget(throbber, inner_area, &mut state);
}

pub fn parse_throbber_set(name: &str) -> throbber_widgets_tui::Set {
    match name {
        "braille" | "braille_six" => throbber_widgets_tui::BRAILLE_SIX,
        "braille_double" | "braille_six_double" => throbber_widgets_tui::BRAILLE_SIX_DOUBLE,
        "braille_one" => throbber_widgets_tui::BRAILLE_ONE,
        "braille_eight" => throbber_widgets_tui::BRAILLE_EIGHT,
        "braille_eight_double" => throbber_widgets_tui::BRAILLE_EIGHT_DOUBLE,
        "dots" | "braille_double_short" => throbber_widgets_tui::BRAILLE_DOUBLE,
        "vertical_block" => throbber_widgets_tui::VERTICAL_BLOCK,
        "horizontal_block" => throbber_widgets_tui::HORIZONTAL_BLOCK,
        "ascii" => throbber_widgets_tui::ASCII,
        "arrow" => throbber_widgets_tui::ARROW,
        "clock" => throbber_widgets_tui::CLOCK,
        "box_drawing" => throbber_widgets_tui::BOX_DRAWING,
        "quadrant_block" => throbber_widgets_tui::QUADRANT_BLOCK,
        "white_square" => throbber_widgets_tui::WHITE_SQUARE,
        "white_circle" => throbber_widgets_tui::WHITE_CIRCLE,
        "black_circle" => throbber_widgets_tui::BLACK_CIRCLE,
        _ => throbber_widgets_tui::BRAILLE_SIX,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    fn make_data(label: Option<&str>, step: i8, set: &str) -> ThrobberData {
        ThrobberData {
            label: label.map(|s| s.to_string()),
            style: Style::default(),
            throbber_style: Style::default(),
            throbber_set: parse_throbber_set(set),
            step,
            block: None,
        }
    }

    #[test]
    fn test_render_throbber_with_label() {
        let backend = TestBackend::new(30, 1);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make_data(Some("Loading..."), 0, "braille");

        terminal
            .draw(|frame| {
                render(frame, &data, Rect::new(0, 0, 30, 1));
            })
            .unwrap();

        let line = buffer_line(&terminal, 0, 30);
        assert!(
            line.contains("Loading..."),
            "Expected 'Loading...' in: {line}"
        );
    }

    #[test]
    fn test_render_throbber_different_steps() {
        let backend = TestBackend::new(30, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let data0 = make_data(None, 0, "braille");
        terminal
            .draw(|frame| {
                render(frame, &data0, Rect::new(0, 0, 30, 1));
            })
            .unwrap();
        let line0 = buffer_line(&terminal, 0, 30);

        let data1 = make_data(None, 1, "braille");
        terminal
            .draw(|frame| {
                render(frame, &data1, Rect::new(0, 0, 30, 1));
            })
            .unwrap();
        let line1 = buffer_line(&terminal, 0, 30);

        // Adjacent steps should produce different symbols
        assert_ne!(line0, line1, "Step 0 and step 1 should render differently");
    }

    #[test]
    fn test_render_throbber_with_block() {
        let backend = TestBackend::new(30, 3);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = ThrobberData {
            label: Some("Working...".to_string()),
            style: Style::default(),
            throbber_style: Style::default(),
            throbber_set: parse_throbber_set("braille"),
            step: 0,
            block: Some(BlockData {
                title: Some("Status".to_string()),
                borders: ratatui::widgets::Borders::ALL,
                border_type: ratatui::widgets::BorderType::Rounded,
                border_style: Style::default(),
                style: Style::default(),
                padding: ratatui::widgets::Padding::zero(),
            }),
        };

        terminal
            .draw(|frame| {
                render(frame, &data, Rect::new(0, 0, 30, 3));
            })
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 30);
        assert!(line0.contains("Status"), "Expected 'Status' in: {line0}");
    }

    #[test]
    fn test_render_throbber_braille_set() {
        let backend = TestBackend::new(10, 1);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make_data(None, 0, "braille");

        terminal
            .draw(|frame| {
                render(frame, &data, Rect::new(0, 0, 10, 1));
            })
            .unwrap();

        let line = buffer_line(&terminal, 0, 10);
        assert!(
            !line.trim().is_empty(),
            "Braille throbber should render a symbol"
        );
    }

    #[test]
    fn test_render_throbber_ascii_set() {
        let backend = TestBackend::new(10, 1);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make_data(None, 0, "ascii");

        terminal
            .draw(|frame| {
                render(frame, &data, Rect::new(0, 0, 10, 1));
            })
            .unwrap();

        let line = buffer_line(&terminal, 0, 10);
        assert!(
            !line.trim().is_empty(),
            "ASCII throbber should render a symbol"
        );
    }
}
