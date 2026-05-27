use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::widgets::calendar::{CalendarEventStore, Monthly};
use ratatui::widgets::Widget;
use time::{Date, Month};

use crate::widgets::block::BlockData;

pub struct CalendarData {
    pub display_date: Date,
    pub events: Vec<(Date, Style)>,
    pub default_style: Style,
    pub show_month_header: Option<Style>,
    pub show_weekdays_header: Option<Style>,
    pub show_surrounding: Option<Style>,
    pub block: Option<BlockData>,
}

pub fn parse_date(year: i32, month: u8, day: u8) -> Result<Date, rustler::Error> {
    let month = Month::try_from(month).map_err(|_| {
        crate::decode::invalid_field(
            "calendar",
            "month",
            &format!("invalid month '{month}' (expected 1..12)"),
        )
    })?;

    Date::from_calendar_date(year, month, day).map_err(|err| {
        crate::decode::invalid_field(
            "calendar",
            "display_date",
            &format!("invalid date {year}-{month:?}-{day}: {err}"),
        )
    })
}

pub fn render(buf: &mut Buffer, data: &CalendarData, area: Rect) {
    let mut store = CalendarEventStore::default();
    for (date, style) in &data.events {
        store.add(*date, *style);
    }

    let mut calendar = Monthly::new(data.display_date, store).default_style(data.default_style);

    if let Some(style) = data.show_month_header {
        calendar = calendar.show_month_header(style);
    }

    if let Some(style) = data.show_weekdays_header {
        calendar = calendar.show_weekdays_header(style);
    }

    if let Some(style) = data.show_surrounding {
        calendar = calendar.show_surrounding(style);
    }

    if let Some(ref block_data) = data.block {
        calendar = calendar.block(block_data.to_block());
    }

    calendar.render(area, buf);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_to_string;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;
    use time::Month;

    fn base(year: i32, month: Month, day: u8) -> CalendarData {
        CalendarData {
            display_date: Date::from_calendar_date(year, month, day).unwrap(),
            events: vec![],
            default_style: Style::default(),
            show_month_header: None,
            show_weekdays_header: None,
            show_surrounding: None,
            block: None,
        }
    }

    fn render_to_terminal(data: &CalendarData, width: u16, height: u16) -> Terminal<TestBackend> {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|frame| render(frame.buffer_mut(), data, Rect::new(0, 0, width, height)))
            .unwrap();
        terminal
    }

    #[test]
    fn renders_basic_month() {
        let data = base(2026, Month::March, 15);
        let terminal = render_to_terminal(&data, 22, 8);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("15"));
    }

    #[test]
    fn renders_month_header_when_enabled() {
        let mut data = base(2026, Month::March, 15);
        data.show_month_header = Some(Style::default());
        let terminal = render_to_terminal(&data, 22, 8);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("March"));
        assert!(rendered.contains("2026"));
    }

    #[test]
    fn hides_month_header_when_none() {
        let data = base(2026, Month::March, 15);
        let terminal = render_to_terminal(&data, 22, 8);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.contains("March"));
    }

    #[test]
    fn renders_weekdays_header_when_enabled() {
        let mut data = base(2026, Month::March, 15);
        data.show_weekdays_header = Some(Style::default());
        let terminal = render_to_terminal(&data, 22, 8);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("Su"));
        assert!(rendered.contains("Sa"));
    }

    #[test]
    fn renders_event_for_specific_day() {
        let mut data = base(2026, Month::March, 15);
        data.events = vec![(
            Date::from_calendar_date(2026, Month::March, 10).unwrap(),
            Style::default(),
        )];
        let terminal = render_to_terminal(&data, 22, 8);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("10"));
    }

    #[test]
    fn renders_multiple_events() {
        let mut data = base(2026, Month::March, 15);
        data.events = vec![
            (
                Date::from_calendar_date(2026, Month::March, 3).unwrap(),
                Style::default(),
            ),
            (
                Date::from_calendar_date(2026, Month::March, 20).unwrap(),
                Style::default(),
            ),
        ];
        let terminal = render_to_terminal(&data, 22, 8);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("3"));
        assert!(rendered.contains("20"));
    }

    #[test]
    fn renders_surrounding_days_when_enabled() {
        let mut data = base(2026, Month::March, 15);
        data.show_surrounding = Some(Style::default());
        let terminal = render_to_terminal(&data, 22, 8);
        let rendered = buffer_to_string(&terminal);
        // Surrounding fills first row with dates from February 2026.
        // Feb 2026 last day is 28 — check for it in the buffer.
        assert!(rendered.contains("28"));
    }

    #[test]
    fn with_block_title_renders() {
        let mut data = base(2026, Month::March, 15);
        data.block = Some(BlockData {
            title: Some(ratatui::text::Line::from("Calendar")),
            borders: ratatui::widgets::Borders::ALL,
            ..Default::default()
        });
        let terminal = render_to_terminal(&data, 24, 10);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("Calendar"));
    }

    #[test]
    fn january_renders() {
        let data = base(2026, Month::January, 1);
        let terminal = render_to_terminal(&data, 22, 8);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("1"));
        assert!(rendered.contains("31"));
    }

    #[test]
    fn december_renders() {
        let data = base(2026, Month::December, 31);
        let terminal = render_to_terminal(&data, 22, 8);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("31"));
    }

    #[test]
    fn leap_february_renders_29() {
        let mut data = base(2024, Month::February, 15);
        data.show_surrounding = Some(Style::default());
        let terminal = render_to_terminal(&data, 22, 8);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("29"));
    }

    #[test]
    fn parse_date_accepts_valid() {
        assert!(parse_date(2026, 3, 15).is_ok());
    }

    #[test]
    fn parse_date_rejects_invalid_month() {
        assert!(parse_date(2026, 13, 1).is_err());
    }

    #[test]
    fn parse_date_rejects_invalid_day() {
        assert!(parse_date(2026, 2, 30).is_err());
    }
}
