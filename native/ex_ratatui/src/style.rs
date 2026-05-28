use ratatui::style::{Color, Modifier, Style};
use rustler::{Encoder, Env, Error, Term};
use std::collections::HashMap;

/// Atoms used by the encoder side (Rust → Elixir) when surfacing styles
/// extracted from a rendered buffer.
///
/// Kept in their own module so it's obvious which atoms are part of the
/// public on-the-wire vocabulary. They match `ExRatatui.Style`'s
/// vocabulary verbatim — named colors as atoms, RGB/indexed as tagged
/// tuples, modifiers as a list of atoms.
mod style_atoms {
    rustler::atoms! {
        // Named colors (mirror of the parse_named_color cases below).
        black,
        red,
        green,
        yellow,
        blue,
        magenta,
        cyan,
        gray,
        dark_gray,
        light_red,
        light_green,
        light_yellow,
        light_blue,
        light_magenta,
        light_cyan,
        white,
        reset,
        // Tagged-tuple discriminators for RGB/indexed colors.
        rgb,
        indexed,
        // Modifier names (mirror of parse_modifier).
        bold,
        dim,
        italic,
        underlined,
        crossed_out,
        reversed,
    }
}

/// Decode an Elixir style map into a ratatui Style.
///
/// Expects a string-keyed map with optional "fg", "bg", and "modifiers" keys.
pub fn decode_style(term: Term) -> Result<Style, Error> {
    let map: HashMap<String, Term> = term.decode()?;
    let mut style = Style::default();

    if let Some(fg_term) = map.get("fg") {
        style = style.fg(decode_color(*fg_term)?);
    }

    if let Some(bg_term) = map.get("bg") {
        style = style.bg(decode_color(*bg_term)?);
    }

    if let Some(uc_term) = map.get("underline_color") {
        style = style.underline_color(decode_color(*uc_term)?);
    }

    if let Some(mods_term) = map.get("modifiers") {
        let mod_names: Vec<String> = mods_term.decode()?;
        for name in &mod_names {
            style = style.add_modifier(parse_modifier(name)?);
        }
    }

    Ok(style)
}

pub fn decode_color(term: Term) -> Result<Color, Error> {
    // Try as a string (named color)
    if let Ok(name) = term.decode::<String>() {
        return parse_named_color(&name);
    }

    // Try as a map (rgb or indexed)
    if let Ok(map) = term.decode::<HashMap<String, Term>>() {
        let color_type: String = map
            .get("type")
            .ok_or_else(|| Error::Term(Box::new("color map missing 'type'")))?
            .decode()?;

        return match color_type.as_str() {
            "rgb" => {
                let r: u8 = map
                    .get("r")
                    .ok_or_else(|| Error::Term(Box::new("rgb missing 'r'")))?
                    .decode()?;
                let g: u8 = map
                    .get("g")
                    .ok_or_else(|| Error::Term(Box::new("rgb missing 'g'")))?
                    .decode()?;
                let b: u8 = map
                    .get("b")
                    .ok_or_else(|| Error::Term(Box::new("rgb missing 'b'")))?
                    .decode()?;
                Ok(Color::Rgb(r, g, b))
            }
            "indexed" => {
                let i: u8 = map
                    .get("value")
                    .ok_or_else(|| Error::Term(Box::new("indexed missing 'value'")))?
                    .decode()?;
                Ok(Color::Indexed(i))
            }
            other => Err(Error::Term(Box::new(format!(
                "unknown color type: {other}"
            )))),
        };
    }

    Err(Error::Term(Box::new("invalid color value")))
}

/// Parse a named color string into a ratatui Color.
pub fn parse_named_color(name: &str) -> Result<Color, Error> {
    match name {
        "black" => Ok(Color::Black),
        "red" => Ok(Color::Red),
        "green" => Ok(Color::Green),
        "yellow" => Ok(Color::Yellow),
        "blue" => Ok(Color::Blue),
        "magenta" => Ok(Color::Magenta),
        "cyan" => Ok(Color::Cyan),
        "gray" => Ok(Color::Gray),
        "dark_gray" => Ok(Color::DarkGray),
        "light_red" => Ok(Color::LightRed),
        "light_green" => Ok(Color::LightGreen),
        "light_yellow" => Ok(Color::LightYellow),
        "light_blue" => Ok(Color::LightBlue),
        "light_magenta" => Ok(Color::LightMagenta),
        "light_cyan" => Ok(Color::LightCyan),
        "white" => Ok(Color::White),
        "reset" => Ok(Color::Reset),
        other => Err(Error::Term(Box::new(format!("unknown color: {other}")))),
    }
}

