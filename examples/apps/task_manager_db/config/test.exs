import Config

config :task_manager, TaskManager.Repo,
  database: Path.expand("../task_manager_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning

config :task_manager, start_tui: false
