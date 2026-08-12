defmodule BurritoDemo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BurritoDemo.CLI
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: BurritoDemo.Supervisor)
  end
end
