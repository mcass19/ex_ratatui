# Example: Custom Widgets — demonstrates the ExRatatui.Widget protocol by
# composing primitives into reusable composite widgets. Two custom widgets
# (StatusBadge and UserCard) are built on top of Block, Paragraph, and rich
# text; a Dashboard custom widget arranges several UserCards and exercises
# the expander's recursive flattening.
#
# Run with: mix run examples/custom_widgets.exs
#
# Controls: up/down = move selection, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Text.{Line, Span}
alias ExRatatui.Widgets.{Block, Paragraph}

defmodule CustomWidgets.StatusBadge do
  @moduledoc """
  A single-line colored badge showing a one-word status plus optional suffix.

  Renders as a `Paragraph` with a styled leading span and a neutral tail,
  letting the parent pick the rect (typically 1 row tall).
  """

  defstruct [:status, suffix: ""]

  defimpl ExRatatui.Widget do
    @colors %{
      online: :green,
      away: :yellow,
      busy: :red,
      offline: :dark_gray
    }

    def render(%{status: status, suffix: suffix}, rect) do
      color = Map.fetch!(@colors, status)
      label = status |> Atom.to_string() |> String.upcase()

      paragraph = %Paragraph{
        text:
          Line.new([
            Span.new(" #{label} ", style: %Style{bg: color, fg: :black, modifiers: [:bold]}),
            Span.new("  " <> suffix, style: %Style{fg: :white})
          ])
      }

      [{paragraph, rect}]
    end
  end
end

defmodule CustomWidgets.UserCard do
  @moduledoc """
  A two-row card: name/handle on the header, status badge on the body.

  Returns a `Block` wrapping child rects and delegates the status row to
  `StatusBadge` — the expander keeps walking until only primitives remain.
  """

  defstruct [:user, selected?: false]

  defimpl ExRatatui.Widget do
    alias CustomWidgets.StatusBadge

    def render(%{user: user, selected?: sel?}, %Rect{} = rect) do
      border_color = if sel?, do: :cyan, else: :dark_gray

      inner = %Rect{
        x: rect.x + 1,
        y: rect.y + 1,
        width: max(rect.width - 2, 0),
        height: max(rect.height - 2, 0)
      }

      [header_rect, body_rect] =
        Layout.split(inner, :vertical, [{:length, 1}, {:min, 0}])

      header = %Paragraph{
        text:
          Line.new([
            Span.new(user.name, style: %Style{fg: :white, modifiers: [:bold]}),
            Span.new("  @" <> user.handle, style: %Style{fg: :dark_gray})
          ])
      }

      block = %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: border_color}
      }

      [
        {block, rect},
        {header, header_rect},
        {%StatusBadge{status: user.status, suffix: user.activity}, body_rect}
      ]
    end
  end
end

defmodule CustomWidgets.Dashboard do
  @moduledoc """
  Vertically stacks a list of `UserCard`s (all the same height) inside a
  framed area. Demonstrates that a custom widget can itself return other
  custom widgets — the Bridge expands the whole tree in one pass.
  """

  defstruct cards: [], selected_index: 0

  defimpl ExRatatui.Widget do
    alias CustomWidgets.UserCard

    @card_height 4

    def render(%{cards: cards, selected_index: selected_index}, %Rect{} = rect) do
      title =
        Line.new([
          Span.new(" "),
          Span.new("Team", style: %Style{fg: :cyan, modifiers: [:bold]}),
          Span.new(" — ", style: %Style{fg: :dark_gray}),
          Span.new("#{length(cards)} members ", style: %Style{fg: :white})
        ])

      outer = %Block{
        title: title,
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }

      inner = %Rect{
        x: rect.x + 1,
        y: rect.y + 1,
        width: max(rect.width - 2, 0),
        height: max(rect.height - 2, 0)
      }

      card_rects = slice_rows(inner, @card_height, length(cards))

      cards_with_rects =
        cards
        |> Enum.with_index()
        |> Enum.zip(card_rects)
        |> Enum.map(fn {{user, index}, card_rect} ->
          {%UserCard{user: user, selected?: index == selected_index}, card_rect}
        end)

      [{outer, rect} | cards_with_rects]
    end

    defp slice_rows(%Rect{} = area, row_height, count) do
      for i <- 0..max(count - 1, 0) do
        %Rect{
          x: area.x,
          y: area.y + i * row_height,
          width: area.width,
          height: row_height
        }
      end
    end
  end
end

defmodule CustomWidgetsExample do
  use ExRatatui.App

  @users [
    %{name: "Alice Moreno", handle: "alicem", status: :online, activity: "reviewing PRs"},
    %{name: "Ben Tanaka", handle: "bent", status: :busy, activity: "in a meeting"},
    %{name: "Carol Rivera", handle: "carolr", status: :away, activity: "back in 15m"},
    %{name: "Dan Okafor", handle: "dano", status: :offline, activity: "last seen 2h ago"}
  ]

  @impl true
  def mount(_opts) do
    {:ok, %{users: @users, selected: 0}}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [body_area, footer_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 1}])

    dashboard = %CustomWidgets.Dashboard{
      cards: state.users,
      selected_index: state.selected
    }

    footer = %Paragraph{
      text:
        Line.new([
          Span.new(" ↑/↓ ", style: %Style{fg: :black, bg: :cyan}),
          Span.new(" move selection  "),
          Span.new(" q ", style: %Style{fg: :black, bg: :red}),
          Span.new(" quit")
        ])
    }

    [{dashboard, body_area}, {footer, footer_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "up", kind: "press"}, state) do
    new_index = max(state.selected - 1, 0)
    {:noreply, %{state | selected: new_index}}
  end

  def handle_event(%Event.Key{code: "down", kind: "press"}, state) do
    new_index = min(state.selected + 1, length(state.users) - 1)
    {:noreply, %{state | selected: new_index}}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end
end

{:ok, pid} = CustomWidgetsExample.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
