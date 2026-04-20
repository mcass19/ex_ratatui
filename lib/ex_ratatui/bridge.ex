defmodule ExRatatui.Bridge do
  @moduledoc """
  Internal bridge between Elixir widget structs and the native render command format.

  This module owns validation and encoding for render commands so both
  `ExRatatui.draw/2` and `ExRatatui.Session.draw/2` cross the NIF boundary
  through the same path.
  """

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.{Coerce, Encode}
  alias ExRatatui.Widget.Expander

  alias ExRatatui.Widgets.{
    Bar,
    BarChart,
    Block,
    Calendar,
    Canvas,
    Checkbox,
    Clear,
    Gauge,
    LineGauge,
    List,
    Markdown,
    Paragraph,
    Popup,
    Scrollbar,
    Sparkline,
    Table,
    Tabs,
    Textarea,
    TextInput,
    Throbber,
    WidgetList
  }

  alias ExRatatui.Widgets.Canvas.{Circle, Line, Points, Rectangle}

  @doc false
  @spec encode_commands!([{ExRatatui.widget(), Rect.t()}]) :: [{map(), map()}]
  def encode_commands!(widgets) when is_list(widgets) do
    widgets
    |> Expander.expand!()
    |> Enum.map(&encode_command/1)
  end

  @doc false
  @spec encode_command({ExRatatui.widget(), Rect.t()}) :: {map(), map()}
  def encode_command({widget, %Rect{} = rect}) do
    {encode_widget(widget), encode_rect(rect)}
  end

  @doc false
  def encode_command(other) do
    raise ArgumentError,
          "expected a render command in the form {widget, %ExRatatui.Layout.Rect{}}, got: #{inspect(other)}"
  end

  defp encode_widget(%Paragraph{} = paragraph) do
    %{
      "type" => "paragraph",
      "text" => paragraph.text |> Coerce.coerce_text!() |> Encode.to_wire_text!(),
      "style" => encode_style(paragraph.style, "paragraph.style"),
      "alignment" => Atom.to_string(paragraph.alignment),
      "wrap" => paragraph.wrap,
      "scroll_y" => elem(paragraph.scroll, 0),
      "scroll_x" => elem(paragraph.scroll, 1)
    }
    |> maybe_put_block(paragraph.block, "paragraph.block")
  end

  defp encode_widget(%Block{} = block) do
    block
    |> encode_block("block")
    |> Map.put("type", "block")
  end

  defp encode_widget(%List{} = list) do
    %{
      "type" => "list",
      "items" =>
        Enum.map(list.items, fn item ->
          item |> Coerce.coerce_text!() |> Encode.to_wire_text!()
        end),
      "style" => encode_style(list.style, "list.style"),
      "highlight_style" => encode_style(list.highlight_style, "list.highlight_style")
    }
    |> maybe_put("highlight_symbol", list.highlight_symbol)
    |> maybe_put("selected", list.selected)
    |> maybe_put_block(list.block, "list.block")
  end

  defp encode_widget(%Table{} = table) do
    %{
      "type" => "table",
      "rows" =>
        Enum.map(table.rows, fn row ->
          Enum.map(row, &encode_line_like/1)
        end),
      "widths" => Enum.map(table.widths, &encode_constraint(&1, "table.widths")),
      "style" => encode_style(table.style, "table.style"),
      "highlight_style" => encode_style(table.highlight_style, "table.highlight_style"),
      "column_spacing" => table.column_spacing
    }
    |> maybe_put("header", encode_table_header(table.header))
    |> maybe_put("highlight_symbol", table.highlight_symbol)
    |> maybe_put("selected", table.selected)
    |> maybe_put_block(table.block, "table.block")
  end

  defp encode_widget(%Clear{}) do
    %{"type" => "clear"}
  end

  defp encode_widget(%Gauge{} = gauge) do
    %{
      "type" => "gauge",
      "ratio" => gauge.ratio * 1.0,
      "style" => encode_style(gauge.style, "gauge.style"),
      "gauge_style" => encode_style(gauge.gauge_style, "gauge.gauge_style")
    }
    |> maybe_put("label", gauge.label)
    |> maybe_put_block(gauge.block, "gauge.block")
  end

  defp encode_widget(%LineGauge{} = line_gauge) do
    %{
      "type" => "line_gauge",
      "ratio" => line_gauge.ratio * 1.0,
      "style" => encode_style(line_gauge.style, "line_gauge.style"),
      "filled_style" => encode_style(line_gauge.filled_style, "line_gauge.filled_style"),
      "unfilled_style" => encode_style(line_gauge.unfilled_style, "line_gauge.unfilled_style")
    }
    |> maybe_put("label", line_gauge.label)
    |> maybe_put_block(line_gauge.block, "line_gauge.block")
  end

  defp encode_widget(%BarChart{} = chart) do
    unless chart.direction in [:vertical, :horizontal] do
      raise ArgumentError,
            "bar_chart.direction expected :vertical or :horizontal, got: #{inspect(chart.direction)}"
    end

    %{
      "type" => "bar_chart",
      "data" => encode_bars(chart.data),
      "bar_width" => chart.bar_width,
      "bar_gap" => chart.bar_gap,
      "bar_style" => encode_style(chart.bar_style, "bar_chart.bar_style"),
      "value_style" => encode_style(chart.value_style, "bar_chart.value_style"),
      "label_style" => encode_style(chart.label_style, "bar_chart.label_style"),
      "direction" => Atom.to_string(chart.direction)
    }
    |> maybe_put("max", chart.max)
    |> maybe_put_block(chart.block, "bar_chart.block")
  end

  defp encode_widget(%Sparkline{} = sparkline) do
    unless sparkline.direction in [:left_to_right, :right_to_left] do
      raise ArgumentError,
            "sparkline.direction expected :left_to_right or :right_to_left, got: #{inspect(sparkline.direction)}"
    end

    validate_sparkline_max!(sparkline.max)

    %{
      "type" => "sparkline",
      "data" => encode_sparkline_data(sparkline.data),
      "direction" => Atom.to_string(sparkline.direction),
      "bar_set" => encode_bar_set(sparkline.bar_set)
    }
    |> maybe_put_style("style", sparkline.style, "sparkline.style")
    |> maybe_put_style(
      "absent_value_style",
      sparkline.absent_value_style,
      "sparkline.absent_value_style"
    )
    |> maybe_put("max", sparkline.max)
    |> maybe_put("absent_value_symbol", sparkline.absent_value_symbol)
    |> maybe_put_block(sparkline.block, "sparkline.block")
  end

  defp encode_widget(%Calendar{} = calendar) do
    validate_calendar_display_date!(calendar.display_date)
    validate_calendar_bool!("show_month_header", calendar.show_month_header)
    validate_calendar_bool!("show_weekdays_header", calendar.show_weekdays_header)

    %Date{year: year, month: month, day: day} = calendar.display_date

    %{
      "type" => "calendar",
      "year" => year,
      "month" => month,
      "day" => day,
      "show_month_header" => calendar.show_month_header,
      "show_weekdays_header" => calendar.show_weekdays_header,
      "events" => encode_calendar_events(calendar.events)
    }
    |> maybe_put_style("default_style", calendar.default_style, "calendar.default_style")
    |> maybe_put_style("header_style", calendar.header_style, "calendar.header_style")
    |> maybe_put_style("weekday_style", calendar.weekday_style, "calendar.weekday_style")
    |> maybe_put_style("show_surrounding", calendar.show_surrounding, "calendar.show_surrounding")
    |> maybe_put_block(calendar.block, "calendar.block")
  end

  defp encode_widget(%Canvas{} = canvas) do
    validate_canvas_bounds!("x_bounds", canvas.x_bounds)
    validate_canvas_bounds!("y_bounds", canvas.y_bounds)
    validate_canvas_marker!(canvas.marker)

    %{
      "type" => "canvas",
      "x_bounds" => encode_canvas_bounds(canvas.x_bounds),
      "y_bounds" => encode_canvas_bounds(canvas.y_bounds),
      "marker" => Atom.to_string(canvas.marker),
      "shapes" => encode_canvas_shapes(canvas.shapes)
    }
    |> maybe_put("background_color", encode_canvas_background(canvas.background_color))
    |> maybe_put_block(canvas.block, "canvas.block")
  end

  defp encode_widget(%Tabs{} = tabs) do
    %{
      "type" => "tabs",
      "titles" => Enum.map(tabs.titles, &encode_line_like/1),
      "style" => encode_style(tabs.style, "tabs.style"),
      "highlight_style" => encode_style(tabs.highlight_style, "tabs.highlight_style"),
      "padding_left" => elem(tabs.padding, 0),
      "padding_right" => elem(tabs.padding, 1)
    }
    |> maybe_put("selected", tabs.selected)
    |> maybe_put("divider", tabs.divider)
    |> maybe_put_block(tabs.block, "tabs.block")
  end

  defp encode_widget(%Scrollbar{} = scrollbar) do
    %{
      "type" => "scrollbar",
      "orientation" => Atom.to_string(scrollbar.orientation),
      "content_length" => scrollbar.content_length,
      "position" => scrollbar.position,
      "thumb_style" => encode_style(scrollbar.thumb_style, "scrollbar.thumb_style"),
      "track_style" => encode_style(scrollbar.track_style, "scrollbar.track_style")
    }
    |> maybe_put("viewport_content_length", scrollbar.viewport_content_length)
    |> maybe_put("thumb_symbol", scrollbar.thumb_symbol)
    |> maybe_put("track_symbol", scrollbar.track_symbol)
    |> maybe_put("begin_symbol", scrollbar.begin_symbol)
    |> maybe_put("end_symbol", scrollbar.end_symbol)
  end

  defp encode_widget(%Checkbox{} = checkbox) do
    %{
      "type" => "checkbox",
      "label" => checkbox.label,
      "checked" => checkbox.checked,
      "style" => encode_style(checkbox.style, "checkbox.style"),
      "checked_style" => encode_style(checkbox.checked_style, "checkbox.checked_style")
    }
    |> maybe_put("checked_symbol", checkbox.checked_symbol)
    |> maybe_put("unchecked_symbol", checkbox.unchecked_symbol)
    |> maybe_put_block(checkbox.block, "checkbox.block")
  end

  defp encode_widget(%TextInput{state: nil}) do
    raise ArgumentError, "text_input.state is required and must be a reference"
  end

  defp encode_widget(%TextInput{state: state})
       when not is_reference(state) and not is_tuple(state) do
    raise ArgumentError,
          "text_input.state is required and must be a reference, got: #{inspect(state)}"
  end

  defp encode_widget(%TextInput{} = text_input) do
    %{
      "type" => "text_input",
      "state" => text_input.state,
      "style" => encode_style(text_input.style, "text_input.style"),
      "cursor_style" => encode_style(text_input.cursor_style, "text_input.cursor_style"),
      "placeholder_style" =>
        encode_style(text_input.placeholder_style, "text_input.placeholder_style")
    }
    |> maybe_put("placeholder", text_input.placeholder)
    |> maybe_put_block(text_input.block, "text_input.block")
  end

  defp encode_widget(%Markdown{} = markdown) do
    %{
      "type" => "markdown",
      "content" => markdown.content,
      "style" => encode_style(markdown.style, "markdown.style"),
      "wrap" => markdown.wrap,
      "scroll_y" => elem(markdown.scroll, 0),
      "scroll_x" => elem(markdown.scroll, 1)
    }
    |> maybe_put_block(markdown.block, "markdown.block")
  end

  defp encode_widget(%Textarea{state: nil}) do
    raise ArgumentError, "textarea.state is required and must be a reference"
  end

  defp encode_widget(%Textarea{state: state})
       when not is_reference(state) and not is_tuple(state) do
    raise ArgumentError,
          "textarea.state is required and must be a reference, got: #{inspect(state)}"
  end

  defp encode_widget(%Textarea{} = textarea) do
    %{
      "type" => "textarea",
      "state" => textarea.state,
      "style" => encode_style(textarea.style, "textarea.style"),
      "cursor_style" => encode_style(textarea.cursor_style, "textarea.cursor_style"),
      "cursor_line_style" =>
        encode_style(textarea.cursor_line_style, "textarea.cursor_line_style"),
      "placeholder_style" =>
        encode_style(textarea.placeholder_style, "textarea.placeholder_style")
    }
    |> maybe_put("placeholder", textarea.placeholder)
    |> maybe_put_style(
      "line_number_style",
      textarea.line_number_style,
      "textarea.line_number_style"
    )
    |> maybe_put_block(textarea.block, "textarea.block")
  end

  defp encode_widget(%Popup{content: nil}) do
    raise ArgumentError, "Popup :content is required — pass a widget struct"
  end

  defp encode_widget(%Popup{} = popup) do
    %{
      "type" => "popup",
      "content" => encode_widget(popup.content),
      "percent_width" => popup.percent_width,
      "percent_height" => popup.percent_height
    }
    |> maybe_put("fixed_width", popup.fixed_width)
    |> maybe_put("fixed_height", popup.fixed_height)
    |> maybe_put_block(popup.block, "popup.block")
  end

  defp encode_widget(%WidgetList{} = widget_list) do
    items =
      Enum.map(widget_list.items, fn
        {widget, height} when is_integer(height) and height >= 0 ->
          {encode_widget(widget), height}

        other ->
          raise ArgumentError,
                "widget_list.items must contain {widget, non_neg_integer()} tuples, got: #{inspect(other)}"
      end)

    %{
      "type" => "widget_list",
      "items" => items,
      "style" => encode_style(widget_list.style, "widget_list.style"),
      "highlight_style" =>
        encode_style(widget_list.highlight_style, "widget_list.highlight_style"),
      "scroll_offset" => widget_list.scroll_offset
    }
    |> maybe_put("selected", widget_list.selected)
    |> maybe_put_block(widget_list.block, "widget_list.block")
  end

  defp encode_widget(%Throbber{} = throbber) do
    %{
      "type" => "throbber",
      "style" => encode_style(throbber.style, "throbber.style"),
      "throbber_style" => encode_style(throbber.throbber_style, "throbber.throbber_style"),
      "throbber_set" => Atom.to_string(throbber.throbber_set),
      "step" => throbber.step
    }
    |> maybe_put("label", throbber.label)
    |> maybe_put_block(throbber.block, "throbber.block")
  end

  defp encode_widget(widget) do
    raise ArgumentError, "unsupported widget struct: #{inspect(widget)}"
  end

  defp encode_bars(bars) when is_list(bars), do: Enum.map(bars, &encode_bar/1)

  defp encode_bars(other) do
    raise ArgumentError, "bar_chart.data expected a list of %Bar{}, got: #{inspect(other)}"
  end

  defp encode_bar(%Bar{value: value}) when not is_integer(value) or value < 0 do
    raise ArgumentError,
          "bar.value expected a non-negative integer, got: #{inspect(value)}"
  end

  defp encode_bar(%Bar{} = bar) do
    %{"label" => bar.label, "value" => bar.value}
    |> maybe_put_style("style", bar.style, "bar.style")
    |> maybe_put("text_value", bar.text_value)
  end

  defp encode_bar(other) do
    raise ArgumentError, "bar_chart.data expected a list of %Bar{}, got entry: #{inspect(other)}"
  end

  defp encode_sparkline_data(data) when is_list(data),
    do: Enum.map(data, &encode_sparkline_entry/1)

  defp encode_sparkline_data(other) do
    raise ArgumentError,
          "sparkline.data expected a list of non-negative integers or nils, got: #{inspect(other)}"
  end

  defp encode_sparkline_entry(nil), do: nil
  defp encode_sparkline_entry(value) when is_integer(value) and value >= 0, do: value

  defp encode_sparkline_entry(other) do
    raise ArgumentError,
          "sparkline.data entries must be non-negative integers or nil, got: #{inspect(other)}"
  end

  defp encode_bar_set(:nine_levels), do: {"preset", "nine_levels"}
  defp encode_bar_set(:three_levels), do: {"preset", "three_levels"}

  defp encode_bar_set(symbols) when is_list(symbols) and symbols != [] do
    validated =
      Enum.map(symbols, fn
        s when is_binary(s) ->
          s

        other ->
          raise ArgumentError,
                "sparkline.bar_set custom list must contain only strings, got entry: #{inspect(other)}"
      end)

    {"custom", validated}
  end

  defp encode_bar_set(other) do
    raise ArgumentError,
          "sparkline.bar_set expected :nine_levels, :three_levels, or a non-empty list of strings, got: #{inspect(other)}"
  end

  defp validate_sparkline_max!(nil), do: :ok
  defp validate_sparkline_max!(value) when is_integer(value) and value >= 0, do: :ok

  defp validate_sparkline_max!(other) do
    raise ArgumentError,
          "sparkline.max expected a non-negative integer or nil, got: #{inspect(other)}"
  end

  defp validate_calendar_display_date!(%Date{}), do: :ok

  defp validate_calendar_display_date!(other) do
    raise ArgumentError,
          "calendar.display_date expected a %Date{}, got: #{inspect(other)}"
  end

  defp validate_calendar_bool!(_field, value) when is_boolean(value), do: :ok

  defp validate_calendar_bool!(field, other) do
    raise ArgumentError,
          "calendar.#{field} expected a boolean, got: #{inspect(other)}"
  end

  defp encode_calendar_events(nil), do: []

  defp encode_calendar_events(events) when is_map(events) and not is_struct(events) do
    events
    |> Enum.reject(fn {_date, style} -> is_nil(style) end)
    |> Enum.map(&encode_calendar_event/1)
  end

  defp encode_calendar_events(events) when is_list(events) do
    Enum.map(events, &encode_calendar_event/1)
  end

  defp encode_calendar_events(other) do
    raise ArgumentError,
          "calendar.events expected a list of {Date, Style} tuples, a map of Date => Style, or nil, got: #{inspect(other)}"
  end

  defp encode_calendar_event({%Date{year: y, month: m, day: d}, %Style{} = style}) do
    {{y, m, d}, encode_style(style, "calendar.events entry")}
  end

  defp encode_calendar_event(other) do
    raise ArgumentError,
          "calendar.events entries must be {Date, Style} tuples, got: #{inspect(other)}"
  end

  defp validate_canvas_bounds!(_field, {min, max})
       when is_number(min) and is_number(max) and min <= max,
       do: :ok

  defp validate_canvas_bounds!(field, {min, max}) when is_number(min) and is_number(max) do
    raise ArgumentError,
          "canvas.#{field} expected {min, max} with min <= max, got: {#{inspect(min)}, #{inspect(max)}}"
  end

  defp validate_canvas_bounds!(field, other) do
    raise ArgumentError,
          "canvas.#{field} expected {min, max} tuple of numbers, got: #{inspect(other)}"
  end

  defp validate_canvas_marker!(marker)
       when marker in [:braille, :dot, :block, :bar, :half_block],
       do: :ok

  defp validate_canvas_marker!(other) do
    raise ArgumentError,
          "canvas.marker expected one of :braille, :dot, :block, :bar, :half_block, got: #{inspect(other)}"
  end

  defp encode_canvas_bounds({min, max}), do: [min * 1.0, max * 1.0]

  defp encode_canvas_background(nil), do: nil
  defp encode_canvas_background(color), do: encode_color(color)

  defp encode_canvas_shapes(shapes) when is_list(shapes),
    do: Enum.map(shapes, &encode_canvas_shape/1)

  defp encode_canvas_shapes(other) do
    raise ArgumentError,
          "canvas.shapes expected a list of shape structs, got: #{inspect(other)}"
  end

  defp encode_canvas_shape(%Line{x1: nil}), do: raise_canvas_required("Line", "x1")
  defp encode_canvas_shape(%Line{y1: nil}), do: raise_canvas_required("Line", "y1")
  defp encode_canvas_shape(%Line{x2: nil}), do: raise_canvas_required("Line", "x2")
  defp encode_canvas_shape(%Line{y2: nil}), do: raise_canvas_required("Line", "y2")
  defp encode_canvas_shape(%Line{color: nil}), do: raise_canvas_required("Line", "color")

  defp encode_canvas_shape(%Line{} = line) do
    validate_canvas_number!("Line", "x1", line.x1)
    validate_canvas_number!("Line", "y1", line.y1)
    validate_canvas_number!("Line", "x2", line.x2)
    validate_canvas_number!("Line", "y2", line.y2)

    %{
      "shape" => "line",
      "x1" => line.x1 * 1.0,
      "y1" => line.y1 * 1.0,
      "x2" => line.x2 * 1.0,
      "y2" => line.y2 * 1.0,
      "color" => encode_color(line.color)
    }
  end

  defp encode_canvas_shape(%Rectangle{x: nil}), do: raise_canvas_required("Rectangle", "x")
  defp encode_canvas_shape(%Rectangle{y: nil}), do: raise_canvas_required("Rectangle", "y")

  defp encode_canvas_shape(%Rectangle{width: nil}),
    do: raise_canvas_required("Rectangle", "width")

  defp encode_canvas_shape(%Rectangle{height: nil}),
    do: raise_canvas_required("Rectangle", "height")

  defp encode_canvas_shape(%Rectangle{color: nil}),
    do: raise_canvas_required("Rectangle", "color")

  defp encode_canvas_shape(%Rectangle{} = rect) do
    validate_canvas_number!("Rectangle", "x", rect.x)
    validate_canvas_number!("Rectangle", "y", rect.y)
    validate_canvas_non_negative!("Rectangle", "width", rect.width)
    validate_canvas_non_negative!("Rectangle", "height", rect.height)

    %{
      "shape" => "rectangle",
      "x" => rect.x * 1.0,
      "y" => rect.y * 1.0,
      "width" => rect.width * 1.0,
      "height" => rect.height * 1.0,
      "color" => encode_color(rect.color)
    }
  end

  defp encode_canvas_shape(%Circle{x: nil}), do: raise_canvas_required("Circle", "x")
  defp encode_canvas_shape(%Circle{y: nil}), do: raise_canvas_required("Circle", "y")
  defp encode_canvas_shape(%Circle{radius: nil}), do: raise_canvas_required("Circle", "radius")
  defp encode_canvas_shape(%Circle{color: nil}), do: raise_canvas_required("Circle", "color")

  defp encode_canvas_shape(%Circle{} = circle) do
    validate_canvas_number!("Circle", "x", circle.x)
    validate_canvas_number!("Circle", "y", circle.y)
    validate_canvas_non_negative!("Circle", "radius", circle.radius)

    %{
      "shape" => "circle",
      "x" => circle.x * 1.0,
      "y" => circle.y * 1.0,
      "radius" => circle.radius * 1.0,
      "color" => encode_color(circle.color)
    }
  end

  defp encode_canvas_shape(%Points{color: nil}), do: raise_canvas_required("Points", "color")

  defp encode_canvas_shape(%Points{} = points) do
    coords = encode_canvas_coords(points.coords)

    %{
      "shape" => "points",
      "coords" => coords,
      "color" => encode_color(points.color)
    }
  end

  defp encode_canvas_shape(other) do
    raise ArgumentError,
          "canvas.shapes entry must be a Line, Rectangle, Circle, or Points struct, got: #{inspect(other)}"
  end

  defp encode_canvas_coords(coords) when is_list(coords),
    do: Enum.map(coords, &encode_canvas_coord/1)

  defp encode_canvas_coords(other) do
    raise ArgumentError,
          "canvas.shapes Points.coords expected a list of {x, y} tuples, got: #{inspect(other)}"
  end

  defp encode_canvas_coord({x, y}) when is_number(x) and is_number(y), do: [x * 1.0, y * 1.0]

  defp encode_canvas_coord(other) do
    raise ArgumentError,
          "canvas.shapes Points.coords entries must be {number, number} tuples, got: #{inspect(other)}"
  end

  defp validate_canvas_number!(_shape, _field, value) when is_number(value), do: :ok

  defp validate_canvas_number!(shape, field, other) do
    raise ArgumentError,
          "canvas.shapes #{shape}.#{field} expected a number, got: #{inspect(other)}"
  end

  defp validate_canvas_non_negative!(_shape, _field, value) when is_number(value) and value >= 0,
    do: :ok

  defp validate_canvas_non_negative!(shape, field, value) when is_number(value) do
    raise ArgumentError,
          "canvas.shapes #{shape}.#{field} must be non-negative, got: #{inspect(value)}"
  end

  defp validate_canvas_non_negative!(shape, field, other) do
    raise ArgumentError,
          "canvas.shapes #{shape}.#{field} expected a non-negative number, got: #{inspect(other)}"
  end

  defp raise_canvas_required(shape, field) do
    raise ArgumentError, "canvas.shapes #{shape}.#{field} is required"
  end

  defp encode_line_like(value), do: value |> Coerce.coerce_line!() |> Encode.to_wire_line!()

  defp encode_optional_line(nil), do: nil
  defp encode_optional_line(value), do: encode_line_like(value)

  defp encode_table_header(nil), do: nil
  defp encode_table_header(cells), do: Enum.map(cells, &encode_line_like/1)

  defp encode_block(%Block{} = block, context) do
    %{
      "borders" => Enum.map(block.borders, &Atom.to_string/1),
      "border_style" => encode_style(block.border_style, "#{context}.border_style"),
      "border_type" => Atom.to_string(block.border_type),
      "style" => encode_style(block.style, "#{context}.style"),
      "padding_left" => elem(block.padding, 0),
      "padding_right" => elem(block.padding, 1),
      "padding_top" => elem(block.padding, 2),
      "padding_bottom" => elem(block.padding, 3)
    }
    |> maybe_put("title", encode_optional_line(block.title))
  end

  defp encode_block(other, context) do
    raise ArgumentError, "#{context} expected %ExRatatui.Widgets.Block{}, got: #{inspect(other)}"
  end

  defp encode_constraint({:percentage, value}, _context),
    do: %{"type" => "percentage", "value" => value}

  defp encode_constraint({:length, value}, _context), do: %{"type" => "length", "value" => value}
  defp encode_constraint({:min, value}, _context), do: %{"type" => "min", "value" => value}
  defp encode_constraint({:max, value}, _context), do: %{"type" => "max", "value" => value}

  defp encode_constraint({:ratio, numerator, denominator}, _context) do
    %{"type" => "ratio", "num" => numerator, "den" => denominator}
  end

  defp encode_constraint(other, _context) do
    raise ArgumentError, "invalid layout constraint: #{inspect(other)}"
  end

  defp encode_style(%Style{} = style, _context) do
    %{"modifiers" => Enum.map(style.modifiers, &Atom.to_string/1)}
    |> maybe_put("fg", encode_color(style.fg))
    |> maybe_put("bg", encode_color(style.bg))
  end

  defp encode_style(other, context) do
    raise ArgumentError, "#{context} expected %ExRatatui.Style{}, got: #{inspect(other)}"
  end

  defp encode_color(nil), do: nil
  defp encode_color(color) when is_atom(color), do: Atom.to_string(color)
  defp encode_color({:rgb, r, g, b}), do: %{"type" => "rgb", "r" => r, "g" => g, "b" => b}
  defp encode_color({:indexed, index}), do: %{"type" => "indexed", "value" => index}

  defp encode_color(other) do
    raise ArgumentError, "invalid color value: #{inspect(other)}"
  end

  defp encode_rect(%Rect{} = rect) do
    %{
      "x" => rect.x,
      "y" => rect.y,
      "width" => rect.width,
      "height" => rect.height
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_style(map, _key, nil, _context), do: map

  defp maybe_put_style(map, key, style, context) do
    Map.put(map, key, encode_style(style, context))
  end

  defp maybe_put_block(map, nil, _context), do: map

  defp maybe_put_block(map, block, context) do
    Map.put(map, "block", encode_block(block, context))
  end
end
