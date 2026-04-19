# Building UIs

This guide covers the building blocks for constructing screens in `render/2`: widgets, layout, styles, and events. Everything here works identically in both the [Callback Runtime](callback_runtime.md) and [Reducer Runtime](reducer_runtime.md).

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

### Constraint Types

| Constraint | Description |
|------------|-------------|
| `{:percentage, n}` | Percentage of the available space (0–100) |
| `{:length, n}` | Exact number of rows or columns |
| `{:min, n}` | At least `n` rows/columns, expands to fill remaining space |
| `{:max, n}` | At most `n` rows/columns |
| `{:ratio, num, den}` | Fraction of available space (e.g., `{:ratio, 1, 3}` for one-third) |

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

## Rich Text

Text fields on many widgets accept more than a plain string: you can pass a `%ExRatatui.Text.Span{}`, a `%ExRatatui.Text.Line{}`, a list of spans, or any mix — letting a single string of output carry per-span colors and modifiers.

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
| `List` | each `items` entry |
| `Table` | each cell in `:rows`, each `:header` cell |
| `Tabs` | each `:titles` entry |
| `Block` | `:title` (single-line only) |

Accepted shapes on these fields: `String.t()`, `%Span{}`, `%Line{}`, or `[%Span{}]`. Plain strings continue to work everywhere. Fields that are semantically single-line (table cells, tab titles, block titles) raise if you pass a string with embedded newlines.

## Events

Terminal events are polled automatically by the runtime. In the [Callback Runtime](callback_runtime.md), they arrive in `handle_event/2`. In the [Reducer Runtime](reducer_runtime.md), they arrive as `{:event, event}` in `update/2`.

### Key Events

```elixir
%ExRatatui.Event.Key{
  code: "q",          # key name: "a"-"z", "up", "down", "enter", "esc", "tab", etc.
  kind: "press",      # "press", "release", or "repeat"
  modifiers: []       # list of "ctrl", "alt", "shift", "super", "hyper", "meta"
}
```

### Mouse Events

```elixir
%ExRatatui.Event.Mouse{
  kind: "down",       # "down", "up", "drag", "moved", "scroll_down", "scroll_up"
  column: 10,
  row: 5,
  modifiers: []
}
```

### Resize Events

```elixir
%ExRatatui.Event.Resize{
  width: 120,
  height: 40
}
```

The runtime automatically re-renders on resize — you don't need to handle resize events unless your app needs to react to size changes in its state.

## Widgets

### Paragraph

Displays text with support for alignment, wrapping, and scrolling.

```elixir
%Paragraph{
  text: "Hello, world!\nSecond line.",
  style: %Style{fg: :cyan, modifiers: [:bold]},
  alignment: :center,
  wrap: true
}
```

### Block

A container with borders and a title. Any widget can be wrapped inside a Block via its `:block` field.

```elixir
%Block{
  title: "My Panel",
  borders: [:all],
  border_type: :rounded,
  border_style: %Style{fg: :blue}
}

# Compose with other widgets:
%Paragraph{
  text: "Inside a box",
  block: %Block{title: "Title", borders: [:all]}
}
```

Border types: `:plain`, `:rounded`, `:double`, `:thick`.

### List

A selectable list with highlight support for the current item.

```elixir
%List{
  items: ["Elixir", "Rust", "Haskell"],
  highlight_style: %Style{fg: :yellow, modifiers: [:bold]},
  highlight_symbol: " > ",
  selected: 0,
  block: %Block{title: " Languages ", borders: [:all]}
}
```

### Table

A table with headers, rows, and column width constraints.

```elixir
%Table{
  rows: [["Alice", "30"], ["Bob", "25"]],
  header: ["Name", "Age"],
  widths: [{:length, 15}, {:length, 10}],
  highlight_style: %Style{fg: :yellow},
  selected: 0
}
```

### Gauge

A progress bar that fills proportionally to a given ratio.

```elixir
%Gauge{
  ratio: 0.75,
  label: "75%",
  gauge_style: %Style{fg: :green}
}
```

### LineGauge

A thin single-line progress bar using line-drawing characters, with separate styles for the filled and unfilled portions.

```elixir
%LineGauge{
  ratio: 0.6,
  label: "60%",
  filled_style: %Style{fg: :green},
  unfilled_style: %Style{fg: :dark_gray}
}
```

### BarChart

Vertical or horizontal bar chart. `:data` is a list of `%Bar{}` structs, each with a plain-string `:label` and non-negative integer `:value`. Chart-level `:bar_style`, `:value_style`, and `:label_style` apply to every bar; individual bars override color via `:style` and replace the numeric display via `:text_value`. When `:max` is `nil` the chart auto-scales to the largest value.

