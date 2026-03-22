use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::widgets::{Scrollbar, ScrollbarOrientation, ScrollbarState};
use ratatui::Frame;

pub struct ScrollbarData {
    pub orientation: ScrollbarOrientation,
    pub thumb_style: Style,
    pub track_style: Style,
    pub begin_symbol: Option<String>,
    pub end_symbol: Option<String>,
    pub thumb_symbol: Option<String>,
    pub track_symbol: Option<String>,
    pub content_length: usize,
    pub position: usize,
    pub viewport_content_length: Option<usize>,
}

pub fn render(frame: &mut Frame, data: &ScrollbarData, area: Rect) {
    let mut scrollbar = Scrollbar::new(data.orientation.clone())
        .thumb_style(data.thumb_style)
        .track_style(data.track_style);

    if let Some(ref symbol) = data.thumb_symbol {
        scrollbar = scrollbar.thumb_symbol(symbol.as_str());
    }

    if let Some(ref symbol) = data.track_symbol {
        scrollbar = scrollbar.track_symbol(Some(symbol.as_str()));
    }

    if let Some(ref symbol) = data.begin_symbol {
        scrollbar = scrollbar.begin_symbol(Some(symbol.as_str()));
    }

    if let Some(ref symbol) = data.end_symbol {
        scrollbar = scrollbar.end_symbol(Some(symbol.as_str()));
    }

    let mut state = ScrollbarState::new(data.content_length).position(data.position);

    if let Some(vcl) = data.viewport_content_length {
        state = state.viewport_content_length(vcl);
    }

    frame.render_stateful_widget(scrollbar, area, &mut state);
}

pub fn parse_orientation(s: &str) -> Result<ScrollbarOrientation, rustler::Error> {
    match s {
        "vertical_right" => Ok(ScrollbarOrientation::VerticalRight),
        "vertical_left" => Ok(ScrollbarOrientation::VerticalLeft),
        "horizontal_bottom" => Ok(ScrollbarOrientation::HorizontalBottom),
        "horizontal_top" => Ok(ScrollbarOrientation::HorizontalTop),
        other => Err(rustler::Error::Term(Box::new(format!(
            "unknown scrollbar orientation: {other}"
        )))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    #[test]
    fn test_render_scrollbar_vertical() {
        let backend = TestBackend::new(20, 10);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ScrollbarData {
            orientation: ScrollbarOrientation::VerticalRight,
            thumb_style: Style::default(),
            track_style: Style::default(),
            begin_symbol: None,
            end_symbol: None,
            thumb_symbol: None,
            track_symbol: None,
            content_length: 100,
            position: 0,
            viewport_content_length: None,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 20, 10)))
            .unwrap();
        // Should render without panic
    }

    #[test]
    fn test_render_scrollbar_horizontal() {
        let backend = TestBackend::new(20, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = ScrollbarData {
            orientation: ScrollbarOrientation::HorizontalBottom,
            thumb_style: Style::default(),
            track_style: Style::default(),
            begin_symbol: None,
            end_symbol: None,
            thumb_symbol: None,
            track_symbol: None,
            content_length: 50,
            position: 25,
            viewport_content_length: None,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 20, 5)))
            .unwrap();
    }

    #[test]
    fn test_parse_orientation_all() {
        assert!(matches!(
            parse_orientation("vertical_right").unwrap(),
            ScrollbarOrientation::VerticalRight
        ));
        assert!(matches!(
            parse_orientation("vertical_left").unwrap(),
            ScrollbarOrientation::VerticalLeft
        ));
        assert!(matches!(
            parse_orientation("horizontal_bottom").unwrap(),
            ScrollbarOrientation::HorizontalBottom
        ));
        assert!(matches!(
            parse_orientation("horizontal_top").unwrap(),
            ScrollbarOrientation::HorizontalTop
        ));
    }

    #[test]
    fn test_parse_orientation_unknown() {
        assert!(parse_orientation("diagonal").is_err());
    }
}
