# Example: a TUI opened from an IEx session over SSH.
# Run with: mix run --no-halt examples/basics/iex_over_ssh.exs
#     then: ssh demo@localhost -p 2223   (password: demo)
#     and, at the remote iex> prompt:
#           ExRatatui.IODevice.run(ShellDemo)
#
# Controls: any key shows up in the window; q = back to the IEx prompt
#
# The daemon here gives each client an IEx shell, the way `nerves_ssh`
# does on a Nerves device. An app started from that shell with
# `start_link/1` would run on the `:local` transport and draw on this
# node's own terminal, not in the SSH session. `ExRatatui.IODevice.run/2`
# draws through the shell's I/O device instead, so the TUI appears in the
# SSH client, and quitting hands the prompt back. `ShellDemo` also shows
# what `ExRatatui.IODevice.io_device?/0` says from the calling shell.

alias ExRatatui.Event
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph}

defmodule ShellDemo do
  use ExRatatui.App

  @impl true
  def mount(_opts) do
    # The app runs under the caller's group leader, so this asks the SSH
    # session's I/O device: true here, false from a local `iex`.
    {:ok, %{last_key: nil, io_device?: ExRatatui.IODevice.io_device?()}}
  end

  @impl true
  def render(state, frame) do
    text = """

    Drawn through the IEx session's I/O device.

    size:      #{frame.width} × #{frame.height}  (resize the window: it follows within 250 ms)
    last key:  #{inspect(state.last_key)}
    io_device?: #{state.io_device?}

    q hands the iex> prompt back.
    """

    widget = %Paragraph{
      text: text,
      style: %Style{fg: :white},
      block: %Block{
        title: " ExRatatui.IODevice ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    [{widget, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, modifiers: mods}, state),
    do: {:noreply, %{state | last_key: {code, mods}}}

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, _} = Application.ensure_all_started([:ssh, :iex])

host_keys =
  ExRatatui.SSH.Daemon.ensure_host_key!(
    Path.join(System.tmp_dir!(), "ex_ratatui_example_host_keys")
  )

{:ok, _daemon} =
  :ssh.daemon(2223,
    system_dir: host_keys,
    auth_methods: ~c"password",
    user_passwords: [{~c"demo", ~c"demo"}],
    # The same shell `nerves_ssh` starts on Elixir 1.15+.
    shell: {:iex, :start, [[], {:elixir_utils, :noop, []}]}
  )

IO.puts("""
ssh demo@localhost -p 2223   (password: demo)
then at the remote iex> prompt:  ExRatatui.IODevice.run(ShellDemo)
Ctrl-C twice stops the daemon.
""")
