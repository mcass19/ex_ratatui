defmodule ExRatatui.SSH.Daemon do
  @moduledoc """
  GenServer that owns an OTP `:ssh.daemon/2` listening for TUI clients.

  This is the transport-level supervisor for `ExRatatui.App` under
  `transport: :ssh`. It starts an `:ssh` daemon on the requested port,
  registers the app module as an SSH subsystem + default shell, and
  tears the daemon down on shutdown. Each connected SSH client gets its
  own `ExRatatui.SSH` channel process, which in turn supervises its own
  `ExRatatui.Server` — so a single `Daemon` can serve many concurrent
  clients without any shared state between them.

  ## Usage

  Typically you don't start this directly; `use ExRatatui.App` routes
  `start_link(transport: :ssh, ...)` through here. But for full control
  you can add it to a supervision tree by hand:

      children = [
        {ExRatatui.SSH.Daemon,
         mod: MyApp.TUI,
         port: 2222,
         system_dir: ~c"/etc/ssh",
         user_dir: ~c"/var/ssh/users"}
      ]

  ## Options

    * `:mod` (required) — the `ExRatatui.App` module to serve.
    * `:port` (default `2222`) — TCP port to listen on. `0` picks a random
      free port — use `daemon_info/1` to find it.
    * `:system_dir` — path to the daemon's host key directory, forwarded
      as-is to `:ssh.daemon/2`.
    * `:user_dir` — path to client-authentication key material.
    * `:authorized_keys` — forwarded through to `:ssh.daemon/2`.
    * `:name` — process name (default `__MODULE__`, pass `nil` to skip).
    * `:app_opts` — extra opts that will be merged into every client's
      `mount/1` callbacks (e.g. shared PubSub topic names).
    * Any other keyword pair is forwarded verbatim to `:ssh.daemon/2`, so
      e.g. `:pwdfun`, `:idle_time`, `:profile` all work unchanged.

  ## Testability

  `:daemon_starter` and `:daemon_stopper` keyword options let tests
  substitute fakes for `&:ssh.daemon/2` and `&:ssh.stop_daemon/1` so the
  GenServer can be exercised without starting a real SSH listener. The
  real functions are the defaults; production callers never pass either.
  """

  use GenServer

  require Logger

  @default_port 2222
  @default_daemon_starter &:ssh.daemon/2
  @default_daemon_stopper &:ssh.stop_daemon/1

  defstruct [
    :mod,
    :daemon_ref,
    :port,
    :daemon_stopper
  ]

  @type t :: %__MODULE__{
          mod: module(),
          daemon_ref: term() | nil,
          port: non_neg_integer(),
          daemon_stopper: (term() -> :ok)
        }

  @doc """
  Starts a supervised SSH daemon serving the given `ExRatatui.App`
  module. Returns the daemon's process pid on success.

  See the module docs for the full list of accepted options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Returns the `{:ok, daemon_ref}` handle of the underlying OTP `:ssh`
  daemon, or `{:error, :not_started}` if it isn't up.
  """
  @spec daemon_ref(GenServer.server()) :: {:ok, term()} | {:error, :not_started}
  def daemon_ref(server \\ __MODULE__) do
    GenServer.call(server, :daemon_ref)
  end

  @doc """
  Returns the port the daemon is listening on.
  """
  @spec port(GenServer.server()) :: non_neg_integer()
  def port(server \\ __MODULE__) do
    GenServer.call(server, :port)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    mod = Keyword.fetch!(opts, :mod)
    port = Keyword.get(opts, :port, @default_port)
    starter = Keyword.get(opts, :daemon_starter, @default_daemon_starter)
    stopper = Keyword.get(opts, :daemon_stopper, @default_daemon_stopper)
    daemon_opts = build_daemon_opts(mod, opts)

    case starter.(port, daemon_opts) do
      {:ok, daemon_ref} ->
        {:ok,
         %__MODULE__{
           mod: mod,
           daemon_ref: daemon_ref,
           port: port,
           daemon_stopper: stopper
         }}

      {:error, reason} ->
        Logger.error("ExRatatui.SSH.Daemon failed to start: #{inspect(reason)}")
        {:stop, {:ssh_daemon_failed, reason}}
    end
  end

  @impl true
  def handle_call(:daemon_ref, _from, %__MODULE__{daemon_ref: nil} = state) do
    {:reply, {:error, :not_started}, state}
  end

  def handle_call(:daemon_ref, _from, %__MODULE__{daemon_ref: ref} = state) do
    {:reply, {:ok, ref}, state}
  end

  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  @impl true
  def terminate(_reason, %__MODULE__{daemon_ref: nil}), do: :ok

  def terminate(_reason, %__MODULE__{daemon_ref: ref, daemon_stopper: stopper}) do
    _ = stopper.(ref)
    :ok
  end

  ## Internal helpers (@doc false, public for unit-testability)

  @doc false
  # Turns the Daemon's start_link opts into the shape `:ssh.daemon/2`
  # wants. All transport/infra knobs (`:mod`, `:port`, `:name`, etc.) are
  # stripped; everything else is forwarded as-is so OTP's own `:ssh`
  # options (system_dir, user_dir, authorized_keys, pwdfun, idle_time,
  # profile, ...) keep working.
  def build_daemon_opts(mod, opts) do
    app_opts = Keyword.get(opts, :app_opts, [])

    # `ssh_cli: {M, Args}` replaces OTP's default shell channel handler
    # with ours, so shell _and_ subsystem requests flow through
    # ExRatatui.SSH.handle_ssh_msg/2. The subsystem list is a
    # belt-and-braces so named-subsystem clients work identically; we
    # bake the same args into it so `:app_opts` reaches mount/1 either
    # way.
    cli_args = [mod: mod, app_opts: app_opts]

    {name, _} = ExRatatui.SSH.subsystem(mod)
    subsystem = {name, {ExRatatui.SSH, cli_args}}

    base = [
      ssh_cli: {ExRatatui.SSH, cli_args},
      subsystems: [subsystem],
      exec: :disabled
    ]

    opts
    |> Keyword.drop([
      :mod,
      :port,
      :name,
      :daemon_starter,
      :daemon_stopper,
      :app_opts,
      :transport
    ])
    |> Keyword.merge(base)
  end
end
