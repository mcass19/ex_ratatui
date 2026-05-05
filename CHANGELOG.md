# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`ExRatatui.CellSession` — non-terminal rendering primitive** — sibling of `ExRatatui.Session` for consumers that aren't terminals (Phoenix LiveView painting `<span>` cells, embedded framebuffers, screenshot tools, headless tests). Backed by ratatui's `TestBackend`, it exposes the cell buffer directly instead of ANSI bytes. Same widget tree, input parser, and `draw/2` / `resize/3` / `feed_input/2` / `close/1` lifecycle as `Session`; the only API divergence is `take_output/1` being replaced by `take_cells/1` (full snapshot) and `take_cells_diff/1` (cells that changed since the last diff call). Cells are `%{row, col, symbol, fg, bg, modifiers, skip}` in row-major order, with colors and modifiers using the same `ExRatatui.Style` vocabulary as the rest of the library. `take_cells_diff/1` returns a full payload on its first call, after `resize/3`, and after reconstruction; otherwise only cells that differ structurally. Adds 9 NIFs, the `ExRatatui.CellSession{,.Cell,.Snapshot,.Diff}` modules, a [Rendering to Non-Terminal Surfaces guide](guides/cell_session.md), and a headless [`cell_dump.exs`](examples/cell_dump.exs) example.

- **`{:cell_session, cell_session, cell_writer_fn}` Server transport tag** — ExRatatui.Server now accepts a fourth `:transport` shape (alongside `:local`, `:session`, and `:distributed_server`) that drives an `ExRatatui.App` against a `CellSession` instead of a byte-stream `Session`. On every render the Server calls `CellSession.draw/2`, then `CellSession.take_cells_diff/1`, then hands the resulting `%CellSession.Diff{}` to the user-supplied `cell_writer_fn` — same call shape as the byte-stream `:session` transport, just a different payload type. `ExRatatui.Transport.start_server/1` accepts the new shape unchanged via the `t:server_transport/0` union; the `t:cell_writer_fn/0` type lives next to the existing `t:writer_fn/0`. Mount opts are augmented identically to the byte-stream path: `opts[:transport] = :cell_session`, `opts[:width]` / `opts[:height]` populated from `CellSession.size/1`. Telemetry mirrors the existing taxonomy: `[:ex_ratatui, :transport, :connect]` and `[:ex_ratatui, :session, :lifecycle, :open]` fire on init with `transport: :cell_session`; `[:ex_ratatui, :session, :lifecycle, :close]` and `[:ex_ratatui, :transport, :disconnect]` fire on `terminate/2`. Resize semantics match `:session` exactly — the transport must call `CellSession.resize/3` before forwarding `{:ex_ratatui_resize, w, h}` to the Server, then the Server updates the cached size and dispatches a `%Event.Resize{}` to the App; the next render's diff payload after a resize is always full (prior baseline at the old area is no longer comparable).

## [0.8.2] - 2026-04-29

### Fixed

- **`%Event.Resize{}` now reaches `handle_event/2` over byte-stream transports** — when the runtime ran over a byte-stream transport (`:session` for SSH / Kino / custom TCP, `:distributed_server` for distribution), the `{:ex_ratatui_resize, w, h}` message synthesized by `ExRatatui.Transport.ByteStream` was intercepted by the Server's own `handle_info/2` clause: it updated the cached `width` / `height` and re-rendered, but never dispatched a `%Event.Resize{}` to the App. The local-tty path delivered Resize through the polling event loop, so an App that worked when run over the real terminal would silently miss resize events the moment it was supervised over SSH, distribution, or a Livebook notebook. The Server now updates its cached size first (so the follow-up render sees the new dims) and then routes the resize through `dispatch_event/2`, giving the App's `handle_event/2` exactly the same `%Event.Resize{width: w, height: h}` it would see on local tty. Apps that only had a fall-through `handle_event(_, state)` clause are unaffected; apps that explicitly track terminal size in their own state can now do so over every transport. The two transport tests (`session_transport_test.exs`, `distributed_transport_test.exs`) were updated to assert App delivery in addition to the re-render

## [0.8.1] - 2026-04-27

### Added

