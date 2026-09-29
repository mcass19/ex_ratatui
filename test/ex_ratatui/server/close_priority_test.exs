defmodule ExRatatui.Server.ClosePriorityTest do
  @moduledoc """
  A disconnect must stop the Server even when its mailbox is backed up.
  `GatedWorker` blocks the Server inside a callback while each test piles a
  backlog up behind it and fires the close; once the close signal is in the
  queue the test lets the Server go. On OTP 28+ the close overtakes the
  backlog (priority signals), so none of it is handled; without priority
  signals the whole backlog drains first.
  """

  use ExUnit.Case, async: true

  alias ExRatatui.Event.Key
  alias ExRatatui.Server
  alias ExRatatui.Test.Mailbox
  alias ExRatatui.Test.ServerApps.GatedWorker

  @backlog 50

  # Starts the Server from a throwaway process so the test can make that
  # parent exit on demand, the way an SSH channel or a crashing parent would.
  defp start_under_fake_parent(extra, exit_fun) do
    test_pid = self()

    parent =
      spawn(fn ->
        {:ok, pid} = Server.start_link(worker_opts(test_pid, extra))
        send(test_pid, {:server, pid})

        receive do
          :exit -> exit_fun.(pid)
        end
      end)

    assert_receive {:server, pid}, 1000
    cleanup([parent, pid])
    {parent, pid}
  end

  defp start_distributed(extra) do
    client = spawn(fn -> Process.sleep(:infinity) end)

    opts =
      worker_opts(self(), extra)
      |> Keyword.delete(:test_mode)
      |> Keyword.put(:transport, {:distributed_server, client, 20, 5})

    {:ok, pid} = Server.start_link(opts)
    cleanup([client, pid])
    {client, pid}
  end

  defp worker_opts(test_pid, extra) do
    Keyword.merge([mod: GatedWorker, name: nil, test_pid: test_pid, test_mode: {20, 5}], extra)
  end

  # A failing assertion would otherwise leave a Server blocked at the gate.
  defp cleanup(pids), do: on_exit(fn -> Enum.each(pids, &Process.exit(&1, :kill)) end)

  # Blocks the Server at the gate, queues the backlog behind it, runs
  # `close` and waits until its `signals` exit/down messages have landed
  # too, then releases the Server.
  defp backlog_then_close(pid, backlog, close, signals) do
    send(pid, :gate)
    assert_receive :gated, 1000

    backlog.()
    close.()

    Mailbox.wait_for_len(pid, @backlog + signals)
    send(pid, :release)
  end

  defp work(pid), do: fn -> for(_ <- 1..@backlog, do: send(pid, :work)) end

  defp keys(pid) do
    key = %Key{code: "x", modifiers: [], kind: "press"}
    fn -> for(_ <- 1..@backlog, do: send(pid, {:ex_ratatui_event, key})) end
  end

  describe "parent exit" do
    @describetag :otp28

    test "overtakes a backed-up mailbox and still runs terminate/2" do
      {parent, pid} = start_under_fake_parent([], fn _ -> exit(:shutdown) end)
      ref = Process.monitor(pid)

      backlog_then_close(pid, work(pid), fn -> send(parent, :exit) end, 1)

      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 1000
      assert_receive {:terminated, :shutdown, 0}
    end

    test "overtakes the backlog on the SSH channel's shutdown-then-exit sequence" do
      stop = fn server ->
        Process.exit(server, :shutdown)
        exit(:normal)
      end

      {parent, pid} = start_under_fake_parent([], stop)
      ref = Process.monitor(pid)

      backlog_then_close(pid, work(pid), fn -> send(parent, :exit) end, 2)

      # The channel's explicit `:shutdown` is an ordinary signal and stays
      # queued; the link EXIT (`:normal`) is the one that jumps ahead.
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
      assert_receive {:terminated, :normal, 0}
    end
  end

  describe "parent exit without priority signals" do
    test "drains the mailbox before stopping" do
      {parent, pid} =
        start_under_fake_parent([priority_signals: false], fn _ -> exit(:shutdown) end)

      ref = Process.monitor(pid)

      backlog_then_close(pid, work(pid), fn -> send(parent, :exit) end, 1)

      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 1000
      assert_receive {:terminated, :shutdown, @backlog}
    end
  end

  describe "distributed client exit" do
    @tag :otp28
    test "overtakes a backed-up mailbox" do
      {client, pid} = start_distributed([])
      ref = Process.monitor(pid)

      backlog_then_close(pid, keys(pid), fn -> Process.exit(client, :kill) end, 1)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
      assert_receive {:terminated, :normal, 0}
    end

    test "drains the mailbox first without priority signals" do
      {client, pid} = start_distributed(priority_signals: false)
      ref = Process.monitor(pid)

      backlog_then_close(pid, keys(pid), fn -> Process.exit(client, :kill) end, 1)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
      assert_receive {:terminated, :normal, @backlog}
    end
  end
end
