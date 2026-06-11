# Building UIs

This guide covers the building blocks for constructing screens in `render/2`: widgets, layout, styles, and events. Everything here works identically in both the [Callback Runtime](../runtimes/callback_runtime.md) and [Reducer Runtime](../runtimes/reducer_runtime.md).

## Layout

`render/2` returns a list of `{widget, rect}` tuples. Each `%ExRatatui.Layout.Rect{}` defines a rectangular area on the screen. Use `ExRatatui.Layout.split/3` to divide areas into sub-regions using constraints:

```elixir
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect

area = %Rect{x: 0, y: 0, width: 80, height: 24}

# Three-row layout: header, body, footer
[header, body, footer] = Layout.split(area, :vertical, [
  {:length, 3},
  {:min, 0},
  {:length, 1}
])

# Split body into sidebar + main
[sidebar, main] = Layout.split(body, :horizontal, [
  {:percentage, 30},
  {:percentage, 70}
])
```

### Constraint types

| Constraint | Description |
|------------|-------------|
| `{:percentage, n}` | Percentage of the available space (0–100) |
| `{:length, n}` | Exact number of rows or columns |
| `{:min, n}` | At least `n` rows/columns, expands to fill remaining space |
| `{:max, n}` | At most `n` rows/columns |
| `{:ratio, num, den}` | Fraction of available space (e.g., `{:ratio, 1, 3}` for one-third) |
| `{:fill, weight}` | Proportional share of whatever is left after the other constraints (`{:fill, 1}` + `{:fill, 2}` splits leftover space 1:2) |

`split/4` also takes `:flex` (how excess space is distributed — centered popups, end-aligned status bars) and `:spacing` (gutter cells between segments) — see `ExRatatui.Layout` for the shapes.

## Styles

Styles control foreground color, background color, and text modifiers:

```elixir
alias ExRatatui.Style

# Named colors
%Style{fg: :green, bg: :black}

# RGB
%Style{fg: {:rgb, 255, 100, 0}}

# 256-color indexed
%Style{fg: {:indexed, 42}}

# Modifiers
%Style{modifiers: [:bold, :dim, :italic, :underlined, :crossed_out, :reversed]}
```

Named colors: `:black`, `:red`, `:green`, `:yellow`, `:blue`, `:magenta`, `:cyan`, `:gray`, `:dark_gray`, `:light_red`, `:light_green`, `:light_yellow`, `:light_blue`, `:light_magenta`, `:light_cyan`, `:white`, `:reset`.

Styles can be applied to most widgets via the `:style` field, and many widgets accept additional style fields for specific parts (e.g., `highlight_style`, `border_style`).

## Rich text

Text fields on many widgets accept more than a plain string: pass a `%ExRatatui.Text.Span{}`, a `%ExRatatui.Text.Line{}`, a list of spans, or any mix — letting a single string of output carry per-span colors and modifiers.

```elixir
alias ExRatatui.Text.{Line, Span}
alias ExRatatui.Style

# A single styled run
Span.new("error", style: %Style{fg: :red, modifiers: [:bold]})

# Multiple styled runs on one line
Line.new([
  Span.new(" ok ", style: %Style{fg: :green}),
  Span.new(" Build ", style: %Style{fg: :yellow, modifiers: [:bold]})
])

# Line-level overrides: a style layered over spans + per-line alignment
Line.new([Span.new("centered")], style: %Style{modifiers: [:bold]}, alignment: :center)
```

Widgets that accept rich text on their text-bearing fields:

| Widget | Field(s) |
|--------|----------|
| `Paragraph` | `:text` |
| `BigText` | `:lines` (first arg to `BigText.new/2`) |
| `List` | each `items` entry |
| `Table` | each cell in `:rows`, each `:header` cell |
| `Tabs` | each `:titles` entry |
| `Block` | `:title` (single-line only) |

Accepted shapes on these fields: `String.t()`, `%Span{}`, `%Line{}`, or `[%Span{}]`. Plain strings continue to work everywhere. Fields that are semantically single-line (table cells, tab titles, block titles) raise if passed a string with embedded newlines.

## Events

Terminal events are polled automatically by the runtime. In the [Callback Runtime](../runtimes/callback_runtime.md), they arrive in `handle_event/2`. In the [Reducer Runtime](../runtimes/reducer_runtime.md), they arrive as `{:event, event}` in `update/2`.

