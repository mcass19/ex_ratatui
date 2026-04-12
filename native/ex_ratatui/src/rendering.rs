use ratatui::buffer::Buffer;
use ratatui::layout::{Alignment, Rect};
use rustler::{Atom, Error, ResourceArc, Term};

use crate::decode::{
    decode_map, decode_optional, decode_required, error_message, invalid_field, optional_term,
    TermMap,
};
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

pub(crate) struct RenderCommand {
    pub(crate) widget: WidgetData,
    pub(crate) area: Rect,
}

#[rustler::nif(schedule = "DirtyIo")]
fn draw_frame(resource: ResourceArc<TerminalResource>, commands: Term) -> Result<Atom, Error> {
    let render_commands = decode_render_commands(commands)?;

    with_terminal_draw(&resource, |frame| {
        for cmd in &render_commands {
            render_widget(frame, cmd);
        }
    })
}

pub(crate) fn decode_render_commands(commands: Term<'_>) -> Result<Vec<RenderCommand>, Error> {
    let entries: Vec<(Term<'_>, Term<'_>)> = commands.decode()?;

    entries
        .into_iter()
        .map(|(widget_term, rect_term)| {
            let widget_map = decode_map(widget_term, "render_command.widget")?;
            let widget = decode_widget_from_map(&widget_map)?;

            Ok(RenderCommand {
                widget,
                area: decode_rect(rect_term)?,
            })
        })
        .collect()
}

pub fn decode_widget_from_map(widget_map: &TermMap<'_>) -> Result<WidgetData, Error> {
    let widget_type: String = decode_required(widget_map, "type", "widget")?;

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
        other => Err(error_message(format!(
            "widget.type: unsupported widget type '{other}'"
        ))),
    }
}

