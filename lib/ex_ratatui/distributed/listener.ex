defmodule ExRatatui.Distributed.Listener do
  @moduledoc """
  Supervisor for distribution-attach sessions on the app node.

  When an `ExRatatui.App` is started with `transport: :distributed`,
  `dispatch_start/1` starts this supervisor instead of the usual
  `ExRatatui.Server`. The Listener sits idle until a remote node calls
  `ExRatatui.Distributed.attach/2`, which triggers `start_session/4`
  to spawn a `Server` in `:distributed_server` mode under the
  Listener's `DynamicSupervisor`.

  ## Usage

  Typically you don't start this directly; `use ExRatatui.App` routes
  `start_link(transport: :distributed, ...)` through here:

      children = [
        {MyApp.TUI, transport: :distributed}
      ]

  For full control you can add it to a supervision tree by hand:

      children = [
        {ExRatatui.Distributed.Listener, mod: MyApp.TUI}
      ]
  """

  use Supervisor

  @config_table __MODULE__.Config

  @doc """
  Starts the Listener supervisor.

  ## Options

    * `:mod` (required) — the `ExRatatui.App` module to serve.
    * `:name` — process registration name (default: `__MODULE__`).
      Pass `nil` to skip registration.
    * `:app_opts` — extra opts merged into every client's `mount/1`
      callback (e.g. shared PubSub topic names).
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    if name do
      Supervisor.start_link(__MODULE__, opts, name: name)
    else
      Supervisor.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Returns the DynamicSupervisor pid used for per-attach sessions.
  """
  @spec session_sup(Supervisor.supervisor()) :: pid()
  def session_sup(listener \\ __MODULE__) do
    listener
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {_id, pid, :supervisor, _} -> pid
      _ -> nil
    end)
  end

  @impl true
  def init(opts) do
    mod = Keyword.fetch!(opts, :mod)
    app_opts = Keyword.get(opts, :app_opts, [])

    # ETS table stores {listener_pid, mod, app_opts} so start_session
    # can look up the config for this specific Listener instance.
    # Multiple Listeners in tests each get their own row.
    ensure_config_table()
    :ets.insert(@config_table, {self(), mod, app_opts})

    children = [
      {DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  # Called via RPC from the attaching node. Spawns a Server in
  # :distributed_server mode under the Listener's DynamicSupervisor.
  @spec start_session(pid(), non_neg_integer(), non_neg_integer(), Supervisor.supervisor()) ::
          {:ok, pid()} | {:error, term()}
  def start_session(client_pid, width, height, listener \\ __MODULE__) do
    listener_pid = resolve_pid(listener)
    [{^listener_pid, mod, app_opts}] = :ets.lookup(@config_table, listener_pid)
    sup = session_sup(listener)

    child_spec =
      %{
        id: make_ref(),
        start:
          {ExRatatui.Server, :start_link,
           [
             [
               mod: mod,
               name: nil,
               transport: {:distributed_server, client_pid, width, height}
             ] ++ app_opts
           ]},
        restart: :temporary
      }

    DynamicSupervisor.start_child(sup, child_spec)
  end

  defp ensure_config_table do
    if :ets.whereis(@config_table) == :undefined do
      :ets.new(@config_table, [:named_table, :public, :set])
    end
  rescue
    # Race condition: another process created the table between our
    # check and our create — that's fine.
    ArgumentError -> :ok
  end

  defp resolve_pid(pid) when is_pid(pid), do: pid
  defp resolve_pid(name) when is_atom(name), do: Process.whereis(name)
end
