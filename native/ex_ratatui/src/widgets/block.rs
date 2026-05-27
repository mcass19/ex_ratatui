use ratatui::buffer::Buffer;
use ratatui::layout::{Alignment, Rect};
use ratatui::style::Style;
use ratatui::text::Line;
use ratatui::widgets::{Block, BorderType, Borders, Padding, TitlePosition, Widget};
use rustler::{Error, Term};
use std::collections::HashMap;

use crate::style::decode_style;
use crate::text;

#[derive(Clone)]
pub struct TitleData {
    pub line: Line<'static>,
    pub position: Option<TitlePosition>,
    pub alignment: Option<Alignment>,
    pub style: Option<Style>,
}

#[derive(Clone)]
pub struct BlockData {
    pub title: Option<Line<'static>>,
    pub titles: Vec<TitleData>,
    pub title_position: TitlePosition,
    pub title_alignment: Alignment,
    pub title_style: Option<Style>,
    pub borders: Borders,
    pub border_style: Style,
    pub border_type: BorderType,
    pub style: Style,
    pub padding: Padding,
}

impl Default for BlockData {
    fn default() -> Self {
        Self {
            title: None,
            titles: Vec::new(),
            title_position: TitlePosition::Top,
            title_alignment: Alignment::Left,
            title_style: None,
            borders: Borders::NONE,
            border_style: Style::default(),
            border_type: BorderType::Plain,
            style: Style::default(),
            padding: Padding::ZERO,
        }
    }
}

impl BlockData {
    pub fn to_block(&self) -> Block<'_> {
        let mut block = Block::default()
            .borders(self.borders)
            .border_style(self.border_style)
            .border_type(self.border_type)
            .style(self.style)
            .padding(self.padding)
            .title_position(self.title_position)
            .title_alignment(self.title_alignment);

        if let Some(style) = self.title_style {
            block = block.title_style(style);
        }

        if let Some(ref title) = self.title {
            block = block.title(title.clone());
        }

        for title in &self.titles {
            let mut line = title.line.clone();

            // Per-title style overrides the block's title_style for this
            // particular title only. Apply by merging into the line's
            // style — ratatui's per-title style API works on `Line`.
            if let Some(style) = title.style {
                line = line.patch_style(style);
            }

            // Per-title alignment is carried on the `Line` itself; the
            // block's default title_alignment applies when the line has
            // no alignment of its own.
            let line = match title.alignment {
                Some(Alignment::Left) => line.left_aligned(),
                Some(Alignment::Center) => line.centered(),
                Some(Alignment::Right) => line.right_aligned(),
                None => line,
            };

            block = match title.position {
                Some(TitlePosition::Top) => block.title_top(line),
                Some(TitlePosition::Bottom) => block.title_bottom(line),
                None => block.title(line),
            };
        }

        block
    }
}

pub fn render(buf: &mut Buffer, data: &BlockData, area: Rect) {
    data.to_block().render(area, buf);
}

pub fn decode_block(term: Term) -> Result<BlockData, Error> {
    let map: HashMap<String, Term> = term.decode()?;
    decode_block_from_map(&map)
}

pub fn decode_block_from_map(map: &HashMap<String, Term>) -> Result<BlockData, Error> {
    let title = match map.get("title") {
        Some(term) => Some(text::decode_line(*term)?),
        None => None,
    };

    let titles = match map.get("titles") {
        Some(term) => {
            let entries: Vec<HashMap<String, Term>> = term.decode()?;
            entries
                .iter()
                .map(decode_title)
                .collect::<Result<Vec<_>, _>>()?
        }
        None => Vec::new(),
    };

    let title_position = match map.get("title_position") {
        Some(term) => {
            let s: String = term.decode()?;
            parse_title_position(&s)?
        }
        None => TitlePosition::Top,
    };

    let title_alignment = match map.get("title_alignment") {
        Some(term) => {
            let s: String = term.decode()?;
            parse_alignment(&s)?
        }
        None => Alignment::Left,
    };

    let title_style = match map.get("title_style") {
        Some(term) => Some(decode_style(*term)?),
        None => None,
    };

    let borders = match map.get("borders") {
        Some(term) => {
            let names: Vec<String> = term.decode()?;
            parse_borders(&names)?
        }
        None => Borders::NONE,
    };

    let border_style = match map.get("border_style") {
        Some(term) => decode_style(*term)?,
        None => Style::default(),
    };

    let border_type = match map.get("border_type") {
        Some(term) => {
            let s: String = term.decode()?;
            parse_border_type(&s)?
        }
        None => BorderType::Plain,
    };

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => Style::default(),
    };

    let left: u16 = match map.get("padding_left") {
        Some(term) => term.decode()?,
        None => 0,
    };
    let right: u16 = match map.get("padding_right") {
        Some(term) => term.decode()?,
        None => 0,
    };
    let top: u16 = match map.get("padding_top") {
        Some(term) => term.decode()?,
        None => 0,
    };
    let bottom: u16 = match map.get("padding_bottom") {
        Some(term) => term.decode()?,
        None => 0,
    };

    Ok(BlockData {
        title,
        titles,
        title_position,
        title_alignment,
        title_style,
        borders,
        border_style,
        border_type,
        style,
        padding: Padding::new(left, right, top, bottom),
    })
}

