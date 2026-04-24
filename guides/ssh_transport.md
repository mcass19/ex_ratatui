# Running TUIs over SSH

ExRatatui ships with a built-in SSH transport that lets any `ExRatatui.App` module be served as a remote terminal UI. Instead of rendering into the host's physical terminal, the app renders into a per-connection in-memory terminal (a `ExRatatui.Session`) whose ANSI output is piped back to an SSH client over a single channel.

This is the mode you want when:

  * You're running on a headless box (Nerves device, container, remote host) and want to drive a TUI from your local.
  * You want multiple people to attach to the same daemon, each with their own independent session.
  * You're wrapping an existing `nerves_ssh` daemon and just want one more subsystem for your TUI.

The entire transport is pure OTP `:ssh` — no Erlang ports, no extra TCP listeners, no external `sshd`.

## The Big Picture

```
       ┌──────────┐        ┌──────────────────────────────┐
 ssh   │          │  TCP   │ :ssh.daemon                  │
 ────▶ │  client  │ ─────▶ │  └─ ExRatatui.SSH channel    │
       │          │        │       ├─ ExRatatui.Session   │
       └──────────┘        │       └─ ExRatatui.Server    │
                           │             └─ your App mod  │
                           └──────────────────────────────┘
```

One `ExRatatui.SSH.Daemon` GenServer owns a `:ssh.daemon/2` listening on a TCP port. Each new client connection spawns its own `ExRatatui.SSH` channel process, which in turn owns:

  * A `ExRatatui.Session` — an in-memory terminal sized to the client's PTY, backed by a VTE ANSI parser.
  * A linked internal server process running your `ExRatatui.App` module in `:session` transport mode — the generic byte-stream runtime the SSH channel (and any other byte-oriented transport, such as a custom TCP bridge) plugs into.

Clients are fully isolated from each other: their own state, their own key events, their own screen size. A single daemon can serve many concurrent sessions without any shared mutable state.

## Quick Start — Standalone Daemon

The simplest way to start is by adding the daemon to your supervision tree:

```elixir
children = [
  {ExRatatui.SSH.Daemon,
   mod: MyApp.TUI,
   port: 2222,
   system_dir: ~c"/etc/ex_ratatui/host_keys",
   user_passwords: [{~c"admin", ~c"s3cret"}],
   auth_methods: ~c"password"}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Then connect from another terminal:

```sh
ssh admin@localhost -p 2222
```

Or try it live with the bundled example:

```sh
mix run --no-halt examples/system_monitor.exs --ssh
# (in another terminal)
ssh demo@localhost -p 2222   # password: demo
```

The example generates a throwaway RSA host key under your system tmp dir on first run and reuses it afterward.

### App-level Shortcut

`ExRatatui.App` knows about the transport dispatch too, so if your module already uses the behaviour you can skip the explicit `SSH.Daemon` child spec:

```elixir
children = [
  {MyApp.TUI,
   transport: :ssh,
   port: 2222,
   system_dir: ~c"/etc/ex_ratatui/host_keys",
   user_passwords: [{~c"admin", ~c"s3cret"}]}
]
```

With `transport: :ssh` set, `MyApp.TUI.start_link/1` routes through `ExRatatui.SSH.Daemon` instead of the local terminal path. Omitting `:transport` (or passing `:local`) keeps the default behaviour.

## Integrating with `nerves_ssh`

If you're already running `nerves_ssh` on a Nerves device, you don't need to stand up a second daemon. `nerves_ssh` accepts a `subsystems:` option that takes OTP `:ssh_server_channel` modules, and `ExRatatui.SSH` is exactly one of those. Use the `subsystem/1` helper to build the tuple in the shape OTP wants:

```elixir
# config/runtime.exs
import Config

if Application.spec(:nerves_ssh) do
  config :nerves_ssh,
    subsystems: [
      :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
      ExRatatui.SSH.subsystem(MyApp.TUI)
    ]
