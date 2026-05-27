use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};
use ratatui::symbols::Marker;
use ratatui::text::{Line as TextLine, Span};
use ratatui::widgets::canvas::{Canvas, Circle, Line, Map, MapResolution, Points, Rectangle};
use ratatui::widgets::Widget;

use crate::widgets::block::BlockData;

pub enum CanvasShape {
    Line {
        x1: f64,
        y1: f64,
        x2: f64,
        y2: f64,
        color: Color,
    },
    Rectangle {
        x: f64,
        y: f64,
        width: f64,
        height: f64,
        color: Color,
    },
    Circle {
        x: f64,
        y: f64,
        radius: f64,
        color: Color,
    },
    Points {
        coords: Vec<(f64, f64)>,
        color: Color,
    },
    Map {
        resolution: MapResolution,
        color: Color,
    },
    Label {
        x: f64,
        y: f64,
        text: String,
        color: Color,
    },
}

pub struct CanvasData {
    pub x_bounds: [f64; 2],
    pub y_bounds: [f64; 2],
    pub marker: Marker,
    pub background_color: Option<Color>,
    pub shapes: Vec<CanvasShape>,
    pub block: Option<BlockData>,
}

pub fn parse_marker(value: &str) -> Result<Marker, rustler::Error> {
    match value {
        "braille" => Ok(Marker::Braille),
        "dot" => Ok(Marker::Dot),
        "block" => Ok(Marker::Block),
        "bar" => Ok(Marker::Bar),
        "half_block" => Ok(Marker::HalfBlock),
        other => Err(crate::decode::invalid_field(
            "canvas",
            "marker",
            &format!("unknown marker '{other}'"),
        )),
    }
}

pub fn parse_map_resolution(value: &str) -> Result<MapResolution, rustler::Error> {
    match value {
        "low" => Ok(MapResolution::Low),
        "high" => Ok(MapResolution::High),
        other => Err(crate::decode::invalid_field(
            "canvas.shapes Map",
            "resolution",
            &format!("unknown resolution '{other}'"),
        )),
    }
}