fn decode_title(map: &HashMap<String, Term>) -> Result<TitleData, Error> {
    let content_term = map
        .get("content")
        .ok_or_else(|| Error::Term(Box::new("block title missing :content".to_string())))?;
    let line = text::decode_line(*content_term)?;

    let position = match map.get("position") {
        Some(term) => {
            let s: String = term.decode()?;
            Some(parse_title_position(&s)?)
        }
        None => None,
    };

    let alignment = match map.get("alignment") {
        Some(term) => {
            let s: String = term.decode()?;
            Some(parse_alignment(&s)?)
        }
        None => None,
    };

    let style = match map.get("style") {
        Some(term) => Some(decode_style(*term)?),
        None => None,
    };

    Ok(TitleData {
        line,
        position,
        alignment,
        style,
    })
}

fn parse_title_position(s: &str) -> Result<TitlePosition, Error> {
    match s {
        "top" => Ok(TitlePosition::Top),
        "bottom" => Ok(TitlePosition::Bottom),
        other => Err(Error::Term(Box::new(format!(
            "unknown title position: {other}"
        )))),
    }
}

fn parse_alignment(s: &str) -> Result<Alignment, Error> {
    match s {
        "left" => Ok(Alignment::Left),
        "center" => Ok(Alignment::Center),
        "right" => Ok(Alignment::Right),
        other => Err(Error::Term(Box::new(format!("unknown alignment: {other}")))),
    }
}

pub fn parse_borders(names: &[String]) -> Result<Borders, Error> {
    let mut borders = Borders::NONE;
    for name in names {
        borders |= match name.as_str() {
            "all" => Borders::ALL,
            "top" => Borders::TOP,
            "right" => Borders::RIGHT,
            "bottom" => Borders::BOTTOM,
            "left" => Borders::LEFT,
            other => return Err(Error::Term(Box::new(format!("unknown border: {other}")))),
        };
    }
    Ok(borders)
}

