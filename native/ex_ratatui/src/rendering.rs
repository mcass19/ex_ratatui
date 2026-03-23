use ratatui::layout::{Alignment, Rect};
use rustler::{Atom, Error, ResourceArc, Term};
use std::collections::HashMap;

use crate::layout::decode_constraint;
use crate::style::decode_style;
use crate::terminal::{with_terminal_draw, TerminalResource};
use crate::text_input::{self, TextInputRenderData, TextInputResource};
use crate::textarea::{self, TextareaRenderData, TextareaResource};
use crate::widgets::block::{self, BlockData};
use crate::widgets::checkbox::{self, CheckboxData};
use crate::widgets::gauge::{self, GaugeData};
use crate::widgets::line_gauge::{self, LineGaugeData};
use crate::widgets::list::{self, ListData};
use crate::widgets::markdown::{self, MarkdownData};
use crate::widgets::paragraph::{self, ParagraphData};
use crate::widgets::popup::{self, PopupData};
use crate::widgets::scrollbar::{self, ScrollbarData};
use crate::widgets::table::{self, TableData};
use crate::widgets::tabs::{self, TabsData};
use crate::widgets::throbber::{self, ThrobberData};
use crate::widgets::widget_list::{self, WidgetListData, WidgetListItem};

pub enum WidgetData {
    Paragraph(ParagraphData),
    Block(BlockData),
    List(ListData),
    Table(TableData),
    Gauge(GaugeData),
    LineGauge(LineGaugeData),
    Tabs(TabsData),
    Scrollbar(ScrollbarData),
    Checkbox(CheckboxData),
    TextInput(TextInputRenderData),
    Throbber(ThrobberData),
    Markdown(MarkdownData),
    Textarea(TextareaRenderData),
    Popup(PopupData),
    WidgetList(WidgetListData),
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
            let widget = decode_widget_from_map(&widget_map)?;

            Ok(RenderCommand {
                widget,
                area: decode_rect(*rect_term)?,
            })
        })
        .collect()
}

