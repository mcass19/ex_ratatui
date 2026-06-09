# Chat Interface Example
#
# Demonstrates all new widgets: Markdown, Textarea, Throbber, Popup,
# WidgetList, and SlashCommands in a working AI chat interface.
#
# Run with: mix run examples/apps/chat.exs
#
# Controls:
#   Ctrl+S       — send message
#   Enter        — insert newline in textarea
#   /            — trigger slash command autocomplete
#   Escape       — close autocomplete popup
#   Up/Down      — navigate autocomplete or scroll messages
#   Ctrl+C / q   — quit (when textarea is empty)

alias ExRatatui.{Layout, Style}
alias ExRatatui.Layout.Rect
alias ExRatatui.Event
alias ExRatatui.Widgets.{Block, Markdown, Paragraph, Scrollbar, Textarea, Throbber, WidgetList}
alias ExRatatui.Widgets.SlashCommands
alias ExRatatui.Widgets.SlashCommands.Command

defmodule ChatApp do
  @commands [
    %Command{name: "help", description: "Show available commands"},
    %Command{name: "clear", description: "Clear chat history"},
    %Command{name: "model", description: "Switch AI model"},
    %Command{name: "system", description: "Set system prompt"},
    %Command{name: "quit", description: "Exit the chat", aliases: ["exit", "q"]}
  ]

  @ai_responses [
    """
    # Welcome!

    I'm your AI assistant. Here are some things I can help with:

    - **Code review** — paste code and I'll analyze it
    - **Explanations** — ask about any concept
    - **Debugging** — describe your issue

    Try typing a message or use `/help` for commands.
    """,
    """
    That's a great question! Here's a quick example:

    ```elixir
    defmodule MyApp do
      def hello(name) do
        "Hello, \#{name}!"
      end
    end
    ```

    The `defmodule` macro defines a new module. Functions are defined with `def`.
    """,
    """
    Here are some **key concepts**:

    1. *Pattern matching* — the `=` operator matches rather than assigns
    2. *Immutability* — data structures are never modified in place
    3. *Processes* — lightweight concurrent units of execution

    > "Let it crash" — the OTP philosophy

    Would you like me to elaborate on any of these?
    """,
    """
    Sure! Let me break that down:

    - First, we need to understand the **problem space**
    - Then we can look at possible *solutions*
    - Finally, we'll pick the best approach

    The key insight is that `GenServer` gives us:
    - State management
    - Message passing
    - Fault tolerance via supervisors

    ---

    Let me know if you need more details!
    """
  ]

  def run do
    ExRatatui.run(fn terminal ->
      textarea_state = ExRatatui.textarea_new()

      state = %{
        terminal: terminal,
        textarea: textarea_state,
        messages: [
          {:ai, Enum.at(@ai_responses, 0)}
        ],
        scroll_offset: 0,
        response_index: 1,
        throbber_step: 0,
        loading: false,
        loading_timer: nil,
        show_autocomplete: false,
        autocomplete_selected: 0,
        autocomplete_matches: [],
        quit: false
      }

      loop(state)
    end)
  end

  defp loop(%{quit: true}), do: :ok

  defp loop(state) do
    render(state)

    state =
      if state.loading do
        %{state | throbber_step: state.throbber_step + 1}
      else
        state
      end

    case ExRatatui.poll_event(50) do
      nil ->
        state = maybe_finish_loading(state)
        loop(state)

      %Event.Key{code: "c", modifiers: ["ctrl"], kind: "press"} ->
        :ok

      %Event.Key{code: "q", kind: "press"} = event ->
        value = ExRatatui.textarea_get_value(state.textarea)

        if value == "" and not state.show_autocomplete do
          :ok
        else
          state = handle_key(state, event)
          loop(state)
        end

      %Event.Key{kind: "press"} = event ->
        state = handle_key(state, event)
        loop(state)

      _other ->
        loop(state)
    end
  end

  defp handle_key(state, %Event.Key{code: "escape"}) do
    if state.show_autocomplete do
      %{state | show_autocomplete: false}
    else
      state
    end
  end

  # Ctrl+S = submit message
  defp handle_key(state, %Event.Key{code: "s", modifiers: ["ctrl"]}) do
    submit_message(state)
  end

  defp handle_key(state, %Event.Key{code: "enter"}) do
    if state.show_autocomplete do
      execute_command(state)
    else
      # Enter always inserts newline (Shift/Alt+Enter not reliably detected)
      ExRatatui.textarea_handle_key(state.textarea, "enter", [])
      state
    end
  end

  defp handle_key(state, %Event.Key{code: "up"}) do
    cond do
      state.show_autocomplete ->
        new_sel = max(0, state.autocomplete_selected - 1)
        %{state | autocomplete_selected: new_sel}

      true ->
        %{state | scroll_offset: max(0, state.scroll_offset - 1)}
    end
  end

  defp handle_key(state, %Event.Key{code: "down"}) do
    cond do
      state.show_autocomplete ->
        max_sel = max(0, length(state.autocomplete_matches) - 1)
        new_sel = min(max_sel, state.autocomplete_selected + 1)
        %{state | autocomplete_selected: new_sel}

      true ->
        max_offset = max_scroll_offset(state.messages)
        %{state | scroll_offset: min(state.scroll_offset + 1, max_offset)}
    end
  end

  defp handle_key(state, %Event.Key{code: code, modifiers: mods}) do
    ExRatatui.textarea_handle_key(state.textarea, code, mods)
    check_slash_command(state)
  end

  defp check_slash_command(state) do
    value = ExRatatui.textarea_get_value(state.textarea)

    case SlashCommands.parse(value) do
      {:command, prefix} ->
        matches = SlashCommands.match_commands(@commands, prefix)

        %{
          state
          | show_autocomplete: length(matches) > 0,
            autocomplete_matches: matches,
            autocomplete_selected: 0
        }

      :no_command ->
        %{state | show_autocomplete: false, autocomplete_matches: []}
    end
  end

  defp submit_message(state) do
    value = ExRatatui.textarea_get_value(state.textarea) |> String.trim()

    if value == "" do
      state
    else
      ExRatatui.textarea_set_value(state.textarea, "")

      %{
        state
        | messages: state.messages ++ [{:user, value}],
          loading: true,
          loading_timer: System.monotonic_time(:millisecond),
          show_autocomplete: false
      }
    end
  end

  defp execute_command(state) do
    case Enum.at(state.autocomplete_matches, state.autocomplete_selected) do
      nil ->
        state

      %Command{name: "clear"} ->
        ExRatatui.textarea_set_value(state.textarea, "")
        %{state | messages: [], show_autocomplete: false, scroll_offset: 0}

      %Command{name: "quit"} ->
        ExRatatui.textarea_set_value(state.textarea, "")
        %{state | show_autocomplete: false, quit: true}

      %Command{name: "help"} ->
        ExRatatui.textarea_set_value(state.textarea, "")

        help_text = """
        # Available Commands

        | Command | Description |
        |---------|-------------|
        | `/help` | Show this help message |
        | `/clear` | Clear chat history |
        | `/model` | Switch AI model |
        | `/system` | Set system prompt |
        | `/quit` | Exit the chat |

        **Keyboard shortcuts:**
        - `Ctrl+S` — send message
        - `Enter` — new line
        - `Ctrl+C` — quit
        - `Up/Down` — scroll messages
        """

        %{
          state
          | messages: state.messages ++ [{:ai, help_text}],
            show_autocomplete: false
        }

      %Command{name: name} ->
        ExRatatui.textarea_set_value(state.textarea, "")

        %{
          state
          | messages: state.messages ++ [{:ai, "Command `/#{name}` is not implemented yet."}],
            show_autocomplete: false
        }
    end
  end

  defp maybe_finish_loading(state) do
    if state.loading do
      elapsed = System.monotonic_time(:millisecond) - state.loading_timer

      if elapsed > 1500 do
        response = Enum.at(@ai_responses, rem(state.response_index, length(@ai_responses)))
        new_messages = state.messages ++ [{:ai, response}]

        %{
          state
          | loading: false,
            loading_timer: nil,
            messages: new_messages,
            response_index: state.response_index + 1,
            scroll_offset: max_scroll_offset(new_messages)
        }
      else
        state
      end
    else
      state
    end
  end

  defp render(state) do
    {w, h} = ExRatatui.terminal_size()
    area = %Rect{x: 0, y: 0, width: w, height: h}

    # Layout: header (1) + messages (flexible) + input (5) + footer (1)
    [header_area, messages_area, input_area, footer_area] =
      Layout.split(area, :vertical, [
        {:length, 1},
        {:min, 5},
        {:length, 5},
        {:length, 1}
      ])

    widgets = []

    # Header
    header = %Paragraph{
      text: " 🤖 AI Chat Interface",
      style: %Style{fg: :cyan, modifiers: [:bold]}
    }

    widgets = [{header, header_area} | widgets]

    # Messages area (leave 1 col on right for scrollbar)
    msg_content_area = %Rect{
      x: messages_area.x,
      y: messages_area.y,
      width: messages_area.width - 1,
      height: messages_area.height
    }

    message_widgets = build_message_list(state, msg_content_area)
    widgets = [{message_widgets, msg_content_area} | widgets]

    # Scrollbar for messages
    total_lines = total_message_lines(state.messages)
    visible_height = messages_area.height - 2

    scrollbar = %Scrollbar{
      content_length: max(1, total_lines - visible_height),
      position: state.scroll_offset,
      orientation: :vertical_right,
      viewport_content_length: visible_height,
      thumb_style: %Style{fg: :cyan},
      track_style: %Style{fg: :dark_gray}
    }

    scrollbar_area = %Rect{
      x: messages_area.x + messages_area.width - 1,
      y: messages_area.y,
      width: 1,
      height: messages_area.height
    }

    widgets = [{scrollbar, scrollbar_area} | widgets]

    # Loading throbber (overlaid on messages area bottom)
    widgets =
      if state.loading do
        throbber = %Throbber{
          label: " AI is thinking...",
          step: state.throbber_step,
          throbber_set: :braille,
          style: %Style{fg: :yellow},
          throbber_style: %Style{fg: :yellow, modifiers: [:bold]}
        }

        throbber_area = %Rect{
          x: messages_area.x + 1,
          y: messages_area.y + messages_area.height - 1,
          width: min(30, messages_area.width - 2),
          height: 1
        }

        [{throbber, throbber_area} | widgets]
      else
        widgets
      end

    # Input textarea
    textarea = %Textarea{
      state: state.textarea,
      style: %Style{fg: :white},
      cursor_style: %Style{bg: :white, fg: :black},
      placeholder: "Type a message... (Ctrl+S to send, / for commands)",
      placeholder_style: %Style{fg: :dark_gray},
      block: %Block{
        title: "Message",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }

    widgets = [{textarea, input_area} | widgets]

    # Footer
    footer = %Paragraph{
      text: " Ctrl+S: send | Enter: newline | /: commands | Ctrl+C: quit",
      style: %Style{fg: :dark_gray}
    }

    widgets = [{footer, footer_area} | widgets]

    # Autocomplete popup (on top of everything)
    widgets =
      if state.show_autocomplete and length(state.autocomplete_matches) > 0 do
        popup_widgets =
          SlashCommands.render_autocomplete(state.autocomplete_matches,
            area: area,
            selected: state.autocomplete_selected,
            percent_width: 40,
            percent_height: 30,
            highlight_style: %Style{fg: :black, bg: :cyan, modifiers: [:bold]}
          )

        popup_widgets ++ widgets
      else
        widgets
      end

    ExRatatui.draw(state.terminal, Enum.reverse(widgets))
  end

  defp max_scroll_offset(messages) do
    {_w, h} = ExRatatui.terminal_size()
    # header(1) + input(5) + footer(1) = 7 fixed rows; WidgetList block border = 2
    visible_h = h - 7 - 2
    max(0, total_message_lines(messages) - visible_h)
  end

  defp total_message_lines(messages) do
    Enum.reduce(messages, 0, fn
      {:user, text}, acc ->
        # label (1) + content lines + spacer (1)
        acc + 1 + max(1, text |> String.split("\n") |> length()) + 1

      {:ai, text}, acc ->
        # label (1) + content lines + spacer (1)
        acc + 1 + max(1, text |> String.trim() |> String.split("\n") |> length()) + 1
    end)
  end

  defp build_message_list(state, _area) do
    items =
      Enum.flat_map(state.messages, fn
        {:user, text} ->
          # Role label
          label = %Paragraph{
            text: " You ",
            style: %Style{fg: :black, bg: :green, modifiers: [:bold]}
          }

          # Message content
          content = %Paragraph{
            text: text,
            style: %Style{fg: :white},
            wrap: true
          }

          lines = text |> String.split("\n") |> length()

          # Blank spacer after message
          spacer = %Paragraph{text: "", style: %Style{}}

          [{label, 1}, {content, max(1, lines)}, {spacer, 1}]

        {:ai, text} ->
          # Role label
          label = %Paragraph{
            text: " AI ",
            style: %Style{fg: :black, bg: :magenta, modifiers: [:bold]}
          }

          # Markdown content with syntax highlighting
          content = %Markdown{
            content: String.trim(text),
            wrap: true
          }

          lines = text |> String.trim() |> String.split("\n") |> length()

          # Blank spacer after message
          spacer = %Paragraph{text: "", style: %Style{}}

          [{label, 1}, {content, max(1, lines)}, {spacer, 1}]
      end)

    %WidgetList{
      items: items,
      scroll_offset: state.scroll_offset,
      block: %Block{
        title: "Chat (#{length(state.messages)} messages)",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end
end

ChatApp.run()
