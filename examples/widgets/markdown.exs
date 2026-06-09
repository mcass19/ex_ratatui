# Example: Markdown — render a Markdown document with syntax-highlighted code.
# Run with: mix run examples/widgets/markdown.exs
#
# Controls: Up/Down = scroll, q = quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Markdown, Paragraph}

defmodule MarkdownDemo do
  use ExRatatui.App

  @doc_content """
  # ExRatatui Markdown

  The `Markdown` widget renders **bold**, *italic*, `inline code`, lists,
  tables, and fenced code blocks with syntax highlighting.

  ## Lists

  - First item
  - Second item
    - Nested item
  - Third item

  ## A table

  | Widget    | Purpose              |
  |-----------|----------------------|
  | Paragraph | styled text          |
  | Table     | tabular data         |
  | Markdown  | rich formatted text  |

  ## Code

  ```elixir
  defmodule Greeter do
    def hello(name), do: "Hello, \#{name}!"
  end
  ```

  > Scroll with Up/Down to see the rest.
  """

  @impl true
  def mount(_opts), do: {:ok, %{scroll: 0}}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [doc_area, help_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 3}])

    markdown = %Markdown{
      content: @doc_content,
      wrap: true,
      scroll: {state.scroll, 0},
      block: %Block{
        title: " Markdown ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan}
      }
    }

    help = %Paragraph{
      text: "  Up/Down = scroll   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    [{markdown, doc_area}, {help, help_area}]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["down", "j"] do
    {:noreply, %{state | scroll: state.scroll + 1}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["up", "k"] do
    {:noreply, %{state | scroll: max(0, state.scroll - 1)}}
  end

  def handle_event(_event, state), do: {:noreply, state}
end

{:ok, pid} = MarkdownDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