```elixir
alias ExRatatui.Widgets.{Bar, BarChart}

%BarChart{
  data: [
    %Bar{label: "Elixir", value: 80},
    %Bar{label: "Rust", value: 95, style: %Style{fg: :red}, text_value: "95!"},
    %Bar{label: "Go", value: 60}
  ],
  bar_width: 6,
  bar_gap: 2,
  bar_style: %Style{fg: :cyan},
  value_style: %Style{fg: :white, modifiers: [:bold]},
  label_style: %Style{fg: :dark_gray},
  direction: :vertical,                 # or :horizontal
  block: %Block{title: " Traffic ", borders: [:all]}
}
```

Values must be non-negative integers — floats or negatives raise `ArgumentError` at encode time. Grouped bars (multiple `BarGroup`s) are not supported yet; a single flat list is rendered as one group.

### Tabs

A tab bar for switching between views.

```elixir
%Tabs{
  titles: ["Home", "Settings", "Help"],
  selected: 0,
  highlight_style: %Style{fg: :cyan, modifiers: [:bold]},
  divider: " | ",
  block: %Block{borders: [:all]}
}
```

### Scrollbar

A scroll position indicator for long content, supporting both vertical and horizontal orientations.

```elixir
%Scrollbar{
  content_length: 100,
  position: 25,
  viewport_content_length: 10,
  orientation: :vertical_right,
  thumb_style: %Style{fg: :cyan}
}
```

Orientations: `:vertical_right`, `:vertical_left`, `:horizontal_bottom`, `:horizontal_top`.

### Checkbox

A boolean toggle with customizable checked and unchecked symbols.

```elixir
%Checkbox{
  label: "Enable notifications",
  checked: true,
  checked_style: %Style{fg: :green},
  checked_symbol: "✓",
  unchecked_symbol: "✗"
}
```

### TextInput

A single-line text input with cursor navigation and viewport scrolling. This is a **stateful** widget — its state lives in Rust via ResourceArc.

```elixir
# Create state (once, e.g. in mount/1 or init/1)
state = ExRatatui.text_input_new()

# Forward key events
ExRatatui.text_input_handle_key(state, "h")
ExRatatui.text_input_handle_key(state, "i")

# Read/set value
ExRatatui.text_input_get_value(state)  #=> "hi"
ExRatatui.text_input_set_value(state, "hello")

# Render
%TextInput{
  state: state,
  style: %Style{fg: :white},
  cursor_style: %Style{fg: :black, bg: :white},
  placeholder: "Type here...",
  placeholder_style: %Style{fg: :dark_gray},
  block: %Block{title: "Search", borders: [:all], border_type: :rounded}
}
```

### Clear

Resets all cells in its area to empty space characters. This is useful for clearing a region before rendering an overlay on top of existing content.

```elixir
%Clear{}
```

### Markdown

Renders markdown text with syntax-highlighted code blocks, powered by `tui-markdown` (pulldown-cmark + syntect). Supports headings, bold, italic, inline code, fenced code blocks, bullet lists, links, and horizontal rules.

```elixir
%Markdown{
  content: "# Hello\n\nSome **bold** text and `inline code`.\n\n```elixir\nIO.puts(\"hi\")\n```",
  wrap: true,
  block: %Block{title: "Response", borders: [:all]}
}
```

### Textarea

A multiline text editor with undo/redo, cursor movement, and Emacs-style shortcuts. This is a **stateful** widget — its state lives in Rust via ResourceArc.

```elixir
# Create state (once, e.g. in mount/1 or init/1)
state = ExRatatui.textarea_new()

# Forward key events (with modifier support)
ExRatatui.textarea_handle_key(state, "h", [])
ExRatatui.textarea_handle_key(state, "enter", [])
ExRatatui.textarea_handle_key(state, "w", ["ctrl"])  # delete word backward

# Read value
ExRatatui.textarea_get_value(state)  #=> "h\n"

