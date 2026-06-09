# Running TUIs over Erlang Distribution

ExRatatui ships with a distribution-attach transport that lets any `ExRatatui.App` module be driven from a remote BEAM node over Erlang distribution. The app node runs all the callbacks (`mount/render/handle_event/handle_info`) and sends widget lists as plain BEAM terms; the attaching node renders them on its own terminal and forwards input events back.

This is the mode you want when:

  * You're running on a BEAM node that has no terminal (Nerves, a container, a release running as a daemon) and want to drive a TUI from your local.
  * You already have Erlang distribution set up (cookies, `epmd`, `--sname`) and don't want to manage SSH keys or ports.
  * You want zero Rust NIF involvement on the app node — widget structs travel as BEAM terms and the client renders them with its own local NIF.

## The Big Picture

```
       ┌──────────────┐                  ┌────────────────────────────┐
       │  local node  │   Erlang dist    │  app node                  │
       │              │ ◀═══════════════▶│                            │
       │  Client      │  {:ex_ratatui_   │  Listener                  │
       │  ├─ terminal │   draw, widgets} │   └─ DynamicSupervisor     │
       │  └─ poll     │                  │       └─ Server            │
       │     events   │ {:ex_ratatui_    │           └─ your App mod  │
       │              │  event, event}   │                            │
       └──────────────┘                  └────────────────────────────┘
```

The app node runs a `Distributed.Listener` supervisor with a `DynamicSupervisor` child. Each call to `attach/2` spawns a `Server` in `:distributed_server` mode under that supervisor — this process runs your app module's callbacks and sends `{:ex_ratatui_draw, widgets}` messages over distribution.

On the attaching node, a `Distributed.Client` process takes over the local terminal, polls input events, and forwards them to the remote server as `{:ex_ratatui_event, event}` or `{:ex_ratatui_resize, w, h}`.

When either side disconnects, process monitors fire, both processes clean up, and the terminal is restored.

## Quick Start

### 1. Add the Listener on the app node

```elixir
# In your supervision tree
children = [
  {MyApp.TUI, transport: :distributed}
]
```

Or with explicit Listener control:

```elixir
children = [
  {ExRatatui.Distributed.Listener, mod: MyApp.TUI}
]
```

### 2. Start the app node

```sh
iex --sname app --cookie mycookie -S mix
```

### 3. Attach from your local

```sh
iex --sname mynode --cookie mycookie -S mix
```

```elixir
iex> ExRatatui.Distributed.attach(:"app@hostname", MyApp.TUI)
```

The TUI takes over your terminal. Press the app's quit key (or Ctrl-C twice) to disconnect and restore the terminal.

### Try It with the System Monitor Example

```sh
# Terminal 1 — start the app node
elixir --sname app --cookie demo -S mix run --no-halt examples/apps/system_monitor.exs --distributed

# Terminal 2 — attach from another node
iex --sname mynode --cookie demo -S mix
iex> ExRatatui.Distributed.attach(:"app@hostname", SystemMonitor)
```

## How It Works

1. `attach/2` calls `Node.connect/1` to reach the app node (if not already connected).
2. An RPC call spawns a `Server` in `:distributed_server` mode on the app node. This process runs your app module and sends `{:ex_ratatui_draw, widgets}` messages over distribution.
3. A local `Distributed.Client` process takes over the node's terminal, polls input events, and forwards them to the remote server.
4. When either side disconnects, monitors fire, both processes clean up, and the terminal is restored.

### Wire Protocol

| Direction | Message | Purpose |
|-----------|---------|---------|
| Server -> Client | `{:ex_ratatui_draw, widgets}` | Widget list after each render |
| Client -> Server | `{:ex_ratatui_event, event}` | Key/mouse events |
| Client -> Server | `{:ex_ratatui_resize, w, h}` | Terminal resize |

All messages are plain BEAM terms sent via `send/2` — no encoding, no NIF, no serialization overhead.

### Stateful Widget Handling

