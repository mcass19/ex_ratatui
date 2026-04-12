defmodule ExRatatui.Runtime do
  @moduledoc """
  Runtime inspection and trace controls for supervised ExRatatui applications.

  `snapshot/1` returns runtime metadata including:

    * runtime mode and transport
    * current dimensions
    * render counts and last render time
    * active subscriptions
    * active async command count
    * recent trace events when tracing is enabled

  `inject_event/2` delivers a synthetic terminal event through the same runtime
  transition path as a polled input event. This is useful for deterministic
  tests when an app is running under `test_mode`, which intentionally disables
  live terminal input polling.
  """

  @spec snapshot(GenServer.server()) :: map()
  def snapshot(server) do
    GenServer.call(server, :ex_ratatui_runtime_snapshot)
  end

  @spec enable_trace(GenServer.server(), keyword()) :: :ok
  def enable_trace(server, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)
    GenServer.call(server, {:ex_ratatui_runtime_trace, true, limit})
  end

  @spec disable_trace(GenServer.server()) :: :ok
  def disable_trace(server) do
    GenServer.call(server, {:ex_ratatui_runtime_trace, false, 0})
  end

  @spec trace_events(GenServer.server()) :: [map()]
  def trace_events(server) do
    snapshot(server).trace_events
  end

  @spec inject_event(
          GenServer.server(),
          ExRatatui.Event.Key.t() | ExRatatui.Event.Mouse.t() | ExRatatui.Event.Resize.t()
        ) :: :ok
  def inject_event(server, event) do
    GenServer.call(server, {:ex_ratatui_runtime_inject_event, event})
  end
end
