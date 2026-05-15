defmodule BurritoDemo.CLI do
  @moduledoc """
  Burrito entry point. Boots the counter TUI, waits for it to exit, and
  stops the VM so the wrapper returns control to the shell.

  Recognises a `--version` flag for non-interactive smoke tests — CI uses
  it to assert that the wrapped binary boots and loads the NIF without
  needing a TTY.
  """

  @version Mix.Project.config()[:version]

  def main(argv) do
    case argv do
      ["--version" | _] ->
        IO.puts("burrito_demo #{@version}")
        System.stop(0)

      _ ->
        run_tui()
    end
  end

  defp run_tui do
    {:ok, pid} = BurritoDemo.Counter.start_link([])
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end

    System.stop(0)
  end
end
