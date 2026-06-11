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
| `BigText` | `:lines` (first arg to `BigText.new/2`) |
| `List` | each `items` entry |
| `Table` | each cell in `:rows`, each `:header` cell |
| `Tabs` | each `:titles` entry |
| `Block` | `:title` (single-line only) |

Accepted shapes on these fields: `String.t()`, `%Span{}`, `%Line{}`, or `[%Span{}]`. Plain strings continue to work everywhere. Fields that are semantically single-line (table cells, tab titles, block titles) raise if you pass a string with embedded newlines.

## Events

Terminal events are polled automatically by the runtime. In the [Callback Runtime](../runtimes/callback_runtime.md), they arrive in `handle_event/2`. In the [Reducer Runtime](../runtimes/reducer_runtime.md), they arrive as `{:event, event}` in `update/2`.

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

### BigText

Renders oversized 8×8-pixel text for slide titles, splash screens, and banners. Backed by [tui-big-text](https://github.com/ratatui/tui-widgets/tree/main/tui-big-text); use `ExRatatui.BigText.new/2` so input is coerced and options validated.

```elixir
ExRatatui.BigText.new("EX_RATATUI",
  pixel_size: :quadrant,
  alignment: :center,
  style: %Style{fg: :magenta, modifiers: [:bold]},
  block: %Block{borders: [:all], border_type: :rounded}
)
```

`:pixel_size` controls how many character cells a single 8×8 pixel maps to. Smaller variants pack more characters into the same area at the cost of legibility:

| Variant | Cells per pixel | Typical use |
|---------|-----------------|-------------|
| `:full` (default) | 1 × 1 | A single word, big impact (8 rows tall) |
| `:half_height` | 0.5 × 1 | Short title bar (4 rows tall) |
| `:half_width` | 1 × 0.5 | Tall narrow text |
| `:quadrant` | 0.5 × 0.5 | Good middle ground for 2–3 word titles |
| `:third_height` | 0.33 × 1 | |
| `:sextant` | 0.33 × 0.5 | |
| `:quarter_height` | 0.25 × 1 | |
| `:octant` | 0.25 × 0.5 | Densest; closer to "bold caps" |

See `examples/widgets/big_text.exs` to cycle through every variant interactively.

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

Values must be non-negative integers — floats or negatives raise `ArgumentError` at encode time.

#### Grouped bars

To render side-by-side clusters with shared captions — handy for comparing the same metric across categories (months, regions, products) — pass `%BarGroup{}` entries via `:groups` instead of `:data`. Each group carries its own optional `:label` and a list of `%Bar{}` structs, and `:group_gap` controls the spacing between clusters.

```elixir
alias ExRatatui.Widgets.{Bar, BarChart, BarGroup}

%BarChart{
  groups: [
    %BarGroup{label: "Q1", bars: [%Bar{label: "A", value: 10}, %Bar{label: "B", value: 20}]},
    %BarGroup{label: "Q2", bars: [%Bar{label: "A", value: 15}, %Bar{label: "B", value: 25}]}
  ],
  bar_width: 3,
  bar_gap: 1,
  group_gap: 3,
  max: 30
}
```

Set either `:data` or `:groups`, not both. When `:data` is used, the chart renders as a single anonymous group; supplying `:groups` overrides it. `:group_gap` must be a non-negative integer, and each entry in `:groups` must be a `%BarGroup{}` whose `:label` is `nil` or a binary — anything else raises `ArgumentError` at encode time.

### Sparkline

Compact, single-line bar chart for time-series or streaming data. `:data` is a list of non-negative integers with `nil` entries representing missing samples. Pick a preset via `:bar_set` (`:nine_levels` for smooth gradients, `:three_levels` for low-density glyphs) or pass a custom list of strings — the symbols are proportionally mapped across the nine internal density slots so any non-empty list works.

```elixir
alias ExRatatui.Widgets.Sparkline

%Sparkline{
  data: [0, 1, 3, 5, 8, 3, 1, nil, 2, 4],
  max: 8,                                   # auto-scales when nil
  direction: :left_to_right,                # or :right_to_left
  bar_set: :nine_levels,                    # or :three_levels, or [" ", "▂", "▅", "█"]
  style: %Style{fg: :cyan},
  absent_value_symbol: "·",
  absent_value_style: %Style{fg: :dark_gray},
  block: %Block{title: " CPU ", borders: [:all]}
}
```

Entries must be non-negative integers or `nil` — floats, negatives, and non-list `:data` raise `ArgumentError` at encode time. Unknown directions, unknown bar-set atoms, empty custom lists, and non-integer `:max` values raise similarly.

### Calendar

A monthly calendar grid that highlights a target date and optional per-day events. `:display_date` drives which month is rendered; events can be passed as a list of `{Date, Style}` tuples or as a `%{Date => Style}` map (map entries with a `nil` value are skipped, making toggling easy).

```elixir
alias ExRatatui.Widgets.Calendar

%Calendar{
  display_date: ~D[2026-03-15],
  events: [
    {~D[2026-03-10], %Style{fg: :red, modifiers: [:bold]}},
    {~D[2026-03-20], %Style{fg: :green}}
  ],
  default_style: %Style{fg: :white},
  show_month_header: true,
  header_style: %Style{fg: :yellow, modifiers: [:bold]},
  show_weekdays_header: true,
  weekday_style: %Style{fg: :cyan},
  show_surrounding: %Style{fg: :dark_gray},
  block: %Block{title: " March ", borders: [:all]}
}
```

`:display_date` must be a `%Date{}`; `:show_month_header` and `:show_weekdays_header` must be booleans; event entries must be `{%Date{}, %Style{}}` tuples. Anything else raises `ArgumentError` at encode time. Set `:show_surrounding` to a `Style` to bleed the previous/next month into empty grid cells (leave it `nil` to hide them). The widget needs roughly 22 columns × 8 rows without a block, or 24 × 10 with one.

### Canvas

A 2D drawing surface for plotting shapes, charts, and custom visualizations. Shapes are drawn onto a virtual coordinate system defined by `:x_bounds` and `:y_bounds` (both `{min, max}` tuples), then sampled onto the terminal cells using the chosen `:marker`.

```elixir
alias ExRatatui.Widgets.Canvas
alias ExRatatui.Widgets.Canvas.{Circle, Label, Line, Points, Rectangle}
alias ExRatatui.Widgets.Canvas.Map, as: CanvasMap

%Canvas{
  x_bounds: {0.0, 100.0},
  y_bounds: {0.0, 50.0},
  marker: :braille,                          # or :dot, :block, :bar, :half_block
  background_color: :black,
  shapes: [
    %Line{x1: 0.0, y1: 0.0, x2: 100.0, y2: 50.0, color: :cyan},
    %Rectangle{x: 10.0, y: 10.0, width: 30.0, height: 20.0, color: :yellow},
    %Circle{x: 70.0, y: 25.0, radius: 10.0, color: :magenta},
    %Points{coords: [{20.0, 40.0}, {50.0, 30.0}, {80.0, 10.0}], color: :green},
    %Label{x: 70.0, y: 25.0, text: "★", color: :white}
  ],
  block: %Block{title: " Plot ", borders: [:all]}
}
```

Every shape takes a plain `Color.t()` (not a `Style`) — canvases sample individual pixels so text modifiers do not apply. `Rectangle` is drawn as an outline anchored at its bottom-left corner; `Circle` is drawn as an outline centered on `{x, y}`; `Points` accepts a list of `{x, y}` tuples; `Label` writes a styled text annotation at the given canvas-space coordinate (handy for naming peaks, marking origins, or labeling map locations). Bounds must be `{min, max}` tuples with `min <= max`; `width`, `height`, and `radius` must be non-negative; any required field set to `nil` or a mistyped value raises `ArgumentError` at encode time. `:marker` defaults to `:braille`, which gives the finest sub-cell resolution — drop to `:dot` or `:block` for lower-density output or for terminals without Braille fonts.

#### Drawing a world map

`%CanvasMap{}` paints the world's coastlines into the canvas — pair it with the geographic bounds `{-180, 180}` × `{-90, 90}` and the `:dot` or `:braille` marker. `Label` shapes layered on top let you pin city names or other annotations directly in lat/lon space.

```elixir
%Canvas{
  x_bounds: {-180.0, 180.0},
  y_bounds: {-90.0, 90.0},
  marker: :dot,
  shapes: [
    %CanvasMap{resolution: :high, color: :green},  # :low | :high
    %Label{x: -74.0, y: 40.7, text: "NYC", color: :yellow},
    %Label{x: 139.7, y: 35.7, text: "Tokyo", color: :yellow}
  ],
  block: %Block{title: " World ", borders: [:all]}
}
```

`Map.resolution` accepts `:low` (cheap silhouette) or `:high` (richer coastline detail). `Label.text` must be a binary; the color applies as the text foreground. Both shapes raise `ArgumentError` if a required field is missing or mistyped.

### Chart

An x/y line, scatter, or bar chart with axes, labels, legend, and multi-series support. Each `%Dataset{}` carries a list of `{x, y}` tuples (integers or floats) plus its own `:marker`, `:graph_type`, and `:style`. The required `:x_axis` and `:y_axis` configure the visible coordinate range via `{min, max}` `:bounds` and optional tick `:labels`. Pass `nil` as `:legend_position` to hide the legend entirely.

```elixir
alias ExRatatui.Widgets.Chart
alias ExRatatui.Widgets.Chart.{Axis, Dataset}

%Chart{
  datasets: [
    %Dataset{
      name: "CPU",
      data: [{0.0, 12.0}, {1.0, 25.0}, {2.0, 48.0}, {3.0, 31.0}, {4.0, 19.0}],
      marker: :braille,                        # or :dot, :block, :bar, :half_block
      graph_type: :line,                       # or :scatter, :bar
      style: %Style{fg: :cyan}
    },
    %Dataset{
      name: "Memory",
      data: [{0.0, 40.0}, {1.0, 42.0}, {2.0, 55.0}, {3.0, 60.0}, {4.0, 58.0}],
      marker: :dot,
      style: %Style{fg: :magenta}
    }
  ],
  x_axis: %Axis{
    title: "Time (s)",
    bounds: {0.0, 4.0},
    labels: ["0", "2", "4"],
    style: %Style{fg: :dark_gray}
  },
  y_axis: %Axis{
    title: "Usage %",
    bounds: {0.0, 100.0},
    labels: ["0", "50", "100"],
    style: %Style{fg: :dark_gray}
  },
  legend_position: :top_right,                 # or :top, :top_left, :bottom, :bottom_left,
                                               # :bottom_right, :left, :right, or nil to hide
  hidden_legend_constraints: {{:ratio, 1, 4}, {:ratio, 1, 4}},
  block: %Block{title: " Metrics ", borders: [:all]}
}
```

`:hidden_legend_constraints` takes a `{width_constraint, height_constraint}` tuple — the same shapes accepted by `ExRatatui.Layout` (`:length`, `:percentage`, `:ratio`, `:min`, `:max`, `:fill`). The legend is hidden whenever its rendered size would exceed those bounds against the chart area, which keeps things readable in cramped layouts. Each dataset's `:graph_type` is independent: combine a `:line` series with a `:scatter` overlay in the same chart for emphasis.

Datasets with non-tuple data points, non-numeric coordinates, unknown markers, unknown `:graph_type`s, unknown `:legend_position`s, missing axes, malformed `:bounds`, malformed `:hidden_legend_constraints`, and unknown `:labels_alignment` values raise `ArgumentError` at the bridge boundary.

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

### CodeBlock

Renders syntax-highlighted source code as a display-only widget, powered by [syntect](https://github.com/trishume/syntect)'s bundled `SyntaxSet` and `ThemeSet`. Unlike `Markdown` — which wraps code inside a larger document — `CodeBlock` is the right pick when the whole widget is the snippet: a `:q`-style help popup, a diff viewer, a REPL transcript pane.

```elixir
%ExRatatui.Widgets.CodeBlock{
  content: """
  defmodule Counter do
    def inc(n), do: n + 1
  end
  """,
  language: "elixir",                          # nil = plain text fallback
  theme: :base16_ocean_dark,
  line_numbers: true,
  starting_line: 1,
  highlight_lines: [2, 5..7],                  # ints + ranges, normalised
  block: %Block{title: " counter.ex ", borders: [:all]}
}
```

Themes accept seven curated atoms — `:base16_ocean_dark`, `:base16_ocean_light`, `:base16_eighties_dark`, `:base16_mocha_dark`, `:inspired_github`, `:solarized_dark`, `:solarized_light` — or any raw string for custom theme sets loaded into syntect. Languages accept any syntect token name; we ship Elixir as an additional bundled syntax on top of syntect's defaults (Rust, Python, JS, Ruby, Go, Java, JSON, YAML, Erlang, …). `nil` is a plain-text fallback that skips tokenisation.

`:line_numbers` turns on a right-aligned dim gutter with a `│` separator; the gutter width grows with the last visible line. `:highlight_lines` accepts a mixed list of ints and ranges (`[3, 7..9]`); the widget normalises that to a sorted unique line set and renders each emphasised line with a theme-derived background (lightened for dark themes, darkened for light themes).

For composite widgets — a diff viewer that paints `+`/`-` gutters, an inspector that interleaves source and AST — reach for the raw helper instead:

```elixir
ExRatatui.CodeBlock.highlight("fn main() {}", "rust", :solarized_dark)
# => [%ExRatatui.Text.Line{spans: [%Span{}, ...]}, ...]
```

`highlight/3` returns the same `[%Line{}]` shape the widget uses internally, so you can drop it into a `Paragraph` or compose it with your own gutter / annotations without re-implementing syntect translation. The call is NIF-backed, runs on a `DirtyCpu` scheduler, and emits a `[:ex_ratatui, :code_block, :highlight]` telemetry span — see the [Telemetry guide](../internals/telemetry.md) for the metadata shape.

See `examples/widgets/code_block.exs` to cycle through every theme / language / gutter combination interactively.

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

See [`examples/apps/chat.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/apps/chat.exs) for a full integration.

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

`Theme` is intentionally Layer A: pure data with three helpers. A later Layer B may add opt-in auto-injection (Block borders pick up `theme.border` unless overridden, etc.); Layer A stays explicit.

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
