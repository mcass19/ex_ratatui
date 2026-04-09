defmodule ExRatatui.SSH.Daemon do
  @moduledoc """
  GenServer that owns an OTP `:ssh.daemon/2` listening for TUI clients.

  This is the transport-level supervisor for `ExRatatui.App` under
  `transport: :ssh`. It starts an `:ssh` daemon on the requested port,
  registers the app module as an SSH subsystem + default shell, and
  tears the daemon down on shutdown. Each connected SSH client gets its
  own `ExRatatui.SSH` channel process, which in turn supervises its own
  internal server running the app — so a single `Daemon` can serve
  many concurrent clients without any shared state between them.

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
      free port — call `port/1` on the daemon pid to discover the chosen
      port.
    * `:system_dir` — path to the daemon's host key directory, forwarded
      as-is to `:ssh.daemon/2`. May be a binary or charlist; binaries are
      converted automatically.
    * `:auto_host_key` (default `false`) — when `true`, the daemon resolves
      the OTP application that owns `:mod`, ensures `<priv_dir>/ssh/`
      exists, and generates a 2048-bit RSA host key there on first boot
      (`ssh_host_rsa_key`). Subsequent boots reuse the same key. Set
      `:system_dir` explicitly to override the directory; passing both
      raises. Intended for "drop into a supervision tree and it just
      works" setups (Phoenix admin TUIs, internal tools); production
      deployments should keep an explicit `:system_dir` under their own
      configuration management.
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
    opts = resolve_host_key_opts(opts, mod)
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
      :transport,
      :auto_host_key
    ])
    |> normalize_system_dir()
    |> Keyword.merge(base)
  end

  @doc false
  # If `:auto_host_key` is set, derive a `:system_dir` under the OTP
  # app's priv dir, generating a fresh RSA host key on first boot. This
  # lets callers drop `ExRatatui.SSH.Daemon` straight into a supervision
  # tree without managing host keys themselves.
  def resolve_host_key_opts(opts, mod) do
    case Keyword.pop(opts, :auto_host_key, false) do
      {false, opts} ->
        opts

      {true, opts} ->
        if Keyword.has_key?(opts, :system_dir) do
          raise ArgumentError,
                "ExRatatui.SSH.Daemon: cannot pass both :auto_host_key and :system_dir — pick one"
        end

        system_dir = ensure_app_host_key!(mod)
        Keyword.put(opts, :system_dir, system_dir)

      {other, _opts} ->
        raise ArgumentError,
              "ExRatatui.SSH.Daemon: :auto_host_key must be a boolean, got: #{inspect(other)}"
    end
  end

  @doc false
  # Resolves the OTP app for `mod` and delegates to `ensure_host_key!/1`
  # against `<priv_dir>/ssh/`. Raises if the module isn't part of any
  # loaded application.
  def ensure_app_host_key!(mod) do
    otp_app =
      case Application.get_application(mod) do
        nil ->
          raise ArgumentError,
                "ExRatatui.SSH.Daemon: could not resolve OTP application for #{inspect(mod)} — " <>
                  "pass :system_dir explicitly instead of :auto_host_key"

        app ->
          app
      end

    otp_app
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("ssh")
    |> ensure_host_key!()
  end

  @doc false
  # Ensures `dir` exists and contains an `ssh_host_rsa_key`. Generates a
  # fresh 2048-bit RSA key on first call, then leaves it alone on every
  # subsequent call. Returns the directory as a charlist (the shape OTP
  # `:ssh.daemon/2` wants for `:system_dir`).
  def ensure_host_key!(dir) when is_binary(dir) do
    File.mkdir_p!(dir)
    key_path = Path.join(dir, "ssh_host_rsa_key")

    unless File.exists?(key_path) do
      Logger.info("ExRatatui.SSH.Daemon generating SSH host key at #{key_path}")
      generate_rsa_host_key!(key_path)
    end

    String.to_charlist(dir)
  end

  defp generate_rsa_host_key!(path) do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    pem = :public_key.pem_encode([pem_entry])
    File.write!(path, pem)
    File.chmod!(path, 0o600)
  end

  defp normalize_system_dir(opts) do
    case Keyword.get(opts, :system_dir) do
      nil -> opts
      dir when is_list(dir) -> opts
      dir when is_binary(dir) -> Keyword.put(opts, :system_dir, String.to_charlist(dir))
    end
  end
end
