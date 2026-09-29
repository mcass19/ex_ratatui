defmodule ExRatatui.Server.MailboxPressureTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ExRatatui.Server

  defmodule QuietApp do
    use ExRatatui.App

    @impl true
    def mount(_opts), do: {:ok, %{}}

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, state), do: {:noreply, state}

    @impl true
    def handle_info(:work, state), do: {:noreply, state, render?: false}
  end

  @doc false
  def __forward__(_event, measurements, meta, test_pid) do
    if meta.mod == QuietApp, do: send(test_pid, {:mailbox, measurements, meta})
  end

  setup do
    handler_id = "mailbox-test-#{inspect(self())}"

    :telemetry.attach(
      handler_id,
      [:ex_ratatui, :runtime, :mailbox],
      &__MODULE__.__forward__/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  defp start(opts) do
    {:ok, pid} =
      Server.start_link([mod: QuietApp, name: nil, test_mode: {20, 5}] ++ opts)

    pid
  end

  # Queues `n` messages while the server is suspended, so it sees them all
  # at once, then waits until it has worked through them.
  defp flood(pid, n) do
    :ok = :sys.suspend(pid)
    for _ <- 1..n, do: send(pid, :work)
    :ok = :sys.resume(pid)
    :sys.get_state(pid)
  end

  test "fires once per crossing and re-arms after the queue drains" do
    pid = start(mailbox_warn_threshold: 10)

    capture_log(fn ->
      flood(pid, 30)
      assert_received {:mailbox, %{message_queue_len: len}, meta}
      assert len >= 10
      assert meta.threshold == 10
      assert meta.transport == :local
      refute_received {:mailbox, _, _}
      refute :sys.get_state(pid).mailbox.alarm?

      flood(pid, 30)
      assert_received {:mailbox, %{message_queue_len: _}, _}
      refute_received {:mailbox, _, _}
    end)

    GenServer.stop(pid)
  end

  test "stays quiet below the threshold" do
    pid = start(mailbox_warn_threshold: 50)
    flood(pid, 30)
    refute_received {:mailbox, _, _}
    GenServer.stop(pid)
  end

  test "logs a warning at most once per interval" do
    pid = start(mailbox_warn_threshold: 10)

    log =
      capture_log(fn ->
        flood(pid, 30)
        warned_at = :sys.get_state(pid).mailbox.warned_at
        assert is_integer(warned_at)

        flood(pid, 30)
        assert :sys.get_state(pid).mailbox.warned_at == warned_at
      end)

    assert_received {:mailbox, _, _}
    assert_received {:mailbox, _, _}

    warnings =
      log
      |> String.split("\n")
      |> Enum.filter(&(&1 =~ "ExRatatui runtime for #{inspect(QuietApp)} has"))

    assert length(warnings) == 1
    assert hd(warnings) =~ "(threshold 10)"
    GenServer.stop(pid)
  end

  test "false disables the check" do
    pid = start(mailbox_warn_threshold: false)
    flood(pid, 30)
    refute_received {:mailbox, _, _}
    GenServer.stop(pid)
  end

  test "defaults to a threshold of 10_000" do
    pid = start([])
    assert :sys.get_state(pid).mailbox.warn_threshold == 10_000
    GenServer.stop(pid)
  end

  @tag capture_log: true
  test "rejects an invalid threshold" do
    Process.flag(:trap_exit, true)

    for bad <- [0, -1, :lots, 1.5] do
      assert {:error, {%ArgumentError{message: message}, _}} =
               Server.start_link(
                 mod: QuietApp,
                 name: nil,
                 test_mode: {20, 5},
                 mailbox_warn_threshold: bad
               )

      assert message =~ ":mailbox_warn_threshold"
    end
  end
end
