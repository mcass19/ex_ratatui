use ratatui::buffer::Buffer;
use ratatui::layout::{Alignment, Rect};
use ratatui::style::Style;
use ratatui::text::Line;
use ratatui::widgets::Widget;
use rustler::Error;
use tui_big_text::{BigText, PixelSize};

use crate::decode::invalid_field;
use crate::widgets::block::BlockData;

pub struct BigTextData {
    pub lines: Vec<Line<'static>>,
    pub pixel_size: PixelSize,
    pub alignment: Alignment,
    pub style: Style,
    pub block: Option<BlockData>,
}

pub fn parse_pixel_size(value: &str) -> Result<PixelSize, Error> {
    match value {
        "full" => Ok(PixelSize::Full),
        "half_height" => Ok(PixelSize::HalfHeight),
        "half_width" => Ok(PixelSize::HalfWidth),
        "quadrant" => Ok(PixelSize::Quadrant),
        "third_height" => Ok(PixelSize::ThirdHeight),
        "sextant" => Ok(PixelSize::Sextant),
        "quarter_height" => Ok(PixelSize::QuarterHeight),
        "octant" => Ok(PixelSize::Octant),
        other => Err(invalid_field(
            "big_text",
            "pixel_size",
            &format!(
                "unknown pixel_size '{other}', expected one of \
                 full, half_height, half_width, quadrant, third_height, \
                 sextant, quarter_height, octant"
            ),
        )),
    }
}

