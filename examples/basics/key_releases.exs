# Example: key repeat and release events (the kitty keyboard protocol).
# Run with: mix run examples/basics/key_releases.exs
#      or:  mix run --no-halt examples/basics/key_releases.exs --ssh
#           then: ssh demo@localhost -p 2222   (password: demo)
#
# Controls: hold the arrow keys to drive the pad; q = quit
#
# Started with `keyboard_enhancement: true`, a terminal that speaks the
# protocol (kitty, Ghostty, WezTerm, foot, Alacritty, iTerm2, …) sends one
# "press" when a key goes down, "repeat"s while it is held and a "release"
# when it comes up, so the pad lights exactly while an arrow is held. A
# terminal without it (GNOME Terminal, anything VTE-based, most tmux setups)
# only sends presses; the pad then treats a key as held until its presses
# stop for half a second, the usual fallback for hold-to-act input.

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, List, Paragraph}

defmodule KeyReleasesDemo do
  use ExRatatui.App

  @arrows ~w(up down left right)
  # Longer than a terminal's autorepeat delay (~500 ms), so a held key in
  # press-only mode doesn't flicker off before its first repeat.
  @press_hold_ms 600
  @tick_ms 100

  @impl true
  def mount(_opts) do
    Process.send_after(self(), :tick, @tick_ms)
    {:ok, %{held: %{}, mode: :press_only, log: []}}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [pad_area, log_area] = Layout.split(area, :horizontal, [{:length, 30}, {:min, 0}])
    [pad_box, status_area] = Layout.split(pad_area, :vertical, [{:length, 9}, {:min, 0}])

    pad = %Paragraph{
      text: pad_text(state),
      alignment: :center,
      style: %Style{fg: :white, modifiers: [:bold]},
      block: %Block{title: " drive pad ", borders: [:all], border_type: :rounded}
    }

    status = %Paragraph{
      text: status_text(state),
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:all], border_type: :rounded}
    }

    log = %List{
      items: Enum.take(state.log, max(frame.height - 2, 0)),
      block: %Block{title: " events (newest first) ", borders: [:all], border_type: :rounded}
    }

    [{pad, pad_box}, {status, status_area}, {log, log_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: kind, modifiers: mods}, state) do
    state = log(state, "#{String.pad_trailing(kind, 8)} #{inspect(code)} #{inspect(mods)}")

    state =
      cond do
        # The first release tells us the terminal reports them.
        kind == "release" -> %{state | mode: :release, held: Map.delete(state.held, code)}
        code in @arrows -> put_in(state.held[code], now())
        true -> state
      end

    {:noreply, state}
  end

  def handle_event(_event, state), do: {:noreply, state}

  # Press-only terminals never say a key came up: drop arrows whose presses
  # stopped. Releases make this a no-op.
  @impl true
  def handle_info(:tick, %{mode: :press_only} = state) do
    Process.send_after(self(), :tick, @tick_ms)
    cutoff = now() - @press_hold_ms
    held = Map.filter(state.held, fn {_key, at} -> at > cutoff end)
    {:noreply, %{state | held: held}, render?: held != state.held}
  end

  def handle_info(:tick, state), do: {:noreply, state, render?: false}

  def handle_info(_msg, state), do: {:noreply, state}

  defp pad_text(state) do
    lit = fn code, glyph -> if Map.has_key?(state.held, code), do: glyph, else: "·" end

    """

    #{lit.("up", "▲")}

    #{lit.("left", "◀")}     #{lit.("right", "▶")}

    #{lit.("down", "▼")}
    """
  end

  defp status_text(%{mode: :release}),
    do: "mode: release\nthe terminal reports\nkey releases"

  defp status_text(_state),
    do: "mode: press-only\nno release seen yet;\nkeys expire after #{@press_hold_ms} ms"

  defp log(state, line), do: %{state | log: Enum.take([line | state.log], 200)}

  defp now, do: System.monotonic_time(:millisecond)
end

case System.argv() do
  ["--ssh" | _] ->
    {:ok, _daemon} =
      ExRatatui.SSH.Daemon.start_link(
        mod: KeyReleasesDemo,
        name: nil,
        port: 2222,
        system_dir:
          ExRatatui.SSH.Daemon.ensure_host_key!(
            Path.join(System.tmp_dir!(), "ex_ratatui_example_host_keys")
          ),
        auth_methods: ~c"password",
        user_passwords: [{~c"demo", ~c"demo"}],
        app_opts: [keyboard_enhancement: true]
      )

    IO.puts("ssh demo@localhost -p 2222   (password: demo) — Ctrl-C twice stops the daemon")

  _ ->
    {:ok, pid} = KeyReleasesDemo.start_link(keyboard_enhancement: true)
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
end