pub fn parse_border_type(s: &str) -> Result<BorderType, Error> {
    match s {
        "plain" => Ok(BorderType::Plain),
        "rounded" => Ok(BorderType::Rounded),
        "double" => Ok(BorderType::Double),
        "thick" => Ok(BorderType::Thick),
        other => Err(Error::Term(Box::new(format!(
            "unknown border type: {other}"
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
    fn test_render_block_with_all_borders() {
        let backend = TestBackend::new(10, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = BlockData {
            title: None,
            titles: Vec::new(),
            title_position: TitlePosition::Top,
            title_alignment: Alignment::Left,
            title_style: None,
            borders: Borders::ALL,
            border_style: Style::default(),
            border_type: BorderType::Plain,
            style: Style::default(),
            padding: Padding::ZERO,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 10, 5)))
            .unwrap();

        let top = buffer_line(&terminal, 0, 10);
        assert!(top.starts_with('┌'));
        assert!(top.ends_with('┐'));

        let bottom = buffer_line(&terminal, 4, 10);
        assert!(bottom.starts_with('└'));
        assert!(bottom.ends_with('┘'));
    }

    #[test]
    fn test_render_block_with_title() {
        let backend = TestBackend::new(20, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = BlockData {
            title: Some(Line::from("Hello")),
            titles: Vec::new(),
            title_position: TitlePosition::Top,
            title_alignment: Alignment::Left,
            title_style: None,
            borders: Borders::ALL,
            border_style: Style::default(),
            border_type: BorderType::Plain,
            style: Style::default(),
            padding: Padding::ZERO,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 5)))
            .unwrap();

        let top = buffer_line(&terminal, 0, 20);
        assert!(top.contains("Hello"));
    }

    #[test]
    fn test_render_block_rounded_borders() {
        let backend = TestBackend::new(10, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = BlockData {
            title: None,
            titles: Vec::new(),
            title_position: TitlePosition::Top,
            title_alignment: Alignment::Left,
            title_style: None,
            borders: Borders::ALL,
            border_style: Style::default(),
            border_type: BorderType::Rounded,
            style: Style::default(),
            padding: Padding::ZERO,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 10, 3)))
            .unwrap();

        let buf = terminal.backend().buffer();
        assert_eq!(buf.cell((0, 0)).unwrap().symbol(), "╭");
        assert_eq!(buf.cell((9, 0)).unwrap().symbol(), "╮");
        assert_eq!(buf.cell((0, 2)).unwrap().symbol(), "╰");
        assert_eq!(buf.cell((9, 2)).unwrap().symbol(), "╯");
    }

    #[test]
    fn test_render_block_with_rich_text_title() {
        use ratatui::style::Modifier;
        use ratatui::text::Span;

        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let title = Line::from(vec![
            Span::styled(" ok ", Style::default().fg(Color::Green)),
            Span::styled(
                "Build",
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
        ]);

        let data = BlockData {
            title: Some(title),
            titles: Vec::new(),
            title_position: TitlePosition::Top,
            title_alignment: Alignment::Left,
            title_style: None,
            borders: Borders::ALL,
            border_style: Style::default(),
            border_type: BorderType::Plain,
            style: Style::default(),
            padding: Padding::ZERO,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 3)))
            .unwrap();

        let buf = terminal.backend().buffer();
        // Title is drawn starting at col 1 (after left corner)
        assert_eq!(buf.cell((1, 0)).unwrap().symbol(), " ");
        assert_eq!(buf.cell((1, 0)).unwrap().fg, Color::Green);
        let build_b = buf.cell((5, 0)).unwrap();
        assert_eq!(build_b.symbol(), "B");
        assert_eq!(build_b.fg, Color::Yellow);
        assert!(build_b.modifier.contains(Modifier::BOLD));
    }

    #[test]
    fn test_render_block_with_border_style() {
        let backend = TestBackend::new(10, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = BlockData {
            title: None,
            titles: Vec::new(),
            title_position: TitlePosition::Top,
            title_alignment: Alignment::Left,
            title_style: None,
            borders: Borders::ALL,
            border_style: Style::default().fg(Color::Red),
            border_type: BorderType::Plain,
            style: Style::default(),
            padding: Padding::ZERO,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 10, 3)))
            .unwrap();

        let buf = terminal.backend().buffer();
        assert_eq!(buf.cell((0, 0)).unwrap().fg, Color::Red);
    }

    #[test]
    fn test_render_multi_title_top_left_and_right() {
        let backend = TestBackend::new(30, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = BlockData {
            title: Some(Line::from("src/lib.rs")),
            titles: vec![TitleData {
                line: Line::from("[3/12]"),
                position: Some(TitlePosition::Top),
                alignment: Some(Alignment::Right),
                style: None,
            }],
            title_position: TitlePosition::Top,
            title_alignment: Alignment::Left,
            title_style: None,
            borders: Borders::ALL,
            border_style: Style::default(),
            border_type: BorderType::Plain,
            style: Style::default(),
            padding: Padding::ZERO,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 30, 3)))
            .unwrap();

        let top = buffer_line(&terminal, 0, 30);
        assert!(top.contains("src/lib.rs"));
        assert!(top.contains("[3/12]"));
        // Right-aligned text should sit at the right side of the top border.
        let right_idx = top.find("[3/12]").unwrap();
        assert!(
            right_idx > 15,
            "expected [3/12] right-aligned, found at col {right_idx}: {top:?}"
        );
    }

    #[test]
    fn test_render_bottom_title() {
        let backend = TestBackend::new(20, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = BlockData {
            title: None,
            titles: vec![TitleData {
                line: Line::from("status"),
                position: Some(TitlePosition::Bottom),
                alignment: None,
                style: None,
            }],
            title_position: TitlePosition::Top,
            title_alignment: Alignment::Left,
            title_style: None,
            borders: Borders::ALL,
            border_style: Style::default(),
            border_type: BorderType::Plain,
            style: Style::default(),
            padding: Padding::ZERO,
        };

        terminal
            .draw(|frame| render(frame.buffer_mut(), &data, Rect::new(0, 0, 20, 3)))
            .unwrap();

        let bottom = buffer_line(&terminal, 2, 20);
        assert!(bottom.contains("status"));
    }

    #[test]
    fn test_parse_title_position() {
        assert_eq!(parse_title_position("top").unwrap(), TitlePosition::Top);
        assert_eq!(
            parse_title_position("bottom").unwrap(),
            TitlePosition::Bottom
        );
        assert!(parse_title_position("middle").is_err());
    }

    #[test]
    fn test_parse_alignment() {
        assert_eq!(parse_alignment("left").unwrap(), Alignment::Left);
        assert_eq!(parse_alignment("center").unwrap(), Alignment::Center);
        assert_eq!(parse_alignment("right").unwrap(), Alignment::Right);
        assert!(parse_alignment("justified").is_err());
    }

    #[test]
    fn test_parse_borders_all() {
        let result = parse_borders(&["all".to_string()]).unwrap();
        assert_eq!(result, Borders::ALL);
    }

    #[test]
    fn test_parse_borders_individual() {
        let result = parse_borders(&["top".to_string(), "bottom".to_string()]).unwrap();
        assert!(result.contains(Borders::TOP));
        assert!(result.contains(Borders::BOTTOM));
        assert!(!result.contains(Borders::LEFT));
    }

    #[test]
    fn test_parse_border_types() {
        assert_eq!(parse_border_type("plain").unwrap(), BorderType::Plain);
        assert_eq!(parse_border_type("rounded").unwrap(), BorderType::Rounded);
        assert_eq!(parse_border_type("double").unwrap(), BorderType::Double);
        assert_eq!(parse_border_type("thick").unwrap(), BorderType::Thick);
        assert!(parse_border_type("dotted").is_err());
    }
}
