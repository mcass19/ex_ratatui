use ratatui::buffer::Buffer;
use ratatui::layout::{Constraint, Rect};
use ratatui::style::Style;
use ratatui::text::Line;
use ratatui::widgets::{Cell, HighlightSpacing, Row, StatefulWidget, Table, TableState, Widget};

use crate::widgets::block::BlockData;

pub struct TableData {
    pub rows: Vec<Vec<Line<'static>>>,
    pub header: Option<Vec<Line<'static>>>,
    pub footer: Option<Vec<Line<'static>>>,
    pub widths: Vec<Constraint>,
    pub style: Style,
    pub block: Option<BlockData>,
    pub highlight_style: Style,
    pub column_highlight_style: Option<Style>,
    pub cell_highlight_style: Option<Style>,
    pub header_style: Option<Style>,
    pub footer_style: Option<Style>,
    pub highlight_symbol: Option<String>,
    pub highlight_spacing: HighlightSpacing,
    pub selected: Option<usize>,
    pub selected_column: Option<usize>,
    pub column_spacing: u16,
}

impl Default for TableData {
    fn default() -> Self {
        Self {
            rows: Vec::new(),
            header: None,
            footer: None,
            widths: Vec::new(),
            style: Style::default(),
            block: None,
            highlight_style: Style::default(),
            column_highlight_style: None,
            cell_highlight_style: None,
            header_style: None,
            footer_style: None,
            highlight_symbol: None,
            highlight_spacing: HighlightSpacing::default(),
            selected: None,
            selected_column: None,
            column_spacing: 1,
        }
    }
}

pub fn render(buf: &mut Buffer, data: &TableData, area: Rect) {
    let rows: Vec<Row> = data
        .rows
        .iter()
        .map(|row| {
            let cells: Vec<Cell> = row.iter().map(|line| Cell::from(line.clone())).collect();
            Row::new(cells)
        })
        .collect();

    let mut table = Table::new(rows, &data.widths)
        .style(data.style)
        .row_highlight_style(data.highlight_style)
        .column_spacing(data.column_spacing)
        .highlight_spacing(data.highlight_spacing.clone());

    if let Some(style) = data.column_highlight_style {
        table = table.column_highlight_style(style);
    }

    if let Some(style) = data.cell_highlight_style {
        table = table.cell_highlight_style(style);
    }

    if let Some(ref header_cells) = data.header {
        let cells: Vec<Cell> = header_cells
            .iter()
            .map(|line| Cell::from(line.clone()))
            .collect();
        let mut header_row = Row::new(cells);
        if let Some(style) = data.header_style {
            header_row = header_row.style(style);
        }
        table = table.header(header_row);
    }

    if let Some(ref footer_cells) = data.footer {
        let cells: Vec<Cell> = footer_cells
            .iter()
            .map(|line| Cell::from(line.clone()))
            .collect();
        let mut footer_row = Row::new(cells);
        if let Some(style) = data.footer_style {
            footer_row = footer_row.style(style);
        }
        table = table.footer(footer_row);
    }

    if let Some(ref sym) = data.highlight_symbol {
        table = table.highlight_symbol(sym.as_str());
    }

    if let Some(ref block_data) = data.block {
        table = table.block(block_data.to_block());
    }

    if data.selected.is_some() || data.selected_column.is_some() {
        let mut state = TableState::default();
        if let Some(row) = data.selected {
            state.select(Some(row));
        }
        if let Some(col) = data.selected_column {
            state.select_column(Some(col));
        }
        StatefulWidget::render(table, area, buf, &mut state);
    } else {
        Widget::render(table, area, buf);
    }
}

