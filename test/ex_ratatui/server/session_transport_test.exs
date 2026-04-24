defmodule ExRatatui.Server.SessionTransportTest do
  @moduledoc """
  Unit tests for `ExRatatui.Server` running under the
  `{:session, session, writer_fn}` transport — the generic byte-stream
  runtime that SSH uses today and Kino will reuse. These don't stand up
  a real OTP `:ssh` daemon — they drive the Server directly with a fake
  `writer_fn` so we can assert on the bytes it emits. The real
  end-to-end SSH test lives in `ExRatatui.SSH.IntegrationTest`.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ExRatatui.Frame
  alias ExRatatui.Session
  alias ExRatatui.Test.ServerApps.{Echo, FailingMount, StopOnAnyEvent}

  defp session_writer(test_pid) do
    fn bytes -> send(test_pid, {:writer_bytes, bytes}) end
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

  describe "lifecycle" do
    test "start_link with {:session, session, writer_fn} mounts and renders" do
      session = Session.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:session, session, session_writer(self())}
        )

      # mount sees augmented opts (transport/width/height)
      assert_receive {:mounted, opts}, 1000
      assert opts[:transport] == :session
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

    test "mount returning {:error, _} closes the session" do
      Process.flag(:trap_exit, true)
      session = Session.new(40, 10)

      capture_log(fn ->
        assert {:error, :mount_failed} =
                 ExRatatui.Server.start_link(
                   mod: FailingMount,
                   name: nil,
                   transport: {:session, session, session_writer(self())}
                 )
      end)

      # session is closed — draw on it must error with "closed"
      assert {:error, reason} = Session.draw(session, [])
      assert reason =~ "closed"
    end

    test "terminate calls Session.close and the user terminate/2 callback" do
      session = Session.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:session, session, session_writer(self())}
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
  end

  describe "message handling" do
    test "{:ex_ratatui_event, event} drives handle_event and triggers a re-render" do
      session = Session.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:session, session, session_writer(self())}
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
          mod: StopOnAnyEvent,
          name: nil,
          test_pid: self(),
          transport: {:session, session, session_writer(self())}
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
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:session, session, session_writer(self())}
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
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:session, session, session_writer(self())}
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

    @tag capture_log: true
    test "logs draw error when the session is closed mid-flight" do
      session = Session.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:session, session, session_writer(self())}
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

      _ = :sys.get_state(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "helpers" do
    test "augment_session_mount_opts adds transport/width/height" do
      opts = [mod: Echo, test_pid: self(), foo: :bar]
      result = ExRatatui.Server.augment_session_mount_opts(opts, 80, 24)

      assert result[:mod] == Echo
      assert result[:test_pid] == self()
      assert result[:foo] == :bar
      assert result[:transport] == :session
      assert result[:width] == 80
      assert result[:height] == 24
    end

    test "process_event_result/1 with :stop returns GenServer stop" do
      state = build_server_state(Echo, %{test_pid: self()})
      assert {:stop, :normal, ^state} = ExRatatui.Server.process_event_result({:stop, state})
    end
  end
end
