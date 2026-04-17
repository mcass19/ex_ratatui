use ratatui::layout::Alignment;
use ratatui::style::Style;
use ratatui::text::{Line, Span, Text};
use rustler::{Error, Term};

use crate::decode::{decode_map, decode_optional, decode_required, invalid_field, optional_term};
use crate::style::decode_style;

/// Decode a canonical text wire map (`{lines, style, alignment}`) into a
/// ratatui `Text<'static>`.
pub fn decode_text(term: Term) -> Result<Text<'static>, Error> {
    let map = decode_map(term, "text")?;

    let line_terms: Vec<Term<'_>> = decode_required(&map, "lines", "text")?;
    let lines = line_terms
        .into_iter()
        .map(decode_line)
        .collect::<Result<Vec<_>, _>>()?;

    let style = decode_optional_style(&map)?;
    let alignment = decode_optional_alignment(&map, "text")?;

    let mut text = Text::from(lines).style(style);
    if let Some(alignment) = alignment {
        text = text.alignment(alignment);
    }
    Ok(text)
}

/// Decode a canonical line wire map (`{spans, style, alignment}`) into a
/// ratatui `Line<'static>`.
pub fn decode_line(term: Term) -> Result<Line<'static>, Error> {
    let map = decode_map(term, "line")?;

    let span_terms: Vec<Term<'_>> = decode_required(&map, "spans", "line")?;
    let spans = span_terms
        .into_iter()
        .map(decode_span)
        .collect::<Result<Vec<_>, _>>()?;

    let style = decode_optional_style(&map)?;
    let alignment = decode_optional_alignment(&map, "line")?;

    let mut line = Line::from(spans).style(style);
    if let Some(alignment) = alignment {
        line = line.alignment(alignment);
    }
    Ok(line)
}

fn decode_span(term: Term) -> Result<Span<'static>, Error> {
    let map = decode_map(term, "span")?;

    let content: String = decode_required(&map, "content", "span")?;
    let style = decode_optional_style(&map)?;

    Ok(Span::styled(content, style))
}

fn decode_optional_style(map: &crate::decode::TermMap<'_>) -> Result<Style, Error> {
    match optional_term(map, "style") {
        Some(term) => decode_style(term),
        None => Ok(Style::default()),
    }
}

fn decode_optional_alignment(
    map: &crate::decode::TermMap<'_>,
    context: &'static str,
) -> Result<Option<Alignment>, Error> {
    match decode_optional::<String>(map, "alignment", context)? {
        Some(s) => match s.as_str() {
            "left" => Ok(Some(Alignment::Left)),
            "center" => Ok(Some(Alignment::Center)),
            "right" => Ok(Some(Alignment::Right)),
            other => Err(invalid_field(
                context,
                "alignment",
                &format!("unknown alignment '{other}'"),
            )),
        },
        None => Ok(None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::layout::Rect;
    use ratatui::style::{Color, Modifier};
    use ratatui::widgets::{Paragraph, Widget};
    use ratatui::Terminal;

    fn render_text(text: Text<'static>, width: u16, height: u16) -> Terminal<TestBackend> {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|frame| {
                Paragraph::new(text).render(Rect::new(0, 0, width, height), frame.buffer_mut())
            })
            .unwrap();
        terminal
    }

    #[test]
    fn test_build_text_from_spans_applies_per_span_style() {
        let text = Text::from(vec![Line::from(vec![
            Span::styled("Hello ", Style::default().fg(Color::Green)),
            Span::styled(
                "world",
                Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
            ),
        ])]);

        let terminal = render_text(text, 20, 1);
        let buf = terminal.backend().buffer();

        assert_eq!(buf.cell((0, 0)).unwrap().symbol(), "H");
        assert_eq!(buf.cell((0, 0)).unwrap().fg, Color::Green);
        assert_eq!(buf.cell((6, 0)).unwrap().symbol(), "w");
        assert_eq!(buf.cell((6, 0)).unwrap().fg, Color::Red);
        assert!(buf.cell((6, 0)).unwrap().modifier.contains(Modifier::BOLD));
    }

    #[test]
    fn test_line_style_cascades_into_spans() {
        // Line style sets yellow bg; span style sets red fg. Both should apply.
        let text = Text::from(vec![Line::from(vec![Span::styled(
            "hi",
            Style::default().fg(Color::Red),
        )])
        .style(Style::default().bg(Color::Yellow))]);

        let terminal = render_text(text, 5, 1);
        let buf = terminal.backend().buffer();

        let cell = buf.cell((0, 0)).unwrap();
        assert_eq!(cell.fg, Color::Red);
        assert_eq!(cell.bg, Color::Yellow);
    }

    #[test]
    fn test_per_line_alignment_overrides_paragraph_default() {
        let text = Text::from(vec![
            Line::from("left").alignment(Alignment::Left),
            Line::from("right").alignment(Alignment::Right),
        ]);

        let backend = TestBackend::new(10, 2);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|frame| {
                Paragraph::new(text).render(Rect::new(0, 0, 10, 2), frame.buffer_mut());
            })
            .unwrap();

        let buf = terminal.backend().buffer();
        // Left-aligned: "left" at column 0
        assert_eq!(buf.cell((0, 0)).unwrap().symbol(), "l");
        // Right-aligned: "right" ends at column 9 (so 'r' is at column 5)
        assert_eq!(buf.cell((5, 1)).unwrap().symbol(), "r");
        assert_eq!(buf.cell((9, 1)).unwrap().symbol(), "t");
    }
}
