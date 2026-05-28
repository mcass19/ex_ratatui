# Example: Focus management — three-panel app showcasing the full
# ExRatatui.Focus surface plus the surrounding Theme + multi-title +
# bracketed-paste features that landed alongside it.
#
# Panels:
#   :search  (TextInput, top-left)    — type to filter; paste accepts URLs / blobs
#   :results (List,      bottom-left) — up/down to move selection
#   :details (Paragraph, right)        — up/down to scroll description
#
# Interaction:
#   * Tab / Shift+Tab cycle focus through the three panels.
#   * Left-click any panel to focus it directly — the click is passed
#     through so widgets that care (TextInput cursor placement, etc.)
#     can still react.
#   * Mouse-wheel scroll routes to whichever panel currently has focus.
#   * Pasting (Ctrl+Shift+V / Cmd+V / middle-click) into :search lands
#     as one Event.Paste even with multi-line / multi-byte content.
#   * Terminal-window focus reporting (focus_events: true) — switch to
#     another window and the footer shows "window in background".
#   * Esc quits.
#
# Run with:  mix run examples/focus_multi_panel.exs

alias ExRatatui.{Event, Focus, Layout, Style, Theme}
alias ExRatatui.Layout.Rect
alias ExRatatui.Text.{Line, Span}
alias ExRatatui.Widgets.{Block, List, Paragraph, TextInput}
alias ExRatatui.Widgets.Block.Title

