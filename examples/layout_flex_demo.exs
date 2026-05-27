# Example: Layout — every Flex mode, Constraint::Fill, and segment
# spacing on one screen. Exercises the four new Layout features that
# landed alongside the focus mouse work.
#
# Layout (top to bottom):
#   * Header — three fixed-length segments centered by `flex: :center`.
#   * Flex row — five labeled bars demoing each :flex mode side by side.
#   * Fill row — three growable panels with `{:fill, 1/2/3}` weights and
#     a 2-cell `spacing:` gutter.
#   * Footer — :end-aligned status block.
#
# Press any key (or Esc) to quit.
# Run with:  mix run examples/layout_flex_demo.exs

alias ExRatatui.{Event, Layout, Style, Theme}
alias ExRatatui.Layout.Rect
alias ExRatatui.Widgets.{Block, Paragraph}
alias ExRatatui.Widgets.Block.Title

defmodule LayoutFlexDemo do
  use ExRatatui.App

  @flex_modes [:start, :center, :end, :space_between, :space_around]

  @impl true
  def mount(_opts) do
    {:ok, %{theme: Theme.default()}}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header, flex_row, fill_row, footer] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:length, length(@flex_modes) * 5 + 4},
        {:min, 0},
        {:length, 3}
      ])

    [
      {header_widget(state), header}
      | flex_row_widgets(state, flex_row) ++
          fill_row_widgets(state, fill_row) ++
          [{footer_widget(state), footer}]
    ]
  end

  @impl true
  def handle_event(%Event.Key{kind: "press"}, state), do: {:stop, state}
  def handle_event(_, state), do: {:noreply, state}

  # --- header: three centered length segments --------------------------

  defp header_widget(state) do
    %Paragraph{
      text: "Layout flex modes + Constraint::Fill + spacing",
      alignment: :center,
      style: %Style{fg: state.theme.text, modifiers: [:bold]},
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(state.theme, focused: true),
        title: "ExRatatui.Layout.split/4",
        titles: [
          %Title{content: "demo", alignment: :right, style: %Style{fg: state.theme.text_dim}}
        ]
      }
    }
  end

  # --- flex row: one labeled strip per :flex mode ----------------------

  defp flex_row_widgets(state, area) do
    rects =
      Layout.split(
        area,
        :vertical,
        Enum.map(@flex_modes, fn _ -> {:length, 5} end),
        spacing: 0
      )

    Enum.zip(@flex_modes, rects)
    |> Enum.map(fn {mode, strip_rect} ->
      {flex_strip_widget(state, mode, strip_rect), strip_rect}
    end)
  end

  defp flex_strip_widget(state, mode, strip_rect) do
    # Inside each strip, lay three fixed-width "tile" placeholders out
    # with the named Flex mode and inline the resulting rects into the
    # title bar so the visual matches the layout.
    inner =
      Layout.split(
        %Rect{strip_rect | x: 0, y: 0},
        :horizontal,
        [{:length, 6}, {:length, 6}, {:length, 6}],
        flex: mode
      )

    positions =
      inner
      |> Enum.map(&"#{&1.x}..#{&1.x + &1.width - 1}")
      |> Enum.join(" / ")

    %Paragraph{
      text: "flex: :#{mode}\n  three 6-cell segments → cols #{positions}",
      style: %Style{fg: state.theme.text_dim},
      block: %Block{
        borders: [:all],
        border_type: :plain,
        border_style: %Style{fg: state.theme.border},
        title: " :#{mode} ",
        title_style: %Style{fg: state.theme.accent, modifiers: [:bold]}
      }
    }
  end

  # --- fill row: three growable panels with a gutter -------------------

  defp fill_row_widgets(state, area) do
    [a, b, c] =
      Layout.split(area, :horizontal, [{:fill, 1}, {:fill, 2}, {:fill, 3}], spacing: 2)

    [
      {fill_panel(state, "{:fill, 1}", "1 share", :primary), a},
      {fill_panel(state, "{:fill, 2}", "2 shares", :accent), b},
      {fill_panel(state, "{:fill, 3}", "3 shares of leftover", :success), c}
    ]
  end

  defp fill_panel(state, title, body, accent_slot) do
    accent = Map.fetch!(state.theme, accent_slot)

    %Paragraph{
      text: body,
      style: %Style{fg: state.theme.text},
      wrap: true,
      block: %Block{
        title: title,
        title_style: %Style{fg: accent, modifiers: [:bold]},
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: accent}
      }
    }
  end

  # --- footer: right-aligned status chip -------------------------------

  defp footer_widget(state) do
    %Paragraph{
      text: " press any key to quit ",
      alignment: :right,
      style: %Style{
        fg: :black,
        bg: state.theme.warning,
        modifiers: [:bold]
      }
    }
  end
end

{:ok, pid} = LayoutFlexDemo.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