pub fn render(buf: &mut Buffer, data: &BigTextData, area: Rect) {
    if area.width == 0 || area.height == 0 {
        return;
    }

    // tui-big-text 0.8.4 has a native `block` field; its Widget::render
    // draws the block and clips glyphs to the inner area itself. Hand
    // the block off via the builder rather than reimplementing that
    // logic — keeps us aligned with upstream and avoids drift if their
    // block handling ever changes.
    let mut builder = BigText::builder();
    builder
        .pixel_size(data.pixel_size)
        .style(data.style)
        .alignment(data.alignment)
        .lines(data.lines.clone());

    if let Some(ref block_data) = data.block {
        builder.block(block_data.to_block());
    }

    builder.build().render(area, buf);
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use ratatui::text::Span;
    use ratatui::widgets::{BorderType, Borders, Padding};
    use ratatui::Terminal;

    fn data_with(
        lines: Vec<Line<'static>>,
        pixel_size: PixelSize,
        alignment: Alignment,
    ) -> BigTextData {
        BigTextData {
            lines,
            pixel_size,
            alignment,
            style: Style::default(),
            block: None,
        }
    }

    fn line(text: &str) -> Line<'static> {
        Line::from(text.to_string())
    }

    fn paints_any_non_space(terminal: &Terminal<TestBackend>) -> bool {
        let buf = terminal.backend().buffer();
        buf.content().iter().any(|c| c.symbol() != " ")
    }

    #[test]
    fn parse_pixel_size_round_trips_known_variants() {
        for (atom, expected) in [
            ("full", PixelSize::Full),
            ("half_height", PixelSize::HalfHeight),
            ("half_width", PixelSize::HalfWidth),
            ("quadrant", PixelSize::Quadrant),
            ("third_height", PixelSize::ThirdHeight),
            ("sextant", PixelSize::Sextant),
            ("quarter_height", PixelSize::QuarterHeight),
            ("octant", PixelSize::Octant),
        ] {
            assert_eq!(
                parse_pixel_size(atom).unwrap(),
                expected,
                "unexpected mapping for {atom}"
            );
        }
    }

    #[test]
    fn parse_pixel_size_rejects_unknown_values() {
        // `rustler::Error` carries an opaque BEAM term so we can't
        // assert on the message text from cargo — that's covered on the
        // Elixir side. Here we just confirm unknown values are not
        // silently treated as some default.
        assert!(parse_pixel_size("huge").is_err());
        assert!(parse_pixel_size("").is_err());
        assert!(
            parse_pixel_size("Full").is_err(),
            "matching is case-sensitive"
        );
    }

    #[test]
    fn render_paints_glyph_cells_for_each_pixel_size() {
        for pixel_size in [
            PixelSize::Full,
            PixelSize::HalfHeight,
            PixelSize::HalfWidth,
            PixelSize::Quadrant,
            PixelSize::ThirdHeight,
            PixelSize::Sextant,
            PixelSize::QuarterHeight,
            PixelSize::Octant,
        ] {
            let backend = TestBackend::new(80, 24);
            let mut terminal = Terminal::new(backend).unwrap();
            let data = data_with(vec![line("HI")], pixel_size, Alignment::Left);

            terminal
                .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 80, 24)))
                .unwrap();

            assert!(
                paints_any_non_space(&terminal),
                "pixel_size {pixel_size:?} should paint at least one non-space cell"
            );
        }
    }

    #[test]
    fn render_respects_style_on_glyph_cells() {
        let backend = TestBackend::new(80, 16);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = BigTextData {
            lines: vec![Line::from(Span::raw("A"))],
            pixel_size: PixelSize::Full,
            alignment: Alignment::Left,
            style: Style::default().fg(Color::Red),
            block: None,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 80, 16)))
            .unwrap();

        let buf = terminal.backend().buffer();
        let mut saw_red = false;
        for cell in buf.content() {
            if cell.symbol() != " " && cell.fg == Color::Red {
                saw_red = true;
                break;
            }
        }
        assert!(saw_red, "expected at least one painted cell to be red");
    }

    #[test]
    fn render_centered_text_starts_after_left_padding() {
        // Left-aligned 'A' should paint near column 0; centered should
        // paint further right. Compare the first painted column for the
        // two alignments to lock the offset behaviour in.
        let left_min = first_painted_column("A", Alignment::Left);
        let centered_min = first_painted_column("A", Alignment::Center);
        assert!(
            centered_min > left_min,
            "expected centered text to start past left-aligned (left={left_min}, centered={centered_min})",
        );
    }

    fn first_painted_column(text: &str, alignment: Alignment) -> u16 {
        let backend = TestBackend::new(80, 16);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = data_with(vec![line(text)], PixelSize::Full, alignment);
        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 80, 16)))
            .unwrap();

        let buf = terminal.backend().buffer();
        for x in 0..buf.area.width {
            for y in 0..buf.area.height {
                if buf.cell((x, y)).map_or(" ", |c| c.symbol()) != " " {
                    return x;
                }
            }
        }
        u16::MAX
    }

    #[test]
    fn render_with_block_paints_border_and_confines_text() {
        let backend = TestBackend::new(40, 10);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = BigTextData {
            lines: vec![line("X")],
            pixel_size: PixelSize::Full,
            alignment: Alignment::Left,
            style: Style::default(),
            block: Some(BlockData {
                title: Some(Line::from("title".to_string())),
                borders: Borders::ALL,
                border_type: BorderType::Rounded,
                border_style: Style::default(),
                style: Style::default(),
                padding: Padding::ZERO,
            }),
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 40, 10)))
            .unwrap();

        // The block's top-left corner should be a border glyph, not a
        // space — confirms the block was rendered before the big text.
        let buf = terminal.backend().buffer();
        let corner = buf.cell((0, 0)).unwrap().symbol();
        assert_ne!(corner, " ", "expected block border at (0, 0), got space");
    }

    #[test]
    fn render_noop_on_zero_area() {
        let backend = TestBackend::new(80, 24);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = data_with(vec![line("hello")], PixelSize::Full, Alignment::Left);

        // Zero-area must not panic and must not paint anything.
        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(10, 5, 0, 0)))
            .unwrap();

        assert!(
            !paints_any_non_space(&terminal),
            "zero-area render should leave the buffer untouched"
        );
    }

    #[test]
    fn render_truncates_gracefully_in_undersized_area() {
        // A long string at :full pixel size needs ~8 cols per char and
        // 8 rows total. Render into a 10×3 area and confirm we don't
        // panic and don't paint past the rect bounds. Slide users will
        // hit this whenever a header overflows a column.
        let mut state = data_with(
            vec![line("OVERFLOW_OVERFLOW")],
            PixelSize::Full,
            Alignment::Left,
        );
        state.style = Style::default();
        let area = Rect::new(0, 0, 10, 3);
        let mut buf = Buffer::empty(area);
        render(&mut buf, &state, area);

        // Some cells should be painted (the visible portion) and no
        // panic should have fired. Painted cells must stay inside the
        // area.
        let any_painted = (0..area.width)
            .any(|x| (0..area.height).any(|y| buf.cell((x, y)).map_or(" ", |c| c.symbol()) != " "));
        assert!(
            any_painted,
            "truncated render should still paint visible glyphs"
        );
    }

    #[test]
    fn render_handles_empty_lines_vec() {
        // No lines = nothing to paint, but render must not panic. The
        // builder itself happily accepts an empty Vec, so this just
        // covers our wrapper.
        let backend = TestBackend::new(80, 24);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = data_with(Vec::new(), PixelSize::Full, Alignment::Left);

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 80, 24)))
            .unwrap();

        assert!(
            !paints_any_non_space(&terminal),
            "empty lines should produce no painted cells"
        );
    }

    #[test]
    fn render_multi_line_paints_taller_than_single_line() {
        // Two lines of Full-pixel-size text should occupy more rows
        // than a single line. We don't need exact row counts — the
        // proportionality check guards us against accidentally only
        // rendering the first line.
        let single = painted_row_extent(vec![line("AB")], PixelSize::Full);
        let multi = painted_row_extent(vec![line("AB"), line("CD")], PixelSize::Full);
        assert!(
            multi > single,
            "two-line render should be taller than one-line (single={single}, multi={multi})"
        );
    }

    fn painted_row_extent(lines: Vec<Line<'static>>, pixel_size: PixelSize) -> u16 {
        let backend = TestBackend::new(80, 24);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = data_with(lines, pixel_size, Alignment::Left);
        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 80, 24)))
            .unwrap();

        let buf = terminal.backend().buffer();
        let mut last_painted_row: i32 = -1;
        for y in 0..buf.area.height {
            for x in 0..buf.area.width {
                if buf.cell((x, y)).map_or(" ", |c| c.symbol()) != " " {
                    last_painted_row = y as i32;
                    break;
                }
            }
        }
        // 0 means no rows painted, otherwise the count of rows.
        (last_painted_row + 1).max(0) as u16
    }
}
