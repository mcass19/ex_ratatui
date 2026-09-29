defmodule ExRatatui.Server.RenderCoalescingTest do
  @moduledoc """
  Renders are merged while the runtime's mailbox is busy: a transition that
  finds more messages queued defers its render to a single marker queued
  behind them, so a burst of N messages costs one frame instead of N.
  """

  use ExUnit.Case, async: true

  alias ExRatatui.Event.Key
  alias ExRatatui.Runtime
  alias ExRatatui.Server
  alias ExRatatui.Test.Mailbox

  defmodule CountingApp do
    use ExRatatui.App

    @impl true
    def mount(opts), do: {:ok, %{test_pid: Keyword.fetch!(opts, :test_pid), count: 0}}

    @impl true
    def render(state, _frame) do
      send(state.test_pid, {:rendered, state.count})
      []
    end

    @impl true
    def handle_event(%Key{code: "q"}, state), do: {:noreply, state, render?: false}
    def handle_event(%Key{code: "b"}, state), do: {:noreply, %{state | count: state.count + 1}}
    def handle_event(_event, state), do: {:noreply, state}

    @impl true
    def handle_info(msg, state) do
      send(state.test_pid, {:info, msg})

      case msg do
        :bump -> {:noreply, %{state | count: state.count + 1}}
        :quiet -> {:noreply, %{state | count: state.count + 1}, render?: false}
        # The stopping state is never drawn; 100 makes it easy to tell apart.
        :stop -> {:stop, %{state | count: state.count + 100}}
      end
    end
  end

  defp start(transport \\ [test_mode: {20, 5}]) do
    {:ok, pid} = Server.start_link([mod: CountingApp, name: nil, test_pid: self()] ++ transport)
    assert_receive {:rendered, 0}, 1000
    pid
  end

  # Queues `msgs` while the server is suspended so it finds them all waiting,
  # then waits until it has worked through them and the marker they queued.
  # Two round trips: the first `get_state` can be queued before the marker
  # (the server only sends it once it handles the first message), but the
  # second is sent after the first returns, so it always lands behind it.
  defp burst(pid, msgs) do
    :ok = :sys.suspend(pid)
    Enum.each(msgs, &send(pid, &1))
    :ok = :sys.resume(pid)
    _ = :sys.get_state(pid)
    :sys.get_state(pid)
  end

  defp render_count(pid), do: Runtime.snapshot(pid).render_count

  defp drain_renders(acc \\ []) do
    receive do
      {:rendered, count} -> drain_renders([count | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "an idle message renders right away" do
    pid = start()
    send(pid, :bump)
    assert_receive {:rendered, 1}, 1000
    refute :sys.get_state(pid).render_pending?
    GenServer.stop(pid)
  end

  test "a burst renders once, with the final state" do
    pid = start()
    burst(pid, List.duplicate(:bump, 50))

    assert drain_renders() == [50]
    assert render_count(pid) == 2
    refute :sys.get_state(pid).render_pending?
    GenServer.stop(pid)
  end

  test "the render marker never reaches the app" do
    pid = start()
    burst(pid, List.duplicate(:bump, 10))

    for _ <- 1..10, do: assert_received({:info, :bump})
    refute_received {:info, _}
    GenServer.stop(pid)
  end

  test "a burst of remote key events renders once" do
    pid = start(transport: {:distributed_server, self(), 20, 5})

    key = %Key{code: "b", modifiers: [], kind: "press"}
    burst(pid, List.duplicate({:ex_ratatui_event, key}, 20))

    assert drain_renders() == [20]
    assert render_count(pid) == 2
    GenServer.stop(pid)
  end

  test "render?: false transitions don't queue a render" do
    pid = start()
    burst(pid, List.duplicate(:quiet, 10))

    assert drain_renders() == []
    assert render_count(pid) == 1
    refute :sys.get_state(pid).render_pending?
    GenServer.stop(pid)
  end

  test "a marker is a no-op once another render has covered it" do
    pid = start()
    :ok = :sys.suspend(pid)
    send(pid, :bump)
    send(pid, :bump)

    # inject_event is a call, and renders synchronously; queue it behind the
    # two bumps so it lands between them and the marker the first bump queues.
    key = %Key{code: "x", modifiers: [], kind: "press"}
    task = Task.async(fn -> Runtime.inject_event(pid, key) end)
    Mailbox.wait_for_len(pid, 3)

    :ok = :sys.resume(pid)
    assert :ok = Task.await(task)
    _ = :sys.get_state(pid)

    assert drain_renders() == [2]
    assert render_count(pid) == 2
    GenServer.stop(pid)
  end

  test "inject_event renders synchronously unless the transition opts out" do
    pid = start()

    assert :ok = Runtime.inject_event(pid, %Key{code: "x", modifiers: [], kind: "press"})
    assert render_count(pid) == 2

    assert :ok = Runtime.inject_event(pid, %Key{code: "q", modifiers: [], kind: "press"})
    assert render_count(pid) == 2
    GenServer.stop(pid)
  end

  test "a stop draws the frame still owed to earlier transitions" do
    pid = start()
    ref = Process.monitor(pid)

    :ok = :sys.suspend(pid)
    Enum.each([:bump, :bump, :stop], &send(pid, &1))
    :ok = :sys.resume(pid)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    assert drain_renders() == [2]
  end

  test "a stop with no render pending draws nothing" do
    pid = start()
    ref = Process.monitor(pid)

    send(pid, :stop)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    assert drain_renders() == []
  end

  test "a stray marker without a pending render does nothing" do
    pid = start()
    send(pid, :__ex_ratatui_render__)
    _ = :sys.get_state(pid)

    assert render_count(pid) == 1
    refute_received {:info, _}
    GenServer.stop(pid)
  end
end