### Key events

```elixir
%ExRatatui.Event.Key{
  code: "q",          # key name: "a"-"z", "up", "down", "enter", "esc", "tab", etc.
  kind: "press",      # "press", "release", or "repeat"
  modifiers: []       # list of "ctrl", "alt", "shift", "super", "hyper", "meta"
}
```

### Mouse events

```elixir
%ExRatatui.Event.Mouse{
  kind: "down",       # "down", "up", "drag", "moved", "scroll_up", "scroll_down", "scroll_left", "scroll_right"
  button: "left",     # "left", "right", "middle" ("" for moves and scrolls)
  x: 10,
  y: 5,
  modifiers: []
}
```

### Resize events

```elixir
%ExRatatui.Event.Resize{
  width: 120,
  height: 40
}
```

The runtime automatically re-renders on resize — there's no need to handle resize events unless the app needs to react to size changes in its state.

## Widgets

Every widget is a plain struct. The [Widgets Cheatsheet](../cheatsheets/widgets.cheatmd) is the per-widget quick reference — every struct with its key fields and a copyable snippet — and each widget's moduledoc holds the full option and validation detail. One contract applies across the board: malformed fields (wrong types, negative sizes, unknown atoms) raise `ArgumentError` at encode time rather than rendering garbage.

| Purpose | Widgets |
|---|---|
| Text and containers | `Paragraph`, `Block` (borders + top/bottom titles), `Clear`, `Markdown`, `CodeBlock`, `BigText` |
| Lists and tables | `List`, `Table`, `WidgetList` |
| Progress and activity | `Gauge`, `LineGauge`, `Sparkline`, `Throbber` |
| Charts and drawing | `BarChart` (`Bar` / `BarGroup`), `Chart` (`Chart.Axis` / `Chart.Dataset`), `Canvas` (`Line` / `Rectangle` / `Circle` / `Points` / `Map` / `Label` shapes) |
| Navigation and selection | `Tabs`, `Scrollbar`, `Calendar`, `Checkbox`, `Popup`, `SlashCommands` |
| Input (stateful, NIF-backed) | `TextInput`, `Textarea` |
| Media | `Image` — covered in the [Images guide](images.md) |

The subsections below cover the patterns that need more than a struct literal. For everything else, lift the snippet from the cheatsheet.

### Composing with Block

Any widget wraps itself in a framed `Block` via its `:block` field — title, borders, and border styling in one struct:

```elixir
%Paragraph{
  text: "Inside a box",
  block: %Block{title: " Title ", borders: [:all], border_type: :rounded}
}
```

Border types: `:plain`, `:rounded`, `:double`, `:thick`.

### Stateful widgets: TextInput and Textarea

Most widgets are pure view descriptors rebuilt every frame. `TextInput` (single-line) and `Textarea` (multi-line, with undo/redo and Emacs-style shortcuts) are the exception — their editor state lives in a NIF resource. Create the state once in `mount/1`/`init/1`, keep the reference in app state, and pass it to the widget on every render:

```elixir
# In mount/1 or init/1 — never in render/2
state = ExRatatui.text_input_new()

# In the event handler: forward key codes (Textarea also takes modifiers)
ExRatatui.text_input_handle_key(state, key.code)
ExRatatui.textarea_handle_key(state, key.code, key.modifiers)

# Read the value any time
ExRatatui.text_input_get_value(state)

# In render/2
%TextInput{
  state: state,
  placeholder: "Type here...",
  block: %Block{title: " Search ", borders: [:all]}
}
```

Recreating the state in `render/2` silently drops the cursor position and typed text on every frame — the most common stateful-widget mistake.

### Overlays: Popup and Clear

`Popup` centers any widget over the parent area, clearing the background underneath — dialogs, confirmations, command palettes:

```elixir
%Popup{
  content: %Paragraph{text: "Are you sure?"},
  block: %Block{title: " Confirm ", borders: [:all], border_type: :rounded},
  percent_width: 50,
  percent_height: 30
}
```

`Clear` is the lower-level building block: it resets every cell in its rect, for hand-rolled overlays drawn late in the render list.

### Heterogeneous scrolling: WidgetList