pub fn render(buf: &mut Buffer, data: &CanvasData, area: Rect) {
    let mut canvas = Canvas::default()
        .x_bounds(data.x_bounds)
        .y_bounds(data.y_bounds)
        .marker(data.marker)
        .paint(|ctx| {
            for shape in &data.shapes {
                match shape {
                    CanvasShape::Line {
                        x1,
                        y1,
                        x2,
                        y2,
                        color,
                    } => ctx.draw(&Line {
                        x1: *x1,
                        y1: *y1,
                        x2: *x2,
                        y2: *y2,
                        color: *color,
                    }),
                    CanvasShape::Rectangle {
                        x,
                        y,
                        width,
                        height,
                        color,
                    } => ctx.draw(&Rectangle {
                        x: *x,
                        y: *y,
                        width: *width,
                        height: *height,
                        color: *color,
                    }),
                    CanvasShape::Circle {
                        x,
                        y,
                        radius,
                        color,
                    } => ctx.draw(&Circle {
                        x: *x,
                        y: *y,
                        radius: *radius,
                        color: *color,
                    }),
                    CanvasShape::Points { coords, color } => ctx.draw(&Points {
                        coords,
                        color: *color,
                    }),
                    CanvasShape::Map { resolution, color } => ctx.draw(&Map {
                        resolution: *resolution,
                        color: *color,
                    }),
                    CanvasShape::Label { x, y, text, color } => {
                        let span = Span::styled(text.clone(), Style::default().fg(*color));
                        ctx.print(*x, *y, TextLine::from(span));
                    }
                }
            }
        });

    if let Some(bg) = data.background_color {
        canvas = canvas.background_color(bg);
    }

    if let Some(ref block_data) = data.block {
        canvas = canvas.block(block_data.to_block());
    }

    canvas.render(area, buf);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::helpers::buffer_to_string;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    fn base(shapes: Vec<CanvasShape>) -> CanvasData {
        CanvasData {
            x_bounds: [0.0, 10.0],
            y_bounds: [0.0, 10.0],
            marker: Marker::Braille,
            background_color: None,
            shapes,
            block: None,
        }
    }

    fn render_to_terminal(data: &CanvasData, width: u16, height: u16) -> Terminal<TestBackend> {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|frame| render(frame.buffer_mut(), data, Rect::new(0, 0, width, height)))
            .unwrap();
        terminal
    }

    #[test]
    fn renders_line() {
        let data = base(vec![CanvasShape::Line {
            x1: 0.0,
            y1: 0.0,
            x2: 10.0,
            y2: 10.0,
            color: Color::Red,
        }]);
        let terminal = render_to_terminal(&data, 20, 10);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.trim().is_empty());
    }

    #[test]
    fn renders_rectangle() {
        let data = base(vec![CanvasShape::Rectangle {
            x: 1.0,
            y: 1.0,
            width: 5.0,
            height: 3.0,
            color: Color::Green,
        }]);
        let terminal = render_to_terminal(&data, 20, 10);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.trim().is_empty());
    }

    #[test]
    fn renders_circle() {
        let data = base(vec![CanvasShape::Circle {
            x: 5.0,
            y: 5.0,
            radius: 3.0,
            color: Color::Yellow,
        }]);
        let terminal = render_to_terminal(&data, 20, 10);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.trim().is_empty());
    }

    #[test]
    fn renders_points() {
        let data = base(vec![CanvasShape::Points {
            coords: vec![(1.0, 1.0), (2.0, 3.0), (5.0, 5.0)],
            color: Color::Magenta,
        }]);
        let terminal = render_to_terminal(&data, 20, 10);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.trim().is_empty());
    }

    #[test]
    fn renders_multiple_shapes() {
        let data = base(vec![
            CanvasShape::Line {
                x1: 0.0,
                y1: 0.0,
                x2: 10.0,
                y2: 0.0,
                color: Color::Red,
            },
            CanvasShape::Circle {
                x: 5.0,
                y: 5.0,
                radius: 2.0,
                color: Color::Blue,
            },
        ]);
        let terminal = render_to_terminal(&data, 20, 10);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.trim().is_empty());
    }

    #[test]
    fn empty_shapes_renders_without_panic() {
        let data = base(vec![]);
        let _ = render_to_terminal(&data, 20, 10);
    }

    #[test]
    fn dot_marker_renders() {
        let mut data = base(vec![CanvasShape::Points {
            coords: vec![(5.0, 5.0)],
            color: Color::White,
        }]);
        data.marker = Marker::Dot;
        let terminal = render_to_terminal(&data, 20, 10);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.trim().is_empty());
    }

    #[test]
    fn background_color_applies() {
        let mut data = base(vec![]);
        data.background_color = Some(Color::Blue);
        let _ = render_to_terminal(&data, 20, 10);
    }

    #[test]
    fn with_block_title_renders() {
        let mut data = base(vec![CanvasShape::Points {
            coords: vec![(5.0, 5.0)],
            color: Color::White,
        }]);
        data.block = Some(BlockData {
            title: Some(ratatui::text::Line::from("Plot")),
            borders: ratatui::widgets::Borders::ALL,
            ..Default::default()
        });
        let terminal = render_to_terminal(&data, 20, 5);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("Plot"));
    }

    #[test]
    fn parse_marker_accepts_all_known() {
        assert!(matches!(parse_marker("braille"), Ok(Marker::Braille)));
        assert!(matches!(parse_marker("dot"), Ok(Marker::Dot)));
        assert!(matches!(parse_marker("block"), Ok(Marker::Block)));
        assert!(matches!(parse_marker("bar"), Ok(Marker::Bar)));
        assert!(matches!(parse_marker("half_block"), Ok(Marker::HalfBlock)));
    }

    #[test]
    fn parse_marker_rejects_unknown() {
        assert!(parse_marker("quadrant").is_err());
    }

    #[test]
    fn renders_map_low_resolution() {
        let mut data = base(vec![CanvasShape::Map {
            resolution: MapResolution::Low,
            color: Color::Green,
        }]);
        data.x_bounds = [-180.0, 180.0];
        data.y_bounds = [-90.0, 90.0];
        data.marker = Marker::Dot;
        let terminal = render_to_terminal(&data, 60, 20);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.trim().is_empty());
    }

    #[test]
    fn renders_map_high_resolution() {
        let mut data = base(vec![CanvasShape::Map {
            resolution: MapResolution::High,
            color: Color::Cyan,
        }]);
        data.x_bounds = [-180.0, 180.0];
        data.y_bounds = [-90.0, 90.0];
        let terminal = render_to_terminal(&data, 80, 30);
        let rendered = buffer_to_string(&terminal);
        assert!(!rendered.trim().is_empty());
    }

    #[test]
    fn renders_label_text() {
        let data = base(vec![CanvasShape::Label {
            x: 1.0,
            y: 5.0,
            text: "origin".to_string(),
            color: Color::White,
        }]);
        let terminal = render_to_terminal(&data, 30, 10);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("origin"));
    }

    #[test]
    fn label_color_applies_to_text() {
        let data = base(vec![CanvasShape::Label {
            x: 1.0,
            y: 5.0,
            text: "X".to_string(),
            color: Color::Red,
        }]);
        let terminal = render_to_terminal(&data, 30, 10);
        let buffer = terminal.backend().buffer();
        let cells = (0..buffer.area.width)
            .flat_map(|x| (0..buffer.area.height).map(move |y| (x, y)))
            .filter_map(|(x, y)| buffer.cell((x, y)));
        let has_red = cells
            .filter(|c| c.symbol() == "X")
            .any(|c| c.fg == Color::Red);
        assert!(has_red, "expected at least one red 'X' cell");
    }

    #[test]
    fn label_and_shape_render_together() {
        let data = base(vec![
            CanvasShape::Circle {
                x: 5.0,
                y: 5.0,
                radius: 2.0,
                color: Color::Yellow,
            },
            CanvasShape::Label {
                x: 5.0,
                y: 5.0,
                text: "*".to_string(),
                color: Color::White,
            },
        ]);
        let terminal = render_to_terminal(&data, 30, 10);
        let rendered = buffer_to_string(&terminal);
        assert!(rendered.contains("*"));
    }

    #[test]
    fn parse_map_resolution_accepts_known() {
        assert!(matches!(
            parse_map_resolution("low"),
            Ok(MapResolution::Low)
        ));
        assert!(matches!(
            parse_map_resolution("high"),
            Ok(MapResolution::High)
        ));
    }

    #[test]
    fn parse_map_resolution_rejects_unknown() {
        assert!(parse_map_resolution("medium").is_err());
    }
}
