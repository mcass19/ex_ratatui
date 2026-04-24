defmodule ExRatatui.SSH do
  @moduledoc """
  OTP `:ssh_server_channel` implementation that serves an `ExRatatui.App`
  over a single SSH channel.

  One instance is spawned per SSH channel (i.e. per connected client). It
  owns an `ExRatatui.Session` for that channel and a linked internal
  server running the user's app module in `:ssh` transport mode. Bytes
  the ratatui backend writes into the session's in-memory buffer are
  shipped back to the client via `:ssh_connection.send/3`, and bytes
  the client types come in as `{:data, _, _, _}` events that get fed
  through the session's ANSI parser and dispatched to the server as
  `{:ex_ratatui_event, event}` messages.

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

  ### Shell vs subsystem startup

  The two modes use different triggers to spin up the server:

    * **Shell mode** waits for the client's `pty_req` (to size the
      session) and then `shell_req` (to launch). If the client skips the
      pty, the channel is rejected on the shell request.
    * **Subsystem mode** can't wait for those messages: OTP `:ssh`
      matches the subsystem name against the daemon's `:subsystems`
      config and consumes the `{:subsystem, ...}` request itself to
      dispatch us — `handle_ssh_msg/2` never sees it. Worse, when the
      client passes `-t` OTP *also* consumes the `pty_req` before
      the subsystem dispatch fires: OTP hands it to the daemon's
      default CLI handler (IEx on a `nerves_ssh` device) and silently
      orphans that CLI process the moment our subsystem handler
      takes over the channel. Neither pty_req nor its dimensions
      reach us through any channel request.

      To work around that, on `{:ssh_channel_up, ...}` we synthesize a
      default 80x24 session, start the server, and immediately emit a
      Cursor Position Report roundtrip —
      `ESC[s ESC[9999;9999H ESC[6n ESC[u` — which parks the cursor at
      (9999, 9999) so the client clamps it to the actual pty size,
      then asks the client to report the position. The response
      arrives on the next `{:data, ...}` channel message, is parsed
      into a `%Event.Resize{}` by the session's ANSI input parser,
      and the data handler resizes the session in place + notifies
      the server. Clients can still send `{:window_change, ...}`
      afterwards to track real runtime resizes.

  `subsystem/1` bakes `subsystem: true` into the init args so the
  channel handler can tell the two flows apart. Shell-mode init (via
  `ssh_cli:`) leaves the flag at its default `false`.

  ### Client-side caveat: always pass `-t` in subsystem mode

  OpenSSH does **not** allocate a PTY by default for `ssh host -s name`
  — that's designed for protocols like `sftp` that don't need one. For
  an interactive TUI you MUST force it with `-t`:

      ssh -t nerves.local -s Elixir.MyApp.TUI   # ✓ works
      ssh nerves.local -s Elixir.MyApp.TUI      # ✗ local tty stays in
                                                #   cooked mode, keys are
                                                #   line-buffered + echoed
                                                #   locally, screen redraw
                                                #   bleeds into the shell
                                                #   prompt on exit

  Without `-t`, render bytes still reach the client and the TUI runs —
  it just can't be driven interactively.

  ## Subsystem helper

  Returns a `{charlist, {module, init_args}}` tuple in exactly the shape
  OTP `:ssh` expects for its `subsystems:` option. Plug it into a
  `nerves_ssh` subsystems list from `config/runtime.exs`:

      # config/runtime.exs
      import Config

      if Application.spec(:nerves_ssh) do
        config :nerves_ssh,
          subsystems: [
            :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
            ExRatatui.SSH.subsystem(MyApp.TUI)
          ]
      end

  This **must** live in `runtime.exs`, not `target.exs`. On a fresh
  `MIX_TARGET=rpi4 mix compile` Mix evaluates compile-time configs
  before it builds deps for the target, so `ExRatatui.SSH` isn't on the
  code path yet and the `subsystem/1` call would crash with `module
  ExRatatui.SSH is not available`. `runtime.exs` runs at device boot
  after every beam file is loaded but before the OTP application
  controller starts `:nerves_ssh`, which is exactly the window we need.
  The `Application.spec(:nerves_ssh)` guard keeps host builds (where
  `:nerves_ssh` isn't a dep) silent. See `guides/ssh_transport.md` for
  the full write-up.

  ## Dependency injection for tests

  `init/1` accepts optional `:sender` and `:starter` overrides so unit
  tests can substitute fakes for `:ssh_connection.send/3` and the
  internal server's start function without standing up real
  infrastructure. Defaults point at the real OTP + Server functions;
  production callers never pass either key.
  """

  @behaviour :ssh_server_channel

  require Logger

  alias ExRatatui.Event
  alias ExRatatui.Session

  @default_sender &:ssh_connection.send/3
  @default_replier &:ssh_connection.reply_request/4
  @default_starter &ExRatatui.Server.start_link/1

  # Switch the client into the alternate screen buffer and hide the
  # cursor before the first frame lands. The in-memory `Session`
  # deliberately never touches these — see
  # `native/ex_ratatui/src/session.rs` — so the SSH transport has to
  # emit them itself or the TUI will paint over the client's shell
  # scrollback instead of onto a clean canvas.
  @enter_screen "\e[?1049h\e[?25l"

  # Cursor Position Report roundtrip used to discover the client's real
  # pty size in subsystem mode. OTP `:ssh` consumes pty_req before the
  # subsystem handler exists (it hands it to the default CLI handler
  # first), so `handle_ssh_msg/2` never sees it and we can't read the
  # dimensions off the wire. Instead, park the cursor at (9999, 9999)
  # — the client clamps the position to its actual size — then issue
  # `ESC[6n`, which the client answers with `ESC[<row>;<col>R`. That
  # response lands on the next `{:data, ...}` channel message, gets
  # parsed into a `%Event.Resize{}` by the session input parser, and
  # the `{:data, ...}` handler turns it into an `{:ex_ratatui_resize,
  # w, h}` to the server. `ESC[s`/`ESC[u` save and restore the cursor
  # position so ratatui's first frame still paints at the top-left.
  @cpr_size_query "\e[s\e[9999;9999H\e[6n\e[u"

  # Inverse of `@enter_screen`, plus an SGR reset so any colours left
  # over from the final rendered frame don't bleed into the client's
  # shell prompt on return. Order matters: we leave the alt buffer
  # *before* re-showing the cursor so that the `\e[?25h` applies to the
  # primary buffer. On terminals where cursor visibility is a global
  # state (xterm, gnome-terminal, kitty, ghostty), reversing this order
  # leaves the cursor invisible on the client's shell after disconnect.
  # This matches crossterm's canonical `LeaveAlternateScreen, Show`
  # teardown.
  @leave_screen "\e[?1049l\e[?25h\e[0m"

  # Bare-Esc detection timeout (milliseconds). VTE's state machine
  # swallows 0x1B as the start of an escape sequence; if no follow-up
  # byte arrives within this window we emit a synthetic Esc press.
  # 50 ms is well above the ~1 ms inter-byte gap of escape sequences
  # but below the human perception threshold.
  @esc_timeout_ms 50

  defstruct [
    :mod,
    :app_opts,
    :conn,
    :channel_id,
    :session,
    :server_pid,
    :sender,
    :replier,
    :starter,
    rendering: false,
    subsystem_mode: false,
    esc_timer: nil
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
          starter: (keyword() -> {:ok, pid()} | {:error, term()}),
          rendering: boolean(),
          subsystem_mode: boolean(),
          esc_timer: reference() | nil
        }

  @doc """
  Returns a `{charlist_name, {ExRatatui.SSH, init_args}}` tuple in the
  shape OTP `:ssh`'s `:subsystems` option (and `nerves_ssh`'s
  `subsystems:` list) expects.

  The charlist name is the full module name (e.g. `~c"Elixir.MyApp.TUI"`)
  so each app module gets its own distinct subsystem. Two apps
  configured into the same daemon will not collide.

  The init args include `subsystem: true` so the channel handler knows
  it was spawned via OTP's subsystem dispatch (which consumes the
  `{:subsystem, ...}` message internally) and can start the TUI server
  as soon as the channel is up, instead of waiting for a shell request
  that will never arrive.

  ## Examples

      iex> ExRatatui.SSH.subsystem(SomeTUIModule)
      {~c"Elixir.SomeTUIModule", {ExRatatui.SSH, [mod: SomeTUIModule, subsystem: true]}}
  """
  @spec subsystem(module()) :: {charlist(), {module(), keyword()}}
  def subsystem(mod) when is_atom(mod) do
    {String.to_charlist(Atom.to_string(mod)), {__MODULE__, [mod: mod, subsystem: true]}}
  end

  ## :ssh_server_channel callbacks

  @impl :ssh_server_channel
  def init(args) when is_list(args) do
    mod = Keyword.fetch!(args, :mod)
    app_opts = Keyword.get(args, :app_opts, [])
    sender = Keyword.get(args, :sender, @default_sender)
    replier = Keyword.get(args, :replier, @default_replier)
    starter = Keyword.get(args, :starter, @default_starter)
    subsystem_mode = Keyword.get(args, :subsystem, false)

    state = %__MODULE__{
      mod: mod,
      app_opts: app_opts,
      sender: sender,
      replier: replier,
      starter: starter,
      subsystem_mode: subsystem_mode
    }

    {:ok, state}
  end

  @impl :ssh_server_channel
  def handle_msg(
        {:ssh_channel_up, channel_id, conn},
        %__MODULE__{subsystem_mode: true} = state
      ) do
    # Subsystem mode: OTP `:ssh` has already consumed the
    # `{:subsystem, ...}` channel request internally to dispatch us
    # here, so it will NEVER forward it to `handle_ssh_msg/2`. This is
    # the only signal we get that the channel is ready. Worse, when
    # the client is invoked as `ssh -t -s <name>`, OTP ALSO consumes
    # the pty_req before the subsystem dispatch fires — it hands it
    # to the default CLI handler (IEx on nerves_ssh, for example) and
    # that handler is silently orphaned the moment OTP rebinds the
    # channel's user pid to us. So we don't see pty_req either, which
    # means we can't learn the client's real dimensions from any
    # incoming channel request.
    #
    # Build a default 80x24 session and start the TUI server
    # immediately so the first frame goes out as soon as possible,
    # then fire a Cursor Position Report roundtrip (`@cpr_size_query`)
    # to discover the client's actual pty size. The response arrives
    # as `ESC[<row>;<col>R` on the next `{:data, ...}` message, the
    # session input parser decodes it into a `%Event.Resize{}`, and
    # the `{:data, ...}` handler below turns that into a `Session`
    # resize + a `{:ex_ratatui_resize, w, h}` notification to the
    # server. `{:window_change, ...}` still correctly resizes after
    # that if the user drags their terminal window.
    session = Session.new(80, 24)
    primed = %{state | session: session, conn: conn, channel_id: channel_id}

    case start_server(primed) do
      {:ok, server_pid} ->
        _ = primed.sender.(conn, channel_id, @cpr_size_query)
        {:ok, %{primed | server_pid: server_pid, rendering: true}}

      {:error, _reason} ->
        Session.close(session)
        {:stop, channel_id, state}
    end
  end

  def handle_msg({:ssh_channel_up, channel_id, conn}, %__MODULE__{} = state) do
    # Shell mode: record the channel/connection now. We can't build the
    # Session yet because we don't know the pty dimensions — that
    # happens in the {:pty, ...} handler below, followed by {:shell,
    # ...} which starts the server.
    {:ok, %{state | channel_id: channel_id, conn: conn}}
  end

  def handle_msg(
        :esc_timeout,
        %__MODULE__{session: %Session{} = session, server_pid: server_pid} = state
      )
      when is_pid(server_pid) do
    # The Esc timeout fired — no follow-up byte arrived after a bare
    # 0x1B, so this was a genuine Esc press. Reset the parser to Ground
    # (clearing the stuck Escape state) and dispatch a synthetic Esc event.
    Session.reset_parser(session)
    esc_event = %Event.Key{code: "esc", modifiers: [], kind: "press"}
    dispatch_input_event(esc_event, session, server_pid)
    {:ok, %{state | esc_timer: nil}}
  end

  def handle_msg(:esc_timeout, state) do
    # Timer fired but no active session/server — just clear it.
    {:ok, %{state | esc_timer: nil}}
  end

  def handle_msg({:EXIT, pid, _reason}, %__MODULE__{server_pid: pid, channel_id: id} = state) do
    # Our linked Server died (normal or crash). Flush the leave-screen
    # sequence *now*, while the channel is still writable — by the time
    # OTP's ssh_server_channel gets around to calling `terminate/2` it
    # has already queued a `SSH_MSG_CHANNEL_CLOSE` and any further
    # `:ssh_connection.send/3` returns `{:error, closed}` silently,
    # stranding the client in the alt buffer with the cursor hidden.
    _ = maybe_leave_screen(state)
    {:stop, id, %{state | server_pid: nil, rendering: false}}
  end

  def handle_msg(_msg, state), do: {:ok, state}

  @impl :ssh_server_channel
  def handle_ssh_msg(
        {:ssh_cm, conn, {:pty, channel_id, want_reply, {_term, width, height, _pw, _ph, _modes}}},
        %__MODULE__{session: nil} = state
      ) do
    # No session yet — this is the shell-mode path, where the session
    # doesn't exist until the client sends pty_req (followed by
    # shell_req, which starts the server).
    {w, h} = normalize_pty_size(width, height)
    session = Session.new(w, h)
    state.replier.(conn, want_reply, :success, channel_id)
    {:ok, %{state | session: session, conn: conn, channel_id: channel_id}}
  end

  def handle_ssh_msg(
        {:ssh_cm, conn, {:pty, channel_id, want_reply, {_term, width, height, _pw, _ph, _modes}}},
        %__MODULE__{session: %Session{}} = state
      ) do
    # Subsystem mode with `ssh -t -s`: channel_up already fired, we
    # built a default 80x24 session and started the server. The client
    # is now telling us its real PTY dimensions — resize the existing
    # session in place instead of swapping in a new one, otherwise the
    # server ends up rendering into a Session the SSH channel no longer
    # points at. Mirrors the `window_change` handler below.
    {w, h} = normalize_pty_size(width, height)
    _ = Session.resize(state.session, w, h)
    if is_pid(state.server_pid), do: send(state.server_pid, {:ex_ratatui_resize, w, h})
    state.replier.(conn, want_reply, :success, channel_id)
    {:ok, state}
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
        {:ok, %{state | server_pid: server_pid, rendering: true}}

      {:error, _reason} ->
        state.replier.(conn, want_reply, :failure, channel_id)
        {:stop, channel_id, state}
    end
  end

  def handle_ssh_msg(
        {:ssh_cm, _conn, {:data, _channel_id, _type, data}},
        %__MODULE__{session: %Session{} = session, server_pid: server_pid} = state
      )
      when is_pid(server_pid) do
    # Cancel any pending Esc timer — new data arrived, so the previous
    # 0x1B was part of an escape sequence, not a bare Esc press.
    state = cancel_esc_timer(state)

    events = Session.feed_input(session, data)
    Enum.each(events, &dispatch_input_event(&1, session, server_pid))

    # If the parser consumed bytes but produced no events, the VTE
    # state machine may be sitting in the Escape state after a bare
    # 0x1B. Schedule a short timeout — if no follow-up byte arrives
    # the timer fires and we emit a synthetic Esc press.
    state =
      if events == [] and byte_size(data) > 0 and :binary.match(data, <<0x1B>>) != :nomatch do
        ref = Process.send_after(self(), :esc_timeout, @esc_timeout_ms)
        %{state | esc_timer: ref}
      else
        state
      end

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
    _ = maybe_leave_screen(state)
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
      |> Keyword.put(:transport, {:session, state.session, writer_fn})

    # Write the alt-screen+hide-cursor prelude BEFORE starting the
    # server so the bytes are queued on the SSH channel ahead of any
    # render output. :ssh_connection.send is FIFO per channel, so
    # once this call returns the prelude is guaranteed to reach the
    # client before the server's first frame.
    _ = state.sender.(state.conn, state.channel_id, @enter_screen)

    case state.starter.(opts) do
      {:ok, pid} ->
        {:ok, pid}

      error ->
        # Undo the alt-screen enter so a client that briefly
        # connected sees a clean shell on disconnect instead of a
        # stuck alt buffer.
        _ = state.sender.(state.conn, state.channel_id, @leave_screen)
        error
    end
  end

  @doc false
  # Fans an event emitted by `Session.feed_input/2` out to the server.
  # CPR responses (which the session parser surfaces as
  # `%Event.Resize{}` values) are intercepted here: we resize the
  # session in place and tell the server via `{:ex_ratatui_resize, w,
  # h}` instead of forwarding a Resize event the way we would for a
  # genuine runtime resize. All other events — Key, Mouse — flow
  # through as `{:ex_ratatui_event, event}`.
  def dispatch_input_event(
        %Event.Resize{width: w, height: h},
        %Session{} = session,
        server_pid
      )
      when is_integer(w) and w > 0 and is_integer(h) and h > 0 do
    _ = Session.resize(session, w, h)
    send(server_pid, {:ex_ratatui_resize, w, h})
    :ok
  end

  def dispatch_input_event(event, %Session{}, server_pid) do
    send(server_pid, {:ex_ratatui_event, event})
    :ok
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

  defp cancel_esc_timer(%__MODULE__{esc_timer: nil} = state), do: state

  defp cancel_esc_timer(%__MODULE__{esc_timer: ref} = state) do
    Process.cancel_timer(ref)
    # Flush a possible already-delivered :esc_timeout from the mailbox
    receive do
      :esc_timeout -> :ok
    after
      0 -> :ok
    end

    %{state | esc_timer: nil}
  end

  defp maybe_leave_screen(%__MODULE__{rendering: false}), do: :ok

  defp maybe_leave_screen(%__MODULE__{sender: sender, conn: conn, channel_id: channel_id}) do
    _ = sender.(conn, channel_id, @leave_screen)
    :ok
  end
end
