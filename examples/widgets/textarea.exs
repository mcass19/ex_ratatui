# Example: Textarea — a multi-line text editor.
# Run with: mix run examples/widgets/textarea.exs
#
# Controls: type to edit, Enter = newline, Backspace = delete,
#           Left/Right/Up/Down = move cursor, q = quit (when empty)

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph, Textarea}

defmodule TextareaDemo do
  use ExRatatui.App

  @impl true
  def mount(_opts), do: {:ok, %{textarea: ExRatatui.textarea_new()}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [editor_area, status_area, help_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 3}, {:length, 3}])

    editor = %Textarea{
      state: state.textarea,
      style: %Style{fg: :white},
      cursor_style: %Style{fg: :black, bg: :white},
      placeholder: "Type here. Enter inserts a newline...",
      placeholder_style: %Style{fg: :dark_gray},
      block: %Block{
        title: " Editor ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    {row, col} = ExRatatui.textarea_cursor(state.textarea)
    lines = ExRatatui.textarea_line_count(state.textarea)

    status = %Paragraph{
      text: "  lines: #{lines}    cursor: #{row},#{col}",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:all], border_type: :rounded, border_style: %Style{fg: :dark_gray}}
    }

    help = %Paragraph{
      text: "  Type to edit   Enter = newline   q = quit (when empty)",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    [{editor, editor_area}, {status, status_area}, {help, help_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    if ExRatatui.textarea_get_value(state.textarea) == "" do
      {:stop, state}
    else
      ExRatatui.textarea_handle_key(state.textarea, "q", [])
      {:noreply, state}
    end
  end

  def handle_event(%Event.Key{code: code, modifiers: mods, kind: "press"}, state) do
    ExRatatui.textarea_handle_key(state.textarea, code, mods)
    {:noreply, state}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = TextareaDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
