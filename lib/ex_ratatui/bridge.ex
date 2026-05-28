defmodule ExRatatui.Bridge do
  @moduledoc false

  # Internal bridge between Elixir widget structs and the native render
  # command format. Owns validation and encoding for render commands so
  # both ExRatatui.draw/2 and ExRatatui.Session.draw/2 cross the NIF
  # boundary through the same path.

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.{Coerce, Encode}
  alias ExRatatui.Widget.Expander

  alias ExRatatui.Widgets.{
    Bar,
    BarChart,
    BarGroup,
    BigText,
    Block,
    Calendar,
    Canvas,
    Chart,
    Checkbox,
    Clear,
    CodeBlock,
    Gauge,
    Image,
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

  alias ExRatatui.Widgets.Canvas.{Circle, Label, Line, Points, Rectangle}
  alias ExRatatui.Widgets.Canvas.Map, as: CanvasMap
  alias ExRatatui.Widgets.Chart.{Axis, Dataset}

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
    selected = validate_selected!(list.selected, length(list.items), "list.selected")
    validate_list_direction!(list.direction)
    validate_scroll_padding!(list.scroll_padding)
    validate_boolean!(list.repeat_highlight_symbol, "list.repeat_highlight_symbol")

    %{
      "type" => "list",
      "items" =>
        Enum.map(list.items, fn item ->
          item |> Coerce.coerce_text!() |> Encode.to_wire_text!()
        end),
      "style" => encode_style(list.style, "list.style"),
      "highlight_style" => encode_style(list.highlight_style, "list.highlight_style"),
      "direction" => Atom.to_string(list.direction),
      "scroll_padding" => list.scroll_padding,
      "repeat_highlight_symbol" => list.repeat_highlight_symbol
    }
    |> maybe_put("highlight_symbol", list.highlight_symbol)
    |> maybe_put("selected", selected)
    |> maybe_put_block(list.block, "list.block")
  end

  defp encode_widget(%Table{} = table) do
    selected = validate_selected!(table.selected, length(table.rows), "table.selected")

    selected_column =
      validate_selected!(
        table.selected_column,
        table_column_count(table),
        "table.selected_column"
      )

    validate_highlight_spacing!(table.highlight_spacing)

    %{
      "type" => "table",
      "rows" =>
        Enum.map(table.rows, fn row ->
          Enum.map(row, &encode_line_like/1)
        end),
      "widths" => Enum.map(table.widths, &encode_constraint(&1, "table.widths")),
      "style" => encode_style(table.style, "table.style"),
      "highlight_style" => encode_style(table.highlight_style, "table.highlight_style"),
      "highlight_spacing" => Atom.to_string(table.highlight_spacing),
      "column_spacing" => table.column_spacing
    }
    |> maybe_put("header", encode_table_header(table.header))
    |> maybe_put("footer", encode_table_header(table.footer))
    |> maybe_put_style(
      "column_highlight_style",
      table.column_highlight_style,
      "table.column_highlight_style"
    )
    |> maybe_put_style(
      "cell_highlight_style",
      table.cell_highlight_style,
      "table.cell_highlight_style"
    )
    |> maybe_put_style("header_style", table.header_style, "table.header_style")
    |> maybe_put_style("footer_style", table.footer_style, "table.footer_style")
    |> maybe_put("highlight_symbol", table.highlight_symbol)
    |> maybe_put("selected", selected)
    |> maybe_put("selected_column", selected_column)
    |> maybe_put_block(table.block, "table.block")
  end

  defp encode_widget(%Clear{}) do
    %{"type" => "clear"}
  end

  defp encode_widget(%Gauge{} = gauge) do
    %{
      "type" => "gauge",
      "ratio" => encode_ratio(gauge.ratio, "gauge.ratio"),
      "style" => encode_style(gauge.style, "gauge.style"),
      "gauge_style" => encode_style(gauge.gauge_style, "gauge.gauge_style")
    }
    |> maybe_put("label", gauge.label)
    |> maybe_put_block(gauge.block, "gauge.block")
  end

  defp encode_widget(%LineGauge{} = line_gauge) do
    %{
      "type" => "line_gauge",
      "ratio" => encode_ratio(line_gauge.ratio, "line_gauge.ratio"),
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

    validate_bar_chart_group_gap!(chart.group_gap)

    groups = encode_bar_groups(chart.data, chart.groups)

    %{
      "type" => "bar_chart",
      "groups" => groups,
      "bar_width" => chart.bar_width,
      "bar_gap" => chart.bar_gap,
      "group_gap" => chart.group_gap,
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

  defp encode_widget(%Chart{x_axis: nil}) do
    raise ArgumentError, "chart.x_axis is required and must be a %ExRatatui.Widgets.Chart.Axis{}"
  end

  defp encode_widget(%Chart{y_axis: nil}) do
    raise ArgumentError, "chart.y_axis is required and must be a %ExRatatui.Widgets.Chart.Axis{}"
  end

  defp encode_widget(%Chart{} = chart) do
    validate_chart_legend_position!(chart.legend_position)

    base = %{
      "type" => "chart",
      "datasets" => encode_chart_datasets(chart.datasets),
      "x_axis" => encode_chart_axis(chart.x_axis, "chart.x_axis"),
      "y_axis" => encode_chart_axis(chart.y_axis, "chart.y_axis")
    }

    base
    |> encode_chart_legend(chart.legend_position)
    |> maybe_put(
      "hidden_legend_constraints",
      encode_chart_hidden_legend_constraints(chart.hidden_legend_constraints)
    )
    |> maybe_put_block(chart.block, "chart.block")
  end

  defp encode_widget(%Tabs{} = tabs) do
    selected = validate_selected!(tabs.selected, length(tabs.titles), "tabs.selected")

    %{
      "type" => "tabs",
      "titles" => Enum.map(tabs.titles, &encode_line_like/1),
      "style" => encode_style(tabs.style, "tabs.style"),
      "highlight_style" => encode_style(tabs.highlight_style, "tabs.highlight_style"),
      "padding_left" => elem(tabs.padding, 0),
      "padding_right" => elem(tabs.padding, 1)
    }
    |> maybe_put("selected", selected)
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

  defp encode_widget(%BigText{} = big_text) do
    %{
      "type" => "big_text",
      "lines" => Enum.map(big_text.lines, &encode_line_like/1),
      "pixel_size" => Atom.to_string(big_text.pixel_size),
      "alignment" => Atom.to_string(big_text.alignment),
      "style" => encode_style(big_text.style, "big_text.style")
    }
    |> maybe_put_block(big_text.block, "big_text.block")
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

  defp encode_widget(%Image{state: nil}) do
    raise ArgumentError, "image.state is required and must be a reference"
  end

  defp encode_widget(%Image{state: state}) when not is_reference(state) and not is_tuple(state) do
    raise ArgumentError,
          "image.state must be a reference returned by ExRatatui.Image.new/2 " <>
            "(or a snapshot tuple inserted by the distributed transport), got: #{inspect(state)}"
  end

  defp encode_widget(%Image{} = image) do
    %{
      "type" => "image",
      "state" => image.state
    }
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

  defp encode_widget(%CodeBlock{} = cb) do
    %{
      "type" => "code_block",
      "content" => cb.content,
      "theme" => ExRatatui.CodeBlock.resolve_theme(cb.theme),
      "line_numbers" => cb.line_numbers,
      "starting_line" => validate_starting_line(cb.starting_line),
      "highlight_lines" => normalize_highlight_lines(cb.highlight_lines),
      "style" => encode_style(cb.style, "code_block.style"),
      "wrap" => cb.wrap,
      "scroll_y" => elem(cb.scroll, 0),
      "scroll_x" => elem(cb.scroll, 1)
    }
    |> maybe_put("language", normalize_language(cb.language))
    |> maybe_put_block(cb.block, "code_block.block")
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

    selected =
      validate_selected!(widget_list.selected, length(items), "widget_list.selected")

    %{
      "type" => "widget_list",
      "items" => items,
      "style" => encode_style(widget_list.style, "widget_list.style"),
      "highlight_style" =>
        encode_style(widget_list.highlight_style, "widget_list.highlight_style"),
      "scroll_offset" => widget_list.scroll_offset
    }
    |> maybe_put("selected", selected)
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

  # Column count for Table's :selected_column validation: the widest
  # of widths, header, and first data row. Matches ratatui's internal
  # max() over the same three sources.
  defp table_column_count(%Table{widths: widths, header: header, rows: rows}) do
    Enum.max([length(widths), header_length(header), row_length(rows)])
  end

  defp header_length(nil), do: 0
  defp header_length(header), do: length(header)

  defp row_length([]), do: 0
  defp row_length([first | _]), do: length(first)

  defp encode_ratio(value, _context) when is_number(value) and value >= 0.0 and value <= 1.0,
    do: value * 1.0

  defp encode_ratio(value, context) do
    raise ArgumentError,
          "#{context} expected a number in 0.0..1.0, got: #{inspect(value)}"
  end

  defp validate_selected!(nil, _count, _context), do: nil

  defp validate_selected!(index, count, _context)
       when is_integer(index) and index >= 0 and index < count,
       do: index

  defp validate_selected!(other, 0, context) do
    raise ArgumentError,
          "#{context} expected nil (collection is empty), got: #{inspect(other)}"
  end

  defp validate_selected!(other, count, context) do
    raise ArgumentError,
          "#{context} expected nil or an integer in 0..#{count - 1}, got: #{inspect(other)}"
  end

  defp validate_list_direction!(value) when value in [:top_to_bottom, :bottom_to_top], do: :ok

  defp validate_list_direction!(other) do
    raise ArgumentError,
          "list.direction expected :top_to_bottom or :bottom_to_top, got: #{inspect(other)}"
  end

  defp validate_scroll_padding!(value) when is_integer(value) and value >= 0, do: :ok

  defp validate_scroll_padding!(other) do
    raise ArgumentError,
          "list.scroll_padding expected a non-negative integer, got: #{inspect(other)}"
  end

  defp validate_boolean!(value, _context) when is_boolean(value), do: :ok

  defp validate_boolean!(other, context) do
    raise ArgumentError, "#{context} expected a boolean, got: #{inspect(other)}"
  end

  defp validate_highlight_spacing!(value)
       when value in [:always, :when_selected, :never],
       do: :ok

  defp validate_highlight_spacing!(other) do
    raise ArgumentError,
          "table.highlight_spacing expected :always, :when_selected, or :never, got: #{inspect(other)}"
  end

  defp encode_bar_groups(_data, groups) when not is_list(groups) do
    raise ArgumentError,
          "bar_chart.groups expected a list of %BarGroup{}, got: #{inspect(groups)}"
  end

  defp encode_bar_groups(_data, [_ | _] = groups) do
    Enum.map(groups, &encode_bar_group/1)
  end

  defp encode_bar_groups(data, []), do: [%{"bars" => encode_bars(data)}]

  defp encode_bar_group(%BarGroup{bars: bars} = group) when is_list(bars) do
    %{"bars" => encode_bars(bars)}
    |> maybe_put("label", encode_bar_group_label(group.label))
  end

  defp encode_bar_group(other) do
    raise ArgumentError,
          "bar_chart.groups expected entries to be %BarGroup{}, got: #{inspect(other)}"
  end

  defp encode_bar_group_label(nil), do: nil
  defp encode_bar_group_label(binary) when is_binary(binary), do: binary

  defp encode_bar_group_label(other) do
    raise ArgumentError,
          "bar_chart.groups label expected a string or nil, got: #{inspect(other)}"
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

  defp validate_bar_chart_group_gap!(value) when is_integer(value) and value >= 0, do: :ok

  defp validate_bar_chart_group_gap!(other) do
    raise ArgumentError,
          "bar_chart.group_gap expected a non-negative integer, got: #{inspect(other)}"
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

  defp encode_canvas_shape(%CanvasMap{color: nil}), do: raise_canvas_required("Map", "color")

  defp encode_canvas_shape(%CanvasMap{resolution: resolution})
       when resolution not in [:low, :high] do
    raise ArgumentError,
          "canvas.shapes Map.resolution expected :low or :high, got: #{inspect(resolution)}"
  end

  defp encode_canvas_shape(%CanvasMap{} = map) do
    %{
      "shape" => "map",
      "resolution" => Atom.to_string(map.resolution),
      "color" => encode_color(map.color)
    }
  end

  defp encode_canvas_shape(%Label{x: nil}), do: raise_canvas_required("Label", "x")
  defp encode_canvas_shape(%Label{y: nil}), do: raise_canvas_required("Label", "y")
  defp encode_canvas_shape(%Label{text: nil}), do: raise_canvas_required("Label", "text")
  defp encode_canvas_shape(%Label{color: nil}), do: raise_canvas_required("Label", "color")

  defp encode_canvas_shape(%Label{text: text}) when not is_binary(text) do
    raise ArgumentError,
          "canvas.shapes Label.text expected a string, got: #{inspect(text)}"
  end

  defp encode_canvas_shape(%Label{} = label) do
    validate_canvas_number!("Label", "x", label.x)
    validate_canvas_number!("Label", "y", label.y)

    %{
      "shape" => "label",
      "x" => label.x * 1.0,
      "y" => label.y * 1.0,
      "text" => label.text,
      "color" => encode_color(label.color)
    }
  end

  defp encode_canvas_shape(other) do
    raise ArgumentError,
          "canvas.shapes entry must be a Line, Rectangle, Circle, Points, Map, or Label struct, got: #{inspect(other)}"
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

  defp encode_chart_datasets(datasets) when is_list(datasets),
    do: Enum.map(datasets, &encode_chart_dataset/1)

  defp encode_chart_datasets(other) do
    raise ArgumentError,
          "chart.datasets expected a list of %ExRatatui.Widgets.Chart.Dataset{}, got: #{inspect(other)}"
  end

  defp encode_chart_dataset(%Dataset{} = dataset) do
    validate_chart_dataset_name!(dataset.name)
    validate_chart_dataset_marker!(dataset.marker)
    validate_chart_dataset_graph_type!(dataset.graph_type)

    %{
      "data" => encode_chart_dataset_data(dataset.data),
      "marker" => Atom.to_string(dataset.marker),
      "graph_type" => Atom.to_string(dataset.graph_type),
      "style" => encode_style(dataset.style, "chart.datasets style")
    }
    |> maybe_put("name", dataset.name)
  end

  defp encode_chart_dataset(other) do
    raise ArgumentError,
          "chart.datasets expected entries to be %ExRatatui.Widgets.Chart.Dataset{}, got: #{inspect(other)}"
  end

  defp encode_chart_dataset_data(data) when is_list(data),
    do: Enum.map(data, &encode_chart_dataset_point/1)

  defp encode_chart_dataset_data(other) do
    raise ArgumentError,
          "chart.datasets data expected a list of {x, y} numeric tuples, got: #{inspect(other)}"
  end

  defp encode_chart_dataset_point({x, y}) when is_number(x) and is_number(y) do
    validate_chart_finite!(x)
    validate_chart_finite!(y)
    [x * 1.0, y * 1.0]
  end

  defp encode_chart_dataset_point(other) do
    raise ArgumentError,
          "chart.datasets data entries must be {number, number} tuples, got: #{inspect(other)}"
  end

  defp validate_chart_finite!(value) when is_integer(value) or is_float(value), do: :ok

  defp validate_chart_dataset_name!(nil), do: :ok
  defp validate_chart_dataset_name!(name) when is_binary(name), do: :ok

  defp validate_chart_dataset_name!(other) do
    raise ArgumentError,
          "chart.datasets name expected a string or nil, got: #{inspect(other)}"
  end

  defp validate_chart_dataset_marker!(marker)
       when marker in [:braille, :dot, :block, :bar, :half_block],
       do: :ok

  defp validate_chart_dataset_marker!(other) do
    raise ArgumentError,
          "chart.datasets marker expected one of :braille, :dot, :block, :bar, :half_block, got: #{inspect(other)}"
  end

  defp validate_chart_dataset_graph_type!(graph_type)
       when graph_type in [:line, :scatter, :bar],
       do: :ok

  defp validate_chart_dataset_graph_type!(other) do
    raise ArgumentError,
          "chart.datasets graph_type expected one of :line, :scatter, :bar, got: #{inspect(other)}"
  end

  defp encode_chart_axis(%Axis{} = axis, context) do
    validate_chart_axis_bounds!(axis.bounds, context)
    validate_chart_axis_alignment!(axis.labels_alignment, context)

    %{
      "bounds" => encode_chart_axis_bounds(axis.bounds),
      "labels" => encode_chart_axis_labels(axis.labels, context),
      "style" => encode_style(axis.style, "#{context} style"),
      "labels_alignment" => Atom.to_string(axis.labels_alignment)
    }
    |> maybe_put("title", encode_optional_line(axis.title))
  end

  defp encode_chart_axis(other, context) do
    raise ArgumentError,
          "#{context} expected %ExRatatui.Widgets.Chart.Axis{}, got: #{inspect(other)}"
  end

  defp validate_chart_axis_bounds!({min, max}, _context)
       when is_number(min) and is_number(max) do
    validate_chart_finite!(min)
    validate_chart_finite!(max)
    :ok
  end

  defp validate_chart_axis_bounds!(other, context) do
    raise ArgumentError,
          "#{context} bounds expected {min, max} of finite numbers, got: #{inspect(other)}"
  end

  defp validate_chart_axis_alignment!(alignment, _context)
       when alignment in [:left, :center, :right],
       do: :ok

  defp validate_chart_axis_alignment!(other, context) do
    raise ArgumentError,
          "#{context} labels_alignment expected one of :left, :center, :right, got: #{inspect(other)}"
  end

  defp encode_chart_axis_bounds({min, max}), do: [min * 1.0, max * 1.0]

  defp encode_chart_axis_labels(labels, _context) when is_list(labels),
    do: Enum.map(labels, &encode_line_like/1)

  defp encode_chart_axis_labels(other, context) do
    raise ArgumentError,
          "#{context} labels expected a list, got: #{inspect(other)}"
  end

  defp validate_chart_legend_position!(position)
       when position in [
              nil,
              :top,
              :top_left,
              :top_right,
              :bottom,
              :bottom_left,
              :bottom_right,
              :left,
              :right
            ],
       do: :ok

  defp validate_chart_legend_position!(other) do
    raise ArgumentError,
          "chart.legend_position expected nil or one of :top, :top_left, :top_right, :bottom, :bottom_left, :bottom_right, :left, :right, got: #{inspect(other)}"
  end

  defp encode_chart_legend(map, nil), do: Map.put(map, "hide_legend", true)

  defp encode_chart_legend(map, position),
    do: Map.put(map, "legend_position", Atom.to_string(position))

  defp encode_chart_hidden_legend_constraints(nil), do: nil

  defp encode_chart_hidden_legend_constraints({h, v}) do
    [
      encode_constraint(h, "chart.hidden_legend_constraints"),
      encode_constraint(v, "chart.hidden_legend_constraints")
    ]
  end

  defp encode_chart_hidden_legend_constraints(other) do
    raise ArgumentError,
          "chart.hidden_legend_constraints expected {Constraint, Constraint} or nil, got: #{inspect(other)}"
  end

  defp encode_line_like(value), do: value |> Coerce.coerce_line!() |> Encode.to_wire_line!()

  defp encode_optional_line(nil), do: nil
  defp encode_optional_line(value), do: encode_line_like(value)

  defp encode_table_header(nil), do: nil
  defp encode_table_header(cells), do: Enum.map(cells, &encode_line_like/1)

  defp encode_block(%Block{} = block, context) do
    validate_title_position!(block.title_position, "#{context}.title_position")
    validate_title_alignment!(block.title_alignment, "#{context}.title_alignment")

    %{
      "borders" => Enum.map(block.borders, &Atom.to_string/1),
      "border_style" => encode_style(block.border_style, "#{context}.border_style"),
      "border_type" => Atom.to_string(block.border_type),
      "style" => encode_style(block.style, "#{context}.style"),
      "padding_left" => elem(block.padding, 0),
      "padding_right" => elem(block.padding, 1),
      "padding_top" => elem(block.padding, 2),
      "padding_bottom" => elem(block.padding, 3),
      "title_position" => Atom.to_string(block.title_position),
      "title_alignment" => Atom.to_string(block.title_alignment),
      "titles" => Enum.map(block.titles, &encode_block_title(&1, "#{context}.titles"))
    }
    |> maybe_put("title", encode_optional_line(block.title))
    |> maybe_put_style("title_style", block.title_style, "#{context}.title_style")
  end

  defp encode_block(other, context) do
    raise ArgumentError, "#{context} expected %ExRatatui.Widgets.Block{}, got: #{inspect(other)}"
  end

  defp encode_block_title(%Block.Title{content: nil}, context) do
    raise ArgumentError, "#{context} entry has nil :content"
  end

  defp encode_block_title(%Block.Title{} = title, context) do
    validate_title_position!(title.position, "#{context}.position", allow_nil: true)
    validate_title_alignment!(title.alignment, "#{context}.alignment", allow_nil: true)

    %{"content" => encode_line_like(title.content)}
    |> maybe_put("position", title.position && Atom.to_string(title.position))
    |> maybe_put("alignment", title.alignment && Atom.to_string(title.alignment))
    |> maybe_put_style("style", title.style, "#{context}.style")
  end

  defp encode_block_title(other, context) do
    %{"content" => encode_line_like(other), "position" => nil, "alignment" => nil}
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  rescue
    e in ArgumentError ->
      reraise ArgumentError,
              "#{context} entry expected %Block.Title{} or a line-like value, got: #{inspect(other)} (#{Exception.message(e)})",
              __STACKTRACE__
  end

  defp validate_title_position!(value, context, opts \\ [])

  defp validate_title_position!(nil, _context, opts) do
    if Keyword.get(opts, :allow_nil, false), do: :ok, else: raise_title_position_error!(nil, "")
  end

  defp validate_title_position!(value, _context, _opts) when value in [:top, :bottom], do: :ok

  defp validate_title_position!(value, context, _opts) do
    raise_title_position_error!(value, context)
  end

  defp raise_title_position_error!(value, context) do
    raise ArgumentError,
          "#{context} expected :top or :bottom, got: #{inspect(value)}"
  end

  defp validate_title_alignment!(value, context, opts \\ [])

  defp validate_title_alignment!(nil, _context, opts) do
    if Keyword.get(opts, :allow_nil, false),
      do: :ok,
      else: raise_title_alignment_error!(nil, "")
  end

  defp validate_title_alignment!(value, _context, _opts)
       when value in [:left, :center, :right],
       do: :ok

  defp validate_title_alignment!(value, context, _opts) do
    raise_title_alignment_error!(value, context)
  end

  defp raise_title_alignment_error!(value, context) do
    raise ArgumentError,
          "#{context} expected :left, :center, or :right, got: #{inspect(value)}"
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
    |> maybe_put("underline_color", encode_color(style.underline_color))
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

  defp normalize_language(nil), do: nil
  defp normalize_language(lang) when is_binary(lang), do: lang
  defp normalize_language(lang) when is_atom(lang), do: Atom.to_string(lang)

  defp normalize_language(other) do
    raise ArgumentError,
          "code_block.language must be a string, atom, or nil, got: #{inspect(other)}"
  end

  defp validate_starting_line(n) when is_integer(n) and n > 0, do: n

  defp validate_starting_line(other) do
    raise ArgumentError,
          "code_block.starting_line must be a positive integer, got: #{inspect(other)}"
  end

  defp normalize_highlight_lines(entries) when is_list(entries) do
    entries
    |> Enum.flat_map(fn
      n when is_integer(n) and n > 0 -> [n]
      %Range{first: a, last: b, step: 1} when a > 0 and b >= a -> Enum.to_list(a..b)
      other -> raise ArgumentError, "invalid highlight_lines entry: #{inspect(other)}"
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_highlight_lines(other) do
    raise ArgumentError,
          "code_block.highlight_lines must be a list, got: #{inspect(other)}"
  end
end
