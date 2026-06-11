defmodule ExRatatui.Telemetry do
  @moduledoc """
  Telemetry integration for ExRatatui.

  ExRatatui emits `:telemetry` events so applications can plug in logging,
  metrics, and distributed tracing without forking the runtime. The API
  follows the conventions: every long-running operation is wrapped in a span,
  every one-off operation is a single execute, and every event carries a stable
  metadata shape you can match on.

  ## Events

  All events are prefixed with `:ex_ratatui`.

  ### Span events (`:start` / `:stop` / `:exception`)

  Each span emits three events with the suffix appended to the event
  name. Handlers typically attach to `:stop` for timing and
  `:exception` for failure tracking.

  | Event | Description | Metadata |
  | ----- | ----------- | -------- |
  | `[:ex_ratatui, :runtime, :init]` | App mount callback (`mount/1`). | `:mod`, `:transport` |
  | `[:ex_ratatui, :runtime, :event]` | Terminal event decode + user `handle_event/2` dispatch. | `:mod`, `:transport`, `:event` |
  | `[:ex_ratatui, :runtime, :update]` | Info-message dispatch (subscriptions, async results, user `handle_info/2`). | `:mod`, `:transport`, `:msg` |
  | `[:ex_ratatui, :render, :frame]` | Frame build + draw cycle. | `:mod`, `:transport`, `:widget_count` |
  | `[:ex_ratatui, :transport, :connect]` | Transport wiring for a session (terminal init, SSH session bind, distributed client monitor). | `:mod`, `:transport` |
  | `[:ex_ratatui, :image, :decode]` | `ExRatatui.Image.new/2` byte decode (PNG / JPEG / GIF / WebP / BMP). | `:format`, `:bytes`; on `:stop` adds `:width` / `:height`, or `:error` on decode failure |
  | `[:ex_ratatui, :code_block, :highlight]` | `ExRatatui.CodeBlock.highlight/3` syntect tokenisation. | `:language`, `:theme`, `:bytes`; on `:stop` adds `:line_count` |

  The two library-level spans fire from pure functions outside the
  server, so they carry no `:mod` / `:transport` and are not included
  in the default logger's event list.

  `:start` events carry `%{monotonic_time: integer, system_time: integer}`
  as measurements. `:stop` events add `:duration` (native units). On
  exception the metadata gains `:kind`, `:reason`, and `:stacktrace`.

  ### Single events

  | Event | Description | Measurements | Metadata |
  | ----- | ----------- | ------------ | -------- |
  | `[:ex_ratatui, :session, :lifecycle, :open]` | A session-backed runtime adopted a session. | `%{system_time: integer}` | `:mod`, `:transport`, `:width`, `:height` |
  | `[:ex_ratatui, :session, :lifecycle, :close]` | A session-backed runtime released its session. Fires exactly once per session even when transport-level cleanup also closes the session ref. | `%{system_time: integer}` | `:mod`, `:transport`, `:reason` |
  | `[:ex_ratatui, :render, :dropped]` | A frame was skipped (draw error or future backpressure). | `%{system_time: integer}` | `:mod`, `:transport`, `:reason` |
  | `[:ex_ratatui, :transport, :disconnect]` | Session tore down. | `%{system_time: integer}` | `:mod`, `:transport`, `:reason` |

  ## Attaching a default logger

      # in your Application.start/2 or iex
      ExRatatui.Telemetry.attach_default_logger()

  That attaches a handler that logs every `:stop` and single event at
  `:debug` level. Pass a custom level with `attach_default_logger(level: :info)`.

  See `guides/internals/telemetry.md` for a full wiring example with Telemetry.Metrics or OpenTelemetry.
  """

  require Logger

  @doc """
  Wraps `fun` in a `:telemetry` span rooted at `[:ex_ratatui | event]`.

  The `fun`'s return value is returned unchanged. The given `meta` is
  forwarded to both the `:start` and `:stop` events (plus the standard
  `:telemetry_span_context`). If you need extra metadata on `:stop`
  specifically, call `:telemetry.span/3` directly.
  """
  @spec span([atom(), ...], map(), (-> term())) :: term()
  def span(event, meta, fun) when is_list(event) and is_map(meta) and is_function(fun, 0) do
    :telemetry.span([:ex_ratatui | event], meta, fn -> {fun.(), meta} end)
  end

  @doc """
  Emits a single `:telemetry` event rooted at `[:ex_ratatui | event]`.

  `:system_time` is added to the measurements automatically if not already
  present.
  """
  @spec execute([atom(), ...], map(), map()) :: :ok
  def execute(event, measurements, meta)
      when is_list(event) and is_map(measurements) and is_map(meta) do
    measurements = Map.put_new_lazy(measurements, :system_time, &System.system_time/0)
    :telemetry.execute([:ex_ratatui | event], measurements, meta)
  end

  @doc """
  Attaches a logger that prints every ExRatatui telemetry event.

  Useful during development. Detach with `detach_default_logger/0`.

  ## Options

    * `:level` — log level (default: `:debug`).
    * `:events` — list of event suffixes to attach (default: all).
  """
  @spec attach_default_logger(keyword()) :: :ok | {:error, :already_exists}
  def attach_default_logger(opts \\ []) do
    level = Keyword.get(opts, :level, :debug)
    events = Keyword.get(opts, :events, default_logger_events())

    :telemetry.attach_many(
      handler_id(),
      events,
      &__MODULE__.__default_logger_handler__/4,
      %{level: level}
    )
  end

  @doc """
  Detaches the default logger previously attached with `attach_default_logger/1`.
  """
  @spec detach_default_logger() :: :ok | {:error, :not_found}
  def detach_default_logger do
    :telemetry.detach(handler_id())
  end

  @doc false
  def __default_logger_handler__(event, measurements, metadata, %{level: level}) do
    Logger.log(level, fn ->
      [
        "[ex_ratatui] ",
        Enum.map_join(event, ".", &to_string/1),
        " ",
        inspect(Map.merge(measurements, metadata), limit: :infinity, printable_limit: :infinity)
      ]
    end)
  end

  defp handler_id, do: "ex-ratatui-default-logger"

  defp default_logger_events do
    [
      [:ex_ratatui, :runtime, :init, :stop],
      [:ex_ratatui, :runtime, :init, :exception],
      [:ex_ratatui, :runtime, :event, :stop],
      [:ex_ratatui, :runtime, :event, :exception],
      [:ex_ratatui, :runtime, :update, :stop],
      [:ex_ratatui, :runtime, :update, :exception],
      [:ex_ratatui, :render, :frame, :stop],
      [:ex_ratatui, :render, :frame, :exception],
      [:ex_ratatui, :render, :dropped],
      [:ex_ratatui, :transport, :connect, :stop],
      [:ex_ratatui, :transport, :connect, :exception],
      [:ex_ratatui, :transport, :disconnect],
      [:ex_ratatui, :session, :lifecycle, :open],
      [:ex_ratatui, :session, :lifecycle, :close]
    ]
  end
end
