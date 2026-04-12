defmodule ExRatatui.ServerRuntimeTest do
  use ExUnit.Case, async: true

  alias ExRatatui.{Command, Frame, Runtime, Server, Subscription}

  defmodule ReducerControlApp do
    use ExRatatui.App, runtime: :reducer

    @impl true
    def init(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      scenario = Keyword.get(opts, :scenario, :default)

      state = %{test_pid: test_pid, scenario: scenario, phase: :first, poke_count: 0}

      case scenario do
        :no_render ->
          {:ok, state, render?: false}

        :delayed_command ->
          {:ok, state, commands: [Command.send_after(10, :delayed)]}

        :batch_command ->
          {:ok, state,
           commands: [
             Command.batch([Command.message(:batch_now), Command.send_after(0, :batch_later)])
           ]}

        :trace_api ->
          {:ok, state, trace?: true, commands: [Command.message(:boot)]}

        _other ->
          {:ok, state}
      end
    end

    @impl true
    def render(state, frame) do
      send(state.test_pid, {:rendered, state.scenario, frame})
      []
    end

    @impl true
    def update({:event, :stop_with_opts}, state),
      do: {:stop, %{state | phase: :stopped}, trace?: true}

    def update({:info, :boot}, state) do
      send(state.test_pid, :boot_handled)
      {:noreply, state}
    end

    def update({:info, :delayed}, state) do
      send(state.test_pid, :delayed_seen)
      {:noreply, state}
    end

    def update({:info, :batch_now}, state) do
      send(state.test_pid, :batch_now_seen)
      {:noreply, state}
    end

    def update({:info, :batch_later}, state) do
      send(state.test_pid, :batch_later_seen)
      {:noreply, state}
    end

    def update({:info, :poke}, state) do
      send(state.test_pid, :poke_seen)
      {:noreply, %{state | poke_count: state.poke_count + 1}}
    end

    def update({:info, :once_tick}, state) do
      send(state.test_pid, {:once_tick, state.poke_count})
      {:noreply, state}
    end

    def update({:info, :first_tick}, state) do
      send(state.test_pid, :first_tick_seen)
      {:noreply, %{state | phase: :second}}
    end

    def update({:info, :second_tick}, state) do
      send(state.test_pid, :second_tick_seen)
      {:noreply, state}
    end

    def update({:info, :start_async_raise}, state) do
      {:noreply, state, commands: [Command.async(fn -> raise "boom" end, &{:async_result, &1})]}
    end

    def update({:info, :start_async_exit}, state) do
      {:noreply, state, commands: [Command.async(fn -> exit(:boom) end, &{:async_result, &1})]}
    end

    def update({:info, :start_async_throw}, state) do
      {:noreply, state, commands: [Command.async(fn -> throw(:boom) end, &{:async_result, &1})]}
    end

    def update({:info, :start_async_mapper_raise}, state) do
      {:noreply, state,
       commands: [Command.async(fn -> :ok end, fn _result -> raise "mapper boom" end)]}
    end

    def update({:info, :start_async_mapper_exit}, state) do
      {:noreply, state,
       commands: [Command.async(fn -> :ok end, fn _result -> exit(:mapper_boom) end)]}
    end

    def update({:info, :start_async_mapper_throw}, state) do
      {:noreply, state,
       commands: [Command.async(fn -> :ok end, fn _result -> throw(:mapper_boom) end)]}
    end

    def update({:info, {:async_result, result}}, state) do
      send(state.test_pid, {:async_result, result})
      {:noreply, state}
    end

    def update({:info, {:error, {:mapper_exception, reason}}}, state) do
      send(state.test_pid, {:async_mapper_error, reason})
      {:noreply, state}
    end

    def update({:info, {:error, {:mapper_exit, reason}}}, state) do
      send(state.test_pid, {:async_mapper_exit, reason})
      {:noreply, state}
    end

    def update({:info, {:error, {:mapper_catch, {kind, reason}}}}, state) do
      send(state.test_pid, {:async_mapper_catch, kind, reason})
      {:noreply, state}
    end

    def update({:event, %ExRatatui.Event.Key{} = event}, state) do
      send(state.test_pid, {:event_seen, event})
      {:noreply, state}
    end

    def update(_msg, state), do: {:noreply, state}

    @impl true
    def subscriptions(%{scenario: :changing_interval, phase: :first}) do
      [Subscription.interval(:ticker, 10, :first_tick)]
    end

    def subscriptions(%{scenario: :changing_interval, phase: :second}) do
      [Subscription.interval(:ticker, 20, :second_tick)]
    end

    def subscriptions(%{scenario: :once}) do
      [Subscription.once(:once, 100, :once_tick)]
    end

    def subscriptions(%{scenario: :stale_subscription}) do
      [Subscription.once(:once, 200, :once_tick)]
    end

    def subscriptions(_state), do: []
  end

  defmodule InvalidMountResultApp do
    use ExRatatui.App

    @impl true
    def mount(_opts), do: :bad

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule InvalidCallbackResultApp do
    use ExRatatui.App

    @impl true
    def mount(_opts), do: {:ok, %{}}

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, _state), do: :bad
  end

  defmodule InvalidRuntimeOptsMountApp do
    use ExRatatui.App, runtime: :reducer

    @impl true
    def init(_opts), do: {:ok, %{}, :bad_opts}

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def update(_msg, state), do: {:noreply, state}
  end

  test "Runtime API toggles trace and exposes trace events" do
    {:ok, pid} =
      ReducerControlApp.start_link(
        name: nil,
        scenario: :trace_api,
        test_pid: self(),
        test_mode: {40, 10}
      )

    assert_receive {:rendered, :trace_api, %Frame{width: 40, height: 10}}, 1000
    assert_receive :boot_handled, 1000

    snapshot = Runtime.snapshot(pid)
    assert snapshot.trace_enabled?
    assert snapshot.trace_limit == 200
    assert Runtime.trace_events(pid) == snapshot.trace_events
    assert snapshot.trace_events != []

    assert :ok = Runtime.enable_trace(pid, limit: 0)

    enabled_snapshot = Runtime.snapshot(pid)
    assert enabled_snapshot.trace_enabled?
    assert enabled_snapshot.trace_limit == 1
    assert enabled_snapshot.trace_events != []

    assert :ok = Runtime.disable_trace(pid)

    disabled_snapshot = Runtime.snapshot(pid)
    refute disabled_snapshot.trace_enabled?
    assert disabled_snapshot.trace_limit == 1
    assert disabled_snapshot.trace_events == []

    assert :ok = Runtime.enable_trace(pid)

    reenabled_snapshot = Runtime.snapshot(pid)
    assert reenabled_snapshot.trace_enabled?
    assert reenabled_snapshot.trace_limit == 200

    GenServer.stop(pid)
  end

  test "continue_init raises on invalid mount results" do
    assert_raise ArgumentError, "invalid ExRatatui mount result: :bad", fn ->
      Server.continue_init(make_ref(), mod: InvalidMountResultApp, test_mode: {40, 10})
    end
  end

  test "continue_init raises on invalid reducer runtime opts" do
    assert_raise ArgumentError, "invalid runtime opts: :bad_opts", fn ->
      Server.continue_init(make_ref(), mod: InvalidRuntimeOptsMountApp, test_mode: {40, 10})
    end
  end

  test "dispatch_event raises on invalid callback results" do
    state = build_server_state(InvalidCallbackResultApp, %{})

    assert_raise ArgumentError, "invalid ExRatatui callback result: :bad", fn ->
      Server.dispatch_event(state, :bad_event)
    end
  end

  test "reducer stop tuples can carry runtime opts" do
    state =
      build_server_state(ReducerControlApp, %{
        test_pid: self(),
        scenario: :default,
        phase: :first,
        poke_count: 0
      })

    assert {:stop, next_state} = Server.dispatch_event(state, :stop_with_opts)
    assert next_state.user_state.phase == :stopped
    assert next_state.trace_enabled?
  end

  test "render?: false skips the initial render until a synthetic event is injected" do
    {:ok, pid} =
      ReducerControlApp.start_link(
        name: nil,
        scenario: :no_render,
        test_pid: self(),
        test_mode: {40, 10}
      )

    refute_receive {:rendered, :no_render, _frame}, 50
    assert Runtime.snapshot(pid).polling_enabled? == false

    event = %ExRatatui.Event.Key{code: "a", modifiers: [], kind: "press"}
    assert :ok = Runtime.inject_event(pid, event)

    assert_receive {:event_seen, ^event}, 1000
    assert_receive {:rendered, :no_render, %Frame{width: 40, height: 10}}, 1000

    GenServer.stop(pid)
  end

  test "send_after commands route delayed messages back through update" do
    {:ok, pid} =
      ReducerControlApp.start_link(
        name: nil,
        scenario: :delayed_command,
        test_pid: self(),
        test_mode: {40, 10}
      )

    assert_receive {:rendered, :delayed_command, _frame}, 1000
    assert_receive :delayed_seen, 1000

    GenServer.stop(pid)
  end

  test "batch commands run each nested command" do
    {:ok, pid} =
      ReducerControlApp.start_link(
        name: nil,
        scenario: :batch_command,
        test_pid: self(),
        test_mode: {40, 10}
      )

    assert_receive {:rendered, :batch_command, _frame}, 1000
    assert_receive :batch_now_seen, 1000
    assert_receive :batch_later_seen, 1000

    GenServer.stop(pid)
  end

  test "process_event_result executes pending batch commands" do
    state =
      build_server_state(
        ReducerControlApp,
        %{test_pid: self(), scenario: :default, phase: :first, poke_count: 0},
        pending_commands: [
          Command.batch([Command.message(:batched_now), Command.send_after(0, :batched_later)])
        ]
      )

    assert {:noreply, next_state} = Server.process_event_result({:continue, state, false})
    assert next_state.pending_commands == []
    assert_receive :batched_now, 1000
    assert_receive :batched_later, 1000
  end

  test "subscription reconciliation replaces changed subscriptions" do
    {:ok, pid} =
      ReducerControlApp.start_link(
        name: nil,
        scenario: :changing_interval,
        test_pid: self(),
        test_mode: {40, 10}
      )

    assert_receive {:rendered, :changing_interval, _frame}, 1000
    assert_receive :first_tick_seen, 1000

    snapshot = Runtime.snapshot(pid)
    assert [%{id: :ticker, interval_ms: 20}] = snapshot.subscriptions

    assert_receive :second_tick_seen, 1000

    GenServer.stop(pid)
  end

  test "once subscriptions stay armed, can be manually rearmed, and do not refire once fired" do
    {:ok, pid} =
      ReducerControlApp.start_link(
        name: nil,
        scenario: :once,
        test_pid: self(),
        test_mode: {40, 10}
      )

    assert_receive {:rendered, :once, _frame}, 1000

    send(pid, :poke)
    assert_receive :poke_seen, 1000

    snapshot = Runtime.snapshot(pid)
    assert [%{id: :once, active?: true, fired?: false}] = snapshot.subscriptions

    state = :sys.get_state(pid)
    entry = state.subscriptions[:once]
    Process.cancel_timer(entry.timer_ref)

    :sys.replace_state(pid, fn server_state ->
      put_in(server_state.subscriptions[:once], %{entry | timer_ref: nil})
    end)

    send(pid, :poke)
    assert_receive :poke_seen, 1000
    assert_receive {:once_tick, 2}, 1000

    snapshot = Runtime.snapshot(pid)
    assert [%{id: :once, active?: false, fired?: true}] = snapshot.subscriptions
    refute_receive {:once_tick, _count}, 150

    GenServer.stop(pid)
  end

  test "stale subscription ticks are ignored" do
    {:ok, pid} =
      ReducerControlApp.start_link(
        name: nil,
        scenario: :stale_subscription,
        test_pid: self(),
        test_mode: {40, 10}
      )

    assert_receive {:rendered, :stale_subscription, _frame}, 1000

    send(pid, {:__ex_ratatui_subscription_tick__, :once, make_ref()})
    refute_receive {:once_tick, _count}, 50

    GenServer.stop(pid)
  end

  test "async command failures are normalized by failure kind" do
    {:ok, pid} =
      ReducerControlApp.start_link(
        name: nil,
        scenario: :default,
        test_pid: self(),
        test_mode: {40, 10}
      )

    assert_receive {:rendered, :default, _frame}, 1000

    send(pid, :start_async_raise)
    assert_receive {:async_result, {:error, {:exception, "boom"}}}, 1000

    send(pid, :start_async_exit)
    assert_receive {:async_result, {:error, {:exit, :boom}}}, 1000

    send(pid, :start_async_throw)
    assert_receive {:async_result, {:error, {:throw, :boom}}}, 1000

    GenServer.stop(pid)
  end

  test "async mapper failures are normalized and active_async_commands decrements" do
    {:ok, pid} =
      ReducerControlApp.start_link(
        name: nil,
        scenario: :default,
        test_pid: self(),
        test_mode: {40, 10}
      )

    assert_receive {:rendered, :default, _frame}, 1000

    send(pid, :start_async_mapper_raise)
    assert_receive {:async_mapper_error, "mapper boom"}, 1000

    send(pid, :start_async_mapper_exit)
    assert_receive {:async_mapper_exit, :mapper_boom}, 1000

    send(pid, :start_async_mapper_throw)
    assert_receive {:async_mapper_catch, :throw, :mapper_boom}, 1000

    assert Runtime.snapshot(pid).active_async_commands == 0

    GenServer.stop(pid)
  end

  defp build_server_state(mod, user_state, attrs \\ []) do
    struct(
      Server,
      Keyword.merge(
        [
          mod: mod,
          user_state: user_state,
          runtime_mode: mod.__runtime__(),
          test_mode: {40, 10},
          terminal_ref: make_ref(),
          terminal_initialized: true
        ],
        attrs
      )
    )
  end
end
