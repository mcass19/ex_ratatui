# Erlang and Gleam

An ExRatatui app can be an Erlang or Gleam module. There is no separate API: the module implements the `ExRatatui.App` callbacks and starts through `ExRatatui.App.start_link/2`. Elixir still has to be installed, because ExRatatui is a Mix project.

Runnable versions of everything here are in the catalog: [`examples/gleam/counter`](https://github.com/mcass19/ex_ratatui/tree/main/examples/gleam/counter) and [`examples/erlang/counter`](https://github.com/mcass19/ex_ratatui/tree/main/examples/erlang/counter).

## Installing

### Gleam

Needs `gleam`, `elixir`, and `rebar3` on the `PATH`. Gleam builds ExRatatui with Mix and `telemetry` with rebar3.

```sh
gleam add ex_ratatui
```

Gleam rejects a Mix project as a path or git dependency, so only Hex releases work. That Gleam builds Mix packages at all is observed rather than documented; tested with Gleam 1.19.2.

### Erlang

Needs `rebar3` and `elixir`. Use the [`exerl`](https://hex.pm/packages/exerl) plugin, tested with 0.3.0. `rebar_mix` copies only a dependency's `ebin`, which loses the NIF, so the app fails to load it at runtime.

```erlang
{deps, [{ex_ratatui, "~> 0.19"}]}.
{plugins, [exerl]}.
```

Elixir's lib dir has to be on `ERL_LIBS`, or `Application.app_dir/2` is undefined when the NIF loads:

```sh
export ERL_LIBS=$(elixir -e 'IO.puts(Path.dirname(:code.lib_dir(:elixir)))')
```

## The smallest app

### Erlang

```erlang
-module(my_tui).
-behaviour('Elixir.ExRatatui.App').
-export([start/0, mount/1, render/2, handle_event/2]).

start() ->
    {ok, Pid} = 'Elixir.ExRatatui.App':start_link(?MODULE, []),
    Ref = monitor(process, Pid),
    receive {'DOWN', Ref, process, Pid, _Reason} -> ok end.

mount(_Opts) ->
    {ok, 0}.

render(Count, #{width := Width, height := Height}) ->
    Text = <<"Counter: ", (integer_to_binary(Count))/binary>>,
    Paragraph = 'Elixir.ExRatatui.Widgets.Paragraph':'__struct__'(#{text => Text}),
    Area = 'Elixir.ExRatatui.Layout.Rect':'__struct__'(#{x => 0, y => 0, width => Width, height => Height}),
    [{Paragraph, Area}].

handle_event(#{code := <<"q">>}, Count) -> {stop, Count};
handle_event(#{code := <<"k">>}, Count) -> {noreply, Count + 1};
handle_event(_Event, Count) -> {noreply, Count}.
```

```sh
rebar3 shell --eval 'my_tui:start(), init:stop().'
```

`rebar3 shell --eval` exits without evaluating when stdin isn't a terminal. For scripts and CI, run `rebar3 compile` and then `erl -noshell -pa _build/default/lib/*/ebin -eval '...'`.

### Gleam

Gleam can't write Elixir structs, so a small Erlang file sits next to the module in `src/`.

```gleam
import gleam/dynamic.{type Dynamic}
import gleam/int

pub type Next {
  Noreply(Int)
  Stop(Int)
}

pub type AppModule {
  MyTui
}

pub type Pid

pub type Event

pub type Frame

pub type Rect

pub type Widget

pub fn mount(_options: Dynamic) -> Result(Int, Nil) {
  Ok(0)
}

pub fn render(count: Int, frame: Frame) -> List(#(Widget, Rect)) {
  [#(paragraph("Counter: " <> int.to_string(count)), area(frame))]
}

pub fn handle_event(event: Event, count: Int) -> Next {
  case key_code(event) {
    "q" -> Stop(count)
    "k" -> Noreply(count + 1)
    _ -> Noreply(count)
  }
}

pub fn main() -> Nil {
  let assert Ok(pid) = start_link(MyTui, [])
  wait_for_exit(pid)
}

@external(erlang, "Elixir.ExRatatui.App", "start_link")
fn start_link(module: AppModule, options: List(Dynamic)) -> Result(Pid, Dynamic)

@external(erlang, "my_tui_ffi", "paragraph")
fn paragraph(text: String) -> Widget

@external(erlang, "my_tui_ffi", "area")
fn area(frame: Frame) -> Rect

@external(erlang, "my_tui_ffi", "key_code")
fn key_code(event: Event) -> String

@external(erlang, "my_tui_ffi", "wait_for_exit")
fn wait_for_exit(pid: Pid) -> Nil
```

```erlang
-module(my_tui_ffi).
-export([paragraph/1, area/1, key_code/1, wait_for_exit/1]).

paragraph(Text) ->
    'Elixir.ExRatatui.Widgets.Paragraph':'__struct__'(#{text => Text}).

area(#{width := Width, height := Height}) ->
    'Elixir.ExRatatui.Layout.Rect':'__struct__'(#{x => 0, y => 0, width => Width, height => Height}).

key_code(#{code := Code}) -> Code;
key_code(_Event) -> <<>>.

%% `gleam run` halts the VM as soon as main returns.
wait_for_exit(Pid) ->
    Ref = monitor(process, Pid),
    receive {'DOWN', Ref, process, Pid, _Reason} -> nil end.
```

Unlike Erlang's `-behaviour`, nothing checks these callbacks or the `@external` signatures at compile time.

## Data shapes

Elixir modules are the atoms `'Elixir.ExRatatui.Layout'` and so on, and Elixir strings are binaries. In Gleam, `@external(erlang, "Elixir.ExRatatui.Layout", "split")` binds any function whose arguments Gleam can write.

| Value | Erlang | Gleam |
|---|---|---|
| Widgets, `Rect`, `Style`, `Block` | `'Elixir.ExRatatui.Style':'__struct__'(#{fg => cyan})` | The same, in the Erlang file |
| Frame, events | Maps: `#{width := W}`, `#{code := <<"q">>, kind := <<"press">>}` | Field access in the Erlang file |
| `mount/1` result | `{ok, State}` | `Ok(state)` |
| Transition result | `{noreply, State}`, `{stop, State}` | Custom type: `Noreply(state)`, `Stop(state)` |
| Runtime opts | `{noreply, State, [{'render?', false}]}` | In the Erlang file; a custom type can't name `'render?'` |
| Start options | `[{test_mode, {80, 24}}, {name, nil}]` | Custom type: `TestMode(#(80, 24))`, `Name(Nil)` |
| Constraints | `{length, 3}`, `{min, 0}` | Custom type: `Length(3)`, `Min(0)` |
| Colors, modifiers, borders | `dark_gray`, `bold`, `all` | Custom type: `DarkGray`, `Bold`, `All` |

Nested values have to be real structs too: a plain map for `style` or `block` raises when the frame is encoded.

## Elm-style updates

`use` is what selects the reducer runtime, so these modules run on the callback runtime. For the same structure, keep an `update` function and call it from `handle_event/2` and `handle_info/2`. `subscriptions/1` and runtime opts such as `commands` work the same way. The only visible difference is `mode: :callbacks` in `ExRatatui.Runtime.snapshot/1`.

```erlang
handle_info(tick, Model) -> update(tick, Model);
handle_info(_Message, Model) -> {noreply, Model}.

subscriptions(_Model) ->
    ['Elixir.ExRatatui.Subscription':interval(counter_tick, 1000, tick)].
```

`handle_info/2` receives whatever reaches the runtime's mailbox, so a Gleam version needs a catch-all clause even if its message type lists only `Tick`.

## Supervision

`ExRatatui.App.child_spec/2` returns a map an OTP supervisor accepts:

```erlang
init([]) ->
    Children = ['Elixir.ExRatatui.App':child_spec(my_tui, [])],
    {ok, {#{strategy => one_for_one}, Children}}.
```

`gleam_otp` supervisors take their own child format and haven't been tested.

## Transports

`transport: :ssh` and `transport: :distributed` work from both languages with the options in the [SSH](../transports/ssh_transport.md) and [distribution](../transports/distributed_transport.md) guides, and `'Elixir.ExRatatui.Distributed':attach(Node, my_tui)` attaches from an Erlang client.

The SSH daemon needs the `ssh` application running, which comes with starting `ex_ratatui`. `gleam run` starts dependencies on its own, while a plain `erl -eval` has to call `application:ensure_all_started(ex_ratatui)`.

## Testing

`test_mode` and `ExRatatui.Runtime.inject_event/2` work as in the [Testing guide](../internals/testing.md). The Gleam example has a `gleam test` suite that drives the app this way, through a small Erlang file of its own.

## Limits

- **No custom widgets.** `ExRatatui.Widget` is an Elixir protocol, and neither language can write a `defimpl`.
- **No JavaScript target for Gleam.** ExRatatui is a NIF on the BEAM.
- **A wrong shim can look like a blank screen.** A bad widget doesn't crash the app: the frame is dropped with a log line and a `[:ex_ratatui, :render, :dropped]` telemetry event, and the last good frame stays up.
- **Tested on Linux only**, with OTP 29 and Elixir 1.20. macOS, rebar3 releases, and `gleam export` haven't been run.
