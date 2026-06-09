# Example: TextInput with double-width (CJK) characters.
# Run with: EX_RATATUI_BUILD=1 mix run examples/text_input_cjk.exs
#
# Demonstrates how the TextInput viewport scrolls correctly when its value
# contains double-width characters (CJK ideographs, full-width punctuation,
# many emoji) that consume two terminal cells each.
#
# The input is pre-filled with 6 CJK chars (12 cells) inside a 12-wide box
# (10 inner cells after borders). The cursor starts at the end so it is
# already past the visible area — moving with arrow keys and Home/End shows
# the viewport tracking the cursor across mixed-width content.
#
# Controls:
#   - Right / Left       move cursor
#   - End / Home         jump to end / start
#   - Backspace          delete char before cursor
#   - q                  quit

alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph, TextInput}
alias ExRatatui.Event

defmodule TextInputCjkDemo do
  @input_width 12

  def run do
    state = ExRatatui.text_input_new()
    ExRatatui.text_input_set_value(state, "测试测试测试")

    ExRatatui.run(fn terminal ->
      loop(terminal, state)
    end)
  end

  defp loop(terminal, state) do
    {w, h} = ExRatatui.terminal_size()
    full = %Rect{x: 0, y: 0, width: w, height: h}

    outer = %Block{
      title: " Double-width TextInput Demo ",
      borders: [:all],
      border_type: :rounded,
      border_style: %Style{fg: :cyan},
      padding: {2, 2, 1, 1}
    }

    inner = inner_rect(full)

    [header_area, input_row_area, debug_area, footer_area] =
      Layout.split(inner, :vertical, [
        {:length, 6},
        {:length, 3},
        {:length, 3},
        {:min, 1}
      ])

    input_area = center_horizontally(input_row_area, @input_width)

    header = %Paragraph{
      text:
        "TextInput with double-width (CJK) characters\n" <>
          "\n" <>
          "The input below is #{@input_width} cells wide " <>
          "(#{@input_width - 2} inside the borders) and pre-filled with 6 CJK\n" <>
          "characters that take 2 cells each. Move the cursor with the arrow\n" <>
          "keys to watch the viewport scroll across mixed-width content.",
      style: %Style{fg: :white}
    }

    input = %TextInput{
      state: state,
      style: %Style{fg: :white},
      cursor_style: %Style{fg: :black, bg: :white},
      block: %Block{
        title: " width #{@input_width} ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    value = ExRatatui.text_input_get_value(state)
    cursor = ExRatatui.text_input_cursor(state)

    debug = %Paragraph{
      text: "value = #{inspect(value)}    cursor (chars) = #{cursor}",
      style: %Style{fg: :dark_gray},
      alignment: :center
    }

    footer = %Paragraph{
      text: "Left/Right = move | Home/End = jump | Backspace = delete | q = quit",
      style: %Style{fg: :dark_gray},
      alignment: :center
    }

    ExRatatui.draw(terminal, [
      {%Paragraph{text: "", block: outer}, full},
      {header, header_area},
      {input, input_area},
      {debug, debug_area},
      {footer, footer_area}
    ])

    case ExRatatui.poll_event(100) do
      %Event.Key{code: "q", kind: "press"} ->
        :ok

      %Event.Key{code: code, kind: "press"} ->
        ExRatatui.text_input_handle_key(state, code)
        loop(terminal, state)

      _ ->
        loop(terminal, state)
    end
  end

  # Account for the outer block's borders + padding (1 + 2 on each side / 1 + 1 top-bottom).
  defp inner_rect(%Rect{x: x, y: y, width: w, height: h}) do
    %Rect{x: x + 3, y: y + 2, width: max(w - 6, 0), height: max(h - 4, 0)}
  end

  defp center_horizontally(%Rect{x: x, y: y, width: w, height: h}, target_width) do
    target = min(target_width, w)
    offset = div(w - target, 2)
    %Rect{x: x + offset, y: y, width: target, height: h}
  end
end

TextInputCjkDemo.run()
