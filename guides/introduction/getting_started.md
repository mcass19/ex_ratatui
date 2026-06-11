# Getting Started

This guide walks you from an empty `mix new` project to a supervised terminal UI you can actually use. Read it top-to-bottom the first time; come back later for the capstone module.

Every concept is introduced with runnable code. If you get stuck, compare your file against the snippets.

## What you'll build

A small todo app. Type an item, press Enter to add it, move selection with `↑`/`↓` (or `k`/`j`), press `d` to delete, Tab to switch focus between the input and the list, Esc to quit.

```
┌────────────────────────────────────────────────────────┐
│  Todo                                                  │
├────────────────────────────────────────────────────────┤
│ › buy groceries_                                       │
├────────────────────────────────────────────────────────┤
│  walk the dog                                          │
│ ›file taxes                                            │
│  call mom                                              │
│                                                        │
└────────────────────────────────────────────────────────┘
  Tab switch · Enter add · d delete · Esc quit
```

## Install and verify

Create a project and add the dependency:

```sh
mix new my_tui --sup
cd my_tui
```

Edit `mix.exs`:

```elixir
defp deps do
  [
    {:ex_ratatui, "~> 0.10"}
  ]
end
```

Fetch:

```sh
mix deps.get
mix compile
```

A precompiled NIF for your platform downloads automatically — you don't need Rust installed. On first compile you'll see `rustler_precompiled` fetch the binary.

Verify it works. Create `lib/hello.ex`:

```elixir
defmodule Hello do
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  def run do
    ExRatatui.run(fn terminal ->
      {w, h} = ExRatatui.terminal_size()

      paragraph = %Paragraph{
        text: "Hello from ExRatatui!\n\nPress any key to exit.",
        style: %Style{fg: :green, modifiers: [:bold]},
        alignment: :center,
        block: %Block{
          title: " Hello World ",
          borders: [:all],
          border_type: :rounded,
          border_style: %Style{fg: :cyan}
        }
      }

      ExRatatui.draw(terminal, [{paragraph, %Rect{x: 0, y: 0, width: w, height: h}}])
      wait_for_key()
    end)
  end

  defp wait_for_key do
    case ExRatatui.poll_event(5_000) do
      nil -> wait_for_key()
      _ -> :ok
    end
  end
end
```

Run it:

```sh
iex -S mix
iex> Hello.run()
```

You should see a rounded box with a green centered message. Press any key to return to IEx.

If instead you get `terminal_init_failed`, you're likely in a non-TTY shell (IDE terminal, background process, piped stdin). Run from a real terminal emulator — see the [Debugging guide](../internals/debugging.md) for more.

## Your first render

Let's look at what that snippet actually did.

```elixir
ExRatatui.run(fn terminal ->
  # ...
end)
```

`ExRatatui.run/1` takes a function, puts the terminal into raw mode, gives you a `terminal` reference, and guarantees the terminal is restored when the function returns (or raises). This is the right shape for a one-shot script but not for a supervised app — we'll replace it in a minute.

```elixir
{w, h} = ExRatatui.terminal_size()
```

Returns the current size in cells. The terminal won't automatically resize your widgets — you place them explicitly, in cell coordinates.

```elixir
paragraph = %Paragraph{
  text: "Hello from ExRatatui!\n\nPress any key to exit.",
  style: %Style{fg: :green, modifiers: [:bold]},
  alignment: :center,
  block: %Block{title: " Hello World ", borders: [:all], border_type: :rounded}
}
```

A **widget is a struct**. It doesn't draw anything on its own — it's a value you hand to `draw/2`. `Paragraph` renders text; `Block` is a decorative wrapper most widgets accept via a `:block` field for a title and borders.

```elixir
ExRatatui.draw(terminal, [{paragraph, %Rect{x: 0, y: 0, width: w, height: h}}])
```

`draw/2` takes a list of `{widget, rect}` tuples. Each `%Rect{}` says *where* to paint the widget. You can pass many tuples — the whole frame is rendered in one go.

```elixir
ExRatatui.poll_event(5_000)
```

Polls for a terminal event (key press, mouse, resize) with a timeout in milliseconds. Returns `nil` on timeout, an `%Event.Key{}` / `%Event.Mouse{}` / `%Event.Resize{}` (or paste / focus event) otherwise. Event polling runs on the BEAM's DirtyIo scheduler so your other processes keep running.

