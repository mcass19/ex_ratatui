defmodule ExRatatui.Transport do
  @moduledoc """
  Shared protocol between the internal Server runtime and the modules
  that carry input/output bytes for a running `ExRatatui.App`.

  ex_ratatui ships three transports:

    * `ExRatatui.SSH` + `ExRatatui.SSH.Daemon` — serve apps over SSH.
    * `ExRatatui.Distributed.Listener` — serve apps to remote BEAM nodes
      using distribution instead of raw bytes.
    * The built-in `:local` transport — runs against the host tty via
      `ExRatatui.run/1`.

  Downstream packages (`kino_ex_ratatui`, custom TCP bridges, …) plug in
  by adopting `@behaviour ExRatatui.Transport` and speaking the same
  two-way protocol documented below. See
  [`guides/custom_transports.md`](guides/custom_transports.md) for a
  ~60-line TCP walkthrough.

  ## Wire protocol

  A transport is any process that:

    1. Decides *how* the runtime is wired up by passing one of the
       `t:server_transport/0` shapes as the `:transport` option when
       starting the internal Server.
    2. Forwards user input and resize notifications to that Server via
       the `t:to_server/0` mailbox messages.
    3. For byte-stream transports only: receives rendered ANSI bytes
       through the `t:writer_fn/0` it handed to the Server at init
       time and ships them to the remote terminal.

  `ExRatatui.Transport.ByteStream` packages the input/resize half of
  step 2 for transports that carry raw terminal bytes (SSH, xterm.js in
  Livebook, a custom TCP socket). Distributed does not use ByteStream —
  it ships widget trees, not bytes — but still declares the behaviour
  as a marker.

  ## Callbacks

  `c:child_spec/1` is declared as an optional callback: modules that
  are started as children of a supervision tree (`SSH.Daemon`,
  `Distributed.Listener`) satisfy it automatically via `use GenServer`
  / `use Supervisor`. Modules that plug in at a different level (the
  `ExRatatui.SSH` channel, instantiated by OTP `:ssh`) declare the
  behaviour without providing a child spec.
  """

  @typedoc """
  Callback a byte-stream transport hands to the runtime server so it
  can ship rendered ANSI back to the remote terminal. Called from the
  server process on every render; must be fast and non-blocking.
  """
  @type writer_fn :: (iodata() -> :ok)

  @typedoc """
  Variants accepted by the runtime server's `:transport` option at
  init time.

    * `:local` — the server owns a real tty via `ExRatatui.run/1`.
    * `{:session, session, writer_fn}` — the server renders into the
      given `ExRatatui.Session` and calls `writer_fn` with the
      resulting bytes. Used by SSH today and by Kino in the future.
    * `{:distributed_server, client_pid, width, height}` — the server
      ships widget trees to a remote renderer (see
      `ExRatatui.Distributed.Listener`) that renders them locally.
  """
  @type server_transport ::
          :local
          | {:session, ExRatatui.Session.t(), writer_fn()}
          | {:distributed_server, pid(), pos_integer(), pos_integer()}

  @typedoc """
  Mailbox messages a transport sends to the Server pid.

    * `{:ex_ratatui_event, event}` — user input (key press, mouse,
      paste, focus change) decoded to a `t:ExRatatui.Event.t/0`.
    * `{:ex_ratatui_resize, w, h}` — the terminal changed size.
      Sessions must already be resized before the message is sent;
      the Server just picks up the new dimensions and re-renders.
  """
  @type to_server ::
          {:ex_ratatui_event, ExRatatui.Event.t()}
          | {:ex_ratatui_resize, pos_integer(), pos_integer()}

  @doc """
  Returns a supervisor child spec for the transport. Implemented
  automatically by modules that `use GenServer` or `use Supervisor`.
  Transports that aren't started as supervised children (e.g. an
  SSH channel instantiated by OTP `:ssh`) don't need to provide it.
  """
  @callback child_spec(keyword()) :: Supervisor.child_spec()

  @optional_callbacks child_spec: 1

  @doc """
  Starts the runtime server that backs a transport. This is the public
  entrypoint for custom transports — the built-in `:local`, SSH, and
  Distributed transports call it internally.

  `opts` is a keyword list:

    * `:mod` (required) — module implementing `ExRatatui.App`.
    * `:transport` — one of the `t:server_transport/0` shapes. Defaults
      to `:local`.
    * `:name` — optional `GenServer` name. Pass `nil` to start an
      unnamed server (recommended for per-connection transports that
      serve many clients).

  Returns `{:ok, server_pid}` on success, propagating any error tuple
  the server raises during init.

  ## Example

  A byte-stream transport typically looks like:

      session = ExRatatui.Session.new(width, height)
      writer  = fn bytes -> transport_write(conn, bytes) end

      {:ok, server} =
        ExRatatui.Transport.start_server(
          mod: MyApp,
          name: nil,
          transport: {:session, session, writer}
        )

  See [`guides/custom_transports.md`](guides/custom_transports.md) for
  the full walkthrough.
  """
  @spec start_server(keyword()) :: GenServer.on_start()
  def start_server(opts) when is_list(opts) do
    ExRatatui.Server.start_link(opts)
  end
end
