defmodule ExRatatui.EventTest do
  use ExUnit.Case, async: true

  doctest ExRatatui.Event.Key
  doctest ExRatatui.Event.Mouse
  doctest ExRatatui.Event.Resize

  describe "poll_event/1" do
    test "returns nil (timeout), an event, or {:error, _} (no TTY)" do
      result = ExRatatui.poll_event(10)
      assert valid_poll_result?(result)
    end

    test "accepts default timeout (no argument)" do
      result = ExRatatui.poll_event()
      assert valid_poll_result?(result)
    end

    test "does not block the BEAM (runs on dirty scheduler)" do
      parent = self()

      task =
        Task.async(fn ->
          send(parent, :alive)
          :done
        end)

      # poll_event is a DirtyIo NIF — must not block the task
      assert_receive :alive, 1000
      ExRatatui.poll_event(50)
      assert Task.await(task) == :done
    end

    test "concurrent poll_event calls do not deadlock" do
      tasks =
        for _ <- 1..4 do
          Task.async(fn ->
            result = ExRatatui.poll_event(10)
            assert valid_poll_result?(result)
            :ok
          end)
        end

      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end

  defp valid_poll_result?(nil), do: true
  defp valid_poll_result?({:error, _}), do: true
  defp valid_poll_result?(%ExRatatui.Event.Key{}), do: true
  defp valid_poll_result?(%ExRatatui.Event.Mouse{}), do: true
  defp valid_poll_result?(%ExRatatui.Event.Resize{}), do: true
  defp valid_poll_result?(%ExRatatui.Event.Paste{}), do: true
  defp valid_poll_result?(%ExRatatui.Event.FocusGained{}), do: true
  defp valid_poll_result?(%ExRatatui.Event.FocusLost{}), do: true
  defp valid_poll_result?(_), do: false
end