Most widgets (Paragraph, Table, List, etc.) are pure Elixir structs that serialize naturally over Erlang distribution. However, **stateful widgets** — `TextInput` and `Textarea` — store their mutable state (text value, cursor position, viewport offset) in a NIF resource reference, a pointer into Rust memory on the local node. NIF references cannot cross BEAM node boundaries.

The distributed server handles this transparently: before sending a widget list, it snapshots each stateful widget's NIF state into a plain tuple (`{value, cursor, viewport_offset}` for TextInput, `{value, cursor_row, cursor_col}` for Textarea) and replaces the reference in the struct. On the client node, the Rust decoder recognizes the snapshot form and reconstructs a temporary resource for rendering. This happens automatically — app code doesn't need to do anything special.

### No NIF on the App Node (for stateless widgets)

For apps that only use stateless widgets (Paragraph, Table, List, etc.), the app node never loads the Rust NIF — widget structs are standard Elixir terms that serialize directly. When using stateful widgets (TextInput, Textarea), the app node does load the NIF to manage their mutable state, but the rendering NIF is still only loaded on the client side. This makes the app node lightweight — ideal for constrained environments like Nerves devices.

## Options

### `ExRatatui.Distributed.Listener`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:mod` | `module()` | **required** | The `ExRatatui.App` module to serve |
| `:name` | `atom() \| nil` | `ExRatatui.Distributed.Listener` | Registered name, or `nil` to skip |
| `:app_opts` | `keyword()` | `[]` | Extra opts merged into every client's `mount/1` call |

Running multiple Listeners in the same supervision tree requires distinct `:name` values — the default (`ExRatatui.Distributed.Listener`) would collide on the second instance. Pass the matching name as the `:listener` option when attaching:

```elixir
children = [
  {ExRatatui.Distributed.Listener, mod: AdminTui},                                      # default name
  {ExRatatui.Distributed.Listener, mod: StatsTui, name: :stats_dist}                     # explicit name
]

# Attaching clients must match the listener name:
ExRatatui.Distributed.attach(:"app@host", StatsTui, listener: :stats_dist)
```

### `ExRatatui.Distributed.attach/3`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:listener` | `atom()` | `ExRatatui.Distributed.Listener` | Registered name of the Listener on the remote node |
| `:poll_interval` | `integer()` | `16` | Local event polling interval in ms (~60fps) |
| `:test_mode` | `{w, h}` | `nil` | Headless test terminal dimensions; disables live local input polling |

## Forwarding `mount/1` Opts

Anything you pass as `:app_opts` on the Listener reaches every attached client's `mount/1` callback:

```elixir
children = [
  {ExRatatui.Distributed.Listener,
   mod: MyApp.TUI,
   app_opts: [pubsub: MyApp.PubSub, node_role: :primary]}
]
```

```elixir
defmodule MyApp.TUI do
  use ExRatatui.App

  @impl true
  def mount(opts) do
    pubsub = Keyword.fetch!(opts, :pubsub)
    Phoenix.PubSub.subscribe(pubsub, "alerts")
    {:ok, %{pubsub: pubsub, role: opts[:node_role]}}
  end
end
```

The `mount/1` opts also include `:transport` (set to `:distributed`), `:width`, and `:height`. Byte-stream transports like SSH set `:transport` to `:session` instead — your app module stays transport-agnostic either way.

## Authentication

Authentication is delegated entirely to the Erlang distribution cookie. If you can `Node.connect/1`, you can attach — the same trust model as `iex --remsh`. For production deployments, secure your cookie and consider TLS distribution:

```elixir
# vm.args or rel/env.sh.eex
-proto_dist inet_tls
-ssl_dist_optfile /etc/my_app/ssl_dist.conf
```

