import Config

config :task_manager, TaskManager.Repo,
  database: Path.expand("../task_manager_#{config_env()}.db", __DIR__),
  pool_size: 5

config :task_manager,
  ecto_repos: [TaskManager.Repo]

import_config "#{config_env()}.exs"
