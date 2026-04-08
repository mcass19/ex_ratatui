defmodule ExRatatui.Server do
  @moduledoc false

  use GenServer

  require Logger

  alias ExRatatui.Frame
  alias ExRatatui.Native
  alias ExRatatui.Session

  defstruct [
    :mod,
    :user_state,
    :test_mode,
    :terminal_ref,
    :session,
    :writer_fn,
    :width,
    :height,
    transport: :local,
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
    Process.flag(:trap_exit, true)

    case Keyword.get(opts, :transport, :local) do
      :local ->
        test_mode = Keyword.get(opts, :test_mode)
        init_terminal(test_mode) |> continue_init(opts)

      {:ssh, %Session{} = session, writer_fn} when is_function(writer_fn, 1) ->
        continue_init_ssh(session, writer_fn, opts)
    end
  end

  @doc false
  def continue_init({:error, reason}, _opts), do: {:stop, {:terminal_init_failed, reason}}

  def continue_init(terminal_ref, opts) do
    mod = Keyword.fetch!(opts, :mod)
    poll_interval = Keyword.get(opts, :poll_interval, 16)
    test_mode = Keyword.get(opts, :test_mode)

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

  @doc false
  # SSH transport init: the Session is created externally by the SSH
  # channel (which knows how to ship bytes back to the client), so this
  # path never touches the OS terminal. mount/1 sees augmented opts so an
  # app can opt into per-client behaviour without breaking the local case.
  def continue_init_ssh(%Session{} = session, writer_fn, opts) do
    mod = Keyword.fetch!(opts, :mod)
    {w, h} = Session.size(session)
    augmented_opts = augment_ssh_mount_opts(opts, w, h)

    case mod.mount(augmented_opts) do
      {:ok, user_state} ->
        state = %__MODULE__{
          mod: mod,
          user_state: user_state,
          transport: :ssh,
          session: session,
          writer_fn: writer_fn,
          width: w,
          height: h,
          terminal_initialized: true
        }

        state = do_render(state)
        {:ok, state}

      {:error, reason} ->
        Session.close(session)
        {:stop, reason}
    end
  end

  @doc false
  def augment_ssh_mount_opts(opts, width, height) do
    opts
    |> Keyword.put(:transport, :ssh)
    |> Keyword.put(:width, width)
    |> Keyword.put(:height, height)
  end

  @impl true
  def handle_info(:poll, %__MODULE__{transport: :local} = state) do
    state.poll_interval
    |> ExRatatui.poll_event()
    |> handle_poll_result(state)
    |> process_poll_result()
  end

  # Non-local transports are event-driven via mailbox messages from the
  # transport process — we silently absorb stray :poll messages so they
  # never reach the user module's handle_info/2.
  def handle_info(:poll, state), do: {:noreply, state}

  def handle_info({:ex_ratatui_event, event}, %__MODULE__{transport: :ssh} = state) do
    state
    |> dispatch_event(event)
    |> process_event_result()
  end

  def handle_info({:ex_ratatui_resize, w, h}, %__MODULE__{transport: :ssh} = state) do
    {:noreply, do_render(%{state | width: w, height: h})}
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
  def terminate(reason, %__MODULE__{transport: :local, terminal_initialized: true} = state) do
    restore_terminal(state.terminal_ref)
    state.mod.terminate(reason, state.user_state)
    :ok
  end

  def terminate(reason, %__MODULE__{transport: :ssh, terminal_initialized: true} = state) do
    Session.close(state.session)
    state.mod.terminate(reason, state.user_state)
    :ok
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  ## Extracted logic (@doc false, public for testability)

  @doc false
  def handle_poll_result(nil, state), do: {:continue, state, false}
  def handle_poll_result({:error, _}, state), do: {:continue, state, false}
  def handle_poll_result(event, state), do: dispatch_event(state, event)

  @doc false
  def dispatch_event(state, event) do
    case state.mod.handle_event(event, state.user_state) do
      {:noreply, new_user_state} ->
        {:continue, %{state | user_state: new_user_state}, true}

      {:stop, new_user_state} ->
        {:stop, %{state | user_state: new_user_state}}
    end
  end

  @doc false
  def process_poll_result({:stop, state}), do: {:stop, :normal, state}

  def process_poll_result({:continue, state, render?}) do
    state = if render?, do: do_render(state), else: state
    send(self(), :poll)
    {:noreply, state}
  end

  @doc false
  # SSH/distributed analogue of process_poll_result that does not re-arm a
  # poll loop — non-local transports get the next event from the mailbox.
  def process_event_result({:stop, state}), do: {:stop, :normal, state}

  def process_event_result({:continue, state, render?}) do
    state = if render?, do: do_render(state), else: state
    {:noreply, state}
  end

  @doc false
  def resolve_terminal_size({w, h}), do: {w, h}

  def resolve_terminal_size(nil) do
    ExRatatui.terminal_size() |> normalize_size_result()
  end

  @doc false
  def normalize_size_result({w, h}) when is_integer(w) and is_integer(h), do: {w, h}
  def normalize_size_result({:error, _}), do: {80, 24}

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

  defp do_render(state) do
    {w, h} = current_size(state)

    frame = %Frame{width: w, height: h}

    widgets = state.mod.render(state.user_state, frame)
    draw_widgets(state, widgets)
    state
  rescue
    e ->
      Logger.error(
        "ExRatatui render error: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      state
  end

  defp current_size(%__MODULE__{transport: :ssh, width: w, height: h}), do: {w, h}
  defp current_size(%__MODULE__{transport: :local, test_mode: tm}), do: resolve_terminal_size(tm)

  defp draw_widgets(_state, []), do: :ok

  defp draw_widgets(%__MODULE__{transport: :local, terminal_ref: terminal_ref}, widgets) do
    case ExRatatui.draw(terminal_ref, widgets) do
      :ok -> :ok
      {:error, reason} -> Logger.error("ExRatatui draw error: #{inspect(reason)}")
    end
  end

  defp draw_widgets(
         %__MODULE__{transport: :ssh, session: session, writer_fn: writer_fn},
         widgets
       ) do
    case Session.draw(session, widgets) do
      :ok ->
        bytes = Session.take_output(session)
        writer_fn.(bytes)
        :ok

      {:error, reason} ->
        Logger.error("ExRatatui session draw error: #{inspect(reason)}")
    end
  end
end
