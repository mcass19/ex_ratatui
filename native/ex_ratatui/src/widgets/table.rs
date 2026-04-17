use ratatui::buffer::Buffer;
use ratatui::layout::{Constraint, Rect};
use ratatui::style::Style;
use ratatui::text::Line;
use ratatui::widgets::{Cell, Row, StatefulWidget, Table, TableState, Widget};

use crate::widgets::block::BlockData;

pub struct TableData {
    pub rows: Vec<Vec<Line<'static>>>,
    pub header: Option<Vec<Line<'static>>>,
    pub widths: Vec<Constraint>,
    pub style: Style,
    pub block: Option<BlockData>,
    pub highlight_style: Style,
    pub highlight_symbol: Option<String>,
    pub selected: Option<usize>,
    pub column_spacing: u16,
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
        .column_spacing(data.column_spacing);

    if let Some(ref header_cells) = data.header {
        let cells: Vec<Cell> = header_cells
            .iter()
            .map(|line| Cell::from(line.clone()))
            .collect();
        table = table.header(Row::new(cells));
    }

    if let Some(ref sym) = data.highlight_symbol {
        table = table.highlight_symbol(sym.as_str());
    }

    if let Some(ref block_data) = data.block {
        table = table.block(block_data.to_block());
    }

    if let Some(selected) = data.selected {
        let mut state = TableState::default();
        state.select(Some(selected));
        StatefulWidget::render(table, area, buf, &mut state);
    } else {
        Widget::render(table, area, buf);
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
            header: None,
            widths: vec![Constraint::Length(10), Constraint::Length(10)],
            style: Style::default(),
            block: None,
            highlight_style: Style::default(),
            highlight_symbol: None,
            selected: None,
            column_spacing: 1,
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
            style: Style::default(),
            block: None,
            highlight_style: Style::default(),
            highlight_symbol: None,
            selected: None,
            column_spacing: 1,
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
            header: None,
            widths: vec![Constraint::Length(20)],
            style: Style::default(),
            block: None,
            highlight_style: Style::default().fg(Color::Cyan),
            highlight_symbol: Some("> ".to_string()),
            selected: Some(1),
            column_spacing: 1,
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
            style: Style::default(),
            block: None,
            highlight_style: Style::default(),
            highlight_symbol: None,
            selected: None,
            column_spacing: 1,
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
}
