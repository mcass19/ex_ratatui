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
#   Tab                  cycle focus (log ↔ composer)
#   Enter (in composer)  send the message
#   Alt+Enter            insert a newline in the composer (multi-line typing)
#                        Two reasons we use Alt rather than Shift here:
#                          (1) most terminals can't disambiguate Shift+Enter
#                              from plain Enter — both send `\r` over the
#                              wire and the Shift modifier is dropped before
#                              crossterm sees it (the Kitty keyboard protocol
#                              would fix this; not on by default here).
#                          (2) tui-textarea's default key handler requires
#                              alt: false for the Enter → insert_newline arm,
#                              so we bypass it and call textarea_insert_str/2
#                              with "\n" explicitly to insert the line break.
#   Paste                drop a multi-line blob into the composer (newlines kept)
#   Ctrl+L               clear the log (resets unread to 0)
#   Esc                  quit
#
# Run with:  mix run examples/apps/chat_log.exs

alias ExRatatui.{Event, Focus, Layout, Style, Theme}
alias ExRatatui.Layout.{Padding, Rect}
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

    update_window_title(state)
    {:ok, state}
  end

  # Reflect the channel + message count in the terminal window/tab
  # title via OSC 0/2. Called from mount and after each send rather
  # than from render/2 (a side-effecting NIF doesn't belong in the
  # render path).
  defp update_window_title(state) do
    ExRatatui.set_terminal_title("ex_ratatui — #general (#{length(state.messages)})")
    state
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

  # Alt+Enter inserts a newline. tui-textarea's default key handler
  # requires alt: false for the Enter → insert_newline arm, so we
  # bypass it and call textarea_insert_str/2 with a literal "\n" —
  # which the insert_str path preserves as a real line break.
  defp dispatch_composer(state, %Event.Key{code: "enter", modifiers: ["alt"]}) do
    :ok = ExRatatui.textarea_insert_str(state.composer, "\n")
    state
  end

  defp dispatch_composer(state, %Event.Key{code: "enter", modifiers: mods}) when mods == [] do
    case state.composer |> ExRatatui.textarea_get_value() |> String.trim() do
      "" ->
        state

      text ->
        :ok = ExRatatui.textarea_set_value(state.composer, "")

        %{state | messages: state.messages ++ [{state.typing_user, text}]}
        |> update_window_title()
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
        border_style: %Style{fg: state.theme.border},
        padding: Padding.horizontal(1)
      }
    }
  end

  # Bottom-to-top list pins the newest message to the bottom edge and
  # grows upward — the classic chat shape. Ratatui's contract: items[0]
  # renders at the *bottom*. state.messages is kept in chronological
  # order (oldest first); reversing it here puts newest at items[0] →
  # bottom edge.
  defp log_widget(state) do
    items =
      state.messages
      |> Enum.reverse()
      |> Enum.flat_map(&format_message(state, &1))

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

  # A single message may contain newlines (Alt+Enter while typing, or
  # multi-line paste). Span.new/2 rejects newlines, so split the body
  # and emit one List item per line: the first carries the username
  # prefix, the rest carry an indent that lines up under the body.
  #
  # Lines are returned in REVERSE visual order because the List uses
  # direction: :bottom_to_top, where items[0] renders at the bottom.
  # The last line of the body (visually at the bottom of the message
  # block) needs to be earliest in the items list; the first line
  # (visually at the top of the message block) needs to be latest.
  defp format_message(state, {user, body}) do
    prefix = String.pad_trailing(user, 6) <> " "
    indent = String.duplicate(" ", String.length(prefix))
    user_style = %Style{fg: user_color(state, user)}
    body_style = %Style{fg: state.theme.text}

    case String.split(body, "\n") do
      [single] ->
        [Line.new([Span.new(prefix, style: user_style), Span.new(single, style: body_style)])]

      [first | rest] ->
        first_line =
          Line.new([Span.new(prefix, style: user_style), Span.new(first, style: body_style)])

        continuations =
          Enum.map(rest, fn line ->
            Line.new([Span.new(indent <> line, style: body_style)])
          end)

        Enum.reverse([first_line | continuations])
    end
  end

  defp user_color(state, "me"), do: state.theme.accent
  defp user_color(state, "alice"), do: state.theme.primary
  defp user_color(state, "bob"), do: state.theme.success
  defp user_color(state, _), do: state.theme.text_dim

  defp composer_widget(state) do
    %Textarea{
      state: state.composer,
      placeholder:
        "type a message — Enter sends, Alt+Enter inserts a newline, paste keeps line breaks",
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
          chip(state, "Alt+Enter", :accent),
          Span.new(" newline  "),
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
