defmodule ExRatatui.ServerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ExRatatui.Frame
  alias ExRatatui.Runtime
  alias ExRatatui.Test.ServerApps.Echo, as: TestApp
  alias ExRatatui.Test.ServerApps.{FailingMount, StopOnAnyEvent}

  @doc false
  def __forward_connect__(_event, _measurements, meta, test_pid) do
    send(test_pid, {:telemetry_connect, meta})
  end

  defmodule RenderingApp do
    use ExRatatui.App

    alias ExRatatui.Layout.Rect
    alias ExRatatui.Widgets.Paragraph

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      {:ok, %{test_pid: test_pid}}
    end

    @impl true
    def render(state, frame) do
      send(state.test_pid, :rendered)

      [
        {%Paragraph{text: "Hello from render"},
         %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
      ]
    end

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule CrashRenderApp do
    use ExRatatui.App

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      {:ok, %{test_pid: test_pid, crash: true}}
    end

    @impl true
    def render(%{crash: true}, _frame) do
      raise "render boom"
    end

    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule DrawErrorApp do
    use ExRatatui.App

    alias ExRatatui.Layout.Rect
    alias ExRatatui.Widgets.Paragraph

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:mounted, self()})
      {:ok, %{test_pid: test_pid}}
    end

    @impl true
    def render(state, frame) do
      send(state.test_pid, :rendered)

      [
        {%Paragraph{text: "Hello"}, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
      ]
    end

    @impl true
    def handle_event(_event, state), do: {:noreply, state}

    @impl true
    def handle_info(:trigger_render, state) do
      {:noreply, state}
    end

    def handle_info(_msg, state), do: {:noreply, state}
  end

  defmodule StopOnInfoApp do
    use ExRatatui.App

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      {:ok, %{test_pid: test_pid}}
    end

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, state), do: {:noreply, state}

    @impl true
    def handle_info(:stop_now, state), do: {:stop, state}
    def handle_info(_msg, state), do: {:noreply, state}
  end

  defmodule TerminateApp do
    use ExRatatui.App

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      {:ok, %{test_pid: test_pid}}
    end

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, state), do: {:noreply, state}

    @impl true
    def terminate(reason, state) do
      send(state.test_pid, {:terminated, reason})
      :ok
    end
  end

  describe "local-terminal opts (mouse_capture, focus_events)" do
    setup do
      handler_id = "connect-test-#{inspect(self())}-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:ex_ratatui, :transport, :connect, :start],
        &__MODULE__.__forward_connect__/4,
        self()
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "defaults focus_events and mouse_capture to false on the connect span metadata" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      assert_receive {:telemetry_connect,
                      %{transport: :local, focus_events: false, mouse_capture: false}},
                     1000

      GenServer.stop(pid)
    end

    test "passes focus_events and mouse_capture opts through to the connect span" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24},
          focus_events: true,
          mouse_capture: true
        )

      assert_receive {:telemetry_connect,
                      %{transport: :local, focus_events: true, mouse_capture: true}},
                     1000

      GenServer.stop(pid)
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

    test "handle_info returning {:stop, state} shuts down the server" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: StopOnInfoApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      ref = Process.monitor(pid)
      send(pid, :stop_now)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  describe "terminate callback" do
    test "terminate/2 is called on normal stop" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TerminateApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      ref = Process.monitor(pid)
      GenServer.stop(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
      assert_receive {:terminated, :normal}, 1000
    end
  end

  describe "named start_link" do
    test "starts with a registered name" do
      name = :"test_server_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: name,
          test_pid: self(),
          test_mode: {80, 24}
        )

      assert_receive {:mounted, _opts}, 1000
      assert Process.whereis(name) == pid

      GenServer.stop(pid)
    end
  end

  describe "mount failure" do
    test "server stops when mount returns {:error, reason}" do
      Process.flag(:trap_exit, true)

      capture_log(fn ->
        assert {:error, :mount_failed} =
                 ExRatatui.Server.start_link(
                   mod: FailingMount,
                   name: nil,
                   test_mode: {80, 24}
                 )
      end)
    end

    test "mount failure does not leak a linked Task.Supervisor crash log" do
      # Regression: init/1 used to start a Task.Supervisor linked to the
      # Server before mount/1 ran. When mount returned {:error, reason}
      # the Server crashed with that reason and the linked task_sup
      # received the EXIT, terminated with the same reason, and logged
      # its own `GenServer terminating` line. The fix stops the
      # task_sup in each failure branch before returning {:stop, _}.
      Process.flag(:trap_exit, true)

      log =
        capture_log(fn ->
          assert {:error, :mount_failed} =
                   ExRatatui.Server.start_link(
                     mod: FailingMount,
                     name: nil,
                     test_mode: {80, 24}
                   )
        end)

      refute log =~ "GenServer", "expected no GenServer crash log, got:\n#{log}"
      refute log =~ "Task.Supervisor", "expected no Task.Supervisor log, got:\n#{log}"
    end

    test "server stops when terminal init fails (no TTY)" do
      Process.flag(:trap_exit, true)

      # Without test_mode, init_terminal(nil) calls Native.init_terminal()
      # which fails in headless CI — covering the {:error, reason} branch
      result =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self()
        )

      case result do
        {:error, {:terminal_init_failed, _}} ->
          # Expected in CI: no TTY available
          :ok

        {:ok, pid} ->
          # Has a real TTY (local dev) — just clean up
          GenServer.stop(pid)
      end
    end
  end

  describe "rendering with widgets" do
    test "server draws non-empty widget list from render" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: RenderingApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      assert_receive :rendered, 1000

      GenServer.stop(pid)
    end
  end

  describe "handle_poll_result/2" do
    test "nil returns continue without render" do
      state = build_server_state(TestApp, %{test_pid: self()})
      assert {:continue, ^state, false} = ExRatatui.Server.handle_poll_result(nil, state)
    end

    test "error returns continue without render" do
      state = build_server_state(TestApp, %{test_pid: self()})

      assert {:continue, ^state, false} =
               ExRatatui.Server.handle_poll_result({:error, "fail"}, state)
    end

    test "event dispatches to app module" do
      state = build_server_state(TestApp, %{test_pid: self(), count: 0})
      event = %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}
      assert {:continue, _new_state, true} = ExRatatui.Server.handle_poll_result(event, state)
      assert_receive {:event, ^event}
    end
  end

  describe "dispatch_event/2" do
    test "noreply returns continue with render flag" do
      state = build_server_state(TestApp, %{test_pid: self(), count: 0})
      event = %ExRatatui.Event.Key{code: "a", modifiers: [], kind: "press"}
      assert {:continue, new_state, true} = ExRatatui.Server.dispatch_event(state, event)
      assert_receive {:event, ^event}
      assert new_state.mod == TestApp
    end

    test "stop returns stop tuple" do
      state = build_server_state(StopOnAnyEvent, %{test_pid: self()})
      event = %{stop: true}
      assert {:stop, new_state} = ExRatatui.Server.dispatch_event(state, event)
      assert new_state.user_state == %{test_pid: self()}
    end
  end

  describe "runtime event injection" do
    test "inject_event/2 drives handle_event for local test servers" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      assert_receive {:mounted, _opts}, 1000
      assert_receive {:rendered, 0, %Frame{width: 80, height: 24}}, 1000

      event = %ExRatatui.Event.Key{code: "a", modifiers: [], kind: "press"}

      assert :ok = Runtime.inject_event(pid, event)
      assert_receive {:event, ^event}, 1000
      assert_receive {:rendered, 1, %Frame{width: 80, height: 24}}, 1000

      GenServer.stop(pid)
    end

    test "inject_event/2 can stop the server cleanly" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: StopOnAnyEvent,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      ref = Process.monitor(pid)

      assert :ok = Runtime.inject_event(pid, %{stop: true})
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  describe "process_poll_result/1" do
    test "stop returns GenServer stop tuple" do
      state = build_server_state(TestApp, %{test_pid: self()})
      assert {:stop, :normal, ^state} = ExRatatui.Server.process_poll_result({:stop, state})
    end

    test "continue re-arms polling when live input is enabled" do
      state =
        build_server_state(TestApp, %{test_pid: self()},
          test_mode: nil,
          polling_enabled?: true,
          poll_interval: 0
        )

      assert {:noreply, ^state} = ExRatatui.Server.process_poll_result({:continue, state, false})
      assert_receive :poll, 1000
    end
  end

  describe "resolve_terminal_size/1" do
    test "passes through explicit dimensions" do
      assert {80, 24} = ExRatatui.Server.resolve_terminal_size({80, 24})
    end

    test "uses the default resolver when dimensions are not explicit" do
      {w, h} = ExRatatui.Server.resolve_terminal_size(nil)
      assert is_integer(w) and is_integer(h)
    end

    test "uses the injected resolver when dimensions are not explicit" do
      assert {145, 30} = ExRatatui.Server.resolve_terminal_size(nil, fn -> {145, 30} end)
    end

    test "falls back to 80x24 when the injected resolver errors" do
      assert {80, 24} =
               ExRatatui.Server.resolve_terminal_size(nil, fn -> {:error, "no tty"} end)
    end
  end

  describe "normalize_size_result/1" do
    test "passes through integer dimensions" do
      assert {120, 40} = ExRatatui.Server.normalize_size_result({120, 40})
    end

    test "falls back to 80x24 on error" do
      assert {80, 24} = ExRatatui.Server.normalize_size_result({:error, "no tty"})
    end
  end

  describe "continue_init/2" do
    test "returns stop when terminal init failed" do
      assert {:stop, {:terminal_init_failed, "no tty"}} =
               ExRatatui.Server.continue_init({:error, "no tty"}, [])
    end

    test "enables polling for live local servers" do
      {:ok, task_sup} = Task.Supervisor.start_link()

      assert {:ok, state} =
               ExRatatui.Server.continue_init(make_ref(),
                 mod: TestApp,
                 name: nil,
                 test_pid: self(),
                 task_supervisor: task_sup,
                 terminal_size_fn: fn -> {80, 24} end
               )

      assert state.polling_enabled?
      assert_receive {:mounted, _opts}, 1000
      assert_receive {:rendered, 0, %Frame{width: 80, height: 24}}, 1000
      assert_receive :poll, 1000
    end
  end

  describe "poll loop handling" do
    test ":poll is ignored when headless polling is disabled" do
      state = build_server_state(TestApp, %{test_pid: self()}, polling_enabled?: false)
      assert {:noreply, ^state} = ExRatatui.Server.handle_info(:poll, state)
    end

    test ":poll re-arms when live polling is enabled" do
      state =
        build_server_state(TestApp, %{test_pid: self()},
          test_mode: nil,
          polling_enabled?: true,
          poll_interval: 0
        )

      assert {:noreply, %ExRatatui.Server{} = next_state} =
               ExRatatui.Server.handle_info(:poll, state)

      assert next_state.polling_enabled?
      assert_receive :poll, 1000
    end
  end

  describe "terminate/2" do
    test "catch-all returns :ok for non-initialized state" do
      assert :ok = ExRatatui.Server.terminate(:normal, %{})
    end
  end

  describe "restore_terminal rescue" do
    @tag capture_log: true
    test "logs warning when terminal ref is invalid on shutdown" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: TestApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      assert_receive {:mounted, _opts}, 1000

      # Replace terminal_ref with invalid ref to trigger rescue on shutdown
      :sys.replace_state(pid, fn state -> %{state | terminal_ref: make_ref()} end)

      ref = Process.monitor(pid)
      GenServer.stop(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  describe "render error handling" do
    @tag capture_log: true
    test "server survives when render raises" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: CrashRenderApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      # Server should still be alive despite render crashing
      _ = :sys.get_state(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    @tag capture_log: true
    test "server logs draw error when terminal ref is invalidated" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: DrawErrorApp,
          name: nil,
          test_pid: self(),
          test_mode: {80, 24}
        )

      assert_receive {:mounted, ^pid}, 1000
      assert_receive :rendered, 1000

      # Get the terminal ref from server state and restore it to invalidate
      %{terminal_ref: terminal_ref} = :sys.get_state(pid)
      ExRatatui.Native.restore_terminal(terminal_ref)

      # Trigger a new render — draw will fail on the restored terminal
      send(pid, :trigger_render)
      assert_receive :rendered, 1000

      # Server should still be alive (draw error is logged, not fatal)
      _ = :sys.get_state(pid)
      assert Process.alive?(pid)

      # Clean up — stop will try to restore already-restored terminal
      GenServer.stop(pid)
    end
  end

  defp build_server_state(mod, user_state, attrs \\ []) do
    {:ok, task_sup} = Task.Supervisor.start_link()

    struct!(
      ExRatatui.Server,
      Keyword.merge(
        [
          mod: mod,
          user_state: user_state,
          test_mode: {80, 24},
          terminal_ref: make_ref(),
          terminal_size_fn: fn -> {80, 24} end,
          task_supervisor: task_sup,
          terminal_initialized: true
        ],
        attrs
      )
    )
  end
end
