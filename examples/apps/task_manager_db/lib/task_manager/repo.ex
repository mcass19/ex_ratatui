defmodule TaskManager.Repo do
  use Ecto.Repo,
    otp_app: :task_manager,
    adapter: Ecto.Adapters.SQLite3
end
