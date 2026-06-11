# Custom Transports

An ExRatatui "transport" is any module that decides **where the bytes go** for a running `ExRatatui.App`. The library ships several transports out of the box — `:local` for the host tty via `ExRatatui.run/1`, `ExRatatui.SSH.Daemon` + `ExRatatui.SSH` for serving the same App over OTP `:ssh`, `ExRatatui.Distributed.Listener` for serving the App to remote BEAM nodes, and the session-backed shapes that this guide and [Rendering to Non-Terminal Surfaces](cell_session.md) build on (the [Transports](transports.md) guide has the full matrix). If none of those fits — serving an App over a raw TCP socket, a Livebook widget, a WebSocket, whatever — plug in a custom one. This guide walks through the contract and a small TCP example.

If the consumer is **not** a terminal — a Phoenix LiveView painting `<span>` cells, a Nerves device rasterising into a framebuffer, a screenshot tool — see [Rendering to Non-Terminal Surfaces](cell_session.md). `ExRatatui.CellSession` is the ANSI-free sibling of `Session`, and the patterns in this guide (acceptor + per-connection worker, runtime-server monitoring, alt-screen lifecycle for byte streams) still apply with a cell buffer in place of the byte writer.

## The contract

`ExRatatui.Transport` is the shared behaviour. It declares one optional callback (`child_spec/1`) and — more importantly — documents the two-way protocol every transport speaks with the internal Server runtime:

```elixir
@type server_transport ::
        :local
        | {:session, ExRatatui.Session.t(), writer_fn()}
        | {:cell_session, ExRatatui.CellSession.t(), cell_writer_fn()}
        | {:cell_session, ExRatatui.CellSession.t(), cell_writer_fn(), intent_writer_fn()}
        | {:distributed_server, pid(), pos_integer(), pos_integer()}

@type to_server ::
        {:ex_ratatui_event, ExRatatui.Event.t()}
        | {:ex_ratatui_resize, pos_integer(), pos_integer()}
```

(`t:ExRatatui.Transport.server_transport/0` is the source of truth if this snippet ever drifts.)

A byte-stream transport (SSH, a TCP bridge, a Kino widget) does three things. It creates an `ExRatatui.Session` sized to the remote terminal, starts the runtime server via `ExRatatui.Transport.start_server/1` with `transport: {:session, session, writer_fn}` (the server calls `writer_fn` with the rendered ANSI bytes on every frame — job is to ship those bytes to the remote terminal), and when bytes arrive *from* the remote terminal it forwards them to the server using `ExRatatui.Transport.ByteStream.forward_input/3`. When the remote terminal resizes, it uses `forward_resize/4`.

`ByteStream` handles the parsing side (`Session.feed_input/2`), absorbs `%Event.Resize{}` events into `{:ex_ratatui_resize, _, _}` notifications, and sends everything else to the server as `{:ex_ratatui_event, event}` — exactly the shape the runtime expects. Reuse it; don't hand-roll the dispatch loop.

## A minimal TCP transport

Two responsibilities, one module: a long-lived **acceptor** that loops on `:gen_tcp.accept` and re-arms after every client, and a short-lived **connection** task per client that owns the `Session`, the runtime server, and the byte pump. Splitting them is what makes the listener survive across disconnects — fold the acceptor and connection into one GenServer and the whole thing dies the moment the first client leaves.

