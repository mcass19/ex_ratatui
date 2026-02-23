defmodule ExRatatui.Server do
  @moduledoc false

  use GenServer

  require Logger

  alias ExRatatui.Frame
  alias ExRatatui.Native

  defstruct [
    :mod,
    :user_state,
    :test_mode,
    :terminal_ref,
    poll_interval: 16,
    terminal_initialized: false
  ]

  @doc false
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    mod = Keyword.fetch!(opts, :mod)
    poll_interval = Keyword.get(opts, :poll_interval, 16)
    test_mode = Keyword.get(opts, :test_mode)

    Process.flag(:trap_exit, true)

    case init_terminal(test_mode) do
      {:error, reason} ->
        {:stop, {:terminal_init_failed, reason}}

      terminal_ref ->
        case mod.mount(opts) do
          {:ok, user_state} ->
            state = %__MODULE__{
              mod: mod,
              user_state: user_state,
              poll_interval: poll_interval,
              test_mode: test_mode,
              terminal_ref: terminal_ref,
              terminal_initialized: true
            }

            state = do_render(state)
            send(self(), :poll)

            {:ok, state}

          {:error, reason} ->
            restore_terminal(terminal_ref)
            {:stop, reason}
        end
    end
  end

  @impl true
  def handle_info(:poll, state) do
    result =
      case ExRatatui.poll_event(state.poll_interval) do
        nil ->
          {:continue, state, false}

        {:error, _} ->
          {:continue, state, false}

        event ->
          dispatch_event(state, event)
      end

    case result do
      {:stop, state} ->
        {:stop, :normal, state}

      {:continue, state, render?} ->
        state = if render?, do: do_render(state), else: state
        send(self(), :poll)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    case state.mod.handle_info(msg, state.user_state) do
      {:noreply, new_user_state} ->
        state = %{state | user_state: new_user_state}
        state = do_render(state)
        {:noreply, state}

      {:stop, new_user_state} ->
        {:stop, :normal, %{state | user_state: new_user_state}}
    end
  end

  @impl true
  def terminate(reason, %__MODULE__{terminal_initialized: true} = state) do
    restore_terminal(state.terminal_ref)
    state.mod.terminate(reason, state.user_state)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  ## Private helpers

  defp init_terminal(nil), do: Native.init_terminal()
  defp init_terminal({width, height}), do: ExRatatui.init_test_terminal(width, height)

  defp restore_terminal(terminal_ref) do
    Native.restore_terminal(terminal_ref)
  rescue
    e ->
      Logger.warning("Failed to restore terminal: #{Exception.message(e)}")
      :ok
  end

  defp dispatch_event(state, event) do
    case state.mod.handle_event(event, state.user_state) do
      {:noreply, new_user_state} ->
        {:continue, %{state | user_state: new_user_state}, true}

      {:stop, new_user_state} ->
        {:stop, %{state | user_state: new_user_state}}
    end
  end

  defp do_render(state) do
    {w, h} =
      case state.test_mode do
        {w, h} ->
          {w, h}

        nil ->
          case ExRatatui.terminal_size() do
            {w, h} when is_integer(w) and is_integer(h) -> {w, h}
            {:error, _} -> {80, 24}
          end
      end

    frame = %Frame{width: w, height: h}

    widgets = state.mod.render(state.user_state, frame)
    draw_widgets(state.terminal_ref, widgets)
    state
  rescue
    e ->
      Logger.error("ExRatatui render error: #{Exception.message(e)}")
      state
  end

  defp draw_widgets(_terminal_ref, []), do: :ok

  defp draw_widgets(terminal_ref, widgets) do
    case ExRatatui.draw(terminal_ref, widgets) do
      :ok -> :ok
      {:error, reason} -> Logger.error("ExRatatui draw error: #{inspect(reason)}")
    end
  end
end