/// Encode a ratatui [`Color`] into a `Term` using the same shape
/// `ExRatatui.Style` colors take in Elixir:
///
///   * `Color::Reset` and the 16 named colors → atoms (`:reset`, `:red`, ...)
///   * `Color::Rgb(r, g, b)` → `{:rgb, r, g, b}` tagged tuple
///   * `Color::Indexed(i)` → `{:indexed, i}` tagged tuple
///
/// This is the inverse of [`decode_color`] for the named/Rgb/Indexed cases.
/// It is **not** a perfect round-trip: `decode_color` accepts string keys
/// (e.g. `"red"`) for cross-language compatibility, while we always emit
/// atoms here because that's what the rest of the Elixir API uses.
pub fn encode_color<'a>(env: Env<'a>, color: Color) -> Term<'a> {
    match color {
        Color::Reset => style_atoms::reset().encode(env),
        Color::Black => style_atoms::black().encode(env),
        Color::Red => style_atoms::red().encode(env),
        Color::Green => style_atoms::green().encode(env),
        Color::Yellow => style_atoms::yellow().encode(env),
        Color::Blue => style_atoms::blue().encode(env),
        Color::Magenta => style_atoms::magenta().encode(env),
        Color::Cyan => style_atoms::cyan().encode(env),
        Color::Gray => style_atoms::gray().encode(env),
        Color::DarkGray => style_atoms::dark_gray().encode(env),
        Color::LightRed => style_atoms::light_red().encode(env),
        Color::LightGreen => style_atoms::light_green().encode(env),
        Color::LightYellow => style_atoms::light_yellow().encode(env),
        Color::LightBlue => style_atoms::light_blue().encode(env),
        Color::LightMagenta => style_atoms::light_magenta().encode(env),
        Color::LightCyan => style_atoms::light_cyan().encode(env),
        Color::White => style_atoms::white().encode(env),
        Color::Rgb(r, g, b) => (style_atoms::rgb(), r, g, b).encode(env),
        Color::Indexed(i) => (style_atoms::indexed(), i).encode(env),
    }
}

/// Encode a ratatui [`Modifier`] bitflag set into a list of atoms in a
/// stable, sorted-by-name order so consumers can compare two encoded
/// modifier lists for equality without normalising first.
///
/// The order matches the way modifiers are listed in `ExRatatui.Style`'s
/// docs (`:bold, :dim, :italic, :underlined, :crossed_out, :reversed`),
/// which is the order ratatui's own [`Modifier`] bitflag definitions use.
pub fn encode_modifiers<'a>(env: Env<'a>, modifier: Modifier) -> Term<'a> {
    let mut mods: Vec<rustler::Atom> = Vec::with_capacity(6);
    if modifier.contains(Modifier::BOLD) {
        mods.push(style_atoms::bold());
    }
    if modifier.contains(Modifier::DIM) {
        mods.push(style_atoms::dim());
    }
    if modifier.contains(Modifier::ITALIC) {
        mods.push(style_atoms::italic());
    }
    if modifier.contains(Modifier::UNDERLINED) {
        mods.push(style_atoms::underlined());
    }
    if modifier.contains(Modifier::CROSSED_OUT) {
        mods.push(style_atoms::crossed_out());
    }
    if modifier.contains(Modifier::REVERSED) {
        mods.push(style_atoms::reversed());
    }
    mods.encode(env)
}

/// Parse a modifier name string into a ratatui Modifier.
pub fn parse_modifier(name: &str) -> Result<Modifier, Error> {
    match name {
        "bold" => Ok(Modifier::BOLD),
        "dim" => Ok(Modifier::DIM),
        "italic" => Ok(Modifier::ITALIC),
        "underlined" => Ok(Modifier::UNDERLINED),
        "crossed_out" => Ok(Modifier::CROSSED_OUT),
        "reversed" => Ok(Modifier::REVERSED),
        other => Err(Error::Term(Box::new(format!("unknown modifier: {other}")))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_all_named_colors() {
        let cases = vec![
            ("black", Color::Black),
            ("red", Color::Red),
            ("green", Color::Green),
            ("yellow", Color::Yellow),
            ("blue", Color::Blue),
            ("magenta", Color::Magenta),
            ("cyan", Color::Cyan),
            ("gray", Color::Gray),
            ("dark_gray", Color::DarkGray),
            ("light_red", Color::LightRed),
            ("light_green", Color::LightGreen),
            ("light_yellow", Color::LightYellow),
            ("light_blue", Color::LightBlue),
            ("light_magenta", Color::LightMagenta),
            ("light_cyan", Color::LightCyan),
            ("white", Color::White),
            ("reset", Color::Reset),
        ];

        for (name, expected) in cases {
            assert_eq!(
                parse_named_color(name).unwrap(),
                expected,
                "failed for color: {name}"
            );
        }
    }

    #[test]
    fn test_parse_unknown_color_returns_error() {
        assert!(parse_named_color("neon_pink").is_err());
    }

    #[test]
    fn test_parse_all_modifiers() {
        let cases = vec![
            ("bold", Modifier::BOLD),
            ("dim", Modifier::DIM),
            ("italic", Modifier::ITALIC),
            ("underlined", Modifier::UNDERLINED),
            ("crossed_out", Modifier::CROSSED_OUT),
            ("reversed", Modifier::REVERSED),
        ];

        for (name, expected) in cases {
            assert_eq!(
                parse_modifier(name).unwrap(),
                expected,
                "failed for modifier: {name}"
            );
        }
    }

    #[test]
    fn test_parse_unknown_modifier_returns_error() {
        assert!(parse_modifier("blink").is_err());
    }
}
