# Custom Widgets

The `ExRatatui.Widget` protocol lets you build composite widgets in pure Elixir without touching Rust. A custom widget is just a struct you own plus a `defimpl` that projects it onto primitive widgets — `%Paragraph{}`, `%Block{}`, `%List{}`, and friends — positioned inside the rect you're given. The Bridge expands your widget into primitives before crossing the NIF boundary, so `ExRatatui.draw/2` accepts primitive and custom widgets interchangeably at the top level of a frame.

## When to reach for a custom widget

If you find yourself repeating the same Layout.split + a handful of primitives in several screens, that's a custom widget. Typical shapes:

- **Composed cards** — a title bar, body, and status line that always render together
- **Domain-named views** — `MessageCard`, `FileRow`, `LogEntry` — where the struct IS the model the renderer projects from
- **Simple wrappers** — "a Block with these defaults and a Paragraph inside"

Stay with inline primitives for one-off layouts. Custom widgets cost a module and a protocol impl — worth it when you'll reuse the shape or name is part of readability.

## The protocol

One callback, stateless, strict return shape:

```elixir
defprotocol ExRatatui.Widget do
  @spec render(t(), ExRatatui.Layout.Rect.t()) ::
          [{ExRatatui.widget(), ExRatatui.Layout.Rect.t()}]
  def render(widget, rect)
end
```

`render/2` receives your struct and the rect it should occupy, and returns a list of `{widget, rect}` tuples placing each child. Order matters: earlier entries are drawn first, later entries on top (the usual z-order).

## A full example

```elixir
defmodule MyApp.Widgets.UserCard do
  defstruct [:user, selected?: false]

  defimpl ExRatatui.Widget do
    alias ExRatatui.Layout
    alias ExRatatui.Layout.Rect
    alias ExRatatui.Style
    alias ExRatatui.Widgets.{Block, Paragraph}

    def render(%{user: user, selected?: sel?}, %Rect{} = rect) do
      border_style = if sel?, do: %Style{fg: :yellow}, else: %Style{}

      [header, body] =
        Layout.split(rect, :vertical, [{:length, 1}, {:min, 0}])

      [
        {%Block{title: user.name, borders: [:all], border_style: border_style}, rect},
        {%Paragraph{text: user.handle, style: %Style{modifiers: [:bold]}}, header},
        {%Paragraph{text: user.bio}, body}
      ]
    end
  end
end
```

You draw it the same way as any primitive:

```elixir
ExRatatui.draw(terminal, [
  {%MyApp.Widgets.UserCard{user: u, selected?: true},
   %Rect{x: 0, y: 0, width: 40, height: 5}}
])
```

## Composition

A custom widget can return *other* custom widgets in its children — the expander keeps walking until every entry is a primitive. This is how you build up: a `Dashboard` that returns two `Panel`s, each of which returns a `TitledBox` containing Paragraph primitives.

```elixir
defmodule MyApp.Widgets.Dashboard do
  defstruct [:left_panel, :right_panel]

  defimpl ExRatatui.Widget do
    alias ExRatatui.Layout

    def render(%{left_panel: l, right_panel: r}, rect) do
      [left, right] =
        Layout.split(rect, :horizontal, [{:percentage, 50}, {:percentage, 50}])

      [{l, left}, {r, right}]
    end
  end
end
```

A safety cap of 32 nesting levels protects against infinite recursion; exceeding it raises `ArgumentError` with the chain of struct names at fault.

## Stateless by design

The protocol has no `init/1` / `update/2` callbacks. State that evolves over time — keyboard focus, selection, input buffers — lives in your `ExRatatui.App` or `ExRatatui.Session` model and is projected onto a fresh struct each frame. Treat the struct as a pure view descriptor, not a mini-actor.

When you need genuinely stateful rendering (like `TextInput` or `Textarea`, whose Rust side owns a buffer), use one of the built-in stateful widgets — the protocol is for composition, not state management.

## Limitations

Custom widgets are expanded at the top level of the list passed to `ExRatatui.draw/2`. They are **not** currently supported inside:

- `ExRatatui.Widgets.Popup`'s `:content` field
- `ExRatatui.Widgets.WidgetList`'s `:items`

Those nested fields still require primitive widgets. The inverse works fine: a custom widget can itself *return* a `%Popup{}` or `%WidgetList{}` in its children. Only the widgets placed *inside* Popup/WidgetList stay primitive for now, because their inner rects are computed Rust-side at render time.

## Pitfalls

- **Returning the wrong rect type** — the second element of each tuple must be a `%ExRatatui.Layout.Rect{}`, not a plain tuple or map. Raises `ArgumentError`.
- **Returning a non-list** — `render/2` must return a list, even for a single child or a no-op (`[]` is valid).
- **Infinite self-recursion** — a widget whose `render/2` returns itself (directly or via a cycle) hits the depth cap above.
- **Expecting rect clipping validation** — children whose rects extend outside the parent are not rejected; ratatui clips at render time.

## Testing

Treat custom widgets like any other widget: draw into a test terminal and assert on the rendered buffer.

```elixir
test "renders greeting" do
  terminal = ExRatatui.init_test_terminal(30, 1)
  rect = %Rect{x: 0, y: 0, width: 30, height: 1}

  :ok = ExRatatui.draw(terminal, [{%Greeting{name: "world"}, rect}])
  assert ExRatatui.get_buffer_content(terminal) =~ "Hello, world!"
end
```

No need to exercise the protocol directly — the full expand-then-encode pipeline is what to cover.

## Related

  * [`examples/widgets/custom_widget.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/widgets/custom_widget.exs) — a runnable composite-widget demo
  * [Building UIs](building_uis.md) — the primitives composites are built from
  * [Testing](../internals/testing.md) — the headless backend used above
