# Custom Transports

An ExRatatui "transport" is any module that decides **where the bytes go** for a running `ExRatatui.App`. The library ships three built-in transports — `:local` for the host tty via `ExRatatui.run/1`, `ExRatatui.SSH.Daemon` + `ExRatatui.SSH` for serving the same App over OTP `:ssh`, and `ExRatatui.Distributed.Listener` for serving the App to remote BEAM nodes. If none of those fits — you want to serve an App over a raw TCP socket, a Livebook widget, a WebSocket, whatever — you can plug in your own. This guide walks through the contract and a small TCP example.

## The contract

`ExRatatui.Transport` is the shared behaviour. It declares one optional callback (`child_spec/1`) and — more importantly — documents the two-way protocol every transport speaks with the internal Server runtime:

```elixir
@type server_transport ::
        :local
        | {:session, ExRatatui.Session.t(), (iodata() -> :ok)}
        | {:distributed_server, pid(), pos_integer(), pos_integer()}

@type to_server ::
        {:ex_ratatui_event, ExRatatui.Event.t()}
        | {:ex_ratatui_resize, pos_integer(), pos_integer()}
```

A byte-stream transport (SSH, a TCP bridge, a Kino widget) does three things. It creates an `ExRatatui.Session` sized to the remote terminal, starts the runtime server via `ExRatatui.Transport.start_server/1` with `transport: {:session, session, writer_fn}` (the server calls `writer_fn` with the rendered ANSI bytes on every frame — job is to ship those bytes to the remote terminal), and when bytes arrive *from* the remote terminal it forwards them to the server using `ExRatatui.Transport.ByteStream.forward_input/3`. When the remote terminal resizes, it uses `forward_resize/4`.

`ByteStream` handles the parsing side (`Session.feed_input/2`), absorbs `%Event.Resize{}` events into `{:ex_ratatui_resize, _, _}` notifications, and sends everything else to the server as `{:ex_ratatui_event, event}` — exactly the shape the runtime expects. Reuse it; don't hand-roll the dispatch loop.

## A minimal TCP transport

Listen on a TCP port, on every connection spawn a `Session`, start a `Server` pointed at it, and pump bytes in both directions:

```elixir
defmodule MyApp.TcpTransport do
  @moduledoc false
  use GenServer

  @behaviour ExRatatui.Transport

  alias ExRatatui.Session
  alias ExRatatui.Transport.ByteStream

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    mod  = Keyword.fetch!(opts, :mod)
    port = Keyword.get(opts, :port, 4040)
    {:ok, listener} = :gen_tcp.listen(port, [:binary, active: true])
    {:ok, %{mod: mod, listener: listener}, {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, state) do
    {:ok, socket} = :gen_tcp.accept(state.listener)
    session = Session.new(80, 24)
    writer  = fn bytes -> :gen_tcp.send(socket, bytes) end

    {:ok, server} =
      ExRatatui.Transport.start_server(
        mod: state.mod,
        name: nil,
        transport: {:session, session, writer}
      )

    {:noreply, Map.merge(state, %{socket: socket, session: session, server: server})}
  end

  @impl true
  def handle_info({:tcp, socket, bytes}, %{socket: socket} = state) do
    _events = ByteStream.forward_input(state.session, state.server, bytes)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    {:stop, :normal, state}
  end
end
```

Drop `{MyApp.TcpTransport, mod: MyApp.Counter, port: 4040}` into your supervision tree and any `ExRatatui.App` module now runs over TCP. Connect with `nc localhost 4040` (or a real speaking client) and you'll see the TUI. Keys you type are parsed by the Session's VTE frontend and delivered to `handle_event/2` as `%Event.Key{}` values.

## Checklist for a new byte-stream transport

A few non-obvious things to get right. Declare `@behaviour ExRatatui.Transport` on the module that owns the connection (the GenServer, channel handler, whatever your framework gives you). Size the `Session` to the remote terminal at connect time — if you can't know the size up front, pick a default (80×24) and send a resize as soon as you learn the real dimensions. The `writer_fn` you hand to the runtime server must be fast and non-blocking; it's called from the server process on every render, and a blocking write back-pressures the entire runtime. Route inbound bytes through `ByteStream.forward_input/3` rather than calling `Session.feed_input/2` yourself — you'll miss the Resize-absorption logic. Route inbound resize signals through `ByteStream.forward_resize/4`. On disconnect, stop the server (so it tears down cleanly) and close the Session.

## When NOT to use a byte-stream transport

If your transport doesn't carry raw ANSI — for example, BEAM distribution ships widget trees between nodes as Erlang terms — use the `{:distributed_server, pid, w, h}` variant instead. See `ExRatatui.Distributed.Listener` for the pattern. Byte-stream helpers don't apply there; you still send `{:ex_ratatui_event, _}` and `{:ex_ratatui_resize, _, _}` messages to the Server yourself, but the rendered payload crosses the network as structured widget data, not bytes.

## Telemetry

Every transport automatically participates in the runtime telemetry events — see [Telemetry](telemetry.md). `[:ex_ratatui, :transport, :connect]` and `[:ex_ratatui, :transport, :disconnect]` fire with `%{transport: :session}` for byte-stream transports (or `%{transport: :distributed_server}`), so a single handler can observe every transport uniformly without caring which concrete module is carrying the bytes.

## Related

- [Running TUIs over SSH](ssh_transport.md) — reference implementation of a byte-stream transport, backed by OTP `:ssh`.
- [Running TUIs over Erlang Distribution](distributed_transport.md) — the non-byte-stream transport.
- `ExRatatui.Transport` — behaviour, typespecs, and `start_server/1`
- `ExRatatui.Transport.ByteStream` — the two helpers used above
