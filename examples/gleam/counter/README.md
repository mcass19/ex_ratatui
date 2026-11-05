# gleam_counter — an ExRatatui app in Gleam

The counter from [`basics/reducer_counter_app.exs`](../../basics/reducer_counter_app.exs), written in Gleam: Up and Down change the count, a 1-second subscription counts ticks with `render?: false`, typing fills a `TextInput`, Enter logs the label and count to a `Table`, and Esc quits. A tick shows up on the next key's frame.

`src/gleam_counter.gleam` holds the app, in the shape of an Elm program. `src/gleam_counter_ffi.erl` holds what Gleam can't write: Elixir structs, event fields, and the `'render?'` atom.

See the [Erlang and Gleam guide](../../../guides/runtimes/erlang_and_gleam.md).

## Requirements

`gleam`, `elixir`, and `rebar3`. Gleam builds ExRatatui with Mix and `telemetry` with rebar3. `mise install` sets them all up from `mise.toml`.

This example needs `ExRatatui.App.start_link/2`, which is newer than ExRatatui 0.19.0 on Hex.

## Run

```sh
gleam run
```

## Test

```sh
gleam test
```

The tests run on a headless terminal, using `test_mode` and `ExRatatui.Runtime.inject_event/2`.
