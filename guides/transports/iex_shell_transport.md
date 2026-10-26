# Running TUIs in a Remote IEx Shell

`ExRatatui.IODevice` runs an app on the I/O device of the shell it was called from, so a TUI opened from an IEx session over SSH, or from an `iex --remsh` attached from another machine, draws on the screen in front of us.

## Why the local transport isn't enough

The `:local` transport drives the terminal the BEAM itself was started on, through crossterm. On a laptop that is the terminal running `iex`, and everything lines up. On a Nerves device it is the device's console (a serial port or HDMI), and an IEx session reached over `nerves_ssh` is a different terminal altogether: its input and output travel through the shell's group leader and the SSH channel. Starting a `:local` app from there takes over the console nobody is looking at, while the SSH session just waits.

`iex --remsh` has the same shape: the shell runs on the remote node, its group leader lives on the node we typed `iex` on, and the remote node's own terminal is somewhere else.

The SSH subsystem (`ExRatatui.SSH.subsystem/1`, `ssh -t host -s Elixir.MyApp.TUI`) avoids the problem by never going through IEx. This transport is for when we are already in the shell and want a TUI there, without disconnecting and reconnecting to a subsystem.

## Usage

```elixir
iex> ExRatatui.IODevice.run(MyApp.TUI)
```

`run/2` blocks until the app stops, then hands the shell back with its echo and binary options restored. It takes the same options as the app's `start_link/1` (minus `:transport` and `:name`); anything else reaches `mount/1` as usual:

```elixir
ExRatatui.IODevice.run(MyApp.TUI, robot: MyRobot, keyboard_enhancement: true)
```

The return value is `:ok` when the app stops, or `{:error, reason}` when it couldn't start or crashed.

## Picking the transport automatically

`ExRatatui.IODevice.io_device?/1` asks the shell's group leader for its terminal driver and compares it with this node's own (`:user_drv`). It is `true` in an SSH shell and under `iex --remsh`, `false` in a plain `iex` on the machine's own terminal. An IEx helper can then pick the right transport for wherever it is called from:

```elixir
def tui do
  if ExRatatui.IODevice.io_device?() do
    ExRatatui.IODevice.run(MyApp.TUI)
  else
    {:ok, pid} = MyApp.TUI.start_link(name: nil)
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
  end
end
```

The local branch starts the app on the `:local` transport and waits for it to exit.

## How it works

Under the hood this is the same byte-stream path as the SSH transport. An `ExRatatui.Session` renders each frame to ANSI bytes, which go to the group leader as `put_chars` requests. Input is read one character at a time with `get_chars`, echo off, and fed to the session's input parser, so keys, mouse reports and key releases decode exactly as they do over SSH. A lone `Esc` is told apart from the start of an escape sequence by a 50 ms timeout.

The Erlang I/O protocol has no resize notification, so the device's columns and rows are polled every 250 ms and a change arrives as an `ExRatatui.Event.Resize` like on any other transport. The poll is asynchronous: a slow shell never holds up reading keys.

## Key releases

`keyboard_enhancement: true` asks the terminal for the kitty keyboard protocol, as on the other transports: pushed once inside the alternate screen, popped before leaving it. Over a shell there is no way to check whether the terminal took it, so `ExRatatui.Runtime.snapshot/1` reports `nil`; the first `"release"` an app sees is the signal. See [Key releases](../core/building_uis.md#key-releases).

## Limits

- Images render as `:halfblocks`; the transport has no `:image_protocol` option yet.
- Resizes land up to 250 ms late.
- Bracketed paste and focus events aren't decoded, the same gap as the SSH transport (see the [Transports](transports.md) matrix).
- The shell is blocked while the app runs: `run/2` is meant for an interactive session, not for supervising long-lived apps. Use the [SSH transport](ssh_transport.md) for that.

## Related

- [Running TUIs over SSH](ssh_transport.md) — the subsystem and daemon routes
- [Running TUIs over Erlang Distribution](distributed_transport.md) — rendering on our own node instead
- [Transports](transports.md) — the feature matrix
