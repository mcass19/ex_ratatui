use ratatui::layout::{Alignment, Rect};
use rustler::{Atom, Error, ResourceArc, Term};
use std::collections::HashMap;

use crate::layout::decode_constraint;
use crate::style::decode_style;
use crate::terminal::{with_terminal_draw, TerminalResource};
use crate::widgets::block::{self, BlockData};
use crate::widgets::gauge::{self, GaugeData};
use crate::widgets::line_gauge::{self, LineGaugeData};
use crate::widgets::list::{self, ListData};
use crate::widgets::paragraph::{self, ParagraphData};
use crate::widgets::scrollbar::{self, ScrollbarData};
use crate::widgets::table::{self, TableData};
use crate::widgets::tabs::{self, TabsData};

enum WidgetData {
    Paragraph(ParagraphData),
    Block(BlockData),
    List(ListData),
    Table(TableData),
    Gauge(GaugeData),
    LineGauge(LineGaugeData),
    Tabs(TabsData),
    Scrollbar(ScrollbarData),
    Clear,
}

struct RenderCommand {
    widget: WidgetData,
    area: Rect,
}

#[rustler::nif(schedule = "DirtyIo")]
fn draw_frame(resource: ResourceArc<TerminalResource>, commands: Term) -> Result<Atom, Error> {
    let command_list: Vec<(Term, Term)> = commands.decode()?;
    let render_commands = decode_commands(&command_list)?;

    with_terminal_draw(&resource, |frame| {
        for cmd in &render_commands {
            render_widget(frame, cmd);
        }
    })
}

fn decode_commands(commands: &[(Term, Term)]) -> Result<Vec<RenderCommand>, Error> {
    commands
        .iter()
        .map(|(widget_term, rect_term)| {
            let widget_map: HashMap<String, Term> = widget_term.decode()?;
            let widget_type: String = widget_map
                .get("type")
                .ok_or_else(|| Error::Term(Box::new("widget missing 'type' key")))?
                .decode()?;

            let widget = match widget_type.as_str() {
                "paragraph" => WidgetData::Paragraph(decode_paragraph(&widget_map)?),
                "block" => WidgetData::Block(block::decode_block_from_map(&widget_map)?),
                "list" => WidgetData::List(decode_list(&widget_map)?),
                "table" => WidgetData::Table(decode_table(&widget_map)?),
                "gauge" => WidgetData::Gauge(decode_gauge(&widget_map)?),
                "line_gauge" => WidgetData::LineGauge(decode_line_gauge(&widget_map)?),
                "tabs" => WidgetData::Tabs(decode_tabs(&widget_map)?),
                "scrollbar" => WidgetData::Scrollbar(decode_scrollbar(&widget_map)?),
                "clear" => WidgetData::Clear,
                other => {
                    return Err(Error::Term(Box::new(format!(
                        "unknown widget type: {other}"
                    ))))
                }
            };

            Ok(RenderCommand {
                widget,
                area: decode_rect(*rect_term)?,
            })
        })
        .collect()
}

fn decode_paragraph(map: &HashMap<String, Term>) -> Result<ParagraphData, Error> {
    let text: String = map
        .get("text")
        .ok_or_else(|| Error::Term(Box::new("paragraph missing 'text'")))?
        .decode()?;

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let alignment = match map.get("alignment") {
        Some(term) => {
            let s: String = term.decode()?;
            match s.as_str() {
                "center" => Alignment::Center,
                "right" => Alignment::Right,
                _ => Alignment::Left,
            }
        }
        None => Alignment::Left,
    };

    let wrap: bool = match map.get("wrap") {
        Some(term) => term.decode()?,
        None => false,
    };

    let scroll_y: u16 = match map.get("scroll_y") {
        Some(term) => term.decode()?,
        None => 0,
    };
    let scroll_x: u16 = match map.get("scroll_x") {
        Some(term) => term.decode()?,
        None => 0,
    };

    let block = decode_optional_block(map)?;

    Ok(ParagraphData {
        text,
        style,
        alignment,
        wrap,
        scroll: (scroll_y, scroll_x),
        block,
    })
}

