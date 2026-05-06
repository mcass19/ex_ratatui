defmodule ExRatatui.Server.IntentsTest do
  @moduledoc """
  Tests for the `:intents` runtime opt under the `:cell_session`
  transport — the path consumed by `phoenix_ex_ratatui` for inter-page
  navigation.

  Intents are opaque to ex_ratatui; they're forwarded verbatim to the
  transport's `intent_writer_fn` (the 4th element of the
  `{:cell_session, cell_session, cell_writer_fn, intent_writer_fn}`
  transport tag). Transports that don't supply an intent writer
  (local/SSH/distributed, or the 3-tuple cell_session shape) silently
  drop intents — apps can return them safely regardless of where
  they're running.
  """

  use ExUnit.Case, async: true

  alias ExRatatui.CellSession
  alias ExRatatui.Event.Key
  alias ExRatatui.Test.ServerApps.Intents

  defp cell_writer(test_pid) do
    fn diff -> send(test_pid, {:writer_diff, diff}) end
  end

  defp intent_writer(test_pid) do
    fn intent -> send(test_pid, {:writer_intent, intent}) end
  end

  describe "4-tuple {:cell_session, cs, cell_writer, intent_writer} transport tag" do
    test "intents returned from mount are dispatched to the intent_writer in order" do
      cs = CellSession.new(20, 5)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Intents,
          name: nil,
          test_pid: self(),
          mount_intents: [{:patch, "/welcome"}, {:navigate, "/home"}],
          transport: {:cell_session, cs, cell_writer(self()), intent_writer(self())}
        )

      assert_receive {:mounted, _opts}, 500
      assert_receive {:writer_intent, {:patch, "/welcome"}}, 500
      assert_receive {:writer_intent, {:navigate, "/home"}}, 500

      GenServer.stop(pid)
    end

    test "intents from handle_event in a {:noreply, state, intents: ...} transition fire" do
      cs = CellSession.new(20, 5)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Intents,
          name: nil,
          test_pid: self(),
          transport: {:cell_session, cs, cell_writer(self()), intent_writer(self())}
        )

      assert_receive {:mounted, _opts}, 500
      assert_receive {:writer_diff, _}, 500

      send(pid, {:ex_ratatui_event, %Key{code: "navigate"}})

      assert_receive {:writer_intent, {:navigate, "/dashboard"}}, 500

      GenServer.stop(pid)
    end

    test "intents from handle_info dispatch through the writer" do
      cs = CellSession.new(20, 5)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Intents,
          name: nil,
          test_pid: self(),
          transport: {:cell_session, cs, cell_writer(self()), intent_writer(self())}
        )

      assert_receive {:mounted, _opts}, 500

      send(pid, {:emit_intents, [{:redirect, "/elsewhere"}]})

      assert_receive {:writer_intent, {:redirect, "/elsewhere"}}, 500

      GenServer.stop(pid)
    end

    test "intents from a {:stop, state, intents: ...} transition still fire before exit" do
      Process.flag(:trap_exit, true)
      cs = CellSession.new(20, 5)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Intents,
          name: nil,
          test_pid: self(),
          transport: {:cell_session, cs, cell_writer(self()), intent_writer(self())}
        )

      assert_receive {:mounted, _opts}, 500

      send(pid, {:ex_ratatui_event, %Key{code: "stop_with_intent"}})

      # Intent fires BEFORE the server exits — phoenix_ex_ratatui needs
      # the redirect to reach the LV before its linked Server tears down.
      assert_receive {:writer_intent, {:redirect, "/login"}}, 500
      assert_receive {:EXIT, ^pid, :normal}, 500
    end

    test "no-op when handler returns no intents" do
      cs = CellSession.new(20, 5)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Intents,
          name: nil,
          test_pid: self(),
          transport: {:cell_session, cs, cell_writer(self()), intent_writer(self())}
        )

      assert_receive {:mounted, _opts}, 500
      assert_receive {:writer_diff, _}, 500

      send(pid, {:ex_ratatui_event, %Key{code: "x"}})

      refute_receive {:writer_intent, _}, 100

      GenServer.stop(pid)
    end
  end

  describe "shape validation" do
    test "non-list :intents value raises ArgumentError from the runtime" do
      Process.flag(:trap_exit, true)
      cs = CellSession.new(20, 5)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Intents,
          name: nil,
          test_pid: self(),
          transport: {:cell_session, cs, cell_writer(self()), intent_writer(self())}
        )

      assert_receive {:mounted, _opts}, 500

      ExUnit.CaptureLog.capture_log(fn ->
        send(pid, {:ex_ratatui_event, %Key{code: "bogus_intents"}})
        assert_receive {:EXIT, ^pid, {%ArgumentError{message: msg}, _}}, 500
        assert msg =~ "invalid intents"
      end)
    end
  end

  describe "3-tuple {:cell_session, cs, cell_writer} transport tag (no intent writer)" do
    test "intents from app transitions are silently dropped" do
      cs = CellSession.new(20, 5)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Intents,
          name: nil,
          test_pid: self(),
          mount_intents: [{:navigate, "/dropped"}],
          transport: {:cell_session, cs, cell_writer(self())}
        )

      assert_receive {:mounted, _opts}, 500

      # No intent_writer registered → mount intents drop on the floor;
      # the app does not crash and rendering proceeds normally.
      refute_receive {:writer_intent, _}, 100
      assert_receive {:writer_diff, _}, 500

      GenServer.stop(pid)
    end
  end
end
