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
use crate::text;
use crate::text_input::{self, TextInputRenderData, TextInputResource, TextInputState};
use crate::textarea::{self, TextareaRenderData, TextareaResource};
use crate::widgets::bar_chart::{self, BarChartData, BarData, BarGroupData};
use crate::widgets::block::{self, BlockData};
use crate::widgets::calendar::{self, CalendarData};
use crate::widgets::canvas::{self, CanvasData, CanvasShape};
use crate::widgets::chart::{self, AxisData, ChartData, DatasetData};
use crate::widgets::checkbox::{self, CheckboxData};
use crate::widgets::gauge::{self, GaugeData};
use crate::widgets::line_gauge::{self, LineGaugeData};
use crate::widgets::list::{self, ListData};
use crate::widgets::markdown::{self, MarkdownData};
use crate::widgets::paragraph::{self, ParagraphData};
use crate::widgets::popup::{self, PopupData};
use crate::widgets::scrollbar::{self, ScrollbarData};
use crate::widgets::sparkline::{self, SparklineBarSet, SparklineData};
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
    BarChart(BarChartData),
    Sparkline(SparklineData),
    Calendar(CalendarData),
    Canvas(CanvasData),
    Chart(ChartData),
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
        "bar_chart" => Ok(WidgetData::BarChart(decode_bar_chart(widget_map)?)),
        "sparkline" => Ok(WidgetData::Sparkline(decode_sparkline(widget_map)?)),
        "calendar" => Ok(WidgetData::Calendar(decode_calendar(widget_map)?)),
        "canvas" => Ok(WidgetData::Canvas(decode_canvas(widget_map)?)),
        "chart" => Ok(WidgetData::Chart(decode_chart(widget_map)?)),
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
    let text_term = optional_term(map, "text")
        .ok_or_else(|| crate::decode::missing_field("paragraph", "text"))?;
    let text = text::decode_text(text_term)?;

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
    let items_term =
        optional_term(map, "items").ok_or_else(|| crate::decode::missing_field("list", "items"))?;
    let item_terms: Vec<Term<'_>> = items_term
        .decode()
        .map_err(|_| crate::decode::invalid_field("list", "items", "expected a list"))?;
    let items: Vec<ratatui::text::Text<'static>> = item_terms
        .into_iter()
        .map(text::decode_text)
        .collect::<Result<_, _>>()?;

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
    let rows_term =
        optional_term(map, "rows").ok_or_else(|| crate::decode::missing_field("table", "rows"))?;
    let row_terms: Vec<Vec<Term<'_>>> = rows_term
        .decode()
        .map_err(|_| invalid_field("table", "rows", "expected a list of cell lists"))?;
    let rows: Vec<Vec<ratatui::text::Line<'static>>> = row_terms
        .into_iter()
        .map(|cells| cells.into_iter().map(text::decode_line).collect())
        .collect::<Result<_, _>>()?;

    let header = match optional_term(map, "header") {
        Some(term) => {
            let cell_terms: Vec<Term<'_>> = term
                .decode()
                .map_err(|_| invalid_field("table", "header", "expected a list"))?;
            Some(
                cell_terms
                    .into_iter()
                    .map(text::decode_line)
                    .collect::<Result<_, _>>()?,
            )
        }
        None => None,
    };

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
    let titles_term = optional_term(map, "titles")
        .ok_or_else(|| crate::decode::missing_field("tabs", "titles"))?;
    let title_terms: Vec<Term<'_>> = titles_term
        .decode()
        .map_err(|_| invalid_field("tabs", "titles", "expected a list"))?;
    let titles: Vec<ratatui::text::Line<'static>> = title_terms
        .into_iter()
        .map(text::decode_line)
        .collect::<Result<_, _>>()?;

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

