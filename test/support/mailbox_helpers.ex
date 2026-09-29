defmodule ExRatatui.Test.Mailbox do
  @moduledoc """
  Waits on another process's message queue, for tests that pile a backlog up
  behind a blocked server and need every message (or exit signal) to have
  landed before they let it go.
  """

  import ExUnit.Assertions

  @doc "Waits until `pid` has at least `n` messages queued, or flunks after `timeout` ms."
  def wait_for_len(pid, n, timeout \\ 1_000) do
    do_wait(pid, n, System.monotonic_time(:millisecond) + timeout)
  end

  defp do_wait(pid, n, deadline) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} when len >= n ->
        :ok

      nil ->
        flunk("#{inspect(pid)} exited while waiting for #{n} queued messages")

      {:message_queue_len, len} ->
        if System.monotonic_time(:millisecond) > deadline do
          flunk("#{inspect(pid)} has #{len} queued messages, expected at least #{n}")
        end

        Process.sleep(1)
        do_wait(pid, n, deadline)
    end
  end
end
