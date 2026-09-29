defmodule ExRatatui.Server.ClosePriorityTest do
  @moduledoc """
  A disconnect must stop the Server even when its mailbox is backed up.
  `SlowWorker` sleeps on every message it handles, so a flood of them keeps
  the Server busy for seconds; the close has to overtake that backlog
  (OTP 28+ priority signals) instead of waiting behind it.
  """

  use ExUnit.Case, async: true

  alias ExRatatui.Server
  alias ExRatatui.Test.ServerApps.SlowWorker

  @backlog 1_000
  @work_ms 5

  # Starts the Server from a throwaway process so the test can make that
  # parent exit on demand, the way an SSH channel or supervisor would.
  defp start_under_fake_parent(opts, exit_fun) do
    test_pid = self()

    parent =
      spawn(fn ->
        {:ok, pid} = Server.start_link(opts)
        send(test_pid, {:server, pid})

        receive do
          :exit -> exit_fun.(pid)
        end
      end)

    assert_receive {:server, pid}, 1000
    {parent, pid}
  end

  defp worker_opts(extra) do
    Keyword.merge(
      [mod: SlowWorker, name: nil, test_pid: self(), work_ms: @work_ms, test_mode: {20, 5}],
      extra
    )
  end

  defp flood(pid, n), do: for(_ <- 1..n, do: send(pid, :work))

  # A remote client floods the Server with key events rather than info
  # messages; both go through the same slow path in `SlowWorker`.
  defp flood_keys(pid, n) do
    key = %ExRatatui.Event.Key{code: "x", modifiers: [], kind: "press"}
    for _ <- 1..n, do: send(pid, {:ex_ratatui_event, key})
  end

  describe "parent exit" do
    @describetag :otp28

    test "overtakes a backed-up mailbox and still runs terminate/2" do
      {parent, pid} = start_under_fake_parent(worker_opts([]), fn _ -> exit(:shutdown) end)
      ref = Process.monitor(pid)

      flood(pid, @backlog)
      send(parent, :exit)

      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 1000
      assert_receive {:terminated, :shutdown, handled}
      assert handled < 200
    end

    test "overtakes the backlog on the SSH channel's shutdown-then-exit sequence" do
      stop = fn server ->
        Process.exit(server, :shutdown)
        exit(:normal)
      end

      {parent, pid} = start_under_fake_parent(worker_opts([]), stop)
      ref = Process.monitor(pid)

      flood(pid, @backlog)
      send(parent, :exit)

      # The channel's explicit `:shutdown` is an ordinary signal and stays
      # queued; the link EXIT (`:normal`) is the one that jumps ahead.
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
      assert_receive {:terminated, :normal, handled}
      assert handled < 200
    end
  end

  describe "parent exit without priority signals" do
    test "drains the mailbox before stopping" do
      {parent, pid} =
        start_under_fake_parent(worker_opts(priority_signals: false), fn _ -> exit(:shutdown) end)

      ref = Process.monitor(pid)

      flood(pid, 20)
      send(parent, :exit)

      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 2000
      assert_receive {:terminated, :shutdown, 20}
    end
  end

  describe "distributed client exit" do
    defp start_distributed(extra) do
      client = spawn(fn -> Process.sleep(:infinity) end)

      opts =
        worker_opts(extra)
        |> Keyword.delete(:test_mode)
        |> Keyword.put(:transport, {:distributed_server, client, 20, 5})

      {:ok, pid} = Server.start_link(opts)
      {client, pid}
    end

    @tag :otp28
    test "overtakes a backed-up mailbox" do
      {client, pid} = start_distributed([])
      ref = Process.monitor(pid)

      flood_keys(pid, @backlog)
      Process.exit(client, :kill)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
      assert_receive {:terminated, :normal, handled}
      assert handled < 200
    end

    test "drains the mailbox first without priority signals" do
      {client, pid} = start_distributed(priority_signals: false)
      ref = Process.monitor(pid)

      flood_keys(pid, 20)
      Process.exit(client, :kill)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2000
      assert_receive {:terminated, :normal, 20}
    end
  end
end
