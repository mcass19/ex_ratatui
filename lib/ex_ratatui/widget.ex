defprotocol ExRatatui.Widget do
  @moduledoc """
  Protocol for user-defined widgets that compose ExRatatui primitives.

  Implement this protocol on your own struct to build custom widgets in
  pure Elixir — no Rust required. `render/2` receives the widget struct
  and the `%ExRatatui.Layout.Rect{}` it should occupy, and returns a
  list of placed children. Children may be primitives
  (`%ExRatatui.Widgets.Paragraph{}`, `%ExRatatui.Widgets.Block{}`, …)
  or other custom widgets — the render tree is expanded recursively
  before crossing the NIF boundary.

  The protocol is intentionally minimal and stateless: the struct
  carries all data the render needs. State that evolves over time
  (keyboard focus, selection, input buffers) lives in your
  `ExRatatui.App` / `ExRatatui.Session` model and is projected onto a
  fresh struct each frame.

  ## Example

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

  Then draw it like any other widget:

      ExRatatui.draw(terminal, [{%MyApp.Widgets.UserCard{user: u}, rect}])

  ## Composition

  A custom widget can return another custom widget in its children
  list. The expander walks recursively until every entry is a
  primitive, with a safety cap of 32 nesting levels.

  ## Limitations

  Custom widgets are expanded at the top level of
  `ExRatatui.draw/2`'s widget list. They are not currently supported
  inside `ExRatatui.Widgets.Popup`'s `:content` field or
  `ExRatatui.Widgets.WidgetList`'s `:items` — those fields still
  require primitive widgets. A custom widget can itself *return* a
  `%Popup{}` or `%WidgetList{}`; the restriction only applies to the
  widgets placed *inside* them.
  """

  @type rendered :: {ExRatatui.widget(), ExRatatui.Layout.Rect.t()}

  @doc """
  Renders this widget at the given rect into a list of placed children.

  Children may be primitive widgets or other structs implementing
  `ExRatatui.Widget`. Return `[]` to render nothing.
  """
  @spec render(t(), ExRatatui.Layout.Rect.t()) :: [rendered()]
  def render(widget, rect)
end
