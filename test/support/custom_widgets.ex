defmodule ExRatatui.Test.CustomWidgets do
  @moduledoc false

  defmodule Greeting do
    @moduledoc false
    defstruct [:name]

    defimpl ExRatatui.Widget do
      def render(%{name: name}, rect) do
        [{%ExRatatui.Widgets.Paragraph{text: "Hello, #{name}!"}, rect}]
      end
    end
  end

  defmodule TitledBox do
    @moduledoc false
    defstruct [:title, :body]

    defimpl ExRatatui.Widget do
      alias ExRatatui.Layout
      alias ExRatatui.Widgets.{Block, Paragraph}

      def render(%{title: title, body: body}, rect) do
        [inner] = Layout.split(rect, :vertical, [{:min, 0}])

        body_rect = %{
          inner
          | x: inner.x + 1,
            y: inner.y + 1,
            width: inner.width - 2,
            height: inner.height - 2
        }

        [
          {%Block{title: title, borders: [:all]}, rect},
          {%Paragraph{text: body}, body_rect}
        ]
      end
    end
  end

  defmodule Stacked do
    @moduledoc false
    # Returns another custom widget plus a primitive — exercises
    # recursive expansion end-to-end.
    defstruct [:top_name, :bottom_text]

    defimpl ExRatatui.Widget do
      alias ExRatatui.Layout
      alias ExRatatui.Test.CustomWidgets.Greeting
      alias ExRatatui.Widgets.Paragraph

      def render(%{top_name: name, bottom_text: text}, rect) do
        [top, bottom] =
          Layout.split(rect, :vertical, [{:percentage, 50}, {:percentage, 50}])

        [
          {%Greeting{name: name}, top},
          {%Paragraph{text: text}, bottom}
        ]
      end
    end
  end
end