fn decode_bar_chart(map: &TermMap<'_>) -> Result<BarChartData, Error> {
    let groups_term = optional_term(map, "groups")
        .ok_or_else(|| crate::decode::missing_field("bar_chart", "groups"))?;
    let group_terms: Vec<Term<'_>> = groups_term
        .decode()
        .map_err(|_| invalid_field("bar_chart", "groups", "expected a list"))?;

    let groups: Vec<BarGroupData> = group_terms
        .into_iter()
        .map(decode_bar_group)
        .collect::<Result<_, _>>()?;

    let bar_width: u16 = decode_optional(map, "bar_width", "bar_chart")?.unwrap_or(1);
    let bar_gap: u16 = decode_optional(map, "bar_gap", "bar_chart")?.unwrap_or(1);
    let group_gap: u16 = decode_optional(map, "group_gap", "bar_chart")?.unwrap_or(0);

    let bar_style = match optional_term(map, "bar_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let value_style = match optional_term(map, "value_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let label_style = match optional_term(map, "label_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let max: Option<u64> = decode_optional(map, "max", "bar_chart")?;

    let direction_str: String =
        decode_optional(map, "direction", "bar_chart")?.unwrap_or_else(|| "vertical".to_string());
    let direction = bar_chart::parse_direction(&direction_str)?;

    let block = decode_optional_block(map)?;

    Ok(BarChartData {
        groups,
        bar_width,
        bar_gap,
        group_gap,
        bar_style,
        value_style,
        label_style,
        max,
        direction,
        block,
    })
}

fn decode_bar_group(term: Term<'_>) -> Result<BarGroupData, Error> {
    let map = decode_map(term, "bar_chart.groups")?;
    let label: Option<String> = decode_optional(&map, "label", "bar_chart.groups")?;

    let bars_term = optional_term(&map, "bars")
        .ok_or_else(|| crate::decode::missing_field("bar_chart.groups", "bars"))?;
    let bar_terms: Vec<Term<'_>> = bars_term
        .decode()
        .map_err(|_| invalid_field("bar_chart.groups", "bars", "expected a list"))?;

    let bars: Vec<BarData> = bar_terms
        .into_iter()
        .map(decode_bar)
        .collect::<Result<_, _>>()?;

    Ok(BarGroupData { label, bars })
}

fn decode_bar(term: Term<'_>) -> Result<BarData, Error> {
    let map = decode_map(term, "bar")?;
    let label: String = decode_required(&map, "label", "bar")?;
    let value: u64 = decode_required(&map, "value", "bar")?;

    let style = match optional_term(&map, "style") {
        Some(style_term) => Some(decode_style(style_term)?),
        None => None,
    };

    let text_value: Option<String> = decode_optional(&map, "text_value", "bar")?;

    Ok(BarData {
        label,
        value,
        style,
        text_value,
    })
}

fn decode_sparkline(map: &TermMap<'_>) -> Result<SparklineData, Error> {
    let data_term = optional_term(map, "data")
        .ok_or_else(|| crate::decode::missing_field("sparkline", "data"))?;
    let entry_terms: Vec<Term<'_>> = data_term
        .decode()
        .map_err(|_| invalid_field("sparkline", "data", "expected a list"))?;

    let data: Vec<Option<u64>> = entry_terms
        .into_iter()
        .map(|term| {
            if term.decode::<Atom>().is_ok() {
                // Nil came through as the atom :nil.
                return Ok(None);
            }
            term.decode::<u64>()
                .map(Some)
                .map_err(|_| invalid_field("sparkline", "data", "expected integer or nil"))
        })
        .collect::<Result<_, _>>()?;

    let style = match optional_term(map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let absent_value_style = match optional_term(map, "absent_value_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let max: Option<u64> = decode_optional(map, "max", "sparkline")?;

    let direction_str: String = decode_optional(map, "direction", "sparkline")?
        .unwrap_or_else(|| "left_to_right".to_string());
    let direction = sparkline::parse_direction(&direction_str)?;

    let bar_set_term = optional_term(map, "bar_set")
        .ok_or_else(|| crate::decode::missing_field("sparkline", "bar_set"))?;
    let bar_set = decode_sparkline_bar_set(bar_set_term)?;

    let absent_value_symbol: Option<String> =
        decode_optional(map, "absent_value_symbol", "sparkline")?;

    let block = decode_optional_block(map)?;

    Ok(SparklineData {
        data,
        style,
        max,
        direction,
        bar_set,
        absent_value_style,
        absent_value_symbol,
        block,
    })
}

fn decode_sparkline_bar_set(term: Term<'_>) -> Result<SparklineBarSet, Error> {
    let (tag, payload): (String, Term<'_>) = term.decode().map_err(|_| {
        invalid_field(
            "sparkline",
            "bar_set",
            "expected {\"preset\", name} or {\"custom\", symbols}",
        )
    })?;

    match tag.as_str() {
        "preset" => {
            let name: String = payload.decode().map_err(|_| {
                invalid_field("sparkline", "bar_set", "preset name must be a string")
            })?;
            match name.as_str() {
                "nine_levels" => Ok(SparklineBarSet::NineLevels),
                "three_levels" => Ok(SparklineBarSet::ThreeLevels),
                other => Err(invalid_field(
                    "sparkline",
                    "bar_set",
                    &format!("unknown preset '{other}'"),
                )),
            }
        }
        "custom" => {
            let symbols: Vec<String> = payload.decode().map_err(|_| {
                invalid_field(
                    "sparkline",
                    "bar_set",
                    "custom symbols must be a list of strings",
                )
            })?;
            if symbols.is_empty() {
                return Err(invalid_field(
                    "sparkline",
                    "bar_set",
                    "custom symbols list must not be empty",
                ));
            }
            Ok(SparklineBarSet::Custom(symbols))
        }
        other => Err(invalid_field(
            "sparkline",
            "bar_set",
            &format!("unknown tag '{other}'"),
        )),
    }
}

fn decode_calendar(map: &TermMap<'_>) -> Result<CalendarData, Error> {
    let year: i32 = decode_required(map, "year", "calendar")?;
    let month: u8 = decode_required(map, "month", "calendar")?;
    let day: u8 = decode_required(map, "day", "calendar")?;
    let display_date = calendar::parse_date(year, month, day)?;

    let show_month_header: bool = decode_required(map, "show_month_header", "calendar")?;
    let show_weekdays_header: bool = decode_required(map, "show_weekdays_header", "calendar")?;

    let header_style = match optional_term(map, "header_style") {
        Some(term) => Some(decode_style(term)?),
        None => None,
    };
    let weekday_style = match optional_term(map, "weekday_style") {
        Some(term) => Some(decode_style(term)?),
        None => None,
    };

    let show_month_header = if show_month_header {
        Some(header_style.unwrap_or_default())
    } else {
        None
    };
    let show_weekdays_header = if show_weekdays_header {
        Some(weekday_style.unwrap_or_default())
    } else {
        None
    };

    let show_surrounding = match optional_term(map, "show_surrounding") {
        Some(term) => Some(decode_style(term)?),
        None => None,
    };

    let default_style = match optional_term(map, "default_style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let events = decode_calendar_events(map)?;

    let block = decode_optional_block(map)?;

    Ok(CalendarData {
        display_date,
        events,
        default_style,
        show_month_header,
        show_weekdays_header,
        show_surrounding,
        block,
    })
}

fn decode_calendar_events(
    map: &TermMap<'_>,
) -> Result<Vec<(time::Date, ratatui::style::Style)>, Error> {
    let Some(term) = optional_term(map, "events") else {
        return Ok(Vec::new());
    };
    let entries: Vec<(Term<'_>, Term<'_>)> = term
        .decode()
        .map_err(|_| invalid_field("calendar", "events", "expected a list of tuples"))?;

    entries
        .into_iter()
        .map(|(date_term, style_term)| {
            let (year, month, day): (i32, u8, u8) = date_term.decode().map_err(|_| {
                invalid_field(
                    "calendar",
                    "events",
                    "date entry must be {year, month, day}",
                )
            })?;
            let date = calendar::parse_date(year, month, day)?;
            let style = decode_style(style_term)?;
            Ok((date, style))
        })
        .collect()
}

fn decode_canvas(map: &TermMap<'_>) -> Result<CanvasData, Error> {
    let x_bounds = decode_canvas_bounds(map, "x_bounds")?;
    let y_bounds = decode_canvas_bounds(map, "y_bounds")?;

    let marker_name: String =
        decode_optional(map, "marker", "canvas")?.unwrap_or_else(|| "braille".to_string());
    let marker = canvas::parse_marker(&marker_name)?;

    let background_color = match optional_term(map, "background_color") {
        Some(term) => Some(crate::style::decode_color(term)?),
        None => None,
    };

    let shapes_term = optional_term(map, "shapes")
        .ok_or_else(|| crate::decode::missing_field("canvas", "shapes"))?;
    let shape_terms: Vec<Term<'_>> = shapes_term
        .decode()
        .map_err(|_| invalid_field("canvas", "shapes", "expected a list"))?;
    let shapes = shape_terms
        .into_iter()
        .map(decode_canvas_shape)
        .collect::<Result<_, _>>()?;

    let block = decode_optional_block(map)?;

    Ok(CanvasData {
        x_bounds,
        y_bounds,
        marker,
        background_color,
        shapes,
        block,
    })
}

fn decode_canvas_bounds(map: &TermMap<'_>, field: &'static str) -> Result<[f64; 2], Error> {
    let term =
        optional_term(map, field).ok_or_else(|| crate::decode::missing_field("canvas", field))?;
    let values: Vec<f64> = term
        .decode()
        .map_err(|_| invalid_field("canvas", field, "expected [min, max]"))?;

    if values.len() != 2 {
        return Err(invalid_field("canvas", field, "expected [min, max]"));
    }

    Ok([values[0], values[1]])
}

fn decode_canvas_shape(term: Term<'_>) -> Result<CanvasShape, Error> {
    let map = decode_map(term, "canvas.shapes")?;
    let tag: String = decode_required(&map, "shape", "canvas.shapes")?;
    let color = crate::style::decode_color(
        optional_term(&map, "color")
            .ok_or_else(|| crate::decode::missing_field("canvas.shapes", "color"))?,
    )?;

    match tag.as_str() {
        "map" => {
            let resolution_str: String = decode_optional(&map, "resolution", "canvas.shapes Map")?
                .unwrap_or_else(|| "low".to_string());
            let resolution = canvas::parse_map_resolution(&resolution_str)?;
            Ok(CanvasShape::Map { resolution, color })
        }
        "label" => Ok(CanvasShape::Label {
            x: decode_required(&map, "x", "canvas.shapes Label")?,
            y: decode_required(&map, "y", "canvas.shapes Label")?,
            text: decode_required(&map, "text", "canvas.shapes Label")?,
            color,
        }),
        "line" => Ok(CanvasShape::Line {
            x1: decode_required(&map, "x1", "canvas.shapes Line")?,
            y1: decode_required(&map, "y1", "canvas.shapes Line")?,
            x2: decode_required(&map, "x2", "canvas.shapes Line")?,
            y2: decode_required(&map, "y2", "canvas.shapes Line")?,
            color,
        }),
        "rectangle" => Ok(CanvasShape::Rectangle {
            x: decode_required(&map, "x", "canvas.shapes Rectangle")?,
            y: decode_required(&map, "y", "canvas.shapes Rectangle")?,
            width: decode_required(&map, "width", "canvas.shapes Rectangle")?,
            height: decode_required(&map, "height", "canvas.shapes Rectangle")?,
            color,
        }),
        "circle" => Ok(CanvasShape::Circle {
            x: decode_required(&map, "x", "canvas.shapes Circle")?,
            y: decode_required(&map, "y", "canvas.shapes Circle")?,
            radius: decode_required(&map, "radius", "canvas.shapes Circle")?,
            color,
        }),
        "points" => {
            let coords_term = optional_term(&map, "coords")
                .ok_or_else(|| crate::decode::missing_field("canvas.shapes Points", "coords"))?;
            let coord_pairs: Vec<Vec<f64>> = coords_term.decode().map_err(|_| {
                invalid_field(
                    "canvas.shapes Points",
                    "coords",
                    "expected a list of [x, y] pairs",
                )
            })?;
            let coords = coord_pairs
                .into_iter()
                .map(|pair| {
                    if pair.len() != 2 {
                        return Err(invalid_field(
                            "canvas.shapes Points",
                            "coords",
                            "each entry must be [x, y]",
                        ));
                    }
                    Ok((pair[0], pair[1]))
                })
                .collect::<Result<_, _>>()?;
            Ok(CanvasShape::Points { coords, color })
        }
        other => Err(invalid_field(
            "canvas.shapes",
            "shape",
            &format!("unknown shape '{other}'"),
        )),
    }
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
    let resource = decode_text_input_state(map)?;

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
    let resource = decode_textarea_state(map)?;

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

fn decode_chart(map: &TermMap<'_>) -> Result<ChartData, Error> {
    let datasets_term = optional_term(map, "datasets")
        .ok_or_else(|| crate::decode::missing_field("chart", "datasets"))?;
    let dataset_terms: Vec<Term<'_>> = datasets_term
        .decode()
        .map_err(|_| invalid_field("chart", "datasets", "expected a list"))?;
    let datasets: Vec<DatasetData> = dataset_terms
        .into_iter()
        .map(decode_dataset)
        .collect::<Result<_, _>>()?;

    let x_axis_term = optional_term(map, "x_axis")
        .ok_or_else(|| crate::decode::missing_field("chart", "x_axis"))?;
    let x_axis = decode_axis(x_axis_term, "x_axis")?;

    let y_axis_term = optional_term(map, "y_axis")
        .ok_or_else(|| crate::decode::missing_field("chart", "y_axis"))?;
    let y_axis = decode_axis(y_axis_term, "y_axis")?;

    let hide_legend: bool = decode_optional(map, "hide_legend", "chart")?.unwrap_or(false);

    let legend_position = match decode_optional::<String>(map, "legend_position", "chart")? {
        Some(s) => Some(chart::parse_legend_position(&s)?),
        None => None,
    };

    let hidden_legend_constraints = match optional_term(map, "hidden_legend_constraints") {
        Some(term) => {
            let terms: Vec<Term<'_>> = term.decode().map_err(|_| {
                invalid_field(
                    "chart",
                    "hidden_legend_constraints",
                    "expected a list of two constraints",
                )
            })?;
            if terms.len() != 2 {
                return Err(invalid_field(
                    "chart",
                    "hidden_legend_constraints",
                    "expected exactly two constraints",
                ));
            }
            Some((decode_constraint(terms[0])?, decode_constraint(terms[1])?))
        }
        None => None,
    };

    let block = decode_optional_block(map)?;

    Ok(ChartData {
        datasets,
        x_axis,
        y_axis,
        legend_position,
        hide_legend,
        hidden_legend_constraints,
        block,
    })
}

fn decode_dataset(term: Term<'_>) -> Result<DatasetData, Error> {
    let map = decode_map(term, "chart.datasets")?;

    let name: Option<String> = decode_optional(&map, "name", "chart.datasets")?;

    let data_term = optional_term(&map, "data")
        .ok_or_else(|| crate::decode::missing_field("chart.datasets", "data"))?;
    let pairs: Vec<Vec<f64>> = data_term
        .decode()
        .map_err(|_| invalid_field("chart.datasets", "data", "expected a list of [x, y] pairs"))?;
    let data = pairs
        .into_iter()
        .map(|pair| {
            if pair.len() != 2 {
                return Err(invalid_field(
                    "chart.datasets",
                    "data",
                    "each entry must be [x, y]",
                ));
            }
            Ok((pair[0], pair[1]))
        })
        .collect::<Result<_, _>>()?;

    let marker_name: String =
        decode_optional(&map, "marker", "chart.datasets")?.unwrap_or_else(|| "braille".to_string());
    let marker = canvas::parse_marker(&marker_name)?;

    let graph_type_name: String = decode_optional(&map, "graph_type", "chart.datasets")?
        .unwrap_or_else(|| "line".to_string());
    let graph_type = chart::parse_graph_type(&graph_type_name)?;

    let style = match optional_term(&map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    Ok(DatasetData {
        name,
        data,
        marker,
        graph_type,
        style,
    })
}

fn decode_axis(term: Term<'_>, field: &'static str) -> Result<AxisData, Error> {
    let map = decode_map(term, &format!("chart.{field}"))?;

    let bounds_term = optional_term(&map, "bounds")
        .ok_or_else(|| crate::decode::missing_field(&format!("chart.{field}"), "bounds"))?;
    let bounds_vec: Vec<f64> = bounds_term
        .decode()
        .map_err(|_| invalid_field("chart", field, "expected bounds as [min, max]"))?;
    if bounds_vec.len() != 2 {
        return Err(invalid_field(
            "chart",
            field,
            "expected bounds as [min, max]",
        ));
    }
    let bounds = [bounds_vec[0], bounds_vec[1]];

    let labels = match optional_term(&map, "labels") {
        Some(labels_term) => {
            let label_terms: Vec<Term<'_>> = labels_term
                .decode()
                .map_err(|_| invalid_field("chart", field, "labels must be a list"))?;
            label_terms
                .into_iter()
                .map(text::decode_line)
                .collect::<Result<_, _>>()?
        }
        None => Vec::new(),
    };

    let style = match optional_term(&map, "style") {
        Some(term) => decode_style(term)?,
        None => ratatui::style::Style::default(),
    };

    let alignment = match decode_optional::<String>(&map, "labels_alignment", "chart")? {
        Some(s) => match s.as_str() {
            "center" => Alignment::Center,
            "right" => Alignment::Right,
            "left" => Alignment::Left,
            other => {
                return Err(invalid_field(
                    "chart",
                    field,
                    &format!("unknown labels_alignment '{other}'"),
                ))
            }
        },
        None => Alignment::Left,
    };

    let title = match optional_term(&map, "title") {
        Some(term) => Some(text::decode_line(term)?),
        None => None,
    };

    Ok(AxisData {
        title,
        bounds,
        labels,
        style,
        labels_alignment: alignment,
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
        WidgetData::BarChart(data) => bar_chart::render(buf, data, area),
        WidgetData::Sparkline(data) => sparkline::render(buf, data, area),
        WidgetData::Calendar(data) => calendar::render(buf, data, area),
        WidgetData::Canvas(data) => canvas::render(buf, data, area),
        WidgetData::Chart(data) => chart::render(buf, data, area),
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

/// Decodes the `"state"` field for a TextInput widget.
///
/// Accepts either a `ResourceArc<TextInputResource>` (local rendering) or a
/// `{value, cursor, viewport_offset}` snapshot tuple (distributed rendering
/// where the NIF reference could not cross the node boundary). When a snapshot
/// is received, a temporary `ResourceArc` is constructed so the rest of the
/// decode + render pipeline stays uniform.
fn decode_text_input_state(map: &TermMap<'_>) -> Result<ResourceArc<TextInputResource>, Error> {
    match map.get("state").copied() {
        Some(term) => {
            // Fast path: local NIF reference.
            if let Ok(resource) = term.decode::<ResourceArc<TextInputResource>>() {
                return Ok(resource);
            }
            // Distributed snapshot: {value, cursor, viewport_offset}.
            let (value, cursor, viewport_offset): (String, usize, usize) = term
                .decode()
                .map_err(|_| invalid_field("text_input", "state", "unexpected value"))?;
            Ok(ResourceArc::new(TextInputResource {
                state: std::sync::Mutex::new(TextInputState {
                    value,
                    cursor,
                    viewport_offset,
                }),
            }))
        }
        None => Err(crate::decode::missing_field("text_input", "state")),
    }
}

/// Decodes the `"state"` field for a Textarea widget.
///
/// Same dual-path logic as `decode_text_input_state`: accepts a
/// `ResourceArc<TextareaResource>` or a `{value, cursor_row, cursor_col}`
/// snapshot tuple. The snapshot path creates a fresh `TextArea`, sets its
/// text content, and positions the cursor via `CursorMove::Jump`.
fn decode_textarea_state(map: &TermMap<'_>) -> Result<ResourceArc<TextareaResource>, Error> {
    match map.get("state").copied() {
        Some(term) => {
            if let Ok(resource) = term.decode::<ResourceArc<TextareaResource>>() {
                return Ok(resource);
            }
            let (value, cursor_row, cursor_col): (String, usize, usize) = term
                .decode()
                .map_err(|_| invalid_field("textarea", "state", "unexpected value"))?;
            let lines: Vec<String> = value.split('\n').map(|s| s.to_string()).collect();
            let mut textarea = ratatui_textarea::TextArea::new(lines);
            textarea.move_cursor(ratatui_textarea::CursorMove::Jump(
                cursor_row as u16,
                cursor_col as u16,
            ));
            Ok(ResourceArc::new(TextareaResource {
                state: std::sync::Mutex::new(textarea),
            }))
        }
        None => Err(crate::decode::missing_field("textarea", "state")),
    }
}