Beyond that, three things to get right: emit the alt-screen enter/leave sequences (the in-memory `Session` deliberately doesn't — it's the transport's job, mirroring `ExRatatui.SSH`), monitor the runtime server so the connection tears down when the app quits, and flush the leave-screen bytes *before* closing the socket so the client's terminal is restored.

```elixir
defmodule MyApp.TcpTransport do
  @moduledoc false
  use GenServer

  @behaviour ExRatatui.Transport

  alias ExRatatui.Session
  alias ExRatatui.Transport.ByteStream

  # Same canonical pair `ExRatatui.SSH` emits. Without these the TUI
  # would paint into the client's main scrollback (no alt buffer) and
  # leave the client stuck in the alt buffer with the cursor hidden
  # after disconnect.
  @enter_screen "\e[?1049h\e[?25l"
  @leave_screen "\e[?1049l\e[?25h\e[0m"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    mod  = Keyword.fetch!(opts, :mod)
    port = Keyword.get(opts, :port, 4040)

    # `reuseaddr: true` lets us re-bind the port instantly after a
    # restart instead of waiting through the OS' lingering close.
    {:ok, listener} =
      :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true])

    {:ok, %{mod: mod, listener: listener}, {:continue, :accept}}
  end

  # Accept one connection, hand it off to a per-client task, and
  # immediately re-arm the next accept. Each connection runs in its own
  # *unlinked* Task so a single client crashing or disconnecting can't
  # take the acceptor with it. For production, start each client
  # under a `DynamicSupervisor` so they're observable; for a minimal
  # example this is enough.
  @impl true
  def handle_continue(:accept, state) do
    {:ok, socket} = :gen_tcp.accept(state.listener)
    {:ok, conn}   = Task.start(fn -> run_connection(state.mod, socket) end)
    :ok = :gen_tcp.controlling_process(socket, conn)
    send(conn, :go)
    {:noreply, state, {:continue, :accept}}
  end

  ## Per-connection worker

  defp run_connection(mod, socket) do
    # Wait until the acceptor has finished the controlling-process
    # handover before we switch the socket to active mode.
    receive do
      :go -> :ok
    end

    :ok = :inet.setopts(socket, active: true)
    :ok = :gen_tcp.send(socket, @enter_screen)

    session = Session.new(80, 24)
    writer  = fn bytes -> :gen_tcp.send(socket, bytes) end

    {:ok, server} =
      ExRatatui.Transport.start_server(
        mod: mod,
        name: nil,
        transport: {:session, session, writer}
      )

    server_ref = Process.monitor(server)
    connection_loop(socket, session, server, server_ref)
  end

  defp connection_loop(socket, session, server, server_ref) do
    receive do
      {:tcp, ^socket, bytes} ->
        _ = ByteStream.forward_input(session, server, bytes)
        connection_loop(socket, session, server, server_ref)

      {:tcp_closed, ^socket} ->
        # Client disconnected. Stop the server explicitly — it owns
        # the Session and won't notice on its own until its next
        # writer_fn call fails.
        if Process.alive?(server), do: GenServer.stop(server)

      {:DOWN, ^server_ref, :process, ^server, _reason} ->
        # App quit (q pressed, terminate returned :stop, mount failed,
        # …). Flush the leave-screen bytes *now*, while the socket is
        # still writable, then close the socket so the client's
        # terminal is restored.
        _ = :gen_tcp.send(socket, @leave_screen)
        _ = :gen_tcp.close(socket)
    end
  end
end
```

Drop `{MyApp.TcpTransport, mod: MyApp.Counter, port: 4040}` into the supervision tree and any `ExRatatui.App` module now runs over TCP — concurrent clients welcome, and the listener stays up across disconnects.

### Client requirements

Plain TCP has no equivalent of SSH's PTY negotiation, so the *client* has to put its terminal in raw mode for per-keystroke delivery. The most robust option is `socat`, which handles the terminal mode itself:

```bash
socat -,raw,echo=0,escape=0x03 TCP:localhost:4040
```

`raw,echo=0` on `-` (stdin) puts the local terminal in raw mode without local echo for the duration of the connection and restores it on exit. `escape=0x03` keeps Ctrl-C as a way out if the server hangs.

`nc` works too with an `stty` wrapper, with one caveat:

```bash
stty raw -echo; nc localhost 4040; stty sane
```

Without `stty raw -echo`, the local terminal stays in cooked mode: keystrokes are buffered locally until Enter is pressed, the local terminal echoes characters before they're sent, and the TUI never sees individual key events. The trailing `stty sane` restores the shell once `nc` exits.

`nc` has a teardown quirk worth knowing about: it doesn't exit purely on remote socket close — it also waits for EOF on its stdin. So when the app quits, the TUI restores correctly but one extra keypress is needed for `nc` to notice (the keypress fails to write to the dead socket, which is what makes `nc` finally exit) before `stty sane` runs and the shell returns. If that's bothersome, use `socat`.

### Limitation: no resize support

The TCP example above hardcodes `Session.new(80, 24)` and never updates it. That's not a bug in the example — it's a structural limit of raw TCP. SSH has a dedicated channel for terminal dimensions (`pty_req` at connect for the initial size, `window_change` packets while running for SIGWINCH), and `ExRatatui.SSH` translates both into `{:ex_ratatui_resize, w, h}` messages to the runtime. Raw TCP has no equivalent — every byte on the socket is application data, and dumb clients like `nc` and `socat` ignore SIGWINCH on the local terminal because they have no protocol slot to forward it through.

For *initial* size discovery without changing the client, the SSH transport's CPR trick works over TCP too: send `\e[s\e[9999;9999H\e[6n\e[u` after the alt-screen enter, the client's terminal answers with `\e[<row>;<col>R`, the `Session`'s input parser decodes that into a `%Event.Resize{}`, and `ByteStream.forward_input/3` absorbs it into a runtime resize automatically. `ExRatatui.SSH` uses the same sequence (its `@cpr_size_query` attribute) in subsystem mode.

For *ongoing* resize a smarter client is needed — one that watches SIGWINCH and sends the new dimensions back over the socket as a framed message the transport decodes. That's a real custom-client effort (think `mosh`-style); at that point, SSH is almost always the better answer.

## Checklist for a new byte-stream transport

A few non-obvious things to get right:

- **Declare `@behaviour ExRatatui.Transport`** on the module that owns the connection (the GenServer, channel handler, whatever the framework provides).
- **Separate the acceptor from the per-connection worker.** A single process doing both serves one client at a time and dies with that client, taking the listener with it.
- **Size the `Session` to the remote terminal at connect time.** If the size isn't knowable up front, default to 80×24 and send a resize as soon as the real dimensions arrive.
- **Keep the `writer_fn` fast and non-blocking.** It's called from the server process on every render; a blocking write back-pressures the entire runtime.
- **Emit the alt-screen enter sequence (`\e[?1049h\e[?25l`) before the first frame and the leave sequence (`\e[?1049l\e[?25h\e[0m`) on teardown.** The `Session` deliberately doesn't; without them the TUI paints over the client's shell scrollback and the client is left stuck in the alt buffer after disconnect.
- **Route inbound bytes through `ByteStream.forward_input/3`**, not `Session.feed_input/2` directly — going direct skips the Resize-absorption logic. Resize signals go through `ByteStream.forward_resize/4`.
- **Monitor the runtime server pid (or trap exits).** When the app quits, flush the leave-screen sequence *while the connection is still writable*, then close the socket/channel.

## When not to use a byte-stream transport

If the transport doesn't carry raw ANSI — for example, BEAM distribution ships widget trees between nodes as Erlang terms — use the `{:distributed_server, pid, w, h}` variant instead. See `ExRatatui.Distributed.Listener` for the pattern. Byte-stream helpers don't apply there; the transport still sends `{:ex_ratatui_event, _}` and `{:ex_ratatui_resize, _, _}` messages to the Server itself, but the rendered payload crosses the network as structured widget data, not bytes.

## Telemetry

Every transport automatically participates in the runtime telemetry events — see [Telemetry](../internals/telemetry.md). `[:ex_ratatui, :transport, :connect]` and `[:ex_ratatui, :transport, :disconnect]` fire with `%{transport: :session}` for byte-stream transports (or `%{transport: :distributed_server}`), so a single handler can observe every transport uniformly without caring which concrete module is carrying the bytes.

## Related

- [Running TUIs over SSH](ssh_transport.md) — reference implementation of a byte-stream transport, backed by OTP `:ssh`.
- [Running TUIs over Erlang Distribution](distributed_transport.md) — the non-byte-stream transport.
- [Rendering to Non-Terminal Surfaces](cell_session.md) — `CellSession` for transports whose consumers don't speak ANSI (LiveView, framebuffers, screenshots).
- `ExRatatui.Transport` — behaviour, typespecs, and `start_server/1`
- `ExRatatui.Transport.ByteStream` — the two helpers used above