That's the whole "bare metal" API: size, build structs, draw, poll. For a supervised long-running app, you want the next layer.

## Switch to `ExRatatui.App`

`ExRatatui.run/1` is fine for scripts. For a real app you want supervision, test support, and transports (SSH, distribution). That's what the `ExRatatui.App` behaviour gives you.

Replace `lib/hello.ex` with:

```elixir
defmodule Hello do
  use ExRatatui.App

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  @impl true
  def mount(_opts) do
    {:ok, %{}}
  end

  @impl true
  def render(_state, frame) do
    paragraph = %Paragraph{
      text: "Hello from ExRatatui!\n\nPress any key to exit.",
      style: %Style{fg: :green, modifiers: [:bold]},
      alignment: :center,
      block: %Block{
        title: " Hello World ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    [{paragraph, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
  end

  @impl true
  def handle_event(%ExRatatui.Event.Key{kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(_event, state), do: {:noreply, state}
end
```

Three callbacks:

- **`mount/1`** — runs once when the app starts. Returns `{:ok, state}`. Here the state is empty.
- **`render/2`** — runs after every state change. Gets `state` and a `%Frame{width:, height:}` with the current terminal size. Returns `[{widget, rect}, ...]`. **Always return the full scene** — the runtime diffs cells between frames for you, but your job is to describe the whole screen.
- **`handle_event/2`** — receives a terminal event. Returns `{:noreply, new_state}` to keep running or `{:stop, state}` to quit. Here any key press quits.

Run it:

```sh
iex -S mix
iex> {:ok, pid} = Hello.start_link(name: nil)
```

Under a supervisor, you'd add it like any other child:

```elixir
# lib/my_tui/application.ex
children = [
  Hello
]
```

Same behavior as before, but now you have a proper OTP process you can test, supervise, and serve remotely. The [SSH](../transports/ssh_transport.md) and [Distribution](../transports/distributed_transport.md) guides serve this exact module over the network with no code changes.

## State and events

A static paragraph isn't very interactive. Let's add a counter.

```elixir
defmodule Hello do
  use ExRatatui.App

  alias ExRatatui.{Event, Layout}
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph}

  @impl true
  def mount(_opts), do: {:ok, %{count: 0}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    widget = %Paragraph{
      text: "\n\n  Count: #{state.count}",
      style: %Style{fg: :white, modifiers: [:bold]},
      alignment: :center,
      block: %Block{title: " Counter ", borders: [:all], border_type: :rounded}
    }

    [{widget, area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["up", "k"] do
    {:noreply, %{state | count: state.count + 1}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["down", "j"] do
    {:noreply, %{state | count: state.count - 1}}
  end

  def handle_event(_, state), do: {:noreply, state}
end
```

Two things to notice.

**Events come in `handle_event` clauses.** An `%Event.Key{}` carries `:code` (a string like `"up"`, `"a"`, `"enter"`, `"esc"`), `:modifiers` (strings too, e.g. `["ctrl"]`), and `:kind` (`"press"` / `"repeat"` / `"release"`). Pattern-match on the shape you care about; fall through to a catch-all `{:noreply, state}` so unhandled events don't crash.

**Return values control the loop:**

- `{:noreply, state}` — update state and re-render
- `{:noreply, state, opts}` — same, with options like `render?: false` to skip the re-render (see the [Performance guide](../internals/performance.md))
- `{:stop, state}` — exit cleanly

Run it, press `↑`/`↓` or `k`/`j`, watch the counter. Press `q` to quit.

## Layout

Placing everything in one giant `Rect` gets old fast. `Layout.split/3` divides a rectangle into regions using constraints.

```elixir
def render(state, frame) do
  area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

  [header, body, footer] = Layout.split(area, :vertical, [
    {:length, 3},
    {:min, 0},
    {:length, 1}
  ])

  header_widget = %Paragraph{
    text: "  Counter",
    style: %Style{fg: :cyan, modifiers: [:bold]},
    block: %Block{borders: [:all], border_type: :rounded}
  }

  body_widget = %Paragraph{
    text: "\n\n  Count: #{state.count}",
    alignment: :center,
    block: %Block{borders: [:all], border_type: :rounded}
  }

  footer_widget = %Paragraph{
    text: " ↑/k +1 · ↓/j -1 · q quit",
    style: %Style{fg: :dark_gray}
  }

  [{header_widget, header}, {body_widget, body}, {footer_widget, footer}]
end
```

