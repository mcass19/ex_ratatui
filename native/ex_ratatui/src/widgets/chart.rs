use ratatui::buffer::Buffer;
use ratatui::layout::{Alignment, Constraint, Rect};
use ratatui::style::Style;
use ratatui::symbols::Marker;
use ratatui::text::Line;
use ratatui::widgets::{Axis, Chart, Dataset, GraphType, LegendPosition, Widget};

use crate::widgets::block::BlockData;

pub struct DatasetData {
    pub name: Option<String>,
    pub data: Vec<(f64, f64)>,
    pub marker: Marker,
    pub graph_type: GraphType,
    pub style: Style,
}

pub struct AxisData {
    pub title: Option<Line<'static>>,
    pub bounds: [f64; 2],
    pub labels: Vec<Line<'static>>,
    pub style: Style,
    pub labels_alignment: Alignment,
}

pub struct ChartData {
    pub datasets: Vec<DatasetData>,
    pub x_axis: AxisData,
    pub y_axis: AxisData,
    pub legend_position: Option<LegendPosition>,
    pub hide_legend: bool,
    pub hidden_legend_constraints: Option<(Constraint, Constraint)>,
    pub block: Option<BlockData>,
}

pub fn parse_graph_type(value: &str) -> Result<GraphType, rustler::Error> {
    match value {
        "line" => Ok(GraphType::Line),
        "scatter" => Ok(GraphType::Scatter),
        "bar" => Ok(GraphType::Bar),
        other => Err(crate::decode::invalid_field(
            "chart.datasets",
            "graph_type",
            &format!("unknown graph_type '{other}'"),
        )),
    }
}

pub fn parse_legend_position(value: &str) -> Result<LegendPosition, rustler::Error> {
    match value {
        "top" => Ok(LegendPosition::Top),
        "top_left" => Ok(LegendPosition::TopLeft),
        "top_right" => Ok(LegendPosition::TopRight),
        "bottom" => Ok(LegendPosition::Bottom),
        "bottom_left" => Ok(LegendPosition::BottomLeft),
        "bottom_right" => Ok(LegendPosition::BottomRight),
        "left" => Ok(LegendPosition::Left),
        "right" => Ok(LegendPosition::Right),
        other => Err(crate::decode::invalid_field(
            "chart",
            "legend_position",
            &format!("unknown legend_position '{other}'"),
        )),
    }
}

fn build_axis(data: &AxisData) -> Axis<'_> {
    let mut axis = Axis::default()
        .bounds(data.bounds)
        .style(data.style)
        .labels_alignment(data.labels_alignment);

    if !data.labels.is_empty() {
        axis = axis.labels(data.labels.clone());
    }

    if let Some(title) = &data.title {
        axis = axis.title(title.clone());
    }

    axis
}

