//! Shared syntect-backed highlighter for `CodeBlock` (and, later, the
//! standalone `highlight/3` helper).
//!
//! Loads syntect's bundled `SyntaxSet` and `ThemeSet` once and serves every
//! call. Unknown languages fall through to plain text; unknown themes fall
//! back to `base16-ocean.dark`.
//!
//! The `translate_*` helpers are adapted from MIT-licensed `syntect-tui`
//! (https://crates.io/crates/syntect-tui) — inlined here because syntect-tui
//! is pinned to older ratatui versions while this project tracks 0.30.

use ratatui::style::{Color, Modifier, Style as RStyle};
use ratatui::text::{Line, Span};
use std::sync::OnceLock;
use syntect::easy::HighlightLines;
use syntect::highlighting::{Color as SColor, FontStyle, Style as SStyle, ThemeSet};
use syntect::parsing::{SyntaxDefinition, SyntaxSet};
use syntect::util::LinesWithEndings;

static SYNTAX_SET: OnceLock<SyntaxSet> = OnceLock::new();
static THEME_SET: OnceLock<ThemeSet> = OnceLock::new();

/// Languages bundled by us on top of syntect's defaults. See
/// `native/ex_ratatui/syntaxes/README.md` for licensing and the add-a-language
/// procedure.
const ELIXIR_SYNTAX: &str = include_str!("../../syntaxes/Elixir.sublime-syntax");

fn syntaxes() -> &'static SyntaxSet {
    SYNTAX_SET.get_or_init(|| {
        let mut builder = SyntaxSet::load_defaults_newlines().into_builder();

        let elixir = SyntaxDefinition::load_from_str(ELIXIR_SYNTAX, true, None)
            .expect("bundled Elixir.sublime-syntax must parse");
        builder.add(elixir);

        builder.build()
    })
}

fn themes() -> &'static ThemeSet {
    THEME_SET.get_or_init(ThemeSet::load_defaults)
}

/// Theme background color — used as the base when emphasising line ranges.
pub fn theme_bg(theme_name: &str) -> Option<Color> {
    let theme = themes().themes.get(theme_name)?;
    theme.settings.background.map(|c| Color::Rgb(c.r, c.g, c.b))
}

/// Highlight `code` for the given `language` token (`"elixir"`, `"rust"`…).
/// Returns one `Line` per source line. Unknown languages fall back to plain
/// text. Unknown themes fall back to `base16-ocean.dark`.
pub fn lines_for(code: &str, language: Option<&str>, theme_name: &str) -> Vec<Line<'static>> {
    let syntax_set = syntaxes();
    let syntax = language
        .and_then(|l| syntax_set.find_syntax_by_token(l))
        .unwrap_or_else(|| syntax_set.find_syntax_plain_text());

    let theme_set = themes();
    let theme = theme_set
        .themes
        .get(theme_name)
        .or_else(|| theme_set.themes.get("base16-ocean.dark"))
        .expect("syntect ThemeSet missing base16-ocean.dark fallback");

    let mut h = HighlightLines::new(syntax, theme);

    LinesWithEndings::from(code)
        .map(|line_text| {
            let segments = h.highlight_line(line_text, syntax_set).unwrap_or_default();
            let spans: Vec<Span<'static>> = segments
                .into_iter()
                .map(|(s_style, s)| Span::styled(s.to_string(), translate_style(s_style)))
                .collect();
            Line::from(spans)
        })
        .collect()
}

fn translate_style(s: SStyle) -> RStyle {
    RStyle {
        fg: translate_color(s.foreground),
        bg: translate_color(s.background),
        underline_color: translate_color(s.foreground),
        add_modifier: translate_font_style(s.font_style),
        sub_modifier: Modifier::empty(),
    }
}

fn translate_color(c: SColor) -> Option<Color> {
    if c.a > 0 {
        Some(Color::Rgb(c.r, c.g, c.b))
    } else {
        None
    }
}

fn translate_font_style(fs: FontStyle) -> Modifier {
    let mut m = Modifier::empty();
    if fs.contains(FontStyle::BOLD) {
        m |= Modifier::BOLD;
    }
    if fs.contains(FontStyle::ITALIC) {
        m |= Modifier::ITALIC;
    }
    if fs.contains(FontStyle::UNDERLINE) {
        m |= Modifier::UNDERLINED;
    }
    m
}