Constraint types you'll use most:

- `{:length, n}` — exactly `n` cells
- `{:min, n}` — at least `n`, expand to fill remaining space
- `{:percentage, n}` — `n`% of the parent
- `{:ratio, num, den}` — `num/den` of the parent

`Layout.split/3` returns a list of `%Rect{}` in the same order as your constraints. Chain splits to build grids — split vertically into rows, then split each row horizontally into columns. The [Building UIs guide](../core/building_uis.md) goes deep on constraints.

## Styling and rich text

`%Style{}` carries foreground, background, and modifiers. Accepts named colors (`:green`), RGB (`{:rgb, 255, 100, 0}`), and 256-color indices (`{:indexed, 42}`).

```elixir
%Style{fg: :red, bg: {:rgb, 30, 30, 30}, modifiers: [:bold, :underlined]}
```

Most widgets take a top-level `:style` plus part-specific fields like `:highlight_style` or `:border_style`.

**Rich text** lets one string carry per-segment styling. Build a `%Span{}` for a styled run and group them with `%Line{}`:

```elixir
alias ExRatatui.Text.{Line, Span}

%Paragraph{
  text: Line.new([
    Span.new(" ok ", style: %Style{fg: :black, bg: :green}),
    Span.new("  Count: #{state.count}", style: %Style{modifiers: [:bold]})
  ])
}
```

`Paragraph.text`, `List.items`, `Table` cells, `Tabs.titles`, and `Block.title` all accept rich text. Plain strings keep working everywhere — you only reach for spans when you want mixed styling on one line.

Make negative counts red:

```elixir
style = if state.count < 0, do: %Style{fg: :red}, else: %Style{fg: :white}

body_widget = %Paragraph{
  text: "\n\n  Count: #{state.count}",
  style: style,
  alignment: :center,
  block: %Block{borders: [:all], border_type: :rounded}
}
```

## Capstone: a small todo app

Time to put it together. This app introduces two things you haven't seen:

1. **A stateful widget** — `TextInput` owns a NIF-side editor state. You create the state once in `mount/1`, keep the reference in your state map, and pass it to the widget on every render.
2. **Focus management** — two regions (input, list) want different keybindings. We track a `focus: :input | :list` atom and dispatch keys accordingly. For multi-panel apps with more than a couple of regions, `ExRatatui.Focus` gives you a proper focus ring; see [Building UIs](../core/building_uis.md#focus-management) for that pattern.

Create `lib/todo.ex`:

```elixir
defmodule Todo do
  use ExRatatui.App

  alias ExRatatui.{Event, Layout, Style}
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, List, Paragraph, TextInput}

  @impl true
  def mount(_opts) do
    {:ok,
     %{
       input: ExRatatui.text_input_new(),
       items: [],
       selected: 0,
       focus: :input
     }}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header, input_rect, list_rect, footer] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:length, 3},
        {:min, 0},
        {:length, 1}
      ])

    [
      {header_widget(), header},
      {input_widget(state), input_rect},
      {list_widget(state), list_rect},
      {footer_widget(), footer}
    ]
  end

  # ---- events ----------------------------------------------------------

  @impl true
  def handle_event(%Event.Key{code: "esc", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "tab", kind: "press"}, state) do
    {:noreply, toggle_focus(state)}
  end

  def handle_event(%Event.Key{kind: "press"} = key, %{focus: :input} = state) do
    {:noreply, handle_input_key(state, key)}
  end

  def handle_event(%Event.Key{kind: "press"} = key, %{focus: :list} = state) do
    {:noreply, handle_list_key(state, key)}
  end

  def handle_event(_event, state), do: {:noreply, state}

  # ---- input focus -----------------------------------------------------

  defp handle_input_key(state, %Event.Key{code: "enter"}) do
    case ExRatatui.text_input_get_value(state.input) do
      "" ->
        state

      text ->
        :ok = ExRatatui.text_input_set_value(state.input, "")
        %{state | items: state.items ++ [text]}
    end
  end

  defp handle_input_key(state, %Event.Key{code: code}) do
    :ok = ExRatatui.text_input_handle_key(state.input, code)
    state
  end

  # ---- list focus ------------------------------------------------------

  defp handle_list_key(state, %Event.Key{code: code}) when code in ["up", "k"] do
    %{state | selected: max(state.selected - 1, 0)}
  end

  defp handle_list_key(state, %Event.Key{code: code}) when code in ["down", "j"] do
    max_index = max(length(state.items) - 1, 0)
    %{state | selected: min(state.selected + 1, max_index)}
  end

  defp handle_list_key(state, %Event.Key{code: "d"}) do
    items = List.delete_at(state.items, state.selected)
    %{state | items: items, selected: min(state.selected, max(length(items) - 1, 0))}
  end

  defp handle_list_key(state, _), do: state

  # ---- widgets ---------------------------------------------------------

  defp header_widget do
    %Paragraph{
      text: "  Todo",
      style: %Style{fg: :cyan, modifiers: [:bold]},
      block: %Block{borders: [:all], border_type: :rounded, border_style: %Style{fg: :dark_gray}}
    }
  end

  defp input_widget(state) do
    %TextInput{
      state: state.input,
      placeholder: "Add a todo…",
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: border_style(state.focus, :input)
      }
    }
  end

  defp list_widget(state) do
    %List{
      items: state.items,
      selected: if(state.items == [], do: nil, else: state.selected),
      highlight_symbol: "› ",
      highlight_style: %Style{fg: :black, bg: :yellow, modifiers: [:bold]},
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: border_style(state.focus, :list)
      }
    }
  end

  defp footer_widget do
    %Paragraph{
      text: "  Tab switch · Enter add · d delete · Esc quit",
      style: %Style{fg: :dark_gray}
    }
  end

  # ---- helpers ---------------------------------------------------------

  defp toggle_focus(%{focus: :input} = state), do: %{state | focus: :list}
  defp toggle_focus(%{focus: :list} = state), do: %{state | focus: :input}

  defp border_style(focus, id) do
    if focus == id,
      do: %Style{fg: :yellow, modifiers: [:bold]},
      else: %Style{fg: :dark_gray}
  end

end
```

Run it:

```sh
iex -S mix
iex> {:ok, pid} = Todo.start_link(name: nil)
iex> ref = Process.monitor(pid)
iex> receive do {:DOWN, ^ref, _, _, _} -> :ok end
```

Things worth highlighting:

- **`TextInput` state is created in `mount/1`, never in `render/2`.** Creating it on every render would lose the cursor and typed text between frames. The reference lives in state; the widget just reads it.
- **`handle_event/2` dispatches by focus.** The pattern `def handle_event(%Event.Key{…} = key, %{focus: :input} = state)` is a clean way to split behavior without nested `case`.
- **Guard against empty state.** `List.selected` is set to `nil` when there are no items so you don't highlight row zero of an empty list. Delete clamps the new selection to the new length.
- **Focus shows visually.** The focused region gets a bold yellow border. This is a minimal pattern — for more panels, reach for `ExRatatui.Focus`.

## Where to go next

You now have a working local supervised TUI with input, a list, and focus. From here, pick the guide that matches what you want to learn:

- **[Building UIs](../core/building_uis.md)** — full widget reference, layout deep-dive, rich text, events, `ExRatatui.Focus`.
- **[Callback Runtime](../runtimes/callback_runtime.md)** — all callbacks (`mount`, `render`, `handle_event`, `handle_info`, `terminate`), options, lifecycle details.
- **[Reducer Runtime](../runtimes/reducer_runtime.md)** — Elm-style alternative with first-class commands, subscriptions, and runtime inspection. Good when you have async work or want structured side effects.
- **[Custom Widgets](../core/custom_widgets.md)** — compose primitives into reusable widgets via the `ExRatatui.Widget` protocol.
- **[State Machine Patterns](../runtimes/state_machines.md)** — multi-screen apps, modals, conditional UI.
- **[Testing](../internals/testing.md)** — headless test backend, `inject_event`, `Runtime.snapshot`, property-based tests.
- **[Debugging](../internals/debugging.md)** — `Runtime.snapshot`, tracing, buffer inspection, common errors.
- **[Performance](../internals/performance.md)** — `render?: false`, poll tuning, keeping `render/2` cheap.
- **[Running TUIs over SSH](../transports/ssh_transport.md)** — serve this exact app to remote clients.
- **[Running TUIs over Erlang Distribution](../transports/distributed_transport.md)** — drive the TUI from a different BEAM node.

Or browse the [examples/](https://github.com/mcass19/ex_ratatui/tree/main/examples) folder for more patterns — `layout/focus.exs`, `apps/chat.exs`, and `apps/task_manager_db/` are good next reads.
