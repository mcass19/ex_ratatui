defmodule ExRatatui.ServerTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Frame

  defmodule TestApp do
    use ExRatatui.App

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:mounted, opts})
      {:ok, %{test_pid: test_pid, render_count: 0}}
    end

    @impl true
    def render(state, frame) do
      send(state.test_pid, {:rendered, state.render_count, frame})
      []
    end

    @impl true
    def handle_event(event, state) do
      send(state.test_pid, {:event, event})
      {:noreply, state}
    end

    @impl true
    def handle_info(msg, state) do
      send(state.test_pid, {:info, msg})
      {:noreply, state}
    end
  end

  describe "start_link/1" do
    test "starts the server and calls mount" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      assert_receive {:mounted, _opts}, 1000
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "calls render after mount" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      assert_receive {:mounted, _opts}, 1000
      assert_receive {:rendered, 0, %Frame{width: 80, height: 24}}, 1000

      GenServer.stop(pid)
    end
  end

  describe "shutdown" do
    test "terminal is restored on normal stop" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      assert_receive {:mounted, _opts}, 1000

      ref = Process.monitor(pid)
      GenServer.stop(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  describe "handle_info forwarding" do
    test "non-poll messages forwarded to app module" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      assert_receive {:mounted, _opts}, 1000

      send(pid, {:custom_message, "hello"})
      assert_receive {:info, {:custom_message, "hello"}}, 1000

      GenServer.stop(pid)
    end
  end
end
