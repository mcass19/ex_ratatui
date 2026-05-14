//! Public NIF for raw syntax-highlighting.
//!
//! Returns per-line lists of styled spans for users composing their own
//! widgets (DiffViewer, Inspector, …) without instantiating a full
//! `CodeBlock`. The widget itself does not use this path — it calls
//! [`crate::widgets::highlighter::lines_for`] directly and stays in Rust.

use ratatui::style::{Color, Modifier};
use rustler::NifMap;

use crate::widgets::highlighter;

#[derive(NifMap)]
pub struct HighlightedSpan {
    pub content: String,
    /// `None` for the theme's default; `Some((r, g, b))` for an explicit RGB.
    pub fg: Option<(u8, u8, u8)>,
    pub bg: Option<(u8, u8, u8)>,
    pub bold: bool,
    pub italic: bool,
    pub underlined: bool,
}

#[rustler::nif(schedule = "DirtyCpu")]
fn highlight_code(
    code: String,
    language: Option<String>,
    theme: String,
) -> Vec<Vec<HighlightedSpan>> {
    highlighter::lines_for(&code, language.as_deref(), &theme)
        .into_iter()
        .map(|line| line.spans.into_iter().map(span_to_term).collect())
        .collect()
}

fn span_to_term(span: ratatui::text::Span<'static>) -> HighlightedSpan {
    let style = span.style;
    let modifier = style.add_modifier;

    HighlightedSpan {
        content: span.content.into_owned(),
        fg: color_to_rgb(style.fg),
        bg: color_to_rgb(style.bg),
        bold: modifier.contains(Modifier::BOLD),
        italic: modifier.contains(Modifier::ITALIC),
        underlined: modifier.contains(Modifier::UNDERLINED),
    }
}

fn color_to_rgb(c: Option<Color>) -> Option<(u8, u8, u8)> {
    match c {
        Some(Color::Rgb(r, g, b)) => Some((r, g, b)),
        _ => None,
    }
}
