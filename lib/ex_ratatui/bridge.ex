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
    Block,
    Checkbox,
    Clear,
    Gauge,
    LineGauge,
    List,
    Markdown,
    Paragraph,
    Popup,
    Scrollbar,
    Table,
    Tabs,
    Textarea,
    TextInput,
    Throbber,
    WidgetList
  }

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
