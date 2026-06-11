# State Machine Patterns

Once a TUI goes past a single screen, state starts to branch. There's a login flow, a main app, a settings panel, maybe a modal dialog on top of any of them. Stuffing that into a flat map and a big `case` in `render/2` works for a while, then stops working.

This guide is a pattern catalog. All examples work with either runtime — the structure is the same; only the transition signature differs.

## State-as-data vs branching in `render/2`

The first instinct is "render differently when this flag is set":

```elixir
def render(state, frame) do
  cond do
    state.loading? -> loading_view(frame)
    state.error -> error_view(state.error, frame)
    state.settings_open? -> settings_view(state, frame)
    true -> main_view(state, frame)
  end
end
```

This grows fast. Three flags become eight combinations, and tests never get written for all of them. Swap the flags for a single `:screen` atom that *names the state*:

```elixir
def render(%{screen: :loading} = state, frame), do: loading_view(state, frame)
def render(%{screen: :error} = state, frame), do: error_view(state, frame)
def render(%{screen: :settings} = state, frame), do: settings_view(state, frame)
def render(%{screen: :main} = state, frame), do: main_view(state, frame)
```

Now the states are mutually exclusive by construction. Transitions become `%{state | screen: :main}` instead of `%{state | loading?: false, error: nil, settings_open?: false}`.

## Mode atom → dispatch

Same trick for events. Don't pattern-match event codes at the top level — dispatch by screen first:

```elixir
# Callback runtime
def handle_event(event, %{screen: :main} = state), do: handle_main(event, state)
def handle_event(event, %{screen: :settings} = state), do: handle_settings(event, state)
def handle_event(event, %{screen: :error} = state), do: handle_error(event, state)

defp handle_main(%Event.Key{code: "s"}, state), do: {:noreply, %{state | screen: :settings}}
defp handle_main(%Event.Key{code: "q"}, state), do: {:stop, state}
defp handle_main(_, state), do: {:noreply, state}

defp handle_settings(%Event.Key{code: "esc"}, state), do: {:noreply, %{state | screen: :main}}
defp handle_settings(_, state), do: {:noreply, state}
```

Each screen owns its own keymap. Adding a new key to settings doesn't risk breaking main. Same pattern in the reducer runtime, just with `update({:event, event}, state)`.

## Overlay layer for modals

A modal isn't really a new screen — it's a temporary layer on top of whatever's underneath. Model it as a second field:

```elixir
%{
  screen: :main,              # underlying app
  overlay: nil                # or :confirm_quit, :help, :command_palette
}
```

Render both, overlay last:

```elixir
def render(state, frame) do
  base = render_screen(state.screen, state, frame)

  case state.overlay do
    nil -> base
    overlay -> base ++ render_overlay(overlay, state, frame)
  end
end
```

Event dispatch checks the overlay *first* — if one's open, the underlying screen doesn't see input:

```elixir
def handle_event(event, %{overlay: nil} = state), do: handle_screen(event, state)
def handle_event(event, state), do: handle_overlay(event, state)

defp handle_overlay(%Event.Key{code: "esc"}, state), do: {:noreply, %{state | overlay: nil}}
defp handle_overlay(%Event.Key{code: "y"}, %{overlay: :confirm_quit} = state), do: {:stop, state}
defp handle_overlay(_, state), do: {:noreply, state}
```

This keeps the overlay logic in one place and prevents the "why did pressing 'q' close the modal *and* quit the app?" bug.

## Modal via `%Popup{}`

`%Popup{}` does the rendering math — it centers a content widget over the given area and handles sizing:

```elixir
defp render_overlay(:confirm_quit, _state, frame) do
  popup = %Popup{
    content: %Paragraph{
      text: "Quit? (y/n)",
      alignment: :center
    },
    percent_width: 30,
    percent_height: 20,
    block: %Block{title: " Confirm ", borders: [:all], border_type: :double}
  }

  [{popup, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
end
```

Popup renders on top of whatever cells are already there — the `Block`'s background clears the region. For modals that should dim the underlying UI, wrap in `%Clear{}` over a padded rect before the popup.

## Multi-screen apps — explicit transitions

For login → main → settings, make transitions explicit commands/returns, not flag flips:

