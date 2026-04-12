defmodule ExRatatui.Distributed.Client do
  @moduledoc false

  # Thin rendering proxy for distribution-attach.
  #
  # Takes over the local terminal, polls for input events and forwards
  # them to the remote Server as {:ex_ratatui_event, event} /
  # {:ex_ratatui_resize, w, h}. Receives {:ex_ratatui_draw, widgets}
  # from the remote Server and renders them locally with the real
  # TerminalResource.
  #
  # This is NOT an ExRatatui.App — it has no mount/render/handle_event
  # callbacks. It is a dedicated proxy process that bridges the local
  # terminal to a remote distributed_server.
  #
  # Startup is two-phase:
  #   1. start_link/1 initializes the terminal (no remote pid yet).
  #   2. connect_remote/2 sets the remote pid, starts monitoring it,
  #      and begins polling for input events.
  #
  # This split lets attach/3 pass the Client's pid to the remote
  # Server so draws go directly to the rendering process.

  use GenServer

  require Logger

  alias ExRatatui.Event
  alias ExRatatui.Native

  defstruct [
    :terminal_ref,
    :remote_pid,
    :test_mode,
    poll_interval: 16,
    terminal_initialized: false
  ]

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  def connect_remote(client, remote_pid) do
    GenServer.call(client, {:connect_remote, remote_pid})
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    remote_pid = Keyword.get(opts, :remote_pid)
    poll_interval = Keyword.get(opts, :poll_interval, 16)
    test_mode = Keyword.get(opts, :test_mode)

    init_fn = Keyword.get(opts, :init_terminal, &default_init_terminal/1)

    case init_fn.(test_mode) do
      {:error, reason} ->
        {:stop, {:terminal_init_failed, reason}}

      terminal_ref ->
        state = %__MODULE__{
          terminal_ref: terminal_ref,
          remote_pid: remote_pid,
          poll_interval: poll_interval,
          test_mode: test_mode,
          terminal_initialized: true
        }

        if remote_pid do
          Process.monitor(remote_pid)
          send(self(), :poll)
        end

        {:ok, state}
    end
  end

  @impl true
  def handle_call({:connect_remote, remote_pid}, _from, state) do
    Process.monitor(remote_pid)
    send(self(), :poll)
    {:reply, :ok, %{state | remote_pid: remote_pid}}
  end

  @impl true
  def handle_info(:poll, state) do
    state.poll_interval
    |> ExRatatui.poll_event()
    |> handle_poll_result(state)
  end

  def handle_info({:ex_ratatui_draw, widgets}, state) do
    draw_widgets(state, widgets)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{remote_pid: pid} = state) do
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %__MODULE__{terminal_initialized: true} = state) do
    restore_terminal(state.terminal_ref)
    :ok
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  ## Extracted logic (@doc false, public for testability)

  @doc false
  def handle_poll_result(nil, state), do: {:noreply, rearm_poll(state)}
  def handle_poll_result({:error, _}, state), do: {:noreply, rearm_poll(state)}

  def handle_poll_result(%Event.Resize{width: w, height: h}, state) do
    send(state.remote_pid, {:ex_ratatui_resize, w, h})
    {:noreply, rearm_poll(state)}
  end

  def handle_poll_result(event, state) do
    send(state.remote_pid, {:ex_ratatui_event, event})
    {:noreply, rearm_poll(state)}
  end

  ## Private helpers

  defp rearm_poll(state) do
    send(self(), :poll)
    state
  end

  @doc false
  def default_init_terminal(nil), do: Native.init_terminal()
  def default_init_terminal({width, height}), do: ExRatatui.init_test_terminal(width, height)

  defp restore_terminal(terminal_ref) do
    Native.restore_terminal(terminal_ref)
  rescue
    e ->
      Logger.warning("Failed to restore terminal: #{Exception.message(e)}")
      :ok
  end

  defp draw_widgets(_state, []), do: :ok

  defp draw_widgets(%__MODULE__{terminal_ref: terminal_ref}, widgets) do
    case ExRatatui.draw(terminal_ref, widgets) do
      :ok -> :ok
      {:error, reason} -> Logger.error("ExRatatui draw error: #{inspect(reason)}")
    end
  end
end
