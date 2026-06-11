# Paste and clipboard

ExRatatui ships **bracketed paste** out of the box on the local terminal and exposes batch-insert helpers on `TextInput` and `Textarea` so pasted content lands intact in one call. **Clipboard copy** is not built in — apps that need it emit OSC 52 themselves with a few lines of code. This guide covers both.

## Bracketed paste

When `ExRatatui.run/1` opens the terminal, it asks for bracketed paste with crossterm's `EnableBracketedPaste`. Terminals that support it (every modern emulator) wrap pasted content with `ESC[200~ ... ESC[201~` markers; ExRatatui decodes those into a single `%ExRatatui.Event.Paste{content: binary}` instead of dispatching one `%Event.Key{}` per character. Terminals that don't support it ignore the request and the per-char keystream still arrives — no conditional path is needed in the app.

Consume Paste events the same way as any other event:

```elixir
case ExRatatui.poll_event(timeout) do
  %ExRatatui.Event.Paste{content: text} ->
    ExRatatui.textarea_insert_str(state.editor, text)
    state

  %ExRatatui.Event.Key{code: "q"} ->
    :quit

  _ ->
    state
end
```

### Inserting into widgets

Two helpers consume `Event.Paste` content in one call:

  * `ExRatatui.text_input_insert_str/2` — single-line. Strips every control character (newlines, tabs, carriage returns) before inserting at the cursor. Useful for inputs that must never grow beyond one line.
  * `ExRatatui.textarea_insert_str/2` — multi-line. Treats `\n` and `\r\n` as real line breaks; lone `\r` is dropped. Other characters land verbatim at the cursor.

Both batch the insert as a single state mutation, so pasting a 5,000-character URL is one NIF call rather than 5,000.

### Transports other than the local terminal

The local terminal path (`ExRatatui.run/1`, `ExRatatui.poll_event/1`) decodes Paste events automatically. The byte-stream transports (Session, SSH, distributed) run their own VTE input parser; that parser does **not** decode `CSI 200~ / CSI 201~` markers yet, so Paste events do not arrive over SSH today. Apps using those transports can still construct `%ExRatatui.Event.Paste{content: text}` directly and feed it into the event pipeline — the widget-side contract (`insert_str` helpers) is transport-agnostic.

## Clipboard copy via OSC 52

ExRatatui doesn't bundle a clipboard module, too many opinions and options. OSC 52 is the simplest path that works over both local terminals and SSH because the bytes traverse the same channel as the renderer's output. The entire implementation is short enough to drop into any app:

```elixir
defmodule MyApp.Clipboard do
  @moduledoc """
  Copies text to the terminal's clipboard via OSC 52.

  Works on any terminal that honours OSC 52 (alacritty, kitty, wezterm,
  iTerm2, foot, recent xterm), including over SSH. Terminals that don't
  support it ignore the sequence.
  """

  @doc "Returns the raw OSC 52 escape bytes for the given content."
  @spec osc52(binary()) :: binary()
  def osc52(content) when is_binary(content) do
    "\e]52;c;" <> Base.encode64(content) <> "\a"
  end

  @doc "Writes the OSC 52 sequence to stdout (local terminal path)."
  @spec copy_local(binary()) :: :ok
  def copy_local(content), do: IO.write(osc52(content))
end
```

For Session/SSH/distributed transports, write the same bytes into the writer function the transport was started with — the renderer's own output stream is the right channel.

Receiving (paste) is the inverse: bracketed paste already covers it when supported. Reading **from** the system clipboard via terminal escape sequences requires the rarely-supported OSC 52 read query — not worth the effort versus letting the terminal's own Ctrl+Shift+V / Cmd+V trigger a paste event.
