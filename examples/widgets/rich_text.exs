# Example: Rich Text Showcase — demonstrates per-span styling on Paragraph,
# List, Table, Tabs, and Block titles via ExRatatui.Text.{Span, Line}.
# Run with: mix run examples/widgets/rich_text.exs
#
# Controls: Tab/Shift+Tab = switch tabs, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Text.{Line, Span}
alias ExRatatui.Widgets.{Block, List, Paragraph, Table, Tabs}

defmodule RichTextShowcase do
  use ExRatatui.App

  @tabs_count 3

  @impl true
  def mount(_opts) do
    {:ok, %{tab: 0}}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [tabs_area, body_area, footer_area] =
      Layout.split(area, :vertical, [{:length, 3}, {:min, 0}, {:length, 1}])

    tabs = %Tabs{
      titles: [
        Line.new([
          Span.new(" 1 ", style: %Style{bg: :green, fg: :black, modifiers: [:bold]}),
          Span.new(" Paragraph ")
        ]),
        Line.new([
          Span.new(" 2 ", style: %Style{bg: :yellow, fg: :black, modifiers: [:bold]}),
          Span.new(" List ")
        ]),
        Line.new([
          Span.new(" 3 ", style: %Style{bg: :magenta, fg: :black, modifiers: [:bold]}),
          Span.new(" Table ")
        ])
      ],
      selected: state.tab,
      style: %Style{fg: :dark_gray},
      highlight_style: %Style{fg: :white, modifiers: [:bold]},
      divider: " ",
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("Rich Text", style: %Style{fg: :cyan, modifiers: [:bold]}),
            Span.new(" "),
            Span.new("Showcase", style: %Style{fg: :white}),
            Span.new(" ")
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    body_widget = render_tab(state.tab, body_area)

    footer = %Paragraph{
      text:
        Line.new([
          Span.new(" Tab/Shift+Tab ", style: %Style{fg: :black, bg: :cyan}),
          Span.new(" switch tabs  "),
          Span.new(" q ", style: %Style{fg: :black, bg: :red}),
          Span.new(" quit")
        ])
    }

    [{tabs, tabs_area}, body_widget, {footer, footer_area}]
  end

  # --- Tab 1: Paragraph with mixed spans and lines ---
  defp render_tab(0, area) do
    text = [
      Line.new([
        Span.new("$ ", style: %Style{fg: :dark_gray}),
        Span.new("mix test", style: %Style{fg: :white, modifiers: [:bold]})
      ]),
      Line.new([]),
      Line.new([
        Span.new("  ", style: %Style{fg: :green, modifiers: [:bold]}),
        Span.new("ok   ", style: %Style{fg: :green}),
        Span.new("bridge_test.exs", style: %Style{fg: :white}),
        Span.new("  30 tests, 0 failures", style: %Style{fg: :dark_gray})
      ]),
      Line.new([
        Span.new("  ", style: %Style{fg: :green, modifiers: [:bold]}),
        Span.new("ok   ", style: %Style{fg: :green}),
        Span.new("rendering_test.exs", style: %Style{fg: :white}),
        Span.new("  18 tests, 0 failures", style: %Style{fg: :dark_gray})
      ]),
      Line.new([
        Span.new("  ", style: %Style{fg: :yellow, modifiers: [:bold]}),
        Span.new("warn ", style: %Style{fg: :yellow}),
        Span.new("text/span_test.exs", style: %Style{fg: :white}),
        Span.new("  deprecated helper used", style: %Style{fg: :dark_gray})
      ]),
      Line.new([
        Span.new("  ", style: %Style{fg: :red, modifiers: [:bold]}),
        Span.new("fail ", style: %Style{fg: :red}),
        Span.new("coerce_test.exs", style: %Style{fg: :white}),
        Span.new("  1 test, 1 failure", style: %Style{fg: :dark_gray})
      ]),
      Line.new([]),
      Line.new(
        [
          Span.new("Finished in ", style: %Style{fg: :dark_gray}),
          Span.new("1.4s ", style: %Style{fg: :cyan, modifiers: [:bold]}),
          Span.new("— ", style: %Style{fg: :dark_gray}),
          Span.new("49 tests", style: %Style{fg: :white}),
          Span.new(", ", style: %Style{fg: :dark_gray}),
          Span.new("1 failure", style: %Style{fg: :red, modifiers: [:bold]})
        ],
        alignment: :center
      )
    ]

    paragraph = %Paragraph{
      text: text,
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("Paragraph", style: %Style{fg: :green, modifiers: [:bold]}),
            Span.new(" — mixed spans per line ", style: %Style{fg: :dark_gray})
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :green}
      }
    }

    {paragraph, area}
  end

  # --- Tab 2: List with status badges per item ---
  defp render_tab(1, area) do
    items = [
      badge_item("DONE", :green, "Wire Paragraph to rich text"),
      badge_item("DONE", :green, "Wire List to rich text"),
      badge_item("DONE", :green, "Wire Table rows + header"),
      badge_item("DONE", :green, "Wire Tabs titles"),
      badge_item("DONE", :green, "Wire Block title"),
      badge_item("WIP ", :yellow, "Docs + CHANGELOG"),
      badge_item("TODO", :dark_gray, "Retrofit system_monitor example"),
      badge_item("TODO", :dark_gray, "Cut 0.8.0 release")
    ]

    list = %List{
      items: items,
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("List", style: %Style{fg: :yellow, modifiers: [:bold]}),
            Span.new(" — badges on each row ", style: %Style{fg: :dark_gray})
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :yellow}
      }
    }

    {list, area}
  end

  # --- Tab 3: Table with rich header + colored log-level rows ---
  defp render_tab(2, area) do
    header = [
      Span.new("Level", style: %Style{fg: :cyan, modifiers: [:bold, :underlined]}),
      Span.new("Time", style: %Style{fg: :cyan, modifiers: [:bold, :underlined]}),
      Span.new("Source", style: %Style{fg: :cyan, modifiers: [:bold, :underlined]}),
      Span.new("Message", style: %Style{fg: :cyan, modifiers: [:bold, :underlined]})
    ]

    rows = [
      log_row("INFO", :cyan, "12:04:01", "server", "listening on port 4000"),
      log_row("INFO", :cyan, "12:04:02", "bridge", "NIF loaded lazily"),
      log_row("WARN", :yellow, "12:04:17", "render", "large text payload (3.1 KB)"),
      log_row("INFO", :cyan, "12:04:18", "input", "text_input handle_key"),
      log_row("ERROR", :red, "12:04:29", "decode", "unknown span modifier: :blinking"),
      log_row("DEBUG", :dark_gray, "12:04:31", "layout", "split 80x24 into 3 regions"),
      log_row("INFO", :cyan, "12:04:32", "session", "closed cleanly")
    ]

    table = %Table{
      rows: rows,
      header: header,
      widths: [
        {:length, 7},
        {:length, 10},
        {:length, 10},
        {:min, 10}
      ],
      column_spacing: 2,
      block: %Block{
        title:
          Line.new([
            Span.new(" "),
            Span.new("Table", style: %Style{fg: :magenta, modifiers: [:bold]}),
            Span.new(" — rich header + per-cell colors ", style: %Style{fg: :dark_gray})
          ]),
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :magenta}
      }
    }

    {table, area}
  end

  defp badge_item(label, color, description) do
    Line.new([
      Span.new(" #{label} ", style: %Style{bg: color, fg: :black, modifiers: [:bold]}),
      Span.new("  "),
      Span.new(description, style: %Style{fg: :white})
    ])
  end

  defp log_row(level, color, time, source, message) do
    [
      Span.new(level, style: %Style{fg: color, modifiers: [:bold]}),
      Span.new(time, style: %Style{fg: :dark_gray}),
      Span.new(source, style: %Style{fg: :cyan}),
      Span.new(message, style: %Style{fg: :white})
    ]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "tab", kind: "press"}, state) do
    {:noreply, %{state | tab: rem(state.tab + 1, @tabs_count)}}
  end

  def handle_event(%Event.Key{code: "back_tab", kind: "press"}, state) do
    {:noreply, %{state | tab: rem(state.tab - 1 + @tabs_count, @tabs_count)}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end

{:ok, pid} = RichTextShowcase.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
