use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Paragraph, Widget, Wrap};

use crate::widgets::block::BlockData;
use crate::widgets::highlighter;

pub struct CodeBlockData {
    pub content: String,
    pub language: Option<String>,
    pub theme: String,
    pub line_numbers: bool,
    pub starting_line: usize,
    pub highlight_lines: Vec<usize>,
    pub style: Style,
    pub block: Option<BlockData>,
    pub scroll: (u16, u16),
    pub wrap: bool,
}

pub fn render(buf: &mut Buffer, data: &CodeBlockData, area: Rect) {
    let lines = highlighter::lines_for(&data.content, data.language.as_deref(), &data.theme);

    let lines = if data.line_numbers {
        prepend_gutter(lines, data.starting_line)
    } else {
        lines
    };

    let lines = if data.highlight_lines.is_empty() {
        lines
    } else {
        apply_emphasis(
            lines,
            data.starting_line,
            &data.highlight_lines,
            &data.theme,
        )
    };

    let mut widget = Paragraph::new(Text::from(lines)).style(data.style);

    if data.wrap {
        widget = widget.wrap(Wrap { trim: false });
    }

    if data.scroll != (0, 0) {
        widget = widget.scroll(data.scroll);
    }

    if let Some(ref block_data) = data.block {
        widget = widget.block(block_data.to_block());
    }

    widget.render(area, buf);
}

fn apply_emphasis(
    lines: Vec<Line<'static>>,
    starting_line: usize,
    highlight_lines: &[usize],
    theme: &str,
) -> Vec<Line<'static>> {
    let bg = highlighter::theme_bg(theme)
        .map(lift_background)
        .unwrap_or(Color::DarkGray);
    let emphasis = Style::default().bg(bg);

    lines
        .into_iter()
        .enumerate()
        .map(|(i, mut line)| {
            let line_no = starting_line + i;
            if highlight_lines.binary_search(&line_no).is_ok() {
                // Line::patch_style only updates the Line's default style,
                // which fills trailing cells. The spans painted by syntect
                // already carry the theme bg, so override each span's bg
                // explicitly so the emphasis covers content cells too.
                line.spans = line
                    .spans
                    .into_iter()
                    .map(|span| span.patch_style(emphasis))
                    .collect();
                line.style = line.style.patch(emphasis);
            }
            line
        })
        .collect()
}

fn lift_background(c: Color) -> Color {
    // Nudge each channel toward the opposite end so the emphasis stands out
    // for both dark and light themes. ~20/256 step is subtle but visible.
    match c {
        Color::Rgb(r, g, b) => {
            let avg = (u16::from(r) + u16::from(g) + u16::from(b)) / 3;
            if avg < 128 {
                Color::Rgb(
                    r.saturating_add(20),
                    g.saturating_add(20),
                    b.saturating_add(20),
                )
            } else {
                Color::Rgb(
                    r.saturating_sub(20),
                    g.saturating_sub(20),
                    b.saturating_sub(20),
                )
            }
        }
        other => other,
    }
}