pub fn render(buf: &mut Buffer, data: &ChartData, area: Rect) {
    let datasets: Vec<Dataset<'_>> = data
        .datasets
        .iter()
        .map(|d| {
            let mut dataset = Dataset::default()
                .data(&d.data)
                .marker(d.marker)
                .graph_type(d.graph_type)
                .style(d.style);

            if let Some(name) = &d.name {
                dataset = dataset.name(name.clone());
            }

            dataset
        })
        .collect();

    let mut chart = Chart::new(datasets)
        .x_axis(build_axis(&data.x_axis))
        .y_axis(build_axis(&data.y_axis));

    if data.hide_legend {
        chart = chart.legend_position(None);
    } else if let Some(pos) = data.legend_position {
        chart = chart.legend_position(Some(pos));
    }

    if let Some(constraints) = data.hidden_legend_constraints {
        chart = chart.hidden_legend_constraints(constraints);
    }

    if let Some(ref block_data) = data.block {
        chart = chart.block(block_data.to_block());
    }

    chart.render(area, buf);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_to_string;
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use ratatui::Terminal;

    fn axis(bounds: [f64; 2]) -> AxisData {
        AxisData {
            title: None,
            bounds,
            labels: vec![],
            style: Style::default(),
            labels_alignment: Alignment::Left,
        }
    }

    fn dataset(name: &str, data: Vec<(f64, f64)>, graph_type: GraphType) -> DatasetData {
        DatasetData {
            name: Some(name.to_string()),
            data,
            marker: Marker::Braille,
            graph_type,
            style: Style::default().fg(Color::Cyan),
        }
    }

    fn base(datasets: Vec<DatasetData>) -> ChartData {
        ChartData {
            datasets,
            x_axis: axis([0.0, 10.0]),
            y_axis: axis([0.0, 10.0]),
            legend_position: Some(LegendPosition::TopRight),
            hide_legend: false,
            hidden_legend_constraints: None,
            block: None,
        }
    }

    fn render_to_terminal(data: &ChartData, width: u16, height: u16) -> Terminal<TestBackend> {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|frame| render(frame.buffer_mut(), data, Rect::new(0, 0, width, height)))
            .unwrap();
        terminal
    }

    #[test]
    fn renders_line_chart() {
        let data = base(vec![dataset(
            "temp",
            vec![(0.0, 1.0), (5.0, 5.0), (10.0, 9.0)],
            GraphType::Line,
        )]);
        let terminal = render_to_terminal(&data, 40, 12);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("temp"));
    }

    #[test]
    fn renders_scatter_chart() {
        let data = base(vec![dataset(
            "points",
            vec![(1.0, 2.0), (4.0, 5.0), (7.0, 8.0)],
            GraphType::Scatter,
        )]);
        let _ = render_to_terminal(&data, 40, 12);
    }

    #[test]
    fn renders_bar_chart_graph_type() {
        let data = base(vec![dataset(
            "freq",
            vec![(0.0, 3.0), (1.0, 5.0), (2.0, 7.0)],
            GraphType::Bar,
        )]);
        let _ = render_to_terminal(&data, 40, 12);
    }

    #[test]
    fn renders_multiple_datasets() {
        let data = base(vec![
            dataset(
                "cpu",
                vec![(0.0, 1.0), (5.0, 4.0), (10.0, 7.0)],
                GraphType::Line,
            ),
            DatasetData {
                name: Some("mem".to_string()),
                data: vec![(0.0, 8.0), (5.0, 6.0), (10.0, 5.0)],
                marker: Marker::Dot,
                graph_type: GraphType::Line,
                style: Style::default().fg(Color::Magenta),
            },
        ]);
        let terminal = render_to_terminal(&data, 50, 15);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("cpu"));
        assert!(rendered.contains("mem"));
    }

    #[test]
    fn empty_datasets_renders_without_panic() {
        let data = base(vec![]);
        let _ = render_to_terminal(&data, 30, 8);
    }

    #[test]
    fn legend_position_top_left_renders() {
        let mut data = base(vec![dataset(
            "a",
            vec![(0.0, 1.0), (10.0, 9.0)],
            GraphType::Line,
        )]);
        data.legend_position = Some(LegendPosition::TopLeft);
        let terminal = render_to_terminal(&data, 40, 12);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("a"));
    }

    #[test]
    fn hide_legend_omits_dataset_name() {
        let mut data = base(vec![dataset(
            "secret",
            vec![(0.0, 1.0), (10.0, 9.0)],
            GraphType::Line,
        )]);
        data.hide_legend = true;
        let terminal = render_to_terminal(&data, 40, 12);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.contains("secret"));
    }

    #[test]
    fn hidden_legend_constraints_apply_in_tight_area() {
        let mut data = base(vec![dataset(
            "tight",
            vec![(0.0, 1.0), (10.0, 9.0)],
            GraphType::Line,
        )]);
        // Require legend to fit in 3 cells wide and 1 tall — too small for the "tight" label.
        data.hidden_legend_constraints = Some((Constraint::Length(3), Constraint::Length(1)));
        let terminal = render_to_terminal(&data, 20, 6);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.contains("tight"));
    }

    #[test]
    fn axis_with_title_and_labels_renders() {
        let mut data = base(vec![dataset(
            "a",
            vec![(0.0, 1.0), (10.0, 9.0)],
            GraphType::Line,
        )]);
        data.x_axis.title = Some(Line::from("X-Axis"));
        data.x_axis.labels = vec![Line::from("0"), Line::from("5"), Line::from("10")];
        let terminal = render_to_terminal(&data, 50, 12);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("X-Axis"));
    }

    #[test]
    fn renders_with_block_title() {
        let mut data = base(vec![dataset(
            "a",
            vec![(0.0, 1.0), (10.0, 9.0)],
            GraphType::Line,
        )]);
        data.block = Some(BlockData {
            title: Some(Line::from("Plot")),
            borders: ratatui::widgets::Borders::ALL,
            border_type: ratatui::widgets::BorderType::Plain,
            border_style: Style::default(),
            style: Style::default(),
            padding: ratatui::widgets::Padding::new(0, 0, 0, 0),
        });
        let terminal = render_to_terminal(&data, 40, 10);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("Plot"));
    }

    #[test]
    fn parse_graph_type_accepts_known() {
        assert!(matches!(parse_graph_type("line"), Ok(GraphType::Line)));
        assert!(matches!(
            parse_graph_type("scatter"),
            Ok(GraphType::Scatter)
        ));
        assert!(matches!(parse_graph_type("bar"), Ok(GraphType::Bar)));
    }

    #[test]
    fn parse_graph_type_rejects_unknown() {
        assert!(parse_graph_type("pie").is_err());
    }

    #[test]
    fn parse_legend_position_accepts_all_eight() {
        assert!(matches!(
            parse_legend_position("top"),
            Ok(LegendPosition::Top)
        ));
        assert!(matches!(
            parse_legend_position("top_left"),
            Ok(LegendPosition::TopLeft)
        ));
        assert!(matches!(
            parse_legend_position("top_right"),
            Ok(LegendPosition::TopRight)
        ));
        assert!(matches!(
            parse_legend_position("bottom"),
            Ok(LegendPosition::Bottom)
        ));
        assert!(matches!(
            parse_legend_position("bottom_left"),
            Ok(LegendPosition::BottomLeft)
        ));
        assert!(matches!(
            parse_legend_position("bottom_right"),
            Ok(LegendPosition::BottomRight)
        ));
        assert!(matches!(
            parse_legend_position("left"),
            Ok(LegendPosition::Left)
        ));
        assert!(matches!(
            parse_legend_position("right"),
            Ok(LegendPosition::Right)
        ));
    }

    #[test]
    fn parse_legend_position_rejects_unknown() {
        assert!(parse_legend_position("middle").is_err());
    }
}
