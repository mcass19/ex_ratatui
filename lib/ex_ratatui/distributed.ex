defmodule ExRatatui.Distributed do
  @moduledoc """
  Distribution-attach transport for `ExRatatui.App`.

  Lets any connected BEAM node attach to a TUI running
  on a remote node. The remote node runs the app's `mount/render/
  handle_event` callbacks and sends widget lists as BEAM terms over
  Erlang distribution. The local node renders those widgets on its own
  terminal and forwards input events back.

  ## Quick start

  On the app node (e.g. a Nerves device), add the Listener to your
  supervision tree:

      children = [
        {MyApp.TUI, transport: :distributed}
      ]

  On your local, connect and attach:

      $ iex --sname mynode --cookie mycookie -S mix

      ExRatatui.Distributed.attach(:"app@nerves.local", MyApp.TUI)

  The TUI takes over your terminal. Press the app's quit key (or
  Ctrl-C twice) to disconnect and restore the terminal.

  ## How it works

  1. `attach/2` connects to the remote node if not already connected.
  2. A local Client process initializes the terminal.
  3. An RPC call spawns a Server in `:distributed_server` mode on
     the remote node, pointing at the Client's pid — this process
     runs the app module and sends `{:ex_ratatui_draw, widgets}`
     messages directly to the Client over distribution.
  4. The Client starts monitoring the remote Server and polling
     input events, forwarding them as `{:ex_ratatui_event, event}`
     / `{:ex_ratatui_resize, w, h}`.
  5. When either side disconnects, monitors fire, both processes
     clean up, and the terminal is restored.

  ## Authentication

  Delegated entirely to the Erlang distribution cookie. If you can
  `Node.connect/1`, you can attach — same trust model as `iex --remsh`.
  """

  alias ExRatatui.Distributed.Client
  alias ExRatatui.Distributed.Listener

  @doc """
  Attaches to a TUI app running on a remote node.

  Connects to `node` (if not already connected), starts a remote
  session for `mod`, and takes over the local terminal. Blocks until
  the session ends (app stops, remote node disconnects, or the local
  process is interrupted).

  ## Options

    * `:listener` — the registered name of the `Distributed.Listener`
      on the remote node (default: `ExRatatui.Distributed.Listener`).
    * `:poll_interval` — local event polling interval in ms (default: 16).
    * `:test_mode` — `{width, height}` for a headless test terminal. In this
      mode the local client does not poll the live terminal for input.
    * `:image_protocol` — terminal image protocol hint for the local
      terminal: one of `:halfblocks` (default behavior, also the safe
      fallback), `:kitty`, `:sixel`, `:iterm2`, or `:auto` (clears the
      hint). Drives how `protocol: :auto` images are rendered. Explicit
      protocol picks at `ExRatatui.Image.new/2` are always honored.
    * `:image_font_size` — `{cell_width_px, cell_height_px}` for the
      local terminal. When set alongside `:image_protocol`, the render
      path uses the supplied dimensions for Kitty / Sixel / iTerm2
      scaling instead of ratatui-image's `(8, 16)` default. Pass values
      that match your terminal (typically `(10, 20)` for Kitty/Ghostty).

  Returns `:ok` when the session ends normally, or `{:error, reason}`.
  """
  @spec attach(node(), module(), keyword()) :: :ok | {:error, term()}
  def attach(node, mod, opts \\ []) when is_atom(node) and is_atom(mod) do
    listener = Keyword.get(opts, :listener, Listener)

    with :ok <- ensure_connected(node),
         {:ok, width, height} <- resolve_local_size(opts),
         {:ok, client_pid} <- start_local_client(opts) do
      # Start the remote session pointing at the Client GenServer
      # (not self()), so draws go directly to the rendering process.
      case start_remote_session(node, listener, client_pid, width, height) do
        {:ok, remote_pid} ->
          Client.connect_remote(client_pid, remote_pid)
          ref = Process.monitor(client_pid)

          receive do
            {:DOWN, ^ref, :process, ^client_pid, _reason} -> :ok
          end

        {:error, reason} ->
          GenServer.stop(client_pid)
          {:error, reason}
      end
    end
  end

  @doc false
  def ensure_connected(node) do
    if node == Node.self() do
      {:error, :cannot_attach_to_self}
    else
      case Node.connect(node) do
        true -> :ok
        false -> {:error, {:connect_failed, node}}
        :ignored -> {:error, :distribution_not_started}
      end
    end
  end

  @doc false
  def resolve_local_size(opts) do
    case Keyword.get(opts, :test_mode) do
      {w, h} ->
        {:ok, w, h}

      nil ->
        case ExRatatui.terminal_size() do
          {w, h} when is_integer(w) and is_integer(h) -> {:ok, w, h}
          {:error, reason} -> {:error, {:terminal_size_failed, reason}}
        end
    end
  end

  @doc false
  def start_remote_session(node, listener, client_pid, width, height) do
    case :rpc.call(node, Listener, :start_session, [client_pid, width, height, listener]) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, {:remote_session_failed, reason}}
      {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
    end
  end

  @doc false
  def start_local_client(opts) do
    client_opts =
      Keyword.take(opts, [
        :poll_interval,
        :test_mode,
        :init_terminal,
        :image_protocol,
        :image_font_size
      ])

    Client.start_link(client_opts)
  end
end
