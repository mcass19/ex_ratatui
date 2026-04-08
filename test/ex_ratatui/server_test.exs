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

  defmodule StopOnEventApp do
    use ExRatatui.App

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      {:ok, %{test_pid: test_pid}}
    end

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(%{stop: true}, state), do: {:stop, state}
    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule FailingMountApp do
    use ExRatatui.App

    @impl true
    def mount(_opts), do: {:error, :mount_failed}

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule RenderingApp do
    use ExRatatui.App

    alias ExRatatui.Widgets.Paragraph
    alias ExRatatui.Layout.Rect

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

    alias ExRatatui.Widgets.Paragraph
    alias ExRatatui.Layout.Rect

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

      assert {:error, :mount_failed} =
               ExRatatui.Server.start_link(
                 mod: FailingMountApp,
                 name: nil,
                 test_mode: {80, 24}
               )
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
      state = build_server_state(TestApp, %{test_pid: self()})
      event = %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}
      assert {:continue, _new_state, true} = ExRatatui.Server.handle_poll_result(event, state)
      assert_receive {:event, ^event}
    end
  end

  describe "dispatch_event/2" do
    test "noreply returns continue with render flag" do
      state = build_server_state(TestApp, %{test_pid: self()})
      event = %ExRatatui.Event.Key{code: "a", modifiers: [], kind: "press"}
      assert {:continue, new_state, true} = ExRatatui.Server.dispatch_event(state, event)
      assert_receive {:event, ^event}
      assert new_state.mod == TestApp
    end

    test "stop returns stop tuple" do
      state = build_server_state(StopOnEventApp, %{test_pid: self()})
      event = %{stop: true}
      assert {:stop, new_state} = ExRatatui.Server.dispatch_event(state, event)
      assert new_state.user_state == %{test_pid: self()}
    end
  end

  describe "process_poll_result/1" do
    test "stop returns GenServer stop tuple" do
      state = build_server_state(TestApp, %{test_pid: self()})
      assert {:stop, :normal, ^state} = ExRatatui.Server.process_poll_result({:stop, state})
    end
  end

  describe "resolve_terminal_size/1" do
    test "passes through explicit dimensions" do
      assert {80, 24} = ExRatatui.Server.resolve_terminal_size({80, 24})
    end

    test "resolves when nil (falls back to terminal_size or default)" do
      {w, h} = ExRatatui.Server.resolve_terminal_size(nil)
      assert is_integer(w) and is_integer(h)
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
      Process.sleep(50)
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
      Process.sleep(50)
      assert Process.alive?(pid)

      # Clean up — stop will try to restore already-restored terminal
      GenServer.stop(pid)
    end
  end

  defp build_server_state(mod, user_state) do
    %ExRatatui.Server{
      mod: mod,
      user_state: user_state,
      test_mode: {80, 24},
      terminal_ref: make_ref(),
      terminal_initialized: true
    }
  end

  describe "SSH transport" do
    alias ExRatatui.Session
    alias ExRatatui.Widgets.Paragraph
    alias ExRatatui.Layout.Rect

    defmodule SshApp do
      use ExRatatui.App

      @impl true
      def mount(opts) do
        test_pid = Keyword.fetch!(opts, :test_pid)
        send(test_pid, {:mounted, opts})
        {:ok, %{test_pid: test_pid, count: 0}}
      end

      @impl true
      def render(state, frame) do
        send(state.test_pid, {:rendered, state.count, frame})

        [
          {%Paragraph{text: "count: #{state.count}"},
           %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
        ]
      end

      @impl true
      def handle_event(event, state) do
        send(state.test_pid, {:event, event})
        {:noreply, %{state | count: state.count + 1}}
      end

      @impl true
      def handle_info(_msg, state), do: {:noreply, state}

      @impl true
      def terminate(reason, state) do
        send(state.test_pid, {:terminated, reason})
        :ok
      end
    end

    defmodule SshStopApp do
      use ExRatatui.App

      @impl true
      def mount(opts) do
        {:ok, %{test_pid: Keyword.fetch!(opts, :test_pid)}}
      end

      @impl true
      def render(_state, _frame), do: []

      @impl true
      def handle_event(_event, state), do: {:stop, state}
    end

    defmodule SshFailingMountApp do
      use ExRatatui.App

      @impl true
      def mount(_opts), do: {:error, :nope}

      @impl true
      def render(_state, _frame), do: []

      @impl true
      def handle_event(_event, state), do: {:noreply, state}
    end

    defp ssh_writer(test_pid) do
      fn bytes -> send(test_pid, {:writer_bytes, bytes}) end
    end

    test "start_link with {:ssh, session, writer_fn} mounts and renders" do
      session = Session.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: SshApp,
          name: nil,
          test_pid: self(),
          transport: {:ssh, session, ssh_writer(self())}
        )

      # mount sees augmented opts (transport/width/height)
      assert_receive {:mounted, opts}, 1000
      assert opts[:transport] == :ssh
      assert opts[:width] == 40
      assert opts[:height] == 10
      assert opts[:test_pid] == self()

      # initial render uses the session's size for the Frame
      assert_receive {:rendered, 0, %Frame{width: 40, height: 10}}, 1000

      # The writer_fn received the ANSI bytes from the in-memory buffer
      assert_receive {:writer_bytes, bytes}, 1000
      assert is_binary(bytes) and byte_size(bytes) > 0

      GenServer.stop(pid)
      assert_receive {:terminated, :normal}, 1000
    end

    test "{:ex_ratatui_event, event} drives handle_event and triggers a re-render" do
      session = Session.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: SshApp,
          name: nil,
          test_pid: self(),
          transport: {:ssh, session, ssh_writer(self())}
        )

      assert_receive {:mounted, _opts}, 1000
      assert_receive {:rendered, 0, _}, 1000
      assert_receive {:writer_bytes, _initial}, 1000

      event = %ExRatatui.Event.Key{code: "a", modifiers: [], kind: "press"}
      send(pid, {:ex_ratatui_event, event})

      assert_receive {:event, ^event}, 1000
      assert_receive {:rendered, 1, _}, 1000
      assert_receive {:writer_bytes, _after_event}, 1000

      GenServer.stop(pid)
    end

    test "{:ex_ratatui_event, event} returning :stop shuts down the server cleanly" do
      session = Session.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: SshStopApp,
          name: nil,
          test_pid: self(),
          transport: {:ssh, session, ssh_writer(self())}
        )

      ref = Process.monitor(pid)

      send(
        pid,
        {:ex_ratatui_event, %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}}
      )

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "{:ex_ratatui_resize, w, h} updates cached size and re-renders" do
      session = Session.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: SshApp,
          name: nil,
          test_pid: self(),
          transport: {:ssh, session, ssh_writer(self())}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, %Frame{width: 40, height: 10}}, 1000
      assert_receive {:writer_bytes, _}, 1000

      send(pid, {:ex_ratatui_resize, 100, 30})

      # Re-render uses the new cached dims (we don't poke the Session
      # here — the SSH channel is responsible for calling Session.resize
      # before forwarding the resize message).
      assert_receive {:rendered, 0, %Frame{width: 100, height: 30}}, 1000

      GenServer.stop(pid)
    end

    test ":poll messages are silently absorbed in SSH mode" do
      # Belt-and-braces: nothing in our code sends :poll to an SSH-mode
      # server, but if anything ever does (eg. a stale message left from
      # a transport switchover) it must not reach the user module.
      session = Session.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: SshApp,
          name: nil,
          test_pid: self(),
          transport: {:ssh, session, ssh_writer(self())}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, _}, 1000
      assert_receive {:writer_bytes, _}, 1000

      send(pid, :poll)
      # No new render, no event forwarded — we only see writer/event noise
      # if the message was mishandled.
      refute_receive {:rendered, _, _}, 50
      refute_receive {:event, _}, 50

      GenServer.stop(pid)
    end

    test "mount returning {:error, _} closes the session" do
      Process.flag(:trap_exit, true)
      session = Session.new(40, 10)

      assert {:error, :nope} =
               ExRatatui.Server.start_link(
                 mod: SshFailingMountApp,
                 name: nil,
                 transport: {:ssh, session, ssh_writer(self())}
               )

      # session is closed — draw on it must error with "closed"
      assert {:error, reason} = Session.draw(session, [])
      assert reason =~ "closed"
    end

    test "terminate calls Session.close and the user terminate/2 callback" do
      session = Session.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: SshApp,
          name: nil,
          test_pid: self(),
          transport: {:ssh, session, ssh_writer(self())}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, _}, 1000
      assert_receive {:writer_bytes, _}, 1000

      ref = Process.monitor(pid)
      GenServer.stop(pid)

      assert_receive {:terminated, :normal}, 1000
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      # Session was closed by terminate/2 — draws on it must error.
      assert {:error, reason} = Session.draw(session, [])
      assert reason =~ "closed"
    end

    test "augment_ssh_mount_opts adds transport/width/height" do
      opts = [mod: SshApp, test_pid: self(), foo: :bar]
      result = ExRatatui.Server.augment_ssh_mount_opts(opts, 80, 24)

      assert result[:mod] == SshApp
      assert result[:test_pid] == self()
      assert result[:foo] == :bar
      assert result[:transport] == :ssh
      assert result[:width] == 80
      assert result[:height] == 24
    end

    test "process_event_result/1 with :stop returns GenServer stop" do
      state = build_server_state(SshApp, %{test_pid: self()})
      assert {:stop, :normal, ^state} = ExRatatui.Server.process_event_result({:stop, state})
    end

    @tag capture_log: true
    test "logs draw error when the session is closed mid-flight" do
      session = Session.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: SshApp,
          name: nil,
          test_pid: self(),
          transport: {:ssh, session, ssh_writer(self())}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, _}, 1000
      assert_receive {:writer_bytes, _}, 1000

      # Close the session out from under the server, then drive a
      # re-render via a generic handle_info message — Session.draw will
      # return {:error, "session closed"} and the error path must log
      # without crashing the server.
      :ok = Session.close(session)

      send(pid, :something_to_re_render)
      assert_receive {:rendered, 0, _}, 1000

      Process.sleep(20)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end
end