pub fn parse_highlight_spacing(s: &str) -> Result<HighlightSpacing, rustler::Error> {
    match s {
        "always" => Ok(HighlightSpacing::Always),
        "when_selected" => Ok(HighlightSpacing::WhenSelected),
        "never" => Ok(HighlightSpacing::Never),
        other => Err(rustler::Error::Term(Box::new(format!(
            "unknown highlight_spacing: {other}"
        )))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use ratatui::Terminal;

    #[test]
    fn test_render_simple_table() {
        let backend = TestBackend::new(30, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = TableData {
            rows: vec![
                vec![Line::from("Alice"), Line::from("30")],
                vec![Line::from("Bob"), Line::from("25")],
            ],
            widths: vec![Constraint::Length(10), Constraint::Length(10)],
            ..Default::default()
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 5)))
            .unwrap();

        let line0 = buffer_line(&terminal, 0, 30);
        assert!(line0.contains("Alice"));
        assert!(line0.contains("30"));

        let line1 = buffer_line(&terminal, 1, 30);
        assert!(line1.contains("Bob"));
        assert!(line1.contains("25"));
    }

    #[test]
    fn test_render_table_with_header() {
        let backend = TestBackend::new(30, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = TableData {
            rows: vec![vec![Line::from("Alice"), Line::from("30")]],
            header: Some(vec![Line::from("Name"), Line::from("Age")]),
            widths: vec![Constraint::Length(10), Constraint::Length(10)],
            ..Default::default()
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 5)))
            .unwrap();

        let header_line = buffer_line(&terminal, 0, 30);
        assert!(header_line.contains("Name"));
        assert!(header_line.contains("Age"));

        // Data row comes after header (with possible separator)
        let data_line = buffer_line(&terminal, 1, 30);
        assert!(data_line.contains("Alice"));
    }

    #[test]
    fn test_render_table_with_selection() {
        let backend = TestBackend::new(30, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = TableData {
            rows: vec![
                vec![Line::from("Row 1")],
                vec![Line::from("Row 2")],
                vec![Line::from("Row 3")],
            ],
            widths: vec![Constraint::Length(20)],
            highlight_style: Style::default().fg(Color::Cyan),
            highlight_symbol: Some("> ".to_string()),
            selected: Some(1),
            ..Default::default()
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 5)))
            .unwrap();

        let selected_line = buffer_line(&terminal, 1, 30);
        assert!(selected_line.contains("Row 2"));
        assert!(selected_line.contains(">"));
    }

    #[test]
    fn test_render_cells_with_rich_text_spans() {
        use ratatui::style::Modifier;
        use ratatui::text::Span;

        let backend = TestBackend::new(30, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let styled_cell = Line::from(vec![
            Span::styled("err", Style::default().fg(Color::Red)),
            Span::styled(
                "or",
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
        ]);

        let data = TableData {
            rows: vec![vec![styled_cell, Line::from("details")]],
            header: Some(vec![
                Line::from(Span::styled("Status", Style::default().fg(Color::Cyan))),
                Line::from("Info"),
            ]),
            widths: vec![Constraint::Length(10), Constraint::Length(10)],
            ..Default::default()
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 3)))
            .unwrap();

        let buf = terminal.backend().buffer();
        // Header "Status" cyan at (0,0)
        assert_eq!(buf.cell((0, 0)).unwrap().fg, Color::Cyan);
        // Row 0, col 0: "err" red, "or" yellow+bold (row lives at row 1: header is row 0)
        assert_eq!(buf.cell((0, 1)).unwrap().fg, Color::Red);
        let or_cell = buf.cell((3, 1)).unwrap();
        assert_eq!(or_cell.symbol(), "o");
        assert_eq!(or_cell.fg, Color::Yellow);
        assert!(or_cell.modifier.contains(Modifier::BOLD));
    }

    #[test]
    fn test_render_table_with_footer() {
        let backend = TestBackend::new(30, 6);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = TableData {
            rows: vec![vec![Line::from("Alice"), Line::from("30")]],
            header: Some(vec![Line::from("Name"), Line::from("Age")]),
            footer: Some(vec![Line::from("Total"), Line::from("1 row")]),
            widths: vec![Constraint::Length(10), Constraint::Length(10)],
            ..Default::default()
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 6)))
            .unwrap();

        // header at row 0, row at row 1, footer renders at the bottom of the area
        let footer_line = buffer_line(&terminal, 5, 30);
        assert!(footer_line.contains("Total"));
        assert!(footer_line.contains("1 row"));
    }

    #[test]
    fn test_header_style_colors_the_header_row() {
        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = TableData {
            rows: vec![vec![Line::from("a")]],
            header: Some(vec![Line::from("Name")]),
            header_style: Some(Style::default().fg(Color::Magenta)),
            widths: vec![Constraint::Length(10)],
            ..Default::default()
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 3)))
            .unwrap();

        let buf = terminal.backend().buffer();
        assert_eq!(buf.cell((0, 0)).unwrap().fg, Color::Magenta);
    }

    #[test]
    fn test_highlight_spacing_always_reserves_symbol_column_without_selection() {
        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = TableData {
            rows: vec![vec![Line::from("only")]],
            widths: vec![Constraint::Length(10)],
            highlight_symbol: Some(">> ".to_string()),
            highlight_spacing: HighlightSpacing::Always,
            ..Default::default()
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 3)))
            .unwrap();

        let line = buffer_line(&terminal, 0, 20);
        // With Always, the symbol column shifts the row even when nothing is
        // selected — "only" lands after a 3-cell offset.
        assert!(line.starts_with("   only"));
    }

    #[test]
    fn test_parse_highlight_spacing() {
        assert!(matches!(
            parse_highlight_spacing("always"),
            Ok(HighlightSpacing::Always)
        ));
        assert!(matches!(
            parse_highlight_spacing("when_selected"),
            Ok(HighlightSpacing::WhenSelected)
        ));
        assert!(matches!(
            parse_highlight_spacing("never"),
            Ok(HighlightSpacing::Never)
        ));
        assert!(parse_highlight_spacing("sometimes").is_err());
    }
}
