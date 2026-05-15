defmodule BurritoDemo.CLI do
  @moduledoc """
  Burrito entry point. Boots the counter TUI, waits for it to exit, and
  stops the VM so the wrapper returns control to the shell.
  """

  def main(_argv) do
    {:ok, pid} = BurritoDemo.Counter.start_link([])
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end

    System.stop(0)
  end
end
