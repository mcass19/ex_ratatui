use ratatui::layout::{Constraint, Direction, Flex, Layout};
use rustler::{Error, Term};
use std::collections::HashMap;

use crate::rendering::decode_rect;

#[rustler::nif]
fn layout_split(
    area_term: Term,
    direction: String,
    constraints_term: Vec<Term>,
    opts: HashMap<String, Term>,
) -> Result<Vec<(u16, u16, u16, u16)>, Error> {
    let area = decode_rect(area_term)?;

    let dir = match direction.as_str() {
        "horizontal" => Direction::Horizontal,
        "vertical" => Direction::Vertical,
        other => return Err(Error::Term(Box::new(format!("unknown direction: {other}")))),
    };

    let constraints: Vec<Constraint> = constraints_term
        .iter()
        .map(|t| decode_constraint(*t))
        .collect::<Result<_, _>>()?;

    let flex = match opts.get("flex") {
        Some(term) => {
            let s: String = term.decode()?;
            parse_flex(&s)?
        }
        None => Flex::default(),
    };

    let spacing: i16 = match opts.get("spacing") {
        Some(term) => term.decode()?,
        None => 0,
    };

    let chunks = Layout::default()
        .direction(dir)
        .constraints(constraints)
        .flex(flex)
        .spacing(spacing)
        .split(area);

    Ok(chunks
        .iter()
        .map(|r| (r.x, r.y, r.width, r.height))
        .collect())
}

fn parse_flex(s: &str) -> Result<Flex, Error> {
    match s {
        "legacy" => Ok(Flex::Legacy),
        "start" => Ok(Flex::Start),
        "center" => Ok(Flex::Center),
        "end" => Ok(Flex::End),
        "space_between" => Ok(Flex::SpaceBetween),
        "space_around" => Ok(Flex::SpaceAround),
        other => Err(Error::Term(Box::new(format!("unknown flex mode: {other}")))),
    }
}

pub fn decode_constraint(term: Term) -> Result<Constraint, Error> {
    let map: HashMap<String, Term> = term.decode()?;
    let constraint_type: String = map
        .get("type")
        .ok_or_else(|| Error::Term(Box::new("constraint missing 'type'")))?
        .decode()?;

    match constraint_type.as_str() {
        "percentage" => {
            let value: u16 = map
                .get("value")
                .ok_or_else(|| Error::Term(Box::new("percentage missing 'value'")))?
                .decode()?;
            Ok(Constraint::Percentage(value))
        }
        "length" => {
            let value: u16 = map
                .get("value")
                .ok_or_else(|| Error::Term(Box::new("length missing 'value'")))?
                .decode()?;
            Ok(Constraint::Length(value))
        }
        "min" => {
            let value: u16 = map
                .get("value")
                .ok_or_else(|| Error::Term(Box::new("min missing 'value'")))?
                .decode()?;
            Ok(Constraint::Min(value))
        }
        "max" => {
            let value: u16 = map
                .get("value")
                .ok_or_else(|| Error::Term(Box::new("max missing 'value'")))?
                .decode()?;
            Ok(Constraint::Max(value))
        }
        "ratio" => {
            let num: u32 = map
                .get("num")
                .ok_or_else(|| Error::Term(Box::new("ratio missing 'num'")))?
                .decode()?;
            let den: u32 = map
                .get("den")
                .ok_or_else(|| Error::Term(Box::new("ratio missing 'den'")))?
                .decode()?;
            if den == 0 {
                return Err(Error::Term(Box::new("ratio denominator must not be zero")));
            }
            Ok(Constraint::Ratio(num, den))
        }
        "fill" => {
            let value: u16 = map
                .get("value")
                .ok_or_else(|| Error::Term(Box::new("fill missing 'value'")))?
                .decode()?;
            Ok(Constraint::Fill(value))
        }
        other => Err(Error::Term(Box::new(format!(
            "unknown constraint type: {other}"
        )))),
    }
}

#[cfg(test)]
mod tests {
    use ratatui::layout::{Constraint, Direction, Layout, Rect};

    #[test]
    fn test_vertical_split_percentage() {
        let area = Rect::new(0, 0, 80, 24);
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
            .split(area);

        assert_eq!(chunks.len(), 2);
        assert_eq!(chunks[0], Rect::new(0, 0, 80, 12));
        assert_eq!(chunks[1], Rect::new(0, 12, 80, 12));
    }

