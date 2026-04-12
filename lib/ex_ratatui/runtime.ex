defmodule ExRatatui.Runtime do
  @moduledoc """
  Runtime inspection and trace controls for supervised ExRatatui applications.

  `snapshot/1` returns runtime metadata including:

    * `:mode`, `:mod`, and `:transport`
    * `:dimensions` and `:polling_enabled?`
    * `:render_count` and `:last_rendered_at`
    * `:subscription_count` and `:subscriptions`
    * `:active_async_commands`
    * `:trace_enabled?`, `:trace_limit`, and `:trace_events`

  `inject_event/2` delivers a synthetic terminal event through the same runtime
  transition path as a polled input event. This is useful for deterministic
  tests when an app is running under `test_mode`, which intentionally disables
  live terminal input polling.
  """

  @doc """
  Returns a snapshot of a supervised app's runtime state.

  The returned map is intended for debugging, tests, and runtime introspection.
  Under `test_mode`, `:polling_enabled?` is `false`, which makes it easy to
  assert the server is running headlessly.
  """
  @spec snapshot(GenServer.server()) :: map()
  def snapshot(server) do
    GenServer.call(server, :ex_ratatui_runtime_snapshot)
  end

  @doc """
  Enables in-memory runtime tracing for `server`.

  ## Options

    * `:limit` — maximum number of recent trace events to retain in memory.
      Defaults to `200`.
  """
  @spec enable_trace(GenServer.server(), keyword()) :: :ok
  def enable_trace(server, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)
    GenServer.call(server, {:ex_ratatui_runtime_trace, true, limit})
  end

  @doc """
  Disables runtime tracing for `server` and clears retained trace events.
  """
  @spec disable_trace(GenServer.server()) :: :ok
  def disable_trace(server) do
    GenServer.call(server, {:ex_ratatui_runtime_trace, false, 0})
  end

  @doc """
  Returns the current trace event list for `server`.

  This is shorthand for `snapshot(server).trace_events`.
  """
  @spec trace_events(GenServer.server()) :: [map()]
  def trace_events(server) do
    snapshot(server).trace_events
  end

  @doc """
  Injects a synthetic terminal event into `server`.

  This follows the same event path as a real polled input event, so it works
  for both callback-runtime and reducer-runtime apps. It is primarily useful
  under `test_mode`, where live terminal polling is intentionally disabled.
  """
  @spec inject_event(
          GenServer.server(),
          ExRatatui.Event.Key.t() | ExRatatui.Event.Mouse.t() | ExRatatui.Event.Resize.t()
        ) :: :ok
  def inject_event(server, event) do
    GenServer.call(server, {:ex_ratatui_runtime_inject_event, event})
  end
end
