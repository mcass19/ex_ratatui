defmodule TaskManager.Application do
  use Application

  @default_port 2222
  @default_user "demo"
  @default_password "demo"

  @impl true
  def start(_type, _args) do
    transport = detect_transport()
    Application.put_env(:task_manager, :transport, transport)

    children = [TaskManager.Repo] ++ tui_children(transport)

    opts = [strategy: :one_for_one, name: TaskManager.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp tui_children(_transport) do
    if Application.get_env(:task_manager, :start_tui, true) do
      case Application.get_env(:task_manager, :transport, :local) do
        :ssh -> [ssh_daemon_child_spec()]
        :local -> [{TaskManager.TUI, []}]
      end
    else
      []
    end
  end

  defp detect_transport do
    case System.get_env("TASK_MANAGER_SSH") do
      nil -> :local
      "" -> :local
      "0" -> :local
      "false" -> :local
      _ -> :ssh
    end
  end

  defp ssh_daemon_child_spec do
    port =
      case System.get_env("TASK_MANAGER_SSH_PORT") do
        nil -> @default_port
        str -> String.to_integer(str)
      end

    user = System.get_env("TASK_MANAGER_SSH_USER", @default_user)
    password = System.get_env("TASK_MANAGER_SSH_PASSWORD", @default_password)

    IO.puts("""

    \e[36mTask Manager over SSH\e[0m — listening on port #{port}

    Connect from another terminal:

        ssh #{user}@localhost -p #{port}

    Password: \e[1m#{password}\e[0m

    Multiple clients can attach concurrently — they all share the same
    SQLite task list, so changes made by one session will show up on
    every other session's next refresh.

    Ctrl-C twice to stop the daemon.
    """)

    {ExRatatui.SSH.Daemon,
     mod: TaskManager.TUI,
     port: port,
     system_dir: shared_host_key_dir(),
     auth_methods: ~c"password",
     user_passwords: [{String.to_charlist(user), String.to_charlist(password)}]}
  end

  # Host keys live under the system temp dir so the first run after a
  # reboot regenerates them (cheap) but repeated runs in the same
  # session reuse the same key. The directory name is shared with the
  # other ex_ratatui SSH examples (e.g. `examples/system_monitor.exs`)
  # on purpose — switching from one example to another on the same
  # port would otherwise trip `~/.ssh/known_hosts` with a "remote host
  # identification has changed" warning on every swap.
  #
  # The actual key generation is delegated to
  # `ExRatatui.SSH.Daemon.ensure_host_key!/1`. A real Phoenix app can
  # skip this entire helper and pass `auto_host_key: true` to the
  # daemon, which generates the key under the app's own `priv/ssh/`
  # directory — see the `phoenix_ex_ratatui_example` repo.
  defp shared_host_key_dir do
    [System.tmp_dir!(), "ex_ratatui_example_host_keys"]
    |> Path.join()
    |> ExRatatui.SSH.Daemon.ensure_host_key!()
  end
end
