use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::widgets::{Block, BorderType, Borders, Padding};
use ratatui::Frame;
use rustler::{Error, Term};
use std::collections::HashMap;

use crate::style::decode_style;

#[derive(Clone)]
pub struct BlockData {
    pub title: Option<String>,
    pub borders: Borders,
    pub border_style: Style,
    pub border_type: BorderType,
    pub style: Style,
    pub padding: Padding,
}

impl BlockData {
    pub fn to_block(&self) -> Block<'_> {
        let mut block = Block::default()
            .borders(self.borders)
            .border_style(self.border_style)
            .border_type(self.border_type)
            .style(self.style)
            .padding(self.padding);

        if let Some(ref title) = self.title {
            block = block.title(title.as_str());
        }

        block
    }
}

pub fn render(frame: &mut Frame, data: &BlockData, area: Rect) {
    frame.render_widget(data.to_block(), area);
}

pub fn decode_block(term: Term) -> Result<BlockData, Error> {
    let map: HashMap<String, Term> = term.decode()?;
    decode_block_from_map(&map)
}

pub fn decode_block_from_map(map: &HashMap<String, Term>) -> Result<BlockData, Error> {
    let title = match map.get("title") {
        Some(term) => Some(term.decode::<String>()?),
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
        borders,
        border_style,
        border_type,
        style,
        padding: Padding::new(left, right, top, bottom),
    })
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
            borders: Borders::ALL,
            border_style: Style::default(),
            border_type: BorderType::Plain,
            style: Style::default(),
            padding: Padding::ZERO,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 10, 5)))
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
            title: Some("Hello".to_string()),
            borders: Borders::ALL,
            border_style: Style::default(),
            border_type: BorderType::Plain,
            style: Style::default(),
            padding: Padding::ZERO,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 20, 5)))
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
            borders: Borders::ALL,
            border_style: Style::default(),
            border_type: BorderType::Rounded,
            style: Style::default(),
            padding: Padding::ZERO,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 10, 3)))
            .unwrap();

        let buf = terminal.backend().buffer();
        assert_eq!(buf.cell((0, 0)).unwrap().symbol(), "╭");
        assert_eq!(buf.cell((9, 0)).unwrap().symbol(), "╮");
        assert_eq!(buf.cell((0, 2)).unwrap().symbol(), "╰");
        assert_eq!(buf.cell((9, 2)).unwrap().symbol(), "╯");
    }

    #[test]
    fn test_render_block_with_border_style() {
        let backend = TestBackend::new(10, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let data = BlockData {
            title: None,
            borders: Borders::ALL,
            border_style: Style::default().fg(Color::Red),
            border_type: BorderType::Plain,
            style: Style::default(),
            padding: Padding::ZERO,
        };

        terminal
            .draw(|frame| render(frame, &data, Rect::new(0, 0, 10, 3)))
            .unwrap();

        let buf = terminal.backend().buffer();
        assert_eq!(buf.cell((0, 0)).unwrap().fg, Color::Red);
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
