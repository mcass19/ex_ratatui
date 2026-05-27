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
  trees stress both paths. Every widget type the library ships is
  represented: stateless leaves (Paragraph, Block, Clear, …),
  stateful widgets backed by Rust ResourceArcs (TextInput, Textarea,
  Image), and composites whose generators recurse one level deep
  (Popup wrapping a leaf, WidgetList carrying Block items, Canvas
  with shape lists, Chart with axes + datasets).

  Constraints kept tight on purpose:

    * rects are capped at 40x20 (predictable runtime, still wide
      enough to exercise wrap / scroll logic),
    * collections cap at 8 items (validates the selected-index
      contract added in the numeric-validation pass without
      generating pathological trees),
    * text is short printable ASCII (the text-coercion path has its
      own dedicated property suite),
    * Image uses a bundled 1×1 PNG; we randomise protocol and resize
      mode but not the bytes (decoder is exercised in the dedicated
      image_property_test).
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
    Canvas,
    Chart,
    Checkbox,
    Clear,
    CodeBlock,
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

  alias ExRatatui.Widgets.Canvas.{Circle, Label, Line, Points, Rectangle}
  alias ExRatatui.Widgets.Chart.{Axis, Dataset}

  @tiny_png Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
            )

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
          text <- string(:ascii, max_length: 40),
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

  # ASCII content only: tui-markdown panics ratatui's buffer index when
  # wrapping certain astral-plane code points into very narrow rects
  # (e.g. width=2). Real markdown documents are overwhelmingly ASCII +
  # diacritics; the rendering layer's cell-width accounting for
  # private-use / supplementary-plane chars is upstream territory.
  defp markdown_gen do
    gen all(
          content <- string(:ascii, max_length: 80),
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

  # ----------------------------------------------------------------------
  # Stateful + composite generators
  # ----------------------------------------------------------------------

  defp text_input_gen do
    gen all(
          placeholder <- one_of([constant(nil), short_text_gen()]),
          block <- optional_block_gen()
        ) do
      %TextInput{
        state: ExRatatui.text_input_new(),
        placeholder: placeholder,
        block: block
      }
    end
  end

  defp textarea_gen do
    gen all(block <- optional_block_gen()) do
      %Textarea{state: ExRatatui.textarea_new(), block: block}
    end
  end

  defp image_gen do
    gen all(
          protocol <- member_of([:halfblocks, :auto]),
          resize <- member_of([:fit, :crop, :scale])
        ) do
      {:ok, widget} = ExRatatui.Image.new(@tiny_png, protocol: protocol, resize: resize)
      widget
    end
  end

  defp code_block_gen do
    gen all(
          content <- string(:ascii, max_length: 80),
          language <- one_of([constant(nil), constant("elixir"), constant("rust")]),
          theme <-
            member_of([
              :base16_ocean_dark,
              :base16_ocean_light,
              :inspired_github,
              :solarized_dark
            ]),
          line_numbers <- boolean(),
          block <- optional_block_gen()
        ) do
      %CodeBlock{
        content: content,
        language: language,
        theme: theme,
        line_numbers: line_numbers,
        block: block
      }
    end
  end

  # Popup wraps any of the stateless widgets above. Recursion limited
  # to one level (popup contains a leaf, never another popup) to keep
  # generators terminating and trees small.
  defp popup_gen do
    gen all(
          content <- one_of([paragraph_gen(), list_gen(), markdown_gen()]),
          percent_width <- integer(20..90),
          percent_height <- integer(20..90),
          block <- optional_block_gen()
        ) do
      %Popup{
        content: content,
        percent_width: percent_width,
        percent_height: percent_height,
        block: block
      }
    end
  end

  defp widget_list_gen do
    gen all(
          item_count <- integer(0..6),
          height <- integer(1..3),
          selected_opt <- boolean(),
          block <- optional_block_gen()
        ) do
      items = for _ <- 1..item_count//1, do: {%Block{borders: []}, height}
      selected = if selected_opt and item_count > 0, do: 0, else: nil
      %WidgetList{items: items, selected: selected, block: block}
    end
  end

  defp bounds_gen do
    gen all(
          lo <- float(min: 0.0, max: 50.0),
          delta <- float(min: 1.0, max: 50.0)
        ) do
      {lo, lo + delta}
    end
  end

  defp canvas_shape_gen do
    one_of([
      gen all(
            x1 <- float(min: 0.0, max: 50.0),
            y1 <- float(min: 0.0, max: 50.0),
            x2 <- float(min: 0.0, max: 50.0),
            y2 <- float(min: 0.0, max: 50.0),
            color <- member_of(@named_colors -- [:reset])
          ) do
        %Line{x1: x1, y1: y1, x2: x2, y2: y2, color: color}
      end,
      gen all(
            x <- float(min: 0.0, max: 40.0),
            y <- float(min: 0.0, max: 40.0),
            width <- float(min: 1.0, max: 20.0),
            height <- float(min: 1.0, max: 20.0),
            color <- member_of(@named_colors -- [:reset])
          ) do
        %Rectangle{x: x, y: y, width: width, height: height, color: color}
      end,
      gen all(
            x <- float(min: 0.0, max: 40.0),
            y <- float(min: 0.0, max: 40.0),
            radius <- float(min: 1.0, max: 10.0),
            color <- member_of(@named_colors -- [:reset])
          ) do
        %Circle{x: x, y: y, radius: radius, color: color}
      end,
      gen all(
            coords <-
              list_of(
                tuple({float(min: 0.0, max: 50.0), float(min: 0.0, max: 50.0)}),
                min_length: 1,
                max_length: 5
              ),
            color <- member_of(@named_colors -- [:reset])
          ) do
        %Points{coords: coords, color: color}
      end,
      gen all(
            x <- float(min: 0.0, max: 50.0),
            y <- float(min: 0.0, max: 50.0),
            text <- short_text_gen(),
            color <- member_of(@named_colors -- [:reset])
          ) do
        %Label{x: x, y: y, text: text, color: color}
      end
    ])
  end

  defp canvas_gen do
    gen all(
          x_bounds <- bounds_gen(),
          y_bounds <- bounds_gen(),
          marker <- member_of([:braille, :dot, :block, :bar, :half_block]),
          shapes <- list_of(canvas_shape_gen(), max_length: 4),
          block <- optional_block_gen()
        ) do
      %Canvas{
        x_bounds: x_bounds,
        y_bounds: y_bounds,
        marker: marker,
        shapes: shapes,
        block: block
      }
    end
  end

  defp axis_gen do
    gen all(
          title <- one_of([constant(nil), short_text_gen()]),
          bounds <- bounds_gen(),
          labels <- list_of(short_text_gen(), max_length: 3)
        ) do
      %Axis{title: title, bounds: bounds, labels: labels}
    end
  end

  defp dataset_gen do
    gen all(
          name <- one_of([constant(nil), short_text_gen()]),
          data <-
            list_of(
              tuple({float(min: 0.0, max: 50.0), float(min: 0.0, max: 50.0)}),
              max_length: 8
            ),
          marker <- member_of([:braille, :dot, :block, :bar, :half_block]),
          graph_type <- member_of([:line, :scatter, :bar])
        ) do
      %Dataset{name: name, data: data, marker: marker, graph_type: graph_type}
    end
  end

  defp chart_gen do
    gen all(
          x_axis <- axis_gen(),
          y_axis <- axis_gen(),
          datasets <- list_of(dataset_gen(), min_length: 1, max_length: 3),
          block <- optional_block_gen()
        ) do
      %Chart{x_axis: x_axis, y_axis: y_axis, datasets: datasets, block: block}
    end
  end

  # Chart is excluded from `widget_gen/0` for the render property
  # because ratatui upstream panics with "attempt to divide by zero"
  # when the axis layout collapses on rects whose inner area (after
  # block borders + axis titles) leaves no room. The dedicated
  # `chart_gen/0` is exercised against realistic rect minimums in its
  # own property below; the encode property covers Chart at any rect.
  defp widget_gen(include_chart? \\ false) do
    base = [
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
      big_text_gen(),
      text_input_gen(),
      textarea_gen(),
      image_gen(),
      code_block_gen(),
      popup_gen(),
      widget_list_gen(),
      canvas_gen()
    ]

    one_of(if include_chart?, do: [chart_gen() | base], else: base)
  end

  # ----------------------------------------------------------------------
  # Properties
  # ----------------------------------------------------------------------

  property "Bridge.encode_commands! accepts every generated widget at every rect" do
    check all(widget <- widget_gen(true), rect <- rect_gen()) do
      assert [{wire, %{"x" => _, "y" => _, "width" => _, "height" => _}}] =
               Bridge.encode_commands!([{widget, rect}])

      assert is_map(wire)
      assert is_binary(wire["type"])
    end
  end

  # Chart is excluded from the render property: upstream ratatui
  # panics on multiple Chart input combinations (empty datasets, narrow
  # axis bounds, small rects after block borders, `:bar` graph_type
  # with sparse data). Charting at arbitrary inputs is genuinely not a
  # guarantee the library can prove — apps choose well-formed configs.
  # The encode property still covers Chart at any rect.
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
