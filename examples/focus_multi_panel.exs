# Example: Focus management — three-panel app demonstrating ExRatatui.Focus.
#
# Panels:
#   :search  (TextInput, top-left)  — type to filter the results list
#   :results (List,      bottom-left) — up/down to move selection
#   :details (Paragraph, right)       — up/down to scroll description
#
# Tab / Shift+Tab cycle focus. Esc quits.
#
# Run with: mix run examples/focus_multi_panel.exs

alias ExRatatui.{Event, Focus, Layout, Style}
alias ExRatatui.Layout.Rect
alias ExRatatui.Text.{Line, Span}
alias ExRatatui.Widgets.{Block, List, Paragraph, TextInput}

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
      search: ExRatatui.text_input_new(),
      items: @items,
      selected: 0,
      detail_scroll: 0
    }

    {:ok, state}
  end

  @impl true
  def render(state, frame) do
    filtered = filtered_items(state)
    selected = clamp(state.selected, length(filtered))
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [body, footer] = Layout.split(area, :vertical, [{:min, 0}, {:length, 1}])
    [left, right] = Layout.split(body, :horizontal, [{:percentage, 45}, {:min, 0}])
    [search_rect, results_rect] = Layout.split(left, :vertical, [{:length, 3}, {:min, 0}])

    detail_text =
      case Enum.at(filtered, selected) do
        nil -> "(no match)"
        item -> item.body
      end

    [
      {search_widget(state), search_rect},
      {results_widget(state, filtered, selected), results_rect},
      {details_widget(state, detail_text), right},
      {footer_widget(), footer}
    ]
  end

  @impl true
  def handle_event(%Event.Key{code: "esc", kind: "press"}, state) do
    {:stop, state}
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

  # --- widgets ----------------------------------------------------------

  defp search_widget(state) do
    %TextInput{
      state: state.search,
      placeholder: "Type to filter…",
      block: %Block{
        title: "Search",
        borders: [:all],
        border_style: border_style(state.focus, :search)
      }
    }
  end

  defp results_widget(state, items, selected) do
    %List{
      items: Enum.map(items, & &1.name),
      selected: if(items == [], do: nil, else: selected),
      highlight_symbol: "> ",
      highlight_style: %Style{fg: :black, bg: :yellow, modifiers: [:bold]},
      block: %Block{
        title: "Results",
        borders: [:all],
        border_style: border_style(state.focus, :results)
      }
    }
  end

  defp details_widget(state, text) do
    %Paragraph{
      text: text,
      wrap: true,
      scroll: {state.detail_scroll, 0},
      block: %Block{
        title: "Details",
        borders: [:all],
        border_style: border_style(state.focus, :details)
      }
    }
  end

  defp footer_widget do
    %Paragraph{
      text:
        Line.new([
          Span.new(" Tab ", style: %Style{fg: :black, bg: :cyan}),
          Span.new(" cycle focus  "),
          Span.new(" ↑/↓ ", style: %Style{fg: :black, bg: :cyan}),
          Span.new(" navigate / scroll  "),
          Span.new(" Esc ", style: %Style{fg: :black, bg: :red}),
          Span.new(" quit")
        ])
    }
  end

  # --- helpers ----------------------------------------------------------

  defp border_style(focus, id) do
    if Focus.focused?(focus, id),
      do: %Style{fg: :yellow, modifiers: [:bold]},
      else: %Style{fg: :dark_gray}
  end

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

{:ok, pid} = FocusExample.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