pub fn decode_widget_from_map(widget_map: &HashMap<String, Term>) -> Result<WidgetData, Error> {
    let widget_type: String = widget_map
        .get("type")
        .ok_or_else(|| Error::Term(Box::new("widget missing 'type' key")))?
        .decode()?;

    match widget_type.as_str() {
        "paragraph" => Ok(WidgetData::Paragraph(decode_paragraph(widget_map)?)),
        "block" => Ok(WidgetData::Block(block::decode_block_from_map(widget_map)?)),
        "list" => Ok(WidgetData::List(decode_list(widget_map)?)),
        "table" => Ok(WidgetData::Table(decode_table(widget_map)?)),
        "gauge" => Ok(WidgetData::Gauge(decode_gauge(widget_map)?)),
        "line_gauge" => Ok(WidgetData::LineGauge(decode_line_gauge(widget_map)?)),
        "tabs" => Ok(WidgetData::Tabs(decode_tabs(widget_map)?)),
        "scrollbar" => Ok(WidgetData::Scrollbar(decode_scrollbar(widget_map)?)),
        "checkbox" => Ok(WidgetData::Checkbox(decode_checkbox(widget_map)?)),
        "text_input" => Ok(WidgetData::TextInput(decode_text_input(widget_map)?)),
        "throbber" => Ok(WidgetData::Throbber(decode_throbber(widget_map)?)),
        "markdown" => Ok(WidgetData::Markdown(decode_markdown(widget_map)?)),
        "textarea" => Ok(WidgetData::Textarea(decode_textarea(widget_map)?)),
        "popup" => Ok(WidgetData::Popup(decode_popup(widget_map)?)),
        "widget_list" => Ok(WidgetData::WidgetList(decode_widget_list(widget_map)?)),
        "clear" => Ok(WidgetData::Clear),
        other => Err(Error::Term(Box::new(format!(
            "unknown widget type: {other}"
        )))),
    }
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

fn decode_checkbox(map: &HashMap<String, Term>) -> Result<CheckboxData, Error> {
    let label: String = map
        .get("label")
        .ok_or_else(|| Error::Term(Box::new("checkbox missing 'label'")))?
        .decode()?;

    let checked: bool = map
        .get("checked")
        .ok_or_else(|| Error::Term(Box::new("checkbox missing 'checked'")))?
        .decode()?;

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let checked_style = match map.get("checked_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let checked_symbol: Option<String> = match map.get("checked_symbol") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let unchecked_symbol: Option<String> = match map.get("unchecked_symbol") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let block = decode_optional_block(map)?;

    Ok(CheckboxData {
        label,
        checked,
        style,
        checked_style,
        checked_symbol,
        unchecked_symbol,
        block,
    })
}

fn decode_text_input(map: &HashMap<String, Term>) -> Result<TextInputRenderData, Error> {
    let resource: ResourceArc<TextInputResource> = map
        .get("state")
        .ok_or_else(|| Error::Term(Box::new("text_input missing 'state'")))?
        .decode()?;

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let cursor_style = match map.get("cursor_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let placeholder: Option<String> = match map.get("placeholder") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let placeholder_style = match map.get("placeholder_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let block = decode_optional_block(map)?;

    Ok(TextInputRenderData {
        resource,
        style,
        cursor_style,
        placeholder,
        placeholder_style,
        block,
    })
}

fn decode_throbber(map: &HashMap<String, Term>) -> Result<ThrobberData, Error> {
    let label: Option<String> = match map.get("label") {
        Some(term) => {
            let s: String = term.decode()?;
            if s.is_empty() {
                None
            } else {
                Some(s)
            }
        }
        None => None,
    };

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let throbber_style = match map.get("throbber_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let throbber_set_name: String = match map.get("throbber_set") {
        Some(term) => term.decode()?,
        None => "braille".to_string(),
    };
    let throbber_set = throbber::parse_throbber_set(&throbber_set_name);

    let step: i8 = match map.get("step") {
        Some(term) => {
            let val: i64 = term.decode()?;
            (val % 128) as i8
        }
        None => 0,
    };

    let block = decode_optional_block(map)?;

    Ok(ThrobberData {
        label,
        style,
        throbber_style,
        throbber_set,
        step,
        block,
    })
}

fn decode_markdown(map: &HashMap<String, Term>) -> Result<MarkdownData, Error> {
    let content: String = map
        .get("content")
        .ok_or_else(|| Error::Term(Box::new("markdown missing 'content'")))?
        .decode()?;

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let wrap: bool = match map.get("wrap") {
        Some(term) => term.decode()?,
        None => true,
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

    Ok(MarkdownData {
        content,
        style,
        block,
        scroll: (scroll_y, scroll_x),
        wrap,
    })
}

fn decode_textarea(map: &HashMap<String, Term>) -> Result<TextareaRenderData, Error> {
    let resource: ResourceArc<TextareaResource> = map
        .get("state")
        .ok_or_else(|| Error::Term(Box::new("textarea missing 'state'")))?
        .decode()?;

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let cursor_style = match map.get("cursor_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let cursor_line_style = match map.get("cursor_line_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let placeholder: Option<String> = match map.get("placeholder") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let placeholder_style = match map.get("placeholder_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let line_number_style: Option<ratatui::style::Style> = match map.get("line_number_style") {
        Some(term) => Some(decode_style(*term)?),
        None => None,
    };

    let block = decode_optional_block(map)?;

    Ok(TextareaRenderData {
        resource,
        style,
        cursor_style,
        cursor_line_style,
        placeholder,
        placeholder_style,
        line_number_style,
        block,
    })
}

fn decode_popup(map: &HashMap<String, Term>) -> Result<PopupData, Error> {
    let content_map: HashMap<String, Term> = map
        .get("content")
        .ok_or_else(|| Error::Term(Box::new("popup missing 'content'")))?
        .decode()?;
    let content = Box::new(decode_widget_from_map(&content_map)?);

    let percent_width: u16 = match map.get("percent_width") {
        Some(term) => term.decode()?,
        None => 60,
    };

    let percent_height: u16 = match map.get("percent_height") {
        Some(term) => term.decode()?,
        None => 60,
    };

    let fixed_width: Option<u16> = match map.get("fixed_width") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let fixed_height: Option<u16> = match map.get("fixed_height") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let block = decode_optional_block(map)?;

    Ok(PopupData {
        content,
        block,
        percent_width,
        percent_height,
        fixed_width,
        fixed_height,
    })
}

fn decode_widget_list(map: &HashMap<String, Term>) -> Result<WidgetListData, Error> {
    let items_terms: Vec<(Term, Term)> = map
        .get("items")
        .ok_or_else(|| Error::Term(Box::new("widget_list missing 'items'")))?
        .decode()?;

    let mut items = Vec::with_capacity(items_terms.len());
    for (widget_term, height_term) in &items_terms {
        let widget_map: HashMap<String, Term> = widget_term.decode()?;
        let widget = decode_widget_from_map(&widget_map)?;
        let height: u16 = height_term.decode()?;
        items.push(WidgetListItem { widget, height });
    }

    let selected: Option<usize> = match map.get("selected") {
        Some(term) => Some(term.decode()?),
        None => None,
    };

    let highlight_style = match map.get("highlight_style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let scroll_offset: usize = match map.get("scroll_offset") {
        Some(term) => term.decode()?,
        None => 0,
    };

    let style = match map.get("style") {
        Some(term) => decode_style(*term)?,
        None => ratatui::style::Style::default(),
    };

    let block = decode_optional_block(map)?;

    Ok(WidgetListData {
        items,
        selected,
        highlight_style,
        scroll_offset,
        block,
        style,
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
    render_widget_data(frame, &cmd.widget, cmd.area);
}

pub fn render_widget_data(frame: &mut ratatui::Frame, widget: &WidgetData, area: Rect) {
    match widget {
        WidgetData::Paragraph(data) => paragraph::render(frame, data, area),
        WidgetData::Block(data) => block::render(frame, data, area),
        WidgetData::List(data) => list::render(frame, data, area),
        WidgetData::Table(data) => table::render(frame, data, area),
        WidgetData::Gauge(data) => gauge::render(frame, data, area),
        WidgetData::LineGauge(data) => line_gauge::render(frame, data, area),
        WidgetData::Tabs(data) => tabs::render(frame, data, area),
        WidgetData::Scrollbar(data) => scrollbar::render(frame, data, area),
        WidgetData::Checkbox(data) => checkbox::render(frame, data, area),
        WidgetData::TextInput(data) => text_input::render(frame, data, area),
        WidgetData::Throbber(data) => throbber::render(frame, data, area),
        WidgetData::Markdown(data) => markdown::render(frame, data, area),
        WidgetData::Textarea(data) => textarea::render(frame, data, area),
        WidgetData::Popup(data) => popup::render(frame, data, area),
        WidgetData::WidgetList(data) => widget_list::render(frame, data, area),
        WidgetData::Clear => crate::widgets::clear::render(frame, area),
    }
}
