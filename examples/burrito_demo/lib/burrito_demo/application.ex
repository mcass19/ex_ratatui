defmodule BurritoDemo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task, fn -> BurritoDemo.CLI.main(Burrito.Util.Args.argv()) end}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: BurritoDemo.Supervisor)
  end
end
