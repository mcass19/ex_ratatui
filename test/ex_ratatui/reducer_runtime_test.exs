defmodule ExRatatui.ReducerRuntimeTest do
  use ExUnit.Case, async: true

  alias ExRatatui.{Command, Frame, Runtime, Subscription}

  defmodule ReducerApp do
    use ExRatatui.App, runtime: :reducer

    @impl true
    def init(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:reducer_init, opts})

      {:ok, %{test_pid: test_pid, events: [], ticks: 0},
       commands: [Command.message(:boot)], trace?: true}
    end

    @impl true
    def render(state, frame) do
      send(state.test_pid, {:reducer_render, state.events, frame})
      []
    end

    @impl true
    def update({:info, :boot}, state) do
      send(state.test_pid, :boot_handled)
      {:noreply, %{state | events: [:boot | state.events]}}
    end

    def update({:event, event}, state) do
      send(state.test_pid, {:event_seen, event})
      {:noreply, %{state | events: [{:event, event.code} | state.events]}}
    end

    def update({:info, :tick}, state) do
      next = state.ticks + 1
      send(state.test_pid, {:tick_seen, next})
      {:noreply, %{state | ticks: next, events: [{:tick, next} | state.events]}}
    end

    def update({:info, :start_async}, state) do
      {:noreply, state,
       commands: [
         Command.async(fn -> 42 end, fn result -> {:async_result, result} end)
       ]}
    end

    def update({:info, {:async_result, result}}, state) do
      send(state.test_pid, {:async_seen, result})
      {:noreply, %{state | events: [{:async, result} | state.events]}}
    end

    def update({:info, other}, state) do
      {:noreply, %{state | events: [other | state.events]}}
    end

    @impl true
    def subscriptions(%{ticks: ticks}) when ticks < 2 do
      [Subscription.interval(:ticker, 10, :tick)]
    end

    def subscriptions(_state), do: []
  end

  test "reducer apps compile through ExRatatui.App and start normally" do
    assert function_exported?(ReducerApp, :mount, 1)
    assert function_exported?(ReducerApp, :handle_event, 2)
    assert function_exported?(ReducerApp, :handle_info, 2)
    assert function_exported?(ReducerApp, :subscriptions, 1)

    {:ok, pid} = ReducerApp.start_link(name: nil, test_pid: self(), test_mode: {40, 10})

    assert_receive {:reducer_init, _opts}, 1000
    assert_receive {:reducer_render, _events, %Frame{width: 40, height: 10}}, 1000
    assert_receive :boot_handled, 1000

    GenServer.stop(pid)
  end

  test "interval subscriptions are reconciled and stop when no longer desired" do
    {:ok, pid} = ReducerApp.start_link(name: nil, test_pid: self(), test_mode: {40, 10})

    assert_receive {:tick_seen, 1}, 1000
    assert_receive {:tick_seen, 2}, 1000
    refute_receive {:tick_seen, 3}, 100

    snapshot = Runtime.snapshot(pid)
    assert snapshot.subscription_count == 0

    GenServer.stop(pid)
  end

  test "commands can run async work and route the result back through update" do
    {:ok, pid} = ReducerApp.start_link(name: nil, test_pid: self(), test_mode: {40, 10})

    send(pid, :start_async)
    assert_receive {:async_seen, 42}, 1000

    GenServer.stop(pid)
  end

  test "runtime snapshot exposes trace and reducer runtime metadata" do
    {:ok, pid} = ReducerApp.start_link(name: nil, test_pid: self(), test_mode: {40, 10})

    send(pid, :start_async)
    assert_receive {:async_seen, 42}, 1000

    snapshot = Runtime.snapshot(pid)

    assert snapshot.mode == :reducer
    assert snapshot.trace_enabled?
    assert snapshot.render_count >= 1
    assert is_list(snapshot.trace_events)
    assert Enum.any?(snapshot.trace_events, &(&1.kind == :message))

    GenServer.stop(pid)
  end
end
