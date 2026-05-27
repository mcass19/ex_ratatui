# Example: Chat log — `%List{direction: :bottom_to_top}` history pinned
# to the bottom edge + multi-line `%Textarea{}` composer with bracketed
# paste support + multi-title `%Block{}` header showing channel + unread
# count.
#
# Exercises the round-1 features that didn't land in the other demos:
#   * List `:direction: :bottom_to_top` (chat / REPL pattern)
#   * Block multi-title with right-aligned status
#   * `Event.Paste` → `textarea_insert_str/2` for multi-line pasted
#     content (try copying a multi-line code snippet from anywhere)
#   * `ExRatatui.Theme` threading
#   * `ExRatatui.Focus` Tab cycling between log + composer
#
# Keys:
#   Tab            cycle focus (log ↔ composer)
#   Enter (in composer)  send message
#   Ctrl+L         clear the log (resets unread to 0)
#   Esc            quit
#
# Run with:  mix run examples/chat_log.exs

alias ExRatatui.{Event, Focus, Layout, Style, Theme}
alias ExRatatui.Layout.Rect
alias ExRatatui.Text.{Line, Span}
alias ExRatatui.Widgets.{Block, List, Paragraph, Textarea}
alias ExRatatui.Widgets.Block.Title

defmodule ChatLog do
  use ExRatatui.App

  @seed [
    {"alice", "morning! anyone up for a quick design review?"},
    {"bob", "yeah, give me 5 — pouring coffee"},
    {"alice", "no rush. paste the figma link when you're back"},
    {"bob", "k. it's the one we sketched yesterday + a few iterations"},
    {"alice", "perfect"}
  ]

  @impl true
  def mount(_opts) do
    state = %{
      focus: Focus.new([:log, :composer]) |> Focus.focus(:composer),
      theme: Theme.default(),
      composer: ExRatatui.textarea_new(),
      messages: @seed,
      unread: 0,
      typing_user: "me"
    }

    {:ok, state}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    # Composer height grows with line count, capped at 6 rows so a
    # runaway paste never devours the log area.
    composer_height = state.composer |> ExRatatui.textarea_line_count() |> min(6) |> max(1)

    [header_rect, log_rect, composer_rect, footer_rect] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:min, 0},
        {:length, composer_height + 2},
        {:length, 1}
      ])

    [
      {header_widget(state), header_rect},
      {log_widget(state), log_rect},
      {composer_widget(state), composer_rect},
      {footer_widget(state), footer_rect}
    ]
  end

  @impl true
  def handle_event(%Event.Key{code: "esc", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: "l", modifiers: ["ctrl"], kind: "press"}, state) do
    {:noreply, %{state | messages: [], unread: 0}}
  end

  def handle_event(%Event.Key{kind: "press"} = key, state) do
    {focus, key} = Focus.handle_key(state.focus, key)
    state = %{state | focus: focus}

    case key do
      nil ->
        {:noreply, state}

      key ->
        case Focus.current(focus) do
          :composer -> {:noreply, dispatch_composer(state, key)}
          :log -> {:noreply, dispatch_log(state, key)}
        end
    end
  end

  # Pasted blobs land in the composer regardless of which panel has
  # focus — most chat clients paste at the cursor whether the user
  # last-clicked the log or not. textarea_insert_str/2 preserves \n
  # and \r\n as line breaks; lone \r is dropped.
  def handle_event(%Event.Paste{content: text}, state) do
    :ok = ExRatatui.textarea_insert_str(state.composer, text)
    {:noreply, %{state | focus: Focus.focus(state.focus, :composer)}}
  end

  def handle_event(_, state), do: {:noreply, state}

  # --- dispatch --------------------------------------------------------

  defp dispatch_composer(state, %Event.Key{code: "enter", modifiers: mods}) when mods == [] do
    case state.composer |> ExRatatui.textarea_get_value() |> String.trim() do
      "" ->
        state

      text ->
        :ok = ExRatatui.textarea_set_value(state.composer, "")
        %{state | messages: state.messages ++ [{state.typing_user, text}]}
    end
  end

  defp dispatch_composer(state, %Event.Key{code: code, modifiers: mods}) do
    :ok = ExRatatui.textarea_handle_key(state.composer, code, mods)
    state
  end

  # Pretend an unread counter ticks up while the user is reading the log.
  defp dispatch_log(state, %Event.Key{code: "u"}) do
    %{state | unread: state.unread + 1}
  end

  defp dispatch_log(state, _key), do: state

  # --- widgets ---------------------------------------------------------

  defp header_widget(state) do
    unread_title =
      case state.unread do
        0 ->
          []

        n ->
          [%Title{content: "#{n} unread", alignment: :right, style: badge_style(state, :accent)}]
      end

    %Paragraph{
      text: " welcome to #general ",
      alignment: :center,
      style: %Style{fg: state.theme.text_dim},
      block: %Block{
        title: " #general ",
        title_style: %Style{fg: state.theme.surface, bg: state.theme.accent, modifiers: [:bold]},
        titles: unread_title,
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: state.theme.border}
      }
    }
  end

  # Bottom-to-top list pins the newest message to the bottom of the
  # area and grows upward — the classic chat/log shape. Items receive
  # the list with the *oldest* first; ratatui handles the visual flip.
  defp log_widget(state) do
    items = Enum.map(state.messages, &format_message(state, &1))

    %List{
      items: items,
      direction: :bottom_to_top,
      scroll_padding: 1,
      block: %Block{
        title: " messages ",
        borders: [:all],
        border_type: :rounded,
        border_style: border_style(state, :log)
      }
    }
  end

  defp format_message(state, {user, body}) do
    Line.new([
      Span.new("#{String.pad_trailing(user, 6)} ", style: %Style{fg: user_color(state, user)}),
      Span.new(body, style: %Style{fg: state.theme.text})
    ])
  end

  defp user_color(state, "me"), do: state.theme.accent
  defp user_color(state, "alice"), do: state.theme.primary
  defp user_color(state, "bob"), do: state.theme.success
  defp user_color(state, _), do: state.theme.text_dim

  defp composer_widget(state) do
    %Textarea{
      state: state.composer,
      placeholder: "type a message, or paste any blob (multi-line supported)",
      block: %Block{
        title: " composer ",
        borders: [:all],
        border_type: :rounded,
        border_style: border_style(state, :composer)
      }
    }
  end

  defp footer_widget(state) do
    %Paragraph{
      text:
        Line.new([
          chip(state, "Tab", :accent),
          Span.new(" cycle focus  "),
          chip(state, "Enter", :accent),
          Span.new(" send  "),
          chip(state, "Paste", :accent),
          Span.new(" insert blob  "),
          chip(state, "Ctrl+L", :warning),
          Span.new(" clear  "),
          chip(state, "Esc", :danger),
          Span.new(" quit")
        ])
    }
  end

  defp chip(state, label, slot),
    do: Span.new(" #{label} ", style: badge_style(state, slot))

  defp badge_style(state, slot) do
    %Style{fg: :black, bg: Map.fetch!(state.theme, slot), modifiers: [:bold]}
  end

  defp border_style(state, id) do
    Theme.border_style(state.theme, focused: Focus.focused?(state.focus, id))
  end
end

{:ok, pid} = ChatLog.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