See the Erlang [SSL Distribution](https://www.erlang.org/doc/apps/ssl/ssl_distribution.html) docs for the full configuration.

## Running Multiple Transports

The same app module can be supervised under multiple transports simultaneously:

```elixir
children = [
  {MyApp.TUI, []},                                    # local TTY
  {MyApp.TUI, transport: :ssh, port: 2222, ...},      # remote over SSH
  {MyApp.TUI, transport: :distributed}                 # remote over distribution
]
```

Each transport gets its own supervisor/process tree. `mount/1`, `render/2`, `handle_event/2`, and `handle_info/2` are transport-agnostic — the only difference is the `:transport` key in `mount/1` opts.

## Testing

### Unit Tests (no distribution required)

The Listener, Client, and Server's distributed mode are all unit-tested without requiring distributed nodes. These tests run with standard `mix test`:

```sh
mix test
```

### Integration Tests (requires distribution)

Full cross-node integration tests use OTP's `:peer` module to spawn peer BEAM nodes. These are tagged `:distributed` and excluded from the default test run:

```sh
# Run integration tests
elixir --sname test -S mix test --only distributed

# Run everything (unit + integration)
elixir --sname test -S mix test --include distributed
```

The integration tests exercise the full roundtrip: mount on a peer node, render, draw over distribution, forward events, resize, quit, and cleanup.

## Known Limitations

  * **No incremental updates.** Every render sends the complete widget list. For complex UIs with many widgets, this is more data than the SSH transport (which sends only changed terminal cells). In practice, BEAM term serialization is fast and this is rarely a bottleneck over a local network.
  * **No reconnect.** If the connection drops, the session is gone. There's no server-side state preservation or reattach (like the SSH transport, this is `tmux`-style, not `screen`-style).
  * **Cookie-only auth.** There's no per-user authentication layer — anyone who can `Node.connect/1` can attach. If you need user-level access control, use the SSH transport instead.
  * **Single-node rendering.** The Client must have the ExRatatui NIF loaded to render widgets. Cross-architecture distribution (e.g. x86 pc attaching to an ARM Nerves device) works because only the client node needs the NIF compiled for its architecture.

## Troubleshooting

**"distribution_not_started"**
: The attaching node isn't distributed. Start it with `--sname` or `--name`: `iex --sname mynode -S mix`.

**"connect_failed"**
: `Node.connect/1` returned `false`. Check that:
  - Both nodes use the same cookie (`--cookie` or `~/.erlang.cookie`)
  - `epmd` is running on both machines (`epmd -names` to check)
  - The hostname in the node name resolves correctly
  - No firewall blocks the epmd port (4369) or the distribution port range

**"cannot_attach_to_self"**
: You called `attach/2` with `Node.self()`. The distribution transport is for remote nodes — for same-node TUIs, start the app directly with `{MyApp.TUI, []}`.

**"rpc_failed"**
: The RPC to start a session on the remote node failed. Check that:
  - The app node is running and the Listener is started
  - The module name matches what's registered on the app node
  - The Listener's registered name matches the `:listener` option (default: `ExRatatui.Distributed.Listener`)

**Widgets render differently on client vs server**
: The client renders with its own NIF, which must be the same ExRatatui version as the server. Mismatched versions may produce different widget struct shapes.

## Examples

  * [`phoenix_ex_ratatui_example`](https://github.com/mcass19/phoenix_ex_ratatui_example) — Phoenix app with two TUIs (callback and reducer runtime) attached over distribution from any named BEAM node on the network
  * [`nerves_ex_ratatui_example`](https://github.com/mcass19/nerves_ex_ratatui_example) — Nerves firmware with three TUIs attached over distribution from a dev machine to a Raspberry Pi

## Related

  * `ExRatatui.Distributed` — main API module with `attach/3`
  * `ExRatatui.Distributed.Listener` — supervisor for per-attach sessions
  * `Distributed.Client` — local rendering proxy (internal, not public API)
  * `ExRatatui.App` — transport-aware app behaviour
  * [Callback Runtime](callback_runtime.md) — OTP-style callbacks
  * [Reducer Runtime](reducer_runtime.md) — Elm-style commands and subscriptions
  * [Building UIs](building_uis.md) — widgets, layout, styles, and events
  * [Running TUIs over SSH](ssh_transport.md) — alternative remote transport
  * [Custom Transports](custom_transports.md) — write your own transport on top of `ExRatatui.Transport`