end
```

> **Why `runtime.exs`, not `target.exs`?** On a fresh `MIX_TARGET=rpi4 mix compile`, Mix evaluates `config/target.exs` *before* it compiles deps for the target — so `ExRatatui.SSH` isn't on the code path yet and any function call against it crashes with `module ExRatatui.SSH is not available`. `runtime.exs` is evaluated at device boot instead, after every beam file in the release is loaded but before the OTP application controller starts `:nerves_ssh`, which is exactly the window we need. The `Application.spec(:nerves_ssh)` guard keeps host builds (where `:nerves_ssh` isn't a dep) silent. `authorized_keys` should still live in `target.exs` since it reads the developer's keys from `~/.ssh/` and bakes them into the firmware image.

The user then connects with:

```sh
ssh nerves.local -s Elixir.MyApp.TUI
```

The subsystem name is the full Elixir module name as a charlist (because that's what SSH expects), so two different app modules configured into the same daemon get distinct subsystem names and don't collide.

`subsystem/1` bakes a `subsystem: true` flag into its init args so the channel handler knows it was dispatched via OTP's `:subsystems` path. That matters because OTP `:ssh` consumes the `{:subsystem, ...}` channel request _internally_ when it matches the name — `handle_ssh_msg/2` never sees it. The only lifecycle message the handler receives is `{:ssh_channel_up, ...}`, and it uses that as its cue to synthesize a default 80x24 session and start the TUI server immediately.

Learning the client's real terminal dimensions in subsystem mode is trickier than it looks. The obvious answer — "read the dimensions off `pty_req`" — doesn't work on `nerves_ssh` (or any OTP `:ssh.daemon` that configures a default CLI handler alongside the subsystems list). When the client connects with `ssh -t -s <name>`, OTP fires `pty_req` _before_ the subsystem dispatch matches, and the OTP SSH connection CLI path sees an unbound channel user pid, which means it hands the pty_req to the daemon's default CLI handler (IEx on Nerves, for example). Moments later the `{:subsystem, ...}` request arrives, OTP rebinds the channel's user pid to us, and the original CLI handler is silently orphaned — pty_req is gone and there is no OTP message to recover it from.

To sidestep all of that, the handler emits a **Cursor Position Report roundtrip** immediately after starting the server:

```text
ESC[s               → save cursor
ESC[9999;9999H      → move cursor to (9999, 9999) — clamped to terminal size
ESC[6n              → "report your position"
ESC[u               → restore cursor
```

The client clamps the impossible position to its real `(rows, cols)` and answers with `ESC[<row>;<col>R`. That response lands on the next `{:data, ...}` channel message, the session's ANSI input parser (built on `vte`) decodes it into a `%ExRatatui.Event.Resize{}` just like any other resize event, and the SSH data handler intercepts it: resize the session in place, notify the running server via `{:ex_ratatui_resize, w, h}`. From the app's perspective it's identical to a real `window_change`, and subsequent `window_change` events during the session continue to work unchanged. The first frame may still paint briefly at 80x24 before the CPR response comes back, but on any terminal faster than a potato that window is invisible.

### Always pass `-t` in subsystem mode

OpenSSH does **not** allocate a PTY by default for subsystem invocations. `sftp` and similar binary protocols don't need one, but a TUI absolutely does — without a PTY the client's local terminal stays in cooked mode, which means keystrokes get line-buffered and locally echoed (painting garbage over the TUI) and the alt-screen teardown on disconnect bleeds into the shell prompt. Always force PTY allocation with `-t`:

```sh
# ✓ interactive — local terminal enters raw mode, keys flow to the server,
#   quitting leaves a clean shell
ssh -t nerves.local -s Elixir.MyApp.TUI

# ✗ render bytes reach you but it is not usable interactively
ssh nerves.local -s Elixir.MyApp.TUI
```

See the [`nerves_ex_ratatui_example`](https://github.com/mcass19/nerves_ex_ratatui_example) project for an end-to-end Nerves firmware that wires three TUIs (callback and reducer runtime) into a `nerves_ssh` daemon and runs them on a Raspberry Pi.

## Options Reference

`ExRatatui.SSH.Daemon` accepts:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:mod` | `module()` | **required** | The `ExRatatui.App` module to serve |
| `:port` | `integer()` | `2222` | TCP port to listen on; `0` picks a free port |
| `:name` | `atom() \| nil` | `ExRatatui.SSH.Daemon` | Registered name, or `nil` to skip |
| `:app_opts` | `keyword()` | `[]` | Extra opts merged into every client's `mount/1` call |
| `:auto_host_key` | `boolean()` | `false` | Auto-generate an RSA host key under `<priv_dir>/ssh/` (see ["Generating Host Keys"](#generating-host-keys)) |

Everything else is forwarded verbatim to `:ssh.daemon/2`, so all of OTP's `:ssh` options work unchanged:

  * `:system_dir` — host key directory
  * `:user_dir` — client key directory
  * `:authorized_keys` — authorized keys content
  * `:auth_methods` — `~c"password"`, `~c"publickey"`, `~c"publickey,password"`
  * `:user_passwords` — `[{~c"user", ~c"password"}]`
  * `:pwdfun` — custom password callback
  * `:key_cb` — custom key callback (e.g. in-memory keys)
  * `:idle_time` — auto-disconnect idle clients
  * `:max_sessions` — limit concurrent connections
  * `:profile` — multiple daemons on the same machine

See the `:ssh.daemon/2` [OTP docs](https://www.erlang.org/doc/apps/ssh/ssh.html#daemon/2) for the full list.

### Multiple Daemons

Running two or more SSH daemons in the same supervision tree requires distinct `:name` values — the default (`ExRatatui.SSH.Daemon`) is a single global atom, so a second daemon will crash with "already started". Give each daemon its own name and port:

```elixir
children = [
  {AdminTui, transport: :ssh, port: 2222},                                    # name defaults to ExRatatui.SSH.Daemon
  {StatsTui, transport: :ssh, port: 2223, name: :stats_ssh_daemon}             # explicit name avoids collision
]
```

On Nerves, prefer registering multiple TUIs as subsystems on a single `nerves_ssh` daemon instead of running separate daemons — see the ["Integration with `nerves_ssh`"](#integration-with-nerves_ssh) section.

### Why `charlist()` everywhere?

OTP's `:ssh` module is implemented in Erlang and expects Erlang strings — i.e. charlists (`~c"..."`), not Elixir binaries. Any option that holds a username, password, path, or file content needs to be a charlist. If you pass a binary by mistake you'll usually see a cryptic `:badarg` from inside `:ssh`.

As a small convenience, `:system_dir` accepts either form: pass a binary path (`"./priv/host_keys"`) and the daemon will convert it to a charlist before forwarding to `:ssh.daemon/2`. Other charlist options still need the `~c"..."` sigil.

## Authentication

OTP `:ssh` supports both password and public-key authentication. For production use, prefer public keys:

```elixir
{ExRatatui.SSH.Daemon,
 mod: MyApp.TUI,
 port: 2222,
 system_dir: ~c"/etc/ex_ratatui/host_keys",
 user_dir: ~c"/etc/ex_ratatui/users",
 auth_methods: ~c"publickey"}
```

Drop each authorized client's public key into `/etc/ex_ratatui/users/authorized_keys` (the standard OpenSSH format).

For development, a fixed password is fine:

```elixir
{ExRatatui.SSH.Daemon,
 mod: MyApp.TUI,
 port: 2222,
 system_dir: ~c"./priv/host_keys",
 auth_methods: ~c"password",
 user_passwords: [{~c"dev", ~c"dev"}]}
```

For full-custom auth (e.g. looking up users in your own DB), pass `pwdfun: &MyApp.Auth.check/4` — see the OTP [`:ssh` pwdfun docs](https://www.erlang.org/doc/apps/ssh/ssh.html#daemon/2) for the callback signature.

### Generating Host Keys

There are three reasonable strategies for managing the host key. Pick based on where you're running the daemon:

| Strategy | Best for | How |
|---|---|---|
| **Explicit `:system_dir`** | Production, multi-machine setups, anything where the host key needs to be backed up or rotated | Generate with `ssh-keygen`, mount under config management, pass `system_dir: ~c"/etc/ex_ratatui/host_keys"` |
| **`auto_host_key: true`** | Phoenix admin TUIs, internal tools, dev daemons — anywhere you don't want to babysit a directory | Daemon resolves the OTP app for `:mod`, generates a key under `<priv_dir>/ssh/` on first boot, reuses it after |
| **`nerves_ssh`-managed** | Nerves devices already running an SSH listener for IEx and firmware updates | Don't run your own daemon at all — use `ExRatatui.SSH.subsystem/1` and let `nerves_ssh` reuse its existing host key |

The rest of this section walks through each option in detail.

OTP scans `system_dir` for files named `ssh_host_rsa_key`, `ssh_host_ecdsa_key`, `ssh_host_ed25519_key`, etc. You can generate one with `ssh-keygen`:

```sh
mkdir -p priv/host_keys
ssh-keygen -t ed25519 -f priv/host_keys/ssh_host_ed25519_key -N ""
```

Or inside the BEAM at runtime (see `examples/system_monitor.exs` for a ready-to-copy snippet using `:public_key.generate_key/1`).

### `auto_host_key: true` for the lazy path

For Phoenix admin TUIs, internal tools, and development daemons where you don't want to babysit a `system_dir`, pass `auto_host_key: true` and let the daemon take care of it:

```elixir
children = [
  {ExRatatui.SSH.Daemon,
   mod: MyAppWeb.AdminTui,
   port: 2222,
   auto_host_key: true,
   auth_methods: ~c"password",
   user_passwords: [{~c"admin", ~c"admin"}]}
]
```

On first boot, the daemon:

  1. Resolves the OTP application that owns `:mod` (via `Application.get_application/1`).
  2. Creates `<priv_dir>/ssh/` if it doesn't exist.
  3. Generates a fresh 2048-bit RSA host key at `<priv_dir>/ssh/ssh_host_rsa_key` with `0600` permissions.

Subsequent boots reuse the same key, so SSH clients won't see host-key warnings between restarts. **Add `priv/ssh/` to your `.gitignore`** — the key is private to that machine and should never be committed.

Passing both `:auto_host_key` and `:system_dir` is an error. If you need an explicit host-key location (production deployments, multi-machine setups), pass `:system_dir` and manage the keys yourself.

This option exists so you can drop the daemon straight into a Phoenix or library supervision tree and have it _just work_ without hand-rolling a host-key bootstrap. It is **not** a substitute for proper key management in production — see the [`phoenix_ex_ratatui_example`](https://github.com/mcass19/phoenix_ex_ratatui_example) project for an end-to-end demo.

## Forwarding `mount/1` Opts

Anything you pass as `:app_opts` on the Daemon reaches every connected client's `mount/1` callback:

```elixir
{ExRatatui.SSH.Daemon,
 mod: MyApp.TUI,
 port: 2222,
 system_dir: ~c"/etc/ex_ratatui/host_keys",
 app_opts: [pubsub: MyApp.PubSub, feature_flags: %{beta: true}]}
```

```elixir
defmodule MyApp.TUI do
  use ExRatatui.App

  @impl true
  def mount(opts) do
    pubsub = Keyword.fetch!(opts, :pubsub)
    Phoenix.PubSub.subscribe(pubsub, "alerts")
    {:ok, %{pubsub: pubsub, flags: opts[:feature_flags]}}
  end
end
```

This is how you share infrastructure (PubSub topics, Ecto repos, feature toggles) across every SSH-attached session without globals.

## Running Multiple Transports

The same app module can be supervised under multiple transports simultaneously:

```elixir
children = [
  {MyApp.TUI, []},                                    # local TTY
  {MyApp.TUI, transport: :ssh, port: 2222, ...},      # remote over SSH
  {MyApp.TUI, transport: :distributed}                 # remote over distribution
]
```

Each transport gets its own supervisor/process tree. `mount/1`, `render/2`, `handle_event/2`, and `handle_info/2` are transport-agnostic — the only difference is the `:transport` key in `mount/1` opts (`:local`, `:session` for byte-stream transports like SSH, or `:distributed`).

## Testing

### Unit Tests

The SSH channel, daemon, and server's SSH mode are all unit-tested without standing up a real SSH daemon. Fakes replace `:ssh_connection` so the tests run with standard `mix test`:

```sh
mix test
```

### Integration Tests

Full end-to-end integration tests stand up a live `:ssh.daemon/2`, connect to it with `:ssh.connect/3`, open a real PTY session channel, and assert the full roundtrip: mount, render bytes over the channel, keyboard input back to `handle_event/2`, and clean shutdown. These tests generate a throwaway host key per test into `tmp_dir` and listen on port 0, so they run in parallel with everything else and require no host-wide SSH config.

The integration tests run as part of the default `mix test` — no special flags needed.

## Known Limitations

  * **One channel per session.** We don't support SSH port forwarding or multiple channels on a single connection. If you need that, run a second daemon instance on a different port.
  * **No X11 / agent forwarding.** The TUI doesn't need either; both are unconditionally rejected.
  * **Shell mode needs a PTY.** Clients that connect with `ssh host` (no `-T`, no subsystem) must request a PTY or the channel is closed immediately. `ssh host -T` will _not_ work; `ssh host` or `ssh host -t` will.
  * **Subsystem mode starts at 80x24 until the CPR reply comes back.** OTP consumes `pty_req` before a subsystem handler exists, so the transport discovers the client's real dimensions via a Cursor Position Report (`ESC[6n`) roundtrip on `channel_up`. The first frame paints at 80x24 until the response arrives on the next `{:data, ...}` message, which is usually invisibly fast but is not strictly instantaneous. Clients that don't answer `ESC[6n` at all (very rare — this is a half-century-old ANSI spec) stay at 80x24 until their first `window_change`.
  * **No keystroke replay.** If a client disconnects mid-session, the state is gone. There's no server-side scrollback or reattach (think `tmux`, not `screen`).

## Troubleshooting

**"Connection closed by remote host" right after banner**
: The client asked for a shell but didn't allocate a PTY. Add `-t` (`ssh -t host`) or switch to subsystem mode (`ssh -s host Elixir.MyApp.TUI`).

**Client sees garbled box-drawing characters**
: Your SSH client isn't interpreting UTF-8 or isn't in a terminal that knows about Unicode line-drawing glyphs. Set `LANG=en_US.UTF-8` on both sides.

**`:ssh_daemon_failed, :eaddrinuse`**
: Another process holds the port. Use `ss -tlnp | grep 2222` to find it, or pick a different port.

**Silent failure under `nerves_ssh`**
: `nerves_ssh` logs its subsystem errors quietly. Enable verbose SSH logging on the client (`ssh -vv ...`) to see the server's subsystem-failure reason. If you're on `ex_ratatui` `0.6.0` specifically, `ssh host -s Elixir.MyApp.TUI` hangs instead of rendering — upgrade to `0.6.1` or newer; the subsystem handler used to wait for a `{:subsystem, _}` message that OTP consumes before the handler ever sees it.

**Tests time out waiting for an initial render**
: The SSH channel triggers the initial render synchronously inside the linked Server's `init/1` (via `continue_init_ssh/3`) before any client input can arrive. If your `mount/1` does long I/O (e.g. HTTP, DB), the channel won't see render bytes until that finishes — move expensive work to `handle_info(:refresh, ...)` with a self-scheduled message so the first render doesn't block the handshake.

## Related

  * `ExRatatui.SSH` — channel module (`:ssh_server_channel` behaviour)
  * `ExRatatui.SSH.Daemon` — daemon GenServer
  * `ExRatatui.Session` — in-memory per-client terminal
  * `ExRatatui.App` — transport-aware app behaviour
  * [Callback Runtime](callback_runtime.md) — OTP-style callbacks
  * [Reducer Runtime](reducer_runtime.md) — Elm-style commands and subscriptions
  * [Building UIs](building_uis.md) — widgets, layout, styles, and events
  * [Running TUIs over Erlang Distribution](distributed_transport.md) — alternative remote transport