- **Telemetry instrumentation** ([#56](https://github.com/mcass19/ex_ratatui/issues/56)) — new `ExRatatui.Telemetry` module emits `:telemetry` events across the runtime so apps can plug in logging, metrics, or OpenTelemetry tracing without forking the server. Five span events (`:start` / `:stop` / `:exception`) wrap the costly stages: `[:ex_ratatui, :runtime, :init]` around `mount/1`, `[:ex_ratatui, :runtime, :event]` around terminal-input `handle_event/2`, `[:ex_ratatui, :runtime, :update]` around info-message `handle_info/2` (subscriptions, async results, user messages), `[:ex_ratatui, :render, :frame]` around the build+draw cycle (adds `:widget_count` to stop metadata), and `[:ex_ratatui, :transport, :connect]` around local/SSH/distributed handshakes. Four single events fire for point-in-time facts: `[:ex_ratatui, :session, :lifecycle, :open]` when a session-backed runtime adopts a session (carries `:width` / `:height`), `[:ex_ratatui, :session, :lifecycle, :close]` when it releases the session (carries `:reason`; fires exactly once per session even when the transport's own teardown defensively closes the same ref afterwards), `[:ex_ratatui, :render, :dropped]` on draw errors (with a TODO placeholder for future frame-skip backpressure), and `[:ex_ratatui, :transport, :disconnect]` on server teardown. Every event carries `:mod` and `:transport` in its metadata. `ExRatatui.Telemetry.span/3` is a thin helper that prefixes events with `:ex_ratatui` and forwards start metadata to stop; `execute/3` does the same for single events and auto-adds `:system_time`. `attach_default_logger/1` / `detach_default_logger/0` ship a handler that logs every event at a configurable level. New [Telemetry guide](guides/telemetry.md) walks through the full event catalogue, a `Telemetry.Metrics` example, and an `opentelemetry_telemetry` wiring snippet. Added `{:telemetry, "~> 1.0"}` as an explicit dependency and to `extra_applications` so the handler registry is available on every node (including peers in distributed tests)
- **Transport behaviour** — new `ExRatatui.Transport` module documents the protocol between the runtime server and the processes that carry I/O for a running `ExRatatui.App`. Declares the `server_transport`, `writer_fn`, and `to_server` typespecs, plus one optional `child_spec/1` callback and a public `start_server/1` entrypoint for custom transports to boot the runtime without depending on internal modules. `ExRatatui.SSH`, `ExRatatui.SSH.Daemon`, and `ExRatatui.Distributed.Listener` all adopt the behaviour. New `ExRatatui.Transport.ByteStream` helper packages the byte-pump pattern (`forward_input/3`, `forward_resize/4`) so any byte-oriented transport — SSH today, Kino/Livebook next, a custom TCP bridge — can plug in without reimplementing event dispatch or Resize absorption. `ExRatatui.SSH` now delegates to `ByteStream` instead of hand-rolling the loop. New [Custom Transports guide](guides/custom_transports.md) walks through the contract and a working TCP example covering separation of acceptor and per-connection worker (so the listener survives across disconnects and serves concurrent clients), the alt-screen enter/leave sequences, runtime-server monitoring, and the raw-mode client requirement (`stty raw -echo; nc …; stty sane`) that plain TCP needs since it has no equivalent of SSH's PTY negotiation
- **Property-based test pass over the recently-added surface** — five new files under `test/ex_ratatui/property/` covering the modules introduced by the telemetry + transport-behaviour work, plus older surface that previously lacked sweeping coverage. `session_input_property_test.exs` proves `ExRatatui.Session.feed_input/2`'s **byte stitchability** (splitting any byte stream at any boundary, including byte-by-byte, yields the same event sequence) along with shape invariants for printable bytes, bare ESC, and arrow keys. `byte_stream_property_test.exs` covers `ExRatatui.Transport.ByteStream.forward_input/3`'s contract: no `%Event.Resize{}` ever leaks as a regular event, every parsed event is delivered in order, and `forward_resize/4` always emits an `:ex_ratatui_resize` notification. `bridge_property_test.exs` covers `Bridge.encode_commands!/1`'s list-level contract — length / order preservation, `{map, map}` shape, rect coordinate passthrough, and `ArgumentError` on malformed entries — across structurally simple widgets (Paragraph, Block, Clear, Gauge, Throbber). `text_encode_property_test.exs` covers `Text.Encode.to_wire_text!/to_wire_line!` line/span count and content preservation, alignment serialization, and per-line agreement between the two encoders. `normalize_property_test.exs` covers `Subscription.normalize/1` and `Command.normalize/1` idempotence, leaf-count preservation across nested batches, order preservation, and refusal of garbage shapes. The exhaustive per-widget validation property suite (one shape generator per widget × known-malformed shapes raising `ArgumentError`, ~22 widgets) is intentionally deferred — the structural invariants above are uniform across widgets, so the next pass is a per-widget effort rather than a generic one

### Changed

- **Internal `:ssh` transport tag renamed to `:session`** — the Server's internal transport tag always described "generic byte-stream session"; SSH just happened to be the first user. The new name makes room for other byte-stream transports (Kino, custom TCP) to share the same runtime without impersonating SSH. User-facing routing shorthand is untouched: `{MyApp, transport: :ssh}` still routes to `SSH.Daemon`. Affected surfaces: `Runtime.snapshot/1` `.transport` now returns `:session` for byte-stream sessions (was `:ssh`); telemetry metadata `%{transport: _}` on `[:runtime, :init]`, `[:transport, :connect]`, etc. is now `:session` on byte-stream events; `mount(opts)[:transport]` is now `:session` for SSH apps (was `:ssh`). If your app branches on `opts[:transport]` to detect SSH specifically, switch to a different signal (you control the `{MyApp, transport: :ssh}` line in your own supervision tree)


## [0.8.0] - 2026-04-21

### Added

- **Chart widget** — new `ExRatatui.Widgets.Chart` struct plus `Chart.Dataset` and `Chart.Axis` companions wrap ratatui's `Chart` for x/y line, scatter, and bar plots with axes, labels, legend, and multi-series support. Each `%Dataset{}` carries a `:name` (shown in the legend), a list of `{x, y}` numeric tuples in `:data`, plus its own `:marker` (`:braille` / `:dot` / `:block` / `:bar` / `:half_block`), `:graph_type` (`:line` / `:scatter` / `:bar`), and `:style`, so a single chart can mix line and scatter overlays. The required `:x_axis` / `:y_axis` are `%Axis{}` structs with `:bounds` (`{min, max}` numeric tuple), optional tick `:labels` (string / `%Span{}` / `%Line{}`), `:title`, `:style`, and `:labels_alignment` (`:left` / `:center` / `:right`). `:legend_position` accepts `:top`, `:top_left`, `:top_right` (default), `:bottom`, `:bottom_left`, `:bottom_right`, `:left`, `:right`, or `nil` to hide the legend entirely. `:hidden_legend_constraints` takes a `{width_constraint, height_constraint}` pair using the same shapes as `ExRatatui.Layout` (`:length` / `:percentage` / `:ratio` / `:min` / `:max` / `:fill`) — the legend is hidden whenever its rendered size would exceed those bounds against the chart area. `:block` wraps the chart in a framed `Block`. Missing axes, non-list `:datasets`, non-`%Dataset{}` entries, malformed data points, non-numeric coordinates, unknown markers, unknown `:graph_type`s, unknown `:legend_position`s, malformed `:bounds`, malformed `:hidden_legend_constraints`, and unknown `:labels_alignment` values raise `ArgumentError` at the bridge boundary. See the [Chart section](guides/building_uis.md#chart) in Building UIs and the widget cheatsheet for examples
- **Canvas widget** ([#30](https://github.com/mcass19/ex_ratatui/issues/30)) — new `ExRatatui.Widgets.Canvas` struct and six shape structs (`Canvas.Line`, `Canvas.Rectangle`, `Canvas.Circle`, `Canvas.Points`, `Canvas.Map`, `Canvas.Label`) wrap ratatui's `Canvas` for 2D plotting. Shapes live in a virtual coordinate space defined by `:x_bounds` / `:y_bounds` (both `{min, max}` tuples with `min <= max`) and are rasterized onto cells via `:marker` — `:braille` (default), `:dot`, `:block`, `:bar`, or `:half_block`. `Rectangle` draws an outline anchored at its bottom-left corner, `Circle` draws an outline centered on `{x, y}`, `Points` plots a list of `{x, y}` tuples, `Map` paints the world's coastlines at `:low` or `:high` resolution (pair with `{-180, 180}` × `{-90, 90}` bounds), and `Label` writes a styled text annotation at the given canvas-space coordinate. Every drawable shape takes a plain `Color.t()` rather than a `Style` — canvas pixels sample individual cells, so text modifiers don't apply; `Label` uses the color as the text foreground. `:background_color` fills the area, and `:block` wraps the canvas in a framed `Block`. Non-tuple bounds, inverted bounds, unknown markers, unknown map resolutions, missing required shape fields, negative `width` / `height` / `radius`, non-string `Label.text`, malformed `Points.coords` entries, and unknown shape structs all raise `ArgumentError` at the bridge boundary. See the [Canvas section](guides/building_uis.md#canvas) in Building UIs and the widget cheatsheet for examples
- **Calendar widget** ([#31](https://github.com/mcass19/ex_ratatui/issues/31)) — new `ExRatatui.Widgets.Calendar` struct renders ratatui's `Monthly` calendar. `:display_date` is a native `%Date{}` that drives which month is shown and which day is highlighted. `:events` accepts either a list of `{%Date{}, %Style{}}` tuples or a `%{Date => Style}` map — map entries with a `nil` value are skipped so toggling individual days stays ergonomic. `:show_month_header` and `:show_weekdays_header` (booleans, default `true`) toggle the two header rows, with independent `:header_style` / `:weekday_style` overrides. Set `:show_surrounding` to a `%Style{}` to bleed the previous/next month into empty grid cells; leave it `nil` to hide them. `:default_style` paints unstyled days, and `:block` wraps the widget in a framed `Block`. Non-`Date` `:display_date`, non-boolean header toggles, and malformed event entries raise `ArgumentError` at the bridge boundary. See the [Calendar section](guides/building_uis.md#calendar) in Building UIs and the widget cheatsheet for examples
- **Sparkline widget** ([#27](https://github.com/mcass19/ex_ratatui/issues/27)) — new `ExRatatui.Widgets.Sparkline` struct renders ratatui's `Sparkline`, a compact single-line bar chart for streaming or time-series data. `:data` is a list of non-negative integers with `nil` entries representing missing samples; set `:max` to a positive integer or leave `nil` to auto-scale. Choose a rendering style via `:bar_set` — `:nine_levels` for smooth gradients, `:three_levels` for low-density glyphs, or a non-empty list of strings that's proportionally mapped across ratatui's nine density slots. Direction (`:left_to_right` / `:right_to_left`), absent-value symbol and style, chart-wide `:style`, and `:block` are all configurable. Floats, negative values, non-list data, unknown bar-set atoms, and empty custom lists raise `ArgumentError` at the bridge boundary. See the [Sparkline section](guides/building_uis.md#sparkline) in Building UIs and the widget cheatsheet for examples
- **BarChart widget** ([#23](https://github.com/mcass19/ex_ratatui/issues/23)) — new `ExRatatui.Widgets.BarChart`, `ExRatatui.Widgets.Bar`, and `ExRatatui.Widgets.BarGroup` structs render ratatui's `BarChart` in either `:vertical` or `:horizontal` orientation. Each `%Bar{}` carries a `:label`, non-negative integer `:value`, optional per-bar `:style` that overrides the chart-wide `:bar_style`, and an optional `:text_value` to replace the numeric readout. Chart-level fields include `:data` (single anonymous group of bars), `:groups` (list of `%BarGroup{}` for side-by-side clusters with shared captions), `:bar_width`, `:bar_gap`, `:group_gap` (cells between adjacent clusters), `:bar_style`, `:value_style`, `:label_style`, `:max` (nil auto-scales to the largest value), `:direction`, and `:block`. Set either `:data` or `:groups`. Floats, negative values, non-list `:groups`, non-`%BarGroup{}` entries, non-string group labels, and negative `:group_gap` raise `ArgumentError` at the bridge boundary. See the [BarChart section](guides/building_uis.md#barchart) in Building UIs and the widget cheatsheet for examples
- **Focus management** ([#48](https://github.com/mcass19/ex_ratatui/issues/48)) — new `ExRatatui.Focus` struct for multi-panel apps. Declare an ordered ring of focusable IDs with `Focus.new/2`, route every key event through `Focus.handle_key/2`, and pattern-match on `Focus.current/1` to dispatch. Tab / Shift+Tab / `back_tab` are consumed by default; `:next_keys` / `:prev_keys` accept `%Event.Key{}` entries to override (`:kind` ignored, modifiers compared as a set). `Focus.focused?/2` drives border styling without `Focus` ever touching widget structs. Pure Elixir, no Rust changes. The new "Focus management" section in [Building UIs](guides/building_uis.md#focus-management) walks through the caller pattern
- **Widget protocol** ([#24](https://github.com/mcass19/ex_ratatui/issues/24)) — new `ExRatatui.Widget` protocol lets you build composite widgets in pure Elixir by implementing `render/2` on your own struct. The Bridge flattens custom widgets into primitive `{widget, rect}` tuples recursively (with a 32-level depth cap and argument validation) before encoding, so `ExRatatui.draw/2` accepts primitive and custom widgets interchangeably at the top level. Custom widgets inside `Popup.content` / `WidgetList.items` are not supported yet. The public `widget()` type splits into `primitive_widget()` (built-ins, unchanged) and `widget()` (primitive or any struct implementing the protocol); the new [Custom Widgets](guides/custom_widgets.md) guide walks through the API. Protocol consolidation is now limited to `:prod`, so test-time `defimpl` blocks (and your own tests of custom widgets) work without fuss
- **Rich text primitives** ([#26](https://github.com/mcass19/ex_ratatui/issues/26)) — new `ExRatatui.Text.Span` and `ExRatatui.Text.Line` structs let text-bearing widget fields carry per-span colors and modifiers instead of a single style for the entire string. `Paragraph.text`, `List.items`, `Table.rows`/`Table.header`, `Tabs.titles`, and `Block.title` now accept any mix of `String.t()`, `%Span{}`, `%Line{}`, or `[%Span{}]`. Plain strings continue to work on every field; fields that are semantically single-line (table cells, tab titles, block titles) raise on strings containing embedded newlines. The new "Rich Text" section in [Building UIs](guides/building_uis.md#rich-text) walks through the API

### Fixed

- **TextInput cursor invisible at end of double-width input** ([#45](https://github.com/mcass19/ex_ratatui/issues/45)) — when a `TextInput` contained CJK or other double-width characters that overflowed the widget's display width, moving the cursor to the end made it disappear. Viewport scrolling and span construction tracked positions in char counts but the widget's display width is measured in terminal cells, so wide chars consumed twice their accounted-for space and the trailing cursor span was truncated. Both the viewport adjustment and the rendered spans are now cell-aware via the `unicode-width` crate

### Changed

- **Documentation expanded.** Five new guides ship in `guides/`: [Getting Started](guides/getting_started.md) walks `mix new` → supervised todo app with `TextInput` + `List` + manual focus; [State Machine Patterns](guides/state_machines.md) covers mode-atom dispatch, screen stacks, modals via `Popup`, multi-screen transitions, and sibling-GenServer escape hatches; [Testing](guides/testing.md) documents the headless backend, `test_mode`, `Runtime.inject_event/2`, and three assertion patterns (snapshot, `test_pid`, `:sys.get_state`); [Debugging](guides/debugging.md) covers `Runtime.snapshot/1`, `enable_trace/2` events, buffer-inspection-as-dev-tool, common errors (`terminal_init_failed`, garbled output, SSH `-t`, `mix run` stdin), and Rust NIF rebuilds; [Performance](guides/performance.md) covers the render loop, `render?: false`, keeping `render/2` cheap, large trees, poll-interval tuning, subscription cost, async effects, and timing with `:timer.tc` + traces. The widgets cheatsheet was rewritten as task-grouped columns (Styles, Layout, Text, Lists, Progress, Input, Charts, Containers, Calendar) using `{: .col-2}` annotations for scan-ability. A new `examples/README.md` catalogs all 12 examples with SSH and Erlang-distribution one-liners. The top-level README dropped its Learning Path, Testing sample, and Troubleshooting sections (all absorbed by the new guides) and trimmed the Examples table to two (`hello_world` + `counter_app`), now pointing to the examples catalog. Hex sidebar reordered: onboarding → concepts → patterns → ops → cheatsheet
- **Test suite expanded.** New coverage: property-based invariants for `Layout.split/3`, style encoding, text coercion, `Focus` ring semantics, and `decode_event/1` round-tripping key/mouse/resize tuples via `stream_data`; unicode and emoji rendering across CJK, combining marks, ZWJ sequences, and BMP/SMP emoji on every text-bearing widget; stress tests for 2 000-widget scenes, 1 000 redraws, and 1×1 / 500×500 terminals; cross-transport parity tests proving the same `App` module produces identical widget trees under local, SSH, and Erlang distribution; raw-example smoke tests for `system_monitor` (App-based) and `chat_interface` (raw `ExRatatui.run/1` loop). Distributed integration now also exercises Chart, grouped BarChart, and Canvas with a `Map` shape to catch any future NIF-field regression across node boundaries. Coverage remains at 100% across all 55 modules
- **Test layout mirrors `lib/`.** `test/ex_ratatui/widgets_test.exs` was split into per-widget files under `test/ex_ratatui/widgets/`, one-for-one with `lib/ex_ratatui/widgets/`. Cross-cutting integration tests (cross-transport parity, unicode rendering, stress, focus integration, full-stack rendering) now live under `test/integration/`. `server_runtime_test.exs` was renamed to `runtime_test.exs` and `test_backend_test.exs` folded into `terminal_test.exs` to match the modules they cover. `server_test.exs` was further split by transport: SSH and distributed unit tests now live in `test/ex_ratatui/server/ssh_transport_test.exs` and `test/ex_ratatui/server/distributed_transport_test.exs`, each organized under `describe` blocks for lifecycle, message handling, reducer support, and helpers. Duplicated fixture apps across the three server test files were consolidated into `ExRatatui.Test.ServerApps` (`Echo`, `StopOnAnyEvent`, `FailingMount`) under `test/support/`, and SSH test helpers into `ExRatatui.Test.SshHelper`
- **CI hardening.** The `distributed` and `slow` jobs merged into a single `extras` job that runs both tag filters sequentially, saving a runner. The lint matrix now runs `mix xref graph --format cycles --fail-above 0` to catch dependency cycles at CI time. Doctests added to `ExRatatui.Command` and `ExRatatui.Subscription` for the reducer side-effect helpers
- **API polish.** `ExRatatui` moduledoc now documents the error-handling convention: programmer errors raise `ArgumentError`, runtime/I/O failures return `{:error, reason}`. `ExRatatui.Command.async/2` docs now enumerate the mapper's error shapes and include an example. `TextInput` and `Textarea` moduledocs note their `:state` references are node-local NIF resources that must not be serialized, compared, or sent across distribution. The `Bridge` module is hidden from HexDocs (`@moduledoc false`) since it's internal to the NIF boundary
- **Shutdown robustness.** The internal server's `terminate/2` now cancels any armed subscription timers across all three transports, so pending ticks can't be delivered to a supervisor-restarted process carrying a stale mailbox

## [0.7.1] - 2026-04-13

### Fixed

- **SSH bare Esc key not detected** — VTE's state machine swallows `0x1B` as the start of an escape sequence, so a bare Esc press over SSH produced no event. The SSH transport now schedules a 50 ms timeout after a lone `0x1B` with no follow-up bytes; if the timer fires it resets the parser and dispatches a synthetic `%Event.Key{code: "esc"}` press. Follow-up bytes (the normal case for multi-byte sequences like arrow keys) cancel the timer before it fires. Added `Session.reset_parser/1` and its backing `session_reset_parser` NIF
- **Distributed transport crashes on stateful widgets** — `TextInput` and `Textarea` store their mutable state in NIF resource references that cannot cross BEAM node boundaries via Erlang distribution. The distributed server now snapshots stateful widget state into plain tuples before sending, and the Rust decoder reconstructs temporary resources from the snapshot on the client node. Stateless widgets are unaffected. Added `text_input_snapshot` and `textarea_snapshot` NIFs

## [0.7.0] - 2026-04-13

### Added

- **Reducer runtime** for `ExRatatui.App` via `use ExRatatui.App, runtime: :reducer`. Reducer apps implement `init/1`, `render/2`, and `update/2`, receive terminal input as `{:event, event}`, mailbox messages as `{:info, msg}`, and can declare subscriptions with `subscriptions/1`
- `ExRatatui.Command` — reducer side-effect helpers for immediate messages, delayed messages, async work, and batched command execution
- `ExRatatui.Subscription` — reducer timer/subscription helpers for interval and one-shot self-messages reconciled by stable `id`
- `ExRatatui.Runtime` — runtime inspection helpers exposing snapshots, trace events, and trace enable/disable controls for supervised TUI processes
- `ExRatatui.Runtime.inject_event/2` — deterministic synthetic event injection for supervised apps under `test_mode`
- Example: `examples/reducer_counter_app.exs` — simple reducer-driven counter showing `update/2` and `subscriptions/1`

### Changed

- `ExRatatui.App` now supports two runtime styles: the existing callback runtime and the new reducer runtime selected with `runtime: :reducer`
- The internal server now supports reducer runtime options for commands, render suppression, trace state, runtime snapshots, async command tracking, and subscription reconciliation
- Render-command encoding moved into a shared internal bridge, making `ExRatatui.draw/2` and `ExRatatui.Session.draw/2` share one validation and encoding path
- Native render-command decoding was refactored into reusable helpers in `native/ex_ratatui/src/decode.rs` and shared between local terminal rendering and session rendering
- Bumped `ratatui-textarea` Rust dependency from 0.8 to 0.9
- `credo` dependency restricted to `:dev` environment only

### Fixed

- New subscriptions now store their timer reference correctly instead of keeping the `{timer_ref, token}` tuple in the `timer_ref` field, which broke timer cancellation/rearming paths in the reducer runtime
- Async command mappers are now wrapped the same way as async functions, so mapper exceptions/exits return structured error tuples and `active_async_commands` bookkeeping is always decremented
- The `mount/1` callback contract now includes the supported `{:ok, state, callback_opts}` form, which keeps reducer-style startup shims aligned with Dialyzer and the runtime's actual behavior
- Invalid reducer/runtime payloads and malformed render commands now fail earlier with clearer Elixir-side or Rust-side validation errors
- **Parallel cold compile crash** — the NIF bridge no longer loads its NIF via `@on_load` during dependency compilation. Precompiled/source artifacts are still prepared at compile time, but the NIF now loads lazily on first use, which stops isolated compiler VMs from crashing under parallel cold compiles on this host
- **`test_mode` input flake** — local supervised apps and distributed attach clients no longer poll the real terminal while running headless tests, which removes ambient crossterm events from async test runs and stops spurious renders like the `render?: false` reducer flake
- **SSH `auto_host_key` bootstrap** — host-key generation now recreates the parent `<priv_dir>/ssh/` directory immediately before writing the key, so first boot succeeds even if the app's priv tree was absent or cleaned between runs

### Docs

- Extracted runtime and widget content from README into dedicated guides: `guides/callback_runtime.md`, `guides/reducer_runtime.md`, and `guides/building_uis.md`
- Added widget cheatsheet: `guides/cheatsheets/widgets.cheatmd`
- README now documents the reducer runtime, reducer example app, command/subscription helpers, and runtime inspection API
- README and `ExRatatui.App` docs now call out that `mount/1` may return runtime opts and that `WidgetList.scroll_offset` is row-based with partial clipping semantics
- Expanded public moduledocs for `ExRatatui.App`, `ExRatatui.Command`, `ExRatatui.Subscription`, and `ExRatatui.Runtime`
- HexDocs module grouping now includes reducer-runtime modules
- README now notes that the native library loads lazily on first use

### Tests

- Added reducer runtime coverage for commands, subscriptions, tracing, render suppression, async failure handling, and invalid runtime return values
- Added coverage for public `Command`, `Subscription`, `Runtime`, `App`, and shared bridge validation paths
- Elixir test coverage remains at 100%

## [0.6.2] - 2026-04-12

### Added

- **Distribution-attach transport** — serve any `ExRatatui.App` to remote BEAM nodes over Erlang distribution. New `transport: :distributed` option on `ExRatatui.App` and a standalone `ExRatatui.Distributed.Listener` for direct supervision-tree use. Each attaching node gets its own isolated TUI session; widget lists travel as plain BEAM terms with zero NIF on the app node
- `ExRatatui.Distributed` — main API module with `attach/3` for connecting to a remote TUI
- `ExRatatui.Distributed.Listener` — supervisor wrapping a `DynamicSupervisor` for per-attach sessions, with config stored in `:persistent_term`
- Distributed.Client (internal) — local rendering proxy that takes over the terminal, polls events, and forwards them to the remote server
- Server (internal) learns a `transport: {:distributed_server, client_pid, width, height}` init path that sends `{:ex_ratatui_draw, widgets}` over distribution instead of rendering locally
- Guide: `guides/distributed_transport.md` — architecture, quick start, options reference, testing, troubleshooting
- README "Running over Erlang Distribution" section
- `examples/system_monitor.exs` now supports `--distributed` flag for running over Erlang distribution
- `:peer`-based integration tests for the full cross-node roundtrip (tagged `:distributed`, run with `elixir --sname test -S mix test --only distributed`)

### Changed

- `test_mode` now means fully headless local runtime behaviour: it disables live terminal input polling on both the server and `Distributed.Client`, and runtime snapshots expose whether polling is enabled
- Server event and resize handlers are now shared between `:ssh` and `:distributed_server` transports
- `ExRatatui.App` `dispatch_start/1` routes `:distributed` to `ExRatatui.Distributed.Listener.start_link/1`
- **`WidgetList` `scroll_offset` is now row-based** — previously `scroll_offset` skipped whole items by index; it now skips rows of content. To scroll to a specific item, sum the heights of all preceding items. Items partially above the viewport are clipped at the row level, enabling smooth pixel-row scrolling for chat histories and similar variable-height lists. This is a **breaking change** for callers that relied on the item-index interpretation

  **Migration:** If you set `scroll_offset` to an item index (e.g., `scroll_offset: selected`), replace it with the cumulative row height of preceding items. For example, if all items have height 3: `scroll_offset: selected * 3`. For variable-height items, sum their heights: `scroll_offset: items |> Enum.take(selected) |> Enum.map(&elem(&1, 1)) |> Enum.sum()`

### Fixed

- **`WidgetList` partial-item clipping** — items straddling the top edge of the viewport are now correctly rendered via an off-screen buffer blit instead of being skipped entirely

## [0.6.1] - 2026-04-09

### Fixed

- **SSH subsystem dispatch** — `ssh host -s Elixir.MyApp.TUI` (and `ExRatatui.SSH.subsystem/1` under `nerves_ssh`) would hang forever instead of rendering. The channel handler was waiting for a `{:ssh_cm, _, {:subsystem, ...}}` message inside `handle_ssh_msg/2`, but OTP `:ssh` consumes that request internally when it matches a name in the daemon's `:subsystems` config — the handler only ever receives `{:ssh_channel_up, ...}`. `ExRatatui.SSH` now detects subsystem-mode dispatch (via a new `subsystem: true` flag baked into the init args by `subsystem/1` and `ExRatatui.SSH.Daemon`) and synthesizes a default 80x24 session + starts the TUI server directly from `{:ssh_channel_up, ...}`. Shell-mode startup (via `ssh_cli`) is unchanged — it still waits for `pty_req` + `shell_req` as before
- **SSH subsystem + `-t` pty_req races** — when a client connects with `ssh -t -s Elixir.MyApp.TUI`, OTP fires `ssh_channel_up` first (we start an 80x24 session + server) and then delivers the client's `pty_req` with the real dimensions. The previous `pty_req` handler created a brand-new `Session` on every call, which left the SSH channel pointing at a session the running Server no longer rendered into. The handler now splits on `session: nil` vs `session: %Session{}` and resizes the existing session in place when one is already there, mirroring the `window_change` path
- **SSH subsystem pty-size discovery on nerves_ssh** — even with the pty_req race fixed, a subsystem TUI riding on `nerves_ssh` (or any `:ssh.daemon` that configures a default CLI handler) would stay stuck at the hardcoded 80x24 fallback instead of filling the client's real terminal. Root cause: OTP's `ssh_connection:handle_cli_msg/3` hands pty_req to the daemon's default CLI handler when the channel's user pid is still `undefined`, and then silently orphans that CLI handler the moment the subsequent subsystem request rebinds the pid to us — so the subsystem handler *never* sees pty_req on those deployments, no matter how early it arrives. `ExRatatui.SSH` now sidesteps the whole OTP path by emitting a Cursor Position Report roundtrip (`ESC[s ESC[9999;9999H ESC[6n ESC[u`) on `{:ssh_channel_up, ...}`: the client clamps the bogus cursor position to its real pty size, responds with `ESC[<row>;<col>R`, the session's ANSI input parser decodes that as a `%ExRatatui.Event.Resize{}`, and the `{:data, ...}` handler resizes the session in place + notifies the running server via `{:ex_ratatui_resize, w, h}`. Shell-mode startup is unaffected — it still reads the dimensions straight off `pty_req`
- **`session_input.rs` CPR parsing** — the VTE-driven input parser now recognizes `ESC[<row>;<col>R` Cursor Position Report responses and emits them as `NifEvent::Resize(col, row)` so the SSH transport's CPR-based pty-size discovery has something to intercept. The handler runs before the simple-CSI dispatch that would otherwise silently drop any `R` final byte
- **SSH subsystem startup** — added a shell-vs-subsystem section to `ExRatatui.SSH`'s moduledoc and the `guides/ssh_transport.md` guide explaining which message triggers server boot in each mode, plus a loud "always pass `-t`" caveat (OpenSSH doesn't allocate a PTY for subsystem invocations by default, which leaves the client's local terminal in cooked mode — keystrokes get line-buffered and echoed locally on top of the TUI)

## [0.6.0] - 2026-04-09

### Added

- **SSH transport** — serve any `ExRatatui.App` to remote clients over OTP `:ssh`. New `transport: :ssh` option on `ExRatatui.App` and a standalone `ExRatatui.SSH.Daemon` for direct supervision-tree use. Each connected client gets its own isolated TUI session; works as a primary daemon or as a `nerves_ssh` subsystem via `ExRatatui.SSH.subsystem/1`
- `ExRatatui.Session` — in-memory transport-agnostic terminal session (Rust `SharedWriter` + `Viewport::Fixed`) with `new/2`, `draw/2`, `take_output/1`, `feed_input/2`, `resize/3`, `size/1`, and `close/1`
- `ExRatatui.SSH` — `:ssh_server_channel` implementation that drives a Session per channel, parses ANSI input via `vte`, and handles PTY negotiation, `window_change`, and alt-screen lifecycle
- `ExRatatui.SSH.Daemon` — GenServer wrapping `:ssh.daemon/2` with `port/1` and `daemon_ref/1` introspection helpers
- `ExRatatui.SSH.Daemon` `:auto_host_key` option — when set, the daemon resolves the OTP application that owns `:mod`, ensures `<priv_dir>/ssh/` exists, and generates a 2048-bit RSA host key on first boot. Subsequent boots reuse the same key. Lets Phoenix admin TUIs and similar drop the daemon straight into a supervision tree without hand-rolling host-key bootstrap
- `ExRatatui.SSH.Daemon` `:system_dir` accepts binary paths in addition to charlists; the daemon converts them before forwarding to `:ssh.daemon/2`
- VTE-based input parser covering arrows, function keys, SS3, CSI modifiers, Alt+letter, Ctrl+letter, and partial-sequence buffering across feeds (SSH delivers byte-at-a-time during interactive use)
- 7 new session NIFs on ExRatatui.Native: `session_new/2`, `session_close/1`, `session_draw/2`, `session_take_output/1`, `session_feed_input/2`, `session_resize/3`, `session_size/1`
- Guide: `guides/ssh_transport.md` — architecture, quick start, `nerves_ssh` integration, options reference, host-key generation, troubleshooting
- Examples ship an SSH mode: `examples/system_monitor.exs --ssh` and `examples/task_manager` via `TASK_MANAGER_SSH=1` (multiple clients share one SQLite database)
- README "Running Over SSH" section
- CI enforces 100% Elixir test coverage threshold (NIF modules excluded)
- Missing doctests for `ExRatatui`, `Event`, `Event.Key`, `Event.Mouse`, `Event.Resize`, and `SlashCommands`
- Callback documentation for all `ExRatatui.App` callbacks

### Changed

- ExRatatui.Server learns a `transport: :local | :ssh` option and an alternate `init/1` path that drives an injected Session + writer function instead of the local terminal
- `ExRatatui.App` gains a `:transport` option that dispatches between ExRatatui.Server `start_link/1` and `ExRatatui.SSH.Daemon.start_link/1`

### Docs

- Expanded moduledoc prose for `ExRatatui`, `Event`, and event struct modules
- Added coverage requirement note to CONTRIBUTING.md

### Tests

- Bumped Elixir test coverage to 100% — added server, rendering, layout, event, and widget tests
- End-to-end SSH integration test exercising `:ssh.daemon/2` + `:ssh.connect/3` round trip with a generated host key (mount → render bytes → keystroke roundtrip → window_change)

## [0.5.1] - 2026-03-25

### Added

- `ExRatatui.Widgets.Markdown` — markdown rendering widget with syntax-highlighted code blocks, powered by `tui-markdown` (pulldown-cmark + syntect)
- `ExRatatui.Widgets.Textarea` — multiline text editor with undo/redo, cursor movement, and Emacs-style shortcuts. Second **stateful** widget — state lives in Rust via ResourceArc
- `ExRatatui.Widgets.Throbber` — loading spinner widget with 12 animation sets (braille, dots, ascii, arrow, clock, and more)
- `ExRatatui.Widgets.Popup` — centered modal overlay widget for dialogs, confirmations, and command palettes
- `ExRatatui.Widgets.WidgetList` — vertical list of heterogeneous widgets with selection and scrolling, ideal for chat message histories
- `ExRatatui.Widgets.SlashCommands` — slash command parsing, matching, and autocomplete popup rendering
- Textarea NIF functions: `textarea_new/0`, `textarea_handle_key/3`, `textarea_get_value/1`, `textarea_set_value/2`, `textarea_cursor/1`, `textarea_line_count/1`
- Example: `chat_interface.exs` — AI chat interface demonstrating Markdown, Textarea, Throbber, Popup, WidgetList, and SlashCommands

### Fixed

- Replaced deprecated `Padding::zero()` with `Padding::ZERO` in Rust widget renderers
- Wired up unused `style` field in `WidgetList` render function (was `#[allow(dead_code)]`)
- Fixed flaky Rust throbber step test — `calc_step(0)` uses random index, now tests with deterministic non-zero steps
- Throbber animation set test now covers all 12 sets (was 7)

## [0.5.0] - 2026-03-22

### Added

- `ExRatatui.Widgets.Tabs` — a tab bar widget for switching between views, with customizable selection highlight, divider, and padding
- `ExRatatui.Widgets.Scrollbar` — a scrollbar widget for indicating scroll position, supporting all four orientations (vertical right/left, horizontal bottom/top)
- `ExRatatui.Widgets.LineGauge` — a thin single-line progress bar using line-drawing characters, with separate filled/unfilled styles
- `ExRatatui.Widgets.Checkbox` — a checkbox widget for boolean toggles, with customizable checked/unchecked symbols and styles
- `ExRatatui.Widgets.TextInput` — a single-line text input widget with cursor navigation, viewport scrolling, and placeholder support. First **stateful** widget — state lives in Rust via ResourceArc
- Example: `widget_showcase.exs` — interactive demo with tabs, progress bars, checkboxes, text input, scrollable logs, and scrollbar (replaces individual `tabs_demo.exs`, `scrollbar_demo.exs`, `line_gauge_demo.exs`)
- Doctests for `Tabs`, `Scrollbar`, `LineGauge`, and `Checkbox` struct modules
- Updated `task_manager.exs` example to use `Tabs` (header), `LineGauge` (progress), `Scrollbar` (task table), and `TextInput` (new task creation — replaces hand-rolled input buffer with proper cursor navigation, viewport scrolling, and placeholder support)
- Updated `examples/task_manager/` App to use `Tabs` (filter bar with Tab/Shift+Tab navigation), `LineGauge` (replaces `Gauge`), `Scrollbar` (task table), and `TextInput` (replaces hand-rolled input buffer)
- Comprehensive `TextInput` state management tests: get/set value, cursor positioning, backspace, delete, left/right, home/end, and mid-text insertion

### Fixed

- `Checkbox` moduledoc now correctly states that `:checked_symbol` and `:unchecked_symbol` default to `nil` (rendered as `"[x]"` / `"[ ]"` by the Rust backend)
- Removed redundant `.padding()` call in Rust tabs renderer that was always overwritten

## [0.4.2] - 2026-03-06

### Added

- `ExRatatui.Widgets.Clear` — a widget that resets all cells in its area to empty (space) characters, useful for rendering overlays

### Fixed

- Put back `Elixir.` prefix from `List` calls in `task_manager.exs` example

## [0.4.1] - 2026-02-23

### Fixed

- `init_terminal` NIF now cleans up raw mode and alternate screen on partial initialization failure
- All I/O-bound NIFs (`init_terminal`, `restore_terminal`, `draw_frame`, `terminal_size`) now run on the DirtyIo scheduler to avoid blocking normal BEAM schedulers
- `App.render/2` callback typespec narrowed from `term()` to `ExRatatui.widget()` for proper Dialyzer coverage
- `Constraint::Ratio` with denominator zero now returns an error instead of panicking
- `Gauge` ratio now validates the value is finite, preventing a panic on NaN input
- `App.mount/1` callback typespec now includes `{:error, reason}` return
- `ExRatatui.run/1` `after` block no longer masks the original exception if terminal restore also fails
- Server render errors now log the full stacktrace for easier debugging
- Added missing `@impl true` on fallback `terminate/2` clause in the server
- `ExRatatui.Frame` struct defaults to `width: 0, height: 0` instead of `nil` (typespec now matches actual usage)
- Deduplicated `encode_constraint/1` — `ExRatatui.Layout` is now the single source of truth
- Fixed flaky `poll_event` tests that failed when terminal events arrived during the test run
- `Event.Mouse` typespec fields are now non-nullable to match actual NIF output
- Fixed `system_monitor.exs` to cache hostname between refreshes with `Map.get_lazy/3`
- Removed unnecessary `Elixir.` prefix from `List` calls in `task_manager.exs` example
- Added server tests for `{:stop, state}` from `handle_info/2` and `terminate/2` callback

### Docs

- HexDocs "View Source" links now point to the correct version tag
- Expanded `ExRatatui` moduledoc with quick start, core API overview, and cross-references
- README demo GIF now uses an absolute URL so it renders on Hex.pm
- README modifiers list now shows all six supported modifiers
- Documented `:test_mode` option in `ExRatatui.App` for headless testing
- Clarified `system_monitor.exs` is Linux/Nerves only in README

## [0.4.0] - 2026-02-23

### Changed

- **BREAKING**: Terminal state is now per-process via Rust ResourceArc instead of a global mutex
  - `ExRatatui.run/1` closure now receives the terminal reference (1-arity)
  - `draw/1` is now `ExRatatui.draw/2` (terminal reference as first argument)
  - `ExRatatui.init_test_terminal/2` returns a terminal reference instead of `:ok`
  - `get_buffer_content/0` is now `ExRatatui.get_buffer_content/1`
  - `ExRatatui.App` behaviour users: **no API changes**
- Terminal is automatically restored when the terminal reference is garbage collected (crash safety)
- Test terminal instances are now independent, enabling `async: true` for rendering tests

### Added

- Comprehensive API documentation: all key codes, mouse events, colors, modifiers, and App options
- Doctests for Layout, Style, Frame, all widgets, and test backend
- CONTRIBUTING.md with development setup

## [0.3.0] - 2026-02-23

### Added

- Typespecs (`@type t`) for all widget, event, and frame structs
- Function specs (`@spec`) for all public API functions
- Dialyzer static analysis in CI

### Changed

- Extracted `Event.Key`, `Event.Mouse`, `Event.Resize` and `Layout.Rect` into their own files

### Fixed

- Server `start_link/1` now supports `name: nil` to start without process registration
- App-based TUI processes hanging on macOS — the event poll loop now delegates the timeout to the NIF on the DirtyIo scheduler instead of using `Process.send_after/3`, which was causing the GenServer to stop processing messages

## [0.2.0] - 2026-02-21

### Changed

- Simplified release workflow by using `rustler-precompiled-action` instead of manual build and packaging steps

### Added

- Precompiled NIF target for `riscv64gc-unknown-linux-gnu` (Nerves RISC-V boards)
- System monitor example (`examples/system_monitor.exs`) for running on Nerves devices via SSH

## [0.1.1] - 2026-02-19

### Changed

- Improved HexDocs module grouping: Frame moved under Layout, App under new Application group
- Added demo GIF to README

### Fixed

- Changelog formatting for ex_doc compatibility

## [0.1.0] - 2026-02-19

### Added

- **Widgets:** Paragraph (with alignment, wrapping, scrolling), Block (borders, titles, padding), List (selectable with highlight), Table (headers, rows, column constraints), and Gauge (progress bar)
- **Layout engine:** Constraint-based area splitting via `ExRatatui.Layout.split/3` with support for `:percentage`, `:length`, `:min`, `:max`, and `:ratio` constraints
- **Event polling:** Non-blocking keyboard, mouse, and resize event handling on BEAM's DirtyIo scheduler
- **Styling system:** Named colors, RGB (`{:rgb, r, g, b}`), 256-color indexed (`{:indexed, n}`), and text modifiers (bold, italic, underlined, dim, crossed out, etc.)
- **Terminal lifecycle:** `ExRatatui.run/1` for automatic terminal init and cleanup
- **OTP App behaviour:** `ExRatatui.App` with LiveView-inspired callbacks (`mount/1`, `render/2`, `handle_event/2`, `handle_info/2`) for building supervised TUI applications
- **GenServer runtime:** manages terminal lifecycle, self-scheduling event polling, and callback dispatch under OTP supervision
- **Frame struct:** `ExRatatui.Frame` carries terminal dimensions to `render/2` callbacks
- **Test backend:** Headless `TestBackend` via `init_test_terminal/2` and `get_buffer_content/0` for CI-friendly rendering verification
- **Precompiled NIFs:** Via `rustler_precompiled` for Linux, macOS, and Windows (x86_64 and aarch64) — no Rust toolchain required
- **Examples:** `hello_world.exs` (minimal display), `counter.exs` (interactive key events), `counter_app.exs` (App-based counter), `task_manager.exs` (full app with all widgets), and `examples/task_manager/` (supervised Ecto + SQLite CRUD app)

[Unreleased]: https://github.com/mcass19/ex_ratatui/compare/v0.8.2...HEAD
[0.8.1]: https://github.com/mcass19/ex_ratatui/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/mcass19/ex_ratatui/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/mcass19/ex_ratatui/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/mcass19/ex_ratatui/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/mcass19/ex_ratatui/compare/v0.6.2...v0.7.0
[0.6.2]: https://github.com/mcass19/ex_ratatui/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/mcass19/ex_ratatui/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/mcass19/ex_ratatui/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/mcass19/ex_ratatui/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/mcass19/ex_ratatui/compare/v0.4.2...v0.5.0
[0.4.2]: https://github.com/mcass19/ex_ratatui/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/mcass19/ex_ratatui/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/mcass19/ex_ratatui/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/mcass19/ex_ratatui/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/mcass19/ex_ratatui/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/mcass19/ex_ratatui/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/mcass19/ex_ratatui/releases/tag/v0.1.0
