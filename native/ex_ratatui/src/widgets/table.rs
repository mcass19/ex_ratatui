use ratatui::buffer::Buffer;
use ratatui::layout::{Constraint, Rect};
use ratatui::style::Style;
use ratatui::widgets::{Cell, Row, StatefulWidget, Table, TableState, Widget};

use crate::widgets::block::BlockData;

pub struct TableData {
    pub rows: Vec<Vec<String>>,
    pub header: Option<Vec<String>>,
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
            let cells: Vec<Cell> = row.iter().map(|s| Cell::from(s.as_str())).collect();
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
            .map(|s| Cell::from(s.as_str()))
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
                vec!["Alice".into(), "30".into()],
                vec!["Bob".into(), "25".into()],
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
            rows: vec![vec!["Alice".into(), "30".into()]],
            header: Some(vec!["Name".into(), "Age".into()]),
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
                vec!["Row 1".into()],
                vec!["Row 2".into()],
                vec!["Row 3".into()],
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
}