fn prepend_gutter(lines: Vec<Line<'static>>, starting_line: usize) -> Vec<Line<'static>> {
    let total = lines.len();
    if total == 0 {
        return lines;
    }
    let last = starting_line.saturating_add(total).saturating_sub(1);
    let width = last.to_string().len();
    let gutter_style = Style::default().add_modifier(Modifier::DIM);

    lines
        .into_iter()
        .enumerate()
        .map(|(i, line)| {
            let n = starting_line + i;
            let prefix = format!("{:>width$} │ ", n, width = width);
            let mut spans = vec![Span::styled(prefix, gutter_style)];
            spans.extend(line.spans);
            Line::from(spans)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_line;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    fn make(content: &str, language: Option<&str>) -> CodeBlockData {
        CodeBlockData {
            content: content.to_string(),
            language: language.map(String::from),
            theme: "base16-ocean.dark".to_string(),
            line_numbers: false,
            starting_line: 1,
            highlight_lines: Vec::new(),
            style: Style::default(),
            block: None,
            scroll: (0, 0),
            wrap: false,
        }
    }

    #[test]
    fn renders_plain_when_language_nil() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make("hello world", None);
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();
        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("hello world"), "got: {line}");
    }

    #[test]
    fn renders_elixir_source_text() {
        let backend = TestBackend::new(60, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make("defmodule X do end", Some("elixir"));
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 60, 5)))
            .unwrap();
        let line = buffer_line(&terminal, 0, 60);
        assert!(line.contains("defmodule"), "got: {line}");
    }

    #[test]
    fn elixir_produces_distinct_colors() {
        let backend = TestBackend::new(60, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make("defmodule X do\n  def hi, do: :ok\nend", Some("elixir"));
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 60, 5)))
            .unwrap();

        let buffer = terminal.backend().buffer();
        let mut colors = std::collections::HashSet::new();
        for y in 0..3 {
            for x in 0..60 {
                if let Some(cell) = buffer.cell((x, y)) {
                    colors.insert(format!("{:?}", cell.fg));
                }
            }
        }
        assert!(colors.len() >= 2, "expected >=2 fg colors, got {colors:?}");
    }

    #[test]
    fn unknown_language_falls_back_to_plain() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = make("anything goes", Some("not-a-language"));
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();
        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("anything goes"), "got: {line}");
    }

    #[test]
    fn renders_with_block() {
        let backend = TestBackend::new(40, 10);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = CodeBlockData {
            block: Some(BlockData {
                title: Some(ratatui::text::Line::from("code")),
                borders: ratatui::widgets::Borders::ALL,
                border_type: ratatui::widgets::BorderType::Rounded,
                border_style: Style::default(),
                style: Style::default(),
                padding: ratatui::widgets::Padding::ZERO,
            }),
            ..make("x = 1", Some("elixir"))
        };
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 40, 10)))
            .unwrap();
        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("code"), "got: {line}");
    }

    #[test]
    fn unknown_theme_falls_back_silently() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut data = make("x", Some("elixir"));
        data.theme = "not-a-theme".to_string();
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();
        let line = buffer_line(&terminal, 0, 40);
        assert!(line.contains("x"), "got: {line}");
    }

    #[test]
    fn line_numbers_renders_gutter() {
        let backend = TestBackend::new(60, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = CodeBlockData {
            line_numbers: true,
            starting_line: 1,
            ..make("a\nb\nc", None)
        };
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 60, 5)))
            .unwrap();

        assert!(buffer_line(&terminal, 0, 60).starts_with("1 │"));
        assert!(buffer_line(&terminal, 1, 60).starts_with("2 │"));
        assert!(buffer_line(&terminal, 2, 60).starts_with("3 │"));
    }

    #[test]
    fn starting_line_offset_applied_with_width() {
        let backend = TestBackend::new(60, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = CodeBlockData {
            line_numbers: true,
            starting_line: 100,
            ..make("a\nb", None)
        };
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 60, 5)))
            .unwrap();

        assert!(buffer_line(&terminal, 0, 60).starts_with("100 │"));
        assert!(buffer_line(&terminal, 1, 60).starts_with("101 │"));
    }

    #[test]
    fn line_numbers_width_grows_for_larger_files() {
        let backend = TestBackend::new(60, 12);
        let mut terminal = Terminal::new(backend).unwrap();
        // last line will be number 12 → width 2 → " 1 │", " 9 │", "12 │"
        let data = CodeBlockData {
            line_numbers: true,
            starting_line: 1,
            ..make("a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl", None)
        };
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 60, 12)))
            .unwrap();

        assert!(buffer_line(&terminal, 0, 60).starts_with(" 1 │"));
        assert!(buffer_line(&terminal, 11, 60).starts_with("12 │"));
    }

    #[test]
    fn empty_content_with_line_numbers_does_not_panic() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = CodeBlockData {
            line_numbers: true,
            ..make("", None)
        };
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();
    }

    #[test]
    fn highlight_lines_tints_targeted_lines_only() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = CodeBlockData {
            highlight_lines: vec![2],
            ..make("a\nb\nc", None)
        };
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();

        let buffer = terminal.backend().buffer();
        let bg = |y: u16| buffer.cell((0, y)).map(|c| c.bg);
        assert_ne!(bg(0), bg(1), "line 2 bg should differ from line 1");
        assert_eq!(bg(0), bg(2), "lines 1 and 3 should share bg");
    }

    #[test]
    fn highlight_lines_pairs_with_starting_line() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = CodeBlockData {
            starting_line: 10,
            highlight_lines: vec![11],
            ..make("a\nb\nc", None)
        };
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();

        let buffer = terminal.backend().buffer();
        let bg = |y: u16| buffer.cell((0, y)).map(|c| c.bg);
        // starting_line 10 → row 0 is line 10, row 1 is line 11 (highlighted)
        assert_ne!(bg(0), bg(1));
        assert_eq!(bg(0), bg(2));
    }

    #[test]
    fn empty_highlight_lines_leaves_lines_untouched() {
        let backend = TestBackend::new(40, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = CodeBlockData {
            highlight_lines: vec![],
            ..make("a\nb\nc", None)
        };
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 40, 5)))
            .unwrap();

        let buffer = terminal.backend().buffer();
        let bg = |y: u16| buffer.cell((0, y)).map(|c| c.bg);
        assert_eq!(bg(0), bg(1));
        assert_eq!(bg(1), bg(2));
    }

    #[test]
    fn lift_background_brightens_dark_and_dims_light() {
        // Dark theme bg → channels go up
        assert_eq!(
            lift_background(Color::Rgb(10, 10, 10)),
            Color::Rgb(30, 30, 30)
        );
        // Light theme bg → channels go down
        assert_eq!(
            lift_background(Color::Rgb(240, 240, 240)),
            Color::Rgb(220, 220, 220)
        );
        // Non-RGB colors pass through
        assert_eq!(lift_background(Color::DarkGray), Color::DarkGray);
    }

    #[test]
    fn wrap_and_scroll_apply() {
        let backend = TestBackend::new(20, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let data = CodeBlockData {
            scroll: (1, 0),
            wrap: true,
            ..make("aaaaaaaaaa\nbbbbb\nccccc", None)
        };
        terminal
            .draw(|f| render(f.buffer_mut(), &data, Rect::new(0, 0, 20, 5)))
            .unwrap();
        // After scrolling 1 line down, line "bbbbb" should be at top
        let line = buffer_line(&terminal, 0, 20);
        assert!(line.contains("bbbbb"), "got: {line}");
    }
}
