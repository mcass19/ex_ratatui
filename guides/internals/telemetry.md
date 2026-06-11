# Telemetry

ExRatatui emits events for every runtime transition, render cycle, transport handshake, and session lifecycle change. Attach handlers — for logging, metrics, or OpenTelemetry tracing — and get observability without forking the runtime or wrapping custom timers around `mount/1`.

## What gets emitted

Two categories, all prefixed with `:ex_ratatui`. **Span events** wrap something with a duration — `mount/1`, a render, a `handle_event/2` call. Each span fires three telemetry events: `:start` when it begins, `:stop` when it ends (measurements include `:duration`), `:exception` if it raises. **Single events** mark a point in time — a dropped frame, a disconnect — and fire once with no paired stop.

The full catalog — every event with its measurements and metadata — lives in `ExRatatui.Telemetry`'s moduledoc. The shape of it: five runtime/render/transport spans, two library-level spans (`:image, :decode` and `:code_block, :highlight`), and four single events for session lifecycle, dropped frames, and disconnects.

Every runtime / render / transport / session event carries `:mod` and `:transport` in its metadata, so the same handler can tag frames by app module or filter by transport without fishing for the data elsewhere. The two library-level spans — `[:ex_ratatui, :image, :decode]` and `[:ex_ratatui, :code_block, :highlight]` — fire from pure functions outside the server, so they carry only their own decode / highlight metadata; correlate them with a render frame via the `telemetry_span_context` reference if that join is needed.

The split between `:runtime, :event` and `:runtime, :update` isn't arbitrary. Terminal input goes through `:event`; everything else — subscriptions firing, async command results, plain `send/2` into the server — goes through `:update`. When asking "is my app slow because of keyboard handling or because my tick interval is doing too much?", that's the first place to look. `:render, :frame`'s `:stop` event also adds `:widget_count` to its metadata, which makes a `Telemetry.Metrics` summary like "p99 frame build by widget count" a one-liner.

## Log every event

ExRatatui ships a default logger that attaches one handler for every runtime, render, transport, and session event (the `:image, :decode` and `:code_block, :highlight` library spans are not included):

```elixir
# typically in Application.start/2 or an iex session
ExRatatui.Telemetry.attach_default_logger()
```

Every `:stop` and every single event now logs at `:debug`. Pass `level: :info` (or any `Logger` level) to bump the verbosity, or `events:` to restrict which events log:

```elixir
ExRatatui.Telemetry.attach_default_logger(
  level: :info,
  events: [[:ex_ratatui, :render, :frame, :stop], [:ex_ratatui, :render, :dropped]]
)
```

`detach_default_logger/0` reverses it.

## Telemetry.Metrics

[`telemetry_metrics`](https://hexdocs.pm/telemetry_metrics) converts `:telemetry` events into summaries, counters, and distributions. Wire the output into a reporter for dashboards in minutes.

An example:

```elixir
def metrics do
  [
    # Render timing — the one metric actually worth graphing.
    Telemetry.Metrics.summary("ex_ratatui.render.frame.stop.duration",
      unit: {:native, :millisecond},
      tags: [:mod, :transport]
    ),

    # Frame-build cost by scene size — spot "my dashboard grew 3x and now drops frames".
    # :widget_count lives in metadata, not measurements, so point the metric at it.
    Telemetry.Metrics.distribution("ex_ratatui.render.frame.stop.widget_count",
      measurement: fn _measurements, metadata -> metadata.widget_count end,
      tags: [:mod]
    ),

    # Dropped frames — should be near zero. Page on it. The trailing .count
    # makes Telemetry.Metrics count occurrences of the 3-segment event.
    Telemetry.Metrics.counter("ex_ratatui.render.dropped.count",
      tags: [:transport, :reason]
    ),

    # Handler latency — if a :runtime.event.stop summary grows, the
    # handle_event/2 is doing too much.
    Telemetry.Metrics.summary("ex_ratatui.runtime.event.stop.duration",
      unit: {:native, :millisecond},
      tags: [:mod]
    ),

    # Session churn — SSH clients connecting/disconnecting.
    Telemetry.Metrics.counter("ex_ratatui.transport.disconnect.count",
      tags: [:transport, :reason]
    )
  ]
end
```

## OpenTelemetry

[`opentelemetry_telemetry`](https://hexdocs.pm/opentelemetry_telemetry) gives the primitives to turn each `:telemetry` span into an OTel span: `start_telemetry_span/4` when the `:start` event fires, `end_telemetry_span/2` when `:stop` fires. The `telemetry_span_context` reference that `:telemetry.span/3` puts on every event is what lets the pair find each other across handler invocations, so there's no state to thread manually.

Attach one handler covering the suffixes of every span of interest. Configure the exporter (Jaeger, Honeycomb, Tempo) via `:opentelemetry_exporter`, and every ExRatatui span now lands in the trace UI.

The payoff is end-to-end traces: an SSH TUI that calls into a Phoenix backend shows the render span next to the HTTP span next to the DB span, all in one timeline.

## Related

- [Debugging](debugging.md) — `Runtime.enable_trace/2` gives an in-memory event log scoped to one server; telemetry gives the system-wide view. Both have their place.
- [Performance](performance.md) — once metrics surface a slow render, this guide covers what to do about it.
- [Custom Transports](../transports/custom_transports.md) / [Rendering to Non-Terminal Surfaces](../transports/cell_session.md) — transports built on top of these primitives are where a custom per-frame telemetry boundary would attach.
- **`ExRatatui.Telemetry`** — module docs with the helper API.
- [`telemetry`](https://hexdocs.pm/telemetry) / [`telemetry_metrics`](https://hexdocs.pm/telemetry_metrics) / [`opentelemetry_telemetry`](https://hexdocs.pm/opentelemetry_telemetry) — upstream docs.
