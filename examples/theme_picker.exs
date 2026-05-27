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
      | swatch_widgets(state, theme, swatch_rect) ++
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

  defp swatch_widgets(state, theme, area) do
    inner_area = inside(area)

    # One row per slot. Each row: name label on the left, a colored
    # block on the right. The currently-selected row gets a subtle
    # background tint so the user can see which slot is being
    # previewed on the right.
    row_rects =
      Layout.split(
        inner_area,
        :vertical,
        Enum.map(@slots, fn _ -> {:length, 1} end)
      )

    container = swatch_container_widget(theme)

    [
      {container, area}
      | @slots
        |> Enum.with_index()
        |> Enum.zip(row_rects)
        |> Enum.flat_map(fn {{slot, idx}, row_rect} ->
          swatch_row_widgets(theme, slot, idx == state.selected, row_rect)
        end)
    ]
  end

  defp swatch_container_widget(theme) do
    %Block{
      title: " slots — ↑/↓ to preview ",
      title_style: %Style{fg: theme.accent, modifiers: [:bold]},
      borders: [:all],
      border_type: :rounded,
      border_style: %Style{fg: theme.border}
    }
  end

  defp swatch_row_widgets(theme, slot, selected?, row_rect) do
    [marker_rect, label_rect, swatch_rect] =
      Layout.split(row_rect, :horizontal, [{:length, 3}, {:length, 18}, {:min, 0}])

    color = Map.fetch!(theme, slot)
    color_repr = inspect(color)

    marker_text = if selected?, do: " › ", else: "   "
    row_bg = if selected?, do: theme.surface_alt, else: nil

    marker = %Paragraph{
      text: marker_text,
      style: %Style{
        fg: theme.accent,
        bg: row_bg,
        modifiers: if(selected?, do: [:bold], else: [])
      }
    }

    label = %Paragraph{
      text: " #{Atom.to_string(slot) |> String.pad_trailing(15)} ",
      style: %Style{
        fg: theme.text,
        bg: row_bg,
        modifiers: if(selected?, do: [:bold], else: [])
      }
    }

    swatch = %Paragraph{
      text: " #{color_repr}",
      style: swatch_style(color, row_bg)
    }

    [{marker, marker_rect}, {label, label_rect}, {swatch, swatch_rect}]
  end

  defp swatch_style(nil, row_bg),
    do: %Style{fg: :gray, bg: row_bg, modifiers: [:italic]}

  defp swatch_style(color, _row_bg) do
    # Paint the swatch text in inverted contrast over the slot color
    # itself — the swatch *is* the color sample.
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
    slot = Enum.at(@slots, state.selected)

    [intro_rect, swatch_rect, demo_rect] =
      Layout.split(inner, :vertical, [{:length, 1}, {:length, 5}, {:min, 0}], spacing: 1)

    container = %Block{
      title: " preview: :#{slot} ",
      title_style: %Style{fg: theme.accent, modifiers: [:bold]},
      borders: [:all],
      border_type: :rounded,
      border_style: %Style{fg: theme.border}
    }

    [
      {container, area},
      {preview_intro(theme, slot), intro_rect},
      {preview_swatch(theme, slot), swatch_rect}
      | slot_demo_widgets(theme, slot, demo_rect)
    ]
  end

  defp preview_intro(theme, slot) do
    color = Map.fetch!(theme, slot)

    %Paragraph{
      text:
        Line.new([
          Span.new("Map.fetch!(theme, :#{slot}) → ", style: %Style{fg: theme.text_dim}),
          Span.new(inspect(color), style: %Style{fg: theme.text, modifiers: [:bold]})
        ])
    }
  end

  # A big colored block painted with the selected slot — the most
  # honest "what does this slot look like" answer.
  defp preview_swatch(theme, slot) do
    color = Map.fetch!(theme, slot)
    {body, style} = swatch_body(theme, color)

    %Paragraph{
      text: body,
      alignment: :center,
      style: style,
      block: %Block{
        borders: [:all],
        border_type: :thick,
        border_style: %Style{fg: color || theme.text_dim}
      }
    }
  end

  defp swatch_body(theme, nil),
    do:
      {"  nil — falls back to the terminal default  ",
       %Style{fg: theme.text_dim, modifiers: [:italic]}}

  defp swatch_body(_theme, color),
    do: {"  #{inspect(color)}  ", %Style{fg: contrast_for(color), bg: color, modifiers: [:bold]}}

  # "Slot in context": a small widget actually using the slot in its
  # natural role. Different slots call for different demos.
  defp slot_demo_widgets(theme, slot, area) do
    [{slot_demo_widget(theme, slot), area}]
  end

  defp slot_demo_widget(theme, slot) when slot in [:border, :border_focused] do
    border_color = Map.fetch!(theme, slot)

    %Paragraph{
      text: " border_style(focused: #{slot == :border_focused}) ",
      style: Theme.text_style(theme),
      block: %Block{
        title: " block bordered with :#{slot} ",
        title_style: %Style{fg: theme.accent},
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: border_color}
      }
    }
  end

  defp slot_demo_widget(theme, slot) when slot in [:primary, :accent] do
    color = Map.fetch!(theme, slot)

    %List{
      items: ["first item", "second item (selected)", "third item"],
      selected: 1,
      highlight_symbol: "› ",
      highlight_style: %Style{fg: theme.surface, bg: color, modifiers: [:bold]},
      style: Theme.text_style(theme),
      block: %Block{
        title: " selection_style derived from :#{slot} ",
        title_style: %Style{fg: color},
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(theme)
      }
    }
  end

  defp slot_demo_widget(theme, slot) when slot in [:success, :warning, :danger] do
    color = Map.fetch!(theme, slot)

    label =
      case slot do
        :success -> "✓ build passed"
        :warning -> "⚠ 12 deprecation warnings"
        :danger -> "✖ 1 test failed"
      end

    %Paragraph{
      text:
        Line.new([
          Span.new(" #{label} ",
            style: %Style{fg: :black, bg: color, modifiers: [:bold]}
          )
        ]),
      block: %Block{
        title: " status badge using :#{slot} ",
        title_style: %Style{fg: color},
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(theme)
      }
    }
  end

  defp slot_demo_widget(theme, slot) when slot in [:surface, :surface_alt] do
    color = Map.fetch!(theme, slot)
    text_color = color && contrast_for(color)
    text_color = text_color || theme.text

    %Paragraph{
      text: "  surface fill — the table-row / panel background  ",
      alignment: :center,
      style: %Style{fg: text_color, bg: color},
      block: %Block{
        title: " filled with :#{slot} ",
        title_style: %Style{fg: theme.accent},
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(theme)
      }
    }
  end

  defp slot_demo_widget(theme, slot) when slot in [:text, :text_dim] do
    color = Map.fetch!(theme, slot)

    sample =
      case slot do
        :text -> "Theme.text_style(theme) — body copy and main paragraphs"
        :text_dim -> "Theme.text_style(theme, dim: true) — hints, placeholders, disabled"
      end

    %Paragraph{
      text: sample,
      wrap: true,
      style: %Style{fg: color, bg: theme.surface},
      block: %Block{
        title: " text styled with :#{slot} ",
        title_style: %Style{fg: theme.accent},
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.border_style(theme)
      }
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
