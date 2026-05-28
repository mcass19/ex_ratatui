defmodule ExRatatui.Server do
  @moduledoc false

  use GenServer

  require Logger

  alias ExRatatui.CellSession
  alias ExRatatui.Command
  alias ExRatatui.Frame
  alias ExRatatui.Native
  alias ExRatatui.Session
  alias ExRatatui.Subscription
  alias ExRatatui.Telemetry

  defstruct [
    :mod,
    :user_state,
    :test_mode,
    :terminal_ref,
    :terminal_size_fn,
    :session,
    :cell_session,
    :writer_fn,
    :intent_writer_fn,
    :client_pid,
    :task_supervisor,
    :width,
    :height,
    polling_enabled?: false,
    pending_commands: [],
    pending_intents: [],
    subscriptions: %{},
    trace_enabled?: false,
    trace_limit: 200,
    trace_events: [],
    render_count: 0,
    last_rendered_at: nil,
    runtime_mode: :callbacks,
    active_async_commands: 0,
    transport: :local,
    poll_interval: 16,
    terminal_initialized: false
  ]

  @subscription_message :__ex_ratatui_subscription_tick__
  @async_message :__ex_ratatui_async_result__

  @doc false
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {:ok, task_sup} = Task.Supervisor.start_link()
    opts = Keyword.put(opts, :task_supervisor, task_sup)

    case Keyword.get(opts, :transport, :local) do
      :local ->
        mod = Keyword.fetch!(opts, :mod)
        test_mode = Keyword.get(opts, :test_mode)
        focus_events? = Keyword.get(opts, :focus_events, false)
        mouse_capture? = Keyword.get(opts, :mouse_capture, false)

        connect_meta = %{
          mod: mod,
          transport: :local,
          focus_events: focus_events?,
          mouse_capture: mouse_capture?
        }

        terminal_ref =
          Telemetry.span([:transport, :connect], connect_meta, fn ->
            init_terminal(test_mode, focus_events?, mouse_capture?)
          end)

        continue_init(terminal_ref, opts)

      {:session, %Session{} = session, writer_fn} when is_function(writer_fn, 1) ->
        continue_init_session(session, writer_fn, opts)

      {:cell_session, %CellSession{} = cell_session, writer_fn} when is_function(writer_fn, 1) ->
        continue_init_cell_session(cell_session, writer_fn, nil, opts)

      {:cell_session, %CellSession{} = cell_session, writer_fn, intent_writer_fn}
      when is_function(writer_fn, 1) and is_function(intent_writer_fn, 1) ->
        continue_init_cell_session(cell_session, writer_fn, intent_writer_fn, opts)

      {:distributed_server, client_pid, width, height}
      when is_pid(client_pid) and is_integer(width) and is_integer(height) ->
        continue_init_distributed_server(client_pid, width, height, opts)
    end
  end

  @doc false
  def continue_init({:error, reason}, opts) do
    stop_task_supervisor(opts)
    {:stop, {:terminal_init_failed, reason}}
  end

  def continue_init(terminal_ref, opts) do
    mod = Keyword.fetch!(opts, :mod)
    poll_interval = Keyword.get(opts, :poll_interval, 16)
    test_mode = Keyword.get(opts, :test_mode)
    # Internal test seam for deterministic live-mode renders without
    # changing production terminal-size behavior.
    terminal_size_fn = Keyword.get(opts, :terminal_size_fn, &ExRatatui.terminal_size/0)

    mount_result =
      Telemetry.span([:runtime, :init], %{mod: mod, transport: :local}, fn ->
        mod.mount(opts)
      end)

    case normalize_mount_result(mount_result) do
      {:ok, user_state, runtime_opts} ->
        state = %__MODULE__{
          mod: mod,
          user_state: user_state,
          poll_interval: poll_interval,
          polling_enabled?: local_polling_enabled?(test_mode),
          test_mode: test_mode,
          terminal_ref: terminal_ref,
          terminal_size_fn: terminal_size_fn,
          task_supervisor: Keyword.fetch!(opts, :task_supervisor),
          terminal_initialized: true,
          runtime_mode: runtime_mode(mod)
        }

        # Mount-time probe — only honored on :local transport (other
        # transports either force halfblocks (CellSession) or surface
        # their own :image_protocol opt (SSH / Distributed)). Soft-fail:
        # the helper logs nothing and leaves the cache untouched if the
        # probe can't complete.
        maybe_probe_image_protocol(terminal_ref, runtime_opts, test_mode)

        state =
          state
          |> maybe_set_trace(runtime_opts)
          |> reconcile_subscriptions()
          |> queue_commands(runtime_opts)
          |> queue_intents(runtime_opts)
          |> do_render_if(runtime_opts)

        state =
          state
          |> flush_pending_commands()
          |> flush_pending_intents()
          |> maybe_rearm_poll()

        {:ok, state}

      {:error, reason} ->
        restore_terminal(terminal_ref)
        stop_task_supervisor(opts)
        {:stop, reason}
    end
  end

  @doc false
  # Public for testing — production callers go through `continue_init/2`.
  def maybe_probe_image_protocol(_terminal_ref, %{probe_image_protocol: false}, _test_mode),
    do: :ok

  def maybe_probe_image_protocol(_terminal_ref, _runtime_opts, {_, _} = _test_mode),
    do: :ok

  def maybe_probe_image_protocol(terminal_ref, %{probe_image_protocol: true}, nil) do
    _ = ExRatatui.Image.auto_local_protocol(terminal_ref)
    :ok
  end

  @doc false
  # Byte-stream session transport init: the Session is created externally
  # by the transport (SSH channel, Kino widget, a custom TCP
  # bridge…) which knows how to ship bytes back to the client, so this
  # path never touches the OS terminal. mount/1 sees augmented opts so an
  # app can opt into per-client behaviour without breaking the local case.
  def continue_init_session(%Session{} = session, writer_fn, opts) do
    mod = Keyword.fetch!(opts, :mod)

    {w, h} =
      Telemetry.span([:transport, :connect], %{mod: mod, transport: :session}, fn ->
        Session.size(session)
      end)

    Telemetry.execute(
      [:session, :lifecycle, :open],
      %{},
      %{mod: mod, transport: :session, width: w, height: h}
    )

    augmented_opts = augment_session_mount_opts(opts, w, h)

    mount_result =
      Telemetry.span([:runtime, :init], %{mod: mod, transport: :session}, fn ->
        mod.mount(augmented_opts)
      end)

    case normalize_mount_result(mount_result) do
      {:ok, user_state, runtime_opts} ->
        state = %__MODULE__{
          mod: mod,
          user_state: user_state,
          transport: :session,
          session: session,
          writer_fn: writer_fn,
          task_supervisor: Keyword.fetch!(opts, :task_supervisor),
          width: w,
          height: h,
          terminal_initialized: true,
          runtime_mode: runtime_mode(mod)
        }

        state =
          state
          |> maybe_set_trace(runtime_opts)
          |> reconcile_subscriptions()
          |> queue_commands(runtime_opts)
          |> queue_intents(runtime_opts)
          |> do_render_if(runtime_opts)

        state =
          state
          |> flush_pending_commands()
          |> flush_pending_intents()

        {:ok, state}

      {:error, reason} ->
        Telemetry.execute(
          [:session, :lifecycle, :close],
          %{},
          %{mod: mod, transport: :session, reason: reason}
        )

        Session.close(session)
        stop_task_supervisor(opts)
        {:stop, reason}
    end
  end

  @doc false
  # Cell-stream session transport init: the CellSession is created
  # externally by the transport (Phoenix LiveView, Nerves badge,
  # custom non-terminal renderer) which knows how to ship cell diffs
  # back to the consumer. Same shape as `continue_init_session` —
  # different session type, different render output. Telemetry tags
  # the lifecycle events with `transport: :cell_session` so handlers
  # can route browser/embedded sessions to their own dashboards.
  def continue_init_cell_session(%CellSession{} = cell_session, writer_fn, intent_writer_fn, opts) do
    mod = Keyword.fetch!(opts, :mod)

    {w, h} =
      Telemetry.span([:transport, :connect], %{mod: mod, transport: :cell_session}, fn ->
        CellSession.size(cell_session)
      end)

    Telemetry.execute(
      [:session, :lifecycle, :open],
      %{},
      %{mod: mod, transport: :cell_session, width: w, height: h}
    )

    augmented_opts = augment_cell_session_mount_opts(opts, w, h)

    mount_result =
      Telemetry.span([:runtime, :init], %{mod: mod, transport: :cell_session}, fn ->
        mod.mount(augmented_opts)
      end)

    case normalize_mount_result(mount_result) do
      {:ok, user_state, runtime_opts} ->
        state = %__MODULE__{
          mod: mod,
          user_state: user_state,
          transport: :cell_session,
          cell_session: cell_session,
          writer_fn: writer_fn,
          intent_writer_fn: intent_writer_fn,
          task_supervisor: Keyword.fetch!(opts, :task_supervisor),
          width: w,
          height: h,
          terminal_initialized: true,
          runtime_mode: runtime_mode(mod)
        }

        state =
          state
          |> maybe_set_trace(runtime_opts)
          |> reconcile_subscriptions()
          |> queue_commands(runtime_opts)
          |> queue_intents(runtime_opts)
          |> do_render_if(runtime_opts)

        state =
          state
          |> flush_pending_commands()
          |> flush_pending_intents()

        {:ok, state}

      {:error, reason} ->
        Telemetry.execute(
          [:session, :lifecycle, :close],
          %{},
          %{mod: mod, transport: :cell_session, reason: reason}
        )

        CellSession.close(cell_session)
        stop_task_supervisor(opts)
        {:stop, reason}
    end
  end

  @doc false
  # Distribution-attach server init: the remote client rendered locally,
  # so no Rust resource is needed here. We send widget lists as BEAM
  # terms and the client draws them with its own TerminalResource.
  def continue_init_distributed_server(client_pid, width, height, opts) do
    mod = Keyword.fetch!(opts, :mod)

    Telemetry.span([:transport, :connect], %{mod: mod, transport: :distributed_server}, fn ->
      Process.monitor(client_pid)
    end)

    augmented_opts = augment_distributed_mount_opts(opts, width, height)

    mount_result =
      Telemetry.span(
        [:runtime, :init],
        %{mod: mod, transport: :distributed_server},
        fn -> mod.mount(augmented_opts) end
      )

    case normalize_mount_result(mount_result) do
      {:ok, user_state, runtime_opts} ->
        state = %__MODULE__{
          mod: mod,
          user_state: user_state,
          transport: :distributed_server,
          client_pid: client_pid,
          task_supervisor: Keyword.fetch!(opts, :task_supervisor),
          width: width,
          height: height,
          terminal_initialized: true,
          runtime_mode: runtime_mode(mod)
        }

        state =
          state
          |> maybe_set_trace(runtime_opts)
          |> reconcile_subscriptions()
          |> queue_commands(runtime_opts)
          |> queue_intents(runtime_opts)
          |> do_render_if(runtime_opts)

        state =
          state
          |> flush_pending_commands()
          |> flush_pending_intents()

        {:ok, state}

      {:error, reason} ->
        stop_task_supervisor(opts)
        {:stop, reason}
    end
  end

  @doc false
  def augment_distributed_mount_opts(opts, width, height) do
    opts
    |> Keyword.put(:transport, :distributed)
    |> Keyword.put(:width, width)
    |> Keyword.put(:height, height)
  end

  @doc false
  # Populates the opts passed to mount/1 for a byte-stream session
  # transport. `opts[:transport]` is set to `:session` — same tag the
  # Server stores internally — so every byte-stream transport (SSH
  # today, Kino later, custom TCP) reports identically to user code.
  # Apps that need to distinguish "am I running over SSH vs local?"
  # still can: the user put `transport: :ssh` in their child spec
  # themselves, so that context is upstream. In mount, the useful
  # answer is "you're on the session runtime."
  def augment_session_mount_opts(opts, width, height) do
    opts
    |> Keyword.put(:transport, :session)
    |> Keyword.put(:width, width)
    |> Keyword.put(:height, height)
  end

  @doc false
  # Cell-stream analogue of `augment_session_mount_opts`. `opts[:transport]`
  # is set to `:cell_session` so user code in `mount/1` can distinguish
  # "I'm running in a browser/embedded surface" from "I'm running in a
  # terminal." Apps that don't care can ignore it.
  def augment_cell_session_mount_opts(opts, width, height) do
    opts
    |> Keyword.put(:transport, :cell_session)
    |> Keyword.put(:width, width)
    |> Keyword.put(:height, height)
  end

  @impl true
  def handle_info(:poll, %__MODULE__{transport: :local, polling_enabled?: false} = state),
    do: {:noreply, state}

  def handle_info(:poll, %__MODULE__{transport: :local} = state) do
    state.poll_interval
    |> ExRatatui.poll_event()
    |> handle_poll_result(state)
    |> process_poll_result()
  end

  # Non-local transports are event-driven via mailbox messages from the
  # transport process — we silently absorb stray :poll messages so they
  # never reach the user module's handle_info/2.
  def handle_info(:poll, state), do: {:noreply, state}

  def handle_info({@subscription_message, id, token}, state) do
    dispatch_subscription_tick(id, token, state)
  end

  def handle_info({@async_message, message}, state) do
    state
    |> decrement_async_commands()
    |> dispatch_info_message(message)
  end

  def handle_info({:ex_ratatui_event, event}, %__MODULE__{transport: transport} = state)
      when transport in [:session, :cell_session, :distributed_server] do
    state
    |> dispatch_event(event)
    |> process_event_result()
  end

  def handle_info({:ex_ratatui_resize, w, h}, %__MODULE__{transport: transport} = state)
      when transport in [:session, :cell_session, :distributed_server] do
    # Update the cached size *before* dispatching so the render that
    # follows the App's handle_event/2 callback (inside dispatch_event)
    # uses the new dimensions. Without this, an App that adjusts state
    # in response to Resize would see stale `frame.width` / `frame.height`
    # on the very render where it expects the new ones.
    state = %{state | width: w, height: h}

    state
    |> dispatch_event(%ExRatatui.Event.Resize{width: w, height: h})
    |> process_event_result()
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        %__MODULE__{transport: :distributed_server, client_pid: pid} = state
      ) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(msg, state) do
    dispatch_info_message(state, msg)
  end

  @impl true
  def handle_call(:ex_ratatui_runtime_snapshot, _from, state) do
    {:reply, runtime_snapshot(state), state}
  end

  def handle_call({:ex_ratatui_runtime_inject_event, event}, _from, state) do
    case dispatch_event(state, event) do
      {:stop, next_state} ->
        {:stop, :normal, :ok, next_state}

      {:continue, next_state, render?} ->
        next_state =
          next_state
          |> maybe_render(render?)
          |> flush_pending_commands()

        {:reply, :ok, next_state}
    end
  end

  def handle_call({:ex_ratatui_runtime_trace, enabled?, limit}, _from, state) do
    next_state =
      state
      |> Map.put(:trace_enabled?, enabled?)
      |> Map.put(:trace_limit, if(enabled?, do: max(limit, 1), else: state.trace_limit))
      |> maybe_clear_trace_events(enabled?)

    {:reply, :ok, next_state}
  end

  @impl true
  def terminate(reason, %__MODULE__{transport: :local, terminal_initialized: true} = state) do
    cancel_subscription_timers(state)
    restore_terminal(state.terminal_ref)
    state.mod.terminate(reason, state.user_state)
    emit_transport_disconnect(state, reason)
    :ok
  end

  def terminate(reason, %__MODULE__{transport: :session, terminal_initialized: true} = state) do
    cancel_subscription_timers(state)

    Telemetry.execute(
      [:session, :lifecycle, :close],
      %{},
      %{mod: state.mod, transport: state.transport, reason: reason}
    )

    Session.close(state.session)
    state.mod.terminate(reason, state.user_state)
    emit_transport_disconnect(state, reason)
    :ok
  end

  def terminate(reason, %__MODULE__{transport: :cell_session, terminal_initialized: true} = state) do
    cancel_subscription_timers(state)

    Telemetry.execute(
      [:session, :lifecycle, :close],
      %{},
      %{mod: state.mod, transport: state.transport, reason: reason}
    )

    CellSession.close(state.cell_session)
    state.mod.terminate(reason, state.user_state)
    emit_transport_disconnect(state, reason)
    :ok
  end

  def terminate(
        reason,
        %__MODULE__{transport: :distributed_server, terminal_initialized: true} = state
      ) do
    cancel_subscription_timers(state)
    state.mod.terminate(reason, state.user_state)
    emit_transport_disconnect(state, reason)
    :ok
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  defp emit_transport_disconnect(%__MODULE__{} = state, reason) do
    Telemetry.execute(
      [:transport, :disconnect],
      %{},
      %{mod: state.mod, transport: state.transport, reason: reason}
    )
  end

  # Cancel any armed subscription timers so pending ticks are not delivered
  # to a restarted process carrying a stale mailbox.
  defp cancel_subscription_timers(%__MODULE__{subscriptions: subs}) do
    Enum.each(subs, fn
      {_id, %{timer_ref: ref}} when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end)
  end

  ## Extracted logic (@doc false, public for testability)

  @doc false
  def handle_poll_result(nil, state), do: {:continue, state, false}
  def handle_poll_result({:error, _}, state), do: {:continue, state, false}
  def handle_poll_result(event, state), do: dispatch_event(state, event)

  @doc false
  def dispatch_event(state, event) do
    state = trace(state, :message, %{source: :event, payload: event})

    meta = %{mod: state.mod, transport: state.transport, event: event}

    result =
      Telemetry.span([:runtime, :event], meta, fn ->
        state.mod.handle_event(event, state.user_state)
      end)

    result
    |> normalize_transition_result()
    |> apply_transition(state)
  end

  @doc false
  def process_poll_result({:stop, state}) do
    state = flush_pending_intents(state)
    {:stop, :normal, state}
  end

  def process_poll_result({:continue, state, render?}) do
    state =
      state
      |> maybe_render(render?)
      |> flush_pending_commands()
      |> flush_pending_intents()
      |> maybe_rearm_poll()

    {:noreply, state}
  end

  @doc false
  # SSH/distributed analogue of process_poll_result that does not re-arm a
  # poll loop — non-local transports get the next event from the mailbox.
  def process_event_result({:stop, state}) do
    state = flush_pending_intents(state)
    {:stop, :normal, state}
  end

  def process_event_result({:continue, state, render?}) do
    state =
      state
      |> maybe_render(render?)
      |> flush_pending_commands()
      |> flush_pending_intents()

    {:noreply, state}
  end

  @doc false
  def resolve_terminal_size(test_mode, terminal_size_fn \\ &ExRatatui.terminal_size/0)

  def resolve_terminal_size({w, h}, _terminal_size_fn), do: {w, h}

  def resolve_terminal_size(nil, terminal_size_fn) when is_function(terminal_size_fn, 0) do
    terminal_size_fn.() |> normalize_size_result()
  end

  @doc false
  def normalize_size_result({w, h}) when is_integer(w) and is_integer(h), do: {w, h}
  def normalize_size_result({:error, _}), do: {80, 24}

  ## Private helpers

  # Shuts down the linked Task.Supervisor that `init/1` started before
  # the transport / mount succeeded. Called from every `{:stop, reason}`
  # branch in `continue_init*` — otherwise the Server crash propagates a
  # link EXIT into the still-running task_sup, which logs its own
  # `GenServer terminating` line with the same reason. Idempotent for
  # callers that don't have a task_sup in their opts (test helpers).
  defp stop_task_supervisor(opts) do
    case Keyword.get(opts, :task_supervisor) do
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: Supervisor.stop(pid, :normal, :infinity)
        :ok

      _ ->
        :ok
    end
  end

  defp init_terminal(nil, focus?, mouse?), do: Native.init_terminal(focus?, mouse?)

  defp init_terminal({width, height}, _focus?, _mouse?),
    do: ExRatatui.init_test_terminal(width, height)

  defp local_polling_enabled?(nil), do: true
  defp local_polling_enabled?({_width, _height}), do: false

  defp restore_terminal(terminal_ref) do
    Native.restore_terminal(terminal_ref)
  rescue
    e ->
      Logger.warning("Failed to restore terminal: #{Exception.message(e)}")
      :ok
  end

  defp do_render(state) do
    {w, h} = current_size(state)
    frame = %Frame{width: w, height: h}
    start_meta = %{mod: state.mod, transport: state.transport}

    :telemetry.span([:ex_ratatui, :render, :frame], start_meta, fn ->
      widgets = state.mod.render(state.user_state, frame)
      draw_widgets(state, widgets)

      next_state =
        state
        |> Map.update!(:render_count, &(&1 + 1))
        |> Map.put(:last_rendered_at, System.system_time(:millisecond))
        |> trace(:render, %{frame: frame, widget_count: length(widgets)})

      {next_state, Map.put(start_meta, :widget_count, length(widgets))}
    end)
  rescue
    e ->
      Telemetry.execute(
        [:render, :dropped],
        %{},
        %{
          mod: state.mod,
          transport: state.transport,
          reason: {:exception, Exception.message(e)}
        }
      )

      Logger.error(
        "ExRatatui render error: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      state
  end

  # also emit [:ex_ratatui, :render, :dropped] when we
  # skip a frame because the previous NIF draw took longer than the poll
  # interval. The draw-error path below is the only dropped-frame source
  # today; future work should add a scheduling gate in process_poll_result/1.

  defp current_size(%__MODULE__{transport: :session, width: w, height: h}), do: {w, h}
  defp current_size(%__MODULE__{transport: :cell_session, width: w, height: h}), do: {w, h}
  defp current_size(%__MODULE__{transport: :distributed_server, width: w, height: h}), do: {w, h}

  defp current_size(%__MODULE__{transport: :local, test_mode: tm, terminal_size_fn: size_fn}) do
    resolve_terminal_size(tm, size_fn || (&ExRatatui.terminal_size/0))
  end

  defp draw_widgets(_state, []), do: :ok

  defp draw_widgets(%__MODULE__{transport: :local, terminal_ref: terminal_ref} = state, widgets) do
    case ExRatatui.draw(terminal_ref, widgets) do
      :ok ->
        :ok

      {:error, reason} ->
        emit_render_dropped(state, reason)
        Logger.error("ExRatatui draw error: #{inspect(reason)}")
    end
  end

  defp draw_widgets(
         %__MODULE__{transport: :session, session: session, writer_fn: writer_fn} = state,
         widgets
       ) do
    case Session.draw(session, widgets) do
      :ok ->
        bytes = Session.take_output(session)
        writer_fn.(bytes)
        :ok

      {:error, reason} ->
        emit_render_dropped(state, reason)
        Logger.error("ExRatatui session draw error: #{inspect(reason)}")
    end
  end

  # Cell-stream analogue of the byte-stream `:session` clause. The
  # writer_fn receives a `%CellSession.Diff{}` instead of bytes — only
  # cells that changed since the last render — keeping the per-frame
  # payload small. The first call after construction (and the first
  # call after any resize) returns the full grid as ops; consumers
  # that need a complete picture from a single frame can reach for
  # `CellSession.take_cells/1` directly via the bare session reference,
  # but the Server itself never needs to.
  defp draw_widgets(
         %__MODULE__{
           transport: :cell_session,
           cell_session: cell_session,
           writer_fn: writer_fn
         } = state,
         widgets
       ) do
    case CellSession.draw(cell_session, widgets) do
      :ok ->
        diff = CellSession.take_cells_diff(cell_session)
        writer_fn.(diff)
        :ok

      {:error, reason} ->
        emit_render_dropped(state, reason)
        Logger.error("ExRatatui cell session draw error: #{inspect(reason)}")
    end
  end

  defp draw_widgets(%__MODULE__{transport: :distributed_server, client_pid: pid}, widgets) do
    send(pid, {:ex_ratatui_draw, snapshot_stateful_widgets(widgets)})
    :ok
  end

  defp emit_render_dropped(%__MODULE__{} = state, reason) do
    Telemetry.execute(
      [:render, :dropped],
      %{},
      %{mod: state.mod, transport: state.transport, reason: reason}
    )
  end

  # NIF resource references (ResourceArc) cannot cross BEAM node boundaries
  # — they're pointers into Rust memory on the local node. Stateful widgets
  # (TextInput, Textarea) hold their mutable state in such references. Before
  # sending a widget list over distribution, we snapshot each stateful widget's
  # NIF state into a plain tuple that Erlang distribution can serialize. The
  # Rust decoder on the client node reconstructs a temporary ResourceArc from
  # the snapshot so the rest of the rendering pipeline stays uniform.
  defp snapshot_stateful_widgets(widgets) do
    Enum.map(widgets, fn
      {%ExRatatui.Widgets.TextInput{state: ref} = widget, rect} when is_reference(ref) ->
        {%{widget | state: ExRatatui.Native.text_input_snapshot(ref)}, rect}

      {%ExRatatui.Widgets.Textarea{state: ref} = widget, rect} when is_reference(ref) ->
        {%{widget | state: ExRatatui.Native.textarea_snapshot(ref)}, rect}

      {%ExRatatui.Widgets.Image{state: ref} = widget, rect} when is_reference(ref) ->
        {%{widget | state: ExRatatui.Native.image_snapshot(ref)}, rect}

      other ->
        other
    end)
  end

  defp runtime_mode(mod) do
    mod.__runtime__()
  end

  defp normalize_mount_result({:ok, user_state}), do: {:ok, user_state, default_runtime_opts()}
  defp normalize_mount_result({:error, reason}), do: {:error, reason}

  defp normalize_mount_result({:ok, user_state, runtime_opts}) do
    {:ok, user_state, normalize_runtime_opts(runtime_opts)}
  end

  defp normalize_mount_result(other) do
    raise ArgumentError, "invalid ExRatatui mount result: #{inspect(other)}"
  end

  defp normalize_transition_result({:noreply, user_state}) do
    {:continue, user_state, default_runtime_opts()}
  end

  defp normalize_transition_result({:noreply, user_state, runtime_opts}) do
    {:continue, user_state, normalize_runtime_opts(runtime_opts)}
  end

  defp normalize_transition_result({:stop, user_state}) do
    {:stop, user_state, default_runtime_opts()}
  end

  defp normalize_transition_result({:stop, user_state, runtime_opts}) do
    {:stop, user_state, normalize_runtime_opts(runtime_opts)}
  end

  defp normalize_transition_result(other) do
    raise ArgumentError, "invalid ExRatatui callback result: #{inspect(other)}"
  end

  defp default_runtime_opts do
    %{
      commands: [],
      intents: [],
      render?: true,
      trace?: nil,
      probe_image_protocol: false
    }
  end

  defp normalize_runtime_opts(runtime_opts) when is_list(runtime_opts) do
    runtime_opts
    |> Enum.into(%{})
    |> normalize_runtime_opts()
  end

  defp normalize_runtime_opts(runtime_opts) when is_map(runtime_opts) do
    %{
      commands: Command.normalize(Map.get(runtime_opts, :commands)),
      intents: normalize_intents(Map.get(runtime_opts, :intents)),
      render?: Map.get(runtime_opts, :render?, true),
      trace?: Map.get(runtime_opts, :trace?),
      probe_image_protocol: Map.get(runtime_opts, :probe_image_protocol, false)
    }
  end

  defp normalize_runtime_opts(other) do
    raise ArgumentError, "invalid runtime opts: #{inspect(other)}"
  end

  # Intents are opaque to ex_ratatui — they're consumer-defined directives
  # (e.g. phoenix_ex_ratatui maps `{:navigate, "/path"}` to push_navigate).
  # Normalisation is just shape validation: must be a list, nil → [].
  defp normalize_intents(nil), do: []
  defp normalize_intents(list) when is_list(list), do: list

  defp normalize_intents(other) do
    raise ArgumentError, "invalid intents (must be a list): #{inspect(other)}"
  end

  defp apply_transition({:continue, user_state, runtime_opts}, state) do
    next_state =
      state
      |> Map.put(:user_state, user_state)
      |> maybe_set_trace(runtime_opts)
      |> reconcile_subscriptions()
      |> queue_commands(runtime_opts)
      |> queue_intents(runtime_opts)

    {:continue, next_state, runtime_opts.render?}
  end

  defp apply_transition({:stop, user_state, runtime_opts}, state) do
    next_state =
      state
      |> Map.put(:user_state, user_state)
      |> maybe_set_trace(runtime_opts)
      |> reconcile_subscriptions()
      |> queue_commands(runtime_opts)
      |> queue_intents(runtime_opts)

    {:stop, next_state}
  end

  defp do_render_if(state, %{render?: false}), do: state
  defp do_render_if(state, _runtime_opts), do: do_render(state)

  defp maybe_render(state, true), do: do_render(state)
  defp maybe_render(state, false), do: state

  defp maybe_rearm_poll(%__MODULE__{transport: :local, polling_enabled?: true} = state) do
    send(self(), :poll)
    state
  end

  defp maybe_rearm_poll(state), do: state

  defp queue_commands(state, %{commands: commands}) do
    %{state | pending_commands: commands}
  end

  defp flush_pending_commands(%__MODULE__{pending_commands: []} = state), do: state

  defp flush_pending_commands(%__MODULE__{pending_commands: commands} = state) do
    state = %{state | pending_commands: []}
    Enum.reduce(commands, state, &run_command/2)
  end

  defp queue_intents(state, %{intents: intents}) do
    %{state | pending_intents: intents}
  end

  # Intents are forwarded to the transport's intent_writer_fn (when set)
  # in the order they were emitted. Transports that don't ship an intent
  # writer (local/SSH/distributed) silently drop them — apps can return
  # intents safely regardless of where they're running.
  defp flush_pending_intents(%__MODULE__{pending_intents: []} = state), do: state

  defp flush_pending_intents(%__MODULE__{pending_intents: _, intent_writer_fn: nil} = state) do
    %{state | pending_intents: []}
  end

  defp flush_pending_intents(
         %__MODULE__{pending_intents: intents, intent_writer_fn: writer} = state
       )
       when is_function(writer, 1) do
    Enum.each(intents, writer)
    %{state | pending_intents: []}
  end

  defp run_command(%Command{kind: :message, message: message}, state) do
    send(self(), message)
    trace(state, :command, %{kind: :message, message: message})
  end

  defp run_command(%Command{kind: :after, delay_ms: delay_ms, message: message}, state) do
    Process.send_after(self(), message, delay_ms)
    trace(state, :command, %{kind: :after, delay_ms: delay_ms, message: message})
  end

  defp run_command(%Command{kind: :async, fun: fun, mapper: mapper}, state) do
    parent = self()

    Task.Supervisor.start_child(state.task_supervisor, fn ->
      result = safe_async_result(fun)
      message = safe_async_mapper_result(mapper, result)
      send(parent, {@async_message, message})
    end)

    state
    |> Map.update!(:active_async_commands, &(&1 + 1))
    |> trace(:command, %{kind: :async})
  end

  defp run_command(%Command{kind: :batch, commands: commands}, state) do
    Enum.reduce(commands, state, &run_command/2)
  end

  defp decrement_async_commands(state) do
    Map.update!(state, :active_async_commands, &max(&1 - 1, 0))
  end

  defp reconcile_subscriptions(%__MODULE__{} = state) do
    desired =
      state.mod.subscriptions(state.user_state)
      |> Subscription.normalize()
      |> Map.new(&{&1.id, &1})

    state =
      Enum.reduce(state.subscriptions, state, fn {id, entry}, acc ->
        reconcile_subscription_entry(acc, id, entry, desired)
      end)

    Enum.reduce(desired, state, fn {id, subscription}, acc ->
      if Map.has_key?(acc.subscriptions, id),
        do: acc,
        else: put_subscription(acc, id, subscription)
    end)
  end

  defp reconcile_subscription_entry(state, id, entry, desired) do
    case Map.get(desired, id) do
      nil ->
        cancel_subscription(state, id, entry)

      subscription ->
        reconcile_desired_subscription(state, id, entry, subscription)
    end
  end

  defp reconcile_desired_subscription(state, id, entry, subscription) do
    if subscriptions_equal?(entry.subscription, subscription) do
      maybe_rearm_subscription(state, id, entry)
    else
      state
      |> cancel_subscription(id, entry)
      |> put_subscription(id, subscription)
    end
  end

  defp maybe_rearm_subscription(state, id, %{subscription: %{kind: :interval}} = entry) do
    if entry.timer_ref do
      state
    else
      put_timer_ref(state, id, arm_subscription(entry.subscription))
    end
  end

  defp maybe_rearm_subscription(state, id, %{subscription: %{kind: :once}, fired?: false} = entry) do
    if entry.timer_ref do
      state
    else
      put_timer_ref(state, id, arm_subscription(entry.subscription))
    end
  end

  defp maybe_rearm_subscription(state, _id, _entry), do: state

  defp put_subscription(state, id, subscription) do
    token = make_ref()
    {timer_ref, token} = arm_subscription(subscription, token)

    entry = %{
      subscription: subscription,
      timer_ref: timer_ref,
      token: token,
      fired?: false
    }

    state
    |> put_in([Access.key(:subscriptions), id], entry)
    |> trace(:subscription, %{action: :start, id: id, kind: subscription.kind})
  end

  defp cancel_subscription(state, id, entry) do
    if entry.timer_ref, do: Process.cancel_timer(entry.timer_ref)

    state
    |> update_in([Access.key(:subscriptions)], &Map.delete(&1, id))
    |> trace(:subscription, %{action: :cancel, id: id, kind: entry.subscription.kind})
  end

  defp put_timer_ref(state, id, {timer_ref, token}) do
    update_in(state.subscriptions[id], fn entry ->
      %{entry | timer_ref: timer_ref, token: token}
    end)
  end

  defp arm_subscription(subscription), do: arm_subscription(subscription, make_ref())

  defp arm_subscription(subscription, token) do
    timer_ref =
      Process.send_after(
        self(),
        {@subscription_message, subscription.id, token},
        subscription.interval_ms
      )

    {timer_ref, token}
  end

  defp dispatch_subscription_tick(id, token, state) do
    case Map.get(state.subscriptions, id) do
      %{token: ^token, subscription: subscription} = entry ->
        next_state =
          put_in(state.subscriptions[id], %{
            entry
            | timer_ref: nil,
              fired?: subscription.kind == :once or entry.fired?
          })

        next_state
        |> trace(:subscription, %{action: :fire, id: id, kind: subscription.kind})
        |> dispatch_info_message(subscription.message)

      _other ->
        {:noreply, state}
    end
  end

  defp dispatch_info_message(state, msg) do
    state = trace(state, :message, %{source: :info, payload: msg})

    meta = %{mod: state.mod, transport: state.transport, msg: msg}

    result =
      Telemetry.span([:runtime, :update], meta, fn ->
        state.mod.handle_info(msg, state.user_state)
      end)

    result
    |> normalize_transition_result()
    |> apply_transition(state)
    |> process_event_result()
  end

  defp subscriptions_equal?(left, right) do
    left.id == right.id and left.kind == right.kind and left.interval_ms == right.interval_ms and
      left.message == right.message
  end

  defp safe_async_result(fun) when is_function(fun, 0) do
    fun.()
  rescue
    exception ->
      {:error, {:exception, Exception.message(exception)}}
  catch
    :exit, reason -> {:error, {:exit, reason}}
    kind, reason -> {:error, {kind, reason}}
  end

  defp safe_async_mapper_result(mapper, result) when is_function(mapper, 1) do
    mapper.(result)
  rescue
    exception ->
      {:error, {:mapper_exception, Exception.message(exception)}}
  catch
    :exit, reason -> {:error, {:mapper_exit, reason}}
    kind, reason -> {:error, {:mapper_catch, {kind, reason}}}
  end

  defp maybe_set_trace(state, %{trace?: nil}), do: state
  defp maybe_set_trace(state, %{trace?: enabled?}), do: Map.put(state, :trace_enabled?, enabled?)

  defp maybe_clear_trace_events(state, true), do: state
  defp maybe_clear_trace_events(state, false), do: %{state | trace_events: []}

  defp runtime_snapshot(state) do
    %{
      mode: state.runtime_mode,
      mod: state.mod,
      transport: state.transport,
      polling_enabled?: state.polling_enabled?,
      dimensions: current_size(state),
      render_count: state.render_count,
      last_rendered_at: state.last_rendered_at,
      trace_enabled?: state.trace_enabled?,
      trace_limit: state.trace_limit,
      trace_events: Enum.reverse(state.trace_events),
      subscription_count: map_size(state.subscriptions),
      subscriptions:
        Enum.map(state.subscriptions, fn {id, entry} ->
          %{
            id: id,
            kind: entry.subscription.kind,
            interval_ms: entry.subscription.interval_ms,
            fired?: entry.fired?,
            active?: not is_nil(entry.timer_ref)
          }
        end),
      active_async_commands: state.active_async_commands
    }
  end

  defp trace(%__MODULE__{trace_enabled?: false} = state, _kind, _details), do: state

  defp trace(%__MODULE__{} = state, kind, details) do
    event = %{
      kind: kind,
      at_ms: System.system_time(:millisecond),
      details: details
    }

    trace_events =
      [event | state.trace_events]
      |> Enum.take(state.trace_limit)

    %{state | trace_events: trace_events}
  end
end