# Render
%Textarea{
  state: state,
  placeholder: "Type your message...",
  placeholder_style: %Style{fg: :dark_gray},
  block: %Block{title: "Message", borders: [:all], border_type: :rounded}
}
```

### Throbber

A loading spinner that animates through symbol sets. The caller controls the animation by incrementing `:step` on each tick.

```elixir
%Throbber{
  label: "Loading...",
  step: state.tick,
  throbber_set: :braille,
  throbber_style: %Style{fg: :cyan},
  block: %Block{title: "Status", borders: [:all]}
}
```

Available sets: `:braille`, `:dots`, `:ascii`, `:vertical_block`, `:horizontal_block`, `:arrow`, `:clock`, `:box_drawing`, `:quadrant_block`, `:white_square`, `:white_circle`, `:black_circle`.

### Popup

A centered modal overlay that renders any widget over the parent area, clearing the background underneath. Useful for dialogs, confirmations, and command palettes.

```elixir
%Popup{
  content: %Paragraph{text: "Are you sure?"},
  block: %Block{title: "Confirm", borders: [:all], border_type: :rounded},
  percent_width: 50,
  percent_height: 30
}
```

### WidgetList

A vertical list of heterogeneous widgets with optional selection and scrolling. Each item is a `{widget, height}` tuple, making it ideal for chat message histories and similar layouts where items have different heights.

`scroll_offset` is a row offset from the top of the content, not an item index. To scroll to a specific item, sum the heights of all preceding items. Items partially above the viewport are clipped row-by-row instead of being dropped entirely.

> **Migrating from v0.6.1 or earlier:** `scroll_offset` used to be an item index. If you were passing `scroll_offset: selected`, convert by summing the heights of all preceding items, e.g. `items |> Enum.take(selected) |> Enum.map(&elem(&1, 1)) |> Enum.sum()`. See the v0.6.2 entry in the [CHANGELOG](https://github.com/mcass19/ex_ratatui/blob/main/CHANGELOG.md) for details.

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
  block: %Block{title: "Chat", borders: [:all]}
}
```

### SlashCommands

`SlashCommands` is a utility module (not a widget struct) that helps you build a command palette on top of `Popup` + `List`. Use `parse/1` to detect a `/prefix`, `match_commands/2` to filter your commands, and `render_autocomplete/2` to build the popup widgets you append to your render list.

```elixir
alias ExRatatui.Widgets.SlashCommands
alias ExRatatui.Widgets.SlashCommands.Command

commands = [
  %Command{name: "help", description: "Show help"},
  %Command{name: "quit", description: "Exit the app"}
]

# In your render/2:
case SlashCommands.parse(input_text) do
  {:command, prefix} ->
    matched = SlashCommands.match_commands(commands, prefix)
    popup_widgets = SlashCommands.render_autocomplete(matched, area: area, selected: 0)
    base_widgets ++ popup_widgets

  :no_command ->
    base_widgets
end
```

See [`examples/chat_interface.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/chat_interface.exs) for a full integration.

## Focus management

Apps with multiple interactive widgets (e.g., a TextInput + List + details pane) need to track which widget "owns" the current keystroke. Rather than reinventing that bookkeeping every time, use `ExRatatui.Focus`:

```elixir
alias ExRatatui.{Event, Focus}

# Declare the focus ring up front, e.g. in mount/2 or init/1.
state = %{
  focus: Focus.new([:search, :results, :details]),
  search: ExRatatui.text_input_new(),
  results: [...],
  selected: 0
}
```

Route every key event through `Focus.handle_key/2` before dispatching. Tab / Shift+Tab / `back_tab` are consumed (focus moves, you get `nil` back). Everything else passes through unchanged.

```elixir
def handle_event(%Event.Key{} = key, state) do
  {focus, key} = Focus.handle_key(state.focus, key)
  state = %{state | focus: focus}

  case key do
    nil ->
      state

    key ->
      case Focus.current(focus) do
        :search  -> update_search(state, key)
        :results -> update_results(state, key)
        :details -> update_details(state, key)
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

See [`examples/focus_multi_panel.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/focus_multi_panel.exs) for a full three-panel demo.

## Examples

  * [`examples/widget_showcase.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widget_showcase.exs) — interactive showcase of tabs, progress bars, checkboxes, text input, and scrollable logs
  * [`examples/chat_interface.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/chat_interface.exs) — AI chat interface demonstrating markdown, textarea, throbber, popup, and slash commands
  * [`examples/task_manager/`](https://github.com/mcass19/ex_ratatui/tree/main/examples/task_manager) — full CRUD app using table, tabs, scrollbar, line gauge, and block compositions
  * [`examples/focus_multi_panel.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/focus_multi_panel.exs) — multi-panel layout with Tab-cycled focus

## Related

  * [Callback Runtime](callback_runtime.md) — OTP-style callbacks
  * [Reducer Runtime](reducer_runtime.md) — Elm-style commands and subscriptions
  * [Running TUIs over SSH](ssh_transport.md) — SSH transport
  * [Running TUIs over Erlang Distribution](distributed_transport.md) — distribution transport