```elixir
# Reducer runtime
def update({:event, %Event.Key{code: "enter"}}, %{screen: :login} = state) do
  case authenticate(state.username, state.password) do
    {:ok, user} -> {:noreply, %{state | screen: :main, user: user}}
    {:error, reason} -> {:noreply, %{state | screen: :login, error: reason}}
  end
end

def update({:event, %Event.Key{code: "s", modifiers: ["ctrl"]}}, %{screen: :main} = state) do
  {:noreply, %{state | screen: :settings, prev_screen: :main}}
end

def update({:event, %Event.Key{code: "esc"}}, %{screen: :settings, prev_screen: prev} = state) do
  {:noreply, %{state | screen: prev, prev_screen: nil}}
end
```

Note `:prev_screen`. When "esc" from settings should return to wherever the user came from (main, or a sub-screen), track it in state. Don't hard-code `:main` — that breaks the day settings gains a second entry point.

## Conditional UI

Flags within a screen are still fine for small visibility toggles:

```elixir
defp main_view(state, frame) do
  panels =
    [left_panel(state)] ++
      if(state.show_debug?, do: [debug_panel(state)], else: []) ++
      [right_panel(state)]

  [...]
end
```

A handful of these is fine. Once there are five booleans that combine meaningfully, promote to a screen atom or an explicit `:mode` field.

### Focus-aware rendering

When focus matters to the visual — highlighted border on the focused panel, say — track it in state and derive styles in `render/2`:

```elixir
defp panel_border(state, panel_id) do
  if state.focus == panel_id do
    %Style{fg: :yellow, modifiers: [:bold]}
  else
    %Style{fg: :dark_gray}
  end
end
```

For larger apps with a ring of focusable IDs and tab cycling, see `ExRatatui.Focus` — it handles the ring navigation and dispatching events to the currently-focused panel.

## Loading / async states

Async work deserves its own screen atom when it's blocking (nothing else to do until it finishes), or a flag when it's backgrounded (user can still interact):

```elixir
# Blocking: :loading is a screen
def update({:event, %Event.Key{code: "enter"}}, %{screen: :main} = state) do
  command = Command.async(fn -> fetch_report() end, &{:report_loaded, &1})
  {:noreply, %{state | screen: :loading}, commands: [command]}
end

def update({:info, {:report_loaded, report}}, %{screen: :loading} = state) do
  {:noreply, %{state | screen: :report, report: report}}
end

# Non-blocking: :refreshing? is a flag on :main
def update({:event, %Event.Key{code: "r"}}, %{screen: :main} = state) do
  command = Command.async(fn -> refresh() end, &{:refreshed, &1})
  {:noreply, %{state | refreshing?: true}, commands: [command]}
end
```

The screen-atom version shows a full loading view; the flag version shows a throbber in the corner while the user keeps working.

## Escape hatches — when to split processes

Everything above assumes state fits in one `ExRatatui.App`. That's usually the right default. But sometimes the state machine doesn't really belong to the UI:

- **Background data that should survive a UI restart.** A cache, a subscription to external events, a long-running computation.
- **Shared state across multiple TUI sessions.** Over SSH, each client gets its own `Server` — if all clients should see the same data, that data lives in a sibling GenServer, not in app state.
- **Hardware or external resources.** A serial port, a database connection, a websocket — these want their own lifecycle.

In those cases, spin up a separate `GenServer` (or `Agent`, or `Registry`) as a sibling under the same supervisor. The `ExRatatui.App` calls into it in `handle_event/2`/`update/2` and subscribes to its updates. The app stays focused on "what the user sees right now"; the sibling handles "what's true about the world."

```elixir
# supervisor
children = [
  MyApp.DataService,        # owns the cache, subscribes to upstream
  {MyApp.TUI, transport: :local}
]

# in TUI
def handle_event(%Event.Key{code: "r"}, state) do
  MyApp.DataService.refresh()     # fire-and-forget
  {:noreply, state}
end

def handle_info({:data_updated, data}, state) do
  {:noreply, %{state | data: data}}
end
```

Over SSH or distribution, `MyApp.DataService` is one singleton; the TUI children are per-session. That's exactly the shape we want — one source of truth, many views.

## Related

- [Callback Runtime](callback_runtime.md) — full `handle_event` / `handle_info` API.
- [Reducer Runtime](reducer_runtime.md) — `update/2`, `Command`, `Subscription`.
- [Building UIs](../core/building_uis.md) — `ExRatatui.Focus`, layout, styles.
- [Testing](../internals/testing.md) — asserting state-machine transitions deterministically.