`WidgetList` stacks widgets of different heights into a scrollable column — chat histories, log views, mixed-content feeds. Each item is a `{widget, height}` tuple:

```elixir
%WidgetList{
  items: [
    {%Paragraph{text: "User: Hello!"}, 1},
    {%Markdown{content: "**Bot:** Hi there!\n\nHow can I help?"}, 4},
    {%Paragraph{text: "User: What is Elixir?"}, 1}
  ],
  selected: 1,
  highlight_style: %Style{fg: :yellow},
  scroll_offset: 0,
  block: %Block{title: " Chat ", borders: [:all]}
}
```

`scroll_offset` is a row offset from the top of the content, not an item index — to scroll to a specific item, sum the heights of the preceding items. Items partially above the viewport are clipped row-by-row instead of dropped.

### Command palettes: SlashCommands

`SlashCommands` is a utility module (not a widget struct) for building a `/command` palette on top of `Popup` + `List`: `parse/1` detects a `/prefix` in the input, `match_commands/2` filters the registered commands, and `render_autocomplete/2` builds the popup widgets to append to the render list:

```elixir
case SlashCommands.parse(input_text) do
  {:command, prefix} ->
    matched = SlashCommands.match_commands(commands, prefix)
    base_widgets ++ SlashCommands.render_autocomplete(matched, area: area, selected: 0)

  :no_command ->
    base_widgets
end
```

See [`examples/apps/chat.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/apps/chat.exs) for a full integration.

## Focus management

Apps with multiple interactive widgets (e.g., a TextInput + List + details pane) need to track which widget "owns" the current keystroke. Rather than reinventing that bookkeeping every time, use `ExRatatui.Focus`:

```elixir
alias ExRatatui.{Event, Focus}

# Declare the focus ring up front, e.g. in mount/1 or init/1.
state = %{
  focus: Focus.new([:search, :results, :details]),
  search: ExRatatui.text_input_new(),
  results: [...],
  selected: 0
}
```

Route every key event through `Focus.handle_key/2` before dispatching. Tab / Shift+Tab / `back_tab` are consumed (focus moves, the key comes back as `nil`). Everything else passes through unchanged.

```elixir
def handle_event(%Event.Key{} = key, state) do
  {focus, key} = Focus.handle_key(state.focus, key)
  state = %{state | focus: focus}

  case key do
    nil ->
      {:noreply, state}

    key ->
      case Focus.current(focus) do
        :search  -> {:noreply, update_search(state, key)}
        :results -> {:noreply, update_results(state, key)}
        :details -> {:noreply, update_details(state, key)}
      end
  end
end
```

Style the focused widget with `Focus.focused?/2`:

```elixir
border_style =
  if Focus.focused?(focus, :search),
    do: %Style{fg: :yellow},
    else: %Style{fg: :gray}

%TextInput{
  state: state.search,
  block: %Block{borders: [:all], border_style: border_style}
}
```

Override the default keys with `%Event.Key{}` entries — e.g., to add Ctrl+Tab / Ctrl+Shift+Tab or arrow-based cycling:

```elixir
Focus.new([:search, :results, :details],
  next_keys: [%Event.Key{code: "tab"}, %Event.Key{code: "right", modifiers: ["ctrl"]}],
  prev_keys: [%Event.Key{code: "back_tab"}, %Event.Key{code: "left", modifiers: ["ctrl"]}]
)
```

See [`examples/layout/focus.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/layout/focus.exs) for a full three-panel demo.

### Mouse routing

`Focus` carries a `regions: %{id => Rect}` map alongside the ring. Register the regions after layout (typically inside a `%Event.Resize{}` handler) and `Focus.handle_mouse/2` will focus the panel under a left-click — passing the event through so widgets that care (cursor placement, drag start) can still react.

```elixir
def handle_event(%Event.Resize{width: w, height: h}, state) do
  area = %Rect{x: 0, y: 0, width: w, height: h}
  [search_rect, body_rect] = Layout.split(area, :vertical, [{:length, 3}, {:min, 0}])
  [results_rect, details_rect] = Layout.split(body_rect, :horizontal, [
    {:percentage, 40}, {:min, 0}
  ])

  focus =
    Focus.set_regions(state.focus, %{
      search: search_rect,
      results: results_rect,
      details: details_rect
    })

  {:noreply, %{state | focus: focus}}
end

def handle_event(%Event.Mouse{} = mouse, state) do
  {focus, mouse} = Focus.handle_mouse(state.focus, mouse)
  # Left-click in a known region just moved focus; the click is still
  # in `mouse` so the widget can react (Checkbox toggle, cursor place).
  {:noreply, %{state | focus: focus}}
end
```

