# Example: Theme picker — visual reference for every slot in
# `ExRatatui.Theme` plus a live switcher between the two starter
# themes (`default/0` and `light/0`) and a custom dark theme.
#
# Top half: a swatch grid showing each slot's color name + a filled
# block painted with that color, so the user can see what a slot
# means before threading it into a real widget.
#
# Bottom half: a "live" panel that uses every helper —
# `border_style/2` with both focused and unfocused states,
# `text_style/2` with `:dim`, and `selection_style/1` on a small
# selectable list — under whichever theme is active. Compare across
# `1`/`2`/`3` to see how slot choices ripple through real widgets.
#
# Keys:
#   1 / 2 / 3   switch theme (default / light / custom)
#   Esc / q     quit
#
# Run with:  mix run examples/theme_picker.exs

alias ExRatatui.{Event, Layout, Style, Theme}
alias ExRatatui.Layout.Rect
alias ExRatatui.Text.{Line, Span}
alias ExRatatui.Widgets.{Block, List, Paragraph}
alias ExRatatui.Widgets.Block.Title

defmodule ThemePicker do
  use ExRatatui.App

  @slots [
    :primary,
    :accent,
    :border,
    :border_focused,
    :surface,
    :surface_alt,
    :text,
    :text_dim,
    :success,
    :warning,
    :danger
  ]

  # A small dark theme distinct from default/0 so the third option
  # demonstrates that the slots are arbitrary colors, not magic.
  @custom %Theme{
    primary: {:rgb, 136, 192, 208},
    accent: {:rgb, 235, 203, 139},
    border: {:rgb, 76, 86, 106},
    border_focused: {:rgb, 235, 203, 139},
    surface: nil,
    surface_alt: {:rgb, 59, 66, 82},
    text: {:rgb, 236, 239, 244},
    text_dim: {:rgb, 129, 161, 193},
    success: {:rgb, 163, 190, 140},
    warning: {:rgb, 235, 203, 139},
    danger: {:rgb, 191, 97, 106}
  }

  @themes [
    {:default, "Theme.default/0", Theme.default()},
    {:light, "Theme.light/0", Theme.light()},
    {:custom, "Nord-ish (custom)", @custom}
  ]

  @impl true
  def mount(_opts) do
    {:ok, %{theme_key: :default, selected: 0}}
  end

  @impl true
  def render(state, frame) do
    theme = current_theme(state)
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_rect, body_rect, footer_rect] =
      Layout.split(area, :vertical, [{:length, 3}, {:min, 0}, {:length, 1}])

    [swatch_rect, live_rect] =
      Layout.split(body_rect, :horizontal, [{:percentage, 50}, {:min, 0}], spacing: 1)

    [
      {header_widget(state, theme), header_rect}
      | swatch_widgets(theme, swatch_rect) ++
          live_widgets(state, theme, live_rect) ++
          [{footer_widget(theme), footer_rect}]
    ]
  end

  @impl true
  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["esc", "q"] do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["1", "2", "3"] do
    key = Enum.at([:default, :light, :custom], String.to_integer(code) - 1)
    {:noreply, %{state | theme_key: key}}
  end

  def handle_event(%Event.Key{code: "up", kind: "press"}, state) do
    {:noreply, %{state | selected: max(state.selected - 1, 0)}}
  end

  def handle_event(%Event.Key{code: "down", kind: "press"}, state) do
    {:noreply, %{state | selected: min(state.selected + 1, length(@slots) - 1)}}
  end

  def handle_event(_, state), do: {:noreply, state}

  # --- header / footer -------------------------------------------------

  defp header_widget(state, theme) do
    label = @themes |> Enum.find(&(elem(&1, 0) == state.theme_key)) |> elem(1)

    %Paragraph{
      text: " #{label} ",
      alignment: :center,
      style: %Style{fg: theme.surface, bg: theme.accent, modifiers: [:bold]},
      block: %Block{
        title: " ExRatatui.Theme — slot reference + live preview ",
        title_style: %Style{fg: theme.accent, modifiers: [:bold]},
        titles: [
          %Title{content: "press 1/2/3", alignment: :right, style: %Style{fg: theme.text_dim}}
        ],
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: theme.border_focused}
      }
    }
  end

  defp footer_widget(theme) do
    %Paragraph{
      text:
        Line.new([
          chip(theme, "1", :accent),
          Span.new(" default  "),
          chip(theme, "2", :accent),
          Span.new(" light  "),
          chip(theme, "3", :accent),
          Span.new(" custom  "),
          chip(theme, "↑/↓", :primary),
          Span.new(" preview slot  "),
          chip(theme, "Esc/q", :danger),
          Span.new(" quit")
        ])
    }
  end

  defp chip(theme, label, slot) do
    Span.new(" #{label} ",
      style: %Style{fg: :black, bg: Map.fetch!(theme, slot), modifiers: [:bold]}
    )
  end

  # --- swatch grid -----------------------------------------------------

  defp swatch_widgets(theme, area) do
    inner_area = inside(area)

    # One row per slot. Each row: name label on the left, a colored
    # block on the right. Rendering one widget per row makes it easy
    # to follow which color belongs to which name.
    row_rects =
      Layout.split(
        inner_area,
        :vertical,
        Enum.map(@slots, fn _ -> {:length, 1} end)
      )

    container = swatch_container_widget(theme, area)

    [
      {container, area}
      | Enum.zip(@slots, row_rects)
        |> Enum.flat_map(fn {slot, row_rect} -> swatch_row_widgets(theme, slot, row_rect) end)
    ]
  end

  defp swatch_container_widget(theme, _area) do
    %Block{
      title: " slots ",
      title_style: %Style{fg: theme.accent, modifiers: [:bold]},
      borders: [:all],
      border_type: :rounded,
      border_style: %Style{fg: theme.border}
    }
  end

  defp swatch_row_widgets(theme, slot, row_rect) do
    [label_rect, swatch_rect] =
      Layout.split(row_rect, :horizontal, [{:length, 18}, {:min, 0}])

    color = Map.fetch!(theme, slot)
    color_repr = inspect(color)

    label = %Paragraph{
      text: " #{Atom.to_string(slot) |> String.pad_trailing(15)} ",
      style: %Style{fg: theme.text}
    }

    swatch = %Paragraph{
      text: "  #{color_repr}",
      style: swatch_style(theme, color)
    }

    [{label, label_rect}, {swatch, swatch_rect}]
  end

  defp swatch_style(theme, nil),
    do: %Style{fg: theme.text_dim, modifiers: [:italic]}

  defp swatch_style(theme, color) do
    # Painted as the slot color on top of a dim background so nil
    # slots stay visible (text_style/2 default).
    _ = theme

    %Style{
      fg: contrast_for(color),
      bg: color,
      modifiers: [:bold]
    }
  end

  # Very rough contrast picker: dark text on bright bg, light text on
  # dark bg. Good enough for a swatch; not a real WCAG calculator.
  defp contrast_for({:rgb, r, g, b}) when r + g + b > 384, do: :black
  defp contrast_for({:rgb, _, _, _}), do: :white
  defp contrast_for(name) when name in [:white, :light_gray, :yellow, :light_yellow], do: :black
  defp contrast_for(_), do: :white

  # --- live preview ----------------------------------------------------

  defp live_widgets(state, theme, area) do
    inner = inside(area)
    selected_slot = Enum.at(@slots, state.selected)

    [intro_rect, panels_rect, hint_rect] =
      Layout.split(inner, :vertical, [{:length, 3}, {:min, 0}, {:length, 1}], spacing: 1)

    [focused_rect, dim_rect] =
      Layout.split(panels_rect, :vertical, [{:percentage, 50}, {:min, 0}], spacing: 1)

    container = %Block{
      title: " live preview ",
      title_style: %Style{fg: theme.accent, modifiers: [:bold]},
      borders: [:all],
      border_type: :rounded,
      border_style: %Style{fg: theme.border}
    }

    [
      {container, area},
      {intro_widget(theme, selected_slot), intro_rect},
      {focused_panel(theme), focused_rect},
      {dim_panel(theme), dim_rect},
      {hint_widget(theme), hint_rect}
    ]
  end

  defp intro_widget(theme, slot) do
    %Paragraph{
      text:
        Line.new([
          Span.new("selected slot: ", style: %Style{fg: theme.text_dim}),
          Span.new(Atom.to_string(slot),
            style: %Style{fg: theme.accent, modifiers: [:bold, :underlined]}
          )
        ])
    }
  end

  defp focused_panel(theme) do
    %List{
      items: [
        "first item",
        "second item (selected)",
        "third item"
      ],
      selected: 1,
      highlight_symbol: "› ",
      highlight_style: Theme.selection_style(theme),
      style: Theme.text_style(theme),
      block: %Block{
        title: " focused: border_style(focused: true) ",
        title_style: %Style{fg: theme.accent},
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(theme, focused: true)
      }
    }
  end

  defp dim_panel(theme) do
    %Paragraph{
      text:
        Line.new([
          Span.new("body text via Theme.text_style/1\n", style: Theme.text_style(theme)),
          Span.new("dim text via Theme.text_style(theme, dim: true)",
            style: Theme.text_style(theme, dim: true)
          )
        ]),
      wrap: true,
      block: %Block{
        title: " unfocused: border_style(focused: false) ",
        title_style: %Style{fg: theme.text_dim},
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(theme, focused: false)
      }
    }
  end

  defp hint_widget(theme) do
    %Paragraph{
      text: "↑/↓ on the left to highlight a slot",
      alignment: :right,
      style: %Style{fg: theme.text_dim, modifiers: [:italic]}
    }
  end

  # --- helpers ---------------------------------------------------------

  defp current_theme(%{theme_key: key}) do
    {_key, _label, theme} = Enum.find(@themes, &(elem(&1, 0) == key))
    theme
  end

  # Inset a rect by 1 cell on every side so child widgets render
  # inside the bordered container above them.
  defp inside(%Rect{x: x, y: y, width: w, height: h}) do
    %Rect{
      x: x + 1,
      y: y + 1,
      width: max(w - 2, 0),
      height: max(h - 2, 0)
    }
  end
end

{:ok, pid} = ThemePicker.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
