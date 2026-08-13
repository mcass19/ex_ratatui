defmodule BurritoDemo.CLI do
  @moduledoc """
  Burrito entry point — a thin shim over `ExRatatui.Burrito.start_link/3`,
  so entry-point protocol fixes ship with ex_ratatui upgrades instead of
  freezing here.

  Runs as a supervised `Task` keyed on this module, so regenerating the
  wiring stays idempotent and unrelated `Task` children are left alone.
  Inside a burrito-wrapped binary the TUI runs synchronously and keeps the
  VM alive; under `mix test` and `iex -S mix` it is an async no-op that
  never takes over the session. `--version` anywhere in argv prints the
  version for non-interactive smoke tests, and the VM exits non-zero when
  the TUI crashes or fails to start.
  """

  use Task

  @version Mix.Project.config()[:version]

  def start_link(_arg) do
    ExRatatui.Burrito.start_link(BurritoDemo.Counter, Burrito.Util.Args.argv(),
      name: "burrito_demo",
      version: @version
    )
  end
end
