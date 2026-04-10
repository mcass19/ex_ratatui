defmodule ExRatatui.Runtime do
  @moduledoc """
  Runtime inspection and trace controls for supervised ExRatatui applications.
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
end
