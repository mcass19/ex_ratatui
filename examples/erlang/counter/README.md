# erlang_counter — an ExRatatui app in Erlang

The counter from [`basics/reducer_counter_app.exs`](../../basics/reducer_counter_app.exs), written in Erlang: Up and Down change the count, a 1-second subscription counts ticks with `render?: false`, typing fills a `TextInput`, Enter logs the label and count to a `Table`, and Esc quits. A tick shows up on the next key's frame.

See the [Erlang and Gleam guide](../../../guides/runtimes/erlang_and_gleam.md).

## Requirements

`rebar3` and `elixir`. `mise install` sets them up from `mise.toml`.

`rebar.config` uses the [`exerl`](https://hex.pm/packages/exerl) plugin rather than `rebar_mix`, which copies only a dependency's `ebin` and so loses the NIF. Elixir's lib dir has to be on `ERL_LIBS`, or `Application.app_dir/2` is undefined when the NIF loads:

```sh
export ERL_LIBS=$(elixir -e 'IO.puts(Path.dirname(:code.lib_dir(:elixir)))')
```

## Run

```sh
rebar3 shell --eval 'erlang_counter:start(), init:stop().'
```

## Test

```sh
rebar3 eunit
```

The tests run on a headless terminal, using `test_mode` and `ExRatatui.Runtime.inject_event/2`.