defmodule FocusExample do
  use ExRatatui.App

  @items [
    %{
      name: "Alpha",
      body:
        "Alpha is the first Greek letter.\nOriginally derived from the Phoenician \"aleph\".\nUsed to denote the best or primary option."
    },
    %{
      name: "Beta",
      body:
        "Beta is the second letter.\nOften used for prerelease software.\nIn finance, measures volatility vs. the market."
    },
    %{
      name: "Gamma",
      body:
        "Gamma is the third letter.\nIn physics, gamma rays are high-energy photons.\nIn options trading, the rate of change of delta."
    },
    %{
      name: "Delta",
      body:
        "Delta is the fourth letter.\nA delta is also a river landform.\nIn math, denotes change or difference."
    },
    %{
      name: "Epsilon",
      body:
        "Epsilon is the fifth letter.\nIn calculus, an arbitrarily small positive quantity.\nIn machine learning, exploration probability."
    }
  ]

  @impl true
  def mount(_opts) do
    state = %{
      focus: Focus.new([:search, :results, :details]),
      theme: Theme.default(),
      search: ExRatatui.text_input_new(),
      items: @items,
      selected: 0,
      detail_scroll: 0,
      window_focused?: true
    }

    # Resize doesn't fire on initial mount — register regions up front
    # from the live terminal size so left-click works on the first
    # frame instead of waiting for the user to resize.
    {w, h} = ExRatatui.terminal_size()
    {:ok, register_regions(state, w, h)}
  end

  @impl true
  def render(state, frame) do
    filtered = filtered_items(state)
    selected = clamp(state.selected, length(filtered))
    {search_rect, results_rect, details_rect, footer_rect} = panels(frame)

    detail_text =
      case Enum.at(filtered, selected) do
        nil -> "(no match)"
        item -> item.body
      end

    [
      {search_widget(state), search_rect},
      {results_widget(state, filtered, selected), results_rect},
      {details_widget(state, detail_text), details_rect},
      {footer_widget(state), footer_rect}
    ]
  end

  @impl true
  def handle_event(%Event.Key{code: "esc", kind: "press"}, state) do
    {:stop, state}
  end

  # Terminal-window focus reporting (enabled via focus_events: true on
  # start_link). A real app would pause animations / polling while the
  # window is in the background; here we just reflect it in the title bar.
  def handle_event(%Event.FocusGained{}, state),
    do: {:noreply, %{state | window_focused?: true}}

  def handle_event(%Event.FocusLost{}, state),
    do: {:noreply, %{state | window_focused?: false}}

  # Re-register hit-test regions on every layout-changing event. Focus
  # carries the regions so handle_mouse/2 below can use them without
  # re-deriving the layout per click.
  def handle_event(%Event.Resize{} = resize, state) do
    {:noreply, register_regions(state, resize.width, resize.height)}
  end

  def handle_event(%Event.Mouse{} = mouse, state) do
    {focus, mouse} = Focus.handle_mouse(state.focus, mouse)
    state = %{state | focus: focus}

    case mouse do
      %Event.Mouse{kind: kind} when kind in ["scroll_up", "scroll_down"] ->
        # Route scroll to whichever panel is focused.
        {:noreply, dispatch_scroll(state, kind)}

      _ ->
        # Other mouse kinds (click pass-through, drag, move, up) are
        # currently a no-op in this example — focus already moved.
        {:noreply, state}
    end
  end

  # Pasted blobs land in the search field as one Event.Paste,
  # regardless of multi-line / multi-byte content. text_input_insert_str
  # strips newlines for us (single-line widget).
  def handle_event(%Event.Paste{content: text}, state) do
    if Focus.focused?(state.focus, :search) do
      :ok = ExRatatui.text_input_insert_str(state.search, text)
      {:noreply, %{state | selected: 0, detail_scroll: 0}}
    else
      {:noreply, state}
    end
  end

  def handle_event(%Event.Key{kind: "press"} = key, state) do
    {focus, key} = Focus.handle_key(state.focus, key)
    state = %{state | focus: focus}

    case key do
      nil ->
        {:noreply, state}

      key ->
        case Focus.current(focus) do
          :search -> {:noreply, dispatch_search(state, key)}
          :results -> {:noreply, dispatch_results(state, key)}
          :details -> {:noreply, dispatch_details(state, key)}
        end
    end
  end

  def handle_event(_event, state), do: {:noreply, state}

  # --- layout -----------------------------------------------------------

  defp panels(%{width: w, height: h}) do
    area = %Rect{x: 0, y: 0, width: w, height: h}
    [body, footer] = Layout.split(area, :vertical, [{:min, 0}, {:length, 1}])
    [left, right] = Layout.split(body, :horizontal, [{:percentage, 45}, {:min, 0}])
    [search, results] = Layout.split(left, :vertical, [{:length, 3}, {:min, 0}])
    {search, results, right, footer}
  end

  defp register_regions(state, w, h) do
    {search_rect, results_rect, details_rect, _footer} = panels(%{width: w, height: h})

    focus =
      Focus.set_regions(state.focus, %{
        search: search_rect,
        results: results_rect,
        details: details_rect
      })

    %{state | focus: focus}
  end

  # --- dispatch ---------------------------------------------------------

  defp dispatch_search(state, %Event.Key{code: code}) do
    :ok = ExRatatui.text_input_handle_key(state.search, code)
    %{state | selected: 0, detail_scroll: 0}
  end

  defp dispatch_results(state, %Event.Key{code: "up"}) do
    %{state | selected: max(state.selected - 1, 0), detail_scroll: 0}
  end

  defp dispatch_results(state, %Event.Key{code: "down"}) do
    max_index = max(length(filtered_items(state)) - 1, 0)
    %{state | selected: min(state.selected + 1, max_index), detail_scroll: 0}
  end

  defp dispatch_results(state, _), do: state

  defp dispatch_details(state, %Event.Key{code: "up"}) do
    %{state | detail_scroll: max(state.detail_scroll - 1, 0)}
  end

  defp dispatch_details(state, %Event.Key{code: "down"}) do
    %{state | detail_scroll: state.detail_scroll + 1}
  end

  defp dispatch_details(state, _), do: state

  defp dispatch_scroll(state, "scroll_up") do
    case Focus.current(state.focus) do
      :results -> %{state | selected: max(state.selected - 1, 0), detail_scroll: 0}
      :details -> %{state | detail_scroll: max(state.detail_scroll - 1, 0)}
      _ -> state
    end
  end

  defp dispatch_scroll(state, "scroll_down") do
    case Focus.current(state.focus) do
      :results ->
        max_index = max(length(filtered_items(state)) - 1, 0)
        %{state | selected: min(state.selected + 1, max_index), detail_scroll: 0}

      :details ->
        %{state | detail_scroll: state.detail_scroll + 1}

      _ ->
        state
    end
  end

  # --- widgets ----------------------------------------------------------

  defp search_widget(state) do
    %TextInput{
      state: state.search,
      placeholder: "Type to filter (paste also works)",
      block: panel_block(state, :search, "Search")
    }
  end

  defp results_widget(state, items, selected) do
    %List{
      items: Enum.map(items, & &1.name),
      selected: if(items == [], do: nil, else: selected),
      highlight_symbol: "> ",
      highlight_style: Theme.selection_style(state.theme),
      # Demonstrate the new scroll_padding field; small list so it's
      # subtle but the moduledoc explains the effect.
      scroll_padding: 1,
      block: panel_block(state, :results, "Results", "#{length(items)}")
    }
  end

  defp details_widget(state, text) do
    %Paragraph{
      text: text,
      wrap: true,
      scroll: {state.detail_scroll, 0},
      block: panel_block(state, :details, "Details", "L#{state.detail_scroll + 1}")
    }
  end

  # Multi-title block: panel name on the top-left, optional status
  # token on the top-right. focused? swaps the border color via Theme.
  defp panel_block(state, id, title, status \\ nil) do
    focused? = Focus.focused?(state.focus, id)

    titles =
      case status do
        nil -> []
        s -> [%Title{content: s, alignment: :right, style: %Style{fg: state.theme.text_dim}}]
      end

    %Block{
      title: title,
      titles: titles,
      borders: [:all],
      border_type: :rounded,
      border_style: Theme.border_style(state.theme, focused: focused?)
    }
  end

  defp footer_widget(state) do
    {focus_label, focus_color} =
      if state.window_focused?,
        do: {"window focused", state.theme.success},
        else: {"window in background", state.theme.warning}

    %Paragraph{
      text:
        Line.new([
          chip("Tab", state.theme.accent),
          Span.new(" cycle focus  "),
          chip("Click", state.theme.accent),
          Span.new(" focus panel  "),
          chip("↑/↓", state.theme.accent),
          Span.new(" navigate/scroll  "),
          chip("Esc", state.theme.danger),
          Span.new(" quit   "),
          Span.new(focus_label, style: %Style{fg: focus_color, modifiers: [:bold]})
        ])
    }
  end

  defp chip(label, bg_color) do
    Span.new(" #{label} ", style: %Style{fg: :black, bg: bg_color, modifiers: [:bold]})
  end

  # --- helpers ----------------------------------------------------------

  defp filtered_items(state) do
    needle = state.search |> ExRatatui.text_input_get_value() |> String.downcase()

    case needle do
      "" -> state.items
      _ -> Enum.filter(state.items, &String.contains?(String.downcase(&1.name), needle))
    end
  end

  defp clamp(_n, 0), do: 0
  defp clamp(n, len), do: n |> max(0) |> min(len - 1)
end

# Opt-in to mouse capture so the example can demonstrate click-to-focus
# and scroll-wheel routing on the local terminal. SSH / distributed
# transports get mouse events from their VTE input parser regardless.
{:ok, pid} = FocusExample.start_link(mouse_capture: true, focus_events: true)
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