fn decode_list(map: &HashMap<String, Term>) -> Result<ListData, Error> {
    let items: Vec<String> = map
        .get("items")
        .ok_or_else(|| Error::Term(Box::new("list missing 'items'")))?
        .decode()?;

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let highlight_style = match map.get("highlight_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let highlight_symbol: Option<String> = match map.get("highlight_symbol") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let selected: Option<usize> = match map.get("selected") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let block = decode_optional_block(map)?;

    Ok(ListData {
        items,
        style,
        block,
        highlight_style,
        highlight_symbol,
        selected,
    })
}

fn decode_table(map: &HashMap<String, Term>) -> Result<TableData, Error> {
    let rows: Vec<Vec<String>> = map
        .get("rows")
        .ok_or_else(|| Error::Term(Box::new("table missing 'rows'")))?
        .decode()?;

    let header: Option<Vec<String>> = match map.get("header") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let widths = match map.get("widths") {
        Some(term) => {
            let width_terms: Vec<Term> = term.decode()?;
            width_terms
                .iter()
                .map(|t| decode_constraint(*t))
                .collect::<Result<Vec<_>, _>>()?
        }
        None => Vec::new(),
    };

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let highlight_style = match map.get("highlight_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let highlight_symbol: Option<String> = match map.get("highlight_symbol") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let selected: Option<usize> = match map.get("selected") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let column_spacing: u16 = match map.get("column_spacing") {
        Some(term) => term.decode()?,
        None => 1,
    };

    let block = decode_optional_block(map)?;

    Ok(TableData {
        rows,
        header,
        widths,
        style,
        block,
        highlight_style,
        highlight_symbol,
        selected,
        column_spacing,
    })
}

fn decode_gauge(map: &HashMap<String, Term>) -> Result<GaugeData, Error> {
    let ratio: f64 = map
        .get("ratio")
        .ok_or_else(|| Error::Term(Box::new("gauge missing 'ratio'")))?
        .decode()?;

    if !ratio.is_finite() {
        return Err(Error::Term(Box::new("gauge ratio must be a finite number")));
    }

    let label: Option<String> = match map.get("label") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let gauge_style = match map.get("gauge_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let block = decode_optional_block(map)?;

    Ok(GaugeData {
        ratio,
        label,
        style,
        block,
        gauge_style,
    })
}

fn decode_tabs(map: &HashMap<String, Term>) -> Result<TabsData, Error> {
    let titles: Vec<String> = map
        .get("titles")
        .ok_or_else(|| Error::Term(Box::new("tabs missing 'titles'")))?
        .decode()?;

    let selected: Option<usize> = match map.get("selected") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let highlight_style = match map.get("highlight_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let divider: Option<String> = match map.get("divider") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let padding_left: u16 = match map.get("padding_left") {
        Some(term) => term.decode()?,
        None => 1,
    };

    let padding_right: u16 = match map.get("padding_right") {
        Some(term) => term.decode()?,
        None => 1,
    };

    let block = decode_optional_block(map)?;

    Ok(TabsData {
        titles,
        selected,
        style,
        highlight_style,
        divider,
        block,
        padding_left,
        padding_right,
    })
}

fn decode_scrollbar(map: &HashMap<String, Term>) -> Result<ScrollbarData, Error> {
    let orientation_str: String = match map.get("orientation") {
        Some(term) => term.decode()?,
        None => "vertical_right".to_string(),
    };
    let orientation = scrollbar::parse_orientation(&orientation_str)?;

    let thumb_style = match map.get("thumb_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let track_style = match map.get("track_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let begin_symbol: Option<String> = match map.get("begin_symbol") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let end_symbol: Option<String> = match map.get("end_symbol") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let thumb_symbol: Option<String> = match map.get("thumb_symbol") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let track_symbol: Option<String> = match map.get("track_symbol") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let content_length: usize = map
        .get("content_length")
        .ok_or_else(|| Error::Term(Box::new("scrollbar missing 'content_length'")))?
        .decode()?;

    let position: usize = match map.get("position") {
        Some(term) => term.decode()?,
        None => 0,
    };

    let viewport_content_length: Option<usize> = match map.get("viewport_content_length") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    Ok(ScrollbarData {
        orientation,
        thumb_style,
        track_style,
        begin_symbol,
        end_symbol,
        thumb_symbol,
        track_symbol,
        content_length,
        position,
        viewport_content_length,
    })
}

fn decode_line_gauge(map: &HashMap<String, Term>) -> Result<LineGaugeData, Error> {
    let ratio: f64 = map
        .get("ratio")
        .ok_or_else(|| Error::Term(Box::new("line_gauge missing 'ratio'")))?
        .decode()?;

    if !ratio.is_finite() {
        return Err(Error::Term(Box::new(
            "line_gauge ratio must be a finite number",
        )));
    }

    let label: Option<String> = match map.get("label") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let filled_style = match map.get("filled_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let unfilled_style = match map.get("unfilled_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let block = decode_optional_block(map)?;

    Ok(LineGaugeData {
        ratio,
        label,
        style,
        filled_style,
        unfilled_style,
        block,
    })
}

fn decode_optional_block(map: &HashMap<String, Term>) -> Result<Option<BlockData>, Error> {
    match map.get("block") {
        Some(term) => Ok(Some(block::decode_block(*term)?)),
        None => Ok(None),
    }
}

pub fn decode_rect(term: Term) -> Result<Rect, Error> {
    let map: HashMap<String, Term> = term.decode()?;
    Ok(Rect {
        x: map
            .get("x")
            .ok_or_else(|| Error::Term(Box::new("rect missing 'x'")))?
            .decode()?,
        y: map
            .get("y")
            .ok_or_else(|| Error::Term(Box::new("rect missing 'y'")))?
            .decode()?,
        width: map
            .get("width")
            .ok_or_else(|| Error::Term(Box::new("rect missing 'width'")))?
            .decode()?,
        height: map
            .get("height")
            .ok_or_else(|| Error::Term(Box::new("rect missing 'height'")))?
            .decode()?,
    })
}

fn render_widget(frame: &mut ratatui::Frame, cmd: &RenderCommand) {
    match &cmd.widget {
        WidgetData::Paragraph(data) => paragraph::render(frame, data, cmd.area),
        WidgetData::Block(data) => block::render(frame, data, cmd.area),
        WidgetData::List(data) => list::render(frame, data, cmd.area),
        WidgetData::Table(data) => table::render(frame, data, cmd.area),
        WidgetData::Gauge(data) => gauge::render(frame, data, cmd.area),
        WidgetData::LineGauge(data) => line_gauge::render(frame, data, cmd.area),
        WidgetData::Tabs(data) => tabs::render(frame, data, cmd.area),
        WidgetData::Scrollbar(data) => scrollbar::render(frame, data, cmd.area),
        WidgetData::Clear => crate::widgets::clear::render(frame, cmd.area),
    }
}
