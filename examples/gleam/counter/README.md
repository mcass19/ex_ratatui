# gleam_counter — an ExRatatui app in Gleam

The counter from [`basics/reducer_counter_app.exs`](../../basics/reducer_counter_app.exs), written in Gleam: Up/k and Down/j change the count, a 1-second subscription counts ticks with `render?: false`, and q quits. A tick shows up on the next key's frame.

`src/gleam_counter.gleam` holds the app, in the shape of an Elm program. `src/gleam_counter_ffi.erl` holds what Gleam can't write: Elixir structs, event fields, and the `'render?'` atom.

See the [Erlang and Gleam guide](../../../guides/runtimes/erlang_and_gleam.md).

## Requirements

`gleam`, `elixir`, and `rebar3`. Gleam builds ExRatatui with Mix and `telemetry` with rebar3. Tested with Gleam 1.19.2, OTP 29, and Elixir 1.20.

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
