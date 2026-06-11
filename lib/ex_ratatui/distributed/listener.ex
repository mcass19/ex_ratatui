defmodule ExRatatui.Distributed.Listener do
  @moduledoc """
  Supervisor for distribution-attach sessions on the app node.

  When an `ExRatatui.App` is started with `transport: :distributed`,
  `dispatch_start/1` starts this supervisor instead of the usual
  Server process. The Listener sits idle until a remote node calls
  `ExRatatui.Distributed.attach/2`, which triggers `start_session/4`
  to spawn a Server in `:distributed_server` mode under the
  Listener's `DynamicSupervisor`.

  ## Usage

  Typically this isn't started directly; `use ExRatatui.App` routes
  `start_link(transport: :distributed, ...)` through here:

      children = [
        {MyApp.TUI, transport: :distributed}
      ]

  For full control, add it to a supervision tree by hand:

      children = [
        {ExRatatui.Distributed.Listener, mod: MyApp.TUI}
      ]
  """

  use Supervisor

  # Marker behaviour: Distributed doesn't use ByteStream (it ships
  # widget trees over BEAM distribution instead of raw bytes), but it
  # still implements the Transport contract — child_spec/1 comes from
  # `use Supervisor`, and remote events flow to Server via the same
  # `{:ex_ratatui_event, _}` / `{:ex_ratatui_resize, _, _}` mailbox
  # messages documented on ExRatatui.Transport.
  @behaviour ExRatatui.Transport

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
    [{_id, pid, :supervisor, _}] = Supervisor.which_children(listener)
    pid
  end

  @impl true
  def init(opts) do
    mod = Keyword.fetch!(opts, :mod)
    app_opts = Keyword.get(opts, :app_opts, [])

    # Stash config keyed by this listener's pid so start_session can
    # look it up. persistent_term is node-local and survives across
    # RPC calls from other nodes. The entry is small (~100 bytes) and
    # keyed by pid, so it becomes unreachable once the Listener exits.
    # Supervisor does not call terminate/2 on its callback module, so
    # we accept the orphaned entry — Listeners are long-lived
    # supervisors that rarely restart.
    :persistent_term.put({__MODULE__, self()}, %{mod: mod, app_opts: app_opts})

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
    %{mod: mod, app_opts: app_opts} = :persistent_term.get({__MODULE__, listener_pid})
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

  defp resolve_pid(pid) when is_pid(pid), do: pid
  defp resolve_pid(name) when is_atom(name), do: Process.whereis(name)
end
