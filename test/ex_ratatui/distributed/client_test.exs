defmodule ExRatatui.Distributed.ClientTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Distributed.Client
  alias ExRatatui.Event
  alias ExRatatui.Widgets.Paragraph
  alias ExRatatui.Layout.Rect

  describe "start_link/1" do
    test "starts and polls for events" do
      remote = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} =
        Client.start_link(
          remote_pid: remote,
          test_mode: {80, 24}
        )

      assert Process.alive?(pid)

      GenServer.stop(pid)
      Process.exit(remote, :kill)
    end

    test "starts without remote_pid and defers polling" do
      {:ok, pid} = Client.start_link(test_mode: {80, 24})

      assert Process.alive?(pid)
      state = :sys.get_state(pid)
      assert state.remote_pid == nil

      GenServer.stop(pid)
    end

    test "stops when terminal init fails" do
      Process.flag(:trap_exit, true)

      assert {:error, {:terminal_init_failed, :no_tty}} =
               Client.start_link(init_terminal: fn _test_mode -> {:error, :no_tty} end)
    end
  end

  describe "connect_remote/2" do
    test "sets remote pid and starts polling" do
      remote = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} = Client.start_link(test_mode: {80, 24})

      assert :ok = Client.connect_remote(pid, remote)

      state = :sys.get_state(pid)
      assert state.remote_pid == remote

      GenServer.stop(pid)
      Process.exit(remote, :kill)
    end

    test "monitors the remote process after connect" do
      remote = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} = Client.start_link(test_mode: {80, 24})
      Client.connect_remote(pid, remote)

      ref = Process.monitor(pid)
      Process.exit(remote, :kill)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  describe "incoming draw messages" do
    test "{:ex_ratatui_draw, widgets} renders widgets locally" do
      remote = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} =
        Client.start_link(
          remote_pid: remote,
          test_mode: {40, 10}
        )

      widgets = [
        {%Paragraph{text: "hello distributed"}, %Rect{x: 0, y: 0, width: 40, height: 10}}
      ]

      send(pid, {:ex_ratatui_draw, widgets})

      # Give it a moment to process the message
      _ = :sys.get_state(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
      Process.exit(remote, :kill)
    end

    test "empty widget list is handled" do
      remote = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} =
        Client.start_link(
          remote_pid: remote,
          test_mode: {40, 10}
        )

      send(pid, {:ex_ratatui_draw, []})

      _ = :sys.get_state(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
      Process.exit(remote, :kill)
    end
  end

  describe "remote server monitoring" do
    test "stops when remote server exits" do
      remote = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} =
        Client.start_link(
          remote_pid: remote,
          test_mode: {40, 10}
        )

      ref = Process.monitor(pid)
      Process.exit(remote, :kill)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "restores terminal on remote disconnect" do
      remote = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} =
        Client.start_link(
          remote_pid: remote,
          test_mode: {40, 10}
        )

      ref = Process.monitor(pid)
      Process.exit(remote, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    @tag capture_log: true
    test "logs warning when terminal ref is invalid on shutdown" do
      remote = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} =
        Client.start_link(
          remote_pid: remote,
          test_mode: {40, 10}
        )

      # Replace terminal_ref with invalid ref to trigger rescue on shutdown
      :sys.replace_state(pid, fn state -> %{state | terminal_ref: make_ref()} end)

      ref = Process.monitor(pid)
      GenServer.stop(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      Process.exit(remote, :kill)
    end
  end

  describe "handle_poll_result/2" do
    test "nil event re-arms poll without sending" do
      state = build_state()
      assert {:noreply, ^state} = Client.handle_poll_result(nil, state)
      refute_receive {:ex_ratatui_event, _}, 10
    end

    test "error event re-arms poll without sending" do
      state = build_state()
      assert {:noreply, ^state} = Client.handle_poll_result({:error, "fail"}, state)
      refute_receive {:ex_ratatui_event, _}, 10
    end

    test "key event is forwarded to remote as {:ex_ratatui_event, ...}" do
      state = build_state(self())
      event = %Event.Key{code: "a", modifiers: [], kind: "press"}

      assert {:noreply, ^state} = Client.handle_poll_result(event, state)
      assert_receive {:ex_ratatui_event, ^event}
    end

    test "mouse event is forwarded to remote as {:ex_ratatui_event, ...}" do
      state = build_state(self())
      event = %Event.Mouse{kind: "down", button: "left", x: 5, y: 3, modifiers: []}

      assert {:noreply, ^state} = Client.handle_poll_result(event, state)
      assert_receive {:ex_ratatui_event, ^event}
    end

    test "resize event is forwarded as {:ex_ratatui_resize, w, h}" do
      state = build_state(self())
      event = %Event.Resize{width: 120, height: 40}

      assert {:noreply, ^state} = Client.handle_poll_result(event, state)
      assert_receive {:ex_ratatui_resize, 120, 40}
    end
  end

  describe "terminate" do
    test "catch-all returns :ok for non-initialized state" do
      assert :ok = Client.terminate(:normal, %{})
    end
  end

  describe "default_init_terminal/1" do
    test "creates a test terminal with given dimensions" do
      ref = Client.default_init_terminal({80, 24})
      assert is_reference(ref)
      ExRatatui.Native.restore_terminal(ref)
    end

    test "attempts real terminal init when nil" do
      case Client.default_init_terminal(nil) do
        {:error, _} -> :ok
        ref when is_reference(ref) -> ExRatatui.Native.restore_terminal(ref)
      end
    end
  end

  describe "unrecognized messages" do
    test "unknown messages are silently ignored" do
      remote = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} =
        Client.start_link(
          remote_pid: remote,
          test_mode: {40, 10}
        )

      send(pid, {:random, "noise"})
      _ = :sys.get_state(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
      Process.exit(remote, :kill)
    end
  end

  describe "draw error handling" do
    @tag capture_log: true
    test "survives when terminal ref is invalidated" do
      remote = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} =
        Client.start_link(
          remote_pid: remote,
          test_mode: {40, 10}
        )

      # Invalidate the terminal ref to trigger a draw error
      %{terminal_ref: terminal_ref} = :sys.get_state(pid)
      ExRatatui.Native.restore_terminal(terminal_ref)

      widgets = [
        {%Paragraph{text: "after invalidation"}, %Rect{x: 0, y: 0, width: 40, height: 10}}
      ]

      send(pid, {:ex_ratatui_draw, widgets})

      # Give it time to process — should not crash
      Process.sleep(20)
      assert Process.alive?(pid)

      GenServer.stop(pid)
      Process.exit(remote, :kill)
    end
  end

  defp build_state(remote_pid \\ nil) do
    %Client{
      terminal_ref: make_ref(),
      remote_pid: remote_pid || spawn(fn -> Process.sleep(:infinity) end),
      poll_interval: 16,
      terminal_initialized: true
    }
  end
end
