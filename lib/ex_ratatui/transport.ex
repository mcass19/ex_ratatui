defmodule ExRatatui.Transport do
  @moduledoc """
  Shared protocol between `ExRatatui.Server` and the modules that carry
  input/output bytes for a running `ExRatatui.App`.

  ex_ratatui ships three transports:

    * `ExRatatui.SSH` + `ExRatatui.SSH.Daemon` — serve apps over SSH.
    * `ExRatatui.Distributed.Listener` — serve apps to remote BEAM nodes
      using distribution instead of raw bytes.
    * The `:local` transport baked into `ExRatatui.Server` itself — runs
      against the host tty via `ExRatatui.run/1`.

  Downstream packages (`kino_ex_ratatui`, custom TCP bridges, …) plug in
  by adopting `@behaviour ExRatatui.Transport` and speaking the same
  two-way protocol documented below. See
  [`guides/custom_transports.md`](guides/custom_transports.md) for a
  ~60-line TCP walkthrough.

  ## Wire protocol

  A transport is any process that:

    1. Decides *how* the Server is wired up by passing one of the
       `t:server_transport/0` shapes as the `:transport` option to
       `ExRatatui.Server.start_link/1`.
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
  Callback a byte-stream transport hands to `ExRatatui.Server` so the
  Server can ship rendered ANSI back to the remote terminal. Called
  from the Server process on every render; must be fast and non-
  blocking.
  """
  @type writer_fn :: (iodata() -> :ok)

  @typedoc """
  Variants accepted by `ExRatatui.Server`'s `:transport` option at
  init time.

    * `:local` — Server owns a real tty via `ExRatatui.run/1`.
    * `{:session, session, writer_fn}` — Server renders into the given
      `ExRatatui.Session` and calls `writer_fn` with the resulting
      bytes. Used by SSH today and by Kino in the future.
    * `{:distributed_server, client_pid, width, height}` — Server
      ships widget trees to a remote `ExRatatui.Distributed.Client`
      that renders them locally.
  """
  @type server_transport ::
          :local
          | {:session, ExRatatui.Session.t(), writer_fn()}
          | {:distributed_server, pid(), pos_integer(), pos_integer()}

  @typedoc """
  Mailbox messages a transport sends to the Server pid.

    * `{:ex_ratatui_event, event}` — user input (key press, mouse,
      paste, focus change) decoded to an `ExRatatui.Event.t/0`.
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
end
