defmodule ExRatatui.Property.WidgetRenderPropertyTest do
  @moduledoc """
  Per-widget property invariants. For every stateless widget type the
  library ships, prove that:

    1. `ExRatatui.Bridge.encode_commands!/1` accepts arbitrary valid
       inputs without raising. Catches encoder regressions on the
       happy path that example-based tests can miss (e.g. a new field
       silently dropped from the encoder).
    2. `ExRatatui.CellSession.draw/2` followed by
       `ExRatatui.CellSession.take_cells/1` produces a snapshot with
       exactly `width * height` cells. Catches render-time panics from
       the Rust side under arbitrary input combinations.

  Both invariants share one generator per widget so the same random
  trees stress both paths. Widgets that require resource state
  (`TextInput`, `Textarea`, `Image`), or recursive composition
  (`Popup`, `WidgetList`, `Canvas`, `Chart`, `CodeBlock`), are out of
  scope here and tested in their own files / a follow-up property pass.

  Constraints kept tight on purpose:

    * rects are capped at 40x20 (predictable runtime, still wide
      enough to exercise wrap / scroll logic),
    * collections cap at 8 items (validates the selected-index
      contract added in the numeric-validation pass without
      generating pathological trees),
    * text is short printable ASCII (the text-coercion path has its
      own dedicated property suite).
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExRatatui.Bridge
  alias ExRatatui.CellSession
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style

  alias ExRatatui.Widgets.{
    Bar,
    BarChart,
    BarGroup,
    Block,
    Calendar,
    Checkbox,
    Clear,
    Gauge,
    LineGauge,
    List,
    Markdown,
    Paragraph,
    Scrollbar,
    Sparkline,
    Table,
    Tabs,
    Throbber
  }

  @named_colors ~w(black red green yellow blue magenta cyan gray white reset)a
  @modifiers ~w(bold dim italic underlined crossed_out reversed)a

  @throbber_sets ~w(
    braille dots ascii vertical_block horizontal_block arrow clock
    box_drawing quadrant_block white_square white_circle black_circle
  )a

  @scrollbar_orientations ~w(
    vertical_right vertical_left horizontal_bottom horizontal_top
  )a

  @big_text_sizes ~w(
    full half_height half_width quadrant third_height sextant
    quarter_height octant
  )a

  # ----------------------------------------------------------------------
  # Shared generators
  # ----------------------------------------------------------------------

  defp color_gen do
    one_of([
      constant(nil),
      member_of(@named_colors)
    ])
  end

  defp style_gen do
    gen all(
          fg <- color_gen(),
          bg <- color_gen(),
          modifiers <- list_of(member_of(@modifiers), max_length: 3)
        ) do
      %Style{fg: fg, bg: bg, modifiers: Enum.uniq(modifiers)}
    end
  end

  defp short_text_gen, do: string(:alphanumeric, min_length: 1, max_length: 8)

  defp short_items_gen do
    list_of(short_text_gen(), min_length: 1, max_length: 8)
  end

  defp selected_for_gen(items) do
    case length(items) do
      0 -> constant(nil)
      n -> one_of([constant(nil), integer(0..(n - 1))])
    end
  end

  defp rect_gen do
    gen all(
          x <- integer(0..50),
          y <- integer(0..20),
          width <- integer(1..40),
          height <- integer(1..20)
        ) do
      %Rect{x: x, y: y, width: width, height: height}
    end
  end

  # ----------------------------------------------------------------------
  # Per-widget generators
  # ----------------------------------------------------------------------

  defp block_gen do
    gen all(
          title <- one_of([constant(nil), short_text_gen()]),
          borders <-
            list_of(member_of([:top, :right, :bottom, :left]), max_length: 4),
          border_type <- member_of([:plain, :rounded, :double, :thick]),
          style <- style_gen()
        ) do
      %Block{
        title: title,
        borders: Enum.uniq(borders),
        border_type: border_type,
        style: style
      }
    end
  end

  defp optional_block_gen, do: one_of([constant(nil), block_gen()])

  defp paragraph_gen do
    gen all(
          text <- string(:printable, max_length: 40),
          style <- style_gen(),
          block <- optional_block_gen()
        ) do
      %Paragraph{text: text, style: style, block: block}
    end
  end

  defp clear_gen, do: constant(%Clear{})

  defp list_gen do
    gen all(
          items <- short_items_gen(),
          selected <- selected_for_gen(items),
          highlight_symbol <- one_of([constant(nil), short_text_gen()]),
          block <- optional_block_gen()
        ) do
      %List{items: items, selected: selected, highlight_symbol: highlight_symbol, block: block}
    end
  end

  defp table_gen do
    gen all(
          col_count <- integer(1..3),
          row_count <- integer(0..6),
          cell <- short_text_gen(),
          block <- optional_block_gen()
        ) do
      rows = for _ <- 1..row_count//1, do: for(_ <- 1..col_count, do: cell)
      widths = for _ <- 1..col_count, do: {:percentage, div(100, col_count)}

      %Table{
        rows: rows,
        widths: widths,
        selected: if(row_count == 0, do: nil, else: 0),
        block: block
      }
    end
  end

  defp ratio_gen do
    one_of([
      constant(0.0),
      constant(1.0),
      float(min: 0.0, max: 1.0)
    ])
  end

  defp gauge_gen do
    gen all(
          ratio <- ratio_gen(),
          label <- one_of([constant(nil), short_text_gen()]),
          block <- optional_block_gen()
        ) do
      %Gauge{ratio: ratio, label: label, block: block}
    end
  end

  defp line_gauge_gen do
    gen all(
          ratio <- ratio_gen(),
          label <- one_of([constant(nil), short_text_gen()]),
          block <- optional_block_gen()
        ) do
      %LineGauge{ratio: ratio, label: label, block: block}
    end
  end

  defp tabs_gen do
    gen all(
          titles <- short_items_gen(),
          selected <- selected_for_gen(titles),
          block <- optional_block_gen()
        ) do
      %Tabs{titles: titles, selected: selected, block: block}
    end
  end

  defp sparkline_gen do
    gen all(
          data <- list_of(integer(0..100), max_length: 30),
          max <- one_of([constant(nil), integer(1..200)]),
          direction <- member_of([:left_to_right, :right_to_left]),
          bar_set <- member_of([:nine_levels, :three_levels]),
          block <- optional_block_gen()
        ) do
      %Sparkline{
        data: data,
        max: max,
        direction: direction,
        bar_set: bar_set,
        block: block
      }
    end
  end

  defp bar_gen do
    gen all(
          label <- short_text_gen(),
          value <- integer(0..100)
        ) do
      %Bar{label: label, value: value}
    end
  end

  defp bar_chart_gen do
    gen all(
          bars <- list_of(bar_gen(), min_length: 1, max_length: 6),
          bar_width <- integer(1..5),
          bar_gap <- integer(0..3),
          group_gap <- integer(0..3),
          direction <- member_of([:vertical, :horizontal]),
          block <- optional_block_gen()
        ) do
      %BarChart{
        groups: [%BarGroup{bars: bars}],
        bar_width: bar_width,
        bar_gap: bar_gap,
        group_gap: group_gap,
        direction: direction,
        block: block
      }
    end
  end

  defp throbber_gen do
    gen all(
          label <- short_text_gen(),
          throbber_set <- member_of(@throbber_sets),
          step <- integer(0..20),
          block <- optional_block_gen()
        ) do
      %Throbber{label: label, throbber_set: throbber_set, step: step, block: block}
    end
  end

  defp scrollbar_gen do
    gen all(
          orientation <- member_of(@scrollbar_orientations),
          content_length <- integer(0..50),
          position <- integer(0..50)
        ) do
      %Scrollbar{
        orientation: orientation,
        content_length: content_length,
        position: min(position, content_length)
      }
    end
  end

  defp checkbox_gen do
    gen all(
          label <- short_text_gen(),
          checked <- boolean(),
          block <- optional_block_gen()
        ) do
      %Checkbox{label: label, checked: checked, block: block}
    end
  end

  defp calendar_gen do
    gen all(
          year <- integer(1970..2030),
          month <- integer(1..12),
          day <- integer(1..28),
          show_month_header <- boolean(),
          show_weekdays_header <- boolean(),
          block <- optional_block_gen()
        ) do
      %Calendar{
        display_date: Date.new!(year, month, day),
        show_month_header: show_month_header,
        show_weekdays_header: show_weekdays_header,
        block: block
      }
    end
  end

  defp markdown_gen do
    gen all(
          content <- string(:printable, max_length: 80),
          block <- optional_block_gen()
        ) do
      %Markdown{content: content, block: block}
    end
  end

  defp big_text_gen do
    gen all(
          text <- short_text_gen(),
          pixel_size <- member_of(@big_text_sizes),
          alignment <- member_of([:left, :center, :right]),
          block <- optional_block_gen()
        ) do
      widget = ExRatatui.BigText.new(text, pixel_size: pixel_size, alignment: alignment)
      %{widget | block: block}
    end
  end

  defp widget_gen do
    one_of([
      paragraph_gen(),
      block_gen(),
      clear_gen(),
      list_gen(),
      table_gen(),
      gauge_gen(),
      line_gauge_gen(),
      tabs_gen(),
      sparkline_gen(),
      bar_chart_gen(),
      throbber_gen(),
      scrollbar_gen(),
      checkbox_gen(),
      calendar_gen(),
      markdown_gen(),
      big_text_gen()
    ])
  end

  # ----------------------------------------------------------------------
  # Properties
  # ----------------------------------------------------------------------

  property "Bridge.encode_commands! accepts every generated widget at every rect" do
    check all(widget <- widget_gen(), rect <- rect_gen()) do
      assert [{wire, %{"x" => _, "y" => _, "width" => _, "height" => _}}] =
               Bridge.encode_commands!([{widget, rect}])

      assert is_map(wire)
      assert is_binary(wire["type"])
    end
  end

  property "CellSession render produces a snapshot with width*height cells" do
    check all(
            widget <- widget_gen(),
            width <- integer(1..40),
            height <- integer(1..20)
          ) do
      session = CellSession.new(width, height)
      rect = %Rect{x: 0, y: 0, width: width, height: height}

      try do
        :ok = CellSession.draw(session, [{widget, rect}])
        snapshot = CellSession.take_cells(session)
        assert length(snapshot.cells) == width * height
      after
        CellSession.close(session)
      end
    end
  end
end