    #[test]
    fn test_horizontal_split_percentage() {
        let area = Rect::new(0, 0, 80, 24);
        let chunks = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
            .split(area);

        assert_eq!(chunks.len(), 2);
        assert_eq!(chunks[0], Rect::new(0, 0, 40, 24));
        assert_eq!(chunks[1], Rect::new(40, 0, 40, 24));
    }

    #[test]
    fn test_vertical_split_length() {
        let area = Rect::new(0, 0, 80, 24);
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(3), Constraint::Min(0)])
            .split(area);

        assert_eq!(chunks.len(), 2);
        assert_eq!(chunks[0].height, 3);
        assert_eq!(chunks[1].height, 21);
        assert_eq!(chunks[1].y, 3);
    }

    #[test]
    fn test_three_way_split() {
        let area = Rect::new(0, 0, 60, 30);
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(0),
                Constraint::Length(1),
            ])
            .split(area);

        assert_eq!(chunks.len(), 3);
        assert_eq!(chunks[0], Rect::new(0, 0, 60, 3));
        assert_eq!(chunks[1], Rect::new(0, 3, 60, 26));
        assert_eq!(chunks[2], Rect::new(0, 29, 60, 1));
    }

    #[test]
    fn test_split_with_offset() {
        let area = Rect::new(5, 5, 40, 20);
        let chunks = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
            .split(area);

        assert_eq!(chunks[0], Rect::new(5, 5, 20, 20));
        assert_eq!(chunks[1], Rect::new(25, 5, 20, 20));
    }

    #[test]
    fn test_ratio_constraint() {
        let area = Rect::new(0, 0, 90, 24);
        let chunks = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Ratio(1, 3), Constraint::Ratio(2, 3)])
            .split(area);

        assert_eq!(chunks.len(), 2);
        assert_eq!(chunks[0].width, 30);
        assert_eq!(chunks[1].width, 60);
    }

    #[test]
    fn test_max_constraint() {
        let area = Rect::new(0, 0, 80, 24);
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Max(5), Constraint::Min(0)])
            .split(area);

        assert_eq!(chunks[0].height, 5);
        assert_eq!(chunks[1].height, 19);
    }

    #[test]
    fn test_fill_distributes_remaining_space_by_weight() {
        use ratatui::layout::Constraint::Fill;

        let area = Rect::new(0, 0, 60, 24);
        let chunks = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Fill(1), Fill(2), Fill(3)])
            .split(area);

        assert_eq!(chunks.len(), 3);
        assert_eq!(chunks[0].width + chunks[1].width + chunks[2].width, 60);
        assert!(chunks[0].width < chunks[1].width);
        assert!(chunks[1].width < chunks[2].width);
    }

    #[test]
    fn test_flex_center_distributes_excess_to_both_ends() {
        use ratatui::layout::Flex;

        let area = Rect::new(0, 0, 30, 1);
        let chunks = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Length(10)])
            .flex(Flex::Center)
            .split(area);

        assert_eq!(chunks[0].x, 10);
        assert_eq!(chunks[0].width, 10);
    }

    #[test]
    fn test_spacing_adds_gap_between_segments() {
        let area = Rect::new(0, 0, 22, 1);
        let chunks = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Length(10), Constraint::Length(10)])
            .spacing(2)
            .split(area);

        assert_eq!(chunks[0].x, 0);
        assert_eq!(chunks[0].width, 10);
        assert_eq!(chunks[1].x, 12);
        assert_eq!(chunks[1].width, 10);
    }

    #[test]
    fn test_parse_flex_recognizes_every_variant() {
        use super::parse_flex;
        use ratatui::layout::Flex;

        assert_eq!(parse_flex("legacy").unwrap(), Flex::Legacy);
        assert_eq!(parse_flex("start").unwrap(), Flex::Start);
        assert_eq!(parse_flex("center").unwrap(), Flex::Center);
        assert_eq!(parse_flex("end").unwrap(), Flex::End);
        assert_eq!(parse_flex("space_between").unwrap(), Flex::SpaceBetween);
        assert_eq!(parse_flex("space_around").unwrap(), Flex::SpaceAround);
        assert!(parse_flex("nope").is_err());
    }
}
