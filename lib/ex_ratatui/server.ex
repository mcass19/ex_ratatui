defmodule ExRatatui.Server do
  @moduledoc false

  use GenServer

  require Logger

  alias ExRatatui.Command
  alias ExRatatui.Frame
  alias ExRatatui.Native
  alias ExRatatui.Session
  alias ExRatatui.Subscription

  defstruct [
    :mod,
    :user_state,
    :test_mode,
    :terminal_ref,
    :terminal_size_fn,
    :session,
    :writer_fn,
    :client_pid,
    :width,
    :height,
    polling_enabled?: false,
    pending_commands: [],
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

    case Keyword.get(opts, :transport, :local) do
      :local ->
        test_mode = Keyword.get(opts, :test_mode)
        init_terminal(test_mode) |> continue_init(opts)

      {:ssh, %Session{} = session, writer_fn} when is_function(writer_fn, 1) ->
        continue_init_ssh(session, writer_fn, opts)

      {:distributed_server, client_pid, width, height}
      when is_pid(client_pid) and is_integer(width) and is_integer(height) ->
        continue_init_distributed_server(client_pid, width, height, opts)
    end
  end

  @doc false
  def continue_init({:error, reason}, _opts), do: {:stop, {:terminal_init_failed, reason}}

  def continue_init(terminal_ref, opts) do
    mod = Keyword.fetch!(opts, :mod)
    poll_interval = Keyword.get(opts, :poll_interval, 16)
    test_mode = Keyword.get(opts, :test_mode)
    # Internal test seam for deterministic live-mode renders without
    # changing production terminal-size behavior.
    terminal_size_fn = Keyword.get(opts, :terminal_size_fn, &ExRatatui.terminal_size/0)

    case normalize_mount_result(mod.mount(opts)) do
      {:ok, user_state, runtime_opts} ->
        state = %__MODULE__{
          mod: mod,
          user_state: user_state,
          poll_interval: poll_interval,
          polling_enabled?: local_polling_enabled?(test_mode),
          test_mode: test_mode,
          terminal_ref: terminal_ref,
          terminal_size_fn: terminal_size_fn,
          terminal_initialized: true,
          runtime_mode: runtime_mode(mod)
        }

        state =
          state
          |> maybe_set_trace(runtime_opts)
          |> reconcile_subscriptions()
          |> queue_commands(runtime_opts)
          |> do_render_if(runtime_opts)

        state =
          state
          |> flush_pending_commands()
          |> maybe_rearm_poll()

        {:ok, state}

      {:error, reason} ->
        restore_terminal(terminal_ref)
        {:stop, reason}
    end
  end

  @doc false
  # SSH transport init: the Session is created externally by the SSH
  # channel (which knows how to ship bytes back to the client), so this
  # path never touches the OS terminal. mount/1 sees augmented opts so an
  # app can opt into per-client behaviour without breaking the local case.
  def continue_init_ssh(%Session{} = session, writer_fn, opts) do
    mod = Keyword.fetch!(opts, :mod)
    {w, h} = Session.size(session)
    augmented_opts = augment_ssh_mount_opts(opts, w, h)

    case normalize_mount_result(mod.mount(augmented_opts)) do
      {:ok, user_state, runtime_opts} ->
        state = %__MODULE__{
          mod: mod,
          user_state: user_state,
          transport: :ssh,
          session: session,
          writer_fn: writer_fn,
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
          |> do_render_if(runtime_opts)

        state = flush_pending_commands(state)
        {:ok, state}

      {:error, reason} ->
        Session.close(session)
        {:stop, reason}
    end
  end

  @doc false
  # Distribution-attach server init: the remote client rendered locally,
  # so no Rust resource is needed here. We send widget lists as BEAM
  # terms and the client draws them with its own TerminalResource.
  def continue_init_distributed_server(client_pid, width, height, opts) do
    mod = Keyword.fetch!(opts, :mod)
    Process.monitor(client_pid)
    augmented_opts = augment_distributed_mount_opts(opts, width, height)

    case normalize_mount_result(mod.mount(augmented_opts)) do
      {:ok, user_state, runtime_opts} ->
        state = %__MODULE__{
          mod: mod,
          user_state: user_state,
          transport: :distributed_server,
          client_pid: client_pid,
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
          |> do_render_if(runtime_opts)

        state = flush_pending_commands(state)
        {:ok, state}

      {:error, reason} ->
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
  def augment_ssh_mount_opts(opts, width, height) do
    opts
    |> Keyword.put(:transport, :ssh)
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
      when transport in [:ssh, :distributed_server] do
    state
    |> dispatch_event(event)
    |> process_event_result()
  end

  def handle_info({:ex_ratatui_resize, w, h}, %__MODULE__{transport: transport} = state)
      when transport in [:ssh, :distributed_server] do
    {:noreply, do_render(%{state | width: w, height: h})}
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
    restore_terminal(state.terminal_ref)
    state.mod.terminate(reason, state.user_state)
    :ok
  end

  def terminate(reason, %__MODULE__{transport: :ssh, terminal_initialized: true} = state) do
    Session.close(state.session)
    state.mod.terminate(reason, state.user_state)
    :ok
  end

  def terminate(
        reason,
        %__MODULE__{transport: :distributed_server, terminal_initialized: true} = state
      ) do
    state.mod.terminate(reason, state.user_state)
    :ok
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  ## Extracted logic (@doc false, public for testability)

  @doc false
  def handle_poll_result(nil, state), do: {:continue, state, false}
  def handle_poll_result({:error, _}, state), do: {:continue, state, false}
  def handle_poll_result(event, state), do: dispatch_event(state, event)

  @doc false
  def dispatch_event(state, event) do
    state = trace(state, :message, %{source: :event, payload: event})

    state.mod.handle_event(event, state.user_state)
    |> normalize_transition_result()
    |> apply_transition(state)
  end

  @doc false
  def process_poll_result({:stop, state}), do: {:stop, :normal, state}

  def process_poll_result({:continue, state, render?}) do
    state =
      state
      |> maybe_render(render?)
      |> flush_pending_commands()
      |> maybe_rearm_poll()

    {:noreply, state}
  end

  @doc false
  # SSH/distributed analogue of process_poll_result that does not re-arm a
  # poll loop — non-local transports get the next event from the mailbox.
  def process_event_result({:stop, state}), do: {:stop, :normal, state}

  def process_event_result({:continue, state, render?}) do
    state =
      state
      |> maybe_render(render?)
      |> flush_pending_commands()

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

  defp init_terminal(nil), do: Native.init_terminal()
  defp init_terminal({width, height}), do: ExRatatui.init_test_terminal(width, height)

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

    widgets = state.mod.render(state.user_state, frame)
    draw_widgets(state, widgets)

    state
    |> Map.update!(:render_count, &(&1 + 1))
    |> Map.put(:last_rendered_at, System.system_time(:millisecond))
    |> trace(:render, %{frame: frame, widget_count: length(widgets)})
  rescue
    e ->
      Logger.error(
        "ExRatatui render error: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      state
  end

  defp current_size(%__MODULE__{transport: :ssh, width: w, height: h}), do: {w, h}
  defp current_size(%__MODULE__{transport: :distributed_server, width: w, height: h}), do: {w, h}

  defp current_size(%__MODULE__{transport: :local, test_mode: tm, terminal_size_fn: size_fn}) do
    resolve_terminal_size(tm, size_fn || (&ExRatatui.terminal_size/0))
  end

  defp draw_widgets(_state, []), do: :ok

  defp draw_widgets(%__MODULE__{transport: :local, terminal_ref: terminal_ref}, widgets) do
    case ExRatatui.draw(terminal_ref, widgets) do
      :ok -> :ok
      {:error, reason} -> Logger.error("ExRatatui draw error: #{inspect(reason)}")
    end
  end

  defp draw_widgets(
         %__MODULE__{transport: :ssh, session: session, writer_fn: writer_fn},
         widgets
       ) do
    case Session.draw(session, widgets) do
      :ok ->
        bytes = Session.take_output(session)
        writer_fn.(bytes)
        :ok

      {:error, reason} ->
        Logger.error("ExRatatui session draw error: #{inspect(reason)}")
    end
  end

  defp draw_widgets(%__MODULE__{transport: :distributed_server, client_pid: pid}, widgets) do
    send(pid, {:ex_ratatui_draw, widgets})
    :ok
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
    %{commands: [], render?: true, trace?: nil}
  end

  defp normalize_runtime_opts(runtime_opts) when is_list(runtime_opts) do
    runtime_opts
    |> Enum.into(%{})
    |> normalize_runtime_opts()
  end

  defp normalize_runtime_opts(runtime_opts) when is_map(runtime_opts) do
    %{
      commands:
        Command.normalize(Map.get(runtime_opts, :commands) || Map.get(runtime_opts, "commands")),
      render?: Map.get(runtime_opts, :render?, Map.get(runtime_opts, "render?", true)),
      trace?: Map.get(runtime_opts, :trace?, Map.get(runtime_opts, "trace?"))
    }
  end

  defp normalize_runtime_opts(other) do
    raise ArgumentError, "invalid runtime opts: #{inspect(other)}"
  end

  defp apply_transition({:continue, user_state, runtime_opts}, state) do
    next_state =
      state
      |> Map.put(:user_state, user_state)
      |> maybe_set_trace(runtime_opts)
      |> reconcile_subscriptions()
      |> queue_commands(runtime_opts)

    {:continue, next_state, runtime_opts.render?}
  end

  defp apply_transition({:stop, user_state, runtime_opts}, state) do
    next_state =
      state
      |> Map.put(:user_state, user_state)
      |> maybe_set_trace(runtime_opts)
      |> reconcile_subscriptions()
      |> queue_commands(runtime_opts)

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

    Task.start(fn ->
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

    state.mod.handle_info(msg, state.user_state)
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
