defmodule ExRatatui.Server.CellSessionTransportTest do
  @moduledoc """
  Unit tests for `ExRatatui.Server` running under the
  `{:cell_session, cell_session, cell_writer_fn}` transport — the
  cell-stream analogue of the byte-stream `:session` transport. Used
  by `phoenix_ex_ratatui` (browser DOM cells) and the
  [name_badge](https://github.com/protolux-electronics/name_badge)
  Nerves project (1bpp framebuffer rasteriser).

  These tests don't stand up a Phoenix LiveView or Nerves device;
  they drive the Server directly with a fake `cell_writer_fn` so we
  can assert on the `%CellSession.Diff{}` payloads it emits.

  Mirrors `ExRatatui.Server.SessionTransportTest` case-for-case so
  any future regression in one transport that breaks the same
  guarantee in the other surfaces in both files.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ExRatatui.CellSession
  alias ExRatatui.CellSession.Diff
  alias ExRatatui.Frame
  alias ExRatatui.Test.ServerApps.{Echo, FailingMount, StopOnAnyEvent}

  defp cell_writer(test_pid) do
    fn %Diff{} = diff -> send(test_pid, {:writer_diff, diff}) end
  end

  describe "lifecycle" do
    test "start_link with {:cell_session, cell_session, writer_fn} mounts and renders" do
      cell_session = CellSession.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:cell_session, cell_session, cell_writer(self())}
        )

      # mount/1 sees augmented opts (transport tagged :cell_session,
      # plus width/height drawn from the session's intrinsic size).
      assert_receive {:mounted, opts}, 1000
      assert opts[:transport] == :cell_session
      assert opts[:width] == 40
      assert opts[:height] == 10
      assert opts[:test_pid] == self()

      # initial render uses the cell_session's size for the Frame
      assert_receive {:rendered, 0, %Frame{width: 40, height: 10}}, 1000

      # The writer_fn received a %Diff{} carrying every cell of the
      # initial buffer (first take_cells_diff after construction is
      # always a "full" payload).
      assert_receive {:writer_diff, %Diff{} = diff}, 1000
      assert diff.width == 40
      assert diff.height == 10
      assert length(diff.ops) == 40 * 10

      GenServer.stop(pid)
      assert_receive {:terminated, :normal}, 1000
    end

    test "mount returning {:error, _} closes the cell_session" do
      Process.flag(:trap_exit, true)
      cell_session = CellSession.new(40, 10)

      capture_log(fn ->
        assert {:error, :mount_failed} =
                 ExRatatui.Server.start_link(
                   mod: FailingMount,
                   name: nil,
                   transport: {:cell_session, cell_session, cell_writer(self())}
                 )
      end)

      # cell_session is closed — draw on it must error with "closed"
      assert {:error, reason} = CellSession.draw(cell_session, [])
      assert reason =~ "closed"
    end

    test "terminate calls CellSession.close and the user terminate/2 callback" do
      cell_session = CellSession.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:cell_session, cell_session, cell_writer(self())}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, _}, 1000
      assert_receive {:writer_diff, _}, 1000

      ref = Process.monitor(pid)
      GenServer.stop(pid)

      assert_receive {:terminated, :normal}, 1000
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      # CellSession was closed by terminate/2 — draws on it must error.
      assert {:error, reason} = CellSession.draw(cell_session, [])
      assert reason =~ "closed"
    end
  end

  describe "message handling" do
    test "{:ex_ratatui_event, event} drives handle_event and triggers a re-render" do
      cell_session = CellSession.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:cell_session, cell_session, cell_writer(self())}
        )

      assert_receive {:mounted, _opts}, 1000
      assert_receive {:rendered, 0, _}, 1000
      assert_receive {:writer_diff, _initial}, 1000

      event = %ExRatatui.Event.Key{code: "a", modifiers: [], kind: "press"}
      send(pid, {:ex_ratatui_event, event})

      assert_receive {:event, ^event}, 1000
      assert_receive {:rendered, 1, _}, 1000

      # The post-event render shipped a follow-up diff. Echo paints a
      # tiny render-counter digit that flipped from "0" to "1", so the
      # diff carries exactly one op — the cell that changed — not the
      # full grid. This is the whole point of the cell-stream
      # transport: per-frame payloads are proportional to what
      # actually changed, not the screen size. (If Echo's render
      # ever paints over more cells, this assertion will surface it
      # immediately.)
      assert_receive {:writer_diff, %Diff{width: 40, height: 10, ops: [_one_changed_cell]}}, 1000

      GenServer.stop(pid)
    end

    test "{:ex_ratatui_event, event} returning :stop shuts down the server cleanly" do
      cell_session = CellSession.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: StopOnAnyEvent,
          name: nil,
          test_pid: self(),
          transport: {:cell_session, cell_session, cell_writer(self())}
        )

      ref = Process.monitor(pid)

      send(
        pid,
        {:ex_ratatui_event, %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}}
      )

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "{:ex_ratatui_resize, w, h} delivers Resize event to App and re-renders with new size" do
      cell_session = CellSession.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:cell_session, cell_session, cell_writer(self())}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, %Frame{width: 40, height: 10}}, 1000
      assert_receive {:writer_diff, _}, 1000

      # Resize the underlying CellSession before forwarding the
      # message — same contract byte-stream transports follow.
      :ok = CellSession.resize(cell_session, 100, 30)
      send(pid, {:ex_ratatui_resize, 100, 30})

      # The App sees a Resize event in handle_event/2 (Echo bumps the
      # render counter on every event) and the follow-up render uses
      # the new cached dims.
      assert_receive {:event, %ExRatatui.Event.Resize{width: 100, height: 30}}, 1000
      assert_receive {:rendered, 1, %Frame{width: 100, height: 30}}, 1000

      # The post-resize diff carries the FULL new grid as ops because
      # the prior baseline at 40x10 is no longer comparable —
      # CellSession's documented behaviour. Without this guarantee a
      # browser consumer would see a partial paint at the new size
      # and live with stale cells from the old viewport.
      assert_receive {:writer_diff, %Diff{width: 100, height: 30, ops: ops}}, 1000
      assert length(ops) == 100 * 30

      GenServer.stop(pid)
    end

    test ":poll messages are silently absorbed in cell_session mode" do
      # Belt-and-braces: nothing in our code sends :poll to a
      # non-:local server, but if anything ever does (eg. a stale
      # message left from a transport switchover) it must not reach
      # the user module's handle_info/2.
      cell_session = CellSession.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:cell_session, cell_session, cell_writer(self())}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, _}, 1000
      assert_receive {:writer_diff, _}, 1000

      send(pid, :poll)
      refute_receive {:rendered, _, _}, 50
      refute_receive {:event, _}, 50

      GenServer.stop(pid)
    end

    @tag capture_log: true
    test "logs draw error when the cell_session is closed mid-flight" do
      cell_session = CellSession.new(40, 10)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:cell_session, cell_session, cell_writer(self())}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, _}, 1000
      assert_receive {:writer_diff, _}, 1000

      # Close the cell_session out from under the server, then drive
      # a re-render via a generic handle_info message — CellSession.draw
      # will return {:error, "...closed"} and the error path must log
      # without crashing the server. (render_count stays at 0 because
      # the draw failed; no second :rendered message is sent.)
      :ok = CellSession.close(cell_session)

      send(pid, :something_to_re_render)
      assert_receive {:rendered, 0, _}, 1000

      _ = :sys.get_state(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "helpers" do
    test "augment_cell_session_mount_opts adds transport/width/height" do
      opts = [mod: Echo, test_pid: self(), foo: :bar]
      result = ExRatatui.Server.augment_cell_session_mount_opts(opts, 80, 24)

      assert result[:mod] == Echo
      assert result[:test_pid] == self()
      assert result[:foo] == :bar
      assert result[:transport] == :cell_session
      assert result[:width] == 80
      assert result[:height] == 24
    end
  end
end
