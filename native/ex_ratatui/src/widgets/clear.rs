use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::widgets::{Clear, Widget};

pub fn render(buf: &mut Buffer, area: Rect) {
    Clear.render(area, buf);
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::style::Style;
    use ratatui::widgets::Paragraph;
    use ratatui::Terminal;

    #[test]
    fn test_clear_resets_cell_symbols() {
        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        terminal
            .draw(|frame| {
                let p = Paragraph::new("Hello World!").style(Style::default());
                frame.render_widget(p, Rect::new(0, 0, 20, 3));
                render(frame.buffer_mut(), Rect::new(0, 0, 10, 1));
            })
            .unwrap();

        let buf = terminal.backend().buffer();
        // Cleared area should be spaces
        assert_eq!(buf.cell((0, 0)).unwrap().symbol(), " ");
        assert_eq!(buf.cell((5, 0)).unwrap().symbol(), " ");
        // Beyond cleared area should still have text ("Hello World!" - index 10 is 'd')
        assert_eq!(buf.cell((10, 0)).unwrap().symbol(), "d");
    }
}
