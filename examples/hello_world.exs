# Example: renders a paragraph and waits for any key to exit.
# Run with: mix run examples/hello_world.exs

alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph}

defmodule HelloWorld do
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
    case ExRatatui.poll_event(5000) do
      nil -> wait_for_key()
      _ -> :ok
    end
  end
end

HelloWorld.run()