The local terminal needs mouse capture explicitly turned on — pass `mouse_capture: true` to `ExRatatui.run/2` or as a `start_link` option on the `:local` `ExRatatui.App`. SSH and distributed transports decode mouse events regardless. Scroll-wheel routing is intentionally not built in; `Focus.current/1` after `handle_mouse/2` routes "to the focused widget", `Focus.at/3` routes "to the widget under the cursor" — pick whichever fits.

Overlapping regions resolve to the smallest by area (leaf-inside-container picks the leaf). Boundaries are half-open (`x >= rx and x < rx + w`) — natural for ratatui rect semantics. Registering a region for an ID that isn't in the ring raises.

## Theming

Most apps want consistent colors across borders, highlights, text, and status indicators without scattering literal `%Style{fg: :cyan}` calls everywhere. `ExRatatui.Theme` is a pure-data palette struct designed for exactly that — apps thread it through render code by hand, no globals, no automatic injection.

```elixir
alias ExRatatui.Theme

theme = Theme.default()                 # dark-friendly; :surface nil so light and dark terminals both look right
# or  Theme.light()                     # dark text on white surface
# or  %Theme{primary: :magenta, accent: {:rgb, 245, 158, 11}, ...}
```

Eleven semantic slots cover the common needs:

| Slot | Purpose |
|---|---|
| `:primary` | Brand color for titles and major headers |
| `:accent` | Interactive / focused / selected elements |
| `:border` / `:border_focused` | Panel border colors |
| `:surface` / `:surface_alt` | Background and striped-row background |
| `:text` / `:text_dim` | Body text and secondary text (hints, placeholders, disabled) |
| `:success` / `:warning` / `:danger` | Status messages and severity indicators |

Every slot accepts the full `t:ExRatatui.Style.color/0` shape (named atoms, `{:rgb, r, g, b}`, `{:indexed, n}`, or `nil`).

Three helpers cover the most common patterns:

```elixir
# Border styling, with a focused override.
%Block{
  borders: [:all],
  border_style: Theme.border_style(theme, focused: Focus.focused?(focus, :search))
}

# Body text and dim hint text.
%Paragraph{text: "Hello", style: Theme.text_style(theme)}
%Paragraph{text: "(empty)", style: Theme.text_style(theme, dim: true)}

# Selection inversion for List / Table / Tabs highlights.
%List{items: results, highlight_style: Theme.selection_style(theme)}
```

Anything more specialised — gradient-style accents, severity-tinted text — destructures the slots inline:

```elixir
%Paragraph{
  text: " #{count} failures ",
  style: %Style{fg: theme.surface, bg: theme.danger, modifiers: [:bold]}
}
```

`Theme` is deliberately just pure data plus three helpers — no opt-in magic, no global configuration, nothing injected behind the scenes.

## Examples

  * [`examples/widgets/`](https://github.com/mcass19/ex_ratatui/tree/main/examples/widgets) — focused, copyable demos of individual widgets (bar chart, sparkline, chart, calendar, canvas, checkbox, table, and more)
  * [`examples/apps/chat.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/apps/chat.exs) — AI chat interface demonstrating markdown, textarea, throbber, popup, and slash commands
  * [`examples/apps/task_manager_db/`](https://github.com/mcass19/ex_ratatui/tree/main/examples/apps/task_manager_db) — full CRUD app using table, tabs, scrollbar, line gauge, and block compositions
  * [`examples/layout/focus.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/layout/focus.exs) — multi-panel layout with Tab-cycled focus

## Related

  * [Callback Runtime](../runtimes/callback_runtime.md) — OTP-style callbacks
  * [Reducer Runtime](../runtimes/reducer_runtime.md) — Elm-style commands and subscriptions
  * [Running TUIs over SSH](../transports/ssh_transport.md) — SSH transport
  * [Running TUIs over Erlang Distribution](../transports/distributed_transport.md) — distribution transport