fn decode_paragraph(map: &TermMap<'_>) -> Result<ParagraphData, Error> {
    let text: String = decode_required(map, "text", "paragraph")?;

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let alignment = match decode_optional::<String>(map, "alignment", "paragraph")? {
        Some(s) => match s.as_str() {
            "center" => Alignment::Center,
            "right" => Alignment::Right,
            _ => Alignment::Left,
        },
        None => Alignment::Left,
    };

    let wrap: bool = decode_optional(map, "wrap", "paragraph")?.unwrap_or(false);
    let scroll_y: u16 = decode_optional(map, "scroll_y", "paragraph")?.unwrap_or(0);
    let scroll_x: u16 = decode_optional(map, "scroll_x", "paragraph")?.unwrap_or(0);

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

fn decode_list(map: &TermMap<'_>) -> Result<ListData, Error> {
    let items: Vec<String> = decode_required(map, "items", "list")?;

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let highlight_style = match optional_term(map, "highlight_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let highlight_symbol: Option<String> = decode_optional(map, "highlight_symbol", "list")?;
    let selected: Option<usize> = decode_optional(map, "selected", "list")?;

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

fn decode_table(map: &TermMap<'_>) -> Result<TableData, Error> {
    let rows: Vec<Vec<String>> = decode_required(map, "rows", "table")?;
    let header: Option<Vec<String>> = decode_optional(map, "header", "table")?;

    let widths = match optional_term(map, "widths") {
        Some(term) => {
            let width_terms: Vec<Term<'_>> = term
                .decode()
                .map_err(|_| invalid_field("table", "widths", "unexpected value"))?;
            width_terms
                .iter()
                .map(|t| decode_constraint(*t))
                .collect::<Result<Vec<_>, _>>()?
        }
        None => Vec::new(),
    };

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let highlight_style = match optional_term(map, "highlight_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let highlight_symbol: Option<String> = decode_optional(map, "highlight_symbol", "table")?;
    let selected: Option<usize> = decode_optional(map, "selected", "table")?;
    let column_spacing: u16 = decode_optional(map, "column_spacing", "table")?.unwrap_or(1);

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

fn decode_gauge(map: &TermMap<'_>) -> Result<GaugeData, Error> {
    let ratio: f64 = decode_required(map, "ratio", "gauge")?;

    if !ratio.is_finite() {
        return Err(invalid_field("gauge", "ratio", "must be a finite number"));
    }

    let label: Option<String> = decode_optional(map, "label", "gauge")?;

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let gauge_style = match optional_term(map, "gauge_style") {
        Some(term) => decode_style(term)?,
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

fn decode_tabs(map: &TermMap<'_>) -> Result<TabsData, Error> {
    let titles: Vec<String> = decode_required(map, "titles", "tabs")?;
    let selected: Option<usize> = decode_optional(map, "selected", "tabs")?;

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let highlight_style = match optional_term(map, "highlight_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let divider: Option<String> = decode_optional(map, "divider", "tabs")?;
    let padding_left: u16 = decode_optional(map, "padding_left", "tabs")?.unwrap_or(1);
    let padding_right: u16 = decode_optional(map, "padding_right", "tabs")?.unwrap_or(1);

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

fn decode_scrollbar(map: &TermMap<'_>) -> Result<ScrollbarData, Error> {
    let orientation_str: String =
        decode_optional(map, "orientation", "scrollbar")?.unwrap_or("vertical_right".to_string());
    let orientation = scrollbar::parse_orientation(&orientation_str)?;

    let thumb_style = match optional_term(map, "thumb_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let track_style = match optional_term(map, "track_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let begin_symbol: Option<String> = decode_optional(map, "begin_symbol", "scrollbar")?;
    let end_symbol: Option<String> = decode_optional(map, "end_symbol", "scrollbar")?;
    let thumb_symbol: Option<String> = decode_optional(map, "thumb_symbol", "scrollbar")?;
    let track_symbol: Option<String> = decode_optional(map, "track_symbol", "scrollbar")?;
    let content_length: usize = decode_required(map, "content_length", "scrollbar")?;
    let position: usize = decode_optional(map, "position", "scrollbar")?.unwrap_or(0);
    let viewport_content_length: Option<usize> =
        decode_optional(map, "viewport_content_length", "scrollbar")?;

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

fn decode_line_gauge(map: &TermMap<'_>) -> Result<LineGaugeData, Error> {
    let ratio: f64 = decode_required(map, "ratio", "line_gauge")?;

    if !ratio.is_finite() {
        return Err(invalid_field(
            "line_gauge",
            "ratio",
            "must be a finite number",
        ));
    }

    let label: Option<String> = decode_optional(map, "label", "line_gauge")?;

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let filled_style = match optional_term(map, "filled_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let unfilled_style = match optional_term(map, "unfilled_style") {
        Some(term) => decode_style(term)?,
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

fn decode_checkbox(map: &TermMap<'_>) -> Result<CheckboxData, Error> {
    let label: String = decode_required(map, "label", "checkbox")?;
    let checked: bool = decode_required(map, "checked", "checkbox")?;

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let checked_style = match optional_term(map, "checked_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let checked_symbol: Option<String> = decode_optional(map, "checked_symbol", "checkbox")?;
    let unchecked_symbol: Option<String> = decode_optional(map, "unchecked_symbol", "checkbox")?;

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

fn decode_text_input(map: &TermMap<'_>) -> Result<TextInputRenderData, Error> {
    let resource: ResourceArc<TextInputResource> = decode_required(map, "state", "text_input")?;

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let cursor_style = match optional_term(map, "cursor_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let placeholder: Option<String> = decode_optional(map, "placeholder", "text_input")?;

    let placeholder_style = match optional_term(map, "placeholder_style") {
        Some(term) => decode_style(term)?,
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

fn decode_throbber(map: &TermMap<'_>) -> Result<ThrobberData, Error> {
    let label: Option<String> = match optional_term(map, "label") {
        Some(term) => {
            let s: String = term
                .decode()
                .map_err(|_| invalid_field("throbber", "label", "unexpected value"))?;
            if s.is_empty() {
                None
            } else {
                Some(s)
            }
        }
        None => None,
    };

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let throbber_style = match optional_term(map, "throbber_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let throbber_set_name: String =
        decode_optional(map, "throbber_set", "throbber")?.unwrap_or("braille".to_string());
    let throbber_set = throbber::parse_throbber_set(&throbber_set_name);

    let step: i8 = match optional_term(map, "step") {
        Some(term) => {
            let val: i64 = term
                .decode()
                .map_err(|_| invalid_field("throbber", "step", "unexpected value"))?;
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

fn decode_markdown(map: &TermMap<'_>) -> Result<MarkdownData, Error> {
    let content: String = decode_required(map, "content", "markdown")?;

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let wrap: bool = decode_optional(map, "wrap", "markdown")?.unwrap_or(true);
    let scroll_y: u16 = decode_optional(map, "scroll_y", "markdown")?.unwrap_or(0);
    let scroll_x: u16 = decode_optional(map, "scroll_x", "markdown")?.unwrap_or(0);

    let block = decode_optional_block(map)?;

    Ok(MarkdownData {
        content,
        style,
        block,
        scroll: (scroll_y, scroll_x),
        wrap,
    })
}

fn decode_textarea(map: &TermMap<'_>) -> Result<TextareaRenderData, Error> {
    let resource: ResourceArc<TextareaResource> = decode_required(map, "state", "textarea")?;

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let cursor_style = match optional_term(map, "cursor_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let cursor_line_style = match optional_term(map, "cursor_line_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let placeholder: Option<String> = decode_optional(map, "placeholder", "textarea")?;

    let placeholder_style = match optional_term(map, "placeholder_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let line_number_style: Option<ratatui::style::Style> =
        match optional_term(map, "line_number_style") {
            Some(term) => Some(decode_style(term)?),
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

fn decode_popup(map: &TermMap<'_>) -> Result<PopupData, Error> {
    let content_map = decode_map(decode_required(map, "content", "popup")?, "popup.content")?;
    let content = Box::new(decode_widget_from_map(&content_map)?);

    let percent_width: u16 = decode_optional(map, "percent_width", "popup")?.unwrap_or(60);
    let percent_height: u16 = decode_optional(map, "percent_height", "popup")?.unwrap_or(60);
    let fixed_width: Option<u16> = decode_optional(map, "fixed_width", "popup")?;
    let fixed_height: Option<u16> = decode_optional(map, "fixed_height", "popup")?;

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

fn decode_widget_list(map: &TermMap<'_>) -> Result<WidgetListData, Error> {
    let items_terms: Vec<(Term<'_>, Term<'_>)> = decode_required(map, "items", "widget_list")?;

    let mut items = Vec::with_capacity(items_terms.len());
    for (widget_term, height_term) in &items_terms {
        let widget_map = decode_map(*widget_term, "widget_list.item")?;
        let widget = decode_widget_from_map(&widget_map)?;
        let height: u16 = height_term
            .decode()
            .map_err(|_| invalid_field("widget_list", "items", "unexpected item height"))?;
        items.push(WidgetListItem { widget, height });
    }

    let selected: Option<usize> = decode_optional(map, "selected", "widget_list")?;

    let highlight_style = match optional_term(map, "highlight_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let scroll_offset: usize = decode_optional(map, "scroll_offset", "widget_list")?.unwrap_or(0);

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
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

fn decode_optional_block(map: &TermMap<'_>) -> Result<Option<BlockData>, Error> {
    match optional_term(map, "block") {
        Some(term) => Ok(Some(block::decode_block(term)?)),
        None => Ok(None),
    }
}

pub fn decode_rect(term: Term) -> Result<Rect, Error> {
    let map = decode_map(term, "rect")?;
    Ok(Rect {
        x: decode_required(&map, "x", "rect")?,
        y: decode_required(&map, "y", "rect")?,
        width: decode_required(&map, "width", "rect")?,
        height: decode_required(&map, "height", "rect")?,
    })
}

fn render_widget(frame: &mut ratatui::Frame, cmd: &RenderCommand) {
    render_widget_data(frame.buffer_mut(), &cmd.widget, cmd.area);
}

pub fn render_widget_data(buf: &mut Buffer, widget: &WidgetData, area: Rect) {
    match widget {
        WidgetData::Paragraph(data) => paragraph::render(buf, data, area),
        WidgetData::Block(data) => block::render(buf, data, area),
        WidgetData::List(data) => list::render(buf, data, area),
        WidgetData::Table(data) => table::render(buf, data, area),
        WidgetData::Gauge(data) => gauge::render(buf, data, area),
        WidgetData::LineGauge(data) => line_gauge::render(buf, data, area),
        WidgetData::Tabs(data) => tabs::render(buf, data, area),
        WidgetData::Scrollbar(data) => scrollbar::render(buf, data, area),
        WidgetData::Checkbox(data) => checkbox::render(buf, data, area),
        WidgetData::TextInput(data) => text_input::render(buf, data, area),
        WidgetData::Throbber(data) => throbber::render(buf, data, area),
        WidgetData::Markdown(data) => markdown::render(buf, data, area),
        WidgetData::Textarea(data) => textarea::render(buf, data, area),
        WidgetData::Popup(data) => popup::render(buf, data, area),
        WidgetData::WidgetList(data) => widget_list::render(buf, data, area),
        WidgetData::Clear => crate::widgets::clear::render(buf, area),
    }
}
