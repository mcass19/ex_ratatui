# Echo Chat — minimal input-fidelity example
#
# Type a line, press Enter, and it is echoed back into the transcript.
# Deliberately tiny: a plain string buffer fed one keystroke at a time, so
# every character has to land for the line to read correctly. That makes it
# a good stress test for fast/sustained typing — the case where a competing
# terminal reader would otherwise swallow bytes (see the Debugging guide,
# "Dropped keystrokes or missing characters").
#
# On the :local transport ExRatatui parks the BEAM's own terminal reader for
# the duration of the run (ExRatatui.LocalInput), so this stays lossless even
# when launched the quick ways:
#
#   mix run examples/basics/echo_chat.exs
#   elixir examples/basics/echo_chat.exs      # standalone, if deps are available
#   iex -S mix    then    EchoChat.run()      # parked shell reader, no drops
#
# Controls:
#   <printable>  — append to the input line
#   Backspace    — delete the last character
#   Enter        — send the line into the transcript
#   Ctrl+C       — quit

alias ExRatatui.{Layout, Style}
alias ExRatatui.Layout.Rect
alias ExRatatui.Event
alias ExRatatui.Widgets.{Block, Paragraph}

defmodule EchoChat do
  @max_lines 200

  def run do
    ExRatatui.run(fn terminal ->
      loop(%{terminal: terminal, input: "", lines: []})
    end)
  end

  defp loop(state) do
    render(state)

    case ExRatatui.poll_event(100) do
      %Event.Key{code: "c", modifiers: ["ctrl"], kind: "press"} ->
        :ok

      %Event.Key{kind: "press"} = event ->
        loop(handle_key(state, event))

      _other ->
        loop(state)
    end
  end

  defp handle_key(state, %Event.Key{code: "enter"}), do: send_line(state)

  defp handle_key(%{input: ""} = state, %Event.Key{code: "backspace"}), do: state

  defp handle_key(state, %Event.Key{code: "backspace"}) do
    %{state | input: String.slice(state.input, 0..-2//1)}
  end

  # A printable key: a single grapheme with no control/alt chord. crossterm
  # hands back the literal character (including its case), so we just append.
  defp handle_key(state, %Event.Key{code: code, modifiers: mods}) do
    if String.length(code) == 1 and "ctrl" not in mods and "alt" not in mods do
      %{state | input: state.input <> code}
    else
      state
    end
  end

  defp send_line(%{input: ""} = state), do: state

  defp send_line(state) do
    lines = Enum.take([state.input | state.lines], @max_lines)
    %{state | input: "", lines: lines}
  end

  defp render(state) do
    {w, h} = ExRatatui.terminal_size()
    area = %Rect{x: 0, y: 0, width: w, height: h}

    [header_area, transcript_area, input_area, footer_area] =
      Layout.split(area, :vertical, [
        {:length, 1},
        {:min, 3},
        {:length, 3},
        {:length, 1}
      ])

    header = %Paragraph{
      text: " echo chat — type a line and press Enter",
      style: %Style{fg: :cyan, modifiers: [:bold]}
    }

    # Newest line at the bottom, oldest scrolled off the top.
    transcript_height = max(1, transcript_area.height - 2)

    transcript_text =
      state.lines
      |> Enum.take(transcript_height)
      |> Enum.reverse()
      |> Enum.join("\n")

    transcript = %Paragraph{
      text: transcript_text,
      style: %Style{fg: :white},
      block: %Block{title: "transcript", borders: [:all], border_type: :rounded}
    }

    input = %Paragraph{
      # ▏ is a thin block cursor so the caret position is visible.
      text: state.input <> "▏",
      style: %Style{fg: :green},
      block: %Block{
        title: "type",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :blue}
      }
    }

    footer = %Paragraph{
      text: " Enter: send | Backspace: delete | Ctrl+C: quit",
      style: %Style{fg: :dark_gray}
    }

    ExRatatui.draw(state.terminal, [
      {header, header_area},
      {transcript, transcript_area},
      {input, input_area},
      {footer, footer_area}
    ])
  end
end

EchoChat.run()
