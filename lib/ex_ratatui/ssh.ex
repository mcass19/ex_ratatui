defmodule ExRatatui.SSH do
  @moduledoc """
  OTP `:ssh_server_channel` implementation that serves an `ExRatatui.App`
  over a single SSH channel.

  One instance is spawned per SSH channel (i.e. per connected client). It
  owns an `ExRatatui.Session` for that channel and a linked
  `ExRatatui.Server` running the user's app module in `:ssh` transport
  mode. Bytes the ratatui backend writes into the session's in-memory
  buffer are shipped back to the client via `:ssh_connection.send/3`,
  and bytes the client types come in as `{:data, _, _, _}` events that
  get fed through the session's ANSI parser and dispatched to the
  server as `{:ex_ratatui_event, event}` messages.

  ## Two entry points

  SSH has two ways a client can ask a server to run "something":

    * **Shell** — `ssh host` with no command; the client expects the server
      to start the user's default shell and wire it to the channel.
    * **Subsystem** — `ssh host -s <name>`; the client asks for a named
      non-shell handler (this is what `nerves_ssh` uses for its
      `subsystems:` config, what `sftp` rides on, etc.).

  Both are supported here. Shell mode is required for the standalone
  daemon so plain `ssh` just works. Subsystem mode is how `nerves_ssh`
  plugs this into its existing daemon — see `subsystem/1` for the exact
  shape it expects.

  ## PTY is required

  The TUI makes no sense without a pty: no dimensions, no terminal modes,
  nowhere to send ANSI. If the client doesn't request a pty before
  starting the shell/subsystem we reject the channel. The client will
  see this as an immediate disconnect.

  ## Subsystem helper

      # In a nerves_ssh subsystems list:
      subsystems: [ExRatatui.SSH.subsystem(MyApp.TUI)]

  Returns a `{charlist, {module, init_args}}` tuple in exactly the shape
  OTP `:ssh` expects for its `subsystems:` option.

  ## Dependency injection for tests

  `init/1` accepts optional `:sender` and `:starter` overrides so unit
  tests can substitute fakes for `:ssh_connection.send/3` and
  `ExRatatui.Server.start_link/1` without standing up real infrastructure.
  Defaults point at the real OTP + Server functions; production callers
  never pass either key.
  """

  @behaviour :ssh_server_channel

  require Logger

  alias ExRatatui.Session

  @default_sender &:ssh_connection.send/3
  @default_replier &:ssh_connection.reply_request/4
  @default_starter &ExRatatui.Server.start_link/1

  defstruct [
    :mod,
    :app_opts,
    :conn,
    :channel_id,
    :session,
    :server_pid,
    :sender,
    :replier,
    :starter
  ]

  @type t :: %__MODULE__{
          mod: module(),
          app_opts: keyword(),
          conn: term() | nil,
          channel_id: non_neg_integer() | nil,
          session: Session.t() | nil,
          server_pid: pid() | nil,
          sender: (term(), non_neg_integer(), iodata() -> :ok | {:error, term()}),
          replier: (term(), boolean(), :success | :failure, non_neg_integer() -> :ok),
          starter: (keyword() -> {:ok, pid()} | {:error, term()})
        }

  @doc """
  Returns a `{charlist_name, {ExRatatui.SSH, init_args}}` tuple in the
  shape OTP `:ssh`'s `:subsystems` option (and `nerves_ssh`'s
  `subsystems:` list) expects.

  The charlist name is the full module name (e.g. `~c"Elixir.MyApp.TUI"`)
  so each app module gets its own distinct subsystem. Two apps
  configured into the same daemon will not collide.

  ## Examples

      iex> ExRatatui.SSH.subsystem(SomeTUIModule)
      {~c"Elixir.SomeTUIModule", {ExRatatui.SSH, [mod: SomeTUIModule]}}
  """
  @spec subsystem(module()) :: {charlist(), {module(), keyword()}}
  def subsystem(mod) when is_atom(mod) do
    {String.to_charlist(Atom.to_string(mod)), {__MODULE__, [mod: mod]}}
  end

  ## :ssh_server_channel callbacks

  @impl :ssh_server_channel
  def init(args) when is_list(args) do
    mod = Keyword.fetch!(args, :mod)
    app_opts = Keyword.get(args, :app_opts, [])
    sender = Keyword.get(args, :sender, @default_sender)
    replier = Keyword.get(args, :replier, @default_replier)
    starter = Keyword.get(args, :starter, @default_starter)

    state = %__MODULE__{
      mod: mod,
      app_opts: app_opts,
      sender: sender,
      replier: replier,
      starter: starter
    }

    {:ok, state}
  end

  @impl :ssh_server_channel
  def handle_msg({:ssh_channel_up, channel_id, conn}, %__MODULE__{} = state) do
    # Record the channel/connection now. We can't build the Session yet
    # because we don't know the pty dimensions — that happens in the
    # {:pty, ...} handler below.
    {:ok, %{state | channel_id: channel_id, conn: conn}}
  end

  def handle_msg({:EXIT, pid, _reason}, %__MODULE__{server_pid: pid, channel_id: id} = state) do
    # Our linked Server died (normal or crash). Either way the channel
    # has nothing left to do, so close cleanly.
    {:stop, id, %{state | server_pid: nil}}
  end

  def handle_msg(_msg, state), do: {:ok, state}

  @impl :ssh_server_channel
  def handle_ssh_msg(
        {:ssh_cm, conn, {:pty, channel_id, want_reply, {_term, width, height, _pw, _ph, _modes}}},
        %__MODULE__{} = state
      ) do
    {w, h} = normalize_pty_size(width, height)
    session = Session.new(w, h)
    state.replier.(conn, want_reply, :success, channel_id)
    {:ok, %{state | session: session, conn: conn, channel_id: channel_id}}
  end

  def handle_ssh_msg(
        {:ssh_cm, conn, {:shell, channel_id, want_reply}},
        %__MODULE__{session: nil} = state
      ) do
    state.replier.(conn, want_reply, :failure, channel_id)
    {:stop, channel_id, state}
  end

  def handle_ssh_msg(
        {:ssh_cm, conn, {:shell, channel_id, want_reply}},
        %__MODULE__{} = state
      ) do
    case start_server(state) do
      {:ok, server_pid} ->
        state.replier.(conn, want_reply, :success, channel_id)
        {:ok, %{state | server_pid: server_pid}}

      {:error, _reason} ->
        state.replier.(conn, want_reply, :failure, channel_id)
        {:stop, channel_id, state}
    end
  end

  def handle_ssh_msg(
        {:ssh_cm, conn, {:subsystem, channel_id, want_reply, _name}},
        %__MODULE__{session: nil} = state
      ) do
    # Subsystem requests arrive with no pty — we need one to render,
    # so synthesize a default 80x24 session. The client can always
    # send a window_change to correct the size afterwards.
    session = Session.new(80, 24)
    primed = %{state | session: session, conn: conn, channel_id: channel_id}

    case start_server(primed) do
      {:ok, server_pid} ->
        state.replier.(conn, want_reply, :success, channel_id)
        {:ok, %{primed | server_pid: server_pid}}

      {:error, _reason} ->
        Session.close(session)
        state.replier.(conn, want_reply, :failure, channel_id)
        {:stop, channel_id, state}
    end
  end

  def handle_ssh_msg(
        {:ssh_cm, conn, {:subsystem, channel_id, want_reply, _name}},
        %__MODULE__{} = state
      ) do
    # Subsystem request after a pty — e.g. a client that sent pty_req
    # first and then asked for our subsystem. Reuse the existing session.
    case start_server(state) do
      {:ok, server_pid} ->
        state.replier.(conn, want_reply, :success, channel_id)
        {:ok, %{state | server_pid: server_pid}}

      {:error, _reason} ->
        state.replier.(conn, want_reply, :failure, channel_id)
        {:stop, channel_id, state}
    end
  end

  def handle_ssh_msg(
        {:ssh_cm, _conn, {:data, _channel_id, _type, data}},
        %__MODULE__{session: %Session{}, server_pid: server_pid} = state
      )
      when is_pid(server_pid) do
    state.session
    |> Session.feed_input(data)
    |> Enum.each(fn event -> send(server_pid, {:ex_ratatui_event, event}) end)

    {:ok, state}
  end

  def handle_ssh_msg(
        {:ssh_cm, _conn, {:window_change, _channel_id, width, height, _pw, _ph}},
        %__MODULE__{session: %Session{}, server_pid: server_pid} = state
      )
      when is_pid(server_pid) do
    {w, h} = normalize_pty_size(width, height)
    _ = Session.resize(state.session, w, h)
    send(server_pid, {:ex_ratatui_resize, w, h})
    {:ok, state}
  end

  def handle_ssh_msg({:ssh_cm, _conn, {:eof, channel_id}}, state) do
    {:stop, channel_id, state}
  end

  def handle_ssh_msg({:ssh_cm, conn, {:env, channel_id, want_reply, _var, _val}}, state) do
    # Environment variables are advisory and per-channel; we reject them
    # cleanly like OTP's ssh_cli does.
    state.replier.(conn, want_reply, :failure, channel_id)
    {:ok, state}
  end

  def handle_ssh_msg({:ssh_cm, _conn, {:exit_status, channel_id, _status}}, state) do
    {:stop, channel_id, state}
  end

  def handle_ssh_msg({:ssh_cm, _conn, {:exit_signal, channel_id, _, _, _}}, state) do
    {:stop, channel_id, state}
  end

  def handle_ssh_msg({:ssh_cm, _conn, {:signal, _channel_id, _name}}, state) do
    # SSH signals are OS-level and not meaningful to a BEAM TUI — ignore
    # per RFC 4254 §6.9.
    {:ok, state}
  end

  def handle_ssh_msg(_msg, state), do: {:ok, state}

  @impl :ssh_server_channel
  def terminate(_reason, %__MODULE__{} = state) do
    _ = maybe_stop_server(state.server_pid)
    _ = maybe_close_session(state.session)
    :ok
  end

  ## Internal helpers (public with @doc false for unit-testability)

  @doc false
  def start_server(%__MODULE__{} = state) do
    writer_fn = make_writer_fn(state.sender, state.conn, state.channel_id)

    opts =
      state.app_opts
      |> Keyword.put(:mod, state.mod)
      |> Keyword.put(:name, nil)
      |> Keyword.put(:transport, {:ssh, state.session, writer_fn})

    state.starter.(opts)
  end

  @doc false
  def make_writer_fn(sender, conn, channel_id) do
    fn bytes ->
      case sender.(conn, channel_id, bytes) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("ExRatatui.SSH writer failed: #{inspect(reason)}")
          :ok
      end
    end
  end

  @doc false
  # PTY sizes can arrive as 0 when the client only set pixel dimensions.
  # We fall back to a sensible default rather than creating a zero-sized
  # session (which would panic inside ratatui).
  def normalize_pty_size(width, height) do
    {fallback_zero(width, 80), fallback_zero(height, 24)}
  end

  defp fallback_zero(0, default), do: default
  defp fallback_zero(n, _default) when is_integer(n) and n > 0, do: n
  defp fallback_zero(_, default), do: default

  defp maybe_stop_server(nil), do: :ok

  defp maybe_stop_server(pid) when is_pid(pid) do
    # `:shutdown` escapes trap_exit (unlike `:normal`) and is async, so
    # there is no race window against a server that just died.
    if Process.alive?(pid), do: Process.exit(pid, :shutdown)
    :ok
  end

  defp maybe_close_session(nil), do: :ok
  defp maybe_close_session(%Session{} = session), do: Session.close(session)
end
